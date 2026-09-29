--[[
	GoalReplayClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Game)

	PEDIDO ORIGINAL: "durante o áudio, coloque um sistema simples de replay
	que visualiza a bola".

	PEDIDO NOVO (v27): "a bola está amarela/dourada, eu não quero isso,
	quero ela normal, e nem os jogadores e nem o bot aparecem em campo, é
	para aparecerem os dois e recriarem exatamente a jogada, se alguém
	passou pra alguém, quem fez gol, onde o bot foi... entendeu?"

	Cada gol, o servidor manda (Remotes.GoalReplay) um retrato completo do
	lance dos últimos segundos: posição da bola, posição+direção de CADA
	JOGADOR em campo, e posição+direção de qualquer BOT de goleiro ativo
	(ver BallController.lua -> matchHistory / _G.GetReplaySnapshot). Este
	script pega esse retrato e recria a cena inteira com "fantasmas"
	(clones 100% visuais, sem física, sem colisão) deslizando pelo caminho
	gravado de cada um — bola, jogadores e bot juntos, sincronizados.

	SOBRE A BOLA "NORMAL" (v27): antes era uma esfera Neon amarela/dourada
	separada. Agora o fantasma da bola é um CLONE DA BOLA DE VERDADE (pega
	a aparência real dela, seja lá qual for), só com física/colisão
	desligada — fica visualmente igual à bola do jogo.

	SOBRE OS FANTASMAS DE JOGADOR/BOT (v27, NOVO): são clones do Model
	atual de cada jogador (Players:GetPlayerByUserId) e do bot
	(workspace:FindFirstChild("GKBot_" .. time), nome que o
	GKBotController.lua usa) — sem Humanoid/Script/Animator, viram um
	"boneco estático" que só desliza pela posição gravada (sem animação de
	passo/chute — dá pra melhorar depois se quiser). Se um jogador saiu da
	partida ou o bot não existe mais no momento do replay, esse ator
	simplesmente não aparece (não trava o resto do replay).

	Não precisa criar nada no Studio: tudo aqui é 100% gerado por código
	(só Scripts sincronizam pela ponte — ver regra do projeto).

	PEDIDO NOVO (v28): "assim que rola o replay, o GKBOT original e o
	player precisam sumir, pra não conflitar com a visualização do
	replay" — agora, enquanto o replay toca, TODO jogador em campo e
	TODO bot de goleiro de verdade ficam escondidos (só visualmente, só
	local, ver hideRealActorsForReplay) e voltam a aparecer normalmente
	assim que o replay termina.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = workspace

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ============================================================
-- ⚠️ v20 — CÂMERA ORBITAL DO REPLAY
-- PEDIDO: "deixe que quem estiver jogando possa alterar a posição da
-- câmera, girando ela igual faria com o personagem normal; deixe a câmera
-- travada na bola podendo mexer com o botão direito, sem ficar
-- teleportando toda hora pra bola — já mantenha ela colada na bola como
-- parte dela."
--
-- Antes a câmera era RECALCULADA do zero todo frame a partir da direção de
-- movimento da bola (CFrame.lookAt de um ponto atrás dela). Como a direção
-- muda a cada quique/curva, o ponto de vista pulava junto — daí a sensação
-- de "teleportando toda hora". E não tinha como mexer nela.
--
-- Agora a câmera é uma órbita presa na bola: a POSIÇÃO vem sempre da bola
-- (fica colada nela, como se fosse parte dela), mas o ÂNGULO é só seu —
-- botão direito arrasta pra girar, igual a câmera do personagem, e a roda
-- do mouse aproxima/afasta. Nada mais mexe no ângulo sozinho.
-- ============================================================
local UserInputService = game:GetService("UserInputService")

local REPLAY_CAM_SENSITIVITY = 0.006
local REPLAY_CAM_MIN_PITCH = math.rad(-75)
local REPLAY_CAM_MAX_PITCH = math.rad(45)
local REPLAY_CAM_MIN_DISTANCE = 8
local REPLAY_CAM_MAX_DISTANCE = 40

local replayCamYaw = 0
local replayCamPitch = math.rad(-18)
local replayCamDistance = 16
local replayCamOrbiting = false
local replayInProgress = false -- setado pelo playback; a órbita só responde durante o replay

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not replayInProgress then return end
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		replayCamOrbiting = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		replayCamOrbiting = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end)

UserInputService.InputChanged:Connect(function(input, processed)
	if not replayInProgress then return end
	if input.UserInputType == Enum.UserInputType.MouseMovement and replayCamOrbiting then
		replayCamYaw -= input.Delta.X * REPLAY_CAM_SENSITIVITY
		replayCamPitch = math.clamp(
			replayCamPitch - input.Delta.Y * REPLAY_CAM_SENSITIVITY,
			REPLAY_CAM_MIN_PITCH,
			REPLAY_CAM_MAX_PITCH
		)
	elseif input.UserInputType == Enum.UserInputType.Touch and replayCamOrbiting then
		replayCamYaw -= input.Delta.X * REPLAY_CAM_SENSITIVITY
		replayCamPitch = math.clamp(
			replayCamPitch - input.Delta.Y * REPLAY_CAM_SENSITIVITY,
			REPLAY_CAM_MIN_PITCH,
			REPLAY_CAM_MAX_PITCH
		)
	elseif input.UserInputType == Enum.UserInputType.MouseWheel and not processed then
		replayCamDistance = math.clamp(
			replayCamDistance - input.Position.Z * 3,
			REPLAY_CAM_MIN_DISTANCE,
			REPLAY_CAM_MAX_DISTANCE
		)
	end
end)

