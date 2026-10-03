--[[
	HissatsuCutsceneClient (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts

	⚠️ v87 — CUTSCENE DE HISSATSU. PEDIDO: "a cutscene é uma animação, só que
	vai aparecer ali a câmera vidrada no personagem. Ninguém vai poder se mexer
	até ficar 100% completa... faça a cutscene do Fire Tornado melhor que você
	puder."

	Toca em TODA tela (o servidor manda Remotes.HissatsuCutscene pra todos),
	sincronizado pelo relógio do servidor. Tudo aqui é VISUAL e LOCAL:
	  - câmera roteirizada (planos com cortes secos, zoom e tremida no impacto);
	  - corpo do chutador: o HumanoidRootPart (ancorado pelo servidor) é movido
	    localmente pelo caminho da coreografia, e cada junta recebe a pose do
	    quadro (Motor6D.C0) — as animações normais ficam paradas enquanto isso;
	  - bola: segue o caminho da coreografia (também ancorada no servidor);
	  - fogo: anel em espiral no chão durante o giro (a imagem de referência),
	    espiral de fogo saindo dos pés no salto (v90) que se junta num rastro só
	    no chute, brasas em volta, bola incandescente (também no voo), e no
	    impacto flash, onda de choque e explosão de faíscas;
	  - tarjas pretas de cinema e o nome da técnica na tela.
	Quem controla as regras (congelar, soltar, disparar o chute) é o servidor
	(PulseController, playHissatsuCutscene). A coreografia é a mesma dos dois
	lados: HissatsuCutscenes.luau.

	Texturas usadas são as de partícula que já vêm com o Roblox
	(rbxasset://textures/particles/...), então não depende de asset nenhum.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Cutscenes = require(ReplicatedStorage:WaitForChild("HissatsuCutscenes"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local TEX_FOGO = "rbxasset://textures/particles/fire_main.dds"
local TEX_FAISCA = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FUMACA = "rbxasset://textures/particles/smoke_main.dds"

-- Fogo puxado pro laranja/vermelho e com LightEmission moderado: com brilho
-- aditivo total, o fogo em cima da grama verde virava amarelo-esverdeado
-- (visto no teste).
local COR_FOGO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 110)),
	ColorSequenceKeypoint.new(0.3, Color3.fromRGB(255, 115, 20)),
	ColorSequenceKeypoint.new(0.7, Color3.fromRGB(215, 45, 5)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 10, 0)),
})
local BRILHO_FOGO = 0.8 -- 1.0 esverdeava na grama; 0.45 ficou escuro/marrom
-- (v90: a ponta saía quase branca e a espiral parecia amarela-clara; o fogo
-- do anime é laranja com miolo amarelo)
local COR_RASTRO = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 215, 110)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 150, 30)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(235, 70, 10)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(140, 15, 0)),
})

local tocando = false

-- ===== peças de efeito =====
local function novaParte(pasta, nome)
	local p = Instance.new("Part")
	p.Name = nome
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Parent = pasta
	return p
end

local function novoRastro(parte, posA, posB, vida, larguraFim)
	local a0 = Instance.new("Attachment")
	a0.Position = posA
	a0.Parent = parte
	local a1 = Instance.new("Attachment")
	a1.Position = posB
	a1.Parent = parte
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = vida
	t.MinLength = 0.02
	t.LightEmission = 1
	t.LightInfluence = 0
	t.FaceCamera = false
	t.Color = COR_RASTRO
	t.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	t.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, larguraFim or 0.15),
	})
	t.Enabled = false
	t.Parent = parte
	return t
end

local function novoFogo(pai, taxa, tamanho, vida, aceleracaoY)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_FOGO
	e.Color = COR_FOGO
	e.LightEmission = BRILHO_FOGO
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, tamanho),
		NumberSequenceKeypoint.new(0.6, tamanho * 0.7),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(vida * 0.6, vida)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(35, 35)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-220, 220)
	e.Acceleration = Vector3.new(0, aceleracaoY or 10, 0)
	e.Drag = 1.5
	e.ZOffset = 0.3
	e.Rate = taxa
	e.Enabled = taxa > 0
	e.Parent = pai
	return e
end

local function novasFaiscas(pai, taxa)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_FAISCA
	e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 20))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Lifetime = NumberRange.new(0.3, 0.7)
	e.Speed = NumberRange.new(8, 18)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Acceleration = Vector3.new(0, -10, 0)
	e.Rate = taxa
	e.Enabled = taxa > 0
	e.Parent = pai
	return e
end

-- ⚠️ v90 — BRASAS. PEDIDO: "coloque algumas partículas de fogo em volta do
-- fogo". Faísquinhas de fogo que se soltam das chamas, sobem devagar e se
-- apagam — o que dá a sensação de calor em volta da espiral.
local function novasBrasas(pai, taxa)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_FOGO
	e.Color = ColorSequence.new(Color3.fromRGB(255, 225, 130), Color3.fromRGB(255, 70, 10))
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(0.5, 1.1)
	e.Speed = NumberRange.new(2, 7)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-300, 300)
	e.Drag = 2.5
	e.Acceleration = Vector3.new(0, 5, 0)
	e.ZOffset = 0.6
	e.Rate = taxa
	e.Enabled = taxa > 0
	e.Parent = pai
	return e
end

-- ⚠️ v90 — a bola sai da cutscene INCANDESCENTE e continua em chamas no voo
-- real até o gol (no anime ela vira uma bola de fogo depois do chute). Tudo
-- local e temporário: se apaga sozinho depois de `duracao` segundos.
local function acenderBolaEmVoo(ball, duracao)
	local a = Instance.new("Attachment")
	a.Name = "HissatsuFogoVoo"
	a.Parent = ball
	local a0 = Instance.new("Attachment")
	a0.Name = "HissatsuFogoVooA"
	a0.Position = Vector3.new(0, -0.9, 0)
	a0.Parent = ball
	local a1 = Instance.new("Attachment")
	a1.Name = "HissatsuFogoVooB"
	a1.Position = Vector3.new(0, 0.9, 0)
	a1.Parent = ball
	-- ⚠️ v91 — PEDIDO: "a bola vai sair pegando fogo na mesma intensidade ou
	-- um pouquinho só mais fraco de quando foi impactada com o pé". Os números
	-- daqui são ~85% dos do impacto (ver o bloco IMPACTO no quadro).
	novoFogo(a, 300, 3.4, 0.5, 2)
	novasFaiscas(a, 55)
	novasBrasas(a, 70)
	local rastro = Instance.new("Trail")
	rastro.Attachment0 = a0
	rastro.Attachment1 = a1
	rastro.Lifetime = 0.5
	rastro.LightEmission = 1
	rastro.LightInfluence = 0
	rastro.FaceCamera = true
	rastro.Color = COR_RASTRO
	rastro.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	rastro.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.8), NumberSequenceKeypoint.new(1, 0.2) })
	rastro.Parent = ball
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 150, 50)
	luz.Range = 22
	luz.Brightness = 5
	luz.Parent = a
	-- incandescente: a própria bola brilha laranja (Highlight não mexe na
	-- física dela, ao contrário de uma peça soldada)
	local brilho = Instance.new("Highlight")
	brilho.Name = "HissatsuIncandescente"
	brilho.Adornee = ball
	brilho.FillColor = Color3.fromRGB(255, 140, 30)
	brilho.FillTransparency = 0.3
	brilho.OutlineColor = Color3.fromRGB(255, 220, 120)
	brilho.OutlineTransparency = 0.2
	brilho.DepthMode = Enum.HighlightDepthMode.Occluded
	brilho.Parent = ball
	task.delay(duracao, function()
		for _, x in ipairs({ a, a0, a1, rastro, brilho }) do
			if x.Parent then x:Destroy() end
		end
	end)
end

