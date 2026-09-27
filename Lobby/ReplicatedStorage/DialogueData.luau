--[[
	DialogueData (ModuleScript)
	LOCAL: ReplicatedStorage (place Lobby)

	Todas as árvores de diálogo do jogo, num lugar só. Cada NPC no
	Workspace tem a tag "Dialogue" (CollectionService) e um atributo
	DialogueId apontando pra uma chave aqui embaixo (se não tiver o
	atributo, usa o Model.Name como chave — ver NPCDialogueSetup.lua e
	DialogueClient.lua).

	FORMATO DE UMA ÁRVORE:
	{
		Start = "idNoInicial",
		Nodes = {
			[idDoNo] = {
				Speaker = "Nome exibido",       -- opcional, senão usa o Name do NPC
				Text = "Fala mostrada na tela",

				-- Uma das duas formas de avançar:
				Next = "idDoProximoNo",         -- linear: 1 botão "Avançar" (nil = fim do diálogo)
				Choices = {                     -- OU escolhas: vários botões
					{ Text = "Resposta 1", Next = "outroId" },
					{ Text = "Resposta 2", Next = nil },      -- nil = encerra o diálogo
				},

				-- Opcional: roda uma ação conhecida do DialogueClient.lua
				-- quando esse nó é exibido (ver ACTION_HANDLERS lá). Hoje só
				-- existe "OpenShop" (abre a tela da Loja).
				Action = "OpenShop",

				-- Opcional: espaço reservado pra tocar uma animação diferente
				-- nesse nó (no NPC ou no jogador) quando vocês tiverem os
				-- AnimationIds prontos — o DialogueClient já lê estes campos,
				-- só não faz nada se estiverem vazios.
				NpcAnimationId = nil,
				PlayerAnimationId = nil,
			},
		},
	}
]]

local DialogueData = {}

-- Exemplo funcional: o Lojista, que abre a tela da Loja construída em
-- ShopClient.lua. Sirva de modelo pra criar os outros NPCs.
DialogueData.ShopKeeper = {
	Start = "greeting",
	Nodes = {
		greeting = {
			Speaker = "Lojista",
			Text = "E aí! Quer destravar um personagem novo ou reiniciar algum que já tem?",
			Choices = {
				{ Text = "Me mostra a loja", Next = "openShop" },
				{ Text = "Só passando, valeu", Next = "farewell" },
			},
		},
		openShop = {
			Speaker = "Lojista",
			Text = "Aqui está — pode fechar quando terminar.",
			Action = "OpenShop",
			Next = nil,
		},
		farewell = {
			Speaker = "Lojista",
			Text = "Fechou! Qualquer coisa é só voltar aqui.",
			Next = nil,
		},
	},
}

-- NPC que abre a tela de Roll (RollClient.lua) — pra usar, crie um Model
-- chamado "RollMaster" (ou dê o atributo DialogueId = "RollMaster" a
-- qualquer Model) e adicione a tag "Dialogue" nele, igual o Lojista.
DialogueData.RollMaster = {
	Start = "greeting",
	Nodes = {
		greeting = {
			Speaker = "Recrutador",
			Text = "Quer arriscar uma Hissatsu ou uma Arma nova?",
			Choices = {
				{ Text = "Bora ver", Next = "openRoll" },
				{ Text = "Agora não", Next = "farewell" },
			},
		},
		openRoll = {
			Speaker = "Recrutador",
			Text = "Boa sorte! Pode fechar quando terminar.",
			Action = "OpenRoll",
			Next = nil,
		},
		farewell = {
			Speaker = "Recrutador",
			Text = "Beleza, quando quiser é só voltar.",
			Next = nil,
		},
	},
}

-- NPC de missões — pra usar, crie um Model chamado "QuestGiver" (ou com o
-- atributo DialogueId = "QuestGiver") e adicione a tag "Dialogue" nele,
-- igual os outros dois. Abre o painel de missões diárias (QuestClient.lua
-- + QuestManager.legacy.luau, ReplicatedStorage.QuestData.lua com a lista
-- de missões).
DialogueData.QuestGiver = {
	Start = "greeting",
	Nodes = {
		greeting = {
			Speaker = "Zelador",
			Text = "Tenho algumas missões do dia pra você. Topa dar uma olhada?",
			Choices = {
				{ Text = "Ver missões", Next = "openQuests" },
				{ Text = "Depois eu volto", Next = "farewell" },
			},
		},
		openQuests = {
			Speaker = "Zelador",
			Text = "Aqui está — pode fechar quando terminar.",
			Action = "OpenQuests",
			Next = nil,
		},
		farewell = {
			Speaker = "Zelador",
			Text = "Beleza, elas resetam todo dia — quando quiser é só voltar.",
			Next = nil,
		},
	},
}

-- ⚠️ v68 — KOGAMALOTIGO: o NPC que abre a ficha do personagem.
-- PEDIDO: "tira esse botão [PERSONAGEM (P)] e coloca pro meu npc
-- kogamalotigo dizer algo na fala e abrir isso."
--
-- Ele ficou sendo o "técnico": quem cuida da sua ficha, dos seus slots e de
-- te explicar o que os atributos fazem. Isso dá a ele um papel de verdade no
-- lobby em vez de ser mais um boneco parado — e transforma abrir a ficha num
-- lugar aonde você VAI, não num botão que fica na sua cara o jogo inteiro.
DialogueData.Kogamalotigo = {
	Start = "greeting",
	Nodes = {
		greeting = {
			Speaker = "Kogamalotigo",
			Text = "Fala, craque. Quer dar uma olhada na sua ficha? Tenho tudo aqui — seus slots, seus atributos, o que você já destravou.",
			Choices = {
				{ Text = "Abre minha ficha", Next = "openCharacter" },
				{ Text = "O que os atributos fazem?", Next = "explainAttributes" },
				{ Text = "Só passando", Next = "farewell" },
			},
		},
		openCharacter = {
			Speaker = "Kogamalotigo",
			Text = "Tá na mão. Mexe à vontade — quando terminar, é só fechar.",
			Action = "OpenCharacter",
			Next = nil,
		},
		explainAttributes = {
			Speaker = "Kogamalotigo",
			Text = "Resumindo: Físico segura carrinho e ganha disputa. Chute é força e alcance. Drible manda na finta. Técnica é domínio, passe e primeiro toque. Velocidade é o quanto você corre, Fôlego é quantas jogadas seguidas você aguenta, e Energia é quantas Hissatsus você consegue soltar.",
			Choices = {
				{ Text = "Então abre aí", Next = "openCharacter" },
				{ Text = "Entendi, valeu", Next = "farewell" },
			},
		},
		farewell = {
			Speaker = "Kogamalotigo",
			Text = "Tá certo. Quando quiser mexer na ficha, eu fico por aqui.",
			Next = nil,
		},
	},
}

return DialogueData
