--[[
	AbilityHUD (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	PEDIDO: mostrar na tela (1) tudo que está em cooldown, contando
	regressivamente até poder usar de novo, e (2) quais Pulsos/Instinto o
	jogador tem equipados, pra não esquecer.

	Cria a própria GUI via Instance.new (script conta como código, então
	sincroniza pelo bridge — GUI feita direto no Studio não sincronizaria).

	Canto INFERIOR ESQUERDO: Habilidades equipadas (Pulso slot 1/2 — ou só
	slot 1 pro goleiro — e o Instinto). Instinto pisca "ATIVO" quando o
	servidor avisa que a condição dele acabou de ser cumprida (ver
	Remotes.InstinctFeedback — InstinctController.lua no servidor).

	Canto INFERIOR DIREITO: lista de cooldowns ativos, contando regressivo
	("Carrinho: 3s...") e sumindo sozinho quando zera. A maioria é
	PREVISTA localmente (o jogador já sabe a duração de cada cooldown por
	Config.*_COOLDOWN, e o próprio cliente é quem aperta a tecla) — os
	Pulsos usam o feedback real do servidor (Remotes.PulseFeedback), que é
	quem decide o cooldown de cada um (ver PulseInstinctData.lua).

	NADA aqui manda nada pro servidor nem muda nenhuma regra — é 100%
	visual/informativo, só refletindo o que o servidor já decide sozinho.
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
local AbilityAura = require(ReplicatedStorage:WaitForChild("AbilityAura")) -- ⚠️ v45: aura de contorno pulsante (sem pintar o corpo)
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
local Remotes = Config.Remotes

local player = Players.LocalPlayer

local function findPulse(name)
	if not name then return nil end
	for _, def in ipairs(PulseData.Pulses) do
		if def.Name == name then return def end
	end
	return nil
end

local function findInstinct(name)
	if not name then return nil end
	for _, def in ipairs(PulseData.Instincts) do
		if def.Name == name then return def end
	end
	return nil
end

local RARITY_COLOR = {
	Common = Color3.fromRGB(220, 220, 220),
	Rare = Color3.fromRGB(120, 180, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 60),
	Mythic = Color3.fromRGB(255, 90, 110),
}

-- Tradução curta do Trigger, só pra dar contexto de QUANDO cada
-- habilidade dispara/é checada (não é uma descrição completa, só um
-- lembrete rápido).
local TRIGGER_LABEL = {
	KickAtGoal = "ao chutar a gol",
	KickAtTeammate = "ao passar",
	Tackle = "no carrinho",
	Header = "na cabeçada",
	DribbleMove = "na finta",
	SetPiece = "em bola parada",
	Instant = "sempre (condição contínua)",
	Dive = "no mergulho (GK)",
}

-- ===== GUI =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AbilityHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

-- --- Canto inferior esquerdo: habilidades equipadas ---
-- ⚠️ v67 — HUD REFEITA.
-- PEDIDO: "a HUD está muito com cara de IA. Coloca coisas separadas, barras
-- separadas — não esse quadrado cinza falando '100% do Instinct Mode, 100%
-- de Hissatsu'. Coloca ali embaixo duas barrinhas, Flow e Hissatsu,
-- separados, em locais diferentes. E a ARMA na esquerda, na DIREITA as
-- notificações. Deixa mais redondo pra parecer menos IA."
--
-- O QUE HAVIA: um único painel cinza no canto inferior esquerdo com TUDO
-- empilhado dentro — as duas Hissatsus, a Arma, a mensagem de erro e a barra
-- do modo. Tudo com o mesmo peso visual, tudo no mesmo lugar, nada com
-- hierarquia. É exatamente o "cara de IA": informação organizada por
-- conveniência de código, não por importância pro jogador.
--
-- O QUE É AGORA — quatro peças, cada uma no seu canto, todas com canto
-- TOTALMENTE redondo (UDim.new(1,0), não os 8px de antes):
--
--   ARMA        canto inferior ESQUERDO — cartão compacto, some quando vazia
--   HISSATSU    barra fina embaixo, à ESQUERDA do centro
--   FLOW        barra fina embaixo, à DIREITA do centro
--   AVISOS      canto DIREITO — pílula que aparece e some sozinha
--
-- As duas barras ficam separadas por um vão no meio da tela de propósito:
-- são recursos diferentes, com ritmos diferentes, e juntas viravam "mais uma
-- lista". Separadas, dá pra ler qual está cheia sem precisar ler o texto.

local CANTO_REDONDO = UDim.new(1, 0)

local function arredondar(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = raio or CANTO_REDONDO
	c.Parent = inst
	return c
end

local function contorno(inst, cor, transp)
	local st = Instance.new("UIStroke")
	st.Color = cor or Color3.fromRGB(255, 255, 255)
	st.Transparency = transp or 0.85
	st.Thickness = 1
	st.Parent = inst
	return st
end

-- Encolhe tudo um pouco no celular: a tela é menor e os botões de toque já
-- ocupam as bordas.
local ehMobileHUD = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local ESCALA = ehMobileHUD and 0.82 or 1
local function px(v) return math.floor(v * ESCALA + 0.5) end

-- ===================== ARMA (canto inferior esquerdo) =====================
local armaCard = Instance.new("Frame")
armaCard.Name = "ArmaCard"
armaCard.AnchorPoint = Vector2.new(0, 1)
armaCard.Position = UDim2.new(0, px(16), 1, px(-16))
armaCard.Size = UDim2.new(0, px(232), 0, px(52))
armaCard.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
armaCard.BackgroundTransparency = 0.18
armaCard.BorderSizePixel = 0
armaCard.Visible = false
armaCard.Parent = screenGui
arredondar(armaCard)
contorno(armaCard, Color3.fromRGB(255, 255, 255), 0.82)

local armaPad = Instance.new("UIPadding")
armaPad.PaddingLeft = UDim.new(0, px(16))
armaPad.PaddingRight = UDim.new(0, px(14))
armaPad.Parent = armaCard

local armaTitulo = Instance.new("TextLabel")
armaTitulo.Name = "Titulo"
armaTitulo.BackgroundTransparency = 1
armaTitulo.Position = UDim2.new(0, 0, 0, px(8))
armaTitulo.Size = UDim2.new(1, 0, 0, px(12))
armaTitulo.Font = Enum.Font.GothamBold
armaTitulo.TextSize = px(10)
armaTitulo.TextXAlignment = Enum.TextXAlignment.Left
armaTitulo.TextColor3 = Color3.fromRGB(130, 140, 160)
armaTitulo.Text = "ARMA"
armaTitulo.Parent = armaCard

local armaNome = Instance.new("TextLabel")
armaNome.Name = "Nome"
armaNome.BackgroundTransparency = 1
armaNome.Position = UDim2.new(0, 0, 0, px(21))
armaNome.Size = UDim2.new(1, 0, 0, px(20))
armaNome.Font = Enum.Font.GothamBlack
armaNome.TextSize = px(15)
armaNome.TextXAlignment = Enum.TextXAlignment.Left
armaNome.TextTruncate = Enum.TextTruncate.AtEnd
armaNome.TextColor3 = Color3.fromRGB(255, 255, 255)
armaNome.Text = ""
armaNome.Parent = armaCard

-- ===================== HISSATSUS (acima da Arma) =====================
-- ⚠️ v107 — PEDIDO: "os dois slots têm que aparecer na tela da partida (ex.:
-- Tornado de Fogo e Sumiço embaixo)" + "coloca qual é o elemento de cada
-- Hissatsu". A barra de baixo só mostrava o slot 1 (a ponte do slot 2 era
-- vazia). Agora um cartão com as duas linhas: número, nome na cor da
-- raridade e o elemento na cor dele.
local COR_ELEMENTO = {
	Fogo = Color3.fromRGB(255, 125, 45), Vento = Color3.fromRGB(140, 232, 210), Natureza = Color3.fromRGB(115, 212, 110),
	Luz = Color3.fromRGB(255, 226, 115), Void = Color3.fromRGB(175, 115, 255),
}
local hissatsuCard = Instance.new("Frame")
hissatsuCard.Name = "HissatsuCard"
hissatsuCard.AnchorPoint = Vector2.new(0, 1)
hissatsuCard.Position = UDim2.new(0, px(16), 1, px(-76))
hissatsuCard.Size = UDim2.new(0, px(232), 0, px(66))
hissatsuCard.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
hissatsuCard.BackgroundTransparency = 0.18
hissatsuCard.BorderSizePixel = 0
hissatsuCard.Visible = false
hissatsuCard.Parent = screenGui
arredondar(hissatsuCard)
contorno(hissatsuCard, Color3.fromRGB(255, 255, 255), 0.82)
local hissatsuCardPad = Instance.new("UIPadding")
hissatsuCardPad.PaddingLeft = UDim.new(0, px(16))
hissatsuCardPad.PaddingRight = UDim.new(0, px(14))
hissatsuCardPad.Parent = hissatsuCard
local hissatsuCardTitulo = armaTitulo:Clone()
hissatsuCardTitulo.Text = "HISSATSUS"
hissatsuCardTitulo.Parent = hissatsuCard
local hissatsuCardLinhas = {}
for i = 1, 2 do
	local l = armaNome:Clone()
	l.Name = "Slot" .. i
	l.Position = UDim2.new(0, 0, 0, px(21 + (i - 1) * 20))
	l.Size = UDim2.new(1, 0, 0, px(18))
	l.TextSize = px(13)
	l.RichText = true
	l.Parent = hissatsuCard
	hissatsuCardLinhas[i] = l
end
local function corHex(c)
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

-- ===================== BARRAS DE BAIXO =====================
-- Fábrica única: as duas barras são irmãs, só mudam de lado e de cor.
local function criarBarra(nome, ancoraX, offsetX, cor, rotulo)
	local frame = Instance.new("Frame")
	frame.Name = nome
	frame.AnchorPoint = Vector2.new(ancoraX, 1)
	frame.Position = UDim2.new(0.5, px(offsetX), 1, px(-22))
	frame.Size = UDim2.new(0, px(180), 0, px(26))
	frame.BackgroundTransparency = 1
	frame.Parent = screenGui

	local texto = Instance.new("TextLabel")
	texto.Name = "Rotulo"
	texto.BackgroundTransparency = 1
	texto.Size = UDim2.new(1, 0, 0, px(11))
	texto.Font = Enum.Font.GothamBold
	texto.TextSize = px(10)
	texto.TextXAlignment = (ancoraX < 0.5) and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	texto.TextColor3 = Color3.fromRGB(140, 150, 170)
	texto.Text = rotulo
	texto.Parent = frame

	local trilho = Instance.new("Frame")
	trilho.Name = "Trilho"
	trilho.AnchorPoint = Vector2.new(0, 1)
	trilho.Position = UDim2.new(0, 0, 1, 0)
	trilho.Size = UDim2.new(1, 0, 0, px(7))
	trilho.BackgroundColor3 = Color3.fromRGB(26, 28, 36)
	trilho.BackgroundTransparency = 0.25
	trilho.BorderSizePixel = 0
	trilho.Parent = frame
	arredondar(trilho)

	local preenche = Instance.new("Frame")
	preenche.Name = "Preenchimento"
	preenche.Size = UDim2.new(0, 0, 1, 0)
	preenche.BackgroundColor3 = cor
	preenche.BorderSizePixel = 0
	preenche.Parent = trilho
	arredondar(preenche)

	return frame, texto, preenche
end

-- HISSATSU à esquerda do centro, FLOW à direita — o vão no meio é o que
-- impede que as duas voltem a parecer uma lista só.
local hissatsuFrame, hissatsuRotulo, hissatsuFill =
	criarBarra("BarraHissatsu", 1, -14, Color3.fromRGB(255, 190, 70), "HISSATSU")
local instinctModeFrame, instinctModeLabel, instinctModeBarFill =
	criarBarra("BarraFlow", 0, 14, Color3.fromRGB(90, 175, 255), "FLOW")

-- ===================== AVISOS (canto direito) =====================
local avisoPill = Instance.new("TextLabel")
avisoPill.Name = "Aviso"
avisoPill.AnchorPoint = Vector2.new(1, 1)
avisoPill.Position = UDim2.new(1, px(-16), 1, px(-16))
avisoPill.Size = UDim2.new(0, px(250), 0, px(34))
avisoPill.AutomaticSize = Enum.AutomaticSize.Y
avisoPill.BackgroundColor3 = Color3.fromRGB(44, 18, 22)
avisoPill.BackgroundTransparency = 0.12
avisoPill.BorderSizePixel = 0
avisoPill.Font = Enum.Font.GothamMedium
avisoPill.TextSize = px(12)
avisoPill.TextColor3 = Color3.fromRGB(255, 186, 186)
avisoPill.TextWrapped = true
avisoPill.Text = ""
avisoPill.Visible = false
avisoPill.Parent = screenGui
arredondar(avisoPill, UDim.new(0, px(14)))
contorno(avisoPill, Color3.fromRGB(255, 120, 120), 0.7)

local avisoPad = Instance.new("UIPadding")
avisoPad.PaddingLeft = UDim.new(0, px(14))
avisoPad.PaddingRight = UDim.new(0, px(14))
avisoPad.PaddingTop = UDim.new(0, px(9))
avisoPad.PaddingBottom = UDim.new(0, px(9))
avisoPad.Parent = avisoPill

-- ===================== PONTES PRO CÓDIGO QUE JÁ EXISTIA =====================
-- O resto do arquivo continua escrevendo em pulse1Line/pulse2Line/
-- instinctLine como antes. Em vez de sair caçando todos os pontos de
-- atualização espalhados (e arriscar esquecer um), eles viram objetos-ponte
-- com a mesma interface (.Text) que redireciona pro visual novo.
local function ponte(aoEscrever)
	return setmetatable({}, {
		__newindex = function(_, chave, valor)
			if chave == "Text" then aoEscrever(valor) end
		end,
		__index = function() return "" end,
	})
end

-- Rótulo da barra de Hissatsu = nome da equipada + energia. As duas
-- informações chegam de lugares diferentes e em momentos diferentes, então
-- cada uma guarda a sua parte e uma função só recompõe o texto — sem isso,
-- quem escrevesse por último apagaria a metade do outro.
local hissatsuNome = nil
local hissatsuEnergiaTexto = nil

function atualizarRotuloHissatsu()
	local partes = { "HISSATSU" }
	if hissatsuNome then table.insert(partes, maiusculas(hissatsuNome)) end
	if hissatsuEnergiaTexto then table.insert(partes, hissatsuEnergiaTexto) end
	hissatsuRotulo.Text = table.concat(partes, " · ")
end

local pulse1Line = ponte(function(texto)
	-- "1: Nome (Raridade)" -> só o nome interessa
	local t = tostring(texto)
	local nome = t:match("^1:%s*(.-)%s*%(") or t:match("^1:%s*(.+)$") or ""
	if nome == "" or nome == "(vazio)" then
		hissatsuNome = nil
	else
		hissatsuNome = nome
	end
	atualizarRotuloHissatsu()
end)

-- Slot 2 não tem barra própria (o servidor já limpa esse texto pro goleiro);
-- a ponte existe só pra as escritas espalhadas continuarem válidas.
local pulse2Line = ponte(function() end)

local instinctLine = ponte(function(texto)
	local t = tostring(texto)
	local nome = t:match("^Arma:%s*(.-)%s*%(") or ""
	local ativo = string.find(t, "ATIVO") ~= nil
	if nome == "" or nome == "(vazio)" then
		armaCard.Visible = false
	else
		armaCard.Visible = true
		armaNome.Text = nome
		armaNome.TextColor3 = ativo and Color3.fromRGB(120, 255, 150) or Color3.fromRGB(255, 255, 255)
		armaTitulo.Text = ativo and "ARMA · ATIVA" or "ARMA"
	end
end)

local reasonToken = 0
local function showInstinctReason(text)
	reasonToken += 1
	local myToken = reasonToken
	avisoPill.Text = text
	avisoPill.Visible = true
	task.delay(3.5, function()
		if reasonToken == myToken then
			avisoPill.Visible = false
		end
	end)
end

local instinctBaseText = ""
local instinctActive = false
local function refreshInstinctLine()
	if instinctBaseText == "" then
		instinctLine.Text = ""
		return
	end
	instinctLine.Text = instinctBaseText .. (instinctActive and "  ATIVO" or "")
end

local instinctModeBannerActive = false
-- ⚠️ v110: o Flow escolhido na Loja aparece no rótulo ("FLOW · BACHIRA · 40%")
local CosmeticosHUD = nil
pcall(function() CosmeticosHUD = require(ReplicatedStorage:WaitForChild("Cosmeticos", 5)) end)
local function nomeDoFlow()
	local item = CosmeticosHUD and CosmeticosHUD.Equipado(Players.LocalPlayer, "Flow")
	if not item then return "FLOW", nil end
	local curto = item.Nome:gsub("^Flow d[oa] ", "")
	return "FLOW · " .. maiusculas(curto), item.Tema and item.Tema.Cor
end
local ultimoPercentFlow = 0
local function refreshInstinctModeLabel(meterPercent)
	local rotulo, corFlow = nomeDoFlow()
	if instinctModeBannerActive then
		-- ⚠️ v67 — PEDIDO: "eu não quero que isso seja modo instinto. Vai ser
		-- FLOW, igual ao Blue Lock."
		instinctModeLabel.Text = rotulo .. " · ATIVO"
		instinctModeLabel.TextColor3 = corFlow or Color3.fromRGB(120, 210, 255)
	elseif Players.LocalPlayer:GetAttribute("FlowUsado") then
		-- ⚠️ v113: 1 Flow por partida
		instinctModeLabel.Text = rotulo .. " · USADO NESTA PARTIDA"
		instinctModeLabel.TextColor3 = Color3.fromRGB(120, 125, 140)
	else
		instinctModeLabel.Text = (meterPercent or 0) >= 100 and (rotulo .. " · PRONTO") or (rotulo .. (" · %d%%"):format(meterPercent or 0))
		instinctModeLabel.TextColor3 = (meterPercent or 0) >= 100
			and Color3.fromRGB(120, 210, 255) or Color3.fromRGB(140, 150, 170)
	end
end

Players.LocalPlayer:GetAttributeChangedSignal("Cosm_Flow"):Connect(function()
	refreshInstinctModeLabel(instinctModeBannerActive and 100 or ultimoPercentFlow)
end)
Players.LocalPlayer:GetAttributeChangedSignal("FlowUsado"):Connect(function()
	refreshInstinctModeLabel(instinctModeBannerActive and 100 or ultimoPercentFlow)
end)

Remotes.InstinctModeFeedback.OnClientEvent:Connect(function(kind, extra)
	if kind == "MeterUpdate" then
		local percent = tonumber(extra) or 0
		ultimoPercentFlow = percent
		instinctModeBarFill.Size = UDim2.new(math.clamp(percent / 100, 0, 1), 0, 1, 0)
		instinctModeBarFill.BackgroundColor3 = (percent >= 100) and Color3.fromRGB(255, 210, 90) or Color3.fromRGB(120, 255, 140)
		if not instinctModeBannerActive then
			refreshInstinctModeLabel(percent)
		end
	elseif kind == "ModeActivated" then
		instinctModeBannerActive = true
		instinctModeBarFill.BackgroundColor3 = Color3.fromRGB(120, 255, 140)
		refreshInstinctModeLabel(100)
	elseif kind == "ModeEnded" then
		instinctModeBannerActive = false
		refreshInstinctModeLabel(0)
	end
end)

-- ⚠️ v9 PEDIDO: "ainda não está aparecendo a energia de ativação da
-- Hissatsu" — barra de energia de ativação (Config.PULSE_ENERGY_*, ver
-- PulseController.legacy.luau/_G.GetPulseEnergy), separada do Instinct
-- Mode acima. O tamanho do pool (o "cheio" da barra) já escala com o
-- atributo Energy do jogador — quanto maior Energy, mais Pulsos dá pra
-- ativar antes de esvaziar.
-- ⚠️ v67 — A ENERGIA DA HISSATSU É A BARRA DE HISSATSU.
-- Antes este medidor criava a PRÓPRIA barra dentro do painel cinza (que não
-- existe mais). Como o pedido foi justamente "duas barrinhas, Flow e
-- Hissatsu, separadas, em locais diferentes", ele passa a alimentar a barra
-- de Hissatsu criada lá em cima — em vez de desenhar uma terceira.
--
-- As variáveis mantêm os nomes antigos de propósito: o resto do arquivo
-- escreve nelas em vários pontos, e trocar os nomes só criaria chance de
-- esquecer um.
local pulseEnergyBarFill = hissatsuFill
local pulseEnergyLabel = setmetatable({}, {
	__newindex = function(_, chave, valor)
		if chave ~= "Text" then return end
		-- O texto vem como "Energia da Hissatsu: 80/140". Só os números
		-- interessam — o nome da Hissatsu equipada já está no rótulo da barra
		-- (ver a ponte de pulse1Line), então repetir "Hissatsu" aqui seria o
		-- tipo de redundância que deixava a HUD pesada.
		local atual, maximo = string.match(tostring(valor), "(%d+)%s*/%s*(%d+)")
		if atual and maximo then
			hissatsuEnergiaTexto = atual .. "/" .. maximo
		else
			hissatsuEnergiaTexto = nil
		end
		atualizarRotuloHissatsu()
	end,
	__index = function() return "" end,
})

Remotes.PulseEnergyFeedback.OnClientEvent:Connect(function(current, max)
	current = tonumber(current) or 0
	max = math.max(tonumber(max) or 1, 1)
	local fraction = math.clamp(current / max, 0, 1)
	pulseEnergyBarFill.Size = UDim2.new(fraction, 0, 1, 0)
	pulseEnergyBarFill.BackgroundColor3 = (fraction < 0.3) and Color3.fromRGB(255, 100, 90) or Color3.fromRGB(90, 200, 255)
	pulseEnergyLabel.Text = ("Energia da Hissatsu: %d/%d"):format(current, max)
end)

-- --- Canto inferior direito: cooldowns ativos ---
local cooldownFrame = Instance.new("Frame")
cooldownFrame.Name = "CooldownPanel"
cooldownFrame.AnchorPoint = Vector2.new(1, 1)
cooldownFrame.Position = UDim2.new(1, -12, 1, -12)
cooldownFrame.Size = UDim2.new(0, 220, 0, 0)
cooldownFrame.AutomaticSize = Enum.AutomaticSize.Y
cooldownFrame.BackgroundTransparency = 1
cooldownFrame.Parent = screenGui

local cooldownLayout = Instance.new("UIListLayout")
cooldownLayout.FillDirection = Enum.FillDirection.Vertical
cooldownLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
cooldownLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
cooldownLayout.Padding = UDim.new(0, 4)
cooldownLayout.SortOrder = Enum.SortOrder.LayoutOrder
cooldownLayout.Parent = cooldownFrame

-- [id] = { ExpiresAt, Duration, Label(string), GuiLabel(TextLabel) }
local activeCooldowns = {}
local cooldownOrder = 0

local function startCooldown(id, label, duration)
	if duration <= 0 then return end
	local existing = activeCooldowns[id]
	if existing and existing.ExpiresAt - tick() > 0.05 then
		return -- já contando (não reseta por causa de tecla repetida/spam)
	end

	local guiLabel = existing and existing.GuiLabel
	if not guiLabel then
		cooldownOrder += 1
		guiLabel = Instance.new("TextLabel")
		guiLabel.Name = id
		guiLabel.LayoutOrder = cooldownOrder
		guiLabel.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
		guiLabel.BackgroundTransparency = 0.35
		guiLabel.BorderSizePixel = 0
		guiLabel.Size = UDim2.new(1, 0, 0, 24)
		guiLabel.Font = Enum.Font.GothamBold
		guiLabel.TextSize = 13
		guiLabel.TextColor3 = Color3.fromRGB(255, 210, 90)
		guiLabel.TextXAlignment = Enum.TextXAlignment.Right
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = guiLabel
		local padding = Instance.new("UIPadding")
		padding.PaddingRight = UDim.new(0, 8)
		padding.Parent = guiLabel
		guiLabel.Parent = cooldownFrame
	end

	activeCooldowns[id] = {
		ExpiresAt = tick() + duration,
		Duration = duration,
		Label = label,
		GuiLabel = guiLabel,
	}
end

RunService.RenderStepped:Connect(function()
	for id, data in pairs(activeCooldowns) do
		local remaining = data.ExpiresAt - tick()
		if remaining <= 0 then
			data.GuiLabel:Destroy()
			activeCooldowns[id] = nil
		else
			data.GuiLabel.Text = ("%s: %.0fs..."):format(data.Label, math.max(remaining, 0.1))
		end
	end
end)

-- ===== CARREGA HABILIDADES EQUIPADAS =====
-- ⚠️ v76: Pulse3 (Hissatsu extra, Robux) + Instinct1/2/3 (Arma virou
-- lista de até 3 — ver InstinctController.legacy.luau) no lugar do
-- "Instinct" singular antigo.
local equipped = { Pulse1 = nil, Pulse2 = nil, Pulse3 = nil, Instinct1 = nil, Instinct2 = nil, Instinct3 = nil }

local function refreshAbilitiesPanel()
	-- ⚠️ v6: tecla real dos slots de Pulso é "1"/"2" (ver HissatsuInput.
	-- local.luau) — Q/E/R eram do sistema antigo (nunca chegou a ter
	-- input de verdade ligado).
	-- ⚠️ v106 — PEDIDO: "os dois têm que aparecer na tela da partida — Fire
	-- Tornado e, embaixo, Sumiço". O slot 2 ficava SEMPRE em branco (sobra da
	-- época de 1 Hissatsu só). Agora as duas linhas, e a de goleiro avisa que
	-- só funciona no gol.
	local function linha(label, numero, def)
		-- ⚠️ v107: cartão dos dois slots (ver HissatsuCard)
		local l = hissatsuCardLinhas[numero]
		if l then
			if def then
				local corNome = RARITY_COLOR[def.Rarity] or Color3.fromRGB(255, 255, 255)
				local elem = def.Element and string.format('  <font color="%s" size="%d">%s</font>',
					corHex(COR_ELEMENTO[def.Element] or Color3.fromRGB(200, 200, 200)), px(11), maiusculas(def.Element)) or ""
				local gk = def.RoleRequired == "GK" and string.format('  <font color="#8C96AA" size="%d">GOLEIRO</font>', px(10)) or ""
				l.Text = string.format('<font color="#8C96AA">%d</font>  <font color="%s">%s</font>%s%s', numero, corHex(corNome), def.Name, elem, gk)
			else
				l.Text = string.format('<font color="#8C96AA">%d  (vazio)</font>', numero)
			end
			local algum = false
			for _, x in ipairs(hissatsuCardLinhas) do
				if not string.find(x.Text, "(vazio)", 1, true) and x.Text ~= "" then algum = true end
			end
			hissatsuCard.Visible = algum
		end
		if def then
			local extra = def.RoleRequired == "GK" and "  · goleiro" or ""
			label.Text = numero .. ": " .. def.Name .. " (" .. def.Rarity .. ")" .. extra
			label.TextColor3 = RARITY_COLOR[def.Rarity] or Color3.fromRGB(255, 255, 255)
		else
			label.Text = numero .. ": (vazio)"
			label.TextColor3 = Color3.fromRGB(150, 150, 150)
		end
	end
	linha(pulse1Line, 1, findPulse(equipped.Pulse1))
	linha(pulse2Line, 2, findPulse(equipped.Pulse2))

	-- ⚠️ v76: junta os nomes de TODOS os slots de Arma equipados (até 3),
	-- não só um — "Apostador, Xerife" em vez de só o primeiro. O "ATIVO"
	-- (ver refreshInstinctLine) ainda é só um sinalizador geral: acende
	-- quando QUALQUER um dos equipados dispara (ver InstinctFeedback
	-- mais abaixo).
	local nomes = {}
	-- ⚠️ v111 — PEDIDO: "não tá claro como é que você usa". Arma de tecla
	-- mostra a tecla do slot (E = slot 1, R = slot 2) do lado do nome.
	local TECLA_DO_SLOT = { Instinct1 = "E", Instinct2 = "R" }
	for _, campo in ipairs({ "Instinct1", "Instinct2", "Instinct3" }) do
		local def = findInstinct(equipped[campo])
		if def then
			local tecla = def.Tecla and TECLA_DO_SLOT[campo]
			table.insert(nomes, tecla and (def.Name .. " [" .. tecla .. "]") or def.Name)
		end
	end
	if #nomes > 0 then
		instinctBaseText = "Arma: " .. table.concat(nomes, ", ")
	else
		instinctBaseText = "Arma: (vazio)"
	end
	refreshInstinctLine()
