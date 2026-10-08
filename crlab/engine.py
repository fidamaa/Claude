"""Motor de avaliação: combina heurística explicável, modelo de dados e níveis das cartas.

Pipeline de uma estimativa de matchup (deck D contra arquétipo A):
  1. Heurística: capacidades de D vs. o que A exige (defesa) + o quanto A é fraco no que D exige
     (ataque) + sinergia + coerência + força teórica das cartas.
  2. Modelo de cartas treinado em partidas (se houver), misturado à heurística na proporção
     n_suporte / (n_suporte + model_k): poucos dados -> heurística domina.
  3. Ajuste de nível (γ por nível de diferença em relação à referência do jogador).
  4. Partidas do deck exato contra A atualizam a estimativa como posterior Beta.
"""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .archetypes import A_INDEX, ARCH_PT, ARCHETYPES, DIMS, ArchetypeClassifier, demand_matrix
from .catalog import DATA_DIR, Catalog, get_catalog
from .datamodel import DataModel
from .explain import DIM_BAD, DIM_GOOD, DIM_PT, VULNERABILITIES, fmt_pct, join_pt
from .features import FeatureExtractor, SynergyModel
import copy

from .roles import deck_roles
from .levels import EVO, FORM_CODES, FORM_NAMES, HERO, NORMAL, SLOT_ALLOWED, LevelModel, PlayerCollection, arrange_slots, forms_valid
from .settings import load_settings
from .stats import CONFIDENCE_TEXT, beta_posterior, confidence_level, logit, matchup_label, sigmoid
from .store import deck_key

K = len(ARCHETYPES)


class DeckError(ValueError):
    pass


