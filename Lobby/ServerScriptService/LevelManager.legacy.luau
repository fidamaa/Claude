--[[
	LevelManager - Sistema de Níveis e XP
	ATUALIZADO: Suporte a múltiplos slots independentes
	Coloque em ServerScriptService
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ========================================
-- CONFIGURAÇÕES
-- ========================================
-- REWORK do sistema de rolagem de atributos: subiu de 3 pra 4 pontos por
-- nível pra fechar a conta pedida ("dá pra upar 100% de 3 status no
-- melhor dos casos") depois que a faixa de rolagem inicial diminuiu pra
-- 10-40 (ver SKILL_MIN/MAX_BASE_STAT em PlayerDataManager.lua).
-- PEDIDO: 100 é o máximo de qualquer atributo, então agora são 3
-- pontos/nível (era 4) — com ATTRIBUTE_CAP=100 mais abaixo: pool máximo
-- = 3*49 = 147 pontos.
local ATTRIBUTE_POINTS_PER_LEVEL = 3

-- Nível máximo do jogo — usado também pela conta de pool de pontos no
-- PlayerDataManager.lua (comentário acima de CharacterCreator.new: pool
-- total = ATTRIBUTE_POINTS_PER_LEVEL * (MAX_LEVEL-1)). Se mudar qualquer
-- um desses valores aqui, atualize o comentário duplicado lá também.
local MAX_LEVEL = 50

-- REWORK: a curva de XP era EXPONENCIAL (XP_BASE * 1.5^(nível-2)) — no
-- nível 39 isso já pedia mais de 90 MILHÕES de XP pro nível 40, uma
-- progressão inutilizável depois de poucas dezenas de níveis (dobra e
-- meia a cada nível, sem teto). Trocada por crescimento LINEAR: cada
-- nível pede sempre XP_GROWTH_PER_LEVEL a mais que o anterior —
-- previsível, e nunca "explode".
local XP_BASE = 100          -- XP pra sair do nível 1 pro 2
local XP_GROWTH_PER_LEVEL = 40 -- cada nível seguinte pede mais 40 de XP que o anterior

-- ========================================
-- Criar Eventos de Comunicação
-- ========================================
local eventsFolder = ReplicatedStorage:WaitForChild("LobbyEvents")

local getLevelDataFunc = Instance.new("RemoteFunction")
getLevelDataFunc.Name = "GetLevelData"
getLevelDataFunc.Parent = eventsFolder

local addAttributePointFunc = Instance.new("RemoteFunction")
addAttributePointFunc.Name = "AddAttributePoint"
addAttributePointFunc.Parent = eventsFolder

local updateLevelDataEvent = Instance.new("RemoteEvent")
updateLevelDataEvent.Name = "UpdateLevelData"
updateLevelDataEvent.Parent = eventsFolder

-- 🆕 Novo evento para notificar troca de slot
local onSlotChangedEvent = Instance.new("RemoteEvent")
onSlotChangedEvent.Name = "OnSlotChanged"
onSlotChangedEvent.Parent = eventsFolder

-- ========================================
-- Calcular XP necessário para próximo nível
-- ========================================
local function calculateXPForLevel(level)
	if level <= 1 then return 0 end
	return XP_BASE + XP_GROWTH_PER_LEVEL * (level - 2)
end

-- ========================================
-- Inicializar dados de nível para novos personagens
-- ========================================
local function initializeLevelData(characterSlot)
	if not characterSlot.Level then
		characterSlot.Level = 1
		characterSlot.CurrentXP = 0
		characterSlot.AttributePoints = 0
	end
end

-- ========================================
-- 🆕 Obter slot específico do jogador
-- ========================================
local function getCharacterSlot(player, slotIndex)
	if not _G.GetPlayerData then
		warn("❌ PlayerDataManager não carregado!")
		return nil
	end

	local playerData = _G.GetPlayerData(player)
	if not playerData then return nil end

	-- Se slotIndex não foi fornecido, usar o slot ativo
	local targetSlot = slotIndex or playerData.ActiveSlot

	local slot = playerData.CharacterSlots[targetSlot]
	if not slot or slot == "Locked" then return nil end

	initializeLevelData(slot)
	return slot, targetSlot
end

-- ========================================
-- Adicionar XP e verificar Level Up
-- ========================================
local function addXP(player, amount, targetSlotIndex)
	local activeSlot, slotIndex = getCharacterSlot(player, targetSlotIndex)
	if not activeSlot then return false end

	activeSlot.CurrentXP = activeSlot.CurrentXP + amount

	local leveledUp = false
	while activeSlot.Level < MAX_LEVEL do
		local xpNeeded = calculateXPForLevel(activeSlot.Level + 1)

		if activeSlot.CurrentXP >= xpNeeded then
			activeSlot.CurrentXP = activeSlot.CurrentXP - xpNeeded
			activeSlot.Level = activeSlot.Level + 1
			activeSlot.AttributePoints = activeSlot.AttributePoints + ATTRIBUTE_POINTS_PER_LEVEL
			leveledUp = true

			print(string.format("🎉 %s (Slot %d) subiu para nível %d! +%d pontos de atributo",
				player.Name, slotIndex, activeSlot.Level, ATTRIBUTE_POINTS_PER_LEVEL))
		else
			break
		end
	end

	-- No nível máximo, não deixa CurrentXP acumular pra sempre à toa —
	-- trava em 0 (a UI mostra "NÍVEL MÁXIMO" em vez de barra de XP).
	if activeSlot.Level >= MAX_LEVEL then
		activeSlot.CurrentXP = 0
	end

	-- Notificar cliente
	updateLevelDataEvent:FireClient(player, {
		Level = activeSlot.Level,
		CurrentXP = activeSlot.CurrentXP,
		XPNeeded = calculateXPForLevel(activeSlot.Level + 1),
		AttributePoints = activeSlot.AttributePoints,
		IsMaxLevel = activeSlot.Level >= MAX_LEVEL,
		LeveledUp = leveledUp,
		SlotIndex = slotIndex  -- 🆕 Incluir o slot que foi atualizado
	})

	-- MELHORIA DE SAVE: XP/Level nunca disparava salvamento nenhum aqui
	-- antes — só o autosave periódico ou sair do jogo gravavam isso de
	-- verdade. Ganhar XP numa partida e o server cair/reiniciar antes do
	-- próximo autosave perdia esse progresso. Agora agenda um save
	-- (debounced) toda vez que XP muda.
	if _G.RequestSave then
		_G.RequestSave(player)
	end

	return true
end

-- ========================================
-- 🆕 GetLevelData - Retorna dados de nível de um slot específico
-- ========================================
getLevelDataFunc.OnServerInvoke = function(player, slotIndex)
	local activeSlot, actualSlotIndex = getCharacterSlot(player, slotIndex)
	if not activeSlot then return nil end

	return {
		Level = activeSlot.Level,
		CurrentXP = activeSlot.CurrentXP,
		XPNeeded = calculateXPForLevel(activeSlot.Level + 1),
		AttributePoints = activeSlot.AttributePoints,
		Attributes = activeSlot.Attributes,
		SkillPoints = activeSlot.SkillPoints,
		IsMaxLevel = activeSlot.Level >= MAX_LEVEL,
		SlotIndex = actualSlotIndex,
		Element = activeSlot.Element, -- ⚠️ NOVO: elemento do slot (ver Config.ELEMENTS)
	}
end

-- ========================================
-- 🆕 AddAttributePoint - Adiciona ponto em atributo de um slot específico
-- ========================================
addAttributePointFunc.OnServerInvoke = function(player, attributeName, slotIndex)
	print(string.format("📥 AddAttributePoint chamado por %s - Atributo: %s, Slot: %s", 
		player.Name, attributeName, tostring(slotIndex)))

	-- Validar atributo (nomes alinhados com o que o jogo de futebol lê de
	-- verdade — ver FootballConfig.lua no place Game). Aura/BallControl/
	-- CrossingSkill foram removidos: Speed e Kick entraram no lugar dos
	-- dois últimos.
	local validAttributes = {"Physical", "DribbleSkill", "Speed", "Kick", "Energy", "Technique", "Stamina"} -- ⚠️ NOVO: Energy (Pulsos) · Technique (7º atributo)
	if not table.find(validAttributes, attributeName) then
		warn(string.format("❌ Atributo inválido: %s", attributeName))
		return false, "Atributo inválido"
	end

	-- 🆕 Obter o slot correto
	local activeSlot, actualSlotIndex = getCharacterSlot(player, slotIndex)
	if not activeSlot then
		return false, "Slot inválido"
	end

	-- Verificar se tem pontos disponíveis
	if activeSlot.AttributePoints <= 0 then
		return false, "Sem pontos de atributo disponíveis"
	end

	-- Atributos de skill (Physical/DribbleSkill/Speed/Kick) têm teto 100
	-- — sem isso dava pra clicar "+" pra sempre, o que não bate com o
	-- sistema de Sorte (a conta de "dá pra maxar 2 ou 4 atributos" só
	-- funciona se maxar de verdade tiver um teto). Stamina é multiplicador
	-- de MaxStamina, escala diferente, então usa um teto PRÓPRIO abaixo.
	local ATTRIBUTE_CAP = 100
	if attributeName ~= "Stamina" and activeSlot.Attributes[attributeName] >= ATTRIBUTE_CAP then
		return false, "Atributo já está no máximo"
	end

	-- ⚠️ NOVO (fix "fôlego sem teto"): Stamina não tinha NENHUM teto de
	-- investimento — um jogador dedicado podia jogar o pool inteiro de
	-- pontos (196 no nível máximo) só nele, virando um fôlego quase 40x
	-- maior que o de nascimento. Pedido explícito: "no nível máximo, no
	-- máximo vai triplicar, ou quadruplicar o fôlego inicial". Fix: teto
	-- por personagem = StaminaBase (valor de nascimento, salvo em
	-- PlayerDataManager.lua) * 4 — QUADRUPLICA, nunca mais. Fallback de 15
	-- (POOL_MAX_BASE_STAT de lá) só pra dados salvos sem StaminaBase que
	-- por algum motivo não passaram pela migração ainda.
	if attributeName == "Stamina" then
		local staminaBase = activeSlot.Attributes.StaminaBase or 15
		local staminaCap = staminaBase * 4
		if activeSlot.Attributes.Stamina >= staminaCap then
			return false, "Atributo já está no máximo"
		end
	end

	-- Adicionar ponto
	activeSlot.Attributes[attributeName] = activeSlot.Attributes[attributeName] + 1
	activeSlot.AttributePoints = activeSlot.AttributePoints - 1

	print(string.format("✅ %s adicionou 1 ponto em %s (Slot %d) - Total: %d, Restantes: %d", 
		player.Name, attributeName, actualSlotIndex, 
		activeSlot.Attributes[attributeName], activeSlot.AttributePoints))

	-- Atualizar stamina máxima se for o personagem ativo E for Stamina
	if attributeName == "Stamina" then
		local playerData = _G.GetPlayerData(player)
		if playerData and actualSlotIndex == playerData.ActiveSlot then
			local maxStaminaValue = player:FindFirstChild("MaxStamina")
			if maxStaminaValue then
				local BASE_STAMINA = 50
				local STAMINA_PER_POINT = 10
				maxStaminaValue.Value = BASE_STAMINA + (activeSlot.Attributes.Stamina * STAMINA_PER_POINT)
				print(string.format("⚡ MaxStamina atualizada para %d", maxStaminaValue.Value))
			end
		end
	end

	-- ⚠️ FIX (pedido: Speed no Lobby "só conta os atributos iniciais",
	-- precisa contar os atualizados) — se o jogador acabou de gastar
	-- ponto em Speed do personagem ATIVO, StaminaManager.legacy.luau
	-- precisa recalcular o multiplicador de WalkSpeed AGORA, sem esperar
	-- ele respawnar (troca de atributo não troca de Character).
	if attributeName == "Speed" then
		local playerData = _G.GetPlayerData(player)
		if playerData and actualSlotIndex == playerData.ActiveSlot and _G.RefreshLobbySpeedMultiplier then
			_G.RefreshLobbySpeedMultiplier(player)
		end
	end

	-- 🔥 ENVIAR ATUALIZAÇÃO COMPLETA PARA O CLIENTE
	updateLevelDataEvent:FireClient(player, {
		Level = activeSlot.Level,
		CurrentXP = activeSlot.CurrentXP,
		XPNeeded = calculateXPForLevel(activeSlot.Level + 1),
		AttributePoints = activeSlot.AttributePoints,
		Attributes = activeSlot.Attributes,
		UpdatedAttribute = attributeName,
		LeveledUp = false,
		SlotIndex = actualSlotIndex  -- 🆕 Incluir o slot que foi atualizado
	})

	-- MELHORIA DE SAVE: gastar ponto de atributo também nunca salvava na
	-- hora — mesma lógica do XP acima.
	if _G.RequestSave then
		_G.RequestSave(player)
	end

	-- Retornar dados atualizados
	return true, {
		AttributePoints = activeSlot.AttributePoints,
		Attributes = activeSlot.Attributes,
		SlotIndex = actualSlotIndex
	}
end

-- ========================================
-- Função Global para adicionar XP
-- ========================================
_G.AddPlayerXP = function(player, amount, targetSlotIndex)
	return addXP(player, amount or 10, targetSlotIndex)
end

-- ========================================
-- Inicializar jogadores existentes
-- ========================================
Players.PlayerAdded:Connect(function(player)
	-- FIX: WaitForChild só espera a INSTANCE existir (criada bem antes do
	-- carregamento terminar) — sem o Changed:Wait() abaixo, essa checagem
	-- sempre perdia a corrida e o "return" disparava sempre, então isso
	-- nunca inicializava os slots (Hissatsus/SkillPoints) de ninguém.
	local dataLoaded = player:WaitForChild("DataLoaded", 10)
	if dataLoaded and not dataLoaded.Value then
		dataLoaded.Changed:Wait()
	end
	if not dataLoaded or not dataLoaded.Value then
		warn(string.format("⚠️ Dados não carregados para %s no LevelManager", player.Name))
		return
	end

	if _G.GetPlayerData then
		local playerData = _G.GetPlayerData(player)
		if playerData then
			-- 🆕 Inicializar todos os slots desbloqueados
			for i = 1, playerData.UnlockedSlots do
				local slot = playerData.CharacterSlots[i]
				if slot and slot ~= "Locked" then
					initializeLevelData(slot)
					print(string.format("✅ Slot %d inicializado para %s (Nível %d)", 
						i, player.Name, slot.Level))
				end
			end
		end
	end
end)

print(string.format("✅ LevelManager carregado (XP base %d, +%d/nível, %d pontos/nível, máx nível %d)", XP_BASE, XP_GROWTH_PER_LEVEL, ATTRIBUTE_POINTS_PER_LEVEL, MAX_LEVEL))