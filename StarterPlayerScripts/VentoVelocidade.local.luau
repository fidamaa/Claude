--[[
	VentoVelocidade — ⚠️ v104

	PEDIDO: "faça uma animação de dash também, e inclua um vento em volta com
	VFX, como se tivesse bem rápido atravessando vento, adicione isso também
	no carrinho."

	Escuta o mesmo Remotes.AcaoAnimada que o AnimadorProcedural usa e, nas
	ações "Dash" e "Tackle" (de qualquer jogador), desenha em volta do corpo:
	  1) uma ONDA DE AR no começo (disco de ForceField que se abre e some,
	     perpendicular ao movimento — o "estouro" da arrancada);
	  2) LINHAS DE VELOCIDADE: riscos finos e claros nascendo em volta do
	     corpo, alinhados com o movimento, que ficam parados no ar e somem
	     rápido — como o vento passando por ele;
	  3) um RASTRO de ar (Trail) atrás do corpo enquanto dura.
	A direção é medida pelo quanto o corpo andou de um quadro pro outro (o
	carrinho é empurrado pelo servidor e o dash pelo cliente, os dois caem
	aqui igual). Tudo local, sem colisão, se apaga sozinho.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local DURACAO = {
	Dash = (Config.DASH_DURATION or 0.25) + 0.12,
	Tackle = (Config.TACKLE_DASH_DURATION or 0.5) + 0.05,
	Investida = 2.5, -- ⚠️ v108: Investida Titânica (o servidor manda a duração de verdade)
}
local COR_VENTO = Color3.fromRGB(235, 245, 255)
-- ⚠️ v108: a Investida é de FOGO — vento alaranjado
local COR_POR_ACAO = { Investida = Color3.fromRGB(255, 140, 50) }
local corAtual = COR_VENTO

local pasta = Instance.new("Folder")
pasta.Name = "VentoFX"
pasta.Parent = workspace

local function parte(tamanho, cf, transp)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = corAtual
	p.Size = tamanho
	p.CFrame = cf
	p.Transparency = transp
	p.Parent = pasta
	return p
end

local function ondaDeAr(pos, dir)
	-- cilindro: eixo X = direção do movimento (disco de frente pro vento)
	local cf = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(0, math.rad(90), 0)
	local disco = parte(Vector3.new(0.15, 2.5, 2.5), cf, 0.35)
	disco.Shape = Enum.PartType.Cylinder
	disco.Material = Enum.Material.ForceField
	TweenService:Create(disco, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.15, 10, 10), Transparency = 1,
		CFrame = cf - dir * 1.5,
	}):Play()
	Debris:AddItem(disco, 0.4)

	-- anel de poeira no chão
	local chao = parte(Vector3.new(0.1, 2, 2), CFrame.new(pos - Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.5)
	chao.Shape = Enum.PartType.Cylinder
	chao.Material = Enum.Material.ForceField
	TweenService:Create(chao, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.1, 9, 9), Transparency = 1,
	}):Play()
	Debris:AddItem(chao, 0.45)
end

local function linhaDeVelocidade(pos, dir)
	local lateral = dir:Cross(Vector3.yAxis)
	if lateral.Magnitude < 0.01 then lateral = Vector3.xAxis end
	lateral = lateral.Unit
	local ang = math.random() * math.pi * 2
	local raio = 1.3 + math.random() * 1.8
	local off = lateral * math.cos(ang) * raio + Vector3.new(0, math.sin(ang) * raio * 0.9, 0)
	local comprimento = 2.5 + math.random() * 3
	local centro = pos + off + dir * (math.random() * 2.5 - 0.5)
	local fina = 0.05 + math.random() * 0.05
	local risco = parte(Vector3.new(fina, fina, comprimento), CFrame.lookAt(centro, centro + dir), 0.25 + math.random() * 0.25)
	TweenService:Create(risco, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1, Size = Vector3.new(fina * 0.3, fina * 0.3, comprimento * 1.6),
		CFrame = CFrame.lookAt(centro - dir * 1.2, centro),
	}):Play()
	Debris:AddItem(risco, 0.26)
end

local function rastro(root, duracao)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.6, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -2.2, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.18
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(corAtual) -- ⚠️ v108: laranja na Investida
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = root
	task.delay(duracao, function()
		trail.Enabled = false
		Debris:AddItem(trail, 0.3)
		Debris:AddItem(a0, 0.3)
		Debris:AddItem(a1, 0.3)
	end)
end

local ativos = {} -- [model] = { Fim, UltimaPos, Acumulado, Onda }

local function iniciar(model, chave, duracao)
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local dur = (typeof(duracao) == "number" and duracao > 0.05 and chave == "Investida") and duracao or DURACAO[chave]
	ativos[model] = { Fim = os.clock() + dur, UltimaPos = root.Position, Acumulado = 0, Onda = false, Root = root, Cor = COR_POR_ACAO[chave] or COR_VENTO }
	corAtual = ativos[model].Cor
	rastro(root, dur)
	corAtual = COR_VENTO
end

Remotes.AcaoAnimada.OnClientEvent:Connect(function(model, chave, duracao)
	if typeof(model) == "Instance" and model:IsA("Model") and DURACAO[chave] then
		iniciar(model, chave, duracao)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local agora = os.clock()
	for model, e in pairs(ativos) do
		local root = e.Root
		if agora > e.Fim or not root.Parent then
			ativos[model] = nil
			continue
		end
		local pos = root.Position
		local passo = Vector3.new(pos.X - e.UltimaPos.X, 0, pos.Z - e.UltimaPos.Z)
		e.UltimaPos = pos
		if passo.Magnitude > 0.02 then
			local dir = passo.Unit
			corAtual = e.Cor or COR_VENTO
			if not e.Onda then
				e.Onda = true
				ondaDeAr(pos, dir)
			end
			-- mais linhas quanto mais rápido (≈ 1 a cada 0.35 stud percorrido)
			e.Acumulado += passo.Magnitude
			local n = math.min(6, math.floor(e.Acumulado / 0.35))
			e.Acumulado -= n * 0.35
			for _ = 1, n do linhaDeVelocidade(pos, dir) end
			corAtual = COR_VENTO
		end
	end
end)
