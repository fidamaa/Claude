--[[
	NPCDialogueSetup (Script)
	LOCAL: ServerScriptService (place Lobby)

	Prepara qualquer NPC do jogo pra conversar: dá a TAG "Dialogue"
	(CollectionService) a um Model no Workspace e este script cuida do
	resto — cria o ProximityPrompt automaticamente se ainda não existir
	um, com "Conversar" como texto padrão.

	COMO CRIAR UM NPC NOVO NO STUDIO:
	1. Monte o Model normalmente (com Humanoid + HumanoidRootPart, ou
	   qualquer BasePart como PrimaryPart).
	2. Na aba "Tags" do Studio (ou via script), adicione a tag "Dialogue"
	   nesse Model.
	3. (Opcional) Defina o atributo DialogueId (string) nesse Model
	   apontando pra uma árvore em DialogueData.lua — se não definir, o
	   sistema usa o Model.Name como id (ex.: Model chamado "ShopKeeper"
	   já casa com DialogueData.ShopKeeper sem precisar do atributo).
	4. Pronto — não precisa criar o ProximityPrompt na mão, nem mexer em
	   nenhum outro script.
]]

local CollectionService = game:GetService("CollectionService")

local DIALOGUE_TAG = "Dialogue"
local PROMPT_NAME = "TalkPrompt"
local DEFAULT_ACTION_TEXT = "Conversar"
local DEFAULT_MAX_DISTANCE = 10
local DEFAULT_HOLD_DURATION = 0

local function findAnchorPart(npcModel)
	return npcModel.PrimaryPart
		or npcModel:FindFirstChild("HumanoidRootPart")
		or npcModel:FindFirstChildWhichIsA("BasePart", true)
end

local function setupNpc(npcModel)
	if not npcModel:IsA("Model") then
		warn(string.format("NPCDialogueSetup: '%s' tem a tag Dialogue mas não é um Model, ignorando.", npcModel:GetFullName()))
		return
	end

	local anchorPart = findAnchorPart(npcModel)
	if not anchorPart then
		warn(string.format("NPCDialogueSetup: '%s' não tem nenhuma BasePart pra pendurar o ProximityPrompt.", npcModel:GetFullName()))
		return
	end

	local prompt = anchorPart:FindFirstChild(PROMPT_NAME)
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT_NAME
		prompt.ActionText = DEFAULT_ACTION_TEXT
		prompt.ObjectText = npcModel:GetAttribute("NomeNpc") or npcModel.Name
		prompt.HoldDuration = DEFAULT_HOLD_DURATION
		prompt.MaxActivationDistance = DEFAULT_MAX_DISTANCE
		prompt.RequiresLineOfSight = false
		prompt.Parent = anchorPart
	end
	prompt.ObjectText = npcModel:GetAttribute("NomeNpc") or npcModel.Name -- ⚠️ v118: nome certo mesmo em prompt que já existia
end

-- ⚠️ v115 — PEDIDO: "o Bentes/Pepe Nep sentado no banco da praça vira o NPC de
-- ESTATÍSTICAS". O boneco já existe no mapa (Bpepnep) mas sem tag: aqui ele
-- ganha a tag, o DialogueId e o nome que aparece no prompt, por script — assim
-- não depende de mexer no Studio.
local estatistico = workspace:FindFirstChild("Bpepnep", true)
if estatistico and estatistico:IsA("Model") then
	estatistico:SetAttribute("DialogueId", "Estatisticas")
	estatistico:SetAttribute("NomeNpc", "Bentes")
	CollectionService:AddTag(estatistico, DIALOGUE_TAG)
end

-- ⚠️ v118 — PEDIDO: "muda os nomes: Zelador põe Tiluca, Lojista põe o Lavinho, o do
-- Roll é o Pedro, o Bentes está certo e o Kogamalotigo é o Fidama". O nome que
-- aparece no prompt "Conversar" (o diálogo usa o Speaker do DialogueData).
local NOME_POR_DIALOGO = {
	QuestGiver = "Tiluca", ShopKeeper = "Lavinho", RollMaster = "Pedro", Kogamalotigo = "Fidama", Estatisticas = "Bentes",
}
for _, m in ipairs(CollectionService:GetTagged(DIALOGUE_TAG)) do
	local nome = NOME_POR_DIALOGO[m:GetAttribute("DialogueId") or m.Name]
	if nome then m:SetAttribute("NomeNpc", nome) end
end

for _, npcModel in ipairs(CollectionService:GetTagged(DIALOGUE_TAG)) do
	setupNpc(npcModel)
end

CollectionService:GetInstanceAddedSignal(DIALOGUE_TAG):Connect(setupNpc)

print(string.format("✅ NPCDialogueSetup carregado (%d NPC(s) com a tag '%s')", #CollectionService:GetTagged(DIALOGUE_TAG), DIALOGUE_TAG))
