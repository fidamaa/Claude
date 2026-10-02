--[[
	EfeitosDeGol (ModuleScript) — ⚠️ v119
	LOCAL: ReplicatedStorage (place Game). Quem chama: CosmeticosClient
	(remote EfeitoDeGol), em TODOS os clientes, quando o dono do efeito marca.

	PEDIDO: "nos efeitos de gol, realmente se esforce: não fica repetindo, acontece
	no gol/bola e geralmente afeta o campo inteiro. Neve no campo inteiro; planeta
	maior, o ambiente escurece, estrelas sobem, o planeta pisca no céu; o gelo
	congela boa parte do campo. Tem que ser impactante, não discreto."

	Antes (v110-v113) cada efeito era um estouro pequeno em volta da bola que se
	REPETIA a cada ~2s até dar o tempo. Agora cada um é UM espetáculo com começo,
	meio e fim que dura o tempo inteiro (Comum 9s · Raro 10.75s · Épico 12.5s ·
	Lendário 16s · Mítico 19.5s — ver CosmeticosServer duracaoDoEfeito):
	  • começa NA BOLA/NO GOL (estouro, flash) e se espalha pelo CAMPO INTEIRO
	    (o campo é medido pelos dois gols: GolAzul/GolAmarelo);
	  • quase todos mexem no AMBIENTE (hora do dia, escurecer, cor, neblina,
	    estrelas no céu) e devolvem tudo como estava no fim;
	  • partículas densas perto da câmera de cada um (EmissorCamera) + uma camada
	    no campo todo, pra ficar cheio de onde você estiver olhando.

	⚠️ Partícula com Texture = "" NÃO aparece (testado no Studio): o Confete e as
	Pétalas antigos eram invisíveis. As texturas daqui foram geradas e enviadas
	(TEX.*), todas brancas pra poder tingir com Color/ImageColor3.

	Teste: Debug > "Testar gol" (DebugAbilitySelector) com o efeito equipado.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local E = {}

local TEX = {
	Brilho = "rbxassetid://116102662517740", -- círculo macio (miolo forte + halo largo)
	Faisca = "rbxasset://textures/particles/sparkles_main.dds",
	Fogo = "rbxasset://textures/particles/fire_main.dds",
	Estrela = "rbxassetid://124076223617744", -- estrela de 4 pontas
	Quadrado = "rbxassetid://114969590166539", -- confete
	Gota = "rbxassetid://78958439073718", -- risco de chuva
	Anel = "rbxassetid://109697697529772",
	Bolha = "rbxassetid://128373337523591",
	Esfera = "rbxassetid://110065763545195", -- planeta sombreado (cinza; tingir)
	Coracao = "rbxassetid://84266930435195",
	Petala = "rbxassetid://112377272367032",
	Floco = "rbxassetid://92470203989347",
	Nuvem = "rbxassetid://127024223594157",
	Moeda = "rbxassetid://95324231257907",
}
E.TEX = TEX
-- imagem enviada só aparece depois de baixar: pré-carrega ao entrar na partida pra
-- não sair o primeiro gol "vazio"
task.spawn(function()
	local lista = {}
	for _, id in pairs(TEX) do table.insert(lista, id) end
	pcall(function() game:GetService("ContentProvider"):PreloadAsync(lista) end)
end)

local rng = Random.new()
local function rnd(a, b) return a + (b - a) * rng:NextNumber() end
local function lerp(a, b, k) return a + (b - a) * k end
local function suave(k)
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end
local function janela(u, a, b) return math.clamp((u - a) / (b - a), 0, 1) end
local function seq(pontos)
	local k = {}
	for _, p in ipairs(pontos) do table.insert(k, NumberSequenceKeypoint.new(p[1], p[2])) end
	return NumberSequence.new(k)
end
local function cseq(pontos)
	local k = {}
	for _, p in ipairs(pontos) do table.insert(k, ColorSequenceKeypoint.new(p[1], p[2])) end
	return ColorSequence.new(k)
end
local function plano(v)
	local p = Vector3.new(v.X, 0, v.Z)
	return p.Magnitude > 1e-3 and p.Unit or Vector3.xAxis
end
local BRANCO = Color3.new(1, 1, 1)
local UP = Vector3.yAxis

-- ============================================================
-- SESSÃO: tudo de um efeito (pasta, conexões, ambiente) e a limpeza no fim
-- ============================================================
local Sessao = {}
Sessao.__index = Sessao

local function novaSessao(total)
	local s = setmetatable({}, Sessao)
	s.Total = total
	s.T0 = os.clock()
	s.Vivo = true
	s.Conexoes = {}
	s.AoFim = {}
	s.Pasta = Instance.new("Folder")
	s.Pasta.Name = "EfeitoDeGol"
	s.Pasta.Parent = workspace
	return s
end

function Sessao:Cada(fn) -- fn(t, u, dt) todo Heartbeat; devolver true para parar
	local c
	c = RunService.Heartbeat:Connect(function(dt)
		if not self.Vivo then c:Disconnect() return end
		local t = os.clock() - self.T0
		local ok, parar = pcall(fn, t, t / self.Total, dt)
		if not ok then
			warn("[EfeitosDeGol] " .. tostring(parar))
			c:Disconnect()
		elseif parar then
			c:Disconnect()
		end
	end)
	table.insert(self.Conexoes, c)
	return c
end

function Sessao:Em(seg, fn)
	task.delay(seg, function()
		if not self.Vivo then return end
		local ok, erro = pcall(fn)
		if not ok then warn("[EfeitosDeGol] " .. tostring(erro)) end
	end)
end

function Sessao:Fim()
	if not self.Vivo then return end
	self.Vivo = false
	for _, c in ipairs(self.Conexoes) do c:Disconnect() end
	for _, f in ipairs(self.AoFim) do pcall(f) end
	self.Pasta:Destroy()
end

function Sessao:Parte(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = self.Pasta
	return p
end

function Sessao:Ancora(onde, tamanho)
	return self:Parte({
		Transparency = 1,
		Size = tamanho or Vector3.new(0.2, 0.2, 0.2),
		CFrame = typeof(onde) == "Vector3" and CFrame.new(onde) or onde,
	})
end

function Sessao:Emissor(pai, props)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX.Brilho
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = pai
	return e
end

function Sessao:Estouro(pos, props, n)
	local a = self:Ancora(pos)
	local e = self:Emissor(a, props)
	e:Emit(n)
	Debris:AddItem(a, (props.Lifetime and props.Lifetime.Max or 2) + 0.3)
	return e
end

function Sessao:Tween(obj, tempo, props, estilo, direcao)
	local tw = TweenService:Create(obj, TweenInfo.new(tempo, estilo or Enum.EasingStyle.Quad, direcao or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

function Sessao:Luz(pos, cor, alcance, brilho, tempo)
	local a = self:Ancora(pos)
	local l = Instance.new("PointLight")
	l.Color = cor
	l.Range = math.min(alcance, 60)
	l.Brightness = brilho
	l.Shadows = false
	l.Parent = a
	if tempo then
		self:Tween(l, tempo, { Brightness = 0 })
		Debris:AddItem(a, tempo + 0.1)
	end
	return l, a
end

function Sessao:Flash(cor, forca, tempo)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "EfeitoDeGol_Flash"
	cc.TintColor = cor:Lerp(BRANCO, 0.35)
	cc.Brightness = forca
	cc.Parent = Lighting
	self:Tween(cc, tempo, { Brightness = 0, TintColor = BRANCO })
	Debris:AddItem(cc, tempo + 0.05)
end

-- AMBIENTE: hora do dia (sempre andando PRA FRENTE: 15h → 21h, nunca de ré),
-- correção de cor, neblina e estrelas. Entra suave, sai suave e devolve tudo.
-- Durante o efeito dá pra somar s.AmbBrilho (flash/colapso) e trocar s.AmbTint.
function Sessao:Ambiente(alvo)
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	local ceu = Lighting:FindFirstChildOfClass("Sky")
	local base = {
		Hora = Lighting.ClockTime,
		Exposicao = Lighting.ExposureCompensation,
		Estrelas = ceu and ceu.StarCount or nil,
		Atm = atm and { Density = atm.Density, Color = atm.Color, Decay = atm.Decay, Haze = atm.Haze, Glare = atm.Glare } or nil,
	}
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "EfeitoDeGol_Ambiente"
	cc.Parent = Lighting
	local hora = alvo.Hora
	if hora and hora < base.Hora then hora += 24 end
	local entrada, saida = alvo.Entrada or 1.2, alvo.Saida or 1.4
	self.AmbBrilho = 0
	self.AmbTint = nil
	self.K = 0
	self:Cada(function(t)
		local k = suave(t / entrada) * (1 - suave((t - (self.Total - saida)) / saida))
		self.K = k
		if hora then Lighting.ClockTime = lerp(base.Hora, hora, k) % 24 end
		cc.Brightness = (alvo.Brilho or 0) * k + (self.AmbBrilho or 0)
		cc.Contrast = (alvo.Contraste or 0) * k
		cc.Saturation = (alvo.Saturacao or 0) * k
		cc.TintColor = BRANCO:Lerp(self.AmbTint or alvo.Tint or BRANCO, k)
		if alvo.Exposicao then Lighting.ExposureCompensation = lerp(base.Exposicao, alvo.Exposicao, k) end
		if ceu and base.Estrelas and alvo.Estrelas then ceu.StarCount = math.floor(lerp(base.Estrelas, alvo.Estrelas, k)) end
		if atm and base.Atm and alvo.Neblina then
			local n, b = alvo.Neblina, base.Atm
			atm.Density = lerp(b.Density, n.Density or b.Density, k)
			atm.Color = b.Color:Lerp(n.Color or b.Color, k)
			atm.Decay = b.Decay:Lerp(n.Decay or b.Decay, k)
			atm.Haze = lerp(b.Haze, n.Haze or b.Haze, k)
			atm.Glare = lerp(b.Glare, n.Glare or b.Glare, k)
		end
	end)
	table.insert(self.AoFim, function()
		Lighting.ClockTime = base.Hora
		Lighting.ExposureCompensation = base.Exposicao
		if ceu and base.Estrelas then ceu.StarCount = base.Estrelas end
		if atm and base.Atm then
			for prop, v in pairs(base.Atm) do atm[prop] = v end
		end
		cc:Destroy()
	end)
end

-- caixa de partículas do tamanho do CAMPO (altura acima do gramado)
function Sessao:EmissorCampo(C, altura, props, escala, alturaCaixa)
	local esc = escala or 1.1
	local p = self:Parte({
		Transparency = 1,
		Size = Vector3.new(C.Comp * esc, alturaCaixa or 1, C.Larg * esc),
		CFrame = C.CF + Vector3.new(0, altura, 0),
	})
	return self:Emissor(p, props), p
end

-- caixa de partículas que ACOMPANHA a câmera (densidade onde você está olhando)
function Sessao:EmissorCamera(C, altura, raio, props)
	local p = self:Parte({ Transparency = 1, Size = Vector3.new(raio * 2, 1, raio * 2) })
	local e = self:Emissor(p, props)
	self:Cada(function()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local frente = plano(cam.CFrame.LookVector)
		local alvo = cam.CFrame.Position + frente * raio * 0.55
		p.CFrame = CFrame.new(alvo.X, C.ChaoY + altura, alvo.Z)
	end)
	return e, p
end

-- imagem deitada no chão que brilha (anel de onda, marca de impacto)
function Sessao:Chao(pos, raio, imagem, cor, transp, giro)
	local p = self:Parte({
		Transparency = 1,
		Size = Vector3.new(raio * 2, 0.2, raio * 2),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, giro or 0, 0),
	})
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Top
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	sg.CanvasSize = Vector2.new(256, 256)
	sg.Parent = p
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.Image = imagem
	im.ImageColor3 = cor
	im.ImageTransparency = transp or 0
	im.Parent = sg
	return p, im
end

-- onda: anel no chão que abre do ponto até `raio` em `tempo`
function Sessao:OndaChao(pos, cor, raio, tempo, transp)
	local p, im = self:Chao(pos + Vector3.new(0, 0.25, 0), 2, TEX.Anel, cor, transp or 0)
	self:Tween(p, tempo, { Size = Vector3.new(raio * 2, 0.2, raio * 2) }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	self:Tween(im, tempo, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(p, tempo + 0.05)
end

-- BillboardGui (sempre de frente pra câmera) com camadas: planeta, núcleo, nebulosa
-- camadas = { { Imagem=, Cor=, Transp=, Escala=, EscalaY=, Rot=, Solido=true } }
function Sessao:Placa(pos, studs, camadas)
	local a = self:Ancora(pos)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(studs, studs)
	bb.LightInfluence = 0
	bb.MaxDistance = 100000
	bb.ClipsDescendants = false
	bb.Adornee = a
	bb.Parent = a
	local lista = {}
	for i, c in ipairs(camadas) do
		local g
		if c.Solido then
			g = Instance.new("Frame")
			g.BackgroundColor3 = c.Cor or BRANCO
			g.BackgroundTransparency = c.Transp or 0
			g.BorderSizePixel = 0
			local canto = Instance.new("UICorner")
			canto.CornerRadius = UDim.new(0.5, 0)
			canto.Parent = g
		else
			g = Instance.new("ImageLabel")
			g.BackgroundTransparency = 1
			g.Image = c.Imagem or TEX.Brilho
			g.ImageColor3 = c.Cor or BRANCO
			g.ImageTransparency = c.Transp or 0
		end
		g.AnchorPoint = Vector2.new(0.5, 0.5)
		g.Position = UDim2.fromScale(0.5, 0.5)
		g.Size = UDim2.fromScale(c.Escala or 1, c.EscalaY or c.Escala or 1)
		g.Rotation = c.Rot or 0
		g.ZIndex = i
		g.Parent = bb
		lista[i] = g
	end
	return { Ancora = a, Gui = bb, Camadas = lista }
end

-- parede de energia em anel (segmentos), raio/altura mudam a cada quadro
function Sessao:Anel(centro, n, props)
	local partes = {}
	for i = 1, n do partes[i] = self:Parte(props) end
	local anel = {}
	function anel.Atualizar(raio, altura, espessura, transp, cor)
		raio = math.max(raio, 1)
		local seg = 2 * math.pi * raio / n * 1.06
		for i, p in ipairs(partes) do
			local ang = (i / n) * math.pi * 2
			local pos = centro + Vector3.new(math.cos(ang) * raio, altura / 2, math.sin(ang) * raio)
			p.Size = Vector3.new(seg, altura, espessura)
			p.CFrame = CFrame.lookAt(pos, Vector3.new(centro.X, pos.Y, centro.Z))
			p.Transparency = transp
			if cor then p.Color = cor end
		end
	end
	function anel.Destruir()
		for _, p in ipairs(partes) do p:Destroy() end
	end
	return anel
end

-- raio elétrico em zigue-zague com galhos (miolo branco + halo da cor)
function Sessao:Raio(de, ate, cor, largura, galhos, vida)
	local dir = ate - de
	local dist = dir.Magnitude
	if dist < 1 then return end
	local p1 = dir:Cross(Vector3.xAxis)
	if p1.Magnitude < 0.01 then p1 = dir:Cross(Vector3.zAxis) end
	p1 = p1.Unit
	local p2 = dir:Cross(p1).Unit
	local n = math.clamp(math.floor(dist / 16), 5, 24)
	local amp = dist * 0.05
	local pontos = { de }
	for i = 1, n - 1 do
		table.insert(pontos, de + dir * (i / n) + p1 * rnd(-amp, amp) + p2 * rnd(-amp, amp))
	end
	table.insert(pontos, ate)
	for i = 1, #pontos - 1 do
		local a, b = pontos[i], pontos[i + 1]
		local cf = CFrame.lookAt((a + b) / 2, b)
		local len = (b - a).Magnitude
		local miolo = self:Parte({ Color = BRANCO, Size = Vector3.new(largura, largura, len + largura * 0.6), CFrame = cf })
		local halo = self:Parte({ Color = cor, Transparency = 0.55, Size = Vector3.new(largura * 3.2, largura * 3.2, len + largura), CFrame = cf })
		self:Tween(miolo, vida, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		self:Tween(halo, vida, { Transparency = 1 })
		Debris:AddItem(miolo, vida + 0.05)
		Debris:AddItem(halo, vida + 0.05)
		if galhos > 0 and i > 1 and rng:NextNumber() < 0.3 then
			local desvio = (p1 * rnd(-1, 1) + p2 * rnd(-1, 1) + dir.Unit * 0.8).Unit
			self:Raio(a, a + desvio * dist * rnd(0.12, 0.28), cor, largura * 0.5, galhos - 1, vida * 0.8)
		end
	end
end

-- objetos que voam (meteoros, foguetes...) atualizados num laço só
function Sessao:Voadores()
	local lista = {}
	self:Cada(function(_, _, dt)
		for i = #lista, 1, -1 do
			local v = lista[i]
			v.T += dt
			local k = math.min(v.T / v.Dur, 1)
			local pos = v.De:Lerp(v.Ate, k)
			if v.Curva then pos += v.Curva(k) end
			v.Parte.CFrame = CFrame.lookAt(pos, pos + (v.Ate - v.De).Unit)
			if k >= 1 then
				table.remove(lista, i)
				v.Parte:Destroy()
				if v.AoChegar then task.spawn(v.AoChegar, v.Ate) end
			end
		end
	end)
	return function(parte, de, ate, dur, aoChegar, curva)
		table.insert(lista, { Parte = parte, De = de, Ate = ate, Dur = dur, T = 0, AoChegar = aoChegar, Curva = curva })
	end
end

-- cabeça brilhante + rastro (Trail) — meteoro, estrela cadente, foguete
function Sessao:Cometa(cor, tamanho, larguraRastro, vidaRastro)
	local p = self:Parte({ Shape = Enum.PartType.Ball, Size = Vector3.one * tamanho, Color = cor:Lerp(BRANCO, 0.6) })
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, larguraRastro / 2, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -larguraRastro / 2, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Lifetime = vidaRastro
	tr.FaceCamera = true
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.Color = cseq({ { 0, BRANCO }, { 0.25, cor }, { 1, cor } })
	tr.Transparency = seq({ { 0, 0 }, { 0.6, 0.6 }, { 1, 1 } })
	tr.WidthScale = seq({ { 0, 1 }, { 1, 0.1 } })
	tr.Parent = p
	self:Emissor(p, {
		Texture = TEX.Faisca, Color = ColorSequence.new(cor), Rate = 60, Lifetime = NumberRange.new(0.4, 0.8),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Size = seq({ { 0, tamanho * 0.7 }, { 1, 0 } }),
	})
	return p
end

-- ============================================================
-- CAMPO: medido pelos dois gols (GolAzul / GolAmarelo)
-- ============================================================
local function medirCampo(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ignorar, pl.Character) end
	end
	params.FilterDescendantsInstances = ignorar
	params.RespectCanCollide = true
	-- o raio sai do MEIO da bola (não acerta ela mesma)
	local hit = workspace:Raycast(pos, Vector3.new(0, -60, 0), params)
	local chaoY = hit and hit.Position.Y or (pos.Y - 1)

	local C = {}
	local a, b = workspace:FindFirstChild("GolAzul"), workspace:FindFirstChild("GolAmarelo")
	if a and b and a:IsA("BasePart") and b:IsA("BasePart") then
		local pa = Vector3.new(a.Position.X, chaoY, a.Position.Z)
		local pb = Vector3.new(b.Position.X, chaoY, b.Position.Z)
		C.Centro = (pa + pb) / 2
		C.Comp = (pb - pa).Magnitude
		C.Eixo = (pb - pa).Unit
		C.Larg = C.Comp * 0.52
		C.Gol = ((pa - pos).Magnitude < (pb - pos).Magnitude) and pa or pb
	else
		C.Centro = Vector3.new(pos.X, chaoY, pos.Z)
		C.Comp, C.Larg, C.Eixo = 420, 220, Vector3.xAxis
		C.Gol = C.Centro - C.Eixo * 200
	end
	C.ChaoY = chaoY
	C.Bola = pos
	C.Lado = C.Eixo:Cross(UP).Unit
	C.Dentro = plano(C.Centro - C.Gol) -- do gol pro meio do campo
	C.CF = CFrame.fromMatrix(C.Centro, C.Eixo, UP)
	function C.Ponto(fx, fz, y)
		return C.CF * Vector3.new(fx * C.Comp, y or 0, fz * C.Larg)
	end
	function C.Aleatorio(y, margem)
		local m = margem or 0.5
		return C.Ponto(rnd(-m, m), rnd(-m, m), y)
	end
	function C.Dentro01(p) -- dentro do retângulo do campo?
		local l = C.CF:PointToObjectSpace(p)
		return math.abs(l.X) <= C.Comp * 0.52 and math.abs(l.Z) <= C.Larg * 0.55
	end
	function C.PertoDaCamera(raio, y)
		local cam = workspace.CurrentCamera
		local base = cam and (cam.CFrame.Position + plano(cam.CFrame.LookVector) * raio * 0.5) or C.Centro
		local ang, d = rnd(0, math.pi * 2), raio * math.sqrt(rng:NextNumber())
		return Vector3.new(base.X + math.cos(ang) * d, C.ChaoY + (y or 0), base.Z + math.sin(ang) * d)
	end
	return C
end

-- estouro de abertura NA BOLA (todo efeito começa no gol)
local function aberturaNaBola(s, C, cor, forca)
	forca = forca or 1
	s:Flash(cor, 0.45 * forca, 0.5)
	s:Estouro(C.Bola, {
		Texture = TEX.Brilho, Color = cseq({ { 0, BRANCO }, { 0.3, cor }, { 1, cor } }),
		Speed = NumberRange.new(30 * forca, 70 * forca), Lifetime = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(180, 180),
		Drag = 3, Size = seq({ { 0, 3 * forca }, { 1, 0 } }),
	}, math.floor(90 * forca))
	s:OndaChao(Vector3.new(C.Bola.X, C.ChaoY, C.Bola.Z), cor, 70 * forca, 0.8)
	s:Luz(C.Bola, cor, 60, 8, 0.8)
end

local Estilos = {}

-- ============================================================
-- 1. FOGOS DE ARTIFÍCIO (Raro) — anoitece; vulcões de faísca nas traves; foguetes
-- saem de TODA a volta do campo, cada vez mais, em 5 formatos (peônia, anel,
-- salgueiro, crisântemo, estrobo); final em barragem em cima do gol.
-- ============================================================
Estilos.Fogos = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 20.6, Brilho = -0.1, Contraste = 0.12, Saturacao = 0.2, Estrelas = 4000, Entrada = 1.0, Saida = 1.3 })
	aberturaNaBola(s, C, cor, 1)
	for _, lado in ipairs({ -1, 1 }) do
		local a = s:Ancora(C.Gol + C.Lado * (lado * 13) + Vector3.new(0, 0.5, 0))
		local e = s:Emissor(a, {
			Texture = TEX.Faisca, Color = cseq({ { 0, Color3.fromRGB(255, 250, 220) }, { 0.5, Color3.fromRGB(255, 200, 80) }, { 1, Color3.fromRGB(255, 90, 30) } }),
			Rate = 260, Lifetime = NumberRange.new(1.3, 1.9), Speed = NumberRange.new(38, 56), SpreadAngle = Vector2.new(10, 10),
			EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -40, 0), Drag = 0.5, Size = seq({ { 0, 2.6 }, { 1, 0.3 } }),
		})
		s:Em(T * 0.88, function() e.Enabled = false end)
	end
	local voar = s:Voadores()
	local TIPOS = { "Peonia", "Anel", "Salgueiro", "Crisantemo", "Estrobo" }
	local function estourar(alto, c, tipo, esc)
		s:Luz(alto, c, 60, 10 * esc, 1.3)
		if tipo == "Peonia" then
			-- LightEmission menor: com 1 + bloom as partículas somavam e ficava tudo BRANCO
			s:Estouro(alto, { LightEmission = 0.55, Color = cseq({ { 0, c:Lerp(BRANCO, 0.5) }, { 0.1, c }, { 1, c } }), Speed = NumberRange.new(55 * esc, 78 * esc),
				Lifetime = NumberRange.new(1.3, 1.9), SpreadAngle = Vector2.new(180, 180), Drag = 1.7, Acceleration = Vector3.new(0, -14, 0),
				Size = seq({ { 0, 3 * esc }, { 0.7, 1.8 * esc }, { 1, 0 } }) }, 220)
		elseif tipo == "Salgueiro" then
			s:Estouro(alto, { Texture = TEX.Faisca, Color = cseq({ { 0, Color3.fromRGB(255, 240, 200) }, { 1, Color3.fromRGB(255, 160, 50) } }),
				Speed = NumberRange.new(40 * esc, 55 * esc), Lifetime = NumberRange.new(2.6, 3.4), SpreadAngle = Vector2.new(180, 180), Drag = 1.1,
				Acceleration = Vector3.new(0, -22, 0), Size = seq({ { 0, 2.4 * esc }, { 1, 0.3 } }) }, 260)
		elseif tipo == "Crisantemo" then
			local h = c:ToHSV()
			local c2 = Color3.fromHSV((h + 0.5) % 1, 0.6, 1)
			s:Estouro(alto, { LightEmission = 0.55, Color = ColorSequence.new(c, c2), Speed = NumberRange.new(50 * esc, 70 * esc), Lifetime = NumberRange.new(1.4, 1.8),
				SpreadAngle = Vector2.new(180, 180), Drag = 1.5, Acceleration = Vector3.new(0, -10, 0), Size = seq({ { 0, 2.6 * esc }, { 1, 0.2 } }) }, 200)
			s:Em(1.2, function()
				s:Estouro(alto + Vector3.new(0, -14, 0), { Texture = TEX.Estrela, Color = ColorSequence.new(BRANCO), Speed = NumberRange.new(30, 60),
					Lifetime = NumberRange.new(0.15, 0.35), SpreadAngle = Vector2.new(180, 180), Size = seq({ { 0, 4 }, { 1, 0 } }) }, 120)
			end)
		elseif tipo == "Anel" then
			local base = CFrame.new(alto) * CFrame.Angles(rnd(-0.7, 0.7), rnd(0, math.pi), rnd(-0.7, 0.7))
			for i = 1, 30 do
				local ang = i / 30 * math.pi * 2
				local bolinha = s:Parte({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2 * esc, Color = c, CFrame = CFrame.new(alto) })
				local fim = (base * CFrame.new(math.cos(ang) * 58 * esc, 0, math.sin(ang) * 58 * esc)).Position
				s:Tween(bolinha, 1.5, { CFrame = CFrame.new(fim - Vector3.new(0, 10, 0)), Transparency = 1, Size = Vector3.one * 0.5 })
				Debris:AddItem(bolinha, 1.6)
			end
			s:Estouro(alto, { Color = ColorSequence.new(BRANCO, c), Speed = NumberRange.new(8, 18), Lifetime = NumberRange.new(0.5, 0.9),
				SpreadAngle = Vector2.new(180, 180), Size = seq({ { 0, 4 }, { 1, 0 } }) }, 60)
		else -- Estrobo
			for i = 1, 8 do
				s:Em(0.25 + i * 0.1, function()
					s:Estouro(alto + Vector3.new(rnd(-35, 35), rnd(-25, 20), rnd(-35, 35)), { Texture = TEX.Estrela, Color = ColorSequence.new(BRANCO),
						Speed = NumberRange.new(0, 3), Lifetime = NumberRange.new(0.08, 0.2), SpreadAngle = Vector2.new(180, 180), Size = seq({ { 0, 6 }, { 1, 0 } }) }, 18)
				end)
			end
			s:Estouro(alto, { Texture = TEX.Faisca, Color = ColorSequence.new(c), Speed = NumberRange.new(35, 55), Lifetime = NumberRange.new(0.6, 1),
				SpreadAngle = Vector2.new(180, 180), Drag = 2, Size = seq({ { 0, 2 }, { 1, 0 } }) }, 120)
		end
	end
	local function lancar(ini, alto, c, tipo, esc)
		local fog = s:Cometa(c, 1.4 * esc, 1.2 * esc, 0.5)
		fog.CFrame = CFrame.new(ini)
		voar(fog, ini, alto, rnd(0.9, 1.3), function() estourar(alto, c, tipo, esc) end)
	end
	local function pontoBorda()
		if rng:NextNumber() < 0.6 then
			return C.Ponto(rnd(-0.55, 0.55), (rng:NextNumber() < 0.5 and -1 or 1) * 0.62, 0)
		end
		return C.Ponto((rng:NextNumber() < 0.5 and -1 or 1) * 0.56, rnd(-0.6, 0.6), 0)
	end
	-- 1) salva no gol
	for i = 1, 6 do
		s:Em(0.05 + i * 0.12, function()
			local ini = C.Gol + C.Lado * rnd(-22, 22)
			lancar(ini, ini + C.Dentro * rnd(15, 45) + Vector3.new(0, rnd(60, 95), 0), Color3.fromHSV(rng:NextNumber(), 0.65, 1), "Peonia", 0.9)
		end)
	end
	-- 2) o campo inteiro, cada vez mais denso
	local t = 0.9
	while t < T * 0.72 do
		s:Em(t, function()
			local ini = pontoBorda()
			local alto = ini + (C.Centro - ini) * rnd(0.05, 0.3) + Vector3.new(0, rnd(95, 175), 0)
			lancar(ini, alto, Color3.fromHSV(rng:NextNumber(), rnd(0.5, 0.8), 1), TIPOS[rng:NextInteger(1, #TIPOS)], rnd(1.1, 1.6))
		end)
		t += lerp(0.42, 0.11, t / T)
	end
	-- 3) final: barragem em cima do gol
	for k = 1, 16 do
		s:Em(T * 0.72 + k * 0.07, function()
			local ini = C.Gol + C.Lado * rnd(-70, 70) + C.Dentro * rnd(0, 60)
			lancar(ini, ini + Vector3.new(0, rnd(120, 200), 0), Color3.fromHSV((k / 16 + 0.1) % 1, 0.6, 1), k % 3 == 0 and "Salgueiro" or "Peonia", 1.8)
		end)
	end
	s:Em(T * 0.72 + 2.3, function() s:Flash(Color3.fromRGB(255, 230, 180), 0.35, 0.9) end)
end

-- ============================================================
-- 2. CONFETE (Comum) — canhões no gol e nos 4 cantos, chuva de confete no campo
-- inteiro (5 cores, girando), serpentinas e balões subindo da arquibancada.
-- ============================================================
Estilos.Confete = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Brilho = 0.06, Saturacao = 0.35, Contraste = 0.08, Entrada = 0.4, Saida = 1 })
	aberturaNaBola(s, C, cor, 0.9)
	local CORES = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 215, 70), Color3.fromRGB(80, 190, 255), Color3.fromRGB(110, 235, 130), Color3.fromRGB(200, 120, 255) }
	local function props(c, extra)
		local p = {
			Texture = TEX.Quadrado, Color = ColorSequence.new(c), LightEmission = 0.15, LightInfluence = 0.4,
			Lifetime = NumberRange.new(5, 7), Speed = NumberRange.new(3, 8), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-280, 280),
			Size = seq({ { 0, 0.55 }, { 1, 0.45 } }), Drag = 0.4, Acceleration = Vector3.new(1.5, -7, 0.8), Squash = seq({ { 0, 0.6 }, { 0.5, -0.6 }, { 1, 0.6 } }),
		}
		for k, v in pairs(extra or {}) do p[k] = v end
		return p
	end
	-- canhões: no gol (apontando pro campo) e nos cantos (apontando pro meio)
	local canhoes = {}
	for _, lado in ipairs({ -1, 1 }) do
		local pos = C.Gol + C.Lado * (lado * 14)
		table.insert(canhoes, CFrame.lookAt(pos, pos + C.Dentro * 0.6 + UP))
	end
	for _, fx in ipairs({ -0.5, 0.5 }) do
		for _, fz in ipairs({ -0.5, 0.5 }) do
			local pos = C.Ponto(fx, fz, 0)
			table.insert(canhoes, CFrame.lookAt(pos, pos + (C.Centro - pos).Unit * 0.7 + UP))
		end
	end
	for i, cf in ipairs(canhoes) do
		local a = s:Ancora(cf)
		local atraso = i <= 2 and 0 or 0.35 + (i - 3) * 0.15
		for j, c in ipairs(CORES) do
			local e = s:Emissor(a, props(c, { EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(16, 16), Speed = NumberRange.new(55, 95), Drag = 1.1 }))
			s:Em(atraso, function()
				e:Emit(i <= 2 and 160 or 120)
				e.Rate = i <= 2 and 70 or 40
			end)
			s:Em(atraso + T * 0.32, function() e.Rate = 0 end)
		end
		-- serpentinas (fitas compridas)
		local f = s:Emissor(a, props(CORES[(i % 5) + 1], { EmissionDirection = Enum.NormalId.Front, SpreadAngle = Vector2.new(20, 20),
			Speed = NumberRange.new(50, 80), Drag = 1, Size = seq({ { 0, 0.35 }, { 1, 0.3 } }), Squash = seq({ { 0, 2.5 }, { 1, 2.5 } }) }))
		s:Em(atraso, function() f:Emit(40) end)
		s:Em(atraso, function() s:Luz(cf.Position + Vector3.new(0, 4, 0), CORES[(i % 5) + 1], 40, 5, 0.6) end)
	end
	-- chuva no campo inteiro + camada perto da câmera
	local chuvas = {}
	for _, c in ipairs(CORES) do
		table.insert(chuvas, (s:EmissorCampo(C, 90, props(c, { EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(30, 30) }))))
		table.insert(chuvas, (s:EmissorCamera(C, 55, 70, props(c, { EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(30, 30) }))))
	end
	s:Cada(function(t, u)
		local k = janela(u, 0.08, 0.3) * (1 - janela(u, 0.7, 0.8))
		for i, e in ipairs(chuvas) do e.Rate = (i % 2 == 1 and 170 or 45) * k end
	end)
	-- balões subindo das bordas
	local voar = s:Voadores()
	for i = 1, 46 do
		s:Em(T * 0.15 + rnd(0, T * 0.45), function()
			local ini = rng:NextNumber() < 0.5 and C.PertoDaCamera(90, -2) or C.Ponto(rnd(-0.5, 0.5), (rng:NextNumber() < 0.5 and -1 or 1) * rnd(0.45, 0.6), -2)
			local b = s:Parte({ Shape = Enum.PartType.Ball, Size = Vector3.new(3.4, 4, 3.4), Material = Enum.Material.SmoothPlastic,
				Color = CORES[rng:NextInteger(1, #CORES)], Reflectance = 0.15, CFrame = CFrame.new(ini) })
			local fase = rnd(0, 6)
			voar(b, ini, ini + Vector3.new(rnd(-12, 12), rnd(70, 110), rnd(-12, 12)), rnd(5, 7), nil, function(k)
				return Vector3.new(math.sin(k * 9 + fase) * 2, 0, math.cos(k * 7 + fase) * 2)
			end)
		end)
	end
end

-- ============================================================
-- 3. FLASH COLORIDO (Comum) — show de luzes: anoitece, 12 holofotes coloridos em
-- volta do campo varrendo o céu, lasers cruzando o gramado, o chão pulsa em
-- ondas de cor no ritmo e no fim todos os holofotes miram em cima do gol.
-- ============================================================
Estilos.Flash = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 19.6, Brilho = -0.18, Contraste = 0.2, Saturacao = 0.4, Entrada = 0.6, Saida = 1.2 })
	aberturaNaBola(s, C, cor, 1)
	local holofotes = {}
	for i = 1, 12 do
		local fx, fz
		if i <= 8 then
			fx, fz = ((i - 1) % 4) / 3 - 0.5, (i <= 4 and -1 or 1) * 0.6
		else
			fx, fz = (i <= 10 and -1 or 1) * 0.56, (i % 2 == 0) and -0.25 or 0.25
		end
		local base = s:Ancora(C.Ponto(fx, fz, 2))
		local ponta = s:Ancora(C.Ponto(fx, fz, 250))
		local a0 = Instance.new("Attachment")
		a0.Parent = base
		local a1 = Instance.new("Attachment")
		a1.Parent = ponta
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.Width0 = 4
		bm.Width1 = 34
		bm.FaceCamera = true
		bm.LightEmission = 1
		bm.LightInfluence = 0
		bm.Segments = 1
		bm.Transparency = seq({ { 0, 0.1 }, { 1, 0.85 } })
		bm.Parent = base
		table.insert(holofotes, { Beam = bm, Base = base, Ponta = ponta, Fase = i * 0.7, Pos = base.Position })
	end
	-- lasers rasantes
	local lasers = {}
	for i = 1, 8 do
		local l = s:Parte({ Size = Vector3.new(0.6, 0.6, C.Comp * 1.15), Transparency = 0.25 })
		table.insert(lasers, { Parte = l, Fase = i * 0.8, Altura = 6 + (i % 4) * 5 })
	end
	local alvoFinal = C.Gol + C.Dentro * 30 + Vector3.new(0, 140, 0)
	local ultimaBatida = -1
	s:Cada(function(t, u)
		local hue = (t * 0.22) % 1
		local converge = suave(janela(u, 0.78, 0.86))
		local apaga = janela(u, 0.92, 1)
		for i, h in ipairs(holofotes) do
			local c = Color3.fromHSV((hue + i / 12) % 1, 0.75, 1)
			local varre = h.Pos + Vector3.new(math.sin(t * 0.9 + h.Fase) * 160, 260, math.cos(t * 0.7 + h.Fase) * 160)
			h.Ponta.CFrame = CFrame.new(varre:Lerp(alvoFinal, converge))
			h.Beam.Color = ColorSequence.new(c)
			h.Beam.Transparency = seq({ { 0, 0.1 + 0.9 * apaga }, { 1, 0.85 + 0.15 * apaga } })
		end
		for i, l in ipairs(lasers) do
			local ang = t * (0.6 + i * 0.07) + l.Fase
			local centro = C.Centro + Vector3.new(0, l.Altura, 0)
			l.Parte.CFrame = CFrame.new(centro) * CFrame.Angles(0, ang, 0)
			l.Parte.Color = Color3.fromHSV((hue + i / 8 + 0.5) % 1, 0.8, 1)
			l.Parte.Transparency = 0.25 + 0.75 * math.max(converge, apaga)
		end
		s.AmbTint = Color3.fromHSV(hue, 0.3, 1)
		-- batida: onda de cor no chão (ora no gol, ora no meio, ora num canto)
		local batida = math.floor(t / 0.55)
		if batida ~= ultimaBatida and u < 0.8 then
			ultimaBatida = batida
			local origens = { C.Gol, C.Centro, C.Ponto(rnd(-0.5, 0.5), rnd(-0.5, 0.5), 0) }
			local o = origens[(batida % 3) + 1]
			s:OndaChao(Vector3.new(o.X, C.ChaoY, o.Z), Color3.fromHSV((hue + 0.3) % 1, 0.7, 1), C.Comp * 0.55, 1.1, 0.1)
			s.AmbBrilho = 0.12
			s:Em(0.08, function() s.AmbBrilho = 0 end)
		end
	end)
	s:Em(T * 0.86, function()
		s:Flash(BRANCO, 0.9, 0.9)
		s:Estouro(alvoFinal, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 1, cor } }), Speed = NumberRange.new(60, 120),
			Lifetime = NumberRange.new(0.8, 1.4), SpreadAngle = Vector2.new(180, 180), Drag = 2, Size = seq({ { 0, 8 }, { 1, 0 } }) }, 220)
	end)
