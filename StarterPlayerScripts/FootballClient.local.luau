--[[
	FootballClient (LocalScript)
	LOCAL: StarterPlayerScripts

	Um único LocalScript cuidando de TODO o input do jogador (Shift Lock,
	chute/passe/voleio, dash/carrinho, cabeçada) e da UI (barra de
	stamina, placar, menu de troca de time, resumo pós-partida).

	⚠️ NOVO — ESQUEMA DE CONTROLES (PEDIDO do usuário):
		WASD            movimento (sem tecla de sprint — ver RUN_SPEED)
		Q               COM a bola: drible direcional (DribbleInput.local.luau)
		                SEM a bola: carrinho (⚠️ v86 — ver KEYS.Tackle)
		F               dash: arranque curto na direção do WASD, com ou sem
		                bola, não rouba nada (⚠️ v86 — ver KEYS.Dash)
		E / R           Arma 1 / Arma 2 (PulseInput.local.luau)
		1 / 2           Hissatsu 1 / 2 (HissatsuInput.local.luau)
		T               cabeçada
		Espaço          pulo (padrão do Roblox)
		Clique esquerdo chute (voleio se a bola estiver no ar e você sem posse)
	Mantidos por não conflitarem: Ctrl = câmera/Shift Lock, H = pedir
	passe, V = Instinct Mode. Goleiro dentro da área: Q + direção =
	mergulho, F = saída do gol (GKInput.local.luau).
]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

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
local Remotes = Config.Remotes

-- ⚠️ FIX: só pra garantir que o require abaixo rode BEM cedo (o module
-- já corrige sozinho, no próprio require, o CanQuery/CanCollide/CanTouch
-- das Parts GKArea_* — ver GKAreaUtil.lua) — sem isso, se esse script
-- fosse o primeiro a carregar (antes de GKInput/PulseInput/DribbleInput),
-- o mouse.Hit usado pra mirar o chute abaixo podia acertar a caixa
-- invisível da grande área em vez do gramado, "puxando" a mira pra fora
-- toda vez que o jogador mirasse perto ou dentro dela.
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local function waitForPath(root, path, timeout)
	local current = root
	for _, name in ipairs(path) do
		current = current and current:WaitForChild(name, timeout or 5)
		if not current then return nil end
	end
	return current
end

-- ===== TECLAS =====
-- Pass foi removido: chutar mirando num companheiro já funciona como
-- passe. Control (domínio) também foi removido: a posse de bola solta é
-- automática por proximidade (ver BallController).
-- ⚠️ NOVO: Sprint (Shift) SAIU — PEDIDO: "Não haverá botão de corrida/
-- sprint". Carrinho (era Z) virou o DASH no F, e a cabeçada foi de G pra T.
local KEYS = {
	ShiftLock = Enum.KeyCode.LeftControl, -- Shift Lock nativo, só que na tecla Ctrl
	Tackle = Enum.KeyCode.Q, -- ⚠️ v86: carrinho no Q, só SEM a bola (com ela, Q = drible)
	Dash = Enum.KeyCode.F, -- ⚠️ v86: dash de avanço (não é mais o carrinho)
	-- ⚠️ v105: a cabeçada SAIU do T — agora é no ar, com o botão de chute
	-- (ver acaoAerea abaixo)
}

-- ============================================================
-- ⚠️ v5.4 — BUG "chute pra cima vai pra trás" (também no escanteio, que
-- usa o mesmo KickBall). Perto da vertical, mouse.Hit.Position raycasta
-- pra cima e não acha nada — o Mouse do Roblox devolve um ponto BEM longe
-- ao longo do raio da câmera, e como a câmera (3ª pessoa) fica ATRÁS e
-- ACIMA do personagem, a componente HORIZONTAL desse ponto reflete a
-- posição da CÂMERA, não pra onde o jogador queria mirar — daí "chutei
-- pra cima, a bola foi pra trás". Perto da vertical (LookVector quase
-- todo em Y), ignora o mouse.Hit inteiro e usa a direção horizontal da
-- própria câmera (pra onde ela aponta no chão) como referência, com a
-- altura vindo de quão inclinada ela está — a mira sempre fica na frente
-- de quem está mirando, nunca atrás. Mira normal (não muito inclinada
-- pra cima/baixo) continua 100% igual a antes (mouse.Hit.Position puro).
-- ============================================================
-- ⚠️ v38 FIX: "não consigo mais mirar, o chute só vai reto pra cima ou pra
-- baixo" — 0.85 (~58° da horizontal) é um ângulo que a câmera atinge só de
-- olhar pra baixo pra mirar bem na bola de perto, NADA extremo — bem mais
-- comum do que o "câmera quase reta pra cima/baixo" que essa correção foi
-- desenhada pra cobrir (ver comentário grande abaixo). Isso fazia QUALQUER
-- chute com a câmera um pouco mais inclinada cair nesse fallback, que é
-- dominado pelo termo vertical (300*Y) — a componente horizontal (mira de
-- lado) virava insignificante perto disso, e o chute saía quase sempre
-- reto pra cima/baixo, ignorando pra onde o mouse mirava de verdade.
-- Subido pra 0.96 (~74° da horizontal — só ativa perto de olhar reto pra
-- cima/baixo de propósito), pra mira normal (mesmo inclinada) nunca mais
-- cair aqui sem precisar.
local AIM_PITCH_STEEP_THRESHOLD = 0.96 -- ⚠️ v38 (era 0.85) — |LookVector.Y| acima disso: perto o bastante da vertical pra aplicar a correção

-- ⚠️ v6.3: PEDIDO — "quando eu estou olhando pra trás, já que a gente cobra
-- o escanteio bem na frente dessa área [zona de bola fora], ele acaba
-- jogando a bola pra trás... o mesmo problema do negócio de olhar pra cima
-- e ir pra trás quando chutar". MESMA causa raiz do fix de pitch acima
-- (v5.4), só que disparada de outro jeito: perto da BORDA do campo (onde
-- escanteio/tiro de meta são cobrados, bem em cima/perto das zonas
-- OutLateral/OutFundo — ver OutOfBoundsController.lua), o raycast do
-- mouse.Hit pode simplesmente não achar NADA (nenhuma Part) se você olhar
-- pra fora do campo de jogo por ali — e o sintoma é o mesmo de sempre:
-- Mouse.Target vem nil e o Roblox devolve um ponto BEM longe ao longo do
-- raio da câmera, que não reflete a mira de verdade (mesmo problema do
-- "olhar pra cima", só que por PITCH lá e por essa borda aqui). Agora a
-- correção dispara nos DOIS casos — pitch íngreme OU mouse.Target nil (o
-- raycast não achou nada) — com a MESMA correção de sempre.
-- ⚠️ v23 — PEDIDO: "sempre que eu estou com a câmera sobrescrevendo o
-- espaço de uma hitbox, sempre dá problema em tudo, chute, ricochete,
-- etc". CAUSA RAIZ (achada revendo os fixes v10 do OutOfBoundsController e
-- do GKAreaUtil, que já tinham batido nesse MESMO problema antes, só que
-- só pras Parts que eles conheciam por nome): campoHit, GolAzul/Amarelo,
-- GKArea_* e as zonas OutLateral/OutFundo são todas "caixas matemáticas"
-- invisíveis (CanCollide=false) — mas cada uma delas só tem CanQuery
-- forçado pra false UMA VEZ, na hora que o servidor liga. Se você recria/
-- redimensiona qualquer uma dessas Parts DEPOIS (Part nova nasce com
-- CanQuery=true por padrão no Roblox), esse `mouse.Hit`/`mouse.Target`
-- (usado aqui pra mirar TODO chute) volta a poder acertar essa caixa
-- invisível em vez do gramado de verdade sempre que a câmera mirar perto/
-- dentro dela — dando um ponto de mira sem sentido (bola trava, sai fraca,
-- "ricocheteia", etc. — nada disso é física de verdade, é mira errada).
--
-- Em vez de confiar que toda caixa dessas (atuais E futuras, qualquer
-- sistema novo que você criar do mesmo jeito) sempre vai estar com
-- CanQuery=false, a mira agora DESCONFIA de qualquer coisa que pareça uma
-- dessas caixas — mesmo sinal que TODAS elas sempre têm nesse jogo:
-- CanCollide=false (nunca deveriam ser "sólidas"). Se o mouse acertar uma
-- Part assim, trata como se não tivesse acertado nada (mesmo fallback de
-- sempre) em vez de usar aquele ponto.
-- ⚠️ v44 FIX — "eu mirei exatamente no canto superior esquerdo e ela subiu
-- demais a mira."
--
-- CAUSA RAIZ (medida no Studio): a Part do gol (GolAzul / GolAmarelo) é a
-- HITBOX de gol — 18.7 x 21 x 59.7 studs plantada bem na BOCA do gol, e com
-- CanCollide = FALSE. A regra `isProbablyMathOnlyHitbox` descartava QUALQUER
-- parte não-colidível como "o raio não acertou nada", então mirar dentro da
-- boca do gol — exatamente o que se faz pra mirar num canto — caía sempre no
-- fallback, nunca no ponto real.
--
-- E o fallback tinha um viés PRA CIMA embutido: ele devolve
-- `origem + direção * 20` partindo da CINTURA do jogador, mas quem calcula a
-- direção do chute é o servidor, a partir da BOLA, uns 3 studs mais embaixo.
-- A conta fica elevação = tan(θ) + 3/(20·cos θ): uma mira de 5° virava 13°.
-- Daí "subiu demais", e daí também ser pior quanto mais reta a mira.
--
-- DUAS CORREÇÕES:
--   1) O gol é um ALVO DE MIRA VÁLIDO. Acertar a hitbox do gol é o ponto de
--      mira mais preciso que existe — usa o ponto exato, sem fallback.
--   2) Quando o raio realmente não acerta nada, o fallback parte da BOLA, não
--      da cintura. Aí a direção que o servidor calcula é idêntica à do cursor,
--      em qualquer distância, e o viés some.
local ALVOS_DE_MIRA_VALIDOS = {
	[Config.BLUE_GOAL_NAME] = true,
	[Config.YELLOW_GOAL_NAME] = true,
}

