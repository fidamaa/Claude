import numpy as np
import pytest

from crlab.archetypes import A_INDEX, ARCHETYPES
from crlab.engine import DeckError
from crlab.levels import PlayerCollection

from .conftest import GOLEM, HOG_26


def test_classification(engine):
    prim, labels = engine.clf.classify([engine.catalog.by_key[c].idx for c in HOG_26])
    assert prim == "hog" and "cycle" in labels
    prim, _ = engine.clf.classify([engine.catalog.by_key[c].idx for c in GOLEM])
    assert prim == "beatdown"


def test_analysis_structure(engine):
    r = engine.analyze(HOG_26)
    assert len(r["matchups"]) == len(ARCHETYPES)
    for m in r["matchups"]:
        assert 0.3 < m["win_prob"] < 0.7
        assert m["confidence"] == "heurística"     # sem dados -> deixa claro que é heurística
        assert m["explanation"]
    assert r["summary"]
    assert {c["key"] for c in r["capabilities"]} >= {"air_defense", "tank_killing"}


def test_matchups_differ_by_archetype(engine):
    """Hog 2.6 deve ir melhor contra ciclo/hog do que contra beatdown; Golem, o inverso contra ciclo."""
    hog = {m["archetype"]: m["win_prob"] for m in engine.analyze(HOG_26)["matchups"]}
    golem = {m["archetype"]: m["win_prob"] for m in engine.analyze(GOLEM)["matchups"]}
    assert hog["cycle"] > hog["beatdown"]
    assert golem["beatdown"] > golem["cycle"]


def test_weak_air_deck_flagged(engine):
    deck = ["Hog Rider", "Knight", "Valkyrie", "Mini P.E.K.K.A", "Skeletons", "Cannon", "Earthquake", "The Log"]
    r = engine.analyze(deck)
    msgs = " ".join(v["message"] for v in r["vulnerabilities"])
    assert "aérea" in msgs
    lava = next(m for m in r["matchups"] if m["archetype"] == "lava")
    assert lava["win_prob"] < 0.5


def test_invalid_decks(engine):
    with pytest.raises(DeckError):
        engine.parse_deck(HOG_26[:7])
    with pytest.raises(DeckError):
        engine.parse_deck(HOG_26[:7] + ["Hog Rider"])
    with pytest.raises(DeckError):
        engine.parse_deck(HOG_26[:6] + ["Archer Queen", "Golden Knight"])


def test_underleveled_deck_is_penalized(engine):
    cat = engine.catalog
    good = PlayerCollection.from_dict(cat, {"cards": {c: 14 for c in HOG_26}, "reference_level": 14})
    low = PlayerCollection.from_dict(cat, {"cards": {c: 11 for c in HOG_26}, "reference_level": 14})
    r_good, r_low = engine.analyze(HOG_26, good), engine.analyze(HOG_26, low)
    assert r_low["overall"]["ev"] < r_good["overall"]["ev"] - 0.05
    assert r_low["levels"]["effective_gap"] < -2.5
    assert any("níveis" in s or "nível" in s for m in r_low["matchups"] for s in m["reasons_against"])


def test_evolution_bonus(engine):
    cat = engine.catalog
    base = {c: 14 for c in HOG_26}
    plain = PlayerCollection.from_dict(cat, {"cards": base, "reference_level": 14})
    evo = PlayerCollection.from_dict(cat, {"cards": base, "evolutions": ["Skeletons"], "reference_level": 14})
    assert engine.analyze(HOG_26, evo)["overall"]["ev"] > engine.analyze(HOG_26, plain)["overall"]["ev"]


def test_batch_matches_single(engine):
    idx = [engine.catalog.by_key[c].idx for c in HOG_26]
    single = engine.evaluate([idx])["p"][0]
    batch = engine.evaluate(np.array([idx, idx[::-1]]))["p"]
    assert np.allclose(batch[0], single) and np.allclose(batch[1], single)
