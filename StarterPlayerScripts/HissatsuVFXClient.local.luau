--[[
	HissatsuVFXClient — ⚠️ v109 / v110

	PEDIDO (v109): "faça mais habilidades... tackles não precisam de cutscene, já
	têm a animação deles". PEDIDO (v110): "vai com os dribles e defesas... olhe
	na wiki" — cada drible e defesa (as antigas também) ganhou ANIMAÇÃO própria
	(AnimacoesProcedurais, bloco v110) e VFX refeito, seguindo o "Usage" da
	Inazuma Eleven Wiki da técnica original. O servidor avisa quando a técnica
	sai (Remotes.HissatsuVFX: personagem, nome, elemento) e TODO cliente toca a
	animação no corpo de quem usou + o efeito. Tudo local, sem colisão, se apaga
	sozinho. A Chuva de Meteoros tem cutscene (HissatsuCutscenes).

	DRIBLES
	  Residual (Afterimage)          — braços cruzados; fica um VULTO parado no
	                                   lugar (quem der o carrinho pega o vulto)
	  Vendaval (Shippuu Dash)        — zigue-zague com rajadas de vento e vultos;
	                                   rastro de vento durante o pique
	  Névoa (Dokugiri no Jutsu)      — punho na palma, salto, SOPRO venenoso que
	                                   vira a névoa roxa da zona
	  Foice de Vento (Kamaitachi)    — pisão, redemoinho de poeira girando e uma
	                                   LÂMINA de vento cortando pra frente
	  Hora do Céu (Heaven's Time)    — estalo de dedos, luz azul, campo CINZA e
	                                   todo mundo parado; no fim outro estalo e
	                                   redemoinhos de poeira onde eles estavam
	  Investida em Chamas (Heat Tackle) — braços em X, véu de chamas em ESPIRAL
	                                   subindo do chão e investida de ombro
	  Bola Ilusão (Illusion Ball)    — mortal no ar; duas bolas-ilusão roxas
	                                   girando que voltam pra bola
	  Faísca Zigue-Zague             — pulos de um lado pro outro soltando
	                                   faíscas; uma faísca em zigue-zague até cada
	                                   marcador, que fica DE JOELHOS paralisado
	  Dobra Veloz (Sprint Warp)      — nuvem de poeira, vultos em zigue-zague e
	                                   rajadas de vento
	DEFESAS
	  Rasteira (Killer Slide)        — carrinho com várias PERNAS-FANTASMA chutando
	  Costura de Sombra (Kage Nui)   — mãos juntas; a SOMBRA corre pelo chão e
	                                   vira uma mão que agarra as pernas
	  Teia (Kumo no Ito)             — ajoelha, mortal pra trás, mão no chão; os
	                                   fios grudam em quem pisar na teia
	  Muralha Infinita (The Wall)    — braços pro alto e MUROS DE PEDRA sobem do
	                                   chão (mais muros com companheiros perto)
	  Pisão de Sumô (Super Shikofumi)— pisão, ondas amarelas e o PÉ GIGANTE que
	                                   deixa o adversário achatado
	  Corte Giratório (Spinning Cut) — chute giratório com o pé azul, MEIA-LUA
	                                   no chão e o muro de fogo azul subindo
	  Roubo Congelante (Frozen Steal)— perna de gelo, chão congelado e o
	                                   adversário preso num bloco de gelo
	  Clarão de Fótons (Photon Flash)— brilhos juntando no giro, tudo escurece e
	                                   o CLARÃO cega quem estiver perto
	  Anjo da Neve (Snow Angel)      — salto girando num véu de vento gelado,
	                                   cortes de gelo, campo congelado e blocos de
	                                   gelo nos adversários
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local E = require(ReplicatedStorage:WaitForChild("HissatsuEfeitos"))
local Remotes = Config.Remotes
local LocalPlayer = Players.LocalPlayer

local V3 = Vector3.new
local function rgb(r, g, b) return Color3.fromRGB(r, g, b) end
local TEX = E.TEX or {
	Fogo = "rbxasset://textures/particles/fire_main.dds",
	Faisca = "rbxasset://textures/particles/sparkles_main.dds",
	Fumaca = "rbxasset://textures/particles/smoke_main.dds",
}

local pasta = Instance.new("Folder")
pasta.Name = "HissatsuVFX"
pasta.Parent = workspace

-- ============================================================
-- utilidades
-- ============================================================
local function parte(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Size = V3(1, 1, 1)
	for k, v in pairs(props or {}) do p[k] = v end
	p.Parent = pasta
	return p
end

local function sumir(p, dur, props)
	props = props or {}
	props.Transparency = 1
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	Debris:AddItem(p, dur + 0.05)
end

local function anel(pos, normal, cor, de, ate, dur, grossura)
	return E.AnelVazado and E.AnelVazado(pasta, pos, normal, cor, de, ate, dur, grossura or 0.3)
end

local function onda(pos, normal, cor, final, dur, grossura)
	local o = E.Onda and E.Onda(pasta, pos, normal, cor, final, dur, grossura or 0.3)
	if o then Debris:AddItem(o, dur + 0.05) end
	return o
end

local function ignorarPersonagens()
	local ignorar = { pasta }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignorar, p.Character) end end
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	if bola then table.insert(ignorar, bola) end
	return ignorar
end

local function chaoDe(pos)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = ignorarPersonagens()
	local hit = workspace:Raycast(pos + V3(0, 3, 0), V3(0, -30, 0), params)
	return hit and hit.Position.Y or (pos.Y - 3)
end

local function noChao(pos, altura)
	return V3(pos.X, chaoDe(pos) + (altura or 0.1), pos.Z)
end

local function frenteDe(root)
	local f = V3(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	return f.Magnitude > 0.01 and f.Unit or V3(0, 0, -1)
end

-- adversários (do dono da técnica) perto de um ponto -> lista de HumanoidRootPart
local function adversariosPerto(character, pos, raio)
	local dono = Players:GetPlayerFromCharacter(character)
	local lista = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= dono and p.Character and (not dono or not dono.Team or p.Team ~= dono.Team) then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - pos).Magnitude <= raio then table.insert(lista, r) end
		end
	end
	table.sort(lista, function(a, b) return (a.Position - pos).Magnitude < (b.Position - pos).Magnitude end)
	return lista
end

local function companheirosPerto(character, raio)
	local dono = Players:GetPlayerFromCharacter(character)
	local root = character:FindFirstChild("HumanoidRootPart")
	local n = 0
	if not dono or not dono.Team or not root then return 0 end
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= dono and p.Team == dono.Team and p.Character then
			local r = p.Character:FindFirstChild("HumanoidRootPart")
			if r and (r.Position - root.Position).Magnitude <= raio then n += 1 end
		end
	end
	return n
end

local function membro(ch, r6, r15)
	return ch:FindFirstChild(r6) or ch:FindFirstChild(r15)
end
-- ponta do membro (mão / pé) no mundo
local function ponta(parteMembro)
	if not parteMembro then return nil end
	return (parteMembro.CFrame * CFrame.new(0, -parteMembro.Size.Y / 2, 0)).Position
end

local function animar(ch, chave, dur)
	if _G.AnimadorAcaoLocal then pcall(_G.AnimadorAcaoLocal, ch, chave, dur) end
end

-- roda fn(t, dt) todo quadro por `dur` segundos (e chama fim() no final)
local function durante(dur, fn, fim)
	local t0 = os.clock()
	local con
	con = RunService.Heartbeat:Connect(function(dt)
		local t = os.clock() - t0
		if t >= dur then
			con:Disconnect()
			if fim then pcall(fim) end
			return
		end
		local ok, err = pcall(fn, t, dt)
		if not ok then
			con:Disconnect()
			warn("[HissatsuVFX] " .. tostring(err))
		end
	end)
	return con
end

local function emissor(pai, c)
	return E.Emissor(pai, c)
end
local cores, numeros = E.Cores, E.Numeros

local function faiscas(pos, cor, n, forca)
	local a = parte({ Transparency = 1, Size = V3(0.2, 0.2, 0.2), CFrame = CFrame.new(pos) })
	local e = emissor(a, { Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, cor } }), Tamanho = 0.35, Vida = { 0.25, 0.6 },
		Vel = { forca * 0.5, forca }, Drag = 3 })
	e:Emit(n)
	Debris:AddItem(a, 0.8)
end

local function fumaca(pos, cor, n, tamanho, vel)
	local a = parte({ Transparency = 1, Size = V3(0.2, 0.2, 0.2), CFrame = CFrame.new(pos) })
	local e = emissor(a, {
		Textura = TEX.Fumaca, Cor = cor, Brilho = 0,
		Tamanho = numeros({ { 0, tamanho }, { 1, tamanho * 2.4 } }), Transp = numeros({ { 0, 0.25 }, { 1, 1 } }),
		Vida = { 0.6, 1.2 }, Vel = { vel * 0.5, vel }, Spread = 80, Direcao = Enum.NormalId.Top, Drag = 2,
	})
	e:Emit(n)
	Debris:AddItem(a, 1.4)
end

local function fogoEm(pai, taxa, tamanho, corMeio)
	return emissor(pai, {
		Textura = TEX.Fogo, Cor = cores({ { 0, rgb(255, 235, 150) }, { 0.45, corMeio or rgb(255, 120, 30) }, { 1, rgb(170, 30, 10) } }),
		Brilho = 0.9, Tamanho = numeros({ { 0, tamanho or 1.6 }, { 1, 0.2 } }), Transp = numeros({ { 0, 0.15 }, { 1, 1 } }),
		Vida = { 0.3, 0.6 }, Vel = { 2, 5 }, Acel = V3(0, 8, 0), Taxa = taxa or 60,
	})
end