local function isProbablyMathOnlyHitbox(part)
	if Config.KICK_TEST_MODE then return false end -- ⚠️ v23: modo de teste — mira crua, sem esse filtro (volta a confiar 100% no mouse.Target puro)
	if part and ALVOS_DE_MIRA_VALIDOS[part.Name] then return false end -- o gol É onde se mira
	return part ~= nil and part:IsA("BasePart") and part.CanCollide == false
end

-- ⚠️ NOVO FIX: "quando eu subo a mira, ela não vai pros lados de jeito
-- nenhum" — os dois fallbacks abaixo (steepPitch e rayMissedEverything)
-- usavam camera.CFrame.LookVector, que é a direção do CENTRO da tela, não
-- de onde o MOUSE está apontando. Sem Shift Lock (câmera livre, mira pelo
-- cursor — o modo padrão), levantar o cursor em direção ao céu faz
-- mouse.Hit não achar nada (sem chão/arquibancada ali pra acertar) e cair
-- num desses fallbacks — que, usando o centro da tela em vez do cursor,
-- IGNORAVAM completamente pra que lado o cursor tinha sido movido antes de
-- subir, travando o chute só na direção que a câmera olha. Com Shift Lock
-- ligado o cursor já fica travado no centro (mouse.X/Y = centro da tela),
-- então esse cálculo dá exatamente na mesma direção de antes — não muda
-- nada nesse modo, só corrige o modo de câmera livre.
-- ⚠️ v54 — MIRA NO MOBILE.
-- No celular NÃO existe cursor: `mouse.X`/`mouse.Y` ficam parados na
-- posição do ÚLTIMO TOQUE, e `mouse.Target`/`mouse.Hit` apontam pra onde
-- esse toque caiu. Resultado prático: o jogador de celular não tinha como
-- mirar — o chute saía na direção de onde ele tocou pra girar a câmera (ou
-- de onde apertou um botão), não pra onde estava olhando.
--
-- A convenção de mira em terceira pessoa no mobile é o CENTRO DA TELA, que
-- é justamente pra onde a câmera aponta e o que o jogador enxerga. Então no
-- mobile a mira vira: raio pelo centro da tela + raycast de verdade pra
-- achar o ponto no mundo (não dá pra usar mouse.Hit, que segue o toque).
--
-- O caminho de PC fica IDÊNTICO ao que já estava — todo o ajuste fino de
-- mira feito até aqui (v26/v44) continua valendo sem nenhuma mudança.
local function ehMobile()
	-- Mesma detecção que MobileControls.local.luau usa pra decidir se mostra
	-- os botões, pra os dois nunca discordarem sobre o que é um celular.
	return UserInputService.TouchEnabled and not UserInputService.MouseEnabled
end

-- Ponto da TELA de onde a mira parte.
local function pontoDeMiraNaTela()
	if ehMobile() then
		local v = camera.ViewportSize
		return v.X / 2, v.Y / 2
	end
	return mouse.X, mouse.Y
end

-- Raycast do mobile: o equivalente ao mouse.Target/mouse.Hit do PC, só que
-- pelo centro da tela. Ignora personagens pra a mira não "grudar" em quem
-- estiver na frente.
local paramsMiraMobile = RaycastParams.new()
paramsMiraMobile.FilterType = Enum.RaycastFilterType.Exclude
paramsMiraMobile.IgnoreWater = true

local function miraMobileNoMundo()
	local x, y = pontoDeMiraNaTela()
	local ray = camera:ScreenPointToRay(x, y)

	local excluir = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(excluir, p.Character) end
	end
	local sombra = workspace:FindFirstChild("SombraDaBola")
	if sombra then table.insert(excluir, sombra) end
	paramsMiraMobile.FilterDescendantsInstances = excluir

	local batida = workspace:Raycast(ray.Origin, ray.Direction * 2000, paramsMiraMobile)
	if batida then
		return batida.Instance, batida.Position
	end
	return nil, nil
end

local function getMouseLookVector()
	local ray = camera:ScreenPointToRay(pontoDeMiraNaTela())
	local dir = ray.Direction
	if dir.Magnitude < 0.001 then return camera.CFrame.LookVector end
	return dir.Unit
end

local function computeAimPointAntigo()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local origin = root and root.Position or camera.CFrame.Position

	local lookVector = getMouseLookVector()
	local steepPitch = math.abs(lookVector.Y) > AIM_PITCH_STEEP_THRESHOLD

	-- ⚠️ v26 FIX — ACHADO FINALMENTE (revisando o v23 de novo com calma):
	-- essa fórmula abaixo (flatLook*20 + 300*lookVector.Y) foi desenhada
	-- SÓ pra pitch ÍNGREME de verdade (câmera quase reta pra cima/baixo,
	-- |Y| > 0.85) — nesse caso extremo, multiplicar por 300 faz sentido
	-- (dá um arremesso vertical grande de propósito). O v23 juntou essa
	-- MESMA fórmula também pro caso "mouse acertou uma hitbox e foi
	-- ignorado" (rayMissedEverything) — só que aí a câmera pode estar numa
	-- inclinação NORMAL (Y tipo -0.2, -0.3, olhando só um pouco pra baixo
	-- pra mirar no chão) e 300 * -0.3 = -90 STUDS abaixo do jogador. O
	-- chute então mirava um ponto ABSURDAMENTE embaixo da terra, saía quase
	-- reto pra baixo, batia no chão nos PRÓPRIOS PÉS e "morria" ali —
	-- exatamente o "bate numa parede na minha frente e trava" que você
	-- descreveu, e o motivo de nenhum diagnóstico de colisão/corpo nunca
	-- ter pegado nada: a mira é que saía errada, a física só obedecia.
	-- Isso explica tudo: sem campoHit (ou qualquer hitbox no caminho da
	-- mira), o mouse acerta o gramado de verdade normalmente e esse
	-- fallback nunca era usado — com uma hitbox no caminho, TODO chute
	-- naquela direção virava esse fallback quebrado.
	--
	-- Agora os dois casos são separados: pitch íngreme de verdade continua
	-- com a fórmula de sempre (validada há muito tempo); "mira acertou uma
	-- hitbox ou nada" ganha um fallback BEM mais simples e seguro — mira
	-- na direção 3D real da câmera, sem multiplicador nenhum inventando
	-- altura.
	if steepPitch then
		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
		if flatLook.Magnitude < 0.05 then
			-- reto pra cima/baixo TOTAL: não tem "lado" nenhum pra mirar —
			-- usa pra onde o personagem está olhando (a curva nem se
			-- aplica nesse caso, ver o guard em applyCurve no servidor).
			flatLook = root and Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) or Vector3.new(0, 0, -1)
			if flatLook.Magnitude < 0.05 then flatLook = Vector3.new(0, 0, -1) end
		end
		flatLook = flatLook.Unit
		return origin + flatLook * 20 + Vector3.new(0, 300 * lookVector.Y, 0)
	end

	-- ⚠️ v54: no mobile o alvo vem do raycast pelo centro da tela; no PC,
	-- do mouse, exatamente como sempre foi.
	local alvoInstancia, alvoPonto
	if ehMobile() then
		alvoInstancia, alvoPonto = miraMobileNoMundo()
	else
		alvoInstancia = mouse.Target
		alvoPonto = mouse.Hit and mouse.Hit.Position
	end

	local rayMissedEverything = alvoInstancia == nil or isProbablyMathOnlyHitbox(alvoInstancia)
	if rayMissedEverything then
		-- ⚠️ v44: parte da BOLA, não da cintura — ver o comentário grande
		-- acima. É isso que tira o viés pra cima do chute.
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		local origemDoChute = (bola and bola.Position) or origin
		return origemDoChute + lookVector * 20
	end

	return alvoPonto or (origin + lookVector * 50)
end

