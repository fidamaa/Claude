--[[
	CosmeticosClient (LocalScript) — ⚠️ v110
	LOCAL: StarterPlayerScripts (place Game)

	PEDIDO: "inclua todos os cosméticos... implemente no jogo, implemente
	também o nome personalizado que já tem nos slots dentro do jogo" +
	"cutscenes de flow igual as dos animes (o flow do Isagi, do Bachira...)".

	Tudo que é VISUAL dos cosméticos na partida (os dados moram no
	Cosmeticos.luau, os atributos "Cosm_*"/"NomePersonagem" vêm do Lobby):
	  • PLACA DE NOME em cima de cada jogador (menos você): nome do slot,
	    título, tag, cor do nome e moldura (borda em degradê que gira).
	  • CHAT: nome do slot com a cor do chat + a tag.
	  • AURA: partículas sutis no corpo.
	  • EFEITO DE GOL: explode no gol quando o dono marca.
	  • EMOTE: tecla G (ou botão EMOTE no celular) toca o emote equipado.
	  • FLOW: a cena de ativação estilo anime (faixa com o close no rosto,
	    olho brilhando com o rastro de luz, o motivo do personagem — peças
	    de quebra-cabeça do Isagi, o monstro do Bachira, a coroa do Barou...)
	    pra quem ativou; os outros veem um aviso curto. Durante o Flow, os
	    olhos deixam o rastro de luz e o corpo solta a aura da cor do Flow.
	    Nada disso congela o jogo.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local TextChatService = game:GetService("TextChatService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

-- ⚠️ v110: string.upper não põe acento em maiúscula ("Fúria" virava "FúRIA").
-- Converte também as letras acentuadas (UTF-8 à..þ → À..Þ).
local function maiusculas(s)
	s = string.upper(tostring(s))
	return (s:gsub("\195([\160-\190])", function(c)
		local b = string.byte(c)
		if b ~= 183 then return "\195" .. string.char(b - 32) end
	end))
end

local Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos"))
local pastaRemotes = ReplicatedStorage:WaitForChild("CosmeticosRemotes", 30)
if not pastaRemotes then
	warn("CosmeticosClient: CosmeticosRemotes não apareceu")
	return
end
local TocarEmote = pastaRemotes:WaitForChild("TocarEmote")
local FlowAtivado = pastaRemotes:WaitForChild("FlowAtivado")
local EfeitoDeGol = pastaRemotes:WaitForChild("EfeitoDeGol")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local TEX_BRILHO = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FOGO = "rbxasset://textures/particles/fire_main.dds"
local TEX_FUMACA = "rbxasset://textures/particles/smoke_main.dds"

local function nomeDe(player)
	local n = player:GetAttribute("NomePersonagem")
	if typeof(n) == "string" and n ~= "" then return n end
	return player.DisplayName
end

local function tween(obj, tempo, props, estilo, direcao)
	local t = TweenService:Create(obj, TweenInfo.new(tempo, estilo or Enum.EasingStyle.Quad, direcao or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function arcoIris()
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 110)), ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 210, 80)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(90, 230, 130)), ColorSequenceKeypoint.new(0.75, Color3.fromRGB(80, 180, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 110, 255)),
	})
end

-- ============================================================
-- PLACA DE NOME
-- ============================================================
local gradientesGirando = {} -- [UIGradient] = true

local function montarPlaca(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then return end
	local antiga = character:FindFirstChild("PlacaCosmeticos")
	if antiga then antiga:Destroy() end
	if player == localPlayer then return end -- a sua não aparece pra você
	local corTime = player.Team and player.TeamColor.Color or nil
	local placa = Cosmeticos.MontarPlaca(Cosmeticos.DadosDaPlaca(player, nomeDe(player), corTime))
	placa.Adornee = head
	placa.Parent = character -- dentro do personagem: a Névoa esconde junto
	for _, d in ipairs(placa:GetDescendants()) do
		if d:IsA("UIGradient") and d:GetAttribute("Gira") then gradientesGirando[d] = true end
	end
end

RunService.RenderStepped:Connect(function(dt)
	for g in pairs(gradientesGirando) do
		if g.Parent then
			g.Rotation = (g.Rotation + dt * 90) % 360
		else
			gradientesGirando[g] = nil
		end
	end
end)

-- ============================================================
-- AURA
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
	local cor = ColorSequence.new(item.Cor)
	local estilo = item.Estilo
	local base = {
		Texture = TEX_BRILHO, Color = cor, Rate = 7, Lifetime = NumberRange.new(0.8, 1.4),
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

-- ============================================================
-- JOGADORES: placa + aura (e refaz quando muda algo)
-- ============================================================
local ATRIBUTOS_VISUAIS = { NomePersonagem = true, Cosm_Frame = true, Cosm_Title = true, Cosm_Tag = true, Cosm_NameColor = true, Cosm_Aura = true }

local function aplicarTudo(player)
	montarPlaca(player)
	montarAura(player)
end

local function acompanhar(player)
	player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.2)
		aplicarTudo(player)
	end)
	player.AttributeChanged:Connect(function(nome)
		if ATRIBUTOS_VISUAIS[nome] then aplicarTudo(player) end
	end)
	player:GetPropertyChangedSignal("Team"):Connect(function() montarPlaca(player) end)
	if player.Character then task.defer(aplicarTudo, player) end
