--[[
	MatchmakingQueue (Script)
	LOCAL: ServerScriptService (place Lobby)

	Duas responsabilidades, self-contidas neste arquivo pra não espalhar
	estado de grupo em vários lugares:

	1) GRUPO (party): convite simples entre jogadores DESTE MESMO server
	   de Lobby, pra quem quer entrar junto na fila com amigos. Todo
	   jogador começa num "grupo solo" (líder = ele mesmo).

	2) FILA: entrada/saída dos modos (5v5/7v7) na MemoryStoreQueue
	   correspondente. Cada item da fila representa um GRUPO INTEIRO
	   (grupo de 1 = sozinho), nunca jogadores soltos — assim o
	   Matchmaker.lua nunca precisa se preocupar em separar amigos.

	Este script NÃO lê/fecha partidas — isso é o Matchmaker.lua, que roda
	em paralelo e só CONSOME o que este aqui produz na fila.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local LocalizationService = game:GetService("LocalizationService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

-- ⚠️ v3.4: PREFERÊNCIA DE MATCHMAKING (pedido: "primeiro o país, a
-- preferência vai ser o ping de todo mundo... depois vai ser as
-- vitórias"). O Roblox não expõe o ping de um jogador pra um server que
-- ele ainda nem entrou (só dá pra medir ping DEPOIS de já estar
-- conectado nele) — não tem como prever isso antes de formar a partida.
-- LocalizationService:GetCountryRegionForPlayerAsync é a aproximação
-- realista disponível: gente do mesmo país/região tende a ter ping
-- parecido entre si num mesmo server, então "mesma região" é usado aqui
-- como o proxy de "ping parecido" pedido — ver Matchmaker.legacy.luau
-- pra como isso entra na hora de fechar os times.
local function regionOf(player)
	local ok, region = pcall(function()
		return LocalizationService:GetCountryRegionForPlayerAsync(player)
	end)
	return (ok and typeof(region) == "string" and region ~= "") and region or "UNKNOWN"
end

-- Média de Wins (vitórias persistentes, ver PlayerDataManager.legacy.luau)
-- do grupo inteiro — usada como critério de nível pra preferir juntar
-- grupos de força parecida (ver Matchmaker.legacy.luau).
local function averageWinsOf(memberUserIds)
	local total, count = 0, 0
	for _, userId in ipairs(memberUserIds) do
		local plr = Players:GetPlayerByUserId(userId)
		local data = plr and _G.GetPlayerData and _G.GetPlayerData(plr)
		if data and type(data.Wins) == "number" then
			total += data.Wins
			count += 1
		end
	end
	if count == 0 then return 0 end
	return total / count
end

-- ===== FILAS (uma por modo) =====
local queues = {}
for modeId in pairs(Config.MODES) do
	queues[modeId] = MemoryStoreService:GetQueue(Config.QUEUE_NAME_PREFIX .. modeId, Config.QUEUE_INVISIBILITY_TIMEOUT)
end

_G.GetMatchmakingQueue = function(modeId)
	return queues[modeId]
end

-- ===== ESTADO DE GRUPO (PARTY) — tudo indexado pelo UserId do LÍDER =====
local partyLeaderOf = {} -- [UserId] = leaderUserId (grupo solo: partyLeaderOf[id] == id)
local partyMembers = {}  -- [leaderUserId] = { UserId, ... } (líder incluso, ordem de entrada)
local pendingInvite = {} -- [targetUserId] = { FromUserId = , ExpiresAt = }
local queuedGroups = {}  -- [leaderUserId] = { ModeId = } — marca "este grupo está na fila", usado só pra UI/validação LOCAL

local function getPlayerByUserId(userId)
	return Players:GetPlayerByUserId(userId)
end

local function ensureSoloParty(player)
	if not partyLeaderOf[player.UserId] then
		partyLeaderOf[player.UserId] = player.UserId
		partyMembers[player.UserId] = { player.UserId }
	end
end

local function broadcastPartyState(leaderUserId)
	local members = partyMembers[leaderUserId]
	if not members then return end

	local memberNames = {}
	for _, userId in ipairs(members) do
		local plr = getPlayerByUserId(userId)
		table.insert(memberNames, plr and plr.Name or ("Jogador " .. userId))
	end

	for _, userId in ipairs(members) do
		local plr = getPlayerByUserId(userId)
		if plr then
			Remotes.UpdatePartyState:FireClient(plr, {
				LeaderUserId = leaderUserId,
				IsLeader = userId == leaderUserId,
				Members = memberNames,
			})
		end
	end
end

local function disbandParty(leaderUserId)
	local members = partyMembers[leaderUserId]
	if not members then return end

	partyMembers[leaderUserId] = nil
	for _, userId in ipairs(members) do
		partyLeaderOf[userId] = nil
		local plr = getPlayerByUserId(userId)
		if plr then
			ensureSoloParty(plr)
			broadcastPartyState(plr.UserId)
		end
	end
end

local function isInQueue(leaderUserId)
	return queuedGroups[leaderUserId] ~= nil
end

Players.PlayerAdded:Connect(ensureSoloParty)
for _, player in ipairs(Players:GetPlayers()) do
	ensureSoloParty(player)
end

Players.PlayerRemoving:Connect(function(player)
	local leaderUserId = partyLeaderOf[player.UserId]
	if leaderUserId == player.UserId then
		-- Era o líder: dissolve o grupo todo. Mais simples e previsível
		-- que promover outro membro (evita um duo virar trio de fila sem
		-- ninguém ter pedido isso).
		disbandParty(leaderUserId)
	elseif leaderUserId and partyMembers[leaderUserId] then
		local members = partyMembers[leaderUserId]
		for i, userId in ipairs(members) do
			if userId == player.UserId then
				table.remove(members, i)
				break
			end
		end
		broadcastPartyState(leaderUserId)
	end
	partyLeaderOf[player.UserId] = nil
	pendingInvite[player.UserId] = nil
end)

-- ===== CONVITE DE GRUPO =====
Remotes.InviteToParty.OnServerEvent:Connect(function(player, targetPlayer)
	if typeof(targetPlayer) ~= "Instance" or not targetPlayer:IsA("Player") then return end
	if targetPlayer == player then return end

	local myLeader = partyLeaderOf[player.UserId]
	if isInQueue(myLeader) then
		warn(player.Name .. " tentou convidar alguém com o grupo já na fila.")
		return
	end
	if #partyMembers[myLeader] >= Config.MAX_PARTY_SIZE then
		warn(player.Name .. " tentou convidar, mas o grupo já está no limite (" .. Config.MAX_PARTY_SIZE .. ").")
		return
	end
	if partyLeaderOf[targetPlayer.UserId] ~= targetPlayer.UserId then
		warn(targetPlayer.Name .. " já está em outro grupo, convite ignorado.")
		return
	end

	pendingInvite[targetPlayer.UserId] = { FromUserId = player.UserId, ExpiresAt = tick() + Config.PARTY_INVITE_TIMEOUT }
	Remotes.ReceivePartyInvite:FireClient(targetPlayer, player.Name, player.UserId)
end)

Remotes.RespondToPartyInvite.OnServerEvent:Connect(function(player, accepted)
	local invite = pendingInvite[player.UserId]
	pendingInvite[player.UserId] = nil
	if not invite or tick() > invite.ExpiresAt then return end
	if not accepted then return end

	local inviter = getPlayerByUserId(invite.FromUserId)
	if not inviter then return end

	local inviterLeader = partyLeaderOf[inviter.UserId]
	local myLeader = partyLeaderOf[player.UserId]
	if isInQueue(inviterLeader) or (myLeader and isInQueue(myLeader)) then return end
	if not partyMembers[inviterLeader] or #partyMembers[inviterLeader] >= Config.MAX_PARTY_SIZE then return end

	-- Sai do grupo atual (se não for sozinho) antes de entrar no do convidador.
	if myLeader then
		if myLeader == player.UserId then
			disbandParty(myLeader)
		elseif partyMembers[myLeader] then
			for i, userId in ipairs(partyMembers[myLeader]) do
				if userId == player.UserId then
					table.remove(partyMembers[myLeader], i)
					break
				end
			end
			broadcastPartyState(myLeader)
		end
	end

	partyLeaderOf[player.UserId] = inviterLeader
	table.insert(partyMembers[inviterLeader], player.UserId)
	broadcastPartyState(inviterLeader)
end)

Remotes.LeaveParty.OnServerEvent:Connect(function(player)
	local leaderUserId = partyLeaderOf[player.UserId]
	if not leaderUserId or leaderUserId == player.UserId then return end -- já sozinho/líder, nada a fazer aqui

	local members = partyMembers[leaderUserId]
	if members then
		for i, userId in ipairs(members) do
			if userId == player.UserId then
				table.remove(members, i)
				break
			end
		end
	end

	partyLeaderOf[player.UserId] = nil
	ensureSoloParty(player)
	broadcastPartyState(player.UserId)
	broadcastPartyState(leaderUserId)
end)

-- ===== FILA =====
local function buildQueueItem(leaderUserId, leaderPlayer)
	local memberUserIds = {}
	for _, userId in ipairs(partyMembers[leaderUserId]) do
		table.insert(memberUserIds, userId)
	end
	return {
		LeaderUserId = leaderUserId,
		Members = memberUserIds,
		QueuedAt = os.time(),
		-- ⚠️ v3.4: usados pelo Matchmaker.legacy.luau pra preferir juntar
		-- grupos da mesma região (proxy de ping parecido) e de nível
		-- parecido (Wins) antes de cair pra combinação livre de sempre —
		-- ver regionOf/averageWinsOf acima.
		Region = regionOf(leaderPlayer),
		AvgWins = averageWinsOf(memberUserIds),
	}
end

Remotes.JoinQueue.OnServerEvent:Connect(function(player, modeId)
	local mode = Config.MODES[modeId]
	if not mode then
		warn("Modo de partida inválido: " .. tostring(modeId))
		return
	end

	local leaderUserId = partyLeaderOf[player.UserId]
	if leaderUserId ~= player.UserId then
		warn(player.Name .. " tentou entrar na fila sem ser o líder do grupo.")
		return -- só o líder decide a fila do grupo inteiro
	end
	if isInQueue(leaderUserId) then return end

	local groupSize = #partyMembers[leaderUserId]
	if not mode.IsFreeRoom and groupSize > mode.PerTeam then
		warn(("Grupo de %d jogadores não cabe no modo %s (máx %d por time)."):format(groupSize, mode.Id, mode.PerTeam))
		return
	end

	local queue = queues[modeId]
	local item = buildQueueItem(leaderUserId, player)
	local success, err = pcall(function()
		queue:AddAsync(item, Config.QUEUE_ITEM_EXPIRATION)
	end)
	if not success then
		warn("Falha ao entrar na fila: " .. tostring(err))
		return
	end

	queuedGroups[leaderUserId] = { ModeId = modeId }

	for _, userId in ipairs(partyMembers[leaderUserId]) do
		local plr = getPlayerByUserId(userId)
		if plr then
			Remotes.UpdateQueueStatus:FireClient(plr, { InQueue = true, ModeId = modeId })
		end
	end
end)

Remotes.LeaveQueue.OnServerEvent:Connect(function(player)
	local leaderUserId = partyLeaderOf[player.UserId]
	if leaderUserId ~= player.UserId then return end

	if not queuedGroups[leaderUserId] then return end
	queuedGroups[leaderUserId] = nil

	-- ⚠️ v71 — CORRIGIDO ("só consegue puxar partida se cancelar e entrar
	-- de novo, como se precisasse duas vezes"): antes, sair da fila só
	-- avisava o CLIENTE — o grupo, se já tivesse sido puxado da
	-- MemoryStoreQueue pro pendingPool do Matchmaker.lua (pullNewGroups),
	-- continuava lá "fantasma" até casar com alguém ou expirar sozinho em
	-- 90s (Config.GROUP_STUCK_REQUEUE_AFTER). Entrar de novo criava uma
	-- SEGUNDA entrada fantasma pro mesmo líder, e era ELA (não o cancelar
	-- em si) que acabava fechando a Sala Livre — ver o comentário de
	-- tryCloseFreeRoom no Matchmaker.legacy.luau pro resto da história.
	--
	-- _G.RemovePendingGroup (exposto pelo Matchmaker.legacy.luau) tira o
	-- grupo do pendingPool de VERDADE, não só do "queria continuar?" do
	-- cliente. Ainda não cobre um pendingPool de OUTRO server de Lobby
	-- (Roblox não dá jeito de falar com o pendingPool alheio) — mas esse
	-- caso já cai sozinho no timeout de 90s, que é bem menor que "o
	-- jogador nunca mais consegue fechar partida sem o truque".
	if _G.RemovePendingGroup then
		for modeId in pairs(Config.MODES) do
			_G.RemovePendingGroup(modeId, leaderUserId)
		end
	end

	-- Não dá pra "puxar de volta" um item já publicado na MemoryStoreQueue
	-- na hora — se o Matchmaker (deste ou de outro server) ainda não leu
	-- esse item, ele só some de vez quando expirar (Config.QUEUE_ITEM_-
	-- EXPIRATION) ou quando for lido e descartado por não caber em
	-- nenhuma combinação (ver Matchmaker.lua). Marcar localmente como
	-- "não quer mais" evita reprocessar o grupo se ESTE server for quem
	-- ler o item; outros servers não sabem — na pior das hipóteses, a
	-- pessoa é convocada pra uma partida depois de já ter cancelado, e
	-- o MatchFound do lado dela some porque queuedGroups já está limpo
	-- (ver Matchmaker.lua, ele confia nesse estado antes de teleportar).
	for _, userId in ipairs(partyMembers[leaderUserId] or {}) do
		local plr = getPlayerByUserId(userId)
		if plr then
			Remotes.UpdateQueueStatus:FireClient(plr, { InQueue = false })
		end
	end
end)

_G.GetPartyMembers = function() return partyMembers end
_G.GetPartyLeaderOf = function() return partyLeaderOf end
_G.IsGroupQueued = function(leaderUserId) return queuedGroups[leaderUserId] ~= nil end
_G.ClearQueuedGroup = function(leaderUserId) queuedGroups[leaderUserId] = nil end

print("✅ MatchmakingQueue carregado.")