-- ⚠️ v97 — MIRA PRECISA. PEDIDO: "aonde você estiver mirando, você clicou, é
-- pra ser perfeito... às vezes vai pra trás". A mira antiga (acima, fica de
-- reserva) usava o mouse.Hit do Roblox, que para no primeiro corpo na frente
-- do cursor (goleiro, zagueiro) e às vezes na grama entre você e a câmera
-- (chute pra trás). Agora é a MiraPrecisa, a MESMA da Hissatsu: gol = ponto
-- exato da boca do gol; fora dele, a primeira coisa sólida ignorando gente;
-- e nunca pra trás de quem chuta.
local MiraPrecisa = require(ReplicatedStorage:WaitForChild("MiraPrecisa"))

local function computeAimPoint()
	local x, y = pontoDeMiraNaTela()
	local ok, ponto = pcall(MiraPrecisa.Calcular, camera, x, y, { NuncaPraTras = true })
	if ok and typeof(ponto) == "Vector3" then return ponto end
	return computeAimPointAntigo()
end

-- ===== SPRINT =====
-- ⚠️ NOVO: REMOVIDO. PEDIDO: "Não haverá botão de corrida/sprint. O
-- personagem deve correr normalmente usando WASD, e sua velocidade será
-- determinada pelo atributo Velocidade." (ver getRunSpeed em
-- PlayerSystems.legacy.luau). O botão SPRINT do mobile saiu junto.

-- ===== SHIFT LOCK (tecla Ctrl) =====
-- É o Shift Lock nativo do Roblox reimplementado à mão numa tecla
-- diferente (Ctrl) — era porque Shift era o sprint (que não existe mais);
-- continua no Ctrl pra não mudar o costume de quem já joga. Não avisa o
-- servidor de nada, não mexe em WalkSpeed nem em nada da bola — só:
--   1) trava o mouse no centro da tela (câmera gira livre sem precisar
--      segurar botão nenhum, igual o Shift Lock nativo);
--   2) o personagem passa a olhar pra onde a câmera olha, em vez de virar
--      só quando você anda (permite estrafegar/mirar com o mouse livre).
-- É TOGGLE (aperta uma vez liga, aperta de novo desliga), igual o nativo
-- — não é "segurar".
local shiftLockEnabled = false

local function applyAutoRotate(character, enabled)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.AutoRotate = enabled
	end
end

-- ⚠️ v9 PEDIDO: "assim que o minigame [QTE de clique da Hissatsu] começar,
-- eu tiro o mouse de onde estava mirando... salve a mira, lance naquela
-- direção, pro minigame não atrapalhar nada". A mira JÁ é capturada e
-- travada no servidor ANTES do QTE começar (ver computeAimPoint em
-- HissatsuInput.local.luau, mandada junto com Remotes.UsePulse — o chute
-- sempre sai na direção de onde você estava mirando no instante do
-- aperto, não importa o que o mouse faça depois). O problema real era
-- outro: com Shift Lock ligado, o mouse fica PRESO no centro da tela —
-- impossível clicar nos alvos que aparecem espalhados na tela pro QTE de
-- Tap. mouseLockSuspended destrava o cursor temporariamente enquanto um
-- QTE de clique estiver na tela (ver HissatsuQTEWindow.luau) e restaura o
-- Shift Lock de antes assim que ele fechar.
local mouseLockSuspended = false

local function applyMouseLockState()
	if mouseLockSuspended then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	else
		UserInputService.MouseBehavior = shiftLockEnabled and Enum.MouseBehavior.LockCenter or Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = not shiftLockEnabled
	end
end

local suspensoDesde = 0
_G.SetMouseLockSuspendedForQTE = function(suspended)
	suspended = suspended and true or false
	if mouseLockSuspended == suspended then return end
	mouseLockSuspended = suspended
	suspensoDesde = os.clock()
	applyMouseLockState()
end

local function setShiftLock(enabled)
	if shiftLockEnabled == enabled then return end
	shiftLockEnabled = enabled

	applyMouseLockState()

	applyAutoRotate(player.Character, not enabled)
end

player.CharacterAdded:Connect(function(character)
	-- garante que um respawn não deixe o AutoRotate "preso" no estado
	-- errado se o Shift Lock já estava ligado antes de morrer
	applyAutoRotate(character, not shiftLockEnabled)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == KEYS.ShiftLock then
		setShiftLock(not shiftLockEnabled)
	end
end)

-- ⚠️ MOBILE: botão de Shift Lock (é toggle, igual a tecla Ctrl).
_G.MobileToggleShiftLock = function()
	setShiftLock(not shiftLockEnabled)
end

-- O servidor controla a rotação sozinho (via CFrame) durante uma finta ou
-- o lunge do carrinho — se o Shift Lock também tentar girar o boneco pra
-- câmera nesse meio tempo, os dois brigam pela mesma rotação (um no
-- cliente, um no servidor) e o boneco "teleporta a cara" entre as duas
-- direções. `Remotes.SuppressShiftLockRotation` avisa por quantos
-- segundos soltar a rotação; o Shift Lock volta a girar normal assim que
-- a janela passa.
local rotationSuppressedUntil = 0

Remotes.SuppressShiftLockRotation.OnClientEvent:Connect(function(duration)
	if typeof(duration) == "number" and duration > 0 then
		rotationSuppressedUntil = math.max(rotationSuppressedUntil, tick() + duration)
	end
end)

-- Gira o personagem pra onde a câmera olha enquanto o Shift Lock estiver
-- ligado. Só mexe na ROTAÇÃO (a posição usada é a posição atual do
-- personagem no próprio frame), então não interfere em nada do
-- movimento/física — o Humanoid continua cuidando de andar normalmente,
-- só não gira mais sozinho pra direção do movimento (AutoRotate=false).
--
-- ⚠️ v84 — PEDIDO: "atualmente tem um delay pra você efetivamente girar o
-- personagem, remova completamente esse delay". Eram DOIS atrasos:
--   1) um Lerp suavizado (responsividade 14) — a 60fps o corpo só cobria
--      ~21% do ângulo por frame, levando ~0.2s pra alcançar a câmera;
--   2) rodava em RenderStepped, que pode executar ANTES do script de
--      câmera atualizar naquele frame — girando pra onde a câmera ESTAVA
--      no frame anterior (1 frame sempre atrasado).
-- Agora a rotação é aplicada POR INTEIRO (sem Lerp) e amarrada ao
-- BindToRenderStep logo DEPOIS da prioridade de câmera, lendo o CFrame
-- da câmera já atualizado do próprio frame — igual o Shift Lock nativo.
RunService:BindToRenderStep("FootballShiftLockRotation", Enum.RenderPriority.Camera.Value + 1, function()
	-- ⚠️ v108 — PEDIDO: "às vezes eu ativo o Ctrl e tento mexer pro lado e pro
	-- outro e ele não mexe a tela, fica travado, como se a trava não estivesse
	-- ativa". A trava só era aplicada UMA vez, no aperto do Ctrl — qualquer coisa
	-- que devolvesse o mouse pro modo normal depois (o script de câmera do Roblox
	-- ao soltar o botão direito, o replay de gol, o fim de uma cutscene, a janela
	-- de QTE) desfazia a trava calada e ela nunca mais voltava. Agora ela é
	-- REAFIRMADA todo quadro enquanto estiver ligada (fora do QTE de clique e das
	-- cutscenes, que precisam do mouse livre). E a suspensão do QTE se solta
	-- sozinha se ficar presa mais de 10s.
	if mouseLockSuspended and os.clock() - suspensoDesde > 10 then
		mouseLockSuspended = false
		applyMouseLockState()
	end
	if shiftLockEnabled and not mouseLockSuspended and not _G.HissatsuCutsceneLocal
		and camera.CameraType ~= Enum.CameraType.Scriptable then
		if UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
		if UserInputService.MouseIconEnabled then
			UserInputService.MouseIconEnabled = false
		end
	end
	if not shiftLockEnabled then return end
	if tick() < rotationSuppressedUntil then return end -- finta/carrinho em andamento: não briga pela rotação
	if os.clock() < (_G.CorpoTravadoAte or 0) then return end -- ⚠️ v104: caído/levantando do carrinho
	if _G.HissatsuCutsceneLocal then return end -- ⚠️ v87: cutscene de Hissatsu move o corpo sozinha

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local lookVector = camera.CFrame.LookVector
	local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
	if flatLook.Magnitude < 0.001 then return end

	root.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook.Unit)
end)

-- ⚠️ v104 — CORPO TRAVADO no carrinho (ver _G.CorpoTravadoAte em
-- AnimadorProcedural): enquanto o personagem está no chão ou levantando,
-- o comando de andar é zerado e o AutoRotate desligado — nem WASD nem a
-- câmera giram o corpo. Roda DEPOIS do módulo de controle (prioridade de
-- Input), então o Move(zero) daqui é o que vale no quadro. O avanço do
-- carrinho em si é feito pelo servidor (CFrame), então continua igual.
local corpoEstavaTravado = false
RunService:BindToRenderStep("FootballCorpoTravado", Enum.RenderPriority.Input.Value + 1, function()
	local travado = os.clock() < (_G.CorpoTravadoAte or 0)
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	if travado then
		humanoid.AutoRotate = false
		humanoid:Move(Vector3.zero, false)
		humanoid.Jump = false
	elseif corpoEstavaTravado then
		humanoid.AutoRotate = not shiftLockEnabled
	end
	corpoEstavaTravado = travado
end)