end
Players.PlayerAdded:Connect(acompanhar)
for _, p in ipairs(Players:GetPlayers()) do acompanhar(p) end

-- ============================================================
-- CHAT: nome do slot com a cor do chat e a tag
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
		local cor = corChat and corChat.Cor or (player.Team and player.TeamColor.Color) or Color3.new(1, 1, 1)
		local prefixo = string.format('<font color="#%s">%s:</font>', hex(cor), escapar(nomeDe(player)))
		if tag then
			prefixo = string.format('<font color="#%s">[%s]</font> ', hex(tag.Cor), escapar(tag.Nome)) .. prefixo
		end
		props.PrefixText = prefixo
		return props
	end
end)

-- ============================================================
-- EMOTE: tecla G / botão no celular
-- ============================================================
UserInputService.InputBegan:Connect(function(input, processado)
	if processado then return end
	if input.KeyCode == Enum.KeyCode.G then
		if Cosmeticos.Equipado(localPlayer, "Emote") then TocarEmote:FireServer() end
	end
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
	b.Activated:Connect(function() TocarEmote:FireServer() end)
end

-- ============================================================
-- EFEITO DE GOL
-- ============================================================
local pastaFX = Instance.new("Folder")
pastaFX.Name = "CosmeticosFX"
pastaFX.Parent = workspace

local function ancora(pos, vida)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.CFrame = CFrame.new(pos)
	p.Parent = pastaFX
	Debris:AddItem(p, vida or 5)
	return p
end

local function explosao(pos, props, quantidade, vida)
	local p = ancora(pos, vida)
	local e = Instance.new("ParticleEmitter")
	e.Rate = 0
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Texture = TEX_BRILHO
	for k, v in pairs(props) do e[k] = v end
	e.Parent = p
	e:Emit(quantidade)
	return p, e
end

local function neonPart(tamanho, cf, cor, forma)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = cor
	p.Size = tamanho
	p.CFrame = cf
	if forma then p.Shape = forma end
	p.Parent = pastaFX
	return p
end

local function flashTela(cor, forca, tempo)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = cor:Lerp(Color3.new(1, 1, 1), 0.5)
	cc.Brightness = forca
	cc.Parent = Lighting
	tween(cc, tempo, { Brightness = 0, TintColor = Color3.new(1, 1, 1) })
	Debris:AddItem(cc, tempo + 0.1)
end

local function onda(pos, cor, raio, tempo, espessura)
	local anel = neonPart(Vector3.new(espessura or 0.4, 1, 1), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), cor, Enum.PartType.Cylinder)
	anel.Transparency = 0.2
	tween(anel, tempo, { Size = Vector3.new(espessura or 0.4, raio * 2, raio * 2), Transparency = 1 })
	Debris:AddItem(anel, tempo + 0.1)
end

local function raio3D(de, ate, cor, largura)
	local pontos = { de }
	local n = 7
	for i = 1, n - 1 do
		local p = de:Lerp(ate, i / n) + Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 4
		table.insert(pontos, p)
	end
	table.insert(pontos, ate)
	for i = 1, #pontos - 1 do
		local a, b = pontos[i], pontos[i + 1]
		local seg = neonPart(Vector3.new(largura or 0.35, largura or 0.35, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), cor)
		tween(seg, 0.35, { Transparency = 1 })
		Debris:AddItem(seg, 0.4)
	end
end

local ESTILOS_GOL = {}

ESTILOS_GOL.Fogos = function(pos, cor)
	for i = 1, 6 do
		task.delay(i * 0.18, function()
			local ini = pos + Vector3.new(math.random(-12, 12), -2, math.random(-6, 6))
			local alto = ini + Vector3.new(math.random(-3, 3), math.random(16, 26), math.random(-3, 3))
			local c = Color3.fromHSV(math.random(), 0.7, 1)
			local foguete = neonPart(Vector3.new(0.4, 0.4, 0.4), CFrame.new(ini), c, Enum.PartType.Ball)
			tween(foguete, 0.55, { CFrame = CFrame.new(alto) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			task.delay(0.55, function()
				foguete:Destroy()
				explosao(alto, {
					Color = ColorSequence.new(c), Speed = NumberRange.new(14, 22), Lifetime = NumberRange.new(0.8, 1.3),
					SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -12, 0), Drag = 2,
					Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
				}, 70, 3)
			end)
		end)
	end
end

ESTILOS_GOL.Confete = function(pos)
	for _, c in ipairs({ Color3.fromRGB(255, 90, 120), Color3.fromRGB(255, 220, 80), Color3.fromRGB(90, 200, 255), Color3.fromRGB(110, 235, 130), Color3.fromRGB(200, 130, 255) }) do
		explosao(pos + Vector3.new(0, 6, 0), {
			Texture = "", Color = ColorSequence.new(c), Speed = NumberRange.new(12, 20), Lifetime = NumberRange.new(2.5, 3.5),
			SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -9, 0), Drag = 1.5,
			RotSpeed = NumberRange.new(-300, 300), Rotation = NumberRange.new(0, 360), LightEmission = 0.3,
			Size = NumberSequence.new(0.35),
		}, 40, 5)
	end
