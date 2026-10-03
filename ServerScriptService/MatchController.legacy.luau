local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local DataStoreService = game:GetService("DataStoreService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService") -- ⚠️ v49: usado pra medir a duração da música da prorrogação

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes
local Rewards = Config.REWARDS

local ball = workspace:WaitForChild(Config.BALL_NAME)
local ballSpawnPosition = ball.Position

_G.GetBallGroundY = function()
	return ballSpawnPosition.Y
end

-- ===== FORMAÇÃO POR POSIÇÃO (sem SpawnLocation nenhuma no Studio) =====
-- Cada jogador aparece (no primeiro spawn, ver PlayerSystems.legacy.luau
-- — Players.CharacterAutoLoads=false + _G.PositionPlayerAtFormation) e
-- VOLTA (depois de cada gol e no início de cada tempo, ver performKickoff
-- abaixo) pro lugar certo do campo de acordo com o Role (GK/DF/MF/FW) e o
-- Team dele — sem depender de nenhuma SpawnLocation na cena, só dos dois
-- gols que já existem (mesma técnica de eixo do campo do
-- OutOfBoundsController.lua: detecta sozinho se o eixo gol-a-gol é local
-- X ou Z, então funciona com o campo virado em qualquer direção).
local campoHit = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
local blueGoal = workspace:FindFirstChild(Config.BLUE_GOAL_NAME)
local yellowGoal = workspace:FindFirstChild(Config.YELLOW_GOAL_NAME)

-- Profundidade de cada posição, como FRAÇÃO da distância entre o próprio
-- gol (0) e o gol adversário (1) — GK quase em cima do próprio gol, FW
-- avançado perto do meio-campo adversário. Mexa só nesses números pra
-- ajustar a formação.
-- ⚠️ v40 FIX — PEDIDO: "os atacantes estão nascendo no campo do
-- adversário. Isso não pode acontecer. Os atacantes têm que nascer um
-- pouco antes do meio de campo deles."
--
-- FW estava em 0.68 — como 0.5 é o MEIO DE CAMPO, isso colocava o
-- atacante 18% DENTRO do campo adversário, o que nem é legal num
-- pontapé inicial de verdade.
--
-- Por que passou despercebido: quando as parts fixas de spawn existem
-- (Spawn_<Time>_<Vaga>, ver mais abaixo) elas têm PRIORIDADE e estas
-- frações nem são usadas — e as parts que você posicionou à mão no
-- Studio já estavam certas (medi: FW em 0.447, DF 0.198, MF 0.342, GK
-- 0.032, todas no campo próprio). Só que o jogo cai nestas frações
-- sempre que falta a part da vaga, e aí o atacante pulava pro campo
-- adversário. Isso acontece em dois casos reais:
--   - time de tamanho fora de 3/5/7 (teste 1v1/2v2, Sala Livre) — não
--     existe lista de vagas pra esses tamanhos;
--   - 7v7 SEM goleiro, que pede uma vaga "DF3" pra qual não existe part.
--
-- Agora estas frações são um ESPELHO das parts que você já posicionou,
-- então os dois caminhos dão praticamente o mesmo lugar e ninguém nasce
-- no campo adversário em nenhum formato de time.
local ROLE_DEPTH_FRACTION = {
	GK = 0.04, -- medido nas parts: 0.031 / 0.032
	DF = 0.20, -- medido nas parts: 0.198 / 0.200
	MF = 0.34, -- medido nas parts: 0.342 / 0.344
	FW = 0.45, -- medido nas parts: 0.446 / 0.449 — logo ANTES do meio (0.5)
}
local DEFAULT_DEPTH_FRACTION = 0.45

-- ===== SPAWN FIXO POR PART (pedido: parts no campo marcando cada vaga) =====
-- Padrão SEMPRE 7v7 (GK, DF1, DF2, MF1, MF2, FW1, FW2 — por time); 5v5 e
-- 3v3 reaproveitam um SUBCONJUNTO dessas mesmas parts (ver
-- Config.SPAWN_PART_PREFIX em FootballConfig.lua pro nome exato de cada
-- part que você precisa criar no Studio). A ordem de cada lista abaixo
-- bate POSICIONALMENTE com FIXED_FORMATION_TEMPLATES do mesmo tamanho —
-- ou seja, a vaga #3 do template 5v5 ("MF") corresponde à part
-- "..._MF1" abaixo, sempre nessa ordem.
-- ⚠️ v33 — PEDIDO: "a prioridade deles é começar no ATAQUE, começar na
-- frente. O jogador sempre vai iniciar na frente, se não tiver muitos
-- jogadores." As listas de vaga e de Spawn são ALINHADAS POR ÍNDICE, então
-- as duas mudaram juntas — mexer só numa colocaria o atacante no spawn do
-- zagueiro.
local SPAWN_SLOT_NAMES_BY_TEAM_SIZE_WITH_GK = {
	[7] = { "GK", "FW1", "FW2", "MF1", "MF2", "DF1", "DF2" },
	[5] = { "GK", "FW1", "FW2", "MF1", "DF1" },
	[3] = { "GK", "FW1", "MF1" },
}

-- ⚠️ NOVO: PEDIDO — "remova a prioridade por goleiro" — mesma lista, mas
-- pro template SEM GK (ver FIXED_FORMATION_TEMPLATES_NO_GK mais abaixo),
-- usado quando ninguém no time prefere jogar de goleiro. Bate
-- POSICIONALMENTE com esse template (1 defensor a mais no lugar da vaga
-- de GK). Se você usa parts fixas de spawn no Studio e quer que elas
-- continuem funcionando mesmo sem goleiro humano, crie também essas
-- (ex.: "..._Blue_DF3" pro 7v7 sem GK) — se não criar, esse tamanho de
-- time simplesmente cai pro cálculo por fração, sem quebrar nada.
local SPAWN_SLOT_NAMES_BY_TEAM_SIZE_NO_GK = {
	[7] = { "FW1", "FW2", "MF1", "MF2", "DF1", "DF2", "DF3" },
	[5] = { "FW1", "FW2", "MF1", "MF2", "DF1" },
	[3] = { "FW1", "MF1", "DF1" },
}

-- [teamName][slotName] = Part — varrido uma vez, no load do servidor.
local spawnParts = {}
for _, teamName in ipairs(Config.TEAM_NAMES) do
	spawnParts[teamName] = {}