-- Trail entre dois pontos de uma parte (brilho que segue o membro)
local function rastroNaParte(p, meia, cor, vida, dur)
	local a0 = Instance.new("Attachment")
	a0.Position = V3(0, meia, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = V3(0, -meia, 0)
	a1.Parent = p
	local t = Instance.new("Trail")
	t.Attachment0 = a0
	t.Attachment1 = a1
	t.Color = typeof(cor) == "Color3" and ColorSequence.new(cor) or cor
	t.LightEmission = 1
	t.LightInfluence = 0
	t.Lifetime = vida or 0.25
	t.Transparency = numeros({ { 0, 0.1 }, { 1, 1 } })
	t.WidthScale = numeros({ { 0, 1 }, { 1, 0.2 } })
	t.FaceCamera = true
	t.Parent = p
	task.delay(dur, function()
		t.Enabled = false
		Debris:AddItem(t, t.Lifetime + 0.05)
		Debris:AddItem(a0, t.Lifetime + 0.05)
		Debris:AddItem(a1, t.Lifetime + 0.05)
	end)
	return t
end

-- VULTO: cópia parada do corpo inteiro, na pose de agora (partes soltas)
local function vulto(ch, cor, transp, dur, material, deslocar)
	local grupo = Instance.new("Model")
	grupo.Name = "Vulto"
	for _, p in ipairs(ch:GetDescendants()) do
		if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" and p.Transparency < 0.95 then
			local ok, c = pcall(function() return p:Clone() end)
			if ok and c then
				for _, filho in ipairs(c:GetChildren()) do
					if not filho:IsA("DataModelMesh") then filho:Destroy() end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.CastShadow = false
				c.Massless = true
				if c:IsA("MeshPart") then pcall(function() c.TextureID = "" end) end
				c.Material = material or Enum.Material.ForceField
				c.Color = cor
				c.Transparency = transp
				c.CFrame = p.CFrame + (deslocar or Vector3.zero)
				c.Parent = grupo
			end
		end
	end
	grupo.Parent = pasta
	if dur then
		task.delay(dur, function()
			for _, c in ipairs(grupo:GetChildren()) do
				if c:IsA("BasePart") then TweenService:Create(c, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
			end
			Debris:AddItem(grupo, 0.3)
		end)
	end
	return grupo
end

-- tela: efeito de cor local (só em quem está perto do ponto, se raio vier)
local function corDaTela(props, volta, dur)
	local cc = Instance.new("ColorCorrectionEffect")
	for k, v in pairs(props) do cc[k] = v end
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.In), volta):Play()
	Debris:AddItem(cc, dur + 0.05)
	return cc
end

local function meuRoot()
	return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
end

-- rajada de vento: riscos brancos esticados na direção do movimento
local function rajada(pos, dir, cor, n, comprimento)
	for i = 1, n do
		local off = V3(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5) * 3
		local p = parte({ Color = cor, Transparency = 0.25, Size = V3(0.12, 0.12, comprimento * (0.6 + math.random() * 0.6)),
			CFrame = CFrame.lookAt(pos + off, pos + off + dir) })
		TweenService:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.lookAt(pos + off - dir * 4, pos + off), Transparency = 1, Size = V3(0.05, 0.05, comprimento * 0.3) }):Play()
		Debris:AddItem(p, 0.35)
	end
end

-- meia-lua de energia (arco de peças) — devolve a lista pra animar
local function meiaLua(cor, raio, segs, largura)
	local pecas = {}
	for i = 1, segs do
		pecas[i] = parte({ Color = cor, Transparency = 1, Size = V3(largura, 0.25, raio * math.pi / segs * 1.15) })
	end
	return function(cfCentro, alfa, escala)
		escala = escala or 1
		for i, p in ipairs(pecas) do
			local ang = math.rad(-80 + 160 * (i - 0.5) / segs)
			local pos = cfCentro * CFrame.Angles(0, ang, 0) * CFrame.new(0, 0, -raio * escala)
			p.CFrame = pos * CFrame.Angles(0, math.rad(90), 0)
			local borda = math.abs((i - 0.5) / segs - 0.5) * 2
			p.Size = V3(largura * (1 - borda * 0.7) * escala, 0.25, raio * escala * math.pi / segs * 1.15)
			p.Transparency = 1 - alfa * (1 - borda * 0.4)
		end
	end, pecas
end

local function blocoDeGelo(alvo, dur)
	local base = noChao(alvo.Position, 0)
	local bloco = parte({ Material = Enum.Material.Ice, Color = rgb(185, 230, 255), Transparency = 0.3,
		Size = V3(0.5, 0.5, 0.5), CFrame = CFrame.new(base + V3(0, 3.4, 0)) * CFrame.Angles(0, math.random() * 3, 0) })
	TweenService:Create(bloco, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = V3(4.4, 7, 4.4) }):Play()
	for k = 1, 5 do
		local ang = (k / 5) * math.pi * 2
		local ponta_ = parte({ Material = Enum.Material.Ice, Color = rgb(215, 245, 255), Transparency = 0.2,
			Size = V3(0.8, 0.1, 0.8), CFrame = CFrame.new(base + V3(math.cos(ang) * 2.8, 0, math.sin(ang) * 2.8)) * CFrame.Angles(math.cos(ang) * 0.5, 0, math.sin(ang) * 0.5) })
		TweenService:Create(ponta_, TweenInfo.new(0.18), { Size = V3(0.8, 2.6 + math.random() * 1.5, 0.8) }):Play()
		task.delay(dur, function() sumir(ponta_, 0.3) end)
	end
	faiscas(base + V3(0, 3, 0), rgb(200, 240, 255), 25, 10)
	task.delay(dur, function()
		faiscas(base + V3(0, 3, 0), rgb(200, 240, 255), 30, 14)
		sumir(bloco, 0.3)
	end)
end

local function redemoinhoDePoeira(pos, dur, cor)
	local base = noChao(pos, 0.2)
	local p = parte({ Transparency = 1, Size = V3(0.2, 0.2, 0.2), CFrame = CFrame.new(base) })
	local e = emissor(p, {
		Textura = TEX.Fumaca, Cor = cor or cores({ { 0, rgb(215, 195, 160) }, { 1, rgb(150, 125, 95) } }), Brilho = 0,
		Tamanho = numeros({ { 0, 2 }, { 1, 5 } }), Transp = numeros({ { 0, 0.3 }, { 1, 1 } }),
		Vida = { 0.5, 0.9 }, Vel = { 8, 14 }, Spread = 12, Direcao = Enum.NormalId.Top, RotVel = 400, Taxa = 70,
	})
	local ultimo = -1
	durante(dur, function(t)
		if t - ultimo > 0.07 then
			ultimo = t
			local y = (t * 9) % 1 * 8
			anel(base + V3(0, y, 0), Vector3.yAxis, rgb(225, 205, 170), 1.5 + y * 0.35, 3 + y * 0.5, 0.25, 0.25)
		end
	end, function()
		e.Enabled = false
		Debris:AddItem(p, 1)
	end)
end

local VFX = {}

-- ============================================================
-- DRIBLES
-- ============================================================
VFX["Residual"] = function(ch, root)
	animar(ch, "Residual")
	-- o vulto fica no lugar, na pose de braços cruzados (espera a pose entrar)
	local origem = root.Position
	task.delay(0.06, function()
		if not ch.Parent then return end
		local desl = origem - root.Position -- ele já começou a sair: o vulto fica onde ele ESTAVA
		local g = vulto(ch, rgb(200, 255, 210), 0.35, 0.8, Enum.Material.ForceField, V3(desl.X, 0, desl.Z))
		local miolo = vulto(ch, rgb(120, 220, 150), 0.75, 0.8, Enum.Material.Neon, V3(desl.X, 0, desl.Z))
		local _ = g, miolo
		anel(noChao(origem, 0.15), Vector3.yAxis, rgb(170, 255, 190), 2, 6, 0.4)
	end)
end

VFX["Vendaval"] = function(ch, root)
	animar(ch, "Vendaval")
	local VENTO = rgb(225, 255, 240)
	for i = 0, 3 do
		task.delay(i * 0.13, function()
			if not root.Parent then return end
			local lado = (i % 2 == 0) and 1 or -1
			rajada(root.Position, -frenteDe(root), VENTO, 5, 5)
			anel(root.Position, frenteDe(root), rgb(200, 255, 225), 2, 6, 0.3, 0.2)
			if i < 3 then vulto(ch, rgb(180, 255, 215), 0.5, 0.25, Enum.Material.ForceField, root.CFrame.RightVector * lado * 1.5) end
		end)
	end
	-- rastro de vento nos ombros durante o pique (3.5s)
	local torso = membro(ch, "Torso", "UpperTorso")
	if torso then
		rastroNaParte(torso, 1.2, cores({ { 0, rgb(230, 255, 245) }, { 1, rgb(140, 230, 190) } }), 0.3, 3.5)
	end
	local ultimo = 0
	durante(3.5, function(t)
		if t - ultimo > 0.25 and root.AssemblyLinearVelocity.Magnitude > 8 then
			ultimo = t
			rajada(root.Position, root.AssemblyLinearVelocity.Unit, VENTO, 2, 4)
		end
	end)
end

