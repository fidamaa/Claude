local Players = game:GetService("Players")
local player = Players.LocalPlayer
local BadgeService = game:GetService("BadgeService")

local function awardAchievement()
	BadgeService:AwardBadge(player.UserId, 2664288081697490)
	print("Conquista adquirida: Bem-vindo ao jogo!")
end

-- Concede a conquista quando o jogador entra no jogo
awardAchievement()