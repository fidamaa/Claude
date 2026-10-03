--[[
	PulseController (Script)
	LOCAL: ServerScriptService (place Game)

	Dono dos PULSOS (ativos). REWORK "PULSO": não existe mais "armar e
	esperar a ação normal (mirar/carregar/soltar) bater dentro de 5s" —
	agora apertar o botão do Pulso EXECUTA a ação sozinho, na hora (auto-
	mira/auto-alvo, ver os _G.PulseExecute* em BallController.lua).

	Jogador de linha tem 2 SLOTS independentes (tecla Q = slot 1, tecla E
	= slot 2); goleiro DENTRO da própria área (ver GKAreaUtil.lua) só tem
	o slot 1, tecla R — preenchidos pelo Roll do Lobby (o mais recente
	sorteado vai pro slot 1, o que estava no slot 1 desce pro slot 2, ver
	RollServer.legacy.luau de lá).

	⚠️ PULSO v3 — O QUE MUDOU AQUI:
	1. O QTE virou COMBO DE TECLAS. O campo Window ({Delay, Length}) NÃO
	   EXISTE MAIS (suporte removido); no lugar entra
	        Combo = { Delay, StepTime, Keys = {"Q","E","Q"} }.
	   O servidor guarda o instante de abertura de cada passo e valida
	   passo a passo: o aperto só conta como ACERTO se chegar DENTRO da
	   janela daquele passo E com a tecla certa. Tecla errada ou passo
	   perdido faz SÓ AQUELE passo falhar — o combo continua no próximo.
	   Acertou TODOS os passos → def.Perfect; qualquer outra coisa
	   (inclusive 0 acertos) → def.Bom. NUNCA existe whiff total: a ação
	   SEMPRE dispara. A resolução automática continua agendada pelo
	   tempo total (Delay + StepTime * #Keys), pra nada ficar pendurado.
	2. IFRAME EM WIND-UP LONGO (regra GENÉRICA, não Pulso a Pulso): se a
	   duração total do wind-up passar de Config.PULSE_IFRAME_MIN_WINDUP
	   (2s), o jogador ganha iframe de Pulso durante TODO o wind-up —
	   ninguém consegue desarmá-lo/roubar dele nesse período (ver
	   _G.GrantPulseIframe/_G.HasPulseIframe no BallController). O campo
	   opcional Iframe = true força isso mesmo num wind-up curto.
	3. OncePerMatch FOI REMOVIDO (nenhum Pulso usa mais — os Míticos
	   recarregam com cooldown normal agora, pedido do usuário). O
	   feedback "AlreadyUsedThisMatch" nunca mais é mandado; a chave
	   continua existindo no cliente só por compatibilidade.
	4. CHAVES DE EFEITO NOVAS tratadas aqui (as puramente de estado) ou
	   despachadas pro BallController: SelfIframe, StunRadius +
	   StunDuration, KnockbackRadius + KnockbackForce, PassLockSeconds,
	   BallMagnetRadius, CooldownRefundOther, InstinctCharge,
	   TeamBuffRadius + TeamBuffDuration + TeamSpeedMult + TeamForceMult.
	   Ver applyExtraEffectKeys mais abaixo.

	FLUXO (por slot), ver Remotes.UsePulse abaixo:
	1. Cliente aperta Q/E (linha) ou R (GK) → Remotes.UsePulse:FireServer(slot).
	2. Servidor valida cooldown/role E a PRECONDIÇÃO da ação (ex:
	   Shot/Pass/DribbleMove exigem posse de bola; Tackle exige NÃO ter
	   posse E um adversário com a bola em alcance; Header exige bola no
	   ar por perto; SetPieceKick exige bola parada + ser o cobrador).
	   Falhando a precondição, NÃO gasta cooldown — só avisa "NoTarget".
	3. Passando: o cooldown já é marcado NA HORA (é esse aperto que
	   "gasta" o Pulso, mesmo que o efeito real só resolva um pouco
	   depois, no fim do combo).
	4. Sem combo (def.Combo == nil): executa NA HORA com def.Effect.
	5. Com combo: avisa o cliente (PulsePrecisionPrompt, agora com o
	   array de teclas no fim), concede o iframe de wind-up se for o caso
	   e agenda a resolução automática pro instante em que o último passo
	   fecha. Cada Remotes.PulsePrecisionInput(slot, keyName) que chega é
	   comparado — no servidor, contra o tick() de abertura/fechamento do
	   passo que ELE guardou — pra decidir acerto/erro. Acertando o
	   último passo, resolve na hora em vez de esperar.
	6. TETO DURO: do aperto até a ação resolver, no máximo
	   Config.PULSE_MAX_WINDUP (5s) — o maior do jogo é o Chute Fatal, em
	   2.7s.

	Mantido do sistema antigo (contrato público _G.* usado por
	InstinctController/BallController/PlayerSystems — não renomeado):
	GetEquippedPulse, GetPulseSpeedMultiplier, GetPulseStaminaRegenMultiplier,
	GetPulsePickupRadiusAdd, GetPulseActiveAnkleRangeAdd,
	GetPulseActiveKickForceMult, GetPulseBlock, GetPulseGKDiveBonus, e o
	brilho de raridade (RARITY_GLOW_COLOR) enquanto um Pulso "Buff" está
	em duração.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local AbilityAura = require(ReplicatedStorage:WaitForChild("AbilityAura")) -- ⚠️ v45: auras de habilidade (contorno pulsante, sem pintar o corpo)
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
local GKAreaUtil = require(ReplicatedStorage:WaitForChild("GKAreaUtil"))
local Remotes = Config.Remotes

-- ⚠️ v4: NOMES ANTIGOS. Vários Pulsos foram FUNDIDOS em outro na v4 (ver
-- Data.LegacyNames em PulseInstinctData.luau). Quem tinha um deles salvo
-- e equipado não pode ficar sem Pulso nenhum na partida — o nome antigo é
-- resolvido aqui pro atual ANTES de procurar na lista.
local function findPulse(name)
	if not name then return nil end
	if PulseData.ResolveName then
		name = PulseData.ResolveName(name)
	end
	for _, def in ipairs(PulseData.Pulses) do
		if def.Name == name then return def end
	end
	return nil
end

-- ===== ESTADO POR JOGADOR (tudo indexado [player][slot], exceto onde comentado) =====
local Loadout = {}          -- [player][slot] = pulseName (string)
local ReadyAt = {}           -- [player][slot] = tick() em que o cooldown termina
local ActiveBuff = {}        -- [player] = { {Effect, ExpiresAt, Rarity}, {...} } (1 por slot — Pulsos "Buff")
local TeammateBuff = {}      -- [player] = { ForceMult, ExpiresAt } — bônus no PRÓXIMO chute desse jogador (Pulso do Camisa 10/Passe Enfiado/Maestro)
local TeamBuff = {}          -- ⚠️ v3: [player] = { SpeedMult, ForceMult, ExpiresAt } — buff de ÁREA em cima do time (Pulso do General)
local Pending = {}           -- [player][slot] = estado do combo em andamento (ver startCombo)
local LastAimPoint = {}      -- ⚠️ v7: [player] = Vector3 — pra onde o jogador estava mirando quando apertou o Pulso (ver Remotes.UsePulse mais abaixo), pra Hissatsu de chute mirar EXATAMENTE igual um chute padrão em vez de mira automática de canto
local GKGuard = {}           -- ⚠️ v7: [player] = { Def, Slot, ExpiresAt, GuardSize } — "guarda" armada pela Hissatsu de goleiro (ver startGKGuard mais abaixo)

-- ⚠️ NOVO (ferramenta de teste, ver DebugAbilitySelector.lua): quando
-- ligado pra um jogador, ignora TODO cooldown (UsePulse nunca bloqueia
-- por "OnCooldown") e zera o Delay (wind-up) de qualquer Combo — o
-- StepTime de cada passo continua valendo, então ainda dá pra testar o
-- timing do combo, só sem esperar o cooldown nem o wind-up entre um
-- teste e outro.
local DebugNoDelay = {} -- [player] = true/false
_G.SetPulseDebugNoDelay = function(player, enabled)
	DebugNoDelay[player] = enabled and true or nil
end

-- ⚠️ v110 — PEDIDO: "coloca as opções de zerar o cooldown, que não estão
-- funcionando mais... tirar todos os cooldowns das Hissatsus pra poder testar,
-- e a opção de energia infinita". O botão do debugger só desligava o cooldown
-- das ARMAS (Instinto) — nunca chamou nada daqui. Agora (ver
-- DebugAbilitySelector): SemCooldown = ignora o cooldown (sem mexer no preparo
-- nem na cutscene, pra testar a técnica como ela é), Energia = o pool nunca
-- baixa. O atributo no Player avisa o HUD pra não mostrar contagem.
local DebugFlags = {} -- [player] = { SemCooldown = bool, Energia = bool }
_G.SetPulseDebugFlag = function(player, nome, ligado)
	DebugFlags[player] = DebugFlags[player] or {}
	DebugFlags[player][nome] = ligado and true or nil
	player:SetAttribute("Debug" .. nome, ligado and true or nil)
	if nome == "Energia" and ligado and _G.ZerarPulseDebug then _G.ZerarPulseDebug(player, "Energia") end
end

local function ensurePlayerTables(player)
	Loadout[player] = Loadout[player] or {}
	ReadyAt[player] = ReadyAt[player] or {}
	ActiveBuff[player] = ActiveBuff[player] or {}
	Pending[player] = Pending[player] or {}
end

-- slot1Name = mais recente sorteado, desce pros seguintes conforme sai
-- coisa nova (ver equiparNoSlot em RollServer.legacy.luau, no Lobby).
-- ⚠️ v76: slot3Name adicionado (3º Hissatsu, comprado com Robux) — nil
-- pra quem não comprou, exatamente como slot2 sempre tratou "sem nada
-- nesse slot".
_G.SetPlayerLoadout = function(player, slot1Name, slot2Name, slot3Name)
	ensurePlayerTables(player)
	Loadout[player][1] = slot1Name
	Loadout[player][2] = slot2Name
	Loadout[player][3] = slot3Name
end

_G.GetEquippedPulse = function(player, slot)
	return Loadout[player] and Loadout[player][slot]
end

-- ⚠️ v7: PEDIDO — "a mira da Hissatsu tem que ser exatamente onde o cara
-- estiver mirando, igual o chute padrão". Guardado aqui (setado no
-- Remotes.UsePulse mais abaixo) e lido por BallController.legacy.luau em
-- _G.PulseComputeShotTarget, no lugar da mira automática de canto.
-- ⚠️ v67: escrita do ponto de mira, pra quem não é o UsePulse. Hoje quem
-- usa é o InstinctController: o Chute Direto (Instinto) precisa gravar a
-- mira no MESMO lugar que a Hissatsu lê, senão ele reaproveita o ponto
-- sobrado da última Hissatsu e sai em qualquer direção.
_G.SetPulseAimPoint = function(player, ponto)
	if typeof(ponto) == "Vector3" then
		LastAimPoint[player] = ponto
	end
end

_G.GetPulseAimPoint = function(player)
	return LastAimPoint[player]
end

-- ⚠️ v92 — MIRA AO VIVO NO PREPARO. PEDIDO: "acho que a Hissatsu tá saindo
-- onde eu tô olhando. Pode fazer ela sair onde eu tô olhando, mas também
-- onde eu estou mirando com o mouse." A mira era tirada SÓ no aperto da
-- tecla, e entre o aperto e o chute passam o preparo + QTE + cutscene (uns
-- 5-6s) — quem mirava com o mouse depois de apertar não era atendido. Agora
-- o cliente manda o ponto de mira ao vivo (mouse livre = onde o cursor
-- aponta; Shift Lock = centro da tela, onde está olhando) e ele vale
-- enquanto a Hissatsu de chute está no PREPARO. Trava quando a janela do QTE
-- abre, porque aí o mouse vai clicar nos alvos do QTE, não mirar.
Remotes.UpdatePulseAim.OnServerEvent:Connect(function(player, ponto)
	if typeof(ponto) ~= "Vector3" then return end
	if ponto.X ~= ponto.X or ponto.Y ~= ponto.Y or ponto.Z ~= ponto.Z then return end -- NaN
	local pendentes = Pending[player]
	if not pendentes then return end
	for _, state in pairs(pendentes) do
		if state and not state.Resolved and state.Kind == "Tap" and state.Def and state.Def.Action == "Shot"
			and tick() < state.StepsStart + (state.PrepTime or 0) then
			LastAimPoint[player] = ponto
			return
		end
	end
end)

-- ⚠️ v7: PEDIDO — congela o MOVIMENTO (não o resto: o jogador ainda
-- reage a QTE) por "duration" segundos. Usado pela Hissatsu de goleiro
-- (fica parado enquanto a guarda está armada) e pela Grande Muralha
-- (FreezeSelf, ver executeBuff) — "ele não vai poder se mexer nem na
-- Hissatsu do goleiro, nem na do defensor".
-- ⚠️ v9 FIX: "ainda usando os pulsos eu conseguia me mover" — o Heartbeat
-- de sprint/stamina em PlayerSystems.legacy.luau REESCREVE humanoid.
-- WalkSpeed todo frame (sprint ligado/desligado), e não sabia nada sobre
-- esse freeze — então o WalkSpeed=0 durava só até o próximo frame. Agora
-- guarda um "congelado até tick() X" por jogador e expõe _G.IsPulseFrozen,
-- que PlayerSystems passa a respeitar (mesmo padrão de isStunned/
-- isFrozenForSetPiece que já existia lá).
local FrozenUntil = {} -- [player] = tick() até quando o movimento fica travado

local function freezeMovement(player, duration)
	local character = player.Character
	local humanoid = character and character:FindFirstChild("Humanoid")
	if not humanoid or duration <= 0 then return end
	local original = humanoid.WalkSpeed
	FrozenUntil[player] = tick() + duration
	humanoid.WalkSpeed = 0
	task.delay(duration, function()
		if FrozenUntil[player] and tick() >= FrozenUntil[player] then
			FrozenUntil[player] = nil
			if humanoid.Parent then
				humanoid.WalkSpeed = original
			end
		end
	end)
end

_G.IsPulseFrozen = function(player)
	local until_ = FrozenUntil[player]
	return until_ ~= nil and tick() < until_
end

-- ⚠️ v11: solta o congelamento ANTES da hora. Usado quando o QTE do chute
-- resolve mais cedo (o jogador acertou os cliques rápido) — sem isso, quem
-- executa bem ficaria plantado o mesmo tempo que quem deixou a janela
-- inteira passar, ou seja, jogar bem seria punido. Só limpa o FrozenUntil:
-- o WalkSpeed de verdade quem reescreve é o Heartbeat de sprint em
-- PlayerSystems, que consulta _G.IsPulseFrozen todo frame.
local function clearMovementFreeze(player)
	FrozenUntil[player] = nil
end

-- ⚠️ v24 — PEDIDO: "impeça que o personagem chute quando estiver usando a
-- Hissatsu. Quando você usa a Hissatsu, você não pode tirar a bola do pé."
--
-- Enquanto um QTE de Hissatsu que MEXE COM A BOLA está aberto, o jogador não
-- pode chutar/passar/driblar por fora dela: senão dava pra armar a Hissatsu,
-- bater um chute normal no meio do wind-up e a Hissatsu resolvia no vazio
-- (ou pior, roubava a bola de volta de quem já tinha recebido).
-- Hissatsu que NÃO depende da bola (goleiro, desarme, Teia, Muralha) fica de
-- fora: elas acontecem justamente quando a bola não é sua.
local BALL_HOLDING_ACTIONS = {
	Shot = true,
	Header = true,
	DribbleMove = true,
	Pass = true,
	SetPieceKick = true,
}

_G.IsPulseInProgress = function(player)
	local pending = Pending[player]
	if not pending then return false end
	for _, state in pairs(pending) do
		if state and not state.Resolved then
			local def = state.Def
			-- ⚠️ v120b — PEDIDO: "às vezes depois do carrinho o carrinho ou o dash param
			-- de funcionar". Um combo que nunca resolvia (jogador resetado/ragdoll no
			-- meio) deixava o dash bloqueado pra sempre: combo velho (> 6s) não conta.
			local velho = state.StepsStart and (tick() - state.StepsStart) > 6
			if def and BALL_HOLDING_ACTIONS[def.Action] and not velho then
				return true
			end
		end
	end
	return false
end

-- ============================================================
-- ⚠️ v11 — MECÂNICAS NOVAS DO REWORK DE PULSOS
-- Ver o cabeçalho de Data.Pulses em PulseInstinctData.luau pra qual Pulso
-- usa o quê. Tudo aqui é self-contido (não depende do BallController
-- além dos _G.StunPlayer/_G.FreezePlayer que já existiam).
-- ============================================================

local function opponentsOf(player)
	local list = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player then continue end
		-- Sem time definido dos dois lados não dá pra afirmar que é
		-- adversário — mesma regra conservadora do resto do arquivo.
		if player.Team and other.Team and player.Team == other.Team then continue end
		local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(list, { Player = other, Root = root })
		end
	end
	return list
end

-- ============================================================
-- ⚠️ v14 — SALTO DA HISSATSU (PEDIDO: "o Fire Tornado, é pro cara poder
-- pular, girar, e jogar do ar. Algumas habilidades também fazem isso, às
-- vezes de uma altura diferente").
--
-- O def.AirLaunchHeight (em studs) diz a que altura aquela Hissatsu joga o
-- jogador. Ele é lançado pra cima quando o PREPARO acaba (o instante em
-- que a técnica "começa" de verdade) e fica PENDURADO no ápice até o QTE
-- resolver — é o hang time do anime, e é o que garante que o chute saia do
-- ar mesmo que o jogador demore pra acertar os cliques. Solta a gravidade
-- de volta assim que resolve.
--
-- A animação em si fica por conta do usuário; aqui só existe o movimento
-- (subir, ficar, cair), que é o que o código precisa garantir pra a
-- animação ter onde acontecer.
-- ============================================================
local AirHold = {} -- [player] = { Root, HoldFrom = tick() do ápice, Expire }

local function launchIntoAir(player, height)
	if not height or height <= 0 then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local gravity = workspace.Gravity
	if gravity <= 0 then return end

	-- v = raiz(2*g*h): a velocidade exata pra chegar em "height" studs e
	-- parar lá — assim a altura no dado é a altura de verdade em campo.
	local speed = math.sqrt(2 * gravity * height)
	local current = root.AssemblyLinearVelocity
	root.AssemblyLinearVelocity = Vector3.new(current.X, speed, current.Z)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Sem isso o Humanoid tenta "grudar" no chão de volta (ele está com
		-- WalkSpeed 0 pelo freeze do wind-up) e engole o impulso.
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
	end

	AirHold[player] = {
		Root = root,
		HoldFrom = tick() + speed / gravity, -- tempo até o ápice
		-- Rede de segurança: mesmo que alguma coisa impeça o QTE de
		-- resolver, ninguém fica flutuando pra sempre.
		Expire = tick() + Config.PULSE_MAX_WINDUP + 2,
	}
end

local function releaseAirHold(player)
	AirHold[player] = nil
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	for player, hold in pairs(AirHold) do
		if not hold.Root or not hold.Root.Parent or now >= hold.Expire then
			AirHold[player] = nil
		elseif now >= hold.HoldFrom then
			-- No ápice: zera só a queda (X/Z continuam, então um chute que
			-- empurra pro lado ainda empurra) — na prática é gravidade
			-- desligada enquanto a técnica acontece.
			local velocity = hold.Root.AssemblyLinearVelocity
			hold.Root.AssemblyLinearVelocity = Vector3.new(velocity.X, 0, velocity.Z)
		end
	end
end)

-- ===== CORREDOR (Tornado de Fogo / Fúria Glacial) =====
-- A diferença que justifica esses dois Pulsos existirem: o efeito NÃO é
-- um raio em volta do chutador (isso só queima quem já te alcançou) — é
-- uma faixa entre o jogador e a MIRA dele, ou seja, quem está no caminho
-- da bola e ia tentar bloquear. Usa LastAimPoint, o mesmo ponto que o
-- chute de verdade usa (ver _G.GetPulseAimPoint).
local function applyCorridorEffect(player, spec, apply)
	if typeof(spec) ~= "table" then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local target = LastAimPoint[player]
	if not root or not target then return end

	local origin = root.Position
	local delta = target - origin
	local length = delta.Magnitude
	if length < 1 then return end
	local direction = delta.Unit
	local width = math.max(spec.Width or 6, 1)
	local duration = math.max(spec.Duration or 0.5, 0.05)

	-- Quem está DENTRO do corredor do chute (entre você e o alvo, e perto o
	-- bastante da reta)?
	local function dentroDoCorredor(posicao)
		local along = (posicao - origin):Dot(direction)
		if along < 0 or along > length then return false end -- atrás de você ou depois do alvo
		return ((origin + direction * along) - posicao).Magnitude <= width
	end

	for _, entry in ipairs(opponentsOf(player)) do
		if dentroDoCorredor(entry.Root.Position) then
			apply(entry.Player, duration)
		end
	end

	-- ⚠️ v46: o goleiro BOT também. A Fúria Glacial promete "se o goleiro
	-- encostar, ele congela junto e o rebote fica livre", mas opponentsOf
	-- varre Players:GetPlayers() e o bot não é um Player — então contra bot
	-- (o caso normal, já que a vaga de GK nem é mais reservada) essa metade
	-- da habilidade nunca acontecia. `apply` espera um Player, então o bot
	-- vai pelo caminho próprio dele (_G.FreezeGKBot em GKBotController).
	if _G.GetGKBotPositions and _G.FreezeGKBot and player.Team then
		for _, bot in ipairs(_G.GetGKBotPositions()) do
			if bot.TeamName ~= player.Team.Name and dentroDoCorredor(bot.Position) then
				_G.FreezeGKBot(bot.TeamName, duration)
			end
		end
	end
end

-- ===== PARADA DE TEMPO (Hora do Céu) =====
-- ⚠️ v20 — PEDIDO: "ele para o tempo, então não precisa driblar nada. Faça
-- ele só congelar TODOS os jogadores (menos o bot ou o GK_Role)."
-- Antes só pegava ADVERSÁRIOS. Agora pega todo mundo no raio — companheiro
-- incluído, porque tempo parado é tempo parado pra todos. Duas exceções:
--   • você (quem usou);
--   • quem é goleiro (Role == "GK"): congelar o goleiro transformaria a
--     Hissatsu num gol grátis, e ela é um recurso de DRIBLE, não de
--     finalização.
-- O GKBot nem entra na conta: ele não é um Player, então nunca aparece
-- neste laço.
local function applyTimeStop(player, radius, duration)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not _G.FreezePlayer then return end
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player then continue end
		if other:GetAttribute("Role") == "GK" then continue end
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if not otherRoot then continue end
		if (otherRoot.Position - root.Position).Magnitude <= radius then
			_G.FreezePlayer(other, duration)
		end
	end
end

-- ===== ZONA DE LENTIDÃO (Teia / Névoa) =====
-- O único efeito PERSISTENTE do jogo: fica no chão depois que o jogador
-- saiu de perto. Não usa freezeMovement (que é tudo-ou-nada) — entra como
-- multiplicador em _G.GetPulseSpeedMultiplier, que PlayerSystems já lê
-- todo frame, então sobrevive ao Heartbeat de sprint que reescreve
-- WalkSpeed (mesmo problema que o v9 FIX do freezeMovement resolveu).
local SlowZones = {}   -- lista de { Position, Radius, Mult, ExpiresAt, Team, Part }
local SlowedUntil = {} -- [player] = { Mult, ExpiresAt } — renovado a cada Heartbeat dentro da zona

-- ⚠️ v67 — VENDAVAL: pique temporário depois da finta.
-- PEDIDO: "põe um drible que faz alguma coisa realmente." Guardado aqui e
-- lido pelo getter abaixo (que PlayerSystems já consulta todo frame) — mexer
-- no WalkSpeed direto não sobreviveria ao Heartbeat de sprint, que o
-- reescreve sozinho. Mesmo motivo da lentidão por zona.
local PiqueAtivo = {} -- [player] = { Mult, ExpiresAt }

local function aplicarPique(player, mult, duracao)
	if not mult or not duracao or mult <= 0 or duracao <= 0 then return end
	PiqueAtivo[player] = { Mult = mult, ExpiresAt = tick() + duracao }
end

local function getPiqueMultiplier(player)
	local p = PiqueAtivo[player]
	if not p then return 1 end
	if tick() >= p.ExpiresAt then
		PiqueAtivo[player] = nil
		return 1
	end
	return p.Mult
end

-- ⚠️ v67 — NÉVOA: ZONA DE INVISIBILIDADE.
-- PEDIDO: "a Névoa está colocando uma área no chão, não pode ser assim. A
-- Névoa é uma área que deixa o próprio jogador invisível ali dentro. Faz um
-- cilindro, um círculo maior em volta, e deixa o cara transparente, meio que
-- invisível ali dentro. A BOLA também some junto com o jogador, e só aparece
-- na hora que ele sair da área."
--
-- Diferente da Teia (que é lentidão pra quem ENTRA), esta é sobre QUEM a
-- criou: ele fica escondido enquanto estiver dentro. A transparência é
-- aplicada no servidor de propósito — assim todo mundo vê a mesma coisa, e
-- o dono também se vê apagado, o que é a leitura certa de "estou na névoa".
--
-- A bola some junto SÓ enquanto ele for o dono dela: se perder a posse
-- dentro da névoa, a bola reaparece na hora, senão viraria uma bola
-- invisível solta em campo.
local FogZones = {} -- { Player, Position, Radius, ExpiresAt, Part, Escondido }

local function definirTransparencia(character, valor)
	if not character then return end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then
			if d.Name ~= "HumanoidRootPart" then
				pcall(function() d.Transparency = valor end)
			end
		end
	end
end

local function spawnFogZone(player, radius, duration)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local part = Instance.new("Part")
	part.Name = "PulseFogZone"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(Config.FOG_ZONE_HEIGHT, radius * 2, radius * 2)
	part.CFrame = CFrame.new(root.Position.X, root.Position.Y, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = Config.FOG_ZONE_COLOR
	part.Transparency = Config.FOG_ZONE_TRANSPARENCY
	part.Parent = workspace

	table.insert(FogZones, {
		Player = player,
		Position = root.Position,
		Radius = radius,
		ExpiresAt = tick() + duration,
		Part = part,
		Escondido = false,
	})
end

RunService.Heartbeat:Connect(function()
	for i = #FogZones, 1, -1 do
		local z = FogZones[i]
		local expirou = tick() >= z.ExpiresAt
		local character = z.Player and z.Player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")

		local dentro = false
		if not expirou and root then
			local d = (Vector3.new(root.Position.X, 0, root.Position.Z)
				- Vector3.new(z.Position.X, 0, z.Position.Z)).Magnitude
			dentro = d <= z.Radius
		end

		-- ⚠️ v110 — PEDIDO: "a névoa precisa deixar o player 100% INVISÍVEL pra
		-- todos os outros jogadores, a não ser ele mesmo e o próprio time". Antes
		-- a transparência era aplicada aqui no servidor (0.85 pra todo mundo).
		-- Agora o servidor só MARCA (atributos) e cada cliente decide o que vê
		-- (NevoaClient.local.luau): adversário = invisível (corpo, nome, efeitos
		-- e a bola dele); ele e o time = meio transparente, pra saber que está
		-- escondido.
		if dentro ~= z.Escondido then
			z.Escondido = dentro
			if character then character:SetAttribute("NaNevoa", dentro or nil) end
		end
		-- a bola some junto, mas só enquanto ELE for o dono dela (perdeu a posse
		-- dentro da névoa = a bola reaparece na hora)
		do
			local bola = workspace:FindFirstChild(Config.BALL_NAME)
			local dono = _G.GetBallOwner and _G.GetBallOwner()
			local escondida = z.Escondido and dono == z.Player and z.Player.UserId or nil
			if bola and (escondida or bola:GetAttribute("EscondidaNaNevoa") == z.Player.UserId)
				and bola:GetAttribute("EscondidaNaNevoa") ~= escondida then
				bola:SetAttribute("EscondidaNaNevoa", escondida)
			end
		end

		if expirou then
			if character then character:SetAttribute("NaNevoa", nil) end
			local bola = workspace:FindFirstChild(Config.BALL_NAME)
			if bola and bola:GetAttribute("EscondidaNaNevoa") == z.Player.UserId then
				bola:SetAttribute("EscondidaNaNevoa", nil)
			end
			if z.Part then z.Part:Destroy() end
			table.remove(FogZones, i)
		end
	end
end)

local function spawnSlowZone(player, radius, duration, mult)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- ⚠️ v110 — PEDIDO: "a Teia com uma teia bonita e visível". Era um disco roxo
	-- liso. Agora é uma TEIA DE ARANHA de verdade no gramado: fios radiais +
	-- anéis em espiral, que se espalham a partir de quem lançou (cresce em 0.5s).
	local TweenService = game:GetService("TweenService")
	local chaoY = root.Position.Y - 2.9
	do
		local filtro = RaycastParams.new()
		filtro.FilterType = Enum.RaycastFilterType.Exclude
		filtro.RespectCanCollide = true
		local ignorar = {}
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		if bola then table.insert(ignorar, bola) end
		filtro.FilterDescendantsInstances = ignorar
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -12, 0), filtro)
		if hit then chaoY = hit.Position.Y end
	end
	local centro = Vector3.new(root.Position.X, chaoY + 0.06, root.Position.Z)
	local part = Instance.new("Model")
	part.Name = "PulseSlowZone"
	local COR_FIO = Color3.fromRGB(236, 248, 228)
	local function fio(a, b, grossura, transp)
		local p = Instance.new("Part")
		p.Name = "Fio"
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = COR_FIO
		p.Transparency = transp
		local len = (b - a).Magnitude
		p.Size = Vector3.new(grossura, 0.05, 0.05)
		p.CFrame = CFrame.lookAt((a + b) / 2, b)
		p.Parent = part
		-- espalha do centro pra fora
		local atraso = ((a + b) / 2 - centro).Magnitude / radius * 0.45
		task.delay(atraso, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.15), { Size = Vector3.new(grossura, 0.05, len) }):Play()
			end
		end)
	end
	local RAIOS, ANEIS = 14, 7
	local angulos = {}
	for i = 1, RAIOS do
		angulos[i] = (i / RAIOS) * math.pi * 2 + math.sin(i * 1.7) * 0.08 -- teia irregular, de verdade
	end
	for i = 1, RAIOS do
		local ponta = centro + Vector3.new(math.cos(angulos[i]), 0, math.sin(angulos[i])) * radius
		fio(centro, ponta, 0.16, 0.15)
	end
	for anel = 1, ANEIS do
		for i = 1, RAIOS do
			local j = i % RAIOS + 1
			-- raio cresce um pouco de fio em fio (espiral), e o fio "cede" pro centro
			local r1 = radius * (anel - 0.35 + i / RAIOS * 0.35) / ANEIS
			local r2 = radius * (anel - 0.35 + (i % RAIOS == 0 and 0.35 or j / RAIOS * 0.35)) / ANEIS
			local a = centro + Vector3.new(math.cos(angulos[i]), 0, math.sin(angulos[i])) * r1
			local b = centro + Vector3.new(math.cos(angulos[j]), 0, math.sin(angulos[j])) * r2
			fio(a, b, 0.1, 0.3)
		end
	end
	-- véu verde bem fraco embaixo, pra marcar a área
	local veu = Instance.new("Part")
	veu.Name = "Veu"
	veu.Shape = Enum.PartType.Cylinder
	veu.Anchored = true
	veu.CanCollide = false
	veu.CanTouch = false
	veu.CanQuery = false
	veu.CastShadow = false
	veu.Material = Enum.Material.ForceField
	veu.Color = Color3.fromRGB(150, 220, 120)
	veu.Transparency = 0.2
	veu.Size = Vector3.new(0.1, radius * 2, radius * 2)
	veu.CFrame = CFrame.new(centro) * CFrame.Angles(0, 0, math.rad(90))
	veu.Parent = part
	part.Parent = workspace
	-- some aos poucos no último segundo
	task.delay(math.max(duration - 1, 0), function()
		if not part.Parent then return end
		for _, p in ipairs(part:GetChildren()) do
			if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.9), { Transparency = 1 }):Play() end
		end
	end)

	table.insert(SlowZones, {
		Position = root.Position,
		Radius = radius,
		Mult = math.clamp(mult or 0.5, 0.1, 1),
		ExpiresAt = tick() + duration,
		Team = player.Team,
		Part = part,
	})
