--[[
	FootballConfig (ModuleScript)
	LOCAL: ReplicatedStorage
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local Config = {}

-- ⚠️ v23 — MODO DE TESTE TEMPORÁRIO. PEDIDO: "refaça TODAS as mecânicas
-- relacionadas a chute e hitbox... pelo menos pra teste temporario, e
-- vamos testar com tudo novo". Em vez de apagar/reescrever tudo (arriscado
-- e difícil de desfazer se piorar), essa chave ÚNICA desliga, só no chute,
-- TUDO que foi mexido nas últimas sessões — mecânica de corpo, saída
-- limpa do chute (CanCollide), avanço pra frente da bola, curva/spin, e o
-- filtro novo de mira que ignora hitbox — deixando SÓ a física mais crua
-- possível: mira = mouse.Hit.Position puro (sem filtro nenhum), chute =
-- direção * força + impulso vertical, sem mais nada tocando a bola depois
-- disso. Serve pra provar se o problema é uma dessas mecânicas OU se é
-- outra coisa mais funda (física da bola, drible, etc). Depois do teste,
-- é só voltar isso pra false pra ligar tudo de novo — nenhum código foi
-- apagado, só ignorado enquanto essa chave for true.
--
-- ⚠️ RESULTADO DO TESTE: apagando o campoHit (sem mexer nessa chave), o
-- chute voltou ao normal — ou seja, era mesmo o campoHit (mira acertando a
-- caixa invisível dele), não nenhuma das mecânicas acima. Voltando pra
-- false agora pra reativar tudo de novo (mecânica de corpo, saída limpa,
-- avanço pra frente, curva, filtro de mira) e testar de novo COM tudo
-- ligado, mas SEM o campoHit, pra confirmar que as duas coisas continuam
-- funcionando juntas.
Config.KICK_TEST_MODE = false

-- ⚠️ v24 — INTERRUPTOR TEMPORÁRIO. PEDIDO: "acho que foi o novo código que
-- você fez, faz um interruptor e desliga ele, só pra eu testar um
-- segundo". Isso desliga só o watchdog do OutOfBoundsController.lua que
-- reforça CanQuery/CanCollide=false no campoHit/gols/zonas a cada 2s (o
-- código mais "ativo"/novo mexido nessa última rodada). Com false, o
-- OutOfBoundsController volta a fazer só a correção ÚNICA de sempre, na
-- hora que o servidor liga — nada rodando sozinho depois disso.
--
-- IMPORTANTE (pra não gastar o teste à toa): esse watchdog só MUDA alguma
-- coisa se o campoHit (ou gol/zona) estiver com CanQuery/CanCollide ligado
-- de novo depois do servidor já ter iniciado — ele não toca em MAIS NADA
-- (não mexe na detecção de bola fora, não mexe no chute). Se o campoHit
-- "reapareceu do nada" mais provável é o Studio ter revertido a exclusão
-- ao dar Stop no Play (edição feita DURANTE o Play não é salva) — vale
-- conferir isso também.
Config.OOB_HITBOX_WATCHDOG_ENABLED = false -- desligado agora pra você testar, como pedido

-- ===== GRUPOS DE COLISÃO =====
-- FIX: isso morava em PlayerSystems.lua, mas o BallController.lua já usa
-- o grupo "Bola" (ball.CollisionGroup = "Bola") assim que carrega — e como
-- scripts em ServerScriptService tendem a rodar em ordem alfabética,
-- BallController roda ANTES de PlayerSystems, então o grupo ainda não
-- existia nesse momento (erro/crash logo na linha 18 do BallController,
-- derrubando o resto do script: som, trilha da bola, drible, chute, tudo).
-- Registrando aqui, dentro do Config, garante que os grupos já existem
-- pra QUALQUER script que dê require(FootballConfig) antes de mexer em
-- CollisionGroup — e todo mundo faz esse require logo no topo.
-- ⚠️ v11: pedido — "alguns chutes saíram errado, como se o corpo tivesse
-- voltado a influenciar... eu mexi nos grupos de colisão". Isto aqui roda
-- de novo TODA VEZ que o server inicia (é um require, não algo que fica
-- só salvo no arquivo do Studio) — ou seja, qualquer ajuste manual feito
-- no painel de Collision Groups do Studio nos pares "Bola"x"Players" e
-- "Players"x"Players" é SOBRESCRITO por este código assim que o server
-- sobe. Se o corpo ainda estiver influenciando o chute depois disso, o
-- motivo provavelmente NÃO é esses dois pares (eles são forçados aqui) —
-- pode ser um grupo NOVO que você criou pra outra coisa (ex.: alguma Part
-- do campo/gol) que a Bola ou o Players passaram a usar sem querer, ou o
-- CampoHIT/gols (ver fix de CanCollide em OutOfBoundsController.legacy.
-- luau). Os warns abaixo agora aparecem no console se o pcall falhar (
-- antes falhava calado), pra facilitar achar isso na hora certa.
--
-- ⚠️ v11.1 FIX: PhysicsService só existe no SERVIDOR — como este Config é
-- um ModuleScript em ReplicatedStorage, ele roda uma vez quando o
-- SERVIDOR dá require (funciona normal) e OUTRA VEZ quando o CLIENTE de
-- cada jogador dá require (LocalScripts também fazem isso, ex.:
-- FootballClient.lua) — nessa segunda vez, TODA chamada de PhysicsService
-- falhava com "This API can only be used on the server!" (sempre falhou,
-- só que calado; os warns novos acima só deixaram isso visível). Sem
-- efeito real no jogo (o servidor, que manda de verdade, já tinha
-- aplicado certinho — por isso "Bola x Players = false" já aparecia
-- certo mesmo no log do Cliente, só lendo o valor real), mas poluía o
-- console. Agora só roda esse bloco inteiro no servidor.
if RunService:IsServer() then
	for _, name in ipairs({ "Players", "Bola" }) do
		local ok, err = pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
		if not ok then
			warn(("⚠️ FootballConfig: falha ao registrar o grupo de colisão '%s': %s"):format(name, tostring(err)))
		end
	end
	do
		local ok, err = pcall(function()
			PhysicsService:CollisionGroupSetCollidable("Bola", "Players", false)
		end)
		if not ok then
			warn("⚠️ FootballConfig: falha ao desligar colisão Bola x Players: " .. tostring(err))
		end
	end
	do
		local ok, err = pcall(function()
			PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
		end)
		if not ok then
			warn("⚠️ FootballConfig: falha ao desligar colisão Players x Players: " .. tostring(err))
		end
	end
	print(("⚽ FootballConfig: grupos de colisão aplicados — Bola x Players = %s | Players x Players = %s (deve ser sempre 'false' nos dois; se aparecer 'true', tem outro script/lugar reescrevendo isso depois)."):format(
		tostring(PhysicsService:CollisionGroupsAreCollidable("Bola", "Players")),
		tostring(PhysicsService:CollisionGroupsAreCollidable("Players", "Players"))
	))
end

-- ===== BASICO =====
Config.SET_PIECE_AUTO_LAUNCH_FORCE = 45
Config.BALL_NAME = "bola"
Config.MIN_PLAYERS_TO_START = 2
-- ⚠️ FIX: estava com o MESMO ID do place Game (118271624777790 é o
-- GAME_PLACE_ID configurado em Lobby/ReplicatedStorage/LobbyConfig.lua) —
-- ou seja, ao terminar a partida o TeleportAsync mandava todo mundo de
-- volta pro PRÓPRIO place Game (um server novo), não pro Lobby de
-- verdade. Isso é o que fazia "a partida reiniciar sozinha" (o
-- MatchController de novo servidor Game começa do zero) e também por
-- que o dinheiro ficava baixo: o TeleportData com MatchRewards nunca
-- chegava no LobbyRewardsReceiver.lua (que só existe no place Lobby).
Config.LOBBY_PLACE_ID = 119457952389149
Config.SUMMARY_DELAY_BEFORE_TELEPORT = 8

-- ===== TIMES =====
Config.TEAM_NAMES = { "Azul", "Amarelo" }

-- ===== SPAWN DE FORMAÇÃO (parts fixas no campo) =====
-- ⚠️ NOVO: em vez de calcular a posição de cada jogador por fração do
-- campo, agora cada vaga da formação usa uma PART fixa que você posiciona
-- no Studio — o padrão é sempre o modelo 7v7 (2 zagueiros, 2 meias, 2
-- atacantes), e os modelos 5v5/3v3 reaproveitam um SUBCONJUNTO dessas
-- mesmas parts (não precisa criar posições novas pra eles).
--
-- Nome de cada part = Config.SPAWN_PART_PREFIX .. NomeDoTime .. "_" .. Vaga
-- Ou seja, com os times atuais ("Azul"/"Amarelo"), as 14 parts são:
--   Spawn_Azul_GK,  Spawn_Azul_DF1,  Spawn_Azul_DF2,
--   Spawn_Azul_MF1, Spawn_Azul_MF2,  Spawn_Azul_FW1,  Spawn_Azul_FW2,
--   Spawn_Amarelo_GK,  Spawn_Amarelo_DF1,  Spawn_Amarelo_DF2,
--   Spawn_Amarelo_MF1, Spawn_Amarelo_MF2,  Spawn_Amarelo_FW1, Spawn_Amarelo_FW2
--
-- Todas invisíveis (Transparency = 1, CanCollide = false) — só a POSIÇÃO
-- e a ROTAÇÃO importam (o jogador nasce olhando pra LookVector da part,
-- então oriente cada uma virada pro gol adversário). No 5v5, o sistema
-- usa só GK/DF1/MF1/MF2/FW1 (ignora DF2/FW2); no 3v3, usa só GK/DF1/FW1.
-- Enquanto as parts de um time size específico não existirem, o
-- MatchController.lua cai pro cálculo antigo (por fração do campo) só
-- pra esse tamanho de time, sem quebrar nada.
Config.SPAWN_PART_PREFIX = "Spawn_"

-- ===== PARTIDA / TEMPOS =====
-- ⚠️ FALTAVAM: o MatchController.lua já usa esses dois (dois tempos de 4
-- min, com intervalo), mas eles nunca chegaram a existir aqui — o timer
-- quebrava (nil) na primeira vez que o loop rodava.
-- ⚠️ v33: era 3. PEDIDO: partida começa instantaneamente depois da cutscene,
-- sem "3, 2, 1". Voltar pra 3 reativa a contagem sem mexer em código.
Config.KICKOFF_COUNTDOWN = 0

-- ⚠️ v33: a quantos studs ATRÁS da bola o cobrador da saída fica plantado
-- (ver performKickoff). Zero o deixaria em cima da bola.
Config.KICKOFF_TAKER_OFFSET = 4
-- ⚠️ v52 — RELÓGIO "ESTICADO". PEDIDO: "coloque que cada rodada são 2
-- minutos, só que não são exatamente 2 minutos, são uns 2 minutos e meio."
-- E, pra prorrogação: "precisa ser 1 minuto EXATO, só que esse 1 minuto não
-- vai girar exatamente como um minuto: ele vai ser como se fosse 1 minuto e
-- 21, só que em formato de 1 minuto. Só pra poder FINGIR que é."
--
-- Então o relógio tem DOIS números, e eles são diferentes de propósito:
--   DISPLAY = o que o placar mostra e conta pra zero (redondo, bonito).
--   REAL    = quanto aquilo dura de verdade em segundos.
-- Um "segundo" do relógio dura REAL/DISPLAY segundos de verdade (ver
-- runPeriod em MatchController.legacy.luau). Com 120 mostrados em 150
-- reais, cada segundo do placar leva 1.25s — o jogador vê 2:00 contando
-- normalmente, mas tem 2min30 de jogo.
--
-- HALF_DURATION continua existindo com o valor de DISPLAY porque é ele que
-- a HUD usa; quem manda no tempo de verdade é HALF_REAL_SECONDS.
Config.HALF_DURATION = 120          -- o que aparece no placar: 2:00
Config.HALF_REAL_SECONDS = 150      -- o que dura de verdade: 2min30

-- ⚠️ v49 — PRORROGAÇÃO. PEDIDO: "quando der o overtime, o jogo estiver
-- EMPATADO, os caras vão ter aquele 1 minuto, só que vai ser 1 minuto mais
-- lento: vai ser 1 minuto a partir da DURAÇÃO DA MÚSICA que tiver aí. O
-- overtime vai ser definido a partir da duração dessa música."
--
-- Ou seja: a prorrogação dura exatamente o trecho tocável da música dela —
-- de OVERTIME_MUSIC_START_SECONDS até (duração - MUSIC_TAIL_CUT_SECONDS).
-- O servidor mede isso sozinho no início da partida (ver medirDuracaoDaProrrogacao
-- em MatchController.legacy.luau), então mudar a música muda o tempo junto,
-- sem tocar em número nenhum aqui.
--
-- Este valor abaixo é só a REDE DE SEGURANÇA: usado se o áudio não carregar
-- a tempo de informar a duração real (mesmo problema que o apito já tinha).
Config.OVERTIME_FALLBACK_SECONDS = 60

-- ⚠️ v52 — O QUE O PLACAR MOSTRA na prorrogação. PEDIDO: "precisa ser 1
-- minuto exato, só que esse 1 minuto vai ser como se fosse 1 minuto e 21,
-- em formato de 1 minuto. Só pra poder fingir que é."
-- Ou seja: mostra 1:00 e conta até zero, mas os 60 segundos do placar são
-- espalhados pelos ~82s reais da música (cada segundo do relógio dura
-- ~1.38s). O jogador lê "1 minuto"; o tempo de jogo é o da música.
Config.OVERTIME_DISPLAY_SECONDS = 60
-- ⚠️ v52 — PEDIDO: "entre as transições, pra virar de lado ou dar o
-- overtime, coloca só 3 segundos no máximo. O overtime tá com 15 segundos
-- pra começar, não pode ser." Era 15.
-- ⚠️ v112 — PEDIDO: "diminua os tempos de intervalo... vai direto pro segundo tempo... coloca pra ir direto pra iniciar a partida, meio segundo depois do teleporte, pra não ter enrolação".
Config.HALFTIME_BREAK_DURATION = 0 -- segundos de intervalo entre os tempos (era 3)

-- ===== MOVIMENTO / STAMINA =====
Config.NORMAL_SPEED = 22
Config.SPRINT_SPEED = 38
-- ⚠️ NOVO — PEDIDO: "Não haverá botão de corrida/sprint. O personagem deve
-- correr normalmente usando WASD, e sua velocidade será determinada pelo
-- atributo Velocidade." O Shift/botão SPRINT saiu (ver PlayerSystems.
-- legacy.luau e FootballClient.local.luau): todo movimento é corrida, na
-- velocidade RUN_SPEED x multiplicador de Velocidade (SPEED_MULTIPLIER_*).
-- Igual ao antigo SPRINT_SPEED de propósito — é o ritmo em que o jogo foi
-- balanceado (drible, carrinho, animação de Run). NORMAL_SPEED continua
-- existindo só como referência do ritmo de ANDAR da animação (ver
-- refreshTrackSpeed em PlayerSystems). Quer o jogo mais lento? Baixe só
-- este número.
Config.RUN_SPEED = 38
-- PEDIDO: menos stamina MÁXIMA base, mas recuperando bem mais rápido —
-- em vez de aguentar sprintar por muito tempo seguido, o jogador cansa
-- mais rápido só que volta a poder agir logo em seguida (menos "correr
-- sem parar", mais "dar uma pausa curta e continuar").
-- ⚠️ v67 — PEDIDO: "aumente um pouco a stamina base, 20%". 45 -> 54.
Config.BASE_STAMINA = 54            -- era 45 (+20%)
Config.STAMINA_PER_ATTRIBUTE_POINT = 10
-- ⚠️ NOVO: sem sprint, o Fôlego não é mais gasto correndo — só pelas AÇÕES
-- físicas (finta, cabeçada, carrinho — ver *_STAMINA_COST). SPRINT_DRAIN_
-- RATE ficou sem uso; mantido só pra não quebrar quem ainda leia o campo.
Config.SPRINT_DRAIN_RATE = 20
Config.RECOVERY_RATE = 24           -- era 15
Config.EXHAUSTED_RECOVERY_RATE = 8  -- era 5 — junto com a recuperação base maior
Config.EXHAUSTED_DURATION = 2

-- ===== CONTROL LOCK (Shift Lock, tecla Ctrl) =====
-- Puramente client-side: trava o mouse no centro e deixa a câmera girar
-- livremente (sem precisar segurar botão), com o personagem acompanhando
-- a direção da câmera. Não mexe em WalkSpeed, não mexe em nada relativo à
-- bola, e por isso não existe config nem remote aqui — é tudo tratado
-- direto no FootballClient.lua.

-- ===== BOLA / POSSE =====
Config.POSSESSION_PICKUP_RADIUS = 6

-- PEDIDO: facilitar pegar bola NO AR. Mesma ideia do mergulho do goleiro
-- (GK_DIVE_CAPTURE_HEIGHT): decompõe a captura em horizontal/vertical em
-- vez de distância 3D cheia, senão a altura da bola "come" o raio de
-- pickup inteiro e ninguém consegue dominar um cruzamento/lançamento.
--
-- AERIAL_PICKUP_*: pickup PASSIVO (só andando por baixo, sem apertar
-- nada) — só ganha a tolerância de altura generosa se o jogador estiver
-- LENTO (não sprintando, ver AERIAL_PICKUP_MAX_PLAYER_SPEED); sprintando,
-- continua na distância 3D cheia de sempre (community: "domina no peito
-- andando", não correndo).
Config.AERIAL_PICKUP_HEIGHT = 10             -- studs: tolerância vertical do pickup passivo (jogador LENTO)
Config.AERIAL_PICKUP_MAX_PLAYER_SPEED = 20   -- studs/s: acima disso (sprintando) não conta como "lento"

-- TACKLE_AERIAL_CAPTURE_HEIGHT: mesma decomposição horizontal/vertical,
-- só que pro CARRINHO (que já ignora LOOSE_BALL_PICKUP_MAX_SPEED — dá pra
-- carrinhear bola solta rápida mesmo antes desse pedido). PEDIDO NOVO:
-- carrinhar uma bola RÁPIDA ou no AR só funciona se o Drible do jogador
-- estiver no nível mínimo — abaixo disso, o carrinho erra igual sempre
-- (não é qualquer um que controla uma bola voando rápido no peito/pé).
Config.TACKLE_AERIAL_CAPTURE_HEIGHT = 10
-- ⚠️ NOVO: "controle de bolas difíceis" é da TÉCNICA agora (era o
-- DribbleSkill) — ver Config.TECHNIQUE_ATTRIBUTE. Mesmo número de corte.
Config.TACKLE_FAST_BALL_MIN_TECHNIQUE = 60 -- 0-100: nível mínimo de Técnica pra carrinhar bola rápida/no ar
Config.DRIBBLE_OFFSET = 1
Config.DRIBBLE_HEIGHT_OFFSET = -2.6
Config.DRIBBLE_CHASE_GAIN = 25
-- ⚠️ v5.3: mola VERTICAL usada só enquanto o jogador está no AR, pro
-- drible aéreo. No chão a bola usa uma mola fraca (a altura quase não
-- muda); no ar, com o alvo subindo ~7 studs de uma vez, a mola fraca
-- perdia pra gravidade e pular virava perder a bola.
Config.DRIBBLE_AERIAL_CHASE_GAIN = 9
Config.DRIBBLE_MAX_CHASE_SPEED = 40
Config.DRIBBLE_TURN_RATE_THRESHOLD = 2.0
Config.DRIBBLE_TURN_LOOSE_MULTIPLIER = 3.5
Config.DRIBBLE_MAX_LOOSE_EXTRA = 4.5
Config.DRIBBLE_EXPOSE_THRESHOLD = 1.8
Config.DRIBBLE_BOB_AMPLITUDE = 0.25
Config.DRIBBLE_BOB_FREQUENCY = 6
-- ⚠️ v104 — BOLA NOS PÉS. PEDIDO: "a bola estar na sua frente, como se
-- fosse sob o seu domínio... ele esteja se movendo mesmo assim, a bola está
-- ali na frente dele, nos pés dele". Com a posse, quem simula a bola é o
-- CLIENTE de quem tem a posse (BolaNosPes.local.luau): ela fica colada na
-- frente dos pés todo quadro, sem o atraso da rede. O servidor só confere.
Config.BOLA_NOS_PES_LIGADO = true
Config.BOLA_NOS_PES_DISTANCIA = 1.75   -- studs do centro do corpo ao centro da bola (na frente)
Config.BOLA_NOS_PES_TOQUE = 0.35       -- correndo: a bola "vai e volta" um pouco (os toques de condução)
Config.BOLA_NOS_PES_TOQUE_FREQ = 9     -- toques por segundo (em radianos/s ÷ 2π ≈ 1.4 toques/s) quando correndo
Config.BOLA_NOS_PES_DIST_MAX = 9       -- o servidor retoma a bola se ela estiver mais longe que isso do dono

-- REWORK: BallControl foi removido (o controle de bola em curvas
-- rápidas agora usa o mesmo DribbleSkill do drible — ver getDribbleSkill
-- no BallController.lua). Em troca, entram dois atributos que fazem
-- sentido separados: VELOCIDADE (corrida normal/sprint) e CHUTE (força
-- do chute e quem cobra escanteio).
Config.SPEED_ATTRIBUTE = "Speed"
Config.DEFAULT_SPEED = 50
-- Multiplicador de WalkSpeed em cima de NORMAL_SPEED/SPRINT_SPEED: no
-- valor default (50) o multiplicador é exatamente 1.0 (não muda nada
-- pra quem nunca mexeu no atributo). PEDIDO: quem tem Speed alto (ex.:
-- 63) estava sentindo diferença grande demais em campo — diminuída
-- parcialmente a faixa (era 0.85x-1.15x, ±15%; agora 0.90x-1.10x, ±10%),
-- ainda dá vantagem real por investir no atributo, só que mais comedida.
Config.SPEED_MULTIPLIER_MIN = 0.90
Config.SPEED_MULTIPLIER_MAX = 1.10

-- ⚠️ v5.6: PEDIDO — "a velocidade de caminhada do goleiro GK, ele está
-- muito lento, pode duplicar a velocidade dele". ⚠️ v5.7: REVERTIDO — o
-- usuário esclareceu que era sobre o GKBOT (ver GKBOT_WALK_SPEED acima),
-- não o Role="GK" HUMANO. Mantido em 1.0 (sem diferença nenhuma) pra não
-- quebrar quem já chama Config.GK_SPEED_MULTIPLIER em algum lugar.
Config.GK_SPEED_MULTIPLIER = 1.0

Config.KICK_ATTRIBUTE = "Kick"
Config.DEFAULT_KICK = 50
-- Multiplicador em cima de KICK_MAX_FORCE (o teto de força que dá pra
-- carregar no chute): 0.85x em Kick=0, 1.0x no default (50), 1.15x no
-- teto (100) — mesma faixa da Velocidade, pra ficar consistente.
Config.KICK_FORCE_MULTIPLIER_MIN = 0.85
Config.KICK_FORCE_MULTIPLIER_MAX = 1.15

-- ===== FINTA (DRIBLE DIRECIONAL Z esquerda / X trás / C direita) =====
Config.DRIBBLE_SKILL_ATTRIBUTE = "DribbleSkill"
Config.DEFAULT_DRIBBLE_SKILL = 50

-- ⚠️ NOVO: atributo ENERGY — alimenta o sistema de Pulsos (hissatsus),
-- junto com Kick (chute)/Physic (defesa e goleiro). Mesmo padrão dos
-- outros atributos de skill (0-100, default 50, migrado/sorteado no
-- PlayerDataManager.legacy.luau do Lobby, repassado via TeleportData —
-- ver onPlayerAdded no PlayerSystems.lua). Não gasta/recupera aqui — o
-- CONSUMO de energy por Pulso ainda vai ser controlado por outro
-- sistema (o PulseController que vamos construir); isso aqui é só o
-- ATRIBUTO base (quanto Energy o personagem tem pra alimentar a fórmula
-- de força), igual Kick/Physical já funcionam pros outros sistemas.
Config.ENERGY_ATTRIBUTE = "Energy"
Config.DEFAULT_ENERGY = 50
-- ⚠️ NOVO — PEDIDO: "Energia é um RECURSO, e não um atributo que aumenta
-- diretamente a potência das Hissatsus... Não fazer 'mais Energia =
-- Hissatsu mais forte'." REMOVIDOS ENERGY_FORCE_MULTIPLIER_MIN/MAX (o
-- atributo multiplicava a força do chute de Hissatsu) e o bônus de cliques
-- do QTE por Energy (ver startHissatsuQTE em PulseController). O atributo
-- Energy agora só decide o TAMANHO do tanque (PULSE_ENERGY_POOL_MIN/MAX —
-- Energy 50 = tanque de 100) e cada Hissatsu custa energia pra usar
-- (PULSE_ENERGY_COST_BY_RARITY, ou o EnergyCost da própria Hissatsu).

-- ===== TÉCNICA (7º atributo) =====
-- ⚠️ NOVO — PEDIDO: "Técnica representa a habilidade geral do jogador com a
-- bola: domínio, primeiro toque, recepção de passes, controle de bolas
-- difíceis, precisão de passes... Hissatsus que utilizem Técnica". Mesmo
-- padrão dos outros atributos de skill (0-100, default 50 = neutro,
-- sorteado/migrado no PlayerDataManager do Lobby, repassado via
-- TeleportData — ver onPlayerAdded no PlayerSystems.lua). Não é mecânica
-- nova: escala o que JÁ existia no BallController —
--   • domínio/primeiro toque: raio de pickup da bola solta
--     (POSSESSION_PICKUP_RADIUS);
--   • recepção de passe / bola difícil: velocidade máxima de bola que dá
--     pra dominar passivamente (LOOSE_BALL_PICKUP_MAX_SPEED) e altura da
--     bola aérea dominável (AERIAL_PICKUP_HEIGHT);
--   • bola rápida/no ar no carrinho: TACKLE_FAST_BALL_MIN_TECHNIQUE (era
--     o Drible que decidia isso);
--   • precisão de passe: o desvio de mira do PASSE lê Técnica em vez de
--     Chute (hoje o desvio está zerado — ver AIM_DEVIATION_* — então só
--     passa a valer se você religar o desvio).
-- Todos os multiplicadores são 1.0x no default (50): quem nunca mexeu no
-- atributo não sente diferença nenhuma.
Config.TECHNIQUE_ATTRIBUTE = "Technique"
Config.DEFAULT_TECHNIQUE = 50
-- ⚠️ v98 — TÉCNICA REMOVIDA (PEDIDO: "verifica se realmente é algo bom de
-- se manter, senão remove a técnica, e os buffs das Hissatsus pelos seus
-- atributos"). Com a mira perfeita por projeto, "precisão de passe" não
-- existe mais; o resto (domínio, primeiro toque, recepção, bola difícil) é
-- controle de bola = DRIBLE. Então: tudo acima passa a ler o Drible, e as
-- fórmulas das Hissatsus (PulseInstinctData) só usam o atributo da
-- categoria. No Lobby ela some da ficha e não recebe mais ponto. true = volta
-- ao comportamento antigo.
Config.USAR_TECNICA = false
Config.TECHNIQUE_PICKUP_RADIUS_MULT_MIN = 0.85   -- Técnica 0
Config.TECHNIQUE_PICKUP_RADIUS_MULT_MAX = 1.15   -- Técnica 100
Config.TECHNIQUE_RECEIVE_SPEED_MULT_MIN = 0.85   -- bola mais rápida que dá pra dominar
Config.TECHNIQUE_RECEIVE_SPEED_MULT_MAX = 1.15
Config.TECHNIQUE_AERIAL_HEIGHT_MULT_MIN = 0.85   -- bola aérea mais alta que dá pra dominar
Config.TECHNIQUE_AERIAL_HEIGHT_MULT_MAX = 1.15

-- Multiplicador genérico 0-100 -> MIN..MAX (mesma curva linear de todos os
-- atributos do jogo: 50 = meio da faixa).
function Config.AttributeCurve(value, minMult, maxMult)
	local fraction = math.clamp(tonumber(value) or 50, 0, 100) / 100
	return minMult + (maxMult - minMult) * fraction
end

-- ===== ESCALA DE HISSATSU POR ATRIBUTO (fórmula própria por Hissatsu) =====
-- ⚠️ NOVO — PEDIDO: "Cada Hissatsu poderá utilizar atributos diferentes
-- para determinar sua potência... Hissatsu ofensiva: 60% Chute + 40%
-- Técnica; outra: 70% Físico + 30% Técnica". Cada Hissatsu em
-- PulseInstinctData.luau pode declarar
--     Scaling = { Kick = 0.6, Technique = 0.4 }
-- (nomes internos dos atributos, pesos somando 1). A POTÊNCIA BASE continua
-- sendo o que a Hissatsu já define (ForceMult do Bom/Perfect, raridade,
-- raios/durações do efeito) — a fórmula só decide QUAL nota de atributo
-- (média ponderada 0-100) entra nas curvas que já existiam:
--   • força do chute de Hissatsu: curva KICK_FORCE_MULTIPLIER_* (antes era
--     sempre Kick x Energy);
--   • tamanho/potência de área: curva PULSE_EFFECT_POWER_SCALE_* (antes um
--     atributo fixo por categoria);
--   • cliques extras e janela do QTE "Tap" (antes era a Energy).
-- Hissatsu SEM Scaling cai no atributo da categoria, igual sempre foi
-- (HISSATSU_DEFAULT_SCALING logo abaixo). Energy e Stamina NUNCA entram
-- na fórmula: Energy é recurso (custo), Stamina é Fôlego (escala própria).
Config.HISSATSU_SCALABLE_ATTRIBUTES = {
	Physical = "DEFAULT_PHYSICAL",
	Kick = "DEFAULT_KICK",
	DribbleSkill = "DEFAULT_DRIBBLE_SKILL",
	Speed = "DEFAULT_SPEED",
	Technique = "DEFAULT_TECHNIQUE",
}

-- Fórmula padrão de quem não declara Scaling — exatamente o atributo que
-- cada categoria já lia antes (GK/desarme/Root = Físico, chute/cabeçada =
-- Chute, drible = Drible). Buff de linha sem categoria = sem escala.
function Config.GetHissatsuScaling(def)
	if type(def) ~= "table" then return nil end
	if type(def.Scaling) == "table" then return def.Scaling end
	if def.RoleRequired == "GK" then return { Physical = 1 } end
	if def.Action == "Shot" or def.Action == "Header" then return { Kick = 1 } end
	if def.Action == "DribbleMove" then return { DribbleSkill = 1 } end
	if def.Action == "Tackle" or def.Action == "Root" then return { Physical = 1 } end
	return nil
end

-- Nota 0-100 do jogador pra ESTA Hissatsu: média ponderada dos atributos da
-- fórmula. Pesos são normalizados (não precisam somar exatamente 1).
-- Devolve nil se a Hissatsu não escala com nada.
function Config.GetHissatsuAttributeRating(player, def)
	local scaling = Config.GetHissatsuScaling(def)
	if not scaling then return nil end
	local total, weightSum = 0, 0
	for attrName, weight in pairs(scaling) do
		local defaultKey = Config.HISSATSU_SCALABLE_ATTRIBUTES[attrName]
		if defaultKey and typeof(weight) == "number" and weight > 0 then
			local value = player:GetAttribute(attrName)
			if typeof(value) ~= "number" then value = Config[defaultKey] or 50 end
			total += math.clamp(value, 0, 100) * weight
			weightSum += weight
		elseif attrName == "Energy" or attrName == "Stamina" then
			warn(("[Hissatsu] %s: '%s' não pode entrar em Scaling (Energy é custo, Stamina é Fôlego) — ignorado."):format(tostring(def.Name), attrName))
		end
	end
	if weightSum <= 0 then return nil end
	return total / weightSum
end

-- ===== v8 PEDIDO: "as duas coisas juntas" — alcance máximo (MaxRange)
-- por raridade + multiplicador de poder por raridade pros Pulsos de
-- CHUTE (Action="Shot"), pra equilibrar a chance de fazer gol numa
-- determinada distância. Common/Rare/Legendary foram interpolados a
-- partir dos dois valores que o usuário deu de referência (Epic=220,
-- Mythic=330); pode pedir pra ajustar se não bater com o esperado.
-- ⚠️ NOVO: PEDIDO — "diminua um pouco a força dos pulsos de chute (geral)
-- ... eu só devia ter dificuldade contra a mesma raridade (ou GK), ou uma
-- raridade inferior só que perto". Reduzido ~12-15% em toda a tabela (só
-- afeta Pulso de CHUTE — chute normal/Instinto não usam essa tabela, só
-- KICK_MAX_FORCE puro, então ficam do jeito que estavam).
Config.PULSE_RARITY_POWER_MULT = {
	Common = 0.85,
	Rare = 0.95,
	Epic = 1.05,
	Legendary = 1.15,
	Mythic = 1.35,
}
Config.PULSE_RARITY_MAX_RANGE = { -- em studs
	Common = 140,
	Rare = 170,
	Epic = 220,
	Legendary = 270,
	Mythic = 330,
}

-- ⚠️ NOVO: ordem crescente de raridade — usada pra achar "a próxima mais
-- baixa que existe" ao montar o Pulso de goleiro do GKBOT (ver
-- assignGKBotPulseForTeam em GKBotController.legacy.luau: "se não existir
-- pulso comum, ou raro, peguei o próximo da mais baixa raridade").
Config.PULSE_RARITY_ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }

