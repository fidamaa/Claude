--[[
	DebugAbilitySelectorHUD (LocalScript) — ⚠️ FERRAMENTA DE TESTE, TEMPORÁRIA
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Par de DebugAbilitySelector.legacy.lua (ServerScriptService) — juntos
	dão uma HUD simples pra escolher, na hora, qual Pulso (slot 1 e slot
	2), Instinto e Role (GK/DF/MF/FW) testar, sem precisar passar pelo
	Roll do Lobby. APAGUE os dois quando não precisar mais testar —
	nenhum outro sistema depende deles.

	Botão "🛠" no canto: abre/fecha o painel. Dentro: 4 botões de Role no
	topo, depois a lista de Pulsos (botão "Equipar", só existe o slot 1
	hoje) e a lista de Instintos (botão "Equipar"). Tudo construído via
	Instance.new (GUI não sincroniza pela ponte de arquivos, só scripts).

	⚠️ v8: a lista de Pulsos voltou (v5.1 tinha tirado porque Data.Pulses
	estava vazio de propósito — agora tem 20, incluindo os 5 de drible
	novos).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
local DebugConfigureTesting = Config.Remotes.DebugConfigureTesting

local LocalPlayer = Players.LocalPlayer

local RARITY_COLOR = {
	Common = Color3.fromRGB(220, 220, 220),
	Rare = Color3.fromRGB(120, 180, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 60),
	Mythic = Color3.fromRGB(255, 90, 110),
}

-- ===== SHELL =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DebugAbilitySelectorHUD"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(1, 0)
toggleButton.Position = UDim2.new(1, -10, 0, 10)
toggleButton.Size = UDim2.fromOffset(44, 44)
toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 20
toggleButton.Text = "🛠"
toggleButton.Parent = screenGui
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -10, 0, 62)
panel.Size = UDim2.fromOffset(300, 480)
panel.BackgroundColor3 = Color3.fromRGB(18, 18, 24)
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = screenGui
local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel
local panelPadding = Instance.new("UIPadding")
panelPadding.PaddingTop = UDim.new(0, 8)
panelPadding.PaddingBottom = UDim.new(0, 8)
panelPadding.PaddingLeft = UDim.new(0, 8)
panelPadding.PaddingRight = UDim.new(0, 8)
panelPadding.Parent = panel

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 6)
layout.Parent = panel

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

-- ===== TÍTULO =====
local title = Instance.new("TextLabel")
title.LayoutOrder = 1
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 18)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(255, 210, 90)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "⚠️ DEBUG — apagar depois do teste"
title.Parent = panel

-- ===== ROLE (posição) =====
local roleRow = Instance.new("Frame")
roleRow.LayoutOrder = 2
roleRow.BackgroundTransparency = 1
roleRow.Size = UDim2.new(1, 0, 0, 28)
roleRow.Parent = panel
local roleLayout = Instance.new("UIListLayout")
roleLayout.FillDirection = Enum.FillDirection.Horizontal
roleLayout.Padding = UDim.new(0, 4)
roleLayout.Parent = roleRow

for _, role in ipairs({ "GK", "DF", "MF", "FW" }) do
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 66, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.Text = role
	btn.Parent = roleRow
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = btn

	btn.MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("Role", role)
	end)
end

-- ===== SEM COOLDOWN/DELAY (⚠️ NOVO) =====
-- Liga/desliga _G.SetPulseDebugNoDelay no servidor: ignora cooldown de
-- TODO Pulso e zera o wind-up (Delay) de qualquer Combo, pra testar
-- vários Pulsos seguidos sem esperar. O StepTime de cada passo do combo
-- continua de pé (senão não dá pra testar o timing de verdade).
local noDelayEnabled = false

