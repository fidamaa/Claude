--[[
	PlayerNametagSystem - Sistema Completo com Atualização Automática
	Script no ServerScriptService
	
	✅ Exibe nome do personagem acima da cabeça
	✅ Substitui nickname padrão do Roblox
	✅ Atualiza automaticamente quando o nome é alterado
	✅ Atualiza ao trocar de slot ativo
	✅ Função global para atualização manual
]]

local Players = game:GetService("Players")
local TextService = game:GetService("TextService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos")) -- ⚠️ v110

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
local NAMETAG_HEIGHT_OFFSET = 3
local NAMETAG_SIZE = UDim2.new(0, 200, 0, 50)
local TEXT_SIZE = 18
local TEXT_COLOR = Color3.fromRGB(255, 255, 255)
local BACKGROUND_COLOR = Color3.fromRGB(0, 0, 0)
local BACKGROUND_TRANSPARENCY = 0.5
local TEXT_STROKE_COLOR = Color3.fromRGB(0, 0, 0)
local TEXT_STROKE_TRANSPARENCY = 0

-- ========================================
-- Lista de Palavras Proibidas (Filtro Básico)
-- ========================================
local FORBIDDEN_PATTERNS = {
	"idiota", "burro", "estupido", "imbecil", "nigger", "black", "monkey",
	"filho da puta", "desgraçado", "merda", "prostituta", "puta",
	"noob", "lixo", "trash", "admin", "moderator", "roblox", "builderman",
}