-- ⚠️ v36 NOVO: "faça o tamanho do pulso, e a sua potência (congelamento,
-- tamanho da skill de GK, atordoamento) ser maior dependendo de seu
-- respectivo status especial pra essa habilidade afetar, GK = Físico, FW
-- (chute) = Força de Chute, Drible = Drible". Escala os campos de ÁREA/
-- TAMANHO dos Pulsos (FreezeRadius/Duration, StunRadius/Duration,
-- DiveRadiusAdd, GuardSize, KnockbackRadius/Force, RagdollRadius/Duration,
-- AnkleRangeAdd, BlockRadius/Impulse — ver applyPulsePowerScale em
-- PulseController.legacy.luau) pelo atributo certo pra CADA categoria de
-- Pulso: goleiro (RoleRequired="GK") usa Physical, chute (Action="Shot")
-- usa Kick, drible (Action="DribbleMove") usa DribbleSkill, desarme
-- (Action="Tackle") usa Physical também (ainda é força física, só que na
-- defesa). ⚠️ NOVO: isso virou só o PADRÃO — a Hissatsu que declara
-- Scaling usa a própria fórmula (ver Config.GetHissatsuScaling). Mesma curva MIN/DEFAULT/MAX de sempre (ver getKickForceMultiplier
-- em BallController.lua): 0.75x no atributo 0, 1.0x no default (50), 1.30x
-- no atributo 100.
Config.PULSE_EFFECT_POWER_SCALE_MIN = 0.75
Config.PULSE_EFFECT_POWER_SCALE_MAX = 1.30

-- "Chip do zagueiro": defensor perto o bastante do chute de Hissatsu tem
-- essa chance base de cortar o bônus de raridade/tier (ajustada um
-- pouco pela diferença de Physical) — é o principal jeito de um
-- goleiro+zagueiro em dupla pararem um Mythic quase imparável 1x1.
Config.PULSE_DEFENDER_CHIP_CHANCE = 0.55
Config.PULSE_DEFENDER_CHIP_RANGE = 12
-- Teto de força só pros Pulsos de Chute (bem mais alto que o 1.6x
-- genérico de Passe/Cobrança) — sem isso o cap antigo apagava toda a
-- diferença entre raridades altas.
Config.PULSE_SHOT_FORCE_CAP_MULT = 6.0

-- ⚠️ v85 — MIRA DA HISSATSU SEM ASSISTENTE: o ponto sob o cursor é usado
-- exatamente como vem (ver _G.PulseComputeShotTarget no BallController e
-- computeAimPoint em HissatsuInput.local.luau). Saíram PULSE_AIM_MAX_DROP/
-- MAX_RISE (travas de altura) e PULSE_AIM_ASSIST_STRENGTH (assistência).
-- MIN_HORIZONTAL fica: mira com menos que isso de distância na horizontal
-- (cursor no próprio pé) não aponta pra lugar nenhum, e o servidor usa a
-- mira automática de canto do gol adversário.
Config.PULSE_AIM_MIN_HORIZONTAL = 6

-- ⚠️ NOVO: PEDIDO — "coloque um print também, pra eu saber exatamente qual
-- o número em cada lugar, e quanto a skill de GK ou DF tiraram, pra poder
-- equilibrar". Liga/desliga TODOS os prints de debug de força de Pulso
-- (base, raridade, tier do QTE, decaimento por distância, chip do
-- zagueiro, bloqueio da Muralha) em BallController.legacy.luau — desligue
-- (false) quando não precisar mais ficar lendo o Output.
Config.PULSE_FORCE_DEBUG_PRINTS = true

-- ⚠️ v38 — FORÇA CAINDO EM TEMPO REAL DURANTE A DEFESA.
-- PEDIDO: "mostre em tempo real, enquanto o goleiro estiver defendendo a
-- Hissatsu, a força da Hissatsu diminuindo" / "pode colocar a força
-- caindo em tempo real na defesa."
--
-- O número já caía durante o VOO (por distância percorrida) e congelava
-- exatamente no instante em que a bola batia na guarda — o momento mais
-- importante, o cabo de guerra goleiro × chute. Agora, durante a janela
-- em que a bola fica congelada na guarda, ele DRENA (ver
-- beginGuardForceDrain em BallController.legacy.luau).
--
-- O ritmo vem do FÍSICO do goleiro: goleiro fraco come a força devagar
-- (MIN), goleiro máximo come rápido (MAX). Isso é leitura do duelo, NÃO
-- decide nada — quem decide pegou/passou continua sendo a regra de
-- sempre (Físico vs força + QTE do humano / sorteio do bot). No fim da
-- defesa o número é fechado: PEGOU = 0 (absorveu tudo), PASSOU = para no
-- valor drenado, que mostra o quão perto o goleiro chegou de segurar.
Config.PULSE_GUARD_DRAIN_MIN_PER_SECOND = 90
Config.PULSE_GUARD_DRAIN_MAX_PER_SECOND = 260
-- Quanto tempo o número final fica na tela depois da defesa resolver —
-- sem isso ele pisca e some junto com a resolução, sem dar pra ler.
Config.PULSE_GUARD_DRAIN_LINGER_SECONDS = 1.1
-- Cor do número enquanto está sendo drenado (vermelho "sob pressão"),
-- pra diferenciar na hora do amarelo normal do voo.
Config.PULSE_GUARD_DRAIN_COLOR = Color3.fromRGB(255, 110, 90)

-- ⚠️ NOVO: ARRANCADA SELVAGEM / INVESTIDA TITÂNICA (pedido: "é pra dar um
-- dash reto em direção à bola/adversário, o player não se move, o script
-- move ele pra frente sozinho, como um carrinho só que mais longo") —
-- velocidade do dash em studs/segundo (a distância total percorrida é
-- Speed * QTE.Duration daquele Pulso — ver _G.StartPulseDashTackle em
-- BallController.legacy.luau). Mais lento que o carrinho normal
-- (TACKLE_DASH_FORCE=50) DE PROPÓSITO: esse dash dura o QTE inteiro
-- (2-2.5s), não uma fração de segundo — na mesma velocidade do carrinho
-- ele atravessaria o campo inteiro instantaneamente.
Config.PULSE_DASH_TACKLE_SPEED = 24
-- Raio mínimo (fallback) da hitbox de roubo/acerto quando o Pulso não
-- define HitboxRadius no Bom/Perfect — não deveria acontecer na prática
-- (ver PulseInstinctData.lua), só uma rede de segurança.
Config.PULSE_DASH_TACKLE_MIN_HITBOX = 4

-- ⚠️ NOVO: PEDIDO — "a força dos chutes não está diminuindo por stud,
-- estou conferindo pelo texto em cima da bola e não está diminuindo".
-- Causa real: havia uma "zona cheia" sem decaimento nenhum até
-- PULSE_RANGE_FALLOFF_START (0.65) do alcance, e a maioria dos chutes de
-- verdade no campo nunca percorre distância suficiente pra sair dessa
-- zona plana — por isso o número nunca se mexia. Removida a zona plana:
-- agora o decaimento é LINEAR DESDE O PRIMEIRO STUD (100% na distância 0)
-- até travar em PULSE_RANGE_FALLOFF_MIN no alcance máximo da raridade —
-- visível em qualquer chute, e continua valendo "quanto maior a
-- raridade, menos diminui por stud" (o alcance máximo de cada raridade
-- controla a INCLINAÇÃO dessa reta: Common cai rápido em 140 studs,
-- Mythic estica a mesma queda até 330 studs, bem mais suave por stud).
Config.PULSE_RANGE_FALLOFF_MIN = 0.7

-- ⚠️ v103 — DUELO DE DEFESA. PEDIDO: "assim que uma hissatsu de chute colidir
-- com uma hissatsu de defesa ou gol, esse diminuidor de força com a distância
-- vai parar, e a força vai ficar paralisada. o que vai começar a dar dano é
-- quantas vezes o defensor ou GK acertarem a hissatsu deles. ex: chegou no gol
-- com 130 de vida, GK usa a mão demoníaca, acerta 2 QTEs, tira 100 de vida,
-- sobra 30, bola continua sua trajetória e volta o diminuidor por distância."
-- Dano de CADA acerto no QTE da Hissatsu de defesa, pela raridade dela (vezes
-- a escala de atributo da própria Hissatsu — Físico pro goleiro, ~1.0 na nota
-- 50). Acerto perfeito (faixa dourada) vale DEFESA_DANO_PERFEITO_MULT.
-- ⚠️ v105 — REGRA DA MESMA RARIDADE. PEDIDO: "chute e defesa épicos, os dois
-- com 50 de força/físico: do MEIO do campo, a Hissatsu do goleiro consegue
-- defender. Da mesma raridade chutando de PERTO (um pouco na frente da área),
-- não aguenta." Calibrado com as contas reais (campo 25% maior: meio ≈ 354
-- studs do gol, frente da área ≈ 130): do meio, o chute PERFECT da mesma
-- raridade cai dentro de 5 acertos BONS; da frente da área, o chute BOM passa
-- mesmo com 5 acertos PERFEITOS. Vale pra todas as raridades (era 22/28/36/43/50
-- — o goleiro comum/raro/lendário segurava até de perto, o mítico mal segurava
-- do meio). Físico 100 dá +27% de dano por acerto; Chute 100 dá +15% de força.
-- E a regra CRUZADA (pedido seguinte): "não é pra uma mítica não conseguir
-- defender uma épica... dá até pra uma lendária não conseguir uma épica se a
-- lendária sair ruim e a épica forte contra ela; senão não faz sentido".
-- Então o goleiro de raridade R, com 5 acertos BONS, segura o chute PERFECT
-- da raridade de baixo até na frente da área. Pra caber as duas regras, a
-- Zona Morta (Lendária) e a Galáxia (Mítica) subiram de força (PulseInstinctData).
-- v110 — PEDIDO: "-4 de força por acerto é foda; a Hissatsu mais fraca tem ~100 de
-- vida de perto, a defesa comum tem que conseguir parar ela". Era 12/23/34/49/70.
Config.DEFESA_DANO_POR_ACERTO = { Common = 30, Rare = 38, Epic = 46, Legendary = 58, Mythic = 70 }
Config.DEFESA_DANO_PERFEITO_MULT = 1.15
-- ⚠️ v107 — IMPACTO DA DEFESA. PEDIDO: "com a Galáxia do meio de campo, 300 de
-- força, o GK acertou algumas e só tirou 150... são duas míticas, tem que ter
-- briga. Mesmo com a maior desvantagem do mundo, ele tira 200 de 300, sobra 100".
-- Antes a defesa inteira vinha dos acertos (5 x 70 na mítica) — errar 3 QTEs
-- derrubava a defesa pra 40%. Agora a CAPACIDADE da Hissatsu de defesa é
-- DANO_POR_ACERTO x RequiredHits (mesmo total de antes com todos os acertos), e
-- metade dela entra de uma vez no IMPACTO (a mão/soco encontra a bola); a outra
-- metade é dividida pelos acertos. Mítica x mítica do meio (300): neutro e 5
-- acertos = 350 (segura); fraqueza elemental (x0.8) e 2 acertos = 196 (sobra ~100).
Config.DEFESA_IMPACTO_FRACAO = 0.5
-- Goleiro BOT (sem QTE de verdade): "aperta" a cada GKBOT_DUELO_INTERVALO
-- segundos com essa chance de acertar, até o número de acertos da Hissatsu dele.
Config.GKBOT_DUELO_CHANCE_ACERTO = 0.6
Config.GKBOT_DUELO_INTERVALO = 0.45
-- ⚠️ v105: bot que PERDE o duelo fica atordoado esse tempo (a bola passa e entra —
-- antes ele mergulhava/afastava a bola logo depois e jogava a Hissatsu pra fora)
Config.GKBOT_ATORDOADO_APOS_FALHA = 1.6

-- ⚠️ v9 PEDIDO original: "aumente um pouquinho a força dos chutes" — essa
-- definição de Config.KICK_MAX_FORCE ficava AQUI (152), mas era
-- reatribuída DE NOVO mais abaixo na seção "===== CHUTE" (linha ~949,
-- valor 145) — igual o bug duplicado que já foi achado e corrigido em
-- Config.PULSE_RANGE_FALLOFF_START/MIN. Como Lua só fica com a ÚLTIMA
-- atribuição, esse aumento pra 152 NUNCA esteve em vigor de verdade (o
-- jogo sempre rodou com 145) — removida a duplicata morta daqui; o valor
-- de verdade continua editável só na seção CHUTE, mais abaixo.

-- ⚠️ v9 PEDIDO: "energia de ativação da Hissatsu, relacionada ao atributo
-- Energy" — ⚠️ NOVO: é o ÚNICO papel do atributo Energy agora (ele não
-- mexe mais na força de nada, ver Config.ENERGY_ATTRIBUTE): um "combustível" que
-- todo Pulso Hissatsu (chute/defesa/arrancada/drible) GASTA pra ativar,
-- que também escala com o atributo Energy (mais Energy = pool maior).
-- Mostrado na HUD (ver AbilityHUD.local.luau) e verificado em
-- Remotes.UsePulse (ver PulseController.legacy.luau).
--
-- ⚠️ NOVO: PEDIDO — "a energia só recarrega no segundo tempo, ela está
-- recarregando passivamente, e isso não pode acontecer". Removida a
-- regeneração passiva por tempo (não existe mais nenhum "ticker" somando
-- energia sozinho, parado ou não, ver PulseController.legacy.luau) — o
-- pool só ENCHE de novo no início de cada tempo (kickoff do 1º e do 2º
-- tempo, ver _G.ResetPulseEnergy chamado por performKickoff em
-- MatchController.legacy.luau), nunca ambiente/contínuo durante o jogo.
Config.PULSE_ENERGY_POOL_MIN = 60  -- pool máximo com atributo Energy = 0
-- ⚠️ v108 — PEDIDO: "a energia tá bufando muito pouco... se você maximizar a
-- energia, você ganha 200 a mais além do normal — pra usar duas Hissatsus
-- míticas todas as vezes possíveis na partida". Era 140 no máximo; agora 340
-- (140 + 200). Energy 50 = 200 (2 míticas e meia), Energy 100 = 340 (4 míticas).
Config.PULSE_ENERGY_POOL_MAX = 340 -- pool máximo com atributo Energy = 100
Config.PULSE_ENERGY_COST = 35 -- fallback: usado só se a raridade não estiver na tabela abaixo

-- ⚠️ v27 — CUSTO DE ENERGIA POR RARIDADE.
-- PEDIDO: "Hissatsu mítica só pode ser usada no máximo DUAS vezes na mesma
-- rodada, mesmo com todos os atributos no máximo. Com pelo menos 50 pontos
-- você consegue usar uma gastando toda a energia; com 100, duas. Lendária
-- três, épica quatro, rara cinco."
--
-- A conta fecha com o pool que já existe (PULSE_ENERGY_POOL_MIN/MAX): com
-- Energy 100 o pool é 140, com Energy 50 é 100.
--   Mítica 70  -> 140/70 = 2 usos no máximo; com pool 100, dá 1 (gastando
--                 quase tudo, que é exatamente o que você descreveu).
--   Lendária 46 -> 3 usos.  Épica 35 -> 4.  Rara 28 -> 5.  Comum 22 -> 6.
-- E como o pool SÓ reenche no intervalo, esse teto vale por tempo de jogo,
-- não por partida inteira.
-- ⚠️ v28 — COOLDOWN GERAL DAS ARMAS (Instintos), por raridade.
-- PEDIDO: "desenha o cooldown geral das armas separado."
--
-- Regra que amarra os dois sistemas: uma Arma SEMPRE recarrega mais rápido
-- que uma Hissatsu da mesma raridade (ver PULSE_* acima — Mítica 120s lá,
-- 90s aqui). Faz sentido porque a Arma é passiva//situacional e a Hissatsu
-- é um golpe deliberado.
--
-- COMO SE APLICA (ver InstinctController.legacy.luau):
--   • Arma de BOTÃO (Chute Direto, Matador): é o tempo entre dois apertos.
--   • Arma CONTÍNUA ("Instant"): começa a contar quando o efeito DESLIGA —
--     mesma lógica que o Pique já usava com CooldownSeconds.
--   • Arma de EVENTO (chute/carrinho/passe): tempo entre dois disparos.
-- Uma Arma que declara o próprio número (CooldownSeconds/AtivaCooldown)
-- continua mandando — a tabela só preenche quem não declarou.
Config.INSTINCT_COOLDOWN_BY_RARITY = {
	Common = 20,
	Rare = 30,
	Epic = 40,
	Legendary = 60,
	Mythic = 90,
}

-- ⚠️ v28 — O QTE "Tap" DA HISSATSU ESCALA COM ATRIBUTO.
-- ⚠️ NOVO: não é mais a Energy (Energia é recurso, não potência) — é a nota
-- da FÓRMULA da própria Hissatsu (Scaling, ver Config.GetHissatsuAttribute-
-- Rating): um chute 60% Chute + 40% Técnica ganha cliques com esses dois.
-- MAX_BONUS_HITS: quantos alvos EXTRA a nota pode liberar, além dos que
--   a Hissatsu já define. 3 no máximo (nota 100), 0 no mínimo.
-- WINDOW_BONUS: quanto a janela de clique cresce na nota 100 (+70%).
--   Cresce mais rápido que os alvos de propósito — senão atributo alto
--   viraria punição, com mais alvo pra clicar no mesmo tempo.
-- BONUS_HIT_FORCE: quanto de força cada clique EXTRA acrescenta ao chute.
Config.HISSATSU_QTE_MAX_BONUS_HITS = 3
Config.HISSATSU_QTE_WINDOW_BONUS = 0.7
Config.HISSATSU_QTE_BONUS_HIT_FORCE = 0.06

Config.PULSE_ENERGY_COST_BY_RARITY = {
	Common = 22,
	Rare = 28,
	Epic = 35,
	Legendary = 46,
	Mythic = 70,
}

-- ⚠️ v12 (Instinto "Olho de Predador"): a que distância do próprio gol o
-- goleiro já conta como "adiantado", ou seja, de guarda baixa. Ver
-- goalkeeperOffGuard em BallController.legacy.luau. Subir esse número
-- torna o Instinto mais raro (exige o goleiro MUITO fora do lugar).
Config.INSTINCT_GK_OFF_LINE_DISTANCE = 12

-- ⚠️ v63 — PEDIDO: "faça a distância BASE do drible se adequar ao tempo" e
-- "quanto mais upado for, o drible vai mais longe — você altera na distância
-- E na velocidade da reprodução."
--
-- A animação de drible dura 0.583s. A 18 studs/s, esse tempo cobre
-- 18 x 0.583 = 10.5 studs. Então a distância BASE virou 10.5: um drible sem
-- nenhum upgrade percorre exatamente o que a animação percorre, e ela toca na
-- velocidade natural dela (1.00x), sem esticar nem acelerar.
--
-- A partir daí o DribbleSkill leva a distância até 15.6. Como a janela é
-- distância / velocidade, ela cresce junto — e a animação é reajustada pra
-- caber nela (ver `ajustarPara` em playAnimation). É isso que faz o upgrade
-- aparecer nos DOIS lugares que você pediu: vai mais longe e a reprodução
-- acompanha.
--   base  (skill 0)   -> 10.5 studs, 0.583s, animação a 1.00x
--   máximo (skill 100) -> 15.6 studs, 0.867s, animação a 0.67x
-- ⚠️ v67 — PEDIDO: "aumente a distância do drible padrão, 15%". As DUAS
-- pontas sobem juntas pra a escala por DribbleSkill continuar a mesma —
-- subir só a base achataria a diferença entre iniciante e maximizado.
-- A janela continua fixa (DRIBBLE_ANIMATION_SECONDS), então isso também
-- deixa o drible mais RÁPIDO na mesma proporção.
-- ⚠️ v104 — PEDIDO: "quando você dribla, ele dá o dash dele depois, sempre,
-- independente do que aconteça. O drible só dá esse dash de vantagem se você
-- realmente driblar alguém — se alguém sofrer um ankle breaker". O que parecia
-- dash era o PRÓPRIO deslocamento base (12-18 studs em 0.58s). Agora o drible
-- normal é só o rolamento (passo curto) e a arrancada vem no mini-dash, que só
-- existe quando alguém cai (DRIBBLE_MINIDASH_* abaixo). Driblando alguém, o
-- total continua o de antes (12-18).
Config.DRIBBLE_MOVE_MIN_DISTANCE = 4 -- era 12.1
Config.DRIBBLE_MOVE_MAX_DISTANCE = 6 -- era 17.9
-- A finta de HISSATSU (Pulso de drible) continua com o alcance longo de antes:
Config.DRIBBLE_HISSATSU_MIN_DISTANCE = 12.1
Config.DRIBBLE_HISSATSU_MAX_DISTANCE = 17.9
-- ⚠️ v64 — PEDIDO: "faz a outra: mais longe E mais rápido."
--
-- ANTES a velocidade era fixa em 18 e a JANELA é que crescia com o nível
-- (distância / velocidade) — resultado: quanto mais upado, mais LENTA ficava
-- a animação (chegava a 0.67x, câmera lenta no jogador melhor).
--
-- AGORA a janela é fixa, igual à duração da animação, e quem escala é a
-- VELOCIDADE: a distância cresce com o DribbleSkill dentro do MESMO tempo,
-- então o drible fica mais longo e mais rápido ao mesmo tempo, e a animação
-- toca a 1.00x em qualquer nível.
--   base   (skill 0)   -> 10.5 studs em 0.583s = 18.0 studs/s
--   máximo (skill 100) -> 15.6 studs em 0.583s = 26.8 studs/s
--
-- A janela é a duração da ANIMAÇÃO de drible. Se você reexportar as três com
-- outra duração, troque aqui e tudo se reajusta sozinho — a distância não
-- muda, só o tempo em que ela é percorrida (e a reprodução continua em 1x,
-- porque playAnimation recebe esta janela como alvo).
Config.DRIBBLE_ANIMATION_SECONDS = 0.583

-- Mantida só como REFERÊNCIA da velocidade-base (é o valor que sai da conta
-- com skill 0). Não é mais usada pra calcular a janela.
Config.DRIBBLE_MOVE_TRAVEL_SPEED = 18
-- PEDIDO (atualizado): cooldown reduzido pra 1s — a finta volta a poder
-- ser usada bem mais rápido (era 2s, que por sua vez tinha vindo de 0.5s
-- pra evitar spam; o custo de stamina abaixo continua segurando o spam).
Config.DRIBBLE_MOVE_COOLDOWN = 2      -- ⚠️ v104: "muito spamável... dobra o tempo dele" (era 1; antes 0.5, depois 2)
Config.DRIBBLE_MOVE_STAMINA_COST = 14 -- era 8
Config.TACKLE_STUN_ON_FAILED_TIMING = 1.2

-- Ankle breaker: se a finta acontece com um adversário perto o
-- suficiente (ele estava tentando marcar/acompanhar), esse adversário
-- leva um RAGDOLL (cai de verdade, sem controle) por
-- ANKLE_BREAKER_RAGDOLL_DURATION segundos — o "caiu no chão de tanto que
-- balançou" — seguido de um stun (sem controle, mas já de pé) até
-- completar ANKLE_BREAKER_STUN no total. Só afeta ADVERSÁRIOS (checagem
-- de time no BallController), nunca companheiros de time por perto.
-- Ragdoll PRÓPRIO (não é o Humanoid.StateType.Ragdoll nativo, que só
-- funciona em R15) — desliga os Motor6D e liga BallSocketConstraint solta
-- no lugar, então funciona igual em R6 e R15, sem precisar de nenhum
-- objeto novo no Studio (ver ragdollPlayer no BallController.lua).
Config.ANKLE_BREAKER_RANGE = 5   -- alcance, a partir da posição do driblador no instante da finta, pra um adversário ser considerado "perto o suficiente" pra ser enganado
Config.ANKLE_BREAKER_RAGDOLL_DURATION = 1  -- novo — segundos de ragdoll de verdade
Config.ANKLE_BREAKER_STUN = 1  -- era 0.5 — tempo total sem controle (cobre o ragdoll inteiro + levantar)

-- MINI-DASH pós-drible: se a finta REALMENTE derrubou um adversário
-- (ankle breaker acertou), o driblador ganha uma distância extra na
-- mesma deslizada, pra não perder a vantagem depois de acertar o
-- drible. Em DribbleSkill=0 o mini-dash é só a distância-base; em
-- DribbleSkill=100 (skill=1) ele chega a MAX_MULT vezes essa distância-
-- base — não escala em cima da distância normal do drible inteiro
-- (isso deixaria muito OP), só em cima desse valor pequeno próprio.
Config.DRIBBLE_MINIDASH_BASE_DISTANCE = 8 -- ⚠️ v104: a arrancada de vantagem (era 3.5) — distância extra com DribbleSkill = 0
Config.DRIBBLE_MINIDASH_MAX_MULT = 1.5    -- ⚠️ v104: 8 -> 12 com DribbleSkill = 100 (era 2.5)

