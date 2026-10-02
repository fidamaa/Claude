--[[
	CosmeticosLobbyClient (LocalScript) — ⚠️ v110
	LOCAL: StarterPlayerScripts (place Lobby)

	PEDIDO: "inclua todos os cosméticos... coloque tudo possível, implemente
	no jogo... faça animação para cada comemoração... 15 emotes...".

	O lado VISUAL dos cosméticos no Lobby (os dados moram no Cosmeticos.luau,
	os atributos "Cosm_*" são postos pelo ShopServer):
	  • moldura que gira na placa de nome (a placa é do PlayerNametagSystem);
	  • AURA de cada jogador;
	  • CHAT: nome do personagem na cor do chat + a tag;
	  • EMOTES: tecla G (ou botão EMOTE no celular) — todo mundo vê. As poses
	    são as mesmas da partida, tocadas aqui por um reprodutor pequeno (o
	    Lobby usa o Animate padrão do Roblox; durante o emote ele é calado).
	    Andou = o emote para.
	  • _G.PreviewEmoteLobby(id) — o TESTAR da Loja: toca o emote/comemoração
	    só na sua tela, mesmo sem ter comprado.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")

local Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos"))
local shopEvents = ReplicatedStorage:WaitForChild("ShopEvents", 30)
local TocarEmoteLobby = shopEvents and shopEvents:WaitForChild("TocarEmoteLobby", 30)
local EmoteLobby = shopEvents and shopEvents:WaitForChild("EmoteLobby", 30)

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local TEX_BRILHO = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FOGO = "rbxasset://textures/particles/fire_main.dds"
local TEX_FUMACA = "rbxasset://textures/particles/smoke_main.dds"

local function arcoIris()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 110)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 130)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 180, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
	})
end

-- ============================================================
-- MOLDURA QUE GIRA (placas de nome de todo mundo)
-- ============================================================
local gradientes = {}
local function procurarGradientes(character)
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("UIGradient") and d:GetAttribute("Gira") then gradientes[d] = true end
	end
end
task.spawn(function()
	while true do
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then procurarGradientes(p.Character) end
		end
		task.wait(1)
	end
end)
RunService.RenderStepped:Connect(function(dt)
	for g in pairs(gradientes) do
		if g.Parent then
			g.Rotation = (g.Rotation + dt * 90) % 360
		else
			gradientes[g] = nil
		end
	end
end)

-- ============================================================
-- AURA (mesmos estilos da partida)
-- ============================================================
local function emissor(pai, props)
	local e = Instance.new("ParticleEmitter")
	e.Name = "AuraCosmetica"
	e.LightEmission = 0.8
	e.LightInfluence = 0
	for k, v in pairs(props) do e[k] = v end
	e.Parent = pai
	return e
end

-- ⚠️ v114 — AURA DISCRETA. PEDIDO: "Aura: VFX discreto em volta do corpo, não um
-- highlight." Antes a aura saía toda dos pés, concentrada num ponto; agora o mesmo
-- estilo é espalhado pelo corpo (tronco, pernas e braços), com menos partículas,
-- menores, mais transparentes e subindo devagar — presença sutil, sem pintar o
-- personagem nem tapar o uniforme (nada de Highlight/ForceField).
local PARTES_AURA = {
	"UpperTorso", "LowerTorso", "RightLowerLeg", "LeftLowerLeg", "RightLowerArm", "LeftLowerArm", -- R15
	"Torso", "Right Leg", "Left Leg", "Right Arm", "Left Arm", -- R6
}

