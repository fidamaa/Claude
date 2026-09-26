--[[
	MissionTrackerHUD (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Widget pequeno no canto da tela, sempre visível enquanto o jogador anda
	pelo Lobby, com as missões que ele deixou EQUIPADAS (Active = true no
	servidor). Pra ESCOLHER/trocar missão existe o painel grande do
	QuestClient (_G.OpenQuests) — ⚠️ v75: só o NPC abre ele agora (ver
	nota mais abaixo); esta HUD é só leitura, não tem mais botão pra
	abrir o painel daqui.

	Servidor: QuestManager.legacy.luau (ReplicatedStorage.QuestEvents ->
	GetQuests RemoteFunction, QuestCompleted RemoteEvent). Nenhum remote
	novo — o contrato não mudou nesta revisão.

	⚠️ v70 — REWORK VISUAL.
	PEDIDO: "você não fez o rework na HUD de missões" (e, antes, "melhora a
	HUD, tá muito IA").

	⚠️ v73 — PALETA ATUALIZADA PRA BATER COM O MATCHMAKING (v72).
	PEDIDO: "melhora a HUD de missões". O MatchmakingClient passou por um
	redesenho baseado em referência (Valorant) que escureceu o fundo de
	#171A26 pra #0D0F16 — quase preto de verdade, não cinza-azulado. Esta
	tela usava a paleta ANTIGA (v70), então as duas HUDs voltaram a
	destoar entre si. Só a paleta muda aqui; layout/lógica continuam os
	mesmos.

	O que estava denunciando UI feita por conveniência, e o que virou:

	1) EMOJI COMO ÍCONE. O título era "🗒️ Missões equipadas", as linhas
	   começavam com "▸"/"✅" e o rodapé com "✏️". Emoji muda de desenho em
	   cada sistema operacional, não acompanha a paleta e é o sinal mais
	   óbvio de layout montado às pressas. Agora os marcadores são formas
	   desenhadas (barra de acento colorida na linha, seta em triângulo),
	   que respondem às mesmas cores do resto.

	2) PALETA PRÓPRIA. Era cinza-azulado solto, diferente de toda outra
	   tela. Agora usa a MESMA paleta da tela de fila (MatchmakingClient),
	   pra o Lobby parecer um produto só em vez de telas avulsas.

	3) BUG DE USO, não só de estética: o botão "escolher missões" tinha
	   `hintLabel.Visible = false` quando havia missão equipada. Ou seja,
	   ele só aparecia com a lista VAZIA — exatamente quando você menos
	   precisa dele. Quem já tinha missão equipada não tinha por onde
	   trocar sem voltar no NPC. Agora o botão fica sempre visível.

	4) NÃO CABIA NO CELULAR. Largura fixa de 260px sem escala. Agora tem
	   UIScale, igual às outras telas.

	5) A barra de progresso saltava de um valor pro outro a cada poll.
	   Agora ela anima — a diferença entre "não mudou nada" e "avancei"
	   fica visível, que é o ponto de ter um tracker na tela.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local questEvents = ReplicatedStorage:WaitForChild("QuestEvents", 10)
if not questEvents then
	warn("MissionTrackerHUD: QuestEvents não encontrado em ReplicatedStorage.")
	return
end

local getQuestsRemote = questEvents:WaitForChild("GetQuests", 10)
local questCompletedRemote = questEvents:WaitForChild("QuestCompleted", 10)
if not getQuestsRemote or not questCompletedRemote then
	warn("MissionTrackerHUD: remotes de missão não encontrados.")
	return
end

-- ===== PALETA (mesma do MatchmakingClient v72) =====
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_TRILHO      = Color3.fromRGB(9, 10, 15)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_OURO        = Color3.fromRGB(230, 185, 90)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local LARGURA = 276

