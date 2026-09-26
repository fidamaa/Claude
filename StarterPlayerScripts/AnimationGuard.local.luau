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

-- ⚠️ v86 — PEDIDO: "se eu chutar sem a bola, a animação de chutar não sai, e
-- a animação de chute fica paralisada".
--
-- CAUSA: o HoldAtEnd congela o preparo (AdjustSpeed(0)) na cópia LOCAL da
-- track, e nada aqui soltava essa cópia depois. O servidor dava Stop, mas a
-- cópia desta tela continuava parada na pose de perna levantada — e, como o
-- chute está na MESMA prioridade (Action), os dois se misturavam e o chute
-- parecia não sair. O comentário do v85 no BallController já dizia que este
-- script encerraria o preparo quando o atributo KickCharging virasse false,
-- mas essa parte nunca tinha sido escrita.
--
-- AGORA o preparo congelado é solto em três situações, o que vier primeiro:
--   1) o atributo KickCharging do dono vira false (soltou o botão);
--   2) começa outra animação de Action no mesmo personagem (chute,
--      cabeceio, carrinho...) — a ação de verdade sempre substitui o preparo;
--   3) rede de segurança: KickCharging já está false e o preparo segue
--      preso por mais de HOLD_ORPHAN_GRACE (atributo e animação chegam por
--      canais diferentes e podem vir fora de ordem).
local HOLD_ORPHAN_GRACE = 0.3
local RELEASE_FADE = 0.1

local holding = {} -- [AnimationTrack] = { Character = Model, Since = os.clock() }

local function playerOf(character)
	return character and Players:GetPlayerFromCharacter(character) or nil
end

local function releaseHolds(character)
	if not character then return end
	for track, info in pairs(holding) do
		if info.Character == character then
			holding[track] = nil
			pcall(function() track:Stop(RELEASE_FADE) end)
		end
	end
end

local function onTrackPlayed(track, character)
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
		holding[track] = { Character = character, Since = os.clock() }
	elseif rule.Priority == Enum.AnimationPriority.Action then
		releaseHolds(character) -- ⚠️ v86 (2): a ação de verdade substitui o preparo
	end
end

RunService.Heartbeat:Connect(function()
	local agora = os.clock()
	for track, info in pairs(holding) do
		if not track.IsPlaying then
			holding[track] = nil
			continue
		end
		-- ⚠️ v86 (3): preparo órfão — o botão já foi solto e a pose segue presa
		local dono = playerOf(info.Character)
		if dono and dono:GetAttribute("KickCharging") == false and agora - info.Since > HOLD_ORPHAN_GRACE then
			holding[track] = nil
			pcall(function() track:Stop(RELEASE_FADE) end)
			continue
		end
		local length = track.Length
		if length > 0 and track.Speed > 0 and track.TimePosition >= length - HOLD_MARGIN then
			track:AdjustSpeed(0)
		end
	end
end)

local function watchAnimator(animator, character)
	animator.AnimationPlayed:Connect(function(track)
		onTrackPlayed(track, character)
	end)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		onTrackPlayed(track, character)
	end
end

local function watchCharacter(character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		watchAnimator(animator, character)
		return
	end
	-- Animator pode ser criado depois (o servidor cria se faltar)
	local connection
	connection = humanoid.ChildAdded:Connect(function(child)
		if child:IsA("Animator") then
			connection:Disconnect()
			watchAnimator(child, character)
		end
	end)
end

local function watchPlayer(player)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player.CharacterAdded:Connect(watchCharacter)
	-- ⚠️ v86 (1): soltou o botão -> solta o preparo congelado desta tela
	player:GetAttributeChangedSignal("KickCharging"):Connect(function()
		if player:GetAttribute("KickCharging") ~= true then
			releaseHolds(player.Character)
		end
	end)
end

for _, player in ipairs(Players:GetPlayers()) do
	watchPlayer(player)
end
Players.PlayerAdded:Connect(watchPlayer)
