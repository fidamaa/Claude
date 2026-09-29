--[[
	HissatsuEfeitos (ModuleScript)
	LOCAL: ReplicatedStorage

	⚠️ v100 — EFEITOS VISUAIS das cutscenes do MOTOR V2 (ver
	HissatsuCutsceneClient, tocarCutsceneV2). PEDIDO: "você começa as
	cutscenes das próximas habilidades" + o padrão que o usuário aprovou no
	Tornado de Fogo ("vfx profissional": rastro com duas camadas, halo largo
	+ miolo claro, de frente pra câmera; brasas; impacto com flash, onda de
	choque, linhas de velocidade e impact frame; bola que segue acesa no voo).

	Cada conjunto é uma função Criar(ctx) que devolve:
	  Quadro(t, dt, s)  — chamado todo quadro (s = estado do quadro, ver
	                      tocarCutsceneV2: RootLocal, BolaMundo, BolaLocal,
	                      ImpactoFeito, Pe...);
	  Impacto(s)        — uma vez, no instante do chute;
	  Voo(ball, duracao)— depois da cutscene, a bola segue com o efeito no
	                      voo de verdade (tudo local e temporário).
	A pasta ctx.Pasta é destruída pelo motor no fim — tudo que for criado
	dentro dela some junto.

	Só texturas que já vêm com o Roblox (rbxasset://textures/particles/...):
	não depende de asset publicado.
]]

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local E = {}

local TEX = {
	Fogo = "rbxasset://textures/particles/fire_main.dds",
	Faisca = "rbxasset://textures/particles/sparkles_main.dds",
	Fumaca = "rbxasset://textures/particles/smoke_main.dds",
}
E.TEX = TEX

local V3 = Vector3.new
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end

-- ===== utilidades =====
local function phase(t, a, b)
	if b <= a then return t >= b and 1 or 0 end
	return math.clamp((t - a) / (b - a), 0, 1)
end
local function smooth(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end
local function easeOut(u)
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) ^ 3
end

local function cores(lista)
	local k = {}
	for _, p in ipairs(lista) do table.insert(k, ColorSequenceKeypoint.new(p[1], p[2])) end
	return ColorSequence.new(k)
end
local function numeros(lista)
	local k = {}
	for _, p in ipairs(lista) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end
E.Cores = cores
E.Numeros = numeros

local function parte(pasta, nome, props)
	local p = Instance.new("Part")
	p.Name = nome
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Material = Enum.Material.Neon
	p.Size = V3(0.2, 0.2, 0.2)
	if props then
		for k, v in pairs(props) do p[k] = v end
	end
	p.Parent = pasta
	return p
end
E.Parte = parte

-- Emissor de partículas com padrões razoáveis (c = configuração)
local function emissor(pai, c)
	local e = Instance.new("ParticleEmitter")
	e.Texture = c.Textura or TEX.Faisca
	local cor = c.Cor or Color3.new(1, 1, 1)
	e.Color = typeof(cor) == "Color3" and ColorSequence.new(cor) or cor
	e.LightEmission = c.Brilho or 1
	e.LightInfluence = 0
	local tam = c.Tamanho or 1
	e.Size = typeof(tam) == "number" and numeros({ { 0, tam }, { 1, 0 } }) or tam
	e.Transparency = c.Transp or numeros({ { 0, 0 }, { 0.7, 0.3 }, { 1, 1 } })
	e.Lifetime = NumberRange.new(c.Vida and c.Vida[1] or 0.4, c.Vida and c.Vida[2] or 0.8)
	e.Speed = NumberRange.new(c.Vel and c.Vel[1] or 2, c.Vel and c.Vel[2] or 6)
	local sp = c.Spread or 180
	e.SpreadAngle = Vector2.new(sp, sp)
	e.Acceleration = c.Acel or Vector3.zero
	e.Drag = c.Drag or 1
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-(c.RotVel or 180), c.RotVel or 180)
	e.ZOffset = c.ZOffset or 0.3
	e.Rate = c.Taxa or 0
	e.Enabled = (c.Taxa or 0) > 0
	if c.Forma then e.Shape = c.Forma end
	if c.Estilo then e.ShapeStyle = c.Estilo end
	if c.Sentido then e.ShapeInOut = c.Sentido end
	if c.Direcao then e.EmissionDirection = c.Direcao end
	if c.Travado then e.LockedToPart = true end
	e.Parent = pai
	return e
end
E.Emissor = emissor

-- Rastro (Trail) vertical na parte, de frente pra câmera por padrão
local function rastro(p, largura, cor, cfg)
	cfg = cfg or {}
	local a0 = Instance.new("Attachment")
	a0.Position = V3(0, -largura, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = V3(0, largura, 0)
	a1.Parent = p
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = cfg.Vida or 0.4
	t.MinLength = 0.02
	t.LightEmission = cfg.Brilho or 1
	t.LightInfluence = 0
	t.FaceCamera = cfg.FaceCamera ~= false
	t.Color = typeof(cor) == "Color3" and ColorSequence.new(cor) or cor
	t.Transparency = cfg.Transp or numeros({ { 0, cfg.T0 or 0 }, { 0.6, 0.35 + (cfg.T0 or 0) * 0.5 }, { 1, 1 } })
	t.WidthScale = numeros({ { 0, 1 }, { 1, cfg.Fim or 0.15 } })
	if cfg.Textura then
		t.Texture = cfg.Textura
		t.TextureMode = Enum.TextureMode.Stretch
	end
	t.Enabled = false
	t.Parent = p
	return t
end
E.Rastro = rastro

-- Rastro de DUAS camadas (halo largo transparente + miolo claro) — o que
-- deu cara de "VFX profissional" na espiral do Tornado.
local function rastroDuplo(p, largura, corHalo, corMiolo, vida)
	local halo = rastro(p, largura, corHalo, { Vida = vida, T0 = 0.3, Brilho = 0.85, Textura = TEX.Fogo, Fim = 0.2 })
	local miolo = rastro(p, largura * 0.38, corMiolo, { Vida = vida * 0.85, T0 = 0, Brilho = 1, Textura = TEX.Fogo, Fim = 0.2 })
	return {
		Ligar = function(on) halo.Enabled = on; miolo.Enabled = on end,
		Halo = halo, Miolo = miolo,
	}
end
E.RastroDuplo = rastroDuplo

-- Raio (eletricidade) desenhado com um pool de peças neon em zigue-zague
local function novoRaio(pasta, cor, largura)
	local obj = { Partes = {} }
	function obj.Desenhar(a, b, n, desvio, larg, transp)
		n = n or 8
		local dir = b - a
		if dir.Magnitude < 0.05 then obj.Apagar() return end
		local p1 = dir:Cross(Vector3.yAxis)
		if p1.Magnitude < 0.01 then p1 = dir:Cross(Vector3.xAxis) end
		p1 = p1.Unit
		local p2 = dir:Cross(p1).Unit
		local pts = { a }
		for i = 1, n - 1 do
			local u = i / n
			local off = (p1 * (math.random() * 2 - 1) + p2 * (math.random() * 2 - 1)) * desvio * math.sin(u * math.pi)
			table.insert(pts, a + dir * u + off)
		end
		table.insert(pts, b)
		for i = 1, #pts - 1 do
			local p = obj.Partes[i]
			if not p then
				p = parte(pasta, "Raio", { Color = cor })
				obj.Partes[i] = p
			end
			local q0, q1 = pts[i], pts[i + 1]
			local len = (q1 - q0).Magnitude
			local w = larg or largura or 0.25
			p.Size = V3(w, w, math.max(len, 0.05))
			if len > 0.01 then p.CFrame = CFrame.lookAt((q0 + q1) / 2, q1) end
			p.Transparency = transp or 0
		end
		for i = #pts, #obj.Partes do
			obj.Partes[i].Transparency = 1
		end
	end
	function obj.Apagar()
		for _, p in ipairs(obj.Partes) do p.Transparency = 1 end
	end
	return obj
end
E.NovoRaio = novoRaio

-- Onda de choque (disco que abre e some). normal = eixo do disco.
local function onda(pasta, pos, normal, cor, final, tempo, grossura)
	local o = parte(pasta, "Onda", { Shape = Enum.PartType.Cylinder, Color = cor, Transparency = 0.05 })
	o.Size = V3(grossura or 0.3, 1, 1)
	o.CFrame = CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, math.rad(90), 0)
	TweenService:Create(o, TweenInfo.new(tempo, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = V3(0.1, final, final), Transparency = 1 }):Play()
	return o
end
E.Onda = onda

-- ⚠️ v108: ANEL vazado (ForceField brilha na borda, o meio fica transparente) —
-- pra anéis d'água/vento que não podem tampar o personagem. Some sozinho.
local function anelVazado(pasta, pos, normal, cor, de, ate, tempo, grossura)
	local o = parte(pasta, "Anel", { Shape = Enum.PartType.Cylinder, Color = cor, Material = Enum.Material.ForceField, Transparency = 0 })
	o.Size = V3(grossura or 0.25, de, de)
	o.CFrame = CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, math.rad(90), 0)
	TweenService:Create(o, TweenInfo.new(tempo, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = V3(0.1, ate, ate), Transparency = 1 }):Play()
	game:GetService("Debris"):AddItem(o, tempo + 0.05)
	return o
end
E.AnelVazado = anelVazado

-- Esfera neon (bola de energia, núcleo)
local function esfera(pasta, nome, cor, material)
	return parte(pasta, nome, { Shape = Enum.PartType.Ball, Color = cor, Material = material or Enum.Material.Neon })
end

-- ⚠️ v113 — "céu" fechado em volta da cena (espaço da Galáxia e da Queda
-- Celestial). Era uma esfera com malha de escala NEGATIVA pra ser vista por
-- dentro, mas o Roblox não desenha mais isso (na revisão a 0,2s o "espaço"
-- mostrava o céu azul e o estádio). Agora são 6 placas Neon escuras: a face de
-- dentro de cada uma aparece. Devolve um objeto em que `.Transparency = x`
-- vale pras 6 (o resto do código continua igual). `piso` (opcional) = altura
-- do chão da sala em relação ao centro (senão, -tamanho/2).
local function salaEscura(pasta, nome, cor, cf, tamanho, piso)
	local meia = tamanho / 2
	local baixo = piso or -meia
	local lados = {
		{ V3(tamanho, 1, tamanho), V3(0, meia, 0) },
		{ V3(tamanho, 0.2, tamanho), V3(0, baixo, 0) },
		{ V3(1, tamanho, tamanho), V3(meia, 0, 0) },
		{ V3(1, tamanho, tamanho), V3(-meia, 0, 0) },
		{ V3(tamanho, tamanho, 1), V3(0, 0, meia) },
		{ V3(tamanho, tamanho, 1), V3(0, 0, -meia) },
	}
	local placas = {}
	for i, l in ipairs(lados) do
		local p = parte(pasta, nome .. i, { Color = cor })
		p.Size = l[1]
		p.CFrame = cf * CFrame.new(l[2])
		p.Transparency = 1
		placas[i] = p
	end
	return setmetatable({ Placas = placas }, {
		__newindex = function(_, k, v)
			for _, p in ipairs(placas) do p[k] = v end
		end,
	})
end

-- Luz pontual numa parte
local function luz(p, cor, alcance, brilho)
	local l = Instance.new("PointLight")
	l.Color = cor
	l.Range = alcance or 0
	l.Brightness = brilho or 3
	l.Shadows = false
	l.Parent = p
	return l
end

-- Bola brilhando por fora (não mexe na física dela)
local function destaque(ball, corDentro, corFora, transp)
	local h = Instance.new("Highlight")
	h.Name = "HissatsuDestaque"
	h.Adornee = ball
	h.FillColor = corDentro
	h.FillTransparency = transp or 0.35
	h.OutlineColor = corFora
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = ball
	return h
end

-- Efeitos de VOO genéricos: presos na bola, se apagam sozinhos. `extra(a,
-- dt, tempo)` roda a cada Heartbeat (pra efeito que precisa se mexer).
local function efeitoDeVoo(ball, duracao, montar, extra)
	local a = Instance.new("Attachment")
	a.Name = "HissatsuVoo"
	a.Parent = ball
	local coisas = { a }
	montar(a, coisas)
	local conexao
	if extra then
		local tempo = 0
		conexao = RunService.Heartbeat:Connect(function(dt)
			tempo += dt
			if not ball.Parent then return end
			pcall(extra, a, dt, tempo)
		end)
	end
	task.delay(duracao, function()
		if conexao then conexao:Disconnect() end
		for _, x in ipairs(coisas) do
			if typeof(x) == "Instance" and x.Parent then x:Destroy() end
		end
	end)
end

-- Duas fitas orbitando a bola no voo (espiral d'água / de gelo)
local function espiralDeVoo(ball, coisas, corHalo, corMiolo, raio, largura)
	local pasta = Instance.new("Folder")
	pasta.Name = "HissatsuEspiralVoo"
	pasta.Parent = workspace
	table.insert(coisas, pasta)
	local fitas = {}
	for i = 1, 2 do
		local p = parte(pasta, "Fita" .. i)
		local r = rastroDuplo(p, largura, corHalo, corMiolo, 0.35)
		r.Ligar(true)
		fitas[i] = p
	end
	return function(_a, _dt, tempo)
		local v = ball.AssemblyLinearVelocity
		local frente = v.Magnitude > 1 and v.Unit or V3(0, 0, -1)
		local lado = frente:Cross(Vector3.yAxis)
		if lado.Magnitude < 0.05 then lado = Vector3.xAxis end
		lado = lado.Unit
		local cima = lado:Cross(frente).Unit
		for i, p in ipairs(fitas) do
			local ang = tempo * math.pi * 2 * 3 + (i - 1) * math.pi
			local pos = ball.Position + (lado * math.cos(ang) + cima * math.sin(ang)) * raio
			p.CFrame = CFrame.fromMatrix(pos, lado, frente)
		end
	end
end

-- ============================================================
-- ⚡ RAIO (Raio Um)
-- ============================================================
function E.Raio(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local AMARELO = rgb(255, 235, 110)
	local BRANCO_AZUL = rgb(215, 235, 255)

	local raioCeu = novoRaio(pasta, rgb(255, 245, 170), 0.5)
	local raioCeu2 = novoRaio(pasta, AMARELO, 0.22)
	local faiscasBola = {}
	for i = 1, 4 do faiscasBola[i] = novoRaio(pasta, BRANCO_AZUL, 0.1) end

	local bolaFx = parte(pasta, "BolaRaio")
	local bolaFaiscas = emissor(bolaFx, {
		Cor = cores({ { 0, rgb(255, 255, 230) }, { 1, rgb(255, 200, 40) } }),
		Tamanho = 0.45, Vida = { 0.15, 0.35 }, Vel = { 6, 14 }, Drag = 4, RotVel = 400,
	})
	local bolaLuz = luz(bolaFx, rgb(255, 230, 120), 0, 5)
	local bolaRastro = rastroDuplo(bolaFx, 0.9, rgb(255, 200, 40), rgb(255, 255, 220), 0.3)

	-- aura elétrica no corpo durante o giro
	local corpoFx = parte(pasta, "AuraRaio")
	corpoFx.Size = V3(3, 5, 3)
	local aura = emissor(corpoFx, {
		Cor = cores({ { 0, rgb(255, 255, 220) }, { 1, rgb(255, 190, 30) } }),
		Tamanho = 0.35, Vida = { 0.1, 0.25 }, Vel = { 1, 4 }, Forma = Enum.ParticleEmitterShape.Box,
		Estilo = Enum.ParticleEmitterShapeStyle.Volume, RotVel = 500,
	})
	local corpoRastro = rastroDuplo(corpoFx, 2.2, rgb(255, 190, 30), rgb(255, 255, 210), 0.25)
	-- ⚠️ v108: o parceiro tem aura/rastro igual
	local parceiroFx = parte(pasta, "AuraRaioParceiro")
	parceiroFx.Size = V3(3, 5, 3)
	local auraParceiro = emissor(parceiroFx, {
		Cor = cores({ { 0, rgb(255, 255, 220) }, { 1, rgb(255, 190, 30) } }),
		Tamanho = 0.35, Vida = { 0.1, 0.25 }, Vel = { 1, 4 }, Forma = Enum.ParticleEmitterShape.Box,
		Estilo = Enum.ParticleEmitterShapeStyle.Volume, RotVel = 500,
	})
	local parceiroRastro = rastroDuplo(parceiroFx, 2.2, rgb(255, 190, 30), rgb(255, 255, 210), 0.25)
	-- arco elétrico entre os dois e a bola no voleio
	local arcos = { novoRaio(pasta, AMARELO, 0.18), novoRaio(pasta, rgb(255, 255, 230), 0.12), novoRaio(pasta, AMARELO, 0.18) }

	-- pé direito carregado no voleio
	local peFx = parte(pasta, "PeRaio")
	local peRastro = rastroDuplo(peFx, 0.8, rgb(255, 200, 40), rgb(255, 255, 230), 0.22)

	local impacto = parte(pasta, "ImpactoRaio")
	local impactoFaiscas = emissor(impacto, {
		Cor = cores({ { 0, rgb(255, 255, 240) }, { 1, rgb(255, 180, 20) } }),
		Tamanho = 0.7, Vida = { 0.2, 0.5 }, Vel = { 25, 50 }, Drag = 4,
	})
	local radiais = {}
	for i = 1, 12 do radiais[i] = novoRaio(pasta, i % 2 == 0 and BRANCO_AZUL or AMARELO, 0.2) end -- ⚠️ v108: explosão maior

	local caiu = false
	local tImpacto = nil
	local ceuTopo = nil

	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local bola = s.BolaMundo
		bolaFx.CFrame = CFrame.new(bola)
		-- giro: aura + rastro em volta do corpo
		local girando = t >= spec.Phases.Spin[1] and t < spec.Phases.Spin[2] + 0.05
		corpoFx.CFrame = ctx.Root.CFrame * CFrame.new(1.4, 0, 0)
		aura.Enabled = girando
		aura.Rate = 90
		corpoRastro.Ligar(girando)
		local parceiro = ctx.Clones and ctx.Clones[1] and ctx.Clones[1].Root
		if parceiro then parceiroFx.CFrame = parceiro.CFrame * CFrame.new(-1.4, 0, 0) end
		auraParceiro.Enabled = girando and parceiro ~= nil
		auraParceiro.Rate = 90
		parceiroRastro.Ligar(girando and parceiro ~= nil)

		-- ⚠️ v108 — no anime não cai raio do céu: os DOIS carregam a bola com
		-- raios amarelos. Arcos saindo de cada corpo até a bola lá em cima.
		local strike = spec.StrikeTime
		if t >= strike and not caiu then
			caiu = true
			ctx.Flash(rgb(255, 250, 220), 0.35, 0.2)
			ctx.Tremer(0.35, 0.2)
			onda(pasta, bola, Vector3.yAxis, AMARELO, 12, 0.3, 0.2)
			bolaFaiscas:Emit(50)
		end
		if caiu and t < strike + 0.45 then
			local transp = phase(t, strike + 0.25, strike + 0.45)
			raioCeu.Desenhar(ctx.Root.Position + V3(0, 1, 0), bola, 9, 1.6, 0.35 + math.random() * 0.15, transp)
			if parceiro then
				raioCeu2.Desenhar(parceiro.Position + V3(0, 1, 0), bola, 9, 1.6, 0.3, transp)
			else
				raioCeu2.Apagar()
			end
		else
			raioCeu.Apagar()
			raioCeu2.Apagar()
		end
		-- no voleio dos dois: arcos ligando os pés e a bola
		local voleio = t >= spec.Phases.Kick[1] - 0.05 and t < spec.ImpactTime + 0.25
		for i, r in ipairs(arcos) do
			if voleio and math.random() < 0.8 then
				local de = i == 1 and s.PePos or (parceiro and parceiro.Position or s.PePos)
				local para = i == 2 and (parceiro and parceiro.Position or bola) or bola
				if i == 2 then de = s.PePos end
				r.Desenhar(de, para, 6, 0.7, 0.12 + math.random() * 0.08, math.random() * 0.25)
			else
				r.Apagar()
			end
		end

		-- bola eletrizada depois do raio: faíscas em arco em volta dela
		local eletrica = caiu
		for i, r in ipairs(faiscasBola) do
			if eletrica and math.random() < 0.7 then
				local d = V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
				if d.Magnitude < 0.05 then d = Vector3.xAxis end
				r.Desenhar(bola + d.Unit * 0.7, bola + d.Unit * (1.8 + math.random() * 1.2), 4, 0.45, 0.08 + i * 0.01, math.random() * 0.3)
			else
				r.Apagar()
			end
		end
		bolaFaiscas.Enabled = eletrica
		bolaFaiscas.Rate = s.ImpactoFeito and 90 or 45
		bolaRastro.Ligar(t >= 0.14)
		bolaLuz.Range = eletrica and (14 + math.sin(t * 60) * 3) or 0

		-- pé carregado do voleio
		peFx.CFrame = CFrame.new(s.PePos)
		peRastro.Ligar(t >= spec.Phases.Cock[1] and t < spec.ImpactTime + 0.1)

		-- raios radiais do impacto piscam por 0.3s
		if tImpacto then
			local k = phase(t, tImpacto, tImpacto + 0.3)
			for _, r in ipairs(radiais) do
				if k < 1 and math.random() < 0.8 then
					local d = V3(math.random() - 0.5, (math.random() - 0.3) * 0.8, math.random() - 0.5)
					if d.Magnitude < 0.05 then d = Vector3.xAxis end
					r.Desenhar(impacto.Position, impacto.Position + d.Unit * (8 + math.random() * 9), 8, 1.6, 0.2, k)
				else
					r.Apagar()
				end
			end
		end
	end
	function efeitos.Impacto(s)
		tImpacto = s.T
		impacto.CFrame = CFrame.new(s.BolaMundo)
		impactoFaiscas:Emit(160)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, AMARELO, 30, 0.3, 0.35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, rgb(255, 255, 240), 18, 0.2, 0.25)
		onda(pasta, s.BolaMundo, Vector3.yAxis, AMARELO, 16, 0.3, 0.2)
		ctx.Flash(rgb(255, 245, 190), 0.25, 0.25)
	end
	function efeitos.Voo(ball, duracao)
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, {
				Cor = cores({ { 0, rgb(255, 255, 230) }, { 1, rgb(255, 190, 30) } }),
				Tamanho = 0.5, Vida = { 0.15, 0.35 }, Vel = { 5, 12 }, Drag = 4, RotVel = 400, Taxa = 70,
			})
			luz(a, rgb(255, 230, 120), 18, 5)
			local a0 = Instance.new("Attachment") a0.Position = V3(0, -0.9, 0) a0.Parent = ball
			local a1 = Instance.new("Attachment") a1.Position = V3(0, 0.9, 0) a1.Parent = ball
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Lifetime = 0.35
			tr.LightEmission = 1
			tr.LightInfluence = 0
			tr.FaceCamera = true
			tr.Color = cores({ { 0, rgb(255, 255, 220) }, { 1, rgb(255, 170, 0) } })
			tr.Transparency = numeros({ { 0, 0 }, { 1, 1 } })
			tr.WidthScale = numeros({ { 0, 1.6 }, { 1, 0.1 } })
			tr.Parent = ball
			table.insert(coisas, a0)
			table.insert(coisas, a1)
			table.insert(coisas, tr)
			table.insert(coisas, destaque(ball, rgb(255, 230, 90), rgb(255, 255, 220), 0.35))
			-- faíscas em arco em volta da bola, no voo também
			local pastaVoo = Instance.new("Folder")
			pastaVoo.Name = "HissatsuRaioVoo"
			pastaVoo.Parent = workspace
			table.insert(coisas, pastaVoo)
			coisas.Faiscas = { novoRaio(pastaVoo, rgb(215, 235, 255), 0.1), novoRaio(pastaVoo, rgb(255, 235, 110), 0.1) }
			ctx._faiscasVoo = coisas.Faiscas
		end, function()
			for _, r in ipairs(ctx._faiscasVoo or {}) do
				if math.random() < 0.6 then
					local d = V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					if d.Magnitude < 0.05 then d = Vector3.xAxis end
					r.Desenhar(ball.Position + d.Unit * 0.7, ball.Position + d.Unit * 2.2, 4, 0.4, 0.09, 0.1)
				else
					r.Apagar()
				end
			end
		end)
	end
	return efeitos
end

-- ============================================================
-- ⛩️ SUMIÇO
-- ============================================================
-- duração do voo do Sumiço guardada no ctx (efeitos.Voo recebe; o Heartbeat lê)
local function duracaoVooSumico(ctx) return ctx._sumicoDuracao or 99 end

function E.Sumico(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local ROXO = rgb(170, 70, 255)
	local ROSA = rgb(255, 150, 255)
	local ESCURO = rgb(45, 0, 70)

	-- névoa roxa escura rente ao chão
	local nevoa = parte(pasta, "NevoaRoxa")
	nevoa.Size = V3(34, 1, 34)
	nevoa.CFrame = CFrame.new(mundo(V3(0, ctx.ChaoY + 0.5, -4)))
	local nevoaEmissor = emissor(nevoa, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(90, 30, 140) }, { 1, rgb(30, 0, 50) } }), Brilho = 0.2,
		Tamanho = numeros({ { 0, 3 }, { 0.5, 6 }, { 1, 8 } }), Transp = numeros({ { 0, 1 }, { 0.3, 0.55 }, { 1, 1 } }),
		Vida = { 1.5, 2.5 }, Vel = { 0.5, 1.5 }, Spread = 30, Acel = V3(0, 0.6, 0), Drag = 0.5,
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, ZOffset = -1,
	})

	-- ⛩️ o torii (peças neon vermelho-escuro, com brilho roxo)
	local base = spec.ToriiBase
	local toriiPartes = {}
	local function peca(nome, tamanho, pos, rot)
		local p = parte(pasta, "Torii" .. nome, { Color = rgb(150, 20, 55), Material = Enum.Material.Neon })
		p.Size = tamanho
		p.CFrame = ctx.Inicio * CFrame.new(base + pos) * (rot or CFrame.identity)
		table.insert(toriiPartes, p)
		return p
	end
	peca("PilarE", V3(0.9, 8, 0.9), V3(-3.2, 4, 0))
	peca("PilarD", V3(0.9, 8, 0.9), V3(3.2, 4, 0))
	peca("KasagiE", V3(5.2, 0.8, 1.2), V3(-2.45, 8.35, 0), CFrame.Angles(0, 0, math.rad(-4)))
	peca("KasagiD", V3(5.2, 0.8, 1.2), V3(2.45, 8.35, 0), CFrame.Angles(0, 0, math.rad(4)))
	peca("Shimaki", V3(8.8, 0.5, 1), V3(0, 7.7, 0))
	peca("Nuki", V3(7.8, 0.55, 0.7), V3(0, 6.3, 0))
	peca("Gakuzuka", V3(0.5, 1.2, 0.5), V3(0, 7.0, 0))
	-- portal entre os pilares
	local portal = parte(pasta, "PortalRoxo", { Color = rgb(120, 40, 220) })
	portal.Size = V3(5.4, 6, 0.1)
	portal.CFrame = ctx.Inicio * CFrame.new(base + V3(0, 3.1, 0))
	local portalGiro = emissor(portal, {
		Cor = cores({ { 0, ROSA }, { 1, ROXO } }), Tamanho = 0.6, Vida = { 0.5, 1 }, Vel = { 1, 3 },
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, RotVel = 300,
	})
	local portalLuz = luz(portal, ROXO, 0, 4)

	-- bola: rastro de redemoinho roxo
	local bolaFx = parte(pasta, "BolaRoxa")
	local bolaRastro = rastroDuplo(bolaFx, 0.95, ROXO, rgb(255, 210, 255), 0.55)
	local bolaBrilho = emissor(bolaFx, { Cor = cores({ { 0, ROSA }, { 1, ROXO } }), Tamanho = 0.5, Vida = { 0.3, 0.6 }, Vel = { 1, 3 } })
	local bolaLuz = luz(bolaFx, ROXO, 0, 4)

	-- redemoinho que devolve a bola no pé
	local volta = {}
	for i = 1, 4 do
		local p = parte(pasta, "Redemoinho" .. i)
		volta[i] = { Parte = p, Rastro = rastroDuplo(p, 0.6, ROXO, rgb(255, 220, 255), 0.35) }
	end

	local impacto = parte(pasta, "ImpactoRoxo")
	local impactoBrilho = emissor(impacto, { Cor = cores({ { 0, rgb(255, 230, 255) }, { 1, ROXO } }), Tamanho = 0.8, Vida = { 0.25, 0.6 }, Vel = { 20, 40 }, Drag = 4 })

	local sumiu, voltou = false, false
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		nevoaEmissor.Enabled = t < spec.Duration - 0.3
		nevoaEmissor.Rate = 25

		-- torii: nasce transparente, fica, e se desfaz depois do chute
		local aparece = smooth(phase(t, ph.Torii[1], ph.Torii[2]))
		local some = smooth(phase(t, ph.ToriiOut[1], ph.ToriiOut[2]))
		local alfa = aparece * (1 - some)
		for _, p in ipairs(toriiPartes) do
			p.Transparency = 1 - alfa * 0.95
		end
		portal.Transparency = 1 - alfa * (0.35 + 0.15 * math.sin(t * 9))
		portalGiro.Enabled = alfa > 0.1
		portalGiro.Rate = 60
		portalLuz.Range = 18 * alfa

		-- bola
		local visivel = s.BolaVisivel
		bolaFx.CFrame = CFrame.new(s.BolaMundo)
		bolaRastro.Ligar(visivel and t >= ph.Spiral[1])
		bolaBrilho.Enabled = visivel and t >= ph.Spiral[1]
		bolaBrilho.Rate = 40
		bolaLuz.Range = visivel and 12 or 0

		if not sumiu and t >= ph.Vanish[1] then
			sumiu = true
			local p = mundo(spec.Portal)
			impacto.CFrame = CFrame.new(p)
			impactoBrilho:Emit(60)
			onda(pasta, p, ctx.Inicio.LookVector, ROXO, 12, 0.35, 0.2)
			ctx.Flash(rgb(200, 130, 255), 0.55, 0.25)
		end

		-- redemoinho: 4 fitas espiralando PRA DENTRO até o ponto do chute
		local k = phase(t, ph.Reappear[1], ph.Vanish[2] + 0.05)
		local centro = mundo(spec.KickPoint + V3(0, 1.3, 0))
		for i, v in ipairs(volta) do
			local ativo = t >= ph.Reappear[1] and t < ph.Vanish[2] + 0.08
			local ang = t * math.pi * 2 * 2.5 + (i - 1) * math.pi / 2
			local r = 3.2 * (1 - k) + 0.3
			local pos = centro + ctx.Inicio:VectorToWorldSpace(V3(math.cos(ang) * r, math.sin(t * 7 + i) * 0.4, math.sin(ang) * r))
			v.Parte.CFrame = CFrame.new(pos)
			v.Rastro.Ligar(ativo)
		end
		if not voltou and t >= ph.Vanish[2] then
			voltou = true
			impacto.CFrame = CFrame.new(centro)
			impactoBrilho:Emit(45)
			onda(pasta, centro, Vector3.yAxis, ROSA, 8, 0.25, 0.15)
		end
	end
	function efeitos.Impacto(s)
		impacto.CFrame = CFrame.new(s.BolaMundo)
		impactoBrilho:Emit(90)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, ROXO, 22, 0.32, 0.3)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, ESCURO, 14, 0.25, 0.25)
	end
	function efeitos.Voo(ball, duracao)
		ctx._sumicoDuracao = duracao
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, { Cor = cores({ { 0, ROSA }, { 1, ROXO } }), Tamanho = 0.7, Vida = { 0.3, 0.6 }, Vel = { 1, 3 }, Taxa = 80 })
			emissor(a, {
				Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(120, 40, 190) }, { 1, rgb(30, 0, 50) } }), Brilho = 0.4,
				Tamanho = numeros({ { 0, 1.5 }, { 1, 3.5 } }), Transp = numeros({ { 0, 0.4 }, { 1, 1 } }),
				Vida = { 0.4, 0.8 }, Vel = { 0.5, 1.5 }, Taxa = 40,
			})
			luz(a, ROXO, 16, 4)
			table.insert(coisas, destaque(ball, rgb(150, 60, 255), rgb(255, 200, 255), 0.4))
			coisas.Espiral = espiralDeVoo(ball, coisas, ROXO, rgb(255, 215, 255), 1.3, 0.7)
			ctx._espiralSumico = coisas.Espiral
			-- ⚠️ v106 — PEDIDO: "no Sumiço a bola tem que sumir e reaparecer pra
			-- confundir". Pisca no voo: some ~0.25s a cada 0.6s (bola, brilho,
			-- espiral e destaque somem juntos) deixando 2 bolas-FANTASMA que
			-- saem pros lados e se desfazem; reaparece com um estouro roxo.
			local fantasmas = Instance.new("Folder")
			fantasmas.Name = "SumicoFantasmas"
			fantasmas.Parent = workspace
			table.insert(coisas, fantasmas)
			for _, x in ipairs(coisas) do
				if typeof(x) == "Instance" and x:IsA("Folder") and x.Name == "HissatsuEspiralVoo" then ctx._sumicoEspiral = x end
			end
			ctx._sumicoFantasmas = fantasmas
			ctx._sumicoSumida = false
			task.delay(duracao, function()
				if ball.Parent then ball.LocalTransparencyModifier = 0 end
			end)
		end, function(a, dt, tempo)
			if ctx._espiralSumico then ctx._espiralSumico(a, dt, tempo) end
			local ciclo = (tempo - 0.3) % 0.6
			local sumida = tempo > 0.3 and tempo < duracaoVooSumico(ctx) - 0.2 and ciclo < 0.25
			if sumida ~= ctx._sumicoSumida then
				ctx._sumicoSumida = sumida
				ball.LocalTransparencyModifier = sumida and 1 or 0
				for _, x in ipairs(a:GetChildren()) do
					if x:IsA("ParticleEmitter") or x:IsA("PointLight") then x.Enabled = not sumida end
				end
				for _, x in ipairs(ball:GetChildren()) do
					if x.Name == "HissatsuDestaque" and x:IsA("Highlight") then x.Enabled = not sumida end
				end
				if ctx._sumicoEspiral then
					for _, tr in ipairs(ctx._sumicoEspiral:GetDescendants()) do
						if tr:IsA("Trail") then tr.Enabled = not sumida end
					end
				end
				local pasta = ctx._sumicoFantasmas
				if pasta and pasta.Parent then
					-- estouro de fumaça roxa onde ela some/volta
					local puf = parte(pasta, "Puf", { Transparency = 1 })
					puf.CFrame = CFrame.new(ball.Position)
					local e = emissor(puf, {
						Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(200, 120, 255) }, { 1, rgb(40, 0, 70) } }), Brilho = 0.5,
						Tamanho = numeros({ { 0, 1.5 }, { 1, 4 } }), Transp = numeros({ { 0, 0.3 }, { 1, 1 } }),
						Vida = { 0.25, 0.45 }, Vel = { 4, 9 }, Spread = 180, Taxa = 0,
					})
					e:Emit(sumida and 18 or 12)
					game:GetService("Debris"):AddItem(puf, 0.6)
					if sumida then
						local v = ball.AssemblyLinearVelocity
						local frente = v.Magnitude > 1 and v.Unit or V3(0, 0, -1)
						local lado = frente:Cross(Vector3.yAxis)
						lado = lado.Magnitude > 0.05 and lado.Unit or Vector3.xAxis
						for _, sinal in ipairs({ -1, 1 }) do
							local g = parte(pasta, "Fantasma", { Shape = Enum.PartType.Ball, Color = rgb(190, 110, 255), Transparency = 0.25 })
							g.Size = ball.Size
							g.CFrame = CFrame.new(ball.Position)
							local destino = ball.Position + v * 0.3 + lado * sinal * (3 + math.random() * 2) + V3(0, math.random() * 1.5, 0)
							TweenService:Create(g, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								CFrame = CFrame.new(destino), Transparency = 1,
							}):Play()
							game:GetService("Debris"):AddItem(g, 0.4)
						end
					end
				end
			end
		end)
	end
	return efeitos
