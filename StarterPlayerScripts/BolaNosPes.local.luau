--[[
	BolaNosPes — ⚠️ v104

	PEDIDO: "a maior parte dos jogos de futebol, e é o que dá segurança pro
	jogador, é a bola estar na sua frente, como se fosse sob o seu domínio...
	ele esteja se movendo mesmo assim, a bola está ali na frente dele, nos pés
	dele. Aí a animação de drible vai encaixar, e a de chute também vai estar
	sempre colidindo com o pé dele."

	Antes: o SERVIDOR perseguia a bola atrás do jogador (velocidade na
	direção de um alvo). O corpo do jogador chega no servidor atrasado e a
	bola volta pro cliente atrasada de novo — correndo, ela ficava metros
	atrás ou do lado, e virar rápido a jogava pra longe.

	Agora: com a posse, o servidor entrega a FÍSICA da bola pra este cliente
	(SetNetworkOwner — ver definirDonoDeRede em BallController) e este script
	a coloca todo quadro colada na frente dos pés:
	  • sempre na frente do CORPO (LookVector), andando pra qualquer lado;
	  • no chão (raycast), ou na altura dos pés quando pula;
	  • correndo, vai e volta um pouquinho (os toques de condução) e rola
	    na velocidade certa.
	A bola não colide com jogadores (grupo de colisão "Bola"), então ela
	nunca empurra o próprio dono.

	Perdeu a posse (chute, carrinho, passe), o servidor retoma a bola na hora
	e este script para de mexer nela.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

if not Config.BOLA_NOS_PES_LIGADO then return end

local player = Players.LocalPlayer
local ball = workspace:WaitForChild(Config.BALL_NAME)

local comPosse = false
local rotacao = CFrame.identity -- giro acumulado da bola (ela rola enquanto conduz)
local ultimaPos = nil
local fase = 0

Remotes.PossessionChanged.OnClientEvent:Connect(function(quem, ganhou)
	if quem == player then
		comPosse = ganhou and true or false
	elseif ganhou then
		comPosse = false
	end
	ultimaPos = nil
end)

local paramsChao = RaycastParams.new()
paramsChao.FilterType = Enum.RaycastFilterType.Exclude
paramsChao.RespectCanCollide = true

-- distância do centro do HumanoidRootPart até a sola do pé
local function alturaDosPes(character, humanoid, root)
	if humanoid.RigType == Enum.HumanoidRigType.R15 or (humanoid.HipHeight or 0) > 0.1 then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	local tronco = character:FindFirstChild("Torso")
	local perna = character:FindFirstChild("Left Leg")
	return (tronco and tronco.Size.Y / 2 or root.Size.Y / 2) + (perna and perna.Size.Y or 2)
end

RunService:BindToRenderStep("BolaNosPes", Enum.RenderPriority.Character.Value + 1, function(dt)
	if not comPosse or ball.Anchored or _G.HissatsuCutsceneLocal then
		ultimaPos = nil
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return end

	local raio = ball.Size.Y / 2
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)

	local vel = root.AssemblyLinearVelocity
	local velPlana = Vector3.new(vel.X, 0, vel.Z)
	local rapidez = velPlana.Magnitude

	-- toques de condução: só correndo, mais fortes quanto mais rápido
	local intensidade = math.clamp((rapidez - 4) / 16, 0, 1)
	fase += dt * Config.BOLA_NOS_PES_TOQUE_FREQ * (0.6 + 0.4 * intensidade)
	local toque = Config.BOLA_NOS_PES_TOQUE * intensidade * (0.5 + 0.5 * math.sin(fase))

	-- ⚠️ v105: goleiro dentro da área segura a bola NAS MÃOS (peito)
	if character:GetAttribute("BolaNaMao") == true then
		local alvoMao = root.Position + look * 1.45 + Vector3.new(0, 0.35, 0)
		ball.CFrame = CFrame.new(alvoMao) * rotacao
		ball.AssemblyLinearVelocity = vel
		ball.AssemblyAngularVelocity = Vector3.zero
		ultimaPos = nil
		return
	end

	local frente = Config.BOLA_NOS_PES_DISTANCIA + toque
	local xz = root.Position + look * frente

	-- altura: pés do jogador; no chão, apoiada no gramado
	local pesY = root.Position.Y - alturaDosPes(character, humanoid, root)
	local y = pesY + raio
	paramsChao.FilterDescendantsInstances = { character, ball }
	local hit = workspace:Raycast(Vector3.new(xz.X, root.Position.Y, xz.Z), Vector3.new(0, -(root.Position.Y - pesY) - 4, 0), paramsChao)
	local noAr = humanoid.FloorMaterial == Enum.Material.Air
	if hit then
		local yChao = hit.Position.Y + raio
		if not noAr or y < yChao then y = yChao end
	end
	local alvo = Vector3.new(xz.X, y, xz.Z)

	-- rolar: gira pelo caminho percorrido (eixo perpendicular ao movimento)
	if ultimaPos then
		local passo = Vector3.new(alvo.X - ultimaPos.X, 0, alvo.Z - ultimaPos.Z)
		local d = passo.Magnitude
		if d > 1e-3 and d < 5 then
			local eixo = Vector3.yAxis:Cross(passo.Unit)
			rotacao = CFrame.fromAxisAngle(eixo, d / raio) * rotacao
		end
	end
	ultimaPos = alvo

	-- ⚠️ v110: o giro é acumulado quadro a quadro (multiplicação de CFrames) e o
	-- erro numérico vai deformando a rotação — renormaliza sempre, e nunca manda
	-- NaN pra bola (ela "sumia" do campo)
	rotacao = rotacao:Orthonormalize()
	local rx, ry, rz = rotacao:ToEulerAnglesXYZ()
	if rx ~= rx or ry ~= ry or rz ~= rz then rotacao = CFrame.identity end
	if alvo.X ~= alvo.X or alvo.Y ~= alvo.Y or alvo.Z ~= alvo.Z then
		ultimaPos = nil
		return
	end

	ball.CFrame = CFrame.new(alvo) * rotacao
	-- velocidade igual à do corpo: a física do quadro leva a bola junto (e
	-- quem vê de fora recebe o movimento suave, sem "teleportes")
	ball.AssemblyLinearVelocity = Vector3.new(vel.X, noAr and vel.Y or 0, vel.Z)
	if rapidez > 0.5 then
		ball.AssemblyAngularVelocity = Vector3.yAxis:Cross(velPlana.Unit) * (rapidez / raio)
	else
		ball.AssemblyAngularVelocity = Vector3.zero
	end
end)
