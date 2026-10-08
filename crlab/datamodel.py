"""Modelo estatístico treinado em partidas reais.

Camadas (da mais direta à mais indireta), todas com tamanho de amostra explícito:
  1. Estatística do deck exato (por arquétipo adversário)      -> posterior Beta
  2. Modelo de cartas tipo Bradley-Terry com interação carta x arquétipo adversário:
        logit P(A vence B) = Σ b[c∈A] - Σ b[c∈B] + Σ M[c∈A, arq(B)] - Σ M[c∈B, arq(A)] + γ·Δnível
     treinado com regressão logística L2 ponderada por recência (meia-vida configurável).
  3. Estatísticas por carta, por par de cartas (lift de sinergia) e por arquétipo.
  4. Calibração dos pesos heurísticos (demandas por arquétipo) por regressão logística.
Validação temporal: os 10% mais recentes ficam de fora para medir log-loss/acurácia.
"""
from __future__ import annotations

import json
from collections import defaultdict
from datetime import datetime
from pathlib import Path

import numpy as np

from .archetypes import ARCHETYPES, DIMS, ArchetypeClassifier
from .catalog import Catalog
from .features import FeatureExtractor
from .stats import fit_beta_prior, logit, ridge_logistic, sigmoid
from .store import BattleStore

K = len(ARCHETYPES)
PAIR_LIFT_SCALE = 3.0  # converte lift (logit) para a escala da matriz de sinergia heurística
PAIR_SHRINK = 50.0     # pseudo-informação do encolhimento do lift de pares


class DataModel:
    def __init__(self, n_cards: int):
        self.n = n_cards
        self.info: dict = {}
        self.arrays: dict[str, np.ndarray] = {}
        self.deck_stats: dict[str, list] = {}  # deck_key -> [games, wins, arch_games[K], arch_wins[K]]
        self.opponents: dict[int, dict] = {}   # arquétipo -> {"idx": (S,8), "w": (S,), "primary": (S,)}

    # ------------------------------------------------------------------ persistência
    def save(self, path: str | Path):
        path = Path(path)
        path.parent.mkdir(parents=True, exist_ok=True)
        np.savez_compressed(path, **self.arrays)
        side = {
            "info": self.info,
            "deck_stats": self.deck_stats,
            "opponents": {str(k): {kk: np.asarray(vv).tolist() for kk, vv in v.items()} for k, v in self.opponents.items()},
            "n": self.n,
        }
        path.with_suffix(".json").write_text(json.dumps(side), encoding="utf-8")

    @classmethod
    def load(cls, path: str | Path) -> "DataModel | None":
        path = Path(path)
        if not path.exists() or not path.with_suffix(".json").exists():
            return None
        side = json.loads(path.with_suffix(".json").read_text(encoding="utf-8"))
        m = cls(side["n"])
        with np.load(path) as z:
            m.arrays = {k: z[k] for k in z.files}
        m.info = side["info"]
        m.deck_stats = side["deck_stats"]
        m.opponents = {int(k): {kk: np.asarray(vv) for kk, vv in v.items()} for k, v in side["opponents"].items()}
        return m

    def __getattr__(self, item):
        arrays = self.__dict__.get("arrays", {})
        if item in arrays:
            return arrays[item]
        raise AttributeError(item)

    @property
    def is_synthetic(self) -> bool:
        return bool(self.info.get("synthetic"))


def _to_arrays(rows, catalog: Catalog, half_life: float):
    keep, dropped = [], 0
    for r in rows:
        a = [catalog.by_key.get(k) for k in r[4].split("|")]
        b = [catalog.by_key.get(k) for k in r[5].split("|")]
        if None in a or None in b or len(a) != 8 or len(b) != 8:
            dropped += 1
            continue
        keep.append((r, [c.idx for c in a], [c.idx for c in b]))
    if not keep:
        return None, dropped
    keep.sort(key=lambda t: t[0][0])
    A = np.array([t[1] for t in keep])
    B = np.array([t[2] for t in keep])
    y = np.array([t[0][10] for t in keep], float)
    la = np.array([t[0][6] if t[0][6] is not None else np.nan for t in keep], float)
    lb = np.array([t[0][7] if t[0][7] is not None else np.nan for t in keep], float)
    dl = np.nan_to_num(la - lb)
    times = [datetime.fromisoformat(t[0][0]) for t in keep]
    last = max(times)
    age = np.array([(last - t).total_seconds() / 86400 for t in times])
    w = 0.5 ** (age / half_life) if half_life else np.ones(len(keep))
    meta = {"first": min(times).isoformat(), "last": last.isoformat(),
            "sources": sorted({t[0][1] for t in keep}), "has_levels": bool(np.isfinite(la).any())}
    return dict(A=A, B=B, y=y, dl=dl, w=w, keys_a=[t[0][4] for t in keep], keys_b=[t[0][5] for t in keep],
                meta=meta), dropped