end

ESTILOS_GOL.Flash = function(pos, cor)
	flashTela(cor, 0.6, 0.5)
	for i = 0, 2 do
		task.delay(i * 0.15, function() onda(pos, Color3.fromHSV((i * 0.33) % 1, 0.6, 1), 22, 0.7) end)
	end
end

ESTILOS_GOL.Estrelas = function(pos, cor)
	local p = ancora(pos + Vector3.new(0, 22, 0), 5)
	p.Size = Vector3.new(24, 0.2, 12)
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_BRILHO
	e.Color = ColorSequence.new(cor)
	e.LightEmission = 1
	e.Rate = 120
	e.Lifetime = NumberRange.new(1.4, 2)
	e.Speed = NumberRange.new(10, 14)
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0.2) })
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Parent = p
	task.delay(1.8, function() e.Enabled = false end)
end

ESTILOS_GOL.Fogo = function(pos)
	explosao(pos, {
		Texture = TEX_FOGO, Color = ColorSequence.new(Color3.fromRGB(255, 210, 90), Color3.fromRGB(220, 50, 20)),
		Speed = NumberRange.new(10, 24), Lifetime = NumberRange.new(0.6, 1.1), SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top, Drag = 2, LightEmission = 0.8,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
	}, 60, 3)
	onda(pos, Color3.fromRGB(255, 140, 40), 18, 0.5)
end

ESTILOS_GOL.Raio = function(pos, cor)
	flashTela(cor, 0.5, 0.35)
	for i = 1, 5 do
		task.delay((i - 1) * 0.12, function()
			local alvo = pos + Vector3.new(math.random(-8, 8), 0, math.random(-4, 4))
			raio3D(alvo + Vector3.new(math.random(-4, 4), 40, 0), alvo, cor, 0.5)
			explosao(alvo, { Color = ColorSequence.new(cor), Speed = NumberRange.new(8, 16), Lifetime = NumberRange.new(0.3, 0.5), SpreadAngle = Vector2.new(180, 180) }, 20, 2)
		end)
	end
end

ESTILOS_GOL.Petalas = function(pos, cor)
	explosao(pos + Vector3.new(0, 4, 0), {
		Texture = "", Color = ColorSequence.new(cor, Color3.fromRGB(255, 210, 225)), Speed = NumberRange.new(6, 12),
		Lifetime = NumberRange.new(2.5, 3.5), SpreadAngle = Vector2.new(180, 60), Acceleration = Vector3.new(2, -3, 0), Drag = 1,
		RotSpeed = NumberRange.new(-200, 200), Rotation = NumberRange.new(0, 360), LightEmission = 0.4, Size = NumberSequence.new(0.45),
	}, 120, 5)
end

ESTILOS_GOL.Bolhas = function(pos, cor)
	explosao(pos, {
		Color = ColorSequence.new(cor), Speed = NumberRange.new(3, 7), Lifetime = NumberRange.new(2, 3), SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 2, 0), LightEmission = 0.4,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1.4) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(0.9, 0.5), NumberSequenceKeypoint.new(1, 1) }),
	}, 70, 4)
end

ESTILOS_GOL.Neve = function(pos, cor)
	ESTILOS_GOL.Estrelas(pos, cor)
	onda(pos, Color3.fromRGB(200, 240, 255), 16, 0.8)
end

ESTILOS_GOL.Moedas = function(pos)
	for i = 1, 26 do
		local c = neonPart(Vector3.new(0.2, 1, 1), CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 205, 60), Enum.PartType.Cylinder)
		c.Material = Enum.Material.Metal
		local vel = Vector3.new(math.random(-10, 10), math.random(18, 28), math.random(-6, 6))
		local t0 = os.clock()
		local conexao
		conexao = RunService.Heartbeat:Connect(function()
			local t = os.clock() - t0
			if t > 2 or not c.Parent then
				conexao:Disconnect()
				c:Destroy()
				return
			end
			local p = pos + vel * t + Vector3.new(0, -24, 0) * t * t / 2
			c.CFrame = CFrame.new(p) * CFrame.Angles(t * 9 + i, 0, math.rad(90))
		end)
	end
