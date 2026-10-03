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

	Personalidades (DialogueId do boneco) — ⚠️ v118 nomes: Fidama, Lavinho, Pedro,
	Tiluca, Bentes:
	  Kogamalotigo — o Fidama (técnico): parado, de repente vira a cabeça seca pra um
	                 lado, depois pro outro, e volta.
	  ShopKeeper   — o Lavinho (lojista): apoiado no balcão, passa o pano, acena pra
	                 quem chega e gesticula falando.
	  RollMaster   — o Pedro: pose relaxada de mão na cintura; quando o jogador
	                 chega perto ele CHAMA (braço levantado, acenando "vem cá");
	                 falando, muda pra gestos de conversa.
	  QuestGiver   — o Tiluca: poses de JoJo com os braços bem abertos (ele é gordo:
	                 braço cruzando o corpo entra na barriga).
	  Estatisticas — o Bentes no banco: desenhando no caderno, com a Caneta do mapa
	                 presa na mão; levanta a cabeça quando alguém chega.

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

	-- ⚠️ v118 — objetos de MÃO que ficam fora do Model (ex.: a "Caneta" do Bentes, que
	-- o usuário montou no mapa do lado dele): qualquer Model/Part chamado "Caneta"
	-- (ou "Lapis") a até 4 studs da mão direita passa a seguir a mão.
	if model.Parent then
		local mao = pecas.RightHand
		for _, obj in ipairs(model.Parent:GetChildren()) do
			local nome = obj.Name:lower()
			if (nome == "caneta" or nome == "lapis" or nome == "lápis") and obj ~= model then
				local lista = obj:IsA("BasePart") and { obj } or obj:GetDescendants()
				for _, parte in ipairs(lista) do
					if parte:IsA("BasePart") and (parte.Position - mao.Position).Magnitude < 4 then
						parte.Anchored = true
						table.insert(acessorios, { Parte = parte, Corpo = "RightHand", Rel = baked.RightHand:ToObjectSpace(parte.CFrame) })
					end
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

-- LAVINHO (lojista) — ⚠️ v118: PEDIDO "o Lavinho não precisa ficar com medo, ele é
-- um lojista, coloca ele numa posição que faça sentido". Apoiado no balcão com as
-- duas mãos, de vez em quando passa um pano no balcão; quando alguém chega, acena
-- e acompanha com o olhar; falando, gesticula como vendedor.
PERSONALIDADE.ShopKeeper = function(p, t, dt, ctx)
	local pose = basePose(t)
	local e = p.Est
	-- apoiado no balcão
	pose.Waist = V(-14 + 1.2 * math.sin(t * 1.3), 0, 0)
	pose.RShoulder = V(48, 0, 14)
	pose.LShoulder = V(48, 0, -14)
	pose.RElbow = V(38, 0, 0)
	pose.LElbow = V(38, 0, 0)
	pose.RWrist = V(-20, 0, 0)
	pose.LWrist = V(-20, 0, 0)
	pose.RHip = V(4, 0, 4)
	pose.LHip = V(-6, 0, -4)
	pose.LKnee = V(-8, 0, 0)
	pose.Neck = V(-6, 10 * math.sin(t * 0.4), 0)
	-- chegou alguém perto: um aceno rápido (uma vez por chegada)
	local perto = ctx.Tem and ctx.Dist < 22
	if perto and not e.Perto then e.AcenoAte = t + 1.6 end
	e.Perto = perto
	if ctx.Falando then
		local nod = gestosDeFala(pose, t, p.T0, 0.9)
		pose.Waist = V(-6, 0, 0)
		olharJogador(pose, ctx, 1, nod)
		pose.Taxa = 8
	elseif e.AcenoAte and e.AcenoAte > t then
		local w = math.sin(t * 9)
		pose.RShoulder = V(70, 0, 30)
		pose.RElbow = V(95 + 25 * w, 0, 0)
		pose.RWrist = V(0, 0, 18 * w)
		pose.Waist = V(-6, 0, 0)
		olharJogador(pose, ctx, 1, 4)
		pose.Taxa = 9
	else
		-- passa o pano no balcão de tempos em tempos
		e.ProxPano = e.ProxPano or (t + 3)
		if t >= e.ProxPano then
			e.PanoAte = t + 2.4
			e.ProxPano = t + 6 + math.random() * 5
		end
		if e.PanoAte and e.PanoAte > t then
			local a = t * 6
			pose.RShoulder = V(55 + 8 * math.sin(a), 6 * math.cos(a), 18 + 6 * math.cos(a))
			pose.RElbow = V(30 + 10 * math.sin(a + 1), 0, 0)
			pose.Neck = V(-14, -12, 0)
		end
		if perto then olharJogador(pose, ctx, 0.8, -4) end
		pose.Taxa = 6
	end
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

