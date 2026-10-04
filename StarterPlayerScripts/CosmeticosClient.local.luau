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
	-- ⚠️ v119: a Aura saiu dos cosméticos (Cosmeticos.CATEGORIAS) — Equipado devolve
	-- nil e esta função só limpa a aura que tivesse sobrado.
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
-- ⚠️ v117 — RODA DE EMOTES (6 casas, montada na Eleven Store): G abre/fecha, escolhe
-- clicando ou com 1-6. A casa 1 também é a comemoração do gol.
local EmoteWheel = require(ReplicatedStorage:WaitForChild("EmoteWheel"))
local Roda = EmoteWheel.Criar({
	Jogador = localPlayer, Cosmeticos = Cosmeticos,
	AoEscolher = function(indice) TocarEmote:FireServer(indice) end,
})

UserInputService.InputBegan:Connect(function(input, processado)
	if processado then return end
	if input.KeyCode == Enum.KeyCode.G then Roda.Alternar() end
end)

-- emotes cadastrados por AnimationId (EmotesCustom): animação normal do Roblox. O
-- AnimadorProcedural do Game para TODA AnimationTrack, então o corpo fica "pausado"
-- pra ele enquanto o emote toca (mesma trava das cutscenes).
local emoteCustomTocando = {} -- [character] = track
local function pararEmoteCustom(character)
	local track = emoteCustomTocando[character]
	if not track then return end
	emoteCustomTocando[character] = nil
	pcall(function() track:Stop(0.15) end)
	if _G.AnimadorPausado then _G.AnimadorPausado[character] = nil end
end
local function tocarEmoteCustom(character, id)
	local item = Cosmeticos.Item(id)
	if not item or not item.AnimacaoId or typeof(character) ~= "Instance" then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not animator then return end
	pararEmoteCustom(character)
	local anim = Instance.new("Animation")
	anim.Name = "EmoteCustom"
	anim.AnimationId = item.AnimacaoId
	local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
	if not ok or not track then return end
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = item.Loop == true
	emoteCustomTocando[character] = track
	_G.AnimadorPausado = _G.AnimadorPausado or {}
	_G.AnimadorPausado[character] = true
	track:Play(0.15)
	track.Stopped:Connect(function()
		if emoteCustomTocando[character] == track then pararEmoteCustom(character) end
	end)
	task.delay(item.Duracao or 4, function()
		if emoteCustomTocando[character] == track then pararEmoteCustom(character) end
	end)
end
pastaRemotes:WaitForChild("EmoteAnimado").OnClientEvent:Connect(tocarEmoteCustom)
pastaRemotes:WaitForChild("EmoteParar").OnClientEvent:Connect(pararEmoteCustom)

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
		b.Visible = Roda.TemAlgum()
	end
	atualizar()
	for i = 1, Cosmeticos.RODA_TAMANHO do
		localPlayer:GetAttributeChangedSignal("Cosm_EmoteSlot" .. i):Connect(atualizar)
	end
	b.Activated:Connect(function() Roda.Alternar() end)
end

-- ============================================================
-- EFEITO DE GOL
-- ⚠️ v119 — PEDIDO: "realmente se esforce: não fica repetindo, acontece no gol/bola
-- e geralmente afeta o campo inteiro". Os 15 efeitos foram refeitos do zero no
-- módulo ReplicatedStorage/EfeitosDeGol (um espetáculo só do começo ao fim, que
-- toma o campo todo e mexe no céu/luz). Antes eles eram um estouro pequeno
-- repetido a cada ~2s — e o Confete/Pétalas nem apareciam (Texture = "").
-- ============================================================
local EfeitosDeGol = require(ReplicatedStorage:WaitForChild("EfeitosDeGol"))

