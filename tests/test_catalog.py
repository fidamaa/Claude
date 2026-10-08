import pytest

from crlab.catalog import UnknownCardError, get_catalog


def test_catalog_loads_unique_keys():
    cat = get_catalog()
    assert cat.n >= 100
    assert len({c.key for c in cat.cards}) == cat.n


def test_resolve_english_portuguese_and_aliases():
    cat = get_catalog()
    assert cat.resolve("Hog Rider").key == "Hog Rider"
    assert cat.resolve("corredor").key == "Hog Rider"
    assert cat.resolve("Bola de Fogo").key == "Fireball"
    assert cat.resolve("pekka").key == "P.E.K.K.A"
    assert cat.resolve("Valquíria").key == "Valkyrie"


def test_unknown_card_suggests():
    with pytest.raises(UnknownCardError) as e:
        get_catalog().resolve("Hog Ridder")
    assert "Hog Rider" in e.value.suggestions


def test_reference_decks_are_valid(engine):
    for d in engine.reference_decks:
        assert len(set(d["idx"])) == 8, d["name"]
