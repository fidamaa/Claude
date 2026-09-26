--[[
	ShopClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	v2 — REESCRITO 100% SCRIPTADO (Instance.new), igual CodeRedeemClient/
	QuestClient. A versão anterior dependia de uma GUI "Shop" MONTADA À
	MÃO no Studio — como só SCRIPT sincroniza pelo bridge, essa versão não
	depende de NADA feito no Studio.

	Abas por categoria: Cosméticos / Conveniência / Boosts / Robux — ver
	Config.SHOP.Categories/Items/RobuxProducts no LobbyConfig.lua.

	⚠️ v74 — PALETA v72/73 (a mesma do MatchmakingClient/RollClient/
	MissionTrackerHUD) + ROLL DE ROBUX INCLUÍDA.
	PEDIDO: "atualize a loja pro mesmo estilo da hud de roll, e inclua a
	roll de robux".

	O que mudou:
	1) Fundo cinza médio (25,25,32) → quase-preto (13,15,22), cantos
	   discretos, tipografia condensada em caixa alta nos títulos — mesma
	   linguagem das outras três telas.
	2) Título tinha emoji "🛒" — virou barrinha de acento, igual ao padrão
	   estabelecido no MatchmakingClient/MissionTrackerHUD/RollClient.
	   Emoji nos status de Boost ("💰⭐🗒️🍀") e no aviso de produto não
	   configurado ("⚠️") também saíram — texto puro, cor fazendo o
	   trabalho que o emoji tentava fazer.
	3) NOVO: card "Roll de Robux" na aba Robux. Antes o roll pago com
	   Robux só existia DENTRO da tela de Roll (botão helpRobux) — de
	   propósito não duplicado aqui (ver nota antiga em LobbyConfig.lua),
	   pra não ter duas rotas de compra divergentes. Mantive esse
	   princípio: o card daqui não chama PromptProductPurchase direto,
	   ele ABRE a tela de Roll (fecha a Loja, chama _G.OpenRoll) — a
	   compra em si continua acontecendo num único lugar.

	Expõe as mesmas 3 funções globais de sempre (contrato inalterado):
		_G.OpenShop()
		_G.CloseShop()
		_G.ToggleShop()

	Remotes usados:
	- ReplicatedStorage.ShopEvents.GetShopData     (RemoteFunction)
	- ReplicatedStorage.ShopEvents.BuyUnlockSlot   (RemoteFunction)
	- ReplicatedStorage.ShopEvents.BuyResetSlot    (RemoteFunction)
	- ReplicatedStorage.ShopEvents.BuyCatalogItem  (RemoteFunction)
	- ReplicatedStorage.ShopEvents.EquipCosmetic   (RemoteFunction)
	- ReplicatedStorage.LobbyEvents.GetSlotsOverview (RemoteFunction)
	- MarketplaceService:PromptProductPurchase — produtos de Robux
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local MarketplaceService = game:GetService("MarketplaceService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local shopEvents = ReplicatedStorage:WaitForChild("ShopEvents", 10)
if not shopEvents then
	warn("ShopClient: ShopEvents não encontrado em ReplicatedStorage.")
	return
end

local GetShopData = shopEvents:WaitForChild("GetShopData", 10)
local BuyUnlockSlot = shopEvents:WaitForChild("BuyUnlockSlot", 10)
local BuyResetSlot = shopEvents:WaitForChild("BuyResetSlot", 10)
local BuyCatalogItem = shopEvents:WaitForChild("BuyCatalogItem", 10)
local EquipCosmetic = shopEvents:WaitForChild("EquipCosmetic", 10)

local lobbyEvents = ReplicatedStorage:WaitForChild("LobbyEvents", 10)
local GetSlotsOverview = lobbyEvents and lobbyEvents:WaitForChild("GetSlotsOverview", 10)

if not (GetShopData and BuyUnlockSlot and BuyResetSlot and BuyCatalogItem and EquipCosmetic) then
	warn("ShopClient: remotes de loja não encontrados (ShopEvents incompleto).")
	return
end

local function notify(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Loja",
			Text = text,
			Duration = 4,
		})
	end)
