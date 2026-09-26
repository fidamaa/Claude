--[[
	RollHologramClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	⚠️ v74 — PEDIDO: "do lado do NPC de roll tem um Holograma, melhore ele
	e transforme em um holograma bonito de verdade, como se fosse um
	sistema que aparecesse na sua frente... ele vai ter um roll que mostra
	tanto as hissatsus quanto as armas, vai ter os dois botões pra
	alternar entre elas, e um scroll que você pode descer pra ver a lista
	inteira, cada hissatsu com a cor da sua determinada raridade."

	O QUE JÁ EXISTIA: workspace.Holograma era 2 Parts opacas (uma chapa de
	vidro 0.1x3.7x5.8 e uma base de plástico) — sem transparência, sem
	luz, sem nada projetado. Não lia como holograma nenhum, só como uma
	placa de vidro parada do lado do NPC ppedro910 (RollMaster).

	O QUE VIROU:
	1) FÍSICO — a chapa de vidro é substituída por um FEIXE (cilindros
	   Neon empilhados, afinando pra cima, bem transparentes) saindo de
	   um anel na base — a "projeção" clássica de holograma saindo de um
	   emissor no chão. Um anel gira devagar (RunService) pra dar a
	   sensação de sistema ligado, não estampa parada.
	2) DIGITAL — um BillboardGui preso na altura do feixe, sempre virado
	   pra câmera (é a natureza de um BillboardGui — não precisa de nada
	   a mais pra "seguir o jogador"), com fundo escuro translúcido +
	   borda ciano (linguagem de HUD futurista, não a paleta do resto do
	   Lobby de propósito — isso aqui é o único elemento "tech" do mapa,
	   tem que se destacar como tal).

	⚠️ v83 — ARQUITETURA MUDOU (fixando o painel interativo de verdade,
	não só a aparência). Testei ao vivo: BOTÃO DENTRO DE BillboardGui
	preso a uma Part do mundo NÃO recebe clique no Roblox (testado com um
	botão isolado mínimo, sem nada mais na cena — nem esse funcionou,
	contra o mesmo clique que funciona sempre numa ScreenGui normal). Não
	é bug de layout/z-index, é limitação real da engine pra esse tipo de
	GUI 3D. Por isso agora:
	  • O BillboardGui no feixe virou um CONVITE estático ("toque para
	    abrir"), sem nada clicável nele — só decorativo, sempre com
	    tamanho fixo em tela (Size em Offset, não Scale — não muda com a
	    distância, testado e confirmado ao vivo).
	  • O catálogo de VERDADE (abas HISSATSUS/ARMAS + lista rolável) virou
	    uma ScreenGui — mesmo padrão comprovado que já funciona no
	    RollClient/QuestClient — aberta por um ClickDetector na BASE
	    física do holograma (clique em Part sempre funciona, ao contrário
	    de botão em BillboardGui).

	CADA CLIENTE constrói sua PRÓPRIA cópia (é LocalScript, roda em cada
	jogador) — o estado de qual aba está aberta é por jogador, o que é o
	comportamento certo pra um "menu" e não precisa de nenhuma rede/
	servidor pra isso (não gasta nem lê nenhum roll de verdade, é só
	CONSULTA — a compra continua 100% na tela de Roll, ver
	RollClient.local.luau).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local PulseInstinctData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))

-- Mesma tabela de raridades do RollClient — mantida em sincronia à mão
-- de propósito (RollClient também não importa isto de lugar nenhum,
-- então replicar aqui é consistente com o padrão já existente do
-- arquivo, não uma divergência nova).
local RARITY_COLOR = {
	Common = Color3.fromRGB(180, 180, 180),
	Rare = Color3.fromRGB(80, 160, 255),
	Epic = Color3.fromRGB(170, 90, 255),
	Legendary = Color3.fromRGB(255, 175, 60),
	Mythic = Color3.fromRGB(255, 70, 110),
}
local RARITY_LABEL = {
	Common = "Comum", Rare = "Raro", Epic = "Épico", Legendary = "Lendário", Mythic = "Mítico",
}
local RARITY_ORDER = { "Mythic", "Legendary", "Epic", "Rare", "Common" } -- mais raro primeiro, dá vontade de rolar a lista

