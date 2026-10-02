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
ATIVAS["Chapéu@chapeu"] = function(character, extra)
	local verde = Color3.fromRGB(120, 230, 150)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, verde, 2, 7, 0.35, 0.4) end
	rastroNaBola(verde, 1, (extra and extra.Tempo) or 0.9)
	-- marca onde a bola vai cair, pra você correr pra lá
	if extra and typeof(extra.Para) == "Vector3" then
		local marca = parte(Vector3.new(0.12, 5, 5), CFrame.new(extra.Para - Vector3.new(0, 0.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), verde, 0.35, Enum.Material.ForceField)
		marca.Shape = Enum.PartType.Cylinder
		Debris:AddItem(marca, (extra.Tempo or 0.9) + 0.2)
	end
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

-- ===== ⚠️ v116 — TODAS AS ARMAS COM EFEITO PRÓPRIO =====
-- PEDIDO: "armas sem efeito visual (Ego do Rei chutando de fora da área) —
-- conferir TODAS, inclusive as antigas". Antes só umas 12 das 31 Armas tinham
-- desenho próprio; as outras (Ego do Rei, Zona de Ouro, Olho de Predador,
-- Xerife, Muro Duplo, Reflexo, Paredão…) caíam no "generico": um aneizinho no
-- chão que some em 0,45s e passava batido. Agora cada Arma tem uma assinatura
-- visível: as de CHUTE/PASSE acompanham a bola (clarão + rastro + marca no ponto
-- do chute), as de DESARME marcam o chão, as de GOLEIRO aparecem no corpo e as
-- CONTÍNUAS deixam uma aura própria enquanto valem.
local COR_ARMA = {
	["Ego do Rei"] = Color3.fromRGB(168, 85, 247),
	["Zona de Ouro"] = Color3.fromRGB(255, 205, 60),
	["Olho de Predador"] = Color3.fromRGB(255, 60, 70),
	["Passe Preciso"] = Color3.fromRGB(110, 200, 255),
	["Lançamento Perfeito"] = Color3.fromRGB(255, 170, 70),
	["Xerife"] = Color3.fromRGB(255, 215, 80),
	["Muro Duplo"] = Color3.fromRGB(255, 140, 60),
	["Leitor de Almas"] = Color3.fromRGB(190, 150, 255),
	["Desarme Relâmpago"] = Color3.fromRGB(255, 240, 90),
	["Reflexo"] = Color3.fromRGB(90, 230, 255),
	["Corpo Elástico"] = Color3.fromRGB(190, 110, 255),
	["Paredão"] = Color3.fromRGB(150, 215, 255),
	["Domínio"] = Color3.fromRGB(120, 255, 190),
	["A Zona"] = Color3.fromRGB(150, 235, 255),
	["Defesa Zumbi"] = Color3.fromRGB(110, 220, 90),
	["Última Barreira"] = Color3.fromRGB(110, 160, 255),
	["Sexto Sentido"] = Color3.fromRGB(255, 120, 220),
	["Metavisão"] = Color3.fromRGB(90, 255, 240),
	["Maestro do Campo"] = Color3.fromRGB(255, 215, 90),
	["Voz de Comando"] = Color3.fromRGB(120, 220, 255),
	["Marcação Cerrada"] = Color3.fromRGB(200, 120, 70),
	["Leitura de Passe"] = Color3.fromRGB(90, 200, 230),
	["Antecipação Fantasma"] = Color3.fromRGB(160, 110, 230),
	["Saída Rápida"] = Color3.fromRGB(255, 190, 90),
	["Passo Furtivo"] = Color3.fromRGB(99, 102, 241),
	["Tabela"] = Color3.fromRGB(45, 212, 191),
}
local BRANCO = Color3.new(1, 1, 1)

local function pilarDeLuz(pos, cor, altura, largura, dur)
	local p = parte(Vector3.new(altura, largura, largura), CFrame.new(pos + Vector3.new(0, altura / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), cor, 0.3)
	p.Shape = Enum.PartType.Cylinder
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(altura * 1.25, largura * 0.2, largura * 0.2), Transparency = 1,
	}):Play()
	Debris:AddItem(p, dur + 0.05)
end

