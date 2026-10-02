--[[
	LobbyRewardsReceiver - Sistema de Recebimento de Recompensas no Lobby
	COLOQUE NO LOBBY (ServerScriptService)
	
	✅ Carrega recompensas da partida quando jogador retorna
	✅ Aplica dinheiro e XP ganhos
	✅ Mostra resumo da partida
	✅ Limpa dados de recompensas após aplicar
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local REWARDS_DATASTORE_NAME = "MatchRewards_V1"
local MAX_RETRY_ATTEMPTS = 5
local RETRY_DELAY = 2
local AUTO_CHECK_REWARDS = true  -- Verificar recompensas ao entrar

-- DataStore de recompensas
local rewardsDataStore = DataStoreService:GetDataStore(REWARDS_DATASTORE_NAME)

-- Cache de recompensas já processadas
local processedRewards = {}

-- ========================================
-- Carregar Recompensas Pendentes
-- ========================================
-- ⚠️ CORRIGIDO (risco de recompensa DUPLICADA): a versão antiga fazia
-- GetAsync (só lê) aqui e um RemoveAsync SEPARADO, 2 segundos depois, lá
-- embaixo em clearRewards — dois passos independentes. Se o server
-- caísse (ou o RemoveAsync falhasse — ele só dava `warn`, sem retry
-- nenhum) entre o "aplicar" e o "limpar", a entrada `Rewards_<userId>`
-- sobrevivia no DataStore, e a mesma recompensa (dinheiro/XP) podia ser
-- aplicada de novo da próxima vez que esse jogador entrasse em qualquer
-- Lobby — o único guard-rail era `processedRewards`, que é só em
-- memória e zera a cada sessão.
--
-- Agora é um ÚNICO UpdateAsync atômico que LÊ E APAGA ao mesmo tempo
-- (devolve nil pra remover a chave) — mesmo com dois servers de Lobby
-- concorrentes, só UMA chamada em todo o universo consegue ver o valor
-- antigo não-nil aqui; qualquer tentativa concorrente/repetida já vê a
-- chave vazia. Não sobra "clear" nenhum pra fazer depois — se o server
-- cair DEPOIS desta chamada (já reivindicou) mas ANTES de aplicar o
-- dinheiro/XP, a recompensa se perde (não duplica) — troca aceitável,
-- perder é raro e recuperável (reporta), duplicar silenciosamente não é.
local function claimPendingRewards(player)
	local userId = player.UserId
	local key = "Rewards_" .. userId

	print(string.format("🎁 Verificando recompensas pendentes para %s...", player.Name))

	for attempt = 1, MAX_RETRY_ATTEMPTS do
		local claimed
		local success, err = pcall(function()
			rewardsDataStore:UpdateAsync(key, function(current)
				claimed = current
				return nil -- remove atomicamente ao mesmo tempo que lê
			end)
		end)

		if success then
			if not claimed then
				print(string.format("📭 Nenhuma recompensa pendente para %s", player.Name))
				return nil
			end

			if type(claimed) ~= "table" or not claimed.MoneyEarned or not claimed.XPEarned then
				warn(string.format("❌ Recompensas inválidas pra %s (já removidas do DataStore, não tenta de novo)", player.Name))
				return nil
			end

			local rewardsAge = os.time() - (claimed.SavedAt or 0)
			if rewardsAge > 86400 then
				warn(string.format("⚠️ Recompensas antigas detectadas (%d horas)",
					math.floor(rewardsAge / 3600)))
			end

			print(string.format("✅ Recompensas encontradas para %s!", player.Name))
			return claimed
		else
			warn(string.format("❌ Erro ao carregar recompensas (tentativa %d): %s",
				attempt, tostring(err)))
			if attempt < MAX_RETRY_ATTEMPTS then
				task.wait(RETRY_DELAY)
			end
		end
	end

	warn(string.format("❌ Não foi possível verificar recompensas de %s", player.Name))
	return nil
end

-- ========================================
-- Aplicar Recompensas ao Jogador
-- ========================================
local function applyRewards(player, rewards)
	print(string.format("⚙️ Aplicando recompensas para %s...", player.Name))

	if not rewards then
		warn("❌ Recompensas inválidas")
		return false
	end

	local success = true

	-- ⚠️ NOVO: Boosts da Loja (categoria Boosts) — 2x dinheiro/XP enquanto
	-- o timestamp de expiração não passou (ver Config.SHOP.Items no
	-- LobbyConfig.lua e BuyCatalogItem em ShopServer.legacy.luau).
	local playerDataForBoosts = _G.GetPlayerData and _G.GetPlayerData(player)
	local now = os.time()
	local moneyMult = 1
	local xpMult = 1
	if playerDataForBoosts and type(playerDataForBoosts.Boosts) == "table" then
		if (playerDataForBoosts.Boosts.MoneyBoostExpiresAt or 0) > now then
			moneyMult = 2
		end
		if (playerDataForBoosts.Boosts.XPBoostExpiresAt or 0) > now then
			xpMult = 2
		end
	end
	local boostedMoney = math.floor((rewards.MoneyEarned or 0) * moneyMult)
	local boostedXP = math.floor((rewards.XPEarned or 0) * xpMult)

	-- 💰 ADICIONAR DINHEIRO
	if _G.AddMoney then
		local moneySuccess = _G.AddMoney(player, boostedMoney)
		if moneySuccess then
			print(string.format("💰 +$%d adicionado para %s%s", boostedMoney, player.Name, moneyMult > 1 and " (boost 2x ativo)" or ""))
		else
			warn(string.format("⚠️ Erro ao adicionar dinheiro para %s", player.Name))
			success = false
		end
	else
		warn("❌ Sistema de dinheiro não disponível!")
		success = false
	end

	-- ⭐ ADICIONAR XP
	if _G.AddPlayerXP then
		-- Adicionar XP ao slot ativo
		if _G.GetPlayerData then
			local playerData = _G.GetPlayerData(player)
			if playerData then
				local activeSlotIndex = playerData.ActiveSlot
				local xpSuccess = _G.AddPlayerXP(player, boostedXP, activeSlotIndex)

				if xpSuccess then
					print(string.format("⭐ +%d XP adicionado para %s%s", boostedXP, player.Name, xpMult > 1 and " (boost 2x ativo)" or ""))
				else
					warn(string.format("⚠️ Erro ao adicionar XP para %s", player.Name))
					success = false
				end
			end
		end
	else
		warn("❌ Sistema de XP não disponível!")
		success = false
	end

	-- ⚠️ NOVO (v3.4): recompensa de partida diz "vitória" → soma 1 no
	-- contador persistente de Wins (ver _G.AddPlayerWin em
	-- PlayerDataManager.legacy.luau) — usado pela preferência de
	-- matchmaking por nível.
	if rewards.MatchResult == "win" and _G.AddPlayerWin then
		_G.AddPlayerWin(player)
	end
	-- ⚠️ v115: soma a partida nas estatísticas de carreira (NPC Bentes)
	if _G.AddCareerStats and type(rewards.Stats) == "table" then
		_G.AddCareerStats(player, rewards.Stats)
	end

	-- ⚠️ NOVO: alimenta o progresso das missões diárias (QuestManager.
	-- legacy.luau + QuestData.luau) com as estatísticas dessa partida —
	-- "Marcar 5 gols", "Driblar 20 vezes", etc.
	if _G.AddQuestProgress then
		local stats = rewards.Stats
		if type(stats) == "table" then
			if stats.Goals and stats.Goals > 0 then
				_G.AddQuestProgress(player, "Goals", stats.Goals)
			end
			if stats.Assists and stats.Assists > 0 then
				_G.AddQuestProgress(player, "Assists", stats.Assists)
			end
			if stats.Tackles and stats.Tackles > 0 then
				_G.AddQuestProgress(player, "Tackles", stats.Tackles)
			end
			if stats.Dribbles and stats.Dribbles > 0 then
				_G.AddQuestProgress(player, "Dribbles", stats.Dribbles)
			end
			if stats.Saves and stats.Saves > 0 then
				_G.AddQuestProgress(player, "Saves", stats.Saves)
			end
		end
		if rewards.MatchResult == "win" then
			_G.AddQuestProgress(player, "Wins", 1)
		end
		_G.AddQuestProgress(player, "MatchesPlayed", 1)
	end

	return success
end

-- ========================================
-- Criar GUI de Resumo da Partida
-- ========================================
local function showMatchSummary(player, rewards)
	print(string.format("📊 Mostrando resumo da partida para %s", player.Name))

	-- Criar RemoteEvent se não existir
	local eventsFolder = ReplicatedStorage:FindFirstChild("MatchEvents")
	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "MatchEvents"
		eventsFolder.Parent = ReplicatedStorage
	end

	local showSummaryEvent = eventsFolder:FindFirstChild("ShowMatchSummary")
	if not showSummaryEvent then
		showSummaryEvent = Instance.new("RemoteEvent")
		showSummaryEvent.Name = "ShowMatchSummary"
		showSummaryEvent.Parent = eventsFolder
	end

	-- Preparar dados do resumo
	local summaryData = {
		Result = rewards.MatchResult,
		MoneyEarned = rewards.MoneyEarned,
		XPEarned = rewards.XPEarned,
		Stats = rewards.Stats
	}

	-- Enviar para o cliente
	showSummaryEvent:FireClient(player, summaryData)

	print(string.format("✅ Resumo enviado para %s", player.Name))
end

-- ========================================
-- Espiar recompensas SEM consumir (só leitura — pro comando de console
-- _G.ShowPendingRewards abaixo; a claimPendingRewards de cima já apaga
-- ao ler, não serve pra "só olhar" sem entregar de verdade).
-- ========================================
local function peekPendingRewards(player)
	local key = "Rewards_" .. player.UserId
	local success, rewards = pcall(function()
		return rewardsDataStore:GetAsync(key)
	end)
	if success then return rewards end
	warn(string.format("⚠️ Erro ao espiar recompensas: %s", tostring(rewards)))
	return nil
end

-- ========================================
-- ⚠️ NOVO: PEDIDO — "na tela final do jogo ele diz que ganha uma certa
-- quantidade de dinheiro e no lobby você ganha uma quantidade bem
-- inferior a ela" + "as missões não estão funcionando 100%... os dribles
-- não são contabilizados, nem os gols". Raiz dos dois: essa recompensa
-- (MoneyEarned E Stats.Goals/Dribbles/etc, no MESMO registro) dependia só
-- do DataStore MatchRewards_V1 — o place Game escreve com SetAsync, e
-- este script lê MINUTOS "depois" (mas em outro SERVER) com UpdateAsync.
-- DataStore entre servers diferentes não garante leitura-após-escrita
-- imediata; se a leitura daqui chegasse rápido demais, podia pegar uma
-- cópia desatualizada (ou nada) — e como claimPendingRewards já APAGA a
-- chave na mesma operação atômica, uma leitura ruim NUNCA se corrige
-- depois (não sobra nada pra tentar de novo). Isso explica os dois
-- sintomas juntos: dinheiro sempre menor que o mostrado na tela final, e
-- só "vencer partida" (Wins, aplicado fora desse registro) funcionando.
--
-- Fix: MatchController.legacy.luau (place Game) agora manda essa mesma
-- recompensa via TeleportData (mesma técnica que Matchmaker.legacy.luau
-- já usa pra levar Characters do Lobby pro Game) — viaja JUNTO com o
-- teleporte, sem NENHUMA leitura de DataStore de outro server envolvida,
-- então chega garantido e na hora certa. O DataStore continua como rede
-- de segurança pro caso raro de TeleportData não vir (ex.: jogador entrou
-- direto no Lobby sem vir de partida nenhuma).
-- ========================================
local function getTeleportRewards(player)
	local ok, joinData = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(joinData) ~= "table" then return nil end

	local teleportData = joinData.TeleportData
	if type(teleportData) ~= "table" or type(teleportData.MatchRewards) ~= "table" then
		return nil
	end

	local rewards = teleportData.MatchRewards[tostring(player.UserId)]
	if type(rewards) ~= "table" or not rewards.MoneyEarned or not rewards.XPEarned then
		return nil
	end
	return rewards
end

-- ========================================
-- Processar Recompensas Completo
-- ========================================
local function processPlayerRewards(player)
	print(string.format("🔄 Processando recompensas de %s...", player.Name))

	-- Verificar se já foi processado nesta sessão
	if processedRewards[player.UserId] then
		print(string.format("⏭️ Recompensas já processadas para %s nesta sessão", player.Name))
		return
	end

	-- ⚠️ NOVO: prioridade pra recompensa que veio JUNTO no teleporte (ver
	-- comentário acima) — 100% confiável, sem depender de DataStore de
	-- outro server.
	local rewards = getTeleportRewards(player)
	if rewards then
		print(string.format("✅ Recompensa recebida via TeleportData para %s (sem esperar DataStore)", player.Name))
		-- Reivindica (e descarta) a cópia de segurança no DataStore mesmo
		-- assim, só pra ela não ficar esquecida lá e ser aplicada de novo
		-- (duplicada) numa visita futura ao Lobby.
		claimPendingRewards(player)
	else
		-- Sem TeleportData (ex.: entrou direto no Lobby, sem vir de
		-- partida) — cai pro fluxo antigo via DataStore.
		rewards = claimPendingRewards(player)
	end

	if not rewards then
		print(string.format("📭 Nenhuma recompensa para processar (%s)", player.Name))
		return
	end

	-- ⚠️ v79 — CORRIGIDO ("saí e entrei de novo, e computou as mesmas
	-- recompensas de novo"): a rede de segurança no DataStore (SetAsync no
	-- place Game, lido via claimPendingRewards aqui) é APAGADA logo depois
	-- de entregue por TeleportData (ver "claimPendingRewards(player)" na
	-- branch acima) — mas esse apagar tem só 5 tentativas / ~10s de retry.
	-- Sob throttling de DataStore (comum logo na entrada, com vários
	-- sistemas lendo/escrevendo ao mesmo tempo), pode falhar silenciosamente
	-- e deixar a entrada viva — aí uma sessão FUTURA qualquer (nem precisa
	-- ter vindo de partida) acha essa sobra e entrega ela de novo.
	-- `processedRewards` só protegia dentro da MESMA sessão de servidor (e
	-- ainda por cima era limpo no PlayerRemoving) — não sobrevivia a sair e
	-- voltar. Agora a proteção é de verdade: persistida em
	-- playerData.LastRewardClaimedAt (ver PlayerDataManager.legacy.luau),
	-- comparada contra rewards.SavedAt (timestamp único da recompensa,
	-- carimbado no place Game em saveRewards) — sobrevive a qualquer
	-- reconexão, em qualquer server.
	local playerDataForDedup = _G.GetPlayerData and _G.GetPlayerData(player)
	if playerDataForDedup and type(rewards.SavedAt) == "number"
		and rewards.SavedAt > 0 and rewards.SavedAt <= (playerDataForDedup.LastRewardClaimedAt or 0) then
		print(string.format("⏭️ Recompensa de %s já foi reivindicada antes (SavedAt=%d <= LastRewardClaimedAt=%d) — ignorando cópia duplicada.",
			player.Name, rewards.SavedAt, playerDataForDedup.LastRewardClaimedAt or 0))
		return
	end

	-- Aguardar sistemas carregarem
	task.wait(2)

	-- Aplicar recompensas
	local success = applyRewards(player, rewards)

	if success then
		-- Carimba ANTES de mais nada (mesmo antes do resumo/print abaixo) —
		-- é a linha que impede a próxima sessão de aplicar essa MESMA
		-- recompensa de novo, mesmo se a cópia de segurança sobrar no
		-- DataStore.
		if playerDataForDedup and type(rewards.SavedAt) == "number" and rewards.SavedAt > (playerDataForDedup.LastRewardClaimedAt or 0) then
			playerDataForDedup.LastRewardClaimedAt = rewards.SavedAt
			if _G.SavePlayerData then _G.SavePlayerData(player) end
		end
		print(string.format("✅ Recompensas aplicadas para %s!", player.Name))

		-- Mostrar resumo
		task.spawn(function()
			task.wait(1)
			showMatchSummary(player, rewards)
		end)

		-- Marcar como processado
		processedRewards[player.UserId] = true

		-- Log de sucesso completo
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print(string.format("🎉 RECOMPENSAS ENTREGUES PARA %s", player.Name))
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		print(string.format("   💰 Dinheiro: +$%d", rewards.MoneyEarned))
		print(string.format("   ⭐ XP: +%d", rewards.XPEarned))
		print(string.format("   ⚽ Gols: %d", rewards.Stats.Goals))
		print(string.format("   🤝 Assistências: %d", rewards.Stats.Assists))
		print(string.format("   🏁 Resultado: %s", rewards.MatchResult))
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	else
		warn(string.format("❌ Erro ao aplicar recompensas para %s", player.Name))
	end
end

-- ========================================
-- FUNÇÃO GLOBAL: Verificar Recompensas Manualmente
-- ========================================
_G.CheckPlayerRewards = function(player)
	processPlayerRewards(player)
end

_G.ForceRewardsCheck = function(playerName)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	-- Resetar flag de processamento
	processedRewards[player.UserId] = nil

	-- Processar novamente
	processPlayerRewards(player)
end

-- ========================================
-- Eventos de Jogador
-- ========================================
Players.PlayerAdded:Connect(function(player)
	-- Aguardar dados básicos carregarem. FIX: WaitForChild só espera a
	-- INSTANCE "DataLoaded" existir (ela já é criada no início do
	-- carregamento, com Value = false) — não espera o Value virar true.
	-- Sem o Changed:Wait() abaixo, essa checagem sempre perdia a corrida
	-- (a instance já existe muito antes dos dados terminarem de carregar
	-- de verdade) e o "return" abaixo disparava sempre, fazendo esse
	-- script NUNCA aplicar as recompensas da partida (dinheiro/XP
	-- ganhos ficavam para sempre pendentes no DataStore, sem aplicar).
	local dataLoaded = player:WaitForChild("DataLoaded", 30)
	if dataLoaded and not dataLoaded.Value then
		dataLoaded.Changed:Wait()
	end

	if not dataLoaded or not dataLoaded.Value then
		warn(string.format("⚠️ Dados não carregados para %s", player.Name))
		return
	end

	print(string.format("✅ Dados carregados para %s", player.Name))

	-- Aguardar um pouco mais para garantir que tudo carregou
	task.wait(3)

	-- Processar recompensas se houver
	if AUTO_CHECK_REWARDS then
		task.spawn(function()
			processPlayerRewards(player)
		end)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	-- Limpar flag de processamento
	processedRewards[player.UserId] = nil
end)

-- ========================================
-- Comando de Console
-- ========================================
_G.ShowPendingRewards = function(playerName)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print(string.format("🎁 RECOMPENSAS PENDENTES - %s", player.Name))
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	local rewards = peekPendingRewards(player)

	if rewards then
		print("")
		print(string.format("   💰 Dinheiro: $%d", rewards.MoneyEarned))
		print(string.format("   ⭐ XP: %d", rewards.XPEarned))
		print(string.format("   ⚽ Gols: %d", rewards.Stats.Goals))
		print(string.format("   🤝 Assistências: %d", rewards.Stats.Assists))
		print(string.format("   🧤 Defesas: %d", rewards.Stats.Saves))
		print(string.format("   💨 Roubos: %d", rewards.Stats.Steals))
		print(string.format("   🏆 MVP: %s", rewards.Stats.MVP and "SIM" or "Não"))
		print(string.format("   🏁 Resultado: %s", rewards.MatchResult))
		print("")
		print(string.format("   📅 Salvo em: %s", os.date("%d/%m/%Y %H:%M:%S", rewards.SavedAt or 0)))
	else
		print("")
		print("   📭 Nenhuma recompensa pendente")
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

_G.TestRewardsFlow = function(playerName)
	local player = Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("🧪 TESTE DE FLUXO DE RECOMPENSAS")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("")
	print("1️⃣ Criando recompensas de teste...")

	-- Criar recompensas de teste no DataStore
	local testRewards = {
		UserId = player.UserId,
		PlayerName = player.Name,
		Timestamp = os.time(),
		SavedAt = os.time(),
		MoneyEarned = 750,
		XPEarned = 300,
		Stats = {
			Goals = 3,
			Assists = 2,
			Saves = 0,
			Steals = 5,
			MVP = true
		},
		UnlockedItems = {},
		MatchDuration = 300,
		MatchResult = "win"
	}

	local success = pcall(function()
		rewardsDataStore:SetAsync("Rewards_" .. player.UserId, testRewards)
	end)

	if success then
		print("✅ Recompensas de teste criadas!")
		print("")
		print("2️⃣ Resetando flag de processamento...")
		processedRewards[player.UserId] = nil
		print("✅ Flag resetada!")
		print("")
		print("3️⃣ Processando recompensas...")
		print("")

		task.wait(1)
		processPlayerRewards(player)

		print("")
		print("✅ Teste completo!")
	else
		print("❌ Erro ao criar recompensas de teste")
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

print(string.format("✅ LobbyRewardsReceiver carregado (auto-verificação %s)", AUTO_CHECK_REWARDS and "ativa" or "desativada"))