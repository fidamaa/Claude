--[[
	TutorialServer — ⚠️ v104

	PEDIDO: "coloque um tutorial opcional no início do jogo. A pessoa decide
	se vai querer fazer ou não. Se fizer, ele vai ensinar o básico dentro da
	partida... seja criativo: 'chute ao gol, faça isso aqui'. Desative o
	restante da gameplay (timer, cutscenes de entrada)."

	Só roda quando o server é de tutorial (_G.ModoTutorial, lido do
	TeleportData pelo MatchController). O MatchController liga os gols sem
	relógio e chama _G.TutorialComecar. Cada passo:
	  1) prepara o campo (bola, posição);
	  2) manda o texto/teclas/marcador pro cliente (Remotes.TutorialPasso);
	  3) espera o jogador FAZER de verdade (posição, posse da bola, ou um
	     aviso de _G.TutorialNotificar vindo do BallController/MatchController:
	     "Drible", "Dash", "Carrinho", "Gol");
	  4) marca como feito e vai pro próximo.
	No fim (ou em "pular"), encerra a partida pelo caminho normal — tela final
	"tutorial concluído" e volta pro Lobby.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local avisos = {} -- [tipo] = contador
_G.TutorialNotificar = function(_player, tipo)
	if not _G.ModoTutorial then return end
	avisos[tipo] = (avisos[tipo] or 0) + 1
end

local terminado = false
local passoContinuar = false

local function encerrar()
	if terminado then return end
	terminado = true
	if _G.EndMatchNow then _G.EndMatchNow() end
end

Remotes.TutorialAcao.OnServerEvent:Connect(function(_player, acao)
	if not _G.ModoTutorial then return end
	if acao == "continuar" then passoContinuar = true
	elseif acao == "pular" then encerrar() end
end)

-- ===== geometria =====
local function rootDe(player)
	local c = player and player.Character
	return c and c:FindFirstChild("HumanoidRootPart")
end

local function golAdversario(player)
	local meuTime = player.Team and player.Team.Name
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and d:GetAttribute("ScoringTeam") == meuTime then
			return d
		end
	end
	return nil
end

