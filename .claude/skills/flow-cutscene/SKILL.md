---
name: flow-cutscene
description: Fazer ou refazer a cena de ativação de um FLOW (Isagi, Bachira, Rin, Barou...) no padrão do Flow do Isagi v119b — coreografia de ~11.5s baseada em vídeo de referência, poses R6, câmera que segue a cabeça de verdade, efeitos por fase e o efeito do Flow na partida. Use quando o pedido for "faz o Flow do X" (mesmo sem mais detalhes) — inclui a aura com sentido do anime e imagens próprias.
---

# Cena de Flow (padrão Flow do Isagi)

O exemplo completo e aprovado é o **Flow do Isagi** — leia os dois antes de
escrever qualquer coisa:

- coreografia: `ReplicatedStorage/HissatsuCutscenes.luau`, bloco
  `🧠 FLOW DO ISAGI` (`Cutscenes.Flow_Isagi`)
- efeitos e câmera dos closes: `ReplicatedStorage/HissatsuEfeitos.luau`,
  `function E.FlowIsagi(ctx)` (e `E.PecasEmVolta`, `placaFlow`)
- quem dispara: `_G.TocarCenaFlow` em `ServerScriptService/PulseController.legacy.luau`
  (congela todo mundo, manda `HissatsuCutscene` pra todos os clientes)
- quem toca: motor V2 em `StarterPlayerScripts/HissatsuCutsceneClient.local.luau`
  (`tocarCutsceneV2`) — normalmente NÃO precisa mexer nele
- efeito do Flow DURANTE a partida (aura/olhos/peças): `ligarFlowNoCorpo`
  em `StarterPlayerScripts/CosmeticosClient.local.luau`
- dados do Flow (cor, personagem, atributos): `C.Flow` em
  `ReplicatedStorage/Cosmeticos.luau` (e a cópia igual em `Lobby/ReplicatedStorage`)

Leia também as skills `animacao-roblox` (convenção de ângulos, motor V2) e
`particulas-roblox` (texturas prontas, armadilhas de billboard/partícula).

## Quando o pedido é só "faça o Flow do X"

O usuário quer poder pedir só isso e receber o MESMO processo do Isagi, sem
precisar explicar de novo. Então, sozinho:

1. **Achar o vídeo de referência.** Se o usuário não mandou: procure a cena do
   Flow/despertar do personagem no YouTube com o yt-dlp
   (`python -m yt_dlp --no-update --flat-playlist --print "%(id)s | %(duration)s | %(title)s" "ytsearch12:<personagem> flow blue lock"`).
   Atualize antes (`python -m pip install --user --upgrade yt-dlp`) — versão
   velha dá 403. Baixe só o vídeo (`-f "bv*[height<=720][ext=mp4]/18"`).
   Reddit bloqueia download automático (peça o arquivo ao usuário). Na dúvida
   entre dois clipes, mostre a folha de contato e pergunte qual é.
2. **Quadros a cada 0,1s** (PyAV, folhas 4x5) e a descrição por escrito —
   **a tabela de planos** (ver "Por que errei no Isagi" abaixo).
3. **Cena de 10-12s** na ordem da história (passos abaixo), colorida.
4. **A AURA com sentido do anime** (seção seguinte), com imagem própria.
5. **Efeito do Flow na partida** com o mesmo motivo da aura (e o olho do Flow
   no rosto o Flow inteiro, se o personagem tiver olho especial).
6. **A música do Flow** (seção "Música").
7. Conferir balanço `()`/`{}`/`[]`, commitar numa branch, e anotar no commit o
   que o Claude local precisa fazer (subir imagens/áudio, testar no Play).

## Por que errei no Isagi (o usuário teve que corrigir 3 vezes) — NÃO REPETIR

Causa de fundo: eu olhava as folhas de quadros, entendia "a ideia" e depois
**inventava** a montagem. Os detalhes que o usuário cobrou estavam TODOS no
vídeo. Regra: antes de codar, escreva a TABELA DE PLANOS e confira cada linha
contra os quadros:

| tempo no vídeo | o que aparece | câmera (corta? continua? zoom?) | transição pro próximo | onde fica o efeito (na frente/atrás/no rosto/na tela) |

