--[[
	Matchmaker (Script)
	LOCAL: ServerScriptService (place Lobby)

	Roda em TODO servidor de Lobby ao mesmo tempo. Periodicamente:
	1) puxa grupos novos da MemoryStoreQueue compartilhada de cada modo
	   (removendo cada item individualmente assim que lê — ver nota
	   abaixo sobre por que não dá pra usar RemoveAsync em lote aqui);
	2) tenta fechar uma partida (Config.MODES[modo].TotalPlayers) a
	   partir do que já tem guardado localmente (pendingPool);
	3) se conseguir, reserva um server no place Game e avisa TODOS os
	   Lobbies via MessagingService — porque os jogadores dessa partida
	   podem estar espalhados em VÁRIOS servers de Lobby diferentes, e um
	   Player só existe de verdade no server onde a pessoa está de fato.

	NOTA sobre RemoveAsync em lote: ReadAsync(count, ...) devolve um ID
	ÚNICO que cobre TODOS os itens lidos naquela chamada — RemoveAsync
	desse ID remove o lote inteiro de uma vez, não item por item. Como
	decidir "quais grupos entram nesta partida" é um problema de
	combinação (grupos de tamanhos variados somando um total exato), ler
	em lote e depois descartar o lote inteiro perderia gente que não
	coube na combinação escolhida. Por isso este script lê UM item por
	vez (ReadAsync(1, ...)) e remove IMEDIATAMENTE assim que lê — o item
	já fica "comprometido" com este server a partir daí, guardado em
	memória local (pendingPool) até caber numa partida.

	TRADE-OFF conhecido: se ESTE server de Lobby cair enquanto segura
	grupos no pendingPool (já removidos da fila compartilhada, ainda não
	usados em partida nenhuma), esses jogadores somem do matchmaking até
	entrarem na fila de novo. Config.GROUP_STUCK_REQUEUE_AFTER limita
	quanto tempo um grupo fica "preso" aqui antes de voltar sozinho pra
	fila compartilhada — o pior caso é esse atraso, não perda permanente,
	a menos que o server caia bem no meio da janela.

	OUTRO TRADE-OFF: a divisão de time exige achar DOIS subconjuntos de
	grupos que somem exatamente PerTeam cada um (ver tryCloseMatch). Isso
	nunca quebra um grupo ao meio nem força partida desequilibrada, mas
	significa que uma combinação de tamanhos "impossível de dividir ao
	meio" (ex.: grupos de 3+3+4 pro 5v5) fica esperando o pool mudar em
	vez de fechar torto. Normal ter gente esperando um pouco mais por
	causa disso, principalmente com grupos grandes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

local queues = {}
for modeId in pairs(Config.MODES) do
	queues[modeId] = MemoryStoreService:GetQueue(Config.QUEUE_NAME_PREFIX .. modeId, Config.QUEUE_INVISIBILITY_TIMEOUT)
end

-- pendingPool[modeId] = { { LeaderUserId=, Members={UserId,...}, Size=, CapturedAt= }, ... }
local pendingPool = {}
for modeId in pairs(Config.MODES) do
	pendingPool[modeId] = {}
end

-- ===== SUBSET-SUM: acha um subconjunto de grupos que soma EXATAMENTE targetSum =====
-- DP 0/1 knapsack de existência, com reconstrução. n e targetSum são
-- sempre pequenos aqui (targetSum <= 7, grupos <= MAX_PARTY_SIZE de 5),
-- não precisa de nada mais esperto que isso.
-- ⚠️ v104: `precisaGK` — nil = tanto faz; true = o time precisa ter pelo
-- menos 1 goleiro (grupo com GK > 0); false = nenhum goleiro no time (o GK
-- bot completa). Estado do DP = (soma, tem goleiro?).
local function findExactSubset(groups, targetSum, precisaGK)
	local function chave(s, g) return s * 2 + g end
	local alcancavel = { [0] = true }
	local veioDe = {} -- [chave] = { anterior = chave, idx = grupo }

	for idx = 1, #groups do
		local size = groups[idx].Size
		local gk = ((groups[idx].GK or 0) > 0) and 1 or 0
		if not (precisaGK == false and gk == 1) then
			local atuais = {}
			for k in pairs(alcancavel) do table.insert(atuais, k) end
			for _, k in ipairs(atuais) do
				local s, g = k // 2, k % 2
				local ns = s + size
				if ns <= targetSum then
					local nk = chave(ns, math.max(g, gk))
					if not alcancavel[nk] then
						alcancavel[nk] = true
						veioDe[nk] = { anterior = k, idx = idx }
					end
				end
			end
		end
	end

	local alvo
	if precisaGK == true then alvo = chave(targetSum, 1)
	elseif precisaGK == false then alvo = chave(targetSum, 0)
	else alvo = alcancavel[chave(targetSum, 1)] and chave(targetSum, 1) or chave(targetSum, 0) end
	if not alcancavel[alvo] then return nil end

	local chosenIndices = {}
	local k = alvo
	while k ~= 0 do
		local passo = veioDe[k]
		table.insert(chosenIndices, passo.idx)
		k = passo.anterior
	end
	return chosenIndices