end
do
	local prefix = Config.SPAWN_PART_PREFIX
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name:sub(1, #prefix) == prefix then
			local rest = inst.Name:sub(#prefix + 1) -- "<Time>_<Vaga>"
			for _, teamName in ipairs(Config.TEAM_NAMES) do
				local wantedPrefix = teamName .. "_"
				if rest:sub(1, #wantedPrefix) == wantedPrefix then
					spawnParts[teamName][rest:sub(#wantedPrefix + 1)] = inst
					break
				end
			end
		end
	end
end

-- true só se TODAS as parts desse tamanho de time existirem pros DOIS
-- times — parcial não conta (senão um time nasce em part fixa e o outro
-- ainda no cálculo antigo, ficando torto/inconsistente).
-- ⚠️ NOVO: com GK removido da prioridade, um mesmo teamSize pode rodar sob
-- o template COM GK (se alguém pediu GK) ou SEM GK (ninguém pediu) — então
-- a validação de parts fixas precisa aceitar QUALQUER uma das duas listas
-- de nomes de vaga pra aquele tamanho de time (não as duas ao mesmo tempo).
local function hasAllSpawnPartsForTeamSize(teamSize)
	local slotNamesWithGK = SPAWN_SLOT_NAMES_BY_TEAM_SIZE_WITH_GK[teamSize]
	local slotNamesNoGK = SPAWN_SLOT_NAMES_BY_TEAM_SIZE_NO_GK[teamSize]
	if not slotNamesWithGK and not slotNamesNoGK then return false end
	local function allPartsExist(slotNames)
		if not slotNames then return false end
		for _, teamName in ipairs(Config.TEAM_NAMES) do
			local parts = spawnParts[teamName]
			for _, slotName in ipairs(slotNames) do
				if not (parts and parts[slotName]) then return false end
			end
		end
		return true
	end
	return allPartsExist(slotNamesWithGK) or allPartsExist(slotNamesNoGK)
end

for teamSize in pairs(SPAWN_SLOT_NAMES_BY_TEAM_SIZE_WITH_GK) do
	if not hasAllSpawnPartsForTeamSize(teamSize) then
		warn(("⚠️ MatchController: faltam parts \"%s<Time>_<Vaga>\" pro formato %dv%d — esse tamanho de time continua usando o cálculo antigo (por fração do campo) até todas as parts existirem pros dois times. Ver Config.SPAWN_PART_PREFIX em FootballConfig.lua."):format(Config.SPAWN_PART_PREFIX, teamSize, teamSize))
	end
end

local formationReady = campoHit ~= nil and blueGoal ~= nil and yellowGoal ~= nil
local goalAxisIsX, fieldHalfSize, touchHalf
local function goalAxisValue(localPos)
	return goalAxisIsX and localPos.X or localPos.Z
end
local function touchAxisValue(localPos)
	return goalAxisIsX and localPos.Z or localPos.X
end
local function toLocalVector(goalCoord, touchCoord)
	if goalAxisIsX then
		return Vector3.new(goalCoord, 0, touchCoord)
	end
	return Vector3.new(touchCoord, 0, goalCoord)
end

-- ===== VAGAS FIXAS DA FORMAÇÃO (por time) =====
-- PEDIDO: a Role escolhida no slot (Studio/Loja, ver PlayerDataManager.
-- lua do Lobby) é PREFERENCIAL — o jogador nasce nela. Se sobrar mais de
-- um jogador do time querendo a MESMA posição, o jogo escolhe UM
-- aleatoriamente pra manter ali, e o(s) outro(s) vai(vão) pra próxima
-- vaga vazia seguindo uma ORDEM DE PRIORIDADE (ver OVERFLOW_ORDER
-- abaixo), não qualquer vaga vazia à toa.
--
-- Composição EXATA pedida:
--   3v3 (3 por time): 1 GK, 1 DF/MF (vaga única, aceita quem prefere
--                      zagueiro OU meia — não tem vaga de MF separada
--                      nesse modo, ver ROLE_SLOT_ALIASES abaixo), 1 FW
--   5v5 (5 por time): 1 GK, 1 DF (zagueiro), 2 MF (meio), 1 FW (atacante)
--   7v7 (7 por time): 1 GK, 2 DF, 2 MF, 2 FW
-- Sala Livre (tamanho de time variável, sem PerTeam fixo) usa um template
-- genérico de fallback (1 GK + resto alternando DF/MF/FW) já que não tem
-- como pré-definir uma composição pra qualquer N.
local FIXED_FORMATION_TEMPLATES_WITH_GK = {
	[3] = { "GK", "FW", "MF" },
	[5] = { "GK", "FW", "FW", "MF", "DF" },
	[7] = { "GK", "FW", "FW", "MF", "MF", "DF", "DF" },
}

-- ⚠️ NOVO: PEDIDO — "remova a prioridade por goleiro, não é mais
-- necessário ter goleiro no jogo, devido ao GK bot". Quando NENHUM
-- jogador do time prefere GK de verdade, o time nem reserva mais essa
-- vaga "de guarda" (era ela que sobrava vazia e puxava algum atacante de
-- overflow lá pra trás — ver OVERFLOW_ORDER abaixo). O GK bot já cobre o
-- gol sozinho nesse caso (ver hasHumanGK em GKBotController.legacy.luau).
-- A vaga que seria do GK vira reforço na DEFESA (1 zagueiro a mais) —
-- é a posição que mais sente falta de um goleiro humano por perto.
local FIXED_FORMATION_TEMPLATES_NO_GK = {
	[3] = { "FW", "MF", "DF" },
	[5] = { "FW", "FW", "MF", "MF", "DF" },
	[7] = { "FW", "FW", "MF", "MF", "DF", "DF", "DF" },
}

-- PEDIDO (3v3): a vaga "DF" desse template não é só pra quem prefere
-- zagueiro — como não existe vaga de MF separada nesse modo, quem
-- prefere "MF" também cai direto nela (sem contar como overflow). Chave
-- é o TAMANHO DO TIME (igual FIXED_FORMATION_TEMPLATES); só times de 3
-- têm esse mapeamento — 5v5/7v7 continuam com DF e MF como vagas
-- totalmente separadas.
local ROLE_SLOT_ALIASES_BY_TEAM_SIZE = {
	[3] = { DF = { "DF", "MF" } }, -- vaga "DF" aceita preferência DF OU MF
}

-- Resolve pra qual VAGA (Role do template) a preferência de um jogador
-- deve ser considerada, dado o tamanho do time — normalmente é a própria
-- Role preferida (sem alias nenhum). ⚠️ NOVO: o alias DF/MF do 3v3 só faz
-- sentido no template COM GK (onde não existe vaga de MF separada); no
-- template SEM GK, DF e MF são vagas de verdade, então a preferência vale
-- literal, sem aliasing.
local function resolveSlotRole(preferredRole, teamSize, wantsGK)
	if not wantsGK then return preferredRole end
	local aliases = ROLE_SLOT_ALIASES_BY_TEAM_SIZE[teamSize]
	if not aliases then return preferredRole end
	for slotRole, acceptedRoles in pairs(aliases) do
		if table.find(acceptedRoles, preferredRole) then
			return slotRole
		end
	end
	return preferredRole
end

-- ⚠️ NOVO: `wantsGK` decide qual família de templates usar — só reserva
-- vaga de GK quando pelo menos 1 jogador do time realmente prefere essa
-- posição (ver assignTeamFormation, que calcula isso a partir do Role de
-- cada jogador antes de chamar esta função).
local function buildFormationSlots(teamSize, wantsGK)
	local templates = wantsGK and FIXED_FORMATION_TEMPLATES_WITH_GK or FIXED_FORMATION_TEMPLATES_NO_GK
	local template = templates[teamSize]
	if template then
		local slots = {}
		for i, role in ipairs(template) do
			slots[i] = role
		end
		return slots
	end

	-- Fallback genérico (Sala Livre ou qualquer tamanho fora de 3/5/7): só
	-- reserva GK primeiro se alguém realmente quiser; o resto sempre
	-- alterna DF/MF/FW.
	local slots = {}
	if teamSize <= 0 then return slots end
	local startIndex = 1
	if wantsGK then
		table.insert(slots, "GK")
		startIndex = 2
	end
	local cycle = { "FW", "MF", "DF" } -- ⚠️ v33: ataque primeiro
	local cycleIndex = 1
	for _ = startIndex, teamSize do
		table.insert(slots, cycle[cycleIndex])
		cycleIndex = (cycleIndex % #cycle) + 1
	end
	return slots
end

-- PEDIDO: "se o cara não puder pegar atacante, passe pra midfielder; se
-- já tiver um midfielder ocupando a vaga, passe pro zagueiro" — cadeia de
-- prioridade de overflow, sempre andando em direção à defesa primeiro.
-- ⚠️ NOVO: PEDIDO — "remova a prioridade por goleiro". GK saiu de TODAS
-- as cadeias de overflow — ninguém que prefere jogar de linha é mais
-- empurrado pro gol como "sobra" (era exatamente isso que fazia atacante
-- virar goleiro sem querer). Com o GK bot cobrindo o gol sozinho quando
-- ninguém prefere essa posição (ver hasHumanGK em GKBotController.
-- legacy.luau) e a vaga de GK nem existindo mais no template nesse caso
-- (ver FIXED_FORMATION_TEMPLATES_NO_GK acima), não sobra situação real em
-- que isso seria necessário. GK continua tendo sua PRÓPRIA cadeia (pra
-- quando mais de 1 jogador prefere GK de verdade — o "perdedor" do
-- sorteio vai pra linha normalmente, sem problema nenhum nisso).
local OVERFLOW_ORDER = {
	FW = { "MF", "DF" },
	MF = { "DF", "FW" },
	DF = { "MF", "FW" },
	GK = { "DF", "MF", "FW" },
}

-- Fração lateral (-1..1) de cada vaga, calculada a partir da posição dela
-- ENTRE AS VAGAS DO MESMO ROLE NO TEMPLATE (não entre os jogadores
-- presentes agora) — é isso que faz o layout ficar fixo mesmo quando
-- troca quem ocupa cada vaga.
local function buildLateralFractionsForSlots(slots)
	local indicesByRole = {}
	for i, role in ipairs(slots) do
		indicesByRole[role] = indicesByRole[role] or {}
		table.insert(indicesByRole[role], i)
	end

	local lateralFractionOfSlot = {}
	for _, indices in pairs(indicesByRole) do
		local count = #indices
		for order, slotIndex in ipairs(indices) do
			lateralFractionOfSlot[slotIndex] = (count > 1) and (-1 + 2 * (order - 1) / (count - 1)) or 0
		end
	end
	return lateralFractionOfSlot
end

-- Cache por time: só recalcula a escalação (e o sorteio de quem fica em
-- cada vaga quando tem empate de Role) quando o ROSTER do time muda de
-- verdade (alguém entrou/saiu) — assim um gol não reembaralha quem está
-- em qual posição no meio da partida.
local teamFormationCache = {} -- [teamName] = { RosterKey=, SlotOfUserId=, Slots=, LateralFractionOfSlot= }

local function computeRosterKey(players)
	local ids = {}
	for _, plr in ipairs(players) do table.insert(ids, plr.UserId) end
	table.sort(ids)
	return table.concat(ids, ",")
end

local function shuffleInPlace(list)
	for i = #list, 2, -1 do
		local j = math.random(i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function assignTeamFormation(teamName)
	local teamPlayers = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName then
			table.insert(teamPlayers, plr)
		end
	end
	table.sort(teamPlayers, function(a, b) return a.UserId < b.UserId end)

	local rosterKey = computeRosterKey(teamPlayers)
	local cached = teamFormationCache[teamName]
	if cached and cached.RosterKey == rosterKey then
		return cached
	end

	-- ⚠️ NOVO: só reserva vaga de GK se pelo menos 1 jogador do time
	-- realmente prefere essa posição (ver PEDIDO acima) — sem isso, o
	-- time usa o template SEM GK (1 defensor a mais no lugar).
	local wantsGK = false
	for _, plr in ipairs(teamPlayers) do
		if plr:GetAttribute("Role") == "GK" then
			wantsGK = true
			break
		end
	end

	local slots = buildFormationSlots(#teamPlayers, wantsGK)
	local lateralFractionOfSlot = buildLateralFractionsForSlots(slots)

	local slotIndicesByRole = {}
	for i, role in ipairs(slots) do
		slotIndicesByRole[role] = slotIndicesByRole[role] or {}
		table.insert(slotIndicesByRole[role], i)
	end

	-- Agrupa jogadores pela Role PREFERIDA (a do slot do personagem, ver
	-- PlayerSystems.legacy.luau) — passando por resolveSlotRole primeiro
	-- (no 3v3 COM GK, DF e MF preferidos caem os dois na mesma vaga "DF",
	-- ver ROLE_SLOT_ALIASES_BY_TEAM_SIZE acima; sem GK, DF e MF já são
	-- vagas de verdade, sem alias nenhum). Quem tem uma Role sem vaga
	-- nenhuma no template cai direto no overflow.
	local playersByRole = {}
	for _, plr in ipairs(teamPlayers) do
		local role = resolveSlotRole(plr:GetAttribute("Role"), #teamPlayers, wantsGK)
		if not slotIndicesByRole[role] then role = "__NONE__" end
		playersByRole[role] = playersByRole[role] or {}
		table.insert(playersByRole[role], plr)
	end

	local slotOfUserId = {}
	local usedSlot = {}
	-- overflowPlayers guarda { Player=, PreferredRole= } — precisa lembrar
	-- a Role preferida original de cada jogador de overflow pra saber por
	-- qual cadeia (OVERFLOW_ORDER) andar depois.
	local overflowPlayers = {}

	for role, slotIndices in pairs(slotIndicesByRole) do
		local candidates = shuffleInPlace({ table.unpack(playersByRole[role] or {}) })
		for i, plr in ipairs(candidates) do
			if i <= #slotIndices then
				-- PEDIDO: mais de um jogador querendo a mesma posição —
				-- o embaralhamento acima já escolheu aleatoriamente quem
				-- fica; os demais (i > #slotIndices) vão de overflow.
				slotOfUserId[plr.UserId] = slotIndices[i]
				usedSlot[slotIndices[i]] = true
			else
				table.insert(overflowPlayers, { Player = plr, PreferredRole = role })
			end
		end
	end
	for _, plr in ipairs(playersByRole["__NONE__"] or {}) do
		table.insert(overflowPlayers, { Player = plr, PreferredRole = nil })
	end

	-- Vagas vazias, separadas por Role — mutável conforme o overflow vai
	-- ocupando (table.remove tira a vaga usada da lista pra não ser
	-- oferecida de novo).
	local emptySlotIndicesByRole = {}
	for role, slotIndices in pairs(slotIndicesByRole) do
		local emptyList = {}
		for _, idx in ipairs(slotIndices) do
			if not usedSlot[idx] then table.insert(emptyList, idx) end
		end
		emptySlotIndicesByRole[role] = emptyList
	end

	-- PEDIDO: overflow segue a cadeia de prioridade (ex.: atacante sem
	-- vaga -> tenta meio -> se meio também já estiver ocupado, tenta
	-- zagueiro), não "qualquer vaga vazia". A ordem de QUEM processa
	-- primeiro (quando tem mais de 1 jogador de overflow) é embaralhada,
	-- pra não sempre favorecer o mesmo jogador.
	shuffleInPlace(overflowPlayers)
	for _, entry in ipairs(overflowPlayers) do
		local plr, preferredRole = entry.Player, entry.PreferredRole
		local chain = OVERFLOW_ORDER[preferredRole] or { "DF", "MF", "FW" } -- ⚠️ GK removido daqui também (ver PEDIDO acima)

		local placed = false
		for _, candidateRole in ipairs(chain) do
			local emptyList = emptySlotIndicesByRole[candidateRole]
			if emptyList and #emptyList > 0 then
				local slotIndex = table.remove(emptyList, 1)
				slotOfUserId[plr.UserId] = slotIndex
				usedSlot[slotIndex] = true
				placed = true
				break
			end
		end

		if not placed then
			-- Segurança: não deveria acontecer (o total de vagas sempre
			-- bate com o total de jogadores do time), mas se acontecer,
			-- usa QUALQUER vaga que ainda sobrar em vez de deixar alguém
			-- sem posição nenhuma.
			for _, emptyList in pairs(emptySlotIndicesByRole) do
				if #emptyList > 0 then
					local slotIndex = table.remove(emptyList, 1)
					slotOfUserId[plr.UserId] = slotIndex
					usedSlot[slotIndex] = true
					break
				end
			end
		end
	end

	-- IMPORTANTE: sincroniza o Attribute "Role" de cada jogador com a vaga
	-- que ele REALMENTE ocupou — não só a preferida. GKInput/PulseInstinct-
	-- Data (RoleRequired="GK") e o resto do jogo leem esse Attribute pra
	-- saber quem é goleiro; sem isso, o jogador que perdeu o "empate" pelo
	-- GK e foi pra outra vaga continuaria com mecânica de goleiro mesmo
	-- jogando de linha (e vice-versa).
	for _, plr in ipairs(teamPlayers) do
		local slotIndex = slotOfUserId[plr.UserId]
		if slotIndex then
			plr:SetAttribute("Role", slots[slotIndex])
		end
	end

	local newCache = {
		RosterKey = rosterKey,
		SlotOfUserId = slotOfUserId,
		Slots = slots,
		LateralFractionOfSlot = lateralFractionOfSlot,
		WantsGK = wantsGK, -- ⚠️ NOVO: pra getFormationCFrame saber qual variante de SPAWN_SLOT_NAMES_BY_TEAM_SIZE usar
	}
	teamFormationCache[teamName] = newCache
	return newCache
end

local blueDefendingTeam, yellowDefendingTeam
if formationReady then
	local blueLocal = campoHit.CFrame:PointToObjectSpace(blueGoal.Position)
	local yellowLocal = campoHit.CFrame:PointToObjectSpace(yellowGoal.Position)
	goalAxisIsX = math.abs(blueLocal.X - yellowLocal.X) >= math.abs(blueLocal.Z - yellowLocal.Z)
	fieldHalfSize = campoHit.Size / 2
	touchHalf = goalAxisIsX and fieldHalfSize.Z or fieldHalfSize.X

	local function defendingTeamOf(goalPart)
		local scoringTeam = goalPart:GetAttribute("ScoringTeam")
		for _, teamName in ipairs(Config.TEAM_NAMES) do
			if teamName ~= scoringTeam then return teamName end
		end
		return nil
	end
	blueDefendingTeam = defendingTeamOf(blueGoal)
	yellowDefendingTeam = defendingTeamOf(yellowGoal)
else
	warn("⚠️ MatchController: CampoHIT/GolAzul/GolAmarelo não encontrados — formação por posição desligada, personagens vão nascer sem reposicionamento.")
end

local function ownGoalPartOf(teamName)
	if blueDefendingTeam == teamName then return blueGoal end
	if yellowDefendingTeam == teamName then return yellowGoal end
	return nil
end

-- CFrame de formação pra esse jogador (posição + olhando pro gol
-- adversário) — nil se time/role/geometria do campo não estiverem
-- prontos ainda (aí quem chama simplesmente não mexe no personagem).
local function getFormationCFrame(player)
	if not formationReady then return nil end
	if not player.Team then return nil end
	local teamName = player.Team.Name

	local ownGoal = ownGoalPartOf(teamName)
	if not ownGoal then return nil end
	local enemyGoal = (ownGoal == blueGoal) and yellowGoal or blueGoal

	-- Vaga FIXA desse jogador dentro do time (ver assignTeamFormation
	-- acima) — decide tanto o Role usado pra profundidade quanto a
	-- posição lateral, os dois vindos do TEMPLATE da formação, não de
	-- "quantos jogadores têm essa Role agora".
	local formation = assignTeamFormation(teamName)
	local slotIndex = formation.SlotOfUserId[player.UserId]
	local role = slotIndex and formation.Slots[slotIndex] or player:GetAttribute("Role")
	local lateralFraction = slotIndex and (formation.LateralFractionOfSlot[slotIndex] or 0) or 0

	-- PEDIDO: se existirem parts fixas pra esse tamanho de time (ver
	-- SPAWN_SLOT_NAMES_BY_TEAM_SIZE_WITH_GK/_NO_GK acima), usa a
	-- posição/direção delas direto em vez do cálculo por fração abaixo —
	-- X/Z vêm da part, a altura continua calculada (não depende de acertar
	-- a altura exata no Studio) e a direção olhada vem do LookVector da
	-- própria part (oriente cada uma virada pro gol adversário).
	-- ⚠️ NOVO: qual das duas listas usar depende de formation.WantsGK
	-- (se o time atual tem alguém pedindo GK ou não).
	local slotNamesTable = formation.WantsGK and SPAWN_SLOT_NAMES_BY_TEAM_SIZE_WITH_GK or SPAWN_SLOT_NAMES_BY_TEAM_SIZE_NO_GK
	local slotNames = slotIndex and slotNamesTable[#formation.Slots]
	local slotName = slotNames and slotNames[slotIndex]
	local spawnPart = slotName and spawnParts[teamName] and spawnParts[teamName][slotName]
	if spawnPart then
		local standY = ballSpawnPosition.Y + 3
		local worldPos = Vector3.new(spawnPart.Position.X, standY, spawnPart.Position.Z)
		local flatLook = Vector3.new(spawnPart.CFrame.LookVector.X, 0, spawnPart.CFrame.LookVector.Z)
		if flatLook.Magnitude > 0.01 then
			return CFrame.lookAt(worldPos, worldPos + flatLook)
		end
		return CFrame.new(worldPos)
	end

	local ownAxis = goalAxisValue(campoHit.CFrame:PointToObjectSpace(ownGoal.Position))
	local enemyAxis = goalAxisValue(campoHit.CFrame:PointToObjectSpace(enemyGoal.Position))
	local depthFraction = ROLE_DEPTH_FRACTION[role] or DEFAULT_DEPTH_FRACTION
	local axisCoord = ownAxis + (enemyAxis - ownAxis) * depthFraction

	local touchCoord = lateralFraction * touchHalf * 0.75

	local localFlat = toLocalVector(axisCoord, touchCoord)
	local worldFlat = campoHit.CFrame:PointToWorldSpace(localFlat)
	local standY = ballSpawnPosition.Y + 3 -- aproximação de altura do HumanoidRootPart em pé
	local worldPos = Vector3.new(worldFlat.X, standY, worldFlat.Z)

	-- Olhando pro gol adversário (eixo do gol, sem componente lateral) —
	-- todo mundo começa de frente pro ataque, igual formação de verdade.
	local enemyLocalFlat = toLocalVector(enemyAxis, touchCoord)
	local enemyWorldFlat = campoHit.CFrame:PointToWorldSpace(enemyLocalFlat)
	local lookTarget = Vector3.new(enemyWorldFlat.X, standY, enemyWorldFlat.Z)

	if (lookTarget - worldPos).Magnitude < 0.01 then
		return CFrame.new(worldPos)
	end
	return CFrame.lookAt(worldPos, lookTarget)
end

-- ⚠️ NOVO: exposto pra EntranceCutsceneController.legacy.luau conseguir
-- montar o roster da cutscene de entrada com a posição REAL de formação de
-- cada jogador (pra cada "boneco" da fila terminar exatamente onde o
-- personagem de verdade dele já está esperando, escondido).
_G.GetFormationCFrame = getFormationCFrame

-- Chamado pelo PlayerSystems.legacy.luau em todo CharacterAdded (spawn
-- inicial E respawn depois de morrer — não tem SpawnLocation, então isso
-- é o único jeito do personagem aparecer no lugar certo).
_G.PositionPlayerAtFormation = function(player, character)
	character = character or player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart", 5)
	if not root then return end

	local cframe = getFormationCFrame(player)
	if not cframe then return end -- time/role ainda não definido — fica onde o Roblox colocou

	-- ⚠️ v120b: cancela carrinho/dive/ragdoll/deslocamento em andamento antes de
	-- teleportar (senão o corpo era puxado de volta ou caía pelo chão — ver
	-- _G.LimparAcoesDoJogador no BallController)
	if _G.LimparAcoesDoJogador then pcall(_G.LimparAcoesDoJogador, player) end
	root.CFrame = cframe
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

-- Reposiciona TODO MUNDO já em campo — chamado pelo performKickoff (todo
-- gol + início de cada tempo, ver abaixo): "cada um voltar pra sua
-- posição a partir de cada gol".
local function resetAllPlayersToFormation()
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			_G.PositionPlayerAtFormation(plr, plr.Character)
		end
	end
end

-- ⚠️ v111: em place NÃO publicado (ex.: aberto pelo AutoRecovery) o GetDataStore
-- dá ERRO — e, solto aqui no topo, derrubava o MatchController inteiro: gol não
-- contava (_G.RegisterGoal nunca existia), sem kickoff e sem bola parada. Agora
-- falha quieto: só o salvamento das recompensas fica desligado (o SetAsync lá
-- embaixo já está em pcall).
local rewardsDataStore = nil
do
	local ok, ds = pcall(function() return DataStoreService:GetDataStore("MatchRewards_V1") end)
	if ok then
		rewardsDataStore = ds
	else
		warn("⚠️ MatchController: DataStore indisponível (place não publicado?) — recompensas não serão salvas. " .. tostring(ds))
	end
end

local whistleSound = Instance.new("Sound")
whistleSound.SoundId = Config.SOUNDS.Whistle
-- ⚠️ v48: volume veio pro Config e subiu (0.7 -> 1) — com música tocando,
-- o apito precisa cortar por cima dela. Ver Config.WHISTLE_VOLUME.
whistleSound.Volume = Config.WHISTLE_VOLUME
whistleSound.Parent = ball

-- ⚠️ v31 — PEDIDO: "o áudio do apito só metade da duração, tem um tempo aí
-- que é inútil. Coloca um fade out de 0.3 segundos no final."
--
-- O arquivo tem cauda morta depois do apito em si. Em vez de pedir pra você
-- reeditar o áudio, o corte é feito aqui: toca, e um pouco antes da metade
-- começa a baixar o volume até zero, aí para. O fade evita o "clique" que um
-- Stop() seco daria no meio da onda.
--
-- TimeLength só existe DEPOIS que o som carrega — por isso o IsLoaded com
-- fallback: sem a duração real, usa Config.WHISTLE_FALLBACK_SECONDS.
local TweenService = game:GetService("TweenService")
local whistleVolumeBase = whistleSound.Volume
local whistleGeneration = 0

local function playWhistle()
	whistleGeneration += 1
	local minhaGeracao = whistleGeneration

	whistleSound.Volume = whistleVolumeBase
	whistleSound.TimePosition = 0
	whistleSound:Play()

	task.spawn(function()
		-- espera o som carregar pra saber a duração de verdade (no máximo 1s)
		local esperou = 0
		while not whistleSound.IsLoaded and esperou < 1 do
			task.wait(0.05)
			esperou += 0.05
		end
		if whistleGeneration ~= minhaGeracao then return end

		local duracao = whistleSound.IsLoaded and whistleSound.TimeLength or 0
		if duracao <= 0 then duracao = Config.WHISTLE_FALLBACK_SECONDS end

		local fade = Config.WHISTLE_FADE_SECONDS
		local corte = duracao * Config.WHISTLE_PLAY_FRACTION
		local ateOFade = math.max(corte - fade, 0.05)

		task.wait(ateOFade)
		if whistleGeneration ~= minhaGeracao then return end

		TweenService:Create(whistleSound, TweenInfo.new(fade), { Volume = 0 }):Play()
		task.wait(fade)
		if whistleGeneration ~= minhaGeracao then return end

		whistleSound:Stop()
		whistleSound.Volume = whistleVolumeBase
	end)
end

-- Exposto pra quem não é o MatchController — hoje o OutOfBoundsController
-- (apito de bola saindo de campo).
_G.PlayWhistle = playWhistle

-- ===== ESTADO DA PARTIDA =====
local matchActive = false
local matchEnded = false
local matchPaused = false
local timeRemaining = Config.HALF_DURATION -- sempre a duração de UM tempo (4 min)
local currentHalf = 1
-- ⚠️ v104 — GOLDEN GOAL: "overtime, marcou um gol, acabou". true entre o gol
-- da prorrogação e o fim da partida (comemoração + replay) — impede que o
-- fim do relógio chame endMatch por cima do replay.
local golDeOuroPendente = false

_G.SetMatchPaused = function(paused)
	matchPaused = paused
end

local score = {} -- [teamName] = number
for _, teamName in ipairs(Config.TEAM_NAMES) do
	score[teamName] = 0
end

-- ⚠️ NOVAS: expositores simples pro sistema de Pulso/Instinto (ver
-- InstinctController.legacy.luau) checar "faltam X segundos" e "time
-- perdendo/ganhando" sem precisar duplicar estado aqui.
_G.GetMatchTimeRemaining = function()
	return timeRemaining
end
_G.GetTeamScore = function(teamName)
	return score[teamName] or 0
end

local playerRewards = {} -- [userId] = { MoneyEarned, XPEarned, Stats = {...} }

-- ⚠️ v104 — SALA PERSONALIZADA. PEDIDO: "a sala personalizada é uma sala
-- própria sua — só você ou as pessoas da sua party. Não faz sentido ganhar
-- recompensas nela. Mesmo que puxe sozinho, o GK vai estar sempre spawnado."
-- O Lobby manda TeleportData.Privada = true (ver MatchmakingQueue, place
-- Lobby). Aqui: começa com 1 jogador, recompensas zeradas (nada vai pro
-- Lobby) e o GKBotController põe bot nos dois gols mesmo com time vazio.
local salaPersonalizada = false
-- ⚠️ v104 — TUTORIAL: "coloque um tutorial opcional no início do jogo... ele
-- já vai entrar dentro de uma partida... desative o restante da gameplay: o
-- timer, as cutscenes de entrada". TeleportData.Tutorial = true (Lobby,
-- TutorialLobbyServer). Sem relógio, sem cutscene de entrada, sem goleiro
-- bot, sem recompensa; o roteiro dos passos é o TutorialServer.
local modoTutorial = false
local function lerSalaPersonalizada(player)
	local ok, joinData = pcall(function() return player:GetJoinData() end)
	local td = ok and joinData and joinData.TeleportData
	if typeof(td) == "table" and td.Privada == true then
		salaPersonalizada = true
		_G.SalaPersonalizada = true
	end
	-- (teste no Studio: atributo DebugTutorial = true no Workspace força o modo)
	if (typeof(td) == "table" and td.Tutorial == true) or workspace:GetAttribute("DebugTutorial") == true then
		modoTutorial = true
		salaPersonalizada = true
		_G.SalaPersonalizada = true
		_G.ModoTutorial = true
	end
end
for _, p in ipairs(Players:GetPlayers()) do lerSalaPersonalizada(p) end
Players.PlayerAdded:Connect(lerSalaPersonalizada)

-- ===== RECOMPENSAS =====
local function ensureRewardData(player)
	if playerRewards[player.UserId] then return playerRewards[player.UserId] end
	local data = {
		UserId = player.UserId,
		PlayerName = player.Name,
		MoneyEarned = Rewards.BASE_PARTICIPATION,
		XPEarned = Rewards.BASE_XP,
		-- ⚠️ v123: mais informação da partida pras ESTATÍSTICAS do Lobby (chutes,
		-- passes, Hissatsus usadas) — ver _G.RegistrarEstatistica
		Stats = { Goals = 0, Assists = 0, Tackles = 0, Dribbles = 0, Saves = 0, Shots = 0, Passes = 0, Hissatsus = 0, MVP = false, Won = false },
		MatchResult = "ongoing",
	}
	playerRewards[player.UserId] = data
	return data
end

local function addReward(player, money, xp)
	local data = ensureRewardData(player)
	data.MoneyEarned += money
	data.XPEarned += xp
end

_G.RegisterTackle = function(player, stolenFrom)
	local data = ensureRewardData(player)
	data.Stats.Tackles += 1
	addReward(player, Rewards.TACKLE_MONEY, Rewards.TACKLE_XP)
end

-- ⚠️ NOVO: chamado de BallController.legacy.luau toda vez que uma finta
-- de drible dá certo (sempre dá — sem chance). Alimenta Stats.Dribbles,
-- que LobbyRewardsReceiver.legacy.luau usa pra progredir a missão diária
-- "Driblar 20 vezes" no Lobby (ver QuestData.luau).
_G.RegisterDribble = function(player)
	local data = ensureRewardData(player)
	data.Stats.Dribbles += 1
	addReward(player, Rewards.DRIBBLE_MONEY, Rewards.DRIBBLE_XP)
end

-- ⚠️ NOVO: chamado de BallController.legacy.luau toda vez que um goleiro
-- pega um chute de verdade (mergulho interceptando bola vindo em direção
-- ao próprio gol). Alimenta Stats.Saves, usado pelas missões diárias de
-- goleiro no Lobby (ver QuestData.luau).
_G.RegisterSave = function(player)
	local data = ensureRewardData(player)
	data.Stats.Saves += 1
	addReward(player, Rewards.SAVE_MONEY, Rewards.SAVE_XP)
end

-- ⚠️ v123 — PEDIDO: "as estatísticas do Lobby ainda não estão armazenando direito: é só
-- coletar as informações da partida na recompensa... leva mais algumas informações e
-- coloca pra aumentar nas estatísticas pessoais". Contador genérico (sem dinheiro/XP):
-- Shots (chute a gol, normal ou Hissatsu), Passes, Hissatsus (usadas com sucesso).
_G.RegistrarEstatistica = function(player, chave, quanto)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	local data = ensureRewardData(player)
	data.Stats[chave] = (tonumber(data.Stats[chave]) or 0) + (quanto or 1)
end


Players.PlayerAdded:Connect(function(player)
	task.wait(1)
	ensureRewardData(player)
end)

-- ===== SAÍDA DE BOLA (kickoff) =====
-- Reposiciona a bola no centro do campo e força a posse pro jogador mais
-- perto do time que tem direito à saída (time 1 no 1º tempo, time 2 no 2º).
-- FIX: usava a Position da CampoHIT como "centro" — se essa part não
-- estiver EXATAMENTE no meio dos dois gols (qualquer desalinhamento no
-- Studio, por menor que seja), a bola nascia fora do centro de verdade.
-- Ponto médio entre os dois gols é o centro real do campo por definição
-- (mesma ideia do círculo central de um campo de futebol de verdade),
-- então usa isso primeiro — CampoHIT só entra como fallback se os gols
-- não existirem por algum motivo.
local function getFieldCenter()
	if blueGoal and yellowGoal then
		local midpoint = (blueGoal.Position + yellowGoal.Position) / 2
		return Vector3.new(midpoint.X, ballSpawnPosition.Y, midpoint.Z)
	end
	local campoHit = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
	if campoHit then
		return Vector3.new(campoHit.Position.X, ballSpawnPosition.Y, campoHit.Position.Z)
	end
	return ballSpawnPosition
end

-- FIX: sem isso, a bola só era recentralizada dentro de performKickoff —
-- ou seja, só depois da contagem regressiva do 1º tempo terminar. Até lá
-- (o server acabou de subir, contagem regressiva rolando) ela ficava
-- parada onde foi deixada no Studio, fora do centro. Centraliza uma vez,
-- assim que o server sobe (espera _G.ResetBallState existir — Ball-
-- Controller.legacy.luau é outro Script, pode carregar antes ou depois
-- deste, ordem não é garantida).
task.spawn(function()
	local deadline = os.clock() + 5
	while not _G.ResetBallState and os.clock() < deadline do
		task.wait(0.1)
	end
	if _G.ResetBallState then
		_G.ResetBallState(getFieldCenter())
	end
end)

local function closestPlayerOfTeam(teamName, worldPoint)
	local team = Teams:FindFirstChild(teamName)
	if not team then return nil end

	local best, bestDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team == team then
			local character = plr.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local dist = (root.Position - worldPoint).Magnitude
				if dist < bestDist then
					bestDist, best = dist, plr
				end
			end
		end
	end
	return best
end

local function performKickoff(kickoffTeamName)
	local center = getFieldCenter()

	if _G.SetDeadBallMode then _G.SetDeadBallMode(true) end
	resetAllPlayersToFormation() -- "cada um voltar pra sua posição" — todo gol + início de cada tempo
	if _G.ResetBallState then _G.ResetBallState(center) end

	-- ⚠️ v33 — PEDIDO: "o jogador que tiver a posse inicial da bola, depois de
	-- cada gol ou troca de lado, começa NO CENTRO com a bola. Ele pode passar
	-- pros outros, ou só dar um toquinho e pegar ele mesmo."
	--
	-- Antes ele só ganhava a posse onde quer que a formação o tivesse posto —
	-- podia ser lá atrás, com a bola teleportando pro pé dele de longe. Agora
	-- ele é levado ATÉ o círculo central, virado pro gol adversário, e só
	-- então recebe a bola.
	local taker = closestPlayerOfTeam(kickoffTeamName, center)
	if taker then
		local character = taker.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			-- mesmo jeito que getFormationCFrame acha o gol adversário
			local ownGoal = ownGoalPartOf(kickoffTeamName)
			local enemyGoal = ownGoal and ((ownGoal == blueGoal) and yellowGoal or blueGoal) or nil
			local olhar = enemyGoal
				and Vector3.new(enemyGoal.Position.X - center.X, 0, enemyGoal.Position.Z - center.Z)
				or root.CFrame.LookVector
			if olhar.Magnitude < 0.1 then olhar = root.CFrame.LookVector end

			-- Um passo atrás da bola, não em cima dela.
			local pos = Vector3.new(center.X, root.Position.Y, center.Z) - olhar.Unit * Config.KICKOFF_TAKER_OFFSET
			character:PivotTo(CFrame.lookAt(pos, pos + olhar.Unit))
		end
		if _G.SetBallOwnerForced then
			_G.SetBallOwnerForced(taker)
		end
	end

	if _G.SetDeadBallMode then _G.SetDeadBallMode(false) end
end

-- ===== GOLS =====
local goalDebounce = {}

-- ⚠️ NOVO: PEDIDO — "toda vez que um gol é marcado, é contado como 2".
-- Causa: existem DUAS fontes independentes que podem chamar
-- _G.RegisterGoal pro MESMO gol físico — (1) o goalPart.Touched aqui
-- embaixo, confirmado alguns studs depois via pendingGoalChecks, e (2) a
-- checagem de "segmento cruzou a caixa do gol" em OutOfBoundsController.
-- legacy.luau, que roda em TODO Heartbeat (não só em tunelamento — bola
-- entrando normal também cruza o segmento) e chama _G.RegisterGoal
-- DIRETO, sem nenhuma visibilidade do `goalDebounce` local daqui. Na
-- prática, quase todo gol dispara as duas: o Touched confirma pelo
-- caminho normal, e no mesmo intervalo de tempo a checagem de segmento
-- do outro script também detecta a bola cruzando e conta de novo.
--
-- Fix: um debounce GLOBAL dentro do próprio onGoalScored (não por
-- goalPart) — não importa QUAL das duas fontes chega primeiro, só a
-- PRIMEIRA chamada dentro da janela conta; qualquer outra logo em
-- seguida (do mesmo gol de verdade) é ignorada.
--
-- v2 — PEDIDO: "o audio está tocando duas vezes... repetindo quando o
-- replay começa" — suspeita: a SEGUNDA fonte (OutOfBoundsController) às
-- vezes só confirma alguns segundos depois (bola quicando perto da linha,
-- streaming, etc.), e 1.5s não era suficiente pra pegar isso — se a
-- confirmação atrasada bater bem perto de Config.GOAL_CELEBRATION_SECONDS
-- (4s), ela escapava da janela antiga, contava como um SEGUNDO gol de
-- verdade, e disparava tudo de novo (Remotes.GoalScored) bem na hora em
-- que o replay começa. Aumentado pra cobrir com folga toda a janela de
-- comemoração — se isso ERA a causa, o aviso "IGNORADO: duplicata
-- detectada" abaixo vai aparecer no Output do servidor a cada gol a
-- partir de agora (confirma o diagnóstico).
local GOAL_DEDUP_WINDOW = 6 -- segundos (era 1.5)
local lastGoalConfirmedAt = -math.huge

-- ⚠️ NOVO: comemoração do jogador que fez o gol (PEDIDO: "é uma animação
-- específica pra gol (eles comemorando)... o jogador vai ter essa
-- comemoração durante uns 3-5 segundos, e depois parte direto pro
-- replay"). Config.ANIMATIONS.GoalCelebration = "" por enquanto — cole o
-- rbxassetid:// aqui quando a animação estiver publicada; até lá, essa
-- função só não faz nada (sem erro nenhum).
local celebrationTracks = {} -- [player] = AnimationTrack (pra dar Stop no fim da janela)

local function playGoalCelebration(scorer)
	-- ⚠️ v96: com a animação por código ligada, a comemoração vem do
	-- AnimadorProcedural (braços pra cima e socos no ar, em loop pela
	-- duração da comemoração) — não precisa mais de asset publicado.
	-- ⚠️ v110 — COSMÉTICOS: efeito de gol e comemoração equipados na Loja
	-- (ver CosmeticosServer). Sem comemoração equipada, fica a de sempre.
	if _G.EfeitoDeGolCosmetico then _G.EfeitoDeGolCosmetico(scorer) end
	if _G.TocarComemoracaoCosmetica and _G.TocarComemoracaoCosmetica(scorer) then
		return
	end
	if Config.ANIMACAO_PROCEDURAL then
		if scorer.Character and _G.AnimarAcao then
			_G.AnimarAcao(scorer.Character, "GoalCelebration", Config.GOAL_CELEBRATION_SECONDS)
		end
		return
	end
	local animationId = Config.NormalizeAnimationId(Config.ANIMATIONS.GoalCelebration)
	if not animationId or animationId == "" then return end

	local character = scorer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, track = pcall(function()
		return humanoid:LoadAnimation(animation)
	end)
	if not ok or not track then
		warn(("Não consegui carregar a animação de comemoração de gol para %s: %s"):format(scorer.Name, tostring(track)))
		return
	end

	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	track:Play()
	celebrationTracks[scorer] = track
end

local function stopGoalCelebration(scorer)
	local track = celebrationTracks[scorer]
	if track then
		track:Stop(0.3)
		celebrationTracks[scorer] = nil
	end
end

local function findGoalParts()
	local goals = {}
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant:GetAttribute("ScoringTeam") then
			table.insert(goals, descendant)
		end
	end
	return goals
end

local function onGoalScored(scoringTeamName)
	if not matchActive or matchPaused then
		-- ⚠️ v110: a bola parada dentro do gol disparava esse aviso dezenas de
		-- vezes seguidas — um por segundo basta
		if os.clock() - (_G.__UltimoAvisoGolIgnorado or 0) < 1 then return end
		_G.__UltimoAvisoGolIgnorado = os.clock()
		warn(("⚠️ Gol de %s IGNORADO: matchActive=%s, matchPaused=%s. Se matchActive nunca vira true, a partida provavelmente nunca começou — confira Config.MIN_PLAYERS_TO_START (%d) contra quantos jogadores estão de verdade no server."):format(
			scoringTeamName, tostring(matchActive), tostring(matchPaused), Config.MIN_PLAYERS_TO_START))
		return
	end
	if os.clock() - lastGoalConfirmedAt < GOAL_DEDUP_WINDOW then
		print(("⚠️ Gol de %s IGNORADO: duplicata detectada dentro de %.1fs do último gol confirmado (provavelmente Touched + checagem de segmento contando o mesmo lance)."):format(scoringTeamName, GOAL_DEDUP_WINDOW))
		return
	end

	-- ⚠️ v84 — PEDIDO: "impeça que o goleiro e o GK BOT possam fazer gol
	-- contra". As duas fontes de gol (Touched confirmado e checagem de
	-- segmento no OutOfBoundsController) passam por aqui, então a regra fica
	-- num lugar só: se o ÚLTIMO toque na bola foi do goleiro (Role "GK") ou do
	-- GK BOT do time que SOFRERIA o gol, o gol não vale — vira tiro de meta
	-- pro time dele (ver _G.AwardGoalKick no OutOfBoundsController). O último
	-- toque inclui o bot graças ao _G.GetLastBallTouch do BallController.
	local timeQueSofre = nil
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if teamName ~= scoringTeamName then timeQueSofre = teamName break end
	end
	local ultimoToque = _G.GetLastBallTouch and _G.GetLastBallTouch()
	if ultimoToque and timeQueSofre then
		local golContraDoGoleiro = false
		local quem = nil
		if ultimoToque.Kind == "Bot" and ultimoToque.Team == timeQueSofre then
			golContraDoGoleiro = true
			quem = "o GK BOT"
		elseif ultimoToque.Kind == "Player" and ultimoToque.Player
			and ultimoToque.Player.Team and ultimoToque.Player.Team.Name == timeQueSofre
			and ultimoToque.Player:GetAttribute("Role") == "GK" then
			golContraDoGoleiro = true
			quem = "o goleiro " .. ultimoToque.Player.Name
		end
		if golContraDoGoleiro then
			print(("🧤 Gol contra de %s (%s) ANULADO — tiro de meta pro %s."):format(quem, timeQueSofre, timeQueSofre))
			if _G.AwardGoalKick then
				_G.AwardGoalKick(timeQueSofre)
			elseif _G.ResetBallState then
				_G.ResetBallState(getFieldCenter()) -- sem o OutOfBoundsController: pelo menos tira a bola do gol
			end
			return
		end
	end

	lastGoalConfirmedAt = os.clock()

	score[scoringTeamName] = (score[scoringTeamName] or 0) + 1
	print("GOL registrado pra:", scoringTeamName, "-> tabela agora:", score)

	local scorer, assister = nil, nil
	if _G.GetBallTouchers then
		scorer, assister = _G.GetBallTouchers()
	end

	if scorer then
		local data = ensureRewardData(scorer)
		data.Stats.Goals += 1
		addReward(scorer, Rewards.GOAL_MONEY, Rewards.GOAL_XP)
	end
	if assister and assister ~= scorer then
		local data = ensureRewardData(assister)
		data.Stats.Assists += 1
		addReward(assister, Rewards.ASSIST_MONEY, Rewards.ASSIST_XP)
	end

	Remotes.GoalScored:FireAllClients(scoringTeamName, scorer, score)

	-- ⚠️ v104: no tutorial o gol só conclui o passo (sem replay nem kickoff)
	if modoTutorial then
		if _G.TutorialNotificar then _G.TutorialNotificar(scorer, "Gol") end
		return
	end

	-- ⚠️ NOVO: PEDIDO — "o timer não pode funcionar no replay (não pode
	-- descontar tempo)!" — pausa o relógio (runHalf já respeita
	-- `matchPaused`, ver "if not matchPaused then timeRemaining -= 1")
	-- durante TODA a janela de comemoração+replay, não só o replay em si
	-- (mais simples e consistente: nada acontece em campo nesse tempo
	-- todo mesmo). Despausa sozinho um pouco depois do replay acabar na
	-- tela de todo mundo (ver task.delay mais abaixo).
	matchPaused = true
	-- ⚠️ v113: o efeito de gol equipado pode durar bem mais que a comemoração
	-- (até 5x). playGoalCelebration (mais abaixo) preenche _G.UltimaDuracaoEfeitoGol
	-- na hora; o replay espera o MAIOR dos dois. Aqui já uso a duração do efeito
	-- que ESTE gol vai tocar (o efeito do autor equipado).
	local efeitoGolSeg = 0
	do
		local autor = scorer
		local item = autor and _G.DuracaoEfeitoGolDe and _G.DuracaoEfeitoGolDe(autor) or 0
		efeitoGolSeg = item
	end
	local esperaAntesDoReplay = math.max(Config.GOAL_CELEBRATION_SECONDS, efeitoGolSeg + 0.5)
	local replayTotalSeconds = esperaAntesDoReplay + (Config.GOAL_REPLAY_PLAYBACK_SECONDS or 6) + 1

	-- ⚠️ v104 — GOLDEN GOAL: gol na prorrogação encerra a partida. Mantém a
	-- comemoração e o replay (é o lance da vitória), mas em vez do kickoff
	-- vem o fim da partida. O relógio fica pausado até lá.
	if currentHalf == 3 then
		golDeOuroPendente = true
		if Remotes.GoldenGoal then Remotes.GoldenGoal:FireAllClients(scoringTeamName) end
		local snapshotOuro = _G.GetReplaySnapshot and _G.GetReplaySnapshot()
		local eventosOuro = _G.GetReplayEventos and _G.GetReplayEventos() or nil -- ⚠️ v112: na hora do gol
		if scorer then
			playGoalCelebration(scorer)
			if _G.NotifyFlowGoal then _G.NotifyFlowGoal(scorer) end
		end
		if scorer then task.delay(Config.GOAL_CELEBRATION_SECONDS, function() stopGoalCelebration(scorer) end) end
		task.delay(esperaAntesDoReplay, function()
			if _G.SetDeadBallMode then _G.SetDeadBallMode(true) end
			if snapshotOuro then
				Remotes.GoalReplay:FireAllClients(scoringTeamName, snapshotOuro, eventosOuro)
			end
			task.delay((Config.GOAL_REPLAY_PLAYBACK_SECONDS or 6) + 0.5, function()
				_G.EndMatchNow()
			end)
		end)
		return
	end
	task.delay(replayTotalSeconds, function()
		matchPaused = false
	end)

	-- ⚠️ v14 NOVO / v27: captura o snapshot do replay JÁ (bola + jogadores +
	-- bot, ver _G.GetReplaySnapshot em BallController.lua) — ANTES do
	-- performKickoff resetar a bola pro centro, senão o histórico já não
	-- representaria mais o lance que gerou o gol. A EXIBIÇÃO do replay em
	-- si (FireAllClients) é o que fica pra depois da comemoração, ver
	-- abaixo — o snapshot capturado aqui não muda com o tempo.
	local replaySnapshot = _G.GetReplaySnapshot and _G.GetReplaySnapshot()
	-- ⚠️ v112: os EVENTOS (Hissatsu, arma, animações) também são pegos AGORA. Antes
	-- eram lidos só depois da comemoração (4s) — e nesse tempo o histórico já
	-- tinha apagado o começo da jogada.
	local replayEventos = _G.GetReplayEventos and _G.GetReplayEventos() or nil

	-- ⚠️ NOVO: comemoração do jogador que fez o gol, ANTES do replay
	-- (pedido do usuário — ver playGoalCelebration acima). Só o replay e o
	-- kickoff esperam a janela de comemoração acabar; o resto da partida
	-- (outros jogadores) continua andando normal nesse meio-tempo.
	if scorer then
		playGoalCelebration(scorer)
		-- ⚠️ v67 — CARGA DO FLOW: gol é o que mais carrega (pedido: "gols vão
		-- ganhar mais"). Fica junto da comemoração porque é aqui que o autor do
		-- gol já está identificado.
		if _G.NotifyFlowGoal then _G.NotifyFlowGoal(scorer) end
	end

	-- (a comemoração para no tempo normal; o REPLAY espera o efeito de gol acabar)
	if scorer then
		task.delay(Config.GOAL_CELEBRATION_SECONDS, function() stopGoalCelebration(scorer) end)
	end
	task.delay(esperaAntesDoReplay, function()
		if replaySnapshot then
			Remotes.GoalReplay:FireAllClients(scoringTeamName, replaySnapshot, replayEventos) -- ⚠️ v103: + eventos · v112: capturados na hora do gol
		end

		-- depois de um gol, quem sofreu o gol é quem repõe a bola do centro
		local nextKickoffTeam = Config.TEAM_NAMES[1]
		for _, teamName in ipairs(Config.TEAM_NAMES) do
			if teamName ~= scoringTeamName then
				nextKickoffTeam = teamName
				break
			end
		end

		-- ⚠️ v13 FIX — PEDIDO: "o sistema de replay está interferindo no
		-- teleporte dos jogadores... assim que acabar o replay, AÍ SIM os
		-- jogadores vão cada um pra sua posição e realmente começa o apito.
		-- Senão começa um na base do outro e fica injusto."
		--
		-- O que acontecia: o performKickoff rodava no MESMO instante em que
		-- o replay começava. Ou seja, o teleporte pra formação acontecia
		-- enquanto todo mundo estava com a tela tomada pelo replay (e com o
		-- próprio personagem escondido, ver hideModel em GoalReplayClient) —
		-- e durante os ~6s seguintes os jogadores continuavam livres pra
		-- andar, invisíveis, saindo da formação pra onde quisessem. Quando o
		-- replay acabava e a câmera voltava, a formação que o kickoff tinha
		-- montado já não existia mais: cada um estava onde tinha andado no
		-- escuro, e a partida recomeçava com gente em cima de gente.
		--
		-- Agora o kickoff é a ÚLTIMA coisa a acontecer: enquanto o replay
		-- toca, a bola já fica parada no centro em bola morta (ninguém faz
		-- nada nem marca de novo), e só quando o replay termina é que todo
		-- mundo é teleportado pra formação — aí o apito toca e a bola sai.
		-- Ninguém tem tempo de sair do lugar entre o teleporte e o reinício.
		if _G.SetDeadBallMode then _G.SetDeadBallMode(true) end
		if _G.ResetBallState then _G.ResetBallState(getFieldCenter()) end

		task.delay(Config.GOAL_REPLAY_PLAYBACK_SECONDS or 6, function()
			performKickoff(nextKickoffTeam)
			-- O apito de recomeço: antes não existia depois de gol (só no
			-- início de cada tempo), então a bola simplesmente voltava a
			-- valer sem aviso nenhum.
			playWhistle()
			-- O relógio volta EXATAMENTE no apito. O task.delay lá em cima
			-- (replayTotalSeconds) continua existindo como rede de segurança:
			-- se alguma coisa aqui falhar, a partida não fica pausada pra
			-- sempre. Despausar duas vezes não faz mal nenhum.
			matchPaused = false
		end)
	end)
end

_G.RegisterGoal = onGoalScored -- ou o nome atual, se mudou

-- Confirmação "um pouco mais pra trás": o Touched sozinho conta o gol
-- assim que a BOUNDING BOX da bola encosta na hitbox — ou seja, na
-- borda da FRENTE do gol, antes da bola ter cruzado a linha de verdade.
-- Com lag isso vira gol "fantasma" que o goleiro nem tinha chance de
-- defender. Agora o Touched só ARMA uma verificação: a bola precisa
-- continuar avançando pra DENTRO do gol (eixo gol-a-gol do campo, o
-- mesmo já usado pra formação/eixo de lateral) por mais
-- Config.GOAL_LINE_BACK_OFFSET studs antes do gol ser confirmado de
-- verdade. Se a bola voltar (goleiro pegou/afastou) ou passar do tempo
-- limite, a tentativa é cancelada.
local pendingGoalChecks = {} -- [goalPart] = {startAxis, direction, scoringTeam, startTime}

local function cancelPendingGoal(goalPart)
	pendingGoalChecks[goalPart] = nil
end

local function confirmPendingGoal(goalPart, scoringTeam)
	pendingGoalChecks[goalPart] = nil
	goalDebounce[goalPart] = true
	task.delay(1, function() goalDebounce[goalPart] = nil end)
	onGoalScored(scoringTeam)
end

RunService.Heartbeat:Connect(function()
	if next(pendingGoalChecks) == nil then return end
	for goalPart, check in pairs(pendingGoalChecks) do
		if not goalPart.Parent then
			pendingGoalChecks[goalPart] = nil
		else
			local ballAxis = goalAxisValue(campoHit.CFrame:PointToObjectSpace(ball.Position))
			local advanced = (ballAxis - check.startAxis) * check.direction
			if advanced >= Config.GOAL_LINE_BACK_OFFSET then
				confirmPendingGoal(goalPart, check.scoringTeam)
			elseif advanced <= -Config.GOAL_LINE_REJECT_MARGIN then
				cancelPendingGoal(goalPart)
			elseif os.clock() - check.startTime >= Config.GOAL_LINE_CONFIRM_TIMEOUT then
				cancelPendingGoal(goalPart)
			end
		end
	end
end)

local function setupGoalDetection()
	for _, goalPart in ipairs(findGoalParts()) do
		goalPart.Touched:Connect(function(hit)
			if hit ~= ball then return end
			if goalDebounce[goalPart] then return end
			if pendingGoalChecks[goalPart] then return end -- já monitorando essa tentativa

			local scoringTeam = goalPart:GetAttribute("ScoringTeam")
			if not scoringTeam then return end

			if not (campoHit and goalAxisIsX ~= nil) then
				-- Sem geometria de eixo do campo detectada (CampoHIT/gols não
				-- encontrados) — não dá pra medir "mais pra trás", cai de
				-- volta pro comportamento antigo (Touched simples) em vez de
				-- travar o gol pra sempre.
				confirmPendingGoal(goalPart, scoringTeam)
				return
			end

			local goalAxis = goalAxisValue(campoHit.CFrame:PointToObjectSpace(goalPart.Position))
			local direction = goalAxis >= 0 and 1 or -1
			local startAxis = goalAxisValue(campoHit.CFrame:PointToObjectSpace(ball.Position))

			pendingGoalChecks[goalPart] = {
				startAxis = startAxis,
				direction = direction,
				scoringTeam = scoringTeam,
				startTime = os.clock(),
			}
		end)
	end
end

-- ===== MVP =====
local function calculateMVP()
	local mvpPlayer, maxPoints = nil, 0
	for userId, data in pairs(playerRewards) do
		local points = (data.Stats.Goals * 10) + (data.Stats.Assists * 5) + (data.Stats.Tackles * 2)
		if points > maxPoints then
			maxPoints = points
			mvpPlayer = Players:GetPlayerByUserId(userId)
		end
	end
	if mvpPlayer then
		local data = ensureRewardData(mvpPlayer)
		data.Stats.MVP = true
		addReward(mvpPlayer, Rewards.MVP_BONUS_MONEY, Rewards.MVP_BONUS_XP)
	end
	return mvpPlayer
end

-- ===== RESULTADO FINAL =====
local function applyMatchResult()
	local winningTeam, bestScore, tie = nil, -1, false
	for teamName, points in pairs(score) do
		if points > bestScore then
			bestScore, winningTeam, tie = points, teamName, false
		elseif points == bestScore then
			tie = true
		end
	end

	for _, player in ipairs(Players:GetPlayers()) do
		local data = ensureRewardData(player)
		local playerTeamName = player.Team and player.Team.Name

		-- ⚠️ v104 — PEDIDO: "a tela precisa aparecer também empate, não está
		-- aparecendo, tá dando derrota para os dois times que empataram".
		data.Placar = { [Config.TEAM_NAMES[1]] = score[Config.TEAM_NAMES[1]] or 0, [Config.TEAM_NAMES[2]] = score[Config.TEAM_NAMES[2]] or 0 }
		data.TimesOrdem = { Config.TEAM_NAMES[1], Config.TEAM_NAMES[2] }
		data.MeuTime = playerTeamName
		if tie or not winningTeam then
			data.MatchResult = "draw"
			addReward(player, Rewards.DRAW_MONEY or Rewards.LOSE_MONEY, Rewards.DRAW_XP or Rewards.LOSE_XP)
		elseif playerTeamName == winningTeam then
			data.MatchResult = "win"
			data.Stats.Won = true
			addReward(player, Rewards.WIN_MONEY, Rewards.WIN_XP)
		else
			data.MatchResult = "lose"
			addReward(player, Rewards.LOSE_MONEY, Rewards.LOSE_XP)
		end
	end
end

-- ===== SALVAR / TELEPORTAR =====
local function saveRewards(player)
	if salaPersonalizada then return end -- ⚠️ v104: sala personalizada não dá recompensa
	-- ⚠️ v123 — ACHADO (dados reais: 13 partidas na carreira com gols/dribles/desarmes
	-- todos 0): todo teste no STUDIO, ao parar o Play, caía aqui pelo PlayerRemoving e
	-- gravava uma recompensa "ongoing" de verdade no DataStore — o Lobby entregava
	-- depois (+1 partida zerada, +100 de dinheiro). No Studio não grava mais (atributo
	-- SalvarRecompensaNoStudio = true no Workspace pra testar o fluxo de propósito).
	if RunService:IsStudio() and workspace:GetAttribute("SalvarRecompensaNoStudio") ~= true then return end
	local data = playerRewards[player.UserId]
	if not data then return end
	-- ⚠️ CORRIGIDO: LobbyRewardsReceiver.legacy.luau (place Lobby) lê
	-- rewards.SavedAt pra decidir se a recompensa está "velha demais"
	-- (>24h) — mas esse campo nunca era escrito aqui, então TODA
	-- recompensa legítima calculava rewardsAge = os.time() - 0, um número
	-- gigante, e era mis-flagada como antiga (só um warn cosmético hoje,
	-- mas o campo devia existir de verdade).
	-- ⚠️ v123: carimbo FIXO da partida (antes era renovado a cada save — o save do
	-- PlayerRemoving, depois do teleporte, ganhava um SavedAt mais novo e escapava do
	-- "já reivindicada" do Lobby, podendo entregar a mesma partida de novo)
	data.SavedAt = data.SavedAt or os.time()
	local success, err = pcall(function()
		rewardsDataStore:SetAsync("Rewards_" .. player.UserId, data)
	end)
	if not success then
		warn("Erro ao salvar recompensas de " .. player.Name .. ": " .. tostring(err))
	end
end

local function showSummaries()
	for _, player in ipairs(Players:GetPlayers()) do
		local data = playerRewards[player.UserId]
		if data then
			Remotes.ShowMatchSummary:FireClient(player, data)
		end
	end
end

-- ⚠️ NOVO: PEDIDO — "na tela final do jogo ele diz que ganha uma certa
-- quantidade de dinheiro e no lobby você ganha uma quantidade bem
-- inferior a ela". A entrega de recompensa dependia só do DataStore
-- MatchRewards_V1 (esse server escreve com SetAsync, o Lobby lê minutos
-- "depois" com UpdateAsync) — DataStore entre servers DIFERENTES não tem
-- garantia de leitura-após-escrita imediata (é eventualmente consistente
-- de verdade só DENTRO do mesmo server); se o Lobby lesse rápido demais
-- depois do jogador entrar, podia pegar uma versão desatualizada (ou nada
-- ainda) só nesse caso batendo o "return nil"/dados velhos, sem nunca
-- corrigir depois (a chave já foi apagada por essa mesma leitura). O
-- MESMO problema afeta as missões (QuestManager lê rewards.Stats do MESMO
-- registro), então "só as de vencer partida funcionam" é o mesmo bug: só
-- MatchResult vinha certo quando os Stats detalhados (Gols/Dribles/etc)
-- ainda não tinham propagado.
--
-- Fix: manda a recompensa de cada jogador via TeleportData (mesma técnica
-- já usada por Matchmaker.legacy.luau pra levar Characters do Lobby PRO
-- Game) — viaja JUNTO com o teleporte, sem depender de nenhuma leitura de
-- DataStore de outro server, então chega 100% confiável e na hora. O
-- SetAsync em MatchRewards_V1 (saveRewards, já chamado acima) continua
-- existindo como rede de segurança (ex.: o jogador cair no meio do
-- teleporte e entrar no Lobby por outro caminho depois).
local function returnPlayersToLobby()
	local players = Players:GetPlayers()
	local rewardsPayload = {}
	for _, player in ipairs(players) do
		saveRewards(player)
		if playerRewards[player.UserId] and not salaPersonalizada then
			rewardsPayload[tostring(player.UserId)] = playerRewards[player.UserId]
		end
	end
	task.wait(Config.SUMMARY_DELAY_BEFORE_TELEPORT)

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions:SetTeleportData({
		MatchRewards = rewardsPayload,
		TutorialConcluido = modoTutorial or nil, -- ⚠️ v104
	})

	-- ⚠️ v104: tenta de novo se o teleporte falhar (antes, uma falha deixava
	-- todo mundo preso no server da partida já encerrada)
	for tentativa = 1, 4 do
		local restantes = {}
		for _, p in ipairs(players) do
			if p.Parent == Players then table.insert(restantes, p) end
		end
		if #restantes == 0 then return end
		local success, err = pcall(function()
			TeleportService:TeleportAsync(Config.LOBBY_PLACE_ID, restantes, teleportOptions)
		end)
		if success then return end
		warn(("Erro no teleporte para o Lobby (tentativa %d/4): %s"):format(tentativa, tostring(err)))
		task.wait(3)
	end
end

-- ===== FIM DE PARTIDA =====
-- ⚠️ v104 — PEDIDO: "sempre que acaba a partida no overtime, ela não encerra
-- definitivamente... faça o cara teleportar de volta pro lobby depois que
-- acabar toda a partida, tanto no overtime quanto fora". Cada etapa roda
-- protegida: um erro no MVP/resumo não pode mais impedir o teleporte.
local function endMatch()
	if matchEnded then return end
	matchEnded = true
	matchActive = false
	golDeOuroPendente = false
	pcall(playWhistle)

	local mvp
	local okMvp, errMvp = pcall(function() mvp = calculateMVP() end)
	if not okMvp then warn("⚠️ Fim de partida: erro no MVP: " .. tostring(errMvp)) end
	local okRes, errRes = pcall(applyMatchResult)
	if not okRes then warn("⚠️ Fim de partida: erro no resultado: " .. tostring(errRes)) end
	for _, data in pairs(playerRewards) do
		if modoTutorial then data.MatchResult = "tutorial" end
		if salaPersonalizada then
			data.SemRecompensa = true
			data.MoneyEarned = 0
			data.XPEarned = 0
		end
		-- ⚠️ v110: o nome do personagem (slot) quando veio do Lobby
		data.MVPNome = mvp and (mvp:GetAttribute("NomePersonagem") or mvp.DisplayName) or nil
		data.MVPUserId = mvp and mvp.UserId or nil
		data.SegundosAteLobby = Config.SUMMARY_DELAY_BEFORE_TELEPORT
	end
	local okSum, errSum = pcall(showSummaries)
	if not okSum then warn("⚠️ Fim de partida: erro no resumo: " .. tostring(errSum)) end
	returnPlayersToLobby()
end

_G.EndMatchNow = endMatch

-- ===== TIMER: 2 TEMPOS DE 4 MINUTOS =====
-- ⚠️ v33 — PEDIDO: "assim que acabar a visualização, não precisa daqueles
-- três segundos pra começar a partida. Já começa a partida instantaneamente
-- e já começa o apito."
-- Com Config.KICKOFF_COUNTDOWN = 0 o laço não roda e o apito sai na hora. O
-- FireAllClients com 0 continua existindo pra LIMPAR o "3, 2, 1" do HUD —
-- sem ele, o número da contagem anterior ficaria congelado na tela.
local function runKickoffCountdown()
	for i = Config.KICKOFF_COUNTDOWN, 1, -1 do
		Remotes.UpdateMatchState:FireAllClients(timeRemaining, score, i)
		task.wait(1)
	end
	Remotes.UpdateMatchState:FireAllClients(timeRemaining, score, 0)
	playWhistle()
end

-- Roda um tempo inteiro (4 minutos), com saída pro time indicado.
-- O time que NÃO deu a saída no 1º tempo dá a saída no 2º.
-- ⚠️ v52 — RELÓGIO "ESTICADO" (ver o comentário completo em
-- Config.HALF_DURATION / HALF_REAL_SECONDS).
-- PEDIDO: "cada rodada são 2 minutos, só que não são exatamente 2 minutos,
-- são uns 2 e meio" / "1 minuto exato, só que como se fosse 1 minuto e 21,
-- em formato de 1 minuto — só pra poder FINGIR que é."
--
-- `mostrar` é o que o placar conta; `real` é quanto aquilo dura de verdade.
-- Um segundo do relógio passa a durar real/mostrar segundos — então o
-- jogador vê um número redondo contando normalmente, enquanto o tempo de
-- jogo é o que a gente quiser (no caso da prorrogação, o da música).
local function runPeriod(mostrar, real)
	local passo = real / math.max(mostrar, 1)
	timeRemaining = mostrar
	Remotes.UpdateMatchState:FireAllClients(timeRemaining, score)
	-- ⚠️ v104: teto de tempo REAL — pausas (bola parada, replay de gol) não
	-- podem mais segurar o período pra sempre se alguma coisa esquecer de
	-- despausar. Folga generosa: o próprio tempo + 60% + 1 minuto.
	local limiteReal = os.clock() + real * 1.6 + 60

	while timeRemaining > 0 and matchActive do
		if os.clock() > limiteReal then
			warn(("⏱️ Período passou do teto de tempo real (%.0fs) — encerrando o período (pausado=%s)."):format(real * 1.6 + 60, tostring(matchPaused)))
			break
		end
		task.wait(passo)
		-- ⚠️ v113: a cena do Flow (10-15s) não come o tempo da partida
		-- ⚠️ v123 — PEDIDO: "o tempo vai parar durante as Hissatsus também". Qualquer
		-- cutscene (chute, defesa do goleiro, Flow) segura o relógio — todo mundo está
		-- congelado nela mesmo.
		local emCutscene = _G.HissatsuCutsceneActive ~= nil
		if not matchPaused and not emCutscene then
			timeRemaining -= 1
			Remotes.UpdateMatchState:FireAllClients(timeRemaining, score)
		elseif emCutscene then
			limiteReal += passo -- (o teto de segurança não conta o tempo parado na cutscene)
		end
	end
end

local function runHalf(halfNumber, kickoffTeamName)
	currentHalf = halfNumber
	timeRemaining = Config.HALF_DURATION
	performKickoff(kickoffTeamName)

	-- ⚠️ NOVO: PEDIDO — "a energia [de Pulso] só recarrega no segundo
	-- tempo, ela está recarregando passivamente, e isso não pode
	-- acontecer". A regeneração passiva por tempo foi removida (ver
	-- PulseController.legacy.luau) — o único jeito de reabastecer agora é
	-- AQUI, uma vez no início de CADA tempo (1º e 2º), nunca a cada gol
	-- (performKickoff também é chamado depois de cada gol, mas só aqui em
	-- runHalf é início de tempo de verdade).
	if _G.ResetPulseEnergy then _G.ResetPulseEnergy() end

	runPeriod(Config.HALF_DURATION, Config.HALF_REAL_SECONDS)
end

local function runHalftimeBreak()
	matchPaused = true
	if _G.SetDeadBallMode then _G.SetDeadBallMode(true) end

	for i = Config.HALFTIME_BREAK_DURATION, 1, -1 do
		-- reaproveita o campo "countdown" do UpdateMatchState pra mostrar
		-- a contagem do intervalo na mesma UI do timer, sem mexer no cliente
		Remotes.UpdateMatchState:FireAllClients(Config.HALF_DURATION, score, i)
		task.wait(1)
	end

	if _G.SetDeadBallMode then _G.SetDeadBallMode(false) end
	matchPaused = false
end

-- ⚠️ v49 — PRORROGAÇÃO.
-- PEDIDO: "quando der o overtime, o jogo estiver EMPATADO, os caras vão ter
-- aquele 1 minuto, só que vai ser 1 minuto mais lento: vai ser 1 minuto a
-- partir da DURAÇÃO DA MÚSICA que tiver aí. O overtime vai ser definido a
-- partir da duração dessa música."
--
-- Então a duração não é um número escolhido: é medida do próprio áudio, do
-- ponto em que ele começa (OVERTIME_MUSIC_START_SECONDS = 50) até onde ele
-- é cortado (duração - MUSIC_TAIL_CUT_SECONDS). Trocar a música troca o
-- tempo junto, sem mexer em nada aqui.
--
-- A medição roda no SERVIDOR porque é o servidor que manda no relógio. Um
-- Sound só informa TimeLength depois de carregar, então isso é feito uma
-- vez, cedo (no início da partida), com folga de sobra até o fim do segundo
-- tempo — mesma técnica que o apito já usa.
local overtimeSeconds = nil

local function medirDuracaoDaProrrogacao()
	local id = Config.OVERTIME_MUSIC_ID
	if typeof(id) ~= "string" or id == "" then
		overtimeSeconds = Config.OVERTIME_FALLBACK_SECONDS
		return
	end

	local medidor = Instance.new("Sound")
	medidor.Name = "OvertimeMusicProbe"
	medidor.SoundId = id
	medidor.Volume = 0 -- só pra ler TimeLength; nunca toca
	medidor.Parent = SoundService

	local esperou = 0
	while not medidor.IsLoaded and esperou < 10 do
		task.wait(0.2)
		esperou += 0.2
	end

	local total = medidor.IsLoaded and medidor.TimeLength or 0
	medidor:Destroy()

	if total <= 0 then
		overtimeSeconds = Config.OVERTIME_FALLBACK_SECONDS
		warn(string.format(
			"⏱️ [Prorrogação] não consegui ler a duração da música (%s) — usando a rede de segurança de %ds. Se isso repetir, confira se o áudio está aprovado e liberado pra este jogo.",
			id, overtimeSeconds))
		return
	end

	local inicio = Config.OVERTIME_MUSIC_START_SECONDS or 0
	local corte = Config.MUSIC_TAIL_CUT_SECONDS or 1.5
	overtimeSeconds = math.max(math.floor(total - corte - inicio), 10)

	print(string.format(
		"⏱️ [Prorrogação] música tem %.1fs; tocando de %ds até %.1fs -> prorrogação de %ds.",
		total, inicio, total - corte, overtimeSeconds))
end

local function runOvertime(kickoffTeamName)
	currentHalf = 3

	-- Avisa os clientes ANTES do kickoff: é aqui que a música em andamento
	-- desvanece e a da prorrogação entra (ver MusicClient). É o único
	-- momento em que uma faixa é interrompida no meio — pedido explícito.
	Remotes.OvertimeStarted:FireAllClients()

	playWhistle()
	performKickoff(kickoffTeamName)
	if _G.ResetPulseEnergy then _G.ResetPulseEnergy() end

	-- O placar mostra 1:00 (OVERTIME_DISPLAY_SECONDS) contando normalmente,
	-- mas esse "minuto" é espalhado pelos segundos REAIS da música — é o
	-- "fingir que é 1 minuto" do pedido.
	runPeriod(
		Config.OVERTIME_DISPLAY_SECONDS,
		overtimeSeconds or Config.OVERTIME_FALLBACK_SECONDS
	)
end

-- Compara pelos times de verdade (Config.TEAM_NAMES) em vez de iterar
-- `score` com pairs(): se por qualquer motivo a tabela tiver uma chave a
-- mais ou a menos, pairs() daria um empate/desempate falso. Aqui a
-- pergunta é literal: os dois times têm o mesmo número de gols?
local function estaEmpatado()
	local a = score[Config.TEAM_NAMES[1]] or 0
	local b = score[Config.TEAM_NAMES[2]] or 0
	return a == b
end

local function startMatchTimer()
	setupGoalDetection()
	-- ⚠️ v113: cada jogador tem 1 Flow por partida — libera de novo aqui
	if _G.ResetarFlowsDaPartida then _G.ResetarFlowsDaPartida() end

	-- ⚠️ v49: mede a duração da prorrogação agora, em paralelo — leva alguns
	-- segundos pro áudio carregar, e só vai ser usada depois de dois tempos
	-- inteiros. task.spawn pra não segurar o início da partida.
	task.spawn(medirDuracaoDaProrrogacao)

	-- ⚠️ NOVO: CUTSCENE DE ENTRADA — pedido: "quero incluir uma cutscene de
	-- entrada, os dois times passam pelo túnel e depois corta pra todo
	-- mundo dentro de campo". Roda ANTES da contagem de kickoff (o jogador
	-- vê a entrada primeiro, depois "3, 2, 1"). Toda a lógica visual
	-- (esconder os personagens de verdade, andar os bonecos, câmera) é
	-- 100% client-side (ver EntranceCutsceneClient.local.luau) — aqui só
	-- montamos o roster (quem está em cada time + pra onde cada um vai) e
	-- esperamos a duração configurada antes de seguir pro resto da
	-- sequência normal de início de partida.
	if _G.PlayEntranceCutscene then
		_G.PlayEntranceCutscene()
	end

	runKickoffCountdown()
	matchActive = true

	runHalf(1, Config.TEAM_NAMES[1])

	if matchActive then
		runHalftimeBreak()
		playWhistle()
		runHalf(2, Config.TEAM_NAMES[2])
	end

	-- ⚠️ v49: empatado no fim do segundo tempo -> PRORROGAÇÃO, com a duração
	-- vinda da própria música dela (ver medirDuracaoDaProrrogacao).
	if matchActive and estaEmpatado() then
		playWhistle()
		runHalftimeBreak()
		runOvertime(Config.TEAM_NAMES[1])
	end

	-- ⚠️ v104: SEMPRE encerra (antes só se matchActive — se algo o desligasse
	-- no meio, a partida "acabava" sem resumo nem teleporte). Se um golden
	-- goal está no replay, quem encerra é ele.
	while golDeOuroPendente and not matchEnded do task.wait(0.5) end
	endMatch()
end

-- FIX: server que chegou via matchmaking (place Lobby) é um Reserved
-- Server que SÓ recebe exatamente os jogadores daquela partida — o
-- TeleportData de qualquer um deles carrega TotalPlayers (10 pro 5v5,
-- 14 pro 7v7, ver Matchmaker.lua no place Lobby). Sem TeleportData
-- (testando sozinho no Studio, ou entrando direto neste place sem
-- passar pelo Lobby), cai de volta no Config.MIN_PLAYERS_TO_START de
-- sempre — assim o fluxo antigo de teste continua funcionando igual.
local function getExpectedPlayerCount()
	for _, player in ipairs(Players:GetPlayers()) do
		local teleportData = player:GetJoinData().TeleportData
		if typeof(teleportData) == "table" and typeof(teleportData.TotalPlayers) == "number" then
			return teleportData.TotalPlayers
		end
	end
	return salaPersonalizada and 1 or Config.MIN_PLAYERS_TO_START -- ⚠️ v104: sala personalizada/tutorial começa sozinho
end

-- FIX: "entramos 3 e o jogo não deu start" — acontecia quando o
-- TeleportData de algum jogador carregava um TotalPlayers de modo
-- fechado (ex.: 10 pro 5v5) mas menos gente de verdade entrou nesse
-- Reserved Server (timeout da fila, alguém desconectou no teleporte,
-- etc.) — o loop ficava esperando pra sempre um número que nunca ia
-- bater. Agora, uma vez que o mínimo ABSOLUTO (Config.MIN_PLAYERS_TO_
-- START) é alcançado, um cronômetro de segurança (FALLBACK_WAIT_
-- TIMEOUT) começa a contar: se o total esperado do modo não bater até
-- lá, a partida começa mesmo assim com quem está presente, em vez de
-- travar o timer pra sempre.
local FALLBACK_WAIT_TIMEOUT = 20 -- segundos esperando o total do modo antes de começar só com o mínimo

local function waitForPlayersAndStart()
	local lastPrintedCount = -1
	local expectedCount = Config.MIN_PLAYERS_TO_START
	local minReachedAt = nil

	while true do
		local currentCount = #Players:GetPlayers()
		-- ⚠️ v104: sala personalizada começa até com 1 jogador (você sozinho)
		local minimo = salaPersonalizada and 1 or Config.MIN_PLAYERS_TO_START
		expectedCount = math.max(getExpectedPlayerCount(), minimo)
		if currentCount >= expectedCount then break end

		if currentCount >= minimo then
			minReachedAt = minReachedAt or tick()
			if tick() - minReachedAt >= FALLBACK_WAIT_TIMEOUT then
				print(("⏱️ MatchController: %d/%d esperado, mas o mínimo (%d) já foi atingido há %ds — começando a partida assim mesmo."):format(
					currentCount, expectedCount, Config.MIN_PLAYERS_TO_START, FALLBACK_WAIT_TIMEOUT))
				break
			end
		else
			minReachedAt = nil
		end

		if currentCount ~= lastPrintedCount then
			print(("⏳ MatchController esperando jogadores: %d/%d. Timer e gols só começam a funcionar depois disso."):format(currentCount, expectedCount))
			lastPrintedCount = currentCount
		end
		task.wait(1)
	end

	-- ⚠️ v104: tutorial — gols valendo, sem relógio, sem cutscene de entrada
	if modoTutorial then
		print("🎓 Modo tutorial — sem relógio nem cutscene de entrada.")
		setupGoalDetection()
		matchActive = true
		matchPaused = false
		if _G.SetDeadBallMode then _G.SetDeadBallMode(false) end
		if _G.ResetPulseEnergy then _G.ResetPulseEnergy() end
		local limite = os.clock() + 10
		while not _G.TutorialComecar and os.clock() < limite do task.wait(0.2) end
		if _G.TutorialComecar then
			_G.TutorialComecar()
		else
			warn("🎓 TutorialServer não carregou — encerrando.")
			endMatch()
		end
		return
	end

	-- ⚠️ v112: era 3s — PEDIDO: "pra não ter atraso, pra não ter enrolação"
	print("✅ Jogadores suficientes — partida começando.")
	task.wait(0.5)
	startMatchTimer()
end

Players.PlayerRemoving:Connect(function(player)
	saveRewards(player)
	-- Segue usando Config.MIN_PLAYERS_TO_START (não o TotalPlayers do
	-- modo) só como piso absoluto de "não faz sentido continuar" — não
	-- é o alvo real de um 5v5/7v7. Refinar isso pra encerrar quando um
	-- time fica esvaziado demais (ex: 7v7 virar 2v7) fica pra depois.
	if matchActive and #Players:GetPlayers() - 1 < Config.MIN_PLAYERS_TO_START then
		endMatch()
	end
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		saveRewards(player)
	end
	task.wait(1)
end)

task.spawn(waitForPlayersAndStart)

print("✅ MatchController carregado.")