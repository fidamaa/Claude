--[[
	GKAreaUtil (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	Ponto único de verdade pra saber se um jogador (goleiro) está dentro
	da área do PRÓPRIO gol. Usado tanto no servidor (BallController.lua/
	PulseController.lua, pra travar Dive/Forward/Pulso R fora da área)
	quanto no cliente (GKInput/PulseInput/DribbleInput.local.lua, pra
	trocar os controles na hora certa) — os dois lados fazem exatamente
	a mesma conta, então nunca dessincroniza (o cliente só decide QUAL
	tecla manda o quê; o servidor SEMPRE valida de novo antes de agir).

	REQUER (crie no Studio — ver também o comentário em FootballConfig.
	lua): 1 Part invisível, sem colisão física, por time, cobrindo a
	grande área daquele gol:
		GKArea_Azul
		GKArea_Amarelo
	Sem a Part de um time, esse módulo sempre devolve "dentro da área"
	pra goleiros daquele time (fallback seguro — não trava ninguém só
	porque a Part ainda não foi criada).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local GKAreaUtil = {}

-- ⚠️ NOVO: "o aviso nunca some, mesmo perto do gol" (GKArea) e "a Tunnel
-- não existe" (CutsceneTunnel) — causa raiz real dos dois: Workspace.
-- StreamingEnabled com Workspace.StreamingTargetRadius padrão do Roblox
-- (~1024 studs) menor que a distância dessas Parts até o spawn/câmera do
-- jogador no campo novo (bem maior). Isso não é um bug de nome/script —
-- o cliente literalmente nunca recebe essas Parts do servidor enquanto o
-- raio de streaming dele for pequeno demais pro tamanho do mapa, e por
-- isso o aviso "nunca some" mesmo perto do gol. Como este módulo é
-- required cedo tanto no cliente quanto no servidor (ver comentário no
-- topo do arquivo), é o lugar mais cedo/central pra corrigir isso uma vez
-- só pra todo o jogo: alarga o raio de streaming do CLIENTE (não faz
-- nada, nem faz sentido, do lado do servidor, que sempre vê o Workspace
-- inteiro sem streaming) e pede pro engine já ir carregando a região ao
-- redor do jogador imediatamente, em vez de esperar o streaming
-- progressivo de sempre.
-- ⚠️ FIX: "StreamingTargetRadius is not a valid member of Workspace" —
-- essa versão/engine do jogo nem tem essa propriedade (deu erro direto,
-- sem nem cair no pcall de leitura lá embaixo no diagnóstico, porque
-- aquele print não estava protegido — CORRIGIDO agora). Como a
-- propriedade nem existe aqui pra mexer, e ela é a única coisa que
-- StreamingTargetRadius influenciaria, essa tentativa de "alargar o raio
-- de streaming" foi removida — não tem o que ajustar nesse sentido nesse
-- projeto. Isso também é uma boa notícia pro diagnóstico: se o raio nem
-- existe como conceito ajustável aqui, é bem mais provável que o
-- problema real seja a Part não existir de verdade onde o servidor/
-- cliente enxergam (ver printMissingPartsDiagnostic logo abaixo) do que
-- streaming de verdade.
if RunService:IsClient() then
	local Players = game:GetService("Players")
	local localPlayer = Players.LocalPlayer

	local function requestStreamAround(position)
		local streamingOk, streamingEnabled = pcall(function() return workspace.StreamingEnabled end)
		if not streamingOk or not streamingEnabled then return end
		pcall(function()
			workspace:RequestStreamAroundAsync(position, 5)
		end)
	end

	local function requestStreamAroundLocalCharacter()
		local character = localPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then requestStreamAround(root.Position) end
	end

	if localPlayer.Character then
		task.spawn(requestStreamAroundLocalCharacter)
	end
	localPlayer.CharacterAdded:Connect(function()
		task.defer(requestStreamAroundLocalCharacter)
	end)

	-- ⚠️ NOVO: GKArea_* fica perto do GOL (não do spawn do jogador) — pedir
	-- streaming em volta do próprio Gol (Part que já existe e é central
	-- pro jogo, então quase certamente é confiável/visível cedo) é mais
	-- direto do que esperar o jogador andar até lá sozinho.
	task.spawn(function()
		local blueGoal = workspace:WaitForChild(Config.BLUE_GOAL_NAME, 10)
		if blueGoal then requestStreamAround(blueGoal.Position) end
		local yellowGoal = workspace:WaitForChild(Config.YELLOW_GOAL_NAME, 10)
		if yellowGoal then requestStreamAround(yellowGoal.Position) end
	end)
end

local PREFIX = Config.GK_AREA_PART_PREFIX

local areaParts = {} -- [teamName] = Part
local warnedMissing = {}
-- ⚠️ NOVO: forward-declarado aqui (atribuído de verdade lá embaixo, perto
-- do scheduleMissingCheck) por causa do escopo léxico do Luau — tryRegister
-- é definida ANTES na leitura do arquivo, mas precisa chamar essa função
-- assim que registra uma Part (pra confirmar "achou depois de avisar que
-- não tinha achado").
local maybeConfirmFound

-- Registra UMA Part GKArea_* (se for o caso) — usado tanto pelo scan
-- inicial quanto pelo DescendantAdded permanente logo abaixo.
local function tryRegister(inst)
	if not (inst:IsA("BasePart") and inst.Name:sub(1, #PREFIX) == PREFIX) then return end
	local teamName = inst.Name:sub(#PREFIX + 1)
	if areaParts[teamName] == inst then return end -- já registrada, nada a fazer

	areaParts[teamName] = inst
	if maybeConfirmFound then maybeConfirmFound(teamName) end

	-- ⚠️ FIX: essa Part é só uma "caixa matemática" (isPointInsideBox
	-- abaixo) — ela NUNCA deveria interferir com física nem com o
	-- Mouse.Hit do jogador. Antes disso, mesmo com CanCollide=false
	-- (só isso é pedido no comentário do topo), CanQuery continuava
	-- true por padrão do Roblox, então o raycast do mouse.Hit (usado
	-- pra mirar o chute em FootballClient.lua) podia acertar essa
	-- caixa invisível em vez do gramado/gol de verdade sempre que o
	-- jogador mirava perto ou dentro da grande área — resultando num
	-- ponto de mira errado (geralmente na borda/parede da caixa,
	-- "puxando" o chute pra fora). Forçar CanQuery/CanCollide/
	-- CanTouch = false aqui garante isso em QUALQUER Part que o
	-- usuário criar com esse nome, sem precisar configurar nada
	-- manualmente no Studio.
	inst.CanQuery = false
	inst.CanCollide = false
	inst.CanTouch = false

	-- ⚠️ NOVO: "a Part existe e não funciona de jeito nenhum" — o diagnóstico
	-- (printMissingPartsDiagnostic) mostrou que a Part não existe em LUGAR
	-- NENHUM do workspace do lado Cliente (nem streaming, nem aninhada) —
	-- ou seja, ela está sendo DESTRUÍDA de verdade antes do cliente
	-- conseguir vê-la. Causa mais provável: a mesma coisa que já quebrou a
	-- cutscene ("precisava ancorar as Parts") — sem Anchored=true, a
	-- física deixa a Part CAIR (gravidade normal) até passar de
	-- Workspace.FallenPartsDestroyHeight, e o Roblox DESTRÓI ela sozinho
	-- automaticamente (não é streaming, é a Part sumindo de verdade da
	-- cena, pro servidor E pro cliente). Fix definitivo: o usuário precisa
	-- marcar Anchored=true nas Parts no Studio (senão isso volta a
	-- acontecer toda vez); e como reforço, ancora aqui também assim que
	-- registra a Part, o mais cedo possível (esse módulo é required logo
	-- no início do servidor) — se pegar a tempo, antes dela cair o
	-- suficiente pra ser destruída, evita o problema mesmo sem o usuário
	-- lembrar de ancorar manualmente.
	if not inst.Anchored then
		inst.Anchored = true
		warn(string.format(
			"⚠️ GKAreaUtil: Part '%s' não estava ANCORADA (Anchored=false) — isso faz ela CAIR e ser DESTRUÍDA automaticamente pela física assim que passar de Workspace.FallenPartsDestroyHeight (é bem provavelmente por isso que ela 'existe no Studio mas não funciona'). Ancorei ela agora via script, mas marque Anchored=true no Studio também pra isso não voltar a acontecer.",
			inst:GetFullName()
		))
	end
end

-- ⚠️ NOVO: "aumentei o StreamingTargetRadius pra 10000 e não resolveu" —
-- se mesmo assim a Part continua "não encontrada", streaming provavelmente
-- NÃO é a causa (prova real: o valor real de StreamingEnabled/Radius sai
-- impresso abaixo, sem precisar adivinhar) — sobra a Part não existir de
-- verdade onde o servidor/cliente enxergam nessa sessão de teste (nome
-- diferente por 1 caractere/maiúscula, dentro de um Model/Folder em vez de
-- direto em workspace, ClassName que não é BasePart, etc.). Esse
-- diagnóstico varre TODOS os filhos diretos de workspace procurando
-- qualquer nome PARECIDO (sem diferenciar maiúscula/minúscula) — se
-- aparecer aqui só com uma letra diferente ou classe errada, achamos o
-- problema de verdade.
-- ⚠️ FIX: a versão anterior lia workspace.StreamingEnabled/
-- StreamingTargetRadius DIRETO dentro do string.format, sem pcall — nessa
-- engine a segunda propriedade nem existe ("not a valid member"), então
-- isso quebrava com erro NÃO capturado bem no require() deste módulo,
-- travando em cascata todo script que dava require nele (DribbleInput,
-- FootballClient, GKInput apareceram todos com "Requested module
-- experienced an error while loading" por causa disso). Agora cada
-- leitura é protegida individualmente — se uma propriedade não existir
-- nessa versão, aparece "indisponível" no lugar dela em vez de derrubar o
-- módulo inteiro.
local function safeWorkspaceProperty(name)
	local ok, value = pcall(function() return (workspace :: any)[name] end)
	if ok then return tostring(value) end
	return "indisponível nesta versão (propriedade não existe)"
end

local diagnosticPrinted = {}
local function printMissingPartsDiagnostic(missingLabel)
	if diagnosticPrinted[missingLabel] then return end
	diagnosticPrinted[missingLabel] = true

	local ok = pcall(function()
		local side = RunService:IsServer() and "SERVIDOR" or "CLIENTE"
		local needle = missingLabel:lower()
		local near = {}
		-- ⚠️ FIX: trocado de GetChildren() (só filho DIRETO) pra
		-- GetDescendants() (a árvore INTEIRA) — se a Part existir aninhada
		-- dentro de outro Model/Folder por engano, em vez de direto em
		-- workspace como o usuário acredita, isso aparece aqui junto com o
		-- Parent de verdade, em vez de dar falso negativo "NENHUM".
		for _, inst in ipairs(workspace:GetDescendants()) do
			if inst.Name:lower():find(needle, 1, true) then
				table.insert(near, string.format("'%s' (classe %s, parent '%s')", inst.Name, inst.ClassName, inst.Parent and inst.Parent.Name or "?"))
			end
		end

		warn(string.format(
			"🔎 [%s] Diagnóstico GKAreaUtil pra '%s': workspace.StreamingEnabled=%s | StreamingTargetRadius=%s | Parts com nome parecido em QUALQUER lugar de workspace: %s",
			side, missingLabel, safeWorkspaceProperty("StreamingEnabled"), safeWorkspaceProperty("StreamingTargetRadius"),
			(#near > 0) and table.concat(near, " , ") or "NENHUM em lugar nenhum de workspace (nem aninhado, nem por nome parecido/maiúscula-minúscula) — a Part não existe nessa sessão de teste."
		))
	end)

	if not ok then
		warn("🔎 GKAreaUtil: o próprio diagnóstico falhou (erro protegido, não deve travar mais nada) — ignorando e seguindo o jogo normalmente.")
	end
end

local function allTeamsFound()
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		if not areaParts[teamName] then return false end
	end
	return true
end

-- ⚠️ v11 FIX: "o GK entrou no gol do nada, como se a área dele estivesse
-- dentro da área do gol" + os dois warnings de Part não encontrada MESMO
-- com as duas áreas já existindo nos lugares certos. Causa raiz: scan()
-- rodava UMA VEZ SÓ (na hora do require) e nunca mais de novo (a flag
-- "scanned" travava isso pra sempre, sucesso ou não). Se nesse instante
-- exato a Part GKArea_* ainda não tivesse REPLICADO pro cliente —
-- streaming (Workspace StreamingEnabled), e o campo novo ficou bem maior,
-- então essas Parts (perto dos gols, longe do spawn) demoram mais a
-- chegar — o módulo achava "não existe" PRA SEMPRE e caía no fallback
-- "sempre conta como dentro da área" (ver comentário no topo do arquivo).
-- Pra quem é goleiro isso dá privilégio de área em QUALQUER lugar do
-- campo (parece "o GK entrou no gol do nada"); pra qualquer jogador
-- também afeta Instintos que checam dentro/fora de área (Sentinela, Ego
-- do Rei...), o que também pode explicar chutes saindo diferente do
-- esperado.
--
-- Fix: scan() continua rodando na hora, mas agora é barato repetir
-- (allTeamsFound() sai cedo se já achou as duas) — E workspace.
-- DescendantAdded fica registrado PRA SEMPRE, então se a Part aparecer
-- depois (streaming, ou até troca manual em runtime), o módulo se
-- autocorrige sozinho sem precisar reiniciar o server.
--
-- ⚠️ NOVO: "já apaguei e criei outras duas iguais, já estão anchored, e o
-- erro persiste" — esse aviso quase certamente é FALSO ALARME de largada:
-- este módulo é `require`ado tão cedo (antes até do personagem/campo
-- terminarem de carregar pro cliente) que o PRIMEIRO scan() SEMPRE roda
-- antes de qualquer coisa não-crítica (como GKArea_*) ter tido tempo de
-- aparecer — mesmo com a Part 100% correta e ancorada. Antes, esse
-- primeiro scan() já saía avisando na hora, então o aviso aparecia em
-- TODA partida, sempre, mesmo quando tudo está certo (e se autocorrige
-- sozinho um instante depois via DescendantAdded, só que sem nenhuma
-- confirmação visível — parecia "quebrado pra sempre" mesmo estando bem).
-- Agora: scan() continua populando na hora (silencioso, sem avisar nada),
-- e só existe UM aviso de verdade, disparado depois de uma folga real (ver
-- scheduleMissingCheck abaixo) — se depois dessa folga ainda não achou, aí
-- sim é bem provável ser um problema de verdade (nome errado, Part em
-- outro lugar/Place, etc.) e não só timing de carregamento.
local function scan()
	if allTeamsFound() then return end
	for _, inst in ipairs(workspace:GetDescendants()) do
		tryRegister(inst)
	end
end

scan()

-- ⚠️ NOVO: confirmação POSITIVA — sem isso, não tinha como o usuário saber
-- se a Part "se autocorrigiu sozinha" um instante depois do aviso (o que
-- seria o comportamento normal/esperado) ou se ela nunca mais apareceu de
-- verdade. Dispara uma vez só por time, na hora que tryRegister realmente
-- encontra a Part (scan inicial OU DescendantAdded depois).
local confirmedFound = {}
maybeConfirmFound = function(teamName)
	if confirmedFound[teamName] or not areaParts[teamName] then return end
	confirmedFound[teamName] = true
	if warnedMissing[teamName] then
		-- só vale a pena avisar se ela tinha sido dada como "não achada"
		-- antes — se achou de primeira, não precisa de print nenhum.
		print(string.format("✅ GKAreaUtil: Part '%s%s' encontrada e registrada (se autocorrigiu sozinha).", PREFIX, teamName))
	end
end

-- ⚠️ NOVO: só avisa "não encontrada" depois de uma folga de verdade (ver
-- comentário grande acima de scan()) — dá tempo do carregamento normal
-- terminar antes de soar falso alarme em toda partida.
task.spawn(function()
	task.wait(4)
	scan()
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		maybeConfirmFound(teamName)
		if not areaParts[teamName] and not warnedMissing[teamName] then
			warnedMissing[teamName] = true
			printMissingPartsDiagnostic(PREFIX .. teamName)
			warn(string.format(
				"⚠️ GKAreaUtil: Part '%s%s' não encontrada na cena mesmo depois de alguns segundos — habilidades de goleiro do time %s contam como 'dentro' até ela aparecer aqui. Isso já esperou o carregamento inicial (não é mais só timing de largada) — confira o diagnóstico 🔎 logo acima: se ele mostrar 'NENHUM em lugar nenhum de workspace', a Part não existe nessa sessão de teste (conferir se salvou o lugar certo antes de dar Play). Mesmo assim, continua se autocorrigindo sozinho (workspace.DescendantAdded) se ela aparecer depois, sem precisar reiniciar o server.",
				PREFIX, teamName, teamName
			))
		end
	end
end)

-- Pega a Part mesmo se ela aparecer DEPOIS do scan inicial (streaming, ou
-- qualquer script que crie/mova a Part em runtime) — ao contrário do scan
-- antigo, isto nunca "desliga".
workspace.DescendantAdded:Connect(tryRegister)

-- ⚠️ v5.6: "margin" (studs) alarga a caixa pros três eixos antes de
-- testar o ponto — usado por condições que precisam de uma folga na
-- borda da área (ex: Predador da Área, que era travado "no fio" da
-- linha da grande área). margin=0/nil mantém o comportamento exato de
-- sempre.
local function isPointInsideBox(part, worldPoint, margin)
	local localPoint = part.CFrame:PointToObjectSpace(worldPoint)
	local halfSize = part.Size / 2 + Vector3.new(margin or 0, margin or 0, margin or 0)
	return math.abs(localPoint.X) <= halfSize.X
		and math.abs(localPoint.Y) <= halfSize.Y
		and math.abs(localPoint.Z) <= halfSize.Z
end

-- true/false — se a Part do time do jogador não existir na cena, devolve
-- true (fallback seguro, ver nota no topo).
function GKAreaUtil.IsPlayerInOwnGKArea(player)
	scan()

	local teamName = player.Team and player.Team.Name
	if not teamName then return true end

	local part = areaParts[teamName]
	if not part then return true end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return false end

	return isPointInsideBox(part, root.Position)
end

-- ⚠️ v5.4: versão GENÉRICA — quer saber se um PONTO qualquer (não
-- necessariamente o HumanoidRootPart de um goleiro) está dentro da área
-- de um TIME específico. Usada por Instintos de linha que também
-- dependem de "dentro/fora da área" mas não são exclusivos de goleiro
-- (Sentinela: dentro da própria área; Ego do Rei: fora da área
-- ADVERSÁRIA). fallbackInside decide o que devolver se a Part daquele
-- time ainda não existir na cena — cada chamador escolhe o fallback que
-- deixa a habilidade "funcionando" (não travada) se a Part faltar, igual
-- o resto deste módulo já faz.
function GKAreaUtil.IsPositionInArea(teamName, position, fallbackInside, margin)
	scan()
	if not teamName or not position then return fallbackInside end

	local part = areaParts[teamName]
	if not part then return fallbackInside end

	return isPointInsideBox(part, position, margin)
end

-- "GK efetivo": é goleiro (Attribute Role == "GK") E está dentro da
-- própria área. Fora da área, mesmo sendo GK no papel, conta como
-- jogador de linha normal pra fins de controle/habilidade.
function GKAreaUtil.IsEffectiveGK(player)
	if player:GetAttribute("Role") ~= "GK" then return false end
	return GKAreaUtil.IsPlayerInOwnGKArea(player)
end

return GKAreaUtil
