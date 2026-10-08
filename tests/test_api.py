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