end

-- ⚠️ v3.4: PREFERÊNCIA DE MATCHMAKING (pedido do usuário) — primeiro
-- REGIÃO (proxy de ping parecido, ver regionOf em MatchmakingQueue.
-- legacy.luau), depois NÍVEL (Wins: "quem tiver 10 vitórias vai pegar
-- alguém com 15 bem mais fácil que alguém com 1000").
--
-- Não é um sistema de MMR com faixas alargando com o tempo de espera —
-- é mais simples que isso: tenta fechar o time usando SÓ grupos da MESMA
-- região primeiro (e, dentro dela, prefere combinar os de Wins mais
-- parecido, ordenando por Wins antes do subset-sum, o que faz o DP achar
-- primeiro as combinações entre grupos vizinhos em nível); só se
-- NENHUMA região sozinha conseguir fechar o time é que cai pro pool
-- inteiro (todas as regiões misturadas, ainda ordenado por Wins) — assim
-- a fila NUNCA fica travada esperando uma condição perfeita, só prefere
-- ela quando dá.
local function findPreferredSubset(pool, targetSum, precisaGK, soMesmaRegiao)
	local byRegion = {}
	for idx, group in ipairs(pool) do
		local list = byRegion[group.Region or "UNKNOWN"]
		if not list then
			list = {}
			byRegion[group.Region or "UNKNOWN"] = list
		end
		table.insert(list, idx)
	end

	local function tryIndices(indices)
		table.sort(indices, function(a, b) return pool[a].AvgWins < pool[b].AvgWins end)
		local subPool = {}
		for _, idx in ipairs(indices) do
			table.insert(subPool, pool[idx])
		end
		local subIndices = findExactSubset(subPool, targetSum, precisaGK)
		if not subIndices then return nil end
		local mapped = {}
		for _, subIdx in ipairs(subIndices) do
			table.insert(mapped, indices[subIdx])
		end
		return mapped
	end

	-- 1) cada região sozinha primeiro (prioridade: região > nível)
	for _, indices in pairs(byRegion) do
		local found = tryIndices(indices)
		if found then return found end
	end

	-- 2) ninguém fechou sozinho: cai pro pool inteiro, misturando região,
	-- ainda ordenado por Wins (mantém a preferência de nível mesmo sem a
	-- de região). ⚠️ v104: só depois de MATCH_REGION_STRICT_SECONDS de
	-- espera — antes disso, ping bom (mesma região) é obrigatório.
	if soMesmaRegiao then return nil end
	local allIndices = {}
	for idx in ipairs(pool) do
		table.insert(allIndices, idx)
	end
	return tryIndices(allIndices)
end

-- ⚠️ v11: tempo (segundos) que o grupo MAIS ANTIGO de um pool já está
-- esperando — usado pra decidir QUANDO relaxar o tamanho do time exigido
-- (ver Config.MATCH_FULL_WAIT_SECONDS/MATCH_LAST_RESORT_WAIT_SECONDS em
-- LobbyConfig.lua e tryCloseMatch/tryCloseLastResort abaixo).
local function oldestWaitSeconds(pool)
	local oldest = nil
	for _, group in ipairs(pool) do
		if not oldest or group.CapturedAt < oldest then
			oldest = group.CapturedAt
		end
	end
	if not oldest then return 0 end
	return tick() - oldest
end

-- Tenta findPreferredSubset com uma LISTA de somas-alvo, em ordem de
-- preferência (a primeira que fechar vence) — em vez de só aceitar uma
-- soma fixa. É isso que permite cada time fechar com um tamanho
-- DIFERENTE do outro (ex.: 7v6), já que os dois times chamam isto de
-- forma independente em tryCloseMatch.
local function findPreferredSubsetAnyTarget(pool, targetSums, precisaGK, soMesmaRegiao)
	for _, targetSum in ipairs(targetSums) do
		local found = findPreferredSubset(pool, targetSum, precisaGK, soMesmaRegiao)
		if found then return found end
	end
	return nil
end

local function removeIndices(list, indices)
	local indexSet = {}
	for _, idx in ipairs(indices) do indexSet[idx] = true end

	local kept, removed = {}, {}
	for idx, item in ipairs(list) do
		if indexSet[idx] then
			table.insert(removed, item)
		else
			table.insert(kept, item)
		end
	end
	return kept, removed
end