local function chao(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignorar = { workspace:FindFirstChild(Config.BALL_NAME) }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
	params.FilterDescendantsInstances = ignorar
	local r = workspace:Raycast(pos + Vector3.new(0, 30, 0), Vector3.new(0, -80, 0), params)
	return r and r.Position or pos
end

local function bola()
	return workspace:FindFirstChild(Config.BALL_NAME)
end

local function colocarBola(pos)
	if _G.ReleaseBallOwner then _G.ReleaseBallOwner() end
	if _G.SetDeadBallMode then _G.SetDeadBallMode(false) end
	if _G.ResetBallState then _G.ResetBallState(chao(pos) + Vector3.new(0, 1.2, 0)) end
end

local function darBola(player)
	local root = rootDe(player)
	if not root then return end
	colocarBola(root.Position + root.CFrame.LookVector * 3)
end

local function esperar(condicao, vigia)
	while not terminado do
		if condicao() then return true end
		if vigia then vigia() end
		task.wait(0.15)
	end
	return false
end

-- ===== roteiro =====
local function rodar()
	local player = Players:GetPlayers()[1]
	while not player do task.wait(0.5); player = Players:GetPlayers()[1] end
	local limite = os.clock() + 15
	while not rootDe(player) and os.clock() < limite do task.wait(0.2) end
	-- sem time (ex.: teste no Studio sem TeleportData): entra no primeiro time
	if not player.Team then
		local times = game:GetService("Teams")
		local t1 = times:FindFirstChild(Config.TEAM_NAMES and Config.TEAM_NAMES[1] or "Azul")
		if t1 then player.Team = t1 end
	end
	task.wait(1.5)

	local gol = golAdversario(player)
	local campo = workspace:FindFirstChild(Config.FIELD_HITBOX_NAME)
	local centro = campo and campo.Position or rootDe(player).Position
	local ataque = gol and Vector3.new(gol.Position.X - centro.X, 0, gol.Position.Z - centro.Z).Unit or Vector3.new(1, 0, 0)
	local lado = ataque:Cross(Vector3.yAxis).Unit

	local passos = {
		{
			Titulo = "ANDAR",
			Texto = "Use W A S D pra andar. Vá até o marcador verde.",
			Teclas = { "W", "A", "S", "D" },
			Preparar = function(p)
				colocarBola(centro - ataque * 70)
				local root = rootDe(p)
				p:SetAttribute("TutAlvo", chao(root.Position + ataque * 30 + lado * 6))
			end,
			Pronto = function(p)
				local root, alvo = rootDe(p), p:GetAttribute("TutAlvo")
				return root and alvo and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(alvo.X, 0, alvo.Z)).Magnitude < 7
			end,
		},
		{
			Titulo = "PEGAR A BOLA",
			Texto = "Encoste na bola pra dominar. Ela fica sempre colada na frente dos seus pés.",
			Teclas = {},
			Preparar = function(p)
				local root = rootDe(p)
				local pos = root.Position + ataque * 14
				colocarBola(pos)
				p:SetAttribute("TutAlvo", chao(pos))
			end,
			Pronto = function(p) return _G.GetBallOwner and _G.GetBallOwner() == p end,
		},
		{
			Titulo = "CONDUZIR",
			Texto = "Com a bola no pé, leve ela até o marcador. É só andar — ela vai junto.",
			Teclas = { "W", "A", "S", "D" },
			Preparar = function(p)
				local root = rootDe(p)
				p:SetAttribute("TutAlvo", chao(root.Position + ataque * 32 - lado * 14))
			end,
			Pronto = function(p)
				local b, alvo = bola(), p:GetAttribute("TutAlvo")
				return b and alvo and _G.GetBallOwner and _G.GetBallOwner() == p
					and (Vector3.new(b.Position.X, 0, b.Position.Z) - Vector3.new(alvo.X, 0, alvo.Z)).Magnitude < 8
			end,
			Vigia = function(p)
				if _G.GetBallOwner and _G.GetBallOwner() ~= p then
					local b, root = bola(), rootDe(p)
					if b and root and (b.Position - root.Position).Magnitude > 25 then darBola(p) end
				end
			end,
		},
		{
			Titulo = "DRIBLE",
			Texto = "Com a bola, aperte Q junto com uma direção (A ou D) pra rolar a bola de sola pro lado. Se um adversário der carrinho nessa hora, ele cai e você ganha uma arrancada.",
			Teclas = { "Q", "+", "A / D" },
			Evento = "Drible",
			Preparar = function(p)
				p:SetAttribute("TutAlvo", nil)
				if _G.GetBallOwner and _G.GetBallOwner() ~= p then darBola(p) end
			end,
			Vigia = function(p)
				if _G.GetBallOwner and _G.GetBallOwner() ~= p then
					local b, root = bola(), rootDe(p)
					if b and root and (b.Position - root.Position).Magnitude > 12 then darBola(p) end
				end
			end,
		},
		{
			Titulo = "DASH",
			Texto = "Aperte F pra dar uma arrancada rápida na direção que você anda — com ou sem a bola.",
			Teclas = { "F" },
			Evento = "Dash",
			Preparar = function(p) p:SetAttribute("TutAlvo", nil) end,
		},
		{
			Titulo = "CHUTE",
			Texto = "Mire no gol com o mouse. SEGURE o botão esquerdo pra carregar a força e SOLTE pra chutar. Faça um gol!",
			Teclas = { "MIRA", "SEGURA", "SOLTA" },
			Evento = "Gol",
			Preparar = function(p)
				local root = rootDe(p)
				if gol and root then
					local pontoChute = chao(gol.Position - ataque * 48) + Vector3.new(0, 3, 0)
					root.CFrame = CFrame.lookAt(pontoChute, Vector3.new(gol.Position.X, pontoChute.Y, gol.Position.Z))
					task.wait(0.3)
					p:SetAttribute("TutAlvo", gol.Position)
					p:SetAttribute("TutPontoChute", pontoChute)
				end
				darBola(p)
			end,
			Vigia = function(p)
				-- bola parada longe do pé (errou o chute / saiu): devolve no ponto de chute
				local b = bola()
				if not b then return end
				local semDono = not (_G.GetBallOwner and _G.GetBallOwner())
				local parada = b.AssemblyLinearVelocity.Magnitude < 2
				local root = rootDe(p)
				if semDono and parada and root and (b.Position - root.Position).Magnitude > 10 then
					p:SetAttribute("TutParadaDesde", p:GetAttribute("TutParadaDesde") or os.clock())
					if os.clock() - p:GetAttribute("TutParadaDesde") > 2.5 then
						p:SetAttribute("TutParadaDesde", nil)
						local ponto = p:GetAttribute("TutPontoChute")
						if ponto then
							root.CFrame = CFrame.lookAt(ponto, Vector3.new(gol.Position.X, ponto.Y, gol.Position.Z))
						end
						task.wait(0.2)
						darBola(p)
					end
				else
					p:SetAttribute("TutParadaDesde", nil)
				end
			end,
		},
		{
			Titulo = "CARRINHO",
			Texto = "Sem a bola, aperte Q pra dar um carrinho na direção que você anda. É assim que se rouba a bola de alguém.",
			Teclas = { "Q" },
			Evento = "Carrinho",
			Preparar = function(p)
				p:SetAttribute("TutAlvo", nil)
				colocarBola(centro - ataque * 70)
			end,
		},
		{
			Titulo = "TÉCNICAS",
			Texto = "1 e 2 usam as suas Hissatsus (chutes, dribles e defesas especiais, com cutscene). E e R usam as suas Armas. T é cabeçada e Ctrl trava a câmera. Você escolhe tudo isso no Lobby.",
			Teclas = { "1", "2", "E", "R", "T" },
			Botao = "ENTENDI",
			Preparar = function(p) p:SetAttribute("TutAlvo", nil) end,
		},
	}

	for i, passo in ipairs(passos) do
		if terminado then return end
		if passo.Preparar then passo.Preparar(player) end
		local base = passo.Evento and (avisos[passo.Evento] or 0) or 0
		passoContinuar = false
		Remotes.TutorialPasso:FireClient(player, {
			Indice = i, Total = #passos, Titulo = passo.Titulo, Texto = passo.Texto,
			Teclas = passo.Teclas, Botao = passo.Botao, Marcador = player:GetAttribute("TutAlvo"),
		})
		esperar(function()
			if passo.Botao then return passoContinuar end
			if passo.Evento then return (avisos[passo.Evento] or 0) > base end
			return passo.Pronto and passo.Pronto(player)
		end, passo.Vigia and function() passo.Vigia(player) end or nil)
		if terminado then return end
		Remotes.TutorialPasso:FireClient(player, { Feito = i, Total = #passos })
		task.wait(1.3)
	end

	Remotes.TutorialPasso:FireClient(player, { Fim = true })
	task.wait(3.5)
	encerrar()
end

_G.TutorialComecar = function()
	if not _G.ModoTutorial then return end
	task.spawn(rodar)
end
