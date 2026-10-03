--[[
	DebugAbilitySelectorHUD (LocalScript) — ⚠️ FERRAMENTA DE TESTE, TEMPORÁRIA
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Par de DebugAbilitySelector.legacy.lua (ServerScriptService) — juntos
	dão uma HUD simples pra escolher, na hora, qual Hissatsu, Arma e Role
	(GK/DF/MF/FW) testar, sem precisar passar pelo Roll do Lobby. APAGUE os
	dois quando não precisar mais testar — nenhum outro sistema depende deles.
	Tudo construído via Instance.new (GUI não sincroniza pela ponte de
	arquivos, só scripts).

	⚠️ v122b — PEDIDO: "coloca o debug pra facilitar o acesso às armas pra quem
	tem tela menor, meu amigo pediu pra subir ele, formata ele melhor". Antes era
	uma coluna só de 860px: as listas de Armas e Hissatsus ficavam lá embaixo
	(cortadas, ou o painel inteiro encolhia pela metade e ficava ilegível). Agora:
	  • ABAS no topo — ARMAS (abre primeiro), HISSATSU, TESTES, FLOW/GOL;
	  • a altura do painel acompanha a TELA (nunca passa dela, sem encolher o texto);
	  • busca por nome nas listas de Armas e Hissatsus;
	  • linhas e botões mais altos (dá pra tocar no celular);
	  • Role (GK/DF/MF/FW) fixo no cabeçalho.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
local DebugConfigureTesting = Config.Remotes.DebugConfigureTesting

local LocalPlayer = Players.LocalPlayer

local RARITY_COLOR = {
	Common = Color3.fromRGB(220, 220, 220),
	Rare = Color3.fromRGB(120, 180, 255),
	Epic = Color3.fromRGB(200, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 60),
	Mythic = Color3.fromRGB(255, 90, 110),
}
local COR_FUNDO = Color3.fromRGB(18, 18, 24)
local COR_LINHA = Color3.fromRGB(30, 30, 38)
local COR_BOTAO = Color3.fromRGB(46, 46, 56)
local COR_LIGADO = Color3.fromRGB(80, 200, 120)
local COR_DESLIGADO = Color3.fromRGB(70, 70, 78)
local LARGURA = 320
local TOPO = 60 -- onde o painel começa (logo abaixo do botão 🛠)

local function cantos(obj, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio or 6)
	c.Parent = obj
	return c
end

local function lista(parent, espaco)
	local l = Instance.new("UIListLayout")
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, espaco or 4)
	l.Parent = parent
	return l
end

-- ===== SHELL =====
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DebugAbilitySelectorHUD"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 100
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

local toggleButton = Instance.new("TextButton")
toggleButton.Name = "ToggleButton"
toggleButton.AnchorPoint = Vector2.new(1, 0)
toggleButton.Position = UDim2.new(1, -10, 0, 10)
toggleButton.Size = UDim2.fromOffset(44, 44)
toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.Font = Enum.Font.GothamBold
toggleButton.TextSize = 20
toggleButton.Text = "🛠"
toggleButton.Parent = screenGui
cantos(toggleButton, 8)

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.AnchorPoint = Vector2.new(1, 0)
panel.Position = UDim2.new(1, -10, 0, TOPO)
panel.Size = UDim2.fromOffset(LARGURA, 600)
panel.BackgroundColor3 = COR_FUNDO
panel.BackgroundTransparency = 0.04
panel.Visible = false
panel.Parent = screenGui
cantos(panel, 10)
do
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = panel
end

-- a altura acompanha a tela (sem UIScale: o texto continua legível)
do
	local function ajustar()
		local cam = workspace.CurrentCamera
		local tela = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local altura = math.clamp(tela.Y - TOPO - 12, 240, 720)
		local largura = math.min(LARGURA, tela.X - 20)
		panel.Size = UDim2.fromOffset(largura, altura)
	end
	ajustar()
	if workspace.CurrentCamera then
		workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustar)
	end
end

toggleButton.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

-- ===== CABEÇALHO: título + Role =====
local CAB_ALTURA = 18 + 4 + 30 + 4 + 30 + 6 -- título, role, abas
do
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 13
	title.TextColor3 = Color3.fromRGB(255, 210, 90)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = "⚠️ DEBUG — apagar depois do teste"
	title.Parent = panel

	local roleRow = Instance.new("Frame")
	roleRow.BackgroundTransparency = 1
	roleRow.Position = UDim2.fromOffset(0, 22)
	roleRow.Size = UDim2.new(1, 0, 0, 30)
	roleRow.Parent = panel
	local roleLayout = Instance.new("UIListLayout")
	roleLayout.FillDirection = Enum.FillDirection.Horizontal
	roleLayout.HorizontalFlex = Enum.UIFlexAlignment.Fill
	roleLayout.Padding = UDim.new(0, 4)
	roleLayout.Parent = roleRow
	for _, role in ipairs({ "GK", "DF", "MF", "FW" }) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.25, -3, 1, 0)
		btn.BackgroundColor3 = COR_BOTAO
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 13
		btn.Text = role
		btn.Parent = roleRow
		cantos(btn)
		btn.MouseButton1Click:Connect(function()
			DebugConfigureTesting:FireServer("Role", role)
		end)
	end
