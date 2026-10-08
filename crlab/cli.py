"""Interface de linha de comando.

Exemplos:
  crlab analyze "Hog Rider, Musketeer, Ice Golem, Ice Spirit, Skeletons, Cannon, Fireball, The Log"
  crlab analyze "..." --collection minha_colecao.json
  crlab suggest "..." --keep-wincon --target beatdown
  crlab build --collection minha_colecao.json --wincon "Hog Rider" --style cycle --top 5
  crlab data synth --n 40000 && crlab data train
  crlab data crawl --top 100 --max-players 500       (requer CR_API_TOKEN)
  crlab player "#TAG" --out minha_colecao.json        (requer CR_API_TOKEN)
  crlab serve --port 8000
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .archetypes import ARCHETYPES
from .builder import BuildRequest, DeckBuilder, parse_style
from .catalog import UnknownCardError, get_catalog
from .datamodel import train_model
from .engine import DeckError, Engine
from .levels import PlayerCollection
from .optimizer import suggest_swaps
from .settings import load_settings
from .store import BattleStore


def _split(s: str | None) -> list[str]:
    if not s:
        return []
    sep = ";" if ";" in s else ","
    return [x.strip() for x in s.split(sep) if x.strip()]


def _load_collection(engine: Engine, path: str | None) -> PlayerCollection | None:
    if not path:
        return None
    col = PlayerCollection.from_dict(engine.catalog, json.loads(Path(path).read_text(encoding="utf-8")))
    for w in col.warnings:
        print(f"[aviso] {w}", file=sys.stderr)
    return col


def _bar(p: float, width: int = 20) -> str:
    n = int(round((p - 0.3) / 0.4 * width))
    n = max(0, min(width, n))
    return "█" * n + "·" * (width - n)


def print_analysis(r: dict):
    print(f"\nDeck: {', '.join(r['deck_pt'])}")
    print(f"Arquétipo: {r['archetype']['primary_pt']}  (rótulos: {', '.join(r['archetype']['labels_pt'])})")
    print(f"Custo médio: {r['avg_elixir']:.2f}  |  Ciclo (4 mais baratas): {r['cycle_cost']}")
    if r["data"].get("warning"):
        print(f"\n!! {r['data']['warning']}")
    print("\n== Matchups por arquétipo ==")
    for m in sorted(r["matchups"], key=lambda m: -m["win_prob"]):
        ci = f" [{100 * m['interval'][0]:.0f}–{100 * m['interval'][1]:.0f}%]" if m["interval"] else ""
        print(f"  {m['name']:<26} {_bar(m['win_prob'])} {100 * m['win_prob']:5.1f}%{ci}  {m['label']:<18} "
              f"conf.: {m['confidence']} ({m['source']})")
        why = m["reasons_for"][:2] if m["win_prob"] >= 0.5 else m["reasons_against"][:2]
        if why:
            print(f"      ↳ {'; '.join(why)}")
    o = r["overall"]
    print(f"\nMédia vs meta: {100 * o['ev']:.1f}%  |  pior matchup: {100 * o['worst']:.1f}%  |  "
          f"desvio entre matchups: {100 * o['sd']:.1f} p.p.  |  score ({o['objective_mode']}): {100 * o['score']:.1f}")
    print(f"Meta: {o['meta_source']}")
    if r["strengths"]:
        print("\n== Pontos fortes ==")
        for s in r["strengths"]:
            print(f"  + {s}")
    if r["vulnerabilities"]:
        print("\n== Vulnerabilidades ==")
        for v in r["vulnerabilities"][:8]:
            print(f"  - {v['message']}")
    syn = [s for s in r["synergies"] if s["value"] > 0][:5]
    conf = [s for s in r["synergies"] if s["value"] < 0][:3]
    if syn or conf or r["coherence"]["issues"]:
        print("\n== Sinergias e conflitos ==")
        for s in syn:
            print(f"  + {s['cards'][0]} + {s['cards'][1]}: {s['reason']} ({s['source']})")
        for s in conf:
            print(f"  - {s['cards'][0]} + {s['cards'][1]}: {s['reason']} ({s['source']})")
        for i in r["coherence"]["issues"]:
            print(f"  - {i}")
    print("\n== Cartas ==")
    for c in r["cards"]:
        lv = c["at_level"]
        lvtxt = f"nív. {lv['level']:.0f} ({lv['gap']:+.1f}, atributos x{lv['stat_factor']:.2f})" if lv.get("level") else "nível n/i"
        meta = f" | meta: {100 * c['meta']['winrate_shrunk']:.1f}% em {c['meta']['games']} partidas" if c["meta"] else ""
        evo = " [EVO]" if lv.get("evolution") else ""
        print(f"  {c['name_pt']:<24} tier {c['theoretical']['tier']:.0f} | {lvtxt}{evo} | "
              f"contribuição {100 * c['fit']['ev_contribution']:+.1f} p.p.{meta}")
    lv = r["levels"]
    if lv.get("provided"):
        print(f"\nNíveis: diferença efetiva {lv['effective_gap']:+.2f} vs referência {lv['reference_level']:.1f} "
              f"→ impacto {100 * lv['impact_ev']:+.1f} p.p. na média. {lv['note']}")
    print(f"\nÍndice de fatores (secundário): {r['factors']['index']}")
    print(f"\nResumo: {r['summary']}\n")


def cmd_analyze(args, engine):
    col = _load_collection(engine, args.collection)
    r = engine.analyze(_split(args.deck), col)
    print(json.dumps(r, ensure_ascii=False, indent=1, default=float) if args.json else "", end="")
    if not args.json:
        print_analysis(r)


def cmd_suggest(args, engine):
    col = _load_collection(engine, args.collection)
    idx = engine.parse_deck(_split(args.deck))
    keep = [engine.catalog.resolve(k).idx for k in _split(args.keep)]
    res = suggest_swaps(engine, idx, col, top=args.top, keep=keep, keep_win_condition=args.keep_wincon,
                        target=parse_style(args.target))
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=1))
        return
    print("\n== Melhores trocas ==")
    for s in res["swaps"]:
        print(f"  • {s['explanation']}")
    if not res["swaps"]:
        print("  Nenhuma troca melhora o deck segundo o modelo atual.")
    print("\n== Melhores substitutas por carta ==")
    for card, opts in res["replacements"].items():
        txt = ", ".join(f"{o['in_pt']} ({100 * o['delta_ev']:+.1f} p.p.)" for o in opts)
        print(f"  {engine.catalog.by_key[card].name_pt:<24} → {txt}")
    print(f"\n{res['note']}")


def cmd_build(args, engine):
    col = _load_collection(engine, args.collection)
    res_idx = lambda names: [engine.catalog.resolve(n).idx for n in _split(names)]  # noqa: E731
    req = BuildRequest(
        must_include=res_idx(args.must), exclude=res_idx(args.exclude), win_conditions=res_idx(args.wincon),
        style=parse_style(args.style), max_avg_elixir=args.max_elixir, min_avg_elixir=args.min_elixir, top_k=args.top,
    )
    res = DeckBuilder(engine).build(req, col)
    if args.json:
        print(json.dumps(res, ensure_ascii=False, indent=1, default=float))
        return
    print(f"\n{res['note']}\n")
    print("== Comparação ==")
    head = "  # " + "deck".ljust(70) + " média  pior  score  " + " ".join(a[:5].rjust(5) for a in ARCHETYPES)
    print(head)
    for row in res["comparison"]:
        names = ", ".join(engine.catalog.by_key[k].name_pt for k in row["deck"])
        print(f"  {row['rank']} {names[:70]:<70} {100 * row['ev']:5.1f} {100 * row['worst']:5.1f} {100 * row['score']:5.1f}  "
              + " ".join(f"{100 * row['by_archetype'][a]:5.1f}" for a in ARCHETYPES))
    for d in res["decks"]:
        print(f"\n{d['why']}")
        print(f"   {d['analysis']['summary']}")
    if args.detail and res["decks"]:
        print_analysis(res["decks"][0]["analysis"])


def cmd_cards(args, engine):
    for c in engine.catalog.cards:
        print(f"{c.key:<22} {c.name_pt:<26} {c.elixir}  {c.type:<8} {c.rarity:<9} tier {c.tier:.0f} "
              f"{'evo ' if c.evo else ''}{' '.join(sorted(c.tags))}")


def cmd_data(args, engine, cfg):
    store = BattleStore(cfg["data"]["db_path"])
    if args.action == "status":
        print(json.dumps({"store": store.summary(), "model": engine.data_status()}, ensure_ascii=False, indent=1))
    elif args.action == "import":
        from .ingest.importers import read_any
        battles = read_any(args.file, args.source)
        print(f"{store.insert(battles)} novas partidas importadas de {len(battles)} lidas.")
    elif args.action == "synth":
        from .ingest.synthetic import generate
        battles, _ = generate(Engine(cfg=cfg), n=args.n, seed=args.seed)
        print(f"{store.insert(battles)} partidas SINTÉTICAS inseridas (source=synthetic).")
    elif args.action == "crawl":
        from .ingest.official_api import ClashApi
        api = ClashApi(args.token, args.base_url)
        seeds = _split(args.tags) or api.top_players(args.location, args.top)
        battles = api.crawl(seeds, max_players=args.max_players)
        print(f"{store.insert(battles)} novas partidas reais de {len(battles)} coletadas.")
    elif args.action == "train":
        sources = _split(args.sources) or None
        if args.exclude_synthetic:
            sources = [s for s in store.summary()["by_source"] if s != "synthetic"]
        model = train_model(store, get_catalog(), cfg, heuristic_engine=Engine(cfg=cfg), days=args.days, sources=sources)
        model.save(cfg["data"]["model_path"])
        print(f"Modelo salvo em {cfg['data']['model_path']}")
        if "validation" in model.info:
            v = model.info["validation"]
            print(f"Validação temporal ({v['holdout']} partidas mais recentes): log-loss {v['logloss_model']:.4f} "
                  f"(base {v['logloss_baseline']:.4f}), acurácia {100 * v['accuracy_model']:.1f}%")
    elif args.action == "reset-model":
        p = Path(cfg["data"]["model_path"])
        for f in (p, p.with_suffix(".json")):
            if f.exists():
                f.unlink()
        print("Modelo removido: o sistema volta ao modo heurístico.")


def cmd_player(args, engine):
    from .ingest.official_api import ClashApi, collection_from_player
    api = ClashApi(args.token, args.base_url)
    col = collection_from_player(api.player(args.tag))
    out = json.dumps(col, ensure_ascii=False, indent=1)
    if args.out:
        Path(args.out).write_text(out, encoding="utf-8")
        print(f"Coleção salva em {args.out} ({len(col['cards'])} cartas).")
    else:
        print(out)


def main(argv=None):
    ap = argparse.ArgumentParser(prog="crlab", description="Clash Deck Lab — análise e criação de decks")
    ap.add_argument("--settings", help="JSON com parâmetros que sobrescrevem os padrões")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("analyze", help="Analisa um deck de 8 cartas")
    p.add_argument("deck")
    p.add_argument("--collection")
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("suggest", help="Sugere trocas de cartas")
    p.add_argument("deck")
    p.add_argument("--collection")
    p.add_argument("--keep", help="cartas que não podem sair")
    p.add_argument("--keep-wincon", action="store_true", help="manter a condição de vitória")
    p.add_argument("--target", help=f"arquétipo a melhorar: {', '.join(ARCHETYPES)}")
    p.add_argument("--top", type=int, default=5)
    p.add_argument("--json", action="store_true")

    p = sub.add_parser("build", help="Gera os melhores decks a partir da coleção")
    p.add_argument("--collection")
    p.add_argument("--must", help="cartas obrigatórias")
    p.add_argument("--exclude", help="cartas a evitar")
    p.add_argument("--wincon", help="condições de vitória aceitas (ao menos uma)")
    p.add_argument("--style", help=f"estilo: {', '.join(ARCHETYPES)}")
    p.add_argument("--max-elixir", type=float)
    p.add_argument("--min-elixir", type=float)
    p.add_argument("--top", type=int)
    p.add_argument("--detail", action="store_true", help="mostra a análise completa do melhor deck")
    p.add_argument("--json", action="store_true")

    sub.add_parser("cards", help="Lista o catálogo de cartas")

    p = sub.add_parser("data", help="Dados reais: importar, coletar, treinar")
    p.add_argument("action", choices=["status", "import", "synth", "crawl", "train", "reset-model"])
    p.add_argument("--file")
    p.add_argument("--source")
    p.add_argument("--n", type=int, default=40000)
    p.add_argument("--seed", type=int, default=0)
    p.add_argument("--token")
    p.add_argument("--base-url")
    p.add_argument("--tags", help="jogadores semente (senão usa o ranking)")
    p.add_argument("--location", default="global")
    p.add_argument("--top", type=int, default=100)
    p.add_argument("--max-players", type=int, default=300)
    p.add_argument("--days", type=int)
    p.add_argument("--sources", help="treinar só com estas fontes")
    p.add_argument("--exclude-synthetic", action="store_true")

    p = sub.add_parser("player", help="Baixa a coleção (cartas/níveis/evoluções) de um jogador pela API oficial")
    p.add_argument("tag")
    p.add_argument("--out")
    p.add_argument("--token")
    p.add_argument("--base-url")

    p = sub.add_parser("serve", help="Inicia a interface web + API REST")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=8000)

    for stream in (sys.stdout, sys.stderr):  # terminais do Windows (cp1252) não quebram com acentos/símbolos
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(errors="replace")
    args = ap.parse_args(argv)
    cfg = load_settings(args.settings)
    if args.cmd == "serve":
        import uvicorn

        from .api import create_app
        uvicorn.run(create_app(cfg), host=args.host, port=args.port)
        return
    engine = Engine.from_settings(cfg)
    try:
        if args.cmd == "analyze":
            cmd_analyze(args, engine)
        elif args.cmd == "suggest":
            cmd_suggest(args, engine)
        elif args.cmd == "build":
            cmd_build(args, engine)
        elif args.cmd == "cards":
            cmd_cards(args, engine)
        elif args.cmd == "data":
            cmd_data(args, engine, cfg)
        elif args.cmd == "player":
            cmd_player(args, engine)
    except (UnknownCardError, DeckError) as e:
        print(f"Erro: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
