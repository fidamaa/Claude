--[[
	TutorialClient — ⚠️ v104

	O painel do tutorial (ver TutorialServer): passo atual, texto curto, as
	teclas desenhadas como "teclas" de verdade, barra de progresso, um
	marcador no mundo (atravessa parede) quando o passo tem destino, e o
	"FEITO!" quando o jogador conclui. Botão ENTENDI nos passos só de leitura
	e "PULAR TUTORIAL" sempre. Paleta do lobby, sem emoji.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PAINEL      = Color3.fromRGB(13, 15, 22)
local CARTAO      = Color3.fromRGB(21, 24, 34)
local CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local BORDA       = Color3.fromRGB(34, 38, 52)
local ACENTO      = Color3.fromRGB(76, 156, 255)
local LEGENDA     = Color3.fromRGB(125, 185, 255)
local OK          = Color3.fromRGB(64, 196, 122)
local TEXTO       = Color3.fromRGB(238, 241, 248)
local TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)
local TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local function cantos(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i end
local function contorno(i, cor, e, t)
	local s = Instance.new("UIStroke"); s.Color = cor; s.Thickness = e or 1; s.Transparency = t or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = i; return s
end
local function rotulo(pai, txt, tam, cor, fonte)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Text = txt; t.TextSize = tam; t.TextColor3 = cor
	t.Font = fonte or Enum.Font.GothamMedium; t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Top; t.TextWrapped = true; t.Parent = pai
	return t
end

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 40
gui.Enabled = false
gui.Parent = playerGui

local painel = Instance.new("Frame")
painel.AnchorPoint = Vector2.new(0, 0.5)
painel.Position = UDim2.new(0, 24, 0.5, 0)
painel.Size = UDim2.fromOffset(380, 250)
painel.BackgroundColor3 = PAINEL
painel.BackgroundTransparency = 0.04
painel.Parent = gui
cantos(painel, 14)
local stroke = contorno(painel, BORDA, 1)
local escala = Instance.new("UIScale")
escala.Parent = painel
local function ajustarEscala()
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	escala.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720) * 1.05, 0.7, 1.2)
end
ajustarEscala()

local faixa = Instance.new("Frame")
faixa.Size = UDim2.new(0, 4, 1, -28)
faixa.Position = UDim2.fromOffset(0, 14)
faixa.BackgroundColor3 = ACENTO
faixa.BorderSizePixel = 0
faixa.Parent = painel

local legenda = rotulo(painel, "TUTORIAL", 12, LEGENDA, Enum.Font.GothamBold)
legenda.Position = UDim2.fromOffset(22, 16); legenda.Size = UDim2.new(1, -44, 0, 14)

local barras = Instance.new("Frame")
barras.Position = UDim2.fromOffset(22, 36); barras.Size = UDim2.new(1, -44, 0, 4)
barras.BackgroundTransparency = 1; barras.Parent = painel
local barrasLayout = Instance.new("UIListLayout")
barrasLayout.FillDirection = Enum.FillDirection.Horizontal
barrasLayout.Padding = UDim.new(0, 4)
barrasLayout.Parent = barras

local titulo = rotulo(painel, "", 26, TEXTO, Enum.Font.GothamBlack)
titulo.Position = UDim2.fromOffset(22, 50); titulo.Size = UDim2.new(1, -44, 0, 30)

local texto = rotulo(painel, "", 15, TEXTO_MEDIO)
texto.Position = UDim2.fromOffset(22, 86); texto.Size = UDim2.new(1, -44, 0, 80)

local teclas = Instance.new("Frame")
teclas.Position = UDim2.new(0, 22, 1, -76); teclas.Size = UDim2.new(1, -44, 0, 34)
teclas.BackgroundTransparency = 1; teclas.Parent = painel
local teclasLayout = Instance.new("UIListLayout")
teclasLayout.FillDirection = Enum.FillDirection.Horizontal
teclasLayout.VerticalAlignment = Enum.VerticalAlignment.Center
teclasLayout.Padding = UDim.new(0, 6)
teclasLayout.Parent = teclas

local botao = Instance.new("TextButton")
botao.AnchorPoint = Vector2.new(1, 0)
botao.Position = UDim2.new(1, -22, 1, -76); botao.Size = UDim2.fromOffset(110, 34)
botao.BackgroundColor3 = ACENTO; botao.Text = "ENTENDI"; botao.TextColor3 = Color3.new(1, 1, 1)
botao.Font = Enum.Font.GothamBlack; botao.TextSize = 14; botao.AutoButtonColor = true
botao.Visible = false; botao.Parent = painel
cantos(botao, 8)
botao.MouseButton1Click:Connect(function()
	botao.Visible = false
	Remotes.TutorialAcao:FireServer("continuar")
end)

local pular = Instance.new("TextButton")
pular.Position = UDim2.new(0, 22, 1, -30); pular.Size = UDim2.fromOffset(140, 18)
pular.BackgroundTransparency = 1; pular.Text = "PULAR TUTORIAL"; pular.TextColor3 = TEXTO_FRACO
pular.Font = Enum.Font.GothamBold; pular.TextSize = 11; pular.TextXAlignment = Enum.TextXAlignment.Left
pular.Parent = painel
pular.MouseButton1Click:Connect(function() Remotes.TutorialAcao:FireServer("pular") end)

local feito = Instance.new("TextLabel")
feito.AnchorPoint = Vector2.new(1, 0)
feito.Position = UDim2.new(1, -22, 0, 52); feito.Size = UDim2.fromOffset(90, 26)
feito.BackgroundColor3 = OK; feito.Text = "FEITO!"; feito.TextColor3 = PAINEL
feito.Font = Enum.Font.GothamBlack; feito.TextSize = 14; feito.Visible = false
feito.Parent = painel
cantos(feito, 13)

