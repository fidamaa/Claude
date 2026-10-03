--[[
	RollClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Preenche a GUI de Roll que você já montou no Studio (igual o
	ShopClient.lua faz com a Loja — não cria nada do zero, só liga o que
	já existe no Explorer). Estrutura esperada:

		roll (ScreenGui)
		  └─ frame (Frame)
		      ├─ cabeçalho (Frame)
		      │    ├─ CloseButton (GuiButton)
		      │    └─ Texto (TextLabel)
		      ├─ instinct (Frame)
		      │    ├─ spin (TextButton)
		      │    ├─ rng (ImageLabel)
		      │    ├─ desc (TextLabel)
		      │    └─ name (TextLabel)
		      ├─ pulse (Frame) — mesma estrutura de "instinct"
		      │    ├─ spin (TextButton)
		      │    ├─ rng (ImageLabel)
		      │    ├─ desc (TextLabel)
		      │    └─ name (TextLabel)
		      ├─ rarities (Frame) — escondido até clicar em "help"
		      │    ├─ Common (TextLabel)
		      │    ├─ Rare (TextLabel)
		      │    ├─ Epic (TextLabel)
		      │    ├─ Legendary (TextLabel)
		      │    └─ Mythic (TextLabel)
		      ├─ help (GuiButton) — info do roll normal (pago com dinheiro)
		      └─ helpRobux (GuiButton) — AINDA PRECISA SER CRIADO NO STUDIO:
		           duplique o "help" ali do lado, renomeie a cópia pra
		           "helpRobux" e posicione ela logo abaixo do "help"
		           original (só a INSTÂNCIA — GUI não sincroniza sozinha,
		           só scripts, por isso não dá pra criar ela por aqui).
		           Vira o botão que compra 1 roll pago com Robux de
		           verdade (Developer Product, ver LobbyConfig.lua).

	NOVO: o botão "Comprar Roll" (com dinheiro) e o label "Rolls: N" agora
	são CRIADOS POR CÓDIGO aqui dentro de "cabeçalho" (não precisa criar
	nada novo no Studio pra isso — só scripts sincronizam pela ponte, então
	construir por Instance.new garante que chega no seu Studio). Antes essa
	compra era um card dentro da Loja (Shop) — foi removida de lá.

	O QUE JÁ FUNCIONA:
	- help alterna (mostra/esconde) o frame "rarities", preenchendo as 5
	  labels com a raridade + a chance (%) de cada uma.
	- helpRobux (se existir) chama MarketplaceService:PromptProductPurchase
	  pro Developer Product de 40 Robux configurado em LobbyConfig.lua — a
	  compra em si é confirmada no servidor (RollServer.lua/ProcessReceipt),
	  que credita 1 roll pro jogador.
	- CloseButton fecha a tela de roll.
	- spin (tanto de "instinct" quanto de "pulse") gasta 1 crédito de roll
	  (comprado na Loja com dinheiro OU com o helpRobux) e sorteia um item
	  da respectiva lista abaixo, com uma animaçãozinha de "girando" antes
	  de mostrar o resultado (nome + descrição + cor da raridade no rng).
	  Sem crédito, avisa em vez de girar.

	INSTINCT_POOL e PULSE_POOL têm os Pulsos/Instintos de verdade (10
	Common, 7 Rare, 5 Epic, 3 Legendary, 2 Mythic cada, 27 no total cada
	um) — cada entrada já vem com números exatos (não "aumenta o chute",
	e sim "força final = KICK_MAX_FORCE * 1.3"), pensados em cima das
	constantes que já existem em FootballConfig.lua (place Game):
	KICK_MAX_FORCE=145, KICK_CHARGE_RATE=140, CURVE_STRENGTH=45,
	CURVE_DURATION=0.7, TACKLE_BASE_CHANCE=0.65, TACKLE_RANGE=7,
	HEADER_FORCE=65, HEADER_RANGE=6, ANKLE_BREAKER_RANGE=5,
	ANKLE_BREAKER_STUN=0.5, DRIBBLE_MOVE_MAX_DISTANCE=9,
	DRIBBLE_MOVE_COOLDOWN=0.5, POSSESSION_PICKUP_RADIUS=6,
	SPRINT_SPEED=38, NORMAL_SPEED=22, PASS_FORCE=55.

	A DIFERENÇA ENTRE OS DOIS:
	- Instinto = PASSIVO condicional, sem cooldown, sem botão nenhum —
	  fica sempre "ligado" e só faz efeito quando a Condition bate (ex.:
	  "distância até o gol adversário <=18 studs no momento do chute").
	  Effect.Type = "ConditionalPassive"; Effect.Condition é a checagem
	  exata a fazer, Effect.Result é a mudança exata a aplicar (com
	  números). Isso é 1 `if` a mais dentro da função que já existe
	  (KickBall, TackleAttempt, HeaderAttempt, etc.) — não precisa de
	  timer nem de estado novo, é só ler o Instinto equipado do jogador
	  e checar a condição no momento da ação.
	- Pulso = ATIVO, o jogador precisa ACIONAR. ⚠️ v3 (modelo atual, ver
	  PulseController.legacy.luau no place Game): apertar o botão do
	  Pulso (Q/E linha, R goleiro dentro da própria área) já EXECUTA a
	  ação sozinho, com auto-mira/auto-alvo — sem separar "mirar" de
	  "confirmar". Alguns Pulsos têm um COMBO DE TECLAS embutido no
	  wind-up da própria ação (ex: Q → E → Q): cada passo tem sua
	  janelinha própria, e apertar a tecla certa dentro dela conta como
	  acerto. Tecla errada ou passo perdido faz SÓ aquele passo falhar —
	  o combo continua, e a ação SEMPRE dispara no fim: acertou todos os
	  passos = "Perfeito", qualquer outra coisa = "Bom" (nunca é um whiff
	  total). Se o wind-up total passar de 2s, o jogador fica
	  INVULNERÁVEL a desarme durante ele inteiro. Do aperto até a ação
	  resolver, no máximo 5s (o maior é o Chute Fatal, em 2.7s). Nenhum
	  Pulso é mais 1x por partida — os Míticos recarregam com cooldown
	  normal.

	O QUE AINDA FALTA (de propósito, é o próximo passo):
	- O RESULTADO do sorteio (qual item saiu) ainda é decidido aqui no
	  cliente. O que JÁ é autoritativo no servidor é o crédito em si
	  (RollServer.lua): dinheiro e Robux só viram um roll depois de
	  cobrados de verdade — ninguém gira de graça mexendo no cliente. Mas
	  o item sorteado ainda não é GUARDADO em lugar nenhum (não tem
	  inventário/equipar ainda), e nenhum Effect é aplicado de verdade em
	  campo — hoje cada um é só a descrição + metadado de referência pra
	  quando o sistema de equipar/ativar (no Game place) for construído
	  em cima disso. Quando o inventário existir, o sorteio TAMBÉM
	  precisa virar 100% servidor (não só o crédito).
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

-- ⚠️ v110: string.upper não põe acento em maiúscula ("Fúria" virava "FúRIA").
-- Converte também as letras acentuadas (UTF-8 à..þ → À..Þ).
local function maiusculas(s)
	s = string.upper(tostring(s))
	return (s:gsub("\195([\160-\190])", function(c)
		local b = string.byte(c)
		if b ~= 183 then return "\195" .. string.char(b - 32) end
	end))
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local LobbyConfig = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

local rollEvents = ReplicatedStorage:WaitForChild("RollEvents")
local GetRollCredits = rollEvents:WaitForChild("GetRollCredits")
local ConsumeRollCredit = rollEvents:WaitForChild("ConsumeRollCredit")
local RollAbility = rollEvents:WaitForChild("RollAbility") -- sorteio 100% servidor (ver RollServer.lua)
local UpdateRollCreditsEvent = rollEvents:WaitForChild("UpdateRollCredits")
local GetEquippedAbilities = rollEvents:WaitForChild("GetEquippedAbilities") -- o que já estava equipado antes de abrir a tela (ver RollServer.lua)
local BuyRoll = rollEvents:WaitForChild("BuyRoll") -- MOVIDO da Loja pra cá: compra 1 roll com dinheiro (ver RollServer.lua)

-- ========================================
-- RARIDADES (peso = quanto maior, mais comum; some dos pesos = 100)
-- ========================================
local RARITIES = {
	{ Name = "Common", Label = "Comum", Weight = 65, Color = Color3.fromRGB(180, 180, 180) },
	{ Name = "Rare", Label = "Raro", Weight = 25, Color = Color3.fromRGB(80, 160, 255) },
	{ Name = "Epic", Label = "Épico", Weight = 7, Color = Color3.fromRGB(170, 90, 255) },
	{ Name = "Legendary", Label = "Lendário", Weight = 2.5, Color = Color3.fromRGB(255, 175, 60) },
	{ Name = "Mythic", Label = "Mítico", Weight = 0.5, Color = Color3.fromRGB(255, 70, 110) },
}

local TOTAL_WEIGHT = 0
for _, rarity in ipairs(RARITIES) do
	TOTAL_WEIGHT += rarity.Weight
end

local RARITY_BY_NAME = {}
for _, rarity in ipairs(RARITIES) do
	RARITY_BY_NAME[rarity.Name] = rarity
end

-- ========================================
-- INSTINTOS — passivo condicional, SEM cooldown, SEM botão. Effect.
-- Condition é a checagem exata (com números) e Effect.Result é a
-- mudança exata a aplicar quando ela bate. "Distância do gol" sempre
-- medida até o centro do gol adversário (BLUE_GOAL_NAME/GolAmarelo).
-- ========================================
local PulseInstinctData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))

