--[[
	HissatsuQTEWindow (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	Componente visual dos 3 QTEs NOVOS do lote de Pulsos "Hissatsu" (v6,
	ver PulseController.legacy.luau -> startHissatsuQTE e
	PulseInstinctData.luau -> campo QTE de cada Pulso). Mesma ideia do
	PulsePrecisionWindow.luau (módulo único reutilizável, tudo via
	Instance.new — GUI não sincroniza pela ponte, só script), só que pros
	3 tipos NOVOS de minigame pedidos pelo usuário, diferentes do combo de
	teclas antigo:

	"Tap" (chutes): depois de PrepTime segundos de preparo (barra
	amarela "prepara... pode tomar carrinho!"), aparece um alvo circular
	numa posição ALEATÓRIA dentro de um quadrado fixo no centro da tela
	(pra nunca nascer num canto esquisito) — clique nele dentro de
	HitWindow segundos. Metade mais rápida da janela = Perfect.

	"TimingBar" (defesa): uma barra enche da esquerda pra direita ao
	longo de Duration segundos, com uma faixa VERDE (Perfect) e uma
	faixa AMARELA mais larga ao redor dela (Bom) desenhadas de acordo
	com PerfectStart/PerfectEnd/GoodPadding — aperte ESPAÇO (ou clique no
	botão) no momento certo.

	"MashAD" (arrancada): alterne A e D o mais rápido possível até bater
	RequiredAlternations — uma barra de progresso enche a cada troca
	válida.

	Em QUALQUER Pulse Feedback terminal (Fired/Fizzled/Whiffed) a janela
	se esconde na hora — ver HissatsuInput.local.luau, que é quem chama
	Hide() nesses casos.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local HissatsuQTEWindow = {}

local player = Players.LocalPlayer
local screenGui
local activeConnections = {} -- lista de RBXScriptConnection pra desconectar tudo no Hide()
local currentSlot = nil
local onInputCallback = nil -- function(payload) chamada quando o jogador "responde" o QTE ativo

local COLOR_PREP = Color3.fromRGB(255, 210, 90)
local COLOR_ACTIVE = Color3.fromRGB(90, 210, 255)
local COLOR_PERFECT = Color3.fromRGB(90, 220, 120)
local COLOR_GOOD = Color3.fromRGB(255, 210, 90)
local COLOR_MISS = Color3.fromRGB(230, 70, 80)

local function ensureGui()
	if screenGui and screenGui.Parent then return end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HissatsuQTEWindow"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 55
	screenGui.Enabled = false
	screenGui.Parent = player:WaitForChild("PlayerGui")
end

local function clearGui()
	if screenGui then
		for _, child in ipairs(screenGui:GetChildren()) do
			child:Destroy()
		end
	end
end

local function disconnectAll()
	for _, conn in ipairs(activeConnections) do
		conn:Disconnect()
	end
	activeConnections = {}
end

function HissatsuQTEWindow.Hide()
	disconnectAll()
	if screenGui then
		screenGui.Enabled = false
	end
	currentSlot = nil
	onInputCallback = nil
	-- ⚠️ v9: restaura o Shift Lock (se estava ligado antes) assim que
	-- QUALQUER QTE fecha — ver showTap abaixo e _G.SetMouseLockSuspendedForQTE
	-- em FootballClient.local.luau. Seguro chamar mesmo se não era um QTE
	-- de clique (TimingBar/MashAD nunca suspendem, então isto não faz nada).
	if _G.SetMouseLockSuspendedForQTE then _G.SetMouseLockSuspendedForQTE(false) end
end

-- ============================================================
-- "Tap" — alvo numa posição aleatória dentro de um quadrado fixo
-- ============================================================
local TAP_ZONE_SIZE = 280 -- lado do quadrado (px) onde o alvo pode nascer
local TAP_TARGET_SIZE = 64

local function showTap(pulseName, params)
	clearGui()

	-- ⚠️ v9 PEDIDO: destrava o mouse (se estava preso no centro pelo Shift
	-- Lock) assim que o QTE de CLIQUE aparece — a mira do chute já foi
	-- travada antes disso (ver HissatsuInput.local.luau), então mexer o
	-- mouse pra clicar os alvos não muda mais pra onde a bola vai.
	if _G.SetMouseLockSuspendedForQTE then _G.SetMouseLockSuspendedForQTE(true) end

	local frame = Instance.new("Frame")
	frame.Name = "TapFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.42, 0)
	frame.Size = UDim2.fromOffset(TAP_ZONE_SIZE, TAP_ZONE_SIZE)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local zoneOutline = Instance.new("Frame")
	zoneOutline.Name = "ZoneOutline"
	zoneOutline.Size = UDim2.new(1, 0, 1, 0)
	zoneOutline.BackgroundTransparency = 1
	zoneOutline.Parent = frame

	local zoneStroke = Instance.new("UIStroke")
	zoneStroke.Color = COLOR_PREP
	zoneStroke.Thickness = 2
	zoneStroke.Transparency = 0.4
	zoneStroke.Parent = zoneOutline

	local zoneCorner = Instance.new("UICorner")
	zoneCorner.CornerRadius = UDim.new(0, 16)
	zoneCorner.Parent = zoneOutline

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.AnchorPoint = Vector2.new(0.5, 1)
	nameLabel.Position = UDim2.new(0.5, 0, 0, -10)
	nameLabel.Size = UDim2.new(1, 0, 0, 24)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = pulseName or "Pulso"
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Parent = frame

	local promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "PromptLabel"
	promptLabel.AnchorPoint = Vector2.new(0.5, 0)
	promptLabel.Position = UDim2.new(0.5, 0, 1, 10)
	promptLabel.Size = UDim2.new(1, 0, 0, 22)
	promptLabel.BackgroundTransparency = 1
	promptLabel.Text = "prepara... (pode tomar carrinho!)"
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.TextSize = 14
	promptLabel.TextColor3 = COLOR_PREP
	promptLabel.Parent = frame

	-- PEDIDO: "vários botões pra apertar, não só 1" — contador de quantos
	-- dos RequiredHits alvos já foram clicados.
	local hitsLabel = Instance.new("TextLabel")
	hitsLabel.Name = "HitsLabel"
	hitsLabel.AnchorPoint = Vector2.new(0.5, 0)
	hitsLabel.Position = UDim2.new(0.5, 0, 1, 34)
	hitsLabel.Size = UDim2.new(1, 0, 0, 20)
	hitsLabel.BackgroundTransparency = 1
	hitsLabel.Text = ""
	hitsLabel.Font = Enum.Font.GothamBlack
	hitsLabel.TextSize = 16
	hitsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hitsLabel.Parent = frame

	local target = Instance.new("TextButton")
	target.Name = "Target"
	target.Size = UDim2.fromOffset(TAP_TARGET_SIZE, TAP_TARGET_SIZE)
	target.AnchorPoint = Vector2.new(0.5, 0.5)
	target.Position = UDim2.new(0.5, 0, 0.5, 0)
	target.BackgroundColor3 = COLOR_ACTIVE
	target.Text = "!"
	target.Font = Enum.Font.GothamBlack
	target.TextSize = 26
	target.TextColor3 = Color3.fromRGB(20, 20, 25)
	target.AutoButtonColor = false
	target.Visible = false
	target.Parent = frame

	local targetCorner = Instance.new("UICorner")
	targetCorner.CornerRadius = UDim.new(1, 0)
	targetCorner.Parent = target

	local prepTime = math.max(tonumber(params.PrepTime) or 0, 0)
	local hitWindow = math.max(tonumber(params.HitWindow) or 0.8, 0.1)
	local requiredHits = math.max(tonumber(params.RequiredHits) or 5, 1)
	local startedAt = os.clock()
	local targetShown = false
	local hits = 0
	local done = false

	local half = TAP_TARGET_SIZE / 2
	local margin = half + 6 -- garante que o alvo nasce INTEIRO dentro do quadrado, nunca cortado na borda

	local function placeTargetRandomly()
		local x = math.random(margin, TAP_ZONE_SIZE - margin)
		local y = math.random(margin, TAP_ZONE_SIZE - margin)
		target.Position = UDim2.fromOffset(x, y)
	end

	hitsLabel.Text = ("0 / %d"):format(requiredHits)

	-- PEDIDO: "faz uns 5 botões aparecerem" — cada clique válido conta 1
	-- acerto (o servidor é quem decide de verdade, isso aqui é só visual)
	-- e um NOVO alvo nasce em outra posição aleatória, até bater
	-- requiredHits ou a janela fechar.
	target.MouseButton1Click:Connect(function()
		if done or not targetShown then return end
		hits += 1
		hitsLabel.Text = ("%d / %d"):format(hits, requiredHits)
		if onInputCallback then onInputCallback({}) end
		if hits >= requiredHits then
			done = true
			target.BackgroundColor3 = COLOR_PERFECT
			target.Visible = false
		else
			target.BackgroundColor3 = COLOR_ACTIVE
			placeTargetRandomly()
		end
	end)

	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt

		if elapsed < prepTime then
			local alpha = prepTime > 0 and (elapsed / prepTime) or 1
			zoneStroke.Color = COLOR_PREP
			promptLabel.Text = ("prepara... (pode tomar carrinho!) %d%%"):format(math.floor(alpha * 100))
			return
		end

		if done then return end

		if not targetShown then
			targetShown = true
			placeTargetRandomly()
			target.Visible = true
			target.Size = UDim2.fromOffset(TAP_TARGET_SIZE, TAP_TARGET_SIZE)
			promptLabel.Text = "CLICA NOS ALVOS!"
			promptLabel.TextColor3 = COLOR_ACTIVE
			zoneStroke.Color = COLOR_ACTIVE
		end

		local intoWindow = elapsed - prepTime
		if intoWindow >= hitWindow then
			HissatsuQTEWindow.Hide()
			return
		end

		-- Encolhe o alvo ATUAL conforme a janela total fecha — feedback
		-- visual de "o tempo está acabando", sem precisar de barra
		-- separada.
		local shrink = 1 - 0.35 * (intoWindow / hitWindow)
		target.Size = UDim2.fromOffset(TAP_TARGET_SIZE * shrink, TAP_TARGET_SIZE * shrink)
	end))
end

-- ============================================================
-- "TimingBar" — barra que enche, aperte ESPAÇO/clique no momento certo
-- ============================================================
local BAR_WIDTH = 320

local function showTimingBar(pulseName, params)
	clearGui()

	local frame = Instance.new("Frame")
	frame.Name = "TimingBarFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.62, 0)
	frame.Size = UDim2.fromOffset(BAR_WIDTH, 90)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = pulseName or "Pulso"
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Parent = frame

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.Position = UDim2.new(0, 0, 0, 28)
	barBack.Size = UDim2.new(1, 0, 0, 22)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	barBack.BorderSizePixel = 0
	barBack.ClipsDescendants = false
	barBack.Parent = frame

	local barBackCorner = Instance.new("UICorner")
	barBackCorner.CornerRadius = UDim.new(0, 8)
	barBackCorner.Parent = barBack

	local perfectStart = math.clamp(tonumber(params.PerfectStart) or 0.4, 0, 1)
	local perfectEnd = math.clamp(tonumber(params.PerfectEnd) or 0.6, perfectStart, 1)
	local goodPadding = math.max(tonumber(params.GoodPadding) or 0.12, 0)
	local goodStart = math.max(perfectStart - goodPadding, 0)
	local goodEnd = math.min(perfectEnd + goodPadding, 1)

	local goodZone = Instance.new("Frame")
	goodZone.Name = "GoodZone"
	goodZone.BackgroundColor3 = COLOR_GOOD
	goodZone.BackgroundTransparency = 0.4
	goodZone.BorderSizePixel = 0
	goodZone.Position = UDim2.new(goodStart, 0, 0, 0)
	goodZone.Size = UDim2.new(goodEnd - goodStart, 0, 1, 0)
	goodZone.ZIndex = 2
	goodZone.Parent = barBack

	local perfectZone = Instance.new("Frame")
	perfectZone.Name = "PerfectZone"
	perfectZone.BackgroundColor3 = COLOR_PERFECT
	perfectZone.BackgroundTransparency = 0.15
	perfectZone.BorderSizePixel = 0
	perfectZone.Position = UDim2.new(perfectStart, 0, 0, 0)
	perfectZone.Size = UDim2.new(perfectEnd - perfectStart, 0, 1, 0)
	perfectZone.ZIndex = 2
	perfectZone.Parent = barBack

	local marker = Instance.new("Frame")
	marker.Name = "Marker"
	marker.AnchorPoint = Vector2.new(0.5, 0)
	marker.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	marker.BorderSizePixel = 0
	marker.Size = UDim2.new(0, 4, 1, 8)
	marker.Position = UDim2.new(0, 0, 0, -4)
	marker.ZIndex = 3
	marker.Parent = barBack

	-- PEDIDO: "no GK precisa acertar a barra 5 vezes num período de
	-- tempo" — o marcador agora anda pra frente E pra trás (ping-pong) em
	-- ciclos de SweepPeriod segundos, em vez de um passe único, e é
	-- preciso acertar a faixa boa RequiredHits vezes antes de Duration
	-- acabar.
	local promptLabel = Instance.new("TextLabel")
	promptLabel.Position = UDim2.new(0, 0, 0, 56)
	promptLabel.Size = UDim2.new(1, 0, 0, 22)
	promptLabel.BackgroundTransparency = 1
	promptLabel.Text = "ESPAÇO (ou clique) no momento certo!"
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.TextSize = 13
	promptLabel.TextColor3 = COLOR_ACTIVE
	promptLabel.Parent = frame

	local hitsLabel = Instance.new("TextLabel")
	hitsLabel.Name = "HitsLabel"
	hitsLabel.Position = UDim2.new(0, 0, 0, 76)
	hitsLabel.Size = UDim2.new(1, 0, 0, 20)
	hitsLabel.BackgroundTransparency = 1
	hitsLabel.Font = Enum.Font.GothamBlack
	hitsLabel.TextSize = 15
	hitsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	hitsLabel.Parent = frame

	local pressButton = Instance.new("TextButton")
	pressButton.Name = "PressButton"
	pressButton.Position = UDim2.new(0, 0, 0, 56)
	pressButton.Size = UDim2.new(1, 0, 0, 22)
	pressButton.BackgroundTransparency = 1
	pressButton.Text = ""
	pressButton.AutoButtonColor = false
	pressButton.Parent = frame

	local duration = math.max(tonumber(params.Duration) or 1.2, 0.2)
	local sweepPeriod = math.max(tonumber(params.SweepPeriod) or 0.9, 0.1)
	local requiredHits = math.max(tonumber(params.RequiredHits) or 5, 1)
	local startedAt = os.clock()
	local hits = 0
	local resolved = false

	hitsLabel.Text = ("0 / %d"):format(requiredHits)

	-- Mesma fórmula de ping-pong usada pelo servidor (PulseController.
	-- legacy.luau -> sweepFraction) — só visual aqui, o servidor decide
	-- de verdade se o clique contou.
	local function sweepFraction(elapsed)
		local cycle = sweepPeriod * 2
		local t = elapsed % cycle
		if t <= sweepPeriod then
			return t / sweepPeriod
		end
		return 1 - (t - sweepPeriod) / sweepPeriod
	end

	local function respond()
		if resolved then return end
		if onInputCallback then onInputCallback({}) end
		-- Feedback visual OTIMISTA (o servidor confirma de verdade): conta
		-- como acerto se o marcador estiver dentro da faixa amarela/verde
		-- agora mesmo.
		local elapsed = os.clock() - startedAt
		local fraction = sweepFraction(elapsed)
		if fraction >= goodStart and fraction <= goodEnd then
			hits = math.min(hits + 1, requiredHits)
			hitsLabel.Text = ("%d / %d"):format(hits, requiredHits)
			if hits >= requiredHits then
				resolved = true
			end
		end
	end

	pressButton.MouseButton1Click:Connect(respond)

	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			respond()
		end
	end))

	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		if resolved or elapsed >= duration then
			HissatsuQTEWindow.Hide()
			return
		end
		local fraction = sweepFraction(elapsed)
		marker.Position = UDim2.new(fraction, 0, 0, -4)
	end))
