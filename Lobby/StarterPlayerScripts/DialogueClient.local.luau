--[[
	DialogueClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Sistema de diálogo PRÓPRIO — serve pra TODOS os NPCs do jogo, cada um só
	precisa da tag "Dialogue" + opcionalmente o atributo DialogueId (ver
	NPCDialogueSetup no servidor e DialogueData com as falas). Tudo
	construído por código.

	⚠️ v101 — PEDIDO: "tem esse erro no lobby, eu não consigo abrir nenhum
	diálogo... tire essa tela preta de espera pra abrir as coisas, apertou,
	conversou, abriu. e melhore o design, combinando com o design atual do
	lobby."

	CAUSA DO "NÃO ABRE": o Lobby está com StreamingEnabled. O NPC existe no
	cliente, mas as PEÇAS dele só chegam quando você se aproxima. O script
	antigo procurava o ProximityPrompt de cada NPC UMA vez, desistia depois
	de 10s ("não tem nenhuma BasePart... depois de 10s") e nunca mais
	ligava o botão — o prompt aparecia, você apertava, e nada acontecia.
	Agora não existe mais "ligar prompt por NPC": o script escuta TODO
	prompt apertado (ProximityPromptService.PromptTriggered) e, se for o
	"TalkPrompt" de um Model com a tag Dialogue, abre a conversa. Não
	importa quando o NPC carregou, nem se saiu e voltou do streaming.

	FLUXO NOVO (sem tela preta):
	  1. Apertou E: a caixa sobe na hora e a câmera desliza até o NPC.
	  2. Texto "digitando" (rápido); clique/E/Espaço/Enter completa ou avança.
	  3. Escolhas numeradas (1, 2, 3...) dentro da própria caixa.
	  4. Escolha que ABRE algo (Loja, Roll, Missões, Ficha): a caixa fecha e a
	     tela abre no mesmo instante — sem a fala extra "aqui está" pra clicar.
	  5. Esc ou o X fecha.

	VISUAL: mesma paleta do Roll/Matchmaking/MissionTracker (painel escuro,
	borda discreta, acento azul, Gotham).

	ESPAÇO PRA ANIMAÇÃO: cada nó de DialogueData pode ter NpcAnimationId/
	PlayerAnimationId (playNodeAnimations abaixo toca se estiverem
	preenchidos).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

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
local camera = workspace.CurrentCamera

local DialogueData = require(ReplicatedStorage:WaitForChild("DialogueData"))

local DIALOGUE_TAG = "Dialogue"
local PROMPT_NAME = "TalkPrompt"

local TYPE_CHAR_INTERVAL = 0.012 -- segundos por letra ("digitando" rápido)
local CHARACTER_DIALOGUE_TRANSPARENCY = 0.75
local CAMERA_TWEEN_TIME = 0.35
local BOX_ANIM_TIME = 0.18

-- Paleta do Lobby (mesma do RollClient/MatchmakingClient/MissionTrackerHUD)
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

-- ========================================
-- Ações que um nó de diálogo pode disparar (Action = "Nome" no DialogueData)
-- ========================================
local function chamarGlobal(nome, origem)
	return function()
		if _G[nome] then
			_G[nome]()
		else
			warn(string.format("DialogueClient: ação chamada mas _G.%s não existe (%s carregou?)", nome, origem))
		end
	end
end
local ACTION_HANDLERS = {
	OpenShop = chamarGlobal("OpenShop", "ShopClient"),
	OpenRoll = chamarGlobal("OpenRoll", "RollClient"),
	OpenQuests = chamarGlobal("OpenQuests", "QuestClient"),
	-- ⚠️ v68: a ficha do personagem abre pela fala do kogamalotigo
	OpenCharacter = chamarGlobal("OpenCharacter", "CharacterClient"),
}

-- ========================================
-- ajudantes de estilo
-- ========================================
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

-- ========================================
-- GUI
-- ========================================
local dialogueGui = Instance.new("ScreenGui")
dialogueGui.Name = "DialogueGui"
dialogueGui.Enabled = false
dialogueGui.ResetOnSpawn = false
dialogueGui.DisplayOrder = 20
dialogueGui.Parent = playerGui

-- CanvasGroup: dá pra fazer fade da caixa inteira de uma vez
local grupo = Instance.new("CanvasGroup")
grupo.Name = "Caixa"
grupo.AnchorPoint = Vector2.new(0.5, 1)
grupo.Position = UDim2.new(0.5, 0, 1, -28)
grupo.Size = UDim2.new(1, -48, 0, 0)
grupo.AutomaticSize = Enum.AutomaticSize.Y
grupo.BackgroundTransparency = 1
grupo.Parent = dialogueGui
local limite = Instance.new("UISizeConstraint")
limite.MaxSize = Vector2.new(780, math.huge)
limite.Parent = grupo

local box = Instance.new("TextButton") -- TextButton: clique em qualquer lugar avança
box.Name = "Box"
box.AutoButtonColor = false
box.Text = ""
box.Size = UDim2.new(1, 0, 0, 0)
box.AutomaticSize = Enum.AutomaticSize.Y
box.BackgroundColor3 = COR_PAINEL
box.BackgroundTransparency = 0.04
box.Parent = grupo
cantos(box, 10)
contorno(box, COR_BORDA, 1, 0.1)
local boxPad = Instance.new("UIPadding")
boxPad.PaddingLeft = UDim.new(0, 22)
boxPad.PaddingRight = UDim.new(0, 18)
boxPad.PaddingTop = UDim.new(0, 14)
boxPad.PaddingBottom = UDim.new(0, 14)
boxPad.Parent = box
local boxLista = Instance.new("UIListLayout")
boxLista.SortOrder = Enum.SortOrder.LayoutOrder
boxLista.Padding = UDim.new(0, 10)
boxLista.Parent = box

-- faixa de acento na borda esquerda (fora do padding, desenhada por cima)
local faixa = Instance.new("Frame")
faixa.Name = "Faixa"
faixa.BackgroundColor3 = COR_ACENTO
faixa.BorderSizePixel = 0
faixa.Size = UDim2.new(0, 4, 1, -20)
faixa.Position = UDim2.new(0, 8, 0, 10)
faixa.Parent = grupo
cantos(faixa, 2)

-- cabeçalho: [NOME DO NPC] ........ [X]
local cabecalho = Instance.new("Frame")
cabecalho.Name = "Cabecalho"
cabecalho.BackgroundTransparency = 1
cabecalho.Size = UDim2.new(1, 0, 0, 26)
cabecalho.LayoutOrder = 1
cabecalho.Parent = box

local nomeChip = Instance.new("TextLabel")
nomeChip.Name = "Nome"
nomeChip.AutomaticSize = Enum.AutomaticSize.X
nomeChip.Size = UDim2.new(0, 0, 1, 0)
nomeChip.BackgroundColor3 = COR_CARTAO_ALT
nomeChip.Font = Enum.Font.GothamBlack
nomeChip.TextSize = 13
nomeChip.TextColor3 = COR_ACENTO
nomeChip.Text = ""
nomeChip.Parent = cabecalho
cantos(nomeChip, 6)
contorno(nomeChip, COR_ACENTO, 1, 0.55)
local nomePad = Instance.new("UIPadding")
nomePad.PaddingLeft = UDim.new(0, 10)
nomePad.PaddingRight = UDim.new(0, 10)
nomePad.Parent = nomeChip

local fechar = Instance.new("TextButton")
fechar.Name = "Fechar"
fechar.AnchorPoint = Vector2.new(1, 0)
fechar.Position = UDim2.new(1, 0, 0, 0)
fechar.Size = UDim2.fromOffset(26, 26)
fechar.BackgroundColor3 = COR_CARTAO_ALT
fechar.AutoButtonColor = true
fechar.Font = Enum.Font.GothamBold
fechar.TextSize = 14
fechar.TextColor3 = COR_TEXTO_FRACO
fechar.Text = "X"
fechar.Parent = cabecalho
cantos(fechar, 13)

-- texto da fala
local textLabel = Instance.new("TextLabel")
textLabel.Name = "Fala"
textLabel.BackgroundTransparency = 1
textLabel.Size = UDim2.new(1, 0, 0, 0)
textLabel.AutomaticSize = Enum.AutomaticSize.Y
textLabel.Font = Enum.Font.GothamMedium
textLabel.TextSize = 17
textLabel.LineHeight = 1.15
textLabel.TextColor3 = COR_TEXTO
textLabel.TextWrapped = true
textLabel.TextXAlignment = Enum.TextXAlignment.Left
textLabel.TextYAlignment = Enum.TextYAlignment.Top
textLabel.Text = ""
textLabel.LayoutOrder = 2
textLabel.Parent = box

-- escolhas (dentro da caixa)
local choicesFrame = Instance.new("Frame")
choicesFrame.Name = "Escolhas"
choicesFrame.BackgroundTransparency = 1
choicesFrame.Size = UDim2.new(1, 0, 0, 0)
choicesFrame.AutomaticSize = Enum.AutomaticSize.Y
choicesFrame.LayoutOrder = 3
choicesFrame.Visible = false
choicesFrame.Parent = box
local choicesLayout = Instance.new("UIListLayout")
choicesLayout.Padding = UDim.new(0, 6)
choicesLayout.SortOrder = Enum.SortOrder.LayoutOrder
choicesLayout.Parent = choicesFrame

-- rodapé: "▼ continuar"
local advanceHint = Instance.new("TextLabel")
advanceHint.Name = "Continuar"
advanceHint.BackgroundTransparency = 1
advanceHint.Size = UDim2.new(1, 0, 0, 14)
advanceHint.Font = Enum.Font.GothamBold
advanceHint.TextSize = 12
advanceHint.TextColor3 = COR_TEXTO_FRACO
advanceHint.TextXAlignment = Enum.TextXAlignment.Right
advanceHint.Text = "▼  clique ou E pra continuar"
advanceHint.LayoutOrder = 4
advanceHint.Visible = false
advanceHint.Parent = box

-- ========================================
-- ESTADO
-- ========================================
local isOpen = false
local currentTree = nil
local currentNpcModel = nil
local currentNodeId = nil
local typeGeneration = 0
local isTyping = false
local botoesEscolha = {}

local savedCameraType = nil
local savedWalkSpeed, savedJumpPower, savedJumpHeight = nil, nil, nil
local transparencyConnection = nil
local cameraFollowConnection = nil
local hintConnection = nil

-- ========================================
-- JOGADOR: translúcido só na sua tela + travado
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
	transparencyConnection = character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then d.LocalTransparencyModifier = CHARACTER_DIALOGUE_TRANSPARENCY end
	end)
end

local function clearPlayerTransparency()
	if transparencyConnection then
		transparencyConnection:Disconnect()
		transparencyConnection = nil
	end
	if player.Character then setLocalCharacterTransparency(player.Character, 0) end
end

local function lockPlayerMovement()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	savedWalkSpeed, savedJumpPower, savedJumpHeight = humanoid.WalkSpeed, humanoid.JumpPower, humanoid.JumpHeight
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.JumpHeight = 0
end

local function unlockPlayerMovement()
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if savedWalkSpeed then humanoid.WalkSpeed = savedWalkSpeed end
	if savedJumpPower then humanoid.JumpPower = savedJumpPower end
	if savedJumpHeight then humanoid.JumpHeight = savedJumpHeight end
end

-- ========================================
-- CÂMERA: sobre o ombro do jogador, olhando o NPC. Sem espera: se não der
-- pra calcular agora, a câmera normal fica (nada de tela preta esperando).
-- ========================================
local function getHeadPosition(model)
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then return head.Position end
	local anchor = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	return anchor and anchor.Position or nil
end

local function computeDialogueCameraCFrame(npcModel)
	local character = player.Character
	if not character then return nil end
	local playerHeadPos = getHeadPosition(character)
	local npcHeadPos = getHeadPosition(npcModel)
	if not playerHeadPos or not npcHeadPos then return nil end

	local flatDelta = Vector3.new(npcHeadPos.X - playerHeadPos.X, 0, npcHeadPos.Z - playerHeadPos.Z)
	local flatDir = flatDelta.Magnitude > 0.01 and flatDelta.Unit or Vector3.new(0, 0, -1)
	local sideDir = flatDir:Cross(Vector3.new(0, 1, 0))
	local desiredOffset = sideDir * 2.3 - flatDir * 0.6 + Vector3.new(0, 0.35, 0)

	-- não deixa a câmera entrar numa parede (câmera dentro de geometria =
	-- tela preta)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, npcModel }
	local camPos = playerHeadPos + desiredOffset
	local hit = workspace:Raycast(playerHeadPos, desiredOffset, params)
	if hit then
		camPos = playerHeadPos + desiredOffset.Unit * math.max(hit.Distance - 0.3, 0.2)
	end
	return CFrame.lookAt(camPos, npcHeadPos)
