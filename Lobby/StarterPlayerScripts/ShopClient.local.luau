--[[
	ShopClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	v2 — 100% SCRIPTADO (Instance.new): não depende de GUI montada no Studio.

	⚠️ v110 — LOJA NOVA: FLOW + ARMÁRIO.
	PEDIDO: "você vai melhorar a loja, vai incluir as cutscenes [de Flow] na
	loja pra pessoa poder escolher o flow que ela quer utilizar e cada flow vai
	dar buff diferente. Inclua todos os cosméticos... Lembra de colocar a aba
	de seleção pra você escolher qual cosmético você quer. A moldura, você vai
	clicar nela, ele vai expandir uma tela, vai poder decidir. Alguma cor de
	outra, título, um título, outro título... cor no chat... pelo menos 15 de
	cada".

	Abas:
	  FLOW          — os 12 Flows do Blue Lock (cartão com o buff de cada um e
	                  VER CENA: toca a cena de ativação no seu personagem).
	  ARMÁRIO       — à esquerda a PRÉVIA ao vivo (placa de nome com moldura,
	                  título, tag e cor + a linha do chat); à direita as 9
	                  categorias. Clicou numa, EXPANDE a tela com os 15 itens
	                  dela: passar o mouse mostra na prévia, o botão compra /
	                  equipa / desequipa. Emote e comemoração têm TESTAR (toca
	                  no seu boneco, só pra você ver).
	  CONVENIÊNCIA / BOOSTS / ROBUX — como antes.
	Os itens moram no módulo Cosmeticos (o mesmo do place Game).

	Paleta/estilo: skill ui-lobby (sem emoji; Gotham; cartões COR_CARTAO).

	Expõe: _G.OpenShop() / _G.CloseShop() / _G.ToggleShop()
	Remotes: ShopEvents.GetShopData / BuyUnlockSlot / BuyResetSlot /
	BuyCatalogItem / EquipCosmetic; LobbyEvents.GetSlotsOverview;
	MarketplaceService:PromptProductPurchase (Robux).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local MarketplaceService = game:GetService("MarketplaceService")
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

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos"))
local FlowCena = require(ReplicatedStorage:WaitForChild("FlowCena")) -- ⚠️ v110: "VER CENA" dos Flows

local shopEvents = ReplicatedStorage:WaitForChild("ShopEvents", 10)
if not shopEvents then
	warn("ShopClient: ShopEvents não encontrado em ReplicatedStorage.")
	return
end

local GetShopData = shopEvents:WaitForChild("GetShopData", 10)
local BuyUnlockSlot = shopEvents:WaitForChild("BuyUnlockSlot", 10)
local BuyResetSlot = shopEvents:WaitForChild("BuyResetSlot", 10)
local BuyCatalogItem = shopEvents:WaitForChild("BuyCatalogItem", 10)
local EquipCosmetic = shopEvents:WaitForChild("EquipCosmetic", 10)

local lobbyEvents = ReplicatedStorage:WaitForChild("LobbyEvents", 10)
local GetSlotsOverview = lobbyEvents and lobbyEvents:WaitForChild("GetSlotsOverview", 10)

if not (GetShopData and BuyUnlockSlot and BuyResetSlot and BuyCatalogItem and EquipCosmetic) then
	warn("ShopClient: remotes de loja não encontrados (ShopEvents incompleto).")
	return
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = "Loja", Text = text, Duration = 4 })
	end)
end

-- ===== PALETA (skill ui-lobby) =====
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_CARTAO_OK   = Color3.fromRGB(20, 34, 26)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_LEGENDA     = Color3.fromRGB(125, 185, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_OURO        = Color3.fromRGB(255, 200, 70)
local COR_PERIGO      = Color3.fromRGB(224, 76, 76)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local RARIDADE = {
	Common = { Nome = "COMUM", Cor = Color3.fromRGB(180, 180, 180) },
	Rare = { Nome = "RARO", Cor = Color3.fromRGB(80, 160, 255) },
	Epic = { Nome = "ÉPICO", Cor = Color3.fromRGB(170, 90, 255) },
	Legendary = { Nome = "LENDÁRIO", Cor = Color3.fromRGB(255, 175, 60) },
	Mythic = { Nome = "MÍTICO", Cor = Color3.fromRGB(255, 70, 110) },
}

local W, H = 900, 580

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
	s.Transparency = transparencia or 0.2
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = inst
	return s
end

local function texto(pai, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBold
	l.TextColor3 = COR_TEXTO
	l.TextSize = 13
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do l[k] = v end
	l.Parent = pai
	return l
end

local function hoverBrighten(botao, corBase)
	botao.MouseEnter:Connect(function()
		botao.BackgroundColor3 = corBase:Lerp(Color3.new(1, 1, 1), 0.12)
	end)
	botao.MouseLeave:Connect(function()
		botao.BackgroundColor3 = corBase
	end)
end

local function botao(pai, props)
	local b = Instance.new("TextButton")
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 13
	b.TextColor3 = Color3.new(1, 1, 1)
	for k, v in pairs(props) do b[k] = v end
	b.Parent = pai
	cantos(b, 8)
	return b
end

local function dinheiro(n)
	local s = tostring(math.floor(n))
	local r = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if r:sub(1, 1) == "." then r = r:sub(2) end
	return "$" .. r
end

-- ==========================================================
-- Construção do GUI
-- ==========================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopGUI_Provisorio"
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
backdrop.ZIndex = 1
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Size = UDim2.fromOffset(W, H)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.BackgroundColor3 = COR_PAINEL
panel.BorderSizePixel = 0
panel.ZIndex = 2
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
	escala.Scale = math.min(1.25, (v.X - 32) / W, (v.Y - 32) / H)
end

-- cabeçalho
local cabecalho = Instance.new("Frame")
cabecalho.Size = UDim2.new(1, 0, 0, 56)
cabecalho.BackgroundColor3 = COR_CARTAO
cabecalho.BorderSizePixel = 0
cabecalho.Parent = panel
cantos(cabecalho, 10)
local faixaTitulo = Instance.new("Frame")
faixaTitulo.Size = UDim2.fromOffset(4, 22)
faixaTitulo.Position = UDim2.new(0, 18, 0.5, -11)
faixaTitulo.BackgroundColor3 = COR_ACENTO
faixaTitulo.BorderSizePixel = 0
faixaTitulo.Parent = cabecalho
cantos(faixaTitulo, 2)
texto(cabecalho, { Text = "LOJA", Font = Enum.Font.GothamBlack, TextSize = 22, Size = UDim2.new(0, 200, 1, 0), Position = UDim2.new(0, 32, 0, 0) })

local closeButton = botao(cabecalho, {
	AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -12, 0.5, 0),
	BackgroundColor3 = COR_CARTAO_ALT, Text = "X", TextColor3 = COR_TEXTO, TextSize = 15,
})
cantos(closeButton, 17)

local moneyLabel = texto(cabecalho, {
	AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(200, 30), Position = UDim2.new(1, -58, 0.5, 0),
	Text = "$ --", TextColor3 = COR_OURO, Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Right,
})

-- abas
local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -32, 0, 34)
tabRow.Position = UDim2.new(0, 16, 0, 66)
tabRow.BackgroundTransparency = 1
tabRow.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