Erros concretos (cada um virou regra):
1. **Ordem e "quando"**: o olho branco acende AINDA NO CHÃO (5,9s), antes do
   Rin. Eu acendi depois. → anote em que quadro cada efeito COMEÇA.
2. **Corte onde o vídeo transforma**: no vídeo o olho branco VIRA o olho do
   Flow e a câmera vai direto pro olho. Eu cortei pra outra cena. → se no vídeo
   não tem corte, a câmera NÃO corta: a câmera da cena seguinte começa
   exatamente onde a anterior terminou (pegue a última posição da câmera base).
3. **Efeito de rosto flutuando**: billboard "na frente do cabelo" fica falso.
   → olho/marca de rosto vai NO ROSTO (placa colada na cabeça com SurfaceGui,
   ver `E.OlhosFlow`), nos DOIS olhos, deixando a franja passar na frente.
4. **Inventar imagem pior**: fiz uma "máscara" que não existia no pedido. → o
   olho final é a MESMA arte aprovada; não crie variação sem pedir.
5. **Lado do efeito**: riscos de esforço ficam ATRÁS do personagem (a câmera
   está na frente). → anote na tabela "na frente/atrás".
6. **Ponto de vista**: "a visão dele" = câmera NOS OLHOS dele olhando o outro
   personagem (que já está na frente, câmera lenta, fundo branco) — não uma
   câmera seguindo o outro.
7. **Escurecer pela metade**: a espiral deixava branco aparecendo. → quando o
   vídeo vai pro preto, vai pro preto TOTAL (fundo escuro por baixo da arte).
8. **Braço R6 entrando no tronco**: braço é reto; com |rz| pequeno ele
   atravessa o corpo (pior com o tronco inclinado). → |rz| ≥ 20 parado, ≥ 40
   em movimento/pra trás; movimento EXAGERADO pra fora. Meça a direção do
   braço (`-Arm.CFrame.UpVector` no espaço do HRP) e olhe de frente E de lado.
9. **Pose certa, câmera errada**: o dash com braços pra trás de FRENTE parecia
   "braços abertos". → escolha a câmera que mostra a pose (perfil/3/4).
10. **Companheiro "aleatório"**: sem colega de time ele virava uma sombra do
    próprio jogador. → reserva: qualquer jogador → goleiro bot.
11. **Transição de tela que "corta"** (v122): a arte da espiral estava em
    escala tão grande que o buraco ficava FORA da tela e depois fechava de uma
    vez. → calcule a geometria: imagem quadrada pela LARGURA (`RelativeXX`),
    canto da tela a ~0,57·largura do centro (16:9); buraco da EspiralBorda tem
    raio 0,34·escala. Começar em ~1,9 (traços já nos cantos) e apertar até
    ~1,2; abaixo de 1,2 o quadrado girando abre os cantos. Vinheta em
    `RelativeXY` nunca abaixo de 1,02 (aparece o retângulo da imagem). O miolo
    só fecha quando o personagem do fundo some.
12. **Personagem lavado no fundo branco** (v122): neblina + correção clara deixam
    o companheiro quase branco. → Highlight com véu escuro (Fill ~0,35, cor
    azul-escura) vira silhueta forte, como no anime.
13. **Partícula de "risco" torta** (v122): o `emissor` sorteia Rotation 0–360.
    → riscos/linhas: `Rotation = NumberRange.new(0)` e `RotSpeed` 0.
14. **Revisão no Studio** (v122): Play + gancho de teste no servidor
    (`workspace:SetAttribute("TesteFlow", ...)`) + `CutsceneDebugT` no cliente
    + `screen_capture` em cada fase; mudar o disco exige PARAR o Play (o sync
    só entra em Edit) e dar Play de novo. Remover o gancho antes do commit.