end

local function startCameraFollow(npcModel)
	local alvo = computeDialogueCameraCFrame(npcModel)
	if not alvo then return end
	camera.CameraType = Enum.CameraType.Scriptable
	local inicio = camera.CFrame
	local t0 = os.clock()
	cameraFollowConnection = RunService.RenderStepped:Connect(function()
		local cf = computeDialogueCameraCFrame(npcModel)
		if not cf then return end
		local u = math.clamp((os.clock() - t0) / CAMERA_TWEEN_TIME, 0, 1)
		u = 1 - (1 - u) ^ 3 -- easeOut: desliza e assenta
		camera.CFrame = inicio:Lerp(cf, u)
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
-- ANIMAÇÃO (espaço reservado)
-- ========================================
local function playNodeAnimations(node, npcModel)
	local function tocar(model, id)
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		if animator then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			animator:LoadAnimation(anim):Play()
		end
	end
	if node.NpcAnimationId then tocar(npcModel, node.NpcAnimationId) end
	if node.PlayerAnimationId then tocar(player.Character, node.PlayerAnimationId) end
end

-- ========================================
-- TEXTO "DIGITANDO" (pelo número de letras visíveis: não quebra acento)
-- ========================================
local function typeText(fullText)
	typeGeneration += 1
	local minha = typeGeneration
	isTyping = true
	textLabel.Text = fullText
	textLabel.MaxVisibleGraphemes = 0
	local total = utf8.len(fullText) or #fullText
	task.spawn(function()
		for i = 1, total do
			if minha ~= typeGeneration then return end
			textLabel.MaxVisibleGraphemes = i
			task.wait(TYPE_CHAR_INTERVAL)
		end
		if minha == typeGeneration then
			textLabel.MaxVisibleGraphemes = -1
			isTyping = false
		end
	end)
end

local function skipTyping()
	typeGeneration += 1
	textLabel.MaxVisibleGraphemes = -1
	isTyping = false
end

-- ========================================
-- NAVEGAÇÃO
-- ========================================
local closeDialogue -- forward
local goToNode -- forward

local function clearChoiceButtons()
	for _, b in ipairs(botoesEscolha) do b:Destroy() end
	table.clear(botoesEscolha)
	choicesFrame.Visible = false
end

local function mostrarEscolhas(node)
	clearChoiceButtons()
	for i, choice in ipairs(node.Choices) do
		local botao = Instance.new("TextButton")
		botao.Name = "Escolha" .. i
		botao.LayoutOrder = i
		botao.Size = UDim2.new(1, 0, 0, 38)
		botao.BackgroundColor3 = COR_CARTAO
		botao.AutoButtonColor = false
		botao.Text = ""
		botao.Parent = choicesFrame
		cantos(botao, 8)
		local borda = contorno(botao, COR_BORDA, 1, 0)

		local tecla = Instance.new("TextLabel")
		tecla.Name = "Tecla"
		tecla.AnchorPoint = Vector2.new(0, 0.5)
		tecla.Position = UDim2.new(0, 8, 0.5, 0)
		tecla.Size = UDim2.fromOffset(22, 22)
		tecla.BackgroundColor3 = COR_CARTAO_ALT
		tecla.Font = Enum.Font.GothamBlack
		tecla.TextSize = 12
		tecla.TextColor3 = COR_ACENTO
		tecla.Text = tostring(i)
		tecla.Parent = botao
		cantos(tecla, 5)

		local texto = Instance.new("TextLabel")
		texto.Name = "Texto"
		texto.BackgroundTransparency = 1
		texto.Position = UDim2.new(0, 40, 0, 0)
		texto.Size = UDim2.new(1, -52, 1, 0)
		texto.Font = Enum.Font.GothamBold
		texto.TextSize = 15
		texto.TextColor3 = COR_TEXTO
		texto.TextXAlignment = Enum.TextXAlignment.Left
		texto.TextTruncate = Enum.TextTruncate.AtEnd
		texto.Text = choice.Text
		texto.Parent = botao

		-- a escolha que abre uma tela ganha a setinha "›"
		local destino = choice.Next and currentTree.Nodes[choice.Next]
		if destino and destino.Action then
			local seta = Instance.new("TextLabel")
			seta.BackgroundTransparency = 1
			seta.AnchorPoint = Vector2.new(1, 0.5)
			seta.Position = UDim2.new(1, -10, 0.5, 0)
			seta.Size = UDim2.fromOffset(16, 22)
			seta.Font = Enum.Font.GothamBlack
			seta.TextSize = 18
			seta.TextColor3 = COR_ACENTO
			seta.Text = "›"
			seta.Parent = botao
		end

		local info = TweenInfo.new(0.1)
		botao.MouseEnter:Connect(function()
			TweenService:Create(botao, info, { BackgroundColor3 = COR_CARTAO_ALT }):Play()
			TweenService:Create(borda, info, { Color = COR_ACENTO }):Play()
		end)
		botao.MouseLeave:Connect(function()
			TweenService:Create(botao, info, { BackgroundColor3 = COR_CARTAO }):Play()
			TweenService:Create(borda, info, { Color = COR_BORDA }):Play()
		end)
		botao.MouseButton1Click:Connect(function()
			goToNode(choice.Next)
		end)
		table.insert(botoesEscolha, botao)
	end
	choicesFrame.Visible = true
end

goToNode = function(nodeId)
	if not isOpen then return end
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

	-- "apertou, conversou, abriu": nó que abre uma tela fecha o diálogo e
	-- abre NA HORA (a fala desse nó — "aqui está!" — era só mais um clique)
	if node.Action and ACTION_HANDLERS[node.Action] then
		closeDialogue(ACTION_HANDLERS[node.Action])
		return
	end

	nomeChip.Text = maiusculas(node.Speaker or currentNpcModel.Name)
	clearChoiceButtons()
	advanceHint.Visible = false
	playNodeAnimations(node, currentNpcModel)
	typeText(node.Text or "")

	if node.Choices and #node.Choices > 0 then
		mostrarEscolhas(node)
	else
		advanceHint.Text = node.Next and "▼  clique ou E pra continuar" or "▼  clique ou E pra fechar"
		advanceHint.Visible = true
	end
end

-- avançar: completa o texto se ainda estiver digitando; senão segue
local function avancar()
	if not isOpen or not currentNodeId then return end
	local node = currentTree.Nodes[currentNodeId]
	if not node then return end
	if isTyping then
		skipTyping()
		return
	end
	if not (node.Choices and #node.Choices > 0) then
		goToNode(node.Next)
	end
end

box.MouseButton1Click:Connect(avancar)
fechar.MouseButton1Click:Connect(function() closeDialogue() end)

local TECLAS_NUMERO = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3, [Enum.KeyCode.KeypadFour] = 4,
}
local abertoEm = 0
UserInputService.InputBegan:Connect(function(input, processado)
	if not isOpen then return end
	-- 1-4 são teclas da barra de itens do Roblox (CoreGui): podem chegar
	-- marcadas como "processadas" — só ignora de verdade se estiver
	-- digitando no chat
	if processado and (not TECLAS_NUMERO[input.KeyCode] or UserInputService:GetFocusedTextBox()) then return end
	-- o mesmo E que abriu a conversa não pode já avançar a fala
	if os.clock() - abertoEm < 0.2 then return end
	local kc = input.KeyCode
	if kc == Enum.KeyCode.Escape then
		closeDialogue()
	elseif kc == Enum.KeyCode.E or kc == Enum.KeyCode.Space or kc == Enum.KeyCode.Return or kc == Enum.KeyCode.ButtonA then
		avancar()
	elseif TECLAS_NUMERO[kc] then
		local node = currentTree.Nodes[currentNodeId]
		local escolha = node and node.Choices and node.Choices[TECLAS_NUMERO[kc]]
		if escolha then
			if isTyping then skipTyping() end
			goToNode(escolha.Next)
		end
	end
end)

-- ========================================
-- ABRIR / FECHAR (sem tela preta)
-- ========================================
local function animarEntrada()
	grupo.GroupTransparency = 1
	grupo.Position = UDim2.new(0.5, 0, 1, -8)
	local info = TweenInfo.new(BOX_ANIM_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(grupo, info, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, -28) }):Play()