local function cantos(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end

-- ===== RAIZ =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MissionTrackerHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -16, 0, 16)
panel.Size = UDim2.new(0, LARGURA, 0, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.BackgroundColor3 = COR_PAINEL
panel.BackgroundTransparency = 0
panel.BorderSizePixel = 0
panel.ZIndex = 5
panel.Parent = screenGui
cantos(panel, 10) -- cantos discretos (mesmo raio do MatchmakingClient), não bem arredondados

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = COR_BORDA
panelStroke.Thickness = 1
panelStroke.Transparency = 0.15
panelStroke.Parent = panel

local escala = Instance.new("UIScale")
escala.Parent = panel

local function ajustarEscala()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local v = camera.ViewportSize
	if v.X <= 0 then return end
	-- num celular em pé, 276px é quase metade da largura da tela
	escala.Scale = math.clamp(v.X / 900, 0.72, 1)
end

local panelLayout = Instance.new("UIListLayout")
panelLayout.SortOrder = Enum.SortOrder.LayoutOrder
panelLayout.Parent = panel

-- ===== CABEÇALHO =====
local header = Instance.new("TextButton")
header.Name = "Header"
header.Size = UDim2.new(1, 0, 0, 38)
header.BackgroundTransparency = 1
header.Text = ""
header.AutoButtonColor = false
header.LayoutOrder = 1
header.ZIndex = 6
header.Parent = panel

-- Barrinha de acento antes do título — mesmo padrão do MatchmakingClient
-- (v72), pra as duas telas lerem como o mesmo produto.
local barrinha = Instance.new("Frame")
barrinha.Size = UDim2.fromOffset(3, 14)
barrinha.Position = UDim2.new(0, 14, 0.5, -7)
barrinha.BackgroundColor3 = COR_ACENTO
barrinha.BorderSizePixel = 0
barrinha.ZIndex = 6
barrinha.Parent = header
cantos(barrinha, 2)

local headerTitle = Instance.new("TextLabel")
headerTitle.Size = UDim2.new(1, -80, 1, 0)
headerTitle.Position = UDim2.new(0, 24, 0, 0)
headerTitle.BackgroundTransparency = 1
headerTitle.Text = "MISSÕES"
headerTitle.TextColor3 = COR_TEXTO
headerTitle.Font = Enum.Font.GothamBlack
headerTitle.TextSize = 13
headerTitle.TextXAlignment = Enum.TextXAlignment.Left
headerTitle.ZIndex = 6
headerTitle.Parent = header

-- Contador em pílula: diz quantas estão equipadas sem precisar expandir.
local badge = Instance.new("Frame")
badge.Size = UDim2.new(0, 26, 0, 18)
badge.Position = UDim2.new(1, -62, 0.5, -9)
badge.BackgroundColor3 = COR_CARTAO
badge.BorderSizePixel = 0
badge.ZIndex = 6
badge.Parent = header
cantos(badge, 9)

local badgeText = Instance.new("TextLabel")
badgeText.Size = UDim2.new(1, 0, 1, 0)
badgeText.BackgroundTransparency = 1
badgeText.Text = "0"
badgeText.TextColor3 = COR_TEXTO_FRACO
badgeText.Font = Enum.Font.GothamBold
badgeText.TextSize = 11
badgeText.ZIndex = 7
badgeText.Parent = badge

-- Seta desenhada (triângulo girado), não caractere de emoji: acompanha a
-- paleta e roda igual em qualquer sistema.
local seta = Instance.new("TextLabel")
seta.Size = UDim2.new(0, 26, 1, 0)
seta.Position = UDim2.new(1, -30, 0, 0)
seta.BackgroundTransparency = 1
seta.Text = "\u{25BE}"
seta.TextColor3 = COR_TEXTO_FRACO
seta.Font = Enum.Font.GothamBold
seta.TextSize = 14
seta.ZIndex = 6
seta.Parent = header

local divisor = Instance.new("Frame")
divisor.Size = UDim2.new(1, -24, 0, 1)
divisor.Position = UDim2.new(0, 12, 0, 0)
divisor.BackgroundColor3 = COR_BORDA
divisor.BorderSizePixel = 0
divisor.ZIndex = 6
divisor.LayoutOrder = 2
divisor.Parent = panel

-- ===== CORPO =====
local body = Instance.new("Frame")
body.Name = "Body"
body.Size = UDim2.new(1, 0, 0, 0)
body.AutomaticSize = Enum.AutomaticSize.Y
body.BackgroundTransparency = 1
body.LayoutOrder = 3
body.Parent = panel

local bodyLayout = Instance.new("UIListLayout")
bodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
bodyLayout.Padding = UDim.new(0, 6)
bodyLayout.Parent = body

local bodyPadding = Instance.new("UIPadding")
bodyPadding.PaddingTop = UDim.new(0, 10)
bodyPadding.PaddingBottom = UDim.new(0, 10)
bodyPadding.PaddingLeft = UDim.new(0, 10)
bodyPadding.PaddingRight = UDim.new(0, 10)
bodyPadding.Parent = body

-- ⚠️ v75 — PEDIDO: "não dê a opção de abrir a guia de missões pela HUD, a
-- pessoa precisa ir até o NPC." O botão "ESCOLHER MISSÕES" (que chamava
-- _G.OpenQuests direto daqui) saiu. A HUD volta a ser só leitura — pra
-- trocar missão o jogador precisa mesmo visitar o QuestGiver.
local emptyLabel = Instance.new("TextLabel")
emptyLabel.Name = "EmptyLabel"
emptyLabel.Size = UDim2.new(1, 0, 0, 32)
emptyLabel.BackgroundTransparency = 1
emptyLabel.Text = "Nenhuma missão equipada — fale com o NPC de missões."
emptyLabel.TextColor3 = COR_TEXTO_FRACO
emptyLabel.Font = Enum.Font.GothamMedium
emptyLabel.TextSize = 12
emptyLabel.TextWrapped = true
emptyLabel.LayoutOrder = 0
emptyLabel.Visible = false
emptyLabel.ZIndex = 6
emptyLabel.Parent = body