VFX["Névoa"] = function(ch, root)
	animar(ch, "Nevoa")
	local centro = root.Position
	-- o SOPRO venenoso (na queda do salto)
	task.delay(0.6, function()
		if not root.Parent then return end
		local cabeca = ch:FindFirstChild("Head")
		local boca = cabeca and (cabeca.CFrame * CFrame.new(0, -0.2, -0.6)).Position or root.Position + V3(0, 1.5, 0)
		local p = parte({ Transparency = 1, Size = V3(0.2, 0.2, 0.2), CFrame = CFrame.lookAt(boca, boca + frenteDe(root)) })
		local sopro = emissor(p, {
			Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(200, 150, 255) }, { 1, rgb(110, 170, 90) } }), Brilho = 0.2,
			Tamanho = numeros({ { 0, 1 }, { 1, 6 } }), Transp = numeros({ { 0, 0.2 }, { 1, 1 } }),
			Vida = { 0.6, 1.0 }, Vel = { 16, 26 }, Spread = 22, Direcao = Enum.NormalId.Front, Drag = 2,
		})
		sopro:Emit(40)
		Debris:AddItem(p, 1.2)
	end)
	-- a névoa roxa na zona (raio ~30, 7s)
	local base = noChao(centro, 1)
	local zona = parte({ Transparency = 1, Size = V3(52, 2, 52), CFrame = CFrame.new(base) })
	local nevoa = emissor(zona, {
		Textura = TEX.Fumaca, Cor = cores({ { 0, rgb(170, 120, 220) }, { 1, rgb(90, 70, 120) } }), Brilho = 0,
		Tamanho = numeros({ { 0, 8 }, { 0.5, 14 }, { 1, 16 } }), Transp = numeros({ { 0, 1 }, { 0.2, 0.45 }, { 0.8, 0.55 }, { 1, 1 } }),
		Vida = { 2.5, 3.5 }, Vel = { 0.5, 2 }, Spread = 180, Forma = Enum.ParticleEmitterShape.Box, RotVel = 30, Taxa = 0,
	})
	task.delay(0.7, function() nevoa.Rate = 38; nevoa.Enabled = true end)
	task.delay(7, function() nevoa.Enabled = false; Debris:AddItem(zona, 4) end)
end

VFX["Foice de Vento"] = function(ch, root)
	animar(ch, "FoiceVento")
	local VENTO = rgb(215, 255, 235)
	local frente = frenteDe(root)
	task.delay(0.2, function() -- pisão
		if not root.Parent then return end
		local base = noChao(root.Position, 0.15)
		onda(base, Vector3.yAxis, rgb(220, 200, 160), 12, 0.35, 0.25)
		fumaca(base, cores({ { 0, rgb(215, 195, 160) }, { 1, rgb(150, 125, 95) } }), 16, 2, 10)
		redemoinhoDePoeira(root.Position, 0.4)
	end)
	task.delay(0.52, function() -- a LÂMINA de vento cortando pra frente
		if not root.Parent then return end
		local desenhar, pecas = meiaLua(VENTO, 4.5, 11, 0.7)
		local inicio = root.Position + V3(0, 0.5, 0)
		local fonte = parte({ Transparency = 1, Size = V3(0.3, 0.3, 0.3), CFrame = CFrame.new(inicio) })
		rastroNaParte(fonte, 2.5, cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(120, 230, 180) } }), 0.3, 0.3)
		durante(0.32, function(t)
			local u = t / 0.32
			local pos = inicio + frente * (2 + 26 * u)
			local cf = CFrame.lookAt(pos, pos + frente) * CFrame.Angles(0, 0, math.rad(12))
			desenhar(cf * CFrame.new(0, 0, 4.5), 1 - u * 0.4, 1 + u * 0.4)
			fonte.CFrame = cf
		end, function()
			for _, p in ipairs(pecas) do sumir(p, 0.15) end
			Debris:AddItem(fonte, 0.5)
		end)
		task.delay(0.12, function()
			for _, alvo in ipairs(adversariosPerto(ch, root.Position, 28)) do
				rajada(alvo.Position, frente, VENTO, 6, 5)
				faiscas(alvo.Position, rgb(200, 255, 230), 18, 14)
			end
		end)
	end)
end

VFX["Hora do Céu"] = function(ch, root)
	animar(ch, "HoraDoCeu")
	local dono = Players:GetPlayerFromCharacter(ch)
	local DUR = 2.5
	local mao = membro(ch, "Right Arm", "RightHand")
	task.delay(0.32, function() -- o ESTALO: luz azul
		local pos = ponta(mao) or root.Position + V3(0, 3, 0)
		local luz = parte({ Shape = Enum.PartType.Ball, Color = rgb(150, 200, 255), Size = V3(1, 1, 1), CFrame = CFrame.new(pos), Transparency = 0 })
		local pl = Instance.new("PointLight")
		pl.Color = rgb(150, 200, 255)
		pl.Range = 30
		pl.Brightness = 6
		pl.Parent = luz
		sumir(luz, 0.5, { Size = V3(26, 26, 26) })
		anel(pos, Vector3.yAxis, rgb(190, 225, 255), 1, 40, 0.6, 0.2)
		-- o campo fica CINZA (pra todo mundo por perto)
		local meu = meuRoot()
		if meu and (meu.Position - root.Position).Magnitude <= 220 then
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Saturation = -1
			cc.TintColor = rgb(215, 225, 245)
			cc.Contrast = 0.1
			cc.Parent = Lighting
			task.delay(DUR - 0.1, function()
				TweenService:Create(cc, TweenInfo.new(0.25), { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }):Play()
				Debris:AddItem(cc, 0.3)
			end)
		end
		-- quem parou ganha um contorno cinza
		local parados = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if p ~= dono and r and p:GetAttribute("Role") ~= "GK" and (r.Position - root.Position).Magnitude <= 220 then
				local h = Instance.new("Highlight")
				h.FillColor = rgb(180, 180, 190)
				h.FillTransparency = 0.55
				h.OutlineColor = rgb(230, 235, 255)
				h.OutlineTransparency = 0.3
				h.Adornee = p.Character
				h.Parent = pasta
				Debris:AddItem(h, DUR)
				table.insert(parados, r)
			end
		end
		-- segundo estalo: o tempo volta e sobe um redemoinho de poeira onde eles estavam
		task.delay(DUR - 0.35, function()
			if ch.Parent then animar(ch, "HoraDoCeu", 0.5) end
		end)
		task.delay(DUR, function()
			for _, r in ipairs(parados) do
				if r.Parent then redemoinhoDePoeira(r.Position, 0.7) end
			end
		end)
	end)
end

-- ⚠️ v113 — a Investida muda com o ELEMENTO do jogador (efeito no servidor,
-- VARIANTES_INVESTIDA; aqui só as cores): {meio, claro, forte}
local CORES_INVESTIDA = {
	Fogo = { rgb(255, 110, 20), rgb(255, 230, 140), rgb(255, 130, 40) },
	Vento = { rgb(150, 220, 255), rgb(235, 250, 255), rgb(170, 230, 255) },
	Void = { rgb(130, 50, 220), rgb(215, 180, 255), rgb(150, 70, 240) },
	Natureza = { rgb(70, 190, 70), rgb(200, 255, 170), rgb(90, 210, 90) },
	Luz = { rgb(255, 230, 120), rgb(255, 255, 230), rgb(255, 240, 160) },
}
VFX["Investida em Chamas"] = function(ch, root)
	animar(ch, "InvestidaChamas")
	local dono = Players:GetPlayerFromCharacter(ch)
	local pal = CORES_INVESTIDA[dono and dono:GetAttribute(Config.ELEMENT_ATTRIBUTE_NAME) or "Fogo"] or CORES_INVESTIDA.Fogo
	-- véu de chamas em ESPIRAL subindo do chão (0.1-0.45s)
	local base = noChao(root.Position, 0)
	local chamas = {}
	for i = 1, 3 do
		local p = parte({ Transparency = 1, Size = V3(0.3, 0.3, 0.3) })
		fogoEm(p, 70, 2, pal[1])
		rastroNaParte(p, 0.8, cores({ { 0, pal[2] }, { 1, pal[1] } }), 0.25, 0.9)
		chamas[i] = p
	end
	durante(0.9, function(t)
		local centro = root.Position
		local sobe = math.clamp(t / 0.45, 0, 1)
		for i, p in ipairs(chamas) do
			local ang = t * 14 + (i - 1) * (math.pi * 2 / 3)
			local y = (base.Y - centro.Y) + sobe * 6 * ((i - 1) / 3 + 0.4)
			p.CFrame = CFrame.new(centro + V3(math.cos(ang) * 2.4, y, math.sin(ang) * 2.4))
		end
	end, function()
		for _, p in ipairs(chamas) do
			for _, e in ipairs(p:GetChildren()) do if e:IsA("ParticleEmitter") then e.Enabled = false end end
			Debris:AddItem(p, 0.7)
		end
	end)
	for i = 0, 5 do
		task.delay(0.05 + i * 0.06, function()
			if not root.Parent then return end
			anel(V3(root.Position.X, base.Y + 0.3 + i * 0.9, root.Position.Z), Vector3.yAxis, pal[3], 3.5, 5.5, 0.35)
		end)
	end
	-- a investida: fogo no corpo e estouro em quem for jogado longe
	task.delay(0.45, function()
		if not root.Parent then return end
		local a = Instance.new("Attachment")
		a.Parent = root
		local fogo = fogoEm(a, 110, 2.4, pal[1])
		task.delay(0.6, function() fogo.Enabled = false; Debris:AddItem(a, 0.8) end)
		for _, alvo in ipairs(adversariosPerto(ch, root.Position, 10)) do
			onda(alvo.Position, frenteDe(root), pal[3], 9, 0.3, 0.3)
			faiscas(alvo.Position, pal[2], 30, 20)
		end
	end)
end