end

local function loadEquippedAbilities()
	local ok, result = pcall(function()
		return Remotes.GetMyAbilities:InvokeServer()
	end)
	if ok and typeof(result) == "table" then
		equipped.Pulse1 = result.Pulse1
		equipped.Pulse2 = result.Pulse2
		equipped.Pulse3 = result.Pulse3
		equipped.Instinct1 = result.Instinct1
		equipped.Instinct2 = result.Instinct2
		equipped.Instinct3 = result.Instinct3
	end
	refreshAbilitiesPanel()
end

player.CharacterAdded:Connect(function()
	task.wait(0.5) -- dá tempo do servidor terminar de setar Role/Loadout no spawn
	loadEquippedAbilities()
end)
task.spawn(function()
	task.wait(1)
	loadEquippedAbilities()
end)

player:GetAttributeChangedSignal("Role"):Connect(refreshAbilitiesPanel)
-- ⚠️ v106: o servidor avisa quando os slots chegaram (pode ser depois do spawn)
player:GetAttributeChangedSignal("LoadoutVersao"):Connect(loadEquippedAbilities)

-- ===== FEEDBACK DO SERVIDOR: Pulso (cooldown real) e Instinto (ativo) =====
-- REWORK "PULSO": o cooldown agora começa no instante em que o botão é
-- apertado (kind "Used"), não mais quando a ação "consome" depois de uma
-- ação normal bater — ver PulseController.lua. Mantém "Activated"/
-- "Consumed" como aliases aceitos por compatibilidade, caso algum outro
-- script ainda dispare esses kinds antigos.
--
-- ⚠️ PULSO v3: NENHUM Pulso é mais "1x por partida" — os dois Míticos
-- passaram a RECARREGAR como todo mundo (Cooldown = 100s e 90s, ver
-- PulseInstinctData.luau), então esta barra de cooldown agora cobre a
-- tabela inteira: todo Pulso tem Cooldown e todo Pulso aparece aqui
-- contando regressivo. Não existe mais nenhum caso de "usou e acabou".
-- Uma ressalva: a chave CooldownRefundOther (Pulso do Desarme Limpo/
-- Maestro) devolve parte do cooldown do OUTRO slot lá no servidor, e
-- este contador é PREVISTO localmente — nesse caso específico o número
-- na tela pode ficar alguns segundos mais pessimista que a verdade (o
-- Pulso volta antes do contador zerar; nada trava por causa disso,
-- porque quem decide se pode usar é sempre o servidor).
-- ⚠️ v24 — PEDIDO: "toda vez que você acertar no Quick Time Event da
-- Hissatsu de chute ou na de GK, aparece uma bolinha verde em volta de você
-- piscando. Se acertar uma melhorzinha, pisca dourado. Se errar, pisca
-- vermelho."
--
-- Um Highlight de vida curta no próprio personagem, uma piscada por acerto.
-- É só leitura visual — não muda número nenhum. O servidor manda a
-- qualidade em cada passo do QTE (ver PulseFeedback "ComboStep" em
-- PulseController.legacy.luau).
local QTE_FLASH_COLORS = {
	Perfect = Color3.fromRGB(255, 205, 60),  -- dourado: acertou na faixa perfeita
	Hit = Color3.fromRGB(70, 230, 120),      -- verde: acertou
	Miss = Color3.fromRGB(235, 60, 60),      -- vermelho: errou
}
local QTE_FLASH_SECONDS = 0.18
local qteFlashToken = 0

