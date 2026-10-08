"""API REST (FastAPI) + interface web estática."""
from __future__ import annotations

import json
import os
import secrets
import threading
from pathlib import Path

import numpy as np
from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

from .archetypes import ARCH_PT, ARCHETYPES, DEMANDS
from .builder import BuildRequest, DeckBuilder, parse_style
from .catalog import DATA_DIR, UnknownCardError
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
    heroes: list[str] = Field(default_factory=list)
    reference_level: float | None = None


class AnalyzeIn(BaseModel):
    deck: list[str]
    forms: list[str] | None = Field(default=None, description="forma por posição: normal | evo | hero (None = automático)")
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
    potential: bool = True


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
    # IDs oficiais das cartas (para o link "copiar deck" do jogo). Base: data/card_ids.json;
    # com CR_API_TOKEN, completa/atualiza pela API oficial em segundo plano.
    card_ids: dict[str, int] = json.loads((DATA_DIR / "card_ids.json").read_text(encoding="utf-8"))

    def refresh_ids():
        from .ingest.official_api import ApiError, ClashApi
        try:
            for item in ClashApi()._get("/cards").get("items", []):
                card = eng().catalog.find(item.get("name", ""))
                if card and item.get("id"):
                    card_ids[card.key] = int(item["id"])
        except (ApiError, OSError, ValueError):
            pass

    if os.environ.get("CR_API_TOKEN") and start_collector:
        threading.Thread(target=refresh_ids, daemon=True).start()

    @app.get("/api/cards")
    def cards():
        out = []
        for c in eng().catalog.cards:
            d = c.to_dict()
            d["slug"] = card_slug(c.key)
            d["id"] = card_ids.get(c.key)
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

    @app.get("/api/meta")
    def meta(limit: int = 24, min_games: int = 4):
        """Decks e cartas em alta nas partidas coletadas (ou decks de referência, sem dados)."""
        from .archetypes import ARCH_PT
        from .stats import beta_posterior, wilson_lower
        e = eng()
        cat = e.catalog
        decks = []
        if e.model is not None and e.model.deck_stats:
            total = max(1, e.model.info.get("battles", 1)) * 2
            rows = sorted(((k, v) for k, v in e.model.deck_stats.items() if v[0] >= min_games), key=lambda kv: -kv[1][0])
            for k, (games, wins, *_r) in rows[: limit * 2]:
                cards = [cat.by_key.get(x) for x in k.split("|")]
                if None in cards:
                    continue
                idx = [c.idx for c in cards]
                prim, _ = e.clf.classify(idx)
                post = beta_posterior(wins, games, 0.5, 30)
                decks.append({
                    "deck": [c.key for c in cards], "archetype": prim, "archetype_pt": ARCH_PT[prim],
                    "avg_elixir": round(sum(c.elixir for c in cards) / 8, 2), "games": int(games),
                    "winrate": post["mean"], "winrate_raw": wins / games, "winrate_low": wilson_lower(wins, games),
                    "usage": games / total,
                })
            decks = decks[:limit]
            source = "dados"
        else:
            ev = e.evaluate([d["idx"] for d in e.reference_decks])
            for d, p, prim in zip(e.reference_decks, ev["ev"], ev["primary"]):
                cards = [cat.cards[i] for i in d["idx"]]
                a = ARCHETYPES[prim]
                decks.append({"deck": [c.key for c in cards], "name": d["name"], "archetype": a, "archetype_pt": ARCH_PT[a],
                              "avg_elixir": round(sum(c.elixir for c in cards) / 8, 2), "games": 0,
                              "winrate": float(p), "estimated": True})
            decks.sort(key=lambda x: -x["winrate"])
            source = "referência"
        cards_out = []
        if e.model is not None:
            m = e.model
            order = np.argsort(-m.card_games)[:40]
            cards_out = [{"card": cat.cards[i].key, "games": int(m.card_games[i]), "usage": float(m.usage[i]),
                          "winrate": float(m.card_wr[i])} for i in order if m.card_games[i] > 0]
        return jsonable({"source": source, "decks": decks, "cards": cards_out, "data": e.data_status()})

    @app.get("/api/player/{tag}/decks")
    def player_decks(tag: str):
        """Perfil, deck atual e decks usados recentemente por qualquer jogador (battlelog oficial)."""
        from collections import defaultdict
        from .ingest.official_api import ApiError, ClashApi, collection_from_player, normalize_battle
        from .store import deck_key
        if not os.environ.get("CR_API_TOKEN"):
            raise HTTPException(status_code=503, detail="Servidor sem CR_API_TOKEN: consulta de jogadores indisponível.")
        api = ClashApi()
        try:
            profile = collection_from_player(api.player(tag))
            log = api.battlelog(tag)
        except ApiError as e:
            if "404" in str(e):
                raise HTTPException(status_code=404, detail="Jogador não encontrado. Confira a tag.") from e
            raise HTTPException(status_code=502, detail=f"Falha na API do Clash Royale: {e}") from e
        cat = eng().catalog
        groups: dict[str, dict] = defaultdict(lambda: {"games": 0, "wins": 0.0, "last": "", "levels": []})
        for entry in log:
            b = normalize_battle(entry)
            if not b or any(cat.find(c) is None for c in b["a"]["cards"]):
                continue
            g = groups[deck_key(b["a"]["cards"])]
            g["deck"] = [cat.find(c).key for c in b["a"]["cards"]]
            g["games"] += 1
            g["wins"] += b["result"]
            g["last"] = max(g["last"], b["played_at"])
            g["mode"] = b["mode"]
            if b["a"].get("level"):
                g["levels"].append(b["a"]["level"])
        recent = sorted(groups.values(), key=lambda g: (-g["games"], g["last"]))
        for g in recent:
            g["avg_level"] = round(sum(g["levels"]) / len(g["levels"]), 1) if g["levels"] else None
            del g["levels"]
        levels = [v for v in profile["cards"].values() if v]
        return jsonable({
            "player": profile["player"], "current_deck": [c for c in profile["current_deck"] if cat.find(c)],
            "n_cards": len(profile["cards"]), "avg_level": round(sum(levels) / len(levels), 1) if levels else None,
            "recent_decks": recent[:8],
        })

    @app.post("/api/data/refresh")
    def refresh(x_admin_key: str | None = Header(default=None)):
        require_admin(x_admin_key)
        if not collector.status["enabled"]:
            raise HTTPException(status_code=503, detail="Servidor sem CR_API_TOKEN.")
        threading.Thread(target=collector.run_once, daemon=True).start()
        return {"started": True, "note": "Coleta iniciada em segundo plano; acompanhe em /api/status."}

    @app.post("/api/analyze")
    def analyze(body: AnalyzeIn):
        return guarded(lambda: eng().analyze(body.deck, collection(body.collection), body.forms))

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
                potential=body.potential,
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

        # Versão dos arquivos estáticos na URL: o navegador baixa de novo a cada atualização do site.
        import hashlib
        version = hashlib.sha1(b"".join((WEB_DIR / f).read_bytes() for f in ("app.js", "style.css"))).hexdigest()[:10]
        page = ((WEB_DIR / "index.html").read_text(encoding="utf-8")
                .replace("/static/app.js", f"/static/app.js?v={version}")
                .replace("/static/style.css", f"/static/style.css?v={version}"))

        @app.get("/")
        def index():
            return Response(content=page, media_type="text/html", headers={"Cache-Control": "no-cache"})

    return app


def production_app() -> FastAPI:
    """Ponto de entrada do site hospedado (uvicorn crlab.api:production_app --factory)."""
    return create_app(start_collector=True)
