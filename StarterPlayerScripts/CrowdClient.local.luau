--[[
	CrowdClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Game)

	PEDIDO ORIGINAL: "quero fazer uma arquibancada pra colocar os friends
	do Roblox de cada cliente nele, como aparência... não tem uma forma
	automática e menos lagada de fazer isso [em vez de cadeira por
	cadeira, rig por rig, na mão]?"

	PEDIDO v2: "eu quero humanoid, vamos fazer o teste com os personagens
	de verdade, porque eu quero colocar animações neles, que inclusive já
	está pronta, é uma animação específica pra gol (eles comemorando)."
	— trocou os cutouts achatados por clones de um Model/Humanoid de
	verdade, pra dar pra tocar a animação de comemoração (Config.
	ANIMATIONS.GoalCelebration, a MESMA usada no jogador que marca o gol
	— ver MatchController.legacy.luau) na torcida inteira quando sai um
	gol.

	Ver o comentário completo em FootballConfig.luau
	(Config.CROWD_AREA_NAME_PREFIX e vizinhos) — resumo:
	  1) Você coloca UMA Part por seção de arquibancada no Studio
	     (anchored, nome começando com Config.CROWD_AREA_NAME_PREFIX,
	     LookVector apontando pro campo) — esse script preenche o grid
	     inteiro sozinho.
	  2) Você coloca (uma vez só) um Model com Humanoid chamado
	     Config.CROWD_DUMMY_TEMPLATE_NAME em algum lugar (workspace ou
	     ReplicatedStorage) — é ele que é clonado pra cada assento.
	  3) 100% CLIENTE: cada jogador busca os PRÓPRIOS amigos do Roblox e
	     monta a arquibancada só na tela dele — ninguém mais vê os mesmos
	     rostos que você vê.
	  4) Quando sai um gol (Remotes.GoalScored), a torcida INTEIRA toca a
	     animação de comemoração por Config.GOAL_MUSIC_DURATION segundos
	     (a duração do grito da torcida, MusicClient.local.luau) — depois
	     disso ela para de comemorar sozinha, mesmo que ainda esteja no
	     meio do replay. Isso é intencional (pedido do usuário): a torcida
	     não comemora pra sempre.

	SEM o Model-template (Config.CROWD_DUMMY_TEMPLATE_NAME), a
	arquibancada simplesmente não aparece — avisa uma vez no console, sem
	travar nada. SEM nenhuma Part "CrowdArea_...", idem.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = workspace

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes
local player = Players.LocalPlayer

local PREFIX = Config.CROWD_AREA_NAME_PREFIX

-- ===== Pasta local pra guardar tudo que a gente criar =====
local crowdFolder = Instance.new("Folder")
crowdFolder.Name = "LocalCrowd"
crowdFolder.Parent = Workspace

-- ===== Acha o Model-template (workspace OU ReplicatedStorage) =====
local function findDummyTemplate()
	local inWorkspace = Workspace:FindFirstChild(Config.CROWD_DUMMY_TEMPLATE_NAME, true)
	if inWorkspace and inWorkspace:IsA("Model") and inWorkspace:FindFirstChildOfClass("Humanoid") then
		return inWorkspace
	end
	local inReplicated = ReplicatedStorage:FindFirstChild(Config.CROWD_DUMMY_TEMPLATE_NAME, true)
	if inReplicated and inReplicated:IsA("Model") and inReplicated:FindFirstChildOfClass("Humanoid") then
		return inReplicated
	end
	return nil
end

-- ===== Fila de fotos (thumbnails) com no máximo N "em voo" ao mesmo tempo =====
local thumbnailQueue = {}
local inFlight = 0
local thumbnailCache = {} -- [userId] = content (cache pra não rebuscar entre seções/partidas)