end

RunService.Heartbeat:Connect(function()
	local now = tick()
	for index = #SlowZones, 1, -1 do
		local zone = SlowZones[index]
		if now >= zone.ExpiresAt then
			if zone.Part then zone.Part:Destroy() end
			table.remove(SlowZones, index)
			continue
		end
		for _, other in ipairs(Players:GetPlayers()) do
			-- Zona só pega ADVERSÁRIO — quem montou a teia não pode ficar
			-- preso na própria teia.
			if zone.Team and other.Team and zone.Team == other.Team then continue end
			local root = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
			if not root then continue end
			local flat = Vector3.new(root.Position.X - zone.Position.X, 0, root.Position.Z - zone.Position.Z)
			if flat.Magnitude <= zone.Radius then
				-- Renovado com validade curta: sai da zona, volta ao normal
				-- em 0.25s sozinho, sem precisar de evento de "saída".
				SlowedUntil[other] = { Mult = zone.Mult, ExpiresAt = now + 0.25 }
			end
		end
	end
end)

local function getZoneSlowMultiplier(player)
	local slow = SlowedUntil[player]
	if not slow then return 1 end
	if tick() >= slow.ExpiresAt then
		SlowedUntil[player] = nil
		return 1
	end
	return slow.Mult
end

-- ===== DESARME À DISTÂNCIA (Costura de Sombra) =====
-- Fiel ao anime: a sombra vira uma mão, agarra as pernas e PRENDE — não
-- rouba a bola. Quem usa ainda precisa ir buscar. É o único desarme do
-- jogo que funciona sem contato.
local function executeRoot(player, effect, slot, def)
	-- ⚠️ v110 — PEDIDO: "não sei o que a Costura de Sombra faz, testei e não deu
	-- nada — precisa de um oponente? ela paralisa no lugar?" Precisava: só saía
	-- com um adversário COM A BOLA a até 46 studs (senão, nada acontecia). Agora,
	-- como os carrinhos: a SOMBRA corre reta pelo chão na direção da mira (até o
	-- alcance) e o PRIMEIRO adversário que ela alcançar fica PRESO no lugar
	-- (não rouba a bola — quem usou ainda precisa ir buscar). Wiki (Kage Nui): "a
	-- sombra se estica pelo campo, vira uma mão e agarra as pernas".
	do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then return false end
		local direcao
		local mira = LastAimPoint[player]
		if typeof(mira) == "Vector3" and mira.X == mira.X then
			local plano = Vector3.new(mira.X - root.Position.X, 0, mira.Z - root.Position.Z)
			if plano.Magnitude > 1 then direcao = plano.Unit end
		end
		if not direcao then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			direcao = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
		end
		local alcance = effect.RootRadius or 46
		local _ = effect.RootDuration -- (v110: tempo preso = 1.5s + QTE, até 2s — ver o agarrão abaixo)
		-- ⚠️ v113 — PEDIDO: "Costura de Sombra: sombra 3x maior" (largura 4.5 -> 13.5)
		local VEL, LARGURA, ATRASO = 85, 13.5, 0.45 -- (ATRASO = mãos juntas e braços pra trás na animação)
		local origem = root.Position
		-- ⚠️ v110 — PEDIDO: "enquanto eu estiver usando essa habilidade eu NÃO
		-- posso me mover, porque eu tô criando a sombra... é pra travar o avanço
		-- de alguém". Quem usa fica plantado enquanto a sombra corre.
		freezeMovement(player, ATRASO + alcance / VEL + 0.05)
		if Remotes.HissatsuVFX and player.Character then
			Config.DispararVFX("HissatsuVFX", player.Character, "Costura de Sombra", nil,
				{ Dir = direcao, Alcance = alcance, Vel = VEL, Atraso = ATRASO })
		end
		task.delay(ATRASO, function()
			local t0 = tick()
			local percorrido = 0
			local con
			con = RunService.Heartbeat:Connect(function()
				local antes = percorrido
				percorrido = math.min(alcance, (tick() - t0) * VEL)
				local a = origem + direcao * antes
				local b = origem + direcao * percorrido
				for _, other in ipairs(Players:GetPlayers()) do
					if other == player or (player.Team and other.Team == player.Team) then continue end
					if _G.HasPulseIframe and _G.HasPulseIframe(other) then continue end
					local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
					if not r then continue end
					-- distância (no chão) do adversário até o trecho que a sombra andou neste quadro
					local p = Vector3.new(r.Position.X, origem.Y, r.Position.Z)
					local ab = b - a
					local u = ab.Magnitude > 0.001 and math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1) or 0
					if (p - (a + ab * u)).Magnitude <= LARGURA then
						con:Disconnect()
						-- ⚠️ v110 — PEDIDO: "se ela acertar alguém, segura por 1.5
						-- segundos — 2 no máximo" + "pode rolar um quick time event:
						-- quanto mais você acertar, mais tempo dura". Os DOIS ficam
						-- presos (ele pela sombra, você segurando ela) 1.5s; alternar
						-- A/D durante o agarrão estica até 2s.
						local inicio = tick()
						local fim = inicio + 1.5
						local function segurar()
							local resta = fim - tick()
							if resta <= 0 then return end
							if _G.StunPlayer then _G.StunPlayer(other, resta) end
							freezeMovement(player, resta)
						end
						segurar()
						if Remotes.HissatsuVFX and player.Character then
							Config.DispararVFX("HissatsuVFX", player.Character, "Costura de Sombra@agarra", nil,
								{ Alvo = other.Character, Duracao = fim - tick() })
						end
						if slot and _G.StartHissatsuQTE and _G.RegisterQTEHitCallback then
							local qdef = { Name = (def and def.Name) or "Costura de Sombra", Rarity = def and def.Rarity,
								Action = "Root", QTE = { Kind = "MashAD", Duration = 1.3, RequiredAlternations = 10 } }
							_G.StartHissatsuQTE(player, slot, qdef, function() end)
							_G.RegisterQTEHitCallback(player, slot, function(hits)
								local novoFim = inicio + math.min(2.0, 1.5 + (hits or 0) * 0.05)
								if novoFim > fim + 0.01 then
									fim = novoFim
									segurar()
									if Remotes.HissatsuVFX and player.Character then
										Config.DispararVFX("HissatsuVFX", player.Character, "Costura de Sombra@segura", nil,
											{ Alvo = other.Character, Duracao = fim - tick() })
									end
								end
							end)
						end
						return
					end
				end
				if percorrido >= alcance then con:Disconnect() end
			end)
		end)
		return true
	end
	local target = _G.GetBallOwner and _G.GetBallOwner()
	if not target or target == player then return false end
	if player.Team and target.Team and player.Team == target.Team then return false end
	-- Mesma regra do carrinho: alvo com iframe de Pulso não pode ser
	-- pego (ver resolveStealAttempt no BallController).
	if _G.HasPulseIframe and _G.HasPulseIframe(target) then return false end

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not root or not targetRoot then return false end
	if (targetRoot.Position - root.Position).Magnitude > (effect.RootRadius or 18) then return false end

	if _G.FreezePlayer then
		_G.FreezePlayer(target, effect.RootDuration or 1.3)
	end
	return true
