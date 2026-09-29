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

-- ⚠️ v85 — PEDIDO: "a animação de chute fica paralisada". Testado ao vivo:
-- ao soltar o botão o servidor dava Stop no preparo (e a track dele
-- encerrava), mas a cópia DESTA tela, parada no último quadro, continuava
-- "tocando" com velocidade 0 — pose presa pra sempre. A fonte da verdade
-- agora é o atributo "KickCharging" do jogador (BallController o liga/
-- desliga junto com o preparo; atributo replica de forma confiável): virou
-- false, esta tela encerra o preparo daquele jogador na hora.
-- FOLGA_ORDEM: a animação e o atributo chegam por canais diferentes — num
-- toque rápido o "false" pode chegar antes da própria track. Só encerra pela
-- checagem contínua depois dessa folga; a mudança do atributo encerra na hora.
local FOLGA_ORDEM = 0.3

local holding = {} -- [AnimationTrack] = { Player = Player, Since = os.clock() } (HoldAtEnd tocando agora)

local function encerrarPreparo(track)
	holding[track] = nil
	if track.IsPlaying then
		track:Stop(0.1)
	end
end

local function onTrackPlayed(track, player)
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
		holding[track] = { Player = player, Since = os.clock() }
	end
end

RunService.Heartbeat:Connect(function()
	for track, info in pairs(holding) do
		if not track.IsPlaying then
			holding[track] = nil
			continue
		end
		if info.Player and info.Player:GetAttribute("KickCharging") ~= true
			and os.clock() - info.Since >= FOLGA_ORDEM then
			encerrarPreparo(track)
			continue
		end
		local length = track.Length
		if length > 0 and track.Speed > 0 and track.TimePosition >= length - HOLD_MARGIN then
			track:AdjustSpeed(0)
		end
	end
end)

local function watchAnimator(animator, player)
	animator.AnimationPlayed:Connect(function(track)
		onTrackPlayed(track, player)
	end)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		onTrackPlayed(track, player)
	end
end

local function watchCharacter(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		watchAnimator(animator, player)
		return
	end
	-- Animator pode ser criado depois (o servidor cria se faltar)
	local connection
	connection = humanoid.ChildAdded:Connect(function(child)
		if child:IsA("Animator") then
			connection:Disconnect()
			watchAnimator(child, player)
		end
	end)
end

local function watchPlayer(player)
	if player.Character then
		task.spawn(watchCharacter, player, player.Character)
	end
	player.CharacterAdded:Connect(function(character)
		watchCharacter(player, character)
	end)
	-- soltou o botão: encerra o preparo desse jogador na hora
	player:GetAttributeChangedSignal("KickCharging"):Connect(function()
		if player:GetAttribute("KickCharging") == true then return end
		for track, info in pairs(holding) do
			if info.Player == player then
				encerrarPreparo(track)
			end
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
