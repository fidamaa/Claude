"""API REST (FastAPI) + interface web estática."""
from __future__ import annotations

import os
import secrets
from pathlib import Path

import numpy as np
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .archetypes import ARCH_PT, ARCHETYPES, DEMANDS
from .builder import BuildRequest, DeckBuilder, parse_style
from .catalog import UnknownCardError
from .collector import Collector
from .engine import DeckError, Engine
from .images import CardImages, card_slug
from .levels import PlayerCollection
from .optimizer import suggest_swaps
from .settings import load_settings

WEB_DIR = Path(__file__).parent / "web"


class Collection(BaseModel):
    cards: dict[str, float | None] = Field(default_factory=dict, description="carta -> nível (1..16)")
    evolutions: list[str] = Field(default_factory=list)
    reference_level: float | None = None


class AnalyzeIn(BaseModel):
    deck: list[str]
    collection: Collection | None = None


class SuggestIn(AnalyzeIn):
    keep: list[str] = Field(default_factory=list)
    keep_win_condition: bool = False
    target: str | None = None
    top: int = 5


class BuildIn(BaseModel):
    collection: Collection | None = None
    must_include: list[str] = Field(default_factory=list)
    exclude: list[str] = Field(default_factory=list)
    win_conditions: list[str] = Field(default_factory=list)
    style: str | None = None
    max_avg_elixir: float | None = None
    min_avg_elixir: float | None = None
    top_k: int | None = None


def jsonable(x):
    if isinstance(x, dict):
        return {str(k): jsonable(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [jsonable(v) for v in x]
    if isinstance(x, np.ndarray):
        return jsonable(x.tolist())
    if isinstance(x, np.generic):
        return x.item()
    return x


def create_app(cfg: dict | None = None, engine: Engine | None = None, start_collector: bool = False) -> FastAPI:
    cfg = cfg or load_settings()
    app = FastAPI(title="Clash Deck Lab", version="0.1.0",
                  description="Análise explicável de decks, matchups por arquétipo e geração de decks.")
    state = {"engine": engine or Engine.from_settings(cfg)}
    collector = Collector(cfg, on_new_engine=lambda e: state.__setitem__("engine", e))
    if start_collector:
        collector.start_background()

    def require_admin(key: str | None):
        expected = os.environ.get("ADMIN_KEY")
        if not expected:
            raise HTTPException(status_code=403, detail="Ação administrativa desativada (defina ADMIN_KEY no servidor).")
        if not key or not secrets.compare_digest(key, expected):
            raise HTTPException(status_code=401, detail="Chave de administrador inválida.")

    def eng() -> Engine:
        return state["engine"]

    def collection(c: Collection | None) -> PlayerCollection | None:
        if c is None or not c.cards:
            return None
        return PlayerCollection.from_dict(eng().catalog, c.model_dump())

    def names_to_idx(names: list[str]) -> list[int]:
        return [eng().catalog.resolve(n).idx for n in names]

    def guarded(fn):
        try:
            return jsonable(fn())
        except (UnknownCardError, DeckError) as e:
            raise HTTPException(status_code=400, detail=str(e)) from e

    images = CardImages(eng().catalog, Path(cfg["data"]["db_path"]).parent / "img")

    @app.get("/api/cards")
    def cards():
        out = []
        for c in eng().catalog.cards:
            d = c.to_dict()
            d["slug"] = card_slug(c.key)
            out.append(d)
        return out

    @app.get("/img/card/{size}/{name}.png")
    def card_image(size: str, name: str):
        data = images.get(size, name)
        if data is None:
            raise HTTPException(status_code=404, detail="Imagem indisponível.")
        return Response(content=data, media_type="image/png",
                        headers={"Cache-Control": "public, max-age=604800, immutable"})

    @app.get("/api/archetypes")
    def archetypes():
        return [{"key": a, "name": ARCH_PT[a], "demands": DEMANDS[a]} for a in ARCHETYPES]

    @app.get("/api/status")
    def status():
        st = {k: v for k, v in collector.status.items()}
        return jsonable({"data": eng().data_status(), "collector": st, "settings": eng().cfg})

    @app.get("/api/player/{tag}")
    def player(tag: str):
        """Coleção (cartas, níveis, evoluções) e deck atual do jogador, pela API oficial."""
        from .ingest.official_api import ApiError, ClashApi, collection_from_player
        if not os.environ.get("CR_API_TOKEN"):
            raise HTTPException(status_code=503, detail="Servidor sem CR_API_TOKEN: importação pela tag indisponível.")
        try:
            col = collection_from_player(ClashApi().player(tag))
        except ApiError as e:
            msg = str(e)
            if "404" in msg:
                raise HTTPException(status_code=404, detail="Jogador não encontrado. Confira a tag.") from e
            raise HTTPException(status_code=502, detail=f"Falha na API do Clash Royale: {msg}") from e
        cat = eng().catalog
        col["unknown_cards"] = [n for n in col["cards"] if cat.find(n) is None]
        return col

    @app.post("/api/data/refresh")
    def refresh(x_admin_key: str | None = Header(default=None)):
        require_admin(x_admin_key)
        if not collector.status["enabled"]:
            raise HTTPException(status_code=503, detail="Servidor sem CR_API_TOKEN.")
        import threading
        threading.Thread(target=collector.run_once, daemon=True).start()
        return {"started": True, "note": "Coleta iniciada em segundo plano; acompanhe em /api/status."}

    @app.post("/api/analyze")
    def analyze(body: AnalyzeIn):
        return guarded(lambda: eng().analyze(body.deck, collection(body.collection)))

    @app.post("/api/suggest")
    def suggest(body: SuggestIn):
        def run():
            e = eng()
            idx = e.parse_deck(body.deck)
            return suggest_swaps(e, idx, collection(body.collection), top=body.top, keep=names_to_idx(body.keep),
                                 keep_win_condition=body.keep_win_condition, target=parse_style(body.target))
        return guarded(run)

    @app.post("/api/build")
    def build(body: BuildIn):
        def run():
            req = BuildRequest(
                must_include=names_to_idx(body.must_include), exclude=names_to_idx(body.exclude),
                win_conditions=names_to_idx(body.win_conditions), style=parse_style(body.style),
                max_avg_elixir=body.max_avg_elixir, min_avg_elixir=body.min_avg_elixir, top_k=body.top_k,
            )
            return DeckBuilder(eng()).build(req, collection(body.collection))
        return guarded(run)

    @app.post("/api/reload")
    def reload(x_admin_key: str | None = Header(default=None)):
        require_admin(x_admin_key)
        state["engine"] = Engine.from_settings(cfg)
        return jsonable(eng().data_status())

    if WEB_DIR.exists():
        app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")

        @app.get("/")
        def index():
            return FileResponse(WEB_DIR / "index.html")

    return app


def production_app() -> FastAPI:
    """Ponto de entrada do site hospedado (uvicorn crlab.api:production_app --factory)."""
    return create_app(start_collector=True)