-- No celular não existe botão direito: qualquer arraste na tela gira.
UserInputService.TouchStarted:Connect(function()
	if replayInProgress then replayCamOrbiting = true end
end)
UserInputService.TouchEnded:Connect(function()
	replayCamOrbiting = false
end)
local ball = Workspace:WaitForChild(Config.BALL_NAME)

-- ⚠️ v20: replayInProgress é declarado LÁ EM CIMA agora (junto da câmera
-- orbital), porque os handlers de input precisam dele. Redeclarar aqui
-- criaria uma SEGUNDA variável: o playback ligaria uma e os handlers
-- leriam a outra, e a órbita nunca responderia.

-- ===== TEXTO "Replay" NA TELA (PEDIDO: "precisa de um texto escrito
-- 'Replay' em algum lugar que esteja livre na tela") — 100% por código
-- (só Scripts sincronizam pela ponte), num canto livre (canto superior
-- esquerdo) que nenhuma outra UI do jogo usa. Some sozinho quando o
-- replay não está tocando.
local replayGui = Instance.new("ScreenGui")
replayGui.Name = "GoalReplayLabelGui"
replayGui.ResetOnSpawn = false
replayGui.IgnoreGuiInset = true
replayGui.DisplayOrder = 50
replayGui.Parent = player:WaitForChild("PlayerGui")

local replayLabel = Instance.new("TextLabel")
replayLabel.Name = "ReplayLabel"
replayLabel.AnchorPoint = Vector2.new(0, 0)
replayLabel.Position = UDim2.new(0, 20, 0, 20)
replayLabel.Size = UDim2.new(0, 160, 0, 40)
replayLabel.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
replayLabel.BackgroundTransparency = 0.45
replayLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
replayLabel.Font = Enum.Font.GothamBlack
replayLabel.TextScaled = true
replayLabel.Text = "🔁 REPLAY"
replayLabel.Visible = false
replayLabel.Parent = replayGui

local labelCorner = Instance.new("UICorner")
labelCorner.CornerRadius = UDim.new(0, 8)
labelCorner.Parent = replayLabel

-- ===== FANTASMAS (clones 100% visuais) =====

-- Bola: clone da bola DE VERDADE (v27 — "quero ela normal", não mais uma
-- esfera amarela separada), só com física/colisão desligada.
local function buildGhostBall()
	local ghost = ball:Clone()
	ghost.Name = "GoalReplayGhostBall"
	ghost.Anchored = true
	ghost.CanCollide = false
	ghost.CanQuery = false
	ghost.CanTouch = false
	ghost.CastShadow = false

	-- tira o que não é puramente visual (som, força de gravidade
	-- assistida, texto de força de Pulso etc.) — não precisa de nada disso
	-- num fantasma parado/anchored, e evita som duplicado ou lixo visual.
	for _, child in ipairs(ghost:GetChildren()) do
		if child:IsA("Sound") or child:IsA("VectorForce") or child:IsA("Attachment") or child:IsA("BillboardGui") then
			child:Destroy()
		end
	end

	ghost.Parent = Workspace
	return ghost
end

-- Jogador/bot: reconstrói visualmente o Model atual (personagem ou bot),
-- virado um "boneco estático" sem Humanoid/Script/Animator/Sound — só
-- desliza pela posição gravada via Model:PivotTo.
--
-- v31 FIX (causa real, achada pelo diagnóstico v30 — "Clone() devolveu nil"
-- pros DOIS jogadores, até o local): Model de PERSONAGEM DE JOGADOR tem
-- Archivable = false POR PADRÃO no próprio Roblox (proteção de fábrica
-- contra clonar personagem de outro jogador por LocalScript) — por isso
-- sourceModel:Clone() sempre ia devolver nil pra characters, não importa o
-- que a gente fizesse. A solução: Archivable=false só bloqueia clonar
-- AQUELE objeto específico — as Partes/acessórios individuais DENTRO do
-- character continuam Archivable=true (padrão), então em vez de clonar o
-- Model inteiro de uma vez, clonamos parte por parte e montamos um Model
-- novo do zero. Não precisa de Humanoid/Motor6D pra isso: o fantasma
-- sempre foi "rígido" (o Model inteiro anda junto via Model:PivotTo), só
-- as posições relativas das partes no instante do clone importam.
-- ⚠️ v21 — PEDIDO: "as animações durante a cutscene e o replay não estão
-- tocando (mas eles voltaram a se mexer)".
--
-- A remontagem manual do rig (clonar parte por parte e recriar os Motor6D)
-- faz o boneco ANDAR, mas não é um personagem válido do ponto de vista do
-- Humanoid: ele não reconhece o próprio RootPart, e sem isso o Animator
-- não tem por onde aplicar os keyframes. Por isso o track toca (sem erro) e
-- nada se mexe.
--
-- A causa original de não clonar o Model inteiro era "Model:Clone() devolve
-- nil porque o Character tem Archivable = false de fábrica" — o que é
-- verdade, mas Archivable é uma propriedade COMUM: dá pra ligar, clonar e
-- devolver como estava. Isso entrega um rig perfeito (juntas, Humanoid,
-- roupas, acessórios) em uma linha, e a animação simplesmente funciona.
--
-- A remontagem manual continua logo abaixo como plano B, pro caso de a
-- clonagem falhar (personagem sendo destruído no meio, etc.).
-- Toca a animação de andar em loop no fantasma (vale pros dois caminhos de
-- construção: clone inteiro e remontagem manual).
local function startGhostWalkAnimation(ghostModel)
	-- ⚠️ v96: com a animação por código ligada, o fantasma é animado pelo
	-- AnimadorProcedural a partir do próprio movimento no replay (parado,
	-- andando, correndo, no ar) — em vez de andar em loop até parado.
	if Config.ANIMACAO_PROCEDURAL and _G.AnimadorRegistrar then
		_G.AnimadorRegistrar(ghostModel)
		return
	end
	local walkId = Config.NormalizeAnimationId(Config.ANIMATIONS and Config.ANIMATIONS.Walk)
	if not walkId or walkId == "" then return end
	local ghostHumanoid = ghostModel:FindFirstChildOfClass("Humanoid")
	if not ghostHumanoid then return end

	local animator = ghostHumanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = ghostHumanoid
	end

	local animation = Instance.new("Animation")
	animation.AnimationId = walkId
	local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
	if ok and track then
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		track:Play()
	else
		warn("🎞️ [Replay] não consegui tocar a animação de andar no fantasma: " .. tostring(track))
	end
end

local function cloneWholeCharacter(sourceModel, nameSuffix)
	local previousArchivable = sourceModel.Archivable
	sourceModel.Archivable = true
	local ok, modelClone = pcall(function() return sourceModel:Clone() end)
	sourceModel.Archivable = previousArchivable
	if not ok or not modelClone then return nil end

	modelClone.Name = "GoalReplayGhost_" .. nameSuffix

	-- Tira tudo que faria o clone "viver": scripts, sons e a rede de
	-- colisão. O Humanoid FICA (é ele que faz a animação e as roupas
	-- aparecerem), só sem barra de vida/nome.
	for _, inst in ipairs(modelClone:GetDescendants()) do
		if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("Sound") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Anchored = false
		end
	end

	local humanoid = modelClone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		-- Nada de PlatformStand/ChangeState aqui de propósito: os dois mexem
		-- na máquina de estados do Humanoid e podem engolir a animação. Com o
		-- root anchorado e os scripts removidos, ele já não anda sozinho.
	end

	local rootPart = modelClone:FindFirstChild("HumanoidRootPart")
		or (humanoid and humanoid.RootPart)
		or modelClone.PrimaryPart
		or modelClone:FindFirstChildWhichIsA("BasePart")
	if not rootPart then
		modelClone:Destroy()
		return nil
	end

	-- Só o root fica preso: o PivotTo arrasta ele e os Motor6D levam o
	-- resto, deixando a animação livre pros membros.
	rootPart.Anchored = true
	modelClone.PrimaryPart = rootPart
	modelClone.Parent = Workspace
	return modelClone
end

local function buildGhostFromModel(sourceModel, nameSuffix)
	if not sourceModel then return nil, "sourceModel é nil" end

	local whole = cloneWholeCharacter(sourceModel, nameSuffix)
	if whole then
		startGhostWalkAnimation(whole)
		return whole
	end

	local ghostRoot = Instance.new("Model")
	ghostRoot.Name = "GoalReplayGhost_" .. nameSuffix

	local clonedRoot = nil
	local anyPartCloned = false
	-- ⚠️ v18: mapa parte original -> clone, pra poder RECONSTRUIR as juntas
	-- depois (ver o bloco de juntas logo abaixo do loop).
	local cloneByOriginal = {}

	for _, inst in ipairs(sourceModel:GetDescendants()) do
		if inst:IsA("BasePart") then
			local ok, partClone = pcall(function() return inst:Clone() end)
			if ok and partClone then
				-- ⚠️ v18 — PEDIDO: "faça a animação de andar tocar no replay de
				-- gol". Antes TODA parte do fantasma era anchored, e parte
				-- anchored não anima (o Motor6D não consegue mover) — mesma
				-- causa do bug da torcida. Agora só o HumanoidRootPart fica
				-- anchored: ele é quem o PivotTo arrasta, e os membros ficam
				-- livres pra animação mexer.
				partClone.Anchored = (inst.Name == "HumanoidRootPart")
				partClone.CanCollide = false
				partClone.CanQuery = false
				partClone.CanTouch = false
				cloneByOriginal[inst] = partClone
				-- v33 FIX: "fica travando pra um lado e depois pro outro" — o
				-- Motor6D/Weld de dentro de cada Parte (ex: "Neck" ligando
				-- Torso->Head) É CLONADO JUNTO (é filho da Part), mas o
				-- Part0/Part1 dele continua apontando pras Partes DE VERDADE
				-- do personagem (vivo, se mexendo) — porque a gente clona
				-- parte por parte, não o Model inteiro de uma vez, então o
				-- Roblox não tem como "religar" essas juntas pros clones
				-- certos. Resultado: a cada frame de física, essa junta
				-- ainda tenta puxar/alinhar a Parte clonada com a Parte real
				-- (que está se mexendo), brigando com o nosso Model:PivotTo
				-- — daí o "trava pra um lado, volta pro outro". O fantasma é
				-- 100% rígido (anda inteiro via PivotTo), não precisa de
				-- NENHUMA junta, então destruímos todas.
				for _, child in ipairs(partClone:GetChildren()) do
					if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("Sound")
						or child:IsA("JointInstance") or child:IsA("WeldConstraint") then
						child:Destroy()
					end
				end
				partClone.Parent = ghostRoot
				anyPartCloned = true
				if inst.Name == "HumanoidRootPart" then
					clonedRoot = partClone
				end
			end
		end
	end

	if not anyPartCloned then
		ghostRoot:Destroy()
		return nil, "nenhuma Part do personagem/bot pôde ser clonada"
	end

	-- ⚠️ v18: RECONSTRÓI AS JUNTAS. O comentário do v33 acima explica por que
	-- as juntas CLONADAS tinham que morrer (o Part0/Part1 delas continuava
	-- apontando pras partes do personagem VIVO, e elas brigavam com o
	-- PivotTo). Isso continua verdade — mas "destruir e ficar sem junta
	-- nenhuma" é o que deixava o fantasma uma estátua rígida, impossível de
	-- animar. A solução certa é criar juntas NOVAS, ligando clone a clone:
	-- aí o rig existe de verdade, o PivotTo continua arrastando tudo pelo
	-- root anchorado, e a animação tem onde mexer.
	local jointedParts = {}
	for _, inst in ipairs(sourceModel:GetDescendants()) do
		if inst:IsA("Motor6D") or inst:IsA("Weld") then
			local p0 = inst.Part0 and cloneByOriginal[inst.Part0]
			local p1 = inst.Part1 and cloneByOriginal[inst.Part1]
			if p0 and p1 then
				local joint = Instance.new(inst.ClassName)
				joint.Name = inst.Name
				joint.Part0 = p0
				joint.Part1 = p1
				joint.C0 = inst.C0
				joint.C1 = inst.C1
				joint.Parent = p0
				jointedParts[p0] = true
				jointedParts[p1] = true
			end
		end
	end

	-- Qualquer parte que ficou SEM junta (acessório cujo weld não pôde ser
	-- remontado, parte solta de rig customizado) volta a ser anchored — sem
	-- isso ela cairia pelo mapa no meio do replay, já que não tem nada
	-- segurando ela.
	for _, partClone in pairs(cloneByOriginal) do
		if not jointedParts[partClone] and not partClone.Anchored then
			partClone.Anchored = true
		end
	end

	-- v32: "não esquece de inserir as roupas" — Shirt/Pants só aparecem
	-- desenhados em cima das Partes (Torso/Braço/Perna) quando existe um
	-- Humanoid no mesmo Model; sem isso as partes clonadas ficam só com a
	-- cor de pele, sem a roupa por cima. Nenhum desses tem o problema de
	-- Archivable=false do Model em si, então clonam normalmente.
	for _, inst in ipairs(sourceModel:GetChildren()) do
		if inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("BodyColors") or inst:IsA("ShirtGraphic") then
			local ok, clone = pcall(function() return inst:Clone() end)
			if ok and clone then
				clone.Parent = ghostRoot
			end
		elseif inst:IsA("Humanoid") then
			local ok, humanoidClone = pcall(function() return inst:Clone() end)
			if ok and humanoidClone then
				-- só serve pra ativar o desenho da roupa — não queremos barra
				-- de vida/nome flutuando em cima do fantasma.
				humanoidClone.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				humanoidClone.Parent = ghostRoot
			end
		end
	end

	-- normalmente acha o HumanoidRootPart clonado; se por algum motivo não
	-- achar (rig sem esse nome específico), usa qualquer outra Part clonada
	-- como referência — melhor um fantasma levemente deslocado do que nenhum.
	if not clonedRoot then
		clonedRoot = ghostRoot:FindFirstChildOfClass("BasePart")
	end

	if not clonedRoot then
		ghostRoot:Destroy()
		return nil, "clonou partes mas nenhuma é uma BasePart válida pra ser PrimaryPart"
	end

	ghostRoot.PrimaryPart = clonedRoot
	-- ⚠️ v20 FIX ("os fantasmas pararam de se mover"): antes eu anchorava a
	-- parte CHAMADA "HumanoidRootPart". Quando o rig não tem uma com esse
	-- nome exato (caso do GKBot), clonedRoot caía no fallback "qualquer
	-- BasePart" — e aí NENHUMA parte ficava anchorada. Sem parte anchorada o
	-- fantasma virava um boneco de física solto: mover o PrimaryPart não
	-- levava nada, e ele ficava pra trás. Agora quem manda é o PrimaryPart
	-- de verdade, seja ele quem for.
	clonedRoot.Anchored = true
	ghostRoot.Parent = Workspace

	-- ⚠️ v18 — PEDIDO: "faça a animação de andar tocar no replay de gol".
	-- Agora que o rig tem juntas de verdade (ver o bloco acima), dá pra
	-- animar: Animator no Humanoid clonado + a animação de andar em loop
	-- pelo replay inteiro. Carrega pelo Animator (Humanoid:LoadAnimation é
	-- deprecated e falha em rig sem Animator). Sem id configurado em
	-- Config.ANIMATIONS.Walk, simplesmente não faz nada.
	startGhostWalkAnimation(ghostRoot)

	return ghostRoot
end

-- ===== ESCONDER OS ORIGINAIS DURANTE O REPLAY =====
-- PEDIDO (v28): "assim que rola o replay, o GKBOT original e o player
-- precisam sumir, pra não conflitar com a visualização do replay" — os
-- fantasmas são clones que ficam por cima/perto dos originais (o jogador de
-- verdade fica parado no local onde chutou, o GKBot de verdade continua
-- defendendo), então dava a impressão de "dois GKBots"/personagem duplicado.
--
-- Escondemos os originais só VISUALMENTE, só pra quem está vendo o replay
-- (LocalTransparencyModifier é 100% local/client-side — não muda a Parte de
-- verdade nem afeta o servidor, outros scripts, ou colisão/física de
-- ninguém, e cada cliente que recebe o replay esconde por conta própria).
-- ⚠️ v28-FIX: a primeira versão usava "Enabled" tanto pra BillboardGui
-- quanto pra Decal — só que Decal NÃO TEM a propriedade "Enabled" (só
-- "Transparency"), o que jogava um erro no meio do hideModel (ex:
-- "Workspace.GKBot_Azul.Head.face", a textura do rosto) e travava o
-- personagem já escondido ATÉ ALI como invisível pra sempre, e nem deixava
-- o replay continuar. Agora cada tipo usa a propriedade certa, e tudo isso
-- roda dentro de pcall (ver hideModel/hideRealActorsForReplay abaixo) — um
-- erro num objeto nunca mais trava o resto nem deixa alguém preso invisível.
local hiddenParts = {} -- BasePart -> LocalTransparencyModifier original
local hiddenBillboards = {} -- BillboardGui -> Enabled original
local hiddenDecals = {} -- Decal/Texture -> Transparency original

local function hideInstance(inst)
	if inst:IsA("BasePart") then
		if hiddenParts[inst] == nil then
			hiddenParts[inst] = inst.LocalTransparencyModifier
		end
		inst.LocalTransparencyModifier = 1
	elseif inst:IsA("BillboardGui") then
		if hiddenBillboards[inst] == nil then
			hiddenBillboards[inst] = inst.Enabled
		end
		inst.Enabled = false
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		if hiddenDecals[inst] == nil then
			hiddenDecals[inst] = inst.Transparency
		end
		inst.Transparency = 1
	end
end

local function hideModel(model)
	if not model then return end
	-- v30 FIX: "a bola real também precisa sumir" — GetDescendants() só
	-- pega os FILHOS, nunca o próprio objeto. Pra Model (jogador/bot) tanto
	-- faz (o Model em si não é uma Parte visível), mas a bola é uma Part
	-- SOZINHA — sem esconder ela mesma, só os filhos dela (Attachment,
	-- Sound etc) eram escondidos, e a bola de verdade continuava visível.
	pcall(hideInstance, model)
	for _, inst in ipairs(model:GetDescendants()) do
		-- pcall por instância: se UM objeto der erro (propriedade que não
		-- existe, etc), os outros continuam sendo escondidos normalmente.
		pcall(hideInstance, inst)
	end
end

local function restoreHiddenOriginals()
	for part, value in pairs(hiddenParts) do
		pcall(function()
			if part.Parent then part.LocalTransparencyModifier = value end
		end)
	end
	hiddenParts = {}

	for gui, value in pairs(hiddenBillboards) do
		pcall(function()
			if gui.Parent then gui.Enabled = value end
		end)
	end
	hiddenBillboards = {}

	for decal, value in pairs(hiddenDecals) do
		pcall(function()
			if decal.Parent then decal.Transparency = value end
		end)
	end
	hiddenDecals = {}
end

-- v29: "o clone falhou porque não tem HumanoidRootPart" — a causa mais
-- provável (o jogo já tem outro aviso parecido no GKAreaUtil.lua sobre
-- isso) é Workspace.StreamingEnabled: se um jogador/bot está longe da
-- câmera DESSE cliente no momento do replay, o Character dele pode estar
-- carregado no servidor mas ainda SEM as Parts (incluindo o
-- HumanoidRootPart) aqui localmente — daí "o GKBot perto do gol aparece,
-- mas o jogador que estava longe (ex: quem deu o passe) não aparece".
-- Antes de clonar, pedimos pro servidor carregar essa região pro cliente
-- (RequestStreamAroundAsync) e esperamos até 1.5s por isso — se não vier a
-- tempo, o replay continua sem esse fantasma específico, sem travar nada.
local function ensureRegionStreamedIn(position)
	if not Workspace.StreamingEnabled then return end
	pcall(function()
		Workspace:RequestStreamAroundAsync(position, 1.5)
	end)
end

-- Esconde TODO jogador em campo e TODO bot de goleiro (os dois times, não só
-- quem está na trilha do replay) — o replay inteiro é só fantasma enquanto
-- dura, pra não ter nada "de verdade" competindo com a recriação da jogada.
local function hideRealActorsForReplay()
	hideModel(ball) -- v30: a bola real também precisa sumir (ver comentário no hideModel)
	for _, plr in ipairs(Players:GetPlayers()) do
		hideModel(plr.Character)
	end
	for _, inst in ipairs(Workspace:GetChildren()) do
		if inst:IsA("Model") and inst.Name:sub(1, 6) == "GKBot_" then
			hideModel(inst)
		end
	end
end

-- ===== TRILHAS (posição+direção de UM ator ao longo do tempo) =====

-- Extrai, de uma lista de samples completos, a trilha de UM ator
-- específico (bola / jogador / bot) — só nos instantes em que esse ator
-- de fato existia naquele sample.
local function extractTrack(samples, pick)
	local track = {}
	for _, sample in ipairs(samples) do
		local point = pick(sample)
		if point then
			table.insert(track, { t = sample.t, x = point.x, y = point.y, z = point.z, yaw = point.yaw })
		end
	end
	return track
end

local function findPlayerPoint(sample, uid)
	for _, p in ipairs(sample.players) do
		if p.uid == uid then return p end
	end
	return nil
end

local function findBotPoint(sample, teamName)
	for _, b in ipairs(sample.bots) do
		if b.team == teamName then return b end
	end
	return nil
end

-- Cria uma função que, dado um instante `targetT`, devolve a posição e o
-- yaw interpolados nesse trilho — guarda um "cursor" (index) entre
-- chamadas pra não precisar percorrer a trilha inteira toda vez.
local function makeTrackSampler(track)
	if #track == 0 then return nil end
	local index = 1
	return function(targetT)
		while index < #track - 1 and track[index + 1].t < targetT do
			index += 1
		end
		local a, b = track[index], track[math.min(index + 1, #track)]
		local span = math.max(b.t - a.t, 1e-4)
		local alpha = math.clamp((targetT - a.t) / span, 0, 1)

		local pos = Vector3.new(
			a.x + (b.x - a.x) * alpha,
			a.y + (b.y - a.y) * alpha,
			a.z + (b.z - a.z) * alpha
		)

		-- yaw pelo caminho mais curto (evita girar 350° quando o ângulo
		-- cruza de perto de -180° pra perto de 180°)
		local yawA, yawB = a.yaw or 0, b.yaw or 0
		local diff = (yawB - yawA + math.pi) % (2 * math.pi) - math.pi
		local yaw = yawA + diff * alpha

		return pos, yaw
	end
end

-- ===== ⚠️ v103 — EXTRAS DO REPLAY =====
-- PEDIDO: "algumas animações não saem... a de chutar, nem a da cutscene...
-- é pra aparecer o personagem fazendo a animação em tempo real... os VFX vão
-- sair no replay... o número da vida da bola, se o GK usou a habilidade —
-- tudo o que aconteceu vai ser registrado no replay." O servidor agora manda,
-- junto das posições, os EVENTOS (ações animadas e cutscenes) e, em cada
-- amostra, a vida da bola, a aura de habilidade e as peças de habilidade
-- (guarda do goleiro / bloqueio). Aqui tudo isso é repetido nos fantasmas.

-- número da vida da bola em cima da bola fantasma (mesmo visual do jogo)
local function criarVidaDaBola(ghostBall)
	local gui = Instance.new("BillboardGui")
	gui.Name = "VidaDaBolaReplay"
	gui.Size = UDim2.fromOffset(90, 40)
	gui.StudsOffset = Vector3.new(0, 3, 0)
	gui.AlwaysOnTop = true
	gui.Enabled = false
	gui.Parent = ghostBall
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 220, 60)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	return gui, label
end

-- peças de habilidade (guarda/bloqueio): pool reaproveitado quadro a quadro
local function atualizarVisuais(pool, pasta, lista)
	local n = lista and #lista or 0
	for i = 1, n do
		local v = lista[i]
		local part = pool[i]
		if not part then
			part = Instance.new("Part")
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
			part.Material = Enum.Material.ForceField
			part.Parent = pasta
			pool[i] = part
		end
		part.Shape = v.bola and Enum.PartType.Ball or Enum.PartType.Block
		part.Size = Vector3.new(v.sx, v.sy, v.sz)
		part.CFrame = CFrame.new(table.unpack(v.cf))
		part.Color = Color3.new(v.r, v.g, v.b)
		part.Transparency = v.tr
	end
	for i = n + 1, #pool do
		pool[i].Transparency = 1
	end
end

-- ===== REPLAY =====

local function playReplay(_scoringTeam, samples, eventos)
	if replayInProgress then return end
	if not samples or #samples < 2 then return end

	-- Só usa os últimos GOAL_REPLAY_PLAYBACK_SECONDS do histórico gravado
	-- (o histórico guardado pode ser mais longo — GOAL_REPLAY_DURATION).
	local lastT = samples[#samples].t
	local windowStart = lastT - (Config.GOAL_REPLAY_PLAYBACK_SECONDS or 6)
	local trimmed = {}
	for _, sample in ipairs(samples) do
		if sample.t >= windowStart then
			table.insert(trimmed, sample)
		end
	end
	if #trimmed < 2 then trimmed = samples end -- lance muito curto (ex: gol de saída de meio) — usa o que tiver

	replayInProgress = true
	replayLabel.Visible = true
	pcall(hideRealActorsForReplay) -- nunca deixa um erro aqui travar o replay ou prender alguém invisível

	local ghosts = {} -- lista de Instance pra destruir no final
	local samplers = {} -- lista de { ghost, sample = function(t) -> pos, yaw|nil, isBall }
	-- ⚠️ v103
	local fantasmaDaBola = nil
	local fantasmaDoAtor = {} -- ["P<uid>"/"B<time>"] = Model fantasma
	local emCutscene = {} -- [fantasma] = true enquanto a cutscene move ele (o replay não mexe)
	local auraDoFantasma = {} -- [fantasma] = Highlight

	local ok, err = pcall(function()
		-- ===== BOLA =====
		local ballTrack = extractTrack(trimmed, function(s) return s.ball end)
		local ballSampler = makeTrackSampler(ballTrack)
		if ballSampler then
			local ghostBall = buildGhostBall()
			table.insert(ghosts, ghostBall)
			table.insert(samplers, { ghost = ghostBall, sample = ballSampler, isBall = true })
			fantasmaDaBola = ghostBall
		end

		-- ===== JOGADORES =====
		local playerUids = {}
		for _, sample in ipairs(trimmed) do
			for _, p in ipairs(sample.players) do
				playerUids[p.uid] = true
			end
		end

		for uid in pairs(playerUids) do
			local sourcePlayer = Players:GetPlayerByUserId(uid)
			local track = extractTrack(trimmed, function(s) return findPlayerPoint(s, uid) end)
			local sampler = makeTrackSampler(track)
			if sampler then
				-- v29: pede pro servidor carregar a região onde esse jogador
				-- estava ANTES de tentar clonar (ver ensureRegionStreamedIn).
				local lastPoint = track[#track]
				ensureRegionStreamedIn(Vector3.new(lastPoint.x, lastPoint.y, lastPoint.z))

				local sourceCharacter = sourcePlayer and sourcePlayer.Character
				local ghost, reason = buildGhostFromModel(sourceCharacter, "Player_" .. tostring(uid))
				if ghost then
					table.insert(ghosts, ghost)
					table.insert(samplers, { ghost = ghost, sample = sampler, uid = uid })
					fantasmaDoAtor["P" .. tostring(uid)] = ghost
				else
					-- v28/v29/v30 diagnóstico: pra descobrir por que um jogador
					-- some do replay em vez de ficar adivinhando (ex: "meu
					-- segundo personagem não aparece") — mostra o motivo exato.
					warn(("⚠️ GoalReplayClient: fantasma do jogador '%s' (uid %d) não foi criado — %s"):format(
						sourcePlayer and sourcePlayer.Name or "?",
						uid,
						reason or "?"
					))
				end
			end
		end

		-- ===== BOT(S) DE GOLEIRO =====
		local botTeams = {}
		for _, sample in ipairs(trimmed) do
			for _, b in ipairs(sample.bots) do
				botTeams[b.team] = true
			end
		end

		for teamName in pairs(botTeams) do
			local track = extractTrack(trimmed, function(s) return findBotPoint(s, teamName) end)
			local sampler = makeTrackSampler(track)
			if sampler then
				-- v29: mesma lógica de streaming do loop de jogadores acima.
				local lastPoint = track[#track]
				ensureRegionStreamedIn(Vector3.new(lastPoint.x, lastPoint.y, lastPoint.z))

				-- mesmo nome que o GKBotController.lua usa (workspace.GKBot_<Time>)
				local sourceModel = Workspace:FindFirstChild("GKBot_" .. teamName)
				local ghost, reason = buildGhostFromModel(sourceModel, "Bot_" .. teamName)
				if ghost then
					table.insert(ghosts, ghost)
					table.insert(samplers, { ghost = ghost, sample = sampler })
					fantasmaDoAtor["B" .. teamName] = ghost
				else
					warn(("⚠️ GoalReplayClient: fantasma do bot do time '%s' não foi criado — %s"):format(
						teamName,
						reason or "?"
					))
				end
			end
		end

		-- ===== CÂMERA (segue a bola, igual sempre foi) =====
		local previousCameraType = camera.CameraType
		camera.CameraType = Enum.CameraType.Scriptable

		local totalDuration = trimmed[#trimmed].t - trimmed[1].t
		local playbackStart = os.clock()
		local lastBallPos = nil

		-- ⚠️ v103: eventos, vida da bola e peças de habilidade
		local listaEventos = {}
		if typeof(eventos) == "table" then
			for _, ev in ipairs(eventos) do
				-- cutscene que começou um pouco antes da janela ainda entra (em andamento)
				local folga = (ev.tipo == "Cutscene") and 4 or 0
				if typeof(ev) == "table" and typeof(ev.t) == "number" and ev.t >= trimmed[1].t - folga and ev.t <= lastT then
					table.insert(listaEventos, ev)
				end
			end
			table.sort(listaEventos, function(a, b) return a.t < b.t end)
		end
		local proximoEvento = 1
		local vidaGui, vidaLabel = nil, nil
		if fantasmaDaBola then vidaGui, vidaLabel = criarVidaDaBola(fantasmaDaBola) end
		local pastaVisuais = Instance.new("Folder")
		pastaVisuais.Name = "ReplayVisuais"
		pastaVisuais.Parent = Workspace
		table.insert(ghosts, pastaVisuais)
		local poolVisuais = {}
		local cursorAmostra = 1

		local function dispararEvento(ev, relogio)
			local d = ev.dados
			if typeof(d) ~= "table" then return end
			local fantasma = fantasmaDoAtor[d.ator]
			if not fantasma then return end
			if ev.tipo == "Acao" then
				if _G.AnimadorAcaoLocal and not emCutscene[fantasma] then
					_G.AnimadorAcaoLocal(fantasma, d.chave, d.dur, d.params)
				end
			elseif ev.tipo == "Cutscene" and _G.TocarCutsceneReplay and typeof(d.inicio) == "table" then
				local inicio = CFrame.new(table.unpack(d.inicio))
				local bolaLocal = typeof(d.bola) == "table" and Vector3.new(d.bola[1], d.bola[2], d.bola[3]) or nil
				emCutscene[fantasma] = true
				if fantasmaDaBola then emCutscene[fantasmaDaBola] = true end
				local inicioEv = ev.t
				_G.TocarCutsceneReplay(d.nome, fantasma, fantasmaDaBola, inicio, bolaLocal, d.titulo,
					function() return relogio() - inicioEv end,
					function()
						emCutscene[fantasma] = nil
						if fantasmaDaBola then emCutscene[fantasmaDaBola] = nil end
					end, d.dur)
			end
		end
		-- ⚠️ v20: o yaw só é alinhado UMA vez, no primeiro trecho em que a
		-- bola realmente se move — dali em diante o ângulo é do jogador.
		local yawInitialized = false

		while true do
			local elapsed = os.clock() - playbackStart
			if elapsed >= totalDuration or not replayInProgress then break end

			local targetT = trimmed[1].t + elapsed

			-- ⚠️ v103: eventos que já chegaram na hora deles
			while proximoEvento <= #listaEventos and listaEventos[proximoEvento].t <= targetT do
				local ev = listaEventos[proximoEvento]
				proximoEvento += 1
				pcall(dispararEvento, ev, function() return trimmed[1].t + (os.clock() - playbackStart) end)
			end
			-- amostra "atual" (degrau) pra vida da bola, auras e peças
			while cursorAmostra < #trimmed and trimmed[cursorAmostra + 1].t <= targetT do
				cursorAmostra += 1
			end
			local atual = trimmed[cursorAmostra]
			if vidaGui then
				local f = atual.forca
				vidaGui.Enabled = typeof(f) == "table"
				if typeof(f) == "table" then
					vidaLabel.Text = tostring(f.txt)
					vidaLabel.TextColor3 = Color3.new(f.r or 1, f.g or 0.85, f.b or 0.2)
				end
			end
			pcall(atualizarVisuais, poolVisuais, pastaVisuais, atual.visuais)

			for _, entry in ipairs(samplers) do
				local pos, yaw = entry.sample(targetT)
				-- ⚠️ v103: a cutscene está movendo esse fantasma (ou a bola)
				if emCutscene[entry.ghost] then
					if entry.isBall then pos = entry.ghost.Position else continue end
				end
				-- aura de habilidade do jogador nesse instante
				if entry.uid then
					local ponto = findPlayerPoint(atual, entry.uid)
					local aura = ponto and ponto.aura
					local h = auraDoFantasma[entry.ghost]
					if aura and not h then
						h = Instance.new("Highlight")
						h.Name = "AuraReplay"
						h.FillTransparency = 1
						h.OutlineTransparency = 0
						h.Parent = entry.ghost
						auraDoFantasma[entry.ghost] = h
					end
					if h then
						h.Enabled = aura ~= nil
						if aura then
							h.OutlineColor = Color3.new(aura.r, aura.g, aura.b)
							h.OutlineTransparency = 0.25 + 0.25 * math.sin(os.clock() * 8)
						end
					end
				end

				if entry.isBall then
					-- ⚠️ v20: a câmera virou ÓRBITA presa na bola (ver o bloco
					-- da câmera no topo do arquivo). A posição acompanha a bola
					-- todo frame — ela fica colada, como se fosse parte da bola
					-- — mas o ângulo é 100% do jogador (botão direito gira,
					-- roda do mouse aproxima). Nada aqui mexe no ângulo, que era
					-- o que fazia o ponto de vista pular a cada quique.
					--
					-- Na PRIMEIRA amostra, o yaw inicial é alinhado com a
					-- direção em que a bola está indo, pra o replay começar
					-- olhando de trás dela como antes — depois disso, só o
					-- jogador mexe.
					if lastBallPos and not yawInitialized then
						local direction = pos - lastBallPos
						if direction.Magnitude >= 0.05 then
							replayCamYaw = math.atan2(-direction.X, -direction.Z)
							yawInitialized = true
						end
					end
					lastBallPos = pos

					if not emCutscene[entry.ghost] then entry.ghost.Position = pos end

					local focus = pos + Vector3.new(0, 1, 0)
					local orbit = CFrame.new(focus)
						* CFrame.Angles(0, replayCamYaw, 0)
						* CFrame.Angles(replayCamPitch, 0, 0)
					camera.CFrame = orbit * CFrame.new(0, 0, replayCamDistance)
				elseif entry.ghost:IsA("Model") then
					-- v32 FIX: "estou sempre olhando pra trás" — CFrame.Angles(0, yaw, 0)
					-- de um yaw calculado com atan2(look.X, look.Z) aponta o LookVector
					-- resultante EXATAMENTE 180° invertido do original (é a matemática da
					-- rotação em Y do Roblox vs. a fórmula usada pra extrair o ângulo — as
					-- duas convenções ficam espelhadas). Somando meia-volta (math.pi) aqui
					-- na hora de montar o CFrame corrige sem precisar mexer na gravação.
					-- ⚠️ v19 FIX: era Model:PivotTo, que reposiciona TODAS as
					-- partes do fantasma todo frame — inclusive os membros que a
					-- animação acabou de mover, apagando a pose antes dela
					-- aparecer. Com o rig reconstruído (ver buildGhostFromModel),
					-- basta mover o HumanoidRootPart anchorado: os Motor6D levam
					-- o resto do corpo junto, e a animação fica livre pra mexer
					-- nos membros.
					-- ⚠️ v20: de volta pro PivotTo. Ele move o Model inteiro (é o
					-- que garante que o fantasma ANDE mesmo em rig estranho), e
					-- não atrapalha a animação como eu tinha suposto: com os
					-- Motor6D reconstruídos, o solver de juntas re-posiciona os
					-- membros a partir da animação DEPOIS do PivotTo, todo passo
					-- de física. Quem estava travando o movimento era a falta de
					-- parte anchorada (ver buildGhostFromModel), não o PivotTo.
					entry.ghost:PivotTo(CFrame.new(pos) * CFrame.Angles(0, (yaw or 0) + math.pi, 0))
				else
					entry.ghost.Position = pos
				end
			end

			RunService.RenderStepped:Wait()
		end

		camera.CameraType = previousCameraType ~= Enum.CameraType.Scriptable and previousCameraType or Enum.CameraType.Custom
	end)

	for _, ghost in ipairs(ghosts) do
		if ghost.Parent then ghost:Destroy() end
	end
	restoreHiddenOriginals()

	if not ok then
		warn("⚠️ GoalReplayClient: erro durante o replay — restaurando câmera. Detalhe: " .. tostring(err))
		camera.CameraType = Enum.CameraType.Custom
	end

	replayLabel.Visible = false
	replayInProgress = false

	-- ⚠️ v20: se o replay acabar com o jogador ainda segurando o botão
	-- direito, o mouse ficaria travado no lugar depois que o jogo voltasse.
	replayCamOrbiting = false
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
end

Remotes.GoalReplay.OnClientEvent:Connect(function(scoringTeam, samples, eventos)
	playReplay(scoringTeam, samples, eventos) -- ⚠️ v103: + eventos
end)

print("✅ GoalReplayClient carregado.")
