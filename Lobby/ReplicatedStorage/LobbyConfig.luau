--[[
	LobbyConfig (ModuleScript)
	LOCAL: ReplicatedStorage (place Lobby)

	Config do sistema de matchmaking do Lobby. Mesmo espírito do
	FootballConfig.lua do place Game, mas isolado aqui porque Lobby e
	Game são PLACES DIFERENTES no Roblox — não existe ReplicatedStorage
	compartilhado entre eles. Qualquer coisa que os dois precisem saber
	em comum (nomes de time, tamanho de modo) é reescrita manualmente
	dos dois lados. Ver Config.SYNC_NOTE.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = {}

Config.SYNC_NOTE = "TEAM_NAMES aqui tem que ser IDÊNTICO ao Config.TEAM_NAMES "
	.. "do FootballConfig.lua (place Game) — é o texto usado tanto pra "
	.. "criar os Teams quanto pra montar a tabela de Assignments que vai "
	.. "no TeleportData. Se mudar de um lado, muda do outro."

-- ===== PLACE DE DESTINO =====
Config.GAME_PLACE_ID = 118271624777790

-- ===== TIMES (espelha Config.TEAM_NAMES do FootballConfig.lua) =====
Config.TEAM_NAMES = { "Azul", "Amarelo" }

-- ===== MODOS DE PARTIDA =====
-- FREE = "Sala Livre": não exige times fechados em 5 ou 7 por lado, nem
-- número exato de jogadores — fecha a partida com QUALQUER quantidade
-- >= MinPlayers assim que o pool tiver gente (ver tryCloseFreeRoom no
-- Matchmaker.lua), pra dar pra testar/jogar casual com poucos amigos.
Config.MODES = {
	["FREE"] = { Id = "FREE", DisplayName = "Sala Livre", IsFreeRoom = true, MinPlayers = 1 },
	["3v3"] = { Id = "3v3", DisplayName = "3 x 3", PerTeam = 3, TotalPlayers = 6 },
	["5v5"] = { Id = "5v5", DisplayName = "5 x 5", PerTeam = 5, TotalPlayers = 10 },
	["7v7"] = { Id = "7v7", DisplayName = "7 x 7", PerTeam = 7, TotalPlayers = 14 },
}
Config.MODE_ORDER = { "FREE", "3v3", "5v5", "7v7" } -- ordem de exibição na tela

-- ===== TIMES MENORES QUE O NOMINAL (⚠️ v11) =====
-- PEDIDO: "já que o GK não é obrigatório, o 7v7 pode se tornar 7v6, ou
-- 6v6, e o 5v5 pode virar 5v4 ou 4v4, e o 3v3 pode ser 3v2 e 2v2, se
-- demorar muito e nenhum GK entrar, puxe uma partida 2v2 ou 2v3 mesmo."
-- Duas etapas de "relaxamento" no fechamento de partida (ver Matchmaker.
-- legacy.luau -> tryCloseMatch/tryCloseLastResort), cada uma só entra em
-- ação depois de o grupo MAIS ANTIGO do pool esperar tempo suficiente —
-- nunca fecha torto quando dá pra fechar cheio rapidinho:
--   1) MATCH_FULL_WAIT_SECONDS: até aqui, só fecha com os DOIS times no
--      tamanho NOMINAL (mode.PerTeam) — comportamento de sempre.
--   2) depois disso, tryCloseMatch passa a aceitar times com 1 a menos
--      (mode.PerTeam - 1) TAMBÉM, cada time buscando o seu de forma
--      independente — é isso que permite fechar torto tipo 7v6 (não só
--      6v6 simétrico), exatamente como pedido.
--   3) MATCH_LAST_RESORT_WAIT_SECONDS (bem mais tarde, sempre menor que
--      GROUP_STUCK_REQUEUE_AFTER pra não perder a corrida): tryCloseMatch
--      desiste de tentar fechar OS DOIS times com o mesmo tamanho-alvo —
--      fecha com QUALQUER sobra que já tiver esperando, distribuída greedy
--      (igual Sala Livre), mesmo desbalanceado (2v3), contanto que os dois
--      lados batam pelo menos MATCH_LAST_RESORT_MIN_PER_TEAM.
Config.MATCH_FULL_WAIT_SECONDS = 20
Config.MATCH_LAST_RESORT_WAIT_SECONDS = 60 -- < GROUP_STUCK_REQUEUE_AFTER (90s), senão o grupo volta pra fila compartilhada antes de chegar aqui
Config.MATCH_LAST_RESORT_MIN_PER_TEAM = 2 -- nunca fecha com time de 1 jogador só