-- ⚠️ v4: este arquivo NÃO tem mais lista própria de Pulsos/Instintos.
-- Antes existiam aqui DUAS tabelas literais (27 Pulsos e 34 Instintos)
-- copiadas à mão do PulseInstinctData.luau — e elas já estavam fora de
-- sincronia de verdade: o "Pulso do Canto Certo" ainda aparecia como
-- Common depois de ter virado Epic na v3.4, e vários Pulsos que já não
-- existiam mais continuavam listados aqui. Toda vez que a lista de
-- verdade mudava, esta tela mentia pro jogador.
-- Agora os dois pools são construídos a partir do PulseInstinctData, que
-- é a fonte única: mexeu lá, a tela de Roll acompanha sozinha.
local function poolFrom(lista)
	local pool = {}
	for _, def in ipairs(lista) do
		table.insert(pool, {
			Name = def.Name,
			Rarity = def.Rarity,
			Element = def.Element, -- ⚠️ v107: mostrado no cartão do roll
			Posicao = def.Posicao, -- ⚠️ v110: posição da Arma (GK/DF/MF/FW), mostrada no cartão
			Description = def.Description or "",
			Habilidades = def.Habilidades, -- as 1-2 habilidades, se a tela quiser listar depois
			Image = def.Image, -- ⚠️ v77: arte de verdade (ver pedido do usuário) — nil pras que ainda não têm
		})
	end
	return pool
end

local INSTINCT_POOL = poolFrom(PulseInstinctData.Instincts)
local PULSE_POOL = poolFrom(PulseInstinctData.Pulses)

-- Agrupa cada pool por raridade, pra sortear "raridade primeiro, item
-- dentro dela depois" (assim dá pra ter várias entradas na mesma
-- raridade no futuro sem mudar os pesos).
local function groupByRarity(pool)
	local grouped = {}
	for _, item in ipairs(pool) do
		grouped[item.Rarity] = grouped[item.Rarity] or {}
		table.insert(grouped[item.Rarity], item)
	end
	return grouped
end

local INSTINCT_BY_RARITY = groupByRarity(INSTINCT_POOL)
local PULSE_BY_RARITY = groupByRarity(PULSE_POOL)

-- ========================================
-- RNG
-- ========================================
local random = Random.new()

local function rollRarity()
	local roll = random:NextNumber(0, TOTAL_WEIGHT)
	local cumulative = 0
	for _, rarity in ipairs(RARITIES) do
		cumulative += rarity.Weight
		if roll <= cumulative then
			return rarity.Name
		end
	end
	return RARITIES[1].Name -- fallback (não deveria acontecer)
end