-- conteúdo
local conteudo = Instance.new("Frame")
conteudo.Size = UDim2.new(1, -32, 1, -126)
conteudo.Position = UDim2.new(0, 16, 0, 110)
conteudo.BackgroundTransparency = 1
conteudo.Parent = panel

local function novaRolagem(nome)
	local s = Instance.new("ScrollingFrame")
	s.Name = nome
	s.Size = UDim2.fromScale(1, 1)
	s.BackgroundTransparency = 1
	s.BorderSizePixel = 0
	s.ScrollBarThickness = 5
	s.ScrollBarImageColor3 = COR_TEXTO_FRACO
	s.CanvasSize = UDim2.new()
	s.AutomaticCanvasSize = Enum.AutomaticSize.Y
	s.Visible = false
	s.Parent = conteudo
	return s
end

-- lista (Conveniência/Boosts/Robux)
local contentFrame = novaRolagem("Lista")
local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 8)
contentLayout.Parent = contentFrame

-- Flow
local flowFrame = novaRolagem("Flow")
local flowLayout = Instance.new("UIGridLayout")
flowLayout.CellSize = UDim2.new(1 / 3, -8, 0, 200)
flowLayout.CellPadding = UDim2.fromOffset(10, 10)
flowLayout.SortOrder = Enum.SortOrder.LayoutOrder
flowLayout.Parent = flowFrame
local flowPad = Instance.new("UIPadding")
flowPad.PaddingRight = UDim.new(0, 8)
flowPad.Parent = flowFrame

-- Armário
local armario = Instance.new("Frame")
armario.Name = "Armario"
armario.Size = UDim2.fromScale(1, 1)
armario.BackgroundTransparency = 1
armario.Visible = false
armario.Parent = conteudo

-- ==========================================================
-- Estado
-- ==========================================================
local shopData = nil
local currentCategory = "Flow"
local tabButtons = {}
local isBusy = false
local possuidos = {}   -- [Id] = true
local equipados = {}   -- [Slot] = Id
local previaForcada = {} -- [Slot] = Id (passar o mouse num item mostra na prévia)
local categoriaAberta = nil -- slot aberto no Armário (nil = grade das categorias)
-- ⚠️ v117 — RODA DE EMOTES: ids por casa (false = vazia) e a casa escolhida pra receber o próximo emote
local roda = {}
local casaSelecionada = nil
local function casaDaRoda(id)
	for i = 1, (Cosmeticos.RODA_TAMANHO or 6) do
		if roda[i] == id then return i end
	end
	return nil
end

local refreshShopData -- declarada lá embaixo

local function setShopVisible(open)
	screenGui.Enabled = open
	if open then ajustarEscala() end
end

-- ==========================================================
-- AMOSTRA visual de um item (o "ícone" do cosmético, sem emoji)
-- ==========================================================
local gradientesGirando = {}
RunService.RenderStepped:Connect(function(dt)
	if not screenGui.Enabled then return end
	for g in pairs(gradientesGirando) do
		if g.Parent then
			g.Rotation = (g.Rotation + dt * 90) % 360
		else
			gradientesGirando[g] = nil
		end
	end
end)

local function arcoIris()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 110)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 130)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 180, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
	})
end

local function amostra(item, pai, tamanho)
	local slot = item.Slot
	local caixa = Instance.new("Frame")
	caixa.Name = "Amostra"
	caixa.AnchorPoint = Vector2.new(0.5, 0.5)
	caixa.Size = tamanho
	caixa.BackgroundTransparency = 1
	caixa.Parent = pai
	if slot == "Frame" then
		local q = Instance.new("Frame")
		q.AnchorPoint = Vector2.new(0.5, 0.5)
		q.Position = UDim2.fromScale(0.5, 0.5)
		q.Size = UDim2.new(0.8, 0, 0.62, 0)
		q.BackgroundColor3 = Color3.fromRGB(16, 20, 30)
		q.Parent = caixa
		cantos(q, 8)
		local s = contorno(q, Color3.new(1, 1, 1), item.Espessura + 1, 0)
		local g = Instance.new("UIGradient")
		g.Color = item.ArcoIris and arcoIris() or ColorSequence.new(item.Cor1, item.Cor2)
		g.Rotation = 45
		g.Parent = s
		if item.Gira then gradientesGirando[g] = true end
	elseif slot == "Title" then
		texto(caixa, { Size = UDim2.fromScale(1, 1), Text = item.Nome, TextColor3 = item.Cor, TextScaled = true, Font = Enum.Font.GothamBlack,
			TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 })
	elseif slot == "Tag" then
		local chip = texto(caixa, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 0, 0, 22),
			AutomaticSize = Enum.AutomaticSize.X, Text = item.Nome, BackgroundTransparency = 0, BackgroundColor3 = item.Cor,
			TextColor3 = Color3.fromRGB(15, 15, 20), Font = Enum.Font.GothamBlack, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center })
		cantos(chip, 5)
		local p = Instance.new("UIPadding")
		p.PaddingLeft = UDim.new(0, 7)
		p.PaddingRight = UDim.new(0, 7)
		p.Parent = chip
	elseif slot == "NameColor" or slot == "ChatColor" then
		local l = texto(caixa, { Size = UDim2.fromScale(1, 1), Text = slot == "ChatColor" and "Nome: gol!" or "Nome", TextColor3 = item.Cor,
			Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 })
		if item.Cor2 or item.ArcoIris then
			l.TextColor3 = Color3.new(1, 1, 1)
			local g = Instance.new("UIGradient")
			g.Color = item.ArcoIris and arcoIris() or ColorSequence.new(item.Cor, item.Cor2)
			g.Parent = l
		end
	elseif slot == "Emote" or slot == "Celebration" then
		local circ = Instance.new("Frame")
		circ.AnchorPoint = Vector2.new(0.5, 0.5)
		circ.Position = UDim2.fromScale(0.5, 0.5)
		circ.Size = UDim2.fromOffset(44, 44)
		circ.BackgroundColor3 = COR_CARTAO_ALT
		circ.Parent = caixa
		cantos(circ, 22)
		contorno(circ, RARIDADE[item.Raridade].Cor, 2, 0.3)
		texto(circ, { Size = UDim2.fromScale(1, 1), Text = string.format("%.1fs", item.Duracao), TextColor3 = COR_LEGENDA,
			Font = Enum.Font.GothamBlack, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center })
	else -- Aura, GoalEffect, Flow
		local cor = item.Cor or (item.Tema and item.Tema.Cor) or COR_ACENTO
		for i = 3, 1, -1 do
			local c = Instance.new("Frame")
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Position = UDim2.fromScale(0.5, 0.5)
			c.Size = UDim2.fromOffset(16 + i * 12, 16 + i * 12)
			c.BackgroundColor3 = cor
			c.BackgroundTransparency = 0.35 + i * 0.18
			c.Parent = caixa
			cantos(c, 40)
		end
		if item.Estilo == "ArcoIris" then
			local g = Instance.new("UIGradient")
			g.Color = arcoIris()
			g.Parent = caixa:FindFirstChildOfClass("Frame")
		end
	end
	return caixa