local function pumpThumbnailQueue()
	while inFlight < Config.CROWD_THUMBNAILS_IN_FLIGHT and #thumbnailQueue > 0 do
		local job = table.remove(thumbnailQueue, 1)
		inFlight += 1
		task.spawn(function()
			local content = thumbnailCache[job.userId]
			if not content then
				local ok, result = pcall(function()
					return Players:GetUserThumbnailAsync(job.userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
				end)
				if ok then
					content = result
					thumbnailCache[job.userId] = content
				end
			end
			if content then
				job.onReady(content)
			end
			inFlight -= 1
			pumpThumbnailQueue()
		end)
	end
end

local function requestThumbnail(userId, onReady)
	table.insert(thumbnailQueue, { userId = userId, onReady = onReady })
	pumpThumbnailQueue()
end

-- ===== Busca a lista de amigos do jogador local (uma vez, com cache) =====
local cachedFriendIds = nil
-- ⚠️ v84 — CAUSA PRINCIPAL da "plateia branca" (visto no Output de um
-- playtest: só a 1ª área recebia os 60 amigos, TODAS as outras recebiam 0).
-- As áreas são montadas em paralelo (task.spawn por área); a primeira a
-- chegar aqui marcava cachedFriendIds = {} e ficava esperando a resposta do
-- GetFriendsAsync — e as outras, vendo o cache "existindo", devolviam essa
-- lista AINDA VAZIA na hora. Área com 0 amigos = todo torcedor dela branco.
-- Agora quem chega durante a busca ESPERA ela terminar.
local buscandoAmigos = false

local function buscarAmigosAgora()
	local ids = {}

	local ok, pages = pcall(function()
		return Players:GetFriendsAsync(player.UserId)
	end)
	if not ok or not pages then
		return ids -- conta pode não ter permissão/amigos — segue só com fallback
	end

	local guard = 0
	while true do
		guard += 1
		if guard > 20 then break end -- segurança: nunca passa de ~20 páginas mesmo se algo entrar em loop

		local okPage, items = pcall(function()
			return pages:GetCurrentPage()
		end)
		if not okPage or not items then break end

		for _, friendInfo in ipairs(items) do
			if #ids >= Config.CROWD_MAX_FRIENDS_TO_FETCH then
				return ids
			end
			table.insert(ids, friendInfo.Id)
		end

		if pages.IsFinished then break end
		local okNext = pcall(function()
			pages:AdvanceToNextPageAsync()
		end)
		if not okNext then break end
	end

	return ids
end

local function fetchFriendIds()
	while buscandoAmigos do
		task.wait(0.1)
	end
	if cachedFriendIds then return cachedFriendIds end

	buscandoAmigos = true
	local ok, lista = pcall(buscarAmigosAgora)
	cachedFriendIds = (ok and lista) or {}
	buscandoAmigos = false
	return cachedFriendIds
end

-- ===== Lista de todos os torcedores criados (pra tocar a comemoração) =====
local allCrowdHumanoids = {} -- lista de Humanoid

-- ⚠️ v13 — PEDIDO: "os personagens da torcida estão com o MEU cabelo, do
-- meu personagem do Roblox, e algumas roupas e acessórios meus. Tira isso,
-- pra poder colocar a roupa dos personagens originais."
--
-- CAUSA: o Model-template (Config.CROWD_DUMMY_TEMPLATE_NAME) foi montado a
-- partir de um personagem real — então ele carrega cabelo, roupa e
-- acessórios daquela conta, e cada torcedor é um clone dele. O template é
-- um asset do Studio, o código não tem como "consertar" o arquivo; o que
-- ele pode fazer, e faz agora, é limpar a identidade de avatar de CADA
-- clone na hora de criar.
--
-- O que sai: Accessory (cabelo, chapéu, óculos, qualquer acessório),
-- Shirt/Pants/ShirtGraphic (roupas) e CharacterMesh (troca de corpo por
-- pacote). O que FICA: o rig, as cores do corpo e o rosto do template —
-- ou seja, o torcedor continua sendo o boneco que você desenhou, só que
-- sem as suas roupas.
--
-- Isso NÃO atrapalha a aparência dos amigos: applyFriendAppearance roda
-- depois e o ApplyDescription recoloca cabelo/roupa/acessórios do amigo
-- por cima (ver mais abaixo).
local function stripAvatarIdentity(clone)
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("Accessory")
			or desc:IsA("Shirt")
			or desc:IsA("Pants")
			or desc:IsA("ShirtGraphic")
			or desc:IsA("CharacterMesh") then
			desc:Destroy()
		end
	end

	-- Uniforme da torcida, se você quiser um: preencha Config.CROWD_SHIRT_ID
	-- / Config.CROWD_PANTS_ID com os ids das roupas que os torcedores devem
	-- vestir. Vazio (padrão) = corpo limpo do template, sem roupa nenhuma
	-- por cima.
	if Config.CROWD_SHIRT_ID and Config.CROWD_SHIRT_ID ~= "" then
		local shirt = Instance.new("Shirt")
		shirt.ShirtTemplate = Config.CROWD_SHIRT_ID
		shirt.Parent = clone
	end
	if Config.CROWD_PANTS_ID and Config.CROWD_PANTS_ID ~= "" then
		local pants = Instance.new("Pants")
		pants.PantsTemplate = Config.CROWD_PANTS_ID
		pants.Parent = clone
	end
end

-- ===== Constrói um único "torcedor" (clone do template, achatado em
-- performance: tudo anchored/sem colisão/sem sombra) =====
local function createCrowdDummy(template, cframe)
	local clone = template:Clone()
	stripAvatarIdentity(clone)

	-- ⚠️ v17 FIX — PEDIDO: "fiz animação de comemoração de torcida, só que
	-- elas não estão tocando, apesar de estar configurado".
	--
	-- CAUSA: aqui TODA BasePart do torcedor virava Anchored. Um rig com as
	-- partes anchored NÃO ANIMA — animação do Roblox move os membros pelos
	-- Motor6D, e parte anchored simplesmente ignora o Motor6D. Ou seja: a
	-- animação carregava, o track dava Play, os prints diziam "tocando em
	-- N torcedores"... e ninguém mexia um dedo. Por isso parecia problema
	-- de configuração quando o id estava certo o tempo todo.
	--
	-- CORREÇÃO: anchora SÓ o HumanoidRootPart. Ele segura o boneco parado
	-- no lugar (que era o objetivo do anchor), e os membros ficam livres
	-- pros Motor6D/animação mexerem. Continuam sem colisão/sem sombra/sem
	-- query, então o custo de performance segue o mesmo.
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = (desc == rootPart)
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.CastShadow = false
		end
	end

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.NameDisplayDistance = 0
		humanoid.HealthDisplayDistance = 0
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		table.insert(allCrowdHumanoids, humanoid)
	end

	clone.Name = "CrowdDummy"
	clone:PivotTo(cframe)
	clone.Parent = crowdFolder
	return clone
end

-- ⚠️ ANTIGO (mantido só como FALLBACK, ver applyFriendAppearance abaixo):
-- colava a FOTO (thumbnail 2D, achatada) do amigo como Decal na cara do
-- boneco — PEDIDO: "os personagens dos meus amigos estão funcionando, mas
-- são só o rosto e esse rosto está todo bugado, o restante do corpo
-- precisa mudar também". Uma foto 2D esticada numa cabeça 3D (Front de
-- uma Part com várias faces, ângulos diferentes por rig) SEMPRE vai
-- distorcer/"bugar" um pouco — e nunca mexia no corpo. Ver
-- applyFriendAppearance, que agora troca a APARÊNCIA REAL (rosto de
-- verdade + roupas + cor de pele + acessórios) via ApplyDescription.
local function applyFaceDecalFallback(clone, content)
	local head = clone:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then return end

	for _, existing in ipairs(head:GetChildren()) do
		if (existing:IsA("Decal") or existing:IsA("Texture")) and existing.Face == Enum.NormalId.Front then
			existing:Destroy()
		end
	end

	local decal = Instance.new("Decal")
	decal.Name = "Face"
	decal.Texture = content
	decal.Face = Enum.NormalId.Front
	decal.Parent = head
