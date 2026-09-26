--[[
	MatchmakingClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Tela de matchmaking: aparece quando o servidor avisa (via
	SetMatchmakingScreenOpen) que o jogador entrou na área
	(Config.MATCHMAKING_ZONE_NAME). Deixa escolher modo, convidar gente do
	server pro grupo, ver status da fila e cancelar.

	⚠️ v72 — REDESENHO NA LINGUAGEM DE FILA DE JOGO DE VERDADE.
	PEDIDO: "pesquise no google como funciona esse tipo de HUD, visualize
	referências, e tente fazer de forma semelhante, pra ficar mais simples
	e bonita."

	Referências olhadas (Valorant / Apex / LoL, telas de fila e "match
	found"): fundo quase preto (não cinza-azulado médio), painéis com
	cantos discretos em vez de bem arredondados, avatar CIRCULAR de cada
	jogador numa fileira (não uma lista de texto), UMA cor de destaque só
	usada com parcimônia (não várias cores competindo), tipografia
	condensada em caixa alta pro botão principal, botão de ação grande e
	centralizado, status abaixo dele em texto pequeno e discreto — a tela
	inteira existe pra levar o olho direto pro botão de entrar na fila.

	O que mudou de verdade em relação à v69:
	1) Fundo foi de #171A26 (cinza-azulado) pra #0D0F16 (quase preto) — é
	   a diferença mais perceptível nas referências.
	2) Avatares REAIS do Roblox (GetUserThumbnailAsync, headshot) no lugar
	   de nome em lista — cada membro do grupo agora é um retrato
	   circular, com contorno azul no líder. Cai pra iniciais coloridas se
	   o thumbnail falhar (offline/rate limit), sem travar a tela.
	3) Convidar virou compacto: um "+" que abre um popover pequeno, não
	   uma lista sempre visível ocupando 1/3 da tela — o convite é uma
	   ação ocasional, não devia competir por espaço com o botão principal.
	4) Botão de fila ficou maior, com o texto do modo dentro dele (padrão
	   "FIND MATCH" das referências), cronômetro discreto por baixo.
	5) Paleta reduzida a 1 destaque (o azul) + verde/vermelho só nos dois
	   estados do botão — tirei o dourado do texto de recompensa e o
	   ciano do contorno, que brigavam pela atenção sem necessidade.

	O contrato com o servidor não mudou: mesmos remotos, mesmos argumentos.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== PALETA =====
-- Quase-preto de verdade (era 23,26,38 — ainda lia como "cinza escuro",
-- não como o preto das referências) + UM destaque só.
local COR_FUNDO      = Color3.fromRGB(7, 8, 12)
local COR_PAINEL     = Color3.fromRGB(13, 15, 22)
local COR_CARTAO     = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_HOV = Color3.fromRGB(28, 32, 44)
local COR_BORDA      = Color3.fromRGB(34, 38, 52)
local COR_ACENTO     = Color3.fromRGB(76, 156, 255)
local COR_OK         = Color3.fromRGB(64, 196, 122)
local COR_PERIGO     = Color3.fromRGB(224, 76, 76)
local COR_TEXTO      = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO= Color3.fromRGB(120, 128, 148)

-- ===== ESTADO LOCAL =====
local currentPartyState = { IsLeader = true, Members = { player.Name } }
local selectedModeId = Config.MODE_ORDER[1]
local isQueued = false
local queueStartedAt = 0
local thumbCache = {} -- [userId] = content id (evita pedir o mesmo avatar de novo)

