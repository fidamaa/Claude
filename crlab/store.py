"""Armazenamento de partidas (SQLite).

O esquema é simples e portável (Postgres/DuckDB): uma linha por partida, decks como chave
canônica (cartas ordenadas, separadas por '|'). Para escala muito grande, exporte para Parquet
e treine o modelo a partir de lotes; o modelo só precisa de (deck_a, deck_b, níveis, resultado, data).
"""
from __future__ import annotations

import hashlib
import sqlite3
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS battles (
    battle_id TEXT PRIMARY KEY,
    played_at TEXT NOT NULL,
    source TEXT NOT NULL,
    mode TEXT,
    trophies INTEGER,
    deck_a TEXT NOT NULL,
    deck_b TEXT NOT NULL,
    level_a REAL,
    level_b REAL,
    evo_a TEXT,
    evo_b TEXT,
    crowns_a INTEGER,
    crowns_b INTEGER,
    result REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_battles_played ON battles(played_at);
CREATE INDEX IF NOT EXISTS idx_battles_source ON battles(source);
"""


def deck_key(cards) -> str:
    return "|".join(sorted(cards))


def battle_id(played_at: str, side_a: dict, side_b: dict) -> str:
    # Mesma partida vista pelos dois jogadores gera o mesmo id (ordem canônica dos lados).
    parts = sorted([f"{side_a.get('tag', '')}:{deck_key(side_a['cards'])}",
                    f"{side_b.get('tag', '')}:{deck_key(side_b['cards'])}"])
    return hashlib.sha1(f"{played_at}|{parts[0]}|{parts[1]}".encode()).hexdigest()


class BattleStore:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(self.path)
        self.conn.executescript(SCHEMA)

    def insert(self, battles: list[dict]) -> int:
        """battles: [{played_at, source, mode, trophies, result, a:{cards, level, evolutions, crowns, tag}, b:{...}}]
        result: 1 = A venceu, 0 = B venceu, 0.5 = empate."""
        rows = []
        for bt in battles:
            a, b = bt["a"], bt["b"]
            if len(a["cards"]) != 8 or len(b["cards"]) != 8:
                continue
            rows.append((
                bt.get("battle_id") or battle_id(bt["played_at"], a, b), bt["played_at"], bt.get("source", "unknown"),
                bt.get("mode"), bt.get("trophies"), deck_key(a["cards"]), deck_key(b["cards"]),
                a.get("level"), b.get("level"), deck_key(a.get("evolutions", [])), deck_key(b.get("evolutions", [])),
                a.get("crowns"), b.get("crowns"), float(bt["result"]),
            ))
        before = self.count()
        self.conn.executemany("INSERT OR IGNORE INTO battles VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
        self.conn.commit()
        return self.count() - before

    def count(self) -> int:
        return self.conn.execute("SELECT COUNT(*) FROM battles").fetchone()[0]

    def load(self, days: int | None = None, sources: list[str] | None = None, mode: str | None = None,
             min_trophies: int | None = None, until: str | None = None) -> list[tuple]:
        q = ("SELECT played_at, source, mode, trophies, deck_a, deck_b, level_a, level_b, evo_a, evo_b, result "
             "FROM battles WHERE 1=1")
        args: list = []
        end = datetime.fromisoformat(until) if until else None
        if days:
            ref = end or self.latest() or datetime.now(timezone.utc)
            q += " AND played_at >= ?"
            args.append((ref - timedelta(days=days)).isoformat())
        if until:
            q += " AND played_at <= ?"
            args.append(until)
        if sources:
            q += f" AND source IN ({','.join('?' * len(sources))})"
            args += sources
        if mode:
            q += " AND mode = ?"
            args.append(mode)
        if min_trophies is not None:
            q += " AND trophies >= ?"
            args.append(min_trophies)
        return self.conn.execute(q, args).fetchall()

    def latest(self) -> datetime | None:
        row = self.conn.execute("SELECT MAX(played_at) FROM battles").fetchone()[0]
        return datetime.fromisoformat(row) if row else None

    def summary(self) -> dict:
        total = self.count()
        rng = self.conn.execute("SELECT MIN(played_at), MAX(played_at) FROM battles").fetchone()
        by_source = dict(self.conn.execute("SELECT source, COUNT(*) FROM battles GROUP BY source").fetchall())
        return {"battles": total, "first": rng[0], "last": rng[1], "by_source": by_source}
