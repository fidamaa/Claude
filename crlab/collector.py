"""Coleta automática em segundo plano (para o site hospedado).

Se CR_API_TOKEN estiver definido, o servidor coleta partidas reais periodicamente (ranking ->
battlelogs -> adversários), guarda no banco, retreina o modelo e recarrega o motor, sem derrubar o site.
Variáveis de ambiente:
  CR_API_TOKEN            chave da API oficial (obrigatória para coletar)
  AUTO_COLLECT_HOURS      intervalo entre coletas (padrão 6; 0 desliga)
  COLLECT_MAX_PLAYERS     jogadores visitados por coleta (padrão 400)
  COLLECT_SEED_TOP        jogadores do ranking usados como semente (padrão 100)
"""
from __future__ import annotations

import os
import threading
import time
import traceback
from datetime import datetime

from .catalog import get_catalog
from .datamodel import train_model
from .engine import Engine
from .store import BattleStore


class Collector:
    def __init__(self, cfg: dict, on_new_engine):
        self.cfg = cfg
        self.on_new_engine = on_new_engine
        self.lock = threading.Lock()
        self.status = {"enabled": bool(os.environ.get("CR_API_TOKEN")), "running": False, "last_run": None,
                       "last_result": None, "last_error": None, "log": []}
        self.interval_h = float(os.environ.get("AUTO_COLLECT_HOURS", "6"))
        self.max_players = int(os.environ.get("COLLECT_MAX_PLAYERS", "400"))
        self.seed_top = int(os.environ.get("COLLECT_SEED_TOP", "100"))
        self.status["interval_hours"] = self.interval_h

    def _log(self, msg: str):
        line = f"{datetime.now().strftime('%H:%M:%S')} {msg}"
        self.status["log"] = (self.status["log"] + [line])[-30:]

    def start_background(self):
        if not self.status["enabled"] or self.interval_h <= 0:
            return
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        time.sleep(5)
        while True:
            self.run_once()
            time.sleep(self.interval_h * 3600)

    def run_once(self, max_players: int | None = None) -> dict:
        if not self.lock.acquire(blocking=False):
            return {"started": False, "reason": "Uma coleta já está em andamento."}
        try:
            from .api import sync_cards
            from .ingest.official_api import ClashApi, register_catalog
            sync_cards(log=self._log)  # cartas novas do jogo entram no catálogo antes do treino
            register_catalog(get_catalog())
            self.status.update(running=True, last_error=None)
            self._log("Coleta iniciada")
            api = ClashApi()
            seeds = api.top_players("global", self.seed_top)
            self._log(f"{len(seeds)} jogadores do ranking como semente")
            battles = api.crawl(seeds, max_players=max_players or self.max_players, log=self._log)
            store = BattleStore(self.cfg["data"]["db_path"])
            new = store.insert(battles)
            self._log(f"{new} partidas novas ({len(battles)} coletadas); total {store.count()}")
            sources = [s for s in store.summary()["by_source"] if s != "synthetic"]
            model = train_model(store, get_catalog(), self.cfg, heuristic_engine=Engine(cfg=self.cfg),
                                sources=sources, log=self._log)
            model.save(self.cfg["data"]["model_path"])
            self.on_new_engine(Engine(cfg=self.cfg, model=model))
            result = {"new_battles": new, "total": store.count(), "model_battles": model.info["battles"]}
            self.status["last_result"] = result
            self._log("Modelo retreinado e carregado")
            return {"started": True, **result}
        except Exception as e:  # noqa: BLE001 - o site deve continuar no ar mesmo se a coleta falhar
            self.status["last_error"] = f"{type(e).__name__}: {e}"
            self._log(f"Erro: {e}")
            traceback.print_exc()
            return {"started": True, "error": self.status["last_error"]}
        finally:
            self.status.update(running=False, last_run=datetime.now().isoformat(timespec="seconds"))
            self.lock.release()