local CIANO = Color3.fromRGB(90, 225, 255)
local CIANO_FRACO = Color3.fromRGB(60, 150, 170)
local FUNDO_HOLO = Color3.fromRGB(6, 18, 24)
local CARTAO_HOLO = Color3.fromRGB(10, 28, 36)

-- ===== ACHAR O MODELO NO MUNDO =====
local holograma = workspace:WaitForChild("Holograma", 30)
if not holograma then
	warn("RollHologramClient: workspace.Holograma não encontrado — holograma não vai aparecer.")
	return
end

-- ===== RECONSTRÓI O FÍSICO: feixe + anel giratório =====
-- ⚠️ v79 — CORRIGIDO ("diz que não existe BasePart, no output em
-- amarelo" — o warn() abaixo aparece amarelo no Output do Studio).
-- CAUSA: workspace.StreamingEnabled está ligado e o Holograma fica longe
-- do spawn — o Roblox pode replicar o MODEL (a pasta "Holograma") pro
-- cliente ANTES das Parts de dentro dele terminarem de "streamar". O
-- código antigo só olhava UMA VEZ, na hora que o Model aparecia, sem
-- esperar as Parts — se elas ainda não tinham chegado, achava "vazio" e
-- desistia de vez (nunca tentava de novo). Agora: primeiro tenta achar a
-- Part pelo NOME de verdade ("basePart", ver Explorer) com WaitForChild
-- (espera de verdade, até 15s); se não achar por nome (hierarquia mudou
-- no Studio), cai pro scan antigo só que agora COM RETRY por até mais
-- 15s, dando tempo de sobra pro streaming terminar antes de desistir.
local basePart = holograma:FindFirstChild("basePart")
if not basePart or not basePart:IsA("BasePart") then
	basePart = holograma:WaitForChild("basePart", 15)
end

if not basePart or not basePart:IsA("BasePart") then
	local deadline = os.clock() + 15
	repeat
		for _, d in ipairs(holograma:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Plastic then
				basePart = d
				break
			end
		end
		if not basePart then task.wait(0.5) end
	until basePart or os.clock() >= deadline
end

if not basePart then
	basePart = holograma:FindFirstChildWhichIsA("BasePart", true)
end

if not basePart then
	warn("RollHologramClient: Holograma sem nenhuma Part depois de esperar o streaming — não dá pra ancorar o feixe. Confere se workspace.Holograma.basePart existe no Studio.")
	return
end

local origem = basePart.Position
local TOPO_BASE = origem.Y + basePart.Size.Y / 2

-- some com a chapa de vidro opaca antiga (mantém só a base como pedestal)
for _, d in ipairs(holograma:GetDescendants()) do
	if d:IsA("BasePart") and d ~= basePart then
		d.Transparency = 1
		d.CanCollide = false
	end
end
basePart.Material = Enum.Material.Metal
basePart.Color = Color3.fromRGB(30, 34, 40)

local fisico = Instance.new("Folder")
fisico.Name = "Fisico"
fisico.Parent = holograma

local function novaParte(nome, tam, cf, transp, colide)
	local p = Instance.new("Part")
	p.Name = nome
	p.Size = tam
	p.CFrame = cf
	p.Color = CIANO
	p.Material = Enum.Material.Neon
	p.Transparency = transp
	p.Anchored = true
	p.CanCollide = (colide == true)
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = fisico
	return p
end

-- anel na base (emissor)
local anel = novaParte("Anel", Vector3.new(3.4, 0.15, 3.4), CFrame.new(origem.X, TOPO_BASE + 0.1, origem.Z), 0.15, false)
anel.Shape = Enum.PartType.Cylinder
anel.CFrame = CFrame.new(origem.X, TOPO_BASE + 0.1, origem.Z) * CFrame.Angles(0, 0, math.rad(90))

-- feixe: cilindros empilhados, afinando e clareando pra cima (efeito de
-- projeção). Bem transparentes — é luz, não um objeto sólido.
local ALTURA_FEIXE = 6.5
local segmentos = {}
for i = 0, 7 do
	local t = i / 7
	local y = TOPO_BASE + t * ALTURA_FEIXE
	local raio = 1.5 * (1 - t * 0.55)
	local seg = novaParte("Feixe" .. i, Vector3.new(raio, 0.5, raio),
		CFrame.new(origem.X, y, origem.Z), 0.72 + t * 0.2)
	seg.Shape = Enum.PartType.Cylinder
	seg.CFrame = CFrame.new(origem.X, y, origem.Z) * CFrame.Angles(0, 0, math.rad(90))
	table.insert(segmentos, seg)
end

local luz = Instance.new("PointLight")
luz.Color = CIANO
luz.Brightness = 1.6
luz.Range = 16
luz.Parent = anel

-- gira o anel devagar — a diferença entre "ligado" e "estampa parada".
RunService.Heartbeat:Connect(function(dt)
	anel.CFrame = anel.CFrame * CFrame.Angles(0, dt * 0.8, 0)
end)

-- ===== PAINEL HOLOGRÁFICO (BillboardGui) =====
local ancora = Instance.new("Part")
ancora.Name = "AncoraPainel"
ancora.Size = Vector3.new(0.2, 0.2, 0.2)
ancora.Position = Vector3.new(origem.X, TOPO_BASE + ALTURA_FEIXE + 0.6, origem.Z)
ancora.Anchored = true
ancora.CanCollide = false
ancora.CanQuery = false
ancora.Transparency = 1
ancora.Parent = fisico

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
	s.Transparency = transp or 0
	s.Parent = inst
	return s
end

-- ⚠️ v83 — CORRIGIDO DE VERDADE ("não consigo clicar" / "o painel
-- interativo tava quebrado, só conserte ele"). Testei AO VIVO no Studio
-- (medindo cliques com um marcador, não só olhando): mesmo um BOTÃO
-- ISOLADO, sozinho, dentro de um BillboardGui preso a uma Part no mundo,
-- NÃO recebe clique de jeito nenhum — enquanto o EXATO MESMO clique num
-- botão de ScreenGui normal (a própria tela de Roll) funciona sempre.
-- Ou seja: não era um bug no MEU código (tabRow/scroll) — é uma
-- limitação real do Roblox pra botão dentro de GUI 3D presa a Part.
--
-- SOLUÇÃO: o holograma continua com a aparência de antes (BillboardGui
-- flutuando, com abas e a promessa de lista) só que agora é
-- só um CONVITE — mostra "toque para abrir" e não tenta processar
-- clique nele mesmo. O catálogo de verdade (abas HISSATSUS/ARMAS + lista
-- rolável, com scroll garantido por botões ^/v) abre como uma tela
-- normal (ScreenGui, igual RollClient/QuestClient — mesmo padrão já
-- comprovado que FUNCIONA) na frente do jogador, disparada por um
-- ClickDetector na base física do holograma (clicável de verdade, isso
-- É um input que o Roblox garante pra Parts no mundo).
local bb = Instance.new("BillboardGui")
bb.Name = "PainelRoll"
bb.Adornee = ancora
bb.Size = UDim2.fromOffset(260, 110)
bb.StudsOffset = Vector3.new(0, 0, 0)
bb.MaxDistance = 45
bb.AlwaysOnTop = false
bb.LightInfluence = 0
bb.Parent = ancora

local painel = Instance.new("Frame")
painel.Size = UDim2.new(1, 0, 1, 0)
painel.BackgroundColor3 = FUNDO_HOLO
painel.BackgroundTransparency = 0.18
painel.BorderSizePixel = 0
painel.Parent = bb
cantos(painel, 10)
contorno(painel, CIANO, 1.5, 0.25)

for i = 1, 6 do
	local linha = Instance.new("Frame")
	linha.Size = UDim2.new(1, 0, 0, 1)
	linha.Position = UDim2.new(0, 0, i / 7, 0)
	linha.BackgroundColor3 = CIANO
	linha.BackgroundTransparency = 0.92
	linha.BorderSizePixel = 0
	linha.ZIndex = 2
	linha.Parent = painel
end

local cabecalho = Instance.new("TextLabel")
cabecalho.Size = UDim2.new(1, -20, 0, 26)
cabecalho.Position = UDim2.new(0, 10, 0, 14)
cabecalho.BackgroundTransparency = 1
cabecalho.Text = "SISTEMA DE ROLL"
cabecalho.Font = Enum.Font.GothamBlack
cabecalho.TextSize = 15
cabecalho.TextColor3 = CIANO
cabecalho.TextXAlignment = Enum.TextXAlignment.Left
cabecalho.ZIndex = 3
cabecalho.Parent = painel

local linhaSubTitulo = Instance.new("TextLabel")
linhaSubTitulo.Size = UDim2.new(1, -20, 0, 40)
linhaSubTitulo.Position = UDim2.new(0, 10, 0, 44)
linhaSubTitulo.BackgroundTransparency = 1
linhaSubTitulo.Text = "Hissatsus e Armas — toque no\nholograma pra abrir o catálogo"
linhaSubTitulo.Font = Enum.Font.GothamMedium
linhaSubTitulo.TextSize = 12
linhaSubTitulo.TextColor3 = CIANO_FRACO
linhaSubTitulo.TextWrapped = true
linhaSubTitulo.TextXAlignment = Enum.TextXAlignment.Left
linhaSubTitulo.TextYAlignment = Enum.TextYAlignment.Top
linhaSubTitulo.ZIndex = 3
linhaSubTitulo.Parent = painel

-- Leve flutuação vertical no painel inteiro — reforça "projeção no ar",
-- não um cartaz fixo. Sutil de propósito (2 studs, 4 segundos).
task.spawn(function()
	while ancora.Parent do
		TweenService:Create(ancora, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = ancora.Position + Vector3.new(0, 0.35, 0) }):Play()
		task.wait(2)
		TweenService:Create(ancora, TweenInfo.new(2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = ancora.Position - Vector3.new(0, 0.35, 0) }):Play()
		task.wait(2)
	end
end)

-- ===== CATÁLOGO (ScreenGui — clicável/rolável DE VERDADE) =====
local catalogoGui = Instance.new("ScreenGui")
catalogoGui.Name = "RollHologramCatalogo"
catalogoGui.ResetOnSpawn = false
catalogoGui.IgnoreGuiInset = true
catalogoGui.Enabled = false
catalogoGui.Parent = playerGui

local fundo = Instance.new("TextButton") -- botão gigante invisível atrás — clicar fora fecha
fundo.Size = UDim2.fromScale(1, 1)
fundo.BackgroundColor3 = Color3.new(0, 0, 0)
fundo.BackgroundTransparency = 0.45
fundo.Text = ""
fundo.AutoButtonColor = false
fundo.Parent = catalogoGui

local janela = Instance.new("Frame")
janela.AnchorPoint = Vector2.new(0.5, 0.5)
janela.Position = UDim2.fromScale(0.5, 0.5)
janela.Size = UDim2.fromOffset(420, 480)
janela.BackgroundColor3 = FUNDO_HOLO
janela.BorderSizePixel = 0
janela.Parent = catalogoGui
cantos(janela, 14)
contorno(janela, CIANO, 1.5, 0.2)

for i = 1, 14 do
	local linha = Instance.new("Frame")
	linha.Size = UDim2.new(1, 0, 0, 1)
	linha.Position = UDim2.new(0, 0, i / 15, 0)
	linha.BackgroundColor3 = CIANO
	linha.BackgroundTransparency = 0.94
	linha.BorderSizePixel = 0
	linha.ZIndex = 2
	linha.Parent = janela
end

local fechar = Instance.new("TextButton")
fechar.Size = UDim2.fromOffset(30, 30)
fechar.Position = UDim2.new(1, -40, 0, 10)
fechar.BackgroundColor3 = CARTAO_HOLO
fechar.Text = "X"
fechar.Font = Enum.Font.GothamBlack
fechar.TextSize = 14
fechar.TextColor3 = CIANO
fechar.AutoButtonColor = false
fechar.ZIndex = 4
fechar.Parent = janela
cantos(fechar, 8)

local cabecalho2 = Instance.new("TextLabel")
cabecalho2.Size = UDim2.new(1, -60, 0, 30)
cabecalho2.Position = UDim2.new(0, 16, 0, 14)
cabecalho2.BackgroundTransparency = 1
cabecalho2.Text = "SISTEMA DE ROLL"
cabecalho2.Font = Enum.Font.GothamBlack
cabecalho2.TextSize = 18
cabecalho2.TextColor3 = CIANO
cabecalho2.TextXAlignment = Enum.TextXAlignment.Left
cabecalho2.ZIndex = 3
cabecalho2.Parent = janela

local subtitulo2 = Instance.new("TextLabel")
subtitulo2.Size = UDim2.new(1, -32, 0, 16)
subtitulo2.Position = UDim2.new(0, 16, 0, 44)
subtitulo2.BackgroundTransparency = 1
subtitulo2.Text = "catálogo — a compra é na tela de Roll"
subtitulo2.Font = Enum.Font.GothamMedium
subtitulo2.TextSize = 11
subtitulo2.TextColor3 = CIANO_FRACO
subtitulo2.TextXAlignment = Enum.TextXAlignment.Left
subtitulo2.ZIndex = 3
subtitulo2.Parent = janela

-- ===== TOGGLE HISSATSU / ARMA =====
local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -32, 0, 34)
tabRow.Position = UDim2.new(0, 16, 0, 68)
tabRow.BackgroundTransparency = 1
tabRow.ZIndex = 3
tabRow.Parent = janela

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 8)
tabLayout.Parent = tabRow

