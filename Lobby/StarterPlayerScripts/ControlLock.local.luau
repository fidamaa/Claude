--[[
	ControlLock (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Mesmo sistema de Shift Lock alternativo do FootballClient.lua (place
	Game) — replicado aqui pra ficar IDÊNTICO nos dois lugares, em vez
	da implementação antiga que tinha aqui (que usava
	`player.DevEnableMouseLock` — dava "Insufficient permissions" no
	Studio — e um `game:BindToClose` dentro de um LocalScript, que nem
	é permitido: BindToClose só existe no servidor).

	Tecla Left Control liga/desliga (toggle, não precisa segurar):
	1) trava o mouse no centro da tela (câmera gira livre);
	2) o personagem passa a olhar pra onde a câmera olha, em vez de virar
	   só quando anda.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local CONTROL_LOCK_KEY = Enum.KeyCode.LeftControl
local TURN_RESPONSIVENESS = 14 -- maior = vira mais rápido atrás da câmera

local shiftLockEnabled = false

local function applyAutoRotate(character, enabled)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = enabled
	end
end

local function setShiftLock(enabled)
	if shiftLockEnabled == enabled then return end
	shiftLockEnabled = enabled

	UserInputService.MouseBehavior = enabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = not enabled

	applyAutoRotate(player.Character, not enabled)
end

player.CharacterAdded:Connect(function(character)
	-- garante que um respawn não deixe o AutoRotate "preso" no estado
	-- errado se o Shift Lock já estava ligado antes de morrer
	applyAutoRotate(character, not shiftLockEnabled)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == CONTROL_LOCK_KEY then
		setShiftLock(not shiftLockEnabled)
	end
end)

-- ⚠️ MOBILE: exposto pro botão de Câmera de MobileControls.local.luau.
_G.MobileToggleShiftLock = function()
	setShiftLock(not shiftLockEnabled)
end

RunService.RenderStepped:Connect(function(dt)
	if not shiftLockEnabled then return end
	-- ⚠️ v108: reafirma a trava todo quadro (ver FootballClient no Game — ela era
	-- aplicada só no aperto e qualquer coisa que soltasse o mouse desfazia calada)
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = false end
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local lookVector = camera.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.001 then return end
	flatLook = flatLook.Unit

	local targetCFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
	local alpha = 1 - math.exp(-TURN_RESPONSIVENESS * dt)
	root.CFrame = root.CFrame:Lerp(targetCFrame, alpha)
end)

print("✅ ControlLock carregado.")
