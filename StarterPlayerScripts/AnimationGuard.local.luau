--[[
	AnimationGuard (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	⚠️ v84 — PEDIDO: "na tela de algumas pessoas, no cliente, quando alguém
	segura o chute, ele buga entre as animações de chutar e andar e fica
	intercalando... faça uma verificação bem minuciosa pra evitar que uma
	animação sobreponha a outra, lembra que é pra funcionar do jeito que está
	escrito".

	O servidor toca as animações de todo mundo e ajusta Priority, Looped e o
	"congela no último quadro" do preparo do chute. Nada disso chega com
	garantia nos OUTROS clientes: cada tela monta a própria cópia da track a
	partir do asset (salvo como Looped), e o congelamento é por tempo — num
	clipe de ~0.25s, a latência basta pra cópia remota passar do fim,
	reiniciar e alternar com o andar antes do "congela" chegar.

	Este script reaplica LOCALMENTE, em cada tela, em TODO personagem, as
	regras de Config.BuildAnimationRules (FootballConfig.luau):
	  1) Priority e Looped de cada animação conhecida — na hora que a track
	     começa e de novo depois que o asset termina de carregar (a carga
	     sobrescreve Looped com o valor do editor);
	  2) HoldAtEnd — o preparo do chute para no último quadro e segura a pose
	     ali, medido pela track da PRÓPRIA tela (sem depender de tempo de rede).
	Animação que não está nas regras (Hissatsu, comemoração...) não é tocada.
	Só muda o que ESTA tela desenha; o servidor continua mandando no jogo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

-- Folga antes do fim pra congelar: chegando a 100% uma track sem loop
-- encerra sozinha e a pose some. 0.05s cobre ~3 quadros a 60fps.
local HOLD_MARGIN = 0.05

-- Compara pelos DÍGITOS do asset: uma track replicada pode trazer o id como
-- "rbxassetid://123" ou "http://www.roblox.com/asset/?id=123".
local function assetDigits(id)
	return type(id) == "string" and id:match("(%d+)%s*$") or nil
end

local rulesByDigits = {}
for id, rule in pairs(Config.BuildAnimationRules()) do
	local digits = assetDigits(id)
	if digits then rulesByDigits[digits] = rule end
end

local function ruleFor(track)
	local animation = track.Animation
	local digits = animation and assetDigits(animation.AnimationId)
	return digits and rulesByDigits[digits] or nil
end

local function applyRule(track, rule)
	if track.Priority ~= rule.Priority then track.Priority = rule.Priority end
	if track.Looped ~= rule.Looped then track.Looped = rule.Looped end
end

local holding = {} -- [AnimationTrack] = true (HoldAtEnd tocando agora)

local function onTrackPlayed(track)
	local rule = ruleFor(track)
	if not rule then return end

	applyRule(track, rule)
	if track.Length <= 0 then
		task.spawn(function()
			local waited = 0
			while track.Length <= 0 and waited < 3 do
				waited += task.wait()
			end
			applyRule(track, rule) -- a carga do asset devolve o Looped do editor
		end)
	end

	if rule.HoldAtEnd then
		holding[track] = true
	end
end

RunService.Heartbeat:Connect(function()
	for track in pairs(holding) do
		if not track.IsPlaying then
			holding[track] = nil
			continue
		end
		local length = track.Length
		if length > 0 and track.Speed > 0 and track.TimePosition >= length - HOLD_MARGIN then
			track:AdjustSpeed(0)
		end
	end
end)

local function watchAnimator(animator)
	animator.AnimationPlayed:Connect(onTrackPlayed)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		onTrackPlayed(track)
	end
end

local function watchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		watchAnimator(animator)
		return
	end
	-- Animator pode ser criado depois (o servidor cria se faltar)
	local connection
	connection = humanoid.ChildAdded:Connect(function(child)
		if child:IsA("Animator") then
			connection:Disconnect()
			watchAnimator(child)
		end
	end)
end

local function watchPlayer(player)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