end

-- ==========================================================
-- PRÉVIA (placa de nome + chat + o resto equipado)
-- ==========================================================
local colunaPrevia = Instance.new("Frame")
colunaPrevia.Size = UDim2.new(0, 270, 1, 0)
colunaPrevia.BackgroundColor3 = COR_CARTAO
colunaPrevia.BorderSizePixel = 0
colunaPrevia.Parent = armario
cantos(colunaPrevia, 10)
contorno(colunaPrevia, COR_BORDA, 1, 0.2)
texto(colunaPrevia, { Text = "PRÉVIA", Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = COR_LEGENDA, Size = UDim2.new(1, -24, 0, 20), Position = UDim2.new(0, 12, 0, 10) })

local palcoPlaca = Instance.new("Frame")
palcoPlaca.Size = UDim2.new(1, -24, 0, 96)
palcoPlaca.Position = UDim2.new(0, 12, 0, 36)
palcoPlaca.BackgroundColor3 = Color3.fromRGB(60, 110, 70) -- "gramado" atrás da placa
palcoPlaca.BorderSizePixel = 0
palcoPlaca.ClipsDescendants = true
palcoPlaca.Parent = colunaPrevia
cantos(palcoPlaca, 8)
local gradGrama = Instance.new("UIGradient")
gradGrama.Rotation = 90
gradGrama.Color = ColorSequence.new(Color3.fromRGB(110, 150, 190), Color3.fromRGB(50, 95, 60))
gradGrama.Parent = palcoPlaca

local linhaChat = texto(colunaPrevia, { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 0, 140), RichText = true, TextWrapped = true,
	Font = Enum.Font.GothamBold, TextSize = 14, BackgroundTransparency = 0, BackgroundColor3 = COR_CARTAO_ALT })
cantos(linhaChat, 6)
local padChat = Instance.new("UIPadding")
padChat.PaddingLeft = UDim.new(0, 8)
padChat.Parent = linhaChat

local listaEquip = Instance.new("Frame")
listaEquip.Size = UDim2.new(1, -24, 1, -236)
listaEquip.Position = UDim2.new(0, 12, 0, 184)
listaEquip.BackgroundTransparency = 1
listaEquip.Parent = colunaPrevia
local listaEquipLayout = Instance.new("UIListLayout")
listaEquipLayout.Padding = UDim.new(0, 4)
listaEquipLayout.SortOrder = Enum.SortOrder.LayoutOrder
listaEquipLayout.Parent = listaEquip

texto(colunaPrevia, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.new(1, -24, 0, 40), TextWrapped = true,
	Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = COR_TEXTO_MEDIO, TextYAlignment = Enum.TextYAlignment.Bottom,
	Text = "Emotes: tecla G abre a roda de 6 casas (Lobby e partida) — monte a sua no Armário > Emotes. A casa 1 é a comemoração do gol." })

local function hex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

local function itemNaPrevia(slot)
	local id = previaForcada[slot]
	if id == nil then id = equipados[slot] end
	if id == false then return nil end
	return Cosmeticos.Item(id)
end