end

-- ===== ABAS =====
local abasRow = Instance.new("Frame")
abasRow.BackgroundTransparency = 1
abasRow.Position = UDim2.fromOffset(0, 56)
abasRow.Size = UDim2.new(1, 0, 0, 30)
abasRow.Parent = panel
do
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.HorizontalFlex = Enum.UIFlexAlignment.Fill
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, 4)
	l.Parent = abasRow
end

local conteudo = Instance.new("Frame")
conteudo.BackgroundTransparency = 1
conteudo.Position = UDim2.fromOffset(0, CAB_ALTURA)
conteudo.Size = UDim2.new(1, 0, 1, -CAB_ALTURA)
conteudo.Parent = panel

local abas = {} -- { Botao, Pagina }
local function mostrarAba(nome)
	for n, a in pairs(abas) do
		local ativa = n == nome
		a.Pagina.Visible = ativa
		a.Botao.BackgroundColor3 = ativa and Color3.fromRGB(80, 160, 220) or COR_BOTAO
	end
end

local function novaAba(ordem, nome, texto)
	local b = Instance.new("TextButton")
	b.LayoutOrder = ordem
	b.Size = UDim2.new(0.25, -3, 1, 0)
	b.BackgroundColor3 = COR_BOTAO
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 12
	b.Text = texto
	b.Parent = abasRow
	cantos(b)

	local pagina = Instance.new("ScrollingFrame")
	pagina.Name = "Aba_" .. nome
	pagina.BackgroundTransparency = 1
	pagina.BorderSizePixel = 0
	pagina.Size = UDim2.fromScale(1, 1)
	pagina.ScrollBarThickness = 6
	pagina.ScrollingDirection = Enum.ScrollingDirection.Y
	pagina.CanvasSize = UDim2.new()
	pagina.AutomaticCanvasSize = Enum.AutomaticSize.Y
	pagina.Visible = false
	pagina.Parent = conteudo
	lista(pagina, 4)
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingRight = UDim.new(0, 8) -- espaço da barra de rolagem
		pad.Parent = pagina
	end

	abas[nome] = { Botao = b, Pagina = pagina }
	b.MouseButton1Click:Connect(function() mostrarAba(nome) end)
	return pagina
end

-- botão de largura cheia numa página (ordem automática)
local ordemDe = {}
local function proximaOrdem(pagina)
	ordemDe[pagina] = (ordemDe[pagina] or 0) + 1
	return ordemDe[pagina]
end
local function botaoDebug(pagina, texto, cor)
	local b = Instance.new("TextButton")
	b.LayoutOrder = proximaOrdem(pagina)
	b.Size = UDim2.new(1, 0, 0, 32)
	b.BackgroundColor3 = cor or COR_DESLIGADO
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.TextWrapped = true
	b.Text = texto
	b.Parent = pagina
	cantos(b)
	return b
end
local function titulo(pagina, texto)
	local label = Instance.new("TextLabel")
	label.LayoutOrder = proximaOrdem(pagina)
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 18)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = Color3.fromRGB(180, 180, 190)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Text = texto
	label.Parent = pagina
end
local function alternador(pagina, rotulo, kind)
	local ligado = false
	local b = botaoDebug(pagina, rotulo .. ": OFF", COR_DESLIGADO)
	b.MouseButton1Click:Connect(function()
		ligado = not ligado
		b.BackgroundColor3 = ligado and COR_LIGADO or COR_DESLIGADO
		b.Text = rotulo .. (ligado and ": ON" or ": OFF")
		DebugConfigureTesting:FireServer(kind, ligado)
	end)
	return b
end

-- caixa de busca: esconde as linhas cujo nome não contém o texto
local function busca(pagina, linhas)
	local caixa = Instance.new("TextBox")
	caixa.LayoutOrder = proximaOrdem(pagina)
	caixa.Size = UDim2.new(1, 0, 0, 30)
	caixa.BackgroundColor3 = COR_LINHA
	caixa.TextColor3 = Color3.fromRGB(255, 255, 255)
	caixa.PlaceholderText = "🔎 buscar pelo nome..."
	caixa.PlaceholderColor3 = Color3.fromRGB(130, 130, 140)
	caixa.Font = Enum.Font.Gotham
	caixa.TextSize = 13
	caixa.Text = ""
	caixa.ClearTextOnFocus = false
	caixa.TextXAlignment = Enum.TextXAlignment.Left
	caixa.Parent = pagina
	cantos(caixa)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 8)
	pad.Parent = caixa
	caixa:GetPropertyChangedSignal("Text"):Connect(function()
		local q = string.lower(caixa.Text)
		for _, l in ipairs(linhas) do
			l.Frame.Visible = q == "" or string.find(l.Busca, q, 1, true) ~= nil
		end
	end)