-- ===== POSSE DE BOLA (recebida do servidor) =====
local hasPossession = false
Remotes.PossessionChanged.OnClientEvent:Connect(function(playerWithBall, gainedPossession)
	if playerWithBall == player then
		hasPossession = gainedPossession
	elseif hasPossession and playerWithBall ~= player then
		hasPossession = false
	end
end)

-- ⚠️ v86: o Q é drible COM a bola e carrinho SEM ela — o DribbleInput
-- pergunta aqui pra não disparar uma finta que o servidor só ia recusar.
_G.FootballHasPossession = function()
	return hasPossession
end

-- ===== DESLOCAMENTO SEM TRAVAR (drible e dash) — ⚠️ v86 =====
-- PEDIDO: "Não precisa travar o personagem durante o drible... O drible vai
-- só mover o personagem, só que pode deixar ele continuando andando." O
-- servidor manda QUANTO deslocar e em QUANTO TEMPO (Remotes.ApplyDisplacement)
-- e este cliente — que é quem simula a física do próprio personagem — soma o
-- pedaço de cada quadro à posição, por cima do andar normal do Humanoid. O
-- WASD, o pulo e a rotação continuam funcionando durante todo o movimento.
-- Mesma curva de antes (ease-out cúbica: sai rápido e assenta suave), que o
-- servidor também usa pra levar a bola junto.
local deslocamento = nil -- { Offset, Duracao, Inicio, Aplicado }

Remotes.ApplyDisplacement.OnClientEvent:Connect(function(offset, duracao)
	if typeof(offset) ~= "Vector3" or typeof(duracao) ~= "number" or duracao <= 0 then
		deslocamento = nil -- duração 0 = cancelar
		return
	end
	deslocamento = { Offset = offset, Duracao = duracao, Inicio = os.clock(), Aplicado = 0 }
end)

RunService.Heartbeat:Connect(function()
	local d = deslocamento
	if not d then return end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	-- atordoado (WalkSpeed 0), caído (ragdoll/PlatformStand) ou morto: o
	-- empurrão acaba ali mesmo, senão o corpo deslizaria parado no chão
	if not root or not humanoid or humanoid.Health <= 0
		or humanoid.WalkSpeed <= 0 or humanoid.PlatformStand then
		deslocamento = nil
		return
	end

	local alpha = math.clamp((os.clock() - d.Inicio) / d.Duracao, 0, 1)
	local eased = 1 - (1 - alpha) ^ 3
	local passo = d.Offset * (eased - d.Aplicado)
	d.Aplicado = eased
	root.CFrame += passo

	if alpha >= 1 then deslocamento = nil end
end)

-- ===== TOQUE ESPECIAL: barra de força do chute =====
local chargeGui = Instance.new("ScreenGui")
chargeGui.Name = "KickChargeGui"
chargeGui.ResetOnSpawn = false
chargeGui.Parent = playerGui

local chargeBackground = Instance.new("Frame")
chargeBackground.Size = UDim2.new(0, 220, 0, 18)
chargeBackground.Position = UDim2.new(0.5, 0, 0.85, 0)
chargeBackground.AnchorPoint = Vector2.new(0.5, 0.5)
chargeBackground.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
chargeBackground.BackgroundTransparency = 0.3
chargeBackground.Visible = false
chargeBackground.Parent = chargeGui
Instance.new("UICorner", chargeBackground).CornerRadius = UDim.new(1, 0)

local chargeFill = Instance.new("Frame")
chargeFill.Size = UDim2.new(0, 0, 1, 0)
chargeFill.BackgroundColor3 = Color3.fromRGB(85, 255, 127)
chargeFill.BorderSizePixel = 0
chargeFill.Parent = chargeBackground
Instance.new("UICorner", chargeFill).CornerRadius = UDim.new(1, 0)

local function updateChargeBar(alpha)
	chargeFill.Size = UDim2.new(alpha, 0, 1, 0)
	chargeFill.BackgroundColor3 = Color3.fromHSV(0.34 - 0.34 * alpha, 0.85, 1)
end

-- ===== CHUTE (também serve de PASSE e VOLEIO — segurar botão esquerdo pra
-- carregar força; a posição do mouse em relação à bola na tela decide a
-- curva do chute). Não exige mais posse: se a bola estiver no ar e ao
-- alcance, o servidor trata como voleio mesmo sem domínio prévio. =====
local isCharging = false
local currentForce = Config.KICK_MIN_FORCE
local chargeConnection = nil

local function startCharging()
	if isCharging then return end
	isCharging = true
	currentForce = Config.KICK_MIN_FORCE
	chargeBackground.Visible = true
	updateChargeBar(0)
	Remotes.UpdateKickCharging:FireServer(true) -- servidor reduz o WalkSpeed enquanto carrega (ver PlayerSystems.lua)
	chargeConnection = RunService.Heartbeat:Connect(function(dt)
		currentForce = math.min(Config.KICK_MAX_FORCE, currentForce + Config.KICK_CHARGE_RATE * dt)
		local alpha = (currentForce - Config.KICK_MIN_FORCE) / (Config.KICK_MAX_FORCE - Config.KICK_MIN_FORCE)
		updateChargeBar(alpha)
	end)
end

-- ⚠️ v5.4 — INSTINTO "METAVISÃO": pra desenhar a trajetória PREVISTA a
-- partir da mira atual enquanto o jogador carrega o chute (não só reagir
-- à bola já em movimento), InstinctTrajectorySight.local.luau precisa
-- saber se está carregando, com quanta força, e pra onde está mirando —
-- tudo isso só existe aqui. _G é compartilhado entre LocalScripts do
-- mesmo cliente (igual o servidor já faz com _G.CheckInstinct etc.), sem
-- precisar de Remote nem acoplar os dois scripts.
_G.GetKickChargeInfo = function()
	return {
		-- ⚠️ v5.4 FIX: a prévia de mira da Metavisão (ver
		-- InstinctTrajectorySight.local.luau) aparecia mesmo segurando o
		-- botão SEM estar com a bola — não faz sentido prever "pra onde a
		-- bola iria" quando você nem vai chutá-la (só voleio conta, e
		-- voleio precisa da bola no ar perto, não é "segurar o botão à
		-- toa"). Agora só reporta "carregando" com posse de verdade.
		Charging = isCharging and hasPossession,
		Force = currentForce,
		AimPoint = computeAimPoint(),
	}
end

local function releaseKick()
	if not isCharging then return end
	isCharging = false
	chargeBackground.Visible = false
	if chargeConnection then
		chargeConnection:Disconnect()
		chargeConnection = nil
	end
	Remotes.UpdateKickCharging:FireServer(false)
	-- ⚠️ v84: sem spin — o chute normal sai reto na direção mirada (ver o
	-- comentário no final de Remotes.KickBall em BallController).
	-- ⚠️ v105: manda se está no ar — voleio (sem posse) só vale pulando
	Remotes.KickBall:FireServer(currentForce, computeAimPoint(), _G.EstouNoAr and _G.EstouNoAr() or false)
end

-- ===== ⚠️ v105 — CABEÇADA E VOLEIO NO AR =====
-- PEDIDO: "tirar a cabeçada com T. A bola tá no ar, numa altura certa de você
-- e você clicou no botão de chute: cabeçada. A bola mais abaixo da cabeça:
-- voleio. Só vale se você estiver pulando. Se estiver SEGURANDO o botão de
-- chute antes, ele prefere o voleio (a cabeçada é instantânea). Sem segurar,
-- recebeu o passe, precisa reagir rápido: aperta e dá a cabeçada na hora, se
-- estiver na altura certa; senão um voleio fraco."
--   • segurando o chute e solta no ar  -> voleio com a força carregada
--     (releaseKick acima, o servidor trata como voleio);
--   • toque rápido no ar, sem posse    -> acaoAerea: bola na faixa da cabeça
--     = cabeçada instantânea; mais baixa = voleio fraco.
_G.EstouNoAr = function()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false end
	local estado = humanoid:GetState()
	return humanoid.FloorMaterial == Enum.Material.Air
		or estado == Enum.HumanoidStateType.Jumping or estado == Enum.HumanoidStateType.Freefall
end

-- ⚠️ v108: a bola está na faixa da cabeça e ao alcance? (mesma régua do servidor)
local function bolaNaAlturaDaCabeca()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if not root or not bola then return false end
	local rel = bola.Position - root.Position
	local horizontal = Vector3.new(rel.X, 0, rel.Z).Magnitude
	return rel.Y >= (Config.HEADER_ALTURA_MIN_NO_AR or 1.2) and rel.Y <= Config.HEADER_MAX_BALL_HEIGHT
		and horizontal <= Config.HEADER_RANGE
end

