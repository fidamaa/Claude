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

-- ⚠️ v78 — quanto cada seção (pulse/instinct) cresce em altura pra caber
-- a fileira de slots no topo (ver loop "cartões de instinct/pulse" mais
-- abaixo e o resize do painel inteiro, mais adiante).
local SECTION_EXTRA_H = 40
-- ⚠️ v79: folga de verdade embaixo do botão GIRAR/R$ (ver fixarPosicao
-- mais abaixo) — antes ficava raspando o rodapé do cartão.
local SECTION_BOTTOM_MARGIN = 16

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

-- ----- cartões de instinct/pulse -----
-- ⚠️ v74 — PEDIDO: "coloque um texto pra indicar o que é hissatsu e o
-- que é arma". No código, Pulso = Hissatsu (PulseInstinctData.Pulses) e
-- Instinto = Arma (PulseInstinctData.Instincts) — ver o cabeçalho deste
-- arquivo. Cada painel ganha um selo com o nome + uma linha dizendo como
-- a habilidade funciona, pra quem nunca girou entender ANTES de gastar
-- o roll, não só depois de ler a descrição do resultado.
local LEGENDAS = {
	[pulseFrame] = { Titulo = "HISSATSU", Linha = "você aciona — pressiona o botão na partida" },
	[instinctFrame] = { Titulo = "ARMA", Linha = "passiva — ativa sozinha quando a condição bate" },
}

-- ⚠️ v78 — guarda, por seção, tudo que o resto do arquivo precisa achar
-- de novo depois (slot row, ícone de Robux, botão de trocar com a
-- reserva) — construído por código, então não tem como o Studio ter
-- criado sozinho (GUI não sincroniza, só Script).
local sectionUI = {}

