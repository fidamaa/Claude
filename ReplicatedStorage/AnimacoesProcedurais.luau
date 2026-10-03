--[[
	AnimacoesProcedurais (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	⚠️ v96 — ANIMAÇÕES FEITAS POR CÓDIGO, PRA TUDO QUE EXISTE NO JOGO.
	PEDIDO: "faça uma animação pra cada coisa que já existe no jogo. As
	animações atuais são provisórias... pesquisa referências, pega pelo menos
	duas referências pra entender exatamente como funciona cada movimento de
	andar, de correr, de dive... o chute: o pé tinha que ir mais pra trás pra
	simbolizar que você está se esforçando; talvez quanto mais você segure,
	mais pra trás ele vai."

	E o problema das animações "emboladas" (mão solta, duas animações ao mesmo
	tempo): vinham de TRÊS fontes tocando juntas no mesmo corpo — o Animate
	do place, o pacote de animação do avatar de cada jogador (só no jogo
	publicado, por isso não aparecia no Studio) e as nossas tracks por cima.
	Onde a de cima não animava uma junta (a mão), aparecia a de baixo. Agora
	UM animador só (AnimadorProcedural.local.luau) controla TODAS as juntas,
	e todas as outras animações ficam desligadas.

	Este módulo é só a BIBLIOTECA DE POSES (dados + funções puras). Quem
	aplica no corpo é o AnimadorProcedural.

	CONVENÇÃO (a mesma da cutscene do Tornado de Fogo, validada no avatar):
	graus, no espaço da peça-pai da junta.
	  Quadril/ombro: rx+ = membro pra FRENTE; rz+ = abre pro lado (DIREITO
	    positivo, ESQUERDO negativo).
	  Joelho: negativo = dobra. Cotovelo: positivo = dobra.
	  Tornozelo: rx+ = ponta do pé pra cima; rx- = pé esticado.
	  Root (corpo todo) / Waist (tronco): rx+ = inclina pra TRÁS, rx- = pra
	    frente; rz- = tomba pra DIREITA; ry = gira.
	  Neck: rx+ = olha pra cima.
	  RootPos: deslocamento do quadril (studs) — agachar, quicar, deitar.

	REFERÊNCIAS usadas pros números (≥2 por movimento, ver o relatório):
	  Andar: quadril +30/-10, joelho ~15 na carga e ~60 no balanço, 60% apoio.
	  Correr: quadril até ~55 de flexão, joelho até ~125 no meio do balanço,
	    cotovelo ~90, braço oposto à perna.
	  Chute (peito do pé): quadril estende ~30 e joelho dobra ~100 no
	    backswing; depois coxa vai à frente com o joelho dobrado, o joelho
	    estica no contato e segue no follow-through.
	  Mergulho do goleiro: impulso com a perna do lado CONTRÁRIO, passo lateral
	    com a do mesmo lado, saída ~45°, corpo esticado, braços na bola.
	  Carrinho: centro de gravidade baixo, perna da frente esticada com a
	    ponta pra cima, a de trás dobrada por baixo, mão de apoio atrás.
	  Cabeceio: arqueia pra trás, trava o pescoço e projeta a testa, braços
	    abertos pra equilíbrio.
]]

local Anim = {}

Anim.JOINTS = {
	"Root", "Waist", "Neck",
	"RShoulder", "LShoulder", "RElbow", "LElbow", "RWrist", "LWrist",
	"RHip", "LHip", "RKnee", "LKnee", "RAnkle", "LAnkle",
}

local V = Vector3.new
local ZERO = Vector3.zero
local PI2 = math.pi * 2

-- ===== utilidades =====
local function clamp01(x) return math.clamp(x, 0, 1) end
local function smooth(u) u = clamp01(u) return u * u * (3 - 2 * u) end
local function lerp(a, b, t) return a + (b - a) * t end
Anim.Smooth = smooth

-- Sino gaussiano periódico (fase 0..1) centrado em c com largura w — usado
-- pros "picos" de dobra de joelho/tornozelo dentro do ciclo da passada.
local function bump(phi, c, w)
	local d = (phi - c + 0.5) % 1 - 0.5
	return math.exp(-(d / w) ^ 2)
end

-- Pose = { [junta] = Vector3(graus), RootPos = Vector3 }
function Anim.Blend(a, b, t)
	if t <= 0 then return a end
	if t >= 1 then return b end
	local out = {}
	for _, j in ipairs(Anim.JOINTS) do
		out[j] = (a[j] or ZERO):Lerp(b[j] or ZERO, t)
	end
	out.RootPos = (a.RootPos or ZERO):Lerp(b.RootPos or ZERO, t)
	return out
end

-- Mistura só ALGUMAS juntas de b em a (o resto fica de a).
function Anim.BlendMask(a, b, t, mascara)
	local out = {}
	for _, j in ipairs(Anim.JOINTS) do
		local peso = (mascara[j] or 0) * t
		out[j] = (a[j] or ZERO):Lerp(b[j] or ZERO, peso)
	end
	out.RootPos = (a.RootPos or ZERO):Lerp(b.RootPos or ZERO, (mascara.RootPos or 0) * t)
	return out
end

-- Espelha uma pose (direita <-> esquerda): troca R/L e inverte ry/rz.
local function espelhar(p)
	local out = {}
	for chave, v in pairs(p) do
		if chave == "RootPos" then
			out.RootPos = V(-v.X, v.Y, v.Z)
		else
			local nova = chave
			if chave:sub(1, 1) == "R" and chave ~= "Root" then
				nova = "L" .. chave:sub(2)
			elseif chave:sub(1, 1) == "L" then
				nova = "R" .. chave:sub(2)
			end
			out[nova] = V(v.X, -v.Y, -v.Z)
		end
	end
	return out
end
Anim.Espelhar = espelhar

-- Amostra uma lista de quadros { {t, pose}, ... } com transição suave.
local function amostrar(quadros, t)
	if t <= quadros[1][1] then return quadros[1][2] end
	for i = 1, #quadros - 1 do
		local a, b = quadros[i], quadros[i + 1]
		if t <= b[1] then
			local u = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 1
			return Anim.Blend(a[2], b[2], smooth(u))
		end
	end
	return quadros[#quadros][2]
end
Anim.Amostrar = amostrar

-- ⚠️ v105 — "melhora as animações de dive... mantém, só deixa mais fluidas".
-- `amostrar` suaviza CADA trecho sozinho (acelera e freia em toda pose-chave:
-- o corpo "para" em cada quadro). Aqui a curva passa pelas MESMAS poses, mas
-- contínua (Catmull-Rom): a velocidade não zera no meio do movimento.
local function catmull(p0, p1, p2, p3, u)
	local u2, u3 = u * u, u * u * u
	return (p1 * 2 + (p2 - p0) * u + (p0 * 2 - p1 * 5 + p2 * 4 - p3) * u2 + (p1 * 3 - p0 - p2 * 3 + p3) * u3) * 0.5
end
local function amostrarSuave(quadros, t)
	local n = #quadros
	if t <= quadros[1][1] then return quadros[1][2] end
	if t >= quadros[n][1] then return quadros[n][2] end
	for i = 1, n - 1 do
		local a, b = quadros[i], quadros[i + 1]
		if t <= b[1] then
			local u = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 1
			local q0 = (quadros[i - 1] or a)[2]
			local q3 = (quadros[i + 2] or b)[2]
			local out = {}
			for _, j in ipairs(Anim.JOINTS) do
				local p1, p2 = a[2][j], b[2][j]
				if p1 or p2 then
					p1, p2 = p1 or ZERO, p2 or ZERO
					out[j] = catmull(q0[j] or p1, p1, p2, q3[j] or p2, u)
				end
			end
			local r1, r2 = a[2].RootPos, b[2].RootPos
			if r1 or r2 then
				r1, r2 = r1 or ZERO, r2 or ZERO
				out.RootPos = catmull(q0.RootPos or r1, r1, r2, q3.RootPos or r2, u)
			end
			return out
		end
	end
	return quadros[n][2]
end
Anim.AmostrarSuave = amostrarSuave

local function espelharQuadros(quadros)
	local out = {}
	for i, q in ipairs(quadros) do out[i] = { q[1], espelhar(q[2]) } end
	return out
end

-- ============================================================
-- LOCOMOÇÃO
-- ============================================================
-- Parado: respiração lenta, peso trocando de leve, braços soltos.
function Anim.Parado(t)
	local b = math.sin(t * PI2 * 0.25)
	local balanco = math.sin(t * PI2 * 0.11)
	return {
		Root = V(0, 0, 1.2 * balanco),
		Waist = V(1.2 * b, 0, -0.6 * balanco),
		Neck = V(2 - 0.8 * b, 0, 0),
		RShoulder = V(2, 0, 7 + 0.8 * b), LShoulder = V(2, 0, -7 - 0.8 * b),
		RElbow = V(12, 0, 0), LElbow = V(12, 0, 0),
		RWrist = V(4, 0, 0), LWrist = V(4, 0, 0),
		RHip = V(0, 0, 4), LHip = V(0, 0, -4),
		RKnee = V(-4, 0, 0), LKnee = V(-4, 0, 0),
		RAnkle = V(3, 0, 0), LAnkle = V(3, 0, 0),
		RootPos = V(0, -0.03 + 0.015 * b, 0),
	}
end

-- Goleiro pronto (dentro da própria área): base larga, joelhos dobrados,
-- tronco à frente, braços abertos pra frente, quicando nas pontas dos pés.
function Anim.GoleiroPronto(t)
	local q = math.sin(t * PI2 * 1.6)
	return {
		Root = V(-20, 0, 0),
		Waist = V(-4, 0, 0),
		Neck = V(24, 0, 0),
		RShoulder = V(38, 0, 30), LShoulder = V(38, 0, -30),
		RElbow = V(55, 0, 0), LElbow = V(55, 0, 0),
		RWrist = V(-12, 0, 0), LWrist = V(-12, 0, 0),
		RHip = V(38, 0, 14), LHip = V(38, 0, -14),
		RKnee = V(-58, 0, 0), LKnee = V(-58, 0, 0),
		RAnkle = V(18, 0, 0), LAnkle = V(18, 0, 0),
		RootPos = V(0, -0.45 + 0.04 * q, 0),
	}
end

-- Goleiro se deslocando: mantém a postura baixa e dá passinhos laterais
-- (abre e fecha as pernas), em vez de "andar" de pé — é assim que goleiro
-- acompanha a bola na linha.
local function goleiroDeslocando(phi, t)
	local base = Anim.GoleiroPronto(t)
	local s = math.sin(phi * PI2)
	base.RHip = base.RHip + V(0, 0, 10 * s)
	base.LHip = base.LHip + V(0, 0, 10 * s)
	base.RKnee = base.RKnee + V(-10 * math.max(0, s), 0, 0)
	base.LKnee = base.LKnee + V(-10 * math.max(0, -s), 0, 0)
	base.RootPos = base.RootPos + V(0, 0.05 * math.abs(s), 0)
	return base
end

-- Um ciclo de ANDAR na fase phi (0..1 = passada completa da perna direita).
local function andar(phi)
	local w = phi * PI2
	local function perna(f)
		local ww = f * PI2
		return V(10 + 20 * math.cos(ww), 0, 0),
			V(-(8 + 12 * bump(f, 0.1, 0.07) + 50 * bump(f, 0.72, 0.12)), 0, 0),
			V(4 * math.cos(ww) - 14 * bump(f, 0.58, 0.07) + 8 * bump(f, 0.74, 0.1), 0, 0)
	end
	local rh, rk, ra = perna(phi)
	local lh, lk, la = perna((phi + 0.5) % 1)
	local c = math.cos(w)
	return {
		-- ⚠️ v103: sem rolar o corpo de lado a cada passo (pedido: "ele anda e
		-- tomba o corpo junto... deixa normal")
		Root = V(-2, 3 * c, 0),
		Waist = V(1, -6 * c, 0),
		Neck = V(3, 3 * c, 0),
		RShoulder = V(-16 * c, 0, 7), LShoulder = V(16 * c, 0, -7),
		RElbow = V(16 + 8 * math.max(0, -c), 0, 0), LElbow = V(16 + 8 * math.max(0, c), 0, 0),
		RWrist = V(5, 0, 0), LWrist = V(5, 0, 0),
		RHip = rh + V(0, 0, 3), LHip = lh + V(0, 0, -3),
		RKnee = rk, LKnee = lk, RAnkle = ra, LAnkle = la,
		RootPos = V(0, -0.05 * math.cos(2 * w) - 0.04, 0),
	}
end

-- Um ciclo de CORRER.
local function correr(phi)
	local w = phi * PI2
	local function perna(f)
		local ww = f * PI2
		return V(18 + 38 * math.cos(ww), 0, 0),
			V(-(18 + 22 * bump(f, 0.1, 0.07) + 95 * bump(f, 0.64, 0.14)), 0, 0),
			V(8 * math.cos(ww) - 22 * bump(f, 0.42, 0.07) + 10 * bump(f, 0.7, 0.1), 0, 0)
	end
	local rh, rk, ra = perna(phi)
	local lh, lk, la = perna((phi + 0.5) % 1)
	local c = math.cos(w)
	return {
		Root = V(-10, 5 * c, 0), -- ⚠️ v103: sem rolar de lado
		Waist = V(-2, -12 * c, 0),
		Neck = V(12, 5 * c, 0),
		-- braço oposto à perna; o da frente mais fechado, o de trás mais aberto
		RShoulder = V(-42 * c, 0, 10), LShoulder = V(42 * c, 0, -10),
		RElbow = V(85 - 20 * c, 0, 0), LElbow = V(85 + 20 * c, 0, 0),
		RWrist = V(-5, 0, 0), LWrist = V(-5, 0, 0),
		RHip = rh + V(0, 0, 2), LHip = lh + V(0, 0, -2),
		RKnee = rk, LKnee = lk, RAnkle = ra, LAnkle = la,
		RootPos = V(0, -0.08 - 0.12 * math.cos(2 * w + 0.6), 0),
	}
end

-- No ar: subindo (joelhos recolhidos, braços pra cima) -> descendo (pernas
-- esticando pra aterrissar, braços abertos).
local PULO = {
	Root = V(-5, 0, 0), Waist = V(2, 0, 0), Neck = V(10, 0, 0),
	RShoulder = V(60, 0, 20), LShoulder = V(55, 0, -20),
	RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
	RHip = V(45, 0, 4), LHip = V(12, 0, -4),
	RKnee = V(-80, 0, 0), LKnee = V(-30, 0, 0),
	RAnkle = V(-15, 0, 0), LAnkle = V(-20, 0, 0),
}
local QUEDA = {
	Root = V(3, 0, 0), Waist = V(0, 0, 0), Neck = V(0, 0, 0),
	RShoulder = V(22, 0, 55), LShoulder = V(22, 0, -55),
	RElbow = V(25, 0, 0), LElbow = V(25, 0, 0),
	RHip = V(25, 0, 6), LHip = V(15, 0, -6),
	RKnee = V(-35, 0, 0), LKnee = V(-25, 0, 0),
	RAnkle = V(8, 0, 0), LAnkle = V(8, 0, 0),
}

-- Estado de locomoção de UM personagem (o animador guarda e passa de volta).
-- entrada = { Velocidade (studs/s horizontal), VelVertical, NoChao (bool),
--             Goleiro (bool), GiroGrausPorSeg, Aceleracao (frente, studs/s²),
--             Tempo }
-- ⚠️ Passada: o ciclo avança pela DISTÂNCIA percorrida, não pelo tempo —
-- assim o pé não patina, em qualquer velocidade. Andar = 5.5 studs por
-- passada completa, correr = 13 (proporção de ~2.6x a altura do boneco,
-- como numa corrida de verdade).
local PASSADA_ANDAR = 5.5
local PASSADA_CORRER = 13

function Anim.NovoEstadoLocomocao()
	return { Fase = 0, VelSuave = 0, ArSuave = 0, GoleiroSuave = 0 }
end

function Anim.Locomocao(estado, e, dt)
	local vel = e.Velocidade
	estado.VelSuave = lerp(estado.VelSuave, vel, clamp01(dt * 12))
	-- (vel negativa = andando de costas: o ciclo roda ao contrário, mas o
	-- "quanto está correndo" é pelo módulo)
	local v = math.abs(estado.VelSuave)

	local pesoCorrer = smooth((v - 12) / 10)       -- 12..22 studs/s: andar -> correr
	local pesoMover = smooth((v - 0.6) / 3.5)       -- parado -> andando
	local passada = lerp(PASSADA_ANDAR, PASSADA_CORRER, pesoCorrer)
	estado.Fase = (estado.Fase + (vel / passada) * dt) % 1 -- vel com sinal: de costas o ciclo volta

	local ciclo = Anim.Blend(andar(estado.Fase), correr(estado.Fase), pesoCorrer)
	estado.GoleiroSuave = lerp(estado.GoleiroSuave, e.Goleiro and 1 or 0, clamp01(dt * 8))
	-- goleiro devagar = passinhos de goleiro; correndo de verdade = corrida
	if estado.GoleiroSuave > 0.01 then
		ciclo = Anim.Blend(ciclo, goleiroDeslocando(estado.Fase, e.Tempo), estado.GoleiroSuave * (1 - pesoCorrer))
	end
	local parado = Anim.Blend(Anim.Parado(e.Tempo), Anim.GoleiroPronto(e.Tempo), estado.GoleiroSuave)
	local pose = Anim.Blend(parado, ciclo, pesoMover)

	-- ⚠️ v103 — PEDIDO: "a animação de andar... ele anda e mexe o corpo, TOMBA
	-- o corpo junto com a andada dependendo da direção que você estiver andando.
	-- Não, deixa normal." Saíram as duas inclinações que faziam isso: pra
	-- dentro da curva (girar a câmera no Shift Lock contava como curva, então
	-- o corpo tombava conforme a direção) e pra frente/trás na aceleração.

	-- no ar
	estado.ArSuave = lerp(estado.ArSuave, e.NoChao and 0 or 1, clamp01(dt * (e.NoChao and 14 or 8)))
	if estado.ArSuave > 0.01 then
		local subindo = smooth((e.VelVertical + 6) / 20) -- descendo rápido -> subindo rápido
		local ar = Anim.Blend(QUEDA, PULO, subindo)
		ar.RootPos = ZERO
		pose = Anim.Blend(pose, ar, estado.ArSuave)
	end
	return pose
end

-- ============================================================
-- PREPARO DO CHUTE (enquanto segura o botão) — PEDIDO: "o pé tinha que ir
-- mais pra trás... talvez quanto mais você segure, mais pra trás ele vai".
-- c = carga (0 = toque, 1 = carga cheia). Chute de perna DIREITA.
-- ============================================================
-- ⚠️ v106 — PEDIDO: "o pé tá muito pouco indo pra trás na hora de preparar
-- o chute, tem que ir mais pra trás, ser mais impactante". Perna até -75°
-- (era -50°) com a carga cheia, tronco abrindo mais pro lado do chute e o
-- braço direito jogado mais pra trás. (No R6, sem joelho, a perna de trás
-- também deixou de ser encolhida pelo adaptarR6 — ver AnimadorProcedural.)
function Anim.PreparoChute(c)
	c = clamp01(c)
	return {
		-- ⚠️ v108 — PEDIDO: "no preparo do chute o personagem vira pra esquerda
		-- demais, parece que vai chutar pra esquerda. Faz ele continuar reto, só
		-- inclina um pouco pra esquerda." Era giro de 12+16c no Root + 10+14c na
		-- cintura (~52° no máximo); agora ~13° no total e uma inclinação leve pro
		-- lado da perna de apoio (roll positivo = esquerda).
		Root = V(-4 - 6 * c, 3 + 4 * c, 3 + 5 * c),
		Waist = V(2, 2 + 4 * c, 0),
		Neck = V(-12, -10, 0),                         -- olhando a bola
		LShoulder = V(30 + 30 * c, 0, -(40 + 40 * c)), -- braço esquerdo à frente/aberto (equilíbrio)
		RShoulder = V(-(28 + 40 * c), 0, 30 + 25 * c), -- braço direito bem pra trás
		LElbow = V(25, 0, 0), RElbow = V(30, 0, 0),
		RWrist = V(0, 0, 0), LWrist = V(0, 0, 0),
		RHip = V(-(28 + 47 * c), 0, 6),                -- quadril estende até -75 (era -50)
		RKnee = V(-(60 + 65 * c), 0, 0),               -- joelho dobra até -125
		RAnkle = V(-(18 + 22 * c), 0, 0),              -- pé esticado
		-- ⚠️ v122 — PEDIDO: "nos chutes só UM pé se move". No R6 (sem joelho) a perna de
		-- apoio ia de ~16° pra frente (preparo) até -4° (fim) no mundo — as duas pernas
		-- mexiam. Agora ela fica PLANTADA (~2° pra trás no mundo): o quadril só desconta
		-- a inclinação do tronco (Root) — o R6 encolhe o quadril pra frente em 0.7.
		LHip = V(3 + 8.5 * c, 0, -6),                  -- perna de apoio parada (era 24 + 14c)
		LKnee = V(-(28 + 22 * c), 0, 0),
		LAnkle = V(14, 0, 0),
		RootPos = V(0, -0.18 - 0.22 * c, 0),            -- desce mais quanto mais carrega
	}
end

-- Juntas que o preparo controla quando o jogador está se movendo (a perna
-- de apoio divide com a passada).
Anim.MASCARA_PREPARO = {
	Root = 1, Waist = 1, Neck = 1,
	RShoulder = 1, LShoulder = 1, RElbow = 1, LElbow = 1, RWrist = 1, LWrist = 1,
	RHip = 1, RKnee = 1, RAnkle = 1,
	LHip = 0.5, LKnee = 0.5, LAnkle = 0.5,
	RootPos = 0.6,
}

-- ============================================================
-- AÇÕES (uma vez só, disparadas pelo servidor)
-- Cada ação: Duracao (padrão), Quadros (função(parametros) -> lista de
-- quadros em SEGUNDOS normalizados pra Duracao), EntradaSeg/SaidaSeg (blend).
-- ============================================================
Anim.Acoes = {}

local function neutro() return {} end

-- ----- CHUTE -----
-- Backswing (vem do preparo, na carga que o jogador segurou) -> coxa vai à
-- frente com o joelho ainda dobrado ("cocking") -> contato com o joelho
-- esticado e o pé apontado -> follow-through alto, subindo na ponta do pé de
-- apoio. Mais carga = backswing mais fundo E follow-through mais alto.
Anim.Acoes.Kick = {
	Duracao = 0.52, EntradaSeg = 0.03, SaidaSeg = 0.16,
	Quadros = function(p)
		local c = clamp01(p.Carga or 0.4)
		return {
			{ 0.00, Anim.PreparoChute(c) },
			-- ⚠️ v103 — PEDIDO: "no chute você pode fazer o personagem tombar
			-- mais um pouco... o corpo descer mais pra baixo, arquear o corpo...
			-- o cara arqueia o corpo" (referência: chutes de Blue Lock e o
			-- chute de peito do pé real — tronco POR CIMA da bola no contato,
			-- joelho de apoio dobrado, corpo baixo, braço contrário aberto). Antes
			-- o tronco ia pra TRÁS no contato e o corpo subia.
			{ 0.07, {
				Root = V(-8, 4, 4), Waist = V(-4, 0, 0), Neck = V(-18, -4, 0),
				LShoulder = V(25, 0, -65), RShoulder = V(-30, 0, 45), LElbow = V(20, 0, 0), RElbow = V(25, 0, 0),
				RHip = V(10, 0, 4), RKnee = V(-105, 0, 0), RAnkle = V(-30, 0, 0),
				LHip = V(9, 0, -6), LKnee = V(-40, 0, 0), LAnkle = V(14, 0, 0), -- (v122: apoio parado, era 30)
				RootPos = V(0, -0.4, 0),
			} },
			{ 0.13, {
				Root = V(-16, -3, 6), Waist = V(-8, -6, 0), Neck = V(-24, 0, 0), -- ⚠️ v108: giro pela metade (continua reto)
				LShoulder = V(20, 0, -75), RShoulder = V(-35, 0, 45), LElbow = V(20, 0, 0), RElbow = V(25, 0, 0),
				RHip = V(55 + 15 * c, 0, 2), RKnee = V(-18, 0, 0), RAnkle = V(-35, 0, 0),
				LHip = V(20, 0, -6), LKnee = V(-42, 0, 0), LAnkle = V(14, 0, 0), -- (v122: era 34)
				RootPos = V(0, -0.45, 0),
			} },
			{ 0.26, { -- CONTATO: arqueado por cima da bola, baixo, tombando pro lado do apoio
				Root = V(-18, -5, 8), Waist = V(-12, -9, 0), Neck = V(-26, 0, 0),
				LShoulder = V(-5, 0, -75), RShoulder = V(25, 0, 35), LElbow = V(25, 0, 0), RElbow = V(20, 0, 0),
				RHip = V(95 + 25 * c, 0, 0), RKnee = V(-12, 0, 0), RAnkle = V(-25, 0, 0),
				LHip = V(23, 0, -4), LKnee = V(-36, 0, 0), LAnkle = V(10, 0, 0), -- (v122: era 28)
				RootPos = V(0, -0.38, 0),
			} },
			{ 0.42, {
				Root = V(-8, -2, 2), Waist = V(-4, -3, 0), Neck = V(-6, 0, 0),
				LShoulder = V(5, 0, -25), RShoulder = V(5, 0, 15), LElbow = V(15, 0, 0), RElbow = V(15, 0, 0),
				RHip = V(25, 0, 0), RKnee = V(-35, 0, 0), RAnkle = V(-5, 0, 0),
				LHip = V(9, 0, -4), LKnee = V(-10, 0, 0), LAnkle = V(0, 0, 0), -- (v122: era 5)
			} },
			{ 0.52, neutro() },
		}
	end,
}

-- ----- CABEÇADA -----
Anim.Acoes.Header = {
	Duracao = 0.55, EntradaSeg = 0.05, SaidaSeg = 0.15,
	Quadros = function()
		return {
			{ 0.00, neutro() },
			{ 0.12, { -- arqueia pra trás, braços abertos
				Root = V(12, 0, 0), Waist = V(14, 0, 0), Neck = V(22, 0, 0),
				RShoulder = V(25, 0, 55), LShoulder = V(25, 0, -55), RElbow = V(50, 0, 0), LElbow = V(50, 0, 0),
				RHip = V(15, 0, 4), LHip = V(15, 0, -4), RKnee = V(-25, 0, 0), LKnee = V(-25, 0, 0),
			} },
			{ 0.24, { -- golpe: tronco e pescoço vêm à frente, testa na bola
				Root = V(-14, 0, 0), Waist = V(-18, 0, 0), Neck = V(-30, 0, 0),
				RShoulder = V(-25, 0, 40), LShoulder = V(-25, 0, -40), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
				RHip = V(5, 0, 4), LHip = V(5, 0, -4), RKnee = V(-10, 0, 0), LKnee = V(-10, 0, 0),
			} },
			{ 0.40, {
				Root = V(-6, 0, 0), Waist = V(-6, 0, 0), Neck = V(-12, 0, 0),
				RShoulder = V(0, 0, 20), LShoulder = V(0, 0, -20), RElbow = V(20, 0, 0), LElbow = V(20, 0, 0),
			} },
			{ 0.55, neutro() },
		}
	end,
}

-- ----- CARRINHO -----
-- (medido no avatar: com o tronco deitado 62° pra trás, a coxa rente ao chão
-- é ~28° de flexão em relação ao tronco — 90° do chão menos os 62° do tronco.
-- A primeira versão somava 85 e a perna ia pro alto.)
-- ⚠️ v103 — PEDIDO: "o carrinho, o cara tem que cair 100% no chão, não está
-- caindo 100% no chão. E ele está levantando de um jeito meio estranho."
-- Mais deitado (72°) e o quadril mais baixo de propósito: a correção de chão
-- do animador (só SOBE) encosta a parte mais baixa exatamente no gramado —
-- ele fica deitado DE VERDADE, seja qual for a altura do avatar.
-- (medido no avatar, 1ª versão: com a perna de trás dobrada POR BAIXO, era o
-- joelho dela que encostava no gramado e o quadril ficava 1.6 acima do chão
-- — "sentado". Agora o tronco deita 80° e a perna de baixo ABRE pro lado,
-- deitada no gramado, como num carrinho de verdade.)
local POSE_CARRINHO = {
	Root = V(80, 0, 10), Waist = V(-6, 0, 0), Neck = V(-42, 0, 0),
	RHip = V(8, 0, 4), RKnee = V(-4, 0, 0), RAnkle = V(20, 0, 0),      -- perna da frente esticada rente ao chão, ponta pra cima
	LHip = V(16, 0, -16), LKnee = V(-35, 0, 0), LAnkle = V(0, 0, 0),   -- a de baixo à frente, meio dobrada, deslizando (2ª medição: aberta pro lado, o PÉ ainda segurava o quadril a 1.4)
	LShoulder = V(-25, 0, -80), LElbow = V(55, 0, 0),                  -- braço de apoio aberto ao lado (3ª medição: a mão esticada pra trás segurava o quadril a 1.1)
	RShoulder = V(30, 0, 70), RElbow = V(30, 0, 0),
	RootPos = V(0, -2.8, 0.6),
}
-- levantando: senta apoiando a mão esquerda no chão, recolhe as pernas
local CARRINHO_SENTA = {
	Root = V(38, 0, 8), Waist = V(-6, 0, 0), Neck = V(-12, 0, 0),
	RHip = V(70, 0, 6), RKnee = V(-100, 0, 0), RAnkle = V(10, 0, 0),
	LHip = V(55, 0, -6), LKnee = V(-115, 0, 0), LAnkle = V(10, 0, 0),
	LShoulder = V(-45, 0, -45), LElbow = V(5, 0, 0), RShoulder = V(40, 0, 30), RElbow = V(40, 0, 0),
	RootPos = V(0, -1.7, 0.2),
}
local CARRINHO_AGACHA = {
	Root = V(-14, 0, 0), Neck = V(8, 0, 0),
	RHip = V(80, 0, 8), LHip = V(75, 0, -8), RKnee = V(-110, 0, 0), LKnee = V(-110, 0, 0),
	RAnkle = V(20, 0, 0), LAnkle = V(20, 0, 0),
	RShoulder = V(25, 0, 20), LShoulder = V(25, 0, -20), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
	RootPos = V(0, -1.0, 0),
}
-- ⚠️ v103 — PEDIDO: "depois que termina a animação de carrinho o boneco já
-- levanta instantaneamente, e depois volta pra animação deitado e levanta de
-- novo". O servidor manda o carrinho com a duração do LANCE (0.5s) e, se
-- errou, manda a queda (TackleMiss, que começa DEITADO) exatamente no fim
-- dele — e o carrinho já tinha levantado dentro desses 0.5s. Agora: o carrinho
-- fica DEITADO até o fim do lance (FimDaMecanica = 0.50 do relógio dele) e só
-- DEPOIS levanta devagar (senta, agacha, em pé). Errou: a queda chega com ele
-- ainda deitado e continua de onde está (EntradaSeg 0, mesma pose). Acertou:
-- ele levanta com calma no tempo extra.
Anim.Acoes.Tackle = {
	Duracao = 0.85, FimDaMecanica = 0.50, EntradaSeg = 0.03, SaidaSeg = 0.1,
	Quadros = function()
		return {
			{ 0.00, neutro() },
			{ 0.07, {
				Root = V(35, 0, 5), Neck = V(-15, 0, 0),
				RHip = V(45, 0, 4), RKnee = V(-20, 0, 0), LHip = V(0, 0, -8), LKnee = V(-90, 0, 0),
				LShoulder = V(-30, 0, -45), RShoulder = V(20, 0, 60),
				RootPos = V(0, -0.9, 0.1),
			} },
			{ 0.12, POSE_CARRINHO },
			-- deitado até o fim do lance + 0.1s de folga (medido: a queda chega
			-- uns centésimos DEPOIS do fim do lance, pela rede — sem a folga ele
			-- já tinha começado a sentar e dava um pulinho)
			{ 0.60, POSE_CARRINHO },
			{ 0.70, CARRINHO_SENTA },
			{ 0.78, CARRINHO_AGACHA },
			{ 0.85, neutro() },
		}
	end,
}

-- ----- LEVANTAR RÁPIDO DO CARRINHO — ⚠️ v111 -----
-- PEDIDO: "faça o carrinho levantar um pouco mais rápido quando você pega a
-- bola". Quando o carrinho ganha a bola, o animador troca o resto do Tackle
-- (deitado até 0.60s + levantar) por este levantar curto (0.3s).
Anim.Acoes.TackleLevanta = {
	Duracao = 0.3, EntradaSeg = 0.02, SaidaSeg = 0.08,
	Quadros = function()
		return {
			{ 0.00, POSE_CARRINHO },
			{ 0.12, CARRINHO_SENTA },
			{ 0.22, CARRINHO_AGACHA },
			{ 0.30, neutro() },
		}
	end,
}

-- ----- SOFREU CARRINHO — ⚠️ v106 -----
-- PEDIDO: "quando o cara sofrer carrinho, coloca uma animação dele caindo no
-- chão". As pernas são varridas, os braços sobem (desequilíbrio), cai de
-- COSTAS, fica no chão o tempo do atordoamento (Config.TACKLE_VICTIM_STUN) e
-- levanta pelo mesmo caminho do carrinho (senta, agacha, em pé).
local CAIDO_COSTAS = {
	Root = V(85, 0, -8), Waist = V(4, 0, 0), Neck = V(-25, 0, 0),
	RShoulder = V(30, 0, 75), LShoulder = V(10, 0, -80), RElbow = V(20, 0, 0), LElbow = V(35, 0, 0),
	RHip = V(25, 0, 8), LHip = V(15, 0, -8), RKnee = V(-20, 0, 0), LKnee = V(-35, 0, 0),
	RootPos = V(0, -2.75, 0.9),
}
Anim.Acoes.SofreuCarrinho = {
	Duracao = 1.25, EntradaSeg = 0.02, SaidaSeg = 0.15, Suave = true,
	Quadros = function()
		return {
			{ 0.00, neutro() },
			{ 0.10, { -- pernas varridas, braços pra cima
				Root = V(35, 0, -10), Neck = V(10, 0, 0),
				RHip = V(60, 0, 10), LHip = V(45, 0, -6), RKnee = V(-10, 0, 0), LKnee = V(-20, 0, 0),
				RShoulder = V(140, 0, 40), LShoulder = V(120, 0, -40), RElbow = V(20, 0, 0), LElbow = V(20, 0, 0),
				RootPos = V(0, -0.8, 0.2),
			} },
			{ 0.28, CAIDO_COSTAS },
			{ 0.75, CAIDO_COSTAS },
			{ 0.95, CARRINHO_SENTA },
			{ 1.10, CARRINHO_AGACHA },
			{ 1.25, neutro() },
		}
	end,
}

-- ----- QUEDA DEPOIS DE ERRAR O CARRINHO: deitado, depois levanta -----
Anim.Acoes.TackleMiss = {
	Duracao = 1.0, EntradaSeg = 0, SaidaSeg = 0.18, -- v103: entra sem blend (continua o carrinho deitado)
	Quadros = function()
		-- deitado de costas: tronco a 80° pra trás, então pernas "no chão" =
		-- quase na linha do tronco (flexão pequena), joelhos meio dobrados
		local deitado = {
			Root = V(80, 0, 0), Neck = V(-20, 0, 0),
			RHip = V(12, 0, 8), LHip = V(28, 0, -8), RKnee = V(-20, 0, 0), LKnee = V(-50, 0, 0),
			RShoulder = V(-10, 0, 80), LShoulder = V(-10, 0, -80), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0),
			RootPos = V(0, -1.75, 0.6),
		}
		return {
			-- ⚠️ v103: continua NA POSE DO CARRINHO (ele já está no chão) —
			-- misturar com uma pose "deitado" diferente subia o quadril no meio
			-- (medido: 0.97 -> 1.48 -> 1.00, o "levanta e deita de novo")
			{ 0.00, POSE_CARRINHO },
			{ 0.45, POSE_CARRINHO },
			{ 0.58, { -- ⚠️ v103: vira de lado e apoia a mão (levantar natural)
				Root = V(60, 0, -30), Neck = V(-10, 0, -10),
				RHip = V(45, 0, 10), LHip = V(70, 0, -6), RKnee = V(-60, 0, 0), LKnee = V(-100, 0, 0),
				RShoulder = V(-40, 0, 40), RElbow = V(10, 0, 0), LShoulder = V(20, 0, -30), LElbow = V(40, 0, 0),
				RootPos = V(0, -1.65, 0.4),
			} },
			{ 0.72, { -- senta no chão, joelhos pra cima (coxa ~30° acima do chão = 80° do tronco inclinado 40°)
				Root = V(40, 0, 0), Neck = V(-10, 0, 0),
				RHip = V(80, 0, 6), LHip = V(80, 0, -6), RKnee = V(-110, 0, 0), LKnee = V(-110, 0, 0),
				RShoulder = V(40, 0, 20), LShoulder = V(40, 0, -20), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
				RootPos = V(0, -1.45, 0.3),
			} },
			{ 0.88, { -- agachado
				Root = V(-12, 0, 0),
				RHip = V(75, 0, 6), LHip = V(75, 0, -6), RKnee = V(-110, 0, 0), LKnee = V(-110, 0, 0),
				RShoulder = V(20, 0, 15), LShoulder = V(20, 0, -15),
				RAnkle = V(20, 0, 0), LAnkle = V(20, 0, 0),
				RootPos = V(0, -0.95, 0),
			} },
			{ 1.00, neutro() },
		}
	end,
}

-- ----- DRIBLES (janela Config.DRIBBLE_ANIMATION_SECONDS) -----
-- Direita: finge pra esquerda (tomba o peso), empurra com a esquerda e sai
-- de lado com a direita levando a bola; braços abertos pro equilíbrio.
local DRIBLE_DIREITA = {
	{ 0.00, neutro() },
	{ 0.12, {
		Root = V(-4, 0, 10), Neck = V(-10, 0, 0),
		RHip = V(20, 0, 12), RKnee = V(-35, 0, 0), LHip = V(0, 0, -10), LKnee = V(-30, 0, 0),
		LShoulder = V(10, 0, -40), RShoulder = V(10, 0, 30), LElbow = V(30, 0, 0), RElbow = V(30, 0, 0),
		RootPos = V(0, -0.05, 0),
	} },
	{ 0.28, {
		Root = V(-6, -10, -18), Waist = V(0, 0, -6), Neck = V(-8, 0, 5),
		RHip = V(10, 0, 28), RKnee = V(-20, 0, 0), RAnkle = V(0, 0, 0),
		LHip = V(-10, 0, -8), LKnee = V(-45, 0, 0), LAnkle = V(-20, 0, 0),
		LShoulder = V(15, 0, -60), RShoulder = V(-10, 0, 45), LElbow = V(35, 0, 0), RElbow = V(30, 0, 0),
		RootPos = V(0, -0.05, 0), -- (medido: -0.25 afundava o pé de apoio)
	} },
	{ 0.45, {
		Root = V(-4, -4, -6),
		RHip = V(10, 0, 10), RKnee = V(-20, 0, 0), LHip = V(5, 0, -5), LKnee = V(-20, 0, 0),
		LShoulder = V(5, 0, -30), RShoulder = V(0, 0, 25), LElbow = V(25, 0, 0), RElbow = V(25, 0, 0),
	} },
	{ 0.583, neutro() },
}
-- Trás: sola por cima da bola e puxa ("drag-back"), inclinando pra trás.
local DRIBLE_TRAS = {
	{ 0.00, neutro() },
	{ 0.10, {
		Root = V(8, 0, 0), Neck = V(-12, 0, 0),
		RHip = V(35, 0, 4), RKnee = V(-30, 0, 0), RAnkle = V(20, 0, 0),
		LKnee = V(-20, 0, 0),
		RShoulder = V(10, 0, 35), LShoulder = V(10, 0, -35), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
	} },
	{ 0.26, {
		Root = V(14, 0, 0), Neck = V(-10, 0, 0),
		RHip = V(-15, 0, 4), RKnee = V(-55, 0, 0), RAnkle = V(10, 0, 0),
		LHip = V(10, 0, -4), LKnee = V(-30, 0, 0),
		RShoulder = V(10, 0, 45), LShoulder = V(10, 0, -45), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
		RootPos = V(0, -0.15, 0),
	} },
	{ 0.42, {
		Root = V(4, 0, 0),
		RHip = V(5, 0, 2), RKnee = V(-30, 0, 0), LHip = V(-10, 0, -2), LKnee = V(-35, 0, 0),
		RShoulder = V(0, 0, 25), LShoulder = V(0, 0, -25),
	} },
	{ 0.583, neutro() },
}
-- Frente: toque de ponta pra frente e arrancada (joelho alto, braços de corrida).
local DRIBLE_FRENTE = {
	{ 0.00, neutro() },
	{ 0.10, {
		Root = V(-12, 0, 0), Neck = V(0, 0, 0),
		RHip = V(45, 0, 2), RKnee = V(-45, 0, 0), RAnkle = V(-20, 0, 0),
		LShoulder = V(40, 0, -10), RShoulder = V(-30, 0, 10), LElbow = V(80, 0, 0), RElbow = V(80, 0, 0),
	} },
	{ 0.28, {
		Root = V(-18, 0, 0), Neck = V(10, 0, 0),
		LHip = V(60, 0, -2), LKnee = V(-95, 0, 0), RHip = V(-25, 0, 2), RKnee = V(-30, 0, 0), RAnkle = V(-25, 0, 0),
		LShoulder = V(-45, 0, -10), RShoulder = V(50, 0, 10), LElbow = V(90, 0, 0), RElbow = V(90, 0, 0),
		RootPos = V(0, -0.1, 0),
	} },
	{ 0.45, {
		Root = V(-10, 0, 0),
		LHip = V(20, 0, -2), LKnee = V(-30, 0, 0), RHip = V(10, 0, 2), RKnee = V(-25, 0, 0),
		LShoulder = V(-10, 0, -8), RShoulder = V(15, 0, 8), LElbow = V(60, 0, 0), RElbow = V(60, 0, 0),
	} },
	{ 0.583, neutro() },
}
-- Domínio (recebeu a bola): amortece com a parte de dentro do pé.
local DOMINIO = {
	{ 0.00, neutro() },
	{ 0.12, {
		Root = V(-6, 0, 0), Neck = V(-18, 0, 0),
		RHip = V(30, -25, 10), RKnee = V(-30, 0, 0), RAnkle = V(5, 0, 0),
		LKnee = V(-25, 0, 0), RShoulder = V(5, 0, 25), LShoulder = V(5, 0, -25),
		RootPos = V(0, -0.15, 0),
	} },
	{ 0.30, {
		Root = V(-3, 0, 0), Neck = V(-12, 0, 0),
		RHip = V(5, -10, 4), RKnee = V(-20, 0, 0), LKnee = V(-15, 0, 0),
	} },
	{ 0.45, neutro() },
}

-- ⚠️ v103 — PEDIDO: "a de drible tá horrível... é muito simples: ROLAMENTO.
-- Rolamento pra esquerda, pra direita, com o mesmo pé ou com o pé contrário...
-- pra frente ou pra trás. E se o cara fizer diagonalmente, faz uma diagonal."
-- Rolamento = a SOLA sobe em cima da bola e rola ela pro lado; o corpo
-- acompanha com um passo. Pra direita rola com a sola DIREITA (o pé do lado —
-- é o mais natural e o que dá pra ver da câmera); pra esquerda é o espelho
-- (sola esquerda). Frente: sola empurra pra frente e o passo sai atrás dela.
-- Trás: puxada de sola (drag-back). Diagonal = mistura quadro a quadro das
-- duas (todas as listas têm os MESMOS tempos pra poder misturar).
local SOLA_EM_CIMA = {
	Root = V(-4, 0, 4), Neck = V(-20, 0, 0),
	RHip = V(38, 0, 6), RKnee = V(-62, 0, 0), RAnkle = V(8, 0, 0),
	LHip = V(6, 0, -4), LKnee = V(-18, 0, 0),
	RShoulder = V(10, 0, 35), LShoulder = V(10, 0, -40), RElbow = V(25, 0, 0), LElbow = V(25, 0, 0),
}
local ROLAMENTO_DIREITA = {
	{ 0.00, neutro() },
	{ 0.10, SOLA_EM_CIMA },
	{ 0.24, { -- a sola rola a bola pro lado
		Root = V(-4, -6, 8), Neck = V(-16, 0, 0),
		RHip = V(22, 0, 34), RKnee = V(-45, 0, 0), RAnkle = V(5, 0, 0),
		LHip = V(10, 0, -6), LKnee = V(-26, 0, 0),
		RShoulder = V(0, 0, 45), LShoulder = V(15, 0, -58), RElbow = V(25, 0, 0), LElbow = V(30, 0, 0),
		RootPos = V(0, -0.08, 0),
	} },
	{ 0.38, { -- passo lateral acompanhando a bola (o peso passa pra direita)
		Root = V(-4, -4, -6), Neck = V(-10, 0, 0),
		RHip = V(8, 0, 18), RKnee = V(-20, 0, 0),
		LHip = V(12, 0, -14), LKnee = V(-30, 0, 0), LAnkle = V(-10, 0, 0),
		RShoulder = V(5, 0, 35), LShoulder = V(10, 0, -40), RElbow = V(25, 0, 0), LElbow = V(25, 0, 0),
		RootPos = V(0, -0.05, 0),
	} },
	{ 0.50, {
		Root = V(-3, 0, -2),
		RHip = V(5, 0, 6), LHip = V(5, 0, -6), RKnee = V(-12, 0, 0), LKnee = V(-12, 0, 0),
		RShoulder = V(0, 0, 20), LShoulder = V(0, 0, -20), RElbow = V(20, 0, 0), LElbow = V(20, 0, 0),
	} },
	{ 0.583, neutro() },
}
local ROLAMENTO_FRENTE = {
	{ 0.00, neutro() },
	{ 0.10, SOLA_EM_CIMA },
	{ 0.24, { -- a sola empurra a bola pra frente
		Root = V(-8, 0, 0), Neck = V(-14, 0, 0),
		RHip = V(50, 0, 2), RKnee = V(-25, 0, 0), RAnkle = V(5, 0, 0),
		LHip = V(8, 0, -4), LKnee = V(-25, 0, 0),
		RShoulder = V(-10, 0, 30), LShoulder = V(20, 0, -30), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
		RootPos = V(0, -0.06, 0),
	} },
	{ 0.38, { -- passo atrás dela
		Root = V(-10, 0, 0), Neck = V(-4, 0, 0),
		RHip = V(25, 0, 2), RKnee = V(-15, 0, 0),
		LHip = V(-15, 0, -2), LKnee = V(-40, 0, 0), LAnkle = V(-20, 0, 0),
		RShoulder = V(-25, 0, 10), LShoulder = V(30, 0, -10), RElbow = V(70, 0, 0), LElbow = V(70, 0, 0),
		RootPos = V(0, -0.05, 0),
	} },
	{ 0.50, {
		Root = V(-6, 0, 0),
		RHip = V(10, 0, 2), LHip = V(5, 0, -2), RKnee = V(-15, 0, 0), LKnee = V(-18, 0, 0),
		RShoulder = V(-5, 0, 15), LShoulder = V(10, 0, -15), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
	} },
	{ 0.583, neutro() },
}
local ROLAMENTO_TRAS = {
	{ 0.00, neutro() },
	{ 0.10, SOLA_EM_CIMA },
	{ 0.24, { -- puxa de sola (drag-back), inclinando pra trás
		Root = V(12, 0, 0), Neck = V(-12, 0, 0),
		RHip = V(-15, 0, 4), RKnee = V(-60, 0, 0), RAnkle = V(10, 0, 0),
		LHip = V(12, 0, -4), LKnee = V(-30, 0, 0),
		RShoulder = V(10, 0, 45), LShoulder = V(10, 0, -45), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
		RootPos = V(0, -0.12, 0),
	} },
	{ 0.38, { -- recua um passo com a bola
		Root = V(6, 0, 0), Neck = V(-8, 0, 0),
		RHip = V(-5, 0, 2), RKnee = V(-30, 0, 0),
		LHip = V(-12, 0, -2), LKnee = V(-35, 0, 0),
		RShoulder = V(5, 0, 30), LShoulder = V(5, 0, -30), RElbow = V(25, 0, 0), LElbow = V(25, 0, 0),
		RootPos = V(0, -0.06, 0),
	} },
	{ 0.50, {
		Root = V(3, 0, 0),
		RHip = V(3, 0, 2), LHip = V(0, 0, -2), RKnee = V(-15, 0, 0), LKnee = V(-18, 0, 0),
		RShoulder = V(0, 0, 20), LShoulder = V(0, 0, -20),
	} },
	{ 0.583, neutro() },
}
-- mistura quadro a quadro duas listas com os mesmos tempos (diagonal)
local function misturarQuadros(a, b, t)
	local out = {}
	for i, q in ipairs(a) do out[i] = { q[1], Anim.Blend(q[2], b[i][2], t) } end
	return out
end

local function acaoDeQuadros(duracao, quadros)
	return { Duracao = duracao, EntradaSeg = 0.04, SaidaSeg = 0.12, Quadros = function() return quadros end }
end
local ROLAMENTO_ESQUERDA = espelharQuadros(ROLAMENTO_DIREITA)
Anim.Acoes["Dribble.Right"] = acaoDeQuadros(0.583, ROLAMENTO_DIREITA)
Anim.Acoes["Dribble.Left"] = acaoDeQuadros(0.583, ROLAMENTO_ESQUERDA)
Anim.Acoes["Dribble.Back"] = acaoDeQuadros(0.583, ROLAMENTO_TRAS)
Anim.Acoes["Dribble.Forward"] = acaoDeQuadros(0.583, ROLAMENTO_FRENTE)
Anim.Acoes["Dribble.ForwardRight"] = acaoDeQuadros(0.583, misturarQuadros(ROLAMENTO_FRENTE, ROLAMENTO_DIREITA, 0.5))
Anim.Acoes["Dribble.ForwardLeft"] = acaoDeQuadros(0.583, espelharQuadros(misturarQuadros(ROLAMENTO_FRENTE, ROLAMENTO_DIREITA, 0.5)))
Anim.Acoes["Dribble.BackRight"] = acaoDeQuadros(0.583, misturarQuadros(ROLAMENTO_TRAS, ROLAMENTO_DIREITA, 0.5))
Anim.Acoes["Dribble.BackLeft"] = acaoDeQuadros(0.583, espelharQuadros(misturarQuadros(ROLAMENTO_TRAS, ROLAMENTO_DIREITA, 0.5)))
-- (as fintas antigas continuam aqui como referência: DRIBLE_DIREITA/TRAS/FRENTE)
local _ = DRIBLE_DIREITA, DRIBLE_TRAS, DRIBLE_FRENTE
Anim.Acoes.Dominio = acaoDeQuadros(0.45, DOMINIO)

-- ----- MERGULHOS DO GOLEIRO -----
-- Direita: carrega, impulso com a perna ESQUERDA (contrária ao lado) e passo
-- lateral com a direita, sai a ~45°, fica esticado na horizontal com os
-- braços na bola, cai de lado trazendo a bola pro peito e levanta.
local MERGULHO_DIREITA = {
	{ 0.00, Anim.GoleiroPronto(0) },
	{ 0.08, {
		Root = V(-15, 0, -10), Neck = V(20, 0, -8),
		RHip = V(45, 0, 20), RKnee = V(-70, 0, 0), LHip = V(45, 0, -10), LKnee = V(-70, 0, 0),
		RAnkle = V(20, 0, 0), LAnkle = V(20, 0, 0),
		RShoulder = V(30, 0, 40), LShoulder = V(30, 0, -20), RElbow = V(50, 0, 0), LElbow = V(50, 0, 0),
		RootPos = V(0, -0.6, 0),
	} },
	-- ⚠️ v103 — PEDIDO: "o dive, você não tá tombando direito e dando aquele
	-- jump... quando eu faço o dive pros lados a minha mão fica pra trás... a
	-- mão tem que estar reta, aonde ele vai pegar a bola." Tomba mais cedo e
	-- mais rápido, SOBE num arco (RootPos) e os braços já vão esticados na
	-- linha do corpo, apontando pra bola, desde o impulso — sem pulso dobrado.
	{ 0.16, {
		Root = V(-5, 0, -60), Neck = V(10, 0, -14),
		LHip = V(-12, 0, -10), LKnee = V(-8, 0, 0), LAnkle = V(-32, 0, 0), -- empurra
		RHip = V(30, 0, 25), RKnee = V(-40, 0, 0),
		-- ⚠️ v120b — PEDIDO: "o dive precisa ter as mãos um pouco mais separadas,
		-- tão muito juntas": um braço um pouco à frente e o outro um pouco atrás
		RShoulder = V(28, 0, 160), LShoulder = V(-18, 0, -148), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
		RootPos = V(0, 0.4, 0),
	} },
	{ 0.28, {
		Root = V(-4, 0, -88), Neck = V(4, 0, -15),
		RHip = V(8, 0, 8), LHip = V(6, 0, -8), RKnee = V(-8, 0, 0), LKnee = V(-6, 0, 0),
		RAnkle = V(-25, 0, 0), LAnkle = V(-25, 0, 0),
		RShoulder = V(30, 0, 162), LShoulder = V(-20, 0, -150), RElbow = V(0, 0, 0), LElbow = V(0, 0, 0),
		RootPos = V(0, 0.9, 0),
	} },
	{ 0.42, {
		Root = V(-4, 0, -90), Neck = V(2, 0, -15),
		RHip = V(10, 0, 8), LHip = V(8, 0, -8), RKnee = V(-10, 0, 0), LKnee = V(-8, 0, 0),
		RShoulder = V(30, 0, 162), LShoulder = V(-18, 0, -150), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
		RootPos = V(0, 0.7, 0),
	} },
	{ 0.58, {
		Root = V(-4, 0, -88), Neck = V(0, 0, -15),
		RHip = V(15, 0, 8), LHip = V(12, 0, -8), RKnee = V(-20, 0, 0), LKnee = V(-15, 0, 0),
		RShoulder = V(25, 0, 150), LShoulder = V(25, 0, -150), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
		RootPos = V(0, -0.6, 0),
	} },
	{ 0.72, { -- no chão, de lado, bola no peito
		Root = V(0, 0, -90), Neck = V(0, 0, -10),
		RHip = V(45, 0, 5), LHip = V(35, 0, -5), RKnee = V(-50, 0, 0), LKnee = V(-40, 0, 0),
		RShoulder = V(60, 0, 40), LShoulder = V(60, 0, -40), RElbow = V(95, 0, 0), LElbow = V(95, 0, 0),
		-- ⚠️ v120b — PEDIDO: "no final da animação cai no chão e levanta" (parecia
		-- flutuar: o quadril do R6 fica mais alto que o do R15). Desce de vez; a
		-- correção de chão do animador sobe o que passar do gramado.
		RootPos = V(0, -2.3, 0),
	} },
	-- ⚠️ v122 — PEDIDO: "o dive pro lado levanta mais devagar". Fica mais no chão,
	-- apoia a mão, ajoelha e só então levanta (era 0.80 / 0.88 / 1.00).
	{ 1.10, { -- fica no chão
		Root = V(0, 0, -90), Neck = V(0, 0, -10),
		RHip = V(45, 0, 5), LHip = V(35, 0, -5),
		RShoulder = V(60, 0, 40), LShoulder = V(60, 0, -40),
		RootPos = V(0, -2.3, 0),
	} },
	{ 1.24, { -- apoia a mão e ergue o tronco
		Root = V(0, 0, -55), Neck = V(0, 0, -15),
		RHip = V(60, 0, 8), LHip = V(50, 0, -8), RKnee = V(-80, 0, 0), LKnee = V(-70, 0, 0),
		RShoulder = V(20, 0, 50), LShoulder = V(40, 0, -30), RElbow = V(20, 0, 0), LElbow = V(60, 0, 0),
		RootPos = V(0, -1.7, 0),
	} },
	{ 1.38, { -- ajoelha e levanta
		Root = V(-10, 0, -20),
		RHip = V(75, 0, 8), LHip = V(70, 0, -8), RKnee = V(-105, 0, 0), LKnee = V(-100, 0, 0),
		RShoulder = V(25, 0, 20), LShoulder = V(25, 0, -20), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
		RootPos = V(0, -1.0, 0),
	} },
	{ 1.55, Anim.GoleiroPronto(0) },
}
-- Pra cima: pulo com os dois pés, esticado, braços por cima da cabeça.
-- ⚠️ v103 — PEDIDO: "pra cima tá ótimo [a distância], só que a animação do
-- dive pra cima também tem que melhorar". Agora: agachada funda com os braços
-- atrás (carrega), EXPLODE esticando o corpo todo e sobe num arco, com um
-- joelho alto (proteção, como goleiro de verdade pegando bola alta) e os dois
-- braços retos por cima da cabeça; pega e traz a bola pro peito na descida.
local MERGULHO_CIMA = {
	{ 0.00, Anim.GoleiroPronto(0) },
	{ 0.10, {
		Root = V(-24, 0, 0), Neck = V(30, 0, 0),
		RHip = V(65, 0, 12), LHip = V(65, 0, -12), RKnee = V(-95, 0, 0), LKnee = V(-95, 0, 0),
		RAnkle = V(25, 0, 0), LAnkle = V(25, 0, 0),
		RShoulder = V(-45, 0, 25), LShoulder = V(-45, 0, -25), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
		RootPos = V(0, -0.85, 0),
	} },
	{ 0.24, {
		Root = V(8, 0, 0), Waist = V(6, 0, 0), Neck = V(38, 0, 0),
		RHip = V(-4, 0, 6), RKnee = V(-6, 0, 0), RAnkle = V(-35, 0, 0),
		LHip = V(55, 0, -6), LKnee = V(-85, 0, 0), LAnkle = V(-20, 0, 0), -- joelho alto
		RShoulder = V(4, 0, 176), LShoulder = V(4, 0, -176), RElbow = V(0, 0, 0), LElbow = V(0, 0, 0),
		RootPos = V(0, 0.7, 0),
	} },
	{ 0.42, {
		Root = V(6, 0, 0), Waist = V(4, 0, 0), Neck = V(34, 0, 0),
		RHip = V(0, 0, 6), RKnee = V(-10, 0, 0), RAnkle = V(-30, 0, 0),
		LHip = V(60, 0, -6), LKnee = V(-90, 0, 0),
		RShoulder = V(8, 0, 172), LShoulder = V(8, 0, -172), RElbow = V(8, 0, 0), LElbow = V(8, 0, 0),
		RootPos = V(0, 0.8, 0),
	} },
	{ 0.58, { -- pegou: traz a bola pro peito
		Root = V(0, 0, 0), Neck = V(15, 0, 0),
		RHip = V(20, 0, 6), LHip = V(40, 0, -6), RKnee = V(-30, 0, 0), LKnee = V(-60, 0, 0),
		RShoulder = V(70, 0, 30), LShoulder = V(70, 0, -30), RElbow = V(95, 0, 0), LElbow = V(95, 0, 0),
		RootPos = V(0, 0.3, 0),
	} },
	{ 0.80, {
		Root = V(-15, 0, 0), Neck = V(20, 0, 0),
		RHip = V(50, 0, 12), LHip = V(50, 0, -12), RKnee = V(-75, 0, 0), LKnee = V(-75, 0, 0),
		RAnkle = V(20, 0, 0), LAnkle = V(20, 0, 0),
		RShoulder = V(50, 0, 30), LShoulder = V(50, 0, -30), RElbow = V(60, 0, 0), LElbow = V(60, 0, 0),
		RootPos = V(0, -0.6, 0),
	} },
	{ 1.00, Anim.GoleiroPronto(0) },
}
-- Diagonal pra cima-direita: meio caminho entre o pulo e o mergulho de lado.
local MERGULHO_CIMA_DIREITA = {
	{ 0.00, Anim.GoleiroPronto(0) },
	{ 0.10, {
		Root = V(-15, 0, -8), Neck = V(22, 0, -5),
		RHip = V(50, 0, 18), LHip = V(50, 0, -10), RKnee = V(-75, 0, 0), LKnee = V(-75, 0, 0),
		RAnkle = V(20, 0, 0), LAnkle = V(20, 0, 0),
		RShoulder = V(10, 0, 40), LShoulder = V(10, 0, -25), RElbow = V(45, 0, 0), LElbow = V(45, 0, 0),
		RootPos = V(0, -0.65, 0),
	} },
	{ 0.26, {
		Root = V(0, 0, -42), Neck = V(25, 0, -12),
		LHip = V(-8, 0, -8), LKnee = V(-8, 0, 0), LAnkle = V(-30, 0, 0),
		RHip = V(35, 0, 20), RKnee = V(-50, 0, 0),
		RShoulder = V(10, 0, 172), LShoulder = V(10, 0, -168), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
	} },
	{ 0.55, {
		Root = V(0, 0, -50), Neck = V(20, 0, -12),
		RHip = V(30, 0, 15), LHip = V(10, 0, -8), RKnee = V(-40, 0, 0), LKnee = V(-15, 0, 0),
		RShoulder = V(15, 0, 168), LShoulder = V(15, 0, -165),
	} },
	{ 0.80, {
		Root = V(-12, 0, -15),
		RHip = V(50, 0, 12), LHip = V(50, 0, -12), RKnee = V(-75, 0, 0), LKnee = V(-75, 0, 0),
		RShoulder = V(45, 0, 30), LShoulder = V(45, 0, -30), RElbow = V(60, 0, 0), LElbow = V(60, 0, 0),
		RootPos = V(0, -0.6, 0),
	} },
	{ 1.00, Anim.GoleiroPronto(0) },
}
local function acaoMergulho(quadros, duracao)
	return { Duracao = duracao or 1.1, EntradaSeg = 0.05, SaidaSeg = 0.2, Suave = true, Quadros = function() return quadros end }
end
Anim.Acoes["GKDive.Right"] = acaoMergulho(MERGULHO_DIREITA, 1.6)
Anim.Acoes["GKDive.Left"] = acaoMergulho(espelharQuadros(MERGULHO_DIREITA), 1.6)
Anim.Acoes["GKDive.Up"] = acaoMergulho(MERGULHO_CIMA)
Anim.Acoes["GKDive.UpRight"] = acaoMergulho(MERGULHO_CIMA_DIREITA)
Anim.Acoes["GKDive.UpLeft"] = acaoMergulho(espelharQuadros(MERGULHO_CIMA_DIREITA))

-- ----- GOLEIRO COM A BOLA NA MÃO — ⚠️ v105 -----
-- PEDIDO: "coloca pra bola ficar na mão do GK (normal e bot)... e a animação
-- de arremessar". SEGURAR é uma pose só dos braços (o AnimadorProcedural
-- mistura por cima da locomoção enquanto o personagem tem o atributo
-- BolaNaMao): os dois braços pra frente, na altura do peito, abraçando a bola.
Anim.POSE_SEGURAR = {
	RShoulder = V(78, 0, -14), LShoulder = V(78, 0, 14),
	RElbow = V(58, 0, 0), LElbow = V(58, 0, 0),
	RWrist = V(10, 0, 0), LWrist = V(10, 0, 0),
	Neck = V(-6, 0, 0),
}
Anim.MASCARA_BRACOS = {
	RShoulder = 1, LShoulder = 1, RElbow = 1, LElbow = 1, RWrist = 1, LWrist = 1, Neck = 0.5,
}
-- ARREMESSO — v110 — PEDIDO: "ele joga de um jeito estranho, não é assim que se
-- joga a bola no futebol: pega a bola com UMA mão, se curva e joga". Era um
-- arremesso com as duas mãos por cima da cabeça (de lateral). Agora é o de
-- goleiro de verdade: a bola vai pra mão direita, o braço vai pra trás, o
-- esquerdo aponta o alvo, passo com a esquerda, o corpo SE CURVA pra frente e o
-- braço passa por cima soltando a bola lá na frente.
Anim.Acoes.Arremesso = {
	Duracao = 0.75, EntradaSeg = 0.03, SaidaSeg = 0.16, Suave = true,
	Quadros = function()
		return {
			{ 0.00, Anim.POSE_SEGURAR },
			{ 0.14, { -- bola na mão direita, braço pra trás; esquerda aponta o alvo
				Root = V(6, -28, 0), Waist = V(4, -18, 0), Neck = V(-4, 22, 0),
				RShoulder = V(-55, 0, 28), RElbow = V(25, 0, 0), LShoulder = V(85, 0, 18), LElbow = V(10, 0, 0),
				RHip = V(-10, 0, 6), LHip = V(28, 0, -6), LKnee = V(-18, 0, 0), RKnee = V(-12, 0, 0),
			} },
			{ 0.28, { -- o braço sobe por trás (roda por cima)
				Root = V(-6, -18, 0), Waist = V(0, -10, 0), Neck = V(0, 14, 0),
				RShoulder = V(150, 0, 22), RElbow = V(15, 0, 0), LShoulder = V(70, 0, 12), LElbow = V(20, 0, 0),
				RHip = V(-18, 0, 6), LHip = V(34, 0, -6), LKnee = V(-24, 0, 0), RKnee = V(-8, 0, 0),
			} },
			{ 0.38, { -- SOLTA: curvado pra frente, braço reto lá na frente
				Root = V(-30, 16, 0), Waist = V(-14, 14, 0), Neck = V(14, -10, 0),
				RShoulder = V(95, 0, 4), RElbow = V(0, 0, 0), LShoulder = V(15, 0, -30), LElbow = V(35, 0, 0),
				RHip = V(-25, 0, 4), RKnee = V(-10, 0, 0), LHip = V(38, 0, -6), LKnee = V(-30, 0, 0),
				RootPos = V(0, -0.3, 0),
			} },
			{ 0.52, { -- acompanha o movimento cruzando o corpo
				Root = V(-20, 22, 0), Waist = V(-8, 12, 0),
				RShoulder = V(55, 0, -30), RElbow = V(20, 0, 0), LShoulder = V(10, 0, -20), LElbow = V(30, 0, 0),
				RHip = V(10, 0, 4), LHip = V(20, 0, -4), LKnee = V(-20, 0, 0),
				RootPos = V(0, -0.2, 0),
			} },
			{ 0.75, neutro() },
		}
	end,
}

