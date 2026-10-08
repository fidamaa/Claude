"use strict";
// Interface web do Clash Deck Lab (sem dependências externas). Todo texto dinâmico passa por esc().

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const pct = (p, d = 1) => (100 * p).toFixed(d) + "%";
const pp = (x) => (x >= 0 ? "+" : "") + (100 * x).toFixed(1) + " p.p.";
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");
const num = (v) => (typeof v === "number" && isFinite(v) ? v : 0);

const state = { cards: [], byKey: {}, archetypes: [], deck: [], build: { wincon: [], must: [], exclude: [] }, status: null };
const COL_KEY = "crlab.collection.v1";
const PLAYER_KEY = "crlab.player.v1";
const DECK_KEY = "crlab.deck.v1";

function toast(msg, ms = 3800) {
  const t = $("#toast");
  t.textContent = msg;
  t.style.display = "block";
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (t.style.display = "none"), ms);
}

async function api(path, body, headers = {}) {
  const opts = body !== undefined ? { method: "POST", headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) } : { headers };
  const res = await fetch(path, opts);
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail ? (typeof data.detail === "string" ? data.detail : JSON.stringify(data.detail)) : res.statusText);
  return data;
}

// ------------------------------------------------------------------ armazenamento local
function store(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* indisponível */ } }
function load(key, fallback) { try { return JSON.parse(localStorage.getItem(key)) ?? fallback; } catch { return fallback; } }
const emptyCol = () => ({ cards: {}, evolutions: [], reference_level: null });
const loadCollection = () => ({ ...emptyCol(), ...load(COL_KEY, emptyCol()) });
const saveCollection = (c) => store(COL_KEY, c);
function collectionPayload() {
  const c = loadCollection();
  if (!Object.keys(c.cards).length) return null;
  return { cards: c.cards, evolutions: c.evolutions, reference_level: c.reference_level || null };
}

// ------------------------------------------------------------------ navegação
function showTab(name) {
  $$("nav button").forEach((x) => x.classList.toggle("active", x.dataset.tab === name));
  $$(".tab").forEach((t) => t.classList.toggle("active", t.id === "tab-" + name));
  if (name === "collection") renderCollection();
  if (name === "analyze") { renderSlots(); refreshAnalyzePicker(); }
  if (name === "data") renderStatus();
}
$$("nav button").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));

// ------------------------------------------------------------------ cartas (tiles)
function tile(c, { inDeck = false, showLevel = true } = {}) {
  const col = loadCollection();
  const lvl = col.cards[c.key];
  const evo = col.evolutions.includes(c.key);
  const badge = evo ? `<span class="evo-badge">EVO</span>` : showLevel && lvl != null ? `<span class="lvl-badge">${num(lvl)}</span>` : "";
  return `<div class="card-tile r-${esc(c.rarity)} ${inDeck ? "in" : ""}" data-key="${esc(c.key)}" title="${esc(c.key)} · ${esc(c.rarity)}">
    <span class="drop"><span>${num(c.elixir)}</span></span>${badge}<span>${esc(c.name_pt)}</span></div>`;
}
function matches(card, q) {
  if (!q) return true;
  const n = norm(q);
  return norm(card.key).includes(n) || norm(card.name_pt).includes(n);
}
function renderPicker(container, list, query, isIn, onPick) {
  const items = list.filter((c) => matches(c, query)).sort((a, b) => a.elixir - b.elixir || a.name_pt.localeCompare(b.name_pt));
  container.innerHTML = items.map((c) => tile(c, { inDeck: isIn(c.key) })).join("") || "<p class='muted'>Nenhuma carta encontrada.</p>";
  $$(".card-tile", container).forEach((b) => b.addEventListener("click", () => onPick(b.dataset.key)));
}

