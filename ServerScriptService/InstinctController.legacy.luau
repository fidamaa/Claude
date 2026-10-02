--[[
	InstinctController (Script)
	LOCAL: ServerScriptService (place Game)

	Dono dos INSTINTOS (passivos). Sem botão, sem cooldown: o
	BallController/PlayerSystems chamam _G.CheckInstinct(player, trigger,
	ctx) no exato instante do gatilho (chute, carrinho, cabeçada, finta,
	bola parada) e recebem o Effect de volta se a Condition bateu.

	Instintos "Instant" (sem ação pra disparar — ex: Corredor, Fôlego
	Final, Capitão) são reavaliados sozinhos, continuamente, num heartbeat
	próprio — ver getters no fim do arquivo.

	AttackingHalf e NearBylineMaxDistance (geometria de campo): calculadas
	pelo BallController.lua a partir dos dois gols já existentes na cena
	(nenhum objeto novo no Studio) e mandadas dentro de "ctx" — ver
	ctx.AttackingHalf / ctx.DistanceToByline no Trigger "DribbleMove".
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local InstinctData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
-- ⚠️ v67: aura própria do Flow (ver o preset "Flow" em AbilityAura).
local AbilityAura = require(ReplicatedStorage:WaitForChild("AbilityAura"))
local Remotes = Config.Remotes

-- ⚠️ v4: NOMES ANTIGOS. Dois Instintos foram fundidos em outro na v4
-- (Zagueiro → Última Linha, Predatório → Antecipação — ver
-- Data.LegacyNames em PulseInstinctData.luau). Resolve o nome salvo pro
-- atual antes de procurar, pra ninguém ficar sem Instinto.
local function findInstinct(name)
	if not name then return nil end
	if InstinctData.ResolveName then
		name = InstinctData.ResolveName(name)
	end
	for _, def in ipairs(InstinctData.Instincts) do
		if def.Name == name then return def end
	end
	return nil
end

-- ============================================================
-- ⚠️ v5 — AURA DO INSTINTO (pedido: "sempre que uma condição for
-- aplicada, a aura do player fica com a cor equivalente do seu
-- instinto"). NO SERVIDOR de propósito: assim TODO MUNDO em campo vê que
-- aquele jogador está com o instinto ativo, não só ele. Cada Instinto
-- traz sua Cor em PulseInstinctData.luau.
--
-- ⚠️ v5.7: REDESENHADA — era um Highlight (contorno). Pedido: "eu quero
-- que apareça um brilho, tipo uma partícula, ou um campo em volta, algo
-- visual sem ser o contorno, só pra identificar o uso da habilidade, sem
-- sobrescrever o contorno da cor do time e não confundir nada" — o
-- contorno da aura competia visualmente com o TeamHighlight (contorno da
-- cor do TIME, ver PlayerSystems.legacy.luau), ficava difícil separar um
-- do outro. Agora é uma esfera translúcida (material ForceField — o
-- "campo" literal do Roblox, sem precisar de nenhum asset de partícula
-- externo) soldada no HumanoidRootPart, com uma PointLight dentro dela
-- pro brilho — nunca mexe em Highlight/contorno nenhum.
-- ============================================================
local AURA_PULSE_SECONDS = 1.5 -- quanto a aura fica acesa num gatilho de evento
local AURA_BUBBLE_TRANSPARENCY = 0.55
local AURA_LIGHT_BRIGHTNESS = 2.5
local auraByPlayer = {} -- [player] = { bubble = Part, light = PointLight, token = number }

-- ⚠️ v6.5: PEDIDO — "nos instintos, é pra aparecer o forcefield de um
-- tamanho menor, metade desse tamanho atual, com a devida cor da RARIDADE
-- do instinto". Mesma paleta Common/Rare/Epic/Legendary/Mythic já usada no
-- HUD (ver RARITY_COLOR em AbilityHUD.local.luau/
-- DebugAbilitySelectorHUD.local.luau) — repetida aqui porque este é um
-- Script de servidor (sem módulo compartilhado com os LocalScripts do
-- HUD). A cor da aura passa a vir da RARIDADE do Instinto (def.Rarity),
-- não mais da Cor individual de cada um (def.Cor continua existindo e
-- sendo usada só pelo HUD/debug, não pela aura).
local AURA_RARITY_COLOR = {
	Common = Color3.fromRGB(220, 220, 220),
	Rare = Color3.fromRGB(120, 180, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 60),
	Mythic = Color3.fromRGB(255, 90, 110),
}

local function getAura(player)
	local character = player.Character
	if not character then return nil end

	local aura = auraByPlayer[player]
	if aura and aura.bubble.Parent == character then return aura end
	if aura then aura.bubble:Destroy() end

	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return nil end

	local bubble = Instance.new("Part")
	bubble.Name = "InstinctGlow"
	bubble.Shape = Enum.PartType.Ball
	-- ⚠️ v6.5: METADE do tamanho anterior (era 6.5) — pedido: "aparecer o
	-- forcefield de um tamanho menor, metade desse tamanho atual".
	bubble.Size = Vector3.new(3.25, 3.25, 3.25)
	bubble.Material = Enum.Material.ForceField
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CanTouch = false
	bubble.CastShadow = false
	bubble.Massless = true
	bubble.Anchored = false
	bubble.Transparency = 1 -- começa apagada; setAuraActive liga
	bubble.CFrame = root.CFrame
	bubble.Parent = character

	-- Solda no root (não precisa de nenhum loop atualizando posição toda
	-- hora — a física já move a bolha junto do personagem sozinha).
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = bubble
	weld.Part1 = root
	weld.Parent = bubble

	local light = Instance.new("PointLight")
	light.Name = "InstinctGlowLight"
	light.Range = 14
	light.Brightness = 0
	light.Shadows = false
	light.Parent = bubble

	aura = { bubble = bubble, light = light, token = 0 }
	auraByPlayer[player] = aura
	return aura
end

-- Liga a aura na cor do instinto. duration = nil deixa acesa até alguém
-- chamar setAuraActive(player, def, false) — usado pelos instintos
-- contínuos, que ficam acesos enquanto a condição valer.
local function setAuraActive(player, def, active, duration)
	-- ⚠️ v106 — PEDIDO: "tira aquela bolinha que fica em volta dele, aquela bola
	-- azul estranha. Faz um VFX próprio... do impacto na bola, do R, conforme o
	-- anime". A esfera de ForceField (na cor da raridade — azul no Chute
	-- Direto, que é Raro) saiu: cada Arma agora tem efeito próprio desenhado no
	-- cliente (ArmasVFX.local.luau), avisado por aqui.
	if Config.Remotes.ArmaVFX and player.Character then
		Config.DispararVFX("ArmaVFX", player.Character, def and def.Name, def and def.Rarity, active and true or false, duration)
	end
	if true then return end -- (bolha antiga desligada — o resto fica só como referência)
	local aura = getAura(player)
	if not aura then return end

	if not active then
		aura.bubble.Transparency = 1
		aura.light.Brightness = 0
		return
	end

	local cor = def and AURA_RARITY_COLOR[def.Rarity]
	if not cor then return end -- instinto sem Raridade reconhecida: não acende nada

	aura.bubble.Color = cor
	aura.light.Color = cor
	aura.bubble.Transparency = AURA_BUBBLE_TRANSPARENCY
	aura.light.Brightness = AURA_LIGHT_BRIGHTNESS

	if duration then
		-- Token evita que um gatilho antigo apague a aura de um novo.
		aura.token += 1
		local token = aura.token
		task.delay(duration, function()
			if aura.bubble.Parent and aura.token == token then
				aura.bubble.Transparency = 1
				aura.light.Brightness = 0
			end
		end)
	end
end

-- ============================================================
-- ⚠️ v5 — MOMENTO ATIVO ("hissatsu"). O Instinto é passivo, mas alguns
-- FAZEM a jogada acontecer sozinhos quando a condição bate (ex.: a finta
-- que vira lambreta). Reaproveita os executores que o BallController já
-- expõe — eles mesmos checam se a jogada é possível (tem bola no ar? tem
-- alguém no alcance?) e simplesmente não fazem nada se não for.
-- ============================================================
-- ⚠️ v5.6: forward-declaration — amplifyEffect é DEFINIDA mais abaixo (seção
-- "INSTINCT MODE"), mas tryRunAtiva (logo abaixo) já precisa chamá-la pra
-- amplificar AtivaEffect também. Em Lua um "local function" só é visível
-- DEPOIS de onde foi declarado no arquivo — declarando a local aqui (ainda
-- sem valor) e só ATRIBUINDO a função lá embaixo resolve isso: tryRunAtiva
-- guarda essa mesma variável como upvalue, e ela já vai estar preenchida
-- na hora em que o jogo realmente chamar tryRunAtiva (bem depois do script
-- inteiro já ter rodado uma vez).
local amplifyEffect

local ATIVA_EXECUTORS = {
	-- ⚠️ v8: Instinto usa seu PRÓPRIO executor de chute (_G.InstinctExecuteShot,
	-- ver BallController.legacy.luau) — não o de Pulso/Hissatsu. Instinto não
	-- tem raridade de força/MaxRange/chip do zagueiro nem voo reto sem
	-- gravidade: "os instintos não são como o pulso".
	Shot = function(player, effect) return _G.InstinctExecuteShot and _G.InstinctExecuteShot(player, effect) end,
	Pass = function(player, effect) return _G.PulseExecutePass and _G.PulseExecutePass(player, effect) end,
	Tackle = function(player, effect) return _G.PulseExecuteTackle and _G.PulseExecuteTackle(player, effect) end,
	Header = function(player, effect) return _G.PulseExecuteHeader and _G.PulseExecuteHeader(player, effect) end,
	DribbleMove = function(player, effect) return _G.PulseExecuteDribbleMove and _G.PulseExecuteDribbleMove(player, effect) end,
	AerialControl = function(player, effect) return _G.PulseExecuteAerialControl and _G.PulseExecuteAerialControl(player, effect) end,
}
-- ⚠️ v111 — PEDIDO: "tem muitas armas de status... tem que ter utilidade
-- diversa: um drible criativo, alguma coisa diferente". As ativas novas
-- (Arranque, Drible do Monstro, Sumir, Tabela, Passe Curvo, Colar,
-- Interceptar, Passo Fantasma, Saída do Gol, Segundo Fôlego) ficam no
-- BallController como _G.ArmaAtiva_<AtivaAction> — lá estão a bola, a posse e
-- o deslocamento. Cada uma devolve (true) ou (false, "motivo pro HUD").
setmetatable(ATIVA_EXECUTORS, { __index = function(_, acao)
	local f = _G["ArmaAtiva_" .. tostring(acao)]
	return f and function(player, effect) return f(player, effect) end or nil
end })

-- ⚠️ v118: cooldown POR ARMA (antes era um só por jogador: usar a do E travava a
-- do R também, e o HUD novo mostra cada uma separada)
local ativaReadyAtPorNome = {} -- [player] = { [nomeDaArma] = tick() em que pode de novo }
local function prontaEm(player, nome)
	local t = ativaReadyAtPorNome[player]
	return t and t[nome] or nil
end
local ativaReadyAt = setmetatable({}, {
	__newindex = function(_, player, valor)
		if valor == nil then ativaReadyAtPorNome[player] = nil end
	end,
})

local debugNoCooldown = {} -- [player] = true (ferramenta de teste, ver DebugAbilitySelector)

-- Liga/desliga o cooldown das ativas pra testar um Instinto em sequência
-- sem esperar. Chamado pelo DebugAbilitySelector.legacy.luau.
_G.SetInstinctDebugNoCooldown = function(player, enabled)
	debugNoCooldown[player] = enabled and true or nil
end
-- ⚠️ v110 (debugger): zera AGORA o cooldown da ativa da arma
_G.ZerarInstinctCooldown = function(player)
	local t = ativaReadyAtPorNome[player]
	if t then
		for nome in pairs(t) do player:SetAttribute("ArmaCD_" .. nome, nil) end
	end
	ativaReadyAtPorNome[player] = nil
end

local function tryRunAtiva(player, def)
	if not def or not def.AtivaAction then return false end

	local executor = ATIVA_EXECUTORS[def.AtivaAction]
	if not executor then
		warn(string.format("InstinctController: '%s' pede a ação '%s', que não existe.", def.Name, tostring(def.AtivaAction)))
		return false
	end

	-- Cooldown obrigatório: sem ele, um instinto contínuo tentaria
	-- disparar 4x por segundo.
	-- ⚠️ v28: quem não declara AtivaCooldown cai no cooldown GERAL da
	-- raridade (ver Config.INSTINCT_COOLDOWN_BY_RARITY).
	local cooldown = def.AtivaCooldown
		or (Config.INSTINCT_COOLDOWN_BY_RARITY and Config.INSTINCT_COOLDOWN_BY_RARITY[def.Rarity])
		or 10
	local readyAt = prontaEm(player, def.Name)
	if readyAt and tick() < readyAt and not debugNoCooldown[player] then return false end

	-- ⚠️ v5.6: Instinct Mode agora amplifica TODO buff que o instinto daria
	-- normalmente — inclusive o da Ativa (AtivaEffect), que antes nunca era
	-- tocado aqui (só def.Effect passava por amplifyEffect). É o que faz
	-- Chute Direto/Predador da Área também sentirem o Instinct Mode, já
	-- que o bônus real deles mora no AtivaEffect, não no Effect (vazio).
	local ativaEffect = def.AtivaEffect or {}
	if _G.IsInInstinctMode and _G.IsInInstinctMode(player) and amplifyEffect then
		ativaEffect = amplifyEffect(ativaEffect)
	end
	-- ⚠️ v17 — PEDIDO: "melhora um pouco o Matador, porque ele faz mais ou
	-- menos a mesma coisa do Chute Direto... talvez pegar a bola, jogar mais
	-- forte". BallMagnetRadius PUXA a bola pro jogador ANTES da ação rodar.
	-- É o que separa os dois de verdade: o Chute Direto exige que a bola já
	-- esteja no seu pé (você acabou de receber); o Matador vai BUSCAR a bola
	-- que está caindo perto e só então finaliza. Deixa de ser "aperta o botão
	-- e chuta" e vira "aperta o botão e a bola vem até você".
	if ativaEffect.BallMagnetRadius and _G.PulseExecuteBallMagnet then
		_G.PulseExecuteBallMagnet(player, ativaEffect)
	end

	local ok, motivo = executor(player, ativaEffect)
	if ok then
		-- Só entra em cooldown quando a jogada REALMENTE aconteceu — se
		-- não tinha bola no ar, o jogador não fica penalizado por isso.
		ativaReadyAtPorNome[player] = ativaReadyAtPorNome[player] or {}
		ativaReadyAtPorNome[player][def.Name] = tick() + cooldown
		-- ⚠️ v118: o HUD de habilidades lê daqui (contagem e escurecer o slot)
		player:SetAttribute("ArmaCD_" .. def.Name, workspace:GetServerTimeNow() + cooldown)
		player:SetAttribute("ArmaCDTotal_" .. def.Name, cooldown)
	end
	return ok and true or false, motivo
end

-- ⚠️ v76 — VIROU LISTA. PEDIDO: "inclua DOIS slot pra arma... pro player
-- intercalar entre os dois". Antes era 1 nome só por jogador; agora é
-- uma lista (até 3: 2 de graça + 1 comprado com Robux, ver RollServer.
-- legacy.luau no Lobby). Índice 1 = mais recente sorteado.
--
-- ESCOPO DESTA CONVERSÃO (documentado aqui porque é a única coisa não
-- óbvia da mudança): Instintos de gatilho DISCRETO (Trigger de evento —
-- chute, carrinho, cabeceio... — e os poucos com Tecla="R") checam TODOS
-- os slots equipados agora (primeiro que bater a condição vence — ver
-- _G.CheckInstinct e o handler de Remotes.ActivateInstinct mais abaixo).
-- Instintos CONTÍNUOS (Trigger="Instant", tipo "Pique" — ligados/
-- desligados por um cooldown e um "efeito ao vivo" únicos por jogador,
-- não por nome) continuam olhando só o SLOT 1: generalizar cooldown/
-- efeito-ao-vivo pra vários contínuos simultâneos é uma reestruturação
-- bem mais funda (o estado hoje é 1 valor por JOGADOR, precisaria virar
-- 1 valor por JOGADOR+NOME em ~4 tabelas) que eu não ia conseguir
-- validar sem testar ao vivo — então não arrisquei quebrar o sistema de
-- contínuos por causa disso. Os slots 2/3 valem cheio pra Hissatsu-estilo
-- ativa (o caso comum) e só não somam efeito contínuo extra se você
-- equipar 2 instintos "Instant" ao mesmo tempo.
local EquippedList = {} -- [player] = { instinctName, instinctName, instinctName }

_G.SetPlayerInstincts = function(player, listaDeNomes)
	EquippedList[player] = (typeof(listaDeNomes) == "table") and listaDeNomes or {}
end

_G.GetEquippedInstincts = function(player)
	return EquippedList[player] or {}
end

-- Compat: quem só quer "o principal" (slot 1) — usado pelo loop de carga
-- contínua e pelos poucos lugares que ainda pensam em 1 só.
local function equippedPrimary(player)
	local lista = EquippedList[player]
	return lista and lista[1]
end

-- ⚠️ v106 — "as armas não estão funcionando direito, algumas estão, outras
-- estranhas". Arma CONTÍNUA (Trigger "Instant", ex.: Pique) só era lida no
-- slot 1 — no slot 2 ela nunca ligava. Agora vale a primeira contínua
-- equipada, em qualquer slot (duas contínuas juntas: vale a do slot 1).
local function primeiraContinua(player)
	local lista = EquippedList[player]
	if not lista then return nil end
	for _, nome in ipairs(lista) do
		local def = findInstinct(nome)
		if def and def.Trigger == "Instant" then return nome end
	end
	return nil
end

-- ================================================================
-- INSTINCT MODE (novo — medidor separado do cooldown de cada Instinto)
-- ================================================================
-- Carrega +INSTINCT_CHARGE_PER_TRIGGER (flat, mesmo valor pra qualquer
-- raridade por enquanto — dá pra escalar por raridade depois, deixado
-- simples de propósito) toda vez que o Effect do Instinto EQUIPADO do
-- próprio jogador dispara de verdade (dentro de _G.CheckInstinct e na
-- transição ligou/desligou do loop "Instant" abaixo). Cheio (100), o
-- jogador pode gastar o medidor inteiro (Remotes.ActivateInstinctMode)
-- pra entrar em Instinct Mode por INSTINCT_MODE_DURATION segundos: todo
-- bônus numérico do Effect do Instinto equipado fica amplificado, e os
-- limiares da Condition ficam mais fáceis de bater.
local InstinctCharge = {} -- [player] = 0-100
local InstinctModeState = {} -- [player] = { ExpiresAt }

-- ⚠️ v6.5: PEDIDO — "aumente a quantidade de ações pra ativar o modo
-- instinc pro dobro das atuais". Era 20 (5 disparos enchiam o medidor) —
-- metade disso dobra a quantidade de disparos necessários (10 agora).
local INSTINCT_CHARGE_PER_TRIGGER = 10 -- flat por enquanto (ver comentário acima) — 10 disparos enchem o medidor
local INSTINCT_MODE_DURATION = 9
-- ⚠️ v5.6: era 1.75 (bônus ficava +75% maior), depois 1.12 (+12%).
-- ⚠️ v5.7: PEDIDO — "instinct mode na real é 25% bonus": a PORÇÃO de
-- bônus (delta acima da baseline) de cada chave do Effect/AtivaEffect
-- fica 25% maior durante o Instinct Mode.
local INSTINCT_MODE_AMPLIFY = 1.25

_G.IsInInstinctMode = function(player)
	local state = InstinctModeState[player]
	return state ~= nil and tick() < state.ExpiresAt
end

-- ⚠️ PULSO v3: generalizada pra receber a QUANTIDADE de carga (antes era
-- sempre INSTINCT_CHARGE_PER_TRIGGER, fixo). Sem argumento, mantém
-- exatamente o comportamento antigo — todas as chamadas internas
-- continuam iguais. Clamp em 100 e o "MeterUpdate" pro cliente também
-- continuam idênticos.
-- ⚠️ v113 — PEDIDO: "só 1 Flow por partida". Quem já usou não carrega mais
-- (o medidor fica em 0 e o HUD mostra "usado"). Zera no começo da partida
-- (_G.ResetarFlowsDaPartida, chamado pelo MatchController).
local FlowsUsados = {}
_G.ResetarFlowsDaPartida = function()
	for player in pairs(FlowsUsados) do
		if player.Parent then player:SetAttribute("FlowUsado", nil) end
	end
	table.clear(FlowsUsados)
end
local function addInstinctCharge(player, amount)
	amount = tonumber(amount) or (Config.FLOW_CHARGE_ARMA or INSTINCT_CHARGE_PER_TRIGGER)
	if amount <= 0 then return end
	if FlowsUsados[player] then return end
	local current = InstinctCharge[player] or 0
	if current >= 100 then return end
	current = math.min(100, current + amount)
	InstinctCharge[player] = current
	Remotes.InstinctModeFeedback:FireClient(player, "MeterUpdate", current)
end

-- ============================================================
-- ⚠️ v6.5: PEDIDO — "a forma atual de carregar o modo instinct de
-- instintos de BUFF é com o tempo, se for algo geral, ou praticando a
-- ação que o buff causa (chutar, defender...)". Antes, TODO instinto só
-- carregava o medidor quando a condição ESPECIAL dele batia de verdade
-- (ex: Chute Direto só carregava se você apertasse R dentro de 1s depois
-- de receber — chutar "normal" fora dessa janela não carregava nada, e um
-- instinto "geral" como Metavisão, sem NENHUMA ação própria, nunca
-- carregava absolutamente nada). Agora, além da carga cheia de sempre
-- quando a condição bate:
--   - Instintos de BUFF "gerais" (sem uma ação específica — velocidade,
--     visão, sorte) carregam devagar com o TEMPO de jogo, sempre que
--     estiverem equipados.
--   - Instintos de BUFF ligados a uma ação específica (chute, carrinho,
--     cabeceio, drible, mergulho de goleiro) carregam uma fração da carga
--     toda vez que essa ação é PRATICADA de verdade, mesmo quando a
--     condição especial do instinto não bate dessa vez.
-- ============================================================
local INSTINCT_PRACTICE_ACTION = {
	["Chute Direto"] = "Kick",
	["Ego do Rei"] = "Kick",
	["Sentinela"] = "Tackle",
	["Guardião"] = "Dive",
	["Monstro do Drible"] = "DribbleMove",
	["Predador da Área"] = "Header",
}
local INSTINCT_GENERAL = {
	["Velocidade Explosiva"] = true,
	["Domínio Absoluto"] = true,
	["Metavisão"] = true,
	["Apostador"] = true,
}

-- Fração da carga cheia (INSTINCT_CHARGE_PER_TRIGGER) dada só por PRATICAR
-- a ação certa, sem a condição especial bater — bem menor que a carga
-- cheia (~1/3), pra continuar valendo a pena buscar a condição de verdade.
local INSTINCT_CHARGE_PRACTICE_FRACTION = 1 / 3

-- Taxa de carga por TEMPO (por segundo) pros instintos "gerais" — calibrada
-- pra levar por volta do dobro do tempo que os outros levariam só de
-- prática, já que aqui não exige NENHUMA ação específica, só estar
-- equipado e em campo.
local INSTINCT_TIME_CHARGE_PER_SECOND = 100 / 50 -- enche em ~50s só de tempo equipado

-- ⚠️ v6.5: chamado pelo BallController.lua no instante de CADA tentativa
-- de ação (chute, carrinho, cabeceio, finta, mergulho de goleiro) — mesmo
-- quando a jogada não tem nada a ver com o instinto especial do jogador,
-- ou quando a condição dele não bate dessa vez. Só soma carga de PRÁTICA
-- se a ação bater com o INSTINCT_PRACTICE_ACTION do instinto EQUIPADO —
-- pra qualquer outro caso (instinto geral, ou ação de outro tipo), não faz
-- nada.
-- ⚠️ v67 — CARGA DO FLOW, REFEITA.
-- PEDIDO: "o Flow só vai ser carregado por PASSES na bola — passes
-- bem-sucedidos. Se você pegar a bola, passar e pegar de volta depois de ter
-- passado pelo seu próprio domínio, não vale de nada. Mas RECEBER passes vale
-- sim. Domínio de outra pessoa que passa a ser seu, aí sim isso vale — dar
-- carrinho e tirar o domínio de alguém, ou receber algum passe,
-- interceptação. Gols ganham mais."
--
-- A regra de fundo é uma só: **a bola tem que TROCAR DE MÃOS**. Passe é a
-- moeda do jogo aqui; conduzir sozinho não constrói Flow nenhum.
--
-- Por isso NotifyInstinctAction (a carga por "praticar a ação da sua Arma")
-- foi DESLIGADA — ela dava carga por chutar, driblar, cabecear e mergulhar,
-- que é exatamente o oposto do pedido. Ela vira função vazia em vez de
-- sumir pra não quebrar as 5 chamadas espalhadas pelo BallController: elas
-- continuam existindo, só não carregam mais nada.
_G.NotifyInstinctAction = function()
	-- desligada de propósito — ver o comentário acima
end

-- Um passe que CHEGOU: carrega quem deu e quem recebeu.
-- Os dois ganham porque o pedido conta as duas pontas ("passes
-- bem-sucedidos" e "receber passes vale sim").
_G.NotifyFlowPass = function(dePlayer, paraPlayer)
	if dePlayer and dePlayer ~= paraPlayer then
		addInstinctCharge(dePlayer, Config.FLOW_CHARGE_PASS_GIVEN)
	end
	if paraPlayer then
		addInstinctCharge(paraPlayer, Config.FLOW_CHARGE_PASS_RECEIVED)
	end
end

-- Tomou a bola de um ADVERSÁRIO (carrinho, interceptação, roubo).
_G.NotifyFlowSteal = function(player)
	if player then addInstinctCharge(player, Config.FLOW_CHARGE_STEAL) end
end

-- Gol: o que mais carrega.
_G.NotifyFlowGoal = function(player)
	if player then addInstinctCharge(player, Config.FLOW_CHARGE_GOAL) end
end

-- Carga por TEMPO dos instintos "gerais" — um loop simples, independente
-- do resto (não depende de nenhum trigger de ação acontecer).
-- ⚠️ v113 — BUG: "o Flow enche por segundo com a bola; tem que ser por AÇÃO".
-- Este laço dava carga TODO SEGUNDO pras Armas "gerais" equipadas — foi
-- desligado. (A outra metade do bug: a Arma contínua que LIGA — ex.: a
-- condição "com a bola", que liga/desliga a cada toque — dava carga cheia a
-- cada vez; também saiu, ver "Avisa só na TRANSIÇÃO".) O Flow agora só vem de
-- AÇÃO: passe dado/recebido, roubo, gol, Arma disparando numa jogada e ativa
-- usada.

-- Exposta pro PulseController: a chave de Effect "InstinctCharge" (0-100)
-- de um Pulso soma direto no medidor de Instinct Mode do jogador — é o
-- que faz Pulsos "de leitura de jogo" (Leitura, Camisa 10, Xerife,
-- General, Reflexo Absoluto...) aproximarem o Instinct Mode.
_G.AddInstinctCharge = function(player, amount)
	addInstinctCharge(player, amount)
end

-- Amplifica a PORÇÃO de bônus (delta acima de uma baseline "neutra") de
-- CADA chave numérica do Effect — genérico, não trata cada uma das
-- ~20 chaves possíveis na mão. Baseline: 1.0 pra chaves que terminam em
-- "Mult" (ex: ForceMult 1.10 → bônus de 0.10 vira 0.175, virando 1.175),
-- 0 pra chaves que terminam em "Add" (ex: ChanceAdd 0.10 vira 0.175).
-- Chaves que não seguem esse padrão (ex: flags booleanas como
-- AlwaysStun, ou strings) passam direto, sem amplificação.
-- ⚠️ v5.6: agora é ATRIBUIÇÃO (não "local function") — a variável já foi
-- declarada lá em cima (antes de tryRunAtiva) pra poder ser usada como
-- upvalue nela. Ver comentário na declaração.
amplifyEffect = function(effect)
	if not effect then return effect end
	local amplified = {}
	for key, value in pairs(effect) do
		if typeof(value) == "number" then
			local baseline = nil
			if key:match("Mult$") then
				baseline = 1
			elseif key:match("Add$") then
				baseline = 0
			end
			if baseline ~= nil then
				amplified[key] = baseline + (value - baseline) * INSTINCT_MODE_AMPLIFY
			else
				amplified[key] = value
			end
		else
			amplified[key] = value
		end
	end
	return amplified
end

-- Mesma ideia genérica pra Condition: afrouxa limiares numéricos sem
-- tratar cada chave na mão — olha só o PREFIXO/SUFIXO do nome:
--   Max*              → x1.5 (mais forgiving: aceita distância/tempo maior)
--   Min*              → /1.5 (mais forgiving: aceita distância menor)
--   *Chance*          → +0.15 (rolagem de chance fica mais fácil)
--   LastSecondsOfHalf → x1.5 (janela de "faltam N segundos" fica maior)
-- Qualquer outra chave numérica (ex: um raio que não seja Max/Min, ou um
-- booleano como TeamLosing/IsSetPiece) passa direto, sem alterar.
local function loosenCondition(condition)
	if not condition then return condition end
	local loosened = {}
	for key, value in pairs(condition) do
		if typeof(value) == "number" then
			if key:match("^Max") then
				loosened[key] = value * 1.5
			elseif key:match("^Min") then
				loosened[key] = value / 1.5
			elseif key:match("Chance") then
				loosened[key] = value + 0.15
			elseif key == "LastSecondsOfHalf" then
				loosened[key] = value * 1.5
			else
				loosened[key] = value
			end
		else
			loosened[key] = value
		end
	end
	return loosened
end

Remotes.ActivateInstinctMode.OnServerEvent:Connect(function(player)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	local charge = InstinctCharge[player] or 0
	if charge < 100 then return end -- medidor não cheio — cliente já trava o botão, isso é defesa em profundidade
	if _G.IsInInstinctMode(player) then return end -- já ativo
	if FlowsUsados[player] then return end -- ⚠️ v113: 1 Flow por partida

	FlowsUsados[player] = true
	player:SetAttribute("FlowUsado", true)
	InstinctCharge[player] = 0
	Remotes.InstinctModeFeedback:FireClient(player, "MeterUpdate", 0)
	-- ⚠️ v113: primeiro a CENA do Flow (congela a partida, ver PulseController
	-- _G.TocarCenaFlow); os 9s de Flow só começam quando ela acaba
	local cena = _G.TocarCenaFlow and _G.TocarCenaFlow(player) or 0
	-- trava contra apertar de novo durante a cena
	InstinctModeState[player] = { ExpiresAt = tick() + cena + INSTINCT_MODE_DURATION }
	task.delay(cena, function()
		if not player.Parent then return end
		InstinctModeState[player] = { ExpiresAt = tick() + INSTINCT_MODE_DURATION }
		Remotes.InstinctModeFeedback:FireClient(player, "ModeActivated", INSTINCT_MODE_DURATION)
		-- ⚠️ v110 — FLOW ESCOLHIDO NA LOJA (Blue Lock): cada Flow soma atributos
		-- e/ou velocidade enquanto dura + a cena de ativação (ver CosmeticosServer).
		if _G.AtivarFlow then _G.AtivarFlow(player, INSTINCT_MODE_DURATION) end
		task.delay(INSTINCT_MODE_DURATION, function()
			local state = InstinctModeState[player]
			if state and tick() >= state.ExpiresAt then
				InstinctModeState[player] = nil
				Remotes.InstinctModeFeedback:FireClient(player, "ModeEnded")
			end
		end)
	end)
end)

local function otherTeamName(teamName)
	for _, t in ipairs(Config.TEAM_NAMES) do
		if t ~= teamName then return t end
	end
	return nil
end

local function teamLosing(teamName)
	if not _G.GetTeamScore then return false end
	local other = otherTeamName(teamName)
	if not other then return false end
	return _G.GetTeamScore(teamName) < _G.GetTeamScore(other)
end

local function teamLeading(teamName)
	if not _G.GetTeamScore then return false end
	local other = otherTeamName(teamName)
	if not other then return false end
	return _G.GetTeamScore(teamName) > _G.GetTeamScore(other)
end

-- ============================================================
-- ⚠️ v5.4 — "APOSTADOR". Uma jogada de sorte periódica por jogador: a
-- cada GambleIntervalSeconds, sorteia (GambleChance) se o Effect fica
-- valendo pelos próximos GambleDurationSeconds. Guardado aqui (não em
-- conditionMet, que é uma função pura) porque precisa lembrar QUANDO foi
-- o último sorteio e se o prêmio ainda está valendo — mesma ideia de
-- passivoReadyAt mais abaixo, só que por Instinto em vez de por cooldown
-- de "Instant" comum.
-- ============================================================
local gambleState = {} -- [player] = { NextRollAt = tick(), ActiveUntil = 0 }

local function updateGambleContext(c, player, ctx)
	if not c or not c.GambleChance then return end

	local state = gambleState[player]
	if not state then
		state = { NextRollAt = 0, ActiveUntil = 0 }
		gambleState[player] = state
	end

	local agora = tick()
	if agora >= state.NextRollAt then
		local intervalo = c.GambleIntervalSeconds or 4
		state.NextRollAt = agora + intervalo
		-- ⚠️ v5.4: PEDIDO — mostrar o timing da próxima jogada no canto da
		-- tela. Manda só a DURAÇÃO (não um tick() absoluto — cliente e
		-- servidor não têm o mesmo relógio) toda vez que uma rodada nova
		-- começa; o cliente conta regressivo sozinho (ver AbilityHUD.local.
		-- luau, reaproveitando o mesmo painel de cooldowns).
		Remotes.GambleTimerFeedback:FireClient(player, intervalo)
		if math.random() < c.GambleChance then
			state.ActiveUntil = agora + (c.GambleDurationSeconds or 3)
		end
	end

	ctx.GambleActive = agora < state.ActiveUntil
end

local function conditionMet(def, player, ctx)
	local c = def.Condition or {}
	if _G.IsInInstinctMode and _G.IsInInstinctMode(player) then
		c = loosenCondition(c) -- limiares mais fáceis de bater durante o Instinct Mode
	end
	ctx = ctx or {}

	if c.MaxDistanceToGoal and not (ctx.DistanceToGoal and ctx.DistanceToGoal <= c.MaxDistanceToGoal) then return false end
	if c.MinDistanceToGoal and not (ctx.DistanceToGoal and ctx.DistanceToGoal >= c.MinDistanceToGoal) then return false end
	if c.TargetMaxDistanceToGoal and not ((ctx.TargetDistanceToGoal or ctx.DistanceToGoal) and (ctx.TargetDistanceToGoal or ctx.DistanceToGoal) <= c.TargetMaxDistanceToGoal) then return false end -- ⚠️ v111: distância do PONTO MIRADO
	if c.MaxSecondsAfterReceive and not (ctx.SecondsAfterReceive and ctx.SecondsAfterReceive <= c.MaxSecondsAfterReceive) then return false end
	if c.MaxDistanceToOwnGoal and not (ctx.DistanceToOwnGoal and ctx.DistanceToOwnGoal <= c.MaxDistanceToOwnGoal) then return false end
	if c.MaxDistanceOpponent and not (ctx.OpponentDistance and ctx.OpponentDistance <= c.MaxDistanceOpponent) then return false end
	if c.LooseBallOpponentRadius and not (ctx.OpponentDistance and ctx.OpponentDistance <= c.LooseBallOpponentRadius) then return false end
	if c.LastSecondsOfHalf then
		local remaining = _G.GetMatchTimeRemaining and _G.GetMatchTimeRemaining() or math.huge
		if remaining > c.LastSecondsOfHalf then return false end
	end
	if c.TeamLosing and not (player.Team and teamLosing(player.Team.Name)) then return false end
	if c.TeamLeading and not (player.Team and teamLeading(player.Team.Name)) then return false end
	-- ⚠️ v9 FIX: essa condição nunca tinha sido implementada de verdade —
	-- ctx.NoOpponentAhead nunca existiu em lugar nenhum, então nenhum
	-- Instinto que a usasse jamais disparava. Agora compara contra
	-- ctx.ForwardOpponentDistance de verdade (distância até o adversário
	-- mais perto DENTRO de um cone à frente do jogador — "campo livre" de
	-- verdade, ver forwardOpponentDistance em BallController.legacy.luau).
	if c.NoOpponentAheadRadius and not (ctx.ForwardOpponentDistance and ctx.ForwardOpponentDistance >= c.NoOpponentAheadRadius) then return false end
	-- ⚠️ v9 NOVO: "Emboscada" — cercado por N adversários ao mesmo tempo.
	if c.MinOpponentsNearby and not (ctx.OpponentsNearbyCount and ctx.OpponentsNearbyCount >= c.MinOpponentsNearby) then return false end
	-- ⚠️ v9 NOVO: "Xeque-Mate" — leitura numérica real de 2 contra 1 (ou
	-- melhor) na hora do passe.
	if c.RequireNumericalAdvantage and not ctx.HasNumericalAdvantage then return false end
	-- ⚠️ v9 NOVO: "Último Homem" — ninguém do time mais perto do próprio
	-- gol do que você.
	if c.RequireLastManBack and not ctx.IsLastManBack then return false end
	-- ⚠️ v9 NOVO: "Cara a Cara" — OPOSTO de MaxDistanceOpponent: exige que
	-- NINGUÉM adversário esteja perto (breakaway limpo, 1x1 puro com o
	-- goleiro).
	if c.MinDistanceOpponent and not (ctx.OpponentDistance and ctx.OpponentDistance >= c.MinDistanceOpponent) then return false end
	if c.RecoveredInOwnHalf and not ctx.HasPossession then return false end
	if c.IsSetPiece and not ctx.IsSetPiece then return false end
	if c.AttackingHalf and not ctx.AttackingHalf then return false end
	if c.NearBylineMaxDistance and not (ctx.DistanceToByline and ctx.DistanceToByline <= c.NearBylineMaxDistance) then return false end
	-- ⚠️ v5.2: ARRANQUE. "Velocidade Explosiva" só vale nos primeiros
	-- segundos da corrida, não o tempo todo em que o jogador está correndo
	-- (ver _G.GetSecondsSinceSprintStart em PlayerSystems.legacy.luau).
	if c.MaxSecondsAfterSprintStart then
		local desde = _G.GetSecondsSinceSprintStart and _G.GetSecondsSinceSprintStart(player) or math.huge
		if desde > c.MaxSecondsAfterSprintStart then return false end
	end
	-- ⚠️ v5.4: "Ego do Rei" (fora da área adversária) / "Sentinela" (dentro
	-- da própria área) — ctx.OutsideEnemyArea/ctx.InOwnArea vêm prontos do
	-- BallController.lua no instante do chute/carrinho (ele é quem sabe
	-- qual time é o adversário e chama GKAreaUtil).
	if c.RequireOutsideEnemyArea and not ctx.OutsideEnemyArea then return false end
	if c.RequireOwnArea and not ctx.InOwnArea then return false end
	-- ⚠️ v5.4: "Predador da Área" — dentro da área ADVERSÁRIA (a que ele
	-- está atacando), oposto do RequireOutsideEnemyArea do Ego do Rei.
	if c.RequireInsideEnemyArea and not ctx.InsideEnemyArea then return false end
	-- ⚠️ v5.4: "Ego do Rei" só com o chute carregado até o máximo.
	if c.RequireMaxCharge and not ctx.IsMaxCharge then return false end
	-- ⚠️ v5.4: "Apostador" — a jogada de sorte (ver updateGambleContext).
	if c.GambleChance then
		updateGambleContext(c, player, ctx)
		if not ctx.GambleActive then return false end
	end

	-- ============================================================
	-- ⚠️ v12 — CONDIÇÕES NOVAS (Instintos vindos de Blue Lock; ver
	-- Data.Instincts). Todas leem campos que o BallController passou a
	-- calcular na v12 — nenhuma delas dá pra montar com os campos antigos,
	-- que era exatamente o motivo dos 5 Instintos substituídos terem
	-- virado "+X% numa situação genérica".
	-- ============================================================

	-- "Zona de Ouro": o ponto do campo que é SEU — distância E ângulo, não
	-- só distância. Fora de qualquer uma das duas faixas, não vale.
	if c.GoldenZoneDistance then
		local tolerance = c.GoldenZoneDistanceTolerance or 6
		if not ctx.DistanceToGoal then return false end
		if math.abs(ctx.DistanceToGoal - c.GoldenZoneDistance) > tolerance then return false end
	end
	if c.GoldenZoneAngle then
		local tolerance = c.GoldenZoneAngleTolerance or 18
		if not ctx.AngleToGoal then return false end
		if math.abs(ctx.AngleToGoal - c.GoldenZoneAngle) > tolerance then return false end
	end

	-- "Olho de Predador": o goleiro baixou a guarda NESTE chute (adiantado
	-- ou deslocado pro lado contrário). Condição que lê o ADVERSÁRIO.
	if c.RequireGoalkeeperOffGuard and not ctx.GoalkeeperOffGuard then return false end

	-- "Passo Furtivo": ninguém está te olhando, e você não está com a bola
	-- (é um Instinto de movimentação SEM bola — com a bola todo mundo
	-- olha pra você por definição).
	if c.RequireUnseen and not ctx.IsUnseen then return false end
	if c.RequireNoPossession and ctx.HasPossession then return false end

	-- "Tabela": o time trocou N passes seguidos sem perder a bola.
	if c.MinTeamPassChain and not (ctx.TeamPassChain and ctx.TeamPassChain >= c.MinTeamPassChain) then return false end

	-- "A Zona": você está com a bola há N segundos sem largar.
	if c.MinSecondsInPossession and not (ctx.SecondsInPossession and ctx.SecondsInPossession >= c.MinSecondsInPossession) then return false end

	-- ⚠️ v110 — condições das Armas novas (ver Data.Instincts, bloco v110)
	if c.DefendingHalf and ctx.AttackingHalf ~= false then return false end -- no PRÓPRIO campo
	if c.CarrierMaxDistance and not (ctx.CarrierDistance and ctx.CarrierDistance <= c.CarrierMaxDistance) then return false end
	if c.RequirePossession and not ctx.HasPossession then return false end

	return true
end

-- Chamado pelo BallController.lua/PlayerSystems.lua no instante exato do
-- gatilho. Retorna o Effect (table) ou nil.
-- ⚠️ v76: checa TODOS os slots equipados (ordem 1→2→3) — o primeiro cujo
-- Trigger bata E cuja Condition seja satisfeita vence e dispara; os
-- outros nem são tentados. Assinatura/retorno pro chamador (BallController/
-- PlayerSystems) não mudou — continuam recebendo 1 Effect ou nil, só a
-- ORIGEM de qual Instinto virou esse Effect agora pode ser qualquer slot.
_G.CheckInstinct = function(player, trigger, ctx)
	local name, def
	for _, candidato in ipairs(EquippedList[player] or {}) do
		local candidatoDef = findInstinct(candidato)
		if candidatoDef and candidatoDef.Trigger == trigger
			and not (candidatoDef.RoleRequired and player:GetAttribute("Role") ~= candidatoDef.RoleRequired)
			and conditionMet(candidatoDef, player, ctx) then
			name, def = candidato, candidatoDef
			break
		end
	end
	if not name then return nil end

	-- PEDIDO: instintos são passivos (sem botão), mas o jogador precisa
	-- VER na tela quando a condição foi cumprida e o efeito disparou —
	-- avisa o cliente com um "pulso" (liga agora, desliga sozinho logo
	-- depois) só pra feedback visual do HUD (ver AbilityHUD.local.luau).
	Remotes.InstinctFeedback:FireClient(player, true, name)
	task.delay(1.5, function()
		Remotes.InstinctFeedback:FireClient(player, false, name)
	end)

	-- ⚠️ v5: acende a aura na cor do instinto (todo mundo vê) e, se esse
	-- instinto tiver um momento ativo, executa a jogada sozinho.
	setAuraActive(player, def, true, AURA_PULSE_SECONDS)
	if not def.AtivaSoNaTecla then tryRunAtiva(player, def) end -- ⚠️ v111: a de tecla só no aperto

	addInstinctCharge(player) -- Instinct Mode: +carga toda vez que o Effect dispara de verdade

	if _G.IsInInstinctMode(player) then
		return amplifyEffect(def.Effect)
	end
	return def.Effect
end

-- ===== INSTINTOS "Instant" (contínuos, sem ação) =====
-- Reavaliados a cada 0.25s por jogador. Guardam o efeito COMBINADO em
-- LiveEffect[player] pros getters abaixo lerem.
-- ⚠️ v111 — PEDIDO: "faça todas as armas funcionar". Só a PRIMEIRA Arma
-- contínua equipada valia (ver primeiraContinua): com duas contínuas (ex.:
-- Pulmão de Aço + Maestro do Campo) a segunda nunca ligava. Agora cada uma tem
-- o próprio estado (ligada/cooldown) e os efeitos se somam: multiplicadores
-- (…Mult) multiplicam, o resto (AllBoost, PickupRadiusAdd…) soma.
local LiveEffect = {}       -- [player] = efeito combinado das contínuas ligadas
local LiveEffectActive = {} -- [player] = { [nome] = true } — pra avisar só na TRANSIÇÃO
local passivoReadyAt = {}   -- [player] = { [nome] = tick() } — cooldown de cada contínua
local Lentidao = {}         -- [player] = { Mult, Ate } — ⚠️ v111: A Zona desacelera quem está perto
local Impulso = {}          -- [player] = { Mult, Ate } — ⚠️ v111: arranque/colar

local function getCharacterRoot(player)
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function computeNoOpponentAhead(player, radius)
	local root = getCharacterRoot(player)
	if not root then return false end
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player then continue end
		if not player.Team or not other.Team or player.Team == other.Team then continue end
		local otherRoot = getCharacterRoot(other)
		if not otherRoot then continue end
		local toOther = otherRoot.Position - root.Position
		if toOther.Magnitude <= radius and toOther:Dot(root.CFrame.LookVector) > 0 then
			return false
		end
	end
	return true
end

local function combinarEfeitos(lista)
	if #lista == 0 then return nil end
	if #lista == 1 then return lista[1] end
	local c = {}
	for _, e in ipairs(lista) do
		for k, v in pairs(e) do
			if c[k] == nil then
				c[k] = v
			elseif typeof(v) == "number" and typeof(c[k]) == "number" then
				if string.sub(k, -4) == "Mult" then
					c[k] *= v
				elseif k == "ChanceSet" or string.sub(k, -4) == "Raio" then
					c[k] = math.max(c[k], v)
				else
					c[k] += v
				end
			end
		end
	end
	return c
end

task.spawn(function()
	while true do
		task.wait(0.25)
		for _, player in ipairs(Players:GetPlayers()) do
			local estado = LiveEffectActive[player] or {}
			LiveEffectActive[player] = estado
			local prontos = passivoReadyAt[player] or {}
			passivoReadyAt[player] = prontos
			local ligados = {}
			local vistos = {}
			local ctx = nil

			for _, name in ipairs(EquippedList[player] or {}) do
				local def = findInstinct(name)
				if not def or def.Trigger ~= "Instant" or vistos[name] then continue end
				vistos[name] = true
				local isActive = false
				if not (def.RoleRequired and player:GetAttribute("Role") ~= def.RoleRequired) then
					if not ctx then
						ctx = { HasPossession = _G.GetBallOwner and _G.GetBallOwner() == player }
						-- ⚠️ v5: a geometria de campo vem do BallController (dono dos gols)
						if _G.GetInstinctFieldContext then
							local field = _G.GetInstinctFieldContext(player)
							if field then
								for chave, valor in pairs(field) do
									if ctx[chave] == nil then ctx[chave] = valor end
								end
							end
						end
					end
					local c = def.Condition or {}
					if c.NoOpponentAheadRadius then
						ctx.NoOpponentAhead = computeNoOpponentAhead(player, c.NoOpponentAheadRadius)
					end
					isActive = conditionMet(def, player, ctx)
				end

				-- ⚠️ v5.2/v28: COOLDOWN de cada contínua (def.CooldownSeconds ou o
				-- da raridade) — conta a partir de quando ela DESLIGA.
				local instinctCooldown = def.CooldownSeconds
					or (Config.INSTINCT_COOLDOWN_BY_RARITY and Config.INSTINCT_COOLDOWN_BY_RARITY[def.Rarity])
				if instinctCooldown then
					if isActive then
						if prontos[name] and tick() < prontos[name] then isActive = false end
					elseif estado[name] then
						prontos[name] = tick() + instinctCooldown
					end
				end

				if isActive then
					local effect = def.Effect or {}
					if _G.IsInInstinctMode(player) then effect = amplifyEffect(effect) end
					table.insert(ligados, effect)
					-- ⚠️ v110: Armas que aceleram os COMPANHEIROS em volta
					if effect.TeamSpeedMult and _G.PulseTeamBuff then
						_G.PulseTeamBuff(player, effect.TeamRaio or 40, effect.TeamSpeedMult, 0.45)
					end
					-- ⚠️ v111: A Zona — quem está perto de você fica mais lento
					if effect.LentidaoRaio and effect.LentidaoMult then
						local root = getCharacterRoot(player)
						if root then
							for _, other in ipairs(Players:GetPlayers()) do
								if other ~= player and other.Team and player.Team and other.Team ~= player.Team then
									local r = getCharacterRoot(other)
									if r and (r.Position - root.Position).Magnitude <= effect.LentidaoRaio then
										Lentidao[other] = { Mult = effect.LentidaoMult, Ate = tick() + 0.45 }
									end
								end
							end
						end
					end
				end

				-- Avisa só na TRANSIÇÃO (ligou/desligou agora)
				if isActive ~= (estado[name] or false) then
					estado[name] = isActive or nil
					Remotes.InstinctFeedback:FireClient(player, isActive, name)
					setAuraActive(player, def, isActive, nil)
					-- (⚠️ v113: ligar uma Arma contínua não carrega mais o Flow)
				end

				-- ⚠️ v5: a ativa de um instinto contínuo é tentada enquanto a
				-- condição valer (ex.: Domínio segurando bola caindo perto)
				if isActive and def.AtivaAction and not def.AtivaSoNaTecla then
					tryRunAtiva(player, def)
				end
			end

			-- Arma trocada/desequipada com o efeito ligado: desliga
			for name in pairs(estado) do
				if not vistos[name] then
					estado[name] = nil
					Remotes.InstinctFeedback:FireClient(player, false, name)
					setAuraActive(player, findInstinct(name), false, nil)
				end
			end

			LiveEffect[player] = combinarEfeitos(ligados)
		end
	end
end)

_G.GetInstinctSpeedMultiplier = function(player)
	local effect = LiveEffect[player]
	-- ⚠️ v110: FlowVelocidade = multiplicador do Flow ativo (CosmeticosServer)
	local flow = player:GetAttribute("FlowVelocidade")
	local mult = ((effect and effect.SpeedMult) or 1) * (typeof(flow) == "number" and flow or 1)
	local lento = Lentidao[player]
	if lento then
		if tick() < lento.Ate then mult *= lento.Mult else Lentidao[player] = nil end
	end
	local imp = Impulso[player]
	if imp then
		if tick() < imp.Ate then mult *= imp.Mult else Impulso[player] = nil end
	end
	return mult
end

-- ⚠️ v111: impulso de velocidade de uma ativa (Arranque, Colar)
_G.ArmaImpulsoVelocidade = function(player, mult, duracao)
	Impulso[player] = { Mult = mult, Ate = tick() + duracao }
end

_G.GetInstinctStaminaRegenMultiplier = function(player)
	local effect = LiveEffect[player]
	return (effect and effect.StaminaRegenMult) or 1
end

_G.GetInstinctAllBoost = function(player)
	local effect = LiveEffect[player]
	return (effect and effect.AllBoost) or 0
end

-- ⚠️ v111: alcance extra de recepção das contínuas (Passo Furtivo, Leitura de
-- Passe, Domínio). O BallController chamava _G.CheckInstinct(plr, "Instant")
-- a cada quadro de bola solta — isso piscava o HUD, acendia a aura e ENCHIA o
-- medidor do Flow sem parar. Agora só lê o efeito que já está ligado.
_G.GetInstinctPickupRadiusAdd = function(player)
	local effect = LiveEffect[player]
	return (effect and effect.PickupRadiusAdd) or 0
end

-- ⚠️ v111: Defesa Zumbi — stun/queda duram menos (StunMult < 1)
_G.GetInstinctStunMult = function(player)
	local effect = LiveEffect[player]
	return (effect and effect.StunMult) or 1
end

-- ============================================================
-- ⚠️ v78 — INSTINTO DE BOTÃO (tecla R = slot 1, tecla H = slot 2)
-- A maior parte dos Instintos é passiva e ignora isto. Os que têm
-- Tecla = "R" (campo mantém o nome antigo, mas hoje significa "precisa de
-- aperto manual") NÃO disparam sozinhos: existem só quando o jogador
-- aperta a tecla DO SLOT onde estão equipados — R pro slot 1, T pro slot
-- 2 (ver PulseInput.local.luau). Antes só existia 1 slot ativo por vez,
-- então R bastava; agora que todo mundo sempre tem 2 Armas ativas ao
-- mesmo tempo (o 3º slot é só reserva, ver PlayerSystems.legacy.luau),
-- as duas podem precisar de aperto manual ao mesmo tempo — por isso o
-- cliente manda QUAL slot apertou, e aqui a gente olha SÓ aquele slot,
-- em vez de escanear a lista toda. R/T valem igual pra goleiro e jogador
-- de linha — Q e E ficaram livres justamente pra não brigar com os
-- mergulhos diagonais do goleiro.
-- ============================================================
Remotes.ActivateInstinct.OnServerEvent:Connect(function(player, aimPoint, slotIndex)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	-- ⚠️ v67: guarda a mira que o cliente mandou no MESMO lugar que a
	-- Hissatsu usa (LastAimPoint, via _G.SetPulseAimPoint). Sem isto, um
	-- Instinto de chute (Chute Direto) lia o ponto sobrado da última
	-- Hissatsu e saía em qualquer direção — ver PulseInput.local.luau.
	if typeof(aimPoint) == "Vector3" and _G.SetPulseAimPoint then
		_G.SetPulseAimPoint(player, aimPoint)
	end
	-- ⚠️ v78: slotIndex vem do cliente (1=R, 2=H). Qualquer coisa que não
	-- seja exatamente 2 cai em 1 (cliente antigo/desatualizado, ou mobile
	-- chamando sem argumento — continua funcionando igual antes, só que
	-- agora fixo no slot 1 em vez de escanear a lista toda).
	local slot = (slotIndex == 2) and 2 or 1
	local candidato = (EquippedList[player] or {})[slot]
	local name, def
	if candidato then
		local candidatoDef = findInstinct(candidato)
		if candidatoDef and candidatoDef.Tecla == "R"
			and not (candidatoDef.RoleRequired and player:GetAttribute("Role") ~= candidatoDef.RoleRequired) then
			name, def = candidato, candidatoDef
		end
	end
	if not name or not def then return end -- esse slot não tem Instinto de tecla ativa (a maioria é passiva, R/T não fazem nada — normal)
	local teclaLabel = (slot == 2) and "T" or "R"

	-- Monta o contexto na hora do aperto. Tudo que a condição pode
	-- perguntar (distância do gol, tempo desde que recebeu, metade do
	-- campo...) vem daqui — ver _G.GetInstinctFieldContext no
	-- BallController.
	local ctx = {}
	if _G.GetInstinctFieldContext then
		ctx = _G.GetInstinctFieldContext(player) or {}
	end
	local c = def.Condition or {}
	if c.NoOpponentAheadRadius then
		ctx.NoOpponentAhead = computeNoOpponentAhead(player, c.NoOpponentAheadRadius)
	end

	-- ⚠️ v5.2: DIAGNÓSTICO. Antes, apertar R fora de hora não fazia
	-- absolutamente nada e não dizia nada — era impossível saber se o
	-- Instinto estava quebrado ou se era só a condição que não bateu.
	-- Agora todo aperto que NÃO vira jogada explica o motivo no console do
	-- servidor (Studio), com os números reais.
	-- ⚠️ v111: a arma pode ter uma condição só pra tecla (AtivaCondition) e
	-- outra pro passivo (Condition) — ex.: Monstro do Drible.
	local defTecla = def
	if def.AtivaCondition then
		defTecla = setmetatable({ Condition = def.AtivaCondition }, { __index = def })
	end
	if not conditionMet(defTecla, player, ctx) then
		local motivo = "condição não bateu"
		local c = defTecla.Condition or {}
		if c.MaxDistanceToGoal and ctx.DistanceToGoal then
			motivo = string.format("longe do gol (%.1f, precisa <= %.1f)", ctx.DistanceToGoal, c.MaxDistanceToGoal)
		elseif c.MaxSecondsAfterReceive and ctx.SecondsAfterReceive then
			motivo = string.format("faz %.2fs que você recebeu (precisa <= %.2fs)", ctx.SecondsAfterReceive, c.MaxSecondsAfterReceive)
		elseif c.RequireInsideEnemyArea and not ctx.InsideEnemyArea then
			motivo = "fora da área adversária (precisa estar dentro)"
		elseif c.RequirePossession and not ctx.HasPossession then
			motivo = "precisa estar com a bola"
		elseif c.RequireNoPossession and ctx.HasPossession then
			motivo = "só sem a bola"
		elseif c.RequireOwnArea and not ctx.InOwnArea then
			motivo = "só dentro da sua área"
		elseif c.DefendingHalf and ctx.AttackingHalf ~= false then
			motivo = "só no seu campo"
		elseif c.CarrierMaxDistance then
			motivo = string.format("nenhum adversário com a bola a até %d studs", c.CarrierMaxDistance)
		end
		-- ⚠️ v5.4: PEDIDO — "nunca consegui acertar o R do Predador da
		-- Área". Antes o motivo só ia pro console do servidor (só o HOST
		-- via no Studio); quem está jogando como cliente nunca via nada.
		-- Agora o motivo também vai pro HUD do próprio jogador (ver
		-- AbilityHUD.local.luau).
		Remotes.InstinctFeedback:FireClient(player, false, name, motivo)
		print(string.format("🧠 %s apertou %s com '%s' — não rolou: %s", player.Name, teclaLabel, name, motivo))
		return
	end

	local aconteceu, motivoAtiva = tryRunAtiva(player, def)
	if not aconteceu then
		-- A condição bateu, mas a AÇÃO não pôde acontecer (cooldown, ou
		-- não havia bola cabeceável na janela).
		local motivo = "em cooldown"
		local readyAt = prontaEm(player, def.Name)
		if readyAt and tick() < readyAt and not debugNoCooldown[player] then
			motivo = string.format("em cooldown (%.0fs)", readyAt - tick())
		else
			motivo = motivoAtiva or "a jogada não era possível agora"
			if def.AtivaAction == "Header" and _G.PulseHeaderFailReason then
				motivo = _G.PulseHeaderFailReason(player, def.AtivaEffect or {})
			end
		end
		Remotes.InstinctFeedback:FireClient(player, false, name, motivo) -- ⚠️ v5.4: idem — também pro HUD, não só o console
		print(string.format("🧠 %s apertou %s com '%s' — condição OK, mas: %s", player.Name, teclaLabel, name, motivo))
		return
	end

	setAuraActive(player, def, true, AURA_PULSE_SECONDS)
	-- ⚠️ v111: 4º parâmetro = cooldown da ativa, pro HUD contar
	local cd = (not debugNoCooldown[player]) and prontaEm(player, def.Name) and (prontaEm(player, def.Name) - tick()) or nil
	Remotes.InstinctFeedback:FireClient(player, true, name, nil, cd)
	task.delay(1.5, function()
		Remotes.InstinctFeedback:FireClient(player, false, name)
	end)
	addInstinctCharge(player)
end)

Players.PlayerRemoving:Connect(function(player)
	EquippedList[player] = nil
	debugNoCooldown[player] = nil
	LiveEffect[player] = nil
	LiveEffectActive[player] = nil
	passivoReadyAt[player] = nil
	Lentidao[player] = nil
	Impulso[player] = nil
	InstinctCharge[player] = nil
	InstinctModeState[player] = nil
	FlowsUsados[player] = nil
	-- ⚠️ v5: a aura vive dentro do Character, mas a referência fica aqui —
	-- sem isso a tabela cresce pra sempre num servidor de longa duração.
	local aura = auraByPlayer[player]
	if aura then aura:Destroy() end
	auraByPlayer[player] = nil
	ativaReadyAt[player] = nil
	gambleState[player] = nil -- ⚠️ v5.4: estado da jogada de sorte do Apostador
end)

print("✅ InstinctController carregado.")
