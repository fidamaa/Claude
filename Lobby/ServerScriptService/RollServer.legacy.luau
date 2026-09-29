--[[
	RollServer - Créditos de Roll (Pulso/Instinto)
	LOCAL: ServerScriptService (place Lobby)

	Dono da contagem de "RollCredits" do jogador (quantos rolls ele tem
	guardados pra gastar na tela de Roll — ver RollClient.lua). É o único
	lugar que aumenta/diminui esse número; a Loja (ShopServer.lua) e a
	compra com Robux (ProcessReceipt aqui embaixo) só chamam
	_G.AddRollCredits.

	ATUALIZADO: o sorteio (qual Pulso/Instinto saiu) agora é 100%
	SERVIDOR — RollAbility (RemoteFunction abaixo) gasta 1 crédito,
	sorteia por peso de raridade em cima de PulseInstinctData.lua, guarda
	no histórico (OwnedPulses/OwnedInstincts) e AUTO-EQUIPA (o mais
	recente sorteado de cada tipo vira o que vai pra partida — ainda não
	existe uma tela de troca de equipado; ver EquippedPulse/
	EquippedInstinct em PlayerDataManager.lua). RollClient.lua chama esse
	remote em vez de sortear localmente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local LobbyConfig = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local PulseInstinctData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))

