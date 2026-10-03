--[[
	FlowCena (ModuleScript) — ⚠️ v110
	LOCAL: ReplicatedStorage (IGUAL nos dois places: Game e Lobby)

	PEDIDO: "cutscenes de flow igual as dos animes (o flow do Isagi, do
	Bachira...)... incluir as cutscenes na loja pra pessoa poder escolher".

	A cena de ativação do Flow (faixa estilo anime com o close no rosto, o
	olho aceso com o rastro de luz e o motivo de cada personagem). A partida
	toca quando o Flow ativa (CosmeticosClient); a Loja do Lobby toca no
	"VER CENA" de cada Flow, pra escolher antes de comprar.
	Só roda no cliente. Não congela nada.

	FlowCena.Tocar(player, item)   — item = Cosmeticos.Item("Flow_...")
	FlowCena.OlhosPos(head)        — posição dos olhos (espaço da cabeça)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

-- ⚠️ v110: string.upper não põe acento em maiúscula ("Fúria" virava "FúRIA").
-- Converte também as letras acentuadas (UTF-8 à..þ → À..Þ).
local function maiusculas(s)
	s = string.upper(tostring(s))
	return (s:gsub("\195([\160-\190])", function(c)
		local b = string.byte(c)
		if b ~= 183 then return "\195" .. string.char(b - 32) end
	end))
end

local FlowCena = {}

local function tween(obj, tempo, props, estilo, direcao)
	local t = TweenService:Create(obj, TweenInfo.new(tempo, estilo or Enum.EasingStyle.Quad, direcao or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function nomeDe(player)
	local n = player:GetAttribute("NomePersonagem")
	if typeof(n) == "string" and n ~= "" then return n end
	return player.DisplayName
end

local function olhosPos(head)
	local s = head.Size
	return {
		Vector3.new(-s.X * 0.11, 0, -s.Z * 0.5),
		Vector3.new(s.X * 0.11, 0, -s.Z * 0.5),
	}
end
FlowCena.OlhosPos = olhosPos

local COR_PAINEL = Color3.fromRGB(13, 15, 22)

local function frame(pai, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	f.Parent = pai
	return f
end
local function redondo(f, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = raio or UDim.new(1, 0)
	c.Parent = f
	return c
end

-- motivos 2D atrás do rosto (camada = Frame que cobre a faixa)
local MOTIVOS = {}

MOTIVOS.Pecas = function(camada, tema)
	-- Metavisão do Isagi: as peças de quebra-cabeça voam e se encaixam
	for i = 0, 17 do
		local col, lin = i % 6, math.floor(i / 6)
		local alvo = UDim2.new(0.52 + col * 0.075 + (math.random() - 0.5) * 0.01, 0, 0.1 + lin * 0.28 + (math.random() - 0.5) * 0.03, 0)
		local peca = frame(camada, {
			Size = UDim2.fromScale(0.066, 0.25), AnchorPoint = Vector2.new(0.5, 0), BackgroundColor3 = tema.Cor,
			BackgroundTransparency = 0.88, Position = UDim2.new(math.random(), 0, math.random() * 2 - 0.5, 0), Rotation = math.random(-90, 90),
		})
		redondo(peca, UDim.new(0, 6))
		local s = Instance.new("UIStroke")
		s.Color = tema.Cor2
		s.Thickness = 1.5
		s.Transparency = 0.55
		s.Parent = peca
		-- o "encaixe" de quebra-cabeça: um dente redondo em um dos lados
		local dente = frame(peca, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.34, 0.2),
			Position = (i % 2 == 0) and UDim2.fromScale(1, 0.5) or UDim2.fromScale(0.5, 0), BackgroundColor3 = tema.Cor, BackgroundTransparency = 0.88 })
		redondo(dente)
		task.delay(0.1 + i * 0.03, function()
			tween(peca, 0.35, { Position = alvo, Rotation = 0 }, Enum.EasingStyle.Back)
		end)
	end
end

MOTIVOS.Monstro = function(camada, tema)
	-- o "monstro" do Bachira: a sombra enorme atrás dele, contornada de amarelo,
	-- com chifres, olhos amendoados de pupila em fenda e o sorriso de dentes
	-- (⚠️ v110: conferido na tela — sem contorno a sombra sumia no fundo preto)
	local ESCURO = Color3.fromRGB(30, 22, 10)
	local cx = 0.575
	local sombra = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx, 0.6), Size = UDim2.fromScale(0, 0),
		BackgroundColor3 = ESCURO })
	Instance.new("UIAspectRatioConstraint").Parent = sombra
	redondo(sombra)
	local borda = Instance.new("UIStroke")
	borda.Color = tema.Cor
	borda.Thickness = 3
	borda.Transparency = 0.3
	borda.Parent = sombra
	tween(sombra, 0.4, { Size = UDim2.fromScale(0.3, 1.25) }, Enum.EasingStyle.Back)
	for _, lado in ipairs({ -1, 1 }) do
		local chifre = frame(camada, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(cx + lado * 0.055, 0.34), Size = UDim2.new(0, 22, 0, 0),
			BackgroundColor3 = ESCURO, Rotation = lado * 28 })
		local s = Instance.new("UIStroke")
		s.Color = tema.Cor
		s.Thickness = 2
		s.Transparency = 0.3
		s.Parent = chifre
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0) })
		g.Parent = chifre
		tween(chifre, 0.45, { Size = UDim2.new(0, 22, 0.42, 0) }, Enum.EasingStyle.Back)
		-- olho amendoado com pupila em fenda
		local olho = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx + lado * 0.03, 0.46), Size = UDim2.fromOffset(52, 0),
			BackgroundColor3 = tema.Cor, Rotation = lado * -16, ZIndex = 3 })
		redondo(olho)
		local brilho = Instance.new("UIStroke")
		brilho.Color = Color3.fromRGB(255, 250, 200)
		brilho.Thickness = 1.5
		brilho.Parent = olho
		local pupila = frame(olho, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 5, 1, -2),
			BackgroundColor3 = Color3.fromRGB(20, 10, 0), ZIndex = 4 })
		redondo(pupila)
		task.delay(0.35, function() tween(olho, 0.18, { Size = UDim2.fromOffset(52, 16) }) end)
	end
	-- sorriso: fileira de dentes pontudos
	for i = 0, 7 do
		local dente = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(cx - 0.035 + i * 0.01, 0.62 + math.abs(i - 3.5) * -0.012),
			Size = UDim2.fromOffset(0, 0), BackgroundColor3 = Color3.fromRGB(250, 245, 225), Rotation = 45, ZIndex = 3 })
		task.delay(0.45 + i * 0.02, function() tween(dente, 0.12, { Size = UDim2.fromOffset(10, 10) }) end)
	end
