--[[
	PulsePrecisionWindow (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	Componente visual ÚNICO e reutilizável pro QTE de qualquer Pulso com
	Combo — em vez de cada Pulso ter sua própria cópia de UI,
	PulseInput.local.luau chama PulsePrecisionWindow.Show(...) toda vez que
	o servidor manda Remotes.PulsePrecisionPrompt, só parametrizado por
	delay/stepTime/nome/sequência de teclas. Tudo construído via
	Instance.new (GUI não sincroniza pela ponte, só scripts — ver
	comentário no topo de AbilityHUD.local.luau).

	⚠️ PULSO v3: o QTE deixou de ser "aperte a MESMA tecla de novo dentro
	de uma janela" e virou um COMBO DE TECLAS (ex: Q → E → Q). A UI agora
	é uma FILEIRA DE CHIPS, um por tecla da sequência:
		[Q] [E] [Q]
	- Chip do passo ATUAL: destacado e pulsando (escala + cor).
	- Chips já ACERTADOS: verdes.
	- Chips PERDIDOS (tecla errada ou passo que fechou sem aperto):
	  vermelhos.
	- Chips que ainda não chegaram: cinza apagado.
	Abaixo dos chips fica uma barrinha de tempo SÓ DO PASSO ATUAL
	(enchendo de 0 a 100% ao longo de StepTime), e durante o wind-up
	inicial (Delay) ela conta o "prepara..." em amarelo, sem nenhum chip
	ativo ainda.

	Fases (as mesmas que o servidor está contando, ver PulseController):
	1. 0..Delay                                → wind-up ("prepara...")
	2. Delay + StepTime*(i-1) .. Delay+StepTime*i → passo i aberto
	3. Delay + StepTime*#Keys                  → fecha sozinha (o servidor
	   resolve nesse mesmo instante, Perfect se acertou TODOS os passos,
	   Bom em qualquer outro caso — perder passos nunca é whiff total).

	PulsePrecisionWindow.MarkStep(index, hit) pinta um chip na hora, pro
	jogador ter feedback IMEDIATO do próprio aperto sem esperar o round-
	trip do servidor. ⚠️ Isso é só cosmético: o placar que vale é sempre
	o do servidor (ele reconfirma cada passo por Remotes.PulseFeedback
	"ComboStep", ver PulseInput.local.luau).

	Uma instância por vez é suficiente aqui (cada jogador só controla o
	próprio personagem, e o servidor só deixa 1 combo pendente por slot),
	então o módulo guarda um único ScreenGui reaproveitado entre chamadas.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PulsePrecisionWindow = {}

local player = Players.LocalPlayer
local screenGui, chipsRow, barFill, promptLabel, nameLabel
local activeConnection
local chips = {}       -- [i] = { Frame, Label } (reaproveitados entre chamadas)
local chipState = {}   -- [i] = nil (pendente) | "hit" | "miss"
local currentKeys = {}

local COLOR_IDLE = Color3.fromRGB(60, 60, 70)
local COLOR_ACTIVE = Color3.fromRGB(255, 210, 90)
local COLOR_HIT = Color3.fromRGB(90, 220, 120)
local COLOR_MISS = Color3.fromRGB(230, 70, 80)

local CHIP_SIZE = 40
local CHIP_GAP = 6

local function ensureGui()
	if screenGui and screenGui.Parent then return end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PulsePrecisionWindow"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.Parent = player:WaitForChild("PlayerGui")

	local frame = Instance.new("Frame")
	frame.Name = "Frame"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.new(0.5, 0, 0.62, 0)
	frame.Size = UDim2.fromOffset(320, 110)
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0, 20)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 15
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.Text = ""
	nameLabel.Parent = frame

	-- Fileira de chips de tecla — centralizada, um chip por passo do
	-- combo. Os chips em si são criados sob demanda em buildChips (o
	-- número de passos muda de Pulso pra Pulso).
	chipsRow = Instance.new("Frame")
	chipsRow.Name = "ChipsRow"
	chipsRow.AnchorPoint = Vector2.new(0.5, 0)
	chipsRow.Position = UDim2.new(0.5, 0, 0, 26)
	chipsRow.Size = UDim2.new(1, 0, 0, CHIP_SIZE)
	chipsRow.BackgroundTransparency = 1
	chipsRow.Parent = frame

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, CHIP_GAP)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.Parent = chipsRow

	local barBack = Instance.new("Frame")
	barBack.Name = "BarBack"
	barBack.AnchorPoint = Vector2.new(0.5, 0)
	barBack.Position = UDim2.new(0.5, 0, 0, 74)
	barBack.Size = UDim2.new(0, 220, 0, 10)
	barBack.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	barBack.BackgroundTransparency = 0.2
	barBack.BorderSizePixel = 0
	barBack.Parent = frame
	local barBackCorner = Instance.new("UICorner")
	barBackCorner.CornerRadius = UDim.new(1, 0)
	barBackCorner.Parent = barBack

	barFill = Instance.new("Frame")
	barFill.Name = "Fill"
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = COLOR_ACTIVE
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack
	local barFillCorner = Instance.new("UICorner")
	barFillCorner.CornerRadius = UDim.new(1, 0)
	barFillCorner.Parent = barFill

	promptLabel = Instance.new("TextLabel")
	promptLabel.Name = "PromptLabel"
	promptLabel.Position = UDim2.new(0, 0, 0, 88)
	promptLabel.Size = UDim2.new(1, 0, 0, 20)
	promptLabel.BackgroundTransparency = 1
	promptLabel.Font = Enum.Font.GothamBold
	promptLabel.TextSize = 14
	promptLabel.TextColor3 = COLOR_ACTIVE
	promptLabel.Text = ""
	promptLabel.Parent = frame

	screenGui.Enabled = false
