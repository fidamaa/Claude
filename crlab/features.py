"""Extração vetorizada de características de decks.

Um lote de decks é uma matriz de índices de cartas (B x k). Todas as funções aceitam k=8 (deck
completo) ou k<8 (deck parcial, usado na busca e na análise "deixe-uma-de-fora").
"""
from __future__ import annotations

import json

import numpy as np

from .archetypes import DIMS
from .catalog import DATA_DIR, Catalog


def sat(x, k):
    """Saturação com retornos decrescentes: a 2ª carta de defesa aérea vale menos que a 1ª."""
    return 1.0 - np.exp(-np.asarray(x) / k)


class FeatureExtractor:
    def __init__(self, catalog: Catalog):
        self.catalog = catalog
        f = catalog.features
        self.f = f
        nonspell = 1 - f["spell"]
        self.v = {
            "air_def": nonspell * f["dpsa"] + 0.4 * f["spell"] * f["dpsa"],
            "air_spl": f["spl"] * (f["dpsa"] > 0),
            "ground_spl": f["spl"] * ((f["dpsg"] > 0) | (f["spell"] > 0)) * (1 - f["wc"]),
            "tank_kill": nonspell * np.maximum(f["dpsg"] - 0.25, 0) * (1 + 0.6 * f["tk"]),
            "bldg_def": (f["bldgdef"] * 1.0 + f["building"] * f["spawner"] * 0.5
                         + f["troop"] * (f["elixir"] <= 4) * (f["dpsg"] >= 0.5) * 0.5
                         + (f["kite"] + f["pull"]) * 0.4
                         + f["troop"] * (f["elixir"] <= 2) * (1 - f["bt"]) * 0.2),
            "cheap": (nonspell * (1 - f["bt"]) * (f["elixir"] <= 3)
                      * ((f["dpsg"] >= 0.3) | (f["dpsa"] >= 0.3) | (f["spl"] >= 0.3) | (f["minitank"] > 0))
                      + 0.7 * f["spell"] * (f["elixir"] <= 3) * (f["spl"] > 0) * (1 - f["wc"])),
            "reset": f["reset"],
            "pressure": (f["wc"] * f["tier"] / 5 + 0.6 * f["wc2"] * f["tier"] / 5
                         + 0.3 * f["troop"] * (1 - f["wc"]) * f["hp"] * np.maximum(f["dpsg"], f["dpsa"])),
            "siege_break": (0.8 * f["tank"] * f["hp"] + 0.8 * f["antibldg"] + 0.4 * f["big"]
                            + 0.4 * (f["wct_chip"] + f["wct_drill"] + f["wct_graveyard"])
                            + 0.3 * f["bt"] * (1 - f["tank"])),
            "counter": (f["troop"] * (1 - f["bt"]) * (f["hp"] >= 0.3) * f["hp"]
                        * np.maximum(f["dpsg"], f["dpsa"]) * 2 + 0.3 * f["champ"]),
            "def_vol": (nonspell * (1 - f["bt"]) * (0.6 * f["hp"] + 0.8 * np.maximum(f["dpsg"], f["dpsa"]) + 0.4 * f["spl"])),
            "anti_gy": (nonspell * f["spl"] * (f["dpsg"] > 0)
                        + 0.6 * f["spell"] * f["spl"] * (f["dpsg"] > 0) * (1 - f["wc"])
                        + 0.3 * f["bldgdef"]),
        }

    def capabilities(self, idx: np.ndarray) -> np.ndarray:
        """Retorna matriz B x len(DIMS) com capacidades em [0, 1]."""
        idx = np.atleast_2d(idx)
        v, f = self.v, self.f
        S = lambda name: v[name][idx].sum(1)  # noqa: E731
        el = f["elixir"][idx]
        cheapest4 = np.sort(el, axis=1)[:, :4].sum(1) * (4 / min(4, idx.shape[1]))
        small = f["small"][idx].max(1)
        big = np.maximum(f["big"][idx].max(1), f["antibldg"][idx].max(1))
        n_spell = f["spell"][idx].sum(1)
        cols = {
            "air_defense": sat(S("air_def"), 1.5),
            "air_swarm": sat(S("air_spl"), 0.8),
            "ground_swarm": sat(S("ground_spl"), 1.0),
            "tank_killing": sat(S("tank_kill"), 1.4),
            "building_def": sat(S("bldg_def"), 1.2),
            "cheap_answers": sat(S("cheap"), 2.5),
            "cycle": np.clip((14 - cheapest4) / 8, 0, 1),
            "elixir_eff": np.clip((4.7 - el.mean(1)) / 2.0, 0, 1),
            "spells": np.clip(0.45 * small + 0.45 * big + 0.1 * (n_spell >= 2), 0, 1),
            "reset": sat(S("reset"), 0.8),
            "pressure": sat(S("pressure"), 1.3),
            "siege_breaking": sat(S("siege_break"), 1.2),
            "counterattack": sat(S("counter"), 1.0),
            "anti_graveyard": sat(S("anti_gy"), 1.2),
            "defense_volume": sat(S("def_vol"), 3.0),
        }
        return np.stack([cols[d] for d in DIMS], axis=1)

    def quality(self, idx: np.ndarray) -> np.ndarray:
        """Força teórica média (prior heurístico do catálogo), em [0, 1]."""
        return self.f["tier"][np.atleast_2d(idx)].mean(1) / 5

    # ---------------------------------------------------------------- coerência estrutural
    def coherence(self, idx: np.ndarray) -> np.ndarray:
        idx = np.atleast_2d(idx)
        pen = self._coherence_penalties(idx)
        return np.clip(1 - sum(p for p, _ in pen.values()), 0, 1)

    def _coherence_penalties(self, idx: np.ndarray) -> dict[str, tuple[np.ndarray, str]]:
        f = self.f
        cnt = lambda name: f[name][idx].sum(1)  # noqa: E731
        avg = f["elixir"][idx].mean(1)
        n_wc, n_wc2 = cnt("wc"), cnt("wc2")
        has_siege = cnt("wct_siege") > 0
        heavy_tanks = (f["tank"] * (f["elixir"] >= 6))[idx].sum(1)
        fast_wc = (cnt("wct_hog") + cnt("wct_drill") + cnt("wct_chip") + cnt("wct_bait")) > 0
        n_bldg = (f["building"] * (1 - f["wc"]))[idx].sum(1)
        return {
            "no_wc": (np.where(n_wc == 0, np.where(n_wc2 > 0, 0.2, 0.5), 0.0),
                      "Sem condição de vitória clara: o deck depende de dano indireto para derrubar torres."),
            "many_wc": (0.15 * np.maximum(n_wc - 2, 0),
                        "Muitas condições de vitória principais: o plano de jogo fica disperso."),
            "siege_beat": (0.3 * (has_siege & ((cnt("wct_beatdown") + cnt("wct_air")) > 0)),
                           "Mistura siege com beatdown: planos de jogo incompatíveis."),
            "no_spell": (0.25 * (cnt("spell") == 0),
                         "Nenhum feitiço: difícil lidar com enxames e finalizar torres."),
            "many_big": (0.2 * (cnt("big") >= 3), "Três ou mais feitiços pesados: pouca defesa por elixir."),
            "many_spells": (0.15 * (cnt("spell") >= 4), "Quatro ou mais feitiços: faltam tropas para defender."),
            "many_bldg": (0.15 * (n_bldg >= 3), "Muitas construções defensivas: pouca pressão ofensiva."),
            "heavy_tanks": (0.2 * (heavy_tanks >= 2), "Dois tanques de 6+ de elixir: ciclo lento e previsível."),
            "too_heavy": (0.2 * (avg > 4.6), "Custo médio muito alto (acima de 4.6)."),
            "fast_heavy": (0.1 * (fast_wc & (avg > 4.3)),
                           "Condição de vitória rápida em deck pesado: perde a vantagem de ciclar a ameaça."),
            "champions": (1.0 * (cnt("champ") > 1), "Mais de um campeão: deck inválido."),
            "lava_support": (0.25 * ((cnt("wct_air") > 0) & (cnt("tank") * cnt("flying") > 0)
                                     & ((f["flying"] * (1 - f["bt"]) * (f["dpsa"] > 0))[idx].sum(1) < 2)),
                             "Lava sem suporte aéreo suficiente (precisa de 2+ tropas aéreas de dano)."),
            "tank_support": (0.2 * (((f["tank"] * f["bt"] * (f["elixir"] >= 5))[idx].sum(1) > 0)
                                    & ((f["troop"] * (1 - f["bt"]) * ((f["ranged"] + f["spawner"] + f["flying"]) > 0))[idx].sum(1) < 2)),
                             "Tanque sem suporte (precisa de 2+ tropas de apoio à distância/voadoras atrás dele)."),
            "two_win_spells": (0.2 * ((cnt("wct_graveyard") + cnt("wct_bait") + cnt("wct_spell")) >= 2),
                               "Duas condições de vitória em forma de feitiço: pouca defesa e dano previsível."),
        }

    def coherence_issues(self, idx) -> list[str]:
        pen = self._coherence_penalties(np.atleast_2d(idx))
        return [msg for p, msg in pen.values() if float(p[0]) > 0]