-- ===== CANCELAMENTO DE VERDADE =====
-- ⚠️ v71 — PEDIDO: "você só consegue puxar partida se der o play, cancelar
-- e der play novamente, como se precisasse sair e entrar da fila duas
-- vezes".
--
-- CAUSA: LeaveQueue (MatchmakingQueue.legacy.luau) só avisava o CLIENTE
-- que saiu — o grupo, uma vez puxado da fila compartilhada pra dentro de
-- pendingPool (aqui, em pullNewGroups), NUNCA era removido de pendingPool
-- ao cancelar. Ele ficava vivo aqui, "fantasma", até casar com uma
-- partida ou expirar sozinho (Config.GROUP_STUCK_REQUEUE_AFTER, 90s).
--
-- Entrar de novo criava uma SEGUNDA entrada pro mesmo líder — e, na Sala
-- Livre, duas entradas (mesmo repetidas do mesmo jogador) bastam pra
-- tryCloseFreeRoom balancear "os dois times" e fechar. Ou seja: o
-- "cancelar e entrar de nervo" não consertava nada — só criava o segundo
-- fantasma que mascarava o bug de verdade (ver tryCloseFreeRoom abaixo
-- pro segundo bug, este aqui é so metade do problema).
_G.RemovePendingGroup = function(modeId, leaderUserId)
	local pool = pendingPool[modeId]
	if not pool then return end
	for i, group in ipairs(pool) do
		if group.LeaderUserId == leaderUserId then
			table.remove(pool, i)
			return
		end
	end
end

-- ===== PUXAR NOVOS GRUPOS DA FILA COMPARTILHADA =====
local function pullNewGroups(modeId)
	local queue = queues[modeId]
	local pulled = 0

	while pulled < Config.QUEUE_READS_PER_CYCLE do
		local ok, items, readId = pcall(function()
			return queue:ReadAsync(1, false, 0)
		end)
		if not ok or not items or #items == 0 then break end

		local item = items[1]
		pcall(function() queue:RemoveAsync(readId) end)
		pulled += 1

		if typeof(item) == "table" and typeof(item.Members) == "table" then
			table.insert(pendingPool[modeId], {
				LeaderUserId = item.LeaderUserId,
				Members = item.Members,
				Size = #item.Members,
				CapturedAt = tick(),
				-- ⚠️ v3.4: carregados desde MatchmakingQueue.legacy.luau
				-- (buildQueueItem) — ver tryCloseMatch/tryCloseFreeRoom pra
				-- como isso vira preferência na hora de fechar os times.
				Region = typeof(item.Region) == "string" and item.Region or "UNKNOWN",
				AvgWins = typeof(item.AvgWins) == "number" and item.AvgWins or 0,
				GK = typeof(item.GK) == "number" and item.GK or 0, -- ⚠️ v104
			})
		end
	end
end

-- ===== DEVOLVER GRUPO PRESO HÁ MUITO TEMPO PRA FILA COMPARTILHADA =====
local function requeueStuckGroups(modeId)
	local pool = pendingPool[modeId]
	local stillWaiting = {}

	for _, group in ipairs(pool) do
		if tick() - group.CapturedAt >= Config.GROUP_STUCK_REQUEUE_AFTER then
			local ok = pcall(function()
				queues[modeId]:AddAsync({
					LeaderUserId = group.LeaderUserId,
					Members = group.Members,
					QueuedAt = os.time(),
					Region = group.Region, -- ⚠️ v3.4: preserva a preferência ao devolver pra fila (senão o grupo "esquece" a região/nível dele)
					AvgWins = group.AvgWins,
						GK = group.GK, -- ⚠️ v104
				}, Config.QUEUE_ITEM_EXPIRATION)
			end)
			if not ok then
				table.insert(stillWaiting, group) -- falhou ao devolver, mantém aqui e tenta de novo depois
			end
		else
			table.insert(stillWaiting, group)
		end
	end

	pendingPool[modeId] = stillWaiting
end