local function rollItem(groupedPool)
	local rarityName = rollRarity()
	local candidates = groupedPool[rarityName]
	if not candidates or #candidates == 0 then
		-- Essa raridade ainda não tem nenhum item na pool (placeholder
		-- incompleto) — tenta de novo com outra raridade em vez de
		-- travar o roll.
		return rollItem(groupedPool)
	end
	return candidates[random:NextInteger(1, #candidates)]
end

-- ========================================
-- ACHAR A GUI JÁ PRONTA
-- ========================================
local rollGui = playerGui:WaitForChild("roll")
local frame = rollGui:WaitForChild("frame")
local cabecalho = frame:WaitForChild("cabeçalho")
local closeButton = cabecalho:FindFirstChild("CloseButton")
local instinctFrame = frame:WaitForChild("instinct")
local pulseFrame = frame:WaitForChild("pulse")
local raritiesFrame = frame:WaitForChild("rarities")
local helpButton = frame:WaitForChild("help")
local helpRobuxButton = frame:FindFirstChild("helpRobux")

if not helpRobuxButton then
	warn("RollClient: não encontrei 'helpRobux' dentro de frame — duplique o botão 'help' no Studio, renomeie a cópia pra 'helpRobux' e posicione abaixo do help original (o roll com Robux não vai ter botão até isso existir).")
end

-- ========================================
-- ⚠️ v73 — REESTILIZA A GUI MONTADA NO STUDIO.
-- PEDIDO: "melhora a HUD de missões, você consegue interferir diretamente
-- na HUD de Roll?"
--
-- Essa GUI foi montada NA MÃO no Studio (frame/cabeçalho/instinct/pulse/
-- rarities), e por isso NUNCA passou pela mesma paleta que o resto do
-- Lobby (MatchmakingClient/MissionTrackerHUD v72-73): fundo cinza-médio
-- chapado (0.22/0.31/0.42/0.52 — quatro tons de cinza sem relação entre
-- si), texto PRETO em cima de cinza médio (contraste ruim), fontes
-- avulsas (Highway, Cartoon, "Unknown") que não existem em nenhuma outra
-- tela, CloseButton com TextSize 68 (o "X" literalmente estourava o
-- botão), e as cores de raridade do painel de ajuda não batendo com as
-- da tabela RARITIES logo abaixo (Épico aqui é roxo, lá no Studio tinha
-- ficado magenta puro; Lendário aqui é laranja, lá tinha ficado amarelo
-- puro).
--
-- Objetos de GUI (Frame/TextLabel/...) NÃO sincronizam do Studio pro
-- disco — só Scripts. Não dá pra "consertar" isso editando um arquivo
-- .rbxm à parte. O que dá — e é o que este bloco faz — é o PRÓPRIO
-- SCRIPT reestilizar os objetos já existentes assim que os acha, uma vez
-- só, na carga. A lógica de girar/mostrar resultado (mais abaixo) continua
-- escrevendo Text/TextColor3 em cima dessa base nova, sem precisar mudar
-- nada nela.
-- ========================================
local function cantosR(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end

local function contornoR(inst, cor, espessura, transparencia)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = espessura or 1
	s.Transparency = transparencia or 0.15
	s.Parent = inst
	return s
end

-- Mesma paleta do MatchmakingClient/MissionTrackerHUD (v72-73) — é isso
-- que faz as três telas lerem como parte do mesmo Lobby.
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

-- ----- painel principal -----
frame.BackgroundColor3 = COR_PAINEL
cantosR(frame, 10)
contornoR(frame, COR_BORDA, 1, 0.15)

-- ----- cabeçalho -----
cabecalho.BackgroundColor3 = COR_CARTAO
cabecalho.BorderSizePixel = 0

-- ⚠️ v74 — PEDIDO: "remova o texto do cabeçalho, ou mantenha apenas em
-- 'Roll'". Era um label só ("PULSE ... INSTINCT") espaçado à mão pra
-- fingir dois títulos — texto preto, ilegível no fundo escuro novo, e a
-- informação real (o que é cada coluna) virou texto de verdade embaixo
-- de cada painel, não mais só um nome ali em cima. Vira "ROLL".
local textoCabecalho = cabecalho:FindFirstChild("Texto")
if textoCabecalho and textoCabecalho:IsA("TextLabel") then
	textoCabecalho.Text = "ROLL"
	textoCabecalho.Font = Enum.Font.GothamBlack
	textoCabecalho.TextColor3 = COR_TEXTO
	textoCabecalho.TextSize = 20
	textoCabecalho.TextXAlignment = Enum.TextXAlignment.Left
end

if closeButton and closeButton:IsA("GuiButton") then
	closeButton.BackgroundColor3 = COR_CARTAO_ALT
	closeButton.Text = "X" -- × desenhado, não a letra "X" estourando o botão (era TextSize 68)
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 18
	closeButton.TextColor3 = COR_TEXTO
	if not closeButton:FindFirstChildOfClass("UICorner") then cantosR(closeButton, 25) end
end

-- ----- botões "?" (help / helpRobux) -----
for _, botao in ipairs({ helpButton, helpRobuxButton }) do
	if botao and botao:IsA("GuiButton") then
		botao.BackgroundColor3 = COR_CARTAO_ALT
		botao.TextColor3 = COR_ACENTO
		botao.Font = Enum.Font.GothamBlack
		botao.TextSize = 16
		if not botao:FindFirstChildOfClass("UICorner") then cantosR(botao, 18) end
	end
end

-- ----- painel de raridades -----
raritiesFrame.BackgroundColor3 = COR_PAINEL
cantosR(raritiesFrame, 8)
contornoR(raritiesFrame, COR_BORDA, 1, 0.2)
-- cada linha (Common/Rare/Epic/Legendary/Mythic) vira um cartão escuro —
-- a COR da raridade continua entrando pelo TEXTO (loop mais abaixo já
-- faz isso com a tabela RARITIES certa), não mais por um banho de cor
-- translúcida que nem combinava com a tabela.
for _, nomeRaridade in ipairs({ "Common", "Rare", "Epic", "Legendary", "Mythic" }) do
	local label = raritiesFrame:FindFirstChild(nomeRaridade)
	if label and label:IsA("TextLabel") then
		label.BackgroundColor3 = COR_CARTAO
		label.BackgroundTransparency = 0
		label.Font = Enum.Font.GothamMedium
		label.TextSize = 15
	end
end

-- ⚠️ v102 — PEDIDO: "preciso que ela fique um pouco maior, um pouco mais
-- clara... os textos que avisam 'Arma R, Hissatsu 1, Hissatsu 2' ficam meio
-- escuros... quando ela está muito pequena fica muito ruim" + "remove esse
-- segundo slot [o Guardado] que você colocou em cada arma... coloca uma
-- opção na direita: o slot normal e o slot pago... dois slots ativos e dois
-- slots reservas".
--
-- POR QUE FICAVA PEQUENA: o painel tinha 903px de ALTURA (duas fileiras de
-- cartões de 386px) e o UIScale encolhe o painel inteiro até caber na
-- altura da tela — numa janela de 600px ele virava 61% do tamanho. Agora o
-- cartão é HORIZONTAL e baixo (imagem à esquerda, nome/descrição/GIRAR à
-- direita): o painel tem 556px de altura, cresce pra LARGURA (onde sobra
-- tela) e ganha a coluna das RESERVAS à direita. Na mesma janela ele fica
-- ~99% do tamanho, e em tela grande pode passar do tamanho original.
-- Tudo em pixel fixo, calculado aqui (os cartões vêm do Studio com posições
-- em escala; são reposicionados por código).
local CARD_W, CARD_H = 481, 226
local CAB_H = 56 -- altura do cabeçalho
local PAD, GAP = 20, 14
local RESERVA_W = 300
local COL1_X, COL2_X = PAD, PAD + CARD_W + GAP
local LIN1_Y, LIN2_Y = CAB_H + GAP, CAB_H + GAP + CARD_H + GAP
local RESERVA_X = COL2_X + CARD_W + GAP
local DESENHO_LARGURA = RESERVA_X + RESERVA_W + PAD
local DESENHO_ALTURA = LIN2_Y + CARD_H + PAD

-- textos mais claros (pedido): legenda em azul claro + branco-acinzentado,
-- descrição em cinza CLARO (era COR_TEXTO_FRACO, escuro demais no fundo)
local COR_LEGENDA = Color3.fromRGB(125, 185, 255)
local COR_TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)

-- converte o que veio do Studio em escala pra pixel (desenho original
-- 1049 x 431) antes de mexer no tamanho do painel
local DESENHO_ORIG_W, DESENHO_ORIG_H = 1049, 431
for _, filho in ipairs(frame:GetChildren()) do
	if filho:IsA("GuiObject") then
		local p, s = filho.Position, filho.Size
		filho.Position = UDim2.fromOffset(p.X.Scale * DESENHO_ORIG_W + p.X.Offset, p.Y.Scale * DESENHO_ORIG_H + p.Y.Offset)
		filho.Size = UDim2.fromOffset(s.X.Scale * DESENHO_ORIG_W + s.X.Offset, s.Y.Scale * DESENHO_ORIG_H + s.Y.Offset)
	end
end
cabecalho.Size = UDim2.fromOffset(DESENHO_LARGURA, CAB_H)
-- cabeçalho: [? R?] ROLL ........ [COMPRAR ROLL] Rolls: N [X]
-- (as posições do Studio eram em escala do painel antigo: o X ficava
-- gigante e em cima do contador)
if textoCabecalho and textoCabecalho:IsA("TextLabel") then
	textoCabecalho.AnchorPoint = Vector2.new(0, 0.5)
	textoCabecalho.Position = UDim2.new(0, 104, 0.5, 0)
	textoCabecalho.Size = UDim2.fromOffset(300, 34)
	textoCabecalho.TextScaled = false
	textoCabecalho.TextSize = 22
end
if closeButton and closeButton:IsA("GuiButton") then
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.Position = UDim2.new(1, -12, 0.5, 0)
	closeButton.Size = UDim2.fromOffset(34, 34)
	if closeButton:IsA("TextButton") then
		closeButton.TextScaled = false
		closeButton.TextSize = 16
	end
end

-- a fileira do slot 2: cópias dos dois cartões originais (ainda crus)
local pulseFrame2 = pulseFrame:Clone()
pulseFrame2.Name = "pulse2"
pulseFrame2.Parent = frame
local instinctFrame2 = instinctFrame:Clone()
instinctFrame2.Name = "instinct2"
instinctFrame2.Parent = frame

local POSICAO_CARTAO = {
	[pulseFrame] = UDim2.fromOffset(COL1_X, LIN1_Y),
	[instinctFrame] = UDim2.fromOffset(COL2_X, LIN1_Y),
	[pulseFrame2] = UDim2.fromOffset(COL1_X, LIN2_Y),
	[instinctFrame2] = UDim2.fromOffset(COL2_X, LIN2_Y),
}

-- legenda DENTRO do cartão (antes ficava solta em cima, escura): o que é e
-- qual tecla usa na partida
local LEGENDAS = {
	[pulseFrame] = { Titulo = "HISSATSU 1", Linha = "tecla 1 na partida · você aciona" },
	[instinctFrame] = { Titulo = "ARMA 1", Linha = "tecla E na partida · passiva" },
	[pulseFrame2] = { Titulo = "HISSATSU 2", Linha = "tecla 2 na partida · você aciona" },
	[instinctFrame2] = { Titulo = "ARMA 2", Linha = "tecla R na partida · passiva" },
}

local sectionUI = {}

for _, secao in ipairs({ instinctFrame, pulseFrame, instinctFrame2, pulseFrame2 }) do
	secao.BackgroundColor3 = COR_CARTAO
	secao.Size = UDim2.fromOffset(CARD_W, CARD_H)
	secao.Position = POSICAO_CARTAO[secao]
	cantosR(secao, 10)
	local bordaCartao = contornoR(secao, COR_BORDA, 1, 0.25)

	local legenda = LEGENDAS[secao]
	local selo = Instance.new("TextLabel")
	selo.Name = "Legenda"
	selo.Size = UDim2.fromOffset(CARD_W - 32, 20)
	selo.Position = UDim2.fromOffset(16, 11)
	selo.BackgroundTransparency = 1
	selo.Font = Enum.Font.GothamBlack
	selo.TextSize = 15
	selo.TextColor3 = COR_LEGENDA
	selo.TextXAlignment = Enum.TextXAlignment.Left
	selo.RichText = true
	selo.Text = string.format('%s   <font color="#BEC5D4" size="13" weight="medium">%s</font>', legenda.Titulo, legenda.Linha)
	selo.ZIndex = 3
	selo.Parent = secao

	local rngImage = secao:FindFirstChild("rng")
	if rngImage and rngImage:IsA("ImageLabel") then
		rngImage.Position = UDim2.fromOffset(16, 42)
		rngImage.Size = UDim2.fromOffset(150, 150)
		cantosR(rngImage, 12)
		contornoR(rngImage, COR_BORDA, 2, 0)
	end

	local nameLabel = secao:FindFirstChild("name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		nameLabel.Position = UDim2.fromOffset(182, 40)
		nameLabel.Size = UDim2.fromOffset(CARD_W - 182 - 16, 30)
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.TextColor3 = COR_TEXTO
		nameLabel.TextSize = 22
		nameLabel.TextScaled = false
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.BackgroundTransparency = 1
	end

	local descLabel = secao:FindFirstChild("desc")
	-- ⚠️ v107 — PEDIDO: "coloca no roll qual é o elemento de cada Hissatsu" —
	-- linha nova embaixo do nome: o elemento na cor dele + contra quem é forte/fraco.
	local elemLabel = Instance.new("TextLabel")
	elemLabel.Name = "Elemento"
	elemLabel.Position = UDim2.fromOffset(182, 70)
	elemLabel.Size = UDim2.fromOffset(CARD_W - 182 - 16, 18)
	elemLabel.BackgroundTransparency = 1
	elemLabel.Font = Enum.Font.GothamBold
	elemLabel.TextSize = 13
	elemLabel.RichText = true
	elemLabel.TextXAlignment = Enum.TextXAlignment.Left
	elemLabel.TextTruncate = Enum.TextTruncate.AtEnd
	elemLabel.TextColor3 = COR_TEXTO_MEDIO
	elemLabel.Text = ""
	elemLabel.ZIndex = 3
	elemLabel.Parent = secao
	if descLabel and descLabel:IsA("TextLabel") then
		descLabel.Position = UDim2.fromOffset(182, 92)
		descLabel.Size = UDim2.fromOffset(CARD_W - 182 - 16, 78)
		descLabel.BackgroundTransparency = 1
		descLabel.Font = Enum.Font.GothamMedium
		descLabel.TextColor3 = COR_TEXTO_MEDIO
		descLabel.TextSize = 14
		descLabel.TextScaled = false
		descLabel.TextWrapped = true
		descLabel.TextXAlignment = Enum.TextXAlignment.Left
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
		descLabel.TextTruncate = Enum.TextTruncate.AtEnd
	end

	local spinButton = secao:FindFirstChild("spin")
	local robuxIcon
	if spinButton and spinButton:IsA("GuiButton") then
		local ROBUX_W, G = 52, 6
		local larguraLivre = CARD_W - 182 - 16
		spinButton.Position = UDim2.fromOffset(182, 176)
		spinButton.Size = UDim2.fromOffset(larguraLivre - ROBUX_W - G, 38)
		spinButton.BackgroundColor3 = COR_OK
		spinButton.Font = Enum.Font.GothamBlack
		spinButton.TextSize = 17
		spinButton.TextScaled = false
		spinButton.TextColor3 = Color3.new(1, 1, 1)
		spinButton.Text = "GIRAR"
		spinButton.AutoButtonColor = false
		cantosR(spinButton, 8)
		spinButton.MouseEnter:Connect(function()
			spinButton.BackgroundColor3 = COR_OK:Lerp(Color3.new(1, 1, 1), 0.12)
		end)
		spinButton.MouseLeave:Connect(function()
			spinButton.BackgroundColor3 = COR_OK
		end)

		-- R$ do lado: gira na pool de Robux (sem crédito, abre a compra)
		robuxIcon = Instance.new("TextButton")
		robuxIcon.Name = "SpinRobux"
		robuxIcon.Size = UDim2.fromOffset(ROBUX_W, 38)
		robuxIcon.Position = UDim2.fromOffset(182 + larguraLivre - ROBUX_W, 176)
		robuxIcon.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
		robuxIcon.Text = "R$"
		robuxIcon.Font = Enum.Font.GothamBlack
		robuxIcon.TextSize = 16
		robuxIcon.TextColor3 = Color3.fromRGB(150, 255, 195)
		robuxIcon.AutoButtonColor = false
		robuxIcon.ZIndex = 5
		robuxIcon.Parent = secao
		cantosR(robuxIcon, 8)
		contornoR(robuxIcon, Color3.fromRGB(120, 255, 180), 1, 0.35)
		robuxIcon.MouseEnter:Connect(function()
			robuxIcon.BackgroundColor3 = Color3.fromRGB(60, 130, 90):Lerp(Color3.new(1, 1, 1), 0.15)
		end)
		robuxIcon.MouseLeave:Connect(function()
			robuxIcon.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
		end)
	end

	-- camada de "TROCAR AQUI": só aparece quando você escolheu uma reserva
	-- e está escolhendo qual slot ativo vai trocar com ela
	local camadaTroca = Instance.new("TextButton")
	camadaTroca.Name = "TrocarAqui"
	camadaTroca.Size = UDim2.fromScale(1, 1)
	camadaTroca.BackgroundColor3 = COR_PAINEL -- escuro: o texto fica legível por cima da descrição
	camadaTroca.BackgroundTransparency = 0.18
	camadaTroca.AutoButtonColor = false
	camadaTroca.Font = Enum.Font.GothamBlack
	camadaTroca.TextSize = 22
	camadaTroca.TextColor3 = COR_LEGENDA
	camadaTroca.Text = "⇄  TROCAR AQUI"
	camadaTroca.ZIndex = 20
	camadaTroca.Visible = false
	camadaTroca.Parent = secao
	cantosR(camadaTroca, 10)

	sectionUI[secao] = {
		elemLabel = elemLabel,
		nameLabel = nameLabel,
		descLabel = descLabel,
		rngImage = rngImage,
		spinButton = spinButton,
		robuxIcon = robuxIcon,
		camadaTroca = camadaTroca,
		borda = bordaCartao,
	}
end

-- ===== coluna das RESERVAS (direita) =====
local reservaPainel = Instance.new("Frame")
reservaPainel.Name = "Reservas"
reservaPainel.Position = UDim2.fromOffset(RESERVA_X, LIN1_Y)
reservaPainel.Size = UDim2.fromOffset(RESERVA_W, CARD_H * 2 + GAP)
reservaPainel.BackgroundColor3 = COR_CARTAO
reservaPainel.Parent = frame
cantosR(reservaPainel, 10)
contornoR(reservaPainel, COR_BORDA, 1, 0.25)

local reservaTitulo = Instance.new("TextLabel")
reservaTitulo.Name = "Titulo"
reservaTitulo.BackgroundTransparency = 1
reservaTitulo.Position = UDim2.fromOffset(16, 10)
reservaTitulo.Size = UDim2.fromOffset(RESERVA_W - 32, 20)
reservaTitulo.Font = Enum.Font.GothamBlack
reservaTitulo.TextSize = 15
reservaTitulo.TextColor3 = COR_LEGENDA
reservaTitulo.TextXAlignment = Enum.TextXAlignment.Left
reservaTitulo.Text = "RESERVA"
reservaTitulo.Parent = reservaPainel

local reservaDica = Instance.new("TextLabel")
reservaDica.Name = "Dica"
reservaDica.BackgroundTransparency = 1
reservaDica.Position = UDim2.fromOffset(16, 30)
reservaDica.Size = UDim2.fromOffset(RESERVA_W - 32, 16)
reservaDica.Font = Enum.Font.GothamMedium
reservaDica.TextSize = 12
reservaDica.TextColor3 = COR_TEXTO_MEDIO
reservaDica.TextXAlignment = Enum.TextXAlignment.Left
reservaDica.TextTruncate = Enum.TextTruncate.AtEnd
reservaDica.Text = "guardadas — não vão pra partida"
reservaDica.Parent = reservaPainel

local reservaGrupos = {} -- [kind] = { [3] = tile, [4] = tile }
local TILE_W, TILE_H = RESERVA_W - 24, 82
local function criarGrupoReserva(kind, titulo, y)
	local rotulo = Instance.new("TextLabel")
	rotulo.BackgroundTransparency = 1
	rotulo.Position = UDim2.fromOffset(12, y)
	rotulo.Size = UDim2.fromOffset(TILE_W, 18)
	rotulo.Font = Enum.Font.GothamBlack
	rotulo.TextSize = 12
	rotulo.TextColor3 = COR_TEXTO_MEDIO
	rotulo.TextXAlignment = Enum.TextXAlignment.Left
	rotulo.Text = titulo
	rotulo.Parent = reservaPainel

	reservaGrupos[kind] = {}
	for i, slot in ipairs({ 3, 4 }) do
		local tile = Instance.new("Frame")
		tile.Name = kind .. "Reserva" .. slot
		tile.Position = UDim2.fromOffset(12, y + 22 + (i - 1) * (TILE_H + 8))
		tile.Size = UDim2.fromOffset(TILE_W, TILE_H)
		tile.BackgroundColor3 = COR_CARTAO_ALT
		tile.Parent = reservaPainel
		cantosR(tile, 8)
		local borda = contornoR(tile, COR_BORDA, 1, 0)

		local icone = Instance.new("ImageLabel")
		icone.Name = "Icone"
		icone.Position = UDim2.fromOffset(10, 12)
		icone.Size = UDim2.fromOffset(58, 58)
		icone.BackgroundColor3 = COR_CARTAO
		icone.ScaleType = Enum.ScaleType.Fit
		icone.Parent = tile
		cantosR(icone, 8)

		local nome = Instance.new("TextLabel")
		nome.Name = "Nome"
		nome.BackgroundTransparency = 1
		nome.Position = UDim2.fromOffset(78, 10)
		nome.Size = UDim2.fromOffset(TILE_W - 88, 20)
		nome.Font = Enum.Font.GothamBlack
		nome.TextSize = 15
		nome.TextColor3 = COR_TEXTO
		nome.TextXAlignment = Enum.TextXAlignment.Left
		nome.TextTruncate = Enum.TextTruncate.AtEnd
		nome.Parent = tile

		local sub = Instance.new("TextLabel")
		sub.Name = "Sub"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromOffset(78, 30)
		sub.Size = UDim2.fromOffset(TILE_W - 88, 14)
		sub.Font = Enum.Font.GothamMedium
		sub.TextSize = 12
		sub.TextColor3 = COR_TEXTO_MEDIO
		sub.TextXAlignment = Enum.TextXAlignment.Left
		sub.Text = slot == 3 and "reserva" or "reserva paga"
		sub.Parent = tile

		local botao = Instance.new("TextButton")
		botao.Name = "Botao"
		botao.Position = UDim2.fromOffset(78, 50)
		botao.Size = UDim2.fromOffset(TILE_W - 88, 24)
		botao.BackgroundColor3 = COR_CARTAO
		botao.AutoButtonColor = true
		botao.Font = Enum.Font.GothamBlack
		botao.TextSize = 12
		botao.TextColor3 = COR_LEGENDA
		botao.Parent = tile
		cantosR(botao, 6)
		local bordaBotao = contornoR(botao, COR_ACENTO, 1, 0.5)

		reservaGrupos[kind][slot] = {
			Tile = tile, Borda = borda, Icone = icone, Nome = nome, Sub = sub, Botao = botao, BordaBotao = bordaBotao,
		}
	end
end
criarGrupoReserva("Pulse", "HISSATSUS", 56)
criarGrupoReserva("Instinct", "ARMAS", 56 + 22 + TILE_H * 2 + 8 + 16)

-- ⚠️ v68 — A HUD DE ROLL CABE NA TELA AGORA.
-- PEDIDO: "na HUD de roll ela fica meio que pro lado da tela, e o jogador do
-- mobile não consegue clicar direito."
--
-- CAUSA: o painel foi desenhado no Studio com tamanho FIXO em pixels
-- (1049 x 431) e posicionado por ESCALA, sem AnchorPoint. Num monitor grande
-- isso por acaso cai num lugar razoável; num celular, ele começa a ~22% da
-- largura e se estende 1049px — ou seja, a maior parte do painel fica FORA
-- da tela, e os botões que sobram ficam na borda, impossíveis de acertar com
-- o dedo.
--
-- CONSERTO EM DUAS PARTES, as duas por código (não na mão no Studio, pra
-- sobreviver a qualquer re-sync e ficar versionado):
--   1) o painel passa a ser CENTRALIZADO de verdade (AnchorPoint 0.5);
--   2) um UIScale encolhe o conjunto inteiro até caber na tela, mantendo a
--      proporção e todo o layout interno feito à mão intacto.
-- Assim o mesmo desenho serve pra monitor e pra celular, sem duplicar UI.
frame.AnchorPoint = Vector2.new(0.5, 0.5)
frame.Position = UDim2.new(0.5, 0, 0.5, 0)
rollGui.IgnoreGuiInset = true -- sem isso a barra de topo do Roblox desloca o "centro"

-- ⚠️ v78 — PEDIDO: "você pode aumentar o tamanho da HUD de row, pra poder
-- incluir tudo que você precisa" (fileira de slots + ícone de Robux por
-- cima do botão GIRAR). O painel era 1049x431; cada seção (pulse/
-- instinct) ganha +SECTION_EXTRA_H de altura pra caber a fileira de
-- slots no topo, e o painel inteiro cresce junto (só na altura — a
-- largura continua a mesma).
-- (DESENHO_LARGURA/DESENHO_ALTURA vêm do layout v102, lá em cima)
local MARGEM = 16 -- respiro pras bordas, pra nunca encostar no limite da tela
local ESCALA_MAXIMA = 1.2 -- ⚠️ v102: "um pouco maior" — em tela grande passa do tamanho desenhado

