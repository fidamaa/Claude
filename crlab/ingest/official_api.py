"""Cliente da API oficial do Clash Royale (https://developer.clashroyale.com).

- Requer um token (variável CR_API_TOKEN). A API oficial exige cadastrar o IP de origem no token.
  Para IP dinâmico, use o proxy da RoyaleAPI: base_url=https://proxy.royaleapi.dev/v1 e cadastre
  o IP 45.79.218.79 no token (ver documentação da RoyaleAPI).
- Coleta: rankings -> battlelog de cada jogador -> descobre adversários -> BFS limitado.
- O battlelog só guarda as ~25 partidas mais recentes por jogador: para acumular histórico,
  rode a coleta periodicamente (cron). Partidas repetidas são deduplicadas pelo id canônico.
"""
from __future__ import annotations

import base64
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import deque
from datetime import datetime, timezone

DEFAULT_BASE = "https://api.clashroyale.com/v1"
ROYALEAPI_PROXY = "https://proxy.royaleapi.dev/v1"
ROYALEAPI_PROXY_IP = "45.79.218.79"
MAX_STD_LEVEL = 16  # escala unificada de níveis; nível_normalizado = level + (16 - maxLevel)
# Modos que não representam o meta competitivo 1x1 (amistosos, duelos de guerra, batalha naval…)
EXCLUDED_TYPES = {"friendly", "clanMate", "boatBattle", "riverRaceDuel", "riverRaceDuelColosseum", "tutorial"}


class ApiError(RuntimeError):
    pass


def token_cidrs(token: str) -> list[str]:
    """IPs autorizados gravados na chave (lidos do payload do JWT, sem validar assinatura)."""
    try:
        payload = token.split(".")[1]
        claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
    except (IndexError, ValueError):
        return []
    return [c for lim in claims.get("limits", []) for c in lim.get("cidrs", [])]


def default_base_for(token: str) -> str:
    """Chave cadastrada só para o IP do proxy da RoyaleAPI -> usa o proxy automaticamente."""
    cidrs = token_cidrs(token)
    if cidrs and all(c.split("/")[0] == ROYALEAPI_PROXY_IP for c in cidrs):
        return ROYALEAPI_PROXY
    return DEFAULT_BASE


class ClashApi:
    def __init__(self, token: str | None = None, base_url: str | None = None, min_interval: float = 0.05):
        self.token = token or os.environ.get("CR_API_TOKEN")
        if not self.token:
            raise ApiError("Token ausente: defina CR_API_TOKEN ou passe --token.")
        self.base = (base_url or os.environ.get("CR_API_BASE") or default_base_for(self.token)).rstrip("/")
        self.min_interval = min_interval
        self._last = 0.0

    def _get(self, path: str, params: dict | None = None):
        wait = self.min_interval - (time.time() - self._last)
        if wait > 0:
            time.sleep(wait)
        url = self.base + path + ("?" + urllib.parse.urlencode(params) if params else "")
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.token}", "Accept": "application/json"})
        for attempt in range(4):
            try:
                with urllib.request.urlopen(req, timeout=20) as resp:
                    self._last = time.time()
                    return json.loads(resp.read().decode())
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(2 ** attempt)
                    continue
                body = e.read().decode(errors="ignore")[:300]
                raise ApiError(f"HTTP {e.code} em {path}: {body}") from e
            except urllib.error.URLError as e:
                time.sleep(2 ** attempt)
                last = e
        raise ApiError(f"Falha de rede em {path}: {last if 'last' in locals() else 'tentativas esgotadas'}")

    @staticmethod
    def _tag(tag: str) -> str:
        tag = tag.strip().upper()
        return urllib.parse.quote(tag if tag.startswith("#") else "#" + tag)

    def player(self, tag: str) -> dict:
        return self._get(f"/players/{self._tag(tag)}")

    def battlelog(self, tag: str) -> list:
        return self._get(f"/players/{self._tag(tag)}/battlelog")

    def top_players(self, location: str = "global", limit: int = 200) -> list[str]:
        try:
            data = self._get(f"/locations/{location}/pathoflegend/players", {"limit": limit})
        except ApiError:
            data = self._get(f"/locations/{location}/rankings/players", {"limit": limit})
        return [p["tag"] for p in data.get("items", [])]

    def crawl(self, seeds: list[str], max_players: int = 200, log=print) -> list[dict]:
        """BFS a partir de jogadores semente. Retorna partidas normalizadas (1v1)."""
        queue, seen, battles = deque(seeds), set(), []
        while queue and len(seen) < max_players:
            tag = queue.popleft()
            if tag in seen:
                continue
            seen.add(tag)
            try:
                log_entries = self.battlelog(tag)
            except ApiError as e:
                log(f"  {tag}: {e}")
                continue
            for entry in log_entries:
                nb = normalize_battle(entry)
                if nb:
                    battles.append(nb)
                    opp = nb["b"].get("tag")
                    if opp and opp not in seen:
                        queue.append(opp)
            if len(seen) % 25 == 0:
                log(f"  {len(seen)} jogadores, {len(battles)} partidas")
        return battles


