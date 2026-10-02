---
name: flow-cutscene
description: Fazer ou refazer a cena de ativação de um FLOW (Isagi, Bachira, Rin, Barou...) no padrão do Flow do Isagi v119b — coreografia de ~11.5s baseada em vídeo de referência, poses R6, câmera que segue a cabeça de verdade, efeitos por fase e o efeito do Flow na partida. Use quando o pedido for "faz o Flow do X igual ao do Isagi".
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
   peças/partículas presas ao corpo com `LockedToPart` em volta do corpo
   inteiro (não saindo de um ponto pra trás).
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
