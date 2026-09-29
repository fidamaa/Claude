--[[
	StadiumLighting (Script)
	LOCAL: ServerScriptService (place Game)

	⚠️ v25 — PEDIDO: "faz um clima legal pra uma partida de futebol, pra um
	campo de futebol, que pareça bonito visualmente, como se fosse um
	shader. Pesquisa como funciona cada coisa e NÃO AJUSTE O QUE VOCÊ NÃO
	SABE."

	Então: só mexe em propriedade que eu sei o que faz, e cada uma tem um
	comentário dizendo o que ela faz E por que está nesse valor. O que eu
	não tenho certeza fica de fora de propósito (ver "O QUE EU NÃO MEXO" no
	fim do arquivo).

	COMO USAR: escolha o preset em ACTIVE_PRESET logo abaixo. Os números
	todos moram nas tabelas — não precisa ler o resto do arquivo pra
	ajustar nada.

	⚠️ UMA COISA SÓ VOCÊ CONSEGUE FAZER, NO STUDIO: Lighting.Technology é
	somente-leitura em runtime, script nenhum consegue mudar. Ela precisa
	estar em "Future" pro resto aqui valer de verdade (sombras de qualidade,
	luz do ambiente, reflexo). Selecione Lighting no Explorer e ponha
	Technology = Future. Se não estiver, este script avisa no Output toda
	vez que a partida começa.

	Fontes da pesquisa:
	  create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-outdoor-environments
	  create.roblox.com/docs/environment/lighting
]]

local Lighting = game:GetService("Lighting")

-- ============================================================
-- ESCOLHA AQUI
-- ============================================================
local ACTIVE_PRESET = "TardeDourada" -- "TardeDourada" | "NoiteDeEstadio"

