--[[
	GKInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Só faz alguma coisa quando o jogador é GK "efetivo" — Role == "GK" E
	DENTRO da própria área (ver GKAreaUtil.lua) — pra todo mundo mais
	(incluindo o goleiro fora da área), esse script fica quieto (Z/X/C
	viram finta normal, ver DribbleInput.local.luau).

	⚠️ NOVO — Pro goleiro, Q + DIREÇÃO (WASD) vira MERGULHO (defesa por
	botão, ver AttemptGKDive/PulseController.GetGKDiveBonus no servidor),
	igual ao drible direcional do jogador de linha. Antes eram Z/X/C/E/Q
	fixas — E/Q conflitavam com o novo esquema (Q = drible, E = Arma 1):
		A + Q        = mergulho esquerda
		D + Q        = mergulho direita
		Q (ou W/S+Q) = mergulho pra cima
		W + D + Q    = mergulho diagonal cima-direita
		W + A + Q    = mergulho diagonal cima-esquerda
	Esquerda/direita são relativas ao CORPO do goleiro (pra onde ele está
	virado), não à câmera — é o lado pro qual ele se joga.
	F = dash pra frente (AttemptGKForward): rouba a bola do pé do
	adversário se estiver muito perto, ou captura se a bola for direto
	nele. (Fora da área, F é o dash/carrinho normal.)
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local AttemptGKDive = Config.Remotes.AttemptGKDive
local AttemptGKForward = Config.Remotes.AttemptGKForward

local player = Players.LocalPlayer

local DIVE_KEY = Enum.KeyCode.Q

-- Traduz o WASD atual (Humanoid.MoveDirection, espaço de mundo) nos mesmos
-- nomes de mergulho que o servidor já conhece (Left/Right/Up/UpLeft/
-- UpRight) — o servidor não mudou nada.
-- ⚠️ v105 — PEDIDO: "tira o Q padrão (pra cima)... se apertar Q normal ou Q
-- indo pra frente, dá o dash pra frente (o F não vai ter mais utilidade). Pra
-- cima não: o jogador vai pular alto quando estiver no gol, até o travessão,
-- e aí pula e dá o dive pro lado." Então, pro goleiro dentro da área:
--   Q + A / Q + D     = mergulho pro lado (no chão OU no ar, depois do pulo)
--   Q sozinho / Q + W = avanço pra frente (era o F)
--   Q + S             = nada
--   Espaço            = pulo alto (Config.GK_PULO_ALTURA)
-- Diagonais e o mergulho pra cima ficaram só pro GK bot.
local SIDE_THRESHOLD = 0.35
local function acaoDoQ()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root) then return "Forward" end
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then return "Forward" end
	local lateral = move:Dot(root.CFrame.RightVector)
	local forward = move:Dot(root.CFrame.LookVector)
	if math.abs(lateral) >= SIDE_THRESHOLD and math.abs(lateral) >= math.abs(forward) * 0.8 then
		return lateral > 0 and "Right" or "Left"
	end
	if forward < -SIDE_THRESHOLD then return nil end -- Q + S: nada
	return "Forward"
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	-- ⚠️ PULSO v3: enquanto um COMBO de Pulso está pendente, Q/E/R são
	-- CONSUMIDAS pelo combo (ver PulseInput.local.luau, que liga/desliga
	-- esse Attribute) — sem isso, um passo do combo viraria um mergulho
	-- sem querer, já que os dois LocalScripts escutam as mesmas teclas.
	if player:GetAttribute("PulseComboActive") then return end

	if input.KeyCode == DIVE_KEY then
		local acao = acaoDoQ()
		if acao == "Forward" then
			AttemptGKForward:FireServer()
		elseif acao then
			AttemptGKDive:FireServer(acao)
		end
	end
end)

-- ===== pulo alto do goleiro na área =====
local puloOriginal = nil -- { UsaPower, Altura, Power } do personagem fora do gol
local dtPulo = 1 / 60
game:GetService("RunService").Heartbeat:Connect(function(dt)
	dtPulo = math.min(dt, 0.1)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local noGol = GKAreaUtil.IsEffectiveGK(player)
	if noGol then
		if not puloOriginal then
			puloOriginal = { UsaPower = humanoid.UseJumpPower, Altura = humanoid.JumpHeight, Power = humanoid.JumpPower }
		end
		humanoid.UseJumpPower = false
		-- ⚠️ v120b — PEDIDO: "pula 20% mais alto e alcança o ápice MAIS RÁPIDO; cai
		-- rápido". Sobe com a velocidade de um pulo mult× mais alto e, no ar, ganha
		-- gravidade extra ((mult−1)·g): o topo fica em GK_PULO_ALTURA, só que
		-- alcançado em 1/√mult do tempo — e a descida também é mais rápida.
		local mult = Config.GK_PULO_GRAVIDADE_MULT or 1
		humanoid.JumpHeight = (Config.GK_PULO_ALTURA or 14) * mult
		local estado = humanoid:GetState()
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and mult > 1 and (estado == Enum.HumanoidStateType.Freefall or estado == Enum.HumanoidStateType.Jumping) then
			root.AssemblyLinearVelocity -= Vector3.new(0, (mult - 1) * workspace.Gravity * dtPulo, 0)
		end
	elseif puloOriginal then
		humanoid.UseJumpPower = puloOriginal.UsaPower
		humanoid.JumpHeight = puloOriginal.Altura
		humanoid.JumpPower = puloOriginal.Power
		puloOriginal = nil
	end
end)
player.CharacterAdded:Connect(function() puloOriginal = nil end)

-- ⚠️ MOBILE: exposto pros botões de mergulho/dash de MobileControls.
-- local.luau chamarem direto — mesma checagem de GK/combo de cima.
local VALID_DIVES = { Left = true, Right = true } -- ⚠️ v105: só pro lado (cima/diagonal = só o bot)
_G.MobileGKDive = function(direction)
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	if player:GetAttribute("PulseComboActive") then return end
	if not VALID_DIVES[direction] then return end
	AttemptGKDive:FireServer(direction)
end

_G.MobileGKForward = function()
	if not GKAreaUtil.IsEffectiveGK(player) then return end
	if player:GetAttribute("PulseComboActive") then return end
	AttemptGKForward:FireServer()
end