end

-- ============================================================
-- 🌊 MARÉ (Impulso de Maré)
-- ============================================================
function E.Mare(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local AGUA = rgb(25, 110, 215)
	local AGUA_CLARA = rgb(120, 205, 255)
	local ESPUMA = rgb(240, 250, 255)
	local largura = spec.OndaLargura

	-- ondas: um segmento por trecho do perfil (duas camadas: corpo "vidro"
	-- azul + brilho claro por cima), espuma na crista e no lábio
	local segmentos = {}
	for i = 1, #spec.Onda - 1 do
		local corpo = parte(pasta, "Onda" .. i, { Material = Enum.Material.Glass, Color = AGUA:Lerp(AGUA_CLARA, i / #spec.Onda) })
		local brilho = parte(pasta, "OndaBrilho" .. i, { Material = Enum.Material.Neon, Color = AGUA_CLARA })
		local espuma
		if i >= spec.OndaCrista - 2 then
			espuma = emissor(corpo, {
				Textura = TEX.Fumaca, Cor = ESPUMA, Brilho = 0.35,
				Tamanho = numeros({ { 0, 2.5 }, { 0.6, 4.5 }, { 1, 6 } }), Transp = numeros({ { 0, 0.25 }, { 1, 1 } }),
				Vida = { 0.5, 0.9 }, Vel = { 3, 7 }, Spread = 35, Acel = V3(0, -6, 0), Drag = 1.5,
				Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Surface,
				Direcao = Enum.NormalId.Top, ZOffset = 0.5,
			})
		end
		segmentos[i] = { Corpo = corpo, Brilho = brilho, Espuma = espuma }
	end
	-- respingo (gotas) na crista inteira
	local cristaFx = parte(pasta, "CristaGotas")
	local gotas = emissor(cristaFx, {
		Cor = cores({ { 0, ESPUMA }, { 1, AGUA_CLARA } }), Tamanho = 0.35, Vida = { 0.5, 1 }, Vel = { 6, 14 }, Spread = 50,
		Acel = V3(0, -30, 0), Drag = 0.5, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
	})
	-- lâmina d'água cobrindo o gramado
	local lamina = parte(pasta, "LaminaAgua", { Material = Enum.Material.Glass, Color = AGUA })
	lamina.Size = V3(60, 0.3, 60)

	-- espuma nos pés enquanto surfa (a bola é a prancha)
	local pranchaFx = parte(pasta, "PranchaEspuma")
	local pranchaEspuma = emissor(pranchaFx, {
		Textura = TEX.Fumaca, Cor = ESPUMA, Brilho = 0.3, Tamanho = numeros({ { 0, 1.2 }, { 1, 3 } }),
		Transp = numeros({ { 0, 0.3 }, { 1, 1 } }), Vida = { 0.3, 0.6 }, Vel = { 3, 7 }, Spread = 60, Acel = V3(0, -10, 0),
	})
	local pranchaGotas = emissor(pranchaFx, { Cor = ESPUMA, Tamanho = 0.3, Vida = { 0.3, 0.7 }, Vel = { 5, 11 }, Spread = 70, Acel = V3(0, -30, 0) })
	local bolaRastro = rastroDuplo(pranchaFx, 0.9, AGUA_CLARA, ESPUMA, 0.4)

	-- véu d'água em volta da bola (a partir do chute)
	local veu = esfera(pasta, "VeuAgua", AGUA_CLARA, Enum.Material.Glass)
	veu.Size = Vector3.one * (ctx.TamanhoBola * 1.5)

	-- perna da bicicleta: rastro d'água
	local peFx = parte(pasta, "PeAgua")
	local peRastro = rastroDuplo(peFx, 0.9, AGUA_CLARA, ESPUMA, 0.3)

	local impacto = parte(pasta, "ImpactoAgua")
	local impactoGotas = emissor(impacto, { Cor = cores({ { 0, ESPUMA }, { 1, AGUA_CLARA } }), Tamanho = 0.5, Vida = { 0.4, 0.9 }, Vel = { 18, 40 }, Acel = V3(0, -40, 0), Drag = 1 })
	local impactoEspuma = emissor(impacto, {
		Textura = TEX.Fumaca, Cor = ESPUMA, Brilho = 0.4, Tamanho = numeros({ { 0, 3 }, { 1, 9 } }),
		Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.4, 0.8 }, Vel = { 10, 22 }, Drag = 3,
	})

	local ultimoAnel = -1
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		-- ⚠️ v108 — anime (8.5-10s do vídeo): ANÉIS d'água concêntricos atrás dele
		-- enquanto surfa — o "tubo" da onda. Um anel a cada 0.14s, na direção em
		-- que ele sobe a rampa.
		if t >= ph.Hop[2] and t < ph.Leap[2] and t - ultimoAnel > 0.14 then
			ultimoAnel = t
			local dir = ctx.Inicio:VectorToWorldSpace(V3(0, 0.55, -1).Unit)
			local pos = ctx.Root.Position - dir * 1.2
			anelVazado(pasta, pos, dir, AGUA_CLARA, 4, 12, 0.45, 0.3)
			anelVazado(pasta, pos - dir * 0.6, dir, ESPUMA, 3, 8, 0.35, 0.2)
		end
		-- onda: mesma geometria que a bola percorre (HissatsuCutscenes)
		local h = spec.OndaAltura(t)
		local o = spec.OndaOrigem(t)
		local fim = phase(t, 2.5, spec.Duration)
		local alfaOnda = (1 - fim) * math.clamp(h * 2, 0, 1)
		for i, seg in ipairs(segmentos) do
			local a, b = spec.Onda[i], spec.Onda[i + 1]
			-- o lábio (depois da crista) cai pra frente quando a onda quebra
			local queda = i >= spec.OndaCrista and smooth(phase(t, ph.Break[1], ph.Break[2])) * 3 or 0
			local pa = o + V3(0, a[2] * h - (i > spec.OndaCrista and queda or 0), a[1] - (i >= spec.OndaCrista and queda * 0.4 or 0))
			local pb = o + V3(0, b[2] * h - queda, b[1] - queda * 0.4)
			local d = pb - pa
			local len = math.max(d.Magnitude, 0.1)
			local eixo = d / len
			local meio = (pa + pb) / 2
			local cf = ctx.Inicio * CFrame.fromMatrix(meio, Vector3.xAxis, eixo)
			seg.Corpo.CFrame = cf
			seg.Corpo.Size = V3(largura, len + 0.3, 1.1)
			seg.Corpo.Transparency = 1 - alfaOnda * 0.7
			seg.Brilho.CFrame = cf * CFrame.new(0, 0, 0.35)
			seg.Brilho.Size = V3(largura, len + 0.3, 0.4)
			seg.Brilho.Transparency = 1 - alfaOnda * 0.22
			if seg.Espuma then
				seg.Espuma.Enabled = alfaOnda > 0.2
				seg.Espuma.Rate = 35
			end
		end
		local cristaLocal = o + V3(0, spec.Onda[spec.OndaCrista][2] * h, spec.Onda[spec.OndaCrista][1])
		cristaFx.CFrame = ctx.Inicio * CFrame.new(cristaLocal)
		cristaFx.Size = V3(largura, 1, 2)
		gotas.Enabled = alfaOnda > 0.3
		gotas.Rate = 120

		lamina.CFrame = CFrame.new(mundo(V3(0, ctx.ChaoY + 0.05, -4)))
		lamina.Transparency = 1 - 0.55 * smooth(phase(t, 0.1, 0.5)) * (1 - fim)

		-- surfe: espuma e gotas saindo debaixo da bola
		local surfando = t >= ph.Hop[2] and t < ph.Ride[2]
		pranchaFx.CFrame = CFrame.new(s.BolaMundo + V3(0, -0.6, 0))
		pranchaEspuma.Enabled = surfando
		pranchaEspuma.Rate = 60
		pranchaGotas.Enabled = surfando
		pranchaGotas.Rate = 50
		bolaRastro.Ligar(t >= ph.Hop[2])

		veu.CFrame = CFrame.new(s.BolaMundo)
		veu.Transparency = s.ImpactoFeito and (0.45 + 0.1 * math.sin(t * 20)) or 1

		peFx.CFrame = CFrame.new(s.PePos)
		peRastro.Ligar(t >= ph.Flip[1] and t < spec.ImpactTime + 0.1)
	end
	function efeitos.Impacto(s)
		impacto.CFrame = CFrame.new(s.BolaMundo)
		impactoGotas:Emit(140)
		impactoEspuma:Emit(40)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, AGUA_CLARA, 26, 0.35, 0.35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, ESPUMA, 15, 0.25, 0.3)
	end
	function efeitos.Voo(ball, duracao)
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, { Cor = cores({ { 0, ESPUMA }, { 1, AGUA_CLARA } }), Tamanho = 0.35, Vida = { 0.3, 0.6 }, Vel = { 2, 6 }, Acel = V3(0, -25, 0), Taxa = 90 })
			emissor(a, {
				Textura = TEX.Fumaca, Cor = ESPUMA, Brilho = 0.3, Tamanho = numeros({ { 0, 1.2 }, { 1, 2.8 } }),
				Transp = numeros({ { 0, 0.35 }, { 1, 1 } }), Vida = { 0.25, 0.5 }, Vel = { 0.5, 2 }, Taxa = 45,
			})
			luz(a, AGUA_CLARA, 14, 3)
			table.insert(coisas, destaque(ball, AGUA_CLARA, ESPUMA, 0.45))
			coisas.Espiral = espiralDeVoo(ball, coisas, AGUA_CLARA, ESPUMA, 1.4, 0.8)
			ctx._espiralMare = coisas.Espiral
			-- ⚠️ v108 — anime (16-18s): a bola vai pro gol dentro de um TÚNEL d'água
			local pastaTunel = Instance.new("Folder")
			pastaTunel.Name = "HissatsuTunelAgua"
			pastaTunel.Parent = workspace
			table.insert(coisas, pastaTunel)
			ctx._tunelMare = { Pasta = pastaTunel, Ultimo = -1 }
		end, function(a, dt, tempo)
			if ctx._espiralMare then ctx._espiralMare(a, dt, tempo) end
			local tun = ctx._tunelMare
			if tun and tempo - tun.Ultimo > 0.09 then
				tun.Ultimo = tempo
				local v = ball.AssemblyLinearVelocity
				if v.Magnitude > 5 then
					anelVazado(tun.Pasta, ball.Position, v.Unit, AGUA_CLARA, 2.5, 7, 0.4, 0.22)
				end
			end
		end)
	end
	return efeitos
end

-- ============================================================
-- ❄️ GELO (Fúria Glacial)
-- ============================================================
function E.Gelo(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local GELO = rgb(185, 230, 255)
	local CIANO = rgb(120, 220, 255)
	local BRANCO = rgb(245, 252, 255)

	-- disco de gelo que se espalha pelo campo
	local disco = parte(pasta, "DiscoGelo", { Shape = Enum.PartType.Cylinder, Material = Enum.Material.Ice, Color = GELO })
	local discoBrilho = parte(pasta, "DiscoGeloBrilho", { Shape = Enum.PartType.Cylinder, Color = CIANO })

	-- cristais que brotam do chão
	local cristais = {}
	-- ⚠️ v106 — PEDIDO: "Fúria Glacial: gelo maior e uma nevasca leve". Eram 16
	-- cristais de 1.5-4.2 studs até 15 de distância; agora 26 de 2.5-7 até 21, e
	-- 5 PICOS gigantes (9-14 studs) brotando por último, atrás e dos lados.
	local rng = Random.new(7)
	for i = 1, 26 do
		local ang = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(3.5, 21)
		local altura = rng:NextNumber(2.5, 7)
		local p = parte(pasta, "Cristal" .. i, { Material = Enum.Material.Ice, Color = GELO:Lerp(BRANCO, rng:NextNumber()) })
		-- ⚠️ v113: ele corre e dá o mortal pra frente (até ~9 studs): nenhum
		-- cristal nesse corredor, nem do lado direito dele (a câmera da corrida e do
		-- mortal fica ali: os cristais tapavam tudo)
		local cx, cz = math.cos(ang) * dist, math.sin(ang) * dist - 2
		if cx > -3.5 and cx < 15 and cz > -14 and cz < 3 then cx = -(3.5 + math.abs(cx) * 0.6) end
		cristais[i] = {
			Parte = p, Base = V3(cx, ctx.ChaoY, cz),
			Altura = altura, Largura = rng:NextNumber(0.8, 1.9),
			Inclina = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)),
			Quando = 0.35 + (dist / 21) * 0.7,
		}
	end
	for i = 1, 5 do
		local ang = math.pi * (0.15 + 0.175 * (i - 1)) -- leque atrás/dos lados do batedor
		local dist = rng:NextNumber(10, 16)
		local p = parte(pasta, "Pico" .. i, { Material = Enum.Material.Ice, Color = GELO:Lerp(BRANCO, 0.3) })
		table.insert(cristais, {
			Parte = p, Base = V3(math.cos(ang) * dist, ctx.ChaoY, math.sin(ang) * dist + 1),
			Altura = rng:NextNumber(9, 14), Largura = rng:NextNumber(2.2, 3.2),
			Inclina = CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)),
			Quando = 1.0 + i * 0.07,
		})
	end
	-- névoa gelada e neve no ar
	local nevoa = parte(pasta, "NevoaGelo")
	nevoa.Size = V3(44, 1, 44)
	nevoa.CFrame = CFrame.new(mundo(V3(0, ctx.ChaoY + 0.4, -2)))
	local nevoaEmissor = emissor(nevoa, {
		Textura = TEX.Fumaca, Cor = rgb(220, 240, 255), Brilho = 0.2, Tamanho = numeros({ { 0, 2 }, { 1, 6 } }),
		Transp = numeros({ { 0, 1 }, { 0.3, 0.6 }, { 1, 1 } }), Vida = { 1.2, 2 }, Vel = { 0.5, 1.5 }, Spread = 40,
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, ZOffset = -1,
	})
	-- nevasca leve: neve de lado (vento) numa área bem maior + rajadas de
	-- névoa correndo rente ao chão
	local vento = ctx.Inicio:VectorToWorldSpace(V3(1, 0, 0.35)).Unit
	local ar = parte(pasta, "NeveAr")
	ar.Size = V3(52, 16, 52)
	ar.CFrame = CFrame.new(mundo(V3(0, 5, -2)))
	local neve = emissor(ar, {
		Cor = BRANCO, Tamanho = numeros({ { 0, 0.3 }, { 1, 0.18 } }), Vida = { 1.4, 2.4 }, Vel = { 0.3, 1 },
		Acel = vento * 14 + V3(0, -4, 0), Drag = 0.6,
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, RotVel = 180,
	})
	local rajada = emissor(ar, {
		Textura = TEX.Fumaca, Cor = rgb(235, 248, 255), Brilho = 0.25, Tamanho = numeros({ { 0, 3 }, { 1, 8 } }),
		Transp = numeros({ { 0, 1 }, { 0.25, 0.72 }, { 1, 1 } }), Vida = { 0.9, 1.5 }, Vel = { 0.5, 1 },
		Acel = vento * 30, Drag = 0.4, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
		ZOffset = -1, Taxa = 0,
	})

	-- perna direita: rastro gelado na puxada e no chute
	local peFx = parte(pasta, "PeGelo")
	local peRastro = rastroDuplo(peFx, 0.8, CIANO, BRANCO, 0.4)
	local peNeve = emissor(peFx, { Cor = BRANCO, Tamanho = 0.3, Vida = { 0.3, 0.6 }, Vel = { 1, 3 } })

	-- a bola congela (cristal em volta)
	local casca = esfera(pasta, "CascaGelo", GELO, Enum.Material.Ice)
	casca.Size = Vector3.one * (ctx.TamanhoBola * 1.18)

	-- rachadura: zigue-zague no chão, do ponto do chute pro gol
	local rachaduras = {}
	local pontos = { V3(0, 0, 0) }
	local rngR = Random.new(11)
	for i = 1, 14 do
		local ult = pontos[#pontos]
		table.insert(pontos, ult + V3(rngR:NextNumber(-1.4, 1.4), 0, -rngR:NextNumber(2.2, 3.2)))
	end
	for i = 1, #pontos - 1 do
		rachaduras[i] = parte(pasta, "Rachadura" .. i, { Color = CIANO })
	end
	local galhos = {}
	for i = 1, 8 do galhos[i] = parte(pasta, "Galho" .. i, { Color = BRANCO }) end

	local impacto = parte(pasta, "ImpactoGelo")
	local estilhacos = emissor(impacto, { Cor = cores({ { 0, BRANCO }, { 1, CIANO } }), Tamanho = 0.55, Vida = { 0.35, 0.8 }, Vel = { 20, 42 }, Acel = V3(0, -25, 0), Drag = 1.5, RotVel = 400 })
	local geada = emissor(impacto, {
		Textura = TEX.Fumaca, Cor = rgb(220, 245, 255), Brilho = 0.35, Tamanho = numeros({ { 0, 2 }, { 1, 7 } }),
		Transp = numeros({ { 0, 0.3 }, { 1, 1 } }), Vida = { 0.4, 0.8 }, Vel = { 8, 16 }, Drag = 3,
	})

	local tImpacto = nil
	local origemRachadura = nil

	-- ⚠️ v108 — ANIME (vídeo "Inazuma Eleven - Freeze Shot", quadros a cada 0,5s,
	-- 5.0s): quando o campo congela, uma NÉVOA branca gelada ROLA pelo gramado
	-- saindo dele pra todos os lados. Emissor em cilindro soltando pra fora
	-- (radial, rente ao chão).
	local rolaFx = parte(pasta, "NevoaRolando")
	rolaFx.Size = V3(3, 0.6, 3)
	rolaFx.CFrame = CFrame.new(mundo(V3(0, ctx.ChaoY + 0.6, -1)))
	local nevoaRolando = emissor(rolaFx, {
		Textura = TEX.Fumaca, Cor = rgb(240, 250, 255), Brilho = 0.3,
		Tamanho = numeros({ { 0, 2.5 }, { 0.5, 6 }, { 1, 9 } }), Transp = numeros({ { 0, 0.15 }, { 0.6, 0.5 }, { 1, 1 } }),
		Vida = { 1.0, 1.5 }, Vel = { 20, 30 }, Drag = 1.3, Spread = 5, RotVel = 40,
		Forma = Enum.ParticleEmitterShape.Cylinder, Estilo = Enum.ParticleEmitterShapeStyle.Surface,
		Sentido = Enum.ParticleEmitterShapeInOut.Outward, Direcao = Enum.NormalId.Top, ZOffset = -0.5,
	})
	local rolou = false

	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		if not rolou and t >= ph.Freeze[1] then
			rolou = true
			nevoaRolando:Emit(90)
			task.delay(0.15, function() if nevoaRolando.Parent then nevoaRolando:Emit(60) end end)
		end
		-- disco espalhando
		local r = 32 * easeOut(phase(t, ph.Freeze[1], ph.Freeze[2]))
		local fim = phase(t, spec.Duration - 0.35, spec.Duration)
		disco.Size = V3(0.12, math.max(r * 2, 0.1), math.max(r * 2, 0.1))
		disco.CFrame = CFrame.new(mundo(V3(0, ctx.ChaoY + 0.02, -1))) * CFrame.Angles(0, 0, math.rad(90))
		disco.Transparency = r > 0.1 and (0.25 + 0.75 * fim) or 1
		discoBrilho.Size = V3(0.05, math.max(r * 2 + 0.6, 0.1), math.max(r * 2 + 0.6, 0.1))
		discoBrilho.CFrame = disco.CFrame * CFrame.new(-0.05, 0, 0)
		discoBrilho.Transparency = r > 0.1 and (0.8 + 0.2 * fim) or 1

		for _, c in ipairs(cristais) do
			local k = easeOut(phase(t, c.Quando, c.Quando + 0.18))
			local sobe = c.Altura * k
			c.Parte.Size = V3(c.Largura, math.max(sobe, 0.05), c.Largura)
			c.Parte.CFrame = ctx.Inicio * CFrame.new(c.Base) * c.Inclina * CFrame.new(0, sobe / 2, 0)
			c.Parte.Transparency = k > 0 and (0.1 + 0.9 * fim) or 1
		end

		nevoaEmissor.Enabled = t >= ph.Freeze[1] and t < spec.Duration - 0.3
		nevoaEmissor.Rate = 20
		neve.Enabled = t >= ph.Freeze[1]
		neve.Rate = 170
		rajada.Enabled = t >= ph.Freeze[1] and t < spec.Duration - 0.3
		rajada.Rate = 14

		peFx.CFrame = CFrame.new(s.PePos)
		local chutando = t >= ph.Windup[1] and t < spec.ImpactTime + 0.12
		peRastro.Ligar(chutando)
		peNeve.Enabled = chutando
		peNeve.Rate = 50

		casca.CFrame = CFrame.new(s.BolaMundo)
		local gelada = smooth(phase(t, 0.35, 0.8))
		casca.Transparency = 1 - gelada * (s.ImpactoFeito and 0.45 or 0.6)

		-- rachadura correndo pelo chão depois do chute
		if tImpacto then
			local k = phase(t, tImpacto, tImpacto + 0.35)
			local visiveis = math.floor(k * #rachaduras + 0.5)
			for i, p in ipairs(rachaduras) do
				if i <= visiveis then
					local a = origemRachadura + ctx.Inicio:VectorToWorldSpace(pontos[i])
					local b = origemRachadura + ctx.Inicio:VectorToWorldSpace(pontos[i + 1])
					local len = (b - a).Magnitude
					p.Size = V3(0.28, 0.08, len)
					p.CFrame = CFrame.lookAt((a + b) / 2, b)
					p.Transparency = 0.05 + 0.95 * fim
				else
					p.Transparency = 1
				end
			end
			for i, g in ipairs(galhos) do
				local idx = math.clamp(i * 2 - 1, 1, #pontos)
				if idx <= visiveis then
					local a = origemRachadura + ctx.Inicio:VectorToWorldSpace(pontos[idx])
					local lado = (i % 2 == 0) and 1 or -1
					local b = a + ctx.Inicio:VectorToWorldSpace(V3(lado * 1.8, 0, -0.9))
					g.Size = V3(0.15, 0.06, (b - a).Magnitude)
					g.CFrame = CFrame.lookAt((a + b) / 2, b)
					g.Transparency = 0.2 + 0.8 * fim
				else
					g.Transparency = 1
				end
			end
		end
	end
	function efeitos.Impacto(s)
		tImpacto = s.T
		origemRachadura = mundo(V3(spec.KickPoint.X, ctx.ChaoY + 0.04, spec.KickPoint.Z))
		impacto.CFrame = CFrame.new(s.BolaMundo)
		estilhacos:Emit(120)
		geada:Emit(35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, CIANO, 22, 0.3, 0.3)
		onda(pasta, mundo(V3(0, ctx.ChaoY + 0.1, spec.KickPoint.Z)), Vector3.yAxis, BRANCO, 20, 0.4, 0.2)
	end
	function efeitos.Voo(ball, duracao)
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, { Cor = cores({ { 0, BRANCO }, { 1, CIANO } }), Tamanho = 0.35, Vida = { 0.4, 0.8 }, Vel = { 1, 4 }, Taxa = 80, RotVel = 300 })
			emissor(a, {
				Textura = TEX.Fumaca, Cor = rgb(225, 245, 255), Brilho = 0.3, Tamanho = numeros({ { 0, 1.4 }, { 1, 3.2 } }),
				Transp = numeros({ { 0, 0.35 }, { 1, 1 } }), Vida = { 0.3, 0.6 }, Vel = { 0.5, 1.5 }, Taxa = 45,
			})
			luz(a, CIANO, 14, 3)
			table.insert(coisas, destaque(ball, GELO, BRANCO, 0.35))
			coisas.Espiral = espiralDeVoo(ball, coisas, CIANO, BRANCO, 1.3, 0.7)
			ctx._espiralGelo = coisas.Espiral
			-- ⚠️ v108 — anime (7-9.5s): a bola vai dentro de VÁRIOS redemoinhos de
			-- riscos azuis — segunda espiral, mais larga, defasada
			ctx._espiralGelo2 = espiralDeVoo(ball, coisas, rgb(90, 180, 255), BRANCO, 2.3, 0.45)
		end, function(a, dt, tempo)
			if ctx._espiralGelo then ctx._espiralGelo(a, dt, tempo) end
			if ctx._espiralGelo2 then ctx._espiralGelo2(a, dt, tempo + 0.08) end
		end)
	end
	return efeitos
end

-- ============================================================
-- 🔺 ZONA MORTA
-- ============================================================
function E.ZonaMorta(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local ROXO = rgb(150, 60, 255)
	local ROXO_ESCURO = rgb(55, 0, 95)
	local PRETO_ROXO = rgb(25, 0, 40)
	-- ⚠️ v108 — quadro a quadro do anime: as linhas do triângulo são ROSA-MAGENTA,
	-- finas e brilhantes; a bola vira uma ESFERA ROSA grande; o fundo é um
	-- vórtice roxo tipo nebulosa; no chão, aura roxa subindo de cada um e o
	-- triângulo já aparece no gramado; no salto eles giram como broca com anéis
	-- de vento brancos; a bola desce pro gol com espirais rosa.
	local ROSA = rgb(255, 80, 200)
	local ROSA_CLARO = rgb(255, 190, 235)
	local BRANCO = rgb(255, 255, 255)

	-- fumaça de onde as sombras surgem
	local surgir = {}
	for i = 1, 2 do
		local p = parte(pasta, "SurgirSombra" .. i)
		surgir[i] = emissor(p, {
			Textura = TEX.Fumaca, Cor = cores({ { 0, ROXO }, { 1, PRETO_ROXO } }), Brilho = 0.4,
			Tamanho = numeros({ { 0, 2 }, { 1, 6 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }),
			Vida = { 0.5, 0.9 }, Vel = { 2, 6 }, Drag = 2,
		})
		p.CFrame = CFrame.new(mundo(spec.Chao[i] + V3(0, -1, 0)))
	end

	-- aura/rastro nos três corpos enquanto sobem girando
	local auras = {}
	for i = 0, 2 do
		local p = parte(pasta, "AuraZona" .. i)
		local chama = emissor(p, {
			Textura = TEX.Fogo, Cor = cores({ { 0, ROSA_CLARO }, { 0.4, ROXO }, { 1, PRETO_ROXO } }), Brilho = 0.7,
			Tamanho = numeros({ { 0, 2.2 }, { 1, 0.4 } }), Transp = numeros({ { 0, 0.35 }, { 1, 1 } }),
			Vida = { 0.35, 0.6 }, Vel = { 3, 6 }, Spread = 18, Acel = V3(0, 10, 0),
			Forma = Enum.ParticleEmitterShape.Cylinder, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
		})
		auras[i] = { Parte = p, Rastro = rastroDuplo(p, 2.4, ROXO, rgb(230, 190, 255), 0.4), Chama = chama, UltimoAnel = -1 }
	end

	-- vórtice roxo (nebulosa) em volta do triângulo lá em cima
	local ceu = parte(pasta, "NebulosaZona")
	ceu.Size = V3(40, 40, 40)
	ceu.CFrame = CFrame.new(mundo(spec.Centro))
	-- ⚠️ v113 (anime a 0,2s, 13.6-17.6s): o fundo é um VAZIO roxo escuro. Com
	-- brilho 0.35 e cor clara as nuvens saíam lilás claras, em blocos, com o céu
	-- azul aparecendo. Agora mais escuras, maiores e mais densas.
	local nebulosa = emissor(ceu, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(95, 25, 170) }, { 0.5, rgb(50, 5, 95) }, { 1, PRETO_ROXO } }), Brilho = 0.08,
		Tamanho = numeros({ { 0, 20 }, { 1, 34 } }), Transp = numeros({ { 0, 1 }, { 0.25, 0.25 }, { 1, 1 } }),
		Vida = { 1.2, 1.8 }, Vel = { 3, 6 }, RotVel = 60,
		Forma = Enum.ParticleEmitterShape.Sphere, Estilo = Enum.ParticleEmitterShapeStyle.Surface,
		Sentido = Enum.ParticleEmitterShapeInOut.Inward, ZOffset = -4,
	})
	-- triângulo desenhado no gramado antes do salto
	local ladosChao = {}
	for i = 1, 3 do ladosChao[i] = parte(pasta, "TrianguloChao" .. i, { Color = ROSA }) end

	-- o triângulo: 3 lados + 3 raios até a bola
	local lados = {}
	for i = 1, 6 do lados[i] = parte(pasta, "RaioTriangulo" .. i, { Color = i <= 3 and ROSA or ROSA_CLARO }) end
	local function linha(p, a, b, w, transp)
		local len = (b - a).Magnitude
		if len < 0.05 then p.Transparency = 1 return end
		p.Size = V3(w, w, len)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Transparency = transp
	end

	-- bola: núcleo de energia escura + casca + partículas SUGADAS pra ela
	local nucleo = esfera(pasta, "NucleoEscuro", rgb(255, 120, 215)) -- ⚠️ v108: esfera ROSA (era roxo escuro)
	local casca = esfera(pasta, "CascaEscura", ROSA, Enum.Material.ForceField)
	local sugar = parte(pasta, "Sugar")
	sugar.Size = V3(12, 12, 12)
	local sugando = emissor(sugar, {
		Cor = cores({ { 0, ROSA_CLARO }, { 1, ROSA } }), Tamanho = 0.45, Vida = { 0.5, 0.7 }, Vel = { 9, 12 },
		Forma = Enum.ParticleEmitterShape.Sphere, Estilo = Enum.ParticleEmitterShapeStyle.Surface,
		Sentido = Enum.ParticleEmitterShapeInOut.Inward, Drag = 0, RotVel = 300,
	})
	local bolaLuz = luz(nucleo, ROSA, 0, 5)
	local bolaRastro = rastroDuplo(sugar, 0.9, ROXO, rgb(230, 190, 255), 0.35)

	local impacto = parte(pasta, "ImpactoZona")
	local explosao = emissor(impacto, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, ROXO }, { 1, PRETO_ROXO } }), Brilho = 0.5,
		Tamanho = numeros({ { 0, 3 }, { 1, 10 } }), Transp = numeros({ { 0, 0.15 }, { 1, 1 } }), Vida = { 0.4, 0.9 }, Vel = { 12, 26 }, Drag = 3,
	})
	local fagulhas = emissor(impacto, { Cor = cores({ { 0, rgb(240, 210, 255) }, { 1, ROXO } }), Tamanho = 0.6, Vida = { 0.25, 0.6 }, Vel = { 25, 48 }, Drag = 4 })

	local surgiu = false
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		if not surgiu and t >= ph.Spawn[1] then
			surgiu = true
			for _, e in ipairs(surgir) do e:Emit(40) end
		end
		-- corpos (o do chutador e das sombras)
		local corpos = { [0] = ctx.Root }
		for i = 1, 2 do
			local clone = ctx.Clones and ctx.Clones[i]
			corpos[i] = clone and clone.Root or nil
		end
		local subindo = t >= ph.Jump[1] and t < ph.Triangle[1] + 0.1
		local noChao = t >= 0.25 and t < ph.Jump[1] + 0.15
		for i = 0, 2 do
			local a = auras[i]
			local r = corpos[i]
			if r then a.Parte.CFrame = r.CFrame * CFrame.new(0, 0, 0.6) end
			a.Rastro.Ligar(subindo and r ~= nil)
			-- aura roxa subindo no chão
			a.Chama.Enabled = noChao and r ~= nil
			a.Chama.Rate = 45
			-- giro de broca: anéis de vento brancos em volta do corpo subindo
			if subindo and r and t - a.UltimoAnel > 0.11 then
				a.UltimoAnel = t
				anelVazado(pasta, r.Position + V3(0, -1 + math.random() * 2, 0), Vector3.yAxis, BRANCO, 2.5, 6, 0.25, 0.15)
			end
		end
		-- triângulo no gramado (antes do salto)
		local chaoTri = t >= 0.45 and t < ph.Jump[1] + 0.2
		for i = 1, 3 do
			local ra, rb = corpos[i - 1], corpos[i % 3]
			if chaoTri and ra and rb then
				local y = mundo(V3(0, ctx.ChaoY + 0.12, 0)).Y
				linha(ladosChao[i], V3(ra.Position.X, y, ra.Position.Z), V3(rb.Position.X, y, rb.Position.Z), 0.16, 0.1 + math.random() * 0.2)
			else
				ladosChao[i].Transparency = 1
			end
		end
		-- vórtice roxo lá em cima enquanto o triângulo existe
		nebulosa.Enabled = t >= ph.Jump[2] - 0.3 and t < spec.ImpactTime + 0.2
		nebulosa.Rate = 40

		local bola = s.BolaMundo
		local triangulo = t >= ph.Triangle[1] and t < spec.ImpactTime + 0.05
		for i = 1, 3 do
			local ra = corpos[i - 1]
			local rb = corpos[i % 3]
			if triangulo and ra and rb then
				linha(lados[i], ra.Position, rb.Position, 0.09 + math.random() * 0.04, 0.05 + math.random() * 0.2)
			else
				lados[i].Transparency = 1
			end
			local rc = corpos[i - 1]
			if triangulo and rc then
				linha(lados[i + 3], rc.Position, bola, 0.1, 0.25 + math.random() * 0.35)
			else
				lados[i + 3].Transparency = 1
			end
		end

		-- a bola absorvendo a energia
		local carga = smooth(phase(t, ph.Triangle[1], ph.Close[2]))
		local depois = s.ImpactoFeito and 1 or 0
		nucleo.CFrame = CFrame.new(bola)
		-- ⚠️ v108: a bola vira uma esfera de energia rosa GRANDE (anime, 9.5-11s)
		nucleo.Size = Vector3.one * ctx.TamanhoBola * (1.05 + 1.3 * math.max(carga, depois * 0.4))
		nucleo.Transparency = (carga > 0 or depois > 0) and (0.45 - 0.15 * math.sin(t * 25)) or 1
		casca.CFrame = CFrame.new(bola) * CFrame.Angles(t * 3, t * 2, 0)
		casca.Size = Vector3.one * ctx.TamanhoBola * (1.3 + 2.4 * carga)
		casca.Transparency = carga > 0 and (0.3 * (1 - depois)) or 1
		sugar.CFrame = CFrame.new(bola)
		sugando.Enabled = triangulo
		sugando.Rate = 90
		bolaLuz.Range = 10 + 14 * math.max(carga, depois)
		bolaRastro.Ligar(t >= 0.14)
	end
	function efeitos.Impacto(s)
		impacto.CFrame = CFrame.new(s.BolaMundo)
		explosao:Emit(45)
		fagulhas:Emit(90)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, ROSA, 26, 0.35, 0.35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, PRETO_ROXO, 18, 0.28, 0.3)
		onda(pasta, s.BolaMundo, Vector3.yAxis, ROSA_CLARO, 14, 0.3, 0.15)
	end
	function efeitos.Voo(ball, duracao)
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, {
				Textura = TEX.Fumaca, Cor = cores({ { 0, ROXO }, { 1, PRETO_ROXO } }), Brilho = 0.4,
				Tamanho = numeros({ { 0, 1.8 }, { 1, 3.5 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }),
				Vida = { 0.35, 0.7 }, Vel = { 0.5, 2 }, Taxa = 60,
			})
			emissor(a, { Cor = cores({ { 0, ROSA_CLARO }, { 1, ROSA } }), Tamanho = 0.5, Vida = { 0.2, 0.5 }, Vel = { 2, 6 }, Taxa = 60 })
			luz(a, ROSA, 16, 5)
			table.insert(coisas, destaque(ball, rgb(255, 110, 210), ROSA_CLARO, 0.25))
			-- ⚠️ v108: espirais ROSA em volta da bola descendo pro gol (anime 12.5-15s)
			coisas.Espiral = espiralDeVoo(ball, coisas, ROSA, ROSA_CLARO, 1.7, 0.8)
			ctx._espiralZona = coisas.Espiral
		end, function(a, dt, tempo)
			if ctx._espiralZona then ctx._espiralZona(a, dt, tempo) end
		end)
	end
	return efeitos
