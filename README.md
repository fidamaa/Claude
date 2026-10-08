# Clash Deck Lab

Ferramenta para **analisar, comparar e criar decks de Clash Royale** com foco em precisão, transparência e
explicações. Ela não entrega uma nota única de 0 a 100. Ela tenta responder:

> Considerando as cartas do jogador, os níveis delas, o meta atual e os dados reais disponíveis, qual deck tem a
> melhor combinação de consistência, sinergia e desempenho contra diferentes adversários?

## O que faz

| Recurso | Como |
|---|---|
| **Analisar deck** | Estrutura (condição de vitória, defesa aérea/terrestre, área, feitiços, construções, ciclo, custo), sinergias e conflitos, vulnerabilidades, pontos fortes e resumo em texto |
| **Matchups por arquétipo** | Ciclo, beatdown, bridge spam, siege, bait, controle, Lava, Cemitério, Corredor, Gigante Real e Broca Goblin, cada um com probabilidade, rótulo (muito favorável → muito desfavorável), motivos, intervalo de credibilidade, fonte e **nível de confiança** |
| **Níveis e evoluções** | Diferencia força teórica, força no nível do jogador, desempenho no meta (dados) e compatibilidade com o deck |
| **Otimização** | "Trocar A por B melhora contra X (+3,1 p.p.), mas piora contra Y (−2,0 p.p.)" e as 3 melhores substitutas por carta, opcionalmente mantendo a condição de vitória ou mirando um arquétipo |
| **Criar decks** | Busca combinatória sobre a coleção do jogador com cartas obrigatórias/proibidas, condição de vitória, estilo e faixa de elixir, e devolve os K melhores decks distintos, comparados lado a lado |
| **Meta e jogadores** | Decks e cartas em alta nas partidas coletadas; consulta do deck atual e dos decks recentes de qualquer jogador pela tag |
| **Copiar para o jogo** | Botão que abre o Clash Royale com o deck pronto para copiar (link oficial `link.clashroyale.com`) |
| **Dados reais** | Coleta pela API oficial, importação de JSONL/CSV, modelo estatístico com validação temporal, janela de período e ponderação por recência |

## Instalação e uso rápido

```bash
pip install -e ".[dev]"          # Python 3.10+
crlab serve                      # interface web em http://127.0.0.1:8000
```

CLI:

```bash
crlab analyze "Hog Rider, Musketeer, Ice Golem, Ice Spirit, Skeletons, Cannon, Fireball, The Log"
crlab analyze "Corredor, Mosqueteira, Golem de Gelo, Espírito de Gelo, Esqueletos, Canhão, Bola de Fogo, Tronco" --collection colecao.json
crlab suggest "..." --keep-wincon --target beatdown
crlab build --collection colecao.json --wincon "Hog Rider, Miner" --style cycle --max-elixir 3.3 --top 5
crlab cards                      # catálogo (nomes em inglês, português e apelidos como "pekka", "log", "xbow")
```

Formato da coleção (`colecao.json`); os níveis usam a escala unificada de 1 a 16:

```json
{"cards": {"Hog Rider": 14, "Musketeer": 13, "The Log": 12},
 "evolutions": ["Knight"],
 "reference_level": 14}
```

`reference_level` é o nível típico dos seus adversários. Se omitido, usa o percentil 75 dos seus níveis.
Para baixar a coleção automaticamente: `crlab player "#SUATAG" --out colecao.json` (requer token da API).

## Site hospedado (Render, gratuito)

1. Acesse **https://render.com/deploy?repo=https://github.com/fidamaa/Claude** e entre com o GitHub.
2. Em `CR_API_TOKEN`, cole a chave da API (cadastrada para o IP `45.79.218.79`, do proxy da RoyaleAPI).
   `ADMIN_KEY` é gerada automaticamente (senha do botão "Coletar e retreinar agora").
