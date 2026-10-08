from fastapi.testclient import TestClient

from crlab.api import create_app

from .conftest import HOG_26


def test_api_endpoints(engine):
    client = TestClient(create_app(engine=engine))
    assert len(client.get("/api/cards").json()) >= 100
    assert len(client.get("/api/archetypes").json()) == 11
    r = client.post("/api/analyze", json={"deck": HOG_26})
    assert r.status_code == 200 and len(r.json()["matchups"]) == 11
    r = client.post("/api/analyze", json={"deck": HOG_26[:7] + ["Carta Inexistente"]})
    assert r.status_code == 400 and "desconhecida" in r.json()["detail"]
    r = client.post("/api/suggest", json={"deck": HOG_26, "keep_win_condition": True, "top": 2})
    assert r.status_code == 200
    col = {"cards": {c: 14 for c in HOG_26 + ["Valkyrie", "Knight", "Zap", "Arrows"]}}
    r = client.post("/api/build", json={"collection": col, "top_k": 2})
    assert r.status_code == 200 and r.json()["decks"]
    assert client.get("/").status_code == 200


def test_player_import_and_admin(monkeypatch, engine):
    import crlab.ingest.official_api as oa

    class FakeApi:
        def __init__(self, *a, **k):
            pass

        def player(self, tag):
            return {"tag": "#ABC", "name": "Teste", "trophies": 7000,
                    "cards": [{"name": n, "level": 13, "maxLevel": 16} for n in HOG_26] + [{"name": "Carta Nova", "level": 1}],
                    "currentDeck": [{"name": n} for n in HOG_26]}

    monkeypatch.setattr(oa, "ClashApi", FakeApi)
    client = TestClient(create_app(engine=engine))
    monkeypatch.delenv("CR_API_TOKEN", raising=False)
    assert client.get("/api/player/ABC").status_code == 503
    monkeypatch.setenv("CR_API_TOKEN", "x")
    r = client.get("/api/player/ABC").json()
    assert r["current_deck"] == HOG_26 and r["cards"]["Hog Rider"] == 13 and r["unknown_cards"] == ["Carta Nova"]
    # ações administrativas exigem ADMIN_KEY
    monkeypatch.delenv("ADMIN_KEY", raising=False)
    assert client.post("/api/reload").status_code == 403
    monkeypatch.setenv("ADMIN_KEY", "segredo")
    assert client.post("/api/reload", headers={"X-Admin-Key": "errado"}).status_code == 401
    assert client.post("/api/reload", headers={"X-Admin-Key": "segredo"}).status_code == 200


def test_collector_runs_and_swaps_engine(monkeypatch, tmp_path, engine):
    import crlab.ingest.official_api as oa
    from crlab.collector import Collector
    from crlab.ingest.synthetic import generate
    from crlab.settings import load_settings

    battles, _ = generate(engine, n=3000, seed=5)
    for b in battles:
        b["source"] = "official_api"

    class FakeApi:
        def __init__(self, *a, **k):
            pass

        def top_players(self, *a, **k):
            return ["#A"]

        def crawl(self, seeds, max_players=0, log=print):
            return battles

    monkeypatch.setattr(oa, "ClashApi", FakeApi)
    monkeypatch.setenv("CR_API_TOKEN", "x")
    cfg = load_settings(overrides={"data": {"db_path": str(tmp_path / "b.sqlite"), "model_path": str(tmp_path / "m.npz")}})
    got = {}
    col = Collector(cfg, on_new_engine=lambda e: got.setdefault("engine", e))
    res = col.run_once()
    assert res["new_battles"] == 3000 and "engine" in got
    assert got["engine"].data_status()["model"] is True
    assert not col.status["running"] and col.status["last_error"] is None


def test_card_images_only_catalog_names(tmp_path, engine):
    from crlab.images import CardImages, card_slug
    img = CardImages(engine.catalog, tmp_path)
    assert card_slug("P.E.K.K.A") == "pekka" and card_slug("X-Bow") == "x-bow" and card_slug("The Log") == "the-log"
    assert img.valid("s", "hog-rider") and img.valid("l", "knight-ev1")
    assert not img.valid("s", "hog-rider-ev1")          # Corredor não tem evolução
    assert not img.valid("s", "../../etc/passwd") and not img.valid("x", "hog-rider")
    assert img.get("s", "nao-existe") is None
