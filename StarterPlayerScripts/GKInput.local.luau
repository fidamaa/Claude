--[[
	GKInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Só faz alguma coisa quando o jogador é GK "efetivo" — Role == "GK" E
	DENTRO da própria área (ver GKAreaUtil.lua) — pra todo mundo mais
	(incluindo o goleiro fora da área), esse script fica quieto (Z/X/C
	viram finta normal, ver DribbleInput.local.luau).

	Pro goleiro, Z/X/C/E/Q viram MERGULHO (defesa por botão, ver
	AttemptGKDive/PulseController.GetGKDiveBonus no servidor):
		Z = mergulho esquerda
		C = mergulho direita
		X = mergulho pra cima
		E = mergulho diagonal cima-direita
		Q = mergulho diagonal cima-esquerda
	F = dash pra frente (AttemptGKForward): rouba a bola do pé do
	adversário se estiver muito perto, ou captura se a bola for direto
	nele.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local AttemptGKDive = Config.Remotes.AttemptGKDive
local AttemptGKForward = Config.Remotes.AttemptGKForward

local player = Players.LocalPlayer

local KEY_TO_DIVE = {
	[Enum.KeyCode.Z] = "Left",
	[Enum.KeyCode.C] = "Right",
	[Enum.KeyCode.X] = "Up",
	[Enum.KeyCode.E] = "UpRight",
	[Enum.KeyCode.Q] = "UpLeft",
}

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	-- ⚠️ PULSO v3: enquanto um COMBO de Pulso está pendente, Q/E/R são
	-- CONSUMIDAS pelo combo (ver PulseInput.local.luau, que liga/desliga
	-- esse Attribute) — sem isso, um passo do combo viraria um mergulho
	-- sem querer, já que os dois LocalScripts escutam as mesmas teclas.
	if player:GetAttribute("PulseComboActive") then return end

	local diveDirection = KEY_TO_DIVE[input.KeyCode]
	if diveDirection then
		AttemptGKDive:FireServer(diveDirection)
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
