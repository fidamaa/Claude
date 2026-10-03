--[[
	MiraPrecisa (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	⚠️ v97 — UMA MIRA SÓ, PRECISA, PRO CHUTE E PRA HISSATSU.
	PEDIDO: "quando eu uso a Hissatsu sem o control lock, às vezes a bola vai
	um pouco pra cima demais, ou pra baixo demais, ou pro lado. Não é 100%
	preciso... se eu tento mirar num canto do gol, às vezes sobe, sai do gol,
	desce demais, bate no chão. Precisa ir sempre reto aonde foi mirado." E
	sobre a bola: "aonde você estiver mirando, você clicou, é pra ser perfeito."

	O QUE ERRAVA:
	  1. o ponto de mira era "a primeira coisa debaixo do cursor" — e na frente
	     do gol quase sempre tem GENTE (goleiro, zagueiro, o bot). Mirando num
	     canto com o goleiro na frente, o ponto virava o corpo dele: a bola ia
	     pra cima, pra baixo ou pro lado do que você via;
	  2. mirando baixo, o raio da câmera (que vem de cima) batia na GRAMA antes
	     de chegar no gol — a bola ia pro chão, na frente do gol;
	  3. (servidor) curva automática nos chutes de Hissatsu — tirada também.

	COMO FICOU:
	  - se o cursor está sobre o GOL, o alvo é o ponto exato na boca do gol
	    (o raio atravessa gente e grama só pra achar o gol) — nunca abaixo do
	    nível da bola no gramado (mirou rente ao chão = chute rasteiro no
	    canto, não pra dentro da terra);
	  - fora do gol, o alvo é a primeira coisa SÓLIDA debaixo do cursor,
	    ignorando personagens (de qualquer um), a bola e hitboxes invisíveis;
	  - mirou no céu: o ponto fica longe na direção exata do cursor;
	  - (opcional, chute normal) nunca pra TRÁS de quem chuta: se o ponto
	    ficou atrás da bola em relação à câmera (cursor apontando o chão entre
	    você e a câmera), vira "pra frente, na direção da câmera".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local MiraPrecisa = {}

local ALCANCE = 2000

local function gols()
	local lista = {}
	for _, nome in ipairs({ Config.BLUE_GOAL_NAME, Config.YELLOW_GOAL_NAME }) do
		local g = workspace:FindFirstChild(nome, true)
		if g and g:IsA("BasePart") then table.insert(lista, g) end
	end
	return lista
end

local function personagens()
	local lista = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(lista, p.Character) end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" then table.insert(lista, m) end
	end
	return lista
end

local paramsGol = RaycastParams.new()
paramsGol.FilterType = Enum.RaycastFilterType.Include

local paramsMundo = RaycastParams.new()
paramsMundo.FilterType = Enum.RaycastFilterType.Exclude
paramsMundo.IgnoreWater = true

local paramsChao = RaycastParams.new()
paramsChao.FilterType = Enum.RaycastFilterType.Exclude
paramsChao.RespectCanCollide = true

local function alturaDoChao(ponto, ignorar)
	paramsChao.FilterDescendantsInstances = ignorar
	local r = workspace:Raycast(ponto + Vector3.new(0, 40, 0), Vector3.new(0, -120, 0), paramsChao)
	return r and r.Position.Y or nil
end

-- camera, x, y (ponto da tela, mesmo sistema do mouse.X/Y), opcoes:
--   opcoes.NuncaPraTras = true  -> ver cabeçalho
--   opcoes.AlinharNaBocaDoGol = true -> (só Hissatsu, v122) ponto atrás do gol vira o
--     cruzamento do raio com a boca do gol
function MiraPrecisa.Calcular(camera, x, y, opcoes)
	opcoes = opcoes or {}
	local raio = camera:ScreenPointToRay(x, y)
	local direcao = raio.Direction.Unit
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	local sombra = workspace:FindFirstChild("SombraDaBola")

	local ignorar = personagens()
	if bola then table.insert(ignorar, bola) end
	if sombra then table.insert(ignorar, sombra) end

	local ponto

	-- primeira coisa sólida e visível debaixo do cursor (sem gente, sem bola,
	-- sem hitbox invisível)
	local pontoMundo
	do
		local lista = table.clone(ignorar)
		for _ = 1, 16 do
			paramsMundo.FilterDescendantsInstances = lista
			local batida = workspace:Raycast(raio.Origin, direcao * ALCANCE, paramsMundo)
			if not batida then break end
			local parte = batida.Instance
			if parte.Transparency >= 0.95 or not parte.CanCollide then
				table.insert(lista, parte) -- hitbox/zona invisível: atravessa
			else
				pontoMundo = batida.Position
				break
			end
		end
	end

	-- o GOL tem prioridade: o raio atravessa gente e grama só pra achar a
	-- boca do gol. Só não vale quando o gol está MUITO atrás do que o cursor
	-- toca (ex.: mirando um passe no meio-campo com o gol lá no fundo, na
	-- mesma linha) — até 30 studs atrás é o caso "grama na frente do gol".
	local listaGols = gols()
	if #listaGols > 0 then
		paramsGol.FilterDescendantsInstances = listaGols
		local noGol = workspace:Raycast(raio.Origin, direcao * ALCANCE, paramsGol)
		if noGol then
			local distGol = (noGol.Position - raio.Origin).Magnitude
			local distMundo = pontoMundo and (pontoMundo - raio.Origin).Magnitude or math.huge
			if distGol <= distMundo + 30 then
				ponto = noGol.Position
				local chao = alturaDoChao(ponto, ignorar)
				local raioBola = bola and bola.Size.Y / 2 or 0.85
				if chao and ponto.Y < chao + raioBola then
					ponto = Vector3.new(ponto.X, chao + raioBola, ponto.Z)
				end
			end
		end
	end

	local acertouGol = ponto ~= nil
	if not ponto then ponto = pontoMundo end

	-- 3) mirou no céu / no nada: longe, na direção exata do cursor
	if not ponto then
		ponto = raio.Origin + direcao * ALCANCE
	end

	-- ⚠️ v122 — PEDIDO: "nas Hissatsus aéreas, de longe a mira sobe demais — baixar /
	-- alinhar". De longe o cursor quase nunca fica EXATAMENTE no gol: um pouco acima
	-- dele o ponto virava a arquibancada lá atrás (ou o céu, a 2000 studs) e a reta
	-- da bola — que nas aéreas sai lá do alto — passava por cima do travessão. Agora,
	-- se o ponto ficou ATRÁS da boca de um gol, o alvo é onde o raio do cursor CRUZA o
	-- plano da boca do gol: a bola passa exatamente onde o cursor mostrava, de
	-- qualquer altura que ela saia.
	-- ⚠️ v122b — PEDIDO: "na Hissatsu ficou perfeito, mas no chute NORMAL ela sai muito
	-- pra cima: esse sistema novo é só das Hissatsus, o antigo fica pro chute normal".
	-- Só liga com opcoes.AlinharNaBocaDoGol (HissatsuInput); o chute normal não passa.
	if not acertouGol and opcoes.AlinharNaBocaDoGol then
		local distPonto = (ponto - raio.Origin).Magnitude
		for _, g in ipairs(gols()) do
			-- normal da boca = o eixo horizontal mais FINO da peça do gol
			local n = (g.Size.X < g.Size.Z) and g.CFrame.RightVector or g.CFrame.LookVector
			n = Vector3.new(n.X, 0, n.Z)
			if n.Magnitude < 0.01 then continue end
			n = n.Unit
			local den = direcao:Dot(n)
			if math.abs(den) < 1e-3 then continue end
			-- (a peça do gol é uma caixa: o plano é a FACE do lado de quem mira, a boca)
			local profundidade = math.min(g.Size.X, g.Size.Z)
			local ladoCamera = (raio.Origin - g.Position):Dot(n) >= 0 and 1 or -1
			local boca = g.Position + n * (profundidade / 2) * ladoCamera
			local t = (boca - raio.Origin):Dot(n) / den
			if t <= 0 or t >= distPonto then continue end -- o plano não está entre a câmera e o ponto
			local cruza = raio.Origin + direcao * t
			local largura = math.max(g.Size.X, g.Size.Z)
			local lateral = math.abs((cruza - boca):Dot(Vector3.yAxis:Cross(n)))
			-- só perto do gol (até 1,5 largura pro lado e 40 de altura)
			if lateral <= largura * 1.5 and cruza.Y - g.Position.Y < 40 then
				local chao = alturaDoChao(cruza, ignorar)
				local raioBola = bola and bola.Size.Y / 2 or 0.85
				if chao and cruza.Y < chao + raioBola then cruza = Vector3.new(cruza.X, chao + raioBola, cruza.Z) end
				ponto = cruza
				break
			end
		end
	end

	-- nunca pra trás de quem chuta (chute normal)
	if opcoes.NuncaPraTras and bola then
		local frente = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
		local paraAlvo = Vector3.new(ponto.X - bola.Position.X, 0, ponto.Z - bola.Position.Z)
		if frente.Magnitude > 0.01 and paraAlvo:Dot(frente) < 0 then
			ponto = bola.Position + frente.Unit * 30
		end
	end

	return ponto
end

return MiraPrecisa
