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

	table.insert(matchHistory, sample)

	-- poda o que já passou do tempo que a gente precisa guardar (com uma
	-- folguinha de 1s de segurança)
	local cutoff = now - (Config.GOAL_REPLAY_DURATION + 1)
	while #matchHistory > 0 and matchHistory[1].t < cutoff do
		table.remove(matchHistory, 1)
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
local LOOSE_BALL_PICKUP_MAX_SPEED = 22

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
local function playAnimation(player, animationId, priority, ajustarPara, semLoop, congelarNoFim)
	-- ⚠️ FIX: normaliza (aceita colar só o número, sem "rbxassetid://" na
	-- frente — ver Config.NormalizeAnimationId em FootballConfig.luau).
	animationId = Config.NormalizeAnimationId(animationId)
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
	if semLoop or congelarNoFim or (ajustarPara and ajustarPara > 0) then
		task.spawn(function()
			local esperou = 0
			while track.Length <= 0 and esperou < 2 do
				task.wait(0.05)
				esperou += 0.05
			end
			if track.Length <= 0 then return end

			-- reafirma DEPOIS da carga (ver o comentário acima)
			if semLoop or congelarNoFim then track.Looped = false end

			if ajustarPara and ajustarPara > 0 then
				track:AdjustSpeed(track.Length / ajustarPara)
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

local function setOwner(player)
	local previousOwner = owner
	owner = player
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
	if owner then
		Remotes.PossessionChanged:FireAllClients(owner, false)
		if dribbleMoves[owner] then setIframeGlow(owner, false) end
		dribbleMoves[owner] = nil
	end
	owner = nil
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

local function startPulseStraightFlight(force)
	pulseStraightFlightActive = true
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
RunService.Heartbeat:Connect(function()
	if not pulseStraightFlightActive then return end
	if owner ~= nil or ball.AssemblyLinearVelocity.Magnitude < 2 then
		stopPulseStraightFlight()
	end
end)

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
	gravityForce.Force = Vector3.new(0, ball.AssemblyMass * workspace.Gravity * liftFraction, 0)
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
RunService.Heartbeat:Connect(function(dt)
	if owner then return end -- bola com dono: quem controla é o dribble/posse, não isso aqui
	if not isBallGrounded() then return end

	local angular = ball.AssemblyAngularVelocity
	ball.AssemblyAngularVelocity = angular * (Config.BALL_ANGULAR_DAMPING_PER_SECOND ^ dt)

	local velocity = ball.AssemblyLinearVelocity
	local horizontal = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = horizontal.Magnitude
	if speed <= 0.05 then return end

	local decelRate = (speed > Config.BALL_ROLLING_MAX_SPEED)
		and Config.BALL_ROLLING_FAST_DECELERATION
		or Config.BALL_ROLLING_DECELERATION
	local newSpeed = math.max(0, speed - decelRate * dt)
	local newHorizontal = (newSpeed > 0) and (horizontal.Unit * newSpeed) or Vector3.new(0, 0, 0)
	ball.AssemblyLinearVelocity = Vector3.new(newHorizontal.X, velocity.Y, newHorizontal.Z)
end)

-- ===== STUN =====
local stunnedUntil = {}
local preStunWalkSpeed = {}

local function stunPlayer(player, duration)
	if not duration or duration <= 0 then return end
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

-- ⚠️ v8: Energy entra na fórmula de força dos Pulsos de Chute junto com
-- Kick (era só o atributo base sem uso nenhum até agora — ver comentário
-- de Config.ENERGY_ATTRIBUTE). Mesma faixa/curva do Kick.
local function getEnergyForceMultiplier(player)
	local value = player:GetAttribute(Config.ENERGY_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_ENERGY end
	local fraction = math.clamp(value, 0, 100) / 100
	return Config.ENERGY_FORCE_MULTIPLIER_MIN + (Config.ENERGY_FORCE_MULTIPLIER_MAX - Config.ENERGY_FORCE_MULTIPLIER_MIN) * fraction
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
		local _, blockerRoot = getCharacterParts(plr)
		if blockerRoot and (blockerRoot.Position - ball.Position).Magnitude <= radius then
			pulseFlightExternalMult = 0.15
			pulseFlightBlockApplied = true
			ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity * 0.15
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
	local liveFactor = getPulseRangeFactor(traveled, pulseFlightMaxRange)
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
	}
end

-- ===== DESVIO DE MIRA =====
-- Graus de desvio ALEATÓRIO nesse chute específico, antes de qualquer
-- redução de Pulso/Instinto (aimDeviationMult, aplicado por quem chama
-- essa função). Pior Kick = mais desvio; adversário em cima (pressão) =
-- mais desvio ainda.
local function getAimDeviationDegrees(player)
	local kickValue = player:GetAttribute(Config.KICK_ATTRIBUTE)
	if typeof(kickValue) ~= "number" then kickValue = Config.DEFAULT_KICK end
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

	local activeMove = dribbleMoves[owner]
	local targetPosition
	if activeMove then
		if tick() < activeMove.expiresAt then
			targetPosition = activeMove.targetPosition + Vector3.new(0, Config.DRIBBLE_HEIGHT_OFFSET, 0)

			-- Desloca o PERSONAGEM diretamente via CFrame, terminando
			-- exatamente no mesmo instante em que a janela da finta acaba
			-- — sincronizado com a bola por construção. Usa uma curva de
			-- easing (ease-out cúbica) em vez de linear: começa rápido,
			-- parecido com o embalo que o jogador já trazia (corrida/
			-- sprint), e desacelera suave até o ponto final, em vez de
			-- trocar de velocidade/direção de golpe no instante em que a
			-- finta dispara.
			local totalDuration = activeMove.expiresAt - activeMove.triggeredAt
			local alpha = totalDuration > 0
				and math.clamp((tick() - activeMove.triggeredAt) / totalDuration, 0, 1)
				or 1
			local easedAlpha = 1 - (1 - alpha) ^ 3

			local newPosition = activeMove.startPosition:Lerp(activeMove.endPosition, easedAlpha)
			root.CFrame = root.CFrame.Rotation + newPosition
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			root.AssemblyAngularVelocity = Vector3.zero
			if humanoid then
				humanoid:Move(Vector3.zero, false)
			end
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
	if ball.AssemblyLinearVelocity.Magnitude > LOOSE_BALL_PICKUP_MAX_SPEED then return end

	local bestPlayer, bestDistance = nil, math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		-- ⚠️ v5.6: trava de auto-repossessão — o próprio chutador não conta
		-- pro pickup passivo por SELF_PICKUP_LOCK_SECONDS depois do chute
		-- (ver KickBall abaixo). Qualquer outro jogador continua elegível
		-- normalmente.
		if selfPickupLockUntil[plr] and tick() < selfPickupLockUntil[plr] then continue end

		local _, root = getCharacterParts(plr)
		if not root then continue end

		local radius = Config.POSSESSION_PICKUP_RADIUS
		if _G.GetPulsePickupRadiusAdd then radius += _G.GetPulsePickupRadiusAdd(plr) end
		if _G.CheckInstinct then
			local opponentDistance = nearestOpponentDistance(plr)
			local effect = _G.CheckInstinct(plr, "Instant", { OpponentDistance = opponentDistance })
			if effect and effect.PickupRadiusAdd then radius += effect.PickupRadiusAdd end
		end

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
			distance = (vertical <= Config.AERIAL_PICKUP_HEIGHT) and horizontal or math.huge
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
	if not GKAreaUtil.IsEffectiveGK(player) then return end -- só funciona goleiro DENTRO da própria área
	if isStunned(player) then return end
	if gkActionCooldowns[player] and tick() < gkActionCooldowns[player] then return end
	local vectorFn = typeof(direction) == "string" and DIVE_DIRECTION_VECTOR[direction]
	if not vectorFn then return end

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
	startGKMove(player, root, vectorFn(root), diveDistance, Config.GK_DIVE_DURATION, nil)
end)

