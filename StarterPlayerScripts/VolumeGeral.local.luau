--[[
	VolumeGeral (LocalScript) — ⚠️ v124
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	PEDIDO: "aumente o som geral do jogo em 10%". O Roblox não tem um volume
	geral do jogo pra script mexer, então todo Sound (do servidor ou do
	cliente: música, apito, torcida, efeitos) entra num SoundGroup
	"VolumeGeral" com volume Config.VOLUME_GERAL (1.1 = +10%). O SoundGroup
	MULTIPLICA o volume de cada som — os fades/tweens de Sound.Volume continuam
	funcionando igual. Som que já tem SoundGroup próprio fica no dele.
]]

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local grupo = SoundService:FindFirstChild("VolumeGeral")
if not (grupo and grupo:IsA("SoundGroup")) then
	grupo = Instance.new("SoundGroup")
	grupo.Name = "VolumeGeral"
	grupo.Parent = SoundService
end
grupo.Volume = Config.VOLUME_GERAL or 1.1

local function aplicar(obj)
	if obj:IsA("Sound") and obj.SoundGroup == nil then
		obj.SoundGroup = grupo
	end
end

local function cobrir(raiz)
	if not raiz then return end
	for _, d in ipairs(raiz:GetDescendants()) do aplicar(d) end
	raiz.DescendantAdded:Connect(aplicar)
end

cobrir(workspace)
cobrir(SoundService)
cobrir(ReplicatedStorage)
cobrir(Players.LocalPlayer)