frame.Size = UDim2.fromOffset(DESENHO_LARGURA, DESENHO_ALTURA)

local rollScale = frame:FindFirstChildOfClass("UIScale")
if not rollScale then
	rollScale = Instance.new("UIScale")
	rollScale.Parent = frame
end

local function ajustarEscalaDoRoll()
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if not v or v.X <= 0 or v.Y <= 0 then return end
	-- ⚠️ v102: pode crescer até ESCALA_MAXIMA (texto do Roblox escala nítido)
	rollScale.Scale = math.min(
		ESCALA_MAXIMA,
		(v.X - MARGEM * 2) / DESENHO_LARGURA,
		(v.Y - MARGEM * 2) / DESENHO_ALTURA
	)
end

ajustarEscalaDoRoll()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscalaDoRoll)
end

raritiesFrame.Visible = false

-- ========================================
-- CRÉDITOS DE ROLL (autoritativo no servidor — ver RollServer.lua)
-- ========================================
local rollCredits = 0
-- ⚠️ v77 — CORRIGIDO: o cliente nunca soube que existia um crédito de
-- Robux separado (RollCreditsRobux, ver RollServer.legacy.luau) — um
-- jogador que só tinha crédito de Robux via "Sem rolls!" ao tentar
-- girar, porque o botão só checava `rollCredits` (o pool de dinheiro).
local rollCreditsRobux = 0
local rollCreditsLabel = nil -- criado mais abaixo (ver "BOTÃO DE COMPRAR ROLL")