local function espalhar(character, props)
	local alvos = {}
	for _, nome in ipairs(PARTES_AURA) do
		local p = character:FindFirstChild(nome)
		if p and p:IsA("BasePart") then table.insert(alvos, p) end
	end
	if #alvos == 0 then return end
	local p = table.clone(props)
	p.Rate = math.max(0.8, (p.Rate or 7) * 1.3 / #alvos)
	if p.Size then
		local ks = {}
		for _, kp in ipairs(p.Size.Keypoints) do
			table.insert(ks, NumberSequenceKeypoint.new(kp.Time, kp.Value * 0.55, kp.Envelope * 0.55))
		end
		p.Size = NumberSequence.new(ks)
	end
	if p.Transparency then
		local ks = {}
		for _, kp in ipairs(p.Transparency.Keypoints) do
			table.insert(ks, NumberSequenceKeypoint.new(kp.Time, 0.4 + 0.6 * kp.Value))
		end
		p.Transparency = NumberSequence.new(ks)
	end
	if p.Speed then p.Speed = NumberRange.new(p.Speed.Min * 0.6, p.Speed.Max * 0.6) end
	p.Shape = Enum.ParticleEmitterShape.Box
	p.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	p.SpreadAngle = Vector2.new(180, 180)
	p.EmissionDirection = Enum.NormalId.Top
	p.Acceleration = p.Acceleration or Vector3.new(0, 1.2, 0)
	for _, alvo in ipairs(alvos) do emissor(alvo, p) end
end

-- ⚠️ v114b — "Coloca uma aura em volta do personagem com o VFX da hora… discretinho."
-- Além das partículas espalhadas, uma NÉVOA DE LUZ suave atrás do tronco: nuvens
-- grandes e bem transparentes que nascem, crescem e somem sem se mexer — dá o
-- contorno luminoso de aura sem ser highlight nem pintar o corpo.
local function halo(character, estilo, cor)
	local tronco = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	if not tronco then return end
	local sombra = estilo == "Sombra"
	emissor(tronco, {
		Texture = TEX_FUMACA, Color = cor, Rate = 2.4, Lifetime = NumberRange.new(1.6, 2.2),
		Speed = NumberRange.new(0, 0.3), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20),
		LightEmission = sombra and 0 or 0.9, ZOffset = -1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.4), NumberSequenceKeypoint.new(0.5, 5), NumberSequenceKeypoint.new(1, 4.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, sombra and 0.78 or 0.86), NumberSequenceKeypoint.new(1, 1) }),
	})
end

local function montarAura(player)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local velha = root:FindFirstChild("AuraCosmeticaAnexo")
	if velha then velha:Destroy() end
	for _, d in ipairs(character:GetDescendants()) do
		if d:IsA("ParticleEmitter") and d.Name == "AuraCosmetica" then d:Destroy() end
	end
	local item = Cosmeticos.Equipado(player, "Aura")
	if not item then return end
	local estilo = item.Estilo
	local base = {
		Texture = TEX_BRILHO, Color = ColorSequence.new(item.Cor), Rate = 7, Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
	}
	if estilo == "Fogo" then
		base.Texture = TEX_FOGO
		base.Rate = 10
		base.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
		base.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(230, 60, 20))
	elseif estilo == "Sombra" then
		base.Texture = TEX_FUMACA
		base.LightEmission = 0
		base.Rate = 6
		base.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.2) })
		base.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		base.Color = ColorSequence.new(Color3.fromRGB(40, 20, 60), Color3.fromRGB(10, 5, 20))
	elseif estilo == "ArcoIris" then
		base.Color = arcoIris()
		base.Rate = 10
	elseif estilo == "Galaxia" then
		base.Color = ColorSequence.new(Color3.fromRGB(160, 100, 255), Color3.fromRGB(60, 180, 255))
		base.Rate = 9
		espalhar(character, {
			Texture = TEX_FUMACA, Color = ColorSequence.new(Color3.fromRGB(80, 40, 160)), Rate = 4, LightEmission = 0.5,
			Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(0.5, 1),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		})
	elseif estilo == "Petalas" then
		base.Rate = 6
		base.Speed = NumberRange.new(0.6, 1.4)
		base.Acceleration = Vector3.new(0, -1.5, 0)
		base.RotSpeed = NumberRange.new(-180, 180)
		base.Rotation = NumberRange.new(0, 360)
		base.Size = NumberSequence.new(0.28)
		base.Texture = ""
	elseif estilo == "Gelo" then
		base.Speed = NumberRange.new(0.5, 1.2)
		base.Rate = 9
	elseif estilo == "Raio" then
		base.Speed = NumberRange.new(4, 7)
		base.Lifetime = NumberRange.new(0.2, 0.4)
		base.Rate = 14
	elseif estilo == "Estrelas" then
		base.Rate = 8
		base.Speed = NumberRange.new(0.3, 0.8)
		base.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0) })
	end
	espalhar(character, base)
	halo(character, estilo, base.Color)
end

local function acompanhar(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.3)
		montarAura(player)
	end)
	player:GetAttributeChangedSignal("Cosm_Aura"):Connect(function() montarAura(player) end)
	if player.Character then task.defer(montarAura, player) end
end
Players.PlayerAdded:Connect(acompanhar)
for _, p in ipairs(Players:GetPlayers()) do acompanhar(p) end

-- ============================================================
-- CHAT
-- ============================================================
local function hex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
local function escapar(s)
	return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end