VFX["Bola Ilusão"] = function(ch, root)
	-- (⚠️ v113: sem a animação — agora ele anda livre enquanto as cópias saem)
	local bola = workspace:FindFirstChild(Config.BALL_NAME)
	local fantasmas = {}
	for i = 1, 2 do
		local f
		if bola then
			local ok, c = pcall(function() return bola:Clone() end)
			if ok and c then
				for _, filho in ipairs(c:GetChildren()) do
					if not (filho:IsA("DataModelMesh") or filho:IsA("Decal") or filho:IsA("Texture")) then filho:Destroy() end
				end
				c.Anchored = true
				c.CanCollide = false
				c.CanQuery = false
				c.CanTouch = false
				c.Transparency = 0.2
				c.Parent = pasta
				f = c
			end
		end
		f = f or parte({ Shape = Enum.PartType.Ball, Size = V3(1.7, 1.7, 1.7) })
		local aura = parte({ Shape = Enum.PartType.Ball, Color = rgb(190, 110, 255), Material = Enum.Material.ForceField,
			Size = f.Size * 1.35, Transparency = 0.1 })
		rastroNaParte(aura, 0.5, cores({ { 0, rgb(230, 190, 255) }, { 1, rgb(140, 60, 220) } }), 0.3, 1.0)
		fantasmas[i] = { Bola = f, Aura = aura }
	end
	task.delay(0.1, function() if bola then faiscas(bola.Position, rgb(200, 140, 255), 20, 8) end end)
	durante(1.0, function(t)
		local centro = (bola and bola.Position) or root.Position
		local abre = math.clamp((t - 0.1) / 0.2, 0, 1)
		local fecha = t > 0.75 and (1 - (t - 0.75) / 0.25) or 1
		for i, f in ipairs(fantasmas) do
			local ang = t * 9 + (i - 1) * math.pi
			local pos = centro + V3(math.cos(ang) * 3.4 * abre * fecha, 1.2 * abre + math.sin(t * 6 + i) * 0.6, math.sin(ang) * 3.4 * abre * fecha)
			f.Bola.CFrame = CFrame.new(pos) * CFrame.Angles(t * 8, t * 5, 0)
			f.Aura.CFrame = CFrame.new(pos)
			f.Bola.Transparency = abre > 0.05 and 0.2 or 1
			f.Aura.Transparency = abre > 0.05 and 0.3 or 1
		end
	end, function()
		for _, f in ipairs(fantasmas) do sumir(f.Bola, 0.12); sumir(f.Aura, 0.12) end
		if bola then faiscas(bola.Position, rgb(200, 140, 255), 25, 10) end
	end)
end