Remotes.AttemptGKForward.OnServerEvent:Connect(function(player)
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
		end
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

-- ===== FINTA DIRECIONAL (Z esquerda / X trás / C direita) =====
local function getSkillMoveDirectionVector(root, moveName)
	if moveName == "Left" then
		return -root.CFrame.RightVector
	elseif moveName == "Right" then
		return root.CFrame.RightVector
	elseif moveName == "Back" then
		return -root.CFrame.LookVector
	end
	return nil
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
	if owner ~= player then return end
	if isStunned(player) then return end
	-- ⚠️ v24: nem finta por fora de uma Hissatsu de bola em andamento — a
	-- finta desloca a bola e faria a Hissatsu resolver sem ela no pé.
	if _G.IsPulseInProgress and _G.IsPulseInProgress(player) then return end
	if GKAreaUtil.IsEffectiveGK(player) then return end -- GK DENTRO da área usa AttemptGKDive (Z/X/C/E/Q viram mergulho, não finta); fora da área, finta normal

	local direction
	if typeof(moveName) == "string" then
		local _, root = getCharacterParts(player)
		if root then
			direction = getSkillMoveDirectionVector(root, moveName)
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

	-- SEMPRE dá certo — sem porcentagem/chance. Só a distância e a janela
	-- de iframe escalam com o DribbleSkill (0-100) do jogador.
	local skill = getDribbleSkill(player)
	local distance = Config.DRIBBLE_MOVE_MIN_DISTANCE
		+ (Config.DRIBBLE_MOVE_MAX_DISTANCE - Config.DRIBBLE_MOVE_MIN_DISTANCE) * skill
	local window = Config.DRIBBLE_ANIMATION_SECONDS -- ⚠️ v64: janela FIXA (= tempo da animação); a distância é que escala, logo a velocidade escala junto

	playAnimation(player, dribbleAnimationFor(moveName), Enum.AnimationPriority.Action2, window, true) -- ⚠️ v63: reprodução ajustada à janela (cresce com o DribbleSkill)

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
	local endPosition = root.Position + direction * (distance + dashDistance)
	dribbleMoves[player] = {
		targetPosition = endPosition,
		startPosition = root.Position,
		endPosition = endPosition,
		triggeredAt = tick(),
		expiresAt = tick() + window,
	}
	setIframeGlow(player, true) -- janela de iframe ativa: brilho branco enquanto durar

	-- Durante a janela da finta, o servidor é quem decide a rotação
	-- (preserva a que já estava, ver loop de drible acima). Se o Shift
	-- Lock do cliente também tentar girar o boneco pra câmera ao mesmo
	-- tempo, os dois brigam pela mesma rotação — avisa o cliente pra
	-- soltar por essa janela.
	Remotes.SuppressShiftLockRotation:FireClient(player, window)
end)

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

