--[[
	MovementSoundsClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Game)

	PEDIDO: "quero mudar o som de passos, remova-o por enquanto, mas
	coloque um espaço pra eu poder alterá-lo, junto com o de pulo também."
	SEGUNDA RODADA: "Som de passos/pulo continua presente" — a primeira
	tentativa (um Script no ServerScriptService) NUNCA podia ter funcionado.

	POR QUE PRECISA SER CLIENTE (e não servidor): os sons "Running" (passos)
	e "Jumping" (pulo) são criados em TEMPO DE EXECUÇÃO pelo código do
	"Animate" — o LocalScript que o próprio Roblox insere dentro de cada
	personagem. Um LocalScript parentado dentro de um Character SÓ RODA no
	cliente que está enxergando aquele personagem (o dono E qualquer outro
	jogador que o tenha por perto) — CADA cliente roda sua PRÓPRIA cópia do
	Animate pra CADA personagem que vê, e os Sound que ele cria com
	Instance.new ficam só ali, na cópia local daquele cliente específico.
	O servidor NUNCA enxerga esses Sound (bem diferente de uma Part normal,
	que replica pra todo mundo) — por isso o Script no ServerScriptService
	nunca encontrava nada pra silenciar, mesmo esperando.

	Esse script roda em cada cliente e silencia os sons de passos/pulo de
	TODO personagem que ele consegue ver (o próprio E o de todo mundo) —
	assim, cada jogador silencia exatamente o que ELE ouviria, e como isso
	roda em todo cliente ao mesmo tempo, ninguém ouve passos/pulo de
	ninguém.

	Config.SOUNDS.Footstep/Jump (FootballConfig.luau) = "" por enquanto
	(mudo) — troque por um rbxassetid://... quando tiver o som novo, sem
	precisar mexer neste script.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local function overrideMovementSound(rootPart, soundName, configKey)
	local function applyTo(sound)
		if not sound or not sound:IsA("Sound") then return end
		local function apply()
			sound.SoundId = Config.SOUNDS[configKey] or ""
		end
		apply()
		-- Reforça se o próprio Animate tentar tocar/trocar o SoundId de
		-- novo depois (ex.: numa mudança de estado do Humanoid).
		sound:GetPropertyChangedSignal("SoundId"):Connect(function()
			if sound.SoundId ~= (Config.SOUNDS[configKey] or "") then
				apply()
			end
		end)
	end

	-- Pega o som se ele já existir, e também fica de olho em caso de
	-- aparecer mais tarde (o Animate local pode demorar um pouco pra criar
	-- os Sound depois do spawn).
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

print("✅ MovementSoundsClient carregado (silenciando passos/pulo de todo personagem visível).")