end

-- ============================================================
-- "MashAD" — alterna A/D até bater RequiredAlternations
-- ============================================================
local function showMashAD(pulseName, params)
	clearGui()

	local frame = Instance.new("Frame")
	frame.Name = "MashADFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.62, 0)
	frame.Size = UDim2.fromOffset(300, 150) -- +50 pra caber os botões mobile A/D abaixo da barra
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = pulseName or "Pulso"
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 16
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Parent = frame

	local promptLabel = Instance.new("TextLabel")
	promptLabel.Position = UDim2.new(0, 0, 0, 24)
	promptLabel.Size = UDim2.new(1, 0, 0, 22)
	promptLabel.BackgroundTransparency = 1
	promptLabel.Text = "ALTERNA A e D RÁPIDO!"
	promptLabel.Font = Enum.Font.GothamBlack
	promptLabel.TextSize = 16
	promptLabel.TextColor3 = COLOR_ACTIVE
	promptLabel.Parent = frame

	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 0, 0, 50)
	barBack.Size = UDim2.new(1, 0, 0, 20)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	barBack.BorderSizePixel = 0
	barBack.Parent = frame

	local barBackCorner = Instance.new("UICorner")
	barBackCorner.CornerRadius = UDim.new(0, 8)
	barBackCorner.Parent = barBack

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = COLOR_PERFECT
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(0, 8)
	barFillCorner.Parent = barFill

	local countLabel = Instance.new("TextLabel")
	countLabel.Position = UDim2.new(0, 0, 0, 76)
	countLabel.Size = UDim2.new(1, 0, 0, 20)
	countLabel.BackgroundTransparency = 1
	countLabel.Font = Enum.Font.Gotham
	countLabel.TextSize = 13
	countLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
	countLabel.Parent = frame

	local duration = math.max(tonumber(params.Duration) or 2, 0.2)
	local required = math.max(tonumber(params.RequiredAlternations) or 6, 1)
	local startedAt = os.clock()
	local hits = 0
	local lastKey = nil
	local resolved = false

	local function updateBar()
		barFill.Size = UDim2.new(math.clamp(hits / required, 0, 1), 0, 1, 0)
		countLabel.Text = ("%d / %d"):format(hits, required)
	end
	updateBar()

	-- ⚠️ MOBILE: não tem teclado A/D no celular — essa função central
	-- processa uma "tecla" tanto vindo do UserInputService (teclado)
	-- quanto de um toque nos botões abaixo (criados sempre, mas mais
	-- úteis mesmo em touch — em teclado o jogador pode ignorar e usar
	-- A/D normalmente).
	local function registerPress(key)
		if resolved then return end
		if key == lastKey then return end -- precisa alternar de verdade
		lastKey = key
		hits += 1
		updateBar()
		if onInputCallback then onInputCallback({ Key = key }) end
		if hits >= required then
			resolved = true
		end
	end

	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		local key = (input.KeyCode == Enum.KeyCode.A) and "A" or (input.KeyCode == Enum.KeyCode.D) and "D" or nil
		if not key then return end
		registerPress(key)
	end))

	-- ⚠️ MOBILE: dois botões grandes lado a lado (A à esquerda, D à
	-- direita) — mesmo alternar rápido de antes, só que no toque.
	local mashButtonRow = Instance.new("Frame")
	mashButtonRow.Position = UDim2.new(0, 0, 0, 100)
	mashButtonRow.Size = UDim2.new(1, 0, 0, 44)
	mashButtonRow.BackgroundTransparency = 1
	mashButtonRow.Parent = frame

	local mashLayout = Instance.new("UIListLayout")
	mashLayout.FillDirection = Enum.FillDirection.Horizontal
	mashLayout.Padding = UDim.new(0, 10)
	mashLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	mashLayout.Parent = mashButtonRow

	for _, keyName in ipairs({ "A", "D" }) do
		local mashButton = Instance.new("TextButton")
		mashButton.Size = UDim2.new(0.46, 0, 1, 0)
		mashButton.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
		mashButton.Text = keyName
		mashButton.Font = Enum.Font.GothamBlack
		mashButton.TextSize = 20
		mashButton.TextColor3 = Color3.fromRGB(255, 255, 255)
		mashButton.AutoButtonColor = true
		mashButton.Parent = mashButtonRow

		local mashButtonCorner = Instance.new("UICorner")
		mashButtonCorner.CornerRadius = UDim.new(0, 8)
		mashButtonCorner.Parent = mashButton

		mashButton.MouseButton1Down:Connect(function()
			registerPress(keyName)
		end)
	end

	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		if os.clock() - startedAt >= duration then
			HissatsuQTEWindow.Hide()
		end
	end))