Remotes.KickBall.OnServerEvent:Connect(function(player, chargedForce, targetPoint)
	if isStunned(player) then return end
	-- ⚠️ v24: com uma Hissatsu de bola em andamento, a bola não sai do pé por
	-- fora dela (ver _G.IsPulseInProgress em PulseController.legacy.luau).
	if _G.IsPulseInProgress and _G.IsPulseInProgress(player) then return end
	if typeof(targetPoint) ~= "Vector3" then return end

	local _, root = getCharacterParts(player)
	if not root then return end

	local hasControl = owner == player
	local isVolley = false

	if not hasControl then
		-- sem posse: só permite chutar a BOLA se for VOLEIO (bola no ar, ao alcance)
		local ballHeightAboveGround = ball.Position.Y - root.Position.Y
		local distance = (ball.Position - root.Position).Magnitude
		if ballHeightAboveGround < Config.VOLLEY_MIN_BALL_HEIGHT or distance > Config.VOLLEY_RANGE then
			-- ⚠️ v85 — PEDIDO: "se eu chutar sem a bola, a animação de chutar
			-- não sai... a animação de chute precisa sair mesmo sem a bola".
			-- Antes o handler só saía daqui — o preparo (perna levantada) era
			-- encerrado pelo UpdateKickCharging(false) e nenhum chute entrava
			-- no lugar, então a pose parecia travada e o movimento nunca
			-- terminava. Agora é um chute no vazio: a animação toca inteira
			-- (mesmo corte dos dribles do chute de verdade, ver o fim deste
			-- handler), só a bola não é tocada.
			-- ⚠️ v86 — o preparo é encerrado AQUI também, sem depender de o
			-- UpdateKickCharging(false) ter chegado antes: com o preparo ainda
			-- congelado na mesma prioridade (Action), o chute se misturava com
			-- a perna parada e "não saía". O KickCharging=false é o que avisa
			-- o AnimationGuard de cada tela pra soltar a cópia local dele.
			player:SetAttribute("KickCharging", false)
			stopAnimation(player, Config.ANIMATIONS.PrepareKick, 0)
			for _, direcao in ipairs({ "Left", "Back", "Right" }) do
				stopAnimation(player, dribbleAnimationFor(direcao), 0)
			end
			playAnimation(player, Config.ANIMATIONS.Kick, nil, nil, true)
			return
		end
		isVolley = true
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
			DistanceToGoal = distanceToGoal,
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
		local degrees = getAimDeviationDegrees(player) * aimDeviationMult
		direction = applyAimDeviation(direction, degrees)
	end

	nudgeBallForwardForKick(direction) -- ⚠️ v21: já nasce fora do raio do corpo, na direção do chute

	local velocity = direction * force
	velocity += Vector3.new(0, force * Config.KICK_UPWARD_BOOST, 0)
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
	player:SetAttribute("KickCharging", false) -- ⚠️ v86: solta o preparo em toda tela (ver o chute no vazio acima)
	stopAnimation(player, Config.ANIMATIONS.PrepareKick, 0)
	for _, direcao in ipairs({ "Left", "Back", "Right" }) do
		stopAnimation(player, dribbleAnimationFor(direcao), 0)
	end
	playAnimation(player, Config.ANIMATIONS.Kick, nil, nil, true) -- ⚠️ v60
	-- ⚠️ v84 — PEDIDO: chute "sem nenhum tipo de erro, exatamente no ponto
	-- mirado". O `spin` que o cliente manda vem da distância HORIZONTAL entre
	-- o mouse e a bola na tela (computeSpin no FootballClient) — ou seja,
	-- qualquer mira que não esteja exatamente em cima da bola já curvava o
	-- chute (até ~15 studs/s de lado durante 0.7s). Era a maior fonte do "vai
	-- pra um lado ou pro outro". O chute normal agora sai RETO na direção
	-- mirada; curva ficou só nas Hissatsus que têm CurveMult próprio.
	applyCurve(nil, direction)
end)

