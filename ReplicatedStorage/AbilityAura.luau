--[[
	AbilityAura (ModuleScript)
	LOCAL: ReplicatedStorage (place Game)

	⚠️ v45 — PEDIDO: "eu não quero esses highlights padrão de ForceField, e
	de mudar a cor do personagem. Eu quero que você crie um highlight
	próprio, de um jeito diferente, que mostre que ele está utilizando tais
	habilidades. Sei lá, piscar alguma coisa."

	O QUE HAVIA: quatro lugares diferentes criavam Highlight na mão, todos
	com FillTransparency entre 0.35 e 0.55 — ou seja, todos LAVAVAM o
	personagem inteiro numa cor sólida. Eram indistinguíveis entre si (só
	mudava a cor) e apagavam o uniforme do jogador:
	  - iframe de drible/mergulho (BallController.setIframeGlow)
	  - congelamento (BallController.addFreezeVisual)
	  - buff de Pulso ativo (PulseController.setBuffGlow)
	  - flash de QTE (AbilityHUD, no cliente)

	O QUE É AGORA (estado final, depois do ajuste da v47): cada estado tem
	um visual PRÓPRIO, e a regra de quando pintar o corpo é por estado, não
	global. Estado CONTÍNUO não pinta o corpo (só contorno, pra não apagar o
	uniforme); FLASH curto e "modo fantasma" podem pintar, porque aí o
	preenchimento é justamente a informação:

	  Iframe    — v47: preenchimento BRANCO translúcido (0.7), sem pulso.
	              "Modo fantasma": diz que não dá pra acertar ele.
	  Freeze    — contorno duro e parado, sem pulso. O contraste é de
	              propósito: atordoado balança, congelado trava.
	  Buff      — contorno respirando devagar, na cor da raridade.
	              Presença contínua, sem roubar atenção e sem tapar o
	              uniforme (é o estado que mais dura).
	  QTE       — v47: flash preenchido curto (0.18s) na cor do resultado.

	SEMPRE VOLTA AO NORMAL (pedido: "acabou o negócio, sumiu e voltou ao
	normal — acabou o drible, sumiu e voltou o highlight padrão"). Cada aura
	é uma Instance SEPARADA do TeamHighlight: Clear() destrói a aura e o
	highlight de time reaparece intacto embaixo, sem precisar restaurar
	propriedade nenhuma. Era exatamente o salvar-e-restaurar do sistema
	antigo que deixava o personagem preso na cor errada quando dois efeitos
	se sobrepunham.

	COMO A ANIMAÇÃO RODA: o servidor só CRIA o Highlight e escreve os
	atributos (AuraPulse/AuraSpeed/AuraMin/AuraMax). Quem anima é
	AbilityAuraClient.local.luau, num Heartbeat só, no CLIENTE. Animar no
	servidor significaria replicar uma mudança de propriedade por frame por
	jogador — caro à toa, e com a rede engasgando o pulso sairia tremido.
	Assim o pulso é suave de graça, e o servidor continua sendo o dono de
	QUANDO a aura existe.
]]

local AbilityAura = {}

-- Nome do atributo que marca um Highlight como "aura animada" — o cliente
-- varre por ele (ver AbilityAuraClient).
AbilityAura.PULSE_ATTRIBUTE = "AuraPulse"

-- Min/Max são de OutlineTransparency: 0 = contorno cheio, 1 = invisível.
AbilityAura.Presets = {
	-- ⚠️ v47 — PEDIDO: "eu curti o do iframe, mas não precisa deixar assim.
	-- Pode colocar o do iframe transparente, normal, igual estava antes: fill
	-- transparency 0.7 e branco. Que aí meio que diz que você não pode
	-- acertar ele, como se ele estivesse no MODO FANTASMA."
	--
	-- Volta a ser preenchimento (não contorno): é o branco translúcido por
	-- cima do corpo que passa a ideia de "atravessável". Sem pulso — fantasma
	-- não pisca, ele simplesmente está meio lá. AlwaysOnTop pra ficar por
	-- cima do contorno de time sem brigar com ele.
	--
	-- Continua sendo uma Instance SEPARADA do TeamHighlight, que é o que
	-- garante o "acabou o drible, sumiu e voltou o highlight padrão": basta
	-- destruir a aura e o highlight de time reaparece intacto embaixo, sem
	-- precisar restaurar propriedade nenhuma.
	Iframe = {
		Color = Color3.fromRGB(255, 255, 255),
		Fill = 0.7,
		FillColor = Color3.fromRGB(255, 255, 255),
		Pulse = "None",
		Speed = 0,
		Min = 0,
		Max = 0,
	},
	-- Congelado (Fúria Glacial, Hora do Céu, Costura de Sombra).
	-- Sem pulso de propósito — ver o comentário do cabeçalho.
	Freeze = {
		Color = Color3.fromRGB(190, 240, 255),
		Pulse = "None",
		Speed = 0,
		Min = 0,
		Max = 0,
	},
	-- Buff de Pulso ativo. A cor vem da raridade, então é passada na hora.
	Buff = {
		Color = Color3.fromRGB(255, 255, 255),
		Pulse = "Breathe",
		Speed = 1.6,
		Min = 0.1,
		Max = 0.55,
	},
	-- ⚠️ v67 — FLOW (antigo "Instinct Mode"). PEDIDO: "quando o cara ativar o
	-- modo, ele vai ficar com um highlight DIFERENTE."
	--
	-- Precisa ser inconfundível: é o estado mais raro do jogo (um por vez em
	-- campo inteiro) e o adversário tem que reconhecer de longe. Por isso é o
	-- único que combina as duas coisas — preenchimento leve E contorno
	-- pulsando rápido. Azul de Blue Lock.
	Flow = {
		Color = Color3.fromRGB(70, 160, 255),
		Fill = 0.82,
		FillColor = Color3.fromRGB(90, 175, 255),
		Pulse = "Breathe",
		Speed = 2.6,
		Min = 0,
		Max = 0.4,
	},

	-- ⚠️ v47 — PEDIDO: "durante o acerto do QTE, o que eu digo de piscar,
	-- pode usar o force field pra piscar, pode colocar o force field normal
	-- pros acertos — mas isso SÓ VALE PRO QTE."
	--
	-- Ou seja: aqui o preenchimento sólido (o visual "force field") está
	-- liberado, porque é um flash de 0.18s, não um estado contínuo. A cor
	-- vem do resultado (dourado = Perfect, verde = acertou, vermelho =
	-- errou), passada pelo AbilityHUD — é informação, não enfeite.
	QTE = {
		Color = Color3.fromRGB(255, 240, 150),
		Fill = 0.45,
		Pulse = "None",
		Speed = 0,
		Min = 0,
		Max = 0,
	},
}

-- Liga (ou atualiza) uma aura no personagem. `nome` é o nome da Instance,
-- então auras diferentes coexistem sem brigar — um jogador pode estar com
-- buff E invencível ao mesmo tempo.
-- `corOverride` só é usado pelo Buff, que pinta pela raridade.
function AbilityAura.Apply(character, nome, presetName, corOverride)
	if not character then return nil end
	local preset = AbilityAura.Presets[presetName]
	if not preset then return nil end

	local aura = character:FindFirstChild(nome)
	if not aura or not aura:IsA("Highlight") then
		aura = Instance.new("Highlight")
		aura.Name = nome
		aura.Adornee = character
		aura.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		aura.Parent = character
	end

	-- ⚠️ v47: por padrão o corpo NÃO é pintado (FillTransparency 1, só
	-- contorno). Dois presets são exceção explícita e pedida — Iframe (modo
	-- fantasma) e QTE (flash curto) — e declaram `Fill` pra isso.
	local cor = corOverride or preset.Color
	aura.FillTransparency = preset.Fill or 1
	aura.FillColor = preset.FillColor or cor
	aura.OutlineColor = cor
	aura.OutlineTransparency = preset.Min

	aura:SetAttribute(AbilityAura.PULSE_ATTRIBUTE, preset.Pulse)
	aura:SetAttribute("AuraSpeed", preset.Speed)
	aura:SetAttribute("AuraMin", preset.Min)
	aura:SetAttribute("AuraMax", preset.Max)
	aura:SetAttribute("AuraStart", workspace:GetServerTimeNow())

	aura.Enabled = true
	return aura
end

function AbilityAura.Clear(character, nome)
	if not character then return end
	local aura = character:FindFirstChild(nome)
	if aura and aura:IsA("Highlight") then
		aura:Destroy()
	end
end

return AbilityAura