-- ===== UMA LINHA DE MISSÃO =====
local function buildTrackerRow(quest, order)
	local concluida = quest.Completed and true or false
	local corAcento = concluida and COR_OK or COR_ACENTO

	local row = Instance.new("Frame")
	row.Name = "Quest_" .. tostring(quest.Id)
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundColor3 = COR_CARTAO
	row.BackgroundTransparency = 0.25
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 6
	row.Parent = body
	cantos(row, 8)

	-- Barra de acento à esquerda: substitui o "▸"/"✅" de emoji. Azul =
	-- em andamento, verde = concluída — a mesma informação, lida de
	-- relance e na cor do sistema.
	local acento = Instance.new("Frame")
	acento.Size = UDim2.new(0, 3, 1, -12)
	acento.Position = UDim2.new(0, 7, 0, 6)
	acento.BackgroundColor3 = corAcento
	acento.BorderSizePixel = 0
	acento.ZIndex = 7
	acento.Parent = row
	cantos(acento, 2)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -78, 0, 16)
	nameLabel.Position = UDim2.new(0, 17, 0, 7)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = tostring(quest.Name)
	nameLabel.TextColor3 = concluida and COR_OK or COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.ZIndex = 7
	nameLabel.Parent = row

	local rewardLabel = Instance.new("TextLabel")
	rewardLabel.Size = UDim2.new(0, 58, 0, 16)
	rewardLabel.Position = UDim2.new(1, -66, 0, 7)
	rewardLabel.BackgroundTransparency = 1
	rewardLabel.Text = "+$" .. tostring(quest.Reward)
	rewardLabel.TextColor3 = COR_OURO
	rewardLabel.Font = Enum.Font.GothamBold
	rewardLabel.TextSize = 12
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Right
	rewardLabel.ZIndex = 7
	rewardLabel.Parent = row

	local trilho = Instance.new("Frame")
	trilho.Size = UDim2.new(1, -60, 0, 8)
	trilho.Position = UDim2.new(0, 17, 0, 29)
	trilho.BackgroundColor3 = COR_TRILHO
	trilho.BorderSizePixel = 0
	trilho.ZIndex = 7
	trilho.Parent = row
	cantos(trilho, 4)

	local fracao = (quest.Target and quest.Target > 0)
		and math.clamp((quest.Progress or 0) / quest.Target, 0, 1) or 0

	local preenche = Instance.new("Frame")
	preenche.Size = UDim2.new(0, 0, 1, 0) -- começa em zero e anima até o valor
	preenche.BackgroundColor3 = corAcento
	preenche.BorderSizePixel = 0
	preenche.ZIndex = 8
	preenche.Parent = trilho
	cantos(preenche, 4)
	TweenService:Create(preenche, TweenInfo.new(0.45, Enum.EasingStyle.Quad),
		{ Size = UDim2.new(fracao, 0, 1, 0) }):Play()

	local progressLabel = Instance.new("TextLabel")
	progressLabel.Size = UDim2.new(0, 52, 0, 12)
	progressLabel.Position = UDim2.new(1, -60, 0, 27)
	progressLabel.BackgroundTransparency = 1
	progressLabel.Text = tostring(quest.Progress or 0) .. "/" .. tostring(quest.Target or 0)
	progressLabel.TextColor3 = concluida and COR_OK or COR_TEXTO_FRACO
	progressLabel.Font = Enum.Font.GothamMedium
	progressLabel.TextSize = 11
	progressLabel.TextXAlignment = Enum.TextXAlignment.Right
	progressLabel.ZIndex = 7
	progressLabel.Parent = row

	return row
