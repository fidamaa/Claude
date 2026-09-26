--[[
	EntranceCutsceneClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Game)

	PEDIDO: "quero também incluir uma cutscene de entrada. ela vai começar
	naqueles corredores de entrada ao estádio e os dois times vão passar ao
	mesmo tempo um ao lado do outro, numa fila tradicional, a ordem não
	importa, contanto que sejam do mesmo time, eles vão andando em direção
	ao campo, e depois corta pra todo mundo dentro de campo."

	COMO FUNCIONA: o servidor (EntranceCutsceneController.legacy.luau) manda
	um "roster" (quem está em cada time + pra onde cada um vai de verdade no
	kickoff — Remotes.PlayEntranceCutscene). Esse script:
	  1) esconde TODOS os personagens de verdade (só visual, só localmente —
	     mesma técnica do replay de gol, ver hideModel/restoreHiddenOriginals
	     abaixo, adaptada de GoalReplayClient.local.luau);
	  2) cria um "boneco" cosmético pra cada jogador (clone visual do
	     personagem real dele, sem física — mesma técnica de
	     buildGhostFromModel do replay de gol) e alinha os dois times em
	     fila, lado a lado, no túnel;
	  3) anda a fila do início ao fim do túnel, depois abre cada boneco pra
	     sua posição de formação de verdade no campo (o "corta pra todo
	     mundo dentro de campo" acontece suavemente aqui);
	  4) no final: destrói os bonecos, revela os personagens de verdade
	     (que já estavam esperando, parados, exatamente na posição certa) e
	     devolve a câmera/controle pro jogador.

	PARTS QUE PRECISAM EXISTIR NO STUDIO (ver comentário completo em
	FootballConfig.lua, Config.CUTSCENE_TUNNEL_START_PREFIX/_END_PREFIX):
	  CutsceneTunnelStart_<NomeDoTime> e CutsceneTunnelEnd_<NomeDoTime>,
	  uma dupla por time. Sem elas, essa cutscene é pulada silenciosamente
	  (só um aviso no console) — a partida sempre continua normal.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = workspace

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ===== REGISTRO PERSISTENTE DAS PARTS DO TÚNEL (mesmo padrão de GKAreaUtil.luau) =====
-- ⚠️ FIX: "a Tunnel azul não existe" mesmo com a Part já criada no lugar
-- certo — MESMA causa raiz dos avisos de GKAreaUtil colados pelo usuário:
-- Workspace.StreamingEnabled pode não ter replicado/streamado essa Part
-- pro CLIENTE ainda no exato instante em que a cutscene dispara (ela roda
-- bem no começo da partida, o pior momento possível pra isso). O código
-- antigo fazia só WaitForChild(nome, 2) UMA VEZ e desistia pra sempre se
-- não achasse em 2 segundos. Agora, igual GKAreaUtil: um registro que
-- escuta workspace.DescendantAdded PRA SEMPRE desde o carregamento do
-- script (então a Part pode "chegar" bem antes da cutscene rodar, sem
-- precisar reiniciar nada) + espera ativa mais longa (ver
-- findTunnelPartsForTeam) só como reforço extra na hora H.
local tunnelParts = {} -- [nomeCompletoDaPart] = Part

