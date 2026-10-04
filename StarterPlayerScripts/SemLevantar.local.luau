--[[
	SemLevantar — ⚠️ v110

	PEDIDO: "faz a bola parar de levantar o personagem" (e outros personagens
	passando por baixo também levantavam).

	A física já não deixa Bola x Players nem Players x Players colidirem (grupos
	de colisão, ver FootballConfig), mas o SENSOR DE CHÃO do Humanoid (o raio que
	ele solta pra baixo pra achar onde pisar) não respeita grupo de colisão: se a
	bola ou o corpo de outro jogador passa debaixo do pé, ele "sobe" em cima.

	Aqui, só no NOSSO cliente (que é quem simula o nosso personagem): tudo que é
	bola ou corpo de outro personagem que aparece debaixo do nosso pé fica
	CanCollide=false localmente enquanto estiver ali. O servidor não muda nada —
	o toque na bola, os carrinhos e o resto seguem iguais.

	⚠️ v110 (correção): com a POSSE, quem simula a física da bola é o NOSSO
	cliente (rede entregue pro dono, ver BolaNosPes) — desligar a colisão dela
	aqui fazia a bola ATRAVESSAR o gramado (achado na bateria de testes: toda
	Hissatsu de drible terminava com a bola caindo por baixo do campo e sendo
	"resgatada" pro centro). Agora, com a posse, a bola nunca é mexida aqui (e
	a colisão volta na hora que você pega a bola).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local desligadas = {} -- [BasePart] = tick() em que viu debaixo do pé

local function ehBola(part)
	return part.Name == "Ball" or part.Name == "Bola" or part.Name == "bola" or part.CollisionGroup == "Bola"
end

local comPosse = false
task.spawn(function()
	local remotes = ReplicatedStorage:WaitForChild("FootballRemotes", 30)
	local evento = remotes and remotes:WaitForChild("PossessionChanged", 30)
	if not evento then return end
	evento.OnClientEvent:Connect(function(quem, ganhou)
		if quem == player then
			comPosse = ganhou and true or false
		elseif ganhou then
			comPosse = false
		end
		if comPosse then
			-- pegou a bola: devolve a colisão dela JÁ (agora é a gente que simula)
			for p in pairs(desligadas) do
				if ehBola(p) then
					p.CanCollide = true
					desligadas[p] = nil
				end
			end
		end
	end)
end)

local function ehPisavelProibido(part)
	if ehBola(part) then
		return not comPosse -- com a posse, nunca (ver o topo)
	end
	local modelo = part:FindFirstAncestorOfClass("Model")
	while modelo do
		if modelo:FindFirstChildOfClass("Humanoid") then
			return modelo ~= player.Character
		end
		modelo = modelo:FindFirstAncestorOfClass("Model")
	end
	return false
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.RespectCanCollide = false

-- ⚠️ v126c — PEDIDO: "usei o Flow do Shidou e assim que terminei o boneco caiu no chão,
-- levantou, caiu de novo e ficou bugado no chão, teleportando" (sempre). Conferido no Studio:
-- a cena inclina o corpo >100° (bicicleta) e o Humanoid do Roblox entende como "tombou" —
-- quando a cena solta, ele fica em FallingDown ~2s, afundado, e levanta. As quedas do jogo
-- são o ragdoll próprio (PlatformStand), então o tombo automático do Roblox fica DESLIGADO.
local function semTombo(char)
	local hum = char and char:WaitForChild("Humanoid", 10)
	if not hum then return end
	hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
end
if player.Character then task.spawn(semTombo, player.Character) end
player.CharacterAdded:Connect(semTombo)

-- (v126) caixa dos pés e chão pra trava anti-afundar
local filtroCaixa = OverlapParams.new()
filtroCaixa.MaxParts = 40
local filtroChao = RaycastParams.new()
filtroChao.FilterType = Enum.RaycastFilterType.Exclude
filtroChao.RespectCanCollide = true
local afundadoQuadros = 0
local function semPersonagens(char)
	local lista = { char }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and p.Character ~= char then table.insert(lista, p.Character) end
	end
	for _, m in ipairs(workspace:GetChildren()) do
		if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" then table.insert(lista, m) end
		if m:IsA("BasePart") and ehBola(m) then table.insert(lista, m) end
	end
	return lista
end

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local agora = tick()
	if root then
		local function desligar(p)
			if desligadas[p] == nil and p.CanCollide then
				p.CanCollide = false
				desligadas[p] = agora
			elseif desligadas[p] then
				desligadas[p] = agora
			end
		end
		local ignorar = { char }
		-- olha até 4 coisas empilhadas debaixo do pé (bola em cima de outro, etc.)
		for _ = 1, 4 do
			params.FilterDescendantsInstances = ignorar
			local hit = workspace:Raycast(root.Position, Vector3.new(0, -5.5, 0), params)
			if not hit then break end
			local p = hit.Instance
			if not ehPisavelProibido(p) then break end
			desligar(p)
			table.insert(ignorar, p)
		end
		-- ⚠️ v126 — PEDIDO: "quando a bola vai pra trás de mim eu ainda subo em cima dela; o
		-- código que evita isso resolve a maior parte das vezes — refina". O raio do centro do
		-- quadril não via a bola chegando por TRÁS/do lado (debaixo do calcanhar). Agora é uma
		-- CAIXA cobrindo os pés com folga (inclui a bola rolando na direção deles).
		local caixa = root.CFrame * CFrame.new(0, -2.6, 0)
		local naCaixa = workspace:GetPartBoundsInBox(caixa, Vector3.new(4.2, 3.2, 4.6), filtroCaixa)
		for _, p in ipairs(naCaixa) do
			if p:IsA("BasePart") and not p:IsDescendantOf(char) and ehPisavelProibido(p) then
				desligar(p)
			end
		end

		-- ⚠️ v126 — PEDIDO: "o jogador fica caindo no chão e entrando no chão; parte dele entra
		-- no chão e fica descendo e subindo" (depois de Hissatsu/derrubada; jogadores R6). Trava
		-- de segurança: em pé (correndo/parado), fora de ragdoll/cutscene, se o quadril ficar
		-- abaixo da altura de pé por alguns quadros seguidos, sobe o corpo de volta pro gramado.
		local hum = char:FindFirstChildOfClass("Humanoid")
		local estado = hum and hum:GetState()
		local emPe = hum and hum.Health > 0 and not hum.PlatformStand and not hum.Sit and not root.Anchored
			and not _G.HissatsuCutsceneLocal
			and (estado == Enum.HumanoidStateType.Running or estado == Enum.HumanoidStateType.RunningNoPhysics
				or estado == Enum.HumanoidStateType.Landed or estado == Enum.HumanoidStateType.None)
		if emPe then
			local tronco = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
			local perna = char:FindFirstChild("Left Leg") or char:FindFirstChild("LeftUpperLeg")
			local dePe = (hum.HipHeight > 0.1) and (hum.HipHeight + root.Size.Y / 2)
				or ((tronco and tronco.Size.Y / 2 or 1) + (perna and perna.Size.Y or 2))
			filtroChao.FilterDescendantsInstances = semPersonagens(char)
			local chao = workspace:Raycast(root.Position + Vector3.new(0, dePe + 1, 0), Vector3.new(0, -(dePe * 2 + 6), 0), filtroChao)
			local falta = chao and (chao.Position.Y + dePe - root.Position.Y) or 0
			if falta > 0.4 then
				afundadoQuadros += 1
				-- (conferido no Studio: afundada rápida o próprio Humanoid desfaz sozinho — mexer
				-- junto passava do ponto; só age quando o corpo FICA afundado, que é o bug)
				if afundadoQuadros >= 8 then
					root.CFrame += Vector3.new(0, falta, 0)
					local v = root.AssemblyLinearVelocity
					root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z)
					afundadoQuadros = 0
				end
			else
				afundadoQuadros = 0
			end
		else
			afundadoQuadros = 0
		end
	end
	-- devolve a colisão local quando saiu de baixo do pé há um tempinho
	for p, visto in pairs(desligadas) do
		if not p.Parent then
			desligadas[p] = nil
		elseif agora - visto > 0.6 then
			p.CanCollide = true
			desligadas[p] = nil
		end
	end
end)
