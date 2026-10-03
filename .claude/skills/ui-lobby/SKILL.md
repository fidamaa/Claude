---
name: ui-lobby
description: Padrão visual das telas (HUD/GUI) do jogo de futebol Roblox — paleta, tipografia, cartões, botões, cabeçalho, escala pra celular e o que NÃO fazer (emoji). Use sempre que for criar ou refazer qualquer tela/HUD do Lobby ou da partida (Roll, Ficha de personagem, Missões, Matchmaking, diálogo, Loja, QTE...).
---

# UI do Lobby (e do jogo)

Todas as telas são **construídas ou reestilizadas por código** (GUI do Studio
não sincroniza pro disco; só Script). Quando a GUI veio montada no Studio
(ex.: `roll`), o script acha os objetos e reescreve tamanho/posição/cor na
carga. Referências prontas: `RollClient` (Roll), `CharacterClient` (Ficha),
`DialogueClient` (diálogo), `MissionTrackerHUD`, `MatchmakingClient`.

## Regras do usuário (não quebrar)

- **NADA de emoji.** Nem em texto, nem como ícone (🔥⭐🔒✨...). Elemento =
  chip com o nome na cor do elemento; nota/sorte = barrinhas; bloqueado =
  texto "BLOQUEADO". Símbolos simples de texto são ok (✓ ⇄ › ▼ X).
- **Texto claro.** Nada de legenda escura: dica/legenda usa `COR_TEXTO_MEDIO`
  ou `COR_LEGENDA`; `COR_TEXTO_FRACO` só pra coisa realmente secundária.
- **Tamanho:** a tela precisa ficar GRANDE e legível. Prefira layout que
  cresce na LARGURA (a altura da tela é o que limita). Painel sempre com
  `UIScale` que encaixa na tela (celular) e pode passar de 1 em tela grande.
- **Sem tela preta de espera** pra abrir coisas: apertou, abriu.

## Paleta

```lua
local COR_PAINEL      = Color3.fromRGB(13, 15, 22)   -- fundo do painel
local COR_CARTAO      = Color3.fromRGB(21, 24, 34)   -- cartões, cabeçalho
local COR_CARTAO_ALT  = Color3.fromRGB(27, 31, 43)   -- hover, chips, fundo de barra
local COR_BORDA       = Color3.fromRGB(34, 38, 52)   -- UIStroke padrão
local COR_ACENTO      = Color3.fromRGB(76, 156, 255) -- azul: seleção, faixa de título
local COR_LEGENDA     = Color3.fromRGB(125, 185, 255)-- azul claro: rótulos/legendas
local COR_OK          = Color3.fromRGB(64, 196, 122) -- verde: ação principal (GIRAR, +, ATIVO)
local COR_OURO        = Color3.fromRGB(255, 200, 70) -- nível, pontos, sorte
local COR_TEXTO       = Color3.fromRGB(238, 241, 248)
local COR_TEXTO_MEDIO = Color3.fromRGB(190, 197, 212)
local COR_TEXTO_FRACO = Color3.fromRGB(120, 128, 148)
```
Elementos: Natureza (110,210,110), Fogo (255,120,60), Vento (90,220,200),
Luz (255,215,90), Void (170,110,255). Raridade: cores de `RARITIES` no RollClient.
Robux: botão (60,130,90) com texto (150,255,195) e "R$" (ASCII — "✦"/"×"
não existem na Gotham e viram quadrado).

## Tipografia

Gotham em tudo. `GothamBlack` pra títulos, rótulos em CAIXA ALTA, números
e botões; `GothamMedium` pra texto corrido; `GothamBold` pra dica/rodapé.
Tamanhos base (antes do UIScale): título 20–22, nome 15–22, corpo 13–17,
rótulo 11–13. `TextScaled = false` (o que vem do Studio costuma estar true —
desligue, senão o X/contador estouram).

## Peças

- **Painel:** `COR_PAINEL`, `UICorner` 10, `UIStroke` `COR_BORDA` 1px
  (transp 0.15). Centralizado (AnchorPoint 0.5) + `UIScale`:
  `min(ESCALA_MAX, (vp.X-2m)/W, (vp.Y-2m)/H)`, atualizado em `ViewportSize`.
- **Cabeçalho:** 56px, `COR_CARTAO`; faixa azul 4x22 + título GothamBlack à
  esquerda; X redondo 34x34 `COR_CARTAO_ALT` à direita; ações alinhadas à
  direita com AnchorPoint (1, 0.5) (nunca posição em escala herdada).
- **Cartão:** `COR_CARTAO`, canto 8–10, borda `COR_BORDA`; selecionado =
  borda `COR_ACENTO` 2px; hover = `COR_CARTAO_ALT`. Legenda DENTRO do cartão
  (título azul claro + explicação em `#BEC5D4` via RichText).
- **Chip:** `COR_CARTAO_ALT`, canto 6, texto GothamBlack 12–13 na cor do
  significado, `UIStroke` da mesma cor com transparência ~0.5.
- **Botão principal:** fundo `COR_OK`, texto branco GothamBlack, canto 8,
  hover clareia 12%. Secundário: `COR_CARTAO_ALT` + texto `COR_LEGENDA` +
  borda `COR_ACENTO` (transp 0.5).
- **Escolhas numeradas** (diálogo): cartão 38px com "tecla" 22x22 à
  esquerda (número em azul) e "›" à direita quando abre uma tela.
- **Barra (XP etc.):** fundo `COR_CARTAO_ALT` arredondado, preenchimento
  `COR_ACENTO` (dourado no máximo, com texto escuro por cima).
- **Modo de seleção** (ex.: trocar slot): camada escura (`COR_PAINEL`,
  transp ~0.18) com o texto da ação em `COR_LEGENDA` por cima do alvo; o
  que foi escolhido fica com borda azul e o botão vira "CANCELAR".
- **Caixa com fade:** `CanvasGroup` + `GroupTransparency` (entra 0.18s,
  subindo 20px).

## Validar

Play no Studio do Lobby, abrir a tela (pelo NPC com `prompt:InputHoldBegin/End`
ou `_G.Open...` não funciona pelo MCP — o `_G` é outro), `screen_capture`
e conferir: nada sobreposto, texto legível, escala (`UIScale.Scale`) boa na
janela atual. `user_mouse_input` com `instance_path` clica em botões; as
teclas 1–9 são da barra do Roblox e o VirtualInput não consegue apertá-las.