end

-- uma linha de lista: bolinha de cor, nome, etiqueta e botão Equipar
local function linhaEquipar(pagina, def, corBolinha, nome, etiqueta, corEtiqueta, corBotao, aoClicar)
	local row = Instance.new("Frame")
	row.LayoutOrder = proximaOrdem(pagina)
	row.BackgroundColor3 = COR_LINHA
	row.Size = UDim2.new(1, 0, 0, 32)
	row.Parent = pagina
	cantos(row, 5)

	local swatch = Instance.new("Frame")
	swatch.Position = UDim2.new(0, 7, 0.5, 0)
	swatch.AnchorPoint = Vector2.new(0, 0.5)
	swatch.Size = UDim2.fromOffset(10, 10)
	swatch.BackgroundColor3 = corBolinha or Color3.fromRGB(120, 120, 120)
	swatch.BorderSizePixel = 0
	swatch.Parent = row
	cantos(swatch, 5)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Position = UDim2.new(0, 22, 0, 0)
	nameLabel.Size = UDim2.new(1, -22 - 44 - 74, 1, 0)
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextSize = 13
	nameLabel.TextColor3 = RARITY_COLOR[def.Rarity] or Color3.fromRGB(255, 255, 255)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Text = nome
	nameLabel.Parent = row

	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, -74, 0, 0)
	tag.Size = UDim2.fromOffset(42, 32)
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 10
	tag.TextXAlignment = Enum.TextXAlignment.Right
	tag.TextColor3 = corEtiqueta
	tag.Text = etiqueta
	tag.Parent = row

	local equipButton = Instance.new("TextButton")
	equipButton.AnchorPoint = Vector2.new(1, 0.5)
	equipButton.Position = UDim2.new(1, -4, 0.5, 0)
	equipButton.Size = UDim2.fromOffset(66, 24)
	equipButton.BackgroundColor3 = corBotao
	equipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	equipButton.Font = Enum.Font.GothamBold
	equipButton.TextSize = 12
	equipButton.Text = "Equipar"
	equipButton.Parent = row
	cantos(equipButton, 4)
	equipButton.MouseButton1Click:Connect(function()
		aoClicar()
		-- confirmação visual rápida
		equipButton.Text = "✓"
		task.delay(0.6, function() equipButton.Text = "Equipar" end)
	end)

	return { Frame = row, Busca = string.lower(nome .. " " .. etiqueta) }
end

-- ===== ABA ARMAS (abre primeiro) =====
local paginaArmas = novaAba(1, "Armas", "ARMAS")
do
	titulo(paginaArmas, "R = aperta · AUTO = sozinho · — = passivo")
	local linhas = {}
	busca(paginaArmas, linhas)
	for _, def in ipairs(PulseData.Instincts) do
		local etiqueta, cor
		if def.Tecla then
			etiqueta, cor = def.Tecla, Color3.fromRGB(255, 205, 60)
		elseif def.AtivaAction then
			etiqueta, cor = "AUTO", Color3.fromRGB(120, 200, 255)
		else
			etiqueta, cor = "—", Color3.fromRGB(110, 110, 120)
		end
		-- (a bolinha é a COR DA AURA da arma — a mesma que acende em campo)
		local nome = def.Posicao and (def.Posicao .. "  " .. def.Name) or def.Name
		table.insert(linhas, linhaEquipar(paginaArmas, def, def.Cor, nome, etiqueta, cor, COR_LIGADO, function()
			DebugConfigureTesting:FireServer("Instinct", def.Name)
		end))
	end
end

-- ===== ABA HISSATSU =====
local paginaHissatsu = novaAba(2, "Hissatsu", "HISSATSU")
do
	titulo(paginaHissatsu, "Tecla 1 · Equipar manda pro slot único")
	local linhas = {}
	busca(paginaHissatsu, linhas)
	for _, def in ipairs(PulseData.Pulses) do
		table.insert(linhas, linhaEquipar(paginaHissatsu, def, RARITY_COLOR[def.Rarity], def.Name,
			tostring(def.Action or "?"), Color3.fromRGB(120, 200, 255), Color3.fromRGB(80, 160, 220), function()
				DebugConfigureTesting:FireServer("Pulse", def.Name)
			end))
	end