-- ===== ATRIBUTO FÍSICO (usado no CARRINHO, disputa de bola solta, e
-- agora também no tamanho do personagem/hitbox — ver onCharacterAdded
-- no PlayerSystems.lua) =====
Config.PHYSICAL_ATTRIBUTE = "Physical"
Config.DEFAULT_PHYSICAL = 50
-- Escala de corpo (BodyWidthScale/BodyDepthScale, R15) em cima do
-- Physical: no default (50) fica em 1.0 (tamanho normal); baixa até
-- PHYSICAL_SCALE_MIN em Physical=0 e sobe até PHYSICAL_SCALE_MAX em
-- Physical=100. Isso muda o hitbox de verdade (a geometria de colisão
-- escala junto), não só o visual. Reservado também pro sistema futuro
-- de "bola bate no corpo e reduz a velocidade" — quanto maior o
-- Physical, maior a área de corpo que pode tocar a bola.
Config.PHYSICAL_SCALE_MIN = 0.92
Config.PHYSICAL_SCALE_MAX = 1.12
Config.PHYSICAL_HEIGHT_SCALE_MIN = 0.97 -- altura escala menos que largura/profundidade, pra não virar um gigante
Config.PHYSICAL_HEIGHT_SCALE_MAX = 1.06

-- ===== BOLA FORA (lateral / escanteio / tiro de meta) =====
Config.FIELD_HITBOX_NAME = "CampoHIT"
Config.BLUE_GOAL_NAME = "GolAzul" -- era "BlueGoal" — pedido: renomeado no Studio junto com o campo novo
Config.YELLOW_GOAL_NAME = "GolAmarelo"

-- ⚠️ NOVO SISTEMA DE BOLA FORA — PARTS PRECISAS EM VEZ DE MATEMÁTICA DE
-- EIXO: em vez de decidir "saiu ou não saiu" só comparando a posição da
-- bola contra o tamanho do CampoHIT (que pode não bater exatamente com o
-- gramado visual), agora existem duas PARTS que você mesmo posiciona no
-- Studio, cobrindo fisicamente cada região de saída de bola — precisam
-- ser invisíveis (Transparency = 1) e SEM COLISÃO FÍSICA (CanCollide =
-- false; pode deixar CanTouch = false também, já que a detecção não usa
-- Touched, só a posição da bola a cada frame — CanQuery pode ficar true,
-- é só o padrão) — servem só de "marcador"/gabarito de onde cada evento
-- acontece:
--
-- 1) Nome "OutLateral" — DUAS parts (uma pra cada lateral do campo),
--    cobrindo a faixa fora de cada linha lateral, comprida o bastante
--    pra cobrir o campo inteiro (comprimento) e "grossa"/alta o
--    suficiente pra pegar a bola tanto rolando quanto no ar (lateral
--    alta). Sem Attribute nenhum — o time que cobra é sempre decidido
--    por quem tocou por último (igual já era).
--
-- 2) Nome "OutFundo" — DUAS parts (uma atrás de cada gol), cobrindo TODA
--    a largura de trás do gol (inclusive as pontas fora da boca do gol,
--    onde rola escanteio) — cada uma precisa ter um Attribute
--    "DefendingTeam" (string) igual a um dos Config.TEAM_NAMES ("Azul"
--    ou "Amarelo") indicando de QUEM é aquele fundo de campo (mesmo time
--    que defende o gol daquele lado). O tipo (escanteio vs. tiro de
--    meta) continua decidido por quem tocou a bola por último, igual já
--    era — a part só marca ONDE fica "atrás da linha de fundo" daquele
--    lado.
--
-- Enquanto essas parts não existirem na cena, o OutOfBoundsController.lua
-- cai de volta sozinho pro método antigo (matemática de eixo do CampoHIT)
-- pra cada tipo que ainda estiver faltando — não quebra nada até você
-- posicionar as parts nos dois places... digo, na cena.
Config.OUT_LATERAL_ZONE_NAME = "OutLateral"
Config.OUT_FUNDO_ZONE_NAME = "OutFundo"
Config.OUT_FUNDO_TEAM_ATTRIBUTE = "DefendingTeam"

-- ===== ÁREA DO GOLEIRO (gate de habilidades por posição) =====
-- NOVO: as habilidades exclusivas de goleiro (mergulho/AttemptGKDive,
-- dash/AttemptGKForward, e o Pulso do slot único dele, tecla R) só
-- funcionam enquanto ele estiver DENTRO da própria área. Se ele sair,
-- os controles viram os de um jogador de linha normal (Z/X/C = finta,
-- Q/E = os 2 slots de Pulso normais) — ver GKAreaUtil.lua (Replicated-
-- Storage) e o uso em BallController.lua/PulseController.lua (servidor)
-- e GKInput/PulseInput/DribbleInput.local.lua (cliente).
--
-- PRECISA CRIAR NO STUDIO: 1 Part invisível, SEM colisão física
-- (CanCollide = false; CanQuery pode ficar true), cobrindo a grande área
-- de cada gol — uma por time, nome = prefixo + nome do time
-- (Config.TEAM_NAMES):
--   GKArea_Azul
--   GKArea_Amarelo
-- Enquanto a Part de um time não existir, o goleiro DAQUELE time nunca é
-- barrado por área (sempre conta como "dentro") — fallback seguro, igual
-- o resto do sistema de zonas acima.
Config.GK_AREA_PART_PREFIX = "GKArea_"

-- ⚠️ NOVO: "o aviso de GKArea/CutsceneTunnel não encontrada nunca some,
-- mesmo perto do gol" — causa raiz confirmada: Workspace.StreamingEnabled
-- com Workspace.StreamingTargetRadius (padrão do Roblox, ~1024 studs)
-- menor que a distância real dessas Parts até o spawn/câmera do jogador
-- no campo novo (maior). Isso NUNCA vai se autocorrigir sozinho enquanto
-- o raio de streaming do cliente for pequeno demais pro tamanho do mapa —
-- GKAreaUtil.lua usa esse valor pra alargar o raio de streaming de todo
-- cliente logo no carregamento (ver bloco "if RunService:IsClient()"
-- perto do fim deste comentário, dentro de GKAreaUtil.lua).
Config.CLIENT_STREAMING_TARGET_RADIUS = 4096

-- ===== GOLEIRO BOT (substitui quando não tem jogador humano no gol) =====
-- Se nenhum jogador do time estiver com Role == "GK", um bot assume a
-- posição — a menos que Config.CLOSED_TEAM_MODE esteja true, aí ninguém
-- substitui e um humano é obrigatório (esse modo "time fechado" ainda
-- não tem uma tela própria no Lobby pra ativar/desativar — por enquanto
-- é só esse toggle manual; quando o modo "time fechado" de verdade for
-- construído, é só ele setar essa flag antes da partida começar).
Config.CLOSED_TEAM_MODE = false

-- PRECISA CRIAR NO STUDIO: 1 Model chamado exatamente "GKBot" dentro de
-- ServerStorage (não Workspace — é só o MOLDE, clonado por time quando
-- necessário), com um Humanoid + HumanoidRootPart dentro (igual um NPC
-- comum) — ver GKBotController.lua.
Config.GKBOT_TEMPLATE_NAME = "GKBot"

