--[[
	CodeRedeemClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	VERSÃO PROVISÓRIA 100% SCRIPTADA — o GUI antigo ("Codes" > plac > code /
	confirm > botas), feito manualmente no Studio, continuava sem funcionar
	mesmo depois de corrigir os nomes no script anterior. Como só SCRIPT
	sincroniza (Instance de GUI feita à mão no Explorer não sincroniza),
	a solução definitiva é este script criar o GUI inteiro sozinho com
	Instance.new — assim não depende de nada que exista hoje no PlayerGui.

	Se ainda existir uma ScreenGui antiga chamada "Codes" feita no Studio,
	pode deletar ela (ou deixar, esse script não mexe nela — só cria a
	própria, com outro nome, "CodeRedeemGUI_Provisorio").

	O que isso cria:
		- Um botãozinho fixo no canto ("Códigos") que abre/fecha o painel.
		- Um painel com TextBox pra digitar o código e um botão Confirmar.
		- Feedback via StarterGui SendNotification (mesmo esquema de antes).

	Usa o mesmo RemoteFunction do servidor (ReplicatedStorage.CodeEvents.
	RedeemCode), que já existe e já funciona — CodeRedeemServer.legacy.luau
	não precisa de nenhuma mudança.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local codeEvents = ReplicatedStorage:WaitForChild("CodeEvents", 10)
if not codeEvents then
	warn("CodeRedeemClient: CodeEvents não encontrado em ReplicatedStorage.")
	return
end

local redeemCodeRemote = codeEvents:WaitForChild("RedeemCode", 10)
if not redeemCodeRemote then
	warn("CodeRedeemClient: RedeemCode RemoteFunction não encontrado.")
	return
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Código",
			Text = text,
			Duration = 3,
		})
	end)
end

-- ==========================================================
-- Construção do GUI (tudo via Instance.new — não depende de
-- nenhum objeto feito no Studio)
-- ==========================================================

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CodeRedeemGUI_Provisorio"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- Botão que abre/fecha o painel
local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.Size = UDim2.new(0, 110, 0, 36)
toggleButton.Position = UDim2.new(1, -125, 1, -55)
toggleButton.AnchorPoint = Vector2.new(0, 0)
toggleButton.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
toggleButton.BorderSizePixel = 0
toggleButton.Text = "Códigos"
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 16
toggleButton.ZIndex = 10
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 8)
toggleCorner.Parent = toggleButton

local toggleStroke = Instance.new("UIStroke")
toggleStroke.Color = Color3.fromRGB(90, 90, 110)
toggleStroke.Thickness = 1.5
toggleStroke.Parent = toggleButton

-- Painel principal (começa escondido)
-- ⚠️ v4: PEDIDO — "não coloque aquela caixinha pra marcar, só coloque um
-- texto de exigência que PRECISA estar no grupo e favoritado, e faça um
-- código identificar isso." Removido o checkbox de auto-confirmação (só
-- um texto de aviso agora) — a exigência de GRUPO é checada DE VERDADE
-- no servidor (player:IsInGroup, ver CodeRedeemServer.legacy.luau); a
-- de FAVORITO não tem NENHUMA API oficial do Roblox pra um jogo checar
-- se um jogador específico favoritou a experiência, então não dá pra
-- verificar essa parte de verdade — o aviso continua no texto por
-- transparência, mas só o grupo é de fato aplicado.
local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 300, 0, 190)
panel.Position = UDim2.new(1, -320, 1, -260)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 32)
panel.BorderSizePixel = 0
panel.Visible = false
panel.ZIndex = 10
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 10)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(90, 90, 110)
panelStroke.Thickness = 1.5
panelStroke.Parent = panel

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -20, 0, 30)
title.Position = UDim2.new(0, 10, 0, 8)
title.BackgroundTransparency = 1
title.Text = "Resgatar Código"
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 10
title.Parent = panel

