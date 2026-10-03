--[[
	BallController (Script)
	LOCAL: ServerScriptService

	Um script só cuidando de TUDO relacionado à bola:
	drible/posse/finta, stun, chute (que também serve de passe e voleio),
	cabeçada e carrinho.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local AbilityAura = require(ReplicatedStorage:WaitForChild("AbilityAura")) -- ⚠️ v45: auras de habilidade (contorno pulsante, sem pintar o corpo)
local Remotes = Config.Remotes
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))

local PhysicsService = game:GetService("PhysicsService")

local ball = workspace:WaitForChild(Config.BALL_NAME)
ball.CollisionGroup = "Bola"
ball.CanCollide = true
ball.CanTouch = true

-- ⚠️ v14: PEDIDO — "a bola está SIM colidindo com a rootpart do
-- personagem, 99,99% de certeza". A dupla Bola x Players já é forçada
-- pra 'false' lá no FootballConfig.lua, uma vez, na hora do require —
-- isso AQUI é um seguro extra: reforça o CollisionGroup da própria bola
-- (caso algo em qualquer lugar troque ele de volta pra 'Default' — ex.:
-- algum script que clone/recrie a Part, um Union, um Plugin de teste) e
-- reconfirma a dupla não-colidável a cada poucos segundos, pro jogo se
-- autocorrigir sozinho SEM precisar reiniciar o server.
task.spawn(function()
	while ball.Parent do
		if ball.CollisionGroup ~= "Bola" then
			warn(("⚠️ BallController: a Part da bola estava com CollisionGroup '%s' (esperado 'Bola') — corrigido automaticamente. Se isso aparecer de novo e de novo, alguma coisa está trocando esse valor em runtime (confira Plugins/scripts extras)."):format(ball.CollisionGroup))
			ball.CollisionGroup = "Bola"
		end
		if PhysicsService:CollisionGroupsAreCollidable("Bola", "Players") then
			warn("⚠️ BallController: 'Bola' x 'Players' voltou a ficar colidível em runtime — forçando 'false' de novo agora.")
			PhysicsService:CollisionGroupSetCollidable("Bola", "Players", false)
		end
		task.wait(2)
	end
end)

-- ⚠️ v14: diagnóstico DIRETO pra provar (ou descartar de vez) colisão
-- física real — toda vez que a bola encosta numa Part de um personagem,
-- isto imprime os dois CollisionGroups envolvidos e se a dupla está
-- marcada como colidível NAQUELE EXATO INSTANTE. Se aparecer sempre
-- 'Bola'/'Players'/false, a física está correta e o que se sente como
-- "ricochete" é 100% a mecânica de corpo (ver v13 acima) — não colisão.
-- Se aparecer QUALQUER OUTRA COISA (grupo errado, ou 'true'), achamos a
-- causa raiz de verdade. Print (não warn) pra não poluir como erro.
ball.Touched:Connect(function(hit)
	if not hit:IsA("BasePart") then return end
	local character = hit:FindFirstAncestorOfClass("Model")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local collidable = PhysicsService:CollisionGroupsAreCollidable(ball.CollisionGroup, hit.CollisionGroup)
	if hit.CollisionGroup ~= "Players" or collidable then
		warn(("🔎 BallController DIAGNÓSTICO: bola (grupo '%s') tocou '%s' de '%s' (grupo '%s') — colidível entre os dois grupos = %s. Isso NÃO deveria acontecer com 'true' ou grupo diferente de 'Players'."):format(
			ball.CollisionGroup, hit.Name, character.Name, hit.CollisionGroup, tostring(collidable)))
	end
end)

-- ⚠️ v25 — ACHADO: o log que o print v22 (abaixo, removido agora) trouxe
-- mostrou a bola tocando "Linhas.Union" com Size = 4.79 x 93.37 x 93.37 —
-- ENORME pra uma linha do campo, que deveria ser fina. Isso é uma
-- pegadinha clássica do Roblox com Parts feitas por UNIÃO (Union/CSG,
-- geralmente usadas pras linhas/círculo do campo): por padrão
-- (CollisionFidelity = Default/Hull), a colisão de uma união vira o CASCO
-- CONVEXO da forma inteira — pra uma forma "vazada"/complexa (tipo um
-- círculo ou um anel de linhas), o casco convexo PREENCHE o buraco do
-- meio, virando um bloco sólido invisível bem maior que a linha visível.
-- Era ISSO que parecia "parede/teto invisível" no meio do campo: a forma
-- visual é uma linha fina, mas a colisão de verdade é um bloco enorme.
--
-- ⚠️ v25 FIX (ERRO GRAVE): "The current thread cannot write 'CollisionFidelity'
-- (lacking capability Plugin)" — Scripts rodando o jogo NÃO TÊM PERMISSÃO
-- de mudar CollisionFidelity (só um Plugin do Studio pode). A tentativa de
-- escrever isso direto deu erro e DERRUBOU O RESTO DO SCRIPT INTEIRO (por
-- isso o drible parou de funcionar de vez — nada depois desse ponto no
-- arquivo chegou a carregar). Agora só AVISA quais Uniões estão com a
-- colisão potencialmente maior que a forma visível — você mesmo corrige
-- manualmente no Studio (clica na Part > painel Properties > procura
-- "CollisionFidelity" > muda pra "PreciseConvexDecomposition"), 10 segundos,
-- sem risco nenhum de travar nada.
local warnedFidelity = {}
local function checkUnionCollisionFidelity(inst)
	if not (inst:IsA("UnionOperation") or inst:IsA("NegateOperation")) then return end
	if inst.CollisionFidelity == Enum.CollisionFidelity.PreciseConvexDecomposition then return end
	if warnedFidelity[inst] then return end
	warnedFidelity[inst] = true
	warn(("🔧 BallController: '%s' (%s) está com CollisionFidelity = %s — a colisão dela pode ser BEM MAIOR que a forma visível (vira uma 'parede/teto invisível'). Corrige manualmente no Studio: seleciona essa Part, no painel Properties procura \"CollisionFidelity\" e muda pra \"PreciseConvexDecomposition\"."):format(
		inst.Name, inst:GetFullName(), tostring(inst.CollisionFidelity)))
end

for _, inst in ipairs(workspace:GetDescendants()) do
	checkUnionCollisionFidelity(inst)
end
workspace.DescendantAdded:Connect(checkUnionCollisionFidelity)

-- ===== HISTÓRICO DA JOGADA (⚠️ v14 REPLAY DE GOL, v27 EXPANDIDO) =====
-- PEDIDO ORIGINAL: "durante o áudio, coloque um sistema simples de replay
-- que visualiza a bola". PEDIDO NOVO (v27): "a bola está amarela/dourada,
-- eu não quero isso, quero ela normal, e nem os jogadores e nem o bot
-- aparecem em campo... é pra aparecerem os dois e recriarem exatamente a
-- jogada". Agora grava, no MESMO instante de cada amostra (pra tudo ficar
-- perfeitamente sincronizado no replay): posição da bola, posição+direção
-- de CADA JOGADOR em campo, e posição+direção de qualquer BOT de goleiro
-- ativo (_G.GetActiveGKBots, exposto pelo GKBotController.lua — o bot não
-- é um Player, então precisa desse canal separado pra saber onde ele
-- está). MatchController.lua chama _G.GetReplaySnapshot() bem na hora que
-- confirma o gol (antes de resetar a bola pro centro) e manda esse
-- retrato pro cliente desenhar o replay (ver GoalReplayClient.local.luau).
--
-- Só guarda posição (x,y,z) + um ângulo de giro no eixo Y (yaw, pra saber
-- pra onde o personagem/bot estava olhando) — leve o bastante pra mandar
-- pelo RemoteEvent sem pesar, mesmo com vários jogadores em campo. Não é
-- animação de verdade (sem passos/chute animado), só reposiciona cada um
-- ao longo do tempo — dá pra melhorar depois se quiser.
local matchHistory = {} -- array de { t, ball={x,y,z}, players={{uid,name,team,x,y,z,yaw},...}, bots={{team,x,y,z,yaw},...} }
local lastHistorySampleAt = 0

-- ⚠️ v103 — REPLAY COMPLETO. PEDIDO: "o replay tá maravilhoso, só que
-- algumas animações não saem: a de ficar parado e correr saem, mas a de
-- chutar não, nem a da cutscene... não é pra replicar a cutscene, é pra
-- aparecer o personagem fazendo a animação em tempo real... os VFX vão sair
-- no replay pra você saber que a habilidade foi ativada, vai aparecer o
-- número da vida da bola, e se o GK usou a habilidade — tudo o que aconteceu
-- vai ser registrado no replay."
-- Além das posições, agora grava (no MESMO relógio das amostras):
--   • EVENTOS (matchEvents): cada ação animada (chute, drible, mergulho,
--     carrinho, preparo de Hissatsu...) e cada cutscene de Hissatsu, com quem
--     fez e os parâmetros — o cliente repete no fantasma;
--   • por amostra: o número da vida da bola (texto e cor), a aura de
--     habilidade de cada jogador e as peças visuais de habilidade (guarda do
--     goleiro, bloqueio do defensor) — ver replayExtras mais abaixo.
local matchEvents = {} -- { t, tipo, dados }
local replayExtras = {} -- Forca(), Visuais(): preenchidas mais abaixo no arquivo
_G.RegistrarEventoReplay = function(tipo, dados)
	table.insert(matchEvents, { t = os.clock(), tipo = tipo, dados = dados })
end
_G.GetReplayEventos = function()
	local copia = table.create(#matchEvents)
	for i, e in ipairs(matchEvents) do copia[i] = e end
	return copia
end
-- quem é o ator de um Model: "P<UserId>" (jogador) ou "B<time>" (goleiro bot)
local function idDoAtorReplay(model)
	if typeof(model) ~= "Instance" then return nil end
	local plr = Players:GetPlayerFromCharacter(model)
	if plr then return "P" .. plr.UserId end
	if model.Name:sub(1, 6) == "GKBot_" then return "B" .. model.Name:sub(7) end
	return nil
end
_G.IdDoAtorReplay = idDoAtorReplay
local AbilityAuraModulo = ReplicatedStorage:FindFirstChild("AbilityAura") and require(ReplicatedStorage.AbilityAura)
local ATRIBUTO_AURA = AbilityAuraModulo and AbilityAuraModulo.PULSE_ATTRIBUTE
local function auraDoPersonagem(character)
	if not ATRIBUTO_AURA or not character then return nil end
	for _, h in ipairs(character:GetChildren()) do
		if h:IsA("Highlight") and h:GetAttribute(ATRIBUTO_AURA) then
			local c = h.OutlineColor
			return { r = c.R, g = c.G, b = c.B, ritmo = h:GetAttribute(ATRIBUTO_AURA) }
		end
	end
	return nil
end

-- Ângulo de giro no eixo Y a partir do LookVector (ignora pitch/roll —
-- não interessa pra um personagem/bot andando no chão).
local function yawFromLookVector(look)
	return math.atan2(look.X, look.Z)
end

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - lastHistorySampleAt < Config.GOAL_REPLAY_SAMPLE_INTERVAL then return end
	lastHistorySampleAt = now

	local pos = ball.Position
	local sample = { t = now, ball = { x = pos.X, y = pos.Y, z = pos.Z }, players = {}, bots = {} }

	for _, plr in ipairs(Players:GetPlayers()) do
		local character = plr.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local rPos = root.Position
			table.insert(sample.players, {
				uid = plr.UserId,
				name = plr.Name,
				team = plr.Team and plr.Team.Name or nil,
				x = rPos.X, y = rPos.Y, z = rPos.Z,
				yaw = yawFromLookVector(root.CFrame.LookVector),
				aura = auraDoPersonagem(character), -- ⚠️ v103
			})
		end
	end

	local activeBots = _G.GetActiveGKBots and _G.GetActiveGKBots() or {}
	for _, botInfo in ipairs(activeBots) do
		local bPos = botInfo.cframe.Position
		table.insert(sample.bots, {
			team = botInfo.teamName,
			x = bPos.X, y = bPos.Y, z = bPos.Z,
			yaw = yawFromLookVector(botInfo.cframe.LookVector),
		})
	end

	-- ⚠️ v103: vida da bola e peças visuais de habilidade nesse instante
	if replayExtras.Forca then sample.forca = replayExtras.Forca() end
	if replayExtras.Visuais then sample.visuais = replayExtras.Visuais() end

	table.insert(matchHistory, sample)

	-- poda o que já passou do tempo que a gente precisa guardar (com uma
	-- folguinha de 1s de segurança)
	local cutoff = now - (Config.GOAL_REPLAY_DURATION + 1)
	while #matchHistory > 0 and matchHistory[1].t < cutoff do
		table.remove(matchHistory, 1)
	end
	while #matchEvents > 0 and matchEvents[1].t < cutoff do
		table.remove(matchEvents, 1)
	end
end)

_G.GetReplaySnapshot = function()
	-- cópia rasa (os itens são tabelas pequenas e imutáveis na prática,
	-- só a lista em si precisa ser uma cópia pra não vazar referência pro
	-- array que continua sendo escrito)
	local snapshot = table.create(#matchHistory)
	for i, point in ipairs(matchHistory) do
		snapshot[i] = point
	end
	return snapshot
end

-- ===== HIGHLIGHT DA BOLA (branco, sempre ligado) =====
-- Ajuda todo mundo a achar a bola de longe/atrás de jogadores — igual o
-- TeamHighlight dos personagens, mas fixo na bola e sempre visível
-- (não é o mesmo Highlight do iframe, que é só nos personagens).
do
	local ballHighlight = ball:FindFirstChild("BallHighlight")
	if not ballHighlight then
		ballHighlight = Instance.new("Highlight")
		ballHighlight.Name = "BallHighlight"
		ballHighlight.Adornee = ball
		ballHighlight.FillColor = Color3.fromRGB(255, 255, 255)
		ballHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		ballHighlight.FillTransparency = 0.55
		ballHighlight.OutlineTransparency = 0
		ballHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		ballHighlight.Parent = ball
	end
	ballHighlight.Enabled = true
end

local POSSESSION_TOUCH_RADIUS = 3.5
-- ⚠️ v5.4/v5.5 FIX: "chutei de leve um passe pro meu colega, e ele
-- atravessou mesmo com baixa velocidade". Era 14 — um chute na força
-- MÍNIMA (Config.KICK_MIN_FORCE=30) já sai a ~30-35 studs/s, então NENHUM
-- passe chutado de propósito (nem o mais fraco possível) nunca ficava
-- abaixo desse teto. Subiu pra 55 (v5.4), mas ficou FORTE demais na
-- prática (pickup grudando em chutes que já não deveriam contar como
-- "passe fraco"). v5.5: meio-termo em 34 — cobre o passe mais fraco
-- possível (~30-35 studs/s) sem esticar pra chutes de força média pra
-- cima, que devem continuar exigindo captura ativa (carrinho/goleiro).
-- ⚠️ v120b — PEDIDO: "pegar a bola mais fácil (no ar, pro air dribble), se ela
-- estiver lenta — bicuda continua sem dar". 22 → 30.
local LOOSE_BALL_PICKUP_MAX_SPEED = 30

-- ===== TOQUE ESPECIAL: rastro visual + sons =====
local trail
do
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "TrailA"
	attachment0.Position = Vector3.new(0, 0.5, 0)
	attachment0.Parent = ball

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TrailB"
	attachment1.Position = Vector3.new(0, -0.5, 0)
	attachment1.Parent = ball

	trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = 0.35
	trail.MinLength = 0
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Enabled = false
	trail.Parent = ball
end

local kickSound = Instance.new("Sound")
kickSound.Name = "KickSound"
kickSound.SoundId = Config.SOUNDS.Kick
kickSound.Volume = 0.6
kickSound.Parent = ball

local tackleSound = Instance.new("Sound")
tackleSound.Name = "TackleSound"
tackleSound.SoundId = Config.SOUNDS.Tackle
tackleSound.Volume = 0.6
tackleSound.Parent = ball

local function playKickFeedback(force)
	trail.Enabled = force >= Config.BALL_TRAIL_MIN_FORCE
	if trail.Enabled then
		task.delay(Config.CURVE_DURATION + 0.5, function()
			trail.Enabled = false
		end)
	end
	kickSound.PlaybackSpeed = 0.9 + (force / Config.KICK_MAX_FORCE) * 0.3
	kickSound:Play()
end

-- ⚠️ v97 — velocidade de saída pra bola, com essa rapidez, passar PELO
-- ponto `alvo` (parábola com a gravidade da bola: Gravity x
-- BALL_GRAVITY_MULTIPLIER, já que a VectorForce cancela o resto). Usa o arco
-- BAIXO (o mais direto). Alvo fora de alcance: sai na direção exata da mira,
-- um pouquinho acima, e cai antes — a direção nunca erra, só falta força.
_G.VelocidadeBalistica = function(origem, alvo, rapidez)
	local g = workspace.Gravity * Config.BALL_GRAVITY_MULTIPLIER
	local d = alvo - origem
	local plano = Vector3.new(d.X, 0, d.Z)
	local x = plano.Magnitude
	if x < 0.5 or rapidez <= 0 or g <= 0 then return nil end
	local h = d.Y
	local v2 = rapidez * rapidez
	local disc = v2 * v2 - g * (g * x * x + 2 * h * v2)
	local angulo
	if disc >= 0 then
		angulo = math.atan((v2 - math.sqrt(disc)) / (g * x))
	else
		angulo = math.atan2(h, x) + math.rad(5)
	end
	angulo = math.clamp(angulo, math.rad(-70), math.rad(70))
	return plano.Unit * (rapidez * math.cos(angulo)) + Vector3.new(0, rapidez * math.sin(angulo), 0)
end

local curveGeneration = 0
local function applyCurve(spin, travelDirection)
	-- ⚠️ v84: todo chute novo ENCERRA a curva do chute anterior, mesmo que o
	-- novo não tenha curva nenhuma. Antes o "sem curva" saía antes de
	-- incrementar a geração, e o loop de uma curva ainda viva (ex.: Hissatsu
	-- chutada meio segundo antes) continuava empurrando a bola pro lado no
	-- chute seguinte — um dos "às vezes vai pra um lado" do pedido.
	curveGeneration += 1
	if Config.KICK_TEST_MODE then return end -- ⚠️ v23: modo de teste — sem curva, só a velocidade reta do chute
	if not spin or spin == 0 then return end
	spin = math.clamp(spin, -1, 1)

	local myGeneration = curveGeneration
	local elapsed = 0

	-- ⚠️ v5.3 — BUG DA BOLA INDO PRA TRÁS AO OLHAR 100% PRA CIMA.
	-- travelDirection:Cross(Vector3.yAxis) dá o vetor ZERO quando a bola
	-- vai reta pra cima (ou reta pra baixo), porque a direção é paralela
	-- ao eixo Y. E .Unit de um vetor zero, em Roblox, devolve NaN — que
	-- entrava direto na AssemblyLinearVelocity da bola no loop abaixo.
	-- Velocidade NaN faz a física jogar a bola pra um lugar qualquer, o
	-- que aparecia como "chutei pra cima e ela foi pra trás".
	-- Chute reto pra cima não tem lado pra curvar, então aqui a curva
	-- simplesmente não se aplica — em vez de virar NaN.
	local lateral = travelDirection:Cross(Vector3.yAxis)
	if lateral.Magnitude < 1e-3 then return end
	local rightVector = lateral.Unit

	local connection
	connection = RunService.Heartbeat:Connect(function(dt)
		if myGeneration ~= curveGeneration or elapsed >= Config.CURVE_DURATION then
			connection:Disconnect()
			return
		end
		elapsed += dt
		local falloff = 1 - (elapsed / Config.CURVE_DURATION)
		ball.AssemblyLinearVelocity += rightVector * spin * Config.CURVE_STRENGTH * falloff * dt
	end)
end

-- ===== ESTADO =====
local owner = nil
local lastTouchers = {}
-- ⚠️ v6.2: incrementado toda vez que a bola é reposicionada/resetada de
-- verdade (gol + kickoff, ver _G.ResetBallState abaixo) — exposto via
-- _G.GetBallStateGeneration pra outros scripts (ex: GKBotController.lua)
-- conseguirem detectar com certeza "o jogo já seguiu adiante desde que eu
-- comecei a esperar por alguma coisa" (ex: um mergulho com resolução
-- atrasada) sem depender de um número fixo de distância "chutado", que
-- pode falhar dependendo do tamanho do campo.
local ballStateGeneration = 0
local tackleDashes = {}      -- [player] = { startPosition, endPosition, triggeredAt, expiresAt } (lunge de carrinho em andamento)

-- ⚠️ v67 — PEDIDO: "você pode gastar stamina enquanto usa o carrinho, mesmo
-- segurando o shift; isso não pode, senão o cara vai precisar soltar o shift
-- quando for dar carrinho pra evitar gastar demais."
--
-- Durante o lunge o jogador não está CORRENDO — ele foi arremessado. Cobrar
-- fôlego de sprint aí é cobrar duas vezes pela mesma ação (o carrinho já
-- custa TACKLE_STAMINA_COST) e obriga a soltar o Shift antes de cada
-- desarme, que é um controle que ninguém deveria precisar fazer.
-- Lido por PlayerSystems.legacy.luau, que é quem drena o fôlego.
_G.IsInTackleDash = function(player)
	local dash = tackleDashes[player]
	return dash ~= nil and tick() < (dash.expiresAt or 0)
end
local dribbleMoveCooldowns = {}
local headerCooldowns = {}
local tackleCooldowns = {}   -- [player] = tick() da última TENTATIVA de carrinho (independente de stamina/acerto — PEDIDO: 4s de cooldown fixo, pra parar de dar pra spamar a tecla)
local recentKicker, recentKickTime = nil, 0 -- último jogador que chutou/cabeceou a bola + tick() — usado só pra imunizar ELE MESMO contra a própria mecânica de corpo (ver BODY_BLOCK abaixo)
local kickerClearedBody = true -- ⚠️ v12: true = a bola já saiu do raio do próprio corpo do recentKicker desde o último chute dele (ver BODY_BLOCK abaixo pro motivo de existir)
local hasBodyBlockedThisFlight = false -- ⚠️ v14: true = esse lance já foi "absorvido pelo corpo" uma vez — trava novos cortes até o próximo chute de verdade (ver BODY_BLOCK abaixo)
-- ⚠️ v20 ("a bola bate no corpo e para"): enquanto kickClearPlayer não
-- for nil, a bola está com CanCollide = false DE PROPÓSITO — é a "saída
-- limpa do chute", que faz ela atravessar qualquer coisa colada no corpo
-- de quem chutou (ver startKickClearance / o loop de liberação abaixo).
local kickClearPlayer = nil
local kickClearUntil = 0
local kickClearStartY = 0
-- ⚠️ v7: PEDIDO — "o goleiro só vai poder pegar a bola se o físico dele
-- for maior que a força dela" — força do ÚLTIMO chute, guardada aqui pra
-- comparar contra o Physical do goleiro no momento da captura (ver
-- getShotForceRating/currentDangerForceRating mais abaixo).
local lastShotForce = 0
-- ⚠️ v8: PEDIDO — "instintos não são como o pulso... o Chute Direto pode
-- ser defendido só com o dive normal e qualquer físico". true só quando
-- o último chute veio de um Instinto (_G.InstinctExecuteShot), pra
-- currentDangerForceRating devolver 0 nesse caso — Instinto nunca conta
-- como "chute perigoso" pro gate de Physical do goleiro, só Pulso/Hissatsu.
local lastShotWasInstinct = false
-- ⚠️ v7: true enquanto a bola está travada esperando o QTE de colisão da
-- guarda de Hissatsu do goleiro (ver o sistema de guarda mais abaixo,
-- perto de _G.PulseComputeShotTarget) — ninguém (nem o próprio goleiro
-- fora do QTE, nem qualquer outro jogador) pode tocar na bola enquanto
-- isso for true.
local ballFrozenForGuardQTE = false
local dribbleMoves = {}      -- [player] = { targetPosition, expiresAt, direction } (finta ativa)
local deadBallMode = false   -- true durante lateral/escanteio/tiro de meta
local pendingLooseTackle = nil -- { player = Player, time = number } — carrinho em andamento numa bola solta
local lastIgnoreGKShot = 0   -- tick() do último chute com "ignora goleiro" (Instinto Divino do Artilheiro) — reduz um pouco o raio de mergulho por 1s
local diving = {}            -- [player] = { ExpiresAt, Radius } (mergulho/dash de goleiro em andamento)
local gkActionCooldowns = {} -- [player] = tick() em que pode mergulhar/dashar de novo
local bodyBlockDebounce = {} -- [player] = tick() do último bloqueio de corpo
local bodyBlockContactStart = {} -- ⚠️ v13: [player] = tick() de quando a bola entrou no raio do corpo dele (ver MECÂNICA DE CORPO)

-- ⚠️ v84 — PEDIDO: "impeça que o goleiro e o GK BOT possam fazer gol contra".
-- lastTouchers só guarda PLAYERS — o GK BOT não é um Player, então um
-- alívio/rebote/lançamento dele nunca aparecia como "último toque". Este é o
-- último toque de VERDADE, de qualquer um dos dois: { Kind = "Player",
-- Player = ... } ou { Kind = "Bot", Team = "<time do bot>" }. Quem consulta
-- é o onGoalScored do MatchController (ver _G.GetLastBallTouch abaixo).
local ultimoToqueNaBola = nil

local function pushToucher(player)
	ultimoToqueNaBola = { Kind = "Player", Player = player }
	if lastTouchers[1] == player then return end
	lastTouchers[2] = lastTouchers[1]
	lastTouchers[1] = player
end

local function getCharacterParts(player)
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil end
	return character, root, humanoid
end

-- ===== ⚠️ v20: SAÍDA LIMPA DO CHUTE =====
-- PEDIDO: "simplesmente bate no CORPO e não no campo... tem algo
-- colidindo exatamente na bunda do personagem, veja a melhor abordagem
-- pra isso". Depois de várias rodadas tentando IDENTIFICAR o que colide
-- (grupos de colisão, mecânica de corpo, quique de chão — nenhuma
-- explicou o caso), a abordagem virou outra: não importa mais O QUE é.
-- Durante a saída do chute, a bola fica com CanCollide = false e
-- atravessa QUALQUER coisa que esteja colada no corpo do chutador —
-- hitbox invisível, acessório, Part sobrando no personagem, o que for.
--
-- A janela é curtíssima e fecha assim que qualquer uma acontecer:
--   • a bola se afastou Config.KICK_CLEAR_DISTANCE studs do corpo dele;
--   • estourou Config.KICK_CLEAR_MAX_SECONDS (teto de segurança);
--   • a bola caiu mais de Config.KICK_CLEAR_MAX_DROP studs abaixo de
--     onde saiu do pé (chute fraco/rasteiro — devolve a colisão na hora
--     pra ela não afundar no chão).
-- Fora dessa janela nada muda: a física da bola continua a de sempre.
local function startKickClearance(player)
	if Config.KICK_TEST_MODE then return end -- ⚠️ v23: modo de teste — bola nunca fica CanCollide=false, física padrão o tempo todo
	kickClearPlayer = player
	kickClearUntil = tick() + Config.KICK_CLEAR_MAX_SECONDS
	kickClearStartY = ball.Position.Y
	ball.CanCollide = false
end

local function endKickClearance()
	if not kickClearPlayer then return end
	kickClearPlayer = nil
	ball.CanCollide = true
end

RunService.Heartbeat:Connect(function()
	if not kickClearPlayer then return end

	if tick() >= kickClearUntil then
		endKickClearance()
		return
	end

	if ball.Position.Y < kickClearStartY - Config.KICK_CLEAR_MAX_DROP then
		endKickClearance() -- começou a afundar — devolve a colisão imediatamente
		return
	end

	local _, root = getCharacterParts(kickClearPlayer)
	if not root then
		endKickClearance() -- chutador sumiu (morreu/saiu) — não faz sentido manter
		return
	end

	if (root.Position - ball.Position).Magnitude > Config.KICK_CLEAR_DISTANCE then
		endKickClearance() -- já saiu de perto do corpo: caso normal, o mais comum
	end
end)

-- ⚠️ v21 — PEDIDO: "faz a bola sair de um ponto na frente do corpo, pode
-- ser assim". Complementa a saída limpa acima: além de atravessar
-- qualquer coisa colada no corpo durante a janela, a bola já "nasce"
-- deslocada pra frente na direção do chute — só no plano horizontal (X/Z),
-- a altura Y não é tocada, então cabeçada/lob continuam subindo normal.
-- Chamado logo depois da direção final do chute já estar calculada (com
-- desvio de mira aplicado), antes da velocidade ser aplicada na bola.
--
-- ⚠️ v22 FIX — PEDIDO: "quando estou correndo, a bola é teleportada
-- justamente pro ponto de impacto dessa hitbox invisível, e ela já
-- ricocheteia". O teleporte direto (sem checar o caminho) podia jogar a
-- bola pra DENTRO de alguma Part sólida no meio do trajeto de 2.5 studs —
-- daí o "ricochete" bem no instante do chute. Agora faz um Raycast antes
-- de mover: se tiver algo colidível de verdade no caminho, avança só até
-- um pouco antes dele (nunca atravessa/teleporta pra dentro de nada).
local nudgeRaycastParams = RaycastParams.new()
nudgeRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
nudgeRaycastParams.FilterDescendantsInstances = { ball }
nudgeRaycastParams.CollisionGroup = "Bola" -- respeita as mesmas regras de colisão da bola (ex: não "bate" em Players, que é sempre não-colidível com Bola)

local function nudgeBallForwardForKick(direction)
	if Config.KICK_TEST_MODE then return end -- ⚠️ v23: modo de teste — bola nunca é reposicionada, só a velocidade do chute normal
	local horizontalDir = Vector3.new(direction.X, 0, direction.Z)
	if horizontalDir.Magnitude < 0.01 then return end
	horizontalDir = horizontalDir.Unit
	local pos = ball.Position
	local desiredOffset = Config.KICK_LAUNCH_FORWARD_OFFSET

	local travelDistance = desiredOffset
	local result = workspace:Raycast(pos, horizontalDir * desiredOffset, nudgeRaycastParams)
	if result then
		travelDistance = math.max(result.Distance - 0.5, 0) -- para um pouco antes do obstáculo, nunca dentro dele
	end
	if travelDistance < 0.01 then return end

	ball.Position = pos + horizontalDir * travelDistance
end

-- ===== BRILHO DE IFRAME (finta e mergulho de goleiro) =====
-- Indica visualmente uma janela de invencibilidade/ação ativa (a finta já
-- é literalmente chamada de "janela de iframe" no código: enquanto ela
-- dura, um carrinho contra esse jogador falha automaticamente, ver
-- resolveStealAttempt).
--
-- IMPORTANTE: isso NÃO cria um segundo Highlight separado em cima do
-- "TeamHighlight" (PlayerSystems.lua) — ter dois Highlights ao mesmo
-- tempo no mesmo personagem é o que causava o bug reportado (a cor do
-- time sumindo e não voltando depois da finta). Em vez disso, a gente
-- guarda a cor/transparência ORIGINAL do TeamHighlight, pinta ele de
-- branco durante o iframe, e restaura exatamente o que tinha antes
-- quando o iframe termina (ou recalcula a cor do time, se por algum
-- motivo não tiver o snapshot salvo).
-- ⚠️ v45 — PEDIDO: "não quero esses highlights padrão de ForceField, e de
-- mudar a cor do personagem. Cria um highlight próprio, de um jeito
-- diferente. Sei lá, piscar alguma coisa."
--
-- Este aqui pintava o personagem inteiro de branco (FillTransparency 0.35),
-- apagando o uniforme. Agora é uma AURA DE CONTORNO que estroboa rápido —
-- que é justamente a leitura de "invencível/fora de fase". Toda a mecânica
-- de pulso e a explicação completa estão em ReplicatedStorage/AbilityAura.
--
-- Some também o snapshot/restauração do TeamHighlight: a aura é uma
-- Instance SEPARADA, então ela nasce e morre sem nunca encostar no
-- highlight de time — era esse vai-e-volta de propriedades que deixava o
-- personagem preso na cor errada quando duas coisas se sobrepunham.
local IFRAME_AURA = "PulseIframeAura"

local function setIframeGlow(player, enabled)
	local character = player.Character
	if not character then return end
	if enabled then
		AbilityAura.Apply(character, IFRAME_AURA, "Iframe")
	else
		AbilityAura.Clear(character, IFRAME_AURA)
	end
end

-- ===== ⚠️ IFRAME DE PULSO (v3) =====
-- Regra nova (pedido do usuário): um Pulso com wind-up LONGO deixa o
-- jogador parado/exposto tempo demais pra ser justo, então ele fica
-- INVULNERÁVEL a desarme/roubo durante todo o wind-up. Quem decide isso
-- é o PulseController (regra genérica: wind-up total >
-- Config.PULSE_IFRAME_MIN_WINDUP, ou o campo Iframe = true na definição
-- do Pulso) — aqui só ficam a tabela de estado, o feedback visual e a
-- consulta que o resto do arquivo usa (ver resolveStealAttempt).
-- A chave de Effect "SelfIframe" (segundos) usa exatamente o mesmo
-- caminho, só que concedida no instante em que a ação resolve.
--
-- Reaproveita o setIframeGlow ACIMA (que pinta o TeamHighlight já
-- existente e restaura a cor original depois) — NÃO cria um segundo
-- Highlight, que é justamente o bug que aquele comentário documenta.
local pulseIframe = {} -- [player] = tick() em que o iframe expira

_G.GrantPulseIframe = function(player, duration)
	if not player or not duration or duration <= 0 then return end
	local expiresAt = tick() + duration
	if not pulseIframe[player] or expiresAt > pulseIframe[player] then
		pulseIframe[player] = expiresAt
	end
	setIframeGlow(player, true)
end

_G.HasPulseIframe = function(player)
	local expiresAt = pulseIframe[player]
	return expiresAt ~= nil and tick() < expiresAt
end

RunService.Heartbeat:Connect(function()
	for player, expiresAt in pairs(pulseIframe) do
		if tick() >= expiresAt then
			pulseIframe[player] = nil
			-- Só apaga o brilho se NENHUMA outra janela de iframe estiver
			-- rolando ao mesmo tempo (finta ou mergulho de goleiro) — senão
			-- o Pulso apagaria o brilho de uma finta que ainda está ativa.
			if not dribbleMoves[player] and not diving[player] then
				setIframeGlow(player, false)
			end
		end
	end
end)

local loadedAnimationTracks = {}
-- ⚠️ v58 — `ajustarPara` (opcional): duração, em segundos, que a animação
-- DEVE ocupar. Quando informada, a velocidade de reprodução é calculada pra
-- ela caber exatamente nessa janela (AdjustSpeed = duração real / alvo).
--
-- POR QUE ISSO EXISTE: a animação e a mecânica são feitas em lugares
-- diferentes e quase nunca batem no mesmo número. O carrinho é o caso vivo:
-- a janela mecânica é 0.5s (TACKLE_DASH_DURATION) e a animação exportada
-- veio com 0.833s — 25 frames a 30fps. Sem isto, ela seria cortada no meio
-- (o jogador já resolveu o lance com o corpo ainda no ar) ou continuaria
-- tocando depois do lance acabar.
--
-- Amarrando a animação à mecânica, mexer no tempo do carrinho no Config
-- reajusta o vídeo sozinho, e reexportar a animação com outra duração
-- também — nenhum dos dois lados precisa saber do outro.
--
-- ⚠️ v86 — `reverso` (opcional): toca a animação DE TRÁS PRA FRENTE (começa
-- no último quadro, velocidade negativa). PEDIDO: "a animação do para frente
-- é só você fazer a animação do para trás, só que no reverse" — é o drible
-- pra frente, que reaproveita o Dribble.Back.
-- ⚠️ v96 — ANIMAÇÃO POR CÓDIGO (Config.ANIMACAO_PROCEDURAL). O servidor
-- não toca mais asset nenhum no corpo: traduz a animação pedida pro NOME da
-- ação ("Kick", "Dribble.Left", "GKDive.Up"...) e avisa todos os clientes
-- (Remotes.AcaoAnimada); o AnimadorProcedural de cada um anima. Assim nenhum
-- chamador precisou mudar — continuam pedindo pelo ID do Config.
local nomeDaAnimacao = {} -- [animationId normalizado] = nome da ação
do
	for chave, valor in pairs(Config.ANIMATIONS) do
		if type(valor) == "table" then
			for sub, id in pairs(valor) do
				local n = Config.NormalizeAnimationId(id)
				if type(n) == "string" and n ~= "" then nomeDaAnimacao[n] = chave .. "." .. sub end
			end
		else
			local n = Config.NormalizeAnimationId(valor)
			if type(n) == "string" and n ~= "" then nomeDaAnimacao[n] = chave end
		end
	end
end

local function avisarAcao(model, nome, duracao, parametros)
	if model and nome then
		Remotes.AcaoAnimada:FireAllClients(model, nome, duracao, parametros)
		-- ⚠️ v103: vai pro replay também (o fantasma repete a ação)
		local ator = idDoAtorReplay(model)
		if ator then
			_G.RegistrarEventoReplay("Acao", { ator = ator, chave = nome, dur = duracao, params = parametros })
		end
	end
end
-- Pra quem não é jogador (goleiro bot) ou pra ações sem ID no Config.
_G.AnimarAcao = avisarAcao

local function playAnimation(player, animationId, priority, ajustarPara, semLoop, congelarNoFim, reverso, nomeAcao)
	-- ⚠️ FIX: normaliza (aceita colar só o número, sem "rbxassetid://" na
	-- frente — ver Config.NormalizeAnimationId em FootballConfig.luau).
	animationId = Config.NormalizeAnimationId(animationId)

	if Config.ANIMACAO_PROCEDURAL then
		local nome = nomeAcao or (animationId and nomeDaAnimacao[animationId])
		if nome == "Dribble.Back" and reverso then nome = "Dribble.Forward" end
		-- o preparo do chute o animador lê direto do atributo KickCharging
		if nome and nome ~= "PrepareKick" then
			avisarAcao(player.Character, nome, ajustarPara)
		end
		return
	end

	if not animationId or animationId == "" then return end

	local _, _, humanoid = getCharacterParts(player)
	if not humanoid then return end

	-- ⚠️ v17: carrega pelo ANIMATOR, não pelo Humanoid. Humanoid:LoadAnimation
	-- está deprecated desde 2020 e é a causa nº1 de "a animação não toca"
	-- reportada no fórum do Roblox — em rig sem Animator ele nem sempre cria
	-- um, e a chamada falha silenciosamente. O Animator é criado aqui se não
	-- existir (personagem de jogador normalmente já vem com um).
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- ⚠️ v59 FIX — "o carrinho só funciona uma vez, depois dá erro".
	--
	-- O cache guardava as tracks direto e validava com `track.Animator ~=
	-- animator`. Só que **AnimationTrack NÃO TEM a propriedade Animator** —
	-- ler ela lança "Animator is not a valid member of AnimationTrack".
	--
	-- Por que só quebrava na SEGUNDA vez: na primeira, `cache[animationId]`
	-- é nil, `not track` já dá true e o `or` curto-circuita — a propriedade
	-- inexistente nunca chega a ser lida. Da segunda em diante a track existe,
	-- `not track` é false, e aí ele tenta ler e explode.
	--
	-- E por que só apareceu agora: até hoje ANIMATIONS.Tackle estava VAZIA,
	-- então playAnimation saía na checagem de id lá em cima e essa linha
	-- nunca rodava duas vezes pro mesmo id. Preencher o id acordou um bug que
	-- já estava aí.
	--
	-- A INTENÇÃO original era certa: invalidar o cache quando o personagem
	-- renasce (Animator novo), senão as tracks antigas apontam pra um corpo
	-- que não existe mais. Agora o Animator é guardado JUNTO do cache, que é
	-- onde essa informação de fato existe.
	local cacheEntry = loadedAnimationTracks[player]
	if not cacheEntry or cacheEntry.Animator ~= animator then
		cacheEntry = { Animator = animator, Tracks = {} }
		loadedAnimationTracks[player] = cacheEntry
	end
	local cache = cacheEntry.Tracks

	local track = cache[animationId]
	if not track then
		local animation = Instance.new("Animation")
		animation.AnimationId = animationId
		local ok, loadedTrack = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if not ok or not loadedTrack then
			warn(("Não consegui carregar a animação %s para %s: %s"):format(animationId, player.Name, tostring(loadedTrack)))
			return
		end
		track = loadedTrack
		cache[animationId] = track
	end

	track.Priority = priority or Enum.AnimationPriority.Action
	-- ⚠️ v60/v64: várias animações vêm marcadas como Looped no editor mesmo
	-- sendo de ação ÚNICA — o Kick e as TRÊS de drible vieram assim. Sem
	-- isto elas repetem pra sempre depois do lance acabar.
	--
	-- No drible isso era especialmente ruim e foi o bug do "depois de driblar
	-- a animação buga e não volta pro idle": o drible está em Action2, ACIMA
	-- do movimento, então uma finta em loop ficava cobrindo andar e idle pra
	-- sempre. Não era conflito entre driblar e andar — era a finta que nunca
	-- terminava.
	-- (setado aqui E de novo depois da carga — ver o comentário logo abaixo:
	-- antes da carga esse valor é sobrescrito pelo asset.)
	if semLoop or congelarNoFim then track.Looped = false end
	track:Play()

	-- ⚠️ v86: a MESMA track serve o drible pra trás (normal) e pra frente
	-- (reverso), então a velocidade precisa ser reafirmada nos dois sentidos —
	-- senão um Back tocado depois de um Forward sairia ao contrário.
	local function velocidadeAlvo()
		local v = (ajustarPara and ajustarPara > 0 and track.Length > 0) and (track.Length / ajustarPara) or 1
		return reverso and -v or v
	end
	local function aplicarSentido()
		if reverso and track.Length > 0 then
			track.TimePosition = math.max(track.Length - 0.03, 0)
		end
		track:AdjustSpeed(velocidadeAlvo())
	end
	if track.Length > 0 then
		aplicarSentido()
	elseif not reverso then
		track:AdjustSpeed(1)
	end

	-- ⚠️ v67 — REESCRITO. Tudo que depende da animação já ter CARREGADO mora
	-- numa thread só, depois de esperar a carga de verdade.
	--
	-- A CAUSA DOS DOIS BUGS ("a PrepareKick voltou a dar loop" e "correndo, a
	-- corrida prevalece sobre o chute na primeira vez"): no Roblox, quando o
	-- asset da animação termina de carregar, ele SOBRESCREVE o
	-- AnimationTrack.Looped com o valor que ficou marcado no editor. Então
	-- setar Looped = false ANTES da carga não adianta nada na PRIMEIRA
	-- execução — o asset chega depois e devolve o loop. Como todas as nossas
	-- animações de ação vieram marcadas como Looped, a primeira execução de
	-- cada uma saía errada; da segunda em diante (já em cache) funcionava, e
	-- era por isso que parecia intermitente.
	--
	-- Pelo mesmo motivo a primeira execução parecia "não acontecer": sem os
	-- keyframes carregados não há pose nenhuma pra mostrar, e o que estava
	-- por baixo (a corrida) continuava aparecendo.
	--
	-- Agora Looped é reafirmado DEPOIS da carga, junto com o ajuste de
	-- velocidade e o congelamento no último frame.
	if semLoop or congelarNoFim or reverso or (ajustarPara and ajustarPara > 0) then
		task.spawn(function()
			local esperou = 0
			local jaCarregada = track.Length > 0
			while track.Length <= 0 and esperou < 2 do
				task.wait(0.05)
				esperou += 0.05
			end
			if track.Length <= 0 then return end

			-- reafirma DEPOIS da carga (ver o comentário acima)
			if semLoop or congelarNoFim then track.Looped = false end

			if not jaCarregada then
				aplicarSentido() -- primeira execução: só agora dá pra saber a duração
			end

			-- ⚠️ v86: tocando ao contrário, ela chega no quadro 0 e o Roblox nem
			-- sempre encerra sozinho nesse sentido — encerra na mão no fim da
			-- janela (só se ainda estiver indo ao contrário, ou seja, se ninguém
			-- reaproveitou a track pra tocar pra frente nesse meio tempo).
			if reverso then
				task.wait(math.abs(track.Length / velocidadeAlvo()))
				if track.IsPlaying and track.Speed < 0 then track:Stop(0.1) end
			end

			-- Congela no último frame: a track continua tocando (por isso a
			-- pose se mantém), só que parada, até alguém dar Stop. Para uma
			-- pitadinha ANTES do fim porque chegando a 100% ela encerra
			-- sozinha e a pose seria descartada.
			if congelarNoFim and track.IsPlaying then
				local restante = track.Length - track.TimePosition - 0.02
				if restante > 0 then task.wait(restante) end
				if track.IsPlaying then track:AdjustSpeed(0) end
			end
		end)
	end
end

-- ⚠️ v60: contrapartida do playAnimation. A animação de PREPARO do chute
-- fica em loop enquanto o jogador segura o botão, então precisa de alguém
-- que a encerre — as de ação única param sozinhas.
local function stopAnimation(player, animationId, fade)
	animationId = Config.NormalizeAnimationId(animationId)
	if not animationId or animationId == "" then return end
	if Config.ANIMACAO_PROCEDURAL then -- ⚠️ v96: ver playAnimation
		local nome = nomeDaAnimacao[animationId]
		if nome and nome ~= "PrepareKick" then
			avisarAcao(player.Character, "parar:" .. nome)
			if nome == "Dribble.Back" then avisarAcao(player.Character, "parar:Dribble.Forward") end
		end
		return
	end
	local entrada = loadedAnimationTracks[player]
	local track = entrada and entrada.Tracks and entrada.Tracks[animationId]
	if track then
		pcall(function() track:Stop(fade or 0.1) end)
	end
end

-- ⚠️ v63 — uma animação de drible POR DIREÇÃO (ver ANIMATIONS.Dribble).
-- Aceita os dois formatos: a tabela por direção (formato novo) ou uma string
-- só (formato antigo), pra não quebrar se alguém voltar a pôr uma única.
-- Sem direção conhecida — ou direção sem animação própria — cai no "Back",
-- que é a finta mais neutra das três.
local function dribbleAnimationFor(nomeDirecao)
	local conf = Config.ANIMATIONS.Dribble
	if type(conf) == "string" then return conf end
	if type(conf) ~= "table" then return "" end
	return conf[nomeDirecao] or conf.Back or ""
end

-- ⚠️ v65 — uma animação de mergulho POR DIREÇÃO. Os nomes são os mesmos que
-- o GKInput manda (Left/Right/Up/UpLeft/UpRight, teclas Z/C/X/Q/E). Todas já
-- incluem a levantada no final, então não existe animação de recuperação
-- separada. Sem direção conhecida, cai no "Up" (o mergulho mais neutro).
local function gkDiveAnimationFor(nomeDirecao)
	local conf = Config.ANIMATIONS.GKDive
	if type(conf) == "string" then return conf end
	if type(conf) ~= "table" then return "" end
	return conf[nomeDirecao] or conf.Up or ""
end

local lastReceiveTime = {} -- [player] = tick() de quando ganhou a posse (precisa vir ANTES de setOwner, que já usa)

-- ⚠️ v5.6: PEDIDO — "se eu passar muito fraco, eu simplesmente domino a
-- bola novamente no ar". Sem isto, um passe fraco (velocidade baixa o
-- bastante pra entrar em LOOSE_BALL_PICKUP_MAX_SPEED) deixava o PRÓPRIO
-- chutador elegível pro pickup passivo (heartbeat abaixo) no instante
-- seguinte — ele "recebia de volta" o próprio passe fraco sem ninguém
-- mais tocar na bola. Trava só o CHUTADOR (qualquer outro jogador,
-- companheiro ou adversário, continua podendo pegar normalmente) por uma
-- janela curta a partir do chute.
local SELF_PICKUP_LOCK_SECONDS = 0.35
local selfPickupLockUntil = {} -- [player] = tick() até quando ELE MESMO não pode pegar a própria bola de volta pelo pickup passivo

-- ⚠️ v12 — CONTEXTO PRA OS INSTINTOS NOVOS (ver Data.Instincts):
-- teamPassChain  = quantos passes SEGUIDOS o time trocou sem perder a bola
--                  (Instinto "Tabela"). Zera quando a posse troca de time.
-- possessionSince = desde quando ESTE jogador está com a bola sem largar
--                  (Instinto "A Zona"). Zera sozinho ao perder a posse,
--                  porque setOwner só é chamado quando alguém ganha.
local teamPassChain = {}    -- [teamName] = número de passes seguidos
local possessionSince = {}  -- [player] = tick() em que ele ganhou a bola

-- ⚠️ v104 — BOLA NOS PÉS (ver Config.BOLA_NOS_PES_*). Com a posse, a física
-- da bola passa pro cliente de quem está com ela: ele a coloca na frente dos
-- pés todo quadro (BolaNosPes.local.luau) e o resto do servidor a vê já
-- colada no corpo dele (os dois chegam pela MESMA conexão, então os outros
-- jogadores também veem bola e corpo juntos). Sem posse, a bola é SEMPRE do
-- servidor — chute, voo de Hissatsu, curva, tudo continua calculado aqui.
local bolaNoClienteDesde = nil -- tick() em que a rede foi entregue ao dono atual (nil = servidor)
local bolaRetomadaAte = 0      -- servidor segurou a bola (bola longe demais) até esse tick()

local function definirDonoDeRede(player)
	if ball.Anchored then return false end
	local ok = pcall(function()
		if player and Config.BOLA_NOS_PES_LIGADO then
			ball:SetNetworkOwner(player)
		else
			ball:SetNetworkOwner(nil)
		end
	end)
	if ok and player and Config.BOLA_NOS_PES_LIGADO then
		bolaNoClienteDesde = bolaNoClienteDesde or tick()
	else
		bolaNoClienteDesde = nil
	end
	return ok
end

local function bolaEstaNoCliente(player)
	if not Config.BOLA_NOS_PES_LIGADO or not player or ball.Anchored then return false end
	local ok, dono = pcall(function() return ball:GetNetworkOwner() end)
	return ok and dono == player
end

local function setOwner(player)
	local previousOwner = owner
	owner = player
	bolaNoClienteDesde = nil
	if tick() >= bolaRetomadaAte then definirDonoDeRede(player) end
	if player then
		pushToucher(player)
		lastReceiveTime[player] = tick()
		possessionSince[player] = tick()

		-- ⚠️ Comparação de time feita INLINE de propósito: areOpponents/
		-- otherTeamName só são declaradas bem mais abaixo neste arquivo, e
		-- chamá-las daqui pegaria um global nil (setOwner roda toda vez que
		-- alguém domina a bola — seria erro em todo lance).
		local teamName = player.Team and player.Team.Name
		if teamName then
			local sameTeamPass = previousOwner ~= nil
				and previousOwner ~= player
				and previousOwner.Team ~= nil
				and previousOwner.Team == player.Team
			if sameTeamPass then
				teamPassChain[teamName] = (teamPassChain[teamName] or 0) + 1
				-- ⚠️ v67 — CARGA DO FLOW: passe que CHEGOU num companheiro.
				-- Este é o lugar certo porque aqui já se sabe que a bola MUDOU DE
				-- MÃOS dentro do time — exatamente a regra pedida. E "pegar de
				-- volta depois de ter passado pelo seu próprio domínio não vale de
				-- nada" sai de graça: previousOwner ~= player já é condição do
				-- sameTeamPass.
				if _G.NotifyFlowPass then _G.NotifyFlowPass(previousOwner, player) end
			elseif previousOwner ~= player then
				-- Veio de adversário ou de bola solta: sequência recomeça.
				teamPassChain[teamName] = 0
				-- ⚠️ v67: se veio de um ADVERSÁRIO (carrinho, interceptação,
				-- roubo), isso é "domínio de outra pessoa que passa a ser seu" e
				-- carrega Flow. Bola solta não carrega: ninguém foi desarmado.
				local deAdversario = previousOwner ~= nil
					and previousOwner.Team ~= nil
					and previousOwner.Team ~= player.Team
				if deAdversario and _G.NotifyFlowSteal then
					_G.NotifyFlowSteal(player)
				end
			end
			-- Qualquer troca de posse derruba a sequência de quem não está
			-- com a bola (sem precisar saber o nome do time adversário).
			for otherName in pairs(teamPassChain) do
				if otherName ~= teamName then teamPassChain[otherName] = 0 end
			end
		end

		endKickClearance() -- ⚠️ v20: alguém dominou a bola — o lance acabou, colisão normal de volta

		-- ⚠️ v23: o quique amortecido do lançamento longo do goleiro vale só
		-- ATÉ ALGUÉM DOMINAR. Dominou, a bola volta a quicar normal — o
		-- amortecimento nunca "vaza" pro resto da partida. Chamado pelo _G.
		-- porque restoreBallBounce é declarado bem mais abaixo neste arquivo.
		if _G.RestoreBallBounce then _G.RestoreBallBounce() end
	end
	Remotes.PossessionChanged:FireAllClients(player, true)

	-- ⚠️ v15: alguém DIFERENTE do último chutador pegou a bola de verdade
	-- — a "posse" do lance mudou de mãos, então a auto-imunidade do
	-- chutador anterior não faz mais sentido (a bola já não é mais "o
	-- chute dele" pra fins de corpo-bloqueia-corpo). Ver BODY_BLOCK acima.
	if player and player ~= recentKicker then
		kickerClearedBody = true
	end
end

local function releaseOwner()
	-- ⚠️ v113 (depuração): workspace.RastrearPosse = true escreve no log QUEM soltou a posse
	if owner and workspace:GetAttribute("RastrearPosse") then
		warn("[RastrearPosse] soltou a bola de " .. owner.Name .. string.char(10) .. debug.traceback("", 2))
	end
	if owner then
		-- ⚠️ v105: largou a bola — sai das mãos do goleiro
		owner:SetAttribute("BolaNaMao", nil)
		if owner.Character then owner.Character:SetAttribute("BolaNaMao", nil) end
		Remotes.PossessionChanged:FireAllClients(owner, false)
		if dribbleMoves[owner] then setIframeGlow(owner, false) end
		dribbleMoves[owner] = nil
	end
	owner = nil
	definirDonoDeRede(nil) -- ⚠️ v104: sem posse, a bola volta a ser do servidor NA HORA (o chute sai daqui)
end

-- ===== GRAVIDADE E FÍSICA DA BOLA =====
-- PhysicalProperties customizadas — o padrão do Roblox não foi pensado
-- pra bola de futebol (quica demais e desliza indefinidamente no chão).
ball.CustomPhysicalProperties = PhysicalProperties.new(
	Config.BALL_PHYSICAL_PROPERTIES.Density,
	Config.BALL_PHYSICAL_PROPERTIES.Friction,
	Config.BALL_PHYSICAL_PROPERTIES.Elasticity,
	Config.BALL_PHYSICAL_PROPERTIES.FrictionWeight,
	Config.BALL_PHYSICAL_PROPERTIES.ElasticityWeight
)

-- "Gravidade" mais leve SÓ pra bola, sem tocar em Workspace.Gravity (que
-- afetaria pulo/queda de todo mundo). Uma VectorForce numa Attachment no
-- centro da bola cancela uma fração da gravidade real a cada frame —
-- resultado: mais hang-time em cruzamentos/lançamentos/cabeçadas, mais
-- tempo pro efeito de curva atuar, sem mexer na física dos jogadores.
local gravityAttachment = Instance.new("Attachment")
gravityAttachment.Name = "GravityAttachment"
gravityAttachment.Parent = ball

local gravityForce = Instance.new("VectorForce")
gravityForce.Name = "BallGravityAssist"
gravityForce.Attachment0 = gravityAttachment
gravityForce.RelativeTo = Enum.ActuatorRelativeTo.World
gravityForce.ApplyAtCenterOfMass = true
gravityForce.Force = Vector3.new(0, 0, 0)
gravityForce.Parent = ball

-- ===== PULSO: VOO RETO SEM GRAVIDADE + TEXTO DA FORÇA =====
-- PEDIDO: chute/passe de Pulso (Hissatsu) vai RETO — sem nenhuma
-- gravidade desviando a trajetória — até a bola perder toda a velocidade
-- e parar de verdade. Só ligado pelo pulsePerformKick abaixo (chutes/
-- passes de PULSO), nunca pelo chute normal, que continua com a
-- gravidade parcial de sempre (Config.BALL_GRAVITY_MULTIPLIER).
local pulseStraightFlightActive = false

local pulseForceGui = Instance.new("BillboardGui")
pulseForceGui.Name = "PulseForceLabel"
pulseForceGui.Size = UDim2.new(0, 100, 0, 40)
pulseForceGui.StudsOffset = Vector3.new(0, 2.2, 0)
pulseForceGui.AlwaysOnTop = true
pulseForceGui.Enabled = false
pulseForceGui.Parent = ball

local pulseForceLabel = Instance.new("TextLabel")
pulseForceLabel.Name = "ForceText"
pulseForceLabel.BackgroundTransparency = 1
pulseForceLabel.Size = UDim2.new(1, 0, 1, 0)
pulseForceLabel.Font = Enum.Font.GothamBold
pulseForceLabel.TextScaled = true
pulseForceLabel.TextColor3 = Color3.fromRGB(255, 220, 60)
pulseForceLabel.TextStrokeTransparency = 0.3
pulseForceLabel.Text = ""
pulseForceLabel.Parent = pulseForceGui

-- ⚠️ v36 NOVO: "quero ver a força do chute diminuindo [com a distância], e
-- qualquer coisa que influencie a força vai alterar nisso". Antes esse
-- número era calculado UMA VEZ (na mira, não na distância de verdade
-- percorrida) e nunca mudava durante o voo. Essas variáveis guardam o
-- "estado ao vivo" do chute atual pra o Heartbeat mais abaixo (depois de
-- getPulseRangeFactor estar definida) recalcular o número TODO FRAME com
-- base na distância JÁ PERCORRIDA — só pra Pulsos de CHUTE de verdade
-- (que têm raridade/MaxRange); Pass/SetPiece continuam com o número fixo
-- de sempre (pulseFlightMaxRange fica nil pra eles).
local pulseFlightStartPos = nil
local pulseFlightBaseForce = nil        -- force final (já com raridade/range/chip) no instante do chute
local pulseFlightOriginalDistance = nil -- distância até o alvo mirado, no instante do chute
local pulseFlightMaxRange = nil         -- MaxRange da raridade desse Pulso (nil = sem decaimento ao vivo)
local pulseFlightOriginalFactor = nil   -- getPulseRangeFactor(distância original, MaxRange) — evita "pulo" no número no 1º frame
local pulseFlightExternalMult = 1       -- multiplicador extra (ex: Muralha interceptando no meio do voo — ver abaixo)
local pulseFlightBlockApplied = false
-- ⚠️ v37 FIX: guarda o ÚLTIMO número já mostrado nesse chute — trava
-- "ratchet" pra o número NUNCA subir de volta (ver comentário completo no
-- Heartbeat que recalcula pulseForceLabel, logo depois de
-- checkLivePulseBlockInterception).
local pulseFlightLastDisplayed = nil
-- ⚠️ NOVO: declarado AQUI (não só perto do Heartbeat que usa) por causa do
-- escopo léxico do Luau — startPulseStraightFlight (logo abaixo) também
-- precisa resetar essa variável a cada chute nova, e só enxerga locals já
-- declarados ANTES dele no arquivo.
local lastPulseForceDebugPrintAtTraveled = 0
-- ⚠️ v94: direção do voo reto, anotada no 1º quadro do voo (ver o Heartbeat
-- "Até a bola parar" mais abaixo, que encerra o voo se a bola for REBATIDA).
local pulseFlightDirecao = nil
-- ⚠️ v103: módulo da velocidade do voo, anotado junto com a direção (ver o
-- Heartbeat "Até a bola parar") — o voo MANTÉM essa velocidade até a força
-- (a vida da bola) chegar a 0.
local pulseFlightVelocidade = nil

-- ⚠️ v103: o número da vida da bola entra em cada amostra do replay
replayExtras.Forca = function()
	if not pulseForceGui.Enabled then return nil end
	local c = pulseForceLabel.TextColor3
	return { txt = pulseForceLabel.Text, r = c.R, g = c.G, b = c.B }
end

local function startPulseStraightFlight(force)
	pulseStraightFlightActive = true
	_G.VooCurvaInicial = nil -- ⚠️ v122 (ver CurvaInicial; _G por causa do limite de 200 locals)
	pulseFlightDirecao = nil
	pulseFlightVelocidade = nil
	pulseForceLabel.Text = tostring(math.floor(force))
	pulseForceGui.Enabled = true
	pulseFlightStartPos = ball.Position
	pulseFlightExternalMult = 1
	pulseFlightBlockApplied = false
	pulseFlightLastDisplayed = force -- ⚠️ NOVO: começa a trava (ratchet) já no valor inicial mostrado
	lastPulseForceDebugPrintAtTraveled = 0 -- ⚠️ NOVO: reseta o throttle do print de acompanhamento a cada novo chute
end

local function stopPulseStraightFlight()
	pulseStraightFlightActive = false
	pulseForceGui.Enabled = false
	pulseFlightStartPos = nil
	pulseFlightBaseForce = nil
	pulseFlightOriginalDistance = nil
	pulseFlightMaxRange = nil
	pulseFlightOriginalFactor = nil
	pulseFlightLastDisplayed = nil
end

-- ===== v41 — A FORÇA É A *VIDA* DA BOLA, NÃO A VELOCIDADE DELA =====
-- PEDIDO (depois de ver a defesa drenar 143 -> 11): "11 de força ainda é
-- movimento. Não dite essa força como velocidade propriamente dita — a
-- velocidade vai ser algo definido diferente, essa força é só a VIDA da
-- bola. A bola vai continuar andando na MESMA velocidade; nesse caso ela
-- entraria no gol de todo jeito."
--
-- O QUE ESTAVA ERRADO: quando a bola atravessava a guarda, ela saía do
-- congelamento com a velocidade zerada e ganhava um empurrãozinho fixo de
-- 12 studs/s em direção ao gol. Na prática ela "parava no ar" — a força
-- baixa estava, na marra, virando velocidade baixa. Mas drenar a força é
-- o goleiro tirando VIDA do chute, não freando a bola.
--
-- AGORA: a velocidade de antes do congelamento é guardada e devolvida
-- INTACTA (mesma direção, mesmo módulo), e o voo reto sem gravidade
-- recomeça com a força restante como nova vida. A bola segue o caminho
-- que estava fazendo e entra no gol — o que muda é quanta vida ela ainda
-- tem, que é o que o número sempre quis dizer.
local pulseGuardSavedVelocity = nil
local pulseGuardSavedMaxRange = nil

-- Chamado ANTES de congelar a bola numa defesa (nos dois goleiros).
local function capturePulseFlightForGuard()
	if ball.AssemblyLinearVelocity.Magnitude > 0.01 then
		pulseGuardSavedVelocity = ball.AssemblyLinearVelocity
	end
	pulseGuardSavedMaxRange = pulseFlightMaxRange
end

-- Chamado quando a bola ATRAVESSA a guarda, com a vida que sobrou.
local function resumePulseFlightAfterGuard(forcaRestante)
	-- v110: sem o alcance da raridade guardado o laço de decaimento não roda e a
	-- bola seguia reta com a força constante pra sempre (log do usuário: "PASSOU
	-- 173" e ela nunca mais perdeu força). Recupera do último chute de Pulso.
	if not pulseGuardSavedMaxRange then
		local info = _G.GetLastPulseShotInfo and _G.GetLastPulseShotInfo()
		pulseGuardSavedMaxRange = (info and info.Rarity and Config.PULSE_RARITY_MAX_RANGE[info.Rarity]) or 250
	end
	local velocidade = pulseGuardSavedVelocity
	pulseGuardSavedVelocity = nil
	if not velocidade or velocidade.Magnitude < 0.01 then return false end

	ball.Anchored = false
	ball.CanCollide = true
	ball.AssemblyLinearVelocity = velocidade

	-- Recomeça o voo reto (sem gravidade) com a vida que sobrou. O
	-- decaimento por distância continua do ponto atual: zera o marco de
	-- origem e usa a força restante como nova base, mantendo o MaxRange da
	-- raridade original.
	startPulseStraightFlight(forcaRestante)
	pulseFlightBaseForce = forcaRestante
	pulseFlightMaxRange = pulseGuardSavedMaxRange
	pulseGuardSavedMaxRange = nil
	pulseFlightDirecao = velocidade.Unit -- ⚠️ v110: segue na mesma reta travada
	pulseFlightVelocidade = velocidade.Magnitude
	return true
end

-- ===== v38 — FORÇA CAINDO EM TEMPO REAL DURANTE A DEFESA =====
-- PEDIDO: "mostre em tempo real, enquanto o goleiro estiver defendendo a
-- Hissatsu, a força da Hissatsu diminuindo" / "pode colocar a força
-- caindo em tempo real na defesa".
--
-- Até aqui o número só caía durante o VOO (por distância percorrida) e
-- congelava no instante em que a bola batia na guarda do goleiro — que é
-- justamente o momento mais importante, o "cabo de guerra" de Inazuma
-- Eleven onde o goleiro vai comendo a força do chute.
--
-- Como funciona: a bola já é CONGELADA nesse instante pelos dois
-- caminhos de defesa (goleiro humano via QTE de colisão, e agora também o
-- bot), então essa janela parada é exatamente onde a drenagem roda. O
-- número desce continuamente a um ritmo que vem do Físico do goleiro
-- (goleiro forte come a força mais rápido) e, quando a defesa resolve,
-- ele é fechado: PEGOU = cai até 0 (absorveu tudo), PASSOU = para no
-- valor drenado (a bola entra, mas "gasta" — dá pra ver o quanto perto o
-- goleiro chegou de segurar).
--
-- IMPORTANTE: isso NÃO decide nada. Quem decide pegou/não pegou continua
-- sendo a mesma regra de sempre (Físico vs força do chute + QTE / sorteio
-- do bot). A drenagem é a leitura desse duelo, e por isso é fechada com o
-- resultado já decidido em vez de tentar substituí-lo.
local guardDrainGeneration = 0
local PULSE_FORCE_COLOR_NORMAL = Color3.fromRGB(255, 220, 60)

local function guardDrainRate(physical)
	local fraction = math.clamp((physical or 0) / 100, 0, 1)
	return Config.PULSE_GUARD_DRAIN_MIN_PER_SECOND
		+ (Config.PULSE_GUARD_DRAIN_MAX_PER_SECOND - Config.PULSE_GUARD_DRAIN_MIN_PER_SECOND) * fraction
end

-- Começa a drenagem e devolve uma função `encerrar(pegou)` que fecha o
-- número (0 se pegou, o valor drenado se passou) e devolve quanto sobrou.
local function beginGuardForceDrain(forcaInicial, physical)
	guardDrainGeneration += 1
	local geracao = guardDrainGeneration

	local atual = math.max(forcaInicial or 0, 0)
	local ritmo = guardDrainRate(physical)

	pulseForceGui.Enabled = true
	pulseForceLabel.TextColor3 = Config.PULSE_GUARD_DRAIN_COLOR
	pulseForceLabel.Text = tostring(math.floor(atual))

	task.spawn(function()
		local ultimo = os.clock()
		while guardDrainGeneration == geracao and atual > 0 do
			task.wait()
			if guardDrainGeneration ~= geracao then break end
			local agora = os.clock()
			atual = math.max(atual - ritmo * (agora - ultimo), 0)
			ultimo = agora
			pulseForceLabel.Text = tostring(math.floor(atual))
		end
	end)

	return function(pegou)
		if guardDrainGeneration ~= geracao then return atual end
		guardDrainGeneration += 1 -- encerra o loop acima
		local minhaGeracao = guardDrainGeneration

		if pegou then atual = 0 end
		pulseForceLabel.Text = tostring(math.floor(atual))
		pulseForceLabel.TextColor3 = PULSE_FORCE_COLOR_NORMAL

		if Config.PULSE_FORCE_DEBUG_PRINTS then
			print(string.format(
				"🧤 [Defesa] força do chute drenada de %d para %d durante a defesa (ritmo %.0f/s) -> %s",
				math.floor(forcaInicial or 0), math.floor(atual), ritmo,
				pegou and "PEGOU" or "PASSOU"
			))
		end

		-- Deixa o resultado na tela um instante antes de sumir — sem isso
		-- o número pisca e some junto com a resolução, e não dá pra ler.
		task.delay(Config.PULSE_GUARD_DRAIN_LINGER_SECONDS, function()
			-- ⚠️ v41: se a bola ATRAVESSOU a guarda, o voo recomeçou e ela
			-- ainda está no ar com a vida que sobrou — a tag tem que
			-- continuar aparecendo (quem a esconde nesse caso é o fim do
			-- voo, stopPulseStraightFlight). Esconder aqui só vale quando o
			-- goleiro PEGOU: aí a jogada acabou mesmo.
			if guardDrainGeneration == minhaGeracao and not pulseStraightFlightActive then
				pulseForceGui.Enabled = false
			end
		end)

		return atual
	end
end

-- ⚠️ v103 — DUELO DE DEFESA (substitui a drenagem contínua acima nos dois
-- goleiros). PEDIDO: "o GK ao defender SUGA a vida da bola antes de fazer o
-- QTE... o que vai começar a dar dano é quantas vezes o defensor ou GK
-- acertarem a hissatsu deles". Na colisão a força CONGELA (o decaimento por
-- distância para porque o voo reto é encerrado) e só cai por ACERTO — cada
-- acerto tira um valor fixo (Config.DEFESA_DANO_POR_ACERTO) e o número pisca
-- na hora. No fim: força 0 = defendeu; sobrou = a bola retoma o voo com o que
-- sobrou e o decaimento por distância volta (resumePulseFlightAfterGuard).
local function iniciarDueloDeDefesa(forcaInicial)
	guardDrainGeneration += 1 -- encerra qualquer drenagem antiga pendurada
	local geracao = guardDrainGeneration
	local atual = math.max(forcaInicial or 0, 0)
	pulseForceGui.Enabled = true
	pulseForceLabel.TextColor3 = Config.PULSE_GUARD_DRAIN_COLOR
	pulseForceLabel.Text = tostring(math.floor(atual))

	local duelo = {}
	function duelo.Atual() return atual end
	function duelo.Dano(valor)
		if guardDrainGeneration ~= geracao then return atual end
		atual = math.max(atual - math.max(valor or 0, 0), 0)
		pulseForceLabel.Text = tostring(math.floor(atual))
		-- pisca branco no acerto
		pulseForceLabel.TextColor3 = Color3.new(1, 1, 1)
		task.delay(0.12, function()
			if guardDrainGeneration == geracao then
				pulseForceLabel.TextColor3 = Config.PULSE_GUARD_DRAIN_COLOR
			end
		end)
		if Config.PULSE_FORCE_DEBUG_PRINTS then
			print(string.format("🧤 [Duelo] acerto da defesa: -%d -> força %d", math.floor(valor or 0), math.floor(atual)))
		end
		return atual
	end
	-- ⚠️ v122: o impacto da mão/soco nunca zera o chute sozinho (ver
	-- Config.DEFESA_IMPACTO_MAX_DO_CHUTE)
	function duelo.Impacto(valor)
		local teto = math.max(forcaInicial or 0, 0) * (Config.DEFESA_IMPACTO_MAX_DO_CHUTE or 0.55)
		return duelo.Dano(math.min(math.max(valor or 0, 0), teto))
	end
	function duelo.Encerrar(defendeu)
		if guardDrainGeneration ~= geracao then return atual end
		guardDrainGeneration += 1
		local minhaGeracao = guardDrainGeneration
		if defendeu then atual = 0 end
		pulseForceLabel.Text = tostring(math.floor(atual))
		pulseForceLabel.TextColor3 = PULSE_FORCE_COLOR_NORMAL
		if Config.PULSE_FORCE_DEBUG_PRINTS then
			print(string.format("🧤 [Duelo] fim: força %d -> %d (%s)", math.floor(forcaInicial or 0), math.floor(atual), defendeu and "DEFENDEU" or "PASSOU"))
		end
		task.delay(Config.PULSE_GUARD_DRAIN_LINGER_SECONDS, function()
			if guardDrainGeneration == minhaGeracao and not pulseStraightFlightActive then
				pulseForceGui.Enabled = false
			end
		end)
		return atual
	end
	return duelo
end
_G.IniciarDueloDeDefesa = iniciarDueloDeDefesa

-- Exposto pro GKBotController usar a MESMA drenagem do goleiro humano —
-- sem isso o bot teria que duplicar o BillboardGui da bola, que vive aqui.
-- `_G.GetPulseLiveForce` entrega o número que está na tela nesse instante
-- (já com o decaimento por distância aplicado), que é de onde a drenagem
-- da defesa tem que partir.
_G.GetPulseLiveForce = function()
	return pulseFlightLastDisplayed
end
_G.BeginGuardForceDrain = beginGuardForceDrain
_G.CapturePulseFlightForGuard = capturePulseFlightForGuard
_G.ResumePulseFlightAfterGuard = resumePulseFlightAfterGuard

-- "Até a bola parar": sem gravidade nenhuma ela nunca ia "cair e parar"
-- sozinha, então quem encerra o voo reto é a velocidade caindo perto de
-- zero (fricção de rolagem normal quando encosta no chão) OU alguém
-- ganhar posse da bola (dribble assume o controle da velocidade dali pra
-- frente, não faz sentido continuar sem gravidade).
--
-- ⚠️ v94 — PEDIDO: "eu mirei no meio do gol, e a bola subiu pro travessão".
-- Medido: a Hissatsu entrou EXATAMENTE onde foi mirada (meio do gol), bateu
-- na rede do fundo e foi rebatida pra cima — e, como o voo reto continuava
-- ligado (sem gravidade), ela SUBIU por cima do travessão e ainda atravessou
-- o campo inteiro flutuando. O voo reto é a trajetória DO CHUTE; depois que a
-- bola é rebatida (rede, trave, defesa, corpo), ela não está mais nessa
-- trajetória. Então: se a direção mudar bruscamente (mais de ~60° em relação
-- à direção do chute), o voo acaba e a gravidade volta. A curva do chute
-- desvia só alguns graus, então não dispara isso.
-- ⚠️ v103 — PEDIDO (com o log: "força ao vivo 104" aos 105 studs e a bola
-- PAROU): "a força pode estar em 104, mas a bola simplesmente parou aí — ela
-- precisa prosseguir até a força chegar a 0". A Hissatsu rasteira encostava
-- no gramado e a frenagem de rolagem (e o atrito) matavam a VELOCIDADE com a
-- vida ainda alta. Agora, durante o voo, a velocidade do chute é MANTIDA
-- (mesmo módulo, na direção atual) e quem encerra o voo é a força zerar (ver
-- o Heartbeat da força ao vivo), a posse, ou a bola ser rebatida.
-- ⚠️ v105 — "se você chutar com uma Hissatsu pra fora, se por algum motivo a
-- bola for pra fora, ela perde totalmente a força". Limites do campo (a
-- hitbox) e as caixas dos gols (a boca do gol NÃO é "fora").
do -- ⚠️ v105: bloco próprio (o script bateu o limite de 200 locais no topo)
local campoVoo = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
local golsVoo = {}
for _, d in ipairs(workspace:GetDescendants()) do
	if d:IsA("BasePart") and d:GetAttribute("ScoringTeam") then table.insert(golsVoo, d) end
end
local function foraDoCampoNoVoo()
	if not campoVoo or not campoVoo:IsA("BasePart") then return false end
	local rel = campoVoo.CFrame:PointToObjectSpace(ball.Position)
	if math.abs(rel.X) <= campoVoo.Size.X / 2 + 1 and math.abs(rel.Z) <= campoVoo.Size.Z / 2 + 1 then
		return false
	end
	for _, gol in ipairs(golsVoo) do
		local rg = gol.CFrame:PointToObjectSpace(ball.Position)
		if math.abs(rg.X) <= gol.Size.X / 2 + 8 and math.abs(rg.Y) <= gol.Size.Y / 2 + 3 and math.abs(rg.Z) <= gol.Size.Z / 2 + 3 then
			return false -- entrando no gol
		end
	end
	return true
end
local pulseFlightDirAnterior = nil

RunService.Heartbeat:Connect(function()
	if not pulseStraightFlightActive then pulseFlightDirAnterior = nil return end
	if ball.Anchored then return end
	local velocidade = ball.AssemblyLinearVelocity
	if owner ~= nil then
		stopPulseStraightFlight()
		return
	end
	-- ⚠️ v105: saiu do campo = perde TODA a força (acaba o voo e a bola morre)
	if foraDoCampoNoVoo() then
		stopPulseStraightFlight()
		ball.AssemblyLinearVelocity = velocidade * 0.15
		pulseFlightDirAnterior = nil
		return
	end
	if not pulseFlightDirecao then
		if velocidade.Magnitude > 5 then
			pulseFlightDirecao = velocidade.Unit
			pulseFlightVelocidade = velocidade.Magnitude
		elseif velocidade.Magnitude < 2 then
			stopPulseStraightFlight()
		end
		return
	end
	-- ⚠️ v110 — MIRA TRAVADA. PEDIDO: "algumas Hissatsus de chute estão
	-- desobedecendo e não vão pro exato local onde eu mirei. Cria um ponto
	-- invisível na maior extremidade e a bola tem que ir até lá; traça o caminho
	-- até esse ponto e a bola NÃO PODE, de jeito nenhum, trocar de trajetória, a
	-- não ser que perca força — ou uma Hissatsu seja usada pra isso. Ela vai
	-- seguir até aquele ponto até a morte dela."
	-- A reta sai do ponto do chute (pulseFlightStartPos) na direção EXATA do
	-- ponto mirado (pulseFlightDirecao, travada no chute) e vai até o fim do
	-- alcance. Todo quadro a bola é recolocada NA reta, com a mesma velocidade —
	-- gramado, corpo, trave, curva, nada a tira dali. O voo só acaba quando a
	-- força zera (Heartbeat da força ao vivo), alguém domina, ela sai do campo ou
	-- uma defesa de Hissatsu segura (a bola fica ancorada no duelo). Se a reta
	-- entrar no gramado, a bola segue rente ao chão, na mesma direção.
	do
		local origem = pulseFlightStartPos or ball.Position
		local rapidez = pulseFlightVelocidade or velocidade.Magnitude
		local percorrido = math.max((ball.Position - origem):Dot(pulseFlightDirecao), 0)
		local naReta = origem + pulseFlightDirecao * percorrido
		local dir = pulseFlightDirecao
		-- ⚠️ v122 — CURVA INICIAL (Fúria Glacial: "uma leve curva e depois 100% reto na
		-- mira"): nos primeiros Comp studs a bola sai da reta numa barriga y = Amp·sen(πu)
		-- e VOLTA pra ela; depois disso é a reta travada de sempre até o ponto mirado.
		local ci = _G.VooCurvaInicial
		if ci and percorrido < ci.Comp then
			local u = percorrido / ci.Comp
			naReta += ci.Lado * (ci.Amp * math.sin(math.pi * u))
			dir = (pulseFlightDirecao + ci.Lado * (ci.Amp * math.pi / ci.Comp * math.cos(math.pi * u))).Unit
		end
		local raio = ball.Size.Y / 2
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local ignorar = { ball }
		for _, plr in ipairs(Players:GetPlayers()) do if plr.Character then table.insert(ignorar, plr.Character) end end
		params.FilterDescendantsInstances = ignorar
		local chao = workspace:Raycast(naReta + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), params)
		if chao and naReta.Y < chao.Position.Y + raio then
			naReta = Vector3.new(naReta.X, chao.Position.Y + raio, naReta.Z)
			local plano = Vector3.new(dir.X, 0, dir.Z)
			dir = plano.Magnitude > 0.05 and plano.Unit or dir
		end
		if (ball.Position - naReta).Magnitude > 0.05 then
			ball.CFrame = CFrame.new(naReta) * ball.CFrame.Rotation
		end
		ball.AssemblyLinearVelocity = dir * rapidez
		pulseFlightDirAnterior = dir
		return
	end
	-- ⚠️ v105: desvio BRUSCO num quadro só (tapa, corpo, trave) = rebatida —
	-- acaba o voo e a bola perde a velocidade do chute. Antes só um desvio de
	-- mais de 60° encerrava; um tapa de lado menor que isso seguia com a
	-- velocidade da Hissatsu mantida na direção nova, e ia embora pra fora.
	-- A curva do chute muda a direção devagar (poucos graus por segundo).
	if pulseFlightDirAnterior and velocidade.Magnitude > 1
		and velocidade.Unit:Dot(pulseFlightDirAnterior) < math.cos(math.rad(15)) then
		stopPulseStraightFlight()
		ball.AssemblyLinearVelocity = velocidade * 0.5
		pulseFlightDirAnterior = nil
		return
	end
	if velocidade.Magnitude > 1 then pulseFlightDirAnterior = velocidade.Unit end
	if velocidade.Magnitude < 0.5 or velocidade.Unit:Dot(pulseFlightDirecao) < 0.5 then
		stopPulseStraightFlight()
		return
	end
	if pulseFlightVelocidade and velocidade.Magnitude < pulseFlightVelocidade * 0.98 then
		ball.AssemblyLinearVelocity = velocidade.Unit * pulseFlightVelocidade
	end
end)
end -- do (v105)

-- Centro do campo, achado uma vez. Usado pelo resgate da bola logo abaixo.
-- Vem da hitbox do campo (a mesma que o resto do jogo usa pra saber onde o
-- campo fica); sem ela, o resgate simplesmente não roda — nunca chuta uma
-- posição inventada.
local campoCentro = nil
do
	local campo = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
	if campo then
		campoCentro = campo:IsA("BasePart") and campo.Position or campo:GetPivot().Position
	else
		warn("⚽ [Resgate] não achei a hitbox do campo ('" .. tostring(Config.FIELD_HITBOX_NAME) .. "') — o resgate da bola fugitiva fica desligado.")
	end
end

-- ⚠️ v67 — RESGATE DA BOLA FUGITIVA.
-- PEDIDO: "se a bola se distanciar demais do campo — alguém joga ela lá pra
-- cima e ela nunca para, ou vai pra um lugar onde a hitbox não pega — se ela
-- sair exorbitantemente pra longe, uns 2000 studs, ela volta pro centro do
-- mapa. Mesmo que fosse diretamente pra cima, volta pro centro, pros caras
-- pararem de abusar de bug."
--
-- Mede a distância em 3D (inclui a altura de propósito — foi decidido que
-- bola jogada reto pra cima também volta). Reaproveita _G.ResetBallState, o
-- mesmo caminho do kickoff, pra a bola voltar com dono limpo, velocidade
-- zerada e o estado de jogo consistente.
local ultimoResgateDaBola = 0

-- ⚠️ v84 — altura da SUPERFÍCIE do campo, medida uma vez por raycast no
-- centro (ignorando a própria bola). É o piso de referência do resgate por
-- queda logo abaixo — ver Config.BALL_VOID_RESCUE_DEPTH.
-- RespectCanCollide: a hitbox do campo (CampoHIT) é uma caixa ENORME e sem
-- colisão que vai muito acima do gramado — sem isso o raio batia no topo
-- dela (Y≈401) e o jogo achava que a bola, na grama, estava "abaixo do
-- campo". O raio parte da altura da bola (que nasce no gramado), no centro
-- do campo, e a medida só vale se ficar abaixo da bola.
local superficieDoCampoY = nil
if campoCentro then
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ball }
	params.RespectCanCollide = true
	local origem = Vector3.new(campoCentro.X, ball.Position.Y + 30, campoCentro.Z)
	local acerto = workspace:Raycast(origem, Vector3.new(0, -600, 0), params)
	if acerto and acerto.Position.Y <= ball.Position.Y + 5 then
		superficieDoCampoY = acerto.Position.Y
	else
		warn("⚽ [Resgate] não consegui medir o gramado no centro do campo — resgate por queda usando o limite de destruição do Roblox com folga.")
	end
end
-- Sem superfície medida, usa o limite de destruição do Roblox com folga —
-- pior caso ainda resgata antes da bola ser destruída.
local alturaMinimaDaBola = superficieDoCampoY and (superficieDoCampoY - Config.BALL_VOID_RESCUE_DEPTH)
	or (workspace.FallenPartsDestroyHeight + 100)
print(string.format("⚽ [Resgate] gramado em Y=%s — bola é resgatada se cair abaixo de Y=%.1f.", superficieDoCampoY and string.format("%.1f", superficieDoCampoY) or "?", alturaMinimaDaBola))

local function resgatarBola(motivo)
	ultimoResgateDaBola = tick()
	warn("⚽ [Resgate] " .. motivo .. " — devolvida pro centro.")
	if _G.ResetBallState then
		_G.ResetBallState(campoCentro + Vector3.new(0, Config.BALL_RESCUE_SPAWN_HEIGHT, 0))
	end
end

-- ⚠️ v87 — BOLA COM POSIÇÃO/VELOCIDADE INVÁLIDA (NaN). Num teste a bola
-- apareceu "a nan studs do centro" e, mesmo resgatada, sumiu do jogo: um
-- valor NaN na física faz o Roblox descartar a peça. Isso é checado TODO
-- quadro (sem a trava de 1s do resgate normal), antes de qualquer outra
-- coisa, e deixa a bola num estado limpo: voo de Hissatsu desligado, sem
-- âncora, sem velocidade, no centro. O aviso mostra o estado pra dar pra
-- achar a origem se acontecer de novo.
local function temNaN(v)
	return v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z
end

RunService.Heartbeat:Connect(function()
	if not campoCentro or not ball.Parent then return end
	local posicao, velocidade, giro = ball.Position, ball.AssemblyLinearVelocity, ball.AssemblyAngularVelocity
	if not (temNaN(posicao) or temNaN(velocidade) or temNaN(giro)) then return end
	warn(string.format("⚽ [Resgate] bola com valor inválido (pos=%s vel=%s giro=%s anchored=%s voo de Hissatsu=%s) — limpando.",
		tostring(posicao), tostring(velocidade), tostring(giro), tostring(ball.Anchored), tostring(pulseStraightFlightActive)))
	stopPulseStraightFlight()
	ball.Anchored = false
	ultimoResgateDaBola = tick()
	if _G.ResetBallState then
		_G.ResetBallState(campoCentro + Vector3.new(0, Config.BALL_RESCUE_SPAWN_HEIGHT, 0))
	end
end)

RunService.Heartbeat:Connect(function()
	if not campoCentro then return end
	if tick() - ultimoResgateDaBola < 1 then return end -- evita resgatar duas vezes seguidas

	-- Queda: checada TODO frame, porque em ~2s de queda livre a bola passa do
	-- limite de destruição do Roblox e some pra sempre.
	if ball.Position.Y < alturaMinimaDaBola then
		resgatarBola(string.format("a bola caiu abaixo do campo (Y=%.0f, limite %.0f)", ball.Position.Y, alturaMinimaDaBola))
		return
	end

	local distancia = (ball.Position - campoCentro).Magnitude
	if distancia < Config.BALL_RESCUE_DISTANCE then return end
	resgatarBola(string.format("a bola estava a %.0f studs do centro do campo (limite %.0f)", distancia, Config.BALL_RESCUE_DISTANCE))
end)

RunService.Heartbeat:Connect(function()
	local liftFraction = pulseStraightFlightActive and 1 or (1 - Config.BALL_GRAVITY_MULTIPLIER)
	if liftFraction <= 0 then
		gravityForce.Force = Vector3.new(0, 0, 0)
		return
	end
	-- ⚠️ v110 — CAUSA DA BOLA QUE SUMIA (achada na bateria da noite, gravando a
	-- bola quadro a quadro): com a bola ANCORADA (mão do goleiro, QTE, duelo de
	-- defesa) o AssemblyMass é INFINITO — a força virava infinita e, no quadro
	-- em que a bola era solta (arremesso do goleiro!), a física mandava ela pra
	-- Y = inf e o Roblox APAGAVA a bola do jogo. Usa a massa da própria peça
	-- (sempre finita) e zera a força enquanto ancorada.
	if ball.Anchored then
		gravityForce.Force = Vector3.zero
		return
	end
	gravityForce.Force = Vector3.new(0, ball:GetMass() * workspace.Gravity * liftFraction, 0)
end)

-- "Encostada no chão?" via raycast curto pra baixo — usado tanto pra
-- fricção de rolagem quanto pro amortecimento de giro logo abaixo. Sem
-- isso, aplicar fricção de rolagem também no ar mataria o arco de
-- lançamentos/cruzamentos/cabeçadas.
local ballRaycastParams = RaycastParams.new()
ballRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
ballRaycastParams.FilterDescendantsInstances = { ball }

local function isBallGrounded()
	local radius = ball.Size.Y / 2
	-- Tolerância generosa (1.5 studs além do raio) — melhor "grudar" a
	-- fricção de rolagem um pouco cedo demais numa quicada pequena do que
	-- perder o "grounded" por uma folga mínima e deixar a bola deslizando
	-- sem nenhuma frenagem. Fallback: mesmo se o raycast não pegar nada
	-- (chão irregular, degrau, etc), velocidade vertical baixa já indica
	-- que ela não está "no ar" de verdade (lançamento/cabeçada têm Y alto).
	local result = workspace:Raycast(ball.Position, Vector3.new(0, -(radius + 1.5), 0), ballRaycastParams)
	if result then return true end
	return math.abs(ball.AssemblyLinearVelocity.Y) < 2
end

-- Fricção de rolagem + amortecimento de giro: sem dono e encostada no
-- chão, a bola perde velocidade HORIZONTAL por segundo (Friction do
-- PhysicalProperties sozinho não segura bem numa esfera) e o GIRO
-- (AssemblyAngularVelocity) também é amortecido — sem isso o spin
-- realimenta o deslizamento e a bola parece "acelerar sozinha" mesmo
-- rolando devagar, encostada no chão. Dois níveis de decel de
-- velocidade: normal (rolagem de verdade) e "rápida" acima de
-- BALL_ROLLING_MAX_SPEED (chute forte ainda deslizando no chão) — só
-- mexe na horizontal, nunca no ar, pra não atrapalhar arco/quicada.
-- ⚠️ v97 — FÍSICA ARCADE. PEDIDO: "a bola está como uma bola de vida real...
-- às vezes erra pra um lado, vai pra trás, desliza demais, desvia do caminho
-- — quando ela está rotacionando e você acerta ela no chão, ela vai pra
-- direção que estava rotacionando. Não é pra ser assim. Aonde você estiver
-- mirando, clicou, é pra ser perfeito."
--
-- A CAUSA: o giro. A bola guardava qualquer rotação que ganhasse (do
-- drible, de um quique, de um corpo) e, quando encostava no chão, o atrito
-- convertia esse giro em movimento — daí o desvio "pra direção que estava
-- rotacionando", e às vezes pra trás (giro contrário ao movimento).
-- O CONSERTO: o giro deixa de ser livre. A cada quadro ele é exatamente o
-- de "rolar pra frente" na direção em que a bola anda (ω = cima × v / raio):
-- no chão isso é rolar sem escorregar (o atrito não tem o que converter), e
-- no ar a bola já chega girando certo — não sobra efeito nenhum pra desviar.
-- A curva de propósito (que era aplicada direto na velocidade) já foi tirada
-- dos chutes; o giro visual continua existindo, só que sempre coerente.
RunService.Heartbeat:Connect(function(dt)
	if owner then return end -- bola com dono: quem controla é o dribble/posse, não isso aqui
	if ball.Anchored then return end

	local raio = ball.Size.Y / 2
	local vel = ball.AssemblyLinearVelocity
	local horizontalGiro = Vector3.new(vel.X, 0, vel.Z)
	if raio > 0 then
		ball.AssemblyAngularVelocity = Vector3.yAxis:Cross(horizontalGiro) / raio
	end

	if not isBallGrounded() then return end
	-- ⚠️ v103: Hissatsu em voo não freia (ela vai até a força zerar)
	if pulseStraightFlightActive then return end

	local velocity = ball.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontal.Magnitude
	if speed <= 0.05 then return end

	local decelRate = (speed > Config.BALL_ROLLING_MAX_SPEED)
		and Config.BALL_ROLLING_FAST_DECELERATION
		or Config.BALL_ROLLING_DECELERATION
	-- ⚠️ v103: + frenagem proporcional à velocidade (bola longa desliza menos)
	decelRate += (Config.BALL_ROLLING_ARRASTO or 0) * speed
	local newSpeed = math.max(0, speed - decelRate * dt)
	local newHorizontal = (newSpeed > 0) and (horizontal.Unit * newSpeed) or Vector3.new(0, 0, 0)
	ball.AssemblyLinearVelocity = Vector3.new(newHorizontal.X, velocity.Y, newHorizontal.Z)
end)

-- ===== STUN =====
local stunnedUntil = {}
local preStunWalkSpeed = {}

local function stunPlayer(player, duration)
	if not duration or duration <= 0 then return end
	if _G.GetInstinctStunMult then duration *= _G.GetInstinctStunMult(player) end -- ⚠️ v111: Defesa Zumbi
	local _, _, humanoid = getCharacterParts(player)
	if not humanoid then return end

	local expiresAt = tick() + duration
	if not stunnedUntil[player] or expiresAt > stunnedUntil[player] then
		stunnedUntil[player] = expiresAt
	end
	if preStunWalkSpeed[player] == nil then
		preStunWalkSpeed[player] = humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = 0
end

local function isStunned(player)
	local expiresAt = stunnedUntil[player]
	return expiresAt ~= nil and tick() < expiresAt
end

-- ===== RAGDOLL PRÓPRIO (funciona em QUALQUER rig, R6 ou R15) =====
-- O Ragdoll nativo do Roblox (Humanoid:ChangeState(Enum.HumanoidStateType.
-- Ragdoll)) só converte automaticamente em rigs R15 — em R6 não faz nada.
-- Pra funcionar "pro geral" sem depender do tipo de rig, esse sistema faz
-- o ragdoll na mão: desliga cada Motor6D (a "junta" que normalmente
-- prende os membros nas posições da animação) e liga uma
-- BallSocketConstraint solta no lugar — o corpo vira física pura e cai
-- sozinho. Depois do tempo, desfaz tudo e devolve o controle.
local ragdollState = {} -- [player] = { expiresAt, constraints = {Instance}, motors = {Motor6D} }

local function restoreFromRagdoll(player, expectedExpiresAt)
	local state = ragdollState[player]
	if not state then return end
	if state.expiresAt ~= expectedExpiresAt then return end -- foi esticado por um ankle breaker mais novo — a chamada dele que vai restaurar

	for _, obj in ipairs(state.constraints) do
		if obj and obj.Parent then obj:Destroy() end
	end
	for _, motor in ipairs(state.motors) do
		if motor and motor.Parent then motor.Enabled = true end
	end

	local _, _, humanoid = getCharacterParts(player)
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.AutoRotate = true
	end
	ragdollState[player] = nil
end

local function ragdollPlayer(player, duration)
	if not duration or duration <= 0 then return end
	local character, _, humanoid = getCharacterParts(player)
	if not character or not humanoid then return end

	local existing = ragdollState[player]
	if existing then
		-- já ragdollado (outro ankle breaker pegou de novo nesse meio
		-- tempo) — só estica a duração, não duplica constraint em cima
		-- de constraint.
		local expiresAt = tick() + duration
		existing.expiresAt = expiresAt
		task.delay(duration, function()
			restoreFromRagdoll(player, expiresAt)
		end)
		return
	end

	humanoid.PlatformStand = true -- desliga o controlador do Humanoid, física manda no corpo
	humanoid.AutoRotate = false

	local constraints, motors = {}, {}
	for _, motor in ipairs(character:GetDescendants()) do
		if motor:IsA("Motor6D") and motor.Part0 and motor.Part1 then
			local a0 = Instance.new("Attachment")
			a0.Name = "RagdollA0"
			a0.CFrame = motor.C0
			a0.Parent = motor.Part0

			local a1 = Instance.new("Attachment")
			a1.Name = "RagdollA1"
			a1.CFrame = motor.C1
			a1.Parent = motor.Part1

			local socket = Instance.new("BallSocketConstraint")
			socket.Name = "RagdollSocket"
			socket.Attachment0 = a0
			socket.Attachment1 = a1
			socket.Parent = motor.Part0

			motor.Enabled = false

			table.insert(constraints, socket)
			table.insert(constraints, a0)
			table.insert(constraints, a1)
			table.insert(motors, motor)
		end
	end

	local expiresAt = tick() + duration
	ragdollState[player] = { expiresAt = expiresAt, constraints = constraints, motors = motors }
	task.delay(duration, function()
		restoreFromRagdoll(player, expiresAt)
	end)
end

RunService.Heartbeat:Connect(function()
	for player, expiresAt in pairs(stunnedUntil) do
		if tick() >= expiresAt then
			stunnedUntil[player] = nil
			local _, _, humanoid = getCharacterParts(player)
			if humanoid and preStunWalkSpeed[player] then
				humanoid.WalkSpeed = preStunWalkSpeed[player]
			end
			preStunWalkSpeed[player] = nil
		end
	end
end)

-- FIX: OutOfBoundsController chama _G.ClearStun pra "descongelar" na hora
-- todo mundo que não é o cobrador, assim que a cobrança de lateral/
-- escanteio/tiro de meta termina — mas essa função nunca existiu aqui.
-- Sem ela, quem não estava cobrando ficava travado (WalkSpeed=0) pelos
-- Config.SET_PIECE_TIME_LIMIT segundos inteiros (10s), mesmo que o
-- cobrador tivesse chutado a bola em 1 segundo.
local function clearStun(player)
	stunnedUntil[player] = nil
	local _, _, humanoid = getCharacterParts(player)
	if humanoid and preStunWalkSpeed[player] then
		humanoid.WalkSpeed = preStunWalkSpeed[player]
	end
	preStunWalkSpeed[player] = nil
end

-- ===== CONGELAMENTO (Pulso de gelo — ex: Fúria Glacial) =====
-- ⚠️ v36 NOVO: "faça cada pulso responder de acordo com o que realmente
-- faz, o de gelo precisa congelar as pessoas ao redor". Reaproveita o
-- mesmo stunPlayer de sempre pra travar o movimento (WalkSpeed=0, com toda
-- a segurança de restauração que ele já tem), e soma em cima: também zera
-- o pulo (JumpPower=0 — "congelado" não pula) e liga um contorno azul de
-- gelo (Highlight) enquanto durar, pra ficar visualmente diferente de um
-- Stun normal (atordoado ainda balança, congelado trava OLHANDO duro).
local frozenUntil = {}
local preFreezeJumpPower = {}
local freezeHighlights = {}

local function addFreezeVisual(player)
	local character = player.Character
	if not character then return end
	local existing = freezeHighlights[player]
	if existing and existing.Parent then return end
	-- ⚠️ v45: aura de contorno, SEM pulso e SEM pintar o corpo (ver
	-- AbilityAura). O congelado é o único que não pisca de propósito:
	-- atordoado balança, congelado trava — o contraste é a informação.
	local highlight = AbilityAura.Apply(character, "PulseFreezeAura", "Freeze")
	freezeHighlights[player] = highlight
end

local function removeFreezeVisual(player)
	-- ⚠️ v47: limpa pelos DOIS caminhos de propósito.
	-- `AbilityAura.Clear` acha a aura pelo NOME dentro do personagem ATUAL —
	-- é o que garante o "acabou, sumiu e voltou ao highlight padrão" mesmo
	-- se o personagem tiver renascido no meio do congelamento (aí a
	-- referência guardada na tabela aponta pra uma Instance de um corpo que
	-- não existe mais, e destruir ela não limparia o corpo novo).
	-- A tabela continua sendo limpa porque addFreezeVisual usa ela pra saber
	-- se já existe uma aura ativa.
	AbilityAura.Clear(player.Character, "PulseFreezeAura")
	local highlight = freezeHighlights[player]
	if highlight and highlight.Parent then highlight:Destroy() end
	freezeHighlights[player] = nil
end

local function freezePlayer(player, duration)
	if not duration or duration <= 0 then return end
	local _, _, humanoid = getCharacterParts(player)
	if not humanoid then return end

	stunPlayer(player, duration) -- congelado também não anda — reaproveita o stun de sempre

	local expiresAt = tick() + duration
	if not frozenUntil[player] or expiresAt > frozenUntil[player] then
		frozenUntil[player] = expiresAt
	end
	if preFreezeJumpPower[player] == nil then
		preFreezeJumpPower[player] = humanoid.JumpPower
	end
	humanoid.JumpPower = 0
	addFreezeVisual(player)
end

RunService.Heartbeat:Connect(function()
	for player, expiresAt in pairs(frozenUntil) do
		if tick() >= expiresAt then
			frozenUntil[player] = nil
			local _, _, humanoid = getCharacterParts(player)
			if humanoid and preFreezeJumpPower[player] then
				humanoid.JumpPower = preFreezeJumpPower[player]
			end
			preFreezeJumpPower[player] = nil
			removeFreezeVisual(player)
		end
	end
end)

_G.StunPlayer = stunPlayer
_G.FreezePlayer = freezePlayer
_G.IsPlayerStunned = isStunned
_G.ClearStun = clearStun
-- ⚠️ v3.2: exposto pro PulseController usar em WhiffRagdoll — errar TODOS
-- os passos de um QTE marcado assim derruba o próprio jogador em vez de
-- disparar a ação (ver resolveCombo em PulseController.legacy.luau).
_G.RagdollPlayer = ragdollPlayer

-- ===== ATRIBUTOS DE JOGADOR =====
-- REWORK: BallControl foi removido — o controle de bola em curvas
-- rápidas (o que antes lia BallControl aqui) agora usa o mesmo
-- DribbleSkill do drible normal. "Drible é drible": um único atributo
-- cobre tanto a manobra deliberada (finta, ver linha ~452) quanto o
-- controle passivo ao virar rápido com a bola.
local function getDribbleSkill(player)
	local value = player:GetAttribute(Config.DRIBBLE_SKILL_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_DRIBBLE_SKILL end
	return math.clamp(value, 0, 100) / 100
end

-- Retorna o valor BRUTO do atributo Physical (não normalizado 0-1), pois
-- a disputa de carrinho (resolvePhysicalClashChance) trabalha em cima da
-- diferença bruta de pontos, não de uma fração.
local function getPhysical(player)
	local value = player:GetAttribute(Config.PHYSICAL_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_PHYSICAL end
	return math.clamp(value, 0, 100)
end

-- ⚠️ v7 PEDIDO: "o goleiro só vai poder pegar a bola se o físico dele for
-- maior que a força dela — 100 de físico pega até 100 de força, senão
-- precisa de uma Hissatsu." Converte a força bruta do chute (escala de
-- Config.KICK_MAX_FORCE) pra uma nota comparável ao Physical (0-100):
-- 50 de nota = chute com multiplicador de força neutro (Kick 50, sem
-- nenhum bônus de Pulso/Instinto), então um chute de Pulso com
-- ForceMult alto passa facilmente de 100 — impossível de defender só no
-- mergulho normal, precisa mesmo da guarda de Hissatsu.
local function getShotForceRating(force)
	return (force / Config.KICK_MAX_FORCE) * 50
end

-- Multiplicador de força de chute a partir do atributo Kick (0-100) —
-- 1.0x no default (50), entre KICK_FORCE_MULTIPLIER_MIN e _MAX nos
-- extremos (ver FootballConfig.lua).
local function getKickForceMultiplier(player)
	local value = player:GetAttribute(Config.KICK_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_KICK end
	local fraction = math.clamp(value, 0, 100) / 100
	return Config.KICK_FORCE_MULTIPLIER_MIN + (Config.KICK_FORCE_MULTIPLIER_MAX - Config.KICK_FORCE_MULTIPLIER_MIN) * fraction
end

-- ⚠️ v67 — FORÇA EXTRA DO GOLEIRO DENTRO DA PRÓPRIA ÁREA.
-- PEDIDO: "aumenta a força do GK normal, player. Ele vai poder passar mais
-- forte enquanto estiver na área. Então, na área, só o chute vai aumentar.
-- Nenhuma Hissatsu vai aumentar, nem nada — só pra ele conseguir fazer o
-- passe normalmente para os jogadores."
--
-- Por isso NÃO entra em getKickForceMultiplier: aquele é lido também pelos
-- Pulsos (ver as chamadas em _G.PulseExecuteShot e companhia), e o pedido é
-- explícito em não tocar em Hissatsu. Este multiplicador é aplicado só no
-- caminho do CHUTE/PASSE NORMAL, e só enquanto ele é goleiro de verdade
-- dentro da própria área — a mesma regra do resto do jogo (IsEffectiveGK).
local function getGKAreaKickBonus(player)
	if not GKAreaUtil.IsEffectiveGK(player) then return 1 end
	return Config.GK_AREA_KICK_FORCE_MULT or 1
end

-- ⚠️ NOVO: getEnergyForceMultiplier foi REMOVIDO — PEDIDO: "Energia é um
-- RECURSO... Não fazer 'mais Energia = Hissatsu mais forte'". A força do
-- chute de Hissatsu agora vem da FÓRMULA da própria Hissatsu (Scaling),
-- calculada no PulseController e entregue em effect.AttributeForceMult
-- (ver _G.PulseExecuteShot).

-- ⚠️ NOVO: TÉCNICA (0-100, bruto) — domínio, primeiro toque, recepção,
-- bola difícil e precisão de passe (ver Config.TECHNIQUE_ATTRIBUTE).
-- ⚠️ v98 — TÉCNICA REMOVIDA. PEDIDO: "verifica se realmente é algo bom de se
-- manter, senão remove a técnica... os buffs pelos atributos: drible buffa
-- drible, físico buffa físico e defesa". Avaliação: precisão de passe não
-- existe mais (mira perfeita por projeto, desvio 0) e o resto dela —
-- domínio, primeiro toque, recepção, bola difícil — é CONTROLE DE BOLA, que
-- é o Drible. Então o que lia Técnica agora lê o DRIBLE (nome da função
-- mantido pra não mexer nos lugares que chamam). Config.USAR_TECNICA = true
-- volta ao atributo antigo.
local function getTechnique(player)
	local atributo = Config.USAR_TECNICA and Config.TECHNIQUE_ATTRIBUTE or Config.DRIBBLE_SKILL_ATTRIBUTE
	local value = player:GetAttribute(atributo)
	if typeof(value) ~= "number" then
		value = Config.USAR_TECNICA and Config.DEFAULT_TECHNIQUE or Config.DEFAULT_DRIBBLE_SKILL
	end
	return math.clamp(value, 0, 100)
end

-- ⚠️ v8/NOVO: queda de força por distância (MaxRange por raridade) —
-- PEDIDO: "a força não está diminuindo por stud". Antes tinha uma zona
-- CHEIA (sem decaimento nenhum) até 65% do MaxRange — a maioria dos
-- chutes de verdade no campo nunca saía dessa zona, então o número nunca
-- se mexia. Agora decai LINEAR desde o stud 0 (100% na distância 0) até
-- travar em PULSE_RANGE_FALLOFF_MIN no MaxRange e além — sempre visível,
-- e o alcance de cada raridade continua controlando a INCLINAÇÃO da queda
-- ("quanto maior a raridade, menos diminui por stud": Mythic estica a
-- mesma queda até 330 studs, bem mais devagar que Common em 140).
local function getPulseRangeFactor(distance, maxRange)
	if not maxRange or maxRange <= 0 then return 1 end
	if distance <= 0 then return 1 end
	if distance >= maxRange then return Config.PULSE_RANGE_FALLOFF_MIN end
	local t = distance / maxRange
	return 1 - t * (1 - Config.PULSE_RANGE_FALLOFF_MIN)
end

-- Dois jogadores estão em times diferentes? Só true se AMBOS tiverem um
-- Team definido e forem diferentes — se algum dos dois não tem time
-- (nil, ex: espectador/config incompleta), não bloqueia nada, porque não
-- dá pra confirmar que são do mesmo time.
local function areOpponents(playerA, playerB)
	if not playerA.Team or not playerB.Team then return true end
	return playerA.Team ~= playerB.Team
end

-- ⚠️ v36: atualiza o número da força EXIBIDO todo frame durante o voo reto
-- de um Pulso de CHUTE (pulseFlightMaxRange só vem preenchido nesse caso —
-- ver _G.PulseExecuteShot mais abaixo), com base na distância JÁ
-- PERCORRIDA desde que saiu do pé. A conta é uma RAZÃO em cima do valor já
-- mostrado no instante do chute (pulseFlightBaseForce/pulseFlightOriginalFactor),
-- não um recálculo do zero — assim o número nunca "pula" no primeiro
-- frame, só continua a MESMA curva de queda por raridade de sempre,
-- só que animada de verdade em vez de fixa.
-- ⚠️ v36: "qualquer coisa que influencie a força vai alterar nisso" — se a
-- bola (já lançada) VOAR PERTO o bastante da zona de bloqueio (Grande
-- Muralha) de um adversário do chutador, a força cai na hora (mesmo
-- multiplicador 0.15x já usado quando isso acontecia só no instante do
-- chute — ver applyExtraEffectKeys/pulsePerformKick) — antes só protegia
-- quem chutou perto demais do defensor, não quem defendia numa posição
-- que o chute ia sobrevoar/cruzar de verdade.
local function checkLivePulseBlockInterception()
	if pulseFlightBlockApplied then return end
	if not _G.GetPulseBlock or not recentKicker then return end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == recentKicker or not areOpponents(recentKicker, plr) then continue end
		local radius = _G.GetPulseBlock(plr)
		if not radius then continue end
		-- ⚠️ v120b: a Muralha conta pela CAIXA do muro (ver _G.DentroDaBarreira)
		local dentro = _G.DentroDaBarreira and _G.DentroDaBarreira(plr, ball.Position, ball.Size.X / 2)
		if dentro then
			if _G.MuroDaBarreira and _G.MuroDaBarreira(plr) and Remotes.HissatsuVFX and plr.Character then
				Config.DispararVFX("HissatsuVFX", plr.Character, "Muralha Infinita@impacto", "Natureza", { Posicao = ball.Position })
			end
			pulseFlightExternalMult = 0.15
			pulseFlightBlockApplied = true
			ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity * 0.15
			if pulseFlightVelocidade then pulseFlightVelocidade *= 0.15 end
			if Config.PULSE_FORCE_DEBUG_PRINTS then
				print(string.format(
					"🧱 [Pulso] Muralha de %s interceptou o chute de %s em pleno voo — força ao vivo cortada para 15%%",
					plr.Name, recentKicker.Name
				))
			end
			return
		end
	end
end

RunService.Heartbeat:Connect(function()
	if not pulseStraightFlightActive then return end
	checkLivePulseBlockInterception()
	if not (pulseFlightBaseForce and pulseFlightMaxRange and pulseFlightStartPos) then return end

	local traveled = (ball.Position - pulseFlightStartPos).Magnitude

	-- ⚠️ v37 FIX: "eu vi o número AUMENTAR" — a versão anterior comparava
	-- com a velocidade REAL da bola, mas a curva/banana (applyCurve, logo
	-- no topo do arquivo) ADICIONA velocidade lateral por cima da bola
	-- durante um tempo depois do chute — isso podia fazer a velocidade
	-- total da bola SUBIR de novo por um instante (mesmo perdendo força
	-- "de verdade"), e o número acompanhava essa subida. E antes disso, a
	-- v36 original usava (distância até o ALVO MIRADO + percorrido), que
	-- numa raridade de alcance curto podia já nascer "no chão" (preso no
	-- mínimo) e nunca mais se mexer, mesmo a bola ainda tendo studs de voo
	-- pela frente.
	-- FIX DE VERDADE: decai só pela distância JÁ PERCORRIDA DESDE QUE SAIU
	-- DO PÉ (sempre começa em 0 pra QUALQUER chute, perto ou longe do alvo
	-- mirado) — "a distância precisa mudar ele desde o início, cada stud
	-- diminui". Isso nunca depende da velocidade real (imune à curva) e
	-- SEMPRE tem os `maxRange` studs inteiros de queda visível pela
	-- frente, tirando qualquer chance dele subir de volta.
	-- ⚠️ v103: a força ao vivo não trava mais no mínimo da raridade — ela
	-- continua caindo NO MESMO RITMO até 0 (é a vida da bola), e quando zera
	-- o voo acaba: a gravidade e o atrito voltam e a bola cai/rola normal.
	local ritmoPorStud = (1 - Config.PULSE_RANGE_FALLOFF_MIN) / pulseFlightMaxRange
	local liveFactor = math.max(0, 1 - traveled * ritmoPorStud)
	local liveForce = pulseFlightBaseForce * liveFactor * pulseFlightExternalMult

	-- Trava extra (ratchet): NUNCA deixa o número exibido subir em cima do
	-- que já foi mostrado nesse mesmo chute, não importa a causa — só pode
	-- diminuir ou ficar igual, exatamente como "força restante" deveria se
	-- comportar.
	if pulseFlightLastDisplayed and liveForce > pulseFlightLastDisplayed then
		liveForce = pulseFlightLastDisplayed
	end
	pulseFlightLastDisplayed = liveForce

	-- ⚠️ NOVO: print de acompanhamento a cada ~5 studs percorridos (não
	-- todo frame, senão spamaria o Output) — "pra eu saber exatamente qual
	-- o número em cada lugar" durante o próprio voo, não só no instante do
	-- chute.
	if Config.PULSE_FORCE_DEBUG_PRINTS and traveled - lastPulseForceDebugPrintAtTraveled >= 5 then
		lastPulseForceDebugPrintAtTraveled = traveled
		print(string.format(
			"📉 [Pulso] voo: %.0f studs percorridos -> fator %.2f -> força ao vivo %d",
			traveled, liveFactor, math.floor(math.max(liveForce, 0))
		))
	end
	pulseForceLabel.Text = tostring(math.floor(math.max(liveForce, 0)))
	if liveForce <= 0 then
		stopPulseStraightFlight()
	end
end)

-- Nota de força do chute "perigoso" ATUAL — 0 (sempre pegável) se não
-- teve chute recente, se foi bola solta rolando sozinha, ou se foi o
-- PRÓPRIO time que tocou por último (passe não conta como "chute que
-- pode ser bloqueado pelo físico").
local DANGER_SHOT_WINDOW = 2.5
local function currentDangerForceRating(gkPlayer)
	if not recentKicker then return 0 end
	if lastShotWasInstinct then return 0 end -- ⚠️ v8: Instinto nunca é "chute perigoso" pro gate de Physical
	if tick() - recentKickTime > DANGER_SHOT_WINDOW then return 0 end
	if not areOpponents(gkPlayer, recentKicker) then return 0 end
	return getShotForceRating(lastShotForce)
end

-- ⚠️ NOVO: mesma nota de "chute perigoso" acima, só que por NOME DE TIME
-- em vez de Player — o GKBOT não é um Player (não tem :GetAttribute nem
-- Team de verdade do jeito que areOpponents espera), então
-- GKBotController.legacy.luau usa esta versão pra saber se o time
-- adversário do time que ele defende chutou recentemente (ver
-- getGKBotPhysical/attemptCatch em GKBotController.legacy.luau — PEDIDO:
-- "isso também conta pra defender chutes de pulso igual o gk (player)
-- consegue com físico").
_G.GetDangerForceRatingForTeam = function(defendingTeamName)
	if not recentKicker then return 0 end
	if lastShotWasInstinct then return 0 end
	if tick() - recentKickTime > DANGER_SHOT_WINDOW then return 0 end
	local kickerTeam = recentKicker.Team and recentKicker.Team.Name
	if not kickerTeam or kickerTeam == defendingTeamName then return 0 end
	return getShotForceRating(lastShotForce)
end
_G.GetShotForceRating = getShotForceRating

-- ===== SISTEMA DE PULSO/INSTINTO: helpers de gol/time =====
-- GolAzul/GolAmarelo têm o atributo ScoringTeam = nome do time que FAZ
-- GOL entrando ali (ver MatchController.lua) — ou seja, o time que
-- DEFENDE aquele gol é o OUTRO time.
local blueGoalPart = workspace:WaitForChild(Config.BLUE_GOAL_NAME, 5)
local yellowGoalPart = workspace:WaitForChild(Config.YELLOW_GOAL_NAME, 5)

local function otherTeamName(teamName)
	for _, t in ipairs(Config.TEAM_NAMES) do
		if t ~= teamName then return t end
	end
	return nil
end

-- Gol ADVERSÁRIO de quem está com a bola nesse time (onde ele marca).
local function enemyGoalOf(teamName)
	if blueGoalPart and blueGoalPart:GetAttribute("ScoringTeam") == teamName then return blueGoalPart end
	if yellowGoalPart and yellowGoalPart:GetAttribute("ScoringTeam") == teamName then return yellowGoalPart end
	return nil
end

-- Próprio gol de quem está nesse time (onde o adversário marca nele).
local function ownGoalOf(teamName)
	local enemyTeam = otherTeamName(teamName)
	if not enemyTeam then return nil end
	return enemyGoalOf(enemyTeam)
end

-- ⚠️ v9 FIX: "a hitbox que apareceu era minúscula" — a LARGURA do gol
-- assumia sempre Size.X, mas o Part do gol foi montado manualmente no
-- Studio (não por script) e pode ter a largura de verdade no eixo Z em
-- vez de X, dependendo de como foi rotacionado — nesse caso Size.X vira
-- a PROFUNDIDADE (bem menor), e qualquer coisa calculada em cima disso
-- (guarda do goleiro, mira de canto) saía minúscula. Usa o MAIOR entre X
-- e Z: robusto pros dois jeitos de montar o gol, já que a profundidade de
-- um gol-gatilho é sempre bem menor que a largura de verdade.
local function getGoalWidth(goalPart)
	return math.max(goalPart.Size.X, goalPart.Size.Z)
end

local function findRolePlayer(teamName, role)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName and plr:GetAttribute("Role") == role then
			return plr
		end
	end
	return nil
end

local function nearestOpponentDistance(player)
	local _, root = getCharacterParts(player)
	if not root then return math.huge end
	local best = math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player then continue end
		if not areOpponents(player, plr) then continue end
		local _, otherRoot = getCharacterParts(plr)
		if not otherRoot then continue end
		local d = (otherRoot.Position - root.Position).Magnitude
		if d < best then best = d end
	end
	return best
end

-- ===== GEOMETRIA DE CAMPO =====
-- Não usa nenhuma parte/tag nova no Studio — só os dois gols que o
-- BallController já carrega (blueGoalPart/yellowGoalPart). O "eixo do
-- campo" é a reta entre os dois; qualquer posição é projetada nele pra
-- saber de que lado ela está e a que distância da linha de fundo
-- adversária ela está.
local function fieldAxis()
	if not (blueGoalPart and yellowGoalPart) then return nil end
	local from = blueGoalPart.Position
	local delta = yellowGoalPart.Position - from
	if delta.Magnitude < 1e-3 then return nil end
	return from, delta.Unit
end

-- true se "position" está mais perto do gol ADVERSÁRIO de "teamName" do
-- que do próprio gol — ou seja, esse jogador está no campo de ataque.
local function attackingHalfOf(teamName, position)
	local enemyGoal = enemyGoalOf(teamName)
	local ownGoal = ownGoalOf(teamName)
	if not (enemyGoal and ownGoal) then return true end -- gols não carregados: não bloqueia a condição
	local distToEnemy = (position - enemyGoal.Position).Magnitude
	local distToOwn = (position - ownGoal.Position).Magnitude
	return distToEnemy < distToOwn
end

-- Distância projetada (ao longo do eixo gol-a-gol) até a linha de fundo
-- ADVERSÁRIA de "teamName" — 0 = em cima da linha, cresce indo pro meio
-- de campo. Usa projeção no eixo (não distância em linha reta) porque
-- "perto da linha de fundo" é uma faixa de lateral a lateral, não um
-- ponto só.
local function distanceToBylineOf(teamName, position)
	local enemyGoal = enemyGoalOf(teamName)
	if not enemyGoal then return math.huge end
	local origin, axis = fieldAxis()
	if not origin then
		return (position - enemyGoal.Position).Magnitude -- sem eixo válido, cai pra distância reta
	end
	local enemyProjected = (enemyGoal.Position - origin):Dot(axis)
	local posProjected = (position - origin):Dot(axis)
	return math.abs(enemyProjected - posProjected)
end

-- ⚠️ v5 (Instintos): CONTEXTO DE CAMPO pros Instintos CONTÍNUOS
-- (Trigger = "Instant"). O InstinctController reavalia esses instintos
-- num loop próprio, e até a v4 o contexto dele só tinha "tem a bola?" e
-- "tem adversário na frente?" — ou seja, uma condição como "estar perto
-- do gol" NUNCA disparava num instinto contínuo, porque a distância nem
-- chegava lá. Isso expõe a geometria de campo que já era calculada aqui
-- (e só aqui, porque só este script carrega os dois gols) pra qualquer
-- condição de Instinto poder usar.
-- ⚠️ v9 — INSTINTOS SITUACIONAIS NOVOS (pedido: "não quero só buff, quero
-- situação de jogo real: 2v1, campo livre..."). Os dois helpers abaixo
-- viram ctx.ForwardOpponentDistance e ctx.IsLastManBack (ver
-- GetInstinctFieldContext logo abaixo) e ctx.HasNumericalAdvantage (ver
-- KickAtTeammate mais abaixo).

-- Distância até o adversário mais perto DENTRO de um cone à frente do
-- jogador (~66°, cos>0.4) — "campo livre" de verdade: ninguém no seu
-- CAMINHO, mesmo que tenha gente longe atrás ou do lado.
local function forwardOpponentDistance(player, root)
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	if flatLook.Magnitude < 0.05 then return math.huge end
	flatLook = flatLook.Unit
	local best = math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player or not areOpponents(player, plr) then continue end
		local _, oRoot = getCharacterParts(plr)
		if not oRoot then continue end
		local delta = oRoot.Position - root.Position
		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		if flatDelta.Magnitude < 0.1 then continue end
		if flatDelta.Unit:Dot(flatLook) > 0.4 then
			best = math.min(best, flatDelta.Magnitude)
		end
	end
	return best
end

-- true se NENHUM companheiro de time (fora o goleiro) estiver mais perto
-- do PRÓPRIO gol do que você — ou seja, você é o último homem, sozinho
-- na retaguarda.
local function isLastManBack(player, root, teamName)
	local ownGoal = ownGoalOf(teamName)
	if not ownGoal then return false end
	local myDistance = (root.Position - ownGoal.Position).Magnitude
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player then continue end
		if not plr.Team or plr.Team.Name ~= teamName then continue end
		if plr:GetAttribute("Role") == "GK" then continue end
		local _, mateRoot = getCharacterParts(plr)
		if not mateRoot then continue end
		if (mateRoot.Position - ownGoal.Position).Magnitude < myDistance then return false end
	end
	return true
end

-- true se, contando você + companheiros dentro de "radius" da posição
-- dada, tem MAIS gente do seu time do que adversário dentro do mesmo
-- raio — leitura de "2 contra 1" (ou melhor) puro numérico.
local function hasNumericalAdvantage(player, position, radius)
	local mates, opps = 1, 0 -- 1 = você mesmo
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player then continue end
		local _, plrRoot = getCharacterParts(plr)
		if not plrRoot then continue end
		if (plrRoot.Position - position).Magnitude > radius then continue end
		if areOpponents(player, plr) then
			opps += 1
		else
			mates += 1
		end
	end
	return mates > opps
end

-- ⚠️ v12: "Passo Furtivo" (Stealth Walk, Blue Lock) — true quando NENHUM
-- adversário perto está te ENCARANDO. Não é "estar longe": é estar fora
-- do cone de visão de quem poderia te marcar. É o oposto do
-- forwardOpponentDistance acima (lá o cone é o SEU, aqui é o DELES).
local function isUnseenByOpponents(player, root)
	if player.Character and (player.Character:GetAttribute("FurtivoAte") or 0) > workspace:GetServerTimeNow() then return true end -- ⚠️ v111: Passo Furtivo (Sumir)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player or not areOpponents(player, plr) then continue end
		local _, oRoot = getCharacterParts(plr)
		if not oRoot then continue end
		local delta = root.Position - oRoot.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		-- Longe demais pra te marcar de qualquer jeito: não conta como
		-- "estar sendo visto", senão bastaria um adversário do outro lado do
		-- campo olhando na sua direção pra desligar o Instinto.
		if flat.Magnitude > 45 or flat.Magnitude < 0.1 then continue end
		local look = oRoot.CFrame.LookVector
		local flatLook = Vector3.new(look.X, 0, look.Z)
		if flatLook.Magnitude < 0.05 then continue end
		if flat.Unit:Dot(flatLook.Unit) > 0.35 then return false end -- está no campo de visão dele
	end
	return true
end

-- ⚠️ v12: "Zona de Ouro" (Golden Zone, Blue Lock) — ângulo entre você e o
-- gol adversário, medido a partir da linha reta que liga os dois gols. 0°
-- = de frente pro gol; quanto maior, mais de lado você está. É o eixo que
-- nenhum outro Instinto usa (todos os outros só olham DISTÂNCIA).
local function angleToGoalDegrees(root, enemyGoal, ownGoal)
	if not enemyGoal or not ownGoal then return nil end
	local axis = enemyGoal.Position - ownGoal.Position
	axis = Vector3.new(axis.X, 0, axis.Z)
	if axis.Magnitude < 0.1 then return nil end
	local toGoal = enemyGoal.Position - root.Position
	toGoal = Vector3.new(toGoal.X, 0, toGoal.Z)
	if toGoal.Magnitude < 0.1 then return 0 end
	return math.deg(math.acos(math.clamp(toGoal.Unit:Dot(axis.Unit), -1, 1)))
end

-- ⚠️ v12: "Olho de Predador" (Predator Eye, Blue Lock) — o goleiro baixou a
-- guarda NESTE chute? Duas leituras, as duas só de posição (funciona
-- igual pra goleiro humano e pro bot, ver _G.GetActiveGKBots):
--   1. ele está adiantado, longe da própria linha; ou
--   2. ele está deslocado pro lado CONTRÁRIO de onde a bola vai.
-- Ou seja: premia olhar pro goleiro antes de chutar, não a geometria do
-- campo. Nenhuma outra condição do jogo lê o estado do adversário.
local function goalkeeperOffGuard(player, targetPoint)
	if not player.Team then return false end
	local goal = enemyGoalOf(player.Team.Name)
	if not goal then return false end

	local gkPosition
	local enemyName = otherTeamName(player.Team.Name)
	for _, plr in ipairs(Players:GetPlayers()) do
		if not plr.Team or plr.Team.Name ~= enemyName then continue end
		if plr:GetAttribute("Role") ~= "GK" then continue end
		local _, gkRoot = getCharacterParts(plr)
		if gkRoot then gkPosition = gkRoot.Position end
		break
	end
	if not gkPosition and _G.GetActiveGKBots then
		for _, bot in ipairs(_G.GetActiveGKBots()) do
			if bot.teamName == enemyName then
				gkPosition = bot.cframe.Position
				break
			end
		end
	end
	if not gkPosition then return false end

	if (gkPosition - goal.Position).Magnitude >= Config.INSTINCT_GK_OFF_LINE_DISTANCE then
		return true
	end

	local gkOffset = gkPosition - goal.Position
	local aimOffset = targetPoint - goal.Position
	gkOffset = Vector3.new(gkOffset.X, 0, gkOffset.Z)
	aimOffset = Vector3.new(aimOffset.X, 0, aimOffset.Z)
	if gkOffset.Magnitude > 2 and aimOffset.Magnitude > 2 then
		return gkOffset.Unit:Dot(aimOffset.Unit) < -0.2 -- ele foi pro lado oposto do chute
	end
	return false
end

_G.GetInstinctFieldContext = function(player)
	if not player or not player.Team then return nil end
	local _, root = getCharacterParts(player)
	if not root then return nil end

	local teamName = player.Team.Name
	local enemyTeamName = otherTeamName(teamName)
	local enemyGoal = enemyGoalOf(teamName)
	local ownGoal = ownGoalOf(teamName)

	return {
		DistanceToGoal = enemyGoal and (root.Position - enemyGoal.Position).Magnitude or nil,
		DistanceToOwnGoal = ownGoal and (root.Position - ownGoal.Position).Magnitude or nil,
		AttackingHalf = attackingHalfOf(teamName, root.Position),
		DistanceToByline = distanceToBylineOf(teamName, root.Position),
		OpponentDistance = nearestOpponentDistance(player),
		-- ⚠️ v5.1: precisa disto pro Instinto de botão "Chute Direto"
		-- (aperta R até 1s depois de receber). Antes esse número só existia
		-- no instante do chute manual, então um Instinto ativado por tecla
		-- nunca conseguiria checar essa condição.
		SecondsAfterReceive = lastReceiveTime[player] and (tick() - lastReceiveTime[player]) or math.huge,
		HasPossession = (owner == player),
		-- ⚠️ v5.4: "Predador da Área" (Botao/R) precisa saber se você está
		-- DENTRO da área adversária no instante do aperto — fallback true
		-- (não trava o Instinto) se a Part GKArea_<TimeAdversário> ainda não
		-- existir na cena, mesma filosofia do resto do GKAreaUtil.
		-- ⚠️ v5.7: REVERTIDO — v5.6 tinha alargado a borda da área com uma
		-- margem (PREDATOR_AREA_MARGIN), mas o pedido era pra abaixar a
		-- ALTURA, não dar folga na borda ("não dar margem além da borda da
		-- área"). Volta a ser a checagem estrita, sem margem — a folga real
		-- agora mora só no AtivaEffect.HeaderMinHeight (ver
		-- PulseInstinctData.luau).
		InsideEnemyArea = GKAreaUtil.IsPositionInArea(enemyTeamName, root.Position, true),
		-- ⚠️ v9: "campo livre" de verdade (cone à frente) e "último homem"
		-- (ninguém do time mais perto do próprio gol) — ver Instintos
		-- "Campo Aberto"/"Último Homem" em PulseInstinctData.luau.
		ForwardOpponentDistance = forwardOpponentDistance(player, root),
		IsLastManBack = isLastManBack(player, root, teamName),
		-- ⚠️ v12: contexto dos Instintos novos (ver Data.Instincts).
		IsUnseen = isUnseenByOpponents(player, root),
		AngleToGoal = angleToGoalDegrees(root, enemyGoal, ownGoal),
		TeamPassChain = teamPassChain[teamName] or 0,
		SecondsInPossession = (owner == player and possessionSince[player])
			and (tick() - possessionSince[player]) or 0,
		-- ⚠️ v110 (Armas novas): dentro da PRÓPRIA área (Saída Rápida, Sexto
		-- Sentido...) e a distância até o ADVERSÁRIO que está com a bola
		-- (Marcação Cerrada, Defesa Zumbi, Desarme Relâmpago...)
		InOwnArea = GKAreaUtil.IsPositionInArea(teamName, root.Position, true),
		CarrierDistance = (function()
			if not owner or owner == player or not areOpponents(player, owner) then return math.huge end
			local _, oRoot = getCharacterParts(owner)
			return oRoot and (oRoot.Position - root.Position).Magnitude or math.huge
		end)(),
	}
end

-- ===== DESVIO DE MIRA =====
-- Graus de desvio ALEATÓRIO nesse chute específico, antes de qualquer
-- redução de Pulso/Instinto (aimDeviationMult, aplicado por quem chama
-- essa função). Pior Kick = mais desvio; adversário em cima (pressão) =
-- mais desvio ainda.
-- ⚠️ NOVO: isPass=true (chute mirado num companheiro) lê TÉCNICA em vez de
-- Chute — "precisão de passes" é da Técnica. Finalização continua no Chute.
local function getAimDeviationDegrees(player, isPass)
	local kickValue
	if isPass then
		kickValue = getTechnique(player)
	else
		kickValue = player:GetAttribute(Config.KICK_ATTRIBUTE)
		if typeof(kickValue) ~= "number" then kickValue = Config.DEFAULT_KICK end
	end
	local kickFraction = math.clamp(kickValue, 0, 100) / 100

	local degrees = Config.AIM_DEVIATION_MIN_DEGREES
		+ (Config.AIM_DEVIATION_MAX_DEGREES - Config.AIM_DEVIATION_MIN_DEGREES) * (1 - kickFraction)

	if nearestOpponentDistance(player) <= Config.AIM_DEVIATION_PRESSURE_RADIUS then
		degrees += Config.AIM_DEVIATION_PRESSURE_DEGREES
	end

	return degrees
end

-- Gira "direction" (Vector3, horizontal) por um ângulo aleatório dentro
-- de [-degrees, degrees] em volta do eixo vertical — o desvio de mira de
-- verdade.
local function applyAimDeviation(direction, degrees)
	-- ⚠️ v103 — PEDIDO: "Não é pra existir desvio aleatório em nenhum chute."
	-- Desligado de vez (Config.DESVIO_ALEATORIO_LIGADO = true religa): TODO
	-- chute, passe, Instinto e Hissatsu vai exatamente pra onde foi mirado.
	if not Config.DESVIO_ALEATORIO_LIGADO then return direction end
	if not degrees or degrees <= 0 then return direction end
	local randomDegrees = (math.random() * 2 - 1) * degrees
	local rotation = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(randomDegrees))
	return (rotation * direction).Unit
end

-- ===== DRIBLE (condução física, estilo FIFA) =====
local ownerLastFacing = {}
local ownerExposed = {}

RunService.Heartbeat:Connect(function(dt)
	if not owner then return end

	local character, root = getCharacterParts(owner)
	if not root then
		releaseOwner()
		return
	end

	ball.CanCollide = true

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local moveDirection = humanoid and humanoid.MoveDirection or Vector3.zero
	local facing
	if moveDirection.Magnitude > 0.1 then
		facing = (root.CFrame.LookVector * 0.4 + moveDirection.Unit * 0.6)
		facing = facing.Magnitude > 0.01 and facing.Unit or root.CFrame.LookVector
	else
		facing = root.CFrame.LookVector
	end

	local previousFacing = ownerLastFacing[owner] or facing
	local angleDelta = math.acos(math.clamp(previousFacing:Dot(facing), -1, 1))
	local turnRate = dt > 0 and (angleDelta / dt) or 0
	ownerLastFacing[owner] = facing

	local control = getDribbleSkill(owner)

	local looseAmount = 0
	if turnRate > Config.DRIBBLE_TURN_RATE_THRESHOLD then
		looseAmount = (turnRate - Config.DRIBBLE_TURN_RATE_THRESHOLD)
			* Config.DRIBBLE_TURN_LOOSE_MULTIPLIER * (1 - control)
		looseAmount = math.min(looseAmount, Config.DRIBBLE_MAX_LOOSE_EXTRA)
	end
	-- Mantido pro efeito visual (bola mais longe dos pés ao virar rápido),
	-- mas NÃO é mais usado pra roubar posse por proximidade — ver o loop
	-- de pickup logo abaixo, onde esse sistema foi removido.
	ownerExposed[owner] = looseAmount > Config.DRIBBLE_EXPOSE_THRESHOLD

	-- ⚠️ v104: bola nos pés — o cliente do dono é quem posiciona a bola.
	-- Aqui só: (1) entregar a rede se ainda não entregou (ela volta pro
	-- servidor sozinha quando a bola é ancorada, por exemplo); (2) conferir
	-- que a bola está mesmo perto dele — se não estiver, o servidor retoma
	-- por meio segundo e a puxa de volta com a perseguição antiga.
	if Config.BOLA_NOS_PES_LIGADO and dribbleMoves[owner] and tick() >= dribbleMoves[owner].expiresAt then
		dribbleMoves[owner] = nil
		setIframeGlow(owner, false)
	end
	if Config.BOLA_NOS_PES_LIGADO and tick() >= bolaRetomadaAte then
		if bolaEstaNoCliente(owner) then
			local longe = (ball.Position - root.Position).Magnitude > Config.BOLA_NOS_PES_DIST_MAX
			-- (a conferência só vale depois de 1s com a rede: a bola leva um
			-- instante pra chegar do servidor até o cliente e ser colada nos pés)
			if longe and bolaNoClienteDesde and tick() - bolaNoClienteDesde > 1 then
				bolaRetomadaAte = tick() + 0.5
				definirDonoDeRede(nil)
			else
				return
			end
		elseif not ball.Anchored then
			definirDonoDeRede(owner)
		end
	end

	-- ⚠️ v105 — "coloca pra bola ficar na mão do GK": goleiro dentro da
	-- própria área segura a bola nas mãos (BolaNosPes/AnimadorProcedural leem
	-- esse atributo no personagem)
	local naMao = GKAreaUtil.IsEffectiveGK(owner)
	if owner:GetAttribute("BolaNaMao") ~= naMao then owner:SetAttribute("BolaNaMao", naMao) end
	if character:GetAttribute("BolaNaMao") ~= naMao then
		character:SetAttribute("BolaNaMao", naMao)
		if naMao then avisarAcao(character, "Agarrar", 0.4) end -- v110: animação de agarrar
	end

	local activeMove = dribbleMoves[owner]
	local targetPosition
	if activeMove then
		if tick() < activeMove.expiresAt then
			-- ⚠️ v86: o personagem NÃO é mais preso aqui — quem o desloca é
			-- o cliente, somando a finta ao andar (ver sendDisplacement). A
			-- bola vai pra onde a finta termina A PARTIR de onde o jogador
			-- está agora: posição atual + o que ainda falta do deslocamento
			-- (mesma curva ease-out cúbica que o cliente usa). Assim, se ele
			-- continuar andando durante a finta, a bola acompanha.
			local totalDuration = activeMove.expiresAt - activeMove.triggeredAt
			local alpha = totalDuration > 0
				and math.clamp((tick() - activeMove.triggeredAt) / totalDuration, 0, 1)
				or 1
			local easedAlpha = 1 - (1 - alpha) ^ 3
			local offset = activeMove.offset or (activeMove.endPosition - activeMove.startPosition)
			local restante = offset * (1 - easedAlpha)
			targetPosition = Vector3.new(root.Position.X + restante.X, activeMove.targetPosition.Y, root.Position.Z + restante.Z)
				+ Vector3.new(0, Config.DRIBBLE_HEIGHT_OFFSET, 0)
		else
			dribbleMoves[owner] = nil
			setIframeGlow(owner, false)
			activeMove = nil
		end
	end

	if not activeMove then
		local bobPhase = math.sin(tick() * Config.DRIBBLE_BOB_FREQUENCY) * Config.DRIBBLE_BOB_AMPLITUDE
		local rightVector = root.CFrame.RightVector

		targetPosition = root.Position
			+ facing * (Config.DRIBBLE_OFFSET + looseAmount)
			+ rightVector * bobPhase
			+ Vector3.new(0, Config.DRIBBLE_HEIGHT_OFFSET, 0)
		if naMao then
			targetPosition = root.Position + root.CFrame.LookVector * 1.45 + Vector3.new(0, 0.35, 0) -- ⚠️ v105: nas mãos
		end
	end

	local rootVelocity = root.AssemblyLinearVelocity
	local rootVelocityXZ = Vector3.new(rootVelocity.X, 0, rootVelocity.Z)

	local toTarget = targetPosition - ball.Position
	local correctionXZ = Vector3.new(toTarget.X, 0, toTarget.Z) * Config.DRIBBLE_CHASE_GAIN
	local desiredXZ = rootVelocityXZ + correctionXZ
	if desiredXZ.Magnitude > Config.DRIBBLE_MAX_CHASE_SPEED then
		desiredXZ = desiredXZ.Unit * Config.DRIBBLE_MAX_CHASE_SPEED
	end

	local currentVelocity = ball.AssemblyLinearVelocity

	-- ⚠️ v5.3 — DRIBLE AÉREO (pular com a bola).
	-- No chão, a bola acompanha o jogador por uma mola vertical fraca
	-- (toTarget.Y * 6 somado à velocidade), o que é suficiente porque a
	-- altura quase não muda. No AR isso não serve: quando o jogador pula,
	-- o alvo sobe uns 7 studs de uma vez, e uma mola fraca lutando contra
	-- a gravidade deixa a bola pra trás — na prática, pular era perder a
	-- bola. Enquanto o jogador está no ar, a bola HERDA a velocidade
	-- vertical dele e usa uma mola bem mais forte, então ela sobe junto e
	-- dá pra driblar no ar de verdade. (A contrapartida é a cabeçada: com
	-- a bola alta assim, ela vira alvo de quem cabecear — ver
	-- AttemptHeader e Config.HEADER_*.)
	local noAr = humanoid and humanoid.FloorMaterial == Enum.Material.Air
	if noAr then
		local yDesejado = rootVelocity.Y + toTarget.Y * Config.DRIBBLE_AERIAL_CHASE_GAIN
		ball.AssemblyLinearVelocity = Vector3.new(desiredXZ.X, yDesejado, desiredXZ.Z)
	else
		local verticalCorrection = toTarget.Y * 6
		ball.AssemblyLinearVelocity = Vector3.new(desiredXZ.X, currentVelocity.Y + verticalCorrection * dt, desiredXZ.Z)
	end

	if moveDirection.Magnitude < 0.1 then
		ball.AssemblyAngularVelocity = ball.AssemblyAngularVelocity * 0.75
	end
end)

-- ===== PEGAR BOLA SOLTA (por PROXIMIDADE) =====
-- O roubo passivo de quem JÁ TEM posse (bola "exposta" ao virar rápido)
-- foi REMOVIDO — era ele que ficava tirando a bola de volta logo depois
-- de um carrinho bem-sucedido, fazendo parecer que o carrinho "não
-- funcionava" a partir da 2ª tentativa. Agora, enquanto alguém tem a
-- bola, só o CARRINHO tira a posse dele.
-- ===== ⚠️ TRAVA DE PASSE (PassLockSeconds, Pulso v3) =====
-- Depois de um passe de Pulso com a chave PassLockSeconds, SÓ o
-- companheiro mirado pode ganhar a posse pelos próximos N segundos —
-- adversário que encostar simplesmente não pega (a bola não muda de
-- dono). A trava se limpa sozinha quando expira OU assim que o alvo pega
-- a bola.
--
-- DECISÃO DE DESIGN: a trava vale nos caminhos PASSIVOS de aquisição de
-- posse (pickup por proximidade e captura de bola solta por carrinho) —
-- que é onde o "adversário encostou e roubou o passe" acontece. O
-- mergulho/dash do GOLEIRO continua funcionando normalmente: uma defesa
-- ativa, com timing, merece pegar a bola mesmo num passe travado.
local passLock = nil -- { Target = player, Until = tick() + N }

local function passLockBlocks(player)
	if not passLock then return false end
	if tick() >= passLock.Until then
		passLock = nil
		return false
	end
	if player == passLock.Target then
		passLock = nil -- o alvo pegou: trava cumpriu o papel dela
		return false
	end
	return true
end

local function findClosestPlayerToBall(maxRadius, ignorePlayer, opponentOnly)
	local closestPlayer, closestDistance = nil, maxRadius
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == ignorePlayer then continue end
		if opponentOnly and ignorePlayer and not areOpponents(plr, ignorePlayer) then continue end
		local _, root = getCharacterParts(plr)
		if not root then continue end

		local distance = (root.Position - ball.Position).Magnitude
		if distance <= closestDistance then
			closestDistance = distance
			closestPlayer = plr
		end
	end
	return closestPlayer, closestDistance
end

-- Pulso da Leitura/Primeiro Toque (buff ativo) e Instinto Predatório/de
-- Antecipação (PickupRadiusAdd, quando há um adversário perto o
-- bastante da bola solta) aumentam o raio de pickup individual de quem
-- tem o buff/instinto — por isso não dá mais pra usar um raio único pra
-- todo mundo (findClosestPlayerToBall antigo): cada jogador é checado
-- contra o PRÓPRIO raio (base + bônus), e ganha quem estiver mais perto
-- dentre os que estão dentro do raio de cada um.
RunService.Heartbeat:Connect(function()
	if deadBallMode then return end
	if owner then return end
	if ballFrozenForGuardQTE then return end -- bola "parada" pela guarda de Hissatsu não é bola solta pra ninguém pegar
	-- ⚠️ NOVO (Técnica — "recepção de passes / controle de bolas difíceis"):
	-- o teto de velocidade de bola dominável agora é POR JOGADOR (Técnica
	-- alta domina bola um pouco mais rápida). O corte global continua, só
	-- que no teto MÁXIMO possível (Técnica 100) — acima disso ninguém pega.
	local ballSpeed = ball.AssemblyLinearVelocity.Magnitude
	if ballSpeed > LOOSE_BALL_PICKUP_MAX_SPEED * Config.TECHNIQUE_RECEIVE_SPEED_MULT_MAX then return end

	local bestPlayer, bestDistance = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		-- ⚠️ v5.6: trava de auto-repossessão — o próprio chutador não conta
		-- pro pickup passivo por SELF_PICKUP_LOCK_SECONDS depois do chute
		-- (ver KickBall abaixo). Qualquer outro jogador continua elegível
		-- normalmente.
		if selfPickupLockUntil[plr] and tick() < selfPickupLockUntil[plr] then continue end

		local _, root = getCharacterParts(plr)
		if not root then continue end

		-- ⚠️ NOVO: Técnica escala domínio/primeiro toque (raio), recepção
		-- (velocidade de bola aceitável) e bola aérea (altura) — 1.0x em 50.
		local technique = getTechnique(plr)
		if ballSpeed > LOOSE_BALL_PICKUP_MAX_SPEED * Config.AttributeCurve(technique, Config.TECHNIQUE_RECEIVE_SPEED_MULT_MIN, Config.TECHNIQUE_RECEIVE_SPEED_MULT_MAX) then continue end

		local radius = Config.POSSESSION_PICKUP_RADIUS * Config.AttributeCurve(technique, Config.TECHNIQUE_PICKUP_RADIUS_MULT_MIN, Config.TECHNIQUE_PICKUP_RADIUS_MULT_MAX)
		if _G.GetPulsePickupRadiusAdd then radius += _G.GetPulsePickupRadiusAdd(plr) end
		-- ⚠️ v111: era _G.CheckInstinct(plr, "Instant") a cada quadro de bola
		-- solta — piscava o HUD, acendia a aura e enchia o medidor do Flow sem
		-- parar. Agora só soma o alcance das Armas contínuas já ligadas.
		if _G.GetInstinctPickupRadiusAdd then radius += _G.GetInstinctPickupRadiusAdd(plr) end

		-- PEDIDO: bola passando por CIMA de alguém LENTO (andando, não
		-- sprintando) fica mais fácil de dominar — decompõe a distância em
		-- horizontal/vertical (mesma ideia do mergulho do goleiro) em vez
		-- de distância 3D cheia, que fazia a altura "comer" o raio de
		-- pickup inteiro. Sprintando, continua exigindo a distância 3D
		-- cheia de sempre (correndo não dá pra sentir o primeiro toque tão
		-- bem quanto andando).
		local playerSpeed = root.AssemblyLinearVelocity.Magnitude
		local distance
		if playerSpeed <= Config.AERIAL_PICKUP_MAX_PLAYER_SPEED then
			local horizontal = (Vector3.new(ball.Position.X, 0, ball.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
			local vertical = math.abs(ball.Position.Y - root.Position.Y)
			local aerialHeight = Config.AERIAL_PICKUP_HEIGHT * Config.AttributeCurve(technique, Config.TECHNIQUE_AERIAL_HEIGHT_MULT_MIN, Config.TECHNIQUE_AERIAL_HEIGHT_MULT_MAX) -- ⚠️ NOVO: Técnica
			distance = (vertical <= aerialHeight) and horizontal or math.huge
		else
			distance = (root.Position - ball.Position).Magnitude
		end

		if distance <= radius and distance < bestDistance then
			bestDistance = distance
			bestPlayer = plr
		end
	end

	if bestPlayer then
		-- ⚠️ v3: passe de Pulso com PassLockSeconds — só o companheiro
		-- mirado pega a bola nessa janela; qualquer outro simplesmente não
		-- muda a posse (a bola segue solta).
		if passLockBlocks(bestPlayer) then return end
		setOwner(bestPlayer)
	end
end)

-- ===== MECÂNICA DE CORPO (bola bate, corpo absorve força) =====
-- Bola e jogadores não colidem fisicamente de propósito (ver
-- PhysicsService no FootballConfig.lua) — então "bater no corpo" é
-- checado aqui por proximidade+velocidade. Só conta pra quem NÃO é o
-- dono da bola (o dono já controla ela pelo sistema de drible) e só
-- acima de BODY_BLOCK_MIN_SPEED (senão um toque leve/drible normal
-- também contaria). Quanto MAIOR o Physical de quem foi atingido, MAIS
-- a força da bola é absorvida — nunca 100%, pra ficar justo.
--
-- ⚠️ v13 FIX ("a bola bate no jogador e ricocheteia, tipo bate no
-- quadril"): NÃO é colisão física (Bola x Players já é 'false' — ver
-- comentário grande no Config). O corte de velocidade era um multiply
-- ÚNICO, num frame só — com a bola ainda no ar, isso fazia a trajetória
-- "quebrar" de repente bem na altura do HumanoidRootPart (o quadril),
-- parecendo um ricochete numa parede invisível. Agora o corte é espalhado
-- ao longo de Config.BODY_BLOCK_EASE_SECONDS (decaimento exponencial
-- suave, frame a frame, usando o dt do Heartbeat — matematicamente dá o
-- MESMO corte total de sempre no final da janela, só que sem o "kink").
-- ⚠️ v14 FIX ("eu não consigo chutar reto porque ela não está
-- atravessando o personagem"): os prints de diagnóstico da v13 provaram
-- 0% colisão física (nunca acusaram nada) e revelaram a causa de
-- verdade — o MESMO corpo parado do lado da bola voltava a "bloquear" de
-- novo a cada BODY_BLOCK_DEBOUNCE (0.3s), moendo a velocidade em vários
-- cortes seguidos até praticamente zerar, em vez de UM corte só.
-- hasBodyBlockedThisFlight garante no máximo UM corte por lance/chute —
-- reseta a 'false' toda vez que alguém chuta/cabeceia de verdade (ver os
-- 4 pontos que já resetam kickerClearedBody).
RunService.Heartbeat:Connect(function(dt)
	if not Config.BODY_BLOCK_ENABLED or Config.KICK_TEST_MODE then return end -- ⚠️ v23: modo de teste desliga a mecânica de corpo inteira

	local speed = ball.AssemblyLinearVelocity.Magnitude
	if speed < Config.BODY_BLOCK_MIN_SPEED then
		table.clear(bodyBlockContactStart)
		return
	end

	local blockedThisFrame = false

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == owner then continue end

		local _, root = getCharacterParts(plr)
		if not root then continue end

		local physicalFraction = getPhysical(plr) / 100
		local bodyScale = Config.PHYSICAL_SCALE_MIN + (Config.PHYSICAL_SCALE_MAX - Config.PHYSICAL_SCALE_MIN) * physicalFraction
		local radius = Config.BODY_BLOCK_RADIUS * bodyScale
		local distance = (root.Position - ball.Position).Magnitude

		if plr == recentKicker then
			-- ⚠️ v15 FIX (bug reportado DE NOVO, dessa vez explicado
			-- direito pelo usuário: "eu com a bola, tento chutar por
			-- dentro de mim mesmo, a bola trava e para" — é SEMPRE o
			-- PRÓPRIO chutador, não outro jogador). A v12 destravava a
			-- imunidade assim que a bola saía do raio do corpo UMA vez
			-- (kickerClearedBody = true) — mas num chute mais fraco/reto,
			-- é super comum o próprio jogador (correndo na mesma direção,
			-- às vezes mais rápido que a bola desacelerando por atrito)
			-- ALCANÇAR a bola nesse mesmo instante de novo. Como a
			-- imunidade já tinha sido consumida (cleared=true, PRA
			-- SEMPRE, só resetava no próximo chute), o próprio corpo dele
			-- então "bloqueava" o próprio chute de verdade — exatamente o
			-- "a bola tenta colidir com o corpo do próprio personagem".
			--
			-- Fix: a imunidade agora NUNCA se destrava por distância —
			-- só termina quando ALGUÉM (qualquer um, ver setOwner abaixo)
			-- realmente pega a posse da bola, ou depois de
			-- Config.BODY_BLOCK_SELF_IMMUNITY_MAX segundos (teto de
			-- segurança, caso a bola saia de jogo/ninguém encoste nela).
			-- Ou seja: o próprio corpo do chutador NUNCA mais bloqueia o
			-- próprio chute dele, mesmo que ele alcance a bola de novo
			-- correndo atrás dela.
			if not kickerClearedBody and tick() - recentKickTime >= Config.BODY_BLOCK_SELF_IMMUNITY_MAX then
				kickerClearedBody = true -- teto de segurança estourou — libera mesmo sem ninguém ter pego a bola
			end
			if not kickerClearedBody then
				continue
			end
		end

		if distance > radius then
			bodyBlockContactStart[plr] = nil
			continue
		end

		if bodyBlockDebounce[plr] and tick() - bodyBlockDebounce[plr] < Config.BODY_BLOCK_DEBOUNCE then
			blockedThisFrame = true
			break
		end

		local contactStart = bodyBlockContactStart[plr]

		-- ⚠️ v14 FIX: só deixa COMEÇAR um contato novo se esse lance ainda
		-- não foi absorvido por nenhum corpo — um contato JÁ em andamento
		-- (contactStart existente) continua até o fim normalmente, isso só
		-- trava um SEGUNDO corte em cadeia (mesmo jogador de novo depois do
		-- debounce, ou outro jogador do lado).
		if not contactStart and hasBodyBlockedThisFlight then
			continue
		end

		if not contactStart then
			contactStart = tick()
			bodyBlockContactStart[plr] = contactStart
			hasBodyBlockedThisFlight = true
			pushToucher(plr) -- conta como o último a tocar, pra assistência/gol funcionar certo
			-- ⚠️ v22 — PEDIDO: "a bola trava no ar... não deu colisão com
			-- nada" — print único (não é sistema novo, só visibilidade) pra
			-- confirmar se é ESSA mecânica (corpo, não colisão física) que
			-- está cortando a velocidade, e de quem é o corpo.
			warn(("🦵 BallController: mecânica de corpo cortando a bola (%.1f studs/s) perto de %s%s"):format(
				speed, plr.Name, plr == recentKicker and " — ⚠️ É O PRÓPRIO CHUTADOR (imunidade deveria ter travado isso, ver BODY_BLOCK)" or ""))
		end

		local elapsed = tick() - contactStart
		if elapsed >= Config.BODY_BLOCK_EASE_SECONDS then
			-- janela de corte terminou — solta o corpo (debounce evita
			-- reabrir contato na mesma passada) e deixa a bola seguir livre.
			bodyBlockDebounce[plr] = tick()
			bodyBlockContactStart[plr] = nil
			blockedThisFrame = true
			break
		end

		local absorption = Config.BODY_BLOCK_MIN_ABSORPTION
			+ (Config.BODY_BLOCK_MAX_ABSORPTION - Config.BODY_BLOCK_MIN_ABSORPTION) * physicalFraction
		-- decaimento exponencial: multiplicar por (1-absorption)^(dt/EASE)
		-- a cada frame, durante EASE_SECONDS inteiro, dá exatamente
		-- (1-absorption) no total — só que suave, sem kink num frame só.
		local frameFactor = (1 - absorption) ^ (dt / Config.BODY_BLOCK_EASE_SECONDS)
		ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity * frameFactor

		blockedThisFrame = true
		-- só o primeiro corpo no caminho bloqueia nesse frame
		break
	end
end)

-- ===== GOLEIRO: MERGULHO (Z/X/C/E/Q) e DASH PRA FRENTE (F) =====
-- Substitui a antiga "chance de defesa automática": agora o goleiro
-- precisa ATIVAMENTE mergulhar/dashar na direção certa, na hora certa.
-- Enquanto "diving[player]" está ativo, um heartbeat próprio checa se a
-- bola passou perto o bastante (ver loop logo abaixo) — se sim, é
-- defesa (captura).
local DIVE_DIRECTION_VECTOR = {
	Left = function(root) return -root.CFrame.RightVector end,
	Right = function(root) return root.CFrame.RightVector end,
	Up = function(root) return Vector3.new(0, 1, 0) + root.CFrame.LookVector * 0.15 end,
	-- ⚠️ v5.4 FIX: "o dive diagonal está subindo demais e indo pouco pro
	-- lado". Era RightVector*0.7 + Y*1 — o peso vertical (1) já nasce
	-- MAIOR que o horizontal (0.7), então o mergulho saía mais "pra cima"
	-- que "pro lado" mesmo pedindo diagonal. Invertido: horizontal agora
	-- pesa mais que vertical (1.4 contra 0.85), então UpRight/UpLeft vão
	-- de verdade mais pro lado, só com uma subida menor.
	UpRight = function(root) return (root.CFrame.RightVector * 1.4 + Vector3.new(0, 0.85, 0)).Unit end,
	UpLeft = function(root) return (-root.CFrame.RightVector * 1.4 + Vector3.new(0, 0.85, 0)).Unit end,
}

-- PEDIDO: mergulho pro LADO e na DIAGONAL vão mais longe; o de ALTURA
-- (Up) mantém a distância de sempre — ver Config.GK_DIVE_DISTANCE* em
-- FootballConfig.lua.
local DIVE_DISTANCE_BY_DIRECTION = {
	Left = Config.GK_DIVE_DISTANCE_SIDE,
	Right = Config.GK_DIVE_DISTANCE_SIDE,
	Up = Config.GK_DIVE_DISTANCE,
	UpRight = Config.GK_DIVE_DISTANCE_DIAGONAL,
	UpLeft = Config.GK_DIVE_DISTANCE_DIAGONAL,
}

local function startGKMove(player, root, direction, distance, duration, targetPlayer)
	-- v110 — PEDIDO: "o dive do GK está atravessando a parede, só pode atravessar
	-- a hitbox do gol". Corta a distância antes de qualquer coisa SÓLIDA no
	-- caminho (a hitbox do gol não colide, então continua atravessável).
	if direction.Magnitude > 0.01 and distance > 0 then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local ignorar = { ball }
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then table.insert(ignorar, m) end
		end
		params.FilterDescendantsInstances = ignorar
		local hit = workspace:Raycast(root.Position, direction.Unit * (distance + 2), params)
		if hit then distance = math.max(0, (hit.Position - root.Position).Magnitude - 2.5) end
	end
	local dash = {
		startPosition = root.Position,
		endPosition = root.Position + direction * distance,
		triggeredAt = tick(),
		expiresAt = tick() + duration,
		targetPlayer = targetPlayer,
		resolved = false,
	}
	tackleDashes[player] = dash -- reaproveita o mesmo loop de deslocamento por CFrame (linha ~950)
	Remotes.SuppressShiftLockRotation:FireClient(player, duration)
	return dash
end

Remotes.AttemptGKDive.OnServerEvent:Connect(function(player, direction)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	if not GKAreaUtil.IsEffectiveGK(player) then return end -- só funciona goleiro DENTRO da própria área
	if isStunned(player) then return end
	if gkActionCooldowns[player] and tick() < gkActionCooldowns[player] then return end
	local vectorFn = typeof(direction) == "string" and DIVE_DIRECTION_VECTOR[direction]
	if not vectorFn then return end
	-- ⚠️ v105 — PEDIDO: "pode remover o dive diagonal (pula pra cima e pra
	-- direita/esquerda) — só o GK bot pode fazer isso" e "pra cima, não: ele
	-- pula alto". O goleiro humano só mergulha pro LADO (no chão ou no ar,
	-- depois do pulo alto — ver Config.GK_PULO_ALTURA / GKInput).
	if direction ~= "Left" and direction ~= "Right" then return end

	local _, root = getCharacterParts(player)
	if not root then return end

	gkActionCooldowns[player] = tick() + Config.GK_DIVE_COOLDOWN
	if _G.NotifyInstinctAction then _G.NotifyInstinctAction(player, "Dive") end -- ⚠️ v6.5: carga de "prática" do Instinct Mode

	local ownGoal = player.Team and ownGoalOf(player.Team.Name)
	local diveRadius = Config.GK_DIVE_CAPTURE_RADIUS
	local instEffect = _G.CheckInstinct and _G.CheckInstinct(player, "Dive", {
		DistanceToGoal = ownGoal and (ball.Position - ownGoal.Position).Magnitude or math.huge,
		IsSetPiece = deadBallMode,
	})
	if instEffect and instEffect.DiveRadiusAdd then diveRadius += instEffect.DiveRadiusAdd end
	if _G.GetPulseGKDiveBonus then
		local radiusAdd, guaranteed, minShotDistance = _G.GetPulseGKDiveBonus(player)
		local shotDistance = ownGoal and (ball.Position - ownGoal.Position).Magnitude or math.huge
		if radiusAdd and (not minShotDistance or shotDistance >= minShotDistance) then
			diveRadius += radiusAdd
			if guaranteed then diveRadius = math.max(diveRadius, 999) end
		end
	end
	if tick() - lastIgnoreGKShot < 1 then
		diveRadius = diveRadius * 0.5 -- Instinto Divino do Artilheiro: chute recente "ignora goleiro"
	end

	diving[player] = { ExpiresAt = tick() + Config.GK_DIVE_DURATION, Radius = diveRadius }
	setIframeGlow(player, true) -- janela ativa do mergulho: brilho branco
	playAnimation(player, gkDiveAnimationFor(direction), Enum.AnimationPriority.Action2, nil, true) -- ⚠️ v65: animação de mergulho de verdade, uma por direção (antes reaproveitava a finta de drible)
	local diveDistance = DIVE_DISTANCE_BY_DIRECTION[direction] or Config.GK_DIVE_DISTANCE
	-- ⚠️ v110 (Armas de goleiro: Mergulho Longo, Corpo Elástico, Muralha Divina)
	if instEffect and instEffect.DiveDistanceMult then diveDistance *= instEffect.DiveDistanceMult end
	startGKMove(player, root, vectorFn(root), diveDistance, Config.GK_DIVE_DURATION, nil)
end)

Remotes.AttemptGKForward.OnServerEvent:Connect(function(player)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	if not GKAreaUtil.IsEffectiveGK(player) then return end -- só funciona goleiro DENTRO da própria área
	if isStunned(player) then return end
	if gkActionCooldowns[player] and tick() < gkActionCooldowns[player] then return end

	local _, root = getCharacterParts(player)
	if not root then return end

	gkActionCooldowns[player] = tick() + Config.GK_FORWARD_COOLDOWN

	-- Se um adversário com a bola está perto o bastante, é roubo direto
	-- (igual um carrinho) — senão, se a BOLA (solta ou vindo) está perto,
	-- captura.
	local targetOwner = (owner and areOpponents(player, owner)) and owner or nil

	-- ⚠️ v5.5 FIX: mira e distância do dash agora dependem de ter um alvo
	-- perto (adversário com bola, ou a bola solta) — ver comentário em
	-- Config.GK_FORWARD_CHASE_RANGE. Sem alvo em alcance, é o dash curto
	-- de sempre, reto pra frente.
	local chasePosition = nil
	if targetOwner then
		local _, targetRoot = getCharacterParts(targetOwner)
		if targetRoot then chasePosition = targetRoot.Position end
	elseif not owner then
		chasePosition = ball.Position
	end

	-- ⚠️ v84 — PEDIDO: "dive e carrinho são pra direção apontada". A
	-- DIREÇÃO do avanço agora é SEMPRE pra onde o goleiro está apontado —
	-- antes ela virava sozinha pro alvo (bola/atacante) dentro do
	-- GK_FORWARD_CHASE_RANGE. O que sobrou do "perseguir" foi só o ALCANCE:
	-- se o alvo está À FRENTE dele (na direção apontada), o avanço estica
	-- até alcançá-lo, sem nunca mudar a direção.
	local look = root.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z)
	local direction = flatLook.Magnitude > 0.01 and flatLook.Unit or look
	local distance = Config.GK_FORWARD_DASH_DISTANCE
	local duration = Config.GK_FORWARD_DASH_DURATION

	if chasePosition then
		local toTarget = chasePosition - root.Position
		local flatToTarget = Vector3.new(toTarget.X, 0, toTarget.Z)
		local aFrente = flatToTarget:Dot(direction) -- distância do alvo projetada na direção apontada
		if flatToTarget.Magnitude <= Config.GK_FORWARD_CHASE_RANGE and aFrente > distance then
			distance = math.min(aFrente + Config.GK_FORWARD_STEAL_RANGE * 0.5, Config.GK_FORWARD_DASH_MAX_DISTANCE)
			duration = math.max(Config.GK_FORWARD_DASH_DURATION, distance / Config.GK_FORWARD_DASH_SPEED)
		end
	end

	playAnimation(player, Config.ANIMATIONS.GKForwardDash, nil, duration, true) -- ⚠️ v66: animação própria; duration é a duração REAL deste dash (varia por uso)

	-- ⚠️ v5.6 FIX: "continua voltando pro lugar antes do atacante sair da
	-- região dele, parece que ele anda por meio segundo e depois volta".
	-- Causa raiz: startGKMove reaproveita o MESMO loop de Heartbeat do
	-- carrinho normal (tackleDashes), e esse loop resolve o roubo NO MEIO
	-- do lunge assim que entra em Config.TACKLE_RANGE (7 studs) — mas essa
	-- resolução (resolveStealAttempt) é a do CARRINHO, que aplica
	-- applyTackleMiss (STUN) em qualquer falha (posse já mudou, alvo com
	-- iframe, alvo em finta...). Um goleiro perseguindo de longe quase
	-- sempre entra nesses 7 studs bem antes do fim do dash, leva o miss e
	-- STUNA no meio do caminho — visualmente é exatamente "anda e volta".
	-- Fix: passamos targetPlayer=nil pro startGKMove (assim o Heartbeat
	-- genérico NUNCA tenta resolver/stunar esse dash) e resolvemos o
	-- roubo/captura NÓS MESMOS, a cada frame, só em caso de SUCESSO —
	-- falhar simplesmente deixa o dash correr até o fim, sem punição.
	local dash = startGKMove(player, root, direction, distance, duration, nil)
	dash.isGKForward = true
	dash.gkTargetOwner = targetOwner -- pode ser nil (perseguindo bola solta)

	task.delay(duration, function()
		if tackleDashes[player] == dash then tackleDashes[player] = nil end
		if dash.resolved then return end -- já resolvido durante o próprio dash (ver Heartbeat)

		local _, currentRoot = getCharacterParts(player)
		if not currentRoot then return end

		-- ⚠️ v3: iframe de Pulso protege contra QUALQUER desarme, inclusive
		-- o dash do goleiro (ver _G.GrantPulseIframe acima).
		if targetOwner and owner == targetOwner and not (_G.HasPulseIframe and _G.HasPulseIframe(targetOwner)) then
			local _, targetRoot = getCharacterParts(targetOwner)
			if targetRoot and (currentRoot.Position - targetRoot.Position).Magnitude <= Config.GK_FORWARD_STEAL_RANGE then
				local stolenFrom = targetOwner
				releaseOwner()
				ball.CanCollide = true
				tackleSound:Play()
				setOwner(player)
				if _G.RegisterTackle then _G.RegisterTackle(player, stolenFrom) end
				return
			end
		end

		if not owner and (currentRoot.Position - ball.Position).Magnitude <= Config.GK_FORWARD_CAPTURE_RANGE then
			ball.CanCollide = true
			setOwner(player)
			return
		end
		-- ⚠️ v122 — PEDIDO: "o dash pra frente levanta mais devagar": errou = fica no
		-- chão o tempo da animação de levantar (GKForwardDash 0.6 → 1.45)
		if owner ~= player then stunPlayer(player, Config.GK_FORWARD_ERRO_STUN or 0.85) end
	end)
end)

-- Resolve a captura durante o mergulho: enquanto "diving[player]" está
-- ativo, se a bola passar perto o bastante (Radius) e não tiver dono, é
-- defesa — vira posse do goleiro na hora.
RunService.Heartbeat:Connect(function()
	if ballFrozenForGuardQTE then return end -- bola travada esperando o QTE de colisão da guarda de Hissatsu — ninguém mais mexe nela (ver mais abaixo)
	for player, dive in pairs(diving) do
		if tick() >= dive.ExpiresAt then
			diving[player] = nil
			setIframeGlow(player, false)
			-- ⚠️ v122 — PEDIDO: "punição pra quem errar o dive": não pegou = fica no chão
			-- e levanta devagar, sem poder andar nem agir (igual a animação)
			if owner ~= player then stunPlayer(player, Config.GK_DIVE_ERRO_STUN or 1.0) end
			continue
		end
		local _, root = getCharacterParts(player)
		if not root then
			diving[player] = nil
			continue
		end
		if owner and owner ~= player then continue end -- bola já com um adversário, mergulho não intercepta posse formal

		-- Só captura bola vindo em direção ao PRÓPRIO gol (chute/cruzamento
		-- perigoso) ou já lenta/solta (qualquer direção) — assim um passe
		-- do próprio time que só passa perto não vira captura sem querer.
		local ownGoal = player.Team and ownGoalOf(player.Team.Name)
		local movingTowardOwnGoal = true
		if ownGoal and ball.AssemblyLinearVelocity.Magnitude > LOOSE_BALL_PICKUP_MAX_SPEED then
			local towardGoal = (ownGoal.Position - ball.Position)
			movingTowardOwnGoal = towardGoal:Dot(ball.AssemblyLinearVelocity) > 0
		end

		-- FIX (bola no ar): antes comparava a distância 3D cheia (inclui
		-- altura) contra dive.Radius — um cabeceio/cruzamento alto "gastava"
		-- boa parte do raio só na diferença de altura, sobrando pouca
		-- margem horizontal e fazendo o goleiro perder bola que deveria
		-- pegar. Agora horizontal (XZ) e vertical são checados SEPARADOS:
		-- dive.Radius é só a margem horizontal, e GK_DIVE_CAPTURE_HEIGHT é
		-- uma tolerância vertical bem mais generosa — pegar bola alta fica
		-- bem mais fácil, sem afrouxar a exigência horizontal de sempre.
		local horizontalDistance = (Vector3.new(ball.Position.X, 0, ball.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		local verticalDistance = math.abs(ball.Position.Y - root.Position.Y)
		-- ⚠️ v7 PEDIDO: "o goleiro só vai poder pegar a bola dando só o
		-- mergulho se o físico dele for maior que a força dela" — chute
		-- perigoso demais pro Physical atual não é pego aqui (mergulho
		-- normal fica curto), só resta ele já ter armado uma guarda de
		-- Hissatsu (ver o sistema de colisão logo abaixo).
		local strongEnough = getPhysical(player) >= currentDangerForceRating(player)
		if horizontalDistance <= dive.Radius and verticalDistance <= Config.GK_DIVE_CAPTURE_HEIGHT and movingTowardOwnGoal and strongEnough then
			diving[player] = nil
			setIframeGlow(player, false)
			ball.CanCollide = true
			ball.AssemblyLinearVelocity = Vector3.zero
			setOwner(player)

			-- Defesa de verdade (mergulho pegando bola vindo perigosa em
			-- direção ao próprio gol) — alimenta Stats.Saves, usado pelas
			-- missões diárias de goleiro (ver QuestData.luau no Lobby).
			if _G.RegisterSave then
				_G.RegisterSave(player)
			end
		end
	end
end)

-- ⚠️ v105 — HITBOX DO GOLEIRO. PEDIDO: "a hitbox do goleiro vai pegar
-- automaticamente a partir de agora. Se a bola parar e passar nele, no meio
-- dele, tanto do GK quanto do GK bot, ele vai pegar na hora." (O bot já tinha
-- a caixa garantida — GKBOT_GUARANTEED_CATCH_BOX.) Goleiro humano DENTRO da
-- própria área: bola sem dono encostando no corpo = dele. Não vale pra
-- Hissatsu em voo (essa passa pela guarda/duelo), nem logo depois do próprio
-- arremesso, nem com "ignora goleiro" recente.
-- ⚠️ v120b — PEDIDO: "o GK player pega a bola simplesmente se ela passar dentro
-- dele, independente da força, mesmo sem dive — numa hitbox em volta dele, um
-- pouco maior que ele". Chute forte ATRAVESSAVA: a 150 studs/s a bola anda ~2,5
-- studs por quadro e pulava a caixa. Agora testa o CAMINHO da bola entre um
-- quadro e o outro (amostras a cada ~0,8 stud), não só a posição atual.
do
	local posAnterior = nil
	RunService.Heartbeat:Connect(function()
		local atual = ball.Position
		local anterior = posAnterior or atual
		posAnterior = atual
		if ballFrozenForGuardQTE or owner or deadBallMode or pulseStraightFlightActive then return end
		if tick() - lastIgnoreGKShot < 1 then return end
		local caixa = Config.GK_CORPO_CAPTURA or { Raio = 3.3, Baixo = 3.6, Alto = 4.2 }
		local passo = atual - anterior
		if passo.Magnitude > 30 then anterior = atual passo = Vector3.zero end -- (teleporte/reset: não é caminho)
		local amostras = math.clamp(math.ceil(passo.Magnitude / 0.8), 1, 40)
		for _, plr in ipairs(Players:GetPlayers()) do
			if not GKAreaUtil.IsEffectiveGK(plr) or isStunned(plr) then continue end
			if recentKicker == plr and tick() - recentKickTime < 0.6 then continue end
			local _, root = getCharacterParts(plr)
			if not root then continue end
			for i = 1, amostras do
				local rel = (anterior + passo * (i / amostras)) - root.Position
				if Vector3.new(rel.X, 0, rel.Z).Magnitude <= caixa.Raio and rel.Y >= -caixa.Baixo and rel.Y <= caixa.Alto then
					local vinhaRapida = ball.AssemblyLinearVelocity.Magnitude > LOOSE_BALL_PICKUP_MAX_SPEED
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.CanCollide = true
					setOwner(plr)
					if vinhaRapida and _G.RegisterSave then _G.RegisterSave(plr) end
					return
				end
			end
		end
	end)
end

-- ===== FINTA DIRECIONAL (Z esquerda / X trás / C direita) =====
-- ⚠️ NOVO — DRIBLE DIRECIONAL (tecla Q). PEDIDO: "A direção do drible deve
-- ser determinada pelo input de movimento no momento em que Q for
-- pressionado. W+Q frente, S+Q trás, A+Q esquerda, D+Q direita, W+D+Q
-- diagonal..." O cliente manda o Humanoid.MoveDirection (vetor do WASD em
-- espaço de mundo, relativo à câmera) em vez de um nome fixo. Tratado como
-- palpite: achatado no plano e normalizado aqui (sem finta pra cima, nem
-- magnitude inflada). Sem input (parado) = pra frente do personagem.
local function getDribbleDirectionFromInput(root, inputDirection)
	local flat = Vector3.new(inputDirection.X, 0, inputDirection.Z)
	if flat.Magnitude > 0.1 then return flat.Unit end
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	return look.Magnitude > 0.01 and look.Unit or root.CFrame.LookVector
end

-- Qual das animações de finta existentes (Left/Back/Right) combina com a
-- direção escolhida, RELATIVA a pra onde o personagem está virado. Lado
-- dominante = Left/Right (inclui as diagonais); senão, Back (que também é
-- o fallback de dribbleAnimationFor pra frente, que não tem animação própria).
-- ⚠️ v86 — PEDIDO: "drible direcional para a esquerda, para a direita, para
-- trás ou para frente, para frente também pode acontecer". Agora existe o
-- "Forward" de verdade (antes a frente caía no Back): sem lado dominante, o
-- sinal da frente/trás decide. A animação do Forward é o Back ao contrário
-- (ver dribbleAnimationFor/playAnimation).
local function dribbleAnimationNameFor(root, direction)
	local lateral = direction:Dot(root.CFrame.RightVector)
	if math.abs(lateral) >= 0.5 then
		return lateral > 0 and "Right" or "Left"
	end
	return direction:Dot(root.CFrame.LookVector) > 0 and "Forward" or "Back"
end

-- ⚠️ v103: nome da ANIMAÇÃO com diagonal (ForwardRight, BackLeft...) — só
-- pro rolamento na diagonal; o movimento da finta continua o de sempre.
local function nomeDribleComDiagonal(root, direction)
	local lateral = direction:Dot(root.CFrame.RightVector)
	local frente = direction:Dot(root.CFrame.LookVector)
	if math.abs(lateral) >= 0.35 and math.abs(frente) >= 0.35 then
		return (frente > 0 and "Forward" or "Back") .. (lateral > 0 and "Right" or "Left")
	end
	return dribbleAnimationNameFor(root, direction)
end

local function getSkillMoveDirectionVector(root, moveName)
	if moveName == "Left" then
		return -root.CFrame.RightVector
	elseif moveName == "Right" then
		return root.CFrame.RightVector
	elseif moveName == "Back" then
		return -root.CFrame.LookVector
	elseif moveName == "Forward" then
		return root.CFrame.LookVector
	end
	return nil
end

-- ⚠️ v86: toca a finta certa pra direção — o Forward, sem animação própria
-- no Config, reaproveita o Back AO CONTRÁRIO.
local function playDribbleAnimation(player, moveName, window, nomeAnimacao)
	local conf = Config.ANIMATIONS.Dribble
	local reverso = moveName == "Forward" and not (type(conf) == "table" and conf.Forward)
	-- ⚠️ v103: com a animação por código, manda o nome da ação direto (inclui
	-- as diagonais do rolamento)
	local nomeAcao = Config.ANIMACAO_PROCEDURAL and ("Dribble." .. (nomeAnimacao or moveName)) or nil
	playAnimation(player, dribbleAnimationFor(moveName), Enum.AnimationPriority.Action2, window, true, nil, reverso, nomeAcao)
end

-- ⚠️ v86 — PEDIDO: "Não precisa travar o personagem durante o drible... O
-- drible vai só mover o personagem, só que pode deixar ele continuando
-- andando". Antes o servidor PRENDIA o corpo numa linha reta (CFrame a cada
-- quadro, velocidade zerada e Humanoid:Move(0)) — o jogador perdia o
-- controle até a finta acabar. Agora o servidor só avisa o cliente do dono do
-- personagem (quem simula a física dele) quanto deslocar e em quanto tempo;
-- o cliente SOMA esse empurrão ao movimento normal a cada quadro, então o
-- WASD continua valendo durante toda a finta. Fazer isso no servidor não
-- funcionaria: a cópia do servidor está sempre alguns ms atrasada, e cada
-- CFrame escrito lá puxaria o personagem de volta pra essa posição velha.
local function sendDisplacement(player, offset, duration)
	if player and player.Parent == Players then
		Remotes.ApplyDisplacement:FireClient(player, offset, duration)
	end
end

-- ANKLE BREAKER: qualquer ADVERSÁRIO (checagem de time — nunca
-- companheiro) que estiver perto o suficiente do driblador no instante
-- da finta leva um stun curto, igual "caiu de tanto que balançou". Usa a
-- posição do driblador NO INSTANTE DA FINTA (antes dele se deslocar),
-- que é quem realmente estava "perto" o bastante pra ter sido enganado.
-- Retorna true se pelo menos um adversário foi derrubado — usado pra
-- decidir se o "mini-dash" pós-drible (ver Config.DRIBBLE_MINIDASH_*)
-- deve disparar: só acontece quando o drible REALMENTE acertou alguém.
local function applyAnkleBreaker(mover, moverRoot, rangeBonus, stunBonus, alwaysStun)
	local range = Config.ANKLE_BREAKER_RANGE + (rangeBonus or 0)
	local stun = Config.ANKLE_BREAKER_STUN + (stunBonus or 0)
	local hitAny = false
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == mover then continue end
		if not areOpponents(mover, plr) then continue end -- nunca em cima de companheiro de time

		local _, defenderRoot = getCharacterParts(plr)
		if not defenderRoot then continue end

		-- ⚠️ v67 — PEDIDO: "quando eu driblo na cara do jogador ele stuna
		-- automaticamente. Não é pra ser assim. O stun só pode acontecer caso
		-- o jogador adversário USE O CARRINHO na direção do jogador que está
		-- driblando."
		--
		-- Antes bastava estar PERTO: qualquer defensor no raio caía no chão
		-- só por você fintar ao lado dele, sem ter feito nada. Agora o drible
		-- só derruba quem se COMPROMETEU — quem está no meio de um carrinho.
		-- Isso é o que transforma a finta numa resposta ao desarme, em vez de
		-- uma arma que pune quem está só marcando.
		--
		-- `alwaysStun` (Arma Ginga) continua valendo, mas agora garante o
		-- stun em quem CARRINHOU, não em qualquer um por perto.
		local carrinhando = tackleDashes[plr] ~= nil and tick() < (tackleDashes[plr].expiresAt or 0)
		if not carrinhando then continue end

		local distance = (defenderRoot.Position - moverRoot.Position).Magnitude
		if distance <= range or alwaysStun then
			stunPlayer(plr, stun)
			ragdollPlayer(plr, Config.ANKLE_BREAKER_RAGDOLL_DURATION)
			if _G.MostrarTontura then _G.MostrarTontura(plr, stun) end -- ⚠️ v120b: tontura onde atordoa
			hitAny = true
		end
	end
	return hitAny
end

-- MINI-DASH pós-drible: quando o drible acerta e derruba um adversário,
-- o driblador ganha uma distância EXTRA na mesma deslizada (além de
-- derrubar o jogador, "vai um pouco pra frente" pra não perder a
-- vantagem). Escala com DribbleSkill (0-1), mas de forma limitada — em
-- skill 100 chega a Config.DRIBBLE_MINIDASH_MAX_MULT vezes a distância-
-- base do mini-dash (não escala linear com a distância normal do
-- drible inteiro, senão fica muito OP).
local function getMinidashBonusDistance(hitOpponent, skill)
	if not hitOpponent then return 0 end
	return Config.DRIBBLE_MINIDASH_BASE_DISTANCE
		* (1 + skill * (Config.DRIBBLE_MINIDASH_MAX_MULT - 1))
end

Remotes.AttemptDribbleMove.OnServerEvent:Connect(function(player, moveName)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	if owner ~= player then return end
	if isStunned(player) then return end
	-- ⚠️ v24: nem finta por fora de uma Hissatsu de bola em andamento — a
	-- finta desloca a bola e faria a Hissatsu resolver sem ela no pé.
	if _G.IsPulseInProgress and _G.IsPulseInProgress(player) then return end
	if GKAreaUtil.IsEffectiveGK(player) then return end -- GK DENTRO da área usa AttemptGKDive (Z/X/C/E/Q viram mergulho, não finta); fora da área, finta normal

	local direction
	local nomeAnimacaoDrible = nil -- ⚠️ v103: com diagonal (ver nomeDribleComDiagonal)
	local _, rootForDirection = getCharacterParts(player)
	if rootForDirection then
		if typeof(moveName) == "Vector3" then
			-- ⚠️ NOVO: Q + WASD (ver getDribbleDirectionFromInput acima).
			direction = getDribbleDirectionFromInput(rootForDirection, moveName)
			moveName = dribbleAnimationNameFor(rootForDirection, direction)
			nomeAnimacaoDrible = nomeDribleComDiagonal(rootForDirection, direction)
		elseif typeof(moveName) == "string" then
			-- Nome fixo (Left/Back/Right) continua aceito: botões do mobile e
			-- chamadas antigas.
			direction = getSkillMoveDirectionVector(rootForDirection, moveName)
		end
	end
	if not direction then return end
	if _G.NotifyInstinctAction then _G.NotifyInstinctAction(player, "DribbleMove") end -- ⚠️ v6.5: carga de "prática" do Instinct Mode

	local _, rootForCtx = getCharacterParts(player)
	local dribbleCtx = {}
	if rootForCtx and player.Team then
		dribbleCtx.AttackingHalf = attackingHalfOf(player.Team.Name, rootForCtx.Position)
		dribbleCtx.DistanceToByline = distanceToBylineOf(player.Team.Name, rootForCtx.Position)
	end
	local instEffect = _G.CheckInstinct and _G.CheckInstinct(player, "DribbleMove", dribbleCtx)
	local cooldownMult = (instEffect and instEffect.OwnCooldownMult) or 1
	local effectiveCooldown = Config.DRIBBLE_MOVE_COOLDOWN * cooldownMult

	local lastAttempt = dribbleMoveCooldowns[player]
	if lastAttempt and tick() - lastAttempt < effectiveCooldown then return end

	local _, root = getCharacterParts(player)
	if not root then return end

	if not Config.SpendStamina(player, Config.DRIBBLE_MOVE_STAMINA_COST) then
		warn(player.Name .. " tentou uma finta mas não tem stamina suficiente.")
		return
	end

	dribbleMoveCooldowns[player] = tick()

	-- Conta pra estatística de partida (Stats.Dribbles em
	-- MatchController.legacy.luau) — alimenta o sistema de missões diárias
	-- do Lobby ("Driblar 20 vezes", ver QuestData.luau) via
	-- LobbyRewardsReceiver.legacy.luau quando a recompensa chega no Lobby.
	if _G.RegisterDribble then
		_G.RegisterDribble(player)
	end
	if _G.TutorialNotificar then _G.TutorialNotificar(player, "Drible") end -- ⚠️ v104

	-- SEMPRE dá certo — sem porcentagem/chance. Só a distância e a janela
	-- de iframe escalam com o DribbleSkill (0-100) do jogador.
	local skill = getDribbleSkill(player)
	local distance = Config.DRIBBLE_MOVE_MIN_DISTANCE
		+ (Config.DRIBBLE_MOVE_MAX_DISTANCE - Config.DRIBBLE_MOVE_MIN_DISTANCE) * skill
	local window = Config.DRIBBLE_ANIMATION_SECONDS -- ⚠️ v64: janela FIXA (= tempo da animação); a distância é que escala, logo a velocidade escala junto

	playDribbleAnimation(player, moveName, window, nomeAnimacaoDrible) -- ⚠️ v63: reprodução ajustada à janela; v86: Forward = Back ao contrário; v103: diagonais

	local pulseEffect = _G.TryConsumePulse and _G.TryConsumePulse(player, "DribbleMove")
	local rangeBonus = (instEffect and instEffect.AnkleRangeAdd or 0) + (pulseEffect and pulseEffect.AnkleRangeAdd or 0)
		+ (_G.GetPulseActiveAnkleRangeAdd and _G.GetPulseActiveAnkleRangeAdd(player) or 0)
	-- ⚠️ v5.4 FIX: rangeBonus (acima) já somava instEffect + pulseEffect,
	-- mas stunBonus/alwaysStun só liam pulseEffect — ou seja, um Instinto
	-- (não Pulso) com AnkleStunAdd/AlwaysStun no Effect (caso de "Monstro
	-- do Drible" agora) nunca aplicava o stun garantido na finta manual
	-- (Z/X/C). Era esse o motivo de "a lambreta não acontece".
	local stunBonus = (instEffect and instEffect.AnkleStunAdd or 0) + (pulseEffect and pulseEffect.AnkleStunAdd or 0)
	local alwaysStun = (instEffect and instEffect.AlwaysStun) or (pulseEffect and pulseEffect.AlwaysStun)
	local hitOpponent = applyAnkleBreaker(player, root, rangeBonus, stunBonus, alwaysStun) -- stun nos adversários perto o suficiente pra terem sido "driblados"
	local dashDistance = getMinidashBonusDistance(hitOpponent, skill)

	-- O personagem desliza em linha reta de startPosition até endPosition
	-- durante toda a janela (window), via CFrame direto no loop principal
	-- — chega exatamente junto com a bola, sempre, sem depender de
	-- WalkSpeed/Humanoid:Move nem brigar com sprint/exaustão. Se acertou
	-- o drible (derrubou alguém), dashDistance soma um "mini-dash" extra
	-- na mesma deslizada — mesma janela de tempo, então o pique fica
	-- visivelmente mais rápido nesse trecho final.
	-- ⚠️ v86: o deslocamento agora é aplicado pelo cliente, SOMADO ao andar
	-- (ver sendDisplacement). O servidor guarda só o deslocamento total, pra
	-- saber onde conduzir a bola durante a finta. A rotação também fica livre
	-- (não suprime mais o Shift Lock): quem gira é o próprio jogador.
	local offset = direction * (distance + dashDistance)
	local endPosition = root.Position + offset
	dribbleMoves[player] = {
		targetPosition = endPosition,
		startPosition = root.Position,
		endPosition = endPosition,
		offset = offset,
		triggeredAt = tick(),
		expiresAt = tick() + window,
	}
	setIframeGlow(player, true) -- janela de iframe ativa: brilho branco enquanto durar
	sendDisplacement(player, offset, window)
end)

-- ===== DASH (tecla F) — ⚠️ v86 =====
-- PEDIDO: "o F pode ser utilizado para dar um dash, que é meio que um avanço
-- para frente". NÃO é o carrinho (esse voltou pro Q, sem bola): não rouba,
-- não disputa e não derruba ninguém — é só um arranque curto na direção do
-- WASD (parado = pra onde o personagem olha), com ou sem a bola. O
-- deslocamento é aplicado pelo cliente, somado ao andar (sendDisplacement),
-- então o jogador não perde o controle durante o arranque. Goleiro dentro da
-- própria área continua usando o F pra saída do gol (AttemptGKForward).
do
	local dashCooldowns = {}
	Players.PlayerRemoving:Connect(function(plr) dashCooldowns[plr] = nil end)

	Remotes.AttemptDash.OnServerEvent:Connect(function(player, directionArg)
		if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
		if isStunned(player) then return end
		if tackleDashes[player] then return end
		if GKAreaUtil.IsEffectiveGK(player) then return end
		if _G.IsPulseInProgress and _G.IsPulseInProgress(player) then return end

		local last = dashCooldowns[player]
		if last and tick() - last < Config.DASH_COOLDOWN then return end

		local _, root = getCharacterParts(player)
		if not root then return end

		-- mesma desconfiança do carrinho: a direção vem do cliente, então é
		-- achatada e normalizada aqui (nada de dash pra cima nem mais longe)
		local direction
		if typeof(directionArg) == "Vector3" then
			local flat = Vector3.new(directionArg.X, 0, directionArg.Z)
			if flat.Magnitude > 0.1 then direction = flat.Unit end
		end
		if not direction then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if look.Magnitude < 0.01 then return end
			direction = look.Unit
		end

		if not Config.SpendStamina(player, Config.DASH_STAMINA_COST) then return end
		dashCooldowns[player] = tick()

		sendDisplacement(player, direction * Config.DASH_DISTANCE, Config.DASH_DURATION)
		-- ⚠️ v104: animação de arrancada (+ o vento, ver VentoVelocidade.local.luau).
		-- A direção vai no espaço do corpo pra inclinar certo (lado/trás).
		local rel = root.CFrame:VectorToObjectSpace(direction)
		avisarAcao(player.Character, "Dash", Config.DASH_DURATION, { X = rel.X, Z = -rel.Z })
		if _G.TutorialNotificar then _G.TutorialNotificar(player, "Dash") end -- ⚠️ v104
	end)
end

-- ===== CHUTE (também serve de PASSE e de VOLEIO) =====
-- PASSE: não existe mais botão dedicado — se você mirar (com o mouse) num
-- companheiro em vez do gol, é o mesmo KickBall, só que "fraco" e apontado
-- pra ele. A assistência continua funcionando normal via lastTouchers.
-- VOLEIO: se a bola estiver no ar e você NÃO tiver posse, ainda pode
-- chutar (igual a cabeçada já permite), com um bônus de força.
-- ⚠️ v60 — ANIMAÇÃO DE PREPARO DO CHUTE.
-- O cliente já avisa quando o jogador começa e para de carregar o chute
-- (Remotes.UpdateKickCharging) — o PlayerSystems usa esse mesmo aviso pra
-- reduzir a velocidade de caminhada. Aqui vai um SEGUNDO listener no mesmo
-- Remote (RemoteEvent aceita vários) só pra ligar/desligar a animação. Fica
-- neste arquivo, e não no PlayerSystems, porque playAnimation/stopAnimation
-- moram aqui — mover a animação pra lá exigiria expor as duas por _G sem
-- ganhar nada em troca.
--
-- A animação de preparo é em LOOP (0.25s): ela segura a pose enquanto o
-- jogador estiver carregando, por quanto tempo for. Quem a encerra é o
-- próprio soltar do botão, logo abaixo — e a animação de chute entra por
-- cima na mesma prioridade.
Remotes.UpdateKickCharging.OnServerEvent:Connect(function(player, carregando)
	-- ⚠️ v85: estado publicado como ATRIBUTO (replica de forma confiável pra
	-- todo cliente). Testado ao vivo: o Stop do preparo encerrava a track no
	-- servidor, mas a cópia do cliente — parada no último quadro — ficava
	-- presa na pose ("a animação fica paralisada"). O AnimationGuard.local.
	-- luau encerra o preparo localmente assim que isto vira false.
	player:SetAttribute("KickCharging", carregando == true)
	if carregando then
		-- roda uma vez e CONGELA no último frame (perna levantada) até soltar
		playAnimation(player, Config.ANIMATIONS.PrepareKick, nil, nil, nil, true)
	else
		stopAnimation(player, Config.ANIMATIONS.PrepareKick)
	end
end)

-- (⚠️ v120b: com nome em _G pra dar pra testar o chute pelo servidor; sem local novo no topo)
_G.ProcessarChuteServidor = function(player, chargedForce, targetPoint, noAr, tentativaGuardada, movimentoCliente)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	if isStunned(player) then return end
	-- ⚠️ v24: com uma Hissatsu de bola em andamento, a bola não sai do pé por
	-- fora dela (ver _G.IsPulseInProgress em PulseController.legacy.luau).
	if _G.IsPulseInProgress and _G.IsPulseInProgress(player) then return end
	if typeof(targetPoint) ~= "Vector3" then return end
	-- ⚠️ v110 — "a bola sumiu de novo" (log: "cortando a bola (nan studs/s)" logo
	-- depois do próprio chute). Mira ou força com NaN/infinito vindas do cliente
	-- viravam direção NaN e a bola ia pro espaço. Mira inválida = chuta pra frente.
	if targetPoint.X ~= targetPoint.X or targetPoint.Y ~= targetPoint.Y or targetPoint.Z ~= targetPoint.Z
		or math.abs(targetPoint.X) > 1e6 or math.abs(targetPoint.Y) > 1e6 or math.abs(targetPoint.Z) > 1e6 then
		targetPoint = nil
	end
	local forcaNum = tonumber(chargedForce)
	if forcaNum and (forcaNum ~= forcaNum or math.abs(forcaNum) == math.huge) then
		chargedForce = nil
	end

	local _, root = getCharacterParts(player)
	if not root then return end
	targetPoint = targetPoint or (root.Position + root.CFrame.LookVector * 60)

	local hasControl = owner == player
	local isVolley = false
	-- ⚠️ v105: goleiro com a bola NA MÃO arremessa (animação própria)
	local arremessoDoGoleiro = hasControl and player:GetAttribute("BolaNaMao") == true

	if not hasControl then
		-- ⚠️ v108 — PRIMEIRO TOQUE. PEDIDO: "nem precisa dominar, ele pode chutar
		-- direto, antes mesmo do domínio... se a bola estiver fraca na frente dele.
		-- Se estiver forte, já não dá". Antes (v105) sem posse só valia VOLEIO
		-- pulando — bola rolando fraca na sua frente, sem ninguém dominando, não
		-- dava pra bater de primeira. Agora: bola SOLTA (ninguém é dono, não é
		-- Hissatsu voando nem duelo de goleiro), ao alcance e mais lenta que
		-- PRIMEIRO_TOQUE_VEL_MAX = chute de primeira. Se for no ar com a bola
		-- alta, continua sendo VOLEIO (mais forte).
		local ballHeightAboveGround = ball.Position.Y - root.Position.Y
		local distance = (ball.Position - root.Position).Magnitude
		local bolaLivre = owner == nil and not ballFrozenForGuardQTE and not pulseStraightFlightActive
		local bolaFraca = ball.AssemblyLinearVelocity.Magnitude <= (Config.PRIMEIRO_TOQUE_VEL_MAX or 80)
		-- ⚠️ v119 — PEDIDO: "aumenta a hitbox em 1.5x pra dar voleio". Só a bola NO AR
		-- (voleio) ganha o alcance maior; o toque de primeira rasteiro fica igual.
		local ehVoleio = noAr == true and ballHeightAboveGround >= Config.VOLLEY_MIN_BALL_HEIGHT
		local alcanceToque = Config.VOLLEY_RANGE * (ehVoleio and (Config.VOLLEY_HITBOX_MULT or 1.5) or 1)
		-- ⚠️ v121: o voleio mede na HORIZONTAL (com teto de altura próprio)
		if ehVoleio then
			local rel = ball.Position - root.Position
			distance = Vector3.new(rel.X, 0, rel.Z).Magnitude
			if math.abs(rel.Y) > (Config.VOLLEY_ALTURA_MAX or 14) then distance = math.huge end
		end
		if not bolaLivre or not bolaFraca or distance > alcanceToque then
			-- ⚠️ v121 — CHUTE ANTECIPADO: a bola ainda não chegou — guarda o pedido por
			-- CHUTE_ANTECIPADO_SEG; se ela chegar nesse tempo, o chute sai sozinho
			if tentativaGuardada then return "fora" end
			if _G.GuardarChuteAntecipado then
				_G.GuardarChuteAntecipado(player, chargedForce, targetPoint, noAr, movimentoCliente)
			end
			-- ⚠️ v85 — PEDIDO: "se eu chutar sem a bola, a animação de chutar
			-- não sai... a animação de chute precisa sair mesmo sem a bola".
			-- Antes o handler só saía daqui — o preparo (perna levantada) era
			-- encerrado pelo UpdateKickCharging(false) e nenhum chute entrava
			-- no lugar, então a pose parecia travada e o movimento nunca
			-- terminava. Agora é um chute no vazio: a animação toca inteira
			-- (mesmo corte dos dribles do chute de verdade, ver o fim deste
			-- handler), só a bola não é tocada.
			for _, direcao in ipairs({ "Left", "Back", "Right" }) do
				stopAnimation(player, dribbleAnimationFor(direcao), 0)
			end
			playAnimation(player, Config.ANIMATIONS.Kick, nil, nil, true)
			return
		end
		isVolley = noAr == true and ballHeightAboveGround >= Config.VOLLEY_MIN_BALL_HEIGHT
	end

	if _G.NotifyInstinctAction then _G.NotifyInstinctAction(player, "Kick") end -- ⚠️ v6.5: carga de "prática" do Instinct Mode

	-- PEDIDO: chute não gasta mais estamina (nem bloqueia por falta dela)
	-- — antes tinha Config.SpendStamina(player, Config.KICK_STAMINA_COST)
	-- aqui, que além de drenar também RECUSAVA o chute se a stamina não
	-- desse. Drible/cabeceio/carrinho continuam gastando normalmente.

	local kickMaxForce = Config.KICK_MAX_FORCE * getKickForceMultiplier(player) * getGKAreaKickBonus(player) -- ⚠️ v67: bônus do goleiro na própria área (só aqui, nunca em Hissatsu)
	local force = math.clamp(tonumber(chargedForce) or Config.KICK_MIN_FORCE, Config.KICK_MIN_FORCE, kickMaxForce)
	if isVolley then
		force = math.min(kickMaxForce, force * Config.VOLLEY_FORCE_MULTIPLIER)
	end

	-- ===== PULSO/INSTINTO: classifica o chute e aplica os efeitos =====
	-- "SetPiece" durante bola parada; senão, se o alvo está mais perto de
	-- um companheiro do que do gol adversário, é "KickAtTeammate";
	-- senão, "KickAtGoal" (padrão, mesmo sem time definido).
	local aimDeviationMult = 1
	local kickTrigger = nil
	local armaDoChute = nil -- ⚠️ v110: Effect da Arma que disparou neste chute (Curva, CompanheiroForcaMult)
	if player.Team then
		local trigger = "KickAtGoal"
		local enemyGoal = enemyGoalOf(player.Team.Name)
		local ownGoal = ownGoalOf(player.Team.Name)
		local distanceToGoal = enemyGoal and (targetPoint - enemyGoal.Position).Magnitude or math.huge
		local distanceToOwnGoal = ownGoal and (root.Position - ownGoal.Position).Magnitude or math.huge

		if deadBallMode then
			trigger = "SetPiece"
		else
			local nearestTeammate, teammateDistance = nil, math.huge
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr == player then continue end
				if areOpponents(player, plr) then continue end
				local _, mateRoot = getCharacterParts(plr)
				if not mateRoot then continue end
				local d = (targetPoint - mateRoot.Position).Magnitude
				if d < teammateDistance then teammateDistance = d; nearestTeammate = plr end
			end
			if nearestTeammate and teammateDistance < 10 and teammateDistance < distanceToGoal then
				trigger = "KickAtTeammate"
			end
		end

		-- ⚠️ v5.4: "Ego do Rei" — fora da área ADVERSÁRIA de verdade
		-- (fallback false: se a Part GKArea_<TimeAdversário> não existir na
		-- cena, considera "fora" pra não travar o Instinto — mesma
		-- filosofia do resto do módulo, só que na direção oposta do
		-- Sentinela, que quer "dentro"). E se o chute foi carregado até a
		-- força máxima: compara o valor BRUTO que o cliente mandou (o
		-- cliente sempre carrega até Config.KICK_MAX_FORCE, nunca até o
		-- kickMaxForce já multiplicado — ver FootballClient.local.luau) com
		-- Config.KICK_MAX_FORCE, não com kickMaxForce.
		local enemyTeamName = otherTeamName(player.Team.Name)
		local ctx = {
			-- ⚠️ v111 — BUG: era a distância do PONTO MIRADO até o gol. Mirando
			-- no gol ela dá poucos studs, então "chute de fora da área" (Ego do
			-- Rei), "a mais de 25 studs" (Tiro Destruidor) e a Zona de Ouro
			-- (~124 studs) quase nunca batiam. Agora é de onde VOCÊ chuta.
			DistanceToGoal = enemyGoal and (root.Position - enemyGoal.Position).Magnitude or math.huge,
			TargetDistanceToGoal = distanceToGoal,
			DistanceToOwnGoal = distanceToOwnGoal,
			SecondsAfterReceive = lastReceiveTime[player] and (tick() - lastReceiveTime[player]) or math.huge,
			OpponentDistance = nearestOpponentDistance(player),
			Role = player:GetAttribute("Role"),
			OutsideEnemyArea = not GKAreaUtil.IsPositionInArea(enemyTeamName, root.Position, false),
			IsMaxCharge = (tonumber(chargedForce) or 0) >= Config.KICK_MAX_FORCE - 0.5,
			-- ⚠️ v9: "Xeque-Mate" — leitura numérica de verdade (2 contra 1 ou
			-- melhor) num raio de 22 studs em volta de quem está com a bola,
			-- não "qualquer passe pra um companheiro perto".
			HasNumericalAdvantage = hasNumericalAdvantage(player, root.Position, 22),
			-- ⚠️ v12: "Zona de Ouro" precisa do ÂNGULO (não só da distância),
			-- e "Olho de Predador" precisa do estado do goleiro NESTE chute
			-- — os dois só existem no instante do chute, por isso ficam aqui
			-- e não no GetInstinctFieldContext contínuo.
			AngleToGoal = angleToGoalDegrees(root, enemyGoal, ownGoal),
			GoalkeeperOffGuard = goalkeeperOffGuard(player, targetPoint),
		}

		kickTrigger = trigger
		local instEffect = _G.CheckInstinct and _G.CheckInstinct(player, trigger, ctx)
		armaDoChute = instEffect
		local pulseEffect = _G.TryConsumePulse and _G.TryConsumePulse(player, trigger)
		local ignoreGKChance = 0
		if instEffect then
			force *= (instEffect.ForceMult or 1)
			ignoreGKChance = math.max(ignoreGKChance, instEffect.IgnoreGKChance or 0)
			if instEffect.AimDeviationMult then aimDeviationMult = math.min(aimDeviationMult, instEffect.AimDeviationMult) end
		end
		if pulseEffect then
			force *= (pulseEffect.ForceMult or 1)
			ignoreGKChance = math.max(ignoreGKChance, pulseEffect.IgnoreGKChance or 0) -- ⚠️ v3: a chave IgnoreGKChance também vale pro Pulso, não só pro Instinto
			if pulseEffect.AimDeviationMult then aimDeviationMult = math.min(aimDeviationMult, pulseEffect.AimDeviationMult) end
			if pulseEffect.DefenderContestRange then
				-- Pulso Lendário: Chute Fatal — um defensor perto o bastante
				-- da linha do chute ainda pode disputar o bloqueio (mesma
				-- lógica da disputa de carrinho, pelo Physical).
				local nearestDefender
				local bestD = pulseEffect.DefenderContestRange
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr == player or not areOpponents(player, plr) then continue end
					local _, dRoot = getCharacterParts(plr)
					if not dRoot then continue end
					local d = (dRoot.Position - root.Position).Magnitude
					if d <= bestD then bestD = d; nearestDefender = plr end
				end
				if nearestDefender then
					-- mesma fórmula da disputa de carrinho (Physical bruto),
					-- calculada aqui direto pra não depender de uma função
					-- declarada mais abaixo no arquivo.
					local diff = getPhysical(player) - getPhysical(nearestDefender)
					local shooterChance = math.clamp(0.5 + 0.35 * math.tanh(diff / Config.TACKLE_PHYSICAL_STABILIZE_K), 0.15, 0.85)
					if math.random() > shooterChance then
						force = force / (pulseEffect.ForceMult or 1) -- disputa ganha pelo defensor: perde o bônus
					end
				end
			end
		end
		force = math.min(force, kickMaxForce * 1.6) -- teto de segurança

		if _G.GetPulseActiveKickForceMult then
			force *= _G.GetPulseActiveKickForceMult(player)
		end

		-- A defesa do goleiro NÃO é mais uma checagem de chance aqui —
		-- agora é 100% ativa (o goleiro precisa mergulhar/dashar de
		-- verdade, ver AttemptGKDive/AttemptGKForward mais abaixo). Só
		-- guardamos ignoreGKChance pra registrar que esse chute "ignora
		-- goleiro" (usado pelo Instinto Divino do Artilheiro — reduz um
		-- pouco o raio de captura do goleiro nesse chute específico, ver
		-- lastIgnoreGKShot).
		if trigger == "KickAtGoal" and math.random() < ignoreGKChance then
			lastIgnoreGKShot = tick()
		end

		-- Pulso do Muro Final: adversário com o bloqueio ativo perto o
		-- bastante do chutador anula boa parte da força.
		if trigger == "KickAtGoal" and _G.GetPulseBlock then
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr == player or not areOpponents(player, plr) then continue end
				local radius = _G.GetPulseBlock(plr)
				if not radius then continue end
				if _G.MuroDaBarreira and _G.MuroDaBarreira(plr) then continue end -- ⚠️ v120b: o muro para a bola NO MURO, não no chute
				local _, blockerRoot = getCharacterParts(plr)
				if blockerRoot and (blockerRoot.Position - root.Position).Magnitude <= radius then
					force *= 0.15
					break
				end
			end
		end
	end

	if hasControl then
		releaseOwner()
	end
	ball.CanCollide = true
	recentKicker, recentKickTime = player, tick() -- imuniza o chutador da própria mecânica de corpo por um instante (ver BODY_BLOCK acima)
	kickerClearedBody = false -- ⚠️ v12: some quando a bola sair de perto pela 1ª vez (ver BODY_BLOCK)
	hasBodyBlockedThisFlight = false -- ⚠️ v14: novo chute de verdade — libera o corpo pra absorver de novo (uma vez)
	startKickClearance(player) -- ⚠️ v20: sai atravessando qualquer coisa colada no corpo dele (ver startKickClearance)
	lastShotForce = force
	lastShotWasInstinct = false
	selfPickupLockUntil[player] = tick() + SELF_PICKUP_LOCK_SECONDS -- ⚠️ v5.6: trava de auto-repossessão (ver declaração acima)

	local direction = (targetPoint - ball.Position)
	if direction.Magnitude < 0.01 then
		direction = root.CFrame.LookVector
	end
	direction = direction.Unit

	-- ===== DESVIO DE MIRA: aplica por último, já com o multiplicador de
	-- Pulso/Instinto (aimDeviationMult) — sem desvio em bola parada
	-- (Instinto de Bola Parada já cobre a precisão de cobrança).
	if kickTrigger ~= "SetPiece" then
		local degrees = getAimDeviationDegrees(player, kickTrigger == "KickAtTeammate") * aimDeviationMult -- ⚠️ NOVO: passe = Técnica
		direction = applyAimDeviation(direction, degrees)
	end

	nudgeBallForwardForKick(direction) -- ⚠️ v21: já nasce fora do raio do corpo, na direção do chute

	-- ⚠️ v97 — CHUTE QUE PASSA PELO PONTO MIRADO. PEDIDO: "aonde você estiver
	-- mirando, você clicou, é pra ser perfeito". Antes: direção reta até a
	-- mira + um empurrão fixo de 18% pra cima (KICK_UPWARD_BOOST) — a bola
	-- subia ACIMA do ponto mirado, mais quanto mais longe (o "sobe demais").
	-- Agora, com a força carregada, calcula o ângulo de saída exato pra
	-- parábola (gravidade da bola) passar PELO ponto mirado. Se a força não
	-- alcança, sai no ângulo de alcance máximo, na direção certa.
	local velocity = _G.VelocidadeBalistica and _G.VelocidadeBalistica(ball.Position, ball.Position + direction * (targetPoint - ball.Position).Magnitude, force)
	if not velocity then
		velocity = direction * force
		velocity += Vector3.new(0, force * Config.KICK_UPWARD_BOOST, 0)
	end
	ball.AssemblyLinearVelocity = velocity

	-- garante que o toque conte pra assistência/gol mesmo em voleio sem posse formal
	pushToucher(player)

	playKickFeedback(force)
	-- ⚠️ v63 — PEDIDO: "todos [os dribles] começam na animação de idle e
	-- terminam nela. Só corte o final se for o CHUTE, porque aí você vai
	-- nela direto."
	--
	-- O drible está em Action2, ACIMA do chute (Action) — foi de propósito,
	-- pra uma finta poder passar na frente do chute carregado e devolver a
	-- pose depois. Só que isso também faria o rabicho do drible cobrir o
	-- chute de verdade. Cortar o drible aqui é o que deixa o chute entrar
	-- direto, sem esperar a finta terminar de voltar pro idle.
	for _, direcao in ipairs({ "Left", "Back", "Right" }) do
		stopAnimation(player, dribbleAnimationFor(direcao), 0)
	end
	if arremessoDoGoleiro then
		avisarAcao(player.Character, "Arremesso", 0.6) -- ⚠️ v105: arremesso com as mãos
	else
		playAnimation(player, Config.ANIMATIONS.Kick, nil, nil, true) -- ⚠️ v60
	end
	-- ⚠️ v84 — PEDIDO: chute "sem nenhum tipo de erro, exatamente no ponto
	-- mirado". O `spin` que o cliente manda vem da distância HORIZONTAL entre
	-- o mouse e a bola na tela (computeSpin no FootballClient) — ou seja,
	-- qualquer mira que não esteja exatamente em cima da bola já curvava o
	-- chute (até ~15 studs/s de lado durante 0.7s). Era a maior fonte do "vai
	-- pra um lado ou pro outro". O chute normal agora sai RETO na direção
	-- mirada; curva ficou só nas Hissatsus que têm CurveMult próprio.
	applyCurve(nil, direction)

	-- ⚠️ v110 — CHUTE CURVO (Armas: Tiro Destruidor / Passe do Prodígio). PEDIDO:
	-- "me pediram pra colocar chute curvo no jogo... uma arma do Rin (ou do
	-- Sae), que também é curvo". A bola sai ABERTA (virada pra um lado) e uma
	-- força lateral constante traz ela de volta: ela CRUZA a linha do chute
	-- exatamente na distância do ponto mirado (banana que contorna quem está no
	-- meio e chega onde você mirou). Lado: A/D segurando escolhe; sem segurar,
	-- no chute a gol curva de FORA pra DENTRO (e no passe, pela direita).
	-- ⚠️ v120b: a curva vem de QUALQUER arma equipada com Curva (não só da que
	-- "ganhou" o CheckInstinct — ver _G.CurvaDaArmaEquipada)
	local curvaDoChute = armaDoChute and armaDoChute.Curva
		or (kickTrigger and _G.CurvaDaArmaEquipada and _G.CurvaDaArmaEquipada(player, kickTrigger))
	if curvaDoChute and _G.ArmaAplicarCurva then
		_G.ArmaAplicarCurva(player, targetPoint, curvaDoChute, kickTrigger == "KickAtGoal", movimentoCliente)
	end
	if armaDoChute and armaDoChute.CompanheiroForcaMult and kickTrigger == "KickAtTeammate" and _G.SetPulseTeammateBuff then
		local maisPerto, menor = nil, 18
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == player or areOpponents(player, plr) then continue end
			local _, mRoot = getCharacterParts(plr)
			if mRoot and (mRoot.Position - targetPoint).Magnitude < menor then
				menor = (mRoot.Position - targetPoint).Magnitude
				maisPerto = plr
			end
		end
		if maisPerto then _G.SetPulseTeammateBuff(maisPerto, armaDoChute.CompanheiroForcaMult, 6) end
	end
end
-- ⚠️ v122: parâmetros explícitos — o cliente não pode mandar `tentativaGuardada`; o 4º
-- valor dele é o MOVIMENTO (A/D) na hora de soltar, que escolhe o lado da curva
Remotes.KickBall.OnServerEvent:Connect(function(player, forca, alvo, noAr, movimento)
	if typeof(movimento) ~= "Vector3" or movimento.Magnitude > 1.5 then movimento = nil end
	return _G.ProcessarChuteServidor(player, forca, alvo, noAr, false, movimento)
end)

-- ⚠️ v121 — CHUTE ANTECIPADO (ver Config.CHUTE_ANTECIPADO_SEG): o pedido fica guardado
-- e é tentado de novo todo quadro até a bola chegar (posse, primeiro toque ou voleio).
do
	local guardados = {} -- [player] = { Forca, Alvo, NoAr, Ate }
	_G.GuardarChuteAntecipado = function(player, forca, alvo, noAr, movimento)
		guardados[player] = { Forca = forca, Alvo = alvo, NoAr = noAr, Mov = movimento, Ate = tick() + (Config.CHUTE_ANTECIPADO_SEG or 0.35) }
	end
	RunService.Heartbeat:Connect(function()
		for player, g in pairs(guardados) do
			if tick() > g.Ate or not player.Parent then
				guardados[player] = nil
			else
				local r = _G.ProcessarChuteServidor(player, g.Forca, g.Alvo, g.NoAr, true, g.Mov)
				if r ~= "fora" then guardados[player] = nil end
			end
		end
	end)
end

-- ===== CABEÇADA =====
Remotes.AttemptHeader.OnServerEvent:Connect(function(player, targetPoint)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	if isStunned(player) then return end
	local lastAttempt = headerCooldowns[player]
	if lastAttempt and tick() - lastAttempt < Config.HEADER_COOLDOWN then return end

	local _, root = getCharacterParts(player)
	if not root then return end

	-- ⚠️ v5.3: horizontal e altura checados SEPARADOS (era distância 3D).
	-- É o mesmo erro que o mergulho do goleiro já teve: com distância 3D,
	-- uma bola alta gastava quase todo o alcance só na diferença de
	-- altura. Com HEADER_RANGE = 6 e a bola 3 studs acima da cabeça,
	-- sobravam ~5 studs de margem horizontal — por isso a cabeçada parecia
	-- quase impossível. Agora é um cilindro: HEADER_RANGE é só a margem
	-- HORIZONTAL, e a altura tem faixa própria (mín/máx).
	-- ⚠️ v105 — cabeçada só no ar (o cliente só manda pulando; aqui confere
	-- que o corpo não está parado no chão)
	-- ⚠️ v108 — PEDIDO: "tô tentando dar cabeçada e não consigo. Clicou na
	-- altura certa, ele dá a cabeçada automaticamente em vez do chute". A trava
	-- de "só pulando" (v105) matava a cabeçada da bola que chega na altura da
	-- cabeça com você no chão — saiu. No lugar: bola forte demais não dá
	-- (HEADER_VEL_MAX), nem bola que outro jogador está dominando.
	if owner and owner ~= player then return end
	if ball.AssemblyLinearVelocity.Magnitude > (Config.HEADER_VEL_MAX or 95) then return end

	local alturaBola = ball.Position.Y - root.Position.Y
	local distanciaHorizontal = (Vector3.new(ball.Position.X, 0, ball.Position.Z)
		- Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	if distanciaHorizontal > Config.HEADER_RANGE then return end
	if alturaBola < Config.HEADER_MIN_BALL_HEIGHT or alturaBola > Config.HEADER_MAX_BALL_HEIGHT then return end

	if not Config.SpendStamina(player, Config.HEADER_STAMINA_COST) then return end

	headerCooldowns[player] = tick()
	pushToucher(player)
	if _G.NotifyInstinctAction then _G.NotifyInstinctAction(player, "Header") end -- ⚠️ v6.5: carga de "prática" do Instinct Mode

	-- FIX (cabeçada "não funcionando"): se por algum motivo a bola ainda
	-- estava marcada como posse de alguém (ex: cabeceio no meio de uma
	-- disputa/transição), o loop de drible (linha ~655) reassume o
	-- controle da bola no PRÓXIMO Heartbeat e sobrescreve a velocidade que
	-- a cabeçada acabou de aplicar, fazendo a cabeçada "sumir"/não sair do
	-- lugar. Solta a posse antes de aplicar força, igual o chute já faz.
	if owner then
		releaseOwner()
	end
	recentKicker, recentKickTime = player, tick() -- mesma imunidade do chute contra a própria mecânica de corpo — cabeçada acontece bem perto do próprio corpo, então sofria do mesmo bug
	kickerClearedBody = false -- ⚠️ v12: ver BODY_BLOCK
	hasBodyBlockedThisFlight = false -- ⚠️ v14: novo chute de verdade — libera o corpo pra absorver de novo (uma vez)
	startKickClearance(player) -- ⚠️ v20: sai atravessando qualquer coisa colada no corpo dele (ver startKickClearance)

	local direction = root.CFrame.LookVector
	if typeof(targetPoint) == "Vector3" then
		local toTarget = targetPoint - ball.Position
		if toTarget.Magnitude > 0.01 then direction = toTarget.Unit end
	end

	local headerForce = Config.HEADER_FORCE
	local instEffect = _G.CheckInstinct and _G.CheckInstinct(player, "Header", {})
	if instEffect then headerForce *= (instEffect.HeaderForceMult or 1) end
	local pulseEffect = _G.TryConsumePulse and _G.TryConsumePulse(player, "Header")
	if pulseEffect then headerForce *= (pulseEffect.HeaderForceMult or 1) end

	-- Cabeçada também sofre desvio de mira (metade do de um chute normal
	-- — é uma ação mais reflexa, mas ainda imprecisa).
	direction = applyAimDeviation(direction, getAimDeviationDegrees(player) * 0.5)

	nudgeBallForwardForKick(direction) -- ⚠️ v21: já nasce fora do raio do corpo, na direção da cabeçada
	-- ⚠️ v21 FIX: removido o "ball.CanCollide = true" que existia aqui —
	-- ele cancelava na hora a janela de saída limpa (startKickClearance)
	-- aberta logo acima, então a cabeçada nunca se beneficiava dela.
	ball.AssemblyLinearVelocity = direction * headerForce + Vector3.new(0, Config.HEADER_ELEVACAO or 8, 0) -- ⚠️ v105: sobe mais
	playKickFeedback(headerForce)
	playAnimation(player, Config.ANIMATIONS.Header, nil, nil, true) -- ⚠️ v65: cabeçada (normal e de Hissatsu passam as duas por aqui)
end)

-- ===== CARRINHO (TACKLE) =====
-- Uma mecânica só, mesma tecla (Z): serve tanto pra roubar a posse de
-- quem tem a bola (SÓ SE FOR ADVERSÁRIO — ver areOpponents) quanto pra
-- "dashar" até uma bola solta (não depende de time). Não tem cooldown —
-- pode ser tentado a qualquer momento; o único limitador é ter
-- TACKLE_STAMINA_COST de stamina disponível, igual ao sprint. Se o
-- carrinho não conecta em nada — nem rouba posse, nem chega na bola
-- solta — o jogador fica estirado no chão (stun curto) como punição por
-- errar o tempo.
--
-- DENTRO do alcance (TACKLE_RANGE), o roubo de posse de quem já tem a
-- bola é SEMPRE bem-sucedido — sem chance/dado. Só falha se: o dono
-- mudou antes de resolver, a distância no momento de resolver está fora
-- do alcance, ou o alvo estava no meio de uma finta (aí o atacante leva
-- stun por má leitura de tempo).
--
-- DIREÇÃO DO LUNGE: pra onde o jogador está OLHANDO
-- (root.CFrame.LookVector), não em direção à bola/ao dono. Isso torna o
-- carrinho um movimento que precisa ser mirado por quem o usa (vira o
-- personagem antes de apertar), em vez de um "auto-lock" que sempre
-- acerta a direção certa sozinho — mais fiel a um carrinho de verdade, e
-- também abre espaço pra errar o ângulo como punição por má leitura de
-- jogo.
--
-- O lunge (arremesso pra frente) é um deslocamento DIRETO por CFrame —
-- igual à finta — em vez de AssemblyLinearVelocity: o Humanoid
-- sobrescreve a velocidade horizontal sozinho a cada passo de física
-- (mesmo problema raiz já documentado pra WalkSpeed/finta no
-- GameSystemLog), o que fazia o "pra frente" não acontecer de verdade.
-- Agora é garantido, com a mesma curva de easing (ease-out cúbica) da
-- finta.
--
-- Quando DOIS jogadores usam o carrinho quase ao mesmo tempo (dentro de
-- Config.TACKLE_CONTEST_WINDOW) indo pra mesma bola solta, vira uma
-- "disputa de carrinho" (resolvida pelo atributo Physical) em vez de dois
-- eventos separados e independentes.
local function resolvePhysicalClashChance(playerA, playerB)
	local diff = getPhysical(playerA) - getPhysical(playerB)
	local chance = 0.5 + 0.35 * math.tanh(diff / Config.TACKLE_PHYSICAL_STABILIZE_K)
	return math.clamp(chance, 0.15, 0.85)
end

local noStunOnFail = {} -- [player] = true por um instante (Pulso do Carrinho Blindado)

-- PEDIDO: carrinho pra pegar bola SOLTA (sem dono) — decompõe a captura
-- em horizontal/vertical (mesma ideia do mergulho do goleiro e do pickup
-- passivo acima) em vez de distância 3D cheia, senão bola alta/rápida
-- "come" o alcance todo na diferença de altura. Bola rápida OU alta de
-- verdade (velocidade acima do que o pickup passivo aceita, ou bem no
-- ar) só é capturável de carrinho por quem tem DribbleSkill suficiente —
-- carrinho vira "roubo de qualquer bola solta de graça" sem esse filtro.
local function canCaptureLooseBallByTackle(player, root)
	if passLockBlocks(player) then return false end -- ⚠️ v3: passe de Pulso travado pra outro jogador (ver passLock acima)

	local horizontal = (Vector3.new(ball.Position.X, 0, ball.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	if horizontal > Config.TACKLE_RANGE then return false end

	local vertical = math.abs(ball.Position.Y - root.Position.Y)
	if vertical > Config.TACKLE_AERIAL_CAPTURE_HEIGHT then return false end

	local ballSpeed = ball.AssemblyLinearVelocity.Magnitude
	-- ⚠️ v120b — PEDIDO: "carrinho não intercepta chute acima de 40% da barra (na
	-- força base): se o chute saiu a 100% e perdeu velocidade até chegar no que
	-- seria 40%, aí dá pra pegar com carrinho; senão só o dive do goleiro".
	local fracao = Config.TACKLE_INTERCEPT_BAR_FRACTION or 0.4
	local limiteCarrinho = Config.KICK_MIN_FORCE + (Config.KICK_MAX_FORCE - Config.KICK_MIN_FORCE) * fracao
	if ballSpeed > limiteCarrinho then return false end
	local isFastOrAerial = ballSpeed > LOOSE_BALL_PICKUP_MAX_SPEED or vertical > Config.AERIAL_PICKUP_HEIGHT
	if isFastOrAerial and getTechnique(player) < Config.TACKLE_FAST_BALL_MIN_TECHNIQUE then -- ⚠️ NOVO: bola difícil = Técnica (era DribbleSkill)
		return false
	end

	return true
end

local function applyTackleMiss(player)
	playAnimation(player, Config.ANIMATIONS.TackleMiss, nil, Config.TACKLE_MISS_STUN)
	if not noStunOnFail[player] then
		stunPlayer(player, Config.TACKLE_MISS_STUN)
	end
end

-- Resolve uma tentativa de ROUBAR POSSE de targetOwner. Chamado tanto
-- DURANTE o lunge (assim que a distância entra no alcance) quanto no
-- fim dele, como fallback, caso nunca tenha chegado perto o bastante.
-- Dentro do alcance, é SEMPRE sucesso (ver nota acima) — não tem mais
-- rolagem de chance.
local function resolveStealAttempt(player, targetOwner)
	if owner ~= targetOwner then
		applyTackleMiss(player)
		return
	end

	-- ⚠️ v67 — PEDIDO: "o GK não pode perder a bola na área, então é
	-- impossível tirarem a bola dele na área. Nem com Hissatsu, nem com
	-- carrinho, nem nada — proíba isso."
	--
	-- Fica AQUI, na resolução do desarme, porque é o funil por onde TODAS as
	-- formas de roubo passam: carrinho normal, dash de Pulso, Investida, e o
	-- desarme automático das Hissatsus de Tackle. Bloquear em cada uma delas
	-- separadamente deixaria buraco na primeira que eu esquecesse.
	--
	-- Quem tenta leva o miss normal (cai no chão): a tentativa em cima do
	-- goleiro na área é sempre um erro, e tem que custar alguma coisa.
	if GKAreaUtil.IsEffectiveGK(targetOwner) then
		applyTackleMiss(player)
		return
	end

	local _, currentPlayerRoot = getCharacterParts(player)
	local _, currentOwnerRoot = getCharacterParts(targetOwner)
	if not currentPlayerRoot or not currentOwnerRoot then return end

	local distance = (currentPlayerRoot.Position - currentOwnerRoot.Position).Magnitude
	if distance > Config.TACKLE_RANGE then
		applyTackleMiss(player)
		return
	end

	-- ⚠️ v119: guarda do Passo Furtivo — o desarme vira contra-ataque
	if _G.ContraGuardaFurtiva and _G.ContraGuardaFurtiva(targetOwner, player) then return end

	local activeMove = dribbleMoves[targetOwner]
	if activeMove and tick() < activeMove.expiresAt then
		stunPlayer(player, Config.TACKLE_STUN_ON_FAILED_TIMING)
		return
	end

	-- ⚠️ v3: IFRAME DE PULSO — o alvo está no wind-up longo de um Pulso
	-- (ou com SelfIframe ativo): o desarme falha e QUEM TENTOU leva stun,
	-- exatamente o mesmo tratamento que já existe pra uma finta ativa
	-- logo acima (é uma leitura de tempo errada do atacante).
	if _G.HasPulseIframe and _G.HasPulseIframe(targetOwner) then
		stunPlayer(player, Config.TACKLE_STUN_ON_FAILED_TIMING)
		return
	end

	local stolenFrom = targetOwner
	releaseOwner()
	ball.CanCollide = true
	tackleSound:Play()
	setOwner(player)
	stunPlayer(stolenFrom, Config.TACKLE_VICTIM_STUN)
	avisarAcao(stolenFrom.Character, "SofreuCarrinho", Config.TACKLE_VICTIM_STUN) -- ⚠️ v106: cai no chão e levanta

	if _G.RegisterTackle then
		_G.RegisterTackle(player, stolenFrom)
	end
end

-- ⚠️ v15 — PEDIDO: "o tackle não está sendo feito. Preciso que você faça
-- funcionar: pra direita, pra esquerda, pra cima, pra diagonal. Isso é
-- muito importante no jogo de futebol."
--
-- O que havia: a direção do carrinho era SEMPRE root.CFrame.LookVector —
-- pra onde a câmera/corpo estava virado — e a distância era encurtada pra
-- parar em cima do adversário. Resultado: se você não estivesse com o
-- corpo apontado exatamente pro carregador (o que quase nunca acontece
-- correndo do lado dele), o carrinho saía reto pro lado errado e você
-- "errava" sem entender por quê. Não existia NENHUMA forma de escolher o
-- lado.
--
-- ⚠️ v84 — PEDIDO: "atualmente o personagem sempre dá carrinho em direção
-- à bola, desative essa opção — dive e carrinho são pra direção apontada".
-- A AUTO-MIRA (parado = carrinho vira sozinho pro carregador/bola e encurta
-- pra parar em cima dele) FOI REMOVIDA. Sobram só as duas direções que o
-- próprio jogador escolhe:
--   1. DIRECIONAL — segurando W/A/S/D (ou o analógico): vai EXATAMENTE pra
--      lá (pedido do v15: esquerda, direita, frente, diagonal).
--   2. PARADO — vai pra onde o personagem está APONTADO (LookVector; com
--      shift lock é pra onde a câmera olha).
-- Distância sempre cheia — nada de encurtar por causa de um alvo.
local function startTackleDash(player, root, targetPlayer, requestedDirection)
	local direction = requestedDirection
	if not direction then
		local look = root.CFrame.LookVector
		look = Vector3.new(look.X, 0, look.Z)
		direction = look.Magnitude > 0.01 and look.Unit or root.CFrame.LookVector
	end

	local distance = Config.TACKLE_DASH_FORCE * Config.TACKLE_DASH_DURATION

	local dash = {
		startPosition = root.Position,
		endPosition = root.Position + direction * distance,
		triggeredAt = tick(),
		expiresAt = tick() + Config.TACKLE_DASH_DURATION,
		targetPlayer = targetPlayer, -- quem está sendo perseguido (nil = dash pra bola solta)
		resolved = false,            -- trava pra resolver só uma vez
	}
	tackleDashes[player] = dash
	if _G.TutorialNotificar then _G.TutorialNotificar(player, "Carrinho") end -- ⚠️ v104

	Remotes.SuppressShiftLockRotation:FireClient(player, Config.TACKLE_DASH_DURATION)
	return dash -- referência direta, evita a corrida com o fallback do task.delay
end

-- ⚠️ NOVO: Arrancada Selvagem/Investida Titânica — chamado quando a hitbox
-- do dash (ver _G.StartPulseDashTackle mais abaixo) toca um adversário.
-- "hitEffect" já vem pronto (interpolado Bom->Perfect pela fração de
-- acerto das alternâncias A/D no momento do toque — ver dash.currentFraction/
-- dash.pulseDef). Se o alvo tocado tem a posse da bola, rouba de verdade
-- (mesmas regras/counterplay do carrinho normal — iframe de Pulso, finta
-- ativa); se não tem, só aplica o golpe (empurrão/ragdoll/atordoamento),
-- sem stunar quem chutou por "errar" — a hitbox JÁ conectou, não é um
-- whiff.
local function applyPulseDashHit(player, target, dash)
	-- ⚠️ v110: carrinho de Hissatsu (ver _G.PulseExecuteTackle) — aqui só o
	-- ROUBO no contato; o efeito da técnica (gelo, pisão, clarão...) sai na
	-- chegada, em dash.aoChegar.
	if dash.efeitoFixo then
		if owner == target and not GKAreaUtil.IsEffectiveGK(target) then
			if _G.ContraGuardaFurtiva and _G.ContraGuardaFurtiva(target, player) then return end -- ⚠️ v119
			local activeMove = dribbleMoves[target]
			local escapou = (activeMove and tick() < activeMove.expiresAt) or (_G.HasPulseIframe and _G.HasPulseIframe(target))
			if not escapou then
				releaseOwner()
				ball.CanCollide = true
				tackleSound:Play()
				setOwner(player)
				stunPlayer(target, Config.TACKLE_VICTIM_STUN)
				avisarAcao(target.Character, "SofreuCarrinho", Config.TACKLE_VICTIM_STUN)
				if _G.RegisterTackle then _G.RegisterTackle(player, target) end
			end
		end
		return
	end
	local pulseDef = dash.pulseDef
	local bom = (pulseDef and pulseDef.Bom) or {}
	local perfect = (pulseDef and pulseDef.Perfect) or {}
	local fraction = dash.currentFraction or 0
	local hitEffect = {}
	for k, v in pairs(bom) do
		if typeof(v) == "number" and typeof(perfect[k]) == "number" then
			hitEffect[k] = v + (perfect[k] - v) * fraction
		else
			hitEffect[k] = v
		end
	end
	for k, v in pairs(perfect) do
		if hitEffect[k] == nil and typeof(v) == "number" then
			hitEffect[k] = v * fraction -- campo só existe no Perfect: entra gradualmente com a fração de acerto
		end
	end

	-- ⚠️ NÃO chama resolveStealAttempt aqui de propósito: ela reconfere a
	-- distância contra Config.TACKLE_RANGE (fixo) e, se falhar, aplica
	-- applyTackleMiss (stun em QUEM CHUTOU) — regras certas pro carrinho
	-- normal (alcance fixo, "errou o carrinho"), mas erradas aqui: a
	-- hitbox da Arrancada/Investida É VARIÁVEL (Bom/Perfect) e o contato
	-- JÁ aconteceu (não é um whiff) quando essa função é chamada. Reaplica
	-- só as checagens de CONTRAPLAY de verdade (finta ativa / iframe de
	-- Pulso no alvo), sem a re-checagem de distância nem o stun de "errou".
	if owner == target and _G.ContraGuardaFurtiva and _G.ContraGuardaFurtiva(target, player) then
		return -- ⚠️ v119: guarda do Passo Furtivo
	end
	if owner == target then
		local activeMove = dribbleMoves[target]
		if activeMove and tick() < activeMove.expiresAt then
			stunPlayer(player, Config.TACKLE_STUN_ON_FAILED_TIMING)
		elseif _G.HasPulseIframe and _G.HasPulseIframe(target) then
			stunPlayer(player, Config.TACKLE_STUN_ON_FAILED_TIMING)
		else
			local stolenFrom = target
			releaseOwner()
			ball.CanCollide = true
			tackleSound:Play()
			setOwner(player)
			stunPlayer(stolenFrom, Config.TACKLE_VICTIM_STUN)
			if _G.RegisterTackle then _G.RegisterTackle(player, stolenFrom) end
		end
	end

	if hitEffect.KnockbackRadius and hitEffect.KnockbackForce and _G.PulseApplyAreaKnockback then
		_G.PulseApplyAreaKnockback(player, hitEffect.KnockbackRadius, hitEffect.KnockbackForce)
	end
	local _, root = getCharacterParts(player)
	if root and hitEffect.RagdollRadius and hitEffect.RagdollDuration then
		for _, other in ipairs(Players:GetPlayers()) do
			if other == player or not areOpponents(player, other) then continue end
			local _, otherRoot = getCharacterParts(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= hitEffect.RagdollRadius then
				ragdollPlayer(other, hitEffect.RagdollDuration)
			end
		end
	end
	if root and hitEffect.StunRadius and hitEffect.StunDuration then
		for _, other in ipairs(Players:GetPlayers()) do
			if other == player or not areOpponents(player, other) then continue end
			local _, otherRoot = getCharacterParts(other)
			if otherRoot and (otherRoot.Position - root.Position).Magnitude <= hitEffect.StunRadius then
				stunPlayer(other, hitEffect.StunDuration)
			end
		end
	end

	if Config.PULSE_FORCE_DEBUG_PRINTS then
		print(string.format(
			"🏃 [Pulso] %s acertou a Arrancada/Investida em %s — %.0f%% dos acertos de A/D (raio %.1f) | roubou a bola: %s",
			player.Name, target.Name, fraction * 100, dash.hitboxRadius or 0, tostring(owner == player)
		))
	end
end

-- ⚠️ NOVO: exposto pra PulseController.legacy.luau disparar o dash quando
-- o jogador usa a Arrancada Selvagem/Investida Titânica (Action="Tackle",
-- QTE="MashAD"). Reaproveita a MESMA infraestrutura do carrinho normal
-- (tackleDashes + o Heartbeat logo abaixo) — só que sem alvo fixo: a
-- hitbox (que cresce ao vivo com os acertos de A/D) acerta QUALQUER
-- adversário no caminho, com ou sem bola, em qualquer lugar do campo.
_G.StartPulseDashTackle = function(player, slot, def)
	local _, root = getCharacterParts(player)
	if not root then return end

	local qte = def.QTE
	local requiredAlternations = math.max(qte.RequiredAlternations or 6, 1)
	local qteDuration = math.max(qte.Duration or 2, 0.2)
	local bom = def.Bom or {}
	local perfect = def.Perfect or {}
	local bomHitbox = bom.HitboxRadius or Config.PULSE_DASH_TACKLE_MIN_HITBOX
	local perfectHitbox = perfect.HitboxRadius or bomHitbox
	local bomPersist = bom.ExtraPersistSeconds or 0
	local perfectPersist = perfect.ExtraPersistSeconds or bomPersist

	local direction = root.CFrame.LookVector
	direction = Vector3.new(direction.X, 0, direction.Z)
	direction = direction.Magnitude > 0.01 and direction.Unit or root.CFrame.LookVector

	local distance = Config.PULSE_DASH_TACKLE_SPEED * qteDuration * (def.DistanciaMult or 1) -- ⚠️ v108: Investida 2x mais longe

	local dash = {
		startPosition = root.Position,
		endPosition = root.Position + direction * distance,
		triggeredAt = tick(),
		expiresAt = tick() + qteDuration, -- estendido pelo ExtraPersistSeconds quando o QTE resolver, ver abaixo
		isPulseDash = true,
		-- ⚠️ IMPORTANTE: duração do MOVIMENTO físico é FIXA em qteDuration,
		-- separada de dash.expiresAt (que ExtraPersistSeconds estica
		-- abaixo). Sem essa separação, esticar expiresAt reduziria a
		-- fração "alpha" do lerp de posição NO MEIO do dash (mesmo tick(),
		-- duração total maior) e o personagem "saltaria pra trás" na hora —
		-- ver o Heartbeat logo abaixo, que usa moveDuration em vez de
		-- recalcular a partir de expiresAt.
		moveDuration = qteDuration,
		hitboxRadius = bomHitbox, -- cresce ao vivo conforme os acertos de A/D (ver updateFraction abaixo)
		currentFraction = 0,
		pulseDef = def,
		resolved = false,
		-- ⚠️ v108: progresso próprio (A/D acelera o deslocamento, não alonga)
		progress = 0,
		lastTick = tick(),
		velocidadeMash = def.VelocidadeMash or 0,
		multiAlvo = def.MultiAlvo == true,
		atingidos = {},
	}
	tackleDashes[player] = dash
	-- ⚠️ v108: pose de investida (ombro à frente, correndo) + vento de fogo — sem
	-- cutscene ("tackle não precisa de cutscene, já tem a animação dele")
	avisarAcao(player.Character, "Investida", qteDuration)

	local maxDuration = qteDuration + math.max(bomPersist, perfectPersist)
	Remotes.SuppressShiftLockRotation:FireClient(player, maxDuration)

	local function updateFraction(hits)
		local fraction = math.clamp((hits or 0) / requiredAlternations, 0, 1)
		dash.currentFraction = fraction
		dash.hitboxRadius = bomHitbox + (perfectHitbox - bomHitbox) * fraction
	end

	if _G.StartHissatsuQTE then
		_G.StartHissatsuQTE(player, slot, def, function(_, hits)
			local fraction = math.clamp((hits or 0) / requiredAlternations, 0, 1)
			local extraPersist = bomPersist + (perfectPersist - bomPersist) * fraction
			-- só ESTICA o fim do dash (nunca encurta) — a distância física
			-- do lunge já foi calculada pro qteDuration inteiro lá em cima.
			dash.expiresAt = math.max(dash.expiresAt, dash.triggeredAt + qteDuration + extraPersist)
		end)
	end
	if _G.RegisterQTEHitCallback then
		_G.RegisterQTEHitCallback(player, slot, updateFraction)
	end
end

-- ⚠️ v120b — PEDIDO: "às vezes, depois de dar carrinho, ele simplesmente para de
-- funcionar o carrinho ou o dash". Carrinho e dash recusam enquanto existir um
-- tackleDashes[player]; se o loop de baixo der erro numa entrada (dash de Pulso/
-- Hissatsu malformado), ele para de rodar naquele quadro e a entrada NUNCA é
-- limpa — e trava todo mundo. Faxina separada e simples: entrada vencida há mais
-- de 1s (ou sem prazo) sai, aconteça o que acontecer no loop principal.
RunService.Heartbeat:Connect(function()
	local agora = tick()
	for player, dash in pairs(tackleDashes) do
		if typeof(dash) ~= "table" or typeof(dash.expiresAt) ~= "number" or agora >= dash.expiresAt + 1
			or not player.Parent then
			tackleDashes[player] = nil
		end
	end
end)

RunService.Heartbeat:Connect(function()
	for player, dash in pairs(tackleDashes) do
		local _, root = getCharacterParts(player)
		if not root then
			tackleDashes[player] = nil
			continue
		end
		if tick() >= dash.expiresAt then
			-- ⚠️ NOVO: PEDIDO — "pra eu saber o que preciso fazer pra
			-- balancear a defesa" — se um dash de Pulso (Arrancada/Investida)
			-- termina sem NUNCA ter acertado ninguém, mostra o raio final da
			-- hitbox e a % de acertos de A/D, pra dar pra ver se o problema é
			-- hitbox pequena, QTE incompleto, ou (mais provável, ver aviso
			-- fixo abaixo) estar mirando numa bola JÁ CHUTADA/sem dono — essa
			-- skill só acerta JOGADORES adversários (rouba a bola de quem tem
			-- ela), nunca a bola sozinha voando no ar.
			if dash.isPulseDash and not dash.resolved and Config.PULSE_FORCE_DEBUG_PRINTS then
				print(string.format(
					"🏃❌ [Pulso] %s: Arrancada/Investida terminou SEM acertar ninguém — hitbox final %.1f studs, %.0f%% dos acertos de A/D. Lembrete: essa skill só rouba a bola de um ADVERSÁRIO COM A BOLA nos pés — ela não intercepta/bloqueia uma bola já chutada e voando sem dono (isso é papel da Muralha/chip do zagueiro).",
					player.Name, dash.hitboxRadius or 0, (dash.currentFraction or 0) * 100
				))
			end
			tackleDashes[player] = nil
			continue
		end

		-- ⚠️ NOVO: dash.moveDuration (só setado pelo dash de Pulso acima)
		-- separa "quanto tempo o personagem ainda está DESLIZANDO" de
		-- "quanto tempo o dash inteiro (hitbox incluída) continua vivo" —
		-- ver comentário em _G.StartPulseDashTackle. Pros outros tipos de
		-- dash (carrinho normal, avanço de GK) os dois sempre foram a
		-- mesma coisa, então o fallback preserva o comportamento de sempre.
		local totalDuration = dash.moveDuration or (dash.expiresAt - dash.triggeredAt)
		local alpha = totalDuration > 0
			and math.clamp((tick() - dash.triggeredAt) / totalDuration, 0, 1)
			or 1
		local easedAlpha = 1 - (1 - alpha) ^ 3
		if dash.progress then
			-- ⚠️ v108 — Investida: o avanço anda num ritmo que cresce com as
			-- alternâncias A/D (até 1 + velocidadeMash vezes mais rápido); a
			-- distância total não muda. Curva mais reta (é uma investida, não
			-- um lunge que freia).
			local agora = tick()
			local dt = math.clamp(agora - (dash.lastTick or agora), 0, 0.1)
			dash.lastTick = agora
			local ritmo = (1 + (dash.velocidadeMash or 0) * (dash.currentFraction or 0)) / math.max(totalDuration, 0.05)
			dash.progress = math.min(1, dash.progress + dt * ritmo)
			easedAlpha = 1 - (1 - dash.progress) ^ 1.6
			if dash.progress >= 1 and not dash.chegou then
				dash.chegou = true
				dash.expiresAt = math.min(dash.expiresAt, agora + 0.35)
			end
		end

		local newPosition = dash.startPosition:Lerp(dash.endPosition, easedAlpha)
		if dash.arco then -- ⚠️ v110: salto em arco (Anjo da Neve)
			local uArco = math.clamp((tick() - dash.triggeredAt) / math.max(dash.moveDuration or 1, 0.05), 0, 1)
			newPosition += Vector3.new(0, 4 * dash.arco * uArco * (1 - uArco), 0)
		end
		root.CFrame = root.CFrame.Rotation + newPosition
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		root.AssemblyAngularVelocity = Vector3.zero

		-- resolve quem fica com a bola assim que entra no alcance, mas
		-- SEM parar a animação do lunge — ela continua até o fim normal
		if dash.targetPlayer and not dash.resolved then
			local _, targetRoot = getCharacterParts(dash.targetPlayer)
			if targetRoot and (root.Position - targetRoot.Position).Magnitude <= Config.TACKLE_RANGE then
				dash.resolved = true
				resolveStealAttempt(player, dash.targetPlayer)
			end
		end

		-- ⚠️ v5.6: dash de AVANÇO do goleiro (AttemptGKForward) — resolução
		-- PRÓPRIA, contínua, e só em caso de SUCESSO (nunca stuna o
		-- goleiro numa falha, ao contrário do carrinho normal acima). Ver
		-- comentário completo em Remotes.AttemptGKForward.
		if dash.isGKForward and not dash.resolved then
			-- ⚠️ v105 — "se você der o dive pra frente em alguém, você pega a bola
			-- na hora, mesmo que ele drible": vale pra QUALQUER adversário que
			-- esteja com a bola quando o goleiro chega (não só quem tinha no aperto)
			if owner and owner ~= player and areOpponents(player, owner) then
				dash.gkTargetOwner = owner
			end
			if dash.gkTargetOwner then
				if owner == dash.gkTargetOwner and not (_G.HasPulseIframe and _G.HasPulseIframe(dash.gkTargetOwner)) then
					local _, targetRoot = getCharacterParts(dash.gkTargetOwner)
					if targetRoot and (root.Position - targetRoot.Position).Magnitude <= Config.GK_FORWARD_STEAL_RANGE then
						dash.resolved = true
						local stolenFrom = dash.gkTargetOwner
						releaseOwner()
						ball.CanCollide = true
						tackleSound:Play()
						setOwner(player)
						if _G.RegisterTackle then _G.RegisterTackle(player, stolenFrom) end
					end
				end
			elseif not owner then
				if (root.Position - ball.Position).Magnitude <= Config.GK_FORWARD_CAPTURE_RANGE then
					dash.resolved = true
					ball.CanCollide = true
					setOwner(player)
				end
			end
		end

		-- ⚠️ NOVO: Arrancada Selvagem/Investida Titânica (ver
		-- _G.StartPulseDashTackle mais abaixo) — dash reto SEM alvo fixo
		-- nenhum: acerta QUALQUER adversário que a hitbox (crescendo ao
		-- vivo conforme o jogador alterna A/D) tocar, com ou sem bola,
		-- em qualquer lugar do campo (pedido explícito do usuário).
		-- ⚠️ v110: carrinho de Hissatsu chegou no fim do caminho sem acertar
		-- ninguém — a técnica acontece ali mesmo ("vai na reta e faz o que faz")
		if dash.aoChegar and not dash.chegouFixo and tick() - dash.triggeredAt >= (dash.moveDuration or 0) then
			dash.chegouFixo = true
			dash.aoChegar()
		end

		if dash.isPulseDash and (dash.multiAlvo or not dash.resolved) and not dash.chegouFixo and not dash.semContato then
			for _, other in ipairs(Players:GetPlayers()) do
				if other == player or not areOpponents(player, other) then continue end
				if dash.atingidos and dash.atingidos[other] then continue end
				local _, otherRoot = getCharacterParts(other)
				if not otherRoot then continue end
				if (root.Position - otherRoot.Position).Magnitude <= (dash.hitboxRadius or 0) then
					dash.resolved = true
					if dash.atingidos then dash.atingidos[other] = true end
					applyPulseDashHit(player, other, dash)
					-- ⚠️ v110: carrinho de Hissatsu PARA no primeiro que encostar e
					-- a técnica acontece ali (roubou a bola e já aplica o efeito)
					if dash.aoChegar and not dash.chegouFixo then
						dash.chegouFixo = true
						dash.endPosition = root.Position
						dash.startPosition = root.Position
						dash.aoChegar()
						break
					end
					-- ⚠️ v108: roubou a bola — ninguém tira dele até o fim da investida
					if owner == player and not dash.iframeDado and _G.GrantPulseIframe then
						dash.iframeDado = true
						_G.GrantPulseIframe(player, math.max(dash.expiresAt - tick(), 0) + 0.3)
					end
					if not dash.multiAlvo then break end
				end
			end
		end
	end
end)

Remotes.AttemptTackle.OnServerEvent:Connect(function(player, directionArg)
	if _G.HissatsuCutsceneActive then return end -- ⚠️ v87: ninguém age durante a cutscene de Hissatsu
	if isStunned(player) then return end
	if tackleDashes[player] then return end
	if owner == player then
		warn(player.Name .. " tentou carrinho mas está com a posse da bola.")
		return
	end

	-- PEDIDO: cooldown FIXO de Config.TACKLE_COOLDOWN (4s) por tentativa —
	-- antes não tinha nenhum, só o custo de stamina, e dava pra spamar a
	-- tecla. Conta a partir de QUALQUER tentativa válida (acertando ou
	-- errando), não só carrinho bem-sucedido.
	local lastTackleAttempt = tackleCooldowns[player]
	if lastTackleAttempt and tick() - lastTackleAttempt < Config.TACKLE_COOLDOWN then return end

	local _, playerRoot = getCharacterParts(player)
	if not playerRoot then return end

	-- ⚠️ v15: direção escolhida pelo jogador (ver startTackleDash). Vem do
	-- cliente, então é tratada como palpite: só é aceita se for um Vector3
	-- com componente horizontal de verdade, e é achatada/normalizada aqui —
	-- o cliente não consegue mandar um carrinho pra cima, pra dentro do
	-- chão, nem com magnitude inflada pra alcançar mais longe.
	local requestedDirection
	if typeof(directionArg) == "Vector3" then
		local flat = Vector3.new(directionArg.X, 0, directionArg.Z)
		if flat.Magnitude > 0.1 then
			requestedDirection = flat.Unit
		end
	end

	tackleCooldowns[player] = tick()
	if _G.NotifyInstinctAction then _G.NotifyInstinctAction(player, "Tackle") end -- ⚠️ v6.5: carga de "prática" do Instinct Mode

	-- ===== PULSO/INSTINTO: consome/checa no instante do carrinho =====
	local ownGoal = player.Team and ownGoalOf(player.Team.Name)
	-- ⚠️ v9: "Emboscada" — quantos ADVERSÁRIOS estão perto o bastante de
	-- você AGORA (situação de ser cercado/dobrado, não só "qualquer
	-- carrinho") — ver Instinto "Emboscada" em PulseInstinctData.luau.
	local AMBUSH_RADIUS = 10
	local nearbyOpponentsCount = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player or not areOpponents(player, plr) then continue end
		local _, oRoot = getCharacterParts(plr)
		if oRoot and (oRoot.Position - playerRoot.Position).Magnitude <= AMBUSH_RADIUS then
			nearbyOpponentsCount += 1
		end
	end
	local ctx = {
		DistanceToOwnGoal = ownGoal and (playerRoot.Position - ownGoal.Position).Magnitude or math.huge,
		-- ⚠️ v5.4: "Sentinela" agora exige estar DENTRO da própria área de
		-- verdade (fallback true: se a Part GKArea_<Time> não existir na
		-- cena, não trava o Instinto — mesma filosofia do resto do módulo).
		InOwnArea = player.Team and GKAreaUtil.IsPositionInArea(player.Team.Name, playerRoot.Position, true) or false,
		OpponentsNearbyCount = nearbyOpponentsCount,
		AttackingHalf = player.Team and attackingHalfOf(player.Team.Name, playerRoot.Position) or nil, -- ⚠️ v110 (DefendingHalf)
	}
	local instEffect = _G.CheckInstinct and _G.CheckInstinct(player, "Tackle", ctx)
	local pulseEffect = _G.TryConsumePulse and _G.TryConsumePulse(player, "Tackle")
	local tackleChanceBonus = (instEffect and instEffect.ChanceAdd or 0) + (pulseEffect and pulseEffect.ChanceAdd or 0)
	local tackleChanceSet = (pulseEffect and pulseEffect.ChanceSet) or (instEffect and instEffect.ChanceSet)
	noStunOnFail[player] = (pulseEffect and pulseEffect.NoStunOnFail) or false
	task.delay(2, function() noStunOnFail[player] = nil end) -- limpa mesmo se nada resolver a tempo

	if owner then
		local targetOwner = owner

		if not areOpponents(player, targetOwner) then
			warn(("%s tentou carrinho em cima de %s, mas os dois são do mesmo time — bloqueado."):format(player.Name, targetOwner.Name))
			return
		end

		if not Config.SpendStamina(player, Config.TACKLE_STAMINA_COST) then
			warn(player.Name .. " tentou carrinho mas não tem stamina suficiente.")
			return
		end

		playAnimation(player, Config.ANIMATIONS.Tackle, nil, Config.TACKLE_DASH_DURATION)
		local dash = startTackleDash(player, playerRoot, targetOwner, requestedDirection)

		task.delay(Config.TACKLE_DASH_DURATION, function()
			if tackleDashes[player] == dash then
				tackleDashes[player] = nil
			end
			if dash.resolved then return end -- já resolvido durante o lunge — referência direta, sem corrida
			resolveStealAttempt(player, targetOwner)
		end)
		return
	end

	if not Config.SpendStamina(player, Config.TACKLE_STAMINA_COST) then
		warn(player.Name .. " tentou carrinho mas não tem stamina suficiente.")
		return
	end

	playAnimation(player, Config.ANIMATIONS.Tackle, nil, Config.TACKLE_DASH_DURATION)
	startTackleDash(player, playerRoot, nil, requestedDirection)

	if pendingLooseTackle and pendingLooseTackle.player ~= player
		and (tick() - pendingLooseTackle.time) <= Config.TACKLE_CONTEST_WINDOW then
		local rival = pendingLooseTackle.player
		pendingLooseTackle = nil
		local myChance = tackleChanceSet or math.clamp(resolvePhysicalClashChance(player, rival) + tackleChanceBonus, 0.05, 1.0)

		task.delay(Config.TACKLE_DASH_DURATION, function()
			tackleDashes[player] = nil
			if owner or deadBallMode then return end

			local _, currentRoot = getCharacterParts(player)
			local closeEnough = currentRoot and canCaptureLooseBallByTackle(player, currentRoot)
			if not closeEnough then
				applyTackleMiss(player)
				return
			end

			if math.random() <= myChance then
				setOwner(player)
			else
				setOwner(rival)
				applyTackleMiss(player)
			end
		end)
	else
		pendingLooseTackle = { player = player, time = tick() }
		task.delay(Config.TACKLE_DASH_DURATION, function()
			tackleDashes[player] = nil
			if not pendingLooseTackle or pendingLooseTackle.player ~= player then return end
			pendingLooseTackle = nil
			if owner or deadBallMode then return end

			local _, currentRoot = getCharacterParts(player)
			if currentRoot and canCaptureLooseBallByTackle(player, currentRoot) then
				setOwner(player)
			else
				applyTackleMiss(player)
			end
		end)
	end
end)

-- ⚠️ v120b — PEDIDO: "algumas resets depois de usar habilidades, o personagem entra
-- na terra, encosta ali e começa a bugar a animação e o torso — senão cai no void".
-- O reset (gol/kickoff) fazia root.CFrame = formação com coisas ainda em andamento:
-- carrinho/dive ainda arrastando o corpo pro caminho antigo, ragdoll com as juntas
-- soltas, deslocamento do cliente. Isto cancela tudo antes de reposicionar.
_G.LimparAcoesDoJogador = function(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return end
	tackleDashes[player] = nil
	if diving[player] then
		diving[player] = nil
		setIframeGlow(player, false)
	end
	local estadoRagdoll = ragdollState[player]
	if estadoRagdoll then restoreFromRagdoll(player, estadoRagdoll.expiresAt) end
	if player.Parent == Players then
		Remotes.ApplyDisplacement:FireClient(player, Vector3.zero, 0) -- duração 0 = cancelar
	end
	local _, root, humanoid = getCharacterParts(player)
	if humanoid then
		humanoid.PlatformStand = false
		humanoid.Sit = false
		local estado = humanoid:GetState()
		if estado == Enum.HumanoidStateType.Physics or estado == Enum.HumanoidStateType.Ragdoll
			or estado == Enum.HumanoidStateType.FallingDown then
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	if root and not _G.HissatsuCutsceneActive then root.Anchored = false end
end

-- ===== EXPOSTO PARA OUTROS SCRIPTS =====
_G.GetBallTouchers = function()
	return lastTouchers[1], lastTouchers[2]
end

-- ⚠️ v84: ver ultimoToqueNaBola, lá em cima. O GKBotController chama
-- MarkBotBallTouch toda vez que o bot mexe na bola.
_G.MarkBotBallTouch = function(teamName)
	ultimoToqueNaBola = { Kind = "Bot", Team = teamName }
end
_G.GetLastBallTouch = function()
	return ultimoToqueNaBola
end

_G.SetBallOwnerForced = setOwner
_G.ReleaseBallOwner = releaseOwner
_G.GetBallOwner = function() return owner end
_G.SetDeadBallMode = function(active)
	deadBallMode = active
end

_G.ResetBallState = function(centerPosition)
	-- ⚠️ v119 — BUG "às vezes as hissatsus fazem DOIS gols": o reinício (gol, saída,
	-- kickoff) não desligava o voo travado da Hissatsu — o Heartbeat da MIRA TRAVADA
	-- continuava recolocando a bola na reta do chute com a velocidade dela, e quando
	-- a bola era solta no meio-campo ela disparava pro gol de novo.
	stopPulseStraightFlight()
	releaseOwner()
	lastTouchers = {}
	ultimoToqueNaBola = nil
	pendingLooseTackle = nil
	curveGeneration += 1
	ballStateGeneration += 1 -- ⚠️ v6.2: ver comentário na declaração acima
	trail.Enabled = false
	endKickClearance() -- ⚠️ v20: bola reposicionada (gol/saída) — cancela qualquer janela de saída de chute aberta
	ball.CanCollide = true
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = CFrame.new(centerPosition)
end

-- ⚠️ v14 — PEDIDO: "não dá pra fazer uma cabeçada com o Quick Time Event,
-- não faz sentido... ou faz a bola paralisar no ar e rolar o Quick Time
-- Event." É a segunda opção: a bola trava no ar no instante em que a
-- Hissatsu é apertada, o QTE roda com ela parada, e ela só volta a existir
-- fisicamente quando o QTE resolve (aí a cabeçada sai de verdade).
--
-- Reusa de propósito a MESMA flag ballFrozenForGuardQTE da guarda do
-- goleiro, em vez de inventar uma segunda: os guards que impedem a bola
-- congelada de ser pega/empurrada/considerada "bola solta" já estão
-- espalhados pelos Heartbeats deste arquivo checando essa flag (ver os
-- `if ballFrozenForGuardQTE then return end`). Uma flag nova exigiria
-- repetir todos eles e a primeira que alguém esquecesse viraria bug.
-- ⚠️ v23 — PEDIDO: "quanto mais distante, não era só o deslizamento: agora
-- a bola tem quicado. Diminui muito a quicada quando o GK jogar pra muito
-- longe. Só que só até o próximo domínio — quando a próxima pessoa dominar,
-- ela volta a quicar normalmente."
--
-- Quica = Elasticity das CustomPhysicalProperties. O lançamento longo do
-- goleiro precisa de um arco alto (pra chegar manso), e arco alto significa
-- cair de cima — o que fazia a bola pular várias vezes antes de sossegar.
-- Aqui ela cai "murcha"; setOwner devolve o original assim que QUALQUER um
-- dominar, então o quique normal continua valendo pro resto do jogo.
local originalBallPhysicalProperties = ball.CustomPhysicalProperties

local function setBallBounce(elasticity)
	local base = ball.CustomPhysicalProperties or PhysicalProperties.new(ball.Material)
	ball.CustomPhysicalProperties = PhysicalProperties.new(
		base.Density,
		base.Friction,
		elasticity,
		base.FrictionWeight,
		base.ElasticityWeight
	)
end

local function restoreBallBounce()
	ball.CustomPhysicalProperties = originalBallPhysicalProperties
end

_G.SetBallLowBounce = function(elasticity)
	setBallBounce(math.clamp(elasticity or 0.05, 0, 1))
end

_G.RestoreBallBounce = restoreBallBounce

_G.FreezeBallForQTE = function()
	if ballFrozenForGuardQTE then return false end -- já congelada (guarda do goleiro): não atropela
	ballFrozenForGuardQTE = true
	stopPulseStraightFlight()
	curveGeneration += 1 -- cancela qualquer curva em andamento, senão ela brigaria com o anchor
	ball.Anchored = true
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	return true
end

-- Solta a bola. NÃO devolve a velocidade que ela tinha: quem chama isso é
-- o fim de um QTE que vai executar uma ação NA bola logo em seguida
-- (cabeçada), e restaurar a velocidade antiga só faria ela fugir do pé
-- entre o release e a ação.
_G.ReleaseBallFromQTE = function()
	if not ballFrozenForGuardQTE then return end
	ballFrozenForGuardQTE = false
	ball.Anchored = false
end

-- ⚠️ v67 — NÉVOA: esconder/mostrar a bola.
-- PEDIDO: "a bola também some junto com o jogador, e só aparece na hora que
-- ele sair da área." Guarda a transparência original pra devolver exatamente
-- o que era, em vez de assumir 0 (a bola pode ter textura/decal própria).
local transparenciaOriginalDaBola = nil
_G.SetBallHidden = function(escondida)
	if escondida then
		if transparenciaOriginalDaBola == nil then
			transparenciaOriginalDaBola = ball.Transparency
		end
		ball.Transparency = 1
		trail.Enabled = false -- o rastro entregaria a posição dela
	elseif transparenciaOriginalDaBola ~= nil then
		ball.Transparency = transparenciaOriginalDaBola
		transparenciaOriginalDaBola = nil
	end
end

_G.GetBallStateGeneration = function()
	return ballStateGeneration
end

-- ================================================================
-- REWORK "PULSO": EXECUÇÃO AUTOMÁTICA DE AÇÃO
-- ================================================================
-- Chamado pelo PulseController.lua (novo modelo: apertar o botão do
-- Pulso já EXECUTA a ação sozinha — sem mirar/carregar/soltar à parte).
-- Cada _G.PulseExecute* abaixo reaproveita a MESMA física/regras dos
-- handlers normais acima (KickBall/AttemptHeader/AttemptTackle/
-- AttemptDribbleMove) através das locals já declaradas neste arquivo —
-- só decide o alvo/direção sozinho (auto-mira/auto-alvo) e aplica
-- diretamente o Effect (Perfeito ou Bom) que o PulseController mandar,
-- sem esperar o jogador mirar/segurar botão. Cada função devolve
-- true/false (conseguiu executar de verdade ou não — ex: perdeu a posse
-- durante a janela de precisão) pro PulseController decidir o feedback.

_G.IsDeadBallMode = function()
	return deadBallMode
end

_G.PulseHasControl = function(player)
	return owner == player
end

-- Bola no ar e perto o bastante do jogador — mesma checagem que
-- AttemptHeader já usa pra aceitar a cabeçada.
-- ⚠️ v5.2: aceita um "effect" opcional que ALARGA a janela do cabeceio.
-- Motivo: a janela padrão é apertadíssima — a bola precisa estar a no
-- máximo HEADER_RANGE (6) de distância E pelo menos HEADER_MIN_BALL_HEIGHT
-- (3) acima da cabeça. Pra um cabeceio manual tudo bem, mas um Instinto de
-- finalização acrobática (Predador da Área) ficava impossível de acertar:
-- o jogador apertava R e, quase sempre, não havia bola dentro dessa
-- janela — sem nenhum aviso de por quê. Com HeaderRangeAdd/HeaderMinHeight
-- o Instinto tem o alcance de um instinto, não o de um cabeceio comum.
_G.PulseCanHeader = function(player, effect)
	local _, root = getCharacterParts(player)
	if not root then return false end
	effect = effect or {}

	local alcance = Config.HEADER_RANGE + (effect.HeaderRangeAdd or 0)
	local alturaMinima = effect.HeaderMinHeight or Config.HEADER_MIN_BALL_HEIGHT
	local alturaMaxima = Config.HEADER_MAX_BALL_HEIGHT + (effect.HeaderRangeAdd or 0)

	-- ⚠️ v5.3: mesmo cilindro do cabeceio manual — horizontal e altura
	-- separados, em vez de distância 3D (ver AttemptHeader).
	local alturaBola = ball.Position.Y - root.Position.Y
	local distanciaHorizontal = (Vector3.new(ball.Position.X, 0, ball.Position.Z)
		- Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	return distanciaHorizontal <= alcance and alturaBola >= alturaMinima and alturaBola <= alturaMaxima
end

-- Explica POR QUE não deu pra cabecear — usado só pelo Instinto de botão,
-- pra você ver no console em vez de apertar R no escuro.
_G.PulseHeaderFailReason = function(player, effect)
	local _, root = getCharacterParts(player)
	if not root then return "sem personagem" end
	effect = effect or {}
	local alcance = Config.HEADER_RANGE + (effect.HeaderRangeAdd or 0)
	local alturaMinima = effect.HeaderMinHeight or Config.HEADER_MIN_BALL_HEIGHT
	local alturaMaxima = Config.HEADER_MAX_BALL_HEIGHT + (effect.HeaderRangeAdd or 0)
	local altura = ball.Position.Y - root.Position.Y
	local distanciaHorizontal = (Vector3.new(ball.Position.X, 0, ball.Position.Z)
		- Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
	if distanciaHorizontal > alcance then
		return string.format("bola longe demais (%.1f studs na horizontal, precisa <= %.1f)", distanciaHorizontal, alcance)
	end
	if altura < alturaMinima then
		return string.format("bola baixa demais (%.1f acima de você, precisa >= %.1f)", altura, alturaMinima)
	end
	if altura > alturaMaxima then
		return string.format("bola alta demais (%.1f acima de você, teto %.1f)", altura, alturaMaxima)
	end
	return "condição de cabeceio ok"
end

-- true se existe um adversário COM A BOLA (o único alvo de carrinho que
-- faz sentido nesse jogo — bola sempre tem um dono só) dentro do alcance
-- de carrinho.
-- ⚠️ v43 — `bonusAlcance` NOVO. A Rasteira promete "carrinho seco, com bem
-- MAIS ALCANCE que o normal" (ver Description em PulseInstinctData), mas o
-- alcance aqui era um Config.TACKLE_RANGE fixo, igual pra todo mundo —
-- então essa promessa simplesmente não existia no jogo. Mesmo tipo de
-- buraco do Rebate do Soco Explosivo: descrito no texto, sem chave nenhuma
-- que o código pudesse ler. Agora cada Hissatsu de carrinho pode declarar
-- TackleRangeAdd no Effect dela, e esse bônus vale nos DOIS lugares que
-- medem alcance de carrinho: a checagem de disponibilidade (PulseController,
-- que decide se a habilidade pode sair) e a execução (_G.PulseExecuteTackle
-- logo abaixo). Sem a chave, tudo continua exatamente como era.
_G.PulseHasOpponentInTackleRange = function(player, bonusAlcance)
	if not owner or owner == player then return false end
	if not areOpponents(player, owner) then return false end
	local _, playerRoot = getCharacterParts(player)
	local _, targetRoot = getCharacterParts(owner)
	if not playerRoot or not targetRoot then return false end
	local alcance = Config.TACKLE_RANGE + (bonusAlcance or 0)
	return (targetRoot.Position - playerRoot.Position).Magnitude <= alcance
end

-- Goleiro adversário (RoleRequired GK) de quem está nesse time, se
-- existir em campo.
local function pulseEnemyGK(teamName)
	local enemyTeam = otherTeamName(teamName)
	return enemyTeam and findRolePlayer(enemyTeam, "GK") or nil
end

-- Ponto de mira automática no gol adversário: canto mais distante da
-- posição ATUAL do goleiro (se tiver um defendendo), senão o centro do
-- gol. Assume que o CFrame.RightVector de cada goalPart aponta ao longo
-- da LARGURA da trave (mesma convenção já usada em todo o arquivo pro
-- lado de um personagem, ver root.CFrame.RightVector) — não depende da
-- orientação de CampoHIT. ⚠️ Não testável sem uma sessão Roblox real —
-- se os gols estiverem girados de um jeito que RightVector não siga a
-- largura da trave, o "canto" sai errado (ainda mira em algum ponto
-- dentro do gol, só não necessariamente no canto certo).
_G.PulseComputeShotTarget = function(player)
	-- ⚠️ v85 — PEDIDO: "remova o assistente de mira da hissatsu... é só ir
	-- exatamente onde está apontado o mouse". O ponto que o cliente manda (o
	-- que está debaixo do cursor, ver computeAimPoint em HissatsuInput.local.
	-- luau) é usado EXATAMENTE como veio. Saíram a assistência de altura
	-- (v67/v84) e as travas de altura PULSE_AIM_MAX_DROP/MAX_RISE (v36) — elas
	-- existiam pra segurar pontos absurdos que o cliente antigo gerava (113
	-- studs abaixo da grama), e a mira nova não gera mais isso: o raio para no
	-- gramado, ou segue a direção exata do cursor quando não bate em nada.
	--
	-- Só sobrou uma exceção: mira praticamente sem distância na horizontal (o
	-- cursor em cima do próprio pé) não aponta pra lugar nenhum — aí cai na
	-- mira automática de canto logo abaixo, igual quando não há mira.
	local aimPoint = _G.GetPulseAimPoint and _G.GetPulseAimPoint(player)
	if typeof(aimPoint) == "Vector3" then
		local horizontal = Vector3.new(aimPoint.X - ball.Position.X, 0, aimPoint.Z - ball.Position.Z).Magnitude
		if horizontal >= Config.PULSE_AIM_MIN_HORIZONTAL then
			return aimPoint
		end

		warn(string.format(
			"⚽ [Mira] mira degenerada (só %.1f studs na horizontal) — usando a mira automática de canto.",
			horizontal))
	end

	if not player.Team then return nil end
	local enemyGoal = enemyGoalOf(player.Team.Name)
	if not enemyGoal then return nil end

	local gk = pulseEnemyGK(player.Team.Name)
	local rightVector = enemyGoal.CFrame.RightVector
	local halfWidth = (getGoalWidth(enemyGoal) / 2) * 0.75

	if gk then
		local _, gkRoot = getCharacterParts(gk)
		if gkRoot then
			local side = (gkRoot.Position - enemyGoal.Position):Dot(rightVector)
			local farSide = (side >= 0) and -1 or 1
			return enemyGoal.Position + rightVector * halfWidth * farSide
		end
	end
	return enemyGoal.Position
end

-- ===== v7: GUARDA DO GOLEIRO — visual (quadrado flutuante placeholder)
-- + detecção de colisão + resolução (Físico vs Força / QTE) =====
-- PEDIDO: "vai ter uma área [...] quando você usar a Hissatsu do
-- goleiro [...] coloca um quadrado que ocupa metade do tamanho do gol,
-- que aparece na frente do jogador, pra quando a bola colidir lá, ele
-- começar o QTE. [...] Isso é mais fácil de não errar a Hissatsu do
-- gol." Placeholder por enquanto (sem modelo ainda, só um Part
-- translúcido) — 100% criado por script, sem precisar de nada colocado
-- manualmente no Studio.
local guardVisuals = {} -- [player] = Part

local function getOrCreateGuardVisual(player)
	local part = guardVisuals[player]
	if part and part.Parent then return part end
	part = Instance.new("Part")
	part.Name = "GKGuardVisual"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(120, 200, 255)
	part.Transparency = 0.5
	part.Parent = workspace
	guardVisuals[player] = part
	return part
end

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local guard = _G.GetGKGuard and _G.GetGKGuard(player)
		if not guard then
			local existing = guardVisuals[player]
			if existing then existing.Transparency = 1 end
			continue
		end
		local ownGoal = player.Team and ownGoalOf(player.Team.Name)
		local _, root = getCharacterParts(player)
		if not ownGoal or not root then continue end

		local part = getOrCreateGuardVisual(player)
		-- ⚠️ v9 FIX: largura de verdade (getGoalWidth, não só Size.X — ver
		-- comentário lá em cima) + altura de verdade do gol (Size.Y, que é
		-- sempre vertical não importa a rotação) em vez de um quadrado —
		-- "faça jus ao nome, as hissatsus precisam ter alta hitbox".
		local width = getGoalWidth(ownGoal) * (guard.GuardSize or 0.5)
		local height = math.max(ownGoal.Size.Y * 0.95, width * 0.4)
		part.Size = Vector3.new(width, height, 0.5)
		part.Transparency = 0.35

		-- Fica de frente pro campo (de costas pro próprio gol), flutuando
		-- um pouco na frente do goleiro.
		local facing = ownGoal.Position - root.Position
		facing = Vector3.new(facing.X, 0, facing.Z)
		if facing.Magnitude < 0.1 then
			facing = -Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		end
		if facing.Magnitude < 0.1 then facing = Vector3.new(0, 0, -1) end
		facing = -facing.Unit -- aponta PRA FORA do próprio gol, de frente pro campo

		local center = root.Position + facing * 4 + Vector3.new(0, height / 2, 0)
		part.CFrame = CFrame.lookAt(center, center + facing)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local part = guardVisuals[player]
	if part then part:Destroy() end
	guardVisuals[player] = nil
end)

-- ⚠️ v9 PEDIDO: "a hissatsu da muralha também não apareceu nenhuma
-- hitbox... faça jus ao nome". Grande Muralha nunca teve visual — o
-- bloqueio (_G.GetPulseBlock) sempre foi só um raio invisível. Agora toda
-- vez que o raio estiver ativo (Buff em duração, ver ActiveBuff em
-- PulseController.legacy.luau), mostra uma esfera translúcida do raio de
-- verdade em volta do jogador, do tamanho exato que decide o bloqueio.
local blockVisuals = {} -- [player] = Part

-- ⚠️ v103: as peças visuais de habilidade (guarda do goleiro, bloqueio) que
-- estão aparecendo nesse instante entram em cada amostra do replay
replayExtras.Visuais = function()
	local lista = nil
	local function add(part)
		if not part or not part.Parent or part.Transparency >= 0.99 then return end
		lista = lista or {}
		local cf = part.CFrame
		local c = part.Color
		table.insert(lista, {
			cf = { cf:GetComponents() }, sx = part.Size.X, sy = part.Size.Y, sz = part.Size.Z,
			r = c.R, g = c.G, b = c.B, tr = part.Transparency,
			bola = part.Shape == Enum.PartType.Ball,
		})
	end
	for _, part in pairs(guardVisuals) do add(part) end
	for _, part in pairs(blockVisuals) do add(part) end
	return lista
end

local function getOrCreateBlockVisual(player)
	local part = blockVisuals[player]
	if part and part.Parent then return part end
	part = Instance.new("Part")
	part.Name = "PulseBlockVisual"
	part.Shape = Enum.PartType.Ball
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Material = Enum.Material.ForceField
	part.Color = Color3.fromRGB(255, 140, 60)
	part.Transparency = 0.6
	part.Parent = workspace
	blockVisuals[player] = part
	return part
end

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local radius = _G.GetPulseBlock and _G.GetPulseBlock(player)
		-- ⚠️ v120b: com o muro, a barreira É o muro (desenhado no cliente) — sem a esfera
		if radius and _G.MuroDaBarreira and _G.MuroDaBarreira(player) then radius = nil end
		if not radius then
			local existing = blockVisuals[player]
			if existing then existing.Transparency = 1 end
			continue
		end
		local _, root = getCharacterParts(player)
		if not root then continue end
		local part = getOrCreateBlockVisual(player)
		part.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
		part.CFrame = CFrame.new(root.Position)
		part.Transparency = 0.6
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local part = blockVisuals[player]
	if part then part:Destroy() end
	blockVisuals[player] = nil
end)

-- Detecção de colisão: só reage a chutes de PULSO em voo reto
-- (pulseStraightFlightActive) — chute avulso normal NUNCA aciona isso,
-- ele resolve só pelo mergulho normal (Físico vs Força) acima. Assim que
-- a bola entra na área da guarda de um goleiro, congela tudo e delega o
-- resultado pro QTE de colisão de verdade.
local guardResolving = {} -- [player] = true enquanto o QTE de colisão desse goleiro está rodando

RunService.Heartbeat:Connect(function()
	if not pulseStraightFlightActive then return end
	if ballFrozenForGuardQTE then return end

	for _, player in ipairs(Players:GetPlayers()) do
		if guardResolving[player] then continue end
		local guard = _G.GetGKGuard and _G.GetGKGuard(player)
		if not guard then continue end

		local ownGoal = player.Team and ownGoalOf(player.Team.Name)
		local _, root = getCharacterParts(player)
		if not ownGoal or not root then continue end

		local horizontalDistance = (Vector3.new(ball.Position.X, 0, ball.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
		local guardWidth = getGoalWidth(ownGoal) * (guard.GuardSize or 0.5)
		local guardHeight = math.max(ownGoal.Size.Y * 0.95, guardWidth * 0.4)
		local guardRadius = guardWidth / 2
		if horizontalDistance > guardRadius then continue end
		-- Chute alto demais passa POR CIMA da guarda em vez de colidir —
		-- ela tem altura de verdade agora (guardHeight), não é mais um
		-- plano infinito.
		local verticalOffset = ball.Position.Y - root.Position.Y
		if verticalOffset > guardHeight + 2 then continue end

		-- Colidiu — congela a bola (ninguém mais toca, ver os guards de
		-- ballFrozenForGuardQTE espalhados nos outros Heartbeats) e o
		-- goleiro (freezeMovement já rodou quando a guarda foi armada, mas
		-- reforça aqui também durante o QTE de verdade).
		guardResolving[player] = true
		ballFrozenForGuardQTE = true
		-- ⚠️ v38: captura o número que estava na tela ANTES do
		-- stopPulseStraightFlight limpar tudo — é dele que a drenagem da
		-- defesa parte (ver beginGuardForceDrain lá em cima).
		local forcaNaColisao = pulseFlightLastDisplayed or lastShotForce
		-- ⚠️ v41: guarda a velocidade ANTES de zerar — é ela que volta
		-- intacta se a bola atravessar a guarda (força é vida, não
		-- velocidade; ver resumePulseFlightAfterGuard).
		capturePulseFlightForGuard()
		stopPulseStraightFlight()
		ball.Anchored = true
		ball.CanCollide = false
		ball.AssemblyLinearVelocity = Vector3.zero

		local shooter = recentKicker
		local shooterTeamName = shooter and shooter.Team and shooter.Team.Name
		local forceRating = getShotForceRating(lastShotForce)

		-- ⚠️ v103: a força CONGELA na colisão e só cai por acerto no QTE do
		-- goleiro (ver iniciarDueloDeDefesa) — nada de "sugar" antes do QTE.
		local duelo = iniciarDueloDeDefesa(forcaNaColisao)
		-- ⚠️ v103: cutscene da defesa pela duração do QTE da guarda; o
		-- resultado só é aplicado quando ela acaba
		local fimCutsceneDefesa = tick()
		local durDefesa = (guard.Def and guard.Def.QTE and guard.Def.QTE.Duration) or 3.5
		if _G.TocarCutsceneDeDefesa and _G.TocarCutsceneDeDefesa(player.Character, guard.Def, durDefesa) then
			fimCutsceneDefesa = tick() + durDefesa
		end

		local function finish(caught, rebate)
			-- a força que SOBROU é a vida com que a bola segue voando
			local forcaRestante = duelo.Encerrar(caught)
			ball.Anchored = false
			ball.CanCollide = true
			if caught and rebate then
				-- ⚠️ v39 — PEDIDO: "o efeito do soco do GK é dar um knockback
				-- na bola, e ele só pegou a bola em vez de dar o knockback."
				-- O Soco Explosivo é a única guarda que NUNCA segura (ver
				-- Rebate em PulseInstinctData) — defendeu com sucesso, mas
				-- devolve a bola pro campo. Isso estava só na descrição
				-- dela; sem um sinal explícito, defender era sinônimo de
				-- agarrar aqui também.
				local away = root.Position - ownGoal.Position
				away = Vector3.new(away.X, 0, away.Z)
				away = (away.Magnitude > 0.1) and away.Unit or root.CFrame.LookVector
				ball.AssemblyAngularVelocity = Vector3.zero
				ball.Position = root.Position + away * 3 + Vector3.new(0, 2, 0)
				ball.AssemblyLinearVelocity = away * Config.GK_PUNCH_REBOUND_FORCE + Vector3.new(0, 16, 0)
				if _G.RegisterSave then _G.RegisterSave(player) end
			elseif caught then
				ball.AssemblyLinearVelocity = Vector3.zero
				setOwner(player)
				if _G.RegisterSave then _G.RegisterSave(player) end
			else
				-- ⚠️ v41 — PEDIDO: "11 de força ainda é movimento... a bola
				-- vai continuar andando na MESMA velocidade, nesse caso ela
				-- entraria no gol de todo jeito." Antes aqui tinha um
				-- empurrãozinho fixo de 12 studs/s, que na prática fazia a
				-- bola PARAR no ar depois de uma defesa que quase segurou —
				-- força baixa virava velocidade baixa, e não é isso que o
				-- número significa. Agora ela retoma o voo exatamente como
				-- estava (mesma direção, mesmo módulo), só com menos vida.
				local retomou = resumePulseFlightAfterGuard(forcaRestante or 0)
				if not retomou then
					-- só se não havia velocidade guardada (caso de borda)
					local towardGoal = ownGoal.Position - root.Position
					if towardGoal.Magnitude > 0.1 then
						ball.AssemblyLinearVelocity = towardGoal.Unit * 12
					end
				end
				if shooterTeamName and _G.RegisterGoal then
					_G.RegisterGoal(shooterTeamName)
				end
			end
			ballFrozenForGuardQTE = false
			guardResolving[player] = false
		end

		if _G.ConsumeGKGuardOnCollision then
			-- ⚠️ v103: quem decide é o DANO dos acertos, não mais Físico vs
			-- nota do chute: defendeu = a força chegou a 0.
			local started = _G.ConsumeGKGuardOnCollision(player, function(perfect, effect)
				task.delay(math.max(0, fimCutsceneDefesa - tick()), function()
					finish(duelo.Atual() <= 0, effect and effect.Rebate)
				end)
			end, function(hits, dano)
				if hits == 0 then duelo.Impacto(dano) else duelo.Dano(dano) end -- (hits 0 = o impacto)
			end)
			if not started then finish(false) end
		else
			finish(false)
		end

		break -- só resolve 1 colisão por frame — a próxima bola gera outra colisão do zero
	end
end)

-- Melhor companheiro aberto pra passe automático: entre os do mesmo
-- time, prioriza quem tem linha de passe livre (nenhum adversário perto
-- o bastante da reta jogador→companheiro) e, dentre esses, o mais
-- adiantado (mais perto do gol adversário); sem ninguém de linha livre,
-- cai pro companheiro mais próximo mesmo assim — nunca falha por falta
-- de alvo se existir QUALQUER companheiro em campo.
local OPEN_LANE_MARGIN = 3
_G.PulseComputeBestTeammate = function(player)
	local _, root = getCharacterParts(player)
	if not root or not player.Team then return nil end
	local enemyGoal = enemyGoalOf(player.Team.Name)

	local best, bestScore = nil, -math.huge
	local fallback, fallbackDist = nil, math.huge

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player or areOpponents(player, plr) then continue end
		local _, mateRoot = getCharacterParts(plr)
		if not mateRoot then continue end

		local dist = (mateRoot.Position - root.Position).Magnitude
		if dist < fallbackDist then fallbackDist = dist; fallback = plr end

		local line = mateRoot.Position - root.Position
		local lineLen = line.Magnitude
		local blocked = false
		for _, opp in ipairs(Players:GetPlayers()) do
			if opp == player or not areOpponents(player, opp) then continue end
			local _, oppRoot = getCharacterParts(opp)
			if not oppRoot then continue end
			if lineLen > 0.01 then
				local t = math.clamp((oppRoot.Position - root.Position):Dot(line) / (lineLen * lineLen), 0, 1)
				local closest = root.Position + line * t
				if (oppRoot.Position - closest).Magnitude <= OPEN_LANE_MARGIN then
					blocked = true
					break
				end
			end
		end

		if not blocked then
			local advancement = enemyGoal and -((mateRoot.Position - enemyGoal.Position).Magnitude) or -dist
			if advancement > bestScore then
				bestScore = advancement
				best = plr
			end
		end
	end

	return best or fallback
end

-- ⚠️ NOVO (Pulso do Passe Perfeito): em vez de escolher o companheiro
-- mais ABERTO/adiantado (_G.PulseComputeBestTeammate, acima), trava no
-- companheiro mais PRÓXIMO de onde a bola chegaria se fosse lançada reto
-- na direção que o jogador está olhando — "pousa" num ponto fixo à
-- frente (Config.PULSE_PERFECT_PASS_RANGE studs) e escolhe quem estiver
-- mais perto DESSE PONTO, não de quem está mais aberto. É um passe
-- "cravado": o jogador aponta a direção com o próprio personagem (pra
-- onde ele está de frente) e o Pulso acerta quem estiver ali.
_G.PulseComputeLandingTeammate = function(player)
	local _, root = getCharacterParts(player)
	if not root or not player.Team then return nil end

	local landingPoint = root.Position + root.CFrame.LookVector * Config.PULSE_PERFECT_PASS_RANGE

	local best, bestDist = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player or areOpponents(player, plr) then continue end
		local _, mateRoot = getCharacterParts(plr)
		if not mateRoot then continue end
		local dist = (mateRoot.Position - landingPoint).Magnitude
		if dist < bestDist then
			bestDist = dist
			best = plr
		end
	end

	return best
end

-- ⚠️ v8: "chip do zagueiro" pros Pulsos de Chute — defensor perto o
-- bastante do chutador tem uma chance BASE (Config.PULSE_DEFENDER_CHIP_
-- CHANCE = 55%, ajustada um pouco pela diferença de Physical) de cortar
-- o bônus de raridade+tier do chute, devolvendo a força pra perto do
-- neutro. É esse mecanismo que faz um goleiro+zagueiro em dupla terem
-- chance real contra um Mythic quase imparável 1x1.
local function applyPulseDefenderChip(player, root, force, powerBonus)
	local nearestDefender, bestD = nil, Config.PULSE_DEFENDER_CHIP_RANGE
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player or not areOpponents(player, plr) then continue end
		local _, dRoot = getCharacterParts(plr)
		if not dRoot then continue end
		local d = (dRoot.Position - root.Position).Magnitude
		if d <= bestD then bestD = d; nearestDefender = plr end
	end
	if not nearestDefender then return force end
	local diff = getPhysical(nearestDefender) - getPhysical(player)
	local chipChance = math.clamp(Config.PULSE_DEFENDER_CHIP_CHANCE + diff / 400, 0.25, 0.85)
	local chipped = math.random() < chipChance
	local finalForce = chipped and (force / math.max(powerBonus, 1)) or force
	if Config.PULSE_FORCE_DEBUG_PRINTS then
		print(string.format(
			"🥊 [Pulso] Chip do zagueiro: %s (Physical=%d) perto de %s (Physical=%d) — chance=%.0f%% -> %s | força %d -> %d",
			nearestDefender.Name, getPhysical(nearestDefender), player.Name, getPhysical(player),
			chipChance * 100, chipped and "CORTOU" or "não cortou", math.floor(force), math.floor(finalForce)
		))
	end
	return finalForce
end

-- ===== EXECUÇÃO DE CHUTE/PASSE/COBRANÇA (compartilha a mesma física do
-- KickBall normal, só decide targetPoint/força sozinho) =====
local function pulsePerformKick(player, targetPoint, force, curveMult, aimDeviationMult, effect, forceCapMult, useNormalArc)
	effect = effect or {}
	local _, root = getCharacterParts(player)
	if not root then return false end
	if owner ~= player then return false end

	releaseOwner()
	ball.CanCollide = true
	recentKicker, recentKickTime = player, tick()
	kickerClearedBody = false -- ⚠️ v12: ver BODY_BLOCK
	hasBodyBlockedThisFlight = false -- ⚠️ v14: novo chute de verdade — libera o corpo pra absorver de novo (uma vez)
	startKickClearance(player) -- ⚠️ v20: sai atravessando qualquer coisa colada no corpo dele (ver startKickClearance)

	local direction = (targetPoint - ball.Position)
	if direction.Magnitude < 0.01 then direction = root.CFrame.LookVector end
	direction = direction.Unit

	-- ⚠️ v35/v36 — o diagnóstico de "direção MUITO vertical" que vivia aqui
	-- já cumpriu o papel: ele apontou que a mira vinda do cliente estava a
	-- 113 studs ABAIXO da bola, e a correção foi feita na ORIGEM (ver
	-- computeAimPoint em HissatsuInput.local.luau e o saneamento em
	-- _G.PulseComputeShotTarget). Manter o aviso aqui viraria spam: com a
	-- mira já sã, um chute por cima da barreira é LEGITIMAMENTE vertical e
	-- cairia nele toda vez. O canário agora é o warn de "[Mira] mira do
	-- cliente saneada", que dispara só quando algo está de fato errado.

	-- ⚠️ v103 — PEDIDO: "testei com o chute glacial e ele foi perfeitamente onde
	-- eu queria. Só que o furacão de fogo não foi exatamente onde eu queria...
	-- calcula o ponto antes de tirar". A diferença entre os dois era o DESVIO
	-- DE MIRA aleatório: a Fúria Glacial tem AimDeviationMult 0.5/0.25 (quase
	-- nada), o Tornado não tem o campo (desvio inteiro) — e chutando lá de
	-- cima, alguns graus viram metros no gol. A Hissatsu de voo reto (sem
	-- arco) agora vai EXATAMENTE na reta até o ponto mirado, calculada da
	-- posição real da bola no instante do chute (onde a cutscene deixou).
	-- Instinto/lançamento (arco) continuam com o desvio de sempre.
	local vooReto = not effect.AerialArc and not useNormalArc
	if not deadBallMode and not vooReto then
		local degrees = getAimDeviationDegrees(player) * (aimDeviationMult or 1)
		direction = applyAimDeviation(direction, degrees)
	end
	if vooReto and Config.PULSE_FORCE_DEBUG_PRINTS then
		print(string.format("🎯 [Hissatsu] chute de (%.1f, %.1f, %.1f) pro alvo (%.1f, %.1f, %.1f) — reta exata, sem desvio",
			ball.Position.X, ball.Position.Y, ball.Position.Z, targetPoint.X, targetPoint.Y, targetPoint.Z))
	end

	nudgeBallForwardForKick(direction) -- ⚠️ v21: já nasce fora do raio do corpo, na direção do chute

	force = math.min(force, Config.KICK_MAX_FORCE * getKickForceMultiplier(player) * (forceCapMult or 1.6))
	if _G.GetPulseActiveKickForceMult then force *= _G.GetPulseActiveKickForceMult(player) end

	-- ⚠️ v3: IgnoreGKChance vindo do EFFECT DO PULSO (antes só o Instinto
	-- Divino do Artilheiro alimentava essa chave, pelo caminho do KickBall
	-- normal). Mesmo mecanismo: registra o tick() do chute que "ignora
	-- goleiro" — o AttemptGKDive lê lastIgnoreGKShot e corta pela metade o
	-- raio de captura do mergulho por 1s.
	if effect.IgnoreGKChance and math.random() < effect.IgnoreGKChance then
		lastIgnoreGKShot = tick()
	end

	-- Pulso Lendário: Chute Fatal — contraplay: um defensor perto o
	-- bastante da linha do chute ainda pode disputar o bloqueio (mesma
	-- fórmula de Physical da disputa de carrinho).
	if effect.DefenderContestRange then
		local nearestDefender, bestD = nil, effect.DefenderContestRange
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == player or not areOpponents(player, plr) then continue end
			local _, dRoot = getCharacterParts(plr)
			if not dRoot then continue end
			local d = (dRoot.Position - root.Position).Magnitude
			if d <= bestD then bestD = d; nearestDefender = plr end
		end
		if nearestDefender then
			local diff = getPhysical(player) - getPhysical(nearestDefender)
			local shooterChance = math.clamp(0.5 + 0.35 * math.tanh(diff / Config.TACKLE_PHYSICAL_STABILIZE_K), 0.15, 0.85)
			if math.random() > shooterChance then
				force = force / (effect.ForceMult or 1) -- disputa ganha pelo defensor: perde o bônus
			end
		end
	end

	-- Pulso do Muro Final: adversário com o bloqueio ativo perto o
	-- bastante anula boa parte da força.
	if _G.GetPulseBlock then
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == player or not areOpponents(player, plr) then continue end
			local radius = _G.GetPulseBlock(plr)
			if not radius then continue end
			if _G.MuroDaBarreira and _G.MuroDaBarreira(plr) then continue end -- ⚠️ v120b: o muro para a bola NO MURO
			local _, blockerRoot = getCharacterParts(plr)
			if blockerRoot and (blockerRoot.Position - root.Position).Magnitude <= radius then
				force *= 0.15
				break
			end
		end
	end

	local velocity
	if effect.AerialArc then
		-- ⚠️ NOVO (Pulso do Passe Perfeito — "trajetória aérea curva pra
		-- evitar interceptações"): em vez de "reto na direção do alvo +
		-- um pouquinho de subida" (o normal de qualquer chute/passe),
		-- calcula uma PARÁBOLA de verdade (física de projétil, mesma
		-- fórmula do lançamento do goleiro em GKBotController.lua) que sobe
		-- alto o bastante pra passar por cima de qualquer defensor no meio
		-- do caminho e desce EXATAMENTE em cima do alvo — mesmo com a
		-- força máxima do usuário.
		local horizontalDistance = Vector3.new(targetPoint.X - ball.Position.X, 0, targetPoint.Z - ball.Position.Z).Magnitude
		-- Tempo de voo: nunca menos que PULSE_AERIAL_ARC_MIN_TIME (garante
		-- um arco visível mesmo pra um alvo bem perto), escalando com a
		-- distância/força pra alvos mais longe.
		local speedBasedTime = horizontalDistance / math.max(force * 0.6, 1)
		local arcTime = math.max(Config.PULSE_AERIAL_ARC_MIN_TIME, speedBasedTime)

		local delta = targetPoint - ball.Position
		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		-- ⚠️ v97: a gravidade que a bola sente é Gravity x BALL_GRAVITY_MULTIPLIER
		-- (a VectorForce dela cancela o resto). Com a gravidade cheia aqui, a
		-- parábola calculada caía ANTES e a bola real passava do companheiro.
		local gravity = workspace.Gravity * Config.BALL_GRAVITY_MULTIPLIER

		local vFlat = flatDelta / arcTime
		local vy = (delta.Y + 0.5 * gravity * arcTime * arcTime) / arcTime
		velocity = Vector3.new(vFlat.X, vy, vFlat.Z)
	elseif useNormalArc then
		-- ⚠️ v8 PEDIDO: chute de INSTINTO usa a MESMA física do chute manual
		-- normal (arco com gravidade, Config.KICK_UPWARD_BOOST) — nada de
		-- voo reto sem gravidade nem número de força flutuando (isso é só
		-- do Pulso/Hissatsu, ver o `else` abaixo).
		-- ⚠️ v97: e agora a mesma PRECISÃO do chute manual — parábola que
		-- passa pelo ponto mirado (ver _G.VelocidadeBalistica).
		velocity = _G.VelocidadeBalistica(ball.Position, ball.Position + direction * (targetPoint - ball.Position).Magnitude, force)
		if not velocity then
			velocity = direction * force
			velocity += Vector3.new(0, force * Config.KICK_UPWARD_BOOST, 0)
		end
	else
		-- PEDIDO: chute/passe de Pulso vai RETO na direção do alvo — sem o
		-- probable boost pra cima do chute normal (Config.KICK_UPWARD_BOOST,
		-- que cria aquele arco leve) — e sem gravidade nenhuma puxando pra
		-- baixo até a bola perder a velocidade (ver startPulseStraightFlight
		-- lá em cima, perto do gravityForce).
		-- ⚠️ v119 — PEDIDO: "as hissatsus estão indo muito rápido pro gol (tipo a Queda
		-- Celestial)". A velocidade era IGUAL à força — numa Mítica, 600-900 studs/s: do
		-- meio-campo chegava no gol em meio segundo, sem dar pra ver o voo. A força (a
		-- VIDA da bola, que decide o duelo com o goleiro) continua a mesma; só a
		-- VELOCIDADE do voo tem teto (HISSATSU_VELOCIDADE_MAX).
		local rapidez = math.min(force, Config.HISSATSU_VELOCIDADE_MAX or 210)
		velocity = direction * rapidez
		startPulseStraightFlight(force)
		-- ⚠️ v110: a RETA fica travada desde o chute (ver o Heartbeat do voo)
		pulseFlightDirecao = direction
		pulseFlightVelocidade = rapidez
		if effect.CurvaInicial then
			local ci = effect.CurvaInicial
			local lado = direction:Cross(Vector3.yAxis)
			lado = lado.Magnitude > 0.05 and lado.Unit or Vector3.xAxis
			local comp = math.min(ci.Comp or 30, (targetPoint - ball.Position).Magnitude * 0.6)
			if comp > 4 then
				_G.VooCurvaInicial = {
					Lado = lado * (math.random() < 0.5 and 1 or -1),
					Comp = comp,
					Amp = comp * math.tan(math.rad(ci.Graus or 10)) / math.pi, -- inclinação máxima = Graus
				}
			end
		end
	end
	ball.AssemblyLinearVelocity = velocity
	lastShotForce = force
	lastShotWasInstinct = useNormalArc == true

	pushToucher(player)
	playKickFeedback(force)
	-- ⚠️ v63 — PEDIDO: "todos [os dribles] começam na animação de idle e
	-- terminam nela. Só corte o final se for o CHUTE, porque aí você vai
	-- nela direto."
	--
	-- O drible está em Action2, ACIMA do chute (Action) — foi de propósito,
	-- pra uma finta poder passar na frente do chute carregado e devolver a
	-- pose depois. Só que isso também faria o rabicho do drible cobrir o
	-- chute de verdade. Cortar o drible aqui é o que deixa o chute entrar
	-- direto, sem esperar a finta terminar de voltar pro idle.
	for _, direcao in ipairs({ "Left", "Back", "Right" }) do
		stopAnimation(player, dribbleAnimationFor(direcao), 0)
	end
	playAnimation(player, Config.ANIMATIONS.Kick, nil, nil, true) -- ⚠️ v60

	-- Sem input de spin do jogador (é tudo automático) — deriva uma curva
	-- "banana" na direção do centro do gol a partir do CurveMult do
	-- Pulso, curvando de fora pra dentro quando mira num canto.
	local spin = 0
	if curveMult and curveMult ~= 0 then
		local enemyGoal = player.Team and enemyGoalOf(player.Team.Name)
		if enemyGoal then
			local side = (targetPoint - enemyGoal.Position):Dot(enemyGoal.CFrame.RightVector)
			spin = (side >= 0 and -1 or 1) * 0.75 * curveMult
		end
	end
	-- ⚠️ v97 — PEDIDO: "quando eu uso a Hissatsu... às vezes a bola vai um
	-- pouco pro lado... precisa ir sempre reto aonde foi mirado". A curva
	-- "banana" automática (CurveMult dos Pulsos, puxando pro centro do gol)
	-- tirava a bola do ponto mirado. Agora a bola vai RETA. O cálculo do spin
	-- acima fica, só não é mais aplicado (Config.PULSE_CURVA_AUTOMATICA liga
	-- de volta, se um dia quiser).
	if Config.PULSE_CURVA_AUTOMATICA then
		applyCurve(spin ~= 0 and spin or nil, direction)
	else
		applyCurve(nil, direction) -- só encerra qualquer curva antiga ainda viva
	end

	return true
end

-- ⚠️ NOVO: PEDIDO — "se a bola sair do campohit... precisa voltar ao
-- goleiro do oponente de quem usou a pulso" + "ele [GKBOT] só usará o
-- pulso contra hissatsus, ele vai mirar e usar a habilidade exatamente
-- quando o pulso de chute sair, na direção dela". Guarda o ÚLTIMO chute
-- de Pulso disparado (pra OutOfBoundsController.legacy.luau saber que uma
-- bola-fora-pela-lateral logo em seguida foi "voo de Hissatsu", não um
-- lateral normal) e avisa, na hora, qualquer script inscrito via
-- _G.RegisterPulseShotListener (o GKBotController usa isso pra reagir
-- "exatamente quando o pulso de chute sair" — ver assignGKBotPulseForTeam/
-- reactToPulseShot em GKBotController.legacy.luau).
local lastPulseShotInfo = nil
local pulseShotFiredListeners = {}

_G.GetLastPulseShotInfo = function()
	return lastPulseShotInfo
end

_G.RegisterPulseShotListener = function(fn)
	table.insert(pulseShotFiredListeners, fn)
end

_G.PulseExecuteShot = function(player, effect, rarity)
	if isStunned(player) then return false end
	if owner ~= player then return false end
	local targetPoint = _G.PulseComputeShotTarget(player)
	if not targetPoint then return false end

	-- ⚠️ v8 PEDIDO ("as duas coisas juntas"): multiplicador de raridade
	-- aplicado EM CIMA da nota de atributo da Hissatsu, ANTES do multiplicador de tier do
	-- QTE (effect.ForceMult, que é o Bom/Perfect do Pulso) — depois disso
	-- ainda entra a queda de força por distância (MaxRange) e o chip do
	-- zagueiro, os dois só pros Pulsos de Chute.
	local rarityMult = (rarity and Config.PULSE_RARITY_POWER_MULT[rarity]) or 1
	-- ⚠️ NOVO: a nota de atributo vem da FÓRMULA da Hissatsu (Scaling — ex.:
	-- 60% Chute + 40% Técnica), já passada pela curva de força do Chute no
	-- PulseController (effect.AttributeForceMult). Sem ela (chamada antiga
	-- sem fórmula), cai no Chute puro. A Energy saiu daqui: é só custo.
	local kickMult = (effect.AttributeForceMult or getKickForceMultiplier(player)) * (effect.ElementoProprioMult or 1) -- ⚠️ v107: elemento próprio
	local baseForce = Config.KICK_MAX_FORCE * kickMult * rarityMult
	local qteTierMult = effect.ForceMult or 1
	local force = baseForce * qteTierMult
	local forceBeforeRangeDecay = force

	local maxRange = rarity and Config.PULSE_RARITY_MAX_RANGE[rarity]
	local originalDistance, originalFactor
	if maxRange then
		originalDistance = (targetPoint - ball.Position).Magnitude
		originalFactor = getPulseRangeFactor(originalDistance, maxRange)
		force *= originalFactor
	end
	local forceAfterRangeDecay = force

	local _, root = getCharacterParts(player)
	if root and rarity then
		force = applyPulseDefenderChip(player, root, force, rarityMult * qteTierMult)
	end

	-- ⚠️ NOVO: PEDIDO — "coloque um print pra eu saber exatamente qual o
	-- número em cada lugar, e quanto a skill de GK ou DF tiraram, pra
	-- poder equilibrar". Mostra a conta INTEIRA de um chute de Pulso, na
	-- ordem em que cada fator é aplicado — dá pra ver exatamente onde a
	-- força sai e onde ela é cortada.
	if Config.PULSE_FORCE_DEBUG_PRINTS then
		print(string.format(
			"💥 [Pulso] %s chutou (raridade %s): KickMax=%d x AtributoMult=%.2f x RarityMult=%.2f = base %d | x QTE=%.2f = %d | distância=%.1f/alcance %.0f -> fator=%.2f = %d | após chip do zagueiro = %d",
			player.Name, tostring(rarity),
			Config.KICK_MAX_FORCE, kickMult, rarityMult, math.floor(baseForce),
			qteTierMult, math.floor(forceBeforeRangeDecay),
			originalDistance or 0, maxRange or 0, originalFactor or 1, math.floor(forceAfterRangeDecay),
			math.floor(force)
		))
	end

	-- ⚠️ v36: guarda o "estado ao vivo" desse chute pro Heartbeat de
	-- pulseForceLabel (ver logo depois de getPulseRangeFactor) recalcular o
	-- número exibido a cada frame, com base na distância JÁ percorrida —
	-- "quero ver a força do chute diminuindo". Só pra Pulso de CHUTE de
	-- verdade (maxRange vem da raridade); Pass/SetPiece ficam com o
	-- número fixo de sempre (stopPulseStraightFlight zera isso tudo de
	-- novo quando o voo acaba).
	if maxRange then
		pulseFlightBaseForce = force
		pulseFlightOriginalDistance = originalDistance
		pulseFlightMaxRange = maxRange
		pulseFlightOriginalFactor = originalFactor
	end

	local aimMult = effect.AimDeviationMult
	if aimMult == nil then aimMult = 1 end

	local shotOrigin = ball.Position
	local shotDelta = targetPoint - shotOrigin
	local shotDirection = shotDelta.Magnitude > 0.01 and shotDelta.Unit or Vector3.new(0, 0, 1)
	lastPulseShotInfo = {
		Player = player,
		Team = player.Team and player.Team.Name,
		Rarity = rarity,
		Element = effect.Elemento, -- ⚠️ v107: o duelo de defesa compara com o elemento da defesa
		QuebraDefesa = effect.QuebraDefesa, -- ⚠️ v109: Ruptura de Gaia — fração do dano da defesa que ela ignora
		TargetPoint = targetPoint,
		Origin = shotOrigin,
		Direction = shotDirection,
		Force = force,
		At = tick(),
	}
	-- ⚠️ "exatamente quando o pulso de chute sair" — avisa TODOS os
	-- inscritos NA HORA, síncrono (não task.spawn/defer), antes mesmo da
	-- bola sair do pé — pcall pra um listener com erro nunca travar o
	-- chute em si.
	for _, listener in ipairs(pulseShotFiredListeners) do
		local ok, err = pcall(listener, lastPulseShotInfo)
		if not ok then
			warn("[Pulso] um _G.RegisterPulseShotListener falhou: " .. tostring(err))
		end
	end

	local kicked = pulsePerformKick(player, targetPoint, force, effect.CurveMult, aimMult, effect, Config.PULSE_SHOT_FORCE_CAP_MULT)

	-- ⚠️ v11: VanishSeconds (Pulso "Sumiço", vindo de Kamikakushi/Teleport
	-- Shot — no anime a bola SOME na frente do goleiro e reaparece perto da
	-- rede). Some só depois de um tempinho de voo, senão o próprio chutador
	-- não vê a bola sair do pé. O restore guarda a transparência ORIGINAL de
	-- cada pedaço e roda mesmo se a bola for resetada no meio (gol, saída),
	-- pra nunca sobrar uma bola invisível em campo.
	if kicked and effect.VanishSeconds and effect.VanishSeconds > 0 then
		local vanishing = ball
		local duration = effect.VanishSeconds
		-- ⚠️ v113 — revisão pelo vídeo (Inazuma Eleven 3, "Teleport Shot/Kamikakushi",
		-- quadros a cada 0,2s): a bola some NA FRENTE DO GOLEIRO (30.0s), aparece um
		-- TORII com névoa roxa e um redemoinho em que ela gira (30.6-33.8s) e ela
		-- volta coberta de energia roxa (34.2s). Antes sumia 0.25s depois do chute,
		-- ainda perto do pé, e sem torii nenhum. Agora espera a bola chegar a ~38
		-- studs do gol (no máximo 1.2s de voo) e o torii aparece ali, pra todo mundo.
		local golAlvo = player.Team and enemyGoalOf(player.Team.Name)
		task.spawn(function()
			local t0 = tick()
			task.wait(0.15)
			while vanishing.Parent and tick() - t0 < 1.2 do
				if golAlvo and (vanishing.Position - golAlvo.Position).Magnitude < 38 then break end
				if owner then return end
				RunService.Heartbeat:Wait()
			end
			if owner or not vanishing or not vanishing.Parent then return end
			local dirVoo = vanishing.AssemblyLinearVelocity.Magnitude > 1 and vanishing.AssemblyLinearVelocity.Unit or Vector3.new(0, 0, -1)
			if player.Character then
				Config.DispararVFX("HissatsuVFX", player.Character, "Sumiço@torii", nil,
					{ Posicao = vanishing.Position, Dir = dirVoo, Duracao = duration })
			end
			local originals = { [vanishing] = vanishing.Transparency }
			vanishing.Transparency = 1
			for _, descendant in ipairs(vanishing:GetDescendants()) do
				if descendant:IsA("BasePart") or descendant:IsA("Decal") or descendant:IsA("Texture") then
					originals[descendant] = descendant.Transparency
					descendant.Transparency = 1
				end
			end
			task.delay(duration, function()
				for instance, transparency in pairs(originals) do
					if instance and instance.Parent then
						instance.Transparency = transparency
					end
				end
				-- reaparece coberta de energia roxa (34.2s do vídeo)
				if player.Character and vanishing.Parent then
					Config.DispararVFX("HissatsuVFX", player.Character, "Sumiço@volta", nil, { Posicao = vanishing.Position })
				end
			end)
		end)
	end

	return kicked
end

-- ⚠️ v8 PEDIDO: "instintos não são como o pulso" — chute de INSTINTO
-- (ex: Chute Direto) usa a força normal de Kick (sem fórmula de Hissatsu, sem
-- multiplicador de raridade, sem MaxRange, sem chip do zagueiro — isso
-- tudo é só do Pulso/Hissatsu), e vai pra pulsePerformKick com
-- useNormalArc=true (arco com gravidade normal, sem número de força
-- flutuando) — só pode ser defendido no dive normal, com QUALQUER
-- físico (ver lastShotWasInstinct/currentDangerForceRating acima).
_G.InstinctExecuteShot = function(player, effect)
	if isStunned(player) then return false end
	if owner ~= player then return false end
	local targetPoint = _G.PulseComputeShotTarget(player)
	if not targetPoint then return false end
	local force = Config.KICK_MAX_FORCE * getKickForceMultiplier(player) * (effect.ForceMult or 1)
	local aimMult = effect.AimDeviationMult
	if aimMult == nil then aimMult = 1 end
	return pulsePerformKick(player, targetPoint, force, effect.CurveMult, aimMult, effect, nil, true)
end

_G.PulseExecutePass = function(player, effect)
	if isStunned(player) then return false end
	if owner ~= player then return false end
	-- ⚠️ NOVO: Pulso do Passe Perfeito usa PerfectTargeting — trava no
	-- companheiro mais perto de onde a bola chegaria (ver
	-- _G.PulseComputeLandingTeammate acima), não no "mais aberto".
	local mate = effect.PerfectTargeting
		and _G.PulseComputeLandingTeammate(player)
		or _G.PulseComputeBestTeammate(player)
	if not mate then return false end
	local _, mateRoot = getCharacterParts(mate)
	if not mateRoot then return false end
	-- ⚠️ NOVO (Passe Perfeito — "é pra ser um passe com a força máxima do
	-- usuário"): AerialArc usa a MESMA força máxima de um chute a gol
	-- (Config.KICK_MAX_FORCE * multiplicador de Chute do jogador), não a
	-- força fraca de passe normal (Config.PASS_FORCE, pensada pra um
	-- toque curto no chão).
	local baseForce = effect.AerialArc
		and (Config.KICK_MAX_FORCE * getKickForceMultiplier(player))
		or Config.PASS_FORCE
	local force = baseForce * (effect.ForceMult or 1)
	local aimMult = effect.AimDeviationMult
	if aimMult == nil then aimMult = 1 end
	local ok = pulsePerformKick(player, mateRoot.Position, force, effect.CurveMult, aimMult, effect)
	if ok and effect.BuffTeammateDuration and effect.BuffTeammateForceMult and _G.SetPulseTeammateBuff then
		_G.SetPulseTeammateBuff(mate, effect.BuffTeammateForceMult, effect.BuffTeammateDuration)
	end
	-- ⚠️ v3: PassLockSeconds — registra a trava com o alvo QUE ESTE passe
	-- escolheu (só aqui dá pra saber quem foi), pra nenhum adversário
	-- interceptar o passe encostando na bola durante o voo.
	if ok and effect.PassLockSeconds and effect.PassLockSeconds > 0 then
		passLock = { Target = mate, Until = tick() + effect.PassLockSeconds }
	end
	return ok
end

_G.PulseExecuteSetPieceKick = function(player, effect)
	if isStunned(player) then return false end
	if not deadBallMode then return false end
	if owner ~= player then return false end
	local targetPoint = _G.PulseComputeShotTarget(player)
	if not targetPoint then
		local _, root = getCharacterParts(player)
		if not root then return false end
		targetPoint = root.Position + root.CFrame.LookVector * 30
	end
	local force = Config.SET_PIECE_AUTO_LAUNCH_FORCE * (effect.ForceMult or 1)
	return pulsePerformKick(player, targetPoint, force, effect.CurveMult, 1, effect)
end

_G.PulseExecuteHeader = function(player, effect)
	if isStunned(player) then return false end
	if not _G.PulseCanHeader(player, effect) then return false end
	local _, root = getCharacterParts(player)
	if not root then return false end

	if owner then releaseOwner() end
	recentKicker, recentKickTime = player, tick()
	kickerClearedBody = false -- ⚠️ v12: ver BODY_BLOCK
	hasBodyBlockedThisFlight = false -- ⚠️ v14: novo chute de verdade — libera o corpo pra absorver de novo (uma vez)
	startKickClearance(player) -- ⚠️ v20: sai atravessando qualquer coisa colada no corpo dele (ver startKickClearance)
	pushToucher(player)

	local direction = root.CFrame.LookVector
	local target = _G.PulseComputeShotTarget(player)

	-- ⚠️ v106 — XEQUE-MATE TELEGUIADO. PEDIDO: "o R do Xeque-Mate é pra ser
	-- teleguiado: se você estiver mirando errado, ele vai direto no gol, no
	-- ÂNGULO — ele mira pro ângulo pra você, por isso que ele é tão bom".
	-- Com effect.MiraNoAngulo o alvo vira o ângulo do gol adversário (perto do
	-- travessão, do lado MAIS LONGE do goleiro) e a bola corrige o rumo no voo.
	local anguloAlvo = nil
	if effect.MiraNoAngulo and player.Team then
		local gol = enemyGoalOf(player.Team.Name)
		if gol then
			local cf, sz = gol.CFrame, gol.Size
			-- eixo da LARGURA do gol = o maior eixo horizontal da caixa
			local eixo, meia = cf.RightVector, sz.X / 2
			if sz.Z > sz.X then eixo, meia = cf.LookVector, sz.Z / 2 end
			local baseY = gol.Position.Y - sz.Y / 2
			local altura = baseY + sz.Y * 0.72
			local cantos = {
				Vector3.new(gol.Position.X, altura, gol.Position.Z) + eixo * (meia - 3.5),
				Vector3.new(gol.Position.X, altura, gol.Position.Z) - eixo * (meia - 3.5),
			}
			-- goleiro adversário (humano na área ou o bot)
			local posGK = nil
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr.Team and plr.Team ~= player.Team and GKAreaUtil.IsEffectiveGK(plr) then
					local _, r = getCharacterParts(plr)
					if r then posGK = r.Position end
				end
			end
			if not posGK then
				for _, m in ipairs(workspace:GetChildren()) do
					if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" and m.Name ~= "GKBot_" .. player.Team.Name then
						local r = m:FindFirstChild("HumanoidRootPart")
						if r then posGK = r.Position end
					end
				end
			end
			anguloAlvo = cantos[1]
			if posGK and (cantos[2] - posGK).Magnitude > (cantos[1] - posGK).Magnitude then anguloAlvo = cantos[2] end
			target = anguloAlvo
		end
	end

	if target then
		local toTarget = target - ball.Position
		if toTarget.Magnitude > 0.01 then direction = toTarget.Unit end
	end
	local headerForce = Config.HEADER_FORCE * (effect.HeaderForceMult or 1)
	if not anguloAlvo then
		direction = applyAimDeviation(direction, getAimDeviationDegrees(player) * 0.5)
	end

	nudgeBallForwardForKick(direction) -- ⚠️ v21: já nasce fora do raio do corpo, na direção da cabeçada
	-- ⚠️ v21 FIX: removido o "ball.CanCollide = true" que existia aqui —
	-- ele cancelava na hora a janela de saída limpa (startKickClearance)
	-- aberta logo acima, então essa cabeçada de Pulso nunca se beneficiava dela.
	ball.AssemblyLinearVelocity = direction * headerForce + Vector3.new(0, anguloAlvo and 0 or (Config.HEADER_ELEVACAO or 8), 0) -- ⚠️ v105: sobe mais
	playKickFeedback(headerForce)
	playAnimation(player, Config.ANIMATIONS.Header, nil, nil, true) -- ⚠️ v65: cabeçada (normal e de Hissatsu passam as duas por aqui)
	if anguloAlvo then
		-- teleguiado: corrige o rumo até o ângulo (mesma velocidade), até
		-- chegar, alguém dominar, ou 2.5s
		local inicio = tick()
		local conexao
		conexao = RunService.Heartbeat:Connect(function()
			local v = ball.AssemblyLinearVelocity
			local falta = anguloAlvo - ball.Position
			if owner or ball.Anchored or tick() - inicio > 2.5 or falta.Magnitude < 3 or v.Magnitude < 5 then
				conexao:Disconnect()
				return
			end
			-- ⚠️ v108: correção mais suave (era 0.25) — "tá forte demais, nerfa um pouco"
			ball.AssemblyLinearVelocity = v:Lerp(falta.Unit * v.Magnitude, 0.14)
		end)
	end
	return true
end

-- ⚠️ NOVO (Pulso do Domínio Aéreo): pula e trava a bola no ar com os
-- pés — controle instantâneo de uma bola que ainda nem tocou o chão,
-- ignorando as restrições normais de recepção aérea (AERIAL_PICKUP_*,
-- que só valem devagar/sem sprintar) e mesmo sem ninguém ser dono ainda.
-- Reusa a mesma checagem "bola no ar por perto" que a cabeçada já usa
-- (_G.PulseCanHeader) como precondição — ver actionPrecheck em
-- PulseController.lua.
_G.PulseExecuteAerialControl = function(player, effect)
	if isStunned(player) then return false end
	if owner then return false end -- só bola SOLTA no ar — tirar de quem já controla é Tackle, não isso
	local _, root = getCharacterParts(player)
	if not root then return false end
	-- ⚠️ v120b — PEDIDO: "também é bom ter GRABS: pegar a bola no ar, tipo o Nagi —
	-- alguma arma do Nagi que domine no ar, que faça o trap do Nagi". Com RaioTrap
	-- (Domínio) o alcance é próprio (não o da cabeçada, que ficou menor): bola solta
	-- no ar a até RaioTrap na horizontal / AlturaTrap na vertical, até VelMaxTrap de
	-- velocidade — ela vem até o pé e gruda (com penas brancas, o motivo do Nagi).
	if effect and effect.RaioTrap then
		local rel = ball.Position - root.Position
		local horizontal = Vector3.new(rel.X, 0, rel.Z).Magnitude
		if horizontal > effect.RaioTrap or math.abs(rel.Y) > (effect.AlturaTrap or 12) then return false end
		if ball.AssemblyLinearVelocity.Magnitude > (effect.VelMaxTrap or 95) then return false end
		if rel.Y < 0.5 and ball.AssemblyLinearVelocity.Magnitude < 8 then return false end -- (bola parada no chão: é recepção normal)
		if Remotes.ArmaVFX and player.Character then
			Config.DispararVFX("ArmaVFX", player.Character, "Domínio@trap", nil, true, 0.8, { De = ball.Position })
		end
	elseif not _G.PulseCanHeader(player, effect) then
		return false
	end

	ball.CanCollide = true
	ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	ball.Position = root.Position + root.CFrame.LookVector * Config.DRIBBLE_OFFSET + Vector3.new(0, Config.DRIBBLE_HEIGHT_OFFSET, 0)

	setOwner(player)
	pushToucher(player)
	playAnimation(player, dribbleAnimationFor(nil), Enum.AnimationPriority.Action2, nil, true, nil, nil, "Dominio") -- ⚠️ v63: sem direção aqui (domínio), usa a neutra · v96: no animador por código é a pose de amortecer
	return true
end

_G.PulseExecuteTackle = function(player, effect, def)
	if isStunned(player) then return false end
	-- ⚠️ v110 — PEDIDO: "os tackles, todos, não precisam que você tenha outra
	-- pessoa na frente ou uma pessoa com a bola pra usar. Você pode usar em
	-- qualquer lugar. Ele vai na distância que precisa ir e faz o que ele faz —
	-- o de gelo vai lá, rouba a bola do cara e deixa ele paralisado. Só que ele
	-- vai na RETA onde o cara tá mirando, não exatamente no cara com a bola."
	-- Igual a Investida Titânica: um dash reto na direção da MIRA (a mesma do
	-- chute de Hissatsu), mais longo quanto maior o alcance da técnica
	-- (TackleRangeAdd). No primeiro adversário que encostar ele PARA — rouba a
	-- bola se estiver com ela — e a técnica acontece ali; sem ninguém no
	-- caminho, acontece no fim da reta. O efeito (gelo/pisão/clarão...) sai
	-- depois de def.ImpactoAtraso (o instante do golpe na animação).
	if def then
		if owner == player then return false end
		local _, root = getCharacterParts(player)
		if not root then return false end
		local direcao
		local mira = _G.GetPulseAimPoint and _G.GetPulseAimPoint(player)
		if typeof(mira) == "Vector3" and mira.X == mira.X then
			local plano = Vector3.new(mira.X - root.Position.X, 0, mira.Z - root.Position.Z)
			if plano.Magnitude > 1 then direcao = plano.Unit end
		end
		if not direcao then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			direcao = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
		end
		local extra = effect.TackleRangeAdd or 0
		local distancia = Config.TACKLE_DASH_FORCE * Config.TACKLE_DASH_DURATION + extra * 2
		local duracao = Config.TACKLE_DASH_DURATION + extra * 0.012
		-- ⚠️ v110 — PEDIDO: "faz do jeito que faz mais sentido no anime". Só a
		-- Rasteira e o Roubo Congelante são CARRINHO de verdade; as outras têm o
		-- deslocamento delas (def.Deslocamento):
		--   Carrinho — desliza (Killer Slide, Frozen Steal)
		--   Corrida  — corre de braços pra trás (Photon Flash)
		--   Salto    — salto em arco até o ponto e cai pisando (Snow Angel)
		--   Passo    — um passo curto e pisa ali (Super Shikofumi)
		--   Projetil — fica no lugar e a MEIA-LUA é que corre na mira (Spinning Cut)
		local modo = def.Deslocamento or "Carrinho"
		do -- não atravessa parede
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			params.RespectCanCollide = true
			local ignorar = { ball }
			for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then table.insert(ignorar, m) end
			end
			params.FilterDescendantsInstances = ignorar
			local hit = workspace:Raycast(root.Position, direcao * (distancia + 2), params)
			if hit then distancia = math.max(0, (hit.Position - root.Position).Magnitude - 2.5) end
		end
		local alcanceTotal = distancia
		if modo == "Passo" then
			distancia = math.min(distancia, 6)
			duracao = 0.22
		elseif modo == "Corrida" then
			duracao = duracao * 1.35
		elseif modo == "Salto" then
			duracao = 0.84 -- casa com a animação do Anjo da Neve (cai aos 0.84s)
		elseif modo == "Projetil" then
			distancia = 0
			duracao = 0.4 -- o chute giratório solta a meia-lua aos 0.4s
		end
		root.CFrame = CFrame.lookAt(root.Position, root.Position + direcao)
		local atraso = def.ImpactoAtraso or 0
		local agora = tick()
		local dash = {
			startPosition = root.Position,
			endPosition = root.Position + direcao * distancia,
			triggeredAt = agora,
			expiresAt = agora + duracao + atraso + 0.1,
			moveDuration = duracao,
			isPulseDash = true,
			hitboxRadius = Config.PULSE_TACKLE_HITBOX or 5.5,
			efeitoFixo = effect,
			multiAlvo = true,
			atingidos = {},
			resolved = false,
			arco = (modo == "Salto") and 7 or nil,                        -- sobe e desce no caminho
			semContato = (modo == "Salto" or modo == "Projetil") or nil,  -- não para no caminho
		}
		dash.aoChegar = function()
			dash.expiresAt = tick() + atraso + 0.1 -- fica no lugar enquanto o golpe acontece
			if modo == "Projetil" then
				-- a MEIA-LUA azul corre reta na mira; no primeiro adversário (ou no
				-- fim do alcance) sobe o MURO de fogo azul: joga longe quem estiver
				-- ali, e quem estava com a bola perde ela — que volta quicando pra
				-- quem usou (wiki: "the ball bounces back towards them")
				local _, r0 = getCharacterParts(player)
				if not r0 then return end
				local origem = r0.Position
				local VEL = 70
				if Remotes.HissatsuVFX and player.Character then
					Config.DispararVFX("HissatsuVFX", player.Character, def.Name, def.Element,
						{ Dir = direcao, Vel = VEL, Alcance = alcanceTotal })
				end
				local t0 = tick()
				local andado = 0
				local con
				con = RunService.Heartbeat:Connect(function()
					local antes = andado
					andado = math.min(alcanceTotal, (tick() - t0) * VEL)
					local a = origem + direcao * antes
					local b = origem + direcao * andado
					local atingido = false
					for _, other in ipairs(Players:GetPlayers()) do
						if other == player or not areOpponents(player, other) then continue end
						local _, oRoot = getCharacterParts(other)
						if not oRoot then continue end
						local pp = Vector3.new(oRoot.Position.X, a.Y, oRoot.Position.Z)
						local ab = b - a
						local u = ab.Magnitude > 0.001 and math.clamp((pp - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
						if (pp - (a + ab * u)).Magnitude <= 5 then atingido = true break end
					end
					if not atingido and andado < alcanceTotal then return end
					con:Disconnect()
					local ponto = origem + direcao * andado
					local corte = _G.RegistrarCorteAzul and _G.RegistrarCorteAzul(player, ponto, direcao, def.Element)
					if Remotes.HissatsuVFX and player.Character then
						Config.DispararVFX("HissatsuVFX", player.Character, def.Name .. "@muro", def.Element,
							{ Posicao = ponto, Dir = direcao, Duracao = corte and corte.Duracao, Largura = corte and corte.Largura, Altura = corte and corte.Altura })
					end
					local forca = effect.KnockbackForce or 55
					for _, other in ipairs(Players:GetPlayers()) do
						if other == player or not areOpponents(player, other) then continue end
						local _, oRoot = getCharacterParts(other)
						if not oRoot then continue end
						if Vector3.new(oRoot.Position.X - ponto.X, 0, oRoot.Position.Z - ponto.Z).Magnitude > (effect.KnockbackRadius or 12) then continue end
						if owner == other and not GKAreaUtil.IsEffectiveGK(other) and not (_G.HasPulseIframe and _G.HasPulseIframe(other)) then
							releaseOwner()
							ball.CanCollide = true
							tackleSound:Play()
							local _, meu = getCharacterParts(player)
							local volta = meu and (meu.Position - ball.Position) or -direcao
							volta = Vector3.new(volta.X, 0, volta.Z)
							volta = volta.Magnitude > 0.1 and volta.Unit or -direcao
							ball.AssemblyLinearVelocity = volta * 38 + Vector3.new(0, 18, 0)
							if _G.RegisterTackle then _G.RegisterTackle(player, other) end
						end
						oRoot.AssemblyLinearVelocity += direcao * forca + Vector3.new(0, forca * 0.35, 0)
						stunPlayer(other, 0.8)
					end
				end)
				return
			end
			if Remotes.HissatsuVFX and player.Character then
				Config.DispararVFX("HissatsuVFX", player.Character, def.Name, def.Element)
			end
			task.delay(atraso, function()
				if not player.Parent then return end
				local _, r = getCharacterParts(player)
				if not r then return end
				-- quem estava com a bola ali perto perde ela (o pisão/clarão/gelo
				-- pega quem está no raio, não só quem o corpo encostou)
				local alcanceRoubo = Config.PULSE_TACKLE_HITBOX_ROUBO or 9
				if owner and owner ~= player and areOpponents(player, owner) and not GKAreaUtil.IsEffectiveGK(owner)
					and not (_G.HasPulseIframe and _G.HasPulseIframe(owner)) then
					local _, oRoot = getCharacterParts(owner)
					if oRoot and (oRoot.Position - r.Position).Magnitude <= alcanceRoubo then
						local vitima = owner
						releaseOwner()
						ball.CanCollide = true
						tackleSound:Play()
						setOwner(player)
						stunPlayer(vitima, Config.TACKLE_VICTIM_STUN)
						if _G.RegisterTackle then _G.RegisterTackle(player, vitima) end
					end
				end
				if effect.StunRadius and effect.StunDuration and _G.PulseApplyAreaStun then
					_G.PulseApplyAreaStun(player, effect.StunRadius, effect.StunDuration)
				end
				if effect.FreezeRadius and effect.FreezeDuration and _G.PulseApplyAreaFreeze then
					_G.PulseApplyAreaFreeze(player, effect.FreezeRadius, effect.FreezeDuration)
				end
				-- ⚠️ v113: Clarão de Fótons só cega (tela branca), num raio enorme
				if effect.Cegueira and _G.PulseAplicarCegueira then
					_G.PulseAplicarCegueira(player, r.Position, effect.Cegueira.Raio, effect.Cegueira.Duracao)
				end
				if effect.KnockbackRadius and effect.KnockbackForce and _G.PulseApplyAreaKnockback then
					_G.PulseApplyAreaKnockback(player, effect.KnockbackRadius, effect.KnockbackForce)
				end
				if effect.RagdollRadius and effect.RagdollDuration then
					for _, other in ipairs(Players:GetPlayers()) do
						if other == player or not areOpponents(player, other) then continue end
						local _, otherRoot = getCharacterParts(other)
						if otherRoot and (otherRoot.Position - r.Position).Magnitude <= effect.RagdollRadius then
							ragdollPlayer(other, effect.RagdollDuration)
						end
					end
				end
			end)
		end
		tackleDashes[player] = dash
		if modo == "Carrinho" then
			avisarAcao(player.Character, "Tackle", duracao)
		elseif modo == "Corrida" then
			avisarAcao(player.Character, "CorridaHissatsu", duracao)
		end -- (Salto/Projetil: a animação da técnica toca já no início, pelo VFX)
		Remotes.SuppressShiftLockRotation:FireClient(player, duracao + atraso)
		if Remotes.HissatsuVFX and player.Character then
			Config.DispararVFX("HissatsuVFX", player.Character, def.Name .. "@inicio", def.Element, { Duracao = duracao, Dir = direcao })
		end
		return true
	end
	-- ⚠️ v43: respeita o alcance extra da habilidade (ver TackleRangeAdd).
	if not _G.PulseHasOpponentInTackleRange(player, effect.TackleRangeAdd) then return false end
	-- ⚠️ v67: goleiro na própria área não perde a bola pra ninguém — nem por
	-- Hissatsu. Esta Hissatsu de Tackle rouba DIRETO, sem passar pelo
	-- resolveStealAttempt (onde a mesma regra está), então precisa da
	-- checagem aqui também, senão sobraria justamente este buraco.
	if owner and GKAreaUtil.IsEffectiveGK(owner) then
		stunPlayer(player, Config.TACKLE_STUN_ON_FAILED_TIMING)
		return false
	end
	-- ⚠️ v3: alvo com iframe de Pulso não pode ser desarmado — nem por um
	-- carrinho automático de Pulso (mesma regra de resolveStealAttempt).
	if owner and _G.HasPulseIframe and _G.HasPulseIframe(owner) then
		stunPlayer(player, Config.TACKLE_STUN_ON_FAILED_TIMING)
		return false
	end

	local target = owner
	noStunOnFail[player] = effect.NoStunOnFail or false
	task.delay(2, function() noStunOnFail[player] = nil end)

	playAnimation(player, Config.ANIMATIONS.Tackle, nil, Config.TACKLE_DASH_DURATION)

	local stolenFrom = target
	releaseOwner()
	ball.CanCollide = true
	tackleSound:Play()
	setOwner(player)
	stunPlayer(stolenFrom, Config.TACKLE_VICTIM_STUN)
	avisarAcao(stolenFrom.Character, "SofreuCarrinho", Config.TACKLE_VICTIM_STUN) -- ⚠️ v106: cai no chão e levanta
	if _G.RegisterTackle then _G.RegisterTackle(player, stolenFrom) end
	return true
end

_G.PulseExecuteDribbleMove = function(player, effect)
	if isStunned(player) then return false end
	if owner ~= player then return false end
	if GKAreaUtil.IsEffectiveGK(player) then return false end

	local _, root = getCharacterParts(player)
	if not root then return false end

	-- Resolve a direção sozinho a partir do WalkDirection atual (ou
	-- LookVector se parado) — mapeia pro mais perto de Left/Back/Right,
	-- igual o sistema manual de Z/X/C já faz.
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local moveDir = humanoid and humanoid.MoveDirection or Vector3.zero
	local reference = moveDir.Magnitude > 0.1 and moveDir.Unit or root.CFrame.LookVector

	local candidates = {
		Left = -root.CFrame.RightVector,
		Right = root.CFrame.RightVector,
		Back = -root.CFrame.LookVector,
		Forward = root.CFrame.LookVector, -- ⚠️ v86: drible pra frente também existe (Back ao contrário)
	}
	local bestName, bestDot = "Back", -math.huge
	for name, vec in pairs(candidates) do
		local dot = reference:Dot(vec)
		if dot > bestDot then bestDot = dot; bestName = name end
	end
	local direction = candidates[bestName]

	dribbleMoveCooldowns[player] = tick()

	local skill = getDribbleSkill(player)
	-- ⚠️ v7: DistanceMult — Hissatsus de drible (ver PulseInstinctData.luau,
	-- seção DRIBLE) escalam a distância da finta em cima da distância
	-- normal (que já depende do DribbleSkill do jogador); sem a chave =
	-- 1x (nenhum Pulso de drible usa isso ainda além dos novos 5).
	-- ⚠️ v104: Hissatsu de drible mantém o alcance longo (a finta normal virou só rolamento)
	local minD = Config.DRIBBLE_HISSATSU_MIN_DISTANCE or Config.DRIBBLE_MOVE_MIN_DISTANCE
	local maxD = Config.DRIBBLE_HISSATSU_MAX_DISTANCE or Config.DRIBBLE_MOVE_MAX_DISTANCE
	local distance = (minD + (maxD - minD) * skill) * (effect.DistanceMult or 1)
	local window = Config.DRIBBLE_ANIMATION_SECONDS -- ⚠️ v64: janela FIXA (= tempo da animação); a distância é que escala, logo a velocidade escala junto

	playDribbleAnimation(player, bestName, window) -- ⚠️ v63: reprodução ajustada à janela; v86: Forward = Back ao contrário

	local rangeBonus = (effect.AnkleRangeAdd or 0)
		+ (_G.GetPulseActiveAnkleRangeAdd and _G.GetPulseActiveAnkleRangeAdd(player) or 0)
	local stunBonus = effect.AnkleStunAdd or 0
	local hitOpponent = applyAnkleBreaker(player, root, rangeBonus, stunBonus, effect.AlwaysStun)
	local dashDistance = getMinidashBonusDistance(hitOpponent, skill)

	-- ⚠️ v86: mesmo esquema da finta manual — o cliente desloca, sem travar.
	local offset = direction * (distance + dashDistance)
	local endPosition = root.Position + offset
	dribbleMoves[player] = {
		targetPosition = endPosition,
		startPosition = root.Position,
		endPosition = endPosition,
		offset = offset,
		triggeredAt = tick(),
		expiresAt = tick() + window,
	}
	setIframeGlow(player, true)
	sendDisplacement(player, offset, window)
	return true
end

-- ================================================================
-- ⚠️ EFEITOS DE ÁREA E ÍMÃ DE BOLA (chaves novas da v3)
-- ================================================================
-- Chamados pelo PulseController no resolveAndExecute, logo depois da
-- ação principal do Pulso — valem pra QUALQUER Action (um chute pode
-- stunar quem está em volta, um carrinho pode empurrar, etc). Todos
-- respeitam time: NUNCA acertam companheiro.

-- StunRadius + StunDuration: stun em todos os ADVERSÁRIOS dentro do
-- raio, medido a partir do próprio jogador.
_G.PulseApplyAreaStun = function(player, radius, duration)
	if not radius or radius <= 0 or not duration or duration <= 0 then return end
	local _, root = getCharacterParts(player)
	if not root then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player then continue end
		if not areOpponents(player, plr) then continue end -- nunca em cima de companheiro
		local _, otherRoot = getCharacterParts(plr)
		if not otherRoot then continue end
		if (otherRoot.Position - root.Position).Magnitude <= radius then
			stunPlayer(plr, duration)
			if _G.MostrarTontura then _G.MostrarTontura(plr, duration) end -- ⚠️ v120b: tontura onde atordoa
		end
	end
end

-- FreezeRadius + FreezeDuration: mesma ideia do StunRadius acima, só que
-- CONGELA (ver freezePlayer) em vez de atordoar — pulos de gelo (ex: Fúria
-- Glacial) usam essa chave em vez de StunRadius/StunDuration.
_G.PulseApplyAreaFreeze = function(player, radius, duration)
	if not radius or radius <= 0 or not duration or duration <= 0 then return end
	local _, root = getCharacterParts(player)
	if not root then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player then continue end
		if not areOpponents(player, plr) then continue end -- nunca em cima de companheiro
		local _, otherRoot = getCharacterParts(plr)
		if not otherRoot then continue end
		if (otherRoot.Position - root.Position).Magnitude <= radius then
			freezePlayer(plr, duration)
		end
	end
end

-- KnockbackRadius + KnockbackForce: empurra os ADVERSÁRIOS dentro do
-- raio pra LONGE do jogador (impulso direto na AssemblyLinearVelocity do
-- HumanoidRootPart deles, com um componente vertical pequeno pra
-- "descolar" do chão e o empurrão ser visível).
local KNOCKBACK_VERTICAL_FRACTION = 0.35
_G.PulseApplyAreaKnockback = function(player, radius, force)
	if not radius or radius <= 0 or not force or force <= 0 then return end
	local _, root = getCharacterParts(player)
	if not root then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == player then continue end
		if not areOpponents(player, plr) then continue end -- nunca em cima de companheiro
		local _, otherRoot = getCharacterParts(plr)
		if not otherRoot then continue end

		local away = otherRoot.Position - root.Position
		local horizontal = Vector3.new(away.X, 0, away.Z)
		if horizontal.Magnitude > radius then continue end
		-- Exatamente em cima do jogador (distância ~0): empurra pra frente
		-- dele, senão não daria pra normalizar a direção.
		local direction = horizontal.Magnitude > 0.05 and horizontal.Unit or root.CFrame.LookVector
		otherRoot.AssemblyLinearVelocity = otherRoot.AssemblyLinearVelocity
			+ direction * force
			+ Vector3.new(0, force * KNOCKBACK_VERTICAL_FRACTION, 0)
	end
end

-- BallMagnetRadius: ação INSTANTÂNEA (Pulso do Primeiro Toque) — se a
-- bola estiver SOLTA (sem dono nenhum) dentro do raio, ela é puxada pro
-- jogador e ele fica com a posse ao alcance. Se a bola estiver COM
-- alguém, não faz nada: isso não é um roubo (pra isso existe Steal/
-- Tackle).
local BALL_MAGNET_SPEED = 55 -- studs/s apontados pro jogador — forte o bastante pra chegar rápido de qualquer ponto do raio
_G.PulseExecuteBallMagnet = function(player, effect)
	if isStunned(player) then return false end
	local radius = effect and effect.BallMagnetRadius
	if not radius or radius <= 0 then return false end
	if owner then return false end -- bola com alguém (inclusive com o próprio jogador): não faz nada

	local _, root = getCharacterParts(player)
	if not root then return false end

	local toPlayer = root.Position - ball.Position
	if toPlayer.Magnitude > radius then return false end

	passLock = nil -- puxar a bola pro pé cancela qualquer trava de passe pendente
	ball.CanCollide = true
	if toPlayer.Magnitude > 0.05 then
		ball.AssemblyLinearVelocity = toPlayer.Unit * BALL_MAGNET_SPEED
	end
	-- Posse na hora: o loop de drible já reposiciona a bola nos pés no
	-- próximo Heartbeat, então a velocidade acima é só o "puxão" visual.
	setOwner(player)
	return true
end

Players.PlayerRemoving:Connect(function(player)
	tackleDashes[player] = nil
	dribbleMoveCooldowns[player] = nil
	dribbleMoves[player] = nil
	headerCooldowns[player] = nil
	tackleCooldowns[player] = nil
	ownerLastFacing[player] = nil
	ownerExposed[player] = nil
	loadedAnimationTracks[player] = nil
	stunnedUntil[player] = nil
	preStunWalkSpeed[player] = nil
	lastReceiveTime[player] = nil
	noStunOnFail[player] = nil
	diving[player] = nil
	gkActionCooldowns[player] = nil
	bodyBlockDebounce[player] = nil
	ragdollState[player] = nil -- personagem some junto (character:Destroy), não precisa restaurar Motor6D
	pulseIframe[player] = nil -- ⚠️ v3
	if passLock and passLock.Target == player then passLock = nil end -- ⚠️ v3: alvo do passe saiu, destrava a bola
	if pendingLooseTackle and pendingLooseTackle.player == player then
		pendingLooseTackle = nil
	end
	if owner == player then
		releaseOwner()
	end
end)

print("✅ BallController carregado.")

-- ⚠️ v108 — METAVISÃO: "saber exatamente, a cada tick, aonde o jogador que está
-- com a bola está olhando — uma linha reta fina até o final — pra interceptar
-- (meta pra goleiro)". A mira só existe no cliente de quem chuta; ele manda
-- ~10x/s enquanto tem a posse e aqui vira o atributo MiraBola (replica sozinho).
-- Dentro de do...end: este script está no limite de 200 locals no topo.
do
	-- v110: o GKBot precisa saber se uma Hissatsu está voando (não "afasta" ela)
	_G.PulseEmVooReto = function() return pulseStraightFlightActive end
	Remotes.MiraDoDono.OnServerEvent:Connect(function(player, ponto)
		if typeof(ponto) ~= "Vector3" or ponto ~= ponto or owner ~= player then return end
		player:SetAttribute("MiraBola", ponto)
	end)
	-- ⚠️ v109: caminho rápido, todo quadro — repassa na hora pra todo mundo
	Remotes.MiraDoDonoU.OnServerEvent:Connect(function(player, ponto)
		if typeof(ponto) ~= "Vector3" or ponto ~= ponto or owner ~= player then return end
		Remotes.MiraDoDonoU:FireAllClients(player, ponto)
	end)
end

-- ⚠️ v108 — DEFESA INSTANTÂNEA CONTRA CHUTE NORMAL. PEDIDO: "Hissatsus de
-- defesa e de gol tiram a bola que for chutada. Se uma bola for chutada numa
-- Hissatsu de gol, ele pega instantaneamente — roda a cutscene da Hissatsu, mas
-- a bola simplesmente para na mão dele e nem precisa do QTE. E a do defensor
-- também: a bola para onde for, no ar — a da barreira para na barreira."
-- Hissatsu x Hissatsu continua no duelo com QTE (Heartbeat de colisão acima,
-- que só age com pulseStraightFlightActive). Aqui é só chute comum.
-- (numa função própria: dentro de do...end os locals ainda contam no limite de 200 do topo)
;(function()
	local DUR_CUTSCENE = 1.8
	local VEL_MINIMA = 18
	local bloqueadoNoChute = nil -- recentKickTime do chute já parado pela barreira

	RunService.Heartbeat:Connect(function()
		if pulseStraightFlightActive or ballFrozenForGuardQTE or owner then return end
		if not recentKicker then return end
		local vel = ball.AssemblyLinearVelocity
		if vel.Magnitude < VEL_MINIMA then return end

		-- 1) goleiro com a guarda de Hissatsu armada: pega na hora
		for _, player in ipairs(Players:GetPlayers()) do
			if guardResolving[player] then continue end
			if not areOpponents(recentKicker, player) then continue end
			local guard = _G.GetGKGuard and _G.GetGKGuard(player)
			if not guard then continue end
			local ownGoal = player.Team and ownGoalOf(player.Team.Name)
			local _, root = getCharacterParts(player)
			if not ownGoal or not root then continue end
			local guardWidth = getGoalWidth(ownGoal) * (guard.GuardSize or 0.5)
			local guardHeight = math.max(ownGoal.Size.Y * 0.95, guardWidth * 0.4)
			local horizontal = (Vector3.new(ball.Position.X, 0, ball.Position.Z) - Vector3.new(root.Position.X, 0, root.Position.Z)).Magnitude
			if horizontal > guardWidth / 2 then continue end
			if ball.Position.Y - root.Position.Y > guardHeight + 2 then continue end

			local def = _G.ConsumirGuardaSemQTE and _G.ConsumirGuardaSemQTE(player)
			if not def then continue end
			guardResolving[player] = true
			ballFrozenForGuardQTE = true
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.AssemblyAngularVelocity = Vector3.zero
			ball.Anchored = true
			ball.CanCollide = false
			if _G.TocarCutsceneDeDefesa then _G.TocarCutsceneDeDefesa(player.Character, def, DUR_CUTSCENE) end
			if Config.PULSE_FORCE_DEBUG_PRINTS then
				print(string.format("🧤 [Defesa] %s pegou o chute comum de %s com %s (sem QTE)", player.Name, recentKicker.Name, def.Name))
			end
			task.delay(DUR_CUTSCENE, function()
				ball.Anchored = false
				ball.CanCollide = true
				ballFrozenForGuardQTE = false
				guardResolving[player] = false
				local _, r = getCharacterParts(player)
				local efeito = def.Perfect or def.Bom
				if efeito and efeito.Rebate and r then
					-- Soco Explosivo: soca a bola de volta pro campo
					local away = r.Position - ownGoal.Position
					away = Vector3.new(away.X, 0, away.Z)
					away = (away.Magnitude > 0.1) and away.Unit or r.CFrame.LookVector
					ball.Position = r.Position + away * 3 + Vector3.new(0, 2, 0)
					ball.AssemblyLinearVelocity = away * Config.GK_PUNCH_REBOUND_FORCE + Vector3.new(0, 16, 0)
				elseif player.Character then
					setOwner(player)
				end
				if _G.RegisterSave then _G.RegisterSave(player) end
			end)
			return
		end

		-- 2) barreira de defensor (Muralha Infinita / GetPulseBlock): a bola para no ar
		if _G.GetPulseBlock and bloqueadoNoChute ~= recentKickTime then
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr == recentKicker or not areOpponents(recentKicker, plr) then continue end
				local radius = _G.GetPulseBlock(plr)
				if not radius then continue end
				-- ⚠️ v120b: a Muralha conta pela CAIXA do muro (ver _G.DentroDaBarreira)
				if _G.DentroDaBarreira and _G.DentroDaBarreira(plr, ball.Position, ball.Size.X / 2) then
					if _G.MuroDaBarreira and _G.MuroDaBarreira(plr) and Remotes.HissatsuVFX and plr.Character then
						Config.DispararVFX("HissatsuVFX", plr.Character, "Muralha Infinita@impacto", "Natureza", { Posicao = ball.Position })
					end
					bloqueadoNoChute = recentKickTime
					ball.AssemblyLinearVelocity = Vector3.zero
					ball.AssemblyAngularVelocity = Vector3.zero
					if Config.PULSE_FORCE_DEBUG_PRINTS then
						print(string.format("🧱 [Defesa] barreira de %s parou o chute comum de %s", plr.Name, recentKicker.Name))
					end
					return
				end
			end
		end
	end)
end)()

-- ⚠️ v120b — COUNTER DO CHUTE (Última Barreira): chute de adversário (não Hissatsu
-- em voo — essa vai pro duelo) passando perto de quem tem a arma pronta, no campo
-- dele e indo pro gol dele: bloqueia no peito e a posse é dele.
;(function()
	RunService.Heartbeat:Connect(function()
		if owner or not recentKicker or pulseStraightFlightActive or ballFrozenForGuardQTE or deadBallMode then return end
		if tick() - recentKickTime > 3 then return end
		local v = ball.AssemblyLinearVelocity
		if v.Magnitude < 30 or not _G.UsarCounterDaArma then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == recentKicker or not areOpponents(recentKicker, plr) or isStunned(plr) then continue end
			if GKAreaUtil.IsEffectiveGK(plr) then continue end
			local equipadas = _G.GetEquippedInstincts and _G.GetEquippedInstincts(plr) or {}
			local tem = false
			for _, n in ipairs(equipadas) do if n == "Última Barreira" then tem = true break end end
			if not tem then continue end
			local _, r = getCharacterParts(plr)
			local golDele = r and plr.Team and ownGoalOf(plr.Team.Name)
			if not golDele then continue end
			local rel = ball.Position - r.Position
			if Vector3.new(rel.X, 0, rel.Z).Magnitude > 7 or math.abs(rel.Y) > 6 then continue end
			if (golDele.Position - ball.Position):Dot(v) <= 0 then continue end -- só chute indo pro gol dele
			if attackingHalfOf(plr.Team.Name, r.Position) then continue end -- só no próprio campo
			local efeito = _G.UsarCounterDaArma(plr, "Última Barreira")
			if efeito then
				ball.AssemblyLinearVelocity = Vector3.zero
				ball.AssemblyAngularVelocity = Vector3.zero
				ball.CanCollide = true
				setOwner(plr)
				if Remotes.ArmaVFX and plr.Character then
					Config.DispararVFX("ArmaVFX", plr.Character, "Última Barreira@contra", nil, true, 0.8, { Ponto = ball.Position })
				end
				return
			end
		end
	end)
end)()

-- ⚠️ v120b — O MURO AZUL DO CORTE GIRATÓRIO FICA DE PÉ. PEDIDO: "o match cutting
-- (aquele corte azul no meio): faz ele durar mais tempo, porque se a bola bater
-- nele vai diminuir a velocidade da bola — sem animação nenhuma, bateu, tira uns
-- 40-50 de força; e claro, escala com o elemento, a vantagem. É difícil de acertar:
-- pode aumentar um pouco o tamanho." O muro fica CORTE_DURACAO segundos onde a
-- meia-lua parou; a bola que cruzar a caixa dele perde CORTE_FORCA (×0.8-1.2 pela
-- vantagem do elemento do chute contra o elemento do corte), uma vez por chute.
;(function()
	local CORTE_DURACAO, CORTE_LARGURA, CORTE_ALTURA, CORTE_ESPESSURA = 3.5, 16, 10, 2.5
	local CORTE_FORCA = 45
	local cortes = {}
	_G.RegistrarCorteAzul = function(dono, ponto, direcao, elemento)
		local base = Vector3.new(ponto.X, ponto.Y, ponto.Z)
		local centro = base + Vector3.new(0, CORTE_ALTURA / 2 - 3, 0) -- (ponto = altura do quadril; chão ~3 abaixo)
		local c = {
			CFrame = CFrame.lookAt(centro, centro + direcao), Dono = dono, Elemento = elemento,
			Ate = tick() + CORTE_DURACAO, Chutes = {},
			Duracao = CORTE_DURACAO, Largura = CORTE_LARGURA, Altura = CORTE_ALTURA,
		}
		table.insert(cortes, c)
		return c
	end
	RunService.Heartbeat:Connect(function()
		if #cortes == 0 then return end
		local agora = tick()
		for i = #cortes, 1, -1 do
			if agora >= cortes[i].Ate then table.remove(cortes, i) end
		end
		if owner or not recentKicker then return end
		local v = ball.AssemblyLinearVelocity
		if v.Magnitude < 10 then return end
		for _, c in ipairs(cortes) do
			if c.Chutes[recentKickTime] then continue end
			if c.Dono and recentKicker and not areOpponents(c.Dono, recentKicker) then continue end -- (não atrapalha o próprio time)
			local rel = c.CFrame:PointToObjectSpace(ball.Position)
			local folga = ball.Size.X / 2
			if math.abs(rel.X) <= CORTE_LARGURA / 2 + folga and math.abs(rel.Y) <= CORTE_ALTURA / 2 + folga
				and math.abs(rel.Z) <= CORTE_ESPESSURA / 2 + folga + 1 then
				c.Chutes[recentKickTime] = true
				local elementoChute = recentKicker and recentKicker:GetAttribute(Config.ELEMENT_ATTRIBUTE_NAME or "Element")
				-- vantagem do CORTE (defesa) sobre o chute: tira mais; desvantagem: tira menos
				local mult = Config.MultElementalDaDefesa and Config.MultElementalDaDefesa(elementoChute, c.Elemento) or 1
				local tirar = CORTE_FORCA * mult
				local rapidez = v.Magnitude
				local nova = math.max(rapidez - tirar, 12)
				local razao = nova / rapidez
				ball.AssemblyLinearVelocity = v * razao
				if pulseStraightFlightActive then
					if pulseFlightVelocidade then pulseFlightVelocidade *= razao end
					pulseFlightExternalMult *= razao
				end
				if Config.PULSE_FORCE_DEBUG_PRINTS then
					print(string.format("🌀 [Corte] o muro azul de %s tirou %.0f de força (x%.2f elemento)", c.Dono and c.Dono.Name or "?", tirar, mult))
				end
			end
		end
	end)
end)()

-- ⚠️ v110 — REDE DE SEGURANÇA CONTRA BOLA NaN. PEDIDO: "a bola sumiu de novo".
-- Qualquer conta que gere NaN/infinito na velocidade ou na posição manda a bola
-- pro nada (some da tela e ninguém mais acha). Todo quadro: se a bola ficou
-- inválida, volta pro último lugar válido, parada, e avisa no Output.
;(function()
	local ultimoValido = ball.CFrame
	local function invalido(v)
		return v.X ~= v.X or v.Y ~= v.Y or v.Z ~= v.Z
			or math.abs(v.X) > 1e5 or math.abs(v.Y) > 1e5 or math.abs(v.Z) > 1e5
	end
	RunService.Heartbeat:Connect(function()
		if not ball.Parent then return end
		-- ⚠️ v110 — PEDIDO: "a bola sumiu e não apareceu no centro, na hora que o GK
		-- foi arremessar". Com a posse a física da bola vai pro CLIENTE do dono
		-- (BolaNosPes). Quando o goleiro agarra, a bola fica ANCORADA — e peça
		-- ancorada não troca de dono de rede, então a devolução pro servidor
		-- falhava; no arremesso ela voltava pra propriedade AUTOMÁTICA (o jogador
		-- mais perto) e o cliente dele passava a escrever a bola — até o resgate
		-- pro centro era sobrescrito. Regra: bola SEM DONO = física do servidor.
		if owner == nil and not ball.Anchored then
			local okDono, donoRede = pcall(function() return ball:GetNetworkOwner() end)
			if okDono and donoRede ~= nil then
				pcall(function() ball:SetNetworkOwner(nil) end)
			end
		end
		local pos, vel = ball.Position, ball.AssemblyLinearVelocity
		if invalido(pos) or invalido(vel) or invalido(ball.AssemblyAngularVelocity) then
			warn(("⚠️ BallController: bola ficou INVÁLIDA (pos %s, vel %s) — restaurada no último ponto válido"):format(tostring(pos), tostring(vel)))
			if not ball.Anchored then pcall(function() ball:SetNetworkOwner(nil) end) end
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.AssemblyAngularVelocity = Vector3.zero
			ball.CFrame = ultimoValido + Vector3.new(0, 1, 0)
			return
		end
		ultimoValido = ball.CFrame
	end)
	-- ⚠️ v110 (bateria da noite): a bola SUMIU de vez (Parent = nil) duas vezes
	-- logo depois do arremesso do goleiro bot — o Roblox apaga sozinho uma
	-- peça que a física manda pra posição infinita, e isso acontece DENTRO do
	-- passo de física, antes do Heartbeat acima conseguir consertar. Então
	-- confere também ANTES da física (Stepped): valor inválido volta pro
	-- último ponto bom, e velocidade absurda (nenhum chute passa de ~700
	-- studs/s) é limitada em vez de deixar a física explodir.
	local VEL_MAX, GIRO_MAX = 1500, 400
	RunService.Stepped:Connect(function()
		if not ball.Parent or ball.Anchored then return end
		local pos, vel, giro = ball.Position, ball.AssemblyLinearVelocity, ball.AssemblyAngularVelocity
		if invalido(pos) or invalido(vel) or invalido(giro) then
			warn(("⚠️ BallController: bola INVÁLIDA antes da física (pos %s, vel %s, giro %s) — restaurada"):format(tostring(pos), tostring(vel), tostring(giro)))
			pcall(function() ball:SetNetworkOwner(nil) end)
			ball.AssemblyLinearVelocity = Vector3.zero
			ball.AssemblyAngularVelocity = Vector3.zero
			ball.CFrame = ultimoValido + Vector3.new(0, 1, 0)
			return
		end
		if vel.Magnitude > VEL_MAX then
			warn(("⚠️ BallController: velocidade absurda na bola (%.0f studs/s) — limitada a %d"):format(vel.Magnitude, VEL_MAX))
			ball.AssemblyLinearVelocity = vel.Unit * VEL_MAX
		end
		if giro.Magnitude > GIRO_MAX then
			ball.AssemblyAngularVelocity = giro.Unit * GIRO_MAX
		end
	end)
end)()


-- ============================================================
-- ⚠️ v111 — ARMAS COM USO DE VERDADE. PEDIDO: "faça todas as armas
-- funcionar... a arma do Sae e do Rin não tá claro como usa, tem que andar pro
-- lado e às vezes buga. Tem muitas armas de status — tem que ter utilidade
-- diversa: um drible criativo, um drible que vai mais longe (o Monstro do
-- Drible pode ser isso)... só não pode ser um chute picudo igual Hissatsu."
-- Tudo aqui dentro de uma FUNÇÃO própria: um do...end não basta — os locals
-- dele ainda contam no limite de 200 registradores do script principal.
-- As ativas são chamadas pelo InstinctController como _G.ArmaAtiva_<Nome>
-- (AtivaAction da Arma) e devolvem true ou (false, "motivo pro HUD").
-- ============================================================
;(function()
	local function plano(v, fallback)
		local p = Vector3.new(v.X, 0, v.Z)
		if p.Magnitude > 0.05 then return p.Unit end
		return fallback
	end

	local function paramsSemGente()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local ignorar = { ball }
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m:FindFirstChildOfClass("Humanoid") then table.insert(ignorar, m) end
		end
		params.FilterDescendantsInstances = ignorar
		return params
	end

	-- quanto dá pra andar nessa direção sem atravessar parede/barreira
	local function alcanceLivre(origem, dir, dist)
		local hit = workspace:Raycast(origem, dir * (dist + 2.5), paramsSemGente())
		if hit then return math.max(0, (hit.Position - origem).Magnitude - 2.5) end
		return dist
	end

	local function vfx(player, nome, extra, dur)
		if Remotes.ArmaVFX and player.Character then
			Config.DispararVFX("ArmaVFX", player.Character, nome, nil, true, dur or 1, extra)
		end
	end
	-- ⚠️ v120b — PEDIDO: "o efeito do cara ficando tonto (do Chapéu) coloca em outros
	-- lugares que deixam atordoado". Estrelinhas girando na cabeça de quem ficou tonto.
	_G.MostrarTontura = function(alvo, dur)
		if typeof(alvo) ~= "Instance" or not alvo:IsA("Player") or not alvo.Character then return end
		vfx(alvo, "Tontura", { Alvo = alvo.Character, Tempo = dur or 1.5 }, dur or 1.5)
	end

	local function direcaoDaMira(player, root)
		local mira = _G.GetPulseAimPoint and _G.GetPulseAimPoint(player)
		if typeof(mira) == "Vector3" and mira == mira then
			local d = plano(mira - root.Position, nil)
			if d then return d, mira end
		end
		return plano(root.CFrame.LookVector, Vector3.new(0, 0, -1)), nil
	end

	local function adversarioComBola(player, raio)
		if not owner or owner == player or not areOpponents(player, owner) then return nil end
		local _, r = getCharacterParts(owner)
		local _, meu = getCharacterParts(player)
		if not r or not meu or (r.Position - meu.Position).Magnitude > raio then return nil end
		return owner, r
	end

	-- adversários (jogadores + goleiro bot) — obstáculos da curva
	local function obstaculos(player)
		local lista = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= player and areOpponents(player, plr) then
				local _, r = getCharacterParts(plr)
				if r then table.insert(lista, r.Position) end
			end
		end
		for _, m in ipairs(workspace:GetChildren()) do
			if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" and not (player.Team and m.Name == "GKBot_" .. player.Team.Name) then
				local r = m:FindFirstChild("HumanoidRootPart")
				if r then table.insert(lista, r.Position) end
			end
		end
		return lista
	end

	-- solta a bola do pé na direção de `alvo` (passe/tabela) com a física
	-- de um chute normal (trava de corpo, auto-repossessão, som, animação)
	local function lancarBola(player, root, alvo, rapidez)
		if owner then releaseOwner() end
		passLock = nil
		ball.CanCollide = true
		recentKicker, recentKickTime = player, tick()
		kickerClearedBody = false
		hasBodyBlockedThisFlight = false
		startKickClearance(player)
		selfPickupLockUntil[player] = tick() + SELF_PICKUP_LOCK_SECONDS
		lastShotWasInstinct = false
		pushToucher(player)
		local dir = plano(alvo - ball.Position, plano(root.CFrame.LookVector, Vector3.new(0, 0, -1)))
		nudgeBallForwardForKick(dir)
		local v = _G.VelocidadeBalistica and _G.VelocidadeBalistica(ball.Position, alvo, rapidez)
		if not v then v = dir * rapidez + Vector3.new(0, rapidez * 0.1, 0) end
		ball.AssemblyLinearVelocity = v
		applyCurve(nil, dir)
		playKickFeedback(rapidez)
		playAnimation(player, Config.ANIMATIONS.Kick, nil, nil, true)
	end

	-- =====================================================================
	-- CURVA (Tiro Destruidor — Rin; Passe Curvo — Sae)
	-- ⚠️ v111 — BUG "tem que andar pro lado e às vezes buga": o lado vinha do
	-- MoveDirection no instante do chute. Correndo pra frente (W) ele é quase
	-- paralelo ao corpo e o sinal do produto escalar virava cara-ou-coroa — a
	-- bola curvava pro lado errado ou pra dentro do marcador. Agora o lado é
	-- AUTOMÁTICO: a bola sai pelo lado LIVRE e contorna o adversário (ou o
	-- goleiro) que está no caminho; sem ninguém no caminho, vem de fora pra
	-- dentro do canto mirado. A/D só manda se você estiver andando CLARAMENTE
	-- de lado (não na diagonal da corrida).
	-- =====================================================================
	_G.ArmaAplicarCurva = function(player, targetPoint, curva, chuteAGol, movimentoCliente)
		local _, root = getCharacterParts(player)
		if not root then return end
		local horizontal = Vector3.new(ball.AssemblyLinearVelocity.X, 0, ball.AssemblyLinearVelocity.Z)
		local distancia = Vector3.new(targetPoint.X - ball.Position.X, 0, targetPoint.Z - ball.Position.Z).Magnitude
		if horizontal.Magnitude <= 5 or distancia <= 8 then return end
		local frente = horizontal.Unit
		local direita = frente:Cross(Vector3.yAxis).Unit
		local lado = 0
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local mov = hum and hum.MoveDirection or Vector3.zero
		local lateral = mov:Dot(direita)
		if mov.Magnitude > 0.2 and math.abs(lateral) > 0.75 then
			lado = lateral >= 0 and 1 or -1
		else
			-- quem está no caminho (até 7 studs da linha, entre a bola e o alvo)
			local melhor, melhorAlong = nil, math.huge
			for _, pos in ipairs(obstaculos(player)) do
				local rel = Vector3.new(pos.X - ball.Position.X, 0, pos.Z - ball.Position.Z)
				local along = rel:Dot(frente)
				local desvio = rel:Dot(direita)
				if along > 3 and along < distancia + 2 and math.abs(desvio) < 7 and along < melhorAlong then
					melhor, melhorAlong = desvio, along
				end
			end
			if melhor and math.abs(melhor) > 0.6 then
				lado = melhor > 0 and -1 or 1 -- sai pelo lado LIVRE
			elseif chuteAGol and player.Team and enemyGoalOf(player.Team.Name) then
				local golAdv = enemyGoalOf(player.Team.Name)
				lado = ((targetPoint - golAdv.Position):Dot(direita) >= 0) and 1 or -1 -- de fora pra dentro do canto
			else
				lado = 1
			end
		end
		-- ⚠️ v111 (teste): 16° dava só ~3 studs de desvio num passe de 40 — quase
		-- não se via a curva. 20° x Curva (Rin 20°, Sae 24°).
		-- ⚠️ v118 — PEDIDO: "a curva do chute do Rin é muito pequena, sabor curva —
		-- quero pelo menos 3x mais". O desvio agora é LINEAR na Curva (tg = tan20°·
		-- Curva; Rin Curva 3 = ~27% da distância no meio do caminho) e a velocidade
		-- pra frente NÃO cai mais com a abertura (o chute não perde força).
		local tg = math.tan(math.rad(20)) * math.clamp(curva, 0.2, 3.5)
		local rapidez = horizontal.Magnitude
		local tempoAteAlvo = distancia / rapidez
		-- ⚠️ v119 — PEDIDO: "o chute do Rin chuta e vai pro lado — é a mesma coisa de
		-- chutar mirando pro lado. O certo é começar na minha RETA e fazer uma CURVA,
		-- igual o do Sae; acerta do lado, não exatamente onde mirou (vai pra esquerda
		-- ou pra direita, se você estiver indo pra direita)". Chute a gol (Rin): sai
		-- reto na mira e o desvio cresce aos poucos — y(x) = D·k·(x/D)^2.4 — chegando
		-- ao lado do ponto mirado. O lado é pra onde você está andando (A/D); parado,
		-- o lado livre. O PASSE do Sae continua com a curva de antes (abre e volta).
		if chuteAGol then
			-- ⚠️ v122 — PEDIDO: "o chute de um amigo vai pra esquerda/direita do nada" +
			-- "indo pro lado (A/D), segurando e soltando, não faz curva; pode voltar pra
			-- 24°, mas tem que curvar de verdade". O lado AUTOMÁTICO (adversário no
			-- caminho / de fora pra dentro) curvava TODO chute a gol de quem tinha a
			-- arma — era o "vai pro lado sozinho". E o MoveDirection lido no servidor
			-- falhava. Agora: a curva só existe com A/D segurado na hora de soltar, e o
			-- lado vem do CLIENTE (movimento na hora de soltar; MoveDirection só de reserva).
			local mov2 = movimentoCliente
			if not mov2 then
				local hum2 = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
				mov2 = hum2 and hum2.MoveDirection or Vector3.zero
			end
			local lateral2 = Vector3.new(mov2.X, 0, mov2.Z):Dot(direita)
			if math.abs(lateral2) < 0.3 then
				return nil -- sem A/D: chute RETO, sem curva
			end
			lado = lateral2 >= 0 and 1 or -1
			-- ⚠️ v120b — PEDIDO: "o chute do Rin não tá fazendo curva nenhuma. A partir
			-- de uns 35-45% da trajetória ela começa a virar o eixo pro lado (esquerda ou
			-- direita, conforme você anda); passou mais um pouco, vira mais... até uns
			-- 70%, e PARA — senão uma hora ela dá um 360 e volta pra você". Antes o
			-- desvio crescia com u^2.4 e quase nada aparecia antes do gol. Agora é o
			-- RUMO da bola que gira: 0° até 35% do caminho, sobe suave até o máximo em
			-- 70% e daí segue RETA no rumo novo (vale pra chute fraco ou forte — conta
			-- pela distância andada até o ponto mirado).
			local anguloMax = math.rad(math.clamp(8 * curva, 12, 26)) -- Rin (Curva 3) = 24° (⚠️ v122: "pode voltar pra 24°"; v120b era 30°)
			curveGeneration += 1
			local minhaCurvaGol = curveGeneration
			local origem = ball.Position
			local decorridoGol = 0
			local conexaoGol
			conexaoGol = RunService.Heartbeat:Connect(function(dt)
				decorridoGol += dt
				if minhaCurvaGol ~= curveGeneration or owner ~= nil or decorridoGol > tempoAteAlvo * 3
					or ball.AssemblyLinearVelocity.Magnitude < 6 then
					conexaoGol:Disconnect()
					return
				end
				local v = ball.AssemblyLinearVelocity
				local rel = Vector3.new(ball.Position.X - origem.X, 0, ball.Position.Z - origem.Z)
				local x = math.max(rel:Dot(frente), 0)
				local u = x / distancia
				local k = math.clamp((u - 0.35) / 0.35, 0, 1)
				local ang = anguloMax * (k * k * (3 - 2 * k))
				local horiz = Vector3.new(v.X, 0, v.Z).Magnitude
				local rumo = frente * math.cos(ang) + direita * (lado * math.sin(ang))
				ball.AssemblyLinearVelocity = rumo * horiz + Vector3.new(0, v.Y, 0)
				if u >= 0.7 then
					-- (o rumo novo já está aplicado: daqui pra frente a bola segue reta)
					conexaoGol:Disconnect()
				end
			end)
			return lado
		end
		local aberto = frente * rapidez + direita * (lado * rapidez * tg)
		ball.AssemblyLinearVelocity = aberto + Vector3.new(0, ball.AssemblyLinearVelocity.Y, 0)
		-- ⚠️ v111 (teste): a curva era uma força por TEMPO calculada com a
		-- velocidade de saída — a bola perde velocidade no caminho, então ela
		-- cruzava a linha antes (uns 32 de 40 studs) e chegava 5 studs de lado.
		-- Agora a curva segue a DISTÂNCIA andada: desvio lateral desejado
		-- y(x) = x·tg·(1 − x/D) (abre, chega no máximo no meio e volta a zero
		-- exatamente no alvo), com a velocidade lateral ajustada todo quadro.
		curveGeneration += 1
		local minhaCurva = curveGeneration
		local decorrido = 0
		local inicio = ball.Position
		local conexaoCurva
		conexaoCurva = RunService.Heartbeat:Connect(function(dt)
			decorrido += dt
			if minhaCurva ~= curveGeneration or owner ~= nil or decorrido > tempoAteAlvo * 2.5
				or ball.AssemblyLinearVelocity.Magnitude < 6 then
				conexaoCurva:Disconnect()
				return
			end
			local v = ball.AssemblyLinearVelocity
			local rel = Vector3.new(ball.Position.X - inicio.X, 0, ball.Position.Z - inicio.Z)
			local x = rel:Dot(frente)
			local vx = math.max(Vector3.new(v.X, 0, v.Z):Dot(frente), 1)
			if x >= distancia - 0.5 then
				-- chegou no alvo: a curva acaba e a bola segue reta na mira
				ball.AssemblyLinearVelocity = frente * Vector3.new(v.X, 0, v.Z).Magnitude + Vector3.new(0, v.Y, 0)
				conexaoCurva:Disconnect()
				return
			end
			local y = rel:Dot(direita) * lado
			local yDesejado = x * tg * (1 - x / distancia)
			local inclinacao = tg * (1 - 2 * x / distancia)
			local vLateral = vx * inclinacao + (yDesejado - y) * 6
			ball.AssemblyLinearVelocity = frente * vx + direita * (lado * vLateral) + Vector3.new(0, v.Y, 0)
		end)
		return lado
	end

	-- =====================================================================
	-- PIQUE → ARRANQUE: tiro curto de velocidade (com ou sem a bola)
	-- =====================================================================
	_G.ArmaAtiva_Arranque = function(player, effect)
		if isStunned(player) then return false, "atordoado" end
		local _, root = getCharacterParts(player)
		if not root then return false end
		local dir = plano(root.AssemblyLinearVelocity, nil) or plano(root.CFrame.LookVector, Vector3.new(0, 0, -1))
		local dist = alcanceLivre(root.Position, dir, effect.Distancia or 16)
		if dist < 2 then return false, "sem espaço pra arrancar" end
		sendDisplacement(player, dir * dist, effect.Tempo or 0.35)
		if _G.ArmaImpulsoVelocidade then _G.ArmaImpulsoVelocidade(player, effect.SpeedMult or 1.25, effect.Duracao or 1.6) end
		vfx(player, "Pique@arranque", { Dir = dir }, (effect.Duracao or 1.6))
		return true
	end

	-- =====================================================================
	-- MONSTRO DO DRIBLE (Bachira) → DRIBLE DO MONSTRO: três cortes em zigue-
	-- zague pra frente (~30 studs), sem poder ser desarmado no meio, e quem
	-- estiver no caminho cai (tornozelo quebrado)
	-- =====================================================================
	-- (dirForcada: o COUNTER do Monstro manda a direção — pra longe de quem tentou)
	_G.ArmaAtiva_DribleMonstro = function(player, effect, dirForcada)
		if owner ~= player then return false, "precisa estar com a bola" end
		if isStunned(player) then return false, "atordoado" end
		if GKAreaUtil.IsEffectiveGK(player) then return false, "goleiro na área não dribla" end
		if _G.IsPulseInProgress and _G.IsPulseInProgress(player) then return false end
		local _, root = getCharacterParts(player)
		if not root then return false end
		local frente = (typeof(dirForcada) == "Vector3" and dirForcada.Magnitude > 0.01) and dirForcada.Unit or direcaoDaMira(player, root)
		local direita = frente:Cross(Vector3.yAxis).Unit
		local cortes = effect.Cortes or 3
		local passo = effect.PassoCorte or 10
		local largura = effect.LarguraCorte or 4
		local tempoCorte = effect.TempoCorte or 0.3
		local stun = effect.StunNoCaminho or 1.3
		local total = cortes * tempoCorte
		if _G.GrantPulseIframe then _G.GrantPulseIframe(player, total + 0.2) end
		dribbleMoveCooldowns[player] = tick()
		vfx(player, "Monstro do Drible@drible", { Dir = frente, Cortes = cortes, Tempo = tempoCorte }, total)
		local derrubados = {}
		for i = 1, cortes do
			task.delay((i - 1) * tempoCorte, function()
				if owner ~= player or not player.Parent then return end
				local _, r = getCharacterParts(player)
				if not r then return end
				local lateral = (i == cortes) and 0 or ((i % 2 == 1) and 1 or -1)
				local alvo = frente * passo + direita * (lateral * largura)
				local dist = alcanceLivre(r.Position, alvo.Unit, alvo.Magnitude)
				playDribbleAnimation(player, lateral > 0 and "Right" or (lateral < 0 and "Left" or "Forward"), tempoCorte)
				sendDisplacement(player, alvo.Unit * dist, tempoCorte)
				-- quem está no caminho desse corte cai
				for _, plr in ipairs(Players:GetPlayers()) do
					if plr == player or derrubados[plr] or not areOpponents(player, plr) then continue end
					local _, o = getCharacterParts(plr)
					if o and (o.Position - (r.Position + alvo * 0.5)).Magnitude <= (effect.RaioCaminho or 7) then
						derrubados[plr] = true
						stunPlayer(plr, stun)
						if _G.MostrarTontura then _G.MostrarTontura(plr, stun) end
						ragdollPlayer(plr, math.min(stun, Config.ANKLE_BREAKER_RAGDOLL_DURATION or 1))
					end
				end
			end)
		end
		return true
	end

	-- =====================================================================
	-- PASSO FURTIVO → SUMIR: some da vista dos adversários por alguns
	-- segundos (o cliente deles te desenha quase transparente e sem nome)
	-- =====================================================================
	_G.ArmaAtiva_Sumir = function(player, effect)
		if not player.Character then return false end
		if owner == player then return false, "só sem a bola" end
		local dur = effect.Duracao or 3.5
		player.Character:SetAttribute("FurtivoAte", workspace:GetServerTimeNow() + dur)
		vfx(player, "Passo Furtivo@sumir", nil, dur)
		return true
	end

	-- =====================================================================
	-- ⚠️ v118 — PASSE MAGNETIZADO (Tabela e Passe do Prodígio)
	-- PEDIDO: "o passe de volta da tabela tem que ser automático, direto no seu
	-- pé — se você se mexer um pouco, hoje não pega" + "o passe do Sae tem que
	-- ser literalmente automático: alto, em curva, e magnetiza no corpo do
	-- jogador". A bola não é mais só lançada numa parábola fixa: o servidor guia
	-- a trajetória o voo inteiro (posição desejada a cada quadro) e o ponto de
	-- chegada SEGUE o receptor — se ele andar, a bola acompanha. No fim, ele
	-- domina sozinho. Se alguém pegar no meio do caminho (interceptação), o
	-- guia solta e vale a física normal.
	--   opts.Altura  = altura máxima acima da saída (passe alto)  OU
	--   opts.Rapidez = velocidade horizontal (passe rasteiro/rápido)
	--   opts.Desvio  = curva lateral (fração da distância, 0 = reto)
	--   opts.Lado    = 1 / -1 (lado da curva)
	-- =====================================================================
	local passeGeracao = 0
	local function pePe(r)
		return Vector3.new(r.Position.X, r.Position.Y - 2.2, r.Position.Z)
	end
	local function passeMagnetico(de, receptor, opts, aoChegar)
		local _, rDe = getCharacterParts(de)
		local _, rRec = getCharacterParts(receptor)
		if not rDe or not rRec then return false end
		lancarBola(de, rDe, pePe(rRec), 60)
		passeGeracao += 1
		curveGeneration += 1 -- encerra qualquer curva antiga
		local minha = passeGeracao
		local g = workspace.Gravity * Config.BALL_GRAVITY_MULTIPLIER
		local p0 = ball.Position
		local alvo0 = pePe(rRec)
		local plano0 = Vector3.new(alvo0.X - p0.X, 0, alvo0.Z - p0.Z)
		local dist = plano0.Magnitude
		local dy = alvo0.Y - p0.Y
		local vy, T
		if opts.Altura then
			vy = math.sqrt(2 * g * math.max(opts.Altura, 1))
			T = (vy + math.sqrt(math.max(0, vy * vy - 2 * g * dy))) / g
		else
			T = math.max(dist / (opts.Rapidez or 70), 0.25)
			vy = (dy + 0.5 * g * T * T) / T
		end
		local frente = dist > 0.5 and plano0.Unit or plano(rDe.CFrame.LookVector, Vector3.new(0, 0, -1))
		local lado = opts.Lado or 1
		local desvio = (opts.Desvio or 0) * dist
		local t = 0
		local function posicaoEm(tt)
			local u = math.clamp(tt / T, 0, 1)
			local _, r = getCharacterParts(receptor)
			local alvo = r and (pePe(r) + plano(r.AssemblyLinearVelocity, Vector3.zero) * math.min(r.AssemblyLinearVelocity.Magnitude, 40) * math.max(T - tt, 0) * 0.6) or alvo0
			local planoAlvo = Vector3.new(alvo.X - p0.X, 0, alvo.Z - p0.Z)
			local dirAgora = planoAlvo.Magnitude > 0.5 and planoAlvo.Unit or frente
			local direita = dirAgora:Cross(Vector3.yAxis)
			direita = direita.Magnitude > 0.01 and direita.Unit or Vector3.xAxis
			local h = p0 + planoAlvo * u + direita * (lado * desvio * math.sin(math.pi * u))
			-- vertical: parábola que termina na altura do pé do receptor
			local yBase = p0.Y + vy * tt - 0.5 * g * tt * tt
			local correcao = (alvo.Y - alvo0.Y) * u
			return Vector3.new(h.X, yBase + correcao, h.Z), r
		end
		local conexao
		conexao = RunService.Heartbeat:Connect(function(dt)
			if minha ~= passeGeracao or not receptor.Parent then conexao:Disconnect() return end
			if owner ~= nil then conexao:Disconnect() return end -- alguém dominou/interceptou
			t += dt
			local proxima, r = posicaoEm(t + dt)
			if not r then conexao:Disconnect() return end
			local perto = (ball.Position - r.Position).Magnitude <= 4.5
			if t >= T or (perto and t > T * 0.5) then
				conexao:Disconnect()
				if (ball.Position - r.Position).Magnitude <= 9 then
					ball.AssemblyLinearVelocity = Vector3.zero
					setOwner(receptor)
					pushToucher(receptor)
					if aoChegar then task.spawn(aoChegar) end
				end
				return
			end
			ball.AssemblyLinearVelocity = (proxima - ball.Position) / math.max(dt, 1 / 120)
		end)
		return true, T
	end

	-- companheiro mais perto de um ponto (dentro do alcance de quem passa)
	local function companheiroPerto(player, ponto, maxDoPassador, maxDoPonto)
		local _, eu = getCharacterParts(player)
		local melhor, menor = nil, maxDoPonto or math.huge
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr == player or areOpponents(player, plr) or not plr.Team or plr.Team ~= player.Team then continue end
			local _, r = getCharacterParts(plr)
			if r and eu and (r.Position - eu.Position).Magnitude <= (maxDoPassador or math.huge) then
				local d = Vector3.new(r.Position.X - ponto.X, 0, r.Position.Z - ponto.Z).Magnitude
				if d < menor then melhor, menor = plr, d end
			end
		end
		return melhor
	end

	-- lado da curva com menos gente no caminho
	local function ladoLivre(player, de, para)
		local frente = plano(para - de, Vector3.new(0, 0, -1))
		local direita = frente:Cross(Vector3.yAxis).Unit
		local dist = Vector3.new(para.X - de.X, 0, para.Z - de.Z).Magnitude
		local peso = 0
		for _, pos in ipairs(obstaculos(player)) do
			local rel = Vector3.new(pos.X - de.X, 0, pos.Z - de.Z)
			local along = rel:Dot(frente)
			if along > 2 and along < dist then
				local lateral = rel:Dot(direita)
				if math.abs(lateral) < dist * 0.4 then peso += (lateral > 0 and 1 or -1) end
			end
		end
		return peso > 0 and -1 or 1
	end

	-- =====================================================================
	-- TABELA → UM-DOIS: toca no companheiro e a bola VOLTA de primeira.
	-- ⚠️ v118 — PEDIDO: "não pode ser usada sozinho, precisa ter alguém; e o
	-- passe de volta tem que ser automático, direto no seu pé (hoje, se você se
	-- mexer um pouco, não pega)". Sem a sombra; a ida e a volta são passes
	-- magnetizados (a volta persegue você até chegar no pé).
	-- =====================================================================
	_G.ArmaAtiva_Tabela = function(player, effect)
		if owner ~= player then return false, "precisa estar com a bola" end
		if isStunned(player) then return false, "atordoado" end
		local _, root = getCharacterParts(player)
		if not root then return false end
		local _, mira = direcaoDaMira(player, root)
		local raio = effect.Raio or 60
		-- companheiro: o mais perto da mira (se tiver mira), senão o mais perto de você
		local parceiro = companheiroPerto(player, mira or root.Position, raio, mira and 30 or nil)
			or companheiroPerto(player, root.Position, raio, nil)
		if not parceiro then return false, string.format("precisa de um companheiro a até %d studs", raio) end
		local _, rParc = getCharacterParts(parceiro)
		vfx(player, "Tabela@ida", { De = root.Position, Ponto = pePe(rParc), Sombra = false }, 1.4)
		passeMagnetico(player, parceiro, { Rapidez = 95 }, function()
			-- devolve de primeira, no pé de quem começou a tabela
			task.wait(0.12)
			if owner ~= parceiro or not player.Parent then return end
			local _, rMeu = getCharacterParts(player)
			local _, rP = getCharacterParts(parceiro)
			if not rMeu or not rP then return end
			playAnimation(parceiro, Config.ANIMATIONS.Kick, nil, nil, true)
			passeMagnetico(parceiro, player, { Rapidez = 100 })
			selfPickupLockUntil[player] = nil
			vfx(player, "Tabela@volta", { De = ball.Position, Ponto = pePe(rMeu), Sombra = false }, 1)
		end)
		return true
	end

	-- =====================================================================
	-- PASSE DO PRODÍGIO (Sae) → PASSE CURVO: aperta a tecla e a bola vai
	-- CURVANDO até o ponto mirado — se tiver companheiro perto da mira, até o
	-- pé dele — contornando quem estiver no meio. Quem recebe chuta mais forte.
	-- =====================================================================
	_G.ArmaAtiva_PasseCurvo = function(player, effect)
		-- ⚠️ v118 — PEDIDO: "o passe do Sae tem que ser literalmente automático:
		-- aponta no jogador (o mais perto do mouse), sai um passe ALTO, em curva, e
		-- magnetiza no corpo dele; com distância máxima um pouco antes do meio do
		-- campo; cooldown maior". Ver passeMagnetico acima.
		if owner ~= player then return false, "precisa estar com a bola" end
		if isStunned(player) then return false, "atordoado" end
		local _, root = getCharacterParts(player)
		if not root then return false end
		local frente, mira = direcaoDaMira(player, root)
		local maxDist = effect.MaxDistancia or 340
		local ponto = mira or (root.Position + frente * 60)
		local companheiro = companheiroPerto(player, ponto, nil, nil)
		if not companheiro then return false, "nenhum companheiro em campo" end
		local _, r = getCharacterParts(companheiro)
		local dist = (r.Position - root.Position).Magnitude
		if dist > maxDist then return false, string.format("companheiro longe demais (%.0f studs, máx %d)", dist, maxDist) end
		if dist < 12 then return false, "companheiro perto demais pro passe alto" end
		local lado = ladoLivre(player, root.Position, r.Position)
		-- quanto mais longe, mais alto (passe longo do Sae vem do céu)
		local altura = math.clamp((effect.Altura or 34) * (0.45 + dist / 300), 12, 60)
		passeMagnetico(player, companheiro, { Altura = altura, Desvio = effect.Desvio or 0.35, Lado = lado })
		vfx(player, "Passe do Prodígio", nil, 2.4)
		if effect.CompanheiroForcaMult and _G.SetPulseTeammateBuff then
			_G.SetPulseTeammateBuff(companheiro, effect.CompanheiroForcaMult, 6)
		end
		return true
	end

	-- =====================================================================
	-- MARCAÇÃO CERRADA (Jingo) → COLAR: por alguns segundos você gruda no
	-- adversário com a bola, sempre entre ele e o seu gol
	-- =====================================================================
	_G.ArmaAtiva_Colar = function(player, effect)
		if isStunned(player) then return false, "atordoado" end
		local alvo = adversarioComBola(player, effect.Raio or 25)
		if not alvo then return false, string.format("nenhum adversário com a bola a até %d studs", effect.Raio or 25) end
		local dur = effect.Duracao or 3
		local fim = tick() + dur
		if _G.ArmaImpulsoVelocidade then _G.ArmaImpulsoVelocidade(player, effect.SpeedMult or 1.15, dur) end
		vfx(player, "Marcação Cerrada@colar", { Alvo = alvo.Character }, dur)
		task.spawn(function()
			while tick() < fim and player.Parent and alvo.Parent do
				task.wait(0.1)
				if owner ~= alvo or isStunned(player) then break end
				local _, meu = getCharacterParts(player)
				local _, dele = getCharacterParts(alvo)
				if not meu or not dele then break end
				local gol = player.Team and ownGoalOf(player.Team.Name)
				local proteger = gol and plano(gol.Position - dele.Position, Vector3.zero) or Vector3.zero
				local ponto = dele.Position + proteger * (effect.Distancia or 3.5)
				local falta = Vector3.new(ponto.X - meu.Position.X, 0, ponto.Z - meu.Position.Z)
				if falta.Magnitude > 0.8 then
					local passo = math.min(falta.Magnitude, (effect.VelocidadeColar or 34) * 0.1)
					sendDisplacement(player, falta.Unit * passo, 0.12)
				end
			end
		end)
		return true
	end

	-- =====================================================================
	-- LEITURA DE PASSE (Aiku) → INTERCEPTAR: com a bola solta em movimento
	-- perto, você dispara pro ponto por onde ela vai passar e domina
	-- =====================================================================
	_G.ArmaAtiva_Interceptar = function(player, effect)
		if isStunned(player) then return false, "atordoado" end
		if owner then return false, "só com a bola solta (passe ou chute no ar)" end
		local _, root = getCharacterParts(player)
		if not root then return false end
		local raio = effect.Raio or 38
		local velDash = effect.VelocidadeDash or 70
		local g = workspace.Gravity * Config.BALL_GRAVITY_MULTIPLIER
		local p0, v0 = ball.Position, ball.AssemblyLinearVelocity
		local chaoY = root.Position.Y - 2.5
		local melhorT, melhorPonto = nil, nil
		for i = 0, 24 do
			local t = i * 0.05
			local p = p0 + v0 * t + Vector3.new(0, -0.5 * g * t * t, 0)
			if p.Y < chaoY + 0.5 then p = Vector3.new(p.X, chaoY + 1, p.Z) end
			if p.Y > chaoY + 7 then continue end -- alto demais pra dominar
			local d = Vector3.new(p.X - root.Position.X, 0, p.Z - root.Position.Z).Magnitude
			if d <= raio and d <= velDash * math.max(t, 0.25) + 3 then
				melhorT, melhorPonto = t, p
				break
			end
		end
		if not melhorPonto then return false, "a bola não passa perto o bastante" end
		local falta = Vector3.new(melhorPonto.X - root.Position.X, 0, melhorPonto.Z - root.Position.Z)
		local dir = plano(falta, plano(root.CFrame.LookVector, Vector3.new(0, 0, -1)))
		local dist = alcanceLivre(root.Position, dir, math.max(0, falta.Magnitude - 1.5))
		local tempo = math.clamp(melhorT, 0.18, 0.6)
		sendDisplacement(player, dir * dist, tempo)
		avisarAcao(player.Character, "CorridaHissatsu", tempo)
		vfx(player, "Leitura de Passe@interceptar", { Dir = dir }, tempo)
		task.delay(tempo + 0.02, function()
			if owner or not player.Parent or isStunned(player) then return end
			local _, r = getCharacterParts(player)
			if r and (ball.Position - r.Position).Magnitude <= (effect.RaioDominio or 7) then
				ball.AssemblyLinearVelocity = Vector3.zero
				setOwner(player)
				pushToucher(player)
			end
		end)
		return true
	end

	-- =====================================================================
	-- ANTECIPAÇÃO FANTASMA (Aiku) → PASSO FANTASMA: some e reaparece NA
	-- FRENTE do adversário com a bola, fechando o caminho pro gol
	-- =====================================================================
	_G.ArmaAtiva_PassoFantasma = function(player, effect)
		if isStunned(player) then return false, "atordoado" end
		local alvo, dele = adversarioComBola(player, effect.Raio or 28)
		if not alvo then return false, string.format("nenhum adversário com a bola a até %d studs", effect.Raio or 28) end
		local _, meu = getCharacterParts(player)
		if not meu then return false end
		local gol = player.Team and ownGoalOf(player.Team.Name)
		local frenteDele = plano(dele.AssemblyLinearVelocity, nil) or (gol and plano(gol.Position - dele.Position, nil)) or plano(dele.CFrame.LookVector, Vector3.new(0, 0, -1))
		local ponto = dele.Position + frenteDele * (effect.Distancia or 4.5)
		local falta = Vector3.new(ponto.X - meu.Position.X, 0, ponto.Z - meu.Position.Z)
		local dir = plano(falta, frenteDele)
		local dist = alcanceLivre(meu.Position, dir, falta.Magnitude)
		vfx(player, "Antecipação Fantasma@passo", { De = meu.Position, Para = meu.Position + dir * dist }, 0.6)
		sendDisplacement(player, dir * dist, effect.Tempo or 0.14)
		return true
	end

	-- =====================================================================
	-- ⚠️ v119 — ARMAS DE DEFESA UNIFICADAS + COUNTERS + SAÍDA TELEGUIADA + CHAPÉU
	-- PEDIDO: "três armas de defesa (desarme instantâneo, avançar na bola, avançar
	-- no defensor) podem ser uma só: avança no cara e tira a bola automaticamente,
	-- tipo um segundo carrinho, distância maior, teleguiado, o cara pode driblar"
	-- + "faz umas duas armas de counter" + "a Saída de área é inútil" + "o chapéu
	-- precisa ser mais complexo". Função própria (limite de locais do arquivo).
	-- =====================================================================
	;(function()
		-- persegue um alvo que se mexe (posição devolvida por alvoPos a cada passo)
		-- com deslocamentos curtos; encostou -> AoEncostar(root)
		local function perseguir(player, alvoPos, opts)
			local t0 = tick()
			local passoT = 0.05
			task.spawn(function()
				while player.Parent do
					local _, r = getCharacterParts(player)
					if not r or isStunned(player) then break end
					local alvo = alvoPos()
					if not alvo then break end
					local falta = Vector3.new(alvo.X - r.Position.X, 0, alvo.Z - r.Position.Z)
					if falta.Magnitude <= opts.Raio then
						opts.AoEncostar(r)
						return
					end
					if tick() - t0 > opts.TempoMax then break end
					local dir = falta.Unit
					local passo = math.min(falta.Magnitude, opts.Velocidade * passoT * 1.15)
					local livre = alcanceLivre(r.Position, dir, passo)
					if livre < 0.2 then break end
					sendDisplacement(player, dir * livre, passoT)
					task.wait(passoT)
				end
				if opts.AoAcabar then opts.AoAcabar() end
			end)
		end

		local function roubar(de, para, stun)
			releaseOwner()
			ball.CanCollide = true
			tackleSound:Play()
			setOwner(para)
			if stun and stun > 0 then
				stunPlayer(de, stun)
				avisarAcao(de.Character, "SofreuCarrinho", stun)
			end
			if _G.RegisterTackle then _G.RegisterTackle(para, de) end
		end

		-- DESARME RELÂMPAGO → BOTE TELEGUIADO (a arma unificada)
		_G.ArmaAtiva_BoteTeleguiado = function(player, effect)
			if isStunned(player) then return false, "atordoado" end
			if owner == player then return false, "só sem a bola" end
			local raio = effect.Raio or 40
			local alvo = adversarioComBola(player, raio)
			if not alvo then return false, string.format("nenhum adversário com a bola a até %d studs", raio) end
			local tMax = effect.TempoMax or 0.9
			avisarAcao(player.Character, "Investida", tMax)
			vfx(player, "Desarme Relâmpago@bote", { Alvo = alvo.Character, Tempo = tMax }, tMax)
			Remotes.SuppressShiftLockRotation:FireClient(player, tMax)
			perseguir(player, function()
				if owner ~= alvo then return nil end
				local _, d = getCharacterParts(alvo)
				return d and d.Position
			end, {
				Velocidade = effect.Velocidade or 85, TempoMax = tMax, Raio = effect.RaioRoubo or 4.5,
				-- mesmas regras do carrinho: drible na hora certa / iframe = quem cai é
				-- você; goleiro na área não perde; guarda furtiva vira contra-ataque
				AoEncostar = function() resolveStealAttempt(player, alvo) end,
			})
			return true
		end

		-- LEITURA DE PASSE → ZONA DO AIKU (counter de área, só no terço de defesa)
		_G.ArmaAtiva_ZonaAiku = function(player, effect)
			if isStunned(player) then return false, "atordoado" end
			local _, root = getCharacterParts(player)
			if not root or not player.Character then return false end
			local gol = player.Team and ownGoalOf(player.Team.Name)
			local maxGol = effect.MaxDistanciaGol or 290
			if not gol or Vector3.new(gol.Position.X - root.Position.X, 0, gol.Position.Z - root.Position.Z).Magnitude > maxGol then
				return false, "só no seu terço de defesa"
			end
			local raio, dur = effect.Raio or 14, effect.Duracao or 4
			local fim = tick() + dur
			player.Character:SetAttribute("ZonaAikuAte", workspace:GetServerTimeNow() + dur)
			player.Character:SetAttribute("ZonaAikuRaio", raio)
			vfx(player, "Leitura de Passe@zona", { Raio = raio, Duracao = dur }, dur)
			task.spawn(function()
				while tick() < fim and player.Parent do
					task.wait(0.05)
					if isStunned(player) then break end
					local dono = owner
					if dono and dono ~= player and areOpponents(player, dono) and not GKAreaUtil.IsEffectiveGK(dono)
						and not (_G.HasPulseIframe and _G.HasPulseIframe(dono)) then
						local _, meu = getCharacterParts(player)
						local _, dele = getCharacterParts(dono)
						if meu and dele and (meu.Position - dele.Position).Magnitude <= raio then
							roubar(dono, player, 0.9)
							vfx(player, "Leitura de Passe@roubo", { Alvo = dono.Character }, 0.8)
							break
						end
					end
				end
				if player.Character then player.Character:SetAttribute("ZonaAikuAte", nil) end
			end)
			return true
		end

		-- PASSO FURTIVO: sem a bola = SUMIR (como antes); com a bola = GUARDA
		-- (counter do carrinho)
		local guardaFurtiva = {} -- [player] = { Ate, Effect }
		_G.ArmaAtiva_SumirOuGuarda = function(player, effect)
			if owner ~= player then return _G.ArmaAtiva_Sumir(player, effect) end
			if isStunned(player) then return false, "atordoado" end
			local janela = effect.Janela or 1.6
			guardaFurtiva[player] = { Ate = tick() + janela, Effect = effect }
			if _G.GrantPulseIframe then _G.GrantPulseIframe(player, janela) end
			vfx(player, "Passo Furtivo@guarda", { Tempo = janela }, janela)
			return true
		end
		-- chamado na resolução de TODO desarme (carrinho, bote, investida): se o
		-- alvo está em guarda, o desarme vira contra-ataque e devolve true
		_G.ContraGuardaFurtiva = function(alvo, atacante)
			-- ⚠️ v120b — PEDIDO: "esse counter (do Passo Furtivo) vai pro Monstro do Drible,
			-- e aumenta a velocidade dele: ele dá o counter assim que o cara tenta acertar".
			-- Com a bola e o Monstro do Drible pronto, QUALQUER desarme em você (carrinho,
			-- bote, investida) vira o drible do monstro pra longe dele — e ele fica tonto.
			if owner == alvo and _G.UsarCounterDaArma and not isStunned(alvo) then
				local efeitoMonstro = _G.UsarCounterDaArma(alvo, "Monstro do Drible")
				if efeitoMonstro then
					local _, ra = getCharacterParts(alvo)
					local _, rt = getCharacterParts(atacante)
					local dir = nil
					if ra and rt then
						local longe = plano(ra.Position - rt.Position, plano(ra.CFrame.LookVector, Vector3.new(0, 0, -1)))
						local lado = longe:Cross(Vector3.yAxis).Unit * ((math.random() < 0.5) and 1 or -1)
						dir = (longe + lado * 0.6).Unit
					end
					local stunContra = efeitoMonstro.StunContra or 1.6
					stunPlayer(atacante, stunContra)
					ragdollPlayer(atacante, 1)
					vfx(alvo, "Monstro do Drible@contra", { Alvo = atacante.Character, Tempo = stunContra }, 0.8)
					_G.ArmaAtiva_DribleMonstro(alvo, efeitoMonstro, dir)
					return true
				end
			end
			local g = guardaFurtiva[alvo]
			if not g then return false end
			guardaFurtiva[alvo] = nil
			if tick() > g.Ate or owner ~= alvo then return false end
			local _, ra = getCharacterParts(alvo)
			local _, rt = getCharacterParts(atacante)
			if ra and rt then
				local vindo = plano(ra.Position - rt.Position, plano(ra.CFrame.LookVector, Vector3.new(0, 0, -1)))
				local lado = vindo:Cross(Vector3.yAxis).Unit * ((math.random() < 0.5) and 1 or -1)
				local passo = lado * (g.Effect.Desvio or 7) + vindo * 3
				local livre = alcanceLivre(ra.Position, passo.Unit, passo.Magnitude)
				playDribbleAnimation(alvo, lado:Dot(ra.CFrame.RightVector) > 0 and "Right" or "Left", 0.3)
				sendDisplacement(alvo, passo.Unit * livre, 0.22)
			end
			stunPlayer(atacante, g.Effect.Stun or 1.6)
			ragdollPlayer(atacante, 1)
			if _G.GrantPulseIframe then _G.GrantPulseIframe(alvo, 0.5) end
			vfx(alvo, "Passo Furtivo@contra", { Alvo = atacante.Character }, 0.8)
			return true
		end

		-- ANTECIPAÇÃO FANTASMA → GUARDA CONTRA O DRIBLE (counter)
		_G.ArmaAtiva_AntecipaDrible = function(player, effect)
			if isStunned(player) then return false, "atordoado" end
			local raio = effect.Raio or 18
			local alvo = adversarioComBola(player, raio)
			if not alvo then return false, string.format("nenhum adversário com a bola a até %d studs", raio) end
			local inicio = tick()
			local janela = effect.Janela or 2.5
			local fim = inicio + janela
			vfx(player, "Antecipação Fantasma@guarda", { Alvo = alvo.Character, Tempo = janela }, janela)
			task.spawn(function()
				while tick() < fim and player.Parent do
					task.wait(0.03)
					if isStunned(player) or owner ~= alvo then return end
					local ultimo = dribbleMoveCooldowns[alvo]
					if ultimo and ultimo > inicio then
						task.wait(0.28) -- o fim do drible dele
						if owner ~= alvo or isStunned(player) or GKAreaUtil.IsEffectiveGK(alvo) then return end
						local _, meu = getCharacterParts(player)
						local _, dele = getCharacterParts(alvo)
						if not meu or not dele then return end
						local frente = plano(dele.AssemblyLinearVelocity, nil) or plano(dele.CFrame.LookVector, Vector3.new(0, 0, -1))
						local ponto = dele.Position + frente * 2.5
						local falta = Vector3.new(ponto.X - meu.Position.X, 0, ponto.Z - meu.Position.Z)
						if falta.Magnitude > raio + 14 then return end
						vfx(player, "Antecipação Fantasma@passo", { De = meu.Position, Para = ponto }, 0.6)
						sendDisplacement(player, falta, 0.12)
						task.wait(0.12)
						if owner ~= alvo then return end
						roubar(alvo, player, 1.1) -- leu o drible: passa por cima do iframe dele
						return
					end
				end
			end)
			return true
		end

		-- SAÍDA RÁPIDA (goleiro) → SAÍDA TELEGUIADA
		_G.ArmaAtiva_SaidaDoGol = function(player, effect)
			if isStunned(player) then return false, "atordoado" end
			if owner == player then return false, "você já está com a bola" end
			local _, root = getCharacterParts(player)
			if not root then return false end
			local raio = effect.Raio or 42
			if Vector3.new(ball.Position.X - root.Position.X, 0, ball.Position.Z - root.Position.Z).Magnitude > raio then
				return false, "a bola está longe demais"
			end
			if owner and not areOpponents(player, owner) then return false, "a bola está com o seu time" end
			local tMax = effect.TempoMax or 0.85
			avisarAcao(player.Character, "CorridaHissatsu", tMax)
			vfx(player, "Saída Rápida@saida", { Dir = plano(ball.Position - root.Position, plano(root.CFrame.LookVector, Vector3.new(0, 0, -1))) }, tMax)
			Remotes.SuppressShiftLockRotation:FireClient(player, tMax)
			perseguir(player, function()
				if owner and not areOpponents(player, owner) then return nil end
				if owner then
					local _, d = getCharacterParts(owner)
					return d and d.Position
				end
				return ball.Position
			end, {
				Velocidade = effect.Velocidade or 80, TempoMax = tMax, Raio = effect.RaioAgarrar or 6,
				AoEncostar = function(r)
					if owner == nil then
						if ball.Position.Y < r.Position.Y + 6 then
							ball.AssemblyLinearVelocity = Vector3.zero
							ball.CanCollide = true
							setOwner(player)
							pushToucher(player)
						end
					elseif areOpponents(player, owner) and not (_G.HasPulseIframe and _G.HasPulseIframe(owner)) then
						roubar(owner, player, 0)
					end
				end,
			})
			return true
		end

		-- CHAPÉU: só com marcador NA FRENTE; a bola passa por cima dele, você
		-- contorna pelo lado e pega do outro lado; ele fica atordoado
		_G.ArmaAtiva_Chapeu = function(player, effect)
			if owner ~= player then return false, "precisa estar com a bola" end
			if isStunned(player) then return false, "atordoado" end
			local _, root = getCharacterParts(player)
			if not root then return false end
			local frente = direcaoDaMira(player, root)
			local alvo, rAlvo, menor = nil, nil, effect.RaioMarcador or 14
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= player and areOpponents(player, plr) then
					local _, r = getCharacterParts(plr)
					if r then
						local rel = Vector3.new(r.Position.X - root.Position.X, 0, r.Position.Z - root.Position.Z)
						local d = rel.Magnitude
						if d > 1 and d <= menor and rel.Unit:Dot(frente) > 0.55 then alvo, rAlvo, menor = plr, r, d end
					end
				end
			end
			if not alvo then return false, "precisa de um marcador na sua frente" end
			local dirAlvo = Vector3.new(rAlvo.Position.X - root.Position.X, 0, rAlvo.Position.Z - root.Position.Z).Unit
			local livre = alcanceLivre(root.Position, dirAlvo, menor + (effect.Alem or 8))
			if livre < menor + 3 then return false, "sem espaço atrás do marcador" end
			local chao = root.Position.Y - 3
			local alvoBola = Vector3.new(root.Position.X, chao + 1, root.Position.Z) + dirAlvo * livre
			local g = workspace.Gravity * Config.BALL_GRAVITY_MULTIPLIER
			lancarBola(player, root, alvoBola, 40)
			local p0 = ball.Position
			-- sobe o bastante pra passar por cima da CABEÇA dele
			local subir = math.max(effect.Altura or 9, (rAlvo.Position.Y + 4) - p0.Y)
			local vy = math.sqrt(2 * g * subir)
			local tempo = vy / g + math.sqrt(math.max(0.01, 2 * (subir + p0.Y - alvoBola.Y) / g))
			local planoV = Vector3.new(alvoBola.X - p0.X, 0, alvoBola.Z - p0.Z)
			ball.AssemblyLinearVelocity = planoV / tempo + Vector3.new(0, vy, 0)
			curveGeneration += 1
			selfPickupLockUntil[player] = tick() + tempo * 0.75
			stunPlayer(alvo, effect.Stun or 1.6)
			avisarAcao(alvo.Character, "Tonto", effect.Stun or 1.6)
			if _G.GrantPulseIframe then _G.GrantPulseIframe(player, tempo + 0.3) end
			playAnimation(player, Config.ANIMATIONS.Kick, nil, 0.45, true, nil, nil, "Chapeu")
			-- contorna: primeiro passa pelo LADO dele, depois vai onde a bola cai
			local direita = dirAlvo:Cross(Vector3.yAxis).Unit
			local lado = (math.random() < 0.5) and 1 or -1
			local meio = rAlvo.Position + direita * (lado * 3.5)
			local ida = Vector3.new(meio.X - root.Position.X, 0, meio.Z - root.Position.Z)
			task.delay(0.12, function()
				if not player.Parent then return end
				sendDisplacement(player, ida, tempo * 0.45)
				task.delay(tempo * 0.45, function()
					local _, r = getCharacterParts(player)
					if not r then return end
					sendDisplacement(player, Vector3.new(alvoBola.X - r.Position.X, 0, alvoBola.Z - r.Position.Z), tempo * 0.4)
				end)
			end)
			task.delay(tempo + 0.05, function()
				if owner then return end
				local _, r = getCharacterParts(player)
				if r and (ball.Position - r.Position).Magnitude <= 9 then
					ball.AssemblyLinearVelocity = Vector3.zero
					setOwner(player)
					pushToucher(player)
				end
			end)
			vfx(player, "Chapéu@chapeu", { De = p0, Para = alvoBola, Tempo = tempo, Alvo = alvo.Character }, tempo)
			return true
		end
	end)()
end)()