local function tecla(txt)
	local largura = math.max(34, #txt * 9 + 18)
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromOffset(largura, 32)
	if txt == "+" then
		t.BackgroundTransparency = 1; t.TextColor3 = TEXTO_FRACO; t.Size = UDim2.fromOffset(14, 32)
	else
		t.BackgroundColor3 = CARTAO_ALT; t.TextColor3 = TEXTO
	end
	t.Text = txt; t.Font = Enum.Font.GothamBlack; t.TextSize = #txt > 3 and 11 or 15
	t.Parent = teclas
	if txt ~= "+" then
		cantos(t, 7)
		contorno(t, BORDA, 1)
		local sombra = Instance.new("Frame") -- "base" da tecla
		sombra.Size = UDim2.new(1, 0, 0, 3); sombra.Position = UDim2.new(0, 0, 1, -3)
		sombra.BackgroundColor3 = BORDA; sombra.BorderSizePixel = 0; sombra.Parent = t
	end
end

-- ===== marcador no mundo =====
local ancora = Instance.new("Part")
ancora.Name = "TutorialAlvo"
ancora.Anchored = true; ancora.CanCollide = false; ancora.CanQuery = false; ancora.CanTouch = false
ancora.Size = Vector3.new(0.2, 0.2, 0.2); ancora.Transparency = 1
local aro = Instance.new("Part")
aro.Name = "TutorialAro"
aro.Anchored = true; aro.CanCollide = false; aro.CanQuery = false; aro.CanTouch = false
aro.Shape = Enum.PartType.Cylinder; aro.Material = Enum.Material.Neon; aro.Color = OK
aro.Transparency = 0.45; aro.Size = Vector3.new(0.15, 9, 9)
local bb = Instance.new("BillboardGui")
bb.Size = UDim2.fromOffset(120, 40); bb.AlwaysOnTop = true; bb.LightInfluence = 0
bb.StudsOffset = Vector3.new(0, 5, 0); bb.Adornee = ancora; bb.Parent = ancora
local bbTxt = Instance.new("TextLabel")
bbTxt.Size = UDim2.fromScale(1, 1); bbTxt.BackgroundColor3 = OK; bbTxt.Text = "AQUI"
bbTxt.TextColor3 = PAINEL; bbTxt.Font = Enum.Font.GothamBlack; bbTxt.TextSize = 18; bbTxt.Parent = bb
cantos(bbTxt, 10)

local alvoAtual = nil
local function mostrarMarcador(pos)
	alvoAtual = pos
	if typeof(pos) == "Vector3" then
		ancora.Position = pos
		aro.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
		ancora.Parent = workspace
		aro.Parent = workspace
	else
		ancora.Parent = nil
		aro.Parent = nil
	end
end

local t = 0
RunService.RenderStepped:Connect(function(dt)
	if not alvoAtual then return end
	t += dt
	local s = 8 + math.sin(t * 4) * 1.2
	aro.Size = Vector3.new(0.15, s, s)
	aro.Transparency = 0.4 + 0.2 * (0.5 + 0.5 * math.sin(t * 4))
end)

-- ===== eventos =====
local function montarBarras(indice, total)
	for _, f in ipairs(barras:GetChildren()) do if f:IsA("Frame") then f:Destroy() end end
	for i = 1, total do
		local b = Instance.new("Frame")
		b.Size = UDim2.new(1 / total, -4, 1, 0)
		b.BackgroundColor3 = i < indice and OK or (i == indice and ACENTO or CARTAO_ALT)
		b.BorderSizePixel = 0
		b.Parent = barras
		cantos(b, 2)
	end
end

Remotes.TutorialPasso.OnClientEvent:Connect(function(info)
	if typeof(info) ~= "table" then return end
	gui.Enabled = true
	if info.Fim then
		mostrarMarcador(nil)
		legenda.Text = "TUTORIAL"
		titulo.Text = "PRONTO!"
		texto.Text = "Você já sabe o básico. Voltando pro Lobby — agora é procurar partida."
		for _, c in ipairs(teclas:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
		botao.Visible = false
		feito.Visible = false
		stroke.Color = OK
		faixa.BackgroundColor3 = OK
		return
	end
	if info.Feito then
		feito.Visible = true
		feito.Size = UDim2.fromOffset(60, 20)
		TweenService:Create(feito, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(90, 26) }):Play()
		stroke.Color = OK
		faixa.BackgroundColor3 = OK
		montarBarras(info.Feito + 1, info.Total or 8)
		mostrarMarcador(nil)
		return
	end

	feito.Visible = false
	stroke.Color = BORDA
	faixa.BackgroundColor3 = ACENTO
	legenda.Text = ("TUTORIAL  ·  PASSO %d DE %d"):format(info.Indice or 1, info.Total or 1)
	titulo.Text = info.Titulo or ""
	texto.Text = info.Texto or ""
	montarBarras(info.Indice or 1, info.Total or 1)
	for _, c in ipairs(teclas:GetChildren()) do if c:IsA("TextLabel") then c:Destroy() end end
	for _, k in ipairs(info.Teclas or {}) do tecla(k) end
	botao.Visible = info.Botao ~= nil
	if info.Botao then botao.Text = info.Botao end
	mostrarMarcador(info.Marcador)

	painel.Position = UDim2.new(0, -20, 0.5, 0)
	TweenService:Create(painel, TweenInfo.new(0.3, Enum.EasingStyle.Quint), { Position = UDim2.new(0, 24, 0.5, 0) }):Play()
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end
