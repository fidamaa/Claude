--[[
	LobbyBarrier (Script)
	LOCAL: ServerScriptService (place Lobby)

	⚠️ v68 — PEDIDO: "ajustar as coisas pra não poder sair do limite do mapa."

	Existe uma pasta "InvisibleWall" no Workspace, mas ela está VAZIA — ou
	seja, o limite nunca chegou a ser construído. Dava pra andar pra fora do
	chão e cair no vazio.

	As paredes são construídas por CÓDIGO a partir do próprio piso do lobby
	(a Part "Chão"), e não desenhadas à mão: assim elas acompanham sozinhas
	qualquer expansão do mapa, e não tem como ficarem desalinhadas depois.

	Além das paredes, há uma REDE DE SEGURANÇA: quem conseguir sair mesmo
	assim (ficar preso numa quina, ser empurrado, cair por um buraco de
	geometria) é devolvido ao spawn em vez de cair pra sempre. Parede sozinha
	nunca é 100% — sempre aparece uma fresta.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

local PASTA = "InvisibleWall"
local ALTURA = LobbyConfig.BARRIER_HEIGHT or 90
local ESPESSURA = LobbyConfig.BARRIER_THICKNESS or 6
local MARGEM = LobbyConfig.BARRIER_MARGIN or 4

local function acharPiso()
	-- O piso principal do lobby. Nome com acento vem do Studio.
	local piso = workspace:FindFirstChild("Chão")
	if piso and piso:IsA("BasePart") then return piso end
	-- Fallback: a maior Part plana do workspace (caso o nome mude um dia).
	local melhor, melhorArea = nil, 0
	for _, d in ipairs(workspace:GetChildren()) do
		if d:IsA("BasePart") and d.Size.Y <= 3 then
			local area = d.Size.X * d.Size.Z
			if area > melhorArea then melhor, melhorArea = d, area end
		end
	end
	return melhor
end

-- ⚠️ v70 — LIMITES VÊM DO CONFIG, NÃO DA PART "Chão".
-- A floresta passou a existir FORA do Chão (árvores até X -342 e Z 1423),
-- então medir a parede pelo Chão cortaria a mata no meio. Config.BARRIER_BOUNDS
-- é a mesma fonte que define até onde o piso foi estendido — um número só
-- pros dois, pra nunca sobrar faixa de chão fora da parede nem o contrário.
-- O Chão segue como fallback pra o caso de alguém apagar os limites.
local function limites()
	local b = LobbyConfig.BARRIER_BOUNDS
	if b and b.MinX and b.MaxX and b.MinZ and b.MaxZ then
		return b.MinX, b.MaxX, b.MinZ, b.MaxZ, "config"
	end
	local piso = acharPiso()
	if not piso then return nil end
	return piso.Position.X - piso.Size.X / 2, piso.Position.X + piso.Size.X / 2,
	       piso.Position.Z - piso.Size.Z / 2, piso.Position.Z + piso.Size.Z / 2, "piso"
end

local function construir()
	local piso = acharPiso()
	local x0, x1, z0, z1, origem = limites()
	if not x0 then
		warn("🧱 [LobbyBarrier] sem limites e sem piso — barreira não construída.")
		return
	end

	local pasta = workspace:FindFirstChild(PASTA)
	if not pasta then
		pasta = Instance.new("Folder")
		pasta.Name = PASTA
		pasta.Parent = workspace
	end
	pasta:ClearAllChildren()

	local centro = Vector3.new((x0 + x1) / 2, piso and piso.Position.Y or 4, (z0 + z1) / 2)
	local meioX = (x1 - x0) / 2 + MARGEM
	local meioZ = (z1 - z0) / 2 + MARGEM
	local baseY = piso and (piso.Position.Y + piso.Size.Y / 2) or 4

	-- As laterais são propositalmente mais LONGAS que o piso: sem isso
	-- sobraria uma fresta exatamente em cada quina, que é justamente por onde
	-- o jogador sai quando corre na diagonal.
	local paredes = {
		{ Vector3.new(ESPESSURA, ALTURA, meioZ * 2 + ESPESSURA * 2), Vector3.new( meioX, 0, 0) },
		{ Vector3.new(ESPESSURA, ALTURA, meioZ * 2 + ESPESSURA * 2), Vector3.new(-meioX, 0, 0) },
		{ Vector3.new(meioX * 2 + ESPESSURA * 2, ALTURA, ESPESSURA), Vector3.new(0, 0,  meioZ) },
		{ Vector3.new(meioX * 2 + ESPESSURA * 2, ALTURA, ESPESSURA), Vector3.new(0, 0, -meioZ) },
	}

	for i, p in ipairs(paredes) do
		local parede = Instance.new("Part")
		parede.Name = "Parede" .. i
		parede.Size = p[1]
		parede.Position = centro + p[2] + Vector3.new(0, ALTURA / 2, 0)
		parede.Anchored = true
		parede.CanCollide = true
		parede.CanQuery = false -- não atrapalha raycast de mira/câmera
		parede.CanTouch = false
		parede.CastShadow = false
		parede.Transparency = 1
		parede.Parent = pasta
	end

	print(string.format(
		"🧱 [LobbyBarrier] 4 paredes de %d studs (limite vindo de: %s) — X %.0f a %.0f, Z %.0f a %.0f.",
		ALTURA, origem, centro.X - meioX, centro.X + meioX, centro.Z - meioZ, centro.Z + meioZ))

	return piso, centro, meioX, meioZ, baseY
end

local piso, centro, meioX, meioZ, baseY = construir()

-- ===== REDE DE SEGURANÇA =====
-- Parede nunca segura 100%: quina, empurrão e buraco de geometria sempre
-- arranjam um jeito. Quem sair mesmo assim volta pro spawn em vez de cair
-- pra sempre — o jogador nem percebe que houve um problema.
if piso then
	local LIMITE_ABAIXO = LobbyConfig.BARRIER_FALL_Y or (baseY - 60)
	local FOLGA = 30 -- só resgata quem passou BEM do limite, não quem encostou

	local function spawnDoLobby()
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("SpawnLocation") then return d.CFrame + Vector3.new(0, 4, 0) end
		end
		return CFrame.new(centro + Vector3.new(0, 8, 0))
	end

	local ultimoResgate = {}
	RunService.Heartbeat:Connect(function()
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root then continue end

			local pos = root.Position
			local foraX = math.abs(pos.X - centro.X) > meioX + FOLGA
			local foraZ = math.abs(pos.Z - centro.Z) > meioZ + FOLGA
			local caiu = pos.Y < LIMITE_ABAIXO

			if foraX or foraZ or caiu then
				-- não repete o resgate em rajada enquanto ele reposiciona
				if tick() - (ultimoResgate[player] or 0) < 2 then continue end
				ultimoResgate[player] = tick()
				character:PivotTo(spawnDoLobby())
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
end