end

-- ===== ABA TESTES =====
local paginaTestes = novaAba(3, "Testes", "TESTES")
do
	titulo(paginaTestes, "Cooldown e energia")
	-- liga/desliga _G.SetPulseDebugNoDelay no servidor (sem cooldown e sem wind-up)
	alternador(paginaTestes, "Sem cooldown (Hissatsu + Arma)", "NoDelay")
	botaoDebug(paginaTestes, "Zerar cooldowns agora", Color3.fromRGB(70, 110, 170)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("ZerarCooldowns", true)
	end)
	alternador(paginaTestes, "Energia infinita", "EnergiaInfinita")
	alternador(paginaTestes, "Chutes em grupo sozinho", "TrioSozinho")

	titulo(paginaTestes, "Bola e posição")
	botaoDebug(paginaTestes, "Pegar a bola", Color3.fromRGB(70, 110, 170)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("DarBola", true)
	end)
	botaoDebug(paginaTestes, "Ir pro gol (com a bola)", Color3.fromRGB(70, 110, 170)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("IrProGol", 55)
	end)
	-- sozinho no teste, o goleiro bot fica no SEU gol — esse vai pra ele
	botaoDebug(paginaTestes, "Ir pro gol do goleiro bot (testar defesa)", Color3.fromRGB(70, 110, 170)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("IrProGolDoBot", 45)
	end)
	botaoDebug(paginaTestes, "⚽ Reespawnar bola (centro)", Color3.fromRGB(200, 85, 85)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("RespawnBall", true)
	end)

	-- uma das técnicas de goleiro: toca a cutscene de defesa em você
	local HissatsuCutscenes = require(ReplicatedStorage:WaitForChild("HissatsuCutscenes"))
	local nomes = {}
	for nome in pairs(HissatsuCutscenes.DefesaPorNome or {}) do table.insert(nomes, nome) end
	table.sort(nomes)
	if #nomes > 0 then
		titulo(paginaTestes, "Defesa do goleiro")
		local iDefesa = 1
		local escolherButton = botaoDebug(paginaTestes, "Defesa: " .. nomes[1] .. "  (trocar)", Color3.fromRGB(60, 130, 120))
		escolherButton.MouseButton1Click:Connect(function()
			iDefesa = iDefesa % #nomes + 1
			escolherButton.Text = "Defesa: " .. nomes[iDefesa] .. "  (trocar)"
		end)
		botaoDebug(paginaTestes, "Testar defesa (cutscene do goleiro)", Color3.fromRGB(60, 130, 120)).MouseButton1Click:Connect(function()
			DebugConfigureTesting:FireServer("TestarDefesa", nomes[iDefesa])
		end)
	end

	titulo(paginaTestes, "Replay")
	botaoDebug(paginaTestes, "Testar replay (últimos segundos)", Color3.fromRGB(60, 110, 150)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("TestarReplay", true)
	end)
end

-- ===== ABA FLOW / GOL (Flow e cosméticos da Loja) =====
local paginaFlow = novaAba(4, "Flow", "FLOW/GOL")
do
	local Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos"))
	titulo(paginaFlow, "Flow")
	local iFlow = 1
	local flowButton = botaoDebug(paginaFlow, "Flow: " .. Cosmeticos.Flow[1].Nome .. "  (trocar)", Color3.fromRGB(90, 80, 150))
	flowButton.MouseButton1Click:Connect(function()
		iFlow = iFlow % #Cosmeticos.Flow + 1
		local f = Cosmeticos.Flow[iFlow]
		flowButton.Text = "Flow: " .. f.Nome .. "  (trocar)"
		DebugConfigureTesting:FireServer("Cosmetico", { "Flow", f.Id })
	end)
	botaoDebug(paginaFlow, "Encher o Flow (aperte a tecla do Flow)", Color3.fromRGB(90, 80, 150)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("EncherFlow", true)
	end)

	titulo(paginaFlow, "Cosméticos e gol")
	botaoDebug(paginaFlow, "Sortear cosméticos (1 de cada)", Color3.fromRGB(150, 110, 60)).MouseButton1Click:Connect(function()
		for _, cat in ipairs(Cosmeticos.CATEGORIAS) do
			if cat ~= "Flow" then
				local itens = Cosmeticos[cat]
				DebugConfigureTesting:FireServer("Cosmetico", { cat, itens[math.random(1, #itens)].Id })
			end
		end
	end)
	botaoDebug(paginaFlow, "Testar comemoração + efeito de gol", Color3.fromRGB(150, 110, 60)).MouseButton1Click:Connect(function()
		DebugConfigureTesting:FireServer("TestarGol", true)
	end)
end

mostrarAba("Armas")