end

-- ===== PALETA (mesma do MatchmakingClient/RollClient/MissionTrackerHUD) =====
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)
local COR_CARTAO_OK   = Color3.fromRGB(20, 34, 26)
local COR_BORDA       = Color3.fromRGB(34, 38, 52)
local COR_ACENTO      = Color3.fromRGB(76, 156, 255)
local COR_OK          = Color3.fromRGB(64, 196, 122)
local COR_OURO        = Color3.fromRGB(230, 185, 90)
local COR_PERIGO      = Color3.fromRGB(224, 76, 76)
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)

local function cantos(inst, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, raio)
	c.Parent = inst
	return c
end

local function contorno(inst, cor, espessura, transparencia)
	local s = Instance.new("UIStroke")
	s.Color = cor
	s.Thickness = espessura or 1
	s.Transparency = transparencia or 0.2
	s.Parent = inst
	return s
end

-- ==========================================================
-- Construção do GUI
-- ==========================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ShopGUI_Provisorio"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Enabled = false
screenGui.Parent = playerGui

local backdrop = Instance.new("TextButton")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.new(1, 0, 1, 0)
backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
backdrop.BackgroundTransparency = 0.4
backdrop.BorderSizePixel = 0
backdrop.Text = ""
backdrop.AutoButtonColor = false
backdrop.ZIndex = 9
backdrop.Parent = screenGui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 560, 0, 480)
panel.Position = UDim2.new(0.5, -280, 0.5, -240)
panel.BackgroundColor3 = COR_PAINEL
panel.BorderSizePixel = 0
panel.ZIndex = 10
panel.Parent = screenGui
cantos(panel, 10)
contorno(panel, COR_BORDA, 1, 0.15)

local escala = Instance.new("UIScale")
escala.Parent = panel
local function ajustarEscala()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local v = camera.ViewportSize
	if v.X <= 0 or v.Y <= 0 then return end
	escala.Scale = math.min(1, (v.X - 32) / 560, (v.Y - 32) / 480)
end

local barrinha = Instance.new("Frame")
barrinha.Size = UDim2.fromOffset(3, 20)
barrinha.Position = UDim2.new(0, 18, 0, 20)
barrinha.BackgroundColor3 = COR_ACENTO
barrinha.BorderSizePixel = 0
barrinha.ZIndex = 10
barrinha.Parent = panel
cantos(barrinha, 2)

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -170, 0, 24)
title.Position = UDim2.new(0, 30, 0, 16)
title.BackgroundTransparency = 1
title.Text = "LOJA"
title.TextColor3 = COR_TEXTO
title.Font = Enum.Font.GothamBlack
title.TextSize = 20
title.TextXAlignment = Enum.TextXAlignment.Left
title.ZIndex = 10
title.Parent = panel

local moneyLabel = Instance.new("TextLabel")
moneyLabel.Size = UDim2.new(0, 120, 0, 34)
moneyLabel.Position = UDim2.new(1, -164, 0, 10)
moneyLabel.BackgroundTransparency = 1
moneyLabel.Text = "$ --"
moneyLabel.TextColor3 = COR_OURO
moneyLabel.Font = Enum.Font.GothamBlack
moneyLabel.TextSize = 18
moneyLabel.TextXAlignment = Enum.TextXAlignment.Right
moneyLabel.ZIndex = 10
moneyLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Size = UDim2.new(0, 32, 0, 32)
closeButton.Position = UDim2.new(1, -44, 0, 10)
closeButton.BackgroundColor3 = COR_CARTAO_ALT
closeButton.BorderSizePixel = 0
closeButton.Text = "X"
closeButton.TextColor3 = COR_TEXTO
closeButton.Font = Enum.Font.GothamBold
closeButton.TextSize = 16
closeButton.ZIndex = 10
closeButton.Parent = panel
cantos(closeButton, 16)