-- ⚠️ v113 — BOLA ILUSÃO: 2 cópias do jogador COM BOLA saem em 2 direções
-- (dados.Dirs, sorteadas no servidor entre frente e diagonais); ele é a
-- terceira figura. Em Duracao somem numa nuvem roxa.
VFX["Bola Ilusão@clones"] = function(ch, root, dados)
	if not dados or type(dados.Dirs) ~= "table" then return end
	local dur = dados.Duracao or 1.5
	local dist = dados.Distancia or 22
	local bolaReal = workspace:FindFirstChild(Config.BALL_NAME)
	local inicio = root.CFrame
	local antes = ch.Archivable
	ch.Archivable = true
	local copias = {}
	for i, dir in ipairs(dados.Dirs) do
		if typeof(dir) ~= "Vector3" then continue end
		local ok, c = pcall(function() return ch:Clone() end)
		if ok and c then
			for _, d in ipairs(c:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Sound") or d:IsA("Highlight")
					or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
					d:Destroy()
				elseif d:IsA("BasePart") then
					d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
					d.Anchored = d.Name == "HumanoidRootPart"
					d.Massless = true
				elseif d:IsA("Humanoid") then
					d.EvaluateStateMachine = false
				end
			end
			c.Parent = pasta
			local bola
			if bolaReal then
				local okB, b = pcall(function() return bolaReal:Clone() end)
				if okB and b then
					for _, f in ipairs(b:GetChildren()) do
						if not (f:IsA("DataModelMesh") or f:IsA("Decal") or f:IsA("Texture")) then f:Destroy() end
					end
					b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch = true, false, false, false
					b.Parent = pasta
					bola = b
				end
			end
			if _G.AnimadorRegistrar then _G.AnimadorRegistrar(c, { SempreNoChao = true }) end
			table.insert(copias, { Modelo = c, Root = c:FindFirstChild("HumanoidRootPart"), Dir = dir.Unit, Bola = bola })
		end
	end
	ch.Archivable = antes
	fumaca(noChao(root.Position, 0.5), cores({ { 0, rgb(210, 170, 255) }, { 1, rgb(120, 60, 200) } }), 12, 2, 5)
	-- ⚠️ v120b: TROCA de lugar — "some" na nuvem e as três figuras saem dela juntas
	if dados.Trocou then
		fumaca(noChao(root.Position, 1.5), cores({ { 0, rgb(235, 215, 255) }, { 1, rgb(140, 80, 220) } }), 26, 4, 3)
		faiscas(root.Position, rgb(210, 160, 255), 30, 12)
	end
	local raioBola = bolaReal and bolaReal.Size.X / 2 or 0.85
	-- ⚠️ v123 — TROCA DE LUGAR DE VERDADE: com dados.Meu/Troca, as TRÊS figuras saem e o
	-- jogador (e a bola) fica invisível até `Troca`; aí o servidor teleporta ele pro
	-- lugar da figura `Meu`, que some, e um puf sai nas três ao mesmo tempo.
	local trocaSeg = tonumber(dados.Troca)
	local meuIdx = tonumber(dados.Meu)
	local escondidos = {}
	local function esconder(modelo, sim)
		for _, d in ipairs(modelo:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				if sim then
					escondidos[d] = true
					d.LocalTransparencyModifier = 1
				elseif escondidos[d] then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end
	local trocou = false
	if trocaSeg and meuIdx then
		esconder(ch, true)
		if bolaReal then escondidos[bolaReal] = true; bolaReal.LocalTransparencyModifier = 1 end
	end
	local function fazerTroca()
		if trocou then return end
		trocou = true
		esconder(ch, false)
		if bolaReal then bolaReal.LocalTransparencyModifier = 0 end
		for i, cp in ipairs(copias) do
			local onde = cp.Root and cp.Root.Position or root.Position
			fumaca(onde, cores({ { 0, rgb(225, 195, 255) }, { 1, rgb(110, 50, 190) } }), 10, 2.5, 4)
			faiscas(onde, rgb(210, 160, 255), 14, 10)
			if i == meuIdx then
				-- a figura sorteada vira o jogador de verdade: some na hora
				if _G.AnimadorRemover then pcall(_G.AnimadorRemover, cp.Modelo) end
				cp.Modelo:Destroy()
				if cp.Bola then cp.Bola:Destroy() end
				cp.Root, cp.Bola, cp.Sumiu = nil, nil, true
			end
		end
	end
	durante(dur, function(t)
		if trocaSeg and meuIdx and t >= trocaSeg then fazerTroca() end
		for _, cp in ipairs(copias) do
			if cp.Root then
				local u = math.min(t / dur, 1)
				local pos = inicio.Position + cp.Dir * dist * u
				cp.Root.CFrame = CFrame.lookAt(pos, pos + cp.Dir)
				if cp.Bola then
					cp.Bola.CFrame = CFrame.new(noChao(pos + cp.Dir * 1.8, raioBola)) * CFrame.Angles(t * 10, 0, 0)
				end
			end
		end
	end, function()
		if trocaSeg and meuIdx then fazerTroca() end -- (garantia: nunca fica invisível)
		for _, cp in ipairs(copias) do
			if cp.Sumiu then continue end
			local onde = cp.Root and cp.Root.Position or root.Position
			fumaca(onde, cores({ { 0, rgb(225, 195, 255) }, { 1, rgb(110, 50, 190) } }), 18, 3, 7)
			faiscas(onde, rgb(210, 160, 255), 25, 14)
			anel(noChao(onde, 0.3), Vector3.yAxis, rgb(190, 120, 255), 1, 7, 0.35)
			if _G.AnimadorRemover then pcall(_G.AnimadorRemover, cp.Modelo) end
			for _, d in ipairs(cp.Modelo:GetDescendants()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then sumir(d, 0.25, { Size = d.Size * 0.3 }) end
			end
			if cp.Bola then sumir(cp.Bola, 0.25) end
			Debris:AddItem(cp.Modelo, 0.35)
		end
	end)
end

-- ⚠️ v113 — CEGUEIRA (Clarão de Fótons / Investida de Luz): quem está na lista
-- fica com a tela branca e ela volta aos poucos.
VFX["Clarão de Fótons@cegar"] = function(_ch, _root, dados)
	if not dados or type(dados.Vitimas) ~= "table" then return end
	local sou = false
	for _, id in ipairs(dados.Vitimas) do if id == LocalPlayer.UserId then sou = true end end
	if not sou then return end
	local dur = math.max(tonumber(dados.Duracao) or 1.5, 0.3)
	local gui = Instance.new("ScreenGui")
	gui.Name = "Cegueira"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 60
	gui.ResetOnSpawn = false
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = rgb(255, 252, 235)
	f.BackgroundTransparency = 0
	f.Parent = gui
	gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
	task.delay(dur * 0.4, function()
		TweenService:Create(f, TweenInfo.new(dur * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	end)
	Debris:AddItem(gui, dur + 0.1)
end

VFX["Faísca Zigue-Zague"] = function(ch, root)
	animar(ch, "FaiscaZigueZague")
	local AZUL = rgb(120, 200, 255)
	-- faíscas do atrito em cada pulo
	for i = 0, 2 do
		task.delay(0.1 + i * 0.1, function()
			if not root.Parent then return end
			local pe = noChao(root.Position, 0.3)
			faiscas(pe, AZUL, 22, 14)
			anel(pe, Vector3.yAxis, AZUL, 1, 4, 0.2, 0.15)
		end)
	end
	-- junta numa faísca só e solta em zigue-zague em cada marcador
	task.delay(0.5, function()
		if not root.Parent then return end
		local origem = root.Position + frenteDe(root) * 1.5
		local nucleo = parte({ Shape = Enum.PartType.Ball, Color = rgb(220, 240, 255), Size = V3(1.2, 1.2, 1.2), CFrame = CFrame.new(origem) })
		sumir(nucleo, 0.25, { Size = V3(3, 3, 3) })
		for _, alvo in ipairs(adversariosPerto(ch, root.Position, 18)) do
			local bolinha = parte({ Shape = Enum.PartType.Ball, Color = rgb(200, 235, 255), Size = V3(0.8, 0.8, 0.8), CFrame = CFrame.new(origem) })
			rastroNaParte(bolinha, 0.35, cores({ { 0, rgb(255, 255, 255) }, { 1, AZUL } }), 0.2, 0.4)
			local raio = E.NovoRaio and E.NovoRaio(pasta, rgb(150, 215, 255), 0.14)
			local lado = (alvo.Position - origem):Cross(Vector3.yAxis)
			lado = lado.Magnitude > 0.01 and lado.Unit or Vector3.xAxis
			durante(0.3, function(t)
				local u = t / 0.3
				local zig = math.sin(u * math.pi * 5) * 2.2 * (1 - u)
				local pos = origem:Lerp(alvo.Position, u) + lado * zig
				bolinha.CFrame = CFrame.new(pos)
				if raio then raio.Desenhar(origem, pos, 7, 1.4, 0.12, 0.2) end
			end, function()
				if raio then raio.Apagar() end
				sumir(bolinha, 0.1)
				if not alvo.Parent then return end
				faiscas(alvo.Position, AZUL, 35, 12)
				-- PARALISADO de joelhos, com faíscas presas no corpo
				animar(alvo.Parent, "Paralisado", 1.4)
				local a = Instance.new("Attachment")
				a.Parent = alvo
				local choque = emissor(a, { Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, AZUL } }), Tamanho = 0.3,
					Vida = { 0.1, 0.25 }, Vel = { 4, 9 }, Taxa = 45 })
				local r2 = E.NovoRaio and E.NovoRaio(pasta, rgb(170, 225, 255), 0.08)
				durante(1.3, function()
					if r2 and math.random() < 0.5 then
						local c = alvo.Position
						r2.Desenhar(c + V3(math.random() - 0.5, 1.5, math.random() - 0.5) * 2, c + V3(math.random() - 0.5, -1.5, math.random() - 0.5) * 2, 5, 0.6, 0.08, 0.1)
					end
				end, function()
					if r2 then r2.Apagar() end
					choque.Enabled = false
					Debris:AddItem(a, 0.3)
				end)
			end)
		end
	end)
end

VFX["Dobra Veloz"] = function(ch, root)
	animar(ch, "DobraVeloz")
	local ROXO = rgb(170, 90, 255)
	local base = noChao(root.Position, 0.3)
	-- NUVEM de poeira enorme na arrancada
	fumaca(base, cores({ { 0, rgb(220, 200, 170) }, { 1, rgb(140, 120, 100) } }), 35, 3, 14)
	anel(base, Vector3.yAxis, rgb(210, 190, 160), 2, 14, 0.5)
	-- teleporte em zigue-zague: vultos roxos alternando de lado + rajadas
	for i = 1, 6 do
		task.delay(i * 0.07, function()
			if not root.Parent then return end
			local lado = (i % 2 == 0) and 1.8 or -1.8
			vulto(ch, ROXO, 0.3, 0.22, Enum.Material.ForceField, root.CFrame.RightVector * lado)
			rajada(root.Position, -frenteDe(root), rgb(230, 220, 255), 3, 5)
			faiscas(root.Position, rgb(200, 150, 255), 6, 8)
		end)
	end
	-- freada de lado: poeira
	task.delay(0.62, function()
		if not root.Parent then return end
		fumaca(noChao(root.Position, 0.3), cores({ { 0, rgb(220, 200, 170) }, { 1, rgb(140, 120, 100) } }), 14, 2, 8)
	end)
end

-- ============================================================
-- DEFESAS
-- ============================================================
-- ⚠️ v110: todo carrinho de Hissatsu vai reto na mira, em qualquer lugar, cada um
-- com o deslocamento do anime (Carrinho / Corrida / Salto / Passo / Projetil —
-- ver _G.PulseExecuteTackle). O servidor manda "<nome>@inicio" (dados.Duracao,
-- dados.Dir) na saída e "<nome>" na CHEGADA — é lá que a técnica acontece.

VFX["Rasteira"] = function(ch, root)
	-- chegada: o golpe joga quem estava colado
	faiscas(root.Position, rgb(210, 255, 170), 25, 16)
	onda(noChao(root.Position, 0.2), Vector3.yAxis, rgb(170, 255, 120), 10, 0.3, 0.25)
end

VFX["Rasteira@inicio"] = function(ch, root, dados)
	-- (a pose é o carrinho do servidor) — várias PERNAS-FANTASMA chutando no deslize
	local perna = membro(ch, "Right Leg", "RightLowerLeg")
	if not perna then return end
	local VERDE = rgb(170, 255, 120)
	local ultimo = 0
	durante((dados and dados.Duracao) or 0.5, function(t)
		if t - ultimo < 0.035 then return end
		ultimo = t
		local quadril = perna.CFrame * CFrame.new(0, perna.Size.Y / 2, 0)
		local c = parte({ Color = VERDE, Material = Enum.Material.ForceField, Size = perna.Size, Transparency = 0.15,
			CFrame = quadril * CFrame.Angles(math.rad(math.random(-45, 45)), 0, math.rad(math.random(-25, 25))) * CFrame.new(0, -perna.Size.Y / 2, 0) })
		sumir(c, 0.18)
		if math.random() < 0.4 then faiscas(ponta(perna), rgb(210, 255, 170), 4, 6) end
	end)
	fumaca(noChao(root.Position, 0.3), cores({ { 0, rgb(200, 185, 150) }, { 1, rgb(130, 115, 90) } }), 10, 1.5, 6)
end

local sombraAtiva = {} -- [character] = { Faixa, Parou, Fim, Alvo }
VFX["Costura de Sombra"] = function(ch, root, dados)
	-- ⚠️ v110: a sombra corre RETA na mira (dados.Dir) até o alcance, com ele
	-- fincado segurando ("não posso me mover, tô criando a sombra"); se pegar
	-- alguém chega "@agarra" e ela vira a mão nas pernas dele.
	animar(ch, "Costura")
	dados = dados or {}
	local SOMBRA = rgb(15, 10, 25)
	local dir = typeof(dados.Dir) == "Vector3" and dados.Dir or frenteDe(root)
	local alcance = dados.Alcance or 46
	local vel = dados.Vel or 85
	local atraso = dados.Atraso or 0.45
	local origem = root.Position
	local estado = { Parou = false }
	sombraAtiva[ch] = estado
	task.delay(0.5, function()
		if not estado.Parou and ch.Parent then animar(ch, "CosturaSegura", math.max(atraso + alcance / vel - 0.5, 0.3)) end
	end)
	task.delay(atraso, function()
		local faixa = parte({ Color = SOMBRA, Material = Enum.Material.SmoothPlastic, Transparency = 0.25, Size = V3(5.4, 0.05, 0.1) })
		estado.Faixa = faixa
		local de = noChao(origem, 0.06)
		durante(alcance / vel + 0.05, function(t)
			if estado.Parou then return end
			local len = math.min(alcance, t * vel)
			local fim = de + dir * len
			if len > 0.1 then
				faixa.Size = V3(5.4, 0.05, len)
				faixa.CFrame = CFrame.lookAt((de + fim) / 2, fim)
			end
		end, function()
			if not estado.Parou then
				-- não pegou ninguém: a sombra se desfaz
				sumir(faixa, 0.4)
				if sombraAtiva[ch] == estado then sombraAtiva[ch] = nil end
			end
		end)
	end)
end

VFX["Costura de Sombra@agarra"] = function(ch, root, dados)
	local estado = sombraAtiva[ch] or { Parou = true }
	sombraAtiva[ch] = estado
	estado.Parou = true
	local alvoModel = dados and dados.Alvo
	local alvo = typeof(alvoModel) == "Instance" and alvoModel:FindFirstChild("HumanoidRootPart")
	if not alvo then return end
	local SOMBRA = rgb(15, 10, 25)
	estado.Fim = os.clock() + ((dados and dados.Duracao) or 1.5)
	animar(ch, "CosturaSegura", (dados and dados.Duracao) or 1.5)
	-- vira uma MÃO que sai do chão e agarra as pernas
	local base = noChao(alvo.Position, 0)
	local dedos = {}
	for k = 1, 5 do
		local ang = (k / 5) * math.pi * 2
		local d = parte({ Color = SOMBRA, Material = Enum.Material.SmoothPlastic, Transparency = 0.1, Size = V3(0.55, 0.1, 0.55),
			CFrame = CFrame.new(base + V3(math.cos(ang) * 1.3, 0, math.sin(ang) * 1.3)) })
		TweenService:Create(d, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = V3(0.55, 3.2, 0.55),
			CFrame = CFrame.new(base + V3(math.cos(ang) * 1.0, 1.4, math.sin(ang) * 1.0)) * CFrame.Angles(-math.sin(ang) * 0.45, 0, math.cos(ang) * 0.45),
		}):Play()
		dedos[k] = d
	end
	local palma = parte({ Color = SOMBRA, Material = Enum.Material.SmoothPlastic, Shape = Enum.PartType.Cylinder,
		Size = V3(0.3, 3.4, 3.4), CFrame = CFrame.new(base + V3(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 0.15 })
	fumaca(base + V3(0, 0.5, 0), cores({ { 0, rgb(60, 30, 80) }, { 1, rgb(20, 10, 30) } }), 10, 1.5, 4)
	-- a faixa liga os dois até soltar (o QTE pode esticar — ver "@segura")
	local faixa = estado.Faixa or parte({ Color = SOMBRA, Material = Enum.Material.SmoothPlastic, Transparency = 0.25, Size = V3(5.4, 0.05, 0.1) })
	durante(2.5, function()
		if os.clock() >= estado.Fim then return end
		local de = noChao(root.Position, 0.06)
		local ate = noChao(alvo.Position, 0.06)
		local len = (ate - de).Magnitude
		if len > 0.1 then
			faixa.Size = V3(5.4, 0.05, len)
			faixa.CFrame = CFrame.lookAt((de + ate) / 2, ate)
		end
	end)
	task.spawn(function()
		while os.clock() < estado.Fim do task.wait(0.05) end
		for _, d in ipairs(dedos) do sumir(d, 0.25) end
		sumir(palma, 0.25)
		sumir(faixa, 0.25)
		if sombraAtiva[ch] == estado then sombraAtiva[ch] = nil end
	end)
end

VFX["Costura de Sombra@segura"] = function(ch, root, dados)
	-- QTE: cada A/D certo estica o agarrão (até 2s no total)
	local estado = sombraAtiva[ch]
	if not estado or not estado.Fim then return end
	local resta = (dados and dados.Duracao) or 0
	estado.Fim = math.max(estado.Fim, os.clock() + resta)
	animar(ch, "CosturaSegura", resta)
end

VFX["Teia"] = function(ch, root)
	animar(ch, "Teia")
	local dono = Players:GetPlayerFromCharacter(ch)
	local centro = root.Position
	local FIO = rgb(240, 250, 235)
	-- fios saindo da mão no chão
	task.delay(0.74, function()
		if not root.Parent then return end
		local mao = ponta(membro(ch, "Right Arm", "RightHand")) or root.Position
		local base = noChao(mao, 0.1)
		faiscas(base, FIO, 25, 12)
		for k = 1, 10 do
			local ang = (k / 10) * math.pi * 2
			local f = parte({ Color = FIO, Size = V3(0.08, 0.05, 0.2), Transparency = 0.1,
				CFrame = CFrame.lookAt(base, base + V3(math.cos(ang), 0, math.sin(ang))) })
			TweenService:Create(f, TweenInfo.new(0.35), { Size = V3(0.08, 0.05, 9), CFrame = CFrame.lookAt(base + V3(math.cos(ang), 0, math.sin(ang)) * 4.5, base + V3(math.cos(ang), 0, math.sin(ang)) * 9), Transparency = 1 }):Play()
			Debris:AddItem(f, 0.4)
		end
	end)
	-- quem pisar na teia fica grudado: fios das pernas até o chão
	local ultimo = 0
	durante(8, function(t)
		if t - ultimo < 0.3 then return end
		ultimo = t
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= dono and not (dono and dono.Team and p.Team == dono.Team) and p.Character then
				local r = p.Character:FindFirstChild("HumanoidRootPart")
				if r and V3(r.Position.X - centro.X, 0, r.Position.Z - centro.Z).Magnitude <= 42 then
					local pe = r.Position - V3(0, 2, 0)
					local chao = chaoDe(r.Position)
					for _ = 1, 3 do
						local alvo = V3(pe.X + math.random(-25, 25) / 10, chao + 0.05, pe.Z + math.random(-25, 25) / 10)
						local len = (alvo - pe).Magnitude
						local f = parte({ Color = FIO, Size = V3(0.07, 0.07, len), Transparency = 0.15, CFrame = CFrame.lookAt((pe + alvo) / 2, alvo) })
						sumir(f, 0.45)
					end
				end
			end
		end
	end)
end

VFX["Muralha Infinita"] = function(ch, root)
	animar(ch, "Muralha", 5)
	local frente = frenteDe(root)
	local lado = frente:Cross(Vector3.yAxis).Unit
	-- ⚠️ v120b — PEDIDO: "a muralha tá muito pequena: o tamanho base é pra ser
	-- literalmente GIGANTE (gostei da aparência)". Mesmas medidas da barreira no
	-- servidor (_G.MuroDaBarreira / Muro em PulseInstinctData): 40 x 26 sozinho,
	-- +10 de largura e +3 de altura por companheiro perto (até 2), 8 studs à frente.
	local aliados = math.min(companheirosPerto(ch, 45), 2)
	local largura, alturaMuro = 40 + 10 * aliados, 26 + 3 * aliados
	local n = math.ceil(largura / 6.2)
	local larguraBloco = largura / n
	local base = noChao(root.Position, 0)
	local muros = {}
	task.delay(0.4, function()
		for i = 1, n do
			local off = (i - (n + 1) / 2)
			local pos = base + frente * (8 + math.abs(off) * -0.25) + lado * off * larguraBloco
			local altura = alturaMuro * (0.9 + math.random() * 0.18)
			local m = parte({ Material = Enum.Material.Slate, Color = rgb(140 + math.random(-15, 15), 115, 85), Transparency = 0,
				Size = V3(larguraBloco + 0.6, altura, 4), CFrame = CFrame.lookAt(pos - V3(0, altura / 2, 0), pos - V3(0, altura / 2, 0) + frente) })
			m.CanQuery = false
			local alvo = CFrame.lookAt(pos + V3(0, altura / 2 - 0.3, 0), pos + V3(0, altura / 2 - 0.3, 0) + frente) * CFrame.Angles(math.rad(math.random(-5, 5)), 0, math.rad(math.random(-4, 4)))
			task.delay(i * 0.06, function()
				TweenService:Create(m, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = alvo }):Play()
				fumaca(pos + V3(0, 0.5, 0), cores({ { 0, rgb(200, 180, 150) }, { 1, rgb(120, 100, 80) } }), 12, 2.2, 8)
			end)
			muros[i] = m
		end
		onda(base + V3(0, 0.2, 0), Vector3.yAxis, rgb(190, 160, 110), largura * 1.4, 0.5, 0.35)
		-- o campo treme (câmera de quem está perto)
		local meu = meuRoot()
		local hum = meu and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		if hum and (meu.Position - root.Position).Magnitude < 40 then
			local original = hum.CameraOffset
			durante(0.45, function(t)
				local f = 0.5 * (1 - t / 0.45)
				hum.CameraOffset = original + V3((math.random() - 0.5) * f, (math.random() - 0.5) * f, 0)
			end, function() hum.CameraOffset = original end)
		end
	end)
	-- desmorona no fim (5s)
	task.delay(4.8, function()
		for _, m in ipairs(muros) do
			if m.Parent then
				TweenService:Create(m, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = m.CFrame - V3(0, m.Size.Y, 0), Transparency = 0.6 }):Play()
				fumaca(m.Position - V3(0, m.Size.Y / 2 - 0.5, 0), cores({ { 0, rgb(200, 180, 150) }, { 1, rgb(120, 100, 80) } }), 8, 2, 6)
				Debris:AddItem(m, 0.55)
			end
		end
	end)
end

-- ⚠️ v120b: a bola BATE no muro (o servidor manda onde): poeira, lascas e um tremor
VFX["Muralha Infinita@impacto"] = function(_ch, _root, dados)
	local ponto = dados and typeof(dados.Posicao) == "Vector3" and dados.Posicao
	if not ponto then return end
	anel(ponto, Vector3.yAxis, rgb(220, 190, 140), 2, 14, 0.4, 0.3)
	fumaca(ponto, cores({ { 0, rgb(210, 190, 160) }, { 1, rgb(130, 110, 85) } }), 18, 2.5, 10)
	for _ = 1, 8 do
		local lasca = parte({ Material = Enum.Material.Slate, Color = rgb(150, 120, 90), Transparency = 0,
			Size = V3(0.6 + math.random(), 0.5 + math.random() * 0.6, 0.6 + math.random()), CFrame = CFrame.new(ponto) })
		local destino = ponto + V3(math.random(-6, 6), math.random(2, 7), math.random(-6, 6))
		TweenService:Create(lasca, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(destino) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 }):Play()
		Debris:AddItem(lasca, 0.65)
	end