end

-- ============================================================
-- 🌌 GALÁXIA
-- ============================================================
function E.Galaxia(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local VERDE = rgb(80, 255, 140)
	local AMARELO = rgb(255, 235, 110)
	local DOURADO = rgb(255, 210, 90)
	local BRANCO = rgb(255, 255, 245)

	-- punho carregado
	local punho = esfera(pasta, "PunhoVerde", VERDE)
	punho.Size = V3(1.2, 1.2, 1.2)
	local punhoLuz = luz(punho, VERDE, 0, 5)
	local punhoFaiscas = emissor(punho, { Cor = cores({ { 0, rgb(220, 255, 220) }, { 1, VERDE } }), Tamanho = 0.35, Vida = { 0.2, 0.4 }, Vel = { 2, 6 } })
	local mao = ctx.Character:FindFirstChild("RightHand") or ctx.Character:FindFirstChild("Right Arm")

	-- soco no chão: raios verdes correndo no gramado
	local raiosChao = {}
	for i = 1, 6 do raiosChao[i] = novoRaio(pasta, i % 2 == 0 and VERDE or AMARELO, 0.18) end
	local socoFx = parte(pasta, "Soco")
	local socoFaiscas = emissor(socoFx, { Cor = cores({ { 0, AMARELO }, { 1, VERDE } }), Tamanho = 0.6, Vida = { 0.3, 0.7 }, Vel = { 10, 24 }, Spread = 70, Acel = V3(0, -10, 0) })

	-- 🖐️ a MÃO gigante: palma + 4 dedos (3 falanges) + polegar
	local MAO_COR = VERDE
	local palma = parte(pasta, "Palma", { Color = MAO_COR })
	palma.Size = V3(8, 1, 7.5)
	local dedos = {}
	local xs = { -3, -1, 1, 3 }
	for d = 1, 4 do
		dedos[d] = {}
		for k = 1, 3 do dedos[d][k] = parte(pasta, "Dedo" .. d .. "_" .. k, { Color = MAO_COR }) end
	end
	local polegar = {}
	for k = 1, 3 do polegar[k] = parte(pasta, "Polegar" .. k, { Color = MAO_COR }) end
	local maoLuz = luz(palma, VERDE, 0, 4)
	local maoBrilho = emissor(palma, {
		Cor = cores({ { 0, rgb(220, 255, 220) }, { 1, VERDE } }), Tamanho = 0.5, Vida = { 0.5, 1 }, Vel = { 1, 4 },
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, Acel = V3(0, 3, 0),
	})

	-- 🌌 o espaço: esfera INVERTIDA (malha com escala negativa = dá pra ver de
	-- dentro), estrelas, nebulosa e planetas
	local centroEspaco = mundo(V3(0, spec.AlturaEspaco, -2))
	-- ⚠️ v113 — pelo vídeo do IE3 a 0,2s (146.8s e 150.8s): o espaço é preto e a
	-- TERRA fica embaixo deles. Sala escura com o chão rente ao gramado + a Terra
	-- (com atmosfera e nuvens) saindo do chão.
	local chaoSala = ctx.ChaoY + 0.1
	local ceu = salaEscura(pasta, "CeuGalaxia", rgb(6, 5, 24), ctx.Inicio * CFrame.new(0, spec.AlturaEspaco, -2), 230,
		chaoSala - spec.AlturaEspaco)
	-- A TERRA vista de cima: um DISCO (cilindro deitado, que é bem redondo) com
	-- uma borda de atmosfera brilhando, continentes e nuvens por cima. (Esfera
	-- desse tamanho — Ball ou malha — renderiza com poucas faces e vira um
	-- polígono/quadrado azul.)
	local RT, TOPO = 26, chaoSala + 1.2
	local deitado = CFrame.Angles(0, 0, math.rad(90))
	local terra = parte(pasta, "Terra", { Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = rgb(35, 95, 210) })
	terra.Size = V3(1, RT * 2, RT * 2)
	terra.CFrame = ctx.Inicio * CFrame.new(0, TOPO - 0.5, -2) * deitado
	local atmosfera = parte(pasta, "TerraAtmosfera", { Shape = Enum.PartType.Cylinder, Color = rgb(120, 200, 255) })
	atmosfera.Size = V3(0.8, RT * 2 + 3.5, RT * 2 + 3.5)
	atmosfera.CFrame = ctx.Inicio * CFrame.new(0, TOPO - 0.8, -2) * deitado
	local nuvensTerra = {}
	local rngT = Random.new(5)
	for i = 1, 16 do
		local n = esfera(pasta, "TerraNuvem" .. i, rgb(240, 248, 255), Enum.Material.SmoothPlastic)
		local ang = rngT:NextNumber(0, math.pi * 2)
		local r = rngT:NextNumber(2, RT - 5)
		n.Size = V3(rngT:NextNumber(3.5, 7), 0.5, rngT:NextNumber(1.8, 3.5))
		n.CFrame = ctx.Inicio * CFrame.new(math.cos(ang) * r, TOPO + 0.6, math.sin(ang) * r - 2) * CFrame.Angles(0, rngT:NextNumber(0, 6), 0)
		nuvensTerra[i] = n
	end
	-- continentes (verdes e areia), rentes à superfície, debaixo das nuvens
	local continentes = {}
	for i = 1, 7 do
		local c = parte(pasta, "TerraContinente" .. i, { Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic,
			Color = i % 3 == 0 and rgb(190, 170, 110) or rgb(60, 140, 70) })
		local ang = rngT:NextNumber(0, math.pi * 2)
		local r = rngT:NextNumber(3, RT - 8)
		local d = rngT:NextNumber(5, 10)
		c.Size = V3(0.3, d, d * rngT:NextNumber(0.6, 1))
		c.CFrame = ctx.Inicio * CFrame.new(math.cos(ang) * r, TOPO + 0.1, math.sin(ang) * r - 2) * CFrame.Angles(0, rngT:NextNumber(0, 6), 0) * deitado
		continentes[i] = c
	end
	local estrelasPeca = parte(pasta, "Estrelas")
	estrelasPeca.Size = V3(180, 120, 180)
	estrelasPeca.CFrame = CFrame.new(centroEspaco)
	local estrelas = emissor(estrelasPeca, {
		Cor = cores({ { 0, BRANCO }, { 0.5, rgb(200, 220, 255) }, { 1, rgb(255, 230, 200) } }),
		Tamanho = numeros({ { 0, 0.9 }, { 0.5, 1.3 }, { 1, 0.9 } }), Transp = numeros({ { 0, 1 }, { 0.1, 0 }, { 0.9, 0 }, { 1, 1 } }),
		Vida = { 3, 3 }, Vel = { 0, 0 }, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
		RotVel = 30, Travado = true, ZOffset = -2,
	})
	local nebulosa = emissor(estrelasPeca, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(120, 60, 255) }, { 0.5, rgb(40, 150, 255) }, { 1, rgb(255, 80, 200) } }),
		Brilho = 0.6, Tamanho = numeros({ { 0, 25 }, { 1, 40 } }), Transp = numeros({ { 0, 1 }, { 0.3, 0.7 }, { 0.7, 0.7 }, { 1, 1 } }),
		Vida = { 3, 3 }, Vel = { 0, 0.5 }, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
		Travado = true, ZOffset = -3, RotVel = 10,
	})
	local planetas = {}
	local function planeta(nome, pos, diametro, cor, anel)
		local p = esfera(pasta, nome, cor, Enum.Material.SmoothPlastic)
		p.Size = Vector3.one * diametro
		p.CFrame = CFrame.new(centroEspaco + ctx.Inicio:VectorToWorldSpace(pos))
		local item = { Parte = p }
		if anel then
			local a = parte(pasta, nome .. "Anel", { Shape = Enum.PartType.Cylinder, Color = anel, Material = Enum.Material.Neon })
			a.Size = V3(0.3, diametro * 2, diametro * 2)
			a.CFrame = p.CFrame * CFrame.Angles(0, 0, math.rad(70)) * CFrame.Angles(math.rad(20), 0, 0)
			item.Anel = a
		end
		table.insert(planetas, item)
	end
	planeta("PlanetaGrande", V3(-55, 20, -70), 34, rgb(90, 120, 255), rgb(200, 180, 255))
	planeta("PlanetaVermelho", V3(60, 35, -40), 14, rgb(255, 110, 70))
	planeta("Lua", V3(35, -10, 70), 9, rgb(230, 230, 240))

	-- chute: rastro dourado no pé; bola vira meteoro
	local peFx = parte(pasta, "PeDourado")
	local peRastro = rastroDuplo(peFx, 0.9, DOURADO, BRANCO, 0.35)
	local bolaFx = parte(pasta, "BolaEstrela")
	local bolaBrilho = emissor(bolaFx, { Cor = cores({ { 0, BRANCO }, { 1, DOURADO } }), Tamanho = 0.5, Vida = { 0.3, 0.7 }, Vel = { 1, 4 } })
	local bolaLuz = luz(bolaFx, DOURADO, 0, 5)
	local impacto = parte(pasta, "ImpactoEstrela")
	local estouro = emissor(impacto, { Cor = cores({ { 0, BRANCO }, { 0.5, DOURADO }, { 1, rgb(120, 200, 255) } }), Tamanho = 0.8, Vida = { 0.3, 0.8 }, Vel = { 25, 55 }, Drag = 3 })

	local socou, espacoLigado = false, false
	local socoPonto = nil

	local function segmentos(lista, base, dir0, curva, comp, larg, eixoCurva)
		-- cadeia de falanges: cada uma dobra `curva` a mais que a anterior
		local p = base
		for k, seg in ipairs(lista) do
			local ang = dir0 + curva * (k - 1) + curva * 0.5
			local d
			if eixoCurva == "X" then
				d = V3(0, math.cos(ang), math.sin(ang)) -- dedos: dobram pra +Z (pro chutador)
			else
				d = V3(-math.sin(ang), math.cos(ang), 0) -- polegar: dobra pra -X
			end
			local centro = p + d * (comp / 2)
			local x = eixoCurva == "X" and Vector3.xAxis or Vector3.zAxis
			seg.Size = V3(larg, comp, larg)
			seg.CFrame = ctx.Inicio * CFrame.fromMatrix(centro, x, d)
			p = p + d * comp
		end
	end

	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		-- punho verde
		local carregando = t >= 0.1 and t < ph.Punch[2] + 0.1
		if mao then punho.CFrame = mao.CFrame end
		punho.Transparency = carregando and (0.35 - 0.15 * math.sin(t * 30)) or 1
		punhoLuz.Range = carregando and 10 or 0
		punhoFaiscas.Enabled = carregando
		punhoFaiscas.Rate = 50

		if not socou and t >= ph.Punch[1] + 0.07 then
			socou = true
			-- onde a mão bateu de verdade, projetado no gramado
			local chao = mundo(V3(0.8, ctx.ChaoY + 0.05, -1.2))
			if mao then
				local m = ctx.Inicio:PointToObjectSpace(mao.Position)
				chao = mundo(V3(m.X, ctx.ChaoY + 0.05, m.Z))
			end
			socoPonto = chao
			socoFx.CFrame = CFrame.new(chao)
			socoFaiscas:Emit(70)
			onda(pasta, chao, Vector3.yAxis, AMARELO, 34, 0.45, 0.25)
			onda(pasta, chao, Vector3.yAxis, VERDE, 22, 0.35, 0.2)
			ctx.Flash(rgb(230, 255, 200), 0.5, 0.25)
			ctx.Tremer(0.45, 0.3)
		end
		-- raios verdes no chão por 0.35s depois do soco
		local socoT = ph.Punch[1] + 0.07
		for i, r in ipairs(raiosChao) do
			if t >= socoT and t < socoT + 0.35 and math.random() < 0.75 then
				local ang = (i / #raiosChao) * math.pi * 2 + t
				local a = (socoPonto or mundo(V3(0.8, ctx.ChaoY, -1.2))) + Vector3.new(0, 0.05, 0)
				local b = a + ctx.Inicio:VectorToWorldSpace(V3(math.cos(ang), 0, math.sin(ang)) * (6 + math.random() * 7))
				r.Desenhar(a, b, 8, 1.2, 0.18, phase(t, socoT + 0.15, socoT + 0.35))
			else
				r.Apagar()
			end
		end

		-- a mão: sobe do gramado, fecha em volta, leva pro alto, abre
		local sobe = easeOut(phase(t, ph.HandRise[1], ph.HandRise[2]))
		local elev = spec.Elevacao(t)
		local topoPalma = ctx.ChaoY + elev - (1 - sobe) * 12
		local alfaMao = sobe * (1 - smooth(phase(t, 2.35, 2.75)))
		palma.CFrame = ctx.Inicio * CFrame.new(0, topoPalma - 0.5, -0.5)
		palma.Transparency = 1 - alfaMao * 0.7
		-- fecha: 0 = dedos de pé (em volta, como grade), 1 = curvados por cima
		local fecha = smooth(phase(t, ph.HandClose[1], ph.HandClose[2])) * (1 - smooth(phase(t, ph.HandOpen[1], ph.HandOpen[2])))
		local abre = smooth(phase(t, ph.HandOpen[1], ph.HandOpen[2]))
		local curva = math.rad(28) * fecha - math.rad(12) * abre
		for d, lista in ipairs(dedos) do
			segmentos(lista, V3(xs[d], topoPalma, -4.2), -math.rad(8) * abre, curva, 2.6, 1.5, "X")
			for _, seg in ipairs(lista) do seg.Transparency = 1 - alfaMao * 0.7 end
		end
		segmentos(polegar, V3(4.4, topoPalma, 0.2), math.rad(10) * abre, curva * 0.9, 2.2, 1.6, "Z")
		for _, seg in ipairs(polegar) do seg.Transparency = 1 - alfaMao * 0.7 end
		maoLuz.Range = 22 * alfaMao
		maoBrilho.Enabled = alfaMao > 0.2
		maoBrilho.Rate = 60

		-- o espaço
		local espaco = smooth(phase(t, ph.Space[1], ph.Space[1] + 0.45)) * (1 - smooth(phase(t, ph.Space[2], spec.Duration)))
		ceu.Transparency = 1 - espaco
		-- a Terra só aparece quando a mão já passou do topo dela (ela sai do chão)
		local vistaTerra = math.min(espaco, smooth(phase(t, 1.7, 2.0)))
		terra.Transparency = 1 - vistaTerra
		atmosfera.Transparency = 1 - vistaTerra * 0.55
		for _, n in ipairs(nuvensTerra) do n.Transparency = 1 - vistaTerra * 0.85 end
		for _, c in ipairs(continentes) do c.Transparency = 1 - vistaTerra end
		for _, pl in ipairs(planetas) do
			pl.Parte.Transparency = 1 - espaco
			if pl.Anel then pl.Anel.Transparency = 1 - espaco * 0.6 end
		end
		if not espacoLigado and t >= ph.Space[1] then
			espacoLigado = true
			estrelas:Emit(600)
			nebulosa:Emit(14)
		end
		if espacoLigado and t >= ph.Space[2] then
			estrelas:Clear()
			nebulosa:Clear()
		end

		-- bola brilhando (estrela) no espaço; pé dourado no chute
		bolaFx.CFrame = CFrame.new(s.BolaMundo)
		bolaBrilho.Enabled = t >= ph.Space[1]
		bolaBrilho.Rate = s.ImpactoFeito and 120 or 40
		bolaLuz.Range = t >= ph.Space[1] and (s.ImpactoFeito and 24 or 12) or 0
		peFx.CFrame = CFrame.new(s.PePos)
		peRastro.Ligar(t >= 2.4 and t < spec.ImpactTime + 0.1)
	end
	function efeitos.Impacto(s)
		impacto.CFrame = CFrame.new(s.BolaMundo)
		estouro:Emit(150)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, DOURADO, 26, 0.35, 0.35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, BRANCO, 16, 0.25, 0.3)
	end
	function efeitos.Voo(ball, duracao)
		-- METEORO: fogo branco-dourado, rastro largo, faíscas
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, {
				Textura = TEX.Fogo, Cor = cores({ { 0, BRANCO }, { 0.35, DOURADO }, { 1, rgb(255, 110, 30) } }), Brilho = 0.85,
				Tamanho = numeros({ { 0, 3 }, { 0.6, 2 }, { 1, 0 } }), Transp = numeros({ { 0, 0.15 }, { 0.7, 0.45 }, { 1, 1 } }),
				Vida = { 0.3, 0.5 }, Vel = { 1, 4 }, Spread = 35, Taxa = 260, Drag = 1.5, ZOffset = 0.3,
			})
			emissor(a, { Cor = cores({ { 0, BRANCO }, { 1, rgb(120, 200, 255) } }), Tamanho = 0.5, Vida = { 0.3, 0.7 }, Vel = { 4, 10 }, Taxa = 70 })
			luz(a, DOURADO, 24, 6)
			local a0 = Instance.new("Attachment") a0.Position = V3(0, -0.9, 0) a0.Parent = ball
			local a1 = Instance.new("Attachment") a1.Position = V3(0, 0.9, 0) a1.Parent = ball
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Lifetime = 0.5
			tr.LightEmission = 1
			tr.LightInfluence = 0
			tr.FaceCamera = true
			tr.Texture = TEX.Fogo
			tr.TextureMode = Enum.TextureMode.Stretch
			tr.Color = cores({ { 0, BRANCO }, { 0.4, DOURADO }, { 1, rgb(255, 100, 30) } })
			tr.Transparency = numeros({ { 0, 0 }, { 1, 1 } })
			tr.WidthScale = numeros({ { 0, 2 }, { 1, 0.2 } })
			tr.Parent = ball
			for _, x in ipairs({ a0, a1, tr }) do table.insert(coisas, x) end
			table.insert(coisas, destaque(ball, rgb(255, 230, 150), BRANCO, 0.25))
		end)
	end
	return efeitos
end

-- ============================================================
-- 🧤 DEFESA (⚠️ v103) — cutscene da Hissatsu do goleiro no duelo
-- ============================================================
-- Mão gigante (palma + 4 dedos de 3 falanges + polegar) virada pra bola: a
-- MESMA peça faz a Mão Divina (luz dourada, aberta), a Mão do Demônio (roxa
-- escura, com raios) e o Punho Gigante (verde, fechada em soco). A Muralha de
-- Maré levanta uma parede d'água em arco; o Soco Explosivo acende fogo nos
-- punhos e explode na bola a cada soco.
local function maoGigante(pasta, cor, material, transp)
	local partes = {}
	local function peca(nome)
		local p = parte(pasta, nome, { Color = cor, Material = material or Enum.Material.Neon })
		table.insert(partes, p)
		return p
	end
	local mao = { Palma = peca("Palma"), Dedos = {}, Polegar = {}, Partes = partes }
	for d = 1, 4 do
		mao.Dedos[d] = {}
		for k = 1, 3 do mao.Dedos[d][k] = peca("Dedo" .. d .. k) end
	end
	for k = 1, 3 do mao.Polegar[k] = peca("Polegar" .. k) end
	-- cf = centro da palma (Z da palma aponta PRA BOLA), escala, fecha (0..1), alfa
	function mao.Posar(cf, escala, fecha, alfa)
		local e = escala
		mao.Palma.Size = V3(5.2 * e, 5.6 * e, 1.1 * e)
		mao.Palma.CFrame = cf
		-- ⚠️ v110 (conferido na tela, de frente): os dedos eram colados (0.15 de
		-- folga) e retos — de frente a mão virava um bloco. Agora ficam separados
		-- e abertos em LEQUE (mais aberto quanto mais aberta a mão), como no anime.
		local xs = { -2.1, -0.72, 0.72, 2.1 }
		local leque = { 13, 4.5, -4.5, -13 }
		local curva = math.rad(10 + 70 * fecha) -- aberta ~10°, fechada (punho) ~80° por falange
		for d, lista in ipairs(mao.Dedos) do
			local base = cf * CFrame.new(xs[d] * e, 2.7 * e, 0) * CFrame.Angles(0, 0, math.rad(leque[d] * (1 - fecha)))
			local comp = (d == 2 or d == 3) and 1.9 or 1.6
			local c = base
			for k, seg in ipairs(lista) do
				c = c * CFrame.Angles(curva, 0, 0) -- dobra pra frente, envolvendo a bola (+Z local da palma, que olha pra ela)
				seg.Size = V3(1.0 * e, comp * e, 1.1 * e)
				seg.CFrame = c * CFrame.new(0, comp * e / 2, 0)
				c = c * CFrame.new(0, comp * e, 0)
			end
		end
		local cp = cf * CFrame.new(2.9 * e, -0.6 * e, 0) * CFrame.Angles(0, 0, math.rad(-50))
		for _, seg in ipairs(mao.Polegar) do
			cp = cp * CFrame.Angles(curva * 0.8, 0, 0)
			seg.Size = V3(1.2 * e, 1.5 * e, 1.2 * e)
			seg.CFrame = cp * CFrame.new(0, 0.75 * e, 0)
			cp = cp * CFrame.new(0, 1.5 * e, 0)
		end
		for _, p in ipairs(partes) do p.Transparency = 1 - alfa * (1 - (transp or 0.25)) end
	end
	return mao
end

local DEFESA_CORES = {
	MaoDivina = { rgb(255, 225, 110), rgb(255, 250, 220) },
	-- ⚠️ v106 — "a Mão do Demônio, não sei por que tá roxa... ele é um boneco
	-- AMARELO". A arte do artista: demônio gigante dourado, musculoso, cabelo
	-- espetado laranja-avermelhado, aura amarela — nada de roxo.
	MaoDemonio = { rgb(255, 196, 60), rgb(255, 246, 190) },
	PunhoGigante = { rgb(90, 175, 255), rgb(220, 240, 255) }, -- ⚠️ v109: energia azul (Gigant Wall)
	MuralhaMare = { rgb(90, 190, 255), rgb(240, 250, 255) },
	SocoExplosivo = { rgb(255, 130, 30), rgb(255, 225, 120) },
	-- ⚠️ v109: goleiros novos
	BlocoGelo = { rgb(170, 225, 255), rgb(240, 250, 255) },
	SocoArdente = { rgb(255, 110, 20), rgb(255, 220, 120) },
	EscudoForca = { rgb(255, 170, 50), rgb(255, 240, 190) },
	PunhoJustica = { rgb(255, 210, 60), rgb(255, 250, 210) },
	FuujinRaijin = { rgb(120, 230, 200), rgb(255, 240, 150) },
}

-- ⚠️ v107: tamanho final da mão gigante por técnica (Mão Divina = God Hand)
local ESCALA_MAO = { MaoDivina = 2.1, MaoDemonio = 1.8, PunhoGigante = 1.55, PunhoJustica = 1.9 }



