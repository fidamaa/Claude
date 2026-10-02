--[[
	EstatisticasClient (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Lobby)

	⚠️ v115 — PEDIDO: "o Bentes/Pepe Nep sentado no banco da praça vira o NPC de
	ESTATÍSTICAS, com painel de estatísticas e marcador igual Eleven Store /
	missões / perfil / procurar partida."

	Painel scriptado (mesmo esquema do QuestClient: só SCRIPT sincroniza, então
	o GUI inteiro nasce aqui via Instance.new). Aberto pela fala do Bentes:
	DialogueClient chama _G.OpenStats quando o diálogo fecha.

	Dados: ReplicatedStorage.LobbyEvents.GetCareerStats (RemoteFunction do
	PlayerDataManager) -> { Goals, Assists, Tackles, Dribbles, Saves, MVPs,
	Matches, Wins }. As estatísticas de carreira são somadas a cada partida
	pelo LobbyRewardsReceiver (_G.AddCareerStats).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local eventsFolder = ReplicatedStorage:WaitForChild("LobbyEvents", 15)
local getStatsRemote = eventsFolder and eventsFolder:WaitForChild("GetCareerStats", 15)
if not getStatsRemote then
	warn("EstatisticasClient: remote GetCareerStats não encontrado (PlayerDataManager carregou?).")
end

-- ===== PALETA (mesma do resto do Lobby) =====
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(255, 120, 90)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local LARGURA, ALTURA = 480, 470

local function cantos(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end

local function contorno(inst, cor, esp, transp)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = esp or 1
	s.Transparency = transp or 0.2
	s.Parent = inst
	return s
end

-- ===== o que mostrar =====
local CARTOES = {
	{ Chave = "Matches",  Nome = "PARTIDAS",     Cor = Color3.fromRGB(76, 156, 255) },
	{ Chave = "Wins",     Nome = "VITÓRIAS",     Cor = Color3.fromRGB(64, 196, 122) },
	{ Chave = "Goals",    Nome = "GOLS",         Cor = Color3.fromRGB(255, 200, 70) },
	{ Chave = "Assists",  Nome = "ASSISTÊNCIAS", Cor = Color3.fromRGB(170, 120, 255) },
	{ Chave = "Tackles",  Nome = "DESARMES",     Cor = Color3.fromRGB(255, 120, 90) },
	{ Chave = "Dribbles", Nome = "DRIBLES",      Cor = Color3.fromRGB(80, 220, 230) },
	{ Chave = "Saves",    Nome = "DEFESAS",      Cor = Color3.fromRGB(120, 200, 255) },
	{ Chave = "MVPs",     Nome = "MVP",          Cor = Color3.fromRGB(255, 170, 50) },
}

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "EstatisticasGUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.4
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.ZIndex = 9
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(LARGURA, ALTURA)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.BackgroundColor3 = COR_PAINEL
panel.BorderSizePixel = 0
panel.ZIndex = 10
panel.Parent = screenGui
cantos(panel, 10)
contorno(panel, COR_BORDA, 1, 0.15)

local escala = Instance.new("UIScale")
escala.Parent = panel
local function ajustarEscala()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local v = camera.ViewportSize
	if v.X <= 0 or v.Y <= 0 then return end
	escala.Scale = math.min(1, (v.X - 32) / LARGURA, (v.Y - 32) / ALTURA)
end
ajustarEscala()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- cabeçalho
local barrinha = Instance.new("Frame")
barrinha.Size = UDim2.fromOffset(3, 20)
barrinha.Position = UDim2.new(0, 18, 0, 20)
barrinha.BackgroundColor3 = COR_ACENTO
barrinha.BorderSizePixel = 0
barrinha.ZIndex = 10
barrinha.Parent = panel
cantos(barrinha, 2)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.new(1, -120, 0, 22)
titulo.Position = UDim2.new(0, 30, 0, 14)
titulo.BackgroundTransparency = 1
titulo.Text = "ESTATÍSTICAS"
titulo.TextColor3 = COR_TEXTO
titulo.Font = Enum.Font.GothamBlack
titulo.TextSize = 19
titulo.TextXAlignment = Enum.TextXAlignment.Left
titulo.ZIndex = 10
titulo.Parent = panel

local subtitulo = Instance.new("TextLabel")
subtitulo.Size = UDim2.new(1, -120, 0, 16)
subtitulo.Position = UDim2.new(0, 30, 0, 36)
subtitulo.BackgroundTransparency = 1
subtitulo.Text = "sua carreira em campo — anotado pelo Bentes"
subtitulo.TextColor3 = COR_TEXTO_FRACO
subtitulo.Font = Enum.Font.GothamMedium
subtitulo.TextSize = 12
subtitulo.TextXAlignment = Enum.TextXAlignment.Left
subtitulo.ZIndex = 10
subtitulo.Parent = panel

local fechar = Instance.new("TextButton")
fechar.Name = "CloseButton"
fechar.Size = UDim2.fromOffset(32, 32)
fechar.Position = UDim2.new(1, -44, 0, 12)
fechar.BackgroundColor3 = COR_CARTAO_ALT
fechar.BorderSizePixel = 0
fechar.Text = "X"
fechar.TextColor3 = COR_TEXTO
fechar.Font = Enum.Font.GothamBold
fechar.TextSize = 15
fechar.ZIndex = 10
fechar.Parent = panel
cantos(fechar, 16)

local divisor = Instance.new("Frame")
divisor.Size = UDim2.new(1, -36, 0, 1)
divisor.Position = UDim2.new(0, 18, 0, 62)
divisor.BackgroundColor3 = COR_BORDA
divisor.BorderSizePixel = 0
divisor.ZIndex = 10
divisor.Parent = panel

-- grade de cartões (2 colunas)
local grade = Instance.new("Frame")
grade.Size = UDim2.new(1, -36, 0, 4 * 62 + 3 * 10)
grade.Position = UDim2.new(0, 18, 0, 76)
grade.BackgroundTransparency = 1
grade.ZIndex = 10
grade.Parent = panel

local numeros = {} -- [Chave] = TextLabel
for i, c in ipairs(CARTOES) do
	local col = (i - 1) % 2
	local lin = math.floor((i - 1) / 2)
	local cartao = Instance.new("Frame")
	cartao.Size = UDim2.new(0.5, -5, 0, 62)
	cartao.Position = UDim2.new(col * 0.5, col * 5, 0, lin * 72)
	cartao.BackgroundColor3 = COR_CARTAO
	cartao.BorderSizePixel = 0
	cartao.ZIndex = 10
	cartao.Parent = grade
	cantos(cartao, 8)
	contorno(cartao, COR_BORDA, 1, 0.2)

	local faixa = Instance.new("Frame")
	faixa.Size = UDim2.new(0, 4, 1, -16)
	faixa.Position = UDim2.new(0, 8, 0, 8)
	faixa.BackgroundColor3 = c.Cor
	faixa.BorderSizePixel = 0
	faixa.ZIndex = 11
	faixa.Parent = cartao
	cantos(faixa, 2)

	local nome = Instance.new("TextLabel")
	nome.Size = UDim2.new(1, -30, 0, 16)
	nome.Position = UDim2.new(0, 22, 0, 9)
	nome.BackgroundTransparency = 1
	nome.Text = c.Nome
	nome.TextColor3 = COR_TEXTO_FRACO
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 11
	nome.TextXAlignment = Enum.TextXAlignment.Left
	nome.ZIndex = 11
	nome.Parent = cartao

	local valor = Instance.new("TextLabel")
	valor.Size = UDim2.new(1, -30, 0, 28)
	valor.Position = UDim2.new(0, 22, 0, 24)
	valor.BackgroundTransparency = 1
	valor.Text = "0"
	valor.TextColor3 = COR_TEXTO
	valor.Font = Enum.Font.GothamBlack
	valor.TextSize = 24
	valor.TextXAlignment = Enum.TextXAlignment.Left
	valor.ZIndex = 11
	valor.Parent = cartao
	numeros[c.Chave] = valor
end

-- linha de médias
local medias = Instance.new("Frame")
medias.Size = UDim2.new(1, -36, 0, 62)
medias.Position = UDim2.new(0, 18, 0, 76 + 4 * 72 + 2)
medias.BackgroundColor3 = COR_CARTAO_ALT
medias.BorderSizePixel = 0
medias.ZIndex = 10
medias.Parent = panel
cantos(medias, 8)
contorno(medias, COR_ACENTO, 1, 0.55)

local function criarMedia(posX, rotulo)
	local nome = Instance.new("TextLabel")
	nome.Size = UDim2.new(0.5, -10, 0, 16)
	nome.Position = UDim2.new(posX, 12, 0, 9)
	nome.BackgroundTransparency = 1
	nome.Text = rotulo
	nome.TextColor3 = COR_TEXTO_FRACO
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 11
	nome.TextXAlignment = Enum.TextXAlignment.Left
	nome.ZIndex = 11
	nome.Parent = medias
	local valor = Instance.new("TextLabel")
	valor.Size = UDim2.new(0.5, -10, 0, 26)
	valor.Position = UDim2.new(posX, 12, 0, 25)
	valor.BackgroundTransparency = 1
	valor.Text = "--"
	valor.TextColor3 = COR_ACENTO
	valor.Font = Enum.Font.GothamBlack
	valor.TextSize = 22
	valor.TextXAlignment = Enum.TextXAlignment.Left
	valor.ZIndex = 11
	valor.Parent = medias
	return valor
end
local valorTaxa = criarMedia(0, "TAXA DE VITÓRIA")
local valorGolsPartida = criarMedia(0.5, "GOLS POR PARTIDA")

local aviso = Instance.new("TextLabel")
aviso.Size = UDim2.new(1, -36, 0, 18)
aviso.Position = UDim2.new(0, 18, 1, -30)
aviso.BackgroundTransparency = 1
aviso.Text = ""
aviso.TextColor3 = COR_TEXTO_FRACO
aviso.Font = Enum.Font.GothamMedium
aviso.TextSize = 11
aviso.TextXAlignment = Enum.TextXAlignment.Left
aviso.ZIndex = 10
aviso.Parent = panel

-- ===== lógica =====
local aberto = false
local geracao = 0

local function contarAte(label, alvo, geracaoAtual, formato)
	task.spawn(function()
		local dur = 0.7
		local t0 = os.clock()
		while geracaoAtual == geracao do
			local u = math.clamp((os.clock() - t0) / dur, 0, 1)
			local v = alvo * (1 - (1 - u) ^ 3)
			label.Text = formato and formato(v) or tostring(math.floor(v + 0.5))
			if u >= 1 then break end
			RunService.RenderStepped:Wait()
		end
	end)
end

local function preencher(dados)
	geracao += 1
	local g = geracao
	for _, c in ipairs(CARTOES) do
		contarAte(numeros[c.Chave], dados[c.Chave] or 0, g)
	end
	local partidas = dados.Matches or 0
	local vitorias = dados.Wins or 0
	if partidas > 0 then
		contarAte(valorTaxa, math.min(100, vitorias / partidas * 100), g, function(v) return string.format("%d%%", math.floor(v + 0.5)) end)
		contarAte(valorGolsPartida, (dados.Goals or 0) / partidas, g, function(v) return string.format("%.1f", v) end)
		aviso.Text = ""
	else
		valorTaxa.Text = "--"
		valorGolsPartida.Text = "--"
		aviso.Text = "As partidas jogadas daqui pra frente entram na sua carreira."
	end
end

local function fecharPainel()
	if not aberto then return end
	aberto = false
	geracao += 1
	screenGui.Enabled = false
end

local function abrirPainel()
	if aberto then return end
	aberto = true
	for _, c in ipairs(CARTOES) do numeros[c.Chave].Text = "0" end
	valorTaxa.Text = "--"
	valorGolsPartida.Text = "--"
	aviso.Text = "carregando…"
	screenGui.Enabled = true
	panel.Position = UDim2.new(0.5, 0, 0.5, 14)
	TweenService:Create(panel, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0.5, 0) }):Play()

	task.spawn(function()
		local ok, dados = false, nil
		if getStatsRemote then
			ok, dados = pcall(function() return getStatsRemote:InvokeServer() end)
		end
		if not aberto then return end
		if ok and type(dados) == "table" then
			preencher(dados)
		else
			aviso.Text = "não consegui buscar suas estatísticas agora — tenta de novo."
		end
	end)
end

fechar.MouseButton1Click:Connect(fecharPainel)
backdrop.MouseButton1Click:Connect(fecharPainel)
UserInputService.InputBegan:Connect(function(input, processado)
	if aberto and input.KeyCode == Enum.KeyCode.Escape then fecharPainel() end
end)

-- DialogueClient (Action = "OpenStats") chama isso quando a conversa fecha
_G.OpenStats = abrirPainel

print("✅ EstatisticasClient carregado (NPC Bentes).")