-- ============================================================
-- PRESETS
-- ============================================================
local PRESETS = {
	-- Jogo de fim de tarde: sol baixo e quente, sombras longas e definidas,
	-- céu frio fazendo contraste. É o visual clássico de transmissão de
	-- futebol — e o que mais valoriza o gramado, porque o verde estoura
	-- sob luz quente.
	TardeDourada = {
		Lighting = {
			-- Hora do dia (0–24). 15.5 = meio da tarde: o sol já está
			-- inclinado o bastante pra jogar sombra comprida no gramado,
			-- mas ainda alto o suficiente pra não cegar a câmera rasa.
			ClockTime = 15.5,
			-- Latitude geográfica (graus) — decide a INCLINAÇÃO do arco do
			-- sol. Perto de 0 o sol passa mais a pino; valores altos
			-- deixam ele mais de lado. 18 dá uma sombra diagonal bonita
			-- sem achatar o campo.
			GeographicLatitude = 18,
			-- Intensidade da luz do sol. Sobe o contraste entre a parte
			-- iluminada e a sombra.
			Brightness = 1.85, -- ⚠️ v35: era 2.1 ("tá muito claro")
			-- Exposição da "câmera" (como em fotografia). Um toque pra
			-- cima deixa o gramado vivo sem lavar o branco das linhas.
			ExposureCompensation = -0.06, -- ⚠️ v35: era +0.05
			-- Borrão da borda da sombra: 0 = recorte duro, 1 = bem macia.
			-- Estádio a céu aberto tem sombra bem definida — 0.2 mantém a
			-- silhueta do jogador legível no chão.
			ShadowSoftness = 0.2,
			GlobalShadows = true,
			-- Quanto da luz AMBIENTE vem do céu (0–1). Em 1, o azul do céu
			-- ilumina de verdade o que está na sombra, em vez de a sombra
			-- virar um borrão cinza morto.
			EnvironmentDiffuseScale = 1,
			-- Quanto do REFLEXO vem do ambiente (0–1). É o que faz
			-- superfície lisa (placar, traves, uniforme) refletir o céu.
			EnvironmentSpecularScale = 1,
			-- Cor da luz ambiente ONDE O CÉU É VISÍVEL (campo aberto).
			-- Azulado de propósito: sol quente + sombra fria é o que dá a
			-- sensação de luz natural, e não de lâmpada.
			OutdoorAmbient = Color3.fromRGB(150, 155, 165), -- ⚠️ v29: era bem mais azul e tingia o campo inteiro
			-- Cor da luz ambiente GERAL (inclusive embaixo de cobertura).
			-- Mais escura que a de fora, senão não existe sombra nenhuma.
			Ambient = Color3.fromRGB(92, 94, 100), -- ⚠️ v29
			-- Cor refletida pelas faces VIRADAS PRO SOL — o dourado.
			ColorShift_Top = Color3.fromRGB(255, 244, 222),
			-- Cor refletida pelas faces viradas PRO LADO OPOSTO — o azul
			-- que o céu devolve.
			ColorShift_Bottom = Color3.fromRGB(170, 180, 195),
		},

		-- Atmosfera: é ela que dá PROFUNDIDADE. Sem atmosfera, a
		-- arquibancada do outro lado do campo parece colada na câmera.
		Atmosphere = {
			-- Quantidade de partícula no ar (0–1). 0.3 é o "ar limpo de
			-- dia aberto" que a doc da Roblox recomenda pra exterior.
			Density = 0.12, -- ⚠️ v29: era 0.3
			-- Altura em que a atmosfera começa a aparecer. Segurar em 0.25
			-- evita névoa no nível do gramado (que deixaria o jogo leitoso
			-- bem onde a gente precisa enxergar).
			Offset = 0.1, -- ⚠️ v29
			-- Cor do ar.
			Color = Color3.fromRGB(220, 220, 214),
			-- Cor pra onde o ar "decai" ao longe, misturando com o céu.
			Decay = Color3.fromRGB(150, 150, 142), -- ⚠️ v29: era azul e pintava a cena toda
			-- Espalhamento da luz do sol no ar (aquele brilho em volta do
			-- sol). Baixo de propósito: em excesso vira neblina branca.
			Glare = 0.15, -- ⚠️ v29
			-- Névoa. Mantém o fundo do estádio levemente lavado, o que
			-- separa ele do gramado e cria camada de profundidade.
			Haze = 0.15, -- ⚠️ v29: era 1.2 — a CAUSA do véu azul
		},

		Bloom = {
			-- Brilho estourado nas áreas MAIS claras.
			Intensity = 0.35, -- ⚠️ v26: era 0.6 — menos brilho estourado
			-- Tamanho do borrão do brilho.
			Size = 24,
			-- A partir de qual luminosidade começa a brilhar. Alto de
			-- propósito (1.6): só o que é REALMENTE claro (reflexo do sol,
			-- linha branca sob luz direta) brilha. Threshold baixo faz o
			-- jogo inteiro parecer sujo de vaselina.
			Threshold = 2.0, -- ⚠️ v26: era 1.6 — só o MUITO claro brilha
		},

		SunRays = {
			-- Raios de sol saindo do disco solar. MUITO baixo de propósito:
			-- num jogo em que a câmera vive apontando pro horizonte, raio
			-- forte atrapalha ver a bola.
			Intensity = 0.05,
			Spread = 0.4,
		},

		ColorCorrection = {
			Brightness = 0,
			-- Contraste: separa sombra de luz. É o ajuste que mais faz
			-- "parecer shader" com menos custo.
			Contrast = 0.08,
			-- Saturação: deixa o gramado verde de verdade e o uniforme
			-- vivo, sem chegar no desenho animado.
			Saturation = 0.18, -- ⚠️ v29: puxa o verde do gramado
			-- Tom levemente quente por cima de tudo, pra amarrar a cena.
			TintColor = Color3.fromRGB(255, 252, 246),
		},

		-- Profundidade de campo: SÓ no fundo, e fraca. Desfoca a
		-- arquibancada distante e mantém 100% do campo de jogo nítido.
		-- ⚠️ v27 — PEDIDO: "coloque um PEQUENO blur pra disfarçar melhor".
		-- Desfoque leve da tela inteira. 2 é quase imperceptível parado, mas
		-- é o suficiente pra suavizar o serrilhado das linhas do campo quando
		-- a câmera se move. Acima de ~6 começa a atrapalhar ver a bola.
		Blur = { Size = 4 }, -- ⚠️ v28: era 2 — subido pra teste

		DepthOfField = {
			FarIntensity = 0.15,
			NearIntensity = 0,     -- zero: desfocar o que está perto da câmera atrapalharia o jogo
			FocusDistance = 120,
			InFocusRadius = 260,   -- tudo dentro desse raio fica nítido — o campo inteiro cabe aqui
		},
	},

	-- Jogo à noite sob refletor: sem sol, contraste alto, ar mais denso
	-- pra os holofotes "aparecerem" no ar. Aqui a luz do céu praticamente
	-- não existe, então o que ilumina o campo são as luzes que você tiver
	-- posto na cena (se não tiver nenhuma, vai ficar escuro mesmo — é o
	-- comportamento certo, não um bug).
	NoiteDeEstadio = {
		Lighting = {
			ClockTime = 21,
			GeographicLatitude = 18,
			Brightness = 1.1,
			ExposureCompensation = 0.35,
			ShadowSoftness = 0.35,
			GlobalShadows = true,
			EnvironmentDiffuseScale = 0.55,
			EnvironmentSpecularScale = 1,
			OutdoorAmbient = Color3.fromRGB(58, 66, 88),
			Ambient = Color3.fromRGB(34, 38, 52),
			ColorShift_Top = Color3.fromRGB(196, 214, 255),
			ColorShift_Bottom = Color3.fromRGB(58, 70, 96),
		},
		Atmosphere = {
			Density = 0.38,
			Offset = 0.2,
			Color = Color3.fromRGB(150, 162, 186),
			Decay = Color3.fromRGB(40, 48, 70),
			Glare = 0.15,
			Haze = 1.8,
		},
		Bloom = {
			-- Mais forte que de dia: é o brilho dos refletores que vende a
			-- noite.
			Intensity = 1.1,
			Size = 30,
			Threshold = 1.1,
		},
		SunRays = {
			Intensity = 0, -- não existe sol
			Spread = 0.2,
		},
		ColorCorrection = {
			Brightness = 0.02,
			Contrast = 0.18,
			Saturation = 0.05,
			TintColor = Color3.fromRGB(240, 246, 255),
		},
		Blur = { Size = 4 }, -- ⚠️ v28: era 2 — subido pra teste

		DepthOfField = {
			FarIntensity = 0.2,
			NearIntensity = 0,
			FocusDistance = 110,
			InFocusRadius = 240,
		},
	},
}