-- ===== ÁREA DE MATCHMAKING =====
-- Crie uma Part em Workspace com este nome exato: translúcida,
-- CanCollide = false, CanQuery = true ("Only Query" no dropdown de
-- colisão do Studio). Não precisa de Touched nem ProximityPrompt — a
-- detecção é por overlap (workspace:GetPartsInPart), ver
-- MatchmakingZone.lua.
Config.MATCHMAKING_ZONE_NAME = "MatchmakingZone"
Config.ZONE_CHECK_INTERVAL = 0.25 -- segundos entre checagens de quem está na área

-- ===== FILA (MemoryStoreService) =====
-- Uma MemoryStoreQueue por modo, compartilhada entre TODOS os
-- servidores de Lobby ao mesmo tempo — é isso que permite juntar gente
-- de servidores diferentes na mesma partida (ver Matchmaker.lua).
Config.QUEUE_NAME_PREFIX = "MatchmakingQueue_"
Config.QUEUE_INVISIBILITY_TIMEOUT = 30 -- (GetQueue) tempo que um item lido fica invisível pra outros servers antes de reaparecer, se não for removido a tempo
Config.QUEUE_ITEM_EXPIRATION = 3600     -- (AddAsync) expira sozinho depois de 1h parado na fila, evita fila "fantasma"
Config.QUEUE_POLL_INTERVAL = 3          -- de quanto em quanto tempo cada Lobby tenta ler novos itens da fila
Config.QUEUE_READS_PER_CYCLE = 12       -- máximo de itens novos puxados da fila por ciclo (cobre 7v7 = até 14 grupos de 1, com folga em duas rodadas)
Config.GROUP_STUCK_REQUEUE_AFTER = 90   -- se um grupo capturado por este server fica esse tempo sem completar partida, volta pra fila compartilhada (outro server pode ter a peça que falta)

-- ===== GRUPO / PARTY =====
-- Até 7 pessoas no grupo (o maior modo, 7v7). Uma party de 6 ou 7 só
-- consegue fechar partida no modo 7v7 (não dá pra dividir um grupo ao
-- meio pra caber num 5v5 — ver findExactSubset em Matchmaker.lua); Sala
-- Livre aceita qualquer tamanho de grupo.
Config.MAX_PARTY_SIZE = 7
Config.PARTY_INVITE_TIMEOUT = 20

-- ===== MESSAGING (avisa TODOS os Lobbies quando uma partida fecha) =====
-- Necessário porque o server que MONTA a partida (lendo a fila
-- compartilhada) pode não ter, ele mesmo, os Player de todo mundo que
-- entrou nela — cada Player só existe de verdade no server onde a
-- pessoa está fisicamente. Ver Matchmaker.lua.
Config.MATCH_FOUND_TOPIC = "Matchmaking_MatchFound"