local function updateRollCreditsLabel()
	if rollCreditsLabel then
		rollCreditsLabel.Text = (rollCreditsRobux > 0)
			and string.format("Rolls: %d  R$%d", rollCredits, rollCreditsRobux)
			or string.format("Rolls: %d", rollCredits)
	end
end

local function refreshRollCreditsFromServer()
	local ok, credits, creditsRobux = pcall(function()
		return GetRollCredits:InvokeServer()
	end)
	if ok and type(credits) == "number" then
		rollCredits = credits
		rollCreditsRobux = type(creditsRobux) == "number" and creditsRobux or rollCreditsRobux
		updateRollCreditsLabel()
	end
end

UpdateRollCreditsEvent.OnClientEvent:Connect(function(newValue, newValueRobux)
	rollCredits = newValue
	if type(newValueRobux) == "number" then
		rollCreditsRobux = newValueRobux
	end
	updateRollCreditsLabel()
end)

refreshRollCreditsFromServer()

-- ========================================
-- PREENCHER O FRAME "rarities" (info de cada raridade + chance)
-- ⚠️ v78 — virou FUNÇÃO: o botão "help" mostra as chances do roll NORMAL
-- (RARITIES acima) e o "helpRobux" mostra as chances do roll DE ROBUX
-- (Config.ROBUX_ROLL_RARITY_WEIGHTS — 0% Comum/Raro, 30/40/30% Épico/
-- Lendário/Mítico). Antes helpRobux comprava direto ao clicar; agora ele
-- só INFORMA (igual o help normal) — a compra + o roll de verdade com
-- Robux mudaram pro símbolo de Robux do lado de cada botão GIRAR (ver
-- setupSpinSection mais abaixo).
-- ========================================
local function renderRaritiesPanel(pesos)
	local total = 0
	for _, rarity in ipairs(RARITIES) do
		total += (pesos[rarity.Name] or 0)
	end
	for _, rarity in ipairs(RARITIES) do
		local label = raritiesFrame:FindFirstChild(rarity.Name)
		if label and label:IsA("TextLabel") then
			local peso = pesos[rarity.Name] or 0
			local chancePercent = total > 0 and (peso / total) * 100 or 0
			label.Text = string.format("%s — %.1f%%", rarity.Label, chancePercent)
			label.TextColor3 = rarity.Color
		else
			warn(string.format("RollClient: não encontrei a TextLabel '%s' dentro de rarities.", rarity.Name))
		end
	end
