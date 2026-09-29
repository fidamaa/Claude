--[[
	ArmasVFX — ⚠️ v106

	PEDIDO: "coloque alguns efeitos visuais durante as habilidades que você
	lança das armas. O Chute Direto tem que ter um efeito de chute direto.
	Tira aquela bolinha que fica em volta dele, aquela bola azul estranha. Faz
	um VFX próprio do impacto na bola, do R, dele saindo do jeitinho que
	precisa sair. Faz bonitinho conforme o anime mostra."

	Recebe Remotes.ArmaVFX (InstinctController, no lugar da bolha de
	ForceField) e desenha:
	  • CHUTE DIRETO — o chute seco e reto do anime: clarão branco-azulado no
	    pé/bola, duas ondas de choque perpendiculares ao chute, linhas de
	    velocidade saindo pra trás e um rastro elétrico azul na bola;
	  • XEQUE-MATE — rastro vermelho-carmim na bola teleguiada + faíscas no
	    ponto do cabeceio;
	  • as outras Armas — um anel de energia no chão e faíscas subindo, na
	    cor da raridade (discreto, sem esconder o jogador); as contínuas
	    (ex.: Pique) deixam um vento leve nos pés enquanto estão ligadas.
	Tudo local, sem colisão, se apaga sozinho.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local COR_RARIDADE = {
	Common = Color3.fromRGB(220, 220, 220),
	Rare = Color3.fromRGB(110, 175, 255),
	Epic = Color3.fromRGB(190, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 60),
	Mythic = Color3.fromRGB(255, 90, 110),
}

local pasta = Instance.new("Folder")
pasta.Name = "ArmasVFX"
pasta.Parent = workspace

local function parte(tam, cf, cor, transp, material)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = material or Enum.Material.Neon
	p.Color = cor
	p.Size = tam
	p.CFrame = cf
	p.Transparency = transp
	p.Parent = pasta
	return p
end

local function anel(pos, eixo, cor, de, ate, dur, transp)
	-- cilindro fino com o eixo X na direção `eixo` (disco de frente pra ela)
	local cf = CFrame.lookAt(pos, pos + eixo) * CFrame.Angles(0, math.rad(90), 0)
	local p = parte(Vector3.new(0.12, de, de), cf, cor, transp or 0.3, Enum.Material.ForceField)
	p.Shape = Enum.PartType.Cylinder
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.12, ate, ate), Transparency = 1,
	}):Play()
	Debris:AddItem(p, dur + 0.05)
end

local function flash(pos, cor, tamanho, dur)
	local p = parte(Vector3.new(tamanho, tamanho, tamanho), CFrame.new(pos), cor, 0.1)
	p.Shape = Enum.PartType.Ball
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(tamanho * 2.6, tamanho * 2.6, tamanho * 2.6), Transparency = 1,
	}):Play()
	local l = Instance.new("PointLight")
	l.Color = cor
	l.Range = tamanho * 6
	l.Brightness = 6
	l.Parent = p
	Debris:AddItem(p, dur + 0.05)
end

local function risco(pos, dir, cor, comp, dur)
	local fina = 0.08 + math.random() * 0.06
	local p = parte(Vector3.new(fina, fina, comp), CFrame.lookAt(pos, pos + dir), cor, 0.15)
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1, Size = Vector3.new(fina * 0.3, fina * 0.3, comp * 1.8),
		CFrame = CFrame.lookAt(pos - dir * comp * 0.6, pos),
	}):Play()
	Debris:AddItem(p, dur + 0.05)
end

local function faiscas(pos, cor, n, forca)
	local a = parte(Vector3.new(0.2, 0.2, 0.2), CFrame.new(pos), cor, 1)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), cor)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.25, 0.55)
	e.Speed = NumberRange.new(forca * 0.6, forca)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Rate = 0
	e.Parent = a
	e:Emit(n)
	Debris:AddItem(a, 0.7)
end

