"""Gerador de partidas SINTÉTICAS — apenas para demonstração e testes do pipeline.

As partidas são marcadas com source="synthetic" e o sistema exibe um aviso sempre que um modelo
treinado com elas estiver em uso. Elas NÃO representam o meta real.

Verdade oculta: logit = heurística(A vs arq(B)) - heurística(B vs arq(A)) + força oculta das cartas
+ γ·Δnível + ruído. Serve para verificar se o modelo estatístico recupera efeitos conhecidos.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import numpy as np

from ..engine import Engine


def _mutate(deck: list[int], engine: Engine, rng, n_swaps: int) -> list[int]:
    cat = engine.catalog
    f = cat.features
    deck = list(deck)
    for _ in range(n_swaps):
        pos = rng.integers(8)
        old = deck[pos]
        same = [c.idx for c in cat.cards if c.type == cat.cards[old].type and c.idx not in deck
                and abs(c.elixir - cat.cards[old].elixir) <= 1 and not (f["champ"][c.idx] and f["champ"][deck].sum())]
        if same:
            deck[pos] = int(rng.choice(same))
    return deck


def generate(engine: Engine, n: int = 20000, seed: int = 0, days: int = 30, gamma: float = 0.3,
             hidden_sd: float = 0.08) -> tuple[list[dict], dict]:
    rng = np.random.default_rng(seed)
    cat = engine.catalog
    hidden = rng.normal(0, hidden_sd, cat.n)
    base = [d["idx"] for d in engine.reference_decks]
    pool = []
    for d in base:
        pool.append(d)
        for _ in range(12):
            pool.append(_mutate(d, engine, rng, int(rng.integers(1, 4))))
    pool = np.array(pool)
    popularity = rng.pareto(1.5, len(pool)) + 1
    popularity /= popularity.sum()
    ev = engine.evaluate(pool)
    prim = ev["primary"]
    L = np.log(ev["p"] / (1 - ev["p"]))
    ia = rng.choice(len(pool), n, p=popularity)
    ib = rng.choice(len(pool), n, p=popularity)
    lvl_a = np.clip(rng.normal(14, 0.8, n), 10, 16)
    lvl_b = np.clip(lvl_a + rng.normal(0, 0.6, n), 10, 16)
    z = (L[ia, prim[ib]] - L[ib, prim[ia]]) / 2 + hidden[pool[ia]].sum(1) - hidden[pool[ib]].sum(1) \
        + gamma * (lvl_a - lvl_b)
    y = (rng.random(n) < 1 / (1 + np.exp(-z))).astype(float)
    now = datetime.now(timezone.utc).replace(microsecond=0)
    out = []
    for k in range(n):
        t = now - timedelta(seconds=int(rng.integers(0, days * 86400)))
        out.append({
            "played_at": t.isoformat(), "source": "synthetic", "mode": "synthetic",
            "a": {"cards": [cat.cards[i].key for i in pool[ia[k]]], "level": round(float(lvl_a[k]), 2),
                  "tag": f"#SYN{k}A"},
            "b": {"cards": [cat.cards[i].key for i in pool[ib[k]]], "level": round(float(lvl_b[k]), 2),
                  "tag": f"#SYN{k}B"},
            "result": float(y[k]),
        })
    truth = {"gamma": gamma, "hidden_strength": {cat.cards[i].key: float(hidden[i]) for i in range(cat.n)}}
    return out, truth