end

-- ============================================================
-- 4. CHUVA DE ESTRELAS (Raro) — vira noite estrelada; chuva de meteoros cruzando o
-- céu e caindo pelo campo todo (cada vez mais), e uma estrela cadente GIGANTE
-- cai no gol no final.
-- ============================================================
Estilos.Estrelas = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 23.5, Brilho = -0.05, Saturacao = 0.15, Tint = Color3.fromRGB(215, 225, 255), Estrelas = 6000, Entrada = 1.1, Saida = 1.3 })
	aberturaNaBola(s, C, cor, 0.9)
	local brilho = s:EmissorCampo(C, 60, { Texture = TEX.Estrela, Color = ColorSequence.new(cor:Lerp(BRANCO, 0.4)), Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(0, 1), Size = seq({ { 0, 0 }, { 0.5, 1.6 }, { 1, 0 } }) }, 1.1, 100)
	local perto = s:EmissorCamera(C, 25, 80, { Texture = TEX.Estrela, Color = ColorSequence.new(BRANCO), Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(0, 1), Size = seq({ { 0, 0 }, { 0.5, 0.9 }, { 1, 0 } }) })
	local voar = s:Voadores()
	local radiante = (C.Eixo * 0.55 + C.Lado * 0.35 - UP * 0.75).Unit
	local function meteoro(alvo, tam)
		local c = Color3.fromHSV(((cor:ToHSV()) + rnd(-0.08, 0.08)) % 1, rnd(0.15, 0.45), 1)
		local m = s:Cometa(c, tam, tam * 1.3, 0.7)
		local ini = alvo - radiante * rnd(280, 380)
		m.CFrame = CFrame.new(ini)
		voar(m, ini, alvo, rnd(1.1, 1.5), function(p)
			s:Estouro(p, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 1, c } }), Speed = NumberRange.new(10, 30),
				Lifetime = NumberRange.new(0.5, 1), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -25, 0), Size = seq({ { 0, tam * 1.4 }, { 1, 0 } }) }, 30)
			s:OndaChao(Vector3.new(p.X, C.ChaoY, p.Z), c, 12 + tam * 4, 0.6)
			s:Luz(p + Vector3.new(0, 3, 0), c, 30, 6, 0.6)
		end)
	end
	s:Cada(function(_, u)
		local k = janela(u, 0.05, 0.25) * (1 - janela(u, 0.85, 0.95))
		brilho.Rate = 400 * k
		perto.Rate = 90 * k
	end)
	-- chuva: começa no gol e toma o campo inteiro, acelerando
	local t = 0.3
	while t < T * 0.68 do
		s:Em(t, function()
			local alvo
			local r = rng:NextNumber()
			if r < 0.3 then alvo = C.PertoDaCamera(110, 0) elseif r < 0.45 then alvo = C.Gol + C.Dentro * rnd(10, 80) + C.Lado * rnd(-60, 60) else alvo = C.Aleatorio(0, 0.5) end
			meteoro(alvo, rnd(1.6, 3.2))
		end)
		t += lerp(0.28, 0.06, t / T)
	end
	-- estrela cadente gigante no gol
	s:Em(T * 0.7, function()
		local alvo = C.Gol + C.Dentro * 6
		local m = s:Cometa(cor, 14, 16, 1.1)
		local ini = alvo - radiante * 420
		m.CFrame = CFrame.new(ini)
		voar(m, ini, alvo, 1.6, function(p)
			s:Flash(cor, 1.1, 1.2)
			s:Estouro(p, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 0.4, cor }, { 1, Color3.fromRGB(150, 120, 255) } }),
				Speed = NumberRange.new(40, 110), Lifetime = NumberRange.new(1.2, 2.2), SpreadAngle = Vector2.new(180, 180), Drag = 1.2,
				Acceleration = Vector3.new(0, -12, 0), Size = seq({ { 0, 5 }, { 1, 0 } }) }, 360)
			s:OndaChao(Vector3.new(p.X, C.ChaoY, p.Z), cor, C.Comp * 0.6, 1.8)
			s:OndaChao(Vector3.new(p.X, C.ChaoY, p.Z), BRANCO, C.Comp * 0.35, 1.2)
			s:Luz(p + Vector3.new(0, 6, 0), cor, 60, 14, 2)
		end)
	end)