local function flashQTE(kindKey)
	local character = player.Character
	if not character then return end

	qteFlashToken += 1
	local myToken = qteFlashToken

	-- ⚠️ v45 — PEDIDO: "não quero esses highlights padrão de ForceField, e
	-- de mudar a cor do personagem." Pintava o corpo inteiro
	-- (FillTransparency 0.45). Agora é a aura de contorno "Blink": uma
	-- piscada seca que se apaga sozinha, na cor do resultado (dourado/
	-- verde/vermelho). Ver ReplicatedStorage/AbilityAura.
	local color = QTE_FLASH_COLORS[kindKey] or QTE_FLASH_COLORS.Hit
	local highlight = AbilityAura.Apply(character, "QTEFlashAura", "QTE", color)
	if not highlight then return end

	task.delay(QTE_FLASH_SECONDS, function()
		-- Só apaga se nenhum acerto novo chegou no meio tempo — senão uma
		-- sequência rápida de cliques apagaria a piscada do clique seguinte.
		-- ⚠️ v47: DESTRÓI a aura em vez de só desabilitar — "acabou o
		-- negócio, sumiu e voltou ao normal". Deixar a Instance desabilitada
		-- pendurada no personagem não muda a tela, mas vai acumulando lixo a
		-- cada QTE e deixa um Highlight órfão pronto pra confundir qualquer
		-- coisa que varra os filhos do personagem depois.
		if qteFlashToken == myToken and highlight.Parent then
			AbilityAura.Clear(character, "QTEFlashAura")
		end
	end)
