# Flows — guia para o Claude da nuvem

Você vai fazer (ou refazer) a **cena de ativação de um Flow** neste jogo de futebol do
Roblox (Inazuma Eleven + Blue Lock). Leia este arquivo inteiro antes de mexer em
qualquer coisa. Ele resume o que já foi aprendido fazendo o **Flow do Isagi** e o
**Flow do Shidou**, os dois que o usuário aprovou.

Responda e comente sempre **em português**.

---

## 1. Antes de começar

**Leia nesta ordem:**

1. `.claude/skills/flow-cutscene/SKILL.md` — o processo completo do Flow, com os erros
   que já aconteceram e viraram regra.
2. `.claude/skills/animacao-roblox/SKILL.md` — convenção de ângulos, motor V2, R6.
3. `.claude/skills/particulas-roblox/SKILL.md` — texturas, partículas e billboards.
4. **O Shidou inteiro, que é o modelo mais novo:**
   - `ReplicatedStorage/HissatsuCutscenes.luau`, bloco `💥 FLOW DO SHIDOU`
     (`Cutscenes.Flow_Shidou`). A tabela de planos no topo mostra como documentar.
   - `ReplicatedStorage/HissatsuEfeitos.luau`, `function E.FlowShidou(ctx)`, com asas,
     sons, explosões, olhos e transições.

**Situação de cada Flow:**

| Flow | Situação |
|---|---|
| Isagi | ✅ aprovado (v119–v122) — modelo de aura com imagem própria (peças) |
| Shidou | ✅ aprovado (v126c) — modelo de cena de AÇÃO (chute), câmera e transições |
| Bachira, Nagi, Rin, Chigiri, Kunigami, Reo, Aiku, Barou, Sae, Kaiser | ⚠️ cenas antigas (v113–v119), simples — **precisam ser refeitas** no padrão Isagi/Shidou |

O usuário vai dizer qual Flow fazer. Faça um Flow por vez.

---

## 2. O que você NÃO consegue fazer na nuvem (e o que fazer em vez disso)

Você não tem o Roblox Studio nem o PC do usuário. O Claude local ("os olhos") faz
estas partes depois:

| Não dá na nuvem | O que você faz |
|---|---|
| Testar no Play, tirar screenshots | Escreva o código com cuidado; deixe pronto pra ser conferido. Nada de "testei". |
| Subir imagem (`upload_image`) | Gere o PNG e salve em `docs/texturas/<flow>/`. Use um id provisório (`rbxassetid://0`) e um comentário `-- FALTA SUBIR: docs/texturas/...` |
| Subir áudio | Gere o mp3 mixado e salve em `docs/audio/` (o `_upload/` local não existe na nuvem). Deixe `Musica` sem `Id`, com `-- FALTA SUBIR`. |
| Copiar `StarterPlayerScripts/*` pro Studio | Só edite; liste no HANDOFF quais arquivos dessa pasta mudaram. |
| Ver os arquivos de `_upload/` (vídeos/áudios antigos) | Baixe de novo do YouTube, se tiver internet. |

No fim, sempre escreva o **HANDOFF** (seção 8).

---

## 3. Regras que NÃO podem ser quebradas

- **Não mexer** sem pedido: hissatsus de goleiro, dribles e carrinhos aprovados, Tornado
  de Fogo, Flow do Isagi, Flow do Shidou.
- **Armas:** não renomear, não remover as que têm imagem e não criar armas novas.
- **Jogadores são R6:** sem joelho nem cotovelo, braço e perna são RETOS. Braço com
  `|rz| ≥ 40` em movimento (senão entra no tronco); parado, `≥ 20`.
- **Nada de óvulo/espermatozoide/biologia** das cenas do anime (é um jogo de Roblox). Corte
  e anote o trecho cortado na tabela com ✂️.
- **Áudio sem palavrão.** O Roblox RESTRINGIU o áudio do Shidou por causa de "クソども"
  (kusodomo). Transcreva tudo com `faster-whisper` e corte qualquer palavrão antes de
  entregar (sem cortar a frase no meio de um jeito estranho).
- **Vídeo de referência sempre mudo**, se for abrir no navegador.
- `ServerScriptService/BallController.legacy.luau` está no **limite de 200 locals** no
  topo: local novo só dentro de `do ... end` ou de função.
- Arquivos `.luau`: confira `()` `{}` `[]` balanceados antes de commitar (script na
  skill `roblox-studio-script-sync`, ou faça um equivalente).
- Comentários em português, com `⚠️ vNN` e a frase do PEDIDO do usuário entre aspas.
- `Cosmeticos.luau` e `PulseInstinctData.luau` existem em DUAS cópias (`ReplicatedStorage/`
  e `Lobby/ReplicatedStorage/`). Mude as duas iguais.