local noDelayButton = Instance.new("TextButton")
noDelayButton.LayoutOrder = 3
noDelayButton.Size = UDim2.new(1, 0, 0, 26)
noDelayButton.BackgroundColor3 = Color3.fromRGB(70, 70, 78)
noDelayButton.TextColor3 = Color3.fromRGB(255, 255, 255)
noDelayButton.Font = Enum.Font.GothamBold
noDelayButton.TextSize = 12
noDelayButton.Text = "Sem Cooldown/Delay: OFF"
noDelayButton.Parent = panel
local noDelayCorner = Instance.new("UICorner")
noDelayCorner.CornerRadius = UDim.new(0, 6)
noDelayCorner.Parent = noDelayButton

local function refreshNoDelayButton()
	noDelayButton.BackgroundColor3 = noDelayEnabled and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(70, 70, 78)
	noDelayButton.Text = noDelayEnabled and "Sem Cooldown/Delay: ON" or "Sem Cooldown/Delay: OFF"
end

noDelayButton.MouseButton1Click:Connect(function()
	noDelayEnabled = not noDelayEnabled
	refreshNoDelayButton()
	DebugConfigureTesting:FireServer("NoDelay", noDelayEnabled)
end)

-- ===== REESPAWNAR BOLA (⚠️ NOVO) =====
-- Pra quando a bola buga/some: manda o servidor reposicionar ela no
-- centro do campo (ver kind "RespawnBall" em DebugAbilitySelector.legacy.lua).
local respawnBallButton = Instance.new("TextButton")
respawnBallButton.LayoutOrder = 4
respawnBallButton.Size = UDim2.new(1, 0, 0, 26)
respawnBallButton.BackgroundColor3 = Color3.fromRGB(220, 90, 90)
respawnBallButton.TextColor3 = Color3.fromRGB(255, 255, 255)
respawnBallButton.Font = Enum.Font.GothamBold
respawnBallButton.TextSize = 12
respawnBallButton.Text = "⚽ Reespawnar Bola (Centro)"
respawnBallButton.Parent = panel
local respawnBallCorner = Instance.new("UICorner")
respawnBallCorner.CornerRadius = UDim.new(0, 6)
respawnBallCorner.Parent = respawnBallButton

respawnBallButton.MouseButton1Click:Connect(function()
	DebugConfigureTesting:FireServer("RespawnBall", true)
end)

-- ===== LISTA GENÉRICA (Pulsos com S1/S2, Instintos com Equipar) =====
local function addSectionLabel(parent, order, text)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = order
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 16)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(180, 180, 190)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	label.Parent = parent
end

local function makeScrollingList(order, sizeY)
	local scroll = Instance.new("ScrollingFrame")
	scroll.LayoutOrder = order
	scroll.Size = UDim2.new(1, 0, 0, sizeY)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 4
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 2)
	listLayout.Parent = scroll

	return scroll
end

-- ⚠️ v8: a seção de PULSOS voltou — Data.Pulses tem 20 agora (v5.1 tinha
-- tirado daqui porque a lista ficava vazia de propósito).
addSectionLabel(panel, 6, "HISSATSU (tecla 1 · Equipar manda pro slot único)")
local pulseList = makeScrollingList(7, 220)

for i, def in ipairs(PulseData.Pulses) do
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	row.Size = UDim2.new(1, 0, 0, 24)
	row.Parent = pulseList
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 5)
	rowCorner.Parent = row

	local swatch = Instance.new("Frame")
	swatch.Position = UDim2.new(0, 5, 0.5, 0)
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Size = UDim2.fromOffset(10, 10)
	swatch.BackgroundColor3 = RARITY_COLOR[def.Rarity] or Color3.fromRGB(120, 120, 120)
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(1, 0)
	swatchCorner.Parent = swatch

	-- Action (Shot/Tackle/DribbleMove/Buff), pra saber o que esperar sem
	-- abrir o código toda vez que for testar um Pulso.
	local comoLabel = Instance.new("TextLabel")
	comoLabel.BackgroundTransparency = 1
	comoLabel.Position = UDim2.new(1, -108, 0, 0)
	comoLabel.Size = UDim2.fromOffset(42, 24)
	comoLabel.Font = Enum.Font.GothamBold
	comoLabel.TextSize = 9
	comoLabel.TextXAlignment = Enum.TextXAlignment.Right
	comoLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
	comoLabel.Text = tostring(def.Action or "?")
	comoLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 20, 0, 0)
	nameLabel.Size = UDim2.new(1, -130, 1, 0)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 11
	nameLabel.TextColor3 = RARITY_COLOR[def.Rarity] or Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = def.Name
	nameLabel.Parent = row

	local equipButton = Instance.new("TextButton")
	equipButton.AnchorPoint = Vector2.new(1, 0.5)
	equipButton.Position = UDim2.new(1, -2, 0.5, 0)
	equipButton.Size = UDim2.fromOffset(60, 18)
	equipButton.BackgroundColor3 = Color3.fromRGB(80, 160, 220)
	equipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 11
	equipButton.Text = "Equipar"
	equipButton.Parent = row
	local equipCorner = Instance.new("UICorner")
	equipCorner.CornerRadius = UDim.new(0, 4)
	equipCorner.Parent = equipButton

	equipButton.MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("Pulse", def.Name)
	end)
