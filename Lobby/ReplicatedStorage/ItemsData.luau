--[[
	ItemsData (ModuleScript)
	LOCAL: ReplicatedStorage (place Lobby)

	Catálogo de "Itens" — diferente de Pulso/Instinto (que vêm do Roll,
	ver RollClient.lua): itens são coisas simples, a maioria ganha em
	missões (ver DialogueData.QuestGiver), não no Roll.

	Duas categorias:
	- Buff: consumível simples, efeito pequeno e direto (o campo Effect
	  é só metadado por enquanto, igual o Effect do Roll — nada aplica
	  ele de verdade ainda, é referência pro sistema de missões/inventário
	  que ainda vai ser construído).
	- Quest: item "chave", sem efeito nenhum — só existe pra ser pedido/
	  entregue numa missão (ex.: "traga 3 Emblemas Rachados pro NPC de
	  missões"). RequiredFor é opcional, só documentação de qual missão
	  usa aquele item (preencher quando as missões existirem de verdade).

	NADA aqui está conectado a inventário ainda — é só o catálogo, pra
	quando o sistema de missões (próximo NPC) for construído em cima
	dele.
]]

local ItemsData = {}

ItemsData.Buffs = {
	{
		Name = "Bebida Energética",
		Description = "Recupera uma parte da stamina na hora.",
		Rarity = "Common",
		Effect = { Type = "InstantRestore", Stat = "Stamina", Amount = 30 },
	},
	{
		Name = "Barra de Cereal",
		Description = "Um lanchinho rápido antes da partida — um pouco de XP extra.",
		Rarity = "Common",
		Effect = { Type = "InstantXP", Amount = 25 },
	},
	{
		Name = "Bandagem",
		Description = "Cuida de uma pequena lesão — remove fadiga acumulada.",
		Rarity = "Common",
		Effect = { Type = "RemoveFatigue" },
	},
	{
		Name = "Poção de Foco",
		Description = "Chute mais preciso durante a próxima partida.",
		Rarity = "Rare",
		Effect = { Type = "NextMatchBuff", Stat = "Kick", Amount = 3 },
	},
	{
		Name = "Poção de Fôlego",
		Description = "Stamina extra durante a próxima partida inteira.",
		Rarity = "Rare",
		Effect = { Type = "NextMatchBuff", Stat = "Stamina", Amount = 3 },
	},
	{
		Name = "Elixir Completo",
		Description = "Todos os atributos um pouco melhores na próxima partida.",
		Rarity = "Epic",
		Effect = { Type = "NextMatchBuffMulti", Stats = { Physical = 1, DribbleSkill = 1, Speed = 1, Kick = 1, Energy = 1, Technique = 1, Stamina = 1 } }, -- ⚠️ NOVO: Energy incluído · Technique (7º atributo)
	},
}

ItemsData.QuestItems = {
	{ Name = "Emblema Rachado", Description = "Um pedaço de emblema de time antigo. Alguém deve querer isso.", RequiredFor = nil },
	{ Name = "Bússola Antiga", Description = "Aponta sempre pro campo mais próximo.", RequiredFor = nil },
	{ Name = "Carta Selada", Description = "Um convite pra algo... ainda não se sabe o quê.", RequiredFor = nil },
	{ Name = "Distintivo do Torneio", Description = "Prova de participação num torneio esquecido.", RequiredFor = nil },
}

return ItemsData