-- Raio (studs): se o dono da bola adversário chegar mais perto que isso
-- do bot, ele toma a bola na hora (equivalente a "alguém se aproximar
-- demais").
-- ⚠️ AUMENTADO (pedido: "aumenta um pouco a hitbox do gk, pra ele pegar
-- mais fácil a bola") — era 6.
-- ⚠️ v5.7: REDUZIDO pra 6 (pedido: "deixe um pouco mais próximo do gol
-- pra ele começar a correr atrás do atacante") — só um dos dois gatilhos
-- do bote (ver GKBOT_BOTE_RANGE abaixo pro outro).
Config.GKBOT_CATCH_APPROACH_RADIUS = 6

-- Raio (studs) da "defesa" do bot em cima da trajetória prevista da bola
-- solta (chute/cruzamento vindo na direção dele). ⚠️ AUMENTADO (era 5,
-- mesmo pedido de hitbox maior).
-- ⚠️ v111 — PEDIDO: "aumente a distância dos dives do GK Bot, 50% maior — tanto pra cima, quanto pra diagonal, quanto pros lados"
Config.GKBOT_SHOT_REACT_RADIUS = 18 -- ⚠️ v111: 12 -> 18 (+50%: tenta o dive de mais longe) -- ⚠️ v105: era 7 — "faça o GK dar mais dives": reage a mais chutes

-- Só reage a bola solta se ela já estiver a essa distância (studs, no
-- plano do chão) do bot — evita o bot reagir a um chute do outro lado do
-- campo. ⚠️ AUMENTADO (era 30): junto com a previsão de trajetória com
-- gravidade (ver GKBOT_TRAJECTORY_PREDICT_*), o bot agora começa a
-- calcular ANTES — precisa enxergar o chute de mais longe pra isso valer
-- a pena.
-- ⚠️ v5.8: AUMENTADO (era 40) — pedido: "o GK bot pega a bola, mas
-- normalmente está sendo tarde, depois de ocorrer o gol, deixe um windup
-- um pouquinho maior". Reage ao chute de MAIS LONGE, ganhando mais tempo
-- de reação antes da bola chegar na linha.
Config.GKBOT_SHOT_REACT_MAX_RANGE = 55

-- Tempo mínimo (segundos) entre duas ações do bot (rouba/defende),
-- pra não disparar 2x seguido no mesmo lance.
-- ⚠️ v5.7: PEDIDO — "aumente a velocidade de reação do GK BOT pra ele
-- pegar mais rápido" (esclarecido: era pro BOT, não pro Role="GK" humano —
-- ver PlayerSystems.legacy.luau, revertido lá). Era 1.5.
Config.GKBOT_ACTION_COOLDOWN = 0.6

-- Força do "alívio" (afastar a bola do próprio gol) depois de repelir
-- (só quando a tentativa de AGARRAR falha — ver GKBOT_CATCH_* abaixo).
Config.GKBOT_CLEAR_FORCE = 45

-- ⚠️ NOVO (bot agarra em vez de só repelir): o bot SEMPRE tenta agarrar
-- primeiro nos 2 gatilhos que já existiam (adversário chegou perto /
-- bola solta vindo na direção dele) — só cai pro "repelir" (clearBall,
-- acima) se a tentativa de agarrar falhar.
--
-- Distância (studs, plano do chão) acima da qual o bot NUNCA consegue
-- agarrar (falha automática — bola longe demais).
-- ⚠️ AUMENTADO (era 12) — mesmo pedido de hitbox maior: "pra ele pegar
-- mais fácil a bola".
-- ⚠️ v6.3: AUMENTADO de novo (era 15) — pedido: "aumente um pouco a
-- hitbox do GK".
-- ⚠️ v6.5: DIMINUÍDO BEM (era 17) — pedido: "o GKBOT está pegando a bola
-- sem dar o dive de longe agora, ele precisa encostar na bola pra pegar,
-- pode diminuir bem a hitbox, se isso for efeito dela". Agora que a
-- agarrada por contato é DETERMINÍSTICA (tryContactCatch, v6.4), uma
-- hitbox grande fazia ele "agarrar à distância" sem precisar se mover.
-- Cobrir distância maior volta a ser trabalho do mergulho/perseguição
-- (GKBOT_DIVE_REACH/GKBOT_CHASE_SPEED), não da hitbox de contato.
-- ⚠️ v67 — PEDIDO: "o goleiro bot não está pegando algumas bolas que são
-- essenciais; pode melhorar um pouco mais o bot também". 6.5 -> 8.5.
Config.GKBOT_CATCH_MAX_RANGE = 8.5 -- ⚠️ v110: de volta a 8.5 (v109 tinha subido pra 10) ("aumenta um pouco a hitbox") -- era 6.5 (+31%)

-- Ângulo (graus) entre "de frente pro campo" (linha do próprio gol até o
-- gol adversário) e a direção bot→bola — acima disso, falha automática
-- (bola chegando de um ângulo fechado demais / por trás, ele não alcança).
Config.GKBOT_CATCH_MAX_ANGLE = 92 -- ⚠️ v35: era 115 (original 75) -- ⚠️ v22: era 75 — bola cruzando rente ao lado dele caía fora do cone e era ignorada.

-- Chance de agarrar quando a bola está bem em cima do bot (distância ~0)
-- e a distância no limite de GKBOT_CATCH_MAX_RANGE — interpola entre os
-- dois conforme a distância (quanto mais perto, mais fácil, como pedido).
Config.GKBOT_CATCH_CHANCE_AT_ZERO = 0.95
-- ⚠️ v6.3: AUMENTADO (era 0.10) — pedido: "melhore um pouco mais o dive do
-- bot, pra dificultar pros players". Sem isso, aumentar só o ALCANCE do
-- mergulho (GKBOT_DIVE_REACH/DIAGONAL_KICK/UP_SPEED abaixo) seria inútil
-- perto do limite: ele chegava mais longe, mas quase sempre falhava a
-- pegada mesmo assim (10% de chance). Agora, no limite do alcance, ele
-- ainda erra a maioria das vezes, mas defende bem mais que antes.
Config.GKBOT_CATCH_CHANCE_AT_MAX = 0.18

-- ⚠️ NOVO: PEDIDO — "o GK tem em base todos os status juntos de todos os
-- jogadores do campo, dividido pelo numero de jogadores... e isso também
-- conta pra defender chutes de pulso igual o gk (player) consegue com
-- físico... atualmente o GKBOT cata pulso com facilidade, após adicionar
-- essa melhoria, não vai ser 100% garantido". O bot NÃO é um Player (não
-- tem atributo Physical próprio) — em vez disso, Physical/Energy dele são
-- a MÉDIA de todos os jogadores em campo (ver getGKBotPhysical/
-- getGKBotEnergy). Dentro do alcance/ângulo normais (GKBOT_CATCH_MAX_RANGE/
-- _ANGLE acima) a pegada só é 100% garantida se esse Physical médio for
-- >= a nota de perigo do chute (igual o goleiro humano); abaixo disso, vira
-- uma CHANCE proporcional (nunca 0%, nunca 100%) — reaproveita
-- GKBOT_CATCH_CHANCE_AT_ZERO/_AT_MAX acima como os extremos dessa curva.
Config.GKBOT_CATCH_PHYSICAL_CHANCE_MIN = 0.2 -- chance mínima quando o físico médio está BEM abaixo da força do chute
Config.GKBOT_CATCH_PHYSICAL_CHANCE_MAX = 0.85 -- chance máxima quando o físico médio quase alcança a força do chute (mas ainda não é Hissatsu-proof)

-- ⚠️ NOVO: janela (segundos), a partir do chute de Pulso, dentro da qual
-- a bola saindo pela LATERAL do campoHit é considerada "voou por cima por
-- causa do pulso" — nesse caso o reinício vai direto pro goleiro do time
-- OPOSTO a quem chutou (ver OutOfBoundsController.legacy.luau), em vez da
-- regra normal de lateral (jogador mais perto).
Config.PULSE_OUT_OF_BOUNDS_WINDOW = 1.5

-- ⚠️ NOVO: PEDIDO — "ele só usará o pulso contra hissatsus, ele vai mirar
-- e usar a habilidade exatamente quando o pulso de chute sair, na direção
-- dela, e vai acertar aleatóriamente". Chance de a defesa reativa do
-- GKBOT (usando o Pulso de goleiro atribuído a ele, ver
-- assignGKBotPulseForTeam) realmente ACERTAR/anular o chute — sorteada de
-- novo a cada Hissatsu recebida, nunca garantida.
-- ⚠️ v23: NÃO É MAIS USADO. A decisão do GKBOT de usar a Hissatsu de
-- goleiro deixou de ser sorteio e virou cálculo de força (ver o listener de
-- _G.RegisterPulseShotListener em GKBotController.legacy.luau). Mantido só
-- pra não quebrar nada que ainda leia a chave.
Config.GKBOT_PULSE_DEFENSE_HIT_CHANCE = 0.5

-- ⚠️ v23 — TETO DO MERGULHO NORMAL DO GKBOT (em força de chute).
-- Chute de Hissatsu ABAIXO disso ele segura mergulhando, sem gastar a
-- Hissatsu de goleiro; ACIMA, ele dispara a Hissatsu na hora. Interpola
-- pelo Físico do bot: 0 = MIN, 100 = MAX.
-- Referência do pedido: a Hissatsu mais fraca do jogo sai com ~80 de força
-- ("podia ser que ele conseguisse") e uma Mítica com ~250 ("não era pra
-- ele conseguir com um pulo normal") — com o Físico padrão (50), o teto
-- fica em 125, o que deixa exatamente esse resultado.
-- ⚠️ v39 — PEDIDO (correção do próprio usuário sobre o número anterior):
-- "na real eu falei merda. Pro humano pegar normalmente é entre 50 e 70 de
-- força que ele pegaria dando dive. 70 no nível MÁXIMO. Não é 100 e 120."
-- Então: Físico 0 = 50, Físico 100 = 70. Uma Hissatsu de 200 não é mais
-- pegável com mergulho comum em NENHUM nível — só com a Hissatsu de
-- goleiro de pé, que é o ponto.
Config.GKBOT_NORMAL_SAVE_FORCE_MIN = 50
Config.GKBOT_NORMAL_SAVE_FORCE_MAX = 70 -- ⚠️ v39: era 92 (e 160 antes disso).

-- Quanto tempo a Hissatsu de goleiro do bot fica valendo depois de
-- disparada. Era 0.4s fixo e expirava antes da bola chegar num chute de
-- longe — precisa cobrir o voo inteiro.
Config.GKBOT_PULSE_DEFENSE_WINDOW = 2.5

-- ⚠️ v24 — CHANCE DA HISSATSU DO GOLEIRO PEGAR. Ela sempre SAI (ele sempre
-- tenta); isto decide se ela funciona. Interpola pelo "nível do campo" — a
-- média dos atributos de todos os jogadores em partida (ver
-- fieldSkillFraction em GKBotController.legacy.luau): campo fraco = perto
-- do mínimo, campo todo maximizado = perto do máximo.
-- ⚠️ v26: por quanto tempo o bot LEMBRA que uma Hissatsu está vindo pra cima
-- dele (ver attemptCatch). Precisa cobrir o voo inteiro, inclusive bola que
-- quica ou que ele persegue — era esse tempo curto, no antigo rating por
-- janela, que deixava uma Galáxia de 320 ser pega como bola normal.
Config.GKBOT_INCOMING_SHOT_MEMORY = 6

-- ⚠️ v28: por quanto tempo a placa "PEGOU/ERROU" fica na tela em cima do bot.
Config.GKBOT_RESULT_LABEL_SECONDS = 2.2

-- ⚠️ v38 — JANELA DE DEFESA DO BOT (pra a força poder cair em tempo real).
-- O goleiro HUMANO já tinha essa janela de graça: a bola congela na
-- guarda e o QTE de colisão roda. O bot resolvia tudo no MESMO frame do
-- contato, então não sobrava instante nenhum pra mostrar força caindo.
-- Agora a bola dele congela no contato por esse tempo, a força drena
-- (PULSE_GUARD_DRAIN_* acima) e só então o sorteio de pegou/passou rola.
-- Mexer aqui muda só a DURAÇÃO do momento — não muda a chance dele pegar
-- (isso é GKBOT_PULSE_HIT_CHANCE_MIN/MAX).
Config.GKBOT_GUARD_DRAIN_SECONDS = 0.75
-- Velocidade que a bola ganha ao ATRAVESSAR a guarda do bot. Durante o
-- congelamento a velocidade dela vai a zero, então sem esse empurrão ela
-- só cairia na frente do goleiro em vez de continuar entrando. É o mesmo
-- valor que o goleiro humano usa quando a guarda dele falha.
Config.GKBOT_GUARD_BREAKTHROUGH_SPEED = 12
-- ⚠️ v39 — Knockback do SOCO EXPLOSIVO (a única guarda de goleiro que
-- nunca segura a bola, ver Rebate = true em PulseInstinctData). Ela
-- defende com sucesso e devolve a bola pro campo; esse é o preço dela, e
-- é o que a descrição dela sempre prometeu.
Config.GKBOT_PUNCH_REBOUND_FORCE = 85
-- Mesma coisa pro goleiro HUMANO usando o Soco Explosivo (ver o QTE de
-- colisão da guarda em BallController.legacy.luau).
Config.GK_PUNCH_REBOUND_FORCE = 85
-- ⚠️ v39 — Janelinha depois que a guarda resolve em que resolveCatchOrClear
-- NÃO chama clearBall. A guarda já deu à bola a velocidade certa (entrando
-- no gol quando passou, ou o knockback quando rebateu) e clearBall
-- sobrescreveria as duas.
Config.GKBOT_GUARD_RESOLVE_GRACE = 0.6
-- ⚠️ v40 — INTERCEPTAÇÃO DE HISSATSU (pedido: "a partir do momento que
-- alguém usar uma Hissatsu de chute, o goleiro precisa ir imediatamente
-- pra posição onde a bola está indo, pra poder utilizar a Hissatsu dele...
-- coloca pra ele poder ficar retinho").
--
-- Por quanto tempo, depois de a Hissatsu sair, o goleiro fica com o alvo
-- TRAVADO no ponto onde a bola vai cruzar o plano do gol (calculado uma
-- vez só, exato — chute de Hissatsu voa reto e sem gravidade). Durante
-- essa janela ele corre pra lá na velocidade de perseguição, para no
-- ponto e fica de frente pro campo, reto, em vez de ficar acompanhando a
-- bola de um lado pro outro. A janela é limpa antes da hora assim que a
-- defesa resolve.
--
-- Precisa ser >= o tempo de voo de uma Hissatsu lenta de longe. Curto
-- demais: ele destrava no meio do voo e volta a bailar. Longo demais: ele
-- fica plantado depois da jogada já ter passado.
Config.GKBOT_INTERCEPT_HOLD_SECONDS = 4
-- Até onde ele pode ir pros lados PERSEGUINDO uma Hissatsu já no ar, como
-- fração da meia-largura do gol (1.0 = exatamente o poste).
-- GKBOT_LATERAL_GOAL_FRACTION (0.65) continua valendo pro descanso, que é
-- pra ele não ficar colado num poste com o gol aberto do outro lado — mas
-- usar 0.65 também numa defesa em andamento deixava os 35% externos do gol
-- INALCANÇÁVEIS (num gol de 60, ele nunca passava de 19.5 do centro), e
-- qualquer Hissatsu no canto já estava ganha antes de sair do pé.
Config.GKBOT_INTERCEPT_GOAL_FRACTION = 0.92

-- ===== CÂMERA DO JOGADOR =====
-- ⚠️ v42 — PEDIDO: "limita a câmera pra não poder tirar muito zoom. Deixa
-- ele usar só o zoom padrão ou ficar em primeira pessoa se quiser
-- aumentar o zoom. O zoom padrão é o zoom MÁXIMO que ele pode dar."
--
-- MAX = o quanto ele pode AFASTAR. 12.5 é exatamente a distância padrão em
-- que a câmera do Roblox já nasce, então "padrão" vira o teto: ninguém
-- abre mais que isso pra enxergar meio campo de cima.
-- MIN = o quanto ele pode APROXIMAR. 0.5 mantém a primeira pessoa
-- disponível pra quem quiser (é o mínimo padrão do Roblox).
-- Aplicado por jogador em PlayerSystems.legacy.luau (onPlayerAdded).
-- ===== HIGHLIGHT DO PERSONAGEM =====
-- ⚠️ v47 — A cor do contorno é a COR DO TIME (azul no azul, amarelo no
-- amarelo) — ver updateHighlight em PlayerSystems.legacy.luau. O v45 tinha
-- unificado os dois em amarelo e foi longe demais: o pedido de lá era só
-- parar de PINTAR O CORPO, não apagar a identidade de time.
--
-- "Um pouco mais fino": Highlight não tem espessura no Roblox (não existe
-- OutlineWidth). O que afina a leitura do traço é o DepthMode Occluded
-- (feito no script) mais um tanto de transparência aqui — 0 dá o traço
-- cheio e pesado, perto de 1 some. 0.35 deixa um fio visível sem virar
-- faixa. Suba se quiser ainda mais discreto.
Config.HIGHLIGHT_OUTLINE_TRANSPARENCY = 0.35

-- ===== SOMBRA DA BOLA =====
-- ⚠️ v45 — PEDIDO: "um círculo que aparece quando alguém chutar a bola.
-- Quanto mais perto a bola estiver do chão, MAIOR o círculo; quanto mais
-- longe, MENOR. Mostra mais ou menos onde a bola vai cair. Um círculozinho,
-- como se fosse uma sombra, bem no chão, encostado ao chão."
-- Desenhada em StarterPlayerScripts/BallShadowClient.local.luau.
--
-- ATENÇÃO ao sentido do tamanho: é o CONTRÁRIO de uma sombra física (que
-- encolhe ao se aproximar). Está assim porque foi pedido assim, e
-- confirmado no pedido. Se um dia quiser o comportamento físico, basta
-- trocar MIN_SIZE por MAX_SIZE aqui — o script não precisa mudar.
-- ⚠️ v112 — PEDIDO: "a sombra da bola pode aparecer sempre... coloca um tamanho
-- mínimo; mesmo muito distante ela não pode sumir, só fica no tamanho certo, pro
-- cara ter uma ideia mínima de onde vai cair a bola". Mínimo 3 -> 4 e nunca some.
Config.BALL_SHADOW_MIN_SIZE = 4     -- bola no alto (círculo pequeno — nunca menor que isso)
Config.BALL_SHADOW_MAX_SIZE = 10    -- bola rente ao chão (círculo grande)
-- Altura (studs) em que a sombra já está no tamanho MÍNIMO. Acima disso
-- não encolhe mais.
Config.BALL_SHADOW_MAX_HEIGHT = 45
-- ⚠️ v51 — ALTURA MÍNIMA pra sombra aparecer. PEDIDO: "não é porque a bola
-- está se movimentando que ela tem que mostrar a sombra, ela tem que estar
-- NO AR." Antes a condição era VELOCIDADE (BALL_SHADOW_MIN_SPEED, removida),
-- e por isso bola rolando pelo gramado também marcava sombra.
-- A outra condição, "sem domínio de ninguém", não tem número: é posse, e o
-- cliente sabe por Remotes.PossessionChanged.
Config.BALL_SHADOW_MIN_HEIGHT = 3
-- Transparência da marca: mais apagada com a bola alta, mais escura perto.
Config.BALL_SHADOW_MAX_TRANSPARENCY = 0.82 -- (v112: não usado — ver BALL_SHADOW_MIN_ALPHA)
-- ⚠️ v112: opacidade mínima da marca com a bola bem alta (0 = some, 1 = cheia)
Config.BALL_SHADOW_MIN_ALPHA = 0.7
-- ⚠️ v112: até onde procura o chão embaixo da bola (antes era 1.5 x MAX_HEIGHT = 67
-- studs — bola mais alta que isso não achava o chão e a sombra sumia)
Config.BALL_SHADOW_RAY_LENGTH = 600
Config.BALL_SHADOW_MIN_TRANSPARENCY = 0.35 -- bola rente ao chão
-- ⚠️ v51: a textura foi REMOVIDA. PEDIDO: "arruma a sombra, ela tá muito
-- estranha, parece que é uma skin. Ela tem que ser um círculo embaixo da
-- bola." Um asset de imagem traz borda, formato e proporção próprios e não
-- garante um círculo limpo. Agora a marca é a geometria em si: uma Part com
-- Shape = Cylinder achatada, que vista de cima é um círculo perfeito por
-- definição — sem imagem e sem depender de asset nenhum.
-- Espessura do disco (só pra ele ter corpo e não sumir em z-fighting com o
-- gramado; ele é reposicionado meio disco acima do ponto do chão).
Config.BALL_SHADOW_THICKNESS = 0.08

Config.CAMERA_MAX_ZOOM_DISTANCE = 12.5
Config.CAMERA_MIN_ZOOM_DISTANCE = 0.5

Config.GKBOT_PULSE_HIT_CHANCE_MIN = 0.22
Config.GKBOT_PULSE_HIT_CHANCE_MAX = 0.58

-- Quanto tempo (segundos) o bot segura a bola depois de agarrar, antes
-- de lançar pra um alvo.
Config.GKBOT_HOLD_DURATION = 3

-- ⚠️ v5.9: PEDIDO — "o goleiro pegou a bola e depois contou gol... acho
-- que ele está pegando dentro da área e depois contando". Distância
-- MÍNIMA (studs, medida a partir do próprio gol, eixo fieldForward) que a
-- bola SEGURA (Holding) precisa manter — se a captura aconteceu perto
-- demais da própria linha, holdPositionFor empurra a bola pra frente até
-- bater essa distância, em vez de só somar um deslocamento fixo a partir
-- de onde o bot estava (que podia não ser suficiente pra sair da hitbox
-- do gol — ver GKBotController.legacy.luau).
Config.GKBOT_HOLD_SAFE_DISTANCE = 6

-- Tempo de voo (segundos) usado pra calcular a velocidade do lançamento
-- depois do agarre — física de projétil de verdade (ver computeThrowVelocity
-- em GKBotController.lua), não é uma força fixa. Usado como TETO (o valor
-- máximo) e também no tiro de meta (GKBotTakeGoalKick — sempre uma
-- distância grande, faz sentido o arco cheio).
-- ⚠️ v16: era 1.1 — esse teto era o que quebrava o passe longo (ver o
-- comentário em throwBall, GKBotController.lua). 2.2 deixa a proporção
-- "velocidade de pouso constante" valer até passes de campo inteiro; passe
-- curto não muda nada, porque nem chega perto desse teto.
Config.GKBOT_THROW_ARC_TIME = 2.2

-- ⚠️ NOVO: PEDIDO — "faça o passe do goleiro pro personagem deslizar bem
-- menos... a dele desliza bem mais e acaba levando a bola pra longe do
-- jogador na hora do passe". Causa: throwBall (passe curto pro
-- companheiro mais perto, DIFERENTE do tiro de meta) sempre usava o MESMO
-- Config.GKBOT_THROW_ARC_TIME fixo (1.1s) não importa a distância — a
-- fórmula do arco (computeThrowVelocity) PRECISA de uma velocidade
-- vertical enorme pra "durar" 1.1s no ar mesmo num passe de poucos studs,
-- fazendo a bola subir bem alto e cair com força total em cima/perto do
-- companheiro (o impacto físico dela — CanCollide — empurra/desliza quem
-- está perto). Agora o arco de throwBall (só o passe, não o tiro de meta)
-- é PROPORCIONAL à distância: curto = arco baixo e suave, longo = sobe
-- até esse teto aqui em cima.
Config.GKBOT_THROW_ARC_TIME_MIN = 0.45
Config.GKBOT_THROW_SPEED_REFERENCE = 30 -- studs/segundo usados pra escalar o tempo de arco pela distância do passe

-- ⚠️ v16 (ver throwBall em GKBotController.lua): passe LONGO chega mais
-- suave que passe curto. A partir de GKBOT_THROW_LONG_REFERENCE_DISTANCE
-- studs, a velocidade de pouso alvo cai até GKBOT_THROW_LONG_SPEED_MULT da
-- normal — nunca a zero (a bola sempre continua andando um pouco, só não
-- passa voando pelo companheiro).
Config.GKBOT_THROW_LONG_REFERENCE_DISTANCE = 84 -- ⚠️ v112: campo 20% maior ("aumenta o campo em vinte por cento, ajuste tudo")
Config.GKBOT_THROW_LONG_SPEED_MULT = 0.55

-- ⚠️ v23: quique da bola no lançamento do goleiro (Elasticity). Passe curto
-- mantém o normal; quanto mais longo, mais amortecido, porque o arco alto
-- fazia a bola pular várias vezes ao cair. Volta ao original assim que
-- alguém dominar (setOwner -> _G.RestoreBallBounce).
Config.GKBOT_THROW_BOUNCE_NORMAL = 0.5
Config.GKBOT_THROW_BOUNCE_LONG = 0.04

-- ⚠️ v5.7: DOBRADO (era 18) — pedido esclarecido: "velocidade de
-- caminhada" era sobre o GKBOT, não o Role="GK" humano.
-- ⚠️ v110 — PEDIDO: "o bot está muito rápido, diminua a velocidade dele" (era 36;
-- o jogador corre a 38 — patrulha agora é bem mais calma que a corrida dele)
Config.GKBOT_WALK_SPEED = 26

-- ⚠️ NOVO: velocidade (studs/s) usada SÓ enquanto o bot está perseguindo
-- a bola/adversário de verdade numa tentativa de defesa/bote (ver
-- ChaseTarget em computeMoveTarget/updateBotMovement) — bem mais rápido
-- que a patrulha lateral normal, pra ele conseguir alcançar chutes que
-- antes eram rápidos/distantes demais.
-- ⚠️ AUMENTADO (era 32): "ainda está demorando pra pular e alcançar a
-- bola, aumente a velocidade dele pra alcançar bolas de um lado ao outro
-- mais fácil".
-- ⚠️ v6.1: AUMENTADO de novo (era 44) — junto com GKBOT_DIVE_DIAGONAL_KICK,
-- compensa a patrulha lateral mais parada (GKBOT_LATERAL_RANGE_FRACTION
-- reduzido) fazendo a perseguição/mergulho em si cobrir mais chão.
-- ⚠️ v6.2: AUMENTADO de novo (era 50) — junto com GKBOT_DIVE_REACH/
-- GKBOT_DIVE_DIAGONAL_KICK, pedido: "aumente mais um pouco a distância do
-- dive".
-- ⚠️ v6.3: AUMENTADO de novo (era 54) — pedido: "melhore um pouco mais o
-- dive do bot, pra dificultar pros players".
-- ⚠️ v110: "o bot está muito rápido" — era 66 (quase o DOBRO do jogador, 38)
Config.GKBOT_CHASE_SPEED = 44 -- ⚠️ v35: era 78 (original 58) -- ⚠️ v22: era 58 — com o alcance maior ele precisa CHEGAR lá dentro da duração do mergulho.

-- ⚠️ NOVO (pulo em vez de perseguir a bola): altura (studs) da bola
-- acima dos PÉS do bot a partir da qual ele pula pra tentar alcançar —
-- cruzamento/chute mais alto. O movimento normal do bot é só lateral
-- (ver computeMoveTarget em GKBotController.lua); isso é o que cobre a
-- diferença vertical em vez de "andar até embaixo da bola".
Config.GKBOT_JUMP_MIN_BALL_HEIGHT = 2

-- ⚠️ CORRIGIDO ("não sai da posição pra pular"): a 1ª versão tentava
-- forçar a velocidade HORIZONTAL do mergulho direto (AssemblyLinearVelocity),
-- mas o próprio Humanoid (ativo, não Physics) "briga" e cancela isso no
-- frame seguinte — só o componente VERTICAL (que a Humanoid não controla
-- do mesmo jeito) sobrevivia. Agora o componente horizontal vira uma
-- PERSEGUIÇÃO de verdade (ChaseTarget, andando pelo mesmo sistema
-- confiável de sempre — Humanoid:MoveTo + AssemblyLinearVelocity via
-- updateBotMovement — só que numa velocidade bem maior, GKBOT_CHASE_
-- SPEED, e sem o clamp lateral normal); só o pulo vertical continua
-- sendo um impulso direto (ver maybeJumpForBall em GKBotController.lua).
Config.GKBOT_DIVE_UP_SPEED = 48 -- ⚠️ v111: 32 -> 48 (+50%)      -- ⚠️ v6.3 AUMENTADO (era 23): "melhore um pouco mais o dive do bot, pra dificultar pros players"
-- ⚠️ v5.9: NOVO — pedido: "ele ainda não está dando o dive diagonal,
-- apenas o pulo". Componente HORIZONTAL somado ao impulso vertical do
-- mergulho aéreo (GKBOT_DIVE_UP_SPEED), na direção do alvo — sem isso o
-- pulo saía reto pra cima, o lado ficava só por conta da perseguição
-- (que demora 1 frame pra recalcular). studs/s.
-- ⚠️ v6.1: AUMENTADO (era 14) — pedido: "aumente um pouco o seu dive, pra
-- compensar" a patrulha lateral mais parada (GKBOT_LATERAL_RANGE_FRACTION
-- reduzido acima) — o mergulho cobre mais distância lateral pra compensar.
-- ⚠️ v6.2: AUMENTADO de novo (era 19) — pedido: "pode aumentar mais um
-- pouco a distância do dive".
-- ⚠️ v6.3: AUMENTADO de novo (era 22) — pedido: "melhore um pouco mais o
-- dive do bot, pra dificultar pros players".
Config.GKBOT_DIVE_DIAGONAL_KICK = 54 -- ⚠️ v111: 36 -> 54 (+50%) -- ⚠️ v105: +~50% (era 25) — o mergulho do bot vai mais longe
-- ⚠️ REDUZIDO pra 0.35 (era 0.5): "diminua um pouco o atraso do pulo".
-- ⚠️ v5.8: AUMENTADO um pouco de novo (windup maior, mesmo pedido do
-- GKBOT_SHOT_REACT_MAX_RANGE acima) — 0.35s às vezes acabava/resolvia
-- ANTES do bot terminar de chegar de verdade no ponto previsto, então a
-- captura/repelida rolava tarde demais, depois da bola já ter cruzado a
-- linha.
Config.GKBOT_DIVE_DURATION = 0.65 -- ⚠️ v110: 0.55 -> 0.65 (o voo agora dura de verdade, até 0.6s) · v109: era 0.45 — acompanha o mergulho de corpo (até 0.5s de voo)
-- ⚠️ v109 — velocidade do MERGULHO DE CORPO do bot (studs/s): o corpo voa deitado
-- até o ponto da bola, igual o mergulho do goleiro humano (antes ele só CORRIA)
-- ⚠️ v110: TEMPO DE REAÇÃO — o bot só mergulha depois que o chute já é ameaça há
-- esse tempo (antes reagia no mesmo quadro). Chute forte no canto chega antes.
Config.GKBOT_TEMPO_REACAO = 0.17 -- ⚠️ v111: era 0.22 — "tenta fazer ele acelerar um pouquinho mais... se mirar num canto e chutar, ele não pega de jeito nenhum. Tem que pegar pelo menos algumas vezes"
Config.GKBOT_DIVE_SPEED = 55 -- ⚠️ v111: 44 -> 55 ("pode deixar o mergulho um pouco mais rápido") · 38 -> 44 (mesmo pedido acima: chute no canto nunca era pego) -- ⚠️ v110: era 44 -- ⚠️ v110: era 52 ("o bot está muito rápido") -- ⚠️ v110: era 75 ("impossível de fazer gol, deixa ele um pouco mais fraco")
-- ⚠️ v109: reage a chute que vai passar até esse tanto dele SE estiver indo pro gol
-- dele (o raio pequeno de cima continua valendo pra bola que não vai no gol)
Config.GKBOT_SHOT_REACT_RADIUS_NO_GOL = 22.5 -- ⚠️ v111: 15 -> 22.5 (+50%) -- ⚠️ v110: era 20 ("muito difícil de errar") -- ⚠️ v110: era 28

-- ⚠️ v6.2: SUBSTITUI o antigo GKBOT_DIVE_MIN_LATERAL_DISTANCE (piso fixo,
-- sem teto nenhum) — pedido: "ele precisa calcular se o dive vale a pena
-- ou não, se a bola for passar dele com uma distância de pelo menos 1/3 do
-- tamanho do dive, ele dará o dive". Este valor (studs) representa o
-- ALCANCE de verdade do mergulho — usado em maybeJumpForBall
-- (GKBotController.lua) como referência dos DOIS limites: só vale a pena
-- mergulhar se a bola vai passar a pelo menos 1/3 disso de distância
-- (perto demais e ele já pega parado, sem precisar arriscar) E no máximo a
-- essa distância inteira (mais longe que isso, nem o mergulho alcança —
-- não adianta tentar).
-- ⚠️ v6.3: AUMENTADO (era 18) — pedido: "melhore um pouco mais o dive do
-- bot, pra dificultar pros players". Junto com GKBOT_DIVE_DIAGONAL_KICK/
-- GKBOT_DIVE_UP_SPEED/GKBOT_CHASE_SPEED acima e GKBOT_CATCH_CHANCE_AT_MAX,
-- o bot cobre mais chão E defende melhor quando chega no limite disso.
-- ⚠️ v110 — PEDIDO: "o GK ainda está muito difícil de errar... chuto no canto e é
-- muito difícil fazer gol". Alcance 37 -> 26: canto bem batido fica fora do mergulho.
-- ⚠️ v111 — PEDIDO: "aumente a distância dos dives do GK Bot, 50% maior — tanto pra cima, quanto pra diagonal, quanto pros lados"
Config.GKBOT_DIVE_REACH = 39 -- ⚠️ v111: 26 -> 39 (+50%: alcance do mergulho pros lados/diagonal) -- ⚠️ v105: +50% junto do humano (era 25) — ⚠️ v35: era 34 (original 21) -- ⚠️ v22: era 21 — "melhora o dive dele pra caralho". Alcance real do mergulho.

-- ⚠️ v3.3: PREVISÃO DE TRAJETÓRIA (pedido: "ele não dá dive pra diagonal
-- ... você já começa a calcular antes, igual o sistema de trajetória, ele
-- conseguirá ver a trajetória e ver o melhor caminho"). Mesma fórmula do
-- InstinctTrajectorySight.local.luau (posição + velocidade da bola,
-- gravidade — sem considerar curva/spin, só um auxílio) — mas rodando no
-- SERVIDOR, pra decidir com antecedência PRA ONDE a bola vai chegar
-- (perto do próprio bot), não só onde ela está agora, e mergulhar na
-- DIAGONAL certa em vez de só correr atrás da posição atual.
-- PREDICT_SAMPLES pontos no futuro, cada um PREDICT_STEP segundos mais à
-- frente do anterior (ver predictBallPosition/findClosestPredictedPoint
-- em GKBotController.lua).
-- ⚠️ v5.8: AUMENTADO (era 12) — mesmo pedido de "windup maior": enxerga
-- mais longe no futuro da trajetória (12 * 0.12s = 1.44s antes; agora
-- 16 * 0.12s = 1.92s), decidindo o mergulho/perseguição um pouco ANTES.
Config.GKBOT_TRAJECTORY_PREDICT_SAMPLES = 16
Config.GKBOT_TRAJECTORY_PREDICT_STEP = 0.12

-- ⚠️ NOVO ("bote" do GKBOT — igual o F/AttemptGKForward do goleiro
-- humano, ver GKInput.lua): quando um adversário com a bola ENTRA na
-- própria área (Part GKArea_<Time>), o bot pode dar um bote — um dash de
-- verdade PRA FRENTE (não só lateral) em direção ao adversário, tentando
-- roubar a bola. Só tenta se estiver perto o bastante dele (esse raio)
-- OU se a bola já estiver perto o bastante do bot (GKBOT_CATCH_APPROACH_
-- RADIUS) — ver updateBot em GKBotController.lua.
-- ⚠️ CORRIGIDO: o dash também virou perseguição de verdade (ChaseTarget,
-- mesma ideia do mergulho — ver GKBOT_DIVE_UP_SPEED acima), na mesma
-- GKBOT_CHASE_SPEED — por isso não tem mais uma velocidade separada aqui.
-- ⚠️ AUMENTADO (pedido: "pode fazer ele ir mais longe pra dar o dash dele
-- e pegar a bola, eu preciso quase encostar no goleiro pra isso
-- acontecer") — GKBOT_BOTE_RANGE era 10 (distância pra sequer TENTAR o
-- dash) e GKBOT_BOTE_STEAL_RANGE era 4 (distância, depois do dash, pra
-- sequer tentar o roubo — esse era o "quase encostar"). Os dois bem
-- maiores agora: ele tenta de mais longe E consegue roubar sem precisar
-- ficar colado no adversário.
-- ⚠️ v3.3: GKBOT_BOTE_RANGE virou um PISO, não mais o valor final —
-- pedido: "a distância pra ele dar o dash continua curta, pode dizer que
-- se a pessoa andar metade da area de distância ele já começa ir pra
-- cima". O alcance de verdade agora é o MAIOR entre esse piso e METADE da
-- PROFUNDIDADE real da Part GKArea_<Time> (linha do gol até o fundo da
-- área, medida na hora via OBB — ver areaDepth em GKBotController.lua) —
-- se você desenhar uma área grande no Studio, o bot passa a reagir mais
-- cedo sozinho, sem precisar mexer em número nenhum aqui; sem a Part de
-- área, cai no piso de sempre.
-- ⚠️ DUPLICADO (pedido: "o dash dele, duplique o range de distância pra
-- dar o bote, basta se aproximar menos que ele avança") — eram 16 e 0.5.
-- ⚠️ v5.7: REDUZIDO de novo (pedido: "deixe um pouco mais próximo do gol
-- pra ele começar a correr atrás do atacante") — 32 tava disparando cedo
-- demais.
Config.GKBOT_BOTE_RANGE = 22
Config.GKBOT_BOTE_RANGE_AREA_FRACTION = 0.75
-- ⚠️ v5.7: NÃO é mais um dash de duração fixa que solta o alvo depois de
-- GKBOT_BOTE_DASH_DURATION — virou PERSEGUIÇÃO CONTÍNUA (ver
-- pursueOpponent em GKBotController.legacy.luau): o bot persegue o
-- adversário frame a frame enquanto ele continuar dentro da zona, e só
-- desiste depois de GKBOT_RETURN_DELAY segundos SEGUIDOS com o alvo fora
-- dela. Esta constante fica só de referência histórica (não é mais lida).
Config.GKBOT_BOTE_DASH_DURATION = 0.35
Config.GKBOT_BOTE_STEAL_RANGE = 7   -- studs, distância MÁXIMA pra sequer tentar o roubo durante a perseguição

-- ⚠️ v5.7: segundos que o alvo (adversário perseguido, ou bola solta)
-- precisa ficar CONTINUAMENTE fora da zona de identificação antes do bot
-- desistir de perseguir e voltar pra posição normal — pedido: "ele só
-- volta depois de o atacante estiver por 1.5 segundos fora da área de
-- identificação pra parar de correr, aí ele vai direto no jogador [de
-- volta pra posição]".
Config.GKBOT_RETURN_DELAY = 1.5

-- ⚠️ v5.7: durante uma perseguição contínua, intervalo mínimo (segundos)
-- entre duas tentativas de roubo/captura — sem isso, rolaria a chance
-- TODO frame (60x/s), o que na prática vira quase 100% de acerto quase
-- instantâneo.
Config.GKBOT_STEAL_ATTEMPT_INTERVAL = 0.4

-- ⚠️ v5.7: PEDIDO — "faça o goleiro perseguir a bola, se estiver na mesma
-- área, se a bola estiver próxima desse espaço, ele vai tentar pegar a
-- bola sozinha também". Bola SEM DONO dentro da própria área a até esta
-- distância (studs) do bot: ele vai buscar sozinho (perseguição contínua,
-- igual pursueOpponent, mas sem adversário nenhum envolvido) — cobre o
-- caso de bola solta PARADA/lenta ali dentro, que o gatilho 2 (trajetória
-- de chute) abaixo não pega porque exige velocidade mínima.
Config.GKBOT_LOOSE_BALL_CHASE_RANGE = 20

-- ⚠️ v6.5: PEDIDO — "o GKBOT precisa seguir a bola, se ela entrar na area
-- pequena (45 studs) ele começa a ir em direção a bola individual para
-- pega-la também". Raio FIXO medido do próprio GOL até a bola (não do bot
-- até a bola, como GKBOT_LOOSE_BALL_CHASE_RANGE acima, nem da Part
-- GKArea_<Time>, que pode não existir/ter tamanho diferente na cena) —
-- funciona como uma "área pequena" independente, sempre disponível.
Config.GKBOT_SMALL_AREA_RADIUS = 67 -- ⚠️ v112: campo 20% maior ("aumenta o campo em vinte por cento, ajuste tudo") · 56 · ⚠️ v104: campo 25% maior (era 45)

-- ⚠️ v5.8: PEDIDO — "às vezes quando ele vai pegar a bola, ela buga,
-- talvez ele esteja pegando de novo depois de chutar de volta pros
-- jogadores". Era exatamente isso: logo depois de throwBall/
-- GKBotTakeGoalKick, a bola ainda está bem perto do bot (ele acabou de
-- soltá-la das "mãos") e SEM DONO — no próximo Heartbeat, o gatilho de
-- "bola solta dentro da própria área" (GKBOT_LOOSE_BALL_CHASE_RANGE)
-- disparava de novo, e o bot recapturava o próprio arremesso na hora.
-- ⚠️ v6.4: RENOMEADO de GKBOT_POST_THROW_LOCK_SECONDS — pedido: "o único
-- momento que a hitbox dele é desligada é quando ele passa a bola, e 0.5
-- segundos depois ela é religada de novo". Agora é literalmente isso: o
-- ÚNICO motivo que desliga a "hitbox" de captura do bot (ver
-- isHitboxDisabled/tryContactCatch em GKBotController.lua) — fora dessa
-- janela, contato com a bola = captura garantida, sem mais nenhuma outra
-- condição de bloqueio.
Config.GKBOT_HITBOX_DISABLE_AFTER_THROW = 0.5

-- Chance de roubo = a mesma curva por distância de sempre (GKBOT_CATCH_
-- CHANCE_AT_ZERO/AT_MAX) + um BÔNUS que cresce quanto mais DEVAGAR o
-- adversário estiver indo — pedido explícito: "aumenta a chance dele
-- pegar a bola, principalmente parado, se a velocidade é baixa a chance
-- é extremamente alta". Adversário parado (velocidade 0) = bônus cheio;
-- na velocidade de referência pra cima = bônus 0 (só a chance normal por
-- distância continua valendo).
Config.GKBOT_BOTE_SPEED_REFERENCE = 20 -- studs/s — acima disso, sem bônus nenhum
Config.GKBOT_BOTE_STATIONARY_BONUS = 0.5 -- chance extra (0 a 1) quando o adversário está totalmente parado

-- ⚠️ v5.8: PEDIDO — "mova ele uns 2-3 studs pra frente, pra realmente não
-- bugar o gol". A posição normal de patrulha (computeMoveTarget) ficava
-- exatamente em cima da anchor (linha do gol/Spawn_<Time>_GK) — bola
-- rolando/chutada rasteira podia cruzar a linha de gol (contando ponto no
-- MatchController) no MESMO instante em que o bot ainda estava chegando
-- pra pegar/defender. Empurra a posição de patrulha (e só ela — dive/bote
-- continuam mirando o alvo de verdade) pra DENTRO do campo por este tanto,
-- na direção fieldForward — dá uma folga real antes da linha.
Config.GKBOT_FORWARD_OFFSET = 2.5

-- ⚠️ NOVO: quanto (studs) o bot pode passar da PONTA DA TRAVE pro lado —
-- 0 = nunca passa da ponta da trave. O clamp lateral do movimento usa o
-- MENOR entre isso e a Part GKArea_<Time> (que normalmente é mais larga
-- que o gol, cobrindo a grande área inteira) — ver computeMoveTarget em
-- GKBotController.lua.
Config.GKBOT_LATERAL_POST_MARGIN = 0

-- ⚠️ v5.9: PEDIDO — "faça o jogador andar menos pra direita/esquerda,
-- isso é só pra ele se posicionar um pouco melhor, não ir da ponta a
-- outra do gol". Amortece (< 1) o quanto o bot acompanha a posição
-- lateral da bola na patrulha normal (computeMoveTarget) — 1.0 = segue a
-- bola de trave a trave (comportamento antigo); menor = ajustes mais
-- discretos, sem sair correndo de um lado a outro.
-- ⚠️ v6.1: REDUZIDO de novo (era 0.5) — "diminua mais o diâmetro do
-- movimento de direita e esquerda do GK". O mergulho (dive) foi reforçado
-- junto (ver GKBOT_DIVE_DIAGONAL_KICK/GKBOT_CHASE_SPEED abaixo) pra
-- compensar a patrulha mais parada — ele se posiciona menos, mas quando
-- precisa ir buscar de verdade (mergulho), vai mais longe/rápido.
-- ⚠️ v6.2: SUBSTITUÍDO por um par MIN/MAX — pedido: "permita que o gk
-- acompanhe mais a bola, quão mais perto estiver, maior o diâmetro de
-- movimento dele". Em vez de um número fixo, o quanto o bot acompanha a
-- bola lateralmente agora interpola entre esses dois valores (ver
-- lateralFollowFraction em GKBotController.lua): MIN quando a bola está
-- longe (fora do alcance de referência, comportamento contido de sempre),
-- subindo até MAX quando a bola está bem perto/dentro da própria área
-- (acompanha quase 1:1, bem mais reativo perto do gol).
-- ⚠️ v15: MIN era 0.3 — PEDIDO: "às vezes ele não vai direito na bola, se
-- ela tiver um pouco pro lado ele vai muito devagarinho". Com 0.3, uma bola
-- deslocada 20 studs pro lado fazia o bot andar só 6, e ainda por cima isso
-- era multiplicado pelo fator diagonal (piso 0.45) — no pior caso ele
-- cobria 13% do deslocamento da bola e parecia estar ignorando ela. 0.6
-- deixa ele se alinhar de verdade mesmo com a bola longe.
-- Isso NÃO faz ele se expor: quem impede o "foi demais pro lado e levou no
-- outro canto" continua sendo o clamp da trave (maxLateral, nunca passa da
-- ponta do gol) mais o GKBOT_DIAGONAL_CENTER_MIN_FACTOR abaixo, que segura
-- ele perto do centro justamente nos ângulos abertos.
-- ⚠️ v16: os dois valores agora significam o CONTRÁRIO do que significavam
-- (ver lateralFollowFraction em GKBotController.lua, que teve a curva
-- invertida): MIN é o quanto ele acompanha com a bola PERTO (fica centrado,
-- cobrindo os dois cantos) e MAX é com a bola LONGE (pode deslizar mais,
-- porque o ângulo é fechado e dá tempo de corrigir).
Config.GKBOT_LATERAL_RANGE_FRACTION_MIN = 0.25 -- bola perto: quase centrado
Config.GKBOT_LATERAL_RANGE_FRACTION_MAX = 0.65 -- bola longe: acompanha mais

-- ⚠️ v16: PEDIDO — "o mais longe que ele pode se mover é um pouco menos, não
-- na trave exatamente". Teto do deslize lateral como fração da meia-largura
-- do gol: 1.0 deixaria ele encostar na trave, que é o que escancarava o
-- canto oposto. 0.65 significa que ele nunca passa de ~2/3 do caminho até a
-- trave, então sempre sobra corpo pro outro lado.
Config.GKBOT_LATERAL_GOAL_FRACTION = 0.65

-- ⚠️ v21 (ver attemptCatch em GKBotController.lua): meia-caixa, em studs, em
-- volta do corpo do bot. Bola solta dentro dela = defesa GARANTIDA, sem
-- checar ângulo nem sortear nada — "a bola passou dentro dele, ele pegou".
-- NÃO vale contra chute de Hissatsu: esse continua sendo disputado (é onde
-- entra a Hissatsu de goleiro ou o Físico alto). Aumentar isso deixa o bot
-- mais difícil de vencer com chute normal.
-- ⚠️ v67: caixa de captura garantida do bot um pouco maior junto (mesmo
-- pedido). Continua valendo só pra bola SEM Hissatsu vindo — chute de
-- Hissatsu segue tendo que ser disputado de verdade.
-- v110 — PEDIDO: "ele pega a bola sem sequer estar nela (chute no travessão, sem
-- pular). A hitbox do GK é o GK — uma bola em volta dele, só". A caixa garantida
-- e o alcance de 8.5 viraram uma ESFERA em volta do corpo (+ um pouco pras mãos).
Config.GKBOT_CORPO_RAIO = 4
Config.GKBOT_MAOS_EXTRA = 1.3
-- altura máxima que o mergulho do bot sobe acima do chão (perto do travessão)
Config.GKBOT_DIVE_ALTURA_MAX = 19.5 -- ⚠️ v111: 13 -> 19.5 (+50% pra cima)
-- ⚠️ v111 — PEDIDO: "ele vai sempre tentar priorizar mais dar dives; só se a bola
-- for realmente bem próximo dele ele não dá dive e anda normalmente até a bola".
-- Bola passando a menos disso de lado = anda até ela; mais que isso = mergulha
-- (antes o mínimo era a caixa de defesa garantida, 5.5).
Config.GKBOT_DIVE_PERTO = 3.5
Config.GKBOT_GUARANTEED_CATCH_BOX = Vector3.new(5.5, 7, 5.5) -- ⚠️ v110: de volta (v109 tinha subido pra 6.5, 7.5, 6.5) ("a bola passa direto nele") -- era 4, 5.5, 4

-- Alcance de referência (studs) usado pra essa interpolação: a PROFUNDIDADE
-- real da Part GKArea_<Time> (igual areaDepth em GKBotController.lua),
-- multiplicada por este fator — se adapta a qualquer tamanho de área
-- desenhado no Studio. GKBOT_LATERAL_FOLLOW_RANGE_FALLBACK só é usado se
-- essa Part não existir na cena.
Config.GKBOT_LATERAL_FOLLOW_RANGE_MULT = 1.5
Config.GKBOT_LATERAL_FOLLOW_RANGE_FALLBACK = 36 -- ⚠️ v112: 30 -> 36 (campo 20% maior)

-- ⚠️ v6.3: PEDIDO — "faça o bot ficar mais no centro se o atacante estiver
-- aos lados direita ou diagonal do gol... deixa uma brecha". Piso do fator
-- de "ângulo diagonal" (ver diagonalCenteringFactor em GKBotController.lua)
-- — 1.0 desligaria a contenção (segue a bola até a ponta mesmo num ângulo
-- bem aberto, comportamento antigo); mais baixo = fica mais perto do
-- centro quanto mais aberto/diagonal for o ângulo da bola, nunca menos que
-- este piso (pra ele nunca ficar 100% travado no meio do gol).
Config.GKBOT_DIAGONAL_CENTER_MIN_FACTOR = 0.45

-- ⚠️ NOVO (corrige o "gol fantasma"): quando não existe a Part
-- Spawn_<Time>_GK, o bot usava a CFrame do PRÓPRIO gol como referência —
-- ou seja, podia ficar literalmente em cima da hitbox de gol
-- (goalPart.Touched conta na hora que a bola encosta, ver
-- MatchController.lua). Esse offset empurra a posição de referência pra
-- FRENTE (rumo ao campo) antes de usar, nesse caso.
Config.GKBOT_SAFE_GOAL_OFFSET = 4

-- ⚠️ NOVO (tiro de meta cobrado pelo GKBOT — ver _G.GKBotTakeGoalKick em
-- GKBotController.lua): o alcance real usado é sempre METADE da distância
-- real entre os 2 gols (calculada na hora, campo por campo) — esse valor
-- aqui é só um FALLBACK (studs) pro raríssimo caso de faltar 1 dos 2 gols
-- na cena nesse instante.
Config.GKBOT_GOAL_KICK_MAX_RANGE_FALLBACK = 72 -- ⚠️ v112: 60 -> 72 (campo 20% maior)

-- ⚠️ NOVO (pedir passe, tecla T): quanto tempo (segundos) o pedido de
-- passe de um jogador fica "ativo" (Attribute WantsPass + destaque
-- visual) depois de apertar T, antes de sumir sozinho — ver
-- PassRequestController.lua.
Config.GKBOT_PASS_REQUEST_DURATION = 4

-- ⚠️ NOVO (Pulso do Passe Perfeito): distância (studs) do "ponto de
-- pouso" projetado à frente do jogador (na direção que ele está de
-- frente) usada pra escolher o companheiro mais PRÓXIMO desse ponto —
-- ver _G.PulseComputeLandingTeammate em BallController.lua.
Config.PULSE_PERFECT_PASS_RANGE = 30