EfeitoDeGol.OnClientEvent:Connect(function(id, pos, _autor, total)
	local item = Cosmeticos.Item(id)
	if not item or typeof(pos) ~= "Vector3" then return end
	EfeitosDeGol.Tocar(item.Estilo, pos, item.Cor, tonumber(total) or 7)
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
	-- ⚠️ v119b — PEDIDO: "o efeito do Flow do quebra-cabeça ficou bacana, mas são VÁRIOS
	-- quebra-cabeças, cada imagem uma peça diferente; e não é pra sair nas costas dele,
	-- é em volta dele inteiro, sempre junto dele". Flow do Isagi: as 6 peças nascem no
	-- volume do corpo inteiro, presas a ele (andam junto), crescem, giram e somem.
	if tema.Motivo == "Pecas" then
		local okEf, Ef = pcall(function() return require(ReplicatedStorage:WaitForChild("HissatsuEfeitos")) end)
		if okEf and Ef and Ef.PecasEmVolta then
			-- (v126b: "menores e em maior quantidade" — 12 formatos x taxa 1.6, tamanho 0.3 (era 0.55))
			for _, e in ipairs(Ef.PecasEmVolta(character, tema.Cor, tema.Cor2, 1.6, 0.3)) do table.insert(coisas, e) end
		end
		-- ⚠️ v120b — PEDIDO: "o cara se mantém com esse olho (o de quebra-cabeça)
		-- durante o Flow também, fora da animação": a mesma íris da cena, no rosto
		if okEf and Ef and Ef.OlhosFlow then
			local olhosQC = Ef.OlhosFlow(character)
			if olhosQC then
				olhosQC.Definir(1)
				table.insert(coisas, olhosQC.Parte)
			end
		end
	end
	-- ⚠️ v124 — Flow do Shidou: a mesma íris rosa da cena (borda serrilhada, pupila
	-- oval) nos dois olhos, no rosto, durante o Flow inteiro
	if item.Id == "Flow_Shidou" then
		local okEf, Ef = pcall(function() return require(ReplicatedStorage:WaitForChild("HissatsuEfeitos")) end)
		if okEf and Ef and Ef.OlhosFlow and Ef.OLHO_SHIDOU then
			local olhosSh = Ef.OlhosFlow(character, Ef.OLHO_SHIDOU)
			if olhosSh then
				olhosSh.Definir(1)
				table.insert(coisas, olhosSh.Parte)
			end
		end
		-- ⚠️ v126 — PEDIDO: "coloca uma aura no Shidou, pelo menos uma aurazinha roxa". Fogo
		-- roxo em volta do corpo INTEIRO (preso a cada parte, sobe e some) + faíscas lilás.
		local ROXO_CLARO, ROXO, ROXO_ESCURO = Color3.fromRGB(235, 200, 255), Color3.fromRGB(170, 90, 255), Color3.fromRGB(95, 20, 170)
		for _, nome in ipairs({ "Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
			local parte = character:FindFirstChild(nome)
			if parte and parte:IsA("BasePart") then
				local fogo = Instance.new("ParticleEmitter")
				fogo.Name = "AuraRoxaShidou"
				fogo.Texture = "rbxasset://textures/particles/fire_main.dds"
				fogo.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, ROXO_CLARO), ColorSequenceKeypoint.new(0.35, ROXO), ColorSequenceKeypoint.new(1, ROXO_ESCURO),
				})
				fogo.LightEmission = 0.8
				fogo.LightInfluence = 0
				fogo.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.15) })
				fogo.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
				fogo.Lifetime = NumberRange.new(0.35, 0.65)
				fogo.Speed = NumberRange.new(0.5, 1.8)
				fogo.SpreadAngle = Vector2.new(180, 180)
				fogo.Acceleration = Vector3.new(0, 6, 0)
				fogo.Shape = Enum.ParticleEmitterShape.Box
				fogo.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				fogo.LockedToPart = true
				fogo.Rate = (nome == "Torso") and 16 or 8
				fogo.Parent = parte
				table.insert(coisas, fogo)
			end
		end
		local tronco = character:FindFirstChild("Torso")
		if tronco then
			local faisca = Instance.new("ParticleEmitter")
			faisca.Name = "AuraRoxaShidouFaisca"
			faisca.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			faisca.Color = ColorSequence.new(ROXO_CLARO, ROXO)
			faisca.LightEmission = 1
			faisca.LightInfluence = 0
			faisca.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
			faisca.Lifetime = NumberRange.new(0.3, 0.6)
			faisca.Speed = NumberRange.new(3, 7)
			faisca.SpreadAngle = Vector2.new(180, 180)
			faisca.Shape = Enum.ParticleEmitterShape.Box
			faisca.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			faisca.Rate = 10
			faisca.Parent = tronco
			table.insert(coisas, faisca)
		end
	end
	-- ⚠️ v125 — FLOW DO AIKU: as bolhas de luz verde em volta do corpo (presas a ele) e os
	-- olhos do Flow no rosto — o ESQUERDO verde e o DIREITO azul — durante o Flow todo
	if item.Id == "Flow_Aiku" then
		local okAi, EfAi = pcall(function() return require(ReplicatedStorage:WaitForChild("HissatsuEfeitos")) end)
		if okAi and EfAi then
			if EfAi.AuraAiku then
				for _, e in ipairs(EfAi.AuraAiku(character, 3)) do table.insert(coisas, e) end
			end
			if EfAi.OlhosFlowAiku then
				local olhosAi = EfAi.OlhosFlowAiku(character)
				if olhosAi then
					olhosAi.Definir(1)
					table.insert(coisas, olhosAi.Parte)
				end
			end
		end
	end
	-- ⚠️ v120b — PEDIDO: "às vezes o Flow tá acabando e o cara continua com as
	-- partículas". Desliga no tempo E na hora em que o servidor encerra o Flow
	-- (atributo FlowAtivo some) — o que vier primeiro, uma vez só.
	local desligado = false
	local conexaoFim
	local function desligar()
		if desligado then return end
		desligado = true
		if conexaoFim then conexaoFim:Disconnect() end
		aura.Enabled = false
		for _, c in ipairs(coisas) do
			if c:IsA("ParticleEmitter") then c.Enabled = false end
			if c:IsA("Trail") then c.Enabled = false end
		end
		task.delay(1, function()
			for _, c in ipairs(coisas) do
				if c.Parent then c:Destroy() end
			end
		end)
	end
	conexaoFim = player:GetAttributeChangedSignal("FlowAtivo"):Connect(function()
		if not player:GetAttribute("FlowAtivo") then desligar() end
	end)
	character.AncestryChanged:Connect(function(_, pai)
		if not pai then desligar() end
	end)
	task.delay(duracao, desligar)
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