end

-- ===== ESCALA POR COMPANHEIROS (Zona Morta / Muralha Infinita) =====
-- A hissatsu de jogar com os amigos: a potência sai de quantos
-- companheiros estão por perto NA HORA, não de um número fixo na
-- definição. Quem entra na conta também ganha carga de Instinto — o
-- companheiro é recompensado por ter estado no lugar certo.
local ALLIES_SCALED_KEYS = {
	"ForceMult", "HeaderForceMult", "CurveMult",
	"BlockRadius", "BlockImpulse", "DiveRadiusAdd",
}

local function applyAlliesScale(player, def, effect)
	local spec = def.AlliesScale
	if typeof(spec) ~= "table" then return effect end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then return effect end

	local radius = spec.Radius or 22
	local count = 0
	for _, mate in ipairs(Players:GetPlayers()) do
		if mate == player then continue end
		if not (player.Team and mate.Team and player.Team == mate.Team) then continue end
		local mateRoot = mate.Character and mate.Character:FindFirstChild("HumanoidRootPart")
		if not mateRoot then continue end
		if (mateRoot.Position - root.Position).Magnitude > radius then continue end
		count += 1
		if _G.AddInstinctCharge then _G.AddInstinctCharge(mate, 0.1) end
	end

	count = math.min(count, spec.Max or 2)
	if count <= 0 then return effect end

	local scale = 1 + (spec.PerAlly or 0.45) * count
	local scaled = table.clone(effect)
	for _, key in ipairs(ALLIES_SCALED_KEYS) do
		if scaled[key] then scaled[key] = scaled[key] * scale end
	end
	return scaled
end

-- ⚠️ v9 PEDIDO: "energia de ativação da Hissatsu... precisa ser algo
-- relacionado com o atributo Energy". "Combustível" que QUALQUER Pulso
-- Hissatsu (chute/defesa/arrancada/drible) consome pra ativar; o TAMANHO
-- do pool escala com o atributo Energy. ⚠️ NOVO: é o ÚNICO efeito do
-- atributo Energy — ele não deixa mais nenhuma Hissatsu mais forte
-- (PEDIDO: "Energia é um RECURSO... Energia máxima 100, Hissatsu custa 30,
-- após usar 70"). Só reenche no kickoff (ver _G.ResetPulseEnergy).
local EnergyPool = {} -- [player] = valor atual do pool

local function maxEnergyPool(player)
	local value = player:GetAttribute(Config.ENERGY_ATTRIBUTE)
	if typeof(value) ~= "number" then value = Config.DEFAULT_ENERGY end
	local fraction = math.clamp(value, 0, 100) / 100
	return Config.PULSE_ENERGY_POOL_MIN + (Config.PULSE_ENERGY_POOL_MAX - Config.PULSE_ENERGY_POOL_MIN) * fraction
end

local function ensureEnergy(player)
	if EnergyPool[player] == nil then
		EnergyPool[player] = maxEnergyPool(player)
	end
end

_G.GetPulseEnergy = function(player)
	ensureEnergy(player)
	return EnergyPool[player], maxEnergyPool(player)
end

-- ⚠️ NOVO: PEDIDO — "a energia só recarrega no segundo tempo, ela está
-- recarregando passivamente, e isso não pode acontecer". Removido o
-- ticker de regeneração por tempo que existia aqui (somava energia todo
-- Heartbeat, mesmo com o jogador parado) — o pool NUNCA mais enche
-- sozinho durante o jogo. A única forma de reabastecer agora é
-- _G.ResetPulseEnergy, chamado por performKickoff em MatchController.lua
-- no início do 1º E do 2º tempo (kickoff), enchendo todo mundo pro máximo
-- de uma vez só — um ponto de recarga bem definido, não um "vazamento"
-- ambiente e contínuo.
local lastSentEnergy = {} -- [player] = último valor (arredondado) mandado pro cliente

local function sendEnergyFeedback(player)
	ensureEnergy(player)
	local maxPool = maxEnergyPool(player)
	local rounded = math.floor(EnergyPool[player] + 0.5)
	if lastSentEnergy[player] ~= rounded then
		lastSentEnergy[player] = rounded
		Remotes.PulseEnergyFeedback:FireClient(player, rounded, math.floor(maxPool))
	end
end

_G.ResetPulseEnergy = function()
	for _, player in ipairs(Players:GetPlayers()) do
		EnergyPool[player] = maxEnergyPool(player)
		sendEnergyFeedback(player)
	end
end

-- Concede, pelos próximos "duration" segundos, um multiplicador de força
-- no PRÓXIMO chute de "player" (Pulso do Camisa 10 aplicando no
-- companheiro que recebeu o passe) — consumido no primeiro chute depois
-- disso, ver _G.GetPulseActiveKickForceMult.
-- ⚠️ v110: buff de VELOCIDADE nos companheiros a até `raio` de quem usa (Armas
-- Maestro do Campo / Voz de Comando). Usa a mesma tabela do Pulso do General
-- (TeamBuff), que o GetPulseSpeedMultiplier já lê — sem mexer no PlayerSystems.
_G.PulseTeamBuff = function(player, raio, speedMult, duracao)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not player.Team then return end
	local ate = tick() + duracao
	for _, mate in ipairs(Players:GetPlayers()) do
		if mate ~= player and mate.Team == player.Team then
			local r = mate.Character and mate.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - root.Position).Magnitude <= raio then
				local atual = TeamBuff[mate]
				local valendo = atual and atual.ExpiresAt > tick()
				TeamBuff[mate] = {
					SpeedMult = math.max(speedMult, valendo and (atual.SpeedMult or 1) or 1),
					ForceMult = valendo and (atual.ForceMult or 1) or 1,
					ExpiresAt = math.max(ate, valendo and atual.ExpiresAt or 0),
				}
			end
		end
	end
end

_G.SetPulseTeammateBuff = function(player, forceMult, duration)
	TeammateBuff[player] = { ForceMult = forceMult, ExpiresAt = tick() + duration }
end

local function feedback(player, kind, extra)
	Remotes.PulseFeedback:FireClient(player, kind, extra)
end

-- ===== ⚠️ v108 — ZONA MORTA DE TRÊS (def.Trio, ver PulseInstinctData) =====
-- Tabela única (um local só) com: os companheiros que entram, o estado ativo
-- de quem chutou e a conta final aplicada no resolveAndExecute.
local Trio = { Ativo = {} } -- Ativo[player] = estado do QTE de quem chutou

-- os `quantos` companheiros vivos do time mais perto, até `raio` studs
function Trio.Proximos(player, raio, quantos)
	return Trio.Companheiros(player, { Trio = { Raio = raio, Companheiros = quantos } })
end

function Trio.Companheiros(player, def)
	local spec = def.Trio
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not spec or not root or not player.Team then return {} end
	local lista = {}
	for _, mate in ipairs(Players:GetPlayers()) do
		if mate ~= player and mate.Team == player.Team then
			local r = mate.Character and mate.Character:FindFirstChild("HumanoidRootPart")
			local hum = mate.Character and mate.Character:FindFirstChildOfClass("Humanoid")
			if r and hum and hum.Health > 0 then
				local d = (r.Position - root.Position).Magnitude
				if d <= (spec.Raio or 55) then table.insert(lista, { Mate = mate, D = d }) end
			end
		end
	end
	table.sort(lista, function(a, b) return a.D < b.D end)
	local out = {}
	for i = 1, math.min(#lista, spec.Companheiros or 2) do out[i] = lista[i].Mate end
	return out
end

-- ⚠️ v110 — PEDIDO: "o Death Zone saiu muito fraco mesmo a gente acertando (não
-- acertamos tudo). A força vai SOMANDO a partir do que a gente acerta; se todo
-- mundo acertar tudo, no máximo vai ser um POUCO mais forte que uma Hissatsu
-- solo (ou dupla, porque é trio)." Antes era tudo-ou-nada: um clique a menos de
-- qualquer um = chute a 30%. Agora conta a SINCRONIA = média dos cliques certos
-- de todo mundo (quem chuta + apoios; apoio que faltou conta 0). A força vai de
-- ForcaMin (ninguém acertou nada) até ForcaMax (todos acertaram tudo) —
-- ForcaMax só um pouco acima de 1 (dupla 1.06, trio 1.12). Sincronia baixa
-- também entorta a mira.
function Trio.Efeito(state, effect)
	local spec = state.Def.Trio
	local apoios = state.Trio and state.Trio.Apoios or {}
	local sozinhoDebug = DebugFlags[state.Jogador] and DebugFlags[state.Jogador].TrioSozinho
	local precisa = spec.Companheiros or 2
	local function fracao(hits, req)
		req = math.max(req or 1, 1)
		return math.clamp((hits or 0) / req, 0, 1)
	end
	local fChute = fracao(state.Hits, state.BaseHits or state.RequiredHits)
	local soma, n = fChute, 1
	for _, r in ipairs(apoios) do
		soma += fracao(r.Hits, r.Req)
		n += 1
	end
	for _ = #apoios + 1, precisa do -- apoio que faltou (no debug "sozinho", conta igual a quem chuta)
		soma += sozinhoDebug and fChute or 0
		n += 1
	end
	local sincronia = soma / n
	local minimo = spec.ForcaMin or 0.5
	local maximo = spec.ForcaMax or (precisa >= 2 and 1.12 or 1.06)
	local ef = table.clone(effect or {})
	ef.ForceMult = (ef.ForceMult or 1) * (minimo + (maximo - minimo) * sincronia)
	if sincronia < 0.5 then
		ef.AimDeviationMult = (ef.AimDeviationMult or 1) * (1 + (0.5 - sincronia) * 4)
	end
	local todos = { state.Jogador }
	for _, r in ipairs(apoios) do table.insert(todos, r.Mate) end
	-- ⚠️ v110: com acento em maiúscula também ("FÚRIA", não "FúRIA")
	local titulo = (string.upper(state.Def.Name or ""):gsub("\195([\160-\190])", function(c)
		if string.byte(c) ~= 183 then return "\195" .. string.char(string.byte(c) - 32) end
	end))
	for _, p in ipairs(todos) do
		if p and p.Parent then
			feedback(p, "Aviso", ("%s — sincronia %d%%"):format(titulo, math.floor(sincronia * 100 + 0.5)))
			if p ~= state.Jogador and _G.AddInstinctCharge then _G.AddInstinctCharge(p, 0.1 * sincronia) end
		end
	end
	return ef
end

local function startCooldown(player, slot, def)
	-- OncePerMatch não existe mais (ver cabeçalho, item 3): todo Pulso
	-- tem Cooldown, inclusive os Míticos.
	if def.Cooldown then
		ReadyAt[player][slot] = tick() + def.Cooldown
	end
end

local function roleOk(player, def)
	if not def.RoleRequired then return true end
	if def.RoleRequired == "GK" then
		-- Pulso exclusivo de goleiro só funciona com o goleiro DENTRO da
		-- própria área (ver GKAreaUtil.lua) — fora dela ele já não tem
		-- mais acesso ao slot único de GK (ver bloqueio de slot 2 abaixo
		-- e a troca de tecla em PulseInput.local.luau), então isso é só
		-- defesa em profundidade caso o cliente seja adulterado.
		return GKAreaUtil.IsEffectiveGK(player)
	end
	return player:GetAttribute("Role") == def.RoleRequired
end

-- ===== ⚠️ v3: DURAÇÃO DO WIND-UP E IFRAME AUTOMÁTICO =====
-- Duração total do combo (0 pros Pulsos instantâneos), já truncada pelo
-- teto duro do jogo — se alguém cadastrar um Combo absurdo em
-- PulseInstinctData, o StepTime é encolhido em vez de deixar o jogador
-- parado mais que Config.PULSE_MAX_WINDUP segundos.
local function comboTiming(def)
	local combo = def.Combo
	if not combo or typeof(combo.Keys) ~= "table" or #combo.Keys == 0 then return 0, 0, 0 end

	local delay = math.max(combo.Delay or 0, 0)
	-- ⚠️ v3.2: facilita o QTE — cada passo fica Config.PULSE_COMBO_STEP_TIME_MULT
	-- vezes mais largo (ver comentário na Config).
	local stepTime = math.max((combo.StepTime or 0.3) * (Config.PULSE_COMBO_STEP_TIME_MULT or 1), 0.05)
	local steps = #combo.Keys
	local total = delay + stepTime * steps

	if total > Config.PULSE_MAX_WINDUP then
		local available = math.max(Config.PULSE_MAX_WINDUP - delay, 0.05 * steps)
		stepTime = available / steps
		total = delay + stepTime * steps
	end

	return delay, stepTime, total
end

-- Regra GENÉRICA (pedido do usuário): wind-up longo = iframe o wind-up
-- inteiro. Vale pra qualquer Pulso, presente ou futuro, sem precisar
-- marcar nada na definição dele — só a duração decide (ou o campo
-- opcional Iframe = true, pra forçar num wind-up curto).
local function grantWindupIframe(player, def, totalWindup)
	if totalWindup <= 0 and not def.Iframe then return end
	if not (def.Iframe or totalWindup > Config.PULSE_IFRAME_MIN_WINDUP) then return end
	if _G.GrantPulseIframe then
		-- Num Pulso instantâneo com Iframe = true o wind-up é 0 e não há
		-- nada pra proteger (a ação já resolveu) — sobra só um piscar
		-- mínimo. Pra proteção de verdade depois da ação, a chave certa é
		-- SelfIframe (em segundos), não Iframe.
		_G.GrantPulseIframe(player, math.max(totalWindup, 0.1))
	end
end