-- ============================================================
-- APLICAÇÃO
-- ============================================================

-- Reaproveita o objeto que já existir em Lighting em vez de criar um
-- segundo (dois Bloom/duas Atmosphere na cena somam efeito e ninguém
-- entende por que ficou estourado). Só cria se não existir.
local function ensure(className, name)
	local existing = Lighting:FindFirstChildOfClass(className)
	if existing then return existing end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = Lighting
	return created
end

-- Escreve propriedade a propriedade dentro de pcall: se alguma versão do
-- Roblox não tiver uma delas, o resto do preset continua sendo aplicado
-- em vez de o script inteiro morrer na primeira linha.
local function applyProperties(instance, properties, label)
	for propertyName, value in pairs(properties) do
		local ok, err = pcall(function()
			instance[propertyName] = value
		end)
		if not ok then
			warn(("🎨 [Iluminação] não consegui aplicar %s.%s: %s"):format(label, propertyName, tostring(err)))
		end
	end
end

local function applyPreset(presetName)
	local preset = PRESETS[presetName]
	if not preset then
		warn(("🎨 [Iluminação] preset '%s' não existe. Opções: TardeDourada, NoiteDeEstadio."):format(tostring(presetName)))
		return
	end

	applyProperties(Lighting, preset.Lighting, "Lighting")
	applyProperties(ensure("Atmosphere", "Atmosphere"), preset.Atmosphere, "Atmosphere")
	applyProperties(ensure("BloomEffect", "Bloom"), preset.Bloom, "Bloom")
	applyProperties(ensure("SunRaysEffect", "SunRays"), preset.SunRays, "SunRays")
	applyProperties(ensure("ColorCorrectionEffect", "ColorCorrection"), preset.ColorCorrection, "ColorCorrection")
	applyProperties(ensure("DepthOfFieldEffect", "DepthOfField"), preset.DepthOfField, "DepthOfField")
	applyProperties(ensure("BlurEffect", "Blur"), preset.Blur, "Blur")

	print(("🎨 [Iluminação] preset '%s' aplicado."):format(presetName))

	-- Technology é somente-leitura em runtime — não dá pra consertar daqui,
	-- só avisar. Sem Future, boa parte do preset (sombra de qualidade, luz
	-- do céu, reflexo do ambiente) simplesmente não é renderizada.
	-- ⚠️ v110 FIX: nem LER o Technology o script pode ("cannot read 'Technology'
	-- (lacking capability)") — o erro parava o resto do script depois do preset.
	local okTec, tecnologia = pcall(function() return Lighting.Technology end)
	if okTec and tecnologia ~= Enum.Technology.Future then
		warn(("🎨 [Iluminação] ⚠️ Lighting.Technology está em '%s'. Pra iluminação ficar como foi desenhada, abra o Studio, selecione Lighting no Explorer e mude Technology pra Future. Script nenhum consegue mudar isso em runtime."):format(tecnologia.Name))
	end
end

applyPreset(ACTIVE_PRESET)

-- ⚠️ Deixado pronto pra quando você quiser trocar de clima em pleno jogo
-- (ex: segundo tempo à noite). Nada chama isso ainda.
_G.SetStadiumLighting = applyPreset

--[[
	O QUE EU NÃO MEXO, DE PROPÓSITO
	(pedido: "não ajuste o que você não sabe")

	• Lighting.Technology — somente-leitura em runtime. Só no Studio.
	• FogColor / FogStart / FogEnd — é o sistema de névoa ANTIGO. Quando
	  existe um Atmosphere na cena, ele é quem manda, e mexer nos dois ao
	  mesmo tempo dá resultado imprevisível. Como aqui tem Atmosphere,
	  deixo o Fog quieto.
	• Lighting.TimeOfDay — é a MESMA coisa que ClockTime, só que escrita
	  como texto ("15:30:00"). Setar as duas é pedir pra uma sobrescrever a
	  outra. Uso só ClockTime.
	• SkyBox — não toco porque é arte, não configuração: o céu que você
	  escolher precisa combinar com essas cores, e trocar por conta própria
	  ia brigar com o que você montou. Se quiser, me diz o clima e eu ajusto
	  as cores do preset pro céu que você usar.
	• (BlurEffect saiu desta lista na v27: agora é usado, mas BEM baixo —
	  ver Blur nos presets.)
]]