-- retículo de mira se fechando em cima do ponto (Olho de Predador, Zona de Ouro)
local function miraEm(pos, cor, cor2)
	local cam = workspace.CurrentCamera
	local eixo = cam and (cam.CFrame.Position - pos) or Vector3.yAxis
	eixo = eixo.Magnitude > 0.01 and eixo.Unit or Vector3.yAxis
	for k = 1, 3 do
		task.delay((k - 1) * 0.07, function()
			anel(pos, eixo, k == 3 and cor2 or cor, 11 - k * 1.5, 1.8, 0.32, 0.15)
		end)
	end
	local lado = eixo:Cross(Vector3.yAxis)
	lado = lado.Magnitude > 0.01 and lado.Unit or Vector3.xAxis
	local cima = lado:Cross(eixo).Unit
	for _, d in ipairs({ lado, -lado, cima, -cima }) do
		local p = parte(Vector3.new(0.14, 0.14, 4.5), CFrame.lookAt(pos + d * 5.5, pos + d * 0.6), cor2, 0.05)
		TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.lookAt(pos + d * 1.6, pos), Transparency = 1,
		}):Play()
		Debris:AddItem(p, 0.35)
	end
	flash(pos, cor2, 1, 0.25)
end

-- pentagrama no chão (a estrela do Xerife)
local function estrelaNoChao(pos, cor, raio, dur)
	local pts = {}
	for i = 0, 4 do
		local a = math.rad(90 + i * 72)
		pts[i] = pos + Vector3.new(math.cos(a) * raio, 0, math.sin(a) * raio)
	end
	for i = 0, 4 do
		local a, b = pts[i], pts[(i + 2) % 5]
		local p = parte(Vector3.new(0.4, 0.12, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), cor, 0.05)
		TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		Debris:AddItem(p, dur + 0.05)
	end
	anel(pos, Vector3.yAxis, cor, raio * 1.4, raio * 2.6, dur, 0.3)
end

-- parede de energia que sobe do chão e some
local function muroDeEnergia(pos, dir, cor, larg, alt, dur)
	local cf = CFrame.lookAt(pos, pos + dir)
	local p = parte(Vector3.new(larg, 0.3, 0.5), cf * CFrame.new(0, 0.15, 0), cor, 0.45, Enum.Material.ForceField)
	local topo = parte(Vector3.new(larg, 0.2, 0.7), cf * CFrame.new(0, 0.15, 0), cor, 0.05)
	local info = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(larg, alt, 0.5), CFrame = cf * CFrame.new(0, alt / 2, 0) }):Play()
	TweenService:Create(topo, info, { CFrame = cf * CFrame.new(0, alt, 0) }):Play()
	task.delay(dur, function()
		TweenService:Create(p, TweenInfo.new(0.35), { Transparency = 1 }):Play()
		TweenService:Create(topo, TweenInfo.new(0.35), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(p, dur + 0.45)
	Debris:AddItem(topo, dur + 0.45)
end

-- coluna de partículas subindo do corpo (espíritos, fumaça, brilho)
local function emissorNoCorpo(pai, props)
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 0.8
	e.LightInfluence = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = pai
	return e
end

-- chute/passe: marca no ponto onde a bola sai + clarão + rastro colorido atrás dela
local function chuteDaArma(character, cor, cor2, dur, comAneis)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	task.spawn(function()
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		if not bola then return end
		local inicio = os.clock()
		while os.clock() - inicio < 0.45 and bola.AssemblyLinearVelocity.Magnitude < 20 do
			RunService.Heartbeat:Wait()
		end
		local v = bola.AssemblyLinearVelocity
		local dir = v.Magnitude > 1 and v.Unit or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local ponto = bola.Position
		flash(ponto, BRANCO, 1.6, 0.22)
		if comAneis ~= false then
			anel(ponto, dir, cor, 1.5, 10, 0.3, 0.2)
			task.delay(0.07, function() anel(ponto + dir * 2, dir, cor2, 1, 7, 0.25, 0.3) end)
		end
		local lado = dir:Cross(Vector3.yAxis)
		lado = lado.Magnitude > 0.01 and lado.Unit or Vector3.xAxis
		for _ = 1, 12 do
			local ang = math.random() * math.pi * 2
			local raio = 0.6 + math.random() * 1.6
			local off = lado * math.cos(ang) * raio + Vector3.new(0, math.sin(ang) * raio, 0)
			risco(ponto + off - dir * math.random() * 2, dir, math.random() < 0.4 and cor2 or cor, 3 + math.random() * 4, 0.25)
		end
		faiscas(ponto, cor, 26, 26)
		rastroNaBola(cor, 1.4, dur or 1.6)
	end)
end

local function aneisNoChao(root, cor, cor2)
	local pe = root.Position - Vector3.new(0, 2.8, 0)
	anel(pe, Vector3.yAxis, cor, 2, 11, 0.5, 0.3)
	task.delay(0.1, function() anel(pe, Vector3.yAxis, cor2, 1, 7, 0.4, 0.4) end)
end

-- Armas de EVENTO (disparam uma vez, no gatilho): nome -> function(character, cor, duracao)
local FX_ARMA = {}

-- EGO DO REI: coroa roxa e dourada nasce em cima da cabeça e sobe, aura de rei no chão
-- e a bola sai com rastro roxo — "você não passa, chuta".
FX_ARMA["Ego do Rei"] = function(character)
	local roxo, ouro = COR_ARMA["Ego do Rei"], Color3.fromRGB(255, 215, 90)
	local root = character:FindFirstChild("HumanoidRootPart")
	local cabeca = character:FindFirstChild("Head") or root
	if not cabeca then return end
	local base = cabeca.Position + Vector3.new(0, 2.2, 0)
	local pecas = {}
	local aro = parte(Vector3.new(0.35, 2.2, 2.2), CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90)), ouro, 0.05)
	aro.Shape = Enum.PartType.Cylinder
	table.insert(pecas, aro)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local off = Vector3.new(math.cos(a) * 1.0, 0.65, math.sin(a) * 1.0)
		table.insert(pecas, parte(Vector3.new(0.4, 1.2, 0.4), CFrame.new(base + off), i % 2 == 0 and ouro or roxo, 0.05))
		local joia = parte(Vector3.new(0.34, 0.34, 0.34), CFrame.new(base + off + Vector3.new(0, 0.8, 0)), roxo, 0)
		joia.Shape = Enum.PartType.Ball
		table.insert(pecas, joia)
	end
	for _, p in ipairs(pecas) do
		TweenService:Create(p, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = p.CFrame + Vector3.new(0, 1.8, 0), Transparency = 1,
		}):Play()
		Debris:AddItem(p, 1.3)
	end
	flash(base, ouro, 1.6, 0.3)
	if root then
		aneisNoChao(root, roxo, ouro)
		pilarDeLuz(root.Position - Vector3.new(0, 2.8, 0), roxo, 14, 3.4, 0.6)
	end
	chuteDaArma(character, roxo, ouro, 2.0)
