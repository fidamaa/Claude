--[[
	SprintClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Lobby)

	⚠️ NOVO — SPRINT REMOVIDO. PEDIDO: "Não haverá botão de corrida/sprint.
	O personagem deve correr normalmente usando WASD, e sua velocidade será
	determinada pelo atributo Velocidade."

	Este script ligava o Shift (e o botão SPRINT do celular) ao
	ReplicatedStorage.UpdateSprintingState. Agora o StaminaManager.legacy.
	luau deixa o personagem SEMPRE na velocidade de corrida x Velocidade,
	então não há mais nada pra escutar aqui. O arquivo ficou vazio de
	propósito (em vez de apagado) pra o sync não deixar uma cópia antiga no
	Studio — pode apagar o LocalScript "SprintClient" do Studio quando
	quiser, nada depende dele.
]]

print("✅ SprintClient (Lobby): sem sprint — corrida é sempre na velocidade do atributo.")