end

ESTILOS_GOL.Coracoes = function(pos, cor)
	-- contorno de coração feito de brilhos, crescendo em cima do gol
	local centro = pos + Vector3.new(0, 10, 0)
	for i = 0, 39 do
		local t = i / 40 * math.pi * 2
		local x = 16 * math.sin(t) ^ 3
		local y = 13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)
		local ponto = centro + Vector3.new(x * 0.45, y * 0.45, 0)
		task.delay(i * 0.012, function()
			explosao(ponto, { Color = ColorSequence.new(cor), Speed = NumberRange.new(0.5, 1.5), Lifetime = NumberRange.new(1.2, 1.8),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }) }, 3, 3)
		end)
	end
end

ESTILOS_GOL.Onda = function(pos, cor)
	for i = 0, 3 do
		task.delay(i * 0.2, function() onda(pos, cor, 30, 0.9, 0.6) end)
	end
	explosao(pos, { Color = ColorSequence.new(cor), Speed = NumberRange.new(20, 30), Lifetime = NumberRange.new(0.5, 0.8), SpreadAngle = Vector2.new(180, 10) }, 60, 2)
end

ESTILOS_GOL.Aurora = function(pos, cor)
	local base = ancora(pos, 4.5)
	local cores = { Color3.fromRGB(110, 255, 170), Color3.fromRGB(90, 200, 255), Color3.fromRGB(190, 120, 255) }
	for i = 1, 3 do
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(-18, 14 + i * 3, i * 2)
		a0.Parent = base
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(18, 14 + i * 3, i * 2)
		a1.Parent = base
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Width0 = 7
		beam.Width1 = 7
		beam.CurveSize0 = 6
		beam.CurveSize1 = -6
		beam.Segments = 30
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(cores[i], cores[i % 3 + 1])
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = base
		local t0 = os.clock()
		local conexao
		conexao = RunService.Heartbeat:Connect(function()
			if not beam.Parent then conexao:Disconnect() return end
			local t = os.clock() - t0
			beam.CurveSize0 = 6 * math.sin(t * 2 + i)
			beam.CurveSize1 = -6 * math.cos(t * 1.7 + i)
			if t > 3.5 then beam.Transparency = NumberSequence.new(math.clamp((t - 3.5) / 0.8, 0, 1) * 0.65 + 0.35) end
		end)
	end
end

ESTILOS_GOL.BuracoNegro = function(pos, cor)
	local centro = pos + Vector3.new(0, 7, 0)
	local esfera = neonPart(Vector3.new(0.5, 0.5, 0.5), CFrame.new(centro), Color3.new(0, 0, 0), Enum.PartType.Ball)
	esfera.Material = Enum.Material.SmoothPlastic
	tween(esfera, 0.6, { Size = Vector3.new(7, 7, 7) }, Enum.EasingStyle.Back)
	local disco = neonPart(Vector3.new(0.3, 16, 16), CFrame.new(centro) * CFrame.Angles(0, 0, math.rad(90)), cor, Enum.PartType.Cylinder)
	disco.Transparency = 0.5
	local p, e = explosao(centro, {
		Color = ColorSequence.new(cor, Color3.fromRGB(60, 180, 255)), Rate = 90, Speed = NumberRange.new(-14, -10),
		Lifetime = NumberRange.new(0.6, 0.8), Shape = Enum.ParticleEmitterShape.Sphere,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) }),
	}, 0, 4)
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	p.Size = Vector3.new(14, 14, 14) -- a esfera de emissão: as partículas caem pra dentro (Speed negativa)
	local t0 = os.clock()
	local conexao
	conexao = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > 2.6 then
			conexao:Disconnect()
			e.Enabled = false
			tween(esfera, 0.25, { Size = Vector3.new(0.1, 0.1, 0.1) })
			tween(disco, 0.25, { Size = Vector3.new(0.3, 0.1, 0.1), Transparency = 1 })
			Debris:AddItem(esfera, 0.3)
			Debris:AddItem(disco, 0.3)
			task.delay(0.25, function()
				flashTela(cor, 0.5, 0.4)
				onda(centro, cor, 26, 0.6)
			end)
			return
		end
		disco.CFrame = CFrame.new(centro) * CFrame.Angles(math.rad(15), t * 4, 0) * CFrame.Angles(0, 0, math.rad(90))
	end)
end