end

local NORMAL_WEIGHTS = {}
for _, rarity in ipairs(RARITIES) do
	NORMAL_WEIGHTS[rarity.Name] = rarity.Weight
end

renderRaritiesPanel(NORMAL_WEIGHTS)

-- ========================================
-- ABRIR / FECHAR
-- ========================================
local function setRollVisible(open)
	if rollGui:IsA("ScreenGui") then
		rollGui.Enabled = open
	else
		rollGui.Visible = open
	end
	frame.Visible = open

	if not open then
		raritiesFrame.Visible = false
	end
end

_G.OpenRoll = function()
	setRollVisible(true)
end

_G.CloseRoll = function()
	setRollVisible(false)
end

_G.ToggleRoll = function()
	local isOpen = rollGui:IsA("ScreenGui") and rollGui.Enabled or rollGui.Visible
	if isOpen then
		_G.CloseRoll()
	else
		_G.OpenRoll()
	end
end

if closeButton and closeButton:IsA("GuiButton") then
	closeButton.MouseButton1Click:Connect(function()
		_G.CloseRoll()
	end)
else
	warn("RollClient: não encontrei o 'CloseButton' dentro de cabeçalho — o botão de fechar o Roll não vai funcionar.")
end

-- ========================================
-- BOTÃO HELP: mostra/esconde as informações de raridade
-- ========================================
-- ⚠️ v78: help e helpRobux agora fazem A MESMA COISA (mostrar o painel),
-- só que com números diferentes — help = chances do roll normal,
-- helpRobux = chances do roll de Robux. Clicar num dos dois troca o
-- CONTEÚDO do painel pra aquele conjunto de chances (não really
-- "abre/fecha" independente um do outro — é 1 painel só, sempre
-- mostrando o último clicado).
local raritiesModoAtual = "normal"
local function toggleRaridades(modo)
	if raritiesFrame.Visible and raritiesModoAtual == modo then
		raritiesFrame.Visible = false
		return
	end
	raritiesModoAtual = modo
	renderRaritiesPanel(modo == "robux" and LobbyConfig.ROBUX_ROLL_RARITY_WEIGHTS or NORMAL_WEIGHTS)
	raritiesFrame.Visible = true
end

if helpButton and helpButton:IsA("GuiButton") then
	helpButton.MouseButton1Click:Connect(function()
		toggleRaridades("normal")
	end)
else
	warn("RollClient: 'help' não é um GuiButton válido dentro de frame.")
end

-- ========================================
-- BOTÃO helpRobux — v78: MUDOU DE FUNÇÃO. Antes comprava 1 roll de Robux
-- direto ao clicar; agora só MOSTRA as chances do roll de Robux (pedido:
-- "aquele botão... na verdade é um botão pra você ver as chances de roll
-- de Robux"). A compra + o roll de verdade com Robux agora ficam no
-- símbolozinho de Robux do lado de cada botão GIRAR (ver
-- setupSpinSection mais abaixo — é lá que PromptProductPurchase acontece
-- agora, quando o jogador clica nele sem ter crédito de Robux sobrando).
-- ========================================
if helpRobuxButton and helpRobuxButton:IsA("GuiButton") then
	helpRobuxButton.Text = "R?"
	helpRobuxButton.MouseButton1Click:Connect(function()
		toggleRaridades("robux")
	end)
end

-- Quando uma compra de Robux é confirmada de verdade, o servidor credita
-- o roll e dispara UpdateRollCredits (já conectado acima) — só
-- reconfirma o saldo aqui, pro label atualizar rápido.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if userId == player.UserId and wasPurchased
		and (productId == LobbyConfig.ROBUX_ROLL_PRODUCT_ID) then
		task.delay(1, refreshRollCreditsFromServer) -- dá um tempo pro ProcessReceipt do servidor rodar
	end
end)

-- ========================================
-- BOTÃO DE COMPRAR ROLL — MOVIDO da Loja pra cá (antes era um card em
-- Shop, agora é um botão dedicado dentro da própria tela de Roll).
-- Construído por código (igual o "ResetSlotPicker" do ShopClient.lua) —
-- não depende de nada novo criado no Studio, então sincroniza pelo script
-- sozinho. Fica dentro de "cabeçalho", do lado do texto.
-- ========================================
-- ⚠️ v73: paleta alinhada ao resto da GUI reestilizada acima (era um
-- verde solto de referência nenhuma).
local buyRollButton = Instance.new("TextButton")
buyRollButton.Name = "BuyRollButton"
buyRollButton.Size = UDim2.fromOffset(170, 34)
buyRollButton.Position = UDim2.new(1, -186, 0.5, 0) -- ⚠️ v102: alinhado à direita, antes do contador e do X
buyRollButton.AnchorPoint = Vector2.new(1, 0.5)
buyRollButton.BackgroundColor3 = COR_OK
buyRollButton.Text = string.format("COMPRAR ROLL ($%d)", LobbyConfig.SHOP.Roll.Cost)
buyRollButton.TextColor3 = Color3.new(1, 1, 1)
buyRollButton.Font = Enum.Font.GothamBlack
buyRollButton.TextSize = 13
buyRollButton.AutoButtonColor = false
buyRollButton.ZIndex = 5
buyRollButton.Parent = cabecalho
cantosR(buyRollButton, 8)
buyRollButton.MouseEnter:Connect(function()
	buyRollButton.BackgroundColor3 = COR_OK:Lerp(Color3.new(1, 1, 1), 0.12)
end)
buyRollButton.MouseLeave:Connect(function()
	buyRollButton.BackgroundColor3 = COR_OK
end)

rollCreditsLabel = Instance.new("TextLabel")
rollCreditsLabel.Name = "RollCreditsLabel"
rollCreditsLabel.Size = UDim2.fromOffset(120, 34)
rollCreditsLabel.Position = UDim2.new(1, -58, 0.5, 0)
rollCreditsLabel.AnchorPoint = Vector2.new(1, 0.5)
rollCreditsLabel.TextScaled = false
rollCreditsLabel.TextXAlignment = Enum.TextXAlignment.Right
rollCreditsLabel.BackgroundTransparency = 1
rollCreditsLabel.Text = string.format("Rolls: %d", rollCredits)
rollCreditsLabel.TextColor3 = COR_TEXTO
rollCreditsLabel.Font = Enum.Font.GothamBold
rollCreditsLabel.TextSize = 15
rollCreditsLabel.ZIndex = 5
rollCreditsLabel.Parent = cabecalho

