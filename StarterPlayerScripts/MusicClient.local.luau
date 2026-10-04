--[[
	MusicClient (LocalScript)
	LOCAL: StarterPlayerScripts (place Game)

	Música de fundo (loop contínuo, o jogo inteiro) + música de gol (só
	os primeiros segundos, com fade-out) — pedido: "coloque uma parte pra
	eu colocar uma música de fundo, e outra pra gol, me diga onde é e
	como eu coloco pra fazer funcionar".

	ONDE VOCÊ MEXE: só em FootballConfig.luau (ReplicatedStorage), colando
	os IDs dos seus áudios em Config.BACKGROUND_MUSIC_ID e
	Config.GOAL_MUSIC_ID (ver o comentário lá pra saber como pegar o ID
	no Creator Hub/Studio). Não precisa criar nada no Studio nem mexer
	neste arquivo — o Sound é criado inteiramente por código, porque só
	Scripts sincronizam pela ponte (Parts/GUI têm que ser manuais).

	SOBRE O CORTE DE 5s COM FADE-OUT: "eu preciso fazer isso, ou o Roblox
	consegue fazer também?" — o Roblox consegue, é só código (ver
	playGoalMusic abaixo): toca o áudio normalmente, e uns segundos antes
	do tempo configurado (Config.GOAL_MUSIC_FADE_SECONDS) começa a baixar
	o volume suavemente (TweenService) até parar exatamente em
	Config.GOAL_MUSIC_DURATION segundos. Não precisa editar o arquivo de
	áudio — pode subir a música inteira, o corte é só na hora de tocar.

	Toca no CLIENTE (cada jogador ouve a própria música — é o jeito padrão
	de música ambiente no Roblox: não depende do servidor, e cada
	SoundService já é local por jogador mesmo se fosse criado lá).

	⚠️ NOVO: FADE-IN NO LOOP (pedido: "no loop do áudio normal, ele sempre
	começa com um som mais alto do que o final do mesmo áudio, dá pra fazer
	um fade-in que não comece no mudo, tipo começa em 60% e vai até 100%")
	— tanto a torcida de fundo quanto a futura música secundária usam
	Sound.DidLoop (dispara toda vez que um Sound com Looped=true termina e
	reinicia sozinho, SEM cortar o áudio) pra reaplicar esse fade toda vez
	que o loop reinicia, inclusive na primeira vez que tocam.

	⚠️ NOVO: MÚSICA DE FUNDO SECUNDÁRIA (Config.SECONDARY_MUSIC_ID) — ainda
	vazia, é só o "molde" pronto pra quando você escolher a música (pedido:
	"depois eu vejo uma música legal pra colocar também e abafar um pouco a
	torcida, mas por enquanto coloque o código da futura música pra eu só
	inserir ela"). Com o ID vazio, nada disso roda — o jogo continua
	exatamente como antes. Quando você colar o ID: a torcida de fundo abaixa
	um pouco o tempo todo (Config.SECONDARY_MUSIC_CROWD_DUCK_MULT, "abafar a
	torcida") e a música secundária abaixa ainda mais durante o gol
	(Config.SECONDARY_MUSIC_GOAL_DUCK_MULT), porque toca o som de torcida
	comemorando (GOAL_MUSIC_ID) por cima — e volta ao normal sozinha depois.
]]

local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")

local Config = require(ReplicatedStorage:WaitForChild("FootballConfig"))
local Remotes = Config.Remotes

-- ⚠️ NOVO: helper genérico de fade-in de loop — usado pela torcida de fundo
-- E pela futura música secundária. Começa em `startFraction` do volume alvo
-- (NUNCA em 0/mudo, por pedido explícito) e sobe até `targetVolume` em
-- `fadeSeconds`. Chamado tanto no Play() inicial quanto em todo DidLoop.
local function applyLoopFadeIn(sound, targetVolume, startFraction, fadeSeconds)
	if not sound then return end
	startFraction = math.clamp(startFraction or 0.6, 0, 1)
	fadeSeconds = math.max(fadeSeconds or 1.5, 0.01)
	sound.Volume = targetVolume * startFraction
	TweenService:Create(sound, TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear), { Volume = targetVolume }):Play()
end

-- ⚠️ v48 — PLAYLIST (PEDIDO: "eu vou colocar mais músicas, por enquanto
-- deixa só essa"). A lista vem de Config.MUSIC_PLAYLIST; acrescentar uma
-- faixa lá é tudo que você precisa fazer, nada aqui muda.
--   1 faixa  -> toca em LOOP, com o fade-in de sempre a cada volta.
--   2+ faixas -> loop desligado, e a próxima entra no fim de cada uma
--                (evento .Ended), com o mesmo fade. Ao fim da lista,
--                recomeça da primeira.
-- Config.SECONDARY_MUSIC_ID continua aceito como faixa única, caso a
-- playlist esteja vazia — compatibilidade, não caminho principal.
local playlist = {}
if typeof(Config.MUSIC_PLAYLIST) == "table" then
	for _, id in ipairs(Config.MUSIC_PLAYLIST) do
		if typeof(id) == "string" and id ~= "" then
			table.insert(playlist, id)
		end
	end
end
if #playlist == 0 and typeof(Config.SECONDARY_MUSIC_ID) == "string" and Config.SECONDARY_MUSIC_ID ~= "" then
	table.insert(playlist, Config.SECONDARY_MUSIC_ID)
end

local hasSecondaryMusic = #playlist > 0

-- ===== MÚSICA DE FUNDO (torcida) =====
local bgMusic = nil -- ⚠️ v14: hoisted (fora do if) pra PreloadAsync conseguir referenciar mais embaixo
-- ⚠️ NOVO: enquanto a música secundária estiver ativa, a torcida toca mais
-- baixa ("abafar um pouco a torcida") — sem música secundária, esse fator
-- é 1 e o volume da torcida fica idêntico a antes.
local bgTargetVolume = (Config.BACKGROUND_MUSIC_VOLUME or 0.5) * (hasSecondaryMusic and (Config.SECONDARY_MUSIC_CROWD_DUCK_MULT or 1) or 1)
if typeof(Config.BACKGROUND_MUSIC_ID) == "string" and Config.BACKGROUND_MUSIC_ID ~= "" then
	bgMusic = Instance.new("Sound")
	bgMusic.Name = "BackgroundMusic"
	bgMusic.SoundId = Config.BACKGROUND_MUSIC_ID
	bgMusic.Looped = true
	bgMusic.Parent = SoundService
	applyLoopFadeIn(bgMusic, bgTargetVolume, Config.BACKGROUND_MUSIC_LOOP_FADE_START_FRACTION, Config.BACKGROUND_MUSIC_LOOP_FADE_SECONDS)
	bgMusic:Play()
	bgMusic.DidLoop:Connect(function()
		applyLoopFadeIn(bgMusic, bgTargetVolume, Config.BACKGROUND_MUSIC_LOOP_FADE_START_FRACTION, Config.BACKGROUND_MUSIC_LOOP_FADE_SECONDS)
	end)
else
	warn("🎵 MusicClient: Config.BACKGROUND_MUSIC_ID está vazio em FootballConfig.lua — cole o rbxassetid do seu áudio de fundo lá pra ativar a música (ver comentário no Config).")
end

-- ===== MÚSICA DE FUNDO SECUNDÁRIA (⚠️ NOVO — molde pronto, ID ainda vazio) =====
local secondaryMusic = nil
local secondaryTargetVolume = Config.SECONDARY_MUSIC_VOLUME or 0.35
local secondaryDucked = false -- true durante o gol, pra DidLoop/troca de faixa saberem qual alvo usar

-- Volume-alvo AGORA — uma função só, pra o fade da volta de loop, o da
-- troca de faixa e o do gol nunca discordarem entre si.
local function alvoDaMusica()
	if secondaryDucked then
		return secondaryTargetVolume * (Config.SECONDARY_MUSIC_GOAL_DUCK_MULT or 0.35)
	end
	return secondaryTargetVolume
end

-- ⚠️ v49 — CORTE DE CAUDA + FADE OUT NO FIM DE CADA FAIXA.
-- PEDIDO: "todas as músicas acabam finalizando um segundo e meio antes do
-- áudio acabar. Tira um segundo e meio do final de tudo e coloca um fade
-- out no final de todas as músicas."
--
-- Nenhuma faixa usa Looped nem o evento .Ended: os dois esperariam o
-- arquivo INTEIRO terminar, que é justamente a cauda morta que se quer
-- pular. Em vez disso, cada faixa é agendada — toca até
-- (duração - MUSIC_TAIL_CUT_SECONDS), desvanecendo nos últimos
-- MUSIC_FADE_OUT_SECONDS antes desse ponto, e aí a próxima entra.
-- Com UMA faixa só, "a próxima" é ela mesma, então o loop continua
-- existindo — só que cortado e com fade, em vez do corte seco do Looped.
--
-- A "geração" existe porque a prorrogação pode interromper uma faixa no
-- meio: qualquer agendamento antigo que acorde depois disso vê que a
-- geração mudou e desiste, em vez de retomar a música errada por cima.
local faixaAtual = 0
local geracaoDaFaixa = 0
-- ⚠️ v120b: estado da música do Flow (ver mais abaixo) — declarado aqui porque a
-- prorrogação (logo abaixo) precisa saber se ela está tocando
local flowTocando = false
local prorrogacaoPendente = false

local tocarFaixa -- declarada antes: agendarFimDaFaixa chama ela de volta

-- ⚠️ v110 FIX: esta função era chamada mas nunca tinha sido criada ("attempt
-- to call a nil value" na linha do agendarFimDaFaixa — a faixa nunca era
-- cortada/emendada). Espera o áudio carregar (até 15s) pra ler o TimeLength.
local function esperarCarregar(som)
	if not som then return false end
	local limite = os.clock() + 15
	while not som.IsLoaded and os.clock() < limite do
		task.wait(0.1)
	end
	return som.IsLoaded and som.TimeLength > 0
end

local function agendarFimDaFaixa(minhaGeracao, inicioSegundos)
	task.spawn(function()
		if not esperarCarregar(secondaryMusic) then return end
		if geracaoDaFaixa ~= minhaGeracao then return end

		local corte = Config.MUSIC_TAIL_CUT_SECONDS or 1.5
		local fade = Config.MUSIC_FADE_OUT_SECONDS or 1.5
		-- Ponto em que a faixa deve acabar de verdade.
		local fim = secondaryMusic.TimeLength - corte
		local tocavel = fim - (inicioSegundos or 0)
		if tocavel <= 0 then
			-- Áudio mais curto que o próprio corte (ou offset maior que ele):
			-- não dá pra cortar nada, deixa tocar inteiro.
			tocavel = math.max(secondaryMusic.TimeLength - (inicioSegundos or 0), 0.1)
			fade = math.min(fade, tocavel * 0.5)
		end

		local ateOFade = math.max(tocavel - fade, 0.05)
		task.wait(ateOFade)
		if geracaoDaFaixa ~= minhaGeracao then return end

		TweenService:Create(secondaryMusic, TweenInfo.new(fade, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
		task.wait(fade)
		if geracaoDaFaixa ~= minhaGeracao then return end

		secondaryMusic:Stop()
		tocarFaixa((faixaAtual % #playlist) + 1)
	end)
end

-- `inicioSegundos` só é usado pela prorrogação ("a do overtime começa a
-- partir de 50 segundos"); as faixas normais começam do zero.
tocarFaixa = function(indice, idOverride, inicioSegundos, fadeInSegundos)
	if not secondaryMusic then return end
	geracaoDaFaixa += 1
	local minhaGeracao = geracaoDaFaixa

	faixaAtual = indice
	secondaryMusic.SoundId = idOverride or playlist[indice]
	secondaryMusic.TimePosition = inicioSegundos or 0

	if fadeInSegundos and fadeInSegundos > 0 then
		-- ⚠️ v52 — PEDIDO: "coloca um fade in no overtime também."
		-- Aqui entra do SILÊNCIO mesmo, ao contrário do applyLoopFadeIn (que
		-- começa em 60% de propósito, pra volta de loop não dar salto de
		-- volume). São coisas diferentes: lá o objetivo é não chamar
		-- atenção, aqui é justamente a virada dramática pra prorrogação.
		secondaryMusic.Volume = 0
		TweenService:Create(secondaryMusic, TweenInfo.new(fadeInSegundos, Enum.EasingStyle.Linear), { Volume = alvoDaMusica() }):Play()
	else
		applyLoopFadeIn(secondaryMusic, alvoDaMusica(), Config.SECONDARY_MUSIC_LOOP_FADE_START_FRACTION, Config.SECONDARY_MUSIC_LOOP_FADE_SECONDS)
	end

	secondaryMusic:Play()
	-- TimePosition antes do Play() é ignorado se o áudio ainda não carregou —
	-- reaplica depois pra garantir que o offset da prorrogação valha mesmo.
	if (inicioSegundos or 0) > 0 then
		secondaryMusic.TimePosition = inicioSegundos
	end

	agendarFimDaFaixa(minhaGeracao, inicioSegundos)
end

if hasSecondaryMusic then
	secondaryMusic = Instance.new("Sound")
	secondaryMusic.Name = "SecondaryMusic"
	secondaryMusic.Looped = false -- ver o comentário do corte de cauda acima
	secondaryMusic.Parent = SoundService

	-- Rede de segurança. Quem troca de faixa normalmente é o agendamento
	-- (agendarFimDaFaixa), que precisa que o áudio CARREGUE pra saber a
	-- duração. Se um áudio não carregar (id errado, não aprovado, sem
	-- permissão pra este jogo), esse agendamento desiste — e sem isto aqui
	-- a música simplesmente pararia pra sempre, sem nada no Output.
	-- `Ended` só dispara quando o som termina SOZINHO (Stop() dispara
	-- `Stopped`, não `Ended`), então no fluxo normal isto nunca roda: o
	-- agendamento já parou a faixa antes, na marca do corte.
	secondaryMusic.Ended:Connect(function()
		warn("🎵 MusicClient: a faixa terminou sozinha, sem passar pelo corte agendado — provavelmente o áudio não carregou (id errado, não aprovado, ou sem permissão pra este jogo). Pulando pra próxima.")
		tocarFaixa((faixaAtual % #playlist) + 1)
	end)

	tocarFaixa(1)
end

-- ⚠️ v49 — TROCA PRA MÚSICA DA PRORROGAÇÃO.
-- PEDIDO: "vai intercalando entre as músicas e no final é aquela música do
-- overtime. Mas de um jeito que não pareça que elas vão interromper. NÃO
-- INTERROMPA ELAS, só interrompa na hora do overtime. Coloca uma
-- transiçãozinha, um fade out."
--
-- É o único ponto do jogo que corta uma faixa no meio — e por isso é o
-- único que faz fade out antes de trocar. As faixas normais nunca se
-- interrompem: cada uma vai até o fim do trecho tocável dela.
local function entrarNaProrrogacao()
	if not secondaryMusic then return end
	local id = Config.OVERTIME_MUSIC_ID
	if typeof(id) ~= "string" or id == "" then return end

	local fade = Config.MUSIC_FADE_OUT_SECONDS or 1.5
	geracaoDaFaixa += 1 -- cancela o agendamento da faixa que está tocando

	TweenService:Create(secondaryMusic, TweenInfo.new(fade, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
	task.delay(fade, function()
		if not secondaryMusic then return end
		secondaryMusic:Stop()
		tocarFaixa(
			faixaAtual, id,
			Config.OVERTIME_MUSIC_START_SECONDS or 0,
			Config.OVERTIME_MUSIC_FADE_IN_SECONDS or 0
		)
	end)
end

if Remotes.OvertimeStarted then
	Remotes.OvertimeStarted.OnClientEvent:Connect(function(...)
		-- ⚠️ v120b: com a música do Flow tocando, a prorrogação entra quando ela acabar
		if flowTocando then
			prorrogacaoPendente = true
			return
		end
		entrarNaProrrogacao(...)
	end)
end

-- ===== MÚSICA DE GOL (curta, com fade-out) =====
-- Fica só como MOLDE (nunca entra no SoundService sozinho) — cada gol
-- clona este molde, toca, e destrói a cópia depois. Assim dois gols
-- seguidos não brigam pelo mesmo Sound.
local goalMusicTemplate = nil
if typeof(Config.GOAL_MUSIC_ID) == "string" and Config.GOAL_MUSIC_ID ~= "" then
	goalMusicTemplate = Instance.new("Sound")
	goalMusicTemplate.Name = "GoalMusicTemplate"
	goalMusicTemplate.SoundId = Config.GOAL_MUSIC_ID
	goalMusicTemplate.Volume = Config.GOAL_MUSIC_VOLUME or 0.8
else
	warn("🎵 MusicClient: Config.GOAL_MUSIC_ID está vazio em FootballConfig.lua — cole o rbxassetid do seu áudio de gol lá pra ativar (ver comentário no Config).")
end

-- ⚠️ v14 FIX: "o áudio está um pouco atrasado, deu 1 segundo depois do
-- gol, precisa ser bem na hora". O Sound:Play() só toca de verdade depois
-- do Roblox terminar de BAIXAR o arquivo de áudio pela primeira vez — sem
-- isso, o primeiro Play() de cada áudio (ou de cada CLONE, no caso do gol)
-- sempre tem um atraso de carregamento (varia com o tamanho do arquivo/
-- conexão). ContentProvider:PreloadAsync baixa o áudio ANTES, aqui no
-- carregamento do script (bem no início da partida, sobra tempo de sobra
-- até o primeiro gol de verdade) — assim quando o gol acontecer de
-- verdade, o áudio já está em cache e toca instantaneamente.
task.spawn(function()
	local toPreload = {}
	if bgMusic then table.insert(toPreload, bgMusic) end
	if secondaryMusic then table.insert(toPreload, secondaryMusic) end
	if goalMusicTemplate then table.insert(toPreload, goalMusicTemplate) end
	if #toPreload > 0 then
		ContentProvider:PreloadAsync(toPreload)
	end
end)

local activeGoalSound = nil

-- ⚠️ NOVO: PEDIDO — "o áudio está tocando duas vezes... repetindo quando
-- o replay começa, isso não pode acontecer" — trava extra do lado do
-- CLIENTE (além do aumento da janela de dedup no servidor, ver
-- MatchController.legacy.luau/GOAL_DEDUP_WINDOW): se por QUALQUER motivo
-- Remotes.GoalScored chegar de novo antes de um "gol de verdade" fazer
-- sentido (cooldown = a duração inteira da música de gol), esse segundo
-- disparo é ignorado e avisado no Output — não reinicia a música por cima
-- da que já está tocando.
local lastGoalMusicAt = -math.huge

-- ⚠️ NOVO: abaixa a música secundária durante o gol (o som de torcida
-- comemorando toca por cima) e devolve ela ao volume normal sozinha
-- depois — usa os mesmos tempos do fade da própria música de gol
-- (GOAL_MUSIC_DURATION/GOAL_MUSIC_FADE_SECONDS) pra ficar tudo sincronizado.
-- ============================================================
-- ⚠️ v120b — MÚSICA DO FLOW. PEDIDO: "quando a música tema do Flow estiver
-- rolando, o restante das músicas vai se dissipar; fade in pra começar e fade out
-- no final. Na comemoração do gol ela abaixa um pouquinho. Ela tem prioridade
-- maior que a música de fundo: a de fundo acaba quando ela começa."
-- Cada Flow tem Musica = { Id, Volume } em Cosmeticos. Começa junto com a CENA
-- do Flow (Remotes.HissatsuCutscene "Flow_...", sincronizada pelo horário do
-- servidor — a batida forte cai na pisada) e vai até o Flow acabar (atributo
-- FlowAtivo do jogador some) ou um teto de segurança.
-- ============================================================
local Players = game:GetService("Players")
local Cosmeticos = nil
pcall(function() Cosmeticos = require(ReplicatedStorage:WaitForChild("Cosmeticos", 10)) end)
flowTocando = false
local musicaFlow = nil
local fundoFlow = nil -- (v126j) faixa licenciada tocando junto (Musica.Fundo)
local geracaoFlow = 0
local FADE_FLOW = 1.2
local entrarNaProrrogacaoFn -- (definida mais acima; ligada no fim do arquivo)

local function pararMusicaFlow()
	if not flowTocando then return end
	flowTocando = false
	geracaoFlow += 1
	local som = musicaFlow
	musicaFlow = nil
	local fundo = fundoFlow
	fundoFlow = nil
	for _, s in pairs({ som, fundo }) do
		TweenService:Create(s, TweenInfo.new(FADE_FLOW, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
		task.delay(FADE_FLOW + 0.05, function() s:Destroy() end)
	end
	-- a música de fundo volta de onde parou, com fade
	if prorrogacaoPendente and entrarNaProrrogacaoFn then
		prorrogacaoPendente = false
		entrarNaProrrogacaoFn()
	elseif secondaryMusic then
		geracaoDaFaixa += 1
		local minha = geracaoDaFaixa
		secondaryMusic.Volume = 0
		secondaryMusic:Resume()
		TweenService:Create(secondaryMusic, TweenInfo.new(FADE_FLOW * 1.5, Enum.EasingStyle.Linear), { Volume = alvoDaMusica() }):Play()
		agendarFimDaFaixa(minha, secondaryMusic.TimePosition)
	end
end

local function tocarMusicaFlow(item, quem, horario, duracaoCena)
	local musica = item and item.Musica
	if typeof(musica) ~= "table" or typeof(musica.Id) ~= "string" or musica.Id == "" then return end
	if flowTocando then pararMusicaFlow() end
	flowTocando = true
	geracaoFlow += 1
	local minha = geracaoFlow
	-- a de fundo some (pausa, pra voltar do mesmo ponto)
	if secondaryMusic then
		geracaoDaFaixa += 1 -- cancela o corte agendado da faixa atual
		local sm = secondaryMusic
		TweenService:Create(sm, TweenInfo.new(FADE_FLOW, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
		task.delay(FADE_FLOW, function()
			if flowTocando and geracaoFlow == minha then sm:Pause() end
		end)
	end
	local som = Instance.new("Sound")
	som.Name = "MusicaDoFlow"
	som.SoundId = musica.Id
	som.Volume = 0
	som.Parent = SoundService
	musicaFlow = som
	local alvo = musica.Volume or 0.6
	som:Play()
	-- sincroniza com a cena (quem entrou atrasado começa do ponto certo)
	local atraso = math.max(workspace:GetServerTimeNow() - (horario or workspace:GetServerTimeNow()), 0)
	if atraso > 0.05 then som.TimePosition = atraso end
	TweenService:Create(som, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Volume = alvo }):Play()
	som:SetAttribute("VolumeAlvo", alvo)
	-- ⚠️ v126j — Musica.Fundo = { Id, Volume, Inicio }: uma faixa LICENCIADA do Roblox (Creator
	-- Store, nunca é restringida) tocando junto do áudio das falas/efeitos. PEDIDO: "o áudio
	-- deu como restrito" (a trilha oficial dentro do nosso áudio é que fazia o Roblox restringir)
	local fundoCfg = musica.Fundo
	if typeof(fundoCfg) == "table" and typeof(fundoCfg.Id) == "string" and fundoCfg.Id ~= "" then
		local fundo = Instance.new("Sound")
		fundo.Name = "FundoDoFlow"
		fundo.SoundId = fundoCfg.Id
		fundo.Volume = 0
		fundo.Parent = SoundService
		fundoFlow = fundo
		fundo:Play()
		fundo.TimePosition = (fundoCfg.Inicio or 0) + (atraso > 0.05 and atraso or 0)
		local alvoFundo = fundoCfg.Volume or 0.5
		TweenService:Create(fundo, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Volume = alvoFundo }):Play()
		fundo:SetAttribute("VolumeAlvo", alvoFundo)
	end
	-- fim: quando o Flow do jogador acabar (FlowAtivo some depois de ter aparecido)
	if typeof(quem) == "Instance" and quem:IsA("Player") then
		local viuAtivo = false
		local con
		con = quem:GetAttributeChangedSignal("FlowAtivo"):Connect(function()
			if geracaoFlow ~= minha then con:Disconnect() return end
			if quem:GetAttribute("FlowAtivo") then
				viuAtivo = true
			elseif viuAtivo then
				con:Disconnect()
				pararMusicaFlow()
			end
		end)
	end
	-- teto de segurança: o fim do áudio (v126c: o Flow dura a música inteira), ou cena + 25s
	task.delay(type(musica.Duracao) == "number" and (musica.Duracao + 1) or ((duracaoCena or 12) + 27), function()
		if geracaoFlow == minha then pararMusicaFlow() end
	end)
	som.Ended:Connect(function()
		if geracaoFlow == minha then pararMusicaFlow() end
	end)
end

if Remotes.HissatsuCutscene then
	Remotes.HissatsuCutscene.OnClientEvent:Connect(function(nome, quem, _inicio, _bola, horario, _titulo, duracao)
		if typeof(nome) ~= "string" or nome:sub(1, 5) ~= "Flow_" or not Cosmeticos then return end
		local item = Cosmeticos.Item(nome)
		pcall(tocarMusicaFlow, item, quem, horario, duracao)
	end)
end

-- na comemoração do gol a música do Flow abaixa um pouco e volta
local function duckMusicaFlowParaGol()
	local duration = Config.GOAL_MUSIC_DURATION or 5
	for _, som in pairs({ musicaFlow, fundoFlow }) do
		local alvo = som:GetAttribute("VolumeAlvo") or 0.6
		TweenService:Create(som, TweenInfo.new(0.6, Enum.EasingStyle.Linear), { Volume = alvo * 0.55 }):Play()
		task.delay(duration, function()
			if som.Parent and (musicaFlow == som or fundoFlow == som) then
				TweenService:Create(som, TweenInfo.new(1.2, Enum.EasingStyle.Linear), { Volume = alvo }):Play()
			end
		end)
	end
end

local function duckSecondaryMusicForGoal()
	duckMusicaFlowParaGol()
	if flowTocando then return end -- (a de fundo está pausada pela música do Flow)
	if not secondaryMusic then return end

	local duration = Config.GOAL_MUSIC_DURATION or 5
	local fadeSeconds = math.clamp(Config.GOAL_MUSIC_FADE_SECONDS or 1.5, 0.01, duration)
	secondaryDucked = true
	TweenService:Create(secondaryMusic, TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear), { Volume = alvoDaMusica() }):Play()

	task.delay(duration, function()
		if not secondaryMusic then return end
		secondaryDucked = false
		if flowTocando then return end
		TweenService:Create(secondaryMusic, TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear), { Volume = alvoDaMusica() }):Play()
	end)
end

local function playGoalMusic()
	if not goalMusicTemplate then return end

	local duration = Config.GOAL_MUSIC_DURATION or 5
	local now = os.clock()
	if now - lastGoalMusicAt < duration then
		warn(("🎵 MusicClient: Remotes.GoalScored chegou de novo %.1fs depois do último gol (dentro da janela de %.1fs da música) — IGNORADO pra não tocar a comemoração duas vezes. Se isso aparecer toda partida, o gol está sendo contado 2x no servidor (ver aviso 'duplicata detectada' em MatchController.legacy.luau)."):format(now - lastGoalMusicAt, duration))
		return
	end
	lastGoalMusicAt = now

	-- Gol muito seguido do outro (ou o dedup do MatchController falhando):
	-- corta o anterior em vez de tocar os dois em cima um do outro.
	if activeGoalSound then
		activeGoalSound:Stop()
		activeGoalSound:Destroy()
		activeGoalSound = nil
	end

	local instance = goalMusicTemplate:Clone()
	instance.Parent = SoundService
	instance:Play()
	activeGoalSound = instance

	duckSecondaryMusicForGoal()

	local duration = Config.GOAL_MUSIC_DURATION or 5
	local fadeSeconds = math.clamp(Config.GOAL_MUSIC_FADE_SECONDS or 1.5, 0, duration)
	local fadeStartsAt = duration - fadeSeconds

	task.delay(fadeStartsAt, function()
		if instance == activeGoalSound and instance.Parent then
			TweenService:Create(instance, TweenInfo.new(fadeSeconds, Enum.EasingStyle.Linear), { Volume = 0 }):Play()
		end
	end)

	task.delay(duration, function()
		if instance == activeGoalSound then
			activeGoalSound = nil
		end
		if instance.Parent then
			instance:Stop()
			instance:Destroy()
		end
	end)
end

Remotes.GoalScored.OnClientEvent:Connect(function(_scoringTeam, _scorer, _score)
	playGoalMusic()
end)

-- (a prorrogação que chegar durante a música do Flow espera ela acabar)
entrarNaProrrogacaoFn = entrarNaProrrogacao

print("✅ MusicClient carregado.")
