--[[
	HissatsuQTEWindow (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	Componente visual dos 3 QTEs do lote de Pulsos "Hissatsu" (v6, ver
	PulseController.legacy.luau -> startHissatsuQTE e PulseInstinctData.luau
	-> campo QTE de cada Pulso). Tudo via Instance.new (GUI não sincroniza
	pela ponte, só script).

	"Tap" (chutes): alvos em posições ALEATÓRIAS dentro de um painel — clique
	em RequiredHits alvos dentro de HitWindow segundos.
	"TimingBar" (defesa): marcador indo e voltando numa barra — ESPAÇO (ou
	clique) quando ele estiver na faixa boa, RequiredHits vezes.
	"MashAD" (arrancada): alterne A e D até bater RequiredAlternations.

	⚠️ v95 — REDESIGN. PEDIDO: "substitua o quadro de acertar os botões em uma
	frame na cutscene com background discreto. Melhore também o design dos
	botões onde você aperta no quick time event, e da barra do quick time
	event". O que mudou (a LÓGICA é a mesma de antes — só o visual):
	  • tudo mora num PAINEL: fundo escuro translúcido, cantos arredondados,
	    borda fina alaranjada, cabeçalho com o nome da técnica. Durante uma
	    cutscene de Hissatsu (params.EmCutscene) o painel fica no lado DIREITO
	    da tela, pra não tampar a animação, e por cima das tarjas de cinema;
	  • ALVO: círculo com gradiente de fogo, anel branco, número da ordem, e
	    um anel externo "respirando" chamando o clique; ao acertar ele estoura
	    num anel que se expande e some;
	  • BARRAS: trilho arredondado com brilho interno e preenchimento em
	    gradiente; a barra de tempo do Tap esvazia e fica vermelha no fim;
	  • bolinhas de progresso (uma por acerto necessário) e teclas desenhadas
	    como keycaps (ESPAÇO, A, D) que acendem quando apertadas.

	Em QUALQUER Pulse Feedback terminal (Fired/Fizzled/Whiffed) a janela se
	esconde na hora — ver HissatsuInput.local.luau, que chama Hide().
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local HissatsuQTEWindow = {}

local player = Players.LocalPlayer
local screenGui
local activeConnections = {} -- lista de RBXScriptConnection pra desconectar tudo no Hide()
local currentSlot = nil
local onInputCallback = nil -- function(payload) chamada quando o jogador "responde" o QTE ativo

-- ===== paleta =====
local COR_PAINEL = Color3.fromRGB(14, 11, 16)
local COR_TEXTO = Color3.fromRGB(255, 244, 230)
local COR_TEXTO_SUAVE = Color3.fromRGB(205, 190, 180)
local COR_TRILHO = Color3.fromRGB(32, 26, 30)
-- ⚠️ v103 — CORES DA TÉCNICA. PEDIDO: "as cutscenes têm que mudar o QTE... a
-- aparência. O Tornado de Fogo tá ótimo, laranja... o Fúria Glacial tá na
-- mesma aparência, laranja também. Muda pra um azul da cor do Fúria Glacial,
-- a própria cor do anime". As variáveis abaixo NÃO são mais fixas: Show()
-- troca pelo tema da técnica antes de montar o painel (ver temaDaTecnica).
-- O padrão continua sendo o fogo do Tornado.
local COR_BORDA = Color3.fromRGB(255, 140, 50)
local COR_FOGO_A = Color3.fromRGB(255, 225, 120)
local COR_FOGO_B = Color3.fromRGB(255, 130, 30)
local COR_FOGO_C = Color3.fromRGB(215, 45, 20)
local COR_CONTORNO_TITULO = Color3.fromRGB(60, 10, 0)
local COR_FUNDO_TINTA = Color3.fromRGB(60, 30, 20)
local COR_NUMERO = Color3.fromRGB(120, 30, 5)

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
local okDados, PulseInstinctData = pcall(require, ReplicatedStorage:WaitForChild("PulseInstinctData"))
local okCut, HissatsuCutscenes = pcall(require, ReplicatedStorage:WaitForChild("HissatsuCutscenes"))

local TEMA_FOGO = {
	A = Color3.fromRGB(255, 225, 120), B = Color3.fromRGB(255, 130, 30), C = Color3.fromRGB(215, 45, 20),
	Contorno = Color3.fromRGB(60, 10, 0),
}
-- técnica sem cutscene: pela cor do elemento
local TEMA_ELEMENTO = {
	Fogo = TEMA_FOGO,
	Luz = { A = Color3.fromRGB(255, 255, 225), B = Color3.fromRGB(255, 225, 70), C = Color3.fromRGB(255, 160, 0), Contorno = Color3.fromRGB(35, 25, 90) },
	Vento = { A = Color3.fromRGB(225, 255, 250), B = Color3.fromRGB(90, 220, 200), C = Color3.fromRGB(20, 140, 150), Contorno = Color3.fromRGB(5, 40, 50) },
	Natureza = { A = Color3.fromRGB(230, 255, 220), B = Color3.fromRGB(110, 210, 110), C = Color3.fromRGB(30, 130, 60), Contorno = Color3.fromRGB(5, 40, 15) },
	Void = { A = Color3.fromRGB(240, 215, 255), B = Color3.fromRGB(170, 90, 255), C = Color3.fromRGB(90, 20, 160), Contorno = Color3.fromRGB(25, 0, 40) },
}

local function temaDaTecnica(nome)
	local def
	if okDados and type(PulseInstinctData) == "table" and type(PulseInstinctData.Pulses) == "table" then
		for _, d in ipairs(PulseInstinctData.Pulses) do
			if d.Name == nome then def = d break end
		end
	end
	if def and def.Cutscene and okCut and type(HissatsuCutscenes) == "table" then
		local spec = HissatsuCutscenes[def.Cutscene]
		local tema = spec and spec.Tema
		if tema and tema.Titulo then
			return { A = tema.Titulo[1], B = tema.Titulo[2], C = tema.Titulo[3], Contorno = tema.Contorno or TEMA_FOGO.Contorno }
		end
		return TEMA_FOGO -- Tornado de Fogo (sem Tema = o fogo de sempre)
	end
	return (def and TEMA_ELEMENTO[def.Element]) or TEMA_FOGO
end

local function aplicarTema(tema)
	COR_FOGO_A, COR_FOGO_B, COR_FOGO_C = tema.A, tema.B, tema.C
	COR_BORDA = tema.B
	COR_CONTORNO_TITULO = tema.Contorno
	COR_FUNDO_TINTA = tema.C:Lerp(Color3.new(0, 0, 0), 0.7)
	COR_NUMERO = tema.C:Lerp(Color3.new(0, 0, 0), 0.45)
end
local COR_PERFEITO = Color3.fromRGB(110, 235, 150)
local COR_BOM = Color3.fromRGB(255, 205, 90)
local COR_FALTANDO = Color3.fromRGB(70, 60, 66)

local FONTE_TITULO = Enum.Font.GothamBlack
local FONTE_TEXTO = Enum.Font.GothamBold

local function ensureGui()
	if screenGui and screenGui.Parent then return end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "HissatsuQTEWindow"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	-- ⚠️ v95: acima da cutscene (tarjas/flash estão em 60) e marcada pra a
	-- cutscene NÃO esconder junto com o resto do HUD (ver esconderHud em
	-- HissatsuCutsceneClient.local.luau).
	screenGui.DisplayOrder = 65
	screenGui:SetAttribute("VisivelNaCutscene", true)
	screenGui.Enabled = false
	screenGui.Parent = player:WaitForChild("PlayerGui")
end

local function clearGui()
	if screenGui then
		for _, child in ipairs(screenGui:GetChildren()) do
			child:Destroy()
		end
	end
end

local function disconnectAll()
	for _, conn in ipairs(activeConnections) do
		conn:Disconnect()
	end
	activeConnections = {}
end

function HissatsuQTEWindow.Hide()
	disconnectAll()
	if screenGui then
		screenGui.Enabled = false
	end
	currentSlot = nil
	onInputCallback = nil
	-- ⚠️ v9: restaura o Shift Lock (se estava ligado antes) assim que
	-- QUALQUER QTE fecha — ver showTap abaixo e _G.SetMouseLockSuspendedForQTE
	-- em FootballClient.local.luau. Seguro chamar mesmo se não era um QTE
	-- de clique (TimingBar/MashAD nunca suspendem, então isto não faz nada).
	if _G.SetMouseLockSuspendedForQTE then _G.SetMouseLockSuspendedForQTE(false) end
end

-- ============================================================
-- PEÇAS DE DESIGN (reaproveitadas pelos 3 QTEs)
-- ============================================================
local function canto(pai, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = raio or UDim.new(0, 12)
	c.Parent = pai
	return c
end

local function borda(pai, cor, espessura, transparencia)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = espessura or 1.5
	s.Transparency = transparencia or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = pai
	return s
end

local function gradienteFogo(pai, rotacao)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COR_FOGO_A),
		ColorSequenceKeypoint.new(0.5, COR_FOGO_B),
		ColorSequenceKeypoint.new(1, COR_FOGO_C),
	})
	g.Rotation = rotacao or 0
	g.Parent = pai
	return g
end

local function rotulo(pai, texto, tamanho, cor, fonte)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = texto
	l.TextSize = tamanho
	l.TextColor3 = cor or COR_TEXTO
	l.Font = fonte or FONTE_TEXTO
	l.Parent = pai
	return l
end

-- Painel base: fundo escuro translúcido (o "background discreto"), borda
-- fina alaranjada, cabeçalho com o nome da técnica e uma linha de subtítulo.
-- Na cutscene fica à direita; fora dela, no centro (um pouco acima).
local function criarPainel(nomeTecnica, subtitulo, largura, altura, emCutscene)
	local painel = Instance.new("Frame")
	painel.Name = "Painel"
	painel.AnchorPoint = Vector2.new(0.5, 0.5)
	painel.Position = emCutscene and UDim2.new(0.8, 0, 0.5, 0) or UDim2.new(0.5, 0, 0.55, 0) -- (0.45 encostava no placar)
	painel.Size = UDim2.fromOffset(largura, altura)
	painel.BackgroundColor3 = COR_PAINEL
	painel.BackgroundTransparency = emCutscene and 0.45 or 0.3
	painel.BorderSizePixel = 0
	painel.Parent = screenGui
	canto(painel, UDim.new(0, 18))
	borda(painel, COR_BORDA, 1.5, 0.55)

	-- brilho sutil de cima pra baixo no fundo
	local fundoGrad = Instance.new("UIGradient")
	fundoGrad.Rotation = 90
	fundoGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(1, 0.25),
	})
	fundoGrad.Color = ColorSequence.new(COR_FUNDO_TINTA, Color3.fromRGB(255, 255, 255))
	fundoGrad.Parent = painel

	local titulo = rotulo(painel, maiusculas(nomeTecnica or "HISSATSU"), 17, COR_TEXTO, FONTE_TITULO)
	titulo.Name = "Titulo"
	titulo.Position = UDim2.fromOffset(0, 12)
	titulo.Size = UDim2.new(1, 0, 0, 20)
	gradienteFogo(titulo, 90)
	local tituloBorda = Instance.new("UIStroke")
	tituloBorda.Color = COR_CONTORNO_TITULO
	tituloBorda.Thickness = 1.5
	tituloBorda.Parent = titulo

	local sub = rotulo(painel, subtitulo or "", 12, COR_TEXTO_SUAVE, FONTE_TEXTO)
	sub.Name = "Subtitulo"
	sub.Position = UDim2.fromOffset(0, 34)
	sub.Size = UDim2.new(1, 0, 0, 16)

	-- entrada: cresce de leve e aparece
	local escala = Instance.new("UIScale")
	escala.Scale = 0.85
	escala.Parent = painel
	TweenService:Create(escala, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	return painel, sub
end

-- Barra: trilho escuro arredondado + preenchimento em gradiente de fogo.
local function criarBarra(pai, posicao, largura, altura)
	local trilho = Instance.new("Frame")
	trilho.Name = "Trilho"
	trilho.Position = posicao
	trilho.Size = UDim2.new(0, largura, 0, altura)
	trilho.BackgroundColor3 = COR_TRILHO
	trilho.BorderSizePixel = 0
	trilho.Parent = pai
	canto(trilho, UDim.new(1, 0))
	borda(trilho, Color3.fromRGB(0, 0, 0), 1, 0.4)

	local preenchimento = Instance.new("Frame")
	preenchimento.Name = "Preenchimento"
	preenchimento.Size = UDim2.new(0, 0, 1, 0)
	preenchimento.BackgroundColor3 = Color3.new(1, 1, 1)
	preenchimento.BorderSizePixel = 0
	preenchimento.Parent = trilho
	canto(preenchimento, UDim.new(1, 0))
	local grad = gradienteFogo(preenchimento, 0)

	-- reflexo de luz na metade de cima (dá volume à barra)
	local reflexo = Instance.new("Frame")
	reflexo.BackgroundColor3 = Color3.new(1, 1, 1)
	reflexo.BackgroundTransparency = 0.8
	reflexo.BorderSizePixel = 0
	reflexo.Size = UDim2.new(1, -4, 0.4, 0)
	reflexo.Position = UDim2.new(0, 2, 0, 1)
	reflexo.ZIndex = 3
	reflexo.Parent = trilho
	canto(reflexo, UDim.new(1, 0))

	return trilho, preenchimento, grad
end

-- Bolinhas de progresso: uma por acerto necessário.
local function criarBolinhas(pai, posicao, quantidade)
	local linha = Instance.new("Frame")
	linha.Name = "Bolinhas"
	linha.BackgroundTransparency = 1
	linha.Position = posicao
	linha.Size = UDim2.new(1, 0, 0, 12)
	linha.Parent = pai
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 6)
	layout.Parent = linha
	local lista = {}
	for i = 1, quantidade do
		local b = Instance.new("Frame")
		b.Size = UDim2.fromOffset(10, 10)
		b.BackgroundColor3 = COR_FALTANDO
		b.BorderSizePixel = 0
		b.LayoutOrder = i
		b.Parent = linha
		canto(b, UDim.new(1, 0))
		borda(b, Color3.fromRGB(0, 0, 0), 1, 0.5)
		lista[i] = b
	end
	local function marcar(n, cor)
		for i, b in ipairs(lista) do
			if i <= n then
				if b.BackgroundColor3 == COR_FALTANDO then
					local escala = Instance.new("UIScale")
					escala.Scale = 1.8
					escala.Parent = b
					TweenService:Create(escala, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
				end
				b.BackgroundColor3 = cor or COR_FOGO_B
			end
		end
	end
	return marcar
end

-- Tecla desenhada como keycap (acende quando apertada).
local function criarTecla(pai, texto, largura)
	local tecla = Instance.new("TextButton")
	tecla.Name = "Tecla_" .. texto
	tecla.AutoButtonColor = false
	tecla.Size = UDim2.fromOffset(largura or 44, 40)
	tecla.BackgroundColor3 = Color3.fromRGB(40, 34, 40)
	tecla.Text = texto
	tecla.Font = FONTE_TITULO
	tecla.TextSize = 16
	tecla.TextColor3 = COR_TEXTO
	tecla.Parent = pai
	canto(tecla, UDim.new(0, 8))
	local b = borda(tecla, Color3.fromRGB(255, 255, 255), 1.5, 0.75)
	-- volume de tecla: mais clara em cima, mais escura embaixo
	local volume = Instance.new("UIGradient")
	volume.Rotation = 90
	volume.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 150))
	volume.Parent = tecla
	local function acender()
		tecla.BackgroundColor3 = COR_FOGO_B
		b.Color = COR_FOGO_A
		b.Transparency = 0
		TweenService:Create(tecla, TweenInfo.new(0.25), { BackgroundColor3 = Color3.fromRGB(40, 34, 40) }):Play()
		TweenService:Create(b, TweenInfo.new(0.25), { Transparency = 0.75 }):Play()
	end
	return tecla, acender
