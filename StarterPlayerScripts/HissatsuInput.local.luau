--[[
	HissatsuInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	⚠️ v6 — INPUT DE PULSO, DO ZERO. Antes disso NENHUM script chamava
	Remotes.UsePulse nem escutava Remotes.PulsePrecisionPrompt/PulseQTE-
	Prompt — o sistema de Pulso inteiro (PulseController.legacy.luau,
	PulsePrecisionWindow.luau) existia só do lado do servidor/como módulo
	órfão, e Data.Pulses estava vazia de propósito (v5). Isso aqui é o
	primeiro input de verdade, feito junto com o novo lote de Pulsos
	Hissatsu (ver PulseInstinctData.luau).

	TECLAS: "1" = slot 1 (jogador de linha E goleiro), "2" = slot 2 (só
	jogador de linha — Q/E/Z/X/C/F/R/V/G/T já estão todos ocupados por
	goleiro/instinto/drible/passe/sprint, então 1/2 é o par livre que
	sobrou sem brigar com nada). ⚠️ NOVO: continua 1/2 no esquema novo
	(Q drible, F dash, E/R Armas, T cabeçada, sem sprint).

	QTE: quando o servidor manda Remotes.PulseQTEPrompt (só acontece pros
	Pulsos com campo QTE, ver PulseInstinctData.luau), mostra a janela
	certa via HissatsuQTEWindow.Show — e a resposta do jogador (clique no
	alvo, ESPAÇO na barra, ou tecla A/D alternada) volta pro servidor via
	Remotes.PulseQTEInput. O servidor SEMPRE é quem decide o resultado
	de verdade (ver PulseController.legacy.luau); esta UI é só a
	apresentação.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local HissatsuQTEWindow = require(ReplicatedStorage:WaitForChild("HissatsuQTEWindow"))
local Remotes = Config.Remotes

local LocalPlayer = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse = LocalPlayer:GetMouse()

local SEND_DEBOUNCE = 0.15
local lastSent = 0

-- ⚠️ v7 PEDIDO: "a mira da Hissatsu tem que ser exatamente onde o cara
-- estiver mirando, igual o chute padrão" — MESMO cálculo do chute normal
-- (ver computeAimPoint em FootballClient.local.luau), mandado junto com
-- o UsePulse pro servidor guardar (ver PulseController.legacy.luau ->
-- _G.GetPulseAimPoint) e usar em vez da mira automática de canto.
local AIM_PITCH_STEEP_THRESHOLD = 0.85

-- ⚠️ v36 FIX — "usei uma Hissatsu que nem pula e mesmo assim ela jogou a
-- bola pra cima / pro nada, sendo que eu chutei RETO no gol".
--
-- Este computeAimPoint era uma CÓPIA da versão ANTIGA (pré-v26) do
-- FootballClient, e ficou pra trás quando o chute normal foi consertado
-- lá. O bug é o mesmo que o v26 descreve em detalhe no FootballClient:
-- a fórmula `flatLook * 20 + 300 * lookVector.Y` foi desenhada só pro
-- caso EXTREMO de pitch íngreme (câmera quase reta pra cima/baixo), mas
-- estava sendo usada também quando o raio do mouse não acerta nada
-- (`rayMissedEverything`) — e aí a câmera pode estar numa inclinação
-- totalmente normal. O log confirmou a conta exata: com lookVector.Y
-- ≈ -0.37, 300 × -0.37 = -113 studs, e o alvo saiu 19 studs à frente
-- (flatLook * 20) e 113 studs ABAIXO da bola. Como Hissatsu de chute voa
-- RETO e SEM gravidade, a direção virava Y = -0.99 e a bola atravessava o
-- gramado viajando pra sempre (mais de 1500 studs no log de voo).
--
-- Os dois casos agora ficam separados, igual no chute normal: pitch
-- íngreme de verdade mantém a fórmula de sempre; "mira não acertou nada"
-- ganha o fallback simples que aponta na direção 3D real do cursor, sem
-- multiplicador nenhum inventando altura. Também passa a usar a direção
-- do MOUSE (ScreenPointToRay) em vez do centro da tela, e a ignorar
-- hitbox invisível — as duas outras correções que o chute normal já tinha
-- e esta cópia nunca recebeu.
-- ⚠️ v44 FIX — "eu mirei exatamente no canto superior esquerdo e ela subiu
-- demais a mira."
--
-- CAUSA RAIZ (medida no Studio): a Part do gol (GolAzul / GolAmarelo) é a
-- HITBOX de gol — 18.7 x 21 x 59.7 studs plantada bem na BOCA do gol, e com
-- CanCollide = FALSE. A regra `isProbablyMathOnlyHitbox` descartava QUALQUER
-- parte não-colidível como "o raio não acertou nada", então mirar dentro da
-- boca do gol — exatamente o que se faz pra mirar num canto — caía sempre no
-- fallback, nunca no ponto real.
--
-- E o fallback tinha um viés PRA CIMA embutido: ele devolve
-- `origem + direção * 20` partindo da CINTURA do jogador, mas quem calcula a
-- direção do chute é o servidor, a partir da BOLA, uns 3 studs mais embaixo.
-- A conta fica elevação = tan(θ) + 3/(20·cos θ): uma mira de 5° virava 13°.
-- Daí "subiu demais", e daí também ser pior quanto mais reta a mira.
--
-- DUAS CORREÇÕES:
--   1) O gol é um ALVO DE MIRA VÁLIDO. Acertar a hitbox do gol é o ponto de
--      mira mais preciso que existe — usa o ponto exato, sem fallback.
--   2) Quando o raio realmente não acerta nada, o fallback parte da BOLA, não
--      da cintura. Aí a direção que o servidor calcula é idêntica à do cursor,
--      em qualquer distância, e o viés some.
local ALVOS_DE_MIRA_VALIDOS = {
	[Config.BLUE_GOAL_NAME] = true,
	[Config.YELLOW_GOAL_NAME] = true,
}

