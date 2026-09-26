--[[
	StaminaManager - Versão Completa e Sincronizada
	Gerencia a stamina e a corrida. Espera pelo sinal "DataLoaded" para evitar falhas.

	PEDIDO: corrida no LOBBY não gasta mais estamina — aqui é só o hub de
	menu/loja/matchmaking, não faz sentido cansar andando entre os NPCs.
	As NumberValues Stamina/MaxStamina/IsExhausted continuam existindo
	(outros scripts podem ler pra UI/etc), só que a corrida nunca mais
	drena nem entra em exaustão — sempre pode correr. O gasto de verdade
	continua só no place Game (partida), que tem seu próprio
	PlayerSystems.lua com essa lógica intacta.
]]

-- Serviços
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Comunicação com o Cliente
local updateSprintingState = ReplicatedStorage:WaitForChild("UpdateSprintingState")

-- Configurações de Balanceamento
local BASE_STAMINA = 50
local STAMINA_PER_ATTRIBUTE_POINT = 10
local SPRINT_DRAIN_RATE = 20
local RECOVERY_RATE = 15
local EXHAUSTED_RECOVERY_RATE = 5
local EXHAUSTED_DURATION = 2
-- ⚠️ v75 — PEDIDO: "coloque uma velocidade de corrida maior no lobby, 35%
-- maior." Só a velocidade de CORRIDA (segurando sprint) sobe — a
-- velocidade normal de andar fica igual, pra correr continuar sendo uma
-- escolha que faz diferença, não só um número maior em tudo.
local SPRINT_SPEED = 25 * 1.35 -- 33.75 (era 25)
local NORMAL_SPEED = 16

