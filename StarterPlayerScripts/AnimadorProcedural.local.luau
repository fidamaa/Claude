--[[
	AnimadorProcedural (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts

	⚠️ v96 — UM ANIMADOR SÓ PRA TODOS OS CORPOS. PEDIDO: "verifica se não tem
	duas animações tocando ao mesmo tempo... parece que tem uma animação
	embolada na outra" + "faça animação pra cada coisa que já existe no jogo".

	O QUE ESTAVA ACONTECENDO: três fontes animavam o mesmo corpo ao mesmo tempo
	— o Animate do place (StarterCharacterScripts), o PACOTE DE ANIMAÇÃO do
	avatar de cada jogador (o Roblox aplica no jogo publicado, por isso não
	aparecia no Studio) e as nossas tracks tocadas pelo servidor. O Roblox
	mistura por junta: onde a animação de cima não mexia (a mão), aparecia a de
	baixo — a "mão solta" que o colega viu.

	AGORA: este script é o ÚNICO que anima. Em todo personagem visível (o seu,
	o dos outros jogadores, os goleiros bot e os clones do replay de gol) ele:
	  1. para qualquer AnimationTrack tocando (de onde quer que venha);
	  2. calcula a pose do quadro — locomoção (parado/andar/correr/no ar, com
	     passada guiada pela distância percorrida, inclinação na curva e na
	     aceleração), preparo do chute pela carga, e as ações que o servidor
	     avisa (chute, cabeçada, carrinho, dribles, mergulhos, saída do
	     goleiro, comemoração) — ver AnimacoesProcedurais.luau;
	  3. escreve a pose no Transform de cada junta (funciona com Motor6D e com
	     as juntas novas AnimationConstraint, que são as do avatar do jogo).

	Tudo é local e visual: cada cliente anima todo mundo a partir do que já é
	replicado (posição, atributo KickCharging) + o aviso Remotes.AcaoAnimada.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Anim = require(ReplicatedStorage:WaitForChild("AnimacoesProcedurais"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer

-- Personagens que outros scripts pedem pra este NÃO animar agora (a cutscene
-- de Hissatsu escreve a pose ela mesma, por exemplo).
_G.AnimadorPausado = _G.AnimadorPausado or {}

-- Modelos extras pra animar além dos jogadores (replay de gol, etc.).
local extras = {} -- [model] = true
-- ⚠️ v112 — PEDIDO: "no início eles não começam a andar com o braço balançando,
-- só depois de um tempo — pré-carrega a animação". A lista de modelos só era
-- revarrida a cada 0.5s: o boneco da cutscene de entrada ficava até meio segundo
-- deslizando parado. Registrar agora força a varredura no próximo quadro.
local varrerJa = false
_G.AnimadorRegistrar = function(model)
	if typeof(model) == "Instance" and model:IsA("Model") then
		extras[model] = true
		varrerJa = true
	end
end
_G.AnimadorRemover = function(model)
	extras[model] = nil
end

-- ===== juntas =====
-- Cada junta vira { Escrever(cframeRelativo) , Zerar() }. O cframe relativo
-- é a rotação (e, no Root, também o deslocamento) no espaço da peça-pai; a
-- conversão pro Transform é base^-1 * R * base, onde base é a rotação de
-- repouso da junta (C0 no Motor6D, Attachment0 na AnimationConstraint).
local MAPA_R15 = {
	Root = { "LowerTorso", "Root" }, Waist = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RShoulder = { "RightUpperArm", "RightShoulder" }, LShoulder = { "LeftUpperArm", "LeftShoulder" },
	RElbow = { "RightLowerArm", "RightElbow" }, LElbow = { "LeftLowerArm", "LeftElbow" },
	RWrist = { "RightHand", "RightWrist" }, LWrist = { "LeftHand", "LeftWrist" },
	RHip = { "RightUpperLeg", "RightHip" }, LHip = { "LeftUpperLeg", "LeftHip" },
	RKnee = { "RightLowerLeg", "RightKnee" }, LKnee = { "LeftLowerLeg", "LeftKnee" },
	RAnkle = { "RightFoot", "RightAnkle" }, LAnkle = { "LeftFoot", "LeftAnkle" },
}
local MAPA_R6 = {
	Root = { "HumanoidRootPart", "RootJoint" }, Neck = { "Torso", "Neck" },
	RShoulder = { "Torso", "Right Shoulder" }, LShoulder = { "Torso", "Left Shoulder" },
	RHip = { "Torso", "Right Hip" }, LHip = { "Torso", "Left Hip" },
}

local function juntaDe(obj)
	if not obj then return nil end
	if obj:IsA("Motor6D") then
		-- ⚠️ Motor6D (rig R6 — o goleiro bot): o motor antigo do R6 impõe um
		-- Transform próprio a cada passo de física (medido: o ombro do bot
		-- voltava pra (-43,-22,21) mesmo escrito todo quadro, e o
		-- CurrentAngle ficava travado em 0.5). Em vez de brigar pelo
		-- Transform, a pose vai no C0 JÁ DESCONTANDO o Transform que o motor
		-- impôs: Part1 = Part0 * C0 * T * C1^-1, e queremos
		-- Part0 * pos * R * base * C1^-1  =>  C0 = pos * R * base * T^-1.
		local c0Original = obj.C0
		local pos = CFrame.new(c0Original.Position)
		-- repouso = membro alinhado com a peça-pai. Vem do C1 (e não do C0)
		-- porque o molde do goleiro bot tem o C0 dos ombros POSADO (braços
		-- abertos); o C1 dele está no padrão. Em rig normal os dois são iguais.
		local base = obj.C1.Rotation
		-- ⚠️ v105: o PORTE pelo Físico (PorteFisico, no servidor) muda o tamanho
		-- do corpo e a posição das juntas DEPOIS que este mapa foi feito. A
		-- posição de descanso certa fica no atributo C0Pos da junta — sem ler
		-- dali, o braço seria reescrito na posição antiga, solto do corpo.
		local function posAtual()
			local p = obj:GetAttribute("C0Pos")
			return p and CFrame.new(p) or pos
		end
		return {
			Escrever = function(r) obj.C0 = posAtual() * r * base * obj.Transform:Inverse() end,
			Zerar = function()
				local p = obj:GetAttribute("C0Pos")
				obj.C0 = p and (CFrame.new(p) * c0Original.Rotation) or c0Original
			end,
			Vivo = function() return obj.Parent ~= nil end,
		}
	elseif obj:IsA("AnimationConstraint") and obj.Attachment0 then
		local base = obj.Attachment0.CFrame.Rotation
		local baseInv = base:Inverse()
		return {
			Escrever = function(r) obj.Transform = baseInv * r * base end,
			Zerar = function() obj.Transform = CFrame.identity end,
			Vivo = function() return obj.Parent ~= nil end,
		}
	end
	return nil
end

local function mapearJuntas(model)
	local r15 = model:FindFirstChild("UpperTorso") ~= nil
	local mapa = r15 and MAPA_R15 or MAPA_R6
	local juntas = {}
	local n = 0
	for nome, caminho in pairs(mapa) do
		local pai = model:FindFirstChild(caminho[1])
		local j = juntaDe(pai and pai:FindFirstChild(caminho[2]))
		if j then
			juntas[nome] = j
			n += 1
		end
	end
	return juntas, r15, n
end

-- ===== estado por personagem =====
local estados = {} -- [model] = estado

local function novoEstado(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or (humanoid and humanoid.RootPart)
	if not humanoid or not root then return nil end
	local juntas, r15, n = mapearJuntas(model)
	if n == 0 then return nil end
	return {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Animator = humanoid:FindFirstChildOfClass("Animator"),
		Juntas = juntas,
		R15 = r15,
		Loco = Anim.NovoEstadoLocomocao(),
		UltimaPos = root.Position,
		UltimoYaw = nil,
		VelHoriz = Vector3.zero,
		VelVert = 0,
		Acel = 0,
		Acao = nil,          -- { Chave, Def, Quadros, Inicio, Duracao }
		CargaInicio = nil,   -- os.clock() em que começou a segurar o chute
		UltimaCarga = 0.4,   -- carga do último preparo (o chute usa)
		PreparoPeso = 0,
		Tempo = math.random() * 10, -- desencontra a respiração entre os bonecos
		Zerado = false,
	}
end

local function jogadorDe(model)
	return Players:GetPlayerFromCharacter(model)
end

local function ehGoleiroBot(model)
	return model.Name:sub(1, 6) == "GKBot_"
end

-- ===== ações vindas do servidor =====
local function iniciarAcao(model, chave, duracao, parametros)
	local estado = estados[model]
	if not estado then
		estado = novoEstado(model)
		if not estado then return end
		estados[model] = estado
	end
	if typeof(chave) ~= "string" then return end

	-- "parar:<chave>" corta a ação se for ela que está tocando
	if chave:sub(1, 6) == "parar:" then
		local alvo = chave:sub(7)
		if estado.Acao and (estado.Acao.Chave == alvo or alvo == "*") then
			-- em vez de sumir seco, encurta pra sair suave daqui a pouco
			local agora = os.clock() - estado.Acao.Inicio
			estado.Acao.Duracao = math.min(estado.Acao.Duracao, agora + estado.Acao.Def.SaidaSeg)
		end
		return
	end

	local def = Anim.Acoes[chave]
	if not def then return end
	parametros = typeof(parametros) == "table" and parametros or {}
	if chave == "Kick" then
		parametros.Carga = estado.UltimaCarga
	end
	local d = (typeof(duracao) == "number" and duracao > 0.05) and duracao or def.Duracao
	-- ⚠️ v103: a duração do servidor é a do LANCE; ações com FimDaMecanica
	-- (carrinho) têm um trecho extra depois dele (levantar) — estica junto
	if def.FimDaMecanica and typeof(duracao) == "number" and duracao > 0.05 then
		d = duracao * def.Duracao / def.FimDaMecanica
	end
	-- o mínimo visual: ações mecânicas curtas (ex.: queda do carrinho 0.5s)
	-- ainda mostram a animação inteira
	if chave == "TackleMiss" then d = math.max(d, 0.9) end
	if chave:sub(1, 7) == "GKDive." then d = math.max(d, def.Duracao) end
	estado.Acao = {
		Chave = chave, Def = def, Quadros = def.Quadros(parametros),
		Inicio = os.clock(), Duracao = d,
	}
	-- ⚠️ v104 — PEDIDO: "o carrinho, quando ele acaba e rola a animação dele
	-- levantando, você consegue girar o personagem — não é pra ser possível.
	-- Só vai poder girar assim que levantar completamente (acabaram as duas
	-- animações)". O FootballClient lê _G.CorpoTravadoAte: até lá, nada de
	-- girar nem andar (carrinho + queda/levantar, o que durar mais).
	if (chave == "Tackle" or chave == "TackleMiss" or chave == "SofreuCarrinho") and model == Players.LocalPlayer.Character then
		_G.CorpoTravadoAte = math.max(_G.CorpoTravadoAte or 0, os.clock() + d)
	end
end

-- ⚠️ v103: o replay de gol dispara as ações gravadas direto nos fantasmas
_G.AnimadorAcaoLocal = function(model, chave, duracao, parametros)
	if typeof(model) == "Instance" and model:IsA("Model") then
		iniciarAcao(model, chave, duracao, parametros)
	end
end

Remotes.AcaoAnimada.OnClientEvent:Connect(function(model, chave, duracao, parametros)
	if typeof(model) == "Instance" and model:IsA("Model") then
		iniciarAcao(model, chave, duracao, parametros)
	end
end)

-- ⚠️ v111 — PEDIDO: "faça o carrinho levantar um pouco mais rápido quando você
-- pega a bola". Quem estava no carrinho e ganhou a posse: depois de 0.2s de
-- deslize (pra o carrinho aparecer), levanta em 0.3s — antes ficava deitado
-- até 0.60s e só então levantava (0.85s no total, corpo travado junto).
Remotes.PossessionChanged.OnClientEvent:Connect(function(quem, ganhou)
	if not ganhou or typeof(quem) ~= "Instance" or not quem:IsA("Player") then return end
	local model = quem.Character
	local estado = model and estados[model]
	local acao = estado and estado.Acao
	if not acao or acao.Chave ~= "Tackle" then return end
	local espera = math.max(0, 0.2 - (os.clock() - acao.Inicio))
	task.delay(espera, function()
		local e = estados[model]
		if not e or e.Acao ~= acao then return end
		iniciarAcao(model, "TackleLevanta", 0.3)
		if model == Players.LocalPlayer.Character then
			_G.CorpoTravadoAte = os.clock() + 0.3
		end
	end)
end)

-- ===== quadro =====
local paramsChao = RaycastParams.new()
paramsChao.FilterType = Enum.RaycastFilterType.Exclude
paramsChao.RespectCanCollide = true

-- Devolve (está no chão?, altura Y do chão embaixo dele ou nil).
local function noChao(estado)
	local root = estado.Root
	paramsChao.FilterDescendantsInstances = { estado.Model }
	-- altura do quadril até o chão. R6 usa HipHeight = 0 (a perna é quem
	-- segura), então ali é meio tronco + perna — sem isso o goleiro bot (R6)
	-- parecia estar sempre no ar e ficava na pose de queda.
	local altura
	if (estado.Humanoid.HipHeight or 0) > 0.1 then
		altura = estado.Humanoid.HipHeight + root.Size.Y / 2
	else
		local tronco = estado.Model:FindFirstChild("Torso")
		local perna = estado.Model:FindFirstChild("Left Leg") or estado.Model:FindFirstChild("LeftUpperLeg")
		altura = (tronco and tronco.Size.Y / 2 or root.Size.Y / 2) + (perna and perna.Size.Y or 2)
	end
	local r = workspace:Raycast(root.Position, Vector3.new(0, -(altura + 6), 0), paramsChao)
	if not r then return false, nil end
	return (root.Position.Y - r.Position.Y) <= altura + 1.2, r.Position.Y
end

-- ⚠️ Nenhuma parte do corpo fura o gramado: mede a parte mais baixa (do
-- quadro anterior) e, se ela está abaixo do chão, levanta o corpo o quanto
-- falta. Quando sobra espaço, a correção volta devagar pra zero. Vale pra
-- qualquer pose (andar, mergulho, carrinho, deitado) e qualquer avatar
-- (perna mais longa/curta).
local function corrigirChao(estado, alturaChao)
	if not alturaChao then
		estado.Correcao = math.max(0, (estado.Correcao or 0) * 0.9)
		return
	end
	local menor = math.huge
	for _, p in ipairs(estado.Model:GetChildren()) do
		if p:IsA("BasePart") and p ~= estado.Root and p.Transparency < 1 then
			local fundo = p.Position.Y - p.Size.Y / 2
			if fundo < menor then menor = fundo end
		end
	end
	if menor == math.huge then return end
	local folga = menor - alturaChao
	estado.DbgFolga = folga
	local c = estado.Correcao or 0
	if folga < -0.03 then
		c = c - folga -- afundou: sobe exatamente o que falta
	elseif folga > 0.05 then
		c = math.max(0, c - math.min(folga, c) * 0.25) -- sobrou: desce devagar
	end
	estado.Correcao = math.clamp(c, 0, 3)
end

local function cargaAtual(estado, jog)
	local segurando = jog and jog:GetAttribute("KickCharging") == true
	if segurando then
		if not estado.CargaInicio then estado.CargaInicio = os.clock() end
		local tempoCheio = (Config.KICK_MAX_FORCE - Config.KICK_MIN_FORCE) / Config.KICK_CHARGE_RATE
		local c = math.clamp((os.clock() - estado.CargaInicio) / math.max(tempoCheio, 0.1), 0, 1)
		estado.UltimaCarga = c
		return true, c
	end
	estado.CargaInicio = nil
	return false, estado.UltimaCarga
end

local function pararTracks(estado)
	local animator = estado.Animator
	if not animator or not animator.Parent then
		animator = estado.Humanoid:FindFirstChildOfClass("Animator")
		estado.Animator = animator
	end
	if animator then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
end

-- R6 (goleiro bot) não tem joelho nem cotovelo: perna reta dobrando só no
-- quadril vira "sentado", e abaixar o quadril enterra a perna reta no chão.
-- Então no R6 a flexão de quadril é reduzida e o quadril só desce quando o
-- corpo está deitado/tombado (mergulho, carrinho).
local function adaptarR6(pose)
	local p = table.clone(pose)
	local root = p.Root or Vector3.zero
	local tombado = math.abs(root.X) > 45 or math.abs(root.Z) > 45
	if p.RootPos and not tombado then
		p.RootPos = Vector3.new(p.RootPos.X, math.max(p.RootPos.Y, 0), p.RootPos.Z)
	end
	-- ⚠️ v106: só a perna indo pra FRENTE é encolhida (sem joelho, flexão
	-- grande vira "sentado"); pra TRÁS (preparo do chute, passada) vale inteiro —
	-- era isso que deixava o pé "indo muito pouco pra trás" no R6. E encolhe
	-- menos (0.7, era 0.45): o chute e a passada ficavam tímidos demais.
	for _, nome in ipairs({ "RHip", "LHip" }) do
		local a = p[nome]
		if a and not tombado and a.X > 0 then p[nome] = Vector3.new(a.X * 0.7, a.Y, a.Z * 0.6) end
	end
	return p
end

local function escreverPose(estado, pose)
	if not estado.R15 then pose = adaptarR6(pose) end
	for nome, junta in pairs(estado.Juntas) do
		local a = pose[nome]
		local r
		if a then
			r = CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z))
		else
			r = CFrame.identity
		end
		if nome == "Root" and pose.RootPos then
			r = CFrame.new(pose.RootPos) * r
		end
		junta.Escrever(r)
	end
	estado.Zerado = false
end

local function zerar(estado)
	if estado.Zerado then return end
	for _, junta in pairs(estado.Juntas) do
		if junta.Vivo() then junta.Zerar() end
	end
	estado.Zerado = true
end

local function atualizar(estado, dt)
	local model, humanoid, root = estado.Model, estado.Humanoid, estado.Root
	estado.Tempo += dt

	-- movimento medido pela posição (funciona até em clone ancorado de replay)
	local pos = root.Position
	local delta = pos - estado.UltimaPos
	estado.UltimaPos = pos
	if dt > 0 then
		local velInst = delta / dt
		local horiz = Vector3.new(velInst.X, 0, velInst.Z)
		if horiz.Magnitude > 120 then horiz = Vector3.zero end -- teleporte, não passada
		local anterior = estado.VelHoriz
		estado.VelHoriz = anterior:Lerp(horiz, math.clamp(dt * 14, 0, 1))
		estado.VelVert = estado.VelVert + (math.clamp(velInst.Y, -200, 200) - estado.VelVert) * math.clamp(dt * 14, 0, 1)
		local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		frente = frente.Magnitude > 0.01 and frente.Unit or Vector3.new(0, 0, -1)
		local acelInst = (estado.VelHoriz - anterior):Dot(frente) / dt
		estado.Acel = estado.Acel + (acelInst - estado.Acel) * math.clamp(dt * 6, 0, 1)
	end

	-- giro (graus por segundo, positivo = virando pra esquerda)
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local giro = 0
	if estado.UltimoYaw and dt > 0 then
		local d = (yaw - estado.UltimoYaw + math.pi) % (2 * math.pi) - math.pi
		giro = math.deg(d) / dt
	end
	estado.UltimoYaw = yaw

	-- andar de costas / de lado: a passada segue a direção do movimento em
	-- relação a pra onde o corpo aponta
	local vel = estado.VelHoriz.Magnitude
	local frente = Vector3.new(look.X, 0, look.Z)
	local sentido = 1
	if vel > 1 and frente.Magnitude > 0.01 then
		local dir = estado.VelHoriz.Unit
		local alinhado = dir:Dot(frente.Unit)
		if alinhado < -0.35 then sentido = -1 end
	end

	local jog = jogadorDe(model)
	local goleiro = ehGoleiroBot(model) or (jog ~= nil and GKAreaUtil.IsEffectiveGK(jog))

	local estaNoChao, alturaChao = noChao(estado)
	corrigirChao(estado, estaNoChao and alturaChao or nil)

	local pose = Anim.Locomocao(estado.Loco, {
		Velocidade = vel * sentido,
		VelVertical = estado.VelVert,
		NoChao = estaNoChao,
		Goleiro = goleiro,
		GiroGrausPorSeg = giro,
		Aceleracao = estado.Acel,
		Tempo = estado.Tempo,
	}, dt)

	-- preparo do chute (segurando o botão)
	local segurando, carga = cargaAtual(estado, jog)
	estado.PreparoPeso = estado.PreparoPeso + ((segurando and 1 or 0) - estado.PreparoPeso) * math.clamp(dt * 14, 0, 1)
	if estado.PreparoPeso > 0.01 then
		local mascara = Anim.MASCARA_PREPARO
		if vel < 2 then
			-- parado: o preparo manda no corpo inteiro
			pose = Anim.Blend(pose, Anim.PreparoChute(carga), estado.PreparoPeso)
		else
			pose = Anim.BlendMask(pose, Anim.PreparoChute(carga), estado.PreparoPeso, mascara)
		end
	end

	-- ⚠️ v105: goleiro com a bola nas mãos — braços segurando por cima da
	-- locomoção (a ação, logo abaixo, ainda manda por cima: arremesso, dive)
	estado.MaoPeso = (estado.MaoPeso or 0) + (((model:GetAttribute("BolaNaMao") == true) and 1 or 0) - (estado.MaoPeso or 0)) * math.clamp(dt * 12, 0, 1)
	if estado.MaoPeso > 0.01 and Anim.POSE_SEGURAR then
		pose = Anim.BlendMask(pose, Anim.POSE_SEGURAR, estado.MaoPeso, Anim.MASCARA_BRACOS)
	end

	-- ação por cima de tudo
	local acao = estado.Acao
	if acao then
		local t = os.clock() - acao.Inicio
		if t >= acao.Duracao then
			estado.Acao = nil
		else
			local poseAcao, peso = Anim.AmostrarAcao(acao.Def, acao.Quadros, t, acao.Duracao)
			pose = Anim.Blend(pose, poseAcao, peso)
		end
	end

	if (estado.Correcao or 0) > 0 then
		pose.RootPos = (pose.RootPos or Vector3.zero) + Vector3.new(0, estado.Correcao, 0)
	end
	escreverPose(estado, pose)

	-- diagnóstico (atributo "AnimadorDebug" no LocalPlayer): publica o estado
	-- deste boneco num atributo local, pra dar pra inspecionar de fora
	if player:GetAttribute("AnimadorDebug") then
		local juntas = 0
		for _ in pairs(estado.Juntas) do juntas += 1 end
		model:SetAttribute("AnimDbg", string.format("R15=%s juntas=%d vel=%.1f chao=%s(%.2f) goleiro=%s Root=%s RootPos=%s corr=%.2f folga=%s acao=%s",
			tostring(estado.R15), juntas, vel, tostring(estaNoChao), alturaChao or -1, tostring(goleiro), tostring(pose.Root), tostring(pose.RootPos),
			estado.Correcao or 0, tostring(estado.DbgFolga), estado.Acao and estado.Acao.Chave or "-"))
	end
end

local function modelosParaAnimar()
	local lista = {}
	for _, jog in ipairs(Players:GetPlayers()) do
		if jog.Character then lista[jog.Character] = true end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and ehGoleiroBot(m) then lista[m] = true end
	end
	for m in pairs(extras) do
		if m.Parent then lista[m] = true else extras[m] = nil end
	end
	return lista
end

local ultimaLista = {}
local proximaVarredura = 0

RunService.Stepped:Connect(function(_, dt)
	local agora = os.clock()
	if agora >= proximaVarredura or varrerJa then
		varrerJa = false
		proximaVarredura = agora + 0.5
		ultimaLista = modelosParaAnimar()
		for model in pairs(estados) do
			if not ultimaLista[model] or not model.Parent then estados[model] = nil end
		end
	end

	for model in pairs(ultimaLista) do
		if not model.Parent then continue end
		local estado = estados[model]
		if not estado or not estado.Root.Parent or not estado.Humanoid.Parent then
			estado = novoEstado(model)
			estados[model] = estado
		end
		if player:GetAttribute("AnimadorDebug") then
			model:SetAttribute("AnimDbgVisto", estado and "com estado" or "SEM estado (sem Humanoid/root/juntas)")
		end
		if not estado then continue end

		if _G.AnimadorPausado[model] then
			estado.Zerado = true -- quem pausou está escrevendo; não mexe
			continue
		end
		-- caído/ragdoll/morto: a física manda no corpo
		if estado.Humanoid.PlatformStand or estado.Humanoid.Health <= 0 then
			zerar(estado)
			continue
		end

		pararTracks(estado)
		local ok, err = pcall(atualizar, estado, math.min(dt, 0.1))
		if not ok then
			warn("[Animador] " .. model.Name .. ": " .. tostring(err))
			estados[model] = nil
		end
	end
end)

print("✅ AnimadorProcedural carregado (um animador só pra todos os corpos).")
