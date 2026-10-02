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
2. **Quadros a cada 0,1s** (PyAV, folhas 4x5) e a descrição por escrito.
3. **Cena de 10-12s** na ordem da história (passos abaixo), colorida.
4. **A AURA com sentido do anime** (seção seguinte), com imagem própria.
5. **Efeito do Flow na partida** com o mesmo motivo da aura.
6. Conferir balanço `()`/`{}`/`[]`, commitar numa branch, e anotar no commit o
   que o Claude local precisa fazer (subir imagens, testar no Play).

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
| Isagi | Pecas | ✅ feito: peças de quebra-cabeça (6 formatos) em volta do corpo, cérebro e olhos do "gênio" |
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
   - Olhos: Attachment 0.3 stud à frente do rosto (na frente da franja) +
     Part Neon pra "olho aceso" + billboard pro desenho — **nunca
     AlwaysOnTop** (some) e **desligue o Fill do Highlight** quando o billboard
     tiver que aparecer.
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
