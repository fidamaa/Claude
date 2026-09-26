--[[
	QuestManager (Script) — ServerScriptService (place Lobby)

	Sistema de missões. Pedido do usuário: "faz um sistema de quests...
	quero elas inseridas já no próprio script, aleatorizando pros
	players" — a lista de missões fica em QuestData.luau (ReplicatedStorage),
	esse script só sorteia candidatas, guarda a escolha/progresso do
	jogador, e paga.

	Fluxo (v2 — escolha + reset de 12h):
	1) A cada QuestData.RESET_INTERVAL_SECONDS (12h), ensureCurrentPeriod
	   sorteia QuestData.OFFER_QUEST_COUNT candidatas da pool (sem
	   repetir) e zera Active/Progress/Completed — o jogador PRECISA
	   escolher de novo quais quer deixar ativas nesse novo período
	   (pedido: "coloque a opção de escolher a quest").
	2) O jogador escolhe até QuestData.ACTIVE_QUEST_COUNT das oferecidas
	   via SelectQuest (RemoteEvent, id -> liga/desliga). Só Ids em Active
	   progridem.
	3) _G.AddQuestProgress(player, statName, amount) é chamado de
	   LobbyRewardsReceiver.legacy.luau toda vez que uma recompensa de
	   partida chega do place Game. Soma no progresso de toda missão
	   ATIVA (escolhida) cujo Stat bate com statName; ao bater o Target,
	   paga o Reward em dinheiro NA HORA (sem precisar "coletar" com o
	   NPC) e marca Completed pra nunca pagar 2x.
	4) O painel de missões (QuestClient.local.luau) pede a lista pronta
	   via RemoteFunction GetQuests; _G.OpenQuests (definido lá) é chamado
	   pelo NPC de missão via DialogueClient (ver DialogueData.QuestGiver).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestData = require(ReplicatedStorage:WaitForChild("QuestData"))

-- ========================================
-- Remotes
-- ========================================
local questEvents = ReplicatedStorage:FindFirstChild("QuestEvents")
if not questEvents then
	questEvents = Instance.new("Folder")
	questEvents.Name = "QuestEvents"
	questEvents.Parent = ReplicatedStorage
end

local getQuestsRemote = Instance.new("RemoteFunction")
getQuestsRemote.Name = "GetQuests"
getQuestsRemote.Parent = questEvents

