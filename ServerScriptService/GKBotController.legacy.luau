--[[
	GKBotController (Script)
	LOCAL: ServerScriptService (place Game)

	Substitui o goleiro por um BOT quando nenhum jogador humano do time
	está com Role == "GK" — a menos que Config.CLOSED_TEAM_MODE esteja
	true (aí o gol fica vazio de propósito, forçando alguém a escolher
	ser GK; ver comentário em FootballConfig.lua).

	PRECISA CRIAR NO STUDIO: 1 Model chamado exatamente "GKBot" (ver
	Config.GKBOT_TEMPLATE_NAME) dentro de ServerStorage — com um Humanoid
	+ HumanoidRootPart dentro, igual um NPC comum. Esse script CLONA esse
	molde por time (GKBot_Azul / GKBot_Amarelo) sempre que precisar, e
	destrói o clone assim que um jogador de verdade assume o gol daquele
	time.

	OPCIONAL (recomendado): 1 Part invisível "GKArea_<Time>" (mesma que
	GKAreaUtil.lua já usa pro goleiro humano) — se existir, o bot fica
	andando de um lado pro outro DENTRO dela, seguindo a bola. Sem ela,
	o bot só desliza lateralmente perto do próprio gol (fallback).

	O bot NÃO é um Player — ele fica de fora de todo o sistema normal de
	posse/chute/drible (que é indexado por Player), então tem sua própria
	IA simplificada aqui:

	1) MOVIMENTO: o bot anda de verdade agora (⚠️ antes era WalkSpeed = 0,
	   estático) — segue a bola lateralmente, sempre dentro da própria
	   área (ou perto do gol, sem a Part da área).

	2) REAÇÃO (2 gatilhos, iguais aos de antes):
	   a) Adversário com a bola chega a menos de GKBOT_CATCH_APPROACH_RADIUS
	      studs do bot.
	      b) Bola solta (sem dono) cuja trajetória prevista passa a menos de
	      GKBOT_SHOT_REACT_RADIUS studs do bot, dentro do alcance de reação.
	   Em QUALQUER um dos 2 casos, o bot agora SEMPRE tenta AGARRAR
	   primeiro (⚠️ NOVO) — só cai pro "repelir" (comportamento antigo,
	   afastar a bola pra longe) se a tentativa de agarrar falhar. A
	   chance de agarrar depende da distância (quanto mais perto, mais
	   fácil) e do ângulo (bola chegando de um ângulo muito fechado/por
	   trás = falha automática, "ele não consegue se for muito distante a
	   bola, tipo no ângulo").

	3) AGARROU: segura a bola ~GKBOT_HOLD_DURATION segundos parado, depois
	   lança com velocidade calculada (física de projétil de verdade, não
	   força fixa) pra alcançar um alvo — um companheiro de time que
	   pediu passe (tecla T, Attribute WantsPass — ver
	   PassRequestController.lua) tem PRIORIDADE; sem ninguém pedindo,
	   escolhe um companheiro aleatório; sem ninguém em campo, lança
	   campo adentro.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))

local ball = workspace:WaitForChild(Config.BALL_NAME)

-- Mesmos helpers de gol/time do BallController.lua (arquivos diferentes,
-- sem módulo compartilhado — mantenha em sincronia se mudar um dos dois).
local blueGoalPart = workspace:WaitForChild(Config.BLUE_GOAL_NAME, 5)
local yellowGoalPart = workspace:WaitForChild(Config.YELLOW_GOAL_NAME, 5)

local function otherTeamName(teamName)
	for _, t in ipairs(Config.TEAM_NAMES) do
		if t ~= teamName then return t end
	end
	return nil
end

local function enemyGoalOf(teamName)
	if blueGoalPart and blueGoalPart:GetAttribute("ScoringTeam") == teamName then return blueGoalPart end
	if yellowGoalPart and yellowGoalPart:GetAttribute("ScoringTeam") == teamName then return yellowGoalPart end
	return nil
end

local function ownGoalOf(teamName)
	local enemyTeam = otherTeamName(teamName)
	if not enemyTeam then return nil end
	return enemyGoalOf(enemyTeam)
end

local function hasHumanGK(teamName)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName and plr:GetAttribute("Role") == "GK" then
			return true
		end
	end
	return false
end

local function teamPlayerCount(teamName)
	local count = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName then
			count += 1
		end
	end
	return count
end

-- ⚠️ NOVO: PEDIDO — "o GK tem em base todos os status juntos de todos os
-- jogadores do campo, dividido pelo numero de jogadores e de status, como
-- físico e energia. tipo, se todo mundo tem 10 em cada atributo, o físico
-- do GK vai ser 10." Média do atributo entre TODOS os jogadores com time
-- (os dois lados, goleiros humanos inclusos) — é um "nível geral da
-- partida", não uma média só do próprio time. Sem ninguém em campo ainda,
-- cai pro Default do próprio atributo (igual um jogador sem o Attribute
-- setado).
local function averageFieldAttribute(attributeName, defaultValue)
	local total, count = 0, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team then
			local value = plr:GetAttribute(attributeName)
			if typeof(value) ~= "number" then value = defaultValue end
			total += math.clamp(value, 0, 100)
			count += 1
		end
	end
	if count == 0 then return defaultValue end
	return total / count
end

local function getGKBotPhysical()
	return averageFieldAttribute(Config.PHYSICAL_ATTRIBUTE, Config.DEFAULT_PHYSICAL)
end

local function getGKBotEnergy()
	return averageFieldAttribute(Config.ENERGY_ATTRIBUTE, Config.DEFAULT_ENERGY)
end

_G.GetGKBotPhysical = getGKBotPhysical
_G.GetGKBotEnergy = getGKBotEnergy

-- ===== PULSO DE GOLEIRO DO BOT (raridade calculada pelo campo) =====
-- ⚠️ NOVO: PEDIDO — "todo GK_BOT vai ter um pulso com base nas raridades
-- de todos os jogadores... se tiver 3 jogadores com pulsos épicos, 1
-- comum, 1 mítico e 1 lendário, vai ter pulso de goleiro lendário/épico,
-- se não existir pulso comum, ou raro, peguei o próximo da mais baixa
-- raridade". Só existem Pulsos de goleiro (RoleRequired="GK") em
-- Legendary/Mythic hoje (Mão Divina/Guardião Absoluto) — a busca abaixo é
-- genérica pra continuar funcionando se algum dia existir um GK Common/
-- Rare/Epic também.
local function findGKPulseDef(rarity)
	for _, def in ipairs(PulseData.Pulses) do
		if def.RoleRequired == "GK" and def.Rarity == rarity then
			return def
		end
	end
	return nil
end

local function pickGKPulseForRarity(targetRarity)
	local direct = findGKPulseDef(targetRarity)
	if direct then return direct end

	local order = Config.PULSE_RARITY_ORDER
	local targetIndex = 1
	for i, name in ipairs(order) do
		if name == targetRarity then
			targetIndex = i
			break
		end
	end

	-- "peguei o próximo da mais baixa raridade" — procura pra BAIXO
	-- primeiro (a raridade mais fraca mais próxima que EXISTE no pool de
	-- GK); só sobe se não existir NADA abaixo (pool de GK sem nenhuma
	-- raridade menor que a raridade mirada).
	for i = targetIndex - 1, 1, -1 do
		local def = findGKPulseDef(order[i])
		if def then return def end
	end
	for i = targetIndex + 1, #order do
		local def = findGKPulseDef(order[i])
		if def then return def end
	end
	return nil
end

-- Raridade "moda" (mais comum) entre os Pulsos equipados (os 2 slots) de
-- TODOS os jogadores em campo, dos dois times — igual Physical/Energy
-- acima, não é por time.
local function computeFieldPulseRarity()
	local counts = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team then
			for slot = 1, 2 do
				local name = _G.GetEquippedPulse and _G.GetEquippedPulse(plr, slot)
				if name then
					if PulseData.ResolveName then
						name = PulseData.ResolveName(name)
					end
					for _, def in ipairs(PulseData.Pulses) do
						if def.Name == name and def.Rarity then
							counts[def.Rarity] = (counts[def.Rarity] or 0) + 1
							break
						end
					end
				end
			end
		end
	end

	local bestRarity, bestCount = nil, 0
	for _, rarityName in ipairs(Config.PULSE_RARITY_ORDER) do
		local count = counts[rarityName] or 0
		if count > bestCount then
			bestCount = count
			bestRarity = rarityName
		end
	end
	return bestRarity or "Common"
end


-- Direção "pro campo" (do próprio gol até o gol adversário), estável
-- mesmo que a Part do gol esteja virada de qualquer jeito no Studio —
-- é a base de TUDO que precisa de eixo confiável aqui (ângulo de
-- aproximação em attemptCatch, eixo LATERAL do movimento/pulo, e a
-- direção "seguro" pra segurar a bola sem tocar no próprio gol) — nunca
-- depende da orientação (LookVector) de nenhuma Part, só da POSIÇÃO dos
-- 2 gols, que é sempre confiável.
local function fieldForward(teamName)
	local own = ownGoalOf(teamName)
	local enemy = enemyGoalOf(teamName)
	if own and enemy then
		local dir = enemy.Position - own.Position
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 0.1 then
			return dir.Unit
		end
	end
	return Vector3.new(0, 0, -1) -- fallback arbitrário, só usado se faltar 1 dos 2 gols na cena
end

-- Eixo LATERAL (esquerda/direita) do gol: perpendicular a fieldForward
-- no plano horizontal — ⚠️ CORRIGIDO: antes usava anchor.RightVector (a
-- orientação da Part Spawn_<Time>_GK no Studio), e se essa Part não
-- estava virada exatamente pro gol adversário, "lateral" acabava sendo
-- na verdade o eixo de PROFUNDIDADE (bot indo pra frente/trás em vez de
-- pros lados). Girar fieldForward 90° no plano XZ nunca depende da
-- rotação de nenhuma Part, só da posição dos 2 gols — sempre certo.
local function lateralAxisOf(teamName)
	local forward = fieldForward(teamName)
	return Vector3.new(-forward.Z, 0, forward.X).Unit
end

-- Distância real (studs) entre os 2 gols do time, medida na hora — usada
-- pelo tiro de meta (metade disso = alcance máximo, ver
-- _G.GKBotTakeGoalKick mais abaixo) — nunca um número fixo "chutado", se
-- adapta a qualquer tamanho de campo que você montar no Studio.
local function fieldLength(teamName)
	local own = ownGoalOf(teamName)
	local enemy = enemyGoalOf(teamName)
	if own and enemy then
		local delta = enemy.Position - own.Position
		return Vector3.new(delta.X, 0, delta.Z).Magnitude
	end
	return Config.GKBOT_GOAL_KICK_MAX_RANGE_FALLBACK * 2
end

-- Metade da largura real do GOL (não da grande área) — usada pra nunca
-- deixar o bot passar da ponta da trave lateralmente (ver
-- computeMoveTarget mais abaixo).
-- ⚠️ CORRIGIDO ("goleiro só se move às vezes, meio travado"): a 1ª versão
-- usava goal.Size.X direto, assumindo que o eixo LOCAL X da Part do gol
-- já era a largura alinhada com o eixo lateral do campo — mas a Part do
-- gol pode estar ROTACIONADA no Studio (diferente da Spawn_<Time>_GK, o
-- gol quase nunca é modelado com o cuidado de ficar com X==largura
-- exata). Se a rotação não bater, Size.X podia ser bem menor que a
-- largura real, travando o clamp lateral (maxLateral) pertinho de 0 —
-- o bot ficava "preso" quase sem conseguir andar pro lado. Agora projeta
-- as 3 dimensões da CAIXA (Size) no eixo lateral de verdade (via
-- CFrame:VectorToWorldSpace, que já leva a rotação da Part em conta) —
-- sempre certo, não importa como o gol foi montado.
local function goalHalfWidth(teamName)
	local goal = ownGoalOf(teamName)
	if not goal then return nil end

	local lateralAxis = lateralAxisOf(teamName)
	local half = goal.Size / 2
	local cframe = goal.CFrame

	return math.abs(cframe.RightVector:Dot(lateralAxis)) * half.X
		+ math.abs(cframe.UpVector:Dot(lateralAxis)) * half.Y
		+ math.abs(cframe.LookVector:Dot(lateralAxis)) * half.Z
end

-- ⚠️ v6.0: PEDIDO — "o goleiro está andando meio travado, e a bola
-- também no início do jogo... como se tivesse com baixo fps". Achado:
-- teamGoalCFrame varria TODO workspace:GetDescendants() (potencialmente
-- milhares de Parts, tudo do estádio incluído) TODA VEZ que era chamada —
-- e computeMoveTarget chama ela a cada MOVE_UPDATE_INTERVAL (0.15s) por
-- bot, então eram várias varreduras completas por segundo, o tempo todo
-- que o jogo roda. Agora a Part Spawn_<Time>_GK é procurada uma vez só e
-- fica em cache (mesmo padrão de findAreaPart acima) — só refaz a busca
-- se a Part cacheada tiver sido destruída.
local teamGoalCFrameParts = {} -- [teamName] = Part (só guarda quando ACHA — ver ⚠️ v12 abaixo)
local warnedMissingGoalCFramePart = {}

