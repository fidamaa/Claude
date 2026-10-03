--[[
	EmoteWheel (ModuleScript) — ⚠️ v117
	LOCAL: ReplicatedStorage (IGUAL nos dois places: Game e Lobby — Roblox não tem
	require entre places; mexeu num, copie pro outro)

	PEDIDO: "faça uma roda de emotes pra trocar entre eles e selecionar na loja, uma
	roda com até 6 espaços."

	A roda é a tela que abre com a tecla G (ou o botão EMOTE no celular): 6 casas em
	círculo, cada uma mostrando o emote que o jogador colocou ali na Eleven Store
	(atributos "Cosm_EmoteSlot1".."Cosm_EmoteSlot6"). Escolhe clicando, tocando ou
	apertando 1-6; G de novo / Esc / clicar fora fecha. A casa 1 também é a
	comemoração do gol (marcada "GOL").

	Uso (cada place cria a sua e liga o G):
	  local Roda = EmoteWheel.Criar({
	      Jogador = Players.LocalPlayer, Cosmeticos = Cosmeticos,
	      AoEscolher = function(indice) ... end,   -- 1..6
	  })
	  Roda.Alternar() / Roda.Abrir() / Roda.Fechar() / Roda.EstaAberto()
]]

local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local EmoteWheel = {}

local COR_CARTAO = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT = Color3.fromRGB(27, 31, 43)
local COR_BORDA = Color3.fromRGB(44, 50, 68)
local COR_ACENTO = Color3.fromRGB(76, 156, 255)
local COR_TEXTO = Color3.fromRGB(238, 241, 248)
local COR_FRACO = Color3.fromRGB(120, 128, 148)
local COR_OURO = Color3.fromRGB(255, 200, 70)

local COR_RARIDADE = {
	Common = Color3.fromRGB(190, 198, 215), Rare = Color3.fromRGB(110, 175, 255), Epic = Color3.fromRGB(190, 120, 255),
	Legendary = Color3.fromRGB(255, 175, 60), Mythic = Color3.fromRGB(255, 90, 110),
}

local RAIO = 150
local CASA = 100