-- ===== ABAS =====
local tabRow = Instance.new("Frame")
tabRow.Size = UDim2.new(1, -32, 0, 34)
tabRow.Position = UDim2.new(0, 16, 0, 54)
tabRow.BackgroundTransparency = 1
tabRow.ZIndex = 10
tabRow.Parent = panel

local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
tabLayout.Parent = tabRow

-- ===== ÁREA DE CONTEÚDO (rolável) =====
local contentFrame = Instance.new("ScrollingFrame")
contentFrame.Size = UDim2.new(1, -32, 1, -100)
contentFrame.Position = UDim2.new(0, 16, 0, 96)
contentFrame.BackgroundTransparency = 1
contentFrame.BorderSizePixel = 0
contentFrame.ScrollBarThickness = 4
contentFrame.ScrollBarImageColor3 = COR_TEXTO_FRACO
contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
contentFrame.ZIndex = 10
contentFrame.Parent = panel

local contentLayout = Instance.new("UIListLayout")
contentLayout.SortOrder = Enum.SortOrder.LayoutOrder
contentLayout.Padding = UDim.new(0, 8)
contentLayout.Parent = contentFrame

-- ==========================================================
-- Estado
-- ==========================================================
local shopData = nil
local currentCategory = "Cosmeticos"
local tabButtons = {}
local isBusy = false

local function setShopVisible(open)
	screenGui.Enabled = open
	if open then ajustarEscala() end
end

-- Botão de ação padrão dos cards (mesmo desenho em todo lugar).
local function makeActionButton(row)
	local actionButton = Instance.new("TextButton")
	actionButton.Size = UDim2.new(0, 120, 0, 36)
	actionButton.Position = UDim2.new(1, -132, 0.5, -18)
	actionButton.BorderSizePixel = 0
	actionButton.Font = Enum.Font.GothamBlack
	actionButton.TextSize = 13
	actionButton.TextColor3 = Color3.new(1, 1, 1)
	actionButton.AutoButtonColor = false
	actionButton.ZIndex = 10
	actionButton.Parent = row
	cantos(actionButton, 8)
	return actionButton
end

local function hoverBrighten(botao, corBase)
	botao.MouseEnter:Connect(function()
		botao.BackgroundColor3 = corBase:Lerp(Color3.new(1, 1, 1), 0.12)
	end)
	botao.MouseLeave:Connect(function()
		botao.BackgroundColor3 = corBase
	end)
end

-- ==========================================================
-- Card genérico de item (usado pro catálogo inteiro)
-- ==========================================================
local function buildCatalogCard(item, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 58)
	row.BackgroundColor3 = item.Equipped and COR_CARTAO_OK or COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 10
	row.Parent = contentFrame
	cantos(row, 8)
	if item.Equipped then contorno(row, COR_OK, 1, 0.3) end

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = item.Name
	nameLabel.TextColor3 = COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 10
	nameLabel.Parent = row

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -140, 0, 16)
	subLabel.Position = UDim2.new(0, 12, 0, 32)
	subLabel.BackgroundTransparency = 1
	subLabel.TextColor3 = COR_TEXTO_FRACO
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.ZIndex = 10
	subLabel.Parent = row
	if item.Type == "Cosmetic" then
		subLabel.Text = item.Owned and (item.Equipped and "equipado" or "você tem — clique pra equipar") or "cosmético"
	elseif item.Type == "Boost" then
		subLabel.Text = "boost temporário"
	else
		subLabel.Text = "consumível"
	end

	local actionButton = makeActionButton(row)

	if item.Type == "Cosmetic" and item.Owned then
		actionButton.Text = item.Equipped and "DESEQUIPAR" or "EQUIPAR"
		local cor = item.Equipped and COR_CARTAO_ALT or COR_ACENTO
		actionButton.BackgroundColor3 = cor
		hoverBrighten(actionButton, cor)
		actionButton.MouseButton1Click:Connect(function()
			if isBusy then return end
			isBusy = true
			local ok, success, result = pcall(function()
				return EquipCosmetic:InvokeServer(item.Id)
			end)
			isBusy = false
			if ok and success then
				refreshShopData()
			else
				notify(tostring(result or success))
			end
		end)
	else
		actionButton.Text = "$" .. tostring(item.Cost)
		actionButton.BackgroundColor3 = COR_OK
		hoverBrighten(actionButton, COR_OK)
		actionButton.MouseButton1Click:Connect(function()
			if isBusy then return end
			isBusy = true
			actionButton.Text = "..."
			local ok, success, result = pcall(function()
				return BuyCatalogItem:InvokeServer(item.Id)
			end)
			isBusy = false
			if ok and success then
				if typeof(result) == "table" and result.Element then
					notify(string.format("Elemento sorteado: %s!", result.Element))
				else
					notify("Comprado: " .. item.Name)
				end
				refreshShopData()
			else
				actionButton.Text = "$" .. tostring(item.Cost)
				notify(tostring(result or success))
			end
		end)
	end

	return row