-- ===== HELPERS =====
local function cantos(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end

local function contorno(inst, cor, espessura, transparencia)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = espessura or 1
	s.Transparency = transparencia or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function texto(pai, conteudo, tamanho, cor, fonte)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = conteudo
	t.TextSize = tamanho
	t.TextColor3 = cor
	t.Font = fonte or Enum.Font.GothamMedium
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.Size = UDim2.new(1, 0, 0, tamanho + 6)
	t.Parent = pai
	return t
end

-- Iniciais de um nome, pra usar como fallback do avatar (thumbnail falhou
-- ou ainda não chegou) — nunca deixa um espaço vazio no lugar da pessoa.
local function iniciais(nome)
	return nome:sub(1, 1):upper()
end

local CORES_INICIAL = {
	Color3.fromRGB(230, 96, 96), Color3.fromRGB(96, 170, 230), Color3.fromRGB(96, 200, 140),
	Color3.fromRGB(220, 170, 80), Color3.fromRGB(170, 120, 220), Color3.fromRGB(220, 120, 170),
}
local function corDoNome(nome)
	local soma = 0
	for i = 1, #nome do soma += string.byte(nome, i) end
	return CORES_INICIAL[(soma % #CORES_INICIAL) + 1]
end

-- Avatar circular: pede o headshot real via GetUserThumbnailAsync (pode
-- falhar por rate limit/offline — nesse caso fica só o círculo com a
-- inicial, sem travar nem deixar vazio).
local function avatarCircular(pai, userId, nome, tamanho)
	local aro = Instance.new("Frame")
	aro.Size = UDim2.fromOffset(tamanho, tamanho)
	aro.BackgroundColor3 = corDoNome(nome)
	aro.BorderSizePixel = 0
	aro.ClipsDescendants = true
	aro.Parent = pai
	cantos(aro, tamanho / 2)

	local fallback = texto(aro, iniciais(nome), tamanho * 0.42, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
	fallback.Size = UDim2.new(1, 0, 1, 0)
	fallback.Position = UDim2.new(0, 0, 0, 0)
	fallback.TextXAlignment = Enum.TextXAlignment.Center
	fallback.TextYAlignment = Enum.TextYAlignment.Center

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.new(1, 0, 1, 0)
	img.BackgroundTransparency = 1
	img.ScaleType = Enum.ScaleType.Crop
	img.ImageTransparency = 1 -- só aparece depois de carregar, sem "pop" feio
	img.Parent = aro

	if userId then
		task.spawn(function()
			local content = thumbCache[userId]
			if not content then
				local ok, result = pcall(function()
					local c = Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
					return c
				end)
				if ok then
					content = result
					thumbCache[userId] = content
				end
			end
			if content and img.Parent then
				img.Image = content
				TweenService:Create(img, TweenInfo.new(0.18), { ImageTransparency = 0 }):Play()
				TweenService:Create(fallback, TweenInfo.new(0.18), { TextTransparency = 1 }):Play()
			end
		end)
	end

	return aro
end

-- ===== GUI RAIZ =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchmakingGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local fundo = Instance.new("Frame")
fundo.Name = "Fundo"
fundo.Size = UDim2.new(1, 0, 1, 0)
fundo.BackgroundColor3 = Color3.new(0, 0, 0)
fundo.BackgroundTransparency = 0.35
fundo.BorderSizePixel = 0
fundo.Parent = screenGui

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 420, 0, 0)
mainFrame.AutomaticSize = Enum.AutomaticSize.Y
mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = COR_PAINEL
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
cantos(mainFrame, 10) -- cantos discretos, não bem arredondados (referência)
contorno(mainFrame, COR_BORDA, 1, 0.15)

local escala = Instance.new("UIScale")
escala.Parent = mainFrame

local paddingPrincipal = Instance.new("UIPadding")
paddingPrincipal.PaddingTop = UDim.new(0, 22)
paddingPrincipal.PaddingBottom = UDim.new(0, 22)
paddingPrincipal.PaddingLeft = UDim.new(0, 22)
paddingPrincipal.PaddingRight = UDim.new(0, 22)
paddingPrincipal.Parent = mainFrame

local pilha = Instance.new("UIListLayout")
pilha.FillDirection = Enum.FillDirection.Vertical
pilha.SortOrder = Enum.SortOrder.LayoutOrder
pilha.Padding = UDim.new(0, 16)
pilha.Parent = mainFrame

local function ajustarEscala()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local v = camera.ViewportSize
	if v.X <= 0 or v.Y <= 0 then return end
	local alturaReal = math.max(mainFrame.AbsoluteSize.Y / math.max(escala.Scale, 0.01), 1)
	escala.Scale = math.min(1, (v.X - 32) / 420, (v.Y - 32) / alturaReal)
end

-- ===== CABEÇALHO =====
local headerRow = Instance.new("Frame")
headerRow.LayoutOrder = 1
headerRow.Size = UDim2.new(1, 0, 0, 22)
headerRow.BackgroundTransparency = 1
headerRow.Parent = mainFrame

local barrinha = Instance.new("Frame")
barrinha.Size = UDim2.fromOffset(3, 18)
barrinha.Position = UDim2.new(0, 0, 0.5, -9)
barrinha.BackgroundColor3 = COR_ACENTO
barrinha.BorderSizePixel = 0
barrinha.Parent = headerRow
cantos(barrinha, 2)

local titulo = texto(headerRow, "PARTIDA RÁPIDA", 17, COR_TEXTO, Enum.Font.GothamBlack)
titulo.Position = UDim2.new(0, 12, 0, 0)
titulo.Size = UDim2.new(1, -12, 1, 0)
titulo.TextYAlignment = Enum.TextYAlignment.Center

-- ===== SELEÇÃO DE MODO =====
local modeContainer = Instance.new("Frame")
modeContainer.LayoutOrder = 2
modeContainer.Size = UDim2.new(1, 0, 0, 56)
modeContainer.BackgroundTransparency = 1
modeContainer.Parent = mainFrame

local modeLayout = Instance.new("UIListLayout")
modeLayout.FillDirection = Enum.FillDirection.Horizontal
modeLayout.SortOrder = Enum.SortOrder.LayoutOrder
modeLayout.Padding = UDim.new(0, 6)
modeLayout.Parent = modeContainer

local modeButtons = {}

local function refreshModeButtons()
	for modeId, cartao in pairs(modeButtons) do
		local selecionado = (modeId == selectedModeId)
		cartao.Botao.BackgroundColor3 = selecionado and COR_ACENTO or COR_CARTAO
		cartao.Nome.TextColor3 = selecionado and Color3.new(1, 1, 1) or COR_TEXTO
	end
end

local modeCount = math.max(#Config.MODE_ORDER, 1)
local modeButtonScale = 1 / modeCount

for ordem, modeId in ipairs(Config.MODE_ORDER) do
	local mode = Config.MODES[modeId]

	local botao = Instance.new("TextButton")
	botao.Name = modeId
	botao.LayoutOrder = ordem
	botao.Size = UDim2.new(modeButtonScale, -5, 1, 0)
	botao.BackgroundColor3 = COR_CARTAO
	botao.Text = ""
	botao.AutoButtonColor = false
	botao.Parent = modeContainer
	cantos(botao, 6)

	local nome = texto(botao, mode.DisplayName:upper(), 13, COR_TEXTO, Enum.Font.GothamBold)
	nome.Position = UDim2.new(0, 0, 0, 8)
	nome.Size = UDim2.new(1, 0, 0, 16)
	nome.TextXAlignment = Enum.TextXAlignment.Center

	local descricao = mode.IsFreeRoom and "livre" or ((mode.TotalPlayers or 0) .. " jog.")
	local info = texto(botao, descricao, 10, COR_TEXTO_FRACO)
	info.Position = UDim2.new(0, 0, 0, 28)
	info.Size = UDim2.new(1, 0, 0, 14)
	info.TextXAlignment = Enum.TextXAlignment.Center

	botao.MouseButton1Click:Connect(function()
		if isQueued then return end
		selectedModeId = modeId
		refreshModeButtons()
	end)

	modeButtons[modeId] = { Botao = botao, Nome = nome, Info = info }
end
refreshModeButtons()

-- ===== GRUPO: avatares em fileira + botão de convidar =====
local grupoRow = Instance.new("Frame")
grupoRow.LayoutOrder = 3
grupoRow.Size = UDim2.new(1, 0, 0, 54)
grupoRow.BackgroundTransparency = 1
grupoRow.Parent = mainFrame

local avatarLista = Instance.new("Frame")
avatarLista.Size = UDim2.new(1, -46, 1, 0)
avatarLista.Position = UDim2.new(0, 0, 0, 0)
avatarLista.BackgroundTransparency = 1
avatarLista.Parent = grupoRow

local avatarLayout = Instance.new("UIListLayout")
avatarLayout.FillDirection = Enum.FillDirection.Horizontal
avatarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
avatarLayout.Padding = UDim.new(0, -10) -- se sobrepõem de leve, como nas referências
avatarLayout.SortOrder = Enum.SortOrder.LayoutOrder
avatarLayout.Parent = avatarLista

local function atualizarGrupo(membrosNomes)
	for _, filho in ipairs(avatarLista:GetChildren()) do
		if filho:IsA("Frame") then filho:Destroy() end
	end

	-- currentPartyState só traz nomes — casa cada nome com um Player pra
	-- pegar o UserId de verdade (thumbnail precisa do UserId, não do nome).
	for i, nomeMembro in ipairs(membrosNomes) do
		local alvo = Players:FindFirstChild(nomeMembro)
		local userId = alvo and alvo.UserId

		local slot = Instance.new("Frame")
		slot.LayoutOrder = i
		slot.Size = UDim2.fromOffset(40, 40)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 10 - i
		slot.Parent = avatarLista

		local aro = avatarCircular(slot, userId, nomeMembro, 40)
		aro.ZIndex = slot.ZIndex
		contorno(aro, (i == 1) and COR_ACENTO or COR_PAINEL, i == 1 and 2 or 3)

		if i == 1 then
			local coroa = texto(slot, "★", 12, COR_ACENTO, Enum.Font.GothamBlack)
			coroa.Size = UDim2.fromOffset(14, 14)
			coroa.Position = UDim2.new(1, -12, 1, -12)
			coroa.TextXAlignment = Enum.TextXAlignment.Center
			coroa.ZIndex = slot.ZIndex + 1
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromOffset(14, 14)
			bg.Position = coroa.Position
			bg.BackgroundColor3 = COR_PAINEL
			bg.ZIndex = slot.ZIndex + 1
			bg.Parent = slot
			cantos(bg, 7)
			coroa.Parent = bg
			coroa.Position = UDim2.new(0, 0, 0, 0)
			coroa.Size = UDim2.new(1, 0, 1, 0)
		end
	end
end

atualizarGrupo(currentPartyState.Members)

-- Botão "+" compacto: abre um popover pequeno com quem dá pra convidar,
-- em vez de uma lista sempre visível brigando por espaço com o botão
-- principal (era assim na v69 — grande demais pra uma ação ocasional).
local botaoConvidar = Instance.new("TextButton")
botaoConvidar.Size = UDim2.fromOffset(38, 38)
botaoConvidar.Position = UDim2.new(1, -38, 0.5, -19)
botaoConvidar.BackgroundColor3 = COR_CARTAO
botaoConvidar.Text = "+"
botaoConvidar.TextColor3 = COR_TEXTO_FRACO
botaoConvidar.Font = Enum.Font.GothamBold
botaoConvidar.TextSize = 20
botaoConvidar.AutoButtonColor = false
botaoConvidar.Parent = grupoRow
cantos(botaoConvidar, 19)
contorno(botaoConvidar, COR_BORDA, 1, 0.3)

botaoConvidar.MouseEnter:Connect(function() botaoConvidar.BackgroundColor3 = COR_CARTAO_HOV end)
botaoConvidar.MouseLeave:Connect(function() botaoConvidar.BackgroundColor3 = COR_CARTAO end)

-- ===== POPOVER DE CONVITE =====
local popoverConvite = Instance.new("Frame")
popoverConvite.Visible = false
popoverConvite.Size = UDim2.new(1, 0, 0, 0)
popoverConvite.AutomaticSize = Enum.AutomaticSize.Y
popoverConvite.BackgroundColor3 = COR_CARTAO
popoverConvite.BorderSizePixel = 0
popoverConvite.LayoutOrder = 4
popoverConvite.Parent = mainFrame
cantos(popoverConvite, 8)
contorno(popoverConvite, COR_BORDA, 1, 0.3)

local popoverPadding = Instance.new("UIPadding")
popoverPadding.PaddingTop = UDim.new(0, 8)
popoverPadding.PaddingBottom = UDim.new(0, 8)
popoverPadding.PaddingLeft = UDim.new(0, 8)
popoverPadding.PaddingRight = UDim.new(0, 8)
popoverPadding.Parent = popoverConvite

local popoverLayout = Instance.new("UIListLayout")
popoverLayout.SortOrder = Enum.SortOrder.LayoutOrder
popoverLayout.Padding = UDim.new(0, 4)
popoverLayout.Parent = popoverConvite

local vazioLabel = texto(popoverConvite, "Ninguém mais no servidor agora.", 12, COR_TEXTO_FRACO)
vazioLabel.LayoutOrder = 999
vazioLabel.TextXAlignment = Enum.TextXAlignment.Center
vazioLabel.Size = UDim2.new(1, 0, 0, 26)

local function refreshInviteList()
	for _, filho in ipairs(popoverConvite:GetChildren()) do
		if filho:IsA("TextButton") then filho:Destroy() end
	end

	local algum = false
	for i, outro in ipairs(Players:GetPlayers()) do
		if outro ~= player then
			algum = true

			local botao = Instance.new("TextButton")
			botao.LayoutOrder = i
			botao.Size = UDim2.new(1, 0, 0, 30)
			botao.BackgroundColor3 = COR_PAINEL
			botao.AutoButtonColor = false
			botao.Text = ""
			botao.Parent = popoverConvite
			cantos(botao, 6)

			local avSlot = Instance.new("Frame")
			avSlot.Size = UDim2.fromOffset(22, 22)
			avSlot.Position = UDim2.new(0, 4, 0.5, -11)
			avSlot.BackgroundTransparency = 1
			avSlot.Parent = botao
			avatarCircular(avSlot, outro.UserId, outro.Name, 22)

			local nome = texto(botao, outro.Name, 13, COR_TEXTO)
			nome.Position = UDim2.new(0, 32, 0, 0)
			nome.Size = UDim2.new(1, -90, 1, 0)
			nome.TextYAlignment = Enum.TextYAlignment.Center

			local acao = texto(botao, "CONVIDAR", 11, COR_ACENTO, Enum.Font.GothamBold)
			acao.Position = UDim2.new(1, -70, 0, 0)
			acao.Size = UDim2.new(0, 62, 1, 0)
			acao.TextXAlignment = Enum.TextXAlignment.Right
			acao.TextYAlignment = Enum.TextYAlignment.Center

			botao.MouseButton1Click:Connect(function()
				if isQueued then return end
				Remotes.InviteToParty:FireServer(outro)
				acao.Text = "ENVIADO"
				acao.TextColor3 = COR_OK
				task.delay(2, function()
					if acao.Parent then
						acao.Text = "CONVIDAR"
						acao.TextColor3 = COR_ACENTO
					end
				end)
			end)
		end
	end

	vazioLabel.Visible = not algum
end

local popoverAberto = false
local function fecharPopover()
	popoverAberto = false
	popoverConvite.Visible = false
end
botaoConvidar.MouseButton1Click:Connect(function()
	popoverAberto = not popoverAberto
	popoverConvite.Visible = popoverAberto
	if popoverAberto then refreshInviteList() end
end)

Players.PlayerAdded:Connect(refreshInviteList)
Players.PlayerRemoving:Connect(function()
	task.defer(refreshInviteList)
end)

-- ===== BOTÃO DE FILA — a peça central da tela =====
local queueButton = Instance.new("TextButton")
queueButton.LayoutOrder = 5
queueButton.Size = UDim2.new(1, 0, 0, 56)
queueButton.BackgroundColor3 = COR_OK
queueButton.Text = ""
queueButton.AutoButtonColor = false
queueButton.Parent = mainFrame
cantos(queueButton, 8)

local queueButtonLabel = texto(queueButton, "ENTRAR NA FILA", 18, Color3.new(1, 1, 1), Enum.Font.GothamBlack)
queueButtonLabel.Size = UDim2.new(1, 0, 1, 0)
queueButtonLabel.TextXAlignment = Enum.TextXAlignment.Center
queueButtonLabel.TextYAlignment = Enum.TextYAlignment.Center

local function updateQueueButton()
	queueButton.BackgroundColor3 = isQueued and COR_PERIGO or COR_OK
	if not isQueued then
		queueButtonLabel.Text = "ENTRAR NA FILA"
	end
end

queueButton.MouseEnter:Connect(function()
	queueButton.BackgroundColor3 = (isQueued and COR_PERIGO or COR_OK):Lerp(Color3.new(1, 1, 1), 0.1)
end)
queueButton.MouseLeave:Connect(updateQueueButton)

queueButton.MouseButton1Click:Connect(function()
	fecharPopover()
	if not currentPartyState.IsLeader then return end
	if isQueued then
		Remotes.LeaveQueue:FireServer()
	else
		Remotes.JoinQueue:FireServer(selectedModeId)
	end
end)

-- Status: pequeno e discreto por baixo do botão, do jeito que as
-- referências tratam texto de estado — nunca competindo com a ação.
local statusLabel = texto(mainFrame, "", 12, COR_TEXTO_FRACO, Enum.Font.GothamMedium)
statusLabel.LayoutOrder = 6
statusLabel.TextXAlignment = Enum.TextXAlignment.Center
statusLabel.Size = UDim2.new(1, 0, 0, 16)

RunService.Heartbeat:Connect(function()
	if not (screenGui.Enabled and isQueued) then return end
	local t = math.max(0, os.clock() - queueStartedAt)
	queueButtonLabel.Text = ("CANCELAR · %d:%02d"):format(math.floor(t / 60), math.floor(t % 60))
end)

mainFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(ajustarEscala)

-- ===== EVENTOS DO SERVIDOR =====
Remotes.SetMatchmakingScreenOpen.OnClientEvent:Connect(function(open)
	screenGui.Enabled = open
	if open then
		refreshInviteList()
		ajustarEscala()
		mainFrame.BackgroundTransparency = 1
		TweenService:Create(mainFrame, TweenInfo.new(0.16), { BackgroundTransparency = 0 }):Play()
	else
		fecharPopover()
	end
end)

Remotes.UpdatePartyState.OnClientEvent:Connect(function(state)
	currentPartyState = state
	atualizarGrupo(state.Members)
	queueButton.Visible = state.IsLeader
	if not state.IsLeader then
		statusLabel.Text = "aguardando o líder entrar na fila"
	elseif not isQueued then
		statusLabel.Text = ""
	end
end)

Remotes.UpdateQueueStatus.OnClientEvent:Connect(function(status)
	local entrouAgora = status.InQueue and not isQueued
	isQueued = status.InQueue
	if entrouAgora then queueStartedAt = os.clock() end

	updateQueueButton()
	for modeId, cartao in pairs(modeButtons) do
		cartao.Botao.Active = not isQueued
		local emCinza = isQueued and modeId ~= selectedModeId
		cartao.Nome.TextTransparency = emCinza and 0.6 or 0
		cartao.Info.TextTransparency = emCinza and 0.6 or 0
	end

	if isQueued then
		local mode = Config.MODES[status.ModeId]
		statusLabel.Text = "procurando " .. (mode and mode.DisplayName:lower() or status.ModeId)
	else
		statusLabel.Text = ""
	end
end)

Remotes.MatchFound.OnClientEvent:Connect(function(modeId)
	local mode = Config.MODES[modeId]
	queueButtonLabel.Text = "PARTIDA ENCONTRADA"
	queueButton.BackgroundColor3 = COR_ACENTO
	statusLabel.Text = "teleportando..."
	statusLabel.TextColor3 = COR_ACENTO
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

refreshInviteList()
ajustarEscala()
print("✅ MatchmakingClient carregado.")
