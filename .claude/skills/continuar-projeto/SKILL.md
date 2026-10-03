---
name: continuar-projeto
description: Passagem de bastão do jogo de futebol Roblox (Inazuma Eleven + Blue Lock) — como trabalhar neste projeto, o que já foi feito, o que está pendente e cada detalhe que o usuário pediu. Use no começo de qualquer sessão que vá continuar o trabalho ("continua o que faltou", "faz o resto", "faça o Flow do X").
---

# Continuar o projeto (leia inteiro antes de mexer)

## O projeto
- Jogo de futebol no Roblox inspirado em Inazuma Eleven + Blue Lock. Dois places:
  **Game** (a partida, raiz do repo) e **Lobby** (pasta `Lobby/`).
- Repo local: `C:\Users\fidamaa\Downloads\Game`. Branch de trabalho:
  `claude/awesome-hawking-lzkalt` (push sempre nela; nunca em `main`).
- Falar SEMPRE em português com o usuário. Ele salva e publica os places — lembre
  ele de publicar os DOIS no fim.
- Comentários no código em português com `⚠️ vNN` + a frase do PEDIDO do usuário.
  Versão atual: v121 (próxima: v122).
- Commit no fim de cada bloco, terminando com
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; depois `git push`.
  NÃO commitar `Lobby/ServerScriptService/MatchmakingQueue.legacy.luau` (mudança do
  próprio usuário, pendente): `git add -A -- . ':!Lobby/ServerScriptService/MatchmakingQueue.legacy.luau'`.
- Antes de commitar, rode o balance check (parênteses/chaves/colchetes) em todo
  arquivo editado — o script está na skill `roblox-studio-script-sync`. ATENÇÃO:
  ele não falha o comando; LEIA a saída (já commitei um `MISMATCH` sem ver).
- Comentário no fim de linha que tem `}` / `},` depois: coloque o comentário DEPOIS
  do fechamento, senão ele engole o `},` (aconteceu no Cosmeticos).

## Sincronização com o Studio (MCP Roblox Studio)
- IDs do Studio mudam a cada abertura: use `list_roblox_studios`.
  "Correspondência Automática" = Game; "Onze Fechaduras" = Lobby.
- Disco → Studio sincroniza sozinho: Game `ReplicatedStorage` e
  `ServerScriptService`; Lobby inteiro. Se parar (depois que o usuário reabre o
  Studio), PEÇA pra ele religar a sincronização — não tente contornar.
- Game `StarterPlayerScripts` NÃO sincroniza. Pra levar um script de lá:
  copie `StarterPlayerScripts/X.local.luau` pra `ReplicatedStorage/_TmpSync_X.luau`,
  espere aparecer no Studio, rode no Edit:
  `ScriptEditorService:UpdateSourceAsync(StarterPlayerScripts.X, function() return tmp.Source end)`,
  depois apague os `_TmpSync_*` do disco (e confira que sumiram do Studio).
  ⚠️ v122b: numa dessas o `StarterPlayerScripts/HissatsuInput.local.luau` apareceu
  VAZIO no disco logo depois. Sempre rode `git status` depois do `_TmpSync` e
  restaure com `git checkout -- <arquivo>` se algum script zerou.
- Nome do arquivo define a classe: `X.luau` = ModuleScript, `X.legacy.luau` =
  Script, `X.local.luau` = LocalScript. (O painel de debug virou ModuleScript por
  causa disso e "sumiu" — corrigido pra `.local.luau`.)
- Pra conferir Studio x disco: some um hash por script dos dois lados (exemplo
  usado: `scratchpad/hash_disco.py` + um execute_luau com o mesmo hash).
- `execute_luau` não dispara remote nem usa HttpService; o `_G` dele é separado do
  jogo. No **Edit** dá pra `require` um módulo (use `require(modulo:Clone())` pra pegar a
  versão nova) — foi assim que a MiraPrecisa foi testada com uma câmera falsa. Pra testar
  no Play: gancho temporário `--TESTE_INICIO ... --TESTE_FIM` no FIM do
  `PulseController` escutando um atributo do `workspace` (modelos usados na v122:
  `TesteFlow` → `_G.TocarCenaFlow(p)`; `TesteCena` = nome da cutscene →
  `_G.SetBallOwnerForced(p)` + `playHissatsuCutscene(p, {Cutscene = nome}, onDone)`, e no
  onDone um chute de verdade: `_G.ProcessarChuteServidor` ou `_G.PulseExecuteShot(p,
  effect, raridade)` com `LastAimPoint[p]` setado). TIRE antes do commit.
  - Mudou arquivo? PARE o Play (o sync só entra no Edit), confira a fonte no Edit e dê
    Play de novo.
  - `CutsceneDebugT` no LocalPlayer congela a cutscene no cliente — e ela NÃO termina
    enquanto congelada: a próxima cutscene do teste fica esperando. Tire o atributo
    (`nil`) antes de disparar outra.
  - Câmera pra ver um efeito de lado: `task.spawn` no cliente que espera a peça aparecer
    e põe a câmera em Scriptable por 2-3s (depois volta pra Custom).
