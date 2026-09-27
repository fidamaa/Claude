--[[
	MobileControls (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Suporte mobile SIMPLES: um painel de botões na metade DIREITA da tela
	(a esquerda fica livre pro joystick de movimento que o próprio Roblox
	já desenha sozinho) que chama os MESMOS remotes/funções que o teclado
	já chama — não duplica regra de negócio nenhuma. Cada script de input
	(DribbleInput, GKInput, PassRequestInput, PulseInput, InstinctModeInput,
	HissatsuInput, FootballClient) expõe um `_G.MobileX(...)` que faz
	exatamente a mesma checagem que a tecla física já fazia; ver cada um
	desses arquivos.

	Só é criado em dispositivo touch "de verdade" (celular/tablet — sem
	mouse). PC com tela touch mas com mouse conectado não mostra nada
	disso, continua 100% no teclado/mouse de sempre.

	O chute (segurar e soltar pra carregar/mirar) NÃO tem botão próprio:
	é o próprio toque-e-segure no lado direito da tela, igual ao mouse
	(ver isShootPress em FootballClient.local.luau) — criar um botão fixo
	pra isso quebraria a mira, que segue o dedo/mouse.

	O cluster ◀ ▲ ▶ troca sozinho entre "Finta" (jogador de linha) e
	"Mergulho" (goleiro efetivo) dependendo de GKAreaUtil.IsEffectiveGK —
	igual ao teclado, onde o MESMO Q significa coisas diferentes.
	⚠️ NOVO: no PC a finta/mergulho virou Q + direção do WASD; no celular os
	botões de direção fixa continuam (o servidor aceita os dois jeitos).
	O botão SPRINT saiu (não existe mais sprint).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
-- ⚠️ v67: usado pra saber quem está com a bola (PossessionChanged), que é o
-- que decide se os botões de drible aparecem.
local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ⚠️ Critério padrão pra "é celular/tablet de verdade": tem toque e NÃO
-- tem mouse. Notebook com tela touch continua usando teclado normal.
local function isMobileDevice()
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

if not isMobileDevice() then
	return
end

-- ===== GUI BASE =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MobileControlsGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

local function makeButton(props)
	local button = Instance.new("TextButton")
	button.Name = props.Name or "Button"
	button.Size = props.Size or UDim2.fromOffset(56, 56)
	button.Position = props.Position
	button.AnchorPoint = props.AnchorPoint or Vector2.new(0.5, 0.5)
	button.BackgroundColor3 = props.Color or Color3.fromRGB(25, 25, 30)
	button.BackgroundTransparency = 0.25
	button.Text = props.Text or "?"
	button.Font = Enum.Font.GothamBlack
	button.TextSize = props.TextSize or 16
	button.TextColor3 = Color3.fromRGB(255, 255, 255)
	button.AutoButtonColor = true
	button.Visible = props.Visible ~= false
	button.ZIndex = 5
	button.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = button

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.6
	stroke.Thickness = 1.5
	stroke.Parent = button

	return button
end

-- ===== CHUTE (segurar pra carregar, soltar pra chutar) =====
-- ⚠️ v55 — PEDIDO: "faz o mais limpo que puder."
--
-- Antes, chutar no celular era tocar na metade DIREITA da tela — a mesma
-- metade que o Roblox usa pra girar a câmera. Girar a câmera carregava e
-- soltava um chute junto, e não dava pra olhar em volta sem chutar. Com a
-- mira agora no centro da tela (v54), arrastar pra mirar virou a ação mais
-- comum do jogo, então o conflito só pioraria.
--
-- Com o botão dedicado, a tela inteira volta a ser só câmera/mira e o
-- chute fica num lugar só. É o botão MAIOR e mais destacado da tela, no
-- polegar direito, porque é a ação principal do jogo.
--
-- MouseLeave existe junto com MouseButton1Up de propósito: se o dedo
-- escorregar pra fora do botão, o Up nunca chega e o chute ficaria
-- carregando pra sempre — o jogador ficaria preso, lento, sem entender.
local kickButton = makeButton({
	Name = "Kick",
	Text = "CHUTE",
	TextSize = 15,
	-- Fica na fileira de baixo (onde antes ficava ao lado do SPRINT): é a faixa mais
	-- alcançável pelo polegar direito, e a única livre desse tamanho (o
	-- canto inferior direito é do botão de PULAR nativo do Roblox, que não
	-- dá pra ocupar). Posição conferida contra todos os outros botões — sem
	-- sobreposição em nenhum.
	Size = UDim2.fromOffset(84, 84),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -216, 1, -20),
	Color = Color3.fromRGB(35, 150, 90),
})
kickButton.MouseButton1Down:Connect(function()
	_G.MobileKickStart()
end)
kickButton.MouseButton1Up:Connect(function()
	_G.MobileKickRelease()
end)
kickButton.MouseLeave:Connect(function()
	_G.MobileKickRelease()
end)

-- ===== SPRINT =====
-- ⚠️ NOVO: botão SPRINT REMOVIDO — PEDIDO: "Não haverá botão de corrida/
-- sprint". O personagem corre na velocidade do atributo Velocidade só com
-- o joystick (ver getRunSpeed em PlayerSystems.legacy.luau).

-- ===== SHIFT LOCK (toggle) =====
local shiftLockButton = makeButton({
	Name = "ShiftLock",
	Text = "CÂMERA",
	TextSize = 11,
	Size = UDim2.fromOffset(56, 56),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -110),
})
shiftLockButton.MouseButton1Click:Connect(function()
	_G.MobileToggleShiftLock()
end)

-- ===== CABEÇADA (G) =====
local headerButton = makeButton({
	Name = "Header",
	Text = "CABEÇA",
	TextSize = 11,
	Size = UDim2.fromOffset(60, 60),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -90, 1, -110),
	Color = Color3.fromRGB(160, 60, 60),
})
headerButton.MouseButton1Click:Connect(function()
	_G.MobileHeader()
end)

