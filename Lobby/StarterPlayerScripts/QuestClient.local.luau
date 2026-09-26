--[[
	QuestClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Painel de missões, 100% scriptado (mesmo esquema do
	CodeRedeemClient/ShopClient — só SCRIPT sincroniza pelo bridge, então o
	GUI inteiro nasce aqui via Instance.new).

	Escolha de missão: o servidor oferece OFFER_QUEST_COUNT candidatas por
	período (12h) e o jogador clica pra ativar/desativar até
	ACTIVE_QUEST_COUNT delas. Só as ativas progridem/pagam.

	Aberto pelo NPC de missão: DialogueClient.local.luau chama _G.OpenQuests
	quando o diálogo do QuestGiver termina de fechar.

	Servidor: QuestManager.legacy.luau (ReplicatedStorage.QuestEvents ->
	GetQuests/SelectQuest RemoteFunctions, QuestCompleted RemoteEvent).

	⚠️ v74 — REDESENHO COMPLETO.
	PEDIDO: "a HUD de missões que também precisa atualizar, é aquela que
	aparece depois de clicar em 'Mostrar Missões'... eu quero que tire
	aquele emoji de bloco de notas, e melhore ela DEMAIS faça ela super
	moderna com uma seleção muito bonita, tente manter tudo no mesmo
	estilo."

	O que mudou:
	1) Emoji fora — "🗒️ Missões" virou barrinha de acento + "MISSÕES",
	   mesmo padrão do resto do Lobby (Matchmaking/Roll/Shop/Tracker).
	   "✅"/"☑"/"☐" nas linhas viraram um checkbox DESENHADO (círculo com
	   anel, preenche com tween ao selecionar) — o mesmo tipo de forma
	   que já apareceu nos avatares circulares do Matchmaking.
	2) Paleta v72-74 (fundo quase-preto, um acento só, cartões com borda
	   discreta) — a tela antiga usava cinza médio (25,25,32) isolado do
	   resto.
	3) Contagem regressiva virou pílula no cabeçalho (mesmo desenho do
	   badge de contador do MissionTrackerHUD), não mais uma linha de
	   texto solta.
	4) Barra de progresso anima (TweenService) em vez de saltar de valor
	   pra valor — mesma correção já aplicada no MissionTrackerHUD.
	5) Cartão selecionado ganha borda de acento + leve glow; cartão
	   concluído vira verde. Nenhuma raridade aqui (missão não tem
	   raridade) — a hierarquia visual é só "concluída / ativa / inativa".
	6) UIScale — a tela antiga não tinha, ficava puxada num celular menor.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local questEvents = ReplicatedStorage:WaitForChild("QuestEvents", 10)
if not questEvents then
	warn("QuestClient: QuestEvents não encontrado em ReplicatedStorage.")
	return
end

local getQuestsRemote = questEvents:WaitForChild("GetQuests", 10)
local selectQuestRemote = questEvents:WaitForChild("SelectQuest", 10)
local questCompletedRemote = questEvents:WaitForChild("QuestCompleted", 10)
if not getQuestsRemote or not selectQuestRemote or not questCompletedRemote then
	warn("QuestClient: remotes de missão não encontrados.")
	return
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Missão",
			Text = text,
			Duration = 4,
		})
	end)
end

local function formatCountdown(secondsLeft)
	secondsLeft = math.max(0, math.floor(secondsLeft))
	local hours = math.floor(secondsLeft / 3600)
	local minutes = math.floor((secondsLeft % 3600) / 60)
	return string.format("%dh %02dmin", hours, minutes)
end

-- ===== PALETA (mesma do resto do Lobby, v72-74) =====
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_OK   = Color3.fromRGB(18, 32, 25)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_TRILHO      = Color3.fromRGB(9, 10, 15)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_OURO        = Color3.fromRGB(230, 185, 90)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

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

-- ==========================================================
-- Construção do GUI
-- ==========================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "QuestGUI_Provisorio"
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
panel.Size = UDim2.new(0, 460, 0, 480)
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
	escala.Scale = math.min(1, (v.X - 32) / 460, (v.Y - 32) / 480)
end