local function acaoAerea()
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if not root or not bola then return end
	local rel = bola.Position - root.Position
	local horizontal = Vector3.new(rel.X, 0, rel.Z).Magnitude
	-- faixa da cabeça: do ombro pra cima (mesma régua de altura do servidor,
	-- que mede a partir do HumanoidRootPart)
	local alturaCabeca = (Config.HEADER_ALTURA_MIN_NO_AR or 1.2)
	if rel.Y >= alturaCabeca and rel.Y <= Config.HEADER_MAX_BALL_HEIGHT and horizontal <= Config.HEADER_RANGE then
		Remotes.AttemptHeader:FireServer(computeAimPoint())
	else
		Remotes.KickBall:FireServer(Config.VOLLEY_FRACO_FORCA or 55, computeAimPoint(), true)
	end
end
_G.AcaoAerea = acaoAerea

-- ⚠️ v108/v109 — METAVISÃO dos outros: com a bola no pé, manda pra onde está
-- mirando — ⚠️ v109: TODO QUADRO (pedido: "tem que atualizar a cada instante;
-- antes tinha uma travinha até saber o próximo"), pelo evento não-confiável.
-- É exatamente a mesma mira do chute (mouse no PC, centro da tela no mobile),
-- com ou sem a trava do Ctrl.
RunService.RenderStepped:Connect(function()
	if not hasPossession then return end
	local ok, ponto = pcall(computeAimPoint)
	if ok and typeof(ponto) == "Vector3" then
		Remotes.MiraDoDonoU:FireServer(ponto)
	end
end)

-- Se o personagem morrer/resetar no meio de uma carga de chute, sem isso
-- o servidor ficaria achando que o personagem novo ainda está
-- "carregando" (WalkSpeed preso mais devagar pra sempre).
player.CharacterAdded:Connect(function()
	if isCharging then
		isCharging = false
		chargeBackground.Visible = false
		if chargeConnection then
			chargeConnection:Disconnect()
			chargeConnection = nil
		end
		Remotes.UpdateKickCharging:FireServer(false)
	end
end)

-- ⚠️ MOBILE: não existe MouseButton1 em celular (toque vira
-- UserInputType.Touch, não MouseButton1) — sem isso o chute carregado
-- não tinha NENHUMA forma de disparar no mobile. Pra não brigar com o
-- joystick de movimento (fica sempre no lado ESQUERDO da tela, criado
-- pelo Roblox por cima de qualquer toque ali), só conta como "chute" um
-- toque que começa no lado DIREITO da tela — igual ao mouse, a mira
-- (computeAimPoint) segue esse toque em tempo real (mouse.Hit acompanha
-- arrasto de toque, o Roblox já faz isso sozinho pra câmera 3ª pessoa).
-- ⚠️ v55 — O CHUTE NO MOBILE VIROU BOTÃO DEDICADO.
--
-- O QUE HAVIA: no celular, "chutar" era tocar na metade DIREITA da tela.
-- Só que essa metade é exatamente onde o Roblox põe o giro de câmera —
-- então girar a câmera carregava e soltava um chute junto, e não dava pra
-- olhar em volta sem chutar. Além disso, com a mira agora pelo centro da
-- tela (v54), arrastar pra mirar é a ação MAIS comum que existe: o
-- conflito só pioraria.
--
-- AGORA: no mobile, toque na tela não chuta mais nada — a tela inteira é
-- câmera/mira, e quem chuta é o botão CHUTE (segurar carrega, soltar
-- chuta), igual o botão esquerdo do mouse no PC. Ver _G.MobileKickStart/
-- _G.MobileKickRelease logo abaixo e o botão em MobileControls.
--
-- No PC nada muda: continua sendo MouseButton1.
local function isShootPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1
end

-- ⚠️ v15 — PEDIDO: "o tackle... pra direita, pra esquerda, pra cima, pra
-- diagonal". A direção do carrinho é simplesmente PRA ONDE VOCÊ ESTÁ INDO
-- no momento do aperto: Humanoid.MoveDirection já é o vetor do movimento
-- em espaço de mundo, então W/A/S/D e as diagonais saem de graça, e o
-- analógico do celular também. Parado (MoveDirection zerado) devolve nil,
-- e aí o servidor usa pra onde o personagem está apontado (⚠️ v84: não
-- mira mais sozinho na bola — ver startTackleDash em BallController).
local function currentTackleDirection()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return nil end
	local move = humanoid.MoveDirection
	if move.Magnitude < 0.1 then return nil end
	return move
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if isShootPress(input) then
		-- ⚠️ v105: no ar, sem a bola e sem já estar carregando = reação rápida
		-- ⚠️ v108: e também NO CHÃO se a bola estiver na altura da cabeça —
		-- "clicou na altura certa, ele dá a cabeçada automaticamente em vez do chute"
		if not hasPossession and not isCharging and (_G.EstouNoAr() or bolaNaAlturaDaCabeca()) then
			acaoAerea()
		else
			startCharging()
		end
	elseif input.KeyCode == KEYS.Tackle then
		-- ⚠️ v86 — PEDIDO: "o carrinho, na verdade, é o Q, quando você não
		-- estiver com a bola". Com a bola, o mesmo Q é o drible direcional
		-- (DribbleInput.local.luau). Direção pelo WASD, cooldown
		-- Config.TACKLE_COOLDOWN, custo TACKLE_STAMINA_COST — o carrinho de
		-- sempre, só mudou de tecla.
		-- ⚠️ v5.4 FIX: usa a checagem de área (IsEffectiveGK), não o Role:
		-- goleiro fora da própria área é jogador de linha normal; dentro dela
		-- o Q vira mergulho (GKInput.local.luau).
		-- Combo de Pulso aberto: o Q é um passo do combo (PulseInput), não carrinho.
		if not hasPossession and not GKAreaUtil.IsEffectiveGK(player)
			and not player:GetAttribute("PulseComboActive") then
			Remotes.AttemptTackle:FireServer(currentTackleDirection())
		end
	elseif input.KeyCode == KEYS.Dash then
		-- ⚠️ v86 — PEDIDO: "o F pode ser utilizado para dar um dash, que é
		-- meio que um avanço para frente". Arranque curto na direção do WASD
		-- (parado = pra frente do personagem), com ou sem bola; não rouba nem
		-- disputa nada. Goleiro dentro da área: F é a saída do gol (GKInput).
		if not GKAreaUtil.IsEffectiveGK(player) then
			Remotes.AttemptDash:FireServer(currentTackleDirection())
		end
	end
end)

-- ⚠️ MOBILE: botões de Carrinho, Dash e Cabeçada (Q/F/T não existem em
-- celular). Reaproveitam exatamente a mesma checagem de cima.
_G.MobileTackle = function()
	if not hasPossession and not GKAreaUtil.IsEffectiveGK(player) then
		Remotes.AttemptTackle:FireServer(currentTackleDirection())
	end
end

_G.MobileDash = function() -- ⚠️ v86
	if not GKAreaUtil.IsEffectiveGK(player) then
		Remotes.AttemptDash:FireServer(currentTackleDirection())
	end
end

_G.MobileHeader = function()
	-- ⚠️ v105: o botão de cabeçada do celular vira a reação no ar (só pulando)
	if _G.EstouNoAr() then acaoAerea() end
end

-- ⚠️ v55 — Chute no mobile (ver o comentário em isShootPress). Segurar o
-- botão carrega a força, soltar chuta — exatamente o mesmo par
-- startCharging/releaseKick que o clique do mouse usa no PC, então força,
-- mira e barra de carga se comportam igual nas duas plataformas.
_G.MobileKickStart = function()
	if not hasPossession and not isCharging and _G.EstouNoAr() then
		acaoAerea() -- ⚠️ v105: mesmo comportamento do clique
		return
	end
	startCharging()
end

_G.MobileKickRelease = function()
	releaseKick()
end

UserInputService.InputEnded:Connect(function(input)
	-- ⚠️ v55: só o mouse. O toque não solta mais chute nenhum — no mobile
	-- quem faz isso é o botão CHUTE (_G.MobileKickRelease). Manter o Touch
	-- aqui cancelaria o carregamento do botão no instante em que o jogador
	-- encostasse na tela pra girar a câmera.
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		releaseKick()
	end
end)

-- =========================================================
-- UI - CAMINHOS (ajuste aqui se sua hierarquia for diferente)
-- =========================================================

-- ===== BARRA DE STAMINA (criada por código, sem depender de UI pronta) =====
local staminaGui = Instance.new("ScreenGui")
staminaGui.Name = "StaminaGui"
staminaGui.ResetOnSpawn = false
staminaGui.Parent = playerGui

local staminaBackground = Instance.new("Frame")
staminaBackground.Size = UDim2.new(0, 200, 0, 14)
staminaBackground.Position = UDim2.new(0, 20, 0, 20)
staminaBackground.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
staminaBackground.BackgroundTransparency = 0.3
staminaBackground.Parent = staminaGui
Instance.new("UICorner", staminaBackground).CornerRadius = UDim.new(1, 0)