- Commit numa branch própria (`claude/flow-<nome>`), nunca em `main`. Mensagem termina com
  `Co-Authored-By: Claude ...`.
- **Ganchos de teste** (`--TESTE_INICIO` / `--TESTE_FIM`) nunca vão no commit.

---

## 4. Como o usuário quer as cenas (o que ficou BONITO)

Copiar o anime quadro a quadro **nem sempre fica bom no Roblox**. O usuário aprovou estas
adaptações; use o mesmo raciocínio:

1. **Sem close extremo no olho.** No anime a câmera entra no olho; no Roblox ficou
   estranho. O aprovado: **o corpo inteiro**, numa pose legal, **olhando pra cima**, câmera
   de cima (como se fosse a bola), e só os **olhos mudando**. Close do rosto só se for o
   rosto inteiro.
2. **Nada de corte seco.** Toda mudança (olho branco → íris do Flow, cor, palco) tem
   **transição**: clarão crescendo, a nova íris nasce pequena girando e cresce, a antiga
   apaga por baixo, pulso/anel de cor e flash suave (ver `obj.Transformar` em
   `E.OlhosFlow` e o bloco `pulsoOlho` no Shidou).
3. **Câmera lenta nos momentos certos, nunca no impacto.** Câmera lenta = a curva da
   coreografia anda devagar naquele trecho (ex.: Shidou no ar 9.25–9.75s, bola quase
   parada). O **golpe** (chute) é em velocidade normal, rápido. Depois do golpe vale uma
   **pausa** (bola parada ~0,5s) e aí a saída em velocidade máxima.
4. **Começo em primeira pessoa**, quando fizer sentido: a câmera nos olhos dele, olhando o
   que importa (Shidou: a bola caindo devagar lá em cima). Esconda a cabeça e o cabelo
   dele nesse plano (`LocalTransparencyModifier`).
5. **Animação EXAGERADA.** Pernas mais longe, braços jogados de um lado pro outro. Pose
   tímida parece parada no R6.
6. **Efeitos com sentido do anime e com imagem própria** (seção "aura" da skill). Ex.:
   Shidou tem **asas** de raio rosa saindo das costas (nascem quando a aura estoura, abrem
   mais no golpe). Isagi tem peças de quebra-cabeça de **vários formatos** (12), pequenas e
   numerosas.
7. **Som em cada momento importante, sem exagerar:** o golpe precisa de som **grave e
   forte** (chute + pancada + baque surdo, com `PlaybackSpeed` 0,55–0,85); algo surgindo
   (asas) ganha um som que combine (estouro elétrico); whoosh no salto e na saída. Sons
   prontos ficam no topo de `E.FlowShidou` (tabela `SOM`). Busque sons "Pro Sound Effects"
   (gratuitos, verificados).
8. **Explosão que combina com a música:** o estouro visual cai **no mesmo instante** da
   explosão da trilha (Shidou: 10,4s) — flash, ondas, anéis, explosõezinhas em volta
   escalonadas (`explosaozinha`).
9. **Olho do Flow aparece de verdade**: na cena e **durante o Flow inteiro na partida**,
   colado no rosto (`E.OlhosFlow`, placa com SurfaceGui), nos DOIS olhos, um pouco à frente
   do rosto (caras redondas engolem o olho). Ajuste `X`/`Y` por personagem (Shidou: X 0.085,
   Y 0.22).
10. **Aura na partida** (`ligarFlowNoCorpo` em `CosmeticosClient`): presa ao corpo inteiro
    (cada parte, `LockedToPart`, `Box/Volume`). Ex.: Shidou tem fogo roxo + faíscas.
11. **Iluminação no escuro:** palco/estádio escuro deixa o personagem preto. Ponha uma luz
    do lado da câmera; Highlight (contorno) na cor do Flow.
12. **Cena colorida** no fim (o usuário não quer P&B).

---

## 5. Armadilhas técnicas já resolvidas (não caia de novo)

- **Corpo inclinado na cena** (ex.: bicicleta, pitch > 70°): o Humanoid tombava no fim
  (`FallingDown`). Já resolvido no motor e no `SemLevantar`; não reative esses estados.
- **Bola que precisa ficar parada no ar** perto do pé: use `ColaInicio` (quando a bola
  começa a ir pro pé de verdade) e `ColaCongelaNoChute` (depois do golpe a bola não segue
  o pé). Ver `Flow_Shidou`.
- **Raycast "procurando o chão" de cima pra baixo** acerta travessão/telhado. Só aceite
  superfície na altura do objeto ou abaixo.
- **Câmera em Y negativo** perto do jogador entra no gramado (tela preta). Mantenha a
  câmera ≥ ~1 stud acima do chão (quadril de pé ≈ 3 acima do gramado).
- **Bola na frente da câmera** em POV/closes tampa tudo: desloque a câmera pro lado ou
  esconda a bola (`BallVisible`).