-- ⚠️ v113 — SUPERNOVA GIGANTE ANIMADA (PEDIDO: "Supernova gigante animada").
-- Dura `total` segundos (5x o normal = ~17s) em 4 atos:
--   1. CARGA (0-22%): uma estrela que cresce pulsando, partículas sugadas pra dentro,
--      anéis se fechando, o céu escurece um pouco
--   2. COLAPSO + EXPLOSÃO (22-30%): a estrela some num ponto e ESTOURA — flash de tela
--      cheia, esfera que vai de 10 a 130 studs trocando de cor (branco, amarelo,
--      laranja, magenta, azul), ondas de choque em 3 planos, 28 raios
--   3. NEBULOSA (30-85%): cascas translúcidas expandindo, planetas/rochas orbitando,
--      chuva de estrelas, pulsos a cada 2s, remanescente pulsando
--   4. FIM (85-100%): tudo esvanece
ESTILOS_GOL.SupernovaGigante = function(pos, cor, total)
	total = total or 17
	local centro = pos + Vector3.new(0, 24, 0)
	local t0 = os.clock()
	local escurecer = Instance.new("ColorCorrectionEffect")
	escurecer.Parent = Lighting
	local nucleo = neonPart(Vector3.new(1, 1, 1), CFrame.new(centro), Color3.fromRGB(255, 250, 225), Enum.PartType.Ball)
	local halo = neonPart(Vector3.new(1, 1, 1), CFrame.new(centro), cor, Enum.PartType.Ball)
	halo.Transparency = 0.6
	local casca = neonPart(Vector3.new(1, 1, 1), CFrame.new(centro), cor, Enum.PartType.Ball)
	casca.Material = Enum.Material.ForceField
	casca.Transparency = 1
	local luzCentro = Instance.new("PointLight")
	luzCentro.Range = 0
	luzCentro.Brightness = 6
	luzCentro.Color = cor
	luzCentro.Parent = nucleo
	-- planetas em órbita
	local planetas = {}
	for i = 1, 6 do
		local pl = neonPart(Vector3.one * (2 + i * 0.7), CFrame.new(centro), Color3.fromHSV((i * 0.17) % 1, 0.55, 1), Enum.PartType.Ball)
		pl.Material = Enum.Material.SmoothPlastic
		pl.Transparency = 1
		planetas[i] = { Parte = pl, Raio = 18 + i * 7, Vel = (i % 2 == 0 and 1 or -1) * (0.5 + i * 0.07), Fase = i * 1.3, Incl = (i * 0.35) % 1.2 }
	end
	-- anéis de órbita
	local aneis = {}
	for i = 1, 3 do
		local an = neonPart(Vector3.new(0.25, 1, 1), CFrame.new(centro), cor, Enum.PartType.Cylinder)
		an.Transparency = 1
		aneis[i] = an
	end
	-- emissores: sugados (carga) e estrelas (nebulosa)
	local pe = ancora(centro, total + 2)
	pe.Size = Vector3.new(60, 60, 60)
	local sugar = Instance.new("ParticleEmitter")
	sugar.Texture = TEX_BRILHO
	sugar.Color = ColorSequence.new(cor, Color3.new(1, 1, 1))
	sugar.LightEmission = 1
	sugar.Rate = 0
	sugar.Lifetime = NumberRange.new(0.8, 1.1)
	sugar.Speed = NumberRange.new(-30, -26)
	sugar.Shape = Enum.ParticleEmitterShape.Sphere
	sugar.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	sugar.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.1) })
	sugar.Parent = pe
	local chuva = Instance.new("ParticleEmitter")
	chuva.Texture = TEX_BRILHO
	chuva.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(0.5, cor), ColorSequenceKeypoint.new(1, Color3.fromRGB(190, 120, 255)) })
	chuva.LightEmission = 1
	chuva.Rate = 0
	chuva.Lifetime = NumberRange.new(2.5, 4)
	chuva.Speed = NumberRange.new(2, 8)
	chuva.SpreadAngle = Vector2.new(180, 180)
	chuva.Acceleration = Vector3.new(0, -4, 0)
	chuva.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	chuva.Shape = Enum.ParticleEmitterShape.Sphere
	chuva.Parent = pe
	local PALETA = { Color3.fromRGB(255, 252, 235), Color3.fromRGB(255, 225, 120), Color3.fromRGB(255, 150, 60), Color3.fromRGB(255, 80, 190), Color3.fromRGB(110, 150, 255) }
	local explodiu, ultimoPulso = false, 0
	local conexao
	local function limpar()
		if conexao then conexao:Disconnect() end
		for _, p in ipairs({ nucleo, halo, casca }) do p:Destroy() end
		for _, pl in ipairs(planetas) do pl.Parte:Destroy() end
		for _, an in ipairs(aneis) do an:Destroy() end
		escurecer:Destroy()
	end
	conexao = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		local u = t / total
		if u >= 1 then limpar() return end
		-- ATO 1: carga
		if u < 0.22 then
			local k = u / 0.22
			local pulso = 1 + 0.12 * math.sin(t * (6 + 22 * k))
			nucleo.Size = Vector3.one * (4 + 22 * k * k) * pulso
			halo.Size = nucleo.Size * 1.7
			halo.Transparency = 0.55 + 0.3 * (1 - k)
			luzCentro.Range = 20 + 80 * k
			escurecer.Brightness = -0.25 * k
			escurecer.Saturation = 0.2 * k
			sugar.Rate = 40 + 160 * k
			-- anéis se fechando
			for i, an in ipairs(aneis) do
				local f = ((k * 2.2 + i / 3) % 1)
				local d = 70 * (1 - f) + 4
				an.Size = Vector3.new(0.25, d, d)
				an.CFrame = CFrame.new(centro) * CFrame.Angles(math.rad(i * 60), t * 2, math.rad(90))
				an.Transparency = 0.2 + 0.7 * f
			end
		elseif not explodiu then
			explodiu = true
			sugar.Rate = 0
			for _, an in ipairs(aneis) do an.Transparency = 1 end
			flashTela(Color3.new(1, 1, 1), 1.2, 1.2)
			-- 3 ondas de choque em planos diferentes + anéis grandes
			for i = 1, 3 do
				task.delay(i * 0.12, function()
					local an = neonPart(Vector3.new(1.2, 1, 1), CFrame.new(centro) * CFrame.Angles(math.rad(i * 55), math.rad(i * 30), math.rad(90)), PALETA[i + 1], Enum.PartType.Cylinder)
					an.Transparency = 0.1
					tween(an, 2.2, { Size = Vector3.new(1.2, 220, 220), Transparency = 1 })
					Debris:AddItem(an, 2.4)
				end)
			end
			onda(centro, cor, 90, 1.6, 2)
			-- 28 raios
			for i = 1, 28 do
				local a1, a2 = (i / 28) * math.pi * 2, math.sin(i * 1.9) * 1.1
				local dir = Vector3.new(math.cos(a1) * math.cos(a2), math.sin(a2), math.sin(a1) * math.cos(a2))
				local ray = neonPart(Vector3.new(0.9, 0.9, 6), CFrame.lookAt(centro, centro + dir), PALETA[(i % 5) + 1])
				tween(ray, 1.3, { Size = Vector3.new(0.2, 0.2, 130), CFrame = CFrame.lookAt(centro + dir * 62, centro + dir * 63), Transparency = 1 })
				Debris:AddItem(ray, 1.4)
			end
			explosao(centro, { Color = ColorSequence.new(PALETA[2], PALETA[4]), Speed = NumberRange.new(40, 90), Lifetime = NumberRange.new(1.4, 2.4),
				SpreadAngle = Vector2.new(180, 180), Drag = 1.5,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) }) }, 260, 4)
		end
		-- ATO 2/3: a esfera da explosão cresce e troca de cor
		if u >= 0.22 and u < 0.85 then
			local k = (u - 0.22) / 0.63
			local crescimento = math.min((u - 0.22) / 0.08, 1) -- estoura em ~1.4s
			local tam = 6 + 124 * (crescimento ^ 0.6)
			nucleo.Size = Vector3.one * math.max(tam * (1 - 0.7 * k), 1)
			nucleo.Transparency = 0.15 + 0.7 * k
			nucleo.Color = PALETA[1]:Lerp(PALETA[2], math.clamp(k * 3, 0, 1))
			halo.Size = Vector3.one * tam
			halo.Transparency = 0.4 + 0.5 * k
			halo.Color = PALETA[2]:Lerp(PALETA[3], math.clamp(k * 3, 0, 1)):Lerp(PALETA[4], math.clamp(k * 3 - 1, 0, 1)):Lerp(PALETA[5], math.clamp(k * 3 - 2, 0, 1))
			casca.Size = Vector3.one * tam * 1.12
			casca.Transparency = 0.35 + 0.65 * k
			casca.Color = halo.Color
			luzCentro.Range = 120 * (1 - k * 0.6)
			luzCentro.Color = halo.Color
			escurecer.Brightness = -0.25 + 0.25 * math.min(k * 4, 1)
			chuva.Rate = 70 * (1 - k * 0.5)
			-- planetas orbitam
			local aparece = math.clamp((u - 0.3) / 0.08, 0, 1) * (1 - math.clamp((u - 0.8) / 0.05, 0, 1))
			for _, pl in ipairs(planetas) do
				local ang = pl.Fase + t * pl.Vel
				pl.Parte.CFrame = CFrame.new(centro) * CFrame.Angles(pl.Incl, 0, 0) * CFrame.new(math.cos(ang) * pl.Raio, 0, math.sin(ang) * pl.Raio)
				pl.Parte.Transparency = 1 - aparece
			end
			-- pulsos secundários a cada 2s
			if t - ultimoPulso >= 2 then
				ultimoPulso = t
				local pc = PALETA[2 + math.floor(t / 2) % 4]
				onda(centro, pc, 70 + (math.floor(t) % 3) * 15, 1.2, 1.4)
				explosao(centro, { Color = ColorSequence.new(pc), Speed = NumberRange.new(14, 30), Lifetime = NumberRange.new(1, 1.6),
					SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }) }, 50, 2)
			end
		elseif u >= 0.85 then
			local k = (u - 0.85) / 0.15
			nucleo.Transparency = 0.85 + 0.15 * k
			halo.Transparency = 0.9 + 0.1 * k
			casca.Transparency = 1
			chuva.Rate = 0
			for _, pl in ipairs(planetas) do pl.Parte.Transparency = k end
			luzCentro.Range = 40 * (1 - k)
			escurecer.Brightness = 0
		end
	end)
	task.delay(total + 0.5, limpar)