class SynergyModel:
    """Matriz de sinergia entre pares (heurística + regras genéricas, opcionalmente ajustada por dados)."""

    def __init__(self, catalog: Catalog):
        self.catalog = catalog
        n = catalog.n
        S = np.zeros((n, n))
        reasons: dict[tuple[int, int], str] = {}
        cs = catalog.cards
        # Regras genéricas (fracas) a partir das tags
        for a in cs:
            for b in cs:
                if a.idx >= b.idx:
                    continue
                v, why = 0.0, None
                for x, y in ((a, b), (b, a)):
                    if x.has("wc") and x.has("tank") and y.has("ranged") and y.dpsa >= 0.3 and not y.is_building:
                        v, why = 0.15, f"{y.name_pt} dá suporte à distância atrás do {x.name_pt}"
                    if x.key == "Goblin Barrel" and y.has("bait"):
                        v, why = 0.25, f"{y.name_pt} isca o mesmo feitiço que responde ao Barril"
                    if x.has("wct_siege") and y.has("bldgdef"):
                        v, why = 0.2, f"{y.name_pt} protege a construção de siege"
                    if x.key == "Graveyard" and y.has("tank"):
                        v, why = 0.3, f"{y.name_pt} tanka a torre para o Cemitério"
                if a.is_champion and b.is_champion:
                    v, why = -1.0, "Dois campeões não podem estar no mesmo deck"
                if v:
                    S[a.idx, b.idx] = S[b.idx, a.idx] = v
                    reasons[(a.idx, b.idx)] = why
        data = json.loads((DATA_DIR / "synergies.json").read_text(encoding="utf-8"))
        for ka, kb, v, why in data["pairs"]:
            a, b = catalog.by_key[ka].idx, catalog.by_key[kb].idx
            S[a, b] = S[b, a] = v
            reasons[(min(a, b), max(a, b))] = why
        self.heuristic = S
        self.matrix = S.copy()
        self.reasons = reasons
        self.data_lift: np.ndarray | None = None
        self.data_n: np.ndarray | None = None

    def apply_data(self, lift: np.ndarray, n: np.ndarray, k: float = 300.0):
        """Combina a sinergia heurística com o 'lift' observado em dados (ponderado pela amostra)."""
        w = n / (n + k)
        self.data_lift, self.data_n = lift, n
        self.matrix = (1 - w) * self.heuristic + w * np.clip(lift, -1, 1)

    def raw(self, idx: np.ndarray) -> np.ndarray:
        idx = np.atleast_2d(idx)
        k = idx.shape[1]
        tot = np.zeros(idx.shape[0])
        for i in range(k):
            for j in range(i + 1, k):
                tot += self.matrix[idx[:, i], idx[:, j]]
        return tot

    def score(self, idx: np.ndarray) -> np.ndarray:
        return np.tanh(self.raw(idx) / 1.5)

    def pairs(self, idx) -> list[dict]:
        idx = list(idx)
        out = []
        for i in range(len(idx)):
            for j in range(i + 1, len(idx)):
                a, b = sorted((idx[i], idx[j]))
                v = float(self.matrix[a, b])
                if abs(v) < 0.05:
                    continue
                item = {
                    "cards": [self.catalog.cards[a].key, self.catalog.cards[b].key],
                    "value": round(v, 2),
                    "reason": self.reasons.get((a, b), "Combinação observada nos dados"),
                    "source": "heurística",
                }
                if self.data_n is not None and self.data_n[a, b] > 0:
                    item["source"] = f"heurística + dados ({int(self.data_n[a, b])} partidas)"
                    item["data_lift"] = round(float(self.data_lift[a, b]), 3)
                out.append(item)
        return sorted(out, key=lambda x: -abs(x["value"]))