-- ----- cabeçalho -----
local barrinha = Instance.new("Frame")
barrinha.Size = UDim2.fromOffset(3, 20)
barrinha.Position = UDim2.new(0, 18, 0, 20)
barrinha.BackgroundColor3 = COR_ACENTO
barrinha.BorderSizePixel = 0
barrinha.ZIndex = 10
barrinha.Parent = panel
cantos(barrinha, 2)

local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.new(1, -170, 0, 22)
title.Position = UDim2.new(0, 30, 0, 14)
title.BackgroundTransparency = 1
title.Text = "MISSÕES"
title.TextColor3 = COR_TEXTO
title.Font = Enum.Font.GothamBlack
title.TextSize = 19
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 10
title.Parent = panel

local subtitle = Instance.new("TextLabel")
subtitle.Name = "Subtitle"
subtitle.Size = UDim2.new(1, -170, 0, 16)
subtitle.Position = UDim2.new(0, 30, 0, 36)
subtitle.BackgroundTransparency = 1
subtitle.Text = "escolha as suas — só as escolhidas contam"
subtitle.TextColor3 = COR_TEXTO_FRACO
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextSize = 12
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.ZIndex = 10
subtitle.Parent = panel

-- Pílula de contagem regressiva — mesmo desenho do badge do
-- MissionTrackerHUD, não mais uma linha de texto solta no meio do painel.
local countdownPill = Instance.new("Frame")
countdownPill.Size = UDim2.fromOffset(96, 22)
countdownPill.Position = UDim2.new(1, -140, 0, 16)
countdownPill.BackgroundColor3 = COR_CARTAO_ALT
countdownPill.BorderSizePixel = 0
countdownPill.ZIndex = 10
countdownPill.Parent = panel
cantos(countdownPill, 11)

local countdownLabel = Instance.new("TextLabel")
countdownLabel.Name = "CountdownLabel"
countdownLabel.Size = UDim2.new(1, 0, 1, 0)
countdownLabel.BackgroundTransparency = 1
countdownLabel.Text = "--"
countdownLabel.TextColor3 = COR_TEXTO_FRACO
countdownLabel.Font = Enum.Font.GothamBold
countdownLabel.TextSize = 11
countdownLabel.ZIndex = 10
countdownLabel.Parent = countdownPill

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.Position = UDim2.new(1, -44, 0, 12)
closeButton.BackgroundColor3 = COR_CARTAO_ALT
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = COR_TEXTO
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 15
closeButton.ZIndex = 10
closeButton.Parent = panel
cantos(closeButton, 16)

local divisor = Instance.new("Frame")
divisor.Size = UDim2.new(1, -32, 0, 1)
divisor.Position = UDim2.new(0, 16, 0, 60)
divisor.BackgroundColor3 = COR_BORDA
divisor.BorderSizePixel = 0
divisor.ZIndex = 10
divisor.Parent = panel

local listFrame = Instance.new("ScrollingFrame")
listFrame.Name = "ListFrame"
listFrame.Size = UDim2.new(1, -32, 1, -80)
listFrame.Position = UDim2.new(0, 16, 0, 70)
listFrame.BackgroundTransparency = 1
listFrame.BorderSizePixel = 0
listFrame.ScrollBarThickness = 4
listFrame.ScrollBarImageColor3 = COR_TEXTO_FRACO
listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
listFrame.ZIndex = 10
listFrame.Parent = panel

local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 8)
listLayout.Parent = listFrame

local emptyLabel = Instance.new("TextLabel")
emptyLabel.Name = "EmptyLabel"
emptyLabel.Size = UDim2.new(1, 0, 0, 60)
emptyLabel.BackgroundTransparency = 1
emptyLabel.Text = "Carregando missões..."
emptyLabel.TextColor3 = COR_TEXTO_FRACO
emptyLabel.Font = Enum.Font.GothamMedium
emptyLabel.TextSize = 13
emptyLabel.Visible = false
emptyLabel.ZIndex = 10
emptyLabel.LayoutOrder = 0
emptyLabel.Parent = listFrame

-- ==========================================================
-- Estado local
-- ==========================================================
local latestPeriodEndsAt = 0
local isSelecting = false

local function refreshQuests() end -- forward declare (usado dentro de buildQuestRow)

