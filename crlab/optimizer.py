"""Sugestões de troca de cartas com trade-offs explícitos por arquétipo."""
from __future__ import annotations

import numpy as np

from .archetypes import A_INDEX, ARCH_PT, ARCHETYPES
from .engine import Engine
from .explain import join_pt
from .levels import PlayerCollection


def _pp(x: float) -> str:
    return f"{100 * x:+.1f} p.p."


def suggest_swaps(engine: Engine, idx: list[int], col: PlayerCollection | None = None, top: int = 5,
                  keep: list[int] | None = None, keep_win_condition: bool = False, target: str | None = None,
                  per_card: int = 3) -> dict:
    cat = engine.catalog
    f = cat.features
    keep = set(keep or [])
    if keep_win_condition:
        keep |= {i for i in idx if f["wc"][i] > 0}
    pool = col.owned if col is not None else list(range(cat.n))
    pool = [c for c in pool if c not in idx]
    base = engine.evaluate([idx], col)
    swaps, decks = [], []
    for pos, out_card in enumerate(idx):
        if out_card in keep:
            continue
        rest = [x for x in idx if x != out_card]
        has_champ = any(f["champ"][x] > 0 for x in rest)
        for c in pool:
            if has_champ and f["champ"][c] > 0:
                continue
            swaps.append((out_card, c))
            decks.append(rest + [c])
    if not decks:
        return {"swaps": [], "replacements": {}, "note": "Nenhuma troca possível com as restrições atuais."}
    ev = engine.evaluate(np.array(decks), col)
    d_score = ev["score"] - base["score"][0]
    d_ev = ev["ev"] - base["ev"][0]
    d_p = ev["p"] - base["p"][0]

    def describe(i):
        out_card, in_card = swaps[i]
        diffs = d_p[i]
        ups = [j for j in np.argsort(-diffs) if diffs[j] > 0.01][:3]
        downs = [j for j in np.argsort(diffs) if diffs[j] < -0.01][:3]
        a, b = cat.cards[out_card], cat.cards[in_card]
        txt = f"Trocar {a.name_pt} por {b.name_pt}"
        if ups:
            txt += " melhora o matchup contra " + join_pt([f"{ARCH_PT[ARCHETYPES[j]]} ({_pp(diffs[j])})" for j in ups])
        if downs:
            txt += (", mas" if ups else "") + " reduz sua capacidade contra " + join_pt(
                [f"{ARCH_PT[ARCHETYPES[j]]} ({_pp(diffs[j])})" for j in downs])
        if not ups and not downs:
            txt += " praticamente não altera os matchups"
        txt += f". Média vs meta: {_pp(d_ev[i])}."
        return {
            "out": a.key, "in": b.key, "out_pt": a.name_pt, "in_pt": b.name_pt,
            "delta_score": round(float(d_score[i]), 4), "delta_ev": round(float(d_ev[i]), 4),
            "delta_by_archetype": {ARCHETYPES[j]: round(float(diffs[j]), 4) for j in range(len(ARCHETYPES))},
            "explanation": txt,
        }

    if target:
        t = A_INDEX[target]
        order = [i for i in np.argsort(-d_p[:, t]) if d_score[i] > -0.01]
    else:
        order = list(np.argsort(-d_score))
    best = [describe(i) for i in order[:top] if (target or d_score[i] > 0)]

    replacements = {}
    for out_card in idx:
        if out_card in keep:
            continue
        cand = [i for i, s in enumerate(swaps) if s[0] == out_card]
        cand.sort(key=lambda i: -d_score[i])
        replacements[cat.cards[out_card].key] = [describe(i) for i in cand[:per_card]]
    return {
        "swaps": best,
        "replacements": replacements,
        "kept": [cat.cards[i].key for i in keep],
        "note": ("Estimativas de troca usam o modelo heurístico/estatístico; partidas do deck exato só existem "
                 "para o deck original. Valores em pontos percentuais de taxa de vitória."),
    }