end

ESTILOS_GOL.Supernova = function(pos, cor)
	local centro = pos + Vector3.new(0, 6, 0)
	local esfera = neonPart(Vector3.new(1, 1, 1), CFrame.new(centro), Color3.fromRGB(255, 250, 220), Enum.PartType.Ball)
	tween(esfera, 0.35, { Size = Vector3.new(12, 12, 12) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.35, function()
		flashTela(cor, 0.9, 0.6)
		tween(esfera, 0.7, { Size = Vector3.new(40, 40, 40), Transparency = 1 })
		Debris:AddItem(esfera, 0.8)
		onda(centro, cor, 40, 0.9, 0.8)
		for i = 1, 14 do
			local dir = CFrame.Angles(0, 0, math.rad(i * (360 / 14))) * Vector3.new(1, 0, 0)
			local raio = neonPart(Vector3.new(0.4, 0.4, 2), CFrame.lookAt(centro, centro + dir), cor)
			tween(raio, 0.5, { Size = Vector3.new(0.15, 0.15, 30), CFrame = CFrame.lookAt(centro + dir * 15, centro + dir * 16), Transparency = 1 })
			Debris:AddItem(raio, 0.55)
		end
		explosao(centro, { Color = ColorSequence.new(cor), Speed = NumberRange.new(25, 40), Lifetime = NumberRange.new(0.6, 1), SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }) }, 90, 3)
	end)
