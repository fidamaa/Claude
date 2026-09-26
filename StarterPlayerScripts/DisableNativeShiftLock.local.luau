--[[
	DisableNativeShiftLock (LocalScript)
	LOCAL: StarterPlayer > StarterPlayerScripts (place Game)

	Desliga a opção NATIVA de Shift Lock do Roblox (o ícone de cadeado do
	mouse / o Shift Lock padrão das configurações) — o jogo já tem seu
	PRÓPRIO shift lock (tecla Ctrl, ver FootballClient.local.luau), então
	deixar o nativo ligado só atrapalha (dois sistemas de câmera/trava de
	mouse podendo brigar um com o outro, ou o ícone nativo aparecendo sem
	fazer nada de útil).

	StarterPlayer.EnableMouseLockOption é a property que controla isso —
	setar aqui, o mais cedo possível (topo do arquivo, sem esperar
	character/PlayerGui), garante que o PlayerModule padrão do Roblox
	(que lê essa property quando inicializa o controle de câmera) já
	pega ela desligada.
]]

game:GetService("StarterPlayer").EnableMouseLockOption = false
