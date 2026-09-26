--[[
	FieldBarrier (Script)
	LOCAL: ServerScriptService (place Game)

	⚠️ v67 — PEDIDO: "coloque uma barreira invisível para impedir que o
	jogador passe pelas linhas que demarcam a área fora do campo."

	O PONTO DELICADO: a bola PRECISA continuar saindo de campo — lateral,
	escanteio e tiro de meta dependem disso (ver OutOfBoundsController). Então
	a barreira não pode ser uma parede comum: ela tem que parar o JOGADOR e
	deixar a BOLA atravessar.

	Isso é feito com grupo de colisão próprio ("Barreira"):
	    Barreira x Players ....... COLIDE      (é o objetivo)
	    Barreira x Bola .......... NÃO colide  (lateral/escanteio continuam)
	    Barreira x Default ....... NÃO colide  (não atrapalha nada do cenário)

	As paredes são construídas por CÓDIGO a partir da hitbox do campo
	(Config.FIELD_HITBOX_NAME), e não desenhadas no Studio à mão: assim elas
	acompanham sozinhas qualquer mudança no tamanho do campo, e não existe a
	chance de ficarem desalinhadas com as linhas depois de um ajuste.
]]

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local GRUPO = "Barreira"

local function registrarGrupo()
	pcall(function() PhysicsService:RegisterCollisionGroup(GRUPO) end)
	-- Os grupos "Bola" e "Players" são criados pelo BallController/PlayerSystems.
	-- Registrar de novo é inofensivo (o pcall engole o "já existe") e garante
	-- que as regras abaixo não falhem por ordem de carregamento entre scripts.
	pcall(function() PhysicsService:RegisterCollisionGroup("Bola") end)
	pcall(function() PhysicsService:RegisterCollisionGroup("Players") end)

	pcall(function() PhysicsService:CollisionGroupSetCollidable(GRUPO, "Players", true) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(GRUPO, "Bola", false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(GRUPO, "Default", false) end)
	pcall(function() PhysicsService:CollisionGroupSetCollidable(GRUPO, GRUPO, false) end)
end

local function construir()
	local campo = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
	if not campo then
		warn("🧱 [Barreira] não achei a hitbox do campo ('" .. tostring(Config.FIELD_HITBOX_NAME) .. "') — barreira não construída.")
		return
	end

	local antiga = workspace:FindFirstChild("BarreiraDoCampo")
	if antiga then antiga:Destroy() end

	local cf, tamanho
	if campo:IsA("BasePart") then
		cf, tamanho = campo.CFrame, campo.Size
	else
		cf, tamanho = campo:GetBoundingBox()
	end

	local pasta = Instance.new("Folder")
	pasta.Name = "BarreiraDoCampo"
	pasta.Parent = workspace

	local margem = Config.FIELD_BARRIER_MARGIN
	local altura = Config.FIELD_BARRIER_HEIGHT
	local espessura = Config.FIELD_BARRIER_THICKNESS

	-- A hitbox do campo é um volume ALTO (centro bem acima do gramado), então
	-- a base vem do fundo dela, não do centro — senão as paredes nasceriam
	-- flutuando muito acima do chão.
	local baseY = cf.Position.Y - tamanho.Y / 2
	local meioY = baseY + altura / 2

	local meioX = tamanho.X / 2 + margem
	local meioZ = tamanho.Z / 2 + margem

	-- Quatro paredes, cobrindo os cantos de propósito (as laterais são mais
	-- longas que o campo): sem isso sobraria uma fresta em cada canto.
	local paredes = {
		{ Vector3.new(espessura, altura, meioZ * 2 + espessura * 2), Vector3.new( meioX, 0,     0) },
		{ Vector3.new(espessura, altura, meioZ * 2 + espessura * 2), Vector3.new(-meioX, 0,     0) },
		{ Vector3.new(meioX * 2 + espessura * 2, altura, espessura), Vector3.new(0,      0,  meioZ) },
		{ Vector3.new(meioX * 2 + espessura * 2, altura, espessura), Vector3.new(0,      0, -meioZ) },
	}

	for i, p in ipairs(paredes) do
		local parede = Instance.new("Part")
		parede.Name = "Parede" .. i
		parede.Size = p[1]
		parede.Anchored = true
		parede.CanCollide = true
		parede.CanQuery = false -- não aparece em raycast: não atrapalha a mira do chute
		parede.CanTouch = false
		parede.CastShadow = false
		parede.Transparency = 1
		parede.CollisionGroup = GRUPO
		parede.CFrame = cf * CFrame.new(p[2].X, meioY - cf.Position.Y, p[2].Z)
		parede.Parent = pasta
	end

	print(string.format(
		"🧱 [Barreira] 4 paredes de %.0f studs de altura construídas em volta do campo (margem %.0f).",
		altura, margem))
end

registrarGrupo()
construir()