local staminaFill = Instance.new("Frame")
staminaFill.Size = UDim2.new(1, 0, 1, 0)
staminaFill.BackgroundColor3 = Color3.fromRGB(85, 170, 255)
staminaFill.BorderSizePixel = 0
staminaFill.Parent = staminaBackground
Instance.new("UICorner", staminaFill).CornerRadius = UDim.new(1, 0)

task.spawn(function()
	local staminaValue = player:WaitForChild("Stamina", 10)
	local maxStaminaValue = player:WaitForChild("MaxStamina", 10)
	if not staminaValue or not maxStaminaValue then return end

	local function update()
		local max = maxStaminaValue.Value > 0 and maxStaminaValue.Value or 100
		local alpha = math.clamp(staminaValue.Value / max, 0, 1)
		staminaFill.Size = UDim2.new(alpha, 0, 1, 0)
		-- fica vermelha quando a stamina está baixa, como aviso visual
		staminaFill.BackgroundColor3 = alpha < 0.25
			and Color3.fromRGB(255, 85, 85)
			or Color3.fromRGB(85, 170, 255)
	end

	staminaValue.Changed:Connect(update)
	maxStaminaValue.Changed:Connect(update)
	update()
end)

-- ===== PLACAR (criado por código, mesmo padrão da stamina — não depende
-- de UI pronta no Explorer). Atualizado pelo UpdateMatchState (que já
-- carrega o placar a cada segundo) e reforçado no GoalScored pra refletir
-- o gol imediatamente, sem esperar o próximo tick do timer. =====
local TEAM_A = Config.TEAM_NAMES[1] or "Time A"
local TEAM_B = Config.TEAM_NAMES[2] or "Time B"

-- ⚠️ v103 — PLACAR + TIMER UNIFICADOS. PEDIDO: "melhore esse HUD de timer e
-- pontuação — hoje em dia um sobrescreve o outro — unifique eles pra não ter
-- sobrescrição e melhore, deixe bem bonito." O timer era uma peça do Studio
-- (Menu.Timer) no MESMO lugar do placar criado aqui. Agora é UM painel só,
-- estilo placar de transmissão: [cor | TIME A  2] [ 03:12 ] [1  TIME B | cor].
-- O timer antigo do Studio fica escondido (ver esconderTimerAntigo).
local COR_PAINEL_PLACAR = Color3.fromRGB(13, 15, 22)
local COR_MEIO_PLACAR = Color3.fromRGB(21, 24, 34)
local COR_BORDA_PLACAR = Color3.fromRGB(34, 38, 52)
local COR_TEXTO_PLACAR = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_MEDIO_PLACAR = Color3.fromRGB(190, 197, 212)
local COR_ALERTA_PLACAR = Color3.fromRGB(255, 90, 80)

local function corDoTime(nome, padrao)
	local Teams = game:GetService("Teams")
	local time = Teams:FindFirstChild(nome)
	if time and time:IsA("Team") then return time.TeamColor.Color end
	return padrao
end
local COR_TIME_A = corDoTime(TEAM_A, Color3.fromRGB(60, 130, 255))
local COR_TIME_B = corDoTime(TEAM_B, Color3.fromRGB(255, 205, 50))

local scoreGui = Instance.new("ScreenGui")
scoreGui.Name = "ScoreGui"
scoreGui.ResetOnSpawn = false
scoreGui.IgnoreGuiInset = false
scoreGui.DisplayOrder = 5
scoreGui.Parent = playerGui

local PLACAR_W, PLACAR_H = 440, 54
local placar = Instance.new("Frame")
placar.Name = "Placar"
placar.AnchorPoint = Vector2.new(0.5, 0)
placar.Position = UDim2.new(0.5, 0, 0, 10)
placar.Size = UDim2.fromOffset(PLACAR_W, PLACAR_H)
placar.BackgroundColor3 = COR_PAINEL_PLACAR
placar.BackgroundTransparency = 0.08
placar.Parent = scoreGui
Instance.new("UICorner", placar).CornerRadius = UDim.new(0, 10)
local placarBorda = Instance.new("UIStroke")
placarBorda.Color = COR_BORDA_PLACAR
placarBorda.Thickness = 1
placarBorda.Parent = placar
-- encaixa em tela pequena (celular)
local placarEscala = Instance.new("UIScale")
placarEscala.Parent = placar
local function ajustarPlacar()
	local v = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if v and v.X > 0 then placarEscala.Scale = math.clamp((v.X - 24) / PLACAR_W, 0.6, 1.1) end
end
ajustarPlacar()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarPlacar) end

local LADO_W = (PLACAR_W - 120) / 2
local function ladoDoTime(nome, cor, esquerda)
	local lado = Instance.new("Frame")
	lado.Name = "Time" .. (esquerda and "A" or "B")
	lado.BackgroundTransparency = 1
	lado.Size = UDim2.fromOffset(LADO_W, PLACAR_H)
	lado.Position = esquerda and UDim2.fromOffset(0, 0) or UDim2.fromOffset(PLACAR_W - LADO_W, 0)
	lado.Parent = placar

	local faixa = Instance.new("Frame")
	faixa.BackgroundColor3 = cor
	faixa.BorderSizePixel = 0
	faixa.AnchorPoint = Vector2.new(esquerda and 0 or 1, 0.5)
	faixa.Position = UDim2.new(esquerda and 0 or 1, esquerda and 10 or -10, 0.5, 0)
	faixa.Size = UDim2.fromOffset(5, 30)
	faixa.Parent = lado
	Instance.new("UICorner", faixa).CornerRadius = UDim.new(0, 3)

	local rotulo = Instance.new("TextLabel")
	rotulo.BackgroundTransparency = 1
	rotulo.Font = Enum.Font.GothamBlack
	rotulo.TextSize = 15
	rotulo.TextColor3 = COR_TEXTO_MEDIO_PLACAR
	rotulo.Text = maiusculas(nome)
	rotulo.TextXAlignment = esquerda and Enum.TextXAlignment.Left or Enum.TextXAlignment.Right
	rotulo.Size = UDim2.new(1, -78, 1, 0)
	rotulo.Position = esquerda and UDim2.fromOffset(24, 0) or UDim2.fromOffset(54, 0)
	rotulo.TextTruncate = Enum.TextTruncate.AtEnd
	rotulo.Parent = lado

	local gols = Instance.new("TextLabel")
	gols.Name = "Gols"
	gols.BackgroundTransparency = 1
	gols.Font = Enum.Font.GothamBlack
	gols.TextSize = 32
	gols.TextColor3 = COR_TEXTO_PLACAR
	gols.Text = "0"
	gols.AnchorPoint = Vector2.new(esquerda and 1 or 0, 0.5)
	gols.Position = UDim2.new(esquerda and 1 or 0, esquerda and -12 or 12, 0.5, 0)
	gols.Size = UDim2.fromOffset(44, PLACAR_H)
	gols.TextXAlignment = esquerda and Enum.TextXAlignment.Right or Enum.TextXAlignment.Left
	gols.Parent = lado
	local escalaGols = Instance.new("UIScale")
	escalaGols.Parent = gols
	return gols, escalaGols, faixa
end
local golsA, escalaGolsA = ladoDoTime(TEAM_A, COR_TIME_A, true)
local golsB, escalaGolsB = ladoDoTime(TEAM_B, COR_TIME_B, false)

-- relógio no meio
local meio = Instance.new("Frame")
meio.Name = "Relogio"
meio.AnchorPoint = Vector2.new(0.5, 0.5)
meio.Position = UDim2.fromScale(0.5, 0.5)
meio.Size = UDim2.fromOffset(112, 40)
meio.BackgroundColor3 = COR_MEIO_PLACAR
meio.Parent = placar
Instance.new("UICorner", meio).CornerRadius = UDim.new(0, 8)
local meioBorda = Instance.new("UIStroke")
meioBorda.Color = COR_BORDA_PLACAR
meioBorda.Thickness = 1
meioBorda.Parent = meio
local relogio = Instance.new("TextLabel")
relogio.Name = "Tempo"
relogio.BackgroundTransparency = 1
relogio.Size = UDim2.fromScale(1, 1)
relogio.Font = Enum.Font.GothamBlack
relogio.TextSize = 22
relogio.TextColor3 = COR_TEXTO_PLACAR
relogio.Text = "--:--"
relogio.Parent = meio
local relogioSub = Instance.new("TextLabel")
relogioSub.Name = "Legenda"
relogioSub.BackgroundTransparency = 1
relogioSub.AnchorPoint = Vector2.new(0.5, 0)
relogioSub.Position = UDim2.new(0.5, 0, 1, 2)
relogioSub.Size = UDim2.fromOffset(160, 14)
relogioSub.Font = Enum.Font.GothamBold
relogioSub.TextSize = 11
relogioSub.TextColor3 = COR_TEXTO_MEDIO_PLACAR
relogioSub.Text = ""
relogioSub.Parent = meio

