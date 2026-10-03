--[[
	MatchDataTransfer - Sistema de Transferência de Dados Entre Places
	COLOQUE NO LOBBY (ServerScriptService)
	
	✅ Prepara dados do jogador antes de entrar na partida
	✅ Salva tudo no DataStore antes do teleporte
	✅ Sistema de retry para garantir que nada seja perdido
	
	IMPORTANTE: Este script trabalha em conjunto com o LobbyManager
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PulseInstinctData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local MATCH_DATA_STORE_NAME = "MatchTransferData_V1"
local SAVE_TIMEOUT = 10  -- Tempo máximo para salvar antes do teleporte
local MAX_RETRY_ATTEMPTS = 3

-- DataStore para transferência
local matchDataStore = DataStoreService:GetDataStore(MATCH_DATA_STORE_NAME)

-- ========================================
-- ⚠️ v10: POSIÇÃO DE LINHA SEM SELEÇÃO MANUAL — pedido: "remova a opção
-- de selecionar role no lobby [DF/MF/FW], insira isso no matchmaking...
-- pessoas com esses determinados pulsos têm prioridade pra cair em
-- determinada posição, alguém com pulso de defesa tem prioridade pra
-- cair como defensor". Só GK continua sendo escolha manual (checkbox, ver
-- CharacterClient.local.luau) — activeSlot.Role agora só guarda "GK" ou
-- "LINE" (ver PlayerDataManager.legacy.luau -> setSlotRoleFunc). Quando
-- não é GK, a posição PREFERIDA (usada só como sugestão de formação, ver
-- MatchController.legacy.luau no place Game — nunca trava nada, sempre
-- cai no sorteio/overflow normal se não bater) vem de qual dos Pulsos
-- (Hissatsu) equipados combina melhor com qual posição (ver
-- Data.GetPulsePositionHintByName em PulseInstinctData.luau).
-- ========================================
-- ⚠️ v104 — PEDIDO: "eu já entrei algumas vezes na partida como GK mesmo
-- sem Hissatsu de GK... coloca que eu não entro como GK se eu não marcar que
-- eu quero ser GK. A não ser que as minhas DUAS Hissatsus sejam de GK."
-- O bug: bastava UMA Hissatsu de goleiro equipada (hint "GK") pra posição
-- sugerida virar GK. Agora GK só com a marcação (activeSlot.Role == "GK")
-- ou com as DUAS Hissatsus ativas de goleiro; um hint "GK" sozinho é
-- ignorado (a outra Hissatsu decide, ou cai no sorteio normal).
local function querSerGK(activeSlot, playerData)
	if activeSlot and activeSlot.Role == "GK" then return true end
	local hint1 = PulseInstinctData.GetPulsePositionHintByName(playerData.EquippedPulse1)
	local hint2 = PulseInstinctData.GetPulsePositionHintByName(playerData.EquippedPulse2)
	return hint1 == "GK" and hint2 == "GK"
end

local function derivePreferredRole(activeSlot, playerData)
	if querSerGK(activeSlot, playerData) then return "GK" end

	local hint1 = PulseInstinctData.GetPulsePositionHintByName(playerData.EquippedPulse1)
	local hint2 = PulseInstinctData.GetPulsePositionHintByName(playerData.EquippedPulse2)
	if hint1 == "GK" then hint1 = nil end
	if hint2 == "GK" then hint2 = nil end

	if hint1 and hint1 == hint2 then return hint1 end
	if hint1 and not hint2 then return hint1 end
	if hint2 and not hint1 then return hint2 end
	if hint1 and hint2 then
		-- os dois Pulsos equipados puxam pra posições diferentes — sorteia
		-- entre as duas em vez de sempre priorizar o Slot 1.
		return (math.random(2) == 1) and hint1 or hint2
	end

	return nil -- nenhum Pulso equipado com posição definida — cai no overflow normal (ver MatchController.legacy.luau, place Game)
end

-- ⚠️ v104: GK automático = as DUAS Hissatsus ativas são de goleiro
_G.GKAutomaticoPorHissatsu = function(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return false end
	local hint1 = PulseInstinctData.GetPulsePositionHintByName(playerData.EquippedPulse1)
	local hint2 = PulseInstinctData.GetPulsePositionHintByName(playerData.EquippedPulse2)
	return hint1 == "GK" and hint2 == "GK"
end

-- ⚠️ v104: usado pela fila (MatchmakingQueue) pra equilibrar goleiros
_G.JogadorQuerGK = function(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData or type(playerData.CharacterSlots) ~= "table" then return false end
	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if type(activeSlot) ~= "table" then return false end
	return querSerGK(activeSlot, playerData)
end

-- ========================================
-- Estrutura de Dados para Transferência
-- ========================================
local function gatherPlayerMatchData(player)
	print(string.format("📦 Coletando dados de %s para transferência...", player.Name))

	-- Verificar se os sistemas estão carregados
	if not _G.GetPlayerData then
		warn("❌ PlayerDataManager não carregado!")
		return nil
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then
		warn(string.format("❌ Dados não encontrados para %s", player.Name))
		return nil
	end

	-- Pegar Money
	local money = player:FindFirstChild("Money")
	local currentMoney = money and money.Value or 0

	-- Pegar slot ativo
	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then
		warn(string.format("❌ Slot ativo inválido para %s", player.Name))
		return nil
	end

	-- 🎯 ESTRUTURA DE DADOS COMPLETA
	local matchData = {
		-- Identificação
		UserId = player.UserId,
		PlayerName = player.Name,
		Timestamp = os.time(),

		-- Dados Básicos
		Money = currentMoney,
		ActiveSlot = playerData.ActiveSlot,

		-- Dados do Personagem Ativo
		Character = {
			SlotName = activeSlot.SlotName,
			Role = derivePreferredRole(activeSlot, playerData),
			Element = activeSlot.Element, -- ⚠️ NOVO: elemento do slot (ver Config.ELEMENTS) — reinserido a pedido do usuário

			-- Sistema de Níveis
			Level = activeSlot.Level or 1,
			CurrentXP = activeSlot.CurrentXP or 0,
			AttributePoints = activeSlot.AttributePoints or 0,

			-- Atributos (mesmos nomes que o jogo de futebol lê de verdade —
			-- ver FootballConfig.lua no place Game). Aura/BallControl/
			-- CrossingSkill foram removidos — Speed e Kick entraram no
			-- lugar dos dois últimos.
			Attributes = {
				Physical = activeSlot.Attributes.Physical,
				DribbleSkill = activeSlot.Attributes.DribbleSkill,
				Speed = activeSlot.Attributes.Speed,
				Kick = activeSlot.Attributes.Kick,
				Stamina = activeSlot.Attributes.Stamina,
				Energy = activeSlot.Attributes.Energy, -- ⚠️ NOVO: alimenta o sistema de Pulsos (hissatsus)
				Technique = activeSlot.Attributes.Technique, -- ⚠️ NOVO: Técnica (7º atributo)
			},

			-- 🔥 HISSATSUS (slots vazios por enquanto)
			EquippedHissatsus = activeSlot.EquippedHissatsus or {
				[1] = nil,  -- Slot 1
				[2] = nil,  -- Slot 2
				[3] = nil,  -- Slot 3
				[4] = nil,  -- Slot 4
				[5] = nil   -- Slot 5
			},
			UnlockedHissatsus = activeSlot.UnlockedHissatsus or {},
			SkillPoints = activeSlot.SkillPoints or 10,

			-- 🎲 Pulso/Instinto equipados (sorteados no Roll do Lobby — ver
			-- RollServer.lua e PulseInstinctData.lua). Lidos no place Game
			-- por PlayerSystems.lua e aplicados por PulseController.lua/
			-- InstinctController.lua de lá. 2 slots de Pulso (G/H no jogo).
			EquippedPulse1 = playerData.EquippedPulse1,
			EquippedPulse2 = playerData.EquippedPulse2,
			EquippedPulse3 = playerData.EquippedPulse3, -- ⚠️ v76: 3º slot (Robux)
			EquippedInstinct1 = playerData.EquippedInstinct1,
			EquippedInstinct2 = playerData.EquippedInstinct2, -- ⚠️ v76: Arma também virou 2 slots + 1 Robux
			EquippedInstinct3 = playerData.EquippedInstinct3,
		},

		-- Metadados
		TransferredFrom = "Lobby",
		GameVersion = "1.0"
	}

	print(string.format("✅ Dados coletados de %s:", player.Name))
	print(string.format("   💰 Dinheiro: $%d", matchData.Money))
	print(string.format("   📊 Nível: %d (XP: %d)", matchData.Character.Level, matchData.Character.CurrentXP))
	print(string.format("   👤 Personagem: %s (%s)", matchData.Character.SlotName, matchData.Character.Role or "sem posição preferida")) -- ⚠️ v10: Role pode vir nil agora (nenhum Pulso com posição definida) — cai no overflow normal no Game, não é erro
	print(string.format("   ⚡ Atributos: FIS:%d DRI:%d VEL:%d CHT:%d STA:%d ENE:%d TEC:%d",
		matchData.Character.Attributes.Physical,
		matchData.Character.Attributes.DribbleSkill,
		matchData.Character.Attributes.Speed,
		matchData.Character.Attributes.Kick,
		matchData.Character.Attributes.Stamina,
		matchData.Character.Attributes.Energy or 0,
		matchData.Character.Attributes.Technique or 0)) -- ⚠️ NOVO: Técnica

	return matchData
end

-- ========================================
-- Salvar Dados para Transferência
-- ========================================
local function saveMatchData(player, matchData)
	if not matchData then
		warn(string.format("❌ Dados inválidos para salvar (%s)", player.Name))
		return false
	end

	local userId = player.UserId
	local key = "MatchData_" .. userId

	-- Tentar salvar com retry
	for attempt = 1, MAX_RETRY_ATTEMPTS do
		local success, err = pcall(function()
			matchDataStore:SetAsync(key, matchData)
		end)

		if success then
			print(string.format("💾 Dados de transferência salvos para %s (tentativa %d)", 
				player.Name, attempt))
			return true
		else
			warn(string.format("❌ Erro ao salvar dados (tentativa %d/%d): %s", 
				attempt, MAX_RETRY_ATTEMPTS, tostring(err)))

			if attempt < MAX_RETRY_ATTEMPTS then
				task.wait(1)
			end
		end
	end

	warn(string.format("❌ FALHA CRÍTICA: Não foi possível salvar dados de %s", player.Name))
	return false
end

-- ========================================
-- FUNÇÃO GLOBAL: Preparar Jogador para Partida
-- ========================================
_G.PreparePlayerForMatch = function(player)
	print(string.format("🎮 Preparando %s para entrar na partida...", player.Name))

	-- 1. Coletar dados
	local matchData = gatherPlayerMatchData(player)
	if not matchData then
		return false, "Erro ao coletar dados do jogador"
	end

	-- 2. Salvar dados do lobby (garantir que tudo está salvo) — 1 chamada
	-- só: dinheiro e personagem já estão no mesmo payload (ver
	-- PlayerDataManager.lua), não precisa mais de um _G.SavePlayerMoney
	-- separado.
	if _G.SavePlayerData then
		print(string.format("💾 Salvando dados de %s...", player.Name))
		_G.SavePlayerData(player)
	end

	-- 3. Salvar dados de transferência
	local success = saveMatchData(player, matchData)
	if not success then
		return false, "Erro ao salvar dados de transferência"
	end

	print(string.format("✅ %s está pronto para a partida!", player.Name))
	return true, matchData
end

-- ========================================
-- FIX: o hook antigo interceptava LobbyEvents.FindMatch, criado pelo
-- LobbyManager.lua (sistema de lobby por role, um server só, sem fila
-- entre servidores). LobbyManager.lua foi REMOVIDO — o matchmaking
-- agora é o Matchmaker.lua (cross-server, via MemoryStoreQueue, ver
-- LobbyConfig.lua). _G.TeleportPlayersToMatch também foi removido daqui
-- (fazia sentido só junto do fluxo de um server só do LobbyManager) —
-- quem chama _G.PreparePlayerForMatch agora, por jogador, é o
-- Matchmaker.lua, bem antes de montar o TeleportData de cada partida
-- fechada (embute o retorno em TeleportData.Characters[userId], além de
-- continuar salvando em MatchTransferData_V1 como estava).
-- ========================================
-- LIMPEZA (opcional - limpar dados antigos)
-- ========================================
_G.CleanupOldMatchData = function(player)
	local userId = player.UserId
	local key = "MatchData_" .. userId

	pcall(function()
		matchDataStore:RemoveAsync(key)
	end)

	print(string.format("🧹 Dados de transferência limpos para %s", player.Name))
end

-- ========================================
-- Função de Debug
-- ========================================
_G.TestMatchTransfer = function(playerName)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("🧪 TESTE DE TRANSFERÊNCIA DE DADOS")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	local success, result = _G.PreparePlayerForMatch(player)

	if success then
		print("✅ SUCESSO! Dados preparados:")
		print("")
		print("📊 DADOS COLETADOS:")
		for key, value in pairs(result) do
			if type(value) == "table" then
				print(string.format("   %s: [Tabela]", key))
			else
				print(string.format("   %s: %s", key, tostring(value)))
			end
		end
	else
		print("❌ FALHA:", result)
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

print("✅ MatchDataTransfer carregado (LOBBY)")