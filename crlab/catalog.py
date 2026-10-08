"""Catálogo de cartas: carregamento, busca por nome/apelido e matriz de atributos."""
from __future__ import annotations

import csv
import difflib
import unicodedata
from dataclasses import dataclass
from functools import cached_property
from pathlib import Path

import numpy as np

DATA_DIR = Path(__file__).parent / "data"

TAG_DOC = {
    "wc": "condição de vitória principal",
    "wc2": "condição de vitória secundária",
    "wct_*": "tipo de condição de vitória (beatdown, air, hog, rg, siege, bait, chip, bridge, drill, graveyard, spell)",
    "tank": "tanque (muita vida)",
    "minitank": "mini tanque",
    "tk": "alto dano concentrado (mata tanques)",
    "swarm": "enxame (morre para feitiço pequeno)",
    "airswarm": "enxame aéreo",
    "flying": "tropa voadora",
    "bt": "mira apenas construções",
    "bldgdef": "construção defensiva",
    "spawner": "gera tropas",
    "small": "feitiço pequeno",
    "big": "feitiço pesado",
    "antibldg": "forte contra construções",
    "reset": "reseta/atordoa (Inferno, Sparky)",
    "knock": "empurra tropas",
    "kite": "puxa/desvia tropas",
    "pull": "agrupa/puxa tropas",
    "champ": "campeão",
    "bait": "isca de feitiço",
    "ranged": "ataque à distância",
}

# Apelidos comuns (normalizados na carga). Nomes em inglês e pt-BR já são aceitos.
ALIASES = {
    "Hog Rider": ["hog", "porco", "corredor"],
    "P.E.K.K.A": ["pekka", "peka"],
    "Mini P.E.K.K.A": ["mini pekka", "minipekka", "mp"],
    "The Log": ["log", "tronco"],
    "X-Bow": ["xbow", "x bow", "besta", "xbesta"],
    "Mega Knight": ["mk", "mega cavaleiro"],
    "Electro Wizard": ["ewiz", "e wiz", "mago eletrico"],
    "Electro Giant": ["egiant", "e giant"],
    "Electro Dragon": ["edrag", "e dragon"],
    "Royal Giant": ["rg"],
    "Lava Hound": ["lava", "cao de lava", "lavahound"],
    "Goblin Barrel": ["barril", "gob barrel", "barril goblin"],
    "Skeleton Army": ["skarmy", "exercito"],
    "Inferno Tower": ["inferno", "torre infernal"],
    "Inferno Dragon": ["infernal", "dragao inferno"],
    "Baby Dragon": ["bebe dragao", "baby"],
    "Barbarian Barrel": ["barb barrel", "barril de barbaros"],
    "Giant Snowball": ["snowball", "bola de neve"],
    "Three Musketeers": ["3m", "3 mosqueteiras"],
    "Goblin Drill": ["drill", "broca"],
    "Graveyard": ["gy", "cemiterio"],
    "Night Witch": ["nw", "bruxa noturna"],
    "Magic Archer": ["ma"],
    "Elixir Collector": ["pump", "coletor"],
    "Wall Breakers": ["wb", "destruidores"],
    "Archer Queen": ["aq", "rainha"],
    "Golden Knight": ["gk"],
    "Skeleton King": ["sk", "rei esqueleto"],
    "Mighty Miner": ["mm"],
    "Little Prince": ["lp"],
    "Bomb Tower": ["bt", "torre de bomba"],
    "Goblin Giant": ["gg"],
    "Ice Golem": ["ig"],
    "Ice Spirit": ["espirito de gelo"],
    "Electro Spirit": ["espirito eletrico"],
    "Fire Spirit": ["fire spirits", "espiritos de fogo"],
}

RARITY_ORDER = ["common", "rare", "epic", "legendary", "champion"]