-- ⚠️ v12 FIX: "eu tentei colocar o spawn dele mais pra frente, mas ele
-- continua indo pra trás, será que a posição fixa dele é assim?" — antes
-- disso, quando a Part Spawn_<Time>_GK não era achada na PRIMEIRA
-- chamada (por timing de carregamento, ou por um nome digitado
-- ligeiramente diferente — maiúscula/minúscula importa), o resultado
-- "não achei" ficava em cache PRA SEMPRE (cached = false, nunca mais
-- procurava de novo) — o bot caía pro fallback (perto do próprio gol +
-- Config.GKBOT_SAFE_GOAL_OFFSET) e NUNCA respeitava a Part que você
-- criou, mesmo com o nome certinho, SEM avisar nada no console — dava
-- exatamente a impressão de "posição fixa que não muda". Mesma classe de
-- bug que já corrigimos em GKAreaUtil.lua.
--
-- Agora: só guarda em cache quando ACHA de verdade (nunca trava um "não
-- achei" pra sempre); workspace.DescendantAdded (logo abaixo) pega a Part
-- se ela aparecer/for renomeada DEPOIS, sem custo nenhum de ficar
-- reescaneando; e um warn (só uma vez por time) avisa exatamente qual
-- nome estava esperando, pra você conferir se bate com o que criou.
local function findTeamGoalCFramePart(teamName)
	local cached = teamGoalCFrameParts[teamName]
	if cached then
		if cached.Parent then return cached end
		teamGoalCFrameParts[teamName] = nil -- foi destruída — procura de novo
	end

	local wantedName = Config.SPAWN_PART_PREFIX .. teamName .. "_GK"
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == wantedName then
			teamGoalCFrameParts[teamName] = inst
			return inst
		end
	end

	if not warnedMissingGoalCFramePart[teamName] then
		warnedMissingGoalCFramePart[teamName] = true
		warn(("⚠️ GKBotController: Part '%s' não encontrada — o goleiro-bot do time %s vai descansar numa posição de segurança perto do próprio gol (Config.GKBOT_SAFE_GOAL_OFFSET, %d studs à frente da linha) em vez de respeitar um spawn fixo seu. Confira se o nome da Part está EXATAMENTE assim (maiúsculas/minúsculas importam) — isso continua tentando de novo sozinho se ela aparecer depois, sem precisar reiniciar o server."):format(wantedName, teamName, Config.GKBOT_SAFE_GOAL_OFFSET))
	end

	return nil
end

-- Pega a Part mesmo se ela for criada/renomeada DEPOIS deste script já ter
-- rodado (ex.: você ajustando no Studio com o server já de pé) — custo
-- praticamente zero, só dispara quando algo novo entra no Workspace.
workspace.DescendantAdded:Connect(function(inst)
	if not inst:IsA("BasePart") then return end
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if not teamGoalCFrameParts[teamName] and inst.Name == (Config.SPAWN_PART_PREFIX .. teamName .. "_GK") then
			teamGoalCFrameParts[teamName] = inst
		end
	end
end)

local function teamGoalCFrame(teamName)
	local part = findTeamGoalCFramePart(teamName)
	if part then
		if part.Parent then return part.CFrame end
		teamGoalCFrameParts[teamName] = nil -- foi destruída — procura de novo na próxima chamada
	end

	-- ⚠️ CORRIGIDO: sem a Part Spawn_<Time>_GK, o fallback antigo usava
	-- a CFrame do PRÓPRIO gol — ou seja, o bot podia nascer/ficar
	-- literalmente EM CIMA da hitbox do gol (goalPart.Touched conta gol
	-- na hora que a bola encosta nela, ver MatchController.lua). Agora
	-- empurra a posição pra FRENTE (rumo ao campo) por
	-- GKBOT_SAFE_GOAL_OFFSET studs antes de usar, pra nunca ficar em
	-- cima da própria hitbox de gol.
	local goal = ownGoalOf(teamName)
	if goal then
		local forward = fieldForward(teamName)
		local safePosition = goal.Position + forward * Config.GKBOT_SAFE_GOAL_OFFSET
		return CFrame.new(safePosition)
	end

	return CFrame.new(0, 5, 0)
end

-- ===== ÁREA DO GOLEIRO (pra movimento) — mesma Part de GKAreaUtil.lua,
-- lookup próprio aqui porque esse módulo é indexado por Player e o bot
-- não é um. =====
local areaParts = {} -- [teamName] = Part ou false (já procurou e não achou)

local function findAreaPart(teamName)
	local cached = areaParts[teamName]
	if cached ~= nil then
		return cached or nil
	end

	local target = Config.GK_AREA_PART_PREFIX .. teamName
	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst:IsA("BasePart") and inst.Name == target then
			areaParts[teamName] = inst
			return inst
		end
	end

	areaParts[teamName] = false
	return nil
end

-- Ponto dentro da Part de área? (mesmo teste de GKAreaUtil.lua, mas esse
-- módulo é indexado por Player e o bot não é um — lookup próprio aqui.)
local function isInsideOwnArea(teamName, worldPoint)
	local area = findAreaPart(teamName)
	if not area then return false end
	local half = area.Size / 2
	local local_ = area.CFrame:PointToObjectSpace(worldPoint)
	return math.abs(local_.X) <= half.X and math.abs(local_.Y) <= half.Y and math.abs(local_.Z) <= half.Z
end

-- ⚠️ v3.3: PROFUNDIDADE real da Part GKArea_<Time> (linha do gol até o
-- fundo da área), projetada no eixo fieldForward via OBB — mesma técnica
-- de goalHalfWidth acima, só que no eixo de PROFUNDIDADE em vez do
-- lateral. Usada pra fazer o alcance do "bote" (GKBOT_BOTE_RANGE) crescer
-- sozinho se a área desenhada no Studio for grande, em vez de depender só
-- de um número fixo na Config — "se a pessoa andar metade da área de
-- distância ele já começa ir pra cima".
local function areaDepth(teamName)
	local area = findAreaPart(teamName)
	if not area then return nil end

	local forwardAxis = fieldForward(teamName)
	local half = area.Size / 2
	local cframe = area.CFrame

	local halfDepth = math.abs(cframe.RightVector:Dot(forwardAxis)) * half.X
		+ math.abs(cframe.UpVector:Dot(forwardAxis)) * half.Y
		+ math.abs(cframe.LookVector:Dot(forwardAxis)) * half.Z

	return halfDepth * 2
end

-- ⚠️ v3.3: dado um ponto qualquer (ex: previsão de trajetória, que pode
-- cair fora da área ou até fora do campo), devolve o ponto mais próximo
-- dele que ainda está DENTRO da Part GKArea_<Time> — usa a hitbox da área
-- como "cálculo prévio" de até onde o goleiro pode ir, pedido do usuário.
-- Sem a Part de área, devolve o ponto original sem mexer (fallback).
local function clampPointToOwnArea(teamName, point)
	local area = findAreaPart(teamName)
	if not area then return point end

	local half = area.Size / 2
	local local_ = area.CFrame:PointToObjectSpace(point)
	local clampedLocal = Vector3.new(
		math.clamp(local_.X, -half.X, half.X),
		local_.Y,
		math.clamp(local_.Z, -half.Z, half.Z)
	)
	return area.CFrame:PointToWorldSpace(clampedLocal)
end

-- ⚠️ v3.3: mesma fórmula de previsão do InstinctTrajectorySight.local.luau
-- (posição + velocidade da bola, com gravidade) — mas rodando no
-- SERVIDOR: dado um tempo `t` no futuro, devolve onde a bola vai estar se
-- mantiver a velocidade/gravidade atuais. Não considera curva/spin (ver
-- applyCurve no BallController) — é só previsão auxiliar, o suficiente
-- pra decidir a diagonal do mergulho com antecedência.
local function predictBallPosition(t)
	local origin = ball.Position
	local velocity = ball.AssemblyLinearVelocity
	-- ⚠️ v110: a gravidade que a BOLA sente (o BallController tira 32% dela) e
	-- zero no voo reto de Hissatsu — com a gravidade cheia o bot previa a bola
	-- caindo cedo demais e mergulhava baixo nos chutes altos
	local gravity = (_G.PulseEmVooReto and _G.PulseEmVooReto()) and 0
		or workspace.Gravity * (Config.BALL_GRAVITY_MULTIPLIER or 1)
	return origin + velocity * t - Vector3.new(0, 0.5 * gravity * t * t, 0)
end

-- ⚠️ v3.3: varre GKBOT_TRAJECTORY_PREDICT_SAMPLES pontos no futuro da
-- trajetória prevista da bola e devolve o mais PRÓXIMO do bot (e o tempo
-- até lá) — é isso que deixa o bot "ver a trajetória e o melhor caminho"
-- em vez de só perseguir a posição atual da bola.
local function findClosestPredictedPoint(root)
	local bestPoint, bestDistance, bestT = nil, math.huge, 0
	local step = Config.GKBOT_TRAJECTORY_PREDICT_STEP
	for i = 1, Config.GKBOT_TRAJECTORY_PREDICT_SAMPLES do
		local t = i * step
		local point = predictBallPosition(t)
		local flatDistance = Vector3.new(point.X - root.Position.X, 0, point.Z - root.Position.Z).Magnitude
		if flatDistance < bestDistance then
			bestDistance = flatDistance
			bestPoint = point
			bestT = t
		end
	end
	return bestPoint, bestDistance, bestT
end

-- ⚠️ v24: "nível do campo" — média dos atributos de todos os jogadores em
-- partida, de 0 a 1. É o que faz a chance da Hissatsu do goleiro subir
-- quando o campo inteiro é forte (pedido: "se todo mundo tiver todos os
-- status maximizados, a chance dele acertar é mais alta, porque ele seria
-- melhor"). Sem ninguém em campo, devolve 0.5 (meio-termo).
local SKILL_ATTRIBUTES = {
	Config.KICK_ATTRIBUTE,
	Config.PHYSICAL_ATTRIBUTE,
	Config.ENERGY_ATTRIBUTE,
	Config.DRIBBLE_SKILL_ATTRIBUTE,
	Config.SPEED_ATTRIBUTE,
	Config.TECHNIQUE_ATTRIBUTE, -- ⚠️ NOVO: 7º atributo entra no "nível do campo"
}

-- ⚠️ v26: teto de força que o bot segura com MERGULHO NORMAL, sem Hissatsu.
-- Usado em dois lugares (na decisão de usar a Hissatsu e na hora de agarrar
-- de verdade), então mora aqui pra os dois nunca discordarem.
-- ============================================================
-- ⚠️ v27 — GUARDA VISÍVEL DA HISSATSU DO GKBOT
-- PEDIDO: "não é pra ele pegar a bola antes dela chegar no gol. Tem que
-- aparecer a hitbox igual aparece pro GK normal, e quando a bola bate lá,
-- ele defende. O que estava acontecendo: saiu o chute e o goleiro pegou na
-- hora, na mão."
--
-- CAUSA: com a Hissatsu ativa, attemptCatch devolvia "pegou" assim que a
-- bola entrava em CATCH_MAX_RANGE * 3 (27 studs) — ou seja, ele agarrava a
-- bola ainda lá longe, no meio do voo. Agora a Hissatsu materializa uma
-- ÁREA na frente dele, e a defesa só acontece quando a bola entra NESSA
-- área — igual à guarda do goleiro humano.
-- ============================================================
local function guardHalfSize(bot)
	-- GuardSize da Hissatsu é uma fração (0..1) da largura do gol — mesma
	-- convenção da guarda humana (ver startGKGuard em PulseController).
	local fraction = (bot.Pulse and bot.Pulse.QTE and bot.Pulse.QTE.GuardSize) or 0.5
	local half = goalHalfWidth(bot.TeamName) or 20
	local width = math.max(half * fraction, 6)
	return Vector3.new(width, math.max(width * 0.75, 6), 3)
end

local function hideBotGuard(bot)
	if bot.GuardPart then
		bot.GuardPart:Destroy()
		bot.GuardPart = nil
	end
end

local function updateBotGuard(bot)
	local active = bot.PulseDefenseActiveUntil and tick() < bot.PulseDefenseActiveUntil
	if not active or not bot.Root or not bot.Root.Parent then
		hideBotGuard(bot)
		return
	end

	local size = guardHalfSize(bot)
	if not bot.GuardPart then
		local part = Instance.new("Part")
		part.Name = "GKBotHissatsuGuard"
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(120, 200, 255)
		part.Transparency = 0.72
		part.Size = size * 2
		part.Parent = workspace
		bot.GuardPart = part
	end

	-- Fica plantada logo à frente do bot, virada pro campo.
	local forward = fieldForward(bot.TeamName)
	bot.GuardPart.CFrame = CFrame.lookAt(
		bot.Root.Position + forward * 2.5,
		bot.Root.Position + forward * 10
	)
end

-- A bola está DENTRO da área da guarda?
local function ballInsideGuard(bot)
	if not bot.GuardPart then return false end
	local localBall = bot.GuardPart.CFrame:PointToObjectSpace(ball.Position)
	local half = bot.GuardPart.Size / 2
	return math.abs(localBall.X) <= half.X
		and math.abs(localBall.Y) <= half.Y
		and math.abs(localBall.Z) <= half.Z
end

-- ⚠️ v28 — PEDIDO: "o goleiro precisa aparecer quantas vezes ele errou e
-- quantas vezes ele acertou, com um timing durante a animação dele tentar
-- pegar a bola."
-- Placa flutuante em cima do bot, aparecendo no INSTANTE do contato (não na
-- hora do chute), com o resultado e o placar acumulado da partida.
local function showBotGuardResult(bot, landed)
	bot.GuardHits = (bot.GuardHits or 0) + (landed and 1 or 0)
	bot.GuardMisses = (bot.GuardMisses or 0) + (landed and 0 or 1)

	local anchor = bot.Root
	if not anchor or not anchor.Parent then return end

	local gui = bot.ResultGui
	if not gui or not gui.Parent then
		gui = Instance.new("BillboardGui")
		gui.Name = "GKBotHissatsuResult"
		gui.Size = UDim2.fromOffset(240, 64)
		gui.StudsOffset = Vector3.new(0, 5.5, 0)
		gui.AlwaysOnTop = true
		gui.Adornee = anchor
		gui.Parent = anchor

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextStrokeTransparency = 0.25
		label.Parent = gui

		bot.ResultGui = gui
	end

	local label = gui:FindFirstChild("Label")
	if label then
		label.Text = string.format(
			"%s   pegou %d / errou %d",
			landed and "PEGOU!" or "ERROU!",
			bot.GuardHits, bot.GuardMisses
		)
		label.TextColor3 = landed and Color3.fromRGB(90, 235, 140) or Color3.fromRGB(245, 85, 85)
	end
	gui.Enabled = true

	task.delay(Config.GKBOT_RESULT_LABEL_SECONDS, function()
		if gui and gui.Parent then gui.Enabled = false end
	end)
end

local function normalSaveCeiling()
	local physicalFraction = math.clamp(getGKBotPhysical(), 0, 100) / 100
	return Config.GKBOT_NORMAL_SAVE_FORCE_MIN
		+ (Config.GKBOT_NORMAL_SAVE_FORCE_MAX - Config.GKBOT_NORMAL_SAVE_FORCE_MIN) * physicalFraction
end

local function fieldSkillFraction()
	local total, playerCount = 0, 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if not plr.Team then continue end
		local sum, attributeCount = 0, 0
		for _, attributeName in ipairs(SKILL_ATTRIBUTES) do
			if attributeName then
				local value = plr:GetAttribute(attributeName)
				if typeof(value) == "number" then
					sum += math.clamp(value, 0, 100)
					attributeCount += 1
				end
			end
		end
		if attributeCount > 0 then
			total += sum / attributeCount
			playerCount += 1
		end
	end
	if playerCount == 0 then return 0.5 end
	return math.clamp((total / playerCount) / 100, 0, 1)
end

-- ===== ESTADO DOS BOTS ATIVOS =====
local bots = {} -- [teamName] = { Model, Humanoid, Root, LastActionAt, LastMoveAt, State, HoldUntil }

local function assignGKBotPulseForTeam(teamName)
	local bot = bots[teamName]
	if not bot then return end
	local computedRarity = computeFieldPulseRarity()
	bot.Pulse = pickGKPulseForRarity(computedRarity)
	if Config.PULSE_FORCE_DEBUG_PRINTS then
		print(string.format(
			"🧤 [GKBot] %s recebeu o Pulso de goleiro \"%s\" (raridade calculada do campo: %s).",
			teamName, bot.Pulse and bot.Pulse.Name or "NENHUM (nenhum Pulso de GK cadastrado)", tostring(computedRarity)
		))
	end
end

-- ⚠️ NOVO: PEDIDO — "ele só usará o pulso contra hissatsus, ele vai mirar
-- e usar a habilidade exatamente quando o pulso de chute sair, na direção
-- dela, e vai acertar aleatóriamente". Reage EM CIMA da hora (mesmo
-- listener síncrono que BallController.legacy.luau chama dentro de
-- _G.PulseExecuteShot, "exatamente quando o pulso de chute sair") — só se
-- o time DEFENSOR (o oposto de quem chutou) tiver um bot ativo com um
-- Pulso de goleiro já atribuído (ver assignGKBotPulseForTeam). O
-- resultado (defende ou não) é sorteado na hora — "vai acertar
-- aleatóriamente" — nunca garantido.
-- ⚠️ FIX: a ORDEM de execução entre Scripts diferentes em
-- ServerScriptService (este e BallController.legacy.luau, onde
-- _G.RegisterPulseShotListener é criado) NÃO é garantida pelo Roblox — se
-- este script rodar primeiro, chamar _G.RegisterPulseShotListener direto
-- aqui falharia silenciosamente (função ainda não existe). Esperar em
-- loop (sem travar o resto do script, que continua carregando embaixo)
-- até ela aparecer resolve isso nos dois sentidos de ordem.
-- ⚠️ v40: DECLARAÇÃO ANTECIPADA. O listener logo abaixo chama
-- computeGuardIntercept, mas ela só pode ser DEFINIDA lá embaixo (depende
-- de AREA_SIDE_FALLBACK_RADIUS e companhia, declarados bem depois daqui).
-- Em Luau o escopo é léxico e resolvido na compilação: sem este `local`
-- aqui em cima, o nome lá dentro do listener viraria uma leitura de
-- GLOBAL (nil) e explodiria na primeira Hissatsu. Como o listener só roda
-- em runtime, muito depois do arquivo inteiro carregar, a atribuição lá
-- embaixo chega a tempo.
local computeGuardIntercept

task.spawn(function()
	local waited = 0
	while not _G.RegisterPulseShotListener and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end
	if not _G.RegisterPulseShotListener then
		warn("⚠️ GKBotController: _G.RegisterPulseShotListener nunca apareceu (BallController.legacy.luau carregou?) — defesa reativa de Pulso do GKBOT desativada.")
		return
	end
	_G.RegisterPulseShotListener(function(shotInfo)
		-- ⚠️ v24: DIAGNÓSTICO ALTO. "Ele ainda não está utilizando nenhuma
		-- Hissatsu" — daqui não dá pra saber em qual etapa ele desiste, e são
		-- cinco portas possíveis antes da decisão. Cada uma agora fala.
		local shooterTeam = shotInfo.Team
		if not shooterTeam then
			warn("🧤 [GKBot] Hissatsu saiu mas o chute não tem time (shotInfo.Team vazio) — não dá pra saber quem defende.")
			return
		end
		local defendingTeam = otherTeamName(shooterTeam)
		if not defendingTeam then
			warn("🧤 [GKBot] não achei o time adversário de '" .. tostring(shooterTeam) .. "'.")
			return
		end

		local bot = bots[defendingTeam]
		if not bot or not bot.Model or not bot.Model.Parent then
			warn("🧤 [GKBot] não existe bot no gol do time '" .. tostring(defendingTeam) .. "' (goleiro humano, ou bot ainda não criado).")
			return
		end
		-- ⚠️ v40 — PEDIDO: "a partir do momento que alguém usar uma Hissatsu
		-- de chute, o goleiro precisa ir IMEDIATAMENTE pra posição onde a
		-- bola está indo."
		--
		-- Fica AQUI EM CIMA de propósito, antes de todas as portas de saída
		-- abaixo (sem Hissatsu atribuída, Hissatsu em recarga, força abaixo
		-- do teto do mergulho normal): ir pro lugar certo é bom em TODAS
		-- essas situações, não só quando ele arma a guarda. Se a Hissatsu
		-- dele estiver em recarga, ele ainda assim vai pro ponto certo e
		-- tenta de mergulho — que é o que um goleiro faria.
		local intercepcao = computeGuardIntercept(defendingTeam, shotInfo)
		if intercepcao then
			bot.GuardIntercept = intercepcao
			bot.GuardInterceptUntil = tick() + Config.GKBOT_INTERCEPT_HOLD_SECONDS
			bot.LastMoveAt = 0 -- força o recálculo do alvo já no próximo heartbeat, sem esperar o intervalo
		end

		if not bot.Pulse then
			warn("🧤 [GKBot] o bot de '" .. tostring(defendingTeam) .. "' está SEM Hissatsu de goleiro atribuída — assignGKBotPulseForTeam não achou nenhuma no pool.")
			return
		end

		-- ⚠️ v23 — PEDIDO: "o GK bot tem que utilizar a Hissatsu de goleiro
		-- CALCULANDO que o cara usou uma Hissatsu e vendo se a força é
		-- suficiente... testei com a mais fraca, 80 de força, podia ser que
		-- ele conseguisse; depois com uma mítica de 250 na cola dele, não era
		-- pra conseguir com um pulo normal."
		--
		-- O QUE HAVIA: um `math.random() < CHANCE`. Não olhava a força do
		-- chute, não olhava o Físico do bot, e valia por 0.4s fixos — janela
		-- que expirava antes da bola chegar em qualquer chute de longe. Na
		-- prática a Hissatsu quase nunca acontecia, e quando acontecia era
		-- por sorte.
		--
		-- AGORA é a ordem que você descreveu:
		--   1. saiu uma Hissatsu? (este listener só dispara nisso)
		--   2. a força dela cabe no que ele segura com mergulho normal?
		--      → cabe: não gasta a Hissatsu, vai de mergulho mesmo.
		--      → não cabe: dispara a Hissatsu de goleiro NA HORA.
		-- A Hissatsu do goleiro sai instantânea de propósito (sem QTE, sem
		-- wind-up) — é a diferença dela pras de linha, e é o que permite
		-- reagir a um chute que já está no ar.
		if bot.PulseReadyAt and tick() < bot.PulseReadyAt then
			warn(string.format("🧤 [GKBot] queria usar \"%s\" mas ela está em recarga por mais %.1fs.", bot.Pulse.Name, bot.PulseReadyAt - tick()))
			return
		end

		local ceiling = normalSaveCeiling()
		local shotForce = shotInfo.Force or 0

		-- ⚠️ v26 FIX — "chutei uma Galáxia de 320 na cara do gol e ele pegou
		-- normalmente". CAUSA: quem decidia se o chute era "perigoso" na hora
		-- de agarrar era _G.GetDangerForceRatingForTeam, que só vale por uma
		-- JANELA DE TEMPO (DANGER_SHOT_WINDOW, 2.5s) contada a partir do
		-- chute. Bola que demora mais que isso pra chegar — ou que quica, ou
		-- que ele persegue — chega com a janela já fechada, o rating volta 0,
		-- e aí a captura garantida pegava QUALQUER força.
		--
		-- Agora o bot guarda a Hissatsu que está vindo PRA CIMA DELE, com a
		-- força de verdade, e é isso que attemptCatch consulta. Não depende
		-- mais de relógio nenhum.
		bot.IncomingShotForce = shotForce
		bot.IncomingShotUntil = tick() + Config.GKBOT_INCOMING_SHOT_MEMORY

		if shotForce <= ceiling then
			print(string.format(
				"🧤 [GKBot] %s: chute de %.0f de força cabe no mergulho normal (teto %.0f com Físico %d) — guardou a Hissatsu.",
				defendingTeam, shotForce, ceiling, getGKBotPhysical()
			))
			return
		end

		-- ⚠️ v24 — PEDIDO: "ele tem chance de acertar e chance de errar. A
		-- maior chance vai ser 80%, a menor 35%, e essa chance varia com o
		-- nível dos jogadores do campo: se todo mundo tiver tudo maximizado,
		-- a chance dele acertar é mais alta."
		--
		-- A Hissatsu SEMPRE sai (ele sempre tenta, como um humano tentaria);
		-- o que o sorteio decide é se ela PEGA. Errando, ele fica exposto —
		-- gastou a Hissatsu e a bola passa.
		-- ⚠️ v28: aqui ele só ARMA a guarda. Se ela PEGA ou não é decidido
		-- quando a bola encostar nela (ver attemptCatch) — é lá que existe um
		-- momento pra mostrar o resultado na tela, com a bola chegando.
		bot.PulseReadyAt = tick() + (bot.Pulse.Cooldown or 20)
		bot.PulseDefenseActiveUntil = tick() + Config.GKBOT_PULSE_DEFENSE_WINDOW
		bot.GuardRolled = nil
		-- ⚠️ v38: zera também a janela de drenagem da defesa anterior (ver
		-- attemptCatch), senão a próxima Hissatsu acharia que o contato
		-- já tinha acontecido e resolveria na hora, sem mostrar nada.
		bot.GuardContactAt = nil
		bot.GuardDrainFinish = nil
		bot.GuardFroze = nil
		bot.GuardRebound = nil
		bot.GuardResolvedAt = nil
		-- NÃO limpar GuardIntercept aqui: computeGuardIntercept roda ANTES
		-- deste bloco (lá em cima, antes das portas de saída) e é
		-- exatamente o alvo desta jogada que estaria sendo apagado.

		print(string.format(
			"🧤 [GKBot] %s ARMOU \"%s\" contra chute de %.0f (teto do mergulho normal: %.0f). Recarrega em %ds.",
			defendingTeam, bot.Pulse.Name, shotForce, ceiling, bot.Pulse.Cooldown or 20
		))
	end)
end)

-- ⚠️ NOVO (replay de gol) — PEDIDO: "nem os jogadores e nem o bot aparecem
-- em campo, [no replay]... é pra aparecer os dois". O bot NÃO é um Player
-- (ver comentário no topo do arquivo), então quem grava o histórico do
-- replay (BallController.lua) não tem como saber onde ele está sozinho —
-- esta função expõe a posição atual de cada bot ativo (só os que existem
-- de verdade agora, sem goleiro humano na posição) pra quem quiser gravar.
-- ⚠️ v46 — CONGELAR O GOLEIRO BOT.
-- A Fúria Glacial promete, na descrição dela: "quem estiver na linha do
-- chute trava no lugar — E SE O GOLEIRO ENCOSTAR, ELE CONGELA JUNTO e o
-- rebote fica livre." Só que applyCorridorEffect (PulseController) varre
-- Players:GetPlayers(), e o goleiro BOT não é um Player — ele é um Model
-- controlado por este script. Na prática, contra bot (que é o caso normal,
-- já que a vaga de GK nem é mais reservada) essa metade da habilidade
-- simplesmente não existia.
--
-- Aqui o bot ganha o equivalente do congelamento de jogador: para de se
-- mover, para de decidir, e volta sozinho quando o tempo passa. A aura de
-- gelo NÃO é reaproveitada porque o AbilityAura anima por personagem de
-- Player; o bot ganha a marca visual dele pelo mesmo Highlight simples.
_G.FreezeGKBot = function(teamName, duration)
	local bot = bots[teamName]
	if not bot or not bot.Root or not bot.Root.Parent then return false end
	if not duration or duration <= 0 then return false end

	bot.FrozenUntil = math.max(bot.FrozenUntil or 0, tick() + duration)
	bot.Root.AssemblyLinearVelocity = Vector3.new(0, bot.Root.AssemblyLinearVelocity.Y, 0)
	if bot.Humanoid then bot.Humanoid.WalkSpeed = 0 end

	local gelo = bot.Model and bot.Model:FindFirstChild("GKBotFreezeAura")
	if not gelo and bot.Model then
		gelo = Instance.new("Highlight")
		gelo.Name = "GKBotFreezeAura"
		gelo.Adornee = bot.Model
		gelo.FillTransparency = 1 -- mesmo princípio do AbilityAura: não pinta o corpo
		gelo.OutlineColor = Color3.fromRGB(190, 240, 255)
		gelo.OutlineTransparency = 0
		gelo.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		gelo.Parent = bot.Model
	end
	if gelo then gelo.Enabled = true end
	return true
end

-- Posição de cada bot em campo, pra quem precisa testar alcance/corredor.
_G.GetGKBotPositions = function()
	local list = {}
	for teamName, bot in pairs(bots) do
		if bot.Root and bot.Root.Parent then
			table.insert(list, { TeamName = teamName, Position = bot.Root.Position })
		end
	end
	return list
end

_G.GetActiveGKBots = function()
	local list = {}
	for teamName, bot in pairs(bots) do
		if bot.Root and bot.Root.Parent then
			table.insert(list, { teamName = teamName, cframe = bot.Root.CFrame })
		end
	end
	return list
end

-- ⚠️ v5.7: encerra qualquer perseguição em andamento (adversário ou bola
-- solta) e devolve o bot pra posição normal (lateral, clampada) — chamada
-- tanto quando a perseguição termina em SUCESSO (pegou a bola, ver
-- beginCatch) quanto quando ela é abandonada por completo.
local function stopPursuit(bot)
	bot.PursuingPlayer = nil
	bot.ChasingBall = false
	bot.PursuitLostSince = nil
	bot.ChaseTarget = nil
end

-- ⚠️ v5.7: chamada quando NENHUM alvo qualificado existe neste frame —
-- se o bot já estava perseguindo algo, começa (ou continua) a contar
-- quanto tempo faz que o alvo sumiu da zona, e só desiste de verdade
-- (stopPursuit) depois de Config.GKBOT_RETURN_DELAY segundos SEGUIDOS
-- assim. Pedido: "não deixe-o voltar... ele só volta depois de o
-- atacante estiver por 1.5 segundos fora da área de identificação".
local function updatePursuitGiveUp(bot)
	if not (bot.PursuingPlayer or bot.ChasingBall) then return end
	if not bot.PursuitLostSince then
		bot.PursuitLostSince = tick()
	elseif tick() - bot.PursuitLostSince >= Config.GKBOT_RETURN_DELAY then
		stopPursuit(bot)
	end
end

local function destroyBot(teamName)
	local bot = bots[teamName]
	if bot and bot.Model then
		bot.Model:Destroy()
	end
	bots[teamName] = nil
end

local function spawnBotIfNeeded(teamName)
	if bots[teamName] and bots[teamName].Model.Parent then return end
	if Config.CLOSED_TEAM_MODE then return end
	-- time vazio, sem partida rolando ainda — ⚠️ v104: EXCETO na sala
	-- personalizada ("mesmo que puxe sozinho, o GK vai estar sempre
	-- spawnado"), onde o bot guarda os dois gols (ver MatchController)
	if teamPlayerCount(teamName) <= 0 and not _G.SalaPersonalizada then return end
	if _G.ModoTutorial then return end -- ⚠️ v104: tutorial sem goleiro (o gol é o passo a aprender)

	local template = ServerStorage:FindFirstChild(Config.GKBOT_TEMPLATE_NAME)
	if not template then
		warn(string.format(
			"⚠️ GKBotController: Model '%s' não encontrado em ServerStorage — crie ele lá (Humanoid + HumanoidRootPart dentro) pra poder substituir o goleiro do time %s.",
			Config.GKBOT_TEMPLATE_NAME, teamName
		))
		return
	end

	local clone = template:Clone()
	clone.Name = "GKBot_" .. teamName

	local humanoid = clone:FindFirstChildOfClass("Humanoid")
	local root = clone:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		warn(string.format(
			"⚠️ GKBotController: o Model '%s' precisa ter um Humanoid e uma Part chamada 'HumanoidRootPart' dentro (igual um NPC comum) — bot não criado.",
			Config.GKBOT_TEMPLATE_NAME
		))
		clone:Destroy()
		return
	end

	clone.Parent = workspace
	humanoid.WalkSpeed = Config.GKBOT_WALK_SPEED -- ⚠️ NOVO: bot anda de verdade agora (era 0/estático)
	humanoid.PlatformStand = false
	-- ⚠️ v21: o Humanoid gira o corpo sozinho na direção do movimento. Como o
	-- bot desliza de um lado pro outro, ele ficava rodando 180° a cada
	-- correção. Desligado aqui; quem orienta o bot agora é
	-- updateBotMovement, que o mantém SEMPRE encarando a bola.
	humanoid.AutoRotate = false
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Physics, false) -- não deixa ele travar em "Physics" e parar de responder a MoveTo

	-- ⚠️ IMPORTANTE: personagem ANCHORED nunca anda (Humanoid:MoveTo é
	-- ignorado). Se o molde no ServerStorage estiver anchored, o clone é
	-- desanchorado aqui automaticamente — não precisa mexer no molde à
	-- mão, mas o aviso aparece no Output pra você saber que era isso.
	local hadAnchored = false
	for _, part in ipairs(clone:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Anchored then
				hadAnchored = true
				part.Anchored = false
			end
			part.CollisionGroup = "Players" -- não colide com jogadores nem com a bola, igual um personagem real
		end
	end
	if hadAnchored then
		warn(string.format(
			"⚠️ GKBotController: o Model '%s' estava com partes Anchored (personagem anchored não anda). Desanchorei o clone automaticamente — pra ficar 100%% certo, desmarque Anchored no molde do ServerStorage também.",
			Config.GKBOT_TEMPLATE_NAME
		))
	end

	clone:PivotTo(teamGoalCFrame(teamName))

	bots[teamName] = {
		-- ⚠️ v27: a guarda da Hissatsu precisa saber de que time o bot é
		-- (pra achar a largura do gol e a direção do campo).
		TeamName = teamName,
		Model = clone,
		Humanoid = humanoid,
		Root = root,
		LastActionAt = 0,
		LastMoveAt = 0,
		MoveTarget = nil,
		ChaseTarget = nil, -- ⚠️ NOVO: enquanto setado (e dentro de ChaseUntil), computeMoveTarget mira AQUI em vez da posição lateral normal — ver maybeJumpForBall/pursueOpponent/pursueLooseBall
		ChaseUntil = 0,
		State = "Idle", -- "Idle" | "Holding" (segurando a bola, esperando pra lançar)
		HoldUntil = 0,
		-- ⚠️ v5.7: perseguição CONTÍNUA (substitui o antigo dash de duração
		-- fixa) — ver pursueOpponent/pursueLooseBall/stopPursuit/
		-- updatePursuitGiveUp mais abaixo.
		PursuingPlayer = nil, -- Player sendo perseguido (bote), ou nil
		ChasingBall = false,  -- true = perseguindo a bola SOLTA dentro da própria área (sem adversário envolvido)
		PursuitLostSince = nil, -- tick() de quando o alvo saiu da zona de identificação (nil = ainda dentro dela)
		LastStealAttempt = 0,   -- throttle das tentativas de roubo/captura durante a perseguição (GKBOT_STEAL_ATTEMPT_INTERVAL)
		-- ⚠️ v6.4: tick() do último arremesso (throwBall/GKBotTakeGoalKick) —
		-- ver Config.GKBOT_HITBOX_DISABLE_AFTER_THROW/isHitboxDisabled. PEDIDO:
		-- "o único momento que a hitbox dele é desligada é quando ele passa a
		-- bola, e 0.5 segundos depois ela é religada de novo" — esse é o ÚNICO
		-- motivo que bloqueia a captura agora (fora dele, contato = captura
		-- garantida, ver tryContactCatch).
		LastThrowAt = 0,
		-- ⚠️ v6.1: mergulho resolve inteiramente de forma SÍNCRONA, guiado só
		-- por tick() e checado todo heartbeat em updateActiveDive — sem
		-- task.delay nenhum (ver comentário em reactToBall).
		DiveActive = false,   -- true enquanto o mergulho atual está "em voo", sendo checado todo heartbeat
		DiveResolved = false, -- já decidiu agarrar/repelir para ESTE mergulho? (evita resolver 2x)
		DiveStartedAt = 0,    -- tick() de quando o mergulho atual começou — usado como prazo máximo (GKBOT_DIVE_DURATION) em updateActiveDive
		DiveStateGen = 0,     -- ⚠️ v6.2: _G.GetBallStateGeneration() de quando o mergulho começou — ver reactToBall/resolveCatchOrClear
	}
	print(string.format("🤖 GKBotController: bot assumiu o gol do time %s (sem jogador na posição).", teamName))
	assignGKBotPulseForTeam(teamName)
end

local function reconcile()
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if hasHumanGK(teamName) then
			if bots[teamName] then
				destroyBot(teamName)
				print(string.format("🤖 GKBotController: jogador assumiu o gol do time %s, bot removido.", teamName))
			end
		else
			spawnBotIfNeeded(teamName)
		end
	end
end

-- ===== MOVIMENTO (⚠️ CORRIGIDO: só lateral, nunca persegue a bola pra
-- frente/trás) =====
-- Pedido: o bot tava indo "atrás da bola" de verdade (perseguindo ela
-- pra dentro/fora da área, profundidade incluída) — igual um jogador de
-- linha, não um goleiro. Um goleiro de verdade fica grudado na linha do
-- gol e só se desloca DE LADO acompanhando a posição horizontal da bola;
-- a profundidade (frente/trás) fica sempre FIXA na linha do gol (mesmo Y
-- e mesma "distância do gol" de sempre — teamGoalCFrame). Pulos ficam
-- pro maybeJumpForBall, ver abaixo.
-- ⚠️ v15: era 0.15 (recalculava o alvo ~6x por segundo). Com a bola se
-- mexendo de um lado pro outro, o bot reagia com quase 1/6 de segundo de
-- atraso a cada correção — o que dava a impressão de que ele "não vai
-- direito na bola". 0.08 dobra a taxa de correção e é o que faz ele
-- deslizar de um lado pro outro acompanhando de verdade, em vez de dar um
-- passo, parar, e só depois notar que a bola já andou.
local MOVE_UPDATE_INTERVAL = 0.08
local AREA_SIDE_FALLBACK_RADIUS = 6 -- studs, usado só se a Part GKArea_<Time> não existir na cena

-- ⚠️ v6.2: PEDIDO — "permita que o gk acompanhe mais a bola, quão mais
-- perto estiver, maior o diâmetro de movimento dele". Antes o quanto o bot
-- acompanhava a bola lateralmente na patrulha normal era um número FIXO
-- (Config.GKBOT_LATERAL_RANGE_FRACTION) — bom pra não sair correndo de
-- trave a trave com a bola lá longe no campo adversário, mas também
-- deixava ele pouco reativo quando a bola já estava bem perto/perigosa.
-- Agora esse "quanto ele acompanha" cresce sozinho conforme a bola se
-- aproxima do gol: longe (fora do alcance de referência) usa o mínimo
-- (comportamento contido de sempre); perto (dentro da própria área) sobe
-- até o máximo (acompanha quase 1:1). O alcance de referência usa a
-- PROFUNDIDADE real da Part GKArea_<Time> (igual areaDepth acima) — se
-- adapta a qualquer tamanho de área desenhado no Studio, com um valor fixo
-- só de fallback pra quando ela não existir na cena.
local function lateralFollowFraction(teamName, anchor)
	local toBall = ball.Position - anchor.Position
	local flatDistance = Vector3.new(toBall.X, 0, toBall.Z).Magnitude

	local referenceRange = areaDepth(teamName)
	if not referenceRange or referenceRange <= 0 then
		referenceRange = Config.GKBOT_LATERAL_FOLLOW_RANGE_FALLBACK
	end
	referenceRange = referenceRange * Config.GKBOT_LATERAL_FOLLOW_RANGE_MULT

	-- ⚠️ v16 — A CURVA FOI INVERTIDA. PEDIDO: "se o jogador estiver pertinho
	-- dele com a bola, ele acelera na frente dele [bote]. Se não, ele tenta
	-- manter posição mais ou menos no centro, porque o jogador pode jogar
	-- num lado ou jogar no outro."
	--
	-- Até a v15 era o contrário: quanto MAIS PERTO a bola, MAIS ele
	-- acompanhava pro lado. Isso é justamente o pior momento pra sair do
	-- centro — de perto o atacante enxerga os dois cantos e tem o goleiro
	-- inteiro deslocado pra um lado só; era o "é só chutar no lado contrário"
	-- que o usuário descreveu.
	--
	-- Agora: bola LONGE = pode acompanhar mais (o ângulo é fechado, dá tempo
	-- de corrigir); bola PERTO = segura no centro e cobre os dois cantos. Sair
	-- pra cima do atacante de perto continua existindo, mas é o BOTE
	-- (maybeBoteDash/ChaseTarget), que é uma decisão separada e deliberada —
	-- não esse deslize lateral de patrulha.
	local proximityT = 1 - math.clamp(flatDistance / referenceRange, 0, 1)
	return Config.GKBOT_LATERAL_RANGE_FRACTION_MAX
		- (Config.GKBOT_LATERAL_RANGE_FRACTION_MAX - Config.GKBOT_LATERAL_RANGE_FRACTION_MIN) * proximityT
end

-- ⚠️ v6.3: PEDIDO — "faça o bot ficar mais no centro se o atacante estiver
-- aos lados direita ou diagonal do gol... como ele se move pra onde a bola
-- está, deixa uma brecha [do lado oposto]". Quando a bola vem de um ângulo
-- bem ABERTO/diagonal (bem mais pro lado do que de frente), seguir ela
-- lateralmente até o fim desloca o bot todo pra aquele lado e escancara o
-- lado OPOSTO do gol — um goleiro de verdade, num ângulo assim, se segura
-- mais perto do CENTRO em vez de "fechar" 100% o lado de onde a bola vem.
-- Compara o quanto da posição da bola é PROFUNDIDADE (de frente,
-- fieldForward) contra o quanto é LATERAL (de lado): quanto mais lateral
-- em relação à profundidade (ângulo mais aberto/diagonal), MENOR o fator
-- devolvido (perto de 0 = fica quase parado no centro); de frente
-- (profundidade domina), fator fica perto de 1 (segue normal, sem conter).
local function diagonalCenteringFactor(teamName, anchor, lateralAxis, toBall)
	local depthComponent = math.max(fieldForward(teamName):Dot(toBall), 0)
	local lateralComponent = math.abs(lateralAxis:Dot(Vector3.new(toBall.X, 0, toBall.Z)))

	local factor = depthComponent / math.max(depthComponent + lateralComponent, 0.001)
	return math.clamp(factor, Config.GKBOT_DIAGONAL_CENTER_MIN_FACTOR, 1)
end

-- ⚠️ v40 — INTERCEPTAÇÃO DE HISSATSU: ir DIRETO pra onde a bola VAI.
-- PEDIDO: "a partir do momento que alguém usar uma Hissatsu de chute, o
-- goleiro precisa ir imediatamente para a posição onde a bola está indo,
-- pra poder utilizar a Hissatsu dele. O goleiro está tendo dificuldade
-- pra acertar a Hissatsu. Eu joguei na frente dele e ele ainda teve que
-- se mexer de um lado pro outro. Coloca pra ele poder ficar retinho."
--
-- POR QUE ELE OSCILAVA: computeMoveTarget persegue a posição ATUAL da
-- bola no eixo lateral, e ainda por cima amortecida (lateralFollowFraction
-- × diagonalCenteringFactor). Com a bola voando, o alvo dele mudava todo
-- frame — daí o vaivém. E como o amortecimento puxa pro centro, num chute
-- de perto ele saía do lugar certo em vez de ficar parado.
--
-- AGORA: assim que uma Hissatsu de chute sai, calcula UMA VEZ onde ela vai
-- cruzar o plano do gol e trava o alvo ali. Chute de Hissatsu voa RETO e
-- SEM gravidade (ver pulsePerformKick/startPulseStraightFlight em
-- BallController), então isso é uma interseção reta-plano exata, não um
-- palpite. Chegando no ponto, ele para e fica RETINHO de frente pro campo.
computeGuardIntercept = function(teamName, shotInfo)
	local anchor = teamGoalCFrame(teamName)
	if not anchor then return nil end

	local origem = shotInfo.Origin
	local direcao = shotInfo.Direction
	if typeof(origem) ~= "Vector3" or typeof(direcao) ~= "Vector3" then return nil end
	if direcao.Magnitude < 0.01 then return nil end
	direcao = direcao.Unit

	-- Plano do gol: passa pela boca do gol, com a normal no eixo de
	-- profundidade (fieldForward aponta do gol PRA DENTRO do campo).
	local normal = fieldForward(teamName)
	local denom = direcao:Dot(normal)
	-- Chute indo embora do gol (ou rasante ao plano): não dá pra prever.
	if denom > -0.05 then return nil end

	local t = (anchor.Position - origem):Dot(normal) / denom
	if t <= 0 then return nil end

	local ponto = origem + direcao * t

	-- Converte pro eixo lateral do gol e aplica os MESMOS limites do
	-- movimento normal, pra ele nunca sair da boca do gol atrás de uma
	-- bola que vai passar longe do poste.
	local lateralAxis = lateralAxisOf(teamName)
	local lateral = lateralAxis:Dot(Vector3.new(
		ponto.X - anchor.Position.X, 0, ponto.Z - anchor.Position.Z))

	local maxLateral = AREA_SIDE_FALLBACK_RADIUS
	local area = findAreaPart(teamName)
	if area then maxLateral = area.Size.X / 2 end
	-- ⚠️ v40: aqui o limite lateral é PROPOSITALMENTE mais generoso que o
	-- do posicionamento normal. GKBOT_LATERAL_GOAL_FRACTION (0.65) veio do
	-- pedido "o mais longe que ele pode se mover é um pouco menos, não na
	-- trave exatamente" — que é sobre a posição de DESCANSO/patrulha, pra
	-- ele não ficar colado num poste com o gol aberto do outro lado. Só que
	-- aplicar esse mesmo 0.65 numa defesa EM ANDAMENTO significa que os 35%
	-- externos do gol são fisicamente inalcançáveis: num gol de 60 studs
	-- ele nunca passa de 19.5 do centro, e qualquer Hissatsu mirada no
	-- canto estava ganha antes de sair do pé. Era parte grande do "o
	-- goleiro está tendo dificuldade pra acertar a Hissatsu". Perseguir uma
	-- bola que já está no ar é outra situação — aí ele pode ir até quase o
	-- poste, como um goleiro de verdade.
	local goalHalf = goalHalfWidth(teamName)
	if goalHalf then
		maxLateral = math.min(
			maxLateral,
			goalHalf * Config.GKBOT_INTERCEPT_GOAL_FRACTION + Config.GKBOT_LATERAL_POST_MARGIN
		)
	end
	lateral = math.clamp(lateral, -maxLateral, maxLateral)

	return anchor.Position
		+ fieldForward(teamName) * Config.GKBOT_FORWARD_OFFSET
		+ lateralAxis * lateral
end

local function computeMoveTarget(teamName, bot)
	-- ⚠️ NOVO: durante uma tentativa de defesa/bote (ver maybeJumpForBall/
	-- maybeBoteDash), o alvo vira o próprio ponto que ele tá perseguindo
	-- (bola ou adversário) — SEM o clamp lateral normal, pra ele realmente
	-- sair da linha do gol e ir buscar. Volta pro comportamento normal
	-- sozinho assim que ChaseTarget expira/é limpo (pegou a bola, falhou,
	-- ou a bola saiu da área — ver updateBotMovement/beginCatch/
	-- resolveCatchOrClear/resolveBote).
	if bot.ChaseTarget and tick() < (bot.ChaseUntil or 0) then
		return bot.ChaseTarget
	end

	-- ⚠️ v40: alvo TRAVADO de interceptação de Hissatsu (ver
	-- computeGuardIntercept logo acima). Vem antes do cálculo normal de
	-- propósito: é justamente o acompanhamento amortecido da bola que
	-- fazia ele bailar de um lado pro outro em vez de esperar parado.
	if bot.GuardIntercept and tick() < (bot.GuardInterceptUntil or 0) then
		return bot.GuardIntercept
	end

	local anchor = teamGoalCFrame(teamName)
	local area = findAreaPart(teamName)
	local lateralAxis = lateralAxisOf(teamName) -- ⚠️ CORRIGIDO: eixo derivado dos 2 gols, nunca da rotação de uma Part

	local toBall = ball.Position - anchor.Position
	-- ⚠️ v5.9: PEDIDO — "faça o jogador andar menos pra direita/esquerda,
	-- isso é só pra ele se posicionar um pouco melhor, não ir da ponta a
	-- outra do gol". Amortece o quanto ele acompanha a bola lateralmente —
	-- ⚠️ v6.2: esse amortecimento agora é DINÂMICO (ver lateralFollowFraction
	-- acima) — quanto mais perto a bola estiver do gol, maior o "diâmetro"
	-- de movimento (mais parecido com 1:1); longe, fica contido como antes.
	-- ⚠️ v6.3: multiplicado também pelo fator de "ângulo diagonal" (ver
	-- diagonalCenteringFactor acima) — bola vindo de um ângulo bem aberto/
	-- lateral contém o quanto ele desliza pro lado, deixando ele mais perto
	-- do CENTRO em vez de escancarar o lado oposto do gol perseguindo a
	-- bola até a ponta.
	local lateral = lateralAxis:Dot(Vector3.new(toBall.X, 0, toBall.Z))
		* lateralFollowFraction(teamName, anchor)
		* diagonalCenteringFactor(teamName, anchor, lateralAxis, toBall)

	local maxLateral = AREA_SIDE_FALLBACK_RADIUS
	if area then
		-- Metade do tamanho da área no eixo lateral (Size.X, convenção de
		-- Part de área alinhada com a linha do gol) — limita o quanto ele
		-- desliza pra cada lado sem sair da própria grande área.
		maxLateral = area.Size.X / 2
	end

	-- ⚠️ CORRIGIDO ("goleiro passando da trave e deixando o gol livre"): a
	-- Part GKArea_<Time> normalmente é bem mais larga que o gol em si (ela
	-- cobre a GRANDE ÁREA inteira, não só a boca do gol) — clampar só por
	-- ela deixava o bot deslizar pra fora da linha do gol de verdade.
	-- Agora usa o MENOR entre a área e a largura real do gol (+ uma
	-- margem configurável, 0 por padrão — "não é recomendado ficar mais
	-- pra esquerda do que na ponta da trave").
	local goalHalf = goalHalfWidth(teamName)
	if goalHalf then
		-- ⚠️ v16: PEDIDO — "o mais longe que ele pode se mover é um pouco
		-- menos, não na trave exatamente". Antes o teto era a própria ponta
		-- da trave (goalHalf + margem 0), então no limite ele ficava colado
		-- num poste com o gol inteiro aberto do outro lado. Agora só alcança
		-- uma FRAÇÃO desse caminho (GKBOT_LATERAL_GOAL_FRACTION).
		maxLateral = math.min(
			maxLateral,
			goalHalf * Config.GKBOT_LATERAL_GOAL_FRACTION + Config.GKBOT_LATERAL_POST_MARGIN
		)
	end

	lateral = math.clamp(lateral, -maxLateral, maxLateral)

	-- ⚠️ v5.8: PEDIDO — "mova ele uns 2-3 studs pra frente, pra realmente
	-- não bugar o gol". A posição de PATRULHA (não a de perseguição/dive,
	-- que já retornou mais acima) ganha um empurrão fixo pra DENTRO do
	-- campo (fieldForward) — fica uma folga real entre onde o bot descansa
	-- e a linha do gol, então ele intercepta a bola ANTES dela cruzar,
	-- não em cima da própria linha.
	return anchor.Position + fieldForward(teamName) * Config.GKBOT_FORWARD_OFFSET + lateralAxis * lateral
end

-- Pulo (⚠️ CORRIGIDO: agora pode ser DIAGONAL, não só reto pra cima) —
-- quando a bola está alta o bastante acima dos pés do bot (cruzamento/
-- chute mais forte), ele "voa" na diagonal: soma um empurrão no eixo
-- LATERAL (mesmo eixo do movimento normal, nunca o de profundidade) na
-- direção de onde a bola está, JUNTO com o impulso vertical — não usa
-- Humanoid.Jump (depende de JumpPower/JumpHeight configurado no rig, que
-- pode nem estar setado no molde), a velocidade é aplicada direto no
-- HumanoidRootPart, igual o resto do movimento do bot.
-- Devolve true/false — se mergulhou ou não (usado por updateBot pra saber
-- se precisa ESPERAR o mergulho terminar antes de decidir agarrar/repelir
-- — ver reactToBall mais abaixo).
--
-- ⚠️ CORRIGIDO ("bot vira pro lado mas não sai da posição pra pular"): a
-- versão anterior tentava forçar a velocidade HORIZONTAL direto
-- (AssemblyLinearVelocity) — mas o Humanoid (ativo, controlando o
-- personagem normalmente) recalcula/sobrescreve a velocidade dele mesmo
-- sozinho a cada passo de física, então o impulso horizontal morria quase
-- na hora (só o vertical, que o Humanoid não mexe do mesmo jeito,
-- sobrevivia — por isso ele "virava" mas não saía do lugar). A correção:
-- tirar o bloqueio que existia em updateBotMovement e, em vez de um
-- impulso bruto, fazer o bot ANDAR de verdade até a bola (ChaseTarget),
-- pelo mesmo sistema confiável de sempre (Humanoid:MoveTo +
-- AssemblyLinearVelocity aplicado TODO heartbeat), só que numa velocidade
-- bem maior (GKBOT_CHASE_SPEED) e sem o clamp lateral normal. O pulo
-- vertical continua sendo um impulso direto (é o único jeito de fazer o
-- Humanoid decolar do chão).
-- ⚠️ v3.3: ganhou um `predictedPoint` opcional (posição FUTURA da bola,
-- vinda de findClosestPredictedPoint em cima da trajetória prevista com
-- gravidade — ver updateBot, gatilho 2) — quando presente, o mergulho
-- mira ONDE A BOLA VAI CHEGAR em vez de onde ela está agora, o que é o
-- que faz o mergulho sair na DIAGONAL certa de verdade pra interceptar
-- (pedido: "ele não dá dive pra diagonal... ele conseguirá ver a
-- trajetória e ver o melhor caminho"). O alvo final é sempre clampado pra
-- dentro da própria Part GKArea_<Time> (clampPointToOwnArea) — usa a
-- hitbox da área como limite de até onde faz sentido o bot ir buscar,
-- pedido explícito do usuário.
local function maybeJumpForBall(teamName, bot, predictedPoint)
	local root = bot.Root
	if not root then return false end

	local targetPoint = predictedPoint or ball.Position

	local heightAboveFeet = targetPoint.Y - root.Position.Y
	local lateralAxis = lateralAxisOf(teamName)
	local toTarget = targetPoint - root.Position
	local lateralOffset = lateralAxis:Dot(Vector3.new(toTarget.X, 0, toTarget.Z))
	local lateralDistance = math.abs(lateralOffset)

	-- ⚠️ v6.2: PEDIDO — "ele precisa calcular se o dive vale a pena ou não,
	-- se a bola for passar dele com uma distância de pelo menos 1/3 do
	-- tamanho do dive, ele dará o dive". Config.GKBOT_DIVE_REACH representa
	-- o quão longe de verdade o mergulho consegue alcançar (studs) — vale a
	-- pena mergulhar só quando a bola vai passar longe o BASTANTE (pelo
	-- menos 1/3 do alcance — perto demais disso ele já pega parado, sem
	-- precisar arriscar um mergulho) e ainda DENTRO do alcance (mergulhar
	-- pra uma bola que nem o mergulho alcança não adianta nada). Antes o
	-- mergulho rasteiro (needsGroundDive) só olhava um piso fixo
	-- (GKBOT_DIVE_MIN_LATERAL_DISTANCE) sem nenhum teto — agora os dois
	-- limites vêm do mesmo alcance de verdade do mergulho.
	-- ⚠️ v22 — PEDIDO: "melhora o dive dele pra caralho... ele às vezes falha
	-- em bola simples que passa do lado dele, e é porque tá faltando dive."
	--
	-- O piso era GKBOT_DIVE_REACH/3 (7 studs com o alcance antigo): bola
	-- passando entre "colado nele" e esse piso não gerava mergulho NENHUM —
	-- ele assumia que pegava parado, e não pegava. Era exatamente a bola
	-- simples passando de raspão. Agora o piso é a própria caixa de captura
	-- garantida (GKBOT_GUARANTEED_CATCH_BOX): dentro dela ele já pega sem
	-- mergulhar, e QUALQUER coisa além dela até o limite do alcance vira
	-- mergulho. Não sobra buraco entre os dois comportamentos.
	local guaranteedBox = Config.GKBOT_GUARANTEED_CATCH_BOX
	local diveWorthMin = math.min(guaranteedBox.X, guaranteedBox.Z)
	local diveWorthMax = Config.GKBOT_DIVE_REACH
	local worthDiving = lateralDistance >= diveWorthMin and lateralDistance <= diveWorthMax

	local needsAerialDive = heightAboveFeet >= Config.GKBOT_JUMP_MIN_BALL_HEIGHT and lateralDistance <= diveWorthMax
	-- ⚠️ mergulho também dispara por DISTÂNCIA LATERAL, não só altura —
	-- sem isso, um chute RASTEIRO no canto nunca fazia o bot ir atrás.
	local needsGroundDive = worthDiving
	if not needsAerialDive and not needsGroundDive then return false end

	-- ⚠️ v109 — PEDIDO: "ele não está dando dives, está só indo até a bola. Se ele
	-- calcular que precisa dar o dive, tem que dar o dive." Antes o "mergulho"
	-- rasteiro era o bot CORRENDO em pé até o ponto (ChaseTarget) — a animação de
	-- mergulho tocava, mas o corpo continuava de pé. Agora é um MERGULHO DE CORPO
	-- de verdade, igual o do goleiro humano: o corpo voa deitado de lado (ou pra
	-- frente) até um pouco ALÉM do ponto onde a bola vai passar, dentro da área,
	-- chegando antes dela; bola alta = o mesmo mergulho em arco. No fim ele fica
	-- caído um instante e levanta. Ver o topo de updateBotMovement.
	local alvo = clampPointToOwnArea(teamName, Vector3.new(targetPoint.X, root.Position.Y, targetPoint.Z))
	local desloc = Vector3.new(alvo.X - root.Position.X, 0, alvo.Z - root.Position.Z)
	local dir = desloc.Magnitude > 0.05 and desloc.Unit or (lateralAxis * (lateralOffset >= 0 and 1 or -1))
	local distMergulho = math.min(desloc.Magnitude + 1.5, Config.GKBOT_DIVE_REACH)
	local tempoBola = bot.TempoAteBola or 0.5
	-- ⚠️ v110 — PEDIDO: "o GK tá impossível, não dá tempo da bola chegar" + "bola
	-- aérea, ele teleporta pra bola". A duração era min(distância/velocidade,
	-- tempo até a bola) — ele SEMPRE chegava antes, mesmo que precisasse voar em
	-- 0.18s. Agora é a duração real do voo: se a bola chegar antes, ele não pega.
	local _ = tempoBola
	local dur = math.clamp(distMergulho / (Config.GKBOT_DIVE_SPEED or 52), 0.25, 0.6)
	local direita = root.CFrame.RightVector
	local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	frente = frente.Magnitude > 0.05 and frente.Unit or Vector3.new(0, 0, -1)
	-- v110 — "o dive tem que ser mais alto, chegar perto do travessão" e "não pode
	-- atravessar a parede": sobe até a altura da bola (teto GKBOT_DIVE_ALTURA_MAX) e
	-- a distância é cortada antes de qualquer coisa sólida no caminho.
	do
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.RespectCanCollide = true
		local ignorar = { ball, bot.Model }
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
		params.FilterDescendantsInstances = ignorar
		local hit = workspace:Raycast(root.Position, dir * (distMergulho + 2), params)
		if hit then distMergulho = math.max(0, (hit.Position - root.Position).Magnitude - 2.5) end
	end
	bot.DiveMove = {
		Inicio = root.Position,
		Fim = root.Position + dir * distMergulho,
		T0 = tick(),
		Dur = dur,
		Deitado = 0.45,
		Altura = needsAerialDive and math.clamp(heightAboveFeet - 0.5, 0, Config.GKBOT_DIVE_ALTURA_MAX or 13) or 0,
		Rot = CFrame.lookAt(Vector3.zero, frente).Rotation,
		Lado = direita:Dot(dir) >= 0 and 1 or -1,
		Lateral = math.abs(direita:Dot(dir)),
		Frente = math.max(frente:Dot(dir), 0),
	}
	bot.ChaseTarget = nil
	if bot.Humanoid then bot.Humanoid.PlatformStand = true end
	if true then return true end -- (o impulso antigo abaixo ficou de reserva)

	if needsAerialDive then
		-- ⚠️ NOVO: o Humanoid parado no chão fica "colado" nele (o
		-- controlador interno realinha a altura sozinho todo passo de
		-- física, cancelando um Y de velocidade arbitrário do mesmo jeito
		-- que cancelava o horizontal) — ChangeState(Jumping) avisa o
		-- Humanoid que ele SAIU do chão de propósito, então ele para de
		-- "grudar" e deixa a física de verdade (com o Y que a gente
		-- setou) levar o bot pra cima.
		if bot.Humanoid then
			bot.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end

		-- ⚠️ v5.9: PEDIDO — "ele ainda não está dando o dive diagonal,
		-- apenas o pulo". Antes o impulso só mexia no Y, mantendo o X/Z
		-- que já estava rolando — o componente LATERAL dependia inteiro
		-- do sistema de perseguição (chase), que só recalcula a
		-- velocidade no PRÓXIMO heartbeat (bot.LastMoveAt=0 força isso,
		-- mas ainda é 1 frame de atraso) e, pra um alvo quase centralizado,
		-- mal deslocava ele de lado — na prática só aparecia o pulo reto.
		-- Agora o próprio impulso já sai DIAGONAL: soma um empurrão
		-- horizontal na direção do alvo (lateralOffset) JUNTO com o
		-- vertical, no mesmo instante — sem esperar o próximo recálculo.
		local lateralSign = lateralOffset >= 0 and 1 or -1
		local horizontalKick = lateralAxis * (lateralSign * Config.GKBOT_DIVE_DIAGONAL_KICK)
		root.AssemblyLinearVelocity = Vector3.new(horizontalKick.X, Config.GKBOT_DIVE_UP_SPEED, horizontalKick.Z)
	end

	return true
end

-- ⚠️ CORRIGIDO: Humanoid:MoveTo depende do rig do Model ter juntas/
-- Motor6D válidas e do pathing interno do Humanoid pra "decidir" andar —
-- num NPC clonado isso às vezes simplesmente não anda 1 cm mesmo sem
-- nada Anchored (rig incompleto, animação de andar ausente, etc.). Pra
-- não depender disso, o movimento de verdade agora é feito por
-- VELOCIDADE DIRETA no HumanoidRootPart (AssemblyLinearVelocity) — isso
-- SEMPRE desloca a part, é o mesmo princípio que já usamos em
-- clearBall/beginCatch pra mexer a bola. Ainda chama Humanoid:MoveTo
-- também (de graça, ajuda a tocar a animação de andar SE o rig tiver
-- uma), mas quem garante o deslocamento é a velocidade.
local function updateBotMovement(teamName, bot)
	-- ⚠️ v27: mantém a guarda da Hissatsu colada na frente dele (e some
	-- sozinha quando a janela fecha).
	updateBotGuard(bot)
	local root = bot.Root
	local humanoid = bot.Humanoid
	if not root or not root.Parent then return end

	-- ⚠️ v109: MERGULHO DE CORPO em andamento (ver maybeJumpForBall) — o corpo
	-- é levado por CFrame (igual o mergulho do goleiro humano), deitando de
	-- lado nos primeiros 40% do voo; bola alta sobe em arco. Depois fica caído
	-- `Deitado` segundos e levanta em pé no ponto onde parou.
	local dm = bot.DiveMove
	if dm then
		local agora = tick()
		local u = math.clamp((agora - dm.T0) / dm.Dur, 0, 1)
		local e = 1 - (1 - u) ^ 2
		local pos = dm.Inicio:Lerp(dm.Fim, e)
		local k = math.clamp(u / 0.4, 0, 1)
		-- v110: sobe até a altura da bola e CHEGA lá no fim do voo (antes subia e
		-- descia no meio); depois do voo cai de volta durante o tempo caído
		local depoisVoo = math.clamp((agora - dm.T0 - dm.Dur) / math.max(dm.Deitado, 0.05), 0, 1)
		local arco = dm.Altura * (1 - (1 - u) ^ 2) * (1 - depoisVoo * depoisVoo)
		local baixo = -1.7 * k * (dm.Altura > 0 and depoisVoo or 1)
		root.CFrame = CFrame.new(pos + Vector3.new(0, arco + baixo, 0)) * dm.Rot
			* CFrame.Angles(math.rad(-55) * dm.Frente * k, 0, math.rad(dm.Altura > 0 and -48 or -78) * dm.Lado * dm.Lateral * k) -- (aéreo = diagonal, mais de pé)
		root.AssemblyLinearVelocity = Vector3.zero
		root.AssemblyAngularVelocity = Vector3.zero
		if agora - dm.T0 >= dm.Dur + dm.Deitado then
			bot.DiveMove = nil
			root.CFrame = CFrame.new(Vector3.new(dm.Fim.X, dm.Inicio.Y, dm.Fim.Z)) * dm.Rot
			if humanoid then humanoid.PlatformStand = false end
		end
		return
	end

	-- Recalcula o ALVO só de vez em quando (barato, mas não precisa ser
	-- por frame) — guardado no próprio bot pra ser reaplicado TODO
	-- heartbeat abaixo, já que a fricção do chão vai reduzindo a
	-- velocidade horizontal entre um recálculo e outro se a gente não
	-- reforçar ela sempre.
	-- ⚠️ CORRIGIDO ("tira o script de bloquear a movimentação"): antes
	-- tinha um "return" aqui enquanto bot.DivingUntil estava ativo, pra
	-- não atrapalhar o impulso do mergulho — não existe mais, porque o
	-- mergulho/bote agora É esse mesmo sistema de movimento (via
	-- ChaseTarget), só que numa velocidade maior — ver computeMoveTarget.
	if tick() - bot.LastMoveAt >= MOVE_UPDATE_INTERVAL then
		bot.LastMoveAt = tick()

		-- Perseguição (dive/bote) expirou sozinha (acabou o tempo sem
		-- decisão) OU a bola saiu da área durante a perseguição — pedido:
		-- "obriga ele a voltar pra posição original... ou se ela sair de
		-- area". Limpa ChaseTarget pra computeMoveTarget voltar a mirar a
		-- posição normal (lateral, clampada) já no próximo cálculo.
		if bot.ChaseTarget then
			local chaseExpired = tick() >= (bot.ChaseUntil or 0)
			local ballLeftArea = findAreaPart(teamName) ~= nil and not isInsideOwnArea(teamName, ball.Position)
			if chaseExpired or ballLeftArea then
				bot.ChaseTarget = nil
			end
		end

		bot.MoveTarget = computeMoveTarget(teamName, bot)
	end

	local target = bot.MoveTarget
	if not target then return end

	local currentFlat = Vector3.new(root.Position.X, 0, root.Position.Z)
	local targetFlat = Vector3.new(target.X, 0, target.Z)
	local toTarget = targetFlat - currentFlat
	local distance = toTarget.Magnitude

	local currentVelocity = root.AssemblyLinearVelocity

	if distance < 1 then
		-- já chegou: zera só o componente horizontal (não mexe na
		-- vertical, senão o bot "flutua" ou trava contra a gravidade).
		root.AssemblyLinearVelocity = Vector3.new(0, currentVelocity.Y, 0)
		return
	end

	-- ⚠️ NOVO: velocidade maior (GKBOT_CHASE_SPEED) enquanto perseguindo
	-- de verdade uma bola/adversário (dive/bote em andamento) — "faz o
	-- bot se mover mais rápido, ele tá muito lento pra alguns chutes".
	-- ⚠️ v40: correr também pra alcançar a interceptação da Hissatsu — de
	-- nada adianta saber o ponto certo e ir andando devagar pra lá, a bola
	-- chega primeiro.
	local chasing = (bot.ChaseTarget ~= nil and tick() < (bot.ChaseUntil or 0))
		or (bot.GuardIntercept ~= nil and tick() < (bot.GuardInterceptUntil or 0))
	local speed = chasing and Config.GKBOT_CHASE_SPEED or Config.GKBOT_WALK_SPEED

	local direction = toTarget.Unit
	root.AssemblyLinearVelocity = Vector3.new(direction.X * speed, currentVelocity.Y, direction.Z * speed)

	-- ⚠️ v21 — PEDIDO: "ele só se move virando, vira pra um lado pra
	-- acompanhar, vira pro outro. Ele tem que ficar reto olhando pra bola
	-- sempre, e só se mover de um lado pro outro olhando pra bola, fixo."
	--
	-- O Humanoid gira o corpo sozinho na direção do MOVIMENTO (AutoRotate),
	-- e como o bot desliza de um lado pro outro, ele ficava rodando 180° a
	-- cada correção — aquele "esquisito". Com AutoRotate desligado (ver a
	-- criação do bot) a orientação passa a ser nossa: ele encara a bola o
	-- tempo todo e o deslize vira andar de lado, como um goleiro de verdade.
	-- ⚠️ v40 — PEDIDO: "coloca pra ele poder ficar RETINHO na Hissatsu do
	-- chute e tentar fazer." Durante a interceptação de uma Hissatsu ele
	-- para de encarar a bola e fica de frente pro campo, reto. Dois
	-- motivos: a guarda da Hissatsu é plantada na frente dele seguindo o
	-- fieldForward (ver updateBotGuard), então corpo torto = guarda torta,
	-- cobrindo menos boca de gol; e o giro constante atrás da bola era
	-- parte do "ele fica se mexendo de um lado pro outro".
	local interceptando = bot.GuardIntercept ~= nil and tick() < (bot.GuardInterceptUntil or 0)
	if interceptando then
		local frente = fieldForward(teamName)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + frente)
	else
		local ballFlat = Vector3.new(ball.Position.X, root.Position.Y, ball.Position.Z)
		if (ballFlat - root.Position).Magnitude > 0.5 then
			root.CFrame = CFrame.lookAt(root.Position, ballFlat)
		end
	end

	if humanoid then
		-- ⚠️ v15 FIX: o WalkSpeed do bot ficava SEMPRE em GKBOT_WALK_SPEED
		-- (36), inclusive durante perseguição/mergulho, que deveriam usar
		-- GKBOT_CHASE_SPEED (58). Como o Humanoid recalcula a velocidade dele
		-- sozinho a cada passo de física (o próprio comentário de
		-- maybeJumpForBall explica isso), ele capava o impulso de 58 de volta
		-- pra 36 no frame seguinte — ou seja, a velocidade de perseguição
		-- existia na config e nunca acontecia em campo. É boa parte do "ele
		-- vai muito devagarinho" quando a bola está pro lado.
		-- Seguro mexer aqui: enquanto o bot está Holding (segurando a bola),
		-- updateBotMovement não roda (ver beginCatch), então isso nunca
		-- atropela o WalkSpeed = 0 de lá.
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
		humanoid:MoveTo(target) -- best-effort, só pra tocar a animação de andar SE o rig tiver uma — não é de quem depende o deslocamento
	end
end

-- ===== REPELIR (comportamento antigo — só roda se o agarre falhar) =====
local function clearBall(teamName, bot)
	if _G.ReleaseBallOwner then
		_G.ReleaseBallOwner()
	end

	local root = bot.Root
	local away = ball.Position - root.Position
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude < 0.1 then
		-- ⚠️ CORRIGIDO: LookVector do bot pode apontar pra QUALQUER lado
		-- (inclusive pro próprio gol) — fieldForward nunca aponta pro
		-- próprio gol, sempre pro campo, então o "alívio" nunca lança a
		-- bola pra dentro da própria hitbox de gol nesse caso raro.
		away = fieldForward(teamName)
	end
	away = away.Unit

	ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	ball.Position = root.Position + away * 3 + Vector3.new(0, 2, 0)
	ball.AssemblyLinearVelocity = away * Config.GKBOT_CLEAR_FORCE + Vector3.new(0, 14, 0)
	-- ⚠️ v84: registra o toque do bot (ver _G.MarkBotBallTouch no
	-- BallController) — é o que deixa o MatchController anular gol contra
	-- do GK BOT.
	if _G.MarkBotBallTouch then _G.MarkBotBallTouch(teamName) end
end

-- ⚠️ v39 — RESOLUÇÃO DA DEFESA DE HISSATSU DO BOT (reescrita).
--
-- BUG QUE ISSO CONSERTA (três sintomas, uma causa só): "o número zero
-- vermelho fica pra sempre em cima da bola", "ele pegou uma Hissatsu de
-- 200 com mergulho comum" e "o soco dele só pegou a bola em vez de
-- rebater".
--
-- A v38 colocou a resolução da defesa DENTRO de dois `if` aninhados:
-- `PulseDefenseActiveUntil` (a janela da Hissatsu) e `ballInsideGuard`
-- (a bola está na caixa da guarda). Só que a caixa da guarda ANDA JUNTO
-- com o bot todo frame (ver updateBotGuard) e a bola fica ANCORADA
-- durante a drenagem — então bastava o bot dar um passo pro lado pra bola
-- congelada sair da caixa. A partir daí:
--   1) a resolução nunca rodava -> a drenagem nunca fechava -> o número
--      vermelho ficava na tela pra sempre e a bola ficava congelada;
--   2) a janela da Hissatsu expirava, `IncomingShotUntil` expirava junto,
--      e aí a bola parada bem na frente dele virava "bola solta" pro
--      caminho normal -> a caixa de captura garantida agarrava ela. Era
--      isso o "pegou 200 de força com mergulho comum": ele não defendeu
--      um chute de 200, ele catou uma bola PARADA.
--
-- Agora a defesa, uma vez COMEÇADA, resolve sozinha por TEMPO (task.delay
-- agendado no contato), sem depender da posição da bola nem da janela da
-- Hissatsu continuar aberta. É impossível ficar pendurada.
local function resolveGuardContact(teamName, bot)
	if bot.GuardRolled ~= nil then return end -- já resolvida
	if not bot.GuardContactAt then return end

	if bot.Duelo then
		-- ⚠️ v103: duelo de defesa — defendeu = os acertos zeraram a força
		bot.GuardRolled = bot.Duelo.Atual() <= 0
	else
		local skill = fieldSkillFraction()
		local chance = Config.GKBOT_PULSE_HIT_CHANCE_MIN
			+ (Config.GKBOT_PULSE_HIT_CHANCE_MAX - Config.GKBOT_PULSE_HIT_CHANCE_MIN) * skill
		bot.GuardRolled = math.random() < chance
	end
	bot.GuardResolvedAt = tick()

	-- Fecha o número da força: PEGOU = 0 (absorveu tudo), PASSOU = para no
	-- valor drenado. Isto SEMPRE roda agora — era exatamente o que ficava
	-- pendurado antes.
	local forcaRestante = 0
	if bot.Duelo then
		forcaRestante = bot.Duelo.Encerrar(bot.GuardRolled) or 0
		bot.Duelo = nil
	elseif bot.GuardDrainFinish then
		-- ⚠️ v41: devolve a força que SOBROU — a vida com que a bola segue
		-- voando se tiver atravessado a guarda.
		forcaRestante = bot.GuardDrainFinish(bot.GuardRolled) or 0
		bot.GuardDrainFinish = nil
	end

	if bot.GuardFroze and _G.ReleaseBallFromQTE then
		_G.ReleaseBallFromQTE()
	end
	bot.GuardFroze = nil
	-- ⚠️ v40: acabou a jogada — destrava o alvo de interceptação pra ele
	-- voltar ao posicionamento normal (senão ficaria plantado no ponto do
	-- chute anterior até a janela expirar).
	bot.GuardIntercept = nil
	bot.GuardInterceptUntil = nil

	local root = bot.Root
	if not (root and root.Parent) then
		showBotGuardResult(bot, bot.GuardRolled)
		return
	end

	if not bot.GuardRolled then
		-- ⚠️ v105 — PEDIDO: "com o GK bot, você chuta nele e a bola passa, só
		-- que buga pra fora — o bot redireciona a bola... se ele não conseguir
		-- pegar, a bola passa pelo GK e entra no gol. Dá um stunzinho no GK pra
		-- ele não tentar de novo." A bola retomava o voo e, no quadro seguinte,
		-- o bot (ainda "vivo") mergulhava / afastava a bola (clearBall) — era
		-- o tapa de lado que mandava a Hissatsu pra fora. Perdeu = atordoado.
		bot.AtordoadoAte = tick() + (Config.GKBOT_ATORDOADO_APOS_FALHA or 1.6)
		bot.DiveActive = false
		bot.ChaseTarget = nil
		-- ⚠️ v110 — PEDIDO: "alguns chutes que o GK tenta defender saem pra fora, nem
		-- volta a descer a energia". O corpo do bot (deitado no caminho depois do
		-- mergulho) tem colisão com a bola: ela retomava o voo, batia nele, o
		-- detector de desvio brusco encerrava o voo e ela saía torta, sem perder
		-- força. Perdeu o duelo = o corpo dele atravessável por um instante.
		if bot.Model then
			local desligadas = {}
			for _, p in ipairs(bot.Model:GetDescendants()) do
				if p:IsA("BasePart") and p.CanCollide then
					p.CanCollide = false
					table.insert(desligadas, p)
				end
			end
			task.delay(1.4, function()
				for _, p in ipairs(desligadas) do
					if p.Parent then p.CanCollide = true end
				end
			end)
		end
		-- ⚠️ v41 — PEDIDO: "11 de força ainda é movimento... a bola vai
		-- continuar andando na MESMA velocidade, nesse caso ela entraria no
		-- gol de todo jeito." O empurrãozinho fixo que existia aqui fazia a
		-- bola PARAR no ar depois de uma defesa que quase segurou — força
		-- baixa virava velocidade baixa, e não é isso que o número quer
		-- dizer. Agora ela retoma o voo exatamente como estava, só com
		-- menos vida.
		local retomou = _G.ResumePulseFlightAfterGuard
			and _G.ResumePulseFlightAfterGuard(forcaRestante)
		if not retomou then
			-- só se não havia velocidade guardada (caso de borda)
			local ownGoal = ownGoalOf(teamName)
			local towardGoal = ownGoal and (ownGoal.Position - ball.Position)
			if towardGoal and towardGoal.Magnitude > 0.1 then
				ball.AssemblyLinearVelocity = towardGoal.Unit * Config.GKBOT_GUARD_BREAKTHROUGH_SPEED
			end
		end
	elseif bot.GuardRebound then
		-- ⚠️ v39 — PEDIDO: "o soco que ele utilizou era pra ele ter lançado
		-- a bola pra longe, porque é o efeito dela. O efeito do soco do GK
		-- é dar um knockback na bola. E ele só pegou a bola em vez de dar o
		-- knockback."
		--
		-- O Soco Explosivo (Bakuretsu Punch) é a ÚNICA guarda de goleiro
		-- que nunca segura a bola — ela sempre rebate (ver PulseInstinctData,
		-- onde ela é a única com Rebate = true). Isso estava descrito no
		-- texto dela e no comentário "de propósito SEM GuaranteedCatch",
		-- mas nunca tinha sido implementado como comportamento: sem um
		-- sinal explícito, defender era sempre sinônimo de agarrar.
		--
		-- Rebate pro CAMPO (fieldForward nunca aponta pro próprio gol) com
		-- um arco pra cima, igual o alívio normal — a defesa foi um sucesso,
		-- o preço é o rebote sobrando em jogo.
		if _G.ReleaseBallOwner then _G.ReleaseBallOwner() end
		local away = fieldForward(teamName)
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.Position = root.Position + away * 3 + Vector3.new(0, 2, 0)
		ball.AssemblyLinearVelocity = away * Config.GKBOT_PUNCH_REBOUND_FORCE + Vector3.new(0, 16, 0)
		if _G.MarkBotBallTouch then _G.MarkBotBallTouch(teamName) end -- ⚠️ v84: ver clearBall
		print(string.format(
			"🥊 [GKBot] %s REBATEU a Hissatsu com \"%s\" (essa guarda nunca segura — sempre sobra rebote).",
			teamName, bot.Pulse and bot.Pulse.Name or "?"
		))
	end

	showBotGuardResult(bot, bot.GuardRolled)
