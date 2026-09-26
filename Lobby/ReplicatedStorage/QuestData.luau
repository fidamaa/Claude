--[[
	QuestData (ModuleScript)
	LOCAL: ReplicatedStorage (place Lobby)

	Pool de missões — pedido do usuário: "faz um sistema de quests...
	quero elas inseridas já no próprio script, aleatorizando pros
	players". A cada RESET_INTERVAL_SECONDS (12h — pedido: "elas resetam a
	cada 12h"), QuestManager.legacy.luau sorteia Data.OFFER_QUEST_COUNT
	candidatas DESTA lista (sem repetir) e oferece pro jogador ESCOLHER
	até Data.ACTIVE_QUEST_COUNT delas pra deixar ativas (pedido: "coloque
	a opção de escolher a quest") — só as escolhidas progridem e pagam.

	Progresso é alimentado via _G.AddQuestProgress (chamado de
	LobbyRewardsReceiver.legacy.luau toda vez que uma recompensa de
	partida chega do place Game — ver Stats ali: Goals, Assists, Tackles,
	Dribbles, Saves, Wins, MatchesPlayed).

	Pra ADICIONAR uma missão nova: só acrescente uma entrada na tabela
	abaixo — QuestManager já pega ela no sorteio automaticamente, não
	precisa mexer em mais nada. Campos:
		Id       — único e ESTÁVEL. Nunca troque o Id de uma missão já
		           publicada (quem estiver com ela ativa perde o
		           progresso, já que o progresso é salvo por Id).
		Name     — texto mostrado no painel de missões.
		Stat     — qual estatística de partida alimenta o progresso:
		           "Goals" (gols marcados), "Assists" (assistências),
		           "Tackles" (desarmes), "Dribbles" (fintas de Pulso/
		           drible bem-sucedidas), "Saves" (defesas de goleiro —
		           mergulho pegando chute de verdade, ver
		           BallController.legacy.luau), "Wins" (+1 só quando o
		           resultado da partida é vitória), "MatchesPlayed" (+1
		           em toda partida que termina, ganhando ou perdendo).
		Target   — quanto precisa acumular pra completar.
		Reward   — dinheiro concedido AUTOMATICAMENTE (sem precisar
		           "coletar" com o NPC) assim que Progress >= Target,
		           só pra missões que o jogador ESCOLHEU deixar ativas.
]]

local Data = {}

-- Quantas missões o jogador PODE deixar ativas ao mesmo tempo (escolhidas
-- dentre as ofertadas).
Data.ACTIVE_QUEST_COUNT = 3

-- Quantas candidatas são sorteadas/oferecidas por período pro jogador
-- escolher (sempre >= ACTIVE_QUEST_COUNT, pra sobrar opção de escolha).
Data.OFFER_QUEST_COUNT = 6

-- Reset das missões — pedido: "elas resetam a cada 12h" (era todo dia).
Data.RESET_INTERVAL_SECONDS = 12 * 60 * 60

Data.Quests = {
	-- Ataque / gols
	{ Id = "Quest_Score3Goals", Name = "Marcar 3 gols", Stat = "Goals", Target = 3, Reward = 200 },
	{ Id = "Quest_Score5Goals", Name = "Marcar 5 gols", Stat = "Goals", Target = 5, Reward = 300 },
	{ Id = "Quest_Score8Goals", Name = "Marcar 8 gols", Stat = "Goals", Target = 8, Reward = 450 },
	{ Id = "Quest_Score10Goals", Name = "Marcar 10 gols", Stat = "Goals", Target = 10, Reward = 550 },

	-- Drible
	{ Id = "Quest_Dribble10", Name = "Driblar 10 vezes", Stat = "Dribbles", Target = 10, Reward = 150 },
	{ Id = "Quest_Dribble20", Name = "Driblar 20 vezes", Stat = "Dribbles", Target = 20, Reward = 250 },
	{ Id = "Quest_Dribble30", Name = "Driblar 30 vezes", Stat = "Dribbles", Target = 30, Reward = 350 },
	{ Id = "Quest_Dribble40", Name = "Driblar 40 vezes", Stat = "Dribbles", Target = 40, Reward = 450 },

	-- Assistência
	{ Id = "Quest_Assist2", Name = "Dar 2 assistências", Stat = "Assists", Target = 2, Reward = 180 },
	{ Id = "Quest_Assist3", Name = "Dar 3 assistências", Stat = "Assists", Target = 3, Reward = 250 },
	{ Id = "Quest_Assist6", Name = "Dar 6 assistências", Stat = "Assists", Target = 6, Reward = 500 },

	-- Defesa (desarme)
	{ Id = "Quest_Tackle5", Name = "Fazer 5 desarmes", Stat = "Tackles", Target = 5, Reward = 120 },
	{ Id = "Quest_Tackle10", Name = "Fazer 10 desarmes", Stat = "Tackles", Target = 10, Reward = 200 },
	{ Id = "Quest_Tackle20", Name = "Fazer 20 desarmes", Stat = "Tackles", Target = 20, Reward = 400 },

	-- Goleiro (defesas de verdade — mergulho pegando chute)
	{ Id = "Quest_Save3", Name = "Fazer 3 defesas de goleiro", Stat = "Saves", Target = 3, Reward = 180 },
	{ Id = "Quest_Save5", Name = "Fazer 5 defesas de goleiro", Stat = "Saves", Target = 5, Reward = 300 },
	{ Id = "Quest_Save10", Name = "Fazer 10 defesas de goleiro", Stat = "Saves", Target = 10, Reward = 500 },
	{ Id = "Quest_Save15", Name = "Fazer 15 defesas de goleiro", Stat = "Saves", Target = 15, Reward = 700 },

	-- Vitórias
	{ Id = "Quest_Win1", Name = "Vencer 1 partida", Stat = "Wins", Target = 1, Reward = 350 },
	{ Id = "Quest_Win2", Name = "Vencer 2 partidas", Stat = "Wins", Target = 2, Reward = 500 },
	{ Id = "Quest_Win3", Name = "Vencer 3 partidas", Stat = "Wins", Target = 3, Reward = 700 },

	-- Participação
	{ Id = "Quest_Play2", Name = "Jogar 2 partidas", Stat = "MatchesPlayed", Target = 2, Reward = 150 },
	{ Id = "Quest_Play3", Name = "Jogar 3 partidas", Stat = "MatchesPlayed", Target = 3, Reward = 200 },
	{ Id = "Quest_Play5", Name = "Jogar 5 partidas", Stat = "MatchesPlayed", Target = 5, Reward = 350 },
	{ Id = "Quest_Play6", Name = "Jogar 6 partidas", Stat = "MatchesPlayed", Target = 6, Reward = 400 },
}

return Data