end

local function particulas2D(camada, cor, cor2, n, tam, direcao, giro)
	for i = 1, n do
		local p = frame(camada, {
			AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(tam.X, tam.Y), BackgroundColor3 = (i % 2 == 0) and cor or cor2,
			BackgroundTransparency = (giro == 0) and 0.7 or 0.2, Rotation = (giro == 0) and 0 or math.random(0, 360),
			Position = UDim2.fromScale(direcao == "baixo" and math.random() or 1.1, direcao == "baixo" and -0.1 or math.random()),
		})
		redondo(p)
		local destino = direcao == "baixo" and UDim2.fromScale(math.random(), 1.1) or UDim2.fromScale(-0.1, math.random())
		task.delay(math.random() * 0.6, function()
			tween(p, 1.5 + math.random() * 0.9, { Position = destino, Rotation = p.Rotation + (giro or 180) }, Enum.EasingStyle.Linear)
		end)
	end
end

MOTIVOS.Penas = function(camada, tema)
	-- Nagi: penas brancas caindo devagar e balançando (⚠️ v110: conferido na
	-- tela — as "pílulas" pareciam palitos; agora tem formato e haste)
	for i = 1, 12 do
		local x = 0.45 + math.random() * 0.55
		local pena = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, -0.2 - math.random() * 0.4),
			Size = UDim2.fromOffset(16, 52), BackgroundColor3 = tema.Cor, BackgroundTransparency = 0.1, Rotation = math.random(-40, 40) })
		redondo(pena, UDim.new(0.5, 0))
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 0.9) })
		g.Parent = pena
		frame(pena, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.05), Size = UDim2.new(0, 2, 1.05, 0),
			BackgroundColor3 = tema.Cor2 })
		task.delay(math.random() * 0.5, function()
			tween(pena, 1.8 + math.random() * 0.8, { Position = UDim2.fromScale(x + (math.random() - 0.5) * 0.12, 1.25),
				Rotation = pena.Rotation + math.random(-70, 70) }, Enum.EasingStyle.Sine)
		end)
	end
