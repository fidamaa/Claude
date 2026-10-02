--[[
	EmotesCustom (ModuleScript) — ⚠️ v117
	LOCAL: ReplicatedStorage (IGUAL nos dois places: Game e Lobby — Roblox não tem
	require entre places; mexeu num, copie o arquivo inteiro pro outro)

	PEDIDO: "não precisa fazer os emotes — coloca uma área só pra eu poder ficar
	adicionando um por um: eu coloco o nome deles e coloco a animação, porque meus
	amigos querem fazer."

	ESTA É A ÁREA. Pra cadastrar um emote novo é só ACRESCENTAR UMA LINHA na lista
	abaixo, com o NOME e o ID DA ANIMAÇÃO. Pronto: ele aparece na Eleven Store
	(Armário > Emotes), dá pra comprar, colocar numa das 6 casas da roda e tocar com
	a tecla G, no Lobby e na partida.

	  { Nome = "Siuuu", AnimacaoId = 1234567890 },

	Campos (só Nome e AnimacaoId são obrigatórios):
	  Nome         texto que aparece na loja e na roda.
	  AnimacaoId   número do asset da animação (ou "rbxassetid://123..."). A animação
	               precisa ser do mesmo tipo de corpo do personagem (R15) e estar
	               publicada por você/pelo grupo dono do jogo (ou pública) — senão o
	               Roblox não toca e o emote fica parado.
	  Raridade     "Common" | "Rare" | "Epic" | "Legendary" | "Mythic" (padrão "Common").
	               Define o preço (ver Cosmeticos.PRECO) e a cor do cartão.
	  Duracao      segundos até o emote parar sozinho (padrão: o tamanho da animação).
	  Loop         true = a animação repete até acabar a Duracao (padrão false).
	  Preco        preço próprio em vez do da raridade (opcional).
	  Gratis       true = todo mundo já tem (opcional).
	  Descricao    frase curta (opcional).
	  Autor        quem fez (opcional — aparece na descrição).

	REGRAS:
	  • NÃO renomeie um emote depois de publicado: o Id interno nasce do Nome, e quem
	    já comprou perderia o item. Pra corrigir o ID da animação pode mexer à vontade.
	  • Dois emotes não podem ter o mesmo Nome.
	  • Mexeu aqui? Copie o ARQUIVO INTEIRO pro outro place (Game <-> Lobby).

	Exemplos (tire o "--" da frente pra testar):
	  -- { Nome = "Griddy", AnimacaoId = 111111111, Raridade = "Rare", Duracao = 4, Loop = true, Autor = "Fulano" },
	  -- { Nome = "Siuuu", AnimacaoId = "rbxassetid://222222222", Raridade = "Epic" },
]]

local EmotesCustom = {
	-- ↓↓↓ ADICIONE OS EMOTES AQUI, UM POR LINHA ↓↓↓


	-- ↑↑↑ (não apague a chave "}" de baixo) ↑↑↑
}

return EmotesCustom