local function rastroNaBola(cor, largura, dur)
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if not bola then return end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, largura / 2, 0)
	a0.Parent = bola
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -largura / 2, 0)
	a1.Parent = bola
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Lifetime = 0.35
	t.LightEmission = 1
	t.FaceCamera = true
	t.Color = ColorSequence.new(Color3.new(1, 1, 1), cor)
	t.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	t.WidthScale = NumberSequence.new(1, 0.1)
	t.Parent = bola
	task.delay(dur, function()
		t.Enabled = false
		Debris:AddItem(t, 0.4)
		Debris:AddItem(a0, 0.4)
		Debris:AddItem(a1, 0.4)
	end)
	return bola
end

-- ===== efeitos por Arma =====
local function chuteDireto(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if not root or not bola then return end
	local azul = Color3.fromRGB(120, 200, 255)
	-- espera o chute sair (a bola ganhar velocidade) pra pegar a direção real
	task.spawn(function()
		local inicio = os.clock()
		local pos0 = bola.Position
		while os.clock() - inicio < 0.4 and bola.AssemblyLinearVelocity.Magnitude < 20 do
			RunService.Heartbeat:Wait()
		end
		local v = bola.AssemblyLinearVelocity
		local dir = v.Magnitude > 1 and v.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local ponto = pos0:Lerp(bola.Position, 0.3)
		flash(ponto, Color3.fromRGB(230, 245, 255), 1.6, 0.22)
		anel(ponto, dir, azul, 1.5, 11, 0.3, 0.2)
		task.delay(0.06, function() anel(ponto + dir * 2, dir, Color3.new(1, 1, 1), 1, 7, 0.25, 0.35) end)
		for _ = 1, 14 do
			local lado = dir:Cross(Vector3.yAxis)
			if lado.Magnitude < 0.01 then lado = Vector3.xAxis end
			lado = lado.Unit
			local ang = math.random() * math.pi * 2
			local off = lado * math.cos(ang) * (0.6 + math.random() * 1.6) + Vector3.new(0, math.sin(ang) * (0.6 + math.random() * 1.6), 0)
			risco(ponto + off - dir * math.random() * 2, dir, azul, 3 + math.random() * 4, 0.25)
		end
		faiscas(ponto, azul, 30, 30)
		rastroNaBola(azul, 1.4, 1.2)
	end)
end

local function xequeMate(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local carmim = Color3.fromRGB(255, 50, 80)
	task.delay(0.05, function()
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		if not bola then return end
		flash(bola.Position, Color3.fromRGB(255, 200, 210), 1.4, 0.25)
		faiscas(bola.Position, carmim, 25, 22)
		rastroNaBola(carmim, 1.6, 2.2)
	end)
end

local function generico(character, cor)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pe = root.Position - Vector3.new(0, 2.8, 0)
	anel(pe, Vector3.yAxis, cor, 2, 10, 0.45, 0.35)
	faiscas(root.Position, cor, 18, 14)
end

-- contínuas (ligadas enquanto a condição vale): vento leve nos pés
local continuas = {} -- [character] = emissor
local function continua(character, cor, ligado)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local e = continuas[character]
	if ligado then
		if not e or not e.Parent then
			local a = Instance.new("Attachment")
			a.Name = "ArmaContinuaVFX"
			a.Position = Vector3.new(0, -2.6, 0)
			a.Parent = root
			e = Instance.new("ParticleEmitter")
			e.Color = ColorSequence.new(Color3.new(1, 1, 1), cor)
			e.LightEmission = 0.8
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
			e.Transparency = NumberSequence.new(0.3, 1)
			e.Lifetime = NumberRange.new(0.3, 0.6)
			e.Speed = NumberRange.new(2, 5)
			e.SpreadAngle = Vector2.new(60, 60)
			e.Rate = 25
			e.Parent = a
			continuas[character] = e
		end
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), cor)
		e.Enabled = true
	elseif e then
		e.Enabled = false
	end
end

-- ===== ⚠️ v108 — PIQUE: vento alaranjado correndo =====
-- PEDIDO: "o Pique tá muito escroto. Usa um efeito parecido com o do carrinho/
-- dash, como se ele estivesse soltando esse negócio correndo rápido, dando um
-- pique mesmo — só enquanto estiver correndo e o Pique ativo. Alaranjado, da
-- cor do Pique." Mesmo desenho do VentoVelocidade (onda de ar na arrancada,
-- linhas de velocidade e rastro), na cor do Pique.
local COR_PIQUE = Color3.fromRGB(255, 130, 60)
local piques = {} -- [character] = { Root, UltimaPos, Acumulado, Onda, Trail }