end

Remotes.PulseFeedback.OnClientEvent:Connect(function(kind, extra)
	if kind == "ComboStep" and typeof(extra) == "table" then
		if not extra.Hit then
			flashQTE("Miss")
		elseif extra.Perfect then
			flashQTE("Perfect")
		else
			flashQTE("Hit")
		end
		return
	end
	-- ⚠️ v108: aviso de texto do servidor (ex.: Zona Morta sem companheiros / falhou)
	if kind == "Aviso" and typeof(extra) == "string" then
		showInstinctReason(extra)
		return
	end
	-- ⚠️ v110 (debugger): cooldowns das Hissatsus zerados — some a contagem
	if kind == "CooldownsZerados" then
		for id, data in pairs(activeCooldowns) do
			if id:sub(1, 6) == "Pulse_" then
				data.GuiLabel:Destroy()
				activeCooldowns[id] = nil
			end
		end
		return
	end
	if kind ~= "Used" and kind ~= "Activated" and kind ~= "Consumed" then return end
	-- ⚠️ v110 (debugger "sem cooldown"): o servidor não conta, o HUD também não
	if player:GetAttribute("DebugSemCooldown") then return end
	local pulseName = extra
	local def = findPulse(pulseName)
	if not def or not def.Cooldown then return end

	-- ⚠️ v6: tecla real do slot de Pulso é "1"/"2" (ver HissatsuInput.local.
	-- luau) — Q/E/R aqui em cima ficaram OBSOLETAS (R virou a tecla do
	-- Instinto, Q/E do goleiro viraram mergulho, e nenhum script nunca
	-- ligou Q/E ao Pulso de verdade).
	local slotLabel = (pulseName == equipped.Pulse2 and "2") or (pulseName == equipped.Pulse3 and "3") or "1"
	startCooldown("Pulse_" .. pulseName, pulseName .. " (" .. slotLabel .. ")", def.Cooldown)
end)