-- ==========================================================
-- Checkbox desenhado: círculo com anel, preenche com tween — substitui
-- os caracteres "☑"/"☐"/"✅" por uma forma de verdade na paleta certa.
-- ==========================================================
local function buildCheckbox(pai, ativo, concluida)
	local aro = Instance.new("Frame")
	aro.Name = "Checkbox"
	aro.Size = UDim2.fromOffset(28, 28)
	aro.Position = UDim2.new(0, 10, 0.5, -14)
	aro.BackgroundColor3 = COR_TRILHO
	aro.BorderSizePixel = 0
	aro.ZIndex = 11
	aro.Parent = pai
	cantos(aro, 14)

	local cor = concluida and COR_OK or (ativo and COR_ACENTO or COR_TEXTO_FRACO)
	local anelStroke = contorno(aro, cor, 2, ativo and 0 or 0.35)

	local preenchimento = Instance.new("Frame")
	preenchimento.AnchorPoint = Vector2.new(0.5, 0.5)
	preenchimento.Position = UDim2.new(0.5, 0, 0.5, 0)
	preenchimento.Size = ativo and UDim2.fromOffset(16, 16) or UDim2.fromOffset(0, 0)
	preenchimento.BackgroundColor3 = cor
	preenchimento.BorderSizePixel = 0
	preenchimento.ZIndex = 12
	preenchimento.Parent = aro
	cantos(preenchimento, 8)

	if concluida then
		local check = Instance.new("TextLabel")
		check.Size = UDim2.new(1, 0, 1, 0)
		check.BackgroundTransparency = 1
		check.Text = "\u{2713}"
		check.Font = Enum.Font.GothamBlack
		check.TextSize = 20
		check.TextColor3 = Color3.new(1, 1, 1)
		check.ZIndex = 13
		check.Parent = aro
	end

	return aro
end