local function isProbablyMathOnlyHitbox(part)
	if Config.KICK_TEST_MODE then return false end
	if part and ALVOS_DE_MIRA_VALIDOS[part.Name] then return false end -- o gol É onde se mira
	return part ~= nil and part:IsA("BasePart") and part.CanCollide == false
end

-- ⚠️ v54 — MIRA NO MOBILE.
-- No celular NÃO existe cursor: `mouse.X`/`mouse.Y` ficam parados na
-- posição do ÚLTIMO TOQUE, e `mouse.Target`/`mouse.Hit` apontam pra onde
-- esse toque caiu. Resultado prático: o jogador de celular não tinha como
-- mirar — o chute saía na direção de onde ele tocou pra girar a câmera (ou
-- de onde apertou um botão), não pra onde estava olhando.
--
-- A convenção de mira em terceira pessoa no mobile é o CENTRO DA TELA, que
-- é justamente pra onde a câmera aponta e o que o jogador enxerga. Então no
-- mobile a mira vira: raio pelo centro da tela + raycast de verdade pra
-- achar o ponto no mundo (não dá pra usar mouse.Hit, que segue o toque).
--
-- O caminho de PC fica IDÊNTICO ao que já estava — todo o ajuste fino de
-- mira feito até aqui (v26/v44) continua valendo sem nenhuma mudança.
local function ehMobile()
	-- Mesma detecção que MobileControls.local.luau usa pra decidir se mostra
	-- os botões, pra os dois nunca discordarem sobre o que é um celular.
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Ponto da TELA de onde a mira parte.
local function pontoDeMiraNaTela()
	if ehMobile() then
		local v = camera.ViewportSize
		return v.X / 2, v.Y / 2
	end
	return mouse.X, mouse.Y
end

-- Raycast do mobile: o equivalente ao mouse.Target/mouse.Hit do PC, só que
-- pelo centro da tela. Ignora personagens pra a mira não "grudar" em quem
-- estiver na frente.
local paramsMiraMobile = RaycastParams.new()
paramsMiraMobile.FilterType = Enum.RaycastFilterType.Exclude
paramsMiraMobile.IgnoreWater = true

local function miraMobileNoMundo()
	local x, y = pontoDeMiraNaTela()
	local ray = camera:ScreenPointToRay(x, y)

	local excluir = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(excluir, p.Character) end
	end
	local sombra = workspace:FindFirstChild("SombraDaBola")
	if sombra then table.insert(excluir, sombra) end
	paramsMiraMobile.FilterDescendantsInstances = excluir

	local batida = workspace:Raycast(ray.Origin, ray.Direction * 2000, paramsMiraMobile)
	if batida then
		return batida.Instance, batida.Position
	end
	return nil, nil
