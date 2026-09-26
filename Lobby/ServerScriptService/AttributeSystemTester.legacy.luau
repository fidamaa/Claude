--[[
	AttributeSystemTester - Script de Teste para o Sistema de Atributos
	Coloque em ServerScriptService
	
	Este script adiciona comandos de teste para verificar o funcionamento:
	/testpoints - Dá 5 pontos de atributo para testar
	/testlevelup - Sobe 1 nível (dá 3 pontos automaticamente)
	/testxp - Adiciona 100 XP
	/checkdata - Mostra todos os dados do jogador no console
]]

local Players = game:GetService("Players")

-- Lista de testers (adicione seu UserId)
local TESTERS = {
	311895155  -- ⚠️ ADICIONE SEU USERID AQUI
}

local function isTester(player)
	return table.find(TESTERS, player.UserId) ~= nil
end

-- ========================================
-- Comando: Dar Pontos de Teste
-- ========================================
local function cmdTestPoints(player)
	if not _G.GetPlayerData then
		warn("❌ Sistema de dados não disponível")
		return
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then return end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then return end

	-- Adicionar 5 pontos
	activeSlot.AttributePoints = (activeSlot.AttributePoints or 0) + 5

	print(string.format("🧪 TEST: %s recebeu 5 pontos de atributo (Total: %d)", 
		player.Name, activeSlot.AttributePoints))

	-- Notificar o cliente via UpdateLevelData
	local events = game.ReplicatedStorage:FindFirstChild("LobbyEvents")
	if events then
		local updateEvent = events:FindFirstChild("UpdateLevelData")
		if updateEvent then
			local function calculateXPForLevel(level)
				-- Mesma fórmula LINEAR do LevelManager.lua (ver rework lá) —
				-- não a exponencial antiga.
				if level <= 1 then return 0 end
				return 100 + 40 * (level - 2)
			end

			updateEvent:FireClient(player, {
				Level = activeSlot.Level or 1,
				CurrentXP = activeSlot.CurrentXP or 0,
				XPNeeded = calculateXPForLevel((activeSlot.Level or 1) + 1),
				AttributePoints = activeSlot.AttributePoints,
				Attributes = activeSlot.Attributes,
				LeveledUp = false
			})
		end
	end
end

-- ========================================
-- Comando: Level Up de Teste
-- ========================================
local function cmdTestLevelUp(player)
	if not _G.AddPlayerXP then
		warn("❌ Sistema de XP não disponível")
		return
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then return end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then return end

	-- Calcular XP necessário
	local function calculateXPForLevel(level)
		-- Mesma fórmula LINEAR do LevelManager.lua (ver rework lá) — não a
		-- exponencial antiga.
		if level <= 1 then return 0 end
		return 100 + 40 * (level - 2)
	end

	local xpNeeded = calculateXPForLevel(activeSlot.Level + 1) - activeSlot.CurrentXP

	print(string.format("🧪 TEST: Subindo nível de %s (precisa %d XP)", player.Name, xpNeeded))

	_G.AddPlayerXP(player, xpNeeded)
end

-- ========================================
-- Comando: Adicionar XP de Teste
-- ========================================
local function cmdTestXP(player)
	if not _G.AddPlayerXP then
		warn("❌ Sistema de XP não disponível")
		return
	end

	print(string.format("🧪 TEST: Adicionando 100 XP para %s", player.Name))
	_G.AddPlayerXP(player, 100)
end

-- ========================================
-- Comando: Verificar Dados
-- ========================================
local function cmdCheckData(player)
	if not _G.GetPlayerData then
		warn("❌ Sistema de dados não disponível")
		return
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then
		print("❌ Nenhum dado encontrado para", player.Name)
		return
	end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print(string.format("🧪 DADOS DE TESTE - %s", player.Name))
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	if activeSlot and activeSlot ~= "Locked" then
		print(string.format("📊 SLOT ATIVO (#%d):", playerData.ActiveSlot))
		print(string.format("   Nome: %s", activeSlot.SlotName))
		print(string.format("   Nível: %d", activeSlot.Level or 1))
		print(string.format("   XP Atual: %d", activeSlot.CurrentXP or 0))
		print(string.format("   Pontos de Atributo: %d", activeSlot.AttributePoints or 0))
		print("")
		print("⚡ ATRIBUTOS:")
		for attr, value in pairs(activeSlot.Attributes) do
			print(string.format("   %s = %d", attr, value))
		end
	else
		print("❌ Nenhum slot ativo válido")
	end

	print("")
	print("🎯 VERIFICAÇÕES:")

	-- Verificar se tem pontos disponíveis
	if activeSlot and activeSlot.AttributePoints > 0 then
		print(string.format("   ✅ Tem %d pontos disponíveis", activeSlot.AttributePoints))
		print("   ✅ Botões '+' DEVEM estar visíveis")
	else
		print("   ❌ SEM pontos disponíveis")
		print("   ❌ Botões '+' DEVEM estar ocultos")
	end

	-- Verificar evento de atualização
	local events = game.ReplicatedStorage:FindFirstChild("LobbyEvents")
	if events then
		local updateEvent = events:FindFirstChild("UpdateLevelData")
		if updateEvent then
			print("   ✅ UpdateLevelData existe")
		else
			print("   ❌ UpdateLevelData NÃO existe!")
		end
	else
		print("   ❌ LobbyEvents NÃO existe!")
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