end
MOTIVOS.Petalas = function(camada, tema)
	-- a pantera (Chigiri): pétalas vermelhas + três marcas de garra rasgando
	particulas2D(camada, tema.Cor, tema.Cor2, 22, Vector2.new(16, 24), "lado", 360)
	for i = 0, 2 do
		local garra = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.56 + i * 0.03, 0.5 + i * 0.04),
			Size = UDim2.new(0, 7, 0, 0), BackgroundColor3 = tema.Cor, Rotation = 35 })
		redondo(garra)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = garra
		task.delay(0.2 + i * 0.07, function() tween(garra, 0.18, { Size = UDim2.new(0, 7, 0.9, 0) }, Enum.EasingStyle.Quart) end)
	end
end
-- rosa desenhada com camadas de "pétalas" (quadrados arredondados girados)
local function desenharRosa(camada, pos, cor, cor2, tamanho)
	local camadas = { { 1, 0 }, { 0.8, 22 }, { 0.6, 45 }, { 0.42, 67 }, { 0.26, 10 } }
	for i, c in ipairs(camadas) do
		local petala = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(0, 0),
			BackgroundColor3 = (i % 2 == 1) and cor or cor2, Rotation = c[2], ZIndex = 2 + i })
		redondo(petala, UDim.new(0.14, 0))
		local s = Instance.new("UIStroke")
		s.Color = cor:Lerp(Color3.new(0, 0, 0), 0.55)
		s.Thickness = 2
		s.Transparency = 0.1
		s.Parent = petala
		task.delay(0.12 + i * 0.05, function()
			tween(petala, 0.35, { Size = UDim2.fromOffset(tamanho * c[1], tamanho * c[1]), Rotation = c[2] + 30 }, Enum.EasingStyle.Back)
		end)
	end
	-- folhas
	for _, lado in ipairs({ -1, 1 }) do
		local folha = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = pos + UDim2.fromOffset(lado * tamanho * 0.55, tamanho * 0.45),
			Size = UDim2.fromOffset(0, 0), BackgroundColor3 = Color3.fromRGB(40, 110, 70), Rotation = lado * 35, ZIndex = 2 })
		redondo(folha)
		task.delay(0.4, function() tween(folha, 0.25, { Size = UDim2.fromOffset(tamanho * 0.5, tamanho * 0.2) }) end)
	end
end

MOTIVOS.Rosas = function(camada, tema)
	-- o prodígio (Sae): rosa vermelha aberta + pétalas voando
	particulas2D(camada, tema.Cor, tema.Cor2, 22, Vector2.new(18, 26), "lado", 540)
	desenharRosa(camada, UDim2.fromScale(0.58, 0.45), tema.Cor, tema.Cor2, 120)
end