end

-- ===== AGARRAR (⚠️ NOVO) =====

-- ⚠️ v6.4: PEDIDO — "o único momento que a hitbox dele é desligada é
-- quando ele passa a bola, e 0.5 segundos depois ela é religada de novo".
-- Único motivo que bloqueia a captura por contato agora (ver
-- tryContactCatch mais abaixo) — substitui o antigo "justThrew"/
-- Config.GKBOT_POST_THROW_LOCK_SECONDS local em updateBot por uma checagem
-- única e reaproveitável (config renomeada pra GKBOT_HITBOX_DISABLE_AFTER_
-- THROW, ver FootballConfig.lua).
local function isHitboxDisabled(bot)
	return (tick() - (bot.LastThrowAt or 0)) < Config.GKBOT_HITBOX_DISABLE_AFTER_THROW
end

-- ⚠️ v6.4: PEDIDO — "de novo está dando algumas falhas, não necessariamente
-- é quando o GK toma gol, é em qualquer momento... assim que entrar em
-- contato com a bola, pega". A causa dessas falhas "em qualquer momento"
-- (sem relação com gol/kickoff) era ESTA função: mesmo com a bola bem em
-- cima do bot e de frente, o "agarrar" nunca era garantido — tinha um dado
-- de chance (podia ser só 10% de chance perto do limite do alcance) que
-- fazia ele simplesmente FALHAR e repelir a bola (clearBall) mesmo com
-- tudo "certo" (distância e ângulo OK). Isso não é bug de timing/race — era
-- assim de propósito desde o início — mas o pedido agora é remover essa
-- incerteza: dentro do alcance (a "hitbox") e do ângulo, a captura é
-- SEMPRE garantida — só falha por estar longe demais ou vindo de um
-- ângulo fechado/por trás demais (limites físicos, não sorte).
-- ⚠️ v9 REWORK — PEDIDO: "o GK tem em base todos os status juntos de
-- todos os jogadores do campo... isso também conta pra defender chutes de
-- pulso igual o gk (player) consegue com físico... atualmente o GKBOT
-- cata pulso com facilidade, após adicionar essa melhoria, não vai ser
-- 100% garantido, pra dar lógica ao jogo". Dentro do alcance/ângulo
-- normais (testados abaixo, igual antes) a pegada só continua 100%
-- garantida quando NÃO tem chute perigoso recente (dangerRating == 0,
-- igual sempre foi pra bola solta/passe/chute fraco) OU quando o Physical
-- MÉDIO do campo (getGKBotPhysical) alcança a força desse chute — a
-- MESMA regra do goleiro humano (getPhysical(player) >=
-- currentDangerForceRating(player) em BallController.legacy.luau, só que
-- por TIME em vez de Player, via _G.GetDangerForceRatingForTeam). Só
-- quando o chute é forte demais pro Physical médio é que vira uma CHANCE
-- de verdade (nunca 0%, nunca garantida).
local function attemptCatch(teamName, bot)
	-- ⚠️ NOVO: Pulso de goleiro do bot ACERTOU essa Hissatsu há pouco (ver
	-- o listener de _G.RegisterPulseShotListener acima) — defesa
	-- garantida por um instante, com alcance bem maior, igual o
	-- "GuaranteedCatch" do Pulso humano (Mão Divina/Guardião Absoluto).
	-- ⚠️ v27: com a Hissatsu ativa, a defesa acontece quando a bola ENTRA NA
	-- GUARDA (a área visível na frente dele) — não mais "a bola chegou a 27
	-- studs, agarrou". Era isso que fazia parecer que ele pegava a bola no
	-- ar assim que o chute saía.
	-- ⚠️ v39: defesa de Hissatsu JÁ EM ANDAMENTO tem prioridade sobre TUDO,
	-- inclusive sobre a janela da Hissatsu ter expirado. Enquanto a força
	-- drena, a bola está congelada na frente dele e nada mais pode
	-- acontecer com ela — sem isso, era por aqui que a bola parada virava
	-- "bola solta" e era catada pelo caminho normal (ver o comentário
	-- completo em resolveGuardContact).
	if bot.GuardContactAt then
		if bot.GuardRolled == nil then
			return false -- ainda defendendo: a força está caindo na tela
		end
		-- Resolvida: só agarra de verdade se essa guarda SEGURA a bola.
		-- A que rebate (Soco Explosivo) já devolveu a bola pro campo lá
		-- dentro de resolveGuardContact — devolver `true` aqui faria o
		-- beginCatch agarrar logo depois do soco, que é exatamente o bug.
		return bot.GuardRolled and not bot.GuardRebound
	end

	if bot.PulseDefenseActiveUntil and tick() < bot.PulseDefenseActiveUntil then
		if ballInsideGuard(bot) then
			-- ⚠️ v28: o sorteio de acerto/erro acontece no CONTATO, não no
			-- instante do chute — é onde existe um momento de tela pra
			-- mostrar o resultado, com a bola chegando.
			--
			-- ⚠️ v38/v39 — PEDIDO: "mostre em tempo real, enquanto o goleiro
			-- estiver defendendo a Hissatsu, a força da Hissatsu
			-- diminuindo." O goleiro humano já tinha essa janela de graça (a
			-- bola congela e o QTE de colisão roda); o bot resolvia tudo no
			-- mesmo frame do contato. Aqui ele ABRE a janela: congela a
			-- bola, começa a drenagem e AGENDA a resolução por tempo. O
			-- agendamento é o ponto — v38 dependia de continuar sendo
			-- chamado com a bola dentro da caixa, e era isso que travava.
			bot.GuardContactAt = tick()
			-- lê a força ANTES de congelar: _G.FreezeBallForQTE chama
			-- stopPulseStraightFlight, que zera esse valor.
			local forcaNaColisao = (_G.GetPulseLiveForce and _G.GetPulseLiveForce()) or bot.IncomingShotForce
			-- ⚠️ v41: guarda a velocidade ANTES de congelar — força é a VIDA
			-- da bola, não a velocidade dela, então se ela atravessar a
			-- guarda tem que seguir no mesmo rumo e no mesmo módulo (ver
			-- resumePulseFlightAfterGuard em BallController).
			if _G.CapturePulseFlightForGuard then _G.CapturePulseFlightForGuard() end
			bot.GuardFroze = (_G.FreezeBallForQTE and _G.FreezeBallForQTE()) or false
			-- ⚠️ v103 — DUELO DE DEFESA. PEDIDO: "o GK ao defender SUGA a vida
			-- da bola antes de fazer o QTE... o que vai dar dano é quantas vezes
			-- o GK acertar a hissatsu dele". A força congela aqui e só cai por
			-- ACERTO. O bot não tem QTE de verdade: ele "aperta" a cada
			-- GKBOT_DUELO_INTERVALO com uma chance de acertar (maior com o
			-- time mais forte), até o número de acertos da Hissatsu dele.
			if _G.IniciarDueloDeDefesa then
				bot.Duelo = _G.IniciarDueloDeDefesa(forcaNaColisao)
			elseif _G.BeginGuardForceDrain then
				bot.GuardDrainFinish = _G.BeginGuardForceDrain(forcaNaColisao, getGKBotPhysical())
			end
			-- Essa guarda segura a bola ou rebate? (ver Rebate em
			-- PulseInstinctData — só o Soco Explosivo rebate.)
			local efeito = bot.Pulse and (bot.Pulse.Perfect or bot.Pulse.Bom)
			bot.GuardRebound = (efeito and efeito.Rebate) and true or false

			if bot.Duelo then
				local duelo = bot.Duelo
				local def = bot.Pulse
				local skill = fieldSkillFraction()
				local tentativas = (def and def.QTE and def.QTE.RequiredHits) or 5
				local chanceAcerto = math.clamp((Config.GKBOT_DUELO_CHANCE_ACERTO or 0.6) * (0.7 + 0.6 * skill), 0.1, 0.95)
				local dano = ((Config.DEFESA_DANO_POR_ACERTO or {})[def and def.Rarity or "Common"] or 25) * (0.8 + 0.4 * skill)
				-- ⚠️ v107: mesma conta do goleiro humano — impacto + por acerto, com elemento
				local impacto = 0
				if def and _G.DanoDaDefesa then
					impacto, dano = _G.DanoDaDefesa(nil, def, 0.8 + 0.4 * skill)
				end
				-- ⚠️ v103: cutscene da defesa do bot pela duração do duelo
				local durBot = tentativas * (Config.GKBOT_DUELO_INTERVALO or 0.45) + 0.4
				local fimBot = tick()
				if _G.TocarCutsceneDeDefesa and bot.Model and _G.TocarCutsceneDeDefesa(bot.Model, def, durBot) then
					fimBot = tick() + durBot
				end
				task.spawn(function()
					if impacto > 0 then
						task.wait(0.5)
						if bot.Duelo ~= duelo or bot.GuardRolled ~= nil then return end
						duelo.Dano(impacto)
					end
					for _ = 1, tentativas do
						if duelo.Atual() <= 0 then break end
						task.wait(Config.GKBOT_DUELO_INTERVALO or 0.45)
						if bot.Duelo ~= duelo or bot.GuardRolled ~= nil then return end
						if math.random() < chanceAcerto then
							duelo.Dano(dano)
							if duelo.Atual() <= 0 then break end
						end
					end
					task.wait(math.max(0.2, fimBot - tick()))
					resolveGuardContact(teamName, bot)
				end)
			else
				task.delay(Config.GKBOT_GUARD_DRAIN_SECONDS, function()
					resolveGuardContact(teamName, bot)
				end)
			end
			return false
		end
		-- Hissatsu de pé mas a bola ainda não chegou: NÃO pega por outro
		-- caminho, senão o efeito visual não significaria nada.
		return false
	end

	local root = bot.Root
	local toBall = ball.Position - root.Position
	local flatToBall = Vector3.new(toBall.X, 0, toBall.Z)
	local distance = flatToBall.Magnitude

	-- ⚠️ v21 — PEDIDO: "o bot tem dificuldade pra pegar bolas simples que
	-- passam na frente dele. Ele não pode falhar, é pra pegar sempre: a bola
	-- passou dentro dele, ele pegou. Tem uma hitbox quadrada em volta dele e
	-- ele pega na hora. A não ser que esteja usando Hissatsu."
	--
	-- Caixa em volta do corpo do bot (em espaço LOCAL dele, por isso
	-- "quadrada" de verdade e não um raio): bola dentro dela = defesa, ponto.
	-- Isso passa POR CIMA do teste de ângulo logo abaixo, que era o que fazia
	-- ele ignorar bola cruzando rente ao corpo.
	--
	-- A exceção é exatamente a que você pediu: se vem uma HISSATSU (o
	-- dangerRating só é diferente de zero num chute de Hissatsu, ver
	-- _G.GetDangerForceRatingForTeam em BallController), a captura garantida
	-- NÃO vale — aí a bola tem que ser disputada pelo caminho normal, e é
	-- onde entra a Hissatsu de goleiro (PulseDefenseActiveUntil acima) ou o
	-- Físico dele ser alto o bastante pra segurar mesmo assim.
	-- ⚠️ v26 — A HISSATSU QUE ESTÁ VINDO. Registrada pelo listener do chute
	-- (ver _G.RegisterPulseShotListener acima) com a força REAL, e não
	-- expira por tempo curto como o antigo GetDangerForceRatingForTeam.
	--
	-- PEDIDO: "ele não pode conseguir defender um chute desse sem Hissatsu.
	-- Ele pode TENTAR, mas não pode conseguir."
	-- v110: HITBOX = O CORPO. Só pega se a bola estiver numa esfera em volta dele
	-- (mais um pouco pras mãos) — nada de pegar bola lá no travessão sem pular.
	local dist3D = (ball.Position - root.Position).Magnitude
	local alcanceCorpo = (Config.GKBOT_CORPO_RAIO or 4) + (Config.GKBOT_MAOS_EXTRA or 1.3)
	if dist3D > alcanceCorpo then
		return false
	end
	local incomingHissatsu = bot.IncomingShotUntil and tick() < bot.IncomingShotUntil
	if incomingHissatsu then
		local pulseActive = bot.PulseDefenseActiveUntil and tick() < bot.PulseDefenseActiveUntil
		if pulseActive then
			-- A Hissatsu dele está de pé: essa é a defesa, e ela segura.
			return true
		end
		if (bot.IncomingShotForce or 0) > normalSaveCeiling() then
			-- Forte demais e sem Hissatsu no ar: ele vai até a bola, encosta,
			-- mergulha — e não segura. É o resultado certo.
			return false
		end
		-- Dentro do que ele aguenta: segue pelo caminho normal abaixo.
	else
		-- v110: sem Hissatsu vindo, bola ENCOSTANDO no corpo é defesa garantida
		if dist3D <= (Config.GKBOT_CORPO_RAIO or 4) then
			return true
		end
	end

	if distance > Config.GKBOT_CATCH_MAX_RANGE then
		return false -- longe demais, nem tenta
	end

	if flatToBall.Magnitude > 0.05 then
		local forward = fieldForward(teamName)
		local angle = math.deg(math.acos(math.clamp(forward:Dot(flatToBall.Unit), -1, 1)))
		if angle > Config.GKBOT_CATCH_MAX_ANGLE then
			return false -- ângulo fechado/por trás demais, nem tenta
		end
	end

	local dangerRating = _G.GetDangerForceRatingForTeam and _G.GetDangerForceRatingForTeam(teamName) or 0
	if dangerRating <= 0 then
		return true -- sem chute perigoso recente — agarra sempre, igual antes
	end

	local physical = getGKBotPhysical()
	if physical >= dangerRating then
		return true -- físico médio do campo aguenta esse chute — defesa garantida, igual o goleiro humano
	end

	-- Físico médio abaixo do necessário: chance proporcional a quão perto
	-- ele chegou da força do chute (nunca 0%, nunca garantida).
	local ratio = math.clamp(physical / dangerRating, 0, 1)
	local chance = Config.GKBOT_CATCH_PHYSICAL_CHANCE_MIN
		+ (Config.GKBOT_CATCH_PHYSICAL_CHANCE_MAX - Config.GKBOT_CATCH_PHYSICAL_CHANCE_MIN) * ratio
	return math.random() < chance
