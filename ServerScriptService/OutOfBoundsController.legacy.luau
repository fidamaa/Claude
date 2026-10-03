--[[
	OutOfBoundsController (Script)
	LOCAL: ServerScriptService

	Detecta quando a bola sai da CampoHIT e decide lateral / escanteio /
	tiro de meta. Pausa a partida, teleporta o cobrador forçadamente com a
	bola, e dá Config.SET_PIECE_TIME_LIMIT segundos pra ele agir — senão
	passe forçado automático pra frente dele.

	⚠️ REWORK (pedido): a detecção de bola fora agora usa PARTS FÍSICAS que
	você posiciona no Studio (ver Config.OUT_LATERAL_ZONE_NAME/
	OUT_FUNDO_ZONE_NAME em FootballConfig.lua pro nome exato e o que cada
	uma precisa) em vez de só matemática de eixo em cima do CampoHIT — o
	CampoHIT nem sempre bate exatamente com o gramado visual, então a
	detecção por parts fica mais fiel ao campo de verdade (e, por
	consequência, também deixa a área do gol mais exata: só conta bola
	fora se a bola realmente NÃO entrou no gol primeiro). Enquanto as
	parts de um tipo não existirem na cena, esse script cai sozinho pro
	cálculo antigo (por eixo) só pra esse tipo — não quebra nada até você
	posicionar as parts.

	FIX #2 (gol contando como bola fora, caso "chute forte" — TUNNELING):
	um chute forte o bastante anda mais por frame do que a profundidade da
	caixa do gol — a bola pode estar antes do gol num Heartbeat e já ter
	passado por trás dele no próximo, sem NUNCA ter sido vista "dentro" da
	caixa em nenhum frame específico (e o goalPart.Touched do
	MatchController pode falhar pelo mesmo motivo: colisão física rápida
	demais pra registrar toque). Resolvido trocando "a bola está dentro do
	gol agora?" por "o SEGMENTO de reta entre a posição do frame passado e
	a posição de agora cruza a caixa do gol?" (teste de interseção
	segmento-vs-caixa, método slab) — roda TODO Heartbeat, antes/
	independente da checagem de bola fora, senão um chute assim escaparia
	contando como escanteio/tiro de meta errado.

	IMPORTANTE: como esse caminho pode detectar um gol que o
	goalPart.Touched NUNCA viu, esse script precisa conseguir pontuar o gol
	ele mesmo — pra isso, o MatchController.lua expõe _G.RegisterGoal
	(scoringTeamName). Se essa global não existir, o script avisa via
	warn() e NÃO trata a saída como bola fora mesmo assim (evita cobrança
	de escanteio/tiro de meta errada em cima de um gol de verdade), mas o
	gol também não é contabilizado até você expor o hook.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local ball = workspace:WaitForChild(Config.BALL_NAME)
-- ⚠️ v24 — PEDIDO: "vou remover o campo hit... acabou". O campoHit causou
-- problema demais de novo (bola fora sendo detectada errado em cima de
-- chutes normais, pausando a partida) e a decisão foi tirar ele de vez.
-- Antes isso travaria o jogo inteiro aqui (WaitForChild espera pra
-- sempre se a Part não existir, e esse script inteiro nunca chegaria a
-- rodar nada — nem a detecção de GOL por tunelamento, que não depende do
-- campoHit). Agora campoHit é OPCIONAL: se não existir, esse script
-- continua normalmente, só que sem a detecção de bola fora "por eixo"
-- (fallback matemático) — lateral/escanteio/tiro de meta só funcionam se
-- você posicionar as parts OutLateral/OutFundo (ver Config). Gol continua
-- funcionando 100% do mesmo jeito, não depende de nenhum dos dois.
local campoHit = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
local blueGoal = workspace:WaitForChild(Config.BLUE_GOAL_NAME)
local yellowGoal = workspace:WaitForChild(Config.YELLOW_GOAL_NAME)
local goalPartsList = { blueGoal, yellowGoal }

local hasRealFieldHitbox = campoHit ~= nil -- guarda ANTES de eventualmente sintetizar um substituto lá embaixo

if not campoHit then
	warn(("⚠️ OutOfBoundsController: nenhuma part \"%s\" encontrada — rodando SEM detecção de bola fora por eixo (fallback matemático). Gol continua normal. Lateral/escanteio/tiro de meta só funcionam se as parts \"%s\"/\"%s\" existirem (ver Config)."):format(
		Config.FIELD_HITBOX_NAME, Config.OUT_LATERAL_ZONE_NAME, Config.OUT_FUNDO_ZONE_NAME))
end

-- ⚠️ v10 FIX: "durante o escanteio ou lateral, a bola era arremessada pra
-- fora em vez de ir ao campo" — CampoHIT/GolAzul/GolAmarelo são só
-- "caixas matemáticas" (posição/tamanho lidos em código), mas por padrão
-- todo Part novo no Studio nasce com CanQuery=true — então o raycast do
-- mouse.Hit (usado pra mirar QUALQUER chute, inclusive a cobrança de
-- escanteio/lateral) podia acertar uma dessas caixas invisíveis bem perto
-- da linha (exatamente onde você está parado numa cobrança) em vez do
-- gramado de verdade, gerando um ponto de mira sem sentido que mandava a
-- bola de volta pra fora. Mesmo fix que o GKAreaUtil.luau já tinha pras
-- Parts GKArea_*, só que essas três nunca tinham recebido.
-- ⚠️ v24: NÃO usa {campoHit, blueGoal, yellowGoal} direto numa table — se
-- campoHit for nil (ver acima), ele fica na posição 1 e o ipairs() para
-- ali mesmo (nil corta a sequência), pulando blueGoal/yellowGoal também.
-- Monta a lista só com o que existe de verdade, testando cada um à parte.
-- ⚠️ v23 FIX — PEDIDO: "sempre que eu estou com a câmera sobrescrevendo o
-- espaço de uma hitbox, sempre dá problema em tudo". O loop abaixo reforça
-- CanQuery/CanCollide = false nessas Parts pra sempre, a cada 2s — mesmo
-- padrão de auto-correção que o BallController.lua já usa pro
-- CollisionGroup da bola. Só entram as que realmente existem (v24: campoHit
-- agora é opcional — ver acima). As zonas OutLateral/OutFundo entram aqui
-- embaixo, depois de escaneadas (ver mais abaixo).
local watchedHitboxParts = {}
if campoHit then table.insert(watchedHitboxParts, campoHit) end
if blueGoal then table.insert(watchedHitboxParts, blueGoal) end
if yellowGoal then table.insert(watchedHitboxParts, yellowGoal) end
for _, part in ipairs(watchedHitboxParts) do
	part.CanQuery = false
	part.CanCollide = false
	-- ⚠️ v110: a CampoHIT estava com Anchored = false no place — no Play ela
	-- CAÍA com a gravidade e era destruída em segundos (sem colisão, nada
	-- segura), e tudo que usa a posição dela (lateral/escanteio, altura da
	-- cobrança, resgate da bola, formação, botão Reespawnar Bola) passava a
	-- ler uma caixa caindo / sumida. Hitbox nunca pode se mexer: ancora sempre.
	part.Anchored = true
end

if Config.OOB_HITBOX_WATCHDOG_ENABLED then
	task.spawn(function()
		while true do
			task.wait(2)
			for _, part in ipairs(watchedHitboxParts) do
				if part.CanQuery or part.CanCollide or not part.Anchored then
					part.CanQuery = false
					part.CanCollide = false
					part.Anchored = true
				end
			end
		end
	end)
end

local function getCharacterParts(player)
	local character = player.Character
	if not character then return nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then return nil end
	return character, root, humanoid
end

-- Teste de interseção SEGMENTO-DE-RETA vs. CAIXA (método slab), no espaço
-- local da PART recebida — funciona pra qualquer BasePart (gol OU zona de
-- bola fora). Quando fromPos == toPos (bola praticamente parada entre um
-- frame e outro) se comporta como um teste de ponto único, então não
-- perde nada pro caso "normal", só ganha cobertura pro caso de chute
-- rápido/tunelamento.
local function doesSegmentCrossBox(part, fromPos, toPos)
	local margin = ball.Size.X / 2 -- raio da bola, pra pegar o instante em que ela já está encostando
	local halfSize = part.Size / 2 + Vector3.new(margin, margin, margin)

	local partCFrame = part.CFrame
	local localFrom = partCFrame:PointToObjectSpace(fromPos)
	local localTo = partCFrame:PointToObjectSpace(toPos)
	local direction = localTo - localFrom

	local tMin, tMax = 0, 1

	local function clipAxis(originValue, dirValue, boxHalf)
		if math.abs(dirValue) < 1e-6 then
			return originValue >= -boxHalf and originValue <= boxHalf
		end
		local t1 = (-boxHalf - originValue) / dirValue
		local t2 = (boxHalf - originValue) / dirValue
		if t1 > t2 then t1, t2 = t2, t1 end
		tMin = math.max(tMin, t1)
		tMax = math.min(tMax, t2)
		return tMin <= tMax
	end

	if not clipAxis(localFrom.X, direction.X, halfSize.X) then return false end
	if not clipAxis(localFrom.Y, direction.Y, halfSize.Y) then return false end
	if not clipAxis(localFrom.Z, direction.Z, halfSize.Z) then return false end

	return true
end

-- Teste de PONTO dentro de uma caixa (espaço local da part) — usado pras
-- zonas de bola fora (zonas são "grossas"/compridas o bastante pra não
-- precisar do teste de segmento; se notar bola escapando por tunelamento
-- numa zona, é sinal de que ela precisa ser maior).
local function isPointInsideBox(part, worldPoint)
	local half = part.Size / 2
	local local_ = part.CFrame:PointToObjectSpace(worldPoint)
	return math.abs(local_.X) <= half.X and math.abs(local_.Y) <= half.Y and math.abs(local_.Z) <= half.Z
end

local function findContainingZone(zones, worldPoint)
	for _, zone in ipairs(zones) do
		if isPointInsideBox(zone, worldPoint) then
			return zone
		end
	end
	return nil
end

-- ⚠️ v24: sem campoHit de verdade, o resto do arquivo (cobrança de lateral/
-- escanteio/tiro de meta, quando tem zona OutLateral/OutFundo) ainda
-- precisa de UMA referência geométrica (campoHit.CFrame/.Position/.Size)
-- pra calcular pontos/eixos — em vez de reescrever cada um dos vários
-- lugares que usam campoHit.* espalhados pelo arquivo, sintetiza uma caixa
-- "virtual" (não é uma Part de verdade, não existe no Workspace, só serve
-- de referência matemática) a partir da posição dos dois gols. IMPORTANTE:
-- essa caixa NUNCA é usada pra decidir se a bola saiu por eixo (isso fica
-- travado por `hasRealFieldHitbox` lá embaixo em computeOutOfBoundsState)
-- — só pra não quebrar as contas de POSIÇÃO que dependem de campoHit.
if not campoHit then
	local midpoint = (blueGoal.Position + yellowGoal.Position) / 2
	local flatLook = Vector3.new(yellowGoal.Position.X - blueGoal.Position.X, 0, yellowGoal.Position.Z - blueGoal.Position.Z)
	if flatLook.Magnitude < 0.01 then flatLook = Vector3.new(0, 0, -1) end
	local fieldLength = flatLook.Magnitude
	campoHit = {
		CFrame = CFrame.lookAt(midpoint, midpoint + flatLook.Unit),
		Position = midpoint,
		Size = Vector3.new(math.max(fieldLength * 0.6, 40), 20, fieldLength + 20),
	}
end

local blueLocal = campoHit.CFrame:PointToObjectSpace(blueGoal.Position)
local yellowLocal = campoHit.CFrame:PointToObjectSpace(yellowGoal.Position)

local goalAxisIsX = math.abs(blueLocal.X - yellowLocal.X) >= math.abs(blueLocal.Z - yellowLocal.Z)

local function goalAxisValue(localPos)
	return goalAxisIsX and localPos.X or localPos.Z
end
local function touchAxisValue(localPos)
	return goalAxisIsX and localPos.Z or localPos.X
end
local function toLocalVector(goalCoord, touchCoord)
	if goalAxisIsX then
		return Vector3.new(goalCoord, 0, touchCoord)
	end
	return Vector3.new(touchCoord, 0, goalCoord)
end

local blueAtPositiveEnd = goalAxisValue(blueLocal) > goalAxisValue(yellowLocal)

local function defendingTeamOf(goalPart)
	local scoringTeam = goalPart:GetAttribute("ScoringTeam")
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if teamName ~= scoringTeam then
			return teamName
		end
	end
	return nil
end

local blueDefendingTeam = defendingTeamOf(blueGoal)
local yellowDefendingTeam = defendingTeamOf(yellowGoal)

local fieldHalfSize = campoHit.Size / 2
local goalHalf = goalAxisIsX and fieldHalfSize.X or fieldHalfSize.Z
local touchHalf = goalAxisIsX and fieldHalfSize.Z or fieldHalfSize.X
local groundWorldY = (campoHit.Position.Y - campoHit.Size.Y / 2) + Config.SET_PIECE_BALL_HEIGHT
local function getGroundWorldY()
	if _G.GetBallGroundY then
		return _G.GetBallGroundY() + Config.SET_PIECE_BALL_HEIGHT
	end
	return (campoHit.Position.Y - campoHit.Size.Y / 2) + Config.SET_PIECE_BALL_HEIGHT
end

local function otherTeam(teamName)
	for _, name in ipairs(Config.TEAM_NAMES) do
		if name ~= teamName then return name end
	end
	return Config.TEAM_NAMES[1]
end

-- ⚠️ v5.5 FIX: excludeGK evita que o GOLEIRO seja escolhido pra cobrar
-- lateral/escanteio — antes, "mais perto"/"melhor Chute" olhava TODO
-- mundo do time, então com poucos jogadores em campo (teste solo, por
-- exemplo) o goleiro acabava sendo "o mais perto" mesmo com a bola fora
-- do lado do campo adversário, e era teletransportado pra lá, deixando o
-- gol vazio. Se excluir o goleiro deixar a lista VAZIA (só ele em campo
-- naquele time), cai pro comportamento antigo — melhor o goleiro cobrar
-- do que a bola parada não ter ninguém.
local function getTeamPlayers(teamName, excludeGK)
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName and getCharacterParts(plr) then
			if excludeGK and plr:GetAttribute("Role") == "GK" then continue end
			table.insert(list, plr)
		end
	end
	return list
end

local function closestPlayerTo(teamName, worldPoint, excludeGK)
	local candidates = getTeamPlayers(teamName, excludeGK)
	if excludeGK and #candidates == 0 then
		candidates = getTeamPlayers(teamName, false)
	end

	local best, bestDist = nil, math.huge
	for _, plr in ipairs(candidates) do
		local _, root = getCharacterParts(plr)
		local dist = (root.Position - worldPoint).Magnitude
		if dist < bestDist then
			bestDist, best = dist, plr
		end
	end
	return best
end

-- ⚠️ NOVO: quem cobra TIRO DE META tem que ser o GOLEIRO de verdade (Role
-- == "GK") do time que defende, nunca "só quem tava mais perto do gol"
-- (podia ser qualquer jogador de linha que sobrou lá atrás por acaso).
local function goalkeeperOf(teamName)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName and plr:GetAttribute("Role") == "GK" and getCharacterParts(plr) then
			return plr
		end
	end
	return nil
end

-- Quem cobra escanteio é quem tem o melhor Chute do time (cobrança de
-- escanteio é um chute de longa distância/precisão). ⚠️ v5.5: excludeGK
-- pelo mesmo motivo de closestPlayerTo acima — goleiro não cobra
-- escanteio (só cai pra ele se for o único jogador daquele time em campo).
local function bestCrosserOf(teamName, excludeGK)
	local candidates = getTeamPlayers(teamName, excludeGK)
	if excludeGK and #candidates == 0 then
		candidates = getTeamPlayers(teamName, false)
	end

	local best, bestSkill = nil, -1
	for _, plr in ipairs(candidates) do
		local skill = plr:GetAttribute(Config.KICK_ATTRIBUTE)
		if typeof(skill) ~= "number" then skill = Config.DEFAULT_KICK end
		if skill > bestSkill then
			bestSkill, best = skill, plr
		end
	end
	return best
end

-- ===== ZONAS DE BOLA FORA (parts posicionadas no Studio) =====
local function scanZones(zoneName)
	local list = {}
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Name == zoneName and inst:IsA("BasePart") then
			-- ⚠️ v10 FIX: mesmo motivo do campoHit/gols acima — essas Parts de
			-- OutLateral/OutFundo ficam EXATAMENTE onde o jogador para pra
			-- cobrar lateral/escanteio, então são as maiores suspeitas de
			-- atrapalhar o mouse.Hit (mira) e a câmera bem na hora da
			-- cobrança.
			inst.CanQuery = false
			inst.CanCollide = false
			table.insert(list, inst)
		end
	end
	return list
end

local lateralZones = scanZones(Config.OUT_LATERAL_ZONE_NAME)
local fundoZones = scanZones(Config.OUT_FUNDO_ZONE_NAME)
local useLateralZones = #lateralZones > 0
local useFundoZones = #fundoZones > 0

-- entram no mesmo watchdog de CanQuery/CanCollide declarado acima (v23)
for _, zone in ipairs(lateralZones) do table.insert(watchedHitboxParts, zone) end
for _, zone in ipairs(fundoZones) do table.insert(watchedHitboxParts, zone) end

if not useLateralZones then
	warn(("⚠️ OutOfBoundsController: nenhuma part \"%s\" encontrada — %s"):format(Config.OUT_LATERAL_ZONE_NAME,
		hasRealFieldHitbox and "usando o cálculo antigo (eixo do CampoHIT) pra lateral. Posicione as parts (ver comentário em Config.OUT_LATERAL_ZONE_NAME) pra detecção ficar mais exata."
			or "e sem CampoHIT também (v24) — bola fora de lateral NÃO é detectada até você posicionar essa part."))
end
if not useFundoZones then
	warn(("⚠️ OutOfBoundsController: nenhuma part \"%s\" encontrada — %s"):format(Config.OUT_FUNDO_ZONE_NAME,
		hasRealFieldHitbox and "usando o cálculo antigo (eixo do CampoHIT) pra escanteio/tiro de meta. Posicione as parts (ver comentário em Config.OUT_FUNDO_ZONE_NAME) pra detecção ficar mais exata."
			or "e sem CampoHIT também (v24) — escanteio/tiro de meta NÃO é detectado até você posicionar essa part."))
end
for _, zone in ipairs(fundoZones) do
	if not zone:GetAttribute(Config.OUT_FUNDO_TEAM_ATTRIBUTE) then
		warn(("⚠️ OutOfBoundsController: a part \"%s\" não tem o Attribute \"%s\" definido (\"Azul\" ou \"Amarelo\") — ela vai ser tratada como se não existisse."):format(zone:GetFullName(), Config.OUT_FUNDO_TEAM_ATTRIBUTE))
	end
end

-- Retorna: isOut (bool), overGoalLine (bool, true = fundo/escanteio-ou-
-- tiro-de-meta, false = lateral), fundoZone (a part "OutFundo" que a bola
-- está dentro, se detectada por zona — nil se foi pelo cálculo antigo).
local function computeOutOfBoundsState()
	local fundoZone = useFundoZones and findContainingZone(fundoZones, ball.Position) or nil
	local lateralZone = (not fundoZone) and useLateralZones and findContainingZone(lateralZones, ball.Position) or nil

	if fundoZone or lateralZone then
		return true, fundoZone ~= nil, fundoZone
	end

	if useFundoZones and useLateralZones then
		return false, false, nil -- as duas zonas existem e a bola não está em nenhuma: dentro do campo
	end

	-- Fallback matemático (CampoHIT) só pro(s) tipo(s) ainda sem zona — e só
	-- se existir um CampoHIT DE VERDADE (v24: sem ele, esse fallback fica
	-- desligado de propósito, em vez de usar a caixa sintética acima, que
	-- não representa o campo real e daria falso positivo toda hora).
	if not hasRealFieldHitbox then
		return false, false, nil
	end

	local localBall = campoHit.CFrame:PointToObjectSpace(ball.Position)
	local ballGoalCoord = goalAxisValue(localBall)
	local ballTouchCoord = touchAxisValue(localBall)

	if not useFundoZones and math.abs(ballGoalCoord) > goalHalf then
		return true, true, nil
	end
	if not useLateralZones and math.abs(ballTouchCoord) > touchHalf then
		return true, false, nil
	end
	return false, false, nil
end

-- ⚠️ FIX (escanteio/lateral: cobrador conseguindo se mover livremente):
-- travar só via Humanoid.WalkSpeed = 0 aqui NÃO bastava — PlayerSystems.lua
-- tem um Heartbeat próprio que "refresca" o WalkSpeed todo frame (sprint/
-- Pulso/Instinto), e também reseta o WalkSpeed toda vez que o jogador
-- começa/solta a carga do chute (Remotes.UpdateKickCharging) — exatamente
-- o que acontece ao COBRAR o escanteio. Os dois pontos só respeitavam
-- isStunned(player), nunca esse freeze de bola parada, então o freeze
-- durava só até o cobrador apertar o botão do chute (que é o próprio ato
-- de cobrar!), daí ele saía andando livre. _G.IsSetPieceFrozen expõe esse
-- estado pra PlayerSystems.lua checar do mesmo jeito que já checa stun.
local frozenTakers = {}
_G.IsSetPieceFrozen = function(player)
	return frozenTakers[player] == true
end

Players.PlayerRemoving:Connect(function(player)
	frozenTakers[player] = nil
end)

local handlingDeadBall = false

-- setPieceType: "ThrowIn" | "Corner" | "GoalKick"
local function runSetPiece(takerTeam, worldSpot, setPieceType)
	handlingDeadBall = true
	-- ⚠️ v124: desliga o voo travado da Hissatsu/curvas antes de tudo (senão a bola
	-- volta pra reta do chute e sai de novo em loop — ver _G.CancelarVooDaBola)
	if _G.CancelarVooDaBola then _G.CancelarVooDaBola() end
	-- ⚠️ v30: apito de bola fora (ver Config.SOUNDS.Whistle).
	if _G.PlayWhistle then _G.PlayWhistle() end
	_G.SetMatchPaused(true)
	_G.SetDeadBallMode(true)
	_G.ReleaseBallOwner()   -- encerra a posse de quem chutou a bola fora, sempre

	local taker
	if setPieceType == "GoalKick" then
		-- ⚠️ FIX: era closestPlayerTo (qualquer jogador de linha perto do
		-- gol podia ser "escolhido"), agora é sempre o GOLEIRO de verdade.
		taker = goalkeeperOf(takerTeam)
		if not taker then
			-- Sem goleiro humano: quem seguraria o gol é o GKBOT (ver
			-- GKBotController.lua) — ele não é um Player, então não dá pra
			-- teleportar/congelar ele pelo fluxo humano abaixo. Em vez
			-- disso, entrega a bola direto pro bot repor o jogo sozinho
			-- (mesma lógica de "agarrou e lança pra alguém" que ele já usa
			-- depois de uma defesa) e encerra a bola parada na hora.
			if _G.GKBotTakeGoalKick and _G.GKBotTakeGoalKick(takerTeam, worldSpot) then
				_G.SetDeadBallMode(false)
				_G.SetMatchPaused(false)
				handlingDeadBall = false
				return
			end
			-- Nem goleiro humano nem bot (não devia acontecer) — cai pro
			-- comportamento antigo só pra não travar a partida.
			taker = closestPlayerTo(takerTeam, worldSpot)
		end
	else
		-- ⚠️ v5.5 FIX: excludeGK=true — goleiro nunca cobra lateral/
		-- escanteio (ver comentário em getTeamPlayers acima).
		taker = (setPieceType == "Corner") and bestCrosserOf(takerTeam, true) or closestPlayerTo(takerTeam, worldSpot, true)
	end

	if not taker then
		-- ⚠️ v6.5: PEDIDO — "quando a bola sai e ninguém joga, ela precisa
		-- ser lançada pro centro do mapa automaticamente, para caso alguém
		-- saia cobrando, ou não tenha gente pra cobrar. o timer precisa
		-- parar até o lançamento... ser realizado". Antes esse ramo (SEM
		-- cobrador nenhum disponível) só largava a bola parada no lugar e
		-- despausava — agora replica o mesmo lançamento automático em
		-- direção ao centro do campo que o timeout (acted=false, abaixo)
		-- já usa. O timer já está pausado desde o início desta função
		-- (_G.SetMatchPaused(true) lá em cima) e só volta a rodar DEPOIS do
		-- lançamento, logo abaixo.
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CanCollide = true
		ball.CFrame = CFrame.new(worldSpot)
		local towardCenter = Vector3.new(campoHit.Position.X, ball.Position.Y, campoHit.Position.Z) - ball.Position
		local direction = towardCenter.Magnitude > 0.01 and towardCenter.Unit or Vector3.new(0, 0, 1)
		ball.AssemblyLinearVelocity = direction * Config.SET_PIECE_AUTO_LAUNCH_FORCE + Vector3.new(0, 3, 0)
		_G.SetDeadBallMode(false)
		_G.SetMatchPaused(false)
		handlingDeadBall = false
		return
	end

	-- PEDIDO: freeze (StunPlayer) REMOVIDO de todo mundo que não está
	-- cobrando — só o próprio cobrador fica "preso" (ver freezeTaker
	-- abaixo); adversários e companheiros ficam livres pra se reposicionar
	-- normalmente enquanto a bola está parada, sem congelar a partida
	-- inteira.

	local _, root, takerHumanoid = getCharacterParts(taker)
	if not root then
		-- ⚠️ v6.5: mesmo caso acima (sem cobrador utilizável) — o "taker"
		-- existe mas o personagem dele não está carregado/vivo no momento.
		-- Mesmo lançamento automático rumo ao centro, em vez de deixar a
		-- bola largada parada.
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CanCollide = true
		ball.CFrame = CFrame.new(worldSpot)
		local towardCenter = Vector3.new(campoHit.Position.X, ball.Position.Y, campoHit.Position.Z) - ball.Position
		local direction = towardCenter.Magnitude > 0.01 and towardCenter.Unit or Vector3.new(0, 0, 1)
		ball.AssemblyLinearVelocity = direction * Config.SET_PIECE_AUTO_LAUNCH_FORCE + Vector3.new(0, 3, 0)
		_G.SetDeadBallMode(false)
		_G.SetMatchPaused(false)
		handlingDeadBall = false
		return
	end

	root.CFrame = CFrame.lookAt(worldSpot, Vector3.new(campoHit.Position.X, worldSpot.Y, campoHit.Position.Z))
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = CFrame.new(worldSpot)
	_G.SetBallOwnerForced(taker)

	-- PEDIDO: lateral/escanteio continuam prendendo o cobrador no lugar
	-- (senão ele sairia andando com a bola em vez de cobrar) — TIRO DE
	-- META é exceção: normalmente é o próprio GOLEIRO quem cobra, e agora
	-- ele pode se mover livremente, até sair da área, pra se posicionar
	-- melhor antes de bater. O cronômetro de segurança (SET_PIECE_TIME_
	-- LIMIT) roda igual nos dois casos — se não agir a tempo, sofre o
	-- lançamento forçado automático de sempre.
	local freezeTaker = setPieceType ~= "GoalKick"
	local originalWalkSpeed = takerHumanoid.WalkSpeed
	if freezeTaker then
		frozenTakers[taker] = true
		takerHumanoid.WalkSpeed = 0
	end

	local startTime = tick()
	local acted = false
	while tick() - startTime < Config.SET_PIECE_TIME_LIMIT do
		task.wait(0.1)
		if _G.GetBallOwner() ~= taker then
			acted = true
			break
		end
	end

	if freezeTaker then
		frozenTakers[taker] = nil
		local _, _, currentTakerHumanoid = getCharacterParts(taker)
		if currentTakerHumanoid then
			currentTakerHumanoid.WalkSpeed = originalWalkSpeed
		end
	end

	if not acted then
		_G.ReleaseBallOwner()
		ball.CanCollide = true
		local towardCenter = Vector3.new(campoHit.Position.X, ball.Position.Y, campoHit.Position.Z) - ball.Position
		local direction = towardCenter.Magnitude > 0.01 and towardCenter.Unit or Vector3.new(0, 0, 1)
		ball.AssemblyLinearVelocity = direction * Config.SET_PIECE_AUTO_LAUNCH_FORCE + Vector3.new(0, 3, 0)
	end

	_G.SetDeadBallMode(false)
	_G.SetMatchPaused(false)
	handlingDeadBall = false