end

local function getMouseLookVector()
	local ray = camera:ScreenPointToRay(pontoDeMiraNaTela())
	local dir = ray.Direction
	if dir.Magnitude < 0.001 then return camera.CFrame.LookVector end
	return dir.Unit
end

-- ⚠️ v84 — PEDIDO: "verifique um problema frequente que são as Hissatsus
-- saírem muito pra baixo".
--
-- CAUSA: a Hissatsu voa em LINHA RETA, sem gravidade, da bola até o ponto
-- mirado — então o que importa é a ALTURA desse ponto NA DISTÂNCIA DO GOL. Só
-- que o ponto vinha do `mouse.Hit`, que é onde o raio da câmera BATE em
-- alguma coisa. Mirando no gol, o raio quase sempre passa (a câmera está em
-- cima e atrás do jogador, olhando levemente pra baixo) e só bate no gramado
-- lá atrás do gol — às vezes centenas de studs depois. A reta da bola até
-- esse ponto no chão, na altura da trave, passa rente à grama: a mira
-- estava no meio do gol, a bola saía rasteira.
--
-- AGORA: se você está mirando pro lado do gol adversário, o ponto de mira é
-- onde o raio da sua mira CRUZA O PLANO DO GOL — exatamente o ponto que a
-- mira cobre, na distância em que o gol está. Em cima do gol, sai alta; no
-- canto baixo, sai baixa; no meio, sai no meio. Mira pra outro lugar (um
-- companheiro, o meio-campo) continua usando o ponto de sempre.
local function acharGols()
	local time = LocalPlayer.Team
	if not time then return nil, nil end
	local azul = workspace:FindFirstChild(Config.BLUE_GOAL_NAME)
	local amarelo = workspace:FindFirstChild(Config.YELLOW_GOAL_NAME)
	-- ScoringTeam = time que MARCA naquele gol (mesma regra do enemyGoalOf no
	-- BallController).
	if azul and amarelo then
		if azul:GetAttribute("ScoringTeam") == time.Name then return azul, amarelo end
		if amarelo:GetAttribute("ScoringTeam") == time.Name then return amarelo, azul end
	end
	return nil, nil
end

local function miraNoPlanoDoGol(ray)
	local golAdversario, meuGol = acharGols()
	if not golAdversario then return nil end

	-- eixo do campo, apontando do meu gol pro gol adversário
	local eixo = golAdversario.Position - meuGol.Position
	eixo = Vector3.new(eixo.X, 0, eixo.Z)
	if eixo.Magnitude < 1 then return nil end
	eixo = eixo.Unit

	local direcao = ray.Direction.Unit
	local aproximacao = direcao:Dot(eixo)
	if aproximacao < 0.2 then return nil end -- não está mirando pro lado do gol

	local t = (golAdversario.Position - ray.Origin):Dot(eixo) / aproximacao
	if t <= 0 then return nil end
	local ponto = ray.Origin + direcao * t

	-- Muito pro lado do gol (mirou num companheiro na ponta, por exemplo):
	-- não é chute no gol, deixa o ponto de sempre.
	local relativo = ponto - golAdversario.Position
	local lateral = relativo - eixo * relativo:Dot(eixo)
	local largura = math.max(golAdversario.Size.X, golAdversario.Size.Z)
	if Vector3.new(lateral.X, 0, lateral.Z).Magnitude > largura * 1.5 then return nil end

	return ponto
end

local function parteDePersonagem(instancia)
	local modelo = instancia and instancia:FindFirstAncestorOfClass("Model")
	return modelo ~= nil and modelo:FindFirstChildOfClass("Humanoid") ~= nil and modelo ~= LocalPlayer.Character
end

