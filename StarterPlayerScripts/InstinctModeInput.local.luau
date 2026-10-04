--[[
	InstinctModeInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Tecla dedicada pro Instinct Mode (Parte 2 do rework): V. Escolhida por
	ser a única tecla "de mão esquerda" fácil de alcançar durante o jogo
	que ainda não tinha nenhum uso — Q/E/R (Pulsos), Z/X/C (finta/dive de
	GK), G (cabeçada), F (dash de GK), LeftShift (sprint) e LeftControl
	(shift lock) já estão todas ocupadas (ver PulseInput/GKInput/
	DribbleInput.local.luau e FootballClient.local.luau).
	⚠️ NOVO: o esquema mudou (Q drible, F dash, E/R Armas, T cabeçada, sem
	sprint), mas V continua livre — nada muda aqui.

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
	elseif kind == "FlowOcupado" then
		-- ⚠️ v120b: um Flow por vez no campo inteiro
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Flow",
				Text = ("Outro jogador está no Flow. Tente de novo em %ds."):format(tonumber(extra) or 0),
				Duration = 2.5,
			})
		end)
	elseif kind == "FlowPrecisaBola" then
		-- ⚠️ v124: o Flow do Shidou é o próprio chute (Big Bang Drive) — só com a bola
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = "Flow",
				-- (v126: só com a bola no ar em cima de você)
				Text = "Big Bang Drive: só com a bola NO AR em cima de você (sem estar com ela nos pés). Mire pra onde quer chutar.",
				Duration = 3,
			})
		end)
	end
end)

-- ⚠️ v124 — FLOW COM CHUTE (Shidou): manda pra onde ele está mirando (a MESMA mira da
-- Hissatsu, ver HissatsuInput.local.luau). Os outros Flows ignoram o argumento.
local function pontoDeMira()
	local calcular = _G.HissatsuComputeAimPoint
	if calcular then
		local ok, ponto = pcall(calcular)
		if ok and typeof(ponto) == "Vector3" then return ponto end
	end
	return nil
end

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

	ActivateInstinctMode:FireServer(pontoDeMira())
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

	ActivateInstinctMode:FireServer(pontoDeMira())
end