3. Clique em **Apply**. Em alguns minutos o site fica em `https://clash-deck-lab-xxxx.onrender.com`.

O site importa sua conta pela tag (cartas, níveis, evoluções e deck atual), coleta partidas reais
automaticamente a cada `AUTO_COLLECT_HOURS` horas e retreina o modelo sem sair do ar. No plano gratuito o
servidor "dorme" após 15 min sem acesso e o disco é temporário: ao acordar (~1 min), ele refaz a coleta.
Para outro provedor, há um `Dockerfile` (variável `PORT`).

## Dados reais

```bash
export CR_API_TOKEN=...                 # https://developer.clashroyale.com (o token exige o IP cadastrado)
crlab data crawl --top 100 --max-players 500    # ranking -> battlelogs -> adversários (BFS)
crlab data import --file partidas.jsonl         # ou .csv / battlelog bruto da API
crlab data train --days 30                      # treina o modelo com a janela escolhida
crlab data status
```

* O battlelog da API guarda só as ~25 partidas mais recentes de cada jogador. Para acumular histórico, agende a
  coleta (cron). Partidas vistas pelos dois jogadores são deduplicadas por um id canônico.
* Com IP dinâmico, cadastre na chave o IP `45.79.218.79` (proxy da RoyaleAPI). A ferramenta detecta isso pela
  própria chave e usa `https://proxy.royaleapi.dev/v1` automaticamente.
* No Windows (PowerShell), defina o token com `$env:CR_API_TOKEN="sua_chave"`.
* `crlab data synth` gera partidas **sintéticas** só para demonstrar e testar o pipeline. Elas ficam marcadas e
  a interface mostra um aviso sempre que o modelo em uso foi treinado com elas. Use
  `crlab data train --exclude-synthetic` para treinar só com dados reais.

## Como os números são produzidos

```
             ┌──────────────────────────┐
deck ──────► │ 1. Heurística explicável │──┐ (sempre disponível; limitada a ~35–65%)
             └──────────────────────────┘  │ mistura ponderada por amostra:
             ┌──────────────────────────┐  │ w = n_suporte / (n_suporte + model_k)
             │ 2. Modelo de cartas      │──┤
             └──────────────────────────┘  ▼
                                  + 3. ajuste de nível (γ por nível)
                                  + 4. partidas do deck exato (posterior Beta)
                                  = probabilidade, intervalo, fonte, confiança
```

1. **Heurística** (`features.py`, `archetypes.py`, `engine.py`): cada deck recebe 15 capacidades em [0,1]
   (defesa aérea, área aérea/terrestre, resposta a tanques, defesa contra cartas que miram construções, respostas
   baratas, ciclo, custo, feitiços, reset, pressão, alcance a construções, contra-ataque, defesa contra Cemitério e
   volume defensivo), com retornos decrescentes. Cada arquétipo tem um perfil do que **exige** do adversário. O
   matchup soma:
   * *defesa*: as capacidades do seu deck em relação à média, ponderadas pelo que o arquétipo exige;
   * *ataque*: o quanto o arquétipo costuma ser fraco no que **o seu** plano exige, condicionado à pressão real do deck;
   * sinergia de pares, coerência estrutural (sem condição de vitória, siege + beatdown, Lava sem suporte aéreo…),
     força teórica das cartas e custo de elixir.
2. **Modelo de cartas** (`datamodel.py`): regressão logística tipo Bradley-Terry
   `logit P(A vence B) = Σb[A] − Σb[B] + ΣM[A, arq(B)] − ΣM[B, arq(A)] + γ·Δnível`,
   com L2 e ponderação por recência (meia-vida configurável). O resultado é validado nos 10% de partidas mais
   recentes (log-loss, acurácia, Brier).
3. **Tamanho da amostra sempre conta**: partidas do deck exato atualizam a estimativa como posterior Beta.
   90% em 20 partidas fica perto do prior; 56% em 100.000 quase não muda (`stats.py`, com testes). Os priors de
   cartas são estimados por Bayes empírico (método dos momentos).
