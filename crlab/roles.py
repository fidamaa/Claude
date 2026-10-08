"""Funções de cada carta no deck, no estilo das categorias do Draft da RoyaleAPI.

Obrigatórias: condição de vitória, tanque, dano direto (feitiço), antiaéreo e distração.
Opcionais: as demais. Regras simples sobre os atributos do catálogo, sem pesos escondidos."""
from __future__ import annotations

import numpy as np

from .catalog import Catalog


def _masks(cat: Catalog) -> list[tuple[str, str, bool, np.ndarray]]:
    f = cat.features
    unit = f["spell"] == 0
    cheap = f["elixir"] <= 3
    return [
        ("wincon", "Condição de vitória", True, f["wc"] > 0),
        ("tank", "Tanque", True, (f["tank"] + f["minitank"]) > 0),
        ("spell", "Dano direto", True, f["spell"] > 0),
        ("air", "Antiaéreo", True, unit & (f["dpsa"] > 0)),
        ("distraction", "Distração", True, unit & cheap & ((f["swarm"] + f["bait"]) > 0) | (unit & (f["elixir"] <= 2))),
        ("spell2", "2º feitiço", False, f["spell"] > 0),
        ("antitank", "Anti-tanque", False, f["tk"] > 0),
        ("splash", "Dano em área", False, unit & (f["spl"] >= 0.4)),
        ("cheap_air", "Antiaéreo barato", False, unit & cheap & (f["dpsa"] > 0)),
        ("support", "Suporte", False, unit & (f["ranged"] > 0) & (f["wc"] == 0)),
        ("cycle", "Ciclo (até 2)", False, f["elixir"] <= 2),
    ]


def deck_roles(cat: Catalog, idx: list[int]) -> list[dict]:
    out = []
    for key, name, required, mask in _masks(cat):
        cards = [cat.cards[i].key for i in idx if mask[i]]
        ok = len(cards) >= 2 if key == "spell2" else bool(cards)
        out.append({"role": key, "name": name, "required": required, "ok": ok, "cards": cards})
    return out


def required_matrix(cat: Catalog) -> np.ndarray:
    """(R x n) máscaras das funções essenciais, para checar lotes de decks no gerador."""
    return np.array([m for _, _, req, m in _masks(cat) if req], float)


def missing_required(R: np.ndarray, decks: np.ndarray) -> np.ndarray:
    """Quantas funções essenciais faltam em cada deck (B,)."""
    return (R[:, decks].sum(2) == 0).sum(0)
