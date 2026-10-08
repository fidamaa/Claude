"""Geração de decks por busca combinatória (não aleatória).

Estratégia: busca local iterada com múltiplas sementes.
  1. Sementes: cada condição de vitória possível (ou a escolhida), + decks populares nos dados e
     decks de referência que o jogador consegue montar.
  2. Completar gulosamente: a cada passo avalia TODAS as cartas candidatas em lote (vetorizado).
  3. Busca local: avalia todas as trocas 1-por-1 (8 x |coleção|) e aplica a melhor até convergir.
  4. Perturbação (2 trocas aleatórias) e repetição, para escapar de ótimos locais.
  5. Seleciona os K melhores decks distintos (diferem em pelo menos N cartas) e faz a análise
     completa de cada um, incluindo dados de partidas do deck exato.
"""
from __future__ import annotations

import copy
from dataclasses import dataclass, field

import numpy as np

from .archetypes import A_INDEX, ARCH_PT, ARCHETYPES
from .engine import DeckError, Engine
from .levels import PlayerCollection


@dataclass
class BuildRequest:
    owned: list[int] | None = None          # None = todas as cartas
    must_include: list[int] = field(default_factory=list)
    exclude: list[int] = field(default_factory=list)
    win_conditions: list[int] = field(default_factory=list)  # deck deve conter ao menos uma
    style: str | None = None                # arquétipo desejado (ex.: "cycle", "beatdown")
    max_avg_elixir: float | None = None
    min_avg_elixir: float | None = None
    top_k: int | None = None
    potential: bool = True                  # incluir decks extras "se você upar/desbloquear"


