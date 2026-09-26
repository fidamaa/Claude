--[[
	DialogueClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Sistema de diálogo PRÓPRIO (substitui qualquer modelo de diálogo
	pego pronto na internet) — serve pra TODOS os NPCs do jogo, cada um
	só precisa da tag "Dialogue" + opcionalmente o atributo DialogueId
	(ver NPCDialogueSetup.lua no servidor e DialogueData.lua com as
	falas). Tudo construído por código, mesmo padrão do
	CharacterClient/ShopClient — não depende de nada pronto no Explorer.

	O QUE ACONTECE AO CONVERSAR COM UM NPC:
	1. Tela funde rápido pra preto (evita corte seco de câmera).
	2. Câmera vira Scriptable e centra no NPC (leve enquadramento tipo
	   "sobre o ombro" do jogador).
	3. O personagem do JOGADOR fica translúcido — SÓ NA SUA TELA
	   (LocalTransparencyModifier, client-only de verdade: quem está do
	   lado te vê 100% normal) — pra não tampar o enquadramento na
	   câmera.
	4. Jogador é travado (WalkSpeed/JumpPower = 0) enquanto conversa.
	5. Caixa de diálogo aparece com o nome do NPC e o texto "digitando"
	   letra por letra; clique avança ou pula a animação de texto.
	6. Ao fechar: desfaz tudo (câmera, transparência, movimento) com o
	   mesmo fade.

	ESPAÇO PRA ANIMAÇÃO (ainda não usado): cada nó de DialogueData pode
	ter NpcAnimationId/PlayerAnimationId — quando vocês tiverem as
	animações prontas, é só preencher esses campos lá que o
	playNodeAnimations() abaixo já sabe tocar (por enquanto não faz nada
	se estiverem vazios, de propósito).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = workspace.CurrentCamera

local DialogueData = require(ReplicatedStorage:WaitForChild("DialogueData"))

local DIALOGUE_TAG = "Dialogue"
local PROMPT_NAME = "TalkPrompt"

local TYPE_CHAR_INTERVAL = 0.02 -- segundos por letra na animação de "digitando"
local FADE_TIME = 0.22
local CHARACTER_DIALOGUE_TRANSPARENCY = 0.75
local CAMERA_TWEEN_TIME = 0.45

-- ========================================
-- Ações que um nó de diálogo pode disparar (Action = "Nome" no
-- DialogueData.lua). Hoje só abre a Loja (ShopClient.lua expõe
-- _G.OpenShop — mesmo _G, client e client sempre compartilham o mesmo
-- ambiente global dentro de um jogador).
-- ========================================
local ACTION_HANDLERS = {
	OpenShop = function()
		if _G.OpenShop then
			_G.OpenShop()
		else
			warn("DialogueClient: ação OpenShop chamada mas _G.OpenShop não existe (ShopClient carregou?)")
		end
	end,
	OpenRoll = function()
		if _G.OpenRoll then
			_G.OpenRoll()
		else
			warn("DialogueClient: ação OpenRoll chamada mas _G.OpenRoll não existe (RollClient carregou?)")
		end
	end,
	OpenQuests = function()
		if _G.OpenQuests then
			_G.OpenQuests()
		else
			warn("DialogueClient: ação OpenQuests chamada mas _G.OpenQuests não existe (QuestClient carregou?)")
		end
	end,
	-- ⚠️ v68: abre a ficha do personagem pela fala do kogamalotigo, no lugar
	-- do botão flutuante "PERSONAGEM (P)" que foi removido.
	OpenCharacter = function()
		if _G.OpenCharacter then
			_G.OpenCharacter()
		else
			warn("DialogueClient: ação OpenCharacter chamada mas _G.OpenCharacter não existe (CharacterClient carregou?)")
		end
	end,
}

-- ========================================
-- FADE (tela preta rápida pra mascarar cortes de câmera)
-- ========================================
local fadeGui = Instance.new("ScreenGui")
fadeGui.Name = "DialogueFade"
fadeGui.IgnoreGuiInset = true
fadeGui.DisplayOrder = 100
fadeGui.ResetOnSpawn = false
fadeGui.Parent = playerGui

local fadeFrame = Instance.new("Frame")
fadeFrame.Size = UDim2.fromScale(1, 1)
fadeFrame.BackgroundColor3 = Color3.new(0, 0, 0)
fadeFrame.BackgroundTransparency = 1
fadeFrame.ZIndex = 100
fadeFrame.Parent = fadeGui

local function fadeTo(targetTransparency, duration)
	-- Já estava no valor alvo (ex.: primeira vez que abre o diálogo, o
	-- fadeFrame já nasce com BackgroundTransparency = 1): não precisa
	-- animar nada. Isso também evita depender de tween.Completed:Wait()
	-- travar pra sempre num tween "sem trabalho a fazer" (comportamento
	-- inconsistente entre versões do Roblox pra tweens no-op).
	if math.abs(fadeFrame.BackgroundTransparency - targetTransparency) < 0.001 then
		return
	end

	local tween = TweenService:Create(fadeFrame, TweenInfo.new(duration, Enum.EasingStyle.Sine), {
		BackgroundTransparency = targetTransparency,
	})
	tween:Play()

	-- Não trava pra sempre se Completed nunca disparar por algum motivo:
	-- usa o que vier primeiro entre o evento e um timeout um pouco maior
	-- que a duração do tween.
	local completedSignal = tween.Completed
	local fired = false
	local connection
	connection = completedSignal:Connect(function()
		fired = true
	end)
	local deadline = os.clock() + duration + 0.3
	repeat
		task.wait()
	until fired or os.clock() >= deadline
	connection:Disconnect()

	-- Garante o valor final exato mesmo se o timeout tiver sido o motivo
	-- de sair do loop (tween ainda rodando, mas já perto do fim).
	fadeFrame.BackgroundTransparency = targetTransparency
end

-- ========================================
-- GUI DA CAIXA DE DIÁLOGO
-- ========================================
local dialogueGui = Instance.new("ScreenGui")
dialogueGui.Name = "DialogueGui"
dialogueGui.Enabled = false
dialogueGui.ResetOnSpawn = false
dialogueGui.Parent = playerGui

local box = Instance.new("TextButton") -- TextButton só pra capturar clique em qualquer lugar da caixa
box.Name = "Box"
box.AutoButtonColor = false
box.Text = ""
box.Size = UDim2.new(1, -160, 0, 170)
box.Position = UDim2.new(0.5, 0, 1, -40)
box.AnchorPoint = Vector2.new(0.5, 1)
box.BackgroundColor3 = Color3.fromRGB(18, 18, 26)
box.BackgroundTransparency = 0.08
box.Parent = dialogueGui
Instance.new("UICorner", box).CornerRadius = UDim.new(0, 16)
local boxStroke = Instance.new("UIStroke", box)
boxStroke.Color = Color3.fromRGB(90, 200, 255)
boxStroke.Thickness = 1.5

local speakerLabel = Instance.new("TextLabel")
speakerLabel.Size = UDim2.new(1, -40, 0, 28)
speakerLabel.Position = UDim2.new(0, 22, 0, 14)
speakerLabel.BackgroundTransparency = 1
speakerLabel.Text = ""
speakerLabel.TextColor3 = Color3.fromRGB(90, 200, 255)
speakerLabel.Font = Enum.Font.GothamBlack
speakerLabel.TextSize = 18
speakerLabel.TextXAlignment = Enum.TextXAlignment.Left
speakerLabel.Parent = box

local textLabel = Instance.new("TextLabel")
textLabel.Size = UDim2.new(1, -44, 0, 78)
textLabel.Position = UDim2.new(0, 22, 0, 46)
textLabel.BackgroundTransparency = 1
textLabel.Text = ""
textLabel.TextColor3 = Color3.new(1, 1, 1)
textLabel.Font = Enum.Font.Gotham
textLabel.TextSize = 16
textLabel.TextWrapped = true
textLabel.TextXAlignment = Enum.TextXAlignment.Left
textLabel.TextYAlignment = Enum.TextYAlignment.Top
textLabel.Parent = box

local advanceHint = Instance.new("TextLabel")
advanceHint.Size = UDim2.new(1, -44, 0, 18)
advanceHint.Position = UDim2.new(0, 22, 1, -24)
advanceHint.BackgroundTransparency = 1
advanceHint.Text = "▼ clique pra continuar"
advanceHint.TextColor3 = Color3.fromRGB(150, 150, 165)
advanceHint.Font = Enum.Font.GothamBold
advanceHint.TextSize = 12
advanceHint.TextXAlignment = Enum.TextXAlignment.Right
advanceHint.Visible = false
advanceHint.Parent = box

-- Botões de escolha (empilhados acima da caixa, só aparecem quando o
-- nó atual tem Choices)
local choicesFrame = Instance.new("Frame")
choicesFrame.Name = "Choices"
choicesFrame.Size = UDim2.new(1, -160, 0, 0)
choicesFrame.AutomaticSize = Enum.AutomaticSize.Y
choicesFrame.Position = UDim2.new(0.5, 0, 1, -220)
choicesFrame.AnchorPoint = Vector2.new(0.5, 1)
choicesFrame.BackgroundTransparency = 1
choicesFrame.Parent = dialogueGui

local choicesLayout = Instance.new("UIListLayout")
choicesLayout.Padding = UDim.new(0, 8)
choicesLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
choicesLayout.Parent = choicesFrame

-- ========================================
-- ESTADO DO DIÁLOGO
-- ========================================
local isOpen = false
local currentTree = nil
local currentNpcModel = nil
local typeGeneration = 0 -- incrementado a cada render de nó, pra cancelar a digitação anterior
local isTyping = false

local savedCameraType = nil
local savedWalkSpeed = nil
local savedJumpPower = nil
local savedJumpHeight = nil
local transparencyConnection = nil
local cameraFollowConnection = nil

-- ========================================
-- TRANSPARÊNCIA LOCAL DO JOGADOR (client-only de verdade)
-- ========================================
local function setLocalCharacterTransparency(character, amount)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = amount
		end
	end
end

local function applyPlayerTransparency()
	local character = player.Character
	if not character then return end

	setLocalCharacterTransparency(character, CHARACTER_DIALOGUE_TRANSPARENCY)

	-- Cobre partes que entram DEPOIS (acessórios carregando, por
	-- exemplo) enquanto o diálogo estiver aberto.
	transparencyConnection = character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			descendant.LocalTransparencyModifier = CHARACTER_DIALOGUE_TRANSPARENCY
		end
	end)
end

local function clearPlayerTransparency()
	if transparencyConnection then
		transparencyConnection:Disconnect()
		transparencyConnection = nil
	end

	local character = player.Character
	if character then
		setLocalCharacterTransparency(character, 0)
	end
end

-- ========================================
-- TRAVAR/DESTRAVAR MOVIMENTO
-- ========================================
local function lockPlayerMovement()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpPower = humanoid.JumpPower
	savedJumpHeight = humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function unlockPlayerMovement()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if savedWalkSpeed then humanoid.WalkSpeed = savedWalkSpeed end
	if savedJumpPower then humanoid.JumpPower = savedJumpPower end
	if savedJumpHeight then humanoid.JumpHeight = savedJumpHeight end
end

-- ========================================
-- CÂMERA: centra no NPC com quem está conversando, meio "sobre o
-- ombro" do jogador (por isso a transparência do jogador importa).
-- ========================================
local function getHeadPosition(model)
	local head = model:FindFirstChild("Head")
	if head then return head.Position end
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	return anchor and anchor.Position or Vector3.new()
end

local function computeDialogueCameraCFrame(npcModel)
	local character = player.Character
	if not character then return nil end

	local playerHeadPos = getHeadPosition(character)
	local npcHeadPos = getHeadPosition(npcModel)

	local flatDelta = Vector3.new(npcHeadPos.X - playerHeadPos.X, 0, npcHeadPos.Z - playerHeadPos.Z)
	local flatDir = flatDelta.Magnitude > 0.01 and flatDelta.Unit or Vector3.new(0, 0, -1)
	local sideDir = flatDir:Cross(Vector3.new(0, 1, 0))

	local desiredOffset = sideDir * 2.3 - flatDir * 0.6 + Vector3.new(0, 0.35, 0)

	-- OUTRA causa de tela preta: nada impedia a câmera de acabar DENTRO
	-- de uma parede/objeto (o offset é lateral+pra trás do jogador, sem
	-- checagem nenhuma) — câmera com geometria atravessando o near clip
	-- plane renderiza tudo preto. Faz um raycast do olho do jogador até
	-- a posição desejada da câmera; se bater em algo no caminho, para
	-- um pouco antes do impacto em vez de atravessar.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character, npcModel }

	local camPos = playerHeadPos + desiredOffset
	local rayResult = workspace:Raycast(playerHeadPos, desiredOffset, raycastParams)
	if rayResult then
		local safeDistance = math.max(rayResult.Distance - 0.3, 0.2)
		camPos = playerHeadPos + desiredOffset.Unit * safeDistance
	end

	return CFrame.new(camPos, npcHeadPos)