for _, secao in ipairs({ instinctFrame, pulseFrame }) do
	secao.BackgroundColor3 = COR_CARTAO
	cantosR(secao, 10)
	contornoR(secao, COR_BORDA, 1, 0.25)

	-- ⚠️ v79 — CORRIGIDO ("GIRAR/R$ ficaram meio fora do frame"): a v78
	-- só somava SECTION_EXTRA_H ao OFFSET da Position de cada filho, mas
	-- rng/spin têm a maior parte da posição em ESCALA (fração da altura
	-- DA SEÇÃO) — ao deixar a seção mais alta, o Roblox recalcula essa
	-- fração em cima da altura NOVA (maior), o que empurra rng/spin pra
	-- MUITO mais embaixo do que o +40 sozinho sugeria (a escala "dobra"
	-- o efeito). O spin, por exemplo, tinha Y em 85,4% da altura — em
	-- cima de uma seção maior isso invadia o rodapé do cartão.
	-- Fix: converte a posição de cada filho pra PIXEL FIXO (escala 0),
	-- calculado em cima do tamanho ORIGINAL do Studio (ORIG_SECTION_W/H
	-- abaixo) ANTES de redimensionar — assim não sobra escala nenhuma
	-- pra recompor com a altura nova, e o card ganha uma folga de
	-- verdade embaixo (SECTION_BOTTOM_MARGIN) em vez de ficar raspando.
	local ORIG_SECTION_W, ORIG_SECTION_H = 481, 330

	local function paraPixel(inst)
		local pos = inst.Position
		return pos.X.Scale * ORIG_SECTION_W + pos.X.Offset, pos.Y.Scale * ORIG_SECTION_H + pos.Y.Offset
	end

	secao.Size = UDim2.new(0, ORIG_SECTION_W, 0, ORIG_SECTION_H + SECTION_EXTRA_H + SECTION_BOTTOM_MARGIN)

	local legenda = LEGENDAS[secao]
	if legenda then
		-- Cabe no vão entre o fim do cabeçalho (56px) e o topo do cartão
		-- (~83px, ver Position em escala dele) — por isso a altura curta
		-- e o offset negativo pequeno, não um selo grande flutuando livre.
		local selo = Instance.new("TextLabel")
		selo.Name = "Legenda"
		selo.Size = UDim2.new(1, -24, 0, 20)
		selo.Position = UDim2.new(0, 12, 0, -23)
		selo.BackgroundTransparency = 1
		selo.Font = Enum.Font.GothamBlack
		selo.TextSize = 12
		selo.TextColor3 = COR_ACENTO
		selo.TextXAlignment = Enum.TextXAlignment.Left
		selo.TextYAlignment = Enum.TextYAlignment.Bottom
		selo.RichText = true
		selo.Text = string.format(
			'%s <font color="#788094" size="10">— %s</font>',
			legenda.Titulo, legenda.Linha
		)
		selo.ZIndex = 10
		selo.Parent = secao
	end

	local function fixarPosicao(inst)
		local x, y = paraPixel(inst)
		inst.Position = UDim2.fromOffset(x, y + SECTION_EXTRA_H)
	end

	local nameLabel = secao:FindFirstChild("name")
	if nameLabel and nameLabel:IsA("TextLabel") then
		fixarPosicao(nameLabel)
		nameLabel.Font = Enum.Font.GothamBlack
		nameLabel.TextColor3 = COR_TEXTO
		nameLabel.TextSize = 18
		-- TextColor3 é reescrito pela cor da raridade assim que sorteia/
		-- mostra o equipado (mais abaixo neste arquivo) — isso aqui é só
		-- o tom antes de ter resultado nenhum.
	end

	local descLabel = secao:FindFirstChild("desc")
	if descLabel and descLabel:IsA("TextLabel") then
		fixarPosicao(descLabel)
		descLabel.BackgroundTransparency = 1 -- o cartão escuro já dá o fundo; a chapa cinza clara por cima só brigava com ele
		descLabel.Font = Enum.Font.Gotham
		descLabel.TextColor3 = COR_TEXTO_FRACO
		descLabel.TextSize = 13
		descLabel.TextWrapped = true
		descLabel.TextYAlignment = Enum.TextYAlignment.Top
	end

	local rngImage = secao:FindFirstChild("rng")
	if rngImage and rngImage:IsA("ImageLabel") then
		fixarPosicao(rngImage)
		-- ⚠️ v77 — PEDIDO: "deixe as imagens da arma e do roll um pouco mais
		-- quadradas, você arredondou demais." Era um medalhão TOTALMENTE
		-- redondo (raio = metade do tamanho, virava círculo) — agora é só
		-- um canto suave, a imagem continua lendo como quadrada.
		cantosR(rngImage, 14)
		contornoR(rngImage, COR_BORDA, 2, 0)
	end

	local spinButton = secao:FindFirstChild("spin")
	if spinButton and spinButton:IsA("GuiButton") then
		fixarPosicao(spinButton)
		-- ⚠️ v78: encolhe pra abrir espaço pro ícone de Robux do lado (mesma
		-- linha, mesma coluna esquerda — nunca invade a coluna da
		-- descrição à direita).
		local ROBUX_ICON_W, GAP = 40, 6
		spinButton.Size = UDim2.new(0, spinButton.Size.X.Offset - ROBUX_ICON_W - GAP, 0, spinButton.Size.Y.Offset)
		spinButton.BackgroundColor3 = COR_OK
		spinButton.Font = Enum.Font.GothamBlack
		spinButton.TextSize = 15
		spinButton.Text = "GIRAR"
		spinButton.AutoButtonColor = false
		cantosR(spinButton, 8)
		spinButton.MouseEnter:Connect(function()
			spinButton.BackgroundColor3 = COR_OK:Lerp(Color3.new(1, 1, 1), 0.12)
		end)
		spinButton.MouseLeave:Connect(function()
			spinButton.BackgroundColor3 = COR_OK
		end)

		-- ⚠️ v78 — NOVO: ícone de Robux do lado do GIRAR normal. Clicar
		-- gira especificamente na pool de Robux (chances melhores); sem
		-- crédito de Robux, abre a compra em vez de girar (ver
		-- setupSpinSection, que conecta o clique de verdade).
		local robuxIcon = Instance.new("TextButton")
		robuxIcon.Name = "SpinRobux"
		robuxIcon.Size = UDim2.fromOffset(ROBUX_ICON_W, spinButton.Size.Y.Offset)
		-- fixarPosicao já deixou spinButton.Position em pixel puro (escala
		-- 0) — só soma a largura do spin + respiro, sem risco de compor
		-- com nenhuma escala.
		robuxIcon.Position = UDim2.fromOffset(spinButton.Position.X.Offset + spinButton.Size.X.Offset + GAP, spinButton.Position.Y.Offset)
		robuxIcon.BackgroundColor3 = Color3.fromRGB(60, 130, 90)
		-- ⚠️ FIX: "✦" não existe na fonte Gotham (mesmo bug do "×" antigo —
		-- vira retângulo opaco). "R$" é ASCII puro, sempre renderiza.
		robuxIcon.Text = "R$"
		robuxIcon.Font = Enum.Font.GothamBlack
		robuxIcon.TextSize = 14
		robuxIcon.TextColor3 = Color3.fromRGB(120, 255, 180)
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

		-- ⚠️ v78 — fileira de slots no topo (2 ativos sempre + reserva se
		-- destravada) + botão de trocar o slot selecionado com a reserva.
		-- Construída vazia aqui; populada/atualizada por atualizarSlotRow
		-- (mais abaixo) assim que os dados do servidor chegam.
		local slotRow = Instance.new("Frame")
		slotRow.Name = "SlotRow"
		slotRow.BackgroundTransparency = 1
		slotRow.Size = UDim2.new(1, -24, 0, 30)
		slotRow.Position = UDim2.fromOffset(12, 4)
		slotRow.Parent = secao

		local slotLayout = Instance.new("UIListLayout")
		slotLayout.FillDirection = Enum.FillDirection.Horizontal
		slotLayout.Padding = UDim.new(0, 6)
		slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
		slotLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		slotLayout.Parent = slotRow

		local swapButton = Instance.new("TextButton")
		swapButton.Name = "SwapReserve"
		swapButton.LayoutOrder = 99
		swapButton.Size = UDim2.fromOffset(30, 26)
		swapButton.BackgroundColor3 = COR_CARTAO_ALT
		swapButton.Text = "⇄"
		swapButton.Font = Enum.Font.GothamBlack
		swapButton.TextSize = 16
		swapButton.TextColor3 = COR_ACENTO
		swapButton.AutoButtonColor = false
		swapButton.Visible = false -- só aparece se o jogador tiver o 3º slot destravado
		swapButton.Parent = slotRow
		cantosR(swapButton, 6)

		sectionUI[secao] = {
			nameLabel = nameLabel,
			descLabel = descLabel,
			rngImage = rngImage,
			spinButton = spinButton,
			robuxIcon = robuxIcon,
			slotRow = slotRow,
			swapButton = swapButton,
			chips = {}, -- preenchido por atualizarSlotRow
		}
	end