local function tryRegisterTunnelPart(inst)
	if not inst:IsA("BasePart") then return end
	local name = inst.Name
	if name:sub(1, #Config.CUTSCENE_TUNNEL_START_PREFIX) == Config.CUTSCENE_TUNNEL_START_PREFIX
		or name:sub(1, #Config.CUTSCENE_TUNNEL_END_PREFIX) == Config.CUTSCENE_TUNNEL_END_PREFIX then
		tunnelParts[name] = inst
	end
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	tryRegisterTunnelPart(inst)
end
Workspace.DescendantAdded:Connect(tryRegisterTunnelPart) -- nunca desliga — autocorrige sozinho se a Part chegar depois

-- Espera ativa (poll) na hora de disparar a cutscene, além do registro
-- permanente acima — reforço pro caso da Part streamar bem na hora H.
local function findTunnelPartsForTeam(teamName, timeoutSeconds)
	local startName = Config.CUTSCENE_TUNNEL_START_PREFIX .. teamName
	local endName = Config.CUTSCENE_TUNNEL_END_PREFIX .. teamName
	local deadline = os.clock() + (timeoutSeconds or 6)
	repeat
		local startPart = tunnelParts[startName] or Workspace:FindFirstChild(startName)
		local endPart = tunnelParts[endName] or Workspace:FindFirstChild(endName)
		if startPart and endPart then return startPart, endPart end
		task.wait(0.1)
	until os.clock() >= deadline
	return tunnelParts[startName] or Workspace:FindFirstChild(startName),
		tunnelParts[endName] or Workspace:FindFirstChild(endName)
end

-- ===== ESCONDER OS PERSONAGENS DE VERDADE (adaptado de GoalReplayClient) =====
-- Mesma técnica/comentário de fundo do replay de gol: LocalTransparencyModifier
-- é 100% local, não afeta física/servidor/outros jogadores, e cada tipo de
-- objeto usa a propriedade certa (Decal não tem "Enabled", só "Transparency")
-- pra nunca travar no meio e deixar alguém preso invisível.
local hiddenParts = {}
local hiddenBillboards = {}
local hiddenDecals = {}

local function hideInstance(inst)
	if inst:IsA("BasePart") then
		if hiddenParts[inst] == nil then
			hiddenParts[inst] = inst.LocalTransparencyModifier
		end
		inst.LocalTransparencyModifier = 1
	elseif inst:IsA("BillboardGui") then
		if hiddenBillboards[inst] == nil then
			hiddenBillboards[inst] = inst.Enabled
		end
		inst.Enabled = false
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		if hiddenDecals[inst] == nil then
			hiddenDecals[inst] = inst.Transparency
		end
		inst.Transparency = 1
	end
end

local function hideModel(model)
	if not model then return end
	pcall(hideInstance, model)
	for _, inst in ipairs(model:GetDescendants()) do
		pcall(hideInstance, inst)
	end
end

local function restoreHiddenOriginals()
	for part, value in pairs(hiddenParts) do
		pcall(function()
			if part.Parent then part.LocalTransparencyModifier = value end
		end)
	end
	hiddenParts = {}

	for gui, value in pairs(hiddenBillboards) do
		pcall(function()
			if gui.Parent then gui.Enabled = value end
		end)
	end
	hiddenBillboards = {}

	for decal, value in pairs(hiddenDecals) do
		pcall(function()
			if decal.Parent then decal.Transparency = value end
		end)
	end
	hiddenDecals = {}
end

-- ⚠️ NOVO: PEDIDO — "sempre que colidirem com o end vão sumir, e serem
-- teleportados" — cada jogador precisa ser revelado (o boneco dele
-- destruído, o personagem de verdade reaparecendo) NO MOMENTO EXATO em
-- que ELE chega no fim do túnel, não todo mundo de uma vez no final da
-- cutscene inteira. Mesma ideia de restoreHiddenOriginals, só que restrita
-- às Parts/GUIs/Decals de UM personagem só (removidas das tabelas globais
-- depois de restauradas, pra restoreHiddenOriginals no final não tentar
-- mexer de novo em algo que já foi revelado individualmente).
local function restoreOneModel(model)
	if not model then return end
	local function restoreInstance(inst)
		if hiddenParts[inst] ~= nil then
			local value = hiddenParts[inst]
			hiddenParts[inst] = nil
			pcall(function()
				if inst.Parent then inst.LocalTransparencyModifier = value end
			end)
		end
		if hiddenBillboards[inst] ~= nil then
			local value = hiddenBillboards[inst]
			hiddenBillboards[inst] = nil
			pcall(function()
				if inst.Parent then inst.Enabled = value end
			end)
		end
		if hiddenDecals[inst] ~= nil then
			local value = hiddenDecals[inst]
			hiddenDecals[inst] = nil
			pcall(function()
				if inst.Parent then inst.Transparency = value end
			end)
		end
	end
	restoreInstance(model)
	for _, inst in ipairs(model:GetDescendants()) do
		restoreInstance(inst)
	end
end

-- ===== BONECO COSMÉTICO (mesma técnica de GoalReplayClient.buildGhostFromModel) =====
-- Model de personagem tem Archivable=false por padrão no Roblox (proteção
-- de fábrica) — Model:Clone() sempre devolveria nil. Solução: clona Parte
-- por Parte (essas continuam Archivable=true) e monta um Model novo, sem
-- as juntas antigas (que ainda apontariam pro personagem de verdade, se
-- movendo, e ficariam "brigando" com o nosso PivotTo).
-- ⚠️ NOVO: PEDIDO — "faça a animação de andar antiga ser usada apenas
-- para aquela introdução de chegada dos personagens da cutscene, pode
-- colocar pra eles andarem com aquela animação" — o boneco da cutscene
-- (buildDummyFromModel) sempre foi 100% RÍGIDO (só desliza via PivotTo,
-- sem nenhuma perna se mexendo). Lê a animação de andar PADRÃO do Roblox
-- direto do "Animate" do personagem de verdade (a "antiga", ver
-- overrideMovementAnimations em PlayerSystems.legacy.luau — agora esse
-- script NÃO mexe mais no valor de Animate.walk.WalkAnim, então ele
-- sempre reflete o padrão do Roblox) e toca ela em loop no boneco
-- enquanto ele anda pelo túnel.
local function findDefaultWalkAnimationId(sourceModel)
	local animate = sourceModel:FindFirstChild("Animate")
	local walkFolder = animate and animate:FindFirstChild("walk")
	local walkAnim = walkFolder and walkFolder:FindFirstChild("WalkAnim")
	local id = walkAnim and walkAnim.AnimationId
	if type(id) == "string" and id ~= "" then
		return id
	end
	return nil
end

local function buildDummyFromModel(sourceModel, nameSuffix)
	if not sourceModel then return nil end

	local dummyRoot = Instance.new("Model")
	dummyRoot.Name = "EntranceCutsceneDummy_" .. nameSuffix

	-- ⚠️ v21: tenta primeiro clonar o Model INTEIRO (ver o mesmo comentário
	-- em GoalReplayClient.cloneWholeCharacter). Rig remontado na mão anda,
	-- mas não é um personagem válido pro Humanoid — o RootPart dele não é
	-- reconhecido e o Animator não tem onde aplicar os keyframes, então a
	-- animação toca sem erro e nada se mexe. Archivable é só uma
	-- propriedade: liga, clona, devolve como estava.
	do
		local previousArchivable = sourceModel.Archivable
		sourceModel.Archivable = true
		local okClone, modelClone = pcall(function() return sourceModel:Clone() end)
		sourceModel.Archivable = previousArchivable

		if okClone and modelClone then
			for _, inst in ipairs(modelClone:GetDescendants()) do
				if inst:IsA("Script") or inst:IsA("LocalScript") or inst:IsA("Sound") then
					inst:Destroy()
				elseif inst:IsA("BasePart") then
					inst.CanCollide = false
					inst.CanQuery = false
					inst.CanTouch = false
					inst.Anchored = false
				end
			end

			local wholeHumanoid = modelClone:FindFirstChildOfClass("Humanoid")
			if wholeHumanoid then
				wholeHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end

			local wholeRoot = modelClone:FindFirstChild("HumanoidRootPart")
				or (wholeHumanoid and wholeHumanoid.RootPart)
				or modelClone.PrimaryPart
				or modelClone:FindFirstChildWhichIsA("BasePart")

			if wholeRoot then
				wholeRoot.Anchored = true
				modelClone.Name = dummyRoot.Name
				modelClone.PrimaryPart = wholeRoot
				modelClone.Parent = Workspace
				dummyRoot:Destroy() -- o Model vazio do plano B não é mais necessário

				local walkTrackWhole = nil
				if wholeHumanoid then
					local animationId = Config.NormalizeAnimationId(Config.CUTSCENE_WALK_ANIMATION)
					if not animationId or animationId == "" then
						animationId = findDefaultWalkAnimationId(sourceModel)
					end
					if animationId then
						local animator = wholeHumanoid:FindFirstChildOfClass("Animator")
							or Instance.new("Animator", wholeHumanoid)
						local animation = Instance.new("Animation")
						animation.AnimationId = animationId
						local okTrack, track = pcall(function() return animator:LoadAnimation(animation) end)
						if okTrack and track then
							track.Looped = true
							track.Priority = Enum.AnimationPriority.Action
							track:Play()
							walkTrackWhole = track
						end
					end
				end

				return modelClone, walkTrackWhole
			end

			modelClone:Destroy()
		end
	end

	local clonedRoot = nil
	local anyPartCloned = false

	-- ⚠️ v18: mapa original -> clone, pra RECONSTRUIR as juntas depois.
	local cloneByOriginal = {}

	for _, inst in ipairs(sourceModel:GetDescendants()) do
		if inst:IsA("BasePart") then
			local ok, partClone = pcall(function() return inst:Clone() end)
			if ok and partClone then
				-- ⚠️ v18 FIX: só o HumanoidRootPart fica anchored. Antes TODA
				-- parte era — e parte anchored não anima, porque o Motor6D não
				-- consegue mover ela. Era por isso que o boneco do túnel
				-- deslizava congelado mesmo com o walkTrack tocando logo ali
				-- embaixo: a animação SEMPRE rodou, só não tinha como aparecer.
				partClone.Anchored = (inst.Name == "HumanoidRootPart")
				partClone.CanCollide = false
				partClone.CanQuery = false
				partClone.CanTouch = false
				for _, child in ipairs(partClone:GetChildren()) do
					if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("Sound")
						or child:IsA("JointInstance") or child:IsA("WeldConstraint") then
						child:Destroy()
					end
				end
				partClone.Parent = dummyRoot
				cloneByOriginal[inst] = partClone
				anyPartCloned = true
				if inst.Name == "HumanoidRootPart" then
					clonedRoot = partClone
				end
			end
		end
	end

	if not anyPartCloned then
		dummyRoot:Destroy()
		return nil
	end

	-- ⚠️ v18: juntas NOVAS ligando clone a clone. As clonadas precisavam
	-- morrer (apontavam pras partes do personagem vivo), mas ficar sem junta
	-- nenhuma é o que transformava o boneco numa estátua.
	local jointedParts = {}
	for _, inst in ipairs(sourceModel:GetDescendants()) do
		if inst:IsA("Motor6D") or inst:IsA("Weld") then
			local p0 = inst.Part0 and cloneByOriginal[inst.Part0]
			local p1 = inst.Part1 and cloneByOriginal[inst.Part1]
			if p0 and p1 then
				local joint = Instance.new(inst.ClassName)
				joint.Name = inst.Name
				joint.Part0 = p0
				joint.Part1 = p1
				joint.C0 = inst.C0
				joint.C1 = inst.C1
				joint.Parent = p0
				jointedParts[p0] = true
				jointedParts[p1] = true
			end
		end
	end

	-- Parte sem junta nenhuma volta a ser anchored, senão cai pelo mapa.
	for _, partClone in pairs(cloneByOriginal) do
		if not jointedParts[partClone] and not partClone.Anchored then
			partClone.Anchored = true
		end
	end

	local humanoidClone = nil
	for _, inst in ipairs(sourceModel:GetChildren()) do
		if inst:IsA("Shirt") or inst:IsA("Pants") or inst:IsA("BodyColors") or inst:IsA("ShirtGraphic") then
			local ok, clone = pcall(function() return inst:Clone() end)
			if ok and clone then
				clone.Parent = dummyRoot
			end
		elseif inst:IsA("Humanoid") then
			local ok, clone = pcall(function() return inst:Clone() end)
			if ok and clone then
				clone.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				clone.Parent = dummyRoot
				humanoidClone = clone
			end
		end
	end

	if not clonedRoot then
		clonedRoot = dummyRoot:FindFirstChildOfClass("BasePart")
	end
	if not clonedRoot then
		dummyRoot:Destroy()
		return nil
	end

	dummyRoot.PrimaryPart = clonedRoot
	-- ⚠️ v20 FIX: anchora o PrimaryPart de verdade (não a parte com o nome
	-- "HumanoidRootPart", que pode não existir) — sem uma parte anchorada o
	-- boneco vira física solta e para de acompanhar o PivotTo.
	clonedRoot.Anchored = true
	dummyRoot.Parent = Workspace

	-- Toca a animação de andar PADRÃO do Roblox (a "antiga") em loop
	-- enquanto o boneco desliza pelo túnel — some sozinha quando o boneco
	-- é destruído no reveal (ver dummy.walkTrack no loop de Heartbeat).
	local walkTrack = nil
	if humanoidClone then
		-- ⚠️ v18 — PEDIDO: "quero que você use essa animação de andar
		-- [89188098199704] também na cutscene de entrada". Prefere a animação
		-- configurada em Config.ANIMATIONS.Walk; só cai na animação padrão do
		-- Roblox (findDefaultWalkAnimationId) se aquela estiver vazia.
		local animationId = Config.NormalizeAnimationId(Config.CUTSCENE_WALK_ANIMATION)
		if not animationId or animationId == "" then
			animationId = findDefaultWalkAnimationId(sourceModel)
		end
		if animationId then
			local animator = humanoidClone:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoidClone)
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			if ok and track then
				track.Looped = true
				track:Play()
				walkTrack = track
			end
		end
	end

	return dummyRoot, walkTrack
