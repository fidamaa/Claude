---
name: animacao-roblox
description: Criar e ajustar animações e cutscenes por código no jogo de futebol Roblox (place Game) — poses por junta, ações do AnimadorProcedural, cutscenes de Hissatsu com câmera e VFX de fogo/partículas, e como validar sem depender de screenshot. Use sempre que o pedido envolver animação de personagem, cutscene, pose, movimento de corpo ou efeito visual de técnica.
---

# Animação e cutscene por código (place Game)

Este jogo NÃO usa assets de animação nos personagens. Tudo é pose calculada
por código e escrita nas juntas, em todo cliente. Antes de mexer, entenda as
três peças:

| Peça | Arquivo | Papel |
|---|---|---|
| Biblioteca de poses | `ReplicatedStorage/AnimacoesProcedurais.luau` | Dados e funções puras: locomoção, preparo do chute, ações (quadros-chave) |
| Animador | `StarterPlayerScripts/AnimadorProcedural.local.luau` | Aplica a pose em todo corpo visível (jogadores, `GKBot_*`, fantasmas do replay) |
| Cutscenes | `ReplicatedStorage/HissatsuCutscenes.luau` + `StarterPlayerScripts/HissatsuCutsceneClient.local.luau` + `playHissatsuCutscene` em `PulseController` | Coreografia compartilhada, câmera, VFX; o servidor congela o jogo e solta o chute no último quadro |

Chave geral: `Config.ANIMACAO_PROCEDURAL` (true). O servidor não toca asset:
`playAnimation` no `BallController` traduz o ID do Config pro NOME da ação
(`Kick`, `Dribble.Left`, `GKDive.Up`...) e avisa todos os clientes
(`Remotes.AcaoAnimada:FireAllClients(model, nome, duração, params)`). Pra
quem não é jogador (goleiro bot) use `_G.AnimarAcao(model, nome, duração)`.

## Convenção de ângulos (validada no avatar)

Graus, no espaço da peça-PAI da junta. `Vector3(rx, ry, rz)`.

- Quadril/ombro: `rx+` = membro pra FRENTE; `rz+` abre pro lado (DIREITO
  positivo, ESQUERDO negativo). Braço por cima da cabeça = ombro `rz ±170`.
- Joelho: negativo dobra. Cotovelo: positivo dobra. Tornozelo: `rx+` ponta
  pra cima.
- `Root` (corpo inteiro, pivô no quadril) e `Waist` (tronco): `rx+` inclina
  pra TRÁS, `rx-` pra frente; `rz-` tomba pra DIREITA.
- `Neck`: `rx+` olha pra cima.
- `RootPos`: deslocamento do quadril em studs (agachar, deitar, quicar).
- Juntas: Root, Waist, Neck, R/LShoulder, R/LElbow, R/LWrist, R/LHip,
  R/LKnee, R/LAnkle. Em R6 não existem Waist/joelho/cotovelo/pulso/tornozelo.

**Armadilha de soma de ângulos:** a flexão do quadril é RELATIVA ao tronco.
Com o corpo deitado pra trás (Root rx +62), coxa rente ao chão é ~28 de
flexão (90 − 62), não 85. Sempre desconte a inclinação do Root ao posar
pernas e braços de corpo tombado.

`Anim.Espelhar(pose)` troca direita/esquerda (inverte ry/rz): faça a
versão Direita e gere a Esquerda.

## Adicionar uma ação nova

1. Em `AnimacoesProcedurais.luau`:
   ```lua
   Anim.Acoes["MinhaAcao"] = {
       Duracao = 0.6, EntradaSeg = 0.04, SaidaSeg = 0.14,
       -- Loop = { inicio, fim }  (opcional, repete esse trecho)
       Quadros = function(params) return {
           { 0.00, {} },                       -- {} = pose neutra
           { 0.20, { Root = V(-10,0,0), RHip = V(60,0,0), RKnee = V(-40,0,0) } },
           { 0.60, {} },
       } end,
   }
   ```
2. Disparar: com ID no `Config.ANIMATIONS`, o `playAnimation` já traduz.
   Sem ID: `playAnimation(player, qualquerId, nil, duracao, true, nil, nil, "MinhaAcao")`
   (último parâmetro = nome da ação) ou `_G.AnimarAcao(character, "MinhaAcao", duracao)`.
3. A duração pedida pelo servidor ESTICA/ENCOLHE a ação (os quadros são no
   relógio da `Duracao` original).

## Cutscene de Hissatsu nova (o Tornado de Fogo é o modelo)