def normalize(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return "".join(ch for ch in text.lower() if ch.isalnum())


class UnknownCardError(ValueError):
    def __init__(self, name: str, suggestions: list[str]):
        self.name = name
        self.suggestions = suggestions
        hint = f" Você quis dizer: {', '.join(suggestions)}?" if suggestions else ""
        super().__init__(f"Carta desconhecida: '{name}'.{hint}")


@dataclass(frozen=True)
class Card:
    idx: int
    key: str
    name_pt: str
    elixir: int
    type: str
    rarity: str
    hp: float
    dpsg: float
    dpsa: float
    spl: float
    tier: float
    evo: bool
    tags: frozenset

    @property
    def is_spell(self) -> bool:
        return self.type == "spell"

    @property
    def is_building(self) -> bool:
        return self.type == "building"

    @property
    def is_champion(self) -> bool:
        return "champ" in self.tags

    @property
    def wc_type(self) -> str | None:
        for t in self.tags:
            if t.startswith("wct_"):
                return t[4:]
        return None

    def has(self, tag: str) -> bool:
        return tag in self.tags

    def to_dict(self) -> dict:
        return {
            "key": self.key, "name_pt": self.name_pt, "elixir": self.elixir, "type": self.type,
            "rarity": self.rarity, "tier": self.tier, "evo": self.evo, "tags": sorted(self.tags),
        }


class Catalog:
    def __init__(self, cards: list[Card]):
        self.cards = cards
        self.n = len(cards)
        self.by_key = {c.key: c for c in cards}
        self._lookup: dict[str, int] = {}
        for c in cards:
            self._lookup[normalize(c.key)] = c.idx
            self._lookup.setdefault(normalize(c.name_pt), c.idx)
        for key, aliases in ALIASES.items():
            if key in self.by_key:
                for a in aliases:
                    self._lookup.setdefault(normalize(a), self.by_key[key].idx)

    @classmethod
    def load(cls, path: Path | None = None) -> "Catalog":
        path = path or DATA_DIR / "cards.csv"
        with open(path, encoding="utf-8") as fh:
            rows = [line for line in fh if line.strip() and not line.startswith("#")]
        cards = []
        for i, row in enumerate(csv.DictReader(rows, delimiter=";")):
            cards.append(Card(
                idx=i, key=row["key"], name_pt=row["name_pt"], elixir=int(row["elixir"]),
                type=row["type"], rarity=row["rarity"],
                hp=float(row["hp"]) / 10, dpsg=float(row["dpsg"]) / 10, dpsa=float(row["dpsa"]) / 10,
                spl=float(row["spl"]) / 10, tier=float(row["tier"]), evo=row["evo"] == "1",
                tags=frozenset((row["tags"] or "").split()),
            ))
        return cls(cards)

    def find(self, name: str) -> Card | None:
        idx = self._lookup.get(normalize(name))
        return None if idx is None else self.cards[idx]

    def resolve(self, name: str) -> Card:
        card = self.find(name)
        if card is None:
            names = list(self._lookup)
            close = difflib.get_close_matches(normalize(name), names, n=3, cutoff=0.6)
            raise UnknownCardError(name, sorted({self.cards[self._lookup[c]].key for c in close}))
        return card

    def resolve_many(self, names) -> list[Card]:
        return [self.resolve(n) for n in names]

    @cached_property
    def features(self) -> dict[str, np.ndarray]:
        """Atributos por carta como vetores (usados na avaliação vetorizada de lotes de decks)."""
        cs = self.cards
        f = {
            "elixir": np.array([c.elixir for c in cs], float),
            "hp": np.array([c.hp for c in cs]),
            "dpsg": np.array([c.dpsg for c in cs]),
            "dpsa": np.array([c.dpsa for c in cs]),
            "spl": np.array([c.spl for c in cs]),
            "tier": np.array([c.tier for c in cs]),
            "spell": np.array([c.is_spell for c in cs], float),
            "building": np.array([c.is_building for c in cs], float),
        }
        f["troop"] = 1 - f["spell"] - f["building"]
        for tag in ["wc", "wc2", "tank", "minitank", "tk", "swarm", "airswarm", "flying", "bt", "bldgdef",
                    "spawner", "small", "big", "antibldg", "reset", "knock", "kite", "pull", "champ", "bait",
                    "ranged", "pump", "freeze"]:
            f[tag] = np.array([c.has(tag) for c in cs], float)
        for wct in ["beatdown", "air", "hog", "rg", "siege", "bait", "chip", "bridge", "drill", "graveyard", "spell"]:
            f["wct_" + wct] = np.array([c.has("wct_" + wct) for c in cs], float)
        return f


_CATALOG: Catalog | None = None


def get_catalog() -> Catalog:
    global _CATALOG
    if _CATALOG is None:
        _CATALOG = Catalog.load()
    return _CATALOG