def fit_bt(A, B, pa, pb, dl, y, w, n, l2_b, l2_m, iters=500, lr=0.05, init=None):
    """Bradley-Terry com interação carta x arquétipo. Otimização Adam em lote completo."""
    b = np.zeros(n) if init is None else init[0].copy()
    M = np.zeros(n * K) if init is None else init[1].ravel().copy()
    g = 0.0 if init is None else float(init[2])
    params = [b, M, np.array([g])]
    m1 = [np.zeros_like(p) for p in params]
    m2 = [np.zeros_like(p) for p in params]
    W = w.sum()
    fa, fb = A.ravel(), B.ravel()
    ia = (A * K + pb[:, None]).ravel()
    ib = (B * K + pa[:, None]).ravel()
    for t in range(1, iters + 1):
        b, M, gv = params
        z = b[A].sum(1) - b[B].sum(1) + M[ia].reshape(A.shape).sum(1) - M[ib].reshape(B.shape).sum(1) + gv[0] * dl
        r = w * (sigmoid(z) - y) / W
        r8 = np.repeat(r, A.shape[1])
        gb = np.bincount(fa, r8, n) - np.bincount(fb, r8, n) + l2_b * b / W
        gM = np.bincount(ia, r8, n * K) - np.bincount(ib, r8, n * K) + l2_m * M / W
        gg = np.array([(r * dl).sum()])
        for i, gr in enumerate((gb, gM, gg)):
            m1[i] = 0.9 * m1[i] + 0.1 * gr
            m2[i] = 0.999 * m2[i] + 0.001 * gr * gr
            params[i] = params[i] - lr * (m1[i] / (1 - 0.9 ** t)) / (np.sqrt(m2[i] / (1 - 0.999 ** t)) + 1e-8)
    b, M, gv = params
    return b, M.reshape(n, K), float(gv[0])


def bt_logit(b, M, gamma, A, B, pa, pb, dl):
    return b[A].sum(1) - b[B].sum(1) + M[A, pb[:, None]].sum(1) - M[B, pa[:, None]].sum(1) + gamma * dl


def _logloss(p, y):
    p = np.clip(p, 1e-6, 1 - 1e-6)
    return float(-np.mean(y * np.log(p) + (1 - y) * np.log(1 - p)))