end

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
local DESENHO_LARGURA, DESENHO_ALTURA = 1049, 431 + SECTION_EXTRA_H + SECTION_BOTTOM_MARGIN
local MARGEM = 24 -- respiro pras bordas, pra nunca encostar no limite da tela

frame.Size = UDim2.new(frame.Size.X.Scale, frame.Size.X.Offset, 0, DESENHO_ALTURA)

local rollScale = frame:FindFirstChildOfClass("UIScale")
if not rollScale then
	rollScale = Instance.new("UIScale")
	rollScale.Parent = frame
end

local function ajustarEscalaDoRoll()
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if not v or v.X <= 0 or v.Y <= 0 then return end
	-- nunca AUMENTA (math.min com 1): esticar a arte deixaria tudo borrado.
	rollScale.Scale = math.min(
		1,
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
buyRollButton.Size = UDim2.fromOffset(150, 34)
buyRollButton.Position = UDim2.new(1, -290, 0.5, 0)
buyRollButton.AnchorPoint = Vector2.new(0, 0.5)
buyRollButton.BackgroundColor3 = COR_OK
buyRollButton.Text = string.format("COMPRAR ROLL ($%d)", LobbyConfig.SHOP.Roll.Cost)
buyRollButton.TextColor3 = Color3.new(1, 1, 1)
buyRollButton.Font = Enum.Font.GothamBlack
buyRollButton.TextSize = 12
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
rollCreditsLabel.Size = UDim2.fromOffset(90, 34)
rollCreditsLabel.Position = UDim2.new(1, -130, 0.5, 0)
rollCreditsLabel.AnchorPoint = Vector2.new(0, 0.5)
rollCreditsLabel.BackgroundTransparency = 1
rollCreditsLabel.Text = string.format("Rolls: %d", rollCredits)
rollCreditsLabel.TextColor3 = COR_TEXTO
rollCreditsLabel.Font = Enum.Font.GothamBold
rollCreditsLabel.TextSize = 14
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
-- ⚠️ v78 — SISTEMA DE SLOTS (2 ativos sempre + 1 reserva se destravada
-- com Robux). CORREÇÃO DO USUÁRIO: "todo mundo, pra ser justo, só vai
-- poder usar 2 hissatsus e 2 armas" — o 3º slot NUNCA vai pra partida
-- (ver PlayerSystems.legacy.luau no place Game), é só armazenamento. A
-- tela de Roll agora:
--   • mostra os 2 slots ativos (+ reserva, se houver) como "chips"
--     clicáveis no topo de cada seção — clicar um escolhe ELE como alvo
--     do próximo GIRAR e mostra o que já está equipado nele;
--   • tem um botão "⇄" (só aparece com a reserva destravada) que troca o
--     slot selecionado com a reserva;
--   • o GIRAR normal gasta 1 crédito de dinheiro e cai no slot
--     selecionado; o ✦ do lado gasta 1 crédito DE ROBUX (chances
--     melhores) no mesmo slot — sem crédito de Robux, abre a compra em
--     vez de girar.
-- ========================================
local SwapAbilitySlot = rollEvents:WaitForChild("SwapAbilitySlot")

local KIND_SECTION = { Pulse = pulseFrame, Instinct = instinctFrame }
local KIND_POOL = { Pulse = PULSE_POOL, Instinct = INSTINCT_POOL }

local equippedState = { Pulse = { nil, nil, nil }, Instinct = { nil, nil, nil } }
local slotsCount = { Pulse = 2, Instinct = 2 }
local selectedSlot = { Pulse = 1, Instinct = 1 }

local SPIN_DURATION = 1.2 -- segundos "girando" antes de revelar o resultado
local SPIN_FLICKER_INTERVAL = 0.06
local spinInProgress = { Pulse = false, Instinct = false }

local function renderPreview(kind)
	local ui = sectionUI[KIND_SECTION[kind]]
	if not ui then return end
	local nome = equippedState[kind][selectedSlot[kind]]
	local item = findByName(KIND_POOL[kind], nome)
	if item then
		local rarity = RARITY_BY_NAME[item.Rarity]
		ui.nameLabel.Text = item.Name
		ui.descLabel.Text = item.Description
		ui.nameLabel.TextColor3 = rarity and rarity.Color or COR_TEXTO
		aplicarIconeDeRaridade(ui.rngImage, item, rarity and rarity.Color)
	else
		ui.nameLabel.Text = "Vazio"
		ui.nameLabel.TextColor3 = COR_TEXTO_FRACO
		ui.descLabel.Text = "Esse slot não tem nada equipado — gire pra preencher."
		aplicarIconeDeRaridade(ui.rngImage, nil, COR_CARTAO_ALT)
	end
end

local atualizarSlotRow -- forward declare (selecionarSlot usa antes de definir)

local function selecionarSlot(kind, slot)
	selectedSlot[kind] = slot
	atualizarSlotRow(kind)
	renderPreview(kind)
end

-- ⚠️ v79 — PEDIDO: "inclua a opção do terceiro slot na área do roll, que
-- ainda não existe... coloque pra quando clicar no slot 3, ele pede a
-- opção de comprar, e desbloqueia ela... é permanente." Antes só
-- renderizava `slotsCount[kind]` chips (2, ou 3 depois de comprado) — o
-- slot de reserva simplesmente não aparecia enquanto travado, então não
-- tinha como descobrir/comprar ele por aqui. Agora SEMPRE desenha 3
-- chips: os 2 primeiros iguais a antes, e o 3º troca de figura conforme
-- `slotsCount[kind]` — destravado (clicável, escolhe ele como alvo,
-- igual aos outros) ou travado (cinza, clicar abre a compra do Developer
-- Product certo pro tipo — ver SLOT_UNLOCK_PRODUCT_ID e o listener de
-- PromptProductPurchaseFinished logo abaixo).
local SLOT_UNLOCK_PRODUCT_ID = {
	Pulse = LobbyConfig.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID,
	Instinct = LobbyConfig.ROBUX_EXTRA_INSTINCT_SLOT_PRODUCT_ID,
}

atualizarSlotRow = function(kind)
	local ui = sectionUI[KIND_SECTION[kind]]
	if not ui then return end

	for _, chip in ipairs(ui.chips) do
		chip:Destroy()
	end
	table.clear(ui.chips)

	local n = slotsCount[kind]
	-- ⚠️ v79: 130 (não 148) — com o botão "⇄" de troca contando no mesmo
	-- UIListLayout, 3 chips de 148 + o botão passavam da largura da
	-- fileira (~457px) e vazavam pra fora do cartão. 130 cabe os 3 chips
	-- + o botão + as folgas entre eles com margem de sobra.
	local largura = 130

	for i = 1, 3 do
		local destravado = i <= n

		local chip = Instance.new("TextButton")
		chip.Name = "SlotChip" .. i
		chip.LayoutOrder = i
		chip.Size = UDim2.fromOffset(largura, 26)
		chip.AutoButtonColor = false
		chip.Font = Enum.Font.GothamBold
		chip.TextSize = 12
		chip.TextTruncate = Enum.TextTruncate.AtEnd
		chip.TextXAlignment = Enum.TextXAlignment.Left
		cantosR(chip, 6)

		if destravado then
			local nome = equippedState[kind][i]
			local item = findByName(KIND_POOL[kind], nome)
			local rarity = item and RARITY_BY_NAME[item.Rarity]
			local selecionado = (selectedSlot[kind] == i)
			local rotulo = (i <= 2) and ("Slot " .. i) or "Reserva"
			chip.Text = "  " .. rotulo .. ": " .. (item and item.Name or "vazio")
			chip.TextColor3 = rarity and rarity.Color or COR_TEXTO_FRACO
			chip.BackgroundColor3 = selecionado and COR_ACENTO:Lerp(COR_CARTAO, 0.65) or COR_CARTAO_ALT
			if selecionado then
				contornoR(chip, COR_ACENTO, 1.5, 0)
			end
			chip.MouseButton1Click:Connect(function()
				selecionarSlot(kind, i)
			end)
		else
			chip.Text = "  Reserva: comprar"
			chip.TextColor3 = COR_TEXTO_FRACO
			chip.BackgroundColor3 = COR_CARTAO
			contornoR(chip, COR_TEXTO_FRACO, 1, 0.5)
			chip.MouseButton1Click:Connect(function()
				local productId = SLOT_UNLOCK_PRODUCT_ID[kind]
				if not productId or productId == 0 then
					warn("RollClient: slot de reserva ainda não configurado (product id = 0 em LobbyConfig.lua).")
					return
				end
				MarketplaceService:PromptProductPurchase(player, productId)
			end)
		end

		chip.Parent = ui.slotRow
		table.insert(ui.chips, chip)
	end

	ui.swapButton.Visible = (n >= 3) and (selectedSlot[kind] ~= 3)
end

local function setupSpinSection(kind)
	local secao = KIND_SECTION[kind]
	local ui = sectionUI[secao]
	local pool = KIND_POOL[kind]
	if not ui then
		warn(string.format("RollClient: a seção '%s' está faltando algum dos filhos esperados (spin/rng/desc/name).", kind))
		return
	end

	local function executarRoll(useRobux)
		if spinInProgress[kind] then return end

		if useRobux then
			if rollCreditsRobux < 1 then
				if LobbyConfig.ROBUX_ROLL_PRODUCT_ID == 0 then
					warn("RollClient: roll com Robux ainda não configurado (ROBUX_ROLL_PRODUCT_ID = 0 em LobbyConfig.lua).")
					return
				end
				MarketplaceService:PromptProductPurchase(player, LobbyConfig.ROBUX_ROLL_PRODUCT_ID)
				return
			end
		else
			if rollCredits < 1 then
				ui.descLabel.Text = "Sem rolls! Compre na Loja ou use o R$ de Robux."
				return
			end
		end

		spinInProgress[kind] = true
		ui.spinButton.AutoButtonColor = false
		ui.robuxIcon.AutoButtonColor = false

		task.spawn(function()
			local targetSlot = selectedSlot[kind]
			-- Sorteio 100% servidor (RollAbility gasta o crédito certo E
			-- decide o resultado, atomicamente — ver RollServer.legacy.luau).
			-- Dispara ANTES da animação: se o servidor recusar, cancela sem
			-- mostrar nada.
			local ok, granted, resultInfo = pcall(function()
				return RollAbility:InvokeServer(kind, targetSlot, useRobux)
			end)

			if not ok or not granted then
				ui.descLabel.Text = "Sem rolls! Compre na Loja ou use o R$ de Robux."
				spinInProgress[kind] = false
				ui.spinButton.AutoButtonColor = true
				ui.robuxIcon.AutoButtonColor = true
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

			local slotUsado = (type(resultInfo) == "table" and resultInfo.Slot) or targetSlot
			equippedState[kind][slotUsado] = resultInfo.Name
			selectedSlot[kind] = slotUsado
			atualizarSlotRow(kind)
			renderPreview(kind)

			spinInProgress[kind] = false
			ui.spinButton.AutoButtonColor = true
			ui.robuxIcon.AutoButtonColor = true
		end)
	end

	ui.spinButton.MouseButton1Click:Connect(function() executarRoll(false) end)
	ui.robuxIcon.MouseButton1Click:Connect(function() executarRoll(true) end)

	ui.swapButton.MouseButton1Click:Connect(function()
		local slot = selectedSlot[kind]
		if slot == 3 then return end
		task.spawn(function()
			local ok, success, novo = pcall(function()
				return SwapAbilitySlot:InvokeServer(kind, slot, 3)
			end)
			if ok and success and type(novo) == "table" then
				equippedState.Pulse[1], equippedState.Pulse[2], equippedState.Pulse[3] = novo.Pulse1, novo.Pulse2, novo.Pulse3
				equippedState.Instinct[1], equippedState.Instinct[2], equippedState.Instinct[3] = novo.Instinct1, novo.Instinct2, novo.Instinct3
				atualizarSlotRow("Pulse")
				atualizarSlotRow("Instinct")
				renderPreview(kind)
			end
		end)
	end)

	-- primeiro desenho (chips vazios, até o fetch abaixo trazer o que já
	-- está equipado de verdade)
	atualizarSlotRow(kind)
	renderPreview(kind)
end

setupSpinSection("Instinct")

-- ⚠️ v5: o sistema de Pulso foi desligado (PulseInstinctData.Pulses está
-- vazio de propósito). Em vez de montar uma seção que não pode sortear
-- nada, a seção de Pulso simplesmente some da tela. Se um dia a lista
-- voltar a ter entradas, ela reaparece sozinha, sem mexer aqui.
if #PULSE_POOL > 0 then
	setupSpinSection("Pulse")
else
	pulseFrame.Visible = false
end

-- ========================================
-- MOSTRAR O QUE JÁ ESTAVA EQUIPADO (corrige o "reset visual" — os dados
-- sempre estiveram salvos certinho no servidor, só que essa tela nunca
-- puxava eles de volta ao abrir, então nome/descrição ficavam em branco
-- até girar de novo, parecendo que tinha perdido o Pulso/Instinto)
-- ========================================
local function refreshEquippedFromServer()
	local ok, equipped = pcall(function()
		return GetEquippedAbilities:InvokeServer()
	end)
	if not ok or type(equipped) ~= "table" then
		warn("RollClient: não consegui buscar as habilidades já equipadas.")
		return
	end

	equippedState.Pulse[1], equippedState.Pulse[2], equippedState.Pulse[3] = equipped.Pulse1, equipped.Pulse2, equipped.Pulse3
	equippedState.Instinct[1], equippedState.Instinct[2], equippedState.Instinct[3] = equipped.Instinct1, equipped.Instinct2, equipped.Instinct3
	slotsCount.Pulse = equipped.PulseSlots or 2
	slotsCount.Instinct = equipped.InstinctSlots or 2

	atualizarSlotRow("Pulse")
	atualizarSlotRow("Instinct")
	renderPreview("Pulse")
	renderPreview("Instinct")
end

task.spawn(refreshEquippedFromServer)

-- ⚠️ v79 — NOVO: compra do 3º slot (reserva), clicando no chip "Reserva:
-- comprar" (ver atualizarSlotRow). Developer Product PERMANENTE (mesmo
-- padrão do RollAbility com Robux — ver Config.ROBUX_EXTRA_PULSE_SLOT_
-- PRODUCT_ID/..._INSTINCT_..., creditado de verdade em RollServer.
-- legacy.luau/ProcessReceipt). Depois de confirmada, busca de novo o
-- estado equipado — é a forma mais simples de saber o novo PulseSlots/
-- InstinctSlots (3) sem duplicar essa conta aqui no cliente.
MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, wasPurchased)
	if userId ~= player.UserId or not wasPurchased then return end
	if productId == LobbyConfig.ROBUX_EXTRA_PULSE_SLOT_PRODUCT_ID
		or productId == LobbyConfig.ROBUX_EXTRA_INSTINCT_SLOT_PRODUCT_ID then
		task.delay(1, refreshEquippedFromServer) -- dá um tempo pro ProcessReceipt do servidor rodar
	end
end)

print("✅ RollClient carregado.")
