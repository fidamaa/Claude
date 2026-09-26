--[[
	SlotSyncServer - Gerenciador de Sincronização de Slots (COMPLETO)
	Coloque em ServerScriptService
	
	✅ Coordena comunicação entre RoleClient e AttributeDisplayClient
	✅ Atualiza nametag quando troca de slot visualizado
	✅ Sincroniza todos os sistemas em tempo real
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local eventsFolder = ReplicatedStorage:WaitForChild("LobbyEvents")

-- Criar evento se não existir
local onSlotChangedEvent = eventsFolder:FindFirstChild("OnSlotChanged")
if not onSlotChangedEvent then
	onSlotChangedEvent = Instance.new("RemoteEvent")
	onSlotChangedEvent.Name = "OnSlotChanged"
	onSlotChangedEvent.Parent = eventsFolder
end

-- ========================================
-- Gerenciar troca de slots com Atualização de Nametag
-- ========================================
onSlotChangedEvent.OnServerEvent:Connect(function(player, slotIndex)
	-- Validar entrada
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 5 then
		warn(string.format("❌ SlotSync: Índice de slot inválido %s de %s", tostring(slotIndex), player.Name))
		return
	end

	-- Verificar se o jogador tem dados
	if not _G.GetPlayerData then
		warn("❌ SlotSync: PlayerDataManager não carregado")
		return
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then
		warn(string.format("❌ SlotSync: Dados não encontrados para %s", player.Name))
		return
	end

	-- Verificar se o slot existe e está desbloqueado
	local slot = playerData.CharacterSlots[slotIndex]
	if not slot or slot == "Locked" then
		warn(string.format("❌ SlotSync: Slot %d está bloqueado ou inexistente para %s", slotIndex, player.Name))
		return
	end

	-- Log de sucesso
	print(string.format("🔄 SlotSync: %s trocou visualização para slot %d (%s)", 
		player.Name, slotIndex, slot.SlotName or "Unnamed"))

	-- Notificar o cliente (AttributeDisplayClient) sobre a troca
	onSlotChangedEvent:FireClient(player, slotIndex)

	-- 🆕 ATUALIZAR NAMETAG SE O SLOT ALTERADO SE TORNOU O ATIVO
	-- (Isso só acontece se o jogador clicar em "SetActiveButton" depois)
	-- Mas vamos verificar se o slot já é o ativo
	if playerData.ActiveSlot == slotIndex then
		print(string.format("🏷️ SlotSync: Slot %d já é o ativo, atualizando nametag...", slotIndex))

		if _G.UpdatePlayerNametag then
			task.spawn(function()
				task.wait(0.1)
				local success = _G.UpdatePlayerNametag(player)

				if success then
					print(string.format("✅ SlotSync: Nametag atualizada para '%s'", slot.SlotName))
				else
					warn("⚠️ SlotSync: Falha ao atualizar nametag")
				end
			end)
		else
			warn("⚠️ SlotSync: Função _G.UpdatePlayerNametag não encontrada!")
		end
	else
		print(string.format("⏭️ SlotSync: Slot %d não é o ativo (ativo: %d), nametag não atualizada", 
			slotIndex, playerData.ActiveSlot))
	end
end)

-- ========================================
-- Função de Debug
-- ========================================
_G.TestSlotSync = function(playerName, slotIndex)
	local player = game.Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	print(string.format("🧪 Testando sincronização: %s → Slot %d", playerName, slotIndex))
	onSlotChangedEvent:FireClient(player, slotIndex)
end

-- NOTA: este script só existe pra atender o evento OnSlotChanged, que
-- era disparado pelos antigos RoleClient/AttributeDisplayClient
-- (substituídos pelo CharacterClient.lua). Hoje ninguém mais dispara
-- esse evento, então isso aqui está tecnicamente morto — pode remover
-- este script com segurança se quiser limpar o projeto.
print("✅ SlotSyncServer carregado (legado — ver nota no topo do arquivo)")