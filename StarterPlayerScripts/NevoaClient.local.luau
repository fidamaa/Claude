--[[
	NevoaClient — ⚠️ v110

	PEDIDO: "a Névoa precisa deixar o player 100% invisível pra todos os outros
	jogadores, a não ser ele mesmo, tá? E do próprio time."

	O servidor (PulseController, zona da Névoa) só marca:
	  character:GetAttribute("NaNevoa")          = true enquanto ele está dentro
	  bola:GetAttribute("EscondidaNaNevoa")      = UserId dele enquanto a bola
	                                               está no pé dele lá dentro
	Aqui cada cliente decide o que VÊ:
	  - ADVERSÁRIO: o corpo some 100% (partes, rosto, acessórios), e tudo que o
	    entregaria também — nome em cima da cabeça, partículas, rastros, luzes,
	    contornos (auras de arma) — e a bola, se estiver com ele.
	  - ELE MESMO e o PRÓPRIO TIME: meio transparente, pra saber que está
	    escondido.
	Tudo local (LocalTransparencyModifier / Enabled só nesta tela) — sai da
	névoa e volta tudo como estava.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local LocalPlayer = Players.LocalPlayer

local TRANSP_ALIADO = 0.55

local escondidos = {} -- [character] = { Desligados = { [instância] = true } }

local function ehAliado(p)
	if p == LocalPlayer then return true end
	return LocalPlayer.Team ~= nil and p.Team == LocalPlayer.Team
end

local DESLIGAVEIS = { ParticleEmitter = true, Trail = true, Beam = true, BillboardGui = true, Highlight = true,
	PointLight = true, SpotLight = true, SurfaceLight = true, Fire = true, Smoke = true, Sparkles = true }

local function aplicar(character, invisivel, alfa)
	local estado = escondidos[character]
	if not estado then
		estado = { Desligados = {} }
		escondidos[character] = estado
	end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			pcall(function() d.LocalTransparencyModifier = alfa end)
		elseif invisivel and DESLIGAVEIS[d.ClassName] and d.Enabled then
			-- (religa sozinho se outro script acender de novo — desliga outra vez)
			estado.Desligados[d] = true
			d.Enabled = false
		end
	end
end

local function restaurar(character)
	local estado = escondidos[character]
	if not estado then return end
	escondidos[character] = nil
	if not character.Parent then return end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			pcall(function() d.LocalTransparencyModifier = 0 end)
		end
	end
	for d in pairs(estado.Desligados) do
		if d.Parent then d.Enabled = true end
	end
end

-- bola
local bolaEscondida = false
local trilhasDaBola = {}
local function esconderBola(bola, sim)
	if sim == bolaEscondida then
		if sim then bola.LocalTransparencyModifier = 1 end
		return
	end
	bolaEscondida = sim
	bola.LocalTransparencyModifier = sim and 1 or 0
	for _, d in ipairs(bola:GetDescendants()) do
		if d:IsA("Decal") or d:IsA("Texture") then
			pcall(function() d.LocalTransparencyModifier = sim and 1 or 0 end)
		elseif DESLIGAVEIS[d.ClassName] then
			if sim and d.Enabled then
				trilhasDaBola[d] = true
				d.Enabled = false
			elseif not sim and trilhasDaBola[d] then
				trilhasDaBola[d] = nil
				if d.Parent then d.Enabled = true end
			end
		end
	end
end

local ultimaVarredura = 0
RunService.RenderStepped:Connect(function()
	local agora = os.clock()
	-- (a varredura completa — acha acessório/efeito novo — 5x por segundo;
	-- a transparência do corpo é reaplicada todo quadro, porque outros
	-- scripts mexem nela)
	local varrer = agora - ultimaVarredura > 0.2
	if varrer then ultimaVarredura = agora end

	local vistos = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local ch = p.Character
		if ch and ch:GetAttribute("NaNevoa") then
			vistos[ch] = true
			local aliado = ehAliado(p)
			if varrer or not escondidos[ch] then
				aplicar(ch, not aliado, aliado and TRANSP_ALIADO or 1)
			else
				for _, d in ipairs(ch:GetChildren()) do
					if d:IsA("BasePart") then d.LocalTransparencyModifier = aliado and TRANSP_ALIADO or 1 end
				end
			end
		end
	end
	for ch in pairs(escondidos) do
		if not vistos[ch] then restaurar(ch) end
	end

	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if bola then
		local dono = bola:GetAttribute("EscondidaNaNevoa")
		local escondeDeMim = false
		if typeof(dono) == "number" then
			local donoPlayer = Players:GetPlayerByUserId(dono)
			escondeDeMim = donoPlayer ~= nil and not ehAliado(donoPlayer)
		end
		esconderBola(bola, escondeDeMim)
	end
end)