end

VFX["Pisão de Sumô"] = function(ch, _root)
	-- ⚠️ v113: o pisão cai NA MIRA (ver "@mira"); aqui só a pose
	animar(ch, "PisaoSumo")
end
VFX["Pisão de Sumô@mira"] = function(ch, root, dados)
	local AMARELO = rgb(255, 225, 80)
	local ponto = (dados and typeof(dados.Posicao) == "Vector3") and dados.Posicao or root.Position
	local raio = (dados and dados.Raio) or 13
	-- o PÉ GIGANTE desce no ponto mirado
	local giro = CFrame.Angles(0, math.rad(root.Orientation.Y), 0)
	local pe = parte({ Color = AMARELO, Size = V3(8, 3.2, 12.5), Transparency = 0.15, CFrame = CFrame.new(ponto + V3(0, 26, 0)) * giro })
	local dedoes = parte({ Color = AMARELO, Size = V3(8, 2, 3.2), Transparency = 0.15, CFrame = pe.CFrame * CFrame.new(0, -0.5, -7.3) })
	local luzPe = Instance.new("PointLight")
	luzPe.Color = AMARELO
	luzPe.Range = 20
	luzPe.Parent = pe
	TweenService:Create(pe, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(ponto + V3(0, 1.6, 0)) * giro }):Play()
	TweenService:Create(dedoes, TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(ponto + V3(0, 1.1, 0)) * giro * CFrame.new(0, 0, -7.3) }):Play()
	task.delay(0.9, function() sumir(pe, 0.3); sumir(dedoes, 0.3) end)
	task.delay(0.38, function() -- o PISÃO
		if not root.Parent then return end
		local base = noChao(ponto, 0.2)
		for _, alvo in ipairs(adversariosPerto(ch, ponto, raio)) do
			if alvo.Parent then animar(alvo.Parent, "Achatado", 0.9) end
		end
		for i = 0, 2 do
			task.delay(i * 0.09, function()
				anel(base, Vector3.yAxis, AMARELO, 3, 16 + i * 5, 0.5, 0.35)
			end)
		end
		onda(base, Vector3.yAxis, rgb(255, 240, 150), raio * 2, 0.3, 0.3)
		fumaca(base, cores({ { 0, rgb(220, 200, 150) }, { 1, rgb(150, 130, 90) } }), 14, 2, 8)
		-- (o pé grande já desceu no ponto; os pés menores em cima dos outros saíram)
		for i, alvo in ipairs({}) do
			if i > 3 then break end
			task.delay(0.1 + i * 0.06, function()
				if not alvo.Parent then return end
				local onde = noChao(alvo.Position, 0)
				local giro = CFrame.Angles(0, math.rad(root.Orientation.Y), 0)
				local pe = parte({ Color = AMARELO, Size = V3(6, 2.6, 9.5), Transparency = 0.15, CFrame = CFrame.new(onde + V3(0, 16, 0)) * giro })
				local dedoes = parte({ Color = AMARELO, Size = V3(6, 1.6, 2.4), Transparency = 0.15, CFrame = pe.CFrame * CFrame.new(0, -0.4, -5.5) })
				local luz = Instance.new("PointLight")
				luz.Color = AMARELO
				luz.Range = 16
				luz.Parent = pe
				TweenService:Create(pe, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(onde + V3(0, 1.3, 0)) * giro }):Play()
				TweenService:Create(dedoes, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(onde + V3(0, 0.9, 0)) * giro * CFrame.new(0, 0, -5.5) }):Play()
				task.delay(0.2, function()
					if alvo.Parent then animar(alvo.Parent, "Achatado", 0.9) end
					onda(onde + V3(0, 0.2, 0), Vector3.yAxis, AMARELO, 12, 0.3, 0.3)
					task.delay(0.35, function() sumir(pe, 0.3); sumir(dedoes, 0.3) end)
				end)
			end)
		end
	end)