1. **Pesquise antes de posar.** Abra o vídeo da técnica no navegador
   embutido, pause com `document.querySelector('video').currentTime = X` e
   tire screenshot quadro a quadro (a cada 0.3–0.5s). Descreva cada fase
   (quem gira, pra que lado, quando tomba, onde a bola está) ANTES de
   escrever número. O usuário corrige detalhes que não estão na descrição
   escrita da técnica (ex.: "gira no ar, tomba desde a decolagem, gira ao
   contrário").
2. Em `HissatsuCutscenes.luau`, crie `Cutscenes.NomeDaTecnica` com:
   `Duration`, `ImpactTime`, `Phases`, `RootPosition(t)`, `RootCFrame(t)`
   (yaw + roll), `BallPosition(t, ballStart)`, `BallSpin(t)`, `KickPoint`,
   `KickContactDir`, `Pose(t)`, `Camera(t, rootPos, ballPos)`.
3. No dado da Hissatsu (`PulseInstinctData.luau`, nas DUAS cópias, Game e
   Lobby): `Cutscene = "NomeDaTecnica"`.
4. O QTE roda DURANTE a cutscene (janela encurtada pra caber); o chute sai no
   último quadro com o resultado. Não mude isso sem pedido.
5. **Contato pé-bola:** meça onde o pé fica no `ImpactTime` (congele com o
   atributo de depuração, leia `LeftFoot.Position` no espaço inicial) e ponha
   `KickPoint` a raio da bola (0.85) + 0.3 do pé. O cliente ainda corrige ao
   vivo pelo pé real.
6. VFX que agradaram: rastro com DUAS camadas (halo largo transparente +
   miolo claro), `FaceCamera = true`, textura `rbxasset://textures/particles/fire_main.dds`
   esticada; brasas (partículas pequenas que sobem e somem); espiral
   orbitando no REFERENCIAL DO CORPO (`root.CFrame.Rotation`); no chute as
   fitas convergem num rastro só na perna; impacto com flash, onda de
   choque, linhas de velocidade e "impact frame" (contraste estourado 0.07s);
   bola incandescente (Highlight laranja) que segue em chamas no voo.
   `LightEmission` do fogo ~0.8 (1.0 esverdeia em cima da grama, 0.45 fica
   marrom).

## Motor V2 (todas as cutscenes depois do Tornado)

O Tornado de Fogo tem código próprio no cliente (aprovado pelo usuário: não
mexer). As outras seis (Raio Um, Sumiço, Impulso de Maré, Fúria Glacial,
Zona Morta, Galáxia) usam `Motor = "V2"` → `tocarCutsceneV2` no
`HissatsuCutsceneClient`, que é genérico. Pra uma técnica nova:

1. Coreografia em `HissatsuCutscenes.luau` com os campos do Tornado + 
   `Motor = "V2"`, `Efeitos = "<Nome>"`, `KickFoot`, `Tema` (cores do
   letreiro/flash/correção de cor). Opcionais: `BallVisible(t)`,
   `Clones = { Quantidade, Cor, CFrame(i,t), Pose(i,t), Alpha(i,t) }`
   (sombras do chutador), `ColarNoPe = false` (bola não gruda no pé).
2. Efeitos em `ReplicatedStorage/HissatsuEfeitos.luau`:
   `E.<Nome>(ctx)` devolve `{ Quadro(t, dt, s), Impacto(s), Voo(ball, dur) }`.
   `ctx` tem `Pasta` (destruída no fim), `Inicio`, `Mundo(p)`, `Root`,
   `Character`, `Clones`, `ChaoY` (gramado medido), `TamanhoBola`,
   `DirecaoChute`, `Flash(cor, transp, tempo)`, `Tremer(forca, dur)`.
   `s` tem `BolaMundo`, `BolaLocal`, `PePos`, `BolaVisivel`, `ImpactoFeito`.
   Primitivas prontas: `Emissor`, `Rastro`, `RastroDuplo` (halo + miolo),
   `NovoRaio` (eletricidade em zigue-zague), `Onda` (onda de choque).
3. **Chão calibrado:** o quadril de cada avatar fica numa altura diferente
   (medido 3.47 acima do gramado no avatar de teste; o Tornado supõe 2.9). O
   cliente mede o gramado e chama `Cutscenes.Calibrar(chaoY, raioBola)`; tudo
   que apoia no chão usa `CAL.Chao`/`ctx.ChaoY` (registre o recálculo em
   `recalculos`). O servidor não calibra — use isso só onde meio stud no
   fim não importa.
4. A bola gruda no pé de chute pela diferença entre `BallPosition(ImpactTime)`
   e o contato real (não pelo `KickPoint`), a partir de `Phases.Kick[1] - 0.15`.

## Validar SEM depender de screenshot

A tela do PC do usuário pode estar bloqueada: aí `screen_capture` dá timeout
e `RenderStepped` NÃO roda. Então:

- **Meça.** No Client: posição das partes em relação ao `HumanoidRootPart`
  e ao chão (raycast pra baixo), altura da parte mais baixa (nada abaixo de
  -0.05), para onde aponta o membro. Dispare ações pelo SERVIDOR com
  `task.delay` e meça no CLIENTE (a pose é local, o servidor não vê).
- **Congele/desacelere a cutscene:** atributos no LocalPlayer
  `CutsceneDebugT = segundos` (congela) e `CutsceneDebugSlow = 0.2` (câmera
  lenta). Rastro só aparece em movimento: congelado ele some ou vira reta.
- **Diagnóstico do animador:** `LocalPlayer:SetAttribute("AnimadorDebug", true)`
  → cada modelo animado ganha o atributo `AnimDbg` (R15, juntas, velocidade,
  no chão, goleiro, pose do Root, correção de chão, ação).
- **Rodar a cutscene inteira com a tela bloqueada:** atributo
  `CutsceneDebugHeartbeat = true` no jogador → o motor V2 roda no Heartbeat.
  Bateria usada: o SERVIDOR agenda os disparos (`task.delay` ~15s, porque
  cada chamada do MCP leva ~10s) e grava `TesteNome`/`TesteHorario` no
  workspace; o CLIENTE já fica esperando e amostra todo Heartbeat: menor
  folga ao gramado (nada abaixo de ~-0.1), distância pé→superfície da bola
  no `ImpactTime` (~0.3 = meia espessura do pé = encostou), se a pasta de
  FX sobrou no fim. Resultado final das seis: folga ≥ -0.09, contato 0.12–0.32.
- **Pesquisa de vídeo com o navegador oculto não funciona:** o vídeo não
  decodifica (quadros repetidos), canvas não aparece no screenshot e a wiki
  bloqueia data:/fetch. Use a seção "Usage" da wiki (texto) e deixe o quadro
  a quadro pra quando o usuário estiver na frente do PC.
- **O `_G` do MCP (execute_luau) é SEPARADO do `_G` do jogo.** Não dá pra
  pausar o animador nem chamar `_G.AnimarAcao` pelo MCP — use atributos e
  `Remotes.AcaoAnimada:FireAllClients` direto.

## Armadilhas do Roblox já resolvidas (não desfazer)

- **Personagem do jogador = juntas novas (AnimationConstraint).** A pose vai
  no `Transform` (conjugado pela rotação de repouso). Mexer só no
  `Attachment0` não recalcula a junta com o corpo ancorado; escrever o
  `Transform` força.
- **Goleiro bot = R6 (Motor6D) com molde POSADO.** O `C0` dos ombros do
  molde vem com os braços abertos; o repouso certo vem do `C1`. No Motor6D a
  pose vai no `C0` já descontando o `Transform` que o motor impõe.
  `HipHeight = 0` no R6: altura do chão = meio tronco + perna.
- **Nenhuma outra animação pode tocar.** `StarterCharacterScripts/Animate` é
  um script VAZIO de propósito (substitui o Animate do Roblox e impede o
  pacote de animação do avatar — que só aparece no jogo publicado e
  "embolava" com as nossas). O original está em `ServerStorage.Backup_Animate`.
  O animador também para toda AnimationTrack a cada quadro.
- **Correção de chão automática:** se a parte mais baixa fura o gramado, o
  animador sobe o corpo; mesmo assim, poses de chão devem ficar perto certo
  (medido: mergulho caído RootPos -1.35, carrinho -1.35, deitado -1.75).
- A cutscene pausa o animador do chutador (`_G.AnimadorPausado[character]`).

## Referências usadas (cite e use ≥2 por movimento novo)

- Marcha: quadril +30/−10, joelho ~15 na carga e ~60 no balanço, 60% apoio
  (umich MVS330; PM&R KnowledgeNow "Biomechanics of Normal Gait").
- Corrida/sprint: quadril até ~55, joelho até ~125 no meio do balanço,
  cotovelo ~90, braço oposto à perna (Physiopedia "Running Biomechanics";
  SimpliFaster ALTIS Kinogram).
- Chute de peito do pé: backswing com quadril estendendo ~30 e joelho
  dobrando ~100, cocking, extensão do joelho no contato, follow-through
  (JSSM 2007; PMC5154722).
- Mergulho do goleiro: impulso com a perna CONTRÁRIA, passo lateral com a do
  lado, saída ~45°, corpo esticado (Tandfonline 2018 "Kinematic and kinetic
  analysis of the goalkeeper's diving save"; PMC7739716).
- Carrinho: centro de gravidade baixo, perna da frente esticada com ponta pra
  cima, a de trás dobrada, mão de apoio (Wikipedia "Sliding tackle"; Soccer
  Coach Weekly).
- Cabeceio: arqueia pra trás, trava o pescoço, testa, braços abertos
  (PMC6084627; SoccerPilot "Header - Basics").
- Hissatsus (Inazuma Eleven Wiki, seção "Usage"): Inazuma 1gou (Raio Um),
  Kamikakushi (Sumiço), Tsunami Boost (Impulso de Maré — mais o vídeo do
  Victory Road), Freeze Shot (Fúria Glacial), Death Zone (Zona Morta), The
  Galaxy (Galáxia). Resumo de cada uma no comentário da coreografia.

## Fluxo de entrega

Editar no disco → `balance_check.py` → Studio do Game via HTTP local
(`python -m http.server 8765` na pasta do projeto; `HttpService:GetAsync`
+ `loadstring` + backup em `ServerStorage.Backup_Scripts_vNN` +
`ScriptEditorService:UpdateSourceAsync`; o Studio precisa estar em Edit,
não em Play). O Lobby sincroniza sozinho do disco. Comentários em português,
com `⚠️ vNN` e a frase do PEDIDO.