local function atualizarPrevia()
	for _, c in ipairs(palcoPlaca:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local nome = (shopData and shopData.SlotName) or player.DisplayName
	local placa = Cosmeticos.MontarPlaca({
		Nome = nome, Titulo = itemNaPrevia("Title"), Tag = itemNaPrevia("Tag"),
		CorNome = itemNaPrevia("NameColor"), Moldura = itemNaPrevia("Frame"),
	})
	local caixa = Instance.new("Frame")
	caixa.AnchorPoint = Vector2.new(0.5, 0.5)
	caixa.Position = UDim2.fromScale(0.5, 0.55)
	caixa.Size = placa.Size
	caixa.BackgroundTransparency = 1
	caixa.Parent = palcoPlaca
	for _, filho in ipairs(placa:GetChildren()) do filho.Parent = caixa end
	placa:Destroy()
	for _, d in ipairs(caixa:GetDescendants()) do
		if d:IsA("UIGradient") and d:GetAttribute("Gira") then gradientesGirando[d] = true end
	end

	-- ⚠️ v119: "Cor no Chat" saiu dos cosméticos — o nome no chat usa a cor padrão
	local tag = itemNaPrevia("Tag")
	local prefixo = string.format('<font color="#%s">%s:</font>', hex(COR_TEXTO), nome)
	if tag then prefixo = string.format('<font color="#%s">[%s]</font> ', hex(tag.Cor), tag.Nome) .. prefixo end
	linhaChat.Text = prefixo .. ' <font color="#EEF1F8">que golaço!</font>'

	for _, c in ipairs(listaEquip:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for i, slot in ipairs({ "Emote", "GoalEffect", "Flow" }) do -- ⚠️ v119: sem Aura
		local it = itemNaPrevia(slot)
		local l = texto(listaEquip, { Size = UDim2.new(1, 0, 0, 18), RichText = true, LayoutOrder = i, Font = Enum.Font.GothamMedium, TextSize = 13,
			TextColor3 = COR_TEXTO_MEDIO })
		if slot == "Emote" then
			-- a roda: quantas casas estão preenchidas (a casa 1 toca no gol)
			local n = 0
			for c = 1, (Cosmeticos.RODA_TAMANHO or 6) do
				if roda[c] then n += 1 end
			end
			local casa1 = Cosmeticos.Item(roda[1] or nil)
			l.Text = string.format('<font color="#7DB9FF">%s</font>  %d/%d na roda%s', maiusculas(Cosmeticos.NOME_CATEGORIA[slot]), n,
				Cosmeticos.RODA_TAMANHO or 6, casa1 and ('  ·  gol: ' .. casa1.Nome) or "")
		else
			l.Text = string.format('<font color="#7DB9FF">%s</font>  %s', maiusculas(Cosmeticos.NOME_CATEGORIA[slot]),
				it and it.Nome or '<font color="#788094">nenhum</font>')
		end
	end
end

-- ==========================================================
-- ARMÁRIO: grade das categorias + tela expandida de cada uma
-- ==========================================================
local areaDireita = Instance.new("Frame")
areaDireita.Size = UDim2.new(1, -282, 1, 0)
areaDireita.Position = UDim2.new(0, 282, 0, 0)
areaDireita.BackgroundTransparency = 1
areaDireita.Parent = armario

local gradeCategorias = Instance.new("Frame")
gradeCategorias.Size = UDim2.fromScale(1, 1)
gradeCategorias.BackgroundTransparency = 1
gradeCategorias.Parent = areaDireita
local gradeLayout = Instance.new("UIGridLayout")
gradeLayout.CellSize = UDim2.new(1 / 3, -7, 1 / 3, -7)
gradeLayout.CellPadding = UDim2.fromOffset(10, 10)
gradeLayout.SortOrder = Enum.SortOrder.LayoutOrder
gradeLayout.Parent = gradeCategorias

local telaItens = Instance.new("Frame")
telaItens.Size = UDim2.fromScale(1, 1)
telaItens.BackgroundColor3 = COR_PAINEL
telaItens.BorderSizePixel = 0
telaItens.Visible = false
telaItens.ZIndex = 2
telaItens.Parent = areaDireita

local voltarBtn = botao(telaItens, { Size = UDim2.fromOffset(110, 32), Position = UDim2.fromOffset(0, 0), BackgroundColor3 = COR_CARTAO_ALT,
	Text = "‹  VOLTAR", TextColor3 = COR_LEGENDA, TextSize = 13 })
contorno(voltarBtn, COR_ACENTO, 1, 0.5)
hoverBrighten(voltarBtn, COR_CARTAO_ALT)
local tituloTela = texto(telaItens, { Size = UDim2.new(1, -250, 0, 32), Position = UDim2.fromOffset(124, 0), Font = Enum.Font.GothamBlack, TextSize = 18 })
local contagemTela = texto(telaItens, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(120, 32), Position = UDim2.new(1, -4, 0, 0),
	Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = COR_TEXTO_MEDIO, TextXAlignment = Enum.TextXAlignment.Right })

local rolagemItens = Instance.new("ScrollingFrame")
rolagemItens.Size = UDim2.new(1, 0, 1, -42)
rolagemItens.Position = UDim2.fromOffset(0, 42)
rolagemItens.BackgroundTransparency = 1
rolagemItens.BorderSizePixel = 0
rolagemItens.ScrollBarThickness = 5
rolagemItens.ScrollBarImageColor3 = COR_TEXTO_FRACO
rolagemItens.AutomaticCanvasSize = Enum.AutomaticSize.Y
rolagemItens.CanvasSize = UDim2.new()
rolagemItens.Parent = telaItens
local itensLayout = Instance.new("UIGridLayout")
itensLayout.CellSize = UDim2.new(0.25, -8, 0, 150)
itensLayout.CellPadding = UDim2.fromOffset(8, 8)
itensLayout.SortOrder = Enum.SortOrder.LayoutOrder
itensLayout.Parent = rolagemItens
local itensPad = Instance.new("UIPadding")
itensPad.PaddingRight = UDim.new(0, 8)
itensPad.Parent = rolagemItens

-- ⚠️ v117 — faixa da RODA DE EMOTES (aparece só em Armário > Emotes): 6 casas; clicar numa
-- casa escolhe onde vai o próximo emote; o × tira o emote da casa.
local faixaRoda = Instance.new("Frame")
faixaRoda.Name = "FaixaRoda"
faixaRoda.Size = UDim2.new(1, -8, 0, 92)
faixaRoda.Position = UDim2.fromOffset(0, 42)
faixaRoda.BackgroundColor3 = COR_CARTAO
faixaRoda.BorderSizePixel = 0
faixaRoda.Visible = false
faixaRoda.Parent = telaItens
cantos(faixaRoda, 10)
contorno(faixaRoda, COR_BORDA, 1, 0.2)
texto(faixaRoda, { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(10, 6), Text = "SUA RODA DE EMOTES (tecla G) — clique numa casa e depois no emote que quer nela",
	Font = Enum.Font.GothamBlack, TextSize = 11, TextColor3 = COR_LEGENDA })
local casasRoda = {}
local renderCategory -- declarada aqui porque a faixa da roda precisa dela (definida mais abaixo)
local function montarCasasRoda()
	for _, c in ipairs(casasRoda) do c.Frame:Destroy() end
	casasRoda = {}
	local total = Cosmeticos.RODA_TAMANHO or 6
	for i = 1, total do
		local it = Cosmeticos.Item(roda[i] or nil)
		local selecionada = casaSelecionada == i
		local f = Instance.new("TextButton")
		f.Text = ""
		f.AutoButtonColor = false
		f.Size = UDim2.new(1 / total, -8, 0, 58)
		f.Position = UDim2.new((i - 1) / total, 6, 0, 28)
		f.BackgroundColor3 = selecionada and COR_CARTAO_ALT or COR_PAINEL
		f.BorderSizePixel = 0
		f.Parent = faixaRoda
		cantos(f, 8)
		contorno(f, selecionada and COR_ACENTO or (it and (RARIDADE[it.Raridade] or RARIDADE.Common).Cor or COR_BORDA), selecionada and 2 or 1, selecionada and 0 or 0.3)
		texto(f, { Size = UDim2.fromOffset(18, 16), Position = UDim2.fromOffset(6, 4), Text = tostring(i), Font = Enum.Font.GothamBlack, TextSize = 12,
			TextColor3 = selecionada and COR_ACENTO or COR_LEGENDA, TextXAlignment = Enum.TextXAlignment.Left })
		if i == 1 then
			texto(f, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(34, 14), Position = UDim2.new(1, -6, 0, 4), Text = "GOL", Font = Enum.Font.GothamBlack,
				TextSize = 10, TextColor3 = Color3.fromRGB(255, 200, 70), TextXAlignment = Enum.TextXAlignment.Right })
		end
		texto(f, { Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(6, 22), Text = it and it.Nome or "vazio", Font = Enum.Font.GothamBold,
			TextSize = 12, TextWrapped = true, TextColor3 = it and COR_TEXTO or COR_TEXTO_FRACO, TextYAlignment = Enum.TextYAlignment.Top })
		f.Activated:Connect(function()
			casaSelecionada = (casaSelecionada == i) and nil or i
			renderCategory()
		end)
		if it then
			local x = botao(f, { AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(18, 18), Position = UDim2.new(1, -4, 1, -4), BackgroundColor3 = COR_CARTAO_ALT,
				Text = "×", TextColor3 = COR_TEXTO_MEDIO, TextSize = 14 })
			cantos(x, 9)
			x.Activated:Connect(function()
				if isBusy then return end
				isBusy = true
				pcall(function() return EquipCosmetic:InvokeServer(it.Id, i) end)
				isBusy = false
				refreshShopData()
			end)
		end
		table.insert(casasRoda, { Frame = f })
	end
end

-- ⚠️ v119: Aura e Cor no Chat removidas ("mantenha só a cor do nome, a tag, a moldura, o título, os emotes" + efeito de gol)
local SLOTS_ARMARIO = { "Frame", "Title", "Tag", "NameColor", "Emote", "GoalEffect" } -- ⚠️ v117: Comemoração virou Emote

local function contarPossuidos(slot)
	local n = 0
	for _, it in ipairs(Cosmeticos[slot]) do
		if possuidos[it.Id] then n += 1 end
	end
	return n
end

local function comprarOuEquipar(item)
	if isBusy then return end
	isBusy = true
	local ok, success, result
	if possuidos[item.Id] then
		ok, success, result = pcall(function() return EquipCosmetic:InvokeServer(item.Id, item.Slot == "Emote" and casaSelecionada or nil) end)
		if ok and success and item.Slot == "Emote" then casaSelecionada = nil end
	else
		ok, success, result = pcall(function() return BuyCatalogItem:InvokeServer(item.Id) end)
		if ok and success then notify("Comprado: " .. item.Nome) end
	end
	isBusy = false
	if ok and success then
		refreshShopData()
	else
		notify(tostring(result or success))
	end
