--[[
	PassRequestController (Script)
	LOCAL: ServerScriptService (place Game)

	Pedido de passe geral (⚠️ NOVO): qualquer jogador de LINHA (Role ~=
	"GK") pode apertar T pra sinalizar "me dá o passe" — isso liga o
	Attribute WantsPass (true) por Config.GKBOT_PASS_REQUEST_DURATION
	segundos, some sozinho, e mostra um BillboardGui ("PASSA!") acima da
	cabeça do jogador, visível pra todo mundo (é só uma Instance normal
	dentro do character, replica sozinha — não precisa de Remote extra
	pros outros clientes verem).

	Não usa Highlight de propósito: colocar um 2º Highlight ao mesmo
	tempo no personagem (além do TeamHighlight) já causou bug antes (ver
	comentário sobre o iframe em BallController.lua) — esse pedido de
	passe usa só o BillboardGui, nunca mexe no Highlight de ninguém.

	O goleiro (Role == "GK") NUNCA pode pedir passe — o cliente já nem
	manda o Remote nesse caso (PassRequestInput.local.lua), mas o
	servidor SEMPRE revalida aqui, nunca confia só no cliente.

	GKBotController.lua lê o Attribute WantsPass direto (sem Remote/_G)
	pra dar prioridade a quem pediu passe na hora de escolher o alvo do
	lançamento depois de agarrar a bola.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local RequestPass = Config.Remotes.RequestPass

local REQUEST_COOLDOWN = 1 -- segundos, debounce simples pra não spammar o Remote

local lastRequestAt = {} -- [player] = tick() do último pedido aceito
local clearTokens = {} -- [player] = token atual (invalida timers de expiração antigos se pedir de novo antes de sumir)

local function ensureBillboard(character)
	local billboard = character:FindFirstChild("PassRequestGui")
	if billboard then return billboard end

	billboard = Instance.new("BillboardGui")
	billboard.Name = "PassRequestGui"
	billboard.Size = UDim2.new(0, 140, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 1, 0)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 221, 0)
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	label.Text = "PASSA!"
	label.Parent = billboard

	billboard.Parent = character
	return billboard
end

local function clearRequest(player)
	player:SetAttribute("WantsPass", false)
	local character = player.Character
	local billboard = character and character:FindFirstChild("PassRequestGui")
	if billboard then billboard:Destroy() end
end

RequestPass.OnServerEvent:Connect(function(player)
	if player:GetAttribute("Role") == "GK" then return end -- goleiro nunca pede passe (servidor revalida)

	local now = tick()
	if now - (lastRequestAt[player] or 0) < REQUEST_COOLDOWN then return end
	lastRequestAt[player] = now

	local character = player.Character
	if not character then return end

	player:SetAttribute("WantsPass", true)
	ensureBillboard(character)

	local token = (clearTokens[player] or 0) + 1
	clearTokens[player] = token

	task.delay(Config.GKBOT_PASS_REQUEST_DURATION, function()
		if clearTokens[player] == token then
			clearRequest(player)
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	lastRequestAt[player] = nil
	clearTokens[player] = nil
end)

print("✅ PassRequestController carregado (tecla H = pedir passe, jogador de linha só).")
