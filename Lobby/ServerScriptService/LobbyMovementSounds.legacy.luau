--[[
	LobbyMovementSounds (Script) — DESATIVADO / SUBSTITUÍDO
	LOCAL: ServerScriptService (place Lobby)

	⚠️ ESSE SCRIPT NUNCA PODIA TER FUNCIONADO — você pode DELETAR ele no
	Studio, ficou só como stub (não faz mais nada) pra não confundir.

	Motivo: os sons "Running"/"Jumping" são criados em TEMPO DE EXECUÇÃO
	pelo código do "Animate" (LocalScript que o Roblox insere em cada
	personagem) — um LocalScript dentro de um Character só roda no(s)
	CLIENTE(S) que estão vendo aquele personagem, e os Sound que ele cria
	ficam só na cópia LOCAL daquele cliente. Um Script no ServerScriptService
	(como este) NUNCA enxerga esses Sound, não importa quanto tempo espere.

	A correção de verdade agora mora em StarterPlayerScripts/
	LobbyMovementSoundsClient.local.luau (roda no CLIENTE, pra todo
	personagem que ele consegue ver).
]]

print("ℹ️ LobbyMovementSounds: desativado — ver LobbyMovementSoundsClient.local.luau (StarterPlayerScripts). Pode deletar este Script no Studio.")
