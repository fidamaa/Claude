--[[
	DebugAbilitySelector (Script) — ⚠️ FERRAMENTA DE TESTE, TEMPORÁRIA
	LOCAL: ServerScriptService (place Game)

	Existe só pra você conseguir testar Pulso/Instinto/posição um por um
	direto no Studio, sem precisar ir até o Roll do Lobby toda vez.
	APAGUE esse script e o par dele (DebugAbilitySelectorHUD.local.lua em
	StarterPlayerScripts) quando não precisar mais — nenhum outro sistema
	depende deles, então remover os dois é seguro e não deixa nada quebrado
	pra trás (a Remote DebugConfigureTesting em FootballConfig.lua também
	pode ser removida, mas não precisa).

	⚠️ v5.1: os Pulsos foram desligados (PulseInstinctData.Pulses estava
	vazio), então as opções de Pulso tinham saído daqui.
	⚠️ v8: VOLTARAM — Data.Pulses tem 20 Pulsos "Hissatsu" de novo (ver
	PulseInstinctData.luau), então a opção "Pulse" reaparece aqui pra dar
	pra testar qualquer um deles (inclusive os 5 de drible novos) sem
	precisar passar pelo Roll do Lobby.

	Recebe Remotes.DebugConfigureTesting:FireServer(kind, value):
		kind = "Instinct" → value = nome do Instinto (ou nil pra remover)
		kind = "Pulse"    → value = nome do Pulso (equipa no slot 1 — o
		                    único slot que existe hoje, ver PulseController.
		                    legacy.luau/_G.SetPlayerLoadout)
		kind = "Role"     → value = "GK" | "DF" | "MF" | "FW"
		kind = "NoDelay"  → value = true/false — modo teste rápido: tira o
		                    COOLDOWN das ativas de Instinto (_G.SetInstinct-
		                    DebugNoCooldown), pra você poder apertar R várias
		                    vezes seguidas e ver a jogada acontecer sempre,
		                    em vez de esperar 6-10s entre uma e outra.
		kind = "RespawnBall" → value = true — reespawna a bola no centro do
		                    campo (útil pra quando ela buga/some). Usa
		                    _G.ResetBallState(centerPosition), exposto pelo
		                    BallController.legacy.lua — o MESMO caminho do
		                    gol/kickoff e do resgate da bola fugitiva (v67).
		                    Precisa que BallController.legacy.lua já tenha
		                    carregado (senão avisa e não faz nada).

	Sem validação de permissão (é ferramenta de dev, roda só no seu
	Studio) — mas SEMPRE confere se o nome existe em PulseInstinctData
	antes de aplicar, pra nunca equipar um Instinto inexistente.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local PulseData = require(ReplicatedStorage:WaitForChild("PulseInstinctData"))
local Remotes = Config.Remotes

local function instinctExists(name)
	if name == nil then return true end
	for _, def in ipairs(PulseData.Instincts) do
		if def.Name == name then return true end
	end
	return false
end

local function findPulse(name)
	if name == nil then return nil end
	for _, def in ipairs(PulseData.Pulses) do
		if def.Name == name then return def end
	end
	return nil
end

local VALID_ROLES = { GK = true, DF = true, MF = true, FW = true }

Remotes.DebugConfigureTesting.OnServerEvent:Connect(function(player, kind, value)
	if kind == "Instinct" then
		if not instinctExists(value) then
			warn(string.format("⚠️ DebugAbilitySelector: Instinto '%s' não existe em PulseInstinctData — ignorado.", tostring(value)))
			return
		end
		-- ⚠️ v76: _G.SetPlayerInstinct (singular) virou _G.SetPlayerInstincts
		-- (lista — Arma agora tem até 3 slots, ver InstinctController.
		-- legacy.luau). A ferramenta de debug testa 1 de cada vez, então
		-- manda uma lista de 1 item só.
		if _G.SetPlayerInstincts then
			_G.SetPlayerInstincts(player, { value })

			-- Ajuda a testar: diz no console COMO aquele instinto dispara,
			-- pra você não ficar apertando R num passivo achando que quebrou.
			local def
			for _, d in ipairs(PulseData.Instincts) do
				if d.Name == value then def = d break end
			end
			local como = "passivo (não tem tecla)"
			if def and def.Tecla then
				como = string.format("aperte %s — %s", def.Tecla, def.Ativa or "ativa")
			elseif def and def.AtivaAction then
				como = "automático quando a condição bate"
			end
			print(string.format("🛠 DebugAbilitySelector: %s equipou Instinto='%s' → %s", player.Name, tostring(value), como))
		end

	elseif kind == "Pulse" then
		local def = value ~= nil and findPulse(value) or nil
		if value ~= nil and not def then
			warn(string.format("⚠️ DebugAbilitySelector: Pulso '%s' não existe em PulseInstinctData — ignorado.", tostring(value)))
			return
		end
		if _G.SetPlayerLoadout then
			-- ⚠️ Só slot 1 — o único que existe hoje (ver v7, "só pode equipar
			-- 1 Pulso no momento").
			_G.SetPlayerLoadout(player, value, nil)
			local como = def and def.QTE and string.format("QTE %s", tostring(def.QTE.Kind)) or "sem QTE"
			print(string.format("🛠 DebugAbilitySelector: %s equipou Pulso='%s' (Action=%s, %s)", player.Name, tostring(value), def and tostring(def.Action) or "?", como))
		end

	elseif kind == "Role" then
		if not VALID_ROLES[value] then
			warn(string.format("⚠️ DebugAbilitySelector: Role '%s' inválido (use GK/DF/MF/FW) — ignorado.", tostring(value)))
			return
		end
		player:SetAttribute("Role", value)
		print(string.format("🛠 DebugAbilitySelector: %s virou Role=%s", player.Name, value))

	elseif kind == "NoDelay" then
		-- ⚠️ v5.1: agora tira o cooldown das ATIVAS DE INSTINTO (o de Pulso
		-- não existe mais). Mantido com o mesmo nome "NoDelay" pro HUD não
		-- precisar de outro remote.
		if _G.SetInstinctDebugNoCooldown then
			_G.SetInstinctDebugNoCooldown(player, value == true)
			print(string.format("🛠 DebugAbilitySelector: %s Sem cooldown de Instinto = %s", player.Name, tostring(value == true)))
		end

	elseif kind == "RespawnBall" then
		-- ⚠️ NOVO: bola tava bugando/sumindo. Usa _G.ResetBallState (exposto
		-- pelo BallController.legacy.lua) — é o MESMO caminho que o jogo já
		-- usa no gol/kickoff e no "resgate da bola fugitiva" (ver v67 lá):
		-- solta a posse, zera velocidade/ângular, reabilita colisão e
		-- reposiciona a bola. Acha o centro do campo do mesmo jeito que o
		-- BallController faz (pela hitbox Config.FIELD_HITBOX_NAME), então
		-- não precisa inventar nenhuma posição.
		if _G.ResetBallState then
			local campo = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
			if not campo then
				warn(string.format("⚠️ DebugAbilitySelector: não achei a hitbox do campo ('%s') — não deu pra saber o centro pra reespawnar a bola.", tostring(Config.FIELD_HITBOX_NAME)))
				return
			end
			local campoCentro = campo:IsA("BasePart") and campo.Position or campo:GetPivot().Position
			local spawnPos = campoCentro + Vector3.new(0, Config.BALL_RESCUE_SPAWN_HEIGHT, 0)
			_G.ResetBallState(spawnPos)
			print(string.format("🛠 DebugAbilitySelector: %s reespawnou a bola no centro do campo (%s).", player.Name, tostring(spawnPos)))
		else
			warn("⚠️ DebugAbilitySelector: _G.ResetBallState não existe — confere se o BallController.legacy.lua carregou antes desse script.")
		end
	end
end)

print("🛠 DebugAbilitySelector carregado (ferramenta de teste — apague quando terminar).")