end

-- ZONA DE OURO: mira dourada fecha no ponto de chute + marca no chão
FX_ARMA["Zona de Ouro"] = function(character)
	local ouro, claro = COR_ARMA["Zona de Ouro"], Color3.fromRGB(255, 245, 190)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then
		aneisNoChao(root, ouro, claro)
		miraEm(root.Position - Vector3.new(0, 2.6, 0), ouro, claro)
	end
	chuteDaArma(character, ouro, claro, 1.8)
end

-- OLHO DE PREDADOR: retículo vermelho trava na bola
FX_ARMA["Olho de Predador"] = function(character)
	local vermelho, rosa = COR_ARMA["Olho de Predador"], Color3.fromRGB(255, 190, 190)
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if bola then miraEm(bola.Position, vermelho, rosa) end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, vermelho, 2, 9, 0.4, 0.35) end
	chuteDaArma(character, vermelho, rosa, 1.8, false)
end

FX_ARMA["Passe Preciso"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if root then aneisNoChao(root, COR_ARMA["Passe Preciso"], BRANCO) end
	chuteDaArma(character, COR_ARMA["Passe Preciso"], BRANCO, 1.5, false)
end

FX_ARMA["Lançamento Perfeito"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local cor = COR_ARMA["Lançamento Perfeito"]
	if root then
		aneisNoChao(root, cor, BRANCO)
		pilarDeLuz(root.Position - Vector3.new(0, 2.8, 0), cor, 9, 2.4, 0.5)
	end
	chuteDaArma(character, cor, BRANCO, 2.2)
end

-- XERIFE: estrela de xerife dourada no chão
FX_ARMA["Xerife"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pe = root.Position - Vector3.new(0, 2.7, 0)
	estrelaNoChao(pe, COR_ARMA["Xerife"], 4.2, 0.9)
	pilarDeLuz(pe, COR_ARMA["Xerife"], 8, 2, 0.5)
	faiscas(root.Position, COR_ARMA["Xerife"], 20, 14)
end

-- MURO DUPLO: duas paredes de energia dos lados do carrinho
FX_ARMA["Muro Duplo"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = COR_ARMA["Muro Duplo"]
	local pe = root.Position - Vector3.new(0, 2.7, 0)
	local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	frente = frente.Magnitude > 0.01 and frente.Unit or Vector3.new(0, 0, -1)
	local lado = frente:Cross(Vector3.yAxis).Unit
	muroDeEnergia(pe + lado * 3.4 + frente * 1.5, frente, cor, 5, 6, 0.9)
	muroDeEnergia(pe - lado * 3.4 + frente * 1.5, frente, cor, 5, 6, 0.9)
	anel(pe, Vector3.yAxis, cor, 2, 10, 0.45, 0.3)
end

-- LEITOR DE ALMAS: espíritos brancos e roxos sobem do chão
FX_ARMA["Leitor de Almas"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor, claro = COR_ARMA["Leitor de Almas"], Color3.fromRGB(240, 235, 255)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, -2.6, 0)
	a.Parent = root
	local e = emissorNoCorpo(a, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(claro, cor),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(6, 10), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top, Rate = 60,
		Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	})
	task.delay(0.6, function() e.Enabled = false end)
	Debris:AddItem(a, 2)
	anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 12, 0.6, 0.3)
	pilarDeLuz(root.Position - Vector3.new(0, 2.8, 0), claro, 12, 2.6, 0.7)
end

-- DESARME RELÂMPAGO: raios amarelos no gancho do pé
FX_ARMA["Desarme Relâmpago"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = COR_ARMA["Desarme Relâmpago"]
	local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	frente = frente.Magnitude > 0.01 and frente.Unit or Vector3.new(0, 0, -1)
	flash(root.Position + frente * 2, BRANCO, 1.4, 0.2)
	for i = 1, 7 do
		local ang = math.rad((i - 4) * 14)
		local dir = (CFrame.Angles(0, ang, 0) * CFrame.lookAt(Vector3.zero, frente)).LookVector
		risco(root.Position - Vector3.new(0, 1.5, 0) + dir * 1.2, dir, i % 2 == 0 and BRANCO or cor, 6 + math.random() * 4, 0.28)
	end
	anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 10, 0.4, 0.25)
	faiscas(root.Position, cor, 24, 24)
end

-- GOLEIRO: REFLEXO — faíscas ciano em estrela na hora do mergulho
FX_ARMA["Reflexo"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = COR_ARMA["Reflexo"]
	flash(root.Position, BRANCO, 1.8, 0.2)
	for i = 1, 10 do
		local ang = (i / 10) * math.pi * 2
		local dir = Vector3.new(math.cos(ang), math.random() * 0.6 - 0.2, math.sin(ang)).Unit
		risco(root.Position + dir * 1.4, dir, i % 2 == 0 and BRANCO or cor, 3.5, 0.25)
	end
	anel(root.Position, root.CFrame.LookVector, cor, 2, 9, 0.3, 0.25)
end

-- GOLEIRO: CORPO ELÁSTICO — anéis roxos esticando na direção do mergulho
FX_ARMA["Corpo Elástico"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = COR_ARMA["Corpo Elástico"]
	local dir = root.AssemblyLinearVelocity
	dir = dir.Magnitude > 3 and dir.Unit or root.CFrame.LookVector
	for i = 1, 4 do
		task.delay((i - 1) * 0.06, function()
			if root.Parent then anel(root.Position + dir * (i * 1.6), dir, i % 2 == 0 and BRANCO or cor, 1.5, 8 - i, 0.35, 0.2) end
		end)
	end
	linhasDeVelocidade(root, dir, cor, 12)
end

-- GOLEIRO: PAREDÃO — uma parede de energia enorme na frente do gol
FX_ARMA["Paredão"] = function(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local cor = COR_ARMA["Paredão"]
	local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	frente = frente.Magnitude > 0.01 and frente.Unit or Vector3.new(0, 0, -1)
	local pe = root.Position - Vector3.new(0, 2.7, 0) + frente * 3.5
	muroDeEnergia(pe, -frente, cor, 14, 8, 1.0)
	anel(root.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 12, 0.5, 0.3)
	faiscas(root.Position + frente * 3, cor, 22, 16)
end

-- DOMÍNIO: a bola no ar é "laçada" por um anel verde
FX_ARMA["Domínio"] = function(character)
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	local cor = COR_ARMA["Domínio"]
	if bola then
		anel(bola.Position, Vector3.yAxis, cor, 1.5, 7, 0.4, 0.2)
		anel(bola.Position, Vector3.xAxis, BRANCO, 1, 5, 0.35, 0.3)
		faiscas(bola.Position, cor, 16, 12)
	end
end

-- ===== CONTÍNUAS: aura própria enquanto a Arma vale =====
local auras = {} -- [character] = { [nome] = { coisas } }
local CONT_FX = {}

local function coisaDoCorpo(character, nomeParte)
	local p = character:FindFirstChild(nomeParte)
	if p then return p end
	return character:FindFirstChild("HumanoidRootPart")
end

local function anexo(parteBase, y)
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, y or 0, 0)
	a.Parent = parteBase
	return a
end

CONT_FX["A Zona"] = function(character, raiz, coisas)
	local cor = COR_ARMA["A Zona"]
	-- anel de 18 studs (o raio em que os adversários ficam lentos) preso ao chão do jogador
	local anelFixo = parte(Vector3.new(0.12, 36, 36), raiz.CFrame * CFrame.new(0, -2.8, 0) * CFrame.Angles(0, 0, math.rad(90)), cor, 0.7, Enum.Material.ForceField)
	anelFixo.Shape = Enum.PartType.Cylinder
	anelFixo.Anchored = false
	anelFixo.Massless = true
	local w = Instance.new("WeldConstraint")
	w.Part0 = raiz
	w.Part1 = anelFixo
	w.Parent = anelFixo
	table.insert(coisas, anelFixo)
	local a = anexo(coisaDoCorpo(character, "UpperTorso"), 0)
	table.insert(coisas, a)
	table.insert(coisas, emissorNoCorpo(a, {
		Color = ColorSequence.new(BRANCO, cor), Rate = 14, Lifetime = NumberRange.new(0.7, 1.2),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 3, 0),
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume,
	}))
	-- entrada na Zona: onda grande que vai até os 18 studs
	anel(raiz.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 2, 36, 0.8, 0.3)
	flash(raiz.Position, BRANCO, 2, 0.35)
end

CONT_FX["Defesa Zumbi"] = function(character, raiz, coisas)
	local a = anexo(raiz, -1.2)
	table.insert(coisas, a)
	table.insert(coisas, emissorNoCorpo(a, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(140, 235, 90), Color3.fromRGB(40, 90, 40)), LightEmission = 0.2,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(1, 3), Rate = 14, SpreadAngle = Vector2.new(40, 40),
		Acceleration = Vector3.new(0, 2, 0),
	}))
	anel(raiz.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, COR_ARMA["Defesa Zumbi"], 2, 10, 0.6, 0.35)
end

CONT_FX["Última Barreira"] = function(character, raiz, coisas)
	local cor = COR_ARMA["Última Barreira"]
	local a = anexo(coisaDoCorpo(character, "UpperTorso"), 0)
	table.insert(coisas, a)
	table.insert(coisas, emissorNoCorpo(a, {
		Color = ColorSequence.new(BRANCO, cor), Rate = 12, Lifetime = NumberRange.new(0.5, 0.9),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	}))
	-- arco de 5 placas de energia na frente do jogador
	local frente = Vector3.new(raiz.CFrame.LookVector.X, 0, raiz.CFrame.LookVector.Z)
	frente = frente.Magnitude > 0.01 and frente.Unit or Vector3.new(0, 0, -1)
	local pe = raiz.Position - Vector3.new(0, 2.7, 0)
	for i = -2, 2 do
		local dir = (CFrame.Angles(0, math.rad(i * 28), 0) * CFrame.lookAt(Vector3.zero, frente)).LookVector
		muroDeEnergia(pe + dir * 5, dir, cor, 3.4, 5, 0.9)
	end
	anel(pe, Vector3.yAxis, cor, 2, 12, 0.5, 0.3)
end

CONT_FX["Sexto Sentido"] = function(character, raiz, coisas)
	local cor = COR_ARMA["Sexto Sentido"]
	local a = anexo(coisaDoCorpo(character, "Head"), 0)
	table.insert(coisas, a)
	table.insert(coisas, emissorNoCorpo(a, {
		Color = ColorSequence.new(BRANCO, cor), Rate = 10, Lifetime = NumberRange.new(0.6, 1),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 2, 0),
	}))
	local cabeca = coisaDoCorpo(character, "Head")
	anel(cabeca.Position, Vector3.yAxis, cor, 1.5, 9, 0.6, 0.3)
	anel(cabeca.Position, Vector3.xAxis, BRANCO, 1, 6, 0.5, 0.4)
