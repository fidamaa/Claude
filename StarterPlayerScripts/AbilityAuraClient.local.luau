--[[
	AbilityAuraClient (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	⚠️ v45 — Anima as auras de habilidade criadas pelo servidor (ver
	ReplicatedStorage/AbilityAura.luau, que tem o comentário completo do
	porquê desse sistema existir).

	O servidor só CRIA o Highlight e escreve os atributos AuraPulse/
	AuraSpeed/AuraMin/AuraMax. Quem faz o contorno pulsar é este script,
	num Heartbeat só, no cliente — animar no servidor custaria uma
	replicação de propriedade por frame por jogador, e o pulso sairia
	tremido junto com a rede.

	Cada ritmo é uma leitura diferente:
	  Strobe  — liga/desliga duro e rápido: "piscando, fora de fase".
	  Breathe — sobe e desce suave: presença contínua, não rouba atenção.
	  Blink   — uma piscada seca que se apaga sozinha.
	  None    — contorno parado (congelado NÃO treme, de propósito).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AbilityAura = require(ReplicatedStorage:WaitForChild("AbilityAura"))

local ATRIBUTO = AbilityAura.PULSE_ATTRIBUTE
local TAU = math.pi * 2

-- Devolve OutlineTransparency pra este instante.
local function transparenciaDe(ritmo, tempo, velocidade, minimo, maximo)
	if ritmo == "Strobe" then
		-- Onda quadrada: sem meio-termo, é o que dá a leitura de "piscando".
		return (math.sin(tempo * velocidade * TAU) >= 0) and minimo or maximo
	elseif ritmo == "Breathe" then
		-- Senoide suave entre min e max.
		local t = 0.5 + 0.5 * math.sin(tempo * velocidade * TAU)
		return minimo + (maximo - minimo) * t
	elseif ritmo == "Blink" then
		-- Uma piscada só: acende no mínimo e apaga até o máximo, e fica lá.
		local t = math.clamp(tempo * velocidade / TAU, 0, 1)
		return minimo + (maximo - minimo) * t
	end
	return minimo -- "None": contorno duro e parado
end

-- Varre os personagens em campo em vez de guardar uma lista: personagens
-- entram e saem o tempo todo (respawn, cutscene, replay), e uma lista
-- guardada ficaria com referência pendurada em Model destruído. São poucas
-- dezenas de personagens no pior caso, e a varredura olha só os filhos
-- diretos de cada um — não desce a árvore inteira.
local function aurasAtivas()
	local achadas = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		if character then
			for _, filho in ipairs(character:GetChildren()) do
				if filho:IsA("Highlight") and filho:GetAttribute(ATRIBUTO) then
					table.insert(achadas, filho)
				end
			end
		end
	end
	return achadas
end

RunService.Heartbeat:Connect(function()
	local agora = workspace:GetServerTimeNow()
	for _, aura in ipairs(aurasAtivas()) do
		if aura.Enabled then
			local ritmo = aura:GetAttribute(ATRIBUTO)
			local inicio = aura:GetAttribute("AuraStart") or agora
			local velocidade = aura:GetAttribute("AuraSpeed") or 0
			local minimo = aura:GetAttribute("AuraMin") or 0
			local maximo = aura:GetAttribute("AuraMax") or 0
			aura.OutlineTransparency =
				transparenciaDe(ritmo, agora - inicio, velocidade, minimo, maximo)
		end
	end
end)

print("✅ AbilityAuraClient carregado.")
