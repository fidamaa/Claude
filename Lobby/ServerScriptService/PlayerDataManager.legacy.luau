--[[
	PlayerDataManager - Sistema ROBUSTO com MockDataStore
	REWORK: agora é a ÚNICA fonte de persistência do jogador.

	Antes existiam 3 DataStores separados pro mesmo jogador
	(PlayerCharacterData_V4 aqui, PlayerMoneyData_V1 no MoneyManager,
	UsedCodes_V1 no CodeRedeemServer) — cada saída/autosave/fechamento
	do server disparava 3 chamadas de rede independentes, cada uma com
	seu próprio retry e seu próprio game:BindToClose com espera FIXA
	(task.wait(5) aqui, task.wait(5) no Money, task.wait(3) no Codes) —
	era isso que segurava o Studio fechando mesmo depois do salvamento
	já ter terminado de verdade.

	Agora: 1 DataStore, 1 chave por jogador, 1 SetAsync por salvamento
	(Personagens + Dinheiro + Códigos usados no mesmo payload). Money.lua
	e CodeRedeemServer.lua não tocam mais em DataStore — só leem/escrevem
	nos campos Money/UsedCodes desta mesma tabela em memória, e chamam
	_G.SavePlayerData quando precisam persistir na hora.

	O BindToClose espera só o que está pendente de verdade (contador),
	com teto curto (SHUTDOWN_WAIT_TIMEOUT) em vez de dormir um tempo fixo
	sempre — se o salvamento já terminou, o server fecha na hora.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local RESET_ALL_DATA_ON_JOIN = false

-- ⚠️ NOVO: PEDIDO — "reinicie o personagem de todo mundo, pra aplicar as
-- mudanças recentes, reinicie tudo, dinheiro, codes, slots, missões,
-- qualquer informação que tenha". Diferente de RESET_ALL_DATA_ON_JOIN
-- (que apaga SEMPRE que alguém entra, enquanto ficar true — perigoso de
-- esquecer ligado), isso aqui é um reset de UMA VEZ SÓ por jogador: cada
-- save carrega consigo o número de "WipeVersion" com que foi criado; se
-- o valor salvo for menor que FORCE_WIPE_VERSION (ou não existir, dado
-- bem antigo), os dados são descartados por completo (dinheiro, códigos
-- usados, slots de personagem, missões, cosméticos, boosts, pulsos/
-- instintos sorteados — TUDO) e um personagem novo em folha é criado, já
-- carimbado com a versão atual — então essa pessoa nunca mais é resetada
-- de novo à toa. Pra forçar outro reset geral no futuro (outra mudança
-- que quebre compatibilidade), basta subir esse número de novo.
local FORCE_WIPE_VERSION = 2
-- MELHORIA DE SAVE: autosave de "rede de segurança" descia de 120s pra
-- 30s — não é mais o principal jeito de salvar (isso agora é
-- _G.RequestSave, ver abaixo), só o backup pra qualquer mudança que por
-- algum motivo não tenha passado por ele.
local AUTOSAVE_INTERVAL = 30
local MAX_RETRY_ATTEMPTS = 5
local RETRY_DELAY = 3
local USE_MOCK_DATASTORE = false

-- Salvamento durante o fechamento do server: menos tentativas, delay
-- curto e fixo (não exponencial) — o objetivo aqui é não perder dado,
-- não esgotar retry como se fosse um autosave qualquer.
local SHUTDOWN_MAX_RETRY_ATTEMPTS = 2
local SHUTDOWN_RETRY_DELAY = 0.5
local SHUTDOWN_WAIT_TIMEOUT = 4 -- teto de espera no BindToClose, não um tempo fixo garantido

-- ⚠️ REMOVIDO (pedido do usuário: "remove o sistema de elemento do jogo,
-- não terá utilidade pra ele") — Element (Forest/Wind/Fire/Mountain/Void/
-- Light) era só um rótulo cosmético sorteado por personagem, sem NENHUM
-- efeito de gameplay (nunca era lido no place Game). Removido de
-- CharacterCreator.new, validateCharacterSlot, do snapshot de
-- teleporte (Matchmaker/MatchDataTransfer) e da UI (CharacterClient).
-- Dado salvo antigo que ainda tiver Element não quebra nada — o campo
-- simplesmente é ignorado agora.
-- ⚠️ v10 — PEDIDO: "remova a opção de selecionar role no lobby [DF/MF/FW]...
-- apenas ao goleiro, como a checkbox pedida". DF/MF/FW saíram de vez da
-- escolha manual — a posição de linha agora é sugerida no matchmaking a
-- partir dos Pulsos equipados (ver derivePreferredRole em MatchDataTransfer.
-- legacy.luau). Só sobra uma escolha binária por slot: "GK" (quer ser
-- goleiro) ou "LINE" (não quer — deixa o Pulso sugerir a posição). "LINE"
-- é só um marcador INTERNO do Lobby — nunca é enviado pro Game como Role
-- de verdade (ver derivePreferredRole, que sempre recalcula a partir dos
-- Pulsos quando não é "GK").
local ROLES = {"GK", "LINE"}

local DEFAULT_STARTING_MONEY = 1000

-- FIX: os atributos do roster agora são os MESMOS que o jogo de futebol
-- de verdade lê (ver FootballConfig.lua no place Game: DRIBBLE_SKILL_-
-- ATTRIBUTE, PHYSICAL_ATTRIBUTE, SPEED_ATTRIBUTE, KICK_ATTRIBUTE — todos
-- 0-100, default 50) — antes o roster guardava "Kick"/"Dribble" (nomes
-- antigos, sem relação com o Kick de hoje) que não batiam com nada usado
-- em campo.
--
-- REWORK (atributos que fazem sentido):
-- - "Aura" foi REMOVIDO (era reservado pra uma habilidade ativa que
--   nunca saiu do papel).
-- - "BallControl" foi REMOVIDO — o controle de bola em curva rápida
--   virou parte do DribbleSkill (drible é um atributo só).
-- - "CrossingSkill" foi REMOVIDO — não fazia sentido separado de Chute.
-- - Entram "Speed" (velocidade de corrida/sprint) e "Kick" (força do
--   chute e quem cobra escanteio) no lugar dos dois acima.
-- migrateAttributeNames devolve como AttributePoints livres qualquer
-- ponto que o jogador já tinha investido nos atributos removidos, pra
-- ninguém perder progresso com a limpeza (ver validateCharacterSlot).
--
-- Duas escalas diferentes convivem aqui:
-- - SKILL_MIN/MAX: Physical, DribbleSkill, Speed, Kick — 0-100 na
--   leitura do jogo (GetAttribute(...)/100 ou multiplicador direto),
--   por isso nascem perto do default de 50 do jogo.
-- - POOL_MIN/MAX: Stamina — NÃO é porcentagem, é um multiplicador
--   pequeno (ver Config.STAMINA_PER_ATTRIBUTE_POINT no Game: MaxStamina
--   = 50 + Stamina*10), por isso fica numa escala bem menor. Achatar os
--   dois na mesma faixa faria Stamina virar MaxStamina gigante
--   (Stamina=100 → MaxStamina=1050).
local SKILL_MIN_BASE_STAT = 10
local SKILL_MAX_BASE_STAT = 40
local POOL_MIN_BASE_STAT = 5
local POOL_MAX_BASE_STAT = 15
-- ⚠️ NOVO: "Energy" entra como 5º atributo de skill (mesma escala 0-100
-- de Physical/DribbleSkill/Speed/Kick) — alimenta o sistema de Pulsos
-- (hissatsus: Energy+Kick pro chute especial, Energy+Physical pro
-- goleiro, ver conversa de balanceamento). Por já estar na lista de
-- SKILL_ATTRIBUTE_NAMES, migrateAttributeNames (abaixo) preenche
-- sozinho quem já tinha personagem salvo sem Energy.
local SKILL_ATTRIBUTE_NAMES = { "Physical", "DribbleSkill", "Speed", "Kick", "Energy" }
local POOL_ATTRIBUTE_NAMES = { "Stamina" }
-- Atributos removidos do jogo (nomes antigos) cujos pontos investidos
-- viram AttributePoints livres na migração — ver migrateAttributeNames.
-- Cada um tem sua própria linha de base (Aura nascia na faixa POOL,
-- BallControl/CrossingSkill nasciam na faixa SKILL — usar a base errada
-- faria o refund sair sempre 0 ou exagerado).
local REMOVED_ATTRIBUTE_BASELINES = {
	Aura = POOL_MIN_BASE_STAT,
	BallControl = SKILL_MIN_BASE_STAT,
	CrossingSkill = SKILL_MIN_BASE_STAT,
}

-- ========================================
-- REWORK: os 4 atributos de skill (Physical/DribbleSkill/Speed/Kick) NÃO
-- nascem mais todos IGUAIS a partir de uma única "Sorte" — era esse o bug
-- reportado (personagem saindo com o mesmo número cravado em tudo, tipo
-- 62/62/62/62, só Stamina saindo diferente porque já era rolada à parte).
-- Agora CADA UM sorteia seu PRÓPRIO número, de forma totalmente
-- independente, tipo: físico 16, drible 25, força 10, velocidade 33.
--
-- Faixa também foi reduzida (era 35-65): pior caso agora é 10 em tudo,
-- melhor caso é 40 em tudo (SKILL_MIN/MAX_BASE_STAT acima).
--
-- "Sorte" (Luck) continua existindo só pra exibir as estrelas (1-5) na
-- tela de slots — não decide mais o valor dos atributos, é calculada
-- DEPOIS, como a média dos 4 valores sorteados, normalizada pra 0-100.
--
-- CONTA DE NÍVEL MÁXIMO (ver LevelManager.lua — ATTRIBUTE_POINTS_PER_-
-- LEVEL foi de 3 pra 4 exatamente por causa dessa conta, mantenha os dois
-- arquivos em sincronia se mudar MAX_LEVEL/ATTRIBUTE_POINTS_PER_LEVEL):
-- ⚠️ ATUALIZADO: ATTRIBUTE_POINTS_PER_LEVEL agora é 3 (era 4) — pedido
-- do usuário, já que 100 é o teto de qualquer atributo. Conta abaixo
-- ficou desatualizada (ainda calcula em cima de 4/nível); pool real
-- agora = 3 * 49 = 147 pontos.
--   pool total = 4 pontos/nível * 49 níveis (1→50) = 196 pontos
--   custo pra maxar 1 atributo (teto 100) = 100 - valorInicial
-- MELHOR CASO (os 4 nascem em 40): custo por atributo = 60 → 196/60 = dá
-- pra maxar 3 atributos inteiros (180 pontos) e ainda sobram 16 pontos
-- soltos — bate com o pedido ("dá pra upar 100% de 3 status").
-- PIOR CASO (os 4 nascem em 10): custo por atributo = 90 → 196/90 = só
-- dá pra maxar 2 atributos inteiros (sobra 16).
--
-- ⚠️ NOVO: essa conta foi feita com 4 atributos de skill (Physical/
-- DribbleSkill/Speed/Kick) — agora com Energy entrando como 5º
-- (SKILL_ATTRIBUTE_NAMES acima), o mesmo pool de 196 pontos se espalha
-- por mais um atributo concorrendo: melhor caso vira "maxar 2 inteiros +
-- sobra parcial" em vez de 3. Se quiser preservar a conta original
-- ("maxar 3 de 5"), é só subir ATTRIBUTE_POINTS_PER_LEVEL (LevelManager)
-- proporcionalmente — não mexi nisso agora, só documentando o efeito.
local function rollSkillStat()
	return math.random(SKILL_MIN_BASE_STAT, SKILL_MAX_BASE_STAT)
end

-- Sorte 0-100 só pra exibição (estrelas) — média dos 5 atributos
-- sorteados (⚠️ agora incluindo Energy), remapeada de
-- [SKILL_MIN_BASE_STAT, SKILL_MAX_BASE_STAT] pra [0, 100].
local function luckFromAttributes(physical, dribble, speed, kick, energy)
	local avg = (physical + dribble + speed + kick + energy) / 5
	local span = SKILL_MAX_BASE_STAT - SKILL_MIN_BASE_STAT
	if span <= 0 then return 50 end
	return math.clamp(math.floor(((avg - SKILL_MIN_BASE_STAT) / span) * 100), 0, 100)
end

-- Usado só na MIGRAÇÃO de slots antigos que nunca tiveram Luck salvo
-- (ver validateCharacterSlot abaixo) — não influencia mais os atributos,
-- é só pra ter algum número pras estrelas aparecerem.
local function rollLuck()
	return math.random(0, 100)
end

-- Sorte (0-100) → estrelas (1-5), pra exibir na tela de slots.
local function luckToStars(luck)
	return math.clamp(math.ceil((luck or 0) / 20), 1, 5)
end
_G.LuckToStars = luckToStars

-- ========================================
-- Mock DataStore para Studio
-- ========================================
local MockDataStore = {}
MockDataStore.__index = MockDataStore
MockDataStore.data = {}

function MockDataStore:GetAsync(key)
	print("📦 MockDataStore: GetAsync(" .. key .. ")")
	return self.data[key]
end

function MockDataStore:SetAsync(key, value)
	print("📦 MockDataStore: SetAsync(" .. key .. ")")
	self.data[key] = value
end

function MockDataStore:RemoveAsync(key)
	print("📦 MockDataStore: RemoveAsync(" .. key .. ")")
	self.data[key] = nil
end

-- ========================================
-- DataStore ÚNICO (Personagens + Dinheiro + Códigos usados)
-- ========================================
local playerDataStore

if USE_MOCK_DATASTORE then
	print("⚠️ Usando MockDataStore (dados em memória) - apenas para Studio")
	playerDataStore = setmetatable({}, MockDataStore)
else
	playerDataStore = DataStoreService:GetDataStore("PlayerSaveData_V1") -- V1 do formato UNIFICADO (Character+Money+Codes)
end

-- Handles de LEITURA (só leitura, uma vez, pra migração) dos DataStores
-- antigos separados — nunca mais escrevemos neles depois da migração.
local legacyCharacterStore, legacyMoneyStore, legacyCodesStore
if not USE_MOCK_DATASTORE then
	legacyCharacterStore = DataStoreService:GetDataStore("PlayerCharacterData_V4")
	legacyMoneyStore = DataStoreService:GetDataStore("PlayerMoneyData_V1")
	legacyCodesStore = DataStoreService:GetDataStore("UsedCodes_V1")
end

-- Cache de dados online
local onlinePlayersData = {}

-- ========================================
-- Contador de salvamentos pendentes (usado pelo BindToClose pra
-- esperar só o necessário, em vez de um tempo fixo às cegas)
-- ========================================
local pendingSaves = 0

local function beginPendingSave()
	pendingSaves += 1
end

local function endPendingSave()
	pendingSaves = math.max(0, pendingSaves - 1)
end

-- Espera até não haver mais salvamentos pendentes, ou até o timeout —
-- o que vier primeiro. Se tudo já terminou, retorna quase na hora.
_G.WaitForPendingSaves = function(timeoutSeconds)
	local start = os.clock()
	while pendingSaves > 0 and (os.clock() - start) < timeoutSeconds do
		task.wait(0.1)
	end
end

-- ========================================
-- Criador de Personagens (ATUALIZADO COM NÍVEIS)
-- ========================================
local CharacterCreator = {}

-- ELEMENTOS (reinserido a pedido do usuário, ver Config.ELEMENTS em
-- LobbyConfig.luau — a lista TEM que ficar idêntica à do
-- Config.ELEMENTS do FootballConfig.lua, place Game): sorteado uma vez
-- na criação do slot, pode ser trocado depois com o "Token de Elemento"
-- da Loja (ver ShopServer.legacy.luau, Effect="RerollElement").
local function rollElement()
	-- Void e Luz são raros (0.1% cada) — a matemática do sorteio mora
	-- SÓ em LobbyConfig.RollElement() (evita duplicar/dessincronizar,
	-- ver mesma função usada no reroll da Loja em ShopServer.legacy.luau).
	return LobbyConfig.RollElement()
end

function CharacterCreator.new(slotName, role)
	-- Cada atributo de skill sorteia seu PRÓPRIO número, independente dos
	-- outros (ver nota acima) — não nasce mais tudo igual.
	local physical = rollSkillStat()
	local dribble = rollSkillStat()
	local speed = rollSkillStat()
	local kick = rollSkillStat()
	local energy = rollSkillStat() -- ⚠️ NOVO: alimenta o sistema de Pulsos
	local stamina = math.random(POOL_MIN_BASE_STAT, POOL_MAX_BASE_STAT)
	local luck = luckFromAttributes(physical, dribble, speed, kick, energy)

	return {
		SlotName = slotName,
		Role = role,

		-- ⚠️ NOVO: elemento sorteado na criação (Natureza/Fogo/Vento/Luz/
		-- Void) — afeta Pulsos do mesmo elemento (+10% de potência, ver
		-- Config.PULSE_ELEMENT_SELF_MATCH_MULT no Game) e a vantagem entre
		-- elementos (Config.GetElementMultiplier). Pode ser re-rolado com
		-- o Token de Elemento da Loja.
		Element = rollElement(),

		-- ⭐ SORTE: só informativa agora (estrelas 1-5 na UI) — média dos 4
		-- atributos sorteados abaixo, ver luckFromAttributes.
		Luck = luck,

		-- Sistema de Atributos (ver nota de escala acima). Os 4 de skill
		-- agora nascem cada um com seu PRÓPRIO valor independente.
		Attributes = {
			Physical = physical,
			DribbleSkill = dribble,
			Speed = speed,
			Kick = kick,
			Energy = energy, -- ⚠️ NOVO: alimenta o sistema de Pulsos
			Stamina = stamina,
			-- ⚠️ NOVO (fix "fôlego sem teto"): guarda o valor de NASCIMENTO do
			-- Stamina separado do valor atual — LevelManager usa isso pra
			-- travar o teto de investimento em StaminaBase*4 (no máximo
			-- QUADRUPLICA o fôlego inicial, nunca mais que isso, por pedido
			-- explícito: "no nível máximo, no máximo vai triplicar ou
			-- quadruplicar o fôlego inicial"). Sem isso, Stamina não tinha
			-- teto nenhum (ver LevelManager.lua) e um jogador dedicado podia
			-- jogar os 196 pontos do pool inteiro nele (5 → 201, quase 40x).
			StaminaBase = stamina,
		},

		-- Sistema de Hissatsus
		EquippedHissatsus = {nil, nil, nil, nil, nil},
		UnlockedHissatsus = {},
		SkillPoints = 10,

		-- ⭐ SISTEMA DE NÍVEIS
		Level = 1,
		CurrentXP = 0,
		AttributePoints = 0
	}
end

-- ========================================
-- Validar Estrutura de Dados
-- ========================================
-- FIX: migra slots salvos com formatos antigos de atributos pro formato
-- atual (Physical/DribbleSkill/Speed/Kick/Stamina), em vez de invalidar
-- o personagem inteiro. "Dribble" bem antigo vira DribbleSkill (mesmo
-- conceito, só renomeado). Qualquer atributo faltando (Speed/Kick pra
-- quem só tinha BallControl/CrossingSkill, por exemplo) ganha o valor
-- médio da faixa de skill como ponto de partida — os pontos que a
-- pessoa tinha investido nos atributos removidos voltam à parte, como
-- AttributePoints livres (ver REMOVED_ATTRIBUTE_BASELINES abaixo).
local function migrateAttributeNames(attrs)
	if attrs.Dribble and not attrs.DribbleSkill then
		attrs.DribbleSkill = attrs.Dribble
	end
	attrs.Dribble = nil
	-- NOTA: "Kick" chegou a ser zerado aqui numa migração bem antiga (uma
	-- versão anterior desse nome, sem efeito na gameplay, foi descartada
	-- de propósito). "Kick" agora É um atributo de verdade de novo (ver
	-- REWORK acima) — NÃO zerar mais.

	-- Aura/BallControl/CrossingSkill foram removidos do jogo (ver nota
	-- acima). Quem já tinha pontos investidos neles não perde progresso:
	-- a diferença acima do valor base de nascimento volta como
	-- AttributePoints livres pra redistribuir nos atributos atuais.
	local removedRefund = 0
	for attrName, baseline in pairs(REMOVED_ATTRIBUTE_BASELINES) do
		if type(attrs[attrName]) == "number" then
			removedRefund += math.max(0, attrs[attrName] - baseline)
			attrs[attrName] = nil
		end
	end

	local skillDefault = math.floor((SKILL_MIN_BASE_STAT + SKILL_MAX_BASE_STAT) / 2)
	for _, attrName in ipairs(SKILL_ATTRIBUTE_NAMES) do
		if type(attrs[attrName]) ~= "number" then
			attrs[attrName] = skillDefault
		end
	end

	local poolDefault = POOL_MIN_BASE_STAT
	for _, attrName in ipairs(POOL_ATTRIBUTE_NAMES) do
		if type(attrs[attrName]) ~= "number" then
			attrs[attrName] = poolDefault
		end
	end

	-- ⚠️ NOVO (fix "fôlego sem teto"): migração pra personagens salvos ANTES
	-- de StaminaBase existir. Não temos como saber o valor de nascimento
	-- real deles, então damos o benefício da dúvida:
	-- - Se o Stamina atual ainda está dentro da própria faixa de
	--   nascimento (nunca investiu ponto nele), usa o valor atual como
	--   base — é o caso mais comum.
	-- - Senão (já investiu pontos), assume a base mais generosa possível
	--   (POOL_MAX_BASE_STAT) pra não travar de repente quem já vinha
	--   investindo — o teto vira StaminaBase*4 a partir de agora, só
	--   afeta pontos FUTUROS, nunca reduz o que a pessoa já tem.
	if type(attrs.StaminaBase) ~= "number" then
		if type(attrs.Stamina) == "number" and attrs.Stamina <= POOL_MAX_BASE_STAT then
			attrs.StaminaBase = attrs.Stamina
		else
			attrs.StaminaBase = POOL_MAX_BASE_STAT
		end
	end

	return removedRefund
end

local function validateCharacterSlot(slotData)
	if type(slotData) ~= "table" then
		return false
	end

	-- Verificar campos essenciais (Element não é mais exigido — removido)
	if not slotData.SlotName or not slotData.Role then
		return false
	end

	-- Verificar atributos
	if type(slotData.Attributes) ~= "table" then
		return false
	end

	local removedRefund = migrateAttributeNames(slotData.Attributes)
	if removedRefund > 0 then
		slotData.AttributePoints = (slotData.AttributePoints or 0) + removedRefund
		print(string.format("♻️ Migração: devolvidos %d pontos de atributo (Aura/BallControl/CrossingSkill) pro slot '%s'", removedRefund, tostring(slotData.SlotName)))
	end

	-- Migração: personagem criado antes do sistema de Sorte não tem
	-- Luck salvo — sorteia uma vez agora só pra exibir as estrelas
	-- (não mexe retroativamente nos atributos já rolados dele).
	if type(slotData.Luck) ~= "number" then
		slotData.Luck = rollLuck()
	end

	-- Migração: personagem criado antes do elemento voltar (ou de uma
	-- versão salva com o Element antigo/removido) não tem Element válido
	-- — sorteia um agora, mesmo espírito da migração de Luck acima.
	if type(slotData.Element) ~= "string" or not table.find(LobbyConfig.ELEMENTS, slotData.Element) then
		slotData.Element = rollElement()
	end

	local requiredAttrs = {}
	for _, name in ipairs(SKILL_ATTRIBUTE_NAMES) do table.insert(requiredAttrs, name) end
	for _, name in ipairs(POOL_ATTRIBUTE_NAMES) do table.insert(requiredAttrs, name) end

	for _, attr in ipairs(requiredAttrs) do
		if type(slotData.Attributes[attr]) ~= "number" then
			return false
		end
	end

	-- ⭐ Adicionar dados de nível se não existirem (migração de dados antigos)
	if not slotData.Level then
		slotData.Level = 1
		slotData.CurrentXP = 0
		slotData.AttributePoints = 0
	end

	return true
end

local function validatePlayerData(data)
	if type(data) ~= "table" then
		warn("❌ Dados inválidos: não é uma tabela")
		return false
	end

	if type(data.ActiveSlot) ~= "number" or type(data.UnlockedSlots) ~= "number" then
		warn("❌ Dados inválidos: ActiveSlot ou UnlockedSlots incorretos")
		return false
	end

	if type(data.CharacterSlots) ~= "table" then
		warn("❌ Dados inválidos: CharacterSlots não é uma tabela")
		return false
	end

	-- Verificar pelo menos um slot válido
	local hasValidSlot = false
	for i = 1, 5 do
		local slot = data.CharacterSlots[i]
		if slot and slot ~= "Locked" then
			if validateCharacterSlot(slot) then
				hasValidSlot = true
				break
			end
		end
	end

	if not hasValidSlot then
		warn("❌ Dados inválidos: nenhum slot válido encontrado")
		return false
	end

	-- ⚠️ NOVO: garante que qualquer dado que chegue até aqui (já passou do
	-- filtro de reset acima) fique carimbado com a versão atual — defensivo,
	-- pra nunca ficar sem o campo depois de validado.
	if type(data.WipeVersion) ~= "number" then
		data.WipeVersion = FORCE_WIPE_VERSION
	end

	-- REWORK: Money e UsedCodes agora moram nesta mesma tabela (payload
	-- único). Corrige em vez de invalidar tudo — dado velho migrando de
	-- antes do rework nunca vai ter esses campos na primeira leitura.
	if type(data.Money) ~= "number" then
		data.Money = DEFAULT_STARTING_MONEY
	end
	if type(data.UsedCodes) ~= "table" then
		data.UsedCodes = {}
	end
	-- RollCredits: quantos rolls (Pulso/Instinto) o jogador tem guardados
	-- pra gastar na tela de Roll — comprados na Loja com dinheiro ou com
	-- Robux (ver RollServer.lua). Dado antigo nunca vai ter esse campo.
	if type(data.RollCredits) ~= "number" then
		data.RollCredits = 0
	end
	-- ⚠️ NOVO (v3.4): Wins — total de partidas VENCIDAS, pra preferência de
	-- matchmaking por nível ("quem tiver 10 vitórias vai pegar alguém com
	-- 15 bem mais fácil que alguém com 1000" — ver Matchmaker.legacy.luau
	-- no place Lobby). Dado antigo nunca vai ter esse campo.
	if type(data.Wins) ~= "number" then
		data.Wins = 0
	end
	-- ⚠️ NOVO: Quests — missões oferecidas/escolhidas por esse jogador.
	-- Guardado aqui (não num DataStore separado) pra viajar junto no mesmo
	-- save. PeriodId: identifica o período de 12h atual (ver
	-- QuestData.RESET_INTERVAL_SECONDS) — QuestManager.legacy.luau
	-- resorteia Offered/Active/Progress/Completed quando o período muda.
	-- Offered: candidatas sorteadas pro jogador escolher. Active: Ids que
	-- o jogador ESCOLHEU deixar valendo (pedido: "coloque a opção de
	-- escolher a quest") — só essas progridem/pagam. Progress: Id ->
	-- quantidade acumulada. Completed: Id -> true depois que a
	-- recompensa já foi paga (evita pagar 2x). Dado antigo (formato
	-- anterior, com AssignedDate) é ignorado e resorteado do zero.
	if type(data.Quests) ~= "table" or data.Quests.AssignedDate ~= nil then
		data.Quests = { PeriodId = nil, Offered = {}, Active = {}, Progress = {}, Completed = {} }
	else
		if type(data.Quests.Offered) ~= "table" then data.Quests.Offered = {} end
		if type(data.Quests.Active) ~= "table" then data.Quests.Active = {} end
		if type(data.Quests.Progress) ~= "table" then data.Quests.Progress = {} end
		if type(data.Quests.Completed) ~= "table" then data.Quests.Completed = {} end
	end
	-- ⚠️ NOVO: catálogo de cosméticos da Loja (ver Config.SHOP.Items no
	-- LobbyConfig.lua) — OwnedCosmetics: Ids comprados (compra única, não
	-- reduplica). EquippedCosmetics: Type -> Id equipado (um por tipo:
	-- "Aura", "GoalEffect", "Emote", "NameColor", "Tag", "Frame", "Title",
	-- "ChatColor" — ver ShopServer.legacy.luau EquipCosmetic).
	if type(data.OwnedCosmetics) ~= "table" then
		data.OwnedCosmetics = {}
	end
	if type(data.EquippedCosmetics) ~= "table" then
		data.EquippedCosmetics = {}
	end
	-- ⚠️ NOVO: Boosts temporários comprados na Loja (categoria Boosts) —
	-- todos os campos são timestamps (os.time()) de expiração, ou nil se
	-- nunca comprado. LuckRollsRemaining é contador (não timestamp).
	if type(data.Boosts) ~= "table" then
		data.Boosts = {
			MoneyBoostExpiresAt = 0,
			XPBoostExpiresAt = 0,
			ExtraQuestExpiresAt = 0,
			LuckRollsRemaining = 0,
		}
	else
		if type(data.Boosts.MoneyBoostExpiresAt) ~= "number" then data.Boosts.MoneyBoostExpiresAt = 0 end
		if type(data.Boosts.XPBoostExpiresAt) ~= "number" then data.Boosts.XPBoostExpiresAt = 0 end
		if type(data.Boosts.ExtraQuestExpiresAt) ~= "number" then data.Boosts.ExtraQuestExpiresAt = 0 end
		if type(data.Boosts.LuckRollsRemaining) ~= "number" then data.Boosts.LuckRollsRemaining = 0 end
	end
	-- OwnedPulses/OwnedInstincts: tudo que já saiu no Roll (histórico,
	-- pra uma futura tela de troca de equipado). EquippedPulse/
	-- EquippedInstinct: o que vai pra partida (auto-equipa o mais
	-- recente sorteado de cada tipo — ver RollServer.lua). Dado antigo
	-- nunca vai ter esses campos.
	if type(data.OwnedPulses) ~= "table" then
		data.OwnedPulses = {}
	end
	if type(data.OwnedInstincts) ~= "table" then
		data.OwnedInstincts = {}
	end
	-- ⚠️ v76 — 2 SLOTS DE GRAÇA + 1 COMPRADO COM ROBUX, PRA HISSATSU *E*
	-- PRA ARMA. PEDIDO: "inclua DOIS slot pra arma, e pra hissatsu...
	-- pro player intercalar entre os dois pra trocar. E inclua mais um
	-- slot pra cada um que será comprado com robux."
	--
	-- Hissatsu (Pulse): a tecla "1"/"2" no place Game já sabe escolher
	-- qual slot usar (HissatsuInput.local.luau) — só nunca tinha um
	-- slot 2 de verdade pra usar, porque a v5 simplificou pra 1 só. Volta
	-- a ter 2, e ganha um 3º condicional.
	-- Arma (Instinct): sempre foi 1 campo só (EquippedInstinct). Vira 3
	-- também — como Instinto é PASSIVO (condição bate sozinha, sem
	-- tecla pra escolher qual), os equipados TODOS ficam checados ao
	-- mesmo tempo (ver InstinctController.legacy.luau no place Game).
	for _, campo in ipairs({ "EquippedPulse1", "EquippedPulse2", "EquippedPulse3", "EquippedInstinct1", "EquippedInstinct2", "EquippedInstinct3" }) do
		if data[campo] ~= nil and type(data[campo]) ~= "string" then
			data[campo] = nil
		end
	end
	-- Migração: dado antigo (antes dos 2 slots) tinha só EquippedPulse.
	if type(data.EquippedPulse) == "string" and data.EquippedPulse1 == nil then
		data.EquippedPulse1 = data.EquippedPulse
	end
	data.EquippedPulse = nil
	-- Migração: dado ainda mais antigo tinha só EquippedInstinct (1 campo
	-- só, sem número) — vira o slot 1.
	if type(data.EquippedInstinct) == "string" and data.EquippedInstinct1 == nil then
		data.EquippedInstinct1 = data.EquippedInstinct
	end
	data.EquippedInstinct = nil

	-- Slots extras comprados com Robux (Developer Product — ver
	-- Config.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID/ROBUX_EXTRA_INSTINCT_SLOT_
	-- PRODUCT_ID no LobbyConfig.lua e ProcessReceipt em RollServer.lua).
	if type(data.ExtraPulseSlot) ~= "boolean" then data.ExtraPulseSlot = false end
	if type(data.ExtraInstinctSlot) ~= "boolean" then data.ExtraInstinctSlot = false end

	if type(data.RollCreditsRobux) ~= "number" then data.RollCreditsRobux = 0 end

	-- ⚠️ v79 — PEDIDO: "saí e entrei de novo, e computou as mesmas
	-- recompensas de partida de novo" (dinheiro/XP/missões duplicados).
	-- Ver LobbyRewardsReceiver.legacy.luau — guarda o SavedAt (timestamp)
	-- da última recompensa de partida realmente aplicada, persistido aqui
	-- (sobrevive a reconexões, ao contrário do "processedRewards" que era
	-- só em memória e zerava a cada sessão).
	if type(data.LastRewardClaimedAt) ~= "number" then data.LastRewardClaimedAt = 0 end

	return true
end

-- ========================================
-- Criar Dados Padrão
-- ========================================
-- REWORK (Loja): só nasce com 1 slot destravado — os outros 4 se
-- compram na loja um de cada vez (ver Config.SHOP.UnlockSlot no
-- LobbyConfig.lua do Lobby, e ShopServer.lua que consome
-- _G.CreateRandomCharacterSlot abaixo). Antes nascia com 3 de graça.
local function createDefaultData()
	local newData = {
		WipeVersion = FORCE_WIPE_VERSION, -- ⚠️ NOVO: carimba a versão atual, pra não ser resetado de novo à toa
		ActiveSlot = 1,
		UnlockedSlots = 1,
		CharacterSlots = {
			[1] = nil,
			[2] = "Locked",
			[3] = "Locked",
			[4] = "Locked",
			[5] = "Locked"
		},
		Money = DEFAULT_STARTING_MONEY,
		UsedCodes = {},
		RollCredits = 0,
		Wins = 0,
		Quests = { PeriodId = nil, Offered = {}, Active = {}, Progress = {}, Completed = {} },
		OwnedCosmetics = {},
		EquippedCosmetics = {},
		Boosts = {
			MoneyBoostExpiresAt = 0,
			XPBoostExpiresAt = 0,
			ExtraQuestExpiresAt = 0,
			LuckRollsRemaining = 0,
		},
		OwnedPulses = {},
		OwnedInstincts = {},
		EquippedPulse1 = nil,
		EquippedPulse2 = nil,
		EquippedPulse3 = nil,
		EquippedInstinct1 = nil,
		EquippedInstinct2 = nil,
		EquippedInstinct3 = nil,
		ExtraPulseSlot = false,
		ExtraInstinctSlot = false,
		RollCreditsRobux = 0,
		LastRewardClaimedAt = 0,
	}

	-- ⚠️ v10: nasce SEM pedir goleiro (não é mais sorteado entre as 4
	-- posições — GK precisa ser escolha deliberada via checkbox, nunca
	-- acidente de sorte). Ver ROLES acima.
	newData.CharacterSlots[1] = CharacterCreator.new("Personagem 1", "LINE")

	print("✅ Dados padrão criados com 1 personagem (com sistema de níveis) — demais slots via Loja")
	return newData
end

-- ========================================
-- 🆕 Criar personagem aleatório (usado pela Loja: destravar slot novo
-- ou reiniciar um slot existente) — mesma lógica do createDefaultData,
-- só que reutilizável de fora deste arquivo.
-- ========================================
_G.CreateRandomCharacterSlot = function(slotName)
	-- ⚠️ v10: mesma coisa — nasce sempre "LINE" (ver createDefaultData acima).
	return CharacterCreator.new(slotName, "LINE")
end

-- ========================================
-- MIGRAÇÃO ÚNICA dos 3 DataStores antigos separados, pra quem já
-- jogava antes do rework — best-effort: se qualquer parte falhar, cai
-- de volta pros dados padrão daquela parte, nunca trava o load.
-- ========================================
local function migrateFromLegacyStores(userId)
	if USE_MOCK_DATASTORE then return nil end

	local okChar, legacyChar = pcall(function()
		return legacyCharacterStore:GetAsync("User_" .. userId)
	end)
	if not okChar or type(legacyChar) ~= "table" then
		return nil -- sem personagem antigo, nem vale a pena migrar dinheiro/códigos soltos
	end

	print(string.format("♻️ Migrando dados antigos (3 DataStores separados) pro formato unificado (UserId %d)...", userId))

	local okMoney, legacyMoney = pcall(function()
		return legacyMoneyStore:GetAsync("Money_" .. userId)
	end)
	local okCodes, legacyCodes = pcall(function()
		return legacyCodesStore:GetAsync("Codes_" .. userId)
	end)

	legacyChar.Money = (okMoney and type(legacyMoney) == "number") and legacyMoney or DEFAULT_STARTING_MONEY
	legacyChar.UsedCodes = (okCodes and type(legacyCodes) == "table") and legacyCodes or {}

	return legacyChar
end

-- ========================================
-- Salvar Dados com Retry e Exponential Backoff
-- ========================================
local function savePlayerData(player, isShutdown)
	local userId = player.UserId

	if not onlinePlayersData[userId] then
		warn("⚠️ Tentando salvar dados inexistentes para", player.Name)
		return false
	end

	-- Validar antes de salvar
	if not validatePlayerData(onlinePlayersData[userId]) then
		warn("❌ Não salvando dados corrompidos para", player.Name)
		return false
	end

	local maxAttempts = isShutdown and SHUTDOWN_MAX_RETRY_ATTEMPTS or MAX_RETRY_ATTEMPTS
	local baseDelay = isShutdown and SHUTDOWN_RETRY_DELAY or RETRY_DELAY

	beginPendingSave()

	for attempt = 1, maxAttempts do
		local success, err = pcall(function()
			playerDataStore:SetAsync("User_" .. userId, onlinePlayersData[userId])
		end)

		if success then
			print(string.format("💾 Dados salvos para %s (tentativa %d)%s", player.Name, attempt, isShutdown and " [shutdown]" or ""))
			endPendingSave()
			return true
		else
			local errorMsg = tostring(err)

			if string.find(errorMsg, "500") or string.find(errorMsg, "Internal Server Error") then
				warn(string.format("⚠️ HTTP 500 detectado para %s (tentativa %d/%d)",
					player.Name, attempt, maxAttempts))
			else
				warn(string.format("❌ Erro ao salvar dados para %s (tentativa %d/%d): %s",
					player.Name, attempt, maxAttempts, errorMsg))
			end

			if attempt < maxAttempts then
				local waitTime = isShutdown and baseDelay or (baseDelay * (attempt ^ 1.5))
				task.wait(waitTime)
			end
		end
	end

	warn(string.format("❌ FALHA CRÍTICA: Não foi possível salvar dados para %s após %d tentativas",
		player.Name, maxAttempts))
	endPendingSave()
	return false
end

-- ========================================
-- Carregar Dados com Retry Robusto
-- ========================================
local function loadPlayerData(player)
	print(string.format("🔄 Iniciando carregamento de dados para %s...", player.Name))

	local dataLoadedSignal = Instance.new("BoolValue")
	dataLoadedSignal.Name = "DataLoaded"
	dataLoadedSignal.Value = false
	dataLoadedSignal.Parent = player

	local userId = player.UserId
	local dataLoaded = false

	-- Reset se necessário
	if RESET_ALL_DATA_ON_JOIN then
		warn(string.format("🔴 INTERRUPTOR DE RESET ATIVO! Apagando dados para %s...", player.Name))
		pcall(function()
			playerDataStore:RemoveAsync("User_" .. userId)
		end)
		task.wait(1)
	end

	-- Tentar carregar com retry
	for attempt = 1, MAX_RETRY_ATTEMPTS do
		print(string.format("🔍 Tentativa %d/%d de carregar dados para %s", attempt, MAX_RETRY_ATTEMPTS, player.Name))

		local success, data = pcall(function()
			return playerDataStore:GetAsync("User_" .. userId)
		end)

		if not success then
			warn(string.format("❌ Erro na tentativa %d: %s", attempt, tostring(data)))
			if attempt < MAX_RETRY_ATTEMPTS then
				task.wait(RETRY_DELAY)
			end
			continue
		end

		if data == nil then
			-- Nada no formato novo ainda — tenta migrar dos 3 DataStores
			-- antigos separados (best-effort) antes de cair pro padrão.
			local migrated = migrateFromLegacyStores(userId)
			if migrated then
				data = migrated
			end
		end

		-- ⚠️ NOVO: reset de uma vez só (ver FORCE_WIPE_VERSION acima) — dado
		-- existente mas sem WipeVersion, ou com uma versão mais antiga que a
		-- atual, é descartado por completo (tratado igual a "não achei
		-- nada"), pra recriar do zero já com Energy e as mudanças recentes.
		if type(data) == "table" and (type(data.WipeVersion) ~= "number" or data.WipeVersion < FORCE_WIPE_VERSION) then
			print(string.format("♻️ Reset de dados (WipeVersion desatualizada) para %s — recriando do zero.", player.Name))
			data = nil
		end

		-- Validar dados carregados
		if type(data) == "table" and validatePlayerData(data) then
			onlinePlayersData[userId] = data
			dataLoaded = true
			print(string.format("✅ Dados válidos carregados para %s (tentativa %d)", player.Name, attempt))
			break
		elseif data == nil then
			print(string.format("⚪ Nenhum dado encontrado para %s. Criando dados padrão...", player.Name))
			onlinePlayersData[userId] = createDefaultData()
			dataLoaded = true
			savePlayerData(player)
			break
		else
			warn(string.format("⚠️ Dados corrompidos detectados para %s (tentativa %d)", player.Name, attempt))
			if attempt < MAX_RETRY_ATTEMPTS then
				task.wait(RETRY_DELAY)
			end
		end
	end

	if not dataLoaded then
		warn(string.format("❌ FALHA CRÍTICA: Não foi possível carregar dados válidos para %s", player.Name))
		onlinePlayersData[userId] = createDefaultData()
		warn(string.format("🆘 Usando dados padrão temporários para %s", player.Name))
	end

	-- Validação final
	if not onlinePlayersData[userId] or not validatePlayerData(onlinePlayersData[userId]) then
		warn(string.format("❌ ERRO CRÍTICO: Dados finais inválidos para %s", player.Name))
		player:Kick("Erro crítico ao carregar dados. Por favor, tente novamente.")
		return
	end

	-- Atualizar atributo do personagem ativo
	local activeSlot = onlinePlayersData[userId].ActiveSlot
	local activeSlotData = onlinePlayersData[userId].CharacterSlots[activeSlot]

	if activeSlotData and activeSlotData ~= "Locked" and validateCharacterSlot(activeSlotData) then
		player:SetAttribute("Role", activeSlotData.Role)
		print(string.format("✅ Role definido como '%s' para %s", activeSlotData.Role, player.Name))
		print(string.format("📊 Nível do personagem: %d", activeSlotData.Level or 1))
	else
		player:SetAttribute("Role", "Unknown")
		warn(string.format("⚠️ Slot ativo inválido para %s. Role definido como 'Unknown'", player.Name))
	end

	-- Sinalizar que dados foram carregados
	dataLoadedSignal.Value = true
	print(string.format("✅ Sinal 'DataLoaded' enviado para %s", player.Name))
end

-- ========================================
-- Funções Globais de Acesso
-- ========================================
_G.GetPlayerData = function(player)
	local data = onlinePlayersData[player.UserId]
	if not data then
		warn(string.format("⚠️ Tentativa de acessar dados inexistentes para %s", player.Name))
		return nil
	end
	return data
end

_G.GetOnlinePlayersData = function()
	return onlinePlayersData
end

-- FIX: SlotNameManager (e agora também MoneyManager/CodeRedeemServer)
-- chamam _G.SavePlayerData(player) esperando salvar na hora — antes essa
-- global nunca tinha sido definida em lugar nenhum, a chamada
-- silenciosamente não fazia nada.
_G.SavePlayerData = function(player)
	return savePlayerData(player, false)
end

-- ========================================
-- MELHORIA DE SAVE: _G.RequestSave — salvamento "quase na hora" com
-- debounce, pra qualquer mudança que hoje só era pega pelo autosave
-- periódico (a causa real do "save atrasado": dinheiro/XP/atributos só
-- gravavam de verdade a cada AUTOSAVE_INTERVAL segundos ou ao sair — se o
-- Studio fechasse errado, ou o server crashasse, no meio disso, o
-- progresso daquela janela se perdia).
--
-- Debounce (não salva a cada pixel de mudança, e sim SAVE_DEBOUNCE_-
-- SECONDS depois da ÚLTIMA mudança) evita martelar o DataStore com um
-- SetAsync por clique — o limite de escrita do Roblox é por chave, então
-- várias chamadas RequestSave seguidas (ex.: clicando "+" várias vezes
-- num atributo) colapsam num salvamento só.
-- ========================================
local SAVE_DEBOUNCE_SECONDS = 2
local pendingDebouncedSave = {} -- [userId] = true enquanto um save debounced já está agendado

-- ⚠️ NOVO (v3.4): chamado pelo LobbyRewardsReceiver.legacy.luau quando uma
-- recompensa de partida vinda do place Game diz "vitória" — soma 1 no
-- contador persistente de vitórias (usado pela preferência de
-- matchmaking por nível, ver Matchmaker.legacy.luau).
_G.AddPlayerWin = function(player)
	local data = onlinePlayersData[player.UserId]
	if not data then
		warn(string.format("❌ AddPlayerWin: dados inexistentes para %s", player.Name))
		return false
	end
	data.Wins = (data.Wins or 0) + 1
	_G.RequestSave(player)
	return true
end

_G.RequestSave = function(player)
	local userId = player.UserId
	if pendingDebouncedSave[userId] then
		return -- já tem um save agendado pra essa mudança (ou uma mais recente)
	end
	pendingDebouncedSave[userId] = true

	task.delay(SAVE_DEBOUNCE_SECONDS, function()
		pendingDebouncedSave[userId] = nil
		if player.Parent and onlinePlayersData[userId] then
			savePlayerData(player, false)
		end
	end)
end

-- ========================================
-- SetActiveSlot: troca qual personagem é o ATIVO (o que entra em
-- campo/partida) — antes não existia NENHUM jeito de mudar isso, só de
-- ler (ActiveSlot nascia sempre 1 e nunca mudava).
-- GetSlotsOverview: dá pro cliente o resumo dos 5 slots (bloqueado/
-- destravado, nome, role, nível, quem é o ativo) pra montar a
-- tela de seleção sem expor Attributes/DataStore internals à toa.
-- ========================================
local eventsFolder = ReplicatedStorage:WaitForChild("LobbyEvents")

local function getOrCreateRemoteFunction(name)
	local existing = eventsFolder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = eventsFolder
	return remote
end

local setActiveSlotFunc = getOrCreateRemoteFunction("SetActiveSlot")
local getSlotsOverviewFunc = getOrCreateRemoteFunction("GetSlotsOverview")
local setSlotRoleFunc = getOrCreateRemoteFunction("SetSlotRole")

setActiveSlotFunc.OnServerInvoke = function(player, slotIndex)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 5 then
		return false, "Slot inválido"
	end

	local playerData = onlinePlayersData[player.UserId]
	if not playerData then
		return false, "Dados não carregados"
	end

	local slot = playerData.CharacterSlots[slotIndex]
	if not slot or slot == "Locked" or not validateCharacterSlot(slot) then
		return false, "Slot bloqueado ou inválido"
	end

	playerData.ActiveSlot = slotIndex
	player:SetAttribute("Role", slot.Role)

	-- ⚠️ FIX: trocar de personagem ativo troca de QUAL Speed vale sem
	-- trocar de Character (não respawna) — StaminaManager.legacy.luau
	-- (Lobby) precisa recalcular o multiplicador de WalkSpeed agora,
	-- senão a corrida no Lobby continua com o Speed do slot ANTERIOR.
	if _G.RefreshLobbySpeedMultiplier then
		_G.RefreshLobbySpeedMultiplier(player)
	end

	task.spawn(function()
		savePlayerData(player)
	end)

	if _G.UpdatePlayerNametag then
		task.spawn(function()
			task.wait(0.1)
			_G.UpdatePlayerNametag(player)
		end)
	end

	print(string.format("🎮 %s definiu o slot %d ('%s') como personagem ativo", player.Name, slotIndex, slot.SlotName))

	return true, { ActiveSlot = slotIndex }
end

-- SetSlotRole: ⚠️ v10 — agora só alterna "quer ser goleiro" (GK) ou não
-- (LINE) por slot. DF/MF/FW saíram (ver ROLES acima e derivePreferredRole
-- em MatchDataTransfer.legacy.luau, place Lobby, pra saber de onde vem a
-- posição de linha agora). Nome do remote mantido (CharacterClient.local.
-- luau já usava esse mesmo InvokeServer) pra não precisar recriar Remote.
setSlotRoleFunc.OnServerInvoke = function(player, slotIndex, newRole)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 5 then
		return false, "Slot inválido"
	end
	if type(newRole) ~= "string" or not table.find(ROLES, newRole) then
		return false, "Posição inválida"
	end

	local playerData = onlinePlayersData[player.UserId]
	if not playerData then
		return false, "Dados não carregados"
	end

	local slot = playerData.CharacterSlots[slotIndex]
	if not slot or slot == "Locked" or not validateCharacterSlot(slot) then
		return false, "Slot bloqueado ou inválido"
	end

	slot.Role = newRole

	if playerData.ActiveSlot == slotIndex then
		player:SetAttribute("Role", newRole)
		if _G.UpdatePlayerNametag then
			task.spawn(function()
				task.wait(0.1)
				_G.UpdatePlayerNametag(player)
			end)
		end
	end

	task.spawn(function()
		savePlayerData(player)
	end)

	print(string.format("⚽ %s definiu a posição do slot %d como '%s'", player.Name, slotIndex, newRole))

	return true, { SlotIndex = slotIndex, Role = newRole }
end

getSlotsOverviewFunc.OnServerInvoke = function(player)
	local playerData = onlinePlayersData[player.UserId]
	if not playerData then return nil end

	local overview = {}
	for i = 1, 5 do
		local slot = playerData.CharacterSlots[i]
		if i > playerData.UnlockedSlots or slot == "Locked" or slot == nil then
			overview[i] = { Index = i, Locked = true }
		elseif validateCharacterSlot(slot) then
			overview[i] = {
				Index = i,
				Locked = false,
				IsActive = (i == playerData.ActiveSlot),
				SlotName = slot.SlotName,
				Role = slot.Role,
				Level = slot.Level or 1,
				Luck = slot.Luck or 0,
				Stars = luckToStars(slot.Luck),
				Element = slot.Element,
			}
		else
			overview[i] = { Index = i, Locked = true }
		end
	end

	return { Slots = overview, ActiveSlot = playerData.ActiveSlot, UnlockedSlots = playerData.UnlockedSlots }
end

-- ========================================
-- Eventos de Jogadores
-- ========================================
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		loadPlayerData(player)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	print(string.format("👋 %s saindo. Salvando dados...", player.Name))
	savePlayerData(player)
	onlinePlayersData[player.UserId] = nil
end)

-- ========================================
-- Salvar ao Fechar Servidor
-- REWORK: 1 salvamento por jogador (não mais 3 escritas + 3 esperas
-- fixas espalhadas em 3 scripts diferentes) e espera só o que estiver
-- de fato pendente, com teto de SHUTDOWN_WAIT_TIMEOUT segundos — se o
-- salvamento já terminou antes disso, o server fecha na hora.
-- ========================================
game:BindToClose(function()
	local players = Players:GetPlayers()
	print(string.format("🔌 Servidor fechando. Salvando dados de %d jogador(es)...", #players))

	for _, player in ipairs(players) do
		task.spawn(function()
			savePlayerData(player, true)
		end)
	end

	_G.WaitForPendingSaves(SHUTDOWN_WAIT_TIMEOUT)
	print("✅ Salvamento completo. Servidor pode fechar.")
end)

-- ========================================
-- Auto-Save Periódico (agora cobre Personagens + Dinheiro + Códigos
-- juntos, num payload só)
-- ========================================
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		local playerCount = #Players:GetPlayers()
		if playerCount > 0 then
			print(string.format("💾 Auto-save iniciado (%d jogadores)...", playerCount))
			for _, player in ipairs(Players:GetPlayers()) do
				task.spawn(function()
					savePlayerData(player)
				end)
			end
		end
	end
end)

print("✅ PlayerDataManager carregado (" .. (USE_MOCK_DATASTORE and "⚠️ MockDataStore ATIVO" or "DataStore real: PlayerSaveData_V1") .. ")")