local buyRollInProgress = false
buyRollButton.MouseButton1Click:Connect(function()
	if buyRollInProgress then return end
	buyRollInProgress = true
	buyRollButton.AutoButtonColor = false
	local originalText = buyRollButton.Text
	buyRollButton.Text = "..."

	local ok, success, result = pcall(function()
		return BuyRoll:InvokeServer()
	end)

	if ok and success then
		if type(result) == "table" and type(result.RollCredits) == "number" then
			rollCredits = result.RollCredits
			updateRollCreditsLabel()
		else
			refreshRollCreditsFromServer()
		end
	else
		warn("RollClient: falha ao comprar Roll: " .. tostring(result))
	end

	buyRollButton.Text = originalText
	buyRollInProgress = false
	buyRollButton.AutoButtonColor = true
end)

-- ⚠️ v4: resolve nome ANTIGO (Pulso/Instinto que foi fundido em outro)
-- pro nome atual antes de procurar — senão quem tem um deles equipado
-- abriria a tela de Roll e veria "nada equipado".
local function findByName(pool, name)
	if not name then return nil end
	if PulseInstinctData.ResolveName then
		name = PulseInstinctData.ResolveName(name)
	end
	for _, item in ipairs(pool) do
		if item.Name == name then
			return item
		end
	end
	return nil
end

-- ⚠️ v77 — PEDIDO: "inclua ela nas hissatsus e armas pedidas". Quem TEM
-- arte de verdade (item.Image) mostra a imagem, com um fundo neutro
-- escuro atrás (a cor da raridade sai só pela borda — já ajustada pra
-- "mais quadrada" em vez de redonda, ver cantosR mais acima); quem ainda
-- não tem arte continua no placeholder de sempre (fundo cheio na cor da
-- raridade, sem imagem nenhuma por cima).
local function aplicarIconeDeRaridade(rngImage, item, rarityColor)
	local cor = rarityColor or Color3.fromRGB(255, 255, 255)
	if item and item.Image then
		rngImage.Image = item.Image
		rngImage.BackgroundColor3 = Color3.fromRGB(24, 26, 34)
		rngImage.ScaleType = Enum.ScaleType.Fit
	else
		rngImage.Image = ""
		rngImage.BackgroundColor3 = cor
	end
end

-- ========================================
-- ⚠️ v102 — SLOTS: 2 ATIVOS + 2 RESERVAS por tipo.
-- PEDIDO: "dois slots ativos, como está aí, e dois slots reservas, que você
-- pode trocar com cada um deles... a pessoa só vai ter um slot reserva pra
-- guardar e um slot pago... mantém o botão de troca, só que ele vai alterar
-- no slot reserva: cliquei no botão, cliquei no slot que eu quero alterar,
-- alterou". Os 4 cartões são os ATIVOS (slot 1 em cima, slot 2 embaixo) e
-- giram direto no próprio slot. A coluna da direita tem as RESERVAS de cada
-- tipo: slot 3 (de graça) e slot 4 (pago com Robux — travado mostra o
-- preço e abre a compra). "⇄ TROCAR" numa reserva acende os dois cartões
-- ativos daquele tipo; clicar num deles troca os dois.
-- ========================================
local SwapAbilitySlot = rollEvents:WaitForChild("SwapAbilitySlot")

local KIND_POOL = { Pulse = PULSE_POOL, Instinct = INSTINCT_POOL }

local CARTOES = {
	{ Kind = "Pulse", Slot = 1, Secao = pulseFrame },
	{ Kind = "Instinct", Slot = 1, Secao = instinctFrame },
	{ Kind = "Pulse", Slot = 2, Secao = pulseFrame2 },
	{ Kind = "Instinct", Slot = 2, Secao = instinctFrame2 },
}

local equippedState = { Pulse = {}, Instinct = {} }
local slotsCount = { Pulse = 3, Instinct = 3 } -- 4 quando a reserva paga está destravada

local SPIN_DURATION = 1.2
local SPIN_FLICKER_INTERVAL = 0.06

local SLOT_UNLOCK_PRODUCT_ID = {
	Pulse = LobbyConfig.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID,
	Instinct = LobbyConfig.ROBUX_EXTRA_INSTINCT_SLOT_PRODUCT_ID,
}
-- preço de verdade do Developer Product (buscado uma vez, sem travar a tela)
local precoReserva = {}
for kind, id in pairs(SLOT_UNLOCK_PRODUCT_ID) do
	if id and id ~= 0 then
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, Enum.InfoType.Product)
			end)
			if ok and type(info) == "table" and type(info.PriceInRobux) == "number" then
				precoReserva[kind] = info.PriceInRobux
			end
		end)
	end
end

-- troca em andamento: { Kind, Slot } da reserva escolhida
local trocaAtiva = nil
local renderTudo -- forward

-- ⚠️ v107: elemento (mesma tabela de vantagem do FootballConfig da partida)
local COR_ELEMENTO = {
	Fogo = Color3.fromRGB(255, 125, 45), Vento = Color3.fromRGB(140, 232, 210), Natureza = Color3.fromRGB(115, 212, 110),
	Luz = Color3.fromRGB(255, 226, 115), Void = Color3.fromRGB(175, 115, 255),
}
local FORTE_CONTRA = { Void = "Natureza, Fogo, Vento", Luz = "Void", Natureza = "Vento", Fogo = "Natureza", Vento = "Fogo" }
local FRACO_CONTRA = { Void = "Luz", Natureza = "Fogo", Fogo = "Vento", Vento = "Natureza" }
local NOME_POSICAO = { GK = "GOLEIRO", DF = "DEFENSOR", MF = "MEIO-CAMPO", FW = "ATACANTE" }
local function textoElemento(item)
	-- ⚠️ v110: Arma não tem elemento — a linha mostra a POSIÇÃO dela
	if item and not item.Element and item.Posicao then
		return string.format('<font color="#DCE3F0">%s</font>   <font color="#8C96AA" size="12" weight="medium">arma de %s</font>',
			item.Posicao, string.lower(NOME_POSICAO[item.Posicao] or item.Posicao))
	end
	if not item or not item.Element then return "" end
	local c = COR_ELEMENTO[item.Element] or Color3.fromRGB(200, 200, 200)
	local hex = string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
	local extra = "forte: " .. (FORTE_CONTRA[item.Element] or "-")
	if FRACO_CONTRA[item.Element] then extra ..= "  ·  fraco: " .. FRACO_CONTRA[item.Element] end
	return string.format('<font color="%s">%s</font>   <font color="#8C96AA" size="12" weight="medium">%s</font>', hex, maiusculas(item.Element), extra)
end

local function renderCartao(cartao)
	local ui = sectionUI[cartao.Secao]
	if not ui or cartao.Girando then return end
	local item = findByName(KIND_POOL[cartao.Kind], equippedState[cartao.Kind][cartao.Slot])
	if ui.elemLabel then ui.elemLabel.Text = textoElemento(item) end
	if item then
		local rarity = RARITY_BY_NAME[item.Rarity]
		ui.nameLabel.Text = item.Name
		ui.descLabel.Text = item.Description
		ui.nameLabel.TextColor3 = rarity and rarity.Color or COR_TEXTO
		aplicarIconeDeRaridade(ui.rngImage, item, rarity and rarity.Color)
	else
		ui.nameLabel.Text = "Vazio"
		ui.nameLabel.TextColor3 = COR_TEXTO_MEDIO
		ui.descLabel.Text = "Esse slot não tem nada equipado — gire pra preencher."
		aplicarIconeDeRaridade(ui.rngImage, nil, COR_CARTAO_ALT)
	end
	-- modo troca: acende só os ativos do MESMO tipo da reserva escolhida
	local acender = trocaAtiva ~= nil and trocaAtiva.Kind == cartao.Kind
	ui.camadaTroca.Visible = acender
	ui.borda.Color = acender and COR_ACENTO or COR_BORDA
	ui.borda.Transparency = acender and 0 or 0.25
end

