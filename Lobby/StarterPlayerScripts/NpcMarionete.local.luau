--[[
	NpcMarionete (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Lobby)

	⚠️ v115 — PEDIDO: "No lobby também, faça os NPCs, cada um fazer uma coisa
	diferente, eles se moverem. O meu NPC olhar pra um lado e pro outro, de
	repente. O Rayão tá com medo, olhando pra um lado e pro outro. O Pedro tem
	uma pose meio mal feita, faz uma animação dele chamando o player quando o
	player chega perto; quando tá falando, ele muda de animação."

	POR QUE É UM SCRIPT DE MARIONETE (e não AnimationTrack): os bonecos do Lobby
	chegam sem Motor6D e com TODAS as peças ancoradas (a pose deles é "assada" nas
	posições das peças), então nenhuma animação do Roblox mexe neles. Aqui cada
	cliente monta o esqueleto R15 a partir dos RigAttachments das próprias peças
	(o mesmo par de attachments que o Roblox usa nas juntas) e, a cada quadro,
	recalcula as peças — cinemática direta, com a pose desejada em graus por junta
	(mesma convenção do AnimacoesProcedurais do place Game: rx+ = membro pra
	FRENTE, rz+ abre pro lado DIREITO e pro lado ESQUERDO é negativo, joelho
	negativo dobra, cotovelo positivo dobra, Neck rx+ olha pra cima, ry+ olha pra
	ESQUERDA; Waist/Root rx- inclina pra frente).

	Tudo é LOCAL (cada jogador vê o boneco se mexer na própria tela): nada replica,
	nada pesa no servidor.

	Personalidades (DialogueId do boneco):
	  Kogamalotigo — o técnico: parado, de repente vira a cabeça seca pra um lado,
	                 depois pro outro, e volta.
	  ShopKeeper   — o Rayão: com MEDO. Encolhido, tremendo, mãos no peito,
	                 olhando pros lados o tempo todo.
	  RollMaster   — o Pedro: pose relaxada de mão na cintura; quando o jogador
	                 chega perto ele CHAMA (braço levantado, acenando "vem cá");
	                 falando, muda pra gestos de conversa.
	  QuestGiver   — o Tiluca: pose de JoJo (a do KeyframeSequence "JojoPose"),
	                 trocando de pose de tempos em tempos.
	  Estatisticas — o Bentes/Pepe Nep sentado no banco: escreve num caderno
	                 imaginário e levanta a cabeça quando alguém chega.

	"Falando": o DialogueClient liga o atributo local "Falando" no boneco durante
	a conversa.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer

local ZERO = Vector3.zero
local function V(x, y, z) return Vector3.new(x, y, z) end

-- ============================================================
-- ESQUELETO R15 (ordem: pai antes do filho)
-- ============================================================
local JUNTAS = {
	{ Nome = "Root", Pai = "HumanoidRootPart", Filho = "LowerTorso", Att = "RootRigAttachment" },
	{ Nome = "Waist", Pai = "LowerTorso", Filho = "UpperTorso", Att = "WaistRigAttachment" },
	{ Nome = "Neck", Pai = "UpperTorso", Filho = "Head", Att = "NeckRigAttachment" },
	{ Nome = "RShoulder", Pai = "UpperTorso", Filho = "RightUpperArm", Att = "RightShoulderRigAttachment" },
	{ Nome = "RElbow", Pai = "RightUpperArm", Filho = "RightLowerArm", Att = "RightElbowRigAttachment" },
	{ Nome = "RWrist", Pai = "RightLowerArm", Filho = "RightHand", Att = "RightWristRigAttachment" },
	{ Nome = "LShoulder", Pai = "UpperTorso", Filho = "LeftUpperArm", Att = "LeftShoulderRigAttachment" },
	{ Nome = "LElbow", Pai = "LeftUpperArm", Filho = "LeftLowerArm", Att = "LeftElbowRigAttachment" },
	{ Nome = "LWrist", Pai = "LeftLowerArm", Filho = "LeftHand", Att = "LeftWristRigAttachment" },
	{ Nome = "RHip", Pai = "LowerTorso", Filho = "RightUpperLeg", Att = "RightHipRigAttachment" },
	{ Nome = "RKnee", Pai = "RightUpperLeg", Filho = "RightLowerLeg", Att = "RightKneeRigAttachment" },
	{ Nome = "RAnkle", Pai = "RightLowerLeg", Filho = "RightFoot", Att = "RightAnkleRigAttachment" },
	{ Nome = "LHip", Pai = "LowerTorso", Filho = "LeftUpperLeg", Att = "LeftHipRigAttachment" },
	{ Nome = "LKnee", Pai = "LeftUpperLeg", Filho = "LeftLowerLeg", Att = "LeftKneeRigAttachment" },
	{ Nome = "LAnkle", Pai = "LeftLowerLeg", Filho = "LeftFoot", Att = "LeftAnkleRigAttachment" },
}
local NOMES_JUNTAS = {}
for _, j in ipairs(JUNTAS) do table.insert(NOMES_JUNTAS, j.Nome) end
local PECAS_DO_CHAO = { "LeftFoot", "RightFoot", "LeftLowerLeg", "RightLowerLeg" }

-- pose (Vector3 em graus OU CFrame) -> rotação
local function emRot(v)
	if typeof(v) == "CFrame" then return v.Rotation end
	if not v then return CFrame.identity end
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

-- ============================================================
-- CONSTRUÇÃO DO BONECO
-- modo "neutro": ignora a pose assada e parte do R15 em pé (rest = juntas zeradas)
-- modo "assado": mantém a pose assada (ex.: sentado) e anima por cima
-- ============================================================
local function construir(model, modo)
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then return nil end
	local pecas = { HumanoidRootPart = hrp }
	for _, j in ipairs(JUNTAS) do
		local p = model:FindFirstChild(j.Filho)
		if not (p and p:IsA("BasePart")) then return nil end
		pecas[j.Filho] = p
	end
	-- nada de construir pela metade (streaming): precisa dos attachments também
	local baked = {}
	for nome, p in pairs(pecas) do baked[nome] = p.CFrame end

	-- neutro: raiz EM PÉ (só a direção do boneco vale; o Pedro, por exemplo, tem a raiz
	-- inclinada na pose assada)
	local restHRP = hrp.CFrame
	if modo == "neutro" then
		local f = hrp.CFrame.LookVector
		restHRP = CFrame.new(hrp.Position) * CFrame.Angles(0, math.atan2(-f.X, -f.Z), 0)
	end
	local rest = { HumanoidRootPart = restHRP }
	local juntas = {}
	for _, j in ipairs(JUNTAS) do
		local aP = pecas[j.Pai]:FindFirstChild(j.Att)
		local aC = pecas[j.Filho]:FindFirstChild(j.Att)
		if not (aP and aC and aP:IsA("Attachment") and aC:IsA("Attachment")) then return nil end
		if modo == "neutro" then
			-- ⚠️ só as POSIÇÕES dos attachments: no Pedro a pose assada mora na ORIENTAÇÃO
			-- deles (o par de attachments reproduz a pose torta), então a rotação é ignorada
			rest[j.Filho] = rest[j.Pai] * CFrame.new(aP.CFrame.Position - aC.CFrame.Position)
		else
			rest[j.Filho] = baked[j.Filho]
		end
		local pivoMundo = (rest[j.Filho] * CFrame.new(aC.CFrame.Position)).Position
		table.insert(juntas, {
			Nome = j.Nome, Pai = j.Pai, Filho = j.Filho,
			-- só a POSIÇÃO do pivô no espaço do pai: a rotação é nos eixos do pai
			Pivo = CFrame.new(rest[j.Pai]:PointToObjectSpace(pivoMundo)),
			FilhoLocal = rest[j.Pai]:ToObjectSpace(rest[j.Filho]),
		})
	end

	-- acessórios: seguem a peça do corpo a que estão presos
	local acessorios = {} -- { Parte, Corpo, Rel }
	for _, acc in ipairs(model:GetChildren()) do
		if acc:IsA("Accessory") then
			for _, parte in ipairs(acc:GetDescendants()) do
				if parte:IsA("BasePart") then
					local corpo
					for _, a in ipairs(parte:GetChildren()) do
						if a:IsA("Attachment") and not a.Name:find("RigAttachment") then
							for nome, pc in pairs(pecas) do
								if pc:FindFirstChild(a.Name) then corpo = nome break end
							end
						end
						if corpo then break end
					end
					if not corpo then
						local melhor = math.huge
						for nome, pc in pairs(pecas) do
							local d = (pc.Position - parte.Position).Magnitude
							if d < melhor then melhor, corpo = d, nome end
						end
					end
					table.insert(acessorios, { Parte = parte, Corpo = corpo, Rel = baked[corpo]:ToObjectSpace(parte.CFrame) })
				end
			end
		end
	end

	-- cliente próprio: tudo ancorado AQUI (boneco com física some de baixo da pose)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end

	local p = {
		Model = model, Modo = modo, Pecas = pecas, Juntas = juntas, Acessorios = acessorios,
		RestHRP = rest.HumanoidRootPart, Atual = {}, RootPos = ZERO, Dy = nil, Est = {},
		Id = model:GetAttribute("DialogueId") or model.Name, T0 = math.random() * 50,
	}
	for _, nome in ipairs(NOMES_JUNTAS) do p.Atual[nome] = CFrame.identity end

	-- chão: raycast pra baixo, conferido contra o pé calculado (se destoar, usa o pé)
	local lista, cfs = {}, {}
	local function bottomDe(cf, parte)
		local s = parte.Size
		local meio = 0.5 * (math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z)
		return cf.Position.Y - meio
	end
	p.BottomDe = bottomDe
	local cf0 = {}
	do
		local cfp = { HumanoidRootPart = p.RestHRP }
		for _, j in ipairs(juntas) do cfp[j.Filho] = cfp[j.Pai] * j.FilhoLocal end
		cf0 = cfp
	end
	local menor = math.huge
	for _, nome in ipairs(PECAS_DO_CHAO) do menor = math.min(menor, bottomDe(cf0[nome], pecas[nome])) end
	p.ChaoY = menor
	if modo == "neutro" then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { model }
		local r = workspace:Raycast(hrp.Position + Vector3.new(0, 1, 0), Vector3.new(0, -12, 0), params)
		if r and math.abs(r.Position.Y - menor) < 2.5 then p.ChaoY = r.Position.Y end
	end
	return p
end

-- ============================================================
-- CÁLCULO DO QUADRO
-- ============================================================
local function aplicar(p, dt)
	local cf = { HumanoidRootPart = p.RestHRP }
	for _, j in ipairs(p.Juntas) do
		local P = cf[j.Pai]
		local R = p.Atual[j.Nome]
		if j.Nome == "Root" then P = P * CFrame.new(p.RootPos) end
		cf[j.Filho] = P * j.Pivo * R * j.Pivo:Inverse() * j.FilhoLocal
	end
	local dy = 0
	if p.Modo == "neutro" then
		local menor = math.huge
		for _, nome in ipairs(PECAS_DO_CHAO) do
			menor = math.min(menor, p.BottomDe(cf[nome], p.Pecas[nome]))
		end
		local alvo = p.ChaoY - menor
		if p.Dy == nil then p.Dy = alvo else p.Dy += (alvo - p.Dy) * (1 - math.exp(-dt * 14)) end
		dy = p.Dy
	end
	local desloca = CFrame.new(0, dy, 0)
	local partes, cfs = {}, {}
	for nome, c in pairs(cf) do
		table.insert(partes, p.Pecas[nome])
		table.insert(cfs, desloca * c)
	end
	for _, a in ipairs(p.Acessorios) do
		table.insert(partes, a.Parte)
		table.insert(cfs, desloca * cf[a.Corpo] * a.Rel)
	end
	workspace:BulkMoveTo(partes, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- ============================================================
-- AJUDANTES DE POSE
-- ============================================================
local function basePose(t)
	local r = math.sin(t * 1.7)
	return {
		RootPos = ZERO, Waist = V(r * 0.8, 0, 0), Neck = ZERO,
		RShoulder = V(0, 0, 7 + r * 0.6), LShoulder = V(0, 0, -7 - r * 0.6),
		RElbow = V(10, 0, 0), LElbow = V(10, 0, 0), RWrist = ZERO, LWrist = ZERO,
		RHip = V(0, 0, 2), LHip = V(0, 0, -2), RKnee = ZERO, LKnee = ZERO, RAnkle = ZERO, LAnkle = ZERO,
	}
end

-- cabeça (e um pouco do tronco) pra onde o jogador está
local function olharJogador(pose, ctx, forca, extraX)
	forca = forca or 1
	if not ctx.Tem then return end
	local yaw = math.clamp(ctx.Yaw, -75, 75)
	local pitch = math.clamp(ctx.Pitch, -22, 22)
	pose.Neck = V(pitch * forca + (extraX or 0), yaw * 0.62 * forca, 0)
	pose.Waist = V(pose.Waist.X, yaw * 0.22 * forca, pose.Waist.Z)
end

local function espelhar(pose)
	local r = {}
	local troca = { R = "L", L = "R" }
	for nome, v in pairs(pose) do
		local lado, resto = nome:sub(1, 1), nome:sub(2)
		if (lado == "R" or lado == "L") and resto ~= "" and resto:sub(1, 1):match("%u") then
			r[troca[lado] .. resto] = (typeof(v) == "Vector3") and V(v.X, -v.Y, -v.Z) or v
		elseif typeof(v) == "Vector3" and (nome == "Waist" or nome == "Neck") then
			r[nome] = V(v.X, -v.Y, -v.Z)
		elseif nome == "RootPos" then
			r[nome] = V(-v.X, v.Y, v.Z)
		else
			r[nome] = v
		end
	end
	return r
end

-- gestos de quem está falando (os dois braços, ritmos diferentes)
local function gestosDeFala(pose, t, fase, intensidade)
	intensidade = intensidade or 1
	local a = math.sin(t * 2.6 + fase)
	local b = math.sin(t * 1.9 + 1.3 + fase)
	pose.RShoulder = V((38 + 22 * a) * intensidade, 0, 12 + 8 * b)
	pose.RElbow = V((70 + 28 * b) * intensidade, 0, 0)
	pose.RWrist = V(0, 0, 14 * a)
	pose.LShoulder = V((24 + 18 * b) * intensidade, 0, -12 - 6 * a)
	pose.LElbow = V((62 + 24 * a) * intensidade, 0, 0)
	pose.LWrist = V(0, 0, -10 * b)
	return 4 * math.sin(t * 3.3) -- balanço da cabeça (somar no Neck.X)
end

-- ============================================================
-- PERSONALIDADES
-- Cada função devolve a pose-alvo (e opcionalmente .Taxa de suavização).
-- ============================================================
local PERSONALIDADE = {}

-- KOGAMALOTIGO — "olhar pra um lado e pro outro, de repente"
PERSONALIDADE.Kogamalotigo = function(p, t, dt, ctx)
	local pose = basePose(t)
	local e = p.Est
	e.Fila = e.Fila or {}
	e.Prox = e.Prox or (t + 2)
	e.Yaw = e.Yaw or 0
	e.Pit = e.Pit or 0
	if ctx.Falando then
		local nod = gestosDeFala(pose, t, p.T0, 0.8)
		olharJogador(pose, ctx, 1, nod)
		pose.Taxa = 9
		return pose
	end
	if t >= e.Prox then
		if #e.Fila == 0 then
			-- um "susto de curiosidade": esquerda, direita, (às vezes de novo), centro
			local lado = math.random() < 0.5 and 1 or -1
			e.Fila = { { lado * 68, 0.75 }, { -lado * 68, 0.8 }, { 0, 0.4 } }
			if math.random() < 0.35 then
				table.insert(e.Fila, 3, { lado * 50, 0.55 })
				table.insert(e.Fila, 4, { -lado * 50, 0.5 })
			end
			if math.random() < 0.4 then e.Pit = -6 else e.Pit = 4 end
		end
		local passo = table.remove(e.Fila, 1)
		e.Yaw = passo[1]
		e.Prox = t + passo[2]
		if #e.Fila == 0 then e.Prox = t + 2.2 + math.random() * 3 end
	end
	pose.Neck = V(e.Pit * (math.abs(e.Yaw) / 68), e.Yaw, 0)
	pose.Waist = V(pose.Waist.X, e.Yaw * 0.18, 0)
	-- as mãos acompanham de leve (curiosidade)
	pose.RShoulder = V(0, 0, 7 + math.abs(e.Yaw) * 0.05)
	pose.LShoulder = V(0, 0, -7 - math.abs(e.Yaw) * 0.05)
	pose.Taxa = 22 -- bem seco: é pra ser "de repente"
	return pose
end

-- RAYÃO (lojista) — com MEDO
PERSONALIDADE.ShopKeeper = function(p, t, dt, ctx)
	local pose = basePose(t)
	local e = p.Est
	local tremor = math.sin(t * 41) * 1.6 + math.sin(t * 27 + 1) * 1.1
	-- agachadinho, encolhido
	pose.RootPos = V(math.sin(t * 47) * 0.012, -0.32, 0)
	pose.RHip = V(16, 0, 6)
	pose.LHip = V(16, 0, -6)
	pose.RKnee = V(-34 + tremor, 0, 0)
	pose.LKnee = V(-34 - tremor, 0, 0)
	pose.RAnkle = V(18, 0, 0)
	pose.LAnkle = V(18, 0, 0)
	pose.Waist = V(-13, 0, 0)
	-- mãos protegendo o peito, tremendo
	pose.RShoulder = V(38 + tremor, 0, 8)
	pose.LShoulder = V(38 - tremor, 0, -8)
	pose.RElbow = V(100 + tremor * 1.4, 0, 0)
	pose.LElbow = V(100 - tremor * 1.4, 0, 0)
	pose.RWrist = V(0, 0, 10 * math.sin(t * 36))
	pose.LWrist = V(0, 0, -10 * math.sin(t * 33))
	-- olha pros lados o tempo todo (rápido, nervoso)
	e.Prox = e.Prox or 0
	e.Yaw = e.Yaw or 0
	if t >= e.Prox then
		local lado = (e.Yaw >= 0) and -1 or 1
		e.Yaw = lado * (40 + math.random() * 35)
		e.Prox = t + 0.55 + math.random() * 0.7
		e.Susto = (math.random() < 0.25) and (t + 0.25) or 0
	end
	local pitch = 6 + 4 * math.sin(t * 5)
	if ctx.Falando then
		-- fala olhando pro jogador, mas dá umas olhadas rápidas em volta
		local rapida = (math.floor(t * 0.9) % 3 == 2)
		local alvoYaw = rapida and e.Yaw or math.clamp(ctx.Yaw, -70, 70)
		pose.Neck = V(pitch, alvoYaw * 0.62, 0)
		pose.Waist = V(-13, alvoYaw * 0.2, 0)
		pose.RShoulder = V(48 + tremor + 12 * math.sin(t * 3.1), 0, 8)
		pose.RElbow = V(95 + 20 * math.sin(t * 3.1 + 1), 0, 0)
	else
		pose.Neck = V(pitch, e.Yaw * 0.62, 0)
		pose.Waist = V(-13, e.Yaw * 0.2, 0)
	end
	if e.Susto and e.Susto > t then
		pose.RootPos = V(0, -0.5, 0)
		pose.RShoulder = V(70, 0, 20)
		pose.LShoulder = V(70, 0, -20)
	end
	pose.Taxa = 16
	return pose
end

-- PEDRO (recrutador) — mão na cintura; CHAMA quando o jogador chega perto
PERSONALIDADE.RollMaster = function(p, t, dt, ctx)
	local pose = basePose(t)
	local e = p.Est
	-- histerese: começa a chamar em 30 studs, só para depois de 38
	if ctx.Falando then
		e.PausaChamar = t + 7
	end
	local quer = ctx.Tem and not ctx.Falando and t > (e.PausaChamar or 0)
	if quer then
		if e.Chamando then
			if ctx.Dist > 38 then e.Chamando = false end
		elseif ctx.Dist < 30 then
			e.Chamando = true
		end
	else
		e.Chamando = false
	end

	-- pose de repouso: peso na perna direita, mão esquerda na cintura
	local sway = math.sin(t * 0.8)
	pose.RootPos = V(0.07 * sway, 0, 0)
	pose.Waist = V(math.sin(t * 1.7) * 0.8, 0, 2.2 * sway)
	pose.RHip = V(0, 0, 3)
	pose.LHip = V(11, 0, -6)
	pose.LKnee = V(-16, 0, 0)
	pose.LAnkle = V(5 + 7 * math.max(0, math.sin(t * 3.2)), 0, 0)
	pose.LShoulder = V(10, 0, -46)
	pose.LElbow = V(25, 0, 98)
	pose.RShoulder = V(6, 0, 9 + 1.5 * sway)
	pose.RElbow = V(16, 0, 0)
	pose.Neck = V(0, 18 * math.sin(t * 0.5), 0)

	if ctx.Falando then
		-- falando: desencosta e gesticula com as duas mãos, olhando pro jogador
		pose.LHip = V(5, 0, -4)
		pose.LKnee = V(-8, 0, 0)
		pose.LAnkle = V(2, 0, 0)
		pose.RootPos = V(0, 0, 0)
		local nod = gestosDeFala(pose, t, p.T0, 1)
		pose.Waist = V(-2, 0, 0)
		olharJogador(pose, ctx, 1, nod)
		pose.Taxa = 8
	elseif e.Chamando then
		-- "vem cá!": braço direito levantado, antebraço acenando
		local w = math.sin(t * 8)
		pose.RShoulder = V(80, 0, 12)
		pose.RElbow = V(82 + 30 * w, 0, 0)
		pose.RWrist = V(18 * w, 0, 0)
		pose.Waist = V(-7, 0, 0)
		pose.RootPos = V(0, 0.05 * math.abs(w), 0)
		pose.LHip = V(6, 0, -4)
		pose.LKnee = V(-10, 0, 0)
		olharJogador(pose, ctx, 1, 0)
		pose.Taxa = 7
	else
		pose.Taxa = 5
	end
	return pose
end

-- TILUCA (zelador/missões) — poses de JoJo (KeyframeSequence "JojoPose")
local JOJO_A = {
	Root = V(7.6, 0, 0),
	RHip = V(7.1, 0.8, 3.2),
	LHip = V(-23.3, 2.0, -7.0),
	RShoulder = V(62.9, 11, -78.1), RElbow = V(70.2, 0, 0),
	LShoulder = V(-77.5, -15.9, -92.3), LElbow = V(70.2, 0, 0),
	Neck = V(-12.1, 0, 0),
}
local JOJO_B = espelhar(JOJO_A)
local JOJO_C = { -- "joestar": mão no rosto, tronco inclinado, perna aberta
	Root = V(-6, 0, 0), Waist = V(-8, 0, 6),
	RHip = V(-10, 0, 14), LHip = V(14, 0, -10), RKnee = V(-10, 0, 0), LKnee = V(-18, 0, 0),
	RShoulder = V(20, 0, 20), RElbow = V(12, 0, 0),
	LShoulder = V(88, 20, -10), LElbow = V(120, 0, 0),
	Neck = V(6, -14, 8),
}
local VARIANTES_JOJO = { JOJO_A, JOJO_B, JOJO_C, JOJO_A }

PERSONALIDADE.QuestGiver = function(p, t, dt, ctx)
	local e = p.Est
	e.Idx = e.Idx or 1
	e.Prox = e.Prox or (t + 5)
	if t >= e.Prox then
		e.Idx = (e.Idx % #VARIANTES_JOJO) + 1
		e.Prox = t + 5 + math.random() * 3
	end
	local pose = basePose(t)
	for nome, v in pairs(VARIANTES_JOJO[e.Idx]) do pose[nome] = v end
	-- "ゴゴゴ": tremor lento de presença
	local g = math.sin(t * 17) * 0.6
	pose.Waist = V((pose.Waist.X or 0) + g, pose.Waist.Y, pose.Waist.Z)
	pose.RootPos = V(0, 0.015 * math.sin(t * 2.1), 0)
	pose.Taxa = 3.2
	if ctx.Falando then
		-- falando: desfaz a pose, olha e gesticula devagar
		local base2 = basePose(t)
		for k, v in pairs(base2) do pose[k] = v end
		pose.Root = nil
		local nod = gestosDeFala(pose, t, p.T0 + 2, 0.9)
		olharJogador(pose, ctx, 1, nod)
		pose.Taxa = 6
	end
	return pose
end

-- BENTES / PEPE NEP (estatísticas) — sentado no banco, escreve num caderno
PERSONALIDADE.Estatisticas = function(p, t, dt, ctx)
	local pose = {
		RootPos = ZERO, Waist = ZERO, Neck = V(-9 + 2.5 * math.sin(t * 0.9), 6 * math.sin(t * 0.37), 0),
		RElbow = V(3 * math.sin(t * 9.5), 0, 0), RWrist = V(5 * math.sin(t * 9.5 + 0.7), 0, 3 * math.sin(t * 7)),
		LWrist = V(0, 0, 0),
	}
	local e = p.Est
	-- de vez em quando vira a página
	e.Prox = e.Prox or (t + 4)
	if t >= e.Prox then
		e.Virando = t + 0.7
		e.Prox = t + 4 + math.random() * 4
	end
	if e.Virando and e.Virando > t then
		pose.LWrist = V(-14, 0, 0)
		pose.Neck = V(-14, 0, 0)
	end
	if ctx.Falando then
		local nod = 3 * math.sin(t * 3.3)
		olharJogador(pose, ctx, 1, nod)
		pose.RElbow = V(10 + 12 * math.sin(t * 2.6), 0, 0)
		pose.RWrist = V(0, 0, 14 * math.sin(t * 2.6))
		pose.Taxa = 8
	elseif ctx.Tem and ctx.Dist < 20 then
		-- levanta os olhos do caderno e acompanha quem chegou
		olharJogador(pose, ctx, 0.9, -2)
		pose.Taxa = 7
	else
		pose.Taxa = 5
	end
	return pose
end

local ALIAS_PERSONALIDADE = {
	Kogamalotigo = "Kogamalotigo", ShopKeeper = "ShopKeeper", RollMaster = "RollMaster",
	QuestGiver = "QuestGiver", Estatisticas = "Estatisticas",
}
local MODO_POR_PERSONALIDADE = { Estatisticas = "assado" }

-- ============================================================
-- LOOP
-- ============================================================
local bonecos = {} -- [model] = p

local function procurar()
	for _, model in ipairs(CollectionService:GetTagged("Dialogue")) do
		if model:IsA("Model") and not bonecos[model] and model:IsDescendantOf(workspace) then
			local id = model:GetAttribute("DialogueId") or model.Name
			local nome = ALIAS_PERSONALIDADE[id]
			if nome and PERSONALIDADE[nome] then
				local ok, p = pcall(construir, model, MODO_POR_PERSONALIDADE[nome] or "neutro")
				if ok and p then
					p.Personalidade = nome
					bonecos[model] = p
				elseif not ok then
					warn("[NpcMarionete] " .. model.Name .. ": " .. tostring(p))
				end
			end
		end
	end
	for model, p in pairs(bonecos) do
		local valido = model:IsDescendantOf(workspace)
		if valido then
			for _, pc in pairs(p.Pecas) do
				if not pc:IsDescendantOf(model) then valido = false break end
			end
		end
		if not valido then bonecos[model] = nil end
	end
end

task.spawn(function()
	while true do
		procurar()
		task.wait(1.5)
	end
end)

RunService.RenderStepped:Connect(function(dt)
	local camera = workspace.CurrentCamera
	local cabecaJogador = player.Character and player.Character:FindFirstChild("Head")
	local agora = os.clock()
	for model, p in pairs(bonecos) do
		local hrp = p.Pecas.HumanoidRootPart
		if camera and (hrp.Position - camera.CFrame.Position).Magnitude < 130 then
			local t = agora + p.T0
			-- contexto (onde está o jogador em relação ao boneco)
			local ctx = { Tem = false, Yaw = 0, Pitch = 0, Dist = math.huge, Falando = model:GetAttribute("Falando") == true }
			if cabecaJogador then
				local v = p.RestHRP:PointToObjectSpace(cabecaJogador.Position)
				local horiz = math.sqrt(v.X * v.X + v.Z * v.Z)
				ctx.Tem = true
				ctx.Dist = (cabecaJogador.Position - p.RestHRP.Position).Magnitude
				ctx.Yaw = math.deg(math.atan2(-v.X, -v.Z))
				ctx.Pitch = math.deg(math.atan2(v.Y - 1.5, math.max(horiz, 0.1)))
			end
			local ok, alvo = pcall(PERSONALIDADE[p.Personalidade], p, t, dt, ctx)
			if ok and alvo then
				local k = 1 - math.exp(-(alvo.Taxa or 8) * dt)
				for _, nome in ipairs(NOMES_JUNTAS) do
					p.Atual[nome] = p.Atual[nome]:Lerp(emRot(alvo[nome]), k)
				end
				p.RootPos = p.RootPos:Lerp(alvo.RootPos or ZERO, k)
				aplicar(p, dt)
			elseif not ok then
				warn("[NpcMarionete] " .. p.Personalidade .. ": " .. tostring(alvo))
				bonecos[model] = nil
			end
		end
	end
end)

print("✅ NpcMarionete carregado (NPCs do Lobby se mexendo).")