end

CONT_FX["Metavisão"] = function(character, raiz, coisas)
	local cor = COR_ARMA["Metavisão"]
	local a = anexo(coisaDoCorpo(character, "Head"), 0.2)
	table.insert(coisas, a)
	table.insert(coisas, emissorNoCorpo(a, {
		Color = ColorSequence.new(BRANCO, cor), Rate = 8, Lifetime = NumberRange.new(0.5, 0.9),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180),
	}))
	local cabeca = coisaDoCorpo(character, "Head")
	anel(cabeca.Position, Vector3.yAxis, cor, 1.5, 7, 0.5, 0.35)
end

local function auraDeEquipe(nome, raio)
	return function(character, raiz, coisas)
		local cor = COR_ARMA[nome]
		local a = anexo(coisaDoCorpo(character, "UpperTorso"), 0)
		table.insert(coisas, a)
		table.insert(coisas, emissorNoCorpo(a, {
			Color = ColorSequence.new(BRANCO, cor), Rate = 10, Lifetime = NumberRange.new(0.6, 1),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
			Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 3, 0),
		}))
		anel(raiz.Position - Vector3.new(0, 2.8, 0), Vector3.yAxis, cor, 3, raio * 2, 0.7, 0.45)
		faiscas(raiz.Position, cor, 20, 10)
	end
