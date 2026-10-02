--[[
	CosmeticosServer (Script) — ⚠️ v110
	LOCAL: ServerScriptService (place Game)

	PEDIDO: "inclua todos os cosméticos... coloque tudo possível, implemente
	no jogo, implemente também o nome personalizado que já tem nos slots
	dentro do jogo, comemoração... faça animação pra cada comemoração" +
	"cutscenes de flow igual as dos animes (Blue Lock); cada flow dá um buff
	diferente".

	O que vem do Lobby (TeleportData, ver PlayerSystems.onPlayerAdded):
	  Player "NomePersonagem" = nome do slot
	  Player "Cosm_<Slot>"    = Id equipado (ver Cosmeticos.luau)

	Este script:
	  • Emote (tecla G / botão no celular): toca o emote equipado; mexeu,
	    parou. Não toca com a bola no pé nem durante cutscene.
	  • _G.TocarComemoracaoCosmetica(scorer) — MatchController, no gol.
	  • _G.EfeitoDeGolCosmetico(scorer)      — MatchController, no gol.
	  • _G.AtivarFlow(player, duracao)       — InstinctController, ao ativar o
	    Flow: soma os atributos do Flow escolhido (e tira os MESMOS pontos no
	    fim, sem apagar mudanças de outros sistemas), liga FlowVelocidade
	    (lido por _G.GetInstinctSpeedMultiplier) e manda a cena pra todos.
	O visual (placa de nome, aura, efeito de gol, cena do Flow, chat) fica no
	CosmeticosClient.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos"))
local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local pasta = ReplicatedStorage:FindFirstChild("CosmeticosRemotes")
if not pasta then
	pasta = Instance.new("Folder")
	pasta.Name = "CosmeticosRemotes"
	pasta.Parent = ReplicatedStorage
end
local function remote(nome)
	local r = pasta:FindFirstChild(nome)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = nome
		r.Parent = pasta
	end
	return r
end
local TocarEmote = remote("TocarEmote")
local FlowAtivado = remote("FlowAtivado")
local EfeitoDeGol = remote("EfeitoDeGol")

local ball = workspace:WaitForChild(Config.BALL_NAME, 30)

-- Flow padrão: todo mundo tem o do Isagi (grátis). Espera o PlayerSystems
-- aplicar o TeleportData antes de decidir.
local function padroes(player)
	task.delay(2, function()
		if player.Parent and not player:GetAttribute("Cosm_Flow") then
			player:SetAttribute("Cosm_Flow", "Flow_Isagi")
		end
	end)
end
Players.PlayerAdded:Connect(padroes)
for _, p in ipairs(Players:GetPlayers()) do padroes(p) end

-- ============================================================
-- EMOTES
-- ============================================================
local emoteAtivo = {} -- [player] = { Id, Fim }
local ultimoEmote = {}

local function donoDaBola()
	return _G.GetBallOwner and _G.GetBallOwner() or nil
end

local function tocarAcaoCosmetica(player, item)
	local character = player.Character
	if not (character and _G.AnimarAcao) then return false end
	_G.AnimarAcao(character, item.Id, item.Duracao)
	local registro = { Id = item.Id, Fim = os.clock() + item.Duracao }
	emoteAtivo[player] = registro
	return true
end

TocarEmote.OnServerEvent:Connect(function(player)
	if os.clock() - (ultimoEmote[player] or 0) < 1 then return end
	ultimoEmote[player] = os.clock()
	if _G.HissatsuCutsceneActive then return end
	if donoDaBola() == player then return end
	local item = Cosmeticos.Equipado(player, "Emote")
	if not item then return end
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return end
	tocarAcaoCosmetica(player, item)
end)

-- mexeu (ou pegou a bola) = o emote para na hora
task.spawn(function()
	while true do
		task.wait(0.1)
		for player, reg in pairs(emoteAtivo) do
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if not player.Parent or not humanoid or os.clock() > reg.Fim then
				emoteAtivo[player] = nil
			elseif not reg.Comemoracao and (humanoid.MoveDirection.Magnitude > 0.1 or donoDaBola() == player) then
				emoteAtivo[player] = nil
				if _G.AnimarAcao then _G.AnimarAcao(character, "parar:" .. reg.Id) end
			end
		end
	end
end)

-- ============================================================
-- GOL: comemoração + efeito
-- ============================================================
_G.TocarComemoracaoCosmetica = function(scorer)
	local item = scorer and Cosmeticos.Equipado(scorer, "Celebration")
	if not item then return false end
	if not tocarAcaoCosmetica(scorer, item) then return false end
	emoteAtivo[scorer].Comemoracao = true
	return true
end

-- ⚠️ v113 — PEDIDO: "efeitos de gol com o dobro da duração, os mais raros até 5x;
-- o replay só depois que o efeito terminar". Base ~3.5s (o tamanho dos efeitos
-- antigos) x o multiplicador da raridade. Devolve os segundos totais; o
-- MatchController espera esse tempo antes do replay.
local EFEITO_BASE_SEG = 3.5
local EFEITO_MULT = { Common = 2, Rare = 2.5, Epic = 3, Legendary = 4, Mythic = 5 }
_G.UltimaDuracaoEfeitoGol = 0
_G.DuracaoEfeitoGolDe = function(scorer)
	local item = scorer and Cosmeticos.Equipado(scorer, "GoalEffect")
	if not item then return 0 end
	return EFEITO_BASE_SEG * (EFEITO_MULT[item.Raridade] or 2)
end
_G.EfeitoDeGolCosmetico = function(scorer)
	_G.UltimaDuracaoEfeitoGol = 0
	local item = scorer and Cosmeticos.Equipado(scorer, "GoalEffect")
	if not item then return 0 end
	local pos = ball and ball.Position
	if not pos then return 0 end
	local mult = EFEITO_MULT[item.Raridade] or 2
	local total = EFEITO_BASE_SEG * mult
	_G.UltimaDuracaoEfeitoGol = total
	EfeitoDeGol:FireAllClients(item.Id, pos, scorer, total)
	return total
end

-- ============================================================
-- FLOW
-- ============================================================
local FLOW_TETO = 110 -- o Flow pode passar um pouco do 100 (é o "estado de fluxo")
local flowAtivo = {} -- [player] = { Somado = { attr = pontos }, Fim }

local function encerrarFlow(player)
	local estado = flowAtivo[player]
	if not estado then return end
	flowAtivo[player] = nil
	for attr, pontos in pairs(estado.Somado) do
		local atual = player:GetAttribute(attr)
		if typeof(atual) == "number" then
			player:SetAttribute(attr, atual - pontos)
		end
	end
	player:SetAttribute("FlowVelocidade", nil)
	player:SetAttribute("FlowAtivo", nil)
end

local PADRAO_ATRIBUTO = {
	Kick = Config.DEFAULT_KICK or 50, Speed = 50, Physical = 50, DribbleSkill = 50, Technique = 50,
}

_G.AtivarFlow = function(player, duracao)
	local item = Cosmeticos.Equipado(player, "Flow") or Cosmeticos.Item("Flow_Isagi")
	encerrarFlow(player)
	local estado = { Somado = {}, Fim = os.clock() + duracao }
	for attr, bonus in pairs(item.Atributos or {}) do
		local atual = player:GetAttribute(attr)
		if typeof(atual) ~= "number" then atual = PADRAO_ATRIBUTO[attr] or 50 end
		local novo = math.min(FLOW_TETO, atual + bonus)
		local somado = novo - atual
		if somado > 0 then
			player:SetAttribute(attr, novo)
			estado.Somado[attr] = somado
		end
	end
	flowAtivo[player] = estado
	if item.Velocidade then player:SetAttribute("FlowVelocidade", item.Velocidade) end
	player:SetAttribute("FlowAtivo", item.Id)
	FlowAtivado:FireAllClients(player, item.Id, duracao)
	task.delay(duracao, function()
		if flowAtivo[player] == estado then encerrarFlow(player) end
	end)
end

_G.EncerrarFlow = encerrarFlow

Players.PlayerRemoving:Connect(function(player)
	flowAtivo[player] = nil
	emoteAtivo[player] = nil
	ultimoEmote[player] = nil
end)

print("✅ CosmeticosServer carregado (emotes, comemorações, efeito de gol, Flow)")