-- ===== PRECONDIÇÃO DA AÇÃO (checada ANTES de gastar cooldown) =====
local function actionPrecheck(player, def)
	local action = def.Action
	if action == "Shot" or action == "Pass" or action == "DribbleMove" then
		if not (_G.PulseHasControl and _G.PulseHasControl(player)) then
			return false, "Sem posse de bola"
		end
	elseif action == "Tackle" then
		if _G.PulseHasControl and _G.PulseHasControl(player) then
			return false, "Você está com a posse de bola"
		end
		-- ⚠️ NOVO: a Arrancada/Investida (QTE MashAD) virou um dash livre —
		-- pedido explícito: "posso usar em qualquer lugar do campo, até
		-- mesmo se o player não estiver com a bola, contanto que a hitbox
		-- dele acerte a do player". Só os desarmes CRONOMETRADOS (TimingBar,
		-- ex: Desarme de Aço) continuam exigindo um adversário com a bola
		-- por perto — eles reforçam um carrinho de verdade que já ia
		-- acontecer, não um dash independente.
		local isFreeDash = def.QTE and def.QTE.Kind == "MashAD"
		-- ⚠️ v43: o alcance extra da habilidade (TackleRangeAdd) precisa valer
		-- JÁ AQUI, senão a Rasteira seria recusada ("nenhum adversário por
		-- perto") a uma distância que ela deveria alcançar — o bônus na
		-- execução sozinho nunca chegaria a rodar.
		local bonusAlcance = (def.Effect and def.Effect.TackleRangeAdd)
			or (def.Perfect and def.Perfect.TackleRangeAdd)
			or (def.Bom and def.Bom.TackleRangeAdd)
		-- ⚠️ v110: TODO carrinho de Hissatsu virou dash livre na mira ("pode usar
		-- em qualquer lugar") — só o desarme cronometrado ainda pede alvo
		isFreeDash = isFreeDash or not (def.QTE and def.QTE.Kind == "TimingBar")
		if not isFreeDash and not (_G.PulseHasOpponentInTackleRange and _G.PulseHasOpponentInTackleRange(player, bonusAlcance)) then
			return false, "Nenhum adversário com a bola por perto"
		end
	elseif action == "Root" then
		-- ⚠️ v11 (Costura de Sombra): precisa existir um adversário COM a
		-- bola — o alcance de verdade é checado em executeRoot, aqui só
		-- evita gastar cooldown/energia quando não há ninguém pra prender.
		if _G.PulseHasControl and _G.PulseHasControl(player) then
			return false, "Você está com a posse de bola"
		end
		-- ⚠️ v110: a sombra agora corre RETA na mira e prende quem ela alcançar —
		-- não precisa mais de alguém com a bola pra usar
	elseif action == "Header" then
		if not (_G.PulseCanHeader and _G.PulseCanHeader(player)) then
			return false, "Bola não está no ar por perto"
		end
	elseif action == "AerialControl" then
		-- ⚠️ NOVO (Pulso do Domínio Aéreo): mesma checagem "bola no ar por
		-- perto" da cabeçada — reusa _G.PulseCanHeader em vez de duplicar.
		if not (_G.PulseCanHeader and _G.PulseCanHeader(player)) then
			return false, "Bola não está no ar por perto"
		end
		if _G.GetBallOwner and _G.GetBallOwner() then
			return false, "A bola já está com alguém"
		end
	elseif action == "SetPieceKick" then
		if not (_G.IsDeadBallMode and _G.IsDeadBallMode()) then
			return false, "Só em bola parada"
		end
		if not (_G.PulseHasControl and _G.PulseHasControl(player)) then
			return false, "Você não é o cobrador"
		end
	end
	-- "Steal" e "Buff" não exigem precondição além de role/cooldown (já
	-- checados antes de chegar aqui).
	return true
end

-- ===== AÇÕES SEM DEPENDÊNCIA DE BallController (self-contidas aqui) =====
local function executeBuff(player, slot, def, effect)
	if def.Duration and def.Duration > 0 then
		ActiveBuff[player][slot] = { Effect = effect, ExpiresAt = tick() + def.Duration, Rarity = def.Rarity }
		-- ⚠️ v7 PEDIDO: "ele não vai poder se mexer nem na Hissatsu do
		-- goleiro, nem na do defensor" — Grande Muralha (FreezeSelf=true no
		-- PulseInstinctData.luau) trava o movimento pelo mesmo Duration do
		-- buff. As Hissatsus de goleiro (Mão Divina/Guardião Absoluto) NÃO
		-- passam mais por aqui — ver startGKGuard, que já congela na hora.
		if def.FreezeSelf then
			freezeMovement(player, def.Duration)
		end
	end
	return true
end

local function executeSteal(player, effect)
	local target = _G.GetBallOwner and _G.GetBallOwner()
	if not target or target == player then return false end
	if player.Team and target.Team and player.Team == target.Team then return false end
	-- ⚠️ v3: alvo com iframe de Pulso (wind-up longo/SelfIframe) não pode
	-- ser roubado — mesma regra do carrinho (ver resolveStealAttempt no
	-- BallController).
	if _G.HasPulseIframe and _G.HasPulseIframe(target) then return false end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local targetCharacter = target.Character
	local targetHrp = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp or not targetHrp then return false end
	if (hrp.Position - targetHrp.Position).Magnitude > (effect.StealRadius or 7) then return false end
	if math.random() > (effect.StealChance or 1) then return false end

	if _G.SetBallOwnerForced then _G.SetBallOwnerForced(player) end
	-- StunDuration aqui é o stun da VÍTIMA do roubo (num Pulso com
	-- StunRadius, a mesma chave vira a duração do stun em ÁREA — ver
	-- applyExtraEffectKeys; nenhum Pulso usa as duas coisas junto).
	if _G.StunPlayer then _G.StunPlayer(target, effect.StunDuration or 0.5) end
	if _G.RegisterTackle then _G.RegisterTackle(player, target) end
	return true
end

-- ===== ⚠️ v3: CHAVES DE EFEITO "TRANSVERSAIS" =====
-- Aplicadas DEPOIS da ação principal ter dado certo, pra qualquer
-- def.Action — um chute pode stunar quem está em volta, um carrinho pode
-- empurrar, um passe pode travar a bola pro companheiro, etc. As que
-- dependem de física/posição vão pro BallController (_G.*); as que são
-- puramente de estado do Pulso ficam aqui.
-- ⚠️ v113 — cegueira: tela branca nos ADVERSÁRIOS no raio (Clarão de Fótons,
-- Investida de Luz). Remoto direto (não vai pro replay: não pode cegar quem
-- está assistindo o replay).
_G.PulseAplicarCegueira = function(player, centro, raio, duracao)
	if typeof(centro) ~= "Vector3" or not raio or not duracao then return end
	local vitimas = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other == player or (player.Team and other.Team and player.Team == other.Team) then continue end
		local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if r and Vector3.new(r.Position.X - centro.X, 0, r.Position.Z - centro.Z).Magnitude <= raio then
			table.insert(vitimas, other.UserId)
		end
	end
	if #vitimas > 0 and Remotes.HissatsuVFX and player.Character then
		Remotes.HissatsuVFX:FireAllClients(player.Character, "Clarão de Fótons@cegar", nil, { Vitimas = vitimas, Duracao = duracao })
	end
end

-- ⚠️ v113: variante da Investida pelo elemento do JOGADOR (ver PulseInstinctData)
local VARIANTES_INVESTIDA = {
	Fogo = { KnockbackRadius = 9, KnockbackForce = 50 },
	Vento = { KnockbackRadius = 13, KnockbackForce = 80 },
	Void = { StunGarantido = { Raio = 10, Duracao = 1.0, Atraso = 0.45 } },
	Natureza = { ZoneSlowRadius = 12, ZoneSlowDuration = 3, ZoneSlowMult = 0.6 },
	Luz = { Cegueira = { Raio = 13, Duracao = 1.4, Atraso = 0.45 } },
}

local function applyExtraEffectKeys(player, slot, def, effect)
	if effect.VarianteElemental then
		local el = player:GetAttribute(Config.ELEMENT_ATTRIBUTE_NAME)
		local v = VARIANTES_INVESTIDA[el] or VARIANTES_INVESTIDA.Fogo
		local copia = table.clone(effect)
		copia.VarianteElemental = nil
		for k, val in pairs(v) do copia[k] = val end
		effect = copia
	end

	-- ⚠️ v113: ATORDOAMENTO GARANTIDO (Faísca Zigue-Zague, Investida Sombria):
	-- sai quando o golpe CHEGA (Atraso), no raio inteiro, ignora a resistência
	-- (Defesa Zumbi) e pega também o goleiro bot.
	if effect.StunGarantido then
		local sg = effect.StunGarantido
		task.delay(sg.Atraso or 0, function()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if not root then return end
			for _, other in ipairs(Players:GetPlayers()) do
				if other == player or (player.Team and other.Team and player.Team == other.Team) then continue end
				local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if r and (r.Position - root.Position).Magnitude <= sg.Raio and _G.StunPlayer then
					local mult = _G.GetInstinctStunMult and _G.GetInstinctStunMult(other) or 1
					_G.StunPlayer(other, sg.Duracao / math.max(mult, 0.05))
				end
			end
			if _G.GetGKBotPositions and _G.FreezeGKBot then
				for _, bot in ipairs(_G.GetGKBotPositions()) do
					if (not player.Team or bot.TeamName ~= player.Team.Name) and (bot.Position - root.Position).Magnitude <= sg.Raio then
						_G.FreezeGKBot(bot.TeamName, sg.Duracao)
					end
				end
			end
		end)
	end

	-- ⚠️ v113: cegueira em volta de quem usou (Investida de Luz)
	if effect.Cegueira then
		local cg = effect.Cegueira
		task.delay(cg.Atraso or 0, function()
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then _G.PulseAplicarCegueira(player, root.Position, cg.Raio, cg.Duracao) end
		end)
	end

	-- ⚠️ v113: BOLA ILUSÃO — 2 cópias em 2 das 3 direções (frente, diagonais),
	-- sorteadas; quem usou é a terceira figura e anda livre (ver HissatsuVFX).
	if effect.Ilusao then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			look = look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)
			local angulos = { 0, 40, -40 }
			table.remove(angulos, math.random(1, 3)) -- a direção que sobra é a "sua"
			local dirs = {}
			for i, a in ipairs(angulos) do dirs[i] = CFrame.Angles(0, math.rad(a), 0):VectorToWorldSpace(look) end
			if Remotes.HissatsuVFX then
				Config.DispararVFX("HissatsuVFX", player.Character, "Bola Ilusão@clones", def.Element,
					{ Dirs = dirs, Duracao = effect.Ilusao.Duracao or 1.5, Distancia = effect.Ilusao.Distancia or 22 })
			end
		end
	end

	-- ⚠️ v113: PISÃO DE SUMÔ NA MIRA (até Alcance studs): o pé desce onde você
	-- mirou e atordoa quem estiver ali.
	if effect.PisaoMira then
		local pm = effect.PisaoMira
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			local ponto
			local mira = LastAimPoint[player]
			if typeof(mira) == "Vector3" and mira.X == mira.X then
				local plano = Vector3.new(mira.X - root.Position.X, 0, mira.Z - root.Position.Z)
				if plano.Magnitude > (pm.Alcance or 60) then plano = plano.Unit * (pm.Alcance or 60) end
				ponto = root.Position + plano
			else
				local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
				ponto = root.Position + (look.Magnitude > 0.01 and look.Unit or Vector3.new(0, 0, -1)) * 12
			end
			local chaoY = root.Position.Y - 2.9
			do
				local filtro = RaycastParams.new()
				filtro.FilterType = Enum.RaycastFilterType.Exclude
				filtro.RespectCanCollide = true
				local ignorar = {}
				for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
				local bola = workspace:FindFirstChild(Config.BALL_NAME)
				if bola then table.insert(ignorar, bola) end
				filtro.FilterDescendantsInstances = ignorar
				local hit = workspace:Raycast(Vector3.new(ponto.X, root.Position.Y + 6, ponto.Z), Vector3.new(0, -30, 0), filtro)
				if hit then chaoY = hit.Position.Y end
			end
			ponto = Vector3.new(ponto.X, chaoY, ponto.Z)
			freezeMovement(player, 0.5)
			if Remotes.HissatsuVFX and player.Character then
				Config.DispararVFX("HissatsuVFX", player.Character, "Pisão de Sumô@mira", def.Element, { Posicao = ponto, Atraso = 0.38, Raio = pm.Raio })
			end
			task.delay(0.38, function()
				for _, other in ipairs(Players:GetPlayers()) do
					if other == player or (player.Team and other.Team and player.Team == other.Team) then continue end
					local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
					if r and Vector3.new(r.Position.X - ponto.X, 0, r.Position.Z - ponto.Z).Magnitude <= pm.Raio and _G.StunPlayer then
						_G.StunPlayer(other, pm.Duracao)
						-- ⚠️ v120b — PEDIDO: "o pisão de sumô pode deixar atordoado com o efeito de tontura"
						if _G.MostrarTontura then _G.MostrarTontura(other, pm.Duracao) end
					end
				end
				if _G.GetGKBotPositions and _G.FreezeGKBot then
					for _, bot in ipairs(_G.GetGKBotPositions()) do
						if (not player.Team or bot.TeamName ~= player.Team.Name)
							and Vector3.new(bot.Position.X - ponto.X, 0, bot.Position.Z - ponto.Z).Magnitude <= pm.Raio then
							_G.FreezeGKBot(bot.TeamName, pm.Duracao)
						end
					end
				end
			end)
		end
	end

	-- Iframe próprio (ex: Pulso Fantasma, Explosão, Carrinho Blindado).
	if effect.SelfIframe and _G.GrantPulseIframe then
		_G.GrantPulseIframe(player, effect.SelfIframe)
	end

	-- Stun em área nos adversários (Chute Fatal). Só quando tem RAIO — sem
	-- raio, StunDuration é o stun de vítima do Steal (ver executeSteal).
	if effect.StunRadius and effect.StunDuration and _G.PulseApplyAreaStun then
		_G.PulseApplyAreaStun(player, effect.StunRadius, effect.StunDuration)
	end

	-- ⚠️ v36 NOVO: "o de gelo precisa congelar as pessoas ao redor" —
	-- mesma ideia do StunRadius acima, só que CONGELA (ver _G.FreezePlayer
	-- em BallController.lua) em vez de atordoar. Usado pelo Pulso Fúria
	-- Glacial (ver PulseInstinctData.lua).
	if effect.FreezeRadius and effect.FreezeDuration and _G.PulseApplyAreaFreeze then
		_G.PulseApplyAreaFreeze(player, effect.FreezeRadius, effect.FreezeDuration)
	end

	-- ⚠️ v11: CORREDOR — atinge quem está no caminho da BOLA, não em volta
	-- do chutador (ver applyCorridorEffect). Tornado de Fogo atordoa,
	-- Fúria Glacial congela: a diferença importa, porque atordoado ainda
	-- balança e congelado trava olhando.
	if effect.CorridorStun and _G.StunPlayer then
		applyCorridorEffect(player, effect.CorridorStun, function(victim, duration)
			_G.StunPlayer(victim, duration)
		end)
	end
	if effect.CorridorFreeze and _G.FreezePlayer then
		applyCorridorEffect(player, effect.CorridorFreeze, function(victim, duration)
			_G.FreezePlayer(victim, duration)
		end)
	end

	-- ⚠️ v11: PARADA DE TEMPO (Hora do Céu).
	if effect.TimeStopRadius and effect.TimeStopDuration then
		applyTimeStop(player, effect.TimeStopRadius, effect.TimeStopDuration)
	end

	-- ⚠️ v11: ZONA PERSISTENTE (Teia / Névoa).
	-- ⚠️ v67: pique do Vendaval (ver aplicarPique mais abaixo).
	if effect.SpeedBoostMult and effect.SpeedBoostDuration then
		aplicarPique(player, effect.SpeedBoostMult, effect.SpeedBoostDuration)
	end

	-- ⚠️ v67: Névoa (zona de INVISIBILIDADE, ver spawnFogZone lá em cima).
	if effect.FogRadius and effect.FogDuration then
		spawnFogZone(player, effect.FogRadius, effect.FogDuration)
	end

	if effect.ZoneSlowRadius and effect.ZoneSlowDuration then
		spawnSlowZone(player, effect.ZoneSlowRadius, effect.ZoneSlowDuration, effect.ZoneSlowMult)
	end

	-- ⚠️ v11: DEVOLVE ENERGIA (Vendaval). O pool só reenche no kickoff (ver
	-- _G.ResetPulseEnergy), então esse é o único jeito de ganhar
	-- combustível durante um tempo — e por isso é um Pulso inteiro, não um
	-- detalhe.
	if effect.EnergyRefund and effect.EnergyRefund > 0 then
		ensureEnergy(player)
		EnergyPool[player] = math.min(EnergyPool[player] + effect.EnergyRefund, maxEnergyPool(player))
		sendEnergyFeedback(player)
	end

	-- Empurrão em área nos adversários (Desarme Rasteiro, Carrinho Blindado).
	if effect.KnockbackRadius and effect.KnockbackForce and _G.PulseApplyAreaKnockback then
		_G.PulseApplyAreaKnockback(player, effect.KnockbackRadius, effect.KnockbackForce)
	end

	-- ⚠️ NOVO (Pulso da Arrancada Selvagem/Investida Titânica — "arrancada
	-- violenta que derruba os outros no chão"): RagdollRadius +
	-- RagdollDuration derruba de verdade (ragdoll, não só empurra) todo
	-- ADVERSÁRIO dentro do raio — normalmente usado JUNTO com
	-- KnockbackRadius/KnockbackForce acima (o empurrão dá o impulso, o
	-- ragdoll garante que ele cai mesmo, em vez do Humanoid se
	-- reequilibrar sozinho no meio do ar).
	if effect.RagdollRadius and effect.RagdollDuration and _G.RagdollPlayer then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			for _, other in ipairs(Players:GetPlayers()) do
				if other == player then continue end
				if player.Team and other.Team and player.Team == other.Team then continue end -- nunca em cima de companheiro
				local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
				if not otherRoot then continue end

				local acertou
				if effect.RagdollForward then
					-- ⚠️ v67 — FOICE DE VENTO: corte PRA FRENTE, não explosão em
					-- volta. PEDIDO: "não era pra empurrar os jogadores que estão
					-- na minha FRENTE? É muito perto? Não entendi." Era um raio de
					-- 9 studs em volta, curto demais pra dar pra perceber.
					-- Agora é um corredor na direção em que você está olhando:
					-- RagdollForward é o COMPRIMENTO e RagdollRadius a LARGURA.
					local frente = root.CFrame.LookVector
					frente = Vector3.new(frente.X, 0, frente.Z)
					if frente.Magnitude > 0.01 then
						frente = frente.Unit
						local delta = otherRoot.Position - root.Position
						local aoLongo = Vector3.new(delta.X, 0, delta.Z):Dot(frente)
						local lateral = (Vector3.new(delta.X, 0, delta.Z) - frente * aoLongo).Magnitude
						acertou = aoLongo >= 0 and aoLongo <= effect.RagdollForward and lateral <= effect.RagdollRadius
					end
				else
					acertou = (otherRoot.Position - root.Position).Magnitude <= effect.RagdollRadius
				end

				if acertou then
					_G.RagdollPlayer(other, effect.RagdollDuration)
				end
			end
		end
	end

	-- Carga no medidor de Instinct Mode (ver InstinctController).
	if effect.InstinctCharge and _G.AddInstinctCharge then
		_G.AddInstinctCharge(player, effect.InstinctCharge)
	end

	-- Devolve uma fração do cooldown RESTANTE do OUTRO slot (o goleiro só
	-- tem o slot 1, então pra ele isso simplesmente não acha nada).
	-- ⚠️ v76: com 3 slots agora, "o outro" só é inequívoco entre 1 e 2 —
	-- pensado pra quando só existiam esses dois. Usado a partir do slot 3
	-- (Robux), não reembolsa nada em vez de adivinhar qual dos outros
	-- dois — mantém o comportamento de balance original pra quem sempre
	-- teve só slot 1/2, sem inventar regra nova pro slot novo.
	if effect.CooldownRefundOther and effect.CooldownRefundOther > 0 and slot <= 2 then
		local otherSlot = (slot == 1) and 2 or 1
		local readyAt = ReadyAt[player] and ReadyAt[player][otherSlot]
		if readyAt then
			local remaining = readyAt - tick()
			if remaining > 0 then
				ReadyAt[player][otherSlot] = readyAt - remaining * math.clamp(effect.CooldownRefundOther, 0, 1)
			end
		end
	end

	-- Buff de ÁREA em cima do time (Pulso do General): todos os
	-- companheiros dentro do raio E o próprio jogador. Lido depois por
	-- _G.GetPulseSpeedMultiplier/_G.GetPulseActiveKickForceMult, sem
	-- precisar tocar em PlayerSystems.
	if effect.TeamBuffRadius and effect.TeamBuffDuration then
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local expiresAt = tick() + effect.TeamBuffDuration
			for _, mate in ipairs(Players:GetPlayers()) do
				if mate ~= player then
					-- Só companheiro de time de verdade (sem time definido dos
					-- dois lados, não dá pra afirmar que são do mesmo time).
					if not (player.Team and mate.Team and player.Team == mate.Team) then continue end
					local mateRoot = mate.Character and mate.Character:FindFirstChild("HumanoidRootPart")
					if not mateRoot then continue end
					if (mateRoot.Position - root.Position).Magnitude > effect.TeamBuffRadius then continue end
				end
				TeamBuff[mate] = {
					SpeedMult = effect.TeamSpeedMult or 1,
					ForceMult = effect.TeamForceMult or 1,
					ExpiresAt = expiresAt,
				}
			end
		end
	end
end

-- ===== v36: POTÊNCIA/TAMANHO DE EFEITO DE ÁREA ESCALANDO POR ATRIBUTO =====
-- PEDIDO: "faça o tamanho do pulso, e a sua potência (congelamento,
-- tamanho da skill de GK, atordoamento) ser maior dependendo de seu
-- respectivo status especial pra essa habilidade afetar, GK = Físico, FW
-- (chute) = Força de Chute, Drible = Drible". Cada CATEGORIA de Pulso lê
-- um atributo diferente do jogador (ver Config.PULSE_EFFECT_POWER_SCALE_*
-- em FootballConfig — mesma curva 0-100 -> MIN..MAX de sempre, 1.0x no
-- default 50); Tackle (desarme) usa Physical também, mesma lógica do GK,
-- só que na defesa.
--
-- ⚠️ NOVO — FÓRMULA POR HISSATSU. PEDIDO: "Cada Hissatsu poderá utilizar
-- atributos diferentes para determinar sua potência... 60% Chute + 40%
-- Técnica... 70% Físico + 30% Técnica". O atributo fixo por categoria
-- (antigo getPulsePowerScaleAttribute) virou só o PADRÃO de quem não
-- declara Scaling — ver Config.GetHissatsuScaling/GetHissatsuAttribute-
-- Rating em FootballConfig. A nota (média ponderada 0-100) entra na MESMA
-- curva de sempre, então uma Hissatsu 100% Físico continua idêntica.
local function getPulsePowerScale(player, def)
	local rating = Config.GetHissatsuAttributeRating(player, def)
	if not rating then return 1 end
	return Config.AttributeCurve(rating, Config.PULSE_EFFECT_POWER_SCALE_MIN, Config.PULSE_EFFECT_POWER_SCALE_MAX)
end

-- ⚠️ NOVO: multiplicador de FORÇA de chute da Hissatsu — a nota da fórmula
-- na curva de força do Chute (KICK_FORCE_MULTIPLIER_*: 1.0x na nota 50).
-- Entregue ao BallController em effect.AttributeForceMult (substitui o
-- antigo Kick x Energy de _G.PulseExecuteShot).
local function getPulseAttributeForceMult(player, def)
	local rating = Config.GetHissatsuAttributeRating(player, def)
	if not rating then return nil end
	return Config.AttributeCurve(rating, Config.KICK_FORCE_MULTIPLIER_MIN, Config.KICK_FORCE_MULTIPLIER_MAX)
end

