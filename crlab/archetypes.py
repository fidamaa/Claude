"""Arquétipos: definição, classificação de decks e perfil de demandas (o que cada arquétipo exige
do deck adversário). Os pesos de demanda são heurísticos e podem ser recalibrados com dados reais
(ver crlab/datamodel.py)."""
from __future__ import annotations

import numpy as np

from .catalog import Catalog

ARCHETYPES = ["cycle", "beatdown", "bridge_spam", "siege", "bait", "control", "lava", "graveyard", "hog",
              "royal_giant", "drill"]
A_INDEX = {a: i for i, a in enumerate(ARCHETYPES)}

ARCH_PT = {
    "cycle": "Ciclo rápido",
    "beatdown": "Beatdown",
    "bridge_spam": "Bridge spam",
    "siege": "Siege (X-Besta/Morteiro)",
    "bait": "Bait (isca de feitiço)",
    "control": "Controle",
    "lava": "Lava (aéreo)",
    "graveyard": "Cemitério",
    "hog": "Corredor (Hog)",
    "royal_giant": "Gigante Real",
    "drill": "Broca Goblin",
}

# Dimensões de capacidade (ver crlab/features.py)
DIMS = ["air_defense", "air_swarm", "ground_swarm", "tank_killing", "building_def", "cheap_answers", "cycle",
        "elixir_eff", "spells", "reset", "pressure", "siege_breaking", "counterattack", "anti_graveyard",
        "defense_volume"]
D_INDEX = {d: i for i, d in enumerate(DIMS)}

# O que cada arquétipo ADVERSÁRIO exige do seu deck (pesos relativos; normalizados para somar 1).
DEMANDS = {
    "cycle": {"cheap_answers": .25, "cycle": .2, "building_def": .15, "elixir_eff": .15, "spells": .1,
              "ground_swarm": .05, "pressure": .1},
    "beatdown": {"tank_killing": .3, "pressure": .2, "air_swarm": .1, "air_defense": .1, "spells": .1,
                 "counterattack": .1, "defense_volume": .15},
    "bridge_spam": {"cheap_answers": .15, "tank_killing": .2, "building_def": .15, "ground_swarm": .15,
                    "cycle": .05, "counterattack": .1, "spells": .05, "defense_volume": .15},
    "siege": {"siege_breaking": .35, "spells": .15, "cheap_answers": .15, "cycle": .15, "pressure": .2},
    "bait": {"spells": .25, "ground_swarm": .25, "air_swarm": .2, "cheap_answers": .15, "tank_killing": .05,
             "cycle": .1},
    "control": {"pressure": .3, "counterattack": .2, "siege_breaking": .1, "spells": .1, "elixir_eff": .1,
                "tank_killing": .1, "defense_volume": .1},
    "lava": {"air_defense": .4, "air_swarm": .25, "spells": .1, "tank_killing": .05, "pressure": .1,
             "defense_volume": .1},
    "graveyard": {"anti_graveyard": .35, "ground_swarm": .1, "air_defense": .1, "tank_killing": .1,
                  "pressure": .2, "spells": .05, "defense_volume": .1},
    "hog": {"building_def": .35, "cheap_answers": .25, "cycle": .15, "spells": .1, "ground_swarm": .05,
            "pressure": .1},
    "royal_giant": {"tank_killing": .3, "building_def": .2, "pressure": .15, "spells": .05, "counterattack": .1,
                    "cycle": .05, "defense_volume": .15},
    "drill": {"building_def": .2, "ground_swarm": .25, "cheap_answers": .25, "cycle": .1, "spells": .1,
              "pressure": .1},
}


def demand_matrix() -> np.ndarray:
    m = np.zeros((len(ARCHETYPES), len(DIMS)))
    for a, w in DEMANDS.items():
        for d, v in w.items():
            m[A_INDEX[a], D_INDEX[d]] = v
        m[A_INDEX[a]] /= m[A_INDEX[a]].sum()
    return m


class ArchetypeClassifier:
    """Classificação por regras (vetorizada). Primário = família mais específica; rótulos = multi-label."""

    BRIDGE_HEAVY = ["P.E.K.K.A", "Mega Knight", "Ram Rider", "Royal Hogs", "Battle Ram", "Elite Barbarians"]

    def __init__(self, catalog: Catalog):
        self.catalog = catalog
        n = catalog.n
        f = catalog.features

        def ind(*keys):
            v = np.zeros(n)
            for k in keys:
                if k in catalog.by_key:
                    v[catalog.by_key[k].idx] = 1
            return v

        self.ind = {
            "lava": ind("Lava Hound"), "graveyard": ind("Graveyard"), "siege": ind("X-Bow", "Mortar"),
            "drill": ind("Goblin Drill"), "bait": ind("Goblin Barrel"), "royal_giant": ind("Royal Giant"),
            "hog": ind("Hog Rider"), "balloon": ind("Balloon"),
            "bridge_heavy": ind(*self.BRIDGE_HEAVY),
        }
        self.beat = f["wct_beatdown"]
        self.bridge_piece = np.clip(f["wct_bridge"] + f["wct_hog"] - self.ind["hog"], 0, 1)
        self.heavy_tank = f["tank"] * f["wc"] * (f["elixir"] >= 5) * (1 - self.ind["royal_giant"]) * (1 - self.ind["lava"])
        self.elixir = f["elixir"]

    def classify_batch(self, idx: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        idx = np.atleast_2d(idx)
        B = idx.shape[0]
        has = {k: v[idx].sum(1) > 0 for k, v in self.ind.items()}
        avg = self.elixir[idx].mean(1)
        n_beat = self.beat[idx].sum(1)
        n_bridge = self.bridge_piece[idx].sum(1)
        primary = np.full(B, -1)

        def assign(mask, name):
            sel = (primary < 0) & mask
            primary[sel] = A_INDEX[name]

        for name in ["lava", "graveyard", "siege", "drill", "bait", "royal_giant", "hog"]:
            assign(has[name], name)
        assign(n_beat > 0, "beatdown")
        assign(has["bridge_heavy"] | ((n_bridge >= 2) & (avg >= 3.3)), "bridge_spam")
        assign(avg <= 3.0, "cycle")
        assign(has["balloon"], "beatdown")
        assign(np.ones(B, bool), "control")

        labels = np.zeros((B, len(ARCHETYPES)), bool)
        labels[np.arange(B), primary] = True
        labels[:, A_INDEX["cycle"]] |= avg <= 3.0
        labels[:, A_INDEX["beatdown"]] |= self.heavy_tank[idx].sum(1) > 0
        labels[:, A_INDEX["bridge_spam"]] |= n_bridge >= 2
        return primary, labels

    def classify(self, idx) -> tuple[str, list[str]]:
        p, labels = self.classify_batch(np.asarray(idx)[None, :])
        return ARCHETYPES[p[0]], [ARCHETYPES[i] for i in np.flatnonzero(labels[0])]