pcall(function()
	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then return end
	TextChatService.OnIncomingMessage = function(message)
		local fonte = message.TextSource
		if not fonte then return end
		local player = Players:GetPlayerByUserId(fonte.UserId)
		if not player then return end
		local props = Instance.new("TextChatMessageProperties")
		local corChat = Cosmeticos.Equipado(player, "ChatColor")
		local tag = Cosmeticos.Equipado(player, "Tag")
		local nome = player:GetAttribute("NomePersonagem")
		if typeof(nome) ~= "string" or nome == "" then nome = player.DisplayName end
		local prefixo = string.format('<font color="#%s">%s:</font>', hex(corChat and corChat.Cor or Color3.new(1, 1, 1)), escapar(nome))
		if tag then
			prefixo = string.format('<font color="#%s">[%s]</font> ', hex(tag.Cor), escapar(tag.Nome)) .. prefixo
		end
		props.PrefixText = prefixo
		return props
	end
end)

-- ============================================================
-- EMOTES — reprodutor de pose (mesma convenção do AnimacoesProcedurais)
-- ============================================================
local MAPA_R6 = {
	Root = { "HumanoidRootPart", "RootJoint" }, Neck = { "Torso", "Neck" },
	RShoulder = { "Torso", "Right Shoulder" }, LShoulder = { "Torso", "Left Shoulder" },
	RHip = { "Torso", "Right Hip" }, LHip = { "Torso", "Left Hip" },
}
local MAPA_R15 = {
	Root = { "LowerTorso", "Root" }, Waist = { "UpperTorso", "Waist" }, Neck = { "Head", "Neck" },
	RShoulder = { "RightUpperArm", "RightShoulder" }, LShoulder = { "LeftUpperArm", "LeftShoulder" },
	RElbow = { "RightLowerArm", "RightElbow" }, LElbow = { "LeftLowerArm", "LeftElbow" },
	RHip = { "RightUpperLeg", "RightHip" }, LHip = { "LeftUpperLeg", "LeftHip" },
	RKnee = { "RightLowerLeg", "RightKnee" }, LKnee = { "LeftLowerLeg", "LeftKnee" },
}

local function juntaDe(obj)
	if not obj then return nil end
	if obj:IsA("Motor6D") then
		-- a pose vai no C0 descontando o Transform que o motor/Animate impôs
		local c0Original = obj.C0
		local pos = CFrame.new(c0Original.Position)
		local base = obj.C1.Rotation
		return {
			Escrever = function(r) obj.C0 = pos * r * base * obj.Transform:Inverse() end,
			Zerar = function() obj.C0 = c0Original end,
		}
	elseif obj:IsA("AnimationConstraint") and obj.Attachment0 then
		local base = obj.Attachment0.CFrame.Rotation
		local baseInv = base:Inverse()
		return {
			Escrever = function(r) obj.Transform = baseInv * r * base end,
			Zerar = function() obj.Transform = CFrame.identity end,
		}
	end
	return nil
end

local function mapear(model)
	local r15 = model:FindFirstChild("UpperTorso") ~= nil
	local juntas = {}
	for nome, caminho in pairs(r15 and MAPA_R15 or MAPA_R6) do
		local pai = model:FindFirstChild(caminho[1])
		local j = juntaDe(pai and pai:FindFirstChild(caminho[2]))
		if j then juntas[nome] = j end
	end
	return juntas, r15
end

local function smooth(u) u = math.clamp(u, 0, 1) return u * u * (3 - 2 * u) end

local function misturar(a, b, u)
	local r = {}
	for k, v in pairs(a) do r[k] = v:Lerp(b[k] or Vector3.zero, u) end
	for k, v in pairs(b) do if r[k] == nil then r[k] = Vector3.zero:Lerp(v, u) end end
	return r
end