end


local function montarTile(item, ordem)
	local rar = RARIDADE[item.Raridade] or RARIDADE.Common
	local casaNaRoda = item.Slot == "Emote" and casaDaRoda(item.Id) or nil
	local equipado = (item.Slot == "Emote") and (casaNaRoda ~= nil) or (equipados[item.Slot] == item.Id)
	local tem = possuidos[item.Id] == true
	local tile = Instance.new("TextButton")
	tile.Text = ""
	tile.AutoButtonColor = false
	tile.BackgroundColor3 = equipado and COR_CARTAO_OK or COR_CARTAO
	tile.BorderSizePixel = 0
	tile.LayoutOrder = ordem
	tile.Parent = rolagemItens
	cantos(tile, 8)
	contorno(tile, equipado and COR_OK or COR_BORDA, equipado and 2 or 1, equipado and 0.1 or 0.2)
	local faixa = Instance.new("Frame")
	faixa.Size = UDim2.new(1, -16, 0, 3)
	faixa.Position = UDim2.fromOffset(8, 0)
	faixa.BackgroundColor3 = rar.Cor
	faixa.BorderSizePixel = 0
	faixa.Parent = tile
	amostra(item, tile, UDim2.new(1, -16, 0, 50)).Position = UDim2.new(0.5, 0, 0, 34)
	texto(tile, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 64), Text = item.Nome, Font = Enum.Font.GothamBlack,
		TextSize = 13, TextTruncate = Enum.TextTruncate.AtEnd })
	texto(tile, { Size = UDim2.new(1, -16, 0, 14), Position = UDim2.fromOffset(8, 83), Text = rar.Nome, Font = Enum.Font.GothamBlack,
		TextSize = 11, TextColor3 = rar.Cor })

	local acao = botao(tile, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0.5, 0, 1, -8), TextSize = 12 })
	local corAcao
	if equipado then
		local textoEquipado = casaNaRoda and ("NA RODA · CASA " .. casaNaRoda .. " ✓") or "EQUIPADO ✓"
		acao.Text = textoEquipado
		acao.TextSize = casaNaRoda and 11 or 12
		corAcao = COR_CARTAO_ALT
		acao.TextColor3 = COR_OK
		contorno(acao, COR_OK, 1, 0.4)
		acao.MouseEnter:Connect(function()
			if item.Slot == "Emote" then
				acao.Text = (casaSelecionada and casaSelecionada ~= casaNaRoda) and ("MOVER PRA CASA " .. casaSelecionada) or "TIRAR DA RODA"
			elseif item.Slot ~= "Flow" then
				acao.Text = "DESEQUIPAR"
			end
		end)
		acao.MouseLeave:Connect(function() acao.Text = textoEquipado end)
	elseif tem then
		acao.Text = item.Slot == "Emote" and (casaSelecionada and ("COLOCAR NA CASA " .. casaSelecionada) or "COLOCAR NA RODA") or "EQUIPAR"
		if item.Slot == "Emote" then acao.TextSize = 11 end
		corAcao = COR_ACENTO
	else
		acao.Text = dinheiro(Cosmeticos.Preco(item))
		corAcao = COR_OK
	end
	acao.BackgroundColor3 = corAcao
	hoverBrighten(acao, corAcao)
	acao.MouseButton1Click:Connect(function() comprarOuEquipar(item) end)

	if item.Slot == "Emote" or item.Slot == "Celebration" then
		local testar = botao(tile, { AnchorPoint = Vector2.new(1, 0), Size = UDim2.fromOffset(62, 20), Position = UDim2.new(1, -6, 0, 8),
			BackgroundColor3 = COR_CARTAO_ALT, Text = "TESTAR", TextColor3 = COR_LEGENDA, TextSize = 10 })
		cantos(testar, 5)
		hoverBrighten(testar, COR_CARTAO_ALT)
		testar.MouseButton1Click:Connect(function()
			if _G.PreviewEmoteLobby then
				_G.CloseShop()
				_G.PreviewEmoteLobby(item.Id)
			end
		end)
	end

	tile.MouseEnter:Connect(function()
		tile.BackgroundColor3 = equipado and COR_CARTAO_OK or COR_CARTAO_ALT
		previaForcada[item.Slot] = item.Id
		atualizarPrevia()
	end)
	tile.MouseLeave:Connect(function()
		tile.BackgroundColor3 = equipado and COR_CARTAO_OK or COR_CARTAO
		if previaForcada[item.Slot] == item.Id then
			previaForcada[item.Slot] = nil
			atualizarPrevia()
		end
	end)
	-- no celular não tem "passar o mouse": tocar no cartão mostra na prévia
	tile.Activated:Connect(function()
		previaForcada[item.Slot] = item.Id
		atualizarPrevia()
	end)
end

local function abrirCategoria(slot)
	categoriaAberta = slot
	renderCategory()
end

voltarBtn.MouseButton1Click:Connect(function()
	categoriaAberta = nil
	previaForcada = {}
	renderCategory()
end)

local function renderArmario()
	armario.Visible = true
	atualizarPrevia()
	for _, c in ipairs(gradeCategorias:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for _, c in ipairs(rolagemItens:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	if categoriaAberta then
		gradeCategorias.Visible = false
		telaItens.Visible = true
		-- ⚠️ v117: em Emotes aparece a roda (6 casas) em cima da lista
		local comRoda = categoriaAberta == "Emote"
		faixaRoda.Visible = comRoda
		rolagemItens.Position = UDim2.fromOffset(0, comRoda and 142 or 42)
		rolagemItens.Size = UDim2.new(1, 0, 1, comRoda and -142 or -42)
		if comRoda then montarCasasRoda() end
		tituloTela.Text = maiusculas(Cosmeticos.NOME_CATEGORIA[categoriaAberta])
		contagemTela.Text = string.format("VOCÊ TEM %d/%d", contarPossuidos(categoriaAberta), #Cosmeticos[categoriaAberta])
		for i, item in ipairs(Cosmeticos[categoriaAberta]) do
			montarTile(item, i)
		end
		return
	end
	gradeCategorias.Visible = true
	telaItens.Visible = false
	faixaRoda.Visible = false
	for i, slot in ipairs(SLOTS_ARMARIO) do
		local item = Cosmeticos.Item(equipados[slot])
		local card = Instance.new("TextButton")
		card.Text = ""
		card.AutoButtonColor = false
		card.BackgroundColor3 = COR_CARTAO
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.Parent = gradeCategorias
		cantos(card, 10)
		local borda = contorno(card, COR_BORDA, 1, 0.2)
		texto(card, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 12), Text = maiusculas(Cosmeticos.NOME_CATEGORIA[slot]),
			Font = Enum.Font.GothamBlack, TextSize = 12, TextColor3 = COR_LEGENDA })
		texto(card, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0, 12, 1, -30),
			Text = item and item.Nome or "Nenhum", Font = Enum.Font.GothamBlack, TextSize = 15, TextColor3 = item and COR_TEXTO or COR_TEXTO_FRACO,
			TextTruncate = Enum.TextTruncate.AtEnd })
		texto(card, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.new(1, -40, 0, 16), Position = UDim2.new(0, 12, 1, -12),
			Text = string.format("você tem %d de %d", contarPossuidos(slot), #Cosmeticos[slot]), Font = Enum.Font.GothamMedium, TextSize = 12,
			TextColor3 = COR_TEXTO_MEDIO })
		texto(card, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(20, 30), Position = UDim2.new(1, -8, 0.5, 0), Text = "›",
			Font = Enum.Font.GothamBlack, TextSize = 26, TextColor3 = COR_LEGENDA, TextXAlignment = Enum.TextXAlignment.Center })
		if item then
			amostra(item, card, UDim2.new(1, -60, 0, 44)).Position = UDim2.new(0.5, -10, 0.47, 0)
		end
		card.MouseEnter:Connect(function()
			card.BackgroundColor3 = COR_CARTAO_ALT
			borda.Color = COR_ACENTO
		end)
		card.MouseLeave:Connect(function()
			card.BackgroundColor3 = COR_CARTAO
			borda.Color = COR_BORDA
		end)
		card.Activated:Connect(function() abrirCategoria(slot) end)
	end