-- AGARRAR — v110 — PEDIDO: "não tem animação do GK pegar a bola na mão". Os
-- braços vão NA bola (esticados pra frente) e puxam pro peito agachando um pouco
-- pra amortecer — termina na pose de segurar.
Anim.Acoes.Agarrar = {
	Duracao = 0.4, EntradaSeg = 0.02, SaidaSeg = 0.1, Suave = true,
	Quadros = function()
		return {
			{ 0.00, neutro() },
			{ 0.10, { Root = V(-8, 0, 0), Neck = V(-6, 0, 0),
				RShoulder = V(105, 0, -8), LShoulder = V(105, 0, 8), RElbow = V(12, 0, 0), LElbow = V(12, 0, 0),
				RHip = V(25, 0, 6), LHip = V(25, 0, -6), RKnee = V(-35, 0, 0), LKnee = V(-35, 0, 0), RootPos = V(0, -0.25, 0) } },
			{ 0.24, { Root = V(-12, 0, 0), Neck = V(-10, 0, 0),
				RShoulder = V(70, 0, -16), LShoulder = V(70, 0, 16), RElbow = V(75, 0, 0), LElbow = V(75, 0, 0),
				RHip = V(35, 0, 6), LHip = V(35, 0, -6), RKnee = V(-50, 0, 0), LKnee = V(-50, 0, 0), RootPos = V(0, -0.4, 0) } },
			{ 0.40, Anim.POSE_SEGURAR },
		}
	end,
}