-- ⚠️ v5.4 — PEDIDO: mostrar o timing do Instinto "Apostador" (a cada
-- 15s, uma jogada de sorte) no canto direito da tela. Reaproveita o
-- painel de cooldowns que já existe ali (mesmo canto, mesmo visual dos
-- outros cooldowns) em vez de criar um elemento novo.
Remotes.GambleTimerFeedback.OnClientEvent:Connect(function(secondsUntilNextRoll)
	if typeof(secondsUntilNextRoll) == "number" and secondsUntilNextRoll > 0 then
		startCooldown("Apostador_Timer", "Apostador: sorte em", secondsUntilNextRoll)
	end
end)

Remotes.InstinctFeedback.OnClientEvent:Connect(function(active, name, reason, cooldown)
	if name ~= equipped.Instinct1 and name ~= equipped.Instinct2 and name ~= equipped.Instinct3 then return end
	instinctActive = active and true or false
	refreshInstinctLine()
	if not active and reason then
		showInstinctReason(reason)
	end
	-- ⚠️ v111: arma de tecla usada — conta o cooldown no painel
	if active and typeof(cooldown) == "number" and cooldown > 0.5 then
		local tecla = (name == equipped.Instinct2) and "R" or "E"
		startCooldown("Arma_" .. name, name .. " (" .. tecla .. ")", cooldown)
	end
end)

-- ===== COOLDOWNS PREVISTOS LOCALMENTE (carrinho / drible / goleiro) =====
-- Previstos porque o PRÓPRIO cliente é quem decide apertar a tecla — a
-- duração vem direto de Config.*_COOLDOWN, exatamente o que o servidor
-- usa (ver BallController.lua), então fica preciso sem precisar de um
-- remote extra só pra confirmar.
local hasPossession = false
Remotes.PossessionChanged.OnClientEvent:Connect(function(owner, has)
	if owner == player then
		hasPossession = has
	elseif has then
		hasPossession = false
	end
end)

-- ⚠️ NOVO: esquema de teclas novo — Q = drible direcional (e, pro goleiro
-- dentro da área, Q + direção = mergulho), F = dash/carrinho (e, pro
-- goleiro na área, F = saída). Antes: Z/X/C finta, Z carrinho, Z/X/C/E/Q
-- mergulho.
local DRIBBLE_KEYS = { [Enum.KeyCode.Q] = true }
local GK_DIVE_KEYS = { [Enum.KeyCode.Q] = true }
local DASH_KEY = Enum.KeyCode.F

UserInputService.InputBegan:Connect(function(input, gameProcessedEvent)
	if gameProcessedEvent then return end
	-- ⚠️ PULSO v3: enquanto um COMBO de Pulso está pendente, Q/E/R são
	-- consumidas por ele (ver PulseInput.local.luau) — nenhuma delas vira
	-- mergulho/carrinho de verdade, então também não pode aparecer um
	-- cooldown "previsto" aqui por causa de um passo do combo.
	if player:GetAttribute("PulseComboActive") then return end
	local isGK = player:GetAttribute("Role") == "GK"

	if isGK then
		if GK_DIVE_KEYS[input.KeyCode] then
			startCooldown("GKDive", "Mergulho", Config.GK_DIVE_COOLDOWN)
		elseif input.KeyCode == Enum.KeyCode.F then
			startCooldown("GKForward", "Avanço", Config.GK_FORWARD_COOLDOWN)
		end
		return
	end

	-- ⚠️ v86: Q = carrinho SEM bola / drible COM bola; F = dash (sempre).
	if input.KeyCode == DASH_KEY then
		startCooldown("Dash", "Dash", Config.DASH_COOLDOWN)
	end
	if DRIBBLE_KEYS[input.KeyCode] then
		if hasPossession then
			startCooldown("Dribble", "Drible", Config.DRIBBLE_MOVE_COOLDOWN)
		else
			startCooldown("Tackle", "Carrinho", Config.TACKLE_COOLDOWN)
		end
	end
end)

