--[[
	SprintClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	CAUSA DO "AINDA NÃO DÁ PRA CORRER NO LOBBY": o StaminaManager.legacy.luau
	(servidor) só troca o WalkSpeed quando recebe o evento
	ReplicatedStorage.UpdateSprintingState — mas não existia NENHUM script
	client no Lobby que escutasse a tecla e disparasse esse evento. Sem
	esse script, "wantsToSprint" nunca chegava no servidor, então não tinha
	como correr (independente da estamina já estar liberada ou não).

	Mesma tecla usada no place Game (LeftShift), segurar = correr, soltar
	= andar normal. Aqui no Lobby já não gasta mais estamina (ver
	StaminaManager.legacy.luau), só liga/desliga o WalkSpeed.
]]

local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local updateSprintingState = ReplicatedStorage:WaitForChild("UpdateSprintingState")

local SPRINT_KEY = Enum.KeyCode.LeftShift

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == SPRINT_KEY then
		updateSprintingState:FireServer(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == SPRINT_KEY then
		updateSprintingState:FireServer(false)
	end
end)

-- ⚠️ MOBILE: exposto pro botão de Sprint de MobileControls.local.luau.
_G.MobileSetSprinting = function(sprinting)
	updateSprintingState:FireServer(sprinting and true or false)
end

print("✅ SprintClient (Lobby) carregado.")