end

-- Cria/reaproveita um chip por tecla da sequência e esconde os que
-- sobraram de um combo anterior mais longo.
local function buildChips(keys)
	for index, keyName in ipairs(keys) do
		local chip = chips[index]
		if not chip then
			local chipFrame = Instance.new("Frame")
			chipFrame.Name = "Chip" .. index
			chipFrame.LayoutOrder = index
			chipFrame.Size = UDim2.fromOffset(CHIP_SIZE, CHIP_SIZE)
			chipFrame.BackgroundColor3 = COLOR_IDLE
			chipFrame.BorderSizePixel = 0
			chipFrame.Parent = chipsRow

			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 8)
			corner.Parent = chipFrame

			local stroke = Instance.new("UIStroke")
			stroke.Name = "Stroke"
			stroke.Thickness = 2
			stroke.Color = COLOR_IDLE
			stroke.Parent = chipFrame

			-- UIScale é o que faz o chip do passo atual "pulsar" sem
			-- mexer no layout dos vizinhos (a UIListLayout continua
			-- reservando o mesmo espaço).
			local scale = Instance.new("UIScale")
			scale.Name = "Scale"
			scale.Parent = chipFrame

			local label = Instance.new("TextLabel")
			label.Name = "Key"
			label.BackgroundTransparency = 1
			label.Size = UDim2.new(1, 0, 1, 0)
			label.Font = Enum.Font.GothamBlack
			label.TextSize = 20
			label.TextColor3 = Color3.fromRGB(255, 255, 255)
			label.Parent = chipFrame

			chip = { Frame = chipFrame, Label = label, Stroke = stroke, Scale = scale }
			chips[index] = chip
		end
		chip.Label.Text = keyName
		chip.Frame.BackgroundColor3 = COLOR_IDLE
		chip.Stroke.Color = COLOR_IDLE
		chip.Scale.Scale = 1
		chip.Frame.Visible = true
	end

	for index = #keys + 1, #chips do
		chips[index].Frame.Visible = false
	end
end

local function paintChip(index, color, scale)
	local chip = chips[index]
	if not chip then return end
	chip.Frame.BackgroundColor3 = color
	chip.Stroke.Color = color
	chip.Scale.Scale = scale or 1
end

