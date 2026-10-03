--[[
	InstinctTrajectorySight (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Desenha os efeitos PASSIVOS VISUAIS de Instinto. Não muda NENHUM
	número de gameplay — é só desenho na tela de quem tem o Instinto.

	Dois passivos hoje (campo Passive em PulseInstinctData.luau):

	  "TrajectorySight" — trilha curta prevendo por onde a bola vai passar.

	  "Metavision" — ⚠️ v5.2, o Instinto "Metavisão".
	     TRAJETÓRIA COMPLETA: enquanto a bola estiver em movimento, desenha
	     o caminho dela até o PONTO ONDE ELA VAI PARAR (não uma trilha curta
	     de alguns pontos: simula até bater no chão e marca o ponto final
	     com um anel).

	     ⚠️ v5.7: o efeito de "MAIOR ESPAÇO ABERTO" (triangulação ligando os
	     jogadores em campo) foi REMOVIDO — atrapalhava a visão. A Metavisão
	     mantém a trajetória completa e a habilidade extra do Instinct Mode
	     (ver seção 2 abaixo).

	Por que a v5.1 parecia "ligada 100% do tempo": a Metavisão era só um
	bônus de mira em passe com Condition vazia (valia sempre) e um Passive
	"PassLaneSight" que NENHUM cliente desenhava. Ou seja: o efeito era
	permanente e invisível ao mesmo tempo. Agora ela não tem efeito
	numérico nenhum — é informação, e informação que aparece.

	Não precisa de Remote novo: Remotes.GetMyAbilities já diz o Instinto
	equipado; toda a matemática é feita no cliente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
local Remotes = Config.Remotes

local LocalPlayer = Players.LocalPlayer
local ball = workspace:WaitForChild(Config.BALL_NAME)

-- ⚠️ v5.6 — INSTINCT MODE, HABILIDADE EXCLUSIVA DA METAVISÃO. Pedido: "os
-- instintos que não têm buff (que são poucos) ganham uma habilidade
-- durante o Instinct Mode; ex: metavisão agora dá pra ver a trajetória de
-- TODOS os jogadores". Metavisão nunca teve nenhum número em Effect (é
-- puramente visual), então o Instinct Mode dela não amplifica nada — em
-- vez disso, liga esse modo extra de desenho enquanto durar.
-- _G.IsInInstinctMode é SERVIDOR-side (InstinctController.legacy.luau); o
-- cliente não tinha nenhuma forma de saber o próprio estado — reaproveita
-- o Remotes.InstinctModeFeedback que já existe (ModeActivated/ModeEnded),
-- hoje só consumido por AbilityHUD.local.luau pro medidor/banner.
local instinctModeActive = false
Remotes.InstinctModeFeedback.OnClientEvent:Connect(function(kind)
	if kind == "ModeActivated" then
		instinctModeActive = true
	elseif kind == "ModeEnded" then
		instinctModeActive = false
	end
end)

-- ⚠️ v23: a Zona de Ouro só desenha a marca quando a bola está COM VOCÊ
-- (ver desenharZonaDeOuro). Remotes.PossessionChanged já avisa todo mundo
-- quem ganhou/perdeu a posse — mesmo listener que AbilityHUD e
-- FootballClient usam; não precisa de remote novo.
local localHasPossession = false
Remotes.PossessionChanged.OnClientEvent:Connect(function(playerWithBall, gained)
	if playerWithBall == LocalPlayer then
		localHasPossession = gained and true or false
	elseif gained then
		-- outra pessoa dominou: a bola deixou de ser sua
		localHasPossession = false
	end
end)

-- ===== QUAL PASSIVO ESTÁ EQUIPADO (consulta o servidor) =====
local passivoAtual = nil -- nil | "TrajectorySight" | "Metavision"
-- ⚠️ v106 — "a Metavisão não está funcionando". Isto lia result.Instinct, que
-- deixou de existir quando a Arma virou 2 slots (o servidor manda Instinct1 e
-- Instinct2) — o passivo vinha SEMPRE nil: Metavisão e a marca da Zona de Ouro
-- nunca ligavam. Agora é o CONJUNTO dos passivos das Armas equipadas.
local passivos = {} -- [nomeDoPassivo] = true

local function passiveOf(name)
	if not name then return nil end
	if PulseData.ResolveName then name = PulseData.ResolveName(name) end
	for _, def in ipairs(PulseData.Instincts) do
		if def.Name == name then return def.Passive end
	end
	return nil
end

local function refreshEquipped()
	local ok, result = pcall(function()
		return Remotes.GetMyAbilities:InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		local novos = {}
		for _, campo in ipairs({ "Instinct1", "Instinct2", "Instinct" }) do
			local pas = passiveOf(result[campo])
			if pas then novos[pas] = true end
		end
		passivos = novos
		passivoAtual = (novos.Metavision and "Metavision") or (novos.TrajectorySight and "TrajectorySight") or nil
	end
end

LocalPlayer.CharacterAdded:Connect(function()
	task.wait(0.5) -- dá tempo do servidor setar o Instinto no spawn
	refreshEquipped()
end)

task.spawn(function()
	refreshEquipped()
	while true do
		task.wait(4) -- recheca (troca de Instinto no debugger em pleno jogo)
		refreshEquipped()
	end
end)

-- ============================================================
-- PASTA DE DESENHO
-- ============================================================
local pasta = Instance.new("Folder")
pasta.Name = "InstinctVisionDrawing"
pasta.Parent = workspace

local function novaParte(nome, cor, tamanho)
	local p = Instance.new("Part")
	p.Name = nome
	p.Size = tamanho
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = cor
	p.Parent = nil
	return p
end

-- ===== 1) TRAJETÓRIA =====
local COR_TRAJETORIA = Color3.fromRGB(127, 212, 255)
local PONTOS_MAX = 60          -- teto de passos da simulação
local PASSO = 0.06             -- segundos por passo

-- ⚠️ v108 — PEDIDO: "aumenta a Metavisão, mal dá pra ver onde a bola vai cair".
-- Pontos 0.3 -> 0.55; marca do ponto de queda 4 -> 10 studs, mais opaca, com um
-- anel externo pulsando e uma coluna de luz fina (dá pra ver de longe).
local pontos = {}
for i = 1, PONTOS_MAX do
	pontos[i] = novaParte("Ponto" .. i, COR_TRAJETORIA, Vector3.new(0.55, 0.55, 0.55))
	pontos[i].Shape = Enum.PartType.Ball
end

local marcadorFinal = novaParte("PontoFinal", COR_TRAJETORIA, Vector3.new(0.2, 10, 10))
marcadorFinal.Shape = Enum.PartType.Cylinder
marcadorFinal.Transparency = 0.25
local anelFinal = novaParte("AnelFinal", Color3.fromRGB(230, 248, 255), Vector3.new(0.12, 12, 12))
anelFinal.Shape = Enum.PartType.Cylinder
anelFinal.Material = Enum.Material.ForceField
local colunaFinal = novaParte("ColunaFinal", COR_TRAJETORIA, Vector3.new(0.35, 18, 0.35))
colunaFinal.Transparency = 0.45

local function esconderTrajetoria()
	for _, p in ipairs(pontos) do
		if p.Parent then p.Parent = nil end
	end
	for _, p in ipairs({ marcadorFinal, anelFinal, colunaFinal }) do
		if p.Parent then p.Parent = nil end
	end
end

-- Simula um projétil a partir de UMA posição/velocidade inicial dadas até
-- ele chegar na altura do chão, e devolve os pontos do caminho. Gravidade
-- igual à do BallController (que usa BALL_GRAVITY_MULTIPLIER), pra
-- previsão bater com o que acontece de verdade. Genérica de propósito:
-- serve tanto pra bola já em movimento (desenharTrajetoria) quanto pra
-- ⚠️ v5.4: prever pra onde a bola iria SE você chutasse agora, a partir
-- da sua mira (desenharPreviaDeMira) — mesma matemática, origem/força
-- diferentes.
local function simularCaminho(pos, vel)
	local g = workspace.Gravity * (Config.BALL_GRAVITY_MULTIPLIER or 1)
	local chao = pos.Y - (ball.Size.Y / 2)

	-- Onde é o "chão": faz um raycast pra baixo a partir da origem pra
	-- achar o gramado.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ball, pasta, LocalPlayer.Character }
	local hit = workspace:Raycast(pos, Vector3.new(0, -200, 0), params)
	if hit then chao = hit.Position.Y end

	local caminho = {}
	for i = 1, PONTOS_MAX do
		local t = i * PASSO
		local ponto = pos + vel * t - Vector3.new(0, 0.5 * g * t * t, 0)
		caminho[#caminho + 1] = ponto
		if ponto.Y <= chao + 0.3 then break end -- chegou no chão: acabou
	end
	return caminho
end

-- Desenha (ou esconde, se vazio) um caminho já simulado nas Parts
-- compartilhadas — usado tanto pela trajetória da bola em movimento
-- quanto pela prévia de mira (v5.4): as duas nunca aparecem ao mesmo
-- tempo (bola parada no seu pé enquanto você carrega o chute não conta
-- como "em movimento"), então reaproveitar as mesmas Parts é seguro.
local function desenharCaminho(caminho)
	if not caminho or #caminho == 0 then
		esconderTrajetoria()
		return
	end

	for i, p in ipairs(pontos) do
		local ponto = caminho[i]
		if ponto then
			p.Position = ponto
			-- Some conforme fica mais longe no tempo (mais incerto).
			p.Transparency = 0.1 + (i / #caminho) * 0.5
			if not p.Parent then p.Parent = pasta end
		elseif p.Parent then
			p.Parent = nil
		end
	end

	local final = caminho[#caminho]
	if final then
		local deitado = CFrame.new(final) * CFrame.Angles(0, 0, math.rad(90))
		marcadorFinal.CFrame = deitado
		local pulso = (os.clock() * 1.6) % 1
		anelFinal.Size = Vector3.new(0.12, 10 + 6 * pulso, 10 + 6 * pulso)
		anelFinal.CFrame = deitado
		anelFinal.Transparency = 0.2 + 0.8 * pulso
		colunaFinal.CFrame = CFrame.new(final + Vector3.new(0, 9, 0))
		for _, p in ipairs({ marcadorFinal, anelFinal, colunaFinal }) do
			if not p.Parent then p.Parent = pasta end
		end
	end
end

-- ⚠️ v109 — PEDIDO: "o indicativo de onde a bola vai cair tá aparecendo mesmo
-- conduzindo a bola. Só aparece se a bola estiver off-ball." Quem é o dono
-- agora (qualquer jogador) — com dono, nada de marca.
local donoDaBolaAgora = nil
Remotes.PossessionChanged.OnClientEvent:Connect(function(quem, ganhou)
	if ganhou then
		donoDaBolaAgora = quem
	elseif donoDaBolaAgora == quem then
		donoDaBolaAgora = nil
	end
end)

local function desenharTrajetoria()
	if donoDaBolaAgora ~= nil then
		esconderTrajetoria()
		return
	end
	local velocidade = ball.AssemblyLinearVelocity
	if velocidade.Magnitude < Config.TRAJECTORY_SIGHT_MIN_SPEED then
		esconderTrajetoria()
		return
	end

	desenharCaminho(simularCaminho(ball.Position, velocidade))
end

-- ⚠️ v5.4 — PRÉVIA DE MIRA: enquanto você segura o botão de chute
-- carregando força (ver _G.GetKickChargeInfo em FootballClient.local.
-- luau), mostra pra onde a bola iria SE você chutasse agora, com a mira
-- e a força atuais. Mesma fórmula de velocidade inicial que o servidor
-- usa de verdade em Remotes.KickBall (ver BallController.legacy.luau):
-- direção da bola até o alvo, vezes a força, mais o impulso pra cima de
-- Config.KICK_UPWARD_BOOST — sem desvio de mira (a previsão é do "chute
-- perfeito", igual a trajetória real já assume a bola sem obstáculos).
local function desenharPreviaDeMira(info)
	local origem = ball.Position
	local alvo = info.AimPoint
	if not alvo then
		esconderTrajetoria()
		return
	end

	local direcao = alvo - origem
	if direcao.Magnitude < 0.5 then
		esconderTrajetoria()
		return
	end
	direcao = direcao.Unit

	local forca = info.Force or Config.KICK_MIN_FORCE
	-- ⚠️ v97: mesma conta do servidor agora (parábola que passa pelo ponto
	-- mirado — ver _G.VelocidadeBalistica em BallController). Cópia local
	-- porque _G do servidor não chega aqui.
	local velocidade
	do
		local g = workspace.Gravity * Config.BALL_GRAVITY_MULTIPLIER
		local d = alvo - origem
		local plano = Vector3.new(d.X, 0, d.Z)
		local x = plano.Magnitude
		if x >= 0.5 and g > 0 then
			local v2 = forca * forca
			local disc = v2 * v2 - g * (g * x * x + 2 * d.Y * v2)
			local ang = disc >= 0 and math.atan((v2 - math.sqrt(disc)) / (g * x)) or (math.atan2(d.Y, x) + math.rad(5))
			ang = math.clamp(ang, math.rad(-70), math.rad(70))
			velocidade = plano.Unit * (forca * math.cos(ang)) + Vector3.new(0, forca * math.sin(ang), 0)
		else
			velocidade = direcao * forca + Vector3.new(0, forca * (Config.KICK_UPWARD_BOOST or 0), 0)
		end
	end
	desenharCaminho(simularCaminho(origem, velocidade))
end

-- ===== ⚠️ v108 — LINHA DE MIRA DE QUEM ESTÁ COM A BOLA =====
-- PEDIDO: "coloca pra saber exatamente, a cada tick, aonde o jogador que está
-- com a bola está olhando — uma linha reta, fina, até o final — pra conseguir
-- interceptar. É meta pra goleiro, mas serve pra jogador também." O dono manda a
-- mira (Remotes.MiraDoDono) e o servidor grava em Player:GetAttribute("MiraBola").
-- Aqui: linha fina da bola até o ponto mirado + um alvo pequeno no fim.
local COR_MIRA = Color3.fromRGB(255, 90, 90)
local linhaMira = novaParte("LinhaMira", COR_MIRA, Vector3.new(0.12, 0.12, 1))
linhaMira.Transparency = 0.2
local alvoMira = novaParte("AlvoMira", COR_MIRA, Vector3.new(0.15, 2.4, 2.4))
alvoMira.Shape = Enum.PartType.Cylinder
alvoMira.Transparency = 0.3
local donoDaBola = nil
Remotes.PossessionChanged.OnClientEvent:Connect(function(quem, ganhou)
	if ganhou then
		donoDaBola = quem
	elseif donoDaBola == quem then
		donoDaBola = nil
	end
end)
local miraSuave = nil
local function esconderMira()
	if linhaMira.Parent then linhaMira.Parent = nil end
	if alvoMira.Parent then alvoMira.Parent = nil end
	miraSuave = nil
end
-- ⚠️ v109 — PEDIDO: "no Flow aparece a linha, só que maior — até o final do
-- campo, de um lado ao outro, pra saber exatamente onde o cara tá olhando. E
-- tem que ir exatamente onde ele mira com o mouse, atualizando a cada instante."
-- A mira chega TODO QUADRO por Remotes.MiraDoDonoU (sem suavizar: é a posição
-- exata); a linha sai da bola na direção da mira (no plano do campo) e corre
-- COMPRIMENTO_LINHA studs; o alvo fica no ponto exato mirado.
local COMPRIMENTO_LINHA = 700
local miraPorJogador = {}
Remotes.MiraDoDonoU.OnClientEvent:Connect(function(quem, ponto)
	if typeof(quem) == "Instance" and typeof(ponto) == "Vector3" then
		miraPorJogador[quem] = ponto
	end
end)
Players.PlayerRemoving:Connect(function(p) miraPorJogador[p] = nil end)

local function desenharMiraDoDono()
	local dono = donoDaBola
	if not dono or dono == LocalPlayer or not dono.Parent then return esconderMira() end
	local mira = miraPorJogador[dono]
	if typeof(mira) ~= "Vector3" then return esconderMira() end
	local origem = ball.Position
	local plano = Vector3.new(mira.X - origem.X, 0, mira.Z - origem.Z)
	if plano.Magnitude < 0.5 then return esconderMira() end
	local dir = plano.Unit
	local fim = origem + dir * COMPRIMENTO_LINHA
	linhaMira.Size = Vector3.new(0.14, 0.14, COMPRIMENTO_LINHA)
	linhaMira.CFrame = CFrame.lookAt(origem, fim) * CFrame.new(0, 0, -COMPRIMENTO_LINHA / 2)
	alvoMira.CFrame = CFrame.lookAt(mira, mira + dir) * CFrame.Angles(0, math.rad(90), 0)
	if not linhaMira.Parent then linhaMira.Parent = pasta end
	if not alvoMira.Parent then alvoMira.Parent = pasta end
end
RunService.RenderStepped:Connect(function()
	-- só com Metavisão E no Flow (Instinct Mode)
	-- ⚠️ v111: ou com o Sexto Sentido do goleiro (sempre, sem o Flow)
	local sexto = passivos.SextoSentido and LocalPlayer:GetAttribute("Role") == "GK"
	if not sexto and (passivoAtual ~= "Metavision" or not instinctModeActive) then return esconderMira() end
	local ok = pcall(desenharMiraDoDono)
	if not ok then esconderMira() end
end)

-- ⚠️ v5.7: seção "2) MAIOR ESPAÇO ABERTO (triangulação)" REMOVIDA a pedido
-- — o desenho ligando os jogadores em campo atrapalhava a visão durante a
-- partida. A Metavisão continua com a trajetória completa (seção 1) e a
-- habilidade extra de Instinct Mode (seção 2 abaixo).

-- ===== 2) TRAJETÓRIA DE TODOS OS JOGADORES (só durante Instinct Mode) =====
-- ⚠️ v5.6: extrapola a velocidade HORIZONTAL atual de cada jogador em
-- campo (sem gravidade — é gente correndo no chão, não a bola no ar) por
-- PLAYER_PREDICT_SECONDS à frente, e desenha uma linha fina até lá. Só
-- aparece pra quem tem Metavisão equipada E está em Instinct Mode.
local COR_JOGADOR = Color3.fromRGB(255, 214, 82)
local PLAYER_PREDICT_SECONDS = 1.2
local MIN_PLAYER_SPEED_TO_DRAW = 4 -- parado/andando bem devagar não desenha nada (evita poluir a tela à toa)
local playerTrails = {} -- [player] = Part (linha fina, uma por jogador)

local function getOrCreatePlayerTrail(plr)
	local trail = playerTrails[plr]
	if trail then return trail end
	trail = novaParte("TrajetoriaJogador_" .. plr.Name, COR_JOGADOR, Vector3.new(0.25, 0.25, 1))
	trail.Transparency = 0.3
	playerTrails[plr] = trail
	return trail
end

local function esconderTrajetoriasDeJogadores()
	for _, trail in pairs(playerTrails) do
		if trail.Parent then trail.Parent = nil end
	end
end

local function desenharTrajetoriasDeJogadores()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local trail = playerTrails[plr]

		if not root then
			if trail and trail.Parent then trail.Parent = nil end
			continue
		end

		local velocidade = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		if velocidade.Magnitude < MIN_PLAYER_SPEED_TO_DRAW then
			if trail and trail.Parent then trail.Parent = nil end
			continue
		end

		local origem = root.Position
		local destino = origem + velocidade * PLAYER_PREDICT_SECONDS
		local comprimento = (destino - origem).Magnitude
		if comprimento < 0.05 then continue end

		trail = getOrCreatePlayerTrail(plr)
		trail.Size = Vector3.new(0.25, 0.25, comprimento)
		trail.CFrame = CFrame.lookAt(origem, destino) * CFrame.new(0, 0, -comprimento / 2)
		if not trail.Parent then trail.Parent = pasta end
	end

	-- limpa a linha de quem já saiu da partida.
	for plr, trail in pairs(playerTrails) do
		if not plr.Parent then
			trail:Destroy()
			playerTrails[plr] = nil
		end
	end
end

-- ============================================================
-- LOOPS
-- A trajetória acompanha o frame (a bola se move rápido).
-- ============================================================
RunService.RenderStepped:Connect(function()
	if passivoAtual ~= "TrajectorySight" and passivoAtual ~= "Metavision" then
		esconderTrajetoria()
		return
	end

	-- ⚠️ v109: a prévia de mira ao carregar o chute SAIU — carregar é estar com
	-- a bola, e o pedido é "só aparece com a bola off-ball".

	desenharTrajetoria()
end)

task.spawn(function()
	while true do
		task.wait(0.25)

		-- ⚠️ v5.6: habilidade exclusiva do Instinct Mode da Metavisão.
		if passivoAtual == "Metavision" and instinctModeActive then
			local ok2, err2 = pcall(desenharTrajetoriasDeJogadores)
			if not ok2 then warn("Metavisão (trajetórias de jogadores):", err2) end
		else
			esconderTrajetoriasDeJogadores()
		end
	end
end)

-- ============================================================
-- ⚠️ v17 — ZONA DE OURO (Passive = "GoldenZoneSight")
-- PEDIDO: "coloca a área da Zona de Ouro aparecendo quando você estiver
-- perto dela — tipo a 20 studs, a área aparece no chão, que nem o efeito
-- da teia, só que dourada e brilhante, e só pra você."
--
-- A Arma "Zona de Ouro" premia chutar de uma DISTÂNCIA e um ÂNGULO
-- específicos do gol (ver Condition em PulseInstinctData.luau). Isso é
-- invisível pro jogador — ele não tem como adivinhar onde fica o ponto.
-- Aqui a gente desenha os dois pontos (um de cada lado do gol, porque o
-- ângulo vale pros dois lados) no chão, só no cliente de quem tem a Arma
-- equipada: nada disso existe pros outros jogadores.
--
-- Tudo é calculado aqui mesmo a partir das Parts dos gols (que têm o
-- atributo "ScoringTeam", mesma leitura que o servidor usa) — nenhum
-- remote novo.
-- ============================================================
local GOLDEN_SHOW_DISTANCE = 50 -- ⚠️ v23: era 20; o campo é grande (~500x350), 50 studs é a leitura de "estou chegando na zona"

local goldenParts = {}

local function goldenZoneCondition()
	for _, def in ipairs(PulseData.Instincts) do
		if def.Passive == "GoldenZoneSight" then return def.Condition end
	end
	return nil
end

-- ⚠️ v18: DIAGNÓSTICO. A marca não apareceu no primeiro teste e daqui não
-- dá pra saber em qual das etapas ela parou, então cada motivo de falha
-- imprime UMA vez (não a cada 0.15s) dizendo exatamente o que faltou —
-- mesmo padrão dos prints do CrowdClient, que foi o que resolveu o
-- problema da torcida.
local goldenWarned = {}
local function goldenWarnOnce(key, message)
	if goldenWarned[key] then return end
	goldenWarned[key] = true
	warn("🟡 [Zona de Ouro] " .. message)
end

local function myGoals()
	local teamName = LocalPlayer.Team and LocalPlayer.Team.Name
	if not teamName then
		goldenWarnOnce("team", "LocalPlayer.Team está vazio no cliente — sem saber o seu time, não dá pra saber qual gol é o adversário.")
		return nil, nil
	end

	local blue = workspace:FindFirstChild(Config.BLUE_GOAL_NAME, true)
	local yellow = workspace:FindFirstChild(Config.YELLOW_GOAL_NAME, true)
	if not blue or not yellow then
		goldenWarnOnce("parts", ("não achei as Parts dos gols no workspace (%s=%s, %s=%s)."):format(
			Config.BLUE_GOAL_NAME, tostring(blue), Config.YELLOW_GOAL_NAME, tostring(yellow)))
		return nil, nil
	end

	-- "ScoringTeam" = o time que MARCA naquele gol, ou seja, o gol
	-- adversário de quem está nesse time.
	local blueScoring = blue:GetAttribute("ScoringTeam")
	local yellowScoring = yellow:GetAttribute("ScoringTeam")
	if blueScoring == teamName then return blue, yellow end
	if yellowScoring == teamName then return yellow, blue end

	goldenWarnOnce("attr", ("nenhum gol tem ScoringTeam igual ao seu time. Seu time = '%s'; %s.ScoringTeam = '%s'; %s.ScoringTeam = '%s'. (Se os dois vierem nil, o atributo não está setado nas Parts no Studio.)"):format(
		teamName, Config.BLUE_GOAL_NAME, tostring(blueScoring), Config.YELLOW_GOAL_NAME, tostring(yellowScoring)))
	return nil, nil
end

-- Os dois "pontos doces": na distância pedida, abertos pro ângulo pedido
-- pra cada lado do eixo que liga os dois gols.
local function goldenSpots()
	local cond = goldenZoneCondition()
	local enemyGoal, ownGoal = myGoals()
	if not cond or not enemyGoal or not ownGoal then return nil end

	local axis = enemyGoal.Position - ownGoal.Position
	axis = Vector3.new(axis.X, 0, axis.Z)
	if axis.Magnitude < 0.1 then return nil end
	axis = axis.Unit
	local side = Vector3.new(-axis.Z, 0, axis.X) -- perpendicular horizontal

	local distance = cond.GoldenZoneDistance or 34
	local angle = math.rad(cond.GoldenZoneAngle or 40)
	local back = axis * (math.cos(angle) * distance)
	local across = side * (math.sin(angle) * distance)

	local base = Vector3.new(enemyGoal.Position.X, 0, enemyGoal.Position.Z)
	return {
		base - back + across,
		base - back - across,
	}, cond.GoldenZoneDistanceTolerance or 10
end

local function ensureGoldenPart(index, radius)
	local part = goldenParts[index]
	if part and part.Parent then return part end
	part = Instance.new("Part")
	part.Name = "GoldenZoneMark"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.4, radius * 2, radius * 2)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 200, 70)
	part.Transparency = 0.6
	part.Parent = pasta
	goldenParts[index] = part
	return part
end

local function esconderZonaDeOuro()
	for _, part in pairs(goldenParts) do
		if part and part.Parent then part.Transparency = 1 end
	end
end

local function desenharZonaDeOuro()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return esconderZonaDeOuro() end

	local spots, radius = goldenSpots()
	if not spots then return esconderZonaDeOuro() end

	-- ⚠️ v19: acha o CHÃO de verdade embaixo do ponto em vez de chutar
	-- "altura do jogador menos 2.6". Se o disco nascer dentro do gramado
	-- (Part grossa), ele fica invisível mesmo existindo e com transparência
	-- certa — que é exatamente o sintoma relatado (nenhum aviso no Output,
	-- o bônus funcionando, e nada aparecendo).
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { pasta, LocalPlayer.Character }

	for index, spot in ipairs(spots) do
		local part = ensureGoldenPart(index, radius)
		local flat = Vector3.new(root.Position.X - spot.X, 0, root.Position.Z - spot.Z)
		local distance = flat.Magnitude

		local groundY = root.Position.Y - 2.6
		local hit = workspace:Raycast(Vector3.new(spot.X, root.Position.Y + 20, spot.Z), Vector3.new(0, -200, 0), rayParams)
		if hit then groundY = hit.Position.Y end

		-- ⚠️ v23 — PEDIDO: "volte a Zona de Ouro pra só aparecer quando você
		-- tiver com a posse da bola e estiver a uns 40-60 studs dela." O
		-- "sempre visível" era só pro teste da v20. Agora precisa das DUAS
		-- coisas: bola no seu pé e você perto do ponto. Sem posse, a marca
		-- some — não faz sentido mirar a zona sem ter o que chutar.
		if localHasPossession and distance <= GOLDEN_SHOW_DISTANCE + radius then
			local closeness = 1 - math.clamp((distance - radius) / GOLDEN_SHOW_DISTANCE, 0, 1)
			part.CFrame = CFrame.new(spot.X, groundY + 0.25, spot.Z) * CFrame.Angles(0, 0, math.rad(90))
			part.Transparency = 0.6 - 0.35 * closeness
		else
			part.Transparency = 1
		end

		-- ⚠️ v19: diagnóstico de UMA vez com os números crus. O aviso antigo
		-- não disparava (ou seja, o desenho está rodando) — então o que falta
		-- saber é ONDE ele está desenhando e a que distância você está.
		goldenWarnOnce("geo" .. index, ("ponto %d em (%.0f, %.0f, %.0f) | você a %.0f studs dele | raio do disco %.0f | acende até %.0f studs | chão achado: %s"):format(
			index, spot.X, groundY, spot.Z, distance, radius, GOLDEN_SHOW_DISTANCE + radius, hit and "sim" or "NÃO (usou altura estimada)"))
	end
end

task.spawn(function()
	-- Espera o refreshEquipped inicial responder antes de julgar qualquer
	-- coisa (ele roda no spawn e a cada 4s).
	task.wait(2)
	while true do
		if passivos.GoldenZoneSight then
			local ok, err = pcall(desenharZonaDeOuro)
			if not ok then goldenWarnOnce("draw", "erro ao desenhar: " .. tostring(err)) end
		else
			esconderZonaDeOuro()
			-- ⚠️ v18: o motivo nº1 de "não apareceu" é simplesmente não estar
			-- com a Arma equipada — o passivo vem do servidor
			-- (Remotes.GetMyAbilities). Avisa uma vez só, dizendo o que ele
			-- achou, pra não confundir com um bug de desenho.
			goldenWarnOnce("passive", ("a Arma equipada não é a Zona de Ouro (passivo atual = '%s'). A marca no chão só existe pra quem está com ela equipada — use o seletor de debug pra equipar 'Zona de Ouro'."):format(tostring(passivoAtual)))
		end
		task.wait(0.15)
	end
end)