-- ----- GUARDA DE COUNTER (Passo Furtivo com a bola) — ⚠️ v123 -----
-- PEDIDO: "quando usar o counter, ele vai fazer uma animação e ficar paralisado".
-- Postura de espera: base aberta, corpo um pouco de lado e abaixado, braços abertos
-- e prontos (R6: braço bem fora do tronco), respirando de leve enquanto dura.
do
	local guarda = {
		Root = V(-12, -22, 0), Neck = V(4, 20, 0),
		RHip = V(18, 0, 16), LHip = V(-10, 0, -16), RKnee = V(-35, 0, 0), LKnee = V(-30, 0, 0),
		RShoulder = V(30, 0, 58), LShoulder = V(45, 0, -52), RElbow = V(55, 0, 0), LElbow = V(70, 0, 0),
		RootPos = V(0, -0.35, 0),
	}
	local respira = {
		Root = V(-15, -22, 0), Neck = V(6, 20, 0),
		RHip = V(20, 0, 17), LHip = V(-9, 0, -17), RKnee = V(-38, 0, 0), LKnee = V(-33, 0, 0),
		RShoulder = V(34, 0, 62), LShoulder = V(48, 0, -56), RElbow = V(58, 0, 0), LElbow = V(72, 0, 0),
		RootPos = V(0, -0.42, 0),
	}
	Anim.Acoes.GuardaCounter = {
		Duracao = 1.6, EntradaSeg = 0.06, SaidaSeg = 0.12, Suave = true,
		Quadros = function()
			return {
				{ 0.00, neutro() },
				{ 0.14, guarda },
				{ 0.55, respira },
				{ 0.95, guarda },
				{ 1.35, respira },
				{ 1.60, guarda },
			}
		end,
	}
