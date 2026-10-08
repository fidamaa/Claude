"""Coleção do jogador: cartas possuídas, níveis, evoluções, heróis e as posições especiais do deck.

Posições especiais (regra do jogo): a 1ª aceita carta normal ou Evolução; a 2ª, normal ou Herói;
a 3ª, normal, Evolução ou Herói. As demais só aceitam cartas normais. Logo, um deck é válido se
tiver no máximo 2 Evoluções, no máximo 2 Heróis e no máximo 3 formas especiais no total.

Níveis usam a escala unificada (1..16). A "referência" é o nível típico dos adversários do
jogador: por padrão, o percentil 75 dos níveis das cartas dele (o matchmaking por troféus
costuma emparelhar com o nível das melhores cartas). Pode ser informado manualmente.
"""
from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .catalog import Catalog

NORMAL, EVO, HERO = 0, 1, 2
FORM_NAMES = {NORMAL: "normal", EVO: "evo", HERO: "hero"}
FORM_CODES = {v: k for k, v in FORM_NAMES.items()}
SLOT_ALLOWED = [{NORMAL, EVO}, {NORMAL, HERO}, {NORMAL, EVO, HERO}] + [{NORMAL}] * 5


def forms_valid(forms) -> bool:
    f = list(forms)
    e, h = f.count(EVO), f.count(HERO)
    return e <= 2 and h <= 2 and e + h <= 3


def arrange_slots(idx: list[int], forms: list[int]) -> tuple[list[int], list[int]]:
    """Ordena o deck nas posições do jogo: Evo na 1ª, Herói na 2ª, o restante especial na 3ª."""
    pairs = list(zip(idx, forms))
    evo = [p for p in pairs if p[1] == EVO]
    hero = [p for p in pairs if p[1] == HERO]
    normal = [p for p in pairs if p[1] == NORMAL]
    slots: list = [None, None, None]
    if evo:
        slots[0] = evo.pop(0)
    if hero:
        slots[1] = hero.pop(0)
    rest_special = evo + hero
    if rest_special:
        slots[2] = rest_special.pop(0)
    for i in range(3):
        if slots[i] is None and normal:
            slots[i] = normal.pop(0)
    ordered = [p for p in slots if p is not None] + normal
    return [p[0] for p in ordered], [p[1] for p in ordered]