end

-- Escolhe o alvo do lançamento: prioriza um companheiro que pediu passe
-- (tecla T, Attribute WantsPass — ver PassRequestController.lua); sem
-- ninguém pedindo, sorteia entre os companheiros em campo; sem ninguém,
-- lança campo adentro.
-- ⚠️ v16: meio do campo = ponto médio entre os dois gols. Não depende de
-- nenhuma Part de "linha do meio" existir na cena.
local function fieldMidpoint(teamName)
	local own = ownGoalOf(teamName)
	local enemy = enemyGoalOf(teamName)
	if not own or not enemy then return nil end
	return (own.Position + enemy.Position) / 2
end

-- ⚠️ v16 — PEDIDO: "ele não pode passar pro jogador que tá na frente do
-- meio. O jogador tem que estar no meio ou atrás, perto do gol, pra o bot
-- passar." Sem os dois gols na cena devolve true (não trava o passe) —
-- mesma filosofia de fallback do resto do módulo.
local function isInOwnHalf(teamName, position)
	local mid = fieldMidpoint(teamName)
	if not mid then return true end
	return fieldForward(teamName):Dot(position - mid) <= 0
end

local function pickThrowTarget(teamName)
	local requesters = {}
	local everyone = {}

	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == teamName and plr:GetAttribute("Role") ~= "GK" then
			local character = plr.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			-- ⚠️ v16: companheiro que já subiu pro ataque NÃO é alvo de passe
			-- do goleiro. Lançar pra ele é o que virava aquele passe de campo
			-- inteiro que chegava voando e sobrava pro adversário.
			if root and isInOwnHalf(teamName, root.Position) then
				table.insert(everyone, root)
				if plr:GetAttribute("WantsPass") then
					table.insert(requesters, root)
				end
			end
		end
	end

	local pool = #requesters > 0 and requesters or everyone
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