end

-- ----- DASH (arrancada) — ⚠️ v104 -----
-- PEDIDO: "faça uma animação de dash também, e inclua um vento em volta com
-- VFX, como se tivesse bem rápido atravessando o vento". Arrancada de anime:
-- agacha e explode, corpo quase deitado pra frente e braços jogados pra trás
-- durante o deslocamento (0.25s do servidor, FimDaMecanica), depois recupera.
-- params: X = lado (+ direita), Z = frente (+ pra frente), direção do dash no
-- espaço do corpo — dash pro lado inclina pro lado, pra trás inclina pra trás.
Anim.Acoes.Dash = {
	Duracao = 0.45, FimDaMecanica = 0.25, EntradaSeg = 0.02, SaidaSeg = 0.12,
	Quadros = function(p)
		p = p or {}
		local lado = math.clamp(tonumber(p.X) or 0, -1, 1)
		local frente = math.clamp(tonumber(p.Z) or 1, -1, 1)
		local praTras = frente < -0.4
		local pitch = praTras and 22 or -48 * math.max(0.35, frente) - 10
		local roll = -lado * 22
		local bracos = praTras and 40 or -72
		return {
			{ 0.00, neutro() },
			{ 0.05, { -- agacha pra explodir
				Root = V(pitch * 0.55, 0, roll * 0.5), Neck = V(-pitch * 0.4, 0, 0),
				RHip = V(55, 0, 6), RKnee = V(-75, 0, 0), LHip = V(-20, 0, -6), LKnee = V(-35, 0, 0), LAnkle = V(18, 0, 0),
				RShoulder = V(bracos * 0.6, 0, 20), LShoulder = V(bracos * 0.6, 0, -20), RElbow = V(20, 0, 0), LElbow = V(20, 0, 0),
				RootPos = V(0, -0.55, 0),
			} },
			{ 0.13, { -- rasgando o ar
				Root = V(pitch, 0, roll), Neck = V(-pitch * 0.75, 0, -roll * 0.4),
				RHip = V(38, 0, 6), RKnee = V(-88, 0, 0), RAnkle = V(10, 0, 0),
				LHip = V(-38, 0, -6), LKnee = V(-45, 0, 0), LAnkle = V(25, 0, 0),
				RShoulder = V(bracos, 0, 28), LShoulder = V(bracos, 0, -28), RElbow = V(8, 0, 0), LElbow = V(8, 0, 0),
				RootPos = V(0, -0.45, 0),
			} },
			{ 0.25, {
				Root = V(pitch * 0.9, 0, roll * 0.8), Neck = V(-pitch * 0.65, 0, 0),
				RHip = V(-20, 0, 6), RKnee = V(-40, 0, 0), LHip = V(40, 0, -6), LKnee = V(-80, 0, 0),
				RShoulder = V(bracos * 0.9, 0, 25), LShoulder = V(bracos * 0.9, 0, -25), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0),
				RootPos = V(0, -0.4, 0),
			} },
			{ 0.36, { -- recupera o corpo
				Root = V(pitch * 0.3, 0, roll * 0.2), Neck = V(-pitch * 0.2, 0, 0),
				RHip = V(20, 0, 4), RKnee = V(-30, 0, 0), LHip = V(-5, 0, -4), LKnee = V(-20, 0, 0),
				RShoulder = V(-10, 0, 15), LShoulder = V(15, 0, -15), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
				RootPos = V(0, -0.12, 0),
			} },
			{ 0.45, neutro() },
		}
	end,
}