end

-- ⚠️ v84 — PEDIDO: "impeça que o goleiro e o GK BOT possam fazer gol
-- contra". Quando o MatchController anula um gol contra do goleiro/bot, o
-- jogo recomeça com TIRO DE META pro time dele — o mesmo tiro de meta de
-- bola fora pela linha de fundo (mesmo ponto seguro, mesmo cobrador:
-- goleiro humano, ou o GK BOT se não tiver humano). Devolve false se já
-- houver uma bola parada em andamento.
_G.AwardGoalKick = function(defendingTeam)
	if handlingDeadBall then return false end
	if not (campoHit and goalAxisIsX ~= nil) then return false end
	local golNaPontaPositiva = (defendingTeam == blueDefendingTeam) == blueAtPositiveEnd
	local goalSign = golNaPontaPositiva and 1 or -1
	local localSpot = toLocalVector(goalSign * (goalHalf - Config.GOAL_KICK_INSET - Config.GOAL_KICK_SAFE_OFFSET), 0)
	local worldSpot = campoHit.CFrame:PointToWorldSpace(localSpot)
	worldSpot = Vector3.new(worldSpot.X, getGroundWorldY(), worldSpot.Z)
	task.spawn(runSetPiece, defendingTeam, worldSpot, "GoalKick")
	return true