end

addSectionLabel(panel, 8, "ARMAS (R = aperta · AUTO = sozinho · — = passivo)")
local instinctList = makeScrollingList(9, 300)

for i, def in ipairs(PulseData.Instincts) do
	local row = Instance.new("Frame")
	row.LayoutOrder = i
	row.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
	row.Size = UDim2.new(1, 0, 0, 24)
	row.Parent = instinctList
	local rowCorner = Instance.new("UICorner")
	rowCorner.CornerRadius = UDim.new(0, 5)
	rowCorner.Parent = row

	-- ⚠️ v5.1: quadradinho com a COR DA AURA daquele instinto — é a mesma
	-- cor que o jogador acende em campo quando a condição bate, então dá
	-- pra conferir na hora se o que acendeu foi o instinto certo.
	local swatch = Instance.new("Frame")
	swatch.Position = UDim2.new(0, 5, 0.5, 0)
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Size = UDim2.fromOffset(10, 10)
	swatch.BackgroundColor3 = def.Cor or Color3.fromRGB(120, 120, 120)
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	local swatchCorner = Instance.new("UICorner")
	swatchCorner.CornerRadius = UDim.new(1, 0)
	swatchCorner.Parent = swatch

	-- Como esse instinto dispara, pra não testar apertando R num passivo.
	local comoLabel = Instance.new("TextLabel")
	comoLabel.BackgroundTransparency = 1
	comoLabel.Position = UDim2.new(1, -108, 0, 0)
	comoLabel.Size = UDim2.fromOffset(42, 24)
	comoLabel.Font = Enum.Font.GothamBold
	comoLabel.TextSize = 10
	comoLabel.TextXAlignment = Enum.TextXAlignment.Right
	if def.Tecla then
		comoLabel.Text = def.Tecla
		comoLabel.TextColor3 = Color3.fromRGB(255, 205, 60)
	elseif def.AtivaAction then
		comoLabel.Text = "AUTO"
		comoLabel.TextColor3 = Color3.fromRGB(120, 200, 255)
	else
		comoLabel.Text = "—"
		comoLabel.TextColor3 = Color3.fromRGB(110, 110, 120)
	end
	comoLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 20, 0, 0)
	nameLabel.Size = UDim2.new(1, -130, 1, 0)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 11
	nameLabel.TextColor3 = RARITY_COLOR[def.Rarity] or Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = def.Name
	nameLabel.Parent = row

	local equipButton = Instance.new("TextButton")
	equipButton.AnchorPoint = Vector2.new(1, 0.5)
	equipButton.Position = UDim2.new(1, -2, 0.5, 0)
	equipButton.Size = UDim2.fromOffset(60, 18)
	equipButton.BackgroundColor3 = Color3.fromRGB(80, 200, 120)
	equipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 11
	equipButton.Text = "Equipar"
	equipButton.Parent = row
	local equipCorner = Instance.new("UICorner")
	equipCorner.CornerRadius = UDim.new(0, 4)
	equipCorner.Parent = equipButton

	equipButton.MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("Instinct", def.Name)
	end)
end
