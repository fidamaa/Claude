"""Importadores de partidas a partir de arquivos.

Formatos aceitos:
  * JSONL normalizado (uma partida por linha):
      {"played_at": "2026-09-01T12:00:00+00:00", "source": "meu_dataset", "mode": "ladder",
       "a": {"cards": [8 nomes], "level": 14.1, "evolutions": [...], "crowns": 1},
       "b": {...}, "result": 1}
  * JSON/JSONL com entradas brutas do battlelog da API oficial (detectado automaticamente).
  * CSV com colunas: played_at, deck_a, deck_b, result [, level_a, level_b, mode, source, trophies]
    onde deck_a/deck_b são 8 nomes separados por ';' ou '|'.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

from .official_api import normalize_battle


def _from_obj(obj: dict, source: str | None) -> dict | None:
    if "battleTime" in obj:
        return normalize_battle(obj, source=source or "official_api")
    if "a" in obj and "b" in obj:
        obj.setdefault("source", source or "import")
        return obj
    return None


def read_json(path: str | Path, source: str | None = None) -> list[dict]:
    path = Path(path)
    text = path.read_text(encoding="utf-8").strip()
    objs = []
    if text.startswith("["):
        objs = json.loads(text)
    else:
        for line in text.splitlines():
            if line.strip():
                objs.append(json.loads(line))
    out = []
    for o in objs:
        nb = _from_obj(o, source)
        if nb:
            out.append(nb)
    return out


def read_csv(path: str | Path, source: str | None = None) -> list[dict]:
    out = []
    with open(path, encoding="utf-8") as fh:
        for row in csv.DictReader(fh):
            split = lambda s: [x.strip() for x in s.replace("|", ";").split(";") if x.strip()]  # noqa: E731
            num = lambda k: float(row[k]) if row.get(k) not in (None, "") else None  # noqa: E731
            out.append({
                "played_at": row["played_at"], "source": row.get("source") or source or "csv",
                "mode": row.get("mode"), "trophies": int(num("trophies")) if num("trophies") else None,
                "a": {"cards": split(row["deck_a"]), "level": num("level_a")},
                "b": {"cards": split(row["deck_b"]), "level": num("level_b")},
                "result": float(row["result"]),
            })
    return out


def read_any(path: str | Path, source: str | None = None) -> list[dict]:
    return read_csv(path, source) if str(path).lower().endswith(".csv") else read_json(path, source)
