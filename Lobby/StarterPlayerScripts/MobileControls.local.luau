--[[
	MobileControls (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Lobby)

	Suporte mobile SIMPLES pro Lobby: aqui quase tudo já é botão de GUI
	(Loja, Matchmaking, Missões, Diálogo por ProximityPrompt, Roll,
	Customização de personagem com botão próprio) — então já funciona no
	toque sem mudar nada. O que faltava mesmo eram as DUAS coisas que só
	existiam como tecla: Sprint (segurar Shift) e Câmera/Shift Lock
	(alternar Ctrl). Só isso aqui.

	Só é criado em dispositivo touch "de verdade" (celular/tablet — sem
	mouse); em PC continua tudo igual, no teclado.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local function isMobileDevice()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

if not isMobileDevice() then
	return
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MobileControlsGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local function makeButton(props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.Size = props.Size or UDim2.fromOffset(60, 60)
	button.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	button.Position = props.Position
	button.BackgroundColor3 = props.Color or Color3.fromRGB(25, 25, 30)
	button.BackgroundTransparency = 0.25
	button.Text = props.Text or "?"
	button.Font = Enum.Font.GothamBlack
	button.TextSize = props.TextSize or 13
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = true
	button.ZIndex = 5
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = button

	return button
end

-- ===== SPRINT (segurar) =====
local sprintButton = makeButton({
	Name = "Sprint",
	Text = "SPRINT",
	TextSize = 13,
	Size = UDim2.fromOffset(76, 76),
	AnchorPoint = Vector2.new(1, 1),
	-- ⚠️ Deslocado pro lado (mais pra esquerda) pra não ficar em cima do
	-- botão de PULAR nativo do Roblox, que fica no canto inferior direito.
	Position = UDim2.new(1, -130, 1, -20),
	Color = Color3.fromRGB(40, 110, 200),
})
sprintButton.MouseButton1Down:Connect(function()
	_G.MobileSetSprinting(true)
end)
sprintButton.MouseButton1Up:Connect(function()
	_G.MobileSetSprinting(false)
end)
sprintButton.MouseLeave:Connect(function()
	_G.MobileSetSprinting(false)
end)

-- ===== CÂMERA / SHIFT LOCK (toggle) =====
local cameraButton = makeButton({
	Name = "ShiftLock",
	Text = "CÂMERA",
	TextSize = 11,
	Size = UDim2.fromOffset(56, 56),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -110),
})
cameraButton.MouseButton1Click:Connect(function()
	_G.MobileToggleShiftLock()
end)

print("✅ MobileControls (Lobby) carregado — controles touch ativos.")