// ------------------------------------------------------------------ importação pela tag
function renderPlayerCard() {
  const p = load(PLAYER_KEY, null);
  if (!p) return;
  $("#player-card").innerHTML = `<div><b>${esc(p.name)}</b> <span class="muted">${esc(p.tag)}</span><br>
    <span class="muted">${esc(p.arena || "")}${p.trophies != null ? " · " + num(p.trophies) + " troféus" : ""} · ${num(p.n_cards)} cartas · ${num(p.n_evos)} evoluções</span></div>`;
  $("#tag-input").value = p.tag || "";
}
$("#btn-tag").addEventListener("click", async () => {
  const tag = $("#tag-input").value.trim().replace(/^#/, "").toUpperCase();
  if (!tag) return toast("Digite sua tag (ex.: #2PQ8RJ0LV).");
  const btn = $("#btn-tag");
  btn.disabled = true;
  $("#tag-note").innerHTML = "<span class='spinner'></span>buscando…";
  try {
    const r = await api("/api/player/" + encodeURIComponent(tag));
    const col = { cards: {}, evolutions: [], reference_level: loadCollection().reference_level };
    for (const [name, lvl] of Object.entries(r.cards)) if (state.byKey[name]) col.cards[name] = lvl;
    col.evolutions = r.evolutions.filter((k) => state.byKey[k]);
    saveCollection(col);
    store(PLAYER_KEY, { ...r.player, n_cards: Object.keys(col.cards).length, n_evos: col.evolutions.length });
    const deck = (r.current_deck || []).filter((k) => state.byKey[k]);
    if (deck.length === 8) { state.deck = deck; store(DECK_KEY, deck); }
    $("#analyze-use-col").checked = true;
    renderPlayerCard(); renderSlots(); refreshAnalyzePicker(); refreshBuildPicker();
    if ($("#tab-collection").classList.contains("active")) renderCollection();
    $("#tag-note").textContent = r.unknown_cards?.length ? `Cartas ainda fora do catálogo: ${r.unknown_cards.join(", ")}` : "";
    toast(`Conta importada: ${Object.keys(col.cards).length} cartas${deck.length === 8 ? " e deck atual carregado" : ""}.`);
  } catch (e) { $("#tag-note").textContent = ""; toast("Erro: " + e.message, 6000); }
  finally { btn.disabled = false; }
});
$("#tag-input").addEventListener("keydown", (e) => { if (e.key === "Enter") $("#btn-tag").click(); });

// ------------------------------------------------------------------ ANALISAR
function renderSlots() {
  const slots = $("#deck-slots");
  slots.innerHTML = "";
  for (let i = 0; i < 8; i++) {
    const c = state.deck[i] && state.byKey[state.deck[i]];
    const d = document.createElement("div");
    d.innerHTML = c ? tile(c) : `<div class="card-tile empty">vazio</div>`;
    const el = d.firstElementChild;
    if (c) {
      el.title = "Clique para remover";
      el.addEventListener("click", () => { state.deck.splice(i, 1); store(DECK_KEY, state.deck); renderSlots(); refreshAnalyzePicker(); });
    }
    slots.appendChild(el);
  }
  const els = state.deck.map((k) => state.byKey[k]?.elixir || 0);
  const avg = els.length ? els.reduce((a, b) => a + b, 0) / els.length : 0;
  const cyc = [...els].sort((a, b) => a - b).slice(0, 4).reduce((a, b) => a + b, 0);
  $("#deck-meta").innerHTML = `<span>Cartas: <b>${state.deck.length}/8</b></span><span>Custo médio: <b>${avg.toFixed(1)}</b></span><span>Ciclo (4 mais baratas): <b>${els.length >= 4 ? cyc : "—"}</b></span>`;
}
function refreshAnalyzePicker() {
  const col = loadCollection();
  const ownedOnly = $("#analyze-owned").checked && Object.keys(col.cards).length;
  const list = ownedOnly ? state.cards.filter((c) => c.key in col.cards) : state.cards;
  renderPicker($("#analyze-picker"), list, $("#analyze-search").value, (k) => state.deck.includes(k), (k) => {
    const i = state.deck.indexOf(k);
    if (i >= 0) state.deck.splice(i, 1);
    else if (state.deck.length < 8) state.deck.push(k);
    else return toast("O deck já tem 8 cartas. Clique em uma carta do deck para removê-la.");
    store(DECK_KEY, state.deck); renderSlots(); refreshAnalyzePicker();
  });
}
$("#analyze-search").addEventListener("input", refreshAnalyzePicker);
$("#analyze-owned").addEventListener("change", refreshAnalyzePicker);
$("#btn-clear").addEventListener("click", () => { state.deck = []; store(DECK_KEY, []); renderSlots(); refreshAnalyzePicker(); $("#analyze-result").innerHTML = ""; });
$("#btn-paste").addEventListener("click", () => {
  const txt = prompt("Cole as 8 cartas separadas por vírgula (nomes em português ou inglês):");
  if (!txt) return;
  const found = [], missing = [];
  for (const raw of txt.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)) {
    const c = state.cards.find((x) => norm(x.key) === norm(raw) || norm(x.name_pt) === norm(raw));
    if (c) found.push(c.key); else missing.push(raw);
  }
  state.deck = [...new Set(found)].slice(0, 8);
  store(DECK_KEY, state.deck); renderSlots(); refreshAnalyzePicker();
  if (missing.length) toast("Não reconhecidas: " + missing.join(", "));
});
$("#btn-analyze").addEventListener("click", async () => {
  if (state.deck.length !== 8) return toast("Selecione exatamente 8 cartas.");
  const btn = $("#btn-analyze");
  btn.disabled = true;
  $("#analyze-result").innerHTML = "<div class='panel muted'><span class='spinner'></span>Analisando…</div>";
  try {
    const body = { deck: state.deck };
    if ($("#analyze-use-col").checked) {
      const col = collectionPayload();
      if (!col) toast("Coleção vazia: importe pela tag ou preencha 'Minha coleção'."); else body.collection = col;
    }
    const r = await api("/api/analyze", body);
    $("#analyze-result").innerHTML = renderAnalysis(r, true);
    bindSuggest(body);
    $("#analyze-result").scrollIntoView({ behavior: "smooth", block: "start" });
  } catch (e) { $("#analyze-result").innerHTML = ""; toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
});

const LABEL_COLOR = { "muito favorável": "var(--vgood)", "favorável": "var(--good)", "equilibrado": "var(--even)", "desfavorável": "var(--bad)", "muito desfavorável": "var(--vbad)" };
const labelClass = (l) => "lbl l-" + l.replace(/ /g, "-");
// Barra de 30% a 70%, com linha em 50% e intervalo de credibilidade quando há dados.
function probBar(p, interval, label) {
  const x = (v) => Math.max(0, Math.min(100, ((v - 0.3) / 0.4) * 100));
  const ci = interval ? `<div class="ci" style="left:${x(interval[0])}%;width:${Math.max(1, x(interval[1]) - x(interval[0]))}%"></div>` : "";
  return `<div class="bar"><div class="fill" style="width:${x(p)}%;background:${LABEL_COLOR[label] || "var(--accent)"}"></div><div class="mid"></div>${ci}</div>`;
}
const cardName = (k) => esc(state.byKey[k]?.name_pt || k);

function renderAnalysis(r, withSuggest) {
  const warn = r.data && r.data.warning ? `<div class="warn">${esc(r.data.warning)}</div>` : "";
  const o = r.overall;
  const ms = [...r.matchups].sort((a, b) => b.win_prob - a.win_prob);
  const best = ms[0], worst = ms[ms.length - 1];
  const kpis = `<div class="kpis">
    <div class="kpi"><div class="k">Média vs meta</div><div class="v">${pct(o.ev)}</div><div class="s">ponderada pela frequência no meta</div></div>
    <div class="kpi"><div class="k">Melhor matchup</div><div class="v" style="color:var(--vgood)">${pct(best.win_prob, 0)}</div><div class="s">${esc(best.name)}</div></div>
    <div class="kpi"><div class="k">Pior matchup</div><div class="v" style="color:${worst.win_prob < 0.47 ? "var(--vbad)" : "inherit"}">${pct(worst.win_prob, 0)}</div><div class="s">${esc(worst.name)}</div></div>
    <div class="kpi"><div class="k">Consistência</div><div class="v">±${(100 * o.sd).toFixed(1)}</div><div class="s">desvio entre matchups (p.p.)</div></div>
    <div class="kpi"><div class="k">Confiança</div><div class="v" style="font-size:18px">${esc(r.confidence.level)}</div><div class="s">${esc(r.confidence.level === "heurística" ? "sem dados reais suficientes" : "baseada em partidas reais")}</div></div>
  </div>`;
  const mus = ms.map((m) => {
    const extra = m.exact_games ? ` · ${num(m.exact_games)} partidas deste deck` : "";
    const ci = m.interval ? ` · intervalo 90%: ${pct(m.interval[0], 0)}–${pct(m.interval[1], 0)}` : "";
    return `<div class="mu">
      <div class="name">${esc(m.name)}</div>${probBar(m.win_prob, m.interval, m.label)}<div class="pct">${pct(m.win_prob)}</div>
      <div class="why"><span class="${labelClass(m.label)}">${esc(m.label)}</span>
        <span class="conf ${esc(m.confidence)}">confiança ${esc(m.confidence)}</span><span>fonte: ${esc(m.source)}${extra}${ci}</span>
        <span class="txt">${esc(m.explanation)}</span></div>
    </div>`;
  }).join("");
  const caps = r.capabilities.map((c) => `<div class="cap"><span>${esc(c.name)}</span>
      <div class="bar"><div class="fill" style="width:${100 * num(c.value)}%;background:${c.rating === "forte" ? "var(--good)" : c.rating === "fraca" ? "var(--bad)" : "var(--even)"}"></div>
      <div class="base" style="left:${100 * num(c.baseline)}%"></div></div><span>${(100 * num(c.value)).toFixed(0)}</span></div>`).join("");
  const syn = r.synergies.filter((s) => s.value > 0).slice(0, 6).map((s) => `<li class="pos"><b>${cardName(s.cards[0])} + ${cardName(s.cards[1])}</b>: ${esc(s.reason)} <span class="muted">(${esc(s.source)})</span></li>`).join("");
  const con = r.synergies.filter((s) => s.value < 0).slice(0, 4).map((s) => `<li class="neg"><b>${cardName(s.cards[0])} + ${cardName(s.cards[1])}</b>: ${esc(s.reason)}</li>`).join("")
    + r.coherence.issues.map((i) => `<li class="neg">${esc(i)}</li>`).join("");
  const cards = r.cards.map((c) => {
    const lv = c.at_level;
    const lvl = lv.level != null ? `${num(lv.level)} <span class="muted">(${lv.gap >= 0 ? "+" : ""}${num(lv.gap)}; atributos ×${num(lv.stat_factor)})</span>${lv.owned === false ? " <b style='color:var(--vbad)'>não possui</b>" : ""}` : "—";
    const meta = c.meta ? `${pct(c.meta.winrate_shrunk)} <span class="muted">em ${num(c.meta.games)} partidas · uso ${pct(c.meta.usage)}</span>` : "<span class='muted'>sem dados</span>";
    return `<tr><td><b>${esc(c.name_pt)}</b>${lv.evolution ? " <span class='evo-badge' style='position:static'>EVO</span>" : ""}</td><td>${num(c.elixir)}</td><td>${"★".repeat(num(c.theoretical.tier))}</td>
      <td>${lvl}</td><td>${meta}</td><td style="color:${c.fit.ev_contribution >= 0 ? "var(--vgood)" : "var(--vbad)"}">${pp(c.fit.ev_contribution)}</td></tr>`;
  }).join("");
  const factors = r.factors.items.map((f) => `<tr><td>${esc(f.factor.replace(/_/g, " "))}</td><td>${f.available ? (100 * num(f.value)).toFixed(0) : "<span class='muted'>sem dados</span>"}</td><td>${num(f.weight)}</td></tr>`).join("");
  const lv = r.levels;
  const levels = lv.provided
    ? `<p>Diferença efetiva de nível: <b>${lv.effective_gap >= 0 ? "+" : ""}${num(lv.effective_gap)}</b> em relação à referência ${num(lv.reference_level)}
       → impacto de <b>${pp(num(lv.impact_ev))}</b> na média. <span class="muted">${esc(lv.note)}</span>
       ${lv.evolutions_used.length ? "<br>Evoluções usadas: " + lv.evolutions_used.map(cardName).join(", ") : ""}
       ${lv.not_owned.length ? "<br><b>Cartas que você não possui:</b> " + lv.not_owned.map(cardName).join(", ") : ""}</p>`
    : `<p class="muted">${esc(lv.note)}</p>`;
  return `<div class="panel">
      <div class="row" style="margin:0"><h2 style="margin:0">${esc(r.archetype.primary_pt)}</h2>
        <span class="muted">custo médio ${num(r.avg_elixir)} · ciclo ${num(r.cycle_cost)} · ${r.archetype.labels_pt.map(esc).join(", ")}</span></div>
      ${kpis}
      <p class="summary">${esc(r.summary)}</p>${warn}
      <p class="muted">Meta: ${esc(o.meta_source)}. Score (${esc(o.objective_mode)}): ${(100 * o.score).toFixed(1)} — penaliza matchups muito desiguais.</p>
    </div>
    <div class="panel"><h2>Matchups por arquétipo</h2>${mus}</div>
    <div class="cols">
      <div class="panel"><h2>Pontos fortes</h2><ul class="clean">${r.strengths.map((s) => `<li class="pos">${esc(s)}</li>`).join("") || "<li class='muted'>Nenhum destaque acima da média.</li>"}</ul>
        <h2 style="margin-top:16px">Vulnerabilidades</h2><ul class="clean">${r.vulnerabilities.map((v) => `<li class="neg">${esc(v.message)}</li>`).join("") || "<li class='muted'>Nenhuma vulnerabilidade evidente.</li>"}</ul></div>
      <div class="panel"><h2>Sinergias e conflitos</h2><ul class="clean">${syn}${con}</ul>${!syn && !con ? "<p class='muted'>Nenhum par catalogado.</p>" : ""}
        <h2 style="margin-top:16px">Capacidades <span class="muted">(traço = média dos decks de referência)</span></h2>${caps}</div>
    </div>
    <div class="panel"><h2>Cartas: força teórica, no seu nível, no meta e compatibilidade</h2>
      <div class="table-wrap"><table><tr><th>Carta</th><th>Elixir</th><th>Teórica</th><th>Seu nível</th><th>Meta (dados)</th><th>Contribuição</th></tr>${cards}</table></div>
      ${levels}</div>
    <details class="panel"><summary>Índice de fatores (secundário): ${r.factors.index ?? "—"}</summary>
      <p class="muted">${esc(r.factors.note)}</p><table><tr><th>Fator</th><th>Valor</th><th>Peso</th></tr>${factors}</table></details>
    ${withSuggest ? `<div class="panel"><h2>Otimizar este deck</h2>
      <div class="row"><label class="check"><input type="checkbox" id="sg-keep"> manter a condição de vitória</label>
      <label class="check"><input type="checkbox" id="sg-owned" checked> só cartas que possuo</label>
      <select id="sg-target"><option value="">melhorar a média geral</option>${state.archetypes.map((a) => `<option value="${esc(a.key)}">melhorar vs ${esc(a.name)}</option>`).join("")}</select>
      <button id="btn-suggest" class="primary">Sugerir trocas</button></div><div id="suggest-result"></div></div>` : ""}`;
}

function bindSuggest(baseBody) {
  const btn = $("#btn-suggest");
  if (!btn) return;
  btn.addEventListener("click", async () => {
    btn.disabled = true;
    try {
      const body = { ...baseBody, keep_win_condition: $("#sg-keep").checked, target: $("#sg-target").value || null, top: 6 };
      if ($("#sg-owned").checked) { const col = collectionPayload(); if (col) body.collection = col; } else delete body.collection;
      const r = await api("/api/suggest", body);
      const swaps = r.swaps.map((s) => `<li class="pos">${esc(s.explanation)}</li>`).join("") || "<li class='muted'>Nenhuma troca melhora o deck segundo o modelo atual.</li>";
      const repl = Object.entries(r.replacements).map(([k, opts]) => `<tr><td>${cardName(k)}</td><td>${opts.map((o) => `${esc(o.in_pt)} (${pp(o.delta_ev)})`).join(", ")}</td></tr>`).join("");
      $("#suggest-result").innerHTML = `<h3>Melhores trocas</h3><ul class="clean">${swaps}</ul>
        <details style="margin-top:10px"><summary>Três melhores substitutas para cada carta</summary><table><tr><th>Sai</th><th>Opções (efeito na média vs meta)</th></tr>${repl}</table></details>
        <p class="muted">${esc(r.note)}</p>`;
    } catch (e) { toast("Erro: " + e.message); }
    finally { btn.disabled = false; }
  });
}

// ------------------------------------------------------------------ CRIAR
function renderChips() {
  for (const k of ["wincon", "must", "exclude"]) {
    const el = $("#chips-" + k);
    el.innerHTML = state.build[k].map((c) => `<span class="chip" data-k="${esc(c)}" title="remover">${cardName(c)} ✕</span>`).join("") || "<span class='muted'>nenhuma</span>";
    $$(".chip", el).forEach((ch) => ch.addEventListener("click", () => { state.build[k] = state.build[k].filter((x) => x !== ch.dataset.k); renderChips(); refreshBuildPicker(); }));
  }
}
function refreshBuildPicker() {
  const mode = $("#build-mode").value;
  const list = mode === "wincon" ? state.cards.filter((c) => c.tags.includes("wc") || c.tags.includes("wc2")) : state.cards;
  renderPicker($("#build-picker"), list, $("#build-search").value, (k) => state.build[mode].includes(k), (k) => {
    for (const m of ["wincon", "must", "exclude"]) if (m !== mode) state.build[m] = state.build[m].filter((x) => x !== k);
    const arr = state.build[mode];
    const i = arr.indexOf(k);
    if (i >= 0) arr.splice(i, 1); else arr.push(k);
    renderChips(); refreshBuildPicker();
  });
}
$("#build-mode").addEventListener("change", refreshBuildPicker);
$("#build-search").addEventListener("input", refreshBuildPicker);
$("#btn-build").addEventListener("click", async () => {
  const btn = $("#btn-build");
  btn.disabled = true;
  $("#build-result").innerHTML = "<div class='panel muted'><span class='spinner'></span>Buscando as melhores combinações…</div>";
  try {
    const body = {
      must_include: state.build.must, exclude: state.build.exclude, win_conditions: state.build.wincon,
      style: $("#build-style").value || null,
      max_avg_elixir: parseFloat($("#build-max").value) || null, min_avg_elixir: parseFloat($("#build-min").value) || null,
      top_k: parseInt($("#build-top").value) || 5,
    };
    if ($("#build-use-col").checked) {
      body.collection = collectionPayload();
      if (!body.collection) toast("Coleção vazia: usando todas as cartas. Importe sua conta pela tag para considerar níveis.");
    }
    const r = await api("/api/build", body);
    const heads = state.archetypes.map((a) => `<th title="${esc(a.name)}">${esc(a.name.split(" ")[0])}</th>`).join("");
    const rows = r.comparison.map((c) => `<tr><td><b>#${num(c.rank)}</b></td><td>${c.deck.map(cardName).join(", ")}</td>
      <td>${num(c.avg_elixir)}</td><td><b>${pct(c.ev)}</b></td><td>${pct(c.worst)}</td><td>${(100 * c.consistency_sd).toFixed(1)}</td>
      <td>${c.level_gap == null ? "—" : (c.level_gap >= 0 ? "+" : "") + num(c.level_gap)}</td><td>${esc(c.confidence)}</td>
      ${state.archetypes.map((a) => { const p = c.by_archetype[a.key]; return `<td style="color:${p >= 0.53 ? "var(--vgood)" : p < 0.47 ? "var(--vbad)" : "inherit"}">${(100 * p).toFixed(0)}</td>`; }).join("")}</tr>`).join("");
    const details = r.decks.map((d, i) => `<details class="panel" ${i === 0 ? "open" : ""}><summary>${esc(d.why)}</summary>
      <div class="slots" style="margin:12px 0">${d.analysis.deck.map((k) => tile(state.byKey[k])).join("")}</div>
      <div class="row"><button class="use-deck" data-deck="${esc(JSON.stringify(d.analysis.deck))}">Abrir na análise</button></div>
      ${renderAnalysis(d.analysis, false)}</details>`).join("");
    $("#build-result").innerHTML = `<div class="panel"><h2>Comparação</h2><p class="muted">${esc(r.note)}</p>
      <div class="table-wrap"><table class="cmp"><tr><th></th><th>Deck</th><th>Elixir</th><th>Média</th><th>Pior</th><th>Desvio</th><th>Nível</th><th>Conf.</th>${heads}</tr>${rows}</table></div></div>${details}`;
    $$(".use-deck").forEach((b) => b.addEventListener("click", () => {
      state.deck = JSON.parse(b.dataset.deck); store(DECK_KEY, state.deck);
      renderSlots(); refreshAnalyzePicker(); showTab("analyze"); $("#btn-analyze").click();
    }));
  } catch (e) { $("#build-result").innerHTML = ""; toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
});

// ------------------------------------------------------------------ COLEÇÃO
function renderCollection() {
  const col = loadCollection();
  $("#col-ref").value = col.reference_level ?? "";
  const q = $("#col-filter").value;
  const list = state.cards.filter((c) => matches(c, q)).sort((a, b) => a.name_pt.localeCompare(b.name_pt));
  $("#col-count").textContent = `${Object.keys(col.cards).length} cartas na coleção · ${col.evolutions.length} evoluções`;
  $("#col-table").innerHTML = `<div class="col-grid">${list.map((c) => `<div class="col-item r-${esc(c.rarity)} ${c.key in col.cards ? "owned" : ""}">
      <span class="dot"></span><span class="n" title="${esc(c.key)}">${esc(c.name_pt)}</span>
      <input type="number" min="1" max="16" data-key="${esc(c.key)}" value="${col.cards[c.key] ?? ""}" placeholder="—">
      ${c.evo ? `<label class="check" title="evolução desbloqueada"><input type="checkbox" data-evo="${esc(c.key)}" ${col.evolutions.includes(c.key) ? "checked" : ""}>evo</label>` : "<span></span>"}
    </div>`).join("")}</div>`;
  $$("#col-table input[type=number]").forEach((inp) => inp.addEventListener("change", () => {
    const c = loadCollection();
    const v = parseFloat(inp.value);
    if (isNaN(v)) delete c.cards[inp.dataset.key]; else c.cards[inp.dataset.key] = Math.max(1, Math.min(16, v));
    saveCollection(c); renderCollection();
  }));
  $$("#col-table input[data-evo]").forEach((inp) => inp.addEventListener("change", () => {
    const c = loadCollection();
    c.evolutions = c.evolutions.filter((k) => k !== inp.dataset.evo);
    if (inp.checked) c.evolutions.push(inp.dataset.evo);
    saveCollection(c); renderCollection();
  }));
}
$("#col-filter").addEventListener("input", renderCollection);
$("#col-ref").addEventListener("change", () => { const c = loadCollection(); c.reference_level = parseFloat($("#col-ref").value) || null; saveCollection(c); });
$("#btn-fill").addEventListener("click", () => {
  const v = parseFloat($("#col-fill").value);
  if (isNaN(v)) return toast("Informe um nível.");
  const c = loadCollection();
  for (const card of state.cards) c.cards[card.key] = v;
  saveCollection(c); renderCollection();
});
$("#btn-col-clear").addEventListener("click", () => {
  if (!confirm("Apagar a coleção salva neste navegador?")) return;
  saveCollection(emptyCol()); store(PLAYER_KEY, null); renderCollection();
});
$("#btn-export").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify(loadCollection(), null, 1)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = "colecao.json"; a.click();
});
$("#btn-import").addEventListener("click", () => {
  const txt = prompt("Cole o JSON da coleção (formato do 'crlab player' ou exportado aqui):");
  if (!txt) return;
  try {
    const d = JSON.parse(txt);
    const c = { cards: {}, evolutions: (d.evolutions || []).filter((k) => state.byKey[k]), reference_level: d.reference_level ?? null };
    const unknown = [];
    for (const [name, lvl] of Object.entries(d.cards || {})) {
      const card = state.cards.find((x) => norm(x.key) === norm(name) || norm(x.name_pt) === norm(name));
      if (card) c.cards[card.key] = lvl; else unknown.push(name);
    }
    saveCollection(c); renderCollection();
    toast(`${Object.keys(c.cards).length} cartas importadas.` + (unknown.length ? ` Ignoradas: ${unknown.join(", ")}` : ""));
  } catch (e) { toast("JSON inválido: " + e.message); }
});