-- Física de projétil de verdade: dado ponto de partida, ponto de chegada
-- e tempo de voo desejado, devolve a velocidade inicial exata (levando a
-- gravidade em conta) pra bola chegar lá nesse tempo — não é uma força
-- fixa "chutada".
-- ⚠️ v110 — PEDIDO: "o GK bot pegou a bola e quando foi arremessar ela sumiu".
-- O log mostrou a bola com posição/velocidade NaN logo depois do arremesso (e o
-- resgate do BallController jogando ela pro centro). Qualquer vetor inválido
-- aqui agora é trocado por um valor seguro, com um aviso dizendo QUAL veio
-- quebrado (pra achar a origem se voltar a acontecer).
local function vetorValido(v)
	return typeof(v) == "Vector3" and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

local function computeThrowVelocity(fromPos, toPos, arcTime)
	local delta = toPos - fromPos
	local flatDelta = Vector3.new(delta.X, 0, delta.Z)
	-- ⚠️ v110: a bola NÃO cai com a gravidade cheia — o BallController tira uma
	-- parte dela (Config.BALL_GRAVITY_MULTIPLIER, 0.68). Com a gravidade cheia
	-- aqui o arremesso saía ~50% forte demais pra cima (medido: 212 studs/s
	-- vertical) e a bola ia muito além do alvo — era o "goleiro joga no campo
	-- adversário". Agora usa a gravidade que a bola sente de verdade.
	local gravity = workspace.Gravity * (Config.BALL_GRAVITY_MULTIPLIER or 1)

	local vFlat = flatDelta / arcTime
	local vy = (delta.Y + 0.5 * gravity * arcTime * arcTime) / arcTime

	return Vector3.new(vFlat.X, vy, vFlat.Z)
