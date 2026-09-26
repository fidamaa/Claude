--[[
	LobbyMovementSoundsClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	Ver o comentário completo na versão do place Game (StarterPlayerScripts/
	MovementSoundsClient.local.luau) — mesma lógica, mesmo motivo (só dá
	pra silenciar "Running"/"Jumping" do lado do CLIENTE, nunca do servidor,
	porque são Sound criados em tempo de execução pelo Animate local de
	cada personagem, um por espectador).

	Config.SOUNDS.Footstep/Jump (LobbyConfig.luau) = "" por enquanto (mudo)
	— troque por um rbxassetid://... quando tiver o som novo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

local function overrideMovementSound(rootPart, soundName, configKey)
	local function applyTo(sound)
		if not sound or not sound:IsA("Sound") then return end
		local function apply()
			sound.SoundId = Config.SOUNDS[configKey] or ""
		end
		apply()
		sound:GetPropertyChangedSignal("SoundId"):Connect(function()
			if sound.SoundId ~= (Config.SOUNDS[configKey] or "") then
				apply()
			end
		end)
	end

	local existing = rootPart:FindFirstChild(soundName)
	if existing then
		applyTo(existing)
	end
	rootPart.ChildAdded:Connect(function(child)
		if child.Name == soundName then
			applyTo(child)
		end
	end)
end

local function onCharacterAdded(character)
	local rootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not rootPart then return end
	overrideMovementSound(rootPart, "Running", "Footstep")
	overrideMovementSound(rootPart, "Jumping", "Jump")
end

local function onPlayerAdded(player)
	player.CharacterAdded:Connect(onCharacterAdded)
	if player.Character then
		onCharacterAdded(player.Character)
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end

print("✅ LobbyMovementSoundsClient carregado (silenciando passos/pulo de todo personagem visível).")