MOTIVOS.Chamas = function(camada, tema)
	for i = 1, 16 do
		local ch = frame(camada, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.45 + i * 0.035, 1.05), Size = UDim2.fromScale(0.03, 0),
			BackgroundColor3 = tema.Cor })
		redondo(ch)
		local g = Instance.new("UIGradient")
		g.Rotation = -90
		g.Color = ColorSequence.new(tema.Cor, tema.Cor2)
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ch
		task.delay(math.random() * 0.3, function()
			tween(ch, 0.5, { Size = UDim2.fromScale(0.045, 0.6 + math.random() * 0.5) }, Enum.EasingStyle.Back)
		end)
	end
end

MOTIVOS.Espelhos = function(camada, tema)
	-- o camaleão (Reo): cacos de espelho que refletem e piscam
	for i = 1, 10 do
		local caco = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromScale(0.06, 0.2), Rotation = 45,
			BackgroundColor3 = tema.Cor2, BackgroundTransparency = 0.6,
			Position = UDim2.fromScale(0.5 + math.random() * 0.5, math.random()) })
		local s = Instance.new("UIStroke")
		s.Color = tema.Cor
		s.Thickness = 2
		s.Parent = caco
		task.delay(i * 0.06, function()
			tween(caco, 0.12, { BackgroundTransparency = 0.05 })
			task.wait(0.12)
			tween(caco, 0.4, { BackgroundTransparency = 0.7, Rotation = 45 + math.random(-30, 30) })
		end)
	end
end

MOTIVOS.Fantasma = function(camada, tema)
	-- névoa baixa passando (as imagens residuais são criadas na própria cena)
	particulas2D(camada, tema.Cor, tema.Cor2, 8, Vector2.new(140, 10), "lado", 0)
end

-- ⚠️ v110 (conferido na tela): no Roblox a moldura gira em volta do CENTRO
-- dela, não do AnchorPoint — então cada raio é uma barra centrada no ponto da
-- explosão (vira dois raios opostos). Antes os raios giravam fora da faixa.
local function raiosDoCentro(camada, centro, n, cores, espessura, tempo, transpFinal)
	for i = 0, n - 1 do
		local r = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = centro, Size = UDim2.new(0, espessura, 0, 0),
			BackgroundColor3 = cores[i % #cores + 1], BackgroundTransparency = 0.25, Rotation = i * (180 / n) })
		tween(r, tempo, { Size = UDim2.new(0, espessura, 2.6, 0), BackgroundTransparency = transpFinal or 0.35 })
	end
end

MOTIVOS.Coroa = function(camada, tema)
	-- o rei (Barou): raios dourados e a coroa flutuando ao lado dele
	raiosDoCentro(camada, UDim2.fromScale(0.64, 0.5), 10, { tema.Cor }, 6, 0.5)
	local coroa = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.555, -0.3), Size = UDim2.fromOffset(86, 34),
		BackgroundColor3 = tema.Cor, ZIndex = 4 })
	for i = -1, 1 do
		local ponta = frame(coroa, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5 + i * 0.36, 0, 0, 0), Size = UDim2.fromOffset(24, 24),
			BackgroundColor3 = tema.Cor, Rotation = 45, ZIndex = 4 })
		local joia = frame(ponta, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.fromRGB(220, 40, 60), ZIndex = 5 })
		redondo(joia)
	end
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(255, 250, 210)
	s.Thickness = 2
	s.Parent = coroa
	tween(coroa, 0.5, { Position = UDim2.fromScale(0.555, 0.34) }, Enum.EasingStyle.Bounce)
end