end

-- ============================================================
-- 5. EXPLOSÃO DE FOGO (Raro) — bola de fogo no gol e uma ONDA DE FOGO que
-- atravessa o campo inteiro até o outro gol, deixando o gramado em chamas;
-- brasas subindo de todo lado, céu de pôr do sol alaranjado.
-- ============================================================
Estilos.Fogo = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 18.25, Brilho = -0.04, Contraste = 0.22, Saturacao = 0.25, Tint = Color3.fromRGB(255, 205, 170), Entrada = 0.7, Saida = 1.4 })
	local FOGO = cseq({ { 0, Color3.fromRGB(255, 240, 160) }, { 0.35, Color3.fromRGB(255, 140, 40) }, { 1, Color3.fromRGB(150, 30, 10) } })
	-- bola de fogo no gol
	s:Flash(Color3.fromRGB(255, 150, 60), 0.8, 0.7)
	s:Estouro(C.Bola, { Texture = TEX.Fogo, Color = FOGO, Speed = NumberRange.new(30, 70), Lifetime = NumberRange.new(0.8, 1.4),
		SpreadAngle = Vector2.new(180, 180), Drag = 2.2, LightEmission = 0.8, Size = seq({ { 0, 22 }, { 1, 8 } }),
		Transparency = seq({ { 0, 0.05 }, { 0.7, 0.4 }, { 1, 1 } }), RotSpeed = NumberRange.new(-90, 90), Rotation = NumberRange.new(0, 360) }, 140)
	s:Estouro(C.Bola, { Texture = TEX.Faisca, Color = FOGO, Speed = NumberRange.new(60, 120), Lifetime = NumberRange.new(1, 1.8),
		SpreadAngle = Vector2.new(180, 180), Drag = 1.2, Acceleration = Vector3.new(0, -30, 0), Size = seq({ { 0, 1.6 }, { 1, 0 } }) }, 200)
	s:OndaChao(Vector3.new(C.Bola.X, C.ChaoY, C.Bola.Z), Color3.fromRGB(255, 150, 50), 160, 1.1)
	s:Luz(C.Bola, Color3.fromRGB(255, 150, 60), 60, 14, 1.5)
	-- frente de fogo: atravessa o campo
	local dir = C.Dentro
	local largura = C.Larg * 1.05
	local frente = s:Parte({ Transparency = 1, Size = Vector3.new(6, 2, largura) })
	local eFrente = s:Emissor(frente, { Texture = TEX.Fogo, Color = FOGO, Rate = 0, Lifetime = NumberRange.new(0.7, 1.1), Speed = NumberRange.new(18, 32),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(15, 15), LightEmission = 0.8, Size = seq({ { 0, 14 }, { 0.6, 18 }, { 1, 6 } }),
		Transparency = seq({ { 0, 0.15 }, { 0.75, 0.45 }, { 1, 1 } }), RotSpeed = NumberRange.new(-60, 60), Rotation = NumberRange.new(0, 360) })
	local luzFrente = Instance.new("PointLight")
	luzFrente.Range = 60
	luzFrente.Brightness = 8
	luzFrente.Color = Color3.fromRGB(255, 140, 50)
	luzFrente.Parent = frente
	local linhas, proxLinha = {}, 0
	local DUR = T * 0.55
	s:Cada(function(t, u)
		local k = math.clamp((t - 0.4) / DUR, 0, 1)
		local d = k * C.Comp
		frente.CFrame = CFrame.fromMatrix(C.Gol + dir * d + Vector3.new(0, 1, 0), dir, UP)
		eFrente.Rate = (k > 0 and k < 1) and 520 or 0
		luzFrente.Brightness = (k > 0 and k < 1) and 8 or 0
		-- gramado em chamas atrás da frente (uma faixa a cada 45 studs)
		while proxLinha <= d and proxLinha <= C.Comp do
			local p = s:Parte({ Transparency = 1, Size = Vector3.new(30, 1, largura), CFrame = CFrame.fromMatrix(C.Gol + dir * proxLinha + Vector3.new(0, 0.6, 0), dir, UP) })
			local e = s:Emissor(p, { Texture = TEX.Fogo, Color = FOGO, Rate = 70, Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(5, 12),
				EmissionDirection = Enum.NormalId.Top, LightEmission = 0.8, Size = seq({ { 0, 6 }, { 0.5, 9 }, { 1, 3 } }),
				Transparency = seq({ { 0, 0.2 }, { 0.7, 0.5 }, { 1, 1 } }), Rotation = NumberRange.new(0, 360) })
			table.insert(linhas, e)
			proxLinha += 45
		end
		-- as chamas baixam no fim
		local apaga = 1 - janela(u, 0.75, 0.93)
		for _, e in ipairs(linhas) do e.Rate = 70 * apaga end
	end)
	-- brasas subindo do campo todo
	local brasas = s:EmissorCampo(C, 1, { Texture = TEX.Faisca, Color = cseq({ { 0, Color3.fromRGB(255, 220, 120) }, { 1, Color3.fromRGB(255, 80, 20) } }),
		Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(6, 16), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(2, 4, 0), Size = seq({ { 0, 0.7 }, { 1, 0 } }) })
	local brasasPerto = s:EmissorCamera(C, 1, 70, { Texture = TEX.Faisca, Color = cseq({ { 0, Color3.fromRGB(255, 220, 120) }, { 1, Color3.fromRGB(255, 80, 20) } }),
		Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(4, 10), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(1, 3, 0), Size = seq({ { 0, 0.5 }, { 1, 0 } }) })
	s:Cada(function(_, u)
		local k = janela(u, 0.05, 0.2) * (1 - janela(u, 0.8, 0.95))
		brasas.Rate = 350 * k
		brasasPerto.Rate = 80 * k
		-- o céu tremula com o fogo
		s.AmbBrilho = 0.04 * math.sin(os.clock() * 13) * k
	end)
