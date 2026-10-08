"""API REST (FastAPI) + interface web estática."""
from __future__ import annotations

from pathlib import Path

import numpy as np
from fastapi import FastAPI, HTTPException
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .archetypes import ARCH_PT, ARCHETYPES, DEMANDS
from .builder import BuildRequest, DeckBuilder, parse_style
from .catalog import UnknownCardError
from .engine import DeckError, Engine
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


def create_app(cfg: dict | None = None, engine: Engine | None = None) -> FastAPI:
    cfg = cfg or load_settings()
    app = FastAPI(title="Clash Deck Lab", version="0.1.0",
                  description="Análise explicável de decks, matchups por arquétipo e geração de decks.")
    state = {"engine": engine or Engine.from_settings(cfg)}

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

    @app.get("/api/cards")
    def cards():
        return [c.to_dict() for c in eng().catalog.cards]

    @app.get("/api/archetypes")
    def archetypes():
        return [{"key": a, "name": ARCH_PT[a], "demands": DEMANDS[a]} for a in ARCHETYPES]

    @app.get("/api/status")
    def status():
        return jsonable({"data": eng().data_status(), "settings": eng().cfg})

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
    def reload():
        state["engine"] = Engine.from_settings(cfg)
        return jsonable(eng().data_status())

    if WEB_DIR.exists():
        app.mount("/static", StaticFiles(directory=WEB_DIR), name="static")

        @app.get("/")
        def index():
            return FileResponse(WEB_DIR / "index.html")

    return app