-- ----- INVESTIDA TITÂNICA (dashzão de ombro) — ⚠️ v108 -----
-- PEDIDO: "a arrancada é literalmente um dashzão que derruba as pessoas no
-- caminho... tackle não precisa de cutscene, já tem a animação dele". Corrida
-- de investida: corpo bem inclinado, ombro direito à frente, braço esquerdo
-- guardando o peito, passadas largas alternando. O servidor manda a duração do
-- dash (FimDaMecanica) e depois ele recupera.
do
	local QUADROS = { { 0.00, neutro() }, { 0.08, {
		Root = V(-22, -12, 0), Waist = V(-6, -10, 0), Neck = V(18, 10, 0),
		RHip = V(60, 0, 6), RKnee = V(-80, 0, 0), LHip = V(-15, 0, -6), LKnee = V(-40, 0, 0),
		RShoulder = V(-35, 0, 15), LShoulder = V(55, 0, -35), LElbow = V(95, 0, 0), RElbow = V(20, 0, 0),
		RootPos = V(0, -0.5, 0),
	} } }
	local t, lado = 0.2, 1
	while t < 2.3 do
		table.insert(QUADROS, { t, {
			Root = V(-34, -18, 0), Waist = V(-8, -12, 0), Neck = V(26, 14, 0),
			RHip = V(lado > 0 and 65 or -40, 0, 6), RKnee = V(lado > 0 and -85 or -35, 0, 0),
			LHip = V(lado > 0 and -40 or 65, 0, -6), LKnee = V(lado > 0 and -35 or -85, 0, 0),
			RShoulder = V(-45 + 15 * lado, 0, 18), LShoulder = V(60, 0, -38), LElbow = V(100, 0, 0), RElbow = V(15, 0, 0),
			RootPos = V(0, -0.35 - 0.1 * lado, 0),
		} })
		t += 0.16
		lado = -lado
	end
	table.insert(QUADROS, { 2.45, {
		Root = V(-10, -4, 0), Neck = V(6, 0, 0), RHip = V(20, 0, 4), RKnee = V(-30, 0, 0), LHip = V(-5, 0, -4), LKnee = V(-20, 0, 0),
		RShoulder = V(-10, 0, 15), LShoulder = V(15, 0, -15), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0), RootPos = V(0, -0.12, 0),
	} })
	table.insert(QUADROS, { 2.6, neutro() })
	Anim.Acoes.Investida = {
		Duracao = 2.6, FimDaMecanica = 2.3, EntradaSeg = 0.03, SaidaSeg = 0.15,
		Quadros = function() return QUADROS end,
	}