end

-- ==========================================================
-- Card especial: Destravar Slot / Reiniciar Personagem
-- ==========================================================
local pickerGui, pickerList

local function buildResetPicker()
	pickerGui = Instance.new("ScreenGui")
	pickerGui.Name = "ResetSlotPicker"
	pickerGui.ResetOnSpawn = false
	pickerGui.DisplayOrder = 50
	pickerGui.Enabled = false
	pickerGui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromOffset(340, 380)
	frame.Position = UDim2.new(0.5, 0, 0.5, 0)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = COR_PAINEL
	frame.Parent = pickerGui
	cantos(frame, 10)
	contorno(frame, COR_OURO, 1, 0.2)

	local pickerTitle = Instance.new("TextLabel")
	pickerTitle.Size = UDim2.new(1, -20, 0, 34)
	pickerTitle.Position = UDim2.new(0, 14, 0, 10)
	pickerTitle.BackgroundTransparency = 1
	pickerTitle.Text = "ESCOLHA QUEM REINICIAR"
	pickerTitle.TextColor3 = COR_TEXTO
	pickerTitle.Font = Enum.Font.GothamBlack
	pickerTitle.TextSize = 15
	pickerTitle.TextXAlignment = Enum.TextXAlignment.Left
	pickerTitle.Parent = frame

	local pickerCloseButton = Instance.new("TextButton")
	pickerCloseButton.Size = UDim2.fromOffset(28, 28)
	pickerCloseButton.Position = UDim2.new(1, -38, 0, 10)
	pickerCloseButton.BackgroundColor3 = COR_CARTAO_ALT
	pickerCloseButton.Text = "X"
	pickerCloseButton.TextColor3 = COR_TEXTO
	pickerCloseButton.Font = Enum.Font.GothamBold
	pickerCloseButton.Parent = frame
	cantos(pickerCloseButton, 8)
	pickerCloseButton.MouseButton1Click:Connect(function()
		pickerGui.Enabled = false
	end)

	pickerList = Instance.new("Frame")
	pickerList.Size = UDim2.new(1, -20, 1, -110)
	pickerList.Position = UDim2.new(0, 10, 0, 50)
	pickerList.BackgroundTransparency = 1
	pickerList.Parent = frame
	local pickerListLayout = Instance.new("UIListLayout")
	pickerListLayout.Padding = UDim.new(0, 8)
	pickerListLayout.Parent = pickerList

	local pickerWarning = Instance.new("TextLabel")
	pickerWarning.Size = UDim2.new(1, -20, 0, 40)
	pickerWarning.Position = UDim2.new(0, 10, 1, -56)
	pickerWarning.BackgroundTransparency = 1
	pickerWarning.Text = "Isso reinicia atributos, nível e posição do personagem escolhido."
	pickerWarning.TextWrapped = true
	pickerWarning.TextColor3 = COR_PERIGO
	pickerWarning.Font = Enum.Font.GothamMedium
	pickerWarning.TextSize = 12
	pickerWarning.Parent = frame
end
buildResetPicker()