end

-- ⚠️ v113 — intervalo (s) entre repetições de cada estilo curto, pra preencher a
-- duração total (2x-5x). A Supernova tem versão própria que dura o tempo todo.
local INTERVALO_REPETE = {
	Fogos = 2.2, Confete = 1.5, Flash = 2.2, Estrelas = 2.2, Fogo = 1.4, Raio = 2.0, Petalas = 1.5, Bolhas = 1.6,
	Neve = 2.2, Moedas = 1.8, Coracoes = 2.4, Onda = 1.4, Aurora = 4.6, BuracoNegro = 3.4,
}

EfeitoDeGol.OnClientEvent:Connect(function(id, pos, _autor, total)
	local item = Cosmeticos.Item(id)
	if not item or typeof(pos) ~= "Vector3" then return end
	total = tonumber(total) or 3.5
	local function rodar(nome, p)
		local f = ESTILOS_GOL[nome]
		if not f then return end
		local ok, erro = pcall(f, p, item.Cor, total)
		if not ok then warn("[Cosmeticos] efeito de gol " .. id .. ": " .. tostring(erro)) end
	end
	if item.Estilo == "Supernova" then
		rodar("SupernovaGigante", pos)
		return
	end
	local intervalo = INTERVALO_REPETE[item.Estilo] or 2
	local rodadas = math.max(1, math.floor(total / intervalo))
	for i = 0, rodadas - 1 do
		task.delay(i * intervalo, function()
			local desloc = i == 0 and Vector3.zero or Vector3.new(math.random(-9, 9), 0, math.random(-6, 6))
			rodar(item.Estilo, pos + desloc)
		end)
	end
end)

-- ============================================================
-- FLOW — durante: olhos com rastro de luz + aura da cor do Flow
-- ============================================================
local function olhosPos(head)
	local s = head.Size
	return {
		Vector3.new(-s.X * 0.11, s.Y * 0.1, -s.Z * 0.5),
		Vector3.new(s.X * 0.11, s.Y * 0.1, -s.Z * 0.5),
	}
end