end

-- ============================================================
-- 6. RELÂMPAGO (Épico) — tempestade: escurece, neblina pesada, chuva no campo
-- todo e raios caindo pelo gramado inteiro, cada vez mais; no fim um raio
-- GIGANTE cai no gol, o céu clareia e a tempestade vai embora.
-- ============================================================
Estilos.Raio = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 19.8, Brilho = -0.22, Contraste = 0.25, Saturacao = -0.35, Tint = Color3.fromRGB(205, 215, 240), Entrada = 1.2, Saida = 1.6,
		Neblina = { Density = 0.48, Color = Color3.fromRGB(90, 95, 115), Decay = Color3.fromRGB(60, 65, 80), Haze = 2.5, Glare = 0 } })
	aberturaNaBola(s, C, cor, 1)
	local CHUVA = { Texture = TEX.Gota, Color = ColorSequence.new(Color3.fromRGB(200, 215, 240)), LightEmission = 0.3, LightInfluence = 0.5,
		Lifetime = NumberRange.new(0.9, 1.2), Speed = NumberRange.new(90, 110), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(4, 4),
		Size = NumberSequence.new(1.6), Transparency = NumberSequence.new(0.35), Orientation = Enum.ParticleOrientation.VelocityParallel }
	local chuva = s:EmissorCampo(C, 100, CHUVA)
	local chuvaPerto = s:EmissorCamera(C, 70, 60, CHUVA)
	s:Cada(function(_, u)
		local k = janela(u, 0.05, 0.25) * (1 - janela(u, 0.82, 0.95))
		chuva.Rate = 900 * k
		chuvaPerto.Rate = 500 * k
	end)
	local function cair(alvo, larg, forte)
		local topo = alvo + Vector3.new(rnd(-40, 40), rnd(260, 320), rnd(-40, 40))
		s:Raio(topo, alvo, cor, larg, forte and 3 or 2, forte and 0.5 or 0.32)
		s:Flash(Color3.fromRGB(220, 230, 255), forte and 1.3 or 0.45, forte and 0.6 or 0.18)
		s:Luz(alvo + Vector3.new(0, 4, 0), cor, 60, forte and 20 or 10, forte and 1.2 or 0.5)
		s:Estouro(alvo, { Texture = TEX.Faisca, Color = cseq({ { 0, BRANCO }, { 1, cor } }), Speed = NumberRange.new(20, 50),
			Lifetime = NumberRange.new(0.3, 0.7), SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -40, 0), Size = seq({ { 0, 1.4 }, { 1, 0 } }) }, forte and 160 or 40)
		local marca, im = s:Chao(Vector3.new(alvo.X, C.ChaoY + 0.2, alvo.Z), forte and 30 or 8, TEX.Brilho, cor, 0.1)
		s:Tween(im, forte and 2.5 or 1.4, { ImageTransparency = 1, ImageColor3 = Color3.fromRGB(255, 120, 40) })
		Debris:AddItem(marca, forte and 2.6 or 1.5)
		s:OndaChao(Vector3.new(alvo.X, C.ChaoY, alvo.Z), cor, forte and C.Comp * 0.5 or 25, forte and 1.6 or 0.5)
	end
	local t = 0.6
	while t < T * 0.72 do
		s:Em(t, function()
			local alvo = rng:NextNumber() < 0.35 and C.PertoDaCamera(120, 0) or C.Aleatorio(0, 0.52)
			cair(alvo, rnd(0.8, 1.4), false)
		end)
		t += lerp(0.5, 0.12, t / T)
	end
	-- o grande: três raios em sequência no gol
	for i = 0, 2 do
		s:Em(T * 0.76 + i * 0.12, function() cair(C.Gol + C.Dentro * 8, 4 - i, i == 0) end)
	end
end

-- ============================================================
-- 7. PÉTALAS (Comum) — tarde dourada; um REDEMOINHO de pétalas cresce em volta
-- do gol e estoura, e uma ventania de cerejeira atravessa o campo inteiro.
-- ============================================================
Estilos.Petalas = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 17.3, Brilho = 0.04, Saturacao = 0.2, Tint = Color3.fromRGB(255, 225, 235), Entrada = 0.6, Saida = 1.2 })
	aberturaNaBola(s, C, cor, 0.8)
	local CORES = { cor, Color3.fromRGB(255, 215, 230), Color3.fromRGB(255, 245, 250) }
	local vento = (C.Eixo * 0.75 + C.Lado * 0.65).Unit
	local function petala(c, extra)
		local p = { Texture = TEX.Petala, Color = ColorSequence.new(c), LightEmission = 0.25, LightInfluence = 0.5,
			Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(28, 42), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
			Size = NumberSequence.new(0.7), SpreadAngle = Vector2.new(25, 15), Acceleration = Vector3.new(0, -1.5, 0), Drag = 0.2 }
		for k, v in pairs(extra or {}) do p[k] = v end
		return p
	end
	-- ventania no campo todo (a caixa olha pra direção do vento)
	local ventania = {}
	for _, c in ipairs(CORES) do
		local p = s:Parte({ Transparency = 1, Size = Vector3.new(C.Comp * 1.1, 50, C.Larg * 1.1), CFrame = CFrame.lookAt(C.Centro + Vector3.new(0, 26, 0), C.Centro + Vector3.new(0, 26, 0) + vento) })
		table.insert(ventania, s:Emissor(p, petala(c, { EmissionDirection = Enum.NormalId.Front })))
		local e2 = s:EmissorCamera(C, 18, 60, petala(c, { EmissionDirection = Enum.NormalId.Top, Speed = NumberRange.new(4, 9), Acceleration = vento * 9 + Vector3.new(0, -3, 0) }))
		table.insert(ventania, e2)
	end
	-- redemoinho no gol: 4 emissores numa hélice que sobe e abre
	local centro = C.Gol + C.Dentro * 10
	local hel = {}
	for i = 1, 4 do
		local a = s:Ancora(centro)
		hel[i] = { Ancora = a, Emissor = s:Emissor(a, petala(CORES[(i % 3) + 1], { Rate = 0, Speed = NumberRange.new(1, 3), Lifetime = NumberRange.new(1.2, 1.8), Size = NumberSequence.new(1.1) })) }
	end
	local estourou = false
	s:Cada(function(t, u)
		local k = janela(u, 0.15, 0.35) * (1 - janela(u, 0.78, 0.9))
		for i, e in ipairs(ventania) do e.Rate = (i % 2 == 1 and 260 or 80) * k end
		local kh = janela(u, 0, 0.12)
		for i, h in ipairs(hel) do
			local ang = t * 7 + i * math.pi / 2
			local alt = ((t * 18 + i * 9) % 60)
			local raio = 8 + alt * 0.55 + 6 * kh
			h.Ancora.CFrame = CFrame.new(centro + Vector3.new(math.cos(ang) * raio, alt, math.sin(ang) * raio))
			h.Emissor.Rate = (u < 0.55) and 160 * kh or 0
		end
		if u >= 0.55 and not estourou then
			estourou = true
			s:Flash(cor, 0.4, 0.6)
			for _, c in ipairs(CORES) do
				s:Estouro(centro + Vector3.new(0, 25, 0), petala(c, { Speed = NumberRange.new(40, 90), SpreadAngle = Vector2.new(180, 180), Drag = 1.5,
					Lifetime = NumberRange.new(2.5, 4), Size = NumberSequence.new(1.2) }), 160)
			end
			s:OndaChao(centro, cor, 140, 1.2)
		end
	end)
