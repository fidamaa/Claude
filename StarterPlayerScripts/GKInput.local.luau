--[[
	GKInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Só faz alguma coisa quando o jogador é GK "efetivo" — Role == "GK" E
	DENTRO da própria área (ver GKAreaUtil.lua) — pra todo mundo mais
	(incluindo o goleiro fora da área), esse script fica quieto (Z/X/C
	viram finta normal, ver DribbleInput.local.luau).

	⚠️ NOVO — Pro goleiro, Q + DIREÇÃO (WASD) vira MERGULHO (defesa por
	botão, ver AttemptGKDive/PulseController.GetGKDiveBonus no servidor),
	igual ao drible direcional do jogador de linha. Antes eram Z/X/C/E/Q
	fixas — E/Q conflitavam com o novo esquema (Q = drible, E = Arma 1):
		A + Q        = mergulho esquerda
		D + Q        = mergulho direita
		Q (ou W/S+Q) = mergulho pra cima
		W + D + Q    = mergulho diagonal cima-direita
		W + A + Q    = mergulho diagonal cima-esquerda
	Esquerda/direita são relativas ao CORPO do goleiro (pra onde ele está
	virado), não à câmera — é o lado pro qual ele se joga.
	F = dash pra frente (AttemptGKForward): rouba a bola do pé do
	adversário se estiver muito perto, ou captura se a bola for direto
	nele. (Fora da área, F é o dash/carrinho normal.)
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local AttemptGKDive = Config.Remotes.AttemptGKDive
local AttemptGKForward = Config.Remotes.AttemptGKForward

local player = Players.LocalPlayer

local DIVE_KEY = Enum.KeyCode.Q

-- Traduz o WASD atual (Humanoid.MoveDirection, espaço de mundo) nos mesmos
-- nomes de mergulho que o servidor já conhece (Left/Right/Up/UpLeft/
-- UpRight) — o servidor não mudou nada.
local SIDE_THRESHOLD = 0.35
local function diveDirectionFromInput()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return "Up" end
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then return "Up" end
	local lateral = move:Dot(root.CFrame.RightVector)
	local forward = move:Dot(root.CFrame.LookVector)
	if math.abs(lateral) < SIDE_THRESHOLD then return "Up" end
	if forward > SIDE_THRESHOLD then
		return lateral > 0 and "UpRight" or "UpLeft"
	end
	return lateral > 0 and "Right" or "Left"
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	-- ⚠️ PULSO v3: enquanto um COMBO de Pulso está pendente, Q/E/R são
	-- CONSUMIDAS pelo combo (ver PulseInput.local.luau, que liga/desliga
	-- esse Attribute) — sem isso, um passo do combo viraria um mergulho
	-- sem querer, já que os dois LocalScripts escutam as mesmas teclas.
	if player:GetAttribute("PulseComboActive") then return end

	if input.KeyCode == DIVE_KEY then
		AttemptGKDive:FireServer(diveDirectionFromInput())
		return
	end

	if input.KeyCode == Enum.KeyCode.F then
		AttemptGKForward:FireServer()
	end
end)

-- ⚠️ MOBILE: exposto pros botões de mergulho/dash de MobileControls.
-- local.luau chamarem direto — mesma checagem de GK/combo de cima.
local VALID_DIVES = { Left = true, Right = true, Up = true, UpRight = true, UpLeft = true }
_G.MobileGKDive = function(direction)
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	if player:GetAttribute("PulseComboActive") then return end
	if not VALID_DIVES[direction] then return end
	AttemptGKDive:FireServer(direction)
end

_G.MobileGKForward = function()
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	if player:GetAttribute("PulseComboActive") then return end
	AttemptGKForward:FireServer()
end