end

-- ----- SAÍDA DO GOLEIRO (avanço baixo nos pés do atacante) -----
-- v110 — PEDIDO: "o dive pra frente tá caindo muito estranho — é pra ir pra
-- frente como um dash, só que DEITADO RETO". A curva era fixa (0.9s) e o
-- deslocamento dura menos: ele terminava de deitar depois de já ter parado.
-- Agora FimDaMecanica = o voo (a curva estica pra duração que o servidor manda):
-- impulso curto, VOA deitado reto (super-homem: corpo na horizontal, braços
-- esticados pra frente, pernas retas) o voo inteiro, e só no fim cai e levanta.
Anim.Acoes.GKForwardDash = {
	-- ⚠️ v122: "levanta mais devagar do dash pra frente" — Duracao 1.0 → 1.5
	Duracao = 1.5, FimDaMecanica = 0.6, EntradaSeg = 0.03, SaidaSeg = 0.2, Suave = true,
	Quadros = function()
		local voo = {
			Root = V(-86, 0, 0), Neck = V(62, 0, 0),
			RHip = V(-6, 0, 4), LHip = V(-6, 0, -4), RKnee = V(-6, 0, 0), LKnee = V(-6, 0, 0),
			RAnkle = V(-35, 0, 0), LAnkle = V(-35, 0, 0),
			RShoulder = V(172, 0, 8), LShoulder = V(172, 0, -8), RElbow = V(6, 0, 0), LElbow = V(6, 0, 0),
			RootPos = V(0, -1.1, 0),
		}
		return {
			{ 0.00, Anim.GoleiroPronto(0) },
			{ 0.07, { -- impulso: agacha e explode
				Root = V(-35, 0, 0), Neck = V(35, 0, 0),
				RHip = V(65, 0, 8), LHip = V(45, 0, -8), RKnee = V(-85, 0, 0), LKnee = V(-65, 0, 0),
				RShoulder = V(60, 0, 20), LShoulder = V(60, 0, -20), RElbow = V(30, 0, 0), LElbow = V(30, 0, 0),
				RootPos = V(0, -0.6, 0),
			} },
			{ 0.16, voo },
			{ 0.60, voo }, -- voa DEITADO RETO o deslocamento inteiro
			-- ⚠️ v120b — PEDIDO: "o dive pra frente tem que cair no chão — tá flutuando e
			-- não desce; no fim ele cai no chão e levanta". Desce até o gramado (a
			-- correção de chão do animador ajusta o que passar) e fica um instante.
			{ 0.70, { -- cai no chão, deslizando
				Root = V(-88, 0, 0), Neck = V(50, 0, 0),
				RHip = V(0, 0, 6), LHip = V(0, 0, -6), RKnee = V(-20, 0, 0), LKnee = V(-20, 0, 0),
				RShoulder = V(140, 0, 28), LShoulder = V(140, 0, -28), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
				RootPos = V(0, -2.6, 0),
			} },
			{ 1.02, { -- fica de bruços (era até 0.78)
				Root = V(-88, 0, 0), Neck = V(40, 0, 0),
				RShoulder = V(120, 0, 34), LShoulder = V(120, 0, -34),
				RootPos = V(0, -2.6, 0),
			} },
			{ 1.16, { -- empurra o chão com as mãos
				Root = V(-60, 0, 0), Neck = V(30, 0, 0),
				RHip = V(30, 0, 6), LHip = V(20, 0, -6), RKnee = V(-60, 0, 0), LKnee = V(-50, 0, 0),
				RShoulder = V(70, 0, 20), LShoulder = V(70, 0, -20), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0),
				RootPos = V(0, -1.9, 0),
			} },
			{ 1.30, {
				Root = V(-15, 0, 0),
				RHip = V(75, 0, 8), LHip = V(70, 0, -8), RKnee = V(-105, 0, 0), LKnee = V(-100, 0, 0),
				RShoulder = V(30, 0, 20), LShoulder = V(30, 0, -20),
				RootPos = V(0, -1.0, 0),
			} },
			{ 1.45, Anim.GoleiroPronto(0) },
		}
	end,
}

-- ----- COMEMORAÇÃO DE GOL (em loop pela duração que o servidor mandar) -----
Anim.Acoes.GoalCelebration = {
	Duracao = 4, EntradaSeg = 0.1, SaidaSeg = 0.3, Loop = { 0.45, 1.25 },
	Quadros = function()
		local punhoCima = {
			Root = V(10, 0, 0), Waist = V(8, 0, 0), Neck = V(25, 0, 0),
			RShoulder = V(20, 0, 150), LShoulder = V(20, 0, -150), RElbow = V(25, 0, 0), LElbow = V(25, 0, 0),
			RHip = V(10, 0, 8), LHip = V(10, 0, -8), RKnee = V(-15, 0, 0), LKnee = V(-15, 0, 0),
		}
		local punhoBaixo = {
			Root = V(-4, 0, 0), Waist = V(-6, 0, 0), Neck = V(10, 0, 0),
			RShoulder = V(10, 0, 70), LShoulder = V(10, 0, -70), RElbow = V(110, 0, 0), LElbow = V(110, 0, 0),
			RHip = V(30, 0, 8), LHip = V(30, 0, -8), RKnee = V(-45, 0, 0), LKnee = V(-45, 0, 0),
			RootPos = V(0, -0.35, 0),
		}
		return {
			{ 0.00, neutro() },
			{ 0.45, punhoCima },
			{ 0.85, punhoBaixo },
			{ 1.25, punhoCima },
		}
	end,
}

-- ----- PREPARO DE HISSATSU (⚠️ v103) -----
-- PEDIDO: "coloca uma animação pra iniciar todas as Hissatsus: a do Tornado de
-- Fogo, ele começa a preparar um chutão diferente, aparece um foguinho em
-- volta dele bem de leve, umas faíscas, só pra você entender que ele tá
-- começando a querer chutar. A do Fúria Glacial, de gelo. De todas." Toca
-- durante o PREPARO (o jogador fica parado antes da cutscene), em loop
-- respirando; o VFX leve é do HissatsuCutsceneClient (Efeitos.Preparo).
-- p.Estilo = nome da cutscene (FireTornado, FuriaGlacial...) ou o Elemento.
local PREPARO_POSES = {
	-- chutão armado: tronco pra frente, perna direita bem atrás, punhos cerrados
	FireTornado = {
		Root = V(-12, -15, 0), Waist = V(-5, -10, 0), Neck = V(8, 15, 0),
		RHip = V(-35, 0, 8), RKnee = V(-70, 0, 0), LHip = V(25, 0, -8), LKnee = V(-35, 0, 0),
		RShoulder = V(-40, 0, 40), LShoulder = V(35, 0, -45), RElbow = V(30, 0, 0), LElbow = V(40, 0, 0),
		RootPos = V(0, -0.35, 0),
	},
	-- agachado, braço direito apontando pro céu (chamando o raio)
	RaioUm = {
		Root = V(-8, 0, 0), Neck = V(25, 0, 0),
		RHip = V(35, 0, 6), LHip = V(20, 0, -6), RKnee = V(-50, 0, 0), LKnee = V(-35, 0, 0),
		RShoulder = V(0, 0, 165), RElbow = V(5, 0, 0), LShoulder = V(10, 0, -40), LElbow = V(20, 0, 0),
		RootPos = V(0, -0.35, 0),
	},
	-- sinal de mão na frente do rosto, cabeça baixa
	Sumico = {
		Root = V(-4, 0, 0), Neck = V(-12, 0, 0),
		RShoulder = V(125, 0, -25), RElbow = V(95, 0, 0), LShoulder = V(0, 0, -15),
		RKnee = V(-10, 0, 0), LKnee = V(-10, 0, 0), RootPos = V(0, -0.1, 0),
	},
	-- base de surfe, de lado, braços equilibrando
	ImpulsoDeMare = {
		Root = V(-15, 25, 0), Waist = V(0, -15, 0), Neck = V(0, -30, 0),
		RHip = V(35, 0, 20), LHip = V(35, 0, -20), RKnee = V(-55, 0, 0), LKnee = V(-55, 0, 0),
		RShoulder = V(15, 0, 75), LShoulder = V(15, 0, -75),
		RootPos = V(0, -0.6, 0),
	},
	-- braços cruzados, pés plantados (frio e pesado)
	FuriaGlacial = {
		Root = V(4, 0, 0), Neck = V(-8, 0, 0),
		RShoulder = V(75, 0, -30), RElbow = V(110, 0, 0), LShoulder = V(70, 0, 30), LElbow = V(110, 0, 0),
		RHip = V(0, 0, 6), LHip = V(0, 0, -6),
	},
	-- curvado, braços abertos pra baixo, cabeça baixa (energia escura)
	ZonaMorta = {
		Root = V(-18, 0, 0), Waist = V(-8, 0, 0), Neck = V(-20, 0, 0),
		RShoulder = V(-10, 0, 50), LShoulder = V(-10, 0, -50), RElbow = V(40, 0, 0), LElbow = V(40, 0, 0),
		RHip = V(25, 0, 6), LHip = V(25, 0, -6), RKnee = V(-45, 0, 0), LKnee = V(-45, 0, 0),
		RootPos = V(0, -0.4, 0),
	},
	-- carregando o punho verde
	Galaxia = {
		Root = V(-10, 15, 0), Neck = V(-5, -10, 0),
		RShoulder = V(-50, 0, 30), RElbow = V(110, 0, 0), LShoulder = V(60, 0, -20), LElbow = V(20, 0, 0),
		RHip = V(25, 0, 6), LHip = V(30, 0, -6), RKnee = V(-35, 0, 0), LKnee = V(-35, 0, 0),
		RootPos = V(0, -0.3, 0),
	},
}
PREPARO_POSES.Padrao = PREPARO_POSES.FireTornado

-- respiração: a mesma pose um pouco mais funda
local function respirando(pose)
	local r = table.clone(pose)
	local root = pose.Root or V(0, 0, 0)
	r.Root = root + V(-3, 0, 0)
	r.RootPos = (pose.RootPos or V(0, 0, 0)) + V(0, -0.08, 0)
	return r
end

Anim.Acoes.HissatsuPreparo = {
	Duracao = 2, EntradaSeg = 0.18, SaidaSeg = 0.2, Loop = { 0.35, 1.25 },
	Quadros = function(p)
		local pose = PREPARO_POSES[p.Estilo or ""] or PREPARO_POSES.Padrao
		return {
			{ 0.00, neutro() },
			{ 0.35, pose },
			{ 0.80, respirando(pose) },
			{ 1.25, pose },
		}
	end,
}

-- ============================================================
-- ⚠️ v110 — ANIMAÇÕES DAS HISSATSUS DE DRIBLE E DEFESA
-- ============================================================
-- PEDIDO: "vai com os dribles e defesas... olhe na wiki". Cada uma segue o
-- "Usage" da Inazuma Eleven Wiki da técnica original (citado em cima de cada).
-- Tocadas pelo HissatsuVFXClient em todo cliente (_G.AnimadorAcaoLocal), junto
-- com o VFX. GIROS INTEIROS: um quadro com o ângulo 0 seguido, 0.1ms depois, de
-- um com ±360 (mesma orientação — o salto não aparece) e daí volta a 0 girando;
-- assim o giro termina em 0 e a saída não "desgira".
local function acaoHissatsu(duracao, quadros, suave)
	return { Duracao = duracao, EntradaSeg = 0.04, SaidaSeg = 0.14, Suave = suave, Quadros = function() return quadros end }
end
local BRACOS_TRAS = { RShoulder = V(-70, 0, 20), LShoulder = V(-70, 0, -20), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0) }
local function com(base, extra)
	local p = table.clone(base)
	for k, v in pairs(extra) do p[k] = v end
	return p
end

-- Afterimage (残像): "para de repente, CRUZA OS BRAÇOS paralelos no ar e deixa
-- uma imagem parada de si; sai driblando pra direita".
Anim.Acoes.Residual = acaoHissatsu(0.55, {
	{ 0.00, neutro() },
	{ 0.06, { Root = V(-4, 0, 0), Neck = V(6, 0, 0), RShoulder = V(150, 0, -28), LShoulder = V(150, 0, 28),
		RElbow = V(45, 0, 0), LElbow = V(45, 0, 0), RKnee = V(-15, 0, 0), LKnee = V(-15, 0, 0) } },
	{ 0.18, { Root = V(-4, 0, 0), Neck = V(6, 0, 0), RShoulder = V(150, 0, -28), LShoulder = V(150, 0, 28),
		RElbow = V(45, 0, 0), LElbow = V(45, 0, 0), RKnee = V(-15, 0, 0), LKnee = V(-15, 0, 0) } },
	{ 0.32, { Root = V(-12, 0, -18), RShoulder = V(20, 0, 60), LShoulder = V(20, 0, -50),
		RHip = V(20, 0, 30), LHip = V(-10, 0, -5), LKnee = V(-45, 0, 0), RootPos = V(0, -0.4, 0) } },
	{ 0.55, neutro() },
})

-- Shippuu Dash (疾風ダッシュ): "dispara pra direita e pra esquerda deixando
-- rajadas de vento; perto do marcador some e reaparece atrás dele".
local CORRE_D = com(BRACOS_TRAS, { RHip = V(55, 0, 0), RKnee = V(-85, 0, 0), LHip = V(-30, 0, 0), LKnee = V(-40, 0, 0), RootPos = V(0, -0.4, 0) })
local CORRE_E = com(BRACOS_TRAS, { LHip = V(55, 0, 0), LKnee = V(-85, 0, 0), RHip = V(-30, 0, 0), RKnee = V(-40, 0, 0), RootPos = V(0, -0.4, 0) })
Anim.Acoes.Vendaval = acaoHissatsu(0.6, {
	{ 0.00, neutro() },
	{ 0.09, com(CORRE_D, { Root = V(-28, 0, -22), Neck = V(20, 0, 10) }) },
	{ 0.22, com(CORRE_E, { Root = V(-28, 0, 22), Neck = V(20, 0, -10) }) },
	{ 0.36, com(CORRE_D, { Root = V(-28, 0, -22), Neck = V(20, 0, 10) }) },
	{ 0.48, com(CORRE_E, { Root = V(-34, 0, 0), Neck = V(25, 0, 0) }) },
	{ 0.60, neutro() },
}, true)

