--[[
	TelaFinalClient — ⚠️ v104

	PEDIDO: "recompensas no overtime, melhora aquela tela, tá muito genérica,
	faz mais uma tela parecida com o design do lobby. Aquela tela de vitória,
	de recompensa, de MVP... ela precisa aparecer também EMPATE, não está
	aparecendo, tá dando derrota para os dois times que empataram."

	Substitui o resumo antigo do FootballClient (buildSummaryUI). Recebe o
	mesmo Remotes.ShowMatchSummary (dados de MatchController.endMatch):
	MatchResult "win" | "draw" | "lose", MoneyEarned, XPEarned, Stats, Placar,
	TimesOrdem, MeuTime, MVPNome, MVPUserId, SegundosAteLobby.

	Visual = paleta do lobby (skill ui-lobby): painel quase preto, cartões,
	1 acento por estado (verde vitória, ouro empate, vermelho derrota), texto
	claro e grande, sem emoji. Escala com a tela (celular incluso).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- ⚠️ v110: string.upper não põe acento em maiúscula ("Fúria" virava "FúRIA").
-- Converte também as letras acentuadas (UTF-8 à..þ → À..Þ).
local function maiusculas(s)
	s = string.upper(tostring(s))
	return (s:gsub("\195([\160-\190])", function(c)
		local b = string.byte(c)
		if b ~= 183 then return "\195" .. string.char(b - 32) end
	end))
end

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PAINEL      = Color3.fromRGB(13, 15, 22)
local CARTAO      = Color3.fromRGB(21, 24, 34)
local CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local BORDA       = Color3.fromRGB(34, 38, 52)
local LEGENDA     = Color3.fromRGB(125, 185, 255)
local OK          = Color3.fromRGB(64, 196, 122)
local OURO        = Color3.fromRGB(255, 200, 70)
local PERIGO      = Color3.fromRGB(224, 76, 76)
local TEXTO       = Color3.fromRGB(238, 241, 248)
local TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)
local TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local COR_TIME = {
	Azul = Color3.fromRGB(70, 140, 255),
	Amarelo = Color3.fromRGB(255, 205, 60),
}

local RESULTADOS = {
	win  = { Titulo = "VITÓRIA", Sub = "Seu time venceu a partida", Cor = OK },
	draw = { Titulo = "EMPATE",  Sub = "Ninguém saiu na frente",    Cor = OURO },
	lose = { Titulo = "DERROTA", Sub = "Não foi dessa vez",         Cor = PERIGO },
	tutorial = { Titulo = "CONCLUÍDO", Sub = "Tutorial feito — agora é jogar pra valer", Cor = Color3.fromRGB(76, 156, 255) },
}

local function cantos(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end
local function contorno(inst, cor, esp, tr)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = esp or 1
	s.Transparency = tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end
local function rotulo(pai, txt, tam, cor, fonte, alinh)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = txt
	t.TextSize = tam
	t.TextColor3 = cor
	t.Font = fonte or Enum.Font.GothamMedium
	t.TextXAlignment = alinh or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Parent = pai
	return t
end

local gui = Instance.new("ScreenGui")
gui.Name = "TelaFinalGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 80
gui.Enabled = false
gui.Parent = playerGui

local fundo = Instance.new("Frame")
fundo.Size = UDim2.fromScale(1, 1)
fundo.BackgroundColor3 = Color3.new(0, 0, 0)
fundo.BackgroundTransparency = 1
fundo.Parent = gui

local escala = Instance.new("UIScale")
local function ajustarEscala()
	local cam = workspace.CurrentCamera
	local v = cam and cam.ViewportSize or Vector2.new(1280, 720)
	escala.Scale = math.clamp(math.min(v.X / 700, v.Y / 700), 0.55, 1.25)
end

local cartao = Instance.new("CanvasGroup")
cartao.AnchorPoint = Vector2.new(0.5, 0.5)
cartao.Position = UDim2.fromScale(0.5, 0.5)
cartao.Size = UDim2.fromOffset(560, 600)
cartao.BackgroundColor3 = PAINEL
cartao.GroupTransparency = 1
cartao.Parent = fundo
cantos(cartao, 16)
contorno(cartao, BORDA, 1)
escala.Parent = cartao

-- faixa do resultado no topo
local faixa = Instance.new("Frame")
faixa.Size = UDim2.new(1, 0, 0, 6)
faixa.BorderSizePixel = 0
faixa.Parent = cartao

local brilho = Instance.new("Frame")
brilho.Position = UDim2.fromOffset(0, 6)
brilho.Size = UDim2.new(1, 0, 0, 150)
brilho.BorderSizePixel = 0
brilho.Parent = cartao
local grad = Instance.new("UIGradient")
grad.Rotation = 90
grad.Transparency = NumberSequence.new(0.8, 1)
grad.Parent = brilho

local legendaTopo = rotulo(cartao, "FIM DE PARTIDA", 13, LEGENDA, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
legendaTopo.Position = UDim2.fromOffset(0, 26)
legendaTopo.Size = UDim2.new(1, 0, 0, 16)

local titulo = rotulo(cartao, "", 56, TEXTO, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
titulo.Position = UDim2.fromOffset(0, 46)
titulo.Size = UDim2.new(1, 0, 0, 60)

local subtitulo = rotulo(cartao, "", 15, TEXTO_MEDIO, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
subtitulo.Position = UDim2.fromOffset(0, 106)
subtitulo.Size = UDim2.new(1, 0, 0, 20)

-- placar
local placar = Instance.new("Frame")
placar.Position = UDim2.fromOffset(24, 140)
placar.Size = UDim2.new(1, -48, 0, 64)
placar.BackgroundColor3 = CARTAO
placar.Parent = cartao
cantos(placar, 10)

local function ladoTime(alinhar)
	local barra = Instance.new("Frame")
	barra.Size = UDim2.new(0, 4, 1, -20)
	barra.Position = alinhar == "esq" and UDim2.fromOffset(12, 10) or UDim2.new(1, -16, 0, 10)
	barra.BorderSizePixel = 0
	barra.Parent = placar
	local nome = rotulo(placar, "", 18, TEXTO, Enum.Font.GothamBlack,
		alinhar == "esq" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right)
	nome.Position = alinhar == "esq" and UDim2.fromOffset(26, 0) or UDim2.new(0.5, 60, 0, 0)
	nome.Size = UDim2.new(0.5, -86, 1, 0)
	local voce = rotulo(placar, "SEU TIME", 10, LEGENDA, Enum.Font.GothamBold,
		alinhar == "esq" and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right)
	voce.Position = alinhar == "esq" and UDim2.new(0, 26, 1, -18) or UDim2.new(0.5, 60, 1, -18)
	voce.Size = UDim2.new(0.5, -86, 0, 12)
	return barra, nome, voce
end
local barraA, nomeA, voceA = ladoTime("esq")
local barraB, nomeB, voceB = ladoTime("dir")
local golsLabel = rotulo(placar, "0  -  0", 34, TEXTO, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
golsLabel.Position = UDim2.new(0.5, -60, 0, 0)
golsLabel.Size = UDim2.new(0, 120, 1, 0)

-- MVP
local mvpCartao = Instance.new("Frame")
mvpCartao.Position = UDim2.fromOffset(24, 216)
mvpCartao.Size = UDim2.new(1, -48, 0, 70)
mvpCartao.BackgroundColor3 = CARTAO
mvpCartao.Parent = cartao
cantos(mvpCartao, 10)
local mvpStroke = contorno(mvpCartao, OURO, 1, 0.55)

local mvpAro = Instance.new("Frame")
mvpAro.Position = UDim2.fromOffset(12, 11)
mvpAro.Size = UDim2.fromOffset(48, 48)
mvpAro.BackgroundColor3 = CARTAO_ALT
mvpAro.ClipsDescendants = true
mvpAro.Parent = mvpCartao
cantos(mvpAro, 24)
contorno(mvpAro, OURO, 2)
local mvpFoto = Instance.new("ImageLabel")
mvpFoto.Size = UDim2.fromScale(1, 1)
mvpFoto.BackgroundTransparency = 1
mvpFoto.ScaleType = Enum.ScaleType.Crop
mvpFoto.Parent = mvpAro
cantos(mvpFoto, 24)

local mvpChip = Instance.new("TextLabel")
mvpChip.Position = UDim2.fromOffset(74, 14)
mvpChip.Size = UDim2.fromOffset(52, 18)
mvpChip.BackgroundColor3 = OURO
mvpChip.Text = "MVP"
mvpChip.TextColor3 = PAINEL
mvpChip.Font = Enum.Font.GothamBlack
mvpChip.TextSize = 12
mvpChip.Parent = mvpCartao
cantos(mvpChip, 9)
local mvpNome = rotulo(mvpCartao, "", 20, TEXTO, Enum.Font.GothamBlack)
mvpNome.Position = UDim2.fromOffset(74, 34)
mvpNome.Size = UDim2.new(1, -90, 0, 24)
local mvpVoce = rotulo(mvpCartao, "VOCÊ FOI O MELHOR EM CAMPO", 11, OURO, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
mvpVoce.Position = UDim2.new(0, 134, 0, 14)
mvpVoce.Size = UDim2.new(1, -150, 0, 18)

-- recompensas
local function cartaoRecompensa(x, legenda, cor)
	local f = Instance.new("Frame")
	f.Position = UDim2.new(x, x == 0 and 24 or 6, 0, 298)
	f.Size = UDim2.new(0.5, -30, 0, 84)
	f.BackgroundColor3 = CARTAO
	f.Parent = cartao
	cantos(f, 10)
	local acento = Instance.new("Frame")
	acento.Size = UDim2.new(0, 4, 1, -24)
	acento.Position = UDim2.fromOffset(12, 12)
	acento.BackgroundColor3 = cor
	acento.BorderSizePixel = 0
	acento.Parent = f
	local l = rotulo(f, legenda, 12, TEXTO_FRACO, Enum.Font.GothamBold)
	l.Position = UDim2.fromOffset(26, 14)
	l.Size = UDim2.new(1, -36, 0, 14)
	local v = rotulo(f, "0", 32, cor, Enum.Font.GothamBlack)
	v.Position = UDim2.fromOffset(26, 32)
	v.Size = UDim2.new(1, -36, 0, 38)
	return v
end
local dinheiroLabel = cartaoRecompensa(0, "DINHEIRO", OURO)
local xpLabel = cartaoRecompensa(0.5, "EXPERIÊNCIA", LEGENDA)

-- estatísticas
local stats = Instance.new("Frame")
stats.Position = UDim2.fromOffset(24, 394)
stats.Size = UDim2.new(1, -48, 0, 110)
stats.BackgroundTransparency = 1
stats.Parent = cartao
local statsLayout = Instance.new("UIGridLayout")
statsLayout.CellSize = UDim2.new(0.2, -6, 0, 110)
statsLayout.CellPadding = UDim2.fromOffset(7, 0)
statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
statsLayout.Parent = stats

local function stat(ordem, nome)
	local f = Instance.new("Frame")
	f.LayoutOrder = ordem
	f.BackgroundColor3 = CARTAO
	f.Parent = stats
	cantos(f, 10)
	local v = rotulo(f, "0", 34, TEXTO, Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	v.Position = UDim2.fromOffset(0, 22)
	v.Size = UDim2.new(1, 0, 0, 40)
	local n = rotulo(f, nome, 11, TEXTO_FRACO, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
	n.Position = UDim2.fromOffset(0, 70)
	n.Size = UDim2.new(1, 0, 0, 14)
	return v
end
local sGols = stat(1, "GOLS")
local sAssist = stat(2, "ASSIST.")
local sDesarmes = stat(3, "DESARMES")
local sDribles = stat(4, "DRIBLES")
local sDefesas = stat(5, "DEFESAS")

-- rodapé: volta ao lobby
local rodape = rotulo(cartao, "", 14, TEXTO_MEDIO, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
rodape.Position = UDim2.fromOffset(0, 520)
rodape.Size = UDim2.new(1, 0, 0, 20)
local barraFundo = Instance.new("Frame")
barraFundo.Position = UDim2.new(0, 24, 0, 552)
barraFundo.Size = UDim2.new(1, -48, 0, 6)
barraFundo.BackgroundColor3 = CARTAO_ALT
barraFundo.BorderSizePixel = 0
barraFundo.Parent = cartao
cantos(barraFundo, 3)
local barra = Instance.new("Frame")
barra.Size = UDim2.fromScale(0, 1)
barra.BorderSizePixel = 0
barra.Parent = barraFundo
cantos(barra, 3)

local function contarAte(label, alvo, prefixo, sufixo, dur)
	local inicio = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - inicio) / dur, 0, 1)
		local e = 1 - (1 - a) ^ 3
		label.Text = (prefixo or "") .. tostring(math.floor(alvo * e + 0.5)) .. (sufixo or "")
		if a >= 1 then conn:Disconnect() end
	end)
end

local function mostrar(data)
	if typeof(data) ~= "table" then return end
	local res = RESULTADOS[data.MatchResult] or RESULTADOS.lose
	local stats_ = data.Stats or {}

	faixa.BackgroundColor3 = res.Cor
	brilho.BackgroundColor3 = res.Cor
	titulo.Text = res.Titulo
	titulo.TextColor3 = res.Cor
	subtitulo.Text = res.Sub
	barra.BackgroundColor3 = res.Cor

	-- placar
	local ordem = data.TimesOrdem or Config.TEAM_NAMES or { "Azul", "Amarelo" }
	local p = data.Placar or {}
	local a, b = ordem[1], ordem[2]
	nomeA.Text = maiusculas(tostring(a))
	nomeB.Text = maiusculas(tostring(b))
	barraA.BackgroundColor3 = COR_TIME[a] or LEGENDA
	barraB.BackgroundColor3 = COR_TIME[b] or LEGENDA
	voceA.Visible = data.MeuTime == a
	voceB.Visible = data.MeuTime == b
	golsLabel.Text = ("%d  -  %d"):format(p[a] or 0, p[b] or 0)

	-- MVP
	if data.MVPNome then
		mvpCartao.Visible = true
		mvpNome.Text = data.MVPNome
		mvpFoto.Image = typeof(data.MVPUserId) == "number"
			and ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(data.MVPUserId) or ""
		local souEu = (stats_.MVP == true) or data.MVPUserId == player.UserId
		mvpVoce.Visible = souEu
		mvpStroke.Transparency = souEu and 0 or 0.55
	else
		mvpCartao.Visible = true
		mvpNome.Text = "Sem MVP nesta partida"
		mvpFoto.Image = ""
		mvpVoce.Visible = false
		mvpStroke.Transparency = 0.8
	end

	sGols.Text = tostring(stats_.Goals or 0)
	sAssist.Text = tostring(stats_.Assists or 0)
	sDesarmes.Text = tostring(stats_.Tackles or 0)
	sDribles.Text = tostring(stats_.Dribbles or 0)
	sDefesas.Text = tostring(stats_.Saves or 0)

	ajustarEscala()
	gui.Enabled = true
	fundo.BackgroundTransparency = 1
	cartao.GroupTransparency = 1
	cartao.Position = UDim2.new(0.5, 0, 0.5, 30)
	TweenService:Create(fundo, TweenInfo.new(0.35), { BackgroundTransparency = 0.45 }):Play()
	TweenService:Create(cartao, TweenInfo.new(0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5),
	}):Play()

	if data.SemRecompensa then
		-- sala personalizada: sem recompensa (pedido explícito)
		dinheiroLabel.Text = "—"
		xpLabel.Text = data.MatchResult == "tutorial" and "TUTORIAL" or "SALA PERSONALIZADA"
		xpLabel.TextSize = 18
	else
		xpLabel.TextSize = 32
		dinheiroLabel.Text = "+$0"
		xpLabel.Text = "+0 XP"
		task.delay(0.35, function()
			contarAte(dinheiroLabel, tonumber(data.MoneyEarned) or 0, "+$", "", 1.2)
			contarAte(xpLabel, tonumber(data.XPEarned) or 0, "+", " XP", 1.2)
		end)
	end

	local total = tonumber(data.SegundosAteLobby) or Config.SUMMARY_DELAY_BEFORE_TELEPORT or 8
	local inicio = os.clock()
	barra.Size = UDim2.fromScale(0, 1)
	TweenService:Create(barra, TweenInfo.new(total, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
	task.spawn(function()
		while gui.Enabled do
			local falta = math.max(0, math.ceil(total - (os.clock() - inicio)))
			rodape.Text = falta > 0 and ("Voltando ao lobby em %d"):format(falta) or "Voltando ao lobby..."
			task.wait(0.2)
		end
	end)
end

Remotes.ShowMatchSummary.OnClientEvent:Connect(mostrar)
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- teste: _G.TesteTelaFinal("draw")
_G.TesteTelaFinal = function(resultado)
	mostrar({
		MatchResult = resultado or "win", MoneyEarned = 1250, XPEarned = 480,
		Stats = { Goals = 2, Assists = 1, Tackles = 3, Dribbles = 9, Saves = 0, MVP = true },
		Placar = { Azul = 3, Amarelo = 2 }, TimesOrdem = { "Azul", "Amarelo" }, MeuTime = "Azul",
		MVPNome = player.DisplayName, MVPUserId = player.UserId, SegundosAteLobby = 8,
	})
end
