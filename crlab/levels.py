"""Coleção do jogador: cartas possuídas, níveis, evoluções e campeões.

Níveis usam a escala unificada (1..16). A "referência" é o nível típico dos adversários do
jogador: por padrão, o percentil 75 dos níveis das cartas dele (o matchmaking por troféus
costuma emparelhar com o nível das melhores cartas). Pode ser informado manualmente.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .catalog import Catalog


@dataclass
class PlayerCollection:
    levels: dict[int, float] = field(default_factory=dict)  # idx -> nível
    evolutions: set[int] = field(default_factory=set)
    reference_level: float | None = None
    warnings: list[str] = field(default_factory=list)

    @classmethod
    def from_dict(cls, catalog: Catalog, data: dict | None) -> "PlayerCollection | None":
        """Formato: {"cards": {"Hog Rider": 14, ...} ou [{"name":..., "level":...}],
        "evolutions": [...], "reference_level": 14}"""
        if not data:
            return None
        col = cls()
        cards = data.get("cards", {})
        items = cards.items() if isinstance(cards, dict) else ((c["name"], c.get("level")) for c in cards)
        for name, lvl in items:
            card = catalog.find(name)
            if card is None:
                col.warnings.append(f"Carta ignorada (desconhecida): {name}")
                continue
            col.levels[card.idx] = float(lvl) if lvl is not None else np.nan
        for name in data.get("evolutions", []):
            card = catalog.find(name)
            if card is None:
                col.warnings.append(f"Evolução ignorada (carta desconhecida): {name}")
                continue
            if not card.evo:
                col.warnings.append(f"{card.name_pt}: o catálogo não registra evolução; considerada mesmo assim.")
            col.evolutions.add(card.idx)
            col.levels.setdefault(card.idx, np.nan)
        known = [v for v in col.levels.values() if not np.isnan(v)]
        if data.get("reference_level") is not None:
            col.reference_level = float(data["reference_level"])
        elif known:
            col.reference_level = float(np.percentile(known, 75))
        # Nível desconhecido -> assume a referência (neutro)
        for k, v in col.levels.items():
            if np.isnan(v):
                col.levels[k] = col.reference_level if col.reference_level is not None else 14.0
        if col.reference_level is None:
            col.reference_level = 14.0
        return col

    @property
    def owned(self) -> list[int]:
        return sorted(self.levels)


class LevelModel:
    """Converte níveis em um deslocamento de logit, com sensibilidade por tipo de carta."""

    def __init__(self, catalog: Catalog, cfg: dict):
        self.catalog = catalog
        self.cfg = cfg
        lv = cfg["levels"]
        f = catalog.features
        sens = np.full(catalog.n, lv["sensitivity"]["default"])
        sens[f["swarm"] > 0] = lv["sensitivity"]["swarm"]
        sens[f["spell"] > 0] = lv["sensitivity"]["spell"]
        self.sensitivity = sens
        self.gamma = lv["gamma_per_level"]

    def gaps(self, idx: np.ndarray, col: PlayerCollection | None) -> np.ndarray:
        """Diferença de nível efetiva média do deck (B,), incluindo bônus de evolução."""
        idx = np.atleast_2d(idx)
        if col is None:
            return np.zeros(idx.shape[0])
        lv = self.cfg["levels"]
        lvl = np.full(self.catalog.n, col.reference_level)
        for k, v in col.levels.items():
            lvl[k] = v
        evo = np.zeros(self.catalog.n)
        for k in col.evolutions:
            evo[k] = lv["evo_bonus_levels"] * (0.5 + self.catalog.cards[k].tier / 10)
        g = lvl[idx] - col.reference_level
        e = np.sort(evo[idx], axis=1)[:, ::-1][:, : lv["max_evolutions"]].sum(1)
        s = self.sensitivity[idx]
        return ((g * s).sum(1) + e) / s.sum(1)

    def evo_slots(self, idx, col: PlayerCollection | None) -> list[int]:
        if col is None:
            return []
        cands = [i for i in idx if i in col.evolutions]
        cands.sort(key=lambda i: -self.catalog.cards[i].tier)
        return cands[: self.cfg["levels"]["max_evolutions"]]

    def logit_shift(self, gaps: np.ndarray) -> np.ndarray:
        return self.gamma * gaps

    def level_score(self, gaps: np.ndarray) -> np.ndarray:
        """Fator 'níveis' em [0,1]: 1 = no nível de referência ou acima; 0 = 4+ níveis abaixo."""
        return np.clip(1 + gaps / 4, 0, 1)

    def card_detail(self, idx: list[int], col: PlayerCollection | None) -> list[dict]:
        out = []
        per = self.cfg["levels"]["stat_per_level"]
        evo_used = set(self.evo_slots(idx, col))
        for i in idx:
            c = self.catalog.cards[i]
            if col is None:
                out.append({"card": c.key, "level": None, "gap": 0.0, "stat_factor": 1.0, "evolution": False})
                continue
            lvl = col.levels.get(i)
            owned = lvl is not None
            lvl = lvl if owned else col.reference_level
            gap = lvl - col.reference_level
            out.append({
                "card": c.key, "level": lvl, "owned": owned, "gap": round(gap, 2),
                "stat_factor": round((1 + per) ** gap, 3),
                "evolution": i in evo_used,
            })
        return out