-- ============================================================
-- 🐉 TORNADO DO DRAGÃO — ⚠️ v109
-- ============================================================
-- O DRAGÃO: uma corrente de segmentos que segue o CAMINHO da bola (histórico
-- das posições dela), enrolando em volta dele; cabeça maior com olhos
-- vermelhos. Azul até o chute, FOGO depois (a wiki: "o dragão azul vira um
-- dragão de fogo"). O chutador sobe dentro de um tornado de fogo.
-- ⚠️ v113 — revisão pelo anime a 0,2s (0-2.4s: a bola sobe dentro de um DRAGÃO
-- azul, corpo de serpente, cabeça com chifres). Antes: blocos Neon seguindo o
-- histórico por QUADRO (dependia do FPS e, parado, encolhia tudo num bolo em
-- cima da bola). Agora o histórico é por TEMPO (cada gomo fica X segundos
-- atrás da bola), o corpo é de esferas afinando até a cauda, e a cabeça tem
-- focinho, dois chifres e olhos vermelhos.
local function correnteDragao(pastaAlvo, n)
	local segs = {}
	for i = 1, n do
		segs[i] = parte(pastaAlvo, "Dragao" .. i, { Shape = Enum.PartType.Ball, Color = rgb(70, 140, 255) })
	end
	local focinho = parte(pastaAlvo, "DragaoFocinho", { Color = rgb(70, 140, 255) })
	local chifres = { parte(pastaAlvo, "DragaoChifreE", { Color = rgb(220, 240, 255) }), parte(pastaAlvo, "DragaoChifreD", { Color = rgb(220, 240, 255) }) }
	local olhos = { parte(pastaAlvo, "OlhoDragaoE", { Color = rgb(255, 40, 40) }), parte(pastaAlvo, "OlhoDragaoD", { Color = rgb(255, 40, 40) }) }
	local hist = {} -- { t, p }, mais novo primeiro
	local PASSO = 0.03 -- segundos entre um gomo e o próximo
	local function naHora(tt)
		if #hist == 0 then return nil end
		if tt >= hist[1].t then return hist[1].p end
		for k = 1, #hist - 1 do
			local a, b = hist[k], hist[k + 1]
			if tt <= a.t and tt >= b.t then
				local u = (a.t - tt) / math.max(a.t - b.t, 1e-4)
				return a.p:Lerp(b.p, u)
			end
		end
		return hist[#hist].p
	end
	local d = {}
	function d.Atualizar(posBola, cor, alfa, tempo)
		-- voltou no tempo (depuração): recomeça o histórico
		if hist[1] and tempo < hist[1].t - 0.05 then table.clear(hist) end
		if not hist[1] or tempo > hist[1].t + 1e-4 then
			table.insert(hist, 1, { t = tempo, p = posBola })
			while #hist > 2 and hist[#hist].t < tempo - (n + 2) * PASSO do table.remove(hist) end
		else
			hist[1].p = posBola
		end
		local cabecaCF = nil
		for i, s in ipairs(segs) do
			local p = naHora(tempo - (i - 1) * PASSO)
			local prox = naHora(tempo - i * PASSO) or p
			if p and alfa > 0.02 then
				local ang = tempo * 5 + i * 0.5
				local off = V3(math.cos(ang) * 1.6, math.sin(ang * 0.7) * 0.9, math.sin(ang) * 1.6) * math.min((i - 1) / 4, 1)
				local tam = math.max(2.6 - (i - 1) * 0.13, 0.45)
				local pos = p + off
				local dir = p - prox
				if dir.Magnitude < 0.01 then dir = V3(0, 1, 0) end
				s.Size = Vector3.one * tam
				s.CFrame = CFrame.lookAt(pos, pos + dir + V3(0, 0.001, 0))
				s.Color = cor
				s.Transparency = 1 - alfa * 0.85
				if i == 1 then cabecaCF = s.CFrame end
			else
				s.Transparency = 1
			end
		end
		local vis = cabecaCF and alfa > 0.02
		if vis then
			focinho.Size = V3(1.5, 1.0, 2.0)
			focinho.CFrame = cabecaCF * CFrame.new(0, -0.25, -1.5)
			focinho.Color = cor
			for j, c in ipairs(chifres) do
				local lado = j == 1 and -1 or 1
				c.Size = V3(0.3, 0.3, 2.2)
				c.CFrame = cabecaCF * CFrame.new(lado * 0.7, 0.9, 0.6) * CFrame.Angles(math.rad(35), lado * math.rad(20), 0)
			end
			for j, o in ipairs(olhos) do
				o.Size = V3(0.4, 0.4, 0.4)
				o.CFrame = cabecaCF * CFrame.new(j == 1 and -0.6 or 0.6, 0.45, -1.0)
			end
		end
		local transp = vis and (1 - alfa * 0.85) or 1
		focinho.Transparency = transp
		for _, c in ipairs(chifres) do c.Transparency = transp end
		for _, o in ipairs(olhos) do o.Transparency = vis and (1 - alfa) or 1 end
	end
	return d
end

function E.DragaoTornado(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local AZUL = rgb(70, 140, 255)
	local FOGO = rgb(255, 110, 30)
	local dragao = correnteDragao(pasta, 16)
	-- tornado de fogo em volta do chutador (anéis subindo + fogo)
	local tornadoFx = parte(pasta, "TornadoFogo")
	local chamas = emissor(tornadoFx, {
		Textura = TEX.Fogo, Cor = cores({ { 0, rgb(255, 230, 140) }, { 0.5, FOGO }, { 1, rgb(160, 30, 10) } }), Brilho = 0.8,
		Tamanho = numeros({ { 0, 2.6 }, { 1, 0.3 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.35, 0.6 },
		Vel = { 4, 8 }, Acel = V3(0, 14, 0), Forma = Enum.ParticleEmitterShape.Cylinder, Estilo = Enum.ParticleEmitterShapeStyle.Surface,
		Sentido = Enum.ParticleEmitterShapeInOut.Outward,
	})
	tornadoFx.Size = V3(5, 2, 5)
	local ultimoAnel = -1
	local impacto = parte(pasta, "ImpactoDragao")
	local estouro = emissor(impacto, { Cor = cores({ { 0, rgb(255, 250, 210) }, { 1, FOGO } }), Tamanho = 0.7, Vida = { 0.25, 0.6 }, Vel = { 25, 50 }, Drag = 4 })
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		local depois = s.ImpactoFeito
		local alfa = smooth(phase(t, 0.25, 0.5))
		dragao.Atualizar(s.BolaMundo, depois and FOGO or AZUL, alfa, t)
		local subindo = t >= ph.GroundSpin[1] and t < ph.Apex[2]
		tornadoFx.CFrame = ctx.Root.CFrame * CFrame.new(0, -1, 0)
		chamas.Enabled = subindo
		chamas.Rate = 110
		if subindo and t - ultimoAnel > 0.09 then
			ultimoAnel = t
			anelVazado(pasta, ctx.Root.Position + V3(0, -2 + math.random() * 4, 0), Vector3.yAxis, FOGO, 3, 7, 0.3, 0.3)
		end
	end
	function efeitos.Impacto(s)
		impacto.CFrame = CFrame.new(s.BolaMundo)
		estouro:Emit(120)
		ctx.Flash(rgb(255, 220, 160), 0.3, 0.25)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, FOGO, 26, 0.35, 0.35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, AZUL, 16, 0.25, 0.3)
	end
	function efeitos.Voo(ball, duracao)
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, {
				Textura = TEX.Fogo, Cor = cores({ { 0, rgb(255, 230, 140) }, { 1, FOGO } }), Brilho = 0.8,
				Tamanho = numeros({ { 0, 2.2 }, { 1, 0.3 } }), Vida = { 0.25, 0.5 }, Vel = { 1, 3 }, Taxa = 90,
			})
			luz(a, FOGO, 18, 5)
			local pastaVoo = Instance.new("Folder")
			pastaVoo.Name = "DragaoVoo"
			pastaVoo.Parent = workspace
			table.insert(coisas, pastaVoo)
			ctx._dragaoVoo = correnteDragao(pastaVoo, 14)
		end, function(_a, _dt, tempo)
			if ctx._dragaoVoo then ctx._dragaoVoo.Atualizar(ball.Position, FOGO, 1, tempo) end
		end)
	end
	return efeitos
end

-- ============================================================
-- ☄️ LÂMINA METEORO (Ryuusei Blade) — ⚠️ v110
-- ============================================================
-- Pelo vídeo (ver a coreografia): riscos vermelhos no giro; no voleio a bola vira
-- uma ESFERA roxa e azul cheia de raios; um anel roxo se FECHA e ela some num
-- ponto; explode num SOL dourado com reflexo horizontal; clarão branco; e no voo
-- um FEIXE rosa/roxo (cone de frente pra câmera) com RAIOS amarelos nas bordas
-- e explosões curtas pelo caminho.
function E.LaminaMeteoro(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local ROXO, AZUL, ROSA, DOURADO, BRANCO = rgb(170, 70, 255), rgb(80, 150, 255), rgb(255, 90, 200), rgb(255, 210, 90), rgb(255, 255, 245)
	-- riscos vermelhos em volta no giro
	local riscosFx = parte(pasta, "RiscosVermelhos")
	local riscos = emissor(riscosFx, {
		Cor = cores({ { 0, rgb(255, 120, 120) }, { 1, rgb(220, 20, 60) } }), Tamanho = numeros({ { 0, 0.25 }, { 1, 0.1 } }),
		Vida = { 0.2, 0.35 }, Vel = { 40, 70 }, Spread = 180, Forma = Enum.ParticleEmitterShape.Sphere, Taxa = 0,
	})
	-- a esfera roxa/azul, os raios, o anel que fecha e a estrela
	local esferaE = esfera(pasta, "EsferaLamina", ROXO)
	local halo = esfera(pasta, "HaloLamina", AZUL, Enum.Material.ForceField)
	local raiosE = {}
	for i = 1, 10 do raiosE[i] = parte(pasta, "RaioEsfera" .. i, { Color = i % 2 == 0 and ROSA or AZUL }) end
	local anelFecha = parte(pasta, "AnelFecha", { Shape = Enum.PartType.Cylinder, Color = ROXO, Material = Enum.Material.ForceField })
	-- ⚠️ v113 (revisão a 0,2s): o "sol" era uma esfera quase branca de 9 studs
	-- que tampava a tela inteira com o estádio atrás. No vídeo (4.3-5.8s) é um
	-- SOL DOURADO com halo e um reflexo horizontal, num fundo de ESPAÇO escuro.
	local estrela = esfera(pasta, "EstrelaLamina", rgb(255, 205, 90))
	local haloSol = esfera(pasta, "HaloSol", rgb(255, 180, 70))
	local reflexo = parte(pasta, "Reflexo", { Color = rgb(255, 230, 160) })
	local espacoLamina = salaEscura(pasta, "EspacoLamina", rgb(10, 4, 26),
		CFrame.new(mundo(spec.PontoEstrela)) * ctx.Inicio.Rotation, 150, ctx.ChaoY + 0.1 - spec.PontoEstrela.Y) -- chão da sala rente ao gramado
	local luzE = luz(esferaE, ROXO, 0, 6)
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		riscosFx.CFrame = CFrame.new(ctx.Root.Position)
		riscos.Enabled = t >= ph.Spin[1] and t < ph.Kick[2]
		riscos.Rate = 120
		local centro = mundo(spec.PontoEstrela)
		local frente = ctx.Inicio.LookVector
		-- ESFERA: cresce, pulsa, depois COLAPSA
		local cresce = smooth(phase(t, ph.Esfera[1], ph.Esfera[2]))
		local colapsa = smooth(phase(t, ph.Colapso[1], ph.Colapso[2]))
		local tam = 7 * cresce * (1 - colapsa) + (cresce > 0 and 0.4 or 0) * (1 - colapsa)
		esferaE.Size = Vector3.one * math.max(tam * 0.55, 0.1)
		esferaE.CFrame = CFrame.new(centro)
		esferaE.Transparency = tam > 0.3 and 0.1 or 1
		halo.Size = Vector3.one * math.max(tam, 0.1)
		halo.CFrame = CFrame.new(centro)
		halo.Transparency = tam > 0.3 and (0.2 + 0.1 * math.sin(t * 30)) or 1
		luzE.Range = 20 * cresce * (1 - colapsa)
		for i, r in ipairs(raiosE) do
			local ang = (i / #raiosE) * math.pi * 2 + t * 2
			local dir = (ctx.Inicio.RightVector * math.cos(ang) + Vector3.yAxis * math.sin(ang))
			local comp = tam * (1.6 + 0.4 * math.sin(t * 17 + i))
			if comp > 0.3 then
				r.Size = V3(0.18, 0.18, comp)
				r.CFrame = CFrame.lookAt(centro + dir * (comp / 2), centro + dir * comp)
				r.Transparency = 0.15
			else
				r.Transparency = 1
			end
		end
		-- o ANEL roxo que fecha até sumir num ponto
		if t >= ph.Colapso[1] - 0.05 and t < ph.Colapso[2] + 0.05 then
			local u = phase(t, ph.Colapso[1] - 0.05, ph.Colapso[2])
			local d = 16 * (1 - u) + 0.2
			anelFecha.Size = V3(0.25, d, d)
			anelFecha.CFrame = CFrame.lookAt(centro, centro - frente) * CFrame.Angles(0, math.rad(90), 0)
			anelFecha.Transparency = 0.1
		else
			anelFecha.Transparency = 1
		end
		-- o SOL dourado com o reflexo horizontal
		local sol = smooth(phase(t, ph.Estrela[1], ph.Estrela[1] + 0.25)) * (1 - smooth(phase(t, ph.Clarao[1] + 0.05, ph.Clarao[2])))
		estrela.Size = Vector3.one * math.max(4.2 * sol * (1 + 0.08 * math.sin(t * 40)), 0.1)
		estrela.CFrame = CFrame.new(centro)
		estrela.Transparency = sol > 0.02 and 0 or 1
		haloSol.Size = Vector3.one * math.max(6.2 * sol * (1 + 0.12 * math.sin(t * 25)), 0.1)
		haloSol.CFrame = CFrame.new(centro)
		haloSol.Transparency = sol > 0.02 and 0.82 or 1
		-- espaço escuro do anel fechando até o clarão
		local escuro = smooth(phase(t, ph.Colapso[1] - 0.1, ph.Colapso[1] + 0.1)) * (1 - smooth(phase(t, ph.Clarao[1], ph.Clarao[1] + 0.1)))
		espacoLamina.Transparency = 1 - escuro
		reflexo.Size = V3(math.max(46 * sol, 0.1), 0.35 * sol + 0.05, 0.35 * sol + 0.05)
		reflexo.CFrame = CFrame.lookAt(centro, centro + frente) * CFrame.new(0, 0, -0.5)
		reflexo.Transparency = sol > 0.02 and 0.1 or 1
		if not efeitos._clarao and t >= ph.Clarao[1] then
			efeitos._clarao = true
			ctx.Flash(BRANCO, 0, 0.35)
			ctx.Tremer(0.8, 0.3)
		end
	end
	function efeitos.Impacto(s)
		ctx.Flash(rgb(255, 200, 240), 0.35, 0.2)
		anelVazado(pasta, s.BolaMundo, ctx.DirecaoChute, ROSA, 2, 14, 0.3, 0.3)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, ROXO, 12, 0.25, 0.3)
	end
	function efeitos.Voo(ball, duracao)
		-- o FEIXE rosa/roxo com raios amarelos nas bordas e explosões
		efeitoDeVoo(ball, duracao, function(a, coisas)
			luz(a, ROSA, 24, 6)
			table.insert(coisas, destaque(ball, rgb(255, 180, 240), rgb(255, 255, 255), 0.25))
			local pastaVoo = Instance.new("Folder")
			pastaVoo.Name = "LaminaVoo"
			pastaVoo.Parent = workspace
			table.insert(coisas, pastaVoo)
			local cauda = parte(pastaVoo, "LaminaCauda")
			local aBola = Instance.new("Attachment")
			aBola.Parent = ball
			table.insert(coisas, aBola)
			local aCauda = Instance.new("Attachment")
			aCauda.Parent = cauda
			local function feixe(cor, w0, w1, t0, t1, z)
				local b = Instance.new("Beam")
				b.Attachment0, b.Attachment1 = aBola, aCauda
				b.Width0, b.Width1 = w0, w1
				b.Color = cor
				b.Transparency = numeros({ { 0, t0 }, { 1, t1 } })
				b.LightEmission = 1
				b.LightInfluence = 0
				b.FaceCamera = true
				b.ZOffset = z
				b.Parent = cauda
			end
			feixe(cores({ { 0, rgb(255, 230, 250) }, { 0.5, ROSA }, { 1, ROXO } }), 1.8, 16, 0.05, 0.9, 0)
			feixe(cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 200, 240) } }), 0.8, 6, 0, 0.95, 1)
			local raiosBorda = { novoRaio(pastaVoo, DOURADO, 0.18), novoRaio(pastaVoo, rgb(255, 240, 150), 0.14) }
			ctx._lamina = { Cauda = cauda, Raios = raiosBorda, Pasta = pastaVoo, UltimaExplosao = 0 }
		end, function(_a, _dt, tempo)
			local l = ctx._lamina
			if not l then return end
			local v = ball.AssemblyLinearVelocity
			local dir = v.Magnitude > 1 and v.Unit or V3(0, -0.3, -1).Unit
			local comp = math.clamp(v.Magnitude * 0.16, 8, 20)
			local boca = ball.Position - dir * comp
			local lado = dir:Cross(Vector3.yAxis)
			if lado.Magnitude < 0.05 then lado = Vector3.xAxis end
			lado = lado.Unit
			l.Cauda.CFrame = CFrame.lookAt(boca, ball.Position)
			-- raios amarelos correndo pelas bordas do feixe
			for i, r in ipairs(l.Raios) do
				local s = (i == 1) and 1 or -1
				r.Desenhar(ball.Position + lado * s * 0.8, boca + lado * s * 7, 9, 1.2, 0.16, 0.05)
			end
			if tempo - l.UltimaExplosao > 0.11 then
				l.UltimaExplosao = tempo
				local b = parte(l.Pasta, "Explosao", { Shape = Enum.PartType.Ball, Color = rgb(255, 170, 220), Transparency = 0.1,
					Size = V3(1.5, 1.5, 1.5), CFrame = CFrame.new(ball.Position - dir * 3 + lado * (math.random() * 4 - 2)) })
				TweenService:Create(b, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = V3(6, 6, 6), Transparency = 1 }):Play()
				game:GetService("Debris"):AddItem(b, 0.32)
			end
		end)
	end
	return efeitos
end

-- ============================================================
-- 🌌 QUEDA CELESTIAL (Tenkuu Otoshi) — ⚠️ v110
-- ============================================================
-- Pelo vídeo (ver a coreografia): nuvens + clarão amarelo na subida, o céu vira
-- ESPAÇO lá no alto, voleio com anel roxo e ESPINHOS amarelos, e no voo o
-- PORTAL DE UNIVERSO atrás da bola: um cone largo (Beams, de frente pra
-- câmera) com borda MAGENTA e CIANO, o miolo escuro de espaço, planetas
-- passando por dentro dele e riscos amarelos — "uma câmera pra outro universo".
-- Nada de planetas girando em volta da bola (PEDIDO).
local function conePortal(pastaAlvo, ball)
	-- ponta na bola, boca aberta atrás; a parte da boca é reposicionada todo quadro
	local cauda = parte(pastaAlvo, "PortalCauda")
	local aBola = Instance.new("Attachment")
	aBola.Name = "PortalPonta"
	aBola.Parent = ball
	local aCauda = Instance.new("Attachment")
	aCauda.Parent = cauda
	local function feixe(cor, w0, w1, transp0, transp1, brilho, z, textura)
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = aBola, aCauda
		b.Width0, b.Width1 = w0, w1
		b.Color = typeof(cor) == "Color3" and ColorSequence.new(cor) or cor
		b.Transparency = numeros({ { 0, transp0 }, { 1, transp1 } })
		b.LightEmission = brilho
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Segments = 12
		b.ZOffset = z
		if textura then
			b.Texture = textura
			b.TextureMode = Enum.TextureMode.Stretch
			b.TextureSpeed = 2
		end
		b.Parent = cauda
		return b
	end
	local feixes = {
		feixe(cores({ { 0, rgb(170, 240, 255) }, { 1, rgb(40, 190, 255) } }), 1.4, 30, 0.35, 1, 1, -2),                  -- borda ciano (mais larga)
		feixe(cores({ { 0, rgb(255, 150, 255) }, { 0.5, rgb(220, 60, 230) }, { 1, rgb(130, 40, 220) } }), 1.2, 26, 0.15, 0.95, 1, -1), -- borda magenta
		feixe(cores({ { 0, rgb(60, 30, 110) }, { 1, rgb(10, 8, 35) } }), 0.9, 21, 0.05, 0.55, 0, 0),                       -- o ESPAÇO dentro
	}
	-- riscos amarelos correndo dentro do portal
	local riscos = {}
	for i = 1, 5 do
		local a = Instance.new("Attachment")
		a.Parent = cauda
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = aBola, a
		b.Width0, b.Width1 = 0.15, 0.9
		b.Color = cores({ { 0, rgb(255, 250, 200) }, { 1, rgb(255, 170, 60) } })
		b.Transparency = numeros({ { 0, 0.1 }, { 1, 1 } })
		b.LightEmission = 1
		b.LightInfluence = 0
		b.FaceCamera = true
		b.Texture = TEX.Fogo
		b.TextureMode = Enum.TextureMode.Stretch
		b.TextureSpeed = 3
		b.ZOffset = 1
		b.Parent = cauda
		riscos[i] = { A = a, Desvio = V3(math.random() * 2 - 1, math.random() * 2 - 1, 0) * 7, Fase = math.random() * 6 }
	end
	-- planetas passando por dentro (vão da ponta pra boca e reaparecem)
	local planetas = {}
	local coresPl = { rgb(235, 165, 90), rgb(225, 205, 170), rgb(250, 225, 150), rgb(170, 150, 210) }
	for i = 1, 4 do
		local pl = parte(pastaAlvo, "PlanetaPortal" .. i, { Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = coresPl[i] })
		pl.Transparency = 0.15
		planetas[i] = { Parte = pl, Fase = (i - 1) / 4, Tam = 1.6 + math.random() * 2.2, Desvio = V3(math.random() * 2 - 1, math.random() * 2 - 1, 0) }
	end
	local estrelas = emissor(cauda, {
		Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(200, 220, 255) } }), Tamanho = numeros({ { 0, 0.35 }, { 1, 0 } }),
		Vida = { 0.3, 0.6 }, Vel = { 0, 2 }, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, Taxa = 90,
	})
	local brilhoEstrela = emissor(aBola, {
		Textura = TEX.Faisca, Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 200, 255) } }), Tamanho = numeros({ { 0, 3.5 }, { 1, 0 } }),
		Vida = { 0.15, 0.3 }, Vel = { 0, 0 }, Taxa = 40, RotVel = 360,
	})
	local obj = { Coisas = { cauda, aBola } }
	for _, b in ipairs(feixes) do table.insert(obj.Coisas, b) end
	for _, r in ipairs(riscos) do table.insert(obj.Coisas, r.A) end
	for _, pl in ipairs(planetas) do table.insert(obj.Coisas, pl.Parte) end
	table.insert(obj.Coisas, brilhoEstrela)
	function obj.Atualizar(tempo)
		local v = ball.AssemblyLinearVelocity
		local dir = v.Magnitude > 1 and v.Unit or V3(0, -0.3, -1).Unit
		local comp = math.clamp(v.Magnitude * 0.22, 10, 26)
		local boca = ball.Position - dir * comp
		local lado = dir:Cross(Vector3.yAxis)
		if lado.Magnitude < 0.05 then lado = Vector3.xAxis end
		lado = lado.Unit
		local cima = lado:Cross(dir).Unit
		cauda.CFrame = CFrame.fromMatrix(boca, lado, cima)
		cauda.Size = V3(comp * 0.6, comp * 0.6, 1)
		for _, r in ipairs(riscos) do
			local oscila = math.sin(tempo * 7 + r.Fase)
			r.A.WorldPosition = boca + lado * (r.Desvio.X * (0.8 + 0.2 * oscila)) + cima * r.Desvio.Y
		end
		for _, pl in ipairs(planetas) do
			local u = (tempo * 0.9 + pl.Fase) % 1
			local pos = ball.Position - dir * (comp * u) + (lado * pl.Desvio.X + cima * pl.Desvio.Y) * (8 * u)
			pl.Parte.Size = Vector3.one * (pl.Tam * (0.3 + 0.7 * u))
			pl.Parte.CFrame = CFrame.new(pos)
			pl.Parte.Transparency = 0.15 + 0.75 * u
		end
	end
	return obj
end

function E.QuedaCelestial(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local ROXO, MAGENTA, AMARELO, BRANCO = rgb(160, 80, 255), rgb(230, 70, 235), rgb(255, 220, 90), rgb(255, 255, 245)
	-- NUVENS no caminho da subida
	local nuvensPeca = parte(pasta, "Nuvens")
	nuvensPeca.Size = V3(40, 2, 40)
	nuvensPeca.CFrame = CFrame.new(mundo(V3(0, spec.AlturaNuvens, -2)))
	local nuvens = emissor(nuvensPeca, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(210, 225, 245) } }), Brilho = 0.1,
		Tamanho = numeros({ { 0, 8 }, { 1, 14 } }), Transp = numeros({ { 0, 1 }, { 0.2, 0.25 }, { 0.8, 0.35 }, { 1, 1 } }),
		Vida = { 1.5, 2.2 }, Vel = { 0, 1 }, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, Taxa = 0,
	})
	local furo = emissor(nuvensPeca, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 235, 170) } }), Brilho = 0.3,
		Tamanho = numeros({ { 0, 5 }, { 1, 12 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.5, 0.9 }, Vel = { 14, 26 }, Taxa = 0,
	})
	-- o ESPAÇO lá no alto (mesma esfera invertida da Galáxia)
	local centro = mundo(spec.CentroEspaco)
	-- ⚠️ v113 (ver salaEscura): chão da sala rente ao gramado (no espaço o campo
	-- aparecia lá embaixo)
	local ceu = salaEscura(pasta, "CeuQueda", rgb(6, 5, 24), CFrame.new(centro) * ctx.Inicio.Rotation, 200,
		ctx.ChaoY + 0.1 - spec.CentroEspaco.Y)
	local estrelasPeca = parte(pasta, "EstrelasQueda")
	estrelasPeca.Size = V3(150, 100, 150)
	estrelasPeca.CFrame = CFrame.new(centro)
	local estrelas = emissor(estrelasPeca, {
		Cor = cores({ { 0, BRANCO }, { 0.5, rgb(200, 220, 255) }, { 1, rgb(230, 200, 255) } }),
		Tamanho = numeros({ { 0, 0.9 }, { 0.5, 1.3 }, { 1, 0.9 } }), Transp = numeros({ { 0, 1 }, { 0.1, 0 }, { 0.9, 0 }, { 1, 1 } }),
		Vida = { 2.5, 2.5 }, Vel = { 0, 0 }, Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
		RotVel = 30, Travado = true, ZOffset = -2,
	})
	-- as "linhas de velocidade" do espaço no voo deitado (riscos brancos passando)
	local riscosEspaco = emissor(estrelasPeca, {
		Cor = cores({ { 0, BRANCO }, { 1, rgb(170, 190, 255) } }), Tamanho = numeros({ { 0, 0.25 }, { 1, 0.1 } }),
		Vida = { 0.25, 0.4 }, Vel = { 60, 90 }, Spread = 4, Direcao = Enum.NormalId.Back, Taxa = 0, ZOffset = -1,
	})
	-- bola brilhando roxa
	local aura = esfera(pasta, "AuraQueda", ROXO, Enum.Material.ForceField)
	local brilhoBola = emissor(aura, { Cor = cores({ { 0, rgb(240, 225, 255) }, { 1, ROXO } }), Tamanho = 0.45, Vida = { 0.3, 0.6 }, Vel = { 2, 5 } })
	local impacto = parte(pasta, "ImpactoQueda")
	local estouro = emissor(impacto, { Cor = cores({ { 0, BRANCO }, { 0.4, AMARELO }, { 1, ROXO } }), Tamanho = 0.8, Vida = { 0.3, 0.8 }, Vel = { 25, 55 }, Drag = 3 })
	local espinhos = {}
	for i = 1, 12 do espinhos[i] = parte(pasta, "Espinho" .. i, { Color = i % 2 == 0 and AMARELO or MAGENTA }) end
	local furou, espacoLigado, chuteT = false, false, nil
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		-- nuvens aparecem quando ele sobe; o FURO com clarão amarelo
		nuvens.Enabled = t >= 0.6 and t < 1.5
		nuvens.Rate = 25
		if not furou and t >= ph.Clouds[1] then
			furou = true
			nuvensPeca.CFrame = CFrame.new(ctx.Root.Position)
			furo:Emit(40)
			anelVazado(pasta, ctx.Root.Position, Vector3.yAxis, AMARELO, 3, 30, 0.45, 0.35)
			ctx.Flash(rgb(255, 245, 190), 0.35, 0.3)
		end
		-- espaço
		-- ⚠️ v113: some logo depois do voleio — o plano seguinte é do gramado, a bola
		-- brilhando no céu do estádio (10.8s do vídeo); antes ficava tudo preto
		local espaco = smooth(phase(t, ph.Space[1], ph.Space[1] + 0.3)) * (1 - smooth(phase(t, spec.ImpactTime, spec.ImpactTime + 0.12)))
		ceu.Transparency = 1 - espaco
		if not espacoLigado and t >= ph.Space[1] then
			espacoLigado = true
			estrelas:Emit(500)
		end
		estrelasPeca.CFrame = CFrame.lookAt(centro, centro + ctx.Inicio.LookVector)
		riscosEspaco.Enabled = t >= ph.Fly[1] and t < ph.Kick[2]
		riscosEspaco.Rate = 120
		-- bola roxa a partir do voo
		local carga = smooth(phase(t, ph.Fly[1], ph.Kick[1]))
		local tb = (ctx.TamanhoBola or 1.7) * (1.4 + 0.5 * carga)
		aura.Size = V3(tb, tb, tb)
		aura.CFrame = CFrame.new(s.BolaMundo)
		aura.Transparency = carga > 0.02 and (0.3 + 0.1 * math.sin(t * 20)) or 1
		brilhoBola.Enabled = carga > 0.2
		brilhoBola.Rate = 50
		-- ESPINHOS amarelos e magenta abrindo do ponto do chute
		if chuteT then
			local u = phase(t, chuteT, chuteT + 0.35)
			local dirChute = ctx.DirecaoChute
			local lado = dirChute:Cross(Vector3.yAxis)
			if lado.Magnitude < 0.05 then lado = Vector3.xAxis end
			lado = lado.Unit
			local cima = lado:Cross(dirChute).Unit
			for i, e in ipairs(espinhos) do
				local ang = (i / #espinhos) * math.pi * 2
				local radial = lado * math.cos(ang) + cima * math.sin(ang)
				local comp = 9 * easeOut(u) * (i % 2 == 0 and 1 or 0.7)
				local base = s.BolaMundo + radial * (1 + comp * 0.5)
				e.Size = V3(0.35 * (1 - u) + 0.05, 0.35 * (1 - u) + 0.05, math.max(comp, 0.1))
				e.CFrame = CFrame.lookAt(base, base + radial)
				e.Transparency = u >= 1 and 1 or (0.05 + 0.8 * u)
			end
		else
			for _, e in ipairs(espinhos) do e.Transparency = 1 end
		end
	end
	function efeitos.Impacto(s)
		chuteT = spec.ImpactTime
		impacto.CFrame = CFrame.new(s.BolaMundo)
		estouro:Emit(150)
		ctx.Flash(rgb(255, 240, 210), 0.25, 0.3)
		anelVazado(pasta, s.BolaMundo, ctx.DirecaoChute, MAGENTA, 2, 24, 0.45, 0.4)
		anelVazado(pasta, s.BolaMundo, ctx.DirecaoChute, ROXO, 1.5, 16, 0.35, 0.3)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, AMARELO, 20, 0.3, 0.3)
		ctx.Tremer(0.8, 0.35)
	end
	function efeitos.Voo(ball, duracao)
		-- a bola desce como uma ESTRELA com o portal de universo atrás
		efeitoDeVoo(ball, duracao, function(a, coisas)
			luz(a, MAGENTA, 26, 6)
			table.insert(coisas, destaque(ball, rgb(240, 200, 255), rgb(255, 255, 255), 0.25))
			local pastaVoo = Instance.new("Folder")
			pastaVoo.Name = "PortalUniverso"
			pastaVoo.Parent = workspace
			table.insert(coisas, pastaVoo)
			local portal = conePortal(pastaVoo, ball)
			for _, x in ipairs(portal.Coisas) do table.insert(coisas, x) end
			ctx._portal = portal
		end, function(_a, _dt, tempo)
			if ctx._portal then ctx._portal.Atualizar(tempo) end
		end)
	end
	return efeitos
end

-- ============================================================
-- 🪨 RUPTURA DE GAIA — ⚠️ v109
-- ============================================================
-- Feixes de energia AMARELA subindo dos três; ROCHAS brotam do campo em volta,
-- voam até a bola e grudam nela (massa de espinhos); no voo a casca de pedra vai
-- junto, soltando poeira.
local function rochaNova(pastaAlvo, nome)
	local r = parte(pastaAlvo, nome, { Material = Enum.Material.Slate, Color = rgb(125 + math.random(-15, 15), 100 + math.random(-12, 12), 75) })
	local s = 0.9 + math.random() * 1.1
	r.Size = V3(s, s * (1.2 + math.random() * 0.8), s)
	r.Transparency = 1
	return r
end

function E.GaiaBreak(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local AMARELO = rgb(255, 225, 90)
	local feixes = {}
	for i = 1, 3 do feixes[i] = parte(pasta, "FeixeGaia" .. i, { Color = AMARELO }) end
	-- ⚠️ v113 — pelo anime a 0,2s (21.0-23.4s): as rochas são GRANDES, voam
	-- ALTO no feixe amarelo girando e depois se juntam numa massa ESPINHOSA em
	-- volta da bola (pontas pra fora). Antes subiam 2.8 studs e eram pequenas.
	local rochas = {}
	local rng = Random.new(21)
	for i = 1, 18 do
		local ang = rng:NextNumber(0, math.pi * 2)
		local dist = rng:NextNumber(4, 11)
		local p = rochaNova(pasta, "Rocha" .. i)
		local s = rng:NextNumber(1.1, 2)
		p.Size = V3(s, s * rng:NextNumber(1.6, 2.3), s)
		rochas[i] = {
			Parte = p, Tam = s,
			Chao = V3(math.cos(ang) * dist, 0, math.sin(ang) * dist - 3),
			Altura = rng:NextNumber(4, 13),
			Deriva = V3(math.cos(ang), 0, math.sin(ang)) * rng:NextNumber(1, 4),
			Dir = V3(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
			Rot = CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), rng:NextNumber(0, 6)),
			Giro = V3(rng:NextNumber(-4, 4), rng:NextNumber(-4, 4), rng:NextNumber(-4, 4)),
			Quando = 0.6 + i * 0.025,
		}
	end
	local poeiraFx = parte(pasta, "PoeiraGaia")
	local poeira = emissor(poeiraFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(210, 190, 150) }, { 1, rgb(130, 105, 75) } }), Brilho = 0,
		Tamanho = numeros({ { 0, 3 }, { 1, 8 } }), Transp = numeros({ { 0, 0.3 }, { 1, 1 } }), Vida = { 0.6, 1.1 },
		Vel = { 6, 12 }, Spread = 70, Direcao = Enum.NormalId.Top,
	})
	local impacto = parte(pasta, "ImpactoGaia")
	local estilhacos = emissor(impacto, { Cor = cores({ { 0, rgb(255, 245, 200) }, { 1, rgb(150, 120, 80) } }), Tamanho = 0.6, Vida = { 0.3, 0.7 }, Vel = { 20, 40 }, Acel = V3(0, -30, 0) })
	local brotou = false
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local ph = spec.Phases
		-- feixes amarelos subindo dos três
		local corpos = { ctx.Root }
		for i = 1, 2 do if ctx.Clones and ctx.Clones[i] then corpos[#corpos + 1] = ctx.Clones[i].Root end end
		local feixe = smooth(phase(t, ph.Beam[1], ph.Beam[1] + 0.2)) * (1 - smooth(phase(t, ph.Beam[2] - 0.2, ph.Beam[2])))
		for i, f in ipairs(feixes) do
			local r = corpos[i]
			if r and feixe > 0.02 then
				f.Size = V3(1.6, 26 * feixe, 1.6)
				f.CFrame = CFrame.new(r.Position + V3(0, 13 * feixe - 2, 0))
				f.Transparency = 1 - feixe * 0.6
			else
				f.Transparency = 1
			end
		end
		-- rochas: brotam do campo, voam pra bola e grudam nela
		if not brotou and t >= ph.Rocks[1] then
			brotou = true
			poeiraFx.CFrame = CFrame.new(mundo(V3(0, ctx.ChaoY, -3)))
			poeira:Emit(40)
			ctx.Tremer(0.5, 0.4)
		end
		local bola = s.BolaMundo
		for _, r in ipairs(rochas) do
			local sobe = easeOut(phase(t, r.Quando, r.Quando + 0.45))
			local gruda = smooth(phase(t, ph.Gather[1] + (r.Quando - 0.6) * 0.5, ph.Gather[2]))
			local alto = V3(r.Chao.X, ctx.ChaoY - 1.5 + (r.Altura + 1.5) * sobe, r.Chao.Z) + r.Deriva * sobe
			local voando = CFrame.new(mundo(alto)) * r.Rot
				* CFrame.Angles(r.Giro.X * t, r.Giro.Y * t, r.Giro.Z * t)
			-- grudada: ponta pra fora (o eixo comprido da rocha na direção Dir)
			local naBola = bola + r.Dir * ((ctx.TamanhoBola or 1.7) * 0.4 + r.Tam * 0.5)
			local grudada = CFrame.lookAt(naBola, naBola + r.Dir) * CFrame.Angles(-math.pi / 2, 0, 0)
			r.Parte.CFrame = voando:Lerp(grudada, gruda)
			local some = s.ImpactoFeito and 1 or 0
			r.Parte.Transparency = (sobe > 0.02 and some == 0) and 0 or 1
		end
	end
	function efeitos.Impacto(s)
		impacto.CFrame = CFrame.new(s.BolaMundo)
		estilhacos:Emit(90)
		ctx.Flash(rgb(255, 240, 190), 0.3, 0.25)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, AMARELO, 26, 0.35, 0.35)
		onda(pasta, s.BolaMundo, ctx.DirecaoChute, rgb(150, 120, 80), 18, 0.3, 0.3)
	end
	function efeitos.Voo(ball, duracao)
		efeitoDeVoo(ball, duracao, function(a, coisas)
			emissor(a, {
				Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(210, 190, 150) }, { 1, rgb(120, 95, 70) } }), Brilho = 0,
				Tamanho = numeros({ { 0, 1.5 }, { 1, 3.5 } }), Transp = numeros({ { 0, 0.3 }, { 1, 1 } }), Vida = { 0.3, 0.6 }, Vel = { 0.5, 2 }, Taxa = 60,
			})
			luz(a, AMARELO, 14, 3)
			-- a casca de pedra vai junto com a bola
			local pastaVoo = Instance.new("Folder")
			pastaVoo.Name = "CascaGaia"
			pastaVoo.Parent = workspace
			table.insert(coisas, pastaVoo)
			local casca = {}
			for i = 1, 12 do
				local r = rochaNova(pastaVoo, "RochaVoo" .. i)
				local s = 1 + math.random() * 0.9
				r.Size = V3(s, s * 1.8, s)
				r.Transparency = 0
				casca[i] = { Parte = r, Tam = s, Dir = V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit }
			end
			ctx._cascaGaia = casca
		end, function(_a, _dt, tempo)
			-- massa espinhosa girando com a bola (pontas pra fora)
			local giro = CFrame.Angles(tempo * 3, tempo * 2, 0)
			for _, r in ipairs(ctx._cascaGaia or {}) do
				local d = giro:VectorToWorldSpace(r.Dir)
				local pos = ball.Position + d * (ball.Size.X * 0.4 + r.Tam * 0.55)
				r.Parte.CFrame = CFrame.lookAt(pos, pos + d) * CFrame.Angles(-math.pi / 2, 0, 0)
			end
		end)
	end
	return efeitos
end

-- ============================================================
-- ☄️ CHUVA DE METEOROS — ⚠️ v110
-- ============================================================
-- A bola pega fogo subindo com ele, a bicicleta manda ela pro céu, lá em cima
-- ela EXPLODE em 6 meteoros, e cada um cai em cima de um adversário perto (o
-- servidor derruba esses mesmos no fim da cena). Sem adversário perto, os
-- meteoros caem em volta dele. Cada queda: explosão, onda de choque e uma
-- CRATERA que fica no campo uns segundos depois da cutscene.
local Players = game:GetService("Players")
local Debris = game:GetService("Debris")

local function alvosDosMeteoros(ctx, qtd, raio)
	local meu = Players:GetPlayerFromCharacter(ctx.Character)
	local centro = ctx.Inicio.Position
	local chaoMundo = ctx.Mundo(V3(0, ctx.ChaoY, 0)).Y
	local alvos = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl ~= meu and not (meu and meu.Team and pl.Team == meu.Team) then
			local r = pl.Character and pl.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - centro).Magnitude <= raio then
				table.insert(alvos, V3(r.Position.X, chaoMundo, r.Position.Z))
			end
		end
	end
	-- completa com pontos em volta (leque na frente e dos lados)
	local rng = Random.new(7)
	local i = 0
	while #alvos < qtd do
		i += 1
		local ang = math.rad(-160 + (i - 1) * (320 / math.max(qtd - 1, 1))) + rng:NextNumber(-0.2, 0.2)
		local dist = rng:NextNumber(9, 17)
		local p = ctx.Mundo(V3(math.sin(ang) * dist, 0, -math.cos(ang) * dist - 3))
		table.insert(alvos, V3(p.X, chaoMundo, p.Z))
	end
	return alvos