end

-- ============================================================
-- 8. BOLHAS (Comum) — uma bolha GIGANTE envolve o gol e estoura em centenas de
-- bolhas; bolhas furta-cor sobem do campo inteiro e vão estourando.
-- ============================================================
Estilos.Bolhas = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Brilho = 0.05, Saturacao = 0.15, Tint = Color3.fromRGB(225, 245, 255), Entrada = 0.5, Saida = 1 })
	aberturaNaBola(s, C, cor, 0.8)
	local bolhas = {}
	local function nova(pos, tam, vel)
		local p = s:Parte({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.2, Material = Enum.Material.ForceField, Color = cor, CFrame = CFrame.new(pos) })
		s:Tween(p, 0.35, { Size = Vector3.one * tam }, Enum.EasingStyle.Back)
		table.insert(bolhas, { Parte = p, Pos = pos, Vel = vel or Vector3.new(rnd(-1.5, 1.5), rnd(6, 12), rnd(-1.5, 1.5)), Tam = tam, Vida = rnd(3, 5.5), T = 0, Fase = rnd(0, 6) })
	end
	local function estourar(b)
		local p = b.Parte
		s:Tween(p, 0.12, { Size = Vector3.one * b.Tam * 1.35, Transparency = 1 })
		Debris:AddItem(p, 0.15)
		s:Estouro(p.Position, { Texture = TEX.Estrela, Color = ColorSequence.new(BRANCO), Speed = NumberRange.new(6, 14), Lifetime = NumberRange.new(0.2, 0.4),
			SpreadAngle = Vector2.new(180, 180), Size = seq({ { 0, b.Tam * 0.25 }, { 1, 0 } }) }, 8)
	end
	s:Cada(function(t, _, dt)
		for i = #bolhas, 1, -1 do
			local b = bolhas[i]
			b.T += dt
			b.Vel = b.Vel * (1 - 0.6 * dt) + Vector3.new(0, 9 * dt, 0)
			b.Pos += b.Vel * dt
			local bamboleio = Vector3.new(math.sin(b.T * 2.3 + b.Fase), 0, math.cos(b.T * 1.9 + b.Fase)) * 0.8
			b.Parte.CFrame = CFrame.new(b.Pos + bamboleio)
			b.Parte.Color = Color3.fromHSV((t * 0.2 + b.Fase * 0.1) % 1, 0.35, 1)
			if b.T >= b.Vida then
				table.remove(bolhas, i)
				estourar(b)
			end
		end
	end)
	-- bolha gigante no gol
	local centroG = C.Gol + C.Dentro * 8 + Vector3.new(0, 16, 0)
	local gigante = s:Parte({ Shape = Enum.PartType.Ball, Size = Vector3.one, Material = Enum.Material.ForceField, Color = cor, CFrame = CFrame.new(centroG) })
	s:Tween(gigante, 1.2, { Size = Vector3.one * 56 }, Enum.EasingStyle.Back)
	s:Cada(function(t, u)
		if not gigante.Parent then return true end
		local w = 1 + 0.04 * math.sin(t * 6)
		if t > 1.2 then gigante.Size = Vector3.new(56 * w, 56 / w, 56 * w) end
		gigante.Color = Color3.fromHSV((t * 0.3) % 1, 0.4, 1)
		if u >= 0.4 then
			s:Flash(cor, 0.45, 0.6)
			s:Tween(gigante, 0.15, { Size = Vector3.one * 75, Transparency = 1 })
			Debris:AddItem(gigante, 0.2)
			for _ = 1, 45 do
				local dirB = Vector3.new(rnd(-1, 1), rnd(-0.2, 1), rnd(-1, 1)).Unit
				nova(centroG + dirB * 20, rnd(2, 7), dirB * rnd(25, 50))
			end
			s:OndaChao(Vector3.new(centroG.X, C.ChaoY, centroG.Z), cor, 120, 1)
			return true
		end
	end)
	-- bolhas do campo todo (metade perto da câmera)
	local nevoa = s:EmissorCampo(C, 1, { Texture = TEX.Bolha, Color = ColorSequence.new(BRANCO), LightEmission = 0.4, Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(4, 9), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20), Size = seq({ { 0, 0.6 }, { 1, 1.5 } }),
		Transparency = seq({ { 0, 0.1 }, { 0.85, 0.2 }, { 1, 1 } }) })
	local nevoaPerto = s:EmissorCamera(C, 1, 60, { Texture = TEX.Bolha, Color = ColorSequence.new(BRANCO), LightEmission = 0.4, Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(3, 7), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25), Size = seq({ { 0, 0.5 }, { 1, 1.2 } }),
		Transparency = seq({ { 0, 0.1 }, { 0.85, 0.2 }, { 1, 1 } }) })
	local acumulado = 0
	s:Cada(function(_, u, dt)
		local k = janela(u, 0.05, 0.25) * (1 - janela(u, 0.78, 0.9))
		nevoa.Rate = 300 * k
		nevoaPerto.Rate = 70 * k
		acumulado += dt * 26 * k
		while acumulado >= 1 and #bolhas < 140 do
			acumulado -= 1
			local pos = rng:NextNumber() < 0.55 and C.PertoDaCamera(90, rnd(0, 4)) or C.Aleatorio(rnd(0, 4), 0.5)
			nova(pos, rnd(2.5, 10))
		end
	end)
end

-- ============================================================
-- 9. NEVASCA (Raro) — PEDIDO: "neve no campo inteiro" + "o gelo congela boa parte
-- do campo". Estouro de gelo na bola; o gramado vai CONGELANDO a partir do gol
-- (placas de gelo + cristais na borda que avança) até ~60% do campo; nevasca
-- com rajadas de vento no campo todo, neblina branca; no fim o gelo derrete.
-- ============================================================
Estilos.Neve = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Brilho = 0.04, Saturacao = -0.3, Contraste = 0.06, Tint = Color3.fromRGB(215, 235, 255), Entrada = 1, Saida = 1.5,
		Neblina = { Density = 0.42, Color = Color3.fromRGB(225, 238, 255), Decay = Color3.fromRGB(200, 220, 245), Haze = 1.6, Glare = 0 } })
	local GELO = Color3.fromRGB(190, 228, 255)
	-- estouro de gelo na bola
	s:Flash(GELO, 0.7, 0.7)
	s:Estouro(C.Bola, { Texture = TEX.Floco, Color = ColorSequence.new(BRANCO), Speed = NumberRange.new(30, 80), Lifetime = NumberRange.new(0.8, 1.6),
		SpreadAngle = Vector2.new(180, 180), Drag = 2, RotSpeed = NumberRange.new(-180, 180), Rotation = NumberRange.new(0, 360), Size = seq({ { 0, 2.2 }, { 1, 0.4 } }) }, 160)
	s:OndaChao(Vector3.new(C.Bola.X, C.ChaoY, C.Bola.Z), BRANCO, 180, 1.2)
	s:Luz(C.Bola, GELO, 60, 10, 1.2)
	-- neve: campo todo + perto da câmera, com rajadas
	local FLOCO = { Texture = TEX.Floco, Color = ColorSequence.new(BRANCO), LightEmission = 0.35, LightInfluence = 0.6, Lifetime = NumberRange.new(7, 9),
		Speed = NumberRange.new(7, 11), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(25, 25), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90), Size = seq({ { 0, 0.55 }, { 1, 0.45 } }), Transparency = seq({ { 0, 0.4 }, { 0.1, 0 }, { 0.9, 0 }, { 1, 1 } }) }
	local neve = s:EmissorCampo(C, 75, FLOCO, 1.15)
	local nevePerto = s:EmissorCamera(C, 45, 70, FLOCO)
	local bruma = s:EmissorCamera(C, 6, 90, { Texture = TEX.Nuvem, Color = ColorSequence.new(BRANCO), LightEmission = 0.2, LightInfluence = 0.6, Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(2, 5), Size = seq({ { 0, 14 }, { 1, 26 } }), Transparency = seq({ { 0, 1 }, { 0.3, 0.75 }, { 0.7, 0.8 }, { 1, 1 } }),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-15, 15) })
	local ventoDir = C.Lado
	s:Cada(function(t, u)
		local k = janela(u, 0.03, 0.2) * (1 - janela(u, 0.85, 0.97))
		neve.Rate = 900 * k
		nevePerto.Rate = 420 * k
		bruma.Rate = 8 * k
		local rajada = 5 + 9 * math.max(0, math.sin(t * 0.9)) ^ 2
		local acel = ventoDir * rajada + Vector3.new(0, -2, 0)
		neve.Acceleration = acel
		nevePerto.Acceleration = acel
	end)
	-- CONGELAR o gramado: placas de gelo aparecendo conforme a borda avança
	local origem = Vector3.new(C.Bola.X, C.ChaoY, C.Bola.Z)
	local RMAX = C.Comp * 0.62
	local DUR = T * 0.5
	local placas, cristais = {}, {}
	local fila = {}
	for i = 1, 230 do
		local p
		for _ = 1, 6 do
			p = C.Aleatorio(0, 0.5)
			if (p - origem).Magnitude <= RMAX then break end
			p = nil
		end
		if p then table.insert(fila, { Pos = p, D = (p - origem).Magnitude, I = i }) end
	end
	-- perto do gol fica mais denso
	for i = 1, 30 do
		local ang, d = rnd(0, math.pi * 2), rnd(0, 70)
		local p = origem + Vector3.new(math.cos(ang) * d, 0, math.sin(ang) * d)
		if C.Dentro01(p) then table.insert(fila, { Pos = p, D = d, I = 300 + i }) end
	end
	table.sort(fila, function(a, b) return a.D < b.D end)
	local prox = 1
	s:Cada(function(t)
		local frente = math.clamp((t - 0.2) / DUR, 0, 1) ^ 0.8 * RMAX
		while prox <= #fila and fila[prox].D <= frente do
			local f = fila[prox]
			prox += 1
			local r = rnd(16, 30)
			local y = C.ChaoY + 0.12 + (f.I % 9) * 0.012
			local placa = s:Parte({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Ice, Color = GELO, Transparency = 0.12, Reflectance = 0.25,
				Size = Vector3.new(0.24, 0.5, 0.5), CFrame = CFrame.new(f.Pos.X, y, f.Pos.Z) * CFrame.Angles(0, 0, math.rad(90)) })
			s:Tween(placa, 0.4, { Size = Vector3.new(0.24, r * 2, r * 2) }, Enum.EasingStyle.Back)
			table.insert(placas, placa)
			-- cristais na borda que avança (1 a cada 3 placas)
			if f.I % 3 == 0 and #cristais < 150 then
				for _ = 1, rng:NextInteger(2, 4) do
					local h = rnd(4, 13)
					local base = f.Pos + Vector3.new(rnd(-r, r) * 0.6, 0, rnd(-r, r) * 0.6)
					local giro = CFrame.Angles(rnd(-0.5, 0.5), rnd(0, math.pi), rnd(-0.5, 0.5))
					local cr = s:Parte({ Material = Enum.Material.Glass, Color = Color3.fromRGB(170, 220, 255), Transparency = 0.2, Reflectance = 0.3,
						Size = Vector3.new(rnd(1, 2.4), 0.2, rnd(1, 2.4)), CFrame = CFrame.new(base.X, C.ChaoY, base.Z) * giro })
					s:Tween(cr, 0.35, { Size = Vector3.new(cr.Size.X, h, cr.Size.Z), CFrame = CFrame.new(base.X, C.ChaoY, base.Z) * giro * CFrame.new(0, h / 2 - 0.5, 0) }, Enum.EasingStyle.Back)
					table.insert(cristais, cr)
				end
				s:Estouro(f.Pos + Vector3.new(0, 1, 0), { Texture = TEX.Estrela, Color = ColorSequence.new(BRANCO), Speed = NumberRange.new(2, 8),
					Lifetime = NumberRange.new(0.4, 0.8), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Size = seq({ { 0, 1.2 }, { 1, 0 } }) }, 6)
			end
		end
		if prox > #fila then return true end
	end)
	-- derrete no fim
	s:Em(T - 1.6, function()
		for _, p in ipairs(placas) do s:Tween(p, 1.3, { Transparency = 1 }) end
		for _, c in ipairs(cristais) do s:Tween(c, 1, { Transparency = 1, Size = Vector3.new(c.Size.X * 0.4, 0.2, c.Size.Z * 0.4) }) end
	end)
end