-- ==========================================================
-- Uma "linha" de missão (checkbox de escolha, progresso, recompensa)
-- ==========================================================
local function buildQuestRow(quest, order)
	local concluida = quest.Completed and true or false
	local ativa = quest.Active and true or false

	local row = Instance.new("TextButton")
	row.Name = "Quest_" .. quest.Id
	row.Size = UDim2.new(1, 0, 0, 74)
	row.BackgroundColor3 = concluida and COR_CARTAO_OK or COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Text = ""
	row.AutoButtonColor = false
	row.ZIndex = 10
	row.Parent = listFrame
	cantos(row, 10)

	local corBorda = concluida and COR_OK or (ativa and COR_ACENTO or COR_BORDA)
	contorno(row, corBorda, ativa and 1.5 or 1, ativa and 0.15 or 0.35)

	buildCheckbox(row, ativa, concluida)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, -150, 0, 20)
	nameLabel.Position = UDim2.new(0, 48, 0, 10)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = quest.Name
	nameLabel.TextColor3 = concluida and COR_OK or COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 11
	nameLabel.Parent = row

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Name = "RewardLabel"
	rewardLabel.Size = UDim2.new(0, 70, 0, 20)
	rewardLabel.Position = UDim2.new(1, -78, 0, 10)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = "+$" .. tostring(quest.Reward)
	rewardLabel.TextColor3 = COR_OURO
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 13
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	rewardLabel.ZIndex = 11
	rewardLabel.Parent = row

	local barBg = Instance.new("Frame")
	barBg.Name = "BarBg"
	barBg.Size = UDim2.new(1, -60, 0, 8)
	barBg.Position = UDim2.new(0, 48, 0, 40)
	barBg.BackgroundColor3 = COR_TRILHO
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 11
	barBg.Parent = row
	cantos(barBg, 4)

	local fraction = quest.Target > 0 and math.clamp(quest.Progress / quest.Target, 0, 1) or 0
	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = concluida and COR_OK or COR_ACENTO
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 12
	barFill.Parent = barBg
	cantos(barFill, 4)
	TweenService:Create(barFill, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = UDim2.new(fraction, 0, 1, 0) }):Play()

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Name = "ProgressLabel"
	progressLabel.Size = UDim2.new(1, -60, 0, 14)
	progressLabel.Position = UDim2.new(0, 48, 0, 52)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = concluida
		and (ativa and "concluída — clique pra remover e abrir vaga" or "concluída")
		or (tostring(quest.Progress) .. " / " .. tostring(quest.Target))
	progressLabel.TextColor3 = COR_TEXTO_FRACO
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextSize = 11
	progressLabel.TextXAlignment = Enum.TextXAlignment.Left
	progressLabel.ZIndex = 11
	progressLabel.Parent = row

	-- ⚠️ v75 — CORRIGIDO ("depois de completar, não dá pra des-selecionar
	-- pra escolher outra"): antes, uma missão Completed nem tinha clique
	-- ligado — não tinha COMO tirar ela de Active e abrir vaga. Agora
	-- toda linha é clicável; quem decide se aquele clique é permitido é
	-- o servidor (SelectQuest, já corrigido pra sempre aceitar
	-- DESATIVAR uma concluída, só nunca REATIVAR).
	row.MouseEnter:Connect(function()
		row.BackgroundColor3 = concluida and COR_CARTAO_ALT or COR_CARTAO_ALT
	end)
	row.MouseLeave:Connect(function()
		row.BackgroundColor3 = concluida and COR_CARTAO_OK or COR_CARTAO
	end)
	row.MouseButton1Click:Connect(function()
		if isSelecting then return end
		isSelecting = true

		local ok, success, message = pcall(function()
			return selectQuestRemote:InvokeServer(quest.Id)
		end)

		isSelecting = false

		if ok and success then
			refreshQuests()
			-- ⚠️ v79: avisa a HUD pequena (MissionTrackerHUD) que uma missão
			-- foi selecionada/desselecionada, pra ela atualizar SÓ agora —
			-- não tem poll periódico nenhum mais lá (ver aquele arquivo).
			if _G.RefreshMissionTracker then _G.RefreshMissionTracker() end
		else
			local errorMessage = ok and message or tostring(success)
			notify(errorMessage or "Não deu pra escolher essa missão agora.")
		end
	end)

	return row
end

-- ==========================================================
-- Refresh (pede a lista pro servidor e reconstrói o painel)
-- ==========================================================
local function clearList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if (child:IsA("TextButton") or child:IsA("Frame")) and child.Name ~= "EmptyLabel" then
			child:Destroy()
		end
	end
end

local isRefreshing = false

refreshQuests = function()
	if isRefreshing then return end
	isRefreshing = true

	local ok, result = pcall(function()
		return getQuestsRemote:InvokeServer()
	end)

	isRefreshing = false

	if not ok or type(result) ~= "table" then
		warn("QuestClient: falha ao buscar missões:", result)
		return
	end

	local quests = result.Quests or {}
	latestPeriodEndsAt = result.PeriodEndsAt or 0

	clearList()

	if #quests == 0 then
		emptyLabel.Text = "Nenhuma missão disponível agora."
		emptyLabel.Visible = true
		return
	end

	emptyLabel.Visible = false
	for i, quest in ipairs(quests) do
		buildQuestRow(quest, i)
	end
end

-- ==========================================================
-- Abrir / fechar
-- ==========================================================
local function closeQuests()
	screenGui.Enabled = false
	-- ⚠️ v79: "fecha ou abre a aba de missões" é um dos 4 momentos em que
	-- a HUD pequena pode ter ficado desatualizada (o painel grande é onde
	-- o jogador de fato mexeu nas missões) — atualiza ela aqui também.
	if _G.RefreshMissionTracker then _G.RefreshMissionTracker() end
end

local function openQuests()
	screenGui.Enabled = true
	ajustarEscala()
	refreshQuests()
	if _G.RefreshMissionTracker then _G.RefreshMissionTracker() end
end

closeButton.MouseButton1Click:Connect(closeQuests)
backdrop.MouseButton1Click:Connect(closeQuests)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end

-- Contagem regressiva do reset (12h) enquanto o painel estiver aberto.
task.spawn(function()
	while true do
		task.wait(1)
		if screenGui.Enabled and latestPeriodEndsAt > 0 then
			countdownLabel.Text = formatCountdown(latestPeriodEndsAt - os.time())
		end
	end
end)

questCompletedRemote.OnClientEvent:Connect(function(questName, reward)
	notify(string.format("Missão completa: %s (+$%d)", tostring(questName), tonumber(reward) or 0))
	if screenGui.Enabled then
		refreshQuests()
	end
end)

-- Chamado por DialogueClient.local.luau quando o NPC de missão termina o
-- diálogo (ver DialogueData.luau -> QuestGiver -> Action = "OpenQuests").
_G.OpenQuests = openQuests

print("✅ QuestClient carregado.")
