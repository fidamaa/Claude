--[[
	PlayerSystems (Script)
	LOCAL: ServerScriptService

	Junta em um script só tudo que antes estava espalhado em ~6 scripts:
	- Stamina (Fôlego) + velocidade de corrida (⚠️ NOVO: sem sprint — ver getRunSpeed)
	- Grupos de colisão (jogadores não colidem com a bola, nem entre si)
	- Highlight por time
	- Troca de time (RequestTeamChange)
	- Log de entrada / dados de teleporte

	FIX: o BallController controla WalkSpeed durante stun (fintas/carrinho
	mal cronometrado/cobranças de bola parada). Sem a checagem abaixo, essa
	seção de sprint sobrescrevia o WalkSpeed=0 do stun assim que o jogador
	apertasse Shift, quebrando o stun. Agora ela ignora pedidos de sprint
	enquanto _G.IsPlayerStunned(player) for verdadeiro.

	Control Lock (Ctrl) NÃO existe neste script — é um Shift Lock 100%
	client-side (câmera livre + personagem virado pra câmera), tratado
	inteiro no FootballClient.lua. Não tem remote, não tem Attribute, não
	mexe em WalkSpeed nem em nada aqui.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Teams = game:GetService("Teams")

local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("FootballConfig"))
-- ⚠️ v65: usado pra saber se o jogador está sendo goleiro DE VERDADE
-- (dentro da própria área) e escolher a animação de parado certa.
local GKAreaUtil = require(game:GetService("ReplicatedStorage"):WaitForChild("GKAreaUtil"))
local Remotes = Config.Remotes

-- ===== HUD DE HABILIDADES: pulsos/instinto equipados (ver AbilityHUD.
-- local.luau) =====
-- Simples pass-through pros getters já expostos pelo PulseController.lua
-- (_G.GetEquippedPulse) e InstinctController.lua (_G.GetEquippedInstinct)
-- — juntos aqui só porque PlayerSystems é o script "central" de ciclo de
-- vida do jogador; a ordem de carregamento dos outros dois não importa,
-- já que isso só executa quando o CLIENTE pede (bem depois de tudo já
-- ter carregado).
-- ⚠️ v76: Pulse3 (Hissatsu extra, Robux) + Instinct1/2/3 (Arma virou
-- lista — ver SetPlayerInstincts/GetEquippedInstincts em
-- InstinctController.legacy.luau) no lugar do "Instinct" singular.
Remotes.GetMyAbilities.OnServerInvoke = function(player)
	local instintos = (_G.GetEquippedInstincts and _G.GetEquippedInstincts(player)) or {}
	return {
		Pulse1 = _G.GetEquippedPulse and _G.GetEquippedPulse(player, 1),
		Pulse2 = _G.GetEquippedPulse and _G.GetEquippedPulse(player, 2),
		Pulse3 = _G.GetEquippedPulse and _G.GetEquippedPulse(player, 3),
		Instinct1 = instintos[1],
		Instinct2 = instintos[2],
		Instinct3 = instintos[3],
	}
end

-- ===== SPAWN PRÓPRIO (sem SpawnLocation no Studio) =====
-- Time/Role só ficam definidos DEPOIS de TeleportData ser lido (ver
-- onPlayerAdded abaixo) — se o Roblox spawnasse o personagem sozinho
-- (comportamento padrão), o CharacterAdded podia disparar ANTES do time
-- estar pronto, e o MatchController não saberia em que posição de
-- formação colocar o jogador. Por isso o auto-load fica desligado: quem
-- chama player:LoadCharacter() é o fim do onPlayerAdded, só depois do
-- Team/Role já estarem certos — o MatchController.lua então posiciona
-- cada um no lugar certo (ver _G.PositionPlayerAtFormation) assim que o
-- CharacterAdded dispara, sem precisar de nenhuma SpawnLocation na cena.
Players.CharacterAutoLoads = false

-- Como o auto-load está desligado, também preciso respawnar manualmente
-- depois de morrer (RESPAWN_DELAY segundos, igual o padrão do Roblox).
local RESPAWN_DELAY = 5

-- ===== GRUPOS DE COLISÃO =====
-- FIX: movido pra FootballConfig.lua — o BallController.lua já usava o
-- grupo "Bola" antes deste script (PlayerSystems) chegar a registrá-lo,
-- por causa da ordem de carregamento dos Scripts em ServerScriptService.
-- Ver comentário no FootballConfig.lua. Registro fica lá agora, garantido
-- pelo require(Config) que todo script já faz no topo.

local function applyCollisionGroup(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
	character.DescendantAdded:Connect(function(part)
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end)
end

local function isStunned(player)
	return _G.IsPlayerStunned ~= nil and _G.IsPlayerStunned(player) or false
end

-- ⚠️ FIX (cobrador de escanteio/lateral se movendo livre): mesma ideia do
-- isStunned acima, só que pro freeze de bola parada do OutOfBoundsController
-- (_G.IsSetPieceFrozen) — sem isso, o Heartbeat de sprint abaixo e o
-- handler de UpdateKickCharging (que dispara toda vez que o cobrador
-- carrega o próprio chute da cobrança!) reescreviam o WalkSpeed=0 do
-- freeze de volta pro normal, e o "preso no lugar" durava literalmente
-- só até o cobrador tentar cobrar.
local function isFrozenForSetPiece(player)
	return _G.IsSetPieceFrozen ~= nil and _G.IsSetPieceFrozen(player) or false
end

-- ⚠️ v9 FIX: "ainda usando os pulsos eu conseguia me mover" — mesma ideia
-- de isStunned/isFrozenForSetPiece, só que pro freeze de movimento da
-- Hissatsu de goleiro/Grande Muralha (_G.IsPulseFrozen, ver freezeMovement
-- em PulseController.legacy.luau). Sem isso, o Heartbeat de sprint abaixo
-- reescrevia o WalkSpeed=0 do freeze de volta pro normal no frame seguinte.
local function isPulseFrozen(player)
	return _G.IsPulseFrozen ~= nil and _G.IsPulseFrozen(player) or false
end

-- ===== ATRIBUTOS QUE AFETAM MOVIMENTO/CORPO =====
-- Velocidade (Speed): multiplica RUN_SPEED (⚠️ NOVO: única velocidade — sem sprint). No default
-- (50) o multiplicador é 1.0x — ninguém que nunca mexeu no atributo
-- sente diferença nenhuma.
local function getSpeedMultiplier(player)
	local value = player:GetAttribute(Config.SPEED_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_SPEED end
	local fraction = math.clamp(value, 0, 100) / 100
	return Config.SPEED_MULTIPLIER_MIN + (Config.SPEED_MULTIPLIER_MAX - Config.SPEED_MULTIPLIER_MIN) * fraction
end

-- Multiplicador extra de Pulso/Instinto (ex: Pulso da Arrancada,
-- Instinto de Corredor) — 1 se nenhum dos dois está ativo. Vem do
-- PulseController.lua/InstinctController.lua (_G.*), que só existem
-- depois que esses scripts carregam — por isso o "and" defensivo.
local function getAbilitySpeedMultiplier(player)
	local mult = 1
	if _G.GetPulseSpeedMultiplier then mult *= _G.GetPulseSpeedMultiplier(player) end
	if _G.GetInstinctSpeedMultiplier then mult *= _G.GetInstinctSpeedMultiplier(player) end
	if _G.GetInstinctAllBoost then mult *= (1 + _G.GetInstinctAllBoost(player)) end
	-- ⚠️ v5.6: chegou a existir aqui um multiplicador extra pra quem tem
	-- Role=="GK" (pedido de dobrar a velocidade do goleiro). ⚠️ v5.7:
	-- REMOVIDO — o usuário esclareceu que o pedido era sobre o GKBOT (a
	-- IA que substitui o goleiro vazio), não o jogador HUMANO com
	-- Role="GK" — ver Config.GKBOT_WALK_SPEED em GKBotController.legacy.
	-- luau, que é onde esse ajuste vive agora.
	return mult
end

-- Enquanto carrega o chute (segurando o botão), anda mais devagar — o
-- "pé de apoio plantado" carregando força (ver Remotes.UpdateKickCharging
-- abaixo, mesma ideia do UpdateSprinting).
local charging = {} -- [player] = bool
local function getChargeMultiplier(player)
	return charging[player] and Config.KICK_CHARGE_WALK_SPEED_MULT or 1
end

-- ⚠️ v17 — PEDIDO: "coloca uma desvantagem: quem tá com a bola fica um
-- pouco mais lento, 10%. Porque aí equilibra mais o jogo — se o melhor
-- jogador tiver com a bola e for muito rápido, os outros ainda conseguem
-- acompanhar ele."
--
-- Vale pra TODO MUNDO que estiver conduzindo, sem exceção de atributo: é
-- justamente o jogador com Speed alto que precisava de um freio, porque o
-- bônus de atributo dele multiplicava em cima de uma corrida que já era
-- livre. Como é multiplicador, quem é mais rápido continua mais rápido —
-- só deixa de ser inalcançável.
local function getPossessionMultiplier(player)
	if _G.GetBallOwner and _G.GetBallOwner() == player then
		return Config.BALL_CARRIER_SPEED_MULT
	end
	return 1
end

-- ⚠️ NOVO — SEM SPRINT. PEDIDO: "Não haverá botão de corrida/sprint. O
-- personagem deve correr normalmente usando WASD, e sua velocidade será
-- determinada pelo atributo Velocidade." Antes eram duas velocidades
-- (getNormalSpeed andando, getSprintSpeed segurando Shift); agora existe
-- UMA só, Config.RUN_SPEED x Velocidade — com os mesmos multiplicadores de
-- Hissatsu/Arma, carga de chute e freio de quem está com a bola.
local function getRunSpeed(player)
	return Config.RUN_SPEED * getSpeedMultiplier(player) * getAbilitySpeedMultiplier(player) * getChargeMultiplier(player) * getPossessionMultiplier(player)
end

-- Físico (Physical): escala o corpo do personagem (R15 BodyScale) — é
-- isso que aumenta o hitbox de verdade, já que a geometria de colisão
-- escala junto com o corpo. Reservado também pro sistema futuro de bola
-- batendo no corpo (Config.PHYSICAL_ATTRIBUTE, ver FootballConfig.lua).
local function applyPhysicalScale(player, character)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local value = player:GetAttribute(Config.PHYSICAL_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_PHYSICAL end
	local fraction = math.clamp(value, 0, 100) / 100

	local bodyScale = Config.PHYSICAL_SCALE_MIN + (Config.PHYSICAL_SCALE_MAX - Config.PHYSICAL_SCALE_MIN) * fraction
	local heightScale = Config.PHYSICAL_HEIGHT_SCALE_MIN + (Config.PHYSICAL_HEIGHT_SCALE_MAX - Config.PHYSICAL_HEIGHT_SCALE_MIN) * fraction

	-- BodyWidthScale/BodyDepthScale/BodyHeightScale só existem em rigs
	-- R15 com escala habilitada — pcall porque um rig R6 (ou R15 sem
	-- essas NumberValues) não tem esses filhos, e isso não pode quebrar
	-- o resto do setup do personagem.
	pcall(function()
		local widthScale = humanoid:FindFirstChild("BodyWidthScale")
		local depthScale = humanoid:FindFirstChild("BodyDepthScale")
		local heightScaleValue = humanoid:FindFirstChild("BodyHeightScale")

		if widthScale then widthScale.Value = bodyScale end
		if depthScale then depthScale.Value = bodyScale end
		if heightScaleValue then heightScaleValue.Value = heightScale end
	end)
end

-- ===== STAMINA (FÔLEGO) =====
local runStartedAt = {} -- [player] = os.clock() de quando começou a se mover (ver GetSecondsSinceSprintStart)
-- ⚠️ NOVO: sem sprint, o Fôlego não drena mais correndo — só as AÇÕES
-- físicas gastam (finta, cabeçada, carrinho, via Config.SpendStamina), e o
-- MaxStamina (54 + Fôlego x 10) decide quantas dá pra encadear antes de
-- precisar esperar a recuperação.

-- [Player] = snapshot dos atributos do personagem ativo do roster
-- (Physical/DribbleSkill/Speed/Kick/Energy/Technique/Stamina),
-- recebido via TeleportData.Characters quando o jogador chega pelo
-- matchmaking do place Lobby (ver Matchmaker.lua de lá). Substitui a
-- tentativa antiga de chamar _G.GetPlayerData aqui — esse global só
-- existe no place Lobby, nunca existiu de verdade aqui no Game (cada
-- place roda em servers separados, _G não atravessa teleporte).
local characterSnapshots = {}

local function setupStatValues(player)
	if not player:FindFirstChild("Stamina") then
		Instance.new("NumberValue", player).Name = "Stamina"
	end
	if not player:FindFirstChild("MaxStamina") then
		Instance.new("NumberValue", player).Name = "MaxStamina"
	end
	if not player:FindFirstChild("IsExhausted") then
		Instance.new("BoolValue", player).Name = "IsExhausted"
	end
	charging[player] = false
end

RunService.Heartbeat:Connect(function(deltaTime)
	for _, player in ipairs(Players:GetPlayers()) do
		local stamina = player:FindFirstChild("Stamina")
		local maxStamina = player:FindFirstChild("MaxStamina")
		local exhausted = player:FindFirstChild("IsExhausted")
		if not (stamina and maxStamina and exhausted) then continue end

		-- Bônus de Pulso/Instinto na regeneração de stamina (ex: Pulso da
		-- Fôlego Tático, Instinto de Fôlego Final) — só afeta REGENERAÇÃO,
		-- não o gasto das ações.
		local regenMult = 1
		if _G.GetPulseStaminaRegenMultiplier then regenMult *= _G.GetPulseStaminaRegenMultiplier(player) end
		if _G.GetInstinctStaminaRegenMultiplier then regenMult *= _G.GetInstinctStaminaRegenMultiplier(player) end

		-- Refresca o WalkSpeed a cada frame com os multiplicadores de
		-- Pulso/Instinto em dia (eles ligam/desligam sozinhos com o tempo)
		-- — nunca durante stun (o BallController é quem manda no WalkSpeed
		-- nesse caso).
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid and not isStunned(player) and not isFrozenForSetPiece(player) and not isPulseFrozen(player) then
			humanoid.WalkSpeed = getRunSpeed(player)
		end

		-- ⚠️ NOVO: "arranque" (Arma Pique, MaxSecondsAfterSprintStart) agora
		-- conta a partir de quando o jogador COMEÇA A SE MOVER (WASD), já
		-- que não existe mais tecla de sprint pra marcar esse instante.
		local moving = humanoid ~= nil and humanoid.MoveDirection.Magnitude > 0.1
		if moving and not runStartedAt[player] then
			runStartedAt[player] = os.clock()
		elseif not moving then
			runStartedAt[player] = nil
		end

		if exhausted.Value then
			stamina.Value = math.min(maxStamina.Value, stamina.Value + Config.EXHAUSTED_RECOVERY_RATE * deltaTime)
		else
			stamina.Value = math.min(maxStamina.Value, stamina.Value + Config.RECOVERY_RATE * regenMult * deltaTime)
		end
	end
end)

-- ⚠️ v5.2: quando cada jogador COMEÇOU a correr. A Arma "Pique" só vale
-- no arranque (primeiros segundos da corrida). ⚠️ NOVO: sem sprint, o
-- arranque é o instante em que ele começa a se mover com WASD (marcado no
-- Heartbeat acima, em runStartedAt). O Remote UpdateSprinting continua
-- existindo em FootballConfig.Remotes, mas nenhum cliente dispara mais e
-- o servidor não escuta — não existe tecla de corrida.
_G.GetSecondsSinceSprintStart = function(player)
	local t = runStartedAt[player]
	if not t then return math.huge end -- parado
	return os.clock() - t
end

-- Segurando o botão de chute (carregando força) → anda mais devagar. O
-- valor exato de WalkSpeed é sempre refrescado pelo heartbeat acima (que
-- já lê getChargeMultiplier), então aqui só precisa atualizar o estado e
-- aplicar na hora (pra não esperar até o próximo frame do heartbeat).
Remotes.UpdateKickCharging.OnServerEvent:Connect(function(player, isChargingNow)
	charging[player] = isChargingNow and true or false
	-- ⚠️ FIX: é EXATAMENTE esse handler que disparava toda vez que o
	-- cobrador de escanteio/lateral carregava o próprio chute da cobrança
	-- — sem o isFrozenForSetPiece aqui, o WalkSpeed=0 do freeze virava
	-- WalkSpeed normal na hora, e o cobrador saía andando livre.
	if isStunned(player) or isFrozenForSetPiece(player) or isPulseFrozen(player) then return end

	local character = player.Character
	if character and character:FindFirstChild("Humanoid") then
		character.Humanoid.WalkSpeed = getRunSpeed(player)
	end
end)

-- Consumir stamina de forma genérica (usado pelo BallController também)
Config.SpendStamina = function(player, amount)
	local stamina = player:FindFirstChild("Stamina")
	if not stamina or stamina.Value < amount then return false end
	stamina.Value -= amount
	return true
end

-- ===== HIGHLIGHT POR TIME =====
local function updateHighlight(player, character)
	if not character then return end
	local highlight = character:FindFirstChild("TeamHighlight")
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "TeamHighlight"
		highlight.Adornee = character
		highlight.Parent = character
	end

	-- ⚠️ v45 — PEDIDO: "ele não devia ficar da cor do time. Ele tá da cor do
	-- time, muda praticamente todo o revestimento do personagem. Mantém ele
	-- na cor normal, só coloca ele destacado em volta com a cor amarela."
	--
	-- FillTransparency = 1 é o que faz o CORPO aparecer com as cores/roupas
	-- de verdade: o preenchimento do Highlight some por completo e sobra só
	-- o contorno. Antes era 0.7, que ainda lavava o personagem inteiro na
	-- cor do time. O contorno agora é sempre amarelo, igual pros dois times
	-- — quem diz o time é o uniforme, não o brilho.
	-- ⚠️ v47 — PEDIDO: "ele tá com os dois highlights na cor amarela. O azul
	-- tem que ser azul, o amarelo tem que ser amarelo. E deixa ele um pouco
	-- mais FINO."
	--
	-- A cor volta a ser a do time (o v45 tinha unificado em amarelo — foi
	-- longe demais: o pedido de lá era só parar de PINTAR O CORPO, não
	-- apagar a identidade de time do contorno).
	--
	-- Sobre "mais fino": Highlight NÃO tem propriedade de espessura no
	-- Roblox — não existe OutlineWidth. O que dá pra controlar é o PESO
	-- VISUAL do traço, e é o que está feito aqui:
	--   - DepthMode Occluded (o padrão do Highlight é AlwaysOnTop): o
	--     contorno deixa de ser desenhado por cima de tudo e passa a
	--     respeitar o que está na frente. É o que mais muda — AlwaysOnTop dá
	--     aquele traço pesado que "vaza" por cima da geometria.
	--   - Um pouco de OutlineTransparency, que suaviza a borda e faz ela ler
	--     como um fio em vez de uma faixa.
	-- FillTransparency continua em 1: o corpo segue sem ser pintado, que é o
	-- que deixa o uniforme aparecer (e você vai colocar uniforme depois).
	if player.TeamColor then
		highlight.Enabled = true
		highlight.FillTransparency = 1
		highlight.OutlineColor = player.TeamColor.Color
		highlight.OutlineTransparency = Config.HIGHLIGHT_OUTLINE_TRANSPARENCY
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	else
		highlight.Enabled = false
	end
end

-- ⚠️ FIX: o som de passos/pulo (Config.SOUNDS.Footstep/Jump) NÃO dá pra
-- silenciar daqui (SERVIDOR) — descoberto depois que o usuário testou e
-- o som continuou tocando normal. Motivo: os sons "Running"/"Jumping"
-- são criados em TEMPO DE EXECUÇÃO pelo próprio código do Animate
-- (LocalScript que roda dentro do personagem), e um LocalScript só
-- executa no(s) CLIENTE(S) que estão vendo aquele personagem — cada
-- Sound que ele cria (Instance.new("Sound")) fica só na cópia local
-- daquele cliente, nunca chega no servidor (bem diferente de uma Part,
-- que É replicada normalmente). Um script no ServerScriptService jamais
-- vai encontrar esses Sound via WaitForChild, por mais tempo que espere.
-- A correção de verdade agora mora em StarterPlayerScripts/
-- MovementSoundsClient.local.luau (roda no CLIENTE, pra TODO personagem
-- que ele consegue ver — o dele e o de todo mundo — porque é assim que
-- cada Sound realmente existe: uma cópia local por espectador).

-- ===== ANIMAÇÕES DE MOVIMENTO (PEDIDO: "eu quero colocar animação de
-- andar, correr, pular, etc...") =====
-- ⚠️ v2 — PEDIDO: "agora a animação voltou para a antiga... a nova
-- animação de andar ainda não é aplicada". Causa raiz da v1 (mutar
-- Animate.walk.WalkAnim.AnimationId direto): o "Animate" do personagem é
-- um LocalScript que roda por CLIENTE que está vendo (já documentado
-- acima pro som) — e ele só LÊ o AnimationId de cada pasta UMA VEZ, bem
-- no início (função configureAnimationSet, monta sua lista interna de
-- animações e nunca mais relê depois). Se o nosso Script do servidor
-- mudar o valor DEPOIS que o Animate de um cliente específico já leu
-- (corrida — pode acontecer com uns, não com outros, dependendo de quem
-- carregou o personagem primeiro), aquele cliente specific nunca vê a
-- troca — daí "às vezes funciona, às vezes volta pra antiga".
--
-- Fix de verdade: para de mexer no Animate (ele fica INTOCADO, sempre com
-- a animação padrão do Roblox — o que também deixa a "animação antiga"
-- disponível pra cutscene reusar, ver findDefaultWalkAnimationId em
-- EntranceCutsceneClient.local.luau) e toca a NOSSA animação por cima
-- via Animator:LoadAnimation com prioridade Action (SEMPRE visualmente
-- por cima da Movement/Core que o Animate usa) — mesmo método já usado
-- (e comprovadamente funcionando) pra Tackle/Dribble/GoalCelebration.
-- Isso roda 100% no SERVIDOR e replica normal (LoadAnimation+Play sempre
-- replicou bem nesse projeto, só o SOM que não).
-- ⚠️ v65: GKIdle entra na lista pra ser CARREGADA junto (ela é só mais uma
-- animação parada), mas quem decide qual das duas idles tocar é
-- refreshMoveTrack lá embaixo — ver o comentário lá.
local MOVEMENT_ANIMATIONS = { "Idle", "Walk", "Run", "Jump", "Fall", "GKIdle" }

-- Acima de qual WalkSpeed usar a animação de CORRER em vez de ANDAR —
-- ponto médio entre NORMAL_SPEED e SPRINT_SPEED (22 e 38 por padrão).
local RUN_ANIMATION_MIN_SPEED = (Config.NORMAL_SPEED + Config.SPRINT_SPEED) / 2

local function overrideMovementAnimations(character)
	-- ⚠️ v96: com a animação por código ligada, andar/correr/parado/pulo são
	-- do AnimadorProcedural (cliente) — tocar estas tracks aqui era uma das
	-- três fontes que se embolavam no mesmo corpo.
	if Config.ANIMACAO_PROCEDURAL then return end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks = {} -- [configKey] = AnimationTrack | nil (nil = "" no Config, mantém o padrão pra esse estado)
	for _, configKey in ipairs(MOVEMENT_ANIMATIONS) do
		local animationId = Config.NormalizeAnimationId(Config.ANIMATIONS[configKey])
		if animationId and animationId ~= "" then
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			if ok and track then
				-- ⚠️ v62 — PEDIDO: "durante a animação de chute, nenhuma animação
				-- pode interromper ela. Você ainda vai conseguir ANDAR chutando,
				-- mas a animação de andar não vai rolar enquanto a de chute
				-- estiver acontecendo."
				--
				-- Isso é exatamente pra que serve a PRIORIDADE do Roblox, e o
				-- erro era estar tudo no MESMO nível: andar/correr estavam em
				-- Action, igual chute e carrinho, então as duas tocavam juntas e
				-- quem entrasse por último ganhava.
				--
				-- A ordem do Roblox, de baixo pra cima:
				--    Core < Idle < Movement < Action < Action2 < Action3 < Action4
				--
				-- Movimento é o piso (Movement): o jogador continua ANDANDO
				-- normalmente — isso é física, não animação —, só que a animação
				-- de andar fica escondida enquanto houver qualquer ação por cima.
				track.Priority = Enum.AnimationPriority.Movement
				track.Looped = configKey ~= "Jump" -- pulo toca uma vez só, o resto em loop
				tracks[configKey] = track
			end
		end
	end

	if not next(tracks) then return end -- nenhuma animação custom configurada — não faz nada (Animate padrão continua)

	-- ⚠️ v61 — PEDIDO: "na troca do idle pro andar tem um delayzinho; ele só
	-- começa a tocar a animação de andar uns 0.3s depois. A animação de andar
	-- não pode ter idle: ela tem que PARAR no momento que você resolve parar,
	-- e aí faz uma transiçãozinha pro idle."
	--
	-- Dois tempos de fade em vez de um só. Entrar no movimento é quase seco
	-- (o pé tem que sair junto com a tecla); voltar pro idle é que ganha a
	-- transição suave. Antes os dois eram 0.15, o que somava atraso justo na
	-- partida, que é onde incomoda.
	local currentTrack = nil
	local function playTrack(track)
		if track == currentTrack then return end
		local indoProIdle = (track == tracks.Idle)
		if currentTrack then
			currentTrack:Stop(indoProIdle and Config.MOVEMENT_FADE_TO_IDLE or Config.MOVEMENT_FADE_TO_MOVE)
		end
		currentTrack = track
		if track then
			track:Play(indoProIdle and Config.MOVEMENT_FADE_TO_IDLE or Config.MOVEMENT_FADE_TO_MOVE)
		end
	end

	-- Mesma lógica que o Animate padrão do Roblox usa (Running/Jumping/
	-- FreeFalling), só que tocando NOSSAS animações em vez de mexer nas
	-- dele — pulo/queda sempre têm prioridade sobre andar/correr.
	local isJumping = false
	local isFalling = false

	-- ⚠️ v19 — PEDIDO: "coloca que ela escala com a velocidade, e coloca ela
	-- pra ser um pouco mais rápida como velocidade base."
	--
	-- A animação foi feita num ritmo fixo; sem isso o boneco faz os MESMOS
	-- passos andando devagar e em sprint, e parece que ele patina no chão.
	-- AdjustSpeed muda a taxa de reprodução do track: a referência é
	-- Config.NORMAL_SPEED (andar normal = o ritmo base), e a partir daí a
	-- animação acelera/desacelera junto com o WalkSpeed real — que já leva
	-- atributo de Speed, Hissatsu, Arma e o freio de quem está com a bola.
	-- O clamp evita os dois extremos feios: câmera lenta quando quase
	-- parado, e pernas em liquidificador num buff grande.
	local function refreshTrackSpeed(track, speed)
		if not track then return end
		local reference = Config.NORMAL_SPEED
		if not reference or reference <= 0 then reference = 22 end
		local rate = (speed and speed > 0.5) and (speed / reference) or 1
		rate *= Config.MOVEMENT_ANIMATION_BASE_RATE
		track:AdjustSpeed(math.clamp(rate, Config.MOVEMENT_ANIMATION_MIN_RATE, Config.MOVEMENT_ANIMATION_MAX_RATE))
	end

	-- ⚠️ v84 — HISTERESE ANDAR/CORRER. O limiar era um número só: se o
	-- WalkSpeed ficasse oscilando em volta dele (carregar o chute correndo
	-- multiplica por 0.68, buff de Arma liga/desliga, freio de posse), a
	-- animação trocava Run<->Walk a cada oscilação — parte do "fica
	-- intercalando" que aparecia pros outros jogadores. Agora, pra TROCAR de
	-- estado, a velocidade tem que passar do limiar com uma folga; dentro da
	-- folga, fica a que já estava tocando.
	-- 0.5 e não mais: o sprint mais lento possível (Speed mínimo + freio de
	-- posse = 38 x 0.9 x 0.9 = 30.8) tem que continuar entrando em Run com o
	-- limiar em 30 (+0.5).
	local FOLGA_CORRIDA = 0.5
	local function querCorrer(speed)
		if not speed then return false end
		if currentTrack == tracks.Run then
			return speed >= RUN_ANIMATION_MIN_SPEED - FOLGA_CORRIDA
		end
		return speed >= RUN_ANIMATION_MIN_SPEED + FOLGA_CORRIDA
	end

	local function refreshMoveTrack(speed)
		if isJumping and tracks.Jump then
			playTrack(tracks.Jump)
		elseif isFalling and tracks.Fall then
			playTrack(tracks.Fall)
		elseif querCorrer(speed) and tracks.Run then
			playTrack(tracks.Run)
			refreshTrackSpeed(tracks.Run, speed)
		elseif speed and speed > 0.5 and tracks.Walk then
			playTrack(tracks.Walk)
			refreshTrackSpeed(tracks.Walk, speed)
		elseif tracks.Idle or tracks.GKIdle then
			-- ⚠️ v65 — PEDIDO: animação de parado PRÓPRIA do goleiro.
			-- Só vale enquanto ele está sendo goleiro DE VERDADE, ou seja,
			-- dentro da própria área — a mesma regra que o resto do jogo usa
			-- (IsEffectiveGK). Fora dela ele é jogador de linha e volta pra
			-- Idle comum, senão ficaria em pose de goleiro no meio do campo.
			--
			-- A checagem é feita AQUI, e não na hora de carregar, porque ele
			-- entra e sai da área o tempo todo durante a partida.
			-- overrideMovementAnimations recebe o CHARACTER, não o Player —
			-- IsEffectiveGK espera o Player, então converte aqui.
			local dono = Players:GetPlayerFromCharacter(character)
			local ehGoleiro = dono ~= nil and GKAreaUtil.IsEffectiveGK(dono)
			playTrack((ehGoleiro and tracks.GKIdle) or tracks.Idle or tracks.GKIdle)
		else
			playTrack(nil)
		end
	end

	-- ⚠️ v61 — A CAUSA DO ATRASO.
	--
	-- Isto reagia SÓ ao evento Humanoid.Running, que reporta a velocidade
	-- REAL do personagem. Ela sobe do zero: quando a tecla é apertada, o
	-- boneco ainda está a ~0, o `speed > 0.5` lá em refreshMoveTrack falha, e
	-- a animação de andar só entra depois que a física acelerou — daí os
	-- ~0.3s de idle parado com o jogador já andando.
	--
	-- MoveDirection é o INPUT, não o resultado: ela muda no mesmo instante em
	-- que a tecla é apertada ou solta. Reagindo a ela, a animação de andar
	-- começa junto com o movimento e PARA junto com a soltada — que é
	-- exatamente o pedido. A velocidade usada pro ritmo passa a ser o
	-- WalkSpeed (a velocidade que ele VAI ter) em vez da atual, senão o
	-- primeiro instante ainda sairia em câmera lenta.
	--
	-- Running continua ligado como reforço: ele é quem avisa de mudanças que
	-- não vêm do input (empurrão, stun, freio de posse de bola).
	local function estadoAtual()
		return (humanoid.MoveDirection.Magnitude > 0.1) and humanoid.WalkSpeed or 0
	end

	humanoid:GetPropertyChangedSignal("MoveDirection"):Connect(function()
		if not isJumping and not isFalling then
			refreshMoveTrack(estadoAtual())
		end
	end)

	humanoid:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
		if not isJumping and not isFalling then
			refreshMoveTrack(estadoAtual())
		end
	end)

	humanoid.Running:Connect(function()
		if not isJumping and not isFalling then
			refreshMoveTrack(estadoAtual())
		end
	end)

	humanoid.Jumping:Connect(function(active)
		isJumping = active
		refreshMoveTrack(estadoAtual())
	end)

	humanoid.FreeFalling:Connect(function(active)
		isFalling = active
		refreshMoveTrack(estadoAtual())
	end)

	refreshMoveTrack(0)
end

-- ===== SETUP POR JOGADOR =====
local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid")

	-- ⚠️ v34 — PEDIDO: "remova a name tag de todo mundo. Ninguém vai poder
	-- ver o nome de ninguém, a não ser a que eu permitir — vou colocar uma
	-- name tag própria depois."
	-- Isso desliga a placa PADRÃO do Roblox (nome e barra de vida). Uma
	-- BillboardGui sua, criada depois, não é afetada por isso — ela é um
	-- objeto seu, não a placa embutida do Humanoid.
	humanoid.DisplayName = ""
	humanoid.NameDisplayDistance = 0
	humanoid.HealthDisplayDistance = 0
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None

	humanoid.WalkSpeed = getRunSpeed(player)
	applyPhysicalScale(player, character)
	overrideMovementAnimations(character)

	applyCollisionGroup(character)
	updateHighlight(player, character)

	local snapshot = characterSnapshots[player]
	local activeSlotStamina = (snapshot and typeof(snapshot.Stamina) == "number") and snapshot.Stamina or 0

	local maxStamina = Config.BASE_STAMINA + (activeSlotStamina * Config.STAMINA_PER_ATTRIBUTE_POINT)
	player.MaxStamina.Value = maxStamina
	player.Stamina.Value = maxStamina
	player.IsExhausted.Value = false

	-- Sem SpawnLocation: quem decide onde o personagem aparece é o
	-- MatchController.lua (formação por Role/Time) — roda em todo
	-- CharacterAdded, tanto no spawn inicial quanto em cada respawn.
	if _G.PositionPlayerAtFormation then
		_G.PositionPlayerAtFormation(player, character)
	end

	-- Auto-load desligado (ver Players.CharacterAutoLoads acima) =
	-- preciso respawnar na mão depois de morrer.
	humanoid.Died:Connect(function()
		task.delay(RESPAWN_DELAY, function()
			if player.Parent then -- ainda no server (não saiu no meio do delay)
				player:LoadCharacter()
			end
		end)
	end)
end

local function onPlayerAdded(player)
	-- ⚠️ v42 — PEDIDO: "limita a câmera do personagem pra não poder tirar
	-- muito zoom. Deixa ele usar só o zoom padrão, ou ficar em primeira
	-- pessoa se quiser aumentar o zoom. O zoom padrão é o zoom MÁXIMO que
	-- ele pode dar."
	--
	-- CameraMaxZoomDistance é o quanto ele pode AFASTAR a câmera; travando
	-- no valor padrão do Roblox (12.5 studs, a distância em que a câmera
	-- já nasce), ninguém consegue abrir mais que isso e enxergar meio campo
	-- de cima. CameraMinZoomDistance fica em 0.5 de propósito: aproximar
	-- continua livre, incluindo ir até a primeira pessoa.
	--
	-- Feito no SERVIDOR (a propriedade replica) pra valer também pra quem
	-- tenta mexer nisso pelo cliente.
	player.CameraMaxZoomDistance = Config.CAMERA_MAX_ZOOM_DISTANCE
	player.CameraMinZoomDistance = Config.CAMERA_MIN_ZOOM_DISTANCE

	local joinData = player:GetJoinData()
	local teleportData = joinData.TeleportData
	print(("%s entrou. TeleportData: %s"):format(player.Name, tostring(teleportData)))

	-- FIX: jogador que chega via matchmaking (place Lobby) já vem com o
	-- time definido em TeleportData.Assignments (montado pelo
	-- Matchmaker.lua de lá) — não faz sentido depender de
	-- RequestTeamChange manual nesse caso. Quem entra sem TeleportData
	-- (testando sozinho no Studio, por exemplo) continua livre pra
	-- trocar de time pela UI, como sempre funcionou.
	if typeof(teleportData) == "table" and typeof(teleportData.Assignments) == "table" then
		local assignedTeamName = teleportData.Assignments[tostring(player.UserId)]
		local team = assignedTeamName and Teams:FindFirstChild(assignedTeamName)
		if team then
			player.Team = team
		else
			warn(("%s chegou via matchmaking mas o time \"%s\" não bateu com nenhum Team existente."):format(player.Name, tostring(assignedTeamName)))
		end
	end

	-- FIX: aplica o personagem ativo do roster (montado no Lobby por
	-- PlayerDataManager/MatchDataTransfer, embutido pelo Matchmaker.lua
	-- em TeleportData.Characters) como Attributes de verdade no Player —
	-- é isso que o BallController/OutOfBoundsController leem via
	-- GetAttribute(Config.PHYSICAL_ATTRIBUTE) etc. Sem TeleportData
	-- (testando sozinho no Studio), cada atributo cai no default do
	-- FootballConfig.lua (50), como sempre foi.
	if typeof(teleportData) == "table" and typeof(teleportData.Characters) == "table" then
		local snapshot = teleportData.Characters[tostring(player.UserId)]
		if typeof(snapshot) == "table" then
			characterSnapshots[player] = snapshot
			for _, attrName in ipairs({ "Physical", "DribbleSkill", "Speed", "Kick", "Energy", "Technique" }) do -- ⚠️ NOVO: Energy (tanque de Hissatsu) · Technique (7º atributo)
				if typeof(snapshot[attrName]) == "number" then
					player:SetAttribute(attrName, snapshot[attrName])
				end
			end

			-- Role (GK/DF/MF/FW) — usado pelo sistema de Pulso/Instinto pra
			-- saber quem é o goleiro (Instintos/Pulsos com RoleRequired="GK").
			if typeof(snapshot.Role) == "string" then
				player:SetAttribute("Role", snapshot.Role)
			end

			-- ⚠️ NOVO: Element (Natureza/Fogo/Vento/Luz/Void) — reinserido a
			-- pedido do usuário, sorteado por slot no Lobby (ver
			-- CharacterCreator.new em PlayerDataManager.legacy.luau). Usado
			-- pela vantagem elemental e pelo bônus de "elemento igual" em
			-- PulseController.legacy.luau (Config.ELEMENT_ATTRIBUTE_NAME).
			if typeof(snapshot.Element) == "string" then
				player:SetAttribute(Config.ELEMENT_ATTRIBUTE_NAME, snapshot.Element)
			end

			-- ⚠️ v110 — PEDIDO: "implemente o nome personalizado que já tem nos
			-- slots dentro do jogo" + cosméticos/Flow equipados no Lobby. O
			-- nome do slot vira o atributo "NomePersonagem" (placa de nome,
			-- placar, chat); cada cosmético vira "Cosm_<Slot>" (ver
			-- Cosmeticos.luau — o CosmeticosServer/Client aplicam).
			if typeof(snapshot.SlotName) == "string" and snapshot.SlotName ~= "" then
				player:SetAttribute("NomePersonagem", string.sub(snapshot.SlotName, 1, 24))
			end
			if typeof(snapshot.Cosmeticos) == "table" then
				for slotCosm, idCosm in pairs(snapshot.Cosmeticos) do
					if typeof(slotCosm) == "string" and typeof(idCosm) == "string" then
						player:SetAttribute("Cosm_" .. slotCosm, idCosm)
					end
				end
			end

			-- Pulso/Instinto equipados no Lobby (ver RollServer.legacy.luau
			-- de lá e MatchDataTransfer.legacy.luau) — repassa pro
			-- PulseController/InstinctController deste place. Esses scripts
			-- podem carregar em ordem alfabética diferente, então os _G.*
			-- só existem se já tiverem rodado — dá pra rodar de novo com
			-- segurança (idempotente), então tenta e, se ainda não existir,
			-- ignora (o jogador só fica sem Pulso/Instinto nessa partida).
			task.defer(function() -- defer: garante que PulseController/InstinctController já terminaram de carregar, não importa a ordem alfabética dos Scripts
				-- ⚠️ v78 — CORREÇÃO: só 2 slots ATIVOS em partida, sempre, pra
				-- todo mundo (justiça — pedido do usuário). O 3º slot (Robux)
				-- é só RESERVA/armazenamento, trocado pelo jogador na HUD de
				-- Roll (equiparNoSlot em RollServer.legacy.luau escolhe qual
				-- dos 2 slots ativos recebe cada Pulso/Instinto) — por isso
				-- aqui a partida NUNCA recebe EquippedPulse3/EquippedInstinct3,
				-- mesmo que o jogador tenha ExtraPulseSlot/ExtraInstinctSlot.
				-- ⚠️ v106: o task.defer não garante que o PulseController/
				-- InstinctController já carregaram — se ainda não, o jogador
				-- ficava SEM as Hissatsus/Armas a partida inteira, sem aviso.
				-- Espera eles existirem (até 15s) e avisa a HUD (LoadoutVersao).
				local limite = os.clock() + 15
				while (not _G.SetPlayerLoadout or not _G.SetPlayerInstincts) and os.clock() < limite do task.wait(0.2) end
				if not _G.SetPlayerLoadout then warn("[Loadout] PulseController não carregou — " .. player.Name .. " ficou sem Hissatsu") end
				if _G.SetPlayerLoadout then
					local slot1 = typeof(snapshot.EquippedPulse1) == "string" and snapshot.EquippedPulse1 or nil
					local slot2 = typeof(snapshot.EquippedPulse2) == "string" and snapshot.EquippedPulse2 or nil
					_G.SetPlayerLoadout(player, slot1, slot2)
				end
				if _G.SetPlayerInstincts then
					local lista = {}
					for _, campo in ipairs({ "EquippedInstinct1", "EquippedInstinct2" }) do
						if typeof(snapshot[campo]) == "string" then
							table.insert(lista, snapshot[campo])
						end
					end
					_G.SetPlayerInstincts(player, lista)
				end
				player:SetAttribute("LoadoutVersao", (player:GetAttribute("LoadoutVersao") or 0) + 1)
			end)
		end
	end

	setupStatValues(player)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end

	player:GetPropertyChangedSignal("TeamColor"):Connect(function()
		if player.Character then
			updateHighlight(player, player.Character)
		end
	end)

	player.CharacterRemoving:Connect(function(character)
		local highlight = character:FindFirstChild("TeamHighlight")
		if highlight then highlight:Destroy() end
	end)

	-- Auto-load desligado (ver Players.CharacterAutoLoads acima) — só
	-- carrega o personagem AGORA, depois do Team/Role já estarem
	-- definidos acima (e do CharacterAdded já conectado, então o
	-- MatchController pega esse primeiro spawn também).
	if not player.Character then
		player:LoadCharacter()
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(function(player)
	runStartedAt[player] = nil
	charging[player] = nil
	characterSnapshots[player] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

-- ===== TROCA DE TIME =====
Remotes.RequestTeamChange.OnServerEvent:Connect(function(player, requestedTeamName)
	local team = Teams:FindFirstChild(requestedTeamName)
	if not team then
		warn("Time não encontrado: " .. tostring(requestedTeamName))
		return
	end
	if player.Team ~= team then
		player.Team = team
	end
end)

print("✅ PlayerSystems carregado.")