-- ============================================================
-- 10. CHUVA DE MOEDAS (Épico) — jackpot: chafariz de moedas no gol, uma MOEDA
-- GIGANTE gira no céu em cima do gol, chove moeda (que quica no gramado) no
-- campo todo e brilho dourado; no fim a moeda gigante estoura em moedas.
-- ============================================================
Estilos.Moedas = function(s, C, cor)
	local T = s.Total
	local OURO = Color3.fromRGB(255, 200, 50)
	s:Ambiente({ Brilho = 0.07, Contraste = 0.15, Saturacao = 0.3, Tint = Color3.fromRGB(255, 240, 205), Entrada = 0.6, Saida = 1.2 })
	aberturaNaBola(s, C, OURO, 1)
	local moedas = {}
	local function moeda(pos, vel)
		if #moedas >= 260 then return end
		local p = s:Parte({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = OURO, Reflectance = 0.35, Size = Vector3.new(0.35, 2.4, 2.4), CFrame = CFrame.new(pos) })
		table.insert(moedas, { Parte = p, Pos = pos, Vel = vel, Giro = rnd(6, 14), Eixo = Vector3.new(rnd(-1, 1), rnd(-1, 1), rnd(-1, 1)).Unit, T = 0, Quiques = 0, Parada = false })
	end
	s:Cada(function(_, _, dt)
		for i = #moedas, 1, -1 do
			local m = moedas[i]
			m.T += dt
			if not m.Parada then
				m.Vel += Vector3.new(0, -60 * dt, 0)
				m.Pos += m.Vel * dt
				if m.Pos.Y <= C.ChaoY + 0.2 then
					m.Pos = Vector3.new(m.Pos.X, C.ChaoY + 0.2, m.Pos.Z)
					m.Quiques += 1
					if m.Quiques >= 2 then
						m.Parada = true
						m.Parte.CFrame = CFrame.new(m.Pos) * CFrame.Angles(0, rnd(0, 6), math.rad(90))
					else
						m.Vel = Vector3.new(m.Vel.X * 0.5, -m.Vel.Y * 0.35, m.Vel.Z * 0.5)
					end
				end
				if not m.Parada then
					m.Parte.CFrame = CFrame.new(m.Pos) * CFrame.fromAxisAngle(m.Eixo, m.T * m.Giro)
				end
			end
			if m.T > 4.5 then
				table.remove(moedas, i)
				s:Tween(m.Parte, 0.4, { Transparency = 1 })
				Debris:AddItem(m.Parte, 0.45)
			end
		end
	end)
	-- chafariz no gol
	local acumulado = 0
	s:Cada(function(_, u, dt)
		local fonte = u < 0.25 and 70 or 0
		local chuva = 60 * janela(u, 0.15, 0.3) * (1 - janela(u, 0.72, 0.8))
		acumulado += dt * (fonte + chuva)
		while acumulado >= 1 do
			acumulado -= 1
			if rng:NextNumber() < fonte / math.max(fonte + chuva, 1) then
				moeda(C.Bola + Vector3.new(0, 1, 0), C.Dentro * rnd(5, 20) + C.Lado * rnd(-14, 14) + Vector3.new(0, rnd(35, 55), 0))
			else
				moeda(C.PertoDaCamera(110, rnd(50, 80)), Vector3.new(rnd(-3, 3), -rnd(5, 15), rnd(-3, 3)))
			end
		end
	end)
	-- brilho dourado chovendo no campo todo
	local ouro = s:EmissorCampo(C, 90, { Texture = TEX.Estrela, Color = ColorSequence.new(OURO, Color3.fromRGB(255, 245, 200)), Lifetime = NumberRange.new(3, 4.5),
		Speed = NumberRange.new(18, 26), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(10, 10), Size = seq({ { 0, 1.4 }, { 1, 0.6 } }) })
	local ouroPerto = s:EmissorCamera(C, 50, 60, { Texture = TEX.Moeda, LightEmission = 0.3, LightInfluence = 0.5, Color = ColorSequence.new(BRANCO),
		Lifetime = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(16, 22), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(10, 10),
		Size = NumberSequence.new(1.1), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Squash = seq({ { 0, 0 }, { 0.25, 0.8 }, { 0.5, 0 }, { 0.75, -0.8 }, { 1, 0 } }) })
	s:Cada(function(_, u)
		local k = janela(u, 0.12, 0.3) * (1 - janela(u, 0.75, 0.88))
		ouro.Rate = 380 * k
		ouroPerto.Rate = 60 * k
	end)
	-- moeda gigante no céu
	local alto = C.Gol + C.Dentro * 50 + Vector3.new(0, 110, 0)
	local borda = s:Parte({ Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(255, 220, 90), Transparency = 0.45, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(C.Bola) })
	local miolo = s:Parte({ Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal, Color = OURO, Reflectance = 0.45, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(C.Bola) })
	local luz = Instance.new("PointLight")
	luz.Range = 60
	luz.Brightness = 6
	luz.Color = OURO
	luz.Parent = miolo
	local gEmissor = s:Emissor(borda, { Texture = TEX.Estrela, Color = ColorSequence.new(Color3.fromRGB(255, 240, 180)), Rate = 60, Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(4, 12), SpreadAngle = Vector2.new(180, 180), Size = seq({ { 0, 3 }, { 1, 0 } }), Shape = Enum.ParticleEmitterShape.Cylinder })
	local estourou = false
	s:Cada(function(t, u)
		if estourou then return true end
		local sobe = suave(janela(u, 0.05, 0.22))
		local pos = C.Bola:Lerp(alto, sobe)
		local escala = lerp(0.05, 1, sobe)
		local giro = t * lerp(1.6, 9, janela(u, 0.6, 0.78))
		local cf = CFrame.new(pos + Vector3.new(0, math.sin(t * 1.4) * 3, 0)) * CFrame.Angles(0, giro, 0)
		borda.Size = Vector3.new(5, 84, 84) * escala
		miolo.Size = Vector3.new(6.5, 74, 74) * escala
		borda.CFrame = cf
		miolo.CFrame = cf
		if u >= 0.78 then
			estourou = true
			s:Flash(OURO, 0.9, 1)
			s:Estouro(pos, { Texture = TEX.Estrela, Color = ColorSequence.new(BRANCO, OURO), Speed = NumberRange.new(50, 110), Lifetime = NumberRange.new(1, 1.8),
				SpreadAngle = Vector2.new(180, 180), Drag = 1.5, Size = seq({ { 0, 6 }, { 1, 0 } }) }, 280)
			for _ = 1, 110 do
				moeda(pos, Vector3.new(rnd(-1, 1), rnd(-0.3, 1), rnd(-1, 1)).Unit * rnd(30, 70))
			end
			borda:Destroy()
			miolo:Destroy()
			gEmissor:Destroy()
			s:OndaChao(Vector3.new(pos.X, C.ChaoY, pos.Z), OURO, C.Comp * 0.45, 1.5)
			return true
		end
	end)
end