local ultimoPlacar = { A = 0, B = 0 }
local function pulsarGols(label, escala, cor)
	escala.Scale = 1.5
	label.TextColor3 = cor
	TweenService:Create(escala, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(label, TweenInfo.new(1.2), { TextColor3 = COR_TEXTO_PLACAR }):Play()
end

local function updateScoreLabel(score)
	if typeof(score) ~= "table" then return end
	local a, b = score[TEAM_A] or 0, score[TEAM_B] or 0
	golsA.Text = tostring(a)
	golsB.Text = tostring(b)
	if a > ultimoPlacar.A then pulsarGols(golsA, escalaGolsA, COR_TIME_A) end
	if b > ultimoPlacar.B then pulsarGols(golsB, escalaGolsB, COR_TIME_B) end
	ultimoPlacar.A, ultimoPlacar.B = a, b
end

local function atualizarRelogio(timeRemaining, countdown)
	if countdown then
		relogio.Text = tostring(countdown)
		relogio.TextColor3 = COR_TEXTO_PLACAR
		relogioSub.Text = "COMEÇA EM"
		return
	end
	relogioSub.Text = ""
	local restante = math.max(math.floor(tonumber(timeRemaining) or 0), 0)
	relogio.Text = string.format("%02d:%02d", math.floor(restante / 60), restante % 60)
	if restante <= 30 and restante > 0 then
		relogio.TextColor3 = (restante % 2 == 0) and COR_ALERTA_PLACAR or COR_TEXTO_PLACAR
		meioBorda.Color = COR_ALERTA_PLACAR
	else
		relogio.TextColor3 = COR_TEXTO_PLACAR
		meioBorda.Color = COR_BORDA_PLACAR
	end
end

-- o timer antigo (peça do Studio, Menu.Timer) ficava em cima do placar
task.spawn(function()
	local menu = playerGui:WaitForChild("Menu", 10)
	local timerAntigo = menu and menu:WaitForChild("Timer", 5)
	if timerAntigo then
		if timerAntigo:IsA("GuiObject") then timerAntigo.Visible = false end
		for _, d in ipairs(timerAntigo:GetDescendants()) do
			if d:IsA("GuiObject") then d.Visible = false end
		end
	end
	-- os botões de trocar de time (peça do Studio) ficavam ATRÁS do placar:
	-- descem pra logo abaixo dele, menores, no mesmo visual
	local trocaTime = menu and menu:FindFirstChild("TeamChangeFrame")
	if trocaTime and trocaTime:IsA("GuiObject") then
		trocaTime.AnchorPoint = Vector2.new(0.5, 0)
		trocaTime.Position = UDim2.new(0.5, 0, 0, 10 + PLACAR_H + 8)
		trocaTime.Size = UDim2.fromOffset(260, 28)
		trocaTime.BackgroundTransparency = 1
		for i, nome in ipairs({ "BlueTeamButton", "YellowTeamButton" }) do
			local b = trocaTime:FindFirstChild(nome)
			if b and b:IsA("GuiButton") then
				b.AnchorPoint = Vector2.zero
				b.Position = UDim2.fromOffset((i - 1) * 136, 0)
				b.Size = UDim2.fromOffset(124, 28)
				b.BackgroundColor3 = COR_PAINEL_PLACAR
				b.BackgroundTransparency = 0.15
				if b:IsA("TextButton") then
					b.Font = Enum.Font.GothamBlack
					b.TextSize = 12
					b.TextScaled = false
					b.TextColor3 = i == 1 and COR_TIME_A or COR_TIME_B
					b.Text = "ENTRAR " .. maiusculas(i == 1 and TEAM_A or TEAM_B)
				end
				if not b:FindFirstChildOfClass("UICorner") then
					Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
				end
				local s = b:FindFirstChildOfClass("UIStroke") or Instance.new("UIStroke", b)
				s.Color = i == 1 and COR_TIME_A or COR_TIME_B
				s.Transparency = 0.5
				s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			end
		end
	end
end)

-- ---- Menu de troca de time ----
task.spawn(function()
	local teamFrame = waitForPath(playerGui, { "Menu", "TeamChangeFrame" }, 5)
	if not teamFrame then return end

	local blueButton = teamFrame:FindFirstChild("BlueTeamButton")
	local yellowButton = teamFrame:FindFirstChild("YellowTeamButton")

	if blueButton then
		blueButton.MouseButton1Click:Connect(function()
			Remotes.RequestTeamChange:FireServer("Azul")
		end)
	end
	if yellowButton then
		yellowButton.MouseButton1Click:Connect(function()
			Remotes.RequestTeamChange:FireServer("Amarelo")
		end)
	end
end)

-- ===== TOQUE ESPECIAL: tremor de câmera =====
local function shakeCamera(intensity, duration)
	local startTime = tick()
	local connection
	connection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime
		if elapsed >= duration then
			connection:Disconnect()
			return
		end
		local falloff = 1 - (elapsed / duration)
		local offset = Vector3.new(
			(math.random() - 0.5) * intensity * falloff,
			(math.random() - 0.5) * intensity * falloff,
			0
		)
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
end

-- ===== TOQUE ESPECIAL: tela de "GOL!" =====
local goalGui = Instance.new("ScreenGui")
goalGui.Name = "GoalGui"
goalGui.ResetOnSpawn = false
goalGui.Parent = playerGui

local goalLabel = Instance.new("TextLabel")
goalLabel.Size = UDim2.new(0, 500, 0, 100)
goalLabel.Position = UDim2.new(0.5, 0, 0.35, 0)
goalLabel.AnchorPoint = Vector2.new(0.5, 0.5)
goalLabel.BackgroundTransparency = 1
goalLabel.Text = "GOL!"
goalLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
goalLabel.TextStrokeTransparency = 0
goalLabel.TextScaled = true
goalLabel.Font = Enum.Font.GothamBlack
goalLabel.TextTransparency = 1
goalLabel.TextStrokeTransparency = 1
goalLabel.Parent = goalGui

-- ⚠️ v110 — PEDIDO: "o nome personalizado dos slots dentro do jogo": embaixo
-- do GOL! aparece quem marcou, com o nome do personagem (NomePersonagem).
local autorGolLabel = Instance.new("TextLabel")
autorGolLabel.Size = UDim2.new(0, 520, 0, 34)
autorGolLabel.Position = UDim2.new(0.5, 0, 0.35, 62)
autorGolLabel.AnchorPoint = Vector2.new(0.5, 0.5)
autorGolLabel.BackgroundTransparency = 1
autorGolLabel.Text = ""
autorGolLabel.TextColor3 = Color3.fromRGB(238, 241, 248)
autorGolLabel.TextSize = 26
autorGolLabel.Font = Enum.Font.GothamBlack
autorGolLabel.TextTransparency = 1
autorGolLabel.TextStrokeTransparency = 1
autorGolLabel.Parent = goalGui

local function playGoalCelebration(scorer)
	goalLabel.TextTransparency = 0
	goalLabel.TextStrokeTransparency = 0
	if typeof(scorer) == "Instance" and scorer:IsA("Player") then
		local nome = scorer:GetAttribute("NomePersonagem")
		if typeof(nome) ~= "string" or nome == "" then nome = scorer.DisplayName end
		autorGolLabel.Text = "de " .. maiusculas(nome)
		autorGolLabel.TextColor3 = scorer.Team and scorer.TeamColor.Color:Lerp(Color3.new(1, 1, 1), 0.35) or Color3.fromRGB(238, 241, 248)
		autorGolLabel.TextTransparency = 0
		autorGolLabel.TextStrokeTransparency = 0.2
	end
	goalLabel.Size = UDim2.new(0, 300, 0, 60)
	TweenService:Create(goalLabel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 500, 0, 100),
	}):Play()

	task.delay(1.4, function()
		local fadeOut = TweenService:Create(goalLabel, TweenInfo.new(0.5), {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
		})
		fadeOut:Play()
		TweenService:Create(autorGolLabel, TweenInfo.new(0.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

-- ===== HUD: contagem regressiva / timer / placar =====
Remotes.UpdateMatchState.OnClientEvent:Connect(function(timeRemaining, score, countdown)
	atualizarRelogio(timeRemaining, countdown) -- ⚠️ v103: relógio no placar unificado
	updateScoreLabel(score)
end)

Remotes.GoalScored.OnClientEvent:Connect(function(scoringTeam, scorer, score)
	playGoalCelebration(scorer)
	shakeCamera(0.6, 0.5)
	updateScoreLabel(score)
end)

-- ---- Resumo pós-partida (construído por código, sem depender de UI pronta) ----
local function createStatRow(icon, label, value, parent, order)
	local row = Instance.new("Frame")
	row.Name = "StatRow"
	row.Size = UDim2.new(1, 0, 0, 34)
	row.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	row.BackgroundTransparency = 0.94
	row.LayoutOrder = order
	row.Parent = parent
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.new(0, 30, 1, 0)
	iconLabel.Position = UDim2.new(0, 6, 0, 0)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = icon
	iconLabel.TextSize = 18
	iconLabel.Font = Enum.Font.Gotham
	iconLabel.Parent = row

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -100, 1, 0)
	nameLabel.Position = UDim2.new(0, 40, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = label
	nameLabel.TextColor3 = Color3.fromRGB(200, 200, 205)
	nameLabel.TextSize = 16
	nameLabel.Font = Enum.Font.Gotham
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Parent = row

	local valueLabel = Instance.new("TextLabel")
	valueLabel.Size = UDim2.new(0, 50, 1, 0)
	valueLabel.Position = UDim2.new(1, -56, 0, 0)
	valueLabel.BackgroundTransparency = 1
	valueLabel.Text = tostring(value)
	valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	valueLabel.TextSize = 18
	valueLabel.Font = Enum.Font.GothamBold
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Parent = row

	return row
end

local function buildSummaryUI()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MatchSummaryGUI"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "SummaryFrame"
	frame.Size = UDim2.new(0, 400, 0, 0)
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
	frame.Visible = false
	frame.Parent = screenGui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 18)
	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(255, 215, 0)
	frameStroke.Transparency = 0.55
	frameStroke.Thickness = 2
	frameStroke.Parent = frame
	local frameGradient = Instance.new("UIGradient")
	frameGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(36, 36, 46)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 16, 22)),
	})
	frameGradient.Rotation = 90
	frameGradient.Parent = frame

	local mainLayout = Instance.new("UIListLayout")
	mainLayout.SortOrder = Enum.SortOrder.LayoutOrder
	mainLayout.Padding = UDim.new(0, 0)
	mainLayout.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 22)
	padding.PaddingBottom = UDim.new(0, 22)
	padding.PaddingLeft = UDim.new(0, 24)
	padding.PaddingRight = UDim.new(0, 24)
	padding.Parent = frame

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "RESUMO DA PARTIDA"
	titleLabel.TextColor3 = Color3.fromRGB(150, 150, 158)
	titleLabel.TextSize = 14
	titleLabel.Font = Enum.Font.GothamMedium
	titleLabel.LayoutOrder = 1
	titleLabel.Parent = frame

	local resultLabel = Instance.new("TextLabel")
	resultLabel.Name = "ResultLabel"
	resultLabel.Size = UDim2.new(1, 0, 0, 46)
	resultLabel.BackgroundTransparency = 1
	resultLabel.TextSize = 32
	resultLabel.Font = Enum.Font.GothamBlack
	resultLabel.LayoutOrder = 2
	resultLabel.Parent = frame

	-- Badge de MVP: card dourado destacado (só some/apaga quando não é MVP)
	local mvpBadge = Instance.new("Frame")
	mvpBadge.Name = "MVPBadge"
	mvpBadge.Size = UDim2.new(1, 0, 0, 44)
	mvpBadge.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	mvpBadge.LayoutOrder = 3
	mvpBadge.Parent = frame
	Instance.new("UICorner", mvpBadge).CornerRadius = UDim.new(0, 10)
	local mvpGradient = Instance.new("UIGradient")
	mvpGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 236, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 190, 0)),
	})
	mvpGradient.Rotation = 90
	mvpGradient.Parent = mvpBadge
	local mvpLabel = Instance.new("TextLabel")
	mvpLabel.Name = "MVPLabel"
	mvpLabel.Size = UDim2.new(1, 0, 1, 0)
	mvpLabel.BackgroundTransparency = 1
	mvpLabel.Text = "👑  MVP DA PARTIDA"
	mvpLabel.TextColor3 = Color3.fromRGB(50, 35, 0)
	mvpLabel.TextSize = 18
	mvpLabel.Font = Enum.Font.GothamBlack
	mvpLabel.Parent = mvpBadge

	local spacerAfterResult = Instance.new("Frame")
	spacerAfterResult.Name = "SpacerA"
	spacerAfterResult.Size = UDim2.new(1, 0, 0, 14)
	spacerAfterResult.BackgroundTransparency = 1
	spacerAfterResult.LayoutOrder = 4
	spacerAfterResult.Parent = frame

	local rewardsRow = Instance.new("Frame")
	rewardsRow.Name = "RewardsRow"
	rewardsRow.Size = UDim2.new(1, 0, 0, 56)
	rewardsRow.BackgroundTransparency = 1
	rewardsRow.LayoutOrder = 5
	rewardsRow.Parent = frame
	local rewardsLayout = Instance.new("UIListLayout")
	rewardsLayout.FillDirection = Enum.FillDirection.Horizontal
	rewardsLayout.Padding = UDim.new(0, 10)
	rewardsLayout.Parent = rewardsRow

	local function buildRewardCard(icon, color)
		local card = Instance.new("Frame")
		card.Size = UDim2.new(0.5, -5, 1, 0)
		card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		card.BackgroundTransparency = 0.93
		card.Parent = rewardsRow
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

		local iconLabel = Instance.new("TextLabel")
		iconLabel.Size = UDim2.new(1, 0, 0, 20)
		iconLabel.Position = UDim2.new(0, 0, 0, 6)
		iconLabel.BackgroundTransparency = 1
		iconLabel.Text = icon
		iconLabel.TextSize = 18
		iconLabel.Font = Enum.Font.Gotham
		iconLabel.Parent = card

		local valueLabel = Instance.new("TextLabel")
		valueLabel.Name = "ValueLabel"
		valueLabel.Size = UDim2.new(1, 0, 0, 24)
		valueLabel.Position = UDim2.new(0, 0, 0, 26)
		valueLabel.BackgroundTransparency = 1
		valueLabel.TextColor3 = color
		valueLabel.TextSize = 20
		valueLabel.Font = Enum.Font.GothamBlack
		valueLabel.Parent = card

		return valueLabel
	end

	local moneyValueLabel = buildRewardCard("💰", Color3.fromRGB(255, 215, 0))
	local xpValueLabel = buildRewardCard("⭐", Color3.fromRGB(135, 206, 235))

	local spacerAfterRewards = Instance.new("Frame")
	spacerAfterRewards.Name = "SpacerB"
	spacerAfterRewards.Size = UDim2.new(1, 0, 0, 16)
	spacerAfterRewards.BackgroundTransparency = 1
	spacerAfterRewards.LayoutOrder = 6
	spacerAfterRewards.Parent = frame

	local statsContainer = Instance.new("Frame")
	statsContainer.Name = "StatsContainer"
	statsContainer.Size = UDim2.new(1, 0, 0, 120)
	statsContainer.AutomaticSize = Enum.AutomaticSize.Y
	statsContainer.BackgroundTransparency = 1
	statsContainer.LayoutOrder = 7
	statsContainer.Parent = frame
	local statsLayout = Instance.new("UIListLayout")
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 6)
	statsLayout.Parent = statsContainer

	local spacerAfterStats = Instance.new("Frame")
	spacerAfterStats.Name = "SpacerC"
	spacerAfterStats.Size = UDim2.new(1, 0, 0, 18)
	spacerAfterStats.BackgroundTransparency = 1
	spacerAfterStats.LayoutOrder = 8
	spacerAfterStats.Parent = frame

	local closeButton = Instance.new("TextButton")
	closeButton.Size = UDim2.new(1, 0, 0, 42)
	closeButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
	closeButton.Text = "FECHAR"
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.TextSize = 16
	closeButton.Font = Enum.Font.GothamBold
	closeButton.LayoutOrder = 9
	closeButton.AutoButtonColor = true
	closeButton.Parent = frame
	Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 10)

	closeButton.MouseButton1Click:Connect(function()
		frame.Visible = false
	end)

	return frame, resultLabel, moneyValueLabel, xpValueLabel, statsContainer, mvpBadge