-- ========================================
-- Remotes
-- ========================================
local eventsFolder = ReplicatedStorage:FindFirstChild("RollEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "RollEvents"
	eventsFolder.Parent = ReplicatedStorage
end

local function getOrCreate(className, name)
	local existing = eventsFolder:FindFirstChild(name)
	if existing then return existing end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = eventsFolder
	return instance
end

local updateRollCreditsEvent = getOrCreate("RemoteEvent", "UpdateRollCredits")
local getRollCreditsFunc = getOrCreate("RemoteFunction", "GetRollCredits")
local consumeRollCreditFunc = getOrCreate("RemoteFunction", "ConsumeRollCredit")
local rollAbilityFunc = getOrCreate("RemoteFunction", "RollAbility")
-- NOVO: pra tela de Roll mostrar o que já estava equipado ANTES de girar
-- de novo — a UI (RollClient.lua) só preenchia nome/descrição depois de
-- um spin, então ao sair e voltar (ou só reabrir a tela) parecia que o
-- Pulso/Instinto tinha "resetado", mesmo estando salvo certinho no
-- DataStore o tempo todo. Ver uso em RollClient.lua (chamado 1x ao
-- carregar a tela).
local getEquippedAbilitiesFunc = getOrCreate("RemoteFunction", "GetEquippedAbilities")
-- ⚠️ v78 — NOVO: troca o conteúdo de 2 slots (ex.: puxar o que está no
-- slot reserva pro slot 1/2 ativo, ou só reordenar os 2 ativos entre si).
-- Ver _G ... uso em RollClient.local.luau (clique num slot pra escolher
-- alvo + botão de "trocar com reserva").
local swapSlotFunc = getOrCreate("RemoteFunction", "SwapAbilitySlot")

-- MOVIDO: a compra de Roll com dinheiro SAIU da Loja (ShopServer.lua) e
-- entrou direto aqui, dentro da tela de Roll — o botão fica dentro de
-- RollClient.lua agora, em vez de um card na Loja. Continua usando o
-- mesmo preço de sempre (LobbyConfig.SHOP.Roll.Cost).
local buyRollFunc = getOrCreate("RemoteFunction", "BuyRoll")

-- ========================================
-- NumberValue local (igual o padrão do MoneyManager.lua) — carregado a
-- partir do mesmo payload único do PlayerDataManager, sem DataStore
-- próprio.
-- ========================================
local function loadRollCredits(player)
	-- FIX CRÍTICO (mesmo bug do MoneyManager.lua): WaitForChild só espera
	-- a INSTANCE "DataLoaded" existir, não o Value virar true — ela nasce
	-- com Value=false já no início do carregamento, então isso sempre
	-- seguia adiante com os dados de verdade ainda não chegados,
	-- _G.GetPlayerData retornava nil, e o RollCredits nascia sempre 0 —
	-- mesmo se o jogador tivesse rolls comprados salvos. Como nada
	-- re-sincroniza depois, qualquer compra nova (Loja/Robux) somava em
	-- cima desse 0 errado e a próxima save SOBRESCREVIA o valor real
	-- salvo — os rolls "sumiam".
	local dataLoaded = player:WaitForChild("DataLoaded", 15)
	if dataLoaded and not dataLoaded.Value then
		dataLoaded.Changed:Wait()
	end
	if not dataLoaded or not dataLoaded.Value then
		warn(string.format("⚠️ RollServer: dados não carregados a tempo para %s", player.Name))
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	local creditsValue = (playerData and type(playerData.RollCredits) == "number") and playerData.RollCredits or 0

	if playerData and type(playerData.RollCredits) ~= "number" then
		playerData.RollCredits = creditsValue
	end

	local credits = Instance.new("IntValue")
	credits.Name = "RollCredits"
	credits.Value = creditsValue
	credits.Parent = player

	updateRollCreditsEvent:FireClient(player, creditsValue)

	-- ⚠️ v76 — CRÉDITO DE ROLL PAGO COM ROBUX, SEPARADO DO CRÉDITO NORMAL.
	-- PEDIDO: o Roll de Robux tem chances MELHORES (0% Comum/Raro, 30%
	-- Épico, 40% Lendário, 30% Mítico — ver Config.ROBUX_ROLL_RARITY_
	-- WEIGHTS) que o roll normal (65/25/7/2.5/0.5). Pra aplicar pesos
	-- diferentes na hora de girar, o servidor precisa saber DE ONDE veio
	-- aquele crédito — um contador só (RollCredits) não guarda isso.
	-- Mesmo padrão exato do RollCredits acima, espelhado.
	local creditsRobuxValue = (playerData and type(playerData.RollCreditsRobux) == "number") and playerData.RollCreditsRobux or 0
	if playerData and type(playerData.RollCreditsRobux) ~= "number" then
		playerData.RollCreditsRobux = creditsRobuxValue
	end
	local creditsRobux = Instance.new("IntValue")
	creditsRobux.Name = "RollCreditsRobux"
	creditsRobux.Value = creditsRobuxValue
	creditsRobux.Parent = player
	updateRollCreditsEvent:FireClient(player, creditsValue, creditsRobuxValue)
end

local function setupRollCreditsListener(player)
	local credits = player:WaitForChild("RollCredits", 10)
	local creditsRobux = player:WaitForChild("RollCreditsRobux", 10)
	if not credits or not creditsRobux then
		warn(string.format("❌ RollServer: RollCredits/RollCreditsRobux não encontrado para %s após 10s", player.Name))
		return
	end

	local function broadcast()
		updateRollCreditsEvent:FireClient(player, credits.Value, creditsRobux.Value)
	end

	credits.Changed:Connect(function(newValue)
		if newValue < 0 then
			warn(string.format("⚠️ RollCredits negativo detectado para %s! Corrigindo...", player.Name))
			credits.Value = 0
			return
		end
		local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
		if playerData then playerData.RollCredits = newValue end
		broadcast()
	end)

	creditsRobux.Changed:Connect(function(newValue)
		if newValue < 0 then
			warn(string.format("⚠️ RollCreditsRobux negativo detectado para %s! Corrigindo...", player.Name))
			creditsRobux.Value = 0
			return
		end
		local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
		if playerData then playerData.RollCreditsRobux = newValue end
		broadcast()
	end)
end

Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		loadRollCredits(player)
		setupRollCreditsListener(player)
	end)
end)

-- ========================================
-- Funções Globais
-- ========================================
_G.AddRollCredits = function(player, amount)
	local credits = player:FindFirstChild("RollCredits")
	if not credits then
		warn(string.format("❌ RollCredits não encontrado para %s", player.Name))
		return false
	end

	credits.Value = credits.Value + amount

	print(string.format("🎲 %s recebeu %d roll(s) (Total: %d)", player.Name, amount, credits.Value))

	task.spawn(function()
		if _G.SavePlayerData then
			_G.SavePlayerData(player)
		end
	end)

	return true
end

_G.GetRollCredits = function(player)
	local credits = player:FindFirstChild("RollCredits")
	return credits and credits.Value or 0
end

-- ⚠️ v76: par exato de AddRollCredits/GetRollCredits, só que pro crédito
-- comprado com Robux de verdade (ver nota em loadRollCredits acima).
_G.AddRollCreditsRobux = function(player, amount)
	local credits = player:FindFirstChild("RollCreditsRobux")
	if not credits then
		warn(string.format("❌ RollCreditsRobux não encontrado para %s", player.Name))
		return false
	end
	credits.Value = credits.Value + amount
	print(string.format("🎲✨ %s recebeu %d roll(s) DE ROBUX (Total: %d)", player.Name, amount, credits.Value))
	task.spawn(function()
		if _G.SavePlayerData then _G.SavePlayerData(player) end
	end)
	return true