end

-- Anel que estoura (acerto): cresce e some.
local function estouro(pai, posicao, tamanho, cor)
	local anel = Instance.new("Frame")
	anel.AnchorPoint = Vector2.new(0.5, 0.5)
	anel.Position = posicao
	anel.Size = UDim2.fromOffset(tamanho, tamanho)
	anel.BackgroundTransparency = 1
	anel.ZIndex = 8
	anel.Parent = pai
	canto(anel, UDim.new(1, 0))
	local s = borda(anel, cor, 4, 0)
	TweenService:Create(anel, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(tamanho * 2, tamanho * 2) }):Play()
	TweenService:Create(s, TweenInfo.new(0.3), { Transparency = 1, Thickness = 1 }):Play()
	task.delay(0.35, function() anel:Destroy() end)
end

-- ============================================================
-- "Tap" — alvos em posições aleatórias dentro do painel
-- ============================================================
local TAP_ZONA = 250      -- lado da área (px) onde os alvos podem nascer
local TAP_ALVO = 66

local function showTap(pulseName, params)
	clearGui()

	-- ⚠️ v9 PEDIDO: destrava o mouse (se estava preso no centro pelo Shift
	-- Lock) assim que o QTE de CLIQUE aparece — a mira do chute já foi
	-- travada antes disso (ver HissatsuInput.local.luau), então mexer o
	-- mouse pra clicar os alvos não muda mais pra onde a bola vai.
	if _G.SetMouseLockSuspendedForQTE then _G.SetMouseLockSuspendedForQTE(true) end

	local emCutscene = params.EmCutscene == true
	local painel, sub = criarPainel(pulseName, "CLIQUE NOS ALVOS", TAP_ZONA + 40, TAP_ZONA + 118, emCutscene)

	local zona = Instance.new("Frame")
	zona.Name = "Zona"
	zona.Position = UDim2.fromOffset(20, 60)
	zona.Size = UDim2.fromOffset(TAP_ZONA, TAP_ZONA)
	zona.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	zona.BackgroundTransparency = 0.75
	zona.BorderSizePixel = 0
	zona.Parent = painel
	canto(zona, UDim.new(0, 14))
	borda(zona, COR_BORDA, 1, 0.8)

	local requiredHits = math.max(tonumber(params.RequiredHits) or 5, 1)
	local marcarBolinhas = criarBolinhas(painel, UDim2.fromOffset(0, TAP_ZONA + 70), requiredHits)
	local _, tempoFill, tempoGrad = criarBarra(painel, UDim2.fromOffset(20, TAP_ZONA + 92), TAP_ZONA, 10)

	-- ===== o alvo =====
	local alvo = Instance.new("TextButton")
	alvo.Name = "Alvo"
	alvo.AutoButtonColor = false
	alvo.AnchorPoint = Vector2.new(0.5, 0.5)
	alvo.Size = UDim2.fromOffset(TAP_ALVO, TAP_ALVO)
	alvo.BackgroundColor3 = Color3.new(1, 1, 1)
	alvo.Text = ""
	alvo.ZIndex = 5
	alvo.Visible = false
	alvo.Parent = zona
	canto(alvo, UDim.new(1, 0))
	gradienteFogo(alvo, 45)
	local alvoBorda = borda(alvo, Color3.new(1, 1, 1), 3, 0)

	-- miolo claro + número da ordem
	local miolo = Instance.new("Frame")
	miolo.AnchorPoint = Vector2.new(0.5, 0.5)
	miolo.Position = UDim2.fromScale(0.5, 0.5)
	miolo.Size = UDim2.fromScale(0.52, 0.52)
	miolo.BackgroundColor3 = Color3.fromRGB(255, 250, 235)
	miolo.BackgroundTransparency = 0.1
	miolo.ZIndex = 6
	miolo.Parent = alvo
	canto(miolo, UDim.new(1, 0))
	local numero = rotulo(miolo, "1", 18, COR_NUMERO, FONTE_TITULO)
	numero.Size = UDim2.fromScale(1, 1)
	numero.ZIndex = 7

	-- anel externo "respirando" — chama o clique
	local chamariz = Instance.new("Frame")
	chamariz.AnchorPoint = Vector2.new(0.5, 0.5)
	chamariz.Position = UDim2.fromScale(0.5, 0.5)
	chamariz.Size = UDim2.fromScale(1.5, 1.5)
	chamariz.BackgroundTransparency = 1
	chamariz.ZIndex = 4
	chamariz.Parent = alvo
	canto(chamariz, UDim.new(1, 0))
	local chamarizBorda = borda(chamariz, COR_FOGO_A, 2, 0.3)

	local prepTime = math.max(tonumber(params.PrepTime) or 0, 0)
	local hitWindow = math.max(tonumber(params.HitWindow) or 0.8, 0.1)
	local startedAt = os.clock()
	local targetShown = false
	local hits = 0
	local done = false

	local margem = TAP_ALVO / 2 + 10 -- o alvo nasce INTEIRO dentro da área

	local function posicionarAlvo()
		local x = math.random(margem, TAP_ZONA - margem)
		local y = math.random(margem, TAP_ZONA - margem)
		alvo.Position = UDim2.fromOffset(x, y)
		numero.Text = tostring(hits + 1)
		-- nasce pequeno e "abre"
		alvo.Size = UDim2.fromOffset(TAP_ALVO * 0.4, TAP_ALVO * 0.4)
		TweenService:Create(alvo, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Size = UDim2.fromOffset(TAP_ALVO, TAP_ALVO) }):Play()
	end

	-- PEDIDO: "faz uns 5 botões aparecerem" — cada clique válido conta 1
	-- acerto (o servidor é quem decide de verdade, isso aqui é só visual)
	-- e um NOVO alvo nasce em outra posição aleatória, até bater
	-- requiredHits ou a janela fechar.
	alvo.MouseButton1Click:Connect(function()
		if done or not targetShown then return end
		hits += 1
		marcarBolinhas(hits)
		estouro(zona, alvo.Position, TAP_ALVO, COR_FOGO_A)
		if onInputCallback then onInputCallback({}) end
		if hits >= requiredHits then
			done = true
			alvo.Visible = false
			sub.Text = "PERFEITO!"
			sub.TextColor3 = COR_PERFEITO
		else
			posicionarAlvo()
		end
	end)

	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt

		if elapsed < prepTime then
			sub.Text = "PREPARANDO..."
			return
		end

		local intoWindow = elapsed - prepTime
		if intoWindow >= hitWindow then
			HissatsuQTEWindow.Hide()
			return
		end

		-- barra de tempo: esvazia e esquenta pro vermelho no fim
		local resta = 1 - intoWindow / hitWindow
		tempoFill.Size = UDim2.new(resta, 0, 1, 0)
		tempoGrad.Offset = Vector2.new(-(1 - resta) * 0.6, 0)

		if done then return end

		if not targetShown then
			targetShown = true
			sub.Text = "CLIQUE NOS ALVOS"
			alvo.Visible = true
			posicionarAlvo()
		end

		-- anel externo pulsando e encolhendo com o tempo
		local pulso = 1.35 + 0.2 * math.sin(elapsed * 10)
		chamariz.Size = UDim2.fromScale(pulso, pulso)
		chamarizBorda.Transparency = 0.2 + 0.3 * (1 - resta)
		alvoBorda.Thickness = 3 + math.sin(elapsed * 10)
	end))