-- ========================================
-- Função para Filtrar Nome
-- ========================================
local function filterName(name)
	local lowerName = name:lower()

	for _, pattern in ipairs(FORBIDDEN_PATTERNS) do
		if lowerName:find(pattern) then
			name = string.rep("*", #name)
			return name, true
		end
	end

	return name, false
end

-- ========================================
-- Remover Nametag Padrão do Roblox
-- ========================================
local function removeDefaultNametag(character)
	local head = character:WaitForChild("Head", 5)
	if head then
		for _, child in ipairs(head:GetChildren()) do
			if child:IsA("BillboardGui") and child.Name ~= "CharacterNametag" then
				child:Destroy()
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end
end

-- ========================================
-- Criar BillboardGui com Nome
-- ========================================
local function createNametag(character, playerName, characterName)
	-- Remover nametags antigas
	for _, child in ipairs(character:GetDescendants()) do
		if child:IsA("BillboardGui") and (child.Name == "CharacterNametag" or child.Name == "NametagGui") then
			child:Destroy()
		end
	end

	local head = character:FindFirstChild("Head")
	if not head then
		warn("❌ Head não encontrada para " .. playerName)
		return
	end

	removeDefaultNametag(character)

	local filteredName, wasCensored = filterName(characterName)
	-- ⚠️ v110: e o filtro OFICIAL do Roblox (nomes antigos, de antes do filtro
	-- no SlotNameManager, também passam por ele antes de aparecer pros outros)
	local dono = Players:GetPlayerFromCharacter(character)
	if dono and not wasCensored then
		local ok, oficial = pcall(function()
			return TextService:FilterStringAsync(filteredName, dono.UserId, Enum.TextFilterContext.PublicChat):GetNonChatStringForBroadcastAsync()
		end)
		if ok and typeof(oficial) == "string" then
			filteredName = oficial
		elseif not ok then
			filteredName = dono.DisplayName -- sem filtro, não mostra texto livre
		end
	end

	if wasCensored then
		warn(string.format("⚠️ Nome impróprio detectado para %s: '%s' → '%s'", 
			playerName, characterName, filteredName))
	end

	-- ⚠️ v110 — COSMÉTICOS NA PLACA. PEDIDO: "moldura... título... cor..."
	-- A placa agora é montada pelo módulo Cosmeticos (a MESMA do place Game):
	-- nome do slot + título + tag + cor do nome + moldura equipados (atributos
	-- "Cosm_*" do jogador, ver ShopServer). O nome continua filtrado aqui.
	local dono = Players:GetPlayerFromCharacter(character)
	local billboard
	if dono then
		dono:SetAttribute("NomePersonagem", filteredName)
		billboard = Cosmeticos.MontarPlaca(Cosmeticos.DadosDaPlaca(dono, filteredName, nil))
	else
		billboard = Cosmeticos.MontarPlaca({ Nome = filteredName })
	end
	billboard.Name = "CharacterNametag"
	billboard.Adornee = head
	billboard.MaxDistance = 100
	billboard.Parent = character

	print(string.format("✅ Nametag criado para %s: '%s'", playerName, filteredName))

	return billboard
end

-- ========================================
-- FUNÇÃO GLOBAL PARA ATUALIZAR NAMETAG
-- Pode ser chamada de qualquer lugar: _G.UpdatePlayerNametag(player)
-- ========================================
_G.UpdatePlayerNametag = function(player)
	local character = player.Character
	if not character then
		warn("⚠️ Character não encontrado para " .. player.Name)
		return false
	end

	if not _G.GetPlayerData then
		warn("❌ PlayerDataManager não carregado - usando nome padrão")
		createNametag(character, player.Name, "Personagem")
		return false
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then
		warn("⚠️ Dados não encontrados para " .. player.Name)
		createNametag(character, player.Name, "Personagem")
		return false
	end

	local activeSlot = playerData.ActiveSlot or 1
	local slotData = playerData.CharacterSlots[activeSlot]

	local characterName = "Personagem"

	if slotData and slotData ~= "Locked" then
		characterName = slotData.SlotName or "Personagem"
	end

	createNametag(character, player.Name, characterName)

	print(string.format("🔄 Nametag atualizada para %s: '%s'", player.Name, characterName))

	return true
end

-- ========================================
-- Setup para Character
-- ========================================
local function setupCharacter(character)
	local player = Players:GetPlayerFromCharacter(character)
	if not player then return end

	local head = character:WaitForChild("Head", 10)
	if not head then
		warn("❌ Head não carregou para " .. player.Name)
		return
	end

	removeDefaultNametag(character)

	task.wait(0.5)

	_G.UpdatePlayerNametag(player)
end

-- ========================================
-- Evento quando jogador entra
-- ========================================
Players.PlayerAdded:Connect(function(player)
	-- Desabilitar nametag padrão
	player.NameDisplayDistance = 0
	player.HealthDisplayDistance = 0

	player.CharacterAdded:Connect(function(character)
		setupCharacter(character)
	end)

	if player.Character then
		setupCharacter(player.Character)
	end
end)

-- NOTA (removido): este script tentava "envolver" os callbacks de
-- SetActiveSlot/UpdateSlotName lendo `remote.OnServerInvoke` pra
-- guardar o callback original — isso não é permitido no Roblox
-- (OnServerInvoke só pode ser ESCRITO, nunca lido; ler gera o erro
-- "OnServerInvoke is a callback member of RemoteFunction; you can only
-- set the callback value, get is not available" a cada boot do
-- servidor). Também era redundante: PlayerDataManager.lua
-- (SetActiveSlot) e SlotNameManager.lua (UpdateSlotName) já chamam
-- _G.UpdatePlayerNametag(player) diretamente eles mesmos depois de
-- trocar slot/nome — não precisa de nenhum hook aqui.

-- ========================================
-- Inicializar jogadores já presentes
-- ========================================
for _, player in ipairs(Players:GetPlayers()) do
	-- Desabilitar nametag padrão
	player.NameDisplayDistance = 0
	player.HealthDisplayDistance = 0

	task.spawn(function()
		if player.Character then
			setupCharacter(player.Character)
		end

		player.CharacterAdded:Connect(function(character)
			setupCharacter(character)
		end)
	end)
end

-- ========================================
-- Comando de Debug (console)
-- ========================================
_G.UpdateAllNametags = function()
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		if _G.UpdatePlayerNametag(player) then
			count = count + 1
		end
	end
	print(string.format("✅ %d nametags atualizadas", count))
end

print("✅ PlayerNametagSystem carregado")