-- =====================================================================
-- ⚠️ v118 — BARRA DE HABILIDADES (estilo RPG)
-- PEDIDO: "uma HUD melhor de habilidades, que mostra cada habilidade que você
-- tem — a arma, a Hissatsu, a quantidade do flow —, quando ela gastou, quanto
-- tempo falta pra voltar e quando voltou. Fica mais escuro quando está sendo
-- usada/recarregando e volta ao normal quando pode usar de novo."
--
-- Uma fileira de slots no centro de baixo: [1][2] Hissatsus · [E][R] Armas ·
-- [Q][F] drible/carrinho e dash · [V] Flow. Cada slot tem a tecla, o nome, a
-- cor da raridade; em recarga escurece de cima pra baixo com a contagem no
-- meio, e pisca quando volta. Os cartões e barras antigos ficam escondidos (o
-- código que escreve neles continua igual, só não aparecem mais).
-- =====================================================================
do
	local antigo = Instance.new("Folder")
	antigo.Name = "HUDAntiga"
	antigo.Parent = script
	for _, g in ipairs({ armaCard, hissatsuCard, hissatsuFrame, instinctModeFrame, cooldownFrame }) do
		g.Parent = antigo
	end

	local TweenService = game:GetService("TweenService")
	local COR_FUNDO = Color3.fromRGB(16, 18, 26)
	local COR_TECLA = Color3.fromRGB(34, 38, 52)
	local COR_TEXTO_FRACO = Color3.fromRGB(130, 140, 160)
	local TAM = px(62)

	local barra = Instance.new("Frame")
	barra.Name = "BarraHabilidades"
	barra.AnchorPoint = Vector2.new(0.5, 1)
	barra.Position = UDim2.new(0.5, 0, 1, px(-14))
	barra.Size = UDim2.new(0, 0, 0, TAM + px(26))
	barra.AutomaticSize = Enum.AutomaticSize.X
	barra.BackgroundTransparency = 1
	barra.Parent = screenGui
	local lista = Instance.new("UIListLayout")
	lista.FillDirection = Enum.FillDirection.Horizontal
	lista.HorizontalAlignment = Enum.HorizontalAlignment.Center
	lista.VerticalAlignment = Enum.VerticalAlignment.Bottom
	lista.Padding = UDim.new(0, px(7))
	lista.SortOrder = Enum.SortOrder.LayoutOrder
	lista.Parent = barra

	local function grupo(ordem, titulo, n)
		local g = Instance.new("Frame")
		g.Name = "Grupo_" .. titulo
		g.LayoutOrder = ordem
		g.BackgroundTransparency = 1
		-- largura FIXA (n slots): com AutomaticSize a barra de energia (100% da
		-- largura do grupo) realimentava o tamanho e o grupo esticava a tela toda
		g.Size = UDim2.new(0, n * TAM + (n - 1) * px(5), 0, TAM + px(26))
		g.Parent = barra
		local l = Instance.new("UIListLayout")
		l.FillDirection = Enum.FillDirection.Horizontal
		l.VerticalAlignment = Enum.VerticalAlignment.Bottom
		l.Padding = UDim.new(0, px(5))
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = g
		-- título e extras ficam numa Folder: o UIListLayout só arruma os filhos
		-- DIRETOS, então o que está na Folder fica por cima, fora do fluxo
		local fora = Instance.new("Folder")
		fora.Name = "Fora"
		fora.Parent = g
		local cab = Instance.new("TextLabel")
		cab.Name = "Titulo"
		cab.BackgroundTransparency = 1
		cab.AnchorPoint = Vector2.new(0, 1)
		cab.Position = UDim2.new(0, px(2), 1, -TAM - px(8))
		cab.Size = UDim2.new(1, 0, 0, px(12))
		cab.Font = Enum.Font.GothamBold
		cab.TextSize = px(11)
		cab.TextColor3 = Color3.fromRGB(190, 198, 215)
		cab.TextStrokeTransparency = 0.6
		cab.TextXAlignment = Enum.TextXAlignment.Left
		cab.Text = titulo
		cab.Parent = fora
		return g, cab
	end

	local function iniciais(nome)
		local partes = {}
		for p in string.gmatch(nome or "", "[%w\128-\255]+") do
			if #p > 2 or #partes == 0 then table.insert(partes, p) end
		end
		if #partes >= 2 then
			return maiusculas(partes[1]:sub(1, 1) .. partes[2]:sub(1, 1))
		end
		return maiusculas((partes[1] or "?"):sub(1, 2))
	end

	local slots = {} -- [id] = slot
	local function criarSlot(pai, id, tecla, ordem)
		local f = Instance.new("Frame")
		f.Name = "Slot_" .. id
		f.LayoutOrder = ordem
		f.Size = UDim2.new(0, TAM, 0, TAM)
		f.BackgroundColor3 = COR_FUNDO
		f.BackgroundTransparency = 0.08
		f.ClipsDescendants = true
		f.Parent = pai
		arredondar(f, UDim.new(0, px(12)))
		local borda = Instance.new("UIStroke")
		borda.Thickness = 1.6
		borda.Color = Color3.fromRGB(70, 76, 96)
		borda.Transparency = 0.15
		borda.Parent = f
		local escala = Instance.new("UIScale")
		escala.Parent = f

		local brilho = Instance.new("UIGradient")
		brilho.Rotation = 90
		brilho.Transparency = NumberSequence.new(0, 0.25)
		brilho.Parent = f

		-- ⚠️ v118 — PEDIDO: "coloca as imagens do roll nas habilidades respectivas".
		-- A arte da carta (def.Image) ocupa o slot inteiro; sem arte, ficam as iniciais.
		local arte = Instance.new("ImageLabel")
		arte.Name = "Arte"
		arte.BackgroundTransparency = 1
		arte.Size = UDim2.fromScale(1, 1)
		arte.ScaleType = Enum.ScaleType.Crop
		arte.Image = ""
		arte.Visible = false
		arte.ZIndex = 1
		arte.Parent = f
		local sombraNome = Instance.new("Frame") -- faixa escura atrás do nome, pra ler em cima da arte
		sombraNome.Name = "SombraNome"
		sombraNome.AnchorPoint = Vector2.new(0, 1)
		sombraNome.Position = UDim2.new(0, 0, 1, 0)
		sombraNome.Size = UDim2.new(1, 0, 0, px(22))
		sombraNome.BackgroundColor3 = Color3.new(0, 0, 0)
		sombraNome.BackgroundTransparency = 0.35
		sombraNome.BorderSizePixel = 0
		sombraNome.Visible = false
		sombraNome.ZIndex = 1
		sombraNome.Parent = f

		local glifo = Instance.new("TextLabel")
		glifo.Name = "Glifo"
		glifo.BackgroundTransparency = 1
		glifo.Size = UDim2.new(1, 0, 0, px(30))
		glifo.Position = UDim2.new(0, 0, 0, px(12))
		glifo.Font = Enum.Font.GothamBlack
		glifo.TextSize = px(22)
		glifo.TextColor3 = Color3.new(1, 1, 1)
		glifo.Text = ""
		glifo.ZIndex = 2
		glifo.Parent = f

		local nome = Instance.new("TextLabel")
		nome.Name = "Nome"
		nome.BackgroundTransparency = 1
		nome.AnchorPoint = Vector2.new(0.5, 1)
		nome.Position = UDim2.new(0.5, 0, 1, px(-3))
		nome.Size = UDim2.new(1, px(-6), 0, px(18))
		nome.Font = Enum.Font.GothamBold
		nome.TextSize = px(9)
		nome.TextWrapped = true
		nome.TextYAlignment = Enum.TextYAlignment.Bottom
		nome.TextColor3 = Color3.fromRGB(215, 220, 232)
		nome.Text = ""
		nome.ZIndex = 2
		nome.Parent = f

		-- recarga: véu escuro que desce do topo conforme o tempo passa
		local veu = Instance.new("Frame")
		veu.Name = "Recarga"
		veu.AnchorPoint = Vector2.new(0, 1)
		veu.Position = UDim2.new(0, 0, 1, 0)
		veu.Size = UDim2.new(1, 0, 0, 0)
		veu.BackgroundColor3 = Color3.new(0, 0, 0)
		veu.BackgroundTransparency = 0.28
		veu.BorderSizePixel = 0
		veu.ZIndex = 3
		veu.Parent = f
		local escuro = Instance.new("Frame") -- o slot inteiro fica mais apagado durante a recarga
		escuro.Name = "Escuro"
		escuro.Size = UDim2.fromScale(1, 1)
		escuro.BackgroundColor3 = Color3.new(0, 0, 0)
		escuro.BackgroundTransparency = 1
		escuro.BorderSizePixel = 0
		escuro.ZIndex = 3
		escuro.Parent = f
		local conta = Instance.new("TextLabel")
		conta.Name = "Contagem"
		conta.BackgroundTransparency = 1
		conta.Size = UDim2.fromScale(1, 1)
		conta.Font = Enum.Font.GothamBlack
		conta.TextSize = px(22)
		conta.TextColor3 = Color3.new(1, 1, 1)
		conta.TextStrokeTransparency = 0.4
		conta.Text = ""
		conta.ZIndex = 5
		conta.Parent = f

		local teclaLbl = Instance.new("TextLabel")
		teclaLbl.Name = "Tecla"
		teclaLbl.Position = UDim2.new(0, px(4), 0, px(4))
		teclaLbl.Size = UDim2.new(0, px(18), 0, px(16))
		teclaLbl.BackgroundColor3 = COR_TECLA
		teclaLbl.BackgroundTransparency = 0.05
		teclaLbl.Font = Enum.Font.GothamBlack
		teclaLbl.TextSize = px(10)
		teclaLbl.TextColor3 = Color3.new(1, 1, 1)
		teclaLbl.Text = tecla
		teclaLbl.ZIndex = 6
		teclaLbl.Parent = f
		arredondar(teclaLbl, UDim.new(0, px(5)))

		-- barrinha de preenchimento (Flow) no rodapé
		local trilho = Instance.new("Frame")
		trilho.Name = "Preenche"
		trilho.AnchorPoint = Vector2.new(0, 1)
		trilho.Position = UDim2.new(0, 0, 1, 0)
		trilho.Size = UDim2.new(0, 0, 0, px(4))
		trilho.BorderSizePixel = 0
		trilho.Visible = false
		trilho.ZIndex = 4
		trilho.Parent = f

		local s = {
			Id = id, Frame = f, Borda = borda, Escala = escala, Glifo = glifo, Nome = nome, Veu = veu, Escuro = escuro, Arte = arte, SombraNome = sombraNome,
			Conta = conta, Tecla = teclaLbl, Preenche = trilho, Fim = 0, Total = 0, Cor = Color3.new(1, 1, 1), Vazio = true,
		}
		slots[id] = s
		return s
	end

	local function configurar(s, nomeTxt, glifoTxt, cor, vazio, imagem)
		local temArte = typeof(imagem) == "string" and imagem ~= ""
		s.Arte.Image = temArte and imagem or ""
		s.Arte.Visible = temArte
		s.SombraNome.Visible = temArte
		if temArte then glifoTxt = "" end
		s.Vazio = vazio
		s.Cor = cor
		s.Nome.Text = nomeTxt or ""
		s.Glifo.Text = glifoTxt or ""
		s.Glifo.TextColor3 = cor
		s.Borda.Color = vazio and Color3.fromRGB(60, 64, 80) or cor
		s.Frame.BackgroundTransparency = vazio and 0.45 or 0.08
		s.Glifo.TextTransparency = vazio and 0.6 or 0
		s.Nome.TextTransparency = vazio and 0.5 or 0
	end

	local function piscarPronto(s)
		s.Borda.Color = Color3.new(1, 1, 1)
		s.Borda.Thickness = 3
		s.Escala.Scale = 1.12
		TweenService:Create(s.Escala, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(0.35, function()
			if s.Fim <= tick() then
				s.Borda.Color = s.Vazio and Color3.fromRGB(60, 64, 80) or s.Cor
				s.Borda.Thickness = 1.6
			end
		end)
	end

	local function recarga(id, segundos)
		local s = slots[id]
		if not s or not segundos or segundos <= 0.05 then return end
		s.Fim = tick() + segundos
		s.Total = segundos
		s.EmRecarga = true
	end

	local function ativo(id, cor)
		local s = slots[id]
		if not s then return end
		s.Borda.Color = cor or Color3.fromRGB(120, 255, 150)
		s.Borda.Thickness = 3
		s.Escala.Scale = 1.08
		TweenService:Create(s.Escala, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		task.delay(1.2, function()
			if s.Fim <= tick() then
				s.Borda.Color = s.Vazio and Color3.fromRGB(60, 64, 80) or s.Cor
				s.Borda.Thickness = 1.6
			end
		end)
	end

	local gH = grupo(1, "HISSATSU", 2)
	local gA = grupo(2, "ARMA", 2)
	local gB = grupo(3, "BÁSICO", 2)
	local gF = grupo(4, "FLOW", 1)
	criarSlot(gH, "H1", "1", 1)
	criarSlot(gH, "H2", "2", 2)
	criarSlot(gA, "A1", "E", 1)
	criarSlot(gA, "A2", "R", 2)
	criarSlot(gB, "Q", "Q", 1)
	criarSlot(gB, "F", "F", 2)
	local flow = criarSlot(gF, "Flow", "V", 1)
	flow.Preenche.Visible = true

	-- energia da Hissatsu: fio fino em cima dos dois slots
	local energia = Instance.new("Frame")
	energia.Name = "Energia"
	energia.AnchorPoint = Vector2.new(0, 1)
	energia.Position = UDim2.new(0, 0, 1, -TAM - px(4))
	energia.Size = UDim2.new(1, 0, 0, px(4))
	energia.BackgroundColor3 = Color3.fromRGB(30, 33, 44)
	energia.BorderSizePixel = 0
	energia.Parent = gH:FindFirstChild("Fora")
	arredondar(energia)
	local energiaFill = Instance.new("Frame")
	energiaFill.Size = UDim2.new(1, 0, 1, 0)
	energiaFill.BackgroundColor3 = Color3.fromRGB(90, 200, 255)
	energiaFill.BorderSizePixel = 0
	energiaFill.Parent = energia
	arredondar(energiaFill)
	local energiaTxt = gH.Fora.Titulo
	energiaTxt.Position = UDim2.new(0, px(2), 1, -TAM - px(10))

	-- ----- conteúdo dos slots -----
	local function atualizarConteudo()
		local isGK = player:GetAttribute("Role") == "GK"
		for i = 1, 2 do
			local def = findPulse(equipped["Pulse" .. i])
			local s = slots["H" .. i]
			if def then
				local cor = RARITY_COLOR[def.Rarity] or Color3.new(1, 1, 1)
				configurar(s, def.Name, iniciais(def.Name), cor, false, def.Image)
				s.Def = def
			else
				configurar(s, "vazio", "—", Color3.fromRGB(120, 125, 140), true)
				s.Def = nil
			end
		end
		for i, campo in ipairs({ "Instinct1", "Instinct2" }) do
			local def = findInstinct(equipped[campo])
			local s = slots["A" .. i]
			s.Def = def
			if def then
				local cor = def.Cor or RARITY_COLOR[def.Rarity] or Color3.new(1, 1, 1)
				configurar(s, def.Name, iniciais(def.Name), cor, false, def.Image)
				s.Tecla.Text = def.Tecla and (i == 1 and "E" or "R") or "P"
				s.Tecla.BackgroundColor3 = def.Tecla and COR_TECLA or Color3.fromRGB(50, 44, 70)
			else
				configurar(s, "vazio", "—", Color3.fromRGB(120, 125, 140), true)
				s.Tecla.Text = i == 1 and "E" or "R"
			end
		end
		configurar(slots.Q, isGK and "Mergulho" or "Drible / Carrinho", isGK and "⤢" or "⇄", Color3.fromRGB(200, 210, 230), false)
		configurar(slots.F, isGK and "Avanço" or "Dash", "»", Color3.fromRGB(200, 210, 230), false)
		local rotulo, corFlow = nomeDoFlow()
		configurar(flow, (rotulo:gsub("^FLOW · ", "")), "", corFlow or Color3.fromRGB(90, 175, 255), false)
		flow.Preenche.BackgroundColor3 = corFlow or Color3.fromRGB(90, 175, 255)
	end

	-- o refreshAbilitiesPanel antigo continua rodando; a barra se atualiza junto
	local antigoRefresh = refreshAbilitiesPanel
	refreshAbilitiesPanel = function(...)
		antigoRefresh(...)
		atualizarConteudo()
	end
	player:GetAttributeChangedSignal("Role"):Connect(atualizarConteudo)
	player:GetAttributeChangedSignal("Cosm_Flow"):Connect(atualizarConteudo)
	task.defer(atualizarConteudo)

	-- ----- eventos -----
	Remotes.PulseFeedback.OnClientEvent:Connect(function(kind, extra)
		if kind == "CooldownsZerados" then
			slots.H1.Fim, slots.H2.Fim = 0, 0
			return
		end
		if kind ~= "Used" and kind ~= "Activated" and kind ~= "Consumed" then return end
		if player:GetAttribute("DebugSemCooldown") then return end
		local def = findPulse(extra)
		if not def or not def.Cooldown then return end
		local id = (extra == equipped.Pulse2) and "H2" or "H1"
		ativo(id, Color3.fromRGB(255, 210, 90))
		recarga(id, def.Cooldown)
	end)

	Remotes.PulseEnergyFeedback.OnClientEvent:Connect(function(current, max)
		current = tonumber(current) or 0
		max = math.max(tonumber(max) or 1, 1)
		local f = math.clamp(current / max, 0, 1)
		TweenService:Create(energiaFill, TweenInfo.new(0.2), { Size = UDim2.new(f, 0, 1, 0) }):Play()
		energiaFill.BackgroundColor3 = f < 0.3 and Color3.fromRGB(255, 100, 90) or Color3.fromRGB(90, 200, 255)
		if energiaTxt then energiaTxt.Text = string.format("HISSATSU · %d/%d", current, max) end
	end)

	local function slotDaArma(nome)
		if nome == equipped.Instinct1 then return "A1" end
		if nome == equipped.Instinct2 then return "A2" end
		return nil
	end
	Remotes.InstinctFeedback.OnClientEvent:Connect(function(active, name)
		local id = slotDaArma(name)
		if id and active then ativo(id) end
	end)
	-- recarga real das Armas: o servidor grava "ArmaCD_<nome>" (hora do servidor em que volta)
	player.AttributeChanged:Connect(function(attr)
		local nome = attr:match("^ArmaCD_(.+)$")
		if not nome then return end
		local id = slotDaArma(nome)
		if not id then return end
		local fim = player:GetAttribute(attr)
		if typeof(fim) ~= "number" then
			slots[id].Fim = 0
			return
		end
		local restante = fim - workspace:GetServerTimeNow()
		local s = slots[id]
		recarga(id, restante)
		s.Total = player:GetAttribute("ArmaCDTotal_" .. nome) or restante
	end)
	Remotes.GambleTimerFeedback.OnClientEvent:Connect(function(seg)
		local id = slotDaArma("Apostador")
		if id and typeof(seg) == "number" then slots[id].Sorte = tick() + seg end
	end)

	local temBola = false
	Remotes.PossessionChanged.OnClientEvent:Connect(function(dono, tem)
		if dono == player then temBola = tem elseif tem then temBola = false end
	end)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or player:GetAttribute("PulseComboActive") then return end
		local isGK = player:GetAttribute("Role") == "GK"
		if input.KeyCode == Enum.KeyCode.Q and slots.Q.Fim <= tick() then
			recarga("Q", isGK and Config.GK_DIVE_COOLDOWN or (temBola and Config.DRIBBLE_MOVE_COOLDOWN or Config.TACKLE_COOLDOWN))
		elseif input.KeyCode == Enum.KeyCode.F and slots.F.Fim <= tick() then
			recarga("F", isGK and Config.GK_FORWARD_COOLDOWN or Config.DASH_COOLDOWN)
		end
	end)

	-- Flow
	local flowPercent, flowAtivo = 0, false
	Remotes.InstinctModeFeedback.OnClientEvent:Connect(function(kind, extra)
		if kind == "MeterUpdate" then
			flowPercent = tonumber(extra) or 0
		elseif kind == "ModeActivated" then
			flowAtivo = true
			ativo("Flow", Color3.fromRGB(120, 210, 255))
		elseif kind == "ModeEnded" then
			flowAtivo = false
			flowPercent = 0
		end
	end)

	-- ----- quadro a quadro -----
	RunService.RenderStepped:Connect(function()
		local agora = tick()
		for id, s in pairs(slots) do
			if id == "Flow" then continue end
			local resta = s.Fim - agora
			if resta > 0 and not s.Vazio then
				local frac = math.clamp(resta / math.max(s.Total, 0.01), 0, 1)
				s.Veu.Size = UDim2.new(1, 0, frac, 0)
				s.Escuro.BackgroundTransparency = 0.45
				s.Conta.Text = resta >= 10 and string.format("%d", math.ceil(resta)) or string.format("%.1f", resta)
				s.Glifo.TextTransparency = 0.55
				s.Arte.ImageTransparency = 0.5
			elseif s.EmRecarga then
				s.Arte.ImageTransparency = 0
				s.EmRecarga = false
				s.Veu.Size = UDim2.new(1, 0, 0, 0)
				s.Escuro.BackgroundTransparency = 1
				s.Conta.Text = ""
				s.Glifo.TextTransparency = s.Vazio and 0.6 or 0
				piscarPronto(s)
			elseif s.Sorte and s.Sorte > agora then
				s.Conta.Text = ""
				s.Nome.Text = string.format("sorte em %ds", math.ceil(s.Sorte - agora))
			end
		end
		-- Flow: preenchimento, PRONTO, ATIVO, USADO
		local usado = player:GetAttribute("FlowUsado") and not flowAtivo
		local f = flowAtivo and 1 or math.clamp(flowPercent / 100, 0, 1)
		flow.Preenche.Size = UDim2.new(f, 0, 0, px(4))
		flow.Veu.Size = UDim2.new(1, 0, usado and 1 or (1 - f) * 0.85, 0)
		flow.Escuro.BackgroundTransparency = usado and 0.4 or 1
		if flowAtivo then
			flow.Glifo.Text = "ATIVO"
			flow.Glifo.TextSize = px(13)
			flow.Borda.Color = Color3.fromRGB(120, 210, 255)
			flow.Borda.Thickness = 2 + math.sin(agora * 8)
		elseif usado then
			flow.Glifo.Text = "USADO"
			flow.Glifo.TextSize = px(12)
			flow.Borda.Thickness = 1.6
		elseif f >= 1 then
			flow.Glifo.Text = "PRONTO"
			flow.Glifo.TextSize = px(11)
			flow.Borda.Color = flow.Cor
			flow.Borda.Thickness = 2 + 1.2 * math.sin(agora * 5)
		else
			flow.Glifo.Text = string.format("%d%%", math.floor(f * 100))
			flow.Glifo.TextSize = px(18)
			flow.Borda.Thickness = 1.6
		end
	end)
end

print("✅ AbilityHUD carregado.")