- **Close com a franja** tampando os olhos: cabelo semitransparente (0.45–0.8) só naquele
  trecho, e devolva a 0.
- **Partícula "risco"** precisa de `Rotation 0` e `RotSpeed 0`; `emissor` com `Taxa = 0`
  nasce desligado.
- **`AlwaysOnTop` em billboard** faz ele SUMIR. Nunca use.
- O que o servidor faz no fim da cena: `_G.TocarCenaFlow` em `PulseController` (posição
  final, giro, bola). Flow com chute: `ChuteNoFlow = true`; a ativação exige bola no ar
  em cima ou recém-dominada do ar (`_G.FlowBolaEmCima`).
- **Duração do Flow = a música**: `Musica = { Id, Volume, Duracao = <segundos do áudio> }`
  em `Cosmeticos` (as duas cópias). O Flow dura `Duracao − duração da cena`.

---

## 6. O processo (resumo; detalhes na skill flow-cutscene)

1. **Vídeo de referência**: o usuário manda o link ou você busca (`python -m yt_dlp
   "ytsearch12:<personagem> flow blue lock"`). Baixe só o vídeo (720p).
2. **Quadros a cada 0,2s** (PyAV, folhas de contato). Monte a **TABELA DE PLANOS** antes de
   codar: tempo no vídeo → o que aparece → câmera → transição → onde fica cada efeito.
   Depois aplique as adaptações da seção 4 (marque na tabela o que mudou e por quê).
3. **Cena de ~12s** na ordem da história: coreografia em `HissatsuCutscenes.luau`, efeitos
   em `HissatsuEfeitos.luau` (`E.Flow<Nome>`). Copie a estrutura do Shidou.
4. **Áudio da cena (~39s = cena + Flow)**: trilha do personagem (playlist Blue Lock OST,
   ver skill) + falas dele separadas com `demucs` + checagem de palavrão com
   `faster-whisper`. Modelo: `.claude/skills/flow-cutscene/mixar_cena_shidou.py`. A batida
   ou explosão da trilha cai no golpe da cena.
5. **Efeito na partida**: aura com o motivo do personagem + olho do Flow no rosto.
6. **Texturas próprias**: gere com PIL (ex.: `gerar_pecas.py` / skill particulas-roblox),
   salve em `docs/texturas/<flow>/`.
7. Balanço `()`/`{}`/`[]`, commit na branch, **HANDOFF**.

---

## 7. Onde fica cada coisa

| O quê | Arquivo |
|---|---|
| Coreografia (tempos, poses, câmera, bola) | `ReplicatedStorage/HissatsuCutscenes.luau` (`Cutscenes.Flow_<Nome>`) |
| Efeitos, sons, closes, olhos | `ReplicatedStorage/HissatsuEfeitos.luau` (`E.Flow<Nome>`, `E.OlhosFlow`) |
| Motor que toca a cena (cliente) | `StarterPlayerScripts/HissatsuCutsceneClient.local.luau` (raramente mexer) |
| Disparo/fim no servidor | `ServerScriptService/PulseController.legacy.luau` (`_G.TocarCenaFlow`) |
| Ativação, duração do Flow | `ServerScriptService/InstinctController.legacy.luau` |
| Item do Flow (cor, motivo, música) | `ReplicatedStorage/Cosmeticos.luau` + `Lobby/ReplicatedStorage/Cosmeticos.luau` |
| Efeito do Flow na partida | `StarterPlayerScripts/CosmeticosClient.local.luau` (`ligarFlowNoCorpo`) |
| Música do Flow | `StarterPlayerScripts/MusicClient.local.luau` (nada a mudar por Flow) |
| Mixagem de áudio (modelos) | `.claude/skills/flow-cutscene/mixar_cena_*.py` |

---

## 8. HANDOFF (obrigatório no fim)

Crie `docs/HANDOFF_<flow>.md` e ponha o mesmo resumo na mensagem do commit:

```
## O que foi feito
- (lista curta por fase da cena, com os tempos)

## O Claude local precisa
- [ ] subir imagens: docs/texturas/<flow>/*.png -> trocar os rbxassetid://0 em <arquivo:linha>
- [ ] o usuário sobe o áudio docs/audio/<flow>.mp3 -> colocar Id em Cosmeticos (2 cópias), Duracao = <s>
- [ ] copiar pro Studio (StarterPlayerScripts não sincroniza): <lista de arquivos>
- [ ] testar no Play com gancho + CutsceneDebugT nos tempos: <lista de tempos pra conferir>
- [ ] conferir: <pontos em que você ficou em dúvida>

## Dúvidas pro usuário
- ...
```

Seja honesto: o que você não pôde ver, diga que não viu. O Claude local refina depois
com o usuário olhando.