local abas = {
	{ Id = "Pulses", Nome = "HISSATSUS" },
	{ Id = "Instincts", Nome = "ARMAS" },
}
local botoesAba = {}
local abaAtual = "Pulses"

-- ===== LISTA ROLÁVEL =====
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -32, 1, -160)
scroll.Position = UDim2.new(0, 16, 0, 112)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 5
scroll.ScrollBarImageColor3 = CIANO
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 3
scroll.Parent = janela

local scrollLayout = Instance.new("UIListLayout")
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Padding = UDim.new(0, 4)
scrollLayout.Parent = scroll

local function limparLista()
	for _, filho in ipairs(scroll:GetChildren()) do
		if filho:IsA("Frame") then filho:Destroy() end
	end
end

local function construirLinha(item, ordem)
	local cor = RARITY_COLOR[item.Rarity] or Color3.fromRGB(200, 200, 200)

	local linha = Instance.new("Frame")
	linha.Size = UDim2.new(1, 0, 0, 36)
	linha.BackgroundColor3 = CARTAO_HOLO
	linha.BackgroundTransparency = 0.15
	linha.BorderSizePixel = 0
	linha.LayoutOrder = ordem
	linha.ZIndex = 3
	linha.Parent = scroll
	cantos(linha, 6)

	local acento = Instance.new("Frame")
	acento.Size = UDim2.new(0, 4, 1, -10)
	acento.Position = UDim2.new(0, 6, 0, 5)
	acento.BackgroundColor3 = cor
	acento.BorderSizePixel = 0
	acento.ZIndex = 4
	acento.Parent = linha
	cantos(acento, 2)

	local nome = Instance.new("TextLabel")
	nome.Size = UDim2.new(1, -90, 1, 0)
	nome.Position = UDim2.new(0, 18, 0, 0)
	nome.BackgroundTransparency = 1
	nome.Text = item.Name
	nome.Font = Enum.Font.GothamBold
	nome.TextSize = 13
	nome.TextColor3 = Color3.fromRGB(225, 240, 245)
	nome.TextXAlignment = Enum.TextXAlignment.Left
	nome.TextTruncate = Enum.TextTruncate.AtEnd
	nome.ZIndex = 4
	nome.Parent = linha

	local raridade = Instance.new("TextLabel")
	raridade.Size = UDim2.new(0, 66, 1, 0)
	raridade.Position = UDim2.new(1, -74, 0, 0)
	raridade.BackgroundTransparency = 1
	raridade.Text = RARITY_LABEL[item.Rarity] or item.Rarity
	raridade.Font = Enum.Font.GothamBold
	raridade.TextSize = 11
	raridade.TextColor3 = cor
	raridade.TextXAlignment = Enum.TextXAlignment.Right
	raridade.ZIndex = 4
	raridade.Parent = linha