-- Esconde a janela na hora (chamado tanto quando o combo fecha sozinho
-- quanto quando o cliente recebe a confirmação do servidor de que já
-- resolveu, pra não deixar sobrando na tela nem 1 frame a mais).
function PulsePrecisionWindow.Hide()
	if activeConnection then
		activeConnection:Disconnect()
		activeConnection = nil
	end
	if screenGui then
		screenGui.Enabled = false
	end
	chipState = {}
	currentKeys = {}
end

-- Feedback IMEDIATO do próprio aperto (ou da confirmação do servidor):
-- pinta o chip do passo "index" de verde (hit) ou vermelho (miss). Só
-- cosmético — quem conta os acertos de verdade é o servidor.
function PulsePrecisionWindow.MarkStep(index, hit)
	if not index or not chips[index] then return end
	chipState[index] = hit and "hit" or "miss"
	paintChip(index, hit and COLOR_HIT or COLOR_MISS, 1)
end

-- Mostra o QTE de combo de um Pulso: wind-up de delaySeconds (barra
-- amarela, "prepara...", nenhum chip ativo) seguido de #keys passos de
-- stepTime segundos cada, um chip por passo.
-- keys: array de nomes curtos de tecla ({"Q","E","Q"}).
function PulsePrecisionWindow.Show(pulseName, delaySeconds, stepTime, keys)
	ensureGui()
	PulsePrecisionWindow.Hide()

	keys = (typeof(keys) == "table" and #keys > 0) and keys or { "Q" }
	delaySeconds = math.max(tonumber(delaySeconds) or 0, 0)
	stepTime = math.max(tonumber(stepTime) or 0.3, 0.05)

	currentKeys = keys
	chipState = {}
	buildChips(keys)

	screenGui.Enabled = true
	nameLabel.Text = pulseName or "Pulso"
	promptLabel.Text = "prepara..."
	promptLabel.TextColor3 = COLOR_ACTIVE
	barFill.Size = UDim2.new(1, 0, 1, 0)
	barFill.BackgroundColor3 = COLOR_ACTIVE

	local total = delaySeconds + stepTime * #keys
	local startedAt = os.clock()

	activeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt

		if elapsed >= total then
			PulsePrecisionWindow.Hide()
			return
		end

		if elapsed < delaySeconds then
			-- Fase 1: wind-up — barra amarela ENCOLHENDO até o primeiro
			-- passo abrir. Nenhum chip aceso ainda.
			local alpha = delaySeconds > 0 and (1 - elapsed / delaySeconds) or 0
			barFill.Size = UDim2.new(alpha, 0, 1, 0)
			barFill.BackgroundColor3 = COLOR_ACTIVE
			promptLabel.Text = "prepara..."
			promptLabel.TextColor3 = COLOR_ACTIVE
			return
		end

		-- Fase 2: um passo por vez. O índice do passo atual é derivado do
		-- tempo — exatamente a mesma conta que o servidor faz pra decidir
		-- em qual passo um aperto caiu (ver PulseController).
		local intoSteps = elapsed - delaySeconds
		local stepIndex = math.min(math.floor(intoSteps / stepTime) + 1, #keys)
		local stepProgress = (intoSteps - (stepIndex - 1) * stepTime) / stepTime

		-- Passos anteriores que fecharam sem resposta viram "perdidos"
		-- (o servidor conta a mesma coisa: passo sem aperto = falhou).
		for i = 1, stepIndex - 1 do
			if not chipState[i] then
				chipState[i] = "miss"
				paintChip(i, COLOR_MISS, 1)
			end
		end

		-- Chip atual: pulsa (escala + cor) enquanto o passo está aberto,
		-- a não ser que o jogador já tenha respondido esse passo.
		if not chipState[stepIndex] then
			local pulse = 1 + 0.12 * math.sin(os.clock() * 14)
			paintChip(stepIndex, COLOR_ACTIVE, pulse)
		end

		barFill.Size = UDim2.new(math.clamp(stepProgress, 0, 1), 0, 1, 0)
		barFill.BackgroundColor3 = COLOR_ACTIVE
		promptLabel.TextColor3 = COLOR_ACTIVE
		promptLabel.Text = ("passo %d/%d — %s!"):format(stepIndex, #keys, currentKeys[stepIndex] or "?")
	end)
end

return PulsePrecisionWindow
