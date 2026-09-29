--[[
	DribbleInput (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts

	⚠️ NOVO — DRIBLE DIRECIONAL NO Q. PEDIDO: "Q será o drible direcional. A
	direção do drible deve ser determinada pelo input de movimento no
	momento em que Q for pressionado: W+Q frente, S+Q trás, A+Q esquerda,
	D+Q direita, W+D+Q diagonal frente/direita, W+A+Q diagonal
	frente/esquerda." Antes eram três teclas fixas (Z esquerda / X trás /
	C direita).

	Manda o Humanoid.MoveDirection (vetor do WASD em espaço de mundo, já
	relativo à câmera — o mesmo que o dash/carrinho usa, ver
	currentTackleDirection em FootballClient.local.luau) pro MESMO remote de
	finta de sempre (AttemptDribbleMove). O servidor achata/normaliza a
	direção e escolhe a animação de finta mais próxima (ver
	getDribbleDirectionFromInput em BallController.legacy.luau). Q parado,
	sem WASD, = drible pra frente.

	⚠️ v86: SEM a bola o Q é o carrinho (FootballClient.local.luau); a finta
	pra frente toca a animação de trás ao contrário, e o personagem não fica
	mais travado durante a finta (continua andando, ver ApplyDisplacement).

	NÃO faz nada se o jogador é GK EFETIVO (Role == "GK" E dentro da
	própria área — ver GKAreaUtil.lua) — pra ele, Q + direção vira
	mergulho (ver GKInput.local.luau). Goleiro FORA da área volta a usar
	o Q como drible normal, igual jogador de linha.
]]

local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local AttemptDribbleMove = Config.Remotes.AttemptDribbleMove
local player = Players.LocalPlayer

local DRIBBLE_KEY = Enum.KeyCode.Q

-- Direção atual do WASD (espaço de mundo). Vector3.zero parado — o
-- servidor trata como "pra frente do personagem".
local function currentMoveDirection()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return Vector3.zero end
	return humanoid.MoveDirection
end

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	if input.KeyCode ~= DRIBBLE_KEY then return end
	if GKAreaUtil.IsEffectiveGK(player) then return end -- GK dentro da área: Q vira mergulho, ver GKInput.local.luau
	-- ⚠️ v86: sem a bola o Q é o CARRINHO (FootballClient.local.luau) — aqui
	-- só a finta, que só existe com a bola no pé.
	if _G.FootballHasPossession and not _G.FootballHasPossession() then return end

	AttemptDribbleMove:FireServer(currentMoveDirection())
end)

-- ⚠️ MOBILE: exposto pros botões de drible em MobileControls.local.luau.
-- Com nome (Left/Back/Right) continua a finta fixa de antes; sem nome, usa
-- a direção do joystick, igual ao Q no teclado.
local VALID_MOVES = { Left = true, Back = true, Right = true, Forward = true } -- ⚠️ v86: + Forward
_G.MobileDribble = function(moveName)
	if GKAreaUtil.IsEffectiveGK(player) then return end
	if moveName == nil then
		AttemptDribbleMove:FireServer(currentMoveDirection())
		return
	end
	if not VALID_MOVES[moveName] then return end
	AttemptDribbleMove:FireServer(moveName)
end