local function openResetPicker()
	if not GetSlotsOverview then
		notify("Seletor de personagem indisponível no momento.")
		return
	end

	for _, child in ipairs(pickerList:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local ok, overview = pcall(function()
		return GetSlotsOverview:InvokeServer()
	end)
	if not ok or not overview then
		warn("ShopClient: falha ao buscar GetSlotsOverview: " .. tostring(overview))
		return
	end

	local anySlot = false
	for index = 1, 5 do
		local info = overview.Slots[index]
		if info and not info.Locked then
			anySlot = true
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, 0, 0, 44)
			row.BackgroundColor3 = COR_CARTAO
			row.AutoButtonColor = false
			row.Text = string.format("%s — Nv. %d %s", info.SlotName, info.Level, info.IsActive and "(ativo)" or "")
			row.TextColor3 = COR_TEXTO
			row.Font = Enum.Font.GothamBold
			row.TextSize = 13
			row.LayoutOrder = index
			row.Parent = pickerList
			cantos(row, 8)
			hoverBrighten(row, COR_CARTAO)

			row.MouseButton1Click:Connect(function()
				local buyOk, success, result = pcall(function()
					return BuyResetSlot:InvokeServer(index)
				end)
				if buyOk and success then
					pickerGui.Enabled = false
					refreshShopData()
				else
					notify(tostring(result or success))
				end
			end)
		end
	end

	if not anySlot then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 44)
		empty.BackgroundTransparency = 1
		empty.Text = "Nenhum personagem disponível"
		empty.TextColor3 = COR_TEXTO_FRACO
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 13
		empty.Parent = pickerList
	end

	pickerGui.Enabled = true
end

local function buildUnlockSlotCard(order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 58)
	row.BackgroundColor3 = COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 10
	row.Parent = contentFrame
	cantos(row, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = shopData.UnlockSlot.Name
	nameLabel.TextColor3 = COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 10
	nameLabel.Parent = row

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -140, 0, 16)
	subLabel.Position = UDim2.new(0, 12, 0, 32)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = "destrava o próximo slot de personagem"
	subLabel.TextColor3 = COR_TEXTO_FRACO
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.ZIndex = 10
	subLabel.Parent = row

	local actionButton = makeActionButton(row)
	if shopData.UnlockSlot.MaxedOut then
		actionButton.Text = "MÁX"
		actionButton.BackgroundColor3 = COR_CARTAO_ALT
		actionButton.TextColor3 = COR_TEXTO_FRACO
	else
		actionButton.Text = "$" .. tostring(shopData.UnlockSlot.Cost)
		actionButton.BackgroundColor3 = COR_OK
		hoverBrighten(actionButton, COR_OK)
		actionButton.MouseButton1Click:Connect(function()
			if isBusy then return end
			isBusy = true
			local ok, success, result = pcall(function()
				return BuyUnlockSlot:InvokeServer()
			end)
			isBusy = false
			if ok and success then
				refreshShopData()
			else
				notify(tostring(result or success))
			end
		end)
	end

	return row
end

local function buildResetSlotCard(order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 58)
	row.BackgroundColor3 = COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 10
	row.Parent = contentFrame
	cantos(row, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = shopData.ResetSlot.Name
	nameLabel.TextColor3 = COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 10
	nameLabel.Parent = row

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -140, 0, 16)
	subLabel.Position = UDim2.new(0, 12, 0, 32)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = "reinicia atributos/posição de um personagem à escolha"
	subLabel.TextColor3 = COR_TEXTO_FRACO
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.ZIndex = 10
	subLabel.Parent = row

	local actionButton = makeActionButton(row)
	actionButton.Text = "$" .. tostring(shopData.ResetSlot.Cost)
	actionButton.BackgroundColor3 = COR_ACENTO
	hoverBrighten(actionButton, COR_ACENTO)
	actionButton.MouseButton1Click:Connect(openResetPicker)

	return row
end

