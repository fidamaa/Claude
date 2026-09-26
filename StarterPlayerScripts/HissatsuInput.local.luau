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
	sobrou sem brigar com nada).

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

-- ⚠️ v86 — MIRA REFEITA DO ZERO. PEDIDO: "remova o assistente de mira da
-- hissatsu, apenas faça a mira funcionar corretamente, se necessário refaça o
-- sistema de mira da hissatsu, é só ir exatamente onde está apontado o mouse".
--
-- COMO É AGORA: um raio só, saindo da câmera e passando pelo cursor (no
-- mobile, pelo centro da tela), e o ponto de mira é a PRIMEIRA coisa que esse
-- raio encontra. A Hissatsu voa reta da bola até esse ponto — ou seja, a bola
-- vai exatamente no que estava embaixo do cursor. O servidor não mexe mais
-- nele (a assistência de altura saiu, ver _G.PulseComputeShotTarget no
-- BallController).
--
-- O QUE FOI EMBORA (tudo inventava um ponto que NÃO estava sob o cursor):
--   • a fórmula de "câmera íngreme" (origem + frente*20 + 300*Y);
--   • o fallback de 20 studs à frente da bola na direção da câmera;
--   • o mouse.Hit do PC (acerta o próprio boneco e a bola) e o raycast
--     separado do mobile — os dois usam o mesmo raycast agora.
--
-- O QUE CONTINUA (é mira exata, não assistência):
--   • hitbox invisível de cálculo (CanCollide = false) é atravessada — o
--     jogador não enxerga ela, então não é onde ele está mirando. Os gols são
--     exceção: acertar a hitbox do gol É mirar no gol (ver o v44 abaixo);
--   • mirando PELA BOCA do gol adversário, o ponto é onde o raio atravessa a
--     boca — senão o raio passa pela rede e só bate no gramado lá atrás, e a
--     reta da bola até lá sai rasteira (o bug do v84);
--   • raio que não acerta nada (céu): ponto bem longe na direção do cursor —
--     de longe, "bola até o ponto" e "câmera até o ponto" são a mesma direção.

-- ⚠️ v44 — a Part do gol (GolAzul / GolAmarelo) é a HITBOX de gol, plantada
-- na BOCA do gol e com CanCollide = FALSE. Sem esta exceção ela seria
-- atravessada como qualquer hitbox invisível e mirar num canto do gol nunca
-- acertaria o gol.
local ALVOS_DE_MIRA_VALIDOS = {
	[Config.BLUE_GOAL_NAME] = true,
	[Config.YELLOW_GOAL_NAME] = true,
}

local function isProbablyMathOnlyHitbox(part)
	if Config.KICK_TEST_MODE then return false end
	if part and ALVOS_DE_MIRA_VALIDOS[part.Name] then return false end -- o gol É onde se mira
	return part ~= nil and part:IsA("BasePart") and part.CanCollide == false
end

local MIRA_ALCANCE = 2000 -- até onde o raio de mira procura alguma coisa
local MIRA_CEU = 1000     -- mirou no céu: distância do ponto na direção do cursor
local MIRA_MAX_ATRAVESSADAS = 8 -- hitboxes invisíveis puladas por raio, no máximo

-- ⚠️ v54 — MIRA NO MOBILE. No celular não existe cursor (`mouse.X`/`mouse.Y`
-- ficam parados no último toque), então a mira é o CENTRO DA TELA — pra onde
-- a câmera aponta e o que o jogador enxerga.
local function ehMobile()
	-- Mesma detecção que MobileControls.local.luau usa pra decidir se mostra
	-- os botões, pra os dois nunca discordarem sobre o que é um celular.
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

local function raioDeMira()
	if ehMobile() then
		local v = camera.ViewportSize
		return camera:ViewportPointToRay(v.X / 2, v.Y / 2)
	end
	return camera:ScreenPointToRay(mouse.X, mouse.Y)
end

local paramsMira = RaycastParams.new()
paramsMira.FilterType = Enum.RaycastFilterType.Exclude
paramsMira.IgnoreWater = true

-- Primeira coisa VISÍVEL que o raio encontra. Ignora o próprio boneco, a bola
-- e a sombra dela (estão sempre na frente da câmera e não são alvo). Outros
-- jogadores contam: mirar num companheiro é mirar nele.
local function primeiroPontoNoRaio(ray)
	local excluir = {}
	if LocalPlayer.Character then table.insert(excluir, LocalPlayer.Character) end
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if bola then table.insert(excluir, bola) end
	local sombra = workspace:FindFirstChild("SombraDaBola")
	if sombra then table.insert(excluir, sombra) end

	local direcao = ray.Direction.Unit
	for _ = 1, MIRA_MAX_ATRAVESSADAS do
		paramsMira.FilterDescendantsInstances = excluir
		local batida = workspace:Raycast(ray.Origin, direcao * MIRA_ALCANCE, paramsMira)
		if not batida then return nil, nil end
		if not isProbablyMathOnlyHitbox(batida.Instance) then
			return batida.Position, (batida.Position - ray.Origin).Magnitude
		end
		table.insert(excluir, batida.Instance)
	end
	return nil, nil
end

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

-- Onde o raio atravessa a BOCA do gol adversário (a face da hitbox virada pro
-- campo), se atravessar. Fora da largura/altura do gol devolve nil — aí não é
-- chute pela boca do gol e vale o ponto normal do raio.
local function travessiaDaBocaDoGol(ray)
	local golAdversario, meuGol = acharGols()
	if not golAdversario then return nil, nil end

	-- eixo do campo, apontando do meu gol pro gol adversário
	local eixo = golAdversario.Position - meuGol.Position
	eixo = Vector3.new(eixo.X, 0, eixo.Z)
	if eixo.Magnitude < 1 then return nil, nil end
	eixo = eixo.Unit

	local direcao = ray.Direction.Unit
	local aproximacao = direcao:Dot(eixo)
	if aproximacao <= 0.05 then return nil, nil end -- não está mirando pro lado do gol

	local tamanho = golAdversario.Size
	local profundidade = math.min(tamanho.X, tamanho.Z)
	local largura = math.max(tamanho.X, tamanho.Z)
	local boca = golAdversario.Position - eixo * (profundidade / 2)

	local t = (boca - ray.Origin):Dot(eixo) / aproximacao
	if t <= 0 then return nil, nil end
	local ponto = ray.Origin + direcao * t

	local relativo = ponto - boca
	local lateral = Vector3.new(relativo.X, 0, relativo.Z)
	if lateral.Magnitude > largura / 2 then return nil, nil end
	if math.abs(ponto.Y - golAdversario.Position.Y) > tamanho.Y / 2 then return nil, nil end

	return ponto, t
end

local function computeAimPoint()
	local ray = raioDeMira()
	local ponto, distancia = primeiroPontoNoRaio(ray)

	-- A boca do gol vale se vier ANTES do que o raio acertou (um zagueiro na
	-- frente do gol, por exemplo, continua sendo o alvo se estiver sob o cursor).
	local noGol, distanciaGol = travessiaDaBocaDoGol(ray)
	if noGol and (not distancia or distanciaGol <= distancia) then
		return noGol
	end

	if ponto then
		return ponto
	end
	return ray.Origin + ray.Direction.Unit * MIRA_CEU
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
