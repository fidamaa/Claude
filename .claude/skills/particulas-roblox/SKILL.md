---
name: particulas-roblox
description: Criar partículas e VFX com textura própria no jogo (efeitos de gol, cutscenes de hissatsu, Flows, armas) — gerar a textura com Python/PIL, conferir, subir pro Roblox, usar em ParticleEmitter/Beam/Billboard e evitar as armadilhas já descobertas. Use sempre que for fazer um efeito visual novo ou trocar a textura de um.
---

# Partículas e VFX com textura própria

O Roblox só tem meia dúzia de texturas prontas (`rbxasset://textures/particles/
sparkles_main.dds`, `fire_main.dds`, `smoke_main.dds`). Tudo que é forma
específica (floco, pétala, coração, peça de quebra-cabeça, olho, cérebro,
coroa...) é **gerado aqui** com Python + PIL e enviado pelo MCP.

## Armadilhas (já custaram horas — não repetir)

1. **`Texture = ""` = partícula INVISÍVEL.** Não existe "quadradinho branco
   padrão". Confete/pétala antigos nunca apareceram por isso.
2. **BillboardGui em studs (`UDim2.fromScale`) com `AlwaysOnTop = true` NÃO é
   desenhado.** Use sempre `AlwaysOnTop = false` e ponha a âncora um pouco à
   frente do que pode tampar (olho: 0.3 stud à frente do rosto, na frente da
   franja). (Com tamanho em pixels, tipo placa de nome, AlwaysOnTop funciona.)
3. **Highlight com Fill no personagem pinta o corpo POR CIMA dos billboards**
   presos nele. Desligue o Fill (`FillTransparency = 1`) quando o billboard
   precisa aparecer.
4. **Billboard some (AbsoluteSize 0) se a câmera entra no raio dele**
   (tamanho/2). Em zoom, limite o tamanho (ex.: máx 1.8 stud com a câmera a 1.3).
5. **LightEmission 1 + muitas partículas sobrepostas + Bloom = tudo BRANCO.**
   Pra cor aparecer (fogos, explosões coloridas) use LightEmission ~0.5-0.6.
6. Imagem recém-enviada leva ~1 min pra liberar; `ContentProvider:PreloadAsync`
   no `require` do módulo evita o primeiro efeito "vazio". O status que o
   PreloadAsync devolve NÃO é confiável (dá Failure em imagem que aparece).
7. Emissor criado no CORPO do jogador (torso/cabeça/braço) não some sozinho no
   fim da cena — guarde e destrua (padrão `prender()` do FlowIsagi).
8. Partícula que tem que "andar junto" com o personagem: `LockedToPart = true`
   + `Shape = Box` + `ShapeStyle = Volume` na parte do corpo (nasce em volta do
   corpo inteiro, não sai de um ponto indo pra trás).
9. Os jogadores da partida são **R6** (sem joelho/cotovelo). Ver skill
   `animacao-roblox` e a memória `billboard-alwaysontop`.
10. Uma Part com `ParticleEmitter` não precisa estar visível
    (`Transparency = 1`). A caixa de emissão = o tamanho da Part.

## Fluxo

1. **Gerar** a textura (PNG RGBA) com PIL — copie um gerador de
   `geradores/` e troque `OUT` pela pasta de imagens da sessão
   (`<scratchpad>/img4/up/fx/`). Regras do desenho:
   - **branco** no RGB e a forma no **alfa** → dá pra tingir com `Color`
     (partícula) / `ImageColor3` (billboard) — uma textura serve pra várias cores;
   - exceções coloridas de propósito: esfera sombreada (cinza), moeda, coroa;
   - brilho/“glow”: linha nítida + `GaussianBlur` somado (função `brilhar`);
   - 256 px basta pra partícula; 512 pra billboard grande (planeta, cérebro).
2. **Conferir** numa folha de contato sobre fundo escuro (os geradores já
   salvam `fx_*.png` no scratchpad) e olhar com o Read antes de subir.
3. **Subir**: servidor local na pasta de imagens
   (`python -m http.server 8766 --bind 127.0.0.1`, em background com timeout
   longo) e `mcp__Roblox_Studio__upload_image` com as URLs
   (`http://127.0.0.1:8766/fx/<nome>.png`; nome com espaço/acento →
   `urllib.parse.quote`). O retorno é `rbxassetid://...`. Se devolver um ID
   que já existe, a imagem é idêntica a uma já enviada.
