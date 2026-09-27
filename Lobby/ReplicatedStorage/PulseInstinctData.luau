--[[
	PulseInstinctData (ModuleScript)
	Existe IDÊNTICO nos dois places:
		Game/ReplicatedStorage/PulseInstinctData.luau   (aplica os efeitos)
		Lobby/ReplicatedStorage/PulseInstinctData.luau  (sorteia no Roll)
	Se editar um, copie pro outro — não tem require cross-place no Roblox.

	============================================================
	⚠️ v5 — RECOMEÇO ENXUTO (pedido do usuário: "tem MUITA coisa e está
	fora do meu controle, é difícil testar tudo quando tudo dá problema...
	remova todos os pulsos... mantenha apenas 10 instintos, pra eu testar
	individualmente cada situação").

	O QUE MUDOU (v5):
	1. PULSOS: a lista ficou VAZIA por um tempo (⚠️ v6: não fica mais —
	   ver Data.Pulses mais abaixo, 20 Pulsos "Hissatsu" (15 da v6 + 5 de
	   drible da v7), com QTE próprio (Tap/TimingBar/MashAD), pra brincar
	   com os amigos). Os
	   executores de ação do sistema antigo (_G.PulseExecuteShot,
	   _G.PulseExecuteDribbleMove, _G.PulseExecuteHeader,
	   _G.PulseExecuteAerialControl, _G.PulseExecuteTackle) continuam
	   sendo reaproveitados tanto pelos Pulsos quanto pelas "ativas" dos
	   Instintos (ver campo Ativa).
	2. INSTINTOS: 10, e só 10. Cada um é um INSTINTO no sentido do Blue Lock —
	   uma coisa só, que o jogador entende de cara e dá pra testar
	   isolada. O nome disso no jogo é Instinto, e só Instinto. O que
	   valia a pena dos Pulsos virou condição de Instinto.
	3. AURA: cada Instinto tem uma Cor. Quando a condição dele está
	   cumprida, o jogador ACENDE nessa cor, e todo mundo em campo vê
	   (ver showAura em InstinctController.legacy.luau). É o feedback de
	   "meu instinto está ativo AGORA" sem precisar olhar HUD nenhum.

	ANATOMIA DE UM INSTINTO:
		Name         — nome mostrado
		Rarity       — "Common"|"Rare"|"Epic"|"Legendary"|"Mythic"
		Cor          — Color3 da aura quando a condição está ativa
		Description  — texto do jogador (a tela de Roll lê daqui)
		Passiva      — o que ele faz sempre que a condição bate (texto)
		Ativa        — texto da ação automática, quando tem uma
		Trigger      — quando o jogo pergunta por esse instinto:
		               "KickAtGoal"    — no instante de um chute a gol
		               "KickAtTeammate"— no instante de um passe
		               "Tackle"        — no instante de um carrinho
		               "Header"        — no instante de um cabeceio
		               "Dive"          — no instante do mergulho do goleiro
		               "DribbleMove"   — no instante de uma finta
		               "SetPiece"      — em cobrança de bola parada
		               "Instant"       — contínuo, reavaliado a cada 0.25s
		               "Botao"         — NÃO é avaliado sozinho: só acontece
		                                 quando o jogador aperta a tecla do
		                                 campo Tecla (ver abaixo)
			Tecla        — (opcional) "R". Instinto com Tecla NÃO dispara
			               sozinho: o jogador aperta R, o servidor checa a
			               Condition na hora e, se bater, roda a Ativa. R é a
			               MESMA tecla pra goleiro e jogador de linha, e é a
			               única tecla de Instinto que existe — Q e E ficaram
			               livres de propósito (o goleiro usa Q/E nos
			               mergulhos diagonais, então antes havia conflito e
			               ele ficava com uma tecla a menos).
		Condition    — o que precisa ser verdade (números). Nos triggers
		               de evento vem do BallController; nos "Instant"
		               vem de _G.GetInstinctFieldContext (v5).
		               MaxDistanceToGoal / MinDistanceToGoal /
		               MaxDistanceToOwnGoal / TargetMaxDistanceToGoal /
		               MaxSecondsAfterReceive / MaxSecondsAfterSprintStart /
		               NoOpponentAheadRadius /
		               LooseBallOpponentRadius / MaxDistanceOpponent /
		               AttackingHalf / NearBylineMaxDistance /
		               LastSecondsOfHalf / TeamLosing / TeamLeading /
		               RecoveredInOwnHalf / IsSetPiece /
		               ⚠️ v5.4 — RequireOutsideEnemyArea (só vale FORA da
		               grande área adversária — ver GKAreaUtil.IsPositionInArea)
		               / RequireOwnArea (só vale DENTRO da própria grande
		               área) / RequireMaxCharge (só vale se o chute foi
		               carregado até a força máxima) / GambleChance +
		               GambleIntervalSeconds + GambleDurationSeconds (ver
		               Instinto "Apostador" abaixo — a cada
		               GambleIntervalSeconds segundos, GambleChance de
		               "ganhar" e o Effect valer por GambleDurationSeconds)
		Effect       — o que muda quando a condição bate:
		               ForceMult, CurveMult, AimDeviationMult, ChanceAdd,
		               ChanceSet, SpeedMult, StaminaRegenMult,
		               AnkleRangeAdd, PickupRadiusAdd, DiveRadiusAdd,
		               HeaderForceMult, IgnoreGKChance, OwnCooldownMult,
		               AllBoost, Duration
		AtivaAction  — (opcional) AÇÃO automática disparada quando a
		               condição bate: "DribbleMove" | "Header" |
		               "AerialControl" | "Tackle" | "Shot" | "Pass".
		               Roda pelos executores do BallController, que já
		               checam sozinhos se a jogada é possível (tem bola no
		               ar? tem adversário no alcance?) — se não for, não
		               acontece nada, sem erro.
		AtivaEffect  — tabela de efeito passada pra essa ação
		AtivaCooldown— segundos entre duas ativações (obrigatório, senão
		               um instinto contínuo dispararia 4x por segundo)
		Passive      — (opcional) efeito visual passivo no CLIENTE:
		               "TrajectorySight" (mostra onde a bola vai cair)
		               "Metavision"      (trajetória da bola até onde ela vai
		                                 parar + o maior espaço aberto entre
		                                 os jogadores, marcado no chão)
		RoleRequired — (opcional) "GK"

	COMO TESTAR UM DE CADA VEZ: DebugAbilitySelector.legacy.luau
	(ServerScriptService) permite forçar o Instinto equipado sem depender
	do sorteio.

	⚠️ v5.4 — AJUSTES PEDIDOS PELO USUÁRIO:
	1. "Fluxo" saiu (só empilhava atributo, sem carregar Instinct Mode
	   nenhum). Entrou "Apostador" (Mythic): a cada
	   GambleIntervalSeconds, uma jogada de sorte com GambleChance de
	   acertar um bônus grande por GambleDurationSeconds — literalmente
	   uma aposta, e cada acerto carrega o medidor de Instinct Mode que
	   nem qualquer outro Instinto "Instant".
	2. "Ego do Rei" só valia de qualquer distância/lugar (até dentro da
	   área). Agora exige: fora da própria... digo, da área ADVERSÁRIA
	   (RequireOutsideEnemyArea), a no máximo 50 de distância do gol (pra
	   um passe de campo inteiro não contar como "chute a gol"), e só se
	   o chute foi carregado até a força máxima (RequireMaxCharge).
	3. "Sentinela" agora exige estar DENTRO da própria área
	   (RequireOwnArea), no lugar do raio de 20 studs solto.
	4. "Ginga": a Ativa separada (AtivaAction) tinha um bug —
	   ela rodava a finta duas vezes (uma pela Ativa, outra pela finta
	   manual que o jogador já tinha apertado), e a segunda sobrescrevia
	   a primeira sem herdar o stun bonus. Virou só Effect: toda finta no
	   campo de ataque agora SEMPRE atordoa quem estava perto (garantido,
	   não só quando a Ativa "sorteava" rodar), e o stun dura mais.
	5. "Metavisão" ganhou uma terceira visão: enquanto você segura o
	   botão de chute carregando a força, mostra a trajetória prevista a
	   partir da sua mira atual (não só reage à bola já em movimento).
	6. "Pique": +20% (era +30%), útil por 1s de corrida
	   (era 1.5s) com 4s de descanso (era 3s).
	7. "Matador": o jogador não conseguia perceber SE/POR QUE o
	   R não fez nada — agora todo aperto sem sucesso manda o motivo pro
	   HUD do jogador (não só pro console do servidor), ver AbilityHUD.
	   Ver InstinctController.legacy.luau e AbilityHUD.local.luau.
	============================================================
]]

local Data = {}

-- ============================================================
-- ⚠️ v11 — PULSOS "HISSATSU": REWORK COMPLETO, 20 Pulsos, 4 por raridade.
--
-- POR QUE MUDOU: os 20 da v6/v7 eram 20 nomes pra ~4 efeitos. Os 8 chutes
-- eram todos ForceMult+CurveMult+AimDeviationMult com números diferentes;
-- os 5 dribles eram todos AnkleRangeAdd+DistanceMult+SelfIframe em escada;
-- as 2 arrancadas eram a mesma coisa em tamanhos diferentes. Nome de
-- adjetivo ("Chute Cometa", "Chute Vulcânico") escondia que mecanicamente
-- era tudo igual.
--
-- A REGRA NOVA (pedido do usuário: "veja como o humano pensa... que não
-- fique repetitivo"): TODO Pulso precisa responder "QUAL VERBO ele
-- adiciona ao jogo?". Se o verbo já existe em outro Pulso, ele não entra.
-- Os 20 verbos de hoje, um por Pulso, sem repetição:
--   rapidez de execução / finalizar bola aérea / sumir / empurrar /
--   atordoar o corredor / congelar o corredor / escalar com companheiros /
--   ignorar o goleiro / atravessar / devolver energia / lentificar o
--   caminho / derrubar / parar o tempo / alcance de desarme / prender à
--   distância / negar área / bloquear em grupo / perseguir / alcance de
--   guarda / segurar o insegurável.
--
-- DE ONDE VEIO: cada Pulso é uma hissatsu real de Inazuma Eleven e faz o
-- que o anime mostra (pedido explícito). O nome da técnica original está
-- no comentário de cada um.
--
-- QTE — REGRA NOVA (pedido: "drible, tackle é pra sair automático;
-- chute é pra realmente ter o timing, pra dar aquele tempo. O cara não
-- pode se mexer durante a habilidade, pra ter aquela vulnerabilidade"):
--   CHUTE      -> QTE "Tap" + o jogador fica IMÓVEL o wind-up inteiro
--                 (FreezeSelf, ver startHissatsuQTE em PulseController).
--                 Quanto mais forte a hissatsu, mais longo o preparo =
--                 mais tempo exposto a carrinho (o Prep NÃO tem iframe;
--                 só a janela de clique tem).
--   DRIBLE     -> SEM QTE. Aperta, sai na hora (usa def.Effect direto).
--   DESARME    -> SEM QTE. Idem.
--   ARRANCADA  -> única exceção: mantém o MashAD (A/D), porque a hitbox
--                 que cresce com os acertos É a identidade dela.
--   GOLEIRO    -> mantém: arma a guarda parado, e o QTE só começa quando
--                 o chute colide com ela (ver startGKGuard).
--
-- ANATOMIA (campos lidos por PulseController.legacy.luau):
--   Name         — nome mostrado E chave de save. NUNCA troque sem pôr o
--                  nome velho em Data.LegacyNames apontando pro novo.
--   Rarity       — "Common"|"Rare"|"Epic"|"Legendary"|"Mythic"
--   Element      — ⚠️ v11: AGORA PREENCHIDO EM TODOS. Um de
--                  Config.ELEMENTS ("Natureza"|"Fogo"|"Vento"|"Luz"|
--                  "Void"). Estava morto desde que foi criado: o campo
--                  existia, Config.GetElementMultiplier existia escrito, e
--                  nenhum dos 20 Pulsos preenchia — então a tabela de
--                  vantagem nunca rodava. Com o campo preenchido, um
--                  jogador que rolou o MESMO elemento do Pulso já ganha
--                  Config.PULSE_ELEMENT_SELF_MATCH_MULT de potência
--                  (getElementSelfMatchScale, PulseController).
--   Description  — texto da tela de Roll. ⚠️ v11: escrito no formato
--                  "o que acontece quando você usa", não "como é bonito" —
--                  a descrição tem que ENSINAR quando usar.
--   Action       — "Shot"|"Header"|"Tackle"|"DribbleMove"|"Buff"|"Root"
--   Cooldown     — segundos, gasto NO APERTO
--   QTE          — só chute/goleiro/arrancada (ver regra acima)
--   Bom/Perfect  — efeito conforme a qualidade do QTE
--   AirLaunchHeight — ⚠️ v14: em studs. A Hissatsu LANÇA o jogador pra
--                  cima quando o preparo acaba, e ele fica pendurado no
--                  ápice até o QTE resolver (hang time) — o chute sai do
--                  ar. Cada técnica tem a sua altura: Impulso de Maré 10
--                  (quica na onda), Cabeça de Kung Fu 12, Tornado de Fogo
--                  14 (gira no ar), Zona Morta 16, Galáxia 18. As que não
--                  têm o campo batem com os dois pés no chão, de
--                  propósito (Raio Um é rápido demais pra pular, Fúria
--                  Glacial é um chute frio e PESADO, Sumiço é rasteiro).
--                  Só o movimento mora no código — a animação do giro é
--                  colada por cima.
--   FreezeBall   — ⚠️ v14: a bola PARA no ar no instante do aperto e só
--                  volta a ter física quando o QTE resolve. Existe pra
--                  cabeçada (ver Cabeça de Kung Fu): sem isso o QTE era
--                  uma corrida contra a bola caindo, que é justamente o
--                  que não fazia sentido.
--   Effect       — usado pelos Pulsos INSTANTÂNEOS (sem QTE): é essa
--                  tabela que resolveAndExecute recebe (ver o else final
--                  de Remotes.UsePulse). Pulso instantâneo NÃO lê
--                  Bom/Perfect — não existe qualidade pra medir.
--   Scaling      — ⚠️ NOVO: fórmula de POTÊNCIA da Hissatsu por atributo.
--                  Ex.: { Kick = 0.6, Technique = 0.4 } = 60% Chute + 40%
--                  Técnica. Atributos aceitos: Physical, Kick,
--                  DribbleSkill, Speed, Technique (pesos somando 1).
--                  Energy e Stamina NÃO entram: Energia é o CUSTO, não a
--                  força (PEDIDO: "Não fazer mais Energia = Hissatsu mais
--                  forte"). A nota ponderada escala a força do chute, o
--                  tamanho/duração dos efeitos de área e os cliques extras
--                  do QTE (ver Config.GetHissatsuAttributeRating). A
--                  potência BASE continua sendo ForceMult/raridade/raios de
--                  cada uma. Sem o campo, usa o atributo da categoria.
--   EnergyCost   — ⚠️ NOVO (opcional): custo de energia próprio; sem ele,
--                  Config.PULSE_ENERGY_COST_BY_RARITY[Rarity].
--
-- CHAVES DE EFEITO NOVAS (v11, implementadas em PulseController):
--   CorridorStun/CorridorFreeze = { Width, Duration }
--                  aplica no CORREDOR entre o jogador e a mira, não num
--                  raio em volta do próprio jogador. É a diferença entre
--                  "explodi no meu pé" e "quem entrou na frente da bola
--                  se queimou".
--   TimeStopRadius/TimeStopDuration
--                  congela TODO adversário no raio (Hora do Céu).
--   RootRadius/RootDuration + Action="Root"
--                  prende o carregador da bola no lugar, À DISTÂNCIA, sem
--                  contato e sem roubar a bola.
--   ZoneSlowRadius/ZoneSlowDuration/ZoneSlowMult
--                  deixa uma ZONA no chão que lentifica quem entrar, e
--                  continua lá depois que você saiu.
--   AlliesScale = { Radius, PerAlly, Max }
--                  a potência escala com quantos COMPANHEIROS estão por
--                  perto na hora. É a hissatsu de jogar com os amigos.
--   EnergyRefund — devolve energia do pool ao dar certo (o pool só
--                  reenche no kickoff, então isso é economia de verdade).
--   VanishSeconds— a bola fica invisível por esse tempo no meio do voo.
-- ============================================================
Data.Pulses = {
	-- ========================================================
	-- CHUTES — 8. Todos Action="Shot" (menos a cabeçada), QTE "Tap",
	-- jogador IMÓVEL no wind-up.
	-- ========================================================

	-- Inazuma 1gou (イナズマ1号): a bola sobe e é acertada como um raio,
	-- reta. VERBO: rapidez de execução — é o único chute que resolve em
	-- menos de 1s de preparo, então é o único que dá pra soltar com
	-- marcador em cima. O preço é o teto de força mais baixo dos 8.
	{
		Name = "Raio Um",
		Rarity = "Common",
		Element = "Luz",
		Description = "Raio Um sai em menos de um segundo de preparo — o chute mais rápido do jogo, o único que dá pra soltar com um zagueiro em cima — mas é o mais fraco de todos em força.",
		Action = "Shot",
		Scaling = { Kick = 0.5, Technique = 0.5 }, -- ⚠️ NOVO: fórmula de potência (chute rápido e preciso)
		Cooldown = 30,
		QTE = { Kind = "Tap", PrepTime = 0.8, HitWindow = 1.6, HitCount = 3 },
		Bom = { ForceMult = 1.25, AimDeviationMult = 0.9 },
		Perfect = { ForceMult = 1.45, AimDeviationMult = 0.6 },
	},

	-- Kung Fu Head (クンフーヘッド): finalização de cabeça acrobática.
	-- VERBO: finalizar bola AÉREA — Action="Header" exige bola no ar por
	-- perto (ver actionPrecheck), então é o único Pulso que só existe
	-- quando um companheiro cruza. Hissatsu de jogar acompanhado.
	{
		Name = "Cabeça de Kung Fu",
		Rarity = "Common",
		Element = "Natureza",
		Description = "Cabeça de Kung Fu para a bola no ar perto de você, te faz saltar, e solta a cabeçada com muito mais alcance que a normal quando você acerta os cliques do QTE.",
		Action = "Header",
		Scaling = { Kick = 0.4, Physical = 0.3, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (finalização aérea: força, corpo e domínio)
		Cooldown = 30,
		-- ⚠️ v14 PEDIDO: "não dá pra fazer uma cabeçada com o Quick Time
		-- Event, não faz sentido... ou faz a bola paralisar no ar e rolar o
		-- Quick Time Event." FreezeBall trava a bola no instante do aperto
		-- (ver _G.FreezeBallForQTE em BallController), então o QTE deixa de
		-- ser uma corrida contra a bola caindo e vira o instante congelado
		-- do anime. Preparo curtíssimo: a bola já está parada, não tem o
		-- que "preparar" — o tempo todo é a cabeçada em si.
		FreezeBall = true,
		AirLaunchHeight = 12,
		QTE = { Kind = "Tap", PrepTime = 0.4, HitWindow = 1.6, HitCount = 3 },
		Bom = { HeaderForceMult = 1.5, HeaderRangeAdd = 6, HeaderMinHeight = -2, AimDeviationMult = 0.6 },
		Perfect = { HeaderForceMult = 1.9, HeaderRangeAdd = 10, HeaderMinHeight = -4, AimDeviationMult = 0.25 },
	},

	-- Kamikakushi / Teleport Shot (かみかくし): no anime a bola SOME na
	-- frente do goleiro, um torii aparece, e ela reaparece já perto da
	-- rede. VERBO: sumir — não vence o alcance do goleiro, vence a
	-- REAÇÃO dele. Quem já estiver no canto certo ainda defende.
	{
		Name = "Sumiço",
		Rarity = "Rare",
		Element = "Void",
		Description = "Sumiço faz a bola desaparecer no meio do voo e só reaparecer perto do gol — o goleiro não consegue acompanhar o que não está vendo, a menos que já esteja no canto certo por sorte.",
		Action = "Shot",
		Scaling = { Technique = 0.6, Kick = 0.4 }, -- ⚠️ NOVO: fórmula de potência (truque de execução, mais técnica que força)
		Cooldown = 45,
		QTE = { Kind = "Tap", PrepTime = 2.0, HitWindow = 2.0, HitCount = 4 },
		Bom = { ForceMult = 1.4, VanishSeconds = 0.35, IgnoreGKChance = 0.1 },
		Perfect = { ForceMult = 1.6, VanishSeconds = 0.6, IgnoreGKChance = 0.25 },
	},

	-- Tsunami Boost (ツナミブースト): o usuário surfa uma onda imaginária
	-- e salta pra bater. VERBO: empurrar — a onda joga pra trás todo
	-- mundo que estava colado em você no instante do chute, então
	-- ninguém consegue entrar no bloqueio nem disputar o rebote.
	{
		Name = "Impulso de Maré",
		Rarity = "Rare",
		Element = "Natureza",
		Description = "Impulso de Maré te faz saltar numa onda e bater no ar, empurrando pra trás qualquer marcador colado em você — usada com dois marcadores em cima, os dois voam e o rebote fica seu.",
		Action = "Shot",
		Scaling = { Kick = 0.6, Physical = 0.4 }, -- ⚠️ NOVO: fórmula de potência (empurra marcador: força de chute + corpo)
		Cooldown = 45,
		-- Salto baixo: no anime ele quica pra cima da onda, não decola.
		AirLaunchHeight = 10,
		QTE = { Kind = "Tap", PrepTime = 2.2, HitWindow = 2.2, HitCount = 4 },
		Bom = { ForceMult = 1.45, KnockbackRadius = 20, KnockbackForce = 40 },
		Perfect = { ForceMult = 1.7, KnockbackRadius = 30, KnockbackForce = 65, CurveMult = 1.2 },
	},

	-- Fire Tornado (ファイアトルネード): o corpo vira um redemoinho de
	-- chamas e a bola sai DENTRO dele. VERBO: atordoar o CORREDOR — a
	-- versão antiga atordoava em volta do próprio chutador (ou seja,
	-- queimava quem já tinha te alcançado). Agora queima quem está no
	-- caminho da BOLA: quem tentar entrar na frente é engolido.
	{
		Name = "Tornado de Fogo",
		Image = "rbxassetid://98179420325275", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Epic",
		Element = "Fogo",
		Description = "Tornado de Fogo te faz saltar, girar no ar e bater de cima, envolvendo a bola num redemoinho que queima quem estiver no CAMINHO dela (não em volta de você) — quem tentar bloquear na frente paga o preço.",
		Action = "Shot",
		Scaling = { Kick = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (potência acima de tudo)
		Cooldown = 60,
		-- ⚠️ v14 PEDIDO: "o Fire Tornado é pro cara poder pular, girar e
		-- jogar do ar". AirLaunchHeight lança o jogador no fim do preparo e
		-- o segura no ápice até o QTE resolver (ver launchIntoAir em
		-- PulseController) — a animação do giro entra por cima disso.
		AirLaunchHeight = 14,
		QTE = { Kind = "Tap", PrepTime = 2.6, HitWindow = 2.4, HitCount = 5 },
		Bom = { ForceMult = 1.7, CurveMult = 1.4, CorridorStun = { Width = 16, Duration = 0.5 } },
		Perfect = { ForceMult = 2.0, CurveMult = 1.8, CorridorStun = { Width = 24, Duration = 0.9 } },
	},

	-- Freeze Shot (フリーズショット): "congela o que estiver em volta e
	-- solta um chute frio e pesado". VERBO: congelar o CORREDOR — mesma
	-- ideia do Tornado, mas congelar trava OLHANDO (ver freezePlayer em
	-- BallController), então serve pra travar o bloqueio, não pra
	-- derrubar. Mantém o nome (já estava salvo em conta de gente).
	{
		Name = "Fúria Glacial",
		Rarity = "Epic",
		Element = "Vento",
		Description = "Fúria Glacial congela o caminho da bola — qualquer um na linha do chute trava no lugar, e se o goleiro encostar nela, congela junto e deixa o rebote livre.",
		Action = "Shot",
		Scaling = { Kick = 0.6, Technique = 0.4 }, -- ⚠️ NOVO: fórmula de potência (chute pesado e mirado)
		Cooldown = 60,
		QTE = { Kind = "Tap", PrepTime = 2.4, HitWindow = 2.2, HitCount = 5 },
		Bom = { ForceMult = 1.65, AimDeviationMult = 0.5, CorridorFreeze = { Width = 14, Duration = 0.6 } },
		Perfect = { ForceMult = 1.9, AimDeviationMult = 0.25, CorridorFreeze = { Width = 21, Duration = 1.0 } },
	},

	-- Death Zone (デスゾーン): TRÊS jogadores giram no ar em formação
	-- triangular e sincronizam o chute — o triângulo é referência ao
	-- Triângulo das Bermudas. VERBO: escalar com COMPANHEIROS. Sozinho é
	-- o pior Legendary do jogo; com 2 companheiros do lado é o melhor.
	-- É a hissatsu que só faz sentido jogando com os amigos, que é o que
	-- esse jogo é (ver AlliesScale em PulseController).
	{
		Name = "Zona Morta",
		Rarity = "Legendary",
		Element = "Void",
		Description = "Zona Morta te faz subir alto e bater de cima com força que CRESCE conforme mais companheiros estiverem perto de você no momento do chute — sozinho é fraco, com dois do lado é o mais forte fora do Mítico.",
		Action = "Shot",
		Scaling = { Kick = 0.5, Technique = 0.5 }, -- ⚠️ NOVO: fórmula de potência (chute coordenado)
		Cooldown = 90,
		-- No anime são três jogadores girando no ar em formação triangular —
		-- é a segunda maior altura do jogo, atrás só da Galáxia.
		AirLaunchHeight = 16,
		QTE = { Kind = "Tap", PrepTime = 2.8, HitWindow = 2.4, HitCount = 5 },
		-- +45% por companheiro dentro de 22 studs, até 2 (ou seja, até
		-- 1.9x em cima do ForceMult abaixo). Os companheiros que entram na
		-- conta também ganham carga de Instinto (ver applyAlliesScale).
		AlliesScale = { Radius = 55, PerAlly = 0.45, Max = 2 },
		Bom = { ForceMult = 1.3, CurveMult = 1.3 },
		Perfect = { ForceMult = 1.55, CurveMult = 1.6, AimDeviationMult = 0.3 },
	},

	-- The Galaxy (ザ・ギャラクシー): a hissatsu de maior custo do primeiro
	-- jogo (70 TP). VERBO: ignorar o goleiro — no Perfect ela passa
	-- direto, sem disputa (IgnoreGKChance = 1). O contrapeso é limpo: a
	-- guarda Mítica do goleiro (Mão do Demônio) segura mesmo assim, então
	-- os dois Míticos se anulam — pedra-papel-tesoura entre eles.
	{
		Name = "Galáxia",
		Rarity = "Mythic",
		Element = "Luz",
		Description = "Galáxia te faz subir mais alto que qualquer outra técnica e, acertando o timing, a bola atravessa o goleiro sem ele participar — só uma guarda Mítica segura isso. O preparo é o mais longo do jogo: você fica parado e exposto o tempo todo.",
		Action = "Shot",
		Scaling = { Kick = 0.6, Technique = 0.4 }, -- ⚠️ NOVO: fórmula de potência (exemplo do pedido: 60% Chute + 40% Técnica)
		Cooldown = 120,
		AirLaunchHeight = 18, -- a maior do jogo

		QTE = { Kind = "Tap", PrepTime = 3.0, HitWindow = 1.9, HitCount = 6 },
		Bom = { ForceMult = 2.0, IgnoreGKChance = 0.35 },
		Perfect = { ForceMult = 2.4, IgnoreGKChance = 1, CurveMult = 1.5 },
	},

	-- ========================================================
	-- DRIBLES — 5. TODOS INSTANTÂNEOS (sem QTE): usam def.Effect.
	-- ========================================================

	-- Zanzou / Afterimage (残像): "move-se tão rápido que deixa uma
	-- imagem, e o adversário agarra a imagem". VERBO: atravessar — quem
	-- der o carrinho pega o vulto. Distância normal, cooldown baixo: é o
	-- drible de manutenção, não o de matar jogada.
	{
		Name = "Residual",
		Rarity = "Common",
		Element = "Vento",
		Description = "Residual deixa um vulto seu pra trás por um instante — nenhum carrinho te acerta nessa janela. Distância normal de drible: serve pra escapar da pressão, não pra ganhar campo.",
		Action = "DribbleMove",
		Scaling = { DribbleSkill = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (drible de manutenção)
		Cooldown = 30,
		Effect = { SelfIframe = 0.8, AnkleRangeAdd = 2, DistanceMult = 1.1 },
	},

	-- Shippuu Dash (しっぷうダッシュ): o drible mais barato do jogo em TP.
	-- VERBO: devolver ENERGIA. O pool de energia só reenche no kickoff
	-- (ver _G.ResetPulseEnergy) — esse é o único Pulso que devolve
	-- combustível, então ele é o que mantém os outros dois vivos no
	-- segundo tempo. Ideia vinda do "Dribble Crazy" de Captain Tsubasa
	-- (drible certo restaura Spirit), que resolve exatamente o problema
	-- de ter um recurso que só some.
	{
		Name = "Vendaval",
		Rarity = "Rare",
		Element = "Vento",
		Description = "Vendaval dá um arranque curto que DEVOLVE energia em vez de gastar — é o que mantém suas outras habilidades disponíveis até o fim do jogo, já que a energia só enche de novo no intervalo.",
		Action = "DribbleMove",
		Scaling = { DribbleSkill = 0.6, Speed = 0.4 }, -- ⚠️ NOVO: fórmula de potência (arranque)
		Cooldown = 45,
		-- ⚠️ v67 — REFEITA. PEDIDO: "não está claro como o drible funciona. Ele
		-- só dá um driblezinho e recarrega a estamina, é isso? Por que um
		-- drible recarregaria a estamina? Não tem sentido. Põe um drible que
		-- faz alguma coisa realmente."
		-- Agora o vendaval É o arranque: a finta te lança num pique de
		-- velocidade que dura alguns segundos depois dela. A devolução de
		-- energia ficou (é o que mantém suas outras habilidades vivas), mas
		-- deixou de ser a única coisa que a habilidade faz.
		Effect = {
			DistanceMult = 1.35,
			SelfIframe = 0.3,
			EnergyRefund = 40,
			SpeedBoostMult = 1.35,
			SpeedBoostDuration = 3.5,
		},
	},

	-- Dokugiri no Jutsu (毒霧の術): o drible de névoa. VERBO: lentificar o
	-- CAMINHO — deixa uma zona no chão ATRÁS de você que continua lá
	-- depois que você passou. Único Pulso de drible que muda o campo em
	-- vez de mudar você: quem te perseguir, perde.
	{
		Name = "Névoa",
		Rarity = "Epic",
		Element = "Void",
		Description = "Névoa deixa uma nuvem no chão por onde você passa — qualquer perseguidor que atravessar ela fica mais lento. Você não ganha velocidade, é o perseguidor que perde.",
		Action = "DribbleMove",
		Scaling = { DribbleSkill = 0.6, Technique = 0.4 }, -- ⚠️ NOVO: fórmula de potência (drible de controle)
		Cooldown = 60,
		-- ⚠️ v67 — REFEITA. PEDIDO: "a Névoa está colocando uma área no chão,
		-- não pode ser assim. Ela é uma área que deixa o PRÓPRIO JOGADOR
		-- invisível ali dentro. Faz um cilindro maior em volta e deixa o cara
		-- transparente. A bola também some junto, e só aparece quando ele sair
		-- da área."
		-- Deixou de ser lentidão (isso é a Teia) e virou ESCONDERIJO: enquanto
		-- você fica dentro, você e a bola somem. Sair revela os dois.
		Effect = {
			DistanceMult = 1.4,
			SelfIframe = 0.4,
			FogRadius = 30,
			FogDuration = 7,
		},
	},

	-- Kamaitachi (かまいたち): a foice de vento. VERBO: derrubar — ragdoll
	-- de verdade (não stun) em área, e funciona mesmo sem ninguém colado,
	-- então também é ferramenta de fuga em campo aberto.
	{
		Name = "Foice de Vento",
		Rarity = "Legendary",
		Element = "Vento",
		Description = "Foice de Vento derruba de verdade (não é empurrão) todo mundo em volta com um corte de vento — funciona até sem ninguém marcando, então também serve só pra abrir espaço.",
		Action = "DribbleMove",
		Scaling = { DribbleSkill = 0.5, Physical = 0.5 }, -- ⚠️ NOVO: fórmula de potência (derruba de verdade: drible + corpo)
		Cooldown = 90,
		-- ⚠️ v67 — AJUSTADA. PEDIDO: "eu testei mais ou menos, não sei direito
		-- como funciona. Não era pra empurrar os jogadores que estão na minha
		-- frente? Ou é em volta de mim? É muito perto? Não entendi."
		-- Era um raio de 9 studs em VOLTA — perto demais pra dar pra perceber.
		-- Agora o corte vai PRA FRENTE, na direção da finta, com alcance de
		-- verdade: é uma foice, não uma explosão. RagdollForward define o
		-- comprimento e RagdollRadius vira a LARGURA do corte.
		Effect = {
			DistanceMult = 1.7,
			RagdollForward = 26,
			SelfIframe = 0.8,
			AnkleRangeAdd = 5,
			RagdollRadius = 9,
			RagdollDuration = 1.6,
		},
	},

	-- Heaven's Time (ヘブンズタイム): "para o tempo no campo e atravessa
	-- caminhando, elegante". VERBO: parar o tempo. Nenhuma outra
	-- habilidade do jogo mexe com o tempo dos outros — é a carta que
	-- ganha qualquer 1 contra 3, e o cooldown reflete isso.
	{
		Name = "Hora do Céu",
		Rarity = "Mythic",
		Element = "Void",
		Description = "Hora do Céu congela todo jogador num raio grande (companheiro incluído, só o goleiro fica de fora) enquanto o tempo continua rodando só pra você — atravessa o campo andando por onde quiser.",
		-- ⚠️ v20 — PEDIDO: "ele faz um drible pro lado na hora, não é
		-- necessário. Ele para o tempo, então não precisa driblar nada."
		-- Era Action="DribbleMove", então ela disparava a finta normal POR
		-- CIMA da parada de tempo: o jogador era jogado pro lado sozinho,
		-- numa direção que ele não escolheu, bem no momento em que o campo
		-- inteiro tinha congelado e ele deveria ter liberdade total pra andar.
		-- Agora é "Buff" sem Duration = ação instantânea que só aplica os
		-- efeitos (ver executeBuff/applyExtraEffectKeys): congela e pronto,
		-- o deslocamento é 100% do jogador.
		Action = "Buff",
		Scaling = { DribbleSkill = 0.5, Technique = 0.5 }, -- ⚠️ NOVO: fórmula de potência (atravessar o campo com a bola)
		-- Sem Action="DribbleMove", a dica de posição cairia em DF (ver
		-- Data.GetPulsePositionHint). Ela continua sendo uma Hissatsu de
		-- drible na identidade, então força MF.
		PositionHint = "MF",
		Cooldown = 120,
		Effect = {
			SelfIframe = 2.5, -- ⚠️ v24: acompanha a duração da parada de tempo
			TimeStopRadius = 220,
			TimeStopDuration = 2.5,
		},
	},

	-- ========================================================
	-- DEFESA — 5. As 4 de linha são INSTANTÂNEAS; só a arrancada mantém
	-- QTE (exceção declarada, ver cabeçalho).
	-- ========================================================

	-- Killer Slide (キラースライド): o carrinho puro, o mais barato em TP
	-- do jogo. VERBO: alcance de desarme. Sem firula, cooldown curto — é
	-- o feijão com arroz do zagueiro, e tem que existir pra as outras
	-- três defesas serem "a escolha especial".
	{
		Name = "Rasteira",
		Rarity = "Common",
		Element = "Natureza",
		Description = "Rasteira dá um carrinho com bem mais alcance que o normal e cooldown curto — não tem efeito especial, é a defesa de todo dia.",
		Action = "Tackle",
		Scaling = { Physical = 0.6, Speed = 0.4 }, -- ⚠️ NOVO: fórmula de potência (carrinho de alcance)
		Cooldown = 30,
		-- ⚠️ v43: TackleRangeAdd é o que faz a Rasteira ser "carrinho seco COM
		-- BEM MAIS ALCANCE que o normal", que é a única coisa que ela promete.
		-- Isso estava só na descrição — nenhuma chave existia, então o alcance
		-- dela era o mesmo de um carrinho comum (Config.TACKLE_RANGE = 12.1).
		-- +7 leva pra ~19.1, que é o "bem mais" sem virar desarme à distância
		-- (pra isso existe a Costura de Sombra, com RootRadius 46).
		Effect = { KnockbackRadius = 5, KnockbackForce = 22, TackleRangeAdd = 7 },
	},

	-- Kage Nui / Shadow Stitch (影縫い): "a sombra vira uma mão, agarra as
	-- pernas do adversário e prega ele no chão". VERBO: prender À
	-- DISTÂNCIA. É o único desarme SEM CONTATO do jogo (alcance ~18) e
	-- ele NÃO rouba a bola: prende o carregador no lugar por um tempo e
	-- você ainda tem que ir lá buscar. Fiel ao anime e mecanicamente
	-- diferente de tudo (ver Action="Root" / executeRoot).
	{
		Name = "Costura de Sombra",
		Rarity = "Rare",
		Element = "Void",
		Description = "Costura de Sombra prende os pés do adversário no chão à distância, sem precisar encostar nele — ele não se move, mas continua com a bola, então você ainda precisa ir buscar.",
		Action = "Root",
		Scaling = { Physical = 0.5, Technique = 0.5 }, -- ⚠️ NOVO: fórmula de potência (prende à distância)
		Cooldown = 45,
		Effect = { RootRadius = 46, RootDuration = 1.3 },
	},

	-- Kumo no Ito / Spider Web (くもの糸): "espalha a teia no chão; quanto
	-- mais o adversário se debate, mais enrosca". VERBO: negar ÁREA. É o
	-- único Pulso PERSISTENTE do jogo — você monta a armadilha ANTES, e
	-- ela muda por onde o atacante escolhe entrar. Defesa que pensa duas
	-- jogadas à frente em vez de reagir.
	{
		Name = "Teia",
		Rarity = "Epic",
		Element = "Natureza",
		Description = "Teia espalha uma teia no chão por vários segundos — quem pisar nela fica lento, e quanto mais tenta correr, pior fica. Monte ela ANTES, no caminho que o atacante vai usar.",
		Action = "Buff",
		Scaling = { Physical = 0.5, Technique = 0.5 }, -- ⚠️ NOVO: fórmula de potência (zona de marcação)
		Cooldown = 60,
		Duration = 8,
		Effect = {
			ZoneSlowRadius = 42,
			ZoneSlowDuration = 8,
			ZoneSlowMult = 0.45,
		},
	},

	-- Mugen no Kabe / Infinite Wall (無限の壁): "TRÊS jogadores erguem
	-- juntos uma parede intransponível na frente do gol". VERBO: bloquear
	-- EM GRUPO — é o espelho defensivo da Zona Morta: sozinho é um muro
	-- qualquer, com companheiros do lado vira infinita. Mantém o
	-- FreezeSelf (quem ergue a muralha não sai do lugar).
	{
		Name = "Muralha Infinita",
		Rarity = "Legendary",
		Element = "Natureza",
		Description = "Muralha Infinita levanta uma parede na frente do gol que CRESCE com companheiros perto de você — sozinho é comum, com apoio nenhum chute passa. Você fica preso no lugar enquanto ela estiver de pé.",
		Action = "Buff",
		Scaling = { Physical = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (exemplo do pedido: 70% Físico + 30% Técnica)
		Cooldown = 90,
		Duration = 5,
		FreezeSelf = true,
		AlliesScale = { Radius = 45, PerAlly = 0.5, Max = 2 },
		Effect = { BlockRadius = 36, BlockImpulse = 45 },
	},

	-- ⚠️ MANTIDA COMO ESTAVA (dash com MashAD A/D). É a única exceção à
	-- regra "defesa é instantânea": a hitbox que cresce ao vivo com cada
	-- alternância É a identidade dela, e foi desenhada assim a pedido do
	-- usuário. A "Arrancada Selvagem" (Rare) SAIU — era essa mesma com
	-- números menores, exatamente o tipo de duplicata que esse rework
	-- existe pra matar. VERBO: perseguir.
	{
		Name = "Investida Titânica",
		Rarity = "Mythic",
		Element = "Fogo",
		Description = "Investida Titânica dispara você reto pra frente atrás de qualquer adversário no caminho — alterne A/D rápido: cada acerto aumenta sua hitbox e o tempo de perseguição. Você não controla a direção depois de disparar.",
		Action = "Tackle",
		Scaling = { Physical = 0.7, Speed = 0.3 }, -- ⚠️ NOVO: fórmula de potência (investida de corpo)
		Cooldown = 120,
		QTE = { Kind = "MashAD", Duration = 2.5, RequiredAlternations = 8 },
		Bom = { HitboxRadius = 5, ExtraPersistSeconds = 0.4, KnockbackRadius = 7, KnockbackForce = 50, RagdollRadius = 7, RagdollDuration = 1.4 },
		Perfect = { HitboxRadius = 9, ExtraPersistSeconds = 1.4, KnockbackRadius = 10, KnockbackForce = 75, RagdollRadius = 10, RagdollDuration = 2.2, StunRadius = 26, StunDuration = 0.5 },
	},

	-- ========================================================
	-- GOLEIRO — 2. Fluxo mantido (arma a guarda parado, QTE só quando o
	-- chute colide), que já estava certo.
	-- ========================================================

	-- ⚠️ v22 — PEDIDO: "o goleiro precisa ser capaz de usar Hissatsu... só
	-- vai poder defender uma Hissatsu com uma Hissatsu, a não ser que a do
	-- jogador seja muito fraca... implemente mais Hissatsu de goleiro, de
	-- outras raridades, porque ele vai poder usar a de uma raridade
	-- dependendo da maioria dos jogadores."
	--
	-- A ESCOLHA POR RARIDADE JÁ EXISTIA INTEIRA (ver pickGKPulseForRarity em
	-- GKBotController.legacy.luau): o bot conta a raridade dos Pulsos de
	-- todo mundo em campo, tira a maioria e pega a Hissatsu de goleiro
	-- daquela raridade — caindo pra mais baixa que exista se faltar. O que
	-- faltava era CONTEÚDO: só existiam GK em Legendary e Mythic, então
	-- numa partida de gente com Pulso comum/raro o bot caía sempre na Mão
	-- Divina. Agora tem uma pra cada raridade.
	{
		Name = "Soco Explosivo",
		Rarity = "Common",
		Element = "Fogo",
		RoleRequired = "GK",
		-- Bakuretsu Punch (爆裂パンチ): o soco que o Endou inventou no meio da
		-- partida contra o Teikoku pra REBATER o Twin Boost.
		-- VERBO: rebater. É a única guarda que NÃO segura a bola — ela sempre
		-- devolve pro jogo. Em troca é a mais barata e a que volta mais
		-- rápido: serve pra você não ficar sem nada entre uma guarda e outra.
		Description = "Soco Explosivo (só goleiro) sempre rebate a bola pro campo em vez de segurar — é a guarda mais barata e a que recarrega mais rápido, ao custo de sempre sobrar rebote.",
		Action = "Buff",
		Scaling = { Physical = 0.8, Kick = 0.2 }, -- ⚠️ NOVO: fórmula de potência (goleiro que soca)
		Cooldown = 30,
		Duration = 4,
		QTE = { Kind = "TimingBar", Duration = 4.5, PerfectStart = 0.38, PerfectEnd = 0.62, GoodPadding = 0.16, SweepPeriod = 0.9, RequiredHits = 4, GuardSize = 0.4 },
		-- ⚠️ v39: `Rebate` é o sinal EXPLÍCITO de "essa guarda nunca segura a
		-- bola". Antes isso existia só no texto e no comentário "de
		-- propósito SEM GuaranteedCatch" — e como nada no código lia isso,
		-- defender era sempre sinônimo de AGARRAR, então o soco defendia e
		-- ficava com a bola em vez de rebater (PEDIDO: "o efeito do soco do
		-- GK é dar um knockback na bola, e ele só pegou a bola"). Lido em
		-- resolveGuardContact (GKBotController) e na guarda do goleiro
		-- humano (BallController).
		Bom = { DiveRadiusAdd = 2, Rebate = true },
		Perfect = { DiveRadiusAdd = 3.5, Rebate = true }, -- de propósito SEM GuaranteedCatch: ela rebate, não agarra
	},

	{
		Name = "Muralha de Maré",
		Rarity = "Rare",
		Element = "Natureza",
		RoleRequired = "GK",
		-- Tsunami Wall (ツナミウォール): o goleiro bate as duas mãos no chão e
		-- levanta uma onda enorme na frente dele, tipo uma parede.
		-- VERBO: largura. Guarda mais LARGA do jogo (GuardSize alto) mas com
		-- alcance de mergulho pequeno — pega tudo que vem rasteiro ou pelos
		-- lados, e sofre com bola por cima.
		Description = "Muralha de Maré (só goleiro) levanta uma parede de água larga que cobre muito mais espaço pros lados que qualquer outra guarda — bola por cima ainda passa.",
		Action = "Buff",
		Scaling = { Physical = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (goleiro)
		Cooldown = 45,
		Duration = 5,
		QTE = { Kind = "TimingBar", Duration = 4.2, PerfectStart = 0.4, PerfectEnd = 0.6, GoodPadding = 0.14, SweepPeriod = 0.8, RequiredHits = 5, GuardSize = 0.75 },
		Bom = { DiveRadiusAdd = 2 },
		Perfect = { DiveRadiusAdd = 3, GuaranteedCatch = true },
	},

	{
		Name = "Punho Gigante",
		Rarity = "Epic",
		Element = "Natureza",
		RoleRequired = "GK",
		-- Gigant Wall (ジャイガントウォール): o goleiro vira um GIGANTE e soca a
		-- bola contra o chão, rachando o gramado.
		-- VERBO: esmagar o chute forte. MinShotDistance faz ela segurar o que
		-- vem de longe (que é justamente o chute que chega mais forte), então
		-- é a resposta específica pra canhão de fora da área.
		Description = "Punho Gigante (só goleiro) te transforma num gigante que soca a bola contra o chão — quanto mais longe veio o chute, mais fácil segura. Feita pra canhão de fora da área.",
		Action = "Buff",
		Scaling = { Physical = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (goleiro)
		Cooldown = 60,
		Duration = 5,
		QTE = { Kind = "TimingBar", Duration = 4.0, PerfectStart = 0.4, PerfectEnd = 0.6, GoodPadding = 0.13, SweepPeriod = 0.75, RequiredHits = 5, GuardSize = 0.55 },
		Bom = { DiveRadiusAdd = 3, MinShotDistance = 30 },
		Perfect = { DiveRadiusAdd = 4.5, GuaranteedCatch = true, MinShotDistance = 45 },
	},

	-- God Hand (ゴッドハンド): a mão de energia que cresce da luva e para
	-- a bola. VERBO: alcance de guarda.
	{
		Name = "Mão Divina",
		Rarity = "Legendary",
		Element = "Luz",
		RoleRequired = "GK",
		Description = "Mão Divina (só goleiro) arma uma guarda parada na sua frente — quando o chute bater nela, começa o timing; acertando, a bola gruda na mão sem rebote nenhum.",
		Action = "Buff",
		Scaling = { Physical = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (goleiro)
		Cooldown = 90,
		Duration = 5,
		QTE = { Kind = "TimingBar", Duration = 4.0, PerfectStart = 0.4, PerfectEnd = 0.6, GoodPadding = 0.12, SweepPeriod = 0.7, RequiredHits = 5, GuardSize = 0.5 },
		Bom = { DiveRadiusAdd = 3 },
		Perfect = { DiveRadiusAdd = 5.5, GuaranteedCatch = true },
	},

	-- Majin The Hand (マジン・ザ・ハンド, lit. "Mão do Deus-Demônio"): a mão
	-- que segura o que ninguém segura. VERBO: segurar o insegurável — é a
	-- única coisa no jogo que para a Galáxia (ver o comentário lá).
	-- Antes se chamava "Guardião Absoluto", nome genérico de RPG que não
	-- vinha de lugar nenhum.
	{
		Name = "Mão do Demônio",
		Rarity = "Mythic",
		Element = "Void",
		RoleRequired = "GK",
		Description = "Mão do Demônio (só goleiro) é a guarda máxima — acertando o timing, NADA passa, nem a Galáxia (que normalmente ignora o goleiro). A única resposta a um chute Mítico.",
		Action = "Buff",
		Scaling = { Physical = 0.7, Technique = 0.3 }, -- ⚠️ NOVO: fórmula de potência (goleiro)
		Cooldown = 120,
		Duration = 6,
		QTE = { Kind = "TimingBar", Duration = 3.5, PerfectStart = 0.42, PerfectEnd = 0.58, GoodPadding = 0.1, SweepPeriod = 0.65, RequiredHits = 5, GuardSize = 0.6 },
		Bom = { DiveRadiusAdd = 4.5, MinShotDistance = 15 },
		Perfect = { DiveRadiusAdd = 8, GuaranteedCatch = true, MinShotDistance = 25 },
	},
}

-- ============================================================
-- INSTINTOS — os 15 (10 da v5 + 5 novos, 1 por raridade). ⚠️ v9 REDESIGN:
-- a primeira leva dos 5 novos (v8) era só "+X% num gatilho qualquer" —
-- funcional, mas o usuário pediu ideias de verdade, ligadas a SITUAÇÃO DE
-- JOGO (2v1, campo livre...), não buff incondicional. Essa leva lê o
-- estado real do campo a cada disparo, com ctx NOVO computado em
-- BallController.legacy.luau:
--   "Campo Aberto"  (Common)    — ForwardOpponentDistance: ninguém
--                                 adversário dentro de um CONE à frente
--                                 (não só "longe" — precisa estar no seu
--                                 caminho de verdade).
--   "Emboscada"     (Rare)      — OpponentsNearbyCount: você sendo
--                                 cercado por 2+ atacantes ao mesmo tempo.
--   "Xeque-Mate"    (Epic)      — HasNumericalAdvantage: vantagem
--                                 numérica de verdade (2x1 ou melhor) num
--                                 raio de 22 studs na hora do passe.
--   "Último Homem"  (Legendary) — IsLastManBack: nenhum companheiro mais
--                                 perto do próprio gol do que você.
--   "Cara a Cara"   (Mythic)    — MinDistanceOpponent: breakaway limpo,
--                                 ninguém adversário perto, só você e o
--                                 goleiro.
-- ============================================================
Data.Instincts = {
	-- ========== Common (4) ==========
	{
		Name = "Pique",
		Image = "rbxassetid://82375927843223", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Common",
		Cor = Color3.fromRGB(255, 106, 61),
		Description = "Pique aumenta sua velocidade em 20% e recupera fôlego mais rápido durante o 1º segundo de uma arrancada, pra ganhar vantagem no impulso inicial contra seus marcadores — depois disso, precisa de 4s parado correndo pra valer de novo.",
		Passiva = "No 1º segundo de corrida: +20% de velocidade e fôlego recuperando mais rápido. Depois disso precisa de 4s parado de correr pra valer de novo.",
		Trigger = "Instant",
		Condition = { MaxSecondsAfterSprintStart = 1 },
		CooldownSeconds = 4,
		Effect = { SpeedMult = 1.20, StaminaRegenMult = 1.25 },
	},

	{
		Name = "Domínio",
		Image = "rbxassetid://100014626629607", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Common",
		Cor = Color3.fromRGB(199, 203, 209),
		Description = "Domínio aumenta em +6 sua hitbox de recepção perto de adversários e domina sozinho qualquer bola caindo por perto no ar — facilita dominar a bola em diversas situações, inclusive bolas altas e disputadas.",
		Passiva = "Bola solta perto de um adversário: +6 de alcance de recepção.",
		Ativa = "Se a bola estiver caindo por perto, você a domina no ar sozinho.",
		Trigger = "Instant",
		Condition = { LooseBallOpponentRadius = 12 },
		Effect = { PickupRadiusAdd = 6 },
		AtivaAction = "AerialControl",
		AtivaEffect = {},
		AtivaCooldown = 8,
	},

	{
		Name = "Reflexo",
		Image = "rbxassetid://81787426005468", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Common",
		Cor = Color3.fromRGB(255, 159, 10),
		Description = "Reflexo (só goleiro) aumenta o alcance do seu mergulho em +3 e a defesa sai sem rebote — você cobre mais gol do que deveria ser possível.",
		Passiva = "Em qualquer mergulho: +3 de alcance e defesa sem rebote.",
		Trigger = "Dive",
		Condition = {},
		Effect = { DiveRadiusAdd = 3 },
		RoleRequired = "GK",
	},

	-- ⚠️ v9 REDESIGN: "Cobertura Total" saiu — era só "+12% em qualquer
	-- carrinho", cópia genérica de Sentinela sem a exigência de área. Entra
	-- "Campo Aberto", ligado a uma situação de jogo de verdade: ninguém
	-- adversário no seu CAMINHO à frente (não só "longe" — precisa estar
	-- fora do cone que você está encarando, ver forwardOpponentDistance em
	-- BallController.legacy.luau). É a leitura de "tenho campo livre pra
	-- correr", não um buff incondicional.
	-- ⚠️ v12: "Campo Aberto" saiu. Ele era honesto (lia o cone à frente),
	-- mas o efeito era "+20% de velocidade" — o MESMO verbo da Velocidade
	-- Explosiva, só com outra condição. Entra "Zona de Ouro" (Golden Zone,
	-- Blue Lock: cada jogador tem um ponto de onde ele fabrica gol — a de
	-- Chigiri é 19m num ângulo de 44°). É o único Instinto que usa ÂNGULO,
	-- não só distância, e o único que te dá um LUGAR que é seu: em vez de
	-- te dar velocidade, ele te ensina onde parar.
	{
		Name = "Zona de Ouro",
		Rarity = "Common",
		Cor = Color3.fromRGB(245, 200, 66),
		Description = "Zona de Ouro dá mira quase perfeita e +15% de força quando você chuta a gol a ~124 studs de distância, num ângulo de ~40° — fora dessa posição exata, você é um jogador normal.",
		-- ⚠️ v21 — PEDIDO: "ela tá dentro da área do goleiro, literalmente
		-- área pequena. Não é pra ser ali — é pra ser dentro da área LONGA,
		-- então mais distante do gol." 34 studs caía na pequena; 62 põe os
		-- dois pontos lá na entrada/borda da grande área, que é de onde um
		-- atacante realmente arma o chute colocado. Se ainda ficar perto
		-- demais, é só subir este número (e o da tolerância pra abrir a
		-- faixa) — nada mais precisa mudar, a marca no chão se move junto.
		Passiva = "Chute a gol a ~124 studs de distância e num ângulo de ~40° em relação ao gol: mira quase perfeita e +15% de força.",
		Trigger = "KickAtGoal",
		Condition = {
			GoldenZoneDistance = 124,
			GoldenZoneDistanceTolerance = 20,
			GoldenZoneAngle = 40,
			GoldenZoneAngleTolerance = 20,
		},
		Effect = { ForceMult = 1.15, AimDeviationMult = 0.15 },
		-- ⚠️ v17 PEDIDO: "coloca a área da Zona de Ouro aparecendo quando você
		-- estiver perto dela... que nem o efeito da teia, só que dourada e
		-- brilhante, só pra você". Sem isso o jogador não tinha como adivinhar
		-- onde fica o ponto — a Arma inteira dependia de sorte. Desenhado no
		-- CLIENTE (ver InstinctTrajectorySight.local.luau), só pra quem tem
		-- ela equipada: os outros jogadores não veem nada.
		Passive = "GoldenZoneSight",
	},

	-- ========== Rare (4) ==========
	{
		Name = "Chute Direto",
		Rarity = "Rare",
		Cor = Color3.fromRGB(59, 111, 224),
		Description = "Chute Direto finaliza sozinho, com força alta e mira perfeita, se você apertar R em até 1 segundo depois de receber a bola — não precisa dominar pra finalizar.",
		Ativa = "Apertando R até 1 segundo depois de receber, o chute sai sozinho: força alta e mira perfeita.",
		Trigger = "Botao",
		Tecla = "R",
		Condition = { MaxSecondsAfterReceive = 1 },
		Effect = {},
		AtivaAction = "Shot",
		-- ⚠️ v67 — PEDIDO: "o Chute Direto vai com o chute brocha. Ele é tipo um
		-- chute com 100% de força, só que instantâneo, sem precisar preparar. E
		-- é um voleio: o voleio bota 120% de força."
		-- InstinctExecuteShot já usa KICK_MAX_FORCE cheio (não é carga parcial),
		-- então 100% = ForceMult 1.0 e o voleio leva pra 1.2. Somado ao aumento
		-- de 25% na KICK_MAX_FORCE (v67), a força absoluta sobe de 181 pra 217.
		AtivaEffect = { ForceMult = 1.2, AimDeviationMult = 0, IgnoreGKChance = 0.15 },
		AtivaCooldown = 6,
	},

	{
		Name = "Monstro do Drible",
		Image = "rbxassetid://136729033024503", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Rare",
		Cor = Color3.fromRGB(245, 197, 24),
		Description = "Monstro do Drible aumenta o alcance da sua finta em +6 no campo de ataque e garante stun mais longo em quem estiver perto — sempre, não só às vezes.",
		-- ⚠️ v5.4: era uma Ativa separada (AtivaAction="DribbleMove") que
		-- rodava a finta DE NOVO por cima da finta manual que o jogador já
		-- tinha apertado — a segunda sobrescrevia a primeira sem herdar o
		-- stun, então a lambreta "sumia" quase sempre. Virou só Effect: o
		-- mesmo AttemptDribbleMove que o jogador já dispara com Z/X/C agora
		-- lê AnkleStunAdd/AlwaysStun direto daqui (ver BallController.lua,
		-- Remotes.AttemptDribbleMove), garantido, sem segunda finta.
		Passiva = "Finta no campo de ataque: +6 de alcance e stun garantido (mais longo) em quem estiver perto — sempre, não só às vezes.",
		Trigger = "DribbleMove",
		Condition = { AttackingHalf = true },
		Effect = { AnkleRangeAdd = 6, AnkleStunAdd = 1.4, AlwaysStun = true },
	},

	{
		Name = "Xerife",
		Rarity = "Rare",
		Cor = Color3.fromRGB(52, 199, 89),
		Description = "Xerife aumenta sua chance de desarme em +25% em carrinhos dentro da própria área — você lê o atacante antes dele decidir.",
		-- ⚠️ v5.4: era um raio solto (MaxDistanceToOwnGoal=20), que podia
		-- valer fora da área de verdade. Agora usa a mesma Part GKArea_* do
		-- goleiro (GKAreaUtil) — dentro da área de verdade, e só lá.
		Passiva = "Carrinho DENTRO da própria área: +25% de chance de desarme.",
		Trigger = "Tackle",
		Condition = { RequireOwnArea = true },
		Effect = { ChanceAdd = 0.25 },
	},

	-- ⚠️ v9 REDESIGN: "Passe de Ouro" saiu — era "+20% em qualquer passe",
	-- sem ler situação nenhuma. Entra "Emboscada": só dispara quando VOCÊ
	-- (defendendo) está sendo cercado por 2+ atacantes ao mesmo tempo —
	-- lê a dobra e desarma quem está com a bola, em vez de travar sozinho.
	-- ⚠️ v12: "Emboscada" saiu — "+30% de chance de desarme numa condição" é
	-- o mesmo verbo da Sentinela, só trocando "dentro da área" por "cercado
	-- por 2". Entra "Olho de Predador" (Predator Eye, Blue Lock: o atacante
	-- fixa o olhar no goleiro e chuta no instante em que a guarda baixa).
	-- É a ÚNICA condição do jogo que lê o estado do ADVERSÁRIO em vez da
	-- geometria do campo — ver goalkeeperOffGuard em BallController.
	{
		Name = "Olho de Predador",
		Rarity = "Rare",
		Cor = Color3.fromRGB(190, 30, 45),
		Description = "Olho de Predador dá +20% de força e mira muito mais limpa quando o goleiro está fora de posição (adiantado ou deslocado pro lado errado) — 20% de chance dele nem alcançar a bola.",
		Passiva = "Chute a gol com o goleiro fora de posição (adiantado, ou deslocado pro lado contrário do seu chute): +20% de força, mira muito mais limpa e 20% de chance de ele nem alcançar.",
		Trigger = "KickAtGoal",
		Condition = { RequireGoalkeeperOffGuard = true },
		Effect = { ForceMult = 1.2, AimDeviationMult = 0.15, IgnoreGKChance = 0.2 },
	},

	-- ========== Epic (3) ==========
	{
		Name = "Metavisão",
		Image = "rbxassetid://123335535687893", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Epic",
		Cor = Color3.fromRGB(127, 212, 255),
		Description = "Metavisão mostra na tela a trajetória da bola até onde ela vai parar enquanto está em movimento, e pra onde ela iria se você chutasse AGORA enquanto carrega um chute — informação em tempo real, sem gastar nada.",
		-- ⚠️ v5.4: terceira visão — enquanto segura o botão de chute
		-- carregando força, mostra a trajetória prevista a partir da MIRA
		-- ATUAL (mouse.Hit) e da força já carregada, não só reage à bola
		-- que já está em movimento. Ver InstinctTrajectorySight.local.luau
		-- (_G.GetKickChargeInfo, exposto por FootballClient.local.luau).
		-- ⚠️ v46: a frase "e o tempo todo, marca no chão o maior espaço livre
		-- entre os jogadores em campo" foi TIRADA daqui. Esse efeito existiu
		-- e foi REMOVIDO de propósito na v5.7, a pedido ("atrapalhava a
		-- visão" — ver o cabeçalho de InstinctTrajectorySight.local.luau).
		-- O texto tinha ficado prometendo uma coisa que o jogo não faz mais.
		-- Corrigido o TEXTO, e não o comportamento: reimplementar seria
		-- desfazer uma decisão que já foi tomada.
		Passiva = "Enquanto a bola estiver em movimento, mostra a trajetória dela até o ponto onde vai parar. Enquanto VOCÊ estiver carregando um chute, mostra pra onde a bola iria com a mira e a força atuais.",
		Trigger = "Passivo",
		Condition = {},
		Effect = {},
		Passive = "Metavision",
	},

	{
		Name = "Ego do Rei",
		Rarity = "Epic",
		Cor = Color3.fromRGB(168, 85, 247),
		Description = "Ego do Rei dá +30% de força e mira bem mais limpa em chutes carregados até o máximo, de fora da área — você não passa, chuta.",
		-- ⚠️ v5.4: valia pra QUALQUER chute a gol, de qualquer distância —
		-- inclusive de dentro da própria área adversária (chute quase em
		-- cima do gol). Agora exige: fora da área adversária de verdade
		-- (RequireOutsideEnemyArea), até 50 de distância do gol (senão um
		-- passe de campo inteiro contava como "chute"), e só se carregou o
		-- chute até a força máxima (RequireMaxCharge) — não é mais qualquer
		-- toque fraco de longe.
		-- ⚠️ v5.4: 50 studs era perto demais — o usuário testou e achou
		-- pouco espaço, pediu um teto bem maior (200) já que quem realmente
		-- trava um "chute" de "passe de campo inteiro" é o
		-- RequireOutsideEnemyArea + RequireMaxCharge, não a distância.
		Passiva = "Chute a gol carregado até o máximo, de fora da área: +30% de força e mira bem mais limpa.",
		Trigger = "KickAtGoal",
		-- ⚠️ v5.5: 200 studs era longe demais (pedido: diminuir pra 100).
		-- ⚠️ v5.6: pedido: diminuir mais uma vez, pra 80.
		Condition = { MinDistanceToGoal = 14, MaxDistanceToGoal = 80, RequireOutsideEnemyArea = true, RequireMaxCharge = true },
		Effect = { ForceMult = 1.30, AimDeviationMult = 0.2 },
	},

	-- ⚠️ v9 REDESIGN: "Cobrador de Elite" saiu — era "+35% em qualquer bola
	-- parada", sem situação nenhuma. Entra "Xeque-Mate": lê de verdade se
	-- você tem VANTAGEM NUMÉRICA (2 contra 1, ou melhor) num raio de 22
	-- studs na hora do passe — é o exemplo que o próprio pedido deu.
	-- ⚠️ v12: "Xeque-Mate" saiu — bom gatilho (vantagem numérica), mas o
	-- efeito era "passe melhor", o mesmo verbo do Passe de Ouro que ele
	-- tinha substituído. Entra "Passo Furtivo" (Stealth Walk + Off-the-Ball
	-- Movements, Blue Lock: se move entre os adversários sem que percebam).
	-- É o único Instinto que funciona SEM a bola, e o único que lê PRA ONDE
	-- O ADVERSÁRIO ESTÁ OLHANDO (ver isUnseenByOpponents no BallController).
	-- Premia sumir do jogo pra reaparecer no lugar certo.
	{
		Name = "Passo Furtivo",
		Rarity = "Epic",
		Cor = Color3.fromRGB(99, 102, 241),
		Description = "Passo Furtivo dá +25% de velocidade, +5 de alcance de recepção e fôlego recuperando mais rápido sempre que você está sem a bola e nenhum adversário está olhando na sua direção.",
		Passiva = "Sem a posse da bola e com NENHUM adversário olhando na sua direção: +25% de velocidade, +5 de alcance de recepção e fôlego recuperando mais rápido.",
		Trigger = "Instant",
		Condition = { RequireUnseen = true, RequireNoPossession = true },
		Effect = { SpeedMult = 1.25, PickupRadiusAdd = 5, StaminaRegenMult = 1.2 },
	},

	-- ========== Legendary (2) ==========
	{
		Name = "Xeque-Mate",
		Image = "rbxassetid://129579024510412", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Legendary",
		Cor = Color3.fromRGB(225, 29, 72),
		Description = "Xeque-Mate finaliza com uma acrobacia automática se você apertar R dentro da área adversária com a bola caindo perto — bola perdida na área vira gol.",
		-- ⚠️ v5.4: era MaxDistanceToGoal=22 — 22 studs é quase colado na
		-- trave, então na prática só valia bem em cima do gol. Trocado por
		-- "dentro da área de verdade" (mesma Part GKArea_* usada por
		-- Sentinela/Ego do Rei, só que aqui é a área ADVERSÁRIA — você
		-- está atacando o gol dela).
		Ativa = "Dentro da área adversária, apertando R com a bola caindo perto: finalização acrobática.",
		Trigger = "Botao",
		Tecla = "R",
		Condition = { RequireInsideEnemyArea = true },
		Effect = {},
		AtivaAction = "Header",
		-- HeaderRangeAdd/HeaderMinHeight ALARGAM a janela do cabeceio só
		-- pra este Instinto: alcance 6 -> 16. HeaderMinHeight (altura da
		-- bola em relação ao HumanoidRootPart pra contar) baixou de 1 -> 0
		-- (v5.5) e agora v5.7 baixou mais, pra -4: como o HumanoidRootPart
		-- fica alguns studs ACIMA do chão, exigir >= 0 na prática ainda
		-- travava qualquer bola perto do gramado (finalização de bico/
		-- voleio baixo dentro da área) — negativo aceita bola até perto do
		-- pé, não só na altura do quadril pra cima.
		-- ⚠️ v17 — PEDIDO: "o Matador faz mais ou menos a mesma coisa do Chute
		-- Direto: aperta o botão, ele finaliza. Só que é mais difícil acertar
		-- o Matador. Talvez pegar a bola, jogar mais forte."
		--
		-- O que separa os dois AGORA:
		--   Chute Direto  — a bola já tem que estar no SEU pé (até 1s depois
		--                   de receber). Fácil de acertar, bônus moderado.
		--   Matador       — BallMagnetRadius PUXA a bola que está caindo
		--                   perto até você antes de finalizar (ver tryRunAtiva
		--                   em InstinctController), e aí bate MUITO mais
		--                   forte, com mira perfeita e chance real de o
		--                   goleiro nem alcançar. Ou seja: não é mais "o
		--                   Chute Direto porém difícil" — é a habilidade que
		--                   transforma bola perdida na área em gol.
		-- Força 1.8 -> 2.4, mira 0.1 -> 0 (perfeita), + 30% de ignorar o
		-- goleiro, e cooldown 8 -> 7 (é uma janela mais rara que a do Chute
		-- Direto, não faz sentido esperar mais).
		AtivaEffect = {
			HeaderForceMult = 2.4,
			AimDeviationMult = 0,
			HeaderRangeAdd = 10,
			HeaderMinHeight = -4,
			IgnoreGKChance = 0.3,
			BallMagnetRadius = 36,
		},
		AtivaCooldown = 7,
	},

	-- ⚠️ v9 REDESIGN: "Instinto de Virada" saiu — "+40% enquanto o time
	-- está perdendo" ainda era só um buff condicional, sem ler POSIÇÃO em
	-- campo. Entra "Último Homem": dispara quando você é literalmente o
	-- ÚLTIMO jogador do seu time entre a bola e o próprio gol — a corrida
	-- desesperada de recuperação que só acontece quando não sobra mais
	-- ninguém pra cobrir.
	-- ⚠️ v12: "Último Homem" saiu — de novo "+35% de velocidade", terceiro
	-- Instinto com o mesmo verbo (Pique e Campo Aberto já
	-- eram isso). Entra "Tabela" (Super Ace, Captain Tsubasa: recebe depois
	-- de 5+ passes seguidos do time). É o ÚNICO Instinto do jogo que
	-- depende dos seus companheiros jogarem bem — não dá pra ativar
	-- sozinho, de jeito nenhum. Num jogo que existe pra jogar com os
	-- amigos, faltava exatamente isso.
	{
		Name = "Tabela",
		Rarity = "Legendary",
		Cor = Color3.fromRGB(45, 212, 191),
		Description = "Tabela dá +30% em TODOS os atributos por 5 segundos quando você recebe a bola depois do seu time trocar 5 passes seguidos sem perder a posse.",
		Passiva = "Recebendo a bola depois de 5 passes seguidos do seu time (sem perder a posse no meio): +30% em TODOS os atributos pelos primeiros 5 segundos depois de receber.",
		Trigger = "Instant",
		Condition = { MinTeamPassChain = 5, MaxSecondsAfterReceive = 5 },
		Effect = { AllBoost = 0.3 },
	},

	-- ========== Mythic (2) ==========
	-- ⚠️ v5.4: "Fluxo" saiu (só empilhava atributo passivo, sem depender de
	-- nada acontecer — e por isso nunca carregava o medidor de Instinct
	-- Mode: addInstinctCharge só soma quando o Effect faz a transição
	-- desligado→ligado, e Fluxo ficava ligado o jogo INTEIRO sempre que
	-- você estava no campo de ataque, ou seja, ligava uma vez só e nunca
	-- mais recarregava nada). "Apostador" entra no lugar: literalmente uma
	-- aposta — a cada GambleIntervalSeconds segundos, uma jogada de sorte
	-- é lançada (ver conditionMet em InstinctController.legacy.luau); com
	-- GambleChance de dar certo, e aí o Effect vale por
	-- GambleDurationSeconds inteiros. Cada vitória é uma transição
	-- desligado→ligado de verdade, então CARREGA o medidor de Instinct
	-- Mode toda vez que a sorte vira — o oposto do problema do Fluxo.
	{
		Name = "Apostador",
		Image = "rbxassetid://89373794649343", -- ⚠️ v77: arte do artista (ver pedido do usuário)
		Rarity = "Mythic",
		Cor = Color3.fromRGB(250, 204, 21),
		Description = "Apostador sorteia a cada 10 segundos uma chance de 25% de ativar +35% em TODOS os atributos por 3 segundos — quando acerta, sua aura pisca dourada e o contador aparece no canto da tela.",
		-- ⚠️ v5.4: intervalo 4s → 15s (pedido). A contagem regressiva até a
		-- próxima jogada aparece no canto inferior direito da tela (mesmo
		-- painel dos outros cooldowns) — ver Remotes.GambleTimerFeedback em
		-- InstinctController.legacy.luau / AbilityHUD.local.luau.
		-- ⚠️ v17: intervalo 15s -> 10s (pedido). Mais jogadas por partida =
		-- mais transições desligado->ligado, então também carrega o medidor
		-- de Instinct Mode com mais frequência.
		Passiva = "A cada 10s, uma jogada de sorte: 25% de chance de ativar +35% em TODOS os atributos por 3s. Quando acerta, a aura pisca dourada. A contagem até a próxima jogada aparece no canto da tela.",
		Trigger = "Instant",
		Condition = { GambleChance = 0.25, GambleIntervalSeconds = 10, GambleDurationSeconds = 3 },
		Effect = { AllBoost = 0.35 },
	},

	-- ⚠️ v9 REDESIGN: "Testa de Ferro" saiu — "+60% em toda cabeçada" não
	-- lia situação nenhuma. Entra "Cara a Cara": só dispara no breakaway
	-- limpo de verdade — NENHUM adversário perto o bastante pra incomodar,
	-- só você e o goleiro. É o momento clássico do 1x1 puro.
	-- ⚠️ v12: "Cara a Cara" saiu — era um bom momento de futebol, mas o
	-- efeito (força + mira + ignorar goleiro num chute) é exatamente o que
	-- Ego do Rei, Zona de Ouro e Olho de Predador já fazem: o quarto
	-- Instinto de "chute melhor" do jogo. Entra "A Zona" (Flow State, Blue
	-- Lock: imersão total, "estar na zona"), que é o par exato do
	-- Apostador: os dois são Míticos e os dois dão tudo — só que o
	-- Apostador é sorte pura, sorteada sem você fazer nada, e este é mérito
	-- puro, construído segurando a bola sob pressão. Um não pode existir
	-- sem o outro.
	-- ⚠️ NOME: chamado de "A Zona" e não de "Fluxo" de propósito — "Fluxo"
	-- já está em Data.LegacyNames apontando pro Apostador, e reusar o nome
	-- resolveria pro Instinto errado no save de quem já tem.
	{
		Name = "A Zona",
		Rarity = "Mythic",
		Cor = Color3.fromRGB(240, 253, 255),
		Description = "A Zona dá +40% em TODOS os atributos depois de 8 segundos seguidos com a bola no campo de ataque, sem perder a posse — perdeu a bola, o bônus acaba e você começa do zero.",
		Passiva = "Com a bola há 8 segundos seguidos sem perder a posse, no campo de ataque: +40% em TODOS os atributos, até você perder a bola.",
		Trigger = "Instant",
		Condition = { MinSecondsInPossession = 8, AttackingHalf = true },
		Effect = { AllBoost = 0.4 },
	},
}

-- ============================================================
-- NOMES ANTIGOS — Pulsos e Instintos que existiram e não existem mais.
-- Quem tiver um deles salvo NÃO trava nada: quem procura resolve o nome
-- por aqui primeiro e, se o destino também não existir mais (caso de
-- todos os Pulsos na v5), simplesmente não acha nada e o jogador fica
-- sem aquela habilidade, sem erro. NUNCA remova linhas daqui.
-- ============================================================
Data.LegacyNames = {
	-- Instintos da v4 que foram absorvidos pelos 10 da v5
	["Instinto de Área"] = "Ego do Rei",
	["Instinto Matador"] = "Chute Direto",
	["Instinto Clínico"] = "Chute Direto",
	["Instinto de Recepção"] = "Chute Direto",
	["Instinto Divino do Artilheiro"] = "Ego do Rei",
	["Instinto de Corredor"] = "Pique",
	["Instinto de Contra-Ataque"] = "Pique",
	["Instinto de Antecipação"] = "Domínio",
	["Instinto Predatório"] = "Domínio",
	["Instinto de Leitura de Jogo"] = "Metavisão",
	["Instinto de Metavisão"] = "Metavisão",
	["Instinto de Passe Rápido"] = "Metavisão",
	["Instinto de Passe Decisivo"] = "Metavisão",
	["Instinto de Camisa 10"] = "Monstro do Drible",
	["Instinto de Camisa 7 Lendário"] = "Monstro do Drible",
	["Instinto de Fluxo"] = "Apostador",
	["Instinto do Capitão"] = "Apostador",
	["Instinto dos Acréscimos"] = "Apostador",
	-- ⚠️ v5.4: "Fluxo" (o Instinto v5, não o Pulso v4 acima) saiu, virou
	-- "Apostador" — ver comentário em Data.Instincts.
	["Fluxo"] = "Apostador",
	["Instinto do Egoísta"] = "Ego do Rei",
	["Instinto de Sangue Frio"] = "Ego do Rei",
	["Instinto Defensivo"] = "Xerife",
	["Instinto de Zagueiro"] = "Xerife",
	["Instinto de Última Linha"] = "Xerife",
	["Instinto de Camisa 9"] = "Xerife",
	["Instinto do Muro Lendário"] = "Xerife",
	["Instinto de Cabeceio"] = "Xeque-Mate",
	["Instinto de Fôlego Final"] = "Pique",
	["Instinto de Bola Parada"] = "Metavisão",
	["Instinto de Reflexo"] = "Reflexo",
	["Instinto do Um-Contra-Um"] = "Reflexo",
	["Instinto de Muralha"] = "Reflexo",
	["Instinto de Reposição"] = "Reflexo",
	["Instinto Divino do Guardião"] = "Reflexo",
	-- ⚠️ v9: os 5 Instintos novos da v8 eram só buff genérico e foram
	-- REDESENHADOS pra ler situação de jogo de verdade (ver comentário em
	-- Data.Instincts) — quem já tinha sorteado/salvo um deles é resolvido
	-- pro substituto direto, sem perder o Instinto.
	-- ⚠️ v12: REAPONTADOS. ResolveName dá UM salto só (LegacyNames[name] or
	-- name) — como os 5 destinos da v9 saíram na v12, apontar pra eles
	-- deixaria o jogador sem Instinto nenhum. Agora vão direto pro nome
	-- atual. As linhas continuam aqui (nunca remova), só mudaram de alvo.
	["Cobertura Total"] = "Zona de Ouro",
	["Passe de Ouro"] = "Olho de Predador",
	["Cobrador de Elite"] = "Passo Furtivo",
	["Instinto de Virada"] = "Tabela",
	["Testa de Ferro"] = "A Zona",

	-- ⚠️ v12: os 5 Instintos da v9 que saíram agora. Todos eram variações
	-- de "+X% de velocidade" ou "+X% num chute" — três deles tinham
	-- literalmente o mesmo verbo de Instintos que já existiam. Ver o
	-- comentário de cada substituto em Data.Instincts.
	["Campo Aberto"] = "Zona de Ouro",
	["Emboscada"] = "Olho de Predador",
	["Último Homem"] = "Tabela",
	["Cara a Cara"] = "A Zona",

	-- ⚠️ v16: as 6 Armas que trocaram só de NOME (a mecânica é exatamente a
	-- mesma). Os nomes antigos eram descrição ("Velocidade Explosiva") ou
	-- fantasia genérica ("Guardião", "Sentinela") — os novos são palavra de
	-- futebol de verdade, do jeito que um jogador falaria.
	["Velocidade Explosiva"] = "Pique",
	["Domínio Absoluto"] = "Domínio",
	["Guardião"] = "Reflexo",
	["Sentinela"] = "Xerife",
	["Predador da Área"] = "Xeque-Mate",

	-- ⚠️ v11: REWORK DOS 20 PULSOS (ver Data.Pulses). Os nomes velhos eram
	-- adjetivo + substantivo ("Chute Vulcânico") escondendo que 8 chutes
	-- faziam a mesma coisa; os novos são hissatsu de verdade do Inazuma
	-- Eleven. Cada nome antigo aponta pro substituto MAIS PARECIDO em
	-- função (chute vira chute, drible vira drible, defesa vira defesa) —
	-- ninguém fica sem Pulso nem troca de categoria de repente.
	-- ⚠️ v77: renomeados hoje pra bater com arte nova do artista (ver
	-- comentário grande no início de Data.Instincts pra cada um).
	["Primeiro Toque"] = "Domínio",
	["Ginga"] = "Monstro do Drible",
	["Matador"] = "Xeque-Mate",

	["Chute Cometa"] = "Raio Um",
	["Chute Furacão"] = "Raio Um",
	["Chute Relâmpago"] = "Sumiço",
	["Chute Vulcânico"] = "Impulso de Maré",
	["Meteoro Sagrado"] = "Zona Morta",
	["Chute do Fênix Mítico"] = "Galáxia",
	["Corte Certeiro"] = "Residual",
	["Passo Fantasma"] = "Vendaval",
	["Ilusão Dupla"] = "Névoa",
	["Toque Divino"] = "Foice de Vento",
	["Passo do Deus Relâmpago"] = "Hora do Céu",
	["Desarme de Aço"] = "Rasteira",
	["Corrente Impenetrável"] = "Costura de Sombra",
	["Grande Muralha"] = "Muralha Infinita",
	["Arrancada Selvagem"] = "Investida Titânica",
	["Guardião Absoluto"] = "Mão do Demônio",
}

-- Resolve um nome salvo (possivelmente antigo) pro nome atual.
function Data.ResolveName(name)
	if not name then return nil end
	return Data.LegacyNames[name] or name
end

-- ============================================================
-- ⚠️ v10: POSIÇÃO SUGERIDA PELO PULSO — pedido: "existem pulsos que são
-- melhores se utilizarem em uma determinada posição... pessoas com esses
-- pulsos têm prioridade pra cair em determinada posição, mas sem NENHUMA
-- seleção manual" — DF/MF/FW saíram de vez da escolha no Lobby (só GK
-- continua sendo escolha, via checkbox — ver CharacterClient.local.luau /
-- PlayerDataManager.legacy.luau). Deriva a posição de linha "natural" de
-- um Pulso a partir do que ele JÁ tem (Action/RoleRequired), sem precisar
-- marcar um campo novo em cada um dos 20 Pulsos:
--   RoleRequired="GK"      -> GK (Mão Divina, Guardião Absoluto)
--   Action="Shot"          -> FW (os 8 Chutes — quem tem chute forte
--                             equipado quer terminar jogada lá na frente)
--   Action="Tackle"        -> DF (Desarme de Aço, Corrente Impenetrável,
--                             Arrancada Selvagem, Investida Titânica —
--                             mesmo as "arrancadas" são desarme, servem
--                             melhor perto da própria defesa)
--   Action="Buff" (resto)  -> DF (só sobra Grande Muralha aqui — zona de
--                             bloqueio só faz sentido perto de quem
--                             defende; Mão Divina/Guardião já voltaram
--                             GK acima, antes de chegar nesse checa)
--   Action="DribbleMove"   -> MF (as 5 fintas — ninguém tem Pulso de
--                             passe ainda, então quem carrega/dribla a
--                             bola no meio-campo é o encaixe natural)
-- Usado só como SUGESTÃO de formação (ver derivePreferredRole em
-- MatchDataTransfer.legacy.luau, place Lobby) — nunca trava nada: quem
-- não tem Pulso equipado, ou cujo(s) Pulso(s) não têm posição definida,
-- cai no sorteio/overflow normal (ver MatchController.legacy.luau, place
-- Game, que já lida com preferência nil/ausente desde antes).
-- ============================================================
function Data.GetPulsePositionHint(pulseDef)
	if type(pulseDef) ~= "table" then return nil end
	-- ⚠️ v20: override explícito, pra Hissatsu cuja Action não representa a
	-- identidade dela (ver Hora do Céu, que virou "Buff" mas continua sendo
	-- uma técnica de meio-campo).
	if pulseDef.PositionHint then return pulseDef.PositionHint end
	if pulseDef.RoleRequired == "GK" then return "GK" end
	if pulseDef.Action == "Shot" then return "FW" end
	-- ⚠️ v11: "Header" (Cabeça de Kung Fu) é finalização — mesma leitura do
	-- chute. "Root" (Costura de Sombra) é desarme à distância — zagueiro.
	if pulseDef.Action == "Header" then return "FW" end
	if pulseDef.Action == "Tackle" then return "DF" end
	if pulseDef.Action == "Root" then return "DF" end
	if pulseDef.Action == "DribbleMove" then return "MF" end
	if pulseDef.Action == "Buff" then return "DF" end
	return nil
end

-- Mesma coisa, mas a partir do NOME salvo (resolve nome antigo primeiro,
-- igual findPulse em PulseController.legacy.luau).
function Data.GetPulsePositionHintByName(name)
	if not name then return nil end
	local resolved = Data.ResolveName(name)
	for _, def in ipairs(Data.Pulses) do
		if def.Name == resolved then
			return Data.GetPulsePositionHint(def)
		end
	end
	return nil
end

Data.RarityWeights = {
	Common = 65,
	Rare = 25,
	Epic = 7,
	Legendary = 2.5,
	Mythic = 0.5,
}

return Data
