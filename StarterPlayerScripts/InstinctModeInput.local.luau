--[[
	InstinctModeInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Tecla dedicada pro Instinct Mode (Parte 2 do rework): V. Escolhida por
	ser a única tecla "de mão esquerda" fácil de alcançar durante o jogo
	que ainda não tinha nenhum uso — Q/E/R (Pulsos), Z/X/C (finta/dive de
	GK), G (cabeçada), F (dash de GK), LeftShift (sprint) e LeftControl
	(shift lock) já estão todas ocupadas (ver PulseInput/GKInput/
	DribbleInput.local.luau e FootballClient.local.luau).

	Só manda o FireServer — quem decide se o medidor está cheio de
	verdade é sempre o servidor (InstinctController.lua); aqui só evita
	spam óbvio (debounce local) e mostra uma notificação simples se o
	jogador apertar sem o medidor cheio.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local ActivateInstinctMode = Config.Remotes.ActivateInstinctMode
local InstinctModeFeedback = Config.Remotes.InstinctModeFeedback

local INSTINCT_MODE_KEY = Enum.KeyCode.V

local meterFull = false
InstinctModeFeedback.OnClientEvent:Connect(function(kind, extra)
	if kind == "MeterUpdate" then
		meterFull = (tonumber(extra) or 0) >= 100
	elseif kind == "ModeActivated" then
		meterFull = false
	end
end)

local lastPress = 0
UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if input.KeyCode ~= INSTINCT_MODE_KEY then return end
	if tick() - lastPress < 0.5 then return end -- debounce local simples, o servidor é sempre a autoridade de verdade
	lastPress = tick()

	if not meterFull then
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Flow",
				Text = "Medidor ainda não está cheio.",
				Duration = 2,
			})
		end)
		return
	end

	ActivateInstinctMode:FireServer()
end)

-- ⚠️ MOBILE: exposto pro botão de Instinct Mode (V) de MobileControls.
-- local.luau — mesmo debounce e mesmo aviso de "medidor não cheio".
_G.MobileActivateInstinctMode = function()
	if tick() - lastPress < 0.5 then return end
	lastPress = tick()

	if not meterFull then
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Flow",
				Text = "Medidor ainda não está cheio.",
				Duration = 2,
			})
		end)
		return
	end

	ActivateInstinctMode:FireServer()
end
