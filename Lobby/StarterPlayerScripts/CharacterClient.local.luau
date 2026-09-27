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

-- ⚠️ v10 — PEDIDO: "remova a opção de selecionar role no lobby, apenas ao
-- goleiro, como a checkbox pedida". DF/MF/FW saíram: a posição de linha
-- agora é sugerida automaticamente no matchmaking a partir dos Pulsos
-- equipados (ver derivePreferredRole em MatchDataTransfer.legacy.luau) —
-- só GK continua sendo escolha manual, feita abaixo como um checkbox
-- único, não mais um seletor de 4 botões.
local ROLE_LABELS = { GK = "GOL", LINE = "LINHA" }

-- ⚠️ NOVO: ícones dos elementos (Config.ELEMENTS, LobbyConfig.luau) —
-- só emoji, sem asset nenhum pra criar.
local ELEMENT_ICONS = {
	Natureza = "🌿",
	Fogo = "🔥",
	Vento = "🌪️",
	Luz = "✨",
	Void = "🌑",
}

-- ===== ATRIBUTOS (só os normais de futebol — Aura/BallControl/
-- CrossingSkill foram removidos; Speed e Kick entraram no lugar) =====
-- ⚠️ NOVO: Energy entrou como 6º atributo (alimenta o sistema de Pulsos)
-- — a teia agora é um HEXÁGONO em vez de pentágono (ver ATTR_ANGLES
-- abaixo, que já usa #ATTRIBUTE_ORDER em vez de "5" fixo).
-- ⚠️ NOVO: Technique (TÉCNICA) entrou como 7º — a teia vira HEPTÁGONO
-- sozinha (ATTR_ANGLES já deriva de #ATTRIBUTE_ORDER). Fica ao lado do
-- Drible porque os dois são "habilidade com a bola".
local ATTRIBUTE_ORDER = { "Physical", "DribbleSkill", "Technique", "Speed", "Kick", "Energy", "Stamina" }
local ATTRIBUTE_LABELS = {
	Physical = "FÍSICO",
	DribbleSkill = "DRIBLE",
	Technique = "TÉCNICA",
	Speed = "VELOCIDADE",
	Kick = "CHUTE",
	Energy = "ENERGIA",
	Stamina = "FÔLEGO",
}
local ATTRIBUTE_COLOR = Color3.fromRGB(90, 200, 255)
local ATTRIBUTE_COLOR_BRIGHT = Color3.fromRGB(140, 225, 255)

-- ===== GEOMETRIA DA TEIA (⚠️ NOVO: heptágono, 7 atributos) =====
local WEB_SIZE = Vector2.new(400, 400)
local WEB_CENTER = Vector2.new(200, 190)
local WEB_RADIUS = 140
local WEB_MIN_FRACTION = 0.1 -- nunca deixa o polígono de valor colapsar num ponto
local WEB_VALUE_CAP = 100 -- fração visual satura em 100, mas o número mostrado não tem teto

-- ⚠️ NOVO: ângulo por vértice agora deriva de #ATTRIBUTE_ORDER (era "5"/
-- "72" fixos, específico de pentágono) — com Energy virou hexágono (6
-- vértices, 60° cada), mas continua funcionando pra qualquer quantidade
-- de atributos se mudar de novo no futuro.
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

-- ===== GUI RAIZ =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CharacterGui"
screenGui.ResetOnSpawn = false
screenGui.Enabled = false
screenGui.Parent = playerGui

-- Botão flutuante pra abrir/fechar
-- ⚠️ v68 — O BOTÃO FLUTUANTE "PERSONAGEM (P)" FOI REMOVIDO.
-- PEDIDO: "tira esse botão e coloca pro meu npc kogamalotigo dizer algo na
-- fala e abrir isso."
--
-- Um botão retangular escrito "PERSONAGEM (P)" colado no canto é exatamente
-- o tipo de coisa que denuncia UI feita por conveniência: ocupa tela o jogo
-- inteiro pra uma ação que se usa de vez em quando, e ainda ensina um atalho
-- de teclado que não existe no celular.
--
-- Agora quem abre a ficha é o próprio kogamalotigo, conversando (ver
-- DialogueData.Kogamalotigo e a ação OpenCharacter no DialogueClient). A
-- tecla P continua funcionando pra quem joga no PC e já se acostumou — ela
-- só deixou de ser anunciada na tela.
--
-- `toggleButton` sobrevive como objeto-ponte porque há conexões a ele mais
-- abaixo neste arquivo; assim elas continuam válidas sem eu precisar caçar
-- cada uma e arriscar deixar uma pendurada.
local toggleButton = { MouseButton1Click = { Connect = function() end } }

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(920, 560)
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
mainFrame.Visible = false
mainFrame.Parent = screenGui
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 18)
local mainStroke = Instance.new("UIStroke", mainFrame)
mainStroke.Color = Color3.fromRGB(60, 60, 80)
mainStroke.Thickness = 1.5

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -40, 0, 40)
title.Position = UDim2.new(0, 20, 0, 14)
title.BackgroundTransparency = 1
title.Text = "PERSONAGEM"
title.TextColor3 = Color3.new(1, 1, 1)
title.Font = Enum.Font.GothamBlack
title.TextSize = 24
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = mainFrame

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.fromOffset(32, 32)
closeButton.Position = UDim2.new(1, -48, 0, 16)
closeButton.BackgroundColor3 = Color3.fromRGB(60, 40, 45)
closeButton.Text = "X"
closeButton.TextColor3 = Color3.new(1, 1, 1)
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.Parent = mainFrame
Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 8)