local function ondaPique(pos, dir)
	anel(pos, dir, COR_PIQUE, 2.5, 10, 0.32, 0.3)
	anel(pos - Vector3.new(0, 2.8, 0), Vector3.yAxis, COR_PIQUE, 2, 9, 0.35, 0.45)
end

local function rastroPique(root)
	local a0 = Instance.new("Attachment")
	a0.Name = "PiqueVFX0"
	a0.Position = Vector3.new(0, 1.6, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "PiqueVFX1"
	a1.Position = Vector3.new(0, -2.2, 0)
	a1.Parent = root
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Lifetime = 0.2
	tr.LightEmission = 1
	tr.FaceCamera = true
	tr.Color = ColorSequence.new(Color3.fromRGB(255, 210, 150), COR_PIQUE)
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	tr.WidthScale = NumberSequence.new(1, 0.2)
	tr.Enabled = false
	tr.Parent = root
	return tr, { a0, a1, tr }
end

local function pique(character, ligado)
	local e = piques[character]
	if ligado then
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root or (e and e.Root == root) then return end
		local tr, coisas = rastroPique(root)
		piques[character] = { Root = root, UltimaPos = root.Position, Acumulado = 0, Onda = false, Trail = tr, Coisas = coisas }
	elseif e then
		piques[character] = nil
		e.Trail.Enabled = false
		for _, x in ipairs(e.Coisas) do Debris:AddItem(x, 0.3) end
	end
end

RunService.RenderStepped:Connect(function()
	for character, e in pairs(piques) do
		local root = e.Root
		if not root.Parent then
			pique(character, false)
			continue
		end
		local pos = root.Position
		local passo = Vector3.new(pos.X - e.UltimaPos.X, 0, pos.Z - e.UltimaPos.Z)
		e.UltimaPos = pos
		local vel = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		local correndo = vel.Magnitude > 10
		e.Trail.Enabled = correndo
		if correndo and passo.Magnitude > 0.02 then
			local dir = passo.Unit
			if not e.Onda then
				e.Onda = true
				ondaPique(pos, dir)
			end
			e.Acumulado += passo.Magnitude
			local n = math.min(5, math.floor(e.Acumulado / 0.45))
			e.Acumulado -= n * 0.45
			for _ = 1, n do
				local lado = dir:Cross(Vector3.yAxis)
				lado = lado.Magnitude > 0.01 and lado.Unit or Vector3.xAxis
				local ang = math.random() * math.pi * 2
				local raio = 1.3 + math.random() * 1.6
				local off = lado * math.cos(ang) * raio + Vector3.new(0, math.sin(ang) * raio * 0.9, 0)
				risco(pos + off + dir * (math.random() * 2 - 0.5), dir, math.random() < 0.35 and Color3.fromRGB(255, 225, 180) or COR_PIQUE, 2.2 + math.random() * 2.5, 0.22)
			end
		elseif not correndo then
			e.Onda = false -- parou: a próxima arrancada estoura a onda de novo
		end
	end
end)

-- ===== ⚠️ v108 — APOSTADOR: aura dourada em volta do corpo =====
-- PEDIDO: "o Apostador pode colocar essa aura só que em volta do boneco, em
-- dourado, deixa ele um pouquinho dourado ali em volta". Enquanto a sorte está
-- valendo (os 3s do bônus): contorno dourado respirando, brilho leve no corpo
-- e faíscas douradas subindo.
local DOURADO = Color3.fromRGB(255, 205, 60)
local apostadores = {} -- [character] = { Destaque, Coisas }

local function apostador(character, ligado)
	local e = apostadores[character]
	if ligado then
		if e then return end
		local torso = character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso") or character:FindFirstChild("HumanoidRootPart")
		if not torso then return end
		local h = Instance.new("Highlight")
		h.Name = "ApostadorAura"
		h.Adornee = character
		h.FillColor = DOURADO
		h.FillTransparency = 0.82
		h.OutlineColor = Color3.fromRGB(255, 230, 120)
		h.OutlineTransparency = 0.1
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = character
		local a = Instance.new("Attachment")
		a.Name = "ApostadorVFX"
		a.Parent = torso
		local f = Instance.new("ParticleEmitter")
		f.Color = ColorSequence.new(Color3.fromRGB(255, 250, 210), DOURADO)
		f.LightEmission = 1
		f.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		f.Transparency = NumberSequence.new(0.1, 1)
		f.Lifetime = NumberRange.new(0.6, 1.1)
		f.Speed = NumberRange.new(1.5, 4)
		f.Acceleration = Vector3.new(0, 4, 0)
		f.SpreadAngle = Vector2.new(180, 180)
		f.Shape = Enum.ParticleEmitterShape.Box
		f.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		f.Rate = 22
		f.Parent = a
		local l = Instance.new("PointLight")
		l.Color = DOURADO
		l.Range = 9
		l.Brightness = 1.5
		l.Parent = torso
		apostadores[character] = { Destaque = h, Coisas = { h, a, l } }
		-- estouro ao ganhar a aposta
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, DOURADO, 2, 11, 0.5, 0.25)
			faiscas(root.Position, DOURADO, 26, 16)
		end
	elseif e then
		apostadores[character] = nil
		for _, x in ipairs(e.Coisas) do if x.Parent then x:Destroy() end end
	end
