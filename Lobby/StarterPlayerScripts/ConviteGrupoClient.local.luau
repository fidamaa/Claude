--[[
	ConviteGrupoClient — ⚠️ v104

	PEDIDO: "não consigo convidar as pessoas pra party adequadamente, eu clico
	em convidar, mas eles não recebem".

	Causa: nenhum script escutava Remotes.ReceivePartyInvite — a janela de
	aceitar/recusar sumiu quando o MatchmakingClient foi redesenhado. E mesmo
	lá ela não serviria: a tela de matchmaking só fica ligada DENTRO da zona
	da fila, e quem é convidado normalmente está andando pelo lobby.

	Este script tem a própria ScreenGui, sempre ligada, e mostra:
	  • o CONVITE: avatar + nome de quem convidou, ACEITAR / RECUSAR e uma
	    barra com o tempo que falta (Config.PARTY_INVITE_TIMEOUT);
	  • os AVISOS curtos do servidor (Remotes.PartyAviso): "convite enviado",
	    "X recusou", "X entrou no grupo"...
	Visual no padrão do lobby (skill ui-lobby): painel quase preto, 1 acento
	azul, verde/vermelho só nos botões, sem emoji.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_LEGENDA     = Color3.fromRGB(125, 185, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_PERIGO      = Color3.fromRGB(224, 76, 76)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)

local function cantos(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
end

local function contorno(inst, cor, esp, transp)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = esp or 1
	s.Transparency = transp or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function rotulo(pai, txt, tam, cor, fonte)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = txt
	t.TextSize = tam
	t.TextColor3 = cor
	t.Font = fonte or Enum.Font.GothamMedium
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = pai
	return t
end

-- foto = rosto do avatar (rbxthumb não depende de chamada de API, carrega
-- sempre, inclusive no Studio)
local function foto(userId)
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

local gui = Instance.new("ScreenGui")
gui.Name = "ConviteGrupoGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local escala = Instance.new("UIScale")
escala.Parent = gui
local function ajustarEscala()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
	escala.Scale = math.clamp(math.min(v.X / 1280, v.Y / 720) * 1.1, 0.8, 1.2)
end
ajustarEscala()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- ===== CARTÃO DO CONVITE =====
local cartao = Instance.new("CanvasGroup")
cartao.Name = "Convite"
cartao.AnchorPoint = Vector2.new(0.5, 0)
cartao.Position = UDim2.new(0.5, 0, 0, -140)
cartao.Size = UDim2.fromOffset(400, 118)
cartao.BackgroundColor3 = COR_PAINEL
cartao.GroupTransparency = 1
cartao.Visible = false
cartao.Parent = gui
cantos(cartao, 12)
contorno(cartao, COR_BORDA, 1)

local faixa = Instance.new("Frame")
faixa.Size = UDim2.new(0, 4, 1, 0)
faixa.BackgroundColor3 = COR_ACENTO
faixa.BorderSizePixel = 0
faixa.Parent = cartao

local aro = Instance.new("Frame")
aro.Position = UDim2.fromOffset(18, 16)
aro.Size = UDim2.fromOffset(52, 52)
aro.BackgroundColor3 = COR_CARTAO
aro.ClipsDescendants = true
aro.Parent = cartao
cantos(aro, 26)
contorno(aro, COR_ACENTO, 2)
local imgAvatar = Instance.new("ImageLabel")
imgAvatar.Size = UDim2.fromScale(1, 1)
imgAvatar.BackgroundTransparency = 1
imgAvatar.ScaleType = Enum.ScaleType.Crop
imgAvatar.Parent = aro
cantos(imgAvatar, 26)

local legenda = rotulo(cartao, "CONVITE DE GRUPO", 11, COR_LEGENDA, Enum.Font.GothamBold)
legenda.Position = UDim2.fromOffset(84, 16)
legenda.Size = UDim2.new(1, -100, 0, 14)

local nomeLabel = rotulo(cartao, "", 18, COR_TEXTO, Enum.Font.GothamBlack)
nomeLabel.Position = UDim2.fromOffset(84, 32)
nomeLabel.Size = UDim2.new(1, -100, 0, 22)

local subLabel = rotulo(cartao, "quer jogar com você", 13, COR_TEXTO_MEDIO)
subLabel.Position = UDim2.fromOffset(84, 54)
subLabel.Size = UDim2.new(1, -100, 0, 16)

local function botao(txt, cor, x)
	local b = Instance.new("TextButton")
	b.Position = UDim2.new(x, x == 0 and 18 or 5, 0, 76)
	b.Size = UDim2.new(0.5, -23, 0, 32)
	b.BackgroundColor3 = cor
	b.AutoButtonColor = false
	b.Text = txt
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 14
	b.Parent = cartao
	cantos(b, 8)
	b.MouseEnter:Connect(function() b.BackgroundColor3 = cor:Lerp(Color3.new(1, 1, 1), 0.12) end)
	b.MouseLeave:Connect(function() b.BackgroundColor3 = cor end)
	return b
end
local botaoAceitar = botao("ACEITAR", COR_OK, 0)
local botaoRecusar = botao("RECUSAR", COR_CARTAO, 0.5)
contorno(botaoRecusar, COR_BORDA, 1)
botaoRecusar.TextColor3 = COR_TEXTO_MEDIO

local barraFundo = Instance.new("Frame")
barraFundo.AnchorPoint = Vector2.new(0, 1)
barraFundo.Position = UDim2.new(0, 0, 1, 0)
barraFundo.Size = UDim2.new(1, 0, 0, 3)
barraFundo.BackgroundColor3 = COR_CARTAO
barraFundo.BorderSizePixel = 0
barraFundo.Parent = cartao
local barra = Instance.new("Frame")
barra.Size = UDim2.fromScale(1, 1)
barra.BackgroundColor3 = COR_ACENTO
barra.BorderSizePixel = 0
barra.Parent = barraFundo

local conviteAtual = 0 -- contador: cada convite novo invalida o anterior
local respondido = true

local function esconder()
	respondido = true
	TweenService:Create(cartao, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Position = UDim2.new(0.5, 0, 0, -140), GroupTransparency = 1,
	}):Play()
	local meu = conviteAtual
	task.delay(0.2, function()
		if meu == conviteAtual and respondido then cartao.Visible = false end
	end)
end

local function responder(aceito)
	if respondido then return end
	respondido = true
	Remotes.RespondToPartyInvite:FireServer(aceito)
	esconder()
end

botaoAceitar.MouseButton1Click:Connect(function() responder(true) end)
botaoRecusar.MouseButton1Click:Connect(function() responder(false) end)

Remotes.ReceivePartyInvite.OnClientEvent:Connect(function(nome, userId, tempo, nomeExibido)
	conviteAtual += 1
	local meu = conviteAtual
	respondido = false
	tempo = tonumber(tempo) or Config.PARTY_INVITE_TIMEOUT or 20

	nomeLabel.Text = tostring(nomeExibido or nome)
	imgAvatar.Image = typeof(userId) == "number" and foto(userId) or ""

	cartao.Visible = true
	cartao.Position = UDim2.new(0.5, 0, 0, -140)
	cartao.GroupTransparency = 1
	TweenService:Create(cartao, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0.5, 0, 0, 72), GroupTransparency = 0,
	}):Play()

	barra.Size = UDim2.fromScale(1, 1)
	TweenService:Create(barra, TweenInfo.new(tempo, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) }):Play()
	task.delay(tempo, function()
		if meu == conviteAtual and not respondido then esconder() end
	end)