local function computeAimPoint()
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = root and root.Position or camera.CFrame.Position

	local lookVector = getMouseLookVector()
	local steepPitch = math.abs(lookVector.Y) > AIM_PITCH_STEEP_THRESHOLD

	if steepPitch then
		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
		if flatLook.Magnitude < 0.05 then
			flatLook = root and Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
			if flatLook.Magnitude < 0.05 then flatLook = Vector3.new(0, 0, -1) end
		end
		flatLook = flatLook.Unit
		return origin + flatLook * 20 + Vector3.new(0, 300 * lookVector.Y, 0)
	end

	-- ⚠️ v54: no mobile o alvo vem do raycast pelo centro da tela; no PC,
	-- do mouse, exatamente como sempre foi.
	local alvoInstancia, alvoPonto
	if ehMobile() then
		alvoInstancia, alvoPonto = miraMobileNoMundo()
	else
		alvoInstancia = mouse.Target
		alvoPonto = mouse.Hit and mouse.Hit.Position
	end

	-- ⚠️ v84: mirando num JOGADOR (companheiro pro passe, adversário na
	-- frente), o ponto é ele mesmo. Senão, mirando pro gol, o ponto é onde a
	-- mira cruza o plano do gol (ver miraNoPlanoDoGol).
	if alvoPonto and parteDePersonagem(alvoInstancia) then
		return alvoPonto
	end
	local noGol = miraNoPlanoDoGol(camera:ScreenPointToRay(pontoDeMiraNaTela()))
	if noGol then
		return noGol
	end

	local rayMissedEverything = alvoInstancia == nil or isProbablyMathOnlyHitbox(alvoInstancia)
	if rayMissedEverything then
		-- ⚠️ v44: parte da BOLA, não da cintura — ver o comentário grande
		-- acima. É isso que tira o viés pra cima do chute.
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		local origemDoChute = (bola and bola.Position) or origin
		return origemDoChute + lookVector * 20
	end

	return alvoPonto or (origin + lookVector * 50)
end

-- ⚠️ v67: exposto pro PulseInput usar a MESMA mira nos Instintos de chute
-- (Chute Direto). Antes o Instinto ia sem mira e reaproveitava o ponto
-- sobrado da última Hissatsu — ver o comentário em PulseInput.local.luau.
_G.HissatsuComputeAimPoint = computeAimPoint

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if not LocalPlayer.Character then return end

	local slot
	if input.KeyCode == Enum.KeyCode.One then
		slot = 1
	elseif input.KeyCode == Enum.KeyCode.Two then
		slot = 2
	-- ⚠️ v84: a tecla "3" saiu — só 2 Hissatsus ficam ativas em partida; o
	-- 3º slot comprado com Robux é só reserva no Lobby (PlayerSystems nem
	-- manda ele pra cá).
	else
		return
	end

	local agora = os.clock()
	if agora - lastSent < SEND_DEBOUNCE then return end
	lastSent = agora

	Remotes.UsePulse:FireServer(slot, computeAimPoint())
end)

-- ⚠️ MOBILE: exposto pros botões de Pulso (slot 1/2) de MobileControls.
-- local.luau — mesmo debounce e mesmo cálculo de mira de cima.
_G.MobileUsePulse = function(slot)
	if not LocalPlayer.Character then return end
	if slot ~= 1 and slot ~= 2 then return end

	local agora = os.clock()
	if agora - lastSent < SEND_DEBOUNCE then return end
	lastSent = agora

	Remotes.UsePulse:FireServer(slot, computeAimPoint())
end

-- ===== QTE dos Pulsos com campo QTE (Tap/TimingBar/MashAD, ver v6 no topo) =====
Remotes.PulseQTEPrompt.OnClientEvent:Connect(function(slot, pulseName, params)
	if typeof(params) ~= "table" then return end
	HissatsuQTEWindow.Show(slot, pulseName, params, function(payload)
		Remotes.PulseQTEInput:FireServer(slot, payload)
	end)
end)

-- Qualquer feedback TERMINAL do servidor pro Pulso (disparou, falhou, ou
-- nem chegou a sair do chão) esconde a janela de QTE na hora, em vez de
-- deixar ela pendurada até o timeout local perceber sozinho.
local TERMINAL_KINDS = { Fired = true, Fizzled = true, Whiffed = true }
Remotes.PulseFeedback.OnClientEvent:Connect(function(kind)
	if TERMINAL_KINDS[kind] then
		HissatsuQTEWindow.Hide()
	end
end)

print("✅ HissatsuInput carregado (tecla 1/2 pros slots de Pulso, QTE novo de Tap/TimingBar/MashAD).")