end

-- Espera até dar pra calcular uma CFrame de câmera válida (personagem e
-- NPC com Head/BasePart prontos). Isso existe pra evitar o bug de "tela
-- preta": se a câmera virasse Scriptable ANTES do personagem terminar
-- de carregar, computeDialogueCameraCFrame podia devolver nil e a
-- câmera ficava travada numa CFrame inválida (perto da origem do
-- mundo, dentro de geometria = tudo preto).
local function waitForValidCameraCFrame(npcModel, timeoutSeconds)
	local deadline = os.clock() + timeoutSeconds
	repeat
		local cf = computeDialogueCameraCFrame(npcModel)
		if cf then
			return cf
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return nil
end

local function startCameraFollow(npcModel, targetCFrame)
	if not targetCFrame then
		-- Não deu pra calcular uma câmera válida a tempo — não troca pra
		-- Scriptable, o diálogo continua com a câmera normal em vez de
		-- travar numa posição quebrada.
		warn("DialogueClient: não consegui calcular a câmera do diálogo (personagem/NPC sem Head?), mantendo a câmera normal.")
		return
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local tween = TweenService:Create(camera, TweenInfo.new(CAMERA_TWEEN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = targetCFrame,
	})
	tween:Play()

	-- Mantém o enquadramento mesmo se jogador/NPC balançarem um pouco
	-- (idle animation, etc.) enquanto o diálogo está aberto.
	cameraFollowConnection = RunService.RenderStepped:Connect(function()
		local cf = computeDialogueCameraCFrame(npcModel)
		if cf then
			camera.CFrame = cf
		end
	end)
