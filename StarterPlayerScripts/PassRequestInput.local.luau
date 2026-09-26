--[[
	PassRequestInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Tecla H (⚠️ v78: era T — trocou de lugar com a Arma slot 2, que agora
	usa T, ver PulseInput.local.luau): pede passe — só jogador de LINHA.
	Goleiro (Role == "GK") nunca pede passe, seja "efetivo" dentro da área
	ou não — nem manda o Remote nesse caso. O servidor revalida isso de
	novo de qualquer forma (ver PassRequestController.lua), nunca confia
	só no cliente.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local RequestPass = Config.Remotes.RequestPass

local LocalPlayer = Players.LocalPlayer

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if input.KeyCode ~= Enum.KeyCode.H then return end
	if LocalPlayer:GetAttribute("Role") == "GK" then return end -- goleiro não pede passe

	RequestPass:FireServer()
end)

-- ⚠️ MOBILE: exposto pro botão de Pedir Passe de MobileControls.local.luau.
_G.MobileRequestPass = function()
	if LocalPlayer:GetAttribute("Role") == "GK" then return end -- goleiro não pede passe
	RequestPass:FireServer()
end