-- Texto de EXIGÊNCIA (só informativo agora — sem checkbox de
-- auto-confirmação nenhuma). O grupo é validado DE VERDADE no servidor;
-- o favorito não tem como ser validado (Roblox não expõe essa API), mas
-- o aviso continua aqui por transparência com o jogador.
local warningLabel = Instance.new("TextLabel")
warningLabel.Name = "WarningLabel"
warningLabel.Size = UDim2.new(1, -20, 0, 54)
warningLabel.Position = UDim2.new(0, 10, 0, 40)
warningLabel.BackgroundTransparency = 1
warningLabel.Text = "⚠️ EXIGÊNCIA: você PRECISA estar no GRUPO do jogo e ter dado FAVORITE pra conseguir resgatar códigos."
warningLabel.TextColor3 = Color3.fromRGB(255, 200, 90)
warningLabel.Font = Enum.Font.Gotham
warningLabel.TextSize = 13
warningLabel.TextWrapped = true
warningLabel.TextXAlignment = Enum.TextXAlignment.Left
warningLabel.TextYAlignment = Enum.TextYAlignment.Top
warningLabel.ZIndex = 10
warningLabel.Parent = panel

local textbox = Instance.new("TextBox")
textbox.Name = "CodeInput"
textbox.Size = UDim2.new(1, -20, 0, 40)
textbox.Position = UDim2.new(0, 10, 0, 100)
textbox.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
textbox.BorderSizePixel = 0
textbox.PlaceholderText = "Digite o código aqui..."
textbox.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
textbox.Text = ""
textbox.TextColor3 = Color3.fromRGB(255, 255, 255)
textbox.Font = Enum.Font.Gotham
textbox.TextSize = 16
textbox.ClearTextOnFocus = false
textbox.ZIndex = 10
textbox.Parent = panel

local textboxCorner = Instance.new("UICorner")
textboxCorner.CornerRadius = UDim.new(0, 8)
textboxCorner.Parent = textbox

local textboxPadding = Instance.new("UIPadding")
textboxPadding.PaddingLeft = UDim.new(0, 10)
textboxPadding.PaddingRight = UDim.new(0, 10)
textboxPadding.Parent = textbox

local confirmButton = Instance.new("TextButton")
confirmButton.Name = "ConfirmButton"
confirmButton.Size = UDim2.new(1, -20, 0, 40)
confirmButton.Position = UDim2.new(0, 10, 0, 150)
confirmButton.BackgroundColor3 = Color3.fromRGB(70, 160, 90)
confirmButton.BorderSizePixel = 0
confirmButton.Text = "Confirmar"
confirmButton.TextColor3 = Color3.fromRGB(255, 255, 255)
confirmButton.Font = Enum.Font.GothamBold
confirmButton.TextSize = 16
confirmButton.ZIndex = 10
confirmButton.Parent = panel

local confirmCorner = Instance.new("UICorner")
confirmCorner.CornerRadius = UDim.new(0, 8)
confirmCorner.Parent = confirmButton

-- ==========================================================
-- Lógica
-- ==========================================================

local panelOpen = false

local function setPanelOpen(open)
	panelOpen = open
	panel.Visible = open
	if open then
		textbox:CaptureFocus()
	end
end

toggleButton.MouseButton1Click:Connect(function()
	setPanelOpen(not panelOpen)
end)

local isRedeeming = false

local function onConfirmClick()
	if isRedeeming then return end

	local code = textbox.Text:upper():gsub("%s+", "")
	if code == "" then
		notify("Digite um código primeiro.")
		return
	end

	isRedeeming = true
	confirmButton.Text = "..."

	local ok, success, message = pcall(function()
		return redeemCodeRemote:InvokeServer(code)
	end)

	isRedeeming = false
	confirmButton.Text = "Confirmar"

	if ok and success then
		print("✅ Código resgatado:", message)
		notify(message or "Código resgatado!")
		textbox.Text = ""
	else
		local errorMessage = ok and message or tostring(success)
		print("❌ Erro ao resgatar:", errorMessage)
		notify(errorMessage or "Código inválido.")
	end
end

confirmButton.MouseButton1Click:Connect(onConfirmClick)

textbox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		onConfirmClick()
	end
end)

print("✅ CodeRedeemClient (GUI provisório 100% scriptado) carregado.")