end

local wasInBounds = true
local lastBallPosition = ball.Position -- rastreado a cada Heartbeat, pro teste de segmento do gol (FIX #2)

RunService.Heartbeat:Connect(function()
	-- Sempre atualiza a posição rastreada, MESMO durante bola parada —
	-- assim, quando a bola volta a se mexer, o "segmento" começa do
	-- ponto real onde ela estava, não de um valor velho de antes da
	-- cobrança (o que geraria falsos positivos gigantes de "cruzou o gol").
	local previousBallPosition = lastBallPosition
	lastBallPosition = ball.Position

	if handlingDeadBall then return end

	-- 1) GOL por tunelamento — roda SEMPRE, independente das zonas de bola
	--    fora, senão um chute forte demais escaparia contando como
	--    escanteio/tiro de meta errado.
	for _, goalPart in ipairs(goalPartsList) do
		if doesSegmentCrossBox(goalPart, previousBallPosition, ball.Position) then
			local scoringTeam = goalPart:GetAttribute("ScoringTeam")
			if scoringTeam and _G.RegisterGoal then
				_G.RegisterGoal(scoringTeam)
			elseif scoringTeam then
				warn("OutOfBoundsController detectou um gol (via checagem de segmento) que o goalPart.Touched não pegou, mas _G.RegisterGoal não existe. Exponha a função de pontuação em MatchController.lua.")
			end
			wasInBounds = true
			return
		end
	end

	-- 2) Bola fora (zonas OutLateral/OutFundo, com fallback matemático)
	local isOut, overGoalLine, fundoZone = computeOutOfBoundsState()

	if not isOut then
		wasInBounds = true
		return
	end

	if not wasInBounds then return end
	wasInBounds = false

	-- ⚠️ v23 — PEDIDO: "se eu coloco o campohit deixa de funcionar". Uma
	-- hipótese forte: campoHit tem tamanho/posição que não cobre o campo de
	-- verdade, e chutes NORMAIS (não fora de campo nenhuma) estão sendo
	-- classificados como bola fora — o que PAUSA A PARTIDA inteira
	-- (SetMatchPaused/DeadBallMode logo abaixo), sentindo exatamente como
	-- "trava". Este print mostra, toda vez que isso disparar, se foi por
	-- ZONA (OutLateral/OutFundo — parts manuais) ou pelo CÁLCULO MATEMÁTICO
	-- em cima do campoHit — e nesse 2º caso, a coordenada da bola vs. o
	-- limite calculado, pra dar pra saber na hora se o campoHit está do
	-- tamanho certo.
	if not fundoZone then
		local localBall = campoHit.CFrame:PointToObjectSpace(ball.Position)
		warn(("⚠️ OutOfBoundsController: bola fora detectada pelo CÁLCULO DO CAMPOHIT (sem zona) — %s: coordenada da bola = %.1f, limite (metade do campoHit nesse eixo) = %.1f. Se isso disparou num chute NORMAL, dentro do campo de verdade, o campoHit está menor/deslocado do que devia — ajusta o tamanho/posição dele no Studio."):format(
			overGoalLine and "linha de fundo/gol" or "linha lateral",
			overGoalLine and goalAxisValue(localBall) or touchAxisValue(localBall),
			overGoalLine and goalHalf or touchHalf))
	end

	local lastToucher = _G.GetBallTouchers and _G.GetBallTouchers()

	if overGoalLine then
		-- ⚠️ v6.2: PEDIDO — "joguei pra fora da minha própria área... e GK
		-- inimigo apareceu no MEU gol pra cobrar tiro de meta, sendo que
		-- deveria ser escanteio". Causa raiz: quando existe uma Part
		-- "OutFundo" (zona posicionada no Studio) na ponta por onde a bola
		-- saiu, `defendingTeam` vinha DIRETO do Attribute dela (um texto
		-- digitado à mão no Studio, "Azul"/"Amarelo") — se esse Attribute
		-- estiver com o time TROCADO (erro de digitação, fácil de acontecer
		-- e o script só avisava se estivesse faltando, nunca se estivesse
		-- simplesmente ERRADO), o jogo achava que o time que defende
		-- aquele lado é o outro, e tudo desandava a partir daí: achava que
		-- quem tocou por último (você, no seu próprio time) NÃO era o time
		-- que defende ali → não contava como escanteio → virava tiro de
		-- meta → e o "goleiro que defende aquele lado" (agora, por engano,
		-- o time ADVERSÁRIO) aparecia bem no SEU gol.
		--
		-- Agora o time que defende cada lado é SEMPRE calculado pela
		-- POSIÇÃO REAL dos gols (igual o cálculo antigo, que nunca dependia
		-- de nenhum Attribute digitado à mão) — o Attribute da zona
		-- "OutFundo", se existir, só é usado como CONFERÊNCIA: se ele bater
		-- com a posição real, ótimo; se não bater, um aviso aparece no
		-- Output dizendo QUAL zona está com o Attribute errado (pra você
		-- corrigir no Studio), mas o jogo já segue com o lado calculado
		-- pela posição real, que não pode estar errado.
		local localBallSide = campoHit.CFrame:PointToObjectSpace(ball.Position)
		local exitAtPositiveEnd = goalAxisValue(localBallSide) > 0
		local defendingTeam = (exitAtPositiveEnd == blueAtPositiveEnd) and blueDefendingTeam or yellowDefendingTeam
		local goalSign = exitAtPositiveEnd and 1 or -1

		if fundoZone then
			local zoneDefendingTeam = fundoZone:GetAttribute(Config.OUT_FUNDO_TEAM_ATTRIBUTE)
			if zoneDefendingTeam and zoneDefendingTeam ~= defendingTeam then
				warn(("⚠️ OutOfBoundsController: a part \"%s\" tem o Attribute \"%s\" = \"%s\", mas pela POSIÇÃO dela (comparada aos gols de verdade) quem defende esse lado é \"%s\" — corrija o Attribute no Studio. Usando o lado calculado pela posição real por enquanto (mais confiável que o Attribute)."):format(fundoZone:GetFullName(), Config.OUT_FUNDO_TEAM_ATTRIBUTE, tostring(zoneDefendingTeam), tostring(defendingTeam)))
			end
		end

		local attackingTeam = otherTeam(defendingTeam)

		local touchTeam = lastToucher and lastToucher.Team and lastToucher.Team.Name
		local isCorner = touchTeam == defendingTeam

		local localBall = campoHit.CFrame:PointToObjectSpace(ball.Position)
		local touchSign = touchAxisValue(localBall) >= 0 and 1 or -1

		local localSpot, spotTeam, setPieceType
		if isCorner then
			localSpot = toLocalVector(goalSign * (goalHalf - Config.CORNER_ARC_INSET), touchSign * (touchHalf - Config.CORNER_ARC_INSET))
			spotTeam = attackingTeam
			setPieceType = "Corner"
		else
			-- ⚠️ FIX (gol contra no tiro de meta): GOAL_KICK_INSET sozinho
			-- podia deixar o ponto perto/sobrepondo a hitbox do próprio
			-- gol — e o TELEPORTE da bola pra lá já contava como toque
			-- (goalPart.Touched dispara em overlap por teleporte). Soma
			-- GOAL_KICK_SAFE_OFFSET em cima, empurrando bem mais pra
			-- dentro do campo, sempre.
			localSpot = toLocalVector(goalSign * (goalHalf - Config.GOAL_KICK_INSET - Config.GOAL_KICK_SAFE_OFFSET), 0)
			spotTeam = defendingTeam
			setPieceType = "GoalKick"
		end

		local worldSpot = campoHit.CFrame:PointToWorldSpace(localSpot)
		worldSpot = Vector3.new(worldSpot.X, getGroundWorldY(), worldSpot.Z)
		runSetPiece(spotTeam, worldSpot, setPieceType)
	else
		local touchTeam = lastToucher and lastToucher.Team and lastToucher.Team.Name
		local throwInTeam = otherTeam(touchTeam)
		local setPieceType = "ThrowIn"

		-- ⚠️ NOVO: PEDIDO — "se a bola sair do campohit, as vezes ela vai
		-- por cima por conta da pulso, ela precisa voltar ao goleiro do
		-- oponente de quem usou a pulso". Se a bola saiu pela LATERAL logo
		-- depois de um chute de Pulso de verdade (Hissatsu de CHUTE — só
		-- _G.PulseExecuteShot marca isso, nunca passe/drible/tackle),
		-- ignora a regra normal de lateral (jogador mais perto do time
		-- adversário de quem tocou por último) e manda pro GOLEIRO do time
		-- OPOSTO a quem chutou o Pulso, igual um tiro de meta de verdade
		-- (runSetPiece com "GoalKick" já prioriza o goleiro humano e cai
		-- pro GKBOT sozinho se não tiver um — ver função acima).
		local pulseInfo = _G.GetLastPulseShotInfo and _G.GetLastPulseShotInfo()
		if pulseInfo and pulseInfo.Team and (tick() - pulseInfo.At) <= Config.PULSE_OUT_OF_BOUNDS_WINDOW then
			throwInTeam = otherTeam(pulseInfo.Team)
			setPieceType = "GoalKick"
		end

		local localBall = campoHit.CFrame:PointToObjectSpace(ball.Position)
		local touchSign = touchAxisValue(localBall) >= 0 and 1 or -1
		local localSpot = toLocalVector(goalAxisValue(localBall), touchSign * (touchHalf - Config.THROW_IN_INSET))
		local worldSpot = campoHit.CFrame:PointToWorldSpace(localSpot)
		worldSpot = Vector3.new(worldSpot.X, getGroundWorldY(), worldSpot.Z)
		runSetPiece(throwInTeam, worldSpot, setPieceType)
	end
end)

print("✅ OutOfBoundsController carregado.")
