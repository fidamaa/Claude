--[[
	RobuxProducts (Script) — ServerScriptService (place Lobby)

	⚠️ IMPORTANTE: o Roblox só permite UM handler de
	MarketplaceService.ProcessReceipt por jogo inteiro — atribuir de novo
	em outro script SUBSTITUI o anterior silenciosamente (quem atribuir
	por último "vence", o outro produto para de funcionar sem erro nem
	aviso). Antes deste script, RollServer.legacy.luau atribuía
	ProcessReceipt diretamente pra 1 produto só — agora que a Loja também
	vende produtos com Robux (pacotes de dinheiro, destravar slots), TODOS
	os scripts que vendem algo com Robux precisam passar por AQUI, nunca
	atribuir ProcessReceipt por conta própria.

	Uso (em qualquer outro script, depois que este carregar):
		_G.RegisterRobuxProduct(productId, function(player, receiptInfo)
			-- concede o produto pro player
			return true -- ou false se não conseguiu conceder (Roblox tenta de novo depois)
		end)

	ProductId 0 é sempre ignorado (placeholder "ainda não configurado no
	Studio", mesmo padrão usado em Config.ROBUX_ROLL_PRODUCT_ID).
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local handlers = {} -- [productId] = function(player, receiptInfo) -> boolean

_G.RegisterRobuxProduct = function(productId, handlerFn)
	if type(productId) ~= "number" or productId == 0 then
		return -- placeholder não configurado — não registra (evita colisão de vários produtos em "0")
	end
	if handlers[productId] then
		warn(string.format("⚠️ RobuxProducts: ProductId %d já tinha um handler registrado — sobrescrevendo.", productId))
	end
	handlers[productId] = handlerFn
end

MarketplaceService.ProcessReceipt = function(receiptInfo)
	local handlerFn = handlers[receiptInfo.ProductId]
	if not handlerFn then
		-- Produto desconhecido (nenhum script registrou esse Id) — não
		-- concede nada, mas também não trava a fila de recibos do jogador.
		warn(string.format("⚠️ RobuxProducts: recibo pra ProductId %d sem handler registrado.", receiptInfo.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Jogador saiu antes de processar — Roblox tenta de novo mais tarde.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, granted = pcall(handlerFn, player, receiptInfo)
	if not ok then
		warn(string.format("❌ RobuxProducts: erro ao processar ProductId %d pra %s: %s", receiptInfo.ProductId, player.Name, tostring(granted)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not granted then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	return Enum.ProductPurchaseDecision.PurchaseGranted
end

print("✅ RobuxProducts (dispatcher central de Developer Products) carregado")