-- NOVO: escolher/desmarcar uma missão oferecida (pedido: "coloque a
-- opção de escolher a quest"). Retorna (success, message) tipo
-- RedeemCode, pra dar feedback claro no painel.
local selectQuestRemote = Instance.new("RemoteFunction")
selectQuestRemote.Name = "SelectQuest"
selectQuestRemote.Parent = questEvents

local questCompletedRemote = Instance.new("RemoteEvent")
questCompletedRemote.Name = "QuestCompleted"
questCompletedRemote.Parent = questEvents

-- ========================================
-- Helpers
-- ========================================
local function currentPeriodId()
	return math.floor(os.time() / QuestData.RESET_INTERVAL_SECONDS)
end

local function periodEndsAt(periodId)
	return (periodId + 1) * QuestData.RESET_INTERVAL_SECONDS
end

local questById = {}
for _, def in ipairs(QuestData.Quests) do
	questById[def.Id] = def
end

local function findQuestDef(id)
	return questById[id]
end

-- Sorteia OFFER_QUEST_COUNT Ids sem repetir (Fisher-Yates parcial).
local function rollOfferedQuests()
	local pool = {}
	for _, def in ipairs(QuestData.Quests) do
		table.insert(pool, def.Id)
	end

	local count = math.min(QuestData.OFFER_QUEST_COUNT or 6, #pool)
	local picked = {}
	for i = 1, count do
		local j = math.random(i, #pool)
		pool[i], pool[j] = pool[j], pool[i]
		table.insert(picked, pool[i])
	end
	return picked
end

-- Garante que o jogador tem candidatas válidas PRO PERÍODO ATUAL —
-- sorteia (ou re-sorteia, se o período de 12h mudou) quando necessário.
-- Ao trocar de período, o jogador PERDE a escolha anterior (precisa
-- escolher de novo, por design — cada período é um sorteio novo).
local function ensureCurrentPeriod(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then
		return
	end

	if type(playerData.Quests) ~= "table" then
		playerData.Quests = { PeriodId = nil, Offered = {}, Active = {}, Progress = {}, Completed = {} }
	end

	local period = currentPeriodId()
	if playerData.Quests.PeriodId == period and #playerData.Quests.Offered > 0 then
		return -- já sorteado nesse período, nada a fazer
	end

	playerData.Quests.PeriodId = period
	playerData.Quests.Offered = rollOfferedQuests()
	playerData.Quests.Active = {}
	playerData.Quests.Progress = {}
	playerData.Quests.Completed = {}

	if _G.RequestSave then
		_G.RequestSave(player)
	end

	print(string.format("🗒️ Missões oferecidas para %s (período %d): %s", player.Name, period, table.concat(playerData.Quests.Offered, ", ")))
end

-- Monta a lista resolvida (nome/target/reward já preenchidos) pro painel
-- do cliente, sem que o cliente precise dar require em QuestData.
local function buildResolvedList(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData or type(playerData.Quests) ~= "table" then
		return { Quests = {}, PeriodEndsAt = 0, ActiveLimit = QuestData.ACTIVE_QUEST_COUNT }
	end

	local list = {}
	for _, id in ipairs(playerData.Quests.Offered) do
		local def = findQuestDef(id)
		if def then
			local isActive = table.find(playerData.Quests.Active, id) ~= nil
			table.insert(list, {
				Id = def.Id,
				Name = def.Name,
				Progress = playerData.Quests.Progress[id] or 0,
				Target = def.Target,
				Reward = def.Reward,
				Active = isActive,
				Completed = playerData.Quests.Completed[id] == true,
			})
		end
	end

	local activeLimit = QuestData.ACTIVE_QUEST_COUNT
	if type(playerData.Boosts) == "table" and (playerData.Boosts.ExtraQuestExpiresAt or 0) > os.time() then
		activeLimit += 1
	end

	return {
		Quests = list,
		PeriodEndsAt = periodEndsAt(playerData.Quests.PeriodId or currentPeriodId()),
		ActiveLimit = activeLimit,
	}
end

-- ========================================
-- Progresso (chamado de LobbyRewardsReceiver.legacy.luau)
-- ========================================
_G.AddQuestProgress = function(player, statName, amount)
	amount = amount or 1
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData or type(playerData.Quests) ~= "table" then
		return
	end

	ensureCurrentPeriod(player) -- garante que não tá progredindo missão de um período antigo

	local changed = false
	for _, id in ipairs(playerData.Quests.Active) do -- só as ESCOLHIDAS progridem
		if not playerData.Quests.Completed[id] then
			local def = findQuestDef(id)
			if def and def.Stat == statName then
				local newProgress = math.min((playerData.Quests.Progress[id] or 0) + amount, def.Target)
				playerData.Quests.Progress[id] = newProgress
				changed = true

				if newProgress >= def.Target then
					playerData.Quests.Completed[id] = true

					if _G.AddMoney then
						_G.AddMoney(player, def.Reward)
					end

					questCompletedRemote:FireClient(player, def.Name, def.Reward)
					print(string.format("🏆 %s completou a missão '%s': +$%d", player.Name, def.Name, def.Reward))
				end
			end
		end
	end

	if changed and _G.RequestSave then
		_G.RequestSave(player)
	end
end

-- ========================================
-- RemoteFunction: painel pede a lista pronta
-- ========================================
getQuestsRemote.OnServerInvoke = function(player)
	ensureCurrentPeriod(player)
	return buildResolvedList(player)
end

-- ========================================
-- RemoteFunction: escolher/desmarcar uma missão oferecida
-- ========================================
selectQuestRemote.OnServerInvoke = function(player, questId)
	if typeof(questId) ~= "string" then
		return false, "Missão inválida.", buildResolvedList(player)
	end

	ensureCurrentPeriod(player)

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then
		return false, "Dados ainda não carregados.", buildResolvedList(player)
	end

	if not table.find(playerData.Quests.Offered, questId) then
		return false, "Essa missão não está mais disponível.", buildResolvedList(player)
	end

	-- ⚠️ v75 — CORRIGIDO ("depois de completar uma missão, não dá pra
	-- des-selecionar ela pra escolher outra"): esta função bloqueava
	-- QUALQUER toque numa missão já Completed — inclusive tentar tirá-la
	-- de Active pra abrir vaga. Como ela nunca saía de Active sozinha
	-- (fica lá "pra nunca pagar 2x", ver cabeçalho do arquivo), completar
	-- as missões ativas TRAVAVA o jogador sem nenhuma vaga livre até o
	-- período resetar (12h) — mesmo tendo feito tudo direitinho.
	--
	-- O bloqueio agora só vale pra ATIVAR (uma missão Completed nunca
	-- pode voltar a valer, senão pagaria de novo) — DESATIVAR continua
	-- liberado sempre, é só isso que abre a vaga.
	local activeIndex = table.find(playerData.Quests.Active, questId)
	local estaAtiva = activeIndex ~= nil

	if not estaAtiva and playerData.Quests.Completed[questId] then
		return false, "Essa missão já foi completada — não dá pra reativar, mas dá pra remover as suas concluídas pra abrir vaga.", buildResolvedList(player)
	end

	-- ⚠️ NOVO: Loja > Boosts > "Missão Extra" — +1 missão ativa enquanto o
	-- boost não expirar (ver Config.SHOP.Items no LobbyConfig.lua e
	-- BuyCatalogItem em ShopServer.legacy.luau).
	local activeLimit = QuestData.ACTIVE_QUEST_COUNT
	if type(playerData.Boosts) == "table" and (playerData.Boosts.ExtraQuestExpiresAt or 0) > os.time() then
		activeLimit += 1
	end

	if estaAtiva then
		table.remove(playerData.Quests.Active, activeIndex)
	else
		if #playerData.Quests.Active >= activeLimit then
			return false, string.format("Você só pode ter %d missões ativas por vez — desmarque uma antes.", activeLimit), buildResolvedList(player)
		end
		table.insert(playerData.Quests.Active, questId)
	end

	if _G.RequestSave then
		_G.RequestSave(player)
	end

	return true, nil, buildResolvedList(player)
end

-- ========================================
-- Entrada do jogador
-- ========================================
Players.PlayerAdded:Connect(function(player)
	local dataLoaded = player:WaitForChild("DataLoaded", 30)
	if dataLoaded and not dataLoaded.Value then
		dataLoaded.Changed:Wait()
	end

	if not dataLoaded or not dataLoaded.Value then
		warn(string.format("⚠️ QuestManager: dados não carregados para %s, missões não sorteadas", player.Name))
		return
	end

	ensureCurrentPeriod(player)
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		local dataLoaded = player:WaitForChild("DataLoaded", 30)
		if dataLoaded and not dataLoaded.Value then
			dataLoaded.Changed:Wait()
		end
		if dataLoaded and dataLoaded.Value then
			ensureCurrentPeriod(player)
		end
	end)
end

print("✅ Sistema de Missões (Servidor) carregado")