local function renderReserva(kind, slot)
	local r = reservaGrupos[kind] and reservaGrupos[kind][slot]
	if not r then return end
	local destravado = slot <= slotsCount[kind]
	local escolhida = trocaAtiva ~= nil and trocaAtiva.Kind == kind and trocaAtiva.Slot == slot
	r.Borda.Color = escolhida and COR_ACENTO or COR_BORDA
	r.Borda.Thickness = escolhida and 2 or 1

	if not destravado then
		r.Nome.Text = "Bloqueada"
		r.Nome.TextColor3 = COR_TEXTO_MEDIO
		r.Icone.Image = ""
		r.Icone.BackgroundColor3 = COR_CARTAO
		r.Botao.Text = precoReserva[kind] and string.format("DESTRAVAR  R$ %d", precoReserva[kind]) or "DESTRAVAR  (Robux)"
		r.Botao.TextColor3 = Color3.fromRGB(150, 255, 195)
		r.BordaBotao.Color = Color3.fromRGB(120, 255, 180)
		return
	end

	local item = findByName(KIND_POOL[kind], equippedState[kind][slot])
	if item then
		local rarity = RARITY_BY_NAME[item.Rarity]
		r.Nome.Text = item.Name
		r.Nome.TextColor3 = rarity and rarity.Color or COR_TEXTO
		aplicarIconeDeRaridade(r.Icone, item, rarity and rarity.Color)
	else
		r.Nome.Text = "Vazia"
		r.Nome.TextColor3 = COR_TEXTO_MEDIO
		r.Icone.Image = ""
		r.Icone.BackgroundColor3 = COR_CARTAO
	end
	r.Botao.Text = escolhida and "CANCELAR" or "⇄  TROCAR"
	r.Botao.TextColor3 = COR_LEGENDA
	r.BordaBotao.Color = COR_ACENTO
end

renderTudo = function()
	for _, cartao in ipairs(CARTOES) do renderCartao(cartao) end
	for _, kind in ipairs({ "Pulse", "Instinct" }) do
		renderReserva(kind, 3)
		renderReserva(kind, 4)
	end
	if trocaAtiva then
		reservaDica.Text = trocaAtiva.Kind == "Pulse" and "clique na Hissatsu ativa que vai trocar" or "clique na Arma ativa que vai trocar"
		reservaDica.TextColor3 = COR_LEGENDA
	else
		reservaDica.Text = "guardadas — não vão pra partida"
		reservaDica.TextColor3 = COR_TEXTO_MEDIO
	end
end

local function aplicarEstadoDoServidor(novo)
	for _, kind in ipairs({ "Pulse", "Instinct" }) do
		for slot = 1, 4 do
			equippedState[kind][slot] = novo[kind .. slot]
		end
	end
	if type(novo.PulseSlots) == "number" then slotsCount.Pulse = novo.PulseSlots end
	if type(novo.InstinctSlots) == "number" then slotsCount.Instinct = novo.InstinctSlots end
end

local trocando = false
local function trocar(kind, ativo, reserva)
	if trocando then return end
	trocando = true
	task.spawn(function()
		local ok, success, novo = pcall(function()
			return SwapAbilitySlot:InvokeServer(kind, ativo, reserva)
		end)
		if ok and success and type(novo) == "table" then
			aplicarEstadoDoServidor(novo)
		else
			warn("RollClient: não consegui trocar o slot: " .. tostring(novo))
		end
		trocaAtiva = nil
		trocando = false
		renderTudo()
	end)
end

-- botões das reservas
for _, kind in ipairs({ "Pulse", "Instinct" }) do
	for _, slot in ipairs({ 3, 4 }) do
		local r = reservaGrupos[kind][slot]
		r.Botao.MouseButton1Click:Connect(function()
			if slot > slotsCount[kind] then
				local productId = SLOT_UNLOCK_PRODUCT_ID[kind]
				if not productId or productId == 0 then
					warn("RollClient: reserva paga ainda não configurada (product id = 0 em LobbyConfig.lua).")
					return
				end
				MarketplaceService:PromptProductPurchase(player, productId)
				return
			end
			if trocaAtiva and trocaAtiva.Kind == kind and trocaAtiva.Slot == slot then
				trocaAtiva = nil -- cancelar
			else
				trocaAtiva = { Kind = kind, Slot = slot }
			end
			renderTudo()
		end)
	end
end

local function setupCartao(cartao)
	local ui = sectionUI[cartao.Secao]
	local kind = cartao.Kind
	local pool = KIND_POOL[kind]
	if not ui or not ui.spinButton then
		warn(string.format("RollClient: o cartão %s slot %d está faltando algum dos filhos esperados (spin/rng/desc/name).", kind, cartao.Slot))
		return
	end

	-- "TROCAR AQUI" (só aparece com uma reserva escolhida)
	ui.camadaTroca.MouseButton1Click:Connect(function()
		if trocaAtiva and trocaAtiva.Kind == kind then
			trocar(kind, cartao.Slot, trocaAtiva.Slot)
		end
	end)

	local function executarRoll(useRobux)
		if cartao.Girando or trocaAtiva then return end
		if useRobux then
			if rollCreditsRobux < 1 then
				if LobbyConfig.ROBUX_ROLL_PRODUCT_ID == 0 then
					warn("RollClient: roll com Robux ainda não configurado (ROBUX_ROLL_PRODUCT_ID = 0 em LobbyConfig.lua).")
					return
				end
				MarketplaceService:PromptProductPurchase(player, LobbyConfig.ROBUX_ROLL_PRODUCT_ID)
				return
			end
		elseif rollCredits < 1 then
			ui.descLabel.Text = "Sem rolls! Compre no botão lá em cima ou use o R$ de Robux."
			return
		end

		cartao.Girando = true
		task.spawn(function()
			local ok, granted, resultInfo = pcall(function()
				return RollAbility:InvokeServer(kind, cartao.Slot, useRobux)
			end)
			if not ok or not granted then
				cartao.Girando = false
				ui.descLabel.Text = "Sem rolls! Compre no botão lá em cima ou use o R$ de Robux."
				return
			end
			local deadline = os.clock() + SPIN_DURATION
			repeat
				local flickerItem = pool[random:NextInteger(1, #pool)]
				local flickerRarity = RARITY_BY_NAME[flickerItem.Rarity]
				ui.nameLabel.Text = flickerItem.Name
				ui.descLabel.Text = "..."
				ui.nameLabel.TextColor3 = flickerRarity and flickerRarity.Color or Color3.new(1, 1, 1)
				aplicarIconeDeRaridade(ui.rngImage, flickerItem, flickerRarity and flickerRarity.Color)
				task.wait(SPIN_FLICKER_INTERVAL)
			until os.clock() >= deadline
			local slotUsado = (type(resultInfo) == "table" and resultInfo.Slot) or cartao.Slot
			equippedState[kind][slotUsado] = resultInfo.Name
			cartao.Girando = false
			renderTudo()
		end)
	end

	ui.spinButton.MouseButton1Click:Connect(function() executarRoll(false) end)
	if ui.robuxIcon then
		ui.robuxIcon.MouseButton1Click:Connect(function() executarRoll(true) end)
	end
end

for _, cartao in ipairs(CARTOES) do
	if cartao.Kind == "Pulse" and #PULSE_POOL == 0 then
		cartao.Secao.Visible = false -- ⚠️ v5: sem Pulsos cadastrados, os cartões de Hissatsu somem
	else
		setupCartao(cartao)
	end
end
renderTudo()

-- fechar o Roll no meio de uma troca cancela a troca
rollGui:GetPropertyChangedSignal(rollGui:IsA("ScreenGui") and "Enabled" or "Visible"):Connect(function()
	if trocaAtiva then
		trocaAtiva = nil
		renderTudo()
	end
end)

-- ========================================
-- MOSTRAR O QUE JÁ ESTAVA EQUIPADO (os dados sempre estiveram salvos no
-- servidor; a tela só precisa puxar eles ao abrir)
-- ========================================
local function refreshEquippedFromServer()
	local ok, equipped = pcall(function()
		return GetEquippedAbilities:InvokeServer()
	end)
	if not ok or type(equipped) ~= "table" then
		warn("RollClient: não consegui buscar as habilidades já equipadas.")
		return
	end
	aplicarEstadoDoServidor(equipped)
	renderTudo()
end

task.spawn(refreshEquippedFromServer)
-- o preço da reserva paga chega depois (GetProductInfo): redesenha quando vier
task.delay(3, renderTudo)

-- compra da reserva paga confirmada: busca o estado de novo
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if userId ~= player.UserId or not wasPurchased then return end
	if productId == LobbyConfig.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID
		or productId == LobbyConfig.ROBUX_EXTRA_INSTINCT_SLOT_PRODUCT_ID then
		task.delay(1, refreshEquippedFromServer)
	end
end)

print("✅ RollClient carregado (2 ativos + reserva e reserva paga por tipo).")
