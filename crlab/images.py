"""Imagens das cartas (arte oficial da Supercell, via repositório público RoyaleAPI/cr-api-assets).

O servidor baixa cada imagem uma vez, guarda em disco e serve com cache longo. Só nomes do
catálogo são aceitos (sem URLs arbitrárias). Conteúdo de fã, conforme a Fan Content Policy da Supercell.
"""
from __future__ import annotations

import re
import urllib.error
import urllib.request
from pathlib import Path

from .catalog import Catalog

ASSETS_BASE = "https://raw.githubusercontent.com/RoyaleAPI/cr-api-assets/master"
SIZES = {"s": "cards-75", "l": "cards"}  # 75x90 (~13 KB) e 302x363 (~130 KB)


def card_slug(key: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", key.lower().replace(".", "")).strip("-")


class CardImages:
    def __init__(self, catalog: Catalog, cache_dir: str | Path):
        self.cache = Path(cache_dir)
        self.slugs = {card_slug(c.key) for c in catalog.cards}
        self.evo_slugs = {card_slug(c.key) for c in catalog.cards if c.evo}

    def valid(self, size: str, name: str) -> bool:
        if size not in SIZES:
            return False
        base = name[:-4] if name.endswith("-ev1") else name
        return base in self.slugs and (name == base or base in self.evo_slugs)

    def get(self, size: str, name: str) -> bytes | None:
        """Bytes do PNG ou None (inexistente/indisponível)."""
        if not self.valid(size, name):
            return None
        path = self.cache / SIZES[size] / f"{name}.png"
        missing = path.with_suffix(".missing")
        if path.exists():
            return path.read_bytes()
        if missing.exists():
            return None
        try:
            with urllib.request.urlopen(f"{ASSETS_BASE}/{SIZES[size]}/{name}.png", timeout=15) as resp:
                data = resp.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                missing.parent.mkdir(parents=True, exist_ok=True)
                missing.touch()
            return None
        except (urllib.error.URLError, TimeoutError, OSError):
            return None
        if not data.startswith(b"\x89PNG"):
            return None
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return data