end

local function throwBall(teamName, bot)
	local root = bot.Root
	-- ⚠️ v21: destrava a bola antes de lançar (ver beginCatch) — anchorada,
	-- ela ignoraria a velocidade do passe e ficaria parada no ar.
	if _G.ReleaseBallFromQTE then
		_G.ReleaseBallFromQTE()
	end
	-- ⚠️ v110: física da bola volta pro SERVIDOR antes de lançar (senão, recém
	-- desancorada, ela ia pro jogador mais perto e o cliente dele a sobrescrevia)
	if not ball.Anchored then pcall(function() ball:SetNetworkOwner(nil) end) end
	if not vetorValido(ball.Position) then
		ball.Position = root.Position + fieldForward(teamName) * 2 + Vector3.new(0, 1, 0)
	end
	local fromPos = ball.Position
	-- ⚠️ v105: animação de arremesso + sai da pose de segurar
	if bot.Model then bot.Model:SetAttribute("BolaNaMao", nil) end
	if _G.AnimarAcao and bot.Model then _G.AnimarAcao(bot.Model, "Arremesso", 0.6) end

	local targetRoot = pickThrowTarget(teamName)

	-- ⚠️ FIX: PEDIDO — "faça o passe do goleiro pro personagem deslizar
	-- bem menos... a dele desliza bem mais e acaba levando a bola pra
	-- longe do jogador na hora do passe" — arco de voo agora PROPORCIONAL
	-- à distância do passe (perto = arco baixo/suave, longe = sobe até o
	-- teto de sempre), em vez do tempo fixo de 1.1s que fazia até um
	-- passe curtinho subir bem alto e cair com força total em cima do
	-- companheiro (ver Config.GKBOT_THROW_ARC_TIME_MIN/_SPEED_REFERENCE).
	-- ⚠️ v16 — PEDIDO: "senão, o bot vai passar só no meio, no centro, e
	-- foda-se, com força suficiente pra parar no meio". Sem companheiro
	-- válido no próprio campo, o alívio é pro CENTRO do campo (não mais um
	-- "26 studs pra frente" solto) — e como a velocidade de pouso cai com a
	-- distância (ver abaixo), a bola chega lá mansa em vez de sobrar pro
	-- adversário.
	-- v110 — PEDIDO: "sem nenhum player ele joga praticamente no campo adversário —
	-- joga no meio de campo, na metade da distância de hoje"
	local meio = fieldMidpoint(teamName)
	local clearancePos = meio and root.Position:Lerp(meio, 0.5) or (root.Position + fieldForward(teamName) * 26)
	local roughTargetPos = targetRoot and targetRoot.Position or clearancePos
	local flatDistance = (Vector3.new(roughTargetPos.X, 0, roughTargetPos.Z) - Vector3.new(fromPos.X, 0, fromPos.Z)).Magnitude

	-- ⚠️ v16 — PEDIDO: "o passe em curta distância tá ótimo. Em longa
	-- distância, quanto mais longe vai, maior é o deslize dele... quanto mais
	-- longe o bot jogar, menor o deslizamento da bola. Mas com limite, não
	-- pode ser zero."
	--
	-- CAUSA: a conta `flatDistance / SPEED_REFERENCE` já existia pra manter a
	-- velocidade de POUSO constante em 30 studs/s não importa a distância —
	-- o que é exatamente a coisa certa. Só que o clamp batia no teto de 1.1s
	-- a partir de ~33 studs, e daí pra frente a proporção quebrava: um passe
	-- de 80 studs virava 80/1.1 = 72 studs/s de velocidade horizontal na
	-- hora de encostar no chão, mais que o DOBRO do alvo. Por isso passe
	-- curto ficava ótimo e passe longo passava voando pelo companheiro.
	--
	-- Duas correções: (1) o teto de arco subiu, pra a proporção continuar
	-- valendo em passe longo; (2) a velocidade de pouso alvo DIMINUI conforme
	-- a distância cresce (até GKBOT_THROW_LONG_SPEED_MULT do normal, nunca
	-- zero) — quanto mais longe, mais suave a bola chega, que foi o pedido.
	local longFactor = math.clamp(flatDistance / Config.GKBOT_THROW_LONG_REFERENCE_DISTANCE, 0, 1)
	local landingSpeed = Config.GKBOT_THROW_SPEED_REFERENCE
		* (1 - (1 - Config.GKBOT_THROW_LONG_SPEED_MULT) * longFactor)
	local arcTime = math.clamp(flatDistance / landingSpeed, Config.GKBOT_THROW_ARC_TIME_MIN, Config.GKBOT_THROW_ARC_TIME)

	local toPos
	if targetRoot then
		-- pequena "antecipação" pra onde o companheiro tá indo, pra não
		-- lançar sempre exatamente nos pés de quem já saiu do lugar
		local lead = targetRoot.AssemblyLinearVelocity * (arcTime * 0.5)
		toPos = targetRoot.Position + lead
	else
		toPos = clearancePos + Vector3.new(0, 3, 0)
	end

	local velocity = computeThrowVelocity(fromPos, toPos, arcTime)
	if not vetorValido(velocity) then
		warn(string.format("🧤 [GKBot] arremesso com vetor inválido — de=%s para=%s arco=%s alvo=%s. Usando lançamento seguro.",
			tostring(fromPos), tostring(toPos), tostring(arcTime), targetRoot and targetRoot:GetFullName() or "centro"))
		if not vetorValido(ball.Position) then ball.Position = root.Position + fieldForward(teamName) * 2 + Vector3.new(0, 1, 0) end
		velocity = fieldForward(teamName) * 40 + Vector3.new(0, 25, 0)
	end
	ball.AssemblyLinearVelocity = velocity
	if _G.MarkBotBallTouch then _G.MarkBotBallTouch(teamName) end -- ⚠️ v84: ver clearBall
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	-- ⚠️ v23 — PEDIDO: "diminui muito a quicada da bola quando o GK jogar
	-- pra muito longe, só até o próximo domínio". Quanto mais longe o
	-- lançamento, mais alto o arco (ver arcTime acima) e mais a bola pulava
	-- ao cair. O amortecimento escala com a distância e é desfeito por
	-- setOwner assim que alguém dominar (ver _G.RestoreBallBounce).
	if _G.SetBallLowBounce and longFactor > 0 then
		local elasticity = Config.GKBOT_THROW_BOUNCE_NORMAL
			- (Config.GKBOT_THROW_BOUNCE_NORMAL - Config.GKBOT_THROW_BOUNCE_LONG) * longFactor
		_G.SetBallLowBounce(elasticity)
	end

	bot.State = "Idle"
	bot.Humanoid.WalkSpeed = Config.GKBOT_WALK_SPEED
	bot.LastActionAt = tick()
	bot.LastThrowAt = tick() -- ⚠️ v6.4: desliga a hitbox de captura por Config.GKBOT_HITBOX_DISABLE_AFTER_THROW (ver isHitboxDisabled)
end

