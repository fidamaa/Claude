--[[
	Animate (LocalScript) — VAZIO DE PROPÓSITO
	LOCAL: StarterPlayer > StarterCharacterScripts

	⚠️ v96 — PEDIDO: "verifica se não tem duas animações tocando ao mesmo
	tempo... parece que tem uma animação embolada na outra... a mão do
	personagem parece que fica solta".

	O Roblox coloca um script "Animate" em todo personagem que nasce. Ele toca
	andar/correr/parado/pulo — e, no JOGO PUBLICADO, o Roblox ainda troca essas
	animações pelo PACOTE DE ANIMAÇÃO do avatar de cada jogador (o "Ninja", o
	"Stylish"...). Isso tocava POR BAIXO das nossas animações, e o Roblox
	mistura por junta: onde a nossa não mexia (a mão), aparecia a do pacote.
	No Studio não aparecia porque lá não tem pacote de avatar.

	Um script com este MESMO NOME aqui em StarterCharacterScripts substitui o
	padrão do Roblox. Como ele não tem nada dentro (nem as pastas walk/run/
	idle), o pacote do avatar também não tem onde entrar. Quem anima o corpo
	é só o AnimadorProcedural (StarterPlayerScripts).

	O Animate antigo do place ficou guardado em ServerStorage.Backup_Animate
	(pra voltar, é só mover ele de volta pra cá).
]]