-- Dokugiri no Jutsu (毒霧の術): "avança com o punho na palma, salta, puxa o ar e,
-- ao cair, SOPRA um bafo venenoso que vira névoa".
local PUNHO_PALMA = { RShoulder = V(80, 0, -35), LShoulder = V(80, 0, 35), RElbow = V(95, 0, 0), LElbow = V(95, 0, 0) }
Anim.Acoes.Nevoa = acaoHissatsu(0.9, {
	{ 0.00, neutro() },
	{ 0.10, com(PUNHO_PALMA, { Root = V(-6, 0, 0) }) },
	{ 0.30, com(PUNHO_PALMA, { RHip = V(45, 0, 0), RKnee = V(-80, 0, 0), LHip = V(45, 0, 0), LKnee = V(-80, 0, 0), RootPos = V(0, 1.3, 0) }) },
	{ 0.45, com(PUNHO_PALMA, { Root = V(12, 0, 0), Neck = V(22, 0, 0), RHip = V(30, 0, 0), LHip = V(30, 0, 0),
		RKnee = V(-50, 0, 0), LKnee = V(-50, 0, 0), RootPos = V(0, -0.5, 0) }) },
	{ 0.62, { Root = V(-24, 0, 0), Neck = V(-16, 0, 0), RShoulder = V(40, 0, 50), LShoulder = V(40, 0, -50),
		RElbow = V(20, 0, 0), LElbow = V(20, 0, 0), RHip = V(30, 0, 0), LHip = V(-5, 0, 0), RKnee = V(-45, 0, 0), RootPos = V(0, -0.4, 0) } },
	{ 0.90, neutro() },
})

-- Kamaitachi (カマイタチ): "PISA no campo com o pé direito, gira o corpo inteiro
-- pra frente criando um redemoinho de poeira e CORTA o adversário".
Anim.Acoes.FoiceVento = acaoHissatsu(0.75, {
	{ 0.00, neutro() },
	{ 0.10, { RHip = V(75, 0, 0), RKnee = V(-95, 0, 0), RShoulder = V(20, 0, 60), LShoulder = V(20, 0, -60), LKnee = V(-15, 0, 0) } },
	{ 0.20, { Root = V(-10, 0, 0), RHip = V(12, 0, 0), RKnee = V(-30, 0, 0), LKnee = V(-30, 0, 0),
		RShoulder = V(10, 0, 70), LShoulder = V(10, 0, -70), RootPos = V(0, -0.55, 0) } },
	{ 0.2001, { Root = V(-10, -360, 0), RHip = V(12, 0, 0), RKnee = V(-30, 0, 0), LKnee = V(-30, 0, 0),
		RShoulder = V(10, 0, 70), LShoulder = V(10, 0, -70), RootPos = V(0, -0.55, 0) } },
	{ 0.40, { Root = V(-25, -150, 0), RShoulder = V(0, 0, 88), LShoulder = V(0, 0, -88), RHip = V(30, 0, 25), RootPos = V(0, 0.3, 0) } },
	{ 0.55, { Root = V(-32, 0, 0), Neck = V(20, 0, 0), RShoulder = V(95, 0, 20), LShoulder = V(-30, 0, -40),
		RHip = V(45, 0, 0), RKnee = V(-70, 0, 0), LHip = V(-25, 0, 0), RootPos = V(0, -0.4, 0) } },
	{ 0.75, neutro() },
})

-- Heaven's Time (ヘブンズタイム): "ergue a mão e ESTALA os dedos — luz azul, o
-- campo fica cinza e todo mundo para". (O segundo estalo, no fim, é a mesma.)
Anim.Acoes.HoraDoCeu = acaoHissatsu(0.7, {
	{ 0.00, neutro() },
	{ 0.22, { Root = V(4, 0, 0), Neck = V(18, 0, 0), RShoulder = V(172, 0, 8), RElbow = V(18, 0, 0), RWrist = V(-20, 0, 0),
		LShoulder = V(-5, 0, -10) } },
	{ 0.34, { Root = V(4, 0, 0), Neck = V(18, 0, 0), RShoulder = V(172, 0, 8), RElbow = V(22, 0, 0), RWrist = V(35, 0, 0),
		LShoulder = V(-5, 0, -10) } },
	{ 0.50, { Root = V(2, 0, 0), Neck = V(10, 0, 0), RShoulder = V(160, 0, 10), RElbow = V(20, 0, 0), RWrist = V(35, 0, 0) } },
	{ 0.70, neutro() },
})

-- Heat Tackle (ヒートタックル, versão AC): "cruza os braços em X, a energia de
-- fogo envolve; abre os braços e INVESTE de ombro".
Anim.Acoes.InvestidaChamas = acaoHissatsu(0.7, {
	{ 0.00, neutro() },
	{ 0.12, { Root = V(-6, 0, 0), RShoulder = V(95, 0, -42), LShoulder = V(95, 0, 42), RElbow = V(70, 0, 0), LElbow = V(70, 0, 0),
		RKnee = V(-30, 0, 0), LKnee = V(-30, 0, 0), RootPos = V(0, -0.35, 0) } },
	{ 0.30, { Root = V(-8, 0, 0), RShoulder = V(98, 0, -44), LShoulder = V(98, 0, 44), RElbow = V(75, 0, 0), LElbow = V(75, 0, 0),
		RKnee = V(-38, 0, 0), LKnee = V(-38, 0, 0), RootPos = V(0, -0.45, 0) } },
	{ 0.40, { Root = V(-4, 0, 0), Neck = V(10, 0, 0), RShoulder = V(15, 0, 85), LShoulder = V(15, 0, -85), RElbow = V(10, 0, 0), LElbow = V(10, 0, 0) } },
	{ 0.52, { Root = V(-36, -18, 0), Neck = V(25, 0, 0), RShoulder = V(45, 0, 20), LShoulder = V(-45, 0, -20), RElbow = V(60, 0, 0),
		RHip = V(55, 0, 0), RKnee = V(-85, 0, 0), LHip = V(-28, 0, 0), LKnee = V(-35, 0, 0), RootPos = V(0, -0.45, 0) } },
	{ 0.70, neutro() },
})

-- Illusion Ball (イリュージョンボール): "dá um MORTAL no ar com a bola, cria duas
-- ilusões dela girando e sai pra esquerda".
local GRUPADO = { RHip = V(100, 0, 0), RKnee = V(-115, 0, 0), LHip = V(100, 0, 0), LKnee = V(-115, 0, 0),
	RShoulder = V(60, 0, 20), LShoulder = V(60, 0, -20), RElbow = V(60, 0, 0), LElbow = V(60, 0, 0) }
Anim.Acoes.BolaIlusao = acaoHissatsu(0.62, {
	{ 0.00, neutro() },
	{ 0.08, { Root = V(-10, 0, 0), RKnee = V(-45, 0, 0), LKnee = V(-45, 0, 0), RHip = V(25, 0, 0), LHip = V(25, 0, 0), RootPos = V(0, -0.5, 0) } },
	{ 0.0801, { Root = V(350, 0, 0), RKnee = V(-45, 0, 0), LKnee = V(-45, 0, 0), RHip = V(25, 0, 0), LHip = V(25, 0, 0), RootPos = V(0, -0.5, 0) } },
	{ 0.25, com(GRUPADO, { Root = V(180, 0, 0), RootPos = V(0, 2.8, 0) }) },
	{ 0.40, com(GRUPADO, { Root = V(10, 0, 0), RootPos = V(0, 0.6, 0) }) },
	{ 0.48, { Root = V(-8, 0, 16), RHip = V(-10, 0, 5), LHip = V(20, 0, -35), LKnee = V(-40, 0, 0), RKnee = V(-30, 0, 0),
		RShoulder = V(20, 0, 55), LShoulder = V(20, 0, -45), RootPos = V(0, -0.45, 0) } },
	{ 0.62, neutro() },
})

-- Zigzag Spark (ジグザグスパーク): "pula da esquerda pra direita fazendo faíscas
-- azuis pelo atrito; no centro junta tudo numa faísca e solta no marcador".
local AGACHADO_PULO = { RHip = V(45, 0, 0), RKnee = V(-80, 0, 0), LHip = V(45, 0, 0), LKnee = V(-80, 0, 0),
	RShoulder = V(-35, 0, 40), LShoulder = V(-35, 0, -40) }
Anim.Acoes.FaiscaZigueZague = acaoHissatsu(0.78, {
	{ 0.00, neutro() },
	{ 0.10, com(AGACHADO_PULO, { Root = V(-8, 0, 14), RootPos = V(-1.6, 1.1, 0) }) },
	{ 0.20, com(AGACHADO_PULO, { Root = V(-8, 0, -14), RootPos = V(1.6, 1.1, 0) }) },
	{ 0.30, com(AGACHADO_PULO, { Root = V(-8, 0, 14), RootPos = V(-1.3, 1.1, 0) }) },
	{ 0.42, com(AGACHADO_PULO, { Root = V(-12, 0, 0), RootPos = V(0, -0.5, 0), RShoulder = V(30, 0, 30), LShoulder = V(30, 0, -30) }) },
	{ 0.52, { Root = V(-18, 0, 0), Neck = V(-5, 0, 0), RShoulder = V(92, 0, 8), LShoulder = V(92, 0, -8), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
		RHip = V(35, 0, 0), RKnee = V(-50, 0, 0), LHip = V(-15, 0, 0), RootPos = V(0, -0.4, 0) } },
	{ 0.78, neutro() },
})

-- Sprint Warp (スプリントワープ): "braços jogados pra trás, tronco inclinado pra
-- frente; dispara levantando poeira, teleporta em zigue-zague e freia de lado".
Anim.Acoes.DobraVeloz = acaoHissatsu(0.8, {
	{ 0.00, neutro() },
	{ 0.10, com(CORRE_D, { Root = V(-45, 0, 0), Neck = V(35, 0, 0), RootPos = V(0, -0.55, 0) }) },
	{ 0.28, com(CORRE_E, { Root = V(-48, 0, -10), Neck = V(35, 0, 0) }) },
	{ 0.46, com(CORRE_D, { Root = V(-48, 0, 10), Neck = V(35, 0, 0) }) },
	{ 0.62, { Root = V(-10, 0, 28), Neck = V(10, 0, -10), RHip = V(15, 0, 45), RKnee = V(-15, 0, 0), LHip = V(40, 0, -5), LKnee = V(-75, 0, 0),
		RShoulder = V(20, 0, 70), LShoulder = V(40, 0, -30), RootPos = V(0, -0.9, 0) } },
	{ 0.80, neutro() },
}, true)

-- Killer Slide: o carrinho do servidor já é a pose; as "pernas fantasmas"
-- chutando são VFX. Frozen Steal idem (o gelo na perna é VFX).

-- Kage Nui (影縫い): "para, JUNTA as mãos, puxa os braços pra trás e estica a
-- própria sombra no campo".
Anim.Acoes.Costura = acaoHissatsu(1.0, {
	{ 0.00, neutro() },
	{ 0.15, { Root = V(-4, 0, 0), Neck = V(-10, 0, 0), RShoulder = V(78, 0, -32), LShoulder = V(78, 0, 32), RElbow = V(100, 0, 0), LElbow = V(100, 0, 0) } },
	{ 0.35, { Root = V(-4, 0, 0), Neck = V(-12, 0, 0), RShoulder = V(80, 0, -33), LShoulder = V(80, 0, 33), RElbow = V(102, 0, 0), LElbow = V(102, 0, 0) } },
	{ 0.50, { Root = V(-22, 0, 0), Neck = V(18, 0, 0), RShoulder = V(-65, 0, 28), LShoulder = V(-65, 0, -28), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
		RHip = V(45, 0, 0), RKnee = V(-65, 0, 0), LHip = V(-12, 0, 0), LKnee = V(-20, 0, 0), RootPos = V(0, -0.55, 0) } },
	{ 0.85, { Root = V(-22, 0, 0), Neck = V(18, 0, 0), RShoulder = V(-68, 0, 28), LShoulder = V(-68, 0, -28), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
		RHip = V(45, 0, 0), RKnee = V(-65, 0, 0), LHip = V(-12, 0, 0), LKnee = V(-20, 0, 0), RootPos = V(0, -0.55, 0) } },
	{ 1.00, neutro() },
})

-- Kumo no Ito (くもの糸): "AJOELHA com a mão esquerda na frente do rosto, dá um
-- MORTAL PRA TRÁS e põe a mão direita no campo — os fios se espalham".
local AJOELHADO_TEIA = { LHip = V(0, 0, -5), LKnee = V(-95, 0, 0), RHip = V(80, 0, 5), RKnee = V(-85, 0, 0),
	LShoulder = V(115, 0, 12), LElbow = V(105, 0, 0), RShoulder = V(-10, 0, 25), Neck = V(-5, 0, 0), RootPos = V(0, -1.3, 0) }
-- (R6: o quadril só desce com o tronco tombado >45° — por isso 50° pra frente, e
-- as pernas quase na vertical afundam no gramado, lendo como "agachado")
local MAO_NO_CHAO = { Root = V(-50, 0, 0), Neck = V(30, 0, 0), RShoulder = V(40, 0, 12), RElbow = V(5, 0, 0), LShoulder = V(-20, 0, -35),
	RHip = V(55, 0, 10), RKnee = V(-60, 0, 0), LHip = V(35, 0, -10), LKnee = V(-60, 0, 0), RootPos = V(0, -1.3, 0.3) }
Anim.Acoes.Teia = acaoHissatsu(1.05, {
	{ 0.00, neutro() },
	{ 0.12, AJOELHADO_TEIA },
	{ 0.30, AJOELHADO_TEIA },
	{ 0.3001, com(AJOELHADO_TEIA, { Root = V(-360, 0, 0) }) },
	{ 0.50, com(GRUPADO, { Root = V(-180, 0, 0), RootPos = V(0, 2.6, 0) }) },
	{ 0.66, com(GRUPADO, { Root = V(-15, 0, 0), RootPos = V(0, -1.2, 0) }) },
	{ 0.74, MAO_NO_CHAO },
	{ 0.92, MAO_NO_CHAO },
	{ 1.05, neutro() },
})

-- The Wall (ザ・ウォール, versão GO): "agacha e ESTICA os dois braços pro alto,
-- batendo os punhos — a muralha sobe e o campo treme". Fica assim enquanto a
-- Muralha Infinita estiver de pé (quem ergue não sai do lugar).
local AGACHA_MURO = { Root = V(-12, 0, 0), RHip = V(70, 0, 8), LHip = V(70, 0, -8), RKnee = V(-100, 0, 0), LKnee = V(-100, 0, 0),
	RShoulder = V(-20, 0, 25), LShoulder = V(-20, 0, -25), RootPos = V(0, -1.1, 0) }
local BRACOS_ALTO = { Root = V(8, 0, 0), Neck = V(22, 0, 0), RShoulder = V(172, 0, -14), LShoulder = V(172, 0, 14),
	RElbow = V(18, 0, 0), LElbow = V(18, 0, 0), RHip = V(12, 0, 10), LHip = V(12, 0, -10), RKnee = V(-15, 0, 0), LKnee = V(-15, 0, 0) }