-- ===== CABEÇADA =====
Remotes.AttemptHeader.OnServerEvent:Connect(function(player, targetPoint)
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
	ball.AssemblyLinearVelocity = direction * headerForce + Vector3.new(0, 8, 0)
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
	local isFastOrAerial = ballSpeed > LOOSE_BALL_PICKUP_MAX_SPEED or vertical > Config.AERIAL_PICKUP_HEIGHT
	if isFastOrAerial and getDribbleSkill(player) < (Config.TACKLE_FAST_BALL_MIN_DRIBBLE_SKILL / 100) then
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

	local distance = Config.PULSE_DASH_TACKLE_SPEED * qteDuration

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
	}
	tackleDashes[player] = dash

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

		local newPosition = dash.startPosition:Lerp(dash.endPosition, easedAlpha)
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
		if dash.isPulseDash and not dash.resolved then
			for _, other in ipairs(Players:GetPlayers()) do
				if other == player or not areOpponents(player, other) then continue end
				local _, otherRoot = getCharacterParts(other)
				if not otherRoot then continue end
				if (root.Position - otherRoot.Position).Magnitude <= (dash.hitboxRadius or 0) then
					dash.resolved = true
					applyPulseDashHit(player, other, dash)
					break
				end
			end
		end
	end
end)