-- ===== PASSE (H) — só jogador de linha =====
local passButton = makeButton({
	Name = "Pass",
	Text = "PASSE",
	TextSize = 12,
	Size = UDim2.fromOffset(60, 60),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -160, 1, -110),
	Color = Color3.fromRGB(60, 150, 90),
})
passButton.MouseButton1Click:Connect(function()
	_G.MobileRequestPass()
end)

-- ===== INSTINTO / ARMA (R = slot 1; slot 2 usa T, só no teclado por ora) =====
local instinctButton = makeButton({
	Name = "Instinct",
	Text = "ARMA",
	TextSize = 10,
	Size = UDim2.fromOffset(56, 56),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -180),
	Color = Color3.fromRGB(150, 120, 40),
})
instinctButton.MouseButton1Click:Connect(function()
	_G.MobileActivateInstinct()
end)

-- ===== INSTINCT MODE (V) =====
local instinctModeButton = makeButton({
	Name = "InstinctMode",
	Text = "MODO",
	TextSize = 12,
	Size = UDim2.fromOffset(56, 56),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -90, 1, -180),
	Color = Color3.fromRGB(150, 60, 160),
})
instinctModeButton.MouseButton1Click:Connect(function()
	_G.MobileActivateInstinctMode()
end)

-- ===== PULSO (slots 1 e 2) =====
local pulse1Button = makeButton({
	Name = "Pulse1",
	Text = "HISSATSU 1",
	TextSize = 10,
	Size = UDim2.fromOffset(56, 56),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -160, 1, -180),
	Color = Color3.fromRGB(40, 150, 150),
})
pulse1Button.MouseButton1Click:Connect(function()
	_G.MobileUsePulse(1)
end)

local pulse2Button = makeButton({
	Name = "Pulse2",
	Text = "HISSATSU 2",
	TextSize = 10,
	Size = UDim2.fromOffset(56, 56),
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -230, 1, -180),
	Color = Color3.fromRGB(40, 150, 150),
	Visible = false, -- só jogador de linha (ver loop de visibilidade abaixo)
})
pulse2Button.MouseButton1Click:Connect(function()
	_G.MobileUsePulse(2)
end)

-- ===== CLUSTER Z / X / C =====
-- Vira Finta (linha) ou Mergulho (GK efetivo) sozinho, ver loop abaixo.
-- Z = esquerda, X = trás/cima, C = direita — mesma posição relativa das
-- teclas físicas, só que como 3 botões num arco.
local function onZ()
	_G.MobileDribble("Left")
	_G.MobileGKDive("Left")
	-- ⚠️ v67: o carrinho SAIU daqui e virou botão próprio (ver tackleButton
	-- acima). Um botão que faz drible OU carrinho dependendo do contexto é
	-- justamente o que confundia.
end
local function onX()
	_G.MobileDribble("Back")
	_G.MobileGKDive("Up")
end
local function onC()
	_G.MobileDribble("Right")
	_G.MobileGKDive("Right")
end

local zButton = makeButton({
	Name = "MoveLeft",
	Text = "◀",
	Size = UDim2.fromOffset(52, 52),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -200, 1, -250),
	Color = Color3.fromRGB(60, 60, 70),
})
zButton.MouseButton1Click:Connect(onZ)

local xButton = makeButton({
	Name = "MoveBack",
	Text = "▲",
	Size = UDim2.fromOffset(52, 52),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -145, 1, -290),
	Color = Color3.fromRGB(60, 60, 70),
})
xButton.MouseButton1Click:Connect(onX)

