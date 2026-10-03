--[[
	AdminPanelSuperTool - Ferramenta Completa de Administração e Testes
	
	COMANDOS DISPONÍVEIS:
	
	📊 SISTEMA DE XP E NÍVEIS:
	/addxp [jogador] [quantidade]  - Adiciona XP
	/setlevel [jogador] [nível]    - Define nível específico
	/levelup [jogador]             - Sobe 1 nível
	/givepoints [jogador] [qtd]    - Dá pontos de atributo
	
	⚡ SISTEMA DE ATRIBUTOS:
	/setattr [jogador] [atributo] [valor]  - Define valor de atributo
	/maxattrs [jogador]                     - Maximiza todos atributos
	/resetattrs [jogador]                   - Reseta atributos para base
	
	💰 SISTEMA DE DINHEIRO:
	/addmoney [jogador] [quantidade]  - Adiciona dinheiro
	/setmoney [jogador] [quantidade]  - Define dinheiro específico
	/givemoney [jogador] [quantidade] - Igual addmoney
	
	🔄 RESET E DADOS:
	/resetdata [jogador]     - Reseta dados do jogador
	/resetall                - Reseta TODOS online
	/saveall                 - Salva dados de todos
	/reloaddata [jogador]    - Recarrega dados do jogador
	
	👤 GESTÃO DE SLOTS:
	/unlockslot [jogador] [slot]  - Desbloqueia slot (4 ou 5)
	/setslot [jogador] [slot]     - Muda slot ativo
	
	ℹ️ INFORMAÇÕES:
	/playerinfo [jogador]  - Mostra todas as informações
	/listadmins            - Lista admins online
	/help                  - Mostra todos os comandos
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local ADMINS = {
	311895155,
	306920489-- ⚠️ ADICIONE SEU USERID AQUI
	-- Adicione mais admins:
	-- 123456789,
	-- 987654321,
}

local SUPER_ADMINS = {
	311895155  -- Apenas super admins podem usar comandos perigosos (resetall, etc)
}

local DATASTORE_NAME = "PlayerCharacterData_V4"
local COMMAND_PREFIX = "/"
local ENABLE_COMMAND_LOGGING = true  -- Log de todos os comandos usados
local ENABLE_NOTIFICATIONS = true    -- Notificações no chat

-- ========================================
-- Verificações de Permissão
-- ========================================
local function isAdmin(player)
	return table.find(ADMINS, player.UserId) ~= nil
end

local function isSuperAdmin(player)
	return table.find(SUPER_ADMINS, player.UserId) ~= nil
end

-- ========================================
-- Funções de Utilidade
-- ========================================
local function logCommand(admin, command, target)
	if not ENABLE_COMMAND_LOGGING then return end
	local timestamp = os.date("%H:%M:%S")
	local targetName = target and target.Name or "N/A"
	print(string.format("[%s] 🔧 ADMIN: %s | CMD: %s | TARGET: %s", 
		timestamp, admin.Name, command, targetName))
end

local function notify(player, message, isError)
	if not ENABLE_NOTIFICATIONS then return end

	local prefix = isError and "❌" or "✅"
	local fullMessage = string.format("%s [ADMIN] %s", prefix, message)

	-- Criar notificação visual (opcional)
	if player:FindFirstChild("PlayerGui") then
		task.spawn(function()
			-- Você pode criar uma GUI de notificação aqui
			print(string.format("Notificação para %s: %s", player.Name, fullMessage))
		end)
	end
end

local function findPlayer(partialName)
	partialName = string.lower(partialName)

	-- Verificar nome exato
	for _, player in ipairs(Players:GetPlayers()) do
		if string.lower(player.Name) == partialName then
			return player
		end
	end

	-- Verificar nome parcial
	for _, player in ipairs(Players:GetPlayers()) do
		if string.find(string.lower(player.Name), partialName, 1, true) then
			return player
		end
	end

	-- Verificar display name
	for _, player in ipairs(Players:GetPlayers()) do
		if string.find(string.lower(player.DisplayName), partialName, 1, true) then
			return player
		end
	end

	return nil
end

local function formatNumber(num)
	if num >= 1000000 then
		return string.format("%.1fM", num / 1000000)
	elseif num >= 1000 then
		return string.format("%.1fK", num / 1000)
	else
		return tostring(num)
	end
end

-- ========================================
-- COMANDOS DE XP E NÍVEIS
-- ========================================
local function cmdAddXP(admin, args)
	local targetName = args[1]
	local amount = tonumber(args[2])

	if not targetName or not amount then
		notify(admin, "Uso: /addxp [jogador] [quantidade]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	if not _G.AddPlayerXP then
		notify(admin, "Sistema de XP não disponível!", true)
		return
	end

	local success = _G.AddPlayerXP(target, amount)
	if success then
		logCommand(admin, "addxp", target)
		notify(admin, string.format("Adicionado %d XP para %s", amount, target.Name))
		notify(target, string.format("Você recebeu %d XP de um admin!", amount))
	else
		notify(admin, "Erro ao adicionar XP", true)
	end
end

local function cmdSetLevel(admin, args)
	local targetName = args[1]
	local level = tonumber(args[2])

	if not targetName or not level or level < 1 then
		notify(admin, "Uso: /setlevel [jogador] [nível]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	if not _G.GetPlayerData then
		notify(admin, "Sistema de dados não disponível!", true)
		return
	end

	local playerData = _G.GetPlayerData(target)
	if not playerData then
		notify(admin, "Dados não encontrados para " .. target.Name, true)
		return
	end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then
		notify(admin, "Slot ativo inválido", true)
		return
	end

	local oldLevel = activeSlot.Level or 1
	activeSlot.Level = level
	activeSlot.CurrentXP = 0

	logCommand(admin, "setlevel", target)
	notify(admin, string.format("Nível de %s alterado: %d → %d", target.Name, oldLevel, level))
	notify(target, string.format("Seu nível foi alterado para %d por um admin!", level))
end

local function cmdGivePoints(admin, args)
	local targetName = args[1]
	local points = tonumber(args[2]) or 3

	if not targetName then
		notify(admin, "Uso: /givepoints [jogador] [quantidade]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local playerData = _G.GetPlayerData(target)
	if not playerData then
		notify(admin, "Dados não encontrados", true)
		return
	end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then
		notify(admin, "Slot ativo inválido", true)
		return
	end

	activeSlot.AttributePoints = (activeSlot.AttributePoints or 0) + points

	logCommand(admin, "givepoints", target)
	notify(admin, string.format("Dado %d pontos de atributo para %s", points, target.Name))
	notify(target, string.format("Você recebeu %d pontos de atributo!", points))
end

-- ========================================
-- COMANDOS DE ATRIBUTOS
-- ========================================
local function cmdSetAttribute(admin, args)
	local targetName = args[1]
	local attrName = args[2]
	local value = tonumber(args[3])

	if not targetName or not attrName or not value then
		notify(admin, "Uso: /setattr [jogador] [atributo] [valor]", true)
		notify(admin, "Atributos: Kick, Stamina, Physical, Dribble, Aura", false)
		return
	end

	-- Normalizar nome do atributo
	attrName = attrName:sub(1,1):upper() .. attrName:sub(2):lower()

	local validAttrs = {"Kick", "Stamina", "Physical", "Dribble", "Aura"}
	if not table.find(validAttrs, attrName) then
		notify(admin, "Atributo inválido! Use: " .. table.concat(validAttrs, ", "), true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local playerData = _G.GetPlayerData(target)
	if not playerData then
		notify(admin, "Dados não encontrados", true)
		return
	end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then
		notify(admin, "Slot ativo inválido", true)
		return
	end

	local oldValue = activeSlot.Attributes[attrName]
	activeSlot.Attributes[attrName] = value

	logCommand(admin, "setattr", target)
	notify(admin, string.format("%s de %s: %d → %d", attrName, target.Name, oldValue, value))
	notify(target, string.format("Seu atributo %s foi alterado para %d!", attrName, value))
end

local function cmdMaxAttributes(admin, args)
	local targetName = args[1]

	if not targetName then
		notify(admin, "Uso: /maxattrs [jogador]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local playerData = _G.GetPlayerData(target)
	if not playerData then
		notify(admin, "Dados não encontrados", true)
		return
	end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
	if not activeSlot or activeSlot == "Locked" then
		notify(admin, "Slot ativo inválido", true)
		return
	end

	-- Maximizar todos os atributos
	for attr, _ in pairs(activeSlot.Attributes) do
		activeSlot.Attributes[attr] = 99
	end

	logCommand(admin, "maxattrs", target)
	notify(admin, string.format("Todos os atributos de %s foram maximizados!", target.Name))
	notify(target, "Seus atributos foram maximizados por um admin!")
end

-- ========================================
-- COMANDOS DE DINHEIRO
-- ========================================
local function cmdAddMoney(admin, args)
	local targetName = args[1]
	local amount = tonumber(args[2])

	if not targetName or not amount then
		notify(admin, "Uso: /addmoney [jogador] [quantidade]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local money = target:FindFirstChild("Money")
	if not money then
		notify(admin, "Sistema de dinheiro não encontrado", true)
		return
	end

	local oldAmount = money.Value
	money.Value = money.Value + amount

	logCommand(admin, "addmoney", target)
	notify(admin, string.format("Dinheiro de %s: %s → %s (+%s)", 
		target.Name, formatNumber(oldAmount), formatNumber(money.Value), formatNumber(amount)))
	notify(target, string.format("Você recebeu %s de dinheiro!", formatNumber(amount)))
end

local function cmdSetMoney(admin, args)
	local targetName = args[1]
	local amount = tonumber(args[2])

	if not targetName or not amount then
		notify(admin, "Uso: /setmoney [jogador] [quantidade]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local money = target:FindFirstChild("Money")
	if not money then
		notify(admin, "Sistema de dinheiro não encontrado", true)
		return
	end

	local oldAmount = money.Value
	money.Value = amount

	logCommand(admin, "setmoney", target)
	notify(admin, string.format("Dinheiro de %s definido: %s → %s", 
		target.Name, formatNumber(oldAmount), formatNumber(amount)))
	notify(target, string.format("Seu dinheiro foi definido para %s!", formatNumber(amount)))
end

-- ========================================
-- COMANDOS DE RESET E DADOS
-- ========================================
local function cmdResetData(admin, args)
	local targetName = args[1]

	if not targetName then
		notify(admin, "Uso: /resetdata [jogador]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

	local success, err = pcall(function()
		playerDataStore:RemoveAsync("User_" .. target.UserId)
	end)

	if success then
		logCommand(admin, "resetdata", target)
		notify(admin, string.format("Dados de %s foram resetados!", target.Name))

		task.wait(1)
		target:Kick("🔄 Seus dados foram resetados por um admin.\nEntre novamente para criar novos dados.")
	else
		notify(admin, "Erro ao resetar dados: " .. tostring(err), true)
	end
end

local function cmdResetAll(admin, args)
	if not isSuperAdmin(admin) then
		notify(admin, "Apenas Super Admins podem usar este comando!", true)
		return
	end

	local confirmation = args[1]
	if confirmation ~= "CONFIRM" then
		notify(admin, "⚠️ AVISO: Isto resetará TODOS os jogadores!", true)
		notify(admin, "Use: /resetall CONFIRM", true)
		return
	end

	logCommand(admin, "resetall", nil)

	local playersToReset = Players:GetPlayers()
	local count = #playersToReset

	for _, target in ipairs(playersToReset) do
		if target ~= admin then
			task.spawn(function()
				local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
				pcall(function()
					playerDataStore:RemoveAsync("User_" .. target.UserId)
				end)
				task.wait(0.5)
				target:Kick("🔄 Seus dados foram resetados em massa.\nEntre novamente.")
			end)
		end
	end

	notify(admin, string.format("Resetando dados de %d jogadores...", count - 1))
end

local function cmdSaveAll(admin, args)
	if not isSuperAdmin(admin) then
		notify(admin, "Apenas Super Admins podem usar este comando!", true)
		return
	end

	logCommand(admin, "saveall", nil)

	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		-- Assumindo que existe uma função global de save
		if _G.SavePlayerData then
			_G.SavePlayerData(player)
			count = count + 1
		end
	end

	notify(admin, string.format("Salvando dados de %d jogadores...", count))
end

-- ========================================
-- COMANDOS DE INFORMAÇÃO
-- ========================================
local function cmdPlayerInfo(admin, args)
	local targetName = args[1]

	if not targetName then
		notify(admin, "Uso: /playerinfo [jogador]", true)
		return
	end

	local target = findPlayer(targetName)
	if not target then
		notify(admin, "Jogador não encontrado: " .. targetName, true)
		return
	end

	local playerData = _G.GetPlayerData(target)
	if not playerData then
		notify(admin, "Dados não encontrados", true)
		return
	end

	local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print(string.format("📊 INFORMAÇÕES DE %s", target.Name))
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print(string.format("UserId: %d", target.UserId))
	print(string.format("DisplayName: %s", target.DisplayName))
	print(string.format("AccountAge: %d dias", target.AccountAge))

	if activeSlot and activeSlot ~= "Locked" then
		print("")
		print("🎮 PERSONAGEM ATIVO:")
		print(string.format("  Nome: %s", activeSlot.SlotName))
		print(string.format("  Role: %s", activeSlot.Role))
		print(string.format("  Nível: %d", activeSlot.Level or 1))
		print(string.format("  XP: %d", activeSlot.CurrentXP or 0))
		print(string.format("  Pontos de Atributo: %d", activeSlot.AttributePoints or 0))
		print("")
		print("⚡ ATRIBUTOS:")
		for attr, value in pairs(activeSlot.Attributes) do
			print(string.format("  %s: %d", attr, value))
		end
	end

	local money = target:FindFirstChild("Money")
	if money then
		print("")
		print(string.format("💰 Dinheiro: %s", formatNumber(money.Value)))
	end

	print("")
	print(string.format("📦 Slots Desbloqueados: %d/5", playerData.UnlockedSlots))
	print(string.format("🎯 Slot Ativo: %d", playerData.ActiveSlot))
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	notify(admin, string.format("Informações de %s mostradas no console (F9)", target.Name))
end

local function cmdHelp(admin, args)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("📋 COMANDOS ADMINISTRATIVOS DISPONÍVEIS")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("")
	print("📊 XP E NÍVEIS:")
	print("  /addxp [jogador] [qtd]")
	print("  /setlevel [jogador] [nível]")
	print("  /levelup [jogador]")
	print("  /givepoints [jogador] [qtd]")
	print("")
	print("⚡ ATRIBUTOS:")
	print("  /setattr [jogador] [atributo] [valor]")
	print("  /maxattrs [jogador]")
	print("")
	print("💰 DINHEIRO:")
	print("  /addmoney [jogador] [qtd]")
	print("  /setmoney [jogador] [qtd]")
	print("")
	print("🔄 DADOS:")
	print("  /resetdata [jogador]")
	print("  /resetall CONFIRM (⚠️ Super Admin)")
	print("  /saveall (⚠️ Super Admin)")
	print("  /cosmeticos [jogador] (⚠️ Super Admin) — libera todos os cosméticos e Flows")
	print("")
	print("ℹ️ INFORMAÇÕES:")
	print("  /playerinfo [jogador]")
	print("  /listadmins")
	print("  /help")
	print("")
	print("💡 Dica: Use nomes parciais (ex: /addxp jo 100)")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	notify(admin, "Lista de comandos mostrada no console (F9)")
end

local function cmdListAdmins(admin, args)
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("👥 ADMINS ONLINE")
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if isAdmin(player) then
			local superTag = isSuperAdmin(player) and " [SUPER]" or ""
			print(string.format("  • %s%s", player.Name, superTag))
			count = count + 1
		end
	end

	if count == 0 then
		print("  Nenhum admin online")
	end

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	notify(admin, string.format("%d admin(s) online", count))
end

-- ⚠️ v110 — /cosmeticos [jogador]: libera TODOS os cosméticos e Flows da Loja
-- (pra testar o Armário/Flow sem gastar dinheiro). Só Super Admin.
local function cmdCosmeticos(admin, args)
	if not isSuperAdmin(admin) then
		notify(admin, "Só Super Admin pode usar /cosmeticos", true)
		return
	end
	local target = args[1] and findPlayer(args[1]) or admin
	if not target then
		notify(admin, "Jogador não encontrado: " .. tostring(args[1]), true)
		return
	end
	local playerData = _G.GetPlayerData(target)
	if not playerData then
		notify(admin, "Dados não encontrados", true)
		return
	end
	local Cosmeticos = require(game:GetService("ReplicatedStorage"):WaitForChild("Cosmeticos"))
	local n = 0
	for _, cat in ipairs(Cosmeticos.CATEGORIAS) do
		for _, item in ipairs(Cosmeticos[cat]) do
			if not playerData.OwnedCosmetics[item.Id] then
				playerData.OwnedCosmetics[item.Id] = true
				n += 1
			end
		end
	end
	if _G.AplicarCosmeticosLobby then _G.AplicarCosmeticosLobby(target) end
	if _G.SavePlayerData then task.spawn(_G.SavePlayerData, target) end
	logCommand(admin, "cosmeticos", target)
	notify(admin, string.format("%d cosméticos/Flows liberados para %s", n, target.Name))
end

-- ========================================
-- PROCESSADOR DE COMANDOS
-- ========================================
local commands = {
	["cosmeticos"] = cmdCosmeticos, -- ⚠️ v110
	-- XP e Níveis
	["addxp"] = cmdAddXP,
	["setlevel"] = cmdSetLevel,
	["levelup"] = function(admin, args)
		args[2] = "1"  -- Forçar 1 level up
		cmdAddXP(admin, args)
	end,
	["givepoints"] = cmdGivePoints,

	-- Atributos
	["setattr"] = cmdSetAttribute,
	["setattribute"] = cmdSetAttribute,
	["maxattrs"] = cmdMaxAttributes,
	["maxattributes"] = cmdMaxAttributes,

	-- Dinheiro
	["addmoney"] = cmdAddMoney,
	["setmoney"] = cmdSetMoney,
	["givemoney"] = cmdAddMoney,

	-- Reset e Dados
	["resetdata"] = cmdResetData,
	["resetall"] = cmdResetAll,
	["saveall"] = cmdSaveAll,

	-- Informações
	["playerinfo"] = cmdPlayerInfo,
	["info"] = cmdPlayerInfo,
	["listadmins"] = cmdListAdmins,
	["admins"] = cmdListAdmins,
	["help"] = cmdHelp,
	["commands"] = cmdHelp,
}

local function processCommand(admin, message)
	if string.sub(message, 1, 1) ~= COMMAND_PREFIX then
		return
	end

	-- Remover prefix e dividir em partes
	local content = string.sub(message, 2)  -- Remove "/"
	local parts = {}

	for word in string.gmatch(content, "%S+") do
		table.insert(parts, word)
	end

	if #parts == 0 then return end

	local cmdName = string.lower(parts[1])
	table.remove(parts, 1)  -- Remove comando, deixa só args

	local cmdFunction = commands[cmdName]

	if cmdFunction then
		local success, err = pcall(cmdFunction, admin, parts)
		if not success then
			warn(string.format("❌ Erro ao executar comando: %s", tostring(err)))
			notify(admin, "Erro ao executar comando! Veja console.", true)
		end
	else
		notify(admin, "Comando desconhecido! Use /help", true)
	end
end

-- ========================================
-- CONECTAR EVENTOS
-- ========================================
Players.PlayerAdded:Connect(function(player)
	if isAdmin(player) then
		local tag = isSuperAdmin(player) and "SUPER ADMIN" or "ADMIN"
		print(string.format("🔧 %s %s conectado!", tag, player.Name))

		task.wait(2)
		notify(player, "Painel de Admin carregado! Use /help")
	end

	player.Chatted:Connect(function(message)
		if isAdmin(player) and string.sub(message, 1, 1) == COMMAND_PREFIX then
			processCommand(player, message)
		end
	end)
end)

-- ========================================
-- INICIALIZAÇÃO
-- ========================================
-- Contar comandos disponíveis
local function countCommands()
	local count = 0
	for _ in pairs(commands) do
		count = count + 1
	end
	return count
end

print(string.format("✅ AdminPanelSuperTool carregado (Admins: %d, Super Admins: %d, %d comandos, prefixo '%s' — use /help no chat)", #ADMINS, #SUPER_ADMINS, countCommands(), COMMAND_PREFIX))