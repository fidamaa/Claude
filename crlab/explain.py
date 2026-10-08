"""Textos de explicação (pt-BR) para capacidades, matchups e vulnerabilidades."""
from __future__ import annotations

DIM_PT = {
    "air_defense": "defesa aérea",
    "air_swarm": "dano em área contra enxames aéreos",
    "ground_swarm": "dano em área contra enxames terrestres",
    "tank_killing": "resposta a tanques",
    "building_def": "defesa contra cartas que miram construções",
    "cheap_answers": "respostas baratas",
    "cycle": "velocidade de ciclo",
    "elixir_eff": "custo de elixir",
    "spells": "cobertura de feitiços",
    "reset": "cartas de reset/atordoamento",
    "pressure": "pressão ofensiva",
    "siege_breaking": "capacidade de alcançar construções",
    "counterattack": "potencial de contra-ataque",
    "anti_graveyard": "dano em área perto da torre",
    "defense_volume": "volume de defesa (vida e dano das tropas defensivas)",
}

DIM_GOOD = {
    "air_defense": "boa defesa aérea",
    "air_swarm": "boas respostas em área contra enxames aéreos",
    "ground_swarm": "boas respostas em área contra enxames terrestres",
    "tank_killing": "excelente dano contra tanques",
    "building_def": "boas respostas a Corredor/Aríete/Gigante Real",
    "cheap_answers": "muitas respostas baratas",
    "cycle": "ciclo rápido",
    "elixir_eff": "custo médio baixo",
    "spells": "boa cobertura de feitiços",
    "reset": "cartas de reset contra Inferno/Sparky",
    "pressure": "boa pressão ofensiva",
    "siege_breaking": "boas ferramentas para alcançar construções",
    "counterattack": "bom potencial de contra-ataque",
    "anti_graveyard": "bom dano em área perto da torre",
    "defense_volume": "tropas defensivas robustas",
}

DIM_BAD = {
    "air_defense": "defesa aérea limitada",
    "air_swarm": "poucas respostas em área contra enxames aéreos",
    "ground_swarm": "poucas respostas em área contra enxames terrestres",
    "tank_killing": "pouco dano concentrado contra tanques",
    "building_def": "poucas respostas a cartas que miram construções",
    "cheap_answers": "poucas respostas baratas",
    "cycle": "ciclo lento",
    "elixir_eff": "custo médio alto",
    "spells": "cobertura de feitiços incompleta",
    "reset": "nenhuma carta de reset",
    "pressure": "pouca pressão ofensiva",
    "siege_breaking": "dificuldade para alcançar construções",
    "counterattack": "pouco potencial de contra-ataque",
    "anti_graveyard": "pouco dano em área perto da torre",
    "defense_volume": "tropas defensivas frágeis demais",
}

# (dimensão, limiar absoluto, mensagem)
VULNERABILITIES = [
    ("air_defense", 0.50, "Defesa aérea fraca — vulnerável a Lava, Balão, Bebê Dragão e Dragão Infernal."),
    ("air_swarm", 0.45, "Poucas respostas em área contra enxames aéreos (Morcegos, Horda de Servos, filhotes da Lava)."),
    ("ground_swarm", 0.55, "Poucas respostas em área contra enxames terrestres (Exército de Esqueletos, Gangue, Barril de Goblins)."),
    ("tank_killing", 0.45, "Pouco dano concentrado — dificuldade contra tanques (Golem, Gigante, P.E.K.K.A, Gigante Real)."),
    ("building_def", 0.45, "Sem construção defensiva ou DPS barato suficiente — vulnerável a Corredor, Aríete e Gigante Real."),
    ("cycle", 0.35, "Ciclo lento — difícil reagir a ciclo rápido e defender siege a tempo."),
    ("anti_graveyard", 0.55, "Pouco dano em área perto da torre — vulnerável a Cemitério."),
    ("siege_breaking", 0.45, "Pouca capacidade de alcançar construções — siege (X-Besta/Morteiro) pode travar o jogo."),
    ("defense_volume", 0.55, "Pouco volume defensivo — as tropas têm pouca vida/dano para segurar pushes grandes."),
    ("pressure", 0.45, "Pouca pressão ofensiva — controle e siege podem jogar com calma contra você."),
]


def fmt_pct(p: float) -> str:
    return f"{100 * p:.1f}%"


def join_pt(items: list[str]) -> str:
    items = [i for i in items if i]
    if not items:
        return ""
    if len(items) == 1:
        return items[0]
    return ", ".join(items[:-1]) + " e " + items[-1]