def train_model(store: BattleStore, catalog: Catalog, cfg: dict, heuristic_engine=None,
                days: int | None = None, sources: list[str] | None = None, log=print) -> DataModel:
    dcfg = cfg["data"]
    rows = store.load(days=days if days is not None else dcfg["days"], sources=sources)
    data, dropped = _to_arrays(rows, catalog, dcfg["half_life_days"])
    if data is None:
        raise ValueError("Nenhuma partida utilizável no período/fonte selecionados.")
    n = catalog.n
    A, B, y, dl, w = data["A"], data["B"], data["y"], data["dl"], data["w"]
    N = len(y)
    log(f"Partidas utilizáveis: {N} (descartadas por carta desconhecida: {dropped})")
    clf = ArchetypeClassifier(catalog)
    pa, la = clf.classify_batch(A)
    pb, lb = clf.classify_batch(B)

    model = DataModel(n)
    model.info = {
        "battles": N, "dropped": dropped, **data["meta"], "days": days if days is not None else dcfg["days"],
        "half_life_days": dcfg["half_life_days"], "synthetic": "synthetic" in data["meta"]["sources"],
        "trained_at": datetime.now().isoformat(timespec="seconds"),
    }

    # ---------------------------------------------------------------- validação temporal
    split = int(N * 0.9)
    if N >= 500:
        b0, M0, g0 = fit_bt(A[:split], B[:split], pa[:split], pb[:split], dl[:split], y[:split], w[:split], n,
                            dcfg["l2_card"], dcfg["l2_interaction"])
        te = slice(split, N)
        p_te = sigmoid(bt_logit(b0, M0, g0, A[te], B[te], pa[te], pb[te], dl[te]))
        yt = y[te]
        model.info["validation"] = {
            "holdout": int(N - split),
            "logloss_model": _logloss(p_te, yt),
            "logloss_baseline": _logloss(np.full_like(yt, 0.5), yt),
            "accuracy_model": float(np.mean((p_te > 0.5) == (yt > 0.5))),
            "brier_model": float(np.mean((p_te - yt) ** 2)),
        }
        init = (b0, M0, g0)
    else:
        init = None
    b, M, gamma = fit_bt(A, B, pa, pb, dl, y, w, n, dcfg["l2_card"], dcfg["l2_interaction"],
                         iters=300 if init is not None else 500, init=init)
    if not data["meta"]["has_levels"]:
        gamma = cfg["levels"]["gamma_per_level"]
    model.arrays.update(bt_b=b, bt_M=M, bt_gamma=np.array(gamma))
    log(f"Modelo de cartas treinado (γ por nível = {gamma:.3f})")

    # ---------------------------------------------------------------- estatísticas descritivas
    both_idx = np.vstack([A, B])
    both_y = np.concatenate([y, 1 - y])
    both_opp = np.concatenate([pb, pa])
    rep = lambda v: np.repeat(v, 8)  # noqa: E731
    flat = both_idx.ravel()
    model.arrays["card_games"] = np.bincount(flat, minlength=n).astype(float)
    model.arrays["card_wins"] = np.bincount(flat, rep(both_y), n)
    fa = (both_idx * K + both_opp[:, None]).ravel()
    model.arrays["card_arch_games"] = np.bincount(fa, minlength=n * K).reshape(n, K).astype(float)
    model.arrays["card_arch_wins"] = np.bincount(fa, rep(both_y), n * K).reshape(n, K)
    model.arrays["usage"] = model.card_games / (2 * N)
    # Sinergia observada: resíduo do modelo de cartas nas partidas que contêm o par, ou seja, o
    # quanto o par vence ALÉM do que a força individual das cartas explica (passo de Newton com
    # encolhimento: lift = Σ resíduo / (Σ p(1-p) + k)).
    z = bt_logit(b, M, gamma, A, B, pa, pb, dl)
    p_side = np.concatenate([sigmoid(z), sigmoid(-z)])
    resid = both_y - p_side
    info = p_side * (1 - p_side)
    pg = np.zeros(n * n)
    pr = np.zeros(n * n)
    pi = np.zeros(n * n)
    for i in range(8):
        for j in range(8):
            if i == j:
                continue
            f = both_idx[:, i] * n + both_idx[:, j]
            pg += np.bincount(f, minlength=n * n)
            pr += np.bincount(f, resid, n * n)
            pi += np.bincount(f, info, n * n)
    pg, pr, pi = pg.reshape(n, n), pr.reshape(n, n), pi.reshape(n, n)
    mu, k_card = fit_beta_prior(model.card_wins, model.card_games)
    card_wr = (model.card_wins + mu * k_card) / (model.card_games + k_card)
    lift = pr / (pi + PAIR_SHRINK)
    model.arrays.update(pair_games=pg, pair_lift=lift * PAIR_LIFT_SCALE, card_wr=card_wr)
    model.info["card_prior"] = {"mean": mu, "strength": k_card}

    # meta: frequência do arquétipo primário (ponderada por recência)
    prim = np.concatenate([pa, pb])
    ww = np.concatenate([w, w])
    freq = np.bincount(prim, ww, K)
    model.arrays["meta"] = freq / freq.sum()
    model.arrays["arch_games"] = np.bincount(prim, minlength=K).astype(float)

    # decks exatos
    ds: dict[str, list] = defaultdict(lambda: [0, 0.0, [0] * K, [0.0] * K])
    for keys, opp, res in ((data["keys_a"], pb, y), (data["keys_b"], pa, 1 - y)):
        for kk, o, r in zip(keys, opp, res):
            s = ds[kk]
            s[0] += 1
            s[1] += float(r)
            s[2][o] += 1
            s[3][o] += float(r)
    model.deck_stats = {k: v for k, v in ds.items() if v[0] >= 3}

    # amostras de adversários por arquétipo + capacidade média observada
    fx = FeatureExtractor(catalog)
    counts: dict[str, int] = defaultdict(int)
    for kk in data["keys_a"] + data["keys_b"]:
        counts[kk] += 1
    uniq = list(counts)
    U = np.array([[catalog.by_key[c].idx for c in kk.split("|")] for kk in uniq])
    cu = np.array([counts[k] for k in uniq], float)
    pu, _ = clf.classify_batch(U)
    caps = fx.capabilities(U)
    arch_caps = np.zeros((K, len(DIMS)))
    for a in range(K):
        m = pu == a
        if not m.any():
            continue
        arch_caps[a] = np.average(caps[m], axis=0, weights=cu[m])
        order = np.argsort(-cu[m])[: dcfg["opponent_samples"]]
        model.opponents[a] = {"idx": U[m][order], "w": cu[m][order], "primary": pu[m][order]}
    model.arrays["arch_caps"] = arch_caps

    # ---------------------------------------------------------------- calibração da heurística
    if heuristic_engine is not None:
        calibrate_heuristic(model, heuristic_engine, A, B, pa, pb, y, w, log=log)
        calibrate_factor_weights(model, heuristic_engine, cfg, log=log)
    return model


