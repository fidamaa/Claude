--[[
	CharacterClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Tela ÚNICA de personagem: seleção de slots (esquerda) + teia de
	habilidade (direita), toda construída por código (mesmo padrão do
	MatchmakingClient.lua) — não depende de nada pronto no Explorer,
	então não esbarra na limitação de sync de GUI.

	Substitui o antigo par role_client_final / AttributeDisplayClient
	(que viviam soltos dentro de StarterGui, fora do que dá pra
	sincronizar por aqui). Remova/desative aqueles dois no Studio pra
	evitar UI duplicada e chamadas concorrentes nos mesmos remotes.

	Remotes usados (ReplicatedStorage.LobbyEvents):
	- GetSlotsOverview (RemoteFunction, NOVO): resumo dos 5 slots
	- SetActiveSlot    (RemoteFunction, NOVO): troca o personagem ativo
	- GetLevelData     (RemoteFunction): dados completos de UM slot
	- AddAttributePoint(RemoteFunction): investe 1 ponto num atributo
	- UpdateSlotName   (RemoteFunction): renomeia um slot
	- UpdateLevelData  (RemoteEvent): push do servidor (XP, level up, etc)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

-- ⚠️ v110: string.upper não põe acento em maiúscula ("Fúria" virava "FúRIA").
-- Converte também as letras acentuadas (UTF-8 à..þ → À..Þ).
local function maiusculas(s)
	s = string.upper(tostring(s))
	return (s:gsub("\195([\160-\190])", function(c)
		local b = string.byte(c)
		if b ~= 183 then return "\195" .. string.char(b - 32) end
	end))
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder = ReplicatedStorage:WaitForChild("LobbyEvents")
local GetSlotsOverview = eventsFolder:WaitForChild("GetSlotsOverview")
local SetActiveSlotRemote = eventsFolder:WaitForChild("SetActiveSlot")
local GetLevelData = eventsFolder:WaitForChild("GetLevelData")
local AddAttributePoint = eventsFolder:WaitForChild("AddAttributePoint")
local UpdateSlotName = eventsFolder:WaitForChild("UpdateSlotName")
local UpdateLevelDataEvent = eventsFolder:WaitForChild("UpdateLevelData")
local SetSlotRoleRemote = eventsFolder:WaitForChild("SetSlotRole")

-- ⚠️ v102 — VISUAL NOVO DA FICHA. PEDIDO: "melhore a HUD dos atributos...
-- tira esses emojis, eu odeio emoji... faz o negócio mais bonitinho, combina
-- com o restante das HUDs". Mesma paleta/tipografia do Roll, Missões,
-- Matchmaking e diálogo (ver a skill ui-lobby). Nada de emoji: elemento vira
-- um chip colorido com o nome, "sorte" vira 5 barrinhas, cadeado vira texto.
-- A lógica (remotes, render da teia, slots) continua a mesma de antes.
local ROLE_LABELS = { GK = "GOL", LINE = "LINHA" }

-- paleta do Lobby
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_ACENTO_CLARO = Color3.fromRGB(125, 185, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_OURO        = Color3.fromRGB(255, 200, 70)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

-- cor de cada elemento (Config.ELEMENTS no LobbyConfig) — no lugar do emoji
local ELEMENT_COLORS = {
	Natureza = Color3.fromRGB(110, 210, 110),
	Fogo = Color3.fromRGB(255, 120, 60),
	Vento = Color3.fromRGB(90, 220, 200),
	Luz = Color3.fromRGB(255, 215, 90),
	Void = Color3.fromRGB(170, 110, 255),
}

-- ===== ATRIBUTOS =====
-- ⚠️ v98 — TÉCNICA REMOVIDA (o que ela fazia virou do Drible). A teia é um
-- hexágono (ATTR_ANGLES deriva de #ATTRIBUTE_ORDER).
local ATTRIBUTE_ORDER = { "Physical", "DribbleSkill", "Speed", "Kick", "Energy", "Stamina" }
local ATTRIBUTE_LABELS = {
	Physical = "FÍSICO",
	DribbleSkill = "DRIBLE",
	Speed = "VELOCIDADE",
	Kick = "CHUTE",
	Energy = "ENERGIA",
	Stamina = "FÔLEGO",
}
-- o que cada um faz (aparece embaixo da teia ao passar o mouse/tocar)
local ATTRIBUTE_DESCRIPTIONS = {
	Physical = "Segura carrinho, ganha disputa de corpo e fortalece as Hissatsus de defesa e de goleiro.",
	DribbleSkill = "Finta, domínio e primeiro toque — e a força das Hissatsus de drible.",
	Speed = "O quanto você corre.",
	Kick = "Força e alcance do chute — e a força das Hissatsus de chute.",
	Energy = "Quantas Hissatsus você consegue soltar numa partida.",
	Stamina = "Quantas jogadas seguidas você aguenta sem cansar.",
}

-- ===== GEOMETRIA DA TEIA =====
local WEB_SIZE = Vector2.new(400, 340)
local WEB_CENTER = Vector2.new(200, 168)
local WEB_RADIUS = 122 -- (135 encostava o nó de baixo na descrição)
local WEB_MIN_FRACTION = 0.1
local WEB_VALUE_CAP = 100

local ATTR_ANGLES = {}
local ATTR_COUNT = #ATTRIBUTE_ORDER
local ATTR_ANGLE_STEP = 360 / ATTR_COUNT
for i = 1, ATTR_COUNT do
	ATTR_ANGLES[i] = math.rad(-90 + (i - 1) * ATTR_ANGLE_STEP)
end

local function pointOnWeb(index, fraction)
	local angle = ATTR_ANGLES[index]
	return WEB_CENTER + Vector2.new(math.cos(angle), math.sin(angle)) * (WEB_RADIUS * fraction)
end

local function drawLine(parent, pointA, pointB, thickness, color, transparency, zIndex)
	local delta = pointB - pointA
	local distance = math.max(delta.Magnitude, 0.01)
	local angle = math.deg(math.atan2(delta.Y, delta.X))
	local line = Instance.new("Frame")
	line.Name = "Line"
	line.AnchorPoint = Vector2.new(0.5, 0.5)
	line.Position = UDim2.fromOffset((pointA.X + pointB.X) / 2, (pointA.Y + pointB.Y) / 2)
	line.Size = UDim2.fromOffset(distance, thickness)
	line.Rotation = angle
	line.BackgroundColor3 = color
	line.BackgroundTransparency = transparency or 0
	line.BorderSizePixel = 0
	line.ZIndex = zIndex or 1
	line.Parent = parent
	return line
end

local function cantos(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end
local function contorno(inst, cor, espessura, transparencia)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = espessura or 1
	s.Transparency = transparencia or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
local function texto(pai, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamMedium
	l.TextColor3 = COR_TEXTO
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do l[k] = v end
	l.Parent = pai
	return l
end

-- ===== GUI RAIZ =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharacterGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

-- ⚠️ v68: o botão flutuante "PERSONAGEM (P)" foi removido — quem abre a
-- ficha é o kogamalotigo (DialogueData, ação OpenCharacter); a tecla P
-- continua funcionando no PC. `toggleButton` fica como objeto-ponte.
local toggleButton = { MouseButton1Click = { Connect = function() end } }

local PAINEL_W, PAINEL_H = 940, 600
local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(PAINEL_W, PAINEL_H)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = COR_PAINEL
mainFrame.Visible = false
mainFrame.Parent = screenGui
cantos(mainFrame, 10)
contorno(mainFrame, COR_BORDA, 1, 0.15)

-- cabe em qualquer tela (celular incluso), e cresce um pouco em tela grande
local escala = Instance.new("UIScale")
escala.Parent = mainFrame
local function ajustarEscala()
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if not v or v.X <= 0 then return end
	escala.Scale = math.min(1.15, (v.X - 32) / PAINEL_W, (v.Y - 32) / PAINEL_H)
end
ajustarEscala()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- cabeçalho: | PERSONAGEM ......................... [X]
local cabecalho = Instance.new("Frame")
cabecalho.Name = "Cabecalho"
cabecalho.Size = UDim2.new(1, 0, 0, 56)
cabecalho.BackgroundColor3 = COR_CARTAO
cabecalho.BorderSizePixel = 0
cabecalho.Parent = mainFrame
cantos(cabecalho, 10)
local cabecalhoBase = Instance.new("Frame") -- tira o arredondado de baixo do cabeçalho
cabecalhoBase.BackgroundColor3 = COR_CARTAO
cabecalhoBase.BorderSizePixel = 0
cabecalhoBase.Position = UDim2.new(0, 0, 1, -10)
cabecalhoBase.Size = UDim2.new(1, 0, 0, 10)
cabecalhoBase.Parent = cabecalho

local barraTitulo = Instance.new("Frame")
barraTitulo.BackgroundColor3 = COR_ACENTO
barraTitulo.BorderSizePixel = 0
barraTitulo.AnchorPoint = Vector2.new(0, 0.5)
barraTitulo.Position = UDim2.new(0, 20, 0.5, 0)
barraTitulo.Size = UDim2.fromOffset(4, 22)
barraTitulo.Parent = cabecalho
cantos(barraTitulo, 2)

local title = texto(cabecalho, {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 34, 0.5, 0), Size = UDim2.fromOffset(400, 30),
	Font = Enum.Font.GothamBlack, TextSize = 20, Text = "PERSONAGEM",
})

local closeButton = Instance.new("TextButton")
closeButton.AnchorPoint = Vector2.new(1, 0.5)
closeButton.Position = UDim2.new(1, -12, 0.5, 0)
closeButton.Size = UDim2.fromOffset(34, 34)
closeButton.BackgroundColor3 = COR_CARTAO_ALT
closeButton.Text = "X"
closeButton.TextColor3 = COR_TEXTO
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.Parent = cabecalho
cantos(closeButton, 17)

-- ===== SIDEBAR (SLOTS) =====
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.fromOffset(290, PAINEL_H - 56 - 32)
sidebar.Position = UDim2.fromOffset(16, 56 + 16)
sidebar.BackgroundTransparency = 1
sidebar.Parent = mainFrame

local slotListLayout = Instance.new("UIListLayout")
slotListLayout.Padding = UDim.new(0, 8)
slotListLayout.SortOrder = Enum.SortOrder.LayoutOrder
slotListLayout.Parent = sidebar

local slotCards = {}

local function createSlotCard(index)
	local card = Instance.new("TextButton")
	card.Name = "Slot" .. index
	card.Size = UDim2.new(1, 0, 0, 74)
	card.BackgroundColor3 = COR_CARTAO
	card.AutoButtonColor = false
	card.Text = ""
	card.LayoutOrder = index
	card.Parent = sidebar
	cantos(card, 8)
	local stroke = contorno(card, COR_BORDA, 1, 0)

	local nameLabel = texto(card, {
		Position = UDim2.fromOffset(14, 10), Size = UDim2.new(1, -96, 0, 20),
		Font = Enum.Font.GothamBlack, TextSize = 15, Text = "—", TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local infoLabel = texto(card, {
		Position = UDim2.fromOffset(14, 32), Size = UDim2.new(1, -28, 0, 16),
		TextSize = 12, TextColor3 = COR_TEXTO_MEDIO, RichText = true, Text = "",
	})

	-- sorte (1-5): 5 barrinhas douradas no lugar das estrelas
	local sorte = Instance.new("Frame")
	sorte.Name = "Sorte"
	sorte.BackgroundTransparency = 1
	sorte.Position = UDim2.fromOffset(14, 54)
	sorte.Size = UDim2.fromOffset(120, 8)
	sorte.Parent = card
	local sorteLayout = Instance.new("UIListLayout")
	sorteLayout.FillDirection = Enum.FillDirection.Horizontal
	sorteLayout.Padding = UDim.new(0, 4)
	sorteLayout.Parent = sorte
	local pips = {}
	for p = 1, 5 do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.fromOffset(18, 6)
		pip.BorderSizePixel = 0
		pip.BackgroundColor3 = COR_CARTAO_ALT
		pip.LayoutOrder = p
		pip.Parent = sorte
		cantos(pip, 3)
		pips[p] = pip
	end
	local sorteRotulo = texto(card, {
		Position = UDim2.fromOffset(136, 49), Size = UDim2.fromOffset(80, 16),
		TextSize = 11, TextColor3 = COR_TEXTO_FRACO, Text = "",
	})

	local activeTag = texto(card, {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(60, 20),
		BackgroundTransparency = 0, BackgroundColor3 = COR_OK, TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack, TextSize = 11, Text = "ATIVO", Visible = false,
	})
	cantos(activeTag, 6)

	local lockIcon = texto(card, {
		Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = COR_TEXTO_FRACO, RichText = true,
		Text = 'BLOQUEADO<br/><font size="11" weight="medium" color="#788094">destrave na Loja</font>', Visible = false,
	})

	slotCards[index] = {
		Frame = card, Stroke = stroke, NameLabel = nameLabel, InfoLabel = infoLabel,
		Pips = pips, SorteRotulo = sorteRotulo, Sorte = sorte, ActiveTag = activeTag, LockIcon = lockIcon,
	}
	card.MouseEnter:Connect(function()
		if not lockIcon.Visible then card.BackgroundColor3 = COR_CARTAO_ALT end
	end)
	card.MouseLeave:Connect(function()
		card.BackgroundColor3 = COR_CARTAO
	end)
	return card
end

for i = 1, 5 do
	createSlotCard(i)
end

local function setStars(card, stars)
	for p, pip in ipairs(card.Pips) do
		pip.BackgroundColor3 = p <= stars and COR_OURO or COR_CARTAO_ALT
	end
	card.SorteRotulo.Text = string.format("sorte %d/5", stars)
end

local playButton = Instance.new("TextButton")
playButton.Name = "PlayButton"
playButton.Size = UDim2.new(1, 0, 0, 40)
playButton.LayoutOrder = 99
playButton.BackgroundColor3 = COR_ACENTO
playButton.Text = "JOGAR COM ESTE"
playButton.TextColor3 = Color3.new(1, 1, 1)
playButton.Font = Enum.Font.GothamBlack
playButton.TextSize = 14
playButton.Visible = false
playButton.Parent = sidebar
cantos(playButton, 8)

local renameRow = Instance.new("Frame")
renameRow.Name = "RenameRow"
renameRow.Size = UDim2.new(1, 0, 0, 36)
renameRow.LayoutOrder = 100
renameRow.BackgroundTransparency = 1
renameRow.Visible = false
renameRow.Parent = sidebar

local renameBox = Instance.new("TextBox")
renameBox.Size = UDim2.new(1, -84, 1, 0)
renameBox.BackgroundColor3 = COR_CARTAO
renameBox.TextColor3 = COR_TEXTO
renameBox.PlaceholderText = "Renomear personagem..."
renameBox.PlaceholderColor3 = COR_TEXTO_FRACO
renameBox.Font = Enum.Font.GothamMedium
renameBox.TextSize = 13
renameBox.ClearTextOnFocus = false
renameBox.Parent = renameRow
cantos(renameBox, 8)
contorno(renameBox, COR_BORDA, 1, 0)
local renamePad = Instance.new("UIPadding")
renamePad.PaddingLeft = UDim.new(0, 10)
renamePad.Parent = renameBox

local renameButton = Instance.new("TextButton")
renameButton.Size = UDim2.new(0, 76, 1, 0)
renameButton.Position = UDim2.new(1, -76, 0, 0)
renameButton.BackgroundColor3 = COR_CARTAO_ALT
renameButton.Text = "SALVAR"
renameButton.TextColor3 = COR_ACENTO_CLARO
renameButton.Font = Enum.Font.GothamBlack
renameButton.TextSize = 12
renameButton.Parent = renameRow
cantos(renameButton, 8)
contorno(renameButton, COR_ACENTO, 1, 0.5)

-- ===== PAINEL DA TEIA =====
local webPanel = Instance.new("Frame")
webPanel.Name = "WebPanel"
webPanel.Size = UDim2.fromOffset(PAINEL_W - 290 - 16 * 3, PAINEL_H - 56 - 32)
webPanel.Position = UDim2.fromOffset(16 + 290 + 16, 56 + 16)
webPanel.BackgroundColor3 = COR_CARTAO
webPanel.Parent = mainFrame
cantos(webPanel, 10)
contorno(webPanel, COR_BORDA, 1, 0.25)

local slotTitleLabel = texto(webPanel, {
	Position = UDim2.fromOffset(20, 16), Size = UDim2.new(1, -240, 0, 26),
	Font = Enum.Font.GothamBlack, TextSize = 20, Text = "Selecione um personagem", TextTruncate = Enum.TextTruncate.AtEnd,
})

-- chips à direita: [NÍVEL 50] [FOGO]
local levelBadge = texto(webPanel, {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 16), Size = UDim2.fromOffset(96, 26),
	BackgroundTransparency = 0, BackgroundColor3 = COR_CARTAO_ALT, TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = COR_OURO, Text = "NÍVEL —",
})
cantos(levelBadge, 6)
contorno(levelBadge, COR_OURO, 1, 0.6)

local elementBadge = texto(webPanel, {
	Name = "ElementBadge", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -120, 0, 16), Size = UDim2.fromOffset(96, 26),
	BackgroundTransparency = 0, BackgroundColor3 = COR_CARTAO_ALT, TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBlack, TextSize = 13, Text = "",
})
cantos(elementBadge, 6)
local elementStroke = contorno(elementBadge, COR_BORDA, 1, 0.4)

-- checkbox de goleiro
local roleRow = Instance.new("Frame")
roleRow.Name = "GKCheckboxRow"
roleRow.Size = UDim2.new(1, -40, 0, 26)
roleRow.Position = UDim2.fromOffset(20, 50)
roleRow.BackgroundTransparency = 1
roleRow.Parent = webPanel
local roleRowLayout = Instance.new("UIListLayout")
roleRowLayout.FillDirection = Enum.FillDirection.Horizontal
roleRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
roleRowLayout.Padding = UDim.new(0, 8)
roleRowLayout.Parent = roleRow

local gkCheckboxButton = Instance.new("TextButton")
gkCheckboxButton.Name = "GKCheckbox"
gkCheckboxButton.Size = UDim2.fromOffset(22, 22)
gkCheckboxButton.BackgroundColor3 = COR_CARTAO_ALT
gkCheckboxButton.Text = ""
gkCheckboxButton.Font = Enum.Font.GothamBlack
gkCheckboxButton.TextSize = 14
gkCheckboxButton.TextColor3 = Color3.new(1, 1, 1)
gkCheckboxButton.Parent = roleRow
cantos(gkCheckboxButton, 6)
local gkCheckboxStroke = contorno(gkCheckboxButton, COR_BORDA, 1.5, 0)

texto(roleRow, {
	Name = "GKCheckboxLabel", Size = UDim2.fromOffset(220, 22),
	Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = COR_TEXTO_MEDIO, Text = "Jogar como goleiro",
})

-- a teia
local webContainer = Instance.new("Frame")
webContainer.Name = "Web"
webContainer.Size = UDim2.fromOffset(WEB_SIZE.X, WEB_SIZE.Y)
webContainer.Position = UDim2.new(0.5, -WEB_SIZE.X / 2, 0, 76)
webContainer.BackgroundTransparency = 1
webContainer.Parent = webPanel

local ringsFolder = Instance.new("Folder", webContainer)
ringsFolder.Name = "Rings"
for _, fraction in ipairs({ 0.25, 0.5, 0.75, 1 }) do
	for i = 1, ATTR_COUNT do
		local nextI = (i % ATTR_COUNT) + 1
		drawLine(ringsFolder, pointOnWeb(i, fraction), pointOnWeb(nextI, fraction), 1,
			fraction == 1 and Color3.fromRGB(60, 68, 92) or COR_BORDA, fraction == 1 and 0 or 0.1, 2)
	end
end
local spokesFolder = Instance.new("Folder", webContainer)
spokesFolder.Name = "Spokes"
for i = 1, ATTR_COUNT do
	drawLine(spokesFolder, WEB_CENTER, pointOnWeb(i, 1), 1, COR_BORDA, 0.1, 2)
end

local valuePolygonFolder = Instance.new("Folder", webContainer)
valuePolygonFolder.Name = "ValuePolygon"

local function clearFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

-- descrição do atributo sob o mouse
local attrDescLabel = texto(webPanel, {
	Name = "AtributoDescricao", Position = UDim2.new(0, 20, 1, -100), Size = UDim2.new(1, -40, 0, 30),
	TextSize = 13, TextColor3 = COR_TEXTO_MEDIO, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
	RichText = true, Text = "",
})
local DICA_PADRAO = '<font color="#788094">passe o mouse (ou toque) num atributo pra ver o que ele faz</font>'
attrDescLabel.Text = DICA_PADRAO

local attributeNodes = {}
for i, attrName in ipairs(ATTRIBUTE_ORDER) do
	local pos = pointOnWeb(i, 1)
	local nodeButton = Instance.new("TextButton") -- botão: dá pra tocar no celular pra ver a descrição
	nodeButton.Name = attrName
	nodeButton.Text = ""
	nodeButton.AutoButtonColor = false
	nodeButton.Size = UDim2.fromOffset(92, 52)
	nodeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	nodeButton.Position = UDim2.fromOffset(pos.X, pos.Y)
	nodeButton.BackgroundColor3 = COR_CARTAO_ALT
	nodeButton.ZIndex = 3
	nodeButton.Parent = webContainer
	cantos(nodeButton, 8)
	local nodeStroke = contorno(nodeButton, COR_BORDA, 1, 0)

	texto(nodeButton, {
		Position = UDim2.fromOffset(0, 6), Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = COR_ACENTO_CLARO, Text = ATTRIBUTE_LABELS[attrName], ZIndex = 3,
	})
	local valueLabel = texto(nodeButton, {
		Position = UDim2.fromOffset(0, 21), Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBlack, TextSize = 20, Text = "0", ZIndex = 3,
	})

	local plusButton = Instance.new("TextButton")
	plusButton.Size = UDim2.fromOffset(24, 24)
	plusButton.AnchorPoint = Vector2.new(0.5, 0.5)
	plusButton.Position = UDim2.new(1, -2, 0, 2)
	plusButton.BackgroundColor3 = COR_OK
	plusButton.Text = "+"
	plusButton.TextColor3 = Color3.new(1, 1, 1)
	plusButton.Font = Enum.Font.GothamBlack
	plusButton.TextSize = 16
	plusButton.Visible = false
	plusButton.ZIndex = 4
	plusButton.Parent = nodeButton
	cantos(plusButton, 12)

	local function mostrar()
		nodeStroke.Color = COR_ACENTO
		attrDescLabel.Text = string.format('<font color="#7DB9FF"><b>%s</b></font>  %s', ATTRIBUTE_LABELS[attrName], ATTRIBUTE_DESCRIPTIONS[attrName] or "")
	end
	nodeButton.MouseEnter:Connect(mostrar)
	nodeButton.MouseButton1Click:Connect(mostrar)
	nodeButton.MouseLeave:Connect(function()
		nodeStroke.Color = COR_BORDA
		attrDescLabel.Text = DICA_PADRAO
	end)

	attributeNodes[attrName] = { NodeButton = nodeButton, ValueLabel = valueLabel, PlusButton = plusButton, Stroke = nodeStroke }
end

-- pontos disponíveis + barra de XP
local pointsLabel = texto(webPanel, {
	Position = UDim2.new(0, 20, 1, -62), Size = UDim2.new(1, -40, 0, 18),
	Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = COR_OURO, Text = "",
})

local xpBarBack = Instance.new("Frame")
xpBarBack.Size = UDim2.new(1, -40, 0, 18)
xpBarBack.Position = UDim2.new(0, 20, 1, -36)
xpBarBack.BackgroundColor3 = COR_CARTAO_ALT
xpBarBack.BorderSizePixel = 0
xpBarBack.Parent = webPanel
cantos(xpBarBack, 9)

local xpBarFill = Instance.new("Frame")
xpBarFill.Size = UDim2.new(0, 0, 1, 0)
xpBarFill.BackgroundColor3 = COR_ACENTO
xpBarFill.BorderSizePixel = 0
xpBarFill.Parent = xpBarBack
cantos(xpBarFill, 9)

local xpLabel = texto(xpBarBack, {
	Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
	Font = Enum.Font.GothamBold, TextSize = 11, Text = "", ZIndex = 2,
})

-- ===== ESTADO =====
local previewSlotIndex = nil
local activeSlotIndex = nil
local currentSlotData = nil -- resposta crua do GetLevelData pro slot em preview
local lastOverview = nil -- última resposta crua do GetSlotsOverview (pra saber o Role atual)

-- ⚠️ v10: era um seletor de 4 botões (GK/DF/MF/FW) — agora só marca/
-- desmarca o checkbox único de goleiro.
local function highlightSelectedRole(currentRole)
	local isGK = currentRole == "GK"
	gkCheckboxButton.BackgroundColor3 = isGK and COR_ACENTO or COR_CARTAO_ALT
	gkCheckboxStroke.Color = isGK and COR_ACENTO_CLARO or COR_BORDA
	gkCheckboxButton.Text = isGK and "✓" or ""
end

-- ===== RENDER DA TEIA (valores atuais) =====
local function renderWeb(slotData)
	currentSlotData = slotData
	clearFolder(valuePolygonFolder)

	if not slotData then
		levelBadge.Text = "NÍVEL —"
		elementBadge.Text = ""
		elementBadge.Visible = false
		pointsLabel.Text = ""
		xpLabel.Text = ""
		xpBarFill.Size = UDim2.new(0, 0, 1, 0)
		for _, attrName in ipairs(ATTRIBUTE_ORDER) do
			attributeNodes[attrName].ValueLabel.Text = "—"
			attributeNodes[attrName].PlusButton.Visible = false
		end
		return
	end

	levelBadge.Text = "NÍVEL " .. tostring(slotData.Level or 1)
	-- elemento: chip colorido só com o nome (sem emoji)
	local corElemento = slotData.Element and ELEMENT_COLORS[slotData.Element]
	elementBadge.Visible = slotData.Element ~= nil
	elementBadge.Text = slotData.Element and maiusculas(slotData.Element) or ""
	elementBadge.TextColor3 = corElemento or COR_TEXTO_MEDIO
	elementStroke.Color = corElemento or COR_BORDA

	if slotData.IsMaxLevel then
		xpBarFill.Size = UDim2.new(1, 0, 1, 0)
		xpBarFill.BackgroundColor3 = COR_OURO
		xpLabel.TextColor3 = COR_PAINEL -- texto escuro no dourado
		xpLabel.Text = "NÍVEL MÁXIMO"
	else
		local xpNeeded = math.max(slotData.XPNeeded or 1, 1)
		local xpFraction = math.clamp((slotData.CurrentXP or 0) / xpNeeded, 0, 1)
		xpBarFill.Size = UDim2.new(xpFraction, 0, 1, 0)
		xpBarFill.BackgroundColor3 = COR_ACENTO
		xpLabel.TextColor3 = COR_TEXTO
		xpLabel.Text = string.format("%d / %d XP", slotData.CurrentXP or 0, xpNeeded)
	end

	local points = slotData.AttributePoints or 0
	local canEdit = previewSlotIndex ~= nil
	if points > 0 then
		pointsLabel.Text = string.format("%d PONTO%s PRA DISTRIBUIR — clique no + do atributo", points, points == 1 and "" or "S")
		pointsLabel.TextColor3 = COR_OURO
	else
		pointsLabel.Text = "sem pontos pra distribuir agora — suba de nível pra ganhar mais"
		pointsLabel.TextColor3 = COR_TEXTO_FRACO
	end

	local valuePoints = {}
	for i, attrName in ipairs(ATTRIBUTE_ORDER) do
		local value = (slotData.Attributes and slotData.Attributes[attrName]) or 0
		attributeNodes[attrName].ValueLabel.Text = tostring(value)
		attributeNodes[attrName].PlusButton.Visible = canEdit and points > 0

		local fraction = math.clamp(value / WEB_VALUE_CAP, WEB_MIN_FRACTION, 1)
		valuePoints[i] = pointOnWeb(i, fraction)
	end

	-- Contorno do polígono de valor (a "teia" preenchida com sua forma)
	for i = 1, ATTR_COUNT do
		local nextI = (i % ATTR_COUNT) + 1
		drawLine(valuePolygonFolder, valuePoints[i], valuePoints[nextI], 3, COR_ACENTO_CLARO, 0, 3)
		drawLine(valuePolygonFolder, WEB_CENTER, valuePoints[i], 2, COR_ACENTO, 0.55, 2) -- "preenchimento" leve
	end
	-- Pontinhos nos vértices do polígono de valor
	for i = 1, ATTR_COUNT do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(valuePoints[i].X, valuePoints[i].Y)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = COR_TEXTO
		dot.ZIndex = 3
		dot.Parent = valuePolygonFolder
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
	end
end

-- ===== CARREGAR DADOS DE UM SLOT (preview) =====
local function loadSlotIntoWeb(slotIndex)
	local ok, data = pcall(function()
		return GetLevelData:InvokeServer(slotIndex)
	end)
	if ok then
		renderWeb(data)
	else
		warn("CharacterClient: falha ao buscar dados do slot " .. tostring(slotIndex) .. ": " .. tostring(data))
		renderWeb(nil)
	end
end

-- ===== RENDER DA LISTA DE SLOTS =====
local function highlightSelectedCard()
	for index, card in pairs(slotCards) do
		local isSelected = index == previewSlotIndex
		card.Stroke.Color = isSelected and COR_ACENTO or COR_BORDA
		card.Stroke.Thickness = isSelected and 2 or 1
	end
end

local function selectSlotForPreview(slotIndex)
	previewSlotIndex = slotIndex
	slotTitleLabel.Text = (slotCards[slotIndex] and slotCards[slotIndex].NameLabel.Text) or ("Slot " .. slotIndex)
	renameRow.Visible = true
	renameBox.Text = ""
	playButton.Visible = (slotIndex ~= activeSlotIndex)
	highlightSelectedCard()
	local info = lastOverview and lastOverview.Slots[slotIndex]
	highlightSelectedRole(info and info.Role)
	loadSlotIntoWeb(slotIndex)
end

local function renderSlotsOverview(overview)
	lastOverview = overview
	activeSlotIndex = overview.ActiveSlot
	for index, card in pairs(slotCards) do
		local info = overview.Slots[index]
		if not info or info.Locked then
			card.NameLabel.Text = ""
			card.InfoLabel.Text = ""
			card.Sorte.Visible = false
			card.SorteRotulo.Text = ""
			card.ActiveTag.Visible = false
			card.LockIcon.Visible = true
			card.Frame.BackgroundColor3 = COR_CARTAO
			card.Frame.AutoButtonColor = false
		else
			card.LockIcon.Visible = false
			card.Sorte.Visible = true
			card.Frame.BackgroundColor3 = COR_CARTAO
			card.NameLabel.Text = info.SlotName
			-- ⚠️ NOVO: elemento reinserido (Config.ELEMENTS) — mostrado aqui
			-- de novo, dessa vez com utilidade de gameplay de verdade (ver
			-- Config.PULSE_ELEMENT_SELF_MATCH_MULT no place Game).
			-- (v102: elemento em cor, sem emoji)
			local elementSuffix = ""
			if info.Element then
				local c = ELEMENT_COLORS[info.Element] or COR_TEXTO_MEDIO
				elementSuffix = string.format('  ·  <font color="#%s">%s</font>', c:ToHex(), info.Element)
			end
			card.InfoLabel.Text = string.format("%s  ·  Nv. %d%s", ROLE_LABELS[info.Role] or info.Role, info.Level, elementSuffix)
			setStars(card, info.Stars or 1)
			card.ActiveTag.Visible = info.IsActive
		end
	end

	-- Seleciona automaticamente o slot ativo na primeira abertura
	if not previewSlotIndex or (overview.Slots[previewSlotIndex] and overview.Slots[previewSlotIndex].Locked) then
		if overview.Slots[overview.ActiveSlot] and not overview.Slots[overview.ActiveSlot].Locked then
			selectSlotForPreview(overview.ActiveSlot)
		end
	else
		playButton.Visible = (previewSlotIndex ~= activeSlotIndex)
		highlightSelectedCard()
		local info = overview.Slots[previewSlotIndex]
		highlightSelectedRole(info and info.Role)
	end
end

local function refreshSlotsOverview()
	local ok, overview = pcall(function()
		return GetSlotsOverview:InvokeServer()
	end)
	if ok and overview then
		renderSlotsOverview(overview)
	else
		warn("CharacterClient: falha ao buscar GetSlotsOverview: " .. tostring(overview))
	end
end

-- ===== CLIQUES NOS SLOTS =====
for index, card in pairs(slotCards) do
	card.Frame.MouseButton1Click:Connect(function()
		if card.LockIcon.Visible then return end
		selectSlotForPreview(index)
	end)
end

-- ===== BOTÃO JOGAR COM ESTE =====
playButton.MouseButton1Click:Connect(function()
	if not previewSlotIndex then return end
	local ok, success, result = pcall(function()
		return SetActiveSlotRemote:InvokeServer(previewSlotIndex)
	end)
	if ok and success then
		refreshSlotsOverview()
	else
		warn("CharacterClient: falha ao trocar de personagem ativo: " .. tostring(result))
	end
end)

-- ===== RENOMEAR =====
renameButton.MouseButton1Click:Connect(function()
	if not previewSlotIndex then return end
	local newName = renameBox.Text
	if newName == "" then return end

	local ok, success, result = pcall(function()
		return UpdateSlotName:InvokeServer(previewSlotIndex, newName)
	end)
	if ok and success then
		renameBox.Text = ""
		refreshSlotsOverview()
		slotTitleLabel.Text = result.NewName
	else
		warn("CharacterClient: falha ao renomear: " .. tostring(result))
	end
end)

-- ===== CLIQUE NO CHECKBOX DE GOLEIRO =====
-- ⚠️ v10: era um loop de 4 botões (GK/DF/MF/FW) — agora só alterna entre
-- "GK" e "LINE" (posição de linha sem preferência manual, ver ROLES em
-- PlayerDataManager.legacy.luau). lastOverview guarda o Role atual do slot
-- (ver comentário na declaração dele, no topo do arquivo).
gkCheckboxButton.MouseButton1Click:Connect(function()
	if not previewSlotIndex then return end

	local currentInfo = lastOverview and lastOverview.Slots[previewSlotIndex]
	local currentlyGK = currentInfo and currentInfo.Role == "GK"
	local newRole = currentlyGK and "LINE" or "GK"

	local ok, success, result = pcall(function()
		return SetSlotRoleRemote:InvokeServer(previewSlotIndex, newRole)
	end)

	if ok and success then
		highlightSelectedRole(newRole)
		refreshSlotsOverview()
	else
		warn("CharacterClient: falha ao mudar goleiro para " .. newRole .. ": " .. tostring(result))
	end
end)

-- ===== CLIQUES NO "+" DE CADA ATRIBUTO =====
for _, attrName in ipairs(ATTRIBUTE_ORDER) do
	attributeNodes[attrName].PlusButton.MouseButton1Click:Connect(function()
		if not previewSlotIndex then return end

		local ok, success, result = pcall(function()
			return AddAttributePoint:InvokeServer(attrName, previewSlotIndex)
		end)

		if ok and success then
			renderWeb({
				Level = currentSlotData and currentSlotData.Level,
				CurrentXP = currentSlotData and currentSlotData.CurrentXP,
				XPNeeded = currentSlotData and currentSlotData.XPNeeded,
				AttributePoints = result.AttributePoints,
				Attributes = result.Attributes,
				IsMaxLevel = currentSlotData and currentSlotData.IsMaxLevel,
			})
		else
			warn("CharacterClient: falha ao investir ponto em " .. attrName .. ": " .. tostring(result))
		end
	end)
end

-- ===== ATUALIZAÇÕES EMPURRADAS PELO SERVIDOR (XP, level up, etc) =====
UpdateLevelDataEvent.OnClientEvent:Connect(function(data)
	if not data then return end
	-- Só re-renderiza a teia se for do slot que está sendo visualizado
	if data.SlotIndex == nil or data.SlotIndex == previewSlotIndex then
		renderWeb(data)
	end
	-- Nível pode ter mudado no card da sidebar também
	if data.SlotIndex and slotCards[data.SlotIndex] then
		refreshSlotsOverview()
	end
end)

-- ===== ABRIR / FECHAR =====
local isOpen = false

local function setOpen(open)
	isOpen = open
	mainFrame.Visible = open
	if open then
		refreshSlotsOverview()
	end
end

toggleButton.MouseButton1Click:Connect(function()
	setOpen(not isOpen)
end)

closeButton.MouseButton1Click:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.P then
		setOpen(not isOpen)
	end
end)

screenGui.Enabled = true

-- ⚠️ v68: exposto pro diálogo do kogamalotigo abrir a ficha (ação
-- "OpenCharacter" em DialogueClient). Mesmo padrão de _G.OpenShop/_G.OpenRoll,
-- que o sistema de diálogo já usa — nada novo pra aprender.
_G.OpenCharacter = function()
	setOpen(true)
end

print("✅ CharacterClient carregado.")