-- TILUCA (missões) — poses de JoJo.
-- ⚠️ v118 — PEDIDO: "o Tiluca tá com o braço estranho" — o boneco dele é GORDO, e as
-- poses com o braço cruzando o corpo enfiavam a mão na barriga. Agora todo braço
-- que passa na frente do corpo fica bem aberto (ombro ≥ 40° pro lado) e as poses
-- são de braço pra cima/pra fora.
local JOJO_A = { -- "Jotaro": aponta pra frente, a outra mão aberta pro lado
	Waist = V(-4, 22, 0), Neck = V(4, -18, 0),
	RShoulder = V(82, 0, 28), RElbow = V(8, 0, 0),
	LShoulder = V(10, 0, -58), LElbow = V(70, 0, 0),
	RHip = V(0, 0, 12), LHip = V(12, 0, -10), LKnee = V(-12, 0, 0),
}
local JOJO_B = { -- "Giorno": mão pra cima ao lado da cabeça, tronco torto
	Waist = V(6, -16, -10), Neck = V(10, 14, 6),
	RShoulder = V(150, 0, 36), RElbow = V(70, 0, 0),
	LShoulder = V(18, 0, -62), LElbow = V(45, 0, 0),
	RHip = V(-6, 0, 14), LHip = V(8, 0, -8), RKnee = V(-6, 0, 0),
}
local JOJO_C = { -- "Dio": braços abertos, inclinado pra trás, dominante
	Waist = V(12, 0, 0), Neck = V(14, 0, 0),
	RShoulder = V(30, 0, 72), RElbow = V(28, 0, 0),
	LShoulder = V(30, 0, -72), LElbow = V(28, 0, 0),
	RHip = V(0, 0, 10), LHip = V(0, 0, -10),
}
local VARIANTES_JOJO = { JOJO_A, JOJO_B, JOJO_C, espelhar(JOJO_A) }

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

-- BENTES (estatísticas) — sentado no banco, DESENHANDO no caderno.
-- ⚠️ v118 — PEDIDO: "faz ele literalmente desenhando: tem que mexer o lápis que ele
-- tá na mão também". A caneta do mapa ("Caneta", ver construir) segue a mão direita;
-- a mão faz traços curtos e rápidos e vai descendo de linha, como quem rabisca.
PERSONALIDADE.Estatisticas = function(p, t, dt, ctx)
	local linha = (t % 3.4) / 3.4 -- 0..1 atravessando uma "linha" do desenho
	local traco = math.sin(t * 15)
	local volta = linha > 0.88 -- fim da linha: a mão volta pro começo
	local pose = {
		RootPos = ZERO, Waist = V(-2, 0, 0),
		Neck = V(-11 + 1.5 * math.sin(t * 0.9), 4 * math.sin(t * 0.37), 0),
		RShoulder = V(2 * traco, volta and 0 or (linha * 16 - 8), 0),
		RElbow = V(volta and 3 or (3 * traco + 2 * math.sin(t * 5.3)), 0, 0),
		RWrist = V(6 * math.sin(t * 15 + 0.7), 0, 10 * traco),
		LWrist = V(0, 0, 0),
	}
	local e = p.Est
	-- de vez em quando para, olha o desenho de longe e volta
	e.Prox = e.Prox or (t + 6)
	if t >= e.Prox then
		e.OlhandoAte = t + 1.2
		e.Prox = t + 6 + math.random() * 5
	end
	if e.OlhandoAte and e.OlhandoAte > t then
		pose.Waist = V(6, 0, 0)
		pose.Neck = V(-4, 6, 4)
		pose.RShoulder = V(-6, 0, 0)
		pose.RElbow = ZERO
		pose.RWrist = ZERO
	end
	if ctx.Falando then
		local nod = 3 * math.sin(t * 3.3)
		olharJogador(pose, ctx, 1, nod)
		pose.RShoulder = V(-4, 0, 0)
		pose.RElbow = V(8 + 10 * math.sin(t * 2.6), 0, 0)
		pose.RWrist = V(0, 0, 14 * math.sin(t * 2.6))
		pose.Taxa = 8
	elseif ctx.Tem and ctx.Dist < 14 then
		-- levanta os olhos do caderno e acompanha quem chegou (sem parar de rabiscar)
		olharJogador(pose, ctx, 0.8, -2)
		pose.Taxa = 12
	else
		pose.Taxa = 14
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