end

-- ============================================================
-- "GKGuardArmed" — v7: a Hissatsu de goleiro não é mais um QTE na hora
-- de usar, só arma a guarda (ver PulseController.legacy.luau ->
-- startGKGuard) — aqui só um aviso pequeno no canto, sem travar nada,
-- enquanto o goleiro espera o chute colidir com a área.
-- ============================================================
local function showGKGuardArmed(pulseName, params)
	clearGui()

	local duration = math.max(tonumber(params.Duration) or 5, 0.1)

	local frame = Instance.new("Frame")
	frame.Name = "GuardArmedFrame"
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0.06, 0)
	frame.Size = UDim2.fromOffset(260, 40)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = COLOR_ACTIVE
	label.Text = ("🛡️ %s ARMADA — espera o chute colidir"):format(pulseName or "Guarda")
	label.Parent = frame

	local startedAt = os.clock()
	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		if os.clock() - startedAt >= duration then
			HissatsuQTEWindow.Hide()
		end
	end))
end

-- ============================================================
-- Entrada pública: HissatsuInput.local.luau chama isso quando o servidor
-- manda Remotes.PulseQTEPrompt.
-- ============================================================
function HissatsuQTEWindow.Show(slot, pulseName, params, inputCallback)
	ensureGui()
	HissatsuQTEWindow.Hide()

	currentSlot = slot
	onInputCallback = inputCallback
	screenGui.Enabled = true

	if params.Kind == "Tap" then
		showTap(pulseName, params)
	elseif params.Kind == "TimingBar" then
		showTimingBar(pulseName, params)
	elseif params.Kind == "MashAD" then
		showMashAD(pulseName, params)
	elseif params.Kind == "GKGuardArmed" then
		showGKGuardArmed(pulseName, params)
	else
		HissatsuQTEWindow.Hide()
	end
end

return HissatsuQTEWindow