-- ==========================================================
-- Card de produto de Robux
-- ==========================================================
local function buildRobuxCard(product, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 58)
	row.BackgroundColor3 = COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 10
	row.Parent = contentFrame
	cantos(row, 8)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = product.Name
	nameLabel.TextColor3 = COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 10
	nameLabel.Parent = row

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -140, 0, 16)
	subLabel.Position = UDim2.new(0, 12, 0, 32)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = product.Configured and "produto de Robux" or "ainda não configurado — avise o dono do jogo"
	subLabel.TextColor3 = product.Configured and COR_TEXTO_FRACO or COR_PERIGO
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.ZIndex = 10
	subLabel.Parent = row

	local actionButton = makeActionButton(row)
	actionButton.Text = "ROBUX"
	local cor = product.Configured and COR_ACENTO or COR_CARTAO_ALT
	actionButton.BackgroundColor3 = cor
	actionButton.TextColor3 = product.Configured and Color3.new(1, 1, 1) or COR_TEXTO_FRACO
	if product.Configured then hoverBrighten(actionButton, cor) end

	actionButton.MouseButton1Click:Connect(function()
		if not product.Configured then
			notify("Esse produto ainda não foi configurado no Studio.")
			return
		end
		pcall(function()
			MarketplaceService:PromptProductPurchase(player, product.ProductId)
		end)
	end)

	return row
end

-- ⚠️ v74 — CARD DE ROLL DE ROBUX.
-- PEDIDO: "inclua a roll de robux [na loja]". O roll pago com Robux já
-- existe de verdade dentro da tela de Roll (botão helpRobux, ver
-- RollClient.local.luau) — de propósito NUNCA foi duplicado aqui, pra
-- não ter duas rotas de compra do mesmo Developer Product (risco de
-- divergirem). Este card não compra nada sozinho: ele fecha a Loja e
-- ABRE a tela de Roll (_G.OpenRoll), que é onde a compra de verdade
-- acontece — um lugar só pra essa lógica, dois lugares pra chegar nela.
local function buildRollRobuxCard(order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -6, 0, 58)
	row.BackgroundColor3 = COR_CARTAO
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.ZIndex = 10
	row.Parent = contentFrame
	cantos(row, 8)
	contorno(row, COR_ACENTO, 1, 0.4)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -140, 0, 22)
	nameLabel.Position = UDim2.new(0, 12, 0, 8)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = "Roll de Robux (Hissatsu/Arma)"
	nameLabel.TextColor3 = COR_TEXTO
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 14
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 10
	nameLabel.Parent = row

	local subLabel = Instance.new("TextLabel")
	subLabel.Size = UDim2.new(1, -140, 0, 16)
	subLabel.Position = UDim2.new(0, 12, 0, 32)
	subLabel.BackgroundTransparency = 1
	subLabel.Text = "sorteia um Hissatsu ou uma Arma — abre a tela de Roll"
	subLabel.TextColor3 = COR_TEXTO_FRACO
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 11
	subLabel.TextXAlignment = Enum.TextXAlignment.Left
	subLabel.ZIndex = 10
	subLabel.Parent = row

	local actionButton = makeActionButton(row)
	actionButton.Text = "ABRIR ROLL"
	actionButton.BackgroundColor3 = COR_ACENTO
	hoverBrighten(actionButton, COR_ACENTO)
	actionButton.MouseButton1Click:Connect(function()
		_G.CloseShop()
		if _G.OpenRoll then
			_G.OpenRoll()
		else
			notify("Tela de Roll indisponível no momento.")
		end
	end)

	return row
end