- Testes: quando o usuário deixa o Studio aberto e pede ("trabalha a noite toda"),
  teste no Play com screenshots e só mande quando estiver bom. Sem esse pedido: termine,
  avise e deixe ele testar ("deixa que eu testo").
- Imagens: gere com PIL (skill `particulas-roblox`), sirva com
  `python -m http.server 8766 --bind 127.0.0.1` na pasta das imagens e suba com
  `upload_image`. ÁUDIO o MCP não sobe: gere o mp3 em `_upload/` (fora do git), o
  usuário sobe (Studio → View → Asset Manager → Bulk Import → Copy Asset ID) e manda
  o ID. Confira o ID carregando um `Sound` no Edit (`IsLoaded`, `TimeLength`).

## Regras do usuário (não quebrar)
- NÃO mudar sem pedido: hissatsus de goleiro, dribles/tackles aprovados, Tornado de Fogo.
- NÃO renomear armas (o inventário salva pelo nome) nem remover armas que têm imagem
  (adapte). Não criar armas novas: modifique as menos úteis.
- Vídeo de referência sempre mudo.
- Jogadores são R6 (sem joelho/cotovelo). Braço R6 NÃO pode entrar no tronco:
  movimento exagerado pra fora (|rz| ≥ 20 parado, ≥ 40 em movimento) e medir.
- Flow: aura e olho com SENTIDO do anime, imagem própria, efeito NO ROSTO; sem corte
  de câmera onde o vídeo transforma. Tudo na skill `flow-cutscene` (leia ela pra
  qualquer Flow) — inclui "Por que errei no Isagi" (10 erros) e a música por Flow.

## O que JÁ está feito (v119-v120f) e onde
- Flow do Isagi completo (`HissatsuCutscenes.luau` bloco 🧠 FLOW DO ISAGI;
  `HissatsuEfeitos.luau` `E.FlowIsagi` e `E.OlhosFlow`): levanta com riscos/ar
  subindo, olho branco → íris de quebra-cabeça no rosto (gira, nos dois olhos, também
  na partida), zoom no olho, visão dele com o Rin de costas em câmera lenta com bola,
  espiral de pinceladas (borda + miolo + cheia) fechando, mundo do quebra-cabeça, dash
  com braços pra trás e a cabeça se desfazendo em mini peças. Áudio único mixado
  (`.claude/skills/flow-cutscene/mixar_cena_isagi.py`): Puzzle + fala do Sung Jin-Woo
  (Solo Leveling ep.11, 0:29,4-0:34) + SFX sintetizados; ID 138043913660792, Volume 1.3,
  em `C.Flow` do Cosmeticos (DUAS cópias: Game e Lobby, sempre iguais).
- Música do Flow (`StarterPlayerScripts/MusicClient`): começa com a cena, some a de
  fundo, abaixa no gol, volta no fim (atributo `FlowAtivo`). Flow dura 25s e só um
  por vez (`InstinctController`, `INSTINCT_MODE_DURATION`).
- Bola/física: rola mais (`BALL_ROLLING_*`), domínio até 30 (`LOOSE_BALL_PICKUP_MAX_SPEED`),
  carrinho só corta bola até 40% da barra (`TACKLE_INTERCEPT_BAR_FRACTION`), cabeçada
  `HEADER_RANGE` 7 / min 2, voleio `VOLLEY_HITBOX_MULT` 1.5.
- Chute do Rin (Tiro Destruidor): curva em todo chute a gol (rumo gira de 35% a 70% do
  caminho, até 30°) — `_G.ArmaAplicarCurva` no BallController; a curva vem de qualquer
  arma equipada (`_G.CurvaDaArmaEquipada`). Testado no servidor: funciona.
- GK player: pega a bola que passa dentro dele (caminho entre quadros, caixa
  `GK_CORPO_CAPTURA`), pulo 16.8 com subida rápida (`GK_PULO_GRAVIDADE_MULT`, GKInput),
  dive 0.5s, mãos separadas, cai no chão e levanta.
- Bugs: carrinho/dash travando (faxina de `tackleDashes`), corpo afundando no fim das
  cutscenes (termina de pé), reset limpa ações (`_G.LimparAcoesDoJogador`), partículas
  do Flow no fantasma do replay.
- Efeitos de gol: -2s, Buraco Negro mais claro, Supernova com planeta 3D.
- Muralha Infinita gigante (barreira = caixa do muro, `_G.DentroDaBarreira`); Corte
  Giratório com muro azul 3.5s que tira ~45 de força (vantagem de elemento).