-- ===== REMOTES =====
local function getOrCreateRemote(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local remotesFolder = ReplicatedStorage:FindFirstChild("MatchmakingRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "MatchmakingRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

-- ===== LOJA =====
-- Slots: por padrão o jogador só tem 1 slot de personagem destravado
-- (ver PlayerDataManager.lua: UnlockedSlots nasce em 1, não mais 3) —
-- os outros 4 se destravam UM DE CADA VEZ comprando este item, sempre
-- na ordem (não dá pra "pular" pro slot 4 sem ter o 2 e o 3). O preço
-- sobe a cada slot destravado: Costs[1] é o preço de destravar o slot
-- 2 (quando UnlockedSlots == 1), Costs[2] o preço do slot 3, etc.
Config.SHOP = {
	UnlockSlot = {
		Id = "UnlockSlot",
		Name = "Destravar Personagem",
		Costs = { 750, 1500, 3000, 6000 }, -- preço pra ir de 1→2, 2→3, 3→4, 4→5 slots
	},
	-- Reinicia um personagem à escolha (o jogador escolhe o slot): sorteia
	-- Sorte/atributos/posição de novo, nível volta pro 1. O nome
	-- do slot é preservado (não força re-nomear).
	ResetSlot = {
		Id = "ResetSlot",
		Name = "Reiniciar Personagem",
		Cost = 500,
	},
	-- Roll (Pulso/Instinto): compra 1 crédito de roll gastando dinheiro do
	-- jogo (ver RollServer.lua/ShopServer.lua). Repetível — não tem "maxed
	-- out" como o UnlockSlot. Preço calibrado com Config.REWARDS (Game,
	-- FootballConfig.lua): MVP básico (participação + vitória + bônus de
	-- MVP, sem gols/assist extra) rende ~1000, ou seja ~5 rolls — partida
	-- melhor (gols/assistências/desarmes) rende mais que isso.
	Roll = {
		Id = "BuyRoll",
		Name = "Roll (Hissatsu/Arma)",
		Cost = 200,
	},
}

-- ===== LOJA — CATÁLOGO POR CATEGORIA (v2) =====
-- Pedido do usuário: separar a loja por categoria (abas), cada uma com
-- vários itens. UnlockSlot/ResetSlot (acima) e Roll (RollServer.lua)
-- continuam com sua própria lógica dedicada (preço dinâmico, escolher
-- slot, etc.) — este catálogo aqui é pros itens NOVOS, todos com a MESMA
-- lógica genérica de compra (ver ShopServer.legacy.luau: BuyCatalogItem).
Config.SHOP.Categories = {
	{ Id = "Cosmeticos", Name = "Cosméticos" },
	{ Id = "Conveniencia", Name = "Conveniência" },
	{ Id = "Boosts", Name = "Boosts" },
	{ Id = "Robux", Name = "Robux" },
}

-- Type decide o comportamento da compra (ver ShopServer.legacy.luau):
--   "Cosmetic"   — compra única (não reduplica), fica em OwnedCosmetics,
--                  pode ser equipado/desequipado (1 por Slot — ver
--                  campo Slot abaixo: só um item de cada Slot fica
--                  equipado por vez). NÃO tem efeito visual pronto (o
--                  jogo não tem os assets/partículas ainda) — compra e
--                  equipa ficam salvos de verdade; a parte visual (criar
--                  o ParticleEmitter da aura, o efeito no gol, etc.) fica
--                  pra você adicionar no Studio quando tiver os assets,
--                  lendo Player:GetAttribute("Equipped"..Slot).
--   "Consumable" — repetível, aplica um efeito na hora (RollPack soma
--                  RollCredits, MysteryBox sorteia uma recompensa) e
--                  não fica "possuído" depois.
--   "Boost"      — repetível, estende um timestamp de expiração em
--                  playerData.Boosts (ver PlayerDataManager.legacy.luau).
Config.SHOP.Items = {
	-- ===== COSMÉTICOS =====
	{ Id = "GoalEffect_Fireworks", Category = "Cosmeticos", Slot = "GoalEffect", Name = "Efeito de Gol: Fogos de Artifício", Cost = 800, Type = "Cosmetic" },
	{ Id = "GoalEffect_Confetti", Category = "Cosmeticos", Slot = "GoalEffect", Name = "Efeito de Gol: Confete", Cost = 800, Type = "Cosmetic" },
	{ Id = "GoalEffect_Flash", Category = "Cosmeticos", Slot = "GoalEffect", Name = "Efeito de Gol: Flash Colorido", Cost = 800, Type = "Cosmetic" },
	{ Id = "Aura_Gold", Category = "Cosmeticos", Slot = "Aura", Name = "Aura Dourada", Cost = 1200, Type = "Cosmetic" },
	{ Id = "Aura_Blue", Category = "Cosmeticos", Slot = "Aura", Name = "Aura Azul", Cost = 1000, Type = "Cosmetic" },
	{ Id = "Aura_Red", Category = "Cosmeticos", Slot = "Aura", Name = "Aura Vermelha", Cost = 1000, Type = "Cosmetic" },
	{ Id = "Emote_Dance", Category = "Cosmeticos", Slot = "Emote", Name = "Emote: Dança da Vitória", Cost = 400, Type = "Cosmetic" },
	{ Id = "Emote_Jump", Category = "Cosmeticos", Slot = "Emote", Name = "Emote: Salto de Comemoração", Cost = 400, Type = "Cosmetic" },
	{ Id = "Emote_Bow", Category = "Cosmeticos", Slot = "Emote", Name = "Emote: Reverência", Cost = 400, Type = "Cosmetic" },
	{ Id = "NameColor_Gold", Category = "Cosmeticos", Slot = "NameColor", Name = "Cor de Nome: Dourado", Cost = 600, Type = "Cosmetic" },
	{ Id = "NameColor_Red", Category = "Cosmeticos", Slot = "NameColor", Name = "Cor de Nome: Vermelho", Cost = 500, Type = "Cosmetic" },
	{ Id = "NameColor_Cyan", Category = "Cosmeticos", Slot = "NameColor", Name = "Cor de Nome: Azul Neon", Cost = 500, Type = "Cosmetic" },
	{ Id = "Tag_Artilheiro", Category = "Cosmeticos", Slot = "Tag", Name = "Tag Especial: Artilheiro", Cost = 900, Type = "Cosmetic" },
	{ Id = "Tag_Muralha", Category = "Cosmeticos", Slot = "Tag", Name = "Tag Especial: Muralha", Cost = 900, Type = "Cosmetic" },
	{ Id = "Tag_Lenda", Category = "Cosmeticos", Slot = "Tag", Name = "Tag Especial: Lenda", Cost = 1500, Type = "Cosmetic" },
	{ Id = "Frame_Gold", Category = "Cosmeticos", Slot = "Frame", Name = "Moldura de Avatar: Ouro", Cost = 700, Type = "Cosmetic" },
	{ Id = "Frame_Diamond", Category = "Cosmeticos", Slot = "Frame", Name = "Moldura de Avatar: Diamante", Cost = 1400, Type = "Cosmetic" },
	{ Id = "Title_Capitao", Category = "Cosmeticos", Slot = "Title", Name = "Título: Capitão", Cost = 1000, Type = "Cosmetic" },
	{ Id = "ChatColor_Custom", Category = "Cosmeticos", Slot = "ChatColor", Name = "Cor de Chat Customizada", Cost = 800, Type = "Cosmetic" },

	-- ===== CONVENIÊNCIA (junto com "progressão/utilidade", que tinha
	-- pouca coisa — pedido do usuário: "poe junto de conveniência, coloca
	-- um nome mais geral pros dois") =====
	-- Token de Elemento: re-rola o elemento do slot ATIVO pra um novo
	-- (aleatório entre Config.ELEMENTS, pode repetir o mesmo de novo — SEM
	-- exclusão do atual, igual um roll normal) — ver ShopServer.legacy.luau,
	-- Effect="RerollElement". A resposta da compra já indica na hora qual
	-- elemento você pegou (ShopClient.local.luau mostra o resultado).
	{ Id = "ElementToken", Category = "Conveniencia", Name = "Token de Elemento", Cost = 350, Type = "Consumable", Effect = "RerollElement" },
	{ Id = "RollPack_5", Category = "Conveniencia", Name = "Pacote de 5 Rolls", Cost = 900, Type = "Consumable", Effect = "RollPack", Amount = 5 }, -- 5x avulso custaria 1000 (Config.SHOP.Roll.Cost * 5)
	{ Id = "RollPack_10", Category = "Conveniencia", Name = "Pacote de 10 Rolls", Cost = 1700, Type = "Consumable", Effect = "RollPack", Amount = 10 }, -- 10x avulso custaria 2000
	{ Id = "MysteryBox", Category = "Conveniencia", Name = "Baú Misterioso", Cost = 300, Type = "Consumable", Effect = "MysteryBox" },

	-- ===== BOOSTS (sempre progressão — nunca força/precisão em partida,
	-- pra não virar pay-to-win) =====
	{ Id = "Boost_XP_1h", Category = "Boosts", Name = "Boost de XP — 2x por 1 hora", Cost = 300, Type = "Boost", Effect = "XP", DurationSeconds = 3600 },
	{ Id = "Boost_XP_24h", Category = "Boosts", Name = "Boost de XP — 2x por 24 horas", Cost = 1200, Type = "Boost", Effect = "XP", DurationSeconds = 86400 },
	{ Id = "Boost_Money_1h", Category = "Boosts", Name = "Boost de Dinheiro — 2x por 1 hora", Cost = 350, Type = "Boost", Effect = "Money", DurationSeconds = 3600 },
	{ Id = "Boost_Money_24h", Category = "Boosts", Name = "Boost de Dinheiro — 2x por 24 horas", Cost = 1400, Type = "Boost", Effect = "Money", DurationSeconds = 86400 },
	{ Id = "Boost_Combo_1h", Category = "Boosts", Name = "Boost Combo (XP + Dinheiro) — 2x por 1 hora", Cost = 550, Type = "Boost", Effect = "Combo", DurationSeconds = 3600 },
	{ Id = "Boost_Luck_5Rolls", Category = "Boosts", Name = "Boost de Sorte no Roll — próximas 5 rolagens", Cost = 500, Type = "Boost", Effect = "Luck", Amount = 5 },
	{ Id = "Boost_ExtraQuest_24h", Category = "Boosts", Name = "Missão Extra — +1 ativa por 24 horas", Cost = 600, Type = "Boost", Effect = "ExtraQuest", DurationSeconds = 86400 },
}

-- ===== LOJA — PRODUTOS DE ROBUX (v2) =====
-- Cada um precisa de um Developer Product criado manualmente no Studio
-- (Monetização > Developer Products > + Create) — NÃO dá pra criar por
-- script, mesma limitação/instruções do Config.ROBUX_ROLL_PRODUCT_ID
-- acima. Enquanto ProductId ficar 0, aquele produto avisa no console e
-- fica desativado (não quebra o resto da Loja).
--
-- PASSOS (você, no Studio, um de cada vez):
-- 1. Crie o Developer Product com o preço em Robux que quiser pra ele.
-- 2. Copie o ProductId numérico.
-- 3. Cole aqui embaixo, no lugar do 0 correspondente.
-- ⚠️ v76 — IDs DE VERDADE (pedido do usuário, colados diretamente).
Config.SHOP.RobuxProducts = {
	{ Id = "RobuxMoney_Small", Name = "Pacote de Dinheiro Pequeno", ProductId = 3271846531, GrantMoney = 8000 },
	{ Id = "RobuxMoney_Medium", Name = "Pacote de Dinheiro Médio", ProductId = 3714896695, GrantMoney = 20000 },
	{ Id = "RobuxMoney_Large", Name = "Pacote de Dinheiro Grande", ProductId = 3714896810, GrantMoney = 40000 },
	{ Id = "RobuxMoney_Giant", Name = "Pacote de Dinheiro Gigante", ProductId = 3714897061, GrantMoney = 100000 },
	{ Id = "RobuxUnlockAllSlots", Name = "Destravar Todos os 5 Slots", ProductId = 3714899658, GrantUnlockAllSlots = true },
	-- NOTA: "Roll de Robux" já existe e não foi duplicado aqui — continua
	-- na própria tela de Roll (Config.ROBUX_ROLL_PRODUCT_ID acima, ver
	-- RollServer.lua/RollClient.lua).
}

-- ⚠️ v76 — SLOTS EXTRAS DE HISSATSU/ARMA COMPRADOS COM ROBUX.
-- PEDIDO: "inclua mais um slot pra cada um que será comprado com robux."
-- Cada um é um Developer Product À PARTE (não Gamepass — Gamepass é
-- posse permanente comprada 1x fora do fluxo de ProcessReceipt de
-- consumível; Developer Product é o que já usamos em todo o resto da
-- loja, então mantém a MESMA arquitetura de recibo em vez de introduzir
-- um segundo sistema de compra só pra isso). RollServer.legacy.luau
-- credita playerData.ExtraPulseSlot/ExtraInstinctSlot = true ao processar.
Config.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID = 3714898904  -- "Slot Hissatsu"
Config.ROBUX_EXTRA_INSTINCT_SLOT_PRODUCT_ID = 3714899067 -- "Slot Arma"

-- ===== ROLL COM ROBUX =====
-- Cada roll pago com Robux custa 40 Robux DE VERDADE — isso só é possível
-- através de um Developer Product (ProductId numérico), que só existe
-- depois de criado manualmente no Creator Hub/Studio (Monetização >
-- Developer Products > + Create). NÃO dá pra criar isso por script.
--
-- PASSOS (você, no Studio):
-- 1. Crie o Developer Product com preço 40 Robux.
-- 2. Copie o ProductId numérico dele.
-- 3. Cole aqui embaixo, no lugar do 0.
-- Enquanto ROBUX_ROLL_PRODUCT_ID for 0, o botão de roll de Robux avisa
-- no console/chat que ainda não foi configurado, em vez de quebrar.
Config.ROBUX_ROLL_PRODUCT_ID = 3433596394

-- ⚠️ v76 — PESOS PRÓPRIOS PRO ROLL DE ROBUX (pedido do usuário: "aumente
-- as chances de vir coisas lendárias e míticas. deixe impossível de vir
-- algo comum, ou raro, e chance de vir épica é de 30%, lendária 40% e
-- mítica 30%.").
--
-- O roll comprado com DINHEIRO continua usando PulseInstinctData.
-- RarityWeights (65/25/7/2.5/0.5) — só o roll pago com ROBUX DE VERDADE
-- usa esta tabela. Precisa ser tratado à parte porque RollCredits hoje é
-- um contador só, sem saber de onde veio cada crédito — ver
-- RollCreditsRobux (NumberValue separada) em RollServer.legacy.luau.
Config.ROBUX_ROLL_RARITY_WEIGHTS = {
	Common = 0,
	Rare = 0,
	Epic = 30,
	Legendary = 40,
	Mythic = 30,
}

Config.Remotes = {
	-- Servidor -> Cliente: abre/fecha a tela ao entrar/sair da área
	SetMatchmakingScreenOpen = getOrCreateRemote(remotesFolder, "SetMatchmakingScreenOpen"),

	-- Cliente -> Servidor: entrar/sair da fila de um modo (só o líder do grupo pode chamar)
	JoinQueue = getOrCreateRemote(remotesFolder, "JoinQueue"),
	LeaveQueue = getOrCreateRemote(remotesFolder, "LeaveQueue"),
	-- Servidor -> Cliente: status da fila desta pessoa/grupo
	UpdateQueueStatus = getOrCreateRemote(remotesFolder, "UpdateQueueStatus"),

	-- Convite de grupo (duo/party)
	InviteToParty = getOrCreateRemote(remotesFolder, "InviteToParty"),
	ReceivePartyInvite = getOrCreateRemote(remotesFolder, "ReceivePartyInvite"),
	RespondToPartyInvite = getOrCreateRemote(remotesFolder, "RespondToPartyInvite"),
	LeaveParty = getOrCreateRemote(remotesFolder, "LeaveParty"),
	-- Servidor -> Cliente: estado atual do grupo (membros, quem é líder)
	UpdatePartyState = getOrCreateRemote(remotesFolder, "UpdatePartyState"),

	-- Servidor -> Cliente: partida encontrada, vai teleportar em instantes
	MatchFound = getOrCreateRemote(remotesFolder, "MatchFound"),
}

-- ===== ANIMAÇÕES DO LOBBY =====
-- Mesmo espírito do Config.ANIMATIONS do FootballConfig.lua (place Game):
-- é AQUI que entram os AnimationId (rbxassetid://...) das animações do
-- Lobby que ainda não são por-linha-de-diálogo (ver NpcAnimationId/
-- PlayerAnimationId em DialogueData.luau pras animações específicas de
-- cada fala de NPC — essas continuam lá). Preencha as chaves abaixo
-- conforme as novas animações forem chegando.
--
-- ⚠️ NOVO: mesmo bug/fix do place Game — colar só o NÚMERO sem o prefixo
-- "rbxassetid://" quebra o Animate do personagem inteiro (silenciosamente
-- — a animação simplesmente não roda). Aceita os dois jeitos.
function Config.NormalizeAnimationId(id)
	if type(id) ~= "string" or id == "" then
		return ""
	end
	if id:match("^rbxassetid://%d+$") then
		return id
	end
	if id:match("^%d+$") then
		return "rbxassetid://" .. id
	end
	return id
end

Config.ANIMATIONS = {
	-- Idle = "",
	-- Emote = "",

	-- ⚠️ NOVO: animações de MOVIMENTO (PEDIDO: "eu quero colocar animação
	-- de andar, correr, pular, etc..."). Mesmo espírito da versão no
	-- FootballConfig.lua (place Game) — substituem as animações padrão do
	-- Roblox dentro do "Animate" de cada personagem (ver
	-- LobbyMovementAnimations.legacy.luau). "" = mantém a animação padrão
	-- do Roblox pra esse estado.
	Idle = "",
	Walk = "rbxassetid://89188098199704",
	Run = "",
	Jump = "",
	Fall = "",
}

-- ===== ELEMENTOS =====
-- ⚠️ SINCRONIA OBRIGATÓRIA: essa lista TEM que ficar IDÊNTICA ao
-- Config.ELEMENTS do FootballConfig.lua (place Game) — mesmo espírito do
-- Config.SYNC_NOTE acima (TEAM_NAMES). Sorteado por slot na criação (ver
-- CharacterCreator.new em PlayerDataManager.legacy.luau) e re-rolável com
-- o "Token de Elemento" da Loja (Config.SHOP.Items, Effect=
-- "RerollElement"). Se o elemento do PERSONAGEM bater com o elemento do
-- PULSO usado, ganha +10% de potência (Config.PULSE_ELEMENT_SELF_MATCH_-
-- MULT, aplicado no place Game — ver PulseController.legacy.luau).
Config.ELEMENTS = { "Natureza", "Fogo", "Vento", "Luz", "Void" }

-- PEDIDO: "o elemento void e o elemento light são mais raros, enquanto os
-- outros tem a mesma raridade, o void e light tem só 0.1% de chance de
-- pegar." — Natureza/Fogo/Vento dividem o resto (99.8%) igualmente entre
-- si (~33.27% cada). Ver rollElement (PlayerDataManager.legacy.luau) e o
-- reroll do Token de Elemento (ShopServer.legacy.luau) — os DOIS usam
-- essa mesma tabela, pra manter a raridade consistente em qualquer lugar
-- que o elemento é sorteado.
Config.ELEMENT_RARE_CHANCE = 0.001 -- 0.1% cada
Config.ELEMENT_RARE_ELEMENTS = { "Void", "Luz" }

-- Função ÚNICA de sorteio (evita duplicar a lógica de raridade em dois
-- lugares e ela sair de sincronia — mesma classe de bug já vista antes
-- neste projeto com config duplicada). Usada tanto na criação do slot
-- (PlayerDataManager.legacy.luau) quanto no reroll do Token de Elemento
-- (ShopServer.legacy.luau).
function Config.RollElement()
	local rareSet = {}
	for _, name in ipairs(Config.ELEMENT_RARE_ELEMENTS) do
		rareSet[name] = true
	end

	local roll = math.random() -- float em [0, 1)
	local cumulative = 0
	for _, name in ipairs(Config.ELEMENT_RARE_ELEMENTS) do
		cumulative += Config.ELEMENT_RARE_CHANCE
		if roll < cumulative then
			return name
		end
	end

	-- Não caiu em nenhum raro: distribui o resto igualmente entre os
	-- elementos comuns (todos os que não estão em ELEMENT_RARE_ELEMENTS).
	local commonElements = {}
	for _, name in ipairs(Config.ELEMENTS) do
		if not rareSet[name] then
			table.insert(commonElements, name)
		end
	end
	return commonElements[math.random(1, #commonElements)]
end

-- ===== SONS DO LOBBY =====
-- Espaço reservado pros sons de passos/pulo do Lobby (mesmo pedido do
-- Game — "quero mudar o som de passos, remova-o por enquanto, mas
-- coloque um espaço pra eu poder alterar, junto com o de pulo também").
-- Ver LobbyMovementSounds.legacy.luau: silencia os dois (SoundId = "")
-- em todo CharacterAdded. "" = mudo; troque por um rbxassetid://... aqui
-- quando tiver o som novo.
Config.SOUNDS = {
	Footstep = "",
	Jump = "",
}

-- ⚠️ v68 — LIMITE DO MAPA (ver LobbyBarrier.legacy.luau).
-- PEDIDO: "ajustar as coisas pra não poder sair do limite do mapa."
-- A pasta InvisibleWall existia no Workspace mas estava VAZIA — o limite
-- nunca tinha sido construído. As paredes agora são geradas por código a
-- partir do próprio piso, então acompanham qualquer expansão do lobby.
-- ⚠️ v70 — A BARREIRA NÃO É MAIS DERIVADA DO "Chão".
-- PEDIDO: "coloca uma barreira invisível em volta de onde não tem árvore
-- pra o pessoal não poder passar. O limite é até as árvores. Chão pra não
-- se matar no void, e parede pra eles não se matarem no void."
--
-- A versão anterior media as paredes pela Part "Chão". Isso deixou de
-- servir quando a floresta passou a existir: as árvores vão até X -342 e
-- Z 1423, ou seja, PARA FORA do Chão original (X -318.8..10.5, Z 582..1341).
-- Derivando do Chão, a parede cortaria a floresta no meio — o jogador
-- bateria numa parede invisível olhando pra árvores do outro lado.
--
-- Agora o limite é escrito aqui e o piso foi estendido pra acompanhá-lo
-- (ver LobbyExpansao.ChaoExtra, as três faixas em volta do Chão). Os dois
-- vêm do MESMO número, então não tem como um passar do outro e sobrar
-- vão sem chão — que era a origem dos buracos.
Config.BARRIER_BOUNDS = {
	MinX = -360, MaxX = 120,
	MinZ = 582,  MaxZ = 1450,
}

-- 300 e não 90: dá pra subir nos morros da fileira de dentro (até ~80
-- studs) e, de cima deles, uma parede de 90 ficaria na altura do joelho.
Config.BARRIER_HEIGHT = 300
Config.BARRIER_THICKNESS = 8   -- grossa o bastante pra ninguém atravessar correndo
Config.BARRIER_MARGIN = 0      -- os limites acima já são a borda final
-- Abaixo desta altura o jogador é considerado "caiu do mapa" e volta pro
-- spawn. nil = calcula sozinho (60 studs abaixo do piso).
Config.BARRIER_FALL_Y = nil



return Config