-- ⚠️ NOVO (Pulso do Passe Perfeito — Effect.AerialArc): tempo de voo
-- MÍNIMO (segundos) da parábola do passe aéreo — garante que o arco
-- sempre fique visível (bola subindo por cima de defensores) mesmo pra um
-- alvo bem perto, onde a distância sozinha resultaria num tempo de voo
-- curto demais pra qualquer curva aparecer. Ver pulsePerformKick em
-- BallController.lua.
Config.PULSE_AERIAL_ARC_MIN_TIME = 0.9

-- ⚠️ NOVO (Instinto de Leitura de Jogo — visão de trajetória passiva):
-- velocidade mínima (studs/s) que a bola precisa ter pra trilha de pontos
-- de previsão aparecer (chute forte/cruzamento/lançamento) — bola parada
-- ou rolando devagar (ex: sendo driblada) não mostra nada.
Config.TRAJECTORY_SIGHT_MIN_SPEED = 15

Config.SET_PIECE_TIME_LIMIT = 10
Config.OUT_OF_BOUNDS_REENTRY_MARGIN = 1

-- Quanto (em studs) a bola precisa avançar PRA DENTRO do gol, depois do
-- primeiro toque na hitbox, pra confirmar o gol de verdade — evita gol
-- "fantasma" contado cedo demais (lag) antes da bola cruzar a linha do
-- gol de fato, dando um respiro real pro goleiro conseguir a defesa.
Config.GOAL_LINE_BACK_OFFSET = 3
-- Se a bola voltar mais que isso (studs) em direção ao meio de campo
-- antes de confirmar o gol acima, considera que o goleiro afastou/pegou
-- e cancela a tentativa em vez de ficar esperando pra sempre.
Config.GOAL_LINE_REJECT_MARGIN = 1.5
-- Tempo máximo (segundos) esperando a confirmação acima antes de
-- desistir da tentativa (segurança contra bola presa/parada na rede).
-- PEDIDO: com a área do gol/bola fora ficando mais exata (parts físicas
-- em vez de matemática de eixo), não precisa mais de tanta margem de
-- segurança — reduzido pra metade (era 1.5).
Config.GOAL_LINE_CONFIRM_TIMEOUT = 0.75

Config.THROW_IN_INSET = 1.5
-- ⚠️ v5.4 FIX: 2 studs é praticamente EM CIMA do canto de verdade (onde a
-- lateral encontra o fundo) — qualquer chute levemente errado já manda a
-- bola pra fora dos dois lados de uma vez, direto da própria cobrança
-- (reportado: "saiu pra fora direto do escanteio"). Subiu pra 5: mais
-- espaço pro cobrador entre as duas linhas, sem descaracterizar que é
-- "do canto".
Config.CORNER_ARC_INSET = 5
Config.GOAL_KICK_INSET = 6

-- ⚠️ NOVO: margem EXTRA (studs), só pro tiro de meta, somada em cima de
-- GOAL_KICK_INSET — sem isso, o ponto de cobrança podia ficar perto/
-- sobrepondo a hitbox do próprio gol, e o simples TELEPORTE da bola pra
-- lá (ball.Position = worldSpot) já contava como toque no gol
-- (goalPart.Touched dispara em overlap por teleporte, não só por física
-- de verdade — mesma família do bug do "gol fantasma" já corrigido em
-- outro lugar) — o goleiro (humano OU GKBOT, ver GKBotController.lua)
-- cobrava contra o próprio time do nada. Empurra o ponto mais pra dentro
-- do campo, bem longe da hitbox.
Config.GOAL_KICK_SAFE_OFFSET = 6

Config.SET_PIECE_BALL_HEIGHT = 2

-- ===== CHUTE (também serve de PASSE — mire num companheiro em vez do
-- gol — e de VOLEIO, se a bola estiver no ar e você não tiver posse) =====
Config.KICK_MIN_FORCE = 48 -- v110: era 28 ("a força mínima é inútil, a bola cai no pé — o toquinho tem que ir um pouco à frente do personagem") · ⚠️ v104: -10% (era 30), depois +5% ("com chute em 60 está fraco demais")
-- ⚠️ v67 — PEDIDO: "a força do chute está muito fraca; aumenta a força do
-- chute base em 25%". 145 -> 181.
-- ⚠️ v104 — PEDIDO: "aumente o tamanho do campo pra 25% maior, e diminua 10%
-- de força de chute base". 181 -> 163.
-- Depois: "aumenta a força base do chute em 5%" — 163 -> 171.
Config.KICK_MAX_FORCE = 171
Config.KICK_CHARGE_RATE = 155     -- era 140 — carrega um pouquinho mais rápido
Config.KICK_STAMINA_COST = 10
Config.KICK_UPWARD_BOOST = 0.18
Config.CURVE_STRENGTH = 45
Config.CURVE_DURATION = 0.7
Config.BALL_TRAIL_MIN_FORCE = 65

-- Enquanto o jogador segura o botão pra carregar o chute (FootballClient
-- avisa o servidor via Remotes.UpdateKickCharging, igual o sprint já faz
-- com UpdateSprinting), o WalkSpeed é multiplicado por isso — dá pra
-- ainda se mexer (ajustar o ângulo do chute), mais devagar que o normal,
-- como um "pé de apoio plantado" carregando força, mas sem travar tanto.
Config.KICK_CHARGE_WALK_SPEED_MULT = 0.68  -- era 0.55 — um pouco mais rápido enquanto chuta

-- Mantido como referência de força "fraca" pra usos automáticos (ex:
-- lançamento forçado de lateral no OutOfBoundsController), já que o
-- botão de passe dedicado não existe mais.
Config.PASS_FORCE = 55

-- ===== VOLEIO (chute sem posse prévia, bola no ar) =====
Config.VOLLEY_MIN_BALL_HEIGHT = 3   -- igual à cabeçada: altura mínima da bola acima do chão
Config.VOLLEY_RANGE = 6             -- alcance pra alcançar a bola no ar
Config.VOLLEY_FORCE_MULTIPLIER = 1.25 -- voleio bem cronometrado sai mais forte que um chute normal

-- ===== CABEÇADA =====
Config.HEADER_STAMINA_COST = 15
-- ⚠️ v5.3 — CABEÇADA REBALANCEADA (tecla G). Ela era quase impossível de
-- acertar por três motivos somados, todos corrigidos:
--   1. O alcance era medido em distância 3D (bola alta gastava o alcance
--      na altura). Agora HEADER_RANGE é só a margem HORIZONTAL, e a
--      altura tem faixa própria — ver AttemptHeader em BallController.
--   2. A bola precisava estar 3 studs acima do TORSO (uns 5-6 do chão)
--      pra valer: mínimo baixou pra 1, e ganhou um teto (MAX) generoso,
--      pra dar pra cabecear também a bola de um drible aéreo.
--   3. Errar custava 3 SEGUNDOS de espera. Agora é 1.2s, e o cabeceio é
--      a resposta principal a quem sobe com a bola — precisa poder
--      tentar de novo.
Config.HEADER_COOLDOWN = 1.2      -- era 3.0
Config.HEADER_RANGE = 11          -- era 6 — agora é HORIZONTAL só
Config.HEADER_MIN_BALL_HEIGHT = 1 -- era 3 (medido a partir do torso)
Config.HEADER_MAX_BALL_HEIGHT = 15 -- ⚠️ NOVO: teto da faixa cabeceável
-- ⚠️ v105 — PEDIDO: "a cabeçada tá muito fraca... coloque a força dela pra ir
-- mais longe". 65 -> 115, e sobe mais (HEADER_ELEVACAO) pra ganhar distância.
Config.HEADER_FORCE = 115
Config.HEADER_ELEVACAO = 16 -- velocidade pra cima somada à cabeçada (era 8 fixo)
-- ⚠️ v105: voleio "de reação" (toque rápido no ar com a bola abaixo da
-- cabeça, sem ter carregado o chute) — fraco de propósito.
Config.VOLLEY_FRACO_FORCA = 55
-- ⚠️ v108 — PRIMEIRO TOQUE. PEDIDO: "nem precisa dominar, ele pode chutar direto,
-- antes mesmo do domínio. Se a bola estiver fraca na frente dele, ele usa o chute
-- ou a cabeçada. Mas se a bola estiver forte, já não dá pra pegar." Velocidade
-- máxima (studs/s) da bola solta pra dar pra chutar/cabecear de primeira. A
-- cabeçada aceita um pouco mais (cruzamento chega mais rápido que um passe).
Config.PRIMEIRO_TOQUE_VEL_MAX = 80
Config.HEADER_VEL_MAX = 95

-- ===== GRAVIDADE E JOGABILIDADE DA BOLA =====
-- Workspace.Gravity é GLOBAL (afeta jogador também) — pra bola "pesar"
-- diferente do jogador sem mudar o pulo/queda de ninguém, aplicamos uma
-- VectorForce só nela que CANCELA uma fração da gravidade (ver setup no
-- BallController.lua). BALL_GRAVITY_MULTIPLIER = 1 seria gravidade
-- normal (igual o jogador); < 1 deixa a bola "mais leve" (cai mais
-- devagar — cruzamentos/lançamentos/cabeçadas ficam com mais hang-time,
-- efeito de curva tem mais tempo pra atuar). Pra mudar a sensação da
-- bola, mexa SÓ nesse número.
-- ⚠️ v67 — PEDIDO: "você tá mirando num local e ele desce demais; a
-- gravidade não vai puxar ele tanto pra baixo, e ele vai conseguir ir mais
-- longe". Este é o quanto da gravidade REAL a bola sente (1 = gravidade
-- cheia, 0 = nenhuma). 0.82 -> 0.68: a bola cai ~17% menos, então o mesmo
-- chute cobre mais chão e chega mais perto de onde a mira apontou.
Config.BALL_GRAVITY_MULTIPLIER = 0.68

-- ⚠️ v67 — RESGATE DA BOLA FUGITIVA.
-- PEDIDO: "se a bola sair exorbitantemente pra longe, uns 2000 studs, ela
-- volta pro centro do mapa. Mesmo que fosse diretamente pra cima, volta pro
-- centro, pros caras pararem de abusar de bug."
-- A distância é medida em 3D a partir do centro do campo, então altura conta
-- junto — bola chutada reto pra cima também volta.
Config.BALL_RESCUE_DISTANCE = 2000
Config.BALL_RESCUE_SPAWN_HEIGHT = 5 -- studs acima do centro, pra ela cair no gramado

-- ⚠️ v84 — PEDIDO: "a bola cai no void e é destruída, faça uma forma de
-- impedir". CAUSA (medida no Studio): o gramado fica em Y≈-193 e o Roblox
-- DESTRÓI qualquer peça abaixo de workspace.FallenPartsDestroyHeight (-500)
-- — só ~307 studs de queda. O resgate acima só olhava 2000 studs de
-- distância, então uma bola que atravessava o chão era destruída MUITO antes
-- de chegar lá, e com ela ia embora a referência que o jogo inteiro usa.
-- Agora a bola é resgatada assim que fica BALL_VOID_RESCUE_DEPTH studs
-- abaixo da superfície do campo (medida por raycast no boot, não chutada).
Config.BALL_VOID_RESCUE_DEPTH = 25

-- ⚠️ v67 — BARREIRA INVISÍVEL EM VOLTA DO CAMPO (ver FieldBarrier.legacy.luau).
-- PEDIDO: "coloque uma barreira invisível para impedir que o jogador passe
-- pelas linhas que demarcam a área fora do campo."
-- Ela bloqueia só o JOGADOR: a bola atravessa normalmente, senão lateral,
-- escanteio e tiro de meta parariam de existir.
Config.FIELD_BARRIER_MARGIN = 6      -- studs além da borda do campo (folga pra pisar na linha)
Config.FIELD_BARRIER_HEIGHT = 60     -- alta o bastante pra ninguém pular por cima
Config.FIELD_BARRIER_THICKNESS = 4   -- grossa o bastante pra ninguém atravessar em velocidade

-- ⚠️ v67 — NÉVOA (zona de invisibilidade, ver spawnFogZone em PulseController).
-- PEDIDO: "faz um cilindro, um círculo maior em volta, e deixa o cara
-- transparente ali dentro. A bola também some junto."
Config.FOG_ZONE_HEIGHT = 26          -- altura do cilindro (alto o bastante pra cobrir um pulo)
Config.FOG_ZONE_TRANSPARENCY = 0.72  -- a névoa em si: visível, mas dá pra jogar por dentro
Config.FOG_ZONE_COLOR = Color3.fromRGB(198, 210, 225)
-- Quão apagado o jogador (e a bola) ficam dentro dela. 1 = invisível de vez;
-- 0.85 deixa um vulto, que é mais justo pro adversário do que sumir por
-- completo — dá pra adivinhar, não dá pra marcar.
Config.FOG_HIDDEN_TRANSPARENCY = 0.85

-- ⚠️ v67 — CARGA DO FLOW (antigo Instinct Mode).
-- PEDIDO: "o Flow só vai ser carregado por PASSES na bola — passes
-- bem-sucedidos. Receber passes vale sim. Domínio de outra pessoa que passa a
-- ser seu (dar carrinho e tirar o domínio de alguém, ou interceptação) vale.
-- Gols ganham mais."
--
-- A regra de fundo é uma só: a bola tem que TROCAR DE MÃOS. Conduzir sozinho
-- não constrói Flow — foi por isso que a carga por "praticar a ação da sua
-- Arma" (chutar, driblar, cabecear, mergulhar) foi desligada.
--
-- O medidor vai a 100. Com estes números: ~9 passes dados, ~7 recebidos,
-- 5 desarmes, ou 2 gols. A mistura é o caminho normal.
Config.FLOW_CHARGE_PASS_GIVEN = 11
Config.FLOW_CHARGE_PASS_RECEIVED = 14
Config.FLOW_CHARGE_STEAL = 20
Config.FLOW_CHARGE_GOAL = 50

-- Propriedades físicas da bola (Density/Friction/Elasticity) — sem isso
-- a bola usa o padrão genérico do Roblox (que não foi pensado pra
-- futebol). FrictionWeight/ElasticityWeight altos fazem ESSES valores
-- dominarem sobre o material do chão (Roblox tira uma média ponderada
-- entre as duas peças que se tocam) — sem isso, o material do campo
-- pode "diluir" o efeito.
-- ⚙️ Ajustado (pedido: quicar mais, deslizar menos): Elasticity e
-- Friction subiram, com o Weight de cada um também mais alto pra valer
-- de verdade contra o material do chão.
-- ⚠️ v34: AUMENTADO de novo (Friction/FrictionWeight) — pedido: "faça a
-- bola deslizar BEM MENOS quando cair no chão". Isso pega o instante do
-- IMPACTO (a física de verdade do Roblox, antes do nosso amortecimento
-- de rolagem em RunService.Heartbeat abaixo sequer rodar de novo) — sem
-- "grude" suficiente aqui, a bola já sai escorregando forte do próprio
-- quique, e o amortecimento de rolagem só entra depois pra ir freando aos
-- poucos.
-- ⚠️ v37: AUMENTADO de novo (Friction/FrictionWeight) — pedido: "diminua
-- MAIS AINDA o deslizamento da bola".
-- ⚠️ v84 — PEDIDO: "diminua o deslize dela". Friction 1.15 -> 1.5 e
-- FrictionWeight 3.2 -> 4.2 (o atrito da bola manda ainda mais sobre o do
-- gramado no instante do quique), junto com a frenagem de rolagem mais
-- abaixo.
Config.BALL_PHYSICAL_PROPERTIES = {
	Density = 0.7,
	Friction = 1.5,           -- era 1.15/0.95/0.85/0.7/0.55/0.35 — mais "grude" no chão, desliza menos
	Elasticity = 0.65,        -- era 0.6/0.4 — quica mais
	FrictionWeight = 4.2,     -- era 3.2/2.6/2.2/1.8/1.4/1 — domina de vez sobre o material do chão
	ElasticityWeight = 1.6,   -- era 1.4/1
}

-- ===== ⚠️ v20: SAÍDA LIMPA DO CHUTE ("a bola bate no corpo e para") =====
-- Depois de MUITAS tentativas de descobrir O QUE exatamente colide com o
-- corpo (grupos de colisão, mecânica de corpo, quique no chão — nenhuma
-- explicou tudo), a abordagem mudou: em vez de continuar caçando a causa,
-- a bola simplesmente NÃO PODE colidir com nada durante a saída do
-- chute, até ter se afastado do corpo de quem chutou. Enquanto essa
-- "saída" dura, a bola fica com CanCollide = false — ou seja, atravessa
-- QUALQUER coisa que esteja colada no personagem, seja lá o que for
-- (hitbox invisível, acessório, emenda de Part, o que o valha), sem
-- precisar identificar o culpado.
--
-- É uma janela curtíssima e ela acaba assim que QUALQUER uma acontecer:
--   • a bola passou de KICK_CLEAR_DISTANCE studs do corpo do chutador
--     (é o caso normal — num chute de 40-90 studs/s isso leva ~0.1s);
--   • passou KICK_CLEAR_MAX_SECONDS (teto de segurança);
--   • a bola caiu mais de KICK_CLEAR_MAX_DROP studs abaixo de onde
--     estava quando saiu do pé (impede ela de afundar no chão se o chute
--     for muito fraco/rasteiro — nesse caso a colisão volta na hora).
-- Fora dessa janela, a física da bola é EXATAMENTE a de sempre.
Config.KICK_CLEAR_DISTANCE = 5      -- studs de folga do corpo do chutador pra colisão voltar a valer
Config.KICK_CLEAR_MAX_SECONDS = 0.35 -- teto de segurança da janela (nunca fica sem colisão além disso)
Config.KICK_CLEAR_MAX_DROP = 1       -- se a bola cair mais que isso durante a janela, a colisão volta na hora (não afunda no chão)

-- v21 — PEDIDO: "faz a bola sair de um ponto na frente do corpo, pode ser
-- assim". Complementa o KICK_CLEAR_* acima: além de não colidir durante a
-- saída, a bola já "nasce" deslocada pra frente (só no plano horizontal,
-- a altura Y não muda — não afeta cabeçada/lob), na direção do chute, uns
-- studs à frente do corpo de quem chutou. Assim ela começa a viagem já
-- fora do raio de mecânica de corpo, em vez de depender só da colisão
-- desligada por um instante.
Config.KICK_LAUNCH_FORWARD_OFFSET = 2.5 -- studs à frente do chutador, na direção do chute

-- Amortecimento do GIRO (spin) da bola quando ela está no chão sem dono
-- — sem isso, uma esfera pode manter/ganhar rotação por atrito com o
-- chão de um jeito que parece "acelerar sozinha" mesmo andando devagar
-- (o giro realimenta o deslizamento). Fração do AssemblyAngularVelocity
-- que sobra a cada segundo (0.85 = perde 15%/s).
Config.BALL_ANGULAR_DAMPING_PER_SECOND = 0.10 -- ⚠️ v37 (era 0.20/0.35/0.55/0.82) — pedido: "diminua MAIS AINDA o deslizamento" — perde giro ainda mais rápido

-- Fricção de ROLAGEM extra: sem dono, encostada no chão, a bola perde
-- velocidade HORIZONTAL por segundo — sem isso, uma bola rolando
-- praticamente não desacelera sozinha (o Friction do PhysicalProperties
-- sozinho não segura bem numa esfera) e desliza/"acelera" (mantém
-- velocidade alta) por longe demais. Dois níveis: abaixo de
-- BALL_ROLLING_MAX_SPEED usa a decel normal (rolagem natural); ACIMA
-- desse valor (chute forte ainda correndo no chão) usa a decel "rápida",
-- mais forte, pra ela assentar numa velocidade de rolagem razoável mais
-- rápido em vez de continuar deslizando na mesma velocidade alta.
-- ⚠️ v34/v37: AUMENTADO de novo (os três) — pedido: "diminua MAIS AINDA o
-- deslizamento da bola".
-- ⚠️ v84: +40% nos dois (pedido "diminua o deslize").
-- ⚠️ v97: +20% nos dois (pedido "às vezes ela desliza demais"). Parte do
-- "deslizar" também vinha do giro solto virando movimento no chão — isso foi
-- resolvido na raiz (giro sempre coerente, ver BallController v97), então o
-- aumento aqui é moderado.
Config.BALL_ROLLING_DECELERATION = 50         -- era 42/30/20/13/8/3.2/1.6 — studs/s², abaixo de BALL_ROLLING_MAX_SPEED (ainda deslizando muito? sobe esse número de novo)
Config.BALL_ROLLING_FAST_DECELERATION = 84    -- era 70/50/36/24/16/6.5 — studs/s², ACIMA de BALL_ROLLING_MAX_SPEED
Config.BALL_ROLLING_MAX_SPEED = 8             -- era 10/14/18 — abaixa o limiar, entra na frenagem "rápida" mais cedo
-- ⚠️ v103 — PEDIDO: "diminui mais ainda o deslize... se eu jogar muito longe a
-- bola, ela desliza mais do que deveria". Frenagem EXTRA proporcional à
-- velocidade (1/s): bola que cai de um lançamento longo chega rápida e agora
-- freia muito mais; o rolinho devagar quase não muda. Medida de cabeça: caindo
-- a 80 studs/s ela desliza ~24 studs (antes ~38). Mais = desliza menos.
Config.BALL_ROLLING_ARRASTO = 1.0

-- ⚠️ v103 — PEDIDO: "Não é pra existir desvio aleatório em nenhum chute."
-- false = nenhum chute/passe/Hissatsu desvia da mira (ver applyAimDeviation).
Config.DESVIO_ALEATORIO_LIGADO = false

-- ===== DESVIO DE MIRA (aim deviation) =====
-- Todo chute (KickBall e cabeçada) sofre um desvio ALEATÓRIO na direção
-- final — maior quanto PIOR o Kick do jogador, e maior ainda se tem um
-- adversário em cima na hora do chute (pressão). Instintos/Pulsos com
-- AimDeviationMult (0 = mira perfeita, 1 = desvio normal, entre 0 e 1 =
-- reduz) multiplicam o resultado final — ver getAimDeviationDegrees no
-- BallController.lua.
-- ⚠️ v84 — PEDIDO: "faça os chutes saírem sem nenhum tipo de erro... quando
-- você chuta numa direção, parece que ela não vai exatamente no ponto onde
-- você mirou, às vezes vai pra um lado, às vezes pro outro". ZERADO: era
-- 10/1.5/6 graus de desvio ALEATÓRIO (até 16° sob pressão — a 60 studs isso
-- é ~17 studs pro lado). Com tudo em 0, getAimDeviationDegrees devolve 0 e
-- chute, cabeçada e Hissatsu saem exatamente na direção mirada.
-- Efeito colateral a saber: os AimDeviationMult de Armas/Hissatsus
-- ("mira mais precisa") deixam de ter o que reduzir.
Config.AIM_DEVIATION_MAX_DEGREES = 0    -- era 10
Config.AIM_DEVIATION_MIN_DEGREES = 0    -- era 1.5
Config.AIM_DEVIATION_PRESSURE_RADIUS = 5   -- studs: adversário mais perto que isso = "sob pressão"
Config.AIM_DEVIATION_PRESSURE_DEGREES = 0  -- era 6

-- ===== GOLEIRO: DEFESA POR BOTÃO (dive) =====
-- Z/X/C/E/Q substituem a finta (drible) quando o Role do jogador é "GK"
-- — cada tecla é uma DIREÇÃO de mergulho (ver GKInput.local.luau):
-- Z=Esquerda, C=Direita, X=Cima, E=Diagonal-Cima-Direita, Q=Diagonal-
-- Cima-Esquerda. O goleiro se desloca por CFrame na direção (igual à
-- finta/carrinho) e, se a bola estiver vindo em direção ao PRÓPRIO gol e
-- passar perto o bastante durante a janela do mergulho, é defesa
-- (captura — vira posse do goleiro).
-- PEDIDO: mergulhos pro LADO e na DIAGONAL vão mais longe (mais alcance
-- pra defender chutes de canto); o de ALTURA (Up, tecla X) fica com a
-- distância de sempre — não faz sentido esse "voar" mais longe pros
-- lados, é só pra cima mesmo.
-- ⚠️ v36: AUMENTADO de novo (os três) — pedido: "melhore o GK normal sem
-- ser o bot, aumente a distância do dive".
Config.GK_DIVE_DISTANCE = 19          -- era 15/10 — studs percorridos no mergulho de ALTURA (Up)
Config.GK_DIVE_DISTANCE_SIDE = 48     -- ⚠️ v105: +50% ("ele precisa ir mais longe com o dive") — era 32 (v103), 26/21/14 antes
Config.GK_DIVE_DISTANCE_DIAGONAL = 29 -- ⚠️ v103: idem (era 24/19.5/13) — studs percorridos no mergulho na DIAGONAL (UpLeft/UpRight)
Config.GK_DIVE_DURATION = 0.35        -- segundos que o mergulho dura (também a janela de captura)
-- FIX: antes a captura comparava a distância 3D cheia (inclui altura)
-- contra GK_DIVE_CAPTURE_RADIUS — uma bola alta (cabeceio/cruzamento)
-- "gastava" boa parte do raio só na diferença de altura, sobrando pouca
-- margem horizontal e fazendo o goleiro perder bola no ar que deveria
-- pegar. Agora horizontal e vertical são checados SEPARADOS: o raio acima
-- é só a distância horizontal (XZ), e GK_DIVE_CAPTURE_HEIGHT abaixo é a
-- tolerância vertical (bem mais generosa, cobre cabeceio/cruzamento alto)
-- — ver o Heartbeat de captura em BallController.lua.
-- PEDIDO: ficou fácil demais pegar uma bola RETA só usando qualquer
-- mergulho (ex: o de cima/"pulo") perto do corpo, sem precisar acertar
-- a direção certa — a captura não olha pra direção do mergulho, só pra
-- distância até o goleiro, então um raio/altura grandes bastavam pra
-- "pegar tudo". Reduzido um pouco os dois (eram 5 e 14) — ainda bem mais
-- generoso que o original (que causava o problema oposto, bola alta
-- passando batida), só que agora exige um pouco mais de leitura/tempo
-- certo do goleiro.
-- ⚠️ v36: AUMENTADO um pouco (pedido: "um pouco de hitbox a mais" no GK
-- humano, junto com o dive acima).
-- ⚠️ v67 — PEDIDO: "melhora um pouco a hitbox do goleiro humano". 7.5 -> 9.5.
-- ⚠️ v67 — PEDIDO: "aumenta a força do GK player; na área, só o CHUTE vai
-- aumentar. Nenhuma Hissatsu vai aumentar — só pra ele conseguir fazer o
-- passe normalmente para os jogadores."
-- Multiplica a força máxima do chute/passe NORMAL enquanto ele é goleiro
-- dentro da própria área. Não toca em Hissatsu (ver getGKAreaKickBonus em
-- BallController, que de propósito fica FORA de getKickForceMultiplier).
Config.GK_AREA_KICK_FORCE_MULT = 1.45

Config.GK_DIVE_CAPTURE_RADIUS = 9.5   -- era 7.5 (+27%)
Config.GK_DIVE_CAPTURE_HEIGHT = 18    -- era 16.5/11/14
-- ⚠️ v5.6: chegou a baixar pra 0.5 (pedido de "velocidade de reação" do
-- goleiro). ⚠️ v5.7: REVERTIDO pro valor original — o pedido era sobre o
-- GKBOT (ver Config.GKBOT_ACTION_COOLDOWN), não o Role="GK" humano.
Config.GK_DIVE_COOLDOWN = 1.0         -- segundos antes de poder mergulhar de novo