end

-- cratera que sobrevive à cutscene (pasta própria, some sozinha)
local function crateraNoChao(pos, cor)
	local pasta = Instance.new("Folder")
	pasta.Name = "CrateraMeteoro"
	pasta.Parent = workspace
	local fundo = parte(pasta, "Fundo", { Shape = Enum.PartType.Cylinder, Material = Enum.Material.CrackedLava,
		Color = rgb(60, 30, 20), Transparency = 0 })
	fundo.Size = V3(0.25, 9, 9)
	fundo.CFrame = CFrame.new(pos + V3(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local brasa = parte(pasta, "Brasa", { Shape = Enum.PartType.Cylinder, Color = cor, Transparency = 0.2 })
	brasa.Size = V3(0.2, 4, 4)
	brasa.CFrame = CFrame.new(pos + V3(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local rochas = {}
	for k = 1, 9 do
		local ang = (k / 9) * math.pi * 2 + math.random() * 0.3
		local r = parte(pasta, "Borda" .. k, { Material = Enum.Material.Basalt, Color = rgb(70 + math.random(-10, 10), 55, 45), Transparency = 0 })
		local s = 1 + math.random() * 1.2
		r.Size = V3(s * 1.4, s, s)
		r.CFrame = CFrame.new(pos + V3(math.cos(ang) * 4.6, s * 0.3, math.sin(ang) * 4.6))
			* CFrame.Angles(math.random() * 0.8, -ang, math.random() * 0.8)
		rochas[k] = r
	end
	local fumacaFx = parte(pasta, "FumacaCratera")
	fumacaFx.CFrame = CFrame.new(pos + V3(0, 0.5, 0))
	local fumaca = emissor(fumacaFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(90, 70, 60) }, { 1, rgb(40, 35, 35) } }), Brilho = 0,
		Tamanho = numeros({ { 0, 2.5 }, { 1, 6 } }), Transp = numeros({ { 0, 0.4 }, { 1, 1 } }),
		Vida = { 1.2, 2 }, Vel = { 2, 4 }, Spread = 25, Direcao = Enum.NormalId.Top, Taxa = 14,
	})
	local brasas = emissor(fumacaFx, {
		Cor = cores({ { 0, rgb(255, 230, 150) }, { 1, cor } }), Tamanho = 0.35, Vida = { 0.6, 1.2 },
		Vel = { 3, 7 }, Spread = 35, Direcao = Enum.NormalId.Top, Acel = V3(0, -4, 0), Taxa = 20,
	})
	luz(brasa, cor, 12, 2)
	-- apaga devagar depois de uns segundos
	task.delay(4, function()
		fumaca.Enabled = false
		brasas.Enabled = false
		local info = TweenInfo.new(1.6)
		for _, p in ipairs(pasta:GetChildren()) do
			if p:IsA("BasePart") then TweenService:Create(p, info, { Transparency = 1 }):Play() end
		end
	end)
	Debris:AddItem(pasta, 6.5)
end

function E.Meteoros(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local LARANJA, AMARELO, VERMELHO = rgb(255, 130, 30), rgb(255, 220, 110), rgb(200, 40, 10)
	local N = 6
	local alvos = alvosDosMeteoros(ctx, N, 26)

	-- fogo na bola enquanto sobe
	local fogoBola = parte(pasta, "FogoBola")
	local chamas = emissor(fogoBola, {
		Textura = TEX.Fogo, Cor = cores({ { 0, AMARELO }, { 0.5, LARANJA }, { 1, VERMELHO } }), Brilho = 1,
		Tamanho = numeros({ { 0, 2.2 }, { 1, 0.3 } }), Vida = { 0.25, 0.45 }, Vel = { 1, 3 }, Taxa = 0,
	})
	local rastroBola = rastroDuplo(fogoBola, 1.1, LARANJA, AMARELO, 0.3)
	local luzBola = luz(fogoBola, LARANJA, 0, 4)

	-- os meteoros (nascem no céu quando a bola explode)
	local meteoros = {}
	for i = 1, N do
		local nucleo = parte(pasta, "Meteoro" .. i, { Shape = Enum.PartType.Ball, Material = Enum.Material.Basalt,
			Color = rgb(60, 35, 25), Size = V3(2.4, 2.4, 2.4) })
		local casca = esfera(pasta, "Casca" .. i, LARANJA)
		casca.Size = V3(3.4, 3.4, 3.4)
		local fogo = emissor(nucleo, {
			Textura = TEX.Fogo, Cor = cores({ { 0, AMARELO }, { 0.4, LARANJA }, { 1, VERMELHO } }), Brilho = 1,
			Tamanho = numeros({ { 0, 3.2 }, { 1, 0.4 } }), Vida = { 0.25, 0.5 }, Vel = { 1, 3 }, Taxa = 0,
		})
		local r = rastroDuplo(nucleo, 1.5, LARANJA, AMARELO, 0.35)
		local l = luz(nucleo, LARANJA, 0, 5)
		local chegada = spec.Phases.Rain[1] + (i - 1) * ((spec.Phases.Rain[2] - spec.Phases.Rain[1]) / (N - 1))
		meteoros[i] = {
			Nucleo = nucleo, Casca = casca, Fogo = fogo, Rastro = r, Luz = l,
			Alvo = alvos[i], Chegada = chegada, Caiu = false,
			Lado = V3(math.random() * 2 - 1, 0, math.random() * 2 - 1) * 6,
		}
	end

	local explodiu = false
	local explosaoCeu = parte(pasta, "ExplosaoCeu")
	local faiscasCeu = emissor(explosaoCeu, { Cor = cores({ { 0, AMARELO }, { 1, LARANJA } }), Tamanho = 0.7,
		Vida = { 0.3, 0.7 }, Vel = { 25, 45 } })
	local impactoFx = parte(pasta, "ImpactoMeteoro")
	local estilhacos = emissor(impactoFx, { Cor = cores({ { 0, AMARELO }, { 1, rgb(90, 50, 30) } }), Tamanho = 0.7,
		Vida = { 0.4, 0.9 }, Vel = { 18, 36 }, Spread = 70, Direcao = Enum.NormalId.Top, Acel = V3(0, -40, 0) })
	local labareda = emissor(impactoFx, {
		Textura = TEX.Fogo, Cor = cores({ { 0, AMARELO }, { 0.5, LARANJA }, { 1, VERMELHO } }), Brilho = 1,
		Tamanho = numeros({ { 0, 4 }, { 1, 1 } }), Vida = { 0.3, 0.6 }, Vel = { 10, 22 }, Spread = 50, Direcao = Enum.NormalId.Top,
	})
	local poeiraFx = parte(pasta, "PoeiraMeteoro")
	local poeira = emissor(poeiraFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(170, 140, 110) }, { 1, rgb(90, 75, 65) } }), Brilho = 0,
		Tamanho = numeros({ { 0, 3 }, { 1, 9 } }), Transp = numeros({ { 0, 0.25 }, { 1, 1 } }), Vida = { 0.6, 1.1 },
		Vel = { 10, 18 }, Spread = 80, Direcao = Enum.NormalId.Top,
	})

	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		-- bola acesa até explodir no céu
		local acesa = smooth(phase(t, 0.2, 0.6))
		fogoBola.CFrame = CFrame.new(s.BolaMundo)
		chamas.Enabled = acesa > 0.05 and t < 1.8
		chamas.Rate = 50 + 80 * acesa
		rastroBola.Ligar(acesa > 0.3 and t < 1.8)
		luzBola.Range = (t < 1.8) and 14 * acesa or 0

		if not explodiu and t >= 1.8 then
			explodiu = true
			local ceu = mundo(spec.Ceu)
			explosaoCeu.CFrame = CFrame.new(ceu)
			faiscasCeu:Emit(80)
			onda(pasta, ceu, Vector3.yAxis, LARANJA, 24, 0.4, 0.4)
			anelVazado(pasta, ceu, Vector3.yAxis, AMARELO, 3, 30, 0.5, 0.3)
			ctx.Flash(rgb(255, 200, 120), 0.35, 0.3)
		end

		local ceu = mundo(spec.Ceu)
		for _, m in ipairs(meteoros) do
			if t < 1.8 or m.Caiu then
				m.Nucleo.Transparency = 1
				m.Casca.Transparency = 1
				m.Fogo.Enabled = false
				m.Rastro.Ligar(false)
				m.Luz.Range = 0
			else
				-- sai do céu abrindo pros lados e ACELERA descendo até o alvo
				local u = phase(t, 1.8, m.Chegada)
				local abre = ceu + m.Lado + V3(0, 4, 0)
				local a = ceu:Lerp(abre, smooth(math.min(u * 2.5, 1)))
				local pos = a:Lerp(m.Alvo + V3(0, 1.2, 0), u * u * u)
				m.Nucleo.CFrame = CFrame.new(pos) * CFrame.Angles(t * 6, t * 4, 0)
				m.Casca.CFrame = CFrame.new(pos)
				m.Nucleo.Transparency = 0
				m.Casca.Transparency = 0.45 + 0.1 * math.sin(t * 30)
				m.Fogo.Enabled = true
				m.Fogo.Rate = 90
				m.Rastro.Ligar(true)
				m.Luz.Range = 16
				if t >= m.Chegada then
					m.Caiu = true
					impactoFx.CFrame = CFrame.new(m.Alvo + V3(0, 0.5, 0))
					estilhacos:Emit(35)
					labareda:Emit(22)
					poeiraFx.CFrame = CFrame.new(m.Alvo + V3(0, 0.5, 0))
					poeira:Emit(18)
					onda(pasta, m.Alvo + V3(0, 0.3, 0), Vector3.yAxis, LARANJA, 16, 0.35, 0.35)
					anelVazado(pasta, m.Alvo + V3(0, 0.4, 0), Vector3.yAxis, AMARELO, 2, 20, 0.45, 0.3)
					crateraNoChao(m.Alvo, LARANJA)
					-- ⚠️ v113 (anime a 0,2s, 7.8-10.4s): cada meteoro levanta uma
					-- COLUNA de fogo alta (laranja por fora, miolo amarelo)
					for camada = 1, 2 do
						local larg = camada == 1 and 5 or 2.6
						local col = parte(pasta, "ColunaFogo", { Shape = Enum.PartType.Cylinder,
							Color = camada == 1 and LARANJA or AMARELO, Transparency = camada == 1 and 0.3 or 0.1 })
						col.Size = V3(0.5, larg, larg)
						col.CFrame = CFrame.new(m.Alvo) * CFrame.Angles(0, 0, math.rad(90))
						local alto = camada == 1 and 16 or 19
						TweenService:Create(col, TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
							{ Size = V3(alto, larg, larg), CFrame = CFrame.new(m.Alvo + V3(0, alto / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }):Play()
						task.delay(0.14, function()
							if col.Parent then
								TweenService:Create(col, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
									{ Size = V3(alto * 1.1, larg * 0.3, larg * 0.3), Transparency = 1 }):Play()
							end
						end)
						game:GetService("Debris"):AddItem(col, 0.6)
					end
					ctx.Tremer(0.9, 0.25)
				end
			end
		end
	end
	function efeitos.Impacto(s)
		-- a bicicleta: estouro de fogo no pé
		impactoFx.CFrame = CFrame.new(s.BolaMundo)
		labareda:Emit(30)
		onda(pasta, s.BolaMundo, ctx.Inicio.RightVector, LARANJA, 14, 0.3, 0.3)
	end
	function efeitos.Voo(ball, duracao)
		-- a bola que volta pro pé continua em brasa um instante
		efeitoDeVoo(ball, math.min(duracao, 1.5), function(a)
			emissor(a, {
				Textura = TEX.Fogo, Cor = cores({ { 0, AMARELO }, { 1, VERMELHO } }), Brilho = 1,
				Tamanho = numeros({ { 0, 1.6 }, { 1, 0.2 } }), Vida = { 0.2, 0.4 }, Vel = { 1, 2 }, Taxa = 40,
			})
		end)
	end
	return efeitos
end

-- ============================================================
-- ⚠️ v109 — ESTILOS DE DEFESA NOVOS (Bloco de Gelo, Escudo de Força, Deuses do
-- Vento e Trovão). Cada um devolve uma função chamada todo quadro:
-- f(t, bola(local), pontoChoque(mundo), noChoque, alfa, D). Os outros dois
-- novos reaproveitam peças que já existiam: Punho da Justiça = a mão gigante
-- fechada (dourada), Soco Ardente = o fogo nos punhos + um soco só explosivo.
-- ============================================================
local ESTILOS_NOVOS = {}

-- Ice Block — ⚠️ v110 pelo vídeo "Ice Block" a 0,1s: (1) CRISTAIS de gelo
-- pontudos se formam na mão direita erguida (0-1.5s); (2) no soco, EXPLOSÃO de
-- névoa gelada (2.4-2.6s); (3) a bola fica presa num BLOCO DE GELO GRANDE, do
-- chão até perto do ombro, translúcido, com pontas em cima (2.7-4.6s). Antes
-- era um floco plano e um cubo do tamanho da bola.
ESTILOS_NOVOS.BlocoGelo = function(ctx, pasta, cor, claro, mundo)
	local GELO = rgb(190, 235, 255)
	local cristais, dirs = {}, {}
	for i = 1, 7 do
		cristais[i] = parte(pasta, "Cristal" .. i, { Color = GELO, Material = Enum.Material.Ice })
		local a, b = math.random() * math.pi * 2, math.random() * 1.2 - 0.3
		dirs[i] = Vector3.new(math.cos(a) * math.cos(b), math.sin(b) + 0.35, math.sin(a) * math.cos(b)).Unit
	end
	local miolo = esfera(pasta, "CristalMiolo", rgb(235, 250, 255))
	local bloco = parte(pasta, "BlocoGelo", { Material = Enum.Material.Ice, Color = GELO })
	local pontas = {}
	for i = 1, 6 do pontas[i] = parte(pasta, "PontaGelo" .. i, { Material = Enum.Material.Ice, Color = rgb(215, 245, 255) }) end
	local geada = emissor(bloco, { Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, GELO } }), Tamanho = 0.35, Vida = { 0.4, 0.8 }, Vel = { 2, 5 }, RotVel = 200 })
	local nevoaFx = parte(pasta, "NevoaGelo")
	local nevoa = emissor(nevoaFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(250, 254, 255) }, { 1, rgb(170, 220, 250) } }), Brilho = 0.2,
		Tamanho = numeros({ { 0, 3 }, { 1, 8 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }),
		Vida = { 0.5, 1.0 }, Vel = { 10, 20 }, Drag = 3, Spread = 180, Taxa = 0,
	})
	local explodiu = false
	local braco = ctx.Character:FindFirstChild("RightHand") or ctx.Character:FindFirstChild("Right Arm")
	return function(t, bola, pontoChoque, noChoque, alfa, D)
		-- (1) cristais na mão, crescendo; no soco vão até a bola e somem
		local k = smooth(phase(t, 0.05, 0.6))
		local vaiNaBola = smooth(phase(t, 0.7, 0.85))
		local mao = braco and (braco.Name == "Right Arm" and braco.CFrame * CFrame.new(0, -1.3, 0) or braco.CFrame) or ctx.Root.CFrame
		local centro = mao.Position:Lerp(mundo(bola), vaiNaBola)
		local some = 1 - smooth(phase(t, 0.82, 0.92))
		for i, c in ipairs(cristais) do
			local len = (0.9 + (i % 3) * 0.5) * 2.6 * k * some
			local d = ctx.Inicio:VectorToWorldSpace(dirs[i])
			c.Size = V3(0.45, math.max(len, 0.05), 0.45)
			c.CFrame = CFrame.lookAt(centro + d * len / 2, centro + d * len) * CFrame.Angles(math.rad(90), 0, 0)
			c.Transparency = len > 0.1 and 0.15 or 1
		end
		miolo.Size = Vector3.one * math.max(0.9 * k * some, 0.05)
		miolo.CFrame = CFrame.new(centro)
		miolo.Transparency = k * some > 0.1 and 0.25 or 1
		-- (2) explosão de névoa gelada no choque
		if not explodiu and t >= 0.8 then
			explodiu = true
			nevoaFx.CFrame = CFrame.new(mundo(bola))
			nevoa:Emit(45)
			anelVazado(pasta, mundo(bola), ctx.Inicio.LookVector, rgb(230, 248, 255), 2, 14, 0.45, 0.3)
			ctx.Flash(rgb(230, 248, 255), 0.35, 0.2)
		end
		-- (3) bloco grande do chão até acima da bola
		local gelado = smooth(phase(t, 0.82, 1.0)) * alfa
		local chao = ctx.ChaoY or -2.9
		local topo = math.max(bola.Y + 2.4, chao + 6)
		local altura = (topo - chao) * gelado
		local largura, fundo = 5.2, 4.4
		local base = ctx.Inicio * CFrame.new(bola.X, chao + altura / 2, bola.Z) * CFrame.Angles(0, math.rad(12), 0)
		bloco.Size = V3(largura, math.max(altura, 0.05), fundo)
		bloco.CFrame = base
		bloco.Transparency = gelado > 0.02 and (1 - gelado * 0.55) or 1
		geada.Enabled = gelado > 0.3
		geada.Rate = 30
		for i, pt in ipairs(pontas) do
			local x = -largura / 2 + (i - 0.5) * (largura / #pontas)
			local h = (1.2 + (i % 3) * 0.7) * gelado
			pt.Size = V3(0.8, math.max(h, 0.05), 0.8)
			pt.CFrame = base * CFrame.new(x, altura / 2 + h / 2 - 0.2, (i % 2 == 0) and 0.8 or -0.8) * CFrame.Angles(0, 0, math.rad((i % 2 == 0) and 14 or -14))
			pt.Transparency = gelado > 0.05 and (1 - gelado * 0.6) or 1
		end
	end
end

-- ⚠️ v110 — SOCO ARDENTE pelo vídeo "Nekketsu Punch" (quadros a cada 0,1s): o
-- punho PEGA FOGO (3.5-3.8s) e vira uma bola de fogo grande no soco (3.9-5.8s),
-- com CLARÃO laranja e faíscas no impacto. Antes era só um foguinho na mão.
ESTILOS_NOVOS.SocoArdente = function(ctx, pasta, cor, claro, mundo)
	local nucleo = esfera(pasta, "PunhoFogo", rgb(255, 170, 60))
	local luzFogo = luz(nucleo, rgb(255, 140, 40), 0, 8)
	local chamas = emissor(nucleo, {
		Textura = TEX.Fogo, Cor = cores({ { 0, rgb(255, 240, 160) }, { 0.5, rgb(255, 130, 30) }, { 1, rgb(200, 40, 10) } }),
		Brilho = 0.8, Tamanho = numeros({ { 0, 3.2 }, { 1, 0.4 } }), Transp = numeros({ { 0, 0.1 }, { 1, 1 } }),
		Vida = { 0.25, 0.45 }, Vel = { 3, 7 }, Spread = 180, Acel = V3(0, 8, 0), Taxa = 0,
	})
	local faiscasFx = parte(pasta, "FaiscasSoco")
	local faiscas = emissor(faiscasFx, {
		Cor = cores({ { 0, rgb(255, 250, 200) }, { 1, rgb(255, 120, 30) } }), Tamanho = 0.5, Vida = { 0.3, 0.6 }, Vel = { 18, 34 },
		Spread = 180, Drag = 3, Taxa = 0,
	})
	local bateu = false
	local braco = ctx.Character:FindFirstChild("RightHand") or ctx.Character:FindFirstChild("Right Arm")
	return function(t, bola, pontoChoque, noChoque, alfa, D)
		local mao = braco and (braco.Name == "Right Arm" and (braco.CFrame * CFrame.new(0, -1.1, 0)).Position or braco.Position) or ctx.Root.Position
		local acende = smooth(phase(t, 0.3, 0.5))
		local soco = smooth(phase(t, 0.55, 0.8))
		local tamanho = (0.6 + 1.6 * soco) * acende * (1 - smooth(phase(t, D - 0.4, D)))
		nucleo.Size = Vector3.one * math.max(tamanho, 0.05)
		nucleo.CFrame = CFrame.new(mao)
		nucleo.Transparency = tamanho > 0.1 and 0.35 or 1
		chamas.Enabled = tamanho > 0.1
		chamas.Rate = 80
		luzFogo.Range = 16 * acende
		if not bateu and t >= 0.8 then
			bateu = true
			faiscasFx.CFrame = CFrame.new(pontoChoque)
			faiscas:Emit(40)
			ctx.Flash(rgb(255, 170, 70), 0.3, 0.25)
			ctx.Tremer(0.5, 0.25)
			anelVazado(pasta, pontoChoque, ctx.Inicio.LookVector, rgb(255, 160, 50), 2, 12, 0.35, 0.3)
		end
	end
end

-- ⚠️ v110 — PUNHO DA JUSTIÇA pelo vídeo "Seigi no Tekken G5" (quadros a cada
-- 0,1s): (1) ele FINCA os pés e levanta poeira (3.9-4.6s); (2) uma ESPIRAL de
-- energia dourada gira em volta do braço e o punho se forma dela (5.2-7.9s); a
-- espiral acompanha o punho até a bola e fica girando no choque (12-15s).
ESTILOS_NOVOS.PunhoJustica = function(ctx, pasta, cor, claro, mundo)
	local fitas = {}
	for i = 1, 12 do
		fitas[i] = parte(pasta, "EspiralJustica" .. i, { Color = i % 2 == 0 and claro or cor })
	end
	local poeiraFx = parte(pasta, "PoeiraJustica")
	local poeira = emissor(poeiraFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(235, 215, 170) }, { 1, rgb(170, 140, 100) } }), Brilho = 0,
		Tamanho = numeros({ { 0, 1.5 }, { 1, 4 } }), Transp = numeros({ { 0, 0.3 }, { 1, 1 } }),
		Vida = { 0.5, 0.9 }, Vel = { 6, 12 }, Drag = 3, Spread = 80, Direcao = Enum.NormalId.Top, Taxa = 0,
	})
	local pisou = false
	local braco = ctx.Character:FindFirstChild("RightHand") or ctx.Character:FindFirstChild("Right Arm")
	return function(t, bola, pontoChoque, noChoque, alfa, D)
		if not pisou and t >= 0.1 then
			pisou = true
			local pe = mundo(V3(0, (ctx.ChaoY or -2.9) + 0.2, 0))
			poeiraFx.CFrame = CFrame.new(pe)
			poeira:Emit(28)
			anelVazado(pasta, pe, Vector3.yAxis, rgb(240, 215, 150), 2, 11, 0.4, 0.2)
			ctx.Tremer(0.25, 0.15)
		end
		local maoPos = braco and (braco.Name == "Right Arm" and (braco.CFrame * CFrame.new(0, -1.1, 0)).Position or braco.Position) or ctx.Root.Position
		local vai = smooth(phase(t, 0.55, 0.8))
		local centro = maoPos:Lerp(pontoChoque, vai)
		local eixo = ctx.Inicio.LookVector
		local direita, cima = ctx.Inicio.RightVector, ctx.Inicio.UpVector
		local raio = (1 + 2.6 * smooth(phase(t, 0.2, 0.6))) * (1 + 0.6 * vai)
		local visivel = t > 0.18 and alfa > 0.05
		for i, f in ipairs(fitas) do
			local ang = t * 9 + i * (math.pi * 2 / #fitas)
			local ao_longo = ((i / #fitas) - 0.5) * (3 + 2 * vai)
			local radial = direita * math.cos(ang) + cima * math.sin(ang)
			local tangente = (direita * -math.sin(ang) + cima * math.cos(ang)) + eixo * 0.35
			local pos = centro + radial * raio + eixo * ao_longo
			f.Size = V3(0.32, 0.32, 1.7)
			f.CFrame = CFrame.lookAt(pos, pos + tangente)
			f.Transparency = visivel and (0.1 + 0.5 * (1 - alfa)) or 1
		end
	end
end

-- Power Shield — ⚠️ v110 pelo vídeo "Power Shield" (0,1s): ele SALTA alto
-- (11-12.8s), desce SOCANDO o chão (12.9-13.2s) e do chão sobe uma PAREDE
-- dourada de energia, larga e plana, na frente dele (13.3-14.3s), que segura a
-- bola (14.4-16.9s). Antes subia uma cúpula (esfera).
ESTILOS_NOVOS.EscudoForca = function(ctx, pasta, cor, claro, mundo)
	local parede = parte(pasta, "ParedeEscudo", { Material = Enum.Material.ForceField, Color = cor })
	local miolo = parte(pasta, "ParedeEscudoMiolo", { Material = Enum.Material.Neon, Color = claro })
	local listras = {}
	for i = 1, 9 do listras[i] = parte(pasta, "ListraEscudo" .. i, { Material = Enum.Material.Neon, Color = rgb(255, 245, 200) }) end
	local faiscas = emissor(parede, {
		Cor = cores({ { 0, rgb(255, 255, 230) }, { 1, cor } }), Tamanho = 0.45, Vida = { 0.25, 0.6 }, Vel = { 3, 9 },
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Surface, RotVel = 300,
	})
	local bateu = false
	return function(t, bola, pontoChoque, noChoque, alfa, D)
		local chao = ctx.ChaoY or -2.9
		if not bateu and t >= 0.62 then
			bateu = true
			anelVazado(pasta, mundo(V3(0, chao + 0.2, -1)), Vector3.yAxis, cor, 3, 20, 0.5, 0.35)
			ctx.Flash(rgb(255, 240, 190), 0.3, 0.2)
			ctx.Tremer(0.5, 0.25)
		end
		local sobe = easeOut(phase(t, 0.62, 0.85))
		local largura, alturaMax = 15, 10
		local altura = alturaMax * sobe
		local z = bola.Z + 2.2
		local cf = ctx.Inicio * CFrame.new(0, chao + altura / 2, z)
		local vis = altura > 0.2 and alfa > 0.02
		parede.Size = V3(largura, math.max(altura, 0.1), 0.6)
		parede.CFrame = cf
		parede.Transparency = vis and (1 - alfa * (0.7 + 0.1 * math.sin(t * 22))) or 1
		miolo.Size = V3(largura * 0.97, math.max(altura * 0.97, 0.1), 0.2)
		miolo.CFrame = cf
		miolo.Transparency = vis and (1 - alfa * 0.3) or 1
		for i, l in ipairs(listras) do
			local x = -largura / 2 + (i - 0.5) * (largura / #listras)
			local h = altura * (0.55 + 0.45 * math.abs(math.sin(t * 6 + i)))
			l.Size = V3(0.18, math.max(h, 0.05), 0.25)
			l.CFrame = ctx.Inicio * CFrame.new(x, chao + h / 2, z - 0.35)
			l.Transparency = vis and (1 - alfa * 0.8) or 1
		end
		faiscas.Enabled = vis and altura > 2
		faiscas.Rate = 70
	end
end

-- Fuujin Raijin: RELÂMPAGOS caindo do lado direito e uma TEMPESTADE de vento
-- (anéis subindo em tornado) do lado esquerdo; os dois convergem na bola.
ESTILOS_NOVOS.FuujinRaijin = function(ctx, pasta, cor, claro, mundo)
	local raios = {}
	for i = 1, 4 do raios[i] = novoRaio(pasta, i % 2 == 0 and rgb(255, 250, 200) or rgb(255, 215, 60), 0.2) end
	local ventoFx = parte(pasta, "VentoFuujin")
	local vento = emissor(ventoFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(220, 255, 245) }, { 1, rgb(90, 200, 170) } }), Brilho = 0.3,
		Tamanho = numeros({ { 0, 2 }, { 1, 5 } }), Transp = numeros({ { 0, 0.3 }, { 1, 1 } }),
		Vida = { 0.5, 0.9 }, Vel = { 8, 14 }, Spread = 25, RotVel = 200,
	})
	local ultimoAnel = -1
	-- ⚠️ v110 — pelo vídeo "Fuujin Raijin" (Ares, 0,1s): os DOIS DEUSES surgem
	-- atrás do goleiro (6.3-12.5s) — Fuujin (vento, ciano/branco) à esquerda e
	-- Raijin (trovão, vermelho/laranja, com o ARCO DE TAMBORES) à direita — e se
	-- inclinam pra bola no soco (12.6-17s). Antes só havia raios e vento soltos.
	local function deus(nome, corCorpo, corDetalhe)
		local d = {
			Tronco = parte(pasta, nome .. "Tronco", { Color = corCorpo, Material = Enum.Material.Neon }),
			Cabeca = parte(pasta, nome .. "Cabeca", { Color = corCorpo, Material = Enum.Material.Neon }),
			BracoE = parte(pasta, nome .. "BracoE", { Color = corCorpo, Material = Enum.Material.Neon }),
			BracoD = parte(pasta, nome .. "BracoD", { Color = corCorpo, Material = Enum.Material.Neon }),
			OlhoE = parte(pasta, nome .. "OlhoE", { Color = rgb(255, 255, 255), Material = Enum.Material.Neon }),
			OlhoD = parte(pasta, nome .. "OlhoD", { Color = rgb(255, 255, 255), Material = Enum.Material.Neon }),
			Chifres = { parte(pasta, nome .. "Chifre1", { Color = corDetalhe, Material = Enum.Material.Neon }), parte(pasta, nome .. "Chifre2", { Color = corDetalhe, Material = Enum.Material.Neon }) },
		}
		return d
	end
	local fuujin = deus("Fuujin", rgb(120, 230, 215), rgb(240, 255, 255))
	local raijin = deus("Raijin", rgb(240, 110, 50), rgb(255, 220, 80))
	local tambores = {}
	for i = 1, 7 do tambores[i] = parte(pasta, "Tambor" .. i, { Shape = Enum.PartType.Cylinder, Color = rgb(255, 200, 70), Material = Enum.Material.Neon }) end
	local function posarDeus(d, base, transp, inclina, lado)
		local b = base * CFrame.Angles(-math.rad(22) * inclina, 0, 0)
		d.Tronco.Size = V3(7, 9, 4)
		d.Tronco.CFrame = b * CFrame.new(0, 9, 0)
		d.Cabeca.Size = V3(4.4, 4.6, 4.2)
		d.Cabeca.CFrame = b * CFrame.new(0, 16, -0.4)
		d.OlhoE.Size = V3(1, 0.35, 0.3)
		d.OlhoD.Size = V3(1, 0.35, 0.3)
		d.OlhoE.CFrame = b * CFrame.new(-1, 16.6, -2.6)
		d.OlhoD.CFrame = b * CFrame.new(1, 16.6, -2.6)
		for i, c in ipairs(d.Chifres) do
			c.Size = V3(0.8, 3, 0.8)
			c.CFrame = b * CFrame.new(i == 1 and -1.4 or 1.4, 19, -0.3) * CFrame.Angles(0, 0, math.rad(i == 1 and 22 or -22))
		end
		-- braços esticados pra frente (pra bola) no soco
		for i, br in ipairs({ d.BracoE, d.BracoD }) do
			local x = (i == 1 and -4.6 or 4.6)
			br.Size = V3(2.2, 2.2, 7 + 3 * inclina)
			br.CFrame = b * CFrame.new(x, 11, -2.5 - 1.5 * inclina) * CFrame.Angles(math.rad(-10 * (1 - inclina)), math.rad(lado * 8), 0)
		end
		for _, p in ipairs({ d.Tronco, d.Cabeca, d.BracoE, d.BracoD, d.Chifres[1], d.Chifres[2] }) do p.Transparency = transp end
		d.OlhoE.Transparency = math.min(1, transp * 0.6)
		d.OlhoD.Transparency = math.min(1, transp * 0.6)
		return b
	end
	return function(t, bola, pontoChoque, noChoque, alfa, D)
		local chao = ctx.ChaoY or -2.9
		local sobe = easeOut(phase(t, 0.15, 0.55))
		local inclina = smooth(phase(t, 0.6, 0.85))
		local transpDeus = 1 - alfa * 0.55 * sobe
		local baseF = ctx.Inicio * CFrame.new(-9.5, chao - 16 + 16 * sobe, 9) * CFrame.Angles(0, math.rad(-14), 0)
		local baseR = ctx.Inicio * CFrame.new(9.5, chao - 16 + 16 * sobe, 9) * CFrame.Angles(0, math.rad(14), 0)
		posarDeus(fuujin, baseF, transpDeus, inclina, 1)
		local bR = posarDeus(raijin, baseR, transpDeus, inclina, -1)
		-- arco de tambores atrás da cabeça do Raijin
		for i, tb in ipairs(tambores) do
			local ang = math.rad(-75 + (i - 1) * 25)
			tb.Size = V3(1, 2.2, 2.2)
			tb.CFrame = bR * CFrame.new(math.sin(ang) * 7.5, 16 + math.cos(ang) * 6, 2.5) * CFrame.Angles(0, math.rad(90), 0)
			tb.Transparency = transpDeus
		end
		local ativo = t >= 0.55 and alfa > 0.2
		local b = mundo(bola)
		-- relâmpagos do lado direito até a bola
		for i, r in ipairs(raios) do
			if ativo and math.random() < 0.7 then
				local ceu = mundo(V3(7 + i, 24 + math.random() * 6, bola.Z + 1))
				r.Desenhar(ceu, b + V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5), 9, 2.2, 0.2, math.random() * 0.2)
			else
				r.Apagar()
			end
		end
		-- tornado de vento do lado esquerdo, empurrando pra bola
		local esquerda = mundo(V3(-7, (ctx.ChaoY or -2.9) + 1, bola.Z + 1))
		ventoFx.CFrame = CFrame.lookAt(esquerda, b)
		vento.Enabled = ativo
		vento.Rate = 45
		if ativo and t - ultimoAnel > 0.12 then
			ultimoAnel = t
			local y = ((t * 7) % 1) * 9
			anelVazado(pasta, esquerda + Vector3.new(0, y, 0), Vector3.yAxis, rgb(150, 235, 210), 2.5, 7, 0.35, 0.2)
		end
	end