end

-- ============================================================
-- "TimingBar" — marcador indo e voltando; ESPAÇO/clique na faixa boa
-- ============================================================
local BAR_WIDTH = 300

local function showTimingBar(pulseName, params)
	clearGui()

	local emCutscene = params.EmCutscene == true
	local painel, sub = criarPainel(pulseName, "APERTE NA FAIXA VERDE", BAR_WIDTH + 40, 170, emCutscene)
	painel.Position = emCutscene and UDim2.new(0.8, 0, 0.5, 0) or UDim2.new(0.5, 0, 0.66, 0)

	local trilho = criarBarra(painel, UDim2.fromOffset(20, 62), BAR_WIDTH, 22)

	local perfectStart = math.clamp(tonumber(params.PerfectStart) or 0.4, 0, 1)
	local perfectEnd = math.clamp(tonumber(params.PerfectEnd) or 0.6, perfectStart, 1)
	local goodPadding = math.max(tonumber(params.GoodPadding) or 0.12, 0)
	local goodStart = math.max(perfectStart - goodPadding, 0)
	local goodEnd = math.min(perfectEnd + goodPadding, 1)

	local faixaBoa = Instance.new("Frame")
	faixaBoa.Name = "FaixaBoa"
	faixaBoa.BackgroundColor3 = COR_BOM
	faixaBoa.BackgroundTransparency = 0.35
	faixaBoa.BorderSizePixel = 0
	faixaBoa.Position = UDim2.new(goodStart, 0, 0, 0)
	faixaBoa.Size = UDim2.new(goodEnd - goodStart, 0, 1, 0)
	faixaBoa.ZIndex = 2
	faixaBoa.Parent = trilho
	canto(faixaBoa, UDim.new(0, 4))

	local faixaPerfeita = Instance.new("Frame")
	faixaPerfeita.Name = "FaixaPerfeita"
	faixaPerfeita.BackgroundColor3 = COR_PERFEITO
	faixaPerfeita.BackgroundTransparency = 0.05
	faixaPerfeita.BorderSizePixel = 0
	faixaPerfeita.Position = UDim2.new(perfectStart, 0, 0, 0)
	faixaPerfeita.Size = UDim2.new(perfectEnd - perfectStart, 0, 1, 0)
	faixaPerfeita.ZIndex = 2
	faixaPerfeita.Parent = trilho
	canto(faixaPerfeita, UDim.new(0, 4))
	local brilhoPerfeito = borda(faixaPerfeita, COR_PERFEITO, 2, 0.4)

	-- marcador: cápsula branca com halo
	local marcador = Instance.new("Frame")
	marcador.Name = "Marcador"
	marcador.AnchorPoint = Vector2.new(0.5, 0.5)
	marcador.BackgroundColor3 = Color3.new(1, 1, 1)
	marcador.BorderSizePixel = 0
	marcador.Size = UDim2.new(0, 8, 1, 14)
	marcador.Position = UDim2.new(0, 0, 0.5, 0)
	marcador.ZIndex = 5
	marcador.Parent = trilho
	canto(marcador, UDim.new(1, 0))
	borda(marcador, COR_FOGO_A, 2, 0.2)

	local requiredHits = math.max(tonumber(params.RequiredHits) or 5, 1)
	local marcarBolinhas = criarBolinhas(painel, UDim2.fromOffset(0, 98), requiredHits)

	-- tecla ESPAÇO (também é o botão de clique/toque)
	local linhaTecla = Instance.new("Frame")
	linhaTecla.BackgroundTransparency = 1
	linhaTecla.Position = UDim2.fromOffset(0, 118)
	linhaTecla.Size = UDim2.new(1, 0, 0, 44)
	linhaTecla.Parent = painel
	local layoutTecla = Instance.new("UIListLayout")
	layoutTecla.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layoutTecla.Parent = linhaTecla
	local teclaEspaco, acenderEspaco = criarTecla(linhaTecla, "ESPAÇO", 150)

	local duration = math.max(tonumber(params.Duration) or 1.2, 0.2)
	local sweepPeriod = math.max(tonumber(params.SweepPeriod) or 0.9, 0.1)
	local startedAt = os.clock()
	local hits = 0
	local resolved = false

	-- Mesma fórmula de ping-pong usada pelo servidor (PulseController.
	-- legacy.luau -> sweepFraction) — só visual aqui, o servidor decide
	-- de verdade se o clique contou.
	local function sweepFraction(elapsed)
		local cycle = sweepPeriod * 2
		local t = elapsed % cycle
		if t <= sweepPeriod then
			return t / sweepPeriod
		end
		return 1 - (t - sweepPeriod) / sweepPeriod
	end

	local function respond()
		if resolved then return end
		acenderEspaco()
		if onInputCallback then onInputCallback({}) end
		-- Feedback visual OTIMISTA (o servidor confirma de verdade): conta
		-- como acerto se o marcador estiver dentro da faixa agora mesmo.
		local fraction = sweepFraction(os.clock() - startedAt)
		if fraction >= goodStart and fraction <= goodEnd then
			local perfeito = fraction >= perfectStart and fraction <= perfectEnd
			hits = math.min(hits + 1, requiredHits)
			marcarBolinhas(hits, perfeito and COR_PERFEITO or COR_BOM)
			estouro(trilho, marcador.Position, 30, perfeito and COR_PERFEITO or COR_BOM)
			if hits >= requiredHits then
				resolved = true
				sub.Text = "DEFENDIDO!"
				sub.TextColor3 = COR_PERFEITO
			end
		else
			sub.Text = "FORA DA FAIXA!"
			sub.TextColor3 = COR_FOGO_C
			task.delay(0.35, function()
				if sub.Parent and not resolved then
					sub.Text = "APERTE NA FAIXA VERDE"
					sub.TextColor3 = COR_TEXTO_SUAVE
				end
			end)
		end
	end

	teclaEspaco.MouseButton1Click:Connect(respond)

	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if input.KeyCode == Enum.KeyCode.Space then
			respond()
		end
	end))

	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		local elapsed = os.clock() - startedAt
		if resolved or elapsed >= duration then
			HissatsuQTEWindow.Hide()
			return
		end
		local fraction = sweepFraction(elapsed)
		marcador.Position = UDim2.new(fraction, 0, 0.5, 0)
		-- a faixa perfeita "brilha" quando o marcador passa por ela
		local dentro = fraction >= perfectStart and fraction <= perfectEnd
		brilhoPerfeito.Transparency = dentro and 0 or 0.5
	end))
