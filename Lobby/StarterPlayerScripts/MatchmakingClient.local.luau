--[[
	MatchmakingClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Tela de partida: aparece quando o servidor avisa (SetMatchmakingScreenOpen)
	que o jogador entrou na área (Config.MATCHMAKING_ZONE_NAME).

	⚠️ v104 — REDESENHO. PEDIDOS:
	  • "melhora a aparência da HUD do matchmaking, tá muito simples";
	  • "embaixo de cada modo (3v3, 5v5, 7v7), quantas pessoas estão
	    procurando partida nesse momento, e embaixo quantas pessoas do seu
	    país (latência igual à sua) — aí o cara prioriza a que tem mais
	    chance de cair com ping melhor" (Remotes.ContagemFila);
	  • "a sala personalizada é só você e a sua party, sem recompensas, com
	    o GK sempre spawnado";
	  • "não entro como GK se não marcar que quero ser GK" — chave "JOGAR DE
	    GOLEIRO" aqui mesmo (Remotes.DefinirGoleiro / EstadoGoleiro);
	  • "a cara do personagem aparece como a foto da party" (rbxthumb).

	Layout: cartões de modo grandes à esquerda (2x2), coluna do grupo à
	direita (fotos, convite, goleiro, botão principal). Paleta do lobby
	(skill ui-lobby), sem emoji, texto claro. Escala sozinha pra caber na
	tela (celular incluso).

	Contrato com o servidor: JoinQueue/LeaveQueue/InviteToParty/LeaveParty
	(cliente -> servidor) e SetMatchmakingScreenOpen/UpdatePartyState/
	UpdateQueueStatus/MatchFound/ContagemFila/EstadoGoleiro (servidor ->
	cliente).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

-- ⚠️ v110: string.upper não põe acento em maiúscula ("Fúria" virava "FúRIA").
-- Converte também as letras acentuadas (UTF-8 à..þ → À..Þ).
local function maiusculas(s)
	s = string.upper(tostring(s))
	return (s:gsub("\195([\160-\190])", function(c)
		local b = string.byte(c)
		if b ~= 183 then return "\195" .. string.char(b - 32) end
	end))
end

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ===== PALETA (skill ui-lobby) =====
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_CARTAO_HOV  = Color3.fromRGB(31, 36, 50)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_LEGENDA     = Color3.fromRGB(125, 185, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_OURO        = Color3.fromRGB(255, 200, 70)
local COR_PERIGO      = Color3.fromRGB(224, 76, 76)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local LARGURA, ALTURA = 860, 520

-- ===== ESTADO =====
local currentPartyState = { IsLeader = true, Members = { player.Name } }
local selectedModeId = Config.MODE_ORDER[2] or Config.MODE_ORDER[1]
local isQueued = false
local queueStartedAt = 0
local minhaRegiao = nil
local contagens = {} -- [modeId] = { Total, Regiao }
local goleiroMarcado, goleiroAutomatico = false, false

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

local function texto(pai, conteudo, tamanho, cor, fonte, alinh)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = conteudo
	t.TextSize = tamanho
	t.TextColor3 = cor
	t.Font = fonte or Enum.Font.GothamMedium
	t.TextXAlignment = alinh or Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.Size = UDim2.new(1, 0, 0, tamanho + 6)
	t.Parent = pai
	return t
end

local function foto(userId)
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
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

-- Avatar circular com o rosto do personagem (rbxthumb não depende de API);
-- a inicial colorida fica por baixo enquanto a foto carrega.
local function avatarCircular(pai, userId, nome, tamanho)
	local aro = Instance.new("Frame")
	aro.Size = UDim2.fromOffset(tamanho, tamanho)
	aro.BackgroundColor3 = corDoNome(nome)
	aro.BorderSizePixel = 0
	aro.ClipsDescendants = true
	aro.Parent = pai
	cantos(aro, tamanho / 2)

	local inicial = texto(aro, nome:sub(1, 1):upper(), tamanho * 0.42, Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
	inicial.Size = UDim2.fromScale(1, 1)

	if userId then
		local img = Instance.new("ImageLabel")
		img.Size = UDim2.fromScale(1, 1)
		img.BackgroundTransparency = 1
		img.ScaleType = Enum.ScaleType.Crop
		img.Image = foto(userId)
		img.Parent = aro
		cantos(img, tamanho / 2)
	end
	return aro
end

local function hover(botao, normal, sobre)
	botao.MouseEnter:Connect(function() if botao.Active then botao.BackgroundColor3 = sobre end end)
	botao.MouseLeave:Connect(function() botao.BackgroundColor3 = normal() end)
end

-- ===== GUI RAIZ =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MatchmakingGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.DisplayOrder = 20
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- foto por cima do círculo, sempre
screenGui.Parent = playerGui

local fundo = Instance.new("Frame")
fundo.Name = "Fundo"
fundo.Size = UDim2.fromScale(1, 1)
fundo.BackgroundColor3 = Color3.new(0, 0, 0)
fundo.BackgroundTransparency = 0.4
fundo.BorderSizePixel = 0
fundo.Parent = screenGui

local mainFrame = Instance.new("CanvasGroup")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.fromOffset(LARGURA, ALTURA)
mainFrame.Position = UDim2.fromScale(0.5, 0.5)
mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
mainFrame.BackgroundColor3 = COR_PAINEL
mainFrame.BorderSizePixel = 0
mainFrame.Parent = screenGui
cantos(mainFrame, 14)
contorno(mainFrame, COR_BORDA, 1)

local escala = Instance.new("UIScale")
escala.Parent = mainFrame

local function ajustarEscala()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local v = camera.ViewportSize
	if v.X <= 0 or v.Y <= 0 then return end
	escala.Scale = math.min(1.15, (v.X - 24) / LARGURA, (v.Y - 24) / ALTURA)
end

-- brilho azul no topo
local brilho = Instance.new("Frame")
brilho.Size = UDim2.new(1, 0, 0, 120)
brilho.BackgroundColor3 = COR_ACENTO
brilho.BorderSizePixel = 0
brilho.Parent = mainFrame
local grad = Instance.new("UIGradient")
grad.Rotation = 90
grad.Transparency = NumberSequence.new(0.88, 1)
grad.Parent = brilho

-- ===== CABEÇALHO =====
local barrinha = Instance.new("Frame")
barrinha.Position = UDim2.fromOffset(28, 26)
barrinha.Size = UDim2.fromOffset(4, 40)
barrinha.BackgroundColor3 = COR_ACENTO
barrinha.BorderSizePixel = 0
barrinha.Parent = mainFrame
cantos(barrinha, 2)

local titulo = texto(mainFrame, "PROCURAR PARTIDA", 26, COR_TEXTO, Enum.Font.GothamBlack)
titulo.Position = UDim2.fromOffset(42, 22)
titulo.Size = UDim2.fromOffset(500, 28)

local subtitulo = texto(mainFrame, "Mais gente da sua região no modo = partida mais rápida e ping melhor", 13, COR_TEXTO_FRACO)
subtitulo.Position = UDim2.fromOffset(42, 50)
subtitulo.Size = UDim2.fromOffset(560, 18)

local chipRegiao = Instance.new("TextLabel")
chipRegiao.AnchorPoint = Vector2.new(1, 0)
chipRegiao.Position = UDim2.new(1, -28, 0, 30)
chipRegiao.Size = UDim2.fromOffset(150, 28)
chipRegiao.BackgroundColor3 = COR_CARTAO
chipRegiao.Text = "SUA REGIÃO  --"
chipRegiao.TextColor3 = COR_LEGENDA
chipRegiao.Font = Enum.Font.GothamBold
chipRegiao.TextSize = 12
chipRegiao.Parent = mainFrame
cantos(chipRegiao, 14)
contorno(chipRegiao, COR_BORDA, 1)

-- ===== CARTÕES DE MODO (esquerda, 2x2) =====
local grade = Instance.new("Frame")
grade.Position = UDim2.fromOffset(28, 92)
grade.Size = UDim2.fromOffset(540, 400)
grade.BackgroundTransparency = 1
grade.Parent = mainFrame
local gradeLayout = Instance.new("UIGridLayout")
gradeLayout.CellSize = UDim2.fromOffset(264, 194)
gradeLayout.CellPadding = UDim2.fromOffset(12, 12)
gradeLayout.SortOrder = Enum.SortOrder.LayoutOrder
gradeLayout.Parent = grade

local modeCards = {}

local function corCartao(modeId)
	if modeId == selectedModeId then return COR_CARTAO_ALT end
	return COR_CARTAO
end

local function refreshModeCards()
	for modeId, c in pairs(modeCards) do
		local sel = modeId == selectedModeId
		c.Botao.BackgroundColor3 = corCartao(modeId)
		c.Stroke.Color = sel and COR_ACENTO or COR_BORDA
		c.Stroke.Thickness = sel and 2 or 1
		c.Check.Visible = sel
		local apagado = isQueued and not sel
		c.Botao.Active = not isQueued
		for _, l in ipairs(c.Textos) do l.TextTransparency = apagado and 0.6 or 0 end
	end
end

local function atualizarContagens()
	for modeId, c in pairs(modeCards) do
		if c.Total then
			local info = contagens[modeId]
			local total = info and info.Total or 0
			local regiao = info and info.Regiao or 0
			c.Total.Text = tostring(total)
			c.Regiao.Text = ("%d na sua região%s"):format(regiao, minhaRegiao and (" (" .. minhaRegiao .. ")") or "")
			c.Ponto.BackgroundColor3 = regiao > 0 and COR_OK or COR_TEXTO_FRACO
		end
	end
	chipRegiao.Text = "SUA REGIÃO  " .. (minhaRegiao or "--")
end

local function tag(pai, txt, cor, x)
	local t = Instance.new("TextLabel")
	t.Position = UDim2.fromOffset(x, 0)
	t.AutomaticSize = Enum.AutomaticSize.X
	t.Size = UDim2.fromOffset(0, 22)
	t.BackgroundColor3 = COR_PAINEL
	t.Text = txt
	t.TextColor3 = cor
	t.Font = Enum.Font.GothamBold
	t.TextSize = 11
	t.Parent = pai
	cantos(t, 11)
	contorno(t, cor, 1, 0.5)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = t
	return t
end

for ordem, modeId in ipairs(Config.MODE_ORDER) do
	local mode = Config.MODES[modeId]
	local botao = Instance.new("TextButton")
	botao.Name = modeId
	botao.LayoutOrder = ordem
	botao.BackgroundColor3 = COR_CARTAO
	botao.Text = ""
	botao.AutoButtonColor = false
	botao.Parent = grade
	cantos(botao, 12)
	local stroke = contorno(botao, COR_BORDA, 1)

	local check = Instance.new("Frame")
	check.AnchorPoint = Vector2.new(1, 0)
	check.Position = UDim2.new(1, -16, 0, 16)
	check.Size = UDim2.fromOffset(14, 14)
	check.BackgroundColor3 = COR_ACENTO
	check.Parent = botao
	cantos(check, 7)
	local checkAro = contorno(check, COR_ACENTO, 3, 0.6)
	checkAro.ApplyStrokeMode = Enum.ApplyStrokeMode.Border

	local textos = {}
	local card = { Botao = botao, Stroke = stroke, Check = check, Textos = textos }

	if mode.IsPrivate or mode.IsFreeRoom then
		local nome = texto(botao, "SALA", 14, COR_LEGENDA, Enum.Font.GothamBold)
		nome.Position = UDim2.fromOffset(20, 18)
		nome.Size = UDim2.new(1, -60, 0, 18)
		local nome2 = texto(botao, "PERSONALIZADA", 26, COR_TEXTO, Enum.Font.GothamBlack)
		nome2.Position = UDim2.fromOffset(20, 38)
		nome2.Size = UDim2.new(1, -40, 0, 30)
		local desc = texto(botao, "Só você e a sua party. Treine do seu jeito.", 13, COR_TEXTO_MEDIO)
		desc.Position = UDim2.fromOffset(20, 76)
		desc.Size = UDim2.new(1, -40, 0, 36)
		desc.TextWrapped = true
		desc.TextYAlignment = Enum.TextYAlignment.Top
		local tags = Instance.new("Frame")
		tags.Position = UDim2.new(0, 20, 1, -40)
		tags.Size = UDim2.new(1, -40, 0, 22)
		tags.BackgroundTransparency = 1
		tags.Parent = botao
		local tagsLayout = Instance.new("UIListLayout")
		tagsLayout.FillDirection = Enum.FillDirection.Horizontal
		tagsLayout.Padding = UDim.new(0, 8)
		tagsLayout.Parent = tags
		tag(tags, "SEM RECOMPENSAS", COR_TEXTO_FRACO, 0)
		tag(tags, "GK BOT", COR_LEGENDA, 0)
		table.insert(textos, nome); table.insert(textos, nome2); table.insert(textos, desc)
	else
		local nome = texto(botao, maiusculas(mode.DisplayName), 34, COR_TEXTO, Enum.Font.GothamBlack)
		nome.Position = UDim2.fromOffset(20, 16)
		nome.Size = UDim2.new(1, -60, 0, 38)
		local jog = texto(botao, ("%d jogadores%s"):format(mode.TotalPlayers or 0,
			(Config.MODES_GK_OBRIGATORIO and Config.MODES_GK_OBRIGATORIO[modeId]) and "  ·  goleiro obrigatório" or ""), 12, COR_TEXTO_FRACO)
		jog.Position = UDim2.fromOffset(20, 56)
		jog.Size = UDim2.new(1, -40, 0, 16)

		local linha = Instance.new("Frame")
		linha.Position = UDim2.fromOffset(20, 86)
		linha.Size = UDim2.new(1, -40, 0, 1)
		linha.BackgroundColor3 = COR_BORDA
		linha.BorderSizePixel = 0
		linha.Parent = botao

		local total = texto(botao, "0", 36, COR_TEXTO, Enum.Font.GothamBlack)
		total.Position = UDim2.fromOffset(20, 98)
		total.Size = UDim2.fromOffset(90, 40)
		total.AutomaticSize = Enum.AutomaticSize.X
		local totalLeg = texto(botao, "procurando agora", 12, COR_TEXTO_MEDIO)
		totalLeg.Position = UDim2.fromOffset(20, 138)
		totalLeg.Size = UDim2.new(1, -40, 0, 16)

		local ponto = Instance.new("Frame")
		ponto.Position = UDim2.new(0, 20, 1, -24)
		ponto.Size = UDim2.fromOffset(8, 8)
		ponto.BackgroundColor3 = COR_TEXTO_FRACO
		ponto.Parent = botao
		cantos(ponto, 4)
		local regiao = texto(botao, "0 na sua região", 12, COR_TEXTO_MEDIO, Enum.Font.GothamBold)
		regiao.Position = UDim2.new(0, 34, 1, -30)
		regiao.Size = UDim2.new(1, -54, 0, 20)

		card.Total, card.Regiao, card.Ponto = total, regiao, ponto
		table.insert(textos, nome); table.insert(textos, jog); table.insert(textos, total)
		table.insert(textos, totalLeg); table.insert(textos, regiao)
	end

	hover(botao, function() return corCartao(modeId) end, COR_CARTAO_HOV)
	botao.MouseButton1Click:Connect(function()
		if isQueued then return end
		selectedModeId = modeId
		refreshModeCards()
		if _G.AtualizarBotaoFila then _G.AtualizarBotaoFila() end
	end)
	modeCards[modeId] = card
end

-- ===== COLUNA DIREITA =====
local coluna = Instance.new("Frame")
coluna.Position = UDim2.fromOffset(584, 92)
coluna.Size = UDim2.fromOffset(248, 400)
coluna.BackgroundTransparency = 1
coluna.Parent = mainFrame

-- --- grupo ---
local grupoCartao = Instance.new("Frame")
grupoCartao.Size = UDim2.fromOffset(248, 132)
grupoCartao.BackgroundColor3 = COR_CARTAO
grupoCartao.Parent = coluna
cantos(grupoCartao, 12)
contorno(grupoCartao, COR_BORDA, 1)

local grupoTitulo = texto(grupoCartao, "SEU GRUPO", 12, COR_LEGENDA, Enum.Font.GothamBold)
grupoTitulo.Position = UDim2.fromOffset(16, 12)
grupoTitulo.Size = UDim2.fromOffset(120, 16)
local grupoConta = texto(grupoCartao, "1/" .. tostring(Config.MAX_PARTY_SIZE or 7), 12, COR_TEXTO_FRACO, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
grupoConta.Position = UDim2.new(1, -76, 0, 12)
grupoConta.Size = UDim2.fromOffset(60, 16)

local avatarLista = Instance.new("Frame")
avatarLista.Position = UDim2.fromOffset(16, 38)
avatarLista.Size = UDim2.new(1, -74, 0, 46)
avatarLista.BackgroundTransparency = 1
avatarLista.ClipsDescendants = false
avatarLista.Parent = grupoCartao
local avatarLayout = Instance.new("UIListLayout")
avatarLayout.FillDirection = Enum.FillDirection.Horizontal
avatarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
avatarLayout.Padding = UDim.new(0, -10)
avatarLayout.SortOrder = Enum.SortOrder.LayoutOrder
avatarLayout.Parent = avatarLista

local botaoConvidar = Instance.new("TextButton")
botaoConvidar.AnchorPoint = Vector2.new(1, 0)
botaoConvidar.Position = UDim2.new(1, -16, 0, 40)
botaoConvidar.Size = UDim2.fromOffset(42, 42)
botaoConvidar.BackgroundColor3 = COR_CARTAO_ALT
botaoConvidar.Text = "+"
botaoConvidar.TextColor3 = COR_TEXTO
botaoConvidar.Font = Enum.Font.GothamBold
botaoConvidar.TextSize = 22
botaoConvidar.AutoButtonColor = false
botaoConvidar.Parent = grupoCartao
cantos(botaoConvidar, 21)
contorno(botaoConvidar, COR_ACENTO, 1, 0.4)
hover(botaoConvidar, function() return COR_CARTAO_ALT end, COR_CARTAO_HOV)

local nomesGrupo = texto(grupoCartao, "", 12, COR_TEXTO_MEDIO)
nomesGrupo.Position = UDim2.fromOffset(16, 90)
nomesGrupo.Size = UDim2.new(1, -32, 0, 16)

local botaoSair = Instance.new("TextButton")
botaoSair.Position = UDim2.new(0, 16, 1, -26)
botaoSair.Size = UDim2.fromOffset(120, 16)
botaoSair.BackgroundTransparency = 1
botaoSair.Text = "SAIR DO GRUPO"
botaoSair.TextColor3 = COR_PERIGO
botaoSair.Font = Enum.Font.GothamBold
botaoSair.TextSize = 11
botaoSair.TextXAlignment = Enum.TextXAlignment.Left
botaoSair.Visible = false
botaoSair.Parent = grupoCartao
botaoSair.MouseButton1Click:Connect(function()
	if Remotes.LeaveParty then Remotes.LeaveParty:FireServer() end
end)

local function atualizarGrupo(membrosNomes)
	for _, filho in ipairs(avatarLista:GetChildren()) do
		if filho:IsA("Frame") then filho:Destroy() end
	end
	for i, nomeMembro in ipairs(membrosNomes) do
		if i > 6 then break end
		local alvo = Players:FindFirstChild(nomeMembro)
		local slot = Instance.new("Frame")
		slot.LayoutOrder = i
		slot.Size = UDim2.fromOffset(44, 44)
		slot.BackgroundTransparency = 1
		slot.ZIndex = 20 - i
		slot.Parent = avatarLista
		local aro = avatarCircular(slot, alvo and alvo.UserId, nomeMembro, 44)
		aro.ZIndex = slot.ZIndex
		contorno(aro, (i == 1) and COR_ACENTO or COR_CARTAO, i == 1 and 2 or 3)
	end
	grupoConta.Text = ("%d/%d"):format(#membrosNomes, Config.MAX_PARTY_SIZE or 7)
	nomesGrupo.Text = #membrosNomes <= 1 and "Convide amigos com o +" or table.concat(membrosNomes, ", ")
end
atualizarGrupo(currentPartyState.Members)

-- popover de convite
local popoverConvite = Instance.new("ScrollingFrame")
popoverConvite.Name = "PopoverConvite"
popoverConvite.Size = UDim2.fromOffset(248, 200)
popoverConvite.Position = UDim2.fromOffset(584, 92 + 136)
popoverConvite.BackgroundColor3 = COR_PAINEL
popoverConvite.BorderSizePixel = 0
popoverConvite.ScrollBarThickness = 3
popoverConvite.ScrollBarImageColor3 = COR_BORDA
popoverConvite.AutomaticCanvasSize = Enum.AutomaticSize.Y
popoverConvite.CanvasSize = UDim2.new()
popoverConvite.Visible = false
popoverConvite.ZIndex = 50
popoverConvite.Parent = mainFrame
cantos(popoverConvite, 10)
contorno(popoverConvite, COR_ACENTO, 1, 0.3)
local popPad = Instance.new("UIPadding")
popPad.PaddingTop = UDim.new(0, 8)
popPad.PaddingBottom = UDim.new(0, 8)
popPad.PaddingLeft = UDim.new(0, 8)
popPad.PaddingRight = UDim.new(0, 8)
popPad.Parent = popoverConvite
local popLayout = Instance.new("UIListLayout")
popLayout.SortOrder = Enum.SortOrder.LayoutOrder
popLayout.Padding = UDim.new(0, 4)
popLayout.Parent = popoverConvite

local vazioLabel = texto(popoverConvite, "Ninguém mais no servidor agora.", 12, COR_TEXTO_FRACO, nil, Enum.TextXAlignment.Center)
vazioLabel.LayoutOrder = 999
vazioLabel.Size = UDim2.new(1, 0, 0, 30)
vazioLabel.ZIndex = 51

local function refreshInviteList()
	for _, filho in ipairs(popoverConvite:GetChildren()) do
		if filho:IsA("TextButton") then filho:Destroy() end
	end
	local algum = false
	for i, outro in ipairs(Players:GetPlayers()) do
		if outro ~= player and not table.find(currentPartyState.Members or {}, outro.Name) then
			algum = true
			local botao = Instance.new("TextButton")
			botao.LayoutOrder = i
			botao.Size = UDim2.new(1, 0, 0, 36)
			botao.BackgroundColor3 = COR_CARTAO
			botao.AutoButtonColor = false
			botao.Text = ""
			botao.ZIndex = 51
			botao.Parent = popoverConvite
			cantos(botao, 8)
			hover(botao, function() return COR_CARTAO end, COR_CARTAO_HOV)

			local avSlot = Instance.new("Frame")
			avSlot.Size = UDim2.fromOffset(26, 26)
			avSlot.Position = UDim2.new(0, 6, 0.5, -13)
			avSlot.BackgroundTransparency = 1
			avSlot.ZIndex = 52
			avSlot.Parent = botao
			local av = avatarCircular(avSlot, outro.UserId, outro.Name, 26)
			av.ZIndex = 52

			local nome = texto(botao, outro.DisplayName, 13, COR_TEXTO)
			nome.Position = UDim2.fromOffset(40, 0)
			nome.Size = UDim2.new(1, -120, 1, 0)
			nome.ZIndex = 52

			local acao = texto(botao, "CONVIDAR", 11, COR_ACENTO, Enum.Font.GothamBold, Enum.TextXAlignment.Right)
			acao.Position = UDim2.new(1, -80, 0, 0)
			acao.Size = UDim2.new(0, 72, 1, 0)
			acao.ZIndex = 52

			botao.MouseButton1Click:Connect(function()
				if isQueued then return end
				Remotes.InviteToParty:FireServer(outro)
				acao.Text = "ENVIADO"
				acao.TextColor3 = COR_OK
				task.delay(2.5, function()
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
Players.PlayerAdded:Connect(function() if popoverAberto then refreshInviteList() end end)
Players.PlayerRemoving:Connect(function() task.defer(function() if popoverAberto then refreshInviteList() end end) end)

-- --- goleiro ---
local gkCartao = Instance.new("TextButton")
gkCartao.Position = UDim2.fromOffset(0, 144)
gkCartao.Size = UDim2.fromOffset(248, 96)
gkCartao.BackgroundColor3 = COR_CARTAO
gkCartao.AutoButtonColor = false
gkCartao.Text = ""
gkCartao.Parent = coluna
cantos(gkCartao, 12)
local gkStroke = contorno(gkCartao, COR_BORDA, 1)
hover(gkCartao, function() return COR_CARTAO end, COR_CARTAO_HOV)

local gkTitulo = texto(gkCartao, "JOGAR DE GOLEIRO", 15, COR_TEXTO, Enum.Font.GothamBlack)
gkTitulo.Position = UDim2.fromOffset(16, 16)
gkTitulo.Size = UDim2.new(1, -90, 0, 20)
local gkDesc = texto(gkCartao, "", 12, COR_TEXTO_FRACO)
gkDesc.Position = UDim2.fromOffset(16, 42)
gkDesc.Size = UDim2.new(1, -32, 0, 40)
gkDesc.TextWrapped = true
gkDesc.TextYAlignment = Enum.TextYAlignment.Top

local chave = Instance.new("Frame")
chave.AnchorPoint = Vector2.new(1, 0)
chave.Position = UDim2.new(1, -16, 0, 14)
chave.Size = UDim2.fromOffset(46, 24)
chave.BackgroundColor3 = COR_CARTAO_ALT
chave.Parent = gkCartao
cantos(chave, 12)
contorno(chave, COR_BORDA, 1)
local bolinha = Instance.new("Frame")
bolinha.Position = UDim2.fromOffset(3, 3)
bolinha.Size = UDim2.fromOffset(18, 18)
bolinha.BackgroundColor3 = COR_TEXTO_FRACO
bolinha.Parent = chave
cantos(bolinha, 9)

local function atualizarGoleiro()
	local ligado = goleiroMarcado or goleiroAutomatico
	TweenService:Create(bolinha, TweenInfo.new(0.15), {
		Position = ligado and UDim2.fromOffset(25, 3) or UDim2.fromOffset(3, 3),
		BackgroundColor3 = ligado and Color3.new(1, 1, 1) or COR_TEXTO_FRACO,
	}):Play()
	chave.BackgroundColor3 = ligado and COR_OK or COR_CARTAO_ALT
	gkStroke.Color = ligado and COR_OK or COR_BORDA
	gkStroke.Transparency = ligado and 0.4 or 0
	if goleiroAutomatico and not goleiroMarcado then
		gkDesc.Text = "Automático: suas 2 Hissatsus ativas são de goleiro."
	elseif ligado then
		gkDesc.Text = "Você vai pro gol. Sem goleiro nos 2 times, a partida usa o GK bot."
	else
		gkDesc.Text = "Desligado: você joga na linha. O gol fica com outro jogador ou o GK bot."
	end
end
atualizarGoleiro()

gkCartao.MouseButton1Click:Connect(function()
	if isQueued then return end
	if goleiroAutomatico and not goleiroMarcado then return end -- automático pelas Hissatsus
	goleiroMarcado = not goleiroMarcado
	atualizarGoleiro()
	Remotes.DefinirGoleiro:FireServer(goleiroMarcado)
end)

Remotes.EstadoGoleiro.OnClientEvent:Connect(function(marcado, automatico)
	goleiroMarcado = marcado == true
	goleiroAutomatico = automatico == true
	atualizarGoleiro()
end)

-- --- botão principal ---
local queueButton = Instance.new("TextButton")
queueButton.Position = UDim2.fromOffset(0, 254)
queueButton.Size = UDim2.fromOffset(248, 70)
queueButton.BackgroundColor3 = COR_OK
queueButton.Text = ""
queueButton.AutoButtonColor = false
queueButton.Parent = coluna
cantos(queueButton, 12)

local queueLegenda = texto(queueButton, "", 11, Color3.new(1, 1, 1), Enum.Font.GothamBold, Enum.TextXAlignment.Center)
queueLegenda.Position = UDim2.fromOffset(0, 12)
queueLegenda.Size = UDim2.new(1, 0, 0, 14)
queueLegenda.TextTransparency = 0.25
local queueButtonLabel = texto(queueButton, "PROCURAR", 22, Color3.new(1, 1, 1), Enum.Font.GothamBlack, Enum.TextXAlignment.Center)
queueButtonLabel.Position = UDim2.fromOffset(0, 28)
queueButtonLabel.Size = UDim2.new(1, 0, 0, 28)

local statusLabel = texto(coluna, "", 12, COR_TEXTO_FRACO, Enum.Font.GothamMedium, Enum.TextXAlignment.Center)
statusLabel.Position = UDim2.fromOffset(0, 334)
statusLabel.Size = UDim2.new(1, 0, 0, 34)
statusLabel.TextWrapped = true
statusLabel.TextYAlignment = Enum.TextYAlignment.Top

local function corBotao()
	return isQueued and COR_PERIGO or COR_OK
end

local function updateQueueButton()
	queueButton.BackgroundColor3 = corBotao()
	local mode = Config.MODES[selectedModeId]
	if isQueued then
		queueLegenda.Text = "PROCURANDO " .. (mode and maiusculas(mode.DisplayName) or "")
	elseif mode and (mode.IsPrivate or mode.IsFreeRoom) then
		queueLegenda.Text = "SÓ VOCÊ E SUA PARTY"
		queueButtonLabel.Text = "CRIAR SALA"
	else
		queueLegenda.Text = mode and maiusculas(mode.DisplayName) or ""
		queueButtonLabel.Text = "PROCURAR PARTIDA"
	end
end
_G.AtualizarBotaoFila = updateQueueButton
hover(queueButton, corBotao, COR_OK:Lerp(Color3.new(1, 1, 1), 0.1))
queueButton.MouseLeave:Connect(updateQueueButton)

queueButton.MouseButton1Click:Connect(function()
	fecharPopover()
	if not currentPartyState.IsLeader then return end
	if isQueued then
		Remotes.LeaveQueue:FireServer()
	else
		local mode = Config.MODES[selectedModeId]
		if mode and (mode.IsPrivate or mode.IsFreeRoom) then
			statusLabel.Text = "criando a sua sala..."
			statusLabel.TextColor3 = COR_LEGENDA
		end
		Remotes.JoinQueue:FireServer(selectedModeId)
	end
end)

RunService.Heartbeat:Connect(function()
	if not (screenGui.Enabled and isQueued) then return end
	local t = math.max(0, os.clock() - queueStartedAt)
	queueButtonLabel.Text = ("CANCELAR  %d:%02d"):format(math.floor(t / 60), math.floor(t % 60))
end)

refreshModeCards()
updateQueueButton()

-- ===== EVENTOS DO SERVIDOR =====
Remotes.SetMatchmakingScreenOpen.OnClientEvent:Connect(function(open)
	screenGui.Enabled = open
	if open then
		ajustarEscala()
		Remotes.DefinirGoleiro:FireServer(nil) -- pede o estado atual do goleiro
		mainFrame.GroupTransparency = 1
		mainFrame.Position = UDim2.new(0.5, 0, 0.5, 20)
		TweenService:Create(mainFrame, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.5),
		}):Play()
	else
		fecharPopover()
	end
end)

Remotes.UpdatePartyState.OnClientEvent:Connect(function(state)
	currentPartyState = state
	atualizarGrupo(state.Members)
	queueButton.Visible = state.IsLeader
	botaoSair.Visible = not state.IsLeader
	if not state.IsLeader then
		statusLabel.Text = "Aguardando o líder do grupo escolher a partida."
		statusLabel.TextColor3 = COR_TEXTO_FRACO
	elseif not isQueued then
		statusLabel.Text = ""
	end
	if popoverAberto then refreshInviteList() end
end)

Remotes.UpdateQueueStatus.OnClientEvent:Connect(function(status)
	local entrouAgora = status.InQueue and not isQueued
	isQueued = status.InQueue
	if entrouAgora then queueStartedAt = os.clock() end
	if status.InQueue and status.ModeId then selectedModeId = status.ModeId end
	refreshModeCards()
	updateQueueButton()
	if isQueued then
		local info = contagens[status.ModeId]
		statusLabel.Text = info and ("%d procurando · %d na sua região"):format(info.Total or 0, info.Regiao or 0) or "procurando..."
		statusLabel.TextColor3 = COR_TEXTO_MEDIO
	else
		statusLabel.Text = ""
	end
end)

Remotes.ContagemFila.OnClientEvent:Connect(function(porModo, regiao)
	if typeof(porModo) == "table" then contagens = porModo end
	if typeof(regiao) == "string" and regiao ~= "UNKNOWN" then minhaRegiao = regiao end
	atualizarContagens()
end)

Remotes.MatchFound.OnClientEvent:Connect(function(modeId)
	queueLegenda.Text = "PARTIDA ENCONTRADA"
	queueButtonLabel.Text = "ENTRANDO..."
	queueButton.BackgroundColor3 = COR_ACENTO
	statusLabel.Text = "teleportando..."
	statusLabel.TextColor3 = COR_ACENTO
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end
atualizarContagens()
ajustarEscala()
print("✅ MatchmakingClient carregado (v104).")