-- ===== GOLEIRO: DASH PRA FRENTE (tecla F) =====
-- Avança em linha reta (LookVector). Se um ADVERSÁRIO com a bola estiver
-- perto o bastante ao fim do dash, rouba a posse (igual um carrinho,
-- mas sem gastar stamina de carrinho — é a ferramenta própria do
-- goleiro). Se não tem adversário com bola por perto, mas a BOLA (solta
-- ou vindo em direção ao gol) passa perto o bastante, captura.
-- ⚠️ v5.5 FIX: "o dash vai pra frente e já volta, sem pegar ninguém". Era
-- SEMPRE uma linha reta fixa de 12 studs na direção que o goleiro já
-- estava olhando — não perseguia ninguém de verdade, e 12 studs é curto
-- demais pra alcançar um adversário que não estava bem colado. Agora (ver
-- AttemptGKForward em BallController.legacy.luau): se tem um adversário
-- com a bola (ou a bola solta) a até GK_FORWARD_CHASE_RANGE studs, o dash
-- mira DIREITO nele e percorre a distância até lá (até o teto de
-- segurança GK_FORWARD_DASH_MAX_DISTANCE, numa velocidade fixa — dash
-- mais longe demora mais, não "voa"); sem ninguém nesse raio, cai pro
-- dash curto de sempre (GK_FORWARD_DASH_DISTANCE), reto pra frente.
Config.GK_FORWARD_DASH_DISTANCE = 42 -- v110: era 28 (distância maior) · ⚠️ v105: x2 ("tá muito perto, pode dobrar") — era 14
Config.GK_FORWARD_DASH_DURATION = 0.45 -- v110: era 0.35 (voo mais longo)
Config.GK_FORWARD_CHASE_RANGE = 50      -- studs: alcance pra "travar" um alvo (adversário com bola ou bola solta) e perseguir ele
Config.GK_FORWARD_DASH_MAX_DISTANCE = 85 -- v110: era 70 · studs: teto de segurança pro dash perseguindo um alvo longe (⚠️ v105: era 45)
-- ⚠️ v105 — PULO ALTO DO GOLEIRO. PEDIDO: "tira o dive pra cima... o jogador vai
-- pular alto quando estiver no gol, até a altura do travessão, e aí pula e dá o
-- dive pro lado". JumpHeight (studs) do goleiro DENTRO da própria área.
Config.GK_PULO_ALTURA = 14
-- ⚠️ v105 — "a hitbox do goleiro vai pegar automaticamente: se a bola passar
-- nele, no meio dele, ele pega na hora" (goleiro humano; o bot já tinha a caixa
-- GKBOT_GUARANTEED_CATCH_BOX). Cilindro em volta do HumanoidRootPart.
Config.GK_CORPO_CAPTURA = { Raio = 2.8, Baixo = 3.4, Alto = 3.8 }
Config.GK_FORWARD_DASH_SPEED = 45        -- studs/s: velocidade do dash quando perseguindo (define a duração — quanto mais longe, mais tempo demora)
Config.GK_FORWARD_STEAL_RANGE = 8       -- ⚠️ v5.5: +2 (era 6) — alcance pra roubar de um adversário com a bola (o alvo pode ter se mexido durante o dash mais longo)
Config.GK_FORWARD_CAPTURE_RANGE = 7     -- ⚠️ v5.5: +2 (era 5) — alcance pra capturar a bola solta/vindo
-- ⚠️ v5.6: chegou a baixar pra 0.8. ⚠️ v5.7: REVERTIDO — mesmo motivo do
-- GK_DIVE_COOLDOWN acima (era pro GKBOT, não pro Role="GK" humano).
Config.GK_FORWARD_COOLDOWN = 1.5

-- ===== MECÂNICA DE CORPO (bola bate, corpo absorve) =====
-- Bola/Players não colidem fisicamente de propósito (ver PhysicsService
-- no topo deste arquivo) — o "bater no corpo" é checado por
-- proximidade+velocidade no BallController.lua, não pela física de
-- verdade. Quando a bola passa rápido perto de alguém que NÃO tem a
-- posse, o corpo absorve parte da força — quanto MAIOR o Physical, MAIS
-- absorve (mas nunca 100%: mesmo no Physical máximo ainda sobra um
-- pouco de força, pra ficar "justo" e não virar uma parede).
-- ⚠️ v14 FIX: "eu não consigo chutar reto porque ela não está
-- atravessando o personagem" — o log com os prints de diagnóstico (v13)
-- confirmou 0% colisão física (nunca disparou o aviso de colisão real) e
-- mostrou a causa de verdade: o MESMO jogador parado do lado da bola
-- voltava a "bloquear" ela de novo a cada 0.3s (BODY_BLOCK_DEBOUNCE),
-- moendo a velocidade repetidas vezes até praticamente zerar — um chute
-- reto perto de qualquer jogador (companheiro ou adversário) virava uma
-- sequência de vários cortes de 35-75% em cadeia, não só um. Agora cada
-- chute/lance só pode ser "absorvido pelo corpo" UMA VEZ — depois disso
-- o corpo daquele jogador fica isento até o próximo chute de verdade
-- (ver BallController.lua -> hasBodyBlockedThisFlight). Também dá pra
-- desligar a mecânica inteira daqui embaixo se preferir testar sem ela.
Config.BODY_BLOCK_ENABLED = true             -- false = desliga completamente a mecânica de corpo (bola sempre atravessa os jogadores)
Config.BODY_BLOCK_RADIUS = 2.2               -- studs, escalado pelo PHYSICAL_SCALE do dono do corpo (ver applyPhysicalScale)
Config.BODY_BLOCK_MIN_SPEED = 20             -- só conta como "bateu" acima dessa velocidade (senão é só um toque/drible normal)
Config.BODY_BLOCK_MIN_ABSORPTION = 0.35      -- Physical = 0: ainda absorve 35%
Config.BODY_BLOCK_MAX_ABSORPTION = 0.75      -- Physical = 100: absorve até 75% (nunca 100%)
Config.BODY_BLOCK_DEBOUNCE = 0.3             -- segundos antes do mesmo corpo poder "bloquear" de novo (só importa pra decidir QUANDO solta — ver "uma vez por lance" acima)
-- ⚠️ v13 FIX: "a bola bate no jogador e ricocheteia, tipo bate no
-- quadril". NÃO é colisão física de verdade — Bola x Players já é
-- explicitamente 'false' aqui em cima (PhysicsService), então "desativar
-- a colisão e deixar só Query" não muda nada, essa dupla já nunca colide
-- fisicamente. O que causava a SENSAÇÃO de ricochete era o corte de
-- velocidade ser instantâneo — um multiply inteiro num frame só. Com a
-- bola no ar, a gravidade continua puxando ela pra baixo; perder até 75%
-- da velocidade horizontal DE UMA VEZ bem na altura do quadril (onde
-- fica o HumanoidRootPart, centro do raio BODY_BLOCK_RADIUS) faz a
-- trajetória "quebrar" ali do nada — visualmente idêntico a bater numa
-- parede invisível, mesmo sem nenhuma física de colisão envolvida.
-- BODY_BLOCK_EASE_SECONDS espalha esse mesmo corte ao longo de vários
-- frames (decaimento suave) em vez de um só — a queda de velocidade
-- fica gradual, sem o "kink" que parecia ricochete (ver BallController.
-- lua, MECÂNICA DE CORPO).
Config.BODY_BLOCK_EASE_SECONDS = 0.15
-- FIX (bug reportado em v11, v12 E de novo em v14 — "eu chuto reto e a
-- bola trava, tenta colidir com o corpo do PRÓPRIO personagem"): quem
-- chuta/cabeceia a bola precisa ficar imune à própria mecânica de corpo,
-- senão o próprio chute esbarra nele mesmo.
-- ⚠️ v12 tentou: imunidade só até a bola sair do raio do corpo UMA vez
-- (depois disso, destravava pra sempre). Só que num chute mais fraco/reto
-- é comum o PRÓPRIO jogador (correndo na mesma direção, às vezes mais
-- rápido que a bola freando por atrito) alcançar a bola de novo — e como
-- a imunidade já tinha sido consumida, o corpo dele voltava a bloquear o
-- PRÓPRIO chute de verdade. ⚠️ v15 FIX: a imunidade não se destrava mais
-- por distância — só termina quando ALGUÉM (qualquer jogador, incluindo
-- ele mesmo pegando de volta) realmente tomar posse da bola de novo (ver
-- BallController.lua -> setOwner), ou depois deste tempo aqui (teto de
-- segurança, pra bola solta que ninguém encosta nunca mais não ficar
-- imune de propósito indefinidamente).
Config.BODY_BLOCK_SELF_IMMUNITY_MAX = 3

-- ===== CARRINHO (TACKLE) =====
-- Mesma tecla no cliente pra tudo: se alguém JÁ tem a bola, tenta roubar
-- a posse (só se ela for ADVERSÁRIA — ver checagem de time no
-- BallController); se a bola está SOLTA, é um "dash" até ela (não
-- depende de time, qualquer um pode disputar bola solta).
Config.TACKLE_STAMINA_COST = 25
-- ⚠️ v67 — PEDIDO: "após tomar carrinho o jogador fica stunado por tempo
-- demais curto; deixa ele stunado por um dobro e meio do tempo, 150%".
-- 0.5 -> 1.25 (2.5x). É o tempo que o driblador tem pra ganhar vantagem
-- de verdade depois de acertar o desarme.
Config.TACKLE_VICTIM_STUN = 1.25
-- PEDIDO: antes não tinha cooldown nenhum (só o custo de stamina
-- segurava, igual o sprint) — dava pra spamar a tecla. Agora tem um
-- cooldown FIXO de 4s por tentativa, acertando ou errando.
Config.TACKLE_COOLDOWN = 4.2 -- ⚠️ v111: "coloca um pouco mais de cooldown pro carrinho, tipo 0.2 segundos a mais"
-- ⚠️ v17 — PEDIDO: "quem tá com a bola fica 10% mais lento". Multiplicador
-- aplicado em cima da velocidade final de quem está conduzindo (ver
-- getPossessionMultiplier em PlayerSystems.legacy.luau). 1 desliga.
Config.BALL_CARRIER_SPEED_MULT = 0.8 -- v110: era 0.9 ("perder 20% da velocidade com a bola, não 10") — incentiva o toque pra frente

-- ⚠️ v19 (ver refreshTrackSpeed em PlayerSystems.legacy.luau).
-- ⚠️ v61 — TRANSIÇÕES DO MOVIMENTO (ver playTrack em PlayerSystems).
-- PEDIDO: "a animação de andar não pode ter idle; ela tem que parar no
-- momento que você resolve parar, e aí faz uma transiçãozinha pro idle."
-- Entrar no movimento é quase seco (o pé sai junto com a tecla); voltar pro
-- idle é o único que ganha fade de verdade. Antes os dois eram 0.15, o que
-- somava atraso justo na partida.
Config.MOVEMENT_FADE_TO_MOVE = 0.05 -- idle -> andar/correr (quanto menor, mais imediato)
Config.MOVEMENT_FADE_TO_IDLE = 0.2  -- andar/correr -> idle (a "transiçãozinha")

Config.MOVEMENT_ANIMATION_BASE_RATE = 1.15 -- "um pouco mais rápido" que o original
Config.MOVEMENT_ANIMATION_MIN_RATE = 0.6
Config.MOVEMENT_ANIMATION_MAX_RATE = 2.2

-- ⚠️ v17: era 10.08 — pedido: "aumenta um pouco a distância do carrinho".
-- Esse é o alcance de RESOLUÇÃO (a que distância o desarme conta); o
-- alcance do avanço em si é TACKLE_DASH_FORCE * TACKLE_DASH_DURATION,
-- logo abaixo, que subiu junto pra o carrinho direcional alcançar de
-- verdade o espaço que o jogador mirou.
-- ⚠️ v84 — PEDIDO: "aumente 10% da distância do carrinho". Sobe junto com o
-- deslize (TACKLE_DASH_FORCE), igual o v17 fez da outra vez: alcance de
-- resolução e alcance do avanço andam juntos. Era 12.1.
Config.TACKLE_RANGE = 13.3
Config.TACKLE_BASE_CHANCE = 0.65
Config.TACKLE_LOOSE_BALL_IMPULSE = 20

-- Lunge (arremesso pra frente) do carrinho: deslocamento DIRETO por
-- CFrame (igual à finta), na direção em que o jogador está OLHANDO no
-- instante em que aperta — não mais em direção à bola/ao alvo. Distância
-- do lunge = TACKLE_DASH_FORCE * TACKLE_DASH_DURATION.
-- ⚠️ v6.5: PEDIDO — "aumente um pouco a distancia do carrinho". Era
-- 50 * 0.3 = 15 studs de alcance total do lunge; agora 50 * 0.36 = 18
-- studs (~20% a mais), mexendo só na duração (mantém a "força"/velocidade
-- do arremesso igual, só dura um pouco mais).
-- ⚠️ v57 — PEDIDO: "vou fazer 0.5 de duração do tackle, calcule pra ele ir
-- MAIS LONGE com esses 0.5."
--
-- A distância do carrinho é FORCE x DURATION, então esticar a duração e
-- MANTER a força já é exatamente "ir mais longe", sem precisar mexer em
-- mais nada:
--     antes:  62 x 0.36 = 22.3 studs
--     agora:  62 x 0.50 = 31.0 studs   (+39%)
--
-- A velocidade do deslize (a "força") fica igual — ele não fica mais
-- rápido, ele desliza por mais tempo, que é o que combina com a animação
-- de 0.5s.
--
-- Esses 0.5 valem pra TUDO que o carrinho faz: a distância percorrida, o
-- instante em que o roubo é resolvido, e o tempo em que a rotação por
-- shift lock fica suprimida (todos leem esta mesma chave). Então a
-- animação de 0.5s cobre o lance inteiro, do impulso até o corpo no chão.
-- ⚠️ v84 — PEDIDO: "+10% de distância". A duração (0.5) fica — ela está
-- amarrada à animação de 0.5s e ao instante em que o roubo resolve — então
-- os 10% entram pela velocidade do deslize: 62 x 0.5 = 31.0 studs -> 68.2 x
-- 0.5 = 34.1 studs.
Config.TACKLE_DASH_FORCE = 68.2
Config.TACKLE_DASH_DURATION = 0.5

-- ⚠️ v86 — DASH (tecla F). PEDIDO: "o carrinho, na verdade, é o Q, quando
-- você não estiver com a bola... o F pode ser utilizado para dar um dash, que
-- é meio que um avanço para frente". Não rouba bola e não derruba ninguém: é
-- só um arranque curto na direção do WASD (parado = pra onde o personagem
-- olha). Vale com ou sem a bola — com ela, a condução acompanha sozinha.
-- O deslocamento é aplicado pelo PRÓPRIO cliente (Remotes.ApplyDisplacement),
-- então o jogador continua andando normalmente durante o arranque.
Config.DASH_DISTANCE = 16      -- studs percorridos a mais pelo arranque
Config.DASH_DURATION = 0.25    -- segundos que o arranque leva
Config.DASH_COOLDOWN = 2.5
Config.DASH_STAMINA_COST = 12

-- Se o carrinho não rouba a posse nem chega na bola solta, o jogador
-- fica estirado no chão (sem se mover) por esse tempo.
-- ⚠️ v57: este é o tempo-alvo da animação SEPARADA Config.ANIMATIONS.
-- TackleMiss — ela começa com ele já no chão e termina com ele DE PÉ.
-- Só acontece quando o carrinho ERRA; acertando, ele fica com a bola aos
-- 0.5s e sai jogando na hora, sem levantar-se nenhum no meio.
Config.TACKLE_MISS_STUN = 0.5

-- Janela de tempo pra dois carrinhos na mesma bola solta virarem uma
-- "disputa de carrinho" (resolvida pelo atributo Physical) em vez de dois
-- eventos separados e independentes.
Config.TACKLE_CONTEST_WINDOW = 0.25

-- Constante da curva de estabilização da disputa de carrinho (ver
-- resolvePhysicalClashChance no BallController). Quanto MAIOR esse
-- número, mais pontos de diferença de Physical são necessários pra
-- mover a balança.
Config.TACKLE_PHYSICAL_STABILIZE_K = 17

-- ===== PULSO: WIND-UP, COMBO DE TECLAS E IFRAME =====
-- ⚠️ NOVO (Pulso v3): o QTE do Pulso deixou de ser "aperte a MESMA tecla
-- de novo dentro de uma janela" e virou um COMBO de teclas (ex: Q → E →
-- Q), definido em cada Pulso por Combo = { Delay, StepTime, Keys } (ver
-- PulseInstinctData.luau). A duração total do wind-up é sempre
--     Delay + StepTime * #Keys
-- e é essa duração que manda nas duas constantes abaixo.
--
-- PULSE_IFRAME_MIN_WINDUP: regra GENÉRICA (implementada no
-- PulseController, não Pulso a Pulso) — todo Pulso cujo wind-up total
-- passe desse tempo deixa o jogador PARADO/exposto tempo demais pra ser
-- justo, então ele ganha IFRAME de Pulso durante TODO o wind-up: ninguém
-- consegue desarmá-lo/roubar dele nesse período (ver _G.GrantPulseIframe
-- /_G.HasPulseIframe no BallController.legacy.luau e o tratamento em
-- resolveStealAttempt). Um Pulso pode forçar isso mesmo com wind-up
-- curto com o campo opcional Iframe = true na definição dele.
-- Hoje, quem passa desses 2s: Pulso do Artilheiro (2.12s) e Pulso
-- Lendário: Chute Fatal (2.7s).
Config.PULSE_IFRAME_MIN_WINDUP = 2

-- TETO DURO do wind-up: nenhum Pulso pode ficar mais que isso entre o
-- aperto do botão e a resolução da ação (o servidor trunca o StepTime
-- se alguém cadastrar um Combo maior que isso por engano). O maior do
-- jogo hoje é o Chute Fatal, em ~2.7s — bem abaixo do teto.
Config.PULSE_MAX_WINDUP = 5

-- ⚠️ v3.2: QTE ficou mais fácil de apertar (pedido do usuário — "estão
-- muito difíceis de apertar"). Duas alavancas, as DUAS aplicadas no
-- servidor dentro de comboTiming/PulsePrecisionInput (PulseController) —
-- o cliente só ecoa o que o servidor manda, nunca decide sozinho.
-- PULSE_COMBO_STEP_TIME_MULT: multiplica o StepTime de TODO combo (cada
-- passo fica essa fração mais largo pra apertar) — 1.4 = 40% mais tempo
-- por passo. Ainda respeita o teto PULSE_MAX_WINDUP acima.
Config.PULSE_COMBO_STEP_TIME_MULT = 1.4
-- PULSE_COMBO_INPUT_GRACE: aperto até esse tanto de segundos ANTES do
-- passo abrir de verdade já conta pra ele (antecipação) — cobre o caso
-- clássico de "apertei um pouquinho cedo demais e não contou nada".
Config.PULSE_COMBO_INPUT_GRACE = 0.15

-- ===== ANIMAÇÕES =====
-- É AQUI que entram os AnimationId (rbxassetid://...) das animações do
-- jogo — cole o id publicado na chave certa (ou adicione uma chave nova
-- se for uma animação sem lugar ainda) e playAnimation (BallController.
-- legacy.luau) já cuida de carregar/tocar sozinho. Mesmo espírito do
-- Config.ANIMATIONS do LobbyConfig.lua (place Lobby) — são dois lugares
-- SEPARADOS porque os dois places não compartilham ReplicatedStorage.
-- ⚠️ NOVO: PEDIDO — "coloquei minha animação de andar pra 89188098199704,
-- e o boneco ficou estático" — causa exata (ver erro no Output: 'Invalid
-- animation id... unknown AssetId protocol'): colar só o NÚMERO sem o
-- prefixo "rbxassetid://" na frente quebra o Animate do personagem
-- inteiro (silenciosamente, sem travar o jogo, só aquela animação para de
-- funcionar). Esse helper aceita os DOIS jeitos — só o número OU já com
-- "rbxassetid://" — e sempre devolve o formato certo, usado em TODO lugar
-- que lê um AnimationId de Config.ANIMATIONS (overrideMovementAnimations,
-- playAnimation, playGoalCelebration, playCrowdCelebration etc.) — assim
-- colar sem o prefixo nunca mais quebra nada.
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
	return id -- formato estranho/já quebrado — devolve como está, mesmo erro de antes
end

Config.ANIMATIONS = {
	-- ⚠️ v58: as duas foram exportadas com 0.833s (25 frames a 30fps), mas as
	-- janelas da mecânica são 0.5s cada (TACKLE_DASH_DURATION e
	-- TACKLE_MISS_STUN). Não precisa reexportar: playAnimation recebe a
	-- janela-alvo e ajusta a velocidade de reprodução pra caber exatamente
	-- (ver o parâmetro `ajustarPara` em BallController.legacy.luau).
	-- Aqui elas tocam a ~1.67x. Se quiser no ritmo original, é só subir as
	-- duas janelas pra 0.833 no Config — mas repare que TACKLE_DASH_DURATION
	-- também define a DISTÂNCIA do carrinho (FORCE x DURATION).
	Tackle = "rbxassetid://79208354704868",
	-- ⚠️ v63 — DRIBLE, UMA ANIMAÇÃO POR DIREÇÃO.
	-- As três duram 0.583s e começam e terminam na pose de IDLE, então
	-- encaixam sozinhas com o resto sem precisar de fade especial.
	-- A velocidade de reprodução é ajustada pra caber na janela do drible,
	-- que cresce com o DribbleSkill (ver DRIBBLE_MOVE_* logo abaixo) — é
	-- assim que "quanto mais upado, mais longe" aparece também na animação.
	-- ⚠️ v86: o drible pra FRENTE não tem animação própria — PEDIDO: "a
	-- animação do para frente é só você fazer a animação do para trás, só que
	-- no reverse". Ele toca o Back de trás pra frente (ver `reverso` no
	-- playAnimation do BallController). Se um dia existir uma animação
	-- própria, é só adicionar `Forward = "rbxassetid://..."` aqui.
	Dribble = {
		Left  = "rbxassetid://111126363124140",
		Back  = "rbxassetid://78743173200051",
		Right = "rbxassetid://94415061917131",
	},

	-- ⚠️ v60 — CHUTE, em duas partes.
	-- PrepareKick (0.25s, em LOOP): toca enquanto o jogador SEGURA o botão
	-- carregando a força — o loop é o que deixa ela segurar a pose por
	-- quanto tempo ele quiser. Ligada/desligada pelo aviso que o cliente já
	-- manda (Remotes.UpdateKickCharging, ver BallController).
	-- Kick (0.55s): o chute em si, uma vez, quando a bola sai. Vale pro
	-- chute normal E pro de Hissatsu (os dois passam pelo mesmo ponto).
	-- Obs: o asset do Kick veio marcado como Looped no editor mesmo sendo
	-- ação única — o playAnimation força Looped=false nele, senão repetiria
	-- pra sempre depois do lance.
	-- ⚠️ v65 — CABEÇADA. Ação única, tocada tanto no cabeceio normal quanto
	-- no de Hissatsu (os dois passam pelos mesmos dois pontos).
	Header = "rbxassetid://83756627866650",

	-- ⚠️ v65 — GOLEIRO.
	-- GKIdle: parado do goleiro (pose de quem espera o chute). Substitui a
	-- Idle comum SÓ enquanto ele está sendo goleiro de verdade — dentro da
	-- própria área (mesma regra que o resto do jogo usa, IsEffectiveGK).
	-- Fora dela ele volta pra Idle normal, porque ali ele é jogador de linha.
	GKIdle = "rbxassetid://139455863761678",

	-- GKDive: uma por direção de mergulho. As teclas são Z/C/X/Q/E e os
	-- nomes abaixo são EXATAMENTE os que o GKInput manda (ver GKInput.local).
	-- Todas já incluem a LEVANTADA no final, então não precisa de animação
	-- separada de recuperação — a duração delas é maior que a janela do
	-- mergulho (GK_DIVE_DURATION) de propósito: o mergulho resolve antes, e o
	-- resto da animação é ele se recompondo.
	GKDive = {
		Left    = "rbxassetid://107446282020457",
		Right   = "rbxassetid://134439194491162",
		Up      = "rbxassetid://98508729113619",
		UpLeft  = "rbxassetid://123731180552957",
		UpRight = "rbxassetid://106695655711963",
	},

	-- ⚠️ v66 — DASH DE AVANÇO DO GOLEIRO (tecla F). Antes reaproveitava a
	-- animação de Tackle como placeholder; agora tem a própria. A duração da
	-- ação é VARIÁVEL (mais longe = mais tempo, ver AttemptGKForward), então
	-- a reprodução é ajustada pra essa duração real a cada uso, não um número
	-- fixo — igual o carrinho, só que com o alvo mudando por chamada.
	GKForwardDash = "rbxassetid://113953112581237",

	PrepareKick = "rbxassetid://89045958790726",
	Kick = "rbxassetid://111782657482163",
	TackleMiss = "rbxassetid://91993754786804", -- jogador caindo/estirado no chão após errar o carrinho

	-- ⚠️ NOVO: animação de comemoração de gol (separada a pedido do
	-- usuário — "é uma animação específica pra gol, já está pronta").
	-- Tocada no jogador que marcou o gol (ver playGoalCelebration em
	-- MatchController.legacy.luau) em LOOP por Config.GOAL_CELEBRATION_-
	-- SECONDS segundos, ANTES do replay começar. Cole o rbxassetid://
	-- aqui quando publicar — enquanto ficar "", nenhuma animação toca
	-- (sem erro, só pula essa parte).
	GoalCelebration = "",

	-- ⚠️ NOVO: PEDIDO — "a comemoração da torcida são esses dois:
	-- 71075180222011, 109633359624709... intercala eles no código, pra
	-- ser aleatório quem usa qual" — DIFERENTE de GoalCelebration (a do
	-- jogador que marcou): cada torcedor da arquibancada sorteia UM dos
	-- dois ao acaso quando sai um gol (ver playCrowdCelebration em
	-- CrowdClient.local.luau), então a torcida toda não fica comemorando
	-- toda igual/sincronizada.
	GoalCelebrationCrowd = { "rbxassetid://71075180222011", "rbxassetid://109633359624709" },

	-- ⚠️ NOVO: animações de MOVIMENTO (PEDIDO: "eu quero colocar animação
	-- de andar, correr, pular, etc..."). Diferente das de cima (tocadas
	-- sob demanda via playAnimation), essas SUBSTITUEM as animações
	-- padrão do Roblox dentro do próprio "Animate" de cada personagem —
	-- ver overrideMovementAnimations em PlayerSystems.legacy.luau. Cole o
	-- rbxassetid:// na chave certa; "" = mantém a animação PADRÃO do
	-- Roblox pra esse estado (não mexe em nada).
	-- ⚠️ v19: ritmo das animações de movimento (ver refreshTrackSpeed em
	-- PlayerSystems.legacy.luau). BASE_RATE é o "um pouco mais rápido" pedido
	-- (1.0 = exatamente a velocidade em que a animação foi feita); o resto
	-- escala sozinho com o WalkSpeed real do jogador, preso entre MIN e MAX
	-- pra não virar câmera lenta nem liquidificador.
	Idle = "rbxassetid://78224533756564",  -- Animate.idle.Animation1/Animation2 (as DUAS trocam juntas)
	-- ⚠️ v56 — PEDIDO: "a animação anterior de caminhada eu só quero que
	-- esteja presente na CUTSCENE; essa nova aqui vai estar presente em todo
	-- o resto." Então esta chave (que vale pro JOGO e pro replay de gol,
	-- ver ANIMATIONS.Walk nos três usos) recebeu a nova, e a antiga foi pra
	-- Config.CUTSCENE_WALK_ANIMATION, usada só por
	-- EntranceCutsceneClient.local.luau.
	Walk = "rbxassetid://108212086932657",  -- Animate.walk.WalkAnim
	Run = "rbxassetid://126606644574916",   -- Animate.run.RunAnim
	Jump = "rbxassetid://119293281806090",  -- Animate.jump.JumpAnim
	Fall = "",  -- Animate.fall.FallAnim
}

-- ⚠️ v84 — REGRAS DE REPRODUÇÃO DE CADA ANIMAÇÃO (fonte única).
-- PEDIDO: "na tela de algumas pessoas, quando alguém segura o chute, ele buga
-- entre as animações de chutar e andar e fica intercalando... faça algo bem
-- minucioso pra evitar que uma animação sobreponha a outra, do jeito que
-- está escrito".
--
-- As animações são tocadas pelo SERVIDOR (BallController.playAnimation e
-- PlayerSystems.overrideMovementAnimations), que ajusta Priority, Looped e
-- "congela no último quadro" (PrepareKick) por script. Só que o Roblox NÃO
-- garante que Looped/Priority mudados por script cheguem iguais nos OUTROS
-- clientes — cada cliente monta a própria cópia da track a partir do ASSET,
-- e nossos assets de ação vieram salvos como Looped. E o congelamento é feito
-- por tempo: o PrepareKick dura ~0.25s, então com latência o cliente remoto
-- passa do fim, reinicia o loop e alterna com a animação de andar antes do
-- "congela" chegar. Por isso "só na tela de algumas pessoas".
--
-- Estas regras são reaplicadas LOCALMENTE em todo cliente, em todo
-- personagem, por AnimationGuard.local.luau — cada tela passa a mostrar
-- exatamente o que o servidor pretende, independente do asset e da latência.
-- Elas espelham as chamadas do servidor; se uma prioridade mudar lá, mude
-- aqui também:
--   Movement: andar/correr/idle/pulo/queda (Movement — o piso)
--   Action:   preparo do chute, chute, cabeceio, carrinho, queda do
--             carrinho, avanço do goleiro
--   Action2:  fintas (drible) e mergulhos do goleiro (acima do chute, de
--             propósito — ver v63 no BallController)
-- HoldAtEnd = a animação para no último quadro e SEGURA a pose até alguém
-- dar Stop (preparo do chute enquanto o botão está segurado).
-- ⚠️ v96 — ANIMAÇÃO POR CÓDIGO (AnimadorProcedural.local.luau +
-- AnimacoesProcedurais.luau). Ligado: nenhum asset de animação toca em
-- personagem de jogador/goleiro — o servidor só AVISA a ação
-- (Remotes.AcaoAnimada) e cada cliente anima. Desligado (false): volta tudo
-- pro sistema antigo de assets (as IDs de ANIMATIONS acima).
Config.ANIMACAO_PROCEDURAL = true