4. **Pesos derivados de dados quando possível**: com partidas suficientes, os pesos de demanda de cada arquétipo
   são recalibrados por regressão logística, o γ de nível vem do modelo, a sinergia de pares passa a usar o resíduo
   observado (o quanto o par vence além da força individual das cartas) e os pesos do índice de fatores são ajustados
   por mínimos quadrados não-negativos. Sem dados, valem os padrões de `settings.py`, todos ajustáveis por JSON
   (`--settings` ou `CRLAB_SETTINGS`).
5. **Confiança**: `n_efetivo = partidas do deck exato + 0,05 × partidas de suporte das cartas` →
   alta (≥1000), média (≥150), baixa (>0) ou **heurística** (sem dados; a interface diz isso explicitamente).

**Visão geral do deck**: média das probabilidades ponderada pela frequência de cada arquétipo no meta (dos dados, ou
uma distribuição padrão configurável). O *score* padrão é `média − 0,5 × desvio entre matchups`, que favorece
consistência. Há também os modos `mean` e `maximin`. O "índice de fatores" (17 fatores) existe por transparência,
mas é secundário.

**Gerador de decks** (`builder.py`): busca local iterada. As sementes são cada condição de vitória possível, decks
de referência e decks populares nos dados. Cada deck é completado de forma gulosa, avaliando todas as candidatas em
lote. Depois, o gerador testa todas as trocas 1-por-1 até convergir e aplica perturbações para escapar de ótimos
locais. Por fim, escolhe os melhores decks com núcleos de vitória diferentes e faz a análise completa de cada um.
São ~10⁴–10⁵ decks avaliados em menos de 1 s com uma coleção típica.

## Limitações conhecidas (MVP)

* Sem dados, as estimativas são **heurísticas**. Os atributos do catálogo (`crlab/data/cards.csv`), a tabela de
  sinergias e os decks de referência são priors escritos à mão e foram marcados como tal. No modo heurístico, a
  busca tende a preferir decks "versáteis" (ex.: Mineiro + Veneno + Dragão Infernal). Dados reais corrigem isso.
* O catálogo tem 110 cartas. Cartas lançadas depois dele aparecem nas partidas importadas e são descartadas do
  treino (a contagem é informada). Basta adicionar uma linha ao CSV.
* A normalização de nível da API usa `nível + (16 − maxLevel)`. Como o modelo usa diferenças de nível, um
  deslocamento constante não afeta o resultado.

## Estrutura

```
crlab/
  catalog.py      cartas, nomes pt/en, apelidos, matriz de atributos
  archetypes.py   arquétipos, classificação, perfis de demanda
  features.py     capacidades vetorizadas, coerência, sinergia
  levels.py       coleção do jogador, níveis, evoluções
  stats.py        posterior Beta, intervalos, Bayes empírico, regressão logística
  engine.py       motor: heurística + modelo + níveis + explicações
  optimizer.py    sugestões de troca
  builder.py      gerador de decks
  datamodel.py    treino do modelo estatístico e calibrações
  store.py        SQLite (esquema portável para Postgres/DuckDB)
  ingest/         API oficial, importadores, gerador sintético
  api.py, cli.py  REST (FastAPI) e linha de comando
  web/            interface (HTML/JS sem dependências)
  data/           cards.csv, synergies.json, reference_decks.json
tests/            pytest (estatística, motor, gerador, pipeline de dados, API)
```

## Próximos passos sugeridos

* Coleta contínua agendada e armazenamento em Parquet/DuckDB para milhões de partidas.
* Interações de pares e trincas no próprio modelo (fatoração), além de efeitos por faixa de troféus/modo de jogo.
* Modelo por deck vs deck (não só vs arquétipo) usando embeddings de decks.
* Atributos do catálogo extraídos automaticamente dos dados do jogo, no lugar dos priors manuais.