-- ===== juntas do rig (R6 ou R15) =====
-- ⚠️ Dois tipos de junta existem hoje no Roblox, e o personagem pode vir com
-- qualquer um (depende do "Avatar Joint Upgrade" da experiência):
--   - Motor6D (o clássico): a pose vai no C0;
--   - AnimationConstraint (o novo, com um BallSocketConstraint do lado): a
--     pose vai no CFrame do Attachment0 — é exatamente o papel do C0 nele.
-- Nos dois casos o Animator NÃO mexe nisso (ele só escreve o Transform),
-- então a pose da cutscene não briga com animação nenhuma. Cada junta vira um
-- par { ler, escrever } pra o resto do código não precisar saber o tipo.
local function juntaDe(j)
	if not j then return nil end
	if j:IsA("Motor6D") then
		-- ⚠️ v106 — "o bot não está socando literalmente, tá meio bugado". A base
		-- da pose era o C0 do INSTANTE em que a cutscene começa — no goleiro bot
		-- o molde tem os ombros POSADOS (braços abertos), e no R6 dos jogadores
		-- o C0 é escrito pelo AnimadorProcedural (pausado no meio de uma pose).
		-- A pose saía torta. Agora a base é o DESCANSO de verdade: posição da
		-- junta (C0Pos do porte físico, ou a do C0) + a rotação do C1 (membro
		-- alinhado com o tronco) — a mesma regra do AnimadorProcedural. E o
		-- Transform que o motor impõe é descontado, igual lá.
		return {
			Ler = function()
				local p = j:GetAttribute("C0Pos") or j.C0.Position
				return CFrame.new(p) * j.C1.Rotation
			end,
			Escrever = function(cf) j.C0 = cf * j.Transform:Inverse() end,
			Vivo = function() return j.Parent ~= nil end,
		}
	elseif j:IsA("AnimationConstraint") and j.Attachment0 then
		local a0 = j.Attachment0
		return {
			Ler = function() return a0.CFrame end,
			-- Mexer SÓ no attachment não basta: com o corpo ancorado, a junta
			-- nova não é recalculada sozinha (medido: o attachment girava 75° e
			-- a perna ficava parada). Escrever o Transform (neutro, já que as
			-- animações estão paradas) é o que força o recálculo naquele quadro.
			Escrever = function(cf)
				a0.CFrame = cf
				j.Transform = CFrame.identity
			end,
			Vivo = function() return a0.Parent ~= nil end,
		}
	end
	return nil
end

local function mapearJuntas(character)
	local function m(pai, nome)
		local p = character:FindFirstChild(pai)
		return juntaDe(p and p:FindFirstChild(nome))
	end
	local r15 = character:FindFirstChild("UpperTorso") ~= nil
	local map = {}
	if r15 then
		map.Root = m("LowerTorso", "Root")
		map.Waist = m("UpperTorso", "Waist")
		map.Neck = m("Head", "Neck")
		map.RShoulder = m("RightUpperArm", "RightShoulder")
		map.LShoulder = m("LeftUpperArm", "LeftShoulder")
		map.RElbow = m("RightLowerArm", "RightElbow")
		map.LElbow = m("LeftLowerArm", "LeftElbow")
		map.RHip = m("RightUpperLeg", "RightHip")
		map.LHip = m("LeftUpperLeg", "LeftHip")
		map.RKnee = m("RightLowerLeg", "RightKnee")
		map.LKnee = m("LeftLowerLeg", "LeftKnee")
	else
		map.Root = m("HumanoidRootPart", "RootJoint")
		map.Neck = m("Torso", "Neck")
		map.RShoulder = m("Torso", "Right Shoulder")
		map.LShoulder = m("Torso", "Left Shoulder")
		map.RHip = m("Torso", "Right Hip")
		map.LHip = m("Torso", "Left Hip")
	end
	return map, r15
end

local function pecaDoPe(character, lado, r15)
	if r15 then
		return character:FindFirstChild(lado .. "Foot"), Vector3.zero
	end
	return character:FindFirstChild(lado .. " Leg"), Vector3.new(0, -0.9, 0)
end

-- ===== interface de cinema =====
-- ⚠️ v100: `tema` (opcional) = cores da técnica (ver Tema em
-- HissatsuCutscenes). Sem tema, fica exatamente como no Tornado de Fogo.
local function criarInterface(titulo, tema)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HissatsuCutsceneGui"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 60
	gui.Parent = playerGui

	local function tarja(y, ancora)
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BorderSizePixel = 0
		f.AnchorPoint = Vector2.new(0, ancora)
		f.Position = UDim2.fromScale(0, y)
		f.Size = UDim2.fromScale(1, 0)
		f.Parent = gui
		return f
	end
	local cima = tarja(0, 0)
	local baixo = tarja(1, 1)
	local info = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(cima, info, { Size = UDim2.fromScale(1, 0.11) }):Play()
	TweenService:Create(baixo, info, { Size = UDim2.fromScale(1, 0.11) }):Play()

	local nome = Instance.new("TextLabel")
	nome.BackgroundTransparency = 1
	nome.AnchorPoint = Vector2.new(0, 0.5)
	nome.Position = UDim2.new(-0.6, 0, 0.8, 0)
	nome.Size = UDim2.fromScale(0.55, 0.1)
	nome.Font = Enum.Font.LuckiestGuy
	nome.Text = titulo
	nome.TextScaled = true
	nome.TextXAlignment = Enum.TextXAlignment.Left
	nome.TextColor3 = Color3.new(1, 1, 1)
	nome.TextTransparency = 1
	nome.Parent = gui
	local grad = Instance.new("UIGradient")
	local c = tema and tema.Titulo
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c and c[1] or Color3.fromRGB(255, 245, 160)),
		ColorSequenceKeypoint.new(0.5, c and c[2] or Color3.fromRGB(255, 150, 30)),
		ColorSequenceKeypoint.new(1, c and c[3] or Color3.fromRGB(230, 40, 10)),
	})
	grad.Rotation = 90
	grad.Parent = nome
	local contorno = Instance.new("UIStroke")
	contorno.Color = tema and tema.Contorno or Color3.fromRGB(70, 8, 0)
	contorno.Thickness = 3
	contorno.Transparency = 1
	contorno.Parent = nome

	local flash = Instance.new("Frame")
	flash.BackgroundColor3 = tema and tema.Flash or Color3.fromRGB(255, 235, 190)
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	flash.ZIndex = 5
	flash.Parent = gui

	-- ⚠️ v93 — LINHAS DE VELOCIDADE (anime, visto no vídeo aos 5.65s): riscos
	-- brancos saindo das bordas em direção ao centro no instante do chute.
	local linhas = Instance.new("Frame")
	linhas.Name = "LinhasDeVelocidade"
	linhas.BackgroundTransparency = 1
	linhas.Size = UDim2.fromScale(1, 1)
	linhas.ZIndex = 4
	linhas.Visible = false
	linhas.Parent = gui
	local listaLinhas = {}
	for i = 1, 36 do
		local ang = (i / 36) * math.pi * 2 + (math.random() - 0.5) * 0.15
		local l = Instance.new("Frame")
		l.BorderSizePixel = 0
		l.BackgroundColor3 = Color3.fromRGB(255, 245, 225)
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		local raio = 0.42 + math.random() * 0.12
		l.Position = UDim2.fromScale(0.5 + math.cos(ang) * raio, 0.5 + math.sin(ang) * raio * 1.6)
		l.Size = UDim2.new(0.18 + math.random() * 0.2, 0, 0, math.random(2, 5))
		l.Rotation = math.deg(ang)
		l.BackgroundTransparency = 1
		l.ZIndex = 4
		l.Parent = linhas
		table.insert(listaLinhas, l)
	end

	return {
		Gui = gui, Cima = cima, Baixo = baixo, Nome = nome, Contorno = contorno, Flash = flash,
		Linhas = linhas, ListaLinhas = listaLinhas,
	}
end

-- ============================================================
-- ⚠️ v100 — MOTOR V2 (as cutscenes das próximas Hissatsus). PEDIDO: "você
-- começa as cutscenes das próximas habilidades".
-- ============================================================
-- O mesmo esqueleto do Tornado (congela, esconde HUD, tarjas, pose por
-- junta, câmera roteirizada, bola colada no pé no chute, impact frame,
-- linhas de velocidade, tremida), só que genérico: os efeitos de cada
-- técnica vêm de HissatsuEfeitos[spec.Efeitos], e a coreografia pode ter
-- pé de chute próprio (KickFoot), bola sumindo (BallVisible) e sombras do
-- chutador (Clones). O caminho do Tornado lá embaixo NÃO foi mexido.
local Efeitos = require(ReplicatedStorage:WaitForChild("HissatsuEfeitos"))

-- Sombra do chutador (Zona Morta): clone do personagem inteiro, sem
-- script/som/física, pintado de energia. Mesmo truque do
-- replay de gol: Archivable liga, clona, volta como estava.
-- ⚠️ v113 (revisão a 0,2s): era material ForceField — em corpo de blocos (R6)
-- ele fica quase invisível e só o cabelo aparecia, flutuando. Agora é uma
-- silhueta roxa escura sólida com contorno de energia (Highlight).
local function criarSombra(character, cor, pasta)
	local antes = character.Archivable
	character.Archivable = true
	local ok, sombra = pcall(function() return character:Clone() end)
	character.Archivable = antes
	if not ok or not sombra then return nil end
	sombra.Name = "HissatsuSombra"
	for _, inst in ipairs(sombra:GetDescendants()) do
		if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("Sound")
			or inst:IsA("Decal") or inst:IsA("Texture") or inst:IsA("Clothing") or inst:IsA("ShirtGraphic")
			or inst:IsA("BillboardGui") or inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Highlight") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.CastShadow = false
			inst.Anchored = inst.Name == "HumanoidRootPart"
			inst.Material = Enum.Material.SmoothPlastic
			inst.Color = cor:Lerp(Color3.new(0, 0, 0), 0.6)
			if inst:IsA("MeshPart") then inst.TextureID = "" end
		elseif inst:IsA("SpecialMesh") then
			inst.TextureId = ""
		elseif inst:IsA("Humanoid") then
			inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			inst.EvaluateStateMachine = false
		end
	end
	local contorno = Instance.new("Highlight")
	contorno.FillColor = cor
	contorno.FillTransparency = 0.55
	contorno.OutlineColor = cor:Lerp(Color3.new(1, 1, 1), 0.55)
	contorno.OutlineTransparency = 0
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Parent = sombra
	sombra.Parent = pasta
	return sombra