-- Chaves de TAMANHO/POTÊNCIA de efeito de área — ForceMult/CurveMult/etc
-- já têm seu próprio caminho de escala (AttributeForceMult/raridade, ver
-- BallController.lua), então essas aqui são só as de área/duração.
local POWER_SCALED_EFFECT_KEYS = {
	"FreezeRadius", "FreezeDuration",
	"StunRadius", "StunDuration",
	"DiveRadiusAdd",
	"KnockbackRadius", "KnockbackForce",
	"RagdollRadius", "RagdollDuration", "RagdollForward", "SpeedBoostMult",
	"AnkleRangeAdd",
	"BlockRadius", "BlockImpulse",
	-- ⚠️ v11: as mecânicas novas escalam igual às antigas — alcance da
	-- Costura de Sombra e da Hora do Céu pelo atributo da categoria
	-- (Físico pro Root, Drible pro drible), e o raio da zona idem.
	"RootRadius", "RootDuration",
	"ZoneSlowRadius", "TimeStopRadius", "FogRadius",
}

-- NUNCA muta o "effect" recebido — é uma referência direta pro Bom/Perfect
-- de Data.Pulses (Lobby/ReplicatedStorage/PulseInstinctData.lua),
-- COMPARTILHADA entre todo mundo que usa esse Pulso — mexer nela na mão
-- vazaria o multiplicador de UM jogador pros próximos usos, de qualquer
-- jogador. Devolve uma cópia rasa só com as chaves de tamanho escaladas.
-- PEDIDO: "se o personagem tiver o elemento e usar skills do mesmo
-- elemento, ele tem vantagem de 10% de potência com esse elemento" — só
-- entra em jogo quando o Pulso tem def.Element preenchido (nenhum tem
-- ainda — ver comentário em PulseInstinctData.luau) E o jogador já tem um
-- elemento rolado (Config.ELEMENT_ATTRIBUTE_NAME, replicado do Lobby via
-- TeleportData). Sem os dois, devolve 1 (neutro) — zero efeito colateral
-- em Pulsos sem elemento.
local function getElementSelfMatchScale(player, def)
	if not def.Element then return 1 end
	local playerElement = player:GetAttribute(Config.ELEMENT_ATTRIBUTE_NAME)
	if playerElement == def.Element then
		return Config.PULSE_ELEMENT_SELF_MATCH_MULT
	end
	return 1
end

local function applyPulsePowerScale(player, def, effect)
	local scale = getPulsePowerScale(player, def) * getElementSelfMatchScale(player, def)
	-- ⚠️ NOVO: chute de Hissatsu leva junto a força da fórmula (ver
	-- getPulseAttributeForceMult) — só Action="Shot" lê isso.
	local forceMult = def.Action == "Shot" and getPulseAttributeForceMult(player, def) or nil
	if scale == 1 and not forceMult and def.Action ~= "Shot" then return effect end
	local scaled = table.clone(effect)
	if scale ~= 1 then
		for _, key in ipairs(POWER_SCALED_EFFECT_KEYS) do
			if scaled[key] then scaled[key] = scaled[key] * scale end
		end
	end
	scaled.AttributeForceMult = forceMult
	-- ⚠️ v107: o chute leva o elemento (o duelo de defesa compara com o da
	-- defesa) e o bônus de elemento próprio vale também na FORÇA do chute
	-- ("se você tiver o elemento no personagem, a Hissatsu fica mais forte").
	if def.Action == "Shot" then
		scaled.Elemento = def.Element
		scaled.ElementoProprioMult = getElementSelfMatchScale(player, def)
	end
	return scaled
end

-- ===== DISPATCHER: chama o executor certo pra def.Action e manda o feedback =====
local function resolveAndExecute(player, slot, def, effect)
	effect = effect or def.Effect or {}
	-- ⚠️ v108: Zona Morta de três — a conta final (acertou/falhou/perfeitos)
	local trioState = Trio.Ativo[player]
	if trioState and trioState.Def == def then
		Trio.Ativo[player] = nil
		effect = Trio.Efeito(trioState, effect)
	end
	effect = applyPulsePowerScale(player, def, effect) -- ⚠️ v36 (ver comentário acima)
	effect = applyAlliesScale(player, def, effect)     -- ⚠️ v11 (Zona Morta / Muralha Infinita)
	local action = def.Action
	local ok = false

	if action == "Shot" then
		-- ⚠️ v8: manda def.Rarity junto — BallController usa pra puxar o
		-- MaxRange e o multiplicador de poder por raridade (ver
		-- PULSE_RARITY_POWER_MULT/PULSE_RARITY_MAX_RANGE em FootballConfig).
		ok = _G.PulseExecuteShot and _G.PulseExecuteShot(player, effect, def.Rarity) or false
	elseif action == "Pass" then
		ok = _G.PulseExecutePass and _G.PulseExecutePass(player, effect) or false
	elseif action == "Tackle" then
		ok = _G.PulseExecuteTackle and _G.PulseExecuteTackle(player, effect, def) or false -- ⚠️ v110: def = carrinho livre na mira
	elseif action == "Header" then
		ok = _G.PulseExecuteHeader and _G.PulseExecuteHeader(player, effect) or false
	elseif action == "AerialControl" then
		ok = _G.PulseExecuteAerialControl and _G.PulseExecuteAerialControl(player, effect) or false
	elseif action == "DribbleMove" then
		ok = _G.PulseExecuteDribbleMove and _G.PulseExecuteDribbleMove(player, effect) or false
	elseif action == "SetPieceKick" then
		ok = _G.PulseExecuteSetPieceKick and _G.PulseExecuteSetPieceKick(player, effect) or false
	elseif action == "Steal" then
		ok = executeSteal(player, effect)
	elseif action == "Root" then
		-- ⚠️ v11: Costura de Sombra — prende à distância, NÃO rouba.
		ok = executeRoot(player, effect, slot, def)
	elseif action == "Buff" then
		ok = executeBuff(player, slot, def, effect)
		-- ⚠️ v3: Buff SEM Duration + BallMagnetRadius = ação instantânea
		-- (Pulso do Primeiro Toque) — nesse caso é o ímã que decide o
		-- sucesso, não o "buff vazio".
		if effect.BallMagnetRadius and _G.PulseExecuteBallMagnet then
			local magnetOk = _G.PulseExecuteBallMagnet(player, effect)
			if not (def.Duration and def.Duration > 0) then
				ok = magnetOk
			end
		end
	end

	if ok then
		-- ⚠️ v110: carrinho de Hissatsu aplica o efeito dele NA CHEGADA (ver
		-- _G.PulseExecuteTackle no BallController) — aqui só o iframe próprio;
		-- o VFX dele também sai de lá (início e chegada). A Costura idem.
		if action == "Tackle" or action == "Root" then
			if effect.SelfIframe and _G.GrantPulseIframe then _G.GrantPulseIframe(player, effect.SelfIframe) end
		else
			applyExtraEffectKeys(player, slot, def, effect)
		end
		feedback(player, "Fired", def.Name)
		-- ⚠️ v109: VFX das Hissatsus sem cutscene (dribles/defesas) em todo cliente
		if Remotes.HissatsuVFX and player.Character and not def.Cutscene and action ~= "Tackle" and action ~= "Root" then
			Config.DispararVFX("HissatsuVFX", player.Character, def.Name, def.Element)
		end
	else
		-- A precondição já passou no aperto do botão, mas o estado do jogo
		-- mudou nesse meio tempo (perdeu a posse durante o wind-up, levou
		-- stun, etc.) — o cooldown já foi gasto (ver comentário no topo),
		-- não fica tentando de novo sozinho.
		feedback(player, "Fizzled", def.Name)
	end
	return ok
end

-- ===== ⚠️ v3: COMBO DE TECLAS (QTE) =====
-- Server-authoritative: o servidor guarda o tick() em que o PRIMEIRO
-- passo abre (StepsStart) e o tempo de cada passo (StepTime), e é ELE
-- quem decide, a cada aperto, em qual passo aquele aperto caiu e se a
-- tecla era a certa — nunca confia num "acertei" calculado no cliente.
-- Se nenhum aperto chegar, resolve sozinho quando o último passo fecha
-- (a ação NUNCA fica pendurada esperando pra sempre).
local function resolveCombo(state, player, slot)
	if state.Resolved then return end
	state.Resolved = true
	if Pending[player] and Pending[player][slot] == state then
		Pending[player][slot] = nil
	end

	local def = state.Def

	-- ⚠️ v3.2: WhiffRagdoll — diferente da regra geral ("nunca existe whiff
	-- total, a ação sempre dispara"), um Pulso marcado com esse campo (em
	-- segundos) trata "errar TODOS os passos" como uma FALHA DE VERDADE: em
	-- vez de disparar a versão fraca (Bom), o jogador se desequilibra na
	-- carga/movimento e cai em RAGDOLL por esse tempo — sem empurrar/acertar
	-- ninguém. Hoje só o Pulso do Carrinho Blindado usa isso (ver
	-- PulseInstinctData.luau) — o cooldown já foi gasto, é o risco de errar.
	if state.Hits == 0 and def.WhiffRagdoll and _G.RagdollPlayer then
		_G.RagdollPlayer(player, def.WhiffRagdoll)
		feedback(player, "Whiffed", def.Name)
		return
	end

	local perfect = state.Hits >= #state.Keys
	resolveAndExecute(player, slot, def, perfect and def.Perfect or def.Bom)
end

local function startCombo(player, slot, def)
	local delay, stepTime, total = comboTiming(def)
	if DebugNoDelay[player] then
		-- Zera só o WIND-UP (Delay) — o StepTime de cada passo continua de
		-- pé, senão não dá pra testar o timing do combo de verdade.
		total -= delay
		delay = 0
	end
	local keys = def.Combo and def.Combo.Keys

	-- Combo mal cadastrado (sem Keys): não trava o jogador esperando uma
	-- janela que nunca abre — dispara na hora, tratando como "Bom".
	if typeof(keys) ~= "table" or #keys == 0 or total <= 0 then
		resolveAndExecute(player, slot, def, def.Bom or def.Effect)
		return
	end

	local state = {
		Def = def,
		Keys = keys,
		StepTime = stepTime,
		StepsStart = tick() + delay, -- instante em que o PASSO 1 abre
		Answered = {},               -- [passo] = true (1 aperto por passo, o primeiro que chegar)
		Hits = 0,
		Resolved = false,
	}
	Pending[player][slot] = state

	-- ⚠️ Assinatura ganhou o array de teclas NO FIM — a ordem dos
	-- parâmetros anteriores é a mesma de sempre (lengthSeconds virou
	-- stepTime, o tempo de CADA passo).
	Remotes.PulsePrecisionPrompt:FireClient(player, slot, delay, stepTime, def.Name, keys)

	-- Iframe de wind-up longo (regra genérica, ver grantWindupIframe).
	grantWindupIframe(player, def, total)

	task.delay(total, function()
		if state.Resolved then return end
		resolveCombo(state, player, slot)
	end)
end

-- ===== ⚠️ v6: QTE NOVO DE HISSATSU (Tap / TimingBar / MashAD) =====
-- Diferente do combo de teclas (v3, acima): isso é o QTE pedido pro novo
-- lote de Pulsos inspirados em Inazuma Eleven —
--   "Tap"      (chutes): depois de def.QTE.PrepTime segundos de preparo
--               (SEM iframe — pode tomar carrinho, que cancela o chute:
--               ver comentário mais abaixo), aparecem def.QTE.HitCount
--               alvos em SEQUÊNCIA (5 por padrão — pedido: "vários botões
--               pra apertar, não só 1"), cada um em posição aleatória na
--               tela (sorteada no CLIENTE, dentro de um quadrado fixo — o
--               servidor só mede TEMPO/CONTAGEM, não posição), todos
--               dentro de UMA janela total de def.QTE.HitWindow segundos.
--               Bater os HitCount cliques até 70% da janela = Perfect,
--               depois disso (ou não completando todos) = Bom.
--   "TimingBar" (defesa): uma barra de def.QTE.Duration segundos, com o
--               marcador ANDANDO PRA FRENTE E PRA TRÁS em ciclos de
--               def.QTE.SweepPeriod segundos (pedido: "acertar a barra 5
--               vezes num período de tempo") — cada aperto dentro da
--               faixa "boa" (PerfectStart/PerfectEnd ± GoodPadding) conta
--               1 acerto, fora da faixa não conta nada (sem punição, só
--               ignora). Bater def.QTE.RequiredHits acertos (5 por
--               padrão) TODOS na faixa perfeita = Perfect; completar com
--               algum acerto só "bom" (dentro do padding) = Bom; não
--               bater a meta a tempo = Bom também (nunca existe whiff
--               total).
--   "MashAD"    (arrancada): alternar A/D — cada troca de tecla válida
--               conta 1 acerto; bater def.QTE.RequiredAlternations vira
--               Perfect (resolve na hora, sem esperar o resto do tempo).
-- Nos 3 casos: sem input nenhum até o tempo total acabar, resolve sozinho
-- como Bom (ou Perfect nos casos que já bateram a meta antes).
local SWEEP_PERIOD_DEFAULT = 0.9 -- segundos por ida (ou volta) do marcador da TimingBar

-- Posição do marcador da TimingBar (fração 0..1) num instante `elapsed`,
-- indo e voltando (ping-pong) em ciclos de `period` segundos — mesma
-- fórmula usada pelo cliente (HissatsuQTEWindow.luau) pro marcador visual
-- bater exatamente com o que o servidor considera "acerto".
local function sweepFraction(elapsed, period)
	period = math.max(period or SWEEP_PERIOD_DEFAULT, 0.1)
	local cycle = period * 2
	local t = elapsed % cycle
	if t <= period then
		return t / period
	end
	return 1 - (t - period) / period
end

local function hissatsuTiming(def)
	local qte = def.QTE
	if not qte then return nil end

	if qte.Kind == "Tap" then
		local prepTime = math.max(qte.PrepTime or 0, 0)
		local hitWindow = math.max(qte.HitWindow or 0.8, 0.1)
		return prepTime + hitWindow, prepTime, hitWindow
	elseif qte.Kind == "TimingBar" then
		return math.max(qte.Duration or 1.2, 0.2)
	elseif qte.Kind == "MashAD" then
		return math.max(qte.Duration or 2, 0.2)
	end
	return nil
end

-- ===== ⚠️ v87 — CUTSCENE DE HISSATSU =====
-- PEDIDO: "a cutscene é uma animação, só que vai aparecer ali a câmera
-- vidrada no personagem. Ninguém vai poder se mexer até ficar 100% completa.
-- Usou a Hissatsu, vai ter aquele cooldownzinho de 3, 4 segundos (o preparo +
-- QTE de sempre). Depois vai rolar a animação. Assim que acabar, o chute vai
-- sair. E aí o GK teria que usar a skill de GK pra defender, o zagueiro a de
-- zagueiro..."
--
-- O servidor aqui só faz o que precisa ser AUTORIDADE:
--   1. congela o jogo: todo personagem ancorado e com WalkSpeed 0, goleiros
--      bot parados, bola ancorada, e nenhum comando aceito (BallController e
--      o UsePulse abaixo checam _G.HissatsuCutsceneActive);
--   2. manda TODOS os clientes tocarem a cutscene, com o mesmo horário de
--      início (relógio do servidor), pra ela bater igual em toda tela;
--   3. quando acaba, põe o chutador e a bola exatamente onde a coreografia
--      termina (no ar, no ponto do chute), solta tudo e dispara o chute.
-- O resto — câmera, pose, fogo — é visual e mora no cliente
-- (HissatsuCutsceneClient.local.luau), lendo a mesma coreografia
-- (HissatsuCutscenes.luau). A defesa depois do chute é a de sempre: a bola sai
-- como qualquer chute de Hissatsu e as skills de GK/zagueiro reagem a ela.
local HissatsuCutscenes = require(ReplicatedStorage:WaitForChild("HissatsuCutscenes"))

_G.HissatsuCutsceneActive = nil

local function playHissatsuCutscene(player, def, onDone)
	local spec = HissatsuCutscenes[def.Cutscene]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local ball = workspace:FindFirstChild(Config.BALL_NAME)
	local dono = _G.GetBallOwner and _G.GetBallOwner()
	-- Sem coreografia, sem corpo, sem bola ou sem a posse: não tem o que
	-- mostrar — segue direto pro chute (que decide sozinho se ainda dá).
	if not spec or not root or not ball or dono ~= player then
		onDone()
		return
	end

	-- Uma cutscene por vez: se outra estiver rodando, espera ela acabar.
	while _G.HissatsuCutsceneActive do
		task.wait(0.1)
	end
	if not root.Parent or (_G.GetBallOwner and _G.GetBallOwner() ~= player) then
		onDone()
		return
	end

	local duration = spec.Duration

	-- Direção da cutscene = pra onde ele mirou (achatado no chão), igual ao
	-- chute que vai sair no fim.
	local target = LastAimPoint[player]
	local flat = target and Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z)
	if not flat or flat.Magnitude < 0.5 then
		flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local startCFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)

	_G.HissatsuCutsceneActive = { Player = player, Until = tick() + duration }

	-- 1) congela todo mundo (chutador incluso)
	local ancorados = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if otherRoot then
			otherRoot.AssemblyLinearVelocity = Vector3.zero
			otherRoot.Anchored = true
			table.insert(ancorados, otherRoot)
			freezeMovement(other, duration + 0.1)
		end
	end
	root.CFrame = startCFrame
	if _G.GetGKBotPositions and _G.FreezeGKBot then
		for _, bot in ipairs(_G.GetGKBotPositions()) do
			_G.FreezeGKBot(bot.TeamName, duration + 0.1)
		end
	end
	local congelouBola = _G.FreezeBallForQTE and _G.FreezeBallForQTE() or false
	if not congelouBola then ball.Anchored = true end -- já estava congelada por outro motivo: garante mesmo assim
	if _G.GrantPulseIframe then _G.GrantPulseIframe(player, duration + 0.3) end

	local ballLocal = startCFrame:PointToObjectSpace(ball.Position)

	-- 2) todo mundo assiste, sincronizado pelo relógio do servidor
	-- ⚠️ v108: Zona Morta de três — os vértices do triângulo são os 2 companheiros
	-- de verdade (o cliente copia a aparência deles no lugar das sombras)
	local extras = nil
	local trioState = def.Trio and Trio.Ativo[player]
	if trioState and trioState.Trio then
		extras = { Companheiros = {} }
		for _, r in ipairs(trioState.Trio.Apoios) do table.insert(extras.Companheiros, r.Mate) end
	elseif HissatsuCutscenes[def.Cutscene] and HissatsuCutscenes[def.Cutscene].Clones then
		-- ⚠️ v108: técnica de dupla (Raio Um) — o companheiro mais perto faz o
		-- parceiro na cena, com a aparência dele (sem ninguém perto: sombra)
		local qtd = HissatsuCutscenes[def.Cutscene].Clones.Quantidade or 1
		extras = { Companheiros = Trio.Proximos(player, 45, qtd) }
	end
	Remotes.HissatsuCutscene:FireAllClients(def.Cutscene, player, startCFrame, ballLocal, workspace:GetServerTimeNow(), def.Name, nil, extras)
	-- ⚠️ v103: a cutscene vai pro replay (o fantasma do chutador faz ela de novo)
	if _G.RegistrarEventoReplay then
		_G.RegistrarEventoReplay("Cutscene", {
			ator = "P" .. player.UserId, nome = def.Cutscene, titulo = def.Name,
			inicio = { startCFrame:GetComponents() }, bola = { ballLocal.X, ballLocal.Y, ballLocal.Z },
		})
	end

	-- 3) no fim: tudo no lugar do último quadro, solta, e o chute sai
	task.delay(duration, function()
		for _, r in ipairs(ancorados) do
			if r.Parent then r.Anchored = false end
		end
		if root.Parent then
			-- ⚠️ v120b — PEDIDO: "depois da Fúria Glacial (e de algumas habilidades) o
			-- personagem entra na terra, a animação e o torso bugam e ele cai no void".
			-- O último quadro de várias coreografias é agachado/aterrissando (altura do
			-- quadril NEGATIVA — e o servidor nem calibra o chão): o HRP era teleportado
			-- pra baixo da altura de pé e as pernas iam pra dentro do gramado. Agora só
			-- o deslocamento no chão (X/Z) vale; a altura nunca fica abaixo da de pé.
			local fim = spec.RootPosition(duration)
			root.CFrame = startCFrame * CFrame.new(fim.X, math.max(fim.Y, 0), fim.Z)
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if ball.Parent then
			ball.CFrame = CFrame.new(startCFrame:PointToWorldSpace(spec.BallPosition(duration, ballLocal)))
		end
		if congelouBola and _G.ReleaseBallFromQTE then
			_G.ReleaseBallFromQTE()
		else
			ball.Anchored = false
		end
		_G.HissatsuCutsceneActive = nil
		onDone()
	end)