-- ===== TIRO DE META cobrado pelo próprio GKBOT (⚠️ NOVO) =====
-- Diferente do lançamento normal pós-defesa (throwBall/pickThrowTarget
-- acima, que prioriza um companheiro — igual um goleiro de verdade
-- distribuindo o jogo), o tiro de meta mira num jogador ADVERSÁRIO
-- aleatório, de propósito: sem isso, o time com o GKBOT no gol ganhava uma
-- reposição "perfeita" toda vez (contra-ataque de graça pra sempre, OP
-- demais pra um goleiro que é só um bot). Mirar num adversário aleatório
-- cria uma disputa de bola em vez de posse garantida — e o alcance é
-- sempre travado em METADE do campo, pra bola não sobrar direto lá atrás
-- no campo inimigo.
local function pickRandomEnemyTarget(teamName)
	local enemyTeam = otherTeamName(teamName)
	if not enemyTeam then return nil end

	local pool = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Team and plr.Team.Name == enemyTeam then
			local character = plr.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then table.insert(pool, root) end
		end
	end
	if #pool == 0 then return nil end
	return pool[math.random(1, #pool)]
end

-- Clampa o PONTO DE CHEGADA (não a força) até no máximo metade do campo
-- de distância — se o adversário sorteado estiver mais longe que isso, a
-- bola cai numa disputa no meio do caminho em vez de chegar nele de bandeja.
local function clampToHalfField(fromPos, toPos, teamName)
	local delta = toPos - fromPos
	local flatDelta = Vector3.new(delta.X, 0, delta.Z)
	local maxRange = fieldLength(teamName) / 2

	if flatDelta.Magnitude > maxRange and flatDelta.Magnitude > 0.01 then
		flatDelta = flatDelta.Unit * maxRange
	end

	return fromPos + Vector3.new(flatDelta.X, delta.Y, flatDelta.Z)
end

-- Chamado pelo OutOfBoundsController.lua quando um tiro de meta precisa
-- ser cobrado e o time defensor NÃO tem goleiro humano (só o GKBOT) — o
-- bot não é um Player, então não dá pra teleportar/congelar ele pelo
-- fluxo humano normal de bola parada; em vez disso, ele mesmo repõe a
-- bola na hora.
_G.GKBotTakeGoalKick = function(teamName, worldSpot)
	local bot = bots[teamName]
	if not bot or not bot.Root or not bot.Root.Parent then return false end

	if _G.ReleaseBallOwner then _G.ReleaseBallOwner() end

	-- ⚠️ NOVO (pedido: "faz o goleiro ficar um pouquinho mais na frente"):
	-- reposiciona o BOT também (não só a bola) pro ponto de cobrança —
	-- antes ele ficava parado onde já estava (colado na linha do gol) e só
	-- a bola "aparecia" na cobrança, o que também ajudava o gol contra
	-- acidental (bola teleportando perto/dentro da hitbox). worldSpot já
	-- vem com a margem extra de segurança (Config.GOAL_KICK_SAFE_OFFSET,
	-- ver OutOfBoundsController.lua), então mover o bot pra cá também é
	-- seguro.
	bot.Model:PivotTo(CFrame.lookAt(worldSpot, worldSpot + fieldForward(teamName)))
	stopPursuit(bot) -- cancela qualquer perseguição pendente, não faz sentido durante a cobrança

	ball.CanCollide = true
	ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	ball.Position = worldSpot

	-- ⚠️ v23 — PEDIDO: "no tiro de meta ele joga pro adversário. Retira isso.
	-- Era OP antes porque você podia passar da sua área e fazer um gol; agora
	-- ele está com limite até o meio, então mantém normal."
	--
	-- Mirar num adversário aleatório era uma decisão de BALANCEAMENTO da
	-- época em que o lançamento do goleiro ia longe demais e dava
	-- contra-ataque de graça. Esse motivo morreu na v16, quando o alvo do
	-- passe passou a ser obrigatoriamente alguém do próprio campo de defesa.
	-- Agora o tiro de meta usa o MESMO critério do lançamento normal:
	-- companheiro no próprio campo.
	local targetRoot = pickThrowTarget(teamName)
	local toPos
	if targetRoot then
		toPos = clampToHalfField(worldSpot, targetRoot.Position, teamName)
	else
		-- Sem companheiro válido: bate pro meio do campo, igual o
		-- lançamento normal faz (ver throwBall/clearancePos).
		toPos = (fieldMidpoint(teamName) or (worldSpot + fieldForward(teamName) * (fieldLength(teamName) / 2))) + Vector3.new(0, 3, 0)
	end

	local velocity = computeThrowVelocity(worldSpot, toPos, Config.GKBOT_THROW_ARC_TIME)
	ball.AssemblyLinearVelocity = velocity
	if _G.MarkBotBallTouch then _G.MarkBotBallTouch(teamName) end -- ⚠️ v84: ver clearBall
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	bot.State = "Idle"
	bot.LastActionAt = tick()
	bot.LastThrowAt = tick() -- ⚠️ v5.8: mesma trava de recaptura do throwBall
	return true
end

-- ⚠️ v5.9: PEDIDO — "o goleiro pegou a bola e depois contou gol, quando
-- ele foi se preparar pra chutar, acho que ele está pegando dentro da
-- área e depois contando". +2 studs fixos a partir de root.Position (o
-- de sempre) não bastava quando a captura acontecia bem perto da própria
-- profundidade do gol — a bola SEGURA ficava perto/dentro da hitbox
-- (goalPart.Touched, ver MatchController.lua) durante todo o Hold, e
-- reposicioná-la ali TODO frame ia disparando o toque de novo. Agora
-- garante uma distância MÍNIMA de verdade (GKBOT_HOLD_SAFE_DISTANCE)
-- medida a partir do PRÓPRIO GOL (não só um deslocamento fixo a partir
-- de onde o bot está) — usada tanto na captura (snap imediato, ver
-- beginCatch) quanto durante todo o Hold (ver updateHoldingBall).
local function holdPositionFor(teamName, bot)
	local root = bot.Root
	local forward = fieldForward(teamName)
	-- ⚠️ v105: nas MÃOS, na altura do peito (era 2 à frente e 2 acima)
	local holdPosition = root.Position + forward * 1.45 + Vector3.new(0, 0.35, 0)

	local ownGoal = ownGoalOf(teamName)
	if ownGoal then
		local depthFromGoal = (holdPosition - ownGoal.Position):Dot(forward)
		if depthFromGoal < Config.GKBOT_HOLD_SAFE_DISTANCE then
			holdPosition += forward * (Config.GKBOT_HOLD_SAFE_DISTANCE - depthFromGoal)
		end
	end

	return holdPosition
end

local function beginCatch(teamName, bot)
	-- v110: animação de agarrar (braços na bola e puxa pro peito)
	if _G.AnimarAcao and bot.Model then _G.AnimarAcao(bot.Model, "Agarrar", 0.4) end
	-- ⚠️ v109: pegou no meio do mergulho de corpo — levanta em pé onde está
	local dm = bot.DiveMove
	if dm and bot.Root and bot.Root.Parent then
		bot.DiveMove = nil
		local p = bot.Root.Position
		bot.Root.CFrame = CFrame.new(Vector3.new(p.X, dm.Inicio.Y, p.Z)) * dm.Rot
		bot.Root.AssemblyLinearVelocity = Vector3.zero
		if bot.Humanoid then bot.Humanoid.PlatformStand = false end
	end
	if _G.ReleaseBallOwner then
		_G.ReleaseBallOwner()
	end

	-- ⚠️ v21 FIX — PEDIDO: "o goleiro pega a bola de mim e devolve a bola pra
	-- mim. Ele tem que devolver sempre pro time dele."
	--
	-- CAUSA: pickThrowTarget SEMPRE escolheu companheiro (filtra por
	-- plr.Team.Name == teamName), então o passe nunca foi o problema. O
	-- problema é ANTES dele: _G.ReleaseBallOwner() aqui em cima larga a
	-- posse, e durante todo o GKBOT_HOLD_DURATION a bola fica parada do lado
	-- do goleiro valendo como BOLA SOLTA. O atacante que acabou de chutar
	-- está exatamente ali colado — então o pickup passivo entrega a bola pra
	-- ele antes do goleiro chegar a lançar. Parecia "o goleiro devolveu pro
	-- inimigo"; na verdade o inimigo roubou da mão dele.
	--
	-- Reusa a trava que já existe pro QTE da guarda (ballFrozenForGuardQTE):
	-- os guards de "isso não é bola solta pra ninguém pegar" já estão
	-- espalhados pelos Heartbeats do BallController checando essa flag.
	if _G.FreezeBallForQTE then
		_G.FreezeBallForQTE()
	end

	-- ⚠️ v26: pegou — a Hissatsu que estava vindo acabou. Sem isso, a
	-- próxima bola solta nos segundos seguintes ainda seria tratada como
	-- "chute forte demais" e ele se recusaria a pegar uma bola boba.
	bot.IncomingShotUntil = nil
	bot.IncomingShotForce = nil
	-- ⚠️ v27: defendeu — a guarda cumpriu o papel e some na hora, senão
	-- ficaria um retângulo azul flutuando enquanto ele segura a bola.
	bot.PulseDefenseActiveUntil = nil
	hideBotGuard(bot)

	-- ⚠️ NOVO (pedido: "obriga ele a voltar pra posição original após
	-- pegar a bola"): pegou a bola, acabou a perseguição — computeMoveTarget
	-- volta a mirar a posição normal (lateral, clampada) assim que
	-- updateBotMovement voltar a rodar (depois do Hold, ver throwBall).
	-- ⚠️ v5.7: stopPursuit também limpa PursuingPlayer/ChasingBall (a
	-- perseguição contínua não é só o ChaseTarget mais).
	stopPursuit(bot)

	bot.State = "Holding"
	bot.HoldUntil = tick() + Config.GKBOT_HOLD_DURATION
	if bot.Model then bot.Model:SetAttribute("BolaNaMao", true) end -- ⚠️ v105: pose de segurar (AnimadorProcedural)
	if _G.MarkBotBallTouch then _G.MarkBotBallTouch(teamName) end -- ⚠️ v84: ver clearBall
	bot.Humanoid.WalkSpeed = 0 -- parado enquanto segura a bola

	-- Enquanto Holding, updateBotMovement não roda mais (ver dispatch no
	-- Heartbeat no fim do arquivo) — zera a velocidade horizontal aqui
	-- pra não deixar o bot "deslizando" com o impulso de antes de agarrar.
	if bot.Root then
		local vel = bot.Root.AssemblyLinearVelocity
		bot.Root.AssemblyLinearVelocity = Vector3.new(0, vel.Y, 0)
	end

	ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	-- ⚠️ v5.9: snap IMEDIATO pra posição segura, no exato instante da
	-- captura — antes disso só acontecia no próximo updateHoldingBall (1
	-- frame depois), e se a bola tivesse sido agarrada bem em cima da
	-- linha, esse 1 frame já bastava pra ela continuar sobrepondo a
	-- hitbox do gol.
	if bot.Root then
		ball.Position = holdPositionFor(teamName, bot)
	end
end

local function updateHoldingBall(teamName, bot)
	local root = bot.Root
	if not root or not root.Parent then
		bot.State = "Idle"
		return
	end

	-- mantém a bola "nas mãos" do bot durante a espera — ⚠️ CORRIGIDO: o
	-- BUG DO "GOL FANTASMA" (o goleiro agarra e conta gol sozinho, como
	-- se teleportasse a bola pro próprio gol) vinha inteiro daqui. A
	-- posição usava root.CFrame.LookVector, que é a orientação de QUALQUER
	-- jeito que o Humanoid esteja virado nesse instante — podia apontar
	-- pro PRÓPRIO gol (ex: bot ainda girando de um MoveTo anterior), e aí
	-- a bola ficava presa DENTRO da hitbox do gol (goalPart.Touched, ver
	-- MatchController.lua) o tempo todo do Hold, contando gol contra o
	-- próprio time. fieldForward NUNCA aponta pro próprio gol (é sempre
	-- gol→campo, calculado só pela POSIÇÃO dos 2 gols) — segura a bola
	-- sempre no lado seguro, de frente pro campo.
	ball.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
	ball.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	-- ⚠️ v105: de frente pro campo enquanto segura (a bola fica nas mãos)
	local frente = fieldForward(teamName)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(frente.X, 0, frente.Z))
	local naMao = holdPositionFor(teamName, bot)
	if vetorValido(naMao) then
		ball.Position = naMao
	else
		warn("🧤 [GKBot] posição de segurar inválida (root=" .. tostring(root.Position) .. ") — corpo do bot resetado")
		root.CFrame = CFrame.new((ownGoalOf(teamName) and ownGoalOf(teamName).Position or Vector3.zero) + fieldForward(teamName) * 6)
	end

	if tick() >= bot.HoldUntil then
		throwBall(teamName, bot)
	end
end

-- Decide agarrar ou repelir, olhando a posição ATUAL da bola/bot — chamado
-- direto (sem mergulho) ou depois que um mergulho termina (ver reactToBall).
-- `expectedGeneration` é opcional: quando informado (só pelo caminho do
-- mergulho, que pode resolver com atraso — ver updateActiveDive), essa
-- chamada só age de verdade se _G.GetBallStateGeneration() ainda for igual
-- a esse valor.
local function resolveCatchOrClear(teamName, bot, expectedGeneration)
	if not bot.Root or not bot.Root.Parent then return end
	if bot.State ~= "Idle" then return end -- já virou Holding (ou foi destruído) nesse meio tempo
	stopPursuit(bot) -- a tentativa terminou (pegou ou não) — sem motivo pra continuar perseguindo, volta pra posição normal

	-- ⚠️ v6.2: PEDIDO — "sempre que um gol é contabilizado, o gk para de
	-- pegar a bola". Causa raiz: a guarda de distância "3x GKBOT_CATCH_MAX_
	-- RANGE" (v6.0) era um número CHUTADO — em campos menores, o centro do
	-- campo (pra onde a bola é teleportada no kickoff pós-gol) podia estar a
	-- uma distância MENOR que isso do goleiro, então a guarda não disparava:
	-- a resolução atrasada de um mergulho antigo (rede de segurança de
	-- updateActiveDive, até GKBOT_DIVE_DURATION segundos depois) achava a
	-- bola "perto o suficiente" mesmo já sendo a bola do KICKOFF, chamava
	-- attemptCatch (falha, ângulo/posição não batem de verdade) → clearBall
	-- → _G.ReleaseBallOwner() apagava o dono LEGÍTIMO que o kickoff acabou
	-- de definir, e relançava a bola da posição antiga do bot — corrompendo
	-- a reposição de bola inteira, toda vez que isso acontecia por perto o
	-- bastante. Agora, em vez de uma distância chutada, checa DIRETO se a
	-- bola foi reposicionada (_G.GetBallStateGeneration, incrementado pelo
	-- BallController toda vez que _G.ResetBallState roda — kickoff/gol) —
	-- se mudou desde que o mergulho começou, é 100% certeza de que o jogo já
	-- seguiu adiante, não importa o tamanho do campo.
	if expectedGeneration and _G.GetBallStateGeneration and _G.GetBallStateGeneration() ~= expectedGeneration then
		return
	end

	-- Guarda extra (defesa em profundidade, cobre qualquer outro caso de
	-- estado obviamente ultrapassado): distância absurda em relação ao
	-- alcance de captura normal.
	local distToBall = (ball.Position - bot.Root.Position).Magnitude
	if distToBall > Config.GKBOT_CATCH_MAX_RANGE * 3 then
		return
	end

	if attemptCatch(teamName, bot) then
		beginCatch(teamName, bot)
	elseif bot.GuardContactAt and bot.GuardRolled == nil then
		-- (ver abaixo) ainda drenando: a bola está congelada, não mexe.
		-- ⚠️ v38: a bola está PARADA na guarda enquanto a força drena (ver
		-- attemptCatch). Nesses frames attemptCatch devolve `false` porque
		-- a defesa ainda não resolveu — e cair no clearBall aqui socaria a
		-- bola pra longe no meio do momento, matando exatamente o que o
		-- pedido queria mostrar. Não faz nada: o próximo frame volta aqui
		-- e, quando a janela fechar, attemptCatch devolve o resultado de
		-- verdade.
		return
	elseif bot.GuardResolvedAt and (tick() - bot.GuardResolvedAt) < Config.GKBOT_GUARD_RESOLVE_GRACE then
		-- ⚠️ v39: a guarda ACABOU de resolver e já deu à bola a velocidade
		-- certa — o empurrão pra dentro do gol (passou) ou o knockback do
		-- soco (rebateu). clearBall aqui sobrescreveria as duas coisas,
		-- socando a bola pro campo mesmo quando ela devia estar entrando.
		return
	elseif (_G.PulseEmVooReto and _G.PulseEmVooReto()) or (bot.IncomingShotUntil and tick() < bot.IncomingShotUntil) then
		-- v110 — PEDIDO: "ele errou e ainda assim rebateu a Hissatsu com o soco,
		-- jogou a bola pra cima e ela seguiu com a mesma força pra fora". Hissatsu
		-- que ele não segurou SEGUE o caminho dela — o bot não afasta.
		return
	else
		clearBall(teamName, bot)
	end
end

-- ⚠️ v6.4: PEDIDO — "assim que entrar em contato com a bola, pega". Roda
-- TODO heartbeat (chamada no topo de updateBot, antes de qualquer outro
-- gatilho/mergulho/cooldown) — é a captura de CONTATO pura e simples,
-- independente de trigger, mergulho, ângulo de disparo ou cooldown de
-- ação: só olha "a hitbox está ligada? a bola está dentro do alcance/
-- ângulo? então agarra." Nunca chama clearBall (repelir só acontece depois
-- de um mergulho de verdade que falhou de longe/ângulo — ver
-- resolveCatchOrClear) — se não conseguir capturar este frame (fora do
-- alcance ainda), simplesmente não faz nada e tenta de novo no próximo
-- heartbeat sozinha, sem precisar de nenhum gatilho externo pra "lembrar"
-- de tentar de novo.
local function tryContactCatch(teamName, bot)
	if bot.State ~= "Idle" then return false end
	if not bot.Root or not bot.Root.Parent then return false end
	if isHitboxDisabled(bot) then return false end -- só desligada nos 0.5s pós-arremesso, ver isHitboxDisabled

	-- ⚠️ IMPORTANTE: só vale pra bola SOLTA (sem dono nenhum) — chute,
	-- rebote, cruzamento, passe interceptado, etc. Se alguém (do próprio
	-- time OU adversário) já está com a posse/controle da bola, isso NÃO é
	-- "contato com uma bola solta", é o adversário DRIBLANDO perto do gol —
	-- essa disputa continua sendo o gatilho 1 (pursueOpponent/attemptSteal,
	-- com range/chance próprios), nunca uma captura automática só por
	-- passar perto. Sem essa checagem, o goleiro viraria um "ímã" que rouba
	-- a bola de QUALQUER jogador (até companheiro) que chegasse perto do
	-- gol, o que não é o pedido nem faz sentido.
	local owner = _G.GetBallOwner and _G.GetBallOwner()
	if owner then return false end

	if attemptCatch(teamName, bot) then
		beginCatch(teamName, bot)
		return true
	end
	return false
end

-- ⚠️ CORRIGIDO: antes, attemptCatch/beginCatch rodavam no MESMO frame do
-- impulso do mergulho (maybeJumpForBall) — e beginCatch zera a velocidade
-- horizontal do bot NA HORA (pra ele não "escorregar" segurando a bola).
-- Isso cancelava o impulso do mergulho antes da física aplicar 1 frame
-- sequer dele, então o "pulo" nunca aparecia de verdade — só parecia que
-- a bola "teleportava" pro goleiro. Agora, se um mergulho foi disparado,
-- espera ele terminar (mesma duração do impulso, GKBOT_DIVE_DURATION)
-- antes de decidir agarrar/repelir — nesse momento o bot já se moveu de
-- verdade pra perto da bola.
local function reactToBall(teamName, bot, predictedPoint)
	bot.LastActionAt = tick()
	local dived = maybeJumpForBall(teamName, bot, predictedPoint)
	if dived then
		-- ⚠️ v6.1: PEDIDO — "eu já passei no gk novamente pra testar, ele
		-- ainda não consegue pegar a bola... como se desabilitasse
		-- totalmente ele poder pegar a bola mais de uma vez". Causa raiz da
		-- v6.0: a resolução do mergulho dependia de DOIS mecanismos
		-- separados (um `task.delay` assíncrono como rede de segurança +
		-- `updateActiveDive` checando a cada heartbeat), e o `updateActiveDive`
		-- comparava a distância TOTAL (3D, incluindo a altura) até a bola —
		-- numa bola alta ("passa por cima"), essa distância 3D podia nunca
		-- cair dentro de GKBOT_CATCH_MAX_RANGE enquanto a bola ainda estava
		-- no ar, mesmo já estando bem em cima do bot horizontalmente; o bot
		-- ficava com DiveActive=true, bloqueando QUALQUER outro gatilho (ver
		-- topo de updateBot), até o `task.delay` (assíncrono, guardado por
		-- closure) eventualmente disparar — e se esse timing ficasse
		-- torto (ex: 2 mergulhos muito próximos, ou qualquer erro no meio do
		-- caminho abortando a coroutine do delay), o bot ficava PRESO com
		-- DiveActive=true pra sempre, incapaz de reagir a qualquer bola
		-- seguinte. Agora existe UM SÓ mecanismo, síncrono, guiado só por
		-- `tick()` e checado todo heartbeat em updateActiveDive — sem
		-- task.delay nenhum, sem closure guardando estado antigo, sem
		-- possibilidade de travar pra sempre (o pior caso é sempre resolver
		-- no máximo GKBOT_DIVE_DURATION segundos depois, garantido).
		bot.DiveActive = true
		bot.DiveResolved = false
		bot.DiveStartedAt = tick()
		-- ⚠️ v96: animação do mergulho (AnimadorProcedural). A direção sai de
		-- onde a bola vai passar em relação ao corpo do bot: de lado,
		-- pra cima, ou na diagonal alta.
		if _G.AnimarAcao and bot.Model and bot.Root and typeof(predictedPoint) == "Vector3" then
			local rel = bot.Root.CFrame:PointToObjectSpace(predictedPoint)
			local lado = rel.X
			-- ⚠️ v110: mesma decisão do movimento — mergulho aéreo = animação diagonal
			local alto = (bot.DiveMove and bot.DiveMove.Altura > 0) or rel.Y > 2.5
			local direcao
			if math.abs(lado) < 2.5 then
				-- ⚠️ v105: bola baixa bem na frente = mergulho pra frente
				direcao = rel.Y < 1 and "Forward" or "Up"
			elseif alto then
				direcao = lado > 0 and "UpRight" or "UpLeft"
			else
				direcao = lado > 0 and "Right" or "Left"
			end
			_G.AnimarAcao(bot.Model, direcao == "Forward" and "GKForwardDash" or ("GKDive." .. direcao))
		end
		-- ⚠️ v6.2: "carimbo" de qual reposição de bola está valendo agora
		-- (ver _G.GetBallStateGeneration em BallController.lua) — se um gol
		-- acontecer e a bola for reposicionada ENQUANTO esse mergulho ainda
		-- está resolvendo, updateActiveDive vai comparar contra isso e
		-- descartar a resolução em vez de mexer na bola/posse do kickoff.
		bot.DiveStateGen = _G.GetBallStateGeneration and _G.GetBallStateGeneration() or 0
	else
		resolveCatchOrClear(teamName, bot)
	end
end

