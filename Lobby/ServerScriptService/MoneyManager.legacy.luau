--[[
	MoneyManager - Sistema Completo de Economia
	Coloque em ServerScriptService

	REWORK: não tem mais DataStore próprio. O dinheiro agora é só mais um
	campo (Money) dentro do mesmo payload único que o PlayerDataManager
	salva (ver PlayerDataManager.lua) — antes eram 2 DataStores separados
	(PlayerCharacterData_V4 aqui do lado + PlayerMoneyData_V1), cada um
	com seu próprio retry e seu próprio game:BindToClose com espera fixa,
	o que somava tempo no fechamento do server à toa. Este script só
	mantém a NumberValue "Money" em sincronia com playerData.Money e
	expõe as mesmas funções globais de sempre — quem usa _G.AddMoney etc
	não precisa mudar nada.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local STARTING_MONEY = 1000 -- só usado se, por algum motivo, playerData.Money não existir ainda

-- ========================================
-- Criar Eventos de Comunicação
-- ========================================
local eventsFolder = ReplicatedStorage:FindFirstChild("MoneyEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "MoneyEvents"
	eventsFolder.Parent = ReplicatedStorage
end

local updateMoneyEvent = Instance.new("RemoteEvent")
updateMoneyEvent.Name = "UpdateMoney"
updateMoneyEvent.Parent = eventsFolder

local getMoneyFunc = Instance.new("RemoteFunction")
getMoneyFunc.Name = "GetMoney"
getMoneyFunc.Parent = eventsFolder

-- ========================================
-- Carregar Dinheiro do Jogador (a partir do payload já carregado pelo
-- PlayerDataManager — não faz NENHUMA chamada de DataStore própria)
-- ========================================
local function loadMoneyData(player)
	-- FIX CRÍTICO: WaitForChild só espera a INSTANCE "DataLoaded" existir
	-- — ela é criada com Value=false já no INÍCIO do carregamento (bem
	-- antes do DataStore responder de verdade), então esse WaitForChild
	-- sempre voltava quase na hora, com Value ainda false. Sem o
	-- Changed:Wait() abaixo, isso corria direto pra baixo, achava
	-- _G.GetPlayerData(player) == nil (dados de verdade ainda não
	-- tinham chegado) e criava a NumberValue "Money" sempre em
	-- STARTING_MONEY — foi ISSO que fazia o dinheiro "resetar": o valor
	-- carregado do DataStore chegava DEPOIS, mas nada re-sincronizava a
	-- NumberValue com ele, então ela ficava presa no valor errado e
	-- SOBRESCREVIA o save de verdade na próxima mudança (setupMoneyListener
	-- só escreve playerData.Money = newValue, nunca lê o valor salvo de
	-- volta).
	local dataLoaded = player:WaitForChild("DataLoaded", 15)
	if dataLoaded and not dataLoaded.Value then
		dataLoaded.Changed:Wait()
	end
	if not dataLoaded or not dataLoaded.Value then
		warn(string.format("⚠️ MoneyManager: dados não carregados a tempo para %s", player.Name))
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	local moneyValue = (playerData and type(playerData.Money) == "number") and playerData.Money or STARTING_MONEY

	if playerData and type(playerData.Money) ~= "number" then
		playerData.Money = moneyValue -- garante o campo pra próxima leitura/salvamento
	end

	local money = Instance.new("NumberValue")
	money.Name = "Money"
	money.Value = moneyValue
	money.Parent = player

	print(string.format("✅ Dinheiro carregado para %s: $%d", player.Name, moneyValue))
	updateMoneyEvent:FireClient(player, moneyValue)
end

-- ========================================
-- Funções Globais
-- ========================================
_G.AddMoney = function(player, amount)
	local money = player:FindFirstChild("Money")
	if not money then
		warn(string.format("❌ Money não encontrado para %s", player.Name))
		return false
	end

	money.Value = money.Value + amount

	print(string.format("💰 %s recebeu $%d (Total: $%d)", player.Name, amount, money.Value))

	return true
end

_G.RemoveMoney = function(player, amount)
	local money = player:FindFirstChild("Money")
	if not money then
		warn(string.format("❌ Money não encontrado para %s", player.Name))
		return false
	end

	if money.Value < amount then
		warn(string.format("⚠️ %s não tem dinheiro suficiente ($%d < $%d)",
			player.Name, money.Value, amount))
		return false
	end

	money.Value = money.Value - amount

	print(string.format("💰 %s gastou $%d (Restante: $%d)", player.Name, amount, money.Value))

	return true
end

_G.SetMoney = function(player, amount)
	local money = player:FindFirstChild("Money")
	if not money then
		warn(string.format("❌ Money não encontrado para %s", player.Name))
		return false
	end

	money.Value = amount

	print(string.format("💰 Dinheiro de %s definido para $%d", player.Name, amount))

	return true
end

_G.GetMoney = function(player)
	local money = player:FindFirstChild("Money")
	return money and money.Value or 0
end

-- Mantidos por compatibilidade (MatchDataTransfer/CodeRedeemServer ainda
-- podem chamar esses nomes) — agora são só um alias pro salvamento
-- único do PlayerDataManager, já que Money vive no mesmo payload.
_G.SaveAllMoney = function()
	if not _G.SavePlayerData then return 0 end
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if _G.SavePlayerData(player) then
			count += 1
		end
	end
	return count
end

_G.SavePlayerMoney = function(player)
	return _G.SavePlayerData and _G.SavePlayerData(player)
end

-- ========================================
-- RemoteFunction para Cliente
-- ========================================
getMoneyFunc.OnServerInvoke = function(player)
	local money = player:FindFirstChild("Money")
	return money and money.Value or 0
end

-- ========================================
-- Monitorar Mudanças de Dinheiro (mantém playerData.Money em sincronia
-- com a NumberValue — é ISSO que persiste, não uma escrita direta no
-- DataStore a cada mudança)
-- ========================================
local function setupMoneyListener(player)
	local money = player:WaitForChild("Money", 10)
	if not money then
		warn(string.format("❌ Money não encontrado para %s após 10s", player.Name))
		return
	end

	money.Changed:Connect(function(newValue)
		if newValue < 0 then
			warn(string.format("⚠️ Valor negativo detectado para %s! Corrigindo...", player.Name))
			money.Value = 0
			return
		end

		local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
		if playerData then
			playerData.Money = newValue
		end

		-- MELHORIA DE SAVE: antes só a saída/autosave persistiam dinheiro
		-- de verdade (playerData.Money só existia em memória até lá) — é
		-- isso que fazia o save "atrasado". Agora todo AddMoney/RemoveMoney/
		-- SetMoney já agenda um salvamento (debounced, ver PlayerDataManager.
		-- lua) em vez de esperar até 30s (ou o jogador sair) pra virar save
		-- de verdade.
		if _G.RequestSave then
			_G.RequestSave(player)
		end

		updateMoneyEvent:FireClient(player, newValue)
	end)
end

-- ========================================
-- Eventos de Jogadores
-- ========================================
Players.PlayerAdded:Connect(function(player)
	task.spawn(function()
		loadMoneyData(player)
		setupMoneyListener(player)
	end)
end)

-- ========================================
-- Comando de Console (opcional)
-- ========================================
_G.MoneyDebug = function(playerName)
	local target = Players:FindFirstChild(playerName)
	if not target then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	local money = target:FindFirstChild("Money")
	if not money then
		print("❌ Money não encontrado para", target.Name)
		return
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print(string.format("💰 DEBUG DE DINHEIRO - %s", target.Name))
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print(string.format("   Valor Atual: $%d", money.Value))
	print(string.format("   UserId: %d", target.UserId))
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

print(string.format("✅ MoneyManager carregado (fallback $%d)", STARTING_MONEY))
