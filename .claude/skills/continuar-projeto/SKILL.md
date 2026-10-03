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
- Nome do arquivo define a classe: `X.luau` = ModuleScript, `X.legacy.luau` =
  Script, `X.local.luau` = LocalScript. (O painel de debug virou ModuleScript por
  causa disso e "sumiu" — corrigido pra `.local.luau`.)
- Pra conferir Studio x disco: some um hash por script dos dois lados (exemplo
  usado: `scratchpad/hash_disco.py` + um execute_luau com o mesmo hash).
- `execute_luau` NÃO pode `require` módulo do jogo, disparar remote nem usar
  HttpService; o `_G` dele é separado do jogo. Pra testar: um gancho temporário
  `--TESTE_INICIO ... --TESTE_FIM` num script do servidor que escuta um atributo do
  `workspace`; tire antes do commit. Cutscene: atributo `CutsceneDebugT` no
  LocalPlayer congela o tempo.
- O usuário pediu: NÃO testar no Play sem ele pedir ("deixa que eu testo"). Termine,
  avise, e espere ele aprovar antes de partir pro próximo item.
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
6. **Lista da noite de 03/10 (v122)** — o usuário deixou o Studio aberto. Ordem: FLOW
   primeiro (testar com screenshots e só mandar quando estiver MUITO bom), depois o resto.
   Ver a seção "Lista da noite" abaixo; marcar ✅ conforme fizer.

## Lista da noite (v122) — palavras do usuário resumidas
FLOW do Isagi:
- F1 Rever o vídeo `E:\O Gênio da Adaptabilidade rBlueLock.mp4` coisa por coisa (quadros a
  0,1s em `scratchpad/flow_isagi/q`) e conferir se falta algo; melhorar o que der e
  anotar na skill `flow-cutscene`.
- F2 Braços da cena final: "estão muito pra cima e muito pra frente; o OMBRO, o braço
  inteiro com o ombro, tem que estar mais pra TRÁS".
- F3 Espiral: "ainda está cortando; é pra começar a aparecer na tela e ir aumentando e
  diminuindo o campo de visão, AINDA no cara — você ainda vendo o jogador correndo".
- F4 Corrida do Rin (e corrida em geral) mais FLUIDA — pesquisar ciclo de corrida.
- F5 Mais efeitos quando ele levanta.
- F6 Brilho BRANCO do olho mais forte; a íris girar mais rápido ainda.
- F7 O jogador se ARREPIAR.
DEPOIS:
- G1 Chute que vai pra esquerda/direita sozinho (colega). Curva do Rin: "vou pro lado
  segurando o botão, solto, e é pra curvar" — só com A/D; voltar pra 24° mas virar de verdade.
- G2 GK: dash pra frente e dive pro lado levantam mais DEVAGAR; punição por errar o dive;
  dive pode ir um pouco mais longe.
- G3 Tornado de Fogo (e Dragão / quem usa): na subida abrir as pernas devagar; no chute só a
  perna do chute mexe, a outra vai pra trás (pose de bicicleta). (Pedido explícito —
  pode mexer no Tornado nisso.)
- G4 Queda Celestial: o rastro dura mais; é um CILINDRO (não cone) com um universo dentro
  (planetas, estrelas saltando) sem sair do cilindro.
- G5 Bug: chute lendário (Dragão) contra defesa lendária (Punho da Justiça) → força caiu
  de 180 pra 0 na hora.
- G6 Chutes em conjunto (menos a Zona Morta): companheiros mais LONGE do jogador.
- G7 Chutes: só UM pé se move (conferir as poses/"estátuas" de chute).
- G8 Fúria Glacial: não cair no chão — dar um MORTAL e chutar; a bola faz uma leve curva
  e depois vai 100% reto na direção mirada.
- G9 Hissatsus aéreas: de longe a mira sobe demais — baixar/alinhar a mira.

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