-- ========================================
-- Conectar Comandos
-- ========================================
Players.PlayerAdded:Connect(function(player)
	if not isTester(player) then return end

	print(string.format("🧪 Tester conectado: %s", player.Name))

	task.wait(3)
	print(string.format("💡 [%s] Comandos de teste: /testpoints /testlevelup /testxp /checkdata", player.Name))

	player.Chatted:Connect(function(message)
		local lowerMsg = string.lower(message)

		if lowerMsg == "/testpoints" then
			cmdTestPoints(player)

		elseif lowerMsg == "/testlevelup" then
			cmdTestLevelUp(player)

		elseif lowerMsg == "/testxp" then
			cmdTestXP(player)

		elseif lowerMsg == "/checkdata" then
			cmdCheckData(player)
		end
	end)
end)

-- ========================================
-- Auto-teste ao entrar (opcional)
-- ========================================
local AUTO_TEST_ON_JOIN = false  -- Mude para true se quiser teste automático

if AUTO_TEST_ON_JOIN then
	Players.PlayerAdded:Connect(function(player)
		if not isTester(player) then return end

		task.wait(5)  -- Aguardar carregamento

		print("🧪 Iniciando auto-teste para", player.Name)

		-- Verificar dados
		cmdCheckData(player)

		task.wait(2)

		-- Dar pontos de teste
		print("🧪 Dando pontos de teste...")
		cmdTestPoints(player)

		task.wait(1)

		-- Verificar novamente
		cmdCheckData(player)
	end)
end

-- ========================================
-- Funções Globais para Console
-- ========================================
_G.TestGivePoints = function(playerName, amount)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then return end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then return end

	activeSlot.AttributePoints = (activeSlot.AttributePoints or 0) + (amount or 5)

	-- Notificar cliente
	local events = game.ReplicatedStorage:FindFirstChild("LobbyEvents")
	if events then
		local updateEvent = events:FindFirstChild("UpdateLevelData")
		if updateEvent then
			local function calculateXPForLevel(level)
				-- Mesma fórmula LINEAR do LevelManager.lua (ver rework lá)
				-- — não a exponencial antiga.
				if level <= 1 then return 0 end
				return 100 + 40 * (level - 2)
			end

			updateEvent:FireClient(player, {
				Level = activeSlot.Level or 1,
				CurrentXP = activeSlot.CurrentXP or 0,
				XPNeeded = calculateXPForLevel((activeSlot.Level or 1) + 1),
				AttributePoints = activeSlot.AttributePoints,
				Attributes = activeSlot.Attributes,
				LeveledUp = false
			})
		end
	end

	print(string.format("✅ Dado %d pontos para %s (Total: %d)", 
		amount or 5, player.Name, activeSlot.AttributePoints))
end

_G.TestCheckPlayer = function(playerName)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	cmdCheckData(player)
end

_G.TestForceUpdate = function(playerName)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then return end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then return end

	local events = game.ReplicatedStorage:FindFirstChild("LobbyEvents")
	if events then
		local updateEvent = events:FindFirstChild("UpdateLevelData")
		if updateEvent then
			local function calculateXPForLevel(level)
				-- Mesma fórmula LINEAR do LevelManager.lua (ver rework lá)
				-- — não a exponencial antiga.
				if level <= 1 then return 0 end
				return 100 + 40 * (level - 2)
			end

			print(string.format("🔄 Forçando atualização para %s...", player.Name))
			print(string.format("   Pontos: %d", activeSlot.AttributePoints))
			print("   Atributos:")
			for attr, val in pairs(activeSlot.Attributes) do
				print(string.format("     %s = %d", attr, val))
			end

			updateEvent:FireClient(player, {
				Level = activeSlot.Level or 1,
				CurrentXP = activeSlot.CurrentXP or 0,
				XPNeeded = calculateXPForLevel((activeSlot.Level or 1) + 1),
				AttributePoints = activeSlot.AttributePoints,
				Attributes = activeSlot.Attributes,
				LeveledUp = false
			})

			print("✅ Atualização enviada!")
		end
	end
end

print(string.format("✅ AttributeSystemTester carregado (%d tester(s); comandos: /testpoints /testlevelup /testxp /checkdata)", #TESTERS))