// ------------------------------------------------------------------ DADOS
async function renderStatus() {
  try {
    const s = await api("/api/status");
    state.status = s;
    const d = s.data;
    if (!d.model) {
      $("#data-status").innerHTML = `<p><b>Modo heurístico.</b> ${esc(d.note)}</p>
        <p class="muted">Quando o servidor tem a chave da API (CR_API_TOKEN), ele coleta partidas reais e treina o modelo sozinho.</p>`;
    } else {
      const v = d.validation;
      $("#data-status").innerHTML = `${d.warning ? `<div class="warn">${esc(d.warning)}</div>` : `<div class="ok">Modelo treinado com partidas reais.</div>`}
        <div class="table-wrap"><table><tr><th>Partidas usadas</th><td>${num(d.battles)}</td></tr>
        <tr><th>Período</th><td>${esc(d.first?.slice(0, 10))} a ${esc(d.last?.slice(0, 10))} (janela de ${num(d.days)} dias, meia-vida ${num(d.half_life_days)} dias)</td></tr>
        <tr><th>Fontes</th><td>${esc((d.sources || []).join(", "))}</td></tr>
        <tr><th>Descartadas (carta fora do catálogo)</th><td>${num(d.dropped)}</td></tr>
        ${v ? `<tr><th>Validação temporal</th><td>log-loss ${num(v.logloss_model).toFixed(4)} (base ${num(v.logloss_baseline).toFixed(4)}) · acurácia ${pct(v.accuracy_model)} em ${num(v.holdout)} partidas mais recentes</td></tr>` : ""}
        <tr><th>Treinado em</th><td>${esc(d.trained_at)}</td></tr></table></div>`;
    }
    const c = s.collector || {};
    $("#collector-status").innerHTML = !c.enabled
      ? `<p class="muted">Desativada: o servidor não tem <code>CR_API_TOKEN</code>.</p>`
      : `<p>${c.running ? "<span class='spinner'></span><b>Coletando agora…</b>" : "Ativa"} · a cada ${num(c.interval_hours)} h
          ${c.last_run ? ` · última execução ${esc(c.last_run)}` : " · primeira coleta em andamento ou agendada"}</p>
         ${c.last_result ? `<p class="muted">Última coleta: ${num(c.last_result.new_battles)} partidas novas; ${num(c.last_result.total)} no banco.</p>` : ""}
         ${c.last_error ? `<div class="warn">${esc(c.last_error)}</div>` : ""}
         ${c.log?.length ? `<div class="log">${c.log.map(esc).join("\n")}</div>` : ""}`;
  } catch (e) { $("#data-status").textContent = "Erro: " + e.message; }
}
$("#btn-refresh").addEventListener("click", async () => {
  try {
    const r = await api("/api/data/refresh", {}, { "X-Admin-Key": $("#admin-key").value });
    toast(r.note || "Coleta iniciada."); setTimeout(renderStatus, 1500);
  } catch (e) { toast("Erro: " + e.message); }
});

