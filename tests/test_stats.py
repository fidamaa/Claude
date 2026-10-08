from crlab.settings import load_settings
from crlab.stats import beta_posterior, confidence_level, ridge_logistic, wilson_lower

import numpy as np


def test_small_sample_is_shrunk_more_than_large():
    small = beta_posterior(18, 20, prior_mean=0.5, prior_strength=50)
    large = beta_posterior(56000, 100000, prior_mean=0.5, prior_strength=50)
    assert small["raw"] == 0.9
    assert small["mean"] < 0.65            # 90% em 20 partidas é fortemente encolhido
    assert abs(large["mean"] - 0.56) < 0.001
    assert (small["high"] - small["low"]) > 20 * (large["high"] - large["low"])
    # ranking pelo limite inferior prefere a amostra grande
    assert wilson_lower(56000, 100000) > wilson_lower(18, 20) - 0.2
    assert large["low"] > 0.555


def test_interval_contains_mean():
    p = beta_posterior(30, 50, 0.5, 10)
    assert p["low"] < p["mean"] < p["high"]


def test_confidence_levels():
    cfg = load_settings()
    assert confidence_level(0, cfg) == "heurística"
    assert confidence_level(10, cfg) == "baixa"
    assert confidence_level(500, cfg) == "média"
    assert confidence_level(5000, cfg) == "alta"


def test_ridge_logistic_recovers_sign():
    rng = np.random.default_rng(0)
    X = rng.normal(size=(4000, 2))
    y = (rng.random(4000) < 1 / (1 + np.exp(-(1.5 * X[:, 0] - 1.0 * X[:, 1])))).astype(float)
    coef, _ = ridge_logistic(X, y, l2=1.0)
    assert coef[0] > 1.0 and coef[1] < -0.6
