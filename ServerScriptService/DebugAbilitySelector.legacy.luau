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
		kind = "ZerarCooldowns" → (v110) zera agora os cooldowns das Hissatsus e da arma
		kind = "EnergiaInfinita" → (v110) value = true/false — energia das Hissatsus nunca baixa
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
				como = string.format("aperte E (arma no slot 1) — %s", def.Ativa or "ativa") -- ⚠️ v111: E = slot 1, R = slot 2
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
		-- ⚠️ v110 — PEDIDO: "coloca as opções de zerar o cooldown, que não estão
		-- funcionando mais... tirar todos os cooldowns das Hissatsus". Desde a v5.1
		-- isto só desligava o cooldown das ARMAS (Instinto) — as Hissatsus têm o
		-- cooldown delas no PulseController, que nunca era chamado. Agora liga os
		-- dois (e já zera o que estiver contando).
		local ligado = value == true
		if _G.SetInstinctDebugNoCooldown then _G.SetInstinctDebugNoCooldown(player, ligado) end
		if _G.SetPulseDebugFlag then _G.SetPulseDebugFlag(player, "SemCooldown", ligado) end
		if ligado then
			if _G.ZerarPulseDebug then _G.ZerarPulseDebug(player, "Cooldown") end
			if _G.ZerarInstinctCooldown then _G.ZerarInstinctCooldown(player) end
		end
		print(string.format("🛠 DebugAbilitySelector: %s sem cooldown (Hissatsu + Arma) = %s", player.Name, tostring(ligado)))

	elseif kind == "ZerarCooldowns" then
		-- ⚠️ v110: zera uma vez, agora (Hissatsus + arma)
		if _G.ZerarPulseDebug then _G.ZerarPulseDebug(player, "Cooldown") end
		if _G.ZerarInstinctCooldown then _G.ZerarInstinctCooldown(player) end
		print(string.format("🛠 DebugAbilitySelector: %s zerou os cooldowns", player.Name))

	elseif kind == "DarBola" or kind == "IrProGol" or kind == "IrProGolDoBot" then
		-- ⚠️ v110 (debugger): "Pegar a bola" dá a posse na hora; "Ir pro gol"
		-- ainda te coloca de frente pro gol adversário (a ~55 studs) — pra testar
		-- chute/Hissatsu sem atravessar o campo toda vez.
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if not root then return end
		if (kind == "IrProGol" and player.Team) or kind == "IrProGolDoBot" then
			local gol
			if kind == "IrProGolDoBot" then
				-- ⚠️ v110: testando sozinho, o goleiro bot fica no SEU gol (o do
				-- adversário fica vazio) — esse vai pro gol que tem bot, pra testar
				-- o duelo de defesa (vale gol contra, mas no teste não conta)
				-- prefere o bot do time ADVERSÁRIO (quando os dois times têm bot)
				local bot
				for _, m in ipairs(workspace:GetChildren()) do
					if m:IsA("Model") and m.Name:sub(1, 6) == "GKBot_" and m:FindFirstChild("HumanoidRootPart") then
						local doMeuTime = player.Team and m.Name:sub(7) == player.Team.Name
						if not bot or not doMeuTime then bot = m.HumanoidRootPart end
						if not doMeuTime then break end
					end
				end
				local melhor = math.huge
				for _, d in ipairs(workspace:GetDescendants()) do
					if bot and d:IsA("BasePart") and d:GetAttribute("ScoringTeam") then
						local dist = (d.Position - bot.Position).Magnitude
						if dist < melhor then melhor = dist; gol = d end
					end
				end
				if not bot then
					warn("⚠️ DebugAbilitySelector: não tem goleiro bot em campo agora.")
				else
					-- o bot só defende chute do time ADVERSÁRIO: passa você pro outro time
					local timeDoBot = bot.Parent.Name:sub(7)
					for _, t in ipairs(game:GetService("Teams"):GetTeams()) do
						if t.Name ~= timeDoBot and player.Team ~= t then
							player.Team = t
							-- trocar de time faz o GKBotController reorganizar os bots (e
							-- soltar a bola) — espera ele terminar antes de dar a bola
							task.wait(1.2)
							break
						end
					end
				end
			else
				for _, d in ipairs(workspace:GetDescendants()) do
					if d:IsA("BasePart") and d:GetAttribute("ScoringTeam") == player.Team.Name then gol = d break end
				end
			end
			if gol then
				local campo = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
				local centro = campo and (campo:IsA("BasePart") and campo.Position or campo:GetPivot().Position) or root.Position
				local paraDentro = Vector3.new(centro.X - gol.Position.X, 0, centro.Z - gol.Position.Z)
				paraDentro = paraDentro.Magnitude > 1 and paraDentro.Unit or Vector3.new(0, 0, 1)
				local ponto = Vector3.new(gol.Position.X, root.Position.Y, gol.Position.Z) + paraDentro * (tonumber(value) or 55)
				root.CFrame = CFrame.lookAt(ponto, Vector3.new(gol.Position.X, ponto.Y, gol.Position.Z))
				root.AssemblyLinearVelocity = Vector3.zero
			else
				warn("⚠️ DebugAbilitySelector: não achei o gol (" .. kind .. ").")
			end
		end
		task.wait(0.1)
		local bola = workspace:FindFirstChild(Config.BALL_NAME)
		if bola and _G.SetBallOwnerForced then
			if _G.ReleaseBallOwner then _G.ReleaseBallOwner() end
			bola.Anchored = false
			bola.AssemblyLinearVelocity = Vector3.zero
			bola.CFrame = root.CFrame * CFrame.new(0, -2, -2.5)
			_G.SetBallOwnerForced(player)
		end
		print(string.format("🛠 DebugAbilitySelector: %s %s", player.Name, kind == "DarBola" and "pegou a bola" or (kind == "IrProGolDoBot" and "foi pro gol do goleiro bot com a bola" or "foi pro gol com a bola")))

	elseif kind == "TrioSozinho" then
		-- ⚠️ v110: chutes de dupla/trio (Raio Um, Tornado do Dragão, Galáxia,
		-- Ruptura de Gaia, Zona Morta) sem companheiros — sombras no lugar deles
		if _G.SetPulseDebugFlag then _G.SetPulseDebugFlag(player, "TrioSozinho", value == true) end
		print(string.format("🛠 DebugAbilitySelector: %s chutes em grupo sozinho = %s", player.Name, tostring(value == true)))

	elseif kind == "EnergiaInfinita" then
		-- ⚠️ v110 — PEDIDO: "a opção de energia infinita pra eu conseguir sempre
		-- ficar utilizando" (o pool fica cheio e nunca baixa)
		if _G.SetPulseDebugFlag then _G.SetPulseDebugFlag(player, "Energia", value == true) end
		print(string.format("🛠 DebugAbilitySelector: %s energia infinita = %s", player.Name, tostring(value == true)))

	elseif kind == "Cosmetico" then
		-- ⚠️ v110: testar cosméticos/Flow no Studio (sem vir do Lobby).
		-- value = { Slot, Id } (Id nil = tira)
		if typeof(value) == "table" and typeof(value[1]) == "string" then
			local Cosmeticos = require(game:GetService("ReplicatedStorage"):WaitForChild("Cosmeticos"))
			local item = Cosmeticos.Item(value[2])
			if value[2] == nil or (item and item.Slot == value[1]) then
				player:SetAttribute("Cosm_" .. value[1], value[2])
			end
		end

	elseif kind == "EncherFlow" then
		-- ⚠️ v110: enche o medidor do Flow na hora (testar as cenas)
		if _G.AddInstinctCharge then _G.AddInstinctCharge(player, 100) end

	elseif kind == "TestarGol" then
		-- ⚠️ v110: comemoração + efeito de gol equipados, sem precisar marcar
		if _G.EfeitoDeGolCosmetico then _G.EfeitoDeGolCosmetico(player) end
		if _G.TocarComemoracaoCosmetica then _G.TocarComemoracaoCosmetica(player) end

	elseif kind == "TestarDefesa" then
		-- ⚠️ v110 — PEDIDO: "inclua tudo no jogo e coloque no debbuger pra eu
		-- testar". value = nome da técnica de goleiro (ex.: "Mão Divina"). Põe a
		-- bola parada na sua frente e toca a cutscene de defesa em VOCÊ, com a
		-- mesma duração do duelo de verdade (def.QTE.Duration). Não mexe em
		-- placar nem cooldown; no fim a bola cai na sua frente.
		local def = findPulse(value)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		local ball = workspace:FindFirstChild(Config.BALL_NAME)
		if not def or def.RoleRequired ~= "GK" or not root or not ball or not _G.TocarCutsceneDeDefesa then
			warn("⚠️ DebugAbilitySelector: não deu pra testar a defesa '" .. tostring(value) .. "' (técnica, personagem ou bola faltando)")
			return
		end
		if _G.HissatsuCutsceneActive then return end
		if _G.ResetBallState then _G.ResetBallState(root.Position + root.CFrame.LookVector * 9 + Vector3.new(0, 1.5, 0)) end
		local dur = (def.QTE and def.QTE.Duration) or 3.5
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.CFrame = CFrame.new(root.Position + root.CFrame.LookVector * 9 + Vector3.new(0, 1.5, 0))
		ball.Anchored = true
		if _G.TocarCutsceneDeDefesa(char, def, dur) then
			print(string.format("🛠 DebugAbilitySelector: %s testou a defesa '%s' (%.1fs)", player.Name, def.Name, dur))
		end
		task.delay(dur + 0.2, function()
			if ball.Parent then ball.Anchored = false end
		end)

	elseif kind == "TestarReplay" then
		-- ⚠️ v112: mostra o replay dos últimos segundos NA HORA (sem precisar de
		-- gol nem de 2 jogadores) — pra conferir Hissatsu/arma/animação no replay
		local snapshot = _G.GetReplaySnapshot and _G.GetReplaySnapshot()
		local eventos = _G.GetReplayEventos and _G.GetReplayEventos() or nil
		if snapshot and #snapshot > 1 then
			Remotes.GoalReplay:FireClient(player, player.Team and player.Team.Name or "", snapshot, eventos)
			print(string.format("🛠 DebugAbilitySelector: replay de teste (%d amostras, %d eventos)", #snapshot, eventos and #eventos or 0))
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