Remotes.AttemptTackle.OnServerEvent:Connect(function(player, directionArg)
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
-- ⚠️ v86: a assistência de altura (v67/v84) que morava aqui saiu — ver o
-- comentário do v86 dentro de _G.PulseComputeShotTarget logo abaixo.

_G.PulseComputeShotTarget = function(player)
	-- ⚠️ v7 PEDIDO: "a mira da Hissatsu tem que ser EXATAMENTE onde o cara
	-- estiver mirando, igual o chute padrão" — se o cliente mandou um
	-- ponto de mira junto com o UsePulse (ver HissatsuInput.local.luau +
	-- _G.GetPulseAimPoint em PulseController.legacy.luau), usa ele direto,
	-- sem nenhuma mira automática. Só cai no canto automático abaixo se
	-- não tiver mira nenhuma guardada (ex: Pulso usado por outro caminho).
	-- ⚠️ v36 FIX — "a Hissatsu jogou a bola pra cima / pro nada".
	-- DIAGNÓSTICO (log do usuário): alvo=(687,-298,257) com a bola em
	-- (706,-185,258) — ou seja, a mira que o CLIENTE mandou apontava 113
	-- studs ABAIXO da bola, bem abaixo do gramado (-193). Como o chute de
	-- Hissatsu voa RETO e sem gravidade, ele saía atravessando o chão e
	-- viajava pra sempre (o log de voo passou de 1500 studs sem parar).
	--
	-- A causa raiz é no cliente (a mira devolve um ponto degenerado quando
	-- o raio do mouse não acerta nada), mas o servidor não pode aceitar uma
	-- mira dessas de qualquer jeito — nem por bug, nem por cliente
	-- adulterado. Aqui ela é SANEADA: a altura é presa a uma faixa
	-- razoável em volta da bola e, se sobrar uma mira sem direção
	-- horizontal nenhuma (mirou no próprio pé), cai na mira automática de
	-- canto logo abaixo.
	--
	-- ⚠️ v86 — PEDIDO: "remova o assistente de mira da hissatsu, apenas faça
	-- a mira funcionar corretamente [...] é só ir exatamente onde está
	-- apontado o mouse".
	-- O ponto que o cliente manda (ver computeAimPoint em HissatsuInput.
	-- local.luau) já é EXATAMENTE o que está sob o cursor, e aqui ele passa
	-- intocado: sem assistência de altura puxando pro travessão, sem teto de
	-- altura cortando mira alta. Só sobram duas travas que uma mira de
	-- verdade nunca aciona:
	--   • ponto mais de PULSE_AIM_MAX_DROP abaixo da bola (dentro do chão —
	--     o bug do v36) sobe até esse limite;
	--   • mira sem direção horizontal (mirou no próprio pé) sai reta pra
	--     frente do jogador — não mais pro canto automático do gol.
	local aimPoint = _G.GetPulseAimPoint and _G.GetPulseAimPoint(player)
	if typeof(aimPoint) == "Vector3" then
		local alturaMin = ball.Position.Y - Config.PULSE_AIM_MAX_DROP
		local alvo = Vector3.new(aimPoint.X, math.max(aimPoint.Y, alturaMin), aimPoint.Z)

		local horizontal = Vector3.new(alvo.X - ball.Position.X, 0, alvo.Z - ball.Position.Z).Magnitude
		if horizontal >= Config.PULSE_AIM_MIN_HORIZONTAL then
			return alvo
		end

		local _, root = getCharacterParts(player)
		if root then
			local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if frente.Magnitude > 0.01 then
				return ball.Position + frente.Unit * 50
			end
		end
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

		-- ⚠️ v38: a força começa a cair AGORA, enquanto o QTE de colisão
		-- roda — é a janela em que "o goleiro está defendendo".
		local encerrarDrenagem = beginGuardForceDrain(forcaNaColisao, getPhysical(player))

		local function finish(caught, rebate)
			-- ⚠️ v41: encerrarDrenagem devolve a força que SOBROU — é a vida
			-- com que a bola segue voando se tiver atravessado a guarda.
			local forcaRestante = encerrarDrenagem(caught)
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
			local started = _G.ConsumeGKGuardOnCollision(player, function(perfect, effect)
				-- Mesma regra do mergulho normal (Físico vs Força), só que
				-- agora com o bônus da Hissatsu somado (DiveRadiusAdd
				-- reaproveitado como reforço de "físico efetivo" pra ESSA
				-- defesa específica) e GuaranteedCatch garantindo na hora
				-- num Perfect muito bom.
				local boost = (effect and effect.DiveRadiusAdd) or 0
				local guaranteed = effect and effect.GuaranteedCatch
				local caught = guaranteed or (getPhysical(player) + boost >= forceRating)
				finish(caught, effect and effect.Rebate)
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

	if not deadBallMode then
		local degrees = getAimDeviationDegrees(player) * (aimDeviationMult or 1)
		direction = applyAimDeviation(direction, degrees)
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
		local gravity = workspace.Gravity

		local vFlat = flatDelta / arcTime
		local vy = (delta.Y + 0.5 * gravity * arcTime * arcTime) / arcTime
		velocity = Vector3.new(vFlat.X, vy, vFlat.Z)
	elseif useNormalArc then
		-- ⚠️ v8 PEDIDO: chute de INSTINTO usa a MESMA física do chute manual
		-- normal (arco com gravidade, Config.KICK_UPWARD_BOOST) — nada de
		-- voo reto sem gravidade nem número de força flutuando (isso é só
		-- do Pulso/Hissatsu, ver o `else` abaixo).
		velocity = direction * force
		velocity += Vector3.new(0, force * Config.KICK_UPWARD_BOOST, 0)
	else
		-- PEDIDO: chute/passe de Pulso vai RETO na direção do alvo — sem o
		-- probable boost pra cima do chute normal (Config.KICK_UPWARD_BOOST,
		-- que cria aquele arco leve) — e sem gravidade nenhuma puxando pra
		-- baixo até a bola perder a velocidade (ver startPulseStraightFlight
		-- lá em cima, perto do gravityForce).
		velocity = direction * force
		startPulseStraightFlight(force)
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
	applyCurve(spin ~= 0 and spin or nil, direction)

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
	-- aplicado EM CIMA de Energy+Kick, ANTES do multiplicador de tier do
	-- QTE (effect.ForceMult, que é o Bom/Perfect do Pulso) — depois disso
	-- ainda entra a queda de força por distância (MaxRange) e o chip do
	-- zagueiro, os dois só pros Pulsos de Chute.
	local rarityMult = (rarity and Config.PULSE_RARITY_POWER_MULT[rarity]) or 1
	local kickMult = getKickForceMultiplier(player)
	local energyMult = getEnergyForceMultiplier(player)
	local baseForce = Config.KICK_MAX_FORCE * kickMult * energyMult * rarityMult
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
			"💥 [Pulso] %s chutou (raridade %s): KickMax=%d x KickMult=%.2f x EnergyMult=%.2f x RarityMult=%.2f = base %d | x QTE=%.2f = %d | distância=%.1f/alcance %.0f -> fator=%.2f = %d | após chip do zagueiro = %d",
			player.Name, tostring(rarity),
			Config.KICK_MAX_FORCE, kickMult, energyMult, rarityMult, math.floor(baseForce),
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

	-- ⚠️ v86 — curva DESLIGADA no chute de Hissatsu (curveMult = nil). A curva
	-- automática do pulsePerformKick empurra a bola pro CENTRO do gol durante
	-- o voo — na prática uma assistência de mira, e o pedido foi "remova o
	-- assistente de mira [...] é só ir exatamente onde está apontado o mouse".
	-- O CurveMult continua nos dados (PulseInstinctData); pra religar, é só
	-- voltar a passar effect.CurveMult aqui.
	local kicked = pulsePerformKick(player, targetPoint, force, nil, aimMult, effect, Config.PULSE_SHOT_FORCE_CAP_MULT)

	-- ⚠️ v11: VanishSeconds (Pulso "Sumiço", vindo de Kamikakushi/Teleport
	-- Shot — no anime a bola SOME na frente do goleiro e reaparece perto da
	-- rede). Some só depois de um tempinho de voo, senão o próprio chutador
	-- não vê a bola sair do pé. O restore guarda a transparência ORIGINAL de
	-- cada pedaço e roda mesmo se a bola for resetada no meio (gol, saída),
	-- pra nunca sobrar uma bola invisível em campo.
	if kicked and effect.VanishSeconds and effect.VanishSeconds > 0 then
		local vanishing = ball
		local duration = effect.VanishSeconds
		task.delay(0.25, function()
			if not vanishing or not vanishing.Parent then return end
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
			end)
		end)
	end

	return kicked
end

-- ⚠️ v8 PEDIDO: "instintos não são como o pulso" — chute de INSTINTO
-- (ex: Chute Direto) usa a força normal de Kick (sem Energy, sem
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
	return pulsePerformKick(player, targetPoint, force, nil, aimMult, effect, nil, true) -- ⚠️ v86: sem curva, ver PulseExecuteShot
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
	if target then
		local toTarget = target - ball.Position
		if toTarget.Magnitude > 0.01 then direction = toTarget.Unit end
	end
	local headerForce = Config.HEADER_FORCE * (effect.HeaderForceMult or 1)
	direction = applyAimDeviation(direction, getAimDeviationDegrees(player) * 0.5)

	nudgeBallForwardForKick(direction) -- ⚠️ v21: já nasce fora do raio do corpo, na direção da cabeçada
	-- ⚠️ v21 FIX: removido o "ball.CanCollide = true" que existia aqui —
	-- ele cancelava na hora a janela de saída limpa (startKickClearance)
	-- aberta logo acima, então essa cabeçada de Pulso nunca se beneficiava dela.
	ball.AssemblyLinearVelocity = direction * headerForce + Vector3.new(0, 8, 0)
	playKickFeedback(headerForce)
	playAnimation(player, Config.ANIMATIONS.Header, nil, nil, true) -- ⚠️ v65: cabeçada (normal e de Hissatsu passam as duas por aqui)
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
	if not _G.PulseCanHeader(player, effect) then return false end
	if owner then return false end -- só bola SOLTA no ar — tirar de quem já controla é Tackle, não isso

	local _, root = getCharacterParts(player)
	if not root then return false end

	ball.CanCollide = true
	ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	ball.Position = root.Position + root.CFrame.LookVector * Config.DRIBBLE_OFFSET + Vector3.new(0, Config.DRIBBLE_HEIGHT_OFFSET, 0)

	setOwner(player)
	pushToucher(player)
	playAnimation(player, dribbleAnimationFor(nil), Enum.AnimationPriority.Action2, nil, true) -- ⚠️ v63: sem direção aqui (domínio), usa a neutra
	return true
end

_G.PulseExecuteTackle = function(player, effect)
	if isStunned(player) then return false end
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
	local distance = (Config.DRIBBLE_MOVE_MIN_DISTANCE
		+ (Config.DRIBBLE_MOVE_MAX_DISTANCE - Config.DRIBBLE_MOVE_MIN_DISTANCE) * skill) * (effect.DistanceMult or 1)
	local window = Config.DRIBBLE_ANIMATION_SECONDS -- ⚠️ v64: janela FIXA (= tempo da animação); a distância é que escala, logo a velocidade escala junto

	playAnimation(player, dribbleAnimationFor(bestName), Enum.AnimationPriority.Action2, window, true) -- ⚠️ v63: reprodução ajustada à janela

	local rangeBonus = (effect.AnkleRangeAdd or 0)
		+ (_G.GetPulseActiveAnkleRangeAdd and _G.GetPulseActiveAnkleRangeAdd(player) or 0)
	local stunBonus = effect.AnkleStunAdd or 0
	local hitOpponent = applyAnkleBreaker(player, root, rangeBonus, stunBonus, effect.AlwaysStun)
	local dashDistance = getMinidashBonusDistance(hitOpponent, skill)

	local endPosition = root.Position + direction * (distance + dashDistance)
	dribbleMoves[player] = {
		targetPosition = endPosition,
		startPosition = root.Position,
		endPosition = endPosition,
		triggeredAt = tick(),
		expiresAt = tick() + window,
	}
	setIframeGlow(player, true)
	Remotes.SuppressShiftLockRotation:FireClient(player, window)
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