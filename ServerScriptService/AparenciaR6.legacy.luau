--[[
	AparenciaR6 — ⚠️ v105

	PEDIDO: "muda tudo para R6 — aquele boneco simplificado quadrado, que tem
	menos articulações, as animações vão ficar mais simples. Tanto no lobby
	quanto na partida. Deixa um backup caso fique ruim."

	O tipo de avatar da experiência (Game Settings > Avatar) não pode ser
	mudado por script. Então o R6 vem de um StarterPlayer.StarterCharacter R6
	(criado no Studio) — todo mundo nasce nesse corpo. Este script veste nele
	a APARÊNCIA de cada jogador (roupas, cores de pele, rosto, acessórios)
	com a HumanoidDescription do avatar dele, pra ninguém virar um boneco
	cinza igual.

	BACKUP / VOLTAR PRO R15: apague StarterPlayer.StarterCharacter (e, se
	quiser, este script). Todo o resto do código funciona nos dois tipos de
	corpo (animador procedural, cutscenes e efeitos têm mapeamento R6 e R15).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ⚠️ v105: porte pelo Físico (altura igual pra todo mundo; só Físico alto
-- deixa o corpo mais alto e mais largo) — ver PorteFisico
local Porte = require(ReplicatedStorage:WaitForChild("PorteFisico"))

-- Físico do personagem ativo: no Game vem como atributo (TeleportData, ver
-- PlayerSystems); no Lobby, direto dos dados salvos do slot ativo.
local function fisicoDe(player)
	local v = player:GetAttribute("Physical")
	if typeof(v) == "number" then return v end
	local data = _G.GetPlayerData and _G.GetPlayerData(player)
	local slot = data and type(data.CharacterSlots) == "table" and data.CharacterSlots[data.ActiveSlot]
	if type(slot) == "table" and type(slot.Attributes) == "table" and type(slot.Attributes.Physical) == "number" then
		return slot.Attributes.Physical
	end
	return 50
end

local function aplicarPorte(player, character)
	if not character or not character.Parent then return end
	local ok, err = pcall(Porte.Aplicar, character, fisicoDe(player))
	if not ok then warn("AparenciaR6: porte de " .. player.Name .. ": " .. tostring(err)) end
end

-- ⚠️ v106 — "coloca a animação do boneco andando no lobby". O ApplyDescription
-- também copia as ANIMAÇÕES do avatar do jogador — que são R15 e não tocam num
-- corpo R6 (ele deslizava parado). Depois de vestir, o Animate volta pras
-- animações padrão do R6 (o Animate padrão escuta essas trocas).
local ANIMS_R6 = {
	idle = { Animation1 = "rbxassetid://180435571", Animation2 = "rbxassetid://180435792" },
	walk = { WalkAnim = "rbxassetid://180426354" },
	run = { RunAnim = "rbxassetid://180426354" },
	jump = { JumpAnim = "rbxassetid://125750702" },
	fall = { FallAnim = "rbxassetid://180436148" },
	climb = { ClimbAnim = "rbxassetid://180436334" },
	sit = { SitAnim = "rbxassetid://178130996" },
	toolnone = { ToolNoneAnim = "rbxassetid://182393478" },
}
local function forcarAnimacoesR6(character)
	local animate = character:FindFirstChild("Animate")
	if not animate then return end
	for pasta, anims in pairs(ANIMS_R6) do
		local valor = animate:FindFirstChild(pasta)
		if valor then
			for nome, id in pairs(anims) do
				local a = valor:FindFirstChild(nome)
				if a and a:IsA("Animation") and a.AnimationId ~= id then a.AnimationId = id end
			end
		end
	end
end

local cache = {} -- [UserId] = HumanoidDescription

local function descricaoDe(userId)
	if cache[userId] then return cache[userId] end
	local ok, desc = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if ok and desc then
		cache[userId] = desc
		return desc
	end
	return nil
end

local function vestir(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end
	if humanoid.RigType ~= Enum.HumanoidRigType.R6 then return end -- só mexe no corpo R6
	local desc = player.UserId > 0 and descricaoDe(player.UserId) or nil -- jogadores de teste do Studio não têm avatar
	if desc then
		-- ⚠️ v110 — PEDIDO: "o meu personagem não ficou quadradão igual o dos meus
		-- amigos, ele é arredondado e tem a mãozinha". O avatar dele usa um PACOTE de
		-- corpo (bundle); no R6 o ApplyDescription vira CharacterMesh e arredonda o
		-- boneco. Zera as partes do corpo na cópia da descrição -> R6 quadrado pra
		-- todo mundo (roupas, cores, rosto e acessórios continuam).
		local copia = desc:Clone()
		copia.Torso = 0
		copia.LeftArm = 0
		copia.RightArm = 0
		copia.LeftLeg = 0
		copia.RightLeg = 0
		local ok, err = pcall(function()
			humanoid:ApplyDescription(copia)
		end)
		for _, m in ipairs(character:GetChildren()) do
			if m:IsA("CharacterMesh") then m:Destroy() end
		end
		if not ok then warn("AparenciaR6: não deu pra vestir " .. player.Name .. ": " .. tostring(err)) end
	end
	forcarAnimacoesR6(character)
	-- ⚠️ v107 — PEDIDO: "no lobby ele começa a animação de andar e trava antes de
	-- começar realmente a andar". O Animate que o Roblox coloca no corpo divide a
	-- velocidade da animação por HipHeight/2 quando AutomaticScalingEnabled está
	-- ligado — e no R6 o HipHeight é 0: velocidade INFINITA, a trilha de andar
	-- fica congelada no 1º quadro (pose de passo parada, deslizando). Desligado,
	-- ele usa a escala do rig (1) e o passo anda normal. (O porte pelo Físico não
	-- depende disso — PorteFisico mexe nas peças/juntas direto.)
	humanoid.AutomaticScalingEnabled = false
	-- o porte vem DEPOIS de vestir (acessórios novos entram na escala certa)
	-- e espera um instante pros dados do Lobby/TeleportData chegarem
	task.wait(1)
	aplicarPorte(player, character)
end

local function aoEntrar(player)
	player.CharacterAdded:Connect(function(character)
		task.spawn(vestir, player, character)
	end)
	-- Físico mudou (chegou pelo TeleportData, ou o jogador upou): refaz o porte
	player:GetAttributeChangedSignal("Physical"):Connect(function()
		aplicarPorte(player, player.Character)
	end)
	if player.Character then task.spawn(vestir, player, player.Character) end
end

Players.PlayerAdded:Connect(aoEntrar)
for _, p in ipairs(Players:GetPlayers()) do aoEntrar(p) end
Players.PlayerRemoving:Connect(function(p) cache[p.UserId] = nil end)