end

-- ==========================================================
-- FLOW
-- ==========================================================
local NOME_ATRIBUTO = { Kick = "CHUTE", Technique = "TÉCNICA", DribbleSkill = "DRIBLE", Speed = "VELOCIDADE", Physical = "FÍSICO" }
local ORDEM_ATRIBUTO = { "Kick", "Technique", "DribbleSkill", "Speed", "Physical" }

local function chip(pai, txt, cor, ordem)
	local l = texto(pai, { AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.new(0, 0, 0, 20), Text = txt, Font = Enum.Font.GothamBlack, TextSize = 11,
		TextColor3 = cor, BackgroundTransparency = 0, BackgroundColor3 = COR_CARTAO_ALT, LayoutOrder = ordem or 1,
		TextXAlignment = Enum.TextXAlignment.Center })
	cantos(l, 6)
	contorno(l, cor, 1, 0.5)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 7)
	p.PaddingRight = UDim.new(0, 7)
	p.Parent = l
	return l
end

local function renderFlow()
	flowFrame.Visible = true
	for _, c in ipairs(flowFrame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	for i, item in ipairs(Cosmeticos.Flow) do
		local tema = item.Tema
		local rar = RARIDADE[item.Raridade] or RARIDADE.Common
		local equipado = equipados.Flow == item.Id
		local tem = possuidos[item.Id] == true
		local card = Instance.new("Frame")
		card.BackgroundColor3 = equipado and COR_CARTAO_OK or COR_CARTAO
		card.BorderSizePixel = 0
		card.LayoutOrder = i
		card.ClipsDescendants = true
		card.Parent = flowFrame
		cantos(card, 10)
		contorno(card, equipado and COR_OK or COR_BORDA, equipado and 2 or 1, equipado and 0.1 or 0.2)

		-- fundo na cor do Flow (bem discreto) + faixa em cima
		local brilho = Instance.new("Frame")
		brilho.Size = UDim2.fromScale(1, 1)
		brilho.BackgroundColor3 = tema.Cor
		brilho.BackgroundTransparency = 0.85
		brilho.BorderSizePixel = 0
		brilho.Parent = card
		local gb = Instance.new("UIGradient")
		gb.Rotation = 90
		gb.Transparency = NumberSequence.new(0, 1)
		gb.Parent = brilho
		local faixa = Instance.new("Frame")
		faixa.Size = UDim2.new(1, 0, 0, 5)
		faixa.BackgroundColor3 = Color3.new(1, 1, 1)
		faixa.BorderSizePixel = 0
		faixa.Parent = card
		local gf = Instance.new("UIGradient")
		gf.Color = ColorSequence.new(tema.Cor, tema.Cor2)
		gf.Parent = faixa

		texto(card, { Size = UDim2.new(1, -110, 0, 22), Position = UDim2.fromOffset(12, 14), Text = maiusculas(item.Personagem),
			Font = Enum.Font.GothamBlack, TextSize = 16, TextTruncate = Enum.TextTruncate.AtEnd })
		texto(card, { Size = UDim2.new(1, -24, 0, 16), Position = UDim2.fromOffset(12, 36), Text = item.Nome, Font = Enum.Font.GothamBlack,
			TextSize = 12, TextColor3 = tema.Cor:Lerp(Color3.new(1, 1, 1), 0.25) })
		local rc = chip(card, rar.Nome, rar.Cor)
		rc.AnchorPoint = Vector2.new(1, 0)
		rc.Position = UDim2.new(1, -10, 0, 14)
		texto(card, { Size = UDim2.new(1, -24, 0, 32), Position = UDim2.fromOffset(12, 56), Text = item.Descricao, Font = Enum.Font.GothamMedium,
			TextSize = 13, TextColor3 = COR_TEXTO_MEDIO, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })

		local buffs = Instance.new("Frame")
		buffs.Size = UDim2.new(1, -24, 0, 44)
		buffs.Position = UDim2.fromOffset(12, 94)
		buffs.BackgroundTransparency = 1
		buffs.Parent = card
		local bl = Instance.new("UIListLayout")
		bl.FillDirection = Enum.FillDirection.Horizontal
		bl.Padding = UDim.new(0, 5)
		bl.SortOrder = Enum.SortOrder.LayoutOrder
		pcall(function() bl.Wraps = true end) -- muitos buffs (Reo) quebram em 2 linhas
		bl.Parent = buffs
		local n = 0
		for _, attr in ipairs(ORDEM_ATRIBUTO) do
			local v = item.Atributos and item.Atributos[attr]
			if v then
				n += 1
				chip(buffs, string.format("%s +%d", NOME_ATRIBUTO[attr], v), COR_OK, n)
			end
		end
		if item.Velocidade then
			chip(buffs, string.format("CORRIDA +%d%%", math.floor((item.Velocidade - 1) * 100 + 0.5)), COR_OURO, n + 1)
		end

		local verCena = botao(card, { AnchorPoint = Vector2.new(0, 1), Size = UDim2.fromOffset(96, 32), Position = UDim2.new(0, 12, 1, -10),
			BackgroundColor3 = COR_CARTAO_ALT, Text = "VER CENA", TextColor3 = COR_LEGENDA, TextSize = 12 })
		contorno(verCena, COR_ACENTO, 1, 0.5)
		hoverBrighten(verCena, COR_CARTAO_ALT)
		verCena.MouseButton1Click:Connect(function()
			_G.CloseShop()
			FlowCena.Tocar(player, item)
			-- volta pra Loja no fim da cena
			task.delay(2, function() _G.OpenShopTab("Flow") end)
		end)
		local acao = botao(card, { AnchorPoint = Vector2.new(1, 1), Size = UDim2.new(1, -128, 0, 32), Position = UDim2.new(1, -12, 1, -10) })
		local corAcao
		if equipado then
			acao.Text = "ESCOLHIDO ✓"
			corAcao = COR_CARTAO_ALT
			acao.TextColor3 = COR_OK
			contorno(acao, COR_OK, 1, 0.4)
		elseif tem then
			acao.Text = "ESCOLHER"
			corAcao = COR_ACENTO
		else
			acao.Text = dinheiro(Cosmeticos.Preco(item))
			corAcao = COR_OK
		end
		acao.BackgroundColor3 = corAcao
		hoverBrighten(acao, corAcao)
		acao.MouseButton1Click:Connect(function()
			if equipado then return end
			comprarOuEquipar(item)
		end)
	end
end

-- ==========================================================
-- Cartões em lista (Conveniência / Boosts / Robux)
-- ==========================================================
local function makeActionButton(row)
	return botao(row, { AnchorPoint = Vector2.new(1, 0.5), Size = UDim2.fromOffset(130, 36), Position = UDim2.new(1, -12, 0.5, 0) })
end

local function cartaoLinha(order, nome, sub, corSub)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -8, 0, 60)
	row.BackgroundColor3 = COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = contentFrame
	cantos(row, 8)
	contorno(row, COR_BORDA, 1, 0.2)
	texto(row, { Size = UDim2.new(1, -160, 0, 22), Position = UDim2.fromOffset(14, 9), Text = nome, Font = Enum.Font.GothamBlack, TextSize = 15 })
	texto(row, { Size = UDim2.new(1, -160, 0, 16), Position = UDim2.fromOffset(14, 33), Text = sub, Font = Enum.Font.GothamMedium, TextSize = 12,
		TextColor3 = corSub or COR_TEXTO_MEDIO })
	return row
