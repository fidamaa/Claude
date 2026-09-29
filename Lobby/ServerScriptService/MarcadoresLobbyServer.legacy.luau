--[[
	MarcadoresLobbyServer — ⚠️ v104

	PEDIDO: "tem uma mensagem bem em cima do campo, flutuando [procurar
	partida]. Aumenta o tamanho dela, deixa num tamanho visível pra poder ver
	atrás da parede mesmo. Faz isso também na Eleven Store, no local de
	missão, e no meu personagem, o Kogamalotigo — pra abrir o perfil, os
	slots. Tem que ter um pra cada coisa."

	O Lobby usa StreamingEnabled: um NPC longe NÃO existe no cliente, então
	um marcador preso nele sumiria justamente quando é mais útil (de longe).
	Este script (servidor vê tudo) publica a POSIÇÃO de cada destino como
	atributo em ReplicatedStorage.MarcadoresLobby; o cliente
	(MarcadoresLobby.local.luau) cria os marcadores nesses pontos.

	Destinos: a zona de partida (Config.MATCHMAKING_ZONE_NAME) e os NPCs com a
	tag "Dialogue" cujo DialogueId (atributo, ou o nome do Model) é
	ShopKeeper / QuestGiver / Kogamalotigo.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))

local pasta = ReplicatedStorage:FindFirstChild("MarcadoresLobby") or Instance.new("Configuration")
pasta.Name = "MarcadoresLobby"
pasta.Parent = ReplicatedStorage

local DESTINOS_NPC = {
	ShopKeeper = "Loja",
	QuestGiver = "Missoes",
	Kogamalotigo = "Perfil",
}

local function topoDe(model)
	local ok, cf, tamanho = pcall(function() return model:GetBoundingBox() end)
	if not ok then return nil end
	return cf.Position + Vector3.new(0, tamanho.Y / 2 + 9, 0) -- bem acima do nome do NPC (não cobre a plaquinha dele)
end

local function atualizar()
	local zona = workspace:FindFirstChild(Config.MATCHMAKING_ZONE_NAME, true)
	if zona and zona:IsA("BasePart") then
		pasta:SetAttribute("Partida", zona.Position + Vector3.new(0, zona.Size.Y / 2 + 16, 0))
	end
	for _, model in ipairs(CollectionService:GetTagged("Dialogue")) do
		if model:IsA("Model") then
			local id = model:GetAttribute("DialogueId") or model.Name
			-- aceita "kogamalotigo" minúsculo (nome do Model) também
			local chave = DESTINOS_NPC[id] or DESTINOS_NPC[(tostring(id):gsub("^%l", string.upper))]
			if chave then
				local pos = topoDe(model)
				if pos then pasta:SetAttribute(chave, pos) end
			end
		end
	end
end

atualizar()
CollectionService:GetInstanceAddedSignal("Dialogue"):Connect(function() task.defer(atualizar) end)
-- NPCs podem andar/ser reposicionados no Studio: reatualiza de tempos em tempos
task.spawn(function()
	while true do
		task.wait(10)
		atualizar()
	end
end)
