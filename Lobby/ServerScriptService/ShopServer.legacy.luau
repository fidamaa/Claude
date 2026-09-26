--[[
	ShopServer - Loja do Lobby
	Coloque em ServerScriptService (place Lobby)

	v2 — Loja separada por categoria (Cosméticos / Conveniência / Boosts /
	Robux), pedido do usuário. Continua vendendo os 2 itens originais com
	lógica própria:
	- UnlockSlot: destrava o PRÓXIMO slot de personagem (em ordem, 2→3→4→5).
	  O jogador nasce com só 1 slot (ver PlayerDataManager.lua).
	- ResetSlot: reinicia um slot À ESCOLHA do jogador (sorteia Sorte/
	  atributos/posição de novo, nível volta pro 1, nome é preservado).

	E agora TAMBÉM vende o catálogo genérico (Config.SHOP.Items no
	LobbyConfig.lua) através de UM remote só (BuyCatalogItem) — cosméticos
	(compra única + equipar), consumíveis (pacote de roll, baú misterioso)
	e boosts temporários (XP/Dinheiro/Sorte/Missão Extra). Produtos de
	Robux (Config.SHOP.RobuxProducts) são registrados no dispatcher
	central — ver RobuxProducts.legacy.luau.

	MOVIDO: a compra de Roll (Pulso/Instinto) com DINHEIRO saiu da Loja —
	agora tem um botão dedicado dentro da própria tela de Roll (ver
	RollServer.lua/RollClient.lua). Este script não vende Roll com
	dinheiro (só os pacotes com desconto, RollPack_5/RollPack_10, que são
	itens do catálogo genérico).

	Depende de (todos definidos por PlayerDataManager.lua/MoneyManager.lua,
	que precisam carregar ANTES deste script):
	  _G.GetPlayerData(player)
	  _G.AddMoney(player, amount)
	  _G.RemoveMoney(player, amount)
	  _G.SavePlayerData(player)
	  _G.CreateRandomCharacterSlot(slotName)
	  _G.AddRollCredits(player, amount) -- RollServer.lua
	  _G.RegisterRobuxProduct(productId, handlerFn) -- RobuxProducts.lua
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LobbyConfig = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local SHOP = LobbyConfig.SHOP

-- ========================================
-- Remotes
-- ========================================
local eventsFolder = ReplicatedStorage:FindFirstChild("ShopEvents")
if not eventsFolder then
	eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "ShopEvents"
	eventsFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemoteFunction(name)
	local existing = eventsFolder:FindFirstChild(name)
	if existing then return existing end
	local remote = Instance.new("RemoteFunction")
	remote.Name = name
	remote.Parent = eventsFolder
	return remote
end

local getShopDataFunc = getOrCreateRemoteFunction("GetShopData")
local buyUnlockSlotFunc = getOrCreateRemoteFunction("BuyUnlockSlot")
local buyResetSlotFunc = getOrCreateRemoteFunction("BuyResetSlot")
local buyCatalogItemFunc = getOrCreateRemoteFunction("BuyCatalogItem")
local equipCosmeticFunc = getOrCreateRemoteFunction("EquipCosmetic")

-- NOTA: "BuyRoll" não existe mais aqui — o RemoteFunction de mesmo nome
-- agora vive em ReplicatedStorage.RollEvents (criado por RollServer.lua),
-- já que a compra de Roll com dinheiro saiu da Loja e foi pra dentro da
-- tela de Roll.

-- ========================================
-- Índice rápido do catálogo por Id
-- ========================================
local itemById = {}
for _, item in ipairs(SHOP.Items) do
	itemById[item.Id] = item
end

-- ========================================
-- Preço do próximo slot a destravar (nil se já tem os 5)
-- ========================================
local function nextUnlockCost(playerData)
	local nextIndex = playerData.UnlockedSlots + 1 -- índice do slot que SERIA destravado
	if nextIndex > 5 then return nil end
	local costIndex = playerData.UnlockedSlots -- Costs[1] destrava o slot 2 (quando UnlockedSlots==1), etc.
	return SHOP.UnlockSlot.Costs[costIndex]
end

-- ========================================
-- GetShopData: dados pra montar a loja inteira no cliente — os 2 itens
-- de sempre (preço dinâmico) + o catálogo por categoria (com Owned/
-- Equipped já resolvidos) + Boosts ativos + produtos de Robux.
-- ========================================
getShopDataFunc.OnServerInvoke = function(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return nil end

	local unlockCost = nextUnlockCost(playerData)

	local now = os.time()
	local resolvedItems = {}
	for _, item in ipairs(SHOP.Items) do
		table.insert(resolvedItems, {
			Id = item.Id,
			Category = item.Category,
			Slot = item.Slot,
			Name = item.Name,
			Cost = item.Cost,
			Type = item.Type,
			Owned = item.Type == "Cosmetic" and (playerData.OwnedCosmetics[item.Id] == true) or nil,
			Equipped = item.Slot and (playerData.EquippedCosmetics[item.Slot] == item.Id) or nil,
		})
	end

	local resolvedRobux = {}
	for _, product in ipairs(SHOP.RobuxProducts) do
		table.insert(resolvedRobux, {
			Id = product.Id,
			Name = product.Name,
			ProductId = product.ProductId,
			Configured = product.ProductId ~= 0,
		})
	end

	return {
		Money = _G.GetMoney and _G.GetMoney(player) or (playerData.Money or 0),
		UnlockSlot = {
			Id = SHOP.UnlockSlot.Id,
			Name = SHOP.UnlockSlot.Name,
			Cost = unlockCost, -- nil quando já tem os 5 slots
			MaxedOut = unlockCost == nil,
		},
		ResetSlot = {
			Id = SHOP.ResetSlot.Id,
			Name = SHOP.ResetSlot.Name,
			Cost = SHOP.ResetSlot.Cost,
		},
		Categories = SHOP.Categories,
		Items = resolvedItems,
		RobuxProducts = resolvedRobux,
		Boosts = {
			MoneyBoostActive = (playerData.Boosts.MoneyBoostExpiresAt or 0) > now,
			MoneyBoostExpiresAt = playerData.Boosts.MoneyBoostExpiresAt or 0,
			XPBoostActive = (playerData.Boosts.XPBoostExpiresAt or 0) > now,
			XPBoostExpiresAt = playerData.Boosts.XPBoostExpiresAt or 0,
			ExtraQuestActive = (playerData.Boosts.ExtraQuestExpiresAt or 0) > now,
			ExtraQuestExpiresAt = playerData.Boosts.ExtraQuestExpiresAt or 0,
			LuckRollsRemaining = playerData.Boosts.LuckRollsRemaining or 0,
		},
		-- Roll (com dinheiro) saiu daqui — ver nota no topo do arquivo.
	}
end

-- ========================================
-- BuyUnlockSlot: destrava o próximo slot em ordem
-- ========================================
buyUnlockSlotFunc.OnServerInvoke = function(player)
	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return false, "Dados não carregados" end

	if not _G.CreateRandomCharacterSlot or not _G.RemoveMoney then
		warn("❌ ShopServer: PlayerDataManager/MoneyManager não carregados")
		return false, "Loja indisponível no momento"
	end

	local cost = nextUnlockCost(playerData)
	if not cost then
		return false, "Todos os slots já estão destravados"
	end

	local nextIndex = playerData.UnlockedSlots + 1

	if not _G.RemoveMoney(player, cost) then
		return false, "Dinheiro insuficiente"
	end

	playerData.UnlockedSlots = nextIndex
	playerData.CharacterSlots[nextIndex] = _G.CreateRandomCharacterSlot("Personagem " .. nextIndex)

	task.spawn(function()
		_G.SavePlayerData(player)
	end)

	print(string.format("🛒 %s destravou o slot %d por $%d", player.Name, nextIndex, cost))

	return true, {
		UnlockedSlot = nextIndex,
		NextCost = nextUnlockCost(playerData), -- já reflete o novo UnlockedSlots
	}
end

-- ========================================
-- BuyResetSlot: reinicia um slot à escolha (sorte/atributos/posição de
-- novo, nível 1). Nome é preservado.
-- ========================================
buyResetSlotFunc.OnServerInvoke = function(player, slotIndex)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 5 then
		return false, "Slot inválido"
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return false, "Dados não carregados" end

	if not _G.CreateRandomCharacterSlot or not _G.RemoveMoney then
		warn("❌ ShopServer: PlayerDataManager/MoneyManager não carregados")
		return false, "Loja indisponível no momento"
	end

	local slot = playerData.CharacterSlots[slotIndex]
	if slotIndex > playerData.UnlockedSlots or not slot or slot == "Locked" then
		return false, "Slot bloqueado ou inválido"
	end

	local cost = SHOP.ResetSlot.Cost
	if not _G.RemoveMoney(player, cost) then
		return false, "Dinheiro insuficiente"
	end

	local preservedName = slot.SlotName
	local newSlot = _G.CreateRandomCharacterSlot(preservedName)
	playerData.CharacterSlots[slotIndex] = newSlot

	if playerData.ActiveSlot == slotIndex then
		player:SetAttribute("Role", newSlot.Role)
		-- ⚠️ FIX: resetar o slot ATIVO rerola o Speed dele também — sem
		-- isso o multiplicador de corrida no Lobby ficava travado no
		-- Speed de ANTES do reset até o jogador respawnar.
		if _G.RefreshLobbySpeedMultiplier then
			_G.RefreshLobbySpeedMultiplier(player)
		end
		if _G.UpdatePlayerNametag then
			task.spawn(function()
				task.wait(0.1)
				_G.UpdatePlayerNametag(player)
			end)
		end
	end

	task.spawn(function()
		_G.SavePlayerData(player)
	end)

	print(string.format("🛒 %s reiniciou o slot %d ('%s') por $%d", player.Name, slotIndex, preservedName, cost))

	return true, { SlotIndex = slotIndex }
end

-- ========================================
-- BuyCatalogItem: compra genérica pro catálogo (Cosmetic/Consumable/
-- Boost) — Type decide o efeito, ver comentário em Config.SHOP.Items.
-- ========================================
buyCatalogItemFunc.OnServerInvoke = function(player, itemId)
	if typeof(itemId) ~= "string" then
		return false, "Item inválido"
	end

	local item = itemById[itemId]
	if not item then
		return false, "Item não encontrado"
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return false, "Dados não carregados" end

	if not _G.RemoveMoney then
		warn("❌ ShopServer: MoneyManager não carregado")
		return false, "Loja indisponível no momento"
	end

	if item.Type == "Cosmetic" and playerData.OwnedCosmetics[item.Id] then
		return false, "Você já tem esse item"
	end

	if not _G.RemoveMoney(player, item.Cost) then
		return false, "Dinheiro insuficiente"
	end

	local rerolledElement = nil -- só preenchido quando item.Effect == "RerollElement", pra devolver na hora pro cliente

	if item.Type == "Cosmetic" then
		playerData.OwnedCosmetics[item.Id] = true
		-- Equipa automaticamente na compra (troca o que já estava naquele
		-- Slot, se houver) — o jogador pode trocar de novo depois via
		-- EquipCosmetic.
		if item.Slot then
			playerData.EquippedCosmetics[item.Slot] = item.Id
		end
	elseif item.Type == "Consumable" then
		if item.Effect == "RollPack" then
			if _G.AddRollCredits then
				_G.AddRollCredits(player, item.Amount or 0)
			end
		elseif item.Effect == "RerollElement" then
			-- PEDIDO: "pode ser mudado com um token de elemento que estará
			-- na loja, a partir da compra, ele já indica qual elemento você
			-- pegou" — re-rola o elemento do slot ATIVO (pode repetir o
			-- mesmo, igual um roll normal de Pulso/Instinto) e devolve o
			-- resultado na resposta da compra (ver ShopClient.local.luau).
			local activeSlot = playerData.CharacterSlots[playerData.ActiveSlot]
			if type(activeSlot) == "table" and activeSlot ~= "Locked" then
				-- Void/Luz raros (0.1% cada) — mesma função usada na
				-- criação do slot (PlayerDataManager.legacy.luau), pra
				-- não duplicar a lógica de raridade em dois lugares.
				activeSlot.Element = LobbyConfig.RollElement()
				rerolledElement = activeSlot.Element
			end
		elseif item.Effect == "MysteryBox" then
			-- Sorteia entre 3 tipos de recompensa — sempre concede algo,
			-- nunca "nada" (senão vira micro-transação de puro azar).
			local roll = math.random(1, 3)
			if roll == 1 then
				local amount = math.random(150, 500)
				if _G.AddMoney then _G.AddMoney(player, amount) end
			elseif roll == 2 then
				if _G.AddRollCredits then _G.AddRollCredits(player, math.random(1, 3)) end
			else
				-- Cosmético aleatório dentre os que o jogador AINDA não tem
				-- (de graça, sem custo — é o "prêmio bom" do baú).
				local candidates = {}
				for _, catalogItem in ipairs(SHOP.Items) do
					if catalogItem.Type == "Cosmetic" and not playerData.OwnedCosmetics[catalogItem.Id] then
						table.insert(candidates, catalogItem)
					end
				end
				if #candidates > 0 then
					local won = candidates[math.random(1, #candidates)]
					playerData.OwnedCosmetics[won.Id] = true
					if won.Slot then
						playerData.EquippedCosmetics[won.Slot] = won.Id
					end
				elseif _G.AddMoney then
					_G.AddMoney(player, 300) -- já tem todos os cosméticos: vira dinheiro
				end
			end
		end
	elseif item.Type == "Boost" then
		local now = os.time()
		if item.Effect == "XP" then
			playerData.Boosts.XPBoostExpiresAt = math.max(playerData.Boosts.XPBoostExpiresAt or 0, now) + item.DurationSeconds
		elseif item.Effect == "Money" then
			playerData.Boosts.MoneyBoostExpiresAt = math.max(playerData.Boosts.MoneyBoostExpiresAt or 0, now) + item.DurationSeconds
		elseif item.Effect == "Combo" then
			playerData.Boosts.XPBoostExpiresAt = math.max(playerData.Boosts.XPBoostExpiresAt or 0, now) + item.DurationSeconds
			playerData.Boosts.MoneyBoostExpiresAt = math.max(playerData.Boosts.MoneyBoostExpiresAt or 0, now) + item.DurationSeconds
		elseif item.Effect == "Luck" then
			playerData.Boosts.LuckRollsRemaining = (playerData.Boosts.LuckRollsRemaining or 0) + (item.Amount or 0)
		elseif item.Effect == "ExtraQuest" then
			playerData.Boosts.ExtraQuestExpiresAt = math.max(playerData.Boosts.ExtraQuestExpiresAt or 0, now) + item.DurationSeconds
		end
	end

	task.spawn(function()
		_G.SavePlayerData(player)
	end)

	print(string.format("🛒 %s comprou '%s' por $%d", player.Name, item.Name, item.Cost))

	return true, { ItemId = item.Id, Element = rerolledElement }
end

-- ========================================
-- EquipCosmetic: troca (ou desequipa, clicando de novo) um cosmético já
-- comprado. Um item equipado por Slot.
-- ========================================
equipCosmeticFunc.OnServerInvoke = function(player, itemId)
	if typeof(itemId) ~= "string" then
		return false, "Item inválido"
	end

	local item = itemById[itemId]
	if not item or item.Type ~= "Cosmetic" or not item.Slot then
		return false, "Item inválido"
	end

	local playerData = _G.GetPlayerData and _G.GetPlayerData(player)
	if not playerData then return false, "Dados não carregados" end

	if not playerData.OwnedCosmetics[itemId] then
		return false, "Você ainda não tem esse item"
	end

	if playerData.EquippedCosmetics[item.Slot] == itemId then
		playerData.EquippedCosmetics[item.Slot] = nil -- clicar de novo desequipa
	else
		playerData.EquippedCosmetics[item.Slot] = itemId
	end

	task.spawn(function()
		_G.SavePlayerData(player)
	end)

	return true, { Slot = item.Slot, Equipped = playerData.EquippedCosmetics[item.Slot] }
end

-- ========================================
-- Produtos de Robux do catálogo — registra no dispatcher central (ver
-- RobuxProducts.legacy.luau). Precisa esperar ele carregar, já que a
-- ordem entre Scripts de ServerScriptService não é garantida.
-- ========================================
task.spawn(function()
	local waited = 0
	while not _G.RegisterRobuxProduct and waited < 10 do
		task.wait(0.1)
		waited += 0.1
	end
	if not _G.RegisterRobuxProduct then
		warn("❌ ShopServer: RobuxProducts.legacy.luau não carregou a tempo — produtos de Robux da Loja desativados.")
		return
	end

	for _, product in ipairs(SHOP.RobuxProducts) do
		_G.RegisterRobuxProduct(product.ProductId, function(buyer, receiptInfo)
			local buyerData = _G.GetPlayerData and _G.GetPlayerData(buyer)
			if not buyerData then return false end

			if product.GrantMoney and _G.AddMoney then
				_G.AddMoney(buyer, product.GrantMoney)
			end
			if product.GrantUnlockAllSlots then
				for i = buyerData.UnlockedSlots + 1, 5 do
					buyerData.CharacterSlots[i] = _G.CreateRandomCharacterSlot("Personagem " .. i)
				end
				buyerData.UnlockedSlots = 5
			end

			task.spawn(function()
				_G.SavePlayerData(buyer)
			end)

			print(string.format("💎 %s comprou '%s' com Robux (Developer Product %d)", buyer.Name, product.Name, receiptInfo.ProductId))
			return true
		end)
	end
end)

print(string.format("✅ ShopServer carregado (Destravar: %s | Reiniciar: $%d | Catálogo: %d itens | Robux: %d produtos)", table.concat(SHOP.UnlockSlot.Costs, ", "), SHOP.ResetSlot.Cost, #SHOP.Items, #SHOP.RobuxProducts))