15. **Conferir no Studio, não às cegas** (v124, Flow do Shidou feito na nuvem):
    tire quadros do vídeo a cada 0,2s (PEDIDO do usuário) e screenshots da cena nos
    mesmos planos. Erros que só apareceram assim:
    - cabeça R6 = SpecialMesh 1.25x: olho na face da PEÇA fica ENTERRADO (some);
      `FlowCenaOlhos` agora usa a escala da malha (olhos em x ±0.055, y 0.25);
    - close de rosto com a câmera pela inclinação da CABEÇA mostra o topo do cabelo —
      use a frente do CORPO (horizontal); franja do avatar tampa o rosto: cabelo
      semitransparente desde o close do ROSTO;
    - palco escuro + luz desligada = rosto preto; luz forte rosa = rosto rosa: nos
      closes, luz fraca quase branca;
    - brilho de tela (ImageLabel radial) muito grande vira tela CINZA.
16. **Falas do personagem** (v124): baixe o vídeo da cena, separe a voz com `demucs`
    (`python -m demucs --two-stems vocals`, já instalado), transcreva com
    `faster-whisper` (`word_timestamps=True`) e confira quem fala pela legenda do
    vídeo. Coloque cada fala no plano da cena (abaixe a música por baixo, 0.5x).
    Modelo: `_upload/Flow_Shidou_Cena.mp3` (falas + trilha "Big Bang Drive Theme",
    a explosão da trilha em 68,6s cai no chute da cena).

## A aura tem que ter SENTIDO, igual ao anime

PEDIDO do usuário: "sempre que for fazer uma aura precisa ter sentido igual do
anime, com imagens próprias de aura se necessário (Isagi = quebra-cabeça)".
Nada de partícula genérica (faísca/brilho) como aura principal: a aura conta
QUEM é o personagem. Pesquise o simbolismo do Flow dele no anime/mangá (wiki de
Blue Lock, a própria cena) antes de desenhar, e gere as texturas com a skill
`particulas-roblox` (várias imagens diferentes, como as 6 peças do Isagi).

`Tema.Motivo` atual de cada Flow (`C.Flow` em Cosmeticos.luau) — ponto de
partida, confirme no anime:

| Flow | Motivo | O que a aura deve mostrar |
|---|---|---|
| Isagi | Pecas | ✅ feito: peças de quebra-cabeça (6 formatos) em volta do corpo, a cabeça se desfazendo em peças escuras, a ÍRIS de quebra-cabeça no rosto (nos dois olhos, também na partida) |
| Bachira | Monstro | o "monstro" dele (sombra preta com olhos amarelos e dentes, garras) junto do corpo |
| Nagi | Penas | o gênio preguiçoso: penas brancas flutuando leve, calma |
| Chigiri | Petalas | velocidade/rosa: pétalas e rastro rosa-vermelho correndo |
| Kunigami | Chamas | o "herói": chamas laranja fortes, brilho de super-herói |
| Reo | Espelhos | o camaleão que copia: cacos de espelho / reflexos roxos |
| Aiku | Fantasma | o defensor "fantasma": silhuetas translúcidas, névoa cinza-azulada |
| Barou | Coroa | o REI: coroa dourada (já existe sprite da coroa — ver particulas-roblox), aura de rei |
| Shidou | Explosao | o "demônio" do big bang: explosões rosa e amarelas, estrelas |
| Sae | Rosas | o mágico do meio-campo: rosas vermelhas |
| Rin | Agua | destruição/água escura verde-azulada: ondas, gotas, olhos verdes |
| Kaiser | RosaAzul | o imperador: rosas azuis, espinhos, coroa/tatuagem de rosa |

Regras de como a aura aparece (vale pra cena e pra partida):
- presa ao corpo (`LockedToPart`, `Shape = Box`, `Volume`) e EM VOLTA do corpo
  inteiro — nunca saindo de um ponto e indo pra trás quando ele anda;
- várias imagens diferentes do mesmo motivo (não uma só repetida);
- olhos acesos na cor do Flow (Part Neon à frente do rosto + desenho em
  billboard sem AlwaysOnTop).

## Música do Flow (cada Flow com a sua)

PEDIDO: "uma soundtrack boa: a música tema de cada Flow; enquanto ela toca as
outras somem (fade in no começo, fade out no fim); no gol ela abaixa um pouco".
- Playlist de referência (Blue Lock OST):
  `https://www.youtube.com/playlist?list=PLjOrR-jW7I1bwHvCOn7j53PcQNdYhzYri`
  (liste com `--flat-playlist --print`). Já tem faixa com nome de personagem
  (BACHIRA, CHIGIRI, RIN, MEGURU, NAGI, REO, Awakening of BAROU...). O Isagi usa
  **Puzzle** (pedido do usuário).