def calibrate_heuristic(model: DataModel, engine, A, B, pa, pb, y, w, log=print):
    """Ajusta, por arquétipo adversário, o quanto cada capacidade do deck realmente importa.
    Resultado: theta[k, d] em unidades de logit, usado no lugar de alpha*demanda quando há dados."""
    idx = np.vstack([A, B])
    opp = np.concatenate([pb, pa])
    yy = np.concatenate([y, 1 - y])
    ww = np.concatenate([w, w])
    caps = engine.fx.capabilities(idx) - engine.base_caps
    theta = np.zeros((K, len(DIMS)))
    nk = np.zeros(K)
    for a in range(K):
        m = opp == a
        nk[a] = m.sum()
        if nk[a] < 200:
            continue
        coef, _ = ridge_logistic(caps[m], yy[m], ww[m], l2=5.0)
        theta[a] = coef
    model.arrays["calib_theta"] = theta
    model.arrays["calib_n"] = nk
    log("Pesos de demanda calibrados para: " + ", ".join(ARCHETYPES[a] for a in range(K) if nk[a] >= 200))


def calibrate_factor_weights(model: DataModel, engine, cfg: dict, log=print, max_decks: int = 400):
    """Pesos do índice de fatores via mínimos quadrados não-negativos: quais fatores (calculados
    pela heurística) melhor explicam a taxa de vitória observada dos decks com amostra suficiente."""
    min_g = cfg["data"]["min_deck_games"]
    decks = sorted(((k, v) for k, v in model.deck_stats.items() if v[0] >= min_g), key=lambda kv: -kv[1][0])
    decks = decks[:max_decks]
    if len(decks) < 30:
        log(f"Pesos do índice de fatores: poucos decks com {min_g}+ partidas ({len(decks)}); mantidos os padrões.")
        return
    names, X, yv, wv = None, [], [], []
    for k, (g, wins, *_rest) in decks:
        rep = engine.analyze([engine.catalog.by_key[c].idx for c in k.split("|")])
        items = [it for it in rep["factors"]["items"] if it["available"] and it["factor"] not in ("niveis",)]
        names = [it["factor"] for it in items]
        X.append([it["value"] for it in items])
        yv.append((wins + 25) / (g + 50))
        wv.append(g)
    X, yv, wv = np.array(X), np.array(yv), np.array(wv, float)
    Xc = X - np.average(X, axis=0, weights=wv)
    yc = yv - np.average(yv, weights=wv)
    beta = np.zeros(X.shape[1])
    step = 1.0 / (np.linalg.norm((Xc * wv[:, None]).T @ Xc / wv.sum(), 2) + 1e-9)
    for _ in range(3000):  # gradiente projetado (NNLS) com leve ridge
        grad = (Xc * wv[:, None]).T @ (Xc @ beta - yc) / wv.sum() + 1e-4 * beta
        beta = np.maximum(beta - step * grad, 0)
    if beta.sum() <= 0:
        log("Pesos do índice de fatores: nenhum fator explicou a variação; mantidos os padrões.")
        return
    default_mean = np.mean([cfg["factor_weights"][nm] for nm in names])
    weights = beta / beta.mean() * default_mean
    model.info["factor_weights"] = {nm: round(float(v), 3) for nm, v in zip(names, weights)}
    log(f"Pesos do índice de fatores calibrados com {len(decks)} decks.")