end

local function startDialogue(npcModel, dialogueId)
	if isOpen then return end
	local tree = DialogueData[dialogueId]
	if not tree then
		warn("DialogueClient: nenhuma árvore de diálogo pra '" .. tostring(dialogueId) .. "' (confira o DialogueId contra as chaves do DialogueData)")
		return
	end

	isOpen = true
	abertoEm = os.clock()
	currentTree = tree
	currentNpcModel = npcModel
	savedCameraType = camera.CameraType
	-- o prompt "Conversar" some enquanto a conversa estiver aberta (senão o
	-- E que avança o texto reabriria a conversa)
	ProximityPromptService.Enabled = false

	applyPlayerTransparency()
	lockPlayerMovement()
	startCameraFollow(npcModel)

	dialogueGui.Enabled = true
	goToNode(tree.Start)
	animarEntrada()

	-- setinha "▼" pulsando
	hintConnection = RunService.RenderStepped:Connect(function()
		advanceHint.TextTransparency = 0.25 + 0.35 * (0.5 + 0.5 * math.sin(os.clock() * 5))
	end)
end

closeDialogue = function(acao)
	if not isOpen then return end
	isOpen = false
	typeGeneration += 1
	isTyping = false

	if hintConnection then
		hintConnection:Disconnect()
		hintConnection = nil
	end
	clearChoiceButtons()
	stopCameraFollow()
	clearPlayerTransparency()
	unlockPlayerMovement()
	dialogueGui.Enabled = false
	ProximityPromptService.Enabled = true

	currentTree = nil
	currentNpcModel = nil
	currentNodeId = nil

	-- abre a tela pedida (Loja/Roll/Missões/Ficha) no mesmo instante
	if typeof(acao) == "function" then
		acao()
	end
end

-- ========================================
-- NPCs: escuta QUALQUER prompt apertado (funciona com StreamingEnabled —
-- ver o cabeçalho)
-- ========================================
local function npcDoPrompt(prompt)
	if prompt.Name ~= PROMPT_NAME then return nil end
	local atual = prompt.Parent
	while atual and atual ~= workspace do
		if atual:IsA("Model") and CollectionService:HasTag(atual, DIALOGUE_TAG) then
			return atual
		end
		atual = atual.Parent
	end
	return nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, quem)
	if quem ~= player then return end
	local npcModel = npcDoPrompt(prompt)
	if not npcModel then return end
	local dialogueId = npcModel:GetAttribute("DialogueId") or npcModel.Name
	startDialogue(npcModel, dialogueId)
end)

-- se o personagem morrer/renascer no meio da conversa, fecha limpo
player.CharacterAdded:Connect(function()
	if isOpen then closeDialogue() end
end)

print("✅ DialogueClient carregado.")