Anim.Acoes.Muralha = acaoHissatsu(5.0, {
	{ 0.00, neutro() },
	{ 0.22, AGACHA_MURO },
	{ 0.45, BRACOS_ALTO },
	{ 4.70, com(BRACOS_ALTO, { Root = V(6, 0, 0) }) },
	{ 5.00, neutro() },
})

-- Super Shikofumi (スーパーしこふみ): "braço direito pro alto, levanta a perna
-- esquerda de lado e PISA — ondas de choque amarelas".
Anim.Acoes.PisaoSumo = acaoHissatsu(0.75, {
	{ 0.00, neutro() },
	{ 0.22, { Root = V(0, 0, -14), Neck = V(10, 0, 8), RShoulder = V(172, 0, 18), LShoulder = V(10, 0, -65),
		LHip = V(15, 0, -78), LKnee = V(-45, 0, 0), RKnee = V(-18, 0, 0), RHip = V(8, 0, 6) } },
	{ 0.38, { Root = V(-8, 0, 0), Neck = V(-5, 0, 0), RShoulder = V(20, 0, 55), LShoulder = V(20, 0, -55),
		LHip = V(35, 0, -32), LKnee = V(-70, 0, 0), RHip = V(35, 0, 32), RKnee = V(-70, 0, 0), RootPos = V(0, -1.1, 0) } },
	{ 0.56, { Root = V(-8, 0, 0), RShoulder = V(15, 0, 55), LShoulder = V(15, 0, -55),
		LHip = V(35, 0, -32), LKnee = V(-70, 0, 0), RHip = V(35, 0, 32), RKnee = V(-70, 0, 0), RootPos = V(0, -1.1, 0) } },
	{ 0.75, neutro() },
})

-- Spinning Cut (スピニングカット): "salta, puxa a perna direita pra trás, o pé
-- brilha azul e dá um CHUTE GIRATÓRIO que manda um corte em meia-lua pro chão".
Anim.Acoes.CorteGiratorio = acaoHissatsu(0.72, {
	{ 0.00, neutro() },
	{ 0.12, { Root = V(-10, 0, 0), RHip = V(-50, 0, 0), RKnee = V(-95, 0, 0), LKnee = V(-30, 0, 0),
		RShoulder = V(25, 0, 55), LShoulder = V(25, 0, -55), RootPos = V(0, 0.4, 0) } },
	{ 0.1201, { Root = V(-10, 360, 0), RHip = V(-50, 0, 0), RKnee = V(-95, 0, 0), LKnee = V(-30, 0, 0),
		RShoulder = V(25, 0, 55), LShoulder = V(25, 0, -55), RootPos = V(0, 0.4, 0) } },
	{ 0.30, { Root = V(-6, 230, 14), RHip = V(80, 0, 60), RKnee = V(-6, 0, 0), LKnee = V(-25, 0, 0),
		RShoulder = V(10, 0, 80), LShoulder = V(10, 0, -80), RootPos = V(0, 0.9, 0) } },
	{ 0.44, { Root = V(-6, 40, 10), RHip = V(85, 0, 55), RKnee = V(-4, 0, 0), LKnee = V(-25, 0, 0),
		RShoulder = V(10, 0, 80), LShoulder = V(10, 0, -80), RootPos = V(0, 0.4, 0) } },
	{ 0.52, { Root = V(-6, 0, 0), RHip = V(20, 0, 10), RKnee = V(-40, 0, 0), LKnee = V(-40, 0, 0), RootPos = V(0, -0.45, 0) } },
	{ 0.72, neutro() },
})

-- Photon Flash (フォトンフラッシュ): "corre com os braços pra trás deixando brilhos,
-- salta GIRANDO com os braços pro alto juntando os brilhos, para — e CLARÃO".
Anim.Acoes.ClaraoFotons = acaoHissatsu(0.82, {
	{ 0.00, neutro() },
	{ 0.10, com(CORRE_D, { Root = V(-18, 0, 0) }) },
	{ 0.20, { Root = V(4, 0, 0), Neck = V(20, 0, 0), RShoulder = V(168, 0, 12), LShoulder = V(168, 0, -12), RKnee = V(-30, 0, 0), LKnee = V(-30, 0, 0), RootPos = V(0, 1.2, 0) } },
	{ 0.2001, { Root = V(4, -360, 0), Neck = V(20, 0, 0), RShoulder = V(168, 0, 12), LShoulder = V(168, 0, -12), RKnee = V(-30, 0, 0), LKnee = V(-30, 0, 0), RootPos = V(0, 1.2, 0) } },
	{ 0.48, { Root = V(4, 0, 0), Neck = V(20, 0, 0), RShoulder = V(170, 0, 8), LShoulder = V(170, 0, -8), RootPos = V(0, 0.8, 0) } },
	{ 0.58, { Root = V(12, 0, 0), Neck = V(12, 0, 0), RShoulder = V(65, 0, 72), LShoulder = V(65, 0, -72), RElbow = V(5, 0, 0), LElbow = V(5, 0, 0),
		RHip = V(15, 0, 12), LHip = V(15, 0, -12), RootPos = V(0, -0.3, 0) } },
	{ 0.82, neutro() },
})

-- Snow Angel (スノーエンジェル): "salta por cima do adversário, gira balançando a
-- perna direita e depois a esquerda num véu de vento gelado; cai PISANDO com os
-- dois pés e põe a mão direita no chão — o adversário vira um bloco de gelo".
Anim.Acoes.AnjoDaNeve = acaoHissatsu(1.2, {
	{ 0.00, neutro() },
	{ 0.12, { Root = V(-12, 0, 0), RHip = V(55, 0, 6), LHip = V(55, 0, -6), RKnee = V(-85, 0, 0), LKnee = V(-85, 0, 0),
		RShoulder = V(-30, 0, 25), LShoulder = V(-30, 0, -25), RootPos = V(0, -0.7, 0) } },
	{ 0.1201, { Root = V(-12, -360, 0), RHip = V(55, 0, 6), LHip = V(55, 0, -6), RKnee = V(-85, 0, 0), LKnee = V(-85, 0, 0),
		RShoulder = V(-30, 0, 25), LShoulder = V(-30, 0, -25), RootPos = V(0, -0.7, 0) } },
	{ 0.32, { Root = V(0, -250, 0), RHip = V(85, 0, 45), RKnee = V(-5, 0, 0), LKnee = V(-30, 0, 0),
		RShoulder = V(40, 0, 80), LShoulder = V(40, 0, -80), RootPos = V(0, 4.2, 0) } },
	{ 0.52, { Root = V(0, -110, 0), LHip = V(85, 0, -45), LKnee = V(-5, 0, 0), RKnee = V(-30, 0, 0),
		RShoulder = V(40, 0, 80), LShoulder = V(40, 0, -80), RootPos = V(0, 4.8, 0) } },
	{ 0.72, { Root = V(-6, 0, 0), RHip = V(30, 0, 8), LHip = V(30, 0, -8), RKnee = V(-40, 0, 0), LKnee = V(-40, 0, 0),
		RShoulder = V(100, 0, 40), LShoulder = V(100, 0, -40), RootPos = V(0, 2.4, 0) } },
	{ 0.84, MAO_NO_CHAO },
	{ 1.02, MAO_NO_CHAO },
	{ 1.20, neutro() },
})

-- Corrida de técnica (Photon Flash: "corre com os braços pra trás") — dura o
-- tempo que o servidor mandar; a passada repete (Loop)
Anim.Acoes.CorridaHissatsu = { Duracao = 0.5, EntradaSeg = 0.05, SaidaSeg = 0.1, Loop = { 0.0, 0.3 }, Quadros = function()
	return {
		{ 0.00, com(CORRE_D, { Root = V(-30, 0, 0), Neck = V(22, 0, 0) }) },
		{ 0.15, com(CORRE_E, { Root = V(-30, 0, 0), Neck = V(22, 0, 0) }) },
		{ 0.30, com(CORRE_D, { Root = V(-30, 0, 0), Neck = V(22, 0, 0) }) },
		{ 0.50, com(CORRE_D, { Root = V(-30, 0, 0), Neck = V(22, 0, 0) }) },
	}
end }

-- Kage Nui segurando: braços puxados pra trás, fincado, enquanto a sombra prende
local SEGURA_SOMBRA = { Root = V(-22, 0, 0), Neck = V(18, 0, 0), RShoulder = V(-68, 0, 28), LShoulder = V(-68, 0, -28),
	RElbow = V(5, 0, 0), LElbow = V(5, 0, 0), RHip = V(45, 0, 0), RKnee = V(-65, 0, 0), LHip = V(-12, 0, 0), LKnee = V(-20, 0, 0),
	RootPos = V(0, -0.55, 0) }
Anim.Acoes.CosturaSegura = { Duracao = 1.5, EntradaSeg = 0.08, SaidaSeg = 0.15, Quadros = function()
	return { { 0.00, SEGURA_SOMBRA }, { 0.75, com(SEGURA_SOMBRA, { Root = V(-25, 0, 0) }) }, { 1.50, SEGURA_SOMBRA } }
end }

-- REAÇÕES de quem sofre a técnica
-- Zigzag Spark: "o adversário fica paralisado DE JOELHOS".
-- (R6: tronco tombado >45° pra o quadril poder descer; as pernas afundam no
-- gramado até o "joelho")
local DE_JOELHOS = { Root = V(-50, 0, 0), Neck = V(-10, 0, 0), RHip = V(50, 0, 6), LHip = V(50, 0, -6), RKnee = V(-40, 0, 0), LKnee = V(-40, 0, 0),
	RShoulder = V(45, 0, 10), LShoulder = V(45, 0, -10), RElbow = V(15, 0, 0), LElbow = V(15, 0, 0), RootPos = V(0, -1.4, 0.4) }
Anim.Acoes.Paralisado = { Duracao = 1.4, EntradaSeg = 0.05, SaidaSeg = 0.2, Quadros = function()
	return { { 0.00, neutro() }, { 0.14, DE_JOELHOS }, { 1.20, DE_JOELHOS }, { 1.40, neutro() } }
end }
-- Super Shikofumi: "o pé gigante pisa e deixa o adversário ACHATADO".
local ACHATADO = { Root = V(-62, 0, 0), Neck = V(35, 0, 0), RHip = V(62, 0, 35), LHip = V(62, 0, -35), RKnee = V(-60, 0, 0), LKnee = V(-60, 0, 0),
	RShoulder = V(0, 0, 95), LShoulder = V(0, 0, -95), RootPos = V(0, -2.1, 0.3) }
Anim.Acoes.Achatado = { Duracao = 0.9, EntradaSeg = 0.02, SaidaSeg = 0.2, Quadros = function()
	return { { 0.00, neutro() }, { 0.06, ACHATADO }, { 0.72, ACHATADO }, { 0.90, neutro() } }
end }

-- ⚠️ v119 — CHAPÉU (Arma): "o chapéu precisa de animação própria". A lambreta:
-- a perna direita vai pra TRÁS, o calcanhar levanta a bola por cima da cabeça
-- do marcador (perna sobe pra frente), braços abertos de equilíbrio.
Anim.Acoes.Chapeu = { Duracao = 0.45, EntradaSeg = 0.03, SaidaSeg = 0.12, Quadros = function()
	return {
		{ 0.00, neutro() },
		{ 0.12, { Root = V(-10, 0, 0), Neck = V(-12, 0, 0), RHip = V(-40, 0, 6), LHip = V(8, 0, -4),
			RShoulder = V(-15, 0, 40), LShoulder = V(15, 0, -40) } },
		{ 0.24, { Root = V(8, 0, 0), Neck = V(18, 0, 0), RHip = V(60, 0, 4), LHip = V(-6, 0, -4),
			RShoulder = V(10, 0, 55), LShoulder = V(-10, 0, -55) } },
		{ 0.45, neutro() },
	}
end }
-- Marcador que levou o chapéu: TONTO — cambaleia olhando pra cima, sem entender.
local TONTO_A = { Root = V(4, 0, 8), Neck = V(22, 12, 10), RShoulder = V(5, 0, 25), LShoulder = V(5, 0, -18), RHip = V(0, 0, 6), LHip = V(0, 0, -2) }
local TONTO_B = { Root = V(4, 0, -8), Neck = V(22, -12, -10), RShoulder = V(5, 0, 18), LShoulder = V(5, 0, -25), RHip = V(0, 0, 2), LHip = V(0, 0, -6) }
Anim.Acoes.Tonto = { Duracao = 1.6, EntradaSeg = 0.08, SaidaSeg = 0.2, Loop = { 0.0, 0.8 }, Quadros = function()
	return { { 0.00, TONTO_A }, { 0.40, TONTO_B }, { 0.80, TONTO_A }, { 1.60, TONTO_A } }
end }

-- ⚠️ v110 — EMOTES e COMEMORAÇÕES da Loja (15 de cada): as poses moram no
-- módulo Cosmeticos (compartilhado com o Lobby); aqui viram ações comuns do
-- animador, com o Id do item como nome (ex.: "Emote_Dance", "Cel_Siu").
do
	local ok, Cosmeticos = pcall(function()
		return require(script.Parent:WaitForChild("Cosmeticos", 5))
	end)
	if ok and Cosmeticos then
		for _, cat in ipairs({ "Emote" }) do -- ⚠️ v117: comemorações agora moram em "Emote"
			for _, item in ipairs(Cosmeticos[cat]) do
				if not item.Quadros then continue end -- emote cadastrado por AnimationId toca como animação normal
				local quadros = {}
				for i, q in ipairs(item.Quadros) do
					quadros[i] = { q[1], next(q[2]) == nil and neutro() or q[2] }
				end
				Anim.Acoes[item.Id] = {
					Duracao = item.Duracao, EntradaSeg = 0.12, SaidaSeg = 0.25, Loop = item.Loop,
					Quadros = function() return quadros end,
				}
			end
		end
	end
end

-- Amostra uma ação no tempo t (segundos desde o início, já escalado pra
-- duração pedida). Devolve a pose e o "peso" (entrada/saída suaves).
function Anim.AmostrarAcao(acao, quadros, t, duracao)
	local escala = acao.Duracao / duracao
	local tt = t * escala -- tempo no relógio da ação (a Duracao original dela)
	if acao.Loop and tt > acao.Loop[1] and t < duracao - acao.SaidaSeg then
		local a, b = acao.Loop[1], acao.Loop[2]
		tt = a + (tt - a) % (b - a)
	end
	local amostrador = acao.Suave and amostrarSuave or amostrar -- ⚠️ v105: curva contínua (dives)
	local pose = amostrador(quadros, math.min(tt, quadros[#quadros][1]))
	local peso = 1
	if t < acao.EntradaSeg then peso = smooth(t / acao.EntradaSeg) end
	local resta = duracao - t
	if resta < acao.SaidaSeg then peso = math.min(peso, smooth(resta / acao.SaidaSeg)) end
	return pose, peso
end

return Anim