end

-- ⚠️ v113 — CENA DO FLOW. PEDIDO: "flows com cutscene de anime de verdade,
-- 10-15 segundos, por personagem". Mesmo esquema da cutscene de Hissatsu:
-- congela todo mundo (e o relógio da partida — MatchController olha o campo
-- Flow), todos os clientes tocam a coreografia HissatsuCutscenes["Flow_..."]
-- sincronizada, e no fim tudo volta pro lugar. Devolve a duração (0 = sem
-- cena, o Flow começa na hora). O Flow só começa DEPOIS (InstinctController).
local CosmeticosFlow = nil
pcall(function() CosmeticosFlow = require(ReplicatedStorage:WaitForChild("Cosmeticos", 5)) end)
_G.TocarCenaFlow = function(player)
	if _G.HissatsuCutsceneActive then return 0 end
	local item = CosmeticosFlow and (CosmeticosFlow.Equipado(player, "Flow") or CosmeticosFlow.Item("Flow_Isagi"))
	local spec = item and HissatsuCutscenes[item.Id]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not spec or not root then return 0 end
	local duration = spec.Duration
	local ball = workspace:FindFirstChild(Config.BALL_NAME)
	local flat = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if flat.Magnitude < 0.01 then flat = Vector3.new(0, 0, -1) end
	local startCFrame = CFrame.lookAt(root.Position, root.Position + flat.Unit)
	_G.HissatsuCutsceneActive = { Player = player, Until = tick() + duration, Flow = true }

	local ancorados = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local otherRoot = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if otherRoot then
			otherRoot.AssemblyLinearVelocity = Vector3.zero
			otherRoot.Anchored = true
			table.insert(ancorados, otherRoot)
			freezeMovement(other, duration + 0.1)
		end
	end
	if _G.GetGKBotPositions and _G.FreezeGKBot then
		for _, bot in ipairs(_G.GetGKBotPositions()) do
			_G.FreezeGKBot(bot.TeamName, duration + 0.1)
		end
	end
	local congelouBola = false
	if ball then
		congelouBola = _G.FreezeBallForQTE and _G.FreezeBallForQTE() or false
		if not congelouBola then ball.Anchored = true end
	end
	if _G.GrantPulseIframe then _G.GrantPulseIframe(player, duration + 0.3) end
	local ballLocal = ball and startCFrame:PointToObjectSpace(ball.Position) or Vector3.new(0, -2.3, -1.8)
	-- ⚠️ v119 — PEDIDO: "o Rin é um companheiro aleatório, não um fantasma". A cena
	-- que pede (CompanheiroAleatorio) recebe um companheiro de time sorteado; sem
	-- ninguém no time, o cliente usa a sombra.
	local extras = nil
	if spec.CompanheiroAleatorio then
		local mates = {}
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player and other.Team and other.Team == player.Team
				and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
				table.insert(mates, other)
			end
		end
		-- ⚠️ v120b — PEDIDO: "o Rin (alguém aleatório) não tá aparecendo". Sem colega
		-- de time aparecia uma sombra do PRÓPRIO jogador; agora: colega de time →
		-- qualquer outro jogador → um goleiro bot (o cliente aceita Player ou Model)
		if #mates == 0 then
			for _, other in ipairs(Players:GetPlayers()) do
				if other ~= player and other.Character and other.Character:FindFirstChild("HumanoidRootPart") then
					table.insert(mates, other)
				end
			end
		end
		if #mates == 0 then
			for _, m in ipairs(workspace:GetChildren()) do
				if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" and m:FindFirstChild("HumanoidRootPart") then
					table.insert(mates, m)
				end
			end
		end
		if #mates > 0 then extras = { Companheiros = { mates[math.random(1, #mates)] } } end
	end
	Remotes.HissatsuCutscene:FireAllClients(item.Id, player, startCFrame, ballLocal, workspace:GetServerTimeNow(),
		"FLOW · " .. string.upper(item.Personagem or ""), duration, extras)

	task.delay(duration, function()
		for _, r in ipairs(ancorados) do
			if r.Parent then r.Anchored = false end
		end
		if root.Parent then
			root.CFrame = startCFrame
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if ball and ball.Parent then
			if congelouBola and _G.ReleaseBallFromQTE then
				_G.ReleaseBallFromQTE()
			else
				ball.Anchored = false
			end
		end
		_G.HissatsuCutsceneActive = nil
	end)
	return duration
end

-- ⚠️ v103 — CUTSCENE DE DEFESA. PEDIDO: "a Hissatsu de GK e de defensor
-- precisa sair instantaneamente com a colisão na hitbox, e a cutscene da
-- defesa vai acontecer se a bola colidir com essa hitbox." Chamada pelo
-- BallController (goleiro humano) e pelo GKBotController (bot) no instante da
-- colisão: congela todo mundo (igual a cutscene de chute) e todos os clientes
-- tocam a cutscene da técnica do goleiro (HissatsuCutscenes.Defesa_*) pela
-- duração do duelo. A bola já está congelada pela guarda. Devolve true se
-- tocou (quem chamou espera o fim pra aplicar o resultado).
_G.TocarCutsceneDeDefesa = function(model, def, duracao)
	if not model or not def then return false end
	if _G.HissatsuCutsceneActive then return false end
	local nome = def.CutsceneDefesa or (HissatsuCutscenes.DefesaPorNome and HissatsuCutscenes.DefesaPorNome[def.Name])
	if not nome or not HissatsuCutscenes[nome] then return false end
	local root = model:FindFirstChild("HumanoidRootPart")
	local ball = workspace:FindFirstChild(Config.BALL_NAME)
	if not root or not ball then return false end
	duracao = math.clamp(tonumber(duracao) or 3.5, 1.5, 6)

	local plano = Vector3.new(ball.Position.X - root.Position.X, 0, ball.Position.Z - root.Position.Z)
	if plano.Magnitude < 0.2 then plano = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	if plano.Magnitude < 0.01 then plano = Vector3.new(0, 0, -1) end
	local inicio = CFrame.lookAt(root.Position, root.Position + plano.Unit)
	local ballLocal = inicio:PointToObjectSpace(ball.Position)

	_G.HissatsuCutsceneActive = { Player = Players:GetPlayerFromCharacter(model), Until = tick() + duracao, Defesa = true }
	local ancorados = {}
	for _, other in ipairs(Players:GetPlayers()) do
		local r = other.Character and other.Character:FindFirstChild("HumanoidRootPart")
		if r and not r.Anchored then
			r.AssemblyLinearVelocity = Vector3.zero
			r.Anchored = true
			table.insert(ancorados, r)
		end
		freezeMovement(other, duracao + 0.1)
	end
	if _G.GetGKBotPositions and _G.FreezeGKBot then
		for _, bot in ipairs(_G.GetGKBotPositions()) do
			_G.FreezeGKBot(bot.TeamName, duracao + 0.1)
		end
	end

	local ator = Players:GetPlayerFromCharacter(model) or model
	Remotes.HissatsuCutscene:FireAllClients(nome, ator, inicio, ballLocal, workspace:GetServerTimeNow(), def.Name, duracao)
	if _G.RegistrarEventoReplay and _G.IdDoAtorReplay then
		local id = _G.IdDoAtorReplay(model)
		if id then
			_G.RegistrarEventoReplay("Cutscene", {
				ator = id, nome = nome, titulo = def.Name, dur = duracao,
				inicio = { inicio:GetComponents() }, bola = { ballLocal.X, ballLocal.Y, ballLocal.Z },
			})
		end
	end

	task.delay(duracao, function()
		for _, r in ipairs(ancorados) do
			if r.Parent then r.Anchored = false end
		end
		_G.HissatsuCutsceneActive = nil
	end)
	return true
end

local function resolveHissatsu(state, player, slot)
	if state.Resolved then return end
	state.Resolved = true
	if Pending[player] and Pending[player][slot] == state then
		Pending[player][slot] = nil
	end

	-- ⚠️ v11: o congelamento do chute (ver startHissatsuQTE) acaba AQUI, não
	-- no fim da janela — quem acerta os cliques rápido volta a se mexer
	-- antes. A guarda do goleiro tem congelamento próprio
	-- (_G.ConsumeGKGuardOnCollision) e não passa por essa checagem.
	if state.Kind == "Tap" and state.Def and (state.Def.Action == "Shot" or state.Def.FreezeBall)
		and not state.CutsceneMode then -- ⚠️ v95: com cutscene, quem solta é o fim dela
		clearMovementFreeze(player)
	end

	-- ⚠️ v14: o jogador volta a cair e a bola volta a existir fisicamente
	-- ANTES da ação rodar — se a bola ainda estivesse anchorada, a cabeçada
	-- sairia "sem bola" (o executor mexe na velocidade dela, que um objeto
	-- anchorado ignora).
	releaseAirHold(player)
	if state.FrozeBall and _G.ReleaseBallFromQTE then
		_G.ReleaseBallFromQTE()
	end

	-- ⚠️ v7: usado pela guarda do goleiro — o QTE dispara na COLISÃO da
	-- bola (ver _G.ConsumeGKGuardOnCollision), não na hora de usar o
	-- Pulso, e quem decide o que fazer com Perfect/Bom é o BallController
	-- (compara Físico vs Força do chute), não o dispatcher normal.
	-- ⚠️ NOVO: manda state.Hits junto (2º argumento) — usado pela
	-- Arrancada/Investida (ver _G.StartPulseDashTackle em
	-- BallController.legacy.luau) pra saber quantas alternâncias A/D
	-- renderam de verdade, não só o binário Perfect/Bom.
	if state.OnResolved then
		state.OnResolved(state.Perfect, state.Hits)
		return
	end

	local resolvedEffect = state.Perfect and state.Def.Perfect or state.Def.Bom

	-- ⚠️ v28: cada clique ALÉM do básico (os que a fórmula da Hissatsu liberou)
	-- soma força de verdade no chute — é o que faz o atributo valer a pena
	-- em vez de só encher a tela de alvo.
	if state.BaseHits and state.Hits and state.Hits > state.BaseHits and resolvedEffect then
		local extraHits = state.Hits - state.BaseHits
		local boosted = table.clone(resolvedEffect)
		boosted.ForceMult = (boosted.ForceMult or 1) * (1 + extraHits * Config.HISSATSU_QTE_BONUS_HIT_FORCE)
		resolvedEffect = boosted
	end

	-- ⚠️ v87/v95: Hissatsu com cutscene — o QTE roda DURANTE ela, e o chute
	-- só sai no último quadro. Se o QTE resolveu antes do fim (o normal),
	-- guarda o efeito e quem executa é o fim da cutscene (ver startHissatsuQTE).
	if state.CutsceneMode then
		state.EfeitoFinal = resolvedEffect
		if state.CutsceneAcabou and not state.Executou then
			state.Executou = true
			resolveAndExecute(player, slot, state.Def, resolvedEffect)
		end
		return
	end

	resolveAndExecute(player, slot, state.Def, resolvedEffect)
end

local function startHissatsuQTE(player, slot, def, onResolved)
	local qte = def.QTE
	local total, prepTime, hitWindow = hissatsuTiming(def)
	if not total then
		-- QTE mal cadastrado: dispara na hora como Bom, igual ao combo
		-- antigo faz quando não tem Keys.
		if onResolved then
			onResolved(false)
		else
			resolveAndExecute(player, slot, def, def.Bom or def.Effect)
		end
		return
	end

	if DebugNoDelay[player] and qte.Kind == "Tap" then
		total -= prepTime
		prepTime = 0
	end

	local state = {
		Kind = qte.Kind,
		Def = def,
		StepsStart = tick(),
		Resolved = false,
		Perfect = false,
		OnResolved = onResolved,
		-- MashAD:
		Hits = 0,
		LastKey = nil,
	}
	Pending[player][slot] = state

	local promptParams = { Kind = qte.Kind }
	if qte.Kind == "Tap" then
		-- ⚠️ v28 — PEDIDO: "coloca pro tempo aumentar conforme você vai
		-- melhorando a sua habilidade de Energy, e escala a quantidade de
		-- vezes que você pode clicar pra aumentar a força da bola. O máximo
		-- é ganhar mais TRÊS clicadas, e tempo suficiente pra conseguir
		-- clicar em todas se estiver maximizado."
		--
		-- Nota alta dá as duas coisas juntas, de propósito: mais cliques
		-- disponíveis E janela maior pra alcançá-los. Se só os cliques
		-- subissem, atributo alto viraria punição (mais alvos no mesmo
		-- tempo). A janela cresce um pouco mais rápido que os cliques, então
		-- quem está no máximo consegue mesmo fechar todos.
		--
		-- ⚠️ NOVO: a nota NÃO é mais a Energy (Energia é recurso, não
		-- potência) — é a FÓRMULA da própria Hissatsu (Scaling). Um chute
		-- 60% Chute + 40% Técnica ganha cliques com esses dois atributos.
		-- Sem fórmula, nota neutra (50).
		local rating = Config.GetHissatsuAttributeRating(player, def) or 50
		local energyFraction = math.clamp(rating, 0, 100) / 100

		local baseHits = math.max(qte.HitCount or 5, 1)
		local bonusHits = math.floor(energyFraction * Config.HISSATSU_QTE_MAX_BONUS_HITS + 0.0001)

		hitWindow = hitWindow * (1 + energyFraction * Config.HISSATSU_QTE_WINDOW_BONUS)
		total = prepTime + hitWindow

		-- ⚠️ v95 — PEDIDO: "os quick time events precisam ser ativados DURANTE
		-- a cutscene... atualmente são ativados antes da cutscene acontecer,
		-- mas precisa ser ao mesmo tempo". Hissatsu com cutscene: no fim do
		-- preparo a cutscene E o QTE começam juntos (ver o task.delay(prepTime)
		-- logo abaixo). A janela de cliques é encurtada pra caber na cutscene
		-- (acaba meio segundo antes do chute sair), e o resultado fica guardado
		-- até o último quadro — é lá que o chute sai (ver resolveHissatsu).
		local specCutscene = def.Cutscene and HissatsuCutscenes[def.Cutscene]
		if specCutscene then
			hitWindow = math.min(hitWindow, math.max(specCutscene.Duration - 0.5, 0.5))
			total = prepTime + hitWindow
			state.CutsceneMode = true
			promptParams.EmCutscene = true
		end

		state.PrepTime = prepTime
		state.HitWindow = hitWindow
		state.BaseHits = baseHits
		state.RequiredHits = baseHits + bonusHits
		promptParams.PrepTime = prepTime
		promptParams.HitWindow = hitWindow
		promptParams.RequiredHits = state.RequiredHits

		-- ⚠️ v108 — ZONA MORTA DE TRÊS: os 2 companheiros mais perto recebem o
		-- MESMO QTE (mesma janela, os cliques básicos da técnica) no slot
		-- "Apoio". Cada um registra se fechou os cliques e se foi perfeito; a
		-- conta final é no resolveAndExecute (Trio.Efeito), no fim da cutscene.
		if def.Trio then
			state.Jogador = player
			state.Trio = { Apoios = {} }
			Trio.Ativo[player] = state
			for _, mate in ipairs(Trio.Companheiros(player, def)) do
				ensurePlayerTables(mate)
				local registro = { Mate = mate, Ok = false, Perfect = false }
				local apoio = {
					Kind = "Tap", Def = def, StepsStart = state.StepsStart, Resolved = false, Perfect = false,
					Hits = 0, PrepTime = prepTime, HitWindow = hitWindow, BaseHits = baseHits, RequiredHits = baseHits,
					CutsceneMode = true, -- (não mexe no congelamento de quem apoia)
				}
				apoio.OnResolved = function(perfect, hits)
					registro.Ok = (hits or 0) >= apoio.RequiredHits
					registro.Perfect = registro.Ok and perfect and true or false
					registro.Hits = hits or 0 -- ⚠️ v110: a força soma pelos cliques de cada um
					registro.Req = apoio.RequiredHits
				end
				table.insert(state.Trio.Apoios, registro)
				Pending[mate].Apoio = apoio
				local params = table.clone(promptParams)
				params.PrepTime = 0
				params.RequiredHits = apoio.RequiredHits
				task.delay(prepTime, function()
					if apoio.Resolved or not mate.Parent then return end
					Remotes.PulseQTEPrompt:FireClient(mate, "Apoio", def.Name, params)
				end)
				task.delay(prepTime + hitWindow + 0.15, function()
					if not apoio.Resolved then resolveHissatsu(apoio, mate, "Apoio") end
				end)
			end
		end

		-- ⚠️ v11 PEDIDO: "o cara não pode se mexer durante a habilidade, pra
		-- ter aquela vulnerabilidade. Ele tá armando uma Hissatsu forte."
		-- O jogador fica IMÓVEL até o QTE resolver (ver clearMovementFreeze
		-- em resolveHissatsu — acertar rápido te solta mais cedo). Junto com
		-- o iframe só valer DEPOIS do preparo (task.delay logo abaixo), isso
		-- é o risco do chute: quanto mais forte a hissatsu, mais longo o
		-- PrepTime, mais tempo plantado e desarmável.
		-- ⚠️ v14: vale pra chute E pra qualquer Hissatsu que PARE a bola no
		-- ar (def.FreezeBall). Antes a cabeçada era exceção porque a bola
		-- continuava caindo e congelar o jogador garantiria que ele nunca
		-- chegasse nela — agora a bola espera por ele, então a regra do
		-- "não pode se mexer durante a habilidade" volta a valer também ali.
		if def.Action == "Shot" or def.FreezeBall then
			freezeMovement(player, total)
		end
		-- ⚠️ v103 — PEDIDO: "coloca uma animação pra iniciar todas as
		-- Hissatsus... começa a preparar um chutão diferente, um foguinho em
		-- volta dele bem de leve, umas faíscas". Pose e VFX leve do PREPARO,
		-- em todo cliente (AnimadorProcedural + HissatsuCutsceneClient).
		if def.Action == "Shot" and player.Character and Remotes.AcaoAnimada and prepTime > 0.1 then
			Remotes.AcaoAnimada:FireAllClients(player.Character, "HissatsuPreparo", prepTime,
				{ Estilo = def.Cutscene or def.Element or "Padrao" })
		end

		-- ⚠️ v14: a bola trava no ar JÁ no aperto (não depois do preparo) —
		-- é o instante dramático da técnica, e é o que impede a bola de
		-- cair no chão durante o preparo e a cabeçada virar impossível.
		-- Guarda quem foi que congelou: se a bola JÁ estava congelada (guarda
		-- de goleiro em andamento), FreezeBallForQTE devolve false e este
		-- QTE não pode soltá-la no fim — soltar seria cancelar a defesa do
		-- goleiro no meio do QTE dele.
		if def.FreezeBall and _G.FreezeBallForQTE then
			state.FrozeBall = _G.FreezeBallForQTE()
		end

		-- ⚠️ PEDIDO: "os primeiros 2-3 segundos de preparação podem tomar
		-- carrinho (cancela o pulso), e o restante é iframe".
		-- ⚠️ v35: a v34 tinha tirado essa vulnerabilidade, mas foi um
		-- mal-entendido meu — o pedido era sobre QUANDO A CAIXA DO QTE
		-- APARECE, não sobre poder tomar carrinho. O preparo volta a ser
		-- vulnerável: é o risco que justifica a força da Hissatsu.
		task.delay(prepTime, function()
			if state.Resolved then return end
			if _G.GrantPulseIframe then
				_G.GrantPulseIframe(player, math.max(hitWindow, 0.1))
			end
			-- ⚠️ v14: o salto sai junto com o iframe, no fim do preparo — é
			-- o momento em que a técnica "acontece". Quem não tem
			-- AirLaunchHeight simplesmente continua no chão.
			-- ⚠️ v87: Hissatsu com cutscene não pula aqui — o salto é da
			-- própria cutscene, que começa com os pés no chão.
			if not def.Cutscene then
				launchIntoAir(player, def.AirLaunchHeight)
			end
			-- ⚠️ v95: a cutscene começa AGORA, junto com o QTE (o prompt do
			-- QTE sai neste mesmo instante, ver o task.delay(prepTime) do
			-- PulseQTEPrompt mais abaixo). No último quadro dela o chute sai
			-- com o que o QTE decidiu — ou, se o jogador ainda não terminou de
			-- clicar (não deveria: a janela acaba antes), resolve ali mesmo.
			if state.CutsceneMode then
				playHissatsuCutscene(player, def, function()
					state.CutsceneAcabou = true
					if not state.Resolved then
						resolveHissatsu(state, player, slot) -- já executa: CutsceneAcabou
					elseif state.EfeitoFinal and not state.Executou then
						state.Executou = true
						resolveAndExecute(player, slot, def, state.EfeitoFinal)
					end
				end)
			end
		end)
	elseif qte.Kind == "TimingBar" then
		state.Duration = total
		state.PerfectStart = math.clamp(qte.PerfectStart or 0.4, 0, 1)
		state.PerfectEnd = math.clamp(qte.PerfectEnd or 0.6, state.PerfectStart, 1)
		state.GoodPadding = math.max(qte.GoodPadding or 0.12, 0)
		state.SweepPeriod = math.max(qte.SweepPeriod or SWEEP_PERIOD_DEFAULT, 0.1)
		state.RequiredHits = math.max(qte.RequiredHits or 5, 1)
		state.AllPerfect = true
		promptParams.Duration = total
		promptParams.PerfectStart = state.PerfectStart
		promptParams.PerfectEnd = state.PerfectEnd
		promptParams.GoodPadding = state.GoodPadding
		promptParams.SweepPeriod = state.SweepPeriod
		promptParams.RequiredHits = state.RequiredHits
		grantWindupIframe(player, def, total)
	elseif qte.Kind == "MashAD" then
		state.Duration = total
		state.RequiredAlternations = math.max(qte.RequiredAlternations or 6, 1)
		promptParams.Duration = total
		promptParams.RequiredAlternations = state.RequiredAlternations
		grantWindupIframe(player, def, total)
	end

	-- ⚠️ v35 — PEDIDO: "a caixa do QTE não é pra aparecer na hora que você
	-- clica. É pra aparecer DEPOIS QUE ACABA O WIND-UP. Quando começar o QTE,
	-- aí ela aparece de verdade."
	--
	-- Antes o prompt era mandado no instante do aperto, com o PrepTime junto —
	-- então a caixa nascia na tela e ficava lá parada durante todo o preparo.
	-- Agora, no "Tap", ela só é mandada quando o preparo TERMINA, e já vai com
	-- PrepTime = 0: o cliente abre direto na fase de clicar.
	-- Os outros QTEs (TimingBar do goleiro, MashAD da arrancada) não têm
	-- preparo nenhum, então continuam sendo mandados na hora.
	if qte.Kind == "Tap" and prepTime > 0 then
		promptParams.PrepTime = 0
		task.delay(prepTime, function()
			if state.Resolved then return end
			Remotes.PulseQTEPrompt:FireClient(player, slot, def.Name, promptParams)
		end)
	else
		Remotes.PulseQTEPrompt:FireClient(player, slot, def.Name, promptParams)
	end

	task.delay(total, function()
		if state.Resolved then return end
		resolveHissatsu(state, player, slot)
	end)