end

local function stopCameraFollow()
	if cameraFollowConnection then
		cameraFollowConnection:Disconnect()
		cameraFollowConnection = nil
	end
	camera.CameraType = savedCameraType or Enum.CameraType.Custom
end

-- ========================================
-- ANIMAÇÃO (espaço reservado — ver cabeçalho do arquivo)
-- ========================================
local function playNodeAnimations(node, npcModel)
	if node.NpcAnimationId then
		local humanoid = npcModel:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local anim = Instance.new("Animation")
			anim.AnimationId = node.NpcAnimationId
			animator:LoadAnimation(anim):Play()
		end
	end

	if node.PlayerAnimationId then
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local anim = Instance.new("Animation")
			anim.AnimationId = node.PlayerAnimationId
			animator:LoadAnimation(anim):Play()
		end
	end
end

-- ========================================
-- TEXTO "DIGITANDO"
-- ========================================
local function typeText(fullText)
	typeGeneration += 1
	local myGeneration = typeGeneration

	isTyping = true
	textLabel.Text = ""

	for i = 1, #fullText do
		if myGeneration ~= typeGeneration then
			return -- outro nó foi renderizado (ou o jogador pulou) enquanto isso rodava
		end
		textLabel.Text = string.sub(fullText, 1, i)
		task.wait(TYPE_CHAR_INTERVAL)
	end

	isTyping = false