-- ============================================================
-- 11. CORAÇÕES (Épico) — pôr do sol rosa; um coração GIGANTE bate no céu em cima
-- do gol, contornos de coração se abrem pelo gramado, corações sobem do campo
-- todo; no fim o coração gigante explode em corações.
-- ============================================================
Estilos.Coracoes = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 18.1, Brilho = 0.03, Saturacao = 0.25, Tint = Color3.fromRGB(255, 215, 230), Entrada = 0.8, Saida = 1.3 })
	aberturaNaBola(s, C, cor, 1)
	local CORES = { cor, Color3.fromRGB(255, 140, 180), Color3.fromRGB(255, 60, 100), Color3.fromRGB(255, 230, 240) }
	-- contorno de coração no chão que se abre (2 vezes)
	local function contorno(atraso, corC)
		local n = 64
		local partes = {}
		for i = 1, n do
			partes[i] = s:Parte({ Color = corC, Size = Vector3.new(2, 0.3, 2), Transparency = 1 })
		end
		local eixoF = C.Dentro
		local eixoL = C.Lado
		local centro = Vector3.new(C.Bola.X, C.ChaoY + 0.3, C.Bola.Z) + C.Dentro * 10
		s:Cada(function(t)
			local k = (t - atraso) / 2.6
			if k < 0 then return end
			if k >= 1 then
				for _, p in ipairs(partes) do p:Destroy() end
				return true
			end
			local esc = lerp(0.3, 13, k ^ 0.7)
			for i, p in ipairs(partes) do
				local a = i / n * math.pi * 2
				local x = 16 * math.sin(a) ^ 3
				local y = 13 * math.cos(a) - 5 * math.cos(2 * a) - 2 * math.cos(3 * a) - math.cos(4 * a)
				p.CFrame = CFrame.new(centro + eixoL * (x * esc) + eixoF * (y * esc))
				p.Size = Vector3.new(1.4 + esc * 0.35, 0.3, 1.4 + esc * 0.35)
				p.Transparency = 0.1 + 0.9 * k
			end
		end)
	end
	contorno(0.1, cor)
	contorno(T * 0.45, Color3.fromRGB(255, 230, 240))
	-- coração gigante batendo no céu
	local alto = C.Gol + C.Dentro * 40 + Vector3.new(0, 95, 0)
	local gig = s:Placa(alto, 1, {
		{ Imagem = TEX.Brilho, Cor = cor, Transp = 0.35, Escala = 2.2 },
		{ Imagem = TEX.Coracao, Cor = cor, Transp = 0.55, Escala = 1.18 },
		{ Imagem = TEX.Coracao, Cor = cor:Lerp(Color3.fromRGB(255, 40, 90), 0.3), Transp = 0, Escala = 1 },
	})
	local voar = s:Voadores()
	local function coracaoVoando(pos, ate, tam, dur)
		local pl = s:Placa(pos, tam, { { Imagem = TEX.Coracao, Cor = CORES[rng:NextInteger(1, #CORES)], Transp = 0.05 } })
		local fase = rnd(0, 6)
		s:Cada(function(t2)
			if not pl.Ancora.Parent then return true end
			pl.Camadas[1].Rotation = math.sin(t2 * 2 + fase) * 15
		end)
		voar(pl.Ancora, pos, ate, dur, nil, function(k)
			return Vector3.new(math.sin(k * 8 + fase) * 4, 0, math.cos(k * 6 + fase) * 4)
		end)
		s:Em(dur * 0.7, function() s:Tween(pl.Camadas[1], dur * 0.3, { ImageTransparency = 1 }) end)
	end
	local estourou = false
	local acumulado = 0
	s:Cada(function(t, u, dt)
		-- batida dupla (tum-tum) a cada 0.9s
		local fase = (t % 0.9) / 0.9
		local pulso = math.exp(-((fase - 0.1) / 0.05) ^ 2) + 0.7 * math.exp(-((fase - 0.3) / 0.05) ^ 2)
		local aparece = suave(janela(u, 0.03, 0.18))
		if not estourou then
			local tam = 110 * aparece * (1 + 0.14 * pulso)
			gig.Gui.Size = UDim2.fromScale(tam, tam)
			if pulso > 0.9 and gig.UltimaBatida ~= math.floor(t / 0.9) then
				gig.UltimaBatida = math.floor(t / 0.9)
				s.AmbBrilho = 0.06
				s:Em(0.1, function() s.AmbBrilho = 0 end)
			end
		end
		-- corações subindo do campo todo
		local k = janela(u, 0.1, 0.25) * (1 - janela(u, 0.75, 0.85))
		acumulado += dt * 14 * k
		while acumulado >= 1 do
			acumulado -= 1
			local ini = rng:NextNumber() < 0.5 and C.PertoDaCamera(80, 1) or C.Aleatorio(1, 0.5)
			coracaoVoando(ini, ini + Vector3.new(rnd(-8, 8), rnd(35, 60), rnd(-8, 8)), rnd(3, 8), rnd(3, 4.5))
		end
		if u >= 0.8 and not estourou then
			estourou = true
			s:Flash(cor, 0.8, 0.9)
			s:Tween(gig.Gui, 0.5, { Size = UDim2.fromScale(260, 260) })
			for _, c in ipairs(gig.Camadas) do s:Tween(c, 0.5, { ImageTransparency = 1 }) end
			for _ = 1, 40 do
				local d = Vector3.new(rnd(-1, 1), rnd(-0.6, 0.8), rnd(-1, 1)).Unit
				coracaoVoando(alto, alto + d * rnd(80, 160), rnd(5, 12), rnd(1.4, 2.2))
			end
			s:OndaChao(Vector3.new(alto.X, C.ChaoY, alto.Z), cor, C.Comp * 0.4, 1.4)
		end
	end)
end

-- ============================================================
-- 12. ONDA DE ENERGIA (Lendário) — a energia carrega na bola, e TRÊS paredes de
-- energia varrem o campo inteiro a partir do gol, levantando pilares de luz por
-- onde passam; no fim toda a energia volta pro gol e sobe num feixe pro céu.
-- ============================================================
Estilos.Onda = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 19.4, Brilho = -0.15, Contraste = 0.18, Saturacao = 0.15, Tint = Color3.fromRGB(205, 255, 240), Entrada = 1, Saida = 1.4 })
	local origem = Vector3.new(C.Bola.X, C.ChaoY, C.Bola.Z)
	-- carga na bola
	local nucleo = s:Parte({ Shape = Enum.PartType.Ball, Color = BRANCO, Size = Vector3.one, CFrame = CFrame.new(C.Bola) })
	local casca = s:Parte({ Shape = Enum.PartType.Ball, Material = Enum.Material.ForceField, Color = cor, Size = Vector3.one, CFrame = CFrame.new(C.Bola) })
	local sugar = s:Emissor(s:Ancora(C.Bola, Vector3.one * 70), { Texture = TEX.Brilho, Color = ColorSequence.new(cor, BRANCO), Rate = 0,
		Lifetime = NumberRange.new(0.9, 1.1), Speed = NumberRange.new(32, 36), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = seq({ { 0, 1.5 }, { 1, 0.2 } }) })
	-- paredes de energia
	local paredes = {}
	local CORES_P = { cor, Color3.fromRGB(120, 200, 255), Color3.fromRGB(200, 150, 255) }
	for i, inicio in ipairs({ 0.15, 0.36, 0.57 }) do
		paredes[i] = { Inicio = inicio, Anel = s:Anel(origem, 56, { Color = CORES_P[i], Transparency = 1 }), Cor = CORES_P[i] }
	end
	local RMAX = C.Comp * 1.05
	local DUR = T * 0.26
	local motes = s:EmissorCampo(C, 1, { Texture = TEX.Brilho, Color = ColorSequence.new(cor, BRANCO), Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(4, 10),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20), Size = seq({ { 0, 0.8 }, { 1, 0 } }) })
	local motesPerto = s:EmissorCamera(C, 1, 60, { Texture = TEX.Brilho, Color = ColorSequence.new(cor, BRANCO), Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(3, 8),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(25, 25), Size = seq({ { 0, 0.6 }, { 1, 0 } }) })
	local function pilar(pos, c)
		local h = rnd(60, 150)
		local p = s:Parte({ Shape = Enum.PartType.Cylinder, Color = c, Transparency = 0.15, Size = Vector3.new(1, 3, 3),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)) })
		s:Tween(p, 0.25, { Size = Vector3.new(h, 3, 3), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		s:Em(0.25, function() s:Tween(p, 0.6, { Transparency = 1, Size = Vector3.new(h * 1.1, 0.4, 0.4) }) end)
		Debris:AddItem(p, 0.9)
		s:Estouro(pos, { Color = ColorSequence.new(c), Speed = NumberRange.new(5, 15), Lifetime = NumberRange.new(0.4, 0.8), SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top, Size = seq({ { 0, 2 }, { 1, 0 } }) }, 10)
	end
	local disparouFinal, feixe = false, nil
	s:Cada(function(t, u)
		-- carga
		local kc = suave(janela(u, 0, 0.14))
		if u < 0.15 then
			nucleo.Size = Vector3.one * (2 + 10 * kc) * (1 + 0.1 * math.sin(t * 30))
			casca.Size = nucleo.Size * 1.8
			sugar.Rate = 220 * kc
		elseif nucleo.Parent then
			sugar.Rate = 0
			s:Flash(cor, 0.8, 0.6)
			s:Luz(C.Bola, cor, 60, 14, 1)
			nucleo:Destroy()
			casca:Destroy()
		end
		-- paredes
		for _, pw in ipairs(paredes) do
			local k = (u - pw.Inicio) * T / DUR
			if k > 0 and k <= 1.05 then
				local r = RMAX * (k ^ 0.85)
				local altura = lerp(26, 8, k)
				pw.Anel.Atualizar(r, altura, 1.2, lerp(0.15, 0.95, k ^ 2), pw.Cor)
				-- pilares na frente da onda (só dentro do campo)
				for _ = 1, 3 do
					local ang = rnd(0, math.pi * 2)
					local p = origem + Vector3.new(math.cos(ang) * r, 0, math.sin(ang) * r)
					if C.Dentro01(p) and rng:NextNumber() < 0.5 then pilar(p, pw.Cor) end
				end
			elseif k > 1.05 and not pw.Fim then
				pw.Fim = true
				pw.Anel.Destruir()
			end
		end
		local km = janela(u, 0.15, 0.3) * (1 - janela(u, 0.78, 0.85))
		motes.Rate = 320 * km
		motesPerto.Rate = 70 * km
		-- final: tudo volta pro gol e sobe num feixe
		if u >= 0.78 and not disparouFinal then
			disparouFinal = true
			s:Emissor(s:Ancora(C.Bola, Vector3.one * 500), { Texture = TEX.Brilho, Color = ColorSequence.new(cor, BRANCO), Rate = 0,
				Lifetime = NumberRange.new(1.4, 1.6), Speed = NumberRange.new(165, 180), Shape = Enum.ParticleEmitterShape.Sphere,
				ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = seq({ { 0, 3 }, { 1, 0.5 } }) }):Emit(500)
			s:Em(1.3, function()
				s:Flash(BRANCO, 1.1, 1)
				feixe = s:Parte({ Shape = Enum.PartType.Cylinder, Color = BRANCO, Size = Vector3.new(700, 4, 4),
					CFrame = CFrame.new(origem + Vector3.new(0, 350, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
				local halo = s:Parte({ Shape = Enum.PartType.Cylinder, Color = cor, Transparency = 0.6, Size = Vector3.new(700, 10, 10),
					CFrame = feixe.CFrame })
				s:Tween(feixe, 0.3, { Size = Vector3.new(700, 22, 22) })
				s:Tween(halo, 0.3, { Size = Vector3.new(700, 60, 60) })
				s:Em(0.6, function()
					s:Tween(feixe, 1.2, { Size = Vector3.new(700, 0.5, 0.5), Transparency = 1 })
					s:Tween(halo, 1.2, { Size = Vector3.new(700, 90, 90), Transparency = 1 })
				end)
				s:OndaChao(origem, cor, C.Comp * 0.7, 1.6)
				s:Luz(origem + Vector3.new(0, 8, 0), cor, 60, 18, 2)
			end)
		end
	end)
end

-- ============================================================
-- 13. AURORA (Lendário) — vira noite, um pilar verde sobe do gol e ABRE uma
-- aurora boreal gigante em cortinas que ondulam no céu em cima do campo todo;
-- o gramado ganha o reflexo das cores; estrelas cadentes cruzam.
-- ============================================================
Estilos.Aurora = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 23.2, Brilho = -0.08, Saturacao = 0.25, Tint = Color3.fromRGB(215, 255, 235), Estrelas = 6000, Entrada = 1.3, Saida = 1.6 })
	aberturaNaBola(s, C, cor, 0.9)
	-- pilar do gol
	local pil = s:Parte({ Shape = Enum.PartType.Cylinder, Color = cor, Transparency = 0.2, Size = Vector3.new(1, 6, 6),
		CFrame = CFrame.new(C.Gol) * CFrame.Angles(0, 0, math.rad(90)) })
	s:Tween(pil, 1.4, { Size = Vector3.new(420, 6, 6), CFrame = CFrame.new(C.Gol + Vector3.new(0, 210, 0)) * CFrame.Angles(0, 0, math.rad(90)) }, Enum.EasingStyle.Quart)
	s:Em(1.4, function() s:Tween(pil, 1.5, { Transparency = 1, Size = Vector3.new(420, 30, 30) }) end)
	-- cortinas: colunas (Beam vertical) ao longo de uma linha sinuosa
	local CORTINAS = {
		{ Altura = 135, Topo = 245, Desvio = 0.0, Amp = 0.16, Cor0 = Color3.fromRGB(90, 255, 150), Cor1 = Color3.fromRGB(150, 90, 255) },
		{ Altura = 165, Topo = 290, Desvio = 0.32, Amp = 0.12, Cor0 = Color3.fromRGB(80, 220, 255), Cor1 = Color3.fromRGB(255, 110, 210) },
	}
	local colunas = {}
	local N = 34
	for ci, cfg in ipairs(CORTINAS) do
		for i = 1, N do
			local ancA = s:Ancora(C.Centro)
			local ancB = s:Ancora(C.Centro)
			local a0 = Instance.new("Attachment")
			a0.Parent = ancA
			local a1 = Instance.new("Attachment")
			a1.Parent = ancB
			local bm = Instance.new("Beam")
			bm.Attachment0 = a0
			bm.Attachment1 = a1
			bm.FaceCamera = true
			bm.LightEmission = 1
			bm.LightInfluence = 0
			bm.Segments = 8
			bm.Width0 = C.Comp * 1.3 / N * 1.6
			bm.Width1 = C.Comp * 1.3 / N * 1.9
			bm.Color = cseq({ { 0, cfg.Cor0 }, { 0.55, cfg.Cor0:Lerp(cfg.Cor1, 0.5) }, { 1, cfg.Cor1 } })
			bm.Transparency = NumberSequence.new(1)
			bm.Texture = TEX.Nuvem
			bm.TextureMode = Enum.TextureMode.Stretch
			bm.Parent = ancA
			table.insert(colunas, { Beam = bm, A = ancA, B = ancB, I = i, Cfg = cfg, Ci = ci })
		end
	end
	local function corGol(fx) -- distância (0..1) da coluna até o gol (a aurora abre a partir dele)
		local golFx = C.CF:PointToObjectSpace(C.Gol).X / C.Comp
		return math.abs(fx - golFx)
	end
	s:Cada(function(t, u)
		local abre = janela(u, 0.08, 0.35)
		local some = 1 - janela(u, 0.86, 0.97)
		for _, c in ipairs(colunas) do
			local fx = (c.I - 0.5) / N - 0.5
			local fx2 = fx * 1.3
			local fz = c.Cfg.Desvio - 0.15 + c.Cfg.Amp * math.sin(fx2 * 7 + t * 0.45 + c.Ci) + 0.05 * math.sin(fx2 * 17 - t * 0.8)
			local baixo = C.Ponto(fx2, fz, c.Cfg.Altura + 10 * math.sin(fx2 * 5 + t * 0.6))
			local cima = C.Ponto(fx2 + 0.02 * math.sin(t * 0.5 + c.I), fz + 0.03, c.Cfg.Topo + 25 * math.sin(fx2 * 4 - t * 0.5 + c.Ci))
			c.A.CFrame = CFrame.new(baixo)
			c.B.CFrame = CFrame.new(cima)
			local liga = math.clamp((abre * 1.25 - corGol(fx2) * 0.9) * 2.2, 0, 1) * some
			local onda = 0.5 + 0.5 * math.sin(t * 1.6 - fx2 * 12 + c.Ci)
			local base = 1 - liga * (0.35 + 0.4 * onda)
			c.Beam.Transparency = seq({ { 0, 1 }, { 0.12, base }, { 0.45, math.min(1, base + 0.12) }, { 1, 1 } })
		end
		-- reflexo da aurora no gramado
		local h = 0.38 + 0.08 * math.sin(t * 0.7)
		s.AmbTint = Color3.fromHSV(h, 0.16 * abre, 1)
	end)
	-- poeira de luz subindo e estrelas cadentes
	local motes = s:EmissorCampo(C, 2, { Texture = TEX.Estrela, Color = ColorSequence.new(Color3.fromRGB(150, 255, 200), Color3.fromRGB(190, 150, 255)),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(2, 6), EmissionDirection = Enum.NormalId.Top, Size = seq({ { 0, 0 }, { 0.4, 0.9 }, { 1, 0 } }) })
	s:Cada(function(_, u)
		motes.Rate = 260 * janela(u, 0.2, 0.4) * (1 - janela(u, 0.85, 0.95))
	end)
	local voar = s:Voadores()
	for i = 1, 5 do
		s:Em(T * (0.3 + i * 0.1), function()
			local ini = C.Ponto(rnd(-0.6, 0.6), rnd(-0.7, 0.7), rnd(260, 320))
			local fim = ini + (C.Eixo * rnd(-1, 1) + C.Lado * rnd(-1, 1)).Unit * rnd(250, 400) - Vector3.new(0, rnd(60, 120), 0)
			local m = s:Cometa(Color3.fromRGB(220, 255, 240), 1.6, 2, 0.6)
			m.CFrame = CFrame.new(ini)
			voar(m, ini, fim, rnd(0.8, 1.2))
		end)
	end
end

-- ============================================================
-- 14. BURACO NEGRO (Mítico) — escuridão total; um buraco negro nasce em cima do
-- gol com disco de acreção girando, SUGA luz e pedaços do gramado do campo
-- inteiro; colapsa num ponto (silêncio escuro) e explode numa onda que varre
-- o campo todo.
-- ============================================================
Estilos.BuracoNegro = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 0.2, Brilho = -0.3, Saturacao = -0.45, Contraste = 0.28, Tint = Color3.fromRGB(225, 210, 255), Estrelas = 5000, Entrada = 1.4, Saida = 1.8,
		Neblina = { Density = 0.4, Color = Color3.fromRGB(40, 22, 60), Decay = Color3.fromRGB(25, 10, 40), Haze = 1, Glare = 0 } })
	aberturaNaBola(s, C, cor, 0.8)
	local H = C.Gol + C.Dentro * 70 + Vector3.new(0, 95, 0)
	local LARANJA = Color3.fromRGB(255, 170, 90)
	local bn = s:Placa(H, 1, {
		{ Imagem = TEX.Brilho, Cor = cor, Transp = 0.2, Escala = 3.2 },
		{ Imagem = TEX.Brilho, Cor = LARANJA, Transp = 0.35, Escala = 1.9 },
		{ Imagem = TEX.Anel, Cor = Color3.fromRGB(255, 235, 200), Transp = 0, Escala = 1.22 },
		{ Solido = true, Cor = Color3.new(0, 0, 0), Escala = 1 },
	})
	-- disco de acreção 3D (partículas presas no disco, que gira)
	local disco = s:Ancora(CFrame.new(H) * CFrame.Angles(math.rad(72), 0, 0), Vector3.new(1, 1, 1))
	local eDisco = s:Emissor(disco, { Texture = TEX.Brilho, Color = cseq({ { 0, cor }, { 0.6, LARANJA }, { 1, BRANCO } }), Rate = 0, LockedToPart = true,
		Lifetime = NumberRange.new(1.4, 1.8), Speed = NumberRange.new(40, 55), Shape = Enum.ParticleEmitterShape.Disc,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = seq({ { 0, 2.2 }, { 1, 0.6 } }) })
	-- luz do campo inteiro sendo sugada
	local sugaAncora = s:Ancora(H, Vector3.one * 760)
	local eSuga = s:Emissor(sugaAncora, { Texture = TEX.Brilho, Color = ColorSequence.new(Color3.fromRGB(200, 180, 255), cor), Rate = 0,
		Lifetime = NumberRange.new(2.3, 2.5), Speed = NumberRange.new(150, 160), Shape = Enum.ParticleEmitterShape.Sphere,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Size = seq({ { 0, 2.5 }, { 1, 0.4 } }) })
	-- pedaços do gramado que sobem em espiral
	local pedacos = {}
	for i = 1, 70 do
		local ang, d = rnd(0, math.pi * 2), rnd(40, 300)
		local base = Vector3.new(H.X + math.cos(ang) * d, C.ChaoY, H.Z + math.sin(ang) * d)
		if C.Dentro01(base) or i % 3 == 0 then
			local tam = Vector3.new(rnd(1.5, 4.5), rnd(0.6, 1.4), rnd(1.5, 4.5))
			table.insert(pedacos, { Base = base, Ang = ang, D = d, Inicio = rnd(0.12, 0.6), Tam = tam, Giro = Vector3.new(rnd(-3, 3), rnd(-3, 3), rnd(-3, 3)) })
		end
	end
	local colapsou, explodiu = false, false
	s:Cada(function(t, u, dt)
		-- nasce, cresce, colapsa
		local nasce = suave(janela(u, 0.04, 0.2))
		local tam
		if u < 0.72 then
			tam = lerp(2, 70, nasce) + 10 * janela(u, 0.2, 0.72) + 2 * math.sin(t * 5)
		else
			tam = lerp(80, 0, suave(janela(u, 0.72, 0.8)))
		end
		bn.Gui.Size = UDim2.fromScale(tam, tam)
		bn.Camadas[1].Rotation = t * 20
		bn.Camadas[3].Rotation = -t * 40
		disco.CFrame = CFrame.new(H) * CFrame.Angles(math.rad(72), 0, 0) * CFrame.Angles(0, t * 2.4, 0)
		disco.Size = Vector3.new(tam * 2.6, 1, tam * 2.6)
		local ativo = (u > 0.1 and u < 0.72) and 1 or 0
		eDisco.Rate = 520 * ativo * nasce
		eSuga.Rate = 420 * ativo
		-- pedaços
		for _, p in ipairs(pedacos) do
			if u >= p.Inicio and u < 0.75 then
				if not p.Parte then
					p.Parte = s:Parte({ Material = Enum.Material.Grass, Color = Color3.fromRGB(70, 120, 55), Size = p.Tam, CFrame = CFrame.new(p.Base) })
					p.T = 0
					s:Estouro(p.Base, { Texture = TEX.Nuvem, Color = ColorSequence.new(Color3.fromRGB(90, 80, 70)), LightEmission = 0, LightInfluence = 1,
						Speed = NumberRange.new(2, 6), Lifetime = NumberRange.new(0.6, 1), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
						Size = seq({ { 0, 3 }, { 1, 6 } }), Transparency = seq({ { 0, 0.4 }, { 1, 1 } }) }, 4)
				end
				p.T += dt
				local k = math.clamp(p.T / 3.2, 0, 1)
				local kk = k * k
				local ang = p.Ang + kk * 9
				local d = p.D * (1 - kk)
				local pos = Vector3.new(H.X + math.cos(ang) * d, lerp(C.ChaoY + 1, H.Y, kk ^ 0.8), H.Z + math.sin(ang) * d)
				p.Parte.CFrame = CFrame.new(pos) * CFrame.Angles(p.Giro.X * p.T, p.Giro.Y * p.T, p.Giro.Z * p.T)
				p.Parte.Size = p.Tam * (1 - kk * 0.9)
				if k >= 1 then
					p.Parte:Destroy()
					p.Inicio = math.huge
				end
			elseif u >= 0.75 and p.Parte and p.Parte.Parent then
				p.Parte:Destroy()
			end
		end
		-- colapso: tudo escurece
		if u >= 0.72 and not colapsou then
			colapsou = true
			s:Tween(bn.Camadas[1], 0.5, { ImageTransparency = 1 })
			s:Tween(bn.Camadas[2], 0.5, { ImageTransparency = 1 })
		end
		if u >= 0.72 and u < 0.8 then
			s.AmbBrilho = -0.35 * suave(janela(u, 0.72, 0.79))
		end
		-- EXPLOSÃO
		if u >= 0.8 and not explodiu then
			explodiu = true
			s.AmbBrilho = 0
			s:Flash(BRANCO, 1.6, 1.4)
			s:Estouro(H, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 0.3, cor }, { 1, LARANJA } }), Speed = NumberRange.new(80, 200),
				Lifetime = NumberRange.new(1.2, 2.2), SpreadAngle = Vector2.new(180, 180), Drag = 1, Size = seq({ { 0, 9 }, { 1, 0 } }) }, 400)
			for i = 1, 30 do
				local a1, a2 = i / 30 * math.pi * 2, math.sin(i * 1.7) * 0.9
				local dirR = Vector3.new(math.cos(a1) * math.cos(a2), math.sin(a2), math.sin(a1) * math.cos(a2))
				local r = s:Parte({ Color = (i % 2 == 0) and cor or BRANCO, Size = Vector3.new(2, 2, 10), CFrame = CFrame.lookAt(H, H + dirR) })
				s:Tween(r, 1.4, { Size = Vector3.new(0.3, 0.3, 360), CFrame = CFrame.lookAt(H + dirR * 180, H + dirR * 181), Transparency = 1 })
				Debris:AddItem(r, 1.5)
			end
			local anel = s:Anel(Vector3.new(H.X, C.ChaoY, H.Z), 60, { Color = cor, Transparency = 0.2 })
			s:Cada(function(t2)
				local k = (t2 - T * 0.8) / 1.8
				if k >= 1 then anel.Destruir() return true end
				anel.Atualizar(C.Comp * 1.1 * (k ^ 0.6), lerp(40, 6, k), 1.5, lerp(0.1, 1, k ^ 1.5), cor:Lerp(BRANCO, 1 - k))
			end)
			s:OndaChao(Vector3.new(H.X, C.ChaoY, H.Z), BRANCO, C.Comp * 0.8, 1.6)
			s:Luz(H, BRANCO, 60, 20, 2)
			bn.Gui:Destroy()
		end
	end)
