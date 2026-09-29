--[[
	TutorialOfertaClient — ⚠️ v104

	A pergunta da primeira entrada: "quer fazer o tutorial?" (ver
	TutorialLobbyServer). Duas escolhas grandes, sem pegadinha — FAZER
	TUTORIAL (vai pra uma partida de treino guiada) ou AGORA NÃO.
	Paleta do lobby (skill ui-lobby), sem emoji.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
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

local function cantos(i, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r); c.Parent = i end
local function rotulo(pai, txt, tam, cor, fonte, alinh)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.Text = txt; t.TextSize = tam; t.TextColor3 = cor
	t.Font = fonte or Enum.Font.GothamMedium; t.TextWrapped = true
	t.TextXAlignment = alinh or Enum.TextXAlignment.Left; t.TextYAlignment = Enum.TextYAlignment.Top
	t.Parent = pai
	return t
end

local gui = Instance.new("ScreenGui")
gui.Name = "TutorialOfertaGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 90
gui.Enabled = false
gui.Parent = playerGui

local fundo = Instance.new("Frame")
fundo.Size = UDim2.fromScale(1, 1)
fundo.BackgroundColor3 = Color3.new(0, 0, 0)
fundo.BackgroundTransparency = 0.35
fundo.Parent = gui

local cartao = Instance.new("CanvasGroup")
cartao.AnchorPoint = Vector2.new(0.5, 0.5)
cartao.Position = UDim2.fromScale(0.5, 0.5)
cartao.Size = UDim2.fromOffset(520, 330)
cartao.BackgroundColor3 = PAINEL
cartao.Parent = fundo
cantos(cartao, 16)
local s = Instance.new("UIStroke"); s.Color = BORDA; s.Parent = cartao
local escala = Instance.new("UIScale"); escala.Parent = cartao
local function ajustarEscala()
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	escala.Scale = math.clamp(math.min((v.X - 24) / 520, (v.Y - 24) / 330), 0.55, 1.2)
end

local brilho = Instance.new("Frame")
brilho.Size = UDim2.new(1, 0, 0, 140); brilho.BackgroundColor3 = ACENTO; brilho.BorderSizePixel = 0
brilho.Parent = cartao
local g = Instance.new("UIGradient"); g.Rotation = 90; g.Transparency = NumberSequence.new(0.82, 1); g.Parent = brilho

local leg = rotulo(cartao, "BEM-VINDO", 13, LEGENDA, Enum.Font.GothamBold)
leg.Position = UDim2.fromOffset(32, 30); leg.Size = UDim2.new(1, -64, 0, 16)
local tit = rotulo(cartao, "Primeira vez por aqui?", 30, TEXTO, Enum.Font.GothamBlack)
tit.Position = UDim2.fromOffset(32, 50); tit.Size = UDim2.new(1, -64, 0, 36)
local txt = rotulo(cartao, "Faça o tutorial: uma partida de treino guiada que ensina a andar, driblar, dar dash, chutar e dar carrinho. Leva uns 3 minutos e você volta pro Lobby no fim.", 15, TEXTO_MEDIO)
txt.Position = UDim2.fromOffset(32, 96); txt.Size = UDim2.new(1, -64, 0, 80)

local function botao(texto, cor, corTexto, x)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(x, x == 0 and 32 or 6, 1, -96)
	b.Size = UDim2.new(0.5, -38, 0, 60)
	b.BackgroundColor3 = cor; b.Text = texto; b.TextColor3 = corTexto
	b.Font = Enum.Font.GothamBlack; b.TextSize = 18; b.AutoButtonColor = false
	b.Parent = cartao
	cantos(b, 12)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = cor:Lerp(Color3.new(1, 1, 1), 0.1) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = cor end)
	return b
end
local fazer = botao("FAZER TUTORIAL", OK, Color3.new(1, 1, 1), 0)
local pular = botao("AGORA NÃO", CARTAO_ALT, TEXTO_MEDIO, 0.5)
local ps = Instance.new("UIStroke"); ps.Color = BORDA; ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; ps.Parent = pular

local respondeu = false
local function responder(sim)
	if respondeu then return end
	respondeu = true
	Remotes.RespostaTutorial:FireServer(sim)
	if sim then
		fazer.Text = "ENTRANDO..."
		pular.Visible = false
	else
		TweenService:Create(cartao, TweenInfo.new(0.2), { GroupTransparency = 1 }):Play()
		TweenService:Create(fundo, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.delay(0.22, function() gui.Enabled = false end)
	end
end
fazer.MouseButton1Click:Connect(function() responder(true) end)
pular.MouseButton1Click:Connect(function() responder(false) end)

Remotes.OferecerTutorial.OnClientEvent:Connect(function()
	respondeu = false
	ajustarEscala()
	gui.Enabled = true
	cartao.GroupTransparency = 1
	cartao.Position = UDim2.new(0.5, 0, 0.5, 24)
	TweenService:Create(cartao, TweenInfo.new(0.35, Enum.EasingStyle.Quint), { GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5) }):Play()
end)