local function ligarFlowNoCorpo(player, item, duracao)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not head or not root then return end
	local tema = item.Tema
	local coisas = {}
	for i, p in ipairs(olhosPos(head)) do
		-- ⚠️ o "olho do Flow" do anime: o brilho que deixa um rastro de luz
		-- quando o jogador se mexe. Só o olho do lado do Flow fica aceso.
		if i == 2 then
			local a0 = Instance.new("Attachment")
			a0.Position = p + Vector3.new(0, 0.05, 0)
			a0.Parent = head
			local a1 = Instance.new("Attachment")
			a1.Position = p - Vector3.new(0, 0.05, 0)
			a1.Parent = head
			local trilha = Instance.new("Trail")
			trilha.Attachment0 = a0
			trilha.Attachment1 = a1
			trilha.Lifetime = 0.45
			trilha.MinLength = 0.05
			trilha.LightEmission = 1
			trilha.FaceCamera = true
			trilha.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0) })
			trilha.Color = ColorSequence.new(tema.Cor2, tema.Cor)
			trilha.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
			trilha.Parent = head
			local brilho = Instance.new("ParticleEmitter")
			brilho.Texture = TEX_BRILHO
			brilho.Color = ColorSequence.new(tema.Cor)
			brilho.LightEmission = 1
			brilho.LightInfluence = 0
			brilho.Rate = 20
			brilho.Lifetime = NumberRange.new(0.12, 0.18)
			brilho.Speed = NumberRange.new(0)
			brilho.Size = NumberSequence.new(0.35)
			brilho.LockedToPart = true
			brilho.Parent = a0
			table.insert(coisas, a0)
			table.insert(coisas, a1)
			table.insert(coisas, trilha)
		end
	end
	local anexo = Instance.new("Attachment")
	anexo.Position = Vector3.new(0, -1, 0)
	anexo.Parent = root
	local aura = Instance.new("ParticleEmitter")
	aura.Texture = TEX_BRILHO
	aura.Color = ColorSequence.new(tema.Cor, tema.Cor2)
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Rate = 22
	aura.Lifetime = NumberRange.new(0.5, 0.9)
	aura.Speed = NumberRange.new(3, 6)
	aura.EmissionDirection = Enum.NormalId.Top
	aura.SpreadAngle = Vector2.new(20, 20)
	aura.Shape = Enum.ParticleEmitterShape.Cylinder
	aura.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	aura.Parent = anexo
	table.insert(coisas, anexo)
	task.delay(duracao, function()
		aura.Enabled = false
		task.wait(1)
		for _, c in ipairs(coisas) do c:Destroy() end
	end)
end

-- ============================================================
-- FLOW — a cena de ativação mora no módulo FlowCena (a Loja do Lobby usa a mesma)
-- ============================================================
local COR_PAINEL = Color3.fromRGB(13, 15, 22)
local FlowCena = require(ReplicatedStorage:WaitForChild("FlowCena"))

local function frame(pai, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do f[k] = v end
	f.Parent = pai
	return f
end
local function redondo(f, raio)
	local c = Instance.new("UICorner")
	c.CornerRadius = raio or UDim.new(1, 0)
	c.Parent = f
	return c
end

-- aviso curto pros outros jogadores
local function avisoDoFlow(player, item)
	local gui = Instance.new("ScreenGui")
	gui.Name = "AvisoFlow"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 30
	gui.Parent = playerGui
	local caixa = frame(gui, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -60), Size = UDim2.fromOffset(360, 46),
		BackgroundColor3 = COR_PAINEL, BackgroundTransparency = 0.1 })
	redondo(caixa, UDim.new(0, 8))
	local s = Instance.new("UIStroke")
	s.Color = item.Tema.Cor
	s.Thickness = 2
	s.Parent = caixa
	local txt = Instance.new("TextLabel")
	txt.BackgroundTransparency = 1
	txt.Size = UDim2.fromScale(1, 1)
	txt.RichText = true
	txt.Font = Enum.Font.GothamBlack
	txt.TextSize = 16
	txt.TextColor3 = Color3.fromRGB(238, 241, 248)
	txt.Text = string.format('%s ENTROU NO <font color="#%s">FLOW</font>', escapar(maiusculas(nomeDe(player))), hex(item.Tema.Cor))
	txt.Parent = caixa
	tween(caixa, 0.25, { Position = UDim2.new(0, 0, 0, 70) + UDim2.fromScale(0.5, 0) }, Enum.EasingStyle.Back)
	task.delay(2.2, function()
		tween(caixa, 0.25, { Position = UDim2.new(0.5, 0, 0, -60) })
		task.wait(0.3)
		gui:Destroy()
	end)
end

FlowAtivado.OnClientEvent:Connect(function(player, id, duracao)
	local item = Cosmeticos.Item(id)
	if not item or typeof(player) ~= "Instance" then return end
	ligarFlowNoCorpo(player, item, duracao or 9)
	-- ⚠️ v113: Flow com cena 3D (HissatsuCutscenes["Flow_..."]) já teve a cena
	-- antes de ativar — a faixa 2D antiga só pros que ainda não têm
	local temCena3D = false
	pcall(function()
		temCena3D = require(game:GetService("ReplicatedStorage"):WaitForChild("HissatsuCutscenes"))[id] ~= nil
	end)
	if player == localPlayer and not temCena3D then
		FlowCena.Tocar(player, item)
	else
		pcall(avisoDoFlow, player, item)
	end
end)

print("✅ CosmeticosClient carregado")
