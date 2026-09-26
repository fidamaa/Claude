--[[
	PulseInput (LocalScript) — ⚠️ v5.1: AGORA É O INPUT DO INSTINTO
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	O nome do ARQUIVO continua "PulseInput" de propósito, só pra você não
	precisar mexer na hierarquia do Studio. O conteúdo virou outra coisa.
	Pode renomear pra InstinctInput quando quiser — nada depende do nome.

	O QUE ELE FAZIA (v3/v4): escutava Q, E e R pros 2 slots de Pulso e pros
	passos do combo/QTE. Isso criava dois problemas, que agora acabaram:
	  • Q e E BRIGAVAM COM O GOLEIRO. O GKInput.local.luau usa Q e E pros
	    mergulhos DIAGONAIS (UpLeft/UpRight). Como o Pulso queria as mesmas
	    teclas, o goleiro ficava com uma tecla a menos (só R pro slot dele)
	    e o conflito continuava existindo.
	  • O combo consumia qualquer Q/E/R enquanto estava pendente, e ainda
	    ligava o Attribute "PulseComboActive" pra BLOQUEAR o mergulho do
	    goleiro no meio do combo. Esse attribute não é mais ligado por
	    ninguém — quem lê ele (GKInput) simplesmente lê nil e mergulha
	    normal, que é o comportamento certo.

	O QUE ELE FAZ AGORA: escuta DUAS teclas — R e T — e avisa o servidor
	qual SLOT de Arma (Instinto) apertou. Só.
	  • A maior parte dos Instintos é PASSIVA e nem olha pra tecla:
	    apertar R/T com um deles equipado não faz nada, e está certo.
	  • Os Instintos com Tecla = "R" (ver PulseInstinctData.luau — o nome do
	    campo continua "R" por histórico, mas agora significa "precisa de
	    aperto manual", não uma tecla física fixa) só acontecem quando o
	    jogador aperta a tecla do slot ONDE aquele Instinto está equipado —
	    R pro slot 1, T pro slot 2 (ver EquippedList em
	    InstinctController.legacy.luau).
	  • ⚠️ v78: antes só existia R (slot 1). Agora que todo mundo pode ter
	    2 Armas ativas ao mesmo tempo, precisa de uma 2ª tecla pra ativar
	    a do slot 2 — sem isso, se as duas armas equipadas precisassem de
	    aperto manual, a do slot 2 nunca teria como disparar.
	  • ⚠️ v79: a 2ª tecla ERA H, mas o usuário pediu pra trocar de lugar
	    com o Pedir Passe (que também usava T) — agora Pedir Passe é H
	    (ver PassRequestInput.local.luau) e a Arma slot 2 é T. T ficou
	    livre pro goleiro (ele nunca pede passe, então nunca usava T; e
	    o goleiro pode ter Armas com gatilho manual igual jogador de
	    linha), então não há conflito.
	  • R e T valem IGUAL pra goleiro e jogador de linha. Ninguém fica com
	    uma tecla a menos.

	Teclas hoje: R = Arma slot 1 · T = Arma slot 2 · H = Pedir Passe ·
	V = Instinct Mode · Q/E/Z/X/C = goleiro.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

local LocalPlayer = Players.LocalPlayer

local INSTINCT_KEY = Enum.KeyCode.R -- Arma slot 1
local INSTINCT_KEY_SLOT2 = Enum.KeyCode.T -- ⚠️ v79: Arma slot 2 (trocou de lugar com Pedir Passe, ver comentário acima)

-- Só educação com a rede: evita mandar dez eventos por segundo se o
-- jogador martelar a tecla. O cooldown de verdade é do servidor.
local SEND_DEBOUNCE = 0.15
local lastSent = 0

-- ⚠️ v67 FIX — "de vez em quando o Chute Direto sai pra longe, pra direita,
-- pra esquerda, ou pra trás — direções que não são pra onde estou mirando."
--
-- CAUSA: Remotes.ActivateInstinct era disparado SEM mira nenhuma. Do outro
-- lado, _G.InstinctExecuteShot chama _G.PulseComputeShotTarget, que lê
-- LastAimPoint[player] — e esse campo só é preenchido por Remotes.UsePulse
-- (Hissatsu). Ou seja: o Chute Direto usava o ponto de mira SOBRADO da
-- última Hissatsu que você tinha usado (podendo ser de minutos antes, em
-- qualquer direção), ou nada, caindo na mira automática de canto.
--
-- Agora a mira vai junto, calculada do mesmo jeito que a da Hissatsu
-- (HissatsuInput.computeAimPoint), incluindo o tratamento de mobile.
local function computeAimPoint()
	if _G.HissatsuComputeAimPoint then
		local p = _G.HissatsuComputeAimPoint()
		if typeof(p) == "Vector3" then return p end
	end
	-- fallback: direção da câmera a partir da bola
	local camera = workspace.CurrentCamera
	local character = LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local bola = workspace:FindFirstChild("bola")
	local origem = (bola and bola.Position) or (root and root.Position) or camera.CFrame.Position
	return origem + camera.CFrame.LookVector * 60
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	local slot
	if input.KeyCode == INSTINCT_KEY then
		slot = 1
	elseif input.KeyCode == INSTINCT_KEY_SLOT2 then
		slot = 2
	else
		return
	end
	if not LocalPlayer.Character then return end

	local agora = os.clock()
	if agora - lastSent < SEND_DEBOUNCE then return end
	lastSent = agora

	Remotes.ActivateInstinct:FireServer(computeAimPoint(), slot) -- ⚠️ v67: manda a mira junto · v78: manda o slot (1=R, 2=T)
end)

-- ⚠️ MOBILE: exposto pros botões de Arma (R=slot1, T=slot2) de
-- MobileControls.local.luau. v78: agora recebe qual slot foi apertado
-- (default 1, pra não quebrar quem já chamava sem argumento).
_G.MobileActivateInstinct = function(slot)
	if not LocalPlayer.Character then return end

	local agora = os.clock()
	if agora - lastSent < SEND_DEBOUNCE then return end
	lastSent = agora

	Remotes.ActivateInstinct:FireServer(computeAimPoint(), (slot == 2 and 2) or 1) -- ⚠️ v67: manda a mira junto · v78: manda o slot
end

print("✅ Input de Arma carregado (R = slot 1, T = slot 2). Q e E ficaram livres pro goleiro.")