end

-- ===== CONTROLE DO JOGADOR DURANTE A CUTSCENE =====
-- Trava o personagem no lugar (senão ele podia se afastar da posição de
-- kickoff enquanto está escondido/invisível, e reaparecer no lugar errado
-- quando a cutscene termina) e assume a câmera manualmente.
local savedWalkSpeed, savedJumpPower, savedAutoRotate = nil, nil, nil

local function freezeLocalCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	savedWalkSpeed = humanoid.WalkSpeed
	savedJumpPower = humanoid.JumpPower
	savedAutoRotate = humanoid.AutoRotate
	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
end

local function unfreezeLocalCharacter(character)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if savedWalkSpeed then humanoid.WalkSpeed = savedWalkSpeed end
	if savedJumpPower then humanoid.JumpPower = savedJumpPower end
	if savedAutoRotate ~= nil then humanoid.AutoRotate = savedAutoRotate end
	savedWalkSpeed, savedJumpPower, savedAutoRotate = nil, nil, nil
end

-- ⚠️ FIX: "StreamingTargetRadius is not a valid member of Workspace" —
-- essa propriedade nem existe nessa versão/engine (confirmado pelo mesmo
-- erro em GKAreaUtil.lua) — a versão anterior lia ela DIRETO dentro do
-- string.format, sem pcall, e isso quebrava a cutscene toda vez que uma
-- Part faltava (erro não protegido no meio de playEntranceCutscene). Cada
-- leitura agora é protegida individualmente. Também trocado de
-- GetChildren() (só filho DIRETO) pra GetDescendants() (a árvore
-- INTEIRA) — se a Part existir aninhada dentro de outro Model/Folder por
-- engano, em vez de direto em workspace, agora isso aparece no
-- diagnóstico junto com o Parent de verdade, em vez de dar falso negativo.
local function safeWorkspaceProperty(name)
	local ok, value = pcall(function() return (Workspace :: any)[name] end)
	if ok then return tostring(value) end
	return "indisponível nesta versão (propriedade não existe)"
