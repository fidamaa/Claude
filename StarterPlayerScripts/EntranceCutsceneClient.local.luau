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
-- ⚠️ v112 — PEDIDO: "eles não vão poder se mexer, nem ativar a trava do shift, nem
-- nada enquanto tiver na cutscene de entrada". Antes zerava o WalkSpeed uma vez —
-- mas o PlayerSystems reescreve o WalkSpeed todo quadro, então dava pra andar.
-- Agora usa o CORPO TRAVADO do FootballClient (_G.CorpoTravadoAte: Move(zero),
-- sem pulo, sem girar, todo quadro) e _G.CutsceneEntradaAtiva, que o Ctrl lê
-- (não liga/desliga a trava durante a cutscene).
local guisEscondidas = {}
local function travarJogador(travar)
	_G.CutsceneEntradaAtiva = travar and true or nil
	-- ⚠️ v112: HUD (placar, botões) some durante a cutscene — cobria o rosto
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if travar and pg then
		for _, g in ipairs(pg:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled then
				g.Enabled = false
				guisEscondidas[g] = true
			end
		end
	elseif not travar then
		for g in pairs(guisEscondidas) do
			if g.Parent then g.Enabled = true end
		end
		guisEscondidas = {}
	end
	if travar then
		_G.CorpoTravadoAte = math.huge
	elseif _G.CorpoTravadoAte == math.huge then
		_G.CorpoTravadoAte = 0
	end
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
-- ⚠️ v112 — REFEITA (ver o PEDIDO em Config.ENTRADA_*):
--   FASE 1 — as duas filas saem do túnel LADO A LADO, em linha reta, e seguem
--            pro gramado; a câmera vai na FRENTE delas, recuando junto, baixa e
--            perto (o túnel é enorme pro tamanho dos personagens — de longe eles
--            sumiam). Os bonecos andam com a animação de verdade do jogo
--            (_G.AnimadorRegistrar — o asset de caminhada antigo não pegava nos
--            personagens com juntas novas e eles deslizavam parados).
--   FASE 2 — cada time em fila na borda do círculo central, virado pro outro; a
--            câmera passa RENTE, na altura do rosto, de um jogador ao outro; corta
--            pro outro time.
--   FIM    — tudo volta: personagem de verdade na posição de saída, câmera,
--            controle e a trava do Ctrl liberados.
local cutscenePlaying = false

local function alturaDoRosto(character, fallbackY)
	local head = character and character:FindFirstChild("Head")
	if head then return head.Position.Y end
	return fallbackY + 1.6
end

local function playEntranceCutscene(roster, duration)
	if cutscenePlaying then return end

	-- túneis só dos times que TÊM alguém no roster
	local tunnelByTeam = {}
	for teamName, list in pairs(roster) do
		if #list > 0 then
			local startPart, endPart = findTunnelPartsForTeam(teamName, 6)
			if not startPart or not endPart then
				printMissingTunnelDiagnostic(teamName)
				warn(("🎬 EntranceCutsceneClient: Part '%s%s'/'%s%s' não encontrada — cutscene de entrada pulada."):format(
					Config.CUTSCENE_TUNNEL_START_PREFIX, teamName, Config.CUTSCENE_TUNNEL_END_PREFIX, teamName))
				return
			end
			tunnelByTeam[teamName] = { Start = startPart, End = endPart }
		end
	end
	if not next(tunnelByTeam) then return end

	cutscenePlaying = true
	travarJogador(true)
	for _, plr in ipairs(Players:GetPlayers()) do
		hideModel(plr.Character)
	end

	-- ===== GEOMETRIA DA ENTRADA: um eixo só, as duas filas lado a lado =====
	local somaFim, somaFrente, n = Vector3.zero, Vector3.zero, 0
	for _, tunnel in pairs(tunnelByTeam) do
		somaFim += tunnel.End.Position
		local f = tunnel.End.Position - tunnel.Start.Position
		f = Vector3.new(f.X, 0, f.Z)
		if f.Magnitude > 0.01 then somaFrente += f.Unit end
		n += 1
	end
	local bocaDoTunel = somaFim / n
	local frente = somaFrente.Magnitude > 0.01 and somaFrente.Unit or Vector3.new(0, 0, 1)
	local lado = frente:Cross(Vector3.yAxis).Unit

	local times = {}
	for teamName in pairs(tunnelByTeam) do table.insert(times, teamName) end
	table.sort(times)

	local velocidade = Config.ENTRADA_VELOCIDADE or 11
	local antes = Config.ENTRADA_INICIO_ANTES_DO_FIM or 38
	local depois = Config.ENTRADA_ANDA_DEPOIS_DO_FIM or 26
	local gap = Config.ENTRADA_DISTANCIA_ENTRE_FILAS or 7
	local espaco = Config.ENTRANCE_CUTSCENE_QUEUE_SPACING or 5
	local T1 = (antes + depois) / velocidade

	local dummies = {}
	local entradaDoLocal = nil
	for indice, teamName in ipairs(times) do
		local deslocLado = (#times == 1) and 0 or ((indice == 1) and -gap / 2 or gap / 2)
		local frenteDaFila = bocaDoTunel - frente * antes + lado * deslocLado
		for i, entry in ipairs(roster[teamName]) do
			local plr = Players:GetPlayerByUserId(entry.UserId)
			local character = plr and plr.Character
			if plr == player then entradaDoLocal = entry end
			if character then
				local dummy, walkTrack = buildDummyFromModel(character, teamName .. "_" .. tostring(entry.UserId))
				if dummy then
					-- a animação é a do jogo (AnimadorProcedural), não o asset antigo
					if walkTrack then pcall(function() walkTrack:Stop(0) end) end
					-- SempreNoChao: o piso do túnel não tem colisão (ver AnimadorProcedural)
					if _G.AnimadorRegistrar then _G.AnimadorRegistrar(dummy, { SempreNoChao = true }) end
					local inicio = frenteDaFila - frente * (i - 1) * espaco
					dummy:PivotTo(CFrame.lookAt(inicio, inicio + frente))
					table.insert(dummies, { model = dummy, inicio = inicio, time = teamName })
				end
			end
		end
	end

	if #dummies == 0 then
		for _, plr in ipairs(Players:GetPlayers()) do restoreOneModel(plr.Character) end
		travarJogador(false)
		cutscenePlaying = false
		return
	end

	local fovOriginal = camera.FieldOfView
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = Config.ENTRADA_CAMERA_FOV or 60

	-- ===== FASE 2: filas no círculo central + câmera de rosto =====
	-- ⚠️ v112 — PEDIDO: "tem que aparecer todo mundo da lista... você tá mostrando as
	-- costas de um e o rosto do mesmo cara; mostre o rosto de todo mundo, dos dois
	-- lados". Antes a fila era montada com os PERSONAGENS DE VERDADE — só o seu
	-- obedece (o dos outros é do computador de cada um e volta pro lugar): gente
	-- de costas, faltando ou repetida. Agora são os BONECOS da cutscene, que são
	-- 100% daqui: todo mundo aparece, virado pra câmera, e ela passa de lado na
	-- frente dos rostos, um time e depois o outro.
	local planos = nil -- { { de, para, dur }, ... } um por time
	local function montarApresentacao()
		local golAzul = Workspace:FindFirstChild(Config.BLUE_GOAL_NAME, true)
		local golAmarelo = Workspace:FindFirstChild(Config.YELLOW_GOAL_NAME, true)
		if not golAzul or not golAmarelo then return nil end
		local centro = (golAzul.Position + golAmarelo.Position) / 2
		local eixo = golAmarelo.Position - golAzul.Position
		eixo = Vector3.new(eixo.X, 0, eixo.Z)
		if eixo.Magnitude < 1 then return nil end
		eixo = eixo.Unit
		local ladoFila = Vector3.new(-eixo.Z, 0, eixo.X)
		local raio = Config.CUTSCENE_FACEOFF_RADIUS
		local passo = Config.CUTSCENE_FACEOFF_SPACING
		local dist = Config.ENTRADA_ROSTO_DISTANCIA or 7.5
		local lista = {}
		for indice, teamName in ipairs(times) do
			local sentido = (indice == 1) and -1 or 1
			local origem = centro + eixo * (raio * sentido)
			local olhar = eixo * -sentido -- pra dentro, pro outro time
			local doTime = {}
			for _, d in ipairs(dummies) do
				if d.time == teamName and d.model.Parent then table.insert(doTime, d) end
			end
			local total = #doTime
			if total == 0 then continue end
			local rosto = nil
			for i, d in ipairs(doTime) do
				local desl = (i - 1 - (total - 1) / 2) * passo
				local pos = origem + ladoFila * desl
				pos = Vector3.new(pos.X, d.inicio.Y, pos.Z)
				d.model:PivotTo(CFrame.lookAt(pos, pos + olhar))
				rosto = rosto or alturaDoRosto(d.model, pos.Y)
			end
			-- a câmera passa de lado, de uma ponta da fila à outra, na altura do rosto
			local meia = math.max((total - 1) / 2 * passo, 1.5)
			local function quadro(desl)
				local alvo = Vector3.new(origem.X, rosto + 0.5, origem.Z) + ladoFila * desl
				local pos = alvo + olhar * dist + Vector3.new(0, 0.2, 0)
				return CFrame.lookAt(pos, alvo)
			end
			table.insert(lista, { de = quadro(-meia - 1), para = quadro(meia + 1), dur = Config.EntradaTempoDoTime(total) })
		end
		return lista
	end

	local function terminar()
		for _, d in ipairs(dummies) do
			if _G.AnimadorRemover then _G.AnimadorRemover(d.model) end
			if d.model.Parent then d.model:Destroy() end
		end
		restoreHiddenOriginals()
		-- cada um volta pra posição de saída (a fila do círculo era só pra câmera)
		for _, list in pairs(roster) do
			for _, entrada in ipairs(list) do
				local plr = Players:GetPlayerByUserId(entrada.UserId)
				if plr and plr.Character and entrada.FieldCFrame then
					plr.Character:PivotTo(entrada.FieldCFrame)
				end
			end
		end
		travarJogador(false)
		camera.FieldOfView = fovOriginal
		camera.CameraType = Enum.CameraType.Custom
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then camera.CameraSubject = humanoid end
		cutscenePlaying = false
	end

	local inicioT = os.clock()
	local fase2Desde = nil
	local connection
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - inicioT
		-- depuração: atributo EntradaDebugT no jogador congela a cutscene nesse instante
		local congelado = player:GetAttribute("EntradaDebugT")
		if typeof(congelado) == "number" then t = congelado end

		if t < T1 then
			-- ===== FASE 1: as filas andam reto; a câmera recua na frente delas =====
			local andou = velocidade * t
			for _, d in ipairs(dummies) do
				if d.model.Parent then
					local pos = d.inicio + frente * andou
					d.model:PivotTo(CFrame.lookAt(pos, pos + frente))
				end
			end
			local frenteDasFilas = bocaDoTunel - frente * antes + frente * andou
			local camPos = frenteDasFilas + frente * (Config.ENTRADA_CAMERA_FRENTE or 13)
				+ Vector3.new(0, Config.ENTRADA_CAMERA_ALTURA or 4.5, 0) + lado * 1.5
			local alvo = frenteDasFilas - frente * 5 + Vector3.new(0, 1.2, 0)
			camera.CFrame = CFrame.lookAt(camPos, alvo)
			return
		end

		-- ===== FASE 2 =====
		if not fase2Desde then
			fase2Desde = os.clock()
			planos = montarApresentacao()
			if planos then camera.FieldOfView = Config.ENTRADA_ROSTO_FOV or 40 end
		end
		local f = t - T1
		local duracaoFase2 = 0.5
		if planos and #planos > 0 then
			duracaoFase2 = 0
			for _, pl in ipairs(planos) do duracaoFase2 += pl.dur end
			-- qual plano (time) está no ar agora, e quanto dele já passou
			local acumulado, atual, u = 0, planos[#planos], 1
			for _, pl in ipairs(planos) do
				if f < acumulado + pl.dur then
					atual, u = pl, (f - acumulado) / pl.dur
					break
				end
				acumulado += pl.dur
			end
			u = math.clamp(u, 0, 1)
			u = u * u * (3 - 2 * u)
			camera.CFrame = atual.de:Lerp(atual.para, u)
		end
		if f >= duracaoFase2 or t > T1 + duracaoFase2 + 4 then
			connection:Disconnect()
			terminar()
		end
	end)
end

Remotes.PlayEntranceCutscene.OnClientEvent:Connect(playEntranceCutscene)

print("✅ EntranceCutsceneClient carregado.")
