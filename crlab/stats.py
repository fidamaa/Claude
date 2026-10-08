"""Estatística: posteriores Beta, intervalos, encolhimento (shrinkage) e níveis de confiança.

Princípio: uma taxa de vitória é sempre tratada como (vitórias, partidas), nunca como porcentagem
isolada. 90% em 20 partidas é encolhido fortemente para o prior; 56% em 100.000 quase não muda.
"""
from __future__ import annotations

import math

import numpy as np


def logit(p):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return np.log(p / (1 - p))


def sigmoid(x):
    return 1.0 / (1.0 + np.exp(-np.asarray(x, dtype=float)))


def _betacf(a: float, b: float, x: float) -> float:
    # Fração contínua do Numerical Recipes para a beta incompleta regularizada.
    tiny = 1e-30
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c, d = 1.0, 1.0 - qab * x / qap
    d = 1.0 / (d if abs(d) > tiny else tiny)
    h = d
    for m in range(1, 300):
        m2 = 2 * m
        for aa in (m * (b - m) * x / ((qam + m2) * (a + m2)),
                   -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))):
            d = 1.0 + aa * d
            d = 1.0 / (d if abs(d) > tiny else tiny)
            c = 1.0 + aa / c
            c = c if abs(c) > tiny else tiny
            de = d * c
            h *= de
        if abs(de - 1.0) < 1e-10:
            break
    return h


def beta_cdf(x: float, a: float, b: float) -> float:
    if x <= 0:
        return 0.0
    if x >= 1:
        return 1.0
    lbeta = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
    front = math.exp(lbeta + a * math.log(x) + b * math.log(1 - x))
    if x < (a + 1) / (a + b + 2):
        return front * _betacf(a, b, x) / a
    return 1.0 - front * _betacf(b, a, 1 - x) / b


def beta_ppf(q: float, a: float, b: float) -> float:
    lo, hi = 0.0, 1.0
    for _ in range(60):
        mid = (lo + hi) / 2
        if beta_cdf(mid, a, b) < q:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def beta_posterior(wins: float, games: float, prior_mean: float = 0.5, prior_strength: float = 50.0,
                   cred: float = 0.90) -> dict:
    """Posterior Beta(prior_mean*k + wins, (1-prior_mean)*k + losses) com intervalo de credibilidade."""
    a = prior_mean * prior_strength + wins
    b = (1 - prior_mean) * prior_strength + (games - wins)
    a, b = max(a, 1e-3), max(b, 1e-3)
    lo_q = (1 - cred) / 2
    return {
        "mean": a / (a + b),
        "low": beta_ppf(lo_q, a, b),
        "high": beta_ppf(1 - lo_q, a, b),
        "games": games,
        "raw": wins / games if games else None,
    }


def wilson_lower(wins: float, games: float, z: float = 1.645) -> float:
    if games <= 0:
        return 0.0
    p = wins / games
    den = 1 + z * z / games
    centre = p + z * z / (2 * games)
    margin = z * math.sqrt(p * (1 - p) / games + z * z / (4 * games * games))
    return (centre - margin) / den


def fit_beta_prior(wins: np.ndarray, games: np.ndarray, min_games: int = 30) -> tuple[float, float]:
    """Bayes empírico (método dos momentos): estima média e força do prior a partir da
    dispersão real entre itens (cartas/decks). Retorna (média, força k)."""
    m = games >= min_games
    if m.sum() < 5:
        return float(wins.sum() / max(games.sum(), 1)), 50.0
    p = wins[m] / games[m]
    mu = float(np.average(p, weights=games[m]))
    var_obs = float(np.average((p - mu) ** 2, weights=games[m]))
    var_noise = float(np.average(mu * (1 - mu) / games[m], weights=games[m]))
    var_true = max(var_obs - var_noise, 1e-5)
    k = mu * (1 - mu) / var_true - 1
    return mu, float(np.clip(k, 5, 5000))


def confidence_level(n_eff: float, cfg: dict) -> str:
    if n_eff >= cfg["confidence"]["high"]:
        return "alta"
    if n_eff >= cfg["confidence"]["medium"]:
        return "média"
    if n_eff > 0:
        return "baixa"
    return "heurística"


CONFIDENCE_TEXT = {
    "alta": "Alta confiança — grande quantidade de dados reais.",
    "média": "Média confiança — quantidade razoável de dados reais.",
    "baixa": "Baixa confiança — poucos dados; estimativa fortemente puxada para a heurística.",
    "heurística": "Sem dados suficientes — estimativa heurística (regras de composição), não medida.",
}


def matchup_label(p: float, cfg: dict) -> str:
    for thr, name in cfg["labels"]:
        if p >= thr:
            return name
    return cfg["labels"][-1][1]


def ridge_logistic(X: np.ndarray, y: np.ndarray, w: np.ndarray | None = None, l2: float = 1.0,
                   iters: int = 50, fit_intercept: bool = True) -> tuple[np.ndarray, float]:
    """Regressão logística com penalização L2 via Newton-Raphson (IRLS). Para poucas features."""
    n, d = X.shape
    w = np.ones(n) if w is None else w
    Xb = np.hstack([X, np.ones((n, 1))]) if fit_intercept else X
    beta = np.zeros(Xb.shape[1])
    reg = np.full(Xb.shape[1], l2)
    if fit_intercept:
        reg[-1] = 1e-6
    for _ in range(iters):
        p = sigmoid(Xb @ beta)
        g = Xb.T @ (w * (p - y)) + reg * beta
        H = (Xb * (w * p * (1 - p))[:, None]).T @ Xb + np.diag(reg)
        step = np.linalg.solve(H, g)
        beta -= step
        if np.abs(step).max() < 1e-7:
            break
    if fit_intercept:
        return beta[:-1], float(beta[-1])
    return beta, 0.0
