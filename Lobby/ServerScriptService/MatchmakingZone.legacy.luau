--[[
	MatchmakingZone (Script)
	LOCAL: ServerScriptService (place Lobby)

	Detecta quem está DENTRO da Part configurada em
	Config.MATCHMAKING_ZONE_NAME (translúcida, CanCollide = false,
	CanQuery = true — "Only Query" no Studio) por OVERLAP
	(workspace:GetPartsInPart), não por Touched. Abre a tela de
	matchmaking no cliente de quem entra, fecha em quem sai.

	Roda numa checagem periódica (Config.ZONE_CHECK_INTERVAL), não a
	cada frame — não precisa de mais que isso pra uma área parada, e
	evita gastar overlap query em Heartbeat com muita gente no server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

local zone = workspace:WaitForChild(Config.MATCHMAKING_ZONE_NAME)

local overlapParams = OverlapParams.new()
overlapParams.FilterType = Enum.RaycastFilterType.Include

local playersInsideZone = {} -- [Player] = true

local function getCharacterRoot(player)
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChild("HumanoidRootPart")
end

local function isInsideZone(root)
	overlapParams.FilterDescendantsInstances = { root }
	local parts = workspace:GetPartsInPart(zone, overlapParams)
	return #parts > 0
end

task.spawn(function()
	while true do
		task.wait(Config.ZONE_CHECK_INTERVAL)

		for _, player in ipairs(Players:GetPlayers()) do
			local root = getCharacterRoot(player)
			local wasInside = playersInsideZone[player] or false
			local nowInside = root ~= nil and isInsideZone(root)

			if nowInside and not wasInside then
				playersInsideZone[player] = true
				Remotes.SetMatchmakingScreenOpen:FireClient(player, true)
			elseif not nowInside and wasInside then
				playersInsideZone[player] = nil
				Remotes.SetMatchmakingScreenOpen:FireClient(player, false)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	playersInsideZone[player] = nil
end)

print("✅ MatchmakingZone carregado.")
