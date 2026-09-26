--[[
	DribbleInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts

	Mapeia Z (esquerda) / X (trás) / C (direita) pro remote de finta.
	NÃO faz nada se o jogador é GK EFETIVO (Role == "GK" E dentro da
	própria área — ver GKAreaUtil.lua) — pra ele, essas mesmas teclas
	viram mergulho (ver GKInput.local.luau). Goleiro FORA da área volta a
	usar essas teclas como finta normal, igual jogador de linha.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local AttemptDribbleMove = Config.Remotes.AttemptDribbleMove
local player = Players.LocalPlayer

local KEY_TO_MOVE = {
	[Enum.KeyCode.Z] = "Left",
	[Enum.KeyCode.X] = "Back",
	[Enum.KeyCode.C] = "Right",
}

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
	if GKAreaUtil.IsEffectiveGK(player) then return end -- GK dentro da área: vira mergulho, ver GKInput.local.luau

	local moveName = KEY_TO_MOVE[input.KeyCode]
	if not moveName then return end

	AttemptDribbleMove:FireServer(moveName)
end)

-- ⚠️ MOBILE: exposto pro botão correspondente em MobileControls.local.luau
-- chamar direto — mesma checagem de GK de cima, sem duplicar nada.
local VALID_MOVES = { Left = true, Back = true, Right = true }
_G.MobileDribble = function(moveName)
	if GKAreaUtil.IsEffectiveGK(player) then return end
	if not VALID_MOVES[moveName] then return end
	AttemptDribbleMove:FireServer(moveName)
end