"""Posições especiais do deck: 1ª Evo, 2ª Herói, 3ª Evo ou Herói."""
import numpy as np
import pytest

from crlab.builder import BuildRequest, DeckBuilder
from crlab.engine import DeckError
from crlab.levels import EVO, HERO, PlayerCollection, forms_valid

from .conftest import HOG_26

DECK = ["Knight", "Musketeer", "Mini P.E.K.K.A", "Hog Rider", "Ice Spirit", "Skeletons", "Fireball", "The Log"]


def test_forms_rules():
    assert forms_valid([EVO, HERO, EVO, 0, 0, 0, 0, 0])
    assert forms_valid([EVO, HERO, HERO, 0, 0, 0, 0, 0])
    assert not forms_valid([EVO, EVO, EVO, 0, 0, 0, 0, 0])
    assert not forms_valid([EVO, HERO, EVO, HERO, 0, 0, 0, 0])


def test_slot_validation(engine):
    with pytest.raises(DeckError):  # Herói não entra na 1ª posição
        engine.analyze(DECK, None, ["hero"] + ["normal"] * 7)
    with pytest.raises(DeckError):  # Evo não entra na 2ª posição
        engine.analyze(DECK, None, ["normal", "evo"] + ["normal"] * 6)
    with pytest.raises(DeckError):  # forma especial fora das 3 primeiras posições
        engine.analyze(DECK, None, ["normal"] * 3 + ["evo"] + ["normal"] * 4)
    with pytest.raises(DeckError):  # Corredor não tem versão Herói
        engine.analyze(["Knight", "Hog Rider"] + [c for c in DECK if c not in ("Knight", "Hog Rider")], None,
                       ["normal", "hero"] + ["normal"] * 6)
    r = engine.analyze(DECK, None, ["evo", "hero", "hero"] + ["normal"] * 5)
    assert [s["form"] for s in r["slots"][:3]] == ["evo", "hero", "hero"]


def test_auto_forms_use_only_what_player_has(engine):
    cat = engine.catalog
    col = PlayerCollection.from_dict(cat, {"cards": {c: 14 for c in DECK}, "evolutions": ["Skeletons"], "heroes": ["Mini P.E.K.K.A"]})
    r = engine.analyze(DECK, col)
    special = {(s["card"], s["form"]) for s in r["slots"] if s["form"] != "normal"}
    assert special == {("Skeletons", "evo"), ("Mini P.E.K.K.A", "hero")}
    assert r["slots"][0] == {"card": "Skeletons", "form": "evo"} and r["slots"][1] == {"card": "Mini P.E.K.K.A", "form": "hero"}
    # o que falta desbloquear aparece como melhoria, com ganho positivo
    unl = {(u["card"], u["kind"]) for u in r["improvements"]["unlocks"]}
    assert ("Knight", "evo") in unl or ("Knight", "hero") in unl
    # sem coleção: análise teórica com as melhores formas
    full = engine.analyze(DECK)
    assert sum(s["form"] != "normal" for s in full["slots"]) == 3


def test_forms_raise_win_chance(engine):
    cat = engine.catalog
    base = {"cards": {c: 14 for c in DECK}, "reference_level": 14}
    none = engine.analyze(DECK, PlayerCollection.from_dict(cat, base))["overall"]["ev"]
    some = engine.analyze(DECK, PlayerCollection.from_dict(cat, {**base, "evolutions": ["Knight"], "heroes": ["Musketeer"]}))["overall"]["ev"]
    assert some > none + 0.02


def test_upgrade_suggestions(engine):
    cat = engine.catalog
    col = PlayerCollection.from_dict(cat, {"cards": {**{c: 14 for c in HOG_26}, "The Log": 11}, "reference_level": 14})
    imp = engine.analyze(HOG_26, col)["improvements"]
    assert imp["upgrades"][0]["card"] == "The Log" and imp["upgrades"][0]["gain"] > 0


def test_builder_prefers_owned_forms_and_offers_potential(engine):
    cat = engine.catalog
    cards = {c.key: 14 for c in cat.cards if c.idx % 2 == 0}
    cards.update({"Knight": 14, "Musketeer": 14, "Miner": 11, "Poison": 11})
    col = PlayerCollection.from_dict(cat, {"cards": cards, "evolutions": ["Knight"], "heroes": ["Musketeer"], "reference_level": 14})
    res = DeckBuilder(engine).build(BuildRequest(top_k=3), col)
    for d in res["decks"]:
        for s in d["analysis"]["slots"]:
            if s["form"] == "evo":
                assert s["card"] in col_names(cat, col.evolutions)
            if s["form"] == "hero":
                assert s["card"] in col_names(cat, col.heroes)
    assert any(s["form"] != "normal" for d in res["decks"] for s in d["analysis"]["slots"])
    assert 1 <= len(res["potential"]) <= 2
    for p in res["potential"]:
        assert p["gain"] > 0 and (p["upgrades"] or p["unlocks"])


def col_names(cat, idxs):
    return {cat.cards[i].key for i in idxs}


def test_model_learns_form_effects(tmp_path, engine):
    from crlab.datamodel import train_model
    from crlab.ingest.synthetic import generate
    from crlab.store import BattleStore
    store = BattleStore(tmp_path / "b.sqlite")
    battles, truth = generate(engine, n=12000, seed=11, form_effect=0.3)
    store.insert(battles)
    m = train_model(store, engine.catalog, engine.cfg, log=lambda *_: None)
    used = (m.evo_games > 300)
    assert used.sum() > 0
    assert float(np.mean(m.bt_ev[used])) > 0.1  # efeito real médio ≈ 0.3