end

local function skipTyping(fullText)
	typeGeneration += 1 -- cancela o loop de typeText em andamento
	textLabel.Text = fullText
	isTyping = false
end

-- ========================================
-- NAVEGAÇÃO NA ÁRVORE DE DIÁLOGO
-- ========================================
local closeDialogue -- forward reference
local currentNodeId = nil -- id do nó exibido agora, usado pelo clique da caixa (avançar/pular digitação)

local function clearChoiceButtons()
	for _, child in ipairs(choicesFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

-- ⚠️ CORRIGIDO ("a loja abre mas ainda tenho que clicar pra fechar o
-- último diálogo"): o Action (ex: OpenShop/OpenRoll) disparava aqui, no
-- exato instante em que o nó é RENDERIZADO — ou seja, com a caixa de
-- diálogo ainda 100% na tela (ainda digitando aquele texto, isOpen ainda
-- true). O jogador só via o diálogo fechar de verdade num clique
-- SEGUINTE. Agora o Action não dispara mais aqui — fica guardado em
-- pendingAction e só é executado dentro de closeDialogue(), depois que o
-- diálogo já terminou 100% (tela normal de volta, câmera/movimento
-- destravados) — "faça tudo aparecer no final".
local pendingAction = nil

local function goToNode(nodeId)
	currentNodeId = nodeId

	if not nodeId then
		closeDialogue()
		return
	end

	local node = currentTree.Nodes[nodeId]
	if not node then
		warn("DialogueClient: nó de diálogo inexistente: " .. tostring(nodeId))
		closeDialogue()
		return
	end
	clearChoiceButtons()
	speakerLabel.Text = node.Speaker or currentNpcModel.Name
	advanceHint.Visible = false

	if node.Action and ACTION_HANDLERS[node.Action] then
		pendingAction = ACTION_HANDLERS[node.Action]
	end

	playNodeAnimations(node, currentNpcModel)

	typeText(node.Text or "")

	if node.Choices and #node.Choices > 0 then
		for _, choice in ipairs(node.Choices) do
			local choiceButton = Instance.new("TextButton")
			choiceButton.Size = UDim2.new(1, 0, 0, 40)
			choiceButton.BackgroundColor3 = Color3.fromRGB(32, 32, 44)
			choiceButton.Text = choice.Text
			choiceButton.TextColor3 = Color3.new(1, 1, 1)
			choiceButton.Font = Enum.Font.GothamBold
			choiceButton.TextSize = 14
			choiceButton.Parent = choicesFrame
			Instance.new("UICorner", choiceButton).CornerRadius = UDim.new(0, 10)
			local stroke = Instance.new("UIStroke", choiceButton)
			stroke.Color = Color3.fromRGB(90, 200, 255)
			stroke.Thickness = 1

			choiceButton.MouseButton1Click:Connect(function()
				goToNode(choice.Next)
			end)
		end
	else
		advanceHint.Visible = true
	end
end

-- Clicar na caixa: se ainda tá digitando, completa o texto na hora; se
-- já terminou E o nó é linear (sem Choices), avança pro próximo.
box.MouseButton1Click:Connect(function()
	if not isOpen or not currentNodeId then return end
	local node = currentTree.Nodes[currentNodeId]
	if not node then return end

	if isTyping then
		skipTyping(node.Text or "")
		if not (node.Choices and #node.Choices > 0) then
			advanceHint.Visible = true
		end
		return
	end

	if not (node.Choices and #node.Choices > 0) then
		goToNode(node.Next)
	end
end)

-- ========================================
-- ABRIR / FECHAR DIÁLOGO
-- ========================================
local function startDialogue(npcModel, dialogueId)
	if isOpen then return end

	local tree = DialogueData[dialogueId]
	if not tree then
		warn("DialogueClient: nenhuma árvore de diálogo encontrada pra '" .. tostring(dialogueId) .. "' (confira o nome/DialogueId contra as chaves em DialogueData.lua)")
		return
	end

	isOpen = true
	currentTree = tree
	currentNpcModel = npcModel
	savedCameraType = camera.CameraType

	-- Calcula a câmera ANTES de fundir pra preto — se isso demorar
	-- (personagem ainda carregando), o jogador só vê a tela normal um
	-- instante a mais, em vez de ficar preso numa tela preta esperando.
	local readyCFrame = waitForValidCameraCFrame(npcModel, 3)

	-- BackgroundTransparency: 0 = opaco (preto), 1 = invisível (tela
	-- normal). O bug do "quadrado preto" gigante era isso invertido aqui
	-- desde sempre: fadeTo(1) fica INVISÍVEL, não preto — então a tela
	-- nunca fundia de verdade pro preto no começo, e a chamada seguinte,
	-- fadeTo(0), deixava tudo OPACO (preto cobrindo a tela) bem na hora
	-- de mostrar o diálogo, e ficava preso assim.
	fadeTo(0, FADE_TIME)

	applyPlayerTransparency()
	lockPlayerMovement()
	startCameraFollow(npcModel, readyCFrame)
	dialogueGui.Enabled = true

	-- IMPORTANTE: popula o texto do primeiro nó ANTES de fundir de volta
	-- pro visível. Antes disso era ao contrário (fadeTo(0) primeiro,
	-- goToNode depois) — por um instante a caixa já aparecia visível só
	-- que com speakerLabel/textLabel ainda vazios, e como o fundo da
	-- caixa é quase preto (rgb 18,18,26) isso parecia exatamente um
	-- "quadrado preto" cobrindo a tela bem na hora que o diálogo abria.
	goToNode(tree.Start)

	fadeTo(1, FADE_TIME)
end

closeDialogue = function()
	if not isOpen then return end

	fadeTo(0, FADE_TIME)

	dialogueGui.Enabled = false
	clearChoiceButtons()
	stopCameraFollow()
	clearPlayerTransparency()
	unlockPlayerMovement()

	isOpen = false
	currentTree = nil
	currentNpcModel = nil
	currentNodeId = nil

	fadeTo(1, FADE_TIME)

	-- ⚠️ NOVO: só agora, com o diálogo 100% fechado (tela normal, câmera e
	-- movimento já destravados), dispara o Action pendente (ex: abrir a
	-- Loja/Roll) — pedido: "coloque pra abrir a loja ou o menu de spin só
	-- quando terminar o diálogo 100%... faça tudo aparecer no final".
	if pendingAction then
		local action = pendingAction
		pendingAction = nil
		action()
	end
end

-- ========================================
-- LIGAR OS NPCs (tag "Dialogue") AOS SEUS ProximityPrompts
-- ========================================
local connectedPrompts = {}

-- Acha a BasePart que serve de "âncora" pro ProximityPrompt. Tentado
-- várias vezes por um tempo (não só uma vez): o NPC pode estar tagueado
-- ANTES das suas partes terminarem de replicar pro cliente (streaming,
-- ou o Model acabou de entrar no Workspace), então checar só uma vez no
-- instante 0 dava falso negativo mesmo em NPCs montados certinho.
local function waitForAnchorPart(npcModel, timeoutSeconds)
	local deadline = os.clock() + timeoutSeconds
	repeat
		local anchorPart = npcModel.PrimaryPart
			or npcModel:FindFirstChild("HumanoidRootPart")
			or npcModel:FindFirstChildWhichIsA("BasePart", true)
		if anchorPart then
			return anchorPart
		end
		task.wait(0.25)
	until os.clock() >= deadline
	return nil
end

local function connectNpc(npcModel)
	if connectedPrompts[npcModel] then return end

	task.spawn(function()
		local anchorPart = waitForAnchorPart(npcModel, 10)
		if not anchorPart then
			warn("DialogueClient: '" .. npcModel:GetFullName() .. "' não tem nenhuma BasePart (nem PrimaryPart, nem HumanoidRootPart) depois de 10s — confira se o Model tem alguma parte de verdade.")
			return
		end

		local prompt = anchorPart:FindFirstChild(PROMPT_NAME) or anchorPart:WaitForChild(PROMPT_NAME, 10)
		if not prompt then
			warn("DialogueClient: '" .. npcModel:GetFullName() .. "' não tem ProximityPrompt '" .. PROMPT_NAME .. "' (NPCDialogueSetup.lua rodou no servidor?)")
			return
		end

		connectedPrompts[npcModel] = prompt.Triggered:Connect(function()
			local dialogueId = npcModel:GetAttribute("DialogueId") or npcModel.Name
			startDialogue(npcModel, dialogueId)
		end)
	end)
end

for _, npcModel in ipairs(CollectionService:GetTagged(DIALOGUE_TAG)) do
	connectNpc(npcModel)
end

CollectionService:GetInstanceAddedSignal(DIALOGUE_TAG):Connect(connectNpc)

CollectionService:GetInstanceRemovedSignal(DIALOGUE_TAG):Connect(function(npcModel)
	local connection = connectedPrompts[npcModel]
	if connection then
		connection:Disconnect()
		connectedPrompts[npcModel] = nil
	end
end)

print("✅ DialogueClient carregado.")