local function cantos(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
	return c
end

function EmoteWheel.Criar(config)
	local jogador = config.Jogador
	local Cosmeticos = config.Cosmeticos
	local aoEscolher = config.AoEscolher
	local total = Cosmeticos.RODA_TAMANHO or 6

	local gui = Instance.new("ScreenGui")
	gui.Name = "RodaDeEmotes"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 40
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = jogador:WaitForChild("PlayerGui")

	local fundo = Instance.new("TextButton")
	fundo.Size = UDim2.fromScale(1, 1)
	fundo.BackgroundColor3 = Color3.new(0, 0, 0)
	fundo.BackgroundTransparency = 0.55
	fundo.BorderSizePixel = 0
	fundo.Text = ""
	fundo.AutoButtonColor = false
	fundo.Parent = gui

	local raiz = Instance.new("Frame")
	raiz.Name = "Raiz"
	raiz.AnchorPoint = Vector2.new(0.5, 0.5)
	raiz.Position = UDim2.fromScale(0.5, 0.5)
	raiz.Size = UDim2.fromOffset(RAIO * 2 + CASA + 20, RAIO * 2 + CASA + 20)
	raiz.BackgroundTransparency = 1
	raiz.Parent = gui
	local escala = Instance.new("UIScale")
	escala.Parent = raiz
	local function ajustar()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local v = cam.ViewportSize
		escala.Scale = math.clamp(math.min(v.X / (raiz.AbsoluteSize.X + 40), v.Y / (raiz.AbsoluteSize.Y + 40)), 0.5, 1)
	end
	ajustar()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustar) end

	-- miolo
	local miolo = Instance.new("Frame")
	miolo.AnchorPoint = Vector2.new(0.5, 0.5)
	miolo.Position = UDim2.fromScale(0.5, 0.5)
	miolo.Size = UDim2.fromOffset(104, 104)
	miolo.BackgroundColor3 = COR_CARTAO
	miolo.BorderSizePixel = 0
	miolo.Parent = raiz
	cantos(miolo, 52)
	local mioloBorda = Instance.new("UIStroke")
	mioloBorda.Color = COR_ACENTO
	mioloBorda.Transparency = 0.4
	mioloBorda.Thickness = 2
	mioloBorda.Parent = miolo
	local tituloMiolo = Instance.new("TextLabel")
	tituloMiolo.Size = UDim2.new(1, 0, 0, 22)
	tituloMiolo.Position = UDim2.new(0, 0, 0.5, -20)
	tituloMiolo.BackgroundTransparency = 1
	tituloMiolo.Text = "EMOTES"
	tituloMiolo.TextColor3 = COR_TEXTO
	tituloMiolo.Font = Enum.Font.GothamBlack
	tituloMiolo.TextSize = 17
	tituloMiolo.Parent = miolo
	local dicaMiolo = Instance.new("TextLabel")
	dicaMiolo.Size = UDim2.new(1, -12, 0, 30)
	dicaMiolo.Position = UDim2.new(0, 6, 0.5, 2)
	dicaMiolo.BackgroundTransparency = 1
	dicaMiolo.Text = "1-6 ou clique"
	dicaMiolo.TextColor3 = COR_FRACO
	dicaMiolo.Font = Enum.Font.GothamMedium
	dicaMiolo.TextSize = 11
	dicaMiolo.TextWrapped = true
	dicaMiolo.Parent = miolo

	local casas = {}
	for i = 1, total do
		local ang = math.rad(-90 + (i - 1) * (360 / total))
		local b = Instance.new("TextButton")
		b.Name = "Casa" .. i
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.new(0.5, math.cos(ang) * RAIO, 0.5, math.sin(ang) * RAIO)
		b.Size = UDim2.fromOffset(CASA, CASA)
		b.BackgroundColor3 = COR_CARTAO
		b.BorderSizePixel = 0
		b.AutoButtonColor = false
		b.Text = ""
		b.Parent = raiz
		cantos(b, 16)
		local borda = Instance.new("UIStroke")
		borda.Thickness = 2
		borda.Color = COR_BORDA
		borda.Parent = b

		local numero = Instance.new("TextLabel")
		numero.Size = UDim2.fromOffset(22, 22)
		numero.Position = UDim2.fromOffset(6, 6)
		numero.BackgroundColor3 = COR_CARTAO_ALT
		numero.BorderSizePixel = 0
		numero.Text = tostring(i)
		numero.TextColor3 = COR_TEXTO
		numero.Font = Enum.Font.GothamBlack
		numero.TextSize = 13
		numero.Parent = b
		cantos(numero, 11)

		if i == 1 then
			local gol = Instance.new("TextLabel")
			gol.AnchorPoint = Vector2.new(1, 0)
			gol.Size = UDim2.fromOffset(34, 18)
			gol.Position = UDim2.new(1, -6, 0, 8)
			gol.BackgroundColor3 = COR_OURO
			gol.BorderSizePixel = 0
			gol.Text = "GOL"
			gol.TextColor3 = Color3.fromRGB(30, 22, 6)
			gol.Font = Enum.Font.GothamBlack
			gol.TextSize = 10
			gol.Parent = b
			cantos(gol, 9)
		end

		local nome = Instance.new("TextLabel")
		nome.Size = UDim2.new(1, -14, 0, 44)
		nome.Position = UDim2.new(0, 7, 0, 32)
		nome.BackgroundTransparency = 1
		nome.Text = ""
		nome.TextColor3 = COR_TEXTO
		nome.Font = Enum.Font.GothamBold
		nome.TextSize = 13
		nome.TextWrapped = true
		nome.Parent = b

		local faixa = Instance.new("Frame")
		faixa.AnchorPoint = Vector2.new(0.5, 1)
		faixa.Size = UDim2.new(1, -24, 0, 4)
		faixa.Position = UDim2.new(0.5, 0, 1, -8)
		faixa.BackgroundColor3 = COR_BORDA
		faixa.BorderSizePixel = 0
		faixa.Parent = b
		cantos(faixa, 2)

		casas[i] = { Botao = b, Borda = borda, Nome = nome, Faixa = faixa, Numero = numero, Tem = false }
	end

	local aberto = false
	local atualizar

	local function fechar()
		if not aberto then return end
		aberto = false
		gui.Enabled = false
		ContextActionService:UnbindAction("RodaDeEmotesTeclas")
	end

	local function escolher(i)
		local c = casas[i]
		if not c or not c.Tem then return end
		fechar()
		if aoEscolher then aoEscolher(i) end
	end

	local TECLAS = {
		[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
		[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
		[Enum.KeyCode.KeypadOne] = 1, [Enum.KeyCode.KeypadTwo] = 2, [Enum.KeyCode.KeypadThree] = 3,
		[Enum.KeyCode.KeypadFour] = 4, [Enum.KeyCode.KeypadFive] = 5, [Enum.KeyCode.KeypadSix] = 6,
	}

	for i, c in ipairs(casas) do
		c.Botao.MouseEnter:Connect(function()
			if c.Tem then
				TweenService:Create(c.Botao, TweenInfo.new(0.1), { BackgroundColor3 = COR_CARTAO_ALT }):Play()
			end
		end)
		c.Botao.MouseLeave:Connect(function()
			TweenService:Create(c.Botao, TweenInfo.new(0.1), { BackgroundColor3 = COR_CARTAO }):Play()
		end)
		c.Botao.Activated:Connect(function() escolher(i) end)
	end
	fundo.Activated:Connect(fechar)

	atualizar = function()
		for i, c in ipairs(casas) do
			local item = Cosmeticos.CasaDaRoda(jogador, i)
			c.Tem = item ~= nil
			if item then
				local cor = COR_RARIDADE[item.Raridade] or COR_RARIDADE.Common
				c.Nome.Text = item.Nome
				c.Nome.TextColor3 = COR_TEXTO
				c.Borda.Color = cor
				c.Faixa.BackgroundColor3 = cor
				c.Botao.BackgroundTransparency = 0
			else
				c.Nome.Text = "vazio\n(equipe na loja)"
				c.Nome.TextColor3 = COR_FRACO
				c.Borda.Color = COR_BORDA
				c.Faixa.BackgroundColor3 = COR_BORDA
			end
		end
	end

	local function abrir()
		if aberto then return end
		aberto = true
		atualizar()
		gui.Enabled = true
		raiz.Rotation = -8
		ajustar()
		TweenService:Create(raiz, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
		-- as teclas 1-6 e Esc valem só com a roda aberta (e engolem o input: no jogo
		-- 1 e 2 também são os slots de Hissatsu)
		ContextActionService:BindActionAtPriority("RodaDeEmotesTeclas", function(_, estado, input)
			if estado ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Sink end
			if input.KeyCode == Enum.KeyCode.Escape then
				fechar()
			elseif TECLAS[input.KeyCode] then
				escolher(TECLAS[input.KeyCode])
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10,
			Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six,
			Enum.KeyCode.KeypadOne, Enum.KeyCode.KeypadTwo, Enum.KeyCode.KeypadThree, Enum.KeyCode.KeypadFour,
			Enum.KeyCode.KeypadFive, Enum.KeyCode.KeypadSix, Enum.KeyCode.Escape)
	end

	return {
		Abrir = abrir,
		Fechar = fechar,
		Alternar = function() if aberto then fechar() else abrir() end end,
		EstaAberto = function() return aberto end,
		Atualizar = atualizar,
		-- true se alguma casa tem emote (pra esconder o botão do celular)
		TemAlgum = function()
			for i = 1, total do
				if Cosmeticos.CasaDaRoda(jogador, i) then return true end
			end
			return false
		end,
	}
end

return EmoteWheel