- Baixe só o áudio (`-f bestaudio[ext=m4a]`), ache a "batida forte" (envelope de
  volume com PyAV, ver `cortar_audio.py` nesta pasta: `python cortar_audio.py entrada.m4a inicio duracao saida.mp3 fadein fadeout`) e corte o trecho
  pra batida cair no momento forte da cena (no Isagi: 14,3s da faixa = a pisada
  9,55s → começa em 4,75s). Duração = cena + Flow (25s) + folga (~39s), fade-out
  no fim. Salve em `_upload/` (fora do git).
- **Um áudio só por cena, já mixado** (PEDIDO: "não esquece a música e os efeitos
  sonoros"; no Isagi também a fala do Sung Jin-Woo, Solo Leveling 0:30): música +
  voz (com a música abaixando por baixo dela) + efeitos SINTETIZADOS em numpy
  (coração, baque, brilho, vento, cliques de peça, espiral, explosão — sem
  direito autoral), cada um no instante da coreografia. Modelo pronto:
  `mixar_cena_isagi.py` nesta pasta (troque a lista `eventos()` e os trechos).
  Confira desenhando a onda com marcas nos tempos (não dá pra escutar daqui).
- O MCP NÃO sobe áudio: o usuário sobe no Creator Hub e manda o ID; cole em
  `Musica = { Id = "rbxassetid://...", Volume = 0.6 }` no item do Flow em
  `C.Flow` (Cosmeticos, nas DUAS cópias).
- Quem toca: `MusicClient` (ouve `Remotes.HissatsuCutscene` "Flow_..." e para
  quando o atributo `FlowAtivo` do jogador some). Nada a mudar por Flow.

## Passo a passo

1. **Vídeo de referência, quadro a quadro.** Extraia quadros a cada 0,1s com
   PyAV (`av.open(...)`, folhas de contato 4x5) e descreva cada plano por
   escrito ANTES de codar: tempo no vídeo → o que acontece → câmera. Vídeo
   sempre mudo.
2. **Comprimir para 10-12s** (pedido do usuário) mantendo a ORDEM da história —
   o usuário reclamou quando a ordem ficou trocada. Cada plano precisa ser
   legível no Roblox: close de mão/punho no R6 não funciona (não tem dedos);
   close do rosto de baixo não funciona com cabelo grande (use perfil).
3. **Coreografia** (`Cutscenes.Flow_<Nome>`), copiando a estrutura do Isagi:
   `Motor = "V2"`, `Efeitos = "Flow<Nome>"`, `Duration`, `ImpactTime` (o
   "estouro" do Flow), `Phases` com nomes das fases + `Kick`/`Impact`,
   `SemTremidaImpacto = true` se o fim for close, `RootPosition/RootCFrame`,
   `Pose(t)`, `Clones` (personagens extras), `Camera(t, rootPos)` só pros
   planos abertos.
   - Interpolação: `samplePoseFluida` / `sampleFluido` (Catmull-Rom, já
     exportada como `Cutscenes.SamplePoseFluida`) — passa pelas poses sem
     parar; some respiração/tremor por cima em `Pose(t)`.
   - **Os jogadores são R6**: sem joelho/cotovelo (essas juntas são
     ignoradas). Braço e perna são RETOS. Direção do braço pela rotação do
     ombro: `d = (sen rz, −cos rz·cos rx, −cos rz·sen rx)` (no espaço do tronco,
     −Z é a frente). Ex.: braços em X na frente do nariz = Shoulder
     `{116, 0, ∓43}`; braços abertos = `{-10, 0, ±100}`.
   - Quadril do R6 (centro do tronco) em pé = 0; de quatro ≈ `CAL.Chao + 1.45`.
   - A flexão do quadril/ombro é RELATIVA ao tronco (tronco a −65° → coxa
     vertical com Hip +65).
   - Personagem extra de verdade (ex.: o Rin): `FI.CompanheiroAleatorio = true`
     faz o servidor sortear um companheiro do time; `Clones.Contorno` define o
     contorno. Sozinho no teste ele vira sombra da cor `Clones.Cor`.
4. **Efeitos** (`E.Flow<Nome>(ctx)` em HissatsuEfeitos): devolve
   `{ Quadro(t, dt, s), Impacto(s), CameraMundo(t) }`.
   - `CameraMundo(t)` devolve `CFrame, fov` em coordenadas de MUNDO pros closes
     — siga `head.Position`, `head.CFrame.LookVector`, pé, olhos de verdade
     (funciona com qualquer avatar). `nil` = usa a câmera da coreografia.
   - Tudo que for criado NO CORPO (emissor no torso, Attachment na cabeça,
     Beam) entra em `prender()` — senão sobra no jogador depois da cena.
   - Ambiente por fase: ColorCorrection própria na câmera, `salaEscura` como
     palco (branco/escuro/colorido), Highlight no corpo pra silhueta.
   - Olhos: o DESENHO do olho vai no rosto (`E.OlhosFlow`: placa soldada na
     cabeça, rente ao rosto, SurfaceGui com a íris nos dois olhos; a franja
     passa na frente). Brilho branco = Part Neon no olho + billboard de brilho
     com `StudsOffset = (0,0,0.25)` (puxado pra câmera, sem flutuar) — **nunca
     AlwaysOnTop** (some) e **desligue o Fill do Highlight** quando o billboard
     tiver que aparecer.
   - Zoom "pra dentro do olho": billboard/superfície somem ou pixelam com a
     câmera colada → pare a câmera a ~0.9 stud e faça o mergulho final com a
     MESMA imagem desenhada na TELA (ScreenGui com atributo
     `VisivelNaCutscene`), projetada no lugar do olho
     (`Camera:WorldToViewportPoint`) e crescendo até o miolo tomar a tela.
   - Efeitos de TELA (espiral, vinheta, branco/preto de transição): ScreenGui
     em `prender()`, `IgnoreGuiInset`, atributo `VisivelNaCutscene = true`
     (o motor esconde toda GUI sem ele).
   - Neblina "quase branca": `Atmosphere` densa durante a cena (guardar e
     devolver os valores) — partícula de névoa sozinha não esconde o fundo.
   - Palco com chão: o piso da `salaEscura` fica 0,2 acima do gramado → câmera
     baixa precisa ficar ACIMA dele (senão aparece a grama por baixo).
   - Cabelo semitransparente nos closes do olho (`LocalTransparencyModifier`
     nos acessórios) e devolver a 0 no fim.
   - Final COLORIDO (o usuário pediu cor, não P&B).
5. **Efeito do Flow na partida** (`ligarFlowNoCorpo`): siga o do Isagi —
   `if tema.Motivo == "<Motivo>" then ... end` chamando uma função do
   HissatsuEfeitos no estilo de `E.PecasEmVolta` (uma por motivo), com as
   imagens próprias do personagem presas ao corpo (ver seção da aura).
   Desligue os emissores no fim do Flow (o código já desliga tudo que estiver
   em `coisas`).
6. **Texturas novas**: gere e suba pela skill `particulas-roblox` (precisa do
   Studio pra `upload_image`; na nuvem, gere o PNG, deixe no repositório em
   `docs/texturas/` e anote no commit que falta subir — o Claude local sobe).

## Regras do projeto

- Comentários em português, com `⚠️ vNN` e a frase do PEDIDO do usuário.
- Arquivos `.luau` grandes: confira `()`/`{}`/`[]` balanceados antes de
  commitar. `BallController` está no limite de locals (não mexer aqui).
- NÃO mexer: Tornado de Fogo, hissatsus de goleiro, dribles/tackles aprovados.
- Commit com `Co-Authored-By: Claude ...` no fim, numa branch própria
  (ex.: `claude/flow-<nome>`), sem push em `main`.
- O que NÃO dá pra fazer fora do Studio (o Claude local faz depois): testar no
  Play, subir imagem, e copiar scripts de `StarterPlayerScripts` do Game pro
  Studio (essa pasta não sincroniza sozinha). ReplicatedStorage e
  ServerScriptService do Game, e o Lobby inteiro, sincronizam do disco.

## Flow que É um chute (padrão do Shidou, v124)

PEDIDO: "o flow dele vem com a ação de chute dele: pra onde a pessoa mirar o jogador
vai usar o flow e dar a cutscene pra chutar e ativar o flow ao mesmo tempo".
Pra um Flow assim (Shidou, e candidatos: Kaiser, Rin, Barou...):

- Na coreografia: `ChuteNoFlow = true`, `KickFoot`, `KickContactDir` (bola cola no pé de
  verdade a partir de `Phases.Kick[1] - 0.15`) e `BallPosition(t)` que, depois do
  `ImpactTime`, SAI pra frente (-Z = a mira; a cena já nasce virada pra mira). A bola de
  verdade é movida pela coreografia; o servidor a coloca em `BallPosition(Duration)`.
- Tudo é automático: o cliente manda a mira junto com a tecla do Flow
  (`InstinctModeInput` → `_G.HissatsuComputeAimPoint`); o `InstinctController` recusa
  (sem gastar o medidor) se não tiver a bola (`FlowPrecisaBola`);
  `_G.TocarCenaFlow(player, mira, aoFim)` gira a cena pra mira e, no último quadro,
  liga o Flow (`aoFim`) e DEPOIS dispara `_G.PulseExecuteShot` — os bônus do Flow já
  valem na força do chute. Nada a mudar por Flow: só `ChuteNoFlow = true`.
- Close que o vídeo tem e o Roblox não aguenta: esconda a bola nos closes de rosto/peito
  (`BallVisible`), senão ela tampa a câmera.
- NUNCA copie do vídeo cenas de óvulo/espermatozoide/biologia (o jogo é Roblox, o usuário
  pediu pra tirar): corte e anote na tabela de planos com ✂️ o intervalo cortado.

## Flow que é um DUELO (padrão do Aiku, v125)

PEDIDO: "a forma de ativar o flow do Aiku é se o inimigo estiver com a posse da bola perto dele
(ele precisa estar próximo da área)"; a cena é o embate: ele lê o adversário, tenta tirar a bola
(30%/70%), arranca a bola, dá a volta nele e fica com ela.
- Coreografia: `Duelo = true` e `Clones` com 1 personagem (o adversário de verdade, copiado pelo
  motor — o corpo real some durante a cena). `RootPosition`/`Clones.CFrame`/`BallPosition` no FIM
  são onde o servidor devolve cada um (Aiku, adversário caído, bola no pé do Aiku).
- Servidor (`PulseController`): `_G.FlowCondicao(player)` decide se pode ativar (adversário JOGADOR
  com a bola a ≤ 30 studs e o jogador a ≤ 45 studs da PRÓPRIA área; senão avisa
  `FlowPrecisaAdversario` e não gasta o medidor). `_G.TocarCenaFlow` vira a cena pro adversário e, no
  último quadro, `SetBallOwnerForced` passa a posse, o adversário fica atordoado 1s e o Flow liga.
- Olhos: esquerdo VERDE, direito AZUL (o azul é a MESMA íris com o matiz girado). `E.OlhosFlowAiku` e
  `E.AuraAiku` valem na cena e na partida (`CosmeticosClient`). Texturas em `docs/texturas/` (sem ID,
  a íris é desenhada com Frames).
- ÁUDIO que mantém o sentido: o vídeo é cortado no meio, então as falas são REORDENADAS num monólogo
  só (`mixar_cena_aiku.py`: cada fala com seu trecho do vídeo, ordem lógica, duck da trilha por
  baixo, a pausa da trilha caindo antes do DASH e a batida no DASH). A duração da cena nasce da soma
  das falas: ~22,6s. Se precisar encurtar, tire a 2ª e a 4ª fala (sem elas ~19s).
- Tempos das falas: ache pelo envelope de energia na faixa 500-3500 Hz (picos > -30 dB) cruzado com a
  legenda do vídeo; some 0,1s de folga e confira que não pegou a fala de outro personagem.
