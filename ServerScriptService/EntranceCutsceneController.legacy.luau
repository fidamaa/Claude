--[[
	EntranceCutsceneController (Script)
	SERVER: ServerScriptService (place Game)

	PEDIDO: "quero também incluir uma cutscene de entrada. ela vai começar
	naqueles corredores de entrada ao estádio e os dois times vão passar ao
	mesmo tempo um ao lado do outro, numa fila tradicional, a ordem não
	importa, contanto que sejam do mesmo time, eles vão andando em direção
	ao campo, e depois corta pra todo mundo dentro de campo."

	Esse script só faz a parte de SERVIDOR: descobre quem está em cada
	time, pergunta pro MatchController.legacy.luau (via _G.GetFormationCFrame)
	pra ONDE cada jogador vai de verdade no kickoff, manda esse "roster"
	pra todo mundo (Remotes.PlayEntranceCutscene) e espera a duração
	configurada antes do resto da sequência de início de partida continuar
	(ver _G.PlayEntranceCutscene sendo chamado em MatchController.lua ->
	startMatchTimer).

	TODA a parte visual (esconder os personagens de verdade, criar os
	"bonecos" que andam pelo túnel, mover a câmera, revelar os personagens
	de verdade no final) é 100% client-side — ver
	EntranceCutsceneClient.local.luau (StarterPlayerScripts). Isso é só
	cosmético: se as Parts do túnel (ver Config.CUTSCENE_TUNNEL_START_PREFIX/
	CUTSCENE_TUNNEL_END_PREFIX em FootballConfig.lua) ainda não existirem no
	Studio, o cliente detecta sozinho e pula a cutscene sem travar nada —
	a partida sempre começa normalmente de um jeito ou de outro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

-- Monta { [nomeDoTime] = { {UserId=n, FieldCFrame=CFrame}, ... } } com todo
-- jogador que já tem Time definido no momento do kickoff. Quem não tem
-- Team (não deveria acontecer nesse ponto, mas por segurança) ou cuja
-- posição de formação ainda não está pronta (_G.GetFormationCFrame
-- devolveu nil — campo ainda não identificado etc.) simplesmente não entra
-- no roster; o cliente só cria boneco pra quem está na lista.
local function buildRoster()
	local roster = {}
	for _, teamName in ipairs(Config.TEAM_NAMES) do
		roster[teamName] = {}
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Team then
			local teamName = player.Team.Name
			if roster[teamName] then
				local cframe = _G.GetFormationCFrame and _G.GetFormationCFrame(player)
				if cframe then
					table.insert(roster[teamName], { UserId = player.UserId, FieldCFrame = cframe })
				end
			end
		end
	end

	return roster
end

_G.PlayEntranceCutscene = function()
	if not Config.ENTRANCE_CUTSCENE_ENABLED then return end

	local roster = buildRoster()

	-- Nenhum time com jogador nenhum (ex: testando sozinho no Studio antes
	-- de qualquer Team ser atribuído) — não faz sentido tocar a cutscene
	-- pra um túnel vazio, pula direto.
	local anyone = false
	for _, list in pairs(roster) do
		if #list > 0 then anyone = true; break end
	end
	if not anyone then return end

	Remotes.PlayEntranceCutscene:FireAllClients(roster, Config.ENTRANCE_CUTSCENE_DURATION)
	task.wait(Config.ENTRANCE_CUTSCENE_DURATION)
end

print("✅ EntranceCutsceneController carregado.")