end

-- ===== v7: GUARDA DO GOLEIRO (Hissatsu Buff + RoleRequired="GK") =====
-- PEDIDO: "a de goleiro você vai poder preparar antes, vai apertar o
-- botão e não vai usar o QTE, só vai ficar com o efeito do goleiro. E aí
-- assim que a de chute colidir com o goleiro, aí sim começa o QTE do
-- goleiro pra defender." Ou seja: Mão Divina/Guardião Absoluto NÃO
-- disparam mais o TimingBar na hora que são usadas (isGKGuardPulse) — só
-- armam uma "guarda" (ver GKGuard acima) por def.Duration segundos, com
-- o goleiro PARADO (freezeMovement) e uma área visível na frente dele
-- (o quadrado flutuante fica em BallController.legacy.luau, que também é
-- quem detecta a colisão do chute com essa área e chama
-- _G.ConsumeGKGuardOnCollision — só aí o QTE de verdade começa).
local function isGKGuardPulse(def)
	return def.Action == "Buff" and def.RoleRequired == "GK" and def.QTE ~= nil
end

local function startGKGuard(player, slot, def)
	local duration = math.max(def.Duration or 5, 1)
	GKGuard[player] = {
		Def = def,
		Slot = slot,
		ExpiresAt = tick() + duration,
		-- ⚠️ v36: tamanho da guarda também escala com Physical (RoleRequired
		-- é sempre "GK" aqui — ver isGKGuardPulse acima), junto com o motivo
		-- que pediu isso: "diminua o tamanho base das habilidades, porque
		-- estão ocupando literalmente o gol inteiro" — ver base MENOR em
		-- PulseInstinctData.lua (Mão Divina/Guardião Absoluto).
		GuardSize = (def.QTE.GuardSize or 0.5) * getPulsePowerScale(player, def),
	}
	freezeMovement(player, duration)
	-- O cooldown/HUD já fica sabendo pelo feedback "Used" mandado pelo
	-- Remotes.UsePulse acima — aqui só falta avisar o cliente pra mostrar
	-- o indicador visual de "guarda armada" (sem QTE nenhum agora).
	Remotes.PulseQTEPrompt:FireClient(player, slot, def.Name, { Kind = "GKGuardArmed", Duration = duration })
	task.delay(duration, function()
		local guard = GKGuard[player]
		if guard and guard.Slot == slot and tick() >= guard.ExpiresAt then
			GKGuard[player] = nil
		end
	end)
end

-- Consultado por BallController.legacy.luau (visual do quadrado +
-- detecção de colisão). Retorna nil se não tem guarda ativa.
_G.GetGKGuard = function(player)
	local guard = GKGuard[player]
	if not guard or tick() >= guard.ExpiresAt then return nil end
	return guard
end

-- ⚠️ v108 — chute NORMAL (não-Hissatsu) na guarda: o goleiro pega na hora, SEM
-- QTE (ver BallController, "defesa instantânea"). Consome a guarda, solta o
-- goleiro e fecha o indicador de guarda armada no cliente. Devolve a Hissatsu.
_G.ConsumirGuardaSemQTE = function(player)
	local guard = GKGuard[player]
	if not guard or tick() >= guard.ExpiresAt then return nil end
	GKGuard[player] = nil
	clearMovementFreeze(player)
	feedback(player, "Fired", guard.Def.Name)
	return guard.Def
end

-- Chamado por BallController.legacy.luau quando o chute de Pulso colide
-- com a área da guarda — CONSOME a guarda (só serve pra 1 bola) e só
-- ENTÃO dispara o TimingBar de verdade. onResult(perfect, effect) é
-- chamado quando o QTE resolver (clique do goleiro ou timeout).
-- ⚠️ v103: onHit(hits, dano) é chamado a CADA acerto do QTE do goleiro, com
-- o dano daquele acerto (Config.DEFESA_DANO_POR_ACERTO pela raridade x escala
-- de atributo; acerto perfeito vale mais) — é o que tira vida da bola no
-- duelo (ver iniciarDueloDeDefesa no BallController).
local function danoPorAcertoDeDefesa(player, def)
	local base = (Config.DEFESA_DANO_POR_ACERTO or {})[def.Rarity or "Common"] or 25
	return base * getPulsePowerScale(player, def)
end
_G.DanoPorAcertoDeDefesa = danoPorAcertoDeDefesa

-- ⚠️ v107 — dano da defesa em duas partes (ver Config.DEFESA_IMPACTO_FRACAO):
-- IMPACTO (entra quando a mão/soco encontra a bola) + POR ACERTO do QTE.
-- Capacidade = dano por acerto x acertos pedidos, vezes: escala de atributo
-- (player) ou `escala` (bot), elemento contra o chute atual e bônus de
-- elemento próprio. player pode ser nil (goleiro bot).
local function danoDaDefesa(player, def, escala)
	local acertos = (def.QTE and def.QTE.RequiredHits) or 5
	local base = (Config.DEFESA_DANO_POR_ACERTO or {})[def.Rarity or "Common"] or 25
	local mult = escala or (player and getPulsePowerScale(player, def)) or 1
	local info = _G.GetLastPulseShotInfo and _G.GetLastPulseShotInfo()
	local elemChute = info and info.Element
	local elemental = Config.MultElementalDaDefesa and Config.MultElementalDaDefesa(elemChute, def.Element) or 1
	local proprio = player and getElementSelfMatchScale(player, def) or 1
	local capacidade = base * acertos * mult * elemental * proprio
	-- ⚠️ v109: chute que QUEBRA defesa (Ruptura de Gaia) tira essa fração da capacidade
	local quebra = info and tonumber(info.QuebraDefesa) or 0
	if quebra > 0 then capacidade *= (1 - math.clamp(quebra, 0, 0.8)) end
	local fracao = Config.DEFESA_IMPACTO_FRACAO or 0.5
	if Config.PULSE_FORCE_DEBUG_PRINTS then
		print(string.format("🧤 [Duelo] %s (%s) x chute %s: capacidade %d (atributo %.2f, elemento %.2f, próprio %.2f) = impacto %d + %d por acerto",
			def.Name or "?", tostring(def.Element), tostring(elemChute), math.floor(capacidade), mult, elemental, proprio,
			math.floor(capacidade * fracao), math.floor(capacidade * (1 - fracao) / acertos)))
	end
	return capacidade * fracao, capacidade * (1 - fracao) / acertos, acertos
end
_G.DanoDaDefesa = danoDaDefesa

_G.ConsumeGKGuardOnCollision = function(player, onResult, onHit)
	local guard = GKGuard[player]
	if not guard then return false end
	GKGuard[player] = nil
	freezeMovement(player, hissatsuTiming(guard.Def) or 3)
	local impacto, dano = danoDaDefesa(player, guard.Def)
	-- ⚠️ v107: o impacto entra quando a mão encontra a bola na cutscene
	if onHit then
		task.delay(0.5, function() onHit(0, impacto) end)
	end
	startHissatsuQTE(player, guard.Slot, guard.Def, function(perfect, hits)
		-- ⚠️ v36: DiveRadiusAdd também escala com Physical, igual GuardSize
		-- (ver applyPulsePowerScale/getPulsePowerScale acima).
		local effect = applyPulsePowerScale(player, guard.Def, perfect and guard.Def.Perfect or guard.Def.Bom)
		onResult(perfect, effect, hits)
	end)
	local state = Pending[player] and Pending[player][guard.Slot]
	if state and onHit then
		state.OnHit = function(hits, perfeito)
			onHit(hits, dano * (perfeito and (Config.DEFESA_DANO_PERFEITO_MULT or 1) or 1))
		end
	end
	return true
end

Remotes.PulseQTEInput.OnServerEvent:Connect(function(player, slotArg, payload)
	local slot = (slotArg == 2 and 2) or (slotArg == "Apoio" and "Apoio") or 1 -- ⚠️ v108: "Apoio" = companheiro da Zona Morta
	local state = Pending[player] and Pending[player][slot]
	if not state or state.Resolved or not state.Kind then return end -- not state.Kind: é um combo de teclas antigo, não um Hissatsu QTE

	local now = tick()

	if state.Kind == "Tap" then
		local openAt = state.StepsStart + state.PrepTime
		local closeAt = openAt + state.HitWindow
		if now < openAt or now > closeAt then
			-- ⚠️ v24: clicou fora da janela. Antes era um `return` mudo; agora
			-- avisa o cliente pra piscar VERMELHO (ver o flash em
			-- AbilityHUD.local.luau) — errar tem que ser visível.
			feedback(player, "ComboStep", { Hit = false })
			return
		end
		state.Hits += 1
		feedback(player, "ComboStep", { Index = state.Hits, Hit = true })
		if state.OnHit then state.OnHit(state.Hits, false) end -- ⚠️ v103: duelo de defesa
		if state.Hits >= state.RequiredHits then
			local elapsedInWindow = now - openAt
			state.Perfect = elapsedInWindow <= state.HitWindow * 0.7
			resolveHissatsu(state, player, slot)
		end
		-- Menos que RequiredHits ainda: não resolve — espera o próximo
		-- clique (ou o timeout geral, que resolve como Bom sozinho).
	elseif state.Kind == "TimingBar" then
		-- Marcador em ping-pong (sweepFraction) — cada aperto DENTRO da
		-- faixa boa conta 1 acerto; fora da faixa não conta nada (sem
		-- punição, só ignora, pra não travar quem errou o timing de um
		-- ciclo). Só resolve depois de bater RequiredHits acertos.
		if now > state.StepsStart + state.Duration then return end
		local elapsed = now - state.StepsStart
		local fraction = sweepFraction(elapsed, state.SweepPeriod)
		local goodStart = math.max(state.PerfectStart - state.GoodPadding, 0)
		local goodEnd = math.min(state.PerfectEnd + state.GoodPadding, 1)
		if fraction < goodStart or fraction > goodEnd then
			feedback(player, "ComboStep", { Hit = false }) -- ⚠️ v24: fora da faixa = pisca vermelho
			return
		end
		local isPerfectHit = fraction >= state.PerfectStart and fraction <= state.PerfectEnd
		if not isPerfectHit then state.AllPerfect = false end
		state.Hits += 1
		-- ⚠️ v24: manda a QUALIDADE junto — acerto na faixa perfeita pisca
		-- DOURADO, acerto só "bom" pisca verde.
		feedback(player, "ComboStep", { Index = state.Hits, Hit = true, Perfect = isPerfectHit })
		if state.OnHit then state.OnHit(state.Hits, isPerfectHit) end -- ⚠️ v103: duelo de defesa
		if state.Hits >= state.RequiredHits then
			state.Perfect = state.AllPerfect
			resolveHissatsu(state, player, slot)
		end
	elseif state.Kind == "MashAD" then
		local key = typeof(payload) == "table" and payload.Key
		if key ~= "A" and key ~= "D" then return end
		if key == state.LastKey then return end -- precisa ALTERNAR — a mesma tecla duas vezes seguidas não conta
		state.LastKey = key
		state.Hits += 1
		feedback(player, "ComboStep", { Index = state.Hits, Hit = true }) -- reaproveita o mesmo kind do combo antigo pro cliente animar a barra de progresso
		-- ⚠️ NOVO: avisa em TEMPO REAL (não só na resolução final) — usado
		-- pela Arrancada/Investida pra crescer a hitbox do dash AO VIVO
		-- conforme o jogador ainda está alternando A/D (ver
		-- _G.RegisterQTEHitCallback abaixo e _G.StartPulseDashTackle em
		-- BallController.legacy.luau).
		if state.OnHit then state.OnHit(state.Hits) end
		if state.Hits >= state.RequiredAlternations then
			state.Perfect = true
			resolveHissatsu(state, player, slot)
		end
	end
end)

-- ⚠️ NOVO: exposto pra BallController.lua conseguir disparar e acompanhar
-- o QTE de alternância (MashAD) da Arrancada/Investida sem duplicar toda
-- a máquina de QTE aqui — a movimentação física do dash e a detecção de
-- colisão da hitbox moram em BallController.lua (mesmo lugar do carrinho
-- normal), só o "input A/D"/contagem de acertos continuam aqui.
_G.StartHissatsuQTE = startHissatsuQTE

-- Registra um callback chamado a cada acerto de alternância (A/D) NO MEIO
-- do QTE, não só na resolução final — ver uso em state.OnHit acima.
_G.RegisterQTEHitCallback = function(player, slot, onHit)
	local state = Pending[player] and Pending[player][slot]
	if state then
		state.OnHit = onHit
	end
end

Remotes.PulsePrecisionInput.OnServerEvent:Connect(function(player, slotArg, keyArg)
	local slot = (slotArg == 2) and 2 or 1
	local state = Pending[player] and Pending[player][slot]
	if not state or state.Resolved or state.Kind then return end -- state.Kind: é um QTE de Hissatsu (v6), não um combo de teclas antigo
	if typeof(keyArg) ~= "string" then return end

	local now = tick()
	local grace = Config.PULSE_COMBO_INPUT_GRACE or 0
	if now < state.StepsStart - grace then
		return -- aperto cedo demais (nem a antecipação de graça alcança o primeiro passo) — ignora, não conta nem como acerto nem como erro
	end

	-- Em qual passo esse aperto caiu (mesma conta que o cliente usa pra
	-- desenhar o chip atual — mas quem manda é esta, aqui). ⚠️ v3.2: soma a
	-- "graça" de antecipação — um aperto um pouco ANTES do passo abrir de
	-- verdade ainda cai dentro dele, em vez de ser perdido.
	local index = math.floor((now - state.StepsStart + grace) / state.StepTime) + 1
	if index < 1 then index = 1 end
	if index > #state.Keys then return end -- o último passo já fechou: a resolução automática assume
	if state.Answered[index] then return end            -- 1 aperto por passo

	state.Answered[index] = true
	local hit = (state.Keys[index] == keyArg)
	if hit then
		state.Hits += 1
	end
	-- Reconfirma o passo pro cliente (ele já pintou o chip localmente no
	-- instante do aperto — isso aqui é a versão do SERVIDOR, que é a que
	-- vale).
	feedback(player, "ComboStep", { Index = index, Hit = hit })

	-- Último passo respondido: resolve na hora em vez de esperar o resto
	-- da janela dele fechar.
	if index >= #state.Keys then
		resolveCombo(state, player, slot)
	end
end)