async function refreshPill() {
  try {
    const s = await api("/api/status");
    const d = s.data, pill = $("#status-pill");
    pill.className = "status-pill";
    if (d.model && !d.warning) { pill.classList.add("real"); pill.textContent = `dados reais · ${num(d.battles)} partidas`; }
    else if (d.model) { pill.classList.add("synthetic"); pill.textContent = "dados sintéticos (demo)"; }
    else pill.textContent = s.collector?.running ? "coletando dados reais…" : "modo heurístico";
  } catch { /* ignora */ }
}

// ------------------------------------------------------------------ init
(async function init() {
  try {
    state.cards = await api("/api/cards");
    state.byKey = Object.fromEntries(state.cards.map((c) => [c.key, c]));
    state.archetypes = await api("/api/archetypes");
    $("#build-style").innerHTML += state.archetypes.map((a) => `<option value="${esc(a.key)}">${esc(a.name)}</option>`).join("");
    const saved = load(DECK_KEY, null);
    state.deck = Array.isArray(saved) && saved.every((k) => state.byKey[k]) && saved.length
      ? saved : ["Hog Rider", "Musketeer", "Ice Golem", "Ice Spirit", "Skeletons", "Cannon", "Fireball", "The Log"];
    if (collectionPayload()) $("#analyze-use-col").checked = true;
    renderPlayerCard(); renderSlots(); refreshAnalyzePicker(); renderChips(); refreshBuildPicker(); refreshPill();
    setInterval(refreshPill, 60000);
  } catch (e) { toast("Falha ao carregar: " + e.message, 8000); }
})();