end)

-- teclado: Enter aceita, Backspace recusa (só se nenhuma caixa de texto estiver focada)
UserInputService.InputBegan:Connect(function(input)
	if respondido or UserInputService:GetFocusedTextBox() then return end
	if input.KeyCode == Enum.KeyCode.Return then responder(true)
	elseif input.KeyCode == Enum.KeyCode.Backspace then responder(false) end
end)

-- ===== AVISOS CURTOS =====
local pilha = Instance.new("Frame")
pilha.AnchorPoint = Vector2.new(0.5, 0)
pilha.Position = UDim2.new(0.5, 0, 0, 200)
pilha.Size = UDim2.fromOffset(400, 200)
pilha.BackgroundTransparency = 1
pilha.Parent = gui
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = pilha

local ordem = 0
Remotes.PartyAviso.OnClientEvent:Connect(function(txt, tipo)
	ordem += 1
	local cor = (tipo == "ok" and COR_OK) or (tipo == "erro" and COR_PERIGO) or COR_ACENTO
	local aviso = Instance.new("CanvasGroup")
	aviso.LayoutOrder = ordem
	aviso.Size = UDim2.fromOffset(360, 38)
	aviso.BackgroundColor3 = COR_PAINEL
	aviso.GroupTransparency = 1
	aviso.Parent = pilha
	cantos(aviso, 8)
	contorno(aviso, COR_BORDA, 1)
	local ponto = Instance.new("Frame")
	ponto.Position = UDim2.new(0, 14, 0.5, -4)
	ponto.Size = UDim2.fromOffset(8, 8)
	ponto.BackgroundColor3 = cor
	ponto.Parent = aviso
	cantos(ponto, 4)
	local l = rotulo(aviso, tostring(txt), 14, COR_TEXTO, Enum.Font.GothamMedium)
	l.Position = UDim2.fromOffset(32, 0)
	l.Size = UDim2.new(1, -44, 1, 0)
	TweenService:Create(aviso, TweenInfo.new(0.15), { GroupTransparency = 0 }):Play()
	task.delay(3.2, function()
		TweenService:Create(aviso, TweenInfo.new(0.3), { GroupTransparency = 1 }):Play()
		task.wait(0.32)
		aviso:Destroy()
	end)
end)