local cButton = makeButton({
	Name = "MoveRight",
	Text = "▶",
	Size = UDim2.fromOffset(52, 52),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -90, 1, -250),
	Color = Color3.fromRGB(60, 60, 70),
})
cButton.MouseButton1Click:Connect(onC)

-- ===== CARRINHO (⚠️ v67) =====
-- PEDIDO: "sobre o carrinho, coloca mais um botão ali na esquerda, que tem
-- uma areazinha preparada ali pro carrinho."
--
-- Antes o carrinho no celular vinha de carona no botão de drible esquerdo
-- (o `onZ` chama MobileDribble E MobileTackle) — o que é confuso: o mesmo
-- botão fazia duas coisas diferentes dependendo de você ter a bola ou não.
-- Agora ele tem o próprio, e o botão de drible volta a ser só drible.
local tackleButton = makeButton({
	Name = "Tackle",
	Text = "DASH", -- ⚠️ NOVO: o carrinho virou o Dash (tecla F no PC)
	TextSize = 10,
	Size = UDim2.fromOffset(62, 62),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -272, 1, -250),
	Color = Color3.fromRGB(190, 80, 40),
	Visible = false,
})
tackleButton.MouseButton1Click:Connect(function()
	_G.MobileTackle()
end)

-- ===== SÓ GOLEIRO: mergulhos diagonais (E/Q) e dash (F) =====
local diveUpRightButton = makeButton({
	Name = "DiveUpRight",
	Text = "↗",
	Size = UDim2.fromOffset(46, 46),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -115, 1, -350),
	Color = Color3.fromRGB(80, 80, 95),
	Visible = false,
})
diveUpRightButton.MouseButton1Click:Connect(function()
	_G.MobileGKDive("UpRight")
end)

local diveUpLeftButton = makeButton({
	Name = "DiveUpLeft",
	Text = "↖",
	Size = UDim2.fromOffset(46, 46),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -175, 1, -350),
	Color = Color3.fromRGB(80, 80, 95),
	Visible = false,
})
diveUpLeftButton.MouseButton1Click:Connect(function()
	_G.MobileGKDive("UpLeft")
end)

local gkForwardButton = makeButton({
	Name = "GKForward",
	Text = "SAÍDA",
	TextSize = 10,
	Size = UDim2.fromOffset(50, 50),
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(1, -145, 1, -400),
	Color = Color3.fromRGB(80, 80, 95),
	Visible = false,
})
gkForwardButton.MouseButton1Click:Connect(function()
	_G.MobileGKForward()
end)

-- ===== ALTERNA VISIBILIDADE conforme papel (goleiro efetivo ou não) =====
-- Mesma checagem que os scripts de teclado já usam (GKAreaUtil), só que
-- aqui é só cosmético (qual botão aparece) — quem trava a ação de
-- verdade continua sendo cada _G.MobileX / o servidor.
-- ⚠️ v67 — PEDIDO: "coloca os botões de drible (pra cima, esquerda, direita)
-- APENAS quando o jogador estiver com a bola, porque senão vai ficar
-- poluindo a tela dele."
--
-- Mesma fonte de posse que AbilityHUD/FootballClient já usam — não precisa
-- de remote novo. Só interessa se EU tenho a bola.
local temPosse = false
Remotes.PossessionChanged.OnClientEvent:Connect(function(quemPegou, ganhou)
	if quemPegou == player then
		temPosse = ganhou and true or false
	elseif ganhou then
		temPosse = false -- outra pessoa dominou: deixou de ser minha
	end
end)

local lastIsGK, lastPosse = nil, nil
RunService.Heartbeat:Connect(function()
	local isGK = GKAreaUtil.IsEffectiveGK(player)
	if isGK == lastIsGK and temPosse == lastPosse then return end
	lastIsGK, lastPosse = isGK, temPosse

	diveUpRightButton.Visible = isGK
	diveUpLeftButton.Visible = isGK
	gkForwardButton.Visible = isGK
	passButton.Visible = not isGK
	pulse2Button.Visible = not isGK

	-- Pro GOLEIRO, Z/X/C são MERGULHOS — ele precisa deles justamente quando
	-- NÃO tem a bola, então ali eles ficam sempre visíveis.
	-- Pro jogador de linha são DRIBLES, e drible sem bola não existe.
	zButton.Visible = isGK or temPosse
	xButton.Visible = isGK or temPosse
	cButton.Visible = isGK or temPosse

	-- Carrinho: só faz sentido pra jogador de linha SEM a bola (é a regra que
	-- o servidor já aplica em _G.MobileTackle).
	tackleButton.Visible = (not isGK) and (not temPosse)
end)

print("✅ MobileControls (Game) carregado — controles touch ativos.")
