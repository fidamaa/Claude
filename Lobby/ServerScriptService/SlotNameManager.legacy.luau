--[[
	SlotNameManager - Gerenciador de Nomes de Personagens (CORRIGIDO)
	Coloque em ServerScriptService
	
	✅ Permite que jogadores alterem os nomes de seus personagens
	✅ Atualiza a nametag automaticamente em tempo real
	✅ Valida nomes e filtra palavras proibidas
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextService = game:GetService("TextService")
local eventsFolder = ReplicatedStorage:WaitForChild("LobbyEvents")

-- Criar RemoteFunction para atualizar nome
local updateSlotNameFunc = eventsFolder:FindFirstChild("UpdateSlotName")
if not updateSlotNameFunc then
	updateSlotNameFunc = Instance.new("RemoteFunction")
	updateSlotNameFunc.Name = "UpdateSlotName"
	updateSlotNameFunc.Parent = eventsFolder
end

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local MIN_NAME_LENGTH = 1
local MAX_NAME_LENGTH = 30

-- Lista expandida de palavras proibidas
local FORBIDDEN_WORDS = {
	-- Palavras administrativas
	"admin", "administrator", "roblox", "mod", "moderator", "builderman",
	-- Palavrões comuns (português)
	"idiota", "burro", "estupido", "imbecil", "otario", "otário",
	"merda", "puta", "porra", "caralho", "desgraça",
	-- Termos ofensivos
	"noob", "lixo", "trash", "garbage", "ruim",
	-- Termos racistas
	"nigger", "negro", "preto", "monkey", "macaco",
	-- Palavras relacionadas a hack/exploit
	"hack", "hacker", "exploit", "cheat", "script",
}

-- ========================================
-- Validar Nome
-- ========================================
local function validateName(name)
	-- Verificar se é string
	if type(name) ~= "string" then
		return false, "Nome deve ser texto"
	end

	-- Verificar comprimento
	if #name < MIN_NAME_LENGTH then
		return false, "Nome muito curto"
	end

	if #name > MAX_NAME_LENGTH then
		return false, "Nome muito longo (máximo 30 caracteres)"
	end

	-- Verificar se contém apenas espaços
	if name:match("^%s*$") then
		return false, "Nome não pode ser vazio"
	end

	-- Verificar palavras proibidas
	local lowerName = name:lower()
	for _, word in ipairs(FORBIDDEN_WORDS) do
		if lowerName:find(word) then
			return false, "Nome contém palavras proibidas"
		end
	end

	return true, "Nome válido"
end

-- ========================================
-- Atualizar Nome do Slot (CORRIGIDO)
-- ========================================
updateSlotNameFunc.OnServerInvoke = function(player, slotIndex, newName)
	print(string.format("📝 SlotNameManager: %s quer mudar nome do slot %d para '%s'", 
		player.Name, slotIndex, tostring(newName)))

	-- Validar índice do slot
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > 5 then
		warn(string.format("❌ Índice de slot inválido: %s", tostring(slotIndex)))
		return false, "Slot inválido"
	end

	-- Validar nome
	local isValid, errorMsg = validateName(newName)
	if not isValid then
		warn(string.format("❌ Nome inválido: %s", errorMsg))
		return false, errorMsg
	end

	-- ⚠️ v110: FILTRO OFICIAL DO ROBLOX. O nome do personagem agora aparece
	-- pra todo mundo (placa no Lobby, placa/chat/GOL na partida) — texto de
	-- jogador mostrado a outros PRECISA passar pelo TextService (regra da
	-- plataforma). Se o filtro esconder qualquer parte (vira ###), recusa.
	local okFiltro, filtrado = pcall(function()
		local resultado = TextService:FilterStringAsync(newName, player.UserId, Enum.TextFilterContext.PublicChat)
		return resultado:GetNonChatStringForBroadcastAsync()
	end)
	if not okFiltro then
		warn("❌ Filtro de texto indisponível: " .. tostring(filtrado))
		return false, "Não deu pra verificar o nome agora, tente de novo"
	end
	if filtrado ~= newName then
		return false, "Esse nome foi bloqueado pelo filtro do Roblox"
	end

	-- Verificar se PlayerDataManager está carregado
	if not _G.GetPlayerData then
		warn("❌ PlayerDataManager não carregado")
		return false, "Sistema de dados não disponível"
	end

	-- Obter dados do jogador
	local playerData = _G.GetPlayerData(player)
	if not playerData then
		warn(string.format("❌ Dados não encontrados para %s", player.Name))
		return false, "Dados não encontrados"
	end

	-- Verificar se o slot existe e está desbloqueado
	local slot = playerData.CharacterSlots[slotIndex]
	if not slot or slot == "Locked" then
		warn(string.format("❌ Slot %d está bloqueado ou inexistente", slotIndex))
		return false, "Slot bloqueado ou inexistente"
	end

	-- Salvar nome antigo para log
	local oldName = slot.SlotName

	-- Atualizar nome (trim espaços extras)
	local trimmedName = newName:match("^%s*(.-)%s*$")
	slot.SlotName = trimmedName

	-- Log de sucesso
	print(string.format("✅ Slot %d de %s renomeado: '%s' → '%s'", 
		slotIndex, player.Name, oldName, trimmedName))

	-- 🆕 SALVAR DADOS IMEDIATAMENTE
	if _G.SavePlayerData then
		task.spawn(function()
			_G.SavePlayerData(player)
		end)
	end

	-- 🆕 ATUALIZAR NAMETAG SE FOR O SLOT ATIVO
	if playerData.ActiveSlot == slotIndex then
		print(string.format("🏷️ Atualizando nametag para '%s' (slot ativo)", trimmedName))

		if _G.UpdatePlayerNametag then
			task.spawn(function()
				task.wait(0.1)  -- Pequeno delay para garantir sincronização
				local success = _G.UpdatePlayerNametag(player)
				if success then
					print(string.format("✅ Nametag atualizada com sucesso para '%s'", trimmedName))
				else
					warn("⚠️ Falha ao atualizar nametag")
				end
			end)
		else
			warn("⚠️ Função _G.UpdatePlayerNametag não encontrada!")
		end
	else
		print(string.format("⏭️ Slot %d não é o ativo (ativo: %d), nametag não atualizada", 
			slotIndex, playerData.ActiveSlot))
	end

	-- Retornar sucesso
	return true, {
		SlotIndex = slotIndex,
		NewName = trimmedName,
		OldName = oldName
	}
end

-- ========================================
-- Função de Debug (opcional)
-- ========================================
_G.TestNameUpdate = function(playerName, slotIndex, newName)
	local player = game.Players:FindFirstChild(playerName)
	if not player then
		print("❌ Jogador não encontrado:", playerName)
		return
	end

	local success, result = updateSlotNameFunc:InvokeServer(player, slotIndex, newName)
	print("Resultado:", success, result)
end

print(string.format("✅ SlotNameManager carregado (nomes de %d a %d caracteres)", MIN_NAME_LENGTH, MAX_NAME_LENGTH))