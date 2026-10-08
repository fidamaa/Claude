"""Sincroniza o catálogo com a API oficial (GET /cards).

* Cartas que existem no jogo mas não no catálogo são acrescentadas com atributos padrão por tipo
  e custo (o modelo de dados corrige com partidas reais) — assim a coleção do jogador nunca perde
  cartas novas.
* Guarda o ID oficial, as URLs de arte e quais cartas têm arte de Evolução/Herói na API.
Arquivos: <CRLAB_DATA_DIR>/cards_extra.csv e <CRLAB_DATA_DIR>/card_meta.json.
"""
from __future__ import annotations

import json
from pathlib import Path

from .catalog import Catalog

TYPE_BY_PREFIX = {26: "troop", 27: "building", 28: "spell"}


def _default_row(item: dict) -> list[str]:
    cid = int(item.get("id") or 0)
    ctype = TYPE_BY_PREFIX.get(cid // 1_000_000, "troop")
    elixir = int(item.get("elixirCost") or 3)
    rarity = str(item.get("rarity") or "common").lower()
    tags = []
    if rarity == "champion":
        tags.append("champ")
    if ctype == "troop":
        hp, dpsg, dpsa, spl = min(9, 1 + elixir), 4, 0, 0
    elif ctype == "building":
        hp, dpsg, dpsa, spl = 5, 4, 0, 0
        tags.append("bldgdef")
    else:
        hp, dpsg, dpsa, spl = 0, 4, 3, 4
        tags.append("small" if elixir <= 3 else "big")
    icons = item.get("iconUrls") or {}
    evo = "1" if "evolutionMedium" in icons else "0"
    name = item["name"]
    return [name, name, str(elixir), ctype, rarity, str(hp), str(dpsg), str(dpsa), str(spl), "3", evo, " ".join(tags)]


def sync_catalog(api, catalog: Catalog, out_dir: str | Path, log=print) -> dict:
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    data = api._get("/cards")
    items = list(data.get("items", []))
    meta = {"ids": {}, "icons": {}, "evo": [], "hero": [], "icon_keys": []}
    keys_seen: set[str] = set()
    new_rows = []
    for it in items:
        name = it.get("name")
        if not name:
            continue
        icons = it.get("iconUrls") or {}
        keys_seen |= set(icons)
        card = catalog.find(name)
        key = card.key if card else name
        meta["ids"][key] = it.get("id")
        meta["icons"][key] = icons
        if "evolutionMedium" in icons:
            meta["evo"].append(key)
        if any("hero" in k.lower() for k in icons):
            meta["hero"].append(key)
        if card is None:
            new_rows.append(_default_row(it))
    meta["icon_keys"] = sorted(keys_seen)
    header = "key;name_pt;elixir;type;rarity;hp;dpsg;dpsa;spl;tier;evo;tags"
    lines = ["# Cartas acrescentadas automaticamente pela API oficial (atributos padrão; ajustados pelos dados).", header]
    lines += [";".join(r) for r in new_rows]
    (out_dir / "cards_extra.csv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (out_dir / "card_meta.json").write_text(json.dumps(meta), encoding="utf-8")
    log(f"Catálogo sincronizado: {len(items)} cartas na API, {len(new_rows)} novas acrescentadas.")
    return {"api_cards": len(items), "added": [r[0] for r in new_rows], "icon_keys": meta["icon_keys"]}