-- ===== ENTRADA PRINCIPAL: aperta o botão do Pulso =====
local AguardandoCutscene = {} -- ⚠️ v105: [player] = true com um aperto de guarda guardado (ver abaixo)
Players.PlayerRemoving:Connect(function(p) AguardandoCutscene[p] = nil end)
local function onUsePulse(player, slotArg, aimPointArg)
	-- ⚠️ v105 — "a Hissatsu mítica do goleiro não tirava nada de vida": o goleiro
	-- arma a guarda apertando a tecla QUANDO VÊ o chute vindo — que é justamente
	-- durante a cutscene do chute, quando todo aperto era jogado fora. Sem
	-- guarda, sem colisão, sem QTE: a bola passava inteira. Agora, goleiro na
	-- área que aperta durante a cutscene tem o aperto GUARDADO e aplicado assim
	-- que ela acaba (antes da bola voar). O resto continua bloqueado (v87).
	if _G.HissatsuCutsceneActive then
		if GKAreaUtil.IsEffectiveGK(player) and not AguardandoCutscene[player] then
			AguardandoCutscene[player] = true
			task.spawn(function()
				local limite = tick() + 12
				while _G.HissatsuCutsceneActive and tick() < limite do task.wait(0.05) end
				AguardandoCutscene[player] = nil
				if player.Parent then onUsePulse(player, slotArg, aimPointArg) end
			end)
		end
		return
	end
	-- ⚠️ v76: slot 3 adicionado (Hissatsu extra comprada com Robux — ver
	-- RollServer.legacy.luau no Lobby). Qualquer coisa que não seja 2 ou
	-- 3 continua caindo em 1, igual sempre foi.
	local slot = (slotArg == 2 and 2) or (slotArg == 3 and 3) or 1
	ensurePlayerTables(player)

	-- ⚠️ v7 PEDIDO: mira da Hissatsu de chute = exatamente onde o jogador
	-- estava mirando (mesmo cálculo do chute padrão, ver HissatsuInput.
	-- local.luau) — guardado aqui e lido por _G.PulseComputeShotTarget no
	-- BallController. Sem isso (Pulso que não manda mira, ou goleiro
	-- armando a guarda), cai no fallback automático de sempre.
	if typeof(aimPointArg) == "Vector3" then
		LastAimPoint[player] = aimPointArg
	end

	-- Goleiro DENTRO da própria área só tem 1 slot de verdade (R, sempre
	-- slot 1) — fora da área ele vira jogador de linha normal e ganha o
	-- slot 2 de volta (ver GKAreaUtil.lua). Defesa em profundidade (o
	-- cliente já nem manda slot 2 pra GK dentro da área, ver PulseInput.
	-- local.luau).
	-- ⚠️ v76: slot >= 2 (era só "== 2") — goleiro dentro da área continua
	-- restrito a 1 slot só, e agora existe um slot 3 pra também bloquear.
	-- ⚠️ v106 — PEDIDO: "o slot 2 às vezes não funciona pra algumas pessoas, o
	-- slot 1 pra outras... os dois têm que funcionar". O goleiro na área só
	-- podia usar o SLOT 1 — quem tinha a Hissatsu de goleiro no slot 2 não
	-- conseguia defender com ela. Agora vale o TIPO, não o número do slot: na
	-- área, o goleiro usa a Hissatsu de goleiro que estiver em qualquer slot
	-- (as de linha continuam bloqueadas pra ele lá dentro).
	local pulseName = Loadout[player][slot]
	if not pulseName then
		feedback(player, "NoPulseEquipped", slot)
		return
	end
	local def = findPulse(pulseName)
	if not def then
		warn(("[Pulso] %s: a Hissatsu '%s' do slot %d não existe nos dados (nome antigo?)"):format(player.Name, tostring(pulseName), slot))
		feedback(player, "NoPulseEquipped", slot)
		return
	end
	if GKAreaUtil.IsEffectiveGK(player) and def.RoleRequired ~= "GK" then
		feedback(player, "WrongRole", slot)
		return
	end

	local debugFlags = DebugFlags[player] or {}
	if not DebugNoDelay[player] and not debugFlags.SemCooldown and ReadyAt[player][slot] and tick() < ReadyAt[player][slot] then
		feedback(player, "OnCooldown", ReadyAt[player][slot] - tick())
		return
	end
	if not roleOk(player, def) then
		feedback(player, "WrongRole", slot)
		return
	end
	if Pending[player][slot] then
		feedback(player, "AlreadyArmed", slot) -- já esperando o combo desse slot resolver
		return
	end

	local precheckOk, reason = actionPrecheck(player, def)
	if not precheckOk then
		feedback(player, "NoTarget", reason)
		return
	end
	-- ⚠️ v108: Zona Morta só com 2 companheiros perto (nada gasto se faltar)
	-- (debugger "chutes em grupo sozinho": sem companheiros, sombras no lugar)
	if def.Trio and not (DebugFlags[player] and DebugFlags[player].TrioSozinho)
		and #Trio.Companheiros(player, def) < (def.Trio.Companheiros or 2) then
		feedback(player, "Aviso", ("%s precisa de %d companheiros perto de você"):format(def.Name, def.Trio.Companheiros or 2))
		return
	end

	-- ⚠️ v9: "energia de ativação" — sem pool suficiente, o Pulso nem
	-- dispara (cooldown NÃO começa a contar, pra não punir duas vezes).
	ensureEnergy(player)
	-- ⚠️ v27: o custo agora depende da RARIDADE (ver
	-- Config.PULSE_ENERGY_COST_BY_RARITY) — é o que limita quantas vezes uma
	-- Hissatsu forte cabe numa rodada, já que o pool só reenche no intervalo.
	-- ⚠️ NOVO: def.EnergyCost (opcional) — custo próprio da Hissatsu, na
	-- frente da tabela por raridade. PEDIDO: "A Energia deve determinar o
	-- custo para utilizar a Hissatsu, e não sua potência".
	local energyCost = (typeof(def.EnergyCost) == "number" and def.EnergyCost)
		or (Config.PULSE_ENERGY_COST_BY_RARITY and Config.PULSE_ENERGY_COST_BY_RARITY[def.Rarity])
		or Config.PULSE_ENERGY_COST
	if debugFlags.Energia then EnergyPool[player] = maxEnergyPool(player) end -- ⚠️ v110: debug, energia infinita
	if EnergyPool[player] < energyCost then
		feedback(player, "NotEnoughEnergy", energyCost - EnergyPool[player])
		return
	end
	EnergyPool[player] -= energyCost
	if debugFlags.Energia then EnergyPool[player] = maxEnergyPool(player) end
	lastSentEnergy[player] = math.floor(EnergyPool[player] + 0.5)
	Remotes.PulseEnergyFeedback:FireClient(player, lastSentEnergy[player], math.floor(maxEnergyPool(player)))

	-- É esse aperto que "gasta" o Pulso — o efeito real pode resolver um
	-- pouco depois (combo de teclas), mas o cooldown já começa aqui.
	startCooldown(player, slot, def)
	feedback(player, "Used", def.Name)

	if def.Combo then
		startCombo(player, slot, def)
	elseif isGKGuardPulse(def) then
		startGKGuard(player, slot, def)
	elseif def.Action == "Tackle" and def.QTE and def.QTE.Kind == "MashAD" and _G.StartPulseDashTackle then
		-- ⚠️ NOVO: Arrancada Selvagem/Investida Titânica — dash reto pra
		-- frente com hitbox crescente (ver _G.StartPulseDashTackle em
		-- BallController.legacy.luau); NÃO passa pelo resolveAndExecute
		-- genérico, o próprio dash resolve o acerto/roubo quando a hitbox
		-- tocar em alguém.
		_G.StartPulseDashTackle(player, slot, def)
	elseif def.QTE then
		startHissatsuQTE(player, slot, def)
	elseif def.Cutscene and def.Action ~= "Shot" then
		-- ⚠️ v110 — DRIBLE COM CUTSCENE (Chuva de Meteoros): sem QTE; a cena
		-- toca pra todo mundo e, no último quadro dela (os meteoros acabaram de
		-- cair), o drible sai e quem estava no raio é derrubado.
		grantWindupIframe(player, def, 0)
		playHissatsuCutscene(player, def, function()
			resolveAndExecute(player, slot, def, def.Effect)
		end)
	else
		-- Mesmo instantâneo, um Pulso pode pedir iframe explicitamente
		-- (Iframe = true) — o wind-up dele é 0, então a regra automática
		-- sozinha nunca daria.
		grantWindupIframe(player, def, 0)
		resolveAndExecute(player, slot, def, def.Effect)
	end
end
Remotes.UsePulse.OnServerEvent:Connect(onUsePulse)

-- ===== BUFFS ATIVOS (1 por slot, os dois somam) =====
local function getActiveEffects(player)
	local buffs = ActiveBuff[player]
	if not buffs then return nil, nil end
	local a, b = buffs[1], buffs[2]
	if a and tick() >= a.ExpiresAt then buffs[1] = nil; a = nil end
	if b and tick() >= b.ExpiresAt then buffs[2] = nil; b = nil end
	return a and a.Effect, b and b.Effect
end

-- ⚠️ v3: buff de área concedido por um companheiro (Pulso do General) —
-- some sozinho quando expira. Multiplicado por cima dos buffs de slot nos
-- getters abaixo, sem precisar mexer no PlayerSystems.
local function getTeamBuff(player)
	local buff = TeamBuff[player]
	if not buff then return nil end
	if tick() >= buff.ExpiresAt then
		TeamBuff[player] = nil
		return nil
	end
	return buff
end

local function sumField(field, default)
	return function(player)
		local e1, e2 = getActiveEffects(player)
		local total = default
		if e1 and e1[field] then total = (default == 1) and (total * e1[field]) or (total + e1[field]) end
		if e2 and e2[field] then total = (default == 1) and (total * e2[field]) or (total + e2[field]) end
		return total
	end
end

local slotSpeedMultiplier = sumField("SpeedMult", 1)

_G.GetPulseSpeedMultiplier = function(player)
	local mult = slotSpeedMultiplier(player)
	mult *= getPiqueMultiplier(player) -- ⚠️ v67: pique do Vendaval
	local teamBuff = getTeamBuff(player)
	if teamBuff and teamBuff.SpeedMult then mult *= teamBuff.SpeedMult end
	-- ⚠️ v11: Teia / Névoa — lentidão por ZONA entra aqui porque
	-- PlayerSystems já lê esse getter todo frame (o Heartbeat de sprint
	-- reescreve WalkSpeed sozinho, então mexer no WalkSpeed direto não
	-- sobreviveria ao frame seguinte — mesmo motivo do v9 FIX do freeze).
	mult *= getZoneSlowMultiplier(player)
	return mult
end

_G.GetPulseStaminaRegenMultiplier = sumField("StaminaRegenMult", 1)
_G.GetPulsePickupRadiusAdd = sumField("PickupRadiusAdd", 0)
_G.GetPulseActiveAnkleRangeAdd = sumField("AnkleRangeAdd", 0)

_G.GetPulseActiveKickForceMult = function(player)
	local e1, e2 = getActiveEffects(player)
	local mult = 1
	if e1 then mult *= (e1.KickForceMult or e1.PassForceMultAura or 1) end
	if e2 then mult *= (e2.KickForceMult or e2.PassForceMultAura or 1) end

	-- ⚠️ v3: buff de área do time (Pulso do General) — diferente do
	-- TeammateBuff abaixo, NÃO é consumido no primeiro chute: vale o
	-- tempo inteiro do buff.
	local teamBuff = getTeamBuff(player)
	if teamBuff and teamBuff.ForceMult then mult *= teamBuff.ForceMult end

	-- Bônus de "próximo chute" concedido por um companheiro (Pulso do
	-- Camisa 10) — consome no primeiro chute em que é lido.
	local tb = TeammateBuff[player]
	if tb then
		TeammateBuff[player] = nil
		if tick() < tb.ExpiresAt then
			mult *= tb.ForceMult
		end
	end

	return mult
end

-- Pulso do Muro Final: bloqueia chutes de adversário perto o bastante.
-- Retorna raio/impulso se ativo em QUALQUER slot (o maior raio ganha).
_G.GetPulseBlock = function(player)
	local e1, e2 = getActiveEffects(player)
	local bestRadius, bestImpulse = nil, nil
	for _, e in ipairs({ e1, e2 }) do
		if e and e.BlockRadius and (not bestRadius or e.BlockRadius > bestRadius) then
			bestRadius, bestImpulse = e.BlockRadius, e.BlockImpulse
		end
	end
	return bestRadius, bestImpulse
end

-- ⚠️ v120b — MURALHA INFINITA GIGANTE. PEDIDO: "a muralha tá muito pequena — o
-- tamanho base dela é pra ser literalmente gigante (gostei da aparência). E a
-- hitbox é bem maior do que ela: a hitbox precisa ser ELA — se bater nela, contou.
-- As pessoas podem passar no meio dela, a bola não." A barreira com `Muro` no
-- efeito deixa de ser uma esfera em volta de quem usa e vira a CAIXA do muro, na
-- frente dele (mesma conta do desenho em HissatsuVFXClient). Barreiras sem Muro
-- (outros Pulsos) continuam com o raio.
do -- (do...end: sem gastar locals do topo do script)
local function raizDe(player)
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function muroDe(player, e)
	local root = raizDe(player)
	if not root then return nil end
	local m = e.Muro
	local frente = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	frente = frente.Magnitude > 0.01 and frente.Unit or Vector3.new(0, 0, -1)
	-- companheiros perto (cresce com eles, igual ao desenho do muro)
	local aliados = 0
	for _, mate in ipairs(Players:GetPlayers()) do
		if mate ~= player and player.Team and mate.Team == player.Team then
			local r = raizDe(mate)
			if r and (r.Position - root.Position).Magnitude <= 45 then aliados += 1 end
		end
	end
	aliados = math.min(aliados, 2)
	local largura = (m.Largura or 40) + (m.PorAliado or 10) * aliados
	local altura = (m.Altura or 26) + (m.AlturaPorAliado or 3) * aliados
	local chao = root.Position.Y - 3
	local centro = Vector3.new(root.Position.X, chao + altura / 2, root.Position.Z) + frente * (m.Distancia or 8)
	return {
		CFrame = CFrame.lookAt(centro, centro + frente),
		Tamanho = Vector3.new(largura, altura, m.Espessura or 4),
	}
end
_G.MuroDaBarreira = function(player)
	local e1, e2 = getActiveEffects(player)
	for _, e in ipairs({ e1, e2 }) do
		if e and e.Muro and e.BlockRadius then return muroDe(player, e) end
	end
	return nil
end
-- pos está dentro da barreira de `player`? (folga = raio da bola)
_G.DentroDaBarreira = function(player, pos, folga)
	local raio = _G.GetPulseBlock(player)
	if not raio then return false end
	local muro = _G.MuroDaBarreira(player)
	if muro then
		local rel = muro.CFrame:PointToObjectSpace(pos)
		local f = folga or 0
		return math.abs(rel.X) <= muro.Tamanho.X / 2 + f and math.abs(rel.Y) <= muro.Tamanho.Y / 2 + f
			and math.abs(rel.Z) <= muro.Tamanho.Z / 2 + f
	end
	local root = raizDe(player)
	return root ~= nil and (root.Position - pos).Magnitude <= raio
end
end

-- Goleiro: bônus de mergulho vindo de um Pulso ATIVO (buff em duração —
-- Muralha/Muralha Impenetrável/Reflexo Absoluto). Soma os dois slots.
_G.GetPulseGKDiveBonus = function(player)
	local e1, e2 = getActiveEffects(player)
	local radiusAdd, guaranteed, minShotDistance = 0, false, nil
	for _, e in ipairs({ e1, e2 }) do
		if e and e.DiveRadiusAdd then
			radiusAdd += e.DiveRadiusAdd
			if e.GuaranteedCatch then guaranteed = true end
			if e.MinShotDistance then minShotDistance = e.MinShotDistance end
		end
	end
	return radiusAdd, guaranteed, minShotDistance
end

-- ===== BRILHO DE SKILL ATIVA (representação visual) =====
-- Enquanto um Pulso "Buff" está em duração, mostra um contorno colorido
-- por RARIDADE no personagem — mesma ideia do TeamHighlight (PlayerSystems
-- .lua) e do IframeGlow (BallController.lua), só que a cor muda por
-- raridade em vez de time, pra dar feedback visual de "minha skill tá
-- ativa" pra qualquer Pulso com duração (Arrancada, Explosão, Fenômeno,
-- General, Muro Final, Muralha do goleiro etc — sem precisar de nenhum
-- objeto novo no Studio).
local RARITY_GLOW_COLOR = {
	Common = Color3.fromRGB(220, 220, 220),
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(180, 70, 235),
	Legendary = Color3.fromRGB(255, 155, 30),
	Mythic = Color3.fromRGB(255, 60, 90),
}
local RARITY_RANK = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

-- ⚠️ v45 — PEDIDO: "não quero esses highlights padrão de ForceField, e de
-- mudar a cor do personagem." Este pintava o personagem inteiro na cor da
-- raridade (FillTransparency 0.55). Agora é uma aura de CONTORNO que
-- "respira" devagar na cor da raridade — presença contínua, sem apagar o
-- uniforme e sem competir com o estrobo do iframe (ver AbilityAura, que
-- tem a explicação completa dos ritmos).
local BUFF_AURA = "PulseBuffAura"

local function setBuffGlow(player, color)
	local character = player.Character
	if not character then return end
	if not color then
		AbilityAura.Clear(character, BUFF_AURA)
		return
	end
	AbilityAura.Apply(character, BUFF_AURA, "Buff", color)
end

RunService.Heartbeat:Connect(function()
	for _, player in ipairs(Players:GetPlayers()) do
		local buffs = ActiveBuff[player]
		if not buffs then continue end

		local bestRarity, bestRank = nil, 0
		for slot = 1, 2 do
			local buff = buffs[slot]
			if buff then
				if tick() >= buff.ExpiresAt then
					buffs[slot] = nil
				else
					local rank = buff.Rarity and RARITY_RANK[buff.Rarity] or 0
					if rank > bestRank then
						bestRank = rank
						bestRarity = buff.Rarity
					end
				end
			end
		end

		setBuffGlow(player, bestRarity and RARITY_GLOW_COLOR[bestRarity] or nil)
	end
end)

-- ⚠️ v110 (debugger): zera AGORA os cooldowns das Hissatsus (o = "Cooldown") ou
-- enche a energia (o = "Energia"), e avisa o HUD pra limpar a contagem.
_G.ZerarPulseDebug = function(player, o)
	ensurePlayerTables(player)
	if o == "Cooldown" then
		ReadyAt[player] = {}
		feedback(player, "CooldownsZerados")
	elseif o == "Energia" then
		EnergyPool[player] = maxEnergyPool(player)
		lastSentEnergy[player] = nil
		sendEnergyFeedback(player)
	end
end

Players.PlayerRemoving:Connect(function(player)
	Loadout[player] = nil
	ReadyAt[player] = nil
	ActiveBuff[player] = nil
	TeammateBuff[player] = nil
	DebugNoDelay[player] = nil
	DebugFlags[player] = nil
	TeamBuff[player] = nil
	Pending[player] = nil
	FrozenUntil[player] = nil
	GKGuard[player] = nil
	LastAimPoint[player] = nil
	EnergyPool[player] = nil
	lastSentEnergy[player] = nil
end)

print("✅ PulseController carregado (2 slots por jogador, modelo 'Pulso' v3 — combo de teclas + iframe de wind-up).")
