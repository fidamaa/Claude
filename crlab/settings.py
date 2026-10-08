"""Parâmetros ajustáveis. Todos os valores heurísticos ficam aqui (nada escondido no código).

Sobrescreva com um JSON (variável de ambiente CRLAB_SETTINGS ou argumento) contendo apenas as
chaves que deseja alterar. Parâmetros marcados como "calibrável" são substituídos por valores
ajustados a partir de dados reais quando um modelo treinado está disponível.
"""
from __future__ import annotations

import copy
import json
import os
from pathlib import Path

DEFAULTS: dict = {
    "levels": {
        # Efeito (em logit) de 1 nível médio de vantagem/desvantagem. Calibrável pelo modelo.
        "gamma_per_level": 0.28,
        # Uma evolução equivale a quantos níveis de vantagem para a carta.
        "evo_bonus_levels": 1.0,
        "max_evolutions": 2,
        "max_level": 16,
        # Sensibilidade a nível: feitiços e enxames dependem de "breakpoints" (matar ou não matar).
        "sensitivity": {"spell": 1.3, "swarm": 1.2, "default": 1.0},
        # Diferença de atributos por nível (~10% de vida/dano por nível).
        "stat_per_level": 0.10,
    },
    "heuristic": {
        # Escala dos termos de capacidade -> logit. Calibrável (temperature scaling).
        "alpha": 3.0,
        "beta_synergy": 0.25,
        "beta_coherence": 1.2,
        "beta_quality": 0.8,
        # Peso do termo "ofensivo" (o quanto o arquétipo rival é fraco no que meu deck exige).
        "offense_share": 0.5,
        # Penalidade (logit) por elixir de custo médio acima da média dos decks de referência.
        "beta_cost": 0.1,
        # Limite suave da magnitude do logit heurístico (0.6 ~ 35%-65%).
        "max_logit": 0.6,
    },
    "blend": {
        # Pseudo-partidas a partir das quais o modelo de dados passa a dominar a heurística.
        "model_k": 400,
        # Força do prior (pseudo-partidas) ao combinar com partidas do deck exato.
        "exact_prior_strength": 50,
        # Quanto vale (em partidas efetivas) uma partida indireta de carta para a confiança.
        "support_weight": 0.05,
        # Mínimo de partidas por arquétipo para usar pesos de demanda calibrados.
        "calibration_k": 2000,
    },
    "confidence": {"high": 1000, "medium": 150},
    "labels": [[0.58, "muito favorável"], [0.53, "favorável"], [0.47, "equilibrado"], [0.42, "desfavorável"],
               [0.0, "muito desfavorável"]],
    "objective": {
        # "robust": média vs meta - lambda * desvio entre matchups; "mean": só a média; "maximin": pior matchup
        "mode": "robust",
        "lambda": 0.5,
    },
    # Distribuição do meta usada quando não há dados (HEURÍSTICA). Com dados, vem das partidas.
    "meta_prior": {
        "hog": 0.13, "beatdown": 0.13, "bridge_spam": 0.13, "bait": 0.09, "siege": 0.07, "control": 0.10,
        "lava": 0.07, "graveyard": 0.06, "royal_giant": 0.08, "drill": 0.06, "cycle": 0.08,
    },
    # Pesos do índice de fatores (secundário). Calibráveis por regressão quando há dados.
    "factor_weights": {
        "cobertura_defensiva": 1.0, "sinergia": 1.0, "coerencia": 1.0, "capacidade_ofensiva": 1.0,
        "capacidade_defensiva": 1.0, "ciclo": 0.5, "custo_elixir": 0.5, "cobertura_aerea": 1.0,
        "resposta_tanques": 1.0, "resposta_enxames": 1.0, "feiticos": 0.7, "pressao": 0.7,
        "contra_ataque": 0.5, "niveis": 1.5, "desempenho_historico": 2.0, "matchups": 3.0, "meta": 0.5,
    },
    "data": {
        "db_path": "crlab_data/battles.sqlite",
        "model_path": "crlab_data/model.npz",
        "days": 60,
        "half_life_days": 21,
        "min_deck_games": 20,
        "l2_card": 2.0,
        "l2_interaction": 8.0,
        "opponent_samples": 300,
    },
    "builder": {
        "restarts_per_seed": 3,
        "max_seeds": 14,
        "max_iters": 25,
        "top_k": 5,
        "min_distinct_cards": 2,
        "style_penalty": 0.08,
        "seed": 7,
    },
}


def _merge(base: dict, override: dict) -> dict:
    out = copy.deepcopy(base)
    for k, v in override.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _merge(out[k], v)
        else:
            out[k] = v
    return out


def load_settings(path: str | os.PathLike | None = None, overrides: dict | None = None) -> dict:
    cfg = copy.deepcopy(DEFAULTS)
    path = path or os.environ.get("CRLAB_SETTINGS")
    if path and Path(path).exists():
        cfg = _merge(cfg, json.loads(Path(path).read_text(encoding="utf-8")))
    if overrides:
        cfg = _merge(cfg, overrides)
    return cfg