end

-- ⚠️ NOVO: PEDIDO — "os personagens dos meus amigos estão funcionando, mas
-- são só o rosto e esse rosto está todo bugado, o restante do corpo
-- precisa mudar também". Em vez de só colar uma foto achatada na cara,
-- busca a APARÊNCIA REAL do amigo (Players:GetHumanoidDescriptionFromUserId)
-- e aplica ela inteira no Humanoid do clone (humanoid:ApplyDescription) —
-- isso troca rosto, roupas, cor de pele, cabelo e acessórios de uma vez,
-- exatamente como o avatar de verdade do amigo. Reaplica as flags de
-- performance (Anchored/sem colisão/sem sombra) nas partes NOVAS que
-- ApplyDescription recria, porque ela substitui o rig/roupas do template
-- e as flags que createCrowdDummy já tinha aplicado se perdem nessas
-- partes trocadas.
local function reapplyPerformanceFlags(clone)
	-- ⚠️ v17: mesma regra do createCrowdDummy — só o HumanoidRootPart fica
	-- anchored, senão a comemoração não anima (ver o comentário lá).
	-- Acessório NUNCA pode ser anchored: ele é preso na cabeça por um Weld,
	-- e anchorar o Handle faz o chapéu/cabelo ficar parado no ar enquanto o
	-- corpo se mexe.
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	for _, desc in ipairs(clone:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Anchored = (desc == rootPart)
			desc.CanCollide = false
			desc.CanQuery = false
			desc.CanTouch = false
			desc.CastShadow = false
		elseif desc:IsA("Accessory") then
			local handle = desc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.Anchored = false
				handle.CanCollide = false
				handle.CanQuery = false
				handle.CanTouch = false
				handle.CastShadow = false
			end
		end
	end
end

-- ⚠️ v84 — PEDIDO: "ajuste a plateia, onde alguns personagens não vêm como
-- amigos meus, aparecem só personagens em branco".
--
-- CAUSA: cada ASSENTO disparava a própria GetHumanoidDescriptionFromUserId,
-- todas ao mesmo tempo (task.spawn por torcedor, sem limite) — com centenas
-- de torcedores, o serviço de avatar do Roblox recusava boa parte por excesso
-- de pedidos. Sem nova tentativa, o torcedor que falhava ficava com o corpo
-- LIMPO do template (a roupa é tirada em stripAvatarIdentity), ou seja,
-- branco — e no máximo ganhava a foto na cara.
--
-- AGORA:
--   1) a aparência é buscada UMA vez por amigo (cache) — os assentos que
--      repetem o mesmo amigo reaproveitam;
--   2) no máximo APPEARANCE_WORKERS torcedores são vestidos ao mesmo tempo
--      (fila), em vez de centenas de pedidos simultâneos;
--   3) falhou? tenta de novo (com espera crescente);
--   4) se um amigo específico falhar de vez, o torcedor veste a aparência de
--      OUTRO amigo que deu certo — nunca fica branco se pelo menos um
--      amigo carregou.
local APPEARANCE_WORKERS = 4
local DESCRIPTION_ATTEMPTS = 3