end

RunService.RenderStepped:Connect(function()
	local s = (math.sin(os.clock() * 5) + 1) / 2
	for character, e in pairs(apostadores) do
		if not character.Parent then
			apostador(character, false)
		else
			e.Destaque.FillTransparency = 0.72 + 0.16 * s
		end
	end
end)

-- ===== ⚠️ v110 — ARMAS NOVAS =====
-- Chute/passe CURVO (Tiro Destruidor — Rin; Passe do Prodígio — Sae): rastro
-- colorido na bola durante a curva, pra dar pra VER a banana.
local CURVA = {
	["Tiro Destruidor"] = Color3.fromRGB(30, 210, 190),
	["Passe do Prodígio"] = Color3.fromRGB(245, 115, 145),
}
local function curvo(character, cor)
	local root = character:FindFirstChild("HumanoidRootPart")
	task.delay(0.03, function()
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		if not bola then return end
		flash(bola.Position, Color3.new(1, 1, 1), 1.2, 0.2)
		faiscas(bola.Position, cor, 18, 16)
		rastroNaBola(cor, 1.2, 1.6)
		if root then anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 8, 0.35, 0.4) end
	end)
end
-- Armas que aceleram o TIME (Maestro do Campo, Voz de Comando): uma onda no
-- chão ao ligar, do tamanho da área que alcança os companheiros.
local DO_TIME = { ["Maestro do Campo"] = 40, ["Voz de Comando"] = 45 }

-- ===== ⚠️ v111 — ATIVAS NOVAS DAS ARMAS =====
-- PEDIDO: "tem muitas armas de status... tem que ter utilidade diversa". Cada
-- ativa nova (ver _G.ArmaAtiva_* no BallController) tem um desenho próprio:
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

local function sombra(pos, olhando, cor, dur, transp)
	-- silhueta simples (tronco + cabeça + pernas) de neon translúcido
	local cf = CFrame.lookAt(pos, pos + olhando)
	local pecas = {
		parte(Vector3.new(2, 2, 1), cf, cor, transp or 0.45),
		parte(Vector3.new(1.2, 1.2, 1.2), cf * CFrame.new(0, 1.7, 0), cor, transp or 0.45),
		parte(Vector3.new(0.9, 2, 0.9), cf * CFrame.new(-0.5, -2, 0), cor, transp or 0.45),
		parte(Vector3.new(0.9, 2, 0.9), cf * CFrame.new(0.5, -2, 0), cor, transp or 0.45),
	}
	for _, p in ipairs(pecas) do
		TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		Debris:AddItem(p, dur + 0.05)
	end
end

