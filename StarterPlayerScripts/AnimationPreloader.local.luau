--[[
	AnimationPreloader (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	⚠️ v66 — PEDIDO: "o único problema é sempre a primeira vez que toco a
	animação acaba saindo com delay, talvez elas precisam ser pré-carregadas
	pra sempre ir direitinho."

	POR QUE ACONTECE: playAnimation (BallController) roda no SERVIDOR — ele
	só decide QUANDO tocar. Quem de fato BAIXA e decodifica o KeyframeSequence
	é cada CLIENTE, na primeira vez que aquele AnimationId aparece pra ele.
	Sem isso feito antes, o primeiro Play() de cada animação, pra cada
	jogador, para um instante esperando o asset chegar — exatamente o
	"delayzinho na primeira vez" descrito.

	O QUE ESTE SCRIPT FAZ: junta TODO AnimationId usado no jogo (varrendo
	Config.ANIMATIONS de propósito, em vez de listar os ids na mão — assim
	uma animação nova adicionada ali entra no preload sozinha, sem precisar
	lembrar de atualizar dois lugares) e manda pro ContentProvider baixar e
	decodificar tudo de uma vez, logo no carregamento do jogo — bem antes de
	qualquer chute, carrinho, drible ou mergulho acontecer de verdade.

	Roda uma vez por CLIENTE (cada jogador baixa a própria cópia); não runa
	no servidor porque o servidor não renderiza nada, só replica.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))

-- Varre Config.ANIMATIONS (e Config.CUTSCENE_WALK_ANIMATION) recursivamente:
-- aceita string única, tabela por direção/nome (Dribble.Left, GKDive.Up...)
-- e lista (GoalCelebrationCrowd). Assim uma chave nova, de qualquer formato,
-- é pega automaticamente — não precisa vir editar este arquivo de novo.
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

print(string.format("🎞️ [Preload] baixando %d animação(ões) antes do jogo começar...", #paraBaixar))

local inicio = os.clock()
ContentProvider:PreloadAsync(paraBaixar)
print(string.format("🎞️ [Preload] concluído em %.2fs — nenhuma animação deve mais ter delay na primeira vez.", os.clock() - inicio))
