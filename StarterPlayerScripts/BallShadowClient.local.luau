--[[
	BallShadowClient (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	⚠️ v45 — PEDIDO: "eu preciso colocar uma sombra na bola. Vai ter um
	círculo que aparece quando alguém chutar a bola. Quanto mais perto a
	bola estiver do chão, MAIOR vai ser esse círculo; e quanto mais longe,
	MENOR. E aí ele vai mostrar mais ou menos onde a bola vai cair. Um
	círculozinho, como se fosse uma sombra mesmo, bem no chão, abaixo da
	bola, encostado ao chão."

	NOTA SOBRE O TAMANHO: é o contrário de uma sombra física de verdade
	(que encolhe quando o objeto se aproxima do chão). Está assim porque foi
	pedido assim, e explicitamente confirmado no pedido — perto = maior,
	longe = menor. Como leitura de jogo funciona: a marca fica discreta
	enquanto a bola está alta e longe, e "abre" conforme ela chega, chamando
	atenção justo na hora de disputar o lance.

	ONDE ELA FICA: no ponto do CHÃO abaixo da bola, achado por raycast pra
	baixo — então ela acompanha o gramado de verdade em vez de flutuar numa
	altura fixa. É por isso também que ela mostra "mais ou menos onde a bola
	vai cair": com a bola em voo, o ponto embaixo dela vai correndo pela
	grama na direção do lance.

	⚠️ v51 — QUANDO ELA APARECE (duas condições, as DUAS têm que valer):
	  1) SEM DOMÍNIO de ninguém. "Eu estou movimentando com a bola e está
	     aparecendo a sombra, não é pra fazer isso." Bola no pé de alguém
	     nunca tem sombra, nem se ele jogar ela pra cima — foi confirmado:
	     "Não pode não. Sem domínio."
	  2) NO AR de verdade. "Não é porque a bola está se movimentando que ela
	     tem que mostrar a sombra, ela tem que estar NO AR." Antes bastava a
	     bola ter velocidade, então bola rolando no chão também marcava.
	     Agora existe uma altura mínima (BALL_SHADOW_MIN_HEIGHT).

	⚠️ v51 — POR QUE NÃO É MAIS UMA TEXTURA: a primeira versão usava uma
	Decal com um asset de sombra, e ficou "parecendo uma skin" — asset de
	imagem vem com borda, formato e proporção próprios, e não dá pra
	garantir que seja um círculo limpo. Agora a marca é a GEOMETRIA em si:
	uma Part com Shape = Cylinder, achatada. Visto de cima, um cilindro é um
	círculo perfeito por definição — sem imagem, sem asset, sem depender de
	moderação, e sempre redondo.

	POR QUE NO CLIENTE: é puramente visual. Feito no servidor, seria uma
	Part replicada mudando de tamanho e posição todo frame pra todo mundo.
	Aqui cada jogador desenha a sua, de graça pra rede.

	RELAÇÃO COM A METAVISÃO: a Arma Metavisão desenha a trajetória inteira e
	o ponto exato de parada — é bem mais informativa. Esta sombra é o aviso
	básico que TODO mundo tem, com ou sem Arma equipada (pedido: "claro que
	a Metavisão completa isso de uma forma muito melhor, mas eu também quero
	que tenha isso").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
-- ⚠️ v52 FIX: isto FALTAVA. O listener de posse lá embaixo usa
-- Remotes.PossessionChanged, mas `Remotes` nunca tinha sido declarado neste
-- arquivo — ele nasceu só com Config. Isso COMPILA sem reclamar (o erro só
-- acontece ao indexar nil em tempo de execução), o script inteiro morria na
-- primeira linha do listener, e a sombra nunca aparecia em situação
-- nenhuma. Era esse o "joguei pra cima, sem domínio, e ela não aparece".
local Remotes = Config.Remotes

local bola = workspace:WaitForChild(Config.BALL_NAME, 30)
if not bola then
	warn("🌑 [Sombra] não achei a bola ('" .. tostring(Config.BALL_NAME) .. "') — sombra desligada.")
	return
end

-- ===== A MARCA =====
-- ⚠️ v112 — PEDIDO (com print de referência): "a sombra pode aparecer sempre,
-- com um tamanho mínimo — mesmo muito distante ela não pode sumir" + o visual
-- da referência: ANÉIS CONCÊNTRICOS no chão (miolo escuro com contorno claro,
-- faixa escura translúcida e um anel claro por fora).
-- Agora é uma plaquinha invisível deitada no gramado com uma SurfaceGui em
-- cima: os anéis são Frames redondos (UICorner) com UIStroke — círculos
-- perfeitos e nítidos em qualquer tamanho, sem imagem nem asset (continua
-- valendo o motivo do v51: textura vira "skin").
-- CanCollide/CanQuery/CanTouch desligados: não empurra a bola, não entra no
-- raycast da própria sombra e não vira alvo de mira (ver
-- isProbablyMathOnlyHitbox em FootballClient).
local marca = Instance.new("Part")
marca.Name = "SombraDaBola"
marca.Material = Enum.Material.SmoothPlastic
marca.Anchored = true
marca.CanCollide = false
marca.CanQuery = false
marca.CanTouch = false
marca.CastShadow = false
marca.Transparency = 1
marca.Size = Vector3.new(Config.BALL_SHADOW_MAX_SIZE, 0.05, Config.BALL_SHADOW_MAX_SIZE)
marca.Parent = workspace

local superficie = Instance.new("SurfaceGui")
superficie.Name = "Aneis"
superficie.Face = Enum.NormalId.Top
superficie.CanvasSize = Vector2.new(512, 512)
superficie.LightInfluence = 0
superficie.Brightness = 1
superficie.Enabled = false
superficie.Parent = marca

-- { tamanho relativo, cor do fundo, transparência do fundo, cor do anel,
--   transparência do anel, espessura do anel (px do canvas) }
local CAMADAS = {
	{ 1.00, Color3.new(1, 1, 1), 0.9,  Color3.new(1, 1, 1), 0.5,  10 }, -- anel claro de fora
	{ 0.72, Color3.new(0, 0, 0), 0.78, Color3.new(1, 1, 1), 0.7,  5 },  -- faixa escura + anel fino
	{ 0.40, Color3.new(0, 0, 0), 0.35, Color3.new(1, 1, 1), 0.2,  6 },  -- miolo escuro com contorno
}
local aneis = {}
for i, c in ipairs(CAMADAS) do
	local f = Instance.new("Frame")
	f.Name = "Anel" .. i
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(c[1] * 0.96, c[1] * 0.96)
	f.BackgroundColor3 = c[2]
	f.BorderSizePixel = 0
	f.ZIndex = i
	f.Parent = superficie
	local canto = Instance.new("UICorner")
	canto.CornerRadius = UDim.new(0.5, 0)
	canto.Parent = f
	local traco = Instance.new("UIStroke")
	traco.Color = c[4]
	traco.Thickness = c[6]
	traco.Parent = f
	aneis[i] = { Frame = f, Traco = traco, Base = c }
end

local function aplicarOpacidade(alfa, respira)
	-- alfa 1 = como desenhado; menor = mais apagado (bola alta), nunca some
	for i, a in ipairs(aneis) do
		local c = a.Base
		a.Frame.BackgroundTransparency = 1 - (1 - c[3]) * alfa
		a.Traco.Transparency = 1 - (1 - c[5]) * alfa
		if i == 1 then
			-- o anel de fora "respira" devagar, chamando o olho pro ponto
			local s = c[1] * (0.9 + 0.06 * respira)
			a.Frame.Size = UDim2.fromScale(s, s)
		end
	end
end

local filtro = RaycastParams.new()
filtro.FilterType = Enum.RaycastFilterType.Exclude
filtro.IgnoreWater = true

-- Recalcula a lista de exclusão só de vez em quando: personagens entram e
-- saem o tempo todo, mas nem de longe todo frame.
local proximaAtualizacaoDoFiltro = 0
local function atualizarFiltro()
	local excluir = { bola, marca }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then table.insert(excluir, player.Character) end
	end
	filtro.FilterDescendantsInstances = excluir
end
atualizarFiltro()

-- ⚠️ v51: quem está com a bola. Mesmo listener que AbilityHUD,
-- FootballClient e InstinctTrajectorySight já usam — não precisa de remote
-- novo. Basta saber se EXISTE dono, não quem é.
-- ⚠️ v112 FIX: guardava só o ÚLTIMO aviso ("alguém ganhou/perdeu"). Se o
-- "fulano soltou" chegasse DEPOIS do "ciclano pegou", ficava "sem dono" com a
-- bola no pé de alguém — e a sombra aparecia embaixo dele. Agora guarda QUEM é
-- o dono e só limpa se quem soltou for ele mesmo.
local donoDaBola = nil
Remotes.PossessionChanged.OnClientEvent:Connect(function(quem, ganhou)
	if ganhou then
		donoDaBola = quem or true
	elseif donoDaBola == quem or quem == nil then
		donoDaBola = nil
	end
end)

-- ⚠️ v112: os GK Bots em campo (lista viva, sem varrer o workspace todo quadro)
local goleirosBot = {}
local function talvezBot(m)
	if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" then goleirosBot[m] = true end
end
for _, m in ipairs(workspace:GetChildren()) do talvezBot(m) end
workspace.ChildAdded:Connect(talvezBot)
workspace.ChildRemoved:Connect(function(m) goleirosBot[m] = nil end)

local function esconder()
	superficie.Enabled = false
end

RunService.Heartbeat:Connect(function()
	if not bola.Parent then
		esconder()
		return
	end

	local agora = os.clock()
	if agora >= proximaAtualizacaoDoFiltro then
		proximaAtualizacaoDoFiltro = agora + 1
		atualizarFiltro()
	end

	-- ⚠️ v51, CONDIÇÃO 1: bola no pé de alguém NUNCA tem sombra — nem
	-- parada, nem em movimento, nem se a pessoa jogar ela pra cima.
	if donoDaBola then
		esconder()
		return
	end
	-- ⚠️ v112: o GK BOT não é jogador (não passa pelo aviso de posse) — com a
	-- bola na mão dele (atributo BolaNaMao) também não tem sombra
	for m in pairs(goleirosBot) do
		if m:GetAttribute("BolaNaMao") then
			esconder()
			return
		end
	end

	-- ⚠️ v112: procura o chão bem mais longe (antes 67 studs — bola mais alta
	-- que isso ficava sem sombra)
	local batida = workspace:Raycast(
		bola.Position,
		Vector3.new(0, -(Config.BALL_SHADOW_RAY_LENGTH or 600), 0),
		filtro
	)
	if not batida then
		esconder()
		return
	end

	local altura = bola.Position.Y - batida.Position.Y

	-- ⚠️ v51, CONDIÇÃO 2: tem que estar NO AR (bola rolando não marca).
	if altura < Config.BALL_SHADOW_MIN_HEIGHT then
		esconder()
		return
	end

	-- Perto do chão = 1 (grande), na altura máxima ou acima = 0 (tamanho
	-- MÍNIMO — ⚠️ v112: dali pra cima não encolhe nem some mais).
	local proximidade = 1 - math.clamp(altura / Config.BALL_SHADOW_MAX_HEIGHT, 0, 1)
	local tamanho = Config.BALL_SHADOW_MIN_SIZE
		+ (Config.BALL_SHADOW_MAX_SIZE - Config.BALL_SHADOW_MIN_SIZE) * proximidade

	marca.Size = Vector3.new(tamanho, 0.05, tamanho)
	-- Deitada no chão e alinhada com a inclinação dele (a normal da batida):
	-- o eixo Y da plaquinha (face Top, onde está a SurfaceGui) = a normal.
	local normal = batida.Normal
	local apoio = normal:Cross(Vector3.new(0, 0, 1))
	if apoio.Magnitude < 0.01 then
		apoio = normal:Cross(Vector3.new(1, 0, 0))
	end
	marca.CFrame = CFrame.fromMatrix(batida.Position + normal * 0.06, apoio.Unit, normal)

	local minimo = Config.BALL_SHADOW_MIN_ALPHA or 0.7
	aplicarOpacidade(minimo + (1 - minimo) * proximidade, (math.sin(agora * 5) + 1) / 2)
	superficie.Enabled = true
end)

print("✅ BallShadowClient carregado.")