local function linhasDeVelocidade(root, dir, cor, n)
	local lado = dir:Cross(Vector3.yAxis)
	lado = lado.Magnitude > 0.01 and lado.Unit or Vector3.xAxis
	for _ = 1, n do
		local ang = math.random() * math.pi * 2
		local raio = 1.2 + math.random() * 1.8
		local off = lado * math.cos(ang) * raio + Vector3.new(0, math.sin(ang) * raio * 0.9, 0)
		risco(root.Position + off, dir, cor, 3 + math.random() * 3, 0.25)
	end
end

local ATIVAS = {}
ATIVAS["Pique@arranque"] = function(character, extra)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local dir = extra and typeof(extra.Dir) == "Vector3" and extra.Dir or root.CFrame.LookVector
	ondaPique(root.Position, dir)
	linhasDeVelocidade(root, dir, COR_PIQUE, 12)
	pique(character, true)
	task.delay(1.6, function() pique(character, false) end)
end
ATIVAS["Monstro do Drible@drible"] = function(character, extra)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local amarelo = Color3.fromRGB(255, 205, 40)
	local tempo = (extra and extra.Tempo) or 0.3
	for i = 1, (extra and extra.Cortes) or 3 do
		task.delay((i - 1) * tempo, function()
			if not root.Parent then return end
			-- o "monstro" do Bachira: sombra amarela atrás a cada corte
			local dir = extra and typeof(extra.Dir) == "Vector3" and extra.Dir or root.CFrame.LookVector
			sombra(root.Position, dir, amarelo, 0.5, 0.5)
			anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, amarelo, 2, 9, 0.35, 0.35)
			faiscas(root.Position - Vector3.new(0, 2.5, 0), amarelo, 14, 14)
		end)
	end
end
ATIVAS["Passo Furtivo@sumir"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local roxo = Color3.fromRGB(99, 102, 241)
	faiscas(root.Position, roxo, 22, 10)
	anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, roxo, 3, 8, 0.5, 0.4)
end
ATIVAS["Tabela@ida"] = function(character, extra)
	if not extra or typeof(extra.Ponto) ~= "Vector3" then return end
	local ciano = Color3.fromRGB(45, 212, 191)
	if extra.Sombra then
		local de = typeof(extra.De) == "Vector3" and extra.De or extra.Ponto
		sombra(extra.Ponto + Vector3.new(0, 1.5, 0), (de - extra.Ponto) * Vector3.new(1, 0, 1), ciano, 1.4, 0.4)
	end
	anel(extra.Ponto, Vector3.yAxis, ciano, 1.5, 7, 0.4, 0.35)
	rastroNaBola(ciano, 1, 0.6)
end
ATIVAS["Tabela@volta"] = function(character, extra)
	local ciano = Color3.fromRGB(45, 212, 191)
	if extra and typeof(extra.De) == "Vector3" then
		flash(extra.De, Color3.new(1, 1, 1), 1, 0.2)
		faiscas(extra.De, ciano, 14, 14)
	end
	if extra and typeof(extra.Ponto) == "Vector3" then anel(extra.Ponto, Vector3.yAxis, ciano, 1.5, 6, 0.6, 0.4) end
	rastroNaBola(ciano, 1, 0.8)
end
ATIVAS["Pulmão de Aço@folego"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local verde = Color3.fromRGB(120, 230, 150)
	anel(root.Position, Vector3.yAxis, verde, 2, 9, 0.5, 0.35)
	faiscas(root.Position, verde, 24, 9)
end
ATIVAS["Marcação Cerrada@colar"] = function(character, extra)
	local root = character:FindFirstChild("HumanoidRootPart")
	local alvo = extra and extra.Alvo
	local alvoRoot = typeof(alvo) == "Instance" and alvo:FindFirstChild("HumanoidRootPart")
	if not root or not alvoRoot then return end
	-- corrente fina ligando você ao atacante enquanto dura
	local cor = Color3.fromRGB(200, 120, 70)
	local fio = parte(Vector3.new(0.1, 0.1, 1), root.CFrame, cor, 0.3)
	local fim = os.clock() + 3
	local con
	con = RunService.RenderStepped:Connect(function()
		if os.clock() > fim or not root.Parent or not alvoRoot.Parent then
			con:Disconnect()
			fio:Destroy()
			return
		end
		local a, b = root.Position, alvoRoot.Position
		fio.Size = Vector3.new(0.1, 0.1, (b - a).Magnitude)
		fio.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -(b - a).Magnitude / 2)
	end)
	anel(alvoRoot.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 7, 0.4, 0.3)