MOTIVOS.Explosao = function(camada, tema)
	-- Big Bang (Shidou): núcleo pulsando + rajadas rosa/amarelas em ondas a cena
	-- inteira (⚠️ v110: conferido na tela — 3 ondas que sumiam deixavam vazio)
	local centro = UDim2.fromScale(0.62, 0.5)
	local nucleo = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = centro, Size = UDim2.fromOffset(0, 0), BackgroundColor3 = tema.Cor2 })
	redondo(nucleo)
	local aro = Instance.new("UIStroke")
	aro.Color = tema.Cor
	aro.Thickness = 6
	aro.Parent = nucleo
	tween(nucleo, 0.3, { Size = UDim2.fromOffset(70, 70) }, Enum.EasingStyle.Back)
	for onda2 = 0, 6 do
		task.delay(onda2 * 0.25, function()
			if not camada.Parent then return end
			raiosDoCentro(camada, centro, 8, { tema.Cor, tema.Cor2 }, 5 + (onda2 % 3) * 2, 0.4, 0.75)
			local anel = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = centro, Size = UDim2.fromOffset(40, 40), BackgroundTransparency = 1 })
			redondo(anel)
			local s = Instance.new("UIStroke")
			s.Color = onda2 % 2 == 0 and tema.Cor or tema.Cor2
			s.Thickness = 4
			s.Parent = anel
			tween(anel, 0.5, { Size = UDim2.fromOffset(420, 420) })
			tween(s, 0.5, { Transparency = 1 })
		end)
	end
end

MOTIVOS.Agua = function(camada, tema)
	-- o destruidor (Rin): mar escuro atrás dele, ondas que passam e ondulações
	-- (⚠️ v110: conferido na tela — listras retas atrás do texto viravam
	-- "bandeira"; agora o mar fica só do lado dele, translúcido e ondulando)
	local mar = frame(camada, { Position = UDim2.fromScale(0.48, 0), Size = UDim2.fromScale(0.52, 1), BackgroundColor3 = tema.Cor, BackgroundTransparency = 0.82 })
	local gm = Instance.new("UIGradient")
	gm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0) })
	gm.Parent = mar
	for i = 1, 7 do
		local y = 0.1 + i * 0.11
		local onda = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1.15, y), Size = UDim2.new(0.22, 0, 0, 3 + (i % 3) * 2),
			BackgroundColor3 = tema.Cor:Lerp(Color3.new(1, 1, 1), 0.3), BackgroundTransparency = 0.25 })
		redondo(onda)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = onda
		task.delay(i * 0.08, function()
			tween(onda, 1.6, { Position = UDim2.fromScale(0.5, y + math.sin(i) * 0.04) }, Enum.EasingStyle.Sine)
		end)
	end
	for i = 0, 3 do
		task.delay(i * 0.35, function()
			if not camada.Parent then return end
			local anel = frame(camada, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.6, 0.55), Size = UDim2.fromOffset(20, 8), BackgroundTransparency = 1 })
			redondo(anel)
			local s = Instance.new("UIStroke")
			s.Color = tema.Cor
			s.Thickness = 3
			s.Parent = anel
			tween(anel, 0.9, { Size = UDim2.fromOffset(360, 110) })
			tween(s, 0.9, { Transparency = 1 })
		end)
	end
end

MOTIVOS.RosaAzul = function(camada, tema)
	-- o imperador (Kaiser): a rosa azul + pétalas azuis voando
	-- (⚠️ v110: conferido na tela — os "espinhos" retos viravam rabisco)
	particulas2D(camada, tema.Cor, tema.Cor2, 22, Vector2.new(18, 26), "lado", 540)
	desenharRosa(camada, UDim2.fromScale(0.58, 0.45), tema.Cor, tema.Cor2, 120)
end

local cenaAtual = nil