class DeckBuilder:
    def __init__(self, engine: Engine):
        self.engine = engine
        self.cat = engine.catalog
        self.bcfg = engine.cfg["builder"]
        self.f = self.cat.features

    # ---------------------------------------------------------------- objetivo
    def _score(self, decks: np.ndarray, req: BuildRequest, col) -> np.ndarray:
        ev = self.engine.evaluate(decks, col, fast=True)
        s = ev["score"].copy()
        f = self.f
        champs = f["champ"][decks].sum(1)
        s[champs > 1] -= 10
        if req.style:
            s[~ev["labels"][:, A_INDEX[req.style]]] -= self.bcfg["style_penalty"]
        if decks.shape[1] == 8:
            avg = f["elixir"][decks].mean(1)
            if req.max_avg_elixir:
                s -= 0.5 * np.maximum(avg - req.max_avg_elixir, 0)
            if req.min_avg_elixir:
                s -= 0.5 * np.maximum(req.min_avg_elixir - avg, 0)
        if req.win_conditions:
            has = np.isin(decks, req.win_conditions).any(1)
            s[~has] -= 10
        return s

    # ---------------------------------------------------------------- busca
    def _complete(self, partial: list[int], pool: np.ndarray, req, col, rng, noise=0.0) -> list[int]:
        deck = list(partial)
        while len(deck) < 8:
            cand = pool[~np.isin(pool, deck)]
            batch = np.empty((len(cand), len(deck) + 1), dtype=int)
            batch[:, :-1] = deck
            batch[:, -1] = cand
            s = self._score(batch, req, col)
            if noise:
                s = s + rng.normal(0, noise, len(s))
            deck.append(int(cand[int(np.argmax(s))]))
        return deck

    def _local_search(self, deck: list[int], locked: set[int], pool: np.ndarray, req, col, seen: dict):
        """Melhor troca 1-por-1 até convergir. Os lotes (posições livres x candidatas) são montados
        de forma vetorizada; só os melhores de cada lote entram no registro de decks vistos."""
        cur = np.array(deck)
        cur_s = float(self._score(cur[None, :], req, col)[0])
        for _ in range(self.bcfg["max_iters"]):
            free = np.array([p for p, c in enumerate(cur) if c not in locked])
            cand = pool[~np.isin(pool, cur)]
            if len(free) == 0 or len(cand) == 0:
                break
            pos = np.repeat(free, len(cand))
            new = np.tile(cand, len(free))
            batch = np.repeat(cur[None, :], len(pos), axis=0)
            batch[np.arange(len(pos)), pos] = new
            s = self._score(batch, req, col)
            for j in np.argpartition(-s, min(24, len(s) - 1))[:24]:
                seen[tuple(sorted(batch[j].tolist()))] = float(s[j])
            j = int(np.argmax(s))
            if s[j] <= cur_s + 1e-6:
                break
            cur, cur_s = batch[j].copy(), float(s[j])
        seen[tuple(sorted(cur.tolist()))] = cur_s
        return cur.tolist(), cur_s

    def _search(self, req, col, pool, must, wcs, rng, light: bool = False) -> dict:
        """Busca local iterada; devolve {deck (tupla ordenada): score} dos melhores decks vistos."""
        f = self.f
        seeds: list[list[int]] = []
        if wcs:
            seeds += [must + [w] if w not in must else list(must) for w in wcs]
        elif any(f["wc"][m] > 0 for m in must):
            seeds.append(list(must))
        else:
            cand_wc = [int(c) for c in pool if f["wc"][c] > 0 and c not in must]
            single = self._score(np.array([must + [c] for c in cand_wc]), req, col) if cand_wc else []
            for j in np.argsort(-np.asarray(single))[: (6 if light else self.bcfg["max_seeds"])]:
                seeds.append(must + [cand_wc[j]])
            if not seeds:
                seeds.append(list(must))
        known = self._known_decks(pool, must, req)

        seen: dict[tuple, float] = {}
        locked = set(must) | ({wcs[0]} if len(wcs) == 1 else set())
        starts = []
        for sd in seeds:
            for r in range(1 if light else self.bcfg["restarts_per_seed"]):
                starts.append(self._complete(sd, pool, req, col, rng, noise=0.0 if r == 0 else 0.02))
        starts += known
        pool = self._prune_pool(starts, pool, must, wcs, req, col, light)
        done_starts: set[tuple] = set()
        optima: set[tuple] = set()
        for st in starts:
            key = tuple(sorted(st))
            if key in done_starts:
                continue
            done_starts.add(key)
            lock = locked | (set(st) & set(wcs)) if wcs else locked
            deck, s = self._local_search(st, lock, pool, req, col, seen)
            if tuple(sorted(deck)) in optima:  # convergiu para um ótimo já explorado
                continue
            optima.add(tuple(sorted(deck)))
            for _ in range(0 if light else self.bcfg["perturbations"]):  # perturbação
                free = [c for c in deck if c not in lock]
                if len(free) < 2:
                    break
                drop = rng.choice(free, 2, replace=False)
                kept = [c for c in deck if c not in drop]
                pert = self._complete(kept, pool, req, col, rng, noise=0.03)
                deck2, s2 = self._local_search(pert, lock, pool, req, col, seen)
                if s2 > s:
                    deck, s = deck2, s2

        return seen

    def build(self, req: BuildRequest, col: PlayerCollection | None = None) -> dict:
        cat, f = self.cat, self.f
        rng = np.random.default_rng(self.bcfg["seed"])
        owned = req.owned if req.owned is not None else (col.owned if col is not None else list(range(cat.n)))
        pool = np.array(sorted(set(owned) - set(req.exclude) | set(req.must_include)))
        must = list(dict.fromkeys(req.must_include))
        if len(must) > 8:
            raise DeckError("Mais de 8 cartas obrigatórias.")
        if sum(f["champ"][m] for m in must) > 1:
            raise DeckError("Mais de um campeão obrigatório.")
        if len(pool) < 8:
            raise DeckError(f"São necessárias pelo menos 8 cartas disponíveis (há {len(pool)}).")
        if set(req.exclude) & set(must):
            raise DeckError("Uma carta não pode ser obrigatória e excluída ao mesmo tempo.")
        wcs = [w for w in req.win_conditions if w in pool]
        if req.win_conditions and not wcs:
            raise DeckError("Nenhuma das condições de vitória pedidas está disponível na coleção.")

        seen = self._search(req, col, pool, must, wcs, rng)
        ranked = sorted(seen.items(), key=lambda kv: -kv[1])
        top_k = req.top_k or self.bcfg["top_k"]
        chosen = self._select_diverse(ranked, must, req, top_k * 2)
        results = []
        for deck, s in chosen:
            rep = self.engine.analyze(list(deck), col)
            results.append({"score_search": round(s, 4), "analysis": rep})
        # reordena com a análise completa (inclui partidas do deck exato)
        results.sort(key=lambda r: -r["analysis"]["overall"]["score"])
        results = results[:top_k]
        for i, r in enumerate(results):
            r["rank"] = i + 1
            r["why"] = self._why(r, results)
        potential = self._potential(req, col, pool, must, wcs, rng, [r["analysis"]["deck"] for r in results]) \
            if (col is not None and req.potential) else []
        return {
            "decks": results,
            "potential": potential,
            "explored": len(seen),
            "request": {
                "pool_size": int(len(pool)), "must_include": [cat.cards[i].key for i in must],
                "exclude": [cat.cards[i].key for i in req.exclude],
                "win_conditions": [cat.cards[i].key for i in wcs], "style": req.style,
            },
            "comparison": self._comparison(results),
            "note": ("Busca local iterada sobre combinações de 8 cartas avaliadas pelo mesmo motor da análise. "
                     f"{len(seen)} decks distintos avaliados."),
        }

    def _prune_pool(self, starts, pool, must, wcs, req, col, light) -> np.ndarray:
        """Pré-seleção: avalia uma vez todas as trocas a partir dos decks iniciais e mantém só as
        cartas mais promissoras (mais as obrigatórias, condições de vitória e as já usadas)."""
        cap = self.bcfg.get("pool_cap", 55) - (15 if light else 0)
        if len(pool) <= cap or not starts:
            return pool
        best = np.full(len(pool), -np.inf)
        pos_in_pool = {int(c): j for j, c in enumerate(pool)}
        for st in starts[: (2 if light else 4)]:
            cur = np.array(st)
            cand = pool[~np.isin(pool, cur)]
            pos = np.repeat(np.arange(8), len(cand))
            new = np.tile(cand, 8)
            batch = np.repeat(cur[None, :], len(pos), axis=0)
            batch[np.arange(len(pos)), pos] = new
            sc = self._score(batch, req, col).reshape(8, len(cand)).max(0)
            for c, v in zip(cand, sc):
                j = pos_in_pool[int(c)]
                best[j] = max(best[j], v)
        keep = set(pool[np.argsort(-best)[:cap]].tolist()) | set(must) | set(wcs)
        for st in starts:
            keep |= set(st)
        return np.array(sorted(keep))

    def _potential(self, req, col, pool, must, wcs, rng, shown: list[list[str]]) -> list[dict]:
        """1–2 decks extras que ficariam melhores se o jogador upasse cartas abaixo do nível de
        referência ou desbloqueasse Evoluções/Heróis de cartas que já tem."""
        cat = self.cat
        pot = copy.deepcopy(col)
        for i in pot.levels:
            pot.levels[i] = max(pot.levels[i], col.reference_level)
        pot.evolutions |= {i for i in pot.levels if cat.cards[i].evo}
        pot.heroes |= {i for i in pot.levels if cat.cards[i].has("hero")}
        seen = self._search(req, pot, pool, must, wcs, rng, light=True)
        shown_idx = [{cat.by_key[k].idx for k in d} for d in shown]
        cands = [d for d, _s in sorted(seen.items(), key=lambda kv: -kv[1])[:80]
                 if all(len(set(d) - sd) >= 2 for sd in shown_idx)]
        if not cands:
            return []
        arr = np.array(cands)
        gain = self.engine.evaluate(arr, pot)["ev"] - self.engine.evaluate(arr, col)["ev"]  # em lote
        out = []
        for j in np.argsort(-gain):
            deck = cands[j]
            if gain[j] < 0.01 or any(len(set(deck) - sd) < 2 for sd in shown_idx):
                continue
            now = self.engine.analyze(list(deck), col)
            future = self.engine.analyze(list(deck), pot)
            ups = [{"card": cat.cards[i].key, "from": col.levels[i], "to": col.reference_level}
                   for i in deck if col.levels.get(i, col.reference_level) < col.reference_level - 0.5]
            unlocks = [{"card": sl["card"], "kind": sl["form"]} for sl in future["slots"]
                       if sl["form"] != "normal" and cat.by_key[sl["card"]].idx not in
                       (col.evolutions if sl["form"] == "evo" else col.heroes)]
            if not ups and not unlocks:
                continue
            out.append({"analysis": now, "potential_ev": future["overall"]["ev"], "potential_slots": future["slots"],
                        "gain": round(future["overall"]["ev"] - now["overall"]["ev"], 4), "upgrades": ups, "unlocks": unlocks})
            shown_idx.append(set(deck))
            if len(out) >= self.bcfg.get("potential_k", 2):
                break
        return out

    def _select_diverse(self, ranked, must, req, limit) -> list[tuple]:
        """1ª passada: melhor deck de cada núcleo de condições de vitória (variedade de planos de jogo).
        2ª passada: completa com decks que diferem em pelo menos N cartas."""
        f = self.f
        ok = []
        for deck, s in ranked:
            if s < -5 or len(ok) >= 4000:
                break
            if must and not set(must) <= set(deck):
                continue
            if req.style and req.style not in self.engine.clf.classify(list(deck))[1]:
                continue
            ok.append((deck, s))
        chosen, cores = [], set()
        for deck, s in ok:
            core = tuple(sorted(c for c in deck if f["wc"][c] > 0))
            if core in cores:
                continue
            if all(len(set(deck) - set(c)) >= self.bcfg["min_distinct_cards"] for c, _ in chosen):
                chosen.append((deck, s))
                cores.add(core)
            if len(chosen) >= limit:
                return chosen
        for deck, s in ok:
            if all(len(set(deck) - set(c)) >= self.bcfg["min_distinct_cards"] for c, _ in chosen):
                chosen.append((deck, s))
            if len(chosen) >= limit:
                break
        return chosen

    def _known_decks(self, pool, must, req) -> list[list[int]]:
        out = []
        pset = set(pool.tolist())
        cands = [d["idx"] for d in self.engine.reference_decks]
        m = self.engine.model
        if m is not None:
            top = sorted(m.deck_stats.items(), key=lambda kv: -kv[1][0])[:300]
            for k, _ in top:
                cards = [self.cat.by_key.get(x) for x in k.split("|")]
                if None not in cards:
                    cands.append([c.idx for c in cards])
        for d in cands:
            if set(d) <= pset and set(must) <= set(d):
                out.append(list(d))
        return out[:20]

    def _why(self, r: dict, all_results: list[dict]) -> str:
        a = r["analysis"]
        best = sorted(a["matchups"], key=lambda m: -m["win_prob"])[:2]
        worst = min(a["matchups"], key=lambda m: m["win_prob"])
        txt = (f"#{r['rank']}: {a['archetype']['primary_pt']}, média {100 * a['overall']['ev']:.1f}% vs meta, "
               f"pior matchup {worst['name']} ({100 * worst['win_prob']:.1f}%). ")
        txt += f"Destaques: {', '.join(m['name'] for m in best)}. "
        if a["levels"].get("provided"):
            g = a["levels"]["effective_gap"]
            txt += f"Nível efetivo {g:+.2f} vs referência. "
        return txt

    def _comparison(self, results: list[dict]) -> list[dict]:
        rows = []
        for r in results:
            a = r["analysis"]
            rows.append({
                "rank": r["rank"], "deck": a["deck"], "archetype": a["archetype"]["primary"],
                "avg_elixir": a["avg_elixir"], "ev": a["overall"]["ev"], "worst": a["overall"]["worst"],
                "consistency_sd": a["overall"]["sd"], "score": a["overall"]["score"],
                "level_gap": a["levels"].get("effective_gap"),
                "confidence": a["confidence"]["level"],
                "by_archetype": {m["archetype"]: round(m["win_prob"], 3) for m in a["matchups"]},
            })
        return rows


def parse_style(style: str | None) -> str | None:
    if not style or style == "any":
        return None
    if style not in ARCHETYPES:
        raise DeckError(f"Estilo desconhecido: {style}. Opções: {', '.join(ARCHETYPES)}")
    return style


__all__ = ["DeckBuilder", "BuildRequest", "parse_style", "ARCH_PT"]