end

-- ⚠️ v104: o resumo de fim de partida agora é o TelaFinalClient.local.luau
-- (estilo do lobby, com EMPATE). A tela antiga abaixo só roda se ele não
-- existir no place.
local telaFinalNova = script.Parent:FindFirstChild("TelaFinalClient") ~= nil
local summaryFrame, resultLabel, moneyValueLabel, xpValueLabel, statsContainer, mvpBadge = buildSummaryUI()

Remotes.ShowMatchSummary.OnClientEvent:Connect(function(data)
	if telaFinalNova then return end
	if data.MatchResult == "win" then
		resultLabel.Text = "🏆 VITÓRIA!"
		resultLabel.TextColor3 = Color3.fromRGB(85, 255, 127)
	else
		resultLabel.Text = "😔 DERROTA"
		resultLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
	end

	moneyValueLabel.Text = string.format("$%d", data.MoneyEarned)
	xpValueLabel.Text = string.format("%d XP", data.XPEarned)

	-- Badge de MVP: só aparece quando o jogador realmente foi o MVP;
	-- caso contrário fica escondido (nada de "MVP: Não" feio na tela).
	mvpBadge.Visible = data.Stats.MVP and true or false

	for _, child in ipairs(statsContainer:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	createStatRow("⚽", "Gols", data.Stats.Goals, statsContainer, 1)
	createStatRow("🤝", "Assistências", data.Stats.Assists, statsContainer, 2)
	createStatRow("🛡️", "Carrinhos", data.Stats.Tackles, statsContainer, 3)

	summaryFrame.Size = UDim2.new(0, 400, 0, 0)
	summaryFrame.Visible = true
end)

print("✅ FootballClient carregado.")