end

-- ============================================================
-- 15. SUPERNOVA (Mítico) — PEDIDO: "planeta maior, o ambiente escurece, estrelas
-- sobem, o planeta pisca no céu". Escurece e ESTRELAS SOBEM do campo inteiro; um
-- PLANETA gigante cresce no céu atrás do gol e começa a PISCAR cada vez mais
-- rápido; explode em supernova (flash, cascas de cor, raios, onda que varre o
-- campo); sobra uma nebulosa colorida e chuva de estrelas.
-- ============================================================
Estilos.Supernova = function(s, C, cor)
	local T = s.Total
	s:Ambiente({ Hora = 0.3, Brilho = -0.2, Saturacao = 0.1, Contraste = 0.15, Tint = Color3.fromRGB(220, 215, 255), Estrelas = 6000, Entrada = 1.2, Saida = 1.8 })
	aberturaNaBola(s, C, cor, 1)
	local PALETA = { Color3.fromRGB(255, 252, 235), Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 80, 190), Color3.fromRGB(110, 150, 255) }
	-- estrelas subindo do campo
	local sobem = s:EmissorCampo(C, 1, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 1, cor } }), Lifetime = NumberRange.new(6, 9),
		Speed = NumberRange.new(7, 16), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(8, 8), Size = seq({ { 0, 1 }, { 0.5, 3.2 }, { 1, 0 } }) })
	local sobemPerto = s:EmissorCamera(C, 1, 70, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 1, cor } }), Lifetime = NumberRange.new(4, 6),
		Speed = NumberRange.new(5, 11), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(10, 10), Size = seq({ { 0, 0.6 }, { 0.5, 1.8 }, { 1, 0 } }) })
	-- planeta
	local P = C.Gol - C.Dentro * 170 + Vector3.new(0, 150, 0)
	local corPlaneta = cor:Lerp(Color3.fromRGB(255, 160, 90), 0.35)
	local planeta = s:Placa(P, 1, {
		{ Imagem = TEX.Brilho, Cor = corPlaneta, Transp = 0, Escala = 2.1 },
		{ Imagem = TEX.Anel, Cor = Color3.fromRGB(255, 230, 200), Transp = 0.25, Escala = 2.0, EscalaY = 0.5, Rot = -16 },
		{ Imagem = TEX.Esfera, Cor = corPlaneta, Transp = 0, Escala = 1 },
		{ Imagem = TEX.Brilho, Cor = BRANCO, Transp = 1, Escala = 1.3 },
	})
	local lua = s:Placa(P, 1, { { Imagem = TEX.Esfera, Cor = Color3.fromRGB(200, 210, 230) } })
	local EXPLODE = 0.56
	local explodiu = false
	local cascas, nebulosa = {}, {}
	local chuva
	s:Cada(function(t, u)
		local k = janela(u, 0, 0.4)
		if not explodiu then
			-- cresce (planeta maior)
			local tam = lerp(40, 230, suave(k))
			-- pisca, cada vez mais rápido
			local freq = lerp(0.6, 9, janela(u, 0.25, EXPLODE) ^ 1.6)
			planeta.Fase = (planeta.Fase or 0) + freq * (1 / 60)
			local pisca = janela(u, 0.22, 0.3) * (0.5 + 0.5 * math.sin(t * freq * 2 * math.pi))
			planeta.Gui.Size = UDim2.fromScale(tam * (1 + 0.05 * pisca), tam * (1 + 0.05 * pisca))
			planeta.Camadas[1].ImageTransparency = 0.25 - 0.25 * pisca
			planeta.Camadas[4].ImageTransparency = 1 - 0.85 * pisca
			planeta.Camadas[3].ImageColor3 = corPlaneta:Lerp(BRANCO, 0.6 * pisca)
			s.AmbBrilho = 0.06 * pisca
			-- lua orbitando
			local ang = t * 0.8
			lua.Ancora.CFrame = CFrame.new(P + C.Lado * math.cos(ang) * tam * 0.85 + Vector3.new(0, math.sin(ang) * tam * 0.2, 0) - C.Dentro * math.sin(ang) * 20)
			lua.Gui.Size = UDim2.fromScale(tam * 0.16, tam * 0.16)
			-- estrelas sobem
			local ke = janela(u, 0.04, 0.15)
			sobem.Rate = 700 * ke
			sobemPerto.Rate = 160 * ke
		end
		if u >= EXPLODE and not explodiu then
			explodiu = true
			s.AmbBrilho = 0
			sobem.Rate = 0
			sobemPerto.Rate = 0
			s:Flash(BRANCO, 2, 1.8)
			lua.Gui:Destroy()
			-- o planeta vira a explosão
			s:Tween(planeta.Gui, 2.4, { Size = UDim2.fromScale(1600, 1600) }, Enum.EasingStyle.Quart)
			for _, c in ipairs(planeta.Camadas) do
				if c:IsA("ImageLabel") then s:Tween(c, 2.4, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
			end
			planeta.Camadas[3].ImageColor3 = BRANCO
			-- cascas de cor em velocidades diferentes
			for i = 1, 4 do
				local casca = s:Placa(P, 1, { { Imagem = (i % 2 == 0) and TEX.Anel or TEX.Brilho, Cor = PALETA[i + 1], Transp = 0.1 } })
				s:Tween(casca.Gui, 1.4 + i * 0.6, { Size = UDim2.fromScale(500 + i * 380, 500 + i * 380) }, Enum.EasingStyle.Quart)
				s:Tween(casca.Camadas[1], 1.4 + i * 0.6, { ImageTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				table.insert(cascas, casca)
			end
			-- raios
			for i = 1, 36 do
				local a1, a2 = i / 36 * math.pi * 2, math.sin(i * 1.9) * 1.1
				local dirR = Vector3.new(math.cos(a1) * math.cos(a2), math.sin(a2), math.sin(a1) * math.cos(a2))
				local r = s:Parte({ Color = PALETA[(i % 5) + 1], Size = Vector3.new(3, 3, 14), CFrame = CFrame.lookAt(P, P + dirR) })
				s:Tween(r, 1.6, { Size = Vector3.new(0.4, 0.4, 600), CFrame = CFrame.lookAt(P + dirR * 300, P + dirR * 301), Transparency = 1 })
				Debris:AddItem(r, 1.7)
			end
			s:Estouro(P, { Texture = TEX.Estrela, Color = cseq({ { 0, BRANCO }, { 0.4, PALETA[2] }, { 1, PALETA[4] } }), Speed = NumberRange.new(80, 220),
				Lifetime = NumberRange.new(1.5, 2.6), SpreadAngle = Vector2.new(180, 180), Drag = 0.8, Size = seq({ { 0, 10 }, { 1, 0 } }) }, 420)
			-- a onda chega no campo
			local origem = Vector3.new(C.Gol.X, C.ChaoY, C.Gol.Z)
			local anel = s:Anel(origem, 64, { Color = PALETA[2], Transparency = 0.2 })
			s:Cada(function(t2)
				local kk = (t2 - T * EXPLODE - 0.3) / 2.2
				if kk < 0 then return end
				if kk >= 1 then anel.Destruir() return true end
				anel.Atualizar(C.Comp * 1.15 * (kk ^ 0.7), lerp(45, 6, kk), 1.6, lerp(0.1, 1, kk ^ 1.4), PALETA[2]:Lerp(PALETA[5], kk))
			end)
			s:Em(0.3, function() s:OndaChao(origem, PALETA[3], C.Comp * 0.9, 2) end)
			s:Luz(C.Gol + Vector3.new(0, 20, 0), PALETA[2], 60, 20, 2.5)
			-- nebulosa que fica
			for i = 1, 7 do
				local off = C.Lado * rnd(-200, 200) + Vector3.new(0, rnd(-60, 90), 0) - C.Dentro * rnd(-40, 120)
				local nb = s:Placa(P + off, rnd(260, 480), { { Imagem = TEX.Nuvem, Cor = PALETA[(i % 4) + 2], Transp = 1, Rot = rnd(0, 360) } })
				s:Em(0.8, function() s:Tween(nb.Camadas[1], 2, { ImageTransparency = 0.35 }) end)
				table.insert(nebulosa, nb)
			end
			chuva = s:EmissorCampo(C, 120, { Texture = TEX.Estrela, Color = ColorSequence.new(PALETA[2], PALETA[4]), Lifetime = NumberRange.new(4, 6),
				Speed = NumberRange.new(20, 30), EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(10, 10), Size = seq({ { 0, 1.4 }, { 1, 0.3 } }) })
		end
		if explodiu then
			local kn = janela(u, EXPLODE + 0.05, EXPLODE + 0.12) * (1 - janela(u, 0.85, 0.95))
			if chuva then chuva.Rate = 360 * kn end
			for i, nb in ipairs(nebulosa) do
				nb.Camadas[1].Rotation += 0.05 * (i % 2 == 0 and 1 or -1)
				if u >= 0.86 then nb.Camadas[1].ImageTransparency = lerp(0.35, 1, janela(u, 0.86, 0.97)) end
			end
			s.AmbTint = Color3.fromRGB(255, 225, 240):Lerp(Color3.fromRGB(220, 215, 255), janela(u, EXPLODE, 0.9))
		end
	end)
end

-- ============================================================
-- API
-- ============================================================
local sessaoAtual = nil

-- estilo = item.Estilo ("Fogos", "Neve"...), pos = bola no momento do gol,
-- cor = item.Cor, total = segundos (vem do servidor)
function E.Tocar(estilo, pos, cor, total)
	local f = Estilos[estilo]
	if not f or typeof(pos) ~= "Vector3" then return false end
	if sessaoAtual then sessaoAtual:Fim() end -- dois gols seguidos: o anterior acaba e devolve a luz
	total = math.max(tonumber(total) or 7, 4)
	local s = novaSessao(total)
	sessaoAtual = s
	local C = medirCampo(pos)
	local ok, erro = pcall(f, s, C, cor or BRANCO)
	if not ok then warn("[EfeitosDeGol] " .. tostring(estilo) .. ": " .. tostring(erro)) end
	task.delay(total + 0.6, function()
		s:Fim()
		if sessaoAtual == s then sessaoAtual = nil end
	end)
	return true
end

function E.Parar()
	if sessaoAtual then
		sessaoAtual:Fim()
		sessaoAtual = nil
	end
end

E.Estilos = Estilos
return E