-- ⚠️ v97: curva "banana" automática nos chutes de Hissatsu (CurveMult dos
-- Pulsos). Desligada: a bola vai reta pro ponto mirado (pedido "precisa ir
-- sempre reto aonde foi mirado").
Config.PULSE_CURVA_AUTOMATICA = false

function Config.BuildAnimationRules()
	local rules = {}
	local function add(id, priority, looped, holdAtEnd)
		id = Config.NormalizeAnimationId(id)
		if not id or id == "" then return end
		rules[id] = { Priority = priority, Looped = looped, HoldAtEnd = holdAtEnd == true }
	end
	local A = Config.ANIMATIONS
	local P = Enum.AnimationPriority

	for _, key in ipairs({ "Idle", "Walk", "Run", "Fall", "GKIdle" }) do
		add(A[key], P.Movement, true)
	end
	add(A.Jump, P.Movement, false)

	add(A.PrepareKick, P.Action, false, true)
	for _, key in ipairs({ "Kick", "Header", "Tackle", "TackleMiss", "GKForwardDash" }) do
		add(A[key], P.Action, false)
	end

	for _, group in ipairs({ A.Dribble, A.GKDive }) do
		if type(group) == "table" then
			for _, id in pairs(group) do add(id, P.Action2, false) end
		elseif type(group) == "string" then
			add(group, P.Action2, false)
		end
	end
	return rules
end

-- Quanto tempo o jogador que marcou fica comemorando (Config.ANIMATIONS.
-- GoalCelebration) antes do jogo cortar pro replay — pedido do usuário:
-- "durante uns 3-5 segundos". NÃO precisa bater com Config.GOAL_MUSIC_-
-- DURATION (o grito da torcida) — são independentes de propósito: a
-- torcida (ver MusicClient.local.luau) para de comemorar sozinha quando
-- o som dela acabar, mesmo que isso caia no meio do replay — é assim
-- mesmo (pedido do usuário: "a torcida não comemora pra sempre").
Config.GOAL_CELEBRATION_SECONDS = 4

-- ⚠️ v31 — CORTE E FADE DO APITO (ver playWhistle em MatchController).
-- O arquivo do apito tem cauda morta depois do som em si, então ele não toca
-- inteiro: para na fração abaixo da duração, com um fade pra não estalar.
-- ⚠️ v48 — PEDIDO: "pode manter normal o apito, mas AUMENTA um pouco ele,
-- já que vai colocar música, e aí ele só sobrescreve a música na hora. É
-- rapidinho." Era 0.7. A música toca em 0.6, então 1.0 põe o apito
-- claramente por cima sem precisar abaixar nada — o apito dura menos de
-- um segundo, não compensa mexer no volume da música pra isso.
Config.WHISTLE_VOLUME = 1
Config.WHISTLE_PLAY_FRACTION = 0.5    -- toca só metade do arquivo
Config.WHISTLE_FADE_SECONDS = 0.3     -- fade out no fim desse trecho
Config.WHISTLE_FALLBACK_SECONDS = 1.6 -- usado só se o som não tiver carregado a tempo de informar a duração real

-- ===== SONS =====
-- ⚠️ v110 FIX: Kick/Goal/Tackle apontavam pra ids que NÃO são áudio ("Failed to
-- load sound ... Asset type does not match requested type" em todo Play — chute,
-- gol e carrinho ficavam mudos). Trocados por sons que já vêm com o Roblox
-- (rbxasset://sounds/..., testados carregando). Pra usar os seus, cole o
-- rbxassetid:// do áudio aqui.
Config.SOUNDS = {
	Kick = "rbxasset://sounds/hit.wav",
	Goal = "rbxasset://sounds/electronicpingshort.wav",
	-- ⚠️ v30 — PEDIDO: "vou baixar um som de apito pra quando o jogo começar,
	-- ou a bola sair, ou quando acabar cada tempo. Separe um local específico
	-- pra colocar o som do apito."
	--
	-- É AQUI. Um id só, usado nos QUATRO momentos de apito do jogo:
	--   1. início de cada tempo          (runHalf, MatchController)
	--   2. recomeço depois de gol        (onGoalScored, MatchController)
	--   3. fim de cada tempo             (MatchController)
	--   4. bola saindo de campo          (OutOfBoundsController)
	-- Cole o rbxassetid:// aqui e os quatro passam a usar o novo som.
	-- Aceita com ou sem o prefixo (ver Config.NormalizeAnimationId — a
	-- mesma normalização vale pra som).
	Whistle = "rbxassetid://86973351197753",
	Tackle = "rbxasset://sounds/collide.wav",

	-- PEDIDO: "quero mudar o som de passos, remova-o por enquanto, mas
	-- coloque um espaço pra eu poder alterá-lo, junto com o de pulo
	-- também" — esses dois são os sons PADRÃO do Roblox (embutidos no
	-- Animate de cada personagem, sons "Running"/"Jumping" dentro do
	-- HumanoidRootPart), não algo que a gente tinha criado. Ver
	-- overrideMovementSounds em PlayerSystems.legacy.luau: ele silencia os
	-- dois (SoundId = "") todo CharacterAdded — deixe "" pra continuar
	-- mudo, ou cole um rbxassetid://... aqui pra trocar por outro som.
	Footstep = "", -- som de passos (Running) — "" = mudo (removido por enquanto)
	Jump = "",     -- som de pulo (Jumping) — "" = mudo (removido por enquanto)
}

-- ===== RECOMPENSAS =====
-- MVP_BONUS_MONEY calibrado (300 → 400) pra combinar com o preço do Roll
-- na Loja do Lobby (Config.SHOP.Roll.Cost = 200, em LobbyConfig.lua): um
-- MVP "básico" — só participação + vitória + bônus de MVP, sem gols/
-- assistência extra — já rende BASE_PARTICIPATION(100) + WIN_MONEY(500) +
-- MVP_BONUS_MONEY(400) = 1000, exatamente 5 rolls. Uma partida de MVP
-- de verdade (com gols/assistências/desarmes) rende mais que isso.
Config.REWARDS = {
	BASE_PARTICIPATION = 100,
	BASE_XP = 50,
	WIN_MONEY = 500,
	WIN_XP = 200,
	LOSE_MONEY = 100,
	LOSE_XP = 50,
	-- ⚠️ v104: EMPATE agora é resultado próprio (antes contava como derrota
	-- pros dois times) — meio caminho entre vitória e derrota.
	DRAW_MONEY = 250,
	DRAW_XP = 110,
	GOAL_MONEY = 150,
	GOAL_XP = 100,
	ASSIST_MONEY = 75,
	ASSIST_XP = 50,
	TACKLE_MONEY = 25,
	TACKLE_XP = 20,
	-- ⚠️ NOVO: fintas de drible (AttemptDribbleMove) SEMPRE dão certo — sem
	-- chance/porcentagem — então o valor direto por finta fica baixo de
	-- propósito (bem menor que TACKLE, que exige acertar um desarme de
	-- verdade); o grosso do incentivo pra driblar vem da missão diária
	-- "Driblar 20 vezes" (ver QuestData.luau no Lobby), não daqui.
	DRIBBLE_MONEY = 5,
	DRIBBLE_XP = 5,
	-- ⚠️ NOVO: defesa de goleiro (mergulho pegando chute perigoso vindo em
	-- direção ao próprio gol — ver Heartbeat de captura em
	-- BallController.legacy.luau). Valor entre TACKLE e GOAL: exige mais
	-- que um desarme comum (goleiro só, sob pressão de gol).
	SAVE_MONEY = 40,
	SAVE_XP = 30,
	MVP_BONUS_MONEY = 400,
	MVP_BONUS_XP = 150,
}

-- ===== REMOTE EVENTS =====
local function getOrCreateRemote(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

-- ⚠️ v109: evento NÃO-confiável (pra coisa que atualiza todo quadro, ex. a
-- mira do dono da bola pra Metavisão — perder um pacote não importa, o próximo
-- chega no quadro seguinte)
local function getOrCreateUnreliable(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("UnreliableRemoteEvent")
	remote.Name = name
	remote.Parent = parent
	return remote
end

local function getOrCreateRemoteFunction(parent, name)
	local existing = parent:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = parent
	return remote
end

-- ===== MÚSICA (⚠️ v11) =====
-- Pedido: "coloque uma parte pra eu colocar uma música de fundo, e outra
-- pra gol, me diga onde é e como eu coloco pra fazer funcionar". Como só
-- SCRIPTS sincronizam com o Studio pela ponte (Parts/GUI precisam ser
-- criadas manualmente lá), o Sound é criado inteiramente por código (ver
-- MusicClient.local.luau, StarterPlayerScripts) — a ÚNICA coisa que você
-- precisa fazer é colar os IDs dos seus dois áudios logo abaixo.
--
-- COMO PEGAR O ID: suba o áudio no Creator Hub (creator.roblox.com ->
-- Creations -> Audio, ou pelo Toolbox dentro do próprio Studio, aba
-- "Inventário" -> "Áudio" -> "Upload"). Depois de aprovado (o Roblox
-- modera automaticamente, geralmente rápido), o ID aparece como um
-- número — cole aqui embaixo no formato "rbxassetid://SEU_NUMERO".
--
-- Enquanto ficar como "" (vazio), aquela música simplesmente não toca
-- (um aviso aparece no console lembrando) — não quebra nada.
Config.BACKGROUND_MUSIC_ID = "rbxassetid://96405659011262" -- toca em loop o jogo inteiro
Config.BACKGROUND_MUSIC_VOLUME = 0.5

-- ⚠️ NOVO: PEDIDO — "no loop do áudio normal, ele sempre começa com um som
-- mais alto do que o final do mesmo áudio, dá pra fazer um fade-in que não
-- comece no mudo? tipo, começa em 60% e vai aumentando pro 100%". O áudio
-- de torcida (BACKGROUND_MUSIC_ID) tem um salto de volume perceptível toda
-- vez que ele reinicia o loop, porque o fim do arquivo é mais baixo que o
-- começo. Sound:Play() não tem um "fade" nativo, então MusicClient.lua
-- escuta o evento Sound.DidLoop (dispara toda vez que um Sound com
-- Looped=true termina e reinicia sozinho, sem cortar o áudio) e nesse
-- instante abaixa o volume pra essa fração aqui, subindo de volta pro
-- volume normal (BACKGROUND_MUSIC_VOLUME) em BACKGROUND_MUSIC_LOOP_FADE_-
-- SECONDS — inclusive na PRIMEIRA vez que toca, não só nos loops seguintes.
Config.BACKGROUND_MUSIC_LOOP_FADE_START_FRACTION = 0.6 -- começa em 60% do volume, não mudo (pedido explícito, não usar 0)
Config.BACKGROUND_MUSIC_LOOP_FADE_SECONDS = 1.5 -- tempo pra subir de 60% até 100%

-- ⚠️ NOVO: MÚSICA DE FUNDO SECUNDÁRIA (uma trilha musical de verdade, além
-- da torcida) — pedido: "depois eu vejo uma música legal pra colocar
-- também e abafar um pouco a torcida, pra não ficar enjoativo, mas por
-- enquanto coloque o código da futura música pra eu só inserir ela". Deixa
-- "" (vazio) até você colar o rbxassetid — com vazio, nenhum Sound extra é
-- criado e nada muda no jogo (mesmo aviso no console dos outros dois,
-- lembrando que está vazio). Segue o MESMO fade-in de loop configurado
-- acima (SECONDARY_MUSIC_LOOP_FADE_*), pro problema do "começa mais alto"
-- não voltar quando você colar o ID.
-- ⚠️ v48 — PLAYLIST. PEDIDO: "eu vou colocar mais músicas, por enquanto
-- deixa só essa." Pra adicionar outra faixa depois, é SÓ acrescentar o id
-- nesta lista — o MusicClient já toca uma atrás da outra, em ordem, e
-- volta pro começo no fim da lista. Nada mais precisa ser mexido.
--
-- Com UMA faixa só (o caso de hoje), ela toca em loop com o mesmo fade-in
-- de sempre. Com duas ou mais, o loop é desligado e a troca acontece no
-- fim de cada faixa, cada uma entrando com o mesmo fade.
Config.MUSIC_PLAYLIST = {
	"rbxassetid://103088757921783", -- trilha de Blue Lock
	"rbxassetid://118992959258919",
	"rbxassetid://131451324620013", -- Egoist
}

-- ⚠️ v49 — PEDIDO: "todas as músicas acabam finalizando um segundo e meio
-- antes do áudio acabar. Então tira um segundo e meio do final de tudo e
-- coloca um fade out no final de todas as músicas."
--
-- Os arquivos têm cauda morta no fim. Em vez de reeditar cada áudio, o
-- corte é feito por código: cada faixa toca até (duração - CORTE) e os
-- últimos segundos antes disso desvanecem, então a troca pra próxima
-- faixa não tem nem silêncio nem corte seco. Vale pra TODAS as faixas,
-- incluindo a da prorrogação.
Config.MUSIC_TAIL_CUT_SECONDS = 1.5
Config.MUSIC_FADE_OUT_SECONDS = 1.5

-- ⚠️ v49 — MÚSICA DA PRORROGAÇÃO. PEDIDO: "começa todas do início MENOS a
-- do overtime; a do overtime começa a partir de 50 segundos e termina até
-- o final que eu te defini."
Config.OVERTIME_MUSIC_ID = "rbxassetid://72975927472923"
Config.OVERTIME_MUSIC_START_SECONDS = 50
-- ⚠️ v52 — PEDIDO: "coloca um fade in no overtime também." Exceção
-- deliberada à regra de "nunca começar no mudo" (que vale pra volta de
-- loop, onde o salto de volume incomodava): aqui a entrada do silêncio é
-- justamente o efeito dramático da virada pra prorrogação.
Config.OVERTIME_MUSIC_FADE_IN_SECONDS = 2

-- Mantido por compatibilidade: se MUSIC_PLAYLIST estiver vazia, o jogo
-- ainda aceita uma faixa única por aqui.
Config.SECONDARY_MUSIC_ID = ""
-- ⚠️ v53 — PEDIDO: "abaixa um pouco só o som da música, ela tá muito alta."
-- Era 0.6. Baixei pra 0.42 mexendo SÓ na música: a torcida continua em
-- 0.09, então a música segue claramente à frente dela (4.7x), que era o
-- pedido original — só parou de dominar a cena.
Config.SECONDARY_MUSIC_VOLUME = 0.22 -- ⚠️ v85: -25% de novo (era 0.29; antes 0.42) — pedido "abaixe APENAS a música mais 25%"
Config.SECONDARY_MUSIC_LOOP_FADE_START_FRACTION = 0.6
Config.SECONDARY_MUSIC_LOOP_FADE_SECONDS = 1.5
-- Enquanto a música secundária estiver tocando, abaixa a torcida de fundo
-- pra esse multiplicador (0-1) o tempo todo — "abafar um pouco a torcida",
-- pra ela não brigar com a música nem ficar repetitiva/enjoativa por cima.
-- Sem música secundária (ID vazio), a torcida toca no volume normal.
-- ⚠️ v48 — PEDIDO: "diminua um pouco o som da torcida pra ficar só um
-- barulhinho leve de fundo, quase imperceptível." Era 0.65 (torcida em
-- 0.325); 0.18 leva pra 0.09 — presente como ambiente, sem competir.
Config.SECONDARY_MUSIC_CROWD_DUCK_MULT = 0.18
-- Na hora do gol, o som de TORCIDA COMEMORANDO (GOAL_MUSIC_ID) toca por
-- cima de tudo — a música secundária abaixa ainda mais nesse momento (pra
-- esse multiplicador) e volta ao normal sozinha ao fim de GOAL_MUSIC_-
-- DURATION, com um fade de GOAL_MUSIC_FADE_SECONDS pra cada lado (desce e
-- sobe suave, não corta seco).
-- ⚠️ v48 — PEDIDO: "a música ela BAIXA UM POUCO na hora do gol e na hora
-- do apito, nas comemorações." Era 0.15, que praticamente apagava a
-- música; 0.35 é o "baixa um pouco" — ela continua audível por baixo do
-- grito da torcida, só sai da frente.
Config.SECONDARY_MUSIC_GOAL_DUCK_MULT = 0.35


-- PEDIDO: "eu quero que dure só os primeiros 5 segundos, com um fade-out
-- pra não cortar bruscamente, eu preciso fazer isso, ou o Roblox consegue
-- fazer também?" — o Roblox (o script, ver MusicClient.local.luau) já
-- corta e desvanece sozinho, mesmo que o arquivo de áudio original seja
-- bem mais longo que 5s. Não precisa editar/cortar o arquivo você mesmo.
Config.GOAL_MUSIC_ID = "rbxassetid://82416585280705" -- toca só quando alguém marca um gol
Config.GOAL_MUSIC_VOLUME = 0.8
-- ⚠️ v14: PEDIDO — "expanda a duração do áudio pra duração da jogada, uns
-- 5-10 segundos" — subi de 5 pra 8s (meio-termo) pra caber o replay
-- inteiro (ver GOAL_REPLAY_DURATION abaixo) mais uma respirada antes do
-- fade. Ajuste livremente entre 5 e 10 conforme o gosto.
Config.GOAL_MUSIC_DURATION = 8 -- segundos totais que toca (incluindo o fade)
Config.GOAL_MUSIC_FADE_SECONDS = 2 -- os últimos X segundos desses 8 desvanecem em vez de cortar seco

-- ===== REPLAY DE GOL (⚠️ v14 NOVO) =====
-- PEDIDO: "durante o áudio, coloque um sistema simples de replay que
-- visualiza a bola". BallController.lua guarda um histórico contínuo da
-- posição da bola (últimos GOAL_REPLAY_DURATION segundos, amostrado a
-- cada GOAL_REPLAY_SAMPLE_INTERVAL) e manda esse histórico pro cliente
-- assim que o gol é confirmado (Remotes.GoalReplay). O cliente
-- (GoalReplayClient.local.luau) desenha uma "bola fantasma" seguindo
-- esse caminho gravado e move a câmera atrás dela por
-- GOAL_REPLAY_PLAYBACK_SECONDS — puramente visual, não afeta o jogo real
-- (a bola de verdade já foi reposicionada pro centro nesse momento).
-- ⚠️ v112: 8 -> 12. Com 8 (+1 de folga), uma cutscene de Hissatsu que começou uns
-- 5-6s antes do gol já tinha sido apagada da lista de eventos quando o replay saía
-- ("só no primeiro gol aparece a Hissatsu").
Config.GOAL_REPLAY_DURATION = 12 -- quantos segundos de histórico ficam guardados (a jogada toda até o gol)
Config.GOAL_REPLAY_SAMPLE_INTERVAL = 0.05 -- a cada quanto tempo guarda um ponto (20 por segundo — suave sem pesar a rede)
Config.GOAL_REPLAY_PLAYBACK_SECONDS = 6 -- quanto tempo o replay dura na tela (pode ser diferente do histórico guardado — toca os últimos N segundos antes do gol)

local remotesFolder = ReplicatedStorage:FindFirstChild("FootballRemotes")
if not remotesFolder then
	remotesFolder = Instance.new("Folder")
	remotesFolder.Name = "FootballRemotes"
	remotesFolder.Parent = ReplicatedStorage
end

-- PassBall foi REMOVIDO: o chute (KickBall) agora cobre chute, passe
-- (mirando num companheiro) e voleio (bola no ar sem posse prévia).
-- UpdateControlLock foi REMOVIDO: o Control Lock virou um Shift Lock
-- 100% client-side (câmera + rotação do personagem), não precisa mais
-- avisar o servidor de nada.
--
-- ⚠️ REWORK "PULSO": ArmSkill foi REMOVIDO (era o fluxo antigo de
-- "armar e esperar a ação normal bater") — no lugar entram UsePulse
-- (aperta o botão, a ação JÁ executa sozinha) e PulsePrecisionInput (toque
-- de precisão, só pros Pulsos com janela/QTE — ver PulseController.lua).
Config.Remotes = {
	KickBall = getOrCreateRemote(remotesFolder, "KickBall"),
	AttemptTackle = getOrCreateRemote(remotesFolder, "AttemptTackle"),
	AttemptHeader = getOrCreateRemote(remotesFolder, "AttemptHeader"),
	AttemptDribbleMove = getOrCreateRemote(remotesFolder, "AttemptDribbleMove"),
	UpdateSprinting = getOrCreateRemote(remotesFolder, "UpdateSprinting"),
	UpdateKickCharging = getOrCreateRemote(remotesFolder, "UpdateKickCharging"), -- FireServer(bool) — segurando o botão de chute (carregando força), reduz WalkSpeed (ver PlayerSystems.lua)
	SuppressShiftLockRotation = getOrCreateRemote(remotesFolder, "SuppressShiftLockRotation"), -- ⚠️ NOVA
	AcaoAnimada = getOrCreateRemote(remotesFolder, "AcaoAnimada"), -- ⚠️ v96: server→TODOS, FireAllClients(model, chave, duração, parâmetros) — dispara uma ação no AnimadorProcedural ("Kick", "Dribble.Left", "GKDive.Up"... ou "parar:<chave>")
	UpdatePulseAim = getOrCreateRemote(remotesFolder, "UpdatePulseAim"), -- ⚠️ v92: FireServer(ponto) — mira ao vivo durante o PREPARO da Hissatsu de chute (ver HissatsuInput/PulseController)
	HissatsuCutscene = getOrCreateRemote(remotesFolder, "HissatsuCutscene"), -- ⚠️ v87: server→TODOS, FireAllClients(nome, chutador, CFrame inicial, bola local, horário do servidor) — toca a cutscene da Hissatsu (ver HissatsuCutscenes.luau)
	AttemptDash = getOrCreateRemote(remotesFolder, "AttemptDash"), -- ⚠️ v86: FireServer(direção) — dash de avanço da tecla F (não é carrinho)
	ApplyDisplacement = getOrCreateRemote(remotesFolder, "ApplyDisplacement"), -- ⚠️ v86: server→client, FireClient(deslocamento: Vector3, duração) — o cliente soma esse deslocamento ao próprio personagem ao longo da duração, SEM travar o andar (drible e dash, ver FootballClient)
	PossessionChanged = getOrCreateRemote(remotesFolder, "PossessionChanged"),
	UpdateMatchState = getOrCreateRemote(remotesFolder, "UpdateMatchState"),
	GoalScored = getOrCreateRemote(remotesFolder, "GoalScored"),
	-- ⚠️ v49: server→client, disparado quando a partida empatada entra na
	-- PRORROGAÇÃO. O cliente usa pra trocar a música (é o único momento em
	-- que uma faixa é cortada no meio, com fade — ver MusicClient).
	OvertimeStarted = getOrCreateRemote(remotesFolder, "OvertimeStarted"),
	ShowMatchSummary = getOrCreateRemote(remotesFolder, "ShowMatchSummary"),
	GoldenGoal = getOrCreateRemote(remotesFolder, "GoldenGoal"), -- ⚠️ v104: gol na prorrogação encerra a partida
	-- ⚠️ v104: TUTORIAL (TutorialServer / TutorialClient)
	TutorialPasso = getOrCreateRemote(remotesFolder, "TutorialPasso"), -- servidor -> cliente: passo atual / feito / fim
	TutorialAcao = getOrCreateRemote(remotesFolder, "TutorialAcao"), -- cliente -> servidor: "continuar" / "pular"
	-- ⚠️ v106: VFX próprio de cada Arma (ArmasVFX.local.luau) — no lugar da bolha azul
	ArmaVFX = getOrCreateRemote(remotesFolder, "ArmaVFX"), -- servidor -> todos: (personagem, nomeDaArma, raridade, ligado, duracao)
	-- ⚠️ v108: Metavisão — o dono da bola manda pra onde está mirando (~10x/s);
	-- o servidor grava no atributo "MiraBola" do jogador (replica pra todos)
	MiraDoDono = getOrCreateRemote(remotesFolder, "MiraDoDono"),
	-- ⚠️ v109: a mira agora vai TODO QUADRO por aqui (cliente dono -> servidor ->
	-- todos), sem passar por atributo (que atrasava e "travava" a linha)
	MiraDoDonoU = getOrCreateUnreliable(remotesFolder, "MiraDoDonoU"),
	-- ⚠️ v109: VFX das Hissatsus sem cutscene (HissatsuVFXClient.local.luau)
	HissatsuVFX = getOrCreateRemote(remotesFolder, "HissatsuVFX"), -- servidor -> todos: (personagem, nome, elemento)
	RequestTeamChange = getOrCreateRemote(remotesFolder, "RequestTeamChange"),
	UsePulse = getOrCreateRemote(remotesFolder, "UsePulse"), -- ⚠️ REWORK: FireServer(slotNumber) — dispara o Pulso do slot 1 ou 2 NA HORA (executa a ação sozinho). Jogador de linha: Q=1, E=2. Goleiro: só slot 1, tecla R (Q/E são do dive, ver GKInput.local.luau)
	PulsePrecisionInput = getOrCreateRemote(remotesFolder, "PulsePrecisionInput"), -- ⚠️ v3: FireServer(slotNumber, keyName) — um PASSO do combo de teclas do Pulso. keyName é "Q"/"E"/"R"; o servidor é quem sabe qual passo estava aberto no instante em que recebeu e se a tecla era a certa (ver PulseController.legacy.luau)
	PulseFeedback = getOrCreateRemote(remotesFolder, "PulseFeedback"), -- server→client, avisa usar/disparar/falhar/cooldown (ver kinds em PulseController.lua)
	PulsePrecisionPrompt = getOrCreateRemote(remotesFolder, "PulsePrecisionPrompt"), -- ⚠️ v3: server→client, FireClient(slot, delaySeconds, stepTime, pulseName, keysArray) — avisa o cliente pra mostrar a fileira de chips do combo (ver PulsePrecisionWindow.luau). Os 4 primeiros parâmetros mantêm a ordem antiga de propósito (lengthSeconds virou stepTime, o tempo de CADA passo); keysArray é a sequência ({"Q","E","Q"})
	AttemptGKDive = getOrCreateRemote(remotesFolder, "AttemptGKDive"), -- ⚠️ NOVA: FireServer(direction) — só goleiro (Z/X/C/E/Q)
	AttemptGKForward = getOrCreateRemote(remotesFolder, "AttemptGKForward"), -- ⚠️ NOVA: FireServer() — dash pra frente do goleiro (tecla F)
	GetMyAbilities = getOrCreateRemoteFunction(remotesFolder, "GetMyAbilities"), -- ⚠️ NOVA: InvokeServer() → { Pulse1=nome/nil, Pulse2=nome/nil, Instinct=nome/nil } — pro HUD de habilidades (ver AbilityHUD.local.luau)
	InstinctFeedback = getOrCreateRemote(remotesFolder, "InstinctFeedback"), -- ⚠️ NOVA: server→client, FireClient(player, active:boolean) — avisa quando o Instinto equipado está "ativo" (condição cumprida agora), pro HUD mostrar
	ActivateInstinctMode = getOrCreateRemote(remotesFolder, "ActivateInstinctMode"), -- ⚠️ NOVA (Instinct Mode): FireServer() — gasta o medidor cheio (100) e ativa o Instinct Mode por INSTINCT_MODE_DURATION segundos (ver InstinctController.lua)
	-- ⚠️ v5.1: FireServer() quando o jogador aperta R. A maior parte dos
	-- Instintos é passiva e ignora isso; os que têm Tecla = "R" (ver
	-- PulseInstinctData.luau) só acontecem quando o jogador aperta. Vale
	-- pra goleiro E jogador de linha — R é a mesma tecla pros dois, e Q/E
	-- ficaram livres (o goleiro usa Q/E nos mergulhos diagonais).
	ActivateInstinct = getOrCreateRemote(remotesFolder, "ActivateInstinct"),
	InstinctModeFeedback = getOrCreateRemote(remotesFolder, "InstinctModeFeedback"), -- ⚠️ NOVA: server→client, FireClient(kind, extra) — kinds: "MeterUpdate" (extra=0-100), "ModeActivated" (extra=duração em segundos), "ModeEnded" ()
	RequestPass = getOrCreateRemote(remotesFolder, "RequestPass"), -- ⚠️ NOVA: FireServer() — tecla T, jogador de linha (não-GK) pede passe; liga Attribute WantsPass + destaque visual (ver PassRequestController.lua) e dá prioridade pra receber lançamento do GKBot (ver GKBotController.lua)
	DebugConfigureTesting = getOrCreateRemote(remotesFolder, "DebugConfigureTesting"), -- ⚠️ NOVA/TEMPORÁRIA (ferramenta de teste, ver DebugAbilitySelector.lua): FireServer(kind, value) — kind: "Pulse1"/"Pulse2"/"Instinct"/"Role". Apague o par de scripts Debug* quando não precisar mais testar
	GambleTimerFeedback = getOrCreateRemote(remotesFolder, "GambleTimerFeedback"), -- ⚠️ v5.4: server→client, FireClient(player, secondsUntilNextRoll) — Instinto "Apostador": toda vez que uma rodada nova de sorte começa, avisa o cliente pra mostrar a contagem regressiva (ver AbilityHUD.local.luau)

	-- ⚠️ v6 — PULSOS/HISSATSU: QTE NOVO, DIFERENTE DO COMBO DE TECLAS (v3,
	-- ver PulsePrecisionPrompt/PulsePrecisionInput acima, que continuam
	-- existindo mas nenhum Pulso novo usa mais). Pedido do usuário: chute
	-- = clicar um alvo que aparece em posição aleatória dentro de um
	-- quadrado da tela; defesa = apertar no momento certo numa barra;
	-- arrancada = alternar A/D. Um par de Remotes só, genérico pros 3
	-- tipos (o campo Kind dentro do payload decide qual — ver
	-- PulseInstinctData.luau -> campo QTE de cada Pulso, e
	-- PulseController.legacy.luau -> startHissatsuQTE).
	PulseQTEPrompt = getOrCreateRemote(remotesFolder, "PulseQTEPrompt"), -- server→client, FireClient(slot, pulseName, paramsTable) — paramsTable.Kind = "Tap"|"TimingBar"|"MashAD" + os campos específicos de cada um (ver PulseController.legacy.luau)
	PulseQTEInput = getOrCreateRemote(remotesFolder, "PulseQTEInput"), -- FireServer(slot, payload) — payload varia por Kind: Tap não precisa de nada extra, TimingBar não precisa de nada extra (só o instante do aperto importa, e quem mede isso é o servidor), MashAD manda {Key="A"|"D"}

	-- ⚠️ v9: "energia de ativação" da Hissatsu — server→client, FireClient
	-- (current, max) toda vez que o pool muda (gasto ao usar um Pulso, ou
	-- a cada tick perceptível de regeneração) — ver PulseController.
	-- legacy.luau/_G.GetPulseEnergy e AbilityHUD.local.luau.
	PulseEnergyFeedback = getOrCreateRemote(remotesFolder, "PulseEnergyFeedback"),
	-- ⚠️ v14 NOVO: PEDIDO — "durante o áudio, coloque um sistema simples de
	-- replay que visualiza a bola". server→client, FireAllClients(scoringTeam,
	-- points) logo que o gol é confirmado — points é um array de {x,y,z,t}
	-- com a posição da bola nos últimos Config.GOAL_REPLAY_DURATION segundos
	-- (ver BallController.lua -> ballHistory / GoalReplayClient.local.luau).
	GoalReplay = getOrCreateRemote(remotesFolder, "GoalReplay"),

	-- ⚠️ NOVO: CUTSCENE DE ENTRADA — pedido: "quero incluir uma cutscene de
	-- entrada, os dois times passam ao mesmo tempo um ao lado do outro,
	-- numa fila tradicional, indo em direção ao campo, depois corta pra
	-- todo mundo dentro de campo". server→client, FireAllClients(roster,
	-- duration) uma vez, no início da partida (antes da contagem de
	-- kickoff) — roster é { [nomeDoTime] = { {UserId=n, FieldCFrame=CFrame}, ... } }
	-- com a posição REAL de formação de cada jogador (a mesma que ele já
	-- vai ocupar no kickoff — ver getFormationCFrame em MatchController.lua)
	-- pra cada "boneco" da cutscene terminar exatamente onde o personagem
	-- de verdade dele está esperando, escondido (ver EntranceCutsceneClient
	-- .local.luau). duration é Config.ENTRANCE_CUTSCENE_DURATION.
	PlayEntranceCutscene = getOrCreateRemote(remotesFolder, "PlayEntranceCutscene"),
}