class Engine:
    def __init__(self, catalog: Catalog | None = None, cfg: dict | None = None, model: DataModel | None = None):
        self.catalog = catalog or get_catalog()
        self.cfg = cfg or load_settings()
        self.fx = FeatureExtractor(self.catalog)
        self.syn = SynergyModel(self.catalog)
        self.clf = ArchetypeClassifier(self.catalog)
        self.levels = LevelModel(self.catalog, self.cfg)
        self.demand = demand_matrix()
        refs = json.loads((DATA_DIR / "reference_decks.json").read_text(encoding="utf-8"))["decks"]
        self.reference_decks = [{"name": d["name"], "idx": [self.catalog.by_key[c].idx for c in d["cards"]]}
                                for d in refs]
        R = np.array([d["idx"] for d in self.reference_decks])
        self._R = R
        self.model: DataModel | None = None
        self._set_baselines()
        if model is not None:
            self.attach_model(model)

    # ---------------------------------------------------------------- configuração
    def _set_baselines(self):
        R = self._R
        caps = self.fx.capabilities(R)
        self.base_caps = caps.mean(0)
        # Metade da sinergia média dos decks de referência: a tabela de pares é incompleta, então
        # um deck sem pares catalogados não deve ser punido como se tivesse sinergia ruim.
        self.base_syn = 0.5 * float(self.syn.score(R).mean())
        self.base_coh = float(self.fx.coherence(R).mean())
        self.base_qual = float(self.fx.quality(R).mean())
        self.base_avg = float(self.catalog.features["elixir"][R].mean())
        _, labels = self.clf.classify_batch(R)
        arch_caps = np.tile(self.base_caps, (K, 1))
        for a in range(K):
            if labels[:, a].any():
                arch_caps[a] = caps[labels[:, a]].mean(0)
        self.ref_arch_caps = arch_caps
        self.arch_caps = arch_caps.copy()
        h = self.cfg["heuristic"]
        self.Wd = h["alpha"] * self.demand
        mp = self.cfg["meta_prior"]
        self.meta = np.array([mp.get(a, 0.0) for a in ARCHETYPES])
        self.meta /= self.meta.sum()
        self.meta_source = "heurística (distribuição padrão configurável)"
        self.gamma = self.cfg["levels"]["gamma_per_level"]

    def attach_model(self, model: DataModel):
        if model.n != self.catalog.n:  # catálogo mudou (cartas novas): modelo precisa ser retreinado
            self.model = None
            self._model_note = "O catálogo de cartas mudou desde o último treino; o modelo será retreinado na próxima coleta."
            return
        self.model = model
        self.__dict__.pop("_opp_cache", None)
        n_arch = model.arch_games
        w = (n_arch / (n_arch + 500))[:, None]
        self.arch_caps = (1 - w) * self.ref_arch_caps + w * np.where(model.arch_caps.any(1)[:, None],
                                                                     model.arch_caps, self.ref_arch_caps)
        self.syn.apply_data(model.pair_lift, model.pair_games)
        if "calib_theta" in model.arrays:
            lam = (model.calib_n / (model.calib_n + self.cfg["blend"]["calibration_k"]))[:, None]
            self.Wd = (1 - lam) * self.cfg["heuristic"]["alpha"] * self.demand + lam * model.calib_theta
        self.meta = model.meta.copy()
        src = "dados reais" if not model.is_synthetic else "dados SINTÉTICOS (demonstração)"
        self.meta_source = f"{src}: {model.info['battles']} partidas de {model.info['first'][:10]} a {model.info['last'][:10]}"
        self.gamma = float(model.bt_gamma)
        self.levels.gamma = self.gamma

    @classmethod
    def from_settings(cls, cfg: dict | None = None) -> "Engine":
        cfg = cfg or load_settings()
        model = DataModel.load(cfg["data"]["model_path"]) if Path(cfg["data"]["model_path"]).exists() else None
        return cls(cfg=cfg, model=model)

    # ---------------------------------------------------------------- entrada
    def parse_deck(self, names: list[str]) -> list[int]:
        cards = self.catalog.resolve_many(names)
        idx = [c.idx for c in cards]
        if len(idx) != 8:
            raise DeckError(f"Um deck precisa de 8 cartas (recebidas {len(idx)}).")
        if len(set(idx)) != 8:
            raise DeckError("Cartas repetidas no deck.")
        if sum(c.is_champion for c in cards) > 1:
            raise DeckError("Um deck pode ter no máximo um campeão.")
        return idx

    def parse_forms(self, idx: list[int], forms, col: PlayerCollection | None, warnings: list[str]) -> list[int] | None:
        """Valida formas por posição (1ª: normal/Evo; 2ª: normal/Herói; 3ª: normal/Evo/Herói)."""
        if forms is None:
            return None
        if len(forms) != len(idx):
            raise DeckError("Informe uma forma (normal, evo ou hero) para cada uma das 8 cartas.")
        out = []
        for pos, (i, f) in enumerate(zip(idx, forms)):
            code = FORM_CODES.get(str(f or "normal").lower())
            if code is None:
                raise DeckError(f"Forma desconhecida: {f}. Use normal, evo ou hero.")
            card = self.catalog.cards[i]
            if code not in SLOT_ALLOWED[pos]:
                slot = ["1ª (Evolução)", "2ª (Herói)", "3ª (Evolução ou Herói)"][pos] if pos < 3 else f"{pos + 1}ª"
                raise DeckError(f"A posição {slot} não aceita {card.name_pt} como {FORM_NAMES[code]}.")
            if code == EVO and not card.evo:
                raise DeckError(f"{card.name_pt} não tem Evolução.")
            if code == HERO and not card.has("hero"):
                raise DeckError(f"{card.name_pt} não tem versão Herói.")
            if col is not None and code == EVO and i not in col.evolutions:
                warnings.append(f"Você não tem a Evolução de {card.name_pt}; considerada como carta normal.")
                code = NORMAL
            if col is not None and code == HERO and i not in col.heroes:
                warnings.append(f"Você não tem o Herói {card.name_pt}; considerado como carta normal.")
                code = NORMAL
            out.append(code)
        if not forms_valid(out):
            raise DeckError("No máximo 2 Evoluções, 2 Heróis e 3 formas especiais por deck.")
        return out

    # ---------------------------------------------------------------- avaliação em lote
    def heuristic_logits(self, caps, syn, coh, qual, primary, avg):
        h = self.cfg["heuristic"]
        defense = (caps - self.base_caps) @ self.Wd.T
        # O termo ofensivo só vale na proporção da pressão real do deck (evita "ganhar" um rótulo
        # de arquétipo favorável sem ter de fato a condição de vitória correspondente).
        gate = np.clip(caps[:, DIMS.index("pressure")] / self.base_caps[DIMS.index("pressure")], 0, 1.2)
        offense = -(self.Wd[primary] @ (self.arch_caps - self.base_caps).T) * gate[:, None]
        extra = (h["beta_synergy"] * (syn - self.base_syn) + h["beta_coherence"] * (coh - self.base_coh)
                 + h["beta_quality"] * (qual - self.base_qual) - h["beta_cost"] * (avg - self.base_avg))
        L = defense + h["offense_share"] * offense + extra[:, None]
        # Heurística não pode afirmar matchups extremos: limite suave de magnitude.
        c = h["max_logit"]
        return c * np.tanh(L / c)

    def _opponent_tables(self, fast: bool):
        """Pré-calcula, por arquétipo, a força dos decks adversários amostrados (S x K) e os pesos.
        No modo rápido (busca do gerador) usa só os 48 adversários mais frequentes de cada arquétipo."""
        key = "fast" if fast else "full"
        cache = self.__dict__.setdefault("_opp_cache", {})
        if key not in cache:
            m = self.model
            b, M = m.bt_b, m.bt_M
            tables = {}
            for a in range(K):
                opp = m.opponents.get(a)
                if opp is None or len(opp["w"]) == 0:
                    continue
                O, w = opp["idx"], np.asarray(opp["w"], float)
                if fast and len(w) > 48:
                    keep = np.argsort(-w)[:48]
                    O, w = O[keep], w[keep]
                T = b[O].sum(1)[:, None] + M[O].sum(1)
                if "bonus" in opp:
                    bonus = np.asarray(opp["bonus"], float)
                    if fast and len(opp["w"]) > 48:
                        bonus = bonus[np.argsort(-np.asarray(opp["w"], float))[:48]]
                    T = T + bonus[:, None]
                tables[a] = (T, w / w.sum())
            cache[key] = tables
        return cache[key]

    def model_logits(self, idx, primary, fast: bool = False, forms=None):
        m = self.model
        b, M = m.bt_b, m.bt_M
        x = b[idx].sum(1)[:, None] + M[idx].sum(1)  # B x K
        if forms is not None and "bt_ev" in m.arrays:
            x = x + (m.bt_ev[idx] * (forms == EVO) + m.bt_hv[idx] * (forms == HERO)).sum(1)[:, None]
        out = np.zeros_like(x)
        for a, (T, w) in self._opponent_tables(fast).items():
            t = T[:, primary].T  # B x S (depende do arquétipo do deck avaliado)
            out[:, a] = logit(sigmoid(x[:, a:a + 1] - t) @ w)
        support = m.card_arch_games[idx].min(1)  # B x K: carta menos observada limita a confiança
        return out, support

    def _forced_values(self, col, force: dict | None):
        """Valores de formas para escolha (sel) e para bônus (real), aplicando formas exigidas pelo usuário."""
        real = self.levels.form_values(col)
        if not force:
            return real, real
        ev, hv = real[0].copy(), real[1].copy()
        theo_ev, theo_hv = self.levels.form_values(None)
        sel_ev, sel_hv = ev.copy(), hv.copy()
        for i, f in force.items():
            if f == EVO:
                ev[i] = max(ev[i], theo_ev[i]); sel_ev[i] = 1e3; sel_hv[i] = 0.0  # noqa: E702
            elif f == HERO:
                hv[i] = max(hv[i], theo_hv[i]); sel_hv[i] = 1e3; sel_ev[i] = 0.0  # noqa: E702
            else:
                sel_ev[i] = sel_hv[i] = 0.0
        return (sel_ev, sel_hv), (ev, hv)

    def evaluate(self, idx, col: PlayerCollection | None = None, detail: bool = False, fast: bool = False,
                 forms=None, force: dict | None = None) -> dict:
        idx = np.atleast_2d(np.asarray(idx))
        sel, values = self._forced_values(col, force)
        forms = self.levels.auto_forms(idx, col, sel) if forms is None else np.atleast_2d(np.asarray(forms))
        form_bonus = self.levels.form_bonus(idx, forms, col, values)
        primary, labels = self.clf.classify_batch(idx)
        caps = self.fx.capabilities(idx)
        syn = self.syn.score(idx)
        coh = self.fx.coherence(idx)
        qual = self.fx.quality(idx)
        avg = self.catalog.features["elixir"][idx].mean(1)
        # Evoluções/Heróis entram na parte heurística como níveis-equivalentes; com dados, o modelo
        # aprende o efeito real de cada forma (bt_ev / bt_hv) e a mistura pondera as duas fontes.
        L_h = self.heuristic_logits(caps, syn, coh, qual, primary, avg) + self.gamma * form_bonus[:, None]
        L = L_h
        wm = np.zeros_like(L_h)
        support = np.zeros_like(L_h)
        L_m = None
        if self.model is not None:
            L_m, support = self.model_logits(idx, primary, fast=fast, forms=forms)
            wm = support / (support + self.cfg["blend"]["model_k"])
            L = (1 - wm) * L_h + wm * L_m
        gaps = self.levels.gaps(idx, col)
        L = L + self.gamma * gaps[:, None]
        p = sigmoid(L)
        res = {"p": p, "primary": primary, "labels": labels, "gaps": gaps, "forms": forms, "form_bonus": form_bonus,
               **self.objective(p)}
        if detail:
            res.update(caps=caps, syn=syn, coh=coh, qual=qual, L_h=L_h, L_m=L_m, wm=wm, support=support)
        return res

    def objective(self, p):
        m = self.meta
        ev = p @ m
        sd = np.sqrt(((p - ev[:, None]) ** 2) @ m)
        relevant = m > 0.01
        worst = p[:, relevant].min(1)
        o = self.cfg["objective"]
        if o["mode"] == "mean":
            score = ev
        elif o["mode"] == "maximin":
            score = worst
        else:
            score = ev - o["lambda"] * sd
        return {"ev": ev, "sd": sd, "worst": worst, "score": score}

    # ---------------------------------------------------------------- dados do deck exato
    def exact_stats(self, idx):
        if self.model is None:
            return None
        return self.model.deck_stats.get(deck_key(self.catalog.cards[i].key for i in idx))

    def finalize_matchups(self, idx, ev: dict, row: int = 0) -> list[dict]:
        """Aplica partidas do deck exato (posterior Beta) e calcula confiança por arquétipo."""
        cfg = self.cfg
        exact = self.exact_stats(idx)
        out = []
        for a in range(K):
            prior = float(ev["p"][row, a])
            games, wins = (exact[2][a], exact[3][a]) if exact else (0, 0.0)
            post = beta_posterior(wins, games, prior, cfg["blend"]["exact_prior_strength"])
            support = float(ev["support"][row, a]) if "support" in ev else 0.0
            n_eff = games + cfg["blend"]["support_weight"] * support
            conf = confidence_level(n_eff, cfg)
            if games > 0:
                source = "dados do deck exato + modelo" if support > 0 else "dados do deck exato + heurística"
            elif support > 0 and float(ev["wm"][row, a]) > 0.2:
                source = "modelo estatístico de cartas + heurística"
            else:
                source = "heurística"
            p = post["mean"]
            out.append({
                "archetype": ARCHETYPES[a], "name": ARCH_PT[ARCHETYPES[a]], "win_prob": p, "label": matchup_label(p, cfg),
                "interval": [post["low"], post["high"]] if (games > 0 or support > 0) else None,
                "confidence": conf, "source": source, "exact_games": games,
                "exact_winrate": (wins / games) if games else None, "support_games": int(support),
                "model_weight": float(ev["wm"][row, a]) if "wm" in ev else 0.0,
                "meta_share": float(self.meta[a]),
            })
        return out

    # ---------------------------------------------------------------- explicações
    def matchup_reasons(self, ev: dict, a: int, row: int = 0, top: int = 3) -> tuple[list[str], list[str]]:
        h = self.cfg["heuristic"]
        caps = ev["caps"][row]
        prim = ev["primary"][row]
        dpos, dneg = [], []
        for d, name in enumerate(DIMS):
            c_def = self.Wd[a, d] * (caps[d] - self.base_caps[d])
            c_off = -h["offense_share"] * self.Wd[prim, d] * (self.arch_caps[a, d] - self.base_caps[d])
            if c_def > 0.03:
                dpos.append((c_def, f"{DIM_GOOD[name]}"))
            elif c_def < -0.03:
                dneg.append((c_def, f"{DIM_BAD[name]}"))
            if c_off > 0.03:
                dpos.append((c_off, f"decks {ARCH_PT[ARCHETYPES[a]]} costumam ter {DIM_BAD[name]}, o que favorece seu plano de jogo"))
            elif c_off < -0.03:
                dneg.append((c_off, f"decks {ARCH_PT[ARCHETYPES[a]]} costumam ter {DIM_GOOD[name]}, justamente o que atrapalha seu plano de jogo"))
        c_syn = h["beta_synergy"] * (ev["syn"][row] - self.base_syn)
        if c_syn > 0.12:
            dpos.append((c_syn, "boa sinergia entre as cartas"))
        elif c_syn < -0.05:
            dneg.append((c_syn, "pouca sinergia entre as cartas"))
        c_coh = h["beta_coherence"] * (ev["coh"][row] - self.base_coh)
        if c_coh < -0.05:
            dneg.append((c_coh, "problemas estruturais no deck"))
        c_lv = self.gamma * ev["gaps"][row]
        if c_lv > 0.05:
            dpos.append((c_lv, "cartas acima do nível de referência"))
        elif c_lv < -0.05:
            dneg.append((c_lv, "cartas abaixo do nível de referência"))
        dpos.sort(key=lambda x: -x[0])
        dneg.sort(key=lambda x: x[0])
        return [t for _, t in dpos[:top]], [t for _, t in dneg[:top]]

    # ---------------------------------------------------------------- análise completa
    def analyze(self, names_or_idx, col: PlayerCollection | None = None, forms=None, force: dict | None = None) -> dict:
        """forms: None (escolha automática das melhores Evos/Heróis disponíveis) ou uma forma por
        posição, na ordem do deck: "normal" | "evo" | "hero"."""
        idx = (self.parse_deck(names_or_idx) if isinstance(names_or_idx[0], str) else list(names_or_idx))
        warnings: list[str] = list(col.warnings) if col is not None else []
        codes = self.parse_forms(idx, forms, col, warnings)
        forms_auto = codes is None
        if forms_auto:
            codes = [int(x) for x in self.levels.auto_forms([idx], col, self._forced_values(col, force)[0])[0]]
        idx, codes = arrange_slots(idx, codes) if forms_auto else (idx, codes)
        cards = [self.catalog.cards[i] for i in idx]
        ev = self.evaluate([idx], col, detail=True, forms=[codes], force=force)
        matchups = self.finalize_matchups(idx, ev)
        for a, m in enumerate(matchups):
            pos, neg = self.matchup_reasons(ev, a)
            m["reasons_for"], m["reasons_against"] = pos, neg
            m["explanation"] = self._matchup_sentence(m, pos, neg)
            if m["exact_games"]:
                m["explanation"] += (f" Dados: {m['exact_games']} partidas reais deste deck contra o arquétipo "
                                     f"({fmt_pct(m['exact_winrate'])} de vitórias brutas).")
        p_final = np.array([[m["win_prob"] for m in matchups]])
        overall = {k: float(v[0]) for k, v in self.objective(p_final).items()}
        caps = ev["caps"][0]
        primary = ARCHETYPES[ev["primary"][0]]
        labels = [ARCHETYPES[i] for i in np.flatnonzero(ev["labels"][0])]
        avg = float(np.mean([c.elixir for c in cards]))
        cyc = int(sum(sorted(c.elixir for c in cards)[:4]))

        capabilities = [{
            "key": d, "name": DIM_PT[d], "value": round(float(caps[i]), 3), "baseline": round(float(self.base_caps[i]), 3),
            "rating": "forte" if caps[i] - self.base_caps[i] > 0.1 else "fraca" if caps[i] - self.base_caps[i] < -0.1 else "média",
        } for i, d in enumerate(DIMS)]
        strengths = [DIM_GOOD[d] for i, d in enumerate(DIMS) if caps[i] - self.base_caps[i] > 0.12]
        vulns = self._vulnerabilities(idx, caps, matchups)
        fit = self._leave_one_out(idx, col, float(ev["ev"][0]), codes)
        card_rows = self._card_details(idx, col, fit, codes)
        factors = self._factors(idx, ev, overall, col)
        exact = self.exact_stats(idx)
        overall_conf = self._overall_confidence(matchups)
        report = {
            "deck": [c.key for c in cards],
            "deck_pt": [c.name_pt for c in cards],
            "avg_elixir": round(avg, 2),
            "cycle_cost": cyc,
            "archetype": {"primary": primary, "primary_pt": ARCH_PT[primary], "labels": labels,
                          "labels_pt": [ARCH_PT[x] for x in labels]},
            "matchups": matchups,
            "overall": {
                **{k: round(v, 4) for k, v in overall.items()},
                "meta_source": self.meta_source,
                "objective_mode": self.cfg["objective"]["mode"],
                "note": "Média ponderada pela frequência de cada arquétipo no meta; 'score' penaliza "
                        "matchups muito desiguais (consistência).",
            },
            "capabilities": capabilities,
            "strengths": strengths,
            "vulnerabilities": vulns,
            "synergies": self.syn.pairs(idx),
            "coherence": {"value": round(float(ev["coh"][0]), 3), "issues": self.fx.coherence_issues([idx])},
            "cards": card_rows,
            "levels": self._level_summary(idx, col, ev, codes),
            "slots": [{"card": self.catalog.cards[i].key, "form": FORM_NAMES[f]} for i, f in zip(idx, codes)],
            "forms_auto": forms_auto,
            "roles": deck_roles(self.catalog, idx),
            "improvements": self._improvements(idx, codes, col, ev) if col is not None else None,
            "warnings": warnings,
            "factors": factors,
            "historical": ({"games": exact[0], "wins": exact[1],
                            "posterior": beta_posterior(exact[1], exact[0], 0.5, 50)} if exact else None),
            "confidence": overall_conf,
            "data": self.data_status(),
        }
        report["summary"] = self._summary(report)
        return report

    def _matchup_sentence(self, m, pos, neg) -> str:
        head = f"Contra {m['name']}: {m['label']} ({fmt_pct(m['win_prob'])})."
        if m["win_prob"] >= 0.5:
            body = f" Motivo: {join_pt(pos[:2])}." if pos else ""
            if neg:
                body += f" Atenção: {neg[0]}."
        else:
            body = f" Motivo: {join_pt(neg[:2])}." if neg else ""
            if pos:
                body += f" A favor: {pos[0]}."
        return head + body

    def _vulnerabilities(self, idx, caps, matchups) -> list[dict]:
        out = []
        f = self.catalog.features
        for d, thr, msg in VULNERABILITIES:
            v = caps[DIMS.index(d)]
            if v < thr:
                out.append({"dimension": d, "severity": round(float(thr - v), 3), "message": msg})
        has_small = f["small"][idx].any()
        has_big = (f["big"][idx] + f["antibldg"][idx]).any()
        if not has_small:
            out.append({"dimension": "spells", "severity": 0.3,
                        "message": "Sem feitiço pequeno — vulnerável a decks Bait (Barril de Goblins, Princesa, Gangue)."})
        if not has_big:
            out.append({"dimension": "spells", "severity": 0.2,
                        "message": "Sem feitiço pesado — difícil punir suportes (Mosqueteira, Mago) e finalizar torres."})
        tank_wc = (f["tank"][idx] * f["bt"][idx]).any()
        if tank_wc and not f["reset"][idx].any():
            out.append({"dimension": "reset", "severity": 0.15,
                        "message": "Seu tanque não tem suporte de reset (Zap, Mago Elétrico, Espírito Elétrico): "
                                   "Torre/Dragão Infernal podem neutralizá-lo."})
        if f["wc"][idx].sum() == 0 and f["wc2"][idx].sum() > 0:
            out.append({"dimension": "pressure", "severity": 0.1,
                        "message": "Condição de vitória apenas secundária: o dano em torre depende de contra-ataques."})
        for m in matchups:
            if m["win_prob"] < 0.45:
                out.append({"dimension": "matchup", "severity": round(0.5 - m["win_prob"], 3),
                            "message": f"Matchup ruim contra {m['name']} ({fmt_pct(m['win_prob'])})."})
        return sorted(out, key=lambda x: -x["severity"])

    def _leave_one_out(self, idx, col, ev_full, forms) -> list[float]:
        sub = np.array([[j for j in idx if j != i] for i in idx])
        fsub = np.array([[f for j, f in zip(idx, forms) if j != i] for i in idx])
        r = self.evaluate(sub, col, forms=fsub)
        return [float(ev_full - e) for e in r["ev"]]

    def _card_details(self, idx, col, fit, forms) -> list[dict]:
        lv = {d["card"]: d for d in self.levels.card_detail(idx, col, forms)}
        rows = []
        for i, contrib in zip(idx, fit):
            c = self.catalog.cards[i]
            row = {
                "card": c.key, "name_pt": c.name_pt, "elixir": c.elixir, "type": c.type,
                "theoretical": {"tier": c.tier, "source": "prior heurístico do catálogo"},
                "at_level": lv[c.key],
                "fit": {"ev_contribution": round(contrib, 4),
                        "note": "quanto a média vs meta cai ao remover esta carta (compatibilidade com o deck)"},
                "meta": None,
            }
            if self.model is not None:
                g = float(self.model.card_games[i])
                row["meta"] = {
                    "games": int(g), "usage": round(float(self.model.usage[i]), 4),
                    "winrate_shrunk": round(float(self.model.card_wr[i]), 4),
                    "winrate_raw": round(float(self.model.card_wins[i] / g), 4) if g else None,
                    "model_strength": round(float(self.model.bt_b[i]), 4),
                }
            rows.append(row)
        return rows

    def _level_summary(self, idx, col, ev, forms) -> dict:
        if col is None:
            return {"provided": False, "note": "Níveis não informados: análise considera todas as cartas no mesmo nível do adversário."}
        gap = float(ev["gaps"][0])
        flat = copy.deepcopy(col)
        flat.levels = {k: col.reference_level for k in col.levels}
        ev0 = self.evaluate([idx], flat, forms=[forms])["ev"][0]
        evl = float(ev["ev"][0])
        under = [d for d in self.levels.card_detail(idx, col, forms) if d["gap"] <= -1]
        missing = [self.catalog.cards[i].key for i in idx if i not in col.levels]
        return {
            "provided": True, "reference_level": col.reference_level, "effective_gap": round(gap, 2),
            "impact_ev": round(evl - float(ev0), 4),
            "underleveled": under, "not_owned": missing,
            "evolutions_used": [self.catalog.cards[i].key for i, f in zip(idx, forms) if f == EVO],
            "heroes_used": [self.catalog.cards[i].key for i, f in zip(idx, forms) if f == HERO],
            "note": f"Cada nível de diferença ≈ {self.gamma:.2f} em logit (~{100 * (sigmoid(self.gamma) - 0.5):.1f} p.p.).",
        }

    def _improvements(self, idx, forms, col, ev) -> dict:
        """O que mais melhoraria ESTE deck para ESTE jogador: desbloquear Evos/Heróis das cartas do
        deck e subir cartas abaixo do nível de referência (ganho em p.p. na média vs meta)."""
        base = float(self.evaluate([idx], col)["ev"][0])  # formas automáticas com o que o jogador tem
        unlocks, upgrades = [], []
        for i in idx:
            c = self.catalog.cards[i]
            for kind, capable, owned_set in (("evo", c.evo, col.evolutions), ("hero", c.has("hero"), col.heroes)):
                if not capable or i in owned_set:
                    continue
                c2 = copy.deepcopy(col)
                (c2.evolutions if kind == "evo" else c2.heroes).add(i)
                c2.levels.setdefault(i, col.reference_level)
                gain = float(self.evaluate([idx], c2)["ev"][0]) - base
                if gain > 0.002:
                    unlocks.append({"card": c.key, "kind": kind, "gain": round(gain, 4)})
            lvl = col.levels.get(i, col.reference_level)
            if lvl < col.reference_level - 0.5:
                c2 = copy.deepcopy(col)
                c2.levels[i] = col.reference_level
                gain = float(self.evaluate([idx], c2, forms=[forms])["ev"][0]) - float(ev["ev"][0])
                upgrades.append({"card": c.key, "from": lvl, "to": col.reference_level, "gain": round(gain, 4)})
        all_up = None
        if upgrades:
            c2 = copy.deepcopy(col)
            for u in upgrades:
                c2.levels[self.catalog.by_key[u["card"]].idx] = col.reference_level
            all_up = round(float(self.evaluate([idx], c2, forms=[forms])["ev"][0]) - float(ev["ev"][0]), 4)
        return {"unlocks": sorted(unlocks, key=lambda u: -u["gain"]), "upgrades": sorted(upgrades, key=lambda u: -u["gain"]),
                "all_upgrades_gain": all_up}

    def _factors(self, idx, ev, overall, col) -> dict:
        c = {d: float(ev["caps"][0][i]) for i, d in enumerate(DIMS)}
        lvl = float(self.levels.level_score(ev["gaps"])[0]) if col is not None else None
        exact = self.exact_stats(idx)
        hist = None
        if exact and exact[0] >= self.cfg["data"]["min_deck_games"]:
            hist = float(np.clip((beta_posterior(exact[1], exact[0], 0.5, 50)["mean"] - 0.5) * 5 + 0.5, 0, 1))
        meta = None
        if self.model is not None:
            meta = float(np.clip((self.model.card_wr[idx].mean() - 0.5) * 5 + 0.5, 0, 1))
        values = {
            "cobertura_defensiva": np.mean([c["air_defense"], (c["tank_killing"] + c["ground_swarm"]) / 2, c["building_def"]]),
            "sinergia": (float(ev["syn"][0]) + 1) / 2,
            "coerencia": float(ev["coh"][0]),
            "capacidade_ofensiva": (c["pressure"] + c["siege_breaking"]) / 2,
            "capacidade_defensiva": np.mean([c["tank_killing"], c["building_def"], c["cheap_answers"]]),
            "ciclo": c["cycle"], "custo_elixir": c["elixir_eff"],
            "cobertura_aerea": 0.6 * c["air_defense"] + 0.4 * c["air_swarm"],
            "resposta_tanques": c["tank_killing"],
            "resposta_enxames": (c["ground_swarm"] + c["air_swarm"]) / 2,
            "feiticos": c["spells"], "pressao": c["pressure"], "contra_ataque": c["counterattack"],
            "niveis": lvl, "desempenho_historico": hist,
            "matchups": float(np.clip((overall["ev"] - 0.5) * 5 + 0.5, 0, 1)),
            "meta": meta,
        }
        weights = dict(self.cfg["factor_weights"])
        if self.model is not None and "factor_weights" in self.model.info:
            weights.update(self.model.info["factor_weights"])
        items, num, den = [], 0.0, 0.0
        for k, v in values.items():
            w = weights.get(k, 0)
            items.append({"factor": k, "value": None if v is None else round(float(v), 3), "weight": w,
                          "available": v is not None})
            if v is not None:
                num += w * float(v)
                den += w
        return {"items": items, "index": round(num / den, 3) if den else None,
                "note": "Índice secundário e transparente. A avaliação principal são os matchups; pesos "
                        "ajustáveis em settings (ou calibrados com dados)."}

    def _overall_confidence(self, matchups) -> dict:
        order = {"heurística": 0, "baixa": 1, "média": 2, "alta": 3}
        w = sum(m["meta_share"] * order[m["confidence"]] for m in matchups)
        level = ["heurística", "baixa", "média", "alta"][int(round(w))]
        return {"level": level, "text": CONFIDENCE_TEXT[level],
                "by_archetype": {m["archetype"]: m["confidence"] for m in matchups}}

    def _summary(self, r: dict) -> str:
        ms = sorted(r["matchups"], key=lambda m: -m["win_prob"])
        best = [m for m in ms if m["win_prob"] >= 0.53][:3]
        worst = [m for m in reversed(ms) if m["win_prob"] < 0.47][:2]
        s = f"Deck {r['archetype']['primary_pt']} com custo médio {r['avg_elixir']:.1f} e ciclo de {r['cycle_cost']} de elixir. "
        if r["strengths"]:
            s += f"Possui {join_pt(r['strengths'][:3])}. "
        if best:
            s += f"Tende a ir bem contra {join_pt([m['name'] for m in best])}. "
        if worst:
            w = worst[0]
            why = f" porque tem {join_pt(w['reasons_against'][:2])}" if w["reasons_against"] else ""
            s += f"Apresenta dificuldade contra {join_pt([m['name'] for m in worst])}{why}. "
        elif not best:
            s += "Os matchups são equilibrados, sem grandes forças ou fraquezas. "
        lv = r["levels"]
        if lv.get("provided") and lv["impact_ev"] < -0.01:
            s += f"Os níveis das cartas custam cerca de {abs(100 * lv['impact_ev']):.1f} p.p. de taxa de vitória esperada. "
        s += r["confidence"]["text"]
        return s

    # ---------------------------------------------------------------- status
    def data_status(self) -> dict:
        if self.model is None:
            return {"model": False, "note": getattr(self, "_model_note", None) or "Nenhum modelo treinado: todas as estimativas são heurísticas."}
        info = dict(self.model.info)
        info["model"] = True
        if self.model.is_synthetic:
            info["warning"] = "ATENÇÃO: o modelo foi treinado com dados SINTÉTICOS (demonstração), não com partidas reais."
        return info