-- ===== TENTAR FECHAR UMA PARTIDA =====
local function tryCloseMatch(modeId)
	local mode = Config.MODES[modeId]
	local pool = pendingPool[modeId]

	-- ⚠️ v11 — PEDIDO: "já que o GK não é obrigatório, o 7v7 pode se
	-- tornar 7v6, ou 6v6...". Nos primeiros Config.MATCH_FULL_WAIT_SECONDS
	-- só aceita o time CHEIO (comportamento de sempre); depois disso,
	-- aceita também 1 a menos — cada time busca essa lista de forma
	-- INDEPENDENTE (ver findPreferredSubsetAnyTarget), o que já cobre
	-- tanto 7v6 (torto) quanto 6v6 (parelho) sem código separado pra cada
	-- caso.
	local targetSums = { mode.PerTeam }
	if mode.PerTeam - 1 >= Config.MATCH_LAST_RESORT_MIN_PER_TEAM
		and oldestWaitSeconds(pool) >= Config.MATCH_FULL_WAIT_SECONDS then
		table.insert(targetSums, mode.PerTeam - 1)
	end

	-- ⚠️ v104 — GOLEIROS + PING. Tenta, em ordem: os dois times COM goleiro
	-- humano; depois (menos no 7v7, que obriga GK) os dois SEM goleiro. Nunca
	-- um com e outro sem ("quatro na linha e um a mais no gol"). E, até
	-- MATCH_REGION_STRICT_SECONDS de espera, só com gente da mesma região.
	local espera = oldestWaitSeconds(pool)
	local soMesmaRegiao = espera < (Config.MATCH_REGION_STRICT_SECONDS or 0)
	local opcoesGK = { true }
	if not (Config.MODES_GK_OBRIGATORIO and Config.MODES_GK_OBRIGATORIO[modeId]) then
		table.insert(opcoesGK, false)
	end

	local teamAIndices, teamBIndices, remaining, teamAGroups
	for _, precisaGK in ipairs(opcoesGK) do
		local a = findPreferredSubsetAnyTarget(pool, targetSums, precisaGK, soMesmaRegiao)
		if a then
			local resto, grupoA = removeIndices(pool, a)
			local b = findPreferredSubsetAnyTarget(resto, targetSums, precisaGK, soMesmaRegiao)
			if b then
				teamAIndices, teamBIndices, remaining, teamAGroups = a, b, resto, grupoA
				break
			end
		end
	end
	if not teamBIndices then
		-- Não achou uma divisão justa com o que tem agora — não força
		-- partida desequilibrada nem quebra grupo. Espera o pool mudar
		-- (mais gente entrando) e tenta de novo no próximo ciclo (ou cai
		-- pro último recurso em tryCloseLastResort, depois de esperar
		-- ainda mais).
		return
	end

	local teamBRemaining, teamBGroups = removeIndices(remaining, teamBIndices)

	-- Só confirma a remoção definitiva do pool agora, com as duas
	-- equipes fechadas com sucesso.
	pendingPool[modeId] = teamBRemaining

	local assignments = {} -- [tostring(UserId)] = teamName
	local allGroups = {}
	local actualTotalPlayers = 0
	for _, group in ipairs(teamAGroups) do
		table.insert(allGroups, group)
		actualTotalPlayers += group.Size
		for _, userId in ipairs(group.Members) do
			assignments[tostring(userId)] = Config.TEAM_NAMES[1]
		end
	end
	for _, group in ipairs(teamBGroups) do
		table.insert(allGroups, group)
		actualTotalPlayers += group.Size
		for _, userId in ipairs(group.Members) do
			assignments[tostring(userId)] = Config.TEAM_NAMES[2]
		end
	end

	local reserveOk, accessCode = pcall(function()
		return TeleportService:ReserveServerAsync(Config.GAME_PLACE_ID)
	end)

	if not reserveOk or not accessCode then
		warn("Matchmaker: falha ao reservar server pro modo " .. modeId .. ": " .. tostring(accessCode))
		-- Devolve todo mundo pra fila compartilhada, ninguém fica de fora.
		for _, group in ipairs(allGroups) do
			pcall(function()
				queues[modeId]:AddAsync({
					LeaderUserId = group.LeaderUserId,
					Members = group.Members,
					QueuedAt = os.time(),
					Region = group.Region, -- ⚠️ v3.4: preserva a preferência ao devolver pra fila (senão o grupo "esquece" a região/nível dele)
					AvgWins = group.AvgWins,
						GK = group.GK, -- ⚠️ v104
				}, Config.QUEUE_ITEM_EXPIRATION)
			end)
		end
		return
	end

	local payload = {
		MatchId = HttpService:GenerateGUID(false),
		ModeId = modeId,
		-- ⚠️ v11 FIX: era mode.TotalPlayers (fixo, ex.: 14 pro 7v7) — agora
		-- que o time pode fechar menor que o nominal (7v6, 6v6...), mandar
		-- o valor fixo faria o MatchController (place Game) esperar pra
		-- sempre por um jogador que nunca vai chegar. Mesma lógica que já
		-- valia pra Sala Livre (ver tryCloseFreeRoom logo abaixo).
		TotalPlayers = actualTotalPlayers,
		AccessCode = accessCode,
		Assignments = assignments,
	}

	local publishOk, publishErr = pcall(function()
		MessagingService:PublishAsync(Config.MATCH_FOUND_TOPIC, payload)
	end)
	if not publishOk then
		warn("Matchmaker: falha ao avisar os Lobbies da partida fechada: " .. tostring(publishErr))
	end
end