-- ===== CUTSCENE DE ENTRADA (⚠️ NOVO) =====
-- PEDIDO: "ela vai começar naqueles corredores de entrada ao estádio e os
-- dois times vão passar ao mesmo tempo um ao lado do outro, numa fila
-- tradicional, a ordem não importa, contanto que sejam do mesmo time, eles
-- vão andando em direção ao campo, e depois corta pra todo mundo dentro de
-- campo".
--
-- PARTS QUE VOCÊ PRECISA CRIAR NO STUDIO (Workspace, uma vez só — só
-- POSIÇÃO importa, pode deixar Size/rotação/aparência como quiser, dá até
-- pra deixar invisível/sem colisão, são só marcadores):
--   CutsceneTunnelStart_<NomeDoTime> — onde a FRENTE da fila desse time
--     começa (a ponta mais funda do túnel, longe do campo). Uma pra cada
--     time (mesmos nomes de Config.TEAM_NAMES, ex: "CutsceneTunnelStart_Azul",
--     "CutsceneTunnelStart_Amarelo"). As duas parts devem ficar LADO A
--     LADO (mesma distância do campo), pra dar a impressão de "um do lado
--     do outro" pedida.
--   CutsceneTunnelEnd_<NomeDoTime> — onde aquele MESMO time sai do túnel e
--     pisa no gramado (a boca do túnel). Mesma ideia, uma pra cada time,
--     lado a lado. A distância entre Start e End de cada time é o
--     "corredor" que a fila anda.
-- Sem essas Parts (ainda não criadas, ou nome errado), a cutscene
-- simplesmente não roda — a partida começa normal, sem travar nada, com um
-- aviso no console lembrando o nome exato que falta.
Config.CUTSCENE_TUNNEL_START_PREFIX = "CutsceneTunnelStart_"
Config.CUTSCENE_TUNNEL_END_PREFIX = "CutsceneTunnelEnd_"

Config.ENTRANCE_CUTSCENE_ENABLED = true -- true = joga a cutscene 1x no início de cada partida (antes da contagem de kickoff); false = pula direto pra contagem, igual antes
Config.ENTRANCE_CUTSCENE_QUEUE_SPACING = 6.5 -- ⚠️ v112: era 5 ("distancie eles um pouco mais") -- distância (studs) entre um jogador e o de trás dele na fila
-- ⚠️ NOVO: PEDIDO — "aumente um pouco a duração, deixe os personagens um
-- pouco mais lentos" — mesma distância (Start->End da Part), mais tempo
-- pra percorrer = anda mais devagar.
Config.ENTRANCE_CUTSCENE_TUNNEL_SECONDS = 6.5 -- era 4.5 — quanto tempo o PRIMEIRO da fila leva andando do Start até o End (dentro do túnel); quem vem atrás demora um pouco mais (mesma velocidade, mais distância pelo espaçamento da fila)
-- ⚠️ NOVO: PEDIDO — "sempre que colidirem com o end vão sumir, e serem
-- teleportados, assim que todos forem teleportados, a câmera sobe" — não
-- existe mais uma fase de "espalhar pro campo" fixa por tempo: cada
-- jogador anda reto até cruzar a Part End e é revelado ali mesmo (o
-- personagem de verdade já está esperando, parado, na posição de
-- formação certa — só ficava escondido). A câmera só sobe pro take aéreo
-- quando TODOS já tiverem cruzado o End (ver EntranceCutsceneClient,
-- remainingDummies) — não por um tempo fixo. Esse valor vira só uma
-- margem de segurança (caso algo trave, ex: personagem sumiu no meio).
Config.ENTRANCE_CUTSCENE_TUNNEL_SAFETY_SECONDS = 20
-- ⚠️ NOVO: PEDIDO — "coloque um take no final da animação, do campo por
-- cima, por uns 2 segundos" — dura isso depois que TODOS já cruzaram o
-- End (ver EntranceCutsceneClient.local.luau, finalOverheadCFrame).
-- PEDIDO v2: "faça a câmera de cima da cutscene durar mais 2 segundos"
-- — 2 (original) + 2 (pedido) = 4.
Config.ENTRANCE_CUTSCENE_OVERHEAD_SECONDS = 4
-- ⚠️ NOVO: PEDIDO — "vou colocar uma part pra você inserir a câmera nela
-- 'CutsceneAirCamera'" — Part opcional em Workspace: se existir, o take
-- aéreo final usa a CFrame DELA (posição e ângulo exatos que você montar
-- no Studio) em vez do enquadramento calculado automaticamente por cima
-- do campo. Sem essa Part, cai no cálculo automático de sempre — nada
-- quebra se você não criar ela.
Config.CUTSCENE_AIR_CAMERA_NAME = "CutsceneAirCamera"

-- ⚠️ v30 — ENCARAMENTO NO CÍRCULO CENTRAL (substituiu o take aéreo).
-- Depois que os dois times entram, eles se enfileiram nas bordas opostas do
-- círculo central, virados um pro outro. A câmera segura HOLD segundos de um
-- lado e CORTA 180° pro outro, como transmissão esportiva. Ver
-- montarEncaramento em EntranceCutsceneClient.local.luau.
-- (CUTSCENE_AIR_CAMERA_NAME acima não é mais lido — a Part pode ser apagada.)
Config.CUTSCENE_FACEOFF_HOLD_SECONDS = 2    -- tempo parado em CADA lado
Config.CUTSCENE_FACEOFF_RADIUS = 70 -- ⚠️ v112: 58 -> 70 (campo 20% maior)         -- raio do círculo central (⚠️ v104: campo 25% maior — medido: ~58.4; era 46)
Config.CUTSCENE_FACEOFF_SPACING = 5         -- distância entre um jogador e o próximo na fila (⚠️ v112: era 11 — a câmera de rosto passa de um pro outro)
Config.CUTSCENE_FACEOFF_CAMERA_DISTANCE = 42 -- o quanto a câmera fica ATRÁS da fila
Config.CUTSCENE_FACEOFF_CAMERA_HEIGHT = 13   -- altura da câmera
-- ⚠️ v33: o zoom lento em cima do time exibido. A câmera começa na posição
-- acima e termina ZOOM_DISTANCE studs mais perto e ZOOM_DROP mais baixa.
Config.CUTSCENE_FACEOFF_ZOOM_DISTANCE = 34 -- ⚠️ v34: era 16 — zoom mais intenso
Config.CUTSCENE_FACEOFF_ZOOM_DROP = 6  -- ⚠️ v34: era 3 — desce mais junto com a aproximação
-- ⚠️ v36 — PEDIDO: "cutscene precisa de mais zoom na câmera ainda. 50%
-- maior". Não dava pra continuar aumentando ZOOM_DISTANCE: a câmera já
-- termina o dolly a 54 studs do centro (RADIUS 46 + CAMERA_DISTANCE 42 −
-- ZOOM_DISTANCE 34) e a fila de jogadores está a 46 — mais 50% de
-- aproximação (51) enfiaria a câmera 9 studs À FRENTE do time. Então o
-- 50% vem de zoom de LENTE. O tamanho na tela é proporcional a
-- 1/tan(FOV/2): tan(70/2) = 0.700, e 0.700 / 1.5 = 0.467 → FOV = 50, que
-- é exatamente 1.5x maior. Vale SÓ no encaramento (o take do túnel
-- precisa do FOV aberto pra caber o corredor) e é restaurado no fim.
Config.CUTSCENE_FACEOFF_FOV = 50

-- ⚠️ v56 — ANIMAÇÃO DE CAMINHADA SÓ DA CUTSCENE.
-- PEDIDO: "a animação anterior de caminhada, eu só quero que ela esteja
-- presente na cutscene; essa nova aqui vai estar presente em todo o resto."
-- Esta é a ANTIGA, e vale exclusivamente pros bonecos que andam pelo túnel
-- na cutscene de entrada. O jogo inteiro (movimento normal) e o replay de
-- gol usam Config.ANIMATIONS.Walk, que agora tem a nova.
-- Deixar "" aqui faz a cutscene voltar a usar a mesma do resto do jogo.
Config.CUTSCENE_WALK_ANIMATION = "rbxassetid://89188098199704"
-- ⚠️ NOVO: PEDIDO — "todos os jogadores precisam passar pela câmera e não
-- sumir após chegar lá, faça a câmera um pouco mais pra frente" — a
-- câmera do túnel fica um pouco ANTES da Part End (não além dela, e mais
-- baixa/rasteira) — assim dá tempo de cada jogador passar visivelmente
-- pela frente da câmera antes de cruzar o End (que é só ali que ele
-- some/é revelado), em vez de sumir bem em cima da câmera.
Config.ENTRANCE_CUTSCENE_CAMERA_BEFORE_END = 6 -- studs antes do End
Config.ENTRANCE_CUTSCENE_CAMERA_HEIGHT = 6
-- ⚠️ NOVO: usado só pelo SERVIDOR (EntranceCutsceneController.lua) pra
-- saber quanto tempo esperar antes de liberar a contagem de kickoff — uma
-- ESTIMATIVA razoável (túnel + uma folga pra fila terminar de cruzar +
-- take aéreo), não o teto de segurança do cliente (esse é
-- TUNNEL_SAFETY_SECONDS, bem mais folgado de propósito, só pra nunca
-- travar o jogador preso na cutscene se algo der errado).
-- ⚠️ v112 — CUTSCENE DE ENTRADA REFEITA. PEDIDO: "tem que ser os players entrando,
-- vendo os dois times entrando em duas linhas retas; depois demonstrar os dois
-- times — tá muito longe, tem que dar mais zoom pra mostrar o rosto dos dois; e
-- eles não vão poder se mexer nem ativar a trava do shift enquanto tiver na
-- cutscene" + "o local de entrada já tá muito grande pro tamanho dos personagens".
-- FASE 1: as duas filas saem do túnel lado a lado e seguem reto pro gramado,
-- com a câmera na frente delas, recuando junto (plano fechado).
Config.ENTRADA_VELOCIDADE = 11          -- studs/s da caminhada das filas
Config.ENTRADA_INICIO_ANTES_DO_FIM = 38 -- a frente da fila começa isso antes da boca do túnel
Config.ENTRADA_ANDA_DEPOIS_DO_FIM = 26  -- e anda isso pelo gramado até a fase 2
Config.ENTRADA_DISTANCIA_ENTRE_FILAS = 10 -- as duas filas lado a lado (antes: 54 studs, uma em cada túnel) · "distancie eles um pouco mais" (era 7)
Config.ENTRADA_CAMERA_FRENTE = 13       -- câmera à frente da primeira dupla
Config.ENTRADA_CAMERA_ALTURA = 4.5
Config.ENTRADA_CAMERA_FOV = 60
-- FASE 2: cada time em fila no círculo central; a câmera passa rente, na altura do
-- rosto, de um jogador ao outro (um time, corta, o outro).
Config.ENTRADA_APRESENTACAO_SEGUNDOS = 2.5 -- por time
Config.ENTRADA_ROSTO_DISTANCIA = 7.5       -- câmera a isso na frente dos rostos
Config.ENTRADA_ROSTO_FOV = 40
Config.ENTRANCE_CUTSCENE_DURATION = (Config.ENTRADA_INICIO_ANTES_DO_FIM + Config.ENTRADA_ANDA_DEPOIS_DO_FIM) / Config.ENTRADA_VELOCIDADE
	+ Config.ENTRADA_APRESENTACAO_SEGUNDOS * 2 + 0.5

-- ============================================================
-- ELEMENTOS (reinserido a pedido do usuário — a versão antiga, puramente
-- cosmética, foi removida há um tempo; ver comentário em
-- PlayerDataManager.legacy.luau, "REMOVIDO"). Essa versão é NOVA e
-- diferente: os elementos vão realmente afetar Pulsos (existem "Pulsos
-- elementais", ex.: um Pulso de Vento, um de Fogo — ver campo Element em
-- PulseInstinctData.luau). Isso aqui é só a MATEMÁTICA/DADOS da
-- vantagem — o sistema de ROLL (sorteio de qual jogador/Pulso recebe
-- qual elemento) ainda não existe, fica por conta do usuário depois.
--
-- Regras exatas pedidas pelo usuário:
--   Void:      +20% de vantagem contra Natureza, Fogo e Vento;
--              -20% (fraco) contra Luz.
--   Luz:       +20% de vantagem contra Void; neutro (0%) contra
--              Natureza, Fogo e Vento.
--   Natureza:  fraca contra Fogo (-20%); forte contra Vento (+20%).
--   Fogo:      fraco contra Vento (-20%); forte contra Natureza (+20%).
--   Vento:     fraco contra Natureza (-20%); forte contra Fogo (+20%).
-- Ou seja: Natureza/Fogo/Vento formam um "pedra-papel-tesoura" entre si;
-- Void bate os três (menos Luz); Luz só bate Void (neutro no resto).
-- A vantagem é "tomada por clique no QTE" (pedido do usuário) — ou seja,
-- deve ser aplicada na resolução do QTE do Pulso (ver
-- PulseController.legacy.luau -> resolveAndExecute/applyPulsePowerScale),
-- multiplicando a força/potência do Pulso do atacante pelo elemento do
-- Pulso/jogador defensor, uma vez que ambos os lados tiverem elemento
-- definido pelo roll.
Config.ELEMENTS = { "Natureza", "Fogo", "Vento", "Luz", "Void" }

-- Nome do atributo (Instance:GetAttribute/SetAttribute) usado pra
-- guardar o elemento rolado de um jogador — convenção pronta pro futuro
-- sistema de roll usar; nada seta esse atributo ainda.
Config.ELEMENT_ATTRIBUTE_NAME = "Element"

-- attacker -> defender -> multiplicador. Combinação ausente = neutro
-- (1x) — só precisa registrar os casos de +20%/-20%; o resto (incluindo
-- elemento contra si mesmo) fica neutro automaticamente.
Config.ELEMENT_ADVANTAGE = {
	Void = { Natureza = 1.2, Fogo = 1.2, Vento = 1.2, Luz = 0.8 },
	Luz = { Void = 1.2 }, -- neutro (1x) contra Natureza/Fogo/Vento
	Natureza = { Fogo = 0.8, Vento = 1.2 },
	Fogo = { Vento = 0.8, Natureza = 1.2 },
	Vento = { Natureza = 0.8, Fogo = 1.2 },
}

-- Devolve o multiplicador de vantagem elemental de attackerElement
-- contra defenderElement. Sempre 1 (neutro) se qualquer um dos dois for
-- nil (nenhum roll feito ainda) ou não constar na tabela acima.
function Config.GetElementMultiplier(attackerElement, defenderElement)
	if not attackerElement or not defenderElement then return 1 end
	local row = Config.ELEMENT_ADVANTAGE[attackerElement]
	if not row then return 1 end
	return row[defenderElement] or 1
end

-- PEDIDO: "se o personagem tiver o elemento e usar skills do mesmo
-- elemento, ele tem vantagem de 10% de potência com esse elemento" — bônus
-- de "elemento igual" (independente da vantagem ATACANTE x DEFENSOR acima):
-- se o Pulso usado tem o MESMO elemento do personagem (Player:GetAttribute
-- (Config.ELEMENT_ATTRIBUTE_NAME), replicado do Lobby no teleport), a
-- potência dele sobe 10%.
Config.PULSE_ELEMENT_SELF_MATCH_MULT = 1.1

-- ⚠️ v107: multiplicador da DEFESA pelo elemento (antes GetElementMultiplier
-- existia mas ninguém chamava — o duelo ignorava elemento). Se o CHUTE tem
-- vantagem sobre a defesa (ex.: Galáxia/Luz contra Mão do Demônio/Void, 1.2),
-- a defesa tira 0.8x; se a DEFESA tem vantagem sobre o chute, tira 1.2x.
-- Sempre entre 0.8 e 1.2 (não soma os dois lados da mesma relação).
function Config.MultElementalDaDefesa(elementoChute, elementoDefesa)
	local contra = Config.GetElementMultiplier(elementoChute, elementoDefesa)
	if contra ~= 1 then return math.clamp(2 - contra, 0.8, 1.2) end
	return math.clamp(Config.GetElementMultiplier(elementoDefesa, elementoChute), 0.8, 1.2)
end

-- ============================================================
-- ARQUIBANCADA (torcida com os amigos do Roblox de cada cliente)
-- ============================================================
-- PEDIDO: "quero fazer uma arquibancada pra colocar os friends do
-- Roblox de cada cliente nele, como aparência... não tem uma forma
-- automática e menos lagada de fazer isso [em vez de posicionar cadeira
-- por cadeira, rig por rig, na mão]?"
--
-- COMO FUNCIONA (ver CrowdClient.local.luau, StarterPlayerScripts):
--   1) Você só precisa colocar/ancorar, na mão no Studio, UMA Part por
--      SEÇÃO de arquibancada (não uma por cadeira!), com o nome
--      começando em Config.CROWD_AREA_NAME_PREFIX (ex.: "CrowdArea_
--      Norte"). O tamanho dela (Size.X = largura, Size.Z = profundidade)
--      e a rotação (LookVector precisa apontar PRO CAMPO) definem toda
--      a seção — o script preenche um grid de "torcedores" sozinho.
--   2) 100% CLIENTE: cada jogador busca a PRÓPRIA lista de amigos
--      (Players:GetFriendsAsync) e a foto de cada um (thumbnail) e monta
--      a arquibancada só na tela dele — ninguém mais vê os mesmos
--      rostos que você vê. Isso é também o que torna leve: zero
--      replicação de rede extra pros outros jogadores, e cada torcedor
--      é só UMA Part achatada (sem física, sem Humanoid, sem rig, sem
--      animação, CanCollide/CanQuery/CanTouch desligados, CastShadow
--      desligado) com uma Decal da foto colada na frente — MUITO mais
--      barato que um rig completo por cadeira.
--   3) Faltou amigo pra preencher todo mundo? O resto vira uma cor sólida
--      genérica (Config.CROWD_FALLBACK_COLORS, sem custo de rede
--      nenhum) em vez de ficar vazio ou travar tentando buscar gente que
--      não existe.
Config.CROWD_AREA_NAME_PREFIX = "CrowdArea" -- Parts em workspace com nome começando assim viram arquibancada
-- ⚠️ PEDIDO: "faça todos os npcs nascerem mais separados, o dobro da
-- distância atual" — dobrado (3 -> 6, 3.2 -> 6.4).
Config.CROWD_SEAT_WIDTH = 13    -- studs entre um torcedor e o próximo (colunas, ao longo do Size.X da Part)
-- ⚠️ v104: campo 25% maior — os degraus das arquibancadas (workspace.Arquibancadas,
-- só no Studio) ficaram 25% mais fundos: 7 -> 8.75. TEM que bater com o degrau.
Config.CROWD_ROW_DEPTH = 10.5 -- ⚠️ v112: 8.75 x 1.2 (degraus 20% mais fundos com o campo)   -- studs entre uma fileira e a próxima (linhas, ao longo do Size.Z da Part)
Config.CROWD_ROW_RISE = 4.5    -- quanto cada fileira sobe em Y (efeito "degrau" de arquibancada de verdade)

-- ⚠️ v30: quanto o torcedor recua DENTRO da própria fileira, pra ficar em
-- cima do banco em vez de em pé na frente dele (ver basePosition em
-- CrowdClient.local.luau). Tem que acompanhar onde o banco foi construído
-- na geometria das arquibancadas: hoje o banco está a 0.78 da profundidade
-- da fileira, ou seja 7 * 0.78 = 5.46.
Config.CROWD_SEAT_BACK_OFFSET = 7.65 -- ⚠️ v112: 6.375 x 1.2 -- ⚠️ v104: 5.1 * 1.25 (campo/arquibancada 25% maiores)
-- ⚠️ PEDIDO: "pode preencher o espaço da crowd toda, a arquibancada é a
-- area selecionada, não tem problema, se estiver travando, a gente
-- remove" — com isso true, CROWD_MAX_SEATS_PER_AREA (mais abaixo) é
-- IGNORADO e a área é preenchida por inteiro. Se der lag, é só voltar
-- pra false (populateArea volta a reduzir proporcionalmente pro teto).
Config.CROWD_FILL_ENTIRE_AREA = true
-- ⚠️ PEDIDO: "não põe toda, deixa algumas lacunas, como se algumas
-- pessoas não tivessem ido... deixa a grande maioria... causa uma
-- impressão de aleatório, toda vez que entra" — chance de CADA assento
-- ficar vazio. Rola de novo toda vez que a arquibancada é montada (cada
-- sessão de Play), então o padrão de lacunas muda a cada entrada.
-- v3 — PEDIDO: "coloca 50% da crowd vazia" (era 0.25 = 25%, antes disso
-- 0.12 = 12%). v4 — PEDIDO: "diminua mais ainda a crowd" — 0.5 -> 0.7
-- (70% de CADA assento fica vazio agora).
Config.CROWD_EMPTY_SEAT_CHANCE = 0.85

-- ⚠️ NOVO: PEDIDO — "faça uma arquibancada simples gerar atrás deles, de
-- forma que seja como se eles estivessem em pé" — um degrau (Part) por
-- fileira, subindo em escada igual Config.CROWD_ROW_RISE, 100% gerado por
-- código (ver createBleacherStep em CrowdClient.local.luau) — não precisa
-- criar nada no Studio pra isso. Se travar demais, ponha false aqui.
Config.CROWD_BLEACHER_ENABLED = false
Config.CROWD_BLEACHER_COLOR = Color3.fromRGB(120, 120, 130)
Config.CROWD_BLEACHER_MATERIAL = Enum.Material.Concrete
Config.CROWD_MAX_FRIENDS_TO_FETCH = 60 -- teto de amigos buscados por jogador (evita travar puxando páginas demais de quem tem milhares)
Config.CROWD_THUMBNAILS_IN_FLIGHT = 4  -- quantos pedidos de foto ficam "em voo" ao mesmo tempo (evita throttle/hitch da API de thumbnail)
Config.CROWD_FALLBACK_COLORS = {
	Color3.fromRGB(180, 60, 60), Color3.fromRGB(60, 120, 180), Color3.fromRGB(60, 160, 90),
	Color3.fromRGB(200, 180, 60), Color3.fromRGB(140, 80, 180), Color3.fromRGB(220, 140, 60),
}

-- ⚠️ v2 — PEDIDO: "eu quero humanoid, vamos fazer o teste com os
-- personagens de verdade, porque eu quero colocar animações neles"
-- (comemoração de gol). Trocou de cutouts achatados (Parts) pra clones
-- de um Model/Humanoid de verdade — só assim dá pra tocar a animação de
-- Config.ANIMATIONS.GoalCelebration (a mesma usada no jogador que marca
-- o gol) na torcida inteira quando um gol acontece.
--
-- VOCÊ PRECISA CRIAR NO STUDIO (manual, uma vez só): um Model chamado
-- Config.CROWD_DUMMY_TEMPLATE_NAME, com um Humanoid (R6 ou R15) dentro,
-- parado em ReplicatedStorage (ou em qualquer lugar — o script procura
-- por esse nome em workspace/ReplicatedStorage). Sem ele, a arquibancada
-- simplesmente não aparece (avisa uma vez no console, sem travar nada).
--
-- Rig de verdade é MAIS PESADO que os cutouts antigos — por isso o teto
-- de torcedores por área caiu bastante (300 -> 80). Se sentir travamento
-- com muita gente, reduza ainda mais esse número ou o tamanho das Parts
-- CrowdArea_....
Config.CROWD_DUMMY_TEMPLATE_NAME = "CrowdDummyTemplate"

-- ⚠️ v13 (ver stripAvatarIdentity em CrowdClient.local.luau): todo torcedor
-- é criado SEM os acessórios/roupas que vieram no Model-template, porque o
-- template foi montado a partir de um personagem real e estava espalhando o
-- cabelo e as roupas daquela conta pela arquibancada inteira.
-- Se quiser vestir a torcida com um uniforme, cole aqui os ids das roupas
-- ("rbxassetid://123..."). Vazio = corpo limpo do template.
Config.CROWD_SHIRT_ID = ""
Config.CROWD_PANTS_ID = ""
-- Só entra em ação se Config.CROWD_FILL_ENTIRE_AREA = false (ver acima) —
-- por pedido do usuário, o padrão agora é preencher a área toda.
Config.CROWD_MAX_SEATS_PER_AREA = 80

-- ⚠️ v112 — PEDIDO: "no replay, só no primeiro gol aparece a Hissatsu, depois não
-- aparece mais nenhuma, nem arma, nem algumas animações". Os efeitos de Arma
-- (ArmaVFX) e de Hissatsu de drible/carrinho (HissatsuVFX) iam direto pros
-- clientes e NUNCA eram gravados no replay. Todo disparo desses passa por aqui:
-- manda pra todo mundo E grava o evento (o replay repete no fantasma). Só o
-- servidor chama (o RegistrarEventoReplay mora no BallController).
Config.DispararVFX = function(nomeRemoto, character, ...)
	local remoto = Config.Remotes and Config.Remotes[nomeRemoto]
	if not remoto then return end
	remoto:FireAllClients(character, ...)
	if _G.RegistrarEventoReplay and _G.IdDoAtorReplay then
		local ator = _G.IdDoAtorReplay(character)
		if ator then
			-- argumentos com chave em texto: lista com buraco (nil no meio) não
			-- atravessa o RemoteEvent inteira
			local n = select("#", ...)
			local args = {}
			for i = 1, n do args[tostring(i)] = (select(i, ...)) end
			_G.RegistrarEventoReplay("VFX", { ator = ator, remoto = nomeRemoto, args = args, n = n })
		end
	end
end

return Config
