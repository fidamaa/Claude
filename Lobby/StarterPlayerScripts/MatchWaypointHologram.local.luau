--[[
	MatchWaypointHologram (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	⚠️ v80 — NOVO. PEDIDO: "faça outro holograma, pra indicar onde a
	pessoa precisa ir pra dar play (no matchmaking area), esse sim pode
	atravessar a parede e ficar grande e pequeno [com a distância]."

	Diferente do holograma do Roll (RollHologramClient.local.luau — esse
	NÃO pode atravessar parede nem mudar de tamanho, é um painel que você
	lê de perto), este é um MARCADOR DE OBJETIVO — igual um waypoint de
	quest em qualquer jogo: precisa ser visível de longe, inclusive atrás
	de parede/prédio, pra guiar o jogador até o campo (Config.
	MATCHMAKING_ZONE_NAME, a mesma Part que MatchmakingZone.legacy.luau já
	usa pra abrir a tela de fila por overlap — fonte única, não duplica
	posição na mão).

	Duas peças:
	1) FÍSICO — um feixe de luz (Neon, real, 3D) subindo do centro do
		campo até o marcador. Esse SIM ocluide normal atrás de parede (é
		Part de verdade) — é só reforço visual pra quem já está perto/com
		linha de visão.
	2) MARCADOR — BillboardGui com AlwaysOnTop=true (visível através de
		QUALQUER coisa, inclusive parede) e Size em OFFSET (mantém
		tamanho em STUDS — fica maior perto, menor longe, como um objeto
		de verdade) — as DUAS propriedades que o holograma do Roll teve
		que perder pro pedido dele, aqui são exatamente o que foi pedido.
		Flutua (bob) e pulsa (brilho) devagar pra chamar atenção sem virar
		poluição visual.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

local VERDE = Color3.fromRGB(90, 255, 150)
local VERDE_FRACO = Color3.fromRGB(60, 180, 110)
local FUNDO = Color3.fromRGB(8, 20, 14)

-- ⚠️ mesmo cuidado do RollHologramClient: workspace.StreamingEnabled tá
-- ligado e essa zona pode ficar longe do spawn — espera de verdade em
-- vez de olhar só uma vez.
local zona = workspace:WaitForChild(Config.MATCHMAKING_ZONE_NAME, 30)
if not zona then
	warn("MatchWaypointHologram: zona de matchmaking (" .. tostring(Config.MATCHMAKING_ZONE_NAME) .. ") não encontrada — marcador não vai aparecer.")
	return
end

local centro = zona.Position
local TOPO_ZONA = centro.Y + zona.Size.Y / 2
local ALTURA_MARCADOR = 14 -- bem alto — dá pra ver de longe/por cima de prédio baixo

local pasta = Instance.new("Folder")
pasta.Name = "MatchWaypointFisico"
pasta.Parent = zona.Parent or workspace

-- ===== FEIXE FÍSICO (real, oclui normal atrás de parede) =====
local feixe = Instance.new("Part")
feixe.Name = "FeixeWaypoint"
feixe.Size = Vector3.new(0.6, ALTURA_MARCADOR, 0.6)
feixe.CFrame = CFrame.new(centro.X, TOPO_ZONA + ALTURA_MARCADOR / 2, centro.Z)
feixe.Shape = Enum.PartType.Cylinder
feixe.CFrame = feixe.CFrame * CFrame.Angles(0, 0, math.rad(90))
feixe.Color = VERDE
feixe.Material = Enum.Material.Neon
feixe.Transparency = 0.55
feixe.Anchored = true
feixe.CanCollide = false
feixe.CanQuery = false
feixe.CastShadow = false
feixe.Parent = pasta

local luz = Instance.new("PointLight")
luz.Color = VERDE
luz.Brightness = 1.4
luz.Range = 20
luz.Parent = feixe

-- ===== MARCADOR (BillboardGui — AlwaysOnTop, Size em Offset) =====
local ancora = Instance.new("Part")
ancora.Name = "AncoraMarcador"
ancora.Size = Vector3.new(0.2, 0.2, 0.2)
ancora.Position = Vector3.new(centro.X, TOPO_ZONA + ALTURA_MARCADOR + 1.5, centro.Z)
ancora.Anchored = true
ancora.CanCollide = false
ancora.CanQuery = false
ancora.Transparency = 1
ancora.Parent = pasta

local bb = Instance.new("BillboardGui")
bb.Name = "MarcadorPartida"
bb.Adornee = ancora
-- ⚠️ v80 — CONFIRMADO AO VIVO (medindo AbsoluteSize em Studio, variando
-- só a distância da câmera): é o componente em ESCALA do Size que muda
-- de tamanho com a distância — o Offset fica em PIXELS DE TELA FIXOS
-- sempre (isso era o oposto do que o comentário antigo dizia aqui, por
-- isso testei em vez de confiar). AlwaysOnTop=true de propósito —
-- atravessa parede/prédio, é um waypoint visível de longe.
-- ⚠️ v81 — PEDIDO: "o holograma está grande demais". Era 6,3.2 (129x69px
-- a 20 studs) — reduzido praticamente à metade.
bb.Size = UDim2.fromScale(3, 1.6)
bb.StudsOffset = Vector3.new(0, 0, 0)
bb.MaxDistance = 500
bb.AlwaysOnTop = true
bb.LightInfluence = 0
-- ⚠️ v104: o letreiro agora é o do MarcadoresLobby.local.luau (maior,
-- tamanho fixo na tela, um por destino). Aqui fica só o feixe de luz.
bb.Enabled = false
bb.Parent = ancora

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

-- ⚠️ v80: TUDO aqui dentro usa Size em ESCALA (fromScale), nunca Offset
-- — um filho com Offset ficaria travado num tamanho de pixel FIXO (ver
-- nota acima) enquanto o "bb" pai encolhe/cresce com a distância,
-- distorcendo a proporção (testei e foi exatamente isso que aconteceu
-- na primeira versão: painel ficava largo/fino longe, porque só a
-- largura acompanhava o pai). TextScaled=true nos textos pelo mesmo
-- motivo — TextSize sozinho não muda de tamanho junto com o contêiner.
local painel = Instance.new("Frame")
painel.Size = UDim2.fromScale(1, 1)
painel.Position = UDim2.fromScale(0, 0)
painel.BackgroundColor3 = FUNDO
painel.BackgroundTransparency = 0.15
painel.BorderSizePixel = 0
painel.Parent = bb
cantos(painel, 10)
local aroContorno = contorno(painel, VERDE, 1.5, 0.2)

local titulo = Instance.new("TextLabel")
titulo.Size = UDim2.fromScale(0.92, 0.46)
titulo.Position = UDim2.fromScale(0.04, 0.08)
titulo.BackgroundTransparency = 1
titulo.Text = "PARTIDA"
titulo.Font = Enum.Font.GothamBlack
titulo.TextScaled = true
titulo.TextColor3 = VERDE
titulo.TextXAlignment = Enum.TextXAlignment.Center
titulo.ZIndex = 2
titulo.Parent = painel

local subtitulo = Instance.new("TextLabel")
subtitulo.Size = UDim2.fromScale(0.92, 0.26)
subtitulo.Position = UDim2.fromScale(0.04, 0.58)
subtitulo.BackgroundTransparency = 1
subtitulo.Text = "entre aqui pra puxar fila"
subtitulo.Font = Enum.Font.GothamMedium
subtitulo.TextScaled = true
subtitulo.TextColor3 = VERDE_FRACO
subtitulo.TextXAlignment = Enum.TextXAlignment.Center
subtitulo.ZIndex = 2
subtitulo.Parent = painel

-- seta apontando pra baixo (desenhada — um quadrado rotacionado 45°,
-- metade encoberta pelo painel — em vez de caractere Unicode: a fonte
-- Gotham já mostrou não ter glyph pra vários símbolos usados antes, ex.:
-- "×"/"✦", então desenhar é o caminho seguro).
local seta = Instance.new("Frame")
seta.Size = UDim2.fromScale(0.1, 0.1)
seta.AnchorPoint = Vector2.new(0.5, 0.5)
seta.Position = UDim2.new(0.5, 0, 1, 0)
seta.BackgroundColor3 = FUNDO
seta.Rotation = 45
seta.BorderSizePixel = 0
seta.ZIndex = 1
seta.Parent = bb
contorno(seta, VERDE, 1.5, 0.2)

-- ===== ANIMAÇÃO: flutua devagar + brilho pulsando =====
task.spawn(function()
	while ancora.Parent do
		TweenService:Create(ancora, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = ancora.Position + Vector3.new(0, 1, 0) }):Play()
		task.wait(1.6)
		TweenService:Create(ancora, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Position = ancora.Position - Vector3.new(0, 1, 0) }):Play()
		task.wait(1.6)
	end
end)

task.spawn(function()
	while feixe.Parent do
		TweenService:Create(luz, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Brightness = 2.6 }):Play()
		TweenService:Create(aroContorno, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0 }):Play()
		task.wait(1.2)
		TweenService:Create(luz, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Brightness = 1.4 }):Play()
		TweenService:Create(aroContorno, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Transparency = 0.2 }):Play()
		task.wait(1.2)
	end
end)

-- feixe gira devagar em torno do próprio eixo — reforça "energia", não
-- estampa parada (mesmo truque do anel no holograma do Roll).
RunService.Heartbeat:Connect(function(dt)
	if feixe.Parent then
		feixe.CFrame = feixe.CFrame * CFrame.Angles(dt * 0.5, 0, 0)
	end
end)

print("✅ MatchWaypointHologram carregado — marcador do campo ativo.")
