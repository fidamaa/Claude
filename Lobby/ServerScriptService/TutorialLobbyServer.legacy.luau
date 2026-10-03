--[[
	TutorialLobbyServer — ⚠️ v104

	PEDIDO: "coloque um tutorial opcional no início do jogo. A pessoa decide
	se vai querer fazer ou não... você já pode puxar o cara que nunca teve
	conta direto, o cara que entrou pela primeira vez."

	Na primeira vez que alguém entra no Lobby (flag TutorialOferecido nos
	dados salvos), o cliente mostra a pergunta (TutorialOfertaClient). Se a
	pessoa aceita, reserva um server do Game SÓ pra ela e manda pra lá com
	TeleportData.Tutorial = true (o Game roda o roteiro: TutorialServer). Se
	recusa, não pergunta de novo. _G.IniciarTutorial(player) fica exposto pra
	quem quiser oferecer de novo depois (ex.: um NPC).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("LobbyConfig"))
local Remotes = Config.Remotes

local oferecido = {} -- [UserId] = true enquanto a pergunta está aberta

local function dadosDe(player, espera)
	local limite = os.clock() + (espera or 0)
	repeat
		local d = _G.GetPlayerData and _G.GetPlayerData(player)
		if d then return d end
		task.wait(0.5)
	until os.clock() > limite or not player.Parent
	return nil
end

_G.IniciarTutorial = function(player)
	local ok, accessCode = pcall(function()
		return TeleportService:ReserveServerAsync(Config.GAME_PLACE_ID)
	end)
	if not ok or not accessCode then
		warn("Tutorial: falha ao reservar server: " .. tostring(accessCode))
		if Remotes.PartyAviso then Remotes.PartyAviso:FireClient(player, "Não deu pra abrir o tutorial agora.", "erro") end
		return false
	end
	if not _G.TeleportarPartidaLocal then return false end
	_G.TeleportarPartidaLocal({
		MatchId = HttpService:GenerateGUID(false),
		ModeId = "TUTORIAL",
		TotalPlayers = 1,
		AccessCode = accessCode,
		Assignments = { [tostring(player.UserId)] = Config.TEAM_NAMES and Config.TEAM_NAMES[1] or "Azul" },
		Privada = true,
		Tutorial = true,
	})
	return true
end

Players.PlayerAdded:Connect(function(player)
	local data = dadosDe(player, 25)
	if not data or data.TutorialOferecido == true then return end
	-- quem acabou de voltar de uma partida não é "primeira vez"
	local ok, jd = pcall(function() return player:GetJoinData() end)
	local td = ok and jd and jd.TeleportData
	if typeof(td) == "table" and (td.MatchRewards or td.TutorialConcluido) then
		data.TutorialOferecido = true
		return
	end
	task.wait(4) -- deixa o personagem e a tela carregarem
	if not player.Parent then return end
	oferecido[player.UserId] = true
	Remotes.OferecerTutorial:FireClient(player)
end)

Players.PlayerRemoving:Connect(function(p) oferecido[p.UserId] = nil end)

Remotes.RespostaTutorial.OnServerEvent:Connect(function(player, fazer)
	if not oferecido[player.UserId] then return end
	oferecido[player.UserId] = nil
	local data = dadosDe(player, 0)
	if data then
		data.TutorialOferecido = true
		if _G.RequestSave then task.spawn(_G.RequestSave, player) end
	end
	if fazer == true then
		_G.IniciarTutorial(player)
	end
end)