end

function E.Defesa(ctx)
	local pasta, spec, mundo = ctx.Pasta, ctx.Spec, ctx.Mundo
	local estilo = spec.EstiloDefesa or "MaoDivina"
	local cor, claro = DEFESA_CORES[estilo][1], DEFESA_CORES[estilo][2]
	local bolaIni = ctx.BolaInicial or V3(0, 0, -5)

	-- faíscas no ponto de choque (a bola raspando na técnica)
	local choque = parte(pasta, "Choque")
	local faiscasChoque = emissor(choque, {
		Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, cor } }), Tamanho = 0.45, Vida = { 0.2, 0.45 }, Vel = { 12, 26 },
		Drag = 4, RotVel = 400,
	})
	local luzChoque = luz(choque, cor, 0, 5)

	local mao, raios, parede, fogoMaos, aura
	-- ⚠️ v109: estilos novos com peças próprias (ver ESTILOS_NOVOS)
	local estiloNovo = ESTILOS_NOVOS[estilo] and ESTILOS_NOVOS[estilo](ctx, pasta, cor, claro, mundo)
	if estilo == "MaoDivina" or estilo == "MaoDemonio" or estilo == "PunhoGigante" or estilo == "PunhoJustica" then
		mao = maoGigante(pasta, cor, Enum.Material.Neon, estilo == "MaoDemonio" and 0.35 or 0.3)
		local brilho = emissor(mao.Palma, {
			Cor = cores({ { 0, claro }, { 1, cor } }), Tamanho = 0.7, Vida = { 0.4, 0.8 }, Vel = { 2, 6 },
			Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, Taxa = 0,
		})
		mao.Brilho = brilho
		mao.Luz = luz(mao.Palma, cor, 0, 5)
		-- ⚠️ v108 — GOD HAND pelo ANIME (vídeo "Shin God Hand", quadros a cada
		-- 0,5s): (1) a mão direita do goleiro ACENDE dourada antes (carga, 0-1s);
		-- (2) RELÂMPAGOS dourados/brancos em volta dele enquanto a técnica sobe
		-- (4-5.5s); (3) no choque, RAIOS DE LUZ saindo da palma em volta, como um
		-- sol (8.5-9.5s).
		-- ⚠️ v108: a Mão do Demônio usa o mesmo kit (anime: punho no peito
		-- acendendo, relâmpagos, explosão de aura dourada em volta do goleiro)
		if estilo == "MaoDivina" or estilo == "MaoDemonio" then
			local divina = { Raios = {}, Sol = {}, SolNoGoleiro = estilo == "MaoDemonio" }
			for i = 1, 5 do divina.Raios[i] = novoRaio(pasta, i % 2 == 0 and rgb(255, 255, 235) or rgb(255, 215, 90), 0.12) end
			for i = 1, 16 do divina.Sol[i] = parte(pasta, "RaioDeLuz" .. i, { Color = rgb(255, 240, 170) }) end
			local braco = ctx.Character:FindFirstChild("RightHand") or ctx.Character:FindFirstChild("Right Arm")
			if braco then
				divina.Braco = braco
				divina.Carga = esfera(pasta, "MaoCarregando", rgb(255, 230, 120))
				divina.CargaLuz = luz(divina.Carga, rgb(255, 220, 110), 0, 6)
			end
			mao.Divina = divina
		end
		-- ⚠️ v109 — GIGANT WALL: o goleiro GIGANTE (cópia dele 3x, energia azul
		-- translúcida) atrás, o braço de energia descendo até o punho, e no
		-- impacto o chão RACHA (linhas radiais), sobe poeira e voam pedras.
		if estilo == "PunhoGigante" then
			local gig = { Rachas = {} }
			gig.Braco = parte(pasta, "BracoGigante", { Color = cor, Material = Enum.Material.Neon })
			for i = 1, 10 do gig.Rachas[i] = parte(pasta, "Racha" .. i, { Color = rgb(70, 50, 35), Material = Enum.Material.Slate }) end
			local poeiraFx = parte(pasta, "PoeiraGigante")
			gig.PoeiraFx = poeiraFx
			gig.Poeira = emissor(poeiraFx, {
				Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(200, 180, 150) }, { 1, rgb(120, 100, 80) } }), Brilho = 0,
				Tamanho = numeros({ { 0, 3 }, { 1, 9 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }),
				Vida = { 0.7, 1.2 }, Vel = { 10, 20 }, Drag = 2, Spread = 80, Direcao = Enum.NormalId.Top,
			})
			-- a cópia gigante do goleiro
			local ok, copia = pcall(function()
				local antes = ctx.Character.Archivable
				ctx.Character.Archivable = true
				local c = ctx.Character:Clone()
				ctx.Character.Archivable = antes
				return c
			end)
			if ok and copia then
				for _, d in ipairs(copia:GetDescendants()) do
					if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("BillboardGui")
						or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Highlight") or d:IsA("Decal") then
						d:Destroy()
					elseif d:IsA("BasePart") then
						d.Anchored = true
						d.CanCollide = false
						d.CanQuery = false
						d.CanTouch = false
						d.CastShadow = false
						d.Material = Enum.Material.ForceField
						d.Color = cor
					elseif d:IsA("Humanoid") then
						d.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
					end
				end
				copia.Name = "GoleiroGigante"
				pcall(function() copia:ScaleTo(3) end)
				copia.Parent = pasta
				gig.Copia = copia
				gig.CopiaPartes = {}
				for _, d in ipairs(copia:GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then table.insert(gig.CopiaPartes, d) end
				end
			end
			mao.Gigante = gig
		end
		if estilo == "MaoDemonio" then
			raios = {}
			for i = 1, 4 do raios[i] = novoRaio(pasta, i % 2 == 0 and rgb(255, 250, 200) or rgb(255, 150, 30), 0.14) end
			-- ⚠️ v106: o DEMÔNIO da arte — gigante dourado subindo atrás do
			-- goleiro (tronco, cabeça, cabelo espetado laranja, olhos) com a
			-- aura amarela; o braço dele vai do ombro até a mão gigante.
			local dourado = rgb(255, 200, 70)
			local function pecaDemonio(nome, cor, material)
				return parte(pasta, nome, { Color = cor or dourado, Material = material or Enum.Material.Neon })
			end
			local corpo = {
				Tronco = pecaDemonio("DemonioTronco", rgb(230, 140, 40)),
				Peito = pecaDemonio("DemonioPeito", rgb(255, 170, 50)),
				Cabeca = pecaDemonio("DemonioCabeca", rgb(240, 160, 50)),
				Braco = pecaDemonio("DemonioBraco", rgb(240, 160, 50)),
				OlhoE = pecaDemonio("DemonioOlhoE", rgb(255, 255, 255)),
				OlhoD = pecaDemonio("DemonioOlhoD", rgb(255, 255, 255)),
				Cabelo = {},
			}
			for i = 1, 7 do
				corpo.Cabelo[i] = pecaDemonio("DemonioCabelo" .. i, i % 2 == 0 and rgb(235, 80, 25) or rgb(255, 120, 40))
			end
			local fumaca = emissor(corpo.Tronco, {
				Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(255, 235, 140) }, { 1, rgb(255, 150, 30) } }), Brilho = 0.6,
				Tamanho = numeros({ { 0, 4 }, { 1, 10 } }), Transp = numeros({ { 0, 0.45 }, { 1, 1 } }),
				Vida = { 0.8, 1.4 }, Vel = { 2, 6 }, Spread = 40, Acel = V3(0, 6, 0),
				Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, Taxa = 0,
			})
			local faiscas = emissor(corpo.Cabeca, {
				Textura = TEX.Faisca, Cor = cores({ { 0, rgb(255, 255, 220) }, { 1, rgb(255, 170, 40) } }), Brilho = 1,
				Tamanho = numeros({ { 0, 0.8 }, { 1, 0 } }), Vida = { 0.4, 0.8 }, Vel = { 6, 14 }, Spread = 180, Taxa = 0,
			})
			aura = { Corpo = corpo, Fumaca = fumaca, Faiscas = faiscas }
		end
	elseif estilo == "MuralhaMare" then
		parede = {}
		-- ⚠️ v108 (anime): parede MAIS LARGA (o gol inteiro) e mais alta, com
		-- estouro de espuma na base na hora da batida e riscos brancos subindo
		for i = 1, 13 do
			local p = parte(pasta, "Parede" .. i, { Material = Enum.Material.Glass, Color = cor })
			local espuma = emissor(p, {
				Textura = TEX.Fumaca, Cor = claro, Brilho = 0.3, Tamanho = numeros({ { 0, 2 }, { 1, 5 } }),
				Transp = numeros({ { 0, 0.3 }, { 1, 1 } }), Vida = { 0.5, 0.9 }, Vel = { 3, 6 }, Spread = 30,
				Acel = V3(0, -8, 0), Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Surface,
				Direcao = Enum.NormalId.Top, Taxa = 0,
			})
			parede[i] = { Parte = p, Espuma = espuma }
		end
		parede.Riscos = {}
		for i = 1, 12 do
			parede.Riscos[i] = { Parte = parte(pasta, "RiscoAgua" .. i, { Color = rgb(245, 252, 255) }), Fase = math.random(), Seg = math.random(1, 13) }
		end
	elseif estilo == "SocoExplosivo" or estilo == "SocoArdente" then
		fogoMaos = {}
		for _, nome in ipairs({ "RightHand", "LeftHand", "Right Arm", "Left Arm" }) do
			local m = ctx.Character:FindFirstChild(nome)
			if m then
				local a = Instance.new("Attachment")
				a.Parent = m
				local f = emissor(a, {
					Textura = TEX.Fogo, Cor = cores({ { 0, rgb(255, 225, 120) }, { 0.5, rgb(255, 120, 30) }, { 1, rgb(200, 40, 10) } }),
					Brilho = 0.8, Tamanho = numeros({ { 0, 1.6 }, { 1, 0 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }),
					Vida = { 0.25, 0.45 }, Vel = { 1, 3 }, Acel = V3(0, 6, 0), Taxa = 0,
				})
				table.insert(fogoMaos, { A = a, F = f })
			end
		end
	end

	local ultimoSoco = -1
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local D = spec.Duration
		-- ⚠️ v110 — MÃO DIVINA pelo vídeo a 0,1s ("God Hand", Tachimukai): a mão
		-- aparece BEM antes (3.9s de 14s de técnica) — surge já grande atrás dele
		local aparece = (estilo == "MaoDivina" or estilo == "PunhoJustica") and smooth(phase(t, 0.1, 0.35)) or smooth(phase(t, 0.25, 0.8))
		local some = smooth(phase(t, D - 0.35, D))
		local alfa = aparece * (1 - some)
		local bola = s.BolaLocal
		local noChoque = t >= spec.ImpactTime and t < D - 0.2

		-- ponto de choque: entre a bola e o goleiro
		local pontoChoque = mundo(bola + V3(0, 0, 1.1))
		choque.CFrame = CFrame.new(pontoChoque)
		faiscasChoque.Enabled = noChoque
		faiscasChoque.Rate = 70
		luzChoque.Range = noChoque and (12 + math.sin(t * 30) * 3) or 0
		if estiloNovo then estiloNovo(t, bola, pontoChoque, noChoque, alfa, D) end

		if mao then
			-- surge atrás do goleiro, pequena, e vem crescendo até a bola
			-- ⚠️ v107 — "aumenta o tamanho da God Hand, está pequena em relação
			-- ao original": escala final por estilo (era 1.2 pra todas). A palma
			-- sobe junto pra não enterrar no gramado; a bola bate na parte de baixo.
			local escalaFinal = ESCALA_MAO[estilo] or 1.2
			local destino = V3(bola.X, bola.Y + 0.6 + (escalaFinal - 1.2) * 1.6, bola.Z + 2.2)
			local origem = V3(0, 3, 3)
			local p = origem:Lerp(destino, easeOut(phase(t, 0.25, 0.8)))
			local escala = 0.3 + (escalaFinal - 0.3) * easeOut(phase(t, 0.25, 0.8)) + (noChoque and 0.03 * math.sin(t * 20) or 0)
			local fecha = (estilo == "PunhoGigante" or estilo == "PunhoJustica") and 1 or (0.25 * smooth(phase(t, 0.8, 1.4)))
			-- a palma olha PRA BOLA (-Z do goleiro): CFrame virado 180° em Y
			if estilo == "MaoDivina" then
				-- ⚠️ v110 — pelo vídeo (quadros a cada 0,1s): a mão gigante SOBE atrás
				-- e acima do goleiro, de pé, dedos abertos pra frente (3.9-6.4s),
				-- fica ali enquanto ele carrega o braço com relâmpagos (6.5-8.4s) e só
				-- então vai empurrada até a bola (8.5-10.6s). Antes ela saía pequena e
				-- ia direto pra bola.
				local alto = V3(0, 6.2 + (escalaFinal - 1.2) * 1.4, 3.4)
				local sobe = easeOut(phase(t, 0.1, 0.38))
				local vai = phase(t, 0.62, 0.8)
				p = V3(0, 1.5, 3.8):Lerp(alto, sobe):Lerp(destino, vai * vai)
				p += V3(0, math.sin(t * 9) * 0.12 * (1 - vai), 0) -- respira enquanto espera
				escala = 0.4 + (escalaFinal - 0.4) * sobe + (noChoque and 0.03 * math.sin(t * 20) or 0)
			end
			if estilo == "PunhoJustica" then
				-- ⚠️ v110 (vídeo, conferido na tela): o punho se FORMA pequeno na mão
				-- do goleiro, girando dentro da espiral (5.2-7.9s), e só então avança
				-- crescendo até a bola (10-12s). Antes já nascia enorme na frente dele.
				local braco = ctx.Character:FindFirstChild("RightHand") or ctx.Character:FindFirstChild("Right Arm")
				local maoMundo = braco and (braco.Name == "Right Arm" and (braco.CFrame * CFrame.new(0, -1.1, 0)).Position or braco.Position)
				local maoLocal = maoMundo and ctx.Inicio:PointToObjectSpace(maoMundo) or V3(1.5, 0.5, -1)
				local forma = smooth(phase(t, 0.2, 0.55))
				local vai = phase(t, 0.55, 0.8)
				p = maoLocal:Lerp(destino, vai * vai)
				escala = (0.15 + 0.35 * forma) + (escalaFinal - 0.5) * vai + (noChoque and 0.03 * math.sin(t * 20) or 0)
			end
			local cf = ctx.Inicio * CFrame.new(p) * CFrame.Angles(0, math.pi, 0)
			if estilo == "PunhoJustica" then
				-- ⚠️ v110 — pelo vídeo "Seigi no Tekken G5" (0,1s): o punho dourado
				-- avança GIRANDO como broca (6.0-11.9s) e diminui o giro no choque
				local giro = t < 0.8 and t * 16 or (0.8 * 16 + (t - 0.8) * 3)
				cf = cf * CFrame.Angles(0, 0, giro)
			end
			local gig = mao.Gigante
			if gig then
				-- o punho vem de CIMA e martela a bola contra o chão
				local u = phase(t, 0.4, 0.8)
				local alto = V3(0, 15, 2.5)
				local alvo = V3(bola.X, bola.Y + 1.3 * escalaFinal, bola.Z + 0.3)
				p = alto:Lerp(alvo, u * u)
				cf = ctx.Inicio * CFrame.new(p) * CFrame.Angles(math.rad(90), 0, 0)
				-- goleiro gigante atrás
				if gig.Copia then
					local chao = ctx.ChaoY or -2.9
					gig.Copia:PivotTo(ctx.Inicio * CFrame.new(0, -2 * chao, 8))
					local a = smooth(phase(t, 0.1, 0.4)) * (1 - smooth(phase(t, spec.Duration - 0.4, spec.Duration)))
					for _, d in ipairs(gig.CopiaPartes) do d.Transparency = 1 - a * 0.55 end
				end
				-- braço de energia: do ombro do gigante até o punho
				local ombro = mundo(V3(2.5, 13, 7))
				local punho = mundo(p)
				local comp = (punho - ombro).Magnitude
				gig.Braco.Size = V3(2.4, 2.4, math.max(comp, 0.5))
				gig.Braco.CFrame = CFrame.lookAt((ombro + punho) / 2, punho)
				gig.Braco.Transparency = 1 - alfa * 0.5
				-- impacto: racha o chão, poeira e pedras
				if not gig.Bateu and t >= 0.8 then
					gig.Bateu = true
					local centro = mundo(V3(bola.X, (ctx.ChaoY or -2.9) + 0.05, bola.Z))
					for i, r in ipairs(gig.Rachas) do
						local ang = (i / #gig.Rachas) * math.pi * 2 + math.random() * 0.4
						local len = 5 + math.random() * 6
						local dir = ctx.Inicio:VectorToWorldSpace(V3(math.cos(ang), 0, math.sin(ang)))
						r.Size = V3(0.35, 0.12, len)
						r.CFrame = CFrame.lookAt(centro + dir * len / 2, centro + dir * len)
						r.Transparency = 0
					end
					gig.PoeiraFx.CFrame = CFrame.new(centro)
					gig.Poeira:Emit(45)
					for _ = 1, 10 do
						local pedra = parte(pasta, "Pedra", { Color = rgb(110, 95, 80), Material = Enum.Material.Slate, Transparency = 0 })
						local sz = 0.4 + math.random() * 0.8
						pedra.Size = V3(sz, sz, sz)
						pedra.CFrame = CFrame.new(centro + V3(0, 0.5, 0))
						local destino = centro + V3(math.random() * 12 - 6, 2 + math.random() * 5, math.random() * 12 - 6)
						TweenService:Create(pedra, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
							CFrame = CFrame.new(destino) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1,
						}):Play()
						game:GetService("Debris"):AddItem(pedra, 0.6)
					end
					ctx.Tremer(0.6, 0.35)
				end
				if gig.Bateu then
					local some = smooth(phase(t, spec.Duration - 0.35, spec.Duration))
					for _, r in ipairs(gig.Rachas) do r.Transparency = some end
				else
					for _, r in ipairs(gig.Rachas) do r.Transparency = 1 end
				end
			end
			mao.Posar(cf, escala, fecha, alfa)
			mao.Brilho.Enabled = alfa > 0.3
			mao.Brilho.Rate = 40
			mao.Luz.Range = 20 * alfa
			local divina = mao.Divina
			-- ⚠️ v110 — MÃO DIVINA (vídeo 14.0-15.1s): no fim, clarão branco e
			-- uma onda de choque em ANEL em volta do goleiro, já com a bola
			if divina and estilo == "MaoDivina" and not divina.Final and t >= D - 0.45 then
				divina.Final = true
				ctx.Flash(rgb(255, 252, 235), 0.1, 0.3)
				local chao = mundo(V3(0, (ctx.ChaoY or -2.9) + 0.2, 0))
				anelVazado(pasta, chao, Vector3.yAxis, rgb(255, 225, 120), 3, 26, 0.55, 0.35)
				anelVazado(pasta, chao + V3(0, 1.5, 0), Vector3.yAxis, rgb(255, 250, 220), 2, 18, 0.45, 0.25)
			end
			if divina then
				-- (1) carga na mão do goleiro
				if divina.Braco and divina.Carga then
					local ponta = divina.Braco.Name == "Right Arm" and divina.Braco.CFrame * CFrame.new(0, -1.1, 0) or divina.Braco.CFrame
					local k = smooth(phase(t, 0, 0.6)) * (1 - smooth(phase(t, 0.75, 1.0)))
					divina.Carga.CFrame = ponta
					divina.Carga.Size = Vector3.one * (0.4 + 1.8 * k + 0.15 * math.sin(t * 30))
					divina.Carga.Transparency = k > 0.02 and (0.15 + 0.2 * (1 - k)) or 1
					divina.CargaLuz.Range = 14 * k
				end
				-- (2) relâmpagos em volta do goleiro
				local corpo = ctx.Root.Position
				for _, r in ipairs(divina.Raios) do
					if t >= 0.15 and t < 1.3 and math.random() < 0.55 then
						local a = corpo + V3(math.random() * 6 - 3, math.random() * 7 - 2.5, math.random() * 4 - 2)
						local b = a + V3(math.random() * 4 - 2, math.random() * 5 - 2.5, math.random() * 4 - 2)
						r.Desenhar(a, b, 6, 0.9, 0.12, math.random() * 0.3)
					else
						r.Apagar()
					end
				end
				-- (3) raios de luz radiais atrás da palma no choque (God Hand) /
				-- explosão de aura em volta do goleiro no começo (Majin, 2.5-5s)
				local palma = mao.Palma.CFrame
				local ligaSol = noChoque
				if divina.SolNoGoleiro then
					palma = ctx.Inicio * CFrame.new(0, 0.5, 0.8) * CFrame.Angles(0, math.pi, 0)
					ligaSol = t >= 0.12 and t < 0.85
				end
				local giro = t * 0.6
				for i, p in ipairs(divina.Sol) do
					if ligaSol then
						local ang = giro + (i / #divina.Sol) * math.pi * 2
						local dir = palma.RightVector * math.cos(ang) + palma.UpVector * math.sin(ang)
						local comp = (9 + (i % 3) * 3 + math.sin(t * 17 + i) * 2) * (escalaFinal / 2)
						local base = palma.Position + palma.LookVector * 0.9 + dir * (3.2 * escalaFinal / 2)
						p.Size = V3(0.18, 0.18, comp)
						p.CFrame = CFrame.lookAt(base + dir * comp / 2, base + dir * comp)
						p.Transparency = 0.35 + 0.35 * math.random()
					else
						p.Transparency = 1
					end
				end
			end
			if raios then
				for _, r in ipairs(raios) do
					if alfa > 0.3 and math.random() < 0.6 then
						local d = V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
						if d.Magnitude < 0.05 then d = Vector3.xAxis end
						r.Desenhar(mao.Palma.Position, mao.Palma.Position + d.Unit * (4 + math.random() * 4), 6, 1, 0.14, 0.1)
					else
						r.Apagar()
					end
				end
			end
			if aura then
				aura.Fumaca.Enabled = alfa > 0.2
				aura.Fumaca.Rate = 30
				aura.Faiscas.Enabled = alfa > 0.4
				aura.Faiscas.Rate = 18
				-- o demônio sobe do chão atrás do goleiro e respira
				local c = aura.Corpo
				local sobe = easeOut(phase(t, 0.05, 0.75))
				local resp = math.sin(t * 3) * 0.25
				-- ⚠️ v108 (anime 12.5-15.5s): no empurrão o demônio INCLINA pra
				-- frente por cima do goleiro, junto com a mão
				local inclina = smooth(phase(t, 0.62, 0.95))
				local base = ctx.Inicio * CFrame.new(0, -14 + 14 * sobe, 9) * CFrame.Angles(-math.rad(16) * inclina, 0, 0)
				-- ⚠️ v110 (vídeo a 0,1s, 16-23.8s): o demônio é TRANSLÚCIDO atrás do
				-- goleiro e a mão brilha na frente — antes corpo e mão eram o mesmo
				-- amarelo opaco e a mão sumia contra o tronco
				local transp = 1 - alfa * 0.42
				c.Tronco.Size = V3(13, 11 + resp, 5.5)
				c.Tronco.CFrame = base * CFrame.new(0, 12, 0)
				c.Peito.Size = V3(10, 4, 1)
				c.Peito.CFrame = base * CFrame.new(0, 14.5, -2.9)
				c.Cabeca.Size = V3(6, 6.5, 6)
				c.Cabeca.CFrame = base * CFrame.new(0, 21.2 + resp, -0.5)
				c.OlhoE.Size = V3(1.3, 0.45, 0.3)
				c.OlhoD.Size = V3(1.3, 0.45, 0.3)
				c.OlhoE.CFrame = base * CFrame.new(-1.4, 22 + resp, -3.6)
				c.OlhoD.CFrame = base * CFrame.new(1.4, 22 + resp, -3.6)
				for i, fio in ipairs(c.Cabelo) do
					local ang = (i - 4) * 0.42
					fio.Size = V3(1.3, 4.5 + (i % 3), 1.3)
					fio.CFrame = base * CFrame.new(math.sin(ang) * 2.8, 25.2 + resp, -0.3 + math.cos(ang) * 0.6)
						* CFrame.Angles(0, 0, -ang * 1.1) * CFrame.new(0, 1.6, 0)
				end
				-- braço: do ombro direito do demônio até a palma da mão gigante
				local ombro = (base * CFrame.new(6.5, 15, 0)).Position
				local palma = mao.Palma.Position
				local meio = (ombro + palma) / 2
				local comp = (palma - ombro).Magnitude
				c.Braco.Size = V3(3.2, 3.2, math.max(comp - 2, 0.5))
				c.Braco.CFrame = CFrame.lookAt(meio, palma)
				for _, p in ipairs({ c.Tronco, c.Peito, c.Cabeca, c.Braco }) do p.Transparency = transp end
				for _, fio in ipairs(c.Cabelo) do fio.Transparency = 1 - alfa * 0.8 end
				c.OlhoE.Transparency = 1 - alfa
				c.OlhoD.Transparency = 1 - alfa
			end
		end

		if parede then
			-- parede em arco na frente do goleiro, subindo do gramado
			-- sobe DEPOIS que as mãos batem no chão (pose: 0.45 braços em cima,
			-- 0.8 batida)
			local altura = 14 * easeOut(phase(t, 0.55, 0.85)) * (1 - some)
			local zParede = bola.Z + 1.8
			if not parede.Estourou and t >= 0.55 then
				parede.Estourou = true
				for _, seg in ipairs(parede) do seg.Espuma:Emit(14) end
				ctx.Tremer(0.35, 0.25)
			end
			for i, seg in ipairs(parede) do
				local ang = (i - 7) * 0.12
				local x = math.sin(ang) * 14
				local z = zParede + (1 - math.cos(ang)) * 8
				local h = math.max(altura, 0.1)
				seg.Parte.Size = V3(2.6, h, 1.2)
				seg.Parte.CFrame = ctx.Inicio * CFrame.new(x, ctx.ChaoY + h / 2, z) * CFrame.Angles(0, -ang, 0)
				seg.Parte.Transparency = 1 - alfa * 0.6
				seg.Espuma.Enabled = alfa > 0.3
				seg.Espuma.Rate = 20
			end
			-- riscos brancos subindo pela água (anime 17.5s)
			for _, r in ipairs(parede.Riscos) do
				local seg = parede[r.Seg]
				if altura > 1 and seg then
					local u = (t * 0.9 + r.Fase) % 1
					local comp = 1.2 + 1.8 * r.Fase
					r.Parte.Size = V3(0.12, comp, 0.12)
					r.Parte.CFrame = seg.Parte.CFrame * CFrame.new((r.Fase - 0.5) * 2, -altura / 2 + u * altura, -0.65)
					r.Parte.Transparency = 0.2 + 0.6 * u
				else
					r.Parte.Transparency = 1
				end
			end
		end

		if fogoMaos then
			for _, f in ipairs(fogoMaos) do
				f.F.Enabled = t >= 0.2 and t < D - 0.2
				f.F.Rate = 90
			end
			-- uma explosão na bola a cada soco
			-- ⚠️ v106: uma explosão no instante em que o braço estica (mesmo
			-- ritmo do soco da pose, ver Defesa_SocoExplosivo)
			local fase = (t - 0.8) * 6.5
			local soco = math.floor(fase)
			-- ⚠️ v109: Soco Ardente é UM soco só, explosivo, no instante do contato
			if estilo == "SocoArdente" then
				if noChoque and ultimoSoco < 0 then
					ultimoSoco = 1
					faiscasChoque:Emit(60)
					local boom = parte(pasta, "Explosao", { Shape = Enum.PartType.Ball, Color = rgb(255, 200, 90), Transparency = 0.05 })
					boom.Size = V3(2, 2, 2)
					boom.CFrame = CFrame.new(pontoChoque)
					TweenService:Create(boom, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(9, 9, 9), Transparency = 1 }):Play()
					game:GetService("Debris"):AddItem(boom, 0.4)
					onda(pasta, pontoChoque, ctx.Inicio.LookVector, rgb(255, 150, 40), 14, 0.3, 0.3)
					ctx.Tremer(0.5, 0.3)
				end
				soco = ultimoSoco -- (não entra no ritmo de socos abaixo)
			end
			if estilo ~= "SocoArdente" and noChoque and fase - soco >= 0.45 and soco ~= ultimoSoco then
				ultimoSoco = soco
				faiscasChoque:Emit(25)
				onda(pasta, pontoChoque, ctx.Inicio.LookVector, rgb(255, 170, 50), 7, 0.18, 0.2)
				-- ⚠️ v108 — anime (11.5-13.5s): socos rapidíssimos com vários
				-- PUNHOS-FANTASMA borrados e uma explosão branca/amarela em cada
				for _ = 1, 3 do
					local off = ctx.Inicio:VectorToWorldSpace(V3(math.random() * 2.6 - 1.3, math.random() * 2 - 0.6, 0.6 + math.random() * 0.8))
					local fantasma = parte(pasta, "PunhoFantasma", { Shape = Enum.PartType.Ball, Color = rgb(255, 205, 110), Transparency = 0.35 })
					fantasma.Size = V3(1.1, 1.1, 1.1)
					fantasma.CFrame = CFrame.new(pontoChoque + off)
					TweenService:Create(fantasma, TweenInfo.new(0.16), { Transparency = 1, Size = V3(0.6, 0.6, 0.6) }):Play()
					game:GetService("Debris"):AddItem(fantasma, 0.2)
				end
				local boom = parte(pasta, "Explosao", { Shape = Enum.PartType.Ball, Color = rgb(255, 245, 200), Transparency = 0.1 })
				boom.Size = V3(1.5, 1.5, 1.5)
				boom.CFrame = CFrame.new(pontoChoque)
				TweenService:Create(boom, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(4.5, 4.5, 4.5), Transparency = 1 }):Play()
				game:GetService("Debris"):AddItem(boom, 0.22)
			end
		end
	end
	function efeitos.Impacto(s)
		local p = mundo(s.BolaLocal + V3(0, 0, 1.1))
		faiscasChoque:Emit(60)
		onda(pasta, p, ctx.Inicio.LookVector, cor, 18, 0.3, 0.3)
		onda(pasta, p, ctx.Inicio.LookVector, claro, 11, 0.22, 0.25)
	end
	-- (sem Voo: a defesa não manda a bola a lugar nenhum — quem decide é o duelo)
	return efeitos
end

-- ============================================================
-- ⚠️ v103 — VFX LEVE DO PREPARO (antes da cutscene). PEDIDO: "aparece um
-- foguinho em volta dele, bem de leve, umas faíscas, só pra você entender
-- que ele tá começando a querer chutar... Fúria Glacial, de gelo, de todas".
-- Tudo preso no corpo (acompanha se ele mexer) e some sozinho no fim.
-- ============================================================
local PREPARO_CORES = {
	FireTornado = { rgb(255, 215, 110), rgb(255, 120, 30), TEX.Fogo },
	Fogo = { rgb(255, 215, 110), rgb(255, 120, 30), TEX.Fogo },
	RaioUm = { rgb(255, 255, 220), rgb(255, 210, 50), TEX.Faisca },
	Luz = { rgb(255, 255, 220), rgb(255, 210, 50), TEX.Faisca },
	Sumico = { rgb(240, 200, 255), rgb(150, 60, 255), TEX.Fumaca },
	Void = { rgb(240, 200, 255), rgb(150, 60, 255), TEX.Fumaca },
	ZonaMorta = { rgb(210, 150, 255), rgb(60, 0, 100), TEX.Fumaca },
	ImpulsoDeMare = { rgb(240, 250, 255), rgb(90, 190, 255), TEX.Fumaca },
	FuriaGlacial = { rgb(250, 254, 255), rgb(140, 215, 255), TEX.Fumaca },
	Galaxia = { rgb(220, 255, 220), rgb(80, 255, 140), TEX.Faisca },
	Natureza = { rgb(230, 255, 220), rgb(110, 210, 110), TEX.Faisca },
	Vento = { rgb(230, 255, 250), rgb(90, 220, 200), TEX.Fumaca },
}

function E.Preparo(estilo, character, duracao)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local paleta = PREPARO_CORES[estilo] or PREPARO_CORES.Fogo
	local claro, forte, textura = paleta[1], paleta[2], paleta[3]
	local coisas = {}

	-- aura nos pés: chama/névoa baixa (bem de leve)
	local pes = Instance.new("Attachment")
	pes.Name = "HissatsuPreparoPes"
	pes.Position = Vector3.new(0, -2.6, 0)
	pes.Parent = root
	table.insert(coisas, pes)
	local ehFogo = textura == TEX.Fogo
	local chao = emissor(pes, {
		Textura = textura, Cor = cores({ { 0, claro }, { 1, forte } }), Brilho = ehFogo and 0.8 or 0.5,
		Tamanho = numeros({ { 0, ehFogo and 1.4 or 1.8 }, { 0.6, ehFogo and 1.0 or 2.6 }, { 1, 0 } }),
		Transp = numeros({ { 0, 0.35 }, { 0.7, 0.6 }, { 1, 1 } }),
		Vida = { 0.4, 0.8 }, Vel = { 2, 4 }, Spread = 75, Acel = V3(0, ehFogo and 6 or 2, 0), Drag = 2, Taxa = 24,
	})
	chao.EmissionDirection = Enum.NormalId.Top
	-- faíscas/brasas subindo em volta do corpo
	local corpo = Instance.new("Attachment")
	corpo.Name = "HissatsuPreparoCorpo"
	corpo.Parent = root
	table.insert(coisas, corpo)
	emissor(corpo, {
		Cor = cores({ { 0, claro }, { 1, forte } }), Tamanho = 0.28, Vida = { 0.5, 1.0 }, Vel = { 1, 3 },
		Acel = V3(0, estilo == "FuriaGlacial" and -1 or 4, 0), Drag = 1.5, RotVel = 300, Taxa = 14,
	})
	-- luz fraca da cor da técnica
	local l = Instance.new("PointLight")
	l.Color = forte
	l.Range = 9
	l.Brightness = 1.4
	l.Shadows = false
	l.Parent = corpo
	table.insert(coisas, l)

	task.delay(math.max(duracao or 2, 0.2) + 0.1, function()
		for _, x in ipairs(coisas) do
			if x.Parent then x:Destroy() end
		end
	end)
