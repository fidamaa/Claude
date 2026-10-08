import json

import numpy as np
import pytest

from crlab.datamodel import DataModel, train_model
from crlab.engine import Engine
from crlab.ingest.importers import read_any
from crlab.ingest.official_api import collection_from_player, normalize_battle
from crlab.levels import PlayerCollection
from crlab.ingest.synthetic import generate
from crlab.store import BattleStore

from .conftest import HOG_26


@pytest.fixture(scope="module")
def trained(tmp_path_factory, engine):
    d = tmp_path_factory.mktemp("data")
    store = BattleStore(d / "b.sqlite")
    battles, truth = generate(engine, n=15000, seed=3, gamma=0.4)
    assert store.insert(battles) == 15000
    assert store.insert(battles[:50]) == 0  # deduplicação
    model = train_model(store, engine.catalog, engine.cfg, heuristic_engine=engine, log=lambda *_: None)
    model.save(d / "model.npz")
    return DataModel.load(d / "model.npz"), truth


def test_model_recovers_level_effect(trained):
    model, truth = trained
    assert abs(float(model.bt_gamma) - truth["gamma"]) < 0.12
    v = model.info["validation"]
    assert v["logloss_model"] < v["logloss_baseline"]


def test_engine_with_model_reports_sources_and_warning(trained):
    model, _ = trained
    e = Engine(model=model)
    r = e.analyze(HOG_26)
    assert "SINTÉTICOS" in r["data"]["warning"]
    assert any(m["source"] != "heurística" for m in r["matchups"])
    assert any(m["interval"] is not None for m in r["matchups"])
    assert r["cards"][0]["meta"]["games"] > 0
    assert "dados" in r["overall"]["meta_source"] or "SINTÉTICOS" in r["overall"]["meta_source"]


def test_normalize_official_battle():
    def side(tag, crowns, lvl):
        names = HOG_26
        return {"tag": tag, "crowns": crowns, "startingTrophies": 7000,
                "cards": [{"name": n, "level": lvl, "maxLevel": 14, "evolutionLevel": 1 if n == "Skeletons" else 0}
                          for n in names]}
    entry = {"type": "PvP", "battleTime": "20260901T120000.000Z", "gameMode": {"name": "Ladder"},
             "team": [side("#A", 3, 12)], "opponent": [side("#B", 1, 13)]}
    nb = normalize_battle(entry)
    assert nb["result"] == 1.0
    assert nb["a"]["level"] == 14 and nb["b"]["level"] == 15  # escala unificada (16 - maxLevel)
    assert nb["a"]["evolutions"] == ["Skeletons"]
    assert nb["played_at"].startswith("2026-09-01T12:00:00")
    assert normalize_battle({**entry, "team": entry["team"] * 2}) is None  # 2v2 ignorado


def test_collection_from_player(engine):
    player = {"tag": "#X", "name": "p", "cards": [{"name": "Hog Rider", "level": 11, "maxLevel": 13},
                                                   {"name": "Knight", "level": 14, "maxLevel": 16, "evolutionLevel": 1}]}
    col = collection_from_player(player)
    assert col["cards"]["Hog Rider"] == 14 and col["evolutions"] == ["Knight"]
    pc = PlayerCollection.from_dict(engine.catalog, col)
    assert len(pc.owned) == 2


def test_import_jsonl_and_csv(tmp_path):
    line = {"played_at": "2026-09-01T12:00:00+00:00", "a": {"cards": HOG_26}, "b": {"cards": HOG_26[::-1]}, "result": 1}
    p = tmp_path / "x.jsonl"
    p.write_text(json.dumps(line) + "\n" + json.dumps(line), encoding="utf-8")
    assert len(read_any(p, "teste")) == 2
    c = tmp_path / "x.csv"
    c.write_text("played_at,deck_a,deck_b,result,level_a,level_b\n"
                 f"2026-09-01T12:00:00+00:00,{';'.join(HOG_26)},{';'.join(HOG_26)},0,14,13.5\n", encoding="utf-8")
    rows = read_any(c)
    assert rows[0]["a"]["cards"] == HOG_26 and rows[0]["b"]["level"] == 13.5