-- ===== FECHAR PARTIDA NO ÚLTIMO RECURSO (⚠️ v11) =====
-- PEDIDO: "se demorar muito e nenhum GK entrar, puxe uma partida 2v2 ou
-- 2v3 mesmo." Só roda depois que o grupo mais antigo do pool já esperou
-- Config.MATCH_LAST_RESORT_WAIT_SECONDS — nesse ponto, tryCloseMatch já
-- teve chance de sobra de fechar CHEIO ou com só 1 a menos por time (ver
-- tryCloseMatch acima) e não conseguiu. Aqui a exigência de "os dois
-- times do mesmo tamanho-alvo" cai de vez: distribui greedy (mesmo
-- espírito de tryCloseFreeRoom), cada grupo inteiro pro time com menos
-- gente, sem estourar mode.PerTeam — pode fechar torto (2v3), contanto
-- que os dois lados batam pelo menos Config.MATCH_LAST_RESORT_MIN_PER_TEAM.
local function tryCloseLastResort(modeId)
	local mode = Config.MODES[modeId]
	local pool = pendingPool[modeId]
	if #pool == 0 then return end
	if oldestWaitSeconds(pool) < Config.MATCH_LAST_RESORT_WAIT_SECONDS then return end

	local totalPlayers = 0
	for _, group in ipairs(pool) do totalPlayers += group.Size end
	if totalPlayers < Config.MATCH_LAST_RESORT_MIN_PER_TEAM * 2 then return end -- nem dá pra fazer os dois lados baterem o mínimo

	local ordemEmbaralhada = {}
	for _, group in ipairs(pool) do table.insert(ordemEmbaralhada, group) end
	for i = #ordemEmbaralhada, 2, -1 do
		local j = math.random(i)
		ordemEmbaralhada[i], ordemEmbaralhada[j] = ordemEmbaralhada[j], ordemEmbaralhada[i]
	end
	-- Maiores grupos primeiro — mesmo motivo do tryCloseFreeRoom (deixa o
	-- balanceamento do resto mais preciso do que sobrar um grupo grande
	-- pra um lado só no final).
	table.sort(ordemEmbaralhada, function(a, b) return a.Size > b.Size end)

	local teamSizeOf = {}
	for _, teamName in ipairs(Config.TEAM_NAMES) do teamSizeOf[teamName] = 0 end

	local assignments = {}
	local usedGroups = {}
	for _, group in ipairs(ordemEmbaralhada) do
		-- só considera times que ainda CABEM esse grupo inteiro sem passar
		-- de mode.PerTeam (nunca estica o time além do modo escolhido,
		-- só encolhe) — dentre os que cabem, escolhe o(s) com menos gente.
		local melhorTimes, menorTamanho = {}, math.huge
		for _, teamName in ipairs(Config.TEAM_NAMES) do
			local tamanho = teamSizeOf[teamName]
			if tamanho + group.Size <= mode.PerTeam then
				if tamanho < menorTamanho then
					menorTamanho = tamanho
					melhorTimes = { teamName }
				elseif tamanho == menorTamanho then
					table.insert(melhorTimes, teamName)
				end
			end
		end

		if #melhorTimes > 0 then
			local teamName = melhorTimes[math.random(#melhorTimes)]
			teamSizeOf[teamName] += group.Size
			usedGroups[group] = teamName
			for _, userId in ipairs(group.Members) do
				assignments[tostring(userId)] = teamName
			end
		end
		-- se não coube em nenhum time (#melhorTimes == 0), o grupo fica de
		-- fora dessa leva — continua no pool, tenta de novo no próximo ciclo.
	end

	-- Só fecha se os DOIS lados baterem o mínimo de verdade — desbalanceado
	-- tudo bem (pedido explícito), vazio ou 1 sozinho não.
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if teamSizeOf[teamName] < Config.MATCH_LAST_RESORT_MIN_PER_TEAM then return end
	end

	local allGroups, actualTotalPlayers = {}, 0
	local stillPending = {}
	for _, group in ipairs(pool) do
		if usedGroups[group] then
			table.insert(allGroups, group)
			actualTotalPlayers += group.Size
		else
			table.insert(stillPending, group) -- não coube nessa leva (cap de mode.PerTeam) — continua esperando
		end
	end
	pendingPool[modeId] = stillPending

	local reserveOk, accessCode = pcall(function()
		return TeleportService:ReserveServerAsync(Config.GAME_PLACE_ID)
	end)

	if not reserveOk or not accessCode then
		warn("Matchmaker: falha ao reservar server pro último recurso do modo " .. modeId .. ": " .. tostring(accessCode))
		for _, group in ipairs(allGroups) do
			pcall(function()
				queues[modeId]:AddAsync({
					LeaderUserId = group.LeaderUserId,
					Members = group.Members,
					QueuedAt = os.time(),
					Region = group.Region,
					AvgWins = group.AvgWins,
						GK = group.GK, -- ⚠️ v104
				}, Config.QUEUE_ITEM_EXPIRATION)
			end)
		end
		return
	end

	local payload = {
		MatchId = HttpService:GenerateGUID(false),
		ModeId = modeId,
		TotalPlayers = actualTotalPlayers, -- real, não mode.TotalPlayers — ver mesmo comentário em tryCloseMatch
		AccessCode = accessCode,
		Assignments = assignments,
	}

	local publishOk, publishErr = pcall(function()
		MessagingService:PublishAsync(Config.MATCH_FOUND_TOPIC, payload)
	end)
	if not publishOk then
		warn("Matchmaker: falha ao avisar os Lobbies da partida (último recurso) fechada: " .. tostring(publishErr))
	end
end

-- ===== FECHAR SALA LIVRE (FREE ROOM) =====
-- Ao contrário do tryCloseMatch (5v5/7v7), aqui NÃO existe subset-sum:
-- fecha assim que a soma de jogadores bater mode.MinPlayers, sem esperar
-- completar time algum. Grupos inteiros (amigos que entraram juntos, ou
-- um TIME FECHADO) ficam sempre no mesmo time — a distribuição entre os
-- dois times é embaralhada e balanceada por tamanho a cada fechamento
-- (ver comentário dentro da função), e só fecha se os DOIS times
-- ficarem com gente.
local function tryCloseFreeRoom(modeId)
	local mode = Config.MODES[modeId]
	local pool = pendingPool[modeId]

	local totalPlayers = 0
	for _, group in ipairs(pool) do
		totalPlayers += group.Size
	end
	if totalPlayers < mode.MinPlayers or totalPlayers == 0 then return end

	-- ⚠️ FIX (pedido: "o time não é aleatorizado quando a partida inicia, o
	-- time precisa estar dividido"): o jeito antigo sempre começava
	-- alternando do Time 1 (Azul) na ordem de CHEGADA na pool (FIFO), sem
	-- sorteio nenhum — então com número ímpar de grupos o mesmo time
	-- sempre "sobrava" com mais gente, e no pior caso (ex.: um TIME
	-- FECHADO inteiro de amigos jogando 3v3 dentro da Sala Livre, sozinho
	-- na pool no momento em que MinPlayers bate) a sala inteira fechava
	-- com TODO MUNDO no mesmo time e o adversário vazio. Agora:
	--   1. embaralha a ORDEM dos grupos a cada fechamento (aleatoriza
	--      quem "decide" primeiro, em vez de sempre favorecer quem
	--      chegou antes);
	--   2. distribui por BALANCEAMENTO GULOSO — cada grupo inteiro
	--      (nunca quebrado: é isso que mantém um TIME FECHADO junto no
	--      mesmo lado) vai pro time com MENOS jogadores no momento;
	--      empate é resolvido por sorteio, não sempre o mesmo time;
	--   3. só fecha a sala se os DOIS times ficarem com gente — se sobrar
	--      um time vazio (só existe 1 grupo grande na pool até agora, por
	--      exemplo), espera mais gente entrar em vez de começar sem
	--      adversário.
	local ordemEmbaralhada = {}
	for _, group in ipairs(pool) do table.insert(ordemEmbaralhada, group) end
	for i = #ordemEmbaralhada, 2, -1 do
		local j = math.random(i)
		ordemEmbaralhada[i], ordemEmbaralhada[j] = ordemEmbaralhada[j], ordemEmbaralhada[i]
	end
	-- Maiores grupos primeiro (dentro da ordem já embaralhada acima não
	-- importa mais quem chegou primeiro) — processar o TIME FECHADO
	-- grande logo de cara deixa o resto do balanceamento mais preciso do
	-- que deixá-lo por último "sobrando" pra um lado só.
	table.sort(ordemEmbaralhada, function(a, b) return a.Size > b.Size end)

	local teamSizeOf = {}
	for _, teamName in ipairs(Config.TEAM_NAMES) do teamSizeOf[teamName] = 0 end

	local assignments = {}
	local allGroups = {}
	for _, group in ipairs(ordemEmbaralhada) do
		table.insert(allGroups, group)

		local melhorTimes, menorTamanho = {}, math.huge
		for _, teamName in ipairs(Config.TEAM_NAMES) do
			local tamanho = teamSizeOf[teamName]
			if tamanho < menorTamanho then
				menorTamanho = tamanho
				melhorTimes = { teamName }
			elseif tamanho == menorTamanho then
				table.insert(melhorTimes, teamName)
			end
		end
		local teamName = melhorTimes[math.random(#melhorTimes)]
		teamSizeOf[teamName] += group.Size
		for _, userId in ipairs(group.Members) do
			assignments[tostring(userId)] = teamName
		end
	end

	-- ⚠️ v71 — CORRIGIDO ("só consegue puxar partida se cancelar e entrar
	-- de novo"): "não deixa começar com time vazio" parecia certo, mas
	-- criava um impasse que o comentário original da Sala Livre já
	-- prometia não existir ("fecha a partida com QUALQUER quantidade >=
	-- MinPlayers, assim que o pool tiver gente"). Um time só fica vazio
	-- quando existe EXATAMENTE 1 grupo na pool inteira (2+ grupos sempre
	-- caem em lados diferentes, pelo próprio balanceamento guloso acima)
	-- — e um grupo sozinho NUNCA vira dois (grupo não se divide, de
	-- propósito, pra não separar amigos). Sem essa saída, esse grupo
	-- ficava esperando um SEGUNDO grupo aparecer pra sempre — e "cancelar
	-- e entrar de novo" só "funcionava" porque criava um FANTASMA extra
	-- no pendingPool (bug já corrigido em LeaveQueue), que por acaso virava
	-- esse segundo grupo que faltava.
	--
	-- Agora: só espera os dois lados de verdade nos primeiros
	-- Config.MATCH_FULL_WAIT_SECONDS (mesmo prazo que os modos com time
	-- fixo já usam pra isso) — depois disso, fecha mesmo com um lado só,
	-- em vez de travar a fila pra sempre por causa de 1 grupo sozinho.
	local temTimeVazio = false
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if teamSizeOf[teamName] == 0 then temTimeVazio = true end
	end
	if temTimeVazio and oldestWaitSeconds(pool) < Config.MATCH_FULL_WAIT_SECONDS then
		return
	end

	-- Só esvazia o pool agora que a partida já está montada (mesmo
	-- espírito do tryCloseMatch: nunca perder gente entre o esvaziar e o
	-- reservar o server).
	pendingPool[modeId] = {}

	local reserveOk, accessCode = pcall(function()
		return TeleportService:ReserveServerAsync(Config.GAME_PLACE_ID)
	end)

	if not reserveOk or not accessCode then
		warn("Matchmaker: falha ao reservar server pra Sala Livre: " .. tostring(accessCode))
		for _, group in ipairs(allGroups) do
			pcall(function()
				queues[modeId]:AddAsync({
					LeaderUserId = group.LeaderUserId,
					Members = group.Members,
					QueuedAt = os.time(),
					Region = group.Region, -- ⚠️ v3.4: preserva a preferência ao devolver pra fila (senão o grupo "esquece" a região/nível dele)
					AvgWins = group.AvgWins,
						GK = group.GK, -- ⚠️ v104
				}, Config.QUEUE_ITEM_EXPIRATION)
			end)
		end
		return
	end

	local payload = {
		MatchId = HttpService:GenerateGUID(false),
		ModeId = modeId,
		TotalPlayers = totalPlayers, -- FIX: quantidade REAL, não mode.TotalPlayers (que não existe pra Sala Livre) — é isso que faz o MatchController (place Game) começar a partida direto com quem entrou, sem esperar 10/14
		AccessCode = accessCode,
		Assignments = assignments,
	}

	local publishOk, publishErr = pcall(function()
		MessagingService:PublishAsync(Config.MATCH_FOUND_TOPIC, payload)
	end)
	if not publishOk then
		warn("Matchmaker: falha ao avisar os Lobbies da Sala Livre fechada: " .. tostring(publishErr))
	end
end

-- ===== RECEBER O AVISO DE PARTIDA FECHADA E TELEPORTAR QUEM ESTÁ AQUI =====
-- Todo server de Lobby (inclusive o que achou a partida) reage a este
-- mesmo evento — cada um só teleporta os Players que EXISTEM DE
-- VERDADE nele. É assim que uma partida consegue juntar gente de
-- servers de Lobby diferentes.
local function onMatchFound(message)
	local payload = message.Data
	if typeof(payload) ~= "table" or typeof(payload.Assignments) ~= "table" then return end

	local localPlayers = {}
	local characters = {} -- [tostring(UserId)] = snapshot do personagem ativo (roster)

	for userIdString in pairs(payload.Assignments) do
		local plr = Players:GetPlayerByUserId(tonumber(userIdString))
		if plr then
			table.insert(localPlayers, plr)
			Remotes.MatchFound:FireClient(plr, payload.ModeId)

			if _G.GetPartyLeaderOf and _G.ClearQueuedGroup then
				local leaderUserId = _G.GetPartyLeaderOf()[plr.UserId]
				if leaderUserId then _G.ClearQueuedGroup(leaderUserId) end
			end

			-- FIX: embute o personagem ativo do roster (PlayerDataManager,
			-- via MatchDataTransfer) direto no TeleportData — o place Game
			-- não tem como chamar _G.GetPlayerData (esse global só existe
			-- aqui no Lobby, cada place é um server separado), então isso
			-- precisa vir junto da viagem, não ser buscado depois de
			-- chegar. Continua também salvando em MatchTransferData_V1
			-- como sempre fez (ver _G.PreparePlayerForMatch), como
			-- backup/histórico, mesmo sem nada lendo de lá no Game ainda.
			if _G.PreparePlayerForMatch then
				local ok, result = _G.PreparePlayerForMatch(plr)
				if ok and typeof(result) == "table" and typeof(result.Character) == "table" then
					-- FIX CRÍTICO: isso mandava SÓ result.Character.Attributes
					-- (Physical/DribbleSkill/Speed/Kick/Stamina) pro place Game —
					-- Role, EquippedPulse1/EquippedPulse2/EquippedInstinct (e
					-- Level/Element) ficavam de fora do TeleportData inteiro.
					-- PlayerSystems.legacy.luau (place Game) lê Role e os
					-- Equipped* direto de snapshot.Role/snapshot.EquippedPulse1
					-- etc — como nunca chegavam, _G.SetPlayerLoadout/
					-- _G.SetPlayerInstinct nunca eram chamados: Pulso e Instinto
					-- sorteados no Lobby NUNCA apareciam de verdade na partida,
					-- mesmo já estando salvos certinho no DataStore.
					--
					-- Fix: achata Attributes no nível de cima do snapshot (pra
					-- não quebrar snapshot.Physical/DribbleSkill/Speed/Kick, que
					-- o Game já lia assim) E inclui Role/Level/Equipped* junto.
					-- ⚠️ NOVO: Element REINSERIDO a pedido do usuário — dessa vez
					-- com utilidade de gameplay de verdade (vantagem elemental
					-- e bônus de "elemento igual", ver FootballConfig.lua no
					-- place Game). Antes tinha sido removido por não ter uso.
					local char = result.Character
					local snapshot = {}
					if typeof(char.Attributes) == "table" then
						for attrName, attrValue in pairs(char.Attributes) do
							snapshot[attrName] = attrValue
						end
					end
					snapshot.Role = char.Role
					snapshot.Level = char.Level
					snapshot.Element = char.Element
					snapshot.EquippedPulse1 = char.EquippedPulse1
					snapshot.EquippedPulse2 = char.EquippedPulse2
					snapshot.EquippedPulse3 = char.EquippedPulse3 -- ⚠️ v76: 3º slot (Robux)
					snapshot.EquippedInstinct1 = char.EquippedInstinct1
					snapshot.EquippedInstinct2 = char.EquippedInstinct2 -- ⚠️ v76: Arma também virou 2 slots + 1 Robux
					snapshot.EquippedInstinct3 = char.EquippedInstinct3
					-- ⚠️ v110 — PEDIDO: "implemente o nome personalizado que já tem
					-- nos slots dentro do jogo" + cosméticos/Flow equipados na
					-- partida. SlotName = nome que o jogador deu pro personagem;
					-- Cosmeticos = { [Slot] = Id } (ver Cosmeticos.luau).
					-- o nome JÁ filtrado (TextService) que a placa do Lobby usa
					local nomeFiltrado = plr:GetAttribute("NomePersonagem")
					snapshot.SlotName = typeof(nomeFiltrado) == "string" and nomeFiltrado or plr.DisplayName
					local dadosJogador = _G.GetPlayerData and _G.GetPlayerData(plr)
					if dadosJogador and typeof(dadosJogador.EquippedCosmetics) == "table" then
						local cosm = {}
						for slotCosm, idCosm in pairs(dadosJogador.EquippedCosmetics) do
							if typeof(slotCosm) == "string" and typeof(idCosm) == "string" then
								cosm[slotCosm] = idCosm
							end
						end
						cosm.Flow = cosm.Flow or "Flow_Isagi"
						snapshot.Cosmeticos = cosm
					end

					characters[tostring(plr.UserId)] = snapshot
				else
					warn(("Matchmaker: não consegui preparar o personagem de %s pra partida: %s"):format(plr.Name, tostring(result)))
				end
			end
		end
	end

	if #localPlayers == 0 then return end

	local teleportOptions = Instance.new("TeleportOptions")
	teleportOptions.ReservedServerAccessCode = payload.AccessCode
	teleportOptions:SetTeleportData({
		MatchId = payload.MatchId,
		Mode = payload.ModeId,
		TotalPlayers = payload.TotalPlayers,
		Assignments = payload.Assignments,
		Characters = characters,
		Privada = payload.Privada == true, -- ⚠️ v104: sala personalizada (sem recompensa, GK bot sempre)
		Tutorial = payload.Tutorial == true, -- ⚠️ v104: partida de tutorial (TutorialLobbyServer)
	})

	local ok, err = pcall(function()
		TeleportService:TeleportAsync(Config.GAME_PLACE_ID, localPlayers, teleportOptions)
	end)
	if not ok then
		warn("Matchmaker: falha ao teleportar jogadores locais pra partida: " .. tostring(err))
	end
end

-- ⚠️ v104: a sala personalizada (MatchmakingQueue) teleporta direto por
-- aqui, sem passar pelo MessagingService — só tem gente deste server.
_G.TeleportarPartidaLocal = function(payload)
	onMatchFound({ Data = payload })
end

local subscribeOk, subscribeErr = pcall(function()
	MessagingService:SubscribeAsync(Config.MATCH_FOUND_TOPIC, onMatchFound)
end)
if not subscribeOk then
	warn("Matchmaker: falha ao assinar o tópico de partidas encontradas: " .. tostring(subscribeErr))
end

-- ===== LOOP PRINCIPAL =====
task.spawn(function()
	while true do
		task.wait(Config.QUEUE_POLL_INTERVAL)

		for modeId, mode in pairs(Config.MODES) do
			pullNewGroups(modeId)
			requeueStuckGroups(modeId)
			if mode.IsFreeRoom then
				tryCloseFreeRoom(modeId)
			else
				tryCloseMatch(modeId)
				tryCloseLastResort(modeId) -- ⚠️ v11: só age se tryCloseMatch não fechou nada E já esperou muito (ver Config.MATCH_LAST_RESORT_WAIT_SECONDS)
			end
		end
	end
end)

print("✅ Matchmaker carregado.")