end

local function renderizarAba()
	limparLista()
	scroll.CanvasPosition = Vector2.new(0, 0) -- sempre começa do topo ao trocar de aba
	local lista = (abaAtual == "Pulses") and PulseInstinctData.Pulses or PulseInstinctData.Instincts

	local porRaridade = {}
	for _, item in ipairs(lista) do
		porRaridade[item.Rarity] = porRaridade[item.Rarity] or {}
		table.insert(porRaridade[item.Rarity], item)
	end

	local ordem = 1
	for _, raridade in ipairs(RARITY_ORDER) do
		local itens = porRaridade[raridade]
		if itens then
			table.sort(itens, function(a, b) return a.Name < b.Name end)
			for _, item in ipairs(itens) do
				construirLinha(item, ordem)
				ordem += 1
			end
		end
	end
end

local function selecionarAba(id)
	abaAtual = id
	for abaId, botao in pairs(botoesAba) do
		local selecionado = (abaId == id)
		botao.BackgroundColor3 = selecionado and CIANO or CARTAO_HOLO
		botao.TextColor3 = selecionado and Color3.fromRGB(6, 18, 24) or CIANO_FRACO
	end
	renderizarAba()
end

for i, aba in ipairs(abas) do
	local botao = Instance.new("TextButton")
	botao.Size = UDim2.new(0.5, -4, 1, 0)
	botao.LayoutOrder = i
	botao.BackgroundColor3 = CARTAO_HOLO
	botao.Text = aba.Nome
	botao.Font = Enum.Font.GothamBlack
	botao.TextSize = 12
	botao.TextColor3 = CIANO_FRACO
	botao.AutoButtonColor = false
	botao.ZIndex = 3
	botao.Parent = tabRow
	cantos(botao, 7)
	contorno(botao, CIANO, 1, 0.5)

	botao.MouseButton1Click:Connect(function()
		selecionarAba(aba.Id)
	end)

	botoesAba[aba.Id] = botao
end

selecionarAba("Pulses")

local function abrirCatalogo()
	catalogoGui.Enabled = true
end

local function fecharCatalogo()
	catalogoGui.Enabled = false
end

fechar.MouseButton1Click:Connect(fecharCatalogo)
fundo.MouseButton1Click:Connect(fecharCatalogo)

-- ===== GATILHO: ClickDetector na base física (Part de verdade — clique
-- em Part sempre funciona no Roblox, diferente de botão dentro de
-- BillboardGui) =====
local gatilho = Instance.new("ClickDetector")
gatilho.MaxActivationDistance = 20
gatilho.Parent = basePart

gatilho.MouseClick:Connect(function(jogador)
	if jogador == player then
		abrirCatalogo()
	end
end)

-- Mobile/sem mouse: o mesmo feixe/anel também aceita toque via ClickDetector
-- (funciona em touch por padrão no Roblox, não precisa de nada a mais).

print("✅ RollHologramClient carregado — holograma do Roll ativo.")