end

local function buildCatalogCard(item, order)
	local sub = item.Type == "Boost" and "boost temporário" or "consumível"
	local row = cartaoLinha(order, item.Name, sub)
	local actionButton = makeActionButton(row)
	actionButton.Text = dinheiro(item.Cost)
	actionButton.BackgroundColor3 = COR_OK
	hoverBrighten(actionButton, COR_OK)
	actionButton.MouseButton1Click:Connect(function()
		if isBusy then return end
		isBusy = true
		actionButton.Text = "..."
		local ok, success, result = pcall(function() return BuyCatalogItem:InvokeServer(item.Id) end)
		isBusy = false
		if ok and success then
			if typeof(result) == "table" and result.Element then
				notify(string.format("Elemento sorteado: %s!", result.Element))
			else
				notify("Comprado: " .. item.Name)
			end
			refreshShopData()
		else
			actionButton.Text = dinheiro(item.Cost)
			notify(tostring(result or success))
		end
	end)
	return row
end

-- seletor de slot pra reiniciar
local pickerGui, pickerList

local function buildResetPicker()
	pickerGui = Instance.new("ScreenGui")
	pickerGui.Name = "ResetSlotPicker"
	pickerGui.ResetOnSpawn = false
	pickerGui.DisplayOrder = 50
	pickerGui.Enabled = false
	pickerGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(340, 380)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = COR_PAINEL
	frame.Parent = pickerGui
	cantos(frame, 10)
	contorno(frame, COR_OURO, 1, 0.2)

	texto(frame, { Size = UDim2.new(1, -20, 0, 34), Position = UDim2.new(0, 14, 0, 10), Text = "ESCOLHA QUEM REINICIAR", Font = Enum.Font.GothamBlack, TextSize = 15 })

	local pickerCloseButton = botao(frame, { Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, -38, 0, 10), BackgroundColor3 = COR_CARTAO_ALT,
		Text = "X", TextColor3 = COR_TEXTO })
	pickerCloseButton.MouseButton1Click:Connect(function() pickerGui.Enabled = false end)

	pickerList = Instance.new("Frame")
	pickerList.Size = UDim2.new(1, -20, 1, -110)
	pickerList.Position = UDim2.new(0, 10, 0, 50)
	pickerList.BackgroundTransparency = 1
	pickerList.Parent = frame
	local pickerListLayout = Instance.new("UIListLayout")
	pickerListLayout.Padding = UDim.new(0, 8)
	pickerListLayout.Parent = pickerList

	texto(frame, { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.new(0, 10, 1, -56), TextWrapped = true, TextColor3 = COR_PERIGO,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Isso reinicia atributos, nível e posição do personagem escolhido." })
end
buildResetPicker()

local function openResetPicker()
	if not GetSlotsOverview then
		notify("Seletor de personagem indisponível no momento.")
		return
	end
	for _, child in ipairs(pickerList:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local ok, overview = pcall(function() return GetSlotsOverview:InvokeServer() end)
	if not ok or not overview then
		warn("ShopClient: falha ao buscar GetSlotsOverview: " .. tostring(overview))
		return
	end
	local anySlot = false
	for index = 1, 5 do
		local info = overview.Slots[index]
		if info and not info.Locked then
			anySlot = true
			local row = botao(pickerList, { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = COR_CARTAO, LayoutOrder = index, TextColor3 = COR_TEXTO,
				Font = Enum.Font.GothamBold, Text = string.format("%s — Nv. %d %s", info.SlotName, info.Level, info.IsActive and "(ativo)" or "") })
			hoverBrighten(row, COR_CARTAO)
			row.MouseButton1Click:Connect(function()
				local buyOk, success, result = pcall(function() return BuyResetSlot:InvokeServer(index) end)
				if buyOk and success then
					pickerGui.Enabled = false
					refreshShopData()
				else
					notify(tostring(result or success))
				end
			end)
		end
	end
	if not anySlot then
		texto(pickerList, { Size = UDim2.new(1, 0, 0, 44), Text = "Nenhum personagem disponível", TextColor3 = COR_TEXTO_FRACO,
			Font = Enum.Font.GothamMedium, TextXAlignment = Enum.TextXAlignment.Center })
	end
	pickerGui.Enabled = true
end

local function buildUnlockSlotCard(order)
	local row = cartaoLinha(order, shopData.UnlockSlot.Name, "destrava o próximo slot de personagem")
	local actionButton = makeActionButton(row)
	if shopData.UnlockSlot.MaxedOut then
		actionButton.Text = "MÁX"
		actionButton.BackgroundColor3 = COR_CARTAO_ALT
		actionButton.TextColor3 = COR_TEXTO_FRACO
	else
		actionButton.Text = dinheiro(shopData.UnlockSlot.Cost)
		actionButton.BackgroundColor3 = COR_OK
		hoverBrighten(actionButton, COR_OK)
		actionButton.MouseButton1Click:Connect(function()
			if isBusy then return end
			isBusy = true
			local ok, success, result = pcall(function() return BuyUnlockSlot:InvokeServer() end)
			isBusy = false
			if ok and success then
				refreshShopData()
			else
				notify(tostring(result or success))
			end
		end)
	end
end

local function buildResetSlotCard(order)
	local row = cartaoLinha(order, shopData.ResetSlot.Name, "reinicia atributos/posição de um personagem à escolha")
	local actionButton = makeActionButton(row)
	actionButton.Text = dinheiro(shopData.ResetSlot.Cost)
	actionButton.BackgroundColor3 = COR_ACENTO
	hoverBrighten(actionButton, COR_ACENTO)
	actionButton.MouseButton1Click:Connect(openResetPicker)
end

local function buildRobuxCard(product, order)
	local row = cartaoLinha(order, product.Name, product.Configured and "produto de Robux" or "ainda não configurado — avise o dono do jogo",
		not product.Configured and COR_PERIGO or nil)
	local actionButton = makeActionButton(row)
	actionButton.Text = "R$ ROBUX"
	local cor = product.Configured and Color3.fromRGB(60, 130, 90) or COR_CARTAO_ALT
	actionButton.BackgroundColor3 = cor
	actionButton.TextColor3 = product.Configured and Color3.fromRGB(150, 255, 195) or COR_TEXTO_FRACO
	if product.Configured then hoverBrighten(actionButton, cor) end
	actionButton.MouseButton1Click:Connect(function()
		if not product.Configured then
			notify("Esse produto ainda não foi configurado no Studio.")
			return
		end
		pcall(function() MarketplaceService:PromptProductPurchase(player, product.ProductId) end)
	end)
end

-- ⚠️ v74 — Roll de Robux: o card só ABRE a tela de Roll (a compra acontece
-- num lugar só, ver RollClient).
local function buildRollRobuxCard(order)
	local row = cartaoLinha(order, "Roll de Robux (Hissatsu/Arma)", "sorteia um Hissatsu ou uma Arma — abre a tela de Roll")
	contorno(row, COR_ACENTO, 1, 0.4)
	local actionButton = makeActionButton(row)
	actionButton.Text = "ABRIR ROLL"
	actionButton.BackgroundColor3 = COR_ACENTO
	hoverBrighten(actionButton, COR_ACENTO)
	actionButton.MouseButton1Click:Connect(function()
		_G.CloseShop()
		if _G.OpenRoll then
			_G.OpenRoll()
		else
			notify("Tela de Roll indisponível no momento.")
		end
	end)
end

-- ==========================================================
-- Renderização por aba
-- ==========================================================
local function limparLista()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

renderCategory = function()
	if not shopData then return end
	contentFrame.Visible = false
	flowFrame.Visible = false
	armario.Visible = false

	if currentCategory == "Flow" then
		renderFlow()
		return
	end
	if currentCategory == "Cosmeticos" then
		renderArmario()
		return
	end

	contentFrame.Visible = true
	limparLista()
	local order = 1
	if currentCategory == "Conveniencia" then
		buildUnlockSlotCard(order); order += 1
		buildResetSlotCard(order); order += 1
	end
	if currentCategory == "Boosts" then
		local b = shopData.Boosts
		local parts = {}
		if b.MoneyBoostActive then table.insert(parts, "2x dinheiro ativo") end
		if b.XPBoostActive then table.insert(parts, "2x XP ativo") end
		if b.ExtraQuestActive then table.insert(parts, "+1 missão ativa") end
		if (b.LuckRollsRemaining or 0) > 0 then table.insert(parts, string.format("sorte no roll: %d rolagens restantes", b.LuckRollsRemaining)) end
		texto(contentFrame, { Size = UDim2.new(1, -8, 0, 30), LayoutOrder = order, TextWrapped = true, Font = Enum.Font.GothamBold,
			Text = #parts > 0 and table.concat(parts, "  ·  ") or "Nenhum boost ativo agora.", TextColor3 = #parts > 0 and COR_OK or COR_TEXTO_MEDIO })
		order += 1
	end
	if currentCategory == "Robux" then
		buildRollRobuxCard(order); order += 1
		for _, product in ipairs(shopData.RobuxProducts) do
			buildRobuxCard(product, order)
			order += 1
		end
	else
		for _, item in ipairs(shopData.Items) do
			if item.Category == currentCategory then
				buildCatalogCard(item, order)
				order += 1
			end
		end
	end
end

-- ==========================================================
-- Abas
-- ==========================================================
local function selectCategory(categoryId)
	if currentCategory ~= categoryId then
		categoriaAberta = nil
		previaForcada = {}
	end
	currentCategory = categoryId
	for id, btn in pairs(tabButtons) do
		local selecionado = (id == categoryId)
		btn.BackgroundColor3 = selecionado and COR_ACENTO or COR_CARTAO
		btn.TextColor3 = selecionado and Color3.new(1, 1, 1) or COR_TEXTO_MEDIO
	end
	renderCategory()
end

local ABAS = {
	{ Id = "Flow", Name = "FLOW" },
	{ Id = "Cosmeticos", Name = "ARMÁRIO" },
	{ Id = "Conveniencia", Name = "CONVENIÊNCIA" },
	{ Id = "Boosts", Name = "BOOSTS" },
	{ Id = "Robux", Name = "ROBUX" },
}
for i, cat in ipairs(ABAS) do
	local btn = botao(tabRow, { Size = UDim2.new(1 / #ABAS, -5, 1, 0), BackgroundColor3 = COR_CARTAO, Text = cat.Name, TextColor3 = COR_TEXTO_MEDIO,
		TextSize = 13, LayoutOrder = i })
	cantos(btn, 6)
	btn.MouseButton1Click:Connect(function() selectCategory(cat.Id) end)
	tabButtons[cat.Id] = btn
end

-- ==========================================================
-- Refresh / abrir / fechar
-- ==========================================================
refreshShopData = function()
	local ok, data = pcall(function() return GetShopData:InvokeServer() end)
	if ok and data then
		shopData = data
		possuidos = {}
		equipados = {}
		roda = data.EmoteWheel or {}
		for _, item in ipairs(data.Items) do
			if item.Owned then possuidos[item.Id] = true end
			if item.Equipped and item.Slot then equipados[item.Slot] = item.Id end
		end
		moneyLabel.Text = dinheiro(data.Money)
		renderCategory()
	else
		warn("ShopClient: falha ao buscar GetShopData: " .. tostring(data))
	end
end

_G.OpenShop = function()
	setShopVisible(true)
	selectCategory(currentCategory)
	refreshShopData()
end

_G.CloseShop = function()
	setShopVisible(false)
end

_G.ToggleShop = function()
	if screenGui.Enabled then
		_G.CloseShop()
	else
		_G.OpenShop()
	end
end

-- ⚠️ v110: abrir direto numa aba (ex.: NPC do Flow)
_G.OpenShopTab = function(aba)
	currentCategory = aba
	_G.OpenShop()
end

-- depuração (teste pelo Studio): LocalPlayer "LojaDebugAba" = aba pra abrir;
-- "LojaDebugCategoria" = slot do Armário pra expandir
player:GetAttributeChangedSignal("LojaDebugAba"):Connect(function()
	local aba = player:GetAttribute("LojaDebugAba")
	if aba then _G.OpenShopTab(aba) end
end)
player:GetAttributeChangedSignal("LojaDebugCategoria"):Connect(function()
	local slot = player:GetAttribute("LojaDebugCategoria")
	categoriaAberta = slot
	renderCategory()
end)

closeButton.MouseButton1Click:Connect(_G.CloseShop)
backdrop.MouseButton1Click:Connect(_G.CloseShop)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end
ajustarEscala()
selectCategory(currentCategory)

print("✅ ShopClient carregado (v110: Flow + Armário).")
