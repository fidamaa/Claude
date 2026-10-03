--[[
	LobbyMovementAnimations (Script)
	LOCAL: ServerScriptService (place Lobby)

	PEDIDO: "eu quero colocar animação de andar, correr, pular, etc..."

	Sobrescreve as animações PADRÃO do Roblox (idle/walk/run/jump/fall)
	direto dentro do "Animate" de cada personagem (Config.ANIMATIONS,
	LobbyConfig.luau). Diferente do som de passos/pulo (que só existe do
	lado do cliente — ver LobbyMovementSoundsClient.local.luau), a
	estrutura do Animate (pastas idle/walk/run/jump/fall com as
	animações padrão dentro) É uma parte normal do Character, clonada
	server-side igual qualquer Part — dá pra sobrescrever o AnimationId
	direto daqui, sem precisar ser cliente.

	"" em qualquer chave = mantém a animação PADRÃO do Roblox pra esse
	estado (não mexe em nada).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

-- ⚠️ v2 — PEDIDO: "agora a animação voltou para a antiga... a nova
-- animação de andar ainda não é aplicada" — mesma causa raiz e mesmo fix
-- do place Game (ver comentário completo em PlayerSystems.legacy.luau,
-- overrideMovementAnimations): o "Animate" de cada personagem só LÊ o
-- AnimationId de cada pasta UMA VEZ (por cliente que está vendo), então
-- mudar o valor DEPOIS que ele já leu não tem efeito nenhum pra aquele
-- cliente — corrida que explica "às vezes funciona, às vezes volta pra
-- antiga". Fix: para de mexer no Animate (fica sempre com o padrão do
-- Roblox) e toca a NOSSA animação por cima via Animator:LoadAnimation
-- com prioridade Action — sempre visualmente por cima da dele.
local MOVEMENT_ANIMATIONS = { "Idle", "Walk", "Run", "Jump", "Fall" }
local RUN_ANIMATION_MIN_SPEED = 24 -- Lobby não tem sprint (padrão do Roblox é 16) — só um limiar razoável

local function overrideMovementAnimations(character)
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then return end

	-- ⚠️ v107: a animação customizada de andar (Config.ANIMATIONS.Walk) é R15 —
	-- no corpo R6 ela não mexe junta nenhuma, só ficava tocando em prioridade
	-- Action por cima do Animate ("uma animação atrapalhando a outra"). No R6 o
	-- andar é o do próprio Animate.
	if humanoid.RigType == Enum.HumanoidRigType.R6 then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local tracks = {}
	for _, configKey in ipairs(MOVEMENT_ANIMATIONS) do
		local animationId = Config.NormalizeAnimationId(Config.ANIMATIONS[configKey])
		if animationId and animationId ~= "" then
			local animation = Instance.new("Animation")
			animation.AnimationId = animationId
			local ok, track = pcall(function() return animator:LoadAnimation(animation) end)
			if ok and track then
				track.Priority = Enum.AnimationPriority.Action
				track.Looped = configKey ~= "Jump"
				tracks[configKey] = track
			end
		end
	end

	if not next(tracks) then return end

	local currentTrack = nil
	local function playTrack(track)
		if track == currentTrack then return end
		if currentTrack then currentTrack:Stop(0.15) end
		currentTrack = track
		if track then track:Play(0.15) end
	end

	local isJumping = false
	local isFalling = false

	local function refreshMoveTrack(speed)
		if isJumping and tracks.Jump then
			playTrack(tracks.Jump)
		elseif isFalling and tracks.Fall then
			playTrack(tracks.Fall)
		elseif speed and speed >= RUN_ANIMATION_MIN_SPEED and tracks.Run then
			playTrack(tracks.Run)
		elseif speed and speed > 0.5 and tracks.Walk then
			playTrack(tracks.Walk)
		elseif tracks.Idle then
			playTrack(tracks.Idle)
		else
			playTrack(nil)
		end
	end

	humanoid.Running:Connect(function(speed)
		if not isJumping and not isFalling then
			refreshMoveTrack(speed)
		end
	end)

	humanoid.Jumping:Connect(function(active)
		isJumping = active
		refreshMoveTrack(humanoid.MoveDirection.Magnitude > 0 and humanoid.WalkSpeed or 0)
	end)

	humanoid.FreeFalling:Connect(function(active)
		isFalling = active
		refreshMoveTrack(humanoid.MoveDirection.Magnitude > 0 and humanoid.WalkSpeed or 0)
	end)

	refreshMoveTrack(0)
end

local function onCharacterAdded(character)
	overrideMovementAnimations(character)
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

print("✅ LobbyMovementAnimations carregado.")
