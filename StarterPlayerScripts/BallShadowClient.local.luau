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
-- CanCollide/CanQuery/CanTouch desligados: ela
-- não pode nem empurrar a bola, nem aparecer no raycast da própria sombra,
-- nem ser confundida com alvo de mira pelo computeAimPoint do chute (foi
-- exatamente esse tipo de hitbox invisível que já causou bug de mira
-- antes — ver isProbablyMathOnlyHitbox em FootballClient).
-- Cylinder achatado = círculo perfeito visto de cima (ver o comentário do
-- cabeçalho sobre por que não é mais uma Decal com textura).
-- ATENÇÃO à convenção do Roblox: num Part com Shape = Cylinder, as tampas
-- redondas ficam no eixo X. Então Size é (espessura, diâmetro, diâmetro), e
-- quem tem que apontar pra cima é o eixo X — não o Y, como seria num bloco.
local marca = Instance.new("Part")
marca.Name = "SombraDaBola"
marca.Shape = Enum.PartType.Cylinder
marca.Material = Enum.Material.SmoothPlastic
marca.Color = Color3.fromRGB(0, 0, 0)
marca.Anchored = true
marca.CanCollide = false
marca.CanQuery = false
marca.CanTouch = false
marca.CastShadow = false
marca.Transparency = 1
marca.Size = Vector3.new(
	Config.BALL_SHADOW_THICKNESS,
	Config.BALL_SHADOW_MAX_SIZE,
	Config.BALL_SHADOW_MAX_SIZE
)
marca.Parent = workspace

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
local bolaTemDono = false
Remotes.PossessionChanged.OnClientEvent:Connect(function(_, ganhou)
	bolaTemDono = ganhou and true or false
end)

local function esconder()
	marca.Transparency = 1
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
	if bolaTemDono then
		esconder()
		return
	end

	local batida = workspace:Raycast(
		bola.Position,
		Vector3.new(0, -Config.BALL_SHADOW_MAX_HEIGHT * 1.5, 0),
		filtro
	)
	if not batida then
		esconder()
		return
	end

	local altura = bola.Position.Y - batida.Position.Y

	-- ⚠️ v51, CONDIÇÃO 2: tem que estar NO AR. Antes a checagem era por
	-- VELOCIDADE, e por isso bola rolando pelo gramado também marcava
	-- sombra — que é justamente o que não faz sentido.
	if altura < Config.BALL_SHADOW_MIN_HEIGHT then
		esconder()
		return
	end

	-- Perto do chão = 1 (círculo grande), na altura máxima = 0 (pequeno).
	local proximidade = 1 - math.clamp(altura / Config.BALL_SHADOW_MAX_HEIGHT, 0, 1)
	local tamanho = Config.BALL_SHADOW_MIN_SIZE
		+ (Config.BALL_SHADOW_MAX_SIZE - Config.BALL_SHADOW_MIN_SIZE) * proximidade

	marca.Size = Vector3.new(Config.BALL_SHADOW_THICKNESS, tamanho, tamanho)
	-- Colada no chão e alinhada com a inclinação dele (a normal da batida),
	-- pra não atravessar nem flutuar em nenhuma parte do gramado.
	-- CFrame.fromMatrix(posição, eixoX, eixoY): o eixo X recebe a normal do
	-- chão, que é o eixo das tampas redondas do Cylinder — é isso que deixa
	-- o círculo deitado no gramado. `apoio` é só um vetor qualquer
	-- perpendicular à normal pra fechar a base (a rotação do disco em torno
	-- do próprio eixo não importa: um círculo é igual de qualquer ângulo).
	local normal = batida.Normal
	local apoio = normal:Cross(Vector3.new(0, 0, 1))
	if apoio.Magnitude < 0.01 then
		apoio = normal:Cross(Vector3.new(1, 0, 0))
	end
	marca.CFrame = CFrame.fromMatrix(
		batida.Position + normal * (Config.BALL_SHADOW_THICKNESS / 2 + 0.02),
		normal,
		apoio.Unit
	)

	-- Bola muito alta fica quase translúcida; chegando perto, escurece.
	marca.Transparency = Config.BALL_SHADOW_MAX_TRANSPARENCY
		- (Config.BALL_SHADOW_MAX_TRANSPARENCY - Config.BALL_SHADOW_MIN_TRANSPARENCY) * proximidade
end)

print("✅ BallShadowClient carregado.")