local descricaoPorAmigo = {} -- [friendId] = HumanoidDescription | false (falhou todas as tentativas)
local buscandoDescricao = {} -- [friendId] = true enquanto uma busca está em andamento
local descricoesBoas = {}    -- descrições que carregaram (reserva pra quem falhar)

local function obterDescricao(friendId)
	while buscandoDescricao[friendId] do
		task.wait(0.1)
	end
	local emCache = descricaoPorAmigo[friendId]
	if emCache ~= nil then
		return emCache or nil
	end

	buscandoDescricao[friendId] = true
	local descricao
	for tentativa = 1, DESCRIPTION_ATTEMPTS do
		local ok, resultado = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(friendId)
		end)
		if ok and resultado then
			descricao = resultado
			break
		end
		if tentativa < DESCRIPTION_ATTEMPTS then
			task.wait(1.5 * tentativa)
		end
	end
	descricaoPorAmigo[friendId] = descricao or false
	if descricao then
		table.insert(descricoesBoas, descricao)
	end
	buscandoDescricao[friendId] = nil
	return descricao
end

local function applyFriendAppearance(clone, friendId)
	if not clone.Parent then return end
	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local descricao = obterDescricao(friendId)
	if not descricao and #descricoesBoas > 0 then
		descricao = descricoesBoas[math.random(1, #descricoesBoas)]
	end

	if descricao then
		for tentativa = 1, 2 do
			if not clone.Parent then return end
			-- Clone: a mesma descrição é aplicada em vários torcedores.
			local okApply = pcall(function()
				humanoid:ApplyDescription(descricao:Clone())
			end)
			if okApply then
				reapplyPerformanceFlags(clone)
				return
			end
			task.wait(1)
		end
	end

	-- Nenhuma aparência carregou (nem de outro amigo) — cai pro método
	-- antigo (só a foto na cara) em vez de deixar sem nada.
	requestThumbnail(friendId, function(content)
		applyFaceDecalFallback(clone, content)
	end)
end

local filaAparencia = {}
local vestindoAgora = 0

local function bombearFilaAparencia()
	while vestindoAgora < APPEARANCE_WORKERS and #filaAparencia > 0 do
		local trabalho = table.remove(filaAparencia, 1)
		vestindoAgora += 1
		task.spawn(function()
			local ok, erro = pcall(applyFriendAppearance, trabalho.clone, trabalho.friendId)
			if not ok then
				warn("🏟️ [Crowd] falha ao vestir um torcedor: " .. tostring(erro))
			end
			vestindoAgora -= 1
			bombearFilaAparencia()
		end)
	end
end

local function enfileirarAparencia(clone, friendId)
	table.insert(filaAparencia, { clone = clone, friendId = friendId })
	bombearFilaAparencia()
end

-- ===== ARQUIBANCADA (degrau simples atrás/embaixo de cada fileira) =====
-- PEDIDO: "faça uma arquibancada simples gerar atrás deles, de forma que
-- seja como se eles estivessem em pé". Um bloco POR FILEIRA (não por
-- assento — muito mais barato), subindo em escada do "chão" (estimado
-- como a base da própria Part CrowdArea_...) até a altura daquela
-- fileira, criando o perfil de degraus de um estádio de verdade.
local function createBleacherStep(areaPart, row, rightVector, backVector)
	if not Config.CROWD_BLEACHER_ENABLED then return end

	local groundY = areaPart.Position.Y - (areaPart.Size.Y / 2)
	local stepTopY = groundY + Config.CROWD_ROW_RISE * (row + 1) + (Config.CROWD_ROW_RISE * 0.35)
	local stepHeight = math.max(stepTopY - groundY, 0.5)
	local stepCenterYOffset = (groundY + stepHeight / 2) - areaPart.Position.Y

	local localOffset = backVector * (Config.CROWD_ROW_DEPTH * row + Config.CROWD_ROW_DEPTH / 2)
		+ Vector3.new(0, stepCenterYOffset, 0)

	local step = Instance.new("Part")
	step.Name = "CrowdBleacherStep"
	step.Anchored = true
	step.CanCollide = false
	step.CanQuery = false
	step.CanTouch = false
	step.CastShadow = false
	step.Material = Config.CROWD_BLEACHER_MATERIAL or Enum.Material.Concrete
	step.Color = Config.CROWD_BLEACHER_COLOR or Color3.fromRGB(120, 120, 130)
	step.Size = Vector3.new(areaPart.Size.X, stepHeight, Config.CROWD_ROW_DEPTH)
	step.CFrame = areaPart.CFrame + localOffset
	step.Parent = crowdFolder
end

-- ===== Preenche uma seção (uma Part "CrowdArea_...") com o grid inteiro =====
-- ⚠️ NOVO: prints de debug em CADA etapa (pedido do usuário: "não entendi
-- muito bem como funciona o crowd... coloque alguns prints pra eu
-- entender exatamente o que precisa ser feito"). Todos aparecem no
-- Output do cliente (F9 no Studio, ou o console do Play Solo).
local warnedNoTemplate = false

local function populateArea(areaPart)
	print(("🏟️ [Crowd] Encontrei a Part de área '%s' (Size=%s, Position=%s)."):format(
		areaPart.Name, tostring(areaPart.Size), tostring(areaPart.Position)))

	if areaPart:GetAttribute("CrowdPopulated") then
		print(("🏟️ [Crowd] '%s' já estava marcada como preenchida (CrowdPopulated=true) — pulando. Se você mudou o tamanho dela DEPOIS de já ter rodado uma vez nessa mesma sessão de Play, pare e dê Play de novo (esse atributo só reseta com uma nova sessão)."):format(areaPart.Name))
		return
	end

	local template = findDummyTemplate()
	if not template then
		if not warnedNoTemplate then
			warnedNoTemplate = true
			warn(("🏟️ [Crowd] ❌ NENHUM Model '%s' com Humanoid encontrado (procurei em TODO workspace e TODO ReplicatedStorage) — arquibancada não vai aparecer até esse template existir. Confira: (1) o NOME está EXATAMENTE '%s' (maiúsculas/minúsculas importam)? (2) é um Model (não uma pasta/Part solta)? (3) tem um Humanoid DIRETO dentro dele (não aninhado mais fundo)?"):format(
				Config.CROWD_DUMMY_TEMPLATE_NAME, Config.CROWD_DUMMY_TEMPLATE_NAME))
		end
		return
	end
	print(("🏟️ [Crowd] ✅ Template '%s' encontrado em '%s'."):format(template.Name, template.Parent and template.Parent:GetFullName() or "?"))
	areaPart:SetAttribute("CrowdPopulated", true)

	local rightVector = areaPart.CFrame.RightVector
	local backVector = -areaPart.CFrame.LookVector -- "pra trás/pra cima", se afastando do campo
	local faceDirection = areaPart.CFrame.LookVector -- torcedor sempre olhando pro campo

	local columns = math.max(1, math.floor(areaPart.Size.X / Config.CROWD_SEAT_WIDTH))
	local rows = math.max(1, math.floor(areaPart.Size.Z / Config.CROWD_ROW_DEPTH))

	local totalSeats = columns * rows
	if not Config.CROWD_FILL_ENTIRE_AREA and totalSeats > Config.CROWD_MAX_SEATS_PER_AREA then
		-- Area gigante demais — reduz proporcionalmente em vez de travar
		-- clonando um rig inteiro centenas de vezes de uma vez só.
		local scale = math.sqrt(Config.CROWD_MAX_SEATS_PER_AREA / totalSeats)
		columns = math.max(1, math.floor(columns * scale))
		rows = math.max(1, math.floor(rows * scale))
		print(("🏟️ [Crowd] '%s' pediria %d assentos (%dx%d) — reduzido pro teto de %d (Config.CROWD_MAX_SEATS_PER_AREA): %dx%d."):format(
			areaPart.Name, totalSeats, columns, rows, Config.CROWD_MAX_SEATS_PER_AREA, columns, rows))
	elseif Config.CROWD_FILL_ENTIRE_AREA then
		print(("🏟️ [Crowd] '%s': Config.CROWD_FILL_ENTIRE_AREA=true — preenchendo a área INTEIRA (%d assentos), ignorando o teto de %d. Se travar, volte esse Config pra false."):format(
			areaPart.Name, totalSeats, Config.CROWD_MAX_SEATS_PER_AREA))
	end

	print(("🏟️ [Crowd] '%s': vou gerar %d colunas x %d linhas = %d torcedores. Size.X=%.1f (÷%.1f=colunas), Size.Z=%.1f (÷%.1f=linhas)."):format(
		areaPart.Name, columns, rows, columns * rows, areaPart.Size.X, Config.CROWD_SEAT_WIDTH, areaPart.Size.Z, Config.CROWD_ROW_DEPTH))
	-- ⚠️ NOVO: PEDIDO — "a crowd ainda não pula" — print pra confirmar de
	-- vez qual valor está sendo usado de verdade nesse teste (se aparecer
	-- diferente de 0.5 aqui, o FootballConfig.luau sincronizado no Studio
	-- não é o mais recente — reabra/confirme o arquivo).
	print(("🏟️ [Crowd] Config.CROWD_EMPTY_SEAT_CHANCE = %s (chance de CADA assento ficar vazio)."):format(tostring(Config.CROWD_EMPTY_SEAT_CHANCE)))

	local friendIds = fetchFriendIds()
	print(("🏟️ [Crowd] Amigos encontrados pra usar como foto: %d (se for 0, a arquibancada ainda aparece com o rosto/aparência PADRÃO do template — só não ganha nenhuma foto colada em cima). Se você está testando dentro do STUDIO (Play/Play Solo) e isso sempre dá 0, veja Game Settings > Security > 'Enable Studio Access to API Services' — sem isso ligado, GetFriendsAsync e as fotos (thumbnails) sempre falham silenciosamente no Studio, mesmo com o código certo. No servidor real (jogo publicado) isso não é necessário."):format(#friendIds))
	local friendCursor = 0
	local skippedSeats = 0

	-- ⚠️ v30 — PEDIDO: "faz os NPCs irem um pouco mais pra trás, estão pra
	-- frente demais do banco."
	-- A fileira 0 nascia exatamente no plano central da Part de área, e o
	-- banco (geometria permanente, ver workspace.Arquibancadas) fica mais
	-- atrás dentro da mesma fileira. Resultado: todo mundo em pé na frente
	-- do próprio banco. Esse recuo empurra o torcedor pra cima do assento.
	local basePosition = areaPart.Position
		- rightVector * (areaPart.Size.X / 2)
		+ rightVector * (Config.CROWD_SEAT_WIDTH / 2)
		+ backVector * (Config.CROWD_SEAT_BACK_OFFSET or 0)

	for row = 0, rows - 1 do
		local rowOrigin = basePosition
			+ backVector * (Config.CROWD_ROW_DEPTH * row)
			+ Vector3.new(0, Config.CROWD_ROW_RISE * row, 0)

		createBleacherStep(areaPart, row, rightVector, backVector)

		for col = 0, columns - 1 do
			-- PEDIDO: "não põe toda, deixa algumas lacunas, como se
			-- algumas pessoas não tivessem ido" — pula esse assento (sem
			-- criar nada) com chance Config.CROWD_EMPTY_SEAT_CHANCE.
			if math.random() < (Config.CROWD_EMPTY_SEAT_CHANCE or 0) then
				skippedSeats += 1
				continue
			end

			local seatPosition = rowOrigin + rightVector * (Config.CROWD_SEAT_WIDTH * col)
			local seatCFrame = CFrame.lookAt(seatPosition, seatPosition + faceDirection)
			local clone = createCrowdDummy(template, seatCFrame)

			-- Distribui os amigos ciclicamente (se sobrar assento, repete os
			-- mesmos amigos em vez de deixar sem rosto à toa).
			if #friendIds > 0 then
				friendCursor += 1
				local friendId = friendIds[((friendCursor - 1) % #friendIds) + 1]
				enfileirarAparencia(clone, friendId) -- ⚠️ v84: fila com limite (ver applyFriendAppearance)
			end
		end
	end

	print(("🏟️ [Crowd] ✅ '%s' pronta: %d torcedores criados, %d lacunas (assentos vazios) em LocalCrowd (workspace)."):format(areaPart.Name, (columns * rows) - skippedSeats, skippedSeats))
end

-- ===== Descoberta das Parts de área (mesmo padrão auto-corretivo usado
-- em GKAreaUtil/EntranceCutsceneClient pra Parts que podem streamar
-- depois) =====
local scannedAnyArea = false

local function tryPopulate(inst)
	if inst:IsA("BasePart") and inst.Name:sub(1, #PREFIX) == PREFIX then
		scannedAnyArea = true
		if not inst.Anchored then
			inst.Anchored = true
		end
		task.spawn(populateArea, inst)
	end
end

for _, inst in ipairs(Workspace:GetDescendants()) do
	tryPopulate(inst)
end
Workspace.DescendantAdded:Connect(tryPopulate)

task.delay(3, function()
	if not scannedAnyArea then
		warn(("🏟️ [Crowd] ❌ Nenhuma Part com nome começando em '%s' foi encontrada em workspace até agora (esperei 3s pro mundo carregar). Confira se a Part se chama exatamente '%s_NomeQualquer' (ex.: 'CrowdArea_Norte') e está em algum lugar dentro de workspace."):format(PREFIX, PREFIX))
	end
end)

-- ===== Comemoração de gol na torcida inteira (mesma animação do
-- jogador que marcou, Config.ANIMATIONS.GoalCelebration) — dura
-- Config.GOAL_MUSIC_DURATION segundos (o grito da torcida, ver
-- MusicClient.local.luau) e PARA sozinha depois disso, mesmo que ainda
-- esteja no meio do replay — pedido do usuário: "a torcida não comemora
-- pra sempre". =====
local celebrationTracks = {}

-- ⚠️ NOVO: PEDIDO — "o audio está tocando duas vezes... isso não pode
-- acontecer" — mesma trava de cooldown usada em MusicClient.local.luau,
-- pra garantir que mesmo se Remotes.GoalScored chegar duplicado, a
-- torcida não empilha um SEGUNDO conjunto de animações por cima do
-- primeiro (o que, se a animação tiver som/vocalização embutido, tocaria
-- o "grito" duas vezes ao mesmo tempo).
local lastCelebrationAt = -math.huge

local function playCrowdCelebration()
	-- PEDIDO: "a comemoração da torcida são esses dois: 71075180222011,
	-- 109633359624709... intercala eles no código, pra ser aleatório
	-- quem usa qual" — cada torcedor sorteia UM dos dois, não todos usam
	-- o mesmo (ver Config.ANIMATIONS.GoalCelebrationCrowd).
	local pool = Config.ANIMATIONS.GoalCelebrationCrowd
	if type(pool) ~= "table" or #pool == 0 then
		print("🏟️ [Crowd] Comemoração pulada: Config.ANIMATIONS.GoalCelebrationCrowd está vazia/inválida.")
		return
	end

	local durationSeconds = Config.GOAL_MUSIC_DURATION or 8
	local now = os.clock()
	if now - lastCelebrationAt < durationSeconds then
		warn(("🏟️ [Crowd] Gol chegou de novo %.1fs depois do último (dentro da janela de %.1fs) — IGNORADO pra não empilhar animação em cima da que já está tocando."):format(now - lastCelebrationAt, durationSeconds))
		return
	end
	lastCelebrationAt = now

	print(("🏟️ [Crowd] Gol! Tentando tocar comemoração em %d torcedor(es)."):format(#allCrowdHumanoids))
	if #allCrowdHumanoids == 0 then
		warn("🏟️ [Crowd] ❌ Nenhum torcedor na lista (allCrowdHumanoids vazia) — a arquibancada não populou nenhum Humanoid ainda? Confira os prints de populateArea acima.")
	end

	local played = 0
	for _, humanoid in ipairs(allCrowdHumanoids) do
		if humanoid.Parent then
			local animationId = Config.NormalizeAnimationId(pool[math.random(1, #pool)])
			if animationId and animationId ~= "" then
				-- Usa o Animator diretamente (Humanoid:LoadAnimation está
				-- deprecated e em alguns rigs sem Animator ainda não
				-- carrega direito) — cria o Animator se ainda não existir.
				local animator = humanoid:FindFirstChildOfClass("Animator")
				if not animator then
					animator = Instance.new("Animator")
					animator.Parent = humanoid
				end

				local animation = Instance.new("Animation")
				animation.AnimationId = animationId
				local ok, track = pcall(function()
					return animator:LoadAnimation(animation)
				end)
				if ok and track then
					track.Looped = true
					track:Play()
					table.insert(celebrationTracks, track)
					played += 1
				else
					warn(("🏟️ [Crowd] ❌ Falha ao carregar a animação %s num torcedor: %s"):format(tostring(animationId), tostring(track)))
				end
			end
		end
	end
	print(("🏟️ [Crowd] Comemoração tocando em %d/%d torcedor(es)."):format(played, #allCrowdHumanoids))

	task.delay(durationSeconds, function()
		for _, track in ipairs(celebrationTracks) do
			track:Stop(0.3)
		end
		celebrationTracks = {}
	end)
end

if Remotes and Remotes.GoalScored then
	Remotes.GoalScored.OnClientEvent:Connect(playCrowdCelebration)
end

print("✅ CrowdClient carregado.")