end

local corteAtivo = {} -- [character] = { Parou }
VFX["Corte Giratório@inicio"] = function(ch, root)
	-- salta, pé azul e o CHUTE GIRATÓRIO no lugar
	animar(ch, "CorteGiratorio")
	local perna = membro(ch, "Right Leg", "RightLowerLeg")
	if perna then rastroNaParte(perna, perna.Size.Y / 2, cores({ { 0, rgb(220, 240, 255) }, { 1, rgb(90, 180, 255) } }), 0.3, 0.5) end
end

VFX["Corte Giratório"] = function(ch, root, dados)
	-- a MEIA-LUA azul corre pelo chão na mira (dados.Dir/Vel/Alcance) até o servidor
	-- avisar onde ela parou ("@muro")
	local AZUL = rgb(90, 180, 255)
	dados = dados or {}
	local dir = typeof(dados.Dir) == "Vector3" and dados.Dir or frenteDe(root)
	local vel = dados.Vel or 70
	local alcance = dados.Alcance or 40
	local base = noChao(root.Position, 0.25)
	local estado = { Parou = false }
	corteAtivo[ch] = estado
	local desenhar, pecas = meiaLua(AZUL, 4.5, 11, 0.8)
	durante(alcance / vel + 0.1, function(t)
		if estado.Parou then return end
		local andado = math.min(alcance, t * vel)
		local pos = base + dir * (1 + andado)
		desenhar(CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, 4.5), 1, 1 + math.min(andado / alcance, 1) * 0.3)
	end, function()
		for _, p in ipairs(pecas) do sumir(p, 0.1) end
	end)
	estado.Pecas = pecas
end

VFX["Corte Giratório@muro"] = function(ch, root, dados)
	local estado = corteAtivo[ch]
	if estado then
		estado.Parou = true
		for _, p in ipairs(estado.Pecas or {}) do sumir(p, 0.1) end
		corteAtivo[ch] = nil
	end
	local AZUL = rgb(90, 180, 255)
	local dir = (dados and typeof(dados.Dir) == "Vector3") and dados.Dir or frenteDe(root)
	local ponto = (dados and typeof(dados.Posicao) == "Vector3") and noChao(dados.Posicao, 0.25) or noChao(root.Position + dir * 12, 0.25)
	-- o MURO de fogo azul sobe de onde a meia-lua parou
	-- ⚠️ v120b: maior e FICA DE PÉ (o servidor manda Duracao/Largura/Altura — a bola
	-- que bate nele perde força, ver _G.RegistrarCorteAzul no BallController)
	local larg = (dados and dados.Largura) or 16
	local alt = (dados and dados.Altura) or 10
	local dur = (dados and dados.Duracao) or 3.5
	local muro = parte({ Color = rgb(110, 200, 255), Size = V3(larg, 0.2, 1.2), Transparency = 0.25,
		CFrame = CFrame.lookAt(ponto, ponto + dir) })
	TweenService:Create(muro, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = V3(larg, alt, 1.2), CFrame = CFrame.lookAt(ponto + V3(0, alt / 2, 0), ponto + V3(0, alt / 2, 0) + dir) }):Play()
	local fogo = emissor(muro, {
		Textura = TEX.Fogo, Cor = cores({ { 0, rgb(220, 245, 255) }, { 0.5, AZUL }, { 1, rgb(30, 60, 200) } }), Brilho = 1,
		Tamanho = numeros({ { 0, 3 }, { 1, 0.5 } }), Vida = { 0.3, 0.6 }, Vel = { 3, 8 }, Acel = V3(0, 10, 0), Taxa = 120,
	})
	faiscas(ponto + V3(0, 3, 0), rgb(150, 215, 255), 40, 22)
	-- (tremeluz enquanto está de pé)
	durante(dur, function(t)
		if muro.Parent then muro.Transparency = 0.3 + 0.12 * math.sin(t * 14) end
	end)
	task.delay(dur, function() fogo.Enabled = false; sumir(muro, 0.35) end)
end

VFX["Roubo Congelante@inicio"] = function(ch, root, dados)
	local GELO = rgb(190, 235, 255)
	local dur = (dados and dados.Duracao) or 0.6
	-- (a pose é o carrinho do servidor) — perna esquerda coberta de gelo
	local perna = membro(ch, "Left Leg", "LeftLowerLeg")
	if perna then
		local capa = parte({ Material = Enum.Material.Ice, Color = GELO, Transparency = 0.25, Size = perna.Size * 1.3 })
		durante(dur + 0.3, function() capa.CFrame = perna.CFrame end, function() sumir(capa, 0.25) end)
		rastroNaParte(perna, perna.Size.Y / 2, cores({ { 0, rgb(255, 255, 255) }, { 1, GELO } }), 0.3, dur)
	end
	-- o chão vai congelando por onde ele desliza (a reta inteira)
	local frente = frenteDe(root)
	local ultimo = -1
	durante(dur, function(t)
		if t - ultimo < 0.045 then return end
		ultimo = t
		local c = noChao(root.Position, 0.08)
		local p = parte({ Material = Enum.Material.Ice, Color = GELO, Transparency = 0.3, Size = V3(4.5, 0.2, 3.2),
			CFrame = CFrame.lookAt(c, c + frente) * CFrame.Angles(0, math.rad(math.random(-10, 10)), 0) })
		task.delay(1.4, function() sumir(p, 0.4) end)
		if math.random() < 0.5 then faiscas(c + V3(0, 0.4, 0), GELO, 8, 8) end
	end)
end

VFX["Roubo Congelante"] = function(ch, root)
	-- chegada: quem estava perto vira bloco de gelo
	local GELO = rgb(190, 235, 255)
	onda(noChao(root.Position, 0.15), Vector3.yAxis, GELO, 18, 0.35, 0.25)
	task.delay(0.05, function()
		for _, alvo in ipairs(adversariosPerto(ch, root.Position, 12)) do blocoDeGelo(alvo, 1.4) end
	end)
end

VFX["Clarão de Fótons@inicio"] = function(ch, root, dados)
	-- corre com os braços pra trás deixando um RASTRO de brilhos (a pose vem do servidor)
	local a = Instance.new("Attachment")
	a.Parent = root
	local brilhos = emissor(a, { Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 220, 120) } }), Tamanho = 0.4,
		Vida = { 0.5, 0.9 }, Vel = { 0, 1 }, Taxa = 110 })
	local torso = membro(ch, "Torso", "UpperTorso")
	if torso then rastroNaParte(torso, 1, cores({ { 0, rgb(255, 255, 240) }, { 1, rgb(255, 210, 110) } }), 0.35, (dados and dados.Duracao) or 0.6) end
	task.delay((dados and dados.Duracao) or 0.6, function() brilhos.Enabled = false; Debris:AddItem(a, 1) end)
end

