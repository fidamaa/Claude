--[[
	MoneyDisplayClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Reimplementação do "Money Display" que morava dentro da própria GUI
	(removida do Explorer — GUI não sincroniza). Mesma lógica de sempre:
	número formatado com separador de milhares, indicador +/- flutuante
	e piscada de cor ao mudar. Usa os mesmos remotes do MoneyManager.lua
	(MoneyEvents.UpdateMoney / GetMoney) e a NumberValue "Money" que o
	MoneyManager cria no Player.

	ESTRUTURA ASSUMIDA (mesma que você descreveu):

		Money Display (ScreenGui)
		  └─ MoneyFrame (Frame)
		      └─ MoneyLabel (TextLabel)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local UPDATE_ANIMATION = true
local SHOW_PLUS_MINUS = true
local FLASH_COLOR_ON_CHANGE = true

local screenGui = playerGui:WaitForChild("Money Display")
local moneyFrame = screenGui:WaitForChild("MoneyFrame")
local moneyLabel = moneyFrame:WaitForChild("MoneyLabel")

-- ========================================
-- ⚠️ v79 — REESTILIZA A GUI MONTADA NO STUDIO.
-- PEDIDO: "você não alterou a HUD de dinheiro do Lobby... ela precisa
-- ficar bonita". Era um Frame branco chapado (1,1,1) com TextLabel preto
-- em fonte SourceSans padrão, 123x35 — nunca tinha passado pela paleta
-- escura que o resto do Lobby usa hoje (Matchmaking/Missões/Roll, todas
-- v72+). Objetos de GUI não sincronizam do Studio pro disco (só Script),
-- então — mesmo padrão já usado nas outras telas — é o PRÓPRIO SCRIPT
-- que reestiliza os objetos já existentes ao carregar, uma vez só. A
-- lógica de animação/piscada mais abaixo continua igual, só herda a
-- paleta nova.
-- ========================================
local COR_CARTAO  = Color3.fromRGB(21, 24, 34)
local COR_BORDA   = Color3.fromRGB(34, 38, 52)
local COR_OK      = Color3.fromRGB(64, 196, 122)
local COR_TEXTO   = Color3.fromRGB(238, 241, 248)

local function cantosR(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end

local function contornoR(inst, cor, espessura, transparencia)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = espessura or 1
	s.Transparency = transparencia or 0.15
	s.Parent = inst
	return s
end

moneyFrame.Size = UDim2.fromOffset(190, 46)
moneyFrame.BackgroundColor3 = COR_CARTAO
moneyFrame.BackgroundTransparency = 0
moneyFrame.BorderSizePixel = 0
for _, c in ipairs(moneyFrame:GetChildren()) do
	if c:IsA("UICorner") then c:Destroy() end -- o Studio já tinha um UICorner; troca pelo raio novo
end
cantosR(moneyFrame, 12)
contornoR(moneyFrame, COR_BORDA, 1, 0.15)

-- selo "$" à esquerda — mesmo truque visual do "Legenda"/badge que as
-- outras telas do Lobby usam pra dar um ponto de cor sólida antes do
-- texto, em vez de tudo plano.
local selo = Instance.new("Frame")
selo.Name = "MoneyIcon"
selo.Size = UDim2.fromOffset(30, 30)
selo.Position = UDim2.fromOffset(8, 8)
selo.BackgroundColor3 = COR_OK
selo.BackgroundTransparency = 0
selo.ZIndex = 2
selo.Parent = moneyFrame
cantosR(selo, 8)

local seloTexto = Instance.new("TextLabel")
seloTexto.Name = "Cifrao"
seloTexto.Size = UDim2.fromScale(1, 1)
seloTexto.BackgroundTransparency = 1
seloTexto.Text = "$"
seloTexto.Font = Enum.Font.GothamBlack
seloTexto.TextSize = 18
seloTexto.TextColor3 = Color3.fromRGB(10, 15, 12)
seloTexto.ZIndex = 3
seloTexto.Parent = selo

moneyLabel.Position = UDim2.fromOffset(48, 0)
moneyLabel.Size = UDim2.new(1, -58, 1, 0)
moneyLabel.AnchorPoint = Vector2.new(0, 0)
moneyLabel.BackgroundTransparency = 1
moneyLabel.Font = Enum.Font.GothamBlack
moneyLabel.TextSize = 18
moneyLabel.TextColor3 = COR_TEXTO
moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
moneyLabel.TextYAlignment = Enum.TextYAlignment.Center
moneyLabel.ZIndex = 2

local eventsFolder = ReplicatedStorage:WaitForChild("MoneyEvents", 10)
if not eventsFolder then
	warn("MoneyDisplayClient: MoneyEvents não encontrado em ReplicatedStorage!")
	moneyLabel.Text = "$ ERROR"
	return
end

local updateMoneyEvent = eventsFolder:WaitForChild("UpdateMoney", 10)
local getMoneyFunc = eventsFolder:WaitForChild("GetMoney", 10)
if not updateMoneyEvent or not getMoneyFunc then
	warn("MoneyDisplayClient: eventos de dinheiro não encontrados!")
	moneyLabel.Text = "$ ERROR"
	return
end

local currentMoney = 0
local previousMoney = 0

local function formatMoney(amount)
	local formatted = tostring(amount)
	local k
	repeat
		formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1,%2")
	until k == 0
	return "$ " .. formatted
end

local function updateDisplay(newMoney, animated)
	previousMoney = currentMoney
	currentMoney = newMoney
	-- ⚠️ v79: sem o "$ " aqui — o selo dedicado (MoneyIcon) já mostra o "$",
	-- então o texto mostra só o número (formatMoney continua devolvendo
	-- "$ 1.000" porque o resto do arquivo, tipo o changeLabel, ainda usa
	-- o :sub(3) pra cortar o mesmo jeito).
	moneyLabel.Text = formatMoney(currentMoney):sub(3)

	if animated and UPDATE_ANIMATION then
		local difference = currentMoney - previousMoney
		if difference ~= 0 then
			if SHOW_PLUS_MINUS then
				local changeLabel = Instance.new("TextLabel")
				changeLabel.Size = UDim2.new(1, 0, 0.5, 0)
				changeLabel.Position = UDim2.new(0, 0, 1, 0)
				changeLabel.BackgroundTransparency = 1
				changeLabel.TextScaled = true
				changeLabel.Font = Enum.Font.GothamBold
				changeLabel.TextTransparency = 0

				if difference > 0 then
					changeLabel.Text = "+ " .. formatMoney(difference):sub(3)
					changeLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
				else
					changeLabel.Text = "- " .. formatMoney(math.abs(difference)):sub(3)
					changeLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
				end

				changeLabel.Parent = moneyFrame

				local tween = TweenService:Create(changeLabel, TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Position = UDim2.new(0, 0, 0.5, 0),
					TextTransparency = 1,
				})
				tween:Play()
				tween.Completed:Connect(function()
					changeLabel:Destroy()
				end)
			end

			if FLASH_COLOR_ON_CHANGE then
				local originalColor = moneyLabel.TextColor3
				local flashColor = difference > 0 and Color3.fromRGB(85, 255, 127) or Color3.fromRGB(255, 85, 85)

				local tweenInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local colorTween1 = TweenService:Create(moneyLabel, tweenInfo, { TextColor3 = flashColor })
				local colorTween2 = TweenService:Create(moneyLabel, tweenInfo, { TextColor3 = originalColor })
				colorTween1:Play()
				colorTween1.Completed:Connect(function()
					colorTween2:Play()
				end)
			end
		end
	end
end

task.spawn(function()
	repeat
		task.wait()
	until player.Character

	local money = player:WaitForChild("Money", 10)
	if money then
		currentMoney = money.Value
		updateDisplay(currentMoney, false)

		money.Changed:Connect(function(newValue)
			updateDisplay(newValue, true)
		end)

		print("✅ Money Display inicializado: " .. formatMoney(currentMoney))
	else
		local ok, result = pcall(function()
			return getMoneyFunc:InvokeServer()
		end)
		if ok and result then
			currentMoney = result
			updateDisplay(currentMoney, false)
			print("✅ Money Display inicializado (via RemoteFunction): " .. formatMoney(currentMoney))
		else
			warn("❌ Não foi possível carregar dinheiro inicial!")
			moneyLabel.Text = "$ ???"
		end
	end
end)

updateMoneyEvent.OnClientEvent:Connect(function(newMoney)
	updateDisplay(newMoney, true)
end)

-- Backup: se o valor divergir por algum motivo, resincroniza sozinho.
task.spawn(function()
	while task.wait(5) do
		local money = player:FindFirstChild("Money")
		if money and money.Value ~= currentMoney then
			updateDisplay(money.Value, false)
		end
	end
end)

print("✅ MoneyDisplayClient carregado.")