end

-- ⚠️ v108 — ZONA MORTA DE TRÊS. Referência (Inazuma Eleven Wiki, Death Zone):
-- "os três sobem girando e formam um triângulo no ar com a bola no meio... é
-- crucial que os 3 sincronizem". A técnica agora exige 2 companheiros de
-- verdade, então os vértices do triângulo deixam de ser sombras roxas do
-- chutador: são CÓPIAS dos companheiros (roupa, cor, rosto), com contorno roxo
-- de energia. Os corpos reais deles somem durante a cena (estão no triângulo).
local companheirosDaCutscene = nil -- lista de Players, só durante o início de uma cutscene

-- ⚠️ v119: `estilo` (opcional) = { Fill, Outline, OutlineTransp } — o Rin do Flow do Isagi
-- é um companheiro de verdade sem o contorno roxo da Zona Morta
local function criarCompanheiro(mateChar, cor, pasta, estilo)
	local antes = mateChar.Archivable
	mateChar.Archivable = true
	local ok, copia = pcall(function() return mateChar:Clone() end)
	mateChar.Archivable = antes
	if not ok or not copia then return nil end
	copia.Name = "HissatsuCompanheiro"
	for _, inst in ipairs(copia:GetDescendants()) do
		if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("Sound") or inst:IsA("BillboardGui")
			or inst:IsA("ParticleEmitter") or inst:IsA("Trail") or inst:IsA("Highlight") then
			inst:Destroy()
		elseif inst:IsA("BasePart") then
			inst.CanCollide = false
			inst.CanQuery = false
			inst.CanTouch = false
			inst.Anchored = inst.Name == "HumanoidRootPart"
		elseif inst:IsA("Humanoid") then
			inst.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			inst.EvaluateStateMachine = false
		end
	end
	local contorno = Instance.new("Highlight")
	contorno.FillColor = cor
	contorno.FillTransparency = estilo and estilo.Fill or 0.85
	contorno.OutlineColor = estilo and estilo.Outline or Color3.fromRGB(200, 140, 255)
	contorno.OutlineTransparency = estilo and estilo.OutlineTransp or 0.05
	contorno.Parent = copia
	copia.Parent = pasta
	-- o corpo real some enquanto a cena roda (a cópia está no triângulo)
	local escondidas = {}
	for _, p in ipairs(mateChar:GetDescendants()) do
		if p:IsA("BasePart") and p.LocalTransparencyModifier < 1 then
			p.LocalTransparencyModifier = 1
			table.insert(escondidas, p)
		end
	end
	copia.Destroying:Connect(function()
		for _, p in ipairs(escondidas) do
			if p.Parent then p.LocalTransparencyModifier = 0 end
		end
	end)
	return copia
end

local contadorReplay = 0
-- ⚠️ v103: o protagonista pode ser um Player ou um Model (goleiro bot, na
-- cutscene de defesa)
local function corpoDe(quem)
	if typeof(quem) ~= "Instance" then return nil end
	if quem:IsA("Player") then return quem.Character end
	if quem:IsA("Model") then return quem end
	return nil