end

-- ===== REFRESH =====
local function clearRows()
	for _, child in ipairs(body:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "EmptyLabel" then
			child:Destroy()
		end
	end
end

local isRefreshing = false
local function refreshTracker()
	if isRefreshing then return end
	isRefreshing = true

	local ok, result = pcall(function()
		return getQuestsRemote:InvokeServer()
	end)

	isRefreshing = false

	if not ok or type(result) ~= "table" then
		warn("MissionTrackerHUD: falha ao buscar missões:", result)
		return
	end

	local equipped = {}
	for _, quest in ipairs(result.Quests or {}) do
		if quest.Active then
			table.insert(equipped, quest)
		end
	end

	clearRows()
	badgeText.Text = tostring(#equipped)
	badgeText.TextColor3 = #equipped > 0 and COR_TEXTO or COR_TEXTO_FRACO
	emptyLabel.Visible = (#equipped == 0)

	for i, quest in ipairs(equipped) do
		buildTrackerRow(quest, i)
	end
end

-- ===== RECOLHER / EXPANDIR =====
local expanded = true
local function setExpanded(value)
	expanded = value
	body.Visible = expanded
	divisor.Visible = expanded
	seta.Text = expanded and "\u{25BE}" or "\u{25B8}"
end

header.MouseButton1Click:Connect(function()
	setExpanded(not expanded)
	if expanded then
		refreshTracker()
	end
end)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end
ajustarEscala()

-- ⚠️ v79 — CORRIGIDO ("ela fica atualizando periodicamente... a barra de
-- progresso reinicia a animação do 0 a cada poll, fica estranho"). O
-- refresh RECONSTRÓI as linhas do zero (clearRows + buildTrackerRow), e
-- cada linha nova sempre anima a barra a partir de 0 — então um poll a
-- cada 6s fazia a barra "piscar" (reset + preencher) mesmo quando nada
-- tinha mudado. Removido de vez: agora só atualiza em 4 momentos exatos,
-- nunca sozinho no tempo:
--   1) ao entrar no servidor (chamada única logo abaixo);
--   2) quando uma missão É CONCLUÍDA de verdade (questCompletedRemote,
--      evento do SERVIDOR — não é polling, só dispara quando acontece);
--   3) selecionar uma missão nova (QuestClient chama _G.RefreshMission-
--      Tracker depois de um SelectQuest bem-sucedido);
--   4) desselecionar uma missão (mesmo caminho — SelectQuest cobre os
--      dois sentidos);
--   + abrir/fechar o painel de escolha de missões (QuestClient chama o
--   mesmo _G.RefreshMissionTracker em openQuests/closeQuests, cobrindo
--   "abre ou fecha a aba de missões" do pedido original).
refreshTracker()

-- Exposto pro QuestClient.local.luau chamar depois de selecionar/
-- desselecionar uma missão, e ao abrir/fechar o painel — ver ali.
_G.RefreshMissionTracker = refreshTracker

questCompletedRemote.OnClientEvent:Connect(function()
	if expanded then
		refreshTracker()
	end
end)

print("✅ MissionTrackerHUD carregado.")
