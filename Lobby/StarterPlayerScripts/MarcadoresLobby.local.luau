--[[
	MarcadoresLobby — ⚠️ v104

	PEDIDO: "aumenta o tamanho [do marcador de procurar partida], deixa num
	tamanho visível pra poder ver atrás da parede mesmo... faz isso também na
	Eleven Store, no local de missão e no Kogamalotigo (perfil/slots). Tem que
	ter um pra cada coisa."

	Um marcador por destino (posições publicadas pelo servidor em
	ReplicatedStorage.MarcadoresLobby — ver MarcadoresLobbyServer). Cada um é
	um BillboardGui:
	  • AlwaysOnTop — aparece através de parede/prédio;
	  • tamanho em PIXELS fixos — legível igual de perto e de longe;
	  • distância em metros, e some quando você já está em cima do lugar.
	A âncora é uma Part criada AQUI no cliente (não sofre streaming), então o
	marcador existe mesmo com o NPC longe e ainda não carregado.
	Visual no padrão do lobby (skill ui-lobby), 1 cor por destino, sem emoji.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local PAINEL = Color3.fromRGB(13, 15, 22)
local TEXTO = Color3.fromRGB(238, 241, 248)
local TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)

local DESTINOS = {
	{ Chave = "Partida", Titulo = "PROCURAR PARTIDA", Sub = "entre no campo pra jogar", Cor = Color3.fromRGB(64, 196, 122), Letra = "P" },
	{ Chave = "Loja",    Titulo = "ELEVEN STORE",     Sub = "loja",                      Cor = Color3.fromRGB(255, 200, 70), Letra = "E" },
	{ Chave = "Missoes", Titulo = "MISSÕES",          Sub = "missões diárias",           Cor = Color3.fromRGB(76, 156, 255), Letra = "M" },
	{ Chave = "Perfil",  Titulo = "PERFIL",           Sub = "seus slots e atributos",    Cor = Color3.fromRGB(170, 120, 255), Letra = "K" },
}
local SOME_PERTO = 22 -- studs: já chegou, o marcador sai da frente (e não briga com o nome do NPC)

local pasta = ReplicatedStorage:WaitForChild("MarcadoresLobby", 60)
if not pasta then
	warn("MarcadoresLobby: servidor não publicou as posições (MarcadoresLobbyServer).")
	return
end

local raiz = Instance.new("Folder")
raiz.Name = "MarcadoresLobbyLocal"
raiz.Parent = workspace

local function cantos(inst, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local marcadores = {}

local function criar(destino, posicao)
	local ancora = Instance.new("Part")
	ancora.Name = "Ancora_" .. destino.Chave
	ancora.Size = Vector3.new(0.2, 0.2, 0.2)
	ancora.Transparency = 1
	ancora.Anchored = true
	ancora.CanCollide = false
	ancora.CanQuery = false
	ancora.CanTouch = false
	ancora.Position = posicao
	ancora.Parent = raiz

	local bb = Instance.new("BillboardGui")
	bb.Name = "Marcador"
	bb.Adornee = ancora
	bb.Size = UDim2.fromOffset(250, 66)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 3000
	bb.ResetOnSpawn = false
	bb.Parent = ancora

	local grupo = Instance.new("Frame") -- (CanvasGroup não renderiza dentro de BillboardGui)
	grupo.ClipsDescendants = true
	grupo.Size = UDim2.fromScale(1, 1)
	grupo.BackgroundColor3 = PAINEL
	grupo.BackgroundTransparency = 0.08
	grupo.Parent = bb
	cantos(grupo, 12)
	local stroke = Instance.new("UIStroke")
	stroke.Color = destino.Cor
	stroke.Thickness = 2
	stroke.Transparency = 0.2
	stroke.Parent = grupo

	local bloco = Instance.new("Frame")
	bloco.Size = UDim2.new(0, 54, 1, 0)
	bloco.BackgroundColor3 = destino.Cor
	bloco.BorderSizePixel = 0
	bloco.Parent = grupo
	local letra = Instance.new("TextLabel")
	letra.Size = UDim2.fromScale(1, 1)
	letra.BackgroundTransparency = 1
	letra.Text = destino.Letra
	letra.TextColor3 = PAINEL
	letra.Font = Enum.Font.GothamBlack
	letra.TextSize = 30
	letra.Parent = bloco

	local titulo = Instance.new("TextLabel")
	titulo.Position = UDim2.fromOffset(66, 9)
	titulo.Size = UDim2.new(1, -76, 0, 26)
	titulo.BackgroundTransparency = 1
	titulo.Text = destino.Titulo
	titulo.TextColor3 = TEXTO
	titulo.Font = Enum.Font.GothamBlack
	titulo.TextSize = 21
	titulo.TextXAlignment = Enum.TextXAlignment.Left
	titulo.TextTruncate = Enum.TextTruncate.AtEnd
	titulo.Parent = grupo

	local sub = Instance.new("TextLabel")
	sub.Position = UDim2.fromOffset(66, 36)
	sub.Size = UDim2.new(1, -76, 0, 20)
	sub.BackgroundTransparency = 1
	sub.Text = destino.Sub
	sub.TextColor3 = TEXTO_MEDIO
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 14
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.Parent = grupo

	-- setinha embaixo (quadrado girado 45°)
	local seta = Instance.new("Frame")
	seta.AnchorPoint = Vector2.new(0.5, 0.5)
	seta.Position = UDim2.new(0.5, 0, 1, 2)
	seta.Size = UDim2.fromOffset(14, 14)
	seta.Rotation = 45
	seta.BackgroundColor3 = destino.Cor
	seta.BorderSizePixel = 0
	seta.ZIndex = 0
	seta.Parent = bb

	local m = { Destino = destino, Ancora = ancora, Bb = bb, Grupo = grupo, Sub = sub, Stroke = stroke, Base = posicao }
	marcadores[destino.Chave] = m
	return m
end

local function sincronizar()
	for _, destino in ipairs(DESTINOS) do
		local pos = pasta:GetAttribute(destino.Chave)
		if typeof(pos) == "Vector3" then
			local m = marcadores[destino.Chave] or criar(destino, pos)
			m.Base = pos
		end
	end
end
sincronizar()
pasta.AttributeChanged:Connect(sincronizar)

-- flutua devagar, mostra a distância, some quando chega perto
local t = 0
RunService.RenderStepped:Connect(function(dt)
	t += dt
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	for chave, m in pairs(marcadores) do
		m.Ancora.Position = m.Base + Vector3.new(0, math.sin(t * 1.6 + #chave) * 0.8, 0)
		if root then
			local d = (root.Position - m.Base).Magnitude
			local perto = d < SOME_PERTO
			m.Bb.Enabled = not perto
			if not perto then
				m.Sub.Text = ("%s  ·  %d m"):format(m.Destino.Sub, math.floor(d / 3.57 + 0.5)) -- ~3.57 studs = 1 m
			end
		end
		m.Stroke.Transparency = 0.15 + 0.2 * (0.5 + 0.5 * math.sin(t * 3))
	end
end)

-- o marcador antigo (MatchWaypointHologram) foi substituído por este sistema
_G.MarcadoresLobbyAtivo = true