end
local function tocarCutsceneV2(spec, chutador, inicio, bolaLocal, horarioServidor, titulo, opts)
	-- ⚠️ v103: opts = modo REPLAY (fantasma do replay de gol): sem câmera, sem
	-- HUD, sem correção de cor — só o corpo, a bola e os efeitos.
	local replay = opts ~= nil
	local nomeBind = "HissatsuCutscene"
	if replay then
		contadorReplay += 1
		nomeBind = "HissatsuCutsceneReplay" .. contadorReplay
	end
	local character = (opts and opts.Modelo) or corpoDe(chutador)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	local ball = (opts and opts.Bola) or workspace:FindFirstChild(Config.BALL_NAME)
	if typeof(inicio) ~= "CFrame" then return end
	if typeof(bolaLocal) ~= "Vector3" then bolaLocal = nil end
	local criarEfeitos = Efeitos[spec.Efeitos or ""]

	if not replay then
		tocando = true
		_G.HissatsuCutsceneLocal = true
	end
	_G.AnimadorPausado = _G.AnimadorPausado or {}
	_G.AnimadorPausado[character] = true

	local camera = workspace.CurrentCamera
	local fovOriginal = camera.FieldOfView
	local animator = humanoid:FindFirstChildOfClass("Animator")
	local tema = spec.Tema or {}

	local juntas, r15 = mapearJuntas(character)
	local c0Original = {}
	for _, junta in pairs(juntas) do
		c0Original[junta] = junta.Ler()
	end

	local guisEscondidas, jaEscondida = {}, {}
	local ui
	local function esconderHud()
		if replay then return end -- ⚠️ v103: no replay o HUD fica como está
		for _, g in ipairs(playerGui:GetDescendants()) do
			if g:IsA("LayerCollector") and g.Enabled and (not ui or g ~= ui.Gui)
				and not g:GetAttribute("VisivelNaCutscene") then
				g.Enabled = false
				if not jaEscondida[g] then
					jaEscondida[g] = true
					table.insert(guisEscondidas, g)
				end
			end
		end
	end
	esconderHud()
	ui = criarInterface(titulo or spec.TitleText or "", spec.Tema)
	if replay then ui.Gui.Enabled = false end

	local correcao = Instance.new("ColorCorrectionEffect")
	correcao.Name = "HissatsuCutsceneColor"
	correcao.TintColor = tema.Tint or Color3.new(1, 1, 1)
	correcao.Saturation = tema.Saturation or 0.2
	correcao.Contrast = tema.Contrast or 0.12
	correcao.Brightness = tema.Brightness or 0
	correcao.Parent = (not replay) and Lighting or nil
	local brilhoBase, contrasteBase = correcao.Brightness, correcao.Contrast

	local pasta = Instance.new("Folder")
	pasta.Name = "HissatsuCutsceneFX"
	pasta.Parent = workspace

	local function mundo(p) return inicio:PointToWorldSpace(p) end
	local pe, deslPe = pecaDoPe(character, spec.KickFoot or "Right", r15)

	-- ⚠️ v100: mede o gramado de verdade debaixo do chutador (o quadril de
	-- cada avatar fica numa altura diferente — medido 3.47 no de teste, a
	-- coreografia supunha 2.9) e calibra tudo que apoia no chão
	local chaoY = -2.9
	do
		local filtro = RaycastParams.new()
		local ignorar = { pasta }
		for _, pl in ipairs(Players:GetPlayers()) do
			if pl.Character then table.insert(ignorar, pl.Character) end
		end
		if ball then table.insert(ignorar, ball) end
		if opts and opts.Modelo then table.insert(ignorar, opts.Modelo) end
		filtro.FilterDescendantsInstances = ignorar
		filtro.FilterType = Enum.RaycastFilterType.Exclude
		local hit = workspace:Raycast(inicio.Position + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), filtro)
		if hit then chaoY = inicio:PointToObjectSpace(hit.Position).Y end
	end
	if Cutscenes.Calibrar then
		Cutscenes.Calibrar(chaoY, ball and ball.Size.X / 2 or 0.85)
	end

	-- sombras (Zona Morta)
	local sombras = {}
	if spec.Clones then
		for i = 1, spec.Clones.Quantidade or 0 do
			-- ⚠️ v108: companheiro de verdade quando o servidor mandou (Zona Morta de três)
			local mate = (not replay) and companheirosDaCutscene and companheirosDaCutscene[i]
			-- ⚠️ v120b: pode vir um Model (goleiro bot) quando não há outro jogador
			local mateChar = nil
			if typeof(mate) == "Instance" then
				if mate:IsA("Player") then
					mateChar = mate.Character
				elseif mate:IsA("Model") and mate:FindFirstChild("HumanoidRootPart") then
					mateChar = mate
				end
			end
			local real = false
			local modelo
			if mateChar then
				modelo = criarCompanheiro(mateChar, spec.Clones.Cor or Color3.fromRGB(120, 40, 200), pasta, spec.Clones.Contorno)
				real = modelo ~= nil
			end
			modelo = modelo or criarSombra(character, spec.Clones.Cor or Color3.fromRGB(120, 40, 200), pasta)
			if modelo then
				local sRoot = modelo:FindFirstChild("HumanoidRootPart")
				local sJuntas = mapearJuntas(modelo)
				local sOriginal = {}
				for _, j in pairs(sJuntas) do sOriginal[j] = j.Ler() end
				local partes = {}
				for _, p in ipairs(modelo:GetDescendants()) do
					if p:IsA("BasePart") and p ~= sRoot then table.insert(partes, p) end
				end
				local transpOriginal = {}
				for _, p in ipairs(partes) do transpOriginal[p] = p.Transparency end
				sombras[i] = { Modelo = modelo, Root = sRoot, Juntas = sJuntas, Original = sOriginal, Partes = partes, Real = real, TranspOriginal = transpOriginal }
			end
		end
	end

	-- tremida extra pedida pelos efeitos (ex.: o raio caindo)
	local tremidaExtra, tremidaFim = 0, 0
	local tAtual = 0
	local ctx = {
		Spec = spec, Pasta = pasta, Inicio = inicio, Mundo = mundo,
		Character = character, Root = root, Ball = ball,
		TamanhoBola = ball and ball.Size.X or 1.7,
		ChaoY = chaoY, -- altura (local) do gramado
		BolaInicial = bolaLocal,
		DirecaoChute = inicio:VectorToWorldSpace(Vector3.new(0, -0.2, -1).Unit),
		Clones = sombras,
		Flash = function(cor, transp, tempo)
			ui.Flash.BackgroundColor3 = cor
			ui.Flash.BackgroundTransparency = transp
			TweenService:Create(ui.Flash, TweenInfo.new(tempo), { BackgroundTransparency = 1 }):Play()
		end,
		Tremer = function(forca, duracao)
			tremidaExtra = forca
			tremidaFim = tAtual + duracao
		end,
	}
	local efeitos = nil
	if criarEfeitos then
		local okEf, resultado = pcall(criarEfeitos, ctx)
		if okEf then
			efeitos = resultado
		else
			warn("[Cutscene V2] efeitos de " .. tostring(spec.Efeitos) .. " falharam (segue sem eles): " .. tostring(resultado))
		end
	end

	local impactoFeito = false
	local tituloMostrado, tituloEscondido = false, false
	local giroBola = 0
	local ultimoT = 0
	local colaNoChute = nil -- (v125) deslocamento da bola congelado no instante do chute
	local conexao

	-- ⚠️ v113: a bola tem os gomos em DECALS e um Highlight; esconder só a
	-- peça deixava os pentágonos pretos flutuando (visto no Flow do Rin)
	local enfeitesBola = {}
	if ball then
		for _, d in ipairs(ball:GetDescendants()) do
			if d:IsA("Decal") or d:IsA("Highlight") or d:IsA("Trail") or d:IsA("BillboardGui") then
				table.insert(enfeitesBola, d)
			end
		end
	end
	local enfeitesEscondidos = false
	local function esconderEnfeitesDaBola(esconder)
		if esconder == enfeitesEscondidos then return end
		enfeitesEscondidos = esconder
		for _, d in ipairs(enfeitesBola) do
			if d.Parent then
				if d:IsA("Decal") then
					d.LocalTransparencyModifier = esconder and 1 or 0
				elseif esconder then
					d:SetAttribute("CenaEstavaLigado", d.Enabled)
					d.Enabled = false
				elseif d:GetAttribute("CenaEstavaLigado") ~= nil then
					d.Enabled = d:GetAttribute("CenaEstavaLigado")
					d:SetAttribute("CenaEstavaLigado", nil)
				end
			end
		end
	end

	local function escreverPose(mapa, originais, pose)
		for nome, junta in pairs(mapa) do
			local ang = pose[nome]
			if ang then
				local rx, ry, rz = ang[1], ang[2], ang[3]
				if not r15 and nome == "Root" and pose.Waist then
					rx += pose.Waist[1]
					ry += pose.Waist[2]
					rz += pose.Waist[3]
				end
				local original = originais[junta]
				junta.Escrever(CFrame.new(original.Position)
					* CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
					* original.Rotation)
			end
		end
	end

	local function limpar()
		RunService:UnbindFromRenderStep(nomeBind)
		if conexao then conexao:Disconnect() end
		for junta, c0 in pairs(c0Original) do
			if junta.Vivo() then junta.Escrever(c0) end
		end
		-- ⚠️ v120b: o último quadro da coreografia costuma ser agachado (quadril abaixo
		-- da altura de pé) — deixar o corpo ali enterrava as pernas no gramado e
		-- bugava/derrubava no void ("depois da Fúria Glacial"). Termina sempre de pé.
		if not replay and root.Parent and spec.RootPosition then
			local okFim, fim = pcall(spec.RootPosition, spec.Duration)
			if okFim and typeof(fim) == "Vector3" and fim.Y < 0 then
				root.CFrame = inicio * CFrame.new(fim.X, 0, fim.Z) * (inicio:Inverse() * root.CFrame).Rotation
			end
		end
		pasta:Destroy()
		if ball and ball.Parent then
			ball.LocalTransparencyModifier = 0
			esconderEnfeitesDaBola(false)
			if impactoFeito and efeitos and efeitos.Voo then
				pcall(efeitos.Voo, ball, 3)
			end
		end
		correcao:Destroy()
		ui.Gui:Destroy()
		if _G.AnimadorPausado then _G.AnimadorPausado[character] = nil end
		if replay then
			-- ⚠️ v103: no replay não mexe em câmera/HUD do jogador
			if opts.AoTerminar then pcall(opts.AoTerminar) end
			return
		end
		for _, g in ipairs(guisEscondidas) do
			if g.Parent then g.Enabled = true end
		end
		camera.FieldOfView = fovOriginal
		camera.CameraType = Enum.CameraType.Custom
		local meuHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if meuHumanoid then camera.CameraSubject = meuHumanoid end
		_G.HissatsuCutsceneLocal = nil
		tocando = false
	end

	local function quadro()
		local t = replay and opts.Tempo() or (workspace:GetServerTimeNow() - horarioServidor)
		local lento = player:GetAttribute("CutsceneDebugSlow")
		if typeof(lento) == "number" and lento > 0 then t *= lento end
		local tFixo = player:GetAttribute("CutsceneDebugT")
		if typeof(tFixo) == "number" then
			t = math.clamp(tFixo, 0, spec.Duration - 0.001)
		elseif player:GetAttribute("CutsceneDebugStop") then
			t = spec.Duration
		end
		local dt = math.clamp(t - ultimoT, 0, 0.1)
		ultimoT = t
		if t >= spec.Duration or not root.Parent then
			limpar()
			return
		end
		t = math.max(t, 0)
		tAtual = t

		esconderHud()
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
		end

		-- corpo
		local rootLocal = spec.RootPosition(t)
		root.CFrame = inicio * spec.RootCFrame(t)
		escreverPose(juntas, c0Original, spec.Pose(t))

		-- sombras
		for i, s in pairs(sombras) do
			if s.Modelo.Parent and s.Root then
				s.Root.CFrame = inicio * spec.Clones.CFrame(i, t)
				escreverPose(s.Juntas, s.Original, spec.Clones.Pose(i, t))
				local alfa = spec.Clones.Alpha and spec.Clones.Alpha(i, t) or 1
				for _, p in ipairs(s.Partes) do
					if s.Real then
						-- companheiro de verdade: opaco (respeita o que já era transparente)
						local base = s.TranspOriginal[p] or 0
						p.Transparency = base + (1 - base) * (1 - alfa)
					else
						p.Transparency = 1 - alfa * 0.85
					end
				end
			end
		end

		-- bola (colada no pé de chute na chegada do chute)
		local bolaPosLocal = spec.BallPosition(t, bolaLocal)
		local bolaMundo = mundo(bolaPosLocal)
		local pePos = pe and pe.CFrame:PointToWorldSpace(deslPe) or root.Position
		-- (desloca o caminho inteiro pela diferença entre onde a bola estaria
		-- no instante do chute e o contato com o pé de verdade; a Zona Morta
		-- desliga isso — a bola fica no meio dos três pés)
		if pe and spec.KickContactDir and spec.ColarNoPe ~= false and t >= spec.Phases.Kick[1] - 0.15 then
			local raioBola = ball and ball.Size.X / 2 or 0.85
			local contato = pePos + inicio:VectorToWorldSpace(spec.KickContactDir) * (raioBola + 0.3)
			local cola = Cutscenes.Smooth(Cutscenes.Phase(t, spec.Phases.Kick[1] - 0.15, spec.ImpactTime))
			local noChute = mundo(spec.BallPosition(spec.ImpactTime, bolaLocal))
			local desloc = (contato - noChute) * cola
			-- ⚠️ v125: com ColaCongelaNoChute, depois do chute a bola NÃO segue mais o pé
			-- (no Big Bang Drive ele cai de costas e a bola afundava no gramado junto)
			if spec.ColaCongelaNoChute then
				if t >= spec.ImpactTime then
					colaNoChute = colaNoChute or desloc
					desloc = colaNoChute
				else
					colaNoChute = nil -- (o depurador pode voltar no tempo)
				end
			end
			bolaMundo += desloc
			bolaPosLocal = inicio:PointToObjectSpace(bolaMundo)
		end
		giroBola += (spec.BallSpin and spec.BallSpin(t) or 10) * math.pi * 2 * dt
		local bolaVisivel = not spec.BallVisible or spec.BallVisible(t)
		if ball then
			ball.CFrame = CFrame.new(bolaMundo) * CFrame.Angles(giroBola, giroBola * 0.6, 0)
			ball.LocalTransparencyModifier = bolaVisivel and 0 or 1
			esconderEnfeitesDaBola(not bolaVisivel)
		end

		-- título
		if not tituloMostrado and t >= 0.35 then
			tituloMostrado = true
			TweenService:Create(ui.Nome, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.05, 0, 0.8, 0), TextTransparency = 0 }):Play()
			TweenService:Create(ui.Contorno, TweenInfo.new(0.3), { Transparency = 0 }):Play()
		elseif tituloMostrado and not tituloEscondido and t >= 1.5 then
			tituloEscondido = true
			TweenService:Create(ui.Nome, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			TweenService:Create(ui.Contorno, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end

		local estado = {
			T = t, RootLocal = rootLocal, BolaMundo = bolaMundo, BolaLocal = bolaPosLocal,
			BolaVisivel = bolaVisivel, ImpactoFeito = impactoFeito, PePos = pePos,
		}

		-- impacto: o que é igual pra toda técnica (flash, impact frame,
		-- linhas de velocidade) + o próprio de cada uma
		if not impactoFeito and t >= spec.ImpactTime then
			impactoFeito = true
			estado.ImpactoFeito = true
			ui.Flash.BackgroundColor3 = tema.Flash or Color3.fromRGB(255, 235, 190)
			ui.Flash.BackgroundTransparency = 0.15
			TweenService:Create(ui.Flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			correcao.Brightness = brilhoBase + 0.35
			correcao.Contrast = 0.7
			task.delay(0.07, function()
				if correcao.Parent then
					correcao.Contrast = contrasteBase
					TweenService:Create(correcao, TweenInfo.new(0.3), { Brightness = brilhoBase }):Play()
				end
			end)
			ui.Linhas.Visible = true
			for _, l in ipairs(ui.ListaLinhas) do
				l.BackgroundTransparency = 0.1 + math.random() * 0.3
				TweenService:Create(l, TweenInfo.new(0.35 + math.random() * 0.15), { BackgroundTransparency = 1 }):Play()
			end
			if efeitos and efeitos.Impacto then efeitos.Impacto(estado) end
		end
		if efeitos and efeitos.Quadro then efeitos.Quadro(t, dt, estado) end

		-- câmera
		local camLocal, alvoLocal, fov = spec.Camera(t, rootLocal, bolaPosLocal)
		local forca = 0
		if t >= spec.ImpactTime and not spec.SemTremidaImpacto then
			forca = 0.7 * (1 - Cutscenes.Phase(t, spec.ImpactTime, spec.Duration))
		end
		if t < tremidaFim then
			forca = math.max(forca, tremidaExtra * (tremidaFim - t) / 0.3)
		end
		local tremida = Vector3.zero
		if forca > 0 then
			tremida = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * forca
		end
		if not replay then
			camera.CameraType = Enum.CameraType.Scriptable
			-- ⚠️ v119: os efeitos podem mandar a câmera em coordenadas de MUNDO (closes que
			-- seguem a cabeça/olho/mão de verdade de qualquer avatar — Flow do Isagi)
			local camMundo, fovMundo = nil, nil
			if efeitos and efeitos.CameraMundo then
				local okCam, c1, f1 = pcall(efeitos.CameraMundo, t, mundo(camLocal), mundo(alvoLocal), fov)
				if okCam and typeof(c1) == "CFrame" then camMundo, fovMundo = c1, f1 end
			end
			if camMundo then
				camera.CFrame = camMundo + tremida
				camera.FieldOfView = fovMundo or fov
			else
				camera.CFrame = CFrame.lookAt(mundo(camLocal) + tremida, mundo(alvoLocal))
				camera.FieldOfView = fov
			end
		end
	end

	local function passo()
		local ok, err = pcall(quadro)
		if not ok then
			warn("[Cutscene V2] erro no quadro, encerrando: " .. tostring(err))
			pcall(limpar)
		end
	end
	-- Ferramenta de teste: com o atributo "CutsceneDebugHeartbeat" no
	-- LocalPlayer a cutscene roda no Heartbeat (RenderStepped não roda com a
	-- tela do PC bloqueada — é assim que dá pra testar sem ninguém olhando).
	if player:GetAttribute("CutsceneDebugHeartbeat") then
		conexao = RunService.Heartbeat:Connect(passo)
	else
		RunService:BindToRenderStep(nomeBind, Enum.RenderPriority.Camera.Value + 2, passo)
	end
end

-- ===== a cutscene =====
local function tocarCutscene(nomeCutscene, chutador, inicio, bolaLocal, horarioServidor, titulo, opts)
	local spec = Cutscenes[nomeCutscene]
	if not spec then return end
	local replay = opts ~= nil -- ⚠️ v103: modo REPLAY (ver tocarCutsceneV2)
	if tocando and not replay then return end -- o servidor garante uma por vez; isto é só defesa
	if spec.Motor == "V2" then
		return tocarCutsceneV2(spec, chutador, inicio, bolaLocal, horarioServidor, titulo, opts)
	end
	local nomeBind = "HissatsuCutscene"
	if replay then
		contadorReplay += 1
		nomeBind = "HissatsuCutsceneReplay" .. contadorReplay
	end

	local character = (opts and opts.Modelo) or corpoDe(chutador)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then return end
	local ball = (opts and opts.Bola) or workspace:FindFirstChild(Config.BALL_NAME)
	if typeof(inicio) ~= "CFrame" then return end
	if typeof(bolaLocal) ~= "Vector3" then bolaLocal = nil end

	if not replay then
		tocando = true
		_G.HissatsuCutsceneLocal = true -- FootballClient para de girar o corpo pelo Shift Lock enquanto isso
	end
	-- ⚠️ v96: o AnimadorProcedural para de animar o chutador enquanto a
	-- cutscene escreve a pose dele
	_G.AnimadorPausado = _G.AnimadorPausado or {}
	_G.AnimadorPausado[character] = true

	local camera = workspace.CurrentCamera
	local fovOriginal = camera.FieldOfView
	local animator = humanoid:FindFirstChildOfClass("Animator")

	-- juntas e poses originais
	local juntas, r15 = mapearJuntas(character)
	local c0Original = {}
	for _, junta in pairs(juntas) do
		c0Original[junta] = junta.Ler()
	end

	-- esconde o HUD normal (as guis que estavam ligadas voltam no fim)
	-- Roda todo quadro: gui que outro script religar (ou criar) no meio da
	-- cutscene também some. Procura em todo o PlayerGui, não só nos filhos
	-- diretos — tem HUD guardado dentro de pastas.
	local guisEscondidas = {}
	local jaEscondida = {}
	local ui
	local function esconderHud()
		if replay then return end -- ⚠️ v103: no replay o HUD fica como está
		for _, g in ipairs(playerGui:GetDescendants()) do
			-- ⚠️ v95: a janela do QTE fica (ele acontece DURANTE a cutscene)
			if g:IsA("LayerCollector") and g.Enabled and (not ui or g ~= ui.Gui)
				and not g:GetAttribute("VisivelNaCutscene") then
				g.Enabled = false
				if not jaEscondida[g] then
					jaEscondida[g] = true
					table.insert(guisEscondidas, g)
				end
			end
		end
	end
	esconderHud()
	ui = criarInterface(titulo or spec.TitleText or "")
	if replay then ui.Gui.Enabled = false end

	-- cor de cena: mais quente e saturada
	local correcao = Instance.new("ColorCorrectionEffect")
	correcao.Name = "HissatsuCutsceneColor"
	correcao.TintColor = Color3.fromRGB(255, 228, 205)
	correcao.Saturation = 0.25
	correcao.Contrast = 0.12
	correcao.Parent = (not replay) and Lighting or nil

	-- ===== efeitos =====
	local pasta = Instance.new("Folder")
	pasta.Name = "HissatsuCutsceneFX"
	pasta.Parent = workspace

	-- anel de fogo no chão (dois arcos em espiral, como na referência)
	local anel = {}
	for i = 1, 2 do
		local p = novaParte(pasta, "AnelFogo" .. i)
		local rastro = novoRastro(p, Vector3.new(-0.7, 0, 0), Vector3.new(0.7, 0, 0), 0.28, 0.05)
		local fogo = novoFogo(p, 0, 1.6, 0.35, 6)
		anel[i] = { Parte = p, Rastro = rastro, Fogo = fogo }
	end

	-- ⚠️ v91 — ESPIRAL EM VOLTA DO CORPO. PEDIDO: "sobre a espiral sair dos
	-- pés, pode tirar isso aí... pode voltar pra espiral aparecer em volta do
	-- corpo e ir acompanhando em volta, que fica melhor... o rastro pode durar
	-- um pouco mais de tempo, tá acabando muito cedo enquanto você gira, pode
	-- ficar um pouquinho maior". As fitas orbitam o corpo (no mesmo sentido do
	-- giro dele) subindo em espiral, agora com rastro mais longo e mais largo.
	-- Continua valendo o do v90: na hora do chute elas convergem pro pé
	-- esquerdo e viram UM rastro só, que acompanha a perna até a bola.
	local peE, deslE = pecaDoPe(character, "Left", r15)
	local coxaE = r15 and character:FindFirstChild("LeftUpperLeg") or character:FindFirstChild("Left Leg")
	-- ⚠️ v92 — PEDIDO: "intensifica mais um pouco a espiral e faz ela girar
	-- junto com o corpo... a origem dela não é no pé, é dessa forma que tá
	-- agora, só que ela vai girar junto com o corpo do personagem". 6 fitas
	-- (eram 4), mais largas, mais fogo e mais brasas; e a órbita agora é no
	-- REFERENCIAL DO CORPO (ver o quadro): gira e tomba junto com ele.
	-- ⚠️ v93 — PEDIDO: "faz a espiral ser mais grossa, ela é muito fina
	-- atualmente, vfx profissional". Cada fita agora tem DUAS camadas de
	-- rastro, como VFX de anime em jogo:
	--   • halo: largo, laranja-avermelhado, meio transparente — o corpo da
	--     chama;
	--   • miolo: mais estreito, amarelo quase branco — o brilho de dentro.
	-- As duas com textura de chama esticada ao longo do rastro e sempre de
	-- frente pra câmera (antes a fita era plana: vista de lado virava uma
	-- linha fina — era isso que deixava a espiral "muito fina").
	local COR_HALO = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 40)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(235, 70, 15)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(130, 15, 0)),
	})
	local COR_MIOLO = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 215)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 210, 90)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 110, 20)),
	})
	local function camadaDeRastro(parte, largura, cor, transpInicial, brilho)
		local r = novoRastro(parte, Vector3.new(0, -largura, 0), Vector3.new(0, largura, 0), 0.65, 0.25)
		r.FaceCamera = true
		r.Color = cor
		r.LightEmission = brilho
		r.Texture = TEX_FOGO
		r.TextureMode = Enum.TextureMode.Stretch
		r.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, transpInicial),
			NumberSequenceKeypoint.new(0.6, 0.35 + transpInicial * 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		return r
	end

	local QTD_FITAS = 6
	local espiral = {}
	for i = 1, QTD_FITAS do
		local p = novaParte(pasta, "Espiral" .. i)
		local halo = camadaDeRastro(p, 3.2, COR_HALO, 0.25, 0.85)
		local miolo = camadaDeRastro(p, 1.2, COR_MIOLO, 0, 1)
		local fogo = novoFogo(p, 0, 3.2, 0.5, 10)
		local brasas = novasBrasas(p, 0)
		espiral[i] = {
			Parte = p, Rastro = halo, Miolo = miolo, Fogo = fogo, Brasas = brasas,
			Fase = (i - 1) / QTD_FITAS, Largura = 3.2, LarguraMiolo = 1.2,
		}
	end

	-- brasas soltas em volta do corpo inteiro enquanto ele sobe
	local nuvemBrasas = novaParte(pasta, "NuvemBrasas")
	nuvemBrasas.Size = Vector3.new(9, 9, 9)
	local nuvemEmissor = novasBrasas(nuvemBrasas, 0)
	nuvemEmissor.Shape = Enum.ParticleEmitterShape.Box
	nuvemEmissor.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume

	-- coluna de fogo que sobe junto com ele
	local coluna = novaParte(pasta, "ColunaFogo")
	coluna.Size = Vector3.new(6, 1, 6)
	local colunaFogo = novoFogo(coluna, 0, 3, 0.6, 28)
	colunaFogo.Shape = Enum.ParticleEmitterShape.Cylinder
	colunaFogo.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	colunaFogo.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface

	-- fumaça no chão na decolagem
	local poeira = novaParte(pasta, "Poeira")
	local poeiraEmissor = Instance.new("ParticleEmitter")
	poeiraEmissor.Texture = TEX_FUMACA
	poeiraEmissor.Color = ColorSequence.new(Color3.fromRGB(120, 90, 70))
	poeiraEmissor.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	poeiraEmissor.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	poeiraEmissor.Lifetime = NumberRange.new(0.6, 1)
	poeiraEmissor.Speed = NumberRange.new(10, 16)
	poeiraEmissor.SpreadAngle = Vector2.new(5, 180)
	poeiraEmissor.EmissionDirection = Enum.NormalId.Right
	poeiraEmissor.Drag = 4
	poeiraEmissor.Rate = 0
	poeiraEmissor.Enabled = false
	poeiraEmissor.Parent = poeira

	-- luz que acompanha o corpo
	local luzCorpo = novaParte(pasta, "LuzCorpo")
	local luz = Instance.new("PointLight")
	luz.Color = Color3.fromRGB(255, 140, 40)
	luz.Range = 0
	luz.Brightness = 3
	luz.Shadows = false
	luz.Parent = luzCorpo

	-- bola em chamas
	local bolaFx = novaParte(pasta, "BolaFogo")
	local bolaFogo = novoFogo(bolaFx, 0, 2.4, 0.45, 6)
	local bolaFaiscas = novasFaiscas(bolaFx, 0)
	local bolaLuz = Instance.new("PointLight")
	bolaLuz.Color = Color3.fromRGB(255, 150, 50)
	bolaLuz.Range = 0
	bolaLuz.Brightness = 4
	bolaLuz.Parent = bolaFx
	local bolaRastro = novoRastro(bolaFx, Vector3.new(0, -0.9, 0), Vector3.new(0, 0.9, 0), 0.3, 0.1)
	bolaRastro.FaceCamera = true

	-- núcleo incandescente da bola: uma esfera neon por fora dela que acende
	-- quando a espiral se junta no pé e a bola "pega fogo de verdade"
	local nucleo = Instance.new("Part")
	nucleo.Name = "BolaIncandescente"
	nucleo.Shape = Enum.PartType.Ball
	nucleo.Material = Enum.Material.Neon
	nucleo.Color = Color3.fromRGB(255, 150, 40)
	nucleo.Anchored = true
	nucleo.CanCollide = false
	nucleo.CanQuery = false
	nucleo.CanTouch = false
	nucleo.CastShadow = false
	nucleo.Transparency = 1
	local tamanhoBola = ball and ball.Size.X or 2
	nucleo.Size = Vector3.one * tamanhoBola * 1.3
	nucleo.Parent = pasta

	-- impacto
	local impacto = novaParte(pasta, "Impacto")
	local impactoFogo = novoFogo(impacto, 0, 4, 0.5, 4)
	impactoFogo.Speed = NumberRange.new(18, 30)
	impactoFogo.SpreadAngle = Vector2.new(180, 180)
	local impactoFaiscas = novasFaiscas(impacto, 0)
	impactoFaiscas.Speed = NumberRange.new(25, 45)
	local ondas = {}
	for i = 1, 2 do
		local onda = Instance.new("Part")
		onda.Name = "OndaChoque" .. i
		onda.Shape = Enum.PartType.Cylinder
		onda.Material = Enum.Material.Neon
		onda.Color = i == 1 and Color3.fromRGB(255, 170, 50) or Color3.fromRGB(255, 240, 200)
		onda.Anchored = true
		onda.CanCollide = false
		onda.CanQuery = false
		onda.CanTouch = false
		onda.CastShadow = false
		onda.Transparency = 1
		onda.Size = Vector3.new(0.3, 1, 1)
		onda.Parent = pasta
		ondas[i] = onda
	end

	-- ===== estado =====
	local function mundo(p) return inicio:PointToWorldSpace(p) end
	local direcaoChute = inicio:VectorToWorldSpace(Vector3.new(0, -0.35, -1).Unit)
	local impactoFeito = false
	local tituloMostrado, tituloEscondido = false, false
	local decolou = false
	local giroBola = 0
	local ultimoT = 0

	local function aplicarPose(t)
		local pose = spec.Pose(t)
		for nome, junta in pairs(juntas) do
			local ang = pose[nome]
			if ang then
				local rx, ry, rz = ang[1], ang[2], ang[3]
				-- R6 não tem cintura: a inclinação da cintura soma no corpo todo
				if not r15 and nome == "Root" and pose.Waist then
					rx += pose.Waist[1]
					ry += pose.Waist[2]
					rz += pose.Waist[3]
				end
				local original = c0Original[junta]
				junta.Escrever(CFrame.new(original.Position)
					* CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
					* original.Rotation)
			end
		end
	end

	local function limpar()
		RunService:UnbindFromRenderStep(nomeBind)
		for junta, c0 in pairs(c0Original) do
			if junta.Vivo() then junta.Escrever(c0) end
		end
		pasta:Destroy()
		-- a bola sai da cutscene ainda em chamas e continua assim no voo
		if ball and ball.Parent and impactoFeito then
			acenderBolaEmVoo(ball, 3)
		end
		correcao:Destroy()
		ui.Gui:Destroy()
		if _G.AnimadorPausado then _G.AnimadorPausado[character] = nil end
		if replay then
			-- ⚠️ v103: no replay não mexe em câmera/HUD do jogador
			if opts.AoTerminar then pcall(opts.AoTerminar) end
			return
		end
		for _, g in ipairs(guisEscondidas) do
			if g.Parent then g.Enabled = true end
		end
		camera.FieldOfView = fovOriginal
		camera.CameraType = Enum.CameraType.Custom
		local meuHumanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if meuHumanoid then camera.CameraSubject = meuHumanoid end
		_G.HissatsuCutsceneLocal = nil
		tocando = false
	end

	local function quadro()
		local t = replay and opts.Tempo() or (workspace:GetServerTimeNow() - horarioServidor)
		-- Ferramenta de ajuste: com o atributo "CutsceneDebugT" (número) no
		-- LocalPlayer, a cutscene fica PARADA nesse instante — dá pra olhar
		-- cada pose/câmera com calma. Sem o atributo, roda normal.
		-- "CutsceneDebugSlow" (ex.: 0.2) = câmera lenta: pra ver rastro e
		-- espiral, que só existem em movimento (congelado eles somem).
		local lento = player:GetAttribute("CutsceneDebugSlow")
		if typeof(lento) == "number" and lento > 0 then
			t *= lento
		end
		local tFixo = player:GetAttribute("CutsceneDebugT")
		if typeof(tFixo) == "number" then
			t = math.clamp(tFixo, 0, spec.Duration - 0.001)
		elseif player:GetAttribute("CutsceneDebugStop") then
			t = spec.Duration
		end
		local dt = math.clamp(t - ultimoT, 0, 0.1)
		ultimoT = t
		if t >= spec.Duration or not root.Parent then
			limpar()
			return
		end
		t = math.max(t, 0)

		esconderHud()

		-- animações normais paradas: a pose é toda da cutscene
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				track:Stop(0)
			end
		end

		-- corpo
		local rootLocal = spec.RootPosition(t)
		root.CFrame = inicio * spec.RootCFrame(t)
		aplicarPose(t)

		-- bola
		local bolaPosLocal = spec.BallPosition(t, bolaLocal)
		local bolaMundo = mundo(bolaPosLocal)
		-- ⚠️ v91: "o pé tem que colidir com a bola". O ponto do chute da
		-- coreografia é medido, mas o pé de cada avatar varia um pouco; então,
		-- chegando no chute, o caminho inteiro da bola é deslocado até ela
		-- ENCOSTAR no pé esquerdo de verdade (superfície da bola tocando o pé).
		if peE and spec.KickContactDir and t >= spec.Phases.Kick[1] - 0.15 then
			local raioBola = ball and ball.Size.X / 2 or 0.85
			local contato = peE.CFrame:PointToWorldSpace(deslE)
				+ inicio:VectorToWorldSpace(spec.KickContactDir) * (raioBola + 0.3)
			local cola = Cutscenes.Smooth(Cutscenes.Phase(t, spec.Phases.Kick[1] - 0.15, spec.ImpactTime))
			bolaMundo += (contato - mundo(spec.KickPoint)) * cola
			bolaPosLocal = inicio:PointToObjectSpace(bolaMundo)
		end
		giroBola += spec.BallSpin(t) * math.pi * 2 * dt
		if ball then
			ball.CFrame = CFrame.new(bolaMundo) * CFrame.Angles(giroBola, giroBola * 0.6, 0)
		end
		bolaFx.CFrame = CFrame.new(bolaMundo)

		local ph = spec.Phases
		local chaoLocal = Vector3.new(0, -2.9, 0)

		-- título da técnica
		if not tituloMostrado and t >= 0.35 then
			tituloMostrado = true
			TweenService:Create(ui.Nome, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.new(0.05, 0, 0.8, 0), TextTransparency = 0 }):Play()
			TweenService:Create(ui.Contorno, TweenInfo.new(0.3), { Transparency = 0 }):Play()
		elseif tituloMostrado and not tituloEscondido and t >= 1.5 then
			tituloEscondido = true
			TweenService:Create(ui.Nome, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
			TweenService:Create(ui.Contorno, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		end

		-- bola pega fogo quando começa a subir
		local bolaAcesa = t >= 0.3
		bolaFogo.Enabled = bolaAcesa
		bolaFogo.Rate = t >= ph.Jump[1] and 120 or 60
		bolaFaiscas.Enabled = bolaAcesa
		bolaFaiscas.Rate = 25
		bolaRastro.Enabled = bolaAcesa
		bolaLuz.Range = bolaAcesa and 14 or 0

		-- luz do corpo: acende com o giro e tremula
		local intensidade = Cutscenes.Phase(t, 0.4, 0.9)
		luzCorpo.CFrame = root.CFrame
		luz.Range = 18 * intensidade
		luz.Brightness = 2.5 + math.sin(t * 40) * 0.6

		-- anel de fogo em espiral nos pés, na DECOLAGEM (a imagem de
		-- referência): acompanha os pés subindo e abre enquanto ele sai do chão
		local noAnel = t >= ph.GroundSpin[1] and t < ph.GroundSpin[2]
		local centroAnel = mundo(Vector3.new(0, rootLocal.Y, 0) + chaoLocal + Vector3.new(0, 0.25, 0))
		local raio = 1.8 + 2.4 * Cutscenes.EaseOut(Cutscenes.Phase(t, ph.GroundSpin[1], ph.GroundSpin[2]))
		local angBase = t * math.pi * 2 * 2.4
		for i, a in ipairs(anel) do
			local ang = angBase + (i - 1) * math.pi
			local radial = inicio:VectorToWorldSpace(Vector3.new(math.cos(ang), 0, math.sin(ang)))
			local altura = math.sin(ang * 2 + t * 6) * 0.35
			local pos = centroAnel + radial * raio + Vector3.new(0, altura, 0)
			a.Parte.CFrame = CFrame.fromMatrix(pos, radial, Vector3.yAxis)
			a.Rastro.Enabled = noAnel
			a.Fogo.Enabled = noAnel
			a.Fogo.Rate = 45
		end

		-- decolagem: poeira e tremida
		if not decolou and t >= ph.Jump[1] then
			decolou = true
			poeira.CFrame = CFrame.new(mundo(chaoLocal)) * CFrame.Angles(0, 0, math.rad(90))
			poeiraEmissor:Emit(28)
		end

		-- ===== ESPIRAL EM VOLTA DO CORPO (ver criação acima) =====
		local centro = root.Position
		local noTornado = t >= ph.Crouch[1] and t < ph.Kick[1]
		local naEspiral = t >= ph.Crouch[1] and t < spec.ImpactTime + 0.03
		-- 0 = orbitando o corpo; 1 = todas juntas no pé esquerdo (o chute)
		-- ⚠️ v93 — PEDIDO: "unifique a espiral um pouco mais cedo, assim que
		-- começar a girar" (o giro/tombo pro chute, a partir do ápice): as fitas
		-- começam a se juntar no início do Apex (2.4s), e não só 0.3s antes.
		local juntar = Cutscenes.Smooth(Cutscenes.Phase(t, ph.Apex[1], ph.Kick[1]))
		local posPeE = peE and peE.CFrame:PointToWorldSpace(deslE) or centro
		-- direção da perna esquerda (quadril -> pé): no chute o rastro único
		-- corre ao longo dela
		local dirPerna = coxaE and (posPeE - coxaE.Position) or Vector3.yAxis
		if dirPerna.Magnitude < 0.05 then dirPerna = Vector3.yAxis end
		dirPerna = dirPerna.Unit
		-- referencial do CORPO: o giro (yaw) e o tombo (roll) dele — a espiral
		-- é desenhada nesse referencial, então gira e inclina junto com o corpo
		local corpo = root.CFrame.Rotation
		for _, e in ipairs(espiral) do
			-- posição fixa em volta do corpo + um avanço lento próprio (senão,
			-- quando o corpo para de girar no ápice, o rastro some)
			local ang = e.Fase * math.pi * 2 - t * math.pi * 2 * 0.6
			local sobe = (t * 1.2 + e.Fase) % 1 -- cada fita sobe em espiral e recomeça embaixo
			local raio = 3 + 1.4 * sobe
			local orbita = centro + corpo:VectorToWorldSpace(Vector3.new(math.cos(ang) * raio, -3.8 + 8 * sobe, math.sin(ang) * raio))
			local pos = orbita:Lerp(posPeE, juntar)
			-- faixa em pé ao longo do corpo enquanto orbita; no chute, alinhada à perna
			local eixo = root.CFrame.UpVector:Lerp(dirPerna, juntar)
			if eixo.Magnitude < 0.05 then eixo = Vector3.yAxis end
			eixo = eixo.Unit
			local lado = math.abs(eixo.Y) > 0.9 and Vector3.xAxis or Vector3.yAxis
			local z = lado:Cross(eixo).Unit
			e.Parte.CFrame = CFrame.fromMatrix(pos, eixo:Cross(z), eixo, z)
			-- no chute as fitas engrossam: juntas viram um rastro bem largo
			local largura = e.Largura * (1 + 0.5 * juntar)
			e.Rastro.Attachment0.Position = Vector3.new(0, -largura, 0)
			e.Rastro.Attachment1.Position = Vector3.new(0, largura, 0)
			local larguraMiolo = e.LarguraMiolo * (1 + 0.8 * juntar)
			e.Miolo.Attachment0.Position = Vector3.new(0, -larguraMiolo, 0)
			e.Miolo.Attachment1.Position = Vector3.new(0, larguraMiolo, 0)
			e.Rastro.Enabled = naEspiral
			e.Miolo.Enabled = naEspiral
			e.Fogo.Enabled = naEspiral
			e.Fogo.Rate = 60 + 80 * juntar
			e.Brasas.Enabled = naEspiral
			e.Brasas.Rate = 30
		end
		nuvemBrasas.CFrame = CFrame.new(centro)
		nuvemEmissor.Enabled = noTornado
		nuvemEmissor.Rate = 45
		coluna.CFrame = CFrame.new(centro + Vector3.new(0, -2.5, 0))
		colunaFogo.Enabled = noTornado
		colunaFogo.Rate = 70

		-- bola incandescente: acende enquanto a espiral se junta no pé e
		-- fica pulsando depois do impacto
		nucleo.CFrame = CFrame.new(bolaMundo)
		local brasa = math.max(juntar, impactoFeito and 1 or 0)
		nucleo.Transparency = 1 - brasa * (0.55 + 0.15 * math.sin(t * 35))

		-- ===== IMPACTO =====
		if not impactoFeito and t >= spec.ImpactTime then
			impactoFeito = true
			local k = mundo(spec.KickPoint)
			impacto.CFrame = CFrame.new(k)
			impactoFogo:Emit(90)
			bolaFogo.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 4),
				NumberSequenceKeypoint.new(0.6, 2.8),
				NumberSequenceKeypoint.new(1, 0),
			})
			nucleo.Size = Vector3.one * tamanhoBola * 1.6
			impactoFaiscas:Emit(60)
			bolaFaiscas:Emit(40)
			for i, onda in ipairs(ondas) do
				onda.CFrame = CFrame.lookAt(k, k + direcaoChute) * CFrame.Angles(0, math.rad(90), 0)
				onda.Size = Vector3.new(0.35, 1.5, 1.5)
				onda.Transparency = 0.05
				local final = i == 1 and 26 or 16
				local tempo = i == 1 and 0.32 or 0.22
				TweenService:Create(onda, TweenInfo.new(tempo, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = Vector3.new(0.15, final, final), Transparency = 1 }):Play()
			end
			ui.Flash.BackgroundTransparency = 0.15
			TweenService:Create(ui.Flash, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
			-- impact frame: um instante de contraste estourado, depois volta
			correcao.Brightness = 0.35
			correcao.Contrast = 0.7
			task.delay(0.07, function()
				if correcao.Parent then
					correcao.Contrast = 0.12
					TweenService:Create(correcao, TweenInfo.new(0.3), { Brightness = 0 }):Play()
				end
			end)
			-- linhas de velocidade
			ui.Linhas.Visible = true
			for _, l in ipairs(ui.ListaLinhas) do
				l.BackgroundTransparency = 0.1 + math.random() * 0.3
				TweenService:Create(l, TweenInfo.new(0.35 + math.random() * 0.15), { BackgroundTransparency = 1 }):Play()
			end
		end
		-- ⚠️ v91 — PEDIDO: "pode aumentar a intensidade desse fogo que causa
		-- na bola". Cresce enquanto a espiral se junta no pé e explode no
		-- impacto (o voo depois usa ~85% disso, ver acenderBolaEmVoo).
		if impactoFeito then
			bolaFogo.Rate = 350
			bolaFaiscas.Rate = 65
			bolaLuz.Range = 26
			bolaLuz.Brightness = 6
		elseif juntar > 0 then
			bolaFogo.Rate = 120 + 200 * juntar
			bolaLuz.Range = 14 + 10 * juntar
		end

		-- ===== câmera =====
		local camLocal, alvoLocal, fov = spec.Camera(t, rootLocal, bolaPosLocal)
		local tremida = Vector3.zero
		local forca = 0
		if t >= ph.Jump[1] and t < ph.Jump[1] + 0.2 then
			forca = 0.25 * (1 - Cutscenes.Phase(t, ph.Jump[1], ph.Jump[1] + 0.2))
		elseif t >= spec.ImpactTime then
			forca = 0.7 * (1 - Cutscenes.Phase(t, spec.ImpactTime, spec.Duration))
		end
		if forca > 0 then
			tremida = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2 * forca
		end
		if not replay then
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(mundo(camLocal) + tremida, mundo(alvoLocal))
			camera.FieldOfView = fov
		end
	end

	RunService:BindToRenderStep(nomeBind, Enum.RenderPriority.Camera.Value + 2, function()
		local ok, err = pcall(quadro)
		if not ok then
			warn("[Cutscene] erro no quadro, encerrando: " .. tostring(err))
			pcall(limpar)
		end
	end)
end

-- ⚠️ v103 — REPLAY DE GOL: a cutscene toca de novo no FANTASMA do chutador,
-- em tempo real (corpo, bola e VFX; câmera/HUD do jogador ficam como estão).
-- tempoFn() devolve o tempo da cutscene (segundos desde o início) no relógio
-- do replay; aoTerminar é chamado no fim (o replay volta a mover o fantasma).
_G.TocarCutsceneReplay = function(nome, modelo, bola, inicio, bolaLocal, titulo, tempoFn, aoTerminar, duracao)
	if typeof(duracao) == "number" and Cutscenes.PrepararDefesa then Cutscenes.PrepararDefesa(duracao) end
	local ok, err = pcall(tocarCutscene, nome, nil, inicio, bolaLocal, 0, titulo,
		{ Modelo = modelo, Bola = bola, Tempo = tempoFn, AoTerminar = aoTerminar })
	if not ok then
		warn("[Cutscene] replay não tocou: " .. tostring(err))
		if aoTerminar then pcall(aoTerminar) end
	end
end

-- ⚠️ v103: VFX leve do PREPARO de toda Hissatsu de chute (a pose é do
-- AnimadorProcedural, que ouve o mesmo aviso) — ver Efeitos.Preparo.
Remotes.AcaoAnimada.OnClientEvent:Connect(function(model, chave, duracao, parametros)
	if chave ~= "HissatsuPreparo" then return end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then return end
	local estilo = typeof(parametros) == "table" and parametros.Estilo or "Padrao"
	local ok, err = pcall(Efeitos.Preparo, estilo, model, duracao)
	if not ok then warn("[Cutscene] VFX do preparo falhou: " .. tostring(err)) end
end)

Remotes.HissatsuCutscene.OnClientEvent:Connect(function(nome, chutador, inicio, bolaLocal, horario, titulo, duracao, extras)
	-- ⚠️ v103: cutscene de defesa vem com a duração do duelo
	if typeof(duracao) == "number" and Cutscenes.PrepararDefesa then Cutscenes.PrepararDefesa(duracao) end
	-- ⚠️ v108: companheiros da Zona Morta (lidos na montagem das sombras)
	companheirosDaCutscene = typeof(extras) == "table" and typeof(extras.Companheiros) == "table" and extras.Companheiros or nil
	local ok, err = pcall(tocarCutscene, nome, chutador, inicio, bolaLocal, horario, titulo)
	companheirosDaCutscene = nil
	if not ok then
		warn("[Cutscene] não consegui iniciar: " .. tostring(err))
		_G.HissatsuCutsceneLocal = nil
		tocando = false
	end
end)

print("✅ HissatsuCutsceneClient carregado.")
