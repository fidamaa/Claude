--[[
	HissatsuCutscenes (ModuleScript)
	LOCAL: ReplicatedStorage

	⚠️ v87 — CUTSCENE DE HISSATSU. PEDIDO: "faça a cutscene do Fire Tornado...
	a câmera vidrada no personagem, ninguém vai poder se mexer até ficar 100%
	completa... usou a Hissatsu, vai ter aquele cooldownzinho de 3, 4
	segundos, depois vai rolar a animação, assim que acabar o chute vai sair."

	Este módulo é a COREOGRAFIA — a única fonte da verdade que o servidor e o
	cliente leem juntos:
	  - o SERVIDOR (PulseController.legacy.luau, playHissatsuCutscene) usa
	    Duration e as posições FINAIS do corpo e da bola, pra deixar tudo no
	    lugar certo quando a cutscene acaba e o chute sai;
	  - o CLIENTE (HissatsuCutsceneClient.local.luau) usa tudo: o caminho do
	    corpo, as poses de cada junta, o caminho da bola, as câmeras e o
	    horário de cada efeito.

	Não existe asset de animação aqui: a pose é montada por código, junta por
	junta (Motor6D.C0), e o corpo inteiro é movido pelo HumanoidRootPart. Por
	isso funciona em qualquer rig (R6 ou R15) e não precisa publicar nada.

	ESPAÇO LOCAL: tudo é relativo ao CFrame inicial do chutador, já virado pra
	mira. X = direita, Y = cima, -Z = frente (pra onde a bola vai).

	POSES: graus por junta, no espaço da peça-pai da junta. rx positivo = o
	membro vai pra FRENTE (perna/braço) / o corpo inclina pra TRÁS (Root,
	Waist) / a cabeça olha pra CIMA (Neck). rz positivo no ombro direito = braço
	abre pro lado (no esquerdo é negativo). Joelho negativo = dobra pra trás;
	cotovelo positivo = dobra pra frente.
	Juntas: Root (corpo inteiro), Waist, Neck, RShoulder, LShoulder, RElbow,
	LElbow, RHip, LHip, RKnee, LKnee. Em R6, Waist soma no Root e
	joelho/cotovelo não existem (são ignorados).
]]

local Cutscenes = {}

-- ===== utilidades de interpolação =====
local function smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function easeOut(u)
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) ^ 3
end

local function easeIn(u)
	u = math.clamp(u, 0, 1)
	return u * u * u
end

local function phase(t, a, b)
	if b <= a then return t >= b and 1 or 0 end
	return math.clamp((t - a) / (b - a), 0, 1)
end

-- Amostra uma lista de quadros-chave { {t, valor}, ... } (valor = number ou
-- Vector3), com transição suave entre eles.
local function sample(keys, t)
	if t <= keys[1][1] then return keys[1][2] end
	for i = 1, #keys - 1 do
		local a, b = keys[i], keys[i + 1]
		if t <= b[1] then
			local u = smooth(phase(t, a[1], b[1]))
			return a[2] + (b[2] - a[2]) * u
		end
	end
	return keys[#keys][2]
end

-- Mesma coisa pra poses: cada quadro é { t, { Junta = {rx, ry, rz} } }.
-- Junta ausente num quadro = pose neutra (0,0,0) naquele quadro.
local JOINTS = { "Root", "Waist", "Neck", "RShoulder", "LShoulder", "RElbow", "LElbow", "RHip", "LHip", "RKnee", "LKnee" }
local ZERO = { 0, 0, 0 }

local function samplePose(keys, t)
	local i1, i2, u = #keys, #keys, 0
	if t <= keys[1][1] then
		i1, i2 = 1, 1
	else
		for i = 1, #keys - 1 do
			if t <= keys[i + 1][1] then
				i1, i2 = i, i + 1
				u = smooth(phase(t, keys[i][1], keys[i + 1][1]))
				break
			end
		end
	end
	local a, b = keys[i1][2], keys[i2][2]
	local pose = {}
	for _, name in ipairs(JOINTS) do
		local va, vb = a[name] or ZERO, b[name] or ZERO
		pose[name] = {
			va[1] + (vb[1] - va[1]) * u,
			va[2] + (vb[2] - va[2]) * u,
			va[3] + (vb[3] - va[3]) * u,
		}
	end
	return pose
end

Cutscenes.Smooth = smooth
Cutscenes.EaseOut = easeOut
Cutscenes.Phase = phase
Cutscenes.Joints = JOINTS

-- ============================================================
-- 🔥 TORNADO DE FOGO (Fire Tornado / ファイアトルネード)
-- ============================================================
-- ⚠️ v88 — REFEITO a partir do vídeo da técnica (Victory Road), PEDIDO: "ele
-- não gira parando, ele gira no ar, rotaciona antes de chutar". A versão
-- anterior tinha um giro de 1s em pé no chão — isso não existe. O que
-- acontece de verdade, quadro a quadro:
--   1. ele levanta a bola BEM alto com o pé (a câmera sobe junto com ela);
--   2. gira só no instante da DECOLAGEM — é aí que aparecem os dois arcos de
--      fogo em volta dos pés (a imagem de referência) — e já sai do chão;
--   3. sobe girando em espiral dentro do redemoinho de fogo até PASSAR da
--      bola;
--   4. ele já sai do chão TOMBADO e gira assim, inclinado (v89); lá em cima
--      o corpo deita até quase ficar de cabeça pra baixo, a perna esquerda
--      arma;
--   5. bate na bola de cima pra baixo com a esquerda, quase deitado de lado,
--      e o fogo explode. A bola sai pro gol.
-- Descrição oficial (Eleven License): "a bola é chutada alto, ele gira em
-- direção à bola, sobe com um redemoinho de chamas e então chuta pra baixo".
--
-- LINHA DO TEMPO (segundos):
--   0.00-0.40  toque que levanta a bola (perna direita)
--   0.40-0.72  olha a bola subindo
--   0.72-0.88  agacha e começa a girar (anel de fogo nos pés)
--   0.88-2.50  decola e sobe girando (4 voltas) dentro do tornado
--   2.40-3.00  por cima da bola: tomba de lado, inclina pra trás, arma a perna
--   3.00-3.10  chute de cima pra baixo
--   3.10-3.60  impacto (flash, onda de choque) — no fim, o chute SAI
local FT = {}
Cutscenes.FireTornado = FT

FT.Duration = 3.6
FT.ImpactTime = 3.1
FT.TitleText = "TORNADO DE FOGO"

-- Fases usadas pelo cliente pros efeitos
FT.Phases = {
	Flick = { 0.0, 0.4 },
	GroundSpin = { 0.72, 1.3 }, -- anel de fogo nos pés: da agachada até já estar no ar
	Crouch = { 0.72, 0.88 },
	Jump = { 0.88, 2.5 },
	Apex = { 2.4, 3.0 },
	Kick = { 3.0, FT.ImpactTime },
	Impact = { FT.ImpactTime, 3.6 },
}

local APEX_HEIGHT = 22
local KICK_HEIGHT = 22.8
local APEX_FORWARD = -1.5

-- Posição do corpo (HumanoidRootPart) no espaço local.
function FT.RootPosition(t)
	if t < 0.72 then
		return Vector3.zero
	elseif t < 0.88 then
		return Vector3.new(0, -0.7 * smooth(phase(t, 0.72, 0.88)), 0)
	elseif t < 2.5 then
		local u = easeOut(phase(t, 0.88, 2.5))
		return Vector3.new(0, -0.7 + (APEX_HEIGHT + 0.7) * u, APEX_FORWARD * u)
	elseif t < FT.ImpactTime then
		local u = smooth(phase(t, 2.5, FT.ImpactTime))
		return Vector3.new(0, APEX_HEIGHT + (KICK_HEIGHT - APEX_HEIGHT) * u, APEX_FORWARD)
	end
	return Vector3.new(0, KICK_HEIGHT, APEX_FORWARD)
end

-- Giro em volta do eixo Y (radianos): começa na agachada e continua o voo
-- inteiro — 4 voltas, rápido na decolagem e desacelerando até ficar de
-- frente pra mira na hora de armar o chute (sempre volta inteira).
-- ⚠️ v89 — PEDIDO (com a referência do anime, Fire Tornado Kai): "o boneco
-- começa a tombar desde antes, depois de pular ele já tomba e gira ao
-- contrário". O giro é no sentido HORÁRIO visto de cima (negativo), e ele
-- gira JÁ INCLINADO — o corpo tombado precessa em volta do eixo vertical,
-- como um pião torto.
function FT.RootYaw(t)
	local u = phase(t, 0.72, 2.75)
	return -2 * math.pi * 4 * (1 - (1 - u) ^ 2)
end

-- Tombo de lado (rolar em volta do eixo da frente). Negativo = deita pro lado
-- DIREITO, deixando a perna esquerda por cima, que é a que chuta. Começa logo
-- depois de sair do chão (~45° subindo, visto no anime aos 3.0-3.3s), vai
-- deitando até ficar quase de cabeça pra baixo por cima da bola (5.2s no
-- anime) e o chute sai com o corpo passando da horizontal.
local ROLL_KEYS = {
	{ 0.00, 0 },
	{ 0.90, 0 },
	{ 1.25, -40 },
	{ 2.10, -50 },
	{ 2.55, -65 },
	{ 2.95, -95 },
	{ FT.ImpactTime, -110 },
	{ 3.60, -115 },
}

function FT.RootCFrame(t)
	local roll = math.rad(sample(ROLL_KEYS, t))
	return CFrame.new(FT.RootPosition(t)) * CFrame.Angles(0, FT.RootYaw(t), 0) * CFrame.Angles(0, 0, roll)
end

-- Onde a bola é tocada: logo à frente e abaixo do pé esquerdo, que desce por
-- cima dela. Medido no personagem de verdade no instante do chute (pé
-- esquerdo em -1.06, 23.68, -3.60 com o corpo quase invertido, v89).
-- ⚠️ v91 — PEDIDO: "lembra que o pé tem que colidir com a bola, tem que
-- encostar na bola pro chute sair". O centro da bola fica a raio (0.85) + meio
-- pé (0.3) do centro do pé, na direção em que o pé desce (pra baixo e pra
-- frente) — as superfícies se tocam no instante do chute. O cliente ainda
-- corrige ao vivo pelo pé de verdade (ver HissatsuCutsceneClient).
FT.KickPoint = Vector3.new(-1.06, KICK_HEIGHT - 0.13, APEX_FORWARD - 2.65)
FT.KickContactDir = Vector3.new(0, -0.88, -0.48).Unit
-- Direção (local) que a bola começa a "ceder" no impacto.
local IMPACT_PUSH = Vector3.new(0, -0.35, -1).Unit * 1.6

-- Caminho da bola. `ballStart` = onde ela estava no pé quando a cutscene
-- começou (local), mandado pelo servidor.
function FT.BallPosition(t, ballStart)
	ballStart = ballStart or Vector3.new(0, -2.3, -1.8)
	local apex = Vector3.new(0, 27, -2.6)
	local hover = Vector3.new(0, 25, -2.8)
	if t < 0.22 then
		return ballStart
	elseif t < 1.3 then
		-- sobe rápido e alto, girando
		local u = easeOut(phase(t, 0.22, 1.3))
		local base = ballStart:Lerp(apex, u)
		local wobble = (1 - u) * 0.7
		return base + Vector3.new(math.sin(t * 10) * wobble, 0, math.cos(t * 10) * wobble)
	elseif t < 2.4 then
		-- quase parada lá em cima, esperando ele chegar
		return apex:Lerp(hover, smooth(phase(t, 1.3, 2.4)))
	elseif t < FT.ImpactTime then
		return hover:Lerp(FT.KickPoint, smooth(phase(t, 2.4, FT.ImpactTime)))
	end
	local u = easeOut(phase(t, FT.ImpactTime, FT.Duration))
	return FT.KickPoint + IMPACT_PUSH * u
end

function FT.BallSpin(t)
	if t < 0.22 then return 0 end
	if t < FT.ImpactTime then return 12 end
	return 30
end

-- Poses (graus). Ver o cabeçalho pro significado de cada eixo.
local NEUTRAL = {}
local POSE_KEYS = {
	{ 0.00, NEUTRAL },
	-- prepara o toque: perna direita pra trás
	{ 0.12, {
		Root = { -6, 0, 0 },
		RHip = { -30, 0, 0 }, RKnee = { -25, 0, 0 }, LKnee = { -12, 0, 0 },
		RShoulder = { -10, 0, 20 }, LShoulder = { 15, 0, -20 },
	} },
	-- toque: a perna direita sobe e manda a bola pro alto
	{ 0.28, {
		Root = { 8, 0, 0 }, Neck = { 18, 0, 0 },
		RHip = { 80, 0, 0 }, RKnee = { -5, 0, 0 }, LKnee = { -15, 0, 0 },
		RShoulder = { -20, 0, 40 }, LShoulder = { 20, 0, -40 },
	} },
	-- acompanha a bola subindo com o olhar
	{ 0.55, {
		Root = { 4, 0, 0 }, Neck = { 40, 0, 0 },
		RHip = { 5, 0, 0 }, RKnee = { -10, 0, 0 }, LKnee = { -8, 0, 0 },
		RShoulder = { 0, 0, 25 }, LShoulder = { 0, 0, -25 },
	} },
	-- agachada girando: carrega o salto, braços pra trás
	{ 0.86, {
		Root = { -22, 0, 0 }, Waist = { -8, 0, 0 }, Neck = { 35, 0, 0 },
		RHip = { 55, 0, 0 }, LHip = { 55, 0, 0 }, RKnee = { -95, 0, 0 }, LKnee = { -95, 0, 0 },
		RShoulder = { -40, 0, 30 }, LShoulder = { -40, 0, -30 },
	} },
	-- ⚠️ v122 — PEDIDO: "no Tornado de Fogo (e no Dragão, e em quem usa): na SUBIDA ele
	-- vai abrindo as pernas DEVAGAR; no chute SÓ a perna do chute mexe e a outra vai pra
	-- TRÁS — pose de bicicleta". Antes as pernas já saíam do chão em tesoura e, no chute,
	-- o corpo inteiro (Root 26 → -25) e a perna de apoio (50 → -30) giravam junto com a
	-- do chute. Agora: decola de pernas juntas, elas abrem aos poucos até armar; a perna
	-- DIREITA vai pra trás no armar e fica parada (no mundo, ~45° pra trás); o tronco
	-- fica quase fixo e só a ESQUERDA chicoteia (mesmo ângulo final no mundo de antes:
	-- Root + LHip = 80, então o pé chega no mesmo lugar da bola). R6: joelho não existe.
	-- decolagem: estica, braços abrem, pernas ainda JUNTAS
	{ 1.05, {
		Root = { 6, 0, 0 }, Neck = { 30, 0, 0 },
		RHip = { -4, 0, 2 }, RKnee = { -15, 0, 0 },
		LHip = { 12, 0, -2 }, LKnee = { -40, 0, 0 },
		RShoulder = { 25, 0, 95 }, LShoulder = { 25, 0, -95 },
	} },
	-- subindo em espiral: braços abertos pro giro, as pernas vão abrindo devagar
	{ 1.60, {
		Root = { -4, 0, 0 }, Neck = { 25, 0, 0 },
		RHip = { -14, 0, 7 }, RKnee = { -30, 0, 0 },
		LHip = { 32, 0, -7 }, LKnee = { -70, 0, 0 },
		RShoulder = { 10, 0, 85 }, LShoulder = { 10, 0, -85 }, RElbow = { 15, 0, 0 }, LElbow = { 15, 0, 0 },
	} },
	{ 2.35, {
		Root = { -6, 0, 0 }, Neck = { 10, 0, 0 },
		RHip = { -26, 0, 12 }, RKnee = { -40, 0, 0 },
		LHip = { 52, 0, -12 }, LKnee = { -90, 0, 0 },
		RShoulder = { 15, 0, 90 }, LShoulder = { 15, 0, -90 }, RElbow = { 20, 0, 0 }, LElbow = { 20, 0, 0 },
	} },
	-- por cima da bola: ARMA a perna esquerda; a direita vai pra trás e PARA ali
	{ 2.75, {
		Root = { 12, 0, 0 }, Waist = { 6, 0, 0 }, Neck = { -15, 0, 0 },
		RHip = { -57, 0, 10 }, RKnee = { -30, 0, 0 },
		LHip = { -62, 0, -6 }, LKnee = { -85, 0, 0 },
		RShoulder = { 30, 0, 120 }, LShoulder = { -35, 0, -65 }, RElbow = { 20, 0, 0 },
	} },
	{ 3.00, {
		Root = { 14, 0, 0 }, Waist = { 8, 0, 0 }, Neck = { -20, 0, 0 },
		RHip = { -59, 0, 10 }, RKnee = { -30, 0, 0 },
		LHip = { -73, 0, -6 }, LKnee = { -100, 0, 0 },
		RShoulder = { 35, 0, 125 }, LShoulder = { -40, 0, -70 }, RElbow = { 25, 0, 0 },
	} },
	-- CHUTE: só a perna esquerda chicoteia por cima da bola, pra baixo
	{ FT.ImpactTime, {
		Root = { 8, 0, 0 }, Waist = { -4, 0, 0 }, Neck = { -26, 0, 0 },
		LHip = { 72, 0, -4 }, LKnee = { -4, 0, 0 },
		RHip = { -53, 0, 10 }, RKnee = { -30, 0, 0 },
		RShoulder = { -50, 0, 100 }, LShoulder = { 50, 0, -80 }, LElbow = { 20, 0, 0 },
	} },
	{ 3.60, {
		Root = { 6, 0, 0 }, Waist = { -6, 0, 0 }, Neck = { -28, 0, 0 },
		LHip = { 80, 0, -4 }, LKnee = { -2, 0, 0 },
		RHip = { -51, 0, 10 }, RKnee = { -32, 0, 0 },
		RShoulder = { -52, 0, 102 }, LShoulder = { 52, 0, -80 }, LElbow = { 22, 0, 0 },
	} },
}

function FT.Pose(t)
	return samplePose(POSE_KEYS, t)
end

-- ===== CÂMERAS =====
-- Cada plano devolve (posição da câmera, ponto olhado, FOV) no espaço local.
-- Planos tirados do vídeo da técnica; cortes SECOS entre eles.
function FT.Camera(t, rootPos, ballPos)
	if t < 0.4 then
		-- 1) contra-plongée de frente: o toque
		local u = phase(t, 0, 0.4)
		local look = Vector3.new(0, 0.5, 0):Lerp(ballPos, 0.35 + 0.4 * u)
		return Vector3.new(5.5, -1.6, -8.5), look, 62
	elseif t < 0.72 then
		-- 2) do chão, olhando a bola sumir no céu
		return Vector3.new(2.5, -1.8, 5), ballPos, 55
	elseif t < 1.3 then
		-- 3) de cima, na diagonal: a decolagem girando com o anel de fogo
		--    (o enquadramento da imagem de referência)
		local u = smooth(phase(t, 0.72, 1.3))
		local pos = Vector3.new(9.5, 7 + rootPos.Y * 0.7, -8):Lerp(Vector3.new(8.5, 8 + rootPos.Y * 0.8, -6), u)
		return pos, rootPos + Vector3.new(0, -0.5, 0), 62
	elseif t < 2.4 then
		-- 4) lá de cima, perto da bola, olhando ele subir no redemoinho
		local u = smooth(phase(t, 1.3, 2.4))
		local pos = ballPos + Vector3.new(3, 5, 6):Lerp(Vector3.new(4, 3, 5), u)
		return pos, rootPos + Vector3.new(0, 1, 0), 62 - 6 * u
	elseif t < FT.ImpactTime then
		-- 5) de frente e de lado: o tombo e o chute armado
		local u = smooth(phase(t, 2.4, FT.ImpactTime))
		local pos = rootPos + Vector3.new(8, -1.5, -6):Lerp(Vector3.new(6.5, -2, -4.5), u)
		return pos, rootPos:Lerp(ballPos, 0.5), 58
	end
	-- 6) impacto: perto, do lado do PÉ ESQUERDO (do outro lado o corpo tombado
	-- fica na frente da bola), com zoom seco
	local u = easeOut(phase(t, FT.ImpactTime, FT.Duration))
	local pos = FT.KickPoint + Vector3.new(-7, 2.4, 2):Lerp(Vector3.new(-5.5, 1.8, 1), u)
	return pos, ballPos, 62 - 14 * u
end

-- ============================================================
-- ⚠️ v100 — CUTSCENES DAS PRÓXIMAS HISSATSUS. PEDIDO: "depois que você
-- terminar tudo isso... você começa as cutscenes das próximas habilidades".
-- ============================================================
-- Todas as de baixo rodam no MOTOR V2 do cliente (Motor = "V2" — ver
-- tocarCutsceneV2 no HissatsuCutsceneClient): o motor é genérico (câmera,
-- pose, caminho do corpo e da bola, bola encostando no pé de chute, clones,
-- impacto) e os efeitos de cada técnica moram em HissatsuEfeitos.luau
-- (campo Efeitos). O Tornado de Fogo continua no caminho original dele, que
-- o usuário aprovou ("ficou perfeito") — não foi mexido.
--
-- Campos novos (além dos do Tornado):
--   Motor = "V2"; Efeitos = nome do conjunto em HissatsuEfeitos;
--   KickFoot = "Right"/"Left" (o pé que encosta na bola no chute);
--   Tema = cores do letreiro, do flash e da correção de cor da cena;
--   BallVisible(t) (opcional) — a bola some (Sumiço);
--   Clones (opcional) — sombras do chutador (Zona Morta).
--
-- Pesquisa de cada uma (wiki de Inazuma Eleven, seção "Usage", e o vídeo do
-- Victory Road) está resumida no comentário de cada técnica. Os pontos de
-- chute (KickPoint) foram medidos no avatar de verdade no Studio, com a pose
-- do instante do chute aplicada; o cliente ainda cola a bola no pé real.

Cutscenes.Sample = sample
Cutscenes.SamplePose = samplePose
Cutscenes.EaseIn = easeIn

local V3 = Vector3.new
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local function rad(g) return math.rad(g) end

local PARES = {
	RShoulder = "LShoulder", LShoulder = "RShoulder", RElbow = "LElbow", LElbow = "RElbow",
	RHip = "LHip", LHip = "RHip", RKnee = "LKnee", LKnee = "RKnee",
}
-- Troca direita/esquerda de uma pose já amostrada (inverte ry e rz).
local function espelharPose(pose)
	local out = {}
	for nome, v in pairs(pose) do
		out[PARES[nome] or nome] = { v[1], -v[2], -v[3] }
	end
	return out
end
Cutscenes.EspelharPose = espelharPose

-- ⚠️ v100 — CALIBRAGEM DO CHÃO. Medido no Studio: o avatar de teste tem o
-- quadril 3.47 acima do gramado (não 2.9, que é o que o Tornado supõe — lá
-- não importa, é tudo no ar). Tudo que APOIA no gramado (bola parada, torii,
-- gelo, onda, a palma da Galáxia) usa CAL.Chao; o cliente mede o chão de
-- verdade debaixo do chutador e chama Cutscenes.Calibrar antes de tocar. O
-- servidor não calibra (usa o padrão): a diferença é de meio stud e só na
-- posição final do Impulso de Maré, que está no ar.
local CAL = { Chao = -2.9, Raio = 0.85 }
Cutscenes.Calibragem = CAL
local recalculos = {}
function Cutscenes.Calibrar(chaoY, raioBola)
	CAL.Chao = (typeof(chaoY) == "number" and chaoY < -1 and chaoY > -8) and chaoY or -2.9
	CAL.Raio = (typeof(raioBola) == "number" and raioBola > 0.2) and raioBola or 0.85
	for _, f in ipairs(recalculos) do f() end
end

-- yaw (radianos) pra quem está em `de` olhar pra `para` (no chão)
local function yawOlhando(de, para)
	local d = para - de
	return math.atan2(-d.X, -d.Z)
end

-- ============================================================
-- ⚡ RAIO UM (Inazuma 1gou / イナズマ1号) — Luz
-- ============================================================
-- Wiki: "dois usuários correm lado a lado, giram rápido até a bola trocando
-- de lugar, e os dois batem de voleio carregando a bola com raios amarelos".
-- Aqui é solo: toque pra cima, GIRO rápido no ar (a troca de lugar vira uma
-- volta inteira), um RAIO cai do céu e prende a bola lá em cima eletrizada,
-- ele arma o voleio de lado e bate. É o chute mais rápido do jogo (preparo
-- 0.8s), então a cutscene é a mais curta: 2.5s.
local R1 = {}
Cutscenes.RaioUm = R1
R1.Motor = "V2"
R1.Efeitos = "Raio"
R1.KickFoot = "Right"
R1.Duration = 2.5
R1.ImpactTime = 2.0
R1.TitleText = "RAIO UM"
R1.Tema = {
	Titulo = { rgb(255, 255, 225), rgb(255, 225, 70), rgb(255, 160, 0) },
	Contorno = rgb(35, 25, 90), Flash = rgb(255, 250, 215),
	Tint = rgb(232, 238, 255), Saturation = 0.2, Contrast = 0.15, Brightness = 0,
}
R1.Phases = {
	Flick = { 0, 0.3 }, Spin = { 0.3, 0.95 }, Strike = { 1.0, 1.3 }, Cock = { 1.3, 1.85 },
	Kick = { 1.85, R1.ImpactTime }, Impact = { R1.ImpactTime, R1.Duration },
}
local R1_ROOT = {
	{ 0.00, V3(0, 0, 0) }, { 0.30, V3(0, 0, 0) }, { 0.62, V3(0, 1.4, -0.3) }, { 0.95, V3(0, -0.15, -0.5) },
	{ 1.30, V3(0, 0, -0.55) }, { 1.75, V3(0, 0, -0.7) }, { R1.ImpactTime, V3(0, 0.05, -0.9) }, { 2.5, V3(0, -0.1, -1.1) },
}
-- ⚠️ v113 — revisão pelo vídeo (quadros a cada 0,2s, "Inazuma 1gou"): os dois
-- SALTAM pro chute (20.4-21.4s) e batem a bola juntos na altura da CABEÇA, no ar.
-- Antes o chutador batia de pé, com a bola na cintura. Salto com pico no chute
-- (o parceiro é o espelho do chutador, então salta junto).
local R1_SALTO = 2.0
local function r1Salto(t)
	local u = math.clamp((t - 1.45) / 0.95, 0, 1)
	return R1_SALTO * math.sin(math.pi * u)
end
function R1.RootPosition(t) return sample(R1_ROOT, t) + V3(0, r1Salto(t), 0) end
-- tomba pro lado ESQUERDO (positivo) no voleio de direita
local R1_ROLL = { { 0, 0 }, { 1.3, 0 }, { 1.85, 14 }, { R1.ImpactTime, 24 }, { 2.5, 26 } }
function R1.RootCFrame(t)
	local yaw = 2 * math.pi * smooth(phase(t, 0.3, 0.95)) -- uma volta inteira, anti-horário
	return CFrame.new(R1.RootPosition(t)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, rad(sample(R1_ROLL, t)))
end
R1.StrikeTime = 1.0 -- o raio cai
local R1_APEX = V3(0.6, 4.4, -2.6)
R1.KickPoint = V3(1.2, 0.05 + 1.95, -3.75) -- medido: pé direito em (1.61, 0.04, -2.67) no voleio · v113: + o salto (~1.95 no chute)
R1.KickContactDir = V3(-0.35, 0, -0.94).Unit
local R1_PUSH = V3(-0.2, 0.05, -1).Unit * 1.8
function R1.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.14 then return s end
	if t < 0.85 then
		return s:Lerp(R1_APEX, easeOut(phase(t, 0.14, 0.85)))
	end
	if t < 1.45 then
		-- presa no ar pelo raio: treme, eletrizada
		local k = phase(t, 0.85, 1.45)
		return R1_APEX + V3(math.sin(t * 47) * 0.08, math.sin(t * 9) * 0.12 * (1 - k), math.cos(t * 39) * 0.08)
	end
	if t < R1.ImpactTime then
		local u = phase(t, 1.45, R1.ImpactTime)
		return R1_APEX:Lerp(R1.KickPoint, u * u) -- cai acelerando até o pé
	end
	return R1.KickPoint + R1_PUSH * easeOut(phase(t, R1.ImpactTime, R1.Duration))
end
function R1.BallSpin(t)
	if t < 0.14 then return 0 end
	if t < R1.StrikeTime then return 6 end
	if t < R1.ImpactTime then return 14 end
	return 30
end
local R1_POSE = {
	{ 0.00, {} },
	{ 0.12, { Root = { -5, 0, 0 }, RHip = { -25, 0, 0 }, RKnee = { -30, 0, 0 }, LKnee = { -10, 0, 0 },
		RShoulder = { -10, 0, 20 }, LShoulder = { 15, 0, -20 } } },
	-- o toque pra cima
	{ 0.28, { Root = { 6, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 55, 0, 0 }, RKnee = { -20, 0, 0 }, LKnee = { -12, 0, 0 },
		RShoulder = { -20, 0, 35 }, LShoulder = { 20, 0, -35 } } },
	-- giro no ar, encolhido (braços abraçando o corpo)
	{ 0.45, { Neck = { 10, 0, 0 }, RHip = { 60, 0, 0 }, RKnee = { -90, 0, 0 }, LHip = { 50, 0, 0 }, LKnee = { -80, 0, 0 },
		RShoulder = { 40, 0, -20 }, LShoulder = { 40, 0, 20 }, RElbow = { 100, 0, 0 }, LElbow = { 100, 0, 0 } } },
	{ 0.80, { Neck = { 10, 0, 0 }, RHip = { 55, 0, 0 }, RKnee = { -85, 0, 0 }, LHip = { 50, 0, 0 }, LKnee = { -80, 0, 0 },
		RShoulder = { 40, 0, -20 }, LShoulder = { 40, 0, 20 }, RElbow = { 100, 0, 0 }, LElbow = { 100, 0, 0 } } },
	-- aterrissa agachado, braços abertos
	{ 0.95, { Root = { -12, 0, 0 }, RHip = { 40, 0, 0 }, LHip = { 40, 0, 0 }, RKnee = { -60, 0, 0 }, LKnee = { -60, 0, 0 },
		RShoulder = { 0, 0, 45 }, LShoulder = { 0, 0, -45 } } },
	-- olha o raio cair na bola
	{ 1.25, { Root = { 5, 0, 0 }, Neck = { 35, 0, 0 }, RHip = { 10, 0, 0 }, LHip = { 10, 0, 0 }, RKnee = { -20, 0, 0 }, LKnee = { -20, 0, 0 },
		RShoulder = { 20, 0, 60 }, LShoulder = { 20, 0, -60 } } },
	-- arma o voleio de lado: perna direita pra trás e aberta
	{ 1.65, { Root = { 10, 0, 0 }, Neck = { -10, 0, 0 }, LKnee = { -25, 0, 0 }, RHip = { -30, 0, 30 }, RKnee = { -100, 0, 0 },
		RShoulder = { -30, 0, 50 }, LShoulder = { 40, 0, -70 } } },
	{ 1.90, { Root = { 9, 0, 0 }, Neck = { -12, 0, 0 }, LKnee = { -22, 0, 0 }, RHip = { 60, 0, 45 }, RKnee = { -60, 0, 0 },
		RShoulder = { -35, 0, 60 }, LShoulder = { 35, 0, -75 } } },
	-- VOLEIO
	{ R1.ImpactTime, { Root = { 8, 0, 0 }, Neck = { -15, 0, 0 }, LKnee = { -20, 0, 0 }, RHip = { 95, 0, 30 }, RKnee = { -5, 0, 0 },
		RShoulder = { -40, 0, 70 }, LShoulder = { 30, 0, -80 } } },
	{ 2.50, { Root = { 12, 0, 0 }, Neck = { -12, 0, 0 }, LKnee = { -22, 0, 0 }, RHip = { 110, 0, 10 }, RKnee = { -10, 0, 0 },
		RShoulder = { -40, 0, 70 }, LShoulder = { 30, 0, -80 } } },
}
function R1.Pose(t) return samplePose(R1_POSE, t) end