-- ==========================================================
-- Renderização por aba
-- ==========================================================
local function clearContent()
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function renderCategory()
	if not shopData then return end
	clearContent()

	local order = 1

	if currentCategory == "Conveniencia" then
		buildUnlockSlotCard(order); order += 1
		buildResetSlotCard(order); order += 1
	end

	if currentCategory == "Boosts" then
		local statusLabel = Instance.new("TextLabel")
		statusLabel.Size = UDim2.new(1, -6, 0, 40)
		statusLabel.BackgroundTransparency = 1
		statusLabel.TextColor3 = COR_OK
		statusLabel.Font = Enum.Font.GothamMedium
		statusLabel.TextSize = 12
		statusLabel.TextWrapped = true
		statusLabel.TextXAlignment = Enum.TextXAlignment.Left
		statusLabel.LayoutOrder = order
		statusLabel.ZIndex = 10
		statusLabel.Parent = contentFrame
		local b = shopData.Boosts
		local parts = {}
		if b.MoneyBoostActive then table.insert(parts, "2x dinheiro ativo") end
		if b.XPBoostActive then table.insert(parts, "2x XP ativo") end
		if b.ExtraQuestActive then table.insert(parts, "+1 missão ativa") end
		if (b.LuckRollsRemaining or 0) > 0 then table.insert(parts, string.format("sorte no roll: %d rolagens restantes", b.LuckRollsRemaining)) end
		statusLabel.Text = #parts > 0 and table.concat(parts, "  ·  ") or "Nenhum boost ativo agora."
		if #parts == 0 then statusLabel.TextColor3 = COR_TEXTO_FRACO end
		order += 1
	end

	if currentCategory == "Robux" then
		buildRollRobuxCard(order); order += 1
		for _, product in ipairs(shopData.RobuxProducts) do
			buildRobuxCard(product, order)
			order += 1
		end
	else
		for _, item in ipairs(shopData.Items) do
			if item.Category == currentCategory then
				buildCatalogCard(item, order)
				order += 1
			end
		end
	end
end

-- ==========================================================
-- Abas
-- ==========================================================
local function selectCategory(categoryId)
	currentCategory = categoryId
	for id, btn in pairs(tabButtons) do
		local selecionado = (id == categoryId)
		btn.BackgroundColor3 = selecionado and COR_ACENTO or COR_CARTAO
		btn.TextColor3 = selecionado and Color3.new(1, 1, 1) or COR_TEXTO_FRACO
	end
	renderCategory()
end

local function buildTabs()
	local categories = {
		{ Id = "Cosmeticos", Name = "COSMÉTICOS" },
		{ Id = "Conveniencia", Name = "CONVENIÊNCIA" },
		{ Id = "Boosts", Name = "BOOSTS" },
		{ Id = "Robux", Name = "ROBUX" },
	}
	for i, cat in ipairs(categories) do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0.25, -5, 1, 0)
		btn.BackgroundColor3 = COR_CARTAO
		btn.BorderSizePixel = 0
		btn.Text = cat.Name
		btn.TextColor3 = COR_TEXTO_FRACO
		btn.Font = Enum.Font.GothamBold
		btn.TextSize = 11
		btn.AutoButtonColor = false
		btn.LayoutOrder = i
		btn.ZIndex = 10
		btn.Parent = tabRow
		cantos(btn, 6)

		btn.MouseButton1Click:Connect(function()
			selectCategory(cat.Id)
		end)

		tabButtons[cat.Id] = btn
	end
end
buildTabs()

-- ==========================================================
-- Refresh / abrir / fechar
-- ==========================================================
function refreshShopData()
	local ok, data = pcall(function()
		return GetShopData:InvokeServer()
	end)
	if ok and data then
		shopData = data
		moneyLabel.Text = "$" .. tostring(data.Money)
		renderCategory()
	else
		warn("ShopClient: falha ao buscar GetShopData: " .. tostring(data))
	end
end

_G.OpenShop = function()
	setShopVisible(true)
	selectCategory(currentCategory)
	refreshShopData()
end

_G.CloseShop = function()
	setShopVisible(false)
end

_G.ToggleShop = function()
	if screenGui.Enabled then
		_G.CloseShop()
	else
		_G.OpenShop()
	end
end

closeButton.MouseButton1Click:Connect(_G.CloseShop)
backdrop.MouseButton1Click:Connect(_G.CloseShop)

if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(ajustarEscala)
end
ajustarEscala()
selectCategory(currentCategory)

print("✅ ShopClient carregado.")