local function cenaDoFlow(player, item, localPlayer, playerGui)
	local tema = item.Tema
	if cenaAtual then cenaAtual:Destroy() end
	local gui = Instance.new("ScreenGui")
	gui.Name = "CenaFlow"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- ⚠️ v110: senão o motivo (peças etc.) ficava atrás do fundo da faixa
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	cenaAtual = gui

	-- flash na cor do Flow
	local flash = frame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = tema.Cor, BackgroundTransparency = 0.25, ZIndex = 1 })
	tween(flash, 0.35, { BackgroundTransparency = 1 })

	-- a faixa (inclinada, entra pela direita)
	-- ⚠️ v110 (conferido na tela): a faixa NÃO pode ser girada — no Roblox uma
	-- moldura girada não corta o que tem dentro, e o rosto vazava pra fora dela.
	-- A inclinação de anime vem das listras diagonais aqui dentro.
	local faixa = frame(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(1.6, 0.5), Size = UDim2.fromScale(1, 0.46),
		BackgroundColor3 = COR_PAINEL, ClipsDescendants = true, ZIndex = 2,
	})
	for i, x in ipairs({ 0.46, 0.5, 0.97 }) do
		frame(faixa, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(x, 0.5), Size = UDim2.new(0, i == 2 and 4 or 14, 1.6, 0),
			BackgroundColor3 = tema.Cor, BackgroundTransparency = i == 2 and 0.2 or 0.6, Rotation = 18, ZIndex = 5 })
	end
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(COR_PAINEL, tema.Cor:Lerp(COR_PAINEL, 0.55))
	grad.Parent = faixa
	for _, y in ipairs({ 0, 1 }) do
		frame(faixa, { AnchorPoint = Vector2.new(0, y), Position = UDim2.fromScale(0, y), Size = UDim2.new(1, 0, 0, 5), BackgroundColor3 = tema.Cor, ZIndex = 6 })
	end
	local camada = frame(faixa, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 2 })

	-- linhas de velocidade
	for i = 1, 14 do
		local linha = frame(faixa, { Position = UDim2.fromScale(1 + math.random(), math.random()), Size = UDim2.new(0.25 + math.random() * 0.3, 0, 0, math.random(1, 3)),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.5, ZIndex = 3 })
		tween(linha, 0.5 + math.random() * 0.4, { Position = UDim2.fromScale(-0.6, linha.Position.Y.Scale) }, Enum.EasingStyle.Linear)
	end

	-- o close no rosto (ViewportFrame com uma cópia do personagem)
	local vp = Instance.new("ViewportFrame")
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.74, 0.5)
	vp.Size = UDim2.fromScale(0.46, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.fromRGB(150, 150, 160)
	vp.LightColor = Color3.new(1, 1, 1)
	vp.LightDirection = Vector3.new(-0.4, -0.6, -1)
	vp.ZIndex = 4
	vp.Parent = faixa
	local mundo = Instance.new("WorldModel")
	mundo.Parent = vp
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.Parent = vp
	vp.CurrentCamera = camera
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if character and head then
		local arquivavel = character.Archivable
		character.Archivable = true
		local ok, copia = pcall(function() return character:Clone() end)
		character.Archivable = arquivavel
		if ok and copia then
			for _, d in ipairs(copia:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Sound") then
					d:Destroy()
				end
			end
			copia.Parent = mundo
			local cHead = copia:FindFirstChild("Head")
			if cHead then
				-- ⚠️ v110 (conferido na tela): o olho aceso e o rastro de luz são
				-- desenhados em 2D POR CIMA do rosto (projetando a posição 3D do olho
				-- na câmera da ViewportFrame) — em 3D o cabelo do avatar escondia o
				-- olho, e peça Neon não brilha dentro de ViewportFrame.
				local olho = cHead.CFrame:PointToWorldSpace(olhosPos(cHead)[2])
				local centroCabeca = cHead.Position
				local frente = cHead.CFrame.LookVector
				local direita = cHead.CFrame.RightVector
				-- três-quartos, perto: a cabeça grande no quadro
				local alvo = cHead.Position - Vector3.new(0, cHead.Size.Y * 0.1, 0)
				local de = alvo + frente * 3.6 + direita * 1.1 + Vector3.new(0, 0.25, 0)
				local ate = alvo + frente * 2.7 + direita * 0.8 + Vector3.new(0, 0.1, 0)
				camera.CFrame = CFrame.lookAt(de, alvo)

				local brilhoOlho = frame(faixa, { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12),
					BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 6 })
				redondo(brilhoOlho)
				local halo = Instance.new("UIStroke")
				halo.Color = tema.Cor
				halo.Thickness = 4
				halo.Transparency = 0.2
				halo.Parent = brilhoOlho
				local rastro = frame(faixa, { AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.fromOffset(0, 5),
					BackgroundColor3 = tema.Cor2:Lerp(Color3.new(1, 1, 1), 0.5), ZIndex = 5 })
				redondo(rastro)
				local gradRastro = Instance.new("UIGradient")
				gradRastro.Color = ColorSequence.new(Color3.new(1, 1, 1), tema.Cor)
				gradRastro.Transparency = NumberSequence.new(0, 1)
				gradRastro.Parent = rastro

				-- projeta um ponto 3D na área da ViewportFrame (em pixels dentro da faixa)
				local function projetar(p)
					local rel = camera.CFrame:PointToObjectSpace(p)
					if rel.Z >= -0.01 then return nil end
					local tamVp = vp.AbsoluteSize
					if tamVp.Y <= 0 then return nil end
					local tanY = math.tan(math.rad(camera.FieldOfView) / 2)
					local aspecto = tamVp.X / tamVp.Y
					local x = (rel.X / -rel.Z) / (tanY * aspecto)
					local y = (rel.Y / -rel.Z) / tanY
					local origem = vp.AbsolutePosition - faixa.AbsolutePosition
					return Vector2.new(origem.X + (0.5 + x / 2) * tamVp.X, origem.Y + (0.5 - y / 2) * tamVp.Y)
				end

				-- ⚠️ v110 — AIKU (Fantasma): imagens residuais do personagem atrás dele
				-- (cópias translúcidas deslocadas), a "defesa que aparece em todo lugar"
				local fantasmas = {}
				if tema.Motivo == "Fantasma" then
					for i, info in ipairs({ { -0.1, 0.55 }, { -0.2, 0.75 } }) do
						local vpF = vp:Clone()
						for _, filho in ipairs(vpF:GetChildren()) do filho:Destroy() end
						vpF.Position = vp.Position + UDim2.fromScale(info[1], 0)
						vpF.ImageTransparency = info[2]
						vpF.ImageColor3 = tema.Cor:Lerp(Color3.new(1, 1, 1), 0.4)
						vpF.ZIndex = 3
						vpF.Parent = faixa
						local mundoF = Instance.new("WorldModel")
						mundoF.Parent = vpF
						copia:Clone().Parent = mundoF
						local camF = Instance.new("Camera")
						camF.FieldOfView = camera.FieldOfView
						camF.Parent = vpF
						vpF.CurrentCamera = camF
						fantasmas[i] = camF
					end
				end

				local t0 = os.clock()
				local conexao
				conexao = RunService.RenderStepped:Connect(function()
					local t = os.clock() - t0
					if not vp.Parent then conexao:Disconnect() return end
					local a = math.clamp(t / 1.3, 0, 1)
					a = 1 - (1 - a) ^ 3
					camera.CFrame = CFrame.lookAt(de:Lerp(ate, a), alvo)
					for _, camF in ipairs(fantasmas) do camF.CFrame = camera.CFrame end
					local pOlho, pCabeca = projetar(olho), projetar(centroCabeca)
					if pOlho and pCabeca then
						brilhoOlho.Position = UDim2.fromOffset(pOlho.X, pOlho.Y)
						local acende = math.clamp((t - 0.15) / 0.2, 0, 1)
						brilhoOlho.BackgroundTransparency = 1 - acende
						halo.Transparency = 1 - acende * 0.8
						-- o rastro sai do olho pra FORA do rosto (lado oposto ao centro da cabeça)
						local lado = (pOlho.X >= pCabeca.X) and 1 or -1
						local comp = math.clamp((t - 0.3) / 0.45, 0, 1) * vp.AbsoluteSize.X * 0.45
						-- (girar 180° no Roblox não troca o lado de onde o traço sai: o
						-- lado é o AnchorPoint; o giro é só a inclinação)
						rastro.AnchorPoint = Vector2.new(lado > 0 and 0 or 1, 0.5)
						rastro.Position = UDim2.fromOffset(pOlho.X, pOlho.Y)
						rastro.Size = UDim2.fromOffset(comp, 5)
						rastro.Rotation = lado > 0 and -6 or 6
						gradRastro.Rotation = lado > 0 and 0 or 180
					end
				end)
			end
		end
	end

	local motivo = MOTIVOS[tema.Motivo]
	if motivo then pcall(motivo, camada, tema) end

	-- textos
	local flowTxt = Instance.new("TextLabel")
	flowTxt.BackgroundTransparency = 1
	flowTxt.AnchorPoint = Vector2.new(0, 0.5)
	flowTxt.Position = UDim2.fromScale(0.16, 0.4)
	flowTxt.Size = UDim2.fromScale(0.4, 0.42)
	flowTxt.Font = Enum.Font.GothamBlack
	flowTxt.Text = "FLOW"
	flowTxt.TextScaled = true
	flowTxt.TextColor3 = Color3.new(1, 1, 1)
	flowTxt.TextXAlignment = Enum.TextXAlignment.Left
	flowTxt.ZIndex = 7
	flowTxt.Parent = faixa
	local st = Instance.new("UIStroke")
	st.Color = tema.Cor
	st.Thickness = 3
	st.Parent = flowTxt
	local nomeTxt = Instance.new("TextLabel")
	nomeTxt.BackgroundTransparency = 1
	nomeTxt.AnchorPoint = Vector2.new(0, 0)
	nomeTxt.Position = UDim2.fromScale(0.165, 0.62)
	nomeTxt.Size = UDim2.fromScale(0.4, 0.13)
	nomeTxt.Font = Enum.Font.GothamBlack
	nomeTxt.TextScaled = true
	nomeTxt.Text = maiusculas(nomeDe(player)) .. "  ·  " .. maiusculas(item.Nome)
	nomeTxt.TextColor3 = tema.Cor:Lerp(Color3.new(1, 1, 1), 0.35) -- ⚠️ v110: a Cor2 de alguns Flows é escura e apagava o nome
	nomeTxt.TextXAlignment = Enum.TextXAlignment.Left
	nomeTxt.ZIndex = 7
	nomeTxt.Parent = faixa
	local descTxt = nomeTxt:Clone()
	descTxt.Position = UDim2.fromScale(0.165, 0.77)
	descTxt.Size = UDim2.fromScale(0.36, 0.08)
	descTxt.Font = Enum.Font.GothamMedium
	descTxt.Text = item.Descricao or ""
	descTxt.TextColor3 = Color3.fromRGB(190, 197, 212)
	descTxt.Parent = faixa

	-- correção de cor rápida (o "mundo" satura quando entra no Flow)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.4
	cc.Contrast = 0.2
	cc.TintColor = tema.Cor:Lerp(Color3.new(1, 1, 1), 0.7)
	cc.Parent = Lighting
	tween(cc, 1.6, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
	Debris:AddItem(cc, 1.7)

	tween(faixa, 0.22, { Position = UDim2.fromScale(0.5, 0.5) }, Enum.EasingStyle.Quart)
	-- depuração: LocalPlayer "FlowCenaSegurar" = segundos a mais parado (pra tirar print)
	local segurar = localPlayer:GetAttribute("FlowCenaSegurar")
	segurar = typeof(segurar) == "number" and segurar or 0
	task.delay(1.45 + segurar, function()
		if faixa.Parent then
			tween(faixa, 0.25, { Position = UDim2.fromScale(-0.7, 0.5) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		end
	end)
	task.delay(1.8 + segurar, function()
		gui:Destroy()
		if cenaAtual == gui then cenaAtual = nil end
	end)
end

function FlowCena.Tocar(player, item)
	local localPlayer = Players.LocalPlayer
	local playerGui = localPlayer and localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui or not item or not item.Tema then return end
	local ok, erro = pcall(cenaDoFlow, player, item, localPlayer, playerGui)
	if not ok then warn("[FlowCena] " .. tostring(erro)) end
end

return FlowCena