-- ⚠️ FIX (pedido do usuário: "um com 100 de speed e o outro com 70 no
-- lobby, e os dois tinham a mesma velocidade... só conta os atributos
-- iniciais, precisa contar com os atributos gerais") — SPRINT_SPEED/
-- NORMAL_SPEED aqui em cima eram usados FIXOS pra TODO MUNDO, sem nunca
-- ler o atributo "Speed" do personagem ativo (só a Stamina virava
-- MaxStamina). Mesma fórmula de multiplicador que o place Game usa em
-- PlayerSystems.legacy.luau (Config.SPEED_MULTIPLIER_MIN/MAX): no
-- default (50) o multiplicador é 1.0x, ninguém que nunca mexeu no
-- atributo sente diferença nenhuma.
local SPEED_MULTIPLIER_MIN = 0.90
local SPEED_MULTIPLIER_MAX = 1.10

local isSprinting = {}
local speedMultiplierOf = {} -- [player] = multiplicador calculado do Speed do slot ativo

-- Loop Principal de Gerenciamento de Stamina
RunService.Heartbeat:Connect(function(deltaTime)
	for _, player in ipairs(Players:GetPlayers()) do
		local stamina = player:FindFirstChild("Stamina")
		local maxStamina = player:FindFirstChild("MaxStamina")
		local isExhausted = player:FindFirstChild("IsExhausted")

		if not stamina or not maxStamina or not isExhausted then continue end

		-- LOBBY: nunca drena nem exaure — só regenera (caso algo tenha
		-- deixado a stamina abaixo do máximo antes dessa mudança).
		-- isSprinting[player] não é mais usado pra gastar nada, só fica
		-- registrado por compatibilidade.
		if isExhausted.Value then
			isExhausted.Value = false
		end
		stamina.Value = math.min(maxStamina.Value, stamina.Value + (RECOVERY_RATE * deltaTime))
	end
end)

-- Gerenciamento do Estado de Corrida
-- LOBBY: corrida sempre disponível, sem gastar/checar estamina.
updateSprintingState.OnServerEvent:Connect(function(player, wantsToSprint)
	isSprinting[player] = wantsToSprint

	local character = player.Character
	if character and character:FindFirstChild("Humanoid") then
		local mult = speedMultiplierOf[player] or 1
		character.Humanoid.WalkSpeed = (wantsToSprint and SPRINT_SPEED or NORMAL_SPEED) * mult
	end
end)

-- ⚠️ FIX: calcula e aplica o multiplicador de Speed do slot ATIVO agora —
-- extraído numa função à parte (em vez de só rodar dentro de
-- onCharacterAdded) pra dar pra chamar de novo sem precisar respawnar o
-- personagem: LevelManager.legacy.luau chama isso quando o jogador gasta
-- ponto de atributo em Speed, e ShopServer.legacy.luau quando ele troca
-- de personagem ativo — os dois mudam QUAL Speed vale sem trocar de
-- Character.
local function refreshSpeedMultiplier(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return end

	local activeSlotData = playerData.CharacterSlots[playerData.ActiveSlot]
	local speedAttribute = activeSlotData and activeSlotData.Attributes and activeSlotData.Attributes.Speed
	if typeof(speedAttribute) ~= "number" then speedAttribute = 50 end

	local speedFraction = math.clamp(speedAttribute, 0, 100) / 100
	local speedMultiplier = SPEED_MULTIPLIER_MIN + (SPEED_MULTIPLIER_MAX - SPEED_MULTIPLIER_MIN) * speedFraction
	speedMultiplierOf[player] = speedMultiplier

	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = (isSprinting[player] and SPRINT_SPEED or NORMAL_SPEED) * speedMultiplier
	end

	return speedMultiplier
end
_G.RefreshLobbySpeedMultiplier = refreshSpeedMultiplier

-- Inicialização dos valores do jogador
local function setupPlayerValues(player)
	isSprinting[player] = false
	if not player:FindFirstChild("Stamina") then Instance.new("NumberValue", player).Name = "Stamina" end
	if not player:FindFirstChild("MaxStamina") then Instance.new("NumberValue", player).Name = "MaxStamina" end
	if not player:FindFirstChild("IsExhausted") then Instance.new("BoolValue", player).Name = "IsExhausted" end
end

-- [[ LÓGICA DE CARREGAMENTO ATUALIZADA E CORRIGIDA ]]
local function onCharacterAdded(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local humanoid = character:WaitForChild("Humanoid")
	humanoid.WalkSpeed = NORMAL_SPEED

	-- 1. Espera pelo "sinal verde" do PlayerDataManager.
	print(string.format("StaminaManager: Esperando sinal 'DataLoaded' para %s...", player.Name))
	local dataLoadedSignal = player:WaitForChild("DataLoaded")
	if not dataLoadedSignal.Value then
		dataLoadedSignal.Changed:Wait()
	end
	print(string.format("StaminaManager: Sinal recebido. Carregando dados de stamina para %s.", player.Name))

	-- 2. Agora podemos pegar os dados com segurança.
	local playerData = _G.GetPlayerData(player)
	if not playerData then
		warn("StaminaManager: Dados para " .. player.Name .. " não encontrados. Usando valores padrão.")
		return
	end

	local activeSlotData = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlotData then
		activeSlotData = { Attributes = { Stamina = 0 } }
	end

	-- 3. Calcula e aplica a stamina máxima.
	local staminaAttribute = activeSlotData.Attributes.Stamina
	local calculatedMaxStamina = BASE_STAMINA + (staminaAttribute * STAMINA_PER_ATTRIBUTE_POINT)

	player.MaxStamina.Value = calculatedMaxStamina
	player.Stamina.Value = calculatedMaxStamina
	player.IsExhausted.Value = false

	print(string.format("StaminaManager: Stamina de %s definida como %d.", player.Name, calculatedMaxStamina))

	-- 4. ⚠️ FIX: calcula e aplica o multiplicador de Speed (ver comentário
	-- em SPEED_MULTIPLIER_MIN/MAX acima) — antes disso, correr no Lobby
	-- ignorava esse atributo por completo.
	local speedMultiplier = refreshSpeedMultiplier(player)
	print(string.format("StaminaManager: multiplicador de Speed de %s definido como %.2fx.", player.Name, speedMultiplier or 1))
end

-- Conecta os eventos para jogadores
Players.PlayerAdded:Connect(function(player)
	setupPlayerValues(player)
	player.CharacterAdded:Connect(onCharacterAdded)
end)

Players.PlayerRemoving:Connect(function(player)
	isSprinting[player] = nil
	speedMultiplierOf[player] = nil
end)

print("✅ StaminaManager (Completo e Sincronizado) Carregado.")