end

-- ============================================================
-- "MashAD" — alterna A/D até bater RequiredAlternations
-- ============================================================
local function showMashAD(pulseName, params)
	clearGui()

	local emCutscene = params.EmCutscene == true
	local painel, sub = criarPainel(pulseName, "ALTERNE A e D RÁPIDO!", 320, 170, emCutscene)
	painel.Position = emCutscene and UDim2.new(0.8, 0, 0.5, 0) or UDim2.new(0.5, 0, 0.66, 0)

	local _, fill = criarBarra(painel, UDim2.fromOffset(20, 62), 280, 20)

	local contador = rotulo(painel, "", 13, COR_TEXTO_SUAVE, FONTE_TEXTO)
	contador.Position = UDim2.fromOffset(0, 88)
	contador.Size = UDim2.new(1, 0, 0, 16)

	-- ⚠️ MOBILE: não tem teclado A/D no celular — as teclas desenhadas também
	-- são botões (em teclado dá pra ignorar e usar A/D normalmente).
	local linha = Instance.new("Frame")
	linha.BackgroundTransparency = 1
	linha.Position = UDim2.fromOffset(0, 112)
	linha.Size = UDim2.new(1, 0, 0, 44)
	linha.Parent = painel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 16)
	layout.Parent = linha
	local teclaA, acenderA = criarTecla(linha, "A", 110)
	local teclaD, acenderD = criarTecla(linha, "D", 110)

	local duration = math.max(tonumber(params.Duration) or 2, 0.2)
	local required = math.max(tonumber(params.RequiredAlternations) or 6, 1)
	local startedAt = os.clock()
	local hits = 0
	local lastKey = nil
	local resolved = false

	local function updateBar()
		TweenService:Create(fill, TweenInfo.new(0.08), { Size = UDim2.new(math.clamp(hits / required, 0, 1), 0, 1, 0) }):Play()
		contador.Text = ("%d / %d"):format(hits, required)
	end
	updateBar()

	local function registerPress(key)
		if resolved then return end
		if key == "A" then acenderA() else acenderD() end
		if key == lastKey then return end -- precisa alternar de verdade
		lastKey = key
		hits += 1
		updateBar()
		if onInputCallback then onInputCallback({ Key = key }) end
		if hits >= required then
			resolved = true
			sub.Text = "MÁXIMO!"
			sub.TextColor3 = COR_PERFEITO
		end
	end

	table.insert(activeConnections, UserInputService.InputBegan:Connect(function(input)
		local key = (input.KeyCode == Enum.KeyCode.A) and "A" or (input.KeyCode == Enum.KeyCode.D) and "D" or nil
		if not key then return end
		registerPress(key)
	end))
	teclaA.MouseButton1Down:Connect(function() registerPress("A") end)
	teclaD.MouseButton1Down:Connect(function() registerPress("D") end)

	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		if os.clock() - startedAt >= duration then
			HissatsuQTEWindow.Hide()
		end
	end))