4. **Usar**: guarde o ID numa tabela `TEX` no topo do módulo do efeito com o
   que ela é (`Floco = "rbxassetid://..." -- floco de neve 6 braços`).
5. **Testar** no Play (ver abaixo) e commitar.

## Catálogo de texturas já enviadas

| Nome | ID | O que é |
|---|---|---|
| Brilho | 116102662517740 | círculo macio (miolo forte + halo) — glow, poeira de luz |
| Estrela | 124076223617744 | estrela de 4 pontas — cintilar, estrelas |
| Quadrado | 114969590166539 | confete |
| Gota | 78958439073718 | risco vertical — chuva, suor, lágrima |
| Anel | 109697697529772 | anel fino — onda no chão, anel de planeta |
| Bolha | 128373337523591 | bolha furta-cor com reflexo |
| Esfera | 110065763545195 | planeta sombreado (cinza; tingir) |
| Coração | 84266930435195 | coração |
| Pétala | 112377272367032 | pétala de cerejeira |
| Floco | 92470203989347 | floco de neve de 6 braços |
| Nuvem | 127024223594157 | fumaça/névoa/nebulosa com ruído (melhor que smoke_main) |
| Moeda | 95324231257907 | moeda dourada com "$" (já colorida) |
| OlhoMandala | 117811093891036 | pupila-engrenagem (Flow do Isagi) |
| Cérebro | 80036316167885 | cérebro de linhas brilhantes |
| OlhoGênio | 97454924327948 | íris rendada com estrelas |
| QuebraCabeça | 105934225794623 | azulejo 2x2 de peças (ScaleType Tile) |
| Redemoinho | 140668349355595 | espiral |
| Riscos | 121453343893984 | riscos verticais de velocidade |
| Peças 1-6 | 78118904101221, 105525967568383, 111438389261843, 128485843176223, 86633552604297, 95574913983821 | peças de quebra-cabeça diferentes |
| Coroa | 98779256563620 | coroa dourada com joias roxas (Ego do Rei) |

Onde estão em uso: `ReplicatedStorage/EfeitosDeGol.luau` (TEX),
`ReplicatedStorage/HissatsuEfeitos.luau` (TEX_FLOW, `E.PecasEmVolta`),
`StarterPlayerScripts/ArmasVFX.local.luau` (coroa).

## Receitas que funcionaram

- **Chuva/neve no campo inteiro**: Part do tamanho do campo (medido pelos gols
  `GolAzul`/`GolAmarelo`) a ~80 studs de altura + uma caixa menor que segue a
  câmera (densidade onde o jogador olha). Ver `Sessao:EmissorCampo` e
  `Sessao:EmissorCamera` em EfeitosDeGol.
- **Onda no chão**: Part fina com `SurfaceGui` (Face Top, LightInfluence 0,
  Brightness 2) e a textura Anel; tween no Size.
- **Chão que “vira” padrão**: SurfaceGui com `SizingMode = PixelsPerStud` e
  ImageLabel `ScaleType = Tile` — a Part cresce e os ladrilhos ficam do
  mesmo tamanho no mundo.
- **Planeta/núcleo/cérebro grande**: BillboardGui com camadas (glow atrás,
  imagem na frente) — esfera de Part grande vira polígono.
- **Ambiente** (escurecer, noite, neblina): mexer em `Lighting.ClockTime`
  (sempre pra frente), ColorCorrection própria e `Atmosphere`, guardando os
  valores e devolvendo no fim (ver `Sessao:Ambiente`).

## Testar sem depender de sorte

- O `execute_luau` do MCP não pode `require` módulo do jogo nem disparar
  remote: ponha um gancho `--TESTE_INICIO/--TESTE_FIM` num script do servidor
  que escuta um atributo do workspace e dispara o efeito; tire antes do commit.
- Cutscene: atributo `CutsceneDebugT` no LocalPlayer congela o tempo; espere
  ~1.5s depois de pular pra um tempo (flashes/fade em tempo real).
- Pra checar se um billboard está sendo desenhado: `AbsoluteSize` (0 = não).
- Controle de captura: uma Part Neon vermelha na frente da câmera.