end
CONT_FX["Maestro do Campo"] = auraDeEquipe("Maestro do Campo", 40)
CONT_FX["Voz de Comando"] = auraDeEquipe("Voz de Comando", 45)

local contFx
contFx = function(character, nome, ligado)
	local mapa = auras[character]
	if not mapa then
		mapa = {}
		auras[character] = mapa
	end
	local atual = mapa[nome]
	if not ligado then
		if atual then
			mapa[nome] = nil
			for _, x in ipairs(atual) do
				if x.Parent then x:Destroy() end
			end
		end
		return
	end
	if atual then return end
	local raiz = character:FindFirstChild("HumanoidRootPart")
	if not raiz then return end
	local coisas = {}
	mapa[nome] = coisas
	local ok, erro = pcall(CONT_FX[nome], character, raiz, coisas)
	if not ok then warn("[ArmasVFX] " .. nome .. ": " .. tostring(erro)) end
	-- personagem saiu (fim de partida/respawn): leva a aura junto
	character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then contFx(character, nome, false) end
	end)
end

local function aoArmaVFX(character, nome, raridade, ligado, duracao, extra)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return end
	local cor = COR_ARMA[nome] or COR_RARIDADE[raridade] or COR_RARIDADE.Rare
	if typeof(nome) == "string" and ATIVAS[nome] then return ATIVAS[nome](character, extra) end
	-- ⚠️ v108: Pique e Apostador têm efeito próprio (acima)
	-- ⚠️ v111: o Pique virou tecla (o efeito vem pelo "Pique@arranque")
	if nome == "Pique" then return end
	if nome == "Apostador" then return apostador(character, ligado and true or false) end
	-- ⚠️ v116: Armas contínuas com aura própria (A Zona, Defesa Zumbi, Última Barreira…)
	if typeof(nome) == "string" and CONT_FX[nome] then
		continua(character, cor, ligado and true or false) -- vento leve nos pés, na cor da Arma
		contFx(character, nome, ligado and true or false)
		return
	end
	if not ligado then
		continua(character, cor, false)
		return
	end
	-- ⚠️ v116: Armas de evento com assinatura própria (Ego do Rei, Xerife, Paredão…)
	if typeof(nome) == "string" and FX_ARMA[nome] then
		local ok, erro = pcall(FX_ARMA[nome], character, cor, duracao)
		if not ok then warn("[ArmasVFX] " .. nome .. ": " .. tostring(erro)) end
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
end
Remotes.ArmaVFX.OnClientEvent:Connect(aoArmaVFX)
-- ⚠️ v112: o replay de gol repete os efeitos de Arma no fantasma
_G.ArmaVFXLocal = aoArmaVFX
