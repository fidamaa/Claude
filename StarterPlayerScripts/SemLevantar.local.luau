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

RunService.Heartbeat:Connect(function()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local agora = tick()
	if root then
		local ignorar = { char }
		-- olha até 4 coisas empilhadas debaixo do pé (bola em cima de outro, etc.)
		for _ = 1, 4 do
			params.FilterDescendantsInstances = ignorar
			local hit = workspace:Raycast(root.Position, Vector3.new(0, -5.5, 0), params)
			if not hit then break end
			local p = hit.Instance
			if not ehPisavelProibido(p) then break end
			if desligadas[p] == nil and p.CanCollide then
				p.CanCollide = false
				desligadas[p] = agora
			elseif desligadas[p] then
				desligadas[p] = agora
			end
			table.insert(ignorar, p)
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