end

-- ============================================================
-- "GKGuardArmed" — v7: a Hissatsu de goleiro não é mais um QTE na hora
-- de usar, só arma a guarda (ver PulseController.legacy.luau ->
-- startGKGuard) — aqui só um aviso pequeno no alto, sem travar nada,
-- enquanto o goleiro espera o chute colidir com a área.
-- ============================================================
local function showGKGuardArmed(pulseName, params)
	clearGui()

	local duration = math.max(tonumber(params.Duration) or 5, 0.1)

	local faixa = Instance.new("Frame")
	faixa.Name = "GuardaArmada"
	faixa.AnchorPoint = Vector2.new(0.5, 0)
	faixa.Position = UDim2.new(0.5, 0, 0.06, 0)
	faixa.Size = UDim2.fromOffset(330, 40)
	faixa.BackgroundColor3 = COR_PAINEL
	faixa.BackgroundTransparency = 0.35
	faixa.BorderSizePixel = 0
	faixa.Parent = screenGui
	canto(faixa, UDim.new(1, 0))
	borda(faixa, COR_PERFEITO, 1.5, 0.4)

	-- (v103: sem emoji — pedido do usuário)
	local label = rotulo(faixa, ("%s ARMADA — espera o chute"):format(maiusculas(pulseName or "Guarda")), 14, COR_TEXTO, FONTE_TITULO)
	label.Size = UDim2.new(1, 0, 1, -6)

	local _, fill = criarBarra(faixa, UDim2.new(0, 16, 1, -7), 298, 4)
	fill.Size = UDim2.new(1, 0, 1, 0)

	local startedAt = os.clock()
	table.insert(activeConnections, RunService.RenderStepped:Connect(function()
		local passou = os.clock() - startedAt
		if passou >= duration then
			HissatsuQTEWindow.Hide()
			return
		end
		fill.Size = UDim2.new(1 - passou / duration, 0, 1, 0)
	end))
end

-- ============================================================
-- Entrada pública: HissatsuInput.local.luau chama isso quando o servidor
-- manda Remotes.PulseQTEPrompt.
-- ============================================================
function HissatsuQTEWindow.Show(slot, pulseName, params, inputCallback)
	ensureGui()
	HissatsuQTEWindow.Hide()

	currentSlot = slot
	onInputCallback = inputCallback
	screenGui.Enabled = true
	aplicarTema(temaDaTecnica(pulseName)) -- ⚠️ v103: cores da própria técnica

	if params.Kind == "Tap" then
		showTap(pulseName, params)
	elseif params.Kind == "TimingBar" then
		showTimingBar(pulseName, params)
	elseif params.Kind == "MashAD" then
		showMashAD(pulseName, params)
	elseif params.Kind == "GKGuardArmed" then
		showGKGuardArmed(pulseName, params)
	else
		HissatsuQTEWindow.Hide()
	end
end

return HissatsuQTEWindow