@dataclass
class PlayerCollection:
    levels: dict[int, float] = field(default_factory=dict)  # idx -> nível
    evolutions: set[int] = field(default_factory=set)
    heroes: set[int] = field(default_factory=set)
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
        for name in data.get("heroes", []):
            card = catalog.find(name)
            if card is None:
                col.warnings.append(f"Herói ignorado (carta desconhecida): {name}")
                continue
            if not card.has("hero"):
                col.warnings.append(f"{card.name_pt}: o catálogo não registra versão Herói; considerada mesmo assim.")
            col.heroes.add(card.idx)
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
        """Diferença de nível média do deck (B,), ponderada pela sensibilidade de cada carta."""
        idx = np.atleast_2d(idx)
        if col is None:
            return np.zeros(idx.shape[0])
        lvl = np.full(self.catalog.n, col.reference_level)
        for k, v in col.levels.items():
            lvl[k] = v
        g = lvl[idx] - col.reference_level
        s = self.sensitivity[idx]
        return (g * s).sum(1) / s.sum(1)

    # ---------------------------------------------------------------- Evoluções e Heróis
    def form_values(self, col: PlayerCollection | None) -> tuple[np.ndarray, np.ndarray]:
        """Bônus (em níveis-equivalentes) de usar cada carta como Evo/Herói; 0 se indisponível.
        Sem coleção, considera todas as formas existentes disponíveis (análise teórica)."""
        lv = self.cfg["levels"]
        f = self.catalog.features
        tier = f["tier"]
        evo = np.array([c.evo for c in self.catalog.cards], float) * lv["evo_bonus_levels"] * (0.5 + tier / 10)
        hero = f["hero"] * lv["hero_bonus_levels"] * (0.5 + tier / 10)
        if col is not None:
            evo_mask = np.zeros(self.catalog.n)
            hero_mask = np.zeros(self.catalog.n)
            evo_mask[list(col.evolutions)] = 1
            hero_mask[list(col.heroes)] = 1
            evo = np.where(evo_mask > 0, np.maximum(evo, lv["evo_bonus_levels"] * 0.5), 0)
            hero = np.where(hero_mask > 0, np.maximum(hero, lv["hero_bonus_levels"] * 0.5), 0)
        return evo, hero

    def auto_forms(self, idx: np.ndarray, col: PlayerCollection | None, values=None) -> np.ndarray:
        """Melhor atribuição de formas (B x k) respeitando as posições especiais: até 2 Evos,
        até 2 Heróis, no máximo 3 no total, e uma carta não pode ser Evo e Herói ao mesmo tempo."""
        idx = np.atleast_2d(idx)
        ev_c, he_c = values if values is not None else self.form_values(col)
        Ev, Hv = ev_c[idx], he_c[idx]
        out = np.zeros(idx.shape, dtype=int)
        dual = ((Ev > 0) & (Hv > 0)).any(1)  # carta com Evo e Herói disponíveis: precisa enumerar
        if idx.shape[1] < 3:
            dual[:] = True
        fast = ~dual
        if fast.any():
            out[fast] = self._forms_closed(Ev[fast], Hv[fast])
        if dual.any():
            out[dual] = self._forms_enum(Ev[dual], Hv[dual])
        return out

    @staticmethod
    def _forms_closed(Ev, Hv) -> np.ndarray:
        """Sem cartas duplas: o ótimo é (2 Evos + 1 Herói) ou (1 Evo + 2 Heróis), o que valer mais."""
        B, k = Ev.shape
        rows = np.arange(B)
        te = np.argsort(-Ev, axis=1)[:, :2]
        th = np.argsort(-Hv, axis=1)[:, :2]
        e1, e2 = Ev[rows, te[:, 0]], Ev[rows, te[:, 1]] if k > 1 else np.zeros(B)
        h1, h2 = Hv[rows, th[:, 0]], Hv[rows, th[:, 1]] if k > 1 else np.zeros(B)
        two_evo = (e1 + e2 + h1) >= (e1 + h1 + h2)
        out = np.zeros((B, k), dtype=int)
        for pos, val, form, use in ((te[:, 0], e1, EVO, np.ones(B, bool)), (te[:, 1], e2, EVO, two_evo),
                                    (th[:, 0], h1, HERO, np.ones(B, bool)), (th[:, 1], h2, HERO, ~two_evo)):
            sel = use & (val > 0)
            out[rows[sel], pos[sel]] = form
        return out

    @staticmethod
    def _forms_enum(Ev, Hv) -> np.ndarray:
        B, k = Ev.shape
        te = np.argsort(-Ev, axis=1)[:, :3]
        th = np.argsort(-Hv, axis=1)[:, :3]
        subsets = [(), (0,), (1,), (2,), (0, 1), (0, 2), (1, 2)]
        rows = np.arange(B)
        best_val = np.zeros(B)
        best = np.zeros((B, k), dtype=int)
        for se in subsets:
            for sh in subsets:
                if len(se) + len(sh) > 3 or (not se and not sh) or max(se + sh, default=0) >= min(k, 3):
                    continue
                pe = [te[:, j] for j in se]
                ph = [th[:, j] for j in sh]
                val = np.zeros(B)
                ok = np.ones(B, bool)
                for p in pe:
                    v = Ev[rows, p]
                    val += v
                    ok &= v > 0
                for p in ph:
                    v = Hv[rows, p]
                    val += v
                    ok &= v > 0
                for x in pe:
                    for y in ph:
                        ok &= x != y
                better = ok & (val > best_val + 1e-12)
                if better.any():
                    best_val = np.where(better, val, best_val)
                    r = rows[better]
                    best[r] = 0
                    for p in pe:
                        best[r, p[better]] = EVO
                    for p in ph:
                        best[r, p[better]] = HERO
        return best

    def form_bonus(self, idx: np.ndarray, forms: np.ndarray, col: PlayerCollection | None, values=None) -> np.ndarray:
        """Bônus de formas em níveis-equivalentes médios do deck (mesma escala de gaps)."""
        idx = np.atleast_2d(idx)
        ev_c, he_c = values if values is not None else self.form_values(col)
        bonus = (ev_c[idx] * (forms == EVO) + he_c[idx] * (forms == HERO)).sum(1)
        return bonus / self.sensitivity[idx].sum(1)

    def logit_shift(self, gaps: np.ndarray) -> np.ndarray:
        return self.gamma * gaps

    def level_score(self, gaps: np.ndarray) -> np.ndarray:
        """Fator 'níveis' em [0,1]: 1 = no nível de referência ou acima; 0 = 4+ níveis abaixo."""
        return np.clip(1 + gaps / 4, 0, 1)

    def card_detail(self, idx: list[int], col: PlayerCollection | None, forms: list[int] | None = None) -> list[dict]:
        out = []
        per = self.cfg["levels"]["stat_per_level"]
        forms = forms if forms is not None else [NORMAL] * len(idx)
        for i, form in zip(idx, forms):
            c = self.catalog.cards[i]
            base = {"card": c.key, "form": FORM_NAMES[int(form)], "evolution": int(form) == EVO, "hero": int(form) == HERO}
            if col is None:
                out.append({**base, "level": None, "gap": 0.0, "stat_factor": 1.0})
                continue
            lvl = col.levels.get(i)
            owned = lvl is not None
            lvl = lvl if owned else col.reference_level
            gap = lvl - col.reference_level
            out.append({**base, "level": lvl, "owned": owned, "gap": round(gap, 2), "stat_factor": round((1 + per) ** gap, 3)})
        return out
