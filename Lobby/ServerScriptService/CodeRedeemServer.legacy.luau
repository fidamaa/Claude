--[[
	CodeRedeemServer (ServerScriptService)

	REWORK: não tem mais DataStore próprio (era o 3º DataStore separado
	pro mesmo jogador — UsedCodes_V1). Os códigos já usados agora vivem
	em playerData.UsedCodes, dentro do mesmo payload único que o
	PlayerDataManager salva. Isso também mata o game:BindToClose que
	esse script tinha (salvava de novo, sozinho, com mais um task.wait
	fixo em cima do resto).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========================================
-- ⚠️ v3.4: REORGANIZADO (pedido: "10000 pontos é demais, deixe 5 códigos
-- só, e as pessoas precisam estar no grupo e ter dado like/favorite no
-- jogo").
--
-- 1) 8 códigos → 5, e o valor mais alto (MEGACODE, 10000) foi removido —
--    o maior agora é 1500, mais coerente com Config.SHOP/Config.REWARDS
--    do resto do jogo (um roll custa 200, um slot novo 750-6000 — 10000
--    de graça por digitar um código quebrava essa escala inteira).
-- 2) GRUPO: real, via Config.REDEEM_REQUIRE_GROUP + REDEEM_GROUP_ID
--    abaixo (player:IsInGroup, API de verdade do Roblox).
-- 3) "LIKE/FAVORITE": ⚠️ IMPORTANTE — o Roblox NÃO expõe nenhuma API pra
--    um jogo checar se um jogador deu like/favoritou a experiência (isso
--    existe só nas telas do próprio Roblox, sem endpoint disponível pra
--    scripts in-game). Não dá pra implementar essa parte de verdade sem
--    inventar uma checagem falsa — por isso ela NÃO está aplicada aqui.
--    Se quiser incentivar like/favorite mesmo assim, o caminho realista é
--    só o de sempre: um código anunciado especificamente pra quem
--    favoritar (na prática, confiança — sem checagem automática possível)
--    ou um prompt pedindo like na entrada, sem gating.
-- ========================================
local REDEEM_REQUIRE_GROUP = true
local REDEEM_GROUP_ID = 5182426 -- ⚠️ TROQUE pelo Id numérico do seu grupo no Roblox (Studio > cole aqui) — enquanto for 0, a exigência de grupo fica DESATIVADA (avisa no console) pra não travar todo mundo por engano.

local CODES = {
	["LANCAMENTO"] = {reward = 1000, type = "money"},
	["PURPLEWASHERE"] = {reward = 1000, type = "money"},
	["GREENGUY"] = {reward = 500, type = "money"},
	["PULSE"] = {reward = 750, type = "money"},
	["INSTINCT"] = {reward = 750, type = "money"},
}

-- true/false — exige estar no grupo configurado (se REDEEM_REQUIRE_GROUP
-- estiver ligado e REDEEM_GROUP_ID configurado de verdade).
local function meetsGroupRequirement(player)
	if not REDEEM_REQUIRE_GROUP or REDEEM_GROUP_ID == 0 then return true end
	local ok, isInGroup = pcall(function()
		return player:IsInGroup(REDEEM_GROUP_ID)
	end)
	if not ok then
		warn(("CodeRedeemServer: falha ao checar grupo de %s: %s"):format(player.Name, tostring(isInGroup)))
		return false -- falha de rede/API: nega por segurança em vez de deixar passar
	end
	return isInGroup
end

-- ========================================
-- Criar RemoteEvent
-- ========================================
local codeEvents = ReplicatedStorage:FindFirstChild("CodeEvents")
if not codeEvents then
	codeEvents = Instance.new("Folder")
	codeEvents.Name = "CodeEvents"
	codeEvents.Parent = ReplicatedStorage
end

local redeemCodeRemote = Instance.new("RemoteFunction")
redeemCodeRemote.Name = "RedeemCode"
redeemCodeRemote.Parent = codeEvents

-- ========================================
-- Função para Resgatar Código
-- ========================================
local function redeemCode(player, code)
	code = code:upper():gsub("%s+", "") -- Normalizar código

	local codeData = CODES[code]
	if not codeData then
		return false, "Código inválido!"
	end

	if not meetsGroupRequirement(player) then
		return false, "Você precisa estar no grupo do jogo pra resgatar códigos!"
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then
		return false, "Dados ainda não carregados, tente novamente em instantes."
	end

	if type(playerData.UsedCodes) ~= "table" then
		playerData.UsedCodes = {}
	end
	local usedCodes = playerData.UsedCodes

	if table.find(usedCodes, code) then
		return false, "Você já usou este código!"
	end

	if codeData.type == "money" then
		local success = _G.AddMoney and _G.AddMoney(player, codeData.reward)

		if not success then
			return false, "Erro ao adicionar dinheiro!"
		end

		table.insert(usedCodes, code)

		-- 1 salvamento só (dinheiro + código usado já estão no mesmo
		-- payload, ver PlayerDataManager.lua)
		task.spawn(function()
			if _G.SavePlayerData then
				_G.SavePlayerData(player)
			end
		end)

		print(string.format("🎁 %s resgatou código '%s': +$%d",
			player.Name, code, codeData.reward))

		return true, string.format("Código resgatado! +$%d", codeData.reward)
	end

	return false, "Tipo de recompensa desconhecido!"
end

-- ========================================
-- Conectar RemoteFunction
-- ========================================
redeemCodeRemote.OnServerInvoke = function(player, code)
	if not code or type(code) ~= "string" then
		return false, "Código inválido!"
	end

	if #code > 50 then
		return false, "Código muito longo!"
	end

	return redeemCode(player, code)
end

-- ========================================
-- Função Global para Adicionar Códigos
-- ========================================
_G.AddCode = function(codeName, reward, rewardType)
	codeName = codeName:upper()
	CODES[codeName] = {reward = reward, type = rewardType or "money"}
	print(string.format("✅ Código '%s' adicionado: %d %s", codeName, reward, rewardType or "money"))
end

_G.RemoveCode = function(codeName)
	codeName = codeName:upper()
	CODES[codeName] = nil
	print(string.format("🗑️ Código '%s' removido", codeName))
end

_G.ListCodes = function()
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("📋 CÓDIGOS DISPONÍVEIS:")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	for code, data in pairs(CODES) do
		print(string.format("   %s: +$%d (%s)", code, data.reward, data.type))
	end
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
end

print("✅ Sistema de Códigos (Servidor) carregado")