end

_G.GetRollCreditsRobux = function(player)
	local credits = player:FindFirstChild("RollCreditsRobux")
	return credits and credits.Value or 0
end

-- ========================================
-- RemoteFunctions pro cliente
-- ========================================
-- ⚠️ v76: retorna os DOIS créditos agora (money, robux) — antes só
-- devolvia o normal, e o cliente nunca soube que existia um segundo pool
-- (ver rollCreditsRobux em RollClient.local.luau).
getRollCreditsFunc.OnServerInvoke = function(player)
	return _G.GetRollCredits(player), _G.GetRollCreditsRobux(player)
end

-- Gasta 1 crédito (chamado pelo RollClient ANTES de girar) — devolve
-- true/false. É a única coisa autoritativa hoje: se o jogador tem ou não
-- direito a girar (o resultado em si ainda é local, ver nota no topo).
consumeRollCreditFunc.OnServerInvoke = function(player)
	local credits = player:FindFirstChild("RollCredits")
	if not credits or credits.Value < 1 then
		return false
	end

	credits.Value -= 1

	task.spawn(function()
		if _G.SavePlayerData then
			_G.SavePlayerData(player)
		end
	end)

	return true
end

-- ========================================
-- SORTEIO (100% servidor) — por peso de raridade (PulseInstinctData.
-- RarityWeights), dentro da pool certa (Pulses ou Instincts).
-- ========================================
-- ⚠️ NOVO: luckBoost (Loja > Boosts > "Boost de Sorte no Roll") — quando
-- true, dobra o peso de Epic/Legendary/Mythic e reduz o de Common/Rare
-- pra metade, só nesse sorteio. Consumido 1x por rolagem (ver
-- playerData.Boosts.LuckRollsRemaining em rollAbilityFunc abaixo).
local LUCK_BOOST_MULT = {
	Common = 0.5,
	Rare = 0.5,
	Epic = 2,
	Legendary = 2,
	Mythic = 2,
}