- Counters: Monstro do Drible (automático, `_G.UsarCounterDaArma`), Última Barreira
  (contra chute), Antecipação Fantasma, Leitura de Passe. Passo Furtivo = só sumir.
  Monstro do Drible com cópia exata + rastro. Domínio = trap do Nagi. Tontura
  (`_G.MostrarTontura`) em pisão/ankle breaker/área. Bola Ilusão: troca de lugar
  com uma de 3 figuras.
- Painel de debug: `StarterPlayerScripts/DebugAbilitySelectorHUD_local.local.luau`.

## PENDENTE (fazer nesta ordem, um de cada vez, avisando e esperando o usuário testar)
1. ✅ FEITO (v121, falta o usuário testar) — **Voleio e cabeçada mais fáceis**: voleio
   ~13 studs na HORIZONTAL (`VOLLEY_HITBOX_MULT` 2.2, teto `VOLLEY_ALTURA_MAX` 14),
   cabeçada `HEADER_RANGE` 13 / min 1. O cliente (`FootballClient.acaoAerea`) escolhe
   cabeçada se a bola está na faixa da cabeça, senão voleio. Se ele reclamar que a
   cabeçada "rouba" o voleio de novo, ajuste a faixa de altura, não o alcance.
2. ✅ FEITO (v121, falta testar) — **Chute antecipado**: soltar o chute até
   `CHUTE_ANTECIPADO_SEG` (0.35s) antes da bola chegar: o pedido fica guardado
   (`_G.GuardarChuteAntecipado`, BallController, logo antes da CABEÇADA) e é tentado
   todo quadro via `_G.ProcessarChuteServidor(..., tentativaGuardada=true)`.
3. Perguntar ao usuário: a foto do desenho no caderno (`rbxassetid://116382303436712`)
   vai pro "Desenho" do Bentes ou pra pintura "Obra-prima" do Tiluca (NPCs do Lobby)?
4. Outros Flows (Bachira, Nagi, Rin, Barou...): quando ele pedir "faça o Flow do X",
   siga a skill `flow-cutscene` inteira (vídeo quadro a quadro, tabela de planos,
   aura com sentido, olho no rosto, música da playlist + mixagem, nada de corte onde
   o vídeo transforma).
5. Testes que só o usuário faz (com 2+ jogadores): armas/counters, portal da Queda
   Celestial em voo, Rin com companheiro real.
6. ✅ **Lista da noite de 03/10 (v122)** — toda feita (ver abaixo). Próximo: o que o
   usuário disser depois de testar; conferir as poses de chute das outras hissatsus (G7).

## Lista da noite (v122) — ✅ TUDO FEITO E ENVIADO (03/10), falta o usuário testar em partida
Flow do Isagi (commit 36c3d7d), testado no Studio com screenshots:
- ✅ F1 vídeo revisto (ordem bate; o trecho dos braços em X foi tirado a pedido antes).
- ✅ F2 braços do dash pra trás e um pouco abaixo da horizontal (`FI_DASH` −40/±18; final
  −44/±20). De frente em 3/4 eles parecem abertos — é a câmera; de lado lê certo.
- ✅ F3 espiral entra pelas BORDAS desde 7.6 (escala 1.9 → 1.2) e aperta em volta do Rin;
  vinheta em `RelativeXY` 1.6 → 1.02; miolo só fecha 8.3-8.52; preto só depois.
- ✅ F4 corrida do Rin (ciclo de 4 poses na Catmull-Rom), Rin mais longe e em silhueta
  escura (`Clones.Cor` 16,28,44 / Fill 0.35); câmera POV mais aberta (58 → 50).
- ✅ F5 levantada: pedrinhas, anéis, vapor; riscos do ar RETOS (Rotation 0).
- ✅ F6 brilho branco (PointLight + miolo branco), íris 85°/s. ✅ F7 arrepio.
Depois:
- ✅ G1 (628d55a) curva do Rin SÓ com A/D segurado ao soltar: o cliente manda o movimento
  (`FootballClient.movimentoDoChute`, 4º parâmetro do `KickBall`); sem A/D o chute a gol
  sai reto (era o "vai pro lado sozinho"); 24°. O remote tem parâmetros explícitos.
- ✅ G2 (13b348c) dive pro lado 54; levantar mais devagar (GKDive 1.6s, GKForwardDash
  1.5s); errou dive/avanço = stun `GK_DIVE_ERRO_STUN` 1.0 / `GK_FORWARD_ERRO_STUN` 0.85.
- ✅ G3 (334f6f9) Tornado/Dragão: pernas abrem 17° → 78° na subida; no chute a direita fica
  parada ~45° pra trás e só a esquerda chicoteia (medido).