local function amostrar(quadros, t)
	if t <= quadros[1][1] then return quadros[1][2] end
	for i = 1, #quadros - 1 do
		local a, b = quadros[i], quadros[i + 1]
		if t <= b[1] then
			local u = (b[1] > a[1]) and (t - a[1]) / (b[1] - a[1]) or 1
			return misturar(a[2], b[2], smooth(u))
		end
	end
	return quadros[#quadros][2]
end

-- R6 sem joelho: flexão de quadril pra frente menor, quadril só desce tombado
local function adaptarR6(pose)
	local p = table.clone(pose)
	local root = p.Root or Vector3.zero
	local tombado = math.abs(root.X) > 45 or math.abs(root.Z) > 45
	if p.RootPos and not tombado then
		p.RootPos = Vector3.new(p.RootPos.X, math.max(p.RootPos.Y, 0), p.RootPos.Z)
	end
	for _, nome in ipairs({ "RHip", "LHip" }) do
		local a = p[nome]
		if a and not tombado and a.X > 0 then p[nome] = Vector3.new(a.X * 0.7, a.Y, a.Z * 0.6) end
	end
	return p
end

local tocando = {} -- [character] = { Item, Inicio, Juntas, R15, Local }
local ENTRADA, SAIDA = 0.12, 0.25

local function pararEmote(character)
	local e = tocando[character]
	if not e then return end
	tocando[character] = nil
	for _, j in pairs(e.Juntas) do pcall(j.Zerar) end
end

local function tocarEmote(character, id)
	local item = Cosmeticos.Item(id)
	if not item or not item.Quadros then return end
	if not character or not character:FindFirstChildOfClass("Humanoid") then return end
	pararEmote(character)
	local juntas, r15 = mapear(character)
	if next(juntas) == nil then return end
	tocando[character] = { Item = item, Inicio = os.clock(), Juntas = juntas, R15 = r15 }
end

RunService.Stepped:Connect(function()
	local agora = os.clock()
	for character, e in pairs(tocando) do
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		local root = character:FindFirstChild("HumanoidRootPart")
		local t = agora - e.Inicio
		local dur = e.Item.Duracao
		local andando = root and Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude > 3
		if not character.Parent or not humanoid or humanoid.Health <= 0 or t >= dur or (andando and t > 0.25) then
			pararEmote(character)
		else
			-- cala o Animate enquanto o emote toca
			local animator = humanoid:FindFirstChildOfClass("Animator")
			if animator then
				for _, track in ipairs(animator:GetPlayingAnimationTracks()) do track:Stop(0) end
			end
			local tt = t
			local loop = e.Item.Loop
			if loop and tt > loop[1] and t < dur - SAIDA then
				tt = loop[1] + (tt - loop[1]) % (loop[2] - loop[1])
			end
			local pose = amostrar(e.Item.Quadros, math.min(tt, e.Item.Quadros[#e.Item.Quadros][1]))
			if not e.R15 then pose = adaptarR6(pose) end
			local peso = 1
			if t < ENTRADA then peso = smooth(t / ENTRADA) end
			if dur - t < SAIDA then peso = math.min(peso, smooth((dur - t) / SAIDA)) end
			for nome, junta in pairs(e.Juntas) do
				local a = (pose[nome] or Vector3.zero) * peso
				local r = CFrame.Angles(math.rad(a.X), math.rad(a.Y), math.rad(a.Z))
				if nome == "Root" and pose.RootPos then r = CFrame.new(pose.RootPos * peso) * r end
				junta.Escrever(r)
			end
		end
	end
end)

if EmoteLobby then
	EmoteLobby.OnClientEvent:Connect(function(character, id)
		if typeof(character) == "Instance" and character:IsA("Model") then tocarEmote(character, id) end
	end)
end

-- TESTAR da Loja: só na sua tela
_G.PreviewEmoteLobby = function(id)
	if localPlayer.Character then tocarEmote(localPlayer.Character, id) end
end

local function pedirEmote()
	if TocarEmoteLobby and Cosmeticos.Equipado(localPlayer, "Emote") then TocarEmoteLobby:FireServer() end
end

UserInputService.InputBegan:Connect(function(input, processado)
	if processado then return end
	if input.KeyCode == Enum.KeyCode.G then pedirEmote() end
end)

if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteMobile"
	gui.ResetOnSpawn = false
	gui.Parent = playerGui
	local b = Instance.new("TextButton")
	-- canto ESQUERDO, no meio da tela: o canto direito de cima é do painel de
	-- missões (Lobby) / debugger (partida), o de baixo é dos botões de jogo
	b.AnchorPoint = Vector2.new(0, 0.5)
	b.Size = UDim2.fromOffset(64, 32)
	b.Position = UDim2.new(0, 16, 0.42, 0)
	b.BackgroundColor3 = Color3.fromRGB(21, 24, 34)
	b.BackgroundTransparency = 0.15
	b.Text = "EMOTE"
	b.TextColor3 = Color3.fromRGB(125, 185, 255)
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 12
	b.Parent = gui
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(76, 156, 255)
	s.Transparency = 0.5
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	local function atualizar()
		b.Visible = Cosmeticos.Equipado(localPlayer, "Emote") ~= nil
	end
	atualizar()
	localPlayer:GetAttributeChangedSignal("Cosm_Emote"):Connect(atualizar)
	b.Activated:Connect(pedirEmote)
end

print("✅ CosmeticosLobbyClient carregado (placa, aura, chat, emotes)")