end
ATIVAS["Leitura de Passe@interceptar"] = function(character, extra)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = Color3.fromRGB(90, 200, 230)
	local dir = extra and typeof(extra.Dir) == "Vector3" and extra.Dir or root.CFrame.LookVector
	linhasDeVelocidade(root, dir, cor, 10)
	anel(root.Position, dir, cor, 2, 8, 0.3, 0.3)
end
ATIVAS["Antecipação Fantasma@passo"] = function(character, extra)
	local roxo = Color3.fromRGB(160, 110, 230)
	if not extra or typeof(extra.De) ~= "Vector3" or typeof(extra.Para) ~= "Vector3" then return end
	local dir = extra.Para - extra.De
	-- imagens residuais pelo caminho
	for i = 0, 4 do
		sombra(extra.De:Lerp(extra.Para, i / 4), dir * Vector3.new(1, 0, 1), roxo, 0.35 + i * 0.08, 0.55 - i * 0.05)
	end
	flash(extra.Para, Color3.fromRGB(230, 210, 255), 1.2, 0.2)
end
ATIVAS["Saída Rápida@saida"] = function(character, extra)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = Color3.fromRGB(255, 190, 90)
	local dir = extra and typeof(extra.Dir) == "Vector3" and extra.Dir or root.CFrame.LookVector
	linhasDeVelocidade(root, dir, cor, 12)
	anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 9, 0.35, 0.35)
end

-- SUMIR (Passo Furtivo): pra quem é ADVERSÁRIO de quem sumiu, o corpo fica
-- quase invisível e a placa de nome some; pro time dele, meio transparente.
local sumidos = {} -- [character] = true
RunService.RenderStepped:Connect(function()
	local agora = workspace:GetServerTimeNow()
	for _, plr in ipairs(Players:GetPlayers()) do
		local ch = plr.Character
		if not ch then continue end
		local ate = ch:GetAttribute("FurtivoAte")
		local ativo = typeof(ate) == "number" and ate > agora
		if ativo or sumidos[ch] then
			local adversario = plr ~= LocalPlayer and (plr.Team == nil or LocalPlayer.Team == nil or plr.Team ~= LocalPlayer.Team)
			local alvo = ativo and (adversario and 0.93 or 0.55) or 0
			for _, d in ipairs(ch:GetDescendants()) do
				if d:IsA("BasePart") or d:IsA("Decal") then
					d.LocalTransparencyModifier = alvo
				elseif d:IsA("BillboardGui") then
					d.Enabled = not (ativo and adversario)
				elseif d:IsA("Highlight") and d.Name == "TeamHighlight" and adversario then
					d.Enabled = not ativo
				end
			end
			sumidos[ch] = ativo or nil
		end
	end
end)

Remotes.ArmaVFX.OnClientEvent:Connect(function(character, nome, raridade, ligado, duracao, extra)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return end
	local cor = COR_RARIDADE[raridade] or COR_RARIDADE.Rare
	if typeof(nome) == "string" and ATIVAS[nome] then return ATIVAS[nome](character, extra) end
	-- ⚠️ v108: Pique e Apostador têm efeito próprio (acima)
	-- ⚠️ v111: o Pique virou tecla (o efeito vem pelo "Pique@arranque")
	if nome == "Pique" then return end
	if nome == "Apostador" then return apostador(character, ligado and true or false) end
	if not ligado then
		continua(character, cor, false)
		return
	end
	if DO_TIME[nome] then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 3, DO_TIME[nome] * 2, 0.7, 0.45)
			faiscas(root.Position, cor, 20, 10)
		end
	end
	if CURVA[nome] then
		curvo(character, CURVA[nome])
	elseif nome == "Chute Direto" then
		chuteDireto(character)
	elseif nome == "Xeque-Mate" then
		xequeMate(character)
	elseif duracao == nil then
		continua(character, cor, true) -- contínua: fica até desligar
	else
		generico(character, cor)
	end
end)