- ✅ G4 (042d0c7) Queda Celestial: `tuboPortal` — CILINDRO 3D (peças Cylinder, cascas
  ForceField ciano/magenta + espaço escuro) do ponto do chute até a bola, 5.5s; dentro:
  estrelinhas piscando, estrelas de 4 pontas SALTANDO, nebulosas e planetas, tudo no raio.
  O usuário viu e aprovou o formato; pediu mais cara de universo (feito).
- ✅ G5 (ec74b71) duelo: o IMPACTO da defesa tira no máximo 55% da força do chute
  (`DEFESA_IMPACTO_MAX_DO_CHUTE`, `duelo.Impacto`) — lendária x lendária zerava 180 na hora.
- ✅ G6 (f6c40f0) parceiros mais longe: Raio Um, Galáxia, Dragão, Gaia (Zona Morta não).
- ✅ G7 (d71989a) chute normal: perna de apoio plantada no R6. FALTA conferir as poses de
  chute de CADA hissatsu (só o Tornado/Dragão e o chute normal foram revistos).
- ✅ G8 (736d2fd) Fúria Glacial: mortal grupado no AR (sem tocar o gelo) e `CurvaInicial`
  (11°, 30 studs: sai ~1,8 stud pro lado, volta pra linha e segue reta — medido).
- ✅ G9 (0d18bb8) mira: ponto atrás do gol (arquibancada/céu) vira o cruzamento do raio do
  cursor com a BOCA do gol (`MiraPrecisa`) — vale pra todo chute.

## Depois da v122 (v122b, mesma sessão)
- Mira: o alinhamento na boca do gol (`opcoes.AlinharNaBocaDoGol` na `MiraPrecisa`) é SÓ
  das Hissatsus (HissatsuInput); o chute normal usa a mira antiga (o usuário: "no chute
  normal ela sai muito pra cima").
- "Chute normal vai pro lado": medido no Studio, parado / com giro / andando de lado a
  16 studs/s = 0,00 stud de desvio. A causa era a curva da arma valendo correndo na
  DIAGONAL; agora só A ou D puro (`FootballClient.movimentoDoChute`). A hitbox do
  jogador não desvia: a bola não colide com "Players" e fica sem colisão até sair do
  corpo (`startKickClearance`). Se voltar a acontecer, pergunte quais armas a pessoa
  tinha e se estava andando.
- Painel de debug em ABAS (Armas primeiro, Hissatsu, Testes, Flow/Gol), altura pela tela,
  busca por nome — pedido de um amigo do usuário com tela menor.

## Lições da v122 (não repetir)
- `emissor(...)` com `Taxa = 0` nasce com `Enabled = false`: quem controla `Rate` depois
  tem que ligar `Enabled = true` (as estrelas do portal da Queda NUNCA apareceram por isso).
- Textura de partícula inexistente (ex.: `TEX.Brilho`, que não existe) = partícula
  invisível. Confira a chave na tabela `TEX` (Fogo, Faisca, Fumaca, Floco, Bolha, Estrela, Nuvem).
- `Beam` com `FaceCamera` é sempre uma FAIXA chata — pra "cilindro/tubo" use peça
  `Shape = Cylinder` (eixo X) com ForceField nas cascas.
- Efeito de voo que começa no impacto da cutscene: a bola ainda está no ponto da CENA (lá
  no alto); marque a origem quando ela ganhar velocidade de verdade.
- Imagem quadrada na tela (`RelativeXX`) girando: o canto da tela fica a ~0,57·largura do
  centro — abaixo disso os cantos abrem.
- R6 sem joelho: "perna parada" = quadril compensando o `Root` (e o R6 encolhe quadril
  pra frente ×0.7 no `adaptarR6`).
- BallController continua no limite de 200 locals: estado novo vai em `_G` (ex.:
  `_G.VooCurvaInicial`).

## Arquivos-chave
- `ServerScriptService/BallController.legacy.luau` (bola, chute, posse, armas ativas;
  NO LIMITE de 200 locals no topo — local novo só dentro de `do ... end` ou `;(function() ... end)()`).
- `ServerScriptService/PulseController.legacy.luau` (hissatsus, cutscenes no servidor,
  barreiras), `InstinctController.legacy.luau` (armas/instintos, Flow), `MatchController`.
- `ReplicatedStorage/PulseInstinctData.luau` (dados de armas e hissatsus; DUAS cópias:
  Game e Lobby, sempre iguais), `FootballConfig.luau`, `Cosmeticos.luau` (2 cópias),
  `HissatsuCutscenes.luau`, `HissatsuEfeitos.luau`, `EfeitosDeGol.luau`.
- Cliente: `HissatsuCutsceneClient`, `ArmasVFX`, `HissatsuVFXClient`, `MusicClient`,
  `CosmeticosClient`, `GKInput`, `FootballClient`.
