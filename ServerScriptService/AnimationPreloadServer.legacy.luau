--[[
	AnimationPreloadServer (Script)
	LOCAL: ServerScriptService (place Game)

	⚠️ v67 — A METADE QUE FALTAVA DO PRÉ-CARREGAMENTO.

	O AnimationPreloader.local.luau (cliente) já baixa as animações pra quem
	ASSISTE. Só que quem cria e toca as AnimationTracks é o SERVIDOR
	(playAnimation em BallController roda lá), e ele também precisa do asset:

	  - `track.Length` fica 0 até o asset chegar, e é dele que saem o ajuste
	    de velocidade e o congelamento no último frame;
	  - `track.Looped` é SOBRESCRITO pelo valor do editor quando o asset
	    carrega, então "Looped = false" setado antes da carga não vale nada.

	É isso que fazia a PRIMEIRA execução de cada animação sair errada — a
	PrepareKick voltando a dar loop, e o chute "perdendo" pra corrida porque
	ainda não havia pose nenhuma pra mostrar. Com o asset já em memória antes
	do primeiro lance, as duas coisas passam a valer de primeira.

	Varre Config.ANIMATIONS de propósito, em vez de listar os ids na mão:
	animação nova adicionada lá entra no preload sozinha.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

local idsVistos = {}
local function coletar(valor)
	if typeof(valor) == "string" then
		local id = Config.NormalizeAnimationId(valor)
		if id ~= "" then idsVistos[id] = true end
	elseif typeof(valor) == "table" then
		for _, sub in pairs(valor) do
			coletar(sub)
		end
	end
end

coletar(Config.ANIMATIONS)
coletar(Config.CUTSCENE_WALK_ANIMATION)

local paraBaixar = {}
for id in pairs(idsVistos) do
	local animation = Instance.new("Animation")
	animation.AnimationId = id
	table.insert(paraBaixar, animation)
end

task.spawn(function()
	local inicio = os.clock()
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(paraBaixar)
	end)
	if ok then
		print(string.format("🎞️ [Preload/servidor] %d animações prontas em %.2fs.", #paraBaixar, os.clock() - inicio))
	else
		warn("🎞️ [Preload/servidor] falhou: " .. tostring(err))
	end
end)