-- ⚠️ v108 — REFEITO COM O ANIME (vídeo "Inazuma Eleven - Inazuma 1gou", quadros a
-- cada 0,5s) + wiki ("dois usuários giram trocando de lugar e, ao bater de voleio
-- JUNTOS, carregam a bola com raios amarelos"). O que mudou:
--   • tem PARCEIRO (Clones, 1): o companheiro do time mais perto, com a aparência
--     dele, ou uma sombra dourada se não tiver ninguém perto (não é obrigatório);
--   • no giro os dois se CRUZAM (trocam de lugar) — o parceiro sai do lado
--     esquerdo e termina do outro lado da bola;
--   • o voleio é dos DOIS ao mesmo tempo, um de cada lado da bola (o parceiro é o
--     espelho do chutador em volta da bola e bate de esquerda);
--   • não cai mais raio do céu: a energia sai dos DOIS corpos pra bola (Efeitos).
local R1_ESPELHO_X = R1.KickPoint.X -- plano vertical que passa pela bola
local function r1Espelho(p) return V3(2 * R1_ESPELHO_X - p.X, p.Y, p.Z) end
-- ⚠️ v122 — PEDIDO: "nos chutes em conjunto (menos a Zona Morta) os companheiros mais LONGE do jogador" (era -2.4, 0, 0.6)
local R1_PARCEIRO_INICIO = V3(-4.0, 0, 0.8) -- correndo do lado esquerdo do chutador
function R1.ParceiroPos(t)
	if t < 0.3 then return R1_PARCEIRO_INICIO end
	if t < 0.95 then
		-- cruza por trás do chutador, no ar, até o lado de lá da bola
		local u = smooth(phase(t, 0.3, 0.95))
		local destino = r1Espelho(R1.RootPosition(0.95))
		local base = R1_PARCEIRO_INICIO:Lerp(destino, u)
		return base + V3(0, 1.6 * math.sin(u * math.pi), 1.2 * math.sin(u * math.pi))
	end
	return r1Espelho(R1.RootPosition(t))
end
R1.Clones = {
	Quantidade = 1,
	Cor = rgb(255, 205, 60),
	CFrame = function(_i, t)
		local cf = R1.RootCFrame(t)
		local _, yaw, roll = 0, 0, 0
		do
			local rx, ry, rz = cf:ToEulerAnglesYXZ()
			yaw, roll = ry, rz
		end
		-- gira no sentido contrário e tomba pro outro lado (espelho)
		return CFrame.new(R1.ParceiroPos(t)) * CFrame.Angles(0, -yaw, 0) * CFrame.Angles(0, 0, -roll)
	end,
	Pose = function(_i, t) return espelharPose(samplePose(R1_POSE, t)) end,
	Alpha = function(_i, t)
		if t < 0.1 then return smooth(phase(t, 0, 0.1)) end
		if t < 2.3 then return 1 end
		return 1 - smooth(phase(t, 2.3, 2.5))
	end,
}
function R1.Camera(t, rootPos, ballPos)
	if t < 0.3 then
		return V3(4.5, -1.8, -7), (rootPos + V3(0, -1, 0)):Lerp(ballPos, 0.5), 60
	elseif t < 0.95 then
		-- orbita o giro
		local u = smooth(phase(t, 0.3, 0.95))
		local ang = 0.6 + 2.0 * u
		return rootPos + V3(math.cos(ang) * 7, 1.2, -math.sin(ang) * 7), rootPos, 58
	elseif t < 1.35 then
		-- do chão, olhando o raio cair na bola
		return V3(2.5, -2.3, 3), ballPos, 66
	elseif t < R1.ImpactTime then
		-- ⚠️ v108: DE FRENTE, os dois armando o voleio, um de cada lado da bola
		local u = smooth(phase(t, 1.35, R1.ImpactTime))
		local meio = V3(R1_ESPELHO_X, 0.4 + r1Salto(t), -2.2) -- ⚠️ v113: acompanha o salto
		return meio + V3(0.3, 0.8, -9.5):Lerp(V3(0.2, 0.5, -7.5), u), meio, 60
	end
	-- impacto: de trás e do alto, os dois batendo juntos e a bola saindo
	-- ⚠️ v113: mais longe e mais alto — a cabeça do chutador (agora no ar)
	-- tampava metade da cena; aqui dá pra ver a bola sair com os raios
	local u = easeOut(phase(t, R1.ImpactTime, R1.Duration))
	return R1.KickPoint + V3(-3.5, 5, 10):Lerp(V3(-2.5, 4, 8), u), ballPos, 64 - 12 * u
end

-- ============================================================
-- ⛩️ SUMIÇO (Kamikakushi / かみかくし) — Void
-- ============================================================
-- Wiki: a bola chutada em curva SOME na frente do goleiro; aparece um TORII
-- numa névoa roxa escura, a bola faz espiral até ele deixando redemoinhos
-- roxos, o torii some e a bola sai coberta de energia roxa, em curva.
-- Adaptação: o chute de verdade sai de onde a cutscene deixa a bola (o
-- servidor põe a bola no último quadro), então ela não pode terminar lá na
-- frente. Por isso: sinal de mão, o torii nasce à frente, a bola espirala em
-- volta dele (chutador) e ENTRA no torii — some —, e reaparece num redemoinho
-- no pé dele, que bate de curva com a direita. O sumiço de verdade, no voo,
-- continua sendo o VanishSeconds do efeito.
local SU = {}
Cutscenes.Sumico = SU
SU.Motor = "V2"
SU.Efeitos = "Sumico"
SU.KickFoot = "Right"
SU.Duration = 2.9
SU.ImpactTime = 2.35
SU.TitleText = "SUMIÇO"
SU.Tema = {
	Titulo = { rgb(245, 215, 255), rgb(190, 90, 255), rgb(110, 20, 170) },
	Contorno = rgb(30, 0, 45), Flash = rgb(220, 160, 255),
	Tint = rgb(215, 195, 245), Saturation = -0.1, Contrast = 0.2, Brightness = -0.05,
}
SU.ToriiBase = V3(0, -2.9, -9)
SU.Portal = V3(0, 1.3, -9)
table.insert(recalculos, function()
	SU.ToriiBase = V3(0, CAL.Chao, -9)
	SU.KickPoint = V3(0.35, CAL.Chao + CAL.Raio, -2.35)
end)
SU.Phases = {
	Sign = { 0, 0.45 }, Torii = { 0.3, 0.9 }, Spiral = { 0.45, 1.35 }, Vanish = { 1.35, 1.95 },
	Reappear = { 1.8, 2.2 }, Kick = { 2.2, SU.ImpactTime }, Impact = { SU.ImpactTime, SU.Duration },
	ToriiOut = { SU.ImpactTime, 2.85 },
}
local SU_ROOT = {
	{ 0, V3(0, 0, 0) }, { 1.45, V3(0, 0, 0) }, { 1.95, V3(-0.15, -0.1, 0.25) },
	{ SU.ImpactTime, V3(0, -0.1, -0.45) }, { 2.9, V3(0, -0.05, -0.75) },
}
local SU_YAW = { { 0, 0 }, { 1.45, 0 }, { 1.95, 20 }, { SU.ImpactTime, -6 }, { 2.9, -14 } }
function SU.RootPosition(t) return sample(SU_ROOT, t) end
function SU.RootCFrame(t)
	return CFrame.new(SU.RootPosition(t)) * CFrame.Angles(0, rad(sample(SU_YAW, t)), 0)
end
SU.KickPoint = V3(0.35, -2.05, -2.35) -- (recalculado pela calibragem: bola no gramado)
-- um pouco pra cima: o pé bate na metade de baixo da bola, e a bola não afunda no gramado
SU.KickContactDir = V3(-0.25, 0.2, -1).Unit
local SU_PUSH = V3(-0.35, 0.1, -1).Unit * 1.8
function SU.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.45 then return s end
	if t < 1.35 then
		local u = phase(t, 0.45, 1.35)
		-- espiral em volta do chutador (1 volta e 1/4, subindo), depois
		-- mergulha no portal do torii
		local a = -math.pi / 2 - 2 * math.pi * 1.25 * smooth(u)
		local r = 1.8 + 1.4 * math.sin(math.pi * math.min(u * 1.25, 1))
		local espiral = V3(math.cos(a) * r, s.Y + (2.6 - s.Y) * smooth(math.min(u * 1.4, 1)), math.sin(a) * r)
		espiral = s:Lerp(espiral, smooth(phase(u, 0, 0.15)))
		return espiral:Lerp(SU.Portal, smooth(phase(u, 0.55, 1)))
	end
	if t < 1.95 then return SU.Portal end
	if t < 2.2 then
		local u = phase(t, 1.95, 2.2)
		return (SU.KickPoint + V3(0, 1.45, 0)):Lerp(SU.KickPoint, u * u) -- reaparece no ar e cai no pé
	end
	if t < SU.ImpactTime then return SU.KickPoint end
	return SU.KickPoint + SU_PUSH * easeOut(phase(t, SU.ImpactTime, SU.Duration))
end
function SU.BallVisible(t) return t < 1.35 or t >= 1.95 end
function SU.BallSpin(t)
	if t < 0.45 then return 0 end
	if t < SU.ImpactTime then return 8 end
	return 28
end
local SU_SINAL = {
	Root = { -4, 0, 0 }, Neck = { -12, 0, 0 },
	RShoulder = { 125, 0, -25 }, RElbow = { 95, 0, 0 }, LShoulder = { 0, 0, -15 },
}
local SU_POSE = {
	{ 0.00, {} },
	-- sinal de mão na frente do rosto, cabeça baixa
	{ 0.25, SU_SINAL },
	{ 1.20, { Root = { -4, 0, 0 }, Neck = { -8, 0, 0 },
		RShoulder = { 120, 0, -25 }, RElbow = { 95, 0, 0 }, LShoulder = { -20, 0, -30 } } },
	-- abre os braços quando a bola entra no torii
	{ 1.45, { Neck = { 5, 0, 0 }, RShoulder = { 10, 0, 55 }, LShoulder = { 10, 0, -55 } } },
	-- arma o chute de curva
	{ 1.90, { Root = { -6, 0, 0 }, Neck = { -8, 0, 0 }, LHip = { 25, 0, 0 }, LKnee = { -30, 0, 0 },
		RHip = { -50, 0, 10 }, RKnee = { -95, 0, 0 }, RShoulder = { -20, 0, 60 }, LShoulder = { 45, 0, -60 } } },
	{ 2.20, { Root = { -7, 0, 0 }, Neck = { -10, 0, 0 }, LHip = { 20, 0, 0 }, LKnee = { -28, 0, 0 },
		RHip = { 15, 0, -8 }, RKnee = { -40, 0, 0 }, RShoulder = { -25, 0, 62 }, LShoulder = { 48, 0, -65 } } },
	-- CHUTE: cruza a perna por dentro (efeito na bola), RASTEIRO — medido:
	-- com o quadril a 75° o pé passava 1.6 acima do gramado, a bola flutuava
	{ SU.ImpactTime, { Root = { -8, 0, 0 }, Neck = { -12, 0, 0 }, LKnee = { -25, 0, 0 },
		RHip = { 40, 0, -20 }, RKnee = { -8, 0, 0 }, RShoulder = { -30, 0, 65 }, LShoulder = { 50, 0, -70 } } },
	{ 2.90, { Root = { -4, 0, 0 }, Neck = { -6, 0, 0 }, LKnee = { -20, 0, 0 },
		RHip = { 75, 0, -32 }, RKnee = { -15, 0, 0 }, RShoulder = { -30, 0, 65 }, LShoulder = { 50, 0, -70 } } },
}
function SU.Pose(t) return samplePose(SU_POSE, t) end
function SU.Camera(t, rootPos, ballPos)
	if t < 0.45 then
		return V3(1.5, 0.8, -5), rootPos + V3(0, 1.2, 0), 45
	elseif t < 1.35 then
		local u = smooth(phase(t, 0.45, 1.35))
		return V3(7, 4, 8):Lerp(V3(6, 3.2, 6.5), u), V3(0, 0, -5), 60
	elseif t < 1.95 then
		local u = smooth(phase(t, 1.35, 1.95))
		return V3(1.5, -1.5, -11):Lerp(V3(1.2, -1.6, -9.5), u), rootPos + V3(0, 0.5, 0), 55
	elseif t < SU.ImpactTime then
		return V3(4, -2.3, -3.5), rootPos:Lerp(ballPos, 0.6), 55
	end
	local u = easeOut(phase(t, SU.ImpactTime, SU.Duration))
	return rootPos + V3(2.5, 1.5, 4.5):Lerp(V3(2, 1.2, 3.5), u), V3(0, 0, -10), 60 - 12 * u
end

-- ============================================================
-- 🌊 IMPULSO DE MARÉ (Tsunami Boost / ツナミブースト) — Água
-- ============================================================
-- Wiki: "um tsunami enorme cai no campo, o usuário surfa EM CIMA DA BOLA
-- como numa prancha; na crista ele salta da bola, deixando-a no ar, dá um
-- MORTAL e bate de bicicleta; a bola sai coberta por um véu d'água, numa
-- espiral aquática". Vídeo (Victory Road): onda gigante azul e branca
-- atravessando o estádio, ele no ar por cima da espuma, impacto com respingo
-- branco/azul.
-- A onda nasce atrás dele e ele sobe a face de TRÁS dela (a rampa) em cima
-- da bola, de lado (base de surfe), até a crista; salta, vira de costas pro
-- gol no ar e bate de bicicleta. A onda é desenhada pelo cliente com o MESMO
-- perfil (Onda) que a bola percorre aqui.
local MA = {}
Cutscenes.ImpulsoDeMare = MA
MA.Motor = "V2"
MA.Efeitos = "Mare"
MA.KickFoot = "Right"
MA.Duration = 3.3
MA.ImpactTime = 2.75
MA.TitleText = "IMPULSO DE MARÉ"
MA.Tema = {
	Titulo = { rgb(230, 250, 255), rgb(90, 190, 255), rgb(20, 90, 210) },
	Contorno = rgb(5, 30, 80), Flash = rgb(220, 245, 255),
	Tint = rgb(205, 230, 255), Saturation = 0.25, Contrast = 0.1, Brightness = 0,
}
MA.Phases = {
	Rise = { 0, 0.5 }, Hop = { 0.2, 0.45 }, Ride = { 0.45, 1.6 }, Leap = { 1.6, 1.95 },
	Flip = { 1.95, 2.6 }, Kick = { 2.6, MA.ImpactTime }, Impact = { MA.ImpactTime, MA.Duration },
	Break = { 1.75, 2.9 },
}
-- perfil da onda {z, y} a partir do pé dela (y = altura acima do gramado):
-- rampa de trás (índices 1..7, até a CRISTA) e o lábio que cai pra frente
-- ⚠️ v108 — ANIME (vídeo "Inazuma Eleven - Tsunami Boost", quadros a cada 0,5s):
-- a onda é GIGANTE, uma parede d'água que enche a tela (5-8s do vídeo). Era 10
-- studs de altura por 26 de largura; agora 1.55x mais alta, 1.3x mais funda e 44
-- de largura. A bola/o surfe seguem o mesmo perfil (recalcularMare), então a
-- subida pela rampa e a bicicleta acompanham sozinhas.
local MA_ESCALA_Y, MA_ESCALA_Z = 1.55, 1.3
MA.Onda = {}
for i, p in ipairs({
	{ 4.5, 0 }, { 3.3, 1.1 }, { 2.3, 2.9 }, { 1.45, 5 }, { 0.7, 7.2 }, { 0, 9 }, { -0.6, 10 },
	{ -1.6, 9.7 }, { -2.4, 8.6 }, { -2.9, 7.2 },
}) do
	MA.Onda[i] = { p[1] * MA_ESCALA_Z, p[2] * MA_ESCALA_Y }
end
MA.OndaCrista = 7
MA.OndaLargura = 44
function MA.OndaOrigem(t) return V3(0, CAL.Chao, -4.5 - 0.8 * phase(t, 0.45, 1.8)) end
function MA.OndaAltura(t)
	if t < 1.75 then return easeOut(phase(t, 0, 0.5)) end
	return 1 - 0.75 * smooth(phase(t, 1.75, 2.9)) -- quebra depois que ele salta
end
-- ponto (e normal) na rampa de trás: s = 0 no pé da onda, 1 na crista
function MA.Superficie(s, t)
	local h = MA.OndaAltura(t)
	local o = MA.OndaOrigem(t)
	local pts, lens, total = {}, {}, 0
	for i = 1, MA.OndaCrista do
		local p = MA.Onda[i]
		pts[i] = V3(0, p[2] * h, p[1])
	end
	for i = 1, #pts - 1 do
		lens[i] = (pts[i + 1] - pts[i]).Magnitude
		total += lens[i]
	end
	local alvo = math.clamp(s, 0, 1) * total
	for i = 1, #pts - 1 do
		if alvo <= lens[i] or i == #pts - 1 then
			local u = lens[i] > 0 and math.clamp(alvo / lens[i], 0, 1) or 0
			local d = pts[i + 1] - pts[i]
			local n = V3(0, -d.Z, d.Y)
			if n.Magnitude < 1e-3 then n = V3(0, 1, 0) end
			return o + pts[i]:Lerp(pts[i + 1], u), n.Unit
		end
		alvo -= lens[i]
	end
	return o, V3(0, 1, 0)
end
-- em pé EM CIMA da bola: centro da bola + raio + altura do quadril (calibrada)
local PES_ATE_ROOT = 0.85 + 2.9
local function bolaNaRampa(t)
	local p, n = MA.Superficie(smooth(phase(t, 0.45, 1.6)), t)
	return p + n * CAL.Raio
end
local MA_B_PE, MA_B_CRISTA, MA_R_TOPO, MA_R_CHUTE, MA_B_SOLTA
local function recalcularMare()
	PES_ATE_ROOT = CAL.Raio - CAL.Chao
	MA_B_PE = bolaNaRampa(0.45)
	MA_B_CRISTA = bolaNaRampa(1.6)
	MA_R_TOPO = MA_B_CRISTA + V3(0, 6.2, -0.8)
	MA_R_CHUTE = MA_R_TOPO + V3(0, -0.4, -0.6)
	MA_B_SOLTA = MA_B_CRISTA + V3(0, 5.2, -3.0)
	-- medido: a bola colada no pé da bicicleta ficou a 0.12 disto
	MA.KickPoint = MA_R_CHUTE + V3(-0.5, 0.3, -2.2)
end
recalcularMare()
table.insert(recalculos, recalcularMare)
MA.KickContactDir = V3(0, -0.4, -0.92).Unit
local MA_PUSH = V3(0, -0.3, -1).Unit * 1.8
function MA.RootPosition(t)
	if t < 0.2 then
		return V3(0, -0.4 * smooth(phase(t, 0, 0.2)), 0)
	elseif t < 0.45 then
		local u = phase(t, 0.2, 0.45)
		local alvo = MA_B_PE + V3(0, PES_ATE_ROOT, 0)
		return V3(0, -0.4, 0):Lerp(alvo, smooth(u)) + V3(0, math.sin(u * math.pi) * 0.8, 0)
	elseif t < 1.6 then
		return bolaNaRampa(t) + V3(0, PES_ATE_ROOT, 0)
	elseif t < 1.95 then
		return (MA_B_CRISTA + V3(0, PES_ATE_ROOT, 0)):Lerp(MA_R_TOPO, easeOut(phase(t, 1.6, 1.95)))
	elseif t < MA.ImpactTime then
		return MA_R_TOPO:Lerp(MA_R_CHUTE, smooth(phase(t, 1.95, MA.ImpactTime)))
	end
	return MA_R_CHUTE
end
local MA_YAW = { { 0, 0 }, { 0.35, 0 }, { 0.6, 80 }, { 1.6, 80 }, { 2.0, 180 }, { 3.3, 180 } }
local MA_PITCH = { { 0, 0 }, { 1.95, 0 }, { 2.3, 40 }, { 2.6, 85 }, { MA.ImpactTime, 110 }, { 3.3, 118 } }
function MA.RootCFrame(t)
	return CFrame.new(MA.RootPosition(t)) * CFrame.Angles(0, rad(sample(MA_YAW, t)), 0)
		* CFrame.Angles(rad(sample(MA_PITCH, t)), 0, 0)
end
function MA.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.12 then return s end
	if t < 0.45 then return s:Lerp(MA_B_PE, smooth(phase(t, 0.12, 0.42))) end
	if t < 1.6 then return bolaNaRampa(t) end
	if t < 2.05 then return MA_B_CRISTA:Lerp(MA_B_SOLTA, easeOut(phase(t, 1.6, 2.05))) end
	if t < MA.ImpactTime then return MA_B_SOLTA:Lerp(MA.KickPoint, smooth(phase(t, 2.05, MA.ImpactTime))) end
	return MA.KickPoint + MA_PUSH * easeOut(phase(t, MA.ImpactTime, MA.Duration))
end
function MA.BallSpin(t)
	if t < 0.45 then return 2 end
	if t < 1.6 then return 9 end
	if t < MA.ImpactTime then return 5 end
	return 30
end
local MA_POSE = {
	{ 0.00, {} },
	{ 0.18, { Root = { -15, 0, 0 }, RHip = { 45, 0, 0 }, LHip = { 45, 0, 0 }, RKnee = { -80, 0, 0 }, LKnee = { -80, 0, 0 },
		RShoulder = { -30, 0, 20 }, LShoulder = { -30, 0, -20 } } },
	{ 0.40, { RHip = { 30, 0, 0 }, LHip = { 30, 0, 0 }, RKnee = { -60, 0, 0 }, LKnee = { -60, 0, 0 },
		RShoulder = { 40, 0, 50 }, LShoulder = { 40, 0, -50 } } },
	-- base de surfe em cima da bola (de lado, olhando pro gol)
	{ 0.60, { Root = { -15, 0, 0 }, Waist = { 0, -15, 0 }, Neck = { 0, -55, 0 },
		RHip = { 35, 0, 28 }, LHip = { 35, 0, -28 }, RKnee = { -55, 0, 0 }, LKnee = { -55, 0, 0 },
		RShoulder = { 15, 0, 80 }, LShoulder = { 15, 0, -80 }, RElbow = { 15, 0, 0 }, LElbow = { 15, 0, 0 } } },
	{ 1.10, { Root = { -20, 0, 0 }, Waist = { 0, -15, 0 }, Neck = { 0, -50, 0 },
		RHip = { 45, 0, 28 }, LHip = { 45, 0, -28 }, RKnee = { -70, 0, 0 }, LKnee = { -70, 0, 0 },
		RShoulder = { 30, 0, 70 }, LShoulder = { 0, 0, -95 }, RElbow = { 15, 0, 0 }, LElbow = { 15, 0, 0 } } },
	-- comprime pra saltar da crista
	{ 1.50, { Root = { -25, 0, 0 }, Neck = { 0, -40, 0 }, RHip = { 70, 0, 10 }, LHip = { 70, 0, -10 },
		RKnee = { -110, 0, 0 }, LKnee = { -110, 0, 0 }, RShoulder = { -40, 0, 30 }, LShoulder = { -40, 0, -30 } } },
	-- salta com os braços pra cima
	{ 1.80, { Root = { 5, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 5, 0, 0 }, LHip = { 5, 0, 0 },
		RKnee = { -10, 0, 0 }, LKnee = { -10, 0, 0 }, RShoulder = { 165, 0, 20 }, LShoulder = { 165, 0, -20 } } },
	-- mortal: grupado
	{ 2.15, { Neck = { -10, 0, 0 }, RHip = { 85, 0, 0 }, LHip = { 85, 0, 0 }, RKnee = { -125, 0, 0 }, LKnee = { -125, 0, 0 },
		RShoulder = { 60, 0, 25 }, LShoulder = { 60, 0, -25 }, RElbow = { 60, 0, 0 }, LElbow = { 60, 0, 0 } } },
	-- arma a bicicleta
	{ 2.50, { Neck = { 25, 0, 0 }, RHip = { 100, 0, 0 }, RKnee = { -95, 0, 0 }, LHip = { 35, 0, 0 }, LKnee = { -45, 0, 0 },
		RShoulder = { 0, 0, 80 }, LShoulder = { 0, 0, -80 } } },
	-- BICICLETA: a direita passa por cima, a esquerda desce (tesoura)
	{ MA.ImpactTime, { Neck = { 20, 0, 0 }, RHip = { 150, 0, 0 }, RKnee = { -5, 0, 0 }, LHip = { -20, 0, 0 }, LKnee = { -35, 0, 0 },
		RShoulder = { -40, 0, 70 }, LShoulder = { -40, 0, -70 } } },
	{ 3.30, { Neck = { 15, 0, 0 }, RHip = { 140, 0, 0 }, RKnee = { -8, 0, 0 }, LHip = { -25, 0, 0 }, LKnee = { -40, 0, 0 },
		RShoulder = { -40, 0, 70 }, LShoulder = { -40, 0, -70 } } },
}
function MA.Pose(t) return samplePose(MA_POSE, t) end
function MA.Camera(t, rootPos, ballPos)
	if t < 0.45 then
		-- de frente e de baixo: a onda subindo atrás dele
		return V3(-8, -1.8, -10), V3(0, 3, 1), 70
	elseif t < 1.6 then
		-- acompanha de lado (ele surfa de frente pra essa câmera) — ⚠️ v108: mais
		-- aberta pra caber a onda gigante e os anéis d'água atrás dele
		-- ⚠️ v113 (vídeo a 0,2s): a -12 a câmera ficava DENTRO da onda (44 de
		-- largura), debaixo do lábio — o jogador aparecia através de camadas de
		-- água. Agora fica fora dela, de lado, com a lente fechada: plano limpo
		-- dele surfando na bola de braços abertos (12.0-12.4s do vídeo)
		return rootPos + V3(-27, 3.5, -3), rootPos + V3(0, -0.5, 0), 44
	elseif t < 1.95 then
		return rootPos + V3(2.5, -5, -4), rootPos, 66
	elseif t < MA.ImpactTime then
		local u = smooth(phase(t, 1.95, MA.ImpactTime))
		return rootPos + V3(8.5, 0.5, -1):Lerp(V3(7, 0.3, -2), u), rootPos:Lerp(ballPos, 0.5), 58
	end
	-- impacto: do lado do gol, a bola vindo na direção da câmera
	local u = easeOut(phase(t, MA.ImpactTime, MA.Duration))
	return MA.KickPoint + V3(2.5, -1.5, -5):Lerp(V3(2, -1.2, -4), u), MA.KickPoint + V3(0, 0.3, 1.2), 62 - 14 * u
end

-- ============================================================
-- ❄️ FÚRIA GLACIAL (Freeze Shot / フリーズショット) — Gelo
-- ============================================================
-- Wiki: "o usuário fica de BRAÇOS CRUZADOS com a bola debaixo do pé
-- direito. O campo CONGELA, ele puxa a perna direita pra trás e chuta. A bola
-- racha o campo congelado, cercada de redemoinhos de gelo". Chute PESADO:
-- sem pulo, preparo lento, perna bem pra trás.
-- ⚠️ v113 — REVISÃO PELO VÍDEO ("Inazuma Eleven - Freeze Shot", quadros a cada
-- 0,2s). O anime NÃO é um chute parado: braços cruzados com a bola no pé
-- (4.4s), o campo congela (4.8-5.2s), ele toca a bola pra frente e CORRE
-- (5.4s), MERGULHA rente ao gelo (5.6-6.0s), apoia as mãos e dá um MORTAL PRA
-- FRENTE com as pernas por cima (6.2-6.6s), cai já girando a perna e chuta
-- (6.8-7.0s); a bola vai dentro de redemoinhos de gelo (7.2s+). Antes ele só
-- descruzava e puxava a perna, parado.
--   0.00-0.30 cruza os braços;  0.30-1.05 campo congela;  1.05-1.30 toca a bola;
--   1.30-1.62 corre;  1.62-1.92 mergulha;  1.92-2.34 mortal;  2.34-2.60 CHUTE.
local GL = {}
Cutscenes.FuriaGlacial = GL
GL.Motor = "V2"
GL.Efeitos = "Gelo"
GL.KickFoot = "Right"
GL.Duration = 3.2
GL.ImpactTime = 2.6
GL.TitleText = "FÚRIA GLACIAL"
GL.Tema = {
	Titulo = { rgb(255, 255, 255), rgb(170, 230, 255), rgb(80, 160, 230) },
	Contorno = rgb(10, 40, 80), Flash = rgb(230, 250, 255),
	Tint = rgb(215, 235, 255), Saturation = -0.15, Contrast = 0.15, Brightness = 0.02,
}
GL.Phases = {
	Cross = { 0, 0.3 }, Freeze = { 0.3, 1.05 }, Run = { 1.3, 1.62 }, Dive = { 1.62, 1.92 },
	Flip = { 1.92, 2.34 }, Windup = { 1.62, 2.45 },
	Kick = { 2.45, GL.ImpactTime }, Impact = { GL.ImpactTime, GL.Duration },
}
-- ⚠️ v122 — PEDIDO: "a Fúria Glacial não pode cair no chão: dá um MORTAL e chuta".
-- Antes ele mergulhava rente ao gelo e fazia parada de mão; agora corre, SALTA e
-- dá o mortal pra frente no AR (grupado), cai agachado e chuta.
local GL_ROOT = {
	{ 0, V3(0, 0, 0) }, { 1.05, V3(0, 0, 0) }, { 1.3, V3(0, -0.1, -0.4) },
	{ 1.62, V3(0, -0.08, -2.4) },  -- corre inclinado (medido: -0.35 furava o gelo)
	{ 1.74, V3(0, 1.4, -3.3) },    -- salta
	{ 1.92, V3(0, 3.3, -4.3) },
	{ 2.08, V3(0, 3.6, -5.1) },    -- topo do mortal
	{ 2.22, V3(0, 2.2, -5.8) },
	{ 2.34, V3(0, 0.15, -6.3) },   -- cai agachado
	{ 2.45, V3(0, 0, -6.4) },
	{ GL.ImpactTime, V3(0, 0.04, -6.6) }, { 3.2, V3(0, 0.07, -6.9) },
}
-- mortal PRA FRENTE (ângulo negativo em X = a cabeça vai pra frente e pra baixo)
local GL_PITCH = {
	{ 0, 0 }, { 1.3, 0 }, { 1.62, -15 }, { 1.74, -45 }, { 1.92, -150 }, { 2.08, -245 },
	{ 2.22, -320 }, { 2.34, -352 }, { 2.45, -360 }, { 3.2, -360 },
}
function GL.RootPosition(t) return sample(GL_ROOT, t) end
function GL.RootCFrame(t)
	return CFrame.new(GL.RootPosition(t)) * CFrame.Angles(rad(sample(GL_PITCH, t)), 0, 0)
end
GL.PeSobreBola = V3(0.6, -2.05, -1.5) -- a bola parada debaixo da sola direita
GL.KickPoint = V3(0.3, -2.05, -8.8)
table.insert(recalculos, function()
	GL.PeSobreBola = V3(0.6, CAL.Chao + CAL.Raio, -1.5)
	GL.KickPoint = V3(0.3, CAL.Chao + CAL.Raio, -8.8)
end)
GL.KickContactDir = V3(0, 0.28, -1).Unit
local GL_PUSH = V3(0, 0.08, -1).Unit * 1.8
function GL.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.08 then return s end
	if t < 0.3 then return s:Lerp(GL.PeSobreBola, smooth(phase(t, 0.08, 0.3))) end
	if t < 1.15 then return GL.PeSobreBola end
	-- o toque: a bola desliza no gelo e para onde ele vai cair do mortal
	if t < 1.95 then return GL.PeSobreBola:Lerp(GL.KickPoint, easeOut(phase(t, 1.15, 1.95))) end
	if t < GL.ImpactTime then return GL.KickPoint end
	return GL.KickPoint + GL_PUSH * easeOut(phase(t, GL.ImpactTime, GL.Duration))
end
function GL.BallSpin(t)
	if t < 1.15 then return 0 end
	if t < 1.95 then return 8 end
	if t < GL.ImpactTime then return 2 end
	return 26
end
local GL_CRUZADO = {
	Root = { 3, 0, 0 }, Neck = { -6, 0, 0 },
	-- (medido: com 95/-85 a sola afundava 0.3 no topo da bola)
	RHip = { 105, 0, 8 }, RKnee = { -92, 0, 0 }, LKnee = { -8, 0, 0 },
	RShoulder = { 75, 0, -30 }, RElbow = { 110, 0, 0 }, LShoulder = { 70, 0, 30 }, LElbow = { 110, 0, 0 },
}
-- braços esticados "pra cima" em relação ao tronco = pra frente no mergulho e
-- apoiados no gelo de cabeça pra baixo
local GL_BRACOS_APOIO = { RShoulder = { 172, 0, 12 }, LShoulder = { 172, 0, -12 }, RElbow = { 5, 0, 0 }, LElbow = { 5, 0, 0 } }
local function comBracos(pose)
	for k, v in pairs(GL_BRACOS_APOIO) do pose[k] = v end
	return pose
end
local GL_POSE = {
	{ 0.00, {} },
	{ 0.30, GL_CRUZADO },
	{ 1.05, GL_CRUZADO },
	-- descruza e toca a bola pra frente com a direita
	{ 1.22, { Neck = { -6, 0, 0 }, RHip = { 40, 0, 0 }, RKnee = { -15, 0, 0 }, LKnee = { -15, 0, 0 },
		RShoulder = { -20, 0, 30 }, LShoulder = { 20, 0, -30 } } },
	-- corre (braço oposto à perna)
	{ 1.42, { Root = { -12, 0, 0 }, Neck = { 10, 0, 0 }, RHip = { -30, 0, 0 }, RKnee = { -60, 0, 0 }, LHip = { 55, 0, 0 },
		LKnee = { -70, 0, 0 }, RShoulder = { 45, 0, 10 }, RElbow = { 80, 0, 0 }, LShoulder = { -40, 0, -10 }, LElbow = { 80, 0, 0 } } },
	{ 1.62, { Root = { -8, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 45, 0, 0 }, RKnee = { -40, 0, 0 }, LHip = { -25, 0, 0 },
		LKnee = { -50, 0, 0 }, RShoulder = { 120, 0, 15 }, RElbow = { 20, 0, 0 }, LShoulder = { 120, 0, -15 }, LElbow = { 20, 0, 0 } } },
	-- salto: os braços sobem pra puxar o mortal
	{ 1.74, { Neck = { 20, 0, 0 }, RHip = { -10, 0, 4 }, RKnee = { -20, 0, 0 }, LHip = { 25, 0, -4 }, LKnee = { -40, 0, 0 },
		RShoulder = { 165, 0, 20 }, LShoulder = { 165, 0, -20 } } },
	-- GRUPADO no ar: pernas no peito, braços abraçando (R6: perna reta = carpado)
	{ 1.90, { Neck = { 30, 0, 0 }, RHip = { 115, 0, 10 }, RKnee = { -115, 0, 0 }, LHip = { 115, 0, -10 }, LKnee = { -115, 0, 0 },
		RShoulder = { 80, 0, 30 }, LShoulder = { 80, 0, -30 }, RElbow = { 60, 0, 0 }, LElbow = { 60, 0, 0 } } },
	{ 2.12, { Neck = { 30, 0, 0 }, RHip = { 118, 0, 10 }, RKnee = { -118, 0, 0 }, LHip = { 118, 0, -10 }, LKnee = { -118, 0, 0 },
		RShoulder = { 85, 0, 30 }, LShoulder = { 85, 0, -30 }, RElbow = { 60, 0, 0 }, LElbow = { 60, 0, 0 } } },
	-- abre pra cair: braços abrem, pernas descem
	{ 2.25, { Neck = { 10, 0, 0 }, RHip = { 55, 0, 5 }, RKnee = { -60, 0, 0 }, LHip = { 65, 0, -5 }, LKnee = { -50, 0, 0 },
		RShoulder = { 110, 0, 55 }, LShoulder = { 110, 0, -55 } } },
	-- cai agachado já armando a direita pra trás (6.8s)
	{ 2.34, { Root = { -10, 0, 0 }, Neck = { -10, 0, 0 }, RHip = { 20, 0, 5 }, RKnee = { -100, 0, 0 }, LHip = { 70, 0, 0 },
		LKnee = { -95, 0, 0 }, RShoulder = { -20, 0, 70 }, LShoulder = { 50, 0, -70 } } },
	{ 2.45, { Root = { -5, 0, 0 }, Waist = { 0, -15, 0 }, Neck = { -10, 0, 0 }, LHip = { 35, 0, 0 }, LKnee = { -40, 0, 0 },
		RHip = { -55, 0, 5 }, RKnee = { -105, 0, 0 }, RShoulder = { -25, 0, 65 }, LShoulder = { 55, 0, -75 } } },
	-- CHUTE rente ao gelo (medido: com o quadril a 80° o pé passava 1.6 acima
	-- do gramado e a bola saía flutuando)
	{ GL.ImpactTime, { Root = { -10, 0, 0 }, Waist = { 0, 15, 0 }, Neck = { -12, 0, 0 }, LKnee = { -30, 0, 0 },
		RHip = { 42, 0, -5 }, RKnee = { -8, 0, 0 }, RShoulder = { -40, 0, 60 }, LShoulder = { 60, 0, -60 } } },
	{ 3.20, { Root = { -12, 0, 0 }, Waist = { 0, 15, 0 }, Neck = { -8, 0, 0 }, LKnee = { -28, 0, 0 },
		RHip = { 80, 0, -5 }, RKnee = { -12, 0, 0 }, RShoulder = { -40, 0, 60 }, LShoulder = { 60, 0, -60 } } },
}
function GL.Pose(t) return samplePose(GL_POSE, t) end
function GL.Camera(t, rootPos, ballPos)
	if t < 0.55 then
		-- de frente e baixo: braços cruzados, pé em cima da bola (4.4s)
		return V3(2, -1.8, -4.5), V3(0, -0.8, -0.5), 55
	elseif t < 1.05 then
		-- aberta: o campo congelando em volta dele (4.8-5.2s)
		local u = smooth(phase(t, 0.55, 1.05))
		return V3(0, 16 - 4 * u, 10 - 3 * u), V3(0, -2, -2), 60
	elseif t < 1.92 then
		-- de lado, acompanhando a corrida e o mergulho rente ao gelo (5.4-6.0s)
		local u = smooth(phase(t, 1.05, 1.92))
		return rootPos + V3(11 - 2 * u, 0.2, 0.5), rootPos + V3(0, -0.8, -1.5), 58
	elseif t < 2.34 then
		-- de lado e baixo, como no anime (6.2-6.6s): o mortal inteiro de perfil
		-- (de frente os braços apoiados sumiam atrás do corpo)
		local u = smooth(phase(t, 1.92, 2.34))
		return rootPos + V3(10, -1.2, -1):Lerp(V3(9, -0.8, -2.5), u), rootPos + V3(0, 0.2, -0.5), 60
	elseif t < GL.ImpactTime then
		return GL.KickPoint + V3(1.5, -0.3, -4), rootPos, 58
	end
	-- impacto (7.0-7.6s do anime): na frente e do lado da bola, ela explodindo em
	-- redemoinhos de gelo com ele logo atrás. (De trás, colada nas costas, o
	-- corpo dele escondia a bola.)
	local u = easeOut(phase(t, GL.ImpactTime, GL.Duration))
	return GL.KickPoint + V3(4.5, 1, -6):Lerp(V3(3.8, 0.8, -7.5), u), ballPos:Lerp(rootPos, 0.3), 60 - 10 * u
end

-- ============================================================
-- 🔺 ZONA MORTA (Death Zone / デスゾーン) — Void
-- ============================================================
-- Wiki (IE1): o do centro corre, os outros dois aparecem atrás e saltam; os
-- três sobem GIRANDO e formam um TRIÂNGULO no ar com a bola no meio, com
-- raios roxos finos entre eles; a bola absorve a energia do triângulo e os
-- três fecham e batem nela, que sai coberta de energia roxa escura.
-- Solo: os outros dois vértices são SOMBRAS roxas do próprio chutador
-- (Clones). O chutador fica no vértice de TRÁS (pra bola sair pro gol).
local ZM = {}
Cutscenes.ZonaMorta = ZM
ZM.Motor = "V2"
ZM.Efeitos = "ZonaMorta"
ZM.KickFoot = "Right"
ZM.Duration = 3.4
ZM.ImpactTime = 2.85
ZM.TitleText = "ZONA MORTA"
ZM.Tema = {
	Titulo = { rgb(230, 190, 255), rgb(140, 50, 220), rgb(60, 0, 110) },
	Contorno = rgb(15, 0, 25), Flash = rgb(200, 120, 255),
	Tint = rgb(205, 180, 235), Saturation = 0, Contrast = 0.25, Brightness = -0.08,
}
ZM.Phases = {
	Flick = { 0, 0.35 }, Spawn = { 0.25, 0.6 }, Crouch = { 0.65, 0.8 }, Jump = { 0.8, 1.9 },
	-- ⚠️ v108 — quadro a quadro do anime (vídeo do usuário, a cada 0.5s): o
	-- triângulo ENCOLHE GIRANDO em volta da bola antes do chute — o fechamento
	-- ficou mais longo (era 2.55) pra caber uma volta inteira.
	Triangle = { 1.9, 2.3 }, Close = { 2.3, ZM.ImpactTime }, Kick = { 2.6, ZM.ImpactTime },
	Impact = { ZM.ImpactTime, ZM.Duration },
}
ZM.Centro = V3(0, 14, -3.5) -- onde a bola fica no meio do triângulo
ZM.Vertices = {
	[0] = ZM.Centro + V3(0, 0.9, 3.4), -- chutador (atrás)
	[1] = ZM.Centro + V3(-3.0, 1.4, -1.7), -- sombra da esquerda
	[2] = ZM.Centro + V3(3.0, 1.4, -1.7), -- sombra da direita
}
ZM.Chao = { [0] = V3(0, 0, 0), [1] = V3(-3, 0, 1.6), [2] = V3(3, 0, 1.6) }
-- no chute os três fecham até 85% da distância (medido: com 72% os três pés
-- entravam 0.3-0.8 dentro da bola; com 85% as solas encostam na superfície)
local ZM_FECHA = 0.85

local function zmPos(i, t)
	local chao, v = ZM.Chao[i], ZM.Vertices[i]
	if t < 0.65 then return chao end
	if t < 0.8 then return chao + V3(0, -0.7 * smooth(phase(t, 0.65, 0.8)), 0) end
	if t < 1.9 then
		local u = easeOut(phase(t, 0.8, 1.9))
		return (chao + V3(0, -0.7, 0)):Lerp(v, u)
	end
	if t < 2.3 then
		return v + V3(0, math.sin((t - 1.9) * 6 + i) * 0.12, 0)
	end
	-- ⚠️ v108: fecha GIRANDO uma volta inteira em volta da bola (termina no
	-- mesmo lugar, então o chute sai pro mesmo lado)
	local u = smooth(phase(t, 2.3, ZM.ImpactTime))
	local rel = CFrame.Angles(0, 2 * math.pi * u, 0):VectorToWorldSpace(v - ZM.Centro)
	return ZM.Centro + rel * (1 + (ZM_FECHA - 1) * u)
end
local function zmYaw(i, t)
	-- dois giros no ar, terminando de frente pra bola (sombras no sentido contrário)
	local final = yawOlhando(ZM.Vertices[i], ZM.Centro)
	local inicio = i == 0 and 0 or final
	local voltas = (i == 1 and 1 or -1) * 4 * math.pi
	if t < 0.8 then return inicio end
	local u = smooth(phase(t, 0.8, 1.9))
	-- ⚠️ v108: na volta do fechamento continua de frente pra bola
	local giro = t > 2.3 and 2 * math.pi * smooth(phase(t, 2.3, ZM.ImpactTime)) or 0
	return inicio + (final - inicio) * u + voltas * u + giro
end
function ZM.RootPosition(t) return zmPos(0, t) end
function ZM.RootCFrame(t) return CFrame.new(zmPos(0, t)) * CFrame.Angles(0, zmYaw(0, t), 0) end
-- A bola fica no MEIO dos três pés (não colada só no pé do chutador)
ZM.KickPoint = ZM.Centro
ZM.KickContactDir = V3(0, -0.25, -1).Unit
ZM.ColarNoPe = false
local ZM_PUSH = V3(0, -0.2, -1).Unit * 1.6
function ZM.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.14 then return s end
	if t < 1.2 then return s:Lerp(ZM.Centro, easeOut(phase(t, 0.14, 1.2))) end
	if t < 2.55 then return ZM.Centro + V3(0, math.sin((t - 1.2) * 4) * 0.15 * (1 - phase(t, 2.3, 2.55)), 0) end
	if t < ZM.ImpactTime then return ZM.Centro end
	return ZM.KickPoint + ZM_PUSH * easeOut(phase(t, ZM.ImpactTime, ZM.Duration))
end
function ZM.BallSpin(t)
	if t < 0.14 then return 0 end
	if t < ZM.ImpactTime then return 10 end
	return 30
end
local ZM_POSE = {
	{ 0.00, {} },
	{ 0.12, { Root = { -5, 0, 0 }, RHip = { -25, 0, 0 }, RKnee = { -30, 0, 0 }, LKnee = { -10, 0, 0 } } },
	{ 0.28, { Root = { 6, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 60, 0, 0 }, RKnee = { -15, 0, 0 }, LKnee = { -12, 0, 0 },
		RShoulder = { -20, 0, 35 }, LShoulder = { 20, 0, -35 } } },
	{ 0.60, { Neck = { 40, 0, 0 }, RShoulder = { 0, 0, 30 }, LShoulder = { 0, 0, -30 } } },
	{ 0.78, { Root = { -22, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { 55, 0, 0 }, LHip = { 55, 0, 0 },
		RKnee = { -95, 0, 0 }, LKnee = { -95, 0, 0 }, RShoulder = { -40, 0, 30 }, LShoulder = { -40, 0, -30 } } },
	-- sobe girando, grupado
	{ 1.00, { Neck = { 10, 0, 0 }, RHip = { 70, 0, 0 }, LHip = { 60, 0, 0 }, RKnee = { -110, 0, 0 }, LKnee = { -100, 0, 0 },
		RShoulder = { 50, 0, -25 }, LShoulder = { 50, 0, 25 }, RElbow = { 100, 0, 0 }, LElbow = { 100, 0, 0 } } },
	{ 1.70, { Neck = { 10, 0, 0 }, RHip = { 70, 0, 0 }, LHip = { 60, 0, 0 }, RKnee = { -110, 0, 0 }, LKnee = { -100, 0, 0 },
		RShoulder = { 50, 0, -25 }, LShoulder = { 50, 0, 25 }, RElbow = { 100, 0, 0 }, LElbow = { 100, 0, 0 } } },
	-- abre no vértice do triângulo, braços abertos canalizando
	{ 2.00, { Root = { -10, 0, 0 }, Neck = { -15, 0, 0 }, RHip = { 20, 0, 15 }, LHip = { 20, 0, -15 },
		RKnee = { -30, 0, 0 }, LKnee = { -30, 0, 0 }, RShoulder = { 20, 0, 95 }, LShoulder = { 20, 0, -95 } } },
	{ 2.55, { Root = { -15, 0, 0 }, Neck = { -18, 0, 0 }, LHip = { 30, 0, 0 }, LKnee = { -40, 0, 0 },
		RHip = { -40, 0, 5 }, RKnee = { -100, 0, 0 }, RShoulder = { 10, 0, 90 }, LShoulder = { 10, 0, -90 } } },
	-- os três batem juntos
	{ ZM.ImpactTime, { Root = { 5, 0, 0 }, Neck = { -15, 0, 0 }, LHip = { -15, 0, 0 }, LKnee = { -40, 0, 0 },
		RHip = { 95, 0, 0 }, RKnee = { -5, 0, 0 }, RShoulder = { -30, 0, 70 }, LShoulder = { 40, 0, -80 } } },
	{ 3.40, { Root = { 8, 0, 0 }, Neck = { -12, 0, 0 }, LHip = { -18, 0, 0 }, LKnee = { -42, 0, 0 },
		RHip = { 100, 0, 0 }, RKnee = { -8, 0, 0 }, RShoulder = { -30, 0, 70 }, LShoulder = { 40, 0, -80 } } },
}
-- pose das sombras: paradas até pular (surgem da fumaça), depois o mesmo
-- movimento do chutador; a da direita chuta com a esquerda (espelhada)
local ZM_POSE_SOMBRA_CHAO = { Neck = { -10, 0, 0 }, RShoulder = { 0, 0, 12 }, LShoulder = { 0, 0, -12 } }
function ZM.Pose(t) return samplePose(ZM_POSE, t) end
ZM.Clones = {
	Quantidade = 2,
	Cor = rgb(120, 40, 200),
	CFrame = function(i, t) return CFrame.new(zmPos(i, t)) * CFrame.Angles(0, zmYaw(i, t), 0) end,
	Pose = function(i, t)
		local pose = t < 0.62 and samplePose({ { 0, ZM_POSE_SOMBRA_CHAO } }, 0) or samplePose(ZM_POSE, math.max(t, 0.62))
		return i == 2 and espelharPose(pose) or pose
	end,
	Alpha = function(_i, t)
		if t < 0.25 then return 0 end
		if t < 0.6 then return smooth(phase(t, 0.25, 0.6)) end
		if t < 2.95 then return 1 end
		return 1 - smooth(phase(t, 2.95, 3.3))
	end,
}
function ZM.Camera(t, rootPos, ballPos)
	if t < 0.35 then
		return V3(4, -1.8, -6.5), rootPos:Lerp(ballPos, 0.4), 60
	elseif t < 0.8 then
		-- de trás, aberto: as sombras surgindo dos lados
		return V3(0, 2.5, 11), V3(0, 0.5, 0), 60
	elseif t < 1.9 then
		-- de baixo, olhando os três subirem girando
		return V3(5.5, -2, -3.5), V3(0, rootPos.Y * 0.8, -2), 70
	elseif t < 2.3 then
		-- ⚠️ v108: de baixo, o triângulo inteiro no céu roxo (igual ao anime)
		local u = smooth(phase(t, 1.9, 2.3))
		return ZM.Centro + V3(1.5, -9 + 1.5 * u, 2.5), ZM.Centro, 72
	elseif t < ZM.ImpactTime then
		-- os três girando em volta da esfera de energia (anime 16.0-17.6s)
		-- ⚠️ v113: de cima e mais longe. A 8 studs, no meio da volta as sombras
		-- passavam coladas na câmera e tampavam a esfera
		local u = smooth(phase(t, 2.3, ZM.ImpactTime))
		return ZM.Centro + V3(2, 9 - 1.5 * u, 10 - 2 * u), ZM.Centro, 58
	end
	-- impacto: de frente e de baixo, a bola vindo pra câmera (anime 17.8-18.2s)
	-- ⚠️ v113: mais longe — a 7 studs a esfera e as pernas das sombras enchiam a tela
	local u = easeOut(phase(t, ZM.ImpactTime, ZM.Duration))
	return ZM.Centro + V3(-4, -5.5, -13):Lerp(V3(-3.5, -4.8, -11), u), ballPos, 62 - 12 * u
end

-- ============================================================
-- 🌌 GALÁXIA (The Galaxy / ザ・ギャラクシー) — Luz
-- ============================================================
-- Wiki: um deles carrega a mão com energia VERDE e SOCA o campo (energia
-- amarela, raios verdes); uma MÃO VERDE gigante sobe do campo, fecha e leva
-- os jogadores até a GALÁXIA; a mão abre e eles chutam a bola de volta pra
-- Terra, que desce como um METEORO.
-- Solo: soco no chão, a mão sobe e fecha em volta dele e da bola, leva os
-- dois pro espaço (esfera de estrelas, planetas, nebulosa), abre, ele passa
-- por cima da bola e bate pra BAIXO. O céu volta ao normal no fim.
local GA = {}
Cutscenes.Galaxia = GA
GA.Motor = "V2"
GA.Efeitos = "Galaxia"
GA.KickFoot = "Right"
GA.Duration = 3.6
GA.ImpactTime = 3.05
GA.TitleText = "GALÁXIA"
GA.Tema = {
	Titulo = { rgb(255, 255, 230), rgb(170, 255, 190), rgb(60, 200, 255) },
	Contorno = rgb(10, 20, 60), Flash = rgb(255, 255, 240),
	Tint = rgb(220, 230, 255), Saturation = 0.35, Contrast = 0.15, Brightness = 0,
}
GA.Phases = {
	Charge = { 0, 0.55 }, Punch = { 0.55, 0.7 }, HandRise = { 0.7, 1.1 }, HandClose = { 1.1, 1.45 },
	Lift = { 1.3, 2.0 }, Space = { 1.45, 3.35 }, HandOpen = { 2.0, 2.35 }, Float = { 2.0, 2.5 },
	Kick = { 2.85, GA.ImpactTime }, Impact = { GA.ImpactTime, GA.Duration },
}
GA.AlturaEspaco = 17
function GA.Elevacao(t) -- quanto a mão já subiu
	return GA.AlturaEspaco * smooth(phase(t, 1.3, 2.0))
end
local GA_R_TOPO = V3(0, GA.AlturaEspaco + 3.8, -0.2)
GA.KickPoint = V3(0.46, GA.AlturaEspaco + 1.25, -3.05) -- medido: pé em (0.46, +1.97, -2.13)
GA.KickContactDir = V3(0, -0.6, -0.8).Unit
local GA_PUSH = V3(0, -0.6, -0.8).Unit * 2.2
function GA.RootPosition(t)
	if t < 0.55 then return V3(0, -0.25 * smooth(phase(t, 0.2, 0.55)), 0) end
	-- ajoelha: joelho direito no chão (medido: descendo 1.45 a canela furava
	-- o gramado 0.74 — o quadril desce 0.7)
	if t < 0.62 then return V3(0, -0.25 - 0.55 * smooth(phase(t, 0.55, 0.62)), 0) end
	if t < 0.9 then return V3(0, -0.8, 0) end
	-- (o quadril sobe ANTES das pernas esticarem: medido, subindo junto o pé
	-- de trás furava o gramado 0.24 no meio do caminho)
	if t < 1.3 then return V3(0, -0.8 + 0.8 * smooth(phase(t, 0.88, 1.03)), 0) end
	if t < 2.0 then return V3(0, GA.Elevacao(t), 0) end
	return V3(0, GA.AlturaEspaco, 0):Lerp(GA_R_TOPO, smooth(phase(t, 2.0, 2.6)))
end
function GA.RootCFrame(t) return CFrame.new(GA.RootPosition(t)) end
function GA.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 1.3 then return s end
	if t < 2.0 then return s + V3(0, GA.Elevacao(t), 0) end
	local noAlto = s + V3(0, GA.AlturaEspaco, 0)
	if t < 2.6 then return noAlto:Lerp(GA.KickPoint, smooth(phase(t, 2.0, 2.6))) end
	if t < GA.ImpactTime then return GA.KickPoint + V3(0, math.sin((t - 2.6) * 8) * 0.08, 0) end
	return GA.KickPoint + GA_PUSH * easeOut(phase(t, GA.ImpactTime, GA.Duration))
end
function GA.BallSpin(t)
	if t < 2.0 then return 0 end
	if t < GA.ImpactTime then return 6 end
	return 30
end
local GA_POSE = {
	{ 0.00, {} },
	-- carrega o punho (verde) pra trás
	{ 0.40, { Root = { -10, 0, 0 }, Neck = { -8, 0, 0 }, RHip = { 25, 0, 0 }, LHip = { 25, 0, 0 },
		RKnee = { -30, 0, 0 }, LKnee = { -30, 0, 0 }, RShoulder = { -50, 0, 30 }, RElbow = { 100, 0, 0 },
		LShoulder = { 40, 0, -30 } } },
	-- SOCO no chão: ajoelhado de verdade (medido na 1ª versão: o joelho
	-- furava o gramado 0.67 e a mão parava 1.6 acima dele). Tronco 62° pra
	-- frente; as pernas descontam isso: coxa direita em pé (62) com a canela
	-- deitada pra trás, coxa esquerda pra frente (145) com a canela em pé; o
	-- braço direito desce até o gramado, um pouco à frente do corpo.
	{ 0.62, { Root = { -62, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 62, 0, 0 }, LHip = { 145, 0, 0 },
		RKnee = { -90, 0, 0 }, LKnee = { -95, 0, 0 }, RShoulder = { 66, 0, 8 }, RElbow = { 0, 0, 0 },
		LShoulder = { -20, 0, -40 } } },
	{ 0.90, { Root = { -58, 0, 0 }, Neck = { 28, 0, 0 }, RHip = { 58, 0, 0 }, LHip = { 141, 0, 0 },
		RKnee = { -90, 0, 0 }, LKnee = { -95, 0, 0 }, RShoulder = { 62, 0, 8 }, LShoulder = { -20, 0, -40 } } },
	-- levanta na palma, olhando os dedos subirem
	{ 1.15, { Neck = { 30, 0, 0 }, RShoulder = { 20, 0, 50 }, LShoulder = { 20, 0, -50 } } },
	-- subindo: braços pro alto
	{ 1.50, { Neck = { 40, 0, 0 }, RShoulder = { 160, 0, 25 }, LShoulder = { 160, 0, -25 } } },
	-- a mão abre: flutua
	{ 2.10, { Neck = { 10, 0, 0 }, RHip = { 15, 0, 5 }, LHip = { 5, 0, -5 }, RKnee = { -25, 0, 0 }, LKnee = { -20, 0, 0 },
		RShoulder = { 30, 0, 100 }, LShoulder = { 30, 0, -100 } } },
	-- por cima da bola: arma o chute pra baixo
	{ 2.45, { Root = { 18, 0, 0 }, Neck = { -30, 0, 0 }, RHip = { 125, 0, 0 }, RKnee = { -20, 0, 0 },
		LHip = { -15, 0, 0 }, LKnee = { -40, 0, 0 }, RShoulder = { -20, 0, 80 }, LShoulder = { 20, 0, -80 } } },
	{ 2.90, { Root = { 20, 0, 0 }, Neck = { -32, 0, 0 }, RHip = { 130, 0, 0 }, RKnee = { -18, 0, 0 },
		LHip = { -15, 0, 0 }, LKnee = { -40, 0, 0 }, RShoulder = { -20, 0, 82 }, LShoulder = { 20, 0, -82 } } },
	-- CHUTE pra baixo (de volta pra Terra)
	{ GA.ImpactTime, { Root = { 10, 0, 0 }, Neck = { -35, 0, 0 }, RHip = { 55, 0, 0 }, RKnee = { -5, 0, 0 },
		LHip = { -25, 0, 0 }, LKnee = { -45, 0, 0 }, RShoulder = { -60, 0, 60 }, LShoulder = { 40, 0, -70 } } },
	{ 3.60, { Root = { 8, 0, 0 }, Neck = { -35, 0, 0 }, RHip = { 45, 0, 0 }, RKnee = { -8, 0, 0 },
		LHip = { -25, 0, 0 }, LKnee = { -45, 0, 0 }, RShoulder = { -60, 0, 60 }, LShoulder = { 40, 0, -70 } } },
}
function GA.Pose(t) return samplePose(GA_POSE, t) end
-- ⚠️ v110 — Galáxia é de TRÊS (wiki: "um fica perto do gol e SOCA o campo; a mão
-- verde leva os OUTROS DOIS pra galáxia e os dois chutam a bola de volta pra
-- Terra"). Os dois companheiros (os de verdade que entraram no QTE; sem eles,
-- sombras): o 1º soca o campo junto com você e FICA no chão, olhando vocês
-- subirem; o 2º sobe AO SEU LADO na mão e chuta junto (pose espelhada).
-- ⚠️ v122 — PEDIDO: "nos chutes em conjunto (menos a Zona Morta) os companheiros mais LONGE do jogador" (eram 1.9 / -2.2, 3.4)
local GA_LADO = V3(3.4, 0, 0.35)
local GA_SOCADOR = V3(-3.8, 0, 4.8)
local GA_OLHA_SUBIR = { Neck = { 45, 0, 0 }, RShoulder = { 150, 0, 30 }, LShoulder = { 20, 0, -30 } }
GA.Clones = {
	Quantidade = 2,
	Cor = rgb(120, 255, 170),
	CFrame = function(i, t)
		if i == 1 then
			local agachado = t < 1.3 and GA.RootPosition(math.min(t, 1.29)).Y or 0
			return CFrame.new(GA_SOCADOR + V3(0, agachado, 0))
		end
		return CFrame.new(GA.RootPosition(t) + GA_LADO)
	end,
	Pose = function(i, t)
		if i == 1 then
			if t < 1.15 then return samplePose(GA_POSE, t) end
			return samplePose({ { 1.15, GA_POSE[5][2] }, { 1.6, GA_OLHA_SUBIR } }, t)
		end
		return espelharPose(samplePose(GA_POSE, t))
	end,
	Alpha = function(i, t)
		if t < 0.12 then return smooth(phase(t, 0, 0.12)) end
		if i == 1 then return 1 - smooth(phase(t, 1.9, 2.3)) end -- o do chão fica pra trás quando entram no espaço
		if t < 3.3 then return 1 end
		return 1 - smooth(phase(t, 3.3, 3.58))
	end,
}
function GA.Camera(t, rootPos, ballPos)
	if t < 0.55 then
		return V3(3, -1, -4.5), rootPos + V3(0.5, 0, 0), 50
	elseif t < 0.9 then
		-- do alto: a onda amarela e os raios verdes correndo no chão
		return V3(0, 12, 9), V3(0, -2.9, -1), 60
	elseif t < 1.3 then
		-- de longe e de baixo: a mão subindo do gramado
		return V3(0, -2, -13), V3(0, 2, 0), 65
	elseif t < 2.05 then
		-- ⚠️ v113: mais de cima, pra Terra aparecer embaixo (146.8s do vídeo)
		return rootPos + V3(6, 12, -8), rootPos + V3(0, -2, 0), 62
	elseif t < 2.5 then
		-- ⚠️ v113 (vídeo do IE3, 146.8s/148.4s): de cima, os dois no espaço com a
		-- mão abrindo e a TERRA lá embaixo. (De baixo e de lado, um dedo da mão
		-- tampava metade da tela.)
		local u = smooth(phase(t, 2.05, 2.5))
		return rootPos + V3(-6, 13, -10):Lerp(V3(-5, 11, -9), u), rootPos + V3(0, -3, 0), 60
	elseif t < GA.ImpactTime then
		return rootPos + V3(2.5, 5, 5), ballPos, 60
	end
	-- impacto: por trás e por cima, a bola descendo pra TERRA como meteoro
	-- (vídeo do IE3, 151.4-152s). ⚠️ v113: era de baixo — só céu preto atrás.
	local u = easeOut(phase(t, GA.ImpactTime, GA.Duration))
	return GA.KickPoint + V3(-8, 10, 14):Lerp(V3(-7, 8.5, 12), u), GA.KickPoint:Lerp(ballPos, 0.6) + V3(0, -3, -3), 56 - 8 * u
end


-- ============================================================
-- 🐉 TORNADO DO DRAGÃO (Dragon Tornado / ドラゴントルネード) — Fogo — ⚠️ v109
-- ============================================================
-- Wiki: "um sinaliza pro outro; um puxa a perna direita enquanto o outro salta.
-- Aparece o DRAGÃO AZUL de olhos vermelhos, a bola carrega de energia azul e
-- ele a chuta pro alto. O outro gira da esquerda pra direita com as pernas
-- envoltas num jato de FOGO, fecha na bola e bate de voleio — ela pega fogo e o
-- dragão azul vira um dragão de fogo." O segundo movimento é o Tornado de Fogo
-- (que o usuário aprovou) — por isso o chutador HERDA o movimento dele (FT) e
-- só muda o começo: quem levanta a bola é o PARCEIRO (companheiro perto ou
-- sombra azul), com o dragão azul subindo junto.
local DT = setmetatable({}, { __index = FT })
Cutscenes.DragaoTornado = DT
DT.Motor = "V2"
DT.Efeitos = "DragaoTornado"
DT.KickFoot = "Left"
DT.TitleText = "TORNADO DO DRAGÃO"
DT.Tema = {
	Titulo = { rgb(255, 245, 200), rgb(255, 140, 40), rgb(60, 110, 230) },
	Contorno = rgb(40, 10, 0), Flash = rgb(255, 230, 190),
	Tint = rgb(255, 232, 215), Saturation = 0.25, Contrast = 0.15, Brightness = 0,
}
-- ⚠️ v122 — PEDIDO: "nos chutes em conjunto (menos a Zona Morta) os companheiros mais LONGE do jogador" (era -3.4, 0, 2.8; a bola acompanha o pé dele)
local DT_PARCEIRO = V3(-5.0, 0, 3.8)
local DT_BOLA_PE = V3(-4.2, -2.3, 2.2) -- no pé do parceiro
local DT_POSE_INICIO = {
	{ 0.00, {} },
	{ 0.30, { Root = { -12, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 40, 0, 0 }, LHip = { 40, 0, 0 },
		RKnee = { -60, 0, 0 }, LKnee = { -60, 0, 0 }, RShoulder = { -25, 0, 25 }, LShoulder = { -25, 0, -25 } } },
}
function DT.Pose(t)
	if t < 0.55 then
		local a = samplePose(DT_POSE_INICIO, t)
		if t > 0.3 then
			local b = FT.Pose(0.55)
			local k = smooth(phase(t, 0.3, 0.55))
			for j, v in pairs(b) do
				local va = a[j] or { 0, 0, 0 }
				a[j] = { va[1] + (v[1] - va[1]) * k, va[2] + (v[2] - va[2]) * k, va[3] + (v[3] - va[3]) * k }
			end
		end
		return a
	end
	return FT.Pose(t)
end
function DT.BallPosition(t, s)
	local apex = V3(0, 27, -2.6)
	if t < 0.22 then return DT_BOLA_PE end
	if t < 1.3 then
		local u = easeOut(phase(t, 0.22, 1.3))
		return DT_BOLA_PE:Lerp(apex, u) + V3(math.sin(t * 10) * (1 - u), 0, math.cos(t * 10) * (1 - u))
	end
	return FT.BallPosition(t, s)
end
local DT_POSE_PARCEIRO = {
	{ 0.00, {} },
	{ 0.12, { Root = { -6, 0, 0 }, RHip = { -45, 0, 0 }, RKnee = { -60, 0, 0 }, LKnee = { -15, 0, 0 },
		RShoulder = { -15, 0, 30 }, LShoulder = { 25, 0, -35 } } },
	{ 0.28, { Root = { 10, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 105, 0, 0 }, RKnee = { -5, 0, 0 }, LKnee = { -15, 0, 0 },
		RShoulder = { -30, 0, 50 }, LShoulder = { 30, 0, -50 } } },
	{ 0.70, { Neck = { 40, 0, 0 }, RShoulder = { 0, 0, 20 }, LShoulder = { 0, 0, -20 } } },
}
DT.Clones = {
	Quantidade = 1,
	Cor = rgb(80, 140, 255),
	CFrame = function(_i, _t) return CFrame.new(DT_PARCEIRO) end,
	Pose = function(_i, t) return samplePose(DT_POSE_PARCEIRO, t) end,
	Alpha = function(_i, t)
		if t < 0.08 then return smooth(phase(t, 0, 0.08)) end
		if t < 1.4 then return 1 end
		return 1 - smooth(phase(t, 1.4, 1.8))
	end,
}
function DT.Camera(t, rootPos, ballPos)
	-- ⚠️ v113 (anime a 0,2s, 0-2.4s): o parceiro chuta e a bola sobe dentro de um
	-- DRAGÃO AZUL. De frente, o chutador tampava o parceiro e o dragão saía do
	-- quadro logo. Agora: de lado com os dois à vista; depois de perfil, junto da
	-- bola, o corpo do dragão subindo atrás dela.
	if t < 0.3 then
		return V3(-10, 0.3, -4), V3(-1.7, -0.3, 1.2), 60
	elseif t < 0.72 then
		local u = smooth(phase(t, 0.3, 0.72))
		return ballPos + V3(-12, -3 + 2 * u, 3), ballPos + V3(0, -2.5 * (1 - u), 0), 62
	end
	return FT.Camera(t, rootPos, ballPos)
end

-- ============================================================
-- ☄️ LÂMINA METEORO (Ryuusei Blade / 流星ブレード) — Fogo — ⚠️ v110
-- ============================================================
-- PEDIDO: "o chute de meteoro do alienígena de cabelo vermelho (Hiroto)" +
-- "não precisa usar o Fire Tornado pra tudo — olha o vídeo". Refeita pelo VÍDEO
-- ("Inazuma Eleven Ryuusei Blade V3 HD", quadros a cada 0,1s):
--   0,5-1,6  salta e GIRA no ar (fundo de riscos vermelhos), a bola na frente;
--   1,7      VOLEIO com a direita;
--   2,6-4,2  a bola vira uma ESFERA roxa e azul cheia de raios;
--   4,3-4,7  um anel roxo se FECHA e a energia some num ponto (espaço);
--   4,9-5,8  explode num SOL dourado gigante com um reflexo horizontal;
--   5,9-6,5  clarão branco;
--   6,6-9,1  a bola desce como um FEIXE rosa/roxo com raios amarelos nas bordas
--            e explosões pelo caminho, até o goleiro (o "meteoro").
-- Wiki: "salta e gira o corpo, pronto pra bater de voleio com a direita; a bola
-- fica coberta de energia roxa com redemoinhos azuis; a energia some e volta num
-- feixe em forma de lâmina, indo pro gol com explosões, como um meteoro".
local LM = {}
Cutscenes.LaminaMeteoro = LM
LM.Motor = "V2"
LM.Efeitos = "LaminaMeteoro"
LM.KickFoot = "Right"
LM.Duration = 2.85
LM.ImpactTime = 1.25
LM.TitleText = "LÂMINA METEORO"
LM.ColarNoPe = false
LM.Tema = {
	Titulo = { rgb(255, 235, 255), rgb(235, 90, 200), rgb(120, 40, 200) },
	Contorno = rgb(40, 0, 30), Flash = rgb(255, 245, 220),
	Tint = rgb(240, 215, 240), Saturation = 0.25, Contrast = 0.2, Brightness = -0.03,
}
LM.Phases = {
	Crouch = { 0, 0.22 }, Spring = { 0.22, 0.55 }, Spin = { 0.5, 1.05 }, Kick = { 1.05, LM.ImpactTime },
	Esfera = { 1.3, 1.9 }, Colapso = { 1.9, 2.1 }, Estrela = { 2.1, 2.55 }, Clarao = { 2.55, 2.85 },
	Impact = { LM.ImpactTime, LM.Duration },
}
LM.KickPoint = V3(0.6, 5.2, -3.3)
LM.PontoEstrela = V3(0.2, 5.6, -8.5) -- onde a bola vira esfera -> estrela (e de onde o chute sai)
local LM_ROOT = {
	{ 0, V3(0, 0, 0) }, { 0.22, V3(0, -0.7, 0) }, { 0.55, V3(0, 4.2, -0.6) }, { 1.05, V3(0, 5.8, -1.3) },
	{ LM.ImpactTime, V3(0, 5.6, -1.6) }, { 1.9, V3(0, 3.2, -2.0) }, { 2.35, V3(0, -0.6, -2.2) }, { 2.85, V3(0, 0, -2.3) },
}
function LM.RootPosition(t) return sample(LM_ROOT, t) end
-- gira no ar (uma volta) tombado de lado; no voleio o corpo fica inclinado
local LM_GIRO = { { 0, 0 }, { 0.5, 0 }, { 1.05, -360 }, { 2.85, -360 } }
local LM_TOMBA = { { 0, 0 }, { 0.5, 0 }, { 0.7, 55 }, { 1.0, 55 }, { LM.ImpactTime, 35 }, { 1.9, 15 }, { 2.35, 0 }, { 2.85, 0 } }
function LM.RootCFrame(t)
	return CFrame.new(LM.RootPosition(t)) * CFrame.Angles(0, rad(sample(LM_GIRO, t)), 0) * CFrame.Angles(0, 0, rad(-sample(LM_TOMBA, t)))
end
function LM.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.24 then return s end
	-- o toque que levanta a bola, e ela espera na frente dele, na altura do voleio
	local alto = V3(0.4, 5.6, -3.4)
	if t < 1.05 then return s:Lerp(alto, easeOut(phase(t, 0.24, 0.7))) + V3(0, math.sin(t * 5) * 0.15, 0) end
	if t < LM.ImpactTime then return alto:Lerp(LM.KickPoint, smooth(phase(t, 1.05, LM.ImpactTime))) end
	-- o voleio a manda pra frente, onde ela vira a esfera, colapsa e explode em estrela
	return LM.KickPoint:Lerp(LM.PontoEstrela, easeOut(phase(t, LM.ImpactTime, 1.45)))
end
function LM.BallVisible(t) return t < 1.9 or t >= 2.55 end -- some no colapso/estrela
function LM.BallSpin(t) return t < 0.24 and 0 or (t < LM.ImpactTime and 6 or 30) end
local LM_POSE = {
	{ 0.00, {} },
	-- agacha
	{ 0.20, { Root = { -12, 0, 0 }, Neck = { 15, 0, 0 }, RHip = { 55, 0, 8 }, LHip = { 55, 0, -8 }, RKnee = { -90, 0, 0 }, LKnee = { -90, 0, 0 },
		RShoulder = { -35, 0, 20 }, LShoulder = { -35, 0, -20 } } },
	-- toque que levanta a bola
	{ 0.30, { Root = { -4, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 70, 0, 0 }, RKnee = { -15, 0, 0 }, LHip = { 10, 0, 0 }, LKnee = { -30, 0, 0 },
		RShoulder = { 10, 0, 40 }, LShoulder = { 20, 0, -40 } } },
	-- salta, braços abertos, perna esquerda dobrada
	{ 0.55, { Neck = { 20, 0, 0 }, RShoulder = { 120, 0, 40 }, LShoulder = { 120, 0, -40 }, RHip = { 10, 0, 0 }, LHip = { 40, 0, 0 },
		LKnee = { -70, 0, 0 } } },
	-- girando: arma o voleio (direita pra trás)
	{ 0.95, { Neck = { 10, 0, 0 }, RShoulder = { 20, 0, 85 }, LShoulder = { 20, 0, -85 }, RHip = { -40, 0, 0 }, RKnee = { -95, 0, 0 },
		LHip = { 70, 0, 0 }, LKnee = { -30, 0, 0 } } },
	-- VOLEIO
	{ LM.ImpactTime, { Neck = { -5, 0, 0 }, RShoulder = { -30, 0, 80 }, LShoulder = { 40, 0, -80 }, RHip = { 100, 0, -10 }, RKnee = { -5, 0, 0 },
		LHip = { -20, 0, 0 }, LKnee = { -40, 0, 0 } } },
	{ 1.80, { Neck = { 5, 0, 0 }, RShoulder = { 30, 0, 70 }, LShoulder = { 30, 0, -70 }, RHip = { 70, 0, 0 }, RKnee = { -20, 0, 0 },
		LHip = { 0, 0, 0 }, LKnee = { -30, 0, 0 } } },
	-- aterrissa agachado, olhando a estrela
	{ 2.35, { Root = { -10, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 45, 0, 8 }, LHip = { 45, 0, -8 }, RKnee = { -70, 0, 0 }, LKnee = { -70, 0, 0 },
		RShoulder = { 0, 0, 35 }, LShoulder = { 0, 0, -35 } } },
	{ 2.85, { Root = { -4, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 15, 0, 0 }, LHip = { 15, 0, 0 }, RKnee = { -25, 0, 0 }, LKnee = { -25, 0, 0 } } },
}
function LM.Pose(t) return samplePose(LM_POSE, t) end
function LM.Camera(t, rootPos, ballPos)
	if t < 0.5 then
		return V3(2, 1, -9), rootPos + V3(0, 0.5, 0), 55 -- de frente
	elseif t < 1.05 then
		return rootPos + V3(8, -2, 2), rootPos, 62 -- de lado e de baixo: o giro no ar
	elseif t < 1.3 then
		return LM.KickPoint + V3(3, 0.8, -3), LM.KickPoint, 48 -- close no voleio
	elseif t < 2.55 then
		local u = smooth(phase(t, 1.3, 2.55))
		return LM.PontoEstrela + V3(0, 0.5, -12 + 3 * u), LM.PontoEstrela, 55 - 10 * u -- de frente pra esfera -> estrela
	end
	return LM.PontoEstrela + V3(2, 2, 9), LM.PontoEstrela + V3(0, -1, -20), 60 -- atrás da bola: o feixe saindo
end

-- ============================================================
-- 🌌 QUEDA CELESTIAL (Tenkuu Otoshi / 天空落とし) — Fogo — ⚠️ v110
-- ============================================================
-- PEDIDO: "coloca a outra Hissatsu dele (Hiroto)... não é pra invocar um monte
-- de planetas em volta dela — é pro FEIXE ter um universo: quando chutar, o
-- rastro atrás da bola sai como um universo, amarelo com roxo, como uma câmera
-- pra outro universo" (+ imagem do anime). Refeita pelo VÍDEO (quadros a cada
-- 0,1s, "Inazuma Eleven - Tenkuu Otoshi [Hiroto Kiyama]"), que é diferente da
-- descrição do jogo na wiki:
--   0,2-1,6  a bola já está lá no alto, no céu;
--   5,2-6,2  ele SOBE torcendo o corpo (visto de trás, de baixo);
--   6,4      atravessa as NUVENS (clarão amarelo) e entra no ESPAÇO;
--   6,7-8,7  voa DEITADO, esticado, até a bola, armando a perna direita;
--   8,8-9,2  VOLEIO: anel roxo com espinhos amarelos em volta do pé;
--   9,3-10,4 close da chuteira na bola, raios roxos e amarelos atrás;
--   10,8-11  no céu do estádio, a bola brilha como uma ESTRELA descendo;
--   11,1     arco roxo cruzando o céu;
--   11,2-13,4 o FEIXE: um cone largo atrás da bola, borda magenta e ciano, e
--            DENTRO dele o espaço (planetas passando, riscos amarelos) — a
--            "câmera pra outro universo".
-- É a Mítica SOLO. A bola sai lá do alto e desce na reta até a mira (voo
-- reto travado, ver BallController).
local QC = {}
Cutscenes.QuedaCelestial = QC
QC.Motor = "V2"
QC.Efeitos = "QuedaCelestial"
QC.KickFoot = "Right"
QC.Duration = 2.9
QC.ImpactTime = 2.2
QC.TitleText = "QUEDA CELESTIAL"
QC.ColarNoPe = false
QC.Tema = {
	Titulo = { rgb(245, 235, 255), rgb(200, 110, 255), rgb(60, 180, 255) },
	Contorno = rgb(20, 5, 45), Flash = rgb(255, 235, 200),
	Tint = rgb(225, 220, 255), Saturation = 0.3, Contrast = 0.2, Brightness = -0.03,
}
QC.Phases = {
	Flick = { 0, 0.35 }, Crouch = { 0.35, 0.55 }, Rise = { 0.55, 1.3 }, Clouds = { 1.2, 1.2 },
	Space = { 1.25, 2.8 }, Fly = { 1.3, 2.05 }, Kick = { 2.05, QC.ImpactTime }, Impact = { QC.ImpactTime, QC.Duration },
}
QC.AlturaNuvens = 20
QC.CentroEspaco = V3(0, 31, -7)
QC.KickPoint = V3(0.5, 30.8, -10.8)
local QC_ROOT = {
	{ 0, V3(0, 0, 0) }, { 0.35, V3(0, 0, 0) }, { 0.52, V3(0, -0.6, 0) },
	{ 1.3, V3(0, 26, -2) }, { 1.5, V3(0, 29, -4.5) }, { 2.05, V3(0, 33, -9.4) },
	{ QC.ImpactTime, V3(0, 33.4, -10.3) }, { 2.9, V3(0, 33.2, -11.6) },
}
function QC.RootPosition(t) return sample(QC_ROOT, t) end
-- sobe TORCENDO (uma volta) e depois deita pra frente, esticado (voo horizontal)
local QC_GIRO = { { 0, 0 }, { 0.55, 0 }, { 1.3, 360 }, { 2.9, 360 } }
local QC_DEITA = { { 0, 0 }, { 1.3, 0 }, { 1.55, -80 }, { QC.ImpactTime, -78 }, { 2.9, -62 } }
function QC.RootCFrame(t)
	return CFrame.new(QC.RootPosition(t)) * CFrame.Angles(0, rad(sample(QC_GIRO, t)), 0) * CFrame.Angles(rad(sample(QC_DEITA, t)), 0, 0)
end
function QC.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.08 then return s end
	-- o toque que manda a bola pro céu, e ela segue subindo à frente dele
	local alto = V3(0, 30.4, -11.2)
	if t < 1.9 then
		local u = easeOut(phase(t, 0.08, 1.9))
		return s:Lerp(alto, u) + V3(0, math.sin(u * math.pi) * 3, 0)
	end
	if t < QC.ImpactTime then return alto:Lerp(QC.KickPoint, smooth(phase(t, 1.9, QC.ImpactTime))) end
	return QC.KickPoint + V3(0, -0.35, -1).Unit * 2.2 * easeOut(phase(t, QC.ImpactTime, QC.Duration))
end
function QC.BallSpin(t) return t < 0.08 and 0 or (t < QC.ImpactTime and 5 or 28) end
local QC_POSE = {
	{ 0.00, {} },
	-- o toque pro alto (direita)
	{ 0.18, { Root = { 8, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 75, 0, 0 }, RKnee = { -15, 0, 0 }, LKnee = { -20, 0, 0 },
		RShoulder = { -20, 0, 30 }, LShoulder = { 30, 0, -35 } } },
	-- agacha pra saltar, olhando a bola lá em cima
	{ 0.48, { Root = { -15, 0, 0 }, Neck = { 40, 0, 0 }, RHip = { 60, 0, 8 }, LHip = { 60, 0, -8 }, RKnee = { -90, 0, 0 }, LKnee = { -90, 0, 0 },
		RShoulder = { -40, 0, 25 }, LShoulder = { -40, 0, -25 } } },
	-- sobe torcendo, braço direito pro alto
	{ 0.75, { Root = { 8, 0, 0 }, Neck = { 40, 0, 0 }, RShoulder = { 165, 0, 20 }, LShoulder = { 110, 0, -35 },
		RHip = { -15, 0, 0 }, LHip = { 30, 0, 0 }, LKnee = { -55, 0, 0 } } },
	{ 1.25, { Root = { 5, 0, 0 }, Neck = { 45, 0, 0 }, RShoulder = { 170, 0, 15 }, LShoulder = { 140, 0, -25 },
		RHip = { -10, 0, 0 }, LHip = { 20, 0, 0 }, LKnee = { -40, 0, 0 } } },
	-- voando DEITADO (tronco na horizontal): cabeça erguida olhando a bola,
	-- braços colados pra trás, pernas esticadas
	{ 1.55, { Neck = { 60, 0, 0 }, RShoulder = { -25, 0, 22 }, LShoulder = { -25, 0, -22 }, RHip = { -8, 0, 0 }, LHip = { -4, 0, 0 },
		RKnee = { -10, 0, 0 }, LKnee = { -10, 0, 0 } } },
	-- arma a direita (joelho dobrado pra trás)
	{ 1.95, { Neck = { 55, 0, 0 }, RShoulder = { -30, 0, 45 }, LShoulder = { 20, 0, -50 }, RHip = { -55, 0, 0 }, RKnee = { -105, 0, 0 },
		LHip = { 10, 0, 0 }, LKnee = { -15, 0, 0 } } },
	-- VOLEIO: a perna varre pra baixo-frente (com o tronco deitado, 80° = pra baixo)
	{ QC.ImpactTime, { Neck = { 50, 0, 0 }, RShoulder = { -45, 0, 40 }, LShoulder = { 40, 0, -60 }, RHip = { 85, 0, 0 }, RKnee = { -5, 0, 0 },
		LHip = { -15, 0, 0 }, LKnee = { -30, 0, 0 } } },
	{ 2.90, { Neck = { 45, 0, 0 }, RShoulder = { -45, 0, 40 }, LShoulder = { 40, 0, -60 }, RHip = { 100, 0, 0 }, RKnee = { -8, 0, 0 },
		LHip = { -15, 0, 0 }, LKnee = { -30, 0, 0 } } },
}
function QC.Pose(t) return samplePose(QC_POSE, t) end
function QC.Camera(t, rootPos, ballPos)
	if t < 0.5 then
		return V3(1.5, 0.6, 6), ballPos:Lerp(rootPos, 0.5), 62 -- por trás: a bola indo pro céu
	elseif t < 1.3 then
		return rootPos + V3(2.5, -6, 4.5), rootPos + V3(0, 2, -1), 72 -- por trás e de baixo: ele subindo torcendo
	elseif t < 2.05 then
		local u = smooth(phase(t, 1.3, 2.05))
		return rootPos + V3(9 - 2 * u, 0.5, 1.5), rootPos:Lerp(ballPos, 0.45), 60 -- de lado: voando deitado até a bola
	elseif t < QC.ImpactTime then
		return QC.KickPoint + V3(2.6, 0.6, 2.6), QC.KickPoint, 45 -- close no pé e na bola
	end
	-- do gramado, olhando pra cima: a bola vira uma estrela e começa a descer
	local u = easeOut(phase(t, QC.ImpactTime, QC.Duration))
	return V3(3, 1.2, -16):Lerp(V3(2.5, 1.5, -18), u), ballPos, 50 - 8 * u
end

-- ============================================================
-- 🪨 RUPTURA DE GAIA (Gaia Break / ガイアブレイク) — Natureza — ⚠️ v109
-- ============================================================
-- Wiki: "três lado a lado: o do meio agacha, os outros dois cruzam os braços no
-- ar, os três arqueiam o corpo pra trás. Uma energia amarela em feixe aparece em
-- volta deles e manda a bola pro alto enquanto ROCHAS grandes saem do campo. A
-- bola puxa as rochas e vira uma massa de espinhos; os três saltam juntos até
-- ela e batem." Os dois dos lados: companheiros perto ou sombras (Clones).
local GB = {}
Cutscenes.GaiaBreak = GB
GB.Motor = "V2"
GB.Efeitos = "GaiaBreak"
GB.KickFoot = "Right"
GB.Duration = 3.4
GB.ImpactTime = 2.85
GB.TitleText = "RUPTURA DE GAIA"
GB.Tema = {
	Titulo = { rgb(255, 250, 210), rgb(230, 200, 90), rgb(130, 95, 50) },
	Contorno = rgb(45, 30, 10), Flash = rgb(255, 245, 200),
	Tint = rgb(245, 235, 210), Saturation = 0.1, Contrast = 0.2, Brightness = 0,
}
GB.Phases = {
	Pose = { 0, 0.5 }, Beam = { 0.4, 1.1 }, Rocks = { 0.6, 1.2 }, Gather = { 1.3, 1.85 },
	Jump = { 1.7, 2.45 }, Kick = { 2.45, GB.ImpactTime }, Impact = { GB.ImpactTime, GB.Duration },
}
GB.ColarNoPe = false
GB.Centro = V3(0, 12.8, -6) -- onde a bola fica no chute (no meio dos três pés)
GB.KickPoint = GB.Centro
GB.KickContactDir = V3(0, -0.2, -1).Unit
local GB_BOLA_ALTO = V3(0, 17, -7)
-- ⚠️ v122 — PEDIDO: "nos chutes em conjunto (menos a Zona Morta) os companheiros mais LONGE do jogador" (no chão; era 3.6 — no ar eles fecham na bola)
local GB_LADOS = { [1] = -5.4, [2] = 5.4 }
local GB_CHUTE_RAIZ = { [0] = V3(0, 12.3, -2.6), [1] = V3(-2.4, 12.6, -3.8), [2] = V3(2.4, 12.6, -3.8) }
local function gbPos(i, t)
	local chao = i == 0 and V3(0, 0, 0) or V3(GB_LADOS[i], 0, 0.4)
	if t < 0.5 then return chao + V3(0, i == 0 and -0.9 * smooth(phase(t, 0.1, 0.4)) or 0, 0) end
	if t < 1.7 then return chao + V3(0, i == 0 and -0.9 or 0, 0) end
	local u = easeOut(phase(t, 1.7, 2.45))
	return (chao + V3(0, i == 0 and -0.9 or 0, 0)):Lerp(GB_CHUTE_RAIZ[i], u) + V3(0, math.sin(u * math.pi) * 2, 0)
end
local function gbYaw(i, t)
	-- os três terminam olhando a bola (no meio)
	if t < 1.7 then return 0 end
	local de = GB_CHUTE_RAIZ[i]
	local alvo = yawOlhando(de, GB.Centro)
	return alvo * smooth(phase(t, 1.7, 2.4))
end
function GB.RootPosition(t) return gbPos(0, t) end
function GB.RootCFrame(t) return CFrame.new(gbPos(0, t)) * CFrame.Angles(0, gbYaw(0, t), 0) end
function GB.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.45 then return s end
	if t < 1.2 then return s:Lerp(GB_BOLA_ALTO, easeOut(phase(t, 0.45, 1.2))) end
	if t < 1.9 then return GB_BOLA_ALTO + V3(0, math.sin((t - 1.2) * 5) * 0.3, 0) end
	if t < GB.ImpactTime then return GB_BOLA_ALTO:Lerp(GB.Centro, smooth(phase(t, 1.9, GB.ImpactTime))) end
	return GB.Centro + V3(0, -0.25, -1).Unit * 1.8 * easeOut(phase(t, GB.ImpactTime, GB.Duration))
end
function GB.BallSpin(t) return t < 0.45 and 0 or (t < GB.ImpactTime and 8 or 26) end
local GB_POSE_MEIO = {
	{ 0.00, {} },
	-- o do meio agacha
	{ 0.40, { Root = { -20, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 70, 0, 12 }, LHip = { 70, 0, -12 },
		RKnee = { -110, 0, 0 }, LKnee = { -110, 0, 0 }, RShoulder = { 30, 0, 30 }, LShoulder = { 30, 0, -30 } } },
	-- arqueia pra trás (a energia sobe)
	{ 0.90, { Root = { 22, 0, 0 }, Neck = { -25, 0, 0 }, RHip = { 40, 0, 12 }, LHip = { 40, 0, -12 },
		RKnee = { -70, 0, 0 }, LKnee = { -70, 0, 0 }, RShoulder = { 120, 0, 50 }, LShoulder = { 120, 0, -50 } } },
	{ 1.65, { Root = { -15, 0, 0 }, RHip = { 60, 0, 10 }, LHip = { 60, 0, -10 }, RKnee = { -95, 0, 0 }, LKnee = { -95, 0, 0 },
		RShoulder = { -40, 0, 30 }, LShoulder = { -40, 0, -30 } } },
	-- salta
	{ 2.00, { Root = { 5, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { 10, 0, 0 }, LHip = { 50, 0, 0 }, LKnee = { -80, 0, 0 },
		RShoulder = { 150, 0, 25 }, LShoulder = { 150, 0, -25 } } },
	-- arma a perna
	{ 2.55, { Root = { 18, 0, 0 }, Neck = { -15, 0, 0 }, RHip = { -60, 0, 5 }, RKnee = { -95, 0, 0 }, LHip = { 40, 0, 0 },
		LKnee = { -60, 0, 0 }, RShoulder = { 20, 0, 80 }, LShoulder = { 20, 0, -80 } } },
	-- os três batem juntos
	{ GB.ImpactTime, { Root = { -15, 0, 0 }, Neck = { -20, 0, 0 }, RHip = { 105, 0, 0 }, RKnee = { -5, 0, 0 },
		LHip = { -10, 0, 0 }, LKnee = { -40, 0, 0 }, RShoulder = { -40, 0, 70 }, LShoulder = { 40, 0, -80 } } },
	{ 3.40, { Root = { -18, 0, 0 }, Neck = { -18, 0, 0 }, RHip = { 110, 0, 0 }, RKnee = { -6, 0, 0 },
		LHip = { -12, 0, 0 }, LKnee = { -42, 0, 0 }, RShoulder = { -40, 0, 70 }, LShoulder = { 40, 0, -80 } } },
}
-- os dos lados: cruzam os braços no ar (em vez de agachar), depois o mesmo
local GB_CRUZA = { Root = { 4, 0, 0 }, Neck = { 12, 0, 0 }, RShoulder = { 165, 0, -35 }, LShoulder = { 165, 0, 35 },
	RElbow = { 40, 0, 0 }, LElbow = { 40, 0, 0 }, RHip = { 10, 0, 8 }, LHip = { 10, 0, -8 }, RKnee = { -15, 0, 0 }, LKnee = { -15, 0, 0 } }
function GB.Pose(t) return samplePose(GB_POSE_MEIO, t) end
GB.Clones = {
	Quantidade = 2,
	Cor = rgb(200, 160, 80),
	CFrame = function(i, t) return CFrame.new(gbPos(i, t)) * CFrame.Angles(0, gbYaw(i, t), 0) end,
	Pose = function(i, t)
		local pose
		if t < 0.5 then
			pose = samplePose({ { 0, {} }, { 0.4, GB_CRUZA } }, t)
		elseif t < 0.9 then
			pose = samplePose({ { 0.5, GB_CRUZA }, { 0.9, GB_POSE_MEIO[3][2] } }, t)
		else
			pose = samplePose(GB_POSE_MEIO, t)
		end
		return i == 2 and espelharPose(pose) or pose
	end,
	Alpha = function(_i, t)
		if t < 0.15 then return smooth(phase(t, 0, 0.15)) end
		if t < 3.0 then return 1 end
		return 1 - smooth(phase(t, 3.0, 3.35))
	end,
}
function GB.Camera(t, rootPos, ballPos)
	if t < 0.5 then
		return V3(1, 0.8, -14), V3(0, 0.3, 0), 62 -- os três lado a lado, de frente
	elseif t < 1.3 then
		return V3(5, -1.8, 7), ballPos:Lerp(V3(0, 2, -3), 0.4), 68 -- de baixo: a bola sobe e as rochas saem do campo
	elseif t < 2.4 then
		local u = smooth(phase(t, 1.3, 2.4))
		return V3(15 - 3 * u, 7 + 3 * u, -4), V3(0, 6 + 6 * u, -4.5), 64 -- de lado, a massa de pedra e os três saltando
	elseif t < GB.ImpactTime then
		-- de frente, os três fechando na massa de pedra (⚠️ v113: mais aberta — a 9
		-- studs a massa espinhosa tampava os três)
		return GB.Centro + V3(4, 2.5, -15), GB.Centro + V3(0, 0, 2), 55
	end
	local u = easeOut(phase(t, GB.ImpactTime, GB.Duration))
	return GB.Centro + V3(-2, -1.5, -7):Lerp(V3(-1.6, -1.2, -5.2), u), ballPos, 64 - 14 * u
end

-- ============================================================
-- ☄️ CHUVA DE METEOROS (Meteor Shower / メテオシャワー) — Fogo — ⚠️ v110
-- ============================================================
-- Wiki: "salta com a bola, bate de BICICLETA e a bola se divide em vários
-- meteoros de fogo que caem em cima dos adversários, jogando todos longe".
-- PEDIDO: "o personagem sobe com a bola, arremessa o meteoro pra baixo, efeito
-- de meteoro, cratera, e o ragdoll nos jogadores que estiverem embaixo".
-- É um DRIBLE com cutscene: no fim dela o drible normal sai (a bola cai de
-- volta no pé dele) e o servidor derruba quem estava no raio — os meteoros
-- da cena caem exatamente em cima desses adversários (HissatsuEfeitos.Meteoros).
--   0.00-0.25  agacha com a bola no pé;        0.25-1.00  sobe com a bola;
--   0.95-1.45  tomba pra trás (bicicleta);     1.45       CHUTE pro céu;
--   1.80       a bola explode em 6 meteoros;   2.05-2.50  meteoros caindo;
--   1.45-2.50  ele termina o mortal e cai;     2.50-2.90  a bola cai no pé dele.
local CM = {}
Cutscenes.ChuvaDeMeteoros = CM
CM.Motor = "V2"
CM.Efeitos = "Meteoros"
CM.KickFoot = "Right"
CM.Duration = 2.9
CM.ImpactTime = 1.45
CM.TitleText = "CHUVA DE METEOROS"
CM.ColarNoPe = false
CM.Tema = {
	Titulo = { rgb(255, 245, 200), rgb(255, 150, 40), rgb(170, 40, 10) },
	Contorno = rgb(45, 10, 0), Flash = rgb(255, 210, 150),
	Tint = rgb(255, 225, 200), Saturation = 0.25, Contrast = 0.18, Brightness = -0.03,
}
CM.Phases = {
	Crouch = { 0, 0.25 }, Rise = { 0.25, 1.0 }, Flip = { 0.95, 1.45 }, Kick = { 1.3, CM.ImpactTime },
	Split = { 1.8, 1.8 }, Rain = { 2.05, 2.5 }, Land = { 2.2, 2.5 }, Impact = { CM.ImpactTime, CM.Duration },
}
CM.Ceu = V3(0, 34, -5)          -- onde a bola explode em meteoros
CM.PeFinal = V3(0, -2.05, -3.3) -- bola no pé dele no fim (recalculado pela calibragem)
table.insert(recalculos, function()
	CM.PeFinal = V3(0, CAL.Chao + CAL.Raio, -3.3)
end)
local CM_ROOT = {
	{ 0, V3(0, 0, 0) }, { 0.25, V3(0, -0.7, 0) }, { 1.0, V3(0, 14, 0.6) }, { 1.45, V3(0, 15.2, 0.4) },
	{ 2.0, V3(0, 9, -0.6) }, { 2.45, V3(0, -0.6, -1.4) }, { 2.9, V3(0, 0, -1.5) },
}
-- mortal pra trás: deita de costas (110°) no chute e completa a volta caindo
local CM_GIRO = { { 0, 0 }, { 0.95, 0 }, { CM.ImpactTime, 110 }, { 2.1, 360 }, { 2.9, 360 } }
function CM.RootPosition(t) return sample(CM_ROOT, t) end
function CM.RootCFrame(t)
	return CFrame.new(CM.RootPosition(t)) * CFrame.Angles(rad(sample(CM_GIRO, t)), 0, 0)
end
function CM.BallPosition(t, s)
	s = s or V3(0, -2.3, -1.8)
	if t < 0.1 then return s end
	if t < 1.0 then
		-- levanta com o pé e sobe colada acima da cabeça dele
		local acima = CM.RootPosition(t) + V3(0, 3.4, -0.6)
		return s:Lerp(acima, smooth(phase(t, 0.1, 0.4)))
	end
	if t < CM.ImpactTime then
		-- fica no ponto do chute enquanto ele tomba
		local chute = V3(0, 18.6, 1.2)
		return (CM.RootPosition(1.0) + V3(0, 3.4, -0.6)):Lerp(chute, smooth(phase(t, 1.0, 1.35)))
	end
	if t < 1.8 then return V3(0, 18.6, 1.2):Lerp(CM.Ceu, easeOut(phase(t, CM.ImpactTime, 1.8))) end
	if t < 2.5 then return CM.Ceu end
	-- a bola de verdade volta caindo em chamas no pé dele
	local u = phase(t, 2.5, 2.85)
	return (CM.PeFinal + V3(0, 12, 0)):Lerp(CM.PeFinal, u * u)
end
function CM.BallVisible(t) return t < 1.8 or t >= 2.5 end
function CM.BallSpin(t) return t < 0.1 and 0 or (t < CM.ImpactTime and 6 or 22) end
local CM_POSE = {
	{ 0.00, {} },
	-- agacha pra saltar
	{ 0.22, { Root = { -15, 0, 0 }, Neck = { 15, 0, 0 }, RHip = { 60, 0, 8 }, LHip = { 60, 0, -8 },
		RKnee = { -100, 0, 0 }, LKnee = { -100, 0, 0 }, RShoulder = { -40, 0, 20 }, LShoulder = { -40, 0, -20 } } },
	-- sobe esticado, olhando a bola, braços pra cima
	{ 0.50, { Root = { 5, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { -10, 0, 0 }, LHip = { 20, 0, 0 }, LKnee = { -40, 0, 0 },
		RShoulder = { 160, 0, 20 }, LShoulder = { 160, 0, -20 } } },
	{ 0.95, { Root = { 8, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 40, 0, 0 }, LHip = { 60, 0, 0 }, RKnee = { -70, 0, 0 },
		LKnee = { -90, 0, 0 }, RShoulder = { 70, 0, 50 }, LShoulder = { 70, 0, -50 } } },
	-- arma a bicicleta: perna de apoio sobe, a do chute fica pra trás
	{ 1.30, { Neck = { 20, 0, 0 }, RHip = { -30, 0, 0 }, RKnee = { -90, 0, 0 }, LHip = { 100, 0, 0 }, LKnee = { -10, 0, 0 },
		RShoulder = { 20, 0, 80 }, LShoulder = { 20, 0, -80 } } },
	-- CHUTE: a direita passa por cima (tesoura)
	{ CM.ImpactTime, { Neck = { 15, 0, 0 }, RHip = { 125, 0, 0 }, RKnee = { -5, 0, 0 }, LHip = { -30, 0, 0 }, LKnee = { -40, 0, 0 },
		RShoulder = { 30, 0, 85 }, LShoulder = { 30, 0, -85 } } },
	-- cai terminando o mortal, braços abertos
	{ 1.95, { Neck = { -10, 0, 0 }, RHip = { 30, 0, 0 }, LHip = { 10, 0, 0 }, RKnee = { -40, 0, 0 }, LKnee = { -30, 0, 0 },
		RShoulder = { 90, 0, 70 }, LShoulder = { 90, 0, -70 } } },
	-- aterrissa agachado (super-herói)
	{ 2.45, { Root = { -14, 0, 0 }, Neck = { 10, 0, 0 }, RHip = { 55, 0, 8 }, LHip = { 55, 0, -8 },
		RKnee = { -90, 0, 0 }, LKnee = { -90, 0, 0 }, RShoulder = { -20, 0, 40 }, LShoulder = { -20, 0, -40 } } },
	{ 2.90, { Root = { -5, 0, 0 }, RHip = { 15, 0, 0 }, LHip = { 15, 0, 0 }, RKnee = { -25, 0, 0 }, LKnee = { -25, 0, 0 } } },
}
function CM.Pose(t) return samplePose(CM_POSE, t) end
function CM.Camera(t, rootPos, ballPos)
	if t < 0.3 then
		return V3(2.5, 0.2, -8), rootPos + V3(0, 0.6, 0), 60 -- de frente, agachando
	elseif t < 1.0 then
		return V3(4, -1.8, 7), rootPos + V3(0, 1.5, 0), 72 -- do chão, ele subindo
	elseif t < 1.8 then
		-- de lado lá em cima: a bicicleta e a bola subindo pro céu
		local u = smooth(phase(t, 1.0, 1.8))
		return rootPos + V3(10, 0.5 + 4 * u, -1.5), rootPos:Lerp(ballPos, 0.35 + 0.4 * u), 58 + 10 * u
	elseif t < 2.5 then
		-- aberta, de cima e de trás: os meteoros caindo nos marcadores
		local u = smooth(phase(t, 1.8, 2.5))
		return V3(12, 30, 24):Lerp(V3(9, 24, 20), u), V3(0, 4 - 4 * u, -6), 72
	end
	local u = easeOut(phase(t, 2.5, 2.9))
	return V3(3.5, -0.8, -8):Lerp(V3(3, -1.2, -7), u), rootPos + V3(0, 0.5, 0), 60 -- rente ao chão, ele de pé no meio das crateras
end

-- ============================================================
-- 🧤 CUTSCENES DE DEFESA (⚠️ v103)
-- ============================================================
-- PEDIDO: "a Hissatsu de GK e de defensor precisa sair instantaneamente com a
-- colisão na hitbox, e a cutscene da defesa vai acontecer se a bola colidir
-- com essa hitbox." Quando o chute de Hissatsu bate na guarda do goleiro,
-- todo mundo congela e toca a cutscene da técnica DO GOLEIRO enquanto o
-- duelo (QTE, dano por acerto) acontece. O resultado (defendeu/passou) só é
-- aplicado no FIM dela (ver BallController / GKBotController).
-- Espaço local: o goleiro na origem, olhando pra bola (-Z). A duração varia
-- (é a do QTE da guarda): Cutscenes.PrepararDefesa(d) antes de tocar.
-- Referências (Inazuma Eleven Wiki): God Hand (mão de luz gigante que sai das
-- costas e segura a bola), Majin The Hand (demônio roxo atrás do goleiro,
-- mão escura), Tsunami Wall (parede d'água), Bakuretsu Punch (socos
-- sequenciais em chamas), Mega Quake/Giant fist (punho gigante).
local DEF_D = 3.5
function Cutscenes.PrepararDefesa(d)
	DEF_D = math.clamp(tonumber(d) or 3.5, 1.5, 6)
end

local POSE_DEFESA = {
	-- mão aberta empurrando à frente (Mão Divina / Mão do Demônio)
	-- ⚠️ v110 (vídeo "God Hand" a 0,1s): antes de puxar o braço, ele ERGUE a mão
	-- direita aberta na frente do rosto, acendendo (2.6-3.5s do vídeo)
	Mao = {
		ergue = {
			Root = { 0, 8, 0 }, Neck = { 4, -6, 0 },
			RShoulder = { 128, 0, 18 }, RElbow = { 75, 0, 0 }, LShoulder = { 25, 0, -30 }, LElbow = { 35, 0, 0 },
			RHip = { 18, 0, 10 }, LHip = { 22, 0, -10 }, RKnee = { -30, 0, 0 }, LKnee = { -30, 0, 0 },
		},
		arma = {
			Root = { -6, 20, 0 }, Neck = { 0, -10, 0 },
			RShoulder = { -40, 0, 70 }, RElbow = { 70, 0, 0 }, LShoulder = { 30, 0, -40 }, LElbow = { 30, 0, 0 },
			RHip = { 25, 0, 10 }, LHip = { 35, 0, -10 }, RKnee = { -45, 0, 0 }, LKnee = { -45, 0, 0 },
		},
		golpe = {
			Root = { -10, -15, 0 }, Waist = { -4, -5, 0 }, Neck = { 5, 10, 0 },
			RShoulder = { 92, 0, 8 }, RElbow = { 4, 0, 0 }, LShoulder = { 20, 0, -45 }, LElbow = { 35, 0, 0 },
			RHip = { -15, 0, 8 }, RKnee = { -20, 0, 0 }, LHip = { 35, 0, -8 }, LKnee = { -45, 0, 0 },
		},
	},
	-- ⚠️ v109 — ICE BLOCK: braço direito erguido juntando gelo (torção), soco à frente
	Gelo = {
		arma = {
			Root = { 0, -22, 0 }, Waist = { 0, -10, 0 }, Neck = { 8, 15, 0 },
			RShoulder = { 160, 0, 25 }, RElbow = { 25, 0, 0 }, LShoulder = { 35, 0, -35 }, LElbow = { 40, 0, 0 },
			RHip = { 30, 0, 12 }, LHip = { 35, 0, -12 }, RKnee = { -50, 0, 0 }, LKnee = { -55, 0, 0 },
		},
		golpe = {
			Root = { -12, 15, 0 }, Waist = { -4, 8, 0 }, Neck = { 6, -10, 0 },
			RShoulder = { 90, 0, 4 }, RElbow = { 0, 0, 0 }, LShoulder = { -15, 0, -40 }, LElbow = { 45, 0, 0 },
			RHip = { -15, 0, 8 }, RKnee = { -20, 0, 0 }, LHip = { 40, 0, -8 }, LKnee = { -50, 0, 0 },
		},
	},
	-- ⚠️ v109 — NEKKETSU PUNCH / SEIGI NO TEKKEN: arma o braço lá atrás (pisa pra
	-- trás) e soca reto à frente
	PunhoFrente = {
		arma = {
			Root = { 6, 25, 0 }, Neck = { 8, -12, 0 },
			RShoulder = { 150, 0, 30 }, RElbow = { 60, 0, 0 }, LShoulder = { 40, 0, -35 }, LElbow = { 40, 0, 0 },
			RHip = { 20, 0, 10 }, LHip = { 30, 0, -10 }, RKnee = { -35, 0, 0 }, LKnee = { -40, 0, 0 },
		},
		golpe = {
			Root = { -16, -18, 0 }, Waist = { -6, -6, 0 }, Neck = { 8, 10, 0 },
			RShoulder = { 88, 0, 4 }, RElbow = { 0, 0, 0 }, LShoulder = { -20, 0, -45 }, LElbow = { 50, 0, 0 },
			RHip = { -18, 0, 8 }, RKnee = { -18, 0, 0 }, LHip = { 45, 0, -8 }, LKnee = { -55, 0, 0 },
		},
	},
	-- ⚠️ v109 — FUUJIN RAIJIN: os dois punhos se batem na frente (raio num, vento
	-- no outro) e os braços abrem pros lados soltando as duas forças
	Deuses = {
		arma = {
			Root = { -6, 0, 0 }, Neck = { 6, 0, 0 },
			RShoulder = { 75, 0, -25 }, RElbow = { 70, 0, 0 }, LShoulder = { 75, 0, 25 }, LElbow = { 70, 0, 0 },
			RHip = { 30, 0, 14 }, LHip = { 30, 0, -14 }, RKnee = { -45, 0, 0 }, LKnee = { -45, 0, 0 },
		},
		golpe = {
			Root = { -4, 0, 0 }, Neck = { 12, 0, 0 },
			RShoulder = { 120, 0, 75 }, RElbow = { 35, 0, 0 }, LShoulder = { 120, 0, -75 }, LElbow = { 35, 0, 0 },
			RHip = { 25, 0, 18 }, LHip = { 25, 0, -18 }, RKnee = { -40, 0, 0 }, LKnee = { -40, 0, 0 },
		},
	},
	-- ⚠️ v108 — MAJIN THE HAND pelo ANIME (vídeo "Inazuma Eleven - Majin The
	-- Hand", quadros a cada 0,5s): punho direito no PEITO (puxa a energia do
	-- coração, 1.5-2s), GIRA o corpo com o braço erguido (7.5-8s) e empurra a mão
	-- junto com o demônio (12.5-15.5s). O giro é no RootCFrame (Giro = true).
	Demonio = {
		peito = {
			Root = { -4, 25, 0 }, Waist = { 0, 10, 0 }, Neck = { -10, -15, 0 },
			RShoulder = { 35, 0, -55 }, RElbow = { 125, 0, 0 }, LShoulder = { 30, 0, 45 }, LElbow = { 110, 0, 0 },
			RHip = { 30, 0, 12 }, LHip = { 35, 0, -12 }, RKnee = { -50, 0, 0 }, LKnee = { -50, 0, 0 },
		},
		giro = {
			Root = { 4, 0, 0 }, Neck = { 12, 0, 0 },
			RShoulder = { 165, 0, 15 }, RElbow = { 10, 0, 0 }, LShoulder = { 20, 0, -60 }, LElbow = { 30, 0, 0 },
			RHip = { 20, 0, 10 }, LHip = { 25, 0, -10 }, RKnee = { -30, 0, 0 }, LKnee = { -35, 0, 0 },
		},
		golpe = {
			Root = { -10, -15, 0 }, Waist = { -4, -5, 0 }, Neck = { 5, 10, 0 },
			RShoulder = { 92, 0, 8 }, RElbow = { 4, 0, 0 }, LShoulder = { 20, 0, -45 }, LElbow = { 35, 0, 0 },
			RHip = { -15, 0, 8 }, RKnee = { -20, 0, 0 }, LHip = { 35, 0, -8 }, LKnee = { -45, 0, 0 },
		},
	},
	-- ⚠️ v109 — GIGANT WALL (ギガントウォール) pelo vídeo do usuário + wiki: "ergue
	-- os dois braços, agacha e vira um GIGANTE; puxa o braço direito e SOCA a bola
	-- PRA BAIXO contra o campo, o braço coberto de energia azul; o campo racha e a
	-- bola para". Antes: arma alto e soca à frente.
	Punho = {
		arma = {
			Root = { 4, 0, 0 }, Neck = { 12, 0, 0 },
			RShoulder = { 168, 0, 20 }, RElbow = { 10, 0, 0 }, LShoulder = { 168, 0, -20 }, LElbow = { 10, 0, 0 },
			RHip = { 35, 0, 12 }, LHip = { 35, 0, -12 }, RKnee = { -60, 0, 0 }, LKnee = { -60, 0, 0 },
		},
		golpe = {
			Root = { -35, -10, 0 }, Waist = { -8, -6, 0 }, Neck = { 22, 6, 0 },
			RShoulder = { 55, 0, 6 }, RElbow = { 0, 0, 0 }, LShoulder = { 25, 0, -50 }, LElbow = { 40, 0, 0 },
			RHip = { 60, 0, 10 }, RKnee = { -85, 0, 0 }, LHip = { 30, 0, -10 }, LKnee = { -50, 0, 0 },
		},
	},
	-- ⚠️ v108 — TSUNAMI WALL pelo ANIME (vídeo "Inazuma Eleven - Tsunami Wall",
	-- quadros a cada 0,5s): os dois braços sobem BEM alto (13.5-14s) e ele BATE as
	-- duas mãos no chão (14.5-15s) — é daí que a parede sobe. Antes ele empurrava
	-- pra frente.
	Muralha = {
		arma = {
			Root = { 6, 0, 0 }, Neck = { 12, 0, 0 },
			RShoulder = { 170, 0, 18 }, LShoulder = { 170, 0, -18 }, RElbow = { 10, 0, 0 }, LElbow = { 10, 0, 0 },
			RHip = { 10, 0, 12 }, LHip = { 10, 0, -12 }, RKnee = { -15, 0, 0 }, LKnee = { -15, 0, 0 },
		},
		golpe = {
			Root = { -40, 0, 0 }, Neck = { 20, 0, 0 },
			RShoulder = { 55, 0, 12 }, LShoulder = { 55, 0, -12 }, RElbow = { 10, 0, 0 }, LElbow = { 10, 0, 0 },
			RHip = { 75, 0, 14 }, LHip = { 75, 0, -14 }, RKnee = { -95, 0, 0 }, LKnee = { -95, 0, 0 },
		},
	},
}

local function criarDefesa(chave, cfg)
	local S = {
		Motor = "V2", Efeitos = "Defesa", EstiloDefesa = cfg.Estilo, Defesa = true,
		ColarNoPe = false, TitleText = cfg.Titulo, Tema = cfg.Tema,
		ImpactTime = 0.8, -- o instante em que a técnica ENCONTRA a bola
		Phases = { Kick = { 99, 100 }, Summon = { 0, 0.8 } },
	}
	-- Duration acompanha a do QTE da guarda (PrepararDefesa)
	setmetatable(S, { __index = function(_, k) if k == "Duration" then return DEF_D end end })

	-- ⚠️ v108: cfg.Avanco = o goleiro AVANÇA baixo até a bola (Bakuretsu Punch,
	-- anime 8.5-10s); cfg.Giro = volta inteira do corpo (Majin The Hand)
	function S.RootPosition(t)
		if cfg.SaltoAntes then
			-- ⚠️ v110 — ESCUDO DE FORÇA pelo vídeo: salta alto (11-12.8s) e desce
			-- socando o chão na batida (0.62)
			local u = phase(t, 0.12, 0.62)
			return V3(0, cfg.SaltoAntes * math.sin(math.pi * u), 0)
		end
		if cfg.Salto then
			-- ⚠️ v110 — SOCO ARDENTE pelo vídeo "Nekketsu Punch" (0,1s): ele SALTA
			-- pra socar a bola no ar (1.3-1.8s) e cai depois do soco (6.3s+)
			local vai = smooth(phase(t, 0.4, 0.8))
			local altura = cfg.Salto * vai * (1 - smooth(phase(t, 0.9, 1.35)))
			return (cfg.Avanco or V3(0, 0, 0)) * vai + V3(0, altura, 0)
		end
		if cfg.Avanco then return cfg.Avanco * smooth(phase(t, 0.5, 0.8)) end
		return V3(0, 0, 0)
	end
	function S.RootCFrame(t)
		local pos = CFrame.new(S.RootPosition(t))
		if cfg.Giro then
			return pos * CFrame.Angles(0, 2 * math.pi * smooth(phase(t, 0.42, 0.74)), 0)
		end
		return pos
	end

	function S.BallPosition(t, s)
		s = s or V3(0, 0, -5)
		-- a bola chega empurrando (0..0.8) e fica tremendo contra a técnica
		local chega = V3(0, 0, -2.5):Lerp(V3(0, 0, 0), smooth(phase(t, 0, 0.8)))
		local treme = V3(math.sin(t * 53) * 0.12, math.sin(t * 47) * 0.12, math.sin(t * 31) * 0.25)
		return s + chega + (t > 0.8 and treme or V3(0, 0, 0))
	end
	function S.BallSpin(t) return t < 0.8 and 10 or 22 end

	local poses = POSE_DEFESA[cfg.Pose]
	function S.Pose(t)
		local pose
		if cfg.Pose == "Demonio" then
			pose = samplePose({
				{ 0.00, {} },
				{ 0.22, poses.peito },
				{ 0.45, poses.peito },
				{ 0.62, poses.giro },
				{ 0.80, poses.golpe },
				{ 10.0, poses.golpe },
			}, t)
			if t > 0.8 then
				local tr = math.sin(t * 38) * 2.5
				pose.RShoulder[1] += tr
				pose.Root[1] += tr * 0.4
			end
		elseif cfg.Pose == "Soco" then
			-- ⚠️ v106 — "coloca pro bot socar, como se estivesse tentando socar a
			-- bola". Antes os braços TROCAVAM de posição de uma vez (sem ir e
			-- voltar) — parecia bugado. Agora: guarda com os punhos em chamas até
			-- a bola chegar (0..0.8s), depois socos de verdade, alternados — o
			-- braço sai de trás, estica INTEIRO até a bola (ombro ~95°, reto pra
			-- frente) e volta, com o tronco girando pro lado do soco.
			local base = {
				Root = { -10, 0, 0 }, Neck = { 6, 0, 0 },
				RHip = { 25, 0, 10 }, LHip = { 35, 0, -10 }, RKnee = { -40, 0, 0 }, LKnee = { -45, 0, 0 },
			}
			if t < 0.8 then
				local u = smooth(phase(t, 0, 0.5))
				base.RShoulder = { 55 * u, 0, -10 * u }
				base.LShoulder = { 55 * u, 0, 10 * u }
				base.RElbow = { 110 * u, 0, 0 }
				base.LElbow = { 110 * u, 0, 0 }
				pose = samplePose({ { 0, base } }, 0)
			else
				local fase = (t - 0.8) * 6.5 -- ~3 socos por segundo por braço
				local i = math.floor(fase)
				local u = fase - i
				local ext = math.sin(u * math.pi) -- 0 -> 1 (esticado na bola) -> 0
				local direita = i % 2 == 0
				local soco = { -15 + 110 * ext, 0, (direita and 1 or -1) * (8 - 6 * ext) }
				local guarda = { 55, 0, direita and 10 or -10 }
				base.RShoulder = direita and soco or guarda
				base.LShoulder = direita and guarda or { soco[1], 0, -soco[3] }
				base.RElbow = { direita and (100 * (1 - ext)) or 110, 0, 0 }
				base.LElbow = { direita and 110 or (100 * (1 - ext)), 0, 0 }
				base.Root = { -10 - 8 * ext, (direita and -1 or 1) * 16 * ext, 0 }
				base.Neck = { 6, (direita and 1 or -1) * 8 * ext, 0 }
				pose = samplePose({ { 0, base } }, 0)
			end
		elseif cfg.Pose == "Mao" and poses.ergue then
			-- Mão Divina: ergue a mão acesa (0.18) → puxa pra trás carregando
			-- (0.55, com os relâmpagos) → empurra a palma na bola (0.8)
			pose = samplePose({
				{ 0.00, {} },
				{ 0.18, poses.ergue },
				{ 0.40, poses.ergue },
				{ 0.60, poses.arma },
				{ 0.80, poses.golpe },
				{ 10.0, poses.golpe },
			}, t)
			if t > 0.8 then
				local tr = math.sin(t * 38) * 2.5
				pose.RShoulder[1] += tr
				pose.Root[1] += tr * 0.4
			end
		else
			pose = samplePose({
				{ 0.00, {} },
				{ 0.45, poses.arma },
				{ 0.80, poses.golpe },
				{ 10.0, poses.golpe },
			}, t)
			if t > 0.8 then
				-- segurando a força da bola: o corpo treme
				local tr = math.sin(t * 38) * 2.5
				pose.RShoulder[1] += tr
				pose.Root[1] += tr * 0.4
			end
		end
		return pose
	end

	-- ⚠️ v107 — PEDIDO: "a God Hand, tem que aparecer a câmera, tem que dar pra
	-- ver o player, a God Hand e o chute impactando com ela. Às vezes corta. O
	-- socão dá pra dar uma distanciada um pouco maior". Antes: 14 studs e alvo
	-- a 1.5 de altura pra todas — a mão (agora maior) e o demônio (25 studs de
	-- altura) saíam do quadro. Agora cada defesa tem o seu enquadramento
	-- (cfg.Cam): mais longe, alvo mais alto e quase de LADO (perfil), que é o
	-- ângulo em que goleiro, técnica e bola aparecem juntos sem um tampar o outro.
	local cam = cfg.Cam or {}
	local RAIO, ALTURA, ALVO, FOV = cam.Raio or 20, cam.Altura or 5, cam.Alvo or 3, cam.Fov or 60
	function S.Camera(t, rootPos, ballPos)
		if cfg.CamFrente then
			-- ⚠️ v110 — MÃO DIVINA pelo vídeo a 0,1s: (1) antes do choque a câmera
			-- fica afastada e ALTA, do lado de quem chutou, pra mostrar a mão
			-- gigante inteira de pé atrás do goleiro (3.9-6.4s do vídeo); (2) no
			-- choque, DE FRENTE pra palma: a bola no centro e os raios de luz em
			-- volta (10.7-13.9s, o trecho mais longo). De perfil a mão virava lâmina.
			local pre = typeof(cfg.CamFrente) == "table" and cfg.CamFrente or {}
			if t < 0.8 then
				local u = smooth(phase(t, 0, 0.8))
				local pd, pa, pv = pre.PreDist or 24, pre.PreAlto or 5.5, pre.PreAlvo or 6
				local de = ballPos + V3(4, pa, -pd):Lerp(V3(3, pa - 1.5, -(pd - 7)), u)
				return de, rootPos + V3(0, pv - 2.5 * u, 0), 70
			end
			-- enquadramento de frente configurável (a Mão do Demônio precisa caber
			-- o demônio de ~25 studs inteiro)
			local cf2 = typeof(cfg.CamFrente) == "table" and cfg.CamFrente or {}
			local dist, alto, alvoY, fov = cf2.Dist or 15, cf2.Alto or 3.2, cf2.AlvoY or 2.2, cf2.Fov or 64
			local u = phase(t, 0.8, DEF_D)
			local alvo = ballPos + V3(0, alvoY, 1.2)
			return ballPos + V3(3.5 - 2 * u, alto - 0.6 * u, -dist + 2.5 * u), alvo, fov - 4 * u
		end
		if t < 0.8 then
			-- de trás da bola, afastado: a bola indo pro goleiro e ele inteiro no quadro
			local u = smooth(phase(t, 0, 0.8))
			return ballPos + V3(3, 3, -12):Lerp(V3(4, 2.6, -9), u), rootPos + V3(0, ALVO * 0.6, 0), 64
		end
		-- de perfil/diagonal, do lado de quem chutou; gira devagar e aproxima pouco
		local u = phase(t, 0.8, DEF_D)
		local ang = -0.72 + 0.34 * u
		local raio = RAIO * (1 - 0.1 * u)
		local centro = rootPos:Lerp(ballPos, 0.45) + V3(0, ALVO, 0)
		return centro + V3(math.cos(ang) * raio, ALTURA - u, math.sin(ang) * raio), centro, FOV - 4 * u
	end

	Cutscenes[chave] = S
	return S
end

criarDefesa("Defesa_MaoDivina", {
	Estilo = "MaoDivina", Pose = "Mao", Titulo = "MÃO DIVINA",
	CamFrente = true, -- ⚠️ v110: câmera pelo vídeo (ver S.Camera)
	Cam = { Raio = 27, Altura = 6, Alvo = 4.5, Fov = 62 },
	Tema = { Titulo = { rgb(255, 255, 235), rgb(255, 225, 110), rgb(255, 170, 30) }, Contorno = rgb(60, 35, 0),
		Flash = rgb(255, 250, 215), Tint = rgb(255, 245, 220), Saturation = 0.2, Contrast = 0.15, Brightness = 0.02 },
})
criarDefesa("Defesa_MaoDemonio", {
	Estilo = "MaoDemonio", Pose = "Demonio", Giro = true, Titulo = "MÃO DO DEMÔNIO",
	-- ⚠️ v110 (vídeo a 0,1s, 21-23.8s): no choque, de frente e de longe — o
	-- demônio atrás do goleiro e a mão dele segurando a bola (de perfil a mão
	-- virava lâmina)
	CamFrente = { Dist = 30, Alto = 9, AlvoY = 7, Fov = 70 },
	Cam = { Raio = 31, Altura = 8, Alvo = 8, Fov = 64 }, -- o demônio tem ~25 studs de altura
	-- ⚠️ v106: dourado/laranja, igual a arte do artista (era roxo)
	Tema = { Titulo = { rgb(255, 250, 200), rgb(255, 190, 50), rgb(220, 90, 20) }, Contorno = rgb(60, 20, 0),
		Flash = rgb(255, 235, 150), Tint = rgb(255, 238, 200), Saturation = 0.2, Contrast = 0.25, Brightness = 0 },
})
criarDefesa("Defesa_PunhoGigante", {
	Estilo = "PunhoGigante", Pose = "Punho", Titulo = "PUNHO GIGANTE",
	Cam = { Raio = 26, Altura = 9, Alvo = 6, Fov = 64 }, -- ⚠️ v109: mais alta — o soco vem de CIMA
	-- ⚠️ v109: energia AZUL (anime), com a pedra rachando embaixo
	Tema = { Titulo = { rgb(230, 245, 255), rgb(110, 180, 255), rgb(30, 90, 190) }, Contorno = rgb(10, 25, 60),
		Flash = rgb(225, 240, 255), Tint = rgb(225, 235, 250), Saturation = 0.15, Contrast = 0.18, Brightness = 0 },
})
criarDefesa("Defesa_MuralhaMare", {
	Estilo = "MuralhaMare", Pose = "Muralha", Titulo = "MURALHA DE MARÉ",
	Cam = { Raio = 24, Altura = 6, Alvo = 4, Fov = 60 },
	Tema = { Titulo = { rgb(230, 250, 255), rgb(90, 190, 255), rgb(20, 90, 210) }, Contorno = rgb(5, 30, 80),
		Flash = rgb(220, 245, 255), Tint = rgb(205, 230, 255), Saturation = 0.25, Contrast = 0.1, Brightness = 0 },
})
criarDefesa("Defesa_SocoExplosivo", {
	Estilo = "SocoExplosivo", Pose = "Soco", Titulo = "SOCO EXPLOSIVO",
	Avanco = V3(0, -0.55, -1.4), -- ⚠️ v108: avança baixo até a bola (anime)
	Cam = { Raio = 19, Altura = 4, Alvo = 2.5, Fov = 58 }, -- era 14: afastou pra ver os socos e a explosão inteiros
	Tema = { Titulo = { rgb(255, 245, 160), rgb(255, 150, 30), rgb(230, 40, 10) }, Contorno = rgb(70, 8, 0),
		Flash = rgb(255, 235, 190), Tint = rgb(255, 228, 205), Saturation = 0.25, Contrast = 0.12, Brightness = 0 },
})
-- ⚠️ v109 — GOLEIROS NOVOS (referências da wiki em PulseInstinctData)
criarDefesa("Defesa_BlocoGelo", {
	Estilo = "BlocoGelo", Pose = "Gelo", Titulo = "BLOCO DE GELO",
	-- ⚠️ v110 (vídeo "Ice Block" a 0,1s): de frente pro bloco de gelo
	CamFrente = { Dist = 15, Alto = 3.5, AlvoY = 1.8, PreDist = 12, PreAlto = 3, PreAlvo = 3.2 },
	Cam = { Raio = 20, Altura = 5, Alvo = 3, Fov = 60 },
	Tema = { Titulo = { rgb(255, 255, 255), rgb(170, 230, 255), rgb(80, 160, 230) }, Contorno = rgb(10, 40, 80),
		Flash = rgb(230, 250, 255), Tint = rgb(215, 235, 255), Saturation = -0.1, Contrast = 0.15, Brightness = 0.02 },
})
criarDefesa("Defesa_SocoArdente", {
	Estilo = "SocoArdente", Pose = "PunhoFrente", Titulo = "SOCO ARDENTE",
	Avanco = V3(0, 0, -2.8), Salto = 1.0, -- ⚠️ v110: salta pra socar (vídeo)
	CamFrente = { Dist = 14, Alto = 3.2, AlvoY = 2.2, PreDist = 13, PreAlto = 3, PreAlvo = 2.8 },
	Cam = { Raio = 19, Altura = 4, Alvo = 2.5, Fov = 58 },
	Tema = { Titulo = { rgb(255, 245, 170), rgb(255, 140, 40), rgb(210, 40, 10) }, Contorno = rgb(70, 10, 0),
		Flash = rgb(255, 230, 180), Tint = rgb(255, 228, 205), Saturation = 0.25, Contrast = 0.15, Brightness = 0 },
})
criarDefesa("Defesa_EscudoForca", {
	Estilo = "EscudoForca", Pose = "Muralha", Titulo = "ESCUDO DE FORÇA",
	SaltoAntes = 4.5, -- ⚠️ v110: salta e desce socando o chão (vídeo "Power Shield")
	CamFrente = { Dist = 22, Alto = 5, AlvoY = 3.5, PreDist = 18, PreAlto = 4, PreAlvo = 4 },
	Cam = { Raio = 24, Altura = 7, Alvo = 3.5, Fov = 62 },
	Tema = { Titulo = { rgb(255, 250, 210), rgb(255, 190, 70), rgb(230, 100, 20) }, Contorno = rgb(60, 25, 0),
		Flash = rgb(255, 240, 200), Tint = rgb(255, 238, 215), Saturation = 0.2, Contrast = 0.15, Brightness = 0 },
})
criarDefesa("Defesa_PunhoJustica", {
	Estilo = "PunhoJustica", Pose = "PunhoFrente", Titulo = "PUNHO DA JUSTIÇA",
	-- ⚠️ v110 (vídeo "Seigi no Tekken G5" a 0,1s): o choque é de FRENTE pro punho
	CamFrente = { Dist = 17, Alto = 4, AlvoY = 2.5, PreDist = 16, PreAlto = 4, PreAlvo = 3.5 },
	Cam = { Raio = 25, Altura = 6, Alvo = 4, Fov = 62 },
	Tema = { Titulo = { rgb(255, 255, 225), rgb(255, 220, 80), rgb(230, 150, 0) }, Contorno = rgb(60, 35, 0),
		Flash = rgb(255, 248, 210), Tint = rgb(255, 245, 220), Saturation = 0.2, Contrast = 0.15, Brightness = 0.02 },
})
criarDefesa("Defesa_FuujinRaijin", {
	Estilo = "FuujinRaijin", Pose = "Deuses", Titulo = "DEUSES DO VENTO E TROVÃO",
	-- ⚠️ v110 (vídeo a 0,1s): de frente e de longe — os dois deuses atrás dele
	CamFrente = { Dist = 32, Alto = 9, AlvoY = 8, Fov = 72, PreDist = 30, PreAlto = 8, PreAlvo = 9 },
	Cam = { Raio = 28, Altura = 7, Alvo = 5, Fov = 64 },
	Tema = { Titulo = { rgb(240, 255, 250), rgb(120, 230, 200), rgb(255, 220, 60) }, Contorno = rgb(10, 40, 40),
		Flash = rgb(240, 255, 250), Tint = rgb(225, 245, 240), Saturation = 0.15, Contrast = 0.2, Brightness = 0 },
})

-- qual cutscene de defesa cada Hissatsu de goleiro usa (pelo nome)
Cutscenes.DefesaPorNome = {
	["Bloco de Gelo"] = "Defesa_BlocoGelo",
	["Soco Ardente"] = "Defesa_SocoArdente",
	["Escudo de Força"] = "Defesa_EscudoForca",
	["Punho da Justiça"] = "Defesa_PunhoJustica",
	["Deuses do Vento e Trovão"] = "Defesa_FuujinRaijin",
	["Mão Divina"] = "Defesa_MaoDivina",
	["Mão do Demônio"] = "Defesa_MaoDemonio",
	["Punho Gigante"] = "Defesa_PunhoGigante",
	["Muralha de Maré"] = "Defesa_MuralhaMare",
	["Soco Explosivo"] = "Defesa_SocoExplosivo",
}

-- ============================================================
-- 🧠 FLOW DO ISAGI — "O GÊNIO DA ADAPTABILIDADE" (⚠️ v120)
-- ============================================================
-- PEDIDO: "replique o Flow do Isagi do vídeo (the genius of the adaptability)
-- ... COLORIDO, 10-12s, cada detalhe, a animação mais fluida possível".
-- ⚠️ v120 — REVISÃO quadro a quadro com o usuário (vídeo de 0,1 em 0,1s + o
-- clipe do YouTube mVkclcc3z-c, cabeça se desfazendo). PEDIDO: "ele tá deitado,
-- cai suor, tá cansado, fica frustrado e levanta com força; o olho brilha BRANCO
-- ANTES de ver o Rin, ainda no chão; levanta com o joelho subindo devagar; os
-- riscos pretos ATRÁS dele, maiores; neblina quase branca; fica puto, levanta o
-- olho; close no olho ESQUERDO com o quebra-cabeça estático; puxa pro branco de
-- dentro do quebra-cabeça = o branco do fundo do Rin correndo do lado dele (braço
-- bem pra trás, exagerado); o redemoinho ocupa a tela inteira fechando a visão;
-- abre no mundo dele (fundo branco, chão preto); o pé pisa devagar e surgem peças
-- do chão; no fim ele dá um DASH pra frente com os braços pra trás (não abre os
-- braços); o olho fica branco, ele pisca e fica o olho de quebra-cabeça; a cabeça
-- se desfaz em peças de quebra-cabeça".
-- ⚠️ v120b — REVISÃO 2: "a levantada tá perfeita; depois NÃO corta pra cara: o olho
-- branco se TRANSFORMA no olho do Flow sem mudar a câmera e aí dá zoom direto no
-- olho; o olho é nos DOIS lados, NA CARA (no lugar do olho, não na frente do
-- cabelo); o Rin não passa por trás: ele JÁ está na frente, em câmera lenta, da
-- visão do Isagi (a maior parte é a cara dele), fundo branco; a espiral começa
-- olhando o Rin, escurece TOTALMENTE, cresce e gira; as mãos não podem entrar no
-- tronco — movimento exagerado pra fora".
--   A  Caido      0.0-1.6  de quatro na grama, neblina, suor pingando, ofegante
--   B  Rosto      1.6-2.6  close no rosto: frustrado, balança a cabeça, soca o chão
--   C  Levanta    2.6-4.4  olhos acendem BRANCOS ainda no chão; sobe com o joelho
--                          (devagar), riscos pretos grandes ATRÁS dele
--   D  Transforma 4.4-5.2  MESMA câmera da levantada: o branco dos olhos vira a
--                          íris de quebra-cabeça (nos dois olhos, no rosto)
--   E  Olho       5.2-6.6  zoom direto no olho ESQUERDO; a câmera entra no miolo branco
--   F  Rin        6.6-8.0  da visão dele (a cara dele ocupando a tela): o RIN já na
--                          frente, correndo em câmera lenta, fundo branco
--   G  Visao      8.0-8.9  a espiral escurece tudo, cresce e gira, fechando a visão
--   H  Pisa     8.9-10.3 o mundo dele (fundo branco, chão escuro); o pé pisa
--                        devagar e as peças surgem do chão
--   K  Dash     10.3-12  olhos brancos → DASH com os braços pra trás → pisca →
--                        olhos de quebra-cabeça; a cabeça se desfaz em peças
-- Interpolação Catmull-Rom (passa pelas poses sem parar) + respiração por cima.
-- A câmera dos closes vem dos efeitos (FlowIsagi.CameraMundo), que seguem a
-- cabeça/olho/pé DE VERDADE de qualquer avatar.
local FI = {}
Cutscenes.Flow_Isagi = FI
FI.Motor = "V2"
FI.Efeitos = "FlowIsagi"
FI.KickFoot = "Right"
FI.Duration = 12
FI.ImpactTime = 10.55 -- o DASH (explosão de cor)
FI.ColarNoPe = false
FI.SemTremidaImpacto = true -- o fim é close nos olhos: a tremida padrão do impacto sacudia a imagem
FI.CompanheiroAleatorio = true -- o servidor sorteia alguém pra ser o Rin (time → qualquer jogador → goleiro bot)
FI.TitleText = "FLOW · ISAGI YOICHI"
FI.Tema = {
	Titulo = { rgb(255, 255, 255), rgb(160, 210, 255), rgb(40, 110, 220) },
	Contorno = rgb(5, 15, 35), Flash = rgb(225, 240, 255),
	Tint = rgb(255, 255, 255), Saturation = 0, Contrast = 0.08, Brightness = 0,
}
FI.Phases = {
	Caido = { 0, 1.6 }, Rosto = { 1.6, 2.6 }, Levanta = { 2.6, 4.4 }, Transforma = { 4.4, 5.2 },
	Olho = { 5.2, 6.6 }, Rin = { 6.6, 8.0 }, Visao = { 8.0, 8.9 }, Pisa = { 8.9, 10.3 },
	Dash = { 10.3, 12 },
	Kick = { 10.45, FI.ImpactTime }, Impact = { FI.ImpactTime, FI.Duration },
}
FI.Pisada = 9.55 -- o pé toca o chão (a batida da música cai aqui)

-- Catmull-Rom: passa por todos os quadros com velocidade contínua (sem o
-- "para-e-anda" do smoothstep entre poses)
local function catmull(p0, p1, p2, p3, u)
	local u2, u3 = u * u, u * u * u
	return 0.5 * ((2 * p1) + (p2 - p0) * u + (2 * p0 - 5 * p1 + 4 * p2 - p3) * u2 + (3 * p1 - p0 - 3 * p2 + p3) * u3)
end
local function segmento(keys, t)
	local n = #keys
	if t <= keys[1][1] then return 1, 1, 0 end
	if t >= keys[n][1] then return n, n, 0 end
	for i = 1, n - 1 do
		if t <= keys[i + 1][1] then return i, i + 1, phase(t, keys[i][1], keys[i + 1][1]) end
	end
	return n, n, 0
end
local function sampleFluido(keys, t)
	local i1, i2, u = segmento(keys, t)
	local n = #keys
	local a, b = keys[math.max(i1 - 1, 1)][2], keys[i1][2]
	local c, d = keys[i2][2], keys[math.min(i2 + 1, n)][2]
	return catmull(a, b, c, d, u)
end
local function samplePoseFluida(keys, t)
	local i1, i2, u = segmento(keys, t)
	local n = #keys
	local k0, k1, k2, k3 = keys[math.max(i1 - 1, 1)][2], keys[i1][2], keys[i2][2], keys[math.min(i2 + 1, n)][2]
	local pose = {}
	for _, nome in ipairs(JOINTS) do
		local v0, v1, v2, v3 = k0[nome] or ZERO, k1[nome] or ZERO, k2[nome] or ZERO, k3[nome] or ZERO
		pose[nome] = {
			catmull(v0[1], v1[1], v2[1], v3[1], u),
			catmull(v0[2], v1[2], v2[2], v3[2], u),
			catmull(v0[3], v1[3], v2[3], v3[3], u),
		}
	end
	return pose
end
Cutscenes.SamplePoseFluida = samplePoseFluida

-- altura do quadril (R6: o HRP é o centro do tronco)
--   de quatro (aprovado): Chao + 1.45 · ajoelhado subindo: Chao + 1.9 → 2.5 · de pé: 0
local function fiAltura(t)
	local quatro = CAL.Chao + 1.45
	return sampleFluido({
		{ 0, quatro }, { 2.65, quatro }, { 3.15, CAL.Chao + 1.9 }, { 3.8, CAL.Chao + 2.5 }, { 4.4, 0 },
		{ 10.3, 0 }, { 10.5, -0.25 }, { 10.75, -0.45 }, { 12, -0.45 },
	}, t)
end
-- o dash: ele avança de verdade (a câmera recua junto)
local FI_Z = { { 0, 0 }, { 10.45, 0 }, { 10.55, 0.15 }, { 11.2, -4.2 }, { 12, -5.2 } }
function FI.RootPosition(t)
	local respira = 0.05 * math.sin(t * (t < 4.4 and 5.5 or 3)) -- ofegante no chão
	return V3(0, fiAltura(t) + respira, sampleFluido(FI_Z, t))
end
function FI.RootCFrame(t) return CFrame.new(FI.RootPosition(t)) end
function FI.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FI.BallVisible(t) return t < 0.05 end
function FI.BallSpin() return 0 end

-- de quatro (o take aprovado): tronco 65° pra frente, coxa e braço retos
local FI_QUATRO = {
	Root = { -65, 0, 0 }, Neck = { -28, 0, 0 },
	RHip = { 65, 0, 4 }, LHip = { 65, 0, -4 }, RKnee = { -88, 0, 0 }, LKnee = { -88, 0, 0 },
	RShoulder = { 62, 0, 8 }, LShoulder = { 66, 0, -8 }, RElbow = { 12, 0, 0 }, LElbow = { 8, 0, 0 },
}
local function comMudanca(base, mud)
	local p = {}
	for k, v in pairs(base) do p[k] = v end
	for k, v in pairs(mud) do p[k] = v end
	return p
end
-- R6 (braço reto): direção do braço d = (sen rz, −cos rz·cos rx, −cos rz·sen rx)
--   braço pra trás: rx NEGATIVO (−60 = 60° atrás da vertical)
-- ⚠️ v120b — PEDIDO: "a mão tá entrando dentro do personagem: é pra ser um movimento
-- EXAGERADO pra fora". Braço R6 é reto: com |rz| pequeno ele atravessa o tronco
-- (principalmente com o tronco inclinado). Regra: |rz| ≥ 20 parado, ≥ 40 em
-- movimento/pra trás.
-- ⚠️ v120e — PEDIDO: "o braço vai um pouco pra frente do torso: coloca ele pra ir
-- pra TRÁS do corpo, afastado, um pouco de lado; uma pose mais da hora no final".
-- Braços bem pra trás e abertos (d ≈ 0.8 de lado, 0.55 pra trás), tronco torcido de
-- lado, passada larga e a cabeça projetada pra frente.
local FI_DASH = {
	Root = { -36, 14, 0 }, Neck = { 30, -10, 0 },
	RHip = { 70, 0, 8 }, LHip = { -40, 0, -8 },
	-- ⚠️ v122 — PEDIDO: "o braço está muito pra cima e muito pra frente: o OMBRO, o braço
	-- inteiro, tem que estar mais pra TRÁS". Com o tronco 36° pra frente, braço "pra
	-- trás do tronco" aponta pra CIMA no mundo; (−78, 74) apontava 96% pro lado. Agora
	-- (−50, 20): no mundo 94% pra trás, levemente pra baixo e um pouco aberto (medido).
	-- (v122 teste: na câmera 3/4 do dash, braço na HORIZONTAL pra trás parecia aberto
	-- em T; um pouco abaixo da horizontal lê como "jogado pra trás")
	RShoulder = { -40, 0, 18 }, LShoulder = { -40, 0, -18 },
}
local FI_POSE = {
	{ 0.00, FI_QUATRO },
	{ 1.60, comMudanca(FI_QUATRO, { Neck = { -14, 0, 0 } }) },
	-- B: frustrado — a cabeça afunda, balança ("não"), e o braço direito soca o chão
	{ 1.90, comMudanca(FI_QUATRO, { Neck = { -20, 0, 0 } }) },
	{ 2.05, comMudanca(FI_QUATRO, { Neck = { -18, 14, 0 } }) },
	{ 2.20, comMudanca(FI_QUATRO, { Neck = { -18, -14, 0 }, RShoulder = { 30, 0, 12 } }) },
	{ 2.32, comMudanca(FI_QUATRO, { Neck = { -20, 6, 0 }, RShoulder = { 66, 0, 8 } }) }, -- SOCO no chão
	{ 2.60, comMudanca(FI_QUATRO, { Neck = { 0, 0, 0 } }) },
	-- C: os olhos acendem e ele levanta a cabeça ainda de quatro...
	{ 2.85, comMudanca(FI_QUATRO, { Neck = { 34, 0, 0 } }) },
	-- ...e sobe COM O JOELHO: a perna direita vai à frente, a mão no joelho
	{ 3.15, { Root = { -48, 0, 0 }, Neck = { 44, 0, 0 }, RHip = { 95, 0, 6 }, LHip = { 22, 0, -4 },
		RShoulder = { 58, 0, 22 }, LShoulder = { 40, 0, -24 } } },
	{ 3.80, { Root = { -26, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { 62, 0, 6 }, LHip = { -6, 0, -4 },
		RShoulder = { 34, 0, 24 }, LShoulder = { 12, 0, -24 } } },
	-- D: de pé, puto, ergue os olhos
	{ 4.40, { Root = { -6, 0, 0 }, Neck = { 18, 0, 0 }, RShoulder = { 4, 0, 20 }, LShoulder = { 4, 0, -20 },
		RHip = { 0, 0, 5 }, LHip = { 0, 0, -5 } } },
	{ 5.20, { Root = { -3, 0, 0 }, Neck = { 22, 0, 0 }, RShoulder = { 6, 0, 22 }, LShoulder = { 6, 0, -22 },
		RHip = { 0, 0, 5 }, LHip = { 0, 0, -5 } } },
	-- E-F: parado (o zoom no olho; olhando o Rin lá na frente)
	{ 6.60, { Root = { -3, 0, 0 }, Neck = { 10, 0, 0 }, RShoulder = { 4, 0, 20 }, LShoulder = { 4, 0, -20 },
		RHip = { 0, 0, 5 }, LHip = { 0, 0, -5 } } },
	{ 8.90, { Root = { -4, 0, 0 }, Neck = { 2, 0, 0 }, RShoulder = { 2, 0, 20 }, LShoulder = { 2, 0, -20 },
		RHip = { 0, 0, 5 }, LHip = { 0, 0, -5 } } },
	-- H: ergue o pé direito... segura... e PISA devagar
	{ 9.25, { Root = { -6, 0, 0 }, Neck = { -6, 0, 0 }, RHip = { 58, 0, 4 }, LHip = { 0, 0, -4 },
		RShoulder = { -14, 0, 26 }, LShoulder = { 20, 0, -26 } } },
	{ 9.38, { Root = { -7, 0, 0 }, Neck = { -8, 0, 0 }, RHip = { 52, 0, 4 }, LHip = { 0, 0, -4 },
		RShoulder = { -16, 0, 28 }, LShoulder = { 22, 0, -28 } } },
	{ FI.Pisada, { Root = { -12, 0, 0 }, Neck = { -10, 0, 0 }, RHip = { 14, 0, 4 }, LHip = { -8, 0, -4 },
		RShoulder = { -26, 0, 34 }, LShoulder = { 30, 0, -34 } } },
	{ 10.30, { Root = { -10, 0, 0 }, Neck = { 14, 0, 0 }, RHip = { 12, 0, 4 }, LHip = { -6, 0, -4 },
		RShoulder = { -14, 0, 30 }, LShoulder = { 14, 0, -30 } } },
	-- K: carrega o dash (agacha, olhos brancos)...
	{ 10.48, { Root = { -20, 0, 0 }, Neck = { 26, 0, 0 }, RHip = { 34, 0, 6 }, LHip = { 10, 0, -6 },
		RShoulder = { -25, 0, 62 }, LShoulder = { -25, 0, -62 } } },
	-- ...e DISPARA pra frente com os braços pra trás (bem abertos)
	{ 10.70, FI_DASH },
	{ 12.00, comMudanca(FI_DASH, { Root = { -32, 16, 0 }, RShoulder = { -44, 0, 20 }, LShoulder = { -44, 0, -20 } }) },
}
function FI.Pose(t)
	local pose = samplePoseFluida(FI_POSE, t)
	-- respiração (ofegante no chão, funda de pé)
	local f = t < 4.4 and 5.5 or 3
	local amp = t < 2.6 and 2.2 or (t < 4.4 and 1.4 or 1.0)
	pose.Root[1] += amp * math.sin(t * f)
	pose.Neck[1] += amp * 0.6 * math.sin(t * f - 0.6)
	-- ⚠️ v122 — PEDIDO: "faça o jogador se ARREPIAR". Do olho acender até a
	-- transformação, um tremor fino no corpo inteiro (arrepio), mais forte quando ele
	-- fica de pé puto (4.4-5.2).
	if t >= 2.75 and t < 5.6 then
		local k = (t >= 4.4 and t < 5.2) and 1 or 0.55
		local tremor = 0.9 * k * math.sin(t * 41)
		pose.RShoulder[1] += tremor
		pose.LShoulder[1] -= tremor
		pose.Root[3] += 0.7 * k * math.sin(t * 47 + 1)
		pose.Neck[3] += 0.8 * k * math.sin(t * 29)
		pose.Neck[1] += 0.5 * k * math.sin(t * 53)
	end
	return pose
end

-- O RIN: alguém de verdade (o servidor sorteia; sem ninguém vira uma sombra
-- verde-água) JÁ NA FRENTE dele, correndo pra longe em CÂMERA LENTA, no branco.
-- ⚠️ v120 — PEDIDO: "o Rin tá correndo estranho: precisa correr com o braço
-- mais pra trás, exageradamente, igual no take" (no vídeo 10,0-10,8s o braço
-- vai esticado pra trás, o tronco bem inclinado).
local function fiRinPos(t)
	local u = phase(t, 6.6, 8.9)
	-- (v122: mais longe — no teste ele enchia a tela e parecia gigante)
	return V3(0.9, 0, -10 - 6 * u)
end
local RIN_LENTO = 0.42 -- câmera lenta (fração da passada normal)
-- ⚠️ v122 — PEDIDO: "a animação do jogador correr está estranha: faz ele correr de um
-- jeito mais fluido (pode procurar no Google, se esforça)". Ciclo de corrida de
-- verdade (referência: as 4 poses de corrida — contato, descida, impulso e voo; braço
-- oposto à perna; quadril e ombros torcendo em sentidos opostos; o corpo sobe e desce
-- 2x por passada, mais baixo na descida e mais alto no voo). Passado pela Catmull-Rom
-- (sem "para-e-anda"). R6: perna e braço retos, braço aberto do corpo.
-- Quadril da perna DIREITA ao longo da passada (φ 0→1); a esquerda é φ+0.5.
local CORRIDA_QUADRIL = {
	{ 0.000, 40 },  -- contato: perna da frente
	{ 0.125, 24 },  -- descida (carga)
	{ 0.250, 2 },   -- passando sob o corpo
	{ 0.375, -26 }, -- impulso
	{ 0.500, -40 }, -- voo: perna de trás esticada
	{ 0.625, -22 }, -- volta (rápida)
	{ 0.750, 14 },
	{ 0.875, 38 },  -- chega na frente antes do contato
	{ 1.000, 40 },
}
local function quadrilCorrida(f)
	f = f % 1
	for i = 1, #CORRIDA_QUADRIL - 1 do
		local a, b = CORRIDA_QUADRIL[i], CORRIDA_QUADRIL[i + 1]
		if f <= b[1] then
			local u = (f - a[1]) / (b[1] - a[1])
			local p0 = CORRIDA_QUADRIL[i - 1] and CORRIDA_QUADRIL[i - 1][2] or CORRIDA_QUADRIL[#CORRIDA_QUADRIL - 1][2]
			local p3 = CORRIDA_QUADRIL[i + 2] and CORRIDA_QUADRIL[i + 2][2] or CORRIDA_QUADRIL[2][2]
			return catmull(p0, a[2], b[2], p3, u)
		end
	end
	return CORRIDA_QUADRIL[1][2]
end
local function poseCorrida(fase)
	local hr = quadrilCorrida(fase)
	local hl = quadrilCorrida(fase + 0.5)
	local w2 = math.cos(4 * math.pi * fase)
	local tor = math.cos(2 * math.pi * fase)
	return {
		Root = { -18 + 3 * w2, 6 * tor, 0 },
		Neck = { 14 - 2 * w2, -4 * tor, 0 },
		RHip = { hr, 0, 4 }, LHip = { hl, 0, -4 },
		-- braço oposto à perna (o direito acompanha a perna ESQUERDA), um pouco mais
		-- pra frente que pra trás, e abrindo mais quando vai pra trás
		RShoulder = { 0.95 * hl + 8, 0, 16 + 6 * math.max(0, -hl / 40) },
		LShoulder = { 0.95 * hr + 8, 0, -(16 + 6 * math.max(0, -hr / 40)) },
	}
end
local function alturaCorrida(fase)
	-- mais baixo na descida (φ 0.125 / 0.625), mais alto no voo (0.375 / 0.875)
	return 0.13 + 0.13 * math.cos(4 * math.pi * (fase - 0.375))
end
local RIN_FREQ = 1.8 * RIN_LENTO -- passadas por segundo (câmera lenta)
FI.Clones = {
	Quantidade = 1,
	-- ⚠️ v122: no fundo branco (neblina + correção de cor clara) o companheiro ficava
	-- LAVADO, quase branco. Um véu azul-escuro por cima dá a silhueta forte do take
	-- (no vídeo o Rin é escuro contra o branco) sem esconder quem ele é.
	Cor = rgb(16, 28, 44),
	Contorno = { Fill = 0.35, Outline = rgb(150, 255, 230), OutlineTransp = 0.35 },
	CFrame = function(_i, t)
		local p = fiRinPos(t)
		local bob = alturaCorrida(t * RIN_FREQ)
		return CFrame.lookAt(p + V3(0, bob, 0), p + V3(0, bob, -1))
	end,
	-- ⚠️ v120c — PEDIDO: "do nada aparece um cara mexendo o braço estranho. Você
	-- acabou de levantar e está olhando o jogador correndo pra frente: ele está DE
	-- COSTAS correndo (vídeo 10,0-11,0s)". Corrida normal vista de trás, em câmera
	-- lenta: braço oposto à perna, bem aberto do corpo (R6 não pode encostar no tronco).
	Pose = function(_i, t)
		return poseCorrida(t * RIN_FREQ)
	end,
	Alpha = function(_i, t)
		-- (some dentro da espiral, quando a visão fecha)
		if t >= 6.6 and t < 8.62 then return smooth(phase(t, 6.6, 6.95)) * (1 - smooth(phase(t, 8.45, 8.62))) end
		return 0
	end,
}
FI.RinPos = fiRinPos

-- câmera BASE (planos abertos; os closes vêm de FlowIsagi.CameraMundo)
function FI.Camera(t, rootPos)
	if t < 1.6 then
		-- o take aprovado
		local u = smooth(phase(t, 0, 1.6))
		return V3(4.6, CAL.Chao + 1.1, -5.6):Lerp(V3(3.8, CAL.Chao + 1.0, -4.7), u), rootPos + V3(0, -0.3, -0.6), 48
	elseif t >= 2.6 and t < 4.4 then
		-- de frente e baixa: ele sobe na direção da câmera (riscos pretos ATRÁS dele)
		local u = smooth(phase(t, 2.6, 4.4))
		return V3(0.9, CAL.Chao + 0.9, -6.6):Lerp(V3(0.6, CAL.Chao + 2.4, -5.6), u), rootPos + V3(0, -0.2 + 1.1 * u, 0), 52
	end
	return V3(0, 1, -6), rootPos + V3(0, 1.4, 0), 45
end


-- ============================================================
-- 👾 FLOW DO BACHIRA — cena de ativação (⚠️ v113)
-- ============================================================
-- PEDIDO: "Bachira segurando a mão do monstro". Pelo vídeo ("Goodbye,
-- Monster", visão geral a cada 2,5s): o vazio claro/enevoado (65-67s), a
-- MÃO do monstro com garras se estendendo (77.5s), o menino andando com o
-- monstro (85-90s), os olhos AMARELOS arregalados (100-105s).
--   0.0-2.0  ele no vazio claro; o monstro (preto, olhos amarelos, sorriso
--            de dentes, chifres) surge atrás, à esquerda;
--   2.0-4.5  o monstro estende a mão com garras; ele segura (close nas mãos);
--   4.5-7.5  os dois andam de mãos dadas;
--   7.5-9.0  solta a mão, pose de drible; o mundo escurece, olhos amarelos;
--   9.0-10.2 o monstro entra nele (fumaça preta e amarela);
--   10.2-12  pose final com a aura amarela.
-- O monstro é montado de peças nos efeitos (FlowBachira) e o braço direito
-- dele vai até a mão esquerda do Bachira de verdade, quadro a quadro.
local FB = {}
Cutscenes.Flow_Bachira = FB
FB.Motor = "V2"
FB.Efeitos = "FlowBachira"
FB.KickFoot = "Right"
FB.Duration = 12
FB.ImpactTime = 10.2 -- o monstro entra nele
FB.ColarNoPe = false
FB.TitleText = "FLOW · BACHIRA MEGURU"
FB.Tema = {
	Titulo = { rgb(255, 255, 230), rgb(255, 215, 70), rgb(160, 110, 10) },
	Contorno = rgb(30, 20, 5), Flash = rgb(255, 235, 150),
	Tint = rgb(255, 250, 235), Saturation = 0.1, Contrast = 0.15, Brightness = 0,
}
FB.Phases = {
	Surge = { 0, 2 }, Mao = { 2, 4.5 }, Andam = { 4.5, 7.5 }, Drible = { 7.5, 9 },
	Entra = { 9, FB.ImpactTime }, Final = { FB.ImpactTime, 12 },
	Kick = { 9.8, FB.ImpactTime }, Impact = { FB.ImpactTime, FB.Duration },
}
local FB_ROOT = {
	{ 0, V3(0, 0, 0) }, { 4.5, V3(0, 0, 0) }, { 7.5, V3(0, 0, -8) },
	{ 8.0, V3(0, -0.4, -8.4) }, { 9.0, V3(0, -0.4, -8.6) }, { 10.2, V3(0, -0.2, -8.6) }, { 12, V3(0, -0.2, -8.6) },
}
function FB.RootPosition(t) return sample(FB_ROOT, t) end
function FB.RootCFrame(t)
	-- na pose de drible gira um pouco pro lado (o jeito dele de dançar com a bola)
	local giro = 0
	if t >= 7.5 and t < 9 then giro = math.sin((t - 7.5) * 6) * 18 end
	return CFrame.new(FB.RootPosition(t)) * CFrame.Angles(0, rad(giro), 0)
end
function FB.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FB.BallVisible(t) return t < 0.05 end
function FB.BallSpin() return 0 end
FB.PontoMao = nil -- (usado pelos efeitos: onde as mãos se encontram)

local FB_MAO = { LShoulder = { 25, 0, -62 } } -- braço esquerdo erguido pro monstro
local FB_POSE = {
	{ 0.00, {} },
	-- olha pra cima, pro monstro atrás/à esquerda
	{ 1.20, { Neck = { 22, -35, 0 }, RShoulder = { -5, 0, 10 }, LShoulder = { -5, 0, -10 } } },
	{ 2.20, { Neck = { 18, -45, 0 }, RShoulder = { -5, 0, 10 }, LShoulder = { 0, 0, -30 } } },
	{ 3.20, { Neck = { 15, -45, 0 }, RShoulder = { -5, 0, 10 }, LShoulder = FB_MAO.LShoulder } },
	{ 4.50, { Neck = { 10, -30, 0 }, RShoulder = { -5, 0, 10 }, LShoulder = FB_MAO.LShoulder } },
	-- (4.5-7.5: andando de mãos dadas, calculado abaixo)
	-- drible: agachado, braços abertos, joelho pra fora
	{ 7.80, { Root = { -20, 0, 0 }, Neck = { 18, 0, 0 }, RHip = { 40, 0, 20 }, LHip = { 30, 0, -12 },
		RShoulder = { 10, 0, 70 }, LShoulder = { 10, 0, -70 } } },
	{ 9.00, { Root = { -22, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 45, 0, 22 }, LHip = { 28, 0, -14 },
		RShoulder = { 15, 0, 75 }, LShoulder = { 15, 0, -75 } } },
	-- o monstro entra: joga a cabeça pra trás
	{ 9.80, { Root = { 8, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { 10, 0, 10 }, LHip = { 10, 0, -10 },
		RShoulder = { 30, 0, 100 }, LShoulder = { 30, 0, -100 } } },
	-- pose final: inclinado pra frente, braços abertos, joelho direito erguido (riso)
	{ FB.ImpactTime, { Root = { -16, 0, 0 }, Neck = { 22, 0, 0 }, RHip = { 70, 0, 12 }, LHip = { -10, 0, 0 },
		RShoulder = { 20, 0, 85 }, LShoulder = { 20, 0, -85 } } },
	{ 12.00, { Root = { -18, 0, 0 }, Neck = { 24, 0, 0 }, RHip = { 75, 0, 12 }, LHip = { -12, 0, 0 },
		RShoulder = { 22, 0, 88 }, LShoulder = { 22, 0, -88 } } },
}
function FB.Pose(t)
	if t >= 4.5 and t < 7.5 then
		-- andando (passada calma), braço esquerdo segurando a mão dele
		local w = math.sin((t - 4.5) * math.pi * 2 * 1.3)
		return {
			Root = { -3, 0, 0 }, Neck = { 12, -25, 0 },
			RHip = { 28 * w, 0, 0 }, LHip = { -28 * w, 0, 0 },
			RShoulder = { -22 * w, 0, 8 }, LShoulder = FB_MAO.LShoulder,
		}
	end
	return samplePose(FB_POSE, t)
end

function FB.Camera(t, rootPos)
	if t < 2 then
		-- aberta, de trás e baixa: ele pequeno e o monstro surgindo
		local u = smooth(phase(t, 0, 2))
		return V3(5, 0.2, 11):Lerp(V3(4, 0.6, 9.5), u), V3(-1.8, 3.2, 0), 55
	elseif t < 4.5 then
		-- close nas mãos se encontrando
		local u = smooth(phase(t, 2, 4.5))
		-- (mira no ponto das mãos, na altura da cintura dele)
		return V3(-0.4, -0.1, -5.6):Lerp(V3(-0.9, 0.1, -4.6), u), V3(-2.3, 0.4, -0.3), 46
	elseif t < 7.5 then
		-- DE COSTAS: os dois indo embora de mãos dadas (a imagem clássica; de
		-- lado o monstro ficava escondido atrás dele)
		local u = smooth(phase(t, 4.5, 7.5))
		return rootPos + V3(-1.2, 1.2, 10 - 2 * u), rootPos + V3(-1.9, 2.2, -2), 52
	elseif t < 9 then
		-- de frente e baixa: a pose de drible, o monstro enorme atrás
		return rootPos + V3(1.8, -1.2, -6.5), rootPos + V3(-0.8, 1.6, 0), 58
	end
	local u = smooth(phase(t, 9, 12))
	return rootPos + V3(2.2, -1.4, -5.2):Lerp(V3(1.3, -1, -3.9), u), rootPos + V3(0, 1, 0), 58
end


-- ============================================================
-- 🪶 FLOW DO NAGI — cena de ativação (⚠️ v113)
-- ============================================================
-- PEDIDO: "Nagi". Pelo vídeo ("Nagi's Inhuman Goal", U-20, visão geral a cada
-- 2s): a bola cai do alto e ele a MATA no pé (8-14s); levanta, salta e
-- "agarra" a bola com o pé no ar; GIRA na horizontal no ar (32-36s, 46-48s);
-- finge o voleio, deixa a bola cair e bate de verdade (a finta em dois tempos);
-- GOL. Tudo com a cara de preguiça dele. Motivo da loja: penas.
--   0.0-1.6 a bola cai do céu no pé erguido;  1.6-2.0 amortece até o chão;
--   2.0-2.6 levanta;  2.6-3.8 salta e prende no pé no ar;
--   3.8-6.2 gira na horizontal (duas voltas);  6.2-7.0 finge o voleio;
--   7.0-7.4 bate de verdade (a outra perna);  7.4-9.0 a bola some no fundo;
--   9.0-12  pousa, cabeça de lado, olhos claros, penas caindo.
-- A bola da cena é uma cópia (a de verdade não sai do lugar).
local FN = {}
Cutscenes.Flow_Nagi = FN
FN.Motor = "V2"
FN.Efeitos = "FlowNagi"
FN.KickFoot = "Right"
FN.Duration = 12
FN.ImpactTime = 7.4
FN.ColarNoPe = false
FN.TitleText = "FLOW · NAGI SEISHIRO"
FN.Tema = {
	Titulo = { rgb(255, 255, 255), rgb(225, 235, 255), rgb(140, 160, 200) },
	Contorno = rgb(20, 25, 40), Flash = rgb(240, 245, 255),
	Tint = rgb(235, 240, 255), Saturation = -0.1, Contrast = 0.12, Brightness = 0,
}
FN.Phases = {
	Cai = { 0, 1.6 }, Amortece = { 1.6, 2.0 }, Levanta = { 2.0, 2.6 }, Prende = { 2.6, 3.8 },
	Gira = { 3.8, 6.2 }, Finta = { 6.2, 7.0 }, Kick = { 7.0, FN.ImpactTime },
	Voa = { FN.ImpactTime, 9 }, Final = { 9, 12 }, Impact = { FN.ImpactTime, FN.Duration },
}
local FN_ROOT = {
	{ 0, V3(0, 0, 0) }, { 2.6, V3(0, 0, 0) }, { 2.8, V3(0, -0.5, 0) },
	{ 3.8, V3(0, 4.2, -1) }, { 6.2, V3(0, 5, -1.6) }, { 7.4, V3(0, 4.6, -2) },
	{ 8.4, V3(0, 0, -2.4) }, { 12, V3(0, 0, -2.4) },
}
-- (duas voltas inteiras: com volta e meia ele terminava de COSTAS pra câmera)
local FN_YAW = { { 0, 0 }, { 3.9, 0 }, { 5.9, 720 }, { 12, 720 } }
local FN_PITCH = { { 0, 0 }, { 3.9, 0 }, { 4.3, -72 }, { 5.8, -72 }, { 6.3, -10 }, { 7.4, 8 }, { 8.4, 0 }, { 12, 0 } }
function FN.RootPosition(t) return sample(FN_ROOT, t) end
function FN.RootCFrame(t)
	return CFrame.new(FN.RootPosition(t)) * CFrame.Angles(0, rad(sample(FN_YAW, t)), 0) * CFrame.Angles(rad(sample(FN_PITCH, t)), 0, 0)
end
function FN.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FN.BallVisible(t) return t < 0.05 end
function FN.BallSpin() return 0 end

local FN_PREGUICA = { Root = { 3, 0, 0 }, Neck = { -8, 0, -12 }, RShoulder = { -4, 0, 6 }, LShoulder = { -4, 0, -6 } }
local FN_POSE = {
	{ 0.00, FN_PREGUICA },
	{ 0.80, { Root = { 3, 0, 0 }, Neck = { 30, 0, -8 }, RShoulder = { -4, 0, 6 }, LShoulder = { -4, 0, -6 } } }, -- olha a bola
	{ 1.40, { Root = { 6, 0, 0 }, Neck = { 20, 0, -6 }, RHip = { 62, 0, 0 }, RShoulder = { 10, 0, 25 }, LShoulder = { 10, 0, -25 } } }, -- pé erguido
	{ 2.00, { Root = { 4, 0, 0 }, Neck = { -5, 0, -8 }, RHip = { 5, 0, 0 }, RShoulder = { 0, 0, 12 }, LShoulder = { 0, 0, -12 } } }, -- amorteceu
	{ 2.30, { Root = { 2, 0, 0 }, Neck = { 15, 0, -6 }, RHip = { 45, 0, 0 } } }, -- levanta
	{ 2.80, { Root = { -14, 0, 0 }, Neck = { 25, 0, 0 }, RHip = { 55, 0, 5 }, LHip = { 55, 0, -5 },
		RShoulder = { -35, 0, 25 }, LShoulder = { -35, 0, -25 } } }, -- agacha pro salto
	{ 3.60, { Root = { 12, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { 95, 0, 0 }, LHip = { -10, 0, 0 },
		RShoulder = { 40, 0, 70 }, LShoulder = { 40, 0, -70 } } }, -- prende no pé no ar
	{ 6.00, { Root = { 12, 0, 0 }, Neck = { 30, 0, 0 }, RHip = { 95, 0, 0 }, LHip = { -10, 0, 0 },
		RShoulder = { 40, 0, 80 }, LShoulder = { 40, 0, -80 } } },
	{ 6.60, { Neck = { 10, 0, 0 }, RHip = { -45, 0, 0 }, LHip = { 20, 0, 0 }, RShoulder = { -30, 0, 60 }, LShoulder = { 50, 0, -70 } } }, -- arma o voleio
	{ 7.00, { Neck = { 5, 0, 0 }, RHip = { 40, 0, 0 }, LHip = { -40, 0, 0 }, RShoulder = { -30, 0, 60 }, LShoulder = { 50, 0, -70 } } }, -- finta: para no meio
	{ FN.ImpactTime, { Neck = { 0, 0, 0 }, RHip = { -30, 0, 0 }, LHip = { 100, 0, 0 }, RShoulder = { 50, 0, 70 }, LShoulder = { -40, 0, -60 } } }, -- bate com a outra
	{ 8.40, { Root = { -8, 0, 0 }, Neck = { 5, 0, 0 }, RHip = { 25, 0, 4 }, LHip = { 25, 0, -4 } } }, -- pousa
	{ 9.20, FN_PREGUICA },
	{ 12.00, { Root = { 3, 0, 0 }, Neck = { -10, 0, -16 }, RShoulder = { -4, 0, 6 }, LShoulder = { -4, 0, -6 } } },
}
function FN.Pose(t) return samplePose(FN_POSE, t) end

function FN.Camera(t, rootPos)
	if t < 1.6 then
		-- de baixo e de frente: a bola caindo do céu nele
		return V3(1.8, -1.9, -7.5), V3(0, 2.5 - 1.6 * smooth(phase(t, 0.4, 1.6)), -0.5), 58
	elseif t < 2.6 then
		-- close no pé: a bola morre ali
		return V3(3.2, -1.6, -6.4), V3(0.3, -1.6, -0.8), 46
	elseif t < 3.8 then
		return rootPos + V3(8.5, 0.5, -1), rootPos + V3(0, 0, -0.6), 55
	elseif t < 6.2 then
		-- em volta dele no ar, de baixo, enquanto ele gira na horizontal
		local a = 0.3 + (t - 3.8) * 1.1
		return rootPos + V3(math.cos(a) * 7.5, -2.4, math.sin(a) * 7.5), rootPos, 60
	elseif t < FN.ImpactTime then
		return rootPos + V3(2.4, -1.6, -6.5), rootPos + V3(0, -0.6, -1), 55
	elseif t < 9 then
		-- atrás dele: a bola sumindo no fundo com o rastro
		return rootPos + V3(1.2, 1.4, 5), rootPos + V3(0, 0.5, -30), 50
	end
	-- a cara de preguiça
	local cabeca = rootPos + V3(0, 1.5, 0)
	local u = smooth(phase(t, 9, 12))
	return cabeca + V3(0.8, -0.4, -5.2):Lerp(V3(0.5, -0.3, -3.6), u), cabeca + V3(0, -0.1, 0), 40
end


-- ============================================================
-- 🦖 FLOW DO RIN — cena de ativação (⚠️ v113)
-- ============================================================
-- PEDIDO: "Rin com a língua pra fora quebrando o brinquedo (igual a moldura
-- do Rin)". Pelo vídeo ("Rin enters the flow and destroys all opponents",
-- visão geral a cada 5s): o BRINQUEDO de dinossauro verde no escuro (40s); o
-- sorriso insano com o olho em ESPIRAL verde-água e rosa, fundo vermelho
-- (50-65s); os adversários vistos como fracos, o mundo VERMELHO com fumaça
-- (80-95s, 185-205s); ele correndo com a aura verde-água (225s); o olho aceso
-- de perto (230s).
--   0.0-2.0  ele de pé, olhando o brinquedo no chão;
--   2.0-4.2  close: língua pra fora, olho em espiral;
--   4.2-5.6  ergue o pé e PISA: o brinquedo estoura, o mundo fica vermelho;
--   5.6-9.0  corre; duas sombras de adversário caem quando ele passa;
--   9.0-12   close final rindo, língua, aura verde-água.
local FR = {}
Cutscenes.Flow_Rin = FR
FR.Motor = "V2"
FR.Efeitos = "FlowRin"
FR.KickFoot = "Right"
FR.Duration = 12
FR.ImpactTime = 11.4 -- clarão final (o pisão tem o próprio tremor/clarão)
FR.ColarNoPe = false
FR.TitleText = "FLOW · ITOSHI RIN"
FR.Tema = {
	Titulo = { rgb(230, 255, 250), rgb(20, 200, 180), rgb(10, 80, 80) },
	Contorno = rgb(40, 0, 5), Flash = rgb(255, 80, 80),
	Tint = rgb(255, 245, 245), Saturation = 0.1, Contrast = 0.25, Brightness = -0.03,
}
FR.Phases = {
	Olha = { 0, 2 }, Rosto = { 2, 4.2 }, Pisa = { 4.2, 5.6 }, Pisao = { 4.85, 4.85 },
	Corre = { 5.6, 9 }, Final = { 9, 12 }, Kick = { 11, FR.ImpactTime }, Impact = { FR.ImpactTime, FR.Duration },
}
local FR_ROOT = {
	{ 0, V3(0, 0, 0) }, { 4.2, V3(0, 0, 0) }, { 4.6, V3(0, 0.3, -0.6) }, { 4.85, V3(0, -0.4, -1.2) },
	{ 5.6, V3(0, -0.2, -1.4) }, { 6.0, V3(0, -0.3, -2.4) }, { 9.0, V3(0, -0.3, -17) }, { 9.4, V3(0, 0, -17.6) }, { 12, V3(0, 0, -17.6) },
}
function FR.RootPosition(t) return sample(FR_ROOT, t) end
function FR.RootCFrame(t) return CFrame.new(FR.RootPosition(t)) end
function FR.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FR.BallVisible(t) return t < 0.05 end
function FR.BallSpin() return 0 end

-- cabeça tombada de lado, olhar de cima pra baixo (a pose da moldura)
local FR_INSANO = { Root = { -8, 0, 0 }, Neck = { -6, 0, 22 }, RShoulder = { -8, 0, 12 }, LShoulder = { -8, 0, -12 } }
local FR_POSE = {
	{ 0.00, {} },
	{ 1.00, { Root = { -6, 0, 0 }, Neck = { -30, 0, 10 }, RShoulder = { -6, 0, 10 }, LShoulder = { -6, 0, -10 } } }, -- olha o brinquedo
	{ 2.00, FR_INSANO },
	{ 4.20, FR_INSANO },
	{ 4.60, { Root = { 6, 0, 0 }, Neck = { -25, 0, 10 }, RHip = { 85, 0, 0 }, RShoulder = { 30, 0, 50 }, LShoulder = { 30, 0, -50 } } }, -- ergue o pé
	{ 4.85, { Root = { -18, 0, 0 }, Neck = { -30, 0, 10 }, RHip = { 25, 0, 0 }, LHip = { -10, 0, 0 },
		RShoulder = { -20, 0, 60 }, LShoulder = { -20, 0, -60 } } }, -- PISA
	{ 5.60, { Root = { -16, 0, 0 }, Neck = { -10, 0, 15 }, RHip = { 20, 0, 0 }, RShoulder = { -15, 0, 40 }, LShoulder = { -15, 0, -40 } } },
	-- (5.6-9: corrida, calculada abaixo)
	{ 9.40, FR_INSANO },
	{ 12.00, { Root = { -10, 0, 0 }, Neck = { -8, 0, 26 }, RShoulder = { -10, 0, 14 }, LShoulder = { -10, 0, -14 } } },
}
function FR.Pose(t)
	if t >= 5.8 and t < 9 then
		local w = math.sin((t - 5.8) * math.pi * 2 * 3.2)
		local entra = smooth(phase(t, 5.8, 6.1)) * (1 - smooth(phase(t, 8.8, 9)))
		return {
			Root = { -20 * entra, 0, 0 }, Neck = { 8, 0, 12 },
			RHip = { 55 * w * entra, 0, 0 }, LHip = { -55 * w * entra, 0, 0 },
			RShoulder = { -50 * w * entra, 0, 14 }, LShoulder = { 50 * w * entra, 0, -14 },
		}
	end
	return samplePose(FR_POSE, t)
end

-- dois adversários (sombras vermelhas) que ele atravessa e caem pra trás
local FR_ADV = { [1] = V3(-2.4, 0, -8), [2] = V3(2.4, 0, -13.5) }
local FR_QUEDA = { [1] = 7.1, [2] = 8.2 }
FR.Clones = {
	Quantidade = 2,
	Cor = rgb(90, 10, 16), -- escuras (no fundo vermelho), com contorno
	CFrame = function(i, t)
		local p = FR_ADV[i]
		local cai = smooth(phase(t, FR_QUEDA[i], FR_QUEDA[i] + 0.45))
		return CFrame.new(p + V3(0, -1.6 * cai, 0)) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(rad(-80 * cai), 0, rad((i == 1 and 15 or -15) * cai))
	end,
	Pose = function(i, t)
		local cai = smooth(phase(t, FR_QUEDA[i], FR_QUEDA[i] + 0.45))
		return { Root = { 0, 0, 0 }, Neck = { 20 * cai, 0, 0 }, RShoulder = { 60 * cai, 0, 40 * cai + 5 }, LShoulder = { 60 * cai, 0, -40 * cai - 5 },
			RHip = { 30 * cai, 0, 0 }, LHip = { 10 * cai, 0, 0 } }
	end,
	Alpha = function(_i, t)
		if t < 5.8 then return 0 end
		if t < 6.1 then return smooth(phase(t, 5.8, 6.1)) end
		if t < 8.9 then return 1 end
		return 1 - smooth(phase(t, 8.9, 9.2))
	end,
}

function FR.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2 then
		-- baixa, de frente: o brinquedo no chão e ele em pé atrás, olhando
		local u = smooth(phase(t, 0, 2))
		return V3(2.2, -0.6, -8.2):Lerp(V3(1.8, -0.7, -7.2), u), V3(0, -1.1, -1.6), 55
	elseif t < 4.2 then
		-- close: língua pra fora, olho em espiral
		local u = smooth(phase(t, 2, 4.2))
		return cabeca + V3(0.35, -0.35, -4.2):Lerp(V3(0.25, -0.3, -3.2), u), cabeca + V3(0, -0.05, 0), 36
	elseif t < 5.6 then
		-- de lado e baixo: o pisão
		return V3(4.8, -2, -3.4), V3(0, -1.6, -2.2), 55
	elseif t < 9 then
		-- de lado, acompanhando: os dois caindo quando ele passa (de frente, as
		-- sombras ficavam coladas na câmera)
		return rootPos + V3(9.5, 0.4, -3), rootPos + V3(0, 0.4, -3), 55
	end
	local u = smooth(phase(t, 9, 12))
	return cabeca + V3(0.45, -0.35, -4.6):Lerp(V3(0.3, -0.3, -3.3), u), cabeca + V3(0, -0.05, 0), 38
end


-- ============================================================
-- 🐆 FLOW DO CHIGIRI — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o despertar da velocidade — agachado segurando o
-- joelho (a lesão que o travava), levanta decidido, os olhos acendem e ele
-- DISPARA; a pantera (o apelido dele) corre ao lado e ele a passa; corta pra
-- dentro freando; pétalas cor-de-rosa (o motivo da loja).
--   0.0-2.2 agachado, mão no joelho;  2.2-3.6 levanta, close, olhos rosa;
--   3.6-7.6 corrida com a pantera;  7.6-9.0 freia e corta pra dentro;
--   9.0-12  pose final, pétalas e aura.
local FC = {}
Cutscenes.Flow_Chigiri = FC
FC.Motor = "V2"
FC.Efeitos = "FlowChigiri"
FC.KickFoot = "Right"
FC.Duration = 12
FC.ImpactTime = 11.3
FC.ColarNoPe = false
FC.TitleText = "FLOW · CHIGIRI HYOMA"
FC.Tema = {
	Titulo = { rgb(255, 245, 250), rgb(255, 110, 150), rgb(150, 20, 60) },
	Contorno = rgb(40, 0, 15), Flash = rgb(255, 200, 220),
	Tint = rgb(255, 245, 248), Saturation = 0.1, Contrast = 0.15, Brightness = 0,
}
FC.Phases = {
	Joelho = { 0, 2.2 }, Levanta = { 2.2, 3.6 }, Corre = { 3.6, 7.6 }, Corta = { 7.6, 9 },
	Final = { 9, 12 }, Kick = { 11, FC.ImpactTime }, Impact = { FC.ImpactTime, FC.Duration },
}
local FC_ROOT = {
	{ 0, V3(0, -0.9, 0) }, { 2.2, V3(0, -0.9, 0) }, { 3.0, V3(0, 0, 0) }, { 3.6, V3(0, 0, 0) },
	{ 4.2, V3(0, -0.3, -3) }, { 7.6, V3(0, -0.3, -40) }, { 8.4, V3(-3, -0.5, -45) }, { 9.0, V3(-4.5, 0, -46) }, { 12, V3(-4.5, 0, -46) },
}
local FC_YAW = { { 0, 0 }, { 7.6, 0 }, { 8.4, 55 }, { 9, 40 }, { 12, 40 } }
local FC_ROLL = { { 0, 0 }, { 7.5, 0 }, { 8.0, 22 }, { 8.6, 10 }, { 9.0, 0 }, { 12, 0 } }
function FC.RootPosition(t) return sample(FC_ROOT, t) end
function FC.RootCFrame(t)
	return CFrame.new(FC.RootPosition(t)) * CFrame.Angles(0, rad(sample(FC_YAW, t)), 0) * CFrame.Angles(0, 0, rad(sample(FC_ROLL, t)))
end
function FC.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FC.BallVisible(t) return t < 0.05 end
function FC.BallSpin() return 0 end
local FC_AGACHADO = { Root = { -30, 0, 0 }, Neck = { -10, 0, 0 }, RHip = { 80, 0, 6 }, LHip = { 45, 0, -6 },
	RShoulder = { 55, 0, 12 }, LShoulder = { 30, 0, -20 } }
local FC_POSE = {
	{ 0.00, FC_AGACHADO }, { 2.20, FC_AGACHADO },
	{ 3.00, { Root = { -4, 0, 0 }, Neck = { 12, 0, 0 }, RShoulder = { -10, 0, 12 }, LShoulder = { -10, 0, -12 } } },
	{ 3.60, { Root = { -8, 0, 0 }, Neck = { 8, 0, 0 }, RShoulder = { -10, 0, 12 }, LShoulder = { -10, 0, -12 } } },
	-- (3.6-7.6: corrida, calculada abaixo)
	{ 8.00, { Root = { -25, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 60, 0, 25 }, LHip = { -20, 0, -10 },
		RShoulder = { 20, 0, 60 }, LShoulder = { -20, 0, -70 } } }, -- freia inclinado
	{ 9.00, { Root = { -10, 0, 0 }, Neck = { 12, 0, 0 }, RHip = { 20, 0, 10 }, LHip = { -5, 0, 0 },
		RShoulder = { 10, 0, 35 }, LShoulder = { 10, 0, -35 } } },
	{ 12.00, { Root = { -6, 0, 0 }, Neck = { 10, 10, 0 }, RHip = { 10, 0, 8 }, LHip = { -5, 0, 0 },
		RShoulder = { 5, 0, 30 }, LShoulder = { 60, 0, -40 } } }, -- afasta o cabelo (mão esquerda perto do rosto)
}
function FC.Pose(t)
	if t >= 3.6 and t < 7.6 then
		local w = math.sin((t - 3.6) * math.pi * 2 * 3.6)
		local entra = smooth(phase(t, 3.6, 3.9)) * (1 - smooth(phase(t, 7.4, 7.6)))
		return {
			Root = { -24 * entra, 0, 0 }, Neck = { 16, 0, 0 },
			RHip = { 60 * w * entra, 0, 0 }, LHip = { -60 * w * entra, 0, 0 },
			RShoulder = { -55 * w * entra, 0, 10 }, LShoulder = { 55 * w * entra, 0, -10 },
		}
	end
	return samplePose(FC_POSE, t)
end
function FC.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2.2 then
		local u = smooth(phase(t, 0, 2.2))
		return V3(3.5, -1.2, -6):Lerp(V3(2.6, -1, -5), u), V3(0, -0.6, 0), 52
	elseif t < 3.6 then
		local u = smooth(phase(t, 2.2, 3.6))
		return cabeca + V3(0.4, -0.3, -4.4):Lerp(V3(0.3, -0.25, -3.4), u), cabeca, 38
	elseif t < 7.6 then
		-- de frente-lado: ele e a pantera lado a lado (de lado ela sumia atrás dele)
		return rootPos + V3(-8, 2.2, -9), rootPos + V3(1.6, 0.4, -1.5), 52
	elseif t < 9 then
		return rootPos + V3(-4, 1, -8), rootPos + V3(0, 0, 0), 55
	end
	local u = smooth(phase(t, 9, 12))
	return cabeca + V3(-1.4, -0.4, -4.6):Lerp(V3(-1, -0.3, -3.6), u), cabeca, 40
end


-- ============================================================
-- 🔥 FLOW DO KUNIGAMI — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o HERÓI e o canhão de canhota. Punho no peito, cabeça
-- baixa; ergue o olhar e as chamas sobem atrás; corrida curta e o chute de
-- CANHOTA que racha o chão; a bola vira uma bola de fogo; pose de herói.
--   0.0-2.0 punho no peito;  2.0-3.8 close, olhos laranja, chamas;
--   3.8-6.3 corrida e o chute;  6.3-8.5 a bola de fogo indo;  8.5-12 pose de herói.
local FK = {}
Cutscenes.Flow_Kunigami = FK
FK.Motor = "V2"
FK.Efeitos = "FlowKunigami"
FK.KickFoot = "Left"
FK.Duration = 12
FK.ImpactTime = 11.3 -- clarão final (o chute, aos 6.3s, tem tremor próprio)
FK.Chute = 6.3
FK.ColarNoPe = false
FK.TitleText = "FLOW · KUNIGAMI RENSUKE"
FK.Tema = {
	Titulo = { rgb(255, 250, 225), rgb(255, 160, 50), rgb(160, 60, 10) },
	Contorno = rgb(40, 15, 0), Flash = rgb(255, 210, 140),
	Tint = rgb(255, 240, 220), Saturation = 0.2, Contrast = 0.2, Brightness = 0,
}
FK.Phases = {
	Punho = { 0, 2 }, Rosto = { 2, 3.8 }, Corre = { 3.8, 5.8 }, Kick = { 5.8, FK.Chute },
	Voa = { FK.Chute, 8.5 }, Heroi = { 8.5, 12 }, Impact = { FK.ImpactTime, FK.Duration },
}
local FK_ROOT = { { 0, V3(0, 0, 0) }, { 3.8, V3(0, 0, 0) }, { 5.6, V3(0, -0.2, -5) }, { FK.Chute, V3(0, -0.3, -6.2) },
	{ 8.5, V3(0, 0, -6.4) }, { 12, V3(0, 0, -6.4) } }
function FK.RootPosition(t) return sample(FK_ROOT, t) end
function FK.RootCFrame(t) return CFrame.new(FK.RootPosition(t)) end
function FK.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FK.BallVisible(t) return t < 0.05 end
function FK.BallSpin() return 0 end
local FK_PUNHO = { Root = { -4, 0, 0 }, Neck = { -22, 0, 0 }, RShoulder = { 70, 0, -35 }, RElbow = { 100, 0, 0 }, LShoulder = { -5, 0, -8 } }
local FK_HEROI = { Root = { 4, 0, 0 }, Neck = { 6, 0, 0 }, RHip = { 5, 0, 12 }, LHip = { 5, 0, -12 },
	RShoulder = { -8, 0, 22 }, LShoulder = { -8, 0, -22 } }
local FK_POSE = {
	{ 0.00, FK_PUNHO }, { 2.00, FK_PUNHO },
	{ 2.60, { Root = { 2, 0, 0 }, Neck = { 8, 0, 0 }, RShoulder = { 70, 0, -35 }, RElbow = { 100, 0, 0 }, LShoulder = { -5, 0, -8 } } },
	{ 3.80, { Root = { -6, 0, 0 }, Neck = { 6, 0, 0 }, RShoulder = { -10, 0, 12 }, LShoulder = { -10, 0, -12 } } },
	-- (3.8-5.6 corrida)
	{ 5.60, { Root = { -8, 0, 0 }, Neck = { -10, 0, 0 }, RHip = { 30, 0, 0 }, LHip = { -60, 0, 0 },
		RShoulder = { 40, 0, 50 }, LShoulder = { -30, 0, -60 } } }, -- arma a canhota
	{ FK.Chute, { Root = { -14, 0, 0 }, Neck = { -12, 0, 0 }, RHip = { -15, 0, 0 }, LHip = { 95, 0, 0 },
		RShoulder = { -40, 0, 60 }, LShoulder = { 50, 0, -55 } } }, -- CHUTE
	{ 7.20, { Root = { -10, 0, 0 }, Neck = { -5, 0, 0 }, RHip = { -10, 0, 0 }, LHip = { 70, 0, 0 },
		RShoulder = { -40, 0, 60 }, LShoulder = { 50, 0, -55 } } },
	{ 8.50, FK_HEROI }, { 12.00, FK_HEROI },
}
function FK.Pose(t)
	if t >= 3.8 and t < 5.5 then
		local w = math.sin((t - 3.8) * math.pi * 2 * 2.6)
		local e = smooth(phase(t, 3.8, 4.0)) * (1 - smooth(phase(t, 5.3, 5.5)))
		return { Root = { -16 * e, 0, 0 }, Neck = { 10, 0, 0 }, RHip = { 50 * w * e, 0, 0 }, LHip = { -50 * w * e, 0, 0 },
			RShoulder = { -45 * w * e, 0, 10 }, LShoulder = { 45 * w * e, 0, -10 } }
	end
	return samplePose(FK_POSE, t)
end
function FK.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2 then
		local u = smooth(phase(t, 0, 2))
		return V3(2.5, -0.4, -7):Lerp(V3(2, -0.2, -5.8), u), V3(0, 0.6, 0), 50
	elseif t < 3.8 then
		local u = smooth(phase(t, 2, 3.8))
		return cabeca + V3(0.4, -0.4, -4.4):Lerp(V3(0.3, -0.3, -3.4), u), cabeca, 38
	elseif t < FK.Chute then
		-- de lado e baixo: a corrida e a canhota
		return rootPos + V3(-8, -0.6, -1.5), rootPos + V3(0, 0, -1.5), 55
	elseif t < 8.5 then
		-- atrás dele: a bola de fogo indo embora
		return rootPos + V3(1.5, 1.6, 6), rootPos + V3(0, 0.5, -30), 52
	end
	-- herói: de baixo, de frente
	local u = smooth(phase(t, 8.5, 12))
	return rootPos + V3(1.8, -2.4, -6.5):Lerp(V3(1.2, -2.1, -5.2), u), rootPos + V3(0, 1.2, 0), 55
end

-- ============================================================
-- 🪞 FLOW DO REO — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o CAMALEÃO que copia todo mundo. ESPELHOS sobem em
-- volta; em cada um aparece uma cópia (de outra cor: o chute, o drible, o
-- domínio...); os espelhos se estilhaçam e as cópias entram nele; ele faz os
-- movimentos copiados em sequência (chute, giro do drible, cabeceio) e fecha
-- com o sorriso confiante, olhos roxos.
local FRe = {}
Cutscenes.Flow_Reo = FRe
FRe.Motor = "V2"
FRe.Efeitos = "FlowReo"
FRe.KickFoot = "Right"
FRe.Duration = 12
FRe.ImpactTime = 11.3
FRe.ColarNoPe = false
FRe.TitleText = "FLOW · MIKAGE REO"
FRe.Tema = {
	Titulo = { rgb(250, 240, 255), rgb(190, 120, 255), rgb(90, 30, 150) },
	Contorno = rgb(25, 0, 40), Flash = rgb(230, 200, 255),
	Tint = rgb(248, 242, 255), Saturation = 0.1, Contrast = 0.15, Brightness = 0,
}
FRe.Phases = {
	Espelhos = { 0, 2 }, Copias = { 2, 4.5 }, Quebra = { 4.5, 5.2 }, Entram = { 5.2, 6.5 },
	Copia = { 6.5, 9 }, Final = { 9, 12 }, Kick = { 11, FRe.ImpactTime }, Impact = { FRe.ImpactTime, FRe.Duration },
}
local FRE_ROOT = { { 0, V3(0, 0, 0) }, { 6.9, V3(0, 0, 0) }, { 7.6, V3(0, 0, -1) }, { 8.2, V3(0, 3.2, -1.5) }, { 8.8, V3(0, 0, -2) }, { 12, V3(0, 0, -2) } }
local FRE_YAW = { { 0, 0 }, { 7.6, 0 }, { 8.1, 360 }, { 12, 360 } } -- o giro do drible copiado
function FRe.RootPosition(t) return sample(FRE_ROOT, t) end
function FRe.RootCFrame(t) return CFrame.new(FRe.RootPosition(t)) * CFrame.Angles(0, rad(sample(FRE_YAW, t)), 0) end
function FRe.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FRe.BallVisible(t) return t < 0.05 end
function FRe.BallSpin() return 0 end
local FRE_PARADO = { Root = { 0, 0, 0 }, Neck = { 10, 0, 0 }, RShoulder = { -5, 0, 10 }, LShoulder = { -5, 0, -10 } }
local FRE_POSE = {
	{ 0.00, FRE_PARADO }, { 5.20, FRE_PARADO },
	{ 5.80, { Root = { 10, 0, 0 }, Neck = { 25, 0, 0 }, RShoulder = { 35, 0, 100 }, LShoulder = { 35, 0, -100 } } }, -- recebe as cópias
	{ 6.50, FRE_PARADO },
	{ 6.90, { Root = { -8, 0, 0 }, RHip = { -50, 0, 0 }, RShoulder = { -30, 0, 60 }, LShoulder = { 50, 0, -70 } } }, -- arma o chute
	{ 7.20, { Root = { -12, 0, 0 }, RHip = { 95, 0, 0 }, LHip = { -10, 0, 0 }, RShoulder = { -40, 0, 60 }, LShoulder = { 60, 0, -60 } } }, -- chute
	{ 7.60, { Root = { -20, 0, 0 }, RHip = { 40, 0, 20 }, LHip = { 20, 0, -12 }, RShoulder = { 10, 0, 70 }, LShoulder = { 10, 0, -70 } } }, -- drible
	{ 8.10, { Root = { -20, 0, 0 }, RHip = { 40, 0, 20 }, LHip = { 20, 0, -12 }, RShoulder = { 10, 0, 70 }, LShoulder = { 10, 0, -70 } } },
	{ 8.40, { Root = { 18, 0, 0 }, Neck = { -35, 0, 0 }, RHip = { -20, 0, 0 }, LHip = { 20, 0, 0 }, RShoulder = { -20, 0, 50 }, LShoulder = { -20, 0, -50 } } }, -- cabeceio
	{ 9.00, FRE_PARADO },
	-- sorriso confiante: mão no queixo
	{ 9.60, { Root = { 2, 0, 0 }, Neck = { 12, 12, 0 }, RShoulder = { 78, 0, -42 }, LShoulder = { 20, 0, -10 } } },
	{ 12.00, { Root = { 2, 0, 0 }, Neck = { 14, 16, 0 }, RShoulder = { 80, 0, -44 }, LShoulder = { 20, 0, -10 } } },
}
function FRe.Pose(t) return samplePose(FRE_POSE, t) end
-- as cópias: 5 espelhos em volta
FRe.Espelhos = {}
for i = 1, 5 do
	-- meia-lua ATRÁS dele (na frente, tampavam ele da câmera)
	local a = math.rad(90 + (i - 3) * 36)
	FRe.Espelhos[i] = V3(math.cos(a) * 6, 0, math.sin(a) * 6)
end
local FRE_POSES_COPIA = {
	{ RHip = { 95, 0, 0 }, LHip = { -15, 0, 0 }, RShoulder = { -40, 0, 60 }, LShoulder = { 60, 0, -60 } }, -- chute
	{ Root = { -20, 0, 0 }, RHip = { 40, 0, 20 }, LHip = { 20, 0, -12 }, RShoulder = { 10, 0, 70 }, LShoulder = { 10, 0, -70 } }, -- drible
	{ Root = { 18, 0, 0 }, Neck = { -35, 0, 0 }, RShoulder = { -20, 0, 50 }, LShoulder = { -20, 0, -50 } }, -- cabeceio
	{ RHip = { 60, 0, 0 }, RShoulder = { 20, 0, 30 }, LShoulder = { 20, 0, -30 } }, -- domínio
	{ Root = { -25, 0, 0 }, RHip = { 50, 0, 0 }, LHip = { -40, 0, 0 }, RShoulder = { -40, 0, 10 }, LShoulder = { 40, 0, -10 } }, -- corrida
}
FRe.Clones = {
	Quantidade = 5,
	Cor = rgb(150, 90, 230),
	CFrame = function(i, t)
		local p = FRe.Espelhos[i] * 0.88 -- um pouco na frente do vidro
		local entra = smooth(phase(t, 5.2, 6.3))
		local pos = p:Lerp(V3(0, 0, 0), entra)
		return CFrame.lookAt(pos, V3(0, 0, 0)) * CFrame.Angles(0, math.pi, 0)
	end,
	Pose = function(i, _t) return FRE_POSES_COPIA[i] end,
	Alpha = function(_i, t)
		if t < 2.2 then return 0 end
		if t < 2.8 then return smooth(phase(t, 2.2, 2.8)) end
		if t < 5.8 then return 1 end
		return 1 - smooth(phase(t, 5.8, 6.4))
	end,
}
function FRe.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 4.5 then
		-- aberta, de frente e um pouco de cima: ele no meio dos espelhos
		local u = smooth(phase(t, 0, 4.5))
		return V3(0, 3.5, -13):Lerp(V3(0, 2.5, -11), u), V3(0, 0.5, 1.5), 55
	elseif t < 6.5 then
		return V3(3, 1.5, -9), V3(0, 0.8, 0), 55
	elseif t < 9 then
		return rootPos + V3(-7, 0.5, -4), rootPos + V3(0, 0.5, 0), 55
	end
	local u = smooth(phase(t, 9, 12))
	-- (do lado esquerdo dele: o braço da mão no queixo não passa na frente)
	return cabeca + V3(-1.1, -0.3, -4.6):Lerp(V3(-0.9, -0.25, -3.6), u), cabeca, 38
end


-- ============================================================
-- 👻 FLOW DO AIKU — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o FANTASMA da defesa. Na névoa, agachado em guarda de
-- olhos fechados; abre os olhos (claros); um atacante (sombra vermelha) vem
-- conduzindo; ele SOME, deixa rastros de imagem e reaparece do lado, dá o
-- bote e sai com a bola; fecha calmo com a bola no pé.
local FA = {}
Cutscenes.Flow_Aiku = FA
FA.Motor = "V2"
FA.Efeitos = "FlowAiku"
FA.KickFoot = "Right"
FA.Duration = 12
FA.ImpactTime = 11.3
FA.ColarNoPe = false
FA.TitleText = "FLOW · AIKU OLIVER"
FA.Tema = {
	Titulo = { rgb(240, 245, 255), rgb(170, 180, 215), rgb(70, 70, 110) },
	Contorno = rgb(15, 15, 30), Flash = rgb(225, 230, 255),
	Tint = rgb(235, 238, 250), Saturation = -0.25, Contrast = 0.2, Brightness = -0.02,
}
FA.Phases = {
	Guarda = { 0, 2 }, Olhos = { 2, 3.5 }, Vem = { 3.5, 5.2 }, Some = { 5.2, 6.4 }, Bote = { 6.4, 7.6 },
	Final = { 8.5, 12 }, Kick = { 11, FA.ImpactTime }, Impact = { FA.ImpactTime, FA.Duration },
}
local FA_ROOT = {
	{ 0, V3(0, -0.7, 0) }, { 3.5, V3(0, -0.7, 0) }, { 5.2, V3(0, -0.7, 0) },
	{ 6.3, V3(-3.5, -0.4, -5.5) }, -- reaparece do lado do atacante
	{ 7.0, V3(-1.2, -1.3, -6.8) }, -- bote rasteiro
	{ 7.6, V3(0, -1.2, -7.8) }, { 8.5, V3(0, 0, -9.5) }, { 12, V3(0, 0, -9.5) },
}
local FA_YAW = { { 0, 0 }, { 5.2, 0 }, { 6.3, -60 }, { 7.0, -30 }, { 8.5, 0 }, { 12, 0 } }
function FA.RootPosition(t) return sample(FA_ROOT, t) end
function FA.RootCFrame(t) return CFrame.new(FA.RootPosition(t)) * CFrame.Angles(0, rad(sample(FA_YAW, t)), 0) end
function FA.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FA.BallVisible(t) return t < 0.05 end
function FA.BallSpin() return 0 end
local FA_GUARDA = { Root = { -25, 0, 0 }, Neck = { 15, 0, 0 }, RHip = { 55, 0, 14 }, LHip = { 55, 0, -14 },
	RShoulder = { 20, 0, 50 }, LShoulder = { 20, 0, -50 } }
local FA_CALMO = { Root = { 0, 0, 0 }, Neck = { 6, 0, 0 }, RHip = { 25, 0, 0 }, RShoulder = { -5, 0, 10 }, LShoulder = { -5, 0, -10 } }
local FA_POSE = {
	{ 0.00, FA_GUARDA }, { 5.20, FA_GUARDA },
	{ 6.30, { Root = { -30, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 45, 0, 10 }, LHip = { 20, 0, -10 },
		RShoulder = { 30, 0, 60 }, LShoulder = { 30, 0, -60 } } },
	-- bote: carrinho curto, perna direita esticada
	{ 7.00, { Root = { 55, 0, 0 }, Neck = { -30, 0, 0 }, RHip = { 40, 0, 0 }, LHip = { 80, 0, 0 },
		RShoulder = { -20, 0, 40 }, LShoulder = { 80, 0, -30 } } },
	{ 7.60, { Root = { 20, 0, 0 }, Neck = { -10, 0, 0 }, RHip = { 45, 0, 0 }, LHip = { 50, 0, 0 },
		RShoulder = { -10, 0, 30 }, LShoulder = { 40, 0, -30 } } },
	{ 8.50, FA_CALMO }, { 12.00, FA_CALMO },
}
function FA.Pose(t) return samplePose(FA_POSE, t) end
-- 1 = o atacante (vermelho, conduzindo); 2-4 = rastros de imagem dele
FA.Clones = {
	Quantidade = 4,
	Cor = rgb(170, 180, 215),
	CFrame = function(i, t)
		if i == 1 then
			local vem = smooth(phase(t, 3.5, 6.8))
			local p = V3(-2, 0, -14):Lerp(V3(-2, 0, -7), vem)
			local cai = smooth(phase(t, 7.0, 7.6))
			return CFrame.new(p + V3(-1.2 * cai, -0.9 * cai, 0)) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(rad(-35 * cai), 0, rad(30 * cai))
		end
		-- rastros: onde ele esteve um pouco antes
		local atras = (i - 1) * 0.12
		local tt = math.max(t - atras, 0)
		return CFrame.new(FA.RootPosition(tt)) * CFrame.Angles(0, rad(sample(FA_YAW, tt)), 0)
	end,
	Pose = function(i, t)
		if i == 1 then
			local w = math.sin(t * 9)
			local cai = smooth(phase(t, 7.0, 7.6))
			return { Root = { -10 * (1 - cai), 0, 0 }, RHip = { 35 * w * (1 - cai), 0, 0 }, LHip = { -35 * w * (1 - cai), 0, 0 },
				RShoulder = { -30 * w + 60 * cai, 0, 15 + 40 * cai }, LShoulder = { 30 * w + 60 * cai, 0, -15 - 40 * cai } }
		end
		return FA.Pose(math.max(t - (i - 1) * 0.12, 0))
	end,
	Alpha = function(i, t)
		if i == 1 then
			if t < 3.5 then return 0 end
			if t < 3.8 then return smooth(phase(t, 3.5, 3.8)) end
			if t < 9 then return 1 end
			return 1 - smooth(phase(t, 9, 9.4))
		end
		-- rastros só no sumiço/bote
		local a = smooth(phase(t, 5.2, 5.5)) * (1 - smooth(phase(t, 7.4, 7.9)))
		return a * (0.55 - (i - 2) * 0.15)
	end,
}
function FA.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2 then
		local u = smooth(phase(t, 0, 2))
		return V3(3, 0.5, -7.5):Lerp(V3(2.4, 0.2, -6.2), u), V3(0, -0.3, 0), 52
	elseif t < 3.5 then
		local u = smooth(phase(t, 2, 3.5))
		return cabeca + V3(0.35, -0.3, -4):Lerp(V3(0.25, -0.25, -3.2), u), cabeca, 38
	elseif t < 8.5 then
		-- de lado e aberta: o atacante vindo, ele sumindo e o bote
		return V3(11, 1.5, -6), V3(-1, 0, -6.5), 55
	end
	local u = smooth(phase(t, 8.5, 12))
	return cabeca + V3(0.8, -0.8, -5.5):Lerp(V3(0.5, -0.6, -4.2), u), cabeca + V3(0, -0.5, 0), 42
end

-- ============================================================
-- 👑 FLOW DO BAROU — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o REI. Sentado num trono dourado no escuro; a COROA
-- aparece na cabeça, olhos dourados; levanta, o trono se desfaz; um marcador
-- (sombra) vem e ele o tira no ombro — voa longe; fecha com a pose de rei,
-- queixo pra cima, braços cruzados.
local FBa = {}
Cutscenes.Flow_Barou = FBa
FBa.Motor = "V2"
FBa.Efeitos = "FlowBarou"
FBa.KickFoot = "Right"
FBa.Duration = 12
FBa.ImpactTime = 11.3
FBa.ColarNoPe = false
FBa.TitleText = "FLOW · BAROU SHOEI"
FBa.Tema = {
	Titulo = { rgb(255, 250, 220), rgb(255, 205, 60), rgb(120, 80, 10) },
	Contorno = rgb(30, 20, 0), Flash = rgb(255, 235, 170),
	Tint = rgb(255, 248, 230), Saturation = 0.15, Contrast = 0.22, Brightness = -0.02,
}
FBa.Phases = {
	Trono = { 0, 2.5 }, Coroa = { 2.5, 4 }, Levanta = { 4, 6 }, Ombro = { 6, 8.5 },
	Rei = { 8.5, 12 }, Kick = { 11, FBa.ImpactTime }, Impact = { FBa.ImpactTime, FBa.Duration },
}
local FBA_ROOT = { { 0, V3(0, -1.3, 0.8) }, { 4, V3(0, -1.3, 0.8) }, { 4.8, V3(0, 0, -0.2) }, { 6, V3(0, 0, -3.5) },
	{ 6.9, V3(0, -0.2, -5) }, { 8.5, V3(0, 0, -5.4) }, { 12, V3(0, 0, -5.4) } }
function FBa.RootPosition(t) return sample(FBA_ROOT, t) end
function FBa.RootCFrame(t) return CFrame.new(FBa.RootPosition(t)) end
function FBa.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FBa.BallVisible(t) return t < 0.05 end
function FBa.BallSpin() return 0 end
local FBA_SENTADO = { Root = { 0, 0, 0 }, Neck = { -5, 0, 0 }, RHip = { 88, 0, 8 }, LHip = { 88, 0, -8 },
	RShoulder = { 25, 0, 25 }, LShoulder = { 25, 0, -25 } }
local FBA_REI = { Root = { 6, 0, 0 }, Neck = { 14, 0, 0 }, RHip = { 0, 0, 10 }, LHip = { 0, 0, -10 },
	RShoulder = { 80, 0, -48 }, LShoulder = { 80, 0, 48 } } -- braços cruzados
local FBA_POSE = {
	{ 0.00, FBA_SENTADO }, { 4.00, FBA_SENTADO },
	{ 4.80, { Root = { -10, 0, 0 }, Neck = { 5, 0, 0 }, RShoulder = { -8, 0, 14 }, LShoulder = { -8, 0, -14 } } },
	-- (4.8-6: anda devagar, calculado abaixo)
	{ 6.30, { Root = { -8, 0, 0 }, Waist = { 0, -25, 0 }, Neck = { 5, 0, 0 }, RShoulder = { 10, 0, 30 }, LShoulder = { 10, 0, -30 } } },
	{ 6.90, { Root = { -14, 0, 0 }, Waist = { 0, 30, 0 }, Neck = { 0, 0, 0 }, RHip = { 20, 0, 0 }, LHip = { -20, 0, 0 },
		RShoulder = { -30, 0, 70 }, LShoulder = { 20, 0, -20 } } }, -- o ombro
	{ 8.50, FBA_REI }, { 12.00, FBA_REI },
}
function FBa.Pose(t)
	if t >= 4.8 and t < 6.1 then
		local w = math.sin((t - 4.8) * math.pi * 2 * 1.1)
		return { Root = { -4, 0, 0 }, Neck = { 8, 0, 0 }, RHip = { 25 * w, 0, 0 }, LHip = { -25 * w, 0, 0 },
			RShoulder = { -18 * w, 0, 12 }, LShoulder = { 18 * w, 0, -12 } }
	end
	return samplePose(FBA_POSE, t)
end
-- o marcador que ele tira no ombro
FBa.Clones = {
	Quantidade = 1,
	Cor = rgb(90, 80, 70),
	CFrame = function(_i, t)
		local voa = easeOut(phase(t, 6.9, 7.9))
		local p = V3(0.6, 0, -8.5):Lerp(V3(-1.5, 0, -7), smooth(phase(t, 5.6, 6.9)))
		p = p + V3(-7 * voa, 3 * math.sin(voa * math.pi) - 1.2 * voa, -3 * voa)
		return CFrame.new(p) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(rad(-60 * voa), 0, rad(-80 * voa))
	end,
	Pose = function(_i, t)
		local voa = smooth(phase(t, 6.9, 7.4))
		return { Root = { -10, 0, 0 }, RShoulder = { 30 + 60 * voa, 0, 20 + 60 * voa }, LShoulder = { 30 + 60 * voa, 0, -20 - 60 * voa },
			RHip = { 20 * voa, 0, 0 }, LHip = { -20 * voa, 0, 0 } }
	end,
	Alpha = function(_i, t)
		if t < 5.6 then return 0 end
		if t < 5.9 then return smooth(phase(t, 5.6, 5.9)) end
		if t < 8 then return 1 end
		return 1 - smooth(phase(t, 8, 8.4))
	end,
}
function FBa.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2.5 then
		-- de frente e baixa: o rei no trono
		local u = smooth(phase(t, 0, 2.5))
		return V3(0.8, -1.2, -9):Lerp(V3(0.6, -1, -7.5), u), V3(0, 0.6, 0.8), 50
	elseif t < 4 then
		local u = smooth(phase(t, 2.5, 4))
		return cabeca + V3(0.35, -0.2, -4.2):Lerp(V3(0.25, 0, -3.3), u), cabeca + V3(0, 0.4, 0), 40
	elseif t < 8.5 then
		return rootPos + V3(7, 0.8, -5), rootPos + V3(-1, 0.4, -1.5), 55
	end
	-- o rei, de baixo
	local u = smooth(phase(t, 8.5, 12))
	return rootPos + V3(1.2, -2.6, -6.2):Lerp(V3(0.8, -2.2, -4.8), u), rootPos + V3(0, 1.4, 0), 55
end


-- ============================================================
-- 💥 FLOW DO SHIDOU — "BIG BANG DRIVE" (⚠️ v124 → v126) — cena de ativação + CHUTE
-- ============================================================
-- PEDIDO: refazer o Flow do Shidou igual ao do Isagi (baseado no vídeo, quadro a
-- quadro) — "Shidou's Big Bang Drive Goal · BLUE LOCK 2nd Season", 0-1:08 — SEM os
-- trechos de óvulo/espermatozoide ("tira as partes de espermatozoide, é um jogo no
-- roblox"). E: "o flow dele vem com a ação de chute dele: pra onde a pessoa mirar o
-- jogador vai usar o flow e dar a cutscene pra chutar e ativar o flow ao mesmo tempo".
--
-- ⚠️ v126 — PEDIDO: "o intuito: ele fica bem excitado de ter recebido uma bola boa, vê a
-- bola chegando, pula e dá a bicicleta". "Não é pra ele dominar no peito: em primeira
-- pessoa, olhando da visão dele pra cima, a bola caindo devagar". "Não precisa dar um
-- close nos olhos, só o rosto". "Começa o Big Bang Drive antes; câmera lenta no ar, como
-- se a bola parasse; o chutão com um pé em velocidade NORMAL; a bola fica parada ~meio
-- segundo e aí sai com velocidade máxima, dando pra ver ela saindo". "O olho dele quando
-- estiver chutando", "barulho do chute (mais forte que o padrão) e explosãozinha em volta,
-- que faça sentido, igual da música", "as asas dele durante o Big Bang Drive".
--
-- TABELA DE PLANOS (tempo no vídeo → cena de 12s; ✂️ = cortado do vídeo):
--   Chega    0-1.4   0-4.6s     PRIMEIRA PESSOA: da visão dele, olhando pra cima, a bola
--                               caindo devagar lá do alto ("Are? Nanda kono kankaku")
--   Aura     1.4-3.0 6.0-10.5s  a aura rosa EXPLODE no corpo; fundo escuro de estrelas;
--                               ele inclinado pra trás, braço aberto (contorno rosa)
--   Rosto    3.0-4.4 13-17.9s   o rosto (câmera segue a cabeça)
--   Olho     4.4-5.4 18-23.2s   o rosto inteiro, o BRANCO dos olhos acende (sem close extremo)
--   Tunel    5.4-6.3 23.5-27.5s tela preta → o branco cresce no centro e toma a tela
--                               (✂️ 4.7-5.9s e 27.6-27.9s: óvulo/espermatozoide)
--   Peito    6.3-7.5 27.9-30.1s de frente, braços abertos: risco rosa atravessa o peito, a
--                               aura ESTOURA e nascem as ASAS (raios e chamas rosa das costas)
--   Chamas   7.5-8.4 30.7-34.9s ele no ar inclinado pra trás, câmera de baixo; chamas rosa
--                               escorrendo e raios de luz atrás
--   BigBang  8.4-9.75 42-47s    estádio ESCURO: ele desce, olha a bola vindo do alto, VIRA de
--                               costas pro gol (8.55-8.95), agacha e SALTA (9.0-9.25, normal);
--                               no ar, CÂMERA LENTA (9.25-9.75): sobe devagar, a bola quase
--                               parada ("Big Bang Drive!")
--   Kick     9.75-9.88          o CHUTÃO em velocidade normal: bicicleta de costas, a perna
--                               direita passa por cima da cabeça (SEM mortal) — som de chute
--   Parada   9.88-10.4 47-48s   a bola PARADA na chuteira (~0.5s), close no rosto com o olho
--                               do Flow aceso, energia estalando entre o pé e a bola
--   Explosao 10.4-12  48-50s    na explosão da música: a bola sai em velocidade MÁXIMA pro
--                               gol, explosõezinhas em volta; ele cai de costas e levanta
-- O áudio (Flow_Shidou_Cena_v2) tem as falas presas em 0.6 / 4.3 / 8.9 / 12.2 e a explosão
-- da música em 10.4 — não mexer nesses tempos sem remixar (skill flow-cutscene).
-- No último quadro o servidor solta a bola e o chute SAI (PulseController
-- _G.TocarCenaFlow → ChuteNoFlow) e o Flow começa ao mesmo tempo (InstinctController).
-- A câmera dos closes vem dos efeitos (FlowShidou.CameraMundo): segue a cabeça de verdade.
do
	local FS = {}
	Cutscenes.Flow_Shidou = FS
	FS.Motor = "V2"
	FS.Efeitos = "FlowShidou"
	FS.KickFoot = "Right"
	FS.Duration = 12
	FS.ImpactTime = 9.88 -- (v126) o CONTATO: a chuteira acerta a bola (a saída é em FS.Saida)
	FS.Saida = 10.4 -- a bola sai (explosão da música)
	FS.ColarNoPe = true
	FS.ColaInicio = 9.82 -- (v126) só no fim do chutão: antes disso a bola fica parada no ar
	FS.ColaCongelaNoChute = true -- (v125) ele cai depois da bicicleta: a bola não desce junto com o pé
	FS.KickContactDir = V3(0, 0.6, -1).Unit -- (v125) o pé pega a bola por trás/baixo e manda pro gol (−Z)
	FS.SemTremidaImpacto = true -- (v126) os tremores são dos efeitos: leve no contato, forte na saída
	FS.ChuteNoFlow = true -- ⚠️ v124: ativar o Flow = CHUTAR (a cena termina com a bola saindo pra mira)
	FS.TitleText = "FLOW · SHIDOU RYUSEI"
	FS.Tema = {
		Titulo = { rgb(255, 250, 230), rgb(255, 90, 200), rgb(255, 230, 90) },
		Contorno = rgb(40, 0, 25), Flash = rgb(255, 225, 245),
		Tint = rgb(255, 245, 250), Saturation = 0.2, Contrast = 0.15, Brightness = 0,
	}
	FS.Phases = {
		Chega = { 0, 1.4 }, Aura = { 1.4, 3.0 }, Rosto = { 3.0, 4.4 }, Olho = { 4.4, 5.4 }, Tunel = { 5.4, 6.3 },
		Peito = { 6.3, 7.5 }, Chamas = { 7.5, 8.4 }, BigBang = { 8.4, 9.75 }, Kick = { 9.75, FS.ImpactTime },
		Parada = { FS.ImpactTime, FS.Saida }, Impact = { FS.ImpactTime, FS.Duration }, Explosao = { FS.Saida, FS.Duration },
	}

	-- corpo (v126): levita nas chamas, desce, VIRA DE COSTAS pro gol (yaw 180), agacha,
	-- SALTA rápido, sobe DEVAGAR no ar (câmera lenta), tomba pra trás no chutão (pitch até
	-- ~105, NÃO 360), fica suspenso com a bola parada, cai de costas e levanta.
	-- (R6 de pé: quadril ~3 studs acima do gramado; deitado de costas: ~0.5)
	local FS_ALTURA = {
		{ 0, 0 }, { 1.4, 0 }, { 1.8, 0.25 }, { 6.3, 0.25 }, { 7.6, 1.2 }, { 8.3, 1.2 },
		{ 8.55, 0 }, { 9.0, 0 }, { 9.06, -0.35 }, { 9.12, -0.1 }, { 9.25, 2.0 }, { 9.75, 2.85 },
		{ FS.ImpactTime, 3.0 }, { FS.Saida, 3.06 }, { 10.75, 2.5 }, { 11.25, -2.4 }, { 11.55, -2.4 },
		{ 11.95, -0.2 }, { 12, 0 },
	}
	-- tomba pra trás = vai na direção do gol (−Z)
	local FS_Z = { { 0, 0 }, { 9.2, 0 }, { FS.ImpactTime, -0.6 }, { FS.Saida, -0.62 }, { 11.25, -1.8 }, { 12, -1.8 } }
	local FS_PITCH = {
		{ 0, 0 }, { 9.2, 0 }, { 9.25, 6 }, { 9.75, 62 }, { FS.ImpactTime, 105 }, { FS.Saida, 108 },
		{ 10.8, 100 }, { 11.25, 88 }, { 11.55, 88 }, { 11.95, 0 }, { 12, 0 },
	}
	function FS.RootPosition(t)
		local respira = (t < 8.3) and 0.04 * math.sin(t * 3) or 0
		return V3(0, sample(FS_ALTURA, t) + respira, sample(FS_Z, t))
	end
	function FS.RootCFrame(t)
		local giro = smooth(phase(t, 8.55, 8.95)) * 180 -- vira suave (não linear)
		return CFrame.new(FS.RootPosition(t)) * CFrame.Angles(0, rad(giro), 0) * CFrame.Angles(rad(sample(FS_PITCH, t)), 0, 0)
	end

	-- bola (v126): lá no ALTO caindo devagar (primeira pessoa); some na aura/closes; volta
	-- no estádio escuro descendo sobre ele, quase PARA no ar na câmera lenta, encontra a
	-- chuteira (contato), fica PARADA ~0.5s e sai em velocidade máxima pra mira (−Z)
	local FS_BOLA_CEU = V3(0.3, 20, -6.5) -- (conferido: a 30 studs ela ficava um pontinho)
	local FS_BOLA_CEU2 = V3(0.25, 16.5, -5.5)
	local FS_BOLA_ALTO = V3(-0.5, 16, -0.8)
	local FS_BOLA_CONTATO = V3(-0.5, 5.8, -0.4) -- (pé direito: com o giro de 180 fica no −X; medido no Studio)
	local FS_BOLA_U = { { 8.4, 0 }, { 9.25, 0.62 }, { 9.75, 0.92 }, { FS.ImpactTime, 1 } } -- desce → quase para → chega
	local FS_BOLA_SAIDA = V3(0, -0.04, -1).Unit * 28 -- (some em 10.85; o servidor continua o chute dali)
	FS.BolaContato = FS_BOLA_CONTATO
	function FS.BallPosition(t, _s)
		if t < 8.4 then
			return FS_BOLA_CEU:Lerp(FS_BOLA_CEU2, phase(t, 0, 1.4))
		elseif t < FS.ImpactTime then
			return FS_BOLA_ALTO:Lerp(FS_BOLA_CONTATO, sample(FS_BOLA_U, t))
		elseif t < FS.Saida then
			-- parada na chuteira, tremendo cada vez mais (a energia acumulando)
			local k = phase(t, FS.ImpactTime, FS.Saida) * 0.05
			return FS_BOLA_CONTATO + V3(k * math.sin(t * 97), k * math.cos(t * 83), 0)
		end
		-- sai em velocidade MÁXIMA (linear, sem aceleração)
		return FS_BOLA_CONTATO + FS_BOLA_SAIDA * phase(t, FS.Saida, 10.8)
	end
	function FS.BallVisible(t) return t < 1.4 or (t >= 8.4 and t < 10.85) end
	function FS.BallSpin(t)
		if t >= FS.Saida then return 16 end
		if t >= FS.ImpactTime then return 0 end -- parada
		if t >= 9.75 then return 3 end
		return 0.6 -- câmera lenta: gira devagar
	end

	-- R6: braço/perna RETOS. Braço pra fora com |rz| >= 40 em movimento (não entra no tronco).
	-- Root rx+ inclina pra TRÁS; a perna fica reta compensando (Hip = -Root).
	local FS_POSE = {
		-- Chega: olhando pra CIMA a bola (primeira pessoa; o corpo nem aparece)
		{ 0.00, { Root = { 4, 0, 0 }, Neck = { 40, 0, 0 }, RHip = { -4, 0, 8 }, LHip = { -4, 0, -8 },
			RShoulder = { -10, 0, 40 }, LShoulder = { -10, 0, -40 } } },
		{ 1.30, { Root = { 4, 0, 0 }, Neck = { 40, 0, 0 }, RHip = { -4, 0, 8 }, LHip = { -4, 0, -8 },
			RShoulder = { -12, 0, 42 }, LShoulder = { -12, 0, -42 } } },
		-- Aura: inclinado pra trás, um braço aberto, o outro caído (como no vídeo)
		{ 1.70, { Root = { 16, 0, 0 }, Neck = { -6, 0, 0 }, RHip = { -18, 0, 12 }, LHip = { -8, 0, -12 },
			RShoulder = { 20, 0, 52 }, LShoulder = { -25, 0, -62 } } },
		{ 3.00, { Root = { 18, 0, 0 }, Neck = { -8, 0, 0 }, RHip = { -20, 0, 12 }, LHip = { -10, 0, -12 },
			RShoulder = { 22, 0, 55 }, LShoulder = { -28, 0, -65 } } },
		-- Rosto / Olho (v126c): o corpo inteiro visto de cima — tronco jogado pra trás, o rosto
		-- VIRADO PRA CIMA (pra bola/câmera), um braço aberto pro alto e o outro solto pra fora
		{ 3.60, { Root = { 14, 0, 0 }, Neck = { 40, 0, 0 }, RHip = { -14, 0, 12 }, LHip = { -10, 0, -12 },
			RShoulder = { 35, 0, 75 }, LShoulder = { -20, 0, -55 } } },
		{ 4.40, { Root = { 16, 0, 0 }, Neck = { 48, 0, 0 }, RHip = { -16, 0, 12 }, LHip = { -12, 0, -12 },
			RShoulder = { 45, 0, 85 }, LShoulder = { -25, 0, -60 } } },
		{ 5.40, { Root = { 17, 0, 0 }, Neck = { 50, 0, 0 }, RHip = { -17, 0, 12 }, LHip = { -12, 0, -12 },
			RShoulder = { 50, 0, 90 }, LShoulder = { -28, 0, -62 } } },
		-- Peito: braços ABERTOS (como no vídeo, de frente)
		{ 6.30, { Root = { 0, 0, 0 }, Neck = { 20, 0, 0 }, RHip = { 0, 0, 8 }, LHip = { 0, 0, -8 },
			RShoulder = { -10, 0, 100 }, LShoulder = { -10, 0, -100 } } },
		{ 7.40, { Root = { 0, 0, 0 }, Neck = { 22, 0, 0 }, RHip = { 0, 0, 8 }, LHip = { 0, 0, -8 },
			RShoulder = { -10, 0, 104 }, LShoulder = { -10, 0, -104 } } },
		-- Chamas: no ar, inclinado pra trás, braços pra fora e atrás, pernas soltas
		{ 7.80, { Root = { 32, 0, 0 }, Neck = { -18, 0, 0 }, RHip = { -45, 0, 14 }, LHip = { -25, 0, -14 },
			RShoulder = { -38, 0, 72 }, LShoulder = { -38, 0, -72 } } },
		{ 8.30, { Root = { 34, 0, 0 }, Neck = { -20, 0, 0 }, RHip = { -48, 0, 14 }, LHip = { -28, 0, -14 },
			RShoulder = { -40, 0, 76 }, LShoulder = { -40, 0, -76 } } },
		-- BigBang: aterrissa olhando a bola lá em cima e VIRA de costas pro gol
		{ 8.55, { Root = { 4, 0, 0 }, Neck = { 38, 0, 0 }, RHip = { -4, 0, 8 }, LHip = { -4, 0, -8 },
			RShoulder = { -10, 0, 48 }, LShoulder = { -10, 0, -48 } } },
		{ 8.95, { Root = { 2, 0, 0 }, Neck = { 40, 0, 0 }, RHip = { -2, 0, 8 }, LHip = { -2, 0, -8 },
			RShoulder = { -14, 0, 50 }, LShoulder = { -14, 0, -50 } } },
		-- agacha pra saltar (peso pra frente, braços atrás)
		{ 9.06, { Root = { -14, 0, 0 }, Neck = { 32, 0, 0 }, RHip = { 58, 0, 8 }, LHip = { 58, 0, -8 },
			RShoulder = { -50, 0, 45 }, LShoulder = { -50, 0, -45 } } },
		-- ⚠️ v126b — PEDIDO: "faça uma animação mais exagerada, o pé mais longe, o braço mais
		-- pra um lado e pro outro, mais exagerado ainda".
		-- decola: estica, braços lá em cima, o joelho esquerdo puxa (tesoura)
		{ 9.20, { Root = { 0, 0, 0 }, Neck = { 26, 0, 0 }, RHip = { 6, 0, 8 }, LHip = { 40, 0, -8 },
			RShoulder = { 155, 0, 42 }, LShoulder = { 155, 0, -42 } } },
		-- câmera lenta no ar: a esquerda sobe primeiro, a direita (do chute) vai LÁ ATRÁS; os
		-- braços abrem cada um pra um lado
		{ 9.50, { Root = { 0, 0, 0 }, Neck = { 16, 0, 0 }, RHip = { -25, 0, 8 }, LHip = { 85, 0, -10 },
			RShoulder = { 60, 0, 100 }, LShoulder = { -40, 0, -75 } } },
		{ 9.75, { Root = { 0, 0, 0 }, Neck = { 12, 0, 0 }, RHip = { -45, 0, 8 }, LHip = { 100, 0, -10 },
			RShoulder = { -75, 0, 105 }, LShoulder = { 75, 0, -115 } } },
		-- CHUTÃO: corpo tombado ~105 (RootCFrame), a direita passa BEM por cima da cabeça
		-- (105+118 = ~223 do "pra baixo": por cima e LONGE, pro lado do gol); a esquerda desce
		-- forte (tesoura); os braços trocam de lado no tranco
		{ FS.ImpactTime, { Root = { 0, 0, 0 }, Neck = { 12, 0, 0 }, RHip = { 118, 0, 8 }, LHip = { -32, 0, -12 },
			RShoulder = { 75, 0, 125 }, LShoulder = { -85, 0, -125 } } },
		-- suspenso com a bola parada no pé
		{ FS.Saida, { Root = { 0, 0, 0 }, Neck = { 10, 0, 0 }, RHip = { 122, 0, 8 }, LHip = { -36, 0, -12 },
			RShoulder = { 80, 0, 128 }, LShoulder = { -90, 0, -128 } } },
		-- caindo de costas, pernas descendo, braços abertos pra amortecer
		{ 10.80, { Root = { 0, 0, 0 }, Neck = { 18, 0, 0 }, RHip = { 45, 0, 10 }, LHip = { 15, 0, -10 },
			RShoulder = { -40, 0, 80 }, LShoulder = { -40, 0, -80 } } },
		-- deitado de costas no gramado (mãos abertas no chão)
		{ 11.25, { Root = { 0, 0, 0 }, Neck = { 22, 0, 0 }, RHip = { 12, 0, 12 }, LHip = { 8, 0, -12 },
			RShoulder = { -10, 0, 85 }, LShoulder = { -10, 0, -85 } } },
		{ 11.55, { Root = { 0, 0, 0 }, Neck = { 18, 0, 0 }, RHip = { 12, 0, 12 }, LHip = { 8, 0, -12 },
			RShoulder = { -10, 0, 85 }, LShoulder = { -10, 0, -85 } } },
		-- senta e levanta (o tronco volta pra frente — não é giro, é levantar)
		{ 11.95, { Root = { -6, 0, 0 }, Neck = { 8, 0, 0 }, RHip = { 20, 0, 8 }, LHip = { 20, 0, -8 },
			RShoulder = { 10, 0, 55 }, LShoulder = { 10, 0, -55 } } },
		{ 12.00, { Root = { 0, 0, 0 }, Neck = { 6, 0, 0 }, RHip = { 12, 0, 8 }, LHip = { 12, 0, -8 },
			RShoulder = { 20, 0, 60 }, LShoulder = { 20, 0, -60 } } },
	}
	function FS.Pose(t) return samplePoseFluida(FS_POSE, t) end

	-- câmera BASE (planos abertos); os closes (Rosto/Olho e o rosto na bola parada) vêm de
	-- FlowShidou.CameraMundo, que segue a cabeça de verdade
	function FS.Camera(t, rootPos)
		local cabeca = rootPos + V3(0, 1.5, 0)
		if t < 1.4 then
			-- PRIMEIRA PESSOA: dos olhos dele, olhando a bola lá no alto (respiração acelerada)
			local u = smooth(phase(t, 0, 1.4))
			local olho = cabeca + V3(0.03 * math.sin(t * 9), 0.05 + 0.025 * math.sin(t * 13), -0.65)
			local bola = FS.BallPosition(t)
			return olho, olho:Lerp(bola, 0.5) + V3(0, -2, 0) * (1 - u), 72 - 12 * u
		elseif t < 3.0 then
			local u = smooth(phase(t, 1.4, 3.0))
			return V3(3.0, 0.4, -5.2):Lerp(V3(2.4, 0.3, -4.4), u), rootPos + V3(0, 0.3, 0), 50
		elseif t < 6.3 then
			-- ⚠️ v126c — PEDIDO: "a cena que mostra os olhos: não precisa mostrar os olhos de
			-- perto — mostra o personagem INTEIRO, só mudando os olhos, com uma pose legal,
			-- olhando pra cima, como se você estivesse olhando de cima (a bola) e o olho mudando".
			-- Câmera ALTO e na frente (onde a bola está), olhando ele lá embaixo; ele olha pra
			-- cima, pra câmera, e os olhos acendem/viram a íris do Shidou no rosto.
			local u = smooth(phase(t, 3.0, 6.3))
			return rootPos + V3(0.6, 8.0, -5.0):Lerp(V3(0.4, 6.4, -3.7), u), rootPos + V3(0, 0.8, 0), 46 -- (conferido: mais longe ele ficava pequeno)
		elseif t < 7.5 then
			-- de frente, na altura do peito, os braços abertos
			local u = smooth(phase(t, 6.3, 7.5))
			return rootPos + V3(0, 0.6, -4.8):Lerp(V3(0, 0.5, -3.9), u), rootPos + V3(0, 0.3, 0), 52
		elseif t < 8.4 then
			-- de baixo e de lado: ele no ar, chamas escorrendo, as asas abertas
			local u = smooth(phase(t, 7.5, 8.4))
			return rootPos + V3(2.6, -2.2, -3.8):Lerp(V3(2.1, -1.8, -3.0), u), rootPos + V3(0, 0.9, 0), 58
		elseif t < 9.0 then
			-- estádio escuro, de baixo e de lado: ele embaixo, a bola descendo lá em cima,
			-- ele vira de costas pro gol
			local u = smooth(phase(t, 8.4, 9.0))
			-- (conferido no Studio: em y −2 a câmera entrava no gramado — tela preta)
			return V3(-11, -0.7, 1.0):Lerp(V3(-10.5, -0.4, 1.6), u), V3(0, 4.2, -0.5), 72
		elseif t < FS.ImpactTime then
			-- perfil do salto, de baixo e do lado da perna de chute: vê ele subir até a bola
			local u = smooth(phase(t, 9.0, FS.ImpactTime))
			return V3(-10.5, -0.6, 2.5):Lerp(V3(-9.2, 0.9, 1.2), u), V3(0, 1.6, 0):Lerp(V3(0, 4.4, -0.3), u), 60
		elseif t < FS.Saida then
			-- a bola PARADA na chuteira, de lado (v126b: "tira aquele close final nos olhos" —
			-- o olho do Shidou já aparece no zoom dos olhos brancos); a câmera chega devagar
			local u = smooth(phase(t, FS.ImpactTime, FS.Saida))
			return V3(-9.2, 0.9, 1.2):Lerp(V3(-8.0, 1.7, 0.6), u), V3(0, 4.4, -0.3):Lerp(V3(0, 4.9, -0.5), u), 58
		elseif t < 10.85 then
			-- a bola SAI: atrás dele, na altura dela — dá pra ver ela indo pro gol
			local u = smooth(phase(t, FS.Saida, 10.85))
			return V3(-4.5, 6.0, 5.5):Lerp(V3(-5.0, 6.4, 6.4), u), V3(0, 5.4, -16), 64
		end
		-- ele cai de costas e levanta (de baixo, de lado)
		local u = smooth(phase(t, 10.85, FS.Duration))
		return V3(-6.5, -1.0, 3.0):Lerp(V3(-6.0, -0.6, 2.2), u), rootPos + V3(0, 0.4, 0), 55
	end
end

-- ============================================================
-- 🌹 FLOW DO SAE — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o PRODÍGIO frio. Pétalas de rosa vermelha caindo;
-- de olhos fechados; abre os olhos (verde-água frios) e ramos com ROSAS sobem
-- pelas pernas; o passe perfeito sem olhar — a bola vai longe num arco com
-- rastro vermelho e rosas desabrocham no chão pelo caminho; ele vira as costas
-- e olha por cima do ombro.
local FSa = {}
Cutscenes.Flow_Sae = FSa
FSa.Motor = "V2"
FSa.Efeitos = "FlowSae"
FSa.KickFoot = "Right"
FSa.Duration = 12
FSa.ImpactTime = 11.3
FSa.Passe = 4.4
FSa.ColarNoPe = false
FSa.TitleText = "FLOW · ITOSHI SAE"
FSa.Tema = {
	Titulo = { rgb(255, 240, 240), rgb(230, 50, 80), rgb(110, 10, 30) },
	Contorno = rgb(40, 0, 10), Flash = rgb(255, 210, 220),
	Tint = rgb(255, 245, 245), Saturation = 0, Contrast = 0.2, Brightness = -0.02,
}
FSa.Phases = {
	Fecha = { 0, 2 }, Abre = { 2, 3.5 }, Arma = { 3.5, FSa.Passe }, Voa = { FSa.Passe, 8.2 },
	Costas = { 8.5, 12 }, Kick = { 4.1, FSa.Passe }, Impact = { FSa.ImpactTime, FSa.Duration },
}
function FSa.RootPosition(_t) return V3(0, 0, 0) end
local FSA_YAW = { { 0, 0 }, { 8.4, 0 }, { 9.4, 160 }, { 12, 160 } } -- vira as costas
function FSa.RootCFrame(t) return CFrame.new(0, 0, 0) * CFrame.Angles(0, rad(sample(FSA_YAW, t)), 0) end
function FSa.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FSa.BallVisible(t) return t < 0.05 end
function FSa.BallSpin() return 0 end
local FSA_CALMO = { Root = { 2, 0, 0 }, Neck = { -6, 0, 0 }, RShoulder = { -14, 0, 8 }, LShoulder = { -14, 0, -8 } }
local FSA_POSE = {
	{ 0.00, FSA_CALMO }, { 3.50, FSA_CALMO },
	{ 4.10, { Root = { -4, 0, 0 }, Neck = { -4, 0, 0 }, RHip = { -45, 0, 0 }, RShoulder = { -20, 0, 40 }, LShoulder = { 30, 0, -45 } } },
	{ FSa.Passe, { Root = { -8, 0, 0 }, Neck = { -2, 20, 0 }, RHip = { 75, 0, -10 }, RShoulder = { -30, 0, 45 }, LShoulder = { 40, 0, -45 } } }, -- passe sem olhar
	{ 5.40, { Root = { -4, 0, 0 }, Neck = { 0, 20, 0 }, RHip = { 45, 0, -8 }, RShoulder = { -20, 0, 30 }, LShoulder = { 20, 0, -30 } } },
	{ 6.40, FSA_CALMO },
	{ 9.40, { Root = { 2, 0, 0 }, Neck = { -4, -70, 0 }, RShoulder = { -14, 0, 8 }, LShoulder = { -14, 0, -8 } } }, -- olha por cima do ombro
	{ 12.00, { Root = { 2, 0, 0 }, Neck = { -2, -75, 0 }, RShoulder = { -14, 0, 8 }, LShoulder = { -14, 0, -8 } } },
}
function FSa.Pose(t) return samplePose(FSA_POSE, t) end
function FSa.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2 then
		local u = smooth(phase(t, 0, 2))
		return V3(1.6, 0.4, -7):Lerp(V3(1.2, 0.3, -5.8), u), V3(0, 0.5, 0), 50
	elseif t < 3.5 then
		local u = smooth(phase(t, 2, 3.5))
		return cabeca + V3(0.3, -0.2, -3.8):Lerp(V3(0.2, -0.15, -3), u), cabeca, 36
	elseif t < FSa.Passe then
		return V3(3.5, -1.8, -4.5), V3(0.3, -1.6, -1), 52
	elseif t < 8.4 then
		-- o arco da bola: de lado e aberta, acompanhando o voo
		local u = smooth(phase(t, FSa.Passe, 8.2))
		return V3(22, 5, -8):Lerp(V3(24, 6, -34), u), V3(0, 3, -6):Lerp(V3(0, 1, -42), u), 55
	end
	-- ele virou (olha pra +Z): a câmera fica atrás dele, do lado pra onde ele
	-- vira a cabeça — as costas e o perfil olhando por cima do ombro
	local u = smooth(phase(t, 8.4, 12))
	return cabeca + V3(-1.6, -0.2, -4.6):Lerp(V3(-1.3, -0.15, -3.6), u), cabeca, 40
end

-- ============================================================
-- 🌹 FLOW DO KAISER — cena de ativação (⚠️ v113)
-- ============================================================
-- A melhor cena dele: o IMPERADOR e o KAISER IMPACT. Braços abertos no meio
-- das pétalas de rosa AZUL; a tatuagem da rosa azul no pescoço acende, olhos
-- azuis; espinhos azuis sobem pela perna; o chute mais rápido do mundo — o
-- mundo fica cinza (só o azul) e a bola sai num raio azul; fecha com a mão no
-- rosto e o sorriso.
local FKa = {}
Cutscenes.Flow_Kaiser = FKa
FKa.Motor = "V2"
FKa.Efeitos = "FlowKaiser"
FKa.KickFoot = "Right"
FKa.Duration = 12
FKa.ImpactTime = 11.3
FKa.Impacto = 5.6
FKa.ColarNoPe = false
FKa.TitleText = "FLOW · MICHAEL KAISER"
FKa.Tema = {
	Titulo = { rgb(235, 245, 255), rgb(80, 130, 255), rgb(20, 40, 120) },
	Contorno = rgb(0, 10, 40), Flash = rgb(210, 225, 255),
	Tint = rgb(240, 245, 255), Saturation = 0.05, Contrast = 0.2, Brightness = -0.02,
}
FKa.Phases = {
	Imperador = { 0, 2 }, Rosto = { 2, 3.5 }, Espinhos = { 3.5, 5.0 }, Kick = { 5.0, FKa.Impacto },
	Voa = { FKa.Impacto, 8.4 }, Final = { 8.4, 12 }, Impact = { FKa.ImpactTime, FKa.Duration },
}
local FKA_ROOT = { { 0, V3(0, 0, 0) }, { 5.0, V3(0, 0, 0) }, { FKa.Impacto, V3(0, -0.3, -0.8) }, { 8.4, V3(0, 0, -1) }, { 12, V3(0, 0, -1) } }
function FKa.RootPosition(t) return sample(FKA_ROOT, t) end
function FKa.RootCFrame(t) return CFrame.new(FKa.RootPosition(t)) end
function FKa.BallPosition(_t, s) return s or V3(0, -2.3, -1.8) end
function FKa.BallVisible(t) return t < 0.05 end
function FKa.BallSpin() return 0 end
local FKA_ABERTO = { Root = { 6, 0, 0 }, Neck = { 18, 0, 0 }, RShoulder = { 30, 0, 110 }, LShoulder = { 30, 0, -110 } }
local FKA_POSE = {
	{ 0.00, FKA_ABERTO }, { 2.00, FKA_ABERTO },
	{ 3.50, { Root = { 0, 0, 0 }, Neck = { 4, 0, 0 }, RShoulder = { -8, 0, 12 }, LShoulder = { -8, 0, -12 } } },
	{ 5.00, { Root = { -6, 0, 0 }, Neck = { -6, 0, 0 }, RHip = { -60, 0, 0 }, RShoulder = { -30, 0, 55 }, LShoulder = { 45, 0, -60 } } },
	{ FKa.Impacto, { Root = { -12, 0, 0 }, Neck = { -10, 0, 0 }, RHip = { 100, 0, 0 }, LHip = { -10, 0, 0 },
		RShoulder = { -45, 0, 60 }, LShoulder = { 55, 0, -60 } } }, -- KAISER IMPACT
	{ 7.00, { Root = { -8, 0, 0 }, RHip = { 70, 0, 0 }, RShoulder = { -35, 0, 55 }, LShoulder = { 45, 0, -55 } } },
	-- mão no rosto, sorriso
	{ 8.80, { Root = { 4, 0, 0 }, Neck = { 12, 0, 8 }, RShoulder = { 150, 0, -35 }, LShoulder = { -5, 0, -15 } } },
	{ 12.00, { Root = { 5, 0, 0 }, Neck = { 14, 0, 10 }, RShoulder = { 152, 0, -37 }, LShoulder = { -5, 0, -15 } } },
}
function FKa.Pose(t) return samplePose(FKA_POSE, t) end
function FKa.Camera(t, rootPos)
	local cabeca = rootPos + V3(0, 1.5, 0)
	if t < 2 then
		local u = smooth(phase(t, 0, 2))
		return V3(0.5, -0.6, -9):Lerp(V3(0.4, -0.4, -7.5), u), V3(0, 0.8, 0), 52
	elseif t < 3.5 then
		-- close no pescoço e no rosto (a tatuagem da rosa azul)
		local u = smooth(phase(t, 2, 3.5))
		return cabeca + V3(-1.2, -0.6, -3.4):Lerp(V3(-1, -0.5, -2.7), u), cabeca + V3(0, -0.3, 0), 38
	elseif t < FKa.Impacto then
		return V3(4, -1.6, -3), V3(0.3, -1.2, -0.6), 52
	elseif t < 8.4 then
		-- de trás e do lado: o raio azul saindo (bem atrás, o corpo tapava a bola)
		return rootPos + V3(5.5, 1.2, 4.5), rootPos + V3(0, 0.3, -30), 50
	end
	-- mão no rosto: do lado esquerdo dele (o braço não tapa)
	local u = smooth(phase(t, 8.4, 12))
	return cabeca + V3(-1.3, -0.3, -4.4):Lerp(V3(-1, -0.25, -3.4), u), cabeca, 38
end


return Cutscenes
