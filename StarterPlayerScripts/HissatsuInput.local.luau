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

-- ⚠️ v85 — MIRA DA HISSATSU REFEITA DO ZERO.
-- PEDIDO: "remova o assistente de mira da hissatsu, apenas faça a mira
-- funcionar corretamente... se necessário refaça o sistema de mira da
-- hissatsu, é só ir exatamente onde está apontado o mouse."
--
-- A Hissatsu voa em linha RETA da bola até o ponto mirado. Esse ponto agora é
-- literalmente o que está debaixo do cursor: um raio saindo da câmera e
-- passando pelo mouse (no celular, pelo centro da tela), até a primeira coisa
-- VISÍVEL que ele encontrar. Tudo que existia antes pra "corrigir" a mira
-- saiu — fórmula de inclinação íngreme, ponto "20 studs à frente", plano do
-- gol, e no servidor a assistência de altura e as travas de altura:
--   • a hitbox do gol (invisível) CONTA como alvo — é a boca do gol, é ali
--     que se mira;
--   • qualquer outra peça invisível (hitbox do campo, zonas, barreira
--     invisível em volta do campo) é atravessada — ninguém "aponta" pra ela;
--   • o próprio personagem, a bola e a sombra da bola são ignorados;
--   • mirou no céu, sem nada na frente? o ponto fica bem longe, na direção
--     exata do cursor.
local ALCANCE_DA_MIRA = 2000

local ALVOS_DE_MIRA_VALIDOS = {
	[Config.BLUE_GOAL_NAME] = true,
	[Config.YELLOW_GOAL_NAME] = true,
}

local function ehMobile()
	-- Mesma detecção que MobileControls.local.luau usa pra decidir se mostra
	-- os botões, pra os dois nunca discordarem sobre o que é um celular.
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Ponto da TELA de onde a mira parte: o cursor no PC; no celular não existe
-- cursor (mouse.X/Y ficam presos no último toque), então é o centro da tela,
-- pra onde a câmera aponta.
local function pontoDeMiraNaTela()
	if ehMobile() then
		local v = camera.ViewportSize
		return v.X / 2, v.Y / 2
	end
	return mouse.X, mouse.Y
end

local function atravessavel(parte)
	if ALVOS_DE_MIRA_VALIDOS[parte.Name] then return false end
	return parte.Transparency >= 0.95
end

local paramsDaMira = RaycastParams.new()
paramsDaMira.FilterType = Enum.RaycastFilterType.Exclude
paramsDaMira.IgnoreWater = true

-- ⚠️ v97: a mira agora é a MiraPrecisa (mesma do chute normal): cursor
-- sobre o gol = ponto exato da boca do gol, atravessando quem estiver na
-- frente; nunca pra dentro da grama. A versão v85 logo abaixo fica como
-- reserva, caso o módulo não carregue.
local MiraPrecisa = require(ReplicatedStorage:WaitForChild("MiraPrecisa"))

local function computeAimPointV85()
	local ray = camera:ScreenPointToRay(pontoDeMiraNaTela())
	local direcao = ray.Direction.Unit

	local ignorar = {}
	if LocalPlayer.Character then table.insert(ignorar, LocalPlayer.Character) end
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if bola then table.insert(ignorar, bola) end
	local sombra = workspace:FindFirstChild("SombraDaBola")
	if sombra then table.insert(ignorar, sombra) end

	for _ = 1, 16 do
		paramsDaMira.FilterDescendantsInstances = ignorar
		local batida = workspace:Raycast(ray.Origin, direcao * ALCANCE_DA_MIRA, paramsDaMira)
		if not batida then break end
		if not atravessavel(batida.Instance) then
			return batida.Position
		end
		table.insert(ignorar, batida.Instance)
	end
	return ray.Origin + direcao * ALCANCE_DA_MIRA
end

local function computeAimPoint()
	local x, y = pontoDeMiraNaTela()
	-- ⚠️ v122b: alinhamento na boca do gol só pras Hissatsus (o chute normal não usa)
	local ok, ponto = pcall(MiraPrecisa.Calcular, camera, x, y, { AlinharNaBocaDoGol = true })
	if ok and typeof(ponto) == "Vector3" then return ponto end
	return computeAimPointV85()
end

-- ⚠️ v67: exposto pro PulseInput usar a MESMA mira nos Instintos de chute
-- (Chute Direto). Antes o Instinto ia sem mira e reaproveitava o ponto
-- sobrado da última Hissatsu — ver o comentário em PulseInput.local.luau.
_G.HissatsuComputeAimPoint = computeAimPoint

-- ⚠️ v92 — MIRA AO VIVO NO PREPARO (ver Remotes.UpdatePulseAim em
-- PulseController). Depois do aperto, manda o ponto de mira 10x por segundo
-- até a janela do QTE abrir (aí o mouse vai clicar nos alvos, não mirar) ou a
-- Hissatsu terminar. O servidor só aceita durante o preparo de Hissatsu de
-- chute — pras outras ele simplesmente ignora.
local miraAoVivo = 0 -- geração: um aperto novo cancela o anterior
local function iniciarMiraAoVivo()
	miraAoVivo += 1
	local minha = miraAoVivo
	task.spawn(function()
		local inicio = os.clock()
		while miraAoVivo == minha and os.clock() - inicio < 8 do
			task.wait(0.1)
			if miraAoVivo ~= minha then break end
			Remotes.UpdatePulseAim:FireServer(computeAimPoint())
		end
	end)
end
local function pararMiraAoVivo()
	miraAoVivo += 1
end

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
	iniciarMiraAoVivo()
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
	iniciarMiraAoVivo()
end

-- ===== QTE dos Pulsos com campo QTE (Tap/TimingBar/MashAD, ver v6 no topo) =====
Remotes.PulseQTEPrompt.OnClientEvent:Connect(function(slot, pulseName, params)
	if typeof(params) ~= "table" then return end
	pararMiraAoVivo() -- ⚠️ v92: QTE abriu — a mira fica travada onde estava
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
		pararMiraAoVivo()
	end
	-- ⚠️ v92: o Pulso nem saiu (cooldown, sem energia, sem bola...) — nada pra
	-- mirar ao vivo. "Used" é o único aviso de que ele começou de verdade.
	if kind ~= "Used" and not TERMINAL_KINDS[kind] and kind ~= "ComboStep" then
		pararMiraAoVivo()
	end
end)

print("✅ HissatsuInput carregado (tecla 1/2 pros slots de Pulso, QTE novo de Tap/TimingBar/MashAD).")