-- ⚠️ v6.1: roda TODO heartbeat enquanto bot.DiveActive for true (setado
-- acima por reactToBall quando um mergulho é disparado) — único lugar que
-- decide quando o mergulho termina, sem depender de nenhum task.delay
-- assíncrono (ver comentário em reactToBall pro motivo). Resolve
-- agarrar/repelir assim que o bot estiver perto o bastante da bola (mesma
-- distância HORIZONTAL — flat, ignora diferença de altura — usada em
-- attemptCatch, pra bolas altas "passando por cima" não ficarem presas
-- esperando uma distância 3D que nunca cai dentro do alcance) OU quando a
-- duração máxima do mergulho (GKBOT_DIVE_DURATION) se esgotar, o que
-- acontecer primeiro — garantindo que o mergulho SEMPRE termina em tempo
-- finito, não importa o que aconteça com a bola nesse meio tempo. Devolve
-- true enquanto o mergulho ainda está em andamento — updateBot usa isso pra
-- não deixar nenhum outro gatilho atrapalhar/reiniciar o mergulho no meio
-- do caminho.
local function updateActiveDive(teamName, bot)
	if not bot.DiveActive then return false end

	if not bot.Root or not bot.Root.Parent then
		bot.DiveActive = false
		return false
	end

	if bot.DiveResolved then
		-- não deveria sobrar setado assim (resolver já limpa DiveActive
		-- também), mas por segurança: nunca resolve 2x o mesmo mergulho.
		bot.DiveActive = false
		return false
	end

	local toBall = ball.Position - bot.Root.Position
	local flatDistance = Vector3.new(toBall.X, 0, toBall.Z).Magnitude
	local elapsed = tick() - (bot.DiveStartedAt or tick())

	-- ⚠️ v110: só resolve cedo se a bola estiver ao alcance TAMBÉM na altura (antes
	-- bastava a distância no chão — bola alta "teleportava" pras mãos dele)
	local alturaOk = toBall.Magnitude <= (Config.GKBOT_CORPO_RAIO or 4) + (Config.GKBOT_MAOS_EXTRA or 1.3) -- v110: no corpo
	if not alturaOk and elapsed < Config.GKBOT_DIVE_DURATION then
		return true -- ainda longe e ainda dentro do tempo do mergulho — continua "no ar"
	end

	-- Perto o bastante (resolução normal, cedo) OU o tempo máximo do
	-- mergulho já se esgotou (rede de segurança, sempre garantida) —
	-- resolve uma única vez. Passa o "carimbo" da reposição de bola de
	-- quando o mergulho começou — resolveCatchOrClear descarta sozinho se
	-- a bola já tiver sido reposicionada (gol + kickoff) nesse meio tempo.
	bot.DiveActive = false
	bot.DiveResolved = true
	resolveCatchOrClear(teamName, bot, bot.DiveStateGen)
	return true
end

-- ===== "BOTE" (⚠️ NOVO em v5, ⚠️ REESCRITO v5.7) — versão do GKBOT pro
-- F/AttemptGKForward do goleiro humano (ver GKInput.lua): vai atrás do
-- adversário que entrou na área, tentando roubar a bola dos pés dele.
--
-- ⚠️ v5.7: virou PERSEGUIÇÃO CONTÍNUA — pedido: "não deixe-o voltar, isso
-- deve estar fazendo ele bugar, ele só volta depois de o atacante estar
-- por 1.5 segundos fora da área de identificação". Antes era um dash de
-- duração fixa (GKBOT_BOTE_DASH_DURATION, ~0.35s) que soltava o alvo e
-- voltava pra posição na cara dura, mesmo com o atacante ainda dentro da
-- área — "ele só dá o dash e já volta". Agora o bot persegue o alvo
-- FRAME A FRAME (ChaseTarget recarregado todo heartbeat, ver pursueOpponent
-- abaixo) enquanto ele continuar qualificando, e só desiste (stopPursuit)
-- depois de Config.GKBOT_RETURN_DELAY segundos SEGUIDOS fora da zona (ver
-- updatePursuitGiveUp acima). Tentativas de roubo são throttled por
-- Config.GKBOT_STEAL_ATTEMPT_INTERVAL, não uma resolução única. =====

-- Chance de roubo: mesma curva por distância de sempre (GKBOT_CATCH_
-- CHANCE_AT_ZERO/AT_MAX) + BÔNUS que cresce quanto mais devagar o
-- adversário estiver indo — pedido explícito: "aumenta a chance dele
-- pegar a bola, principalmente parado, se a velocidade é baixa a chance
-- é extremamente alta".
local function attemptSteal(bot, targetPlayer)
	local root = bot.Root
	local targetCharacter = targetPlayer.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return false end

	-- ⚠️ v110 (bateria da noite): o bote do bot ignorava o iframe da Hissatsu —
	-- na preparação do chute (wind-up, ~1.2s) ele saía correndo do gol e
	-- roubava a bola, e o chute "fizzlava". Os desarmes de jogador já
	-- respeitam o iframe (BallController); o bot agora também.
	if _G.HasPulseIframe and _G.HasPulseIframe(targetPlayer) then return false end

	local flat = Vector3.new(targetRoot.Position.X - root.Position.X, 0, targetRoot.Position.Z - root.Position.Z)
	local distance = flat.Magnitude
	if distance > Config.GKBOT_BOTE_STEAL_RANGE then return false end

	local t = math.clamp(distance / Config.GKBOT_BOTE_STEAL_RANGE, 0, 1)
	local chance = Config.GKBOT_CATCH_CHANCE_AT_ZERO
		+ (Config.GKBOT_CATCH_CHANCE_AT_MAX - Config.GKBOT_CATCH_CHANCE_AT_ZERO) * t

	local opponentSpeed = Vector3.new(targetRoot.AssemblyLinearVelocity.X, 0, targetRoot.AssemblyLinearVelocity.Z).Magnitude
	local speedT = 1 - math.clamp(opponentSpeed / Config.GKBOT_BOTE_SPEED_REFERENCE, 0, 1)
	chance += Config.GKBOT_BOTE_STATIONARY_BONUS * speedT

	chance = math.clamp(chance, 0, 1)
	return math.random() <= chance
end

-- ⚠️ v5.7: persegue o ADVERSÁRIO continuamente (ver comentário acima da
-- seção). Chamada TODO heartbeat enquanto ele qualificar — recarrega o
-- ChaseTarget/ChaseUntil a cada frame (não precisa de task.delay nenhum:
-- é a própria updateBot, chamada em loop, que mantém isso vivo). A
-- tentativa de roubo em si é throttled (GKBOT_STEAL_ATTEMPT_INTERVAL) —
-- um bote que falha não mexe em nada (a bola continua legitimamente com
-- o adversário; repelir aqui seria roubar a posse de graça mesmo
-- perdendo a disputa).
local function pursueOpponent(teamName, bot, targetPlayer)
	local root = bot.Root
	local targetCharacter = targetPlayer.Character
	local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return end

	bot.PursuingPlayer = targetPlayer
	bot.ChasingBall = false
	bot.PursuitLostSince = nil
	bot.ChaseTarget = Vector3.new(targetRoot.Position.X, root.Position.Y, targetRoot.Position.Z)
	bot.ChaseUntil = tick() + 0.5 -- só um buffer curto — recarregado todo frame enquanto a perseguição continuar

	if tick() - bot.LastStealAttempt < Config.GKBOT_STEAL_ATTEMPT_INTERVAL then return end
	bot.LastStealAttempt = tick()

	-- O adversário pode ter soltado a bola (passou, foi desarmado por
	-- outro jogador, etc.) entre um frame e outro — só rouba se ainda for dele.
	local currentOwner = _G.GetBallOwner and _G.GetBallOwner()
	if currentOwner ~= targetPlayer then return end

	if attemptSteal(bot, targetPlayer) then
		ball.CanCollide = true
		beginCatch(teamName, bot) -- já chama _G.ReleaseBallOwner() e stopPursuit(bot) sozinho
	end
end

-- ⚠️ v5.7: PEDIDO — "faça o goleiro perseguir a bola, se estiver na mesma
-- área, se a bola estiver próxima desse espaço, ele vai tentar pegar a
-- bola sozinha também". Mesma ideia de pursueOpponent, mas sem nenhum
-- adversário envolvido — bola solta dentro da própria área, perto o
-- bastante do bot (ver Config.GKBOT_LOOSE_BALL_CHASE_RANGE). Reaproveita
-- attemptCatch (mesma curva de chance por distância/ângulo de sempre).
local function pursueLooseBall(teamName, bot)
	local root = bot.Root
	if not root then return end

	bot.PursuingPlayer = nil
	bot.ChasingBall = true
	bot.PursuitLostSince = nil
	bot.ChaseTarget = Vector3.new(ball.Position.X, root.Position.Y, ball.Position.Z)
	bot.ChaseUntil = tick() + 0.5

	if tick() - bot.LastStealAttempt < Config.GKBOT_STEAL_ATTEMPT_INTERVAL then return end
	bot.LastStealAttempt = tick()

	if _G.GetBallOwner and _G.GetBallOwner() then return end -- alguém já pegou a bola nesse meio tempo

	if attemptCatch(teamName, bot) then
		beginCatch(teamName, bot) -- já chama stopPursuit(bot) sozinho
	end
end

-- ===== REAÇÃO (mergulha se precisar, agarra primeiro, repele só se falhar) =====
local function updateBot(teamName, bot)
	local root = bot.Root
	if not root or not root.Parent then
		destroyBot(teamName)
		return
	end

	-- ⚠️ v46: congelado (Fúria Glacial e afins) — não anda, não decide, não
	-- mergulha. Sai antes de TUDO, inclusive do mergulho em andamento: é
	-- esse o sentido de "trava no lugar e o rebote fica livre".
	if bot.FrozenUntil and tick() < bot.FrozenUntil then
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		if bot.Humanoid then bot.Humanoid.WalkSpeed = 0 end
		return
	elseif bot.FrozenUntil then
		bot.FrozenUntil = nil
		if bot.Humanoid then bot.Humanoid.WalkSpeed = Config.GKBOT_WALK_SPEED end
		local gelo = bot.Model and bot.Model:FindFirstChild("GKBotFreezeAura")
		if gelo then gelo.Enabled = false end
	end

	-- ⚠️ v6.0: enquanto um mergulho está resolvendo (ver updateActiveDive),
	-- nenhum outro gatilho deve interferir/reiniciar a decisão no meio do
	-- caminho.
	-- ⚠️ v105: atordoado depois de perder o duelo de Hissatsu — não mergulha,
	-- não afasta a bola e não tenta pegar de novo: a bola passa e entra
	if bot.AtordoadoAte and tick() < bot.AtordoadoAte then
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		if bot.Humanoid then bot.Humanoid.WalkSpeed = 0 end
		return
	elseif bot.AtordoadoAte then
		bot.AtordoadoAte = nil
		if bot.Humanoid then bot.Humanoid.WalkSpeed = Config.GKBOT_WALK_SPEED end
	end

	if updateActiveDive(teamName, bot) then return end

	-- ⚠️ v6.4: PEDIDO — "assim que entrar em contato com a bola, pega".
	-- Captura de CONTATO, sempre em primeiro lugar, independente de
	-- qualquer gatilho/cooldown abaixo — ver tryContactCatch.
	if tryContactCatch(teamName, bot) then return end

	local owner = _G.GetBallOwner and _G.GetBallOwner()

	-- ⚠️ v5.8: PEDIDO — "às vezes quando ele vai pegar a bola, ela buga,
	-- talvez ele esteja pegando de novo depois de chutar de volta pros
	-- jogadores". Era isso: logo após arremessar (throwBall/
	-- GKBotTakeGoalKick), a bola ainda está bem perto dele e sem dono —
	-- o gatilho de "bola solta na área" (1.5, abaixo) recapturava o
	-- próprio arremesso na hora. Só trava os gatilhos de BOLA SOLTA (1.5 e
	-- 2) por essa janela curta; roubar de um adversário de verdade (1)
	-- continua liberado normalmente. ⚠️ v6.4: reaproveita isHitboxDisabled
	-- (mesma janela, agora com nome/config únicos — ver Config.GKBOT_
	-- HITBOX_DISABLE_AFTER_THROW).
	local justThrew = isHitboxDisabled(bot)

	-- 1) Adversário com a bola chegou perto demais / entrou na área
	--    (⚠️ "bote", ver pursueOpponent acima) — sem a Part GKArea_<Time>
	--    na cena, cai pro comportamento antigo (só reage por raio, igual
	--    sempre foi). Com ela, reage a QUALQUER adversário com a bola que
	--    ENTRAR na área de verdade, mas só persegue se estiver perto o
	--    bastante dele OU a bola já estiver perto o bastante do bot —
	--    pedido explícito: "só se ele tiver bem perto, ou a bola tiver
	--    perto". ⚠️ v5.7: SEM o ACTION_COOLDOWN aqui — a perseguição em si
	--    é contínua (não uma ação pontual); só a tentativa de roubo lá
	--    dentro é limitada por GKBOT_STEAL_ATTEMPT_INTERVAL.
	if owner and owner.Team and owner.Team.Name ~= teamName then
		local ownerCharacter = owner.Character
		local ownerRoot = ownerCharacter and ownerCharacter:FindFirstChild("HumanoidRootPart")
		if ownerRoot then
			local area = findAreaPart(teamName)
			local distToOwner = (ownerRoot.Position - root.Position).Magnitude
			local distBallToBot = (ball.Position - root.Position).Magnitude

			local triggered
			if area then
				-- ⚠️ v3.3: alcance dinâmico — o MAIOR entre o piso da Config e
				-- METADE da profundidade real da área (ver areaDepth acima) —
				-- "se a pessoa andar metade da área de distância ele já começa
				-- ir pra cima".
				local depth = areaDepth(teamName)
				local boteRange = Config.GKBOT_BOTE_RANGE
				if depth then
					boteRange = math.max(boteRange, depth * Config.GKBOT_BOTE_RANGE_AREA_FRACTION)
				end
				triggered = isInsideOwnArea(teamName, ownerRoot.Position)
					and (distToOwner <= boteRange or distBallToBot <= Config.GKBOT_CATCH_APPROACH_RADIUS)
			else
				triggered = distToOwner <= Config.GKBOT_CATCH_APPROACH_RADIUS
			end

			if triggered then
				if area then
					pursueOpponent(teamName, bot, owner)
				else
					if tick() - bot.LastActionAt < Config.GKBOT_ACTION_COOLDOWN then return end
					reactToBall(teamName, bot)
				end
				return
			end
		end
	end

	-- 1.5) Bola SOLTA (sem dono) dentro da própria área, perto o bastante
	--      do bot — vai buscar sozinho, mesmo parada/lenta (cobre o caso
	--      que o gatilho 2 abaixo não pega, porque exige velocidade
	--      mínima — ver pursueLooseBall acima).
	if not owner and not justThrew then
		local area = findAreaPart(teamName)
		local ballInsideOwnArea = area ~= nil and isInsideOwnArea(teamName, ball.Position)
		local distBallToBot = (ball.Position - root.Position).Magnitude

		-- ⚠️ v6.5: PEDIDO — "o GKBOT precisa seguir a bola, se ela entrar na
		-- area pequena (45 studs) ele começa a ir em direção a bola
		-- individual para pega-la também". Segunda condição, em OR com a de
		-- cima: distância da bola até o PRÓPRIO GOL (Config.
		-- GKBOT_SMALL_AREA_RADIUS) — independente da Part GKArea_<Time> (que
		-- pode não existir na cena) e independente de onde o bot está agora
		-- (a de cima limita é a distância bot→bola).
		local ownGoal = ownGoalOf(teamName)
		local ballNearGoal = ownGoal ~= nil
			and (ball.Position - ownGoal.Position).Magnitude <= Config.GKBOT_SMALL_AREA_RADIUS

		if (ballInsideOwnArea and distBallToBot <= Config.GKBOT_LOOSE_BALL_CHASE_RANGE) or ballNearGoal then
			pursueLooseBall(teamName, bot)
			return
		end
	end

	-- Nem adversário nem bola solta perto o bastante ESTE frame — se
	-- estava perseguindo algo, começa/continua a janela de tolerância
	-- (GKBOT_RETURN_DELAY) antes de desistir de vez.
	updatePursuitGiveUp(bot)
	if bot.PursuingPlayer or bot.ChasingBall then return end -- ainda dentro da janela, não cai pro resto

	if tick() - bot.LastActionAt < Config.GKBOT_ACTION_COOLDOWN then return end

	-- 2) Bola solta (sem dono) cuja trajetória prevista (chute/cruzamento
	--    vindo rápido) passa perto do bot — comportamento antigo, intacto
	--    (mergulho reativo, não uma perseguição a pé).
	if not owner and not justThrew then
		local velocity = ball.AssemblyLinearVelocity
		local flatVel = Vector3.new(velocity.X, 0, velocity.Z)
		if flatVel.Magnitude > 5 then
			local toBall = ball.Position - root.Position
			local planarDistance = Vector3.new(toBall.X, 0, toBall.Z).Magnitude

			if planarDistance <= Config.GKBOT_SHOT_REACT_MAX_RANGE then
				-- ⚠️ v3.3: previsão de verdade (com gravidade), igual o
				-- InstinctTrajectorySight — "você já começa a calcular antes,
				-- igual o sistema de trajetória, ele conseguirá ver a
				-- trajetória e ver o melhor caminho". Varre vários pontos no
				-- futuro (findClosestPredictedPoint) em vez de só 1 ponto
				-- linear sem gravidade — pega chutes com arco de verdade, não
				-- só rasteiros.
				local closestPoint, closestDistance, closestT = findClosestPredictedPoint(root)
				-- ⚠️ v109: chute INDO PRO GOL dele = reage de bem mais longe (o
				-- mergulho alcança GKBOT_DIVE_REACH); bola que não vai no gol
				-- continua com o raio pequeno de sempre (não mergulha à toa)
				local golProprio = ownGoalOf(teamName)
				local rumoAoGol = golProprio ~= nil and (golProprio.Position - ball.Position):Dot(flatVel) > 0
				local raioReacao = rumoAoGol and (Config.GKBOT_SHOT_REACT_RADIUS_NO_GOL or 28) or Config.GKBOT_SHOT_REACT_RADIUS
				bot.TempoAteBola = closestT

				if closestPoint and closestDistance <= raioReacao then
					-- ⚠️ v110 — PEDIDO: "o GK ainda está muito difícil, vai muito
					-- rápido na bola; chuto no canto e é muito difícil fazer gol".
					-- Ele reagia NO MESMO QUADRO em que a bola virava ameaça. Agora
					-- tem TEMPO DE REAÇÃO (GKBOT_TEMPO_REACAO) contado desde que o
					-- chute virou ameaça — chute forte e colocado chega antes dele.
					bot.AmeacaDesde = bot.AmeacaDesde or tick()
					if tick() - bot.AmeacaDesde < (Config.GKBOT_TEMPO_REACAO or 0) then
						return
					end
					bot.AmeacaDesde = nil
					-- Passa o PONTO PREVISTO adiante (não a posição atual da
					-- bola) — é isso que deixa o mergulho sair na diagonal
					-- certa pra interceptar onde ela VAI chegar, ver
					-- maybeJumpForBall.
					reactToBall(teamName, bot, closestPoint)
					return
				end
			end
		end
	end
	bot.AmeacaDesde = nil -- (sem ameaça neste quadro: a próxima conta do zero)
end

-- ===== LOOPS =====
Players.PlayerAdded:Connect(function(player)
	player:GetAttributeChangedSignal("Role"):Connect(reconcile)
	player:GetPropertyChangedSignal("Team"):Connect(reconcile)
	reconcile()
end)
Players.PlayerRemoving:Connect(function()
	task.defer(reconcile) -- espera o jogador sair de Players:GetPlayers() antes de recontar
end)

-- Recheca periodicamente também (cobre troca de time, reset de slot,
-- etc. sem precisar caçar todo Attribute/Signal um por um).
task.spawn(function()
	while true do
		task.wait(1)
		reconcile()
	end
end)

RunService.Heartbeat:Connect(function()
	for teamName, bot in pairs(bots) do
		if bot.State == "Holding" then
			updateHoldingBall(teamName, bot)
		else
			updateBotMovement(teamName, bot)
			updateBot(teamName, bot)
		end
	end
end)

print("✅ GKBotController carregado (bot se move, agarra ou repele conforme a chance, e lança pra quem pediu passe).")
