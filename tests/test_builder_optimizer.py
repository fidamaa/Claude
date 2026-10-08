from crlab.archetypes import A_INDEX
from crlab.builder import BuildRequest, DeckBuilder
from crlab.levels import PlayerCollection
from crlab.optimizer import suggest_swaps

from .conftest import HOG_26

COLLECTION = {
    "cards": {c: 14 for c in HOG_26 + ["Valkyrie", "Knight", "Archers", "Arrows", "Zap", "Baby Dragon", "Giant",
                                       "Mini P.E.K.K.A", "Goblin Gang", "Bats", "Tesla", "Poison", "Royal Giant",
                                       "Inferno Tower", "Wizard", "Bomber", "Goblin Barrel", "Princess", "Minions"]},
    "evolutions": ["Knight"],
}


def test_build_respects_constraints(engine):
    cat = engine.catalog
    col = PlayerCollection.from_dict(cat, COLLECTION)
    hog, log, tesla = (cat.by_key[k].idx for k in ("Hog Rider", "The Log", "Tesla"))
    req = BuildRequest(win_conditions=[hog], must_include=[log], exclude=[tesla], top_k=3)
    res = DeckBuilder(engine).build(req, col)
    assert 1 <= len(res["decks"]) <= 3
    owned = set(COLLECTION["cards"])
    for d in res["decks"]:
        deck = d["analysis"]["deck"]
        assert len(set(deck)) == 8
        assert "Hog Rider" in deck and "The Log" in deck and "Tesla" not in deck
        assert set(deck) <= owned
    assert res["explored"] > 100
    decks = [set(d["analysis"]["deck"]) for d in res["decks"]]
    for i in range(len(decks)):
        for j in range(i + 1, len(decks)):
            assert len(decks[i] - decks[j]) >= 2


def test_build_style(engine):
    col = PlayerCollection.from_dict(engine.catalog, COLLECTION)
    res = DeckBuilder(engine).build(BuildRequest(style="beatdown", top_k=2), col)
    for d in res["decks"]:
        assert "beatdown" in d["analysis"]["archetype"]["labels"]


def test_build_beats_random_decks(engine):
    import numpy as np
    col = PlayerCollection.from_dict(engine.catalog, COLLECTION)
    res = DeckBuilder(engine).build(BuildRequest(top_k=1), col)
    best = res["decks"][0]["analysis"]["overall"]["score"]
    rng = np.random.default_rng(1)
    owned = col.owned
    rand = engine.evaluate(np.array([rng.choice(owned, 8, replace=False) for _ in range(300)]), col)["score"]
    assert best > rand.max()


def test_swaps_keep_win_condition(engine):
    idx = [engine.catalog.by_key[c].idx for c in HOG_26]
    res = suggest_swaps(engine, idx, keep_win_condition=True, top=5)
    assert all(s["out"] != "Hog Rider" for s in res["swaps"])
    assert "Hog Rider" not in res["replacements"]
    assert all(len(v) <= 3 for v in res["replacements"].values())
    for s in res["swaps"]:
        assert s["delta_score"] > 0 and s["explanation"].startswith("Trocar")


def test_swaps_target_archetype(engine):
    idx = [engine.catalog.by_key[c].idx for c in HOG_26]
    res = suggest_swaps(engine, idx, target="beatdown", top=3)
    assert res["swaps"]
    assert res["swaps"][0]["delta_by_archetype"]["beatdown"] > 0