end

-- posição dos olhos no espaço da cabeça (R6 e R15)
local function FlowCenaOlhos(head)
	local s = head.Size
	return { V3(-s.X * 0.1, s.Y * 0.08, -s.Z * 0.5 - 0.04), V3(s.X * 0.1, s.Y * 0.08, -s.Z * 0.5 - 0.04) }
end

-- ============================================================
-- 🧩 FLOW DO ISAGI (⚠️ v113) — ver a coreografia Flow_Isagi
-- ============================================================
-- Palco escuro (salaEscura); P&B no começo (correção de cor só nesta cena);
-- peças de quebra-cabeça girando; buracos de peça no rosto; olho verde com
-- rastro; ele se desfaz em partículas; explosão verde que "devora" as sombras
-- do Rin e do Shidou (partículas sugadas pra ele); aura de chama verde e olhos
-- azuis no voleio final; riscos verdes passando.
function E.FlowIsagi(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local VERDE, VERDE_CLARO, AZUL = rgb(90, 255, 110), rgb(200, 255, 190), rgb(90, 190, 255)
	local character = ctx.Character
	local head = character:FindFirstChild("Head")
	local torso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	local ph = spec.Phases

	-- palco escuro rente ao gramado
	local sala = salaEscura(pasta, "SalaFlowIsagi", rgb(14, 16, 20), ctx.Inicio * CFrame.new(0, 20, -8), 130, ctx.ChaoY + 0.1 - 20)
	sala.Transparency = 0

	-- preto e branco no começo (a correção de cor da cena fica na câmera e
	-- some junto com a pasta)
	local pb = Instance.new("ColorCorrectionEffect")
	pb.Name = "FlowIsagiPB"
	pb.Saturation = -1
	pb.Contrast = 0.35
	pb.Parent = workspace.CurrentCamera
	pasta.Destroying:Connect(function() pb:Destroy() end)

	-- peças de quebra-cabeça: placa + 2 "encaixes" (cilindros)
	local pecas = {}
	local rng = Random.new(12)
	for i = 1, 26 do
		local cor = rgb(235, 235, 235):Lerp(rgb(120, 120, 120), rng:NextNumber())
		local placa = parte(pasta, "Peca" .. i, { Color = cor, Material = Enum.Material.SmoothPlastic })
		placa.Size = V3(1.3, 1.3, 0.16)
		local b1 = parte(pasta, "PecaB" .. i, { Shape = Enum.PartType.Cylinder, Color = cor, Material = Enum.Material.SmoothPlastic })
		b1.Size = V3(0.16, 0.5, 0.5)
		local b2 = parte(pasta, "PecaC" .. i, { Shape = Enum.PartType.Cylinder, Color = cor, Material = Enum.Material.SmoothPlastic })
		b2.Size = V3(0.16, 0.5, 0.5)
		pecas[i] = {
			Placa = placa, B1 = b1, B2 = b2,
			Raio = rng:NextNumber(2.6, 7), Altura = rng:NextNumber(-2.4, 4.5),
			Ang = rng:NextNumber(0, math.pi * 2), Vel = rng:NextNumber(1.2, 2.4) * (i % 2 == 0 and 1 or -1),
			Giro = V3(rng:NextNumber(-3, 3), rng:NextNumber(-3, 3), rng:NextNumber(-3, 3)),
		}
	end

	-- buracos de peça na bochecha (aparecem um por um) e o olho verde
	local buracos = {}
	local POS_BURACO = { V3(0.34, -0.12), V3(0.2, -0.3), V3(0.46, -0.3), V3(0.3, 0.14) }
	for i = 1, #POS_BURACO do
		buracos[i] = parte(pasta, "Buraco" .. i, { Color = rgb(5, 5, 5), Material = Enum.Material.SmoothPlastic })
	end
	local olhoD = esfera(pasta, "OlhoVerde", VERDE)
	local olhoE = esfera(pasta, "OlhoAzulE", AZUL)
	local olhoLuz = luz(olhoD, VERDE, 0, 6)
	local rastroOlho = parte(pasta, "RastroOlho", { Color = VERDE })
	local rastroMiolo = parte(pasta, "RastroOlhoMiolo", { Color = VERDE_CLARO })

	-- se desfaz em partículas (corrida)
	local desfaz = torso and emissor(torso, {
		Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(170, 190, 180) } }), Tamanho = numeros({ { 0, 0.35 }, { 1, 0 } }),
		Vida = { 0.4, 0.8 }, Vel = { 2, 6 }, Acel = ctx.Inicio:VectorToWorldSpace(V3(0, 1, 14)), Drag = 1, RotVel = 300,
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
	})

	-- riscos (linhas de velocidade) passando: peças finas recicladas
	local riscos = {}
	for i = 1, 22 do
		riscos[i] = { Parte = parte(pasta, "Risco" .. i, { Color = i % 3 == 0 and VERDE or rgb(230, 240, 235) }),
			Semente = rng:NextNumber(0, 100), X = rng:NextNumber(-9, 9), Y = rng:NextNumber(-3, 9) }
	end

	-- a explosão verde e as partículas sugadas
	local bolaVerde = esfera(pasta, "ExplosaoVerde", VERDE)
	local sugadas = {}
	for i = 1, 36 do sugadas[i] = esfera(pasta, "Sugada" .. i, i % 2 == 0 and VERDE or VERDE_CLARO) end
	local explodiu = false

	-- aura de chama verde (cabeça e braços) no final
	local chamas = {}
	local function chama(pai, tam)
		if not pai then return end
		table.insert(chamas, emissor(pai, {
			Textura = TEX.Fogo, Cor = cores({ { 0, VERDE_CLARO }, { 0.4, VERDE }, { 1, rgb(20, 120, 40) } }), Brilho = 1,
			Tamanho = numeros({ { 0, tam }, { 1, 0.2 } }), Transp = numeros({ { 0, 0.15 }, { 1, 1 } }),
			Vida = { 0.35, 0.6 }, Vel = { 3, 7 }, Spread = 25, Direcao = Enum.NormalId.Top,
			Acel = ctx.Inicio:VectorToWorldSpace(V3(0, 4, 10)),
		}))
	end
	chama(head, 2.2)
	chama(character:FindFirstChild("Right Arm") or character:FindFirstChild("RightUpperArm"), 1.3)
	chama(character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftUpperArm"), 1.3)

	-- o Shidou (sombra 2) é ROSA; o Rin (1) fica verde-água
	local SHIDOU = rgb(255, 110, 190)
	local sombraShidou = ctx.Clones and ctx.Clones[2]
	if sombraShidou and sombraShidou.Modelo and not sombraShidou.Real then
		for _, d in ipairs(sombraShidou.Modelo:GetDescendants()) do
			if d:IsA("BasePart") then d.Color = SHIDOU:Lerp(Color3.new(0, 0, 0), 0.6)
			elseif d:IsA("Highlight") then d.FillColor = SHIDOU; d.OutlineColor = SHIDOU:Lerp(Color3.new(1, 1, 1), 0.55) end
		end
	end
	-- contorno dele no palco escuro (no anime: traço branco no fundo preto)
	local contorno = Instance.new("Highlight")
	contorno.FillTransparency = 1
	contorno.OutlineColor = Color3.new(1, 1, 1)
	contorno.OutlineTransparency = 1
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Adornee = character
	contorno.Parent = pasta
	-- luz de preenchimento no rosto (close)
	local luzRosto = parte(pasta, "LuzRosto")
	local luzRostoL = luz(luzRosto, rgb(230, 240, 255), 0, 1.6)

	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local root = ctx.Root
		contorno.OutlineTransparency = (t >= 4.6) and 0 or 1
		contorno.OutlineColor = t >= ph.Flow[1] and VERDE_CLARO or Color3.new(1, 1, 1)
		if head then
			luzRosto.CFrame = head.CFrame * CFrame.new(0, -0.3, -2.5)
			luzRostoL.Range = (t >= 1.6 and t < 5.0) and 7 or 0
		end
		-- P&B até o olho acender; depois volta a cor (escuro)
		local cor = smooth(phase(t, 3.2, 4.4))
		pb.Saturation = -1 + cor
		pb.Contrast = 0.35 - 0.15 * cor

		-- peças girando em volta (só no começo; voltam num flash no fim da corrida)
		local vis = 1 - smooth(phase(t, 1.3, 1.7))
		for _, p in ipairs(pecas) do
			local a = p.Ang + t * p.Vel
			local centro = root.Position + V3(math.cos(a) * p.Raio, p.Altura + math.sin(t * 2 + p.Ang) * 0.3, math.sin(a) * p.Raio)
			local cf = CFrame.new(centro) * CFrame.Angles(p.Giro.X * t, p.Giro.Y * t, p.Giro.Z * t)
			p.Placa.CFrame = cf
			p.B1.CFrame = cf * CFrame.new(0, 0.78, 0) * CFrame.Angles(0, math.rad(90), 0)
			p.B2.CFrame = cf * CFrame.new(0.78, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
			local tr = vis > 0.02 and (1 - vis) or 1
			p.Placa.Transparency, p.B1.Transparency, p.B2.Transparency = tr, tr, tr
		end

		-- buracos de peça no rosto
		if head then
			local frente = -head.Size.Z / 2 - 0.02
			for i, b in ipairs(buracos) do
				local quando = 2.1 + (i - 1) * 0.45
				local k = smooth(phase(t, quando, quando + 0.25)) * (1 - smooth(phase(t, 4.6, 5.0)))
				local tam = 0.2 * k
				b.Size = V3(math.max(tam, 0.01), math.max(tam, 0.01), 0.04)
				local o = POS_BURACO[i]
				b.CFrame = head.CFrame * CFrame.new(o.X * head.Size.X * 0.5, o.Y * head.Size.Y, frente)
				b.Transparency = k > 0.02 and 0 or 1
			end
			-- olho verde (direito) desde 3.0; os dois azuis no Flow final
			local olhos = FlowCenaOlhos(head)
			local verde = smooth(phase(t, 3.0, 3.3))
			olhoD.Size = Vector3.one * 0.3
			olhoD.CFrame = head.CFrame * CFrame.new(olhos[2])
			olhoD.Color = t < 9.4 and VERDE or AZUL
			olhoD.Transparency = verde > 0.02 and 0 or 1
			olhoLuz.Range = 8 * verde
			olhoLuz.Color = olhoD.Color
			local azul = smooth(phase(t, 9.4, 9.7))
			olhoE.Size = Vector3.one * 0.3
			olhoE.CFrame = head.CFrame * CFrame.new(olhos[1])
			olhoE.Transparency = azul > 0.02 and 0 or 1
			-- rastro do olho (4.2-5.4): uma faixa saindo pra trás e pro lado
			local r = smooth(phase(t, 4.2, 4.6)) * (1 - smooth(phase(t, 5.2, 5.6)))
			if r > 0.02 then
				local de = olhoD.Position
				local dir = (head.CFrame.RightVector * 0.8 + head.CFrame.LookVector * -1).Unit
				local comp = 7 * r
				rastroOlho.Size = V3(0.32, 0.32, comp)
				rastroOlho.CFrame = CFrame.lookAt(de + dir * comp / 2, de + dir * comp)
				rastroOlho.Transparency = 0.25
				rastroMiolo.Size = V3(0.12, 0.12, comp * 0.95)
				rastroMiolo.CFrame = rastroOlho.CFrame
				rastroMiolo.Transparency = 0
			else
				rastroOlho.Transparency, rastroMiolo.Transparency = 1, 1
			end
		end

		-- se desfaz correndo
		if desfaz then
			desfaz.Enabled = t >= 4.6 and t < 6.4
			desfaz.Rate = 160
		end

		-- riscos passando (corrida e Flow final)
		local correndo = (t >= 5.0 and t < 6.4) or t >= 9.4
		for _, rk in ipairs(riscos) do
			if correndo then
				local ciclo = ((t * 2.2 + rk.Semente) % 1)
				local z = 12 - ciclo * 34
				-- no Flow final a câmera olha de baixo pra cima: os riscos vão pro
				-- fundo, ACIMA dele (perto da câmera viravam barras grossas)
				local y = t >= 9.4 and (4 + math.abs(rk.Y) * 1.3) or (rk.Y - 3)
				local x = t >= 9.4 and rk.X * 1.4 or rk.X
				local p = s.RootLocal + V3(x, y, z)
				rk.Parte.Size = V3(0.05, 0.05, 4)
				rk.Parte.CFrame = CFrame.lookAt(ctx.Mundo(p), ctx.Mundo(p + V3(0, 0, -1)))
				rk.Parte.Transparency = 0.25
			else
				rk.Parte.Transparency = 1
			end
		end

		-- DEVORA: explosão verde + partículas dos dois sugadas pra ele
		if not explodiu and t >= ph.Devora[1] then
			explodiu = true
			ctx.Flash(VERDE, 0.35, 0.35)
			ctx.Tremer(0.8, 0.4)
			onda(pasta, root.Position, ctx.Inicio.LookVector, VERDE, 30, 0.45, 0.4)
			anelVazado(pasta, root.Position, Vector3.yAxis, VERDE_CLARO, 2, 26, 0.5, 0.3)
		end
		local ex = phase(t, ph.Devora[1], ph.Devora[1] + 0.7)
		if ex > 0 and ex < 1 then
			bolaVerde.Size = Vector3.one * (2 + 11 * easeOut(ex))
			bolaVerde.CFrame = CFrame.new(root.Position)
			bolaVerde.Transparency = 0.6 + 0.4 * ex
		else
			bolaVerde.Transparency = 1
		end
		for i, sp in ipairs(sugadas) do
			local qual = ctx.Clones[(i % 2) + 1]
			local k = phase(t, ph.Devora[1] + (i % 9) * 0.04, ph.Devora[1] + 0.55 + (i % 9) * 0.04)
			if qual and qual.Root and k > 0 and k < 1 then
				local de = qual.Root.Position + V3(math.sin(i) * 1.2, math.cos(i * 1.7) * 1.8, math.sin(i * 2.3) * 1.2)
				sp.Size = Vector3.one * (0.5 * (1 - k) + 0.12)
				sp.CFrame = CFrame.new(de:Lerp(root.Position, k * k))
				sp.Transparency = 0
			else
				sp.Transparency = 1
			end
		end

		-- aura de chama verde no Flow
		for _, c in ipairs(chamas) do
			c.Enabled = t >= ph.Flow[1]
			c.Rate = 90
		end
	end
	function efeitos.Impacto(_s)
		ctx.Flash(rgb(230, 255, 230), 0.1, 0.5)
		onda(pasta, ctx.Root.Position, ctx.Inicio.LookVector, VERDE, 24, 0.35, 0.35)
	end
	return efeitos
end


-- ============================================================
-- 👾 FLOW DO BACHIRA (⚠️ v113) — ver a coreografia Flow_Bachira
-- ============================================================
-- O MONSTRO montado de peças: pernas, tronco, cabeça redonda com chifres,
-- olhos amarelos, sorriso de dentes, braços compridos com garras. Preto com
-- contorno amarelo. O braço direito dele sai do ombro e termina na mão
-- esquerda do Bachira (mãos dadas de verdade, em qualquer avatar).
function E.FlowBachira(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local AMARELO, PRETO, CLARO = rgb(255, 215, 70), rgb(14, 11, 9), rgb(250, 245, 230)
	local character = ctx.Character
	local head = character:FindFirstChild("Head")
	local maoBachira = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	local chao = ctx.ChaoY

	-- o vazio: claro e enevoado, escurece no drible
	local sala = salaEscura(pasta, "SalaFlowBachira", CLARO, ctx.Inicio * CFrame.new(0, 20, -5), 130, chao + 0.1 - 20)
	sala.Transparency = 0
	local brilho = parte(pasta, "BrilhoVazio")
	brilho.Size = V3(40, 14, 40)
	brilho.CFrame = ctx.Inicio * CFrame.new(0, 4, -5)
	local faiscas = emissor(brilho, {
		Cor = cores({ { 0, rgb(255, 250, 200) }, { 1, AMARELO } }), Tamanho = numeros({ { 0, 0.25 }, { 1, 0 } }),
		Vida = { 1.5, 2.5 }, Vel = { 0.2, 0.8 }, Taxa = 40, Forma = Enum.ParticleEmitterShape.Box,
		Estilo = Enum.ParticleEmitterShapeStyle.Volume,
	})

	-- ===== o monstro =====
	local pecas = {}
	local function peca(nome, props)
		local p = parte(pasta, nome, props)
		p.Material = props.Material or Enum.Material.SmoothPlastic
		table.insert(pecas, p)
		return p
	end
	local function cunha(nome, tam, cor)
		local w = Instance.new("WedgePart")
		w.Name = nome
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = true, false, false, false, false
		w.Material = Enum.Material.SmoothPlastic
		w.Color = cor
		w.Size = tam
		w.Transparency = 1
		w.Parent = pasta
		table.insert(pecas, w)
		return w
	end
	local M = {
		Tronco = peca("MTronco", { Color = PRETO }), Cabeca = peca("MCabeca", { Shape = Enum.PartType.Ball, Color = PRETO }),
		PernaD = peca("MPernaD", { Color = PRETO }), PernaE = peca("MPernaE", { Color = PRETO }),
		BracoD = peca("MBracoD", { Color = PRETO }), BracoE = peca("MBracoE", { Color = PRETO }),
		OlhoD = peca("MOlhoD", { Shape = Enum.PartType.Ball, Color = AMARELO, Material = Enum.Material.Neon }),
		OlhoE = peca("MOlhoE", { Shape = Enum.PartType.Ball, Color = AMARELO, Material = Enum.Material.Neon }),
		Chifres = {}, Dentes = {}, GarrasD = {}, GarrasE = {},
	}
	M.Tronco.Size = V3(3.4, 3.8, 1.8)
	M.Cabeca.Size = V3(3, 3, 3)
	M.PernaD.Size, M.PernaE.Size = V3(1.1, 3.4, 1.1), V3(1.1, 3.4, 1.1)
	M.OlhoD.Size, M.OlhoE.Size = V3(0.7, 0.7, 0.7), V3(0.7, 0.7, 0.7)
	for i = 1, 5 do M.Chifres[i] = cunha("MChifre" .. i, V3(0.5, 1.8 - math.abs(i - 3) * 0.3, 0.9), PRETO) end
	for i = 1, 8 do M.Dentes[i] = cunha("MDente" .. i, V3(0.12, 0.38, 0.22), rgb(245, 245, 235)) end
	for i = 1, 3 do
		M.GarrasD[i] = cunha("MGarraD" .. i, V3(0.2, 0.9, 0.4), rgb(235, 235, 225))
		M.GarrasE[i] = cunha("MGarraE" .. i, V3(0.2, 0.9, 0.4), rgb(235, 235, 225))
	end
	local contorno = Instance.new("Highlight")
	contorno.FillTransparency = 1
	contorno.OutlineColor = AMARELO
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Adornee = pasta -- (a pasta toda; só as peças do monstro ficam visíveis com contorno)
	contorno.Parent = pasta
	-- o contorno amarelo também pega o palco, então vai só no monstro: um modelo
	local modeloM = Instance.new("Model")
	modeloM.Name = "Monstro"
	modeloM.Parent = pasta
	for _, p in ipairs(pecas) do p.Parent = modeloM end
	contorno.Adornee = modeloM

	-- fumaça preta e amarela quando ele entra no Bachira
	local fumacaFx = parte(pasta, "FumacaMonstro")
	local fumaca = emissor(fumacaFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(30, 25, 15) }, { 0.6, rgb(90, 70, 20) }, { 1, AMARELO } }), Brilho = 0.2,
		Tamanho = numeros({ { 0, 3 }, { 1, 7 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.5, 0.9 },
		Vel = { 3, 9 }, Drag = 2,
	})

	-- olhos amarelos e aura dele
	local olhoB1 = esfera(pasta, "OlhoBachira1", AMARELO)
	local olhoB2 = esfera(pasta, "OlhoBachira2", AMARELO)
	local auras = {}
	local function aura(pai, tam)
		if not pai then return end
		table.insert(auras, emissor(pai, {
			Textura = TEX.Fogo, Cor = cores({ { 0, rgb(255, 250, 200) }, { 0.4, AMARELO }, { 1, rgb(60, 40, 10) } }), Brilho = 0.9,
			Tamanho = numeros({ { 0, tam }, { 1, 0.3 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.4, 0.7 },
			Vel = { 2, 5 }, Spread = 30, Direcao = Enum.NormalId.Top,
		}))
	end
	aura(character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"), 2.6)
	aura(head, 1.8)

	local function visivelMonstro(a)
		for _, p in ipairs(pecas) do p.Transparency = 1 - a end
		contorno.OutlineTransparency = 1 - a
	end

	local ph = spec.Phases
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		-- o vazio escurece no drible
		local escuro = smooth(phase(t, 7.3, 8.0))
		sala.Color = CLARO:Lerp(rgb(12, 10, 8), escuro)
		faiscas.Enabled = t < 9.5

		-- onde o monstro está: à esquerda dele, andando junto
		local r = s.RootLocal
		local surge = smooth(phase(t, 0.3, 1.6))
		local entra = smooth(phase(t, ph.Entra[1], ph.Entra[2]))
		local mLocal = V3(-3.8, 0, 1.2) + V3(0, 0, r.Z)
		if t >= 7.5 then mLocal = V3(-2.6, 0, r.Z + 2.4) end -- atrás dele no drible
		mLocal = mLocal:Lerp(r + V3(0, -1, 0), entra)
		local escala = 1 - 0.75 * entra
		local passo = (t >= 4.5 and t < 7.5) and math.sin((t - 4.5) * math.pi * 2 * 1.3) or 0
		local base = ctx.Inicio * CFrame.new(mLocal.X, chao, mLocal.Z) * CFrame.Angles(0, t >= 7.5 and math.rad(-15) or 0, 0)
		local quadril = base * CFrame.new(0, 3.3 * escala, 0)
		local inclina = t < 2 and math.rad(-20 * surge) or (t < 4.5 and math.rad(-28) or math.rad(-12))
		local tronco = quadril * CFrame.Angles(inclina, 0, 0) * CFrame.new(0, 1.9 * escala, 0)
		M.Tronco.Size = V3(3.4, 3.8, 1.8) * escala
		M.Tronco.CFrame = tronco
		local cab = tronco * CFrame.new(0, 3.1 * escala, -0.3 * escala) * CFrame.Angles(math.rad(-15), math.rad(t < 4.5 and 25 or 10), 0)
		M.Cabeca.Size = V3(3, 3, 3) * escala
		M.Cabeca.CFrame = cab
		M.OlhoD.Size, M.OlhoE.Size = V3(0.7, 0.7, 0.7) * escala, V3(0.7, 0.7, 0.7) * escala
		M.OlhoD.CFrame = cab * CFrame.new(0.6 * escala, 0.25 * escala, -1.35 * escala)
		M.OlhoE.CFrame = cab * CFrame.new(-0.6 * escala, 0.25 * escala, -1.35 * escala)
		for i, c in ipairs(M.Chifres) do
			local a = math.rad(-60 + (i - 1) * 30)
			c.CFrame = cab * CFrame.new(math.sin(a) * 1.3 * escala, math.cos(a) * 1.3 * escala + 0.2, 0.2) * CFrame.Angles(0, 0, -a)
		end
		for i, d in ipairs(M.Dentes) do
			local x = (i - 4.5) * 0.24
			d.CFrame = cab * CFrame.new(x * escala, -0.55 * escala - math.abs(x) * 0.25, -1.28 * escala) * CFrame.Angles(math.rad(180), 0, 0)
		end
		for lado, perna in pairs({ [1] = M.PernaD, [-1] = M.PernaE }) do
			perna.Size = V3(1.1, 3.4, 1.1) * escala
			perna.CFrame = quadril * CFrame.new(0.9 * lado * escala, 0, 0) * CFrame.Angles(math.rad(28 * passo * lado), 0, 0) * CFrame.new(0, -1.65 * escala, 0)
		end
		-- braço direito: do ombro até a mão do Bachira (segurando), ou pendurado
		local ombroD = (tronco * CFrame.new(1.9 * escala, 1.3 * escala, 0)).Position
		local ombroE = (tronco * CFrame.new(-1.9 * escala, 1.3 * escala, 0)).Position
		local segura = smooth(phase(t, 2.4, 3.3)) * (1 - smooth(phase(t, 7.4, 7.8)))
		local livreD = (tronco * CFrame.new(2.2 * escala, -2.2 * escala, -0.6)).Position
		local alvoD = livreD
		if maoBachira and segura > 0 then
			local maoPos = maoBachira.CFrame:PointToWorldSpace(V3(0, -maoBachira.Size.Y / 2, 0))
			alvoD = livreD:Lerp(maoPos, segura)
		end
		if t >= 7.5 then alvoD = (tronco * CFrame.new(3.4 * escala, 1.8 * escala, -2.2)).Position end -- garras abertas no drible
		local alvoE = (tronco * CFrame.new(-2.6 * escala, -2 * escala + math.sin(t * 2) * 0.3, -0.4)).Position
		if t >= 7.5 then alvoE = (tronco * CFrame.new(-3.4 * escala, 1.8 * escala, -2.2)).Position end
		local function braco(p, de, ate, garras)
			local len = math.max((ate - de).Magnitude, 0.5)
			p.Size = V3(0.8 * escala, 0.8 * escala, len)
			local cf = CFrame.lookAt((de + ate) / 2, ate)
			p.CFrame = cf
			local ponta = CFrame.lookAt(ate, ate + cf.LookVector)
			for i, g in ipairs(garras) do
				g.CFrame = ponta * CFrame.new((i - 2) * 0.28, 0, -0.35) * CFrame.Angles(math.rad(-90), 0, 0)
			end
		end
		braco(M.BracoD, ombroD, alvoD, M.GarrasD)
		braco(M.BracoE, ombroE, alvoE, M.GarrasE)
		visivelMonstro(surge * (1 - smooth(phase(t, ph.Entra[2] - 0.3, ph.Entra[2]))))

		-- fumaça quando ele entra
		fumacaFx.CFrame = ctx.Root.CFrame
		fumaca.Enabled = t >= ph.Entra[1] and t < ph.Entra[2] + 0.3
		fumaca.Rate = 70

		-- olhos amarelos a partir do drible
		if head then
			local olhos = FlowCenaOlhos(head)
			local a = smooth(phase(t, 7.6, 7.9))
			olhoB1.Size, olhoB2.Size = Vector3.one * 0.3, Vector3.one * 0.3
			olhoB1.CFrame = head.CFrame * CFrame.new(olhos[1])
			olhoB2.CFrame = head.CFrame * CFrame.new(olhos[2])
			olhoB1.Transparency = a > 0.02 and 0 or 1
			olhoB2.Transparency = olhoB1.Transparency
		end
		for _, a in ipairs(auras) do
			a.Enabled = t >= ph.Entra[2] - 0.2
			a.Rate = 70
		end
	end
	function efeitos.Impacto(_s)
		ctx.Flash(AMARELO, 0.25, 0.4)
		onda(pasta, ctx.Root.Position, Vector3.yAxis, AMARELO, 26, 0.45, 0.35)
		anelVazado(pasta, ctx.Root.Position, ctx.Inicio.LookVector, rgb(255, 245, 190), 2, 18, 0.4, 0.25)
		ctx.Tremer(0.6, 0.3)
	end
	return efeitos
end


-- ============================================================
-- 🪶 FLOW DO NAGI (⚠️ v113) — ver a coreografia Flow_Nagi
-- ============================================================
-- Vazio azul-acinzentado calmo, PENAS brancas caindo, uma cópia da bola que
-- cai do céu, morre no pé, fica presa no pé no ar enquanto ele gira, passa
-- pela finta e sai no chute com rastro branco. Olhos claros no final.
function E.FlowNagi(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local BRANCO, AZUL_CLARO = rgb(250, 252, 255), rgb(180, 210, 255)
	local character = ctx.Character
	local head = character:FindFirstChild("Head")
	local pernaD = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
	local ph = spec.Phases

	local sala = salaEscura(pasta, "SalaFlowNagi", rgb(38, 44, 60), ctx.Inicio * CFrame.new(0, 20, -8), 140, ctx.ChaoY + 0.1 - 20)
	sala.Transparency = 0

	-- penas caindo (partícula achatada e girando devagar)
	local ceu = parte(pasta, "CeuPenas")
	ceu.Size = V3(36, 1, 36)
	ceu.CFrame = ctx.Inicio * CFrame.new(0, 14, -3)
	local penas = emissor(ceu, {
		Cor = BRANCO, Tamanho = numeros({ { 0, 0.55 }, { 1, 0.45 } }), Transp = numeros({ { 0, 0.1 }, { 0.8, 0.2 }, { 1, 1 } }),
		Vida = { 4, 6 }, Vel = { 0.5, 1.5 }, Acel = V3(0, -1.2, 0), Drag = 0.4, RotVel = 90, Taxa = 22,
		Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume, Direcao = Enum.NormalId.Bottom,
	})
	penas.Squash = numeros({ { 0, 1.2 }, { 1, 1.2 } })

	-- a bola da cena
	local bola
	if ctx.Ball then
		local ok, c = pcall(function() return ctx.Ball:Clone() end)
		if ok and c then
			bola = c
			for _, d in ipairs(bola:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") then d:Destroy() end
			end
			if bola:IsA("BasePart") then
				bola.Anchored, bola.CanCollide, bola.CanQuery, bola.CanTouch = true, false, false, false
			end
			bola.Parent = pasta
		end
	end
	if not bola then
		bola = esfera(pasta, "BolaNagi", BRANCO, Enum.Material.SmoothPlastic)
		bola.Size = Vector3.one * (ctx.TamanhoBola or 1.7)
	end
	local rastroBola = rastroDuplo(bola, 0.9, AZUL_CLARO, BRANCO, 0.45)
	local rastrosPernas = {}
	for _, nome in ipairs({ "Right Leg", "Left Leg", "RightLowerLeg", "LeftLowerLeg" }) do
		local p = character:FindFirstChild(nome)
		if p then table.insert(rastrosPernas, rastroDuplo(p, 0.6, AZUL_CLARO, BRANCO, 0.3)) end
	end
	local olhos = { esfera(pasta, "OlhoNagi1", AZUL_CLARO), esfera(pasta, "OlhoNagi2", AZUL_CLARO) }
	local auraFx = parte(pasta, "AuraNagi")
	local aura = emissor(auraFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, BRANCO }, { 1, AZUL_CLARO } }), Brilho = 0.5,
		Tamanho = numeros({ { 0, 1.5 }, { 1, 4 } }), Transp = numeros({ { 0, 0.6 }, { 1, 1 } }), Vida = { 0.8, 1.4 },
		Vel = { 0.5, 1.5 }, Acel = V3(0, 2, 0), Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
	})
	auraFx.Size = V3(2.5, 4.5, 1.5)

	local function noPe()
		if not pernaD then return ctx.Root.Position end
		-- em cima do peito do pé
		return pernaD.CFrame:PointToWorldSpace(V3(0, -pernaD.Size.Y / 2 + 0.2, -0.5 - (ctx.TamanhoBola or 1.7) / 2))
	end
	-- contorno claro (fundo escuro) e luz no rosto no final
	local contorno = Instance.new("Highlight")
	contorno.FillTransparency = 1
	contorno.OutlineColor = AZUL_CLARO
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Adornee = character
	contorno.Parent = pasta
	local luzRosto = parte(pasta, "LuzRostoNagi")
	local luzRostoL = luz(luzRosto, rgb(220, 230, 255), 0, 1.4)

	local posChute = nil
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local r = s.RootLocal
		if head then
			luzRosto.CFrame = head.CFrame * CFrame.new(0, -0.2, -2.6)
			luzRostoL.Range = t >= 8.8 and 7 or 0
		end
		local pos
		if t < ph.Cai[2] then
			local u = phase(t, 0, ph.Cai[2])
			pos = ctx.Mundo(V3(0.4, 22, -3)):Lerp(noPe(), u * u)
		elseif t < ph.Levanta[1] then
			pos = noPe() -- amortecendo: presa no pé
		elseif t < ph.Levanta[2] then
			local u = easeOut(phase(t, ph.Levanta[1], ph.Levanta[2]))
			pos = noPe():Lerp(ctx.Mundo(V3(0.4, 4.5, -1.3)), u)
		elseif t < 3.3 then
			local u = smooth(phase(t, ph.Levanta[2], 3.3))
			pos = ctx.Mundo(V3(0.4, 4.5, -1.3)):Lerp(noPe(), u)
		elseif t < ph.Finta[1] then
			pos = noPe() -- presa no pé no ar, girando com ele
		elseif t < ph.Kick[2] then
			-- finta: a perna passa e a bola vai caindo na frente dele
			local u = phase(t, ph.Finta[1], ph.Kick[2])
			pos = ctx.Mundo(r + V3(0.2, -1.2 - 1.2 * u * u, -1.6))
			posChute = pos
		else
			local u = easeOut(phase(t, ph.Kick[2], ph.Voa[2]))
			local de = posChute or ctx.Mundo(r + V3(0.2, -2.4, -1.6))
			pos = de:Lerp(ctx.Mundo(r + V3(0, 3, -70)), u)
		end
		bola.CFrame = CFrame.new(pos) * CFrame.Angles(t * 4, t * 3, 0)
		bola.Transparency = t < ph.Voa[2] and 0 or 1
		rastroBola.Ligar(t >= ph.Kick[2] and t < ph.Voa[2])
		for _, rr in ipairs(rastrosPernas) do rr.Ligar(t >= ph.Gira[1] and t < ph.Kick[2] + 0.1) end

		if head then
			local o = FlowCenaOlhos(head)
			local a = smooth(phase(t, 8.8, 9.3))
			for i, e in ipairs(olhos) do
				e.Size = Vector3.one * 0.26
				e.CFrame = head.CFrame * CFrame.new(o[i])
				e.Transparency = a > 0.02 and (1 - a * 0.9) or 1
			end
		end
		auraFx.CFrame = ctx.Root.CFrame
		aura.Enabled = t >= 8.6
		aura.Rate = 18
	end
	function efeitos.Impacto(s)
		onda(pasta, bola.Position, ctx.Inicio.LookVector, BRANCO, 18, 0.35, 0.3)
		anelVazado(pasta, bola.Position, ctx.Inicio.LookVector, AZUL_CLARO, 1.5, 12, 0.3, 0.25)
		penas:Emit(40)
	end
	return efeitos
end


-- ============================================================
-- 🦖 FLOW DO RIN (⚠️ v113) — ver a coreografia Flow_Rin
-- ============================================================
-- Palco escuro que fica VERMELHO no pisão; o dinossauro de brinquedo verde
-- (corpo, cabeça, espinhos, rabo, patas) que estoura em pedaços; a LÍNGUA pra
-- fora; os olhos em ESPIRAL (anéis verde-água girando, miolo rosa); fumaça
-- vermelha; aura verde-água na corrida e no final.
function E.FlowRin(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local VERDE_AGUA, ROSA, VERMELHO = rgb(40, 230, 210), rgb(255, 90, 150), rgb(210, 20, 35)
	local character = ctx.Character
	local head = character:FindFirstChild("Head")
	local ph = spec.Phases
	local chao = ctx.ChaoY

	local sala = salaEscura(pasta, "SalaFlowRin", rgb(10, 8, 10), ctx.Inicio * CFrame.new(0, 20, -9), 140, chao + 0.1 - 20)
	sala.Transparency = 0
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "FlowRinCor"
	cc.Parent = workspace.CurrentCamera
	pasta.Destroying:Connect(function() cc:Destroy() end)

	-- ===== o dinossauro de brinquedo =====
	local BASE = V3(0, chao, -2.2)
	local ESC = 0.62 -- tamanho do brinquedo
	local VERDE_TOY, BRANCO = rgb(80, 170, 90), rgb(235, 235, 220)
	local dino = {}
	local function peca(nome, forma, tam, cor, rel)
		local p
		if forma == "Cunha" then
			p = Instance.new("WedgePart")
			p.Name = nome
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Parent = pasta
		else
			p = parte(pasta, nome, forma and { Shape = forma } or nil)
		end
		p.Material = Enum.Material.SmoothPlastic
		p.Color = cor
		p.Size = tam * ESC
		p.Transparency = 0
		local rng = Random.new(#dino + 3)
		rel = CFrame.new(rel.Position * ESC) * (rel - rel.Position)
		table.insert(dino, { Parte = p, Rel = rel,
			Vel = V3(rng:NextNumber(-9, 9), rng:NextNumber(8, 16), rng:NextNumber(-9, 4)),
			Giro = V3(rng:NextNumber(-12, 12), rng:NextNumber(-12, 12), rng:NextNumber(-12, 12)) })
		return p
	end
	-- (de frente pra ele: a cabeça do bicho aponta pra +Z)
	peca("DinoCorpo", Enum.PartType.Ball, V3(1.6, 1.4, 2.4), VERDE_TOY, CFrame.new(0, 1.1, 0))
	peca("DinoBarriga", Enum.PartType.Ball, V3(1.2, 1.1, 1.8), rgb(200, 210, 150), CFrame.new(0, 0.95, 0.25))
	peca("DinoCabeca", Enum.PartType.Ball, V3(1.1, 1, 1.3), VERDE_TOY, CFrame.new(0, 2.1, 1.05))
	peca("DinoFocinho", nil, V3(0.7, 0.45, 0.7), VERDE_TOY, CFrame.new(0, 1.95, 1.65))
	peca("DinoOlhoD", Enum.PartType.Ball, V3(0.22, 0.22, 0.22), rgb(20, 20, 20), CFrame.new(0.3, 2.3, 1.55))
	peca("DinoOlhoE", Enum.PartType.Ball, V3(0.22, 0.22, 0.22), rgb(20, 20, 20), CFrame.new(-0.3, 2.3, 1.55))
	peca("DinoRabo", "Cunha", V3(0.6, 0.6, 1.8), VERDE_TOY, CFrame.new(0, 0.8, -1.9) * CFrame.Angles(0, math.pi, 0))
	for i = 1, 5 do
		peca("DinoEspinho" .. i, "Cunha", V3(0.15, 0.5 - math.abs(i - 3) * 0.06, 0.4), BRANCO, CFrame.new(0, 1.85, 0.8 - i * 0.38))
	end
	for i, p in ipairs({ { 0.5, 0.6 }, { -0.5, 0.6 }, { 0.5, -0.6 }, { -0.5, -0.6 } }) do
		peca("DinoPata" .. i, nil, V3(0.45, 0.6, 0.5), VERDE_TOY, CFrame.new(p[1], 0.3, p[2]))
	end

	-- ===== língua e olhos em espiral =====
	local lingua = parte(pasta, "LinguaRin", { Shape = Enum.PartType.Cylinder, Color = rgb(230, 95, 115), Material = Enum.Material.SmoothPlastic })
	local olhos = {}
	for i = 1, 2 do
		olhos[i] = {
			Fora = parte(pasta, "OlhoFora" .. i, { Shape = Enum.PartType.Cylinder, Color = VERDE_AGUA }),
			Meio = parte(pasta, "OlhoMeio" .. i, { Shape = Enum.PartType.Cylinder, Color = rgb(10, 60, 70) }),
			Dentro = parte(pasta, "OlhoDentro" .. i, { Shape = Enum.PartType.Cylinder, Color = VERDE_AGUA }),
			Miolo = parte(pasta, "OlhoMiolo" .. i, { Shape = Enum.PartType.Ball, Color = ROSA }),
		}
	end

	-- fumaça vermelha e aura verde-água
	local fumacaFx = parte(pasta, "FumacaRin")
	fumacaFx.Size = V3(30, 2, 30)
	local fumaca = emissor(fumacaFx, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(120, 0, 10) }, { 1, rgb(30, 0, 5) } }), Brilho = 0.15,
		Tamanho = numeros({ { 0, 4 }, { 1, 9 } }), Transp = numeros({ { 0, 0.4 }, { 1, 1 } }), Vida = { 1, 1.8 },
		Vel = { 1, 3 }, Acel = V3(0, 2, 0), Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
	})
	local auras = {}
	local function aura(pai, tam)
		if not pai then return end
		table.insert(auras, emissor(pai, {
			Textura = TEX.Fogo, Cor = cores({ { 0, rgb(210, 255, 250) }, { 0.4, VERDE_AGUA }, { 1, rgb(0, 60, 60) } }), Brilho = 1,
			Tamanho = numeros({ { 0, tam }, { 1, 0.2 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.35, 0.6 },
			Vel = { 2, 5 }, Spread = 30, Direcao = Enum.NormalId.Top, Acel = ctx.Inicio:VectorToWorldSpace(V3(0, 3, 8)),
		}))
	end
	aura(character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"), 2.4)
	aura(head, 1.7)
	local contorno = Instance.new("Highlight")
	contorno.FillTransparency = 1
	contorno.OutlineColor = VERDE_AGUA
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Adornee = character
	contorno.Parent = pasta
	local luzRosto = parte(pasta, "LuzRostoRin")
	local luzRostoL = luz(luzRosto, rgb(255, 225, 225), 0, 1.5)

	local pisou = false
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		local vermelho = smooth(phase(t, ph.Pisao[1], ph.Pisao[1] + 0.25))
		sala.Color = rgb(10, 8, 10):Lerp(rgb(95, 6, 14), vermelho)
		cc.TintColor = Color3.new(1, 1, 1):Lerp(rgb(255, 205, 205), vermelho)
		cc.Contrast = 0.1 + 0.2 * vermelho
		contorno.OutlineTransparency = t >= 5.6 and 0 or 1

		-- o dinossauro: inteiro até o pisão, depois os pedaços voam
		-- de perfil pra câmera (a silhueta do bicho)
		local base = ctx.Inicio * CFrame.new(BASE) * CFrame.Angles(0, math.rad(90), 0)
		local dt = math.max(t - ph.Pisao[1], 0)
		for _, d in ipairs(dino) do
			local cf = base * d.Rel
			if t >= ph.Pisao[1] then
				local p = cf.Position + ctx.Inicio:VectorToWorldSpace(d.Vel) * dt + V3(0, -30 * dt * dt, 0)
				p = V3(p.X, math.max(p.Y, ctx.Mundo(V3(0, chao, 0)).Y + 0.2), p.Z)
				cf = CFrame.new(p) * (cf - cf.Position) * CFrame.Angles(d.Giro.X * dt, d.Giro.Y * dt, d.Giro.Z * dt)
			end
			d.Parte.CFrame = cf
			d.Parte.Transparency = t >= ph.Pisao[1] + 0.9 and 1 or 0
		end
		if not pisou and t >= ph.Pisao[1] then
			pisou = true
			ctx.Flash(VERMELHO, 0.1, 0.35)
			ctx.Tremer(1.1, 0.4)
			local p = ctx.Mundo(BASE + V3(0, 0.2, 0))
			onda(pasta, p, Vector3.yAxis, VERMELHO, 22, 0.35, 0.4)
			anelVazado(pasta, p, Vector3.yAxis, rgb(255, 150, 150), 1, 16, 0.4, 0.3)
		end

		-- língua e olhos
		if head then
			local lingOn = (t >= 2.1 and t < 5.6) or t >= 9.2
			-- disco fino pendurado pra fora da boca (de lado: o eixo do cilindro é X)
			lingua.Size = V3(0.05, 0.24, 0.2)
			lingua.CFrame = head.CFrame * CFrame.new(0.05, -head.Size.Y * 0.36, -head.Size.Z / 2 - 0.06)
				* CFrame.Angles(math.rad(-20), 0, 0) * CFrame.Angles(0, math.rad(90), 0)
			lingua.Transparency = lingOn and 0 or 1
			local o = FlowCenaOlhos(head)
			local espiral = (t >= 2.4 and t < 5.6) or t >= 9.2
			for i, e in ipairs(olhos) do
				local cf = head.CFrame * CFrame.new(o[i] + V3(0, 0, -0.02)) * CFrame.Angles(0, math.rad(90), 0)
				local g = CFrame.Angles(t * 8 * (i == 1 and 1 or -1), 0, 0)
				e.Fora.Size = V3(0.03, 0.3, 0.3)
				e.Meio.Size = V3(0.035, 0.22, 0.22)
				e.Dentro.Size = V3(0.04, 0.14, 0.14)
				e.Miolo.Size = Vector3.one * 0.08
				e.Fora.CFrame = cf * g
				e.Meio.CFrame = cf * g * CFrame.new(-0.005, 0.02, 0)
				e.Dentro.CFrame = cf * g * CFrame.new(-0.01, -0.02, 0.01)
				e.Miolo.CFrame = cf * CFrame.new(-0.02, 0, 0)
				local tr = espiral and 0 or 1
				e.Fora.Transparency, e.Meio.Transparency, e.Dentro.Transparency, e.Miolo.Transparency = tr, tr, tr, tr
			end
			luzRosto.CFrame = head.CFrame * CFrame.new(0, -0.2, -2.6)
			luzRostoL.Range = ((t >= 2 and t < 4.2) or t >= 9) and 7 or 0
		end

		fumacaFx.CFrame = ctx.Inicio * CFrame.new(0, chao + 1, s.RootLocal.Z - 4)
		fumaca.Enabled = t >= ph.Pisao[1]
		fumaca.Rate = 30
		for _, a in ipairs(auras) do
			a.Enabled = t >= 5.6
			a.Rate = 80
		end
	end
	function efeitos.Impacto(_s)
		ctx.Flash(rgb(255, 200, 200), 0.2, 0.4)
		onda(pasta, ctx.Root.Position, ctx.Inicio.LookVector, VERDE_AGUA, 20, 0.35, 0.3)
	end
	return efeitos
end


-- ============================================================
-- ⚡ BASE COMUM DAS CENAS DE FLOW (⚠️ v113)
-- ============================================================
-- Palco (sala com chão rente ao gramado), contorno do corpo, olhos acesos,
-- aura de chama, luz no rosto e um emissor de "partículas do tema" (pétalas,
-- brasas...). Cada Flow passa as cores e os tempos; Atualizar(t) liga/desliga.
--   op.Sala (cor), op.SalaCor2 + op.SalaVira {t0,t1} (troca de cor), op.Contorno
--   (cor), op.ContornoDe (t), op.Olhos (cor), op.OlhosDe (t), op.Aura {claro,
--   cor, escuro}, op.AuraDe (t), op.Rosto { {t0,t1}, ... } (luz no rosto),
--   op.Particulas { Cor, Tamanho, Taxa, De, Ate, Textura, Vel, Acel }
local function flowBase(ctx, op)
	local pasta = ctx.Pasta
	local character = ctx.Character
	local head = character:FindFirstChild("Head")
	local B = {}
	local sala = salaEscura(pasta, "SalaFlow", op.Sala or rgb(14, 14, 18), ctx.Inicio * CFrame.new(0, 20, -8), 150, ctx.ChaoY + 0.1 - 20)
	sala.Transparency = 0
	B.Sala = sala
	local contorno = Instance.new("Highlight")
	contorno.FillTransparency = 1
	contorno.OutlineColor = op.Contorno or Color3.new(1, 1, 1)
	contorno.OutlineTransparency = 1
	contorno.DepthMode = Enum.HighlightDepthMode.Occluded
	contorno.Adornee = character
	contorno.Parent = pasta
	B.Contorno = contorno
	local olhos = { esfera(pasta, "OlhoFlow1", op.Olhos or Color3.new(1, 1, 1)), esfera(pasta, "OlhoFlow2", op.Olhos or Color3.new(1, 1, 1)) }
	local auras = {}
	if op.Aura then
		local function aura(pai, tam)
			if not pai then return end
			table.insert(auras, emissor(pai, {
				Textura = TEX.Fogo, Cor = cores({ { 0, op.Aura[1] }, { 0.4, op.Aura[2] }, { 1, op.Aura[3] } }), Brilho = 0.95,
				Tamanho = numeros({ { 0, tam }, { 1, 0.2 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.35, 0.65 },
				Vel = { 2, 5 }, Spread = 30, Direcao = Enum.NormalId.Top,
			}))
		end
		aura(character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso"), 2.5)
		aura(head, 1.7)
	end
	local luzRosto = parte(pasta, "LuzRostoFlow")
	local luzRostoL = luz(luzRosto, rgb(240, 240, 255), 0, 1.5)
	local part
	if op.Particulas then
		local pp = op.Particulas
		local caixa = parte(pasta, "ParticulasFlow")
		caixa.Size = V3(34, 16, 34)
		caixa.CFrame = ctx.Inicio * CFrame.new(0, 6, -8)
		part = emissor(caixa, {
			Textura = pp.Textura, Cor = pp.Cor, Tamanho = pp.Tamanho or numeros({ { 0, 0.5 }, { 1, 0.4 } }),
			Transp = numeros({ { 0, 0.1 }, { 0.8, 0.25 }, { 1, 1 } }), Vida = pp.Vida or { 3, 5 }, Vel = pp.Vel or { 0.5, 2 },
			Acel = pp.Acel or V3(0, -1, 0), Drag = 0.4, RotVel = 120, Taxa = pp.Taxa or 25,
			Forma = Enum.ParticleEmitterShape.Box, Estilo = Enum.ParticleEmitterShapeStyle.Volume,
		})
		if pp.Achatar then part.Squash = numeros({ { 0, pp.Achatar }, { 1, pp.Achatar } }) end
	end
	function B.Atualizar(t)
		if op.SalaCor2 and op.SalaVira then
			sala.Color = (op.Sala or rgb(14, 14, 18)):Lerp(op.SalaCor2, smooth(phase(t, op.SalaVira[1], op.SalaVira[2])))
		end
		contorno.OutlineTransparency = t >= (op.ContornoDe or 0) and 0 or 1
		if head then
			local o = FlowCenaOlhos(head)
			local a = t >= (op.OlhosDe or math.huge)
			for i, e in ipairs(olhos) do
				e.Size = Vector3.one * 0.28
				e.CFrame = head.CFrame * CFrame.new(o[i])
				e.Transparency = a and 0 or 1
			end
			luzRosto.CFrame = head.CFrame * CFrame.new(0, -0.2, -2.6)
			local r = 0
			for _, j in ipairs(op.Rosto or {}) do
				if t >= j[1] and t < j[2] then r = 7 end
			end
			luzRostoL.Range = r
		end
		for _, a in ipairs(auras) do
			a.Enabled = t >= (op.AuraDe or math.huge)
			a.Rate = 80
		end
		if part then
			part.Enabled = t >= (op.Particulas.De or 0) and t < (op.Particulas.Ate or math.huge)
		end
	end
	return B
end
E.FlowBase = flowBase

-- 🐆 FLOW DO CHIGIRI (⚠️ v113): pétalas, olhos rosa, a PANTERA de peças
-- correndo ao lado (corpo, cabeça, orelhas, patas galopando, rabo) e o rastro
-- rosa das pernas na corrida.
function E.FlowChigiri(ctx)
	local pasta = ctx.Pasta
	local ROSA, VINHO = rgb(255, 110, 150), rgb(90, 10, 30)
	local base = flowBase(ctx, {
		Sala = rgb(24, 10, 16), Contorno = ROSA, ContornoDe = 3.6, Olhos = ROSA, OlhosDe = 3.0,
		Aura = { rgb(255, 230, 240), ROSA, rgb(80, 0, 30) }, AuraDe = 9,
		Rosto = { { 2.2, 3.6 }, { 9, 12 } },
		Particulas = { Cor = cores({ { 0, rgb(255, 200, 220) }, { 1, ROSA } }), Tamanho = numeros({ { 0, 0.5 }, { 1, 0.4 } }), Taxa = 30, Achatar = 1.3 },
	})
	-- rastro rosa nas pernas
	local rastros = {}
	for _, nome in ipairs({ "Right Leg", "Left Leg", "RightLowerLeg", "LeftLowerLeg" }) do
		local p = ctx.Character:FindFirstChild(nome)
		if p then table.insert(rastros, rastroDuplo(p, 0.7, ROSA, rgb(255, 230, 240), 0.35)) end
	end
	-- a pantera
	local P = {}
	local function peca(nome, props, tam)
		local p = parte(pasta, nome, props)
		p.Material = Enum.Material.SmoothPlastic
		p.Size = tam
		table.insert(P, p)
		return p
	end
	local corpo = peca("PCorpo", { Shape = Enum.PartType.Cylinder, Color = VINHO }, V3(4.2, 1.4, 1.4))
	local cabeca = peca("PCabeca", { Shape = Enum.PartType.Ball, Color = VINHO }, V3(1.3, 1.3, 1.3))
	local orelhas = { peca("POrelha1", { Color = VINHO }, V3(0.3, 0.45, 0.2)), peca("POrelha2", { Color = VINHO }, V3(0.3, 0.45, 0.2)) }
	local olhosP = { peca("POlho1", { Shape = Enum.PartType.Ball, Color = ROSA, Material = Enum.Material.Neon }, V3(0.22, 0.22, 0.22)),
		peca("POlho2", { Shape = Enum.PartType.Ball, Color = ROSA, Material = Enum.Material.Neon }, V3(0.22, 0.22, 0.22)) }
	olhosP[1].Material, olhosP[2].Material = Enum.Material.Neon, Enum.Material.Neon
	local patas = {}
	for i = 1, 4 do patas[i] = peca("PPata" .. i, { Color = VINHO }, V3(0.4, 1.6, 0.4)) end
	local rabo = peca("PRabo", { Shape = Enum.PartType.Cylinder, Color = VINHO }, V3(2.2, 0.3, 0.3))
	-- (maior: do tamanho de um bicho de verdade ao lado dele)
	for _, p in ipairs(P) do p.Size = p.Size * 1.4 end
	local modelo = Instance.new("Model")
	modelo.Name = "Pantera"
	modelo.Parent = pasta
	for _, p in ipairs(P) do p.Parent = modelo end
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = ROSA
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = modelo
	hl.Parent = pasta

	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		base.Atualizar(t)
		for _, r in ipairs(rastros) do r.Ligar(t >= 3.8 and t < 8.4) end
		-- pantera: aparece na corrida, ao lado (x+2.6), começa na frente e ele a passa
		local vis = smooth(phase(t, 3.8, 4.2)) * (1 - smooth(phase(t, 7.2, 7.6)))
		local r = s.RootLocal
		local frente = 3 - 6 * smooth(phase(t, 4, 7.4))
		local galope = (t - 3.6) * math.pi * 2 * 3
		local salto = math.abs(math.sin(galope)) * 0.5
		local E_ = 1.4
		local cf = ctx.Inicio * CFrame.new(r.X + 3.2, ctx.ChaoY + 1.7 * E_ + salto, r.Z - frente) * CFrame.Angles(math.sin(galope) * 0.12, 0, 0)
		corpo.CFrame = cf * CFrame.Angles(0, math.rad(90), 0)
		cabeca.CFrame = cf * CFrame.new(0, 0.35 * E_, -2.5 * E_)
		orelhas[1].CFrame = cabeca.CFrame * CFrame.new(0.35 * E_, 0.65 * E_, 0)
		orelhas[2].CFrame = cabeca.CFrame * CFrame.new(-0.35 * E_, 0.65 * E_, 0)
		olhosP[1].CFrame = cabeca.CFrame * CFrame.new(0.28 * E_, 0.1 * E_, -0.58 * E_)
		olhosP[2].CFrame = cabeca.CFrame * CFrame.new(-0.28 * E_, 0.1 * E_, -0.58 * E_)
		for i, pata in ipairs(patas) do
			local frenteTras = i <= 2 and -1.5 or 1.5
			local lado = (i % 2 == 0) and 0.45 or -0.45
			local fase = galope + (i <= 2 and 0 or math.pi) + (i % 2) * 0.5
			pata.CFrame = cf * CFrame.new(lado * E_, -0.4 * E_, frenteTras * E_) * CFrame.Angles(math.sin(fase) * 0.9, 0, 0) * CFrame.new(0, -0.7 * E_, 0)
		end
		rabo.CFrame = cf * CFrame.new(0, 0.3 * E_, 2.9 * E_) * CFrame.Angles(math.rad(25) + math.sin(galope) * 0.2, math.rad(90), 0)
		for _, p in ipairs(P) do p.Transparency = 1 - vis end
		hl.OutlineTransparency = 1 - vis
	end
	function efeitos.Impacto(_s)
		ctx.Flash(rgb(255, 210, 225), 0.2, 0.4)
		anelVazado(pasta, ctx.Root.Position, Vector3.yAxis, ROSA, 2, 22, 0.45, 0.3)
	end
	return efeitos
end


-- bola de cena (cópia da bola; a de verdade não sai do lugar)
local function bolaDeCena(ctx)
	local bola
	if ctx.Ball then
		local ok, c = pcall(function() return ctx.Ball:Clone() end)
		if ok and c then
			bola = c
			for _, d in ipairs(bola:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("BillboardGui") or d:IsA("Trail")
					or d:IsA("VectorForce") or d:IsA("Highlight") then d:Destroy() end
			end
			if bola:IsA("BasePart") then bola.Anchored, bola.CanCollide, bola.CanQuery, bola.CanTouch = true, false, false, false end
			bola.Parent = ctx.Pasta
		end
	end
	if not bola then
		bola = esfera(ctx.Pasta, "BolaCena", rgb(250, 250, 250), Enum.Material.SmoothPlastic)
		bola.Size = Vector3.one * (ctx.TamanhoBola or 1.7)
	end
	return bola
end

-- 🔥 FLOW DO KUNIGAMI (⚠️ v113): chamas subindo atrás, o chute de canhota que
-- racha o chão, a bola de FOGO, olhos laranja, aura.
function E.FlowKunigami(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local LARANJA, AMARELO = rgb(255, 150, 40), rgb(255, 225, 120)
	local base = flowBase(ctx, {
		Sala = rgb(20, 10, 4), SalaCor2 = rgb(55, 18, 4), SalaVira = { 2.2, 3.4 },
		Contorno = LARANJA, ContornoDe = 3.8, Olhos = LARANJA, OlhosDe = 2.6,
		Aura = { AMARELO, LARANJA, rgb(90, 20, 0) }, AuraDe = 2.6, Rosto = { { 0, 3.8 }, { 8.5, 12 } },
		Particulas = { Textura = TEX.Faisca, Cor = cores({ { 0, AMARELO }, { 1, LARANJA } }), Tamanho = numeros({ { 0, 0.3 }, { 1, 0 } }),
			Taxa = 40, Vel = { 1, 3 }, Acel = V3(0, 3, 0), De = 2.2 },
	})
	-- muro de chamas atrás dele
	local muro = parte(pasta, "MuroChamas")
	muro.Size = V3(26, 2, 4)
	muro.CFrame = ctx.Inicio * CFrame.new(0, ctx.ChaoY + 1, 7)
	local chamas = emissor(muro, {
		Textura = TEX.Fogo, Cor = cores({ { 0, AMARELO }, { 0.5, LARANJA }, { 1, rgb(80, 15, 0) } }), Brilho = 0.9,
		Tamanho = numeros({ { 0, 5 }, { 1, 1 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }), Vida = { 0.8, 1.3 },
		Vel = { 8, 14 }, Spread = 12, Direcao = Enum.NormalId.Top, Forma = Enum.ParticleEmitterShape.Box,
		Estilo = Enum.ParticleEmitterShapeStyle.Volume,
	})
	local bola = bolaDeCena(ctx)
	local fogoBola = emissor(bola, {
		Textura = TEX.Fogo, Cor = cores({ { 0, AMARELO }, { 1, LARANJA } }), Brilho = 0.9, Tamanho = numeros({ { 0, 3 }, { 1, 0.3 } }),
		Vida = { 0.25, 0.45 }, Vel = { 1, 3 }, Taxa = 0,
	})
	local rastroBola = rastroDuplo(bola, 1.1, LARANJA, AMARELO, 0.4)
	local racha = {}
	for i = 1, 10 do racha[i] = parte(pasta, "RachaFogo" .. i, { Color = LARANJA }) end
	local chutou = false
	local efeitos = {}
	function efeitos.Quadro(t, _dt, s)
		base.Atualizar(t)
		if not chutou and t >= spec.Chute then
			chutou = true
			local p = ctx.Mundo(V3(-0.5, ctx.ChaoY + 0.9, -7.6))
			ctx.Flash(rgb(255, 210, 140), 0.2, 0.3)
			onda(pasta, p, ctx.Inicio.LookVector, LARANJA, 26, 0.35, 0.4)
			onda(pasta, ctx.Mundo(V3(0, ctx.ChaoY + 0.1, -6.6)), Vector3.yAxis, AMARELO, 24, 0.4, 0.25)
			ctx.Tremer(1.1, 0.4)
		end
		chamas.Enabled = t >= 2.3 and t < 11.6
		chamas.Rate = 45
		local r = s.RootLocal
		local pos
		if t < spec.Chute then
			pos = ctx.Mundo(V3(-0.5, ctx.ChaoY + 0.9, -7.6))
		else
			local u = easeOut(phase(t, spec.Chute, 8.5))
			pos = ctx.Mundo(V3(-0.5, ctx.ChaoY + 0.9, -7.6)):Lerp(ctx.Mundo(V3(-0.5, 4, -80)), u)
		end
		bola.CFrame = CFrame.new(pos) * CFrame.Angles(t * 6, 0, 0)
		bola.Transparency = (t >= 3.6 and t < 8.5) and 0 or 1
		fogoBola.Enabled = t >= spec.Chute and t < 8.5
		fogoBola.Rate = 120
		rastroBola.Ligar(t >= spec.Chute and t < 8.5)
		-- rachaduras em leque no chão, a partir do pé de apoio
		local k = phase(t, spec.Chute, spec.Chute + 0.3)
		for i, p in ipairs(racha) do
			if k > 0 and t < 11.5 then
				local a = math.rad(-80 + (i - 1) * 17)
				local de = ctx.Mundo(V3(0, ctx.ChaoY + 0.05, -6.6))
				local comp = (4 + (i % 3) * 2) * k
				local para = de + ctx.Inicio:VectorToWorldSpace(V3(math.sin(a), 0, -math.cos(a)) * comp)
				p.Size = V3(0.25, 0.06, math.max(comp, 0.05))
				p.CFrame = CFrame.lookAt((de + para) / 2, para)
				p.Transparency = 0.05
			else
				p.Transparency = 1
			end
		end
	end
	function efeitos.Impacto(_s)
		ctx.Flash(AMARELO, 0.25, 0.4)
	end
	return efeitos
end

-- 🪞 FLOW DO REO (⚠️ v113): espelhos em volta (vidro com reflexo e moldura
-- roxa), as cópias em cores diferentes, os espelhos estilhaçam, as cópias
-- entram nele, olhos roxos, aura.
function E.FlowReo(ctx)
	local pasta, spec = ctx.Pasta, ctx.Spec
	local ROXO, LILAS = rgb(170, 100, 255), rgb(230, 210, 255)
	local base = flowBase(ctx, {
		Sala = rgb(18, 10, 28), Contorno = ROXO, ContornoDe = 6.5, Olhos = ROXO, OlhosDe = 6.3,
		Aura = { LILAS, ROXO, rgb(40, 0, 70) }, AuraDe = 6.3, Rosto = { { 9, 12 } },
		Particulas = { Cor = LILAS, Tamanho = numeros({ { 0, 0.2 }, { 1, 0 } }), Taxa = 25, Vel = { 0.3, 1 }, Acel = V3(0, 0.5, 0) },
	})
	-- as cópias em cores de outros jogadores
	local CORES = { rgb(70, 140, 255), rgb(255, 215, 70), rgb(240, 240, 255), rgb(255, 110, 150), rgb(40, 220, 200) }
	for i, s in pairs(ctx.Clones or {}) do
		if s.Modelo and not s.Real then
			local c = CORES[i] or ROXO
			for _, d in ipairs(s.Modelo:GetDescendants()) do
				if d:IsA("BasePart") then d.Color = c:Lerp(Color3.new(0, 0, 0), 0.45)
				elseif d:IsA("Highlight") then d.FillColor = c; d.OutlineColor = c:Lerp(Color3.new(1, 1, 1), 0.5) end
			end
		end
	end
	-- espelhos: vidro + moldura; estilhaçam em cacos
	local espelhos = {}
	for i, p in ipairs(spec.Espelhos) do
		local vidro = parte(pasta, "Espelho" .. i, { Material = Enum.Material.Glass, Color = rgb(200, 190, 230) })
		vidro.Reflectance = 0.35
		vidro.Size = V3(3.4, 6, 0.2)
		-- moldura: 4 filetes finos (uma placa inteira tampava o vidro)
		local moldura = {}
		for k, dim in ipairs({ { 3.6, 0.14, 0, 3.05 }, { 3.6, 0.14, 0, -3.05 }, { 0.14, 6.2, 1.75, 0 }, { 0.14, 6.2, -1.75, 0 } }) do
			local f = parte(pasta, "Moldura" .. i .. "_" .. k, { Color = ROXO })
			f.Size = V3(dim[1], dim[2], 0.14)
			moldura[k] = { Parte = f, X = dim[3], Y = dim[4] }
		end
		local cacos = {}
		local rng = Random.new(40 + i)
		for k = 1, 8 do
			local caco = parte(pasta, "Caco" .. i .. "_" .. k, { Material = Enum.Material.Glass, Color = rgb(210, 200, 240) })
			caco.Size = V3(rng:NextNumber(0.6, 1.3), rng:NextNumber(0.8, 1.6), 0.08)
			cacos[k] = { Parte = caco, Rel = V3(rng:NextNumber(-1.4, 1.4), rng:NextNumber(-2.5, 2.5), 0),
				Vel = V3(rng:NextNumber(-6, 6), rng:NextNumber(2, 9), rng:NextNumber(3, 9)), Giro = V3(rng:NextNumber(-9, 9), rng:NextNumber(-9, 9), 0) }
		end
		espelhos[i] = { Vidro = vidro, Moldura = moldura, Cacos = cacos, Pos = p }
	end
	local quebrou = false
	local efeitos = {}
	function efeitos.Quadro(t, _dt, _s)
		base.Atualizar(t)
		local sobe = easeOut(phase(t, 0.2, 1.4))
		for _, e in ipairs(espelhos) do
			local centro = V3(e.Pos.X, ctx.ChaoY + 3.1 - 6 * (1 - sobe), e.Pos.Z) * V3(1.12, 1, 1.12)
			local cf = CFrame.lookAt(ctx.Mundo(centro), ctx.Mundo(V3(0, centro.Y, 0)))
			local inteiro = t < spec.Phases.Quebra[1]
			e.Vidro.CFrame = cf
			e.Vidro.Transparency = inteiro and 0.45 or 1
			for _, f in ipairs(e.Moldura) do
				f.Parte.CFrame = cf * CFrame.new(f.X, f.Y, 0)
				f.Parte.Transparency = inteiro and 0 or 1
			end
			local dt = math.max(t - spec.Phases.Quebra[1], 0)
			for _, c in ipairs(e.Cacos) do
				if not inteiro and dt < 1.2 then
					local p = cf:PointToWorldSpace(c.Rel + c.Vel * dt + V3(0, -18 * dt * dt, 0))
					c.Parte.CFrame = CFrame.new(p) * (cf - cf.Position) * CFrame.Angles(c.Giro.X * dt, c.Giro.Y * dt, 0)
					c.Parte.Transparency = 0.3 + 0.7 * (dt / 1.2)
				else
					c.Parte.Transparency = 1
				end
			end
		end
		if not quebrou and t >= spec.Phases.Quebra[1] then
			quebrou = true
			ctx.Flash(LILAS, 0.3, 0.3)
			ctx.Tremer(0.6, 0.3)
			anelVazado(pasta, ctx.Root.Position, Vector3.yAxis, ROXO, 3, 20, 0.45, 0.3)
		end
	end
	function efeitos.Impacto(_s)
		ctx.Flash(LILAS, 0.2, 0.4)
		onda(pasta, ctx.Root.Position, Vector3.yAxis, ROXO, 20, 0.4, 0.3)
	end
	return efeitos
end


return E