-- ===== SIDEBAR (SLOTS) =====
local sidebar = Instance.new("Frame")
sidebar.Name = "Sidebar"
sidebar.Size = UDim2.fromOffset(280, 480)
sidebar.Position = UDim2.fromOffset(20, 64)
sidebar.BackgroundTransparency = 1
sidebar.Parent = mainFrame

local slotListLayout = Instance.new("UIListLayout")
slotListLayout.Padding = UDim.new(0, 10)
slotListLayout.Parent = sidebar

local slotCards = {} -- [index] = { Frame, NameLabel, InfoLabel, ActiveTag, LockIcon }

local function createSlotCard(index)
	local card = Instance.new("TextButton")
	card.Name = "Slot" .. index
	card.Size = UDim2.new(1, 0, 0, 96)
	card.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
	card.AutoButtonColor = false
	card.Text = ""
	card.LayoutOrder = index
	card.Parent = sidebar
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

	local stroke = Instance.new("UIStroke", card)
	stroke.Color = Color3.fromRGB(55, 55, 70)
	stroke.Thickness = 1.5

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -90, 0, 24)
	nameLabel.Position = UDim2.new(0, 14, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "—"
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local infoLabel = Instance.new("TextLabel")
	infoLabel.Size = UDim2.new(1, -28, 0, 20)
	infoLabel.Position = UDim2.new(0, 14, 0, 38)
	infoLabel.BackgroundTransparency = 1
	infoLabel.Text = ""
	infoLabel.TextColor3 = Color3.fromRGB(170, 170, 185)
	infoLabel.Font = Enum.Font.Gotham
	infoLabel.TextSize = 13
	infoLabel.TextXAlignment = Enum.TextXAlignment.Left
	infoLabel.Parent = card

	-- ⭐ Estrelas de Sorte do slot (1-5, refletem o teto de atributos que
	-- dá pra maxar nesse personagem — ver Luck no PlayerDataManager.lua)
	local starsLabel = Instance.new("TextLabel")
	starsLabel.Size = UDim2.new(1, -28, 0, 16)
	starsLabel.Position = UDim2.new(0, 14, 0, 58)
	starsLabel.BackgroundTransparency = 1
	starsLabel.Text = ""
	starsLabel.TextColor3 = Color3.fromRGB(255, 205, 60)
	starsLabel.Font = Enum.Font.GothamBold
	starsLabel.TextSize = 12
	starsLabel.TextXAlignment = Enum.TextXAlignment.Left
	starsLabel.Parent = card

	local activeTag = Instance.new("TextLabel")
	activeTag.Size = UDim2.fromOffset(60, 20)
	activeTag.Position = UDim2.new(1, -74, 0, 10)
	activeTag.BackgroundColor3 = Color3.fromRGB(85, 200, 120)
	activeTag.Text = "ATIVO"
	activeTag.TextColor3 = Color3.new(1, 1, 1)
	activeTag.Font = Enum.Font.GothamBold
	activeTag.TextSize = 11
	activeTag.Visible = false
	activeTag.Parent = card
	Instance.new("UICorner", activeTag).CornerRadius = UDim.new(0, 6)

	local lockIcon = Instance.new("TextLabel")
	lockIcon.Size = UDim2.new(1, 0, 1, 0)
	lockIcon.BackgroundTransparency = 1
	lockIcon.Text = "🔒 BLOQUEADO"
	lockIcon.TextColor3 = Color3.fromRGB(130, 130, 140)
	lockIcon.Font = Enum.Font.GothamBold
	lockIcon.TextSize = 14
	lockIcon.Visible = false
	lockIcon.Parent = card

	slotCards[index] = {
		Frame = card,
		Stroke = stroke,
		NameLabel = nameLabel,
		InfoLabel = infoLabel,
		StarsLabel = starsLabel,
		ActiveTag = activeTag,
		LockIcon = lockIcon,
	}
	return card
end

for i = 1, 5 do
	createSlotCard(i)
end

local playButton = Instance.new("TextButton")
playButton.Name = "PlayButton"
playButton.Size = UDim2.new(1, 0, 0, 46)
playButton.LayoutOrder = 99
playButton.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
playButton.Text = "JOGAR COM ESTE"
playButton.TextColor3 = Color3.new(1, 1, 1)
playButton.Font = Enum.Font.GothamBlack
playButton.TextSize = 15
playButton.Visible = false
playButton.Parent = sidebar
Instance.new("UICorner", playButton).CornerRadius = UDim.new(0, 10)

local renameRow = Instance.new("Frame")
renameRow.Name = "RenameRow"
renameRow.Size = UDim2.new(1, 0, 0, 40)
renameRow.LayoutOrder = 100
renameRow.BackgroundTransparency = 1
renameRow.Visible = false
renameRow.Parent = sidebar

local renameBox = Instance.new("TextBox")
renameBox.Size = UDim2.new(1, -84, 1, 0)
renameBox.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
renameBox.TextColor3 = Color3.new(1, 1, 1)
renameBox.PlaceholderText = "Renomear personagem..."
renameBox.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
renameBox.Font = Enum.Font.Gotham
renameBox.TextSize = 14
renameBox.ClearTextOnFocus = false
renameBox.Parent = renameRow
Instance.new("UICorner", renameBox).CornerRadius = UDim.new(0, 8)

local renameButton = Instance.new("TextButton")
renameButton.Size = UDim2.new(0, 76, 1, 0)
renameButton.Position = UDim2.new(1, -76, 0, 0)
renameButton.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
renameButton.Text = "SALVAR"
renameButton.TextColor3 = Color3.new(1, 1, 1)
renameButton.Font = Enum.Font.GothamBold
renameButton.TextSize = 12
renameButton.Parent = renameRow
Instance.new("UICorner", renameButton).CornerRadius = UDim.new(0, 8)

-- ===== PAINEL DA TEIA DE HABILIDADE =====
local webPanel = Instance.new("Frame")
webPanel.Name = "WebPanel"
webPanel.Size = UDim2.fromOffset(580, 480)
webPanel.Position = UDim2.fromOffset(320, 64)
webPanel.BackgroundColor3 = Color3.fromRGB(26, 26, 36)
webPanel.Parent = mainFrame
Instance.new("UICorner", webPanel).CornerRadius = UDim.new(0, 14)

local slotTitleLabel = Instance.new("TextLabel")
slotTitleLabel.Size = UDim2.new(1, -40, 0, 30)
slotTitleLabel.Position = UDim2.new(0, 20, 0, 14)
slotTitleLabel.BackgroundTransparency = 1
slotTitleLabel.Text = "Selecione um personagem"
slotTitleLabel.TextColor3 = Color3.new(1, 1, 1)
slotTitleLabel.Font = Enum.Font.GothamBold
slotTitleLabel.TextSize = 19
slotTitleLabel.TextXAlignment = Enum.TextXAlignment.Left
slotTitleLabel.Parent = webPanel

local levelBadge = Instance.new("TextLabel")
levelBadge.Size = UDim2.fromOffset(90, 26)
levelBadge.Position = UDim2.new(1, -110, 0, 16)
levelBadge.BackgroundColor3 = Color3.fromRGB(50, 50, 68)
levelBadge.Text = "Nv. —"
levelBadge.TextColor3 = Color3.fromRGB(255, 215, 0)
levelBadge.Font = Enum.Font.GothamBold
levelBadge.TextSize = 14
levelBadge.Parent = webPanel
Instance.new("UICorner", levelBadge).CornerRadius = UDim.new(0, 8)

-- ⚠️ NOVO: badge do elemento do slot (Config.ELEMENTS) — ao lado do
-- badge de nível.
local elementBadge = Instance.new("TextLabel")
elementBadge.Name = "ElementBadge"
elementBadge.Size = UDim2.fromOffset(90, 26)
elementBadge.Position = UDim2.new(1, -110, 0, 46)
elementBadge.BackgroundColor3 = Color3.fromRGB(50, 50, 68)
elementBadge.Text = ""
elementBadge.TextColor3 = Color3.fromRGB(220, 220, 230)
elementBadge.Font = Enum.Font.GothamBold
elementBadge.TextSize = 13
elementBadge.Parent = webPanel
Instance.new("UICorner", elementBadge).CornerRadius = UDim.new(0, 8)

-- ===== CHECKBOX DE GOLEIRO (⚠️ v10 — substitui o seletor de 4 botões
-- GK/DF/MF/FW; ver comentário perto de ROLE_LABELS no topo do arquivo) =====
local roleRow = Instance.new("Frame")
roleRow.Name = "GKCheckboxRow"
roleRow.Size = UDim2.new(1, -40, 0, 30)
roleRow.Position = UDim2.new(0, 20, 0, 48)
roleRow.BackgroundTransparency = 1
roleRow.Parent = webPanel

local roleRowLayout = Instance.new("UIListLayout")
roleRowLayout.FillDirection = Enum.FillDirection.Horizontal
roleRowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
roleRowLayout.Padding = UDim.new(0, 8)
roleRowLayout.Parent = roleRow

local gkCheckboxButton = Instance.new("TextButton")
gkCheckboxButton.Name = "GKCheckbox"
gkCheckboxButton.Size = UDim2.fromOffset(26, 26)
gkCheckboxButton.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
gkCheckboxButton.Text = ""
gkCheckboxButton.Font = Enum.Font.GothamBold
gkCheckboxButton.TextSize = 16
gkCheckboxButton.TextColor3 = Color3.new(1, 1, 1)
gkCheckboxButton.Parent = roleRow
Instance.new("UICorner", gkCheckboxButton).CornerRadius = UDim.new(0, 6)
local gkCheckboxStroke = Instance.new("UIStroke", gkCheckboxButton)
gkCheckboxStroke.Color = Color3.fromRGB(70, 70, 90)
gkCheckboxStroke.Thickness = 1.5

local gkCheckboxLabel = Instance.new("TextLabel")
gkCheckboxLabel.Name = "GKCheckboxLabel"
gkCheckboxLabel.Size = UDim2.fromOffset(190, 26)
gkCheckboxLabel.BackgroundTransparency = 1
gkCheckboxLabel.Text = "Quer ser Goleiro?"
gkCheckboxLabel.TextColor3 = Color3.new(1, 1, 1)
gkCheckboxLabel.Font = Enum.Font.GothamBold
gkCheckboxLabel.TextSize = 13
gkCheckboxLabel.TextXAlignment = Enum.TextXAlignment.Left
gkCheckboxLabel.Parent = roleRow

-- Container da teia (pentágono)
local webContainer = Instance.new("Frame")
webContainer.Name = "Web"
webContainer.Size = UDim2.fromOffset(WEB_SIZE.X, WEB_SIZE.Y)
webContainer.Position = UDim2.new(0.5, -WEB_SIZE.X / 2, 0, 74)
webContainer.BackgroundTransparency = 1
webContainer.Parent = webPanel

-- Anéis de fundo da teia (25%, 50%, 75%, 100%) — o visual de "rede"
local ringsFolder = Instance.new("Folder", webContainer)
ringsFolder.Name = "Rings"
for _, fraction in ipairs({ 0.25, 0.5, 0.75, 1 }) do
	for i = 1, ATTR_COUNT do
		local nextI = (i % ATTR_COUNT) + 1
		drawLine(
			ringsFolder,
			pointOnWeb(i, fraction),
			pointOnWeb(nextI, fraction),
			1,
			Color3.fromRGB(70, 70, 90),
			fraction == 1 and 0.2 or 0.55,
			2
		)
	end
end

-- Raios do centro até cada vértice
local spokesFolder = Instance.new("Folder", webContainer)
spokesFolder.Name = "Spokes"
for i = 1, ATTR_COUNT do
	drawLine(spokesFolder, WEB_CENTER, pointOnWeb(i, 1), 1, Color3.fromRGB(70, 70, 90), 0.5, 2)
end

-- Polígono de VALOR (recriado a cada atualização)
local valuePolygonFolder = Instance.new("Folder", webContainer)
valuePolygonFolder.Name = "ValuePolygon"

local function clearFolder(folder)
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
	end
end

-- Nós dos atributos (botão + valor + botão "+")
local attributeNodes = {} -- [attrName] = { NodeButton, ValueLabel, PlusButton }

for i, attrName in ipairs(ATTRIBUTE_ORDER) do
	local pos = pointOnWeb(i, 1)

	local nodeButton = Instance.new("Frame")
	nodeButton.Name = attrName
	nodeButton.Size = UDim2.fromOffset(84, 54)
	nodeButton.AnchorPoint = Vector2.new(0.5, 0.5)
	nodeButton.Position = UDim2.fromOffset(pos.X, pos.Y)
	nodeButton.BackgroundColor3 = Color3.fromRGB(32, 32, 46)
	nodeButton.ZIndex = 3
	nodeButton.Parent = webContainer
	Instance.new("UICorner", nodeButton).CornerRadius = UDim.new(0, 12)
	local nodeStroke = Instance.new("UIStroke", nodeButton)
	nodeStroke.Color = ATTRIBUTE_COLOR
	nodeStroke.Thickness = 1.5
	nodeStroke.Transparency = 0.3

	local labelText = Instance.new("TextLabel")
	labelText.Size = UDim2.new(1, 0, 0, 16)
	labelText.Position = UDim2.new(0, 0, 0, 4)
	labelText.BackgroundTransparency = 1
	labelText.Text = ATTRIBUTE_LABELS[attrName]
	labelText.TextColor3 = Color3.fromRGB(180, 210, 230)
	labelText.Font = Enum.Font.GothamBold
	labelText.TextSize = 11
	labelText.ZIndex = 3
	labelText.Parent = nodeButton

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(1, 0, 0, 24)
	valueLabel.Position = UDim2.new(0, 0, 0, 20)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = "0"
	valueLabel.TextColor3 = Color3.new(1, 1, 1)
	valueLabel.Font = Enum.Font.GothamBlack
	valueLabel.TextSize = 20
	valueLabel.ZIndex = 3
	valueLabel.Parent = nodeButton

	local plusButton = Instance.new("TextButton")
	plusButton.Size = UDim2.fromOffset(26, 26)
	plusButton.AnchorPoint = Vector2.new(0.5, 0.5)
	plusButton.Position = UDim2.new(1, 0, 0, 0)
	plusButton.BackgroundColor3 = Color3.fromRGB(85, 200, 120)
	plusButton.Text = "+"
	plusButton.TextColor3 = Color3.new(1, 1, 1)
	plusButton.Font = Enum.Font.GothamBlack
	plusButton.TextSize = 18
	plusButton.Visible = false
	plusButton.ZIndex = 4
	plusButton.Parent = nodeButton
	Instance.new("UICorner", plusButton).CornerRadius = UDim.new(1, 0)

	attributeNodes[attrName] = { NodeButton = nodeButton, ValueLabel = valueLabel, PlusButton = plusButton, Stroke = nodeStroke }
end

-- Pontos disponíveis + barra de XP (embaixo da teia)
local pointsLabel = Instance.new("TextLabel")
pointsLabel.Size = UDim2.new(1, -40, 0, 22)
pointsLabel.Position = UDim2.new(0, 20, 1, -66)
pointsLabel.BackgroundTransparency = 1
pointsLabel.Text = ""
pointsLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
pointsLabel.Font = Enum.Font.GothamBold
pointsLabel.TextSize = 14
pointsLabel.TextXAlignment = Enum.TextXAlignment.Left
pointsLabel.Parent = webPanel

local xpBarBack = Instance.new("Frame")
xpBarBack.Size = UDim2.new(1, -40, 0, 14)
xpBarBack.Position = UDim2.new(0, 20, 1, -36)
xpBarBack.BackgroundColor3 = Color3.fromRGB(40, 40, 54)
xpBarBack.Parent = webPanel
Instance.new("UICorner", xpBarBack).CornerRadius = UDim.new(1, 0)

local xpBarFill = Instance.new("Frame")
xpBarFill.Size = UDim2.new(0, 0, 1, 0)
xpBarFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
xpBarFill.Parent = xpBarBack
Instance.new("UICorner", xpBarFill).CornerRadius = UDim.new(1, 0)

local xpLabel = Instance.new("TextLabel")
xpLabel.Size = UDim2.new(1, 0, 1, 0)
xpLabel.BackgroundTransparency = 1
xpLabel.Text = ""
xpLabel.TextColor3 = Color3.new(1, 1, 1)
xpLabel.Font = Enum.Font.GothamBold
xpLabel.TextSize = 11
xpLabel.Parent = xpBarBack

-- ===== ESTADO =====
local previewSlotIndex = nil
local activeSlotIndex = nil
local currentSlotData = nil -- resposta crua do GetLevelData pro slot em preview
local lastOverview = nil -- última resposta crua do GetSlotsOverview (pra saber o Role atual)

-- ⚠️ v10: era um seletor de 4 botões (GK/DF/MF/FW) — agora só marca/
-- desmarca o checkbox único de goleiro.
local function highlightSelectedRole(currentRole)
	local isGK = currentRole == "GK"
	gkCheckboxButton.BackgroundColor3 = isGK and Color3.fromRGB(85, 170, 255) or Color3.fromRGB(40, 40, 54)
	gkCheckboxStroke.Color = isGK and ATTRIBUTE_COLOR_BRIGHT or Color3.fromRGB(70, 70, 90)
	gkCheckboxButton.Text = isGK and "✓" or ""
end

-- ===== RENDER DA TEIA (valores atuais) =====
local function renderWeb(slotData)
	currentSlotData = slotData
	clearFolder(valuePolygonFolder)

	if not slotData then
		levelBadge.Text = "Nv. —"
		elementBadge.Text = ""
		pointsLabel.Text = ""
		xpLabel.Text = ""
		xpBarFill.Size = UDim2.new(0, 0, 1, 0)
		for _, attrName in ipairs(ATTRIBUTE_ORDER) do
			attributeNodes[attrName].ValueLabel.Text = "—"
			attributeNodes[attrName].PlusButton.Visible = false
		end
		return
	end

	levelBadge.Text = "Nv. " .. tostring(slotData.Level or 1)
	elementBadge.Text = slotData.Element and (ELEMENT_ICONS[slotData.Element] .. " " .. slotData.Element) or ""

	if slotData.IsMaxLevel then
		xpBarFill.Size = UDim2.new(1, 0, 1, 0)
		xpBarFill.BackgroundColor3 = Color3.fromRGB(255, 205, 60)
		xpLabel.Text = "NÍVEL MÁXIMO"
	else
		local xpNeeded = math.max(slotData.XPNeeded or 1, 1)
		local xpFraction = math.clamp((slotData.CurrentXP or 0) / xpNeeded, 0, 1)
		xpBarFill.Size = UDim2.new(xpFraction, 0, 1, 0)
		xpBarFill.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		xpLabel.Text = string.format("%d / %d XP", slotData.CurrentXP or 0, xpNeeded)
	end

	local points = slotData.AttributePoints or 0
	local canEdit = previewSlotIndex ~= nil
	if points > 0 then
		pointsLabel.Text = string.format("⭐ %d ponto(s) de atributo disponível(is)", points)
	else
		pointsLabel.Text = "Sem pontos disponíveis no momento"
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
		drawLine(valuePolygonFolder, valuePoints[i], valuePoints[nextI], 3, ATTRIBUTE_COLOR_BRIGHT, 0.05, 3)
	end
	-- Pontinhos nos vértices do polígono de valor
	for i = 1, ATTR_COUNT do
		local dot = Instance.new("Frame")
		dot.AnchorPoint = Vector2.new(0.5, 0.5)
		dot.Position = UDim2.fromOffset(valuePoints[i].X, valuePoints[i].Y)
		dot.Size = UDim2.fromOffset(8, 8)
		dot.BackgroundColor3 = ATTRIBUTE_COLOR_BRIGHT
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
		card.Stroke.Color = isSelected and ATTRIBUTE_COLOR_BRIGHT or Color3.fromRGB(55, 55, 70)
		card.Stroke.Thickness = isSelected and 2.5 or 1.5
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
			card.StarsLabel.Text = ""
			card.ActiveTag.Visible = false
			card.LockIcon.Visible = true
			card.Frame.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
			card.Frame.AutoButtonColor = false
		else
			card.LockIcon.Visible = false
			card.Frame.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
			card.NameLabel.Text = info.SlotName
			-- ⚠️ NOVO: elemento reinserido (Config.ELEMENTS) — mostrado aqui
			-- de novo, dessa vez com utilidade de gameplay de verdade (ver
			-- Config.PULSE_ELEMENT_SELF_MATCH_MULT no place Game).
			local elementSuffix = info.Element and (" • " .. ELEMENT_ICONS[info.Element] .. info.Element) or ""
			card.InfoLabel.Text = string.format("%s • Nv. %d%s", ROLE_LABELS[info.Role] or info.Role, info.Level, elementSuffix)
			local stars = info.Stars or 1
			card.StarsLabel.Text = string.rep("★", stars) .. string.rep("☆", 5 - stars)
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