def _norm_level(card: dict) -> float | None:
    if "level" not in card:
        return None
    return card["level"] + (MAX_STD_LEVEL - card.get("maxLevel", MAX_STD_LEVEL))


def _is_evo(card: dict) -> bool:
    return int(card.get("evolutionLevel") or 0) > 0 and not _is_hero(card)


def _is_hero(card: dict) -> bool:
    """A API ainda não documenta publicamente como marca Heróis; aceita os campos prováveis.
    (Se o formato for outro, o jogador pode marcar seus Heróis manualmente na Coleção.)"""
    if card.get("isHero") or card.get("hero") or int(card.get("heroLevel") or 0) > 0:
        return True
    return str(card.get("variant", "")).lower() == "hero"


def _side(p: dict) -> dict:
    cards = p.get("cards", [])
    levels = [lv for lv in (_norm_level(c) for c in cards) if lv is not None]
    return {
        "tag": p.get("tag"),
        "cards": [c["name"] for c in cards],
        "level": sum(levels) / len(levels) if levels else None,
        "evolutions": [c["name"] for c in cards if _is_evo(c)],
        "heroes": [c["name"] for c in cards if _is_hero(c)],
        "crowns": p.get("crowns", 0),
        "trophies": p.get("startingTrophies"),
    }


def parse_battle_time(s: str) -> str:
    return datetime.strptime(s, "%Y%m%dT%H%M%S.%fZ").replace(tzinfo=timezone.utc).isoformat()


def normalize_battle(entry: dict, source: str = "official_api") -> dict | None:
    team, opp = entry.get("team", []), entry.get("opponent", [])
    if entry.get("type") in EXCLUDED_TYPES or len(team) != 1 or len(opp) != 1:
        return None
    a, b = _side(team[0]), _side(opp[0])
    if len(a["cards"]) != 8 or len(b["cards"]) != 8:
        return None
    result = 1.0 if a["crowns"] > b["crowns"] else 0.0 if a["crowns"] < b["crowns"] else 0.5
    mode = entry.get("type", "")
    gm = (entry.get("gameMode") or {}).get("name")
    return {
        "played_at": parse_battle_time(entry["battleTime"]),
        "source": source,
        "mode": f"{mode}:{gm}" if gm else mode,
        "trophies": a.get("trophies"),
        "a": a, "b": b, "result": result,
    }


def collection_from_player(player: dict) -> dict:
    """Converte /players/{tag} no formato de coleção do crlab (cartas, níveis, evoluções)."""
    cards, evos, heroes, fields = {}, [], [], set()
    for c in player.get("cards", []):
        cards[c["name"]] = _norm_level(c)
        fields |= set(c)
        if _is_evo(c):
            evos.append(c["name"])
        if _is_hero(c):
            heroes.append(c["name"])
    return {
        "player": {"tag": player.get("tag"), "name": player.get("name"), "trophies": player.get("trophies"),
                   "exp_level": player.get("expLevel"), "arena": (player.get("arena") or {}).get("name")},
        "cards": cards, "evolutions": evos, "heroes": heroes,
        "card_fields": sorted(fields),  # diagnóstico: campos que a API devolve por carta
        "current_deck": [c["name"] for c in player.get("currentDeck", [])],
    }