-- ⚠️ v76: `pesos` agora é PARÂMETRO (era sempre PulseInstinctData.
-- RarityWeights direto) — o roll de Robux usa Config.ROBUX_ROLL_RARITY_
-- WEIGHTS (0% Comum/Raro, 30/40/30% Épico/Lendário/Mítico) em vez da
-- tabela normal. luckBoost (Boost de Sorte) só faz sentido no roll
-- normal — no de Robux já é bom o bastante e não pode faltar Épico+ pra
-- multiplicar em cima.
local function weightedRandom(pool, pesos, luckBoost)
	local totalWeight = 0
	for _, def in ipairs(pool) do
		local weight = pesos[def.Rarity] or 0
		if luckBoost then
			weight *= (LUCK_BOOST_MULT[def.Rarity] or 1)
		end
		totalWeight += weight
	end
	if totalWeight <= 0 then
		-- pesos zerados pra tudo que existe na pool (não deveria
		-- acontecer com as tabelas atuais, mas evita dividir por zero se
		-- alguém zerar tudo por engano) — cai pro peso normal.
		return weightedRandom(pool, PulseInstinctData.RarityWeights, luckBoost)
	end
	local roll = math.random() * totalWeight
	local acc = 0
	for _, def in ipairs(pool) do
		local weight = pesos[def.Rarity] or 0
		if luckBoost then
			weight *= (LUCK_BOOST_MULT[def.Rarity] or 1)
		end
		acc += weight
		if roll <= acc then
			return def
		end
	end
	return pool[#pool] -- fallback (arredondamento de ponto flutuante)
end

-- ⚠️ v76 — quantos slots o jogador tem destravados pra cada tipo: 2 de
-- graça sempre, +1 se comprou o Developer Product daquele tipo (ver
-- Config.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID/..._INSTINCT_..., creditado
-- em ProcessReceipt mais abaixo).
-- ⚠️ v102 — PEDIDO: "dois slots ativos, como está aí, e dois slots
-- reservas... a pessoa só vai ter disponível um slot reserva pra poder
-- guardar, e um slot pago". Por tipo (Hissatsu e Arma):
--   1, 2 = ATIVOS (vão pra partida — ver PlayerSystems no place Game, que
--          só lê 1 e 2);
--   3    = RESERVA de graça (todo mundo tem);
--   4    = RESERVA PAGA (ExtraPulseSlot/ExtraInstinctSlot, Robux).
-- Quem já tinha comprado o slot extra antes (era o 3) continua com o que
-- guardou no 3 (agora grátis) e ganha o 4 destravado.
local function slotsDestravados(playerData, kind)
	local extra = (kind == "Pulse") and playerData.ExtraPulseSlot or playerData.ExtraInstinctSlot
	return extra and 4 or 3
end

local function camposDoSlot(kind)
	if kind == "Pulse" then
		return { "EquippedPulse1", "EquippedPulse2", "EquippedPulse3", "EquippedPulse4" }
	end
	return { "EquippedInstinct1", "EquippedInstinct2", "EquippedInstinct3", "EquippedInstinct4" }
end

-- ⚠️ v78 — CORREÇÃO: antes equipava por FIFO (o resultado novo sempre
-- virava o slot 1, empurrando os outros pra baixo). O usuário pediu pra
-- SER JUSTO: só 2 slots ficam ATIVOS em partida pra todo mundo sempre
-- (ver PlayerSystems.legacy.luau no place da partida, que só lê slot 1 e
-- 2) — o 3º slot (comprado com Robux) é RESERVA/armazenamento, nunca
-- ativo. Por isso agora quem escolhe em QUAL slot o resultado do sorteio
-- entra é o próprio jogador (targetSlot, mandado pelo RollClient — a UI
-- deixa clicar no slot 1, 2 ou reserva ANTES de girar). Valida contra os
-- slots destravados daquele jogador; fora disso, cai no slot 1.
local function equiparNoSlot(playerData, kind, nome, targetSlot)
	local campos = camposDoSlot(kind)
	local n = slotsDestravados(playerData, kind)
	local slot = (type(targetSlot) == "number" and targetSlot >= 1 and targetSlot <= n) and math.floor(targetSlot) or 1
	playerData[campos[slot]] = nome
	return slot
end

-- kind: "Pulse" | "Instinct". targetSlot: 1/2 (ativo) ou 3 (reserva, só
-- se ExtraPulseSlot/ExtraInstinctSlot destravado) — em qual slot o
-- resultado do sorteio vai entrar; default 1. useRobux: true = gasta 1
-- crédito de Robux (chances melhores, ver Config.ROBUX_ROLL_RARITY_
-- WEIGHTS) — false/omitido = gasta 1 crédito normal (dinheiro). Sorteia,
-- guarda no histórico e equipa no slot escolhido. Retorna { Name,
-- Rarity, FromRobux, Slot } ou false + motivo.
-- ⚠️ v78 — CORREÇÃO: antes o servidor decidia sozinho gastar Robux
-- primeiro sempre que o jogador tinha (usarRobux = creditsRobux>=1,
-- automático). O usuário pediu um botão SEPARADO ("símbolozinho de
-- Robux" do lado de cada spin normal) que rola especificamente na pool
-- de Robux — ou seja, agora é o CLIENTE que escolhe explicitamente qual
-- pool gastar (useRobux), e o botão normal NUNCA mais toca no crédito de
-- Robux sozinho.
rollAbilityFunc.OnServerInvoke = function(player, kind, targetSlot, useRobux)
	if kind ~= "Pulse" and kind ~= "Instinct" then
		return false, "Tipo inválido"
	end

	local credits = player:FindFirstChild("RollCredits")
	local creditsRobux = player:FindFirstChild("RollCreditsRobux")
	local usarRobux = useRobux == true
	if usarRobux then
		if not creditsRobux or creditsRobux.Value < 1 then
			return false, "Sem rolls de Robux"
		end
	else
		if not credits or credits.Value < 1 then
			return false, "Sem rolls"
		end
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then
		return false, "Dados não carregados"
	end

	local pool = (kind == "Pulse") and PulseInstinctData.Pulses or PulseInstinctData.Instincts

	-- ⚠️ v6: Data.Pulses tem 15 Pulsos "Hissatsu" agora (era vazio de
	-- propósito na v5 — ver o cabeçalho do PulseInstinctData.luau). Esse
	-- guard continua aqui como rede de segurança genérica: sortear de
	-- uma lista vazia (Pulse OU Instinct, se um dia esvaziar de novo)
	-- daria erro e AINDA gastaria o crédito do jogador, então recusa
	-- antes de descontar qualquer coisa.
	if #pool == 0 then
		return false, "Essa categoria não está disponível no momento."
	end

	local pesos = usarRobux and LobbyConfig.ROBUX_ROLL_RARITY_WEIGHTS or PulseInstinctData.RarityWeights
	local luckBoost = (not usarRobux) and type(playerData.Boosts) == "table" and (playerData.Boosts.LuckRollsRemaining or 0) > 0
	local result = weightedRandom(pool, pesos, luckBoost)
	if luckBoost then
		playerData.Boosts.LuckRollsRemaining -= 1
	end

	if usarRobux then
		creditsRobux.Value -= 1
	else
		credits.Value -= 1
	end

	if kind == "Pulse" then
		table.insert(playerData.OwnedPulses, result.Name)
	else
		table.insert(playerData.OwnedInstincts, result.Name)
	end
	local slotUsado = equiparNoSlot(playerData, kind, result.Name, targetSlot)

	print(string.format("🎲%s %s sorteou %s '%s' (%s) e equipou no slot %d.", usarRobux and "✨" or "", player.Name, kind, result.Name, result.Rarity, slotUsado))

	task.spawn(function()
		if _G.SavePlayerData then _G.SavePlayerData(player) end
	end)

	return true, { Name = result.Name, Rarity = result.Rarity, FromRobux = usarRobux, Slot = slotUsado }
end

-- ⚠️ v78 — NOVO: troca o que está em 2 slots entre si (ex.: puxar a Arma
-- que está guardada no slot 3/reserva pro slot 1 ou 2 ativo, jogando o
-- que tava lá pra reserva — ou só reordenar os 2 ativos). Não sorteia
-- nada, não gasta crédito — é só reorganização do que o jogador já tem
-- equipado. Valida os dois slots contra quantos estão destravados.
swapSlotFunc.OnServerInvoke = function(player, kind, slotA, slotB)
	if kind ~= "Pulse" and kind ~= "Instinct" then
		return false, "Tipo inválido"
	end
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then
		return false, "Dados não carregados"
	end
	local n = slotsDestravados(playerData, kind)
	slotA, slotB = math.floor(tonumber(slotA) or -1), math.floor(tonumber(slotB) or -1)
	if slotA < 1 or slotA > n or slotB < 1 or slotB > n or slotA == slotB then
		return false, "Slot inválido"
	end

	local campos = camposDoSlot(kind)
	playerData[campos[slotA]], playerData[campos[slotB]] = playerData[campos[slotB]], playerData[campos[slotA]]

	print(string.format("🔄 %s trocou %s: slot %d <-> slot %d", player.Name, kind, slotA, slotB))

	task.spawn(function()
		if _G.SavePlayerData then _G.SavePlayerData(player) end
	end)

	return true, {
		Pulse1 = playerData.EquippedPulse1, Pulse2 = playerData.EquippedPulse2, Pulse3 = playerData.EquippedPulse3, Pulse4 = playerData.EquippedPulse4,
		Instinct1 = playerData.EquippedInstinct1, Instinct2 = playerData.EquippedInstinct2, Instinct3 = playerData.EquippedInstinct3, Instinct4 = playerData.EquippedInstinct4,
		PulseSlots = slotsDestravados(playerData, "Pulse"), InstinctSlots = slotsDestravados(playerData, "Instinct"),
	}
end

-- ========================================
-- NOVO: devolve os nomes já equipados pro cliente popular a tela de Roll
-- assim que ela abre, sem precisar girar de novo pra "reaparecer". O
-- cliente já sabe resolver Rarity/Description a partir do Name (mesma
-- lista local usada pra mostrar o resultado de um spin) — aqui só manda
-- o que está salvo, mais quantos slots de cada tipo estão destravados.
-- ========================================
getEquippedAbilitiesFunc.OnServerInvoke = function(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then
		return { PulseSlots = 3, InstinctSlots = 3 }
	end

	return {
		Pulse1 = playerData.EquippedPulse1,
		Pulse2 = playerData.EquippedPulse2,
		Pulse3 = playerData.EquippedPulse3,
		Pulse4 = playerData.EquippedPulse4,
		Instinct1 = playerData.EquippedInstinct1,
		Instinct2 = playerData.EquippedInstinct2,
		Instinct3 = playerData.EquippedInstinct3,
		Instinct4 = playerData.EquippedInstinct4,
		PulseSlots = slotsDestravados(playerData, "Pulse"),
		InstinctSlots = slotsDestravados(playerData, "Instinct"),
	}
end

-- ========================================
-- BuyRoll: compra 1 crédito de roll com DINHEIRO do jogo (repetível, sem
-- "maxed out"). Antes vivia em ShopServer.lua (era um card na Loja);
-- agora é chamado direto pelo botão dedicado dentro da tela de Roll.
-- ========================================
buyRollFunc.OnServerInvoke = function(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return false, "Dados não carregados" end

	if not _G.RemoveMoney then
		warn("❌ RollServer: MoneyManager não carregado")
		return false, "Indisponível no momento"
	end

	local cost = LobbyConfig.SHOP.Roll.Cost
	if not _G.RemoveMoney(player, cost) then
		return false, "Dinheiro insuficiente"
	end

	_G.AddRollCredits(player, 1)

	print(string.format("🎲 %s comprou 1 roll por $%d (tela de Roll)", player.Name, cost))

	return true, { RollCredits = _G.GetRollCredits(player), Cost = cost }
end

-- ========================================
-- COMPRA COM ROBUX (Developer Product, 40 Robux por roll)
-- ========================================
-- ⚠️ MUDOU: não atribui mais MarketplaceService.ProcessReceipt
-- diretamente — agora a Loja também vende produtos com Robux (pacotes de
-- dinheiro, destravar slots), e o Roblox só permite UM handler de
-- ProcessReceipt no jogo inteiro (atribuir de novo sobrescreve o
-- anterior sem aviso). Registra através do dispatcher central — ver
-- RobuxProducts.legacy.luau.
task.spawn(function()
	local waited = 0
	while not _G.RegisterRobuxProduct and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end
	if not _G.RegisterRobuxProduct then
		warn("❌ RollServer: RobuxProducts.legacy.luau não carregou a tempo — Roll com Robux desativado.")
		return
	end

	-- ⚠️ v76: credita RollCreditsRobux agora (era AddRollCredits, o pool
	-- normal) — é essa separação que deixa o roll de Robux usar Config.
	-- ROBUX_ROLL_RARITY_WEIGHTS (0% Comum/Raro, 30/40/30% Épico/Lendário/
	-- Mítico) em vez dos pesos normais. Ver rollAbilityFunc acima.
	_G.RegisterRobuxProduct(LobbyConfig.ROBUX_ROLL_PRODUCT_ID, function(player, receiptInfo)
		local success = _G.AddRollCreditsRobux(player, 1)
		if success then
			print(string.format("💎 %s comprou 1 roll DE ROBUX (chances melhores — Developer Product %d)", player.Name, receiptInfo.ProductId))
		end
		return success
	end)

	-- ⚠️ v76 — 3º SLOT DE HISSATSU/ARMA, COMPRADO COM ROBUX.
	-- PEDIDO: "inclua mais um slot pra cada um que será comprado com
	-- robux." Flag permanente (não consumível) — uma vez comprado, fica
	-- destravado pra sempre (mesmo padrão de UnlockSlot pros slots de
	-- personagem, só que via Robux em vez de dinheiro).
	_G.RegisterRobuxProduct(LobbyConfig.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID, function(player, receiptInfo)
		local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
		if not playerData then return false end
		playerData.ExtraPulseSlot = true
		if _G.RequestSave then _G.RequestSave(player) end
		print(string.format("💎 %s destravou a RESERVA PAGA (slot 4) de HISSATSU com Robux (Developer Product %d)", player.Name, receiptInfo.ProductId))
		return true
	end)

	_G.RegisterRobuxProduct(LobbyConfig.ROBUX_EXTRA_INSTINCT_SLOT_PRODUCT_ID, function(player, receiptInfo)
		local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
		if not playerData then return false end
		playerData.ExtraInstinctSlot = true
		if _G.RequestSave then _G.RequestSave(player) end
		print(string.format("💎 %s destravou a RESERVA PAGA (slot 4) de ARMA com Robux (Developer Product %d)", player.Name, receiptInfo.ProductId))
		return true
	end)
end)

if LobbyConfig.ROBUX_ROLL_PRODUCT_ID == 0 then
	warn("⚠️ RollServer: Config.ROBUX_ROLL_PRODUCT_ID ainda está em 0 — crie o Developer Product de 40 Robux no Studio e cole o Id em LobbyConfig.lua (o roll com Robux não vai funcionar até isso ser feito).")
end

print("✅ RollServer carregado (créditos de roll: dinheiro via Loja + Robux via Developer Product).")