end

local function printMissingTunnelDiagnostic(teamName)
	pcall(function()
		local needle = (Config.CUTSCENE_TUNNEL_START_PREFIX .. teamName):lower()
		local near = {}
		for _, inst in ipairs(Workspace:GetDescendants()) do
			if inst.Name:lower():find("cutscenetunnel", 1, true) or inst.Name:lower():find(needle:sub(1, 6), 1, true) then
				table.insert(near, string.format("'%s' (classe %s, parent '%s')", inst.Name, inst.ClassName, inst.Parent and inst.Parent.Name or "?"))
			end
		end
		warn(string.format(
			"🔎 [CLIENTE] Diagnóstico EntranceCutsceneClient pro time '%s': workspace.StreamingEnabled=%s | StreamingTargetRadius=%s | Parts com nome parecido em QUALQUER lugar de workspace: %s",
			teamName, safeWorkspaceProperty("StreamingEnabled"), safeWorkspaceProperty("StreamingTargetRadius"),
			(#near > 0) and table.concat(near, " , ") or "NENHUM em lugar nenhum de workspace (nem aninhado, nem por nome parecido/maiúscula-minúscula) — a Part não existe nessa sessão de teste."
		))
	end)
end

-- ===== A CUTSCENE EM SI =====
local cutscenePlaying = false

local function playEntranceCutscene(roster, duration)
	if cutscenePlaying then return end -- já tocando (não deveria disparar 2x, mas por segurança)

	duration = tonumber(duration) or Config.ENTRANCE_CUTSCENE_DURATION

	-- Descobre as Parts do túnel só pros times que TÊM alguém no roster —
	-- um time vazio (ninguém escolheu ele, ou 3v3/5v5 com vaga sobrando)
	-- não precisa de túnel nenhum.
	local tunnelByTeam = {}
	for teamName, list in pairs(roster) do
		if #list > 0 then
			local startPart, endPart = findTunnelPartsForTeam(teamName, 6)
			if not startPart or not endPart then
				printMissingTunnelDiagnostic(teamName)
				warn(("🎬 EntranceCutsceneClient: Part '%s%s'/'%s%s' não encontrada na cena (ainda) — cutscene de entrada pulada dessa vez. Se a Part já existe no Studio no lugar certo, isso deve se autocorrigir sozinho nas próximas partidas assim que ela terminar de streamar (workspace.DescendantAdded continua ouvindo, igual GKAreaUtil) — sem precisar reiniciar o server. Se persistir sempre, confira o nome exato da Part (ver comentário em FootballConfig.lua, Config.CUTSCENE_TUNNEL_START_PREFIX)."):format(
					Config.CUTSCENE_TUNNEL_START_PREFIX, teamName, Config.CUTSCENE_TUNNEL_END_PREFIX, teamName))
				return -- aborta só essa cutscene: sem túnel de um time, não dá pra mostrar "os dois lado a lado"
			end
			tunnelByTeam[teamName] = { Start = startPart, End = endPart }
		end
	end

	if not next(tunnelByTeam) then return end -- nenhum time com jogador (ex: testando sozinho)

	cutscenePlaying = true

	-- Esconde TODO personagem de verdade em campo (os dois times) — eles já
	-- estão parados na posição certa de formação (ver
	-- _G.PositionPlayerAtFormation no MatchController), só invisíveis
	-- enquanto o boneco cosmético "anda até lá" no lugar deles.
	for _, plr in ipairs(Players:GetPlayers()) do
		hideModel(plr.Character)
	end

	if player.Character then
		freezeLocalCharacter(player.Character)
	end

	-- ===== MONTA A FILA DE CADA TIME =====
	-- ⚠️ NOVO: cada boneco anda RETO em linha, na sua própria velocidade
	-- (mesma pra todos: distância do túnel / ENTRANCE_CUTSCENE_TUNNEL_SECONDS),
	-- e é revelado (destruído + personagem de verdade aparece) assim que
	-- CRUZA a Part End — não é mais uma fase única sincronizada por tempo
	-- pra todo mundo, então quem está mais atrás na fila cruza o End um
	-- pouco depois (mesmo espaçamento, mesma velocidade = chega depois).
	local dummies = {} -- { model, character, queueStartPos, forward, endPlaneDot, done }
	local remainingDummies = 0

	for teamName, tunnel in pairs(tunnelByTeam) do
		local list = roster[teamName]
		local forward = (tunnel.End.Position - tunnel.Start.Position)
		forward = Vector3.new(forward.X, 0, forward.Z)
		if forward.Magnitude < 0.01 then forward = Vector3.new(0, 0, -1) end
		forward = forward.Unit

		local tunnelDistance = (tunnel.End.Position - tunnel.Start.Position).Magnitude
		local walkSpeed = tunnelDistance / math.max(Config.ENTRANCE_CUTSCENE_TUNNEL_SECONDS, 0.1) -- studs/segundo

		for i, entry in ipairs(list) do
			local plr = Players:GetPlayerByUserId(entry.UserId)
			local character = plr and plr.Character
			if character then
				local dummy, walkTrack = buildDummyFromModel(character, teamName .. "_" .. tostring(entry.UserId))
				if dummy then
					-- fila tradicional: um atrás do outro, espaçados pra trás a
					-- partir da FRENTE (Start) — ordem dentro do time não importa
					-- (pedido explícito), só precisa ser fila.
					local queueStartPos = tunnel.Start.Position - forward * (i - 1) * Config.ENTRANCE_CUTSCENE_QUEUE_SPACING
					dummy:PivotTo(CFrame.lookAt(queueStartPos, queueStartPos + forward))

					remainingDummies += 1
					table.insert(dummies, {
						model = dummy,
						character = character,
						queueStartPos = queueStartPos,
						forward = forward,
						walkSpeed = walkSpeed,
						-- "cruzou o End" = a projeção da posição atual no eixo
						-- forward já passou da projeção do End nesse mesmo eixo.
						endPlaneDot = tunnel.End.Position:Dot(forward),
						done = false,
						-- ⚠️ FIX: "os jogadores estão parando na entrada do campo,
						-- eles precisam teleportar, após passar de TunnelEnd,
						-- direto pras suas posições" — antes disso o código
						-- CONFIAVA que o personagem de verdade já estava parado
						-- na posição de formação (comentário antigo: "já estão
						-- parados na posição certa"), mas isso depende de
						-- timing do servidor (_G.PositionPlayerAtFormation pode
						-- não ter rodado ainda quando a cutscene começa). Agora
						-- teleporta EXPLICITAMENTE pro FieldCFrame que o
						-- servidor já manda dentro do próprio roster (ver
						-- EntranceCutsceneController.legacy.luau, entry.
						-- FieldCFrame) — não depende mais de suposição nenhuma.
						fieldCFrame = entry.FieldCFrame,
						walkTrack = walkTrack,
					})
				end
			end
		end
	end

	-- Nenhum boneco de verdade foi criado (personagens sumiram entre o
	-- servidor mandar o roster e o cliente montar a fila) — não trava a
	-- partida esperando um "todos cruzaram" que nunca chega.
	if remainingDummies == 0 then
		for _, plr in ipairs(Players:GetPlayers()) do
			restoreOneModel(plr.Character)
		end
		if player.Character then unfreezeLocalCharacter(player.Character) end
		cutscenePlaying = false
		return
	end

	-- ===== CÂMERA =====
	-- Ponto médio de todas as Parts de início/fim do túnel (funciona com 1
	-- ou 2 times) pra enquadrar os dois lado a lado automaticamente, sem
	-- precisar de nenhuma Part de câmera extra.
	local sumStart, sumEnd, sumForward, count = Vector3.zero, Vector3.zero, Vector3.zero, 0
	for _, tunnel in pairs(tunnelByTeam) do
		sumStart += tunnel.Start.Position
		sumEnd += tunnel.End.Position
		local f = (tunnel.End.Position - tunnel.Start.Position)
		f = Vector3.new(f.X, 0, f.Z)
		if f.Magnitude > 0.01 then sumForward += f.Unit end
		count += 1
	end
	local midStart = sumStart / count
	local midEnd = sumEnd / count
	local avgForward = sumForward.Magnitude > 0.01 and sumForward.Unit or Vector3.new(0, 0, -1)

	-- ⚠️ NOVO: PEDIDO — "coloque a câmera no lado contrário, do final pro
	-- início" + "todos os jogadores precisam passar pela câmera e não sumir
	-- após chegar lá, faça a câmera um pouco mais pra frente, porque vai
	-- dar impressão que todos estão passando" — a câmera fica ANTES do End
	-- (Config.ENTRANCE_CUTSCENE_CAMERA_BEFORE_END studs, baixa/rasteira),
	-- olhando de volta pro Start: os dois times andam EM DIREÇÃO à câmera,
	-- passam visivelmente por ela, e só somem (revelados como personagem
	-- de verdade) um pouco DEPOIS, ao cruzar o End de verdade — nunca bem
	-- em cima do próprio ponto onde a câmera está.
	local tunnelCamCFrame = CFrame.lookAt(
		midEnd - avgForward * Config.ENTRANCE_CUTSCENE_CAMERA_BEFORE_END + Vector3.new(0, Config.ENTRANCE_CUTSCENE_CAMERA_HEIGHT, 0),
		midStart + Vector3.new(0, 1, 0)
	)

	-- Enquadramento amplo do campo pro corte final ("corta pra todo mundo
	-- dentro de campo") — usa o próprio hitbox do campo (sempre existe,
	-- outros sistemas já dependem dele) em vez de pedir mais uma Part nova.
	local campoHit = Workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
	local fieldOverviewCFrame
	if campoHit then
		local size = campoHit.Size
		local highPoint = campoHit.Position + Vector3.new(0, math.max(size.X, size.Z) * 0.55, 0)
		fieldOverviewCFrame = CFrame.lookAt(
			highPoint - avgForward * (math.max(size.X, size.Z) * 0.32),
			campoHit.Position
		)
	else
		fieldOverviewCFrame = tunnelCamCFrame
	end

	-- ⚠️ NOVO: PEDIDO — "coloque um take no final da animação, do campo
	-- por cima, por uns 2 segundos" — bem mais alto e quase reto pra baixo
	-- (diferente do fieldOverviewCFrame acima, que é um ângulo mais
	-- diagonal/baixo). Desloca um pouquinho na horizontal de propósito: um
	-- CFrame.lookAt totalmente vertical (reto pra baixo) deixa o
	-- LookVector paralelo ao eixo Y, e o RightVector interno vira NaN —
	-- mesmo bug já visto em applyCurve (BallController.lua) — um pequeno
	-- desvio evita isso.
	-- ⚠️ NOVO: PEDIDO — "vou colocar uma part pra você inserir a câmera nela
	-- 'CutsceneAirCamera'" — se essa Part existir, usa a CFrame dela
	-- (posição e ângulo exatos montados no Studio) pro take aéreo final,
	-- em vez do cálculo automático abaixo.
	-- ⚠️ v30 — PEDIDO: "sabe a cutscene que vai pra uma câmera que grava o
	-- campo? remova isso. Depois de entrarem, os times se infileiram nas
	-- extremidades do círculo central, a câmera trava 2 segundos de um lado,
	-- depois vai pro outro lado, 180 graus, pra gravar os times se
	-- encarando. Depois começa a partida."
	--
	-- O take aéreo saiu. O `finalOverheadCFrame` continua sendo calculado só
	-- como PLANO B: se por algum motivo não der pra montar o encaramento
	-- (não achou os gols pra saber onde é o círculo central), a cutscene
	-- volta pro comportamento antigo em vez de travar.
	-- A Part 'CutsceneAirCamera' não é mais usada — pode deletar do Studio.
	local finalOverheadCFrame
	if campoHit then
		-- ⚠️ FIX: "a câmera do campo está virada pra cima, é pra ficar pra
		-- baixo" — CFrame.lookAt perto da vertical (câmera quase reto pra
		-- baixo, como esse take pede) é uma conta instável (produto
		-- vetorial degenera quando o LookVector fica quase paralelo ao Up
		-- padrão (0,1,0)) e podia inverter a rotação, fazendo a câmera
		-- "olhar pra cima" na prática. Trocado por CFrame.Angles, que NUNCA
		-- tem esse problema: um pitch de -90° em X sempre aponta reto pra
		-- BAIXO (LookVector = (0,-1,0)), sem ambiguidade nenhuma de eixo.
		local size = campoHit.Size
		local topPoint = campoHit.Position + Vector3.new(0, math.max(size.X, size.Z) * 1.15, 0)
		finalOverheadCFrame = CFrame.new(topPoint) * CFrame.Angles(math.rad(-90), 0, 0)
	else
		finalOverheadCFrame = fieldOverviewCFrame
	end

	camera.CameraType = Enum.CameraType.Scriptable

	-- ⚠️ v36 — PEDIDO: "cutscene precisa de mais zoom na câmera ainda, 50%
	-- maior". O v34 já tinha dobrado a APROXIMAÇÃO (ZOOM_DISTANCE 16 -> 34)
	-- e não dá pra continuar por aí: a câmera termina o movimento a 54
	-- studs do centro e a fila de jogadores está a 46 — mais 50% de dolly
	-- (51) colocaria a câmera 9 studs À FRENTE do time, atravessando a
	-- fila. Então este 50% vem de zoom de LENTE, que é o que "zoom de
	-- câmera" quer dizer de verdade e não esbarra em geometria nenhuma.
	-- A conta: o tamanho do time na tela é proporcional a 1/tan(FOV/2).
	-- tan(70/2) = 0.700; pra tudo aparecer 1.5x maior preciso de
	-- tan(FOV/2) = 0.700 / 1.5 = 0.467 -> FOV = 50. Restaurado no fim da
	-- cutscene (nos DOIS caminhos de saída, incluindo a rede de segurança).
	local fovOriginal = camera.FieldOfView

	-- ===== ANIMAÇÃO =====
	-- ⚠️ NOVO: já não é mais "uma passada só sincronizada por tempo pra
	-- todo mundo" — agora cada boneco anda reto na sua própria velocidade
	-- até CRUZAR o End (revelado ali, individualmente); a câmera só sobe
	-- pro take aéreo quando `remainingDummies` chegar a 0 (ver comentário
	-- em Config.ENTRANCE_CUTSCENE_TUNNEL_SAFETY_SECONDS).
	local safetySeconds = math.max(Config.ENTRANCE_CUTSCENE_TUNNEL_SAFETY_SECONDS, 1)
	local overheadSeconds = math.max(Config.ENTRANCE_CUTSCENE_OVERHEAD_SECONDS, 0.1)
	local overheadTransitionSeconds = math.min(0.6, overheadSeconds)

	-- ===== ⚠️ v30: ENCARAMENTO NO CÍRCULO CENTRAL =====
	-- Monta, UMA vez, as posições de fila dos dois times nas bordas opostas
	-- do círculo central e as duas câmeras (uma de cada lado, 180° entre
	-- elas). Devolve nil se não der pra descobrir onde fica o círculo — aí o
	-- chamador cai no plano B (take aéreo antigo).
	local function montarEncaramento()
		local golAzul = Workspace:FindFirstChild(Config.BLUE_GOAL_NAME, true)
		local golAmarelo = Workspace:FindFirstChild(Config.YELLOW_GOAL_NAME, true)
		if not golAzul or not golAmarelo then return nil end

		local centro = (golAzul.Position + golAmarelo.Position) / 2
		local eixo = golAmarelo.Position - golAzul.Position
		eixo = Vector3.new(eixo.X, 0, eixo.Z)
		if eixo.Magnitude < 1 then return nil end
		eixo = eixo.Unit
		local lado = Vector3.new(-eixo.Z, 0, eixo.X) -- perpendicular horizontal

		local raio = Config.CUTSCENE_FACEOFF_RADIUS
		local passo = Config.CUTSCENE_FACEOFF_SPACING

		-- Cada time numa borda do círculo, virado pro outro.
		local times = {}
		for teamName in pairs(tunnelByTeam) do table.insert(times, teamName) end
		table.sort(times) -- ordem estável: o mesmo time sempre no mesmo lado

		local filas = {}
		for indice, teamName in ipairs(times) do
			-- índice 1 fica do lado do gol azul, índice 2 do lado oposto
			local sentido = (indice == 1) and -1 or 1
			filas[teamName] = {
				origem = centro + eixo * (raio * sentido),
				olhar = -sentido, -- olha PRA DENTRO, na direção do outro time
			}
		end

		-- Posiciona os personagens de verdade nas filas.
		for teamName, fila in pairs(filas) do
			local lista = roster[teamName] or {}
			local total = #lista
			for i, entrada in ipairs(lista) do
				local plr = Players:GetPlayerByUserId(entrada.UserId)
				local personagem = plr and plr.Character
				if personagem then
					-- centraliza a fila: -(n-1)/2 .. +(n-1)/2
					local deslocamento = (i - 1 - (total - 1) / 2) * passo
					local pos = fila.origem + lado * deslocamento
					pos = Vector3.new(pos.X, (entrada.FieldCFrame and entrada.FieldCFrame.Position.Y) or pos.Y, pos.Z)
					personagem:PivotTo(CFrame.lookAt(pos, pos + eixo * fila.olhar))
				end
			end
		end

		-- Duas câmeras opostas: cada uma por trás de um time, olhando pro
		-- outro. É isso que dá a leitura de "os dois se encarando".
		local altura = Config.CUTSCENE_FACEOFF_CAMERA_HEIGHT
		local recuo = Config.CUTSCENE_FACEOFF_CAMERA_DISTANCE
		local alvo = centro + Vector3.new(0, altura * 0.35, 0)

		-- ⚠️ v33 — PEDIDO: "coloca um jogo de câmera pra dar um zoom com um
		-- pouco de movimento no time que ele tá exibindo."
		-- Cada lado tem DOIS CFrames: onde a câmera começa (mais longe e mais
		-- alta) e onde ela termina (mais perto e mais baixa). O Heartbeat
		-- interpola entre os dois durante o hold, então a câmera "entra" no
		-- time devagar em vez de ficar parada.
		local aproxima = Config.CUTSCENE_FACEOFF_ZOOM_DISTANCE
		local abaixa = Config.CUTSCENE_FACEOFF_ZOOM_DROP

		local function par(sentido)
			local base = centro + eixo * ((raio + recuo) * sentido)
			local perto = centro + eixo * ((raio + recuo - aproxima) * sentido)
			return {
				CFrame.lookAt(base + Vector3.new(0, altura, 0), alvo),
				CFrame.lookAt(perto + Vector3.new(0, altura - abaixa, 0), alvo),
			}
		end

		return par(1), par(-1)
	end

	local encaramentoPronto = false
	local camEncaraA, camEncaraB = nil, nil
	local HOLD = math.max(Config.CUTSCENE_FACEOFF_HOLD_SECONDS, 0.2)

	local startTick = os.clock()
	local allCrossedAt = nil -- os.clock() de quando o ÚLTIMO boneco cruzou o End (nil = ainda tem gente andando)
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - startTick

		-- ===== FASE 1: TÚNEL — cada boneco anda reto até cruzar o End =====
		if not allCrossedAt then
			for _, dummy in ipairs(dummies) do
				if not dummy.done and dummy.model.Parent then
					local traveled = dummy.walkSpeed * elapsed
					local currentPos = dummy.queueStartPos + dummy.forward * traveled
					-- ⚠️ v19 FIX: mesma coisa do replay — Model:PivotTo todo frame
					-- reposicionava os membros junto e apagava a pose da
					-- animação. Move só o HumanoidRootPart anchorado; os Motor6D
					-- (reconstruídos em buildDummyFromModel) levam o corpo.
					-- ⚠️ v20: de volta pro PivotTo (ver o mesmo comentário em
					-- GoalReplayClient) — o que travava o movimento era não ter
					-- parte anchorada, não o PivotTo.
					dummy.model:PivotTo(CFrame.lookAt(currentPos, currentPos + dummy.forward))

					if currentPos:Dot(dummy.forward) >= dummy.endPlaneDot then
						-- cruzou o End: some o boneco e TELEPORTA o personagem de
						-- verdade direto pra posição de formação (fieldCFrame,
						-- mandado pelo servidor no roster) ANTES de revelar —
						-- ele fica travado lá (freezeLocalCharacter já trava o
						-- LOCAL; pra jogadores remotos, o próprio servidor só
						-- libera o jogo depois que a partida começa de verdade)
						-- até o kickoff, sem parar na entrada do túnel.
						dummy.done = true
						dummy.model:Destroy()
						if dummy.fieldCFrame and dummy.character then
							dummy.character:PivotTo(dummy.fieldCFrame)
						end
						restoreOneModel(dummy.character)
						remainingDummies -= 1
					end
				elseif not dummy.done then
					-- boneco sumiu por algum outro motivo (ex: parte destruída);
					-- conta como "cruzado" pra não travar o resto da cutscene.
					dummy.done = true
					restoreOneModel(dummy.character)
					remainingDummies -= 1
				end
			end

			if remainingDummies <= 0 then
				allCrossedAt = os.clock()
			end

			camera.CFrame = tunnelCamCFrame
		else
			-- ===== FASE 2 (v30): ENCARAMENTO NO CÍRCULO CENTRAL =====
			local faseElapsed = os.clock() - allCrossedAt

			if not encaramentoPronto then
				encaramentoPronto = true
				camEncaraA, camEncaraB = montarEncaramento()
				-- ⚠️ v36: zoom de lente só no encaramento — o take do túnel
				-- continua com o FOV normal (ele precisa do campo de visão
				-- aberto pra caber o corredor inteiro).
				if camEncaraA and camEncaraB then
					camera.FieldOfView = Config.CUTSCENE_FACEOFF_FOV
				end
			end

			if camEncaraA and camEncaraB then
				if faseElapsed < HOLD then
					-- LADO 1: entra na câmera vindo do túnel e, ao mesmo tempo,
					-- vai aproximando do time. `zoom` anda de 0 a 1 ao longo do
					-- hold inteiro — é o movimento lento que dá vida ao plano.
					local zoom = math.clamp(faseElapsed / HOLD, 0, 1)
					local destino = camEncaraA[1]:Lerp(camEncaraA[2], zoom)
					local entrada = math.clamp(faseElapsed / overheadTransitionSeconds, 0, 1)
					camera.CFrame = tunnelCamCFrame:Lerp(destino, entrada)
				else
					-- LADO 2: CORTE SECO de 180°, sem lerp de propósito — é o
					-- corte de transmissão esportiva; interpolar aqui daria uma
					-- volta tonta em torno do campo. O zoom recomeça do zero.
					local zoom = math.clamp((faseElapsed - HOLD) / HOLD, 0, 1)
					camera.CFrame = camEncaraB[1]:Lerp(camEncaraB[2], zoom)
				end
			else
				-- Plano B: não achei os gols, volta pro take aéreo antigo.
				local alpha = math.clamp(faseElapsed / overheadTransitionSeconds, 0, 1)
				camera.CFrame = tunnelCamCFrame:Lerp(finalOverheadCFrame, alpha)
			end

			local duracaoFase = (camEncaraA and camEncaraB) and (HOLD * 2) or overheadSeconds
			if faseElapsed >= duracaoFase then
				connection:Disconnect()

				restoreHiddenOriginals() -- rede de segurança: qualquer coisa que não tenha sido revelada individualmente
				unfreezeLocalCharacter(player.Character)

				camera.FieldOfView = fovOriginal
				camera.CameraType = Enum.CameraType.Custom
				local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				if humanoid then
					camera.CameraSubject = humanoid
				end

				cutscenePlaying = false
			end
		end

		-- Margem de segurança: se algo travou (ex: nunca deu allCrossedAt
		-- por bonecos presos), força o fim da cutscene em vez de deixar o
		-- jogador congelado pra sempre. `cutscenePlaying` já checa se o fim
		-- normal (acima) não rodou nesse mesmo tick antes desse aqui.
		-- ⚠️ v30: a rede de segurança precisa cobrir a fase mais LONGA das
		-- duas (encaramento = 2 × HOLD), senão ela cortaria a cutscene no
		-- meio do segundo ângulo.
		if cutscenePlaying and elapsed >= safetySeconds + math.max(overheadSeconds, HOLD * 2 + 1) then
			connection:Disconnect()

			for _, dummy in ipairs(dummies) do
				if dummy.model.Parent then dummy.model:Destroy() end
			end

			restoreHiddenOriginals()
			unfreezeLocalCharacter(player.Character)

			camera.FieldOfView = fovOriginal
			camera.CameraType = Enum.CameraType.Custom
			local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if humanoid then
				camera.CameraSubject = humanoid
			end

			cutscenePlaying = false
		end
	end)
end

Remotes.PlayEntranceCutscene.OnClientEvent:Connect(playEntranceCutscene)

print("✅ EntranceCutsceneClient carregado.")