VFX["Clarão de Fótons"] = function(ch, root)
	animar(ch, "ClaraoFotons")
	local LUZ = rgb(255, 250, 215)
	-- brilhos atrás dele e JUNTANDO no giro
	local a = Instance.new("Attachment")
	a.Parent = root
	local brilhos = emissor(a, { Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 220, 120) } }), Tamanho = 0.35,
		Vida = { 0.4, 0.8 }, Vel = { 0, 1 }, Taxa = 70 })
	local junta = emissor(a, { Cor = cores({ { 0, rgb(255, 255, 255) }, { 1, rgb(255, 230, 140) } }), Tamanho = 0.4,
		Vida = { 0.3, 0.35 }, Vel = { 12, 16 }, Forma = Enum.ParticleEmitterShape.Sphere, Sentido = Enum.ParticleEmitterShapeInOut.Inward, Taxa = 0 })
	task.delay(0.2, function() junta.Rate = 160; junta.Enabled = true; brilhos.Enabled = false end)
	task.delay(0.5, function() junta.Enabled = false; Debris:AddItem(a, 1) end)
	-- escurece em volta e... CLARÃO
	task.delay(0.42, function()
		local meu = meuRoot()
		if meu and (meu.Position - root.Position).Magnitude <= 40 then
			corDaTela({ Brightness = -0.45, Saturation = -0.3 }, { Brightness = 0, Saturation = 0 }, 0.15)
		end
	end)
	task.delay(0.56, function()
		if not root.Parent then return end
		local luz = parte({ Shape = Enum.PartType.Ball, Color = LUZ, Size = V3(3, 3, 3), CFrame = CFrame.new(root.Position), Transparency = 0 })
		local pl = Instance.new("PointLight")
		pl.Range = 45
		pl.Brightness = 10
		pl.Color = LUZ
		pl.Parent = luz
		sumir(luz, 0.5, { Size = V3(34, 34, 34) })
		for k = 1, 8 do -- raios de luz
			local ang = (k / 8) * math.pi * 2
			local r = parte({ Color = LUZ, Size = V3(0.4, 0.4, 2), CFrame = CFrame.lookAt(root.Position, root.Position + V3(math.cos(ang), 0.2, math.sin(ang))) })
			sumir(r, 0.35, { Size = V3(0.1, 0.1, 30), CFrame = CFrame.lookAt(root.Position, root.Position + V3(math.cos(ang), 0.2, math.sin(ang))) * CFrame.new(0, 0, -15) })
		end
		-- quem está perto (e não é do time de quem usou) fica CEGO por um instante
		local meu = meuRoot()
		local dono = Players:GetPlayerFromCharacter(ch)
		if meu and (meu.Position - root.Position).Magnitude <= 26 and dono ~= LocalPlayer and (not dono or dono.Team ~= LocalPlayer.Team) then
			corDaTela({ Brightness = 0.85, Contrast = -0.4 }, { Brightness = 0, Contrast = 0 }, 1.6)
		end
	end)
end

VFX["Anjo da Neve@inicio"] = function(ch, root)
	-- o SALTO girando (o servidor leva o corpo em arco até o ponto; cai aos 0.84s)
	animar(ch, "AnjoDaNeve")
	local GELO = rgb(215, 242, 255)
	local ultimo = -1
	durante(0.7, function(t)
		if t < 0.12 or t - ultimo < 0.06 then return end
		ultimo = t
		anel(root.Position + V3(0, -1.5 + (t * 10) % 4, 0), Vector3.yAxis, GELO, 3, 6.5, 0.3, 0.2)
		faiscas(root.Position, GELO, 5, 8)
	end)
	-- cortes crescentes de gelo mandados pro chão (um por perna)
	for i, quando in ipairs({ 0.3, 0.5 }) do
		task.delay(quando, function()
			if not root.Parent then return end
			local frente = frenteDe(root)
			local ang = (i == 1) and 0.6 or -0.6
			local dir = (CFrame.Angles(0, ang, 0) * frente)
			local base = noChao(root.Position, 0.25)
			local desenhar, pecas = meiaLua(rgb(170, 225, 255), 3.5, 9, 0.6)
			durante(0.3, function(t)
				local u = t / 0.3
				local pos = base + dir * (2 + 14 * u)
				desenhar(CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0, 3.5), 1 - u * 0.3, 1)
			end, function() for _, p in ipairs(pecas) do sumir(p, 0.1) end end)
		end)
	end
	-- neve caindo na área
	local ar = parte({ Transparency = 1, Size = V3(56, 2, 56), CFrame = CFrame.new(root.Position + V3(0, 16, 0)) })
	local neve = emissor(ar, { Cor = rgb(255, 255, 255), Brilho = 0.6, Tamanho = numeros({ { 0, 0.35 }, { 1, 0.3 } }),
		Vida = { 1.6, 2.4 }, Vel = { 4, 8 }, Direcao = Enum.NormalId.Bottom, Spread = 15, Forma = Enum.ParticleEmitterShape.Box, Taxa = 220 })
	task.delay(2.4, function() neve.Enabled = false; Debris:AddItem(ar, 2.5) end)
end

VFX["Anjo da Neve"] = function(ch, root)
	-- a ATERRISSAGEM: o campo vira gelo e os adversários viram blocos de gelo
	local GELO = rgb(215, 242, 255)
	local base = noChao(root.Position, 0.06)
	local campo = parte({ Material = Enum.Material.Ice, Color = rgb(200, 235, 255), Shape = Enum.PartType.Cylinder, Transparency = 0.35,
		Size = V3(0.12, 4, 4), CFrame = CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90)) })
	TweenService:Create(campo, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = V3(0.12, 56, 56) }):Play()
	task.delay(2.2, function() sumir(campo, 0.5) end)
	onda(base + V3(0, 0.1, 0), Vector3.yAxis, GELO, 30, 0.4, 0.3)
	faiscas(base + V3(0, 0.5, 0), GELO, 40, 16)
	for _, alvo in ipairs(adversariosPerto(ch, root.Position, 28)) do blocoDeGelo(alvo, 2.2) end
end

-- (a Chuva de Meteoros agora é cutscene — HissatsuCutscenes.ChuvaDeMeteoros)

-- ⚠️ v113 — SUMIÇO NO VOO (Kamikakushi, pelo vídeo do Inazuma Eleven 3): onde a
-- bola some, na frente do goleiro, sobe um TORII vermelho no meio de uma névoa
-- roxa, com um redemoinho girando por dentro dele; some quando a bola volta.
VFX["Sumiço@torii"] = function(ch, root, dados)
	if not dados or typeof(dados.Posicao) ~= "Vector3" then return end
	local ROXO, ESCURO, VERMELHO = rgb(170, 70, 255), rgb(45, 0, 70), rgb(200, 30, 25)
	local dur = math.max(tonumber(dados.Duracao) or 0.5, 0.35) + 0.35
	local dir = typeof(dados.Dir) == "Vector3" and V3(dados.Dir.X, 0, dados.Dir.Z) or V3(0, 0, -1)
	dir = dir.Magnitude > 0.05 and dir.Unit or V3(0, 0, -1)
	local base = noChao(dados.Posicao + dir * 4, 0)
	local cf = CFrame.lookAt(base, base + dir)
	-- torii: 2 pilares, a viga de cima (kasagi, mais larga) e a de baixo (nuki)
	local pecas = {}
	local function peca(tam, rel, cor)
		local p = parte({ Size = tam, CFrame = cf * rel, Color = cor, Material = Enum.Material.SmoothPlastic, Transparency = 1 })
		table.insert(pecas, p)
		return p
	end
	peca(V3(1.1, 11, 1.1), CFrame.new(-5, 5.5, 0), VERMELHO)
	peca(V3(1.1, 11, 1.1), CFrame.new(5, 5.5, 0), VERMELHO)
	peca(V3(15, 1, 1.6), CFrame.new(0, 11.4, 0), rgb(40, 20, 20))
	peca(V3(13.5, 0.8, 1.3), CFrame.new(0, 10.6, 0), VERMELHO)
	peca(V3(11, 0.6, 0.8), CFrame.new(0, 8.6, 0), VERMELHO)
	-- redemoinho: disco roxo girando dentro do portal + anéis sugando
	-- ForceField: o próprio material já tem o padrão girando (o redemoinho do vídeo)
	local disco = parte({ Shape = Enum.PartType.Cylinder, Size = V3(0.2, 9, 9), Color = rgb(150, 60, 255), Transparency = 1,
		Material = Enum.Material.ForceField,
		CFrame = cf * CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(90), 0) })
	local miolo = parte({ Shape = Enum.PartType.Cylinder, Size = V3(0.25, 3, 3), Color = ESCURO, Transparency = 1,
		CFrame = cf * CFrame.new(0, 5, -0.1) * CFrame.Angles(0, math.rad(90), 0) })
	fumaca(base + V3(0, 1, 0), cores({ { 0, rgb(110, 40, 170) }, { 1, rgb(30, 0, 50) } }), 26, 5, 5)
	faiscas(dados.Posicao, rgb(230, 190, 255), 30, 18)
	local proxAnel = 0
	durante(dur, function(t)
		local entra = math.clamp(t / 0.15, 0, 1)
		local sai = math.clamp((dur - t) / 0.2, 0, 1)
		local a = entra * sai
		for _, p in ipairs(pecas) do p.Transparency = 1 - a end
		disco.Transparency = 1 - a
		miolo.Transparency = 1 - a * 0.9
		disco.CFrame = cf * CFrame.new(0, 5, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(t * 9, 0, 0)
		if t >= proxAnel and a > 0.3 then
			proxAnel = t + 0.1
			anel((cf * CFrame.new(0, 5, 0.2)).Position, cf.LookVector, rgb(230, 170, 255), 9, 1.5, 0.3, 0.25)
		end
	end, function()
		for _, p in ipairs(pecas) do p:Destroy() end
		disco:Destroy()
		miolo:Destroy()
	end)
end
VFX["Sumiço@volta"] = function(ch, root, dados)
	if not dados or typeof(dados.Posicao) ~= "Vector3" then return end
	local ROXO = rgb(170, 70, 255)
	local p = parte({ Shape = Enum.PartType.Ball, Size = V3(2, 2, 2), Color = rgb(235, 190, 255), Transparency = 0.1, CFrame = CFrame.new(dados.Posicao) })
	sumir(p, 0.35, { Size = V3(9, 9, 9) })
	faiscas(dados.Posicao, ROXO, 40, 24)
	anel(dados.Posicao, Vector3.yAxis, ROXO, 2, 12, 0.4, 0.3)
end

local function aoHissatsuVFX(character, nome, elemento, dados)
	if typeof(character) ~= "Instance" or not character:IsA("Model") then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	local f = VFX[nome]
	if root and f then
		local ok, err = pcall(f, character, root, typeof(dados) == "table" and dados or nil, elemento)
		if not ok then warn("[HissatsuVFX] " .. tostring(nome) .. ": " .. tostring(err)) end
	end
end
Remotes.HissatsuVFX.OnClientEvent:Connect(aoHissatsuVFX)
-- ⚠️ v112: o replay de gol repete os efeitos de Hissatsu (drible/carrinho) no fantasma
_G.HissatsuVFXLocal = aoHissatsuVFX
