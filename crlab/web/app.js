"use strict";
// Interface web do Clash Deck Lab (sem dependências externas).

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const pct = (p, d = 1) => (100 * p).toFixed(d) + "%";
const pp = (x) => (x >= 0 ? "+" : "") + (100 * x).toFixed(1) + " p.p.";
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");

const state = { cards: [], byKey: {}, archetypes: [], deck: [], build: { wincon: [], must: [], exclude: [] } };
const COL_KEY = "crlab.collection.v1";

function toast(msg, ms = 3500) {
  const t = $("#toast");
  t.textContent = msg;
  t.style.display = "block";
  clearTimeout(toast._t);
  toast._t = setTimeout(() => (t.style.display = "none"), ms);
}

async function api(path, body) {
  const res = await fetch(path, body ? { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) } : {});
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.detail ? (typeof data.detail === "string" ? data.detail : JSON.stringify(data.detail)) : res.statusText);
  return data;
}

// ------------------------------------------------------------------ coleção (localStorage)
function loadCollection() {
  try { return JSON.parse(localStorage.getItem(COL_KEY)) || { cards: {}, evolutions: [], reference_level: null }; }
  catch { return { cards: {}, evolutions: [], reference_level: null }; }
}
function saveCollection(c) { try { localStorage.setItem(COL_KEY, JSON.stringify(c)); } catch { /* armazenamento indisponível */ } }
function collectionPayload() {
  const c = loadCollection();
  if (!Object.keys(c.cards).length) return null;
  return { cards: c.cards, evolutions: c.evolutions, reference_level: c.reference_level || null };
}

// ------------------------------------------------------------------ navegação
$$("nav button").forEach((b) => b.addEventListener("click", () => {
  $$("nav button").forEach((x) => x.classList.toggle("active", x === b));
  $$(".tab").forEach((t) => t.classList.toggle("active", t.id === "tab-" + b.dataset.tab));
  if (b.dataset.tab === "collection") renderCollection();
  if (b.dataset.tab === "data") renderStatus();
}));

// ------------------------------------------------------------------ seletor de cartas
function matches(card, q) {
  if (!q) return true;
  const n = norm(q);
  return norm(card.key).includes(n) || norm(card.name_pt).includes(n);
}
function renderPicker(container, query, isIn, onPick) {
  const list = state.cards.filter((c) => matches(c, query)).sort((a, b) => a.elixir - b.elixir || a.name_pt.localeCompare(b.name_pt));
  container.innerHTML = list.map((c) =>
    `<button class="pick ${isIn(c.key) ? "in" : ""}" data-key="${esc(c.key)}" title="${esc(c.key)}"><span class="el">${c.elixir}</span>${esc(c.name_pt)}</button>`).join("");
  $$(".pick", container).forEach((b) => b.addEventListener("click", () => onPick(b.dataset.key)));
}

// ------------------------------------------------------------------ ANALISAR
function renderSlots() {
  const slots = $("#deck-slots");
  slots.innerHTML = "";
  for (let i = 0; i < 8; i++) {
    const key = state.deck[i];
    const c = key && state.byKey[key];
    const d = document.createElement("div");
    d.className = "slot" + (c ? " filled" : "");
    d.innerHTML = c ? `<span>${esc(c.name_pt)}</span><span class="el">${c.elixir}</span>` : `<span class="muted">vazio</span>`;
    if (c) d.addEventListener("click", () => { state.deck.splice(i, 1); renderSlots(); refreshAnalyzePicker(); });
    slots.appendChild(d);
  }
}
function refreshAnalyzePicker() {
  renderPicker($("#analyze-picker"), $("#analyze-search").value, (k) => state.deck.includes(k), (k) => {
    const i = state.deck.indexOf(k);
    if (i >= 0) state.deck.splice(i, 1);
    else if (state.deck.length < 8) state.deck.push(k);
    else toast("O deck já tem 8 cartas. Clique em uma carta do deck para removê-la.");
    renderSlots(); refreshAnalyzePicker();
  });
}
$("#analyze-search").addEventListener("input", refreshAnalyzePicker);
$("#btn-clear").addEventListener("click", () => { state.deck = []; renderSlots(); refreshAnalyzePicker(); $("#analyze-result").innerHTML = ""; });
$("#btn-paste").addEventListener("click", () => {
  const txt = prompt("Cole as 8 cartas separadas por vírgula (nomes em português ou inglês):");
  if (!txt) return;
  const found = [], missing = [];
  for (const raw of txt.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)) {
    const c = state.cards.find((x) => norm(x.key) === norm(raw) || norm(x.name_pt) === norm(raw));
    if (c) found.push(c.key); else missing.push(raw);
  }
  state.deck = [...new Set(found)].slice(0, 8);
  renderSlots(); refreshAnalyzePicker();
  if (missing.length) toast("Não reconhecidas: " + missing.join(", "));
});
$("#btn-analyze").addEventListener("click", async () => {
  if (state.deck.length !== 8) return toast("Selecione exatamente 8 cartas.");
  const btn = $("#btn-analyze");
  btn.disabled = true;
  try {
    const body = { deck: state.deck };
    if ($("#analyze-use-col").checked) {
      const col = collectionPayload();
      if (!col) toast("Coleção vazia: preencha a aba 'Minha coleção'."); else body.collection = col;
    }
    const r = await api("/api/analyze", body);
    $("#analyze-result").innerHTML = renderAnalysis(r, true);
    bindSuggest(body);
  } catch (e) { toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
});

function labelClass(l) { return "lbl l-" + l.replace(/ /g, "-"); }
const LABEL_COLOR = { "muito favorável": "var(--vgood)", "favorável": "var(--good)", "equilibrado": "var(--even)", "desfavorável": "var(--bad)", "muito desfavorável": "var(--vbad)" };
// Barra de 30% a 70%, com linha em 50% e intervalo de credibilidade quando há dados.
function probBar(p, interval, label) {
  const x = (v) => Math.max(0, Math.min(100, ((v - 0.3) / 0.4) * 100));
  const ci = interval ? `<div class="ci" style="left:${x(interval[0])}%;width:${Math.max(1, x(interval[1]) - x(interval[0]))}%"></div>` : "";
  return `<div class="bar"><div class="fill" style="width:${x(p)}%;background:${LABEL_COLOR[label] || "var(--accent)"}"></div><div class="mid"></div>${ci}</div>`;
}

function renderAnalysis(r, withSuggest) {
  const warn = r.data && r.data.warning ? `<div class="warn">${esc(r.data.warning)}</div>` : "";
  const conf = `<span class="conf">confiança: ${esc(r.confidence.level)}</span>`;
  const mus = [...r.matchups].sort((a, b) => b.win_prob - a.win_prob).map((m) => {
    const why = m.win_prob >= 0.5 ? m.reasons_for : m.reasons_against;
    const extra = m.exact_games ? ` · ${m.exact_games} partidas do deck exato` : "";
    const ci = m.interval ? ` · intervalo 90%: ${pct(m.interval[0], 0)}–${pct(m.interval[1], 0)}` : "";
    return `<div class="mu">
      <div class="name">${esc(m.name)}</div>${probBar(m.win_prob, m.interval, m.label)}
      <div><b>${pct(m.win_prob)}</b></div>
      <div class="why"><span class="${labelClass(m.label)}">${esc(m.label)}</span>
        <span class="conf">${esc(m.confidence)}</span> ${esc(m.source)}${extra}${ci}<br>${esc(m.explanation)}</div>
    </div>`;
  }).join("");
  const caps = r.capabilities.map((c) => `<div class="cap"><span>${esc(c.name)}</span>
      <div class="bar"><div class="fill" style="width:${100 * c.value}%;background:${c.rating === "forte" ? "var(--good)" : c.rating === "fraca" ? "var(--bad)" : "var(--even)"}"></div>
      <div class="base" style="left:${100 * c.baseline}%"></div></div><span>${(100 * c.value).toFixed(0)}</span></div>`).join("");
  const syn = r.synergies.filter((s) => s.value > 0).slice(0, 6).map((s) => `<li class="pos">${esc(state.byKey[s.cards[0]]?.name_pt)} + ${esc(state.byKey[s.cards[1]]?.name_pt)}: ${esc(s.reason)} <span class="muted">(${esc(s.source)})</span></li>`).join("");
  const con = r.synergies.filter((s) => s.value < 0).slice(0, 4).map((s) => `<li class="neg">${esc(state.byKey[s.cards[0]]?.name_pt)} + ${esc(state.byKey[s.cards[1]]?.name_pt)}: ${esc(s.reason)}</li>`).join("")
    + r.coherence.issues.map((i) => `<li class="neg">${esc(i)}</li>`).join("");
  const cards = r.cards.map((c) => {
    const lv = c.at_level;
    const lvl = lv.level != null ? `${lv.level} (${lv.gap >= 0 ? "+" : ""}${lv.gap}; atributos ×${lv.stat_factor})${lv.owned === false ? " <i>não possui</i>" : ""}` : "—";
    const meta = c.meta ? `${pct(c.meta.winrate_shrunk)} em ${c.meta.games} partidas · uso ${pct(c.meta.usage)}` : "<span class='muted'>sem dados</span>";
    return `<tr><td>${esc(c.name_pt)}${lv.evolution ? " <b>[EVO]</b>" : ""}</td><td>${c.elixir}</td><td>${c.theoretical.tier}/5</td>
      <td>${lvl}</td><td>${meta}</td><td>${pp(c.fit.ev_contribution)}</td></tr>`;
  }).join("");
  const factors = r.factors.items.map((f) => `<tr><td>${esc(f.factor.replace(/_/g, " "))}</td><td>${f.available ? (100 * f.value).toFixed(0) : "<span class='muted'>sem dados</span>"}</td><td>${f.weight}</td></tr>`).join("");
  const lv = r.levels;
  const levels = lv.provided
    ? `<p>Diferença efetiva de nível: <b>${lv.effective_gap >= 0 ? "+" : ""}${lv.effective_gap}</b> em relação à referência ${lv.reference_level}
       → impacto de <b>${pp(lv.impact_ev)}</b> na média. ${esc(lv.note)}
       ${lv.evolutions_used.length ? "<br>Evoluções usadas: " + lv.evolutions_used.map((k) => esc(state.byKey[k]?.name_pt)).join(", ") : ""}
       ${lv.not_owned.length ? "<br><b>Cartas que você não possui:</b> " + lv.not_owned.map((k) => esc(state.byKey[k]?.name_pt)).join(", ") : ""}</p>`
    : `<p class="muted">${esc(lv.note)}</p>`;
  const o = r.overall;
  return `<div class="panel">
      <h2>${esc(r.archetype.primary_pt)} · custo médio ${r.avg_elixir} · ciclo ${r.cycle_cost} ${conf}</h2>
      <p class="muted">Rótulos: ${r.archetype.labels_pt.map(esc).join(", ")}</p>
      <p class="summary">${esc(r.summary)}</p>${warn}
      <p><b>Média vs meta:</b> ${pct(o.ev)} · <b>pior matchup:</b> ${pct(o.worst)} · <b>desvio entre matchups:</b> ${(100 * o.sd).toFixed(1)} p.p.
        · <b>score (${esc(o.objective_mode)}):</b> ${(100 * o.score).toFixed(1)}<br><span class="muted">Meta: ${esc(o.meta_source)}. ${esc(o.note)}</span></p>
    </div>
    <div class="panel"><h2>Matchups por arquétipo</h2>${mus}</div>
    <div class="cols">
      <div class="panel"><h2>Pontos fortes</h2><ul class="clean">${r.strengths.map((s) => `<li class="pos">${esc(s)}</li>`).join("") || "<li class='muted'>Nenhum destaque acima da média.</li>"}</ul>
        <h2 style="margin-top:14px">Vulnerabilidades</h2><ul class="clean">${r.vulnerabilities.map((v) => `<li class="neg">${esc(v.message)}</li>`).join("") || "<li class='muted'>Nenhuma vulnerabilidade evidente.</li>"}</ul></div>
      <div class="panel"><h2>Sinergias e conflitos</h2><ul class="clean">${syn}${con}</ul>${!syn && !con ? "<p class='muted'>Nenhum par catalogado.</p>" : ""}</div>
    </div>
    <div class="panel"><h2>Capacidades <span class="muted">(traço = média dos decks de referência)</span></h2>${caps}</div>
    <div class="panel"><h2>Cartas: força teórica, no nível, no meta e compatibilidade</h2>
      <div class="table-wrap"><table><tr><th>Carta</th><th>Elixir</th><th>Teórica</th><th>Nível</th><th>Meta (dados)</th><th>Contribuição ao deck</th></tr>${cards}</table></div>
      ${levels}</div>
    <details class="panel"><summary>Índice de fatores (secundário): ${r.factors.index ?? "—"}</summary>
      <p class="muted">${esc(r.factors.note)}</p><table><tr><th>Fator</th><th>Valor</th><th>Peso</th></tr>${factors}</table></details>
    ${withSuggest ? `<div class="panel"><h2>Otimização</h2>
      <div class="row"><label><input type="checkbox" id="sg-keep"> manter a condição de vitória</label>
      <select id="sg-target"><option value="">melhorar a média geral</option>${state.archetypes.map((a) => `<option value="${a.key}">melhorar vs ${esc(a.name)}</option>`).join("")}</select>
      <button id="btn-suggest">Sugerir trocas</button></div><div id="suggest-result"></div></div>` : ""}`;
}

function bindSuggest(baseBody) {
  const btn = $("#btn-suggest");
  if (!btn) return;
  btn.addEventListener("click", async () => {
    btn.disabled = true;
    try {
      const r = await api("/api/suggest", { ...baseBody, keep_win_condition: $("#sg-keep").checked, target: $("#sg-target").value || null, top: 6 });
      const swaps = r.swaps.map((s) => `<li class="pos">${esc(s.explanation)}</li>`).join("") || "<li class='muted'>Nenhuma troca melhora o deck segundo o modelo atual.</li>";
      const repl = Object.entries(r.replacements).map(([k, opts]) => `<tr><td>${esc(state.byKey[k]?.name_pt)}</td><td>${opts.map((o) => `${esc(o.in_pt)} (${pp(o.delta_ev)})`).join(", ")}</td></tr>`).join("");
      $("#suggest-result").innerHTML = `<h3>Melhores trocas</h3><ul class="clean">${swaps}</ul>
        <details><summary>Três melhores substitutas para cada carta</summary><table><tr><th>Sai</th><th>Opções (efeito na média vs meta)</th></tr>${repl}</table></details>
        <p class="muted">${esc(r.note)}</p>`;
    } catch (e) { toast("Erro: " + e.message); }
    finally { btn.disabled = false; }
  });
}

// ------------------------------------------------------------------ CRIAR
function renderChips() {
  for (const k of ["wincon", "must", "exclude"]) {
    const el = $("#chips-" + k);
    el.innerHTML = state.build[k].map((c) => `<span class="chip" data-k="${esc(c)}" title="remover">${esc(state.byKey[c]?.name_pt)} ✕</span>`).join("") || "<span class='muted'>nenhuma</span>";
    $$(".chip", el).forEach((ch) => ch.addEventListener("click", () => { state.build[k] = state.build[k].filter((x) => x !== ch.dataset.k); renderChips(); refreshBuildPicker(); }));
  }
}
function refreshBuildPicker() {
  const mode = $("#build-mode").value;
  const all = state.cards;
  const save = state.cards;
  if (mode === "wincon") state.cards = all.filter((c) => c.tags.includes("wc") || c.tags.includes("wc2"));
  renderPicker($("#build-picker"), $("#build-search").value, (k) => state.build[mode].includes(k), (k) => {
    for (const m of ["wincon", "must", "exclude"]) if (m !== mode) state.build[m] = state.build[m].filter((x) => x !== k);
    const arr = state.build[mode];
    const i = arr.indexOf(k);
    if (i >= 0) arr.splice(i, 1); else arr.push(k);
    renderChips(); refreshBuildPicker();
  });
  state.cards = save;
}
$("#build-mode").addEventListener("change", refreshBuildPicker);
$("#build-search").addEventListener("input", refreshBuildPicker);
$("#btn-build").addEventListener("click", async () => {
  const btn = $("#btn-build");
  btn.disabled = true;
  $("#build-result").innerHTML = "<div class='panel muted'>Buscando combinações…</div>";
  try {
    const body = {
      must_include: state.build.must, exclude: state.build.exclude, win_conditions: state.build.wincon,
      style: $("#build-style").value || null,
      max_avg_elixir: parseFloat($("#build-max").value) || null, min_avg_elixir: parseFloat($("#build-min").value) || null,
      top_k: parseInt($("#build-top").value) || 5,
    };
    if ($("#build-use-col").checked) {
      body.collection = collectionPayload();
      if (!body.collection) toast("Coleção vazia: usando todas as cartas. Preencha 'Minha coleção' para considerar níveis.");
    }
    const r = await api("/api/build", body);
    const heads = state.archetypes.map((a) => `<th title="${esc(a.name)}">${esc(a.name.split(" ")[0])}</th>`).join("");
    const rows = r.comparison.map((c) => `<tr><td>#${c.rank}</td><td>${c.deck.map((k) => esc(state.byKey[k]?.name_pt)).join(", ")}</td>
      <td>${c.avg_elixir}</td><td><b>${pct(c.ev)}</b></td><td>${pct(c.worst)}</td><td>${(100 * c.consistency_sd).toFixed(1)}</td>
      <td>${c.level_gap == null ? "—" : (c.level_gap >= 0 ? "+" : "") + c.level_gap}</td><td>${esc(c.confidence)}</td>
      ${state.archetypes.map((a) => { const p = c.by_archetype[a.key]; return `<td style="color:${p >= 0.53 ? "var(--vgood)" : p < 0.47 ? "var(--vbad)" : "inherit"}">${(100 * p).toFixed(0)}</td>`; }).join("")}</tr>`).join("");
    const details = r.decks.map((d) => `<details class="panel"><summary>${esc(d.why)}</summary>${renderAnalysis(d.analysis, false)}</details>`).join("");
    $("#build-result").innerHTML = `<div class="panel"><h2>Comparação</h2><p class="muted">${esc(r.note)}</p>
      <div class="table-wrap"><table><tr><th></th><th>Deck</th><th>Elixir</th><th>Média</th><th>Pior</th><th>Desvio</th><th>Nível</th><th>Conf.</th>${heads}</tr>${rows}</table></div></div>${details}`;
  } catch (e) { $("#build-result").innerHTML = ""; toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
});

// ------------------------------------------------------------------ COLEÇÃO
function renderCollection() {
  const col = loadCollection();
  $("#col-ref").value = col.reference_level ?? "";
  const q = $("#col-filter").value;
  const list = state.cards.filter((c) => matches(c, q)).sort((a, b) => a.name_pt.localeCompare(b.name_pt));
  $("#col-table").innerHTML = `<div class="col-grid">${list.map((c) => `<div class="col-item">
      <span title="${esc(c.key)}">${esc(c.name_pt)}</span>
      <input type="number" min="1" max="16" data-key="${esc(c.key)}" value="${col.cards[c.key] ?? ""}" placeholder="—">
      ${c.evo ? `<label title="evolução desbloqueada"><input type="checkbox" data-evo="${esc(c.key)}" ${col.evolutions.includes(c.key) ? "checked" : ""}>evo</label>` : "<span></span>"}
    </div>`).join("")}</div>`;
  $$("#col-table input[type=number]").forEach((inp) => inp.addEventListener("change", () => {
    const c = loadCollection();
    const v = parseFloat(inp.value);
    if (isNaN(v)) delete c.cards[inp.dataset.key]; else c.cards[inp.dataset.key] = Math.max(1, Math.min(16, v));
    saveCollection(c);
  }));
  $$("#col-table input[data-evo]").forEach((inp) => inp.addEventListener("change", () => {
    const c = loadCollection();
    c.evolutions = c.evolutions.filter((k) => k !== inp.dataset.evo);
    if (inp.checked) c.evolutions.push(inp.dataset.evo);
    saveCollection(c);
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
    const c = { cards: {}, evolutions: d.evolutions || [], reference_level: d.reference_level ?? null };
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
    const d = s.data;
    if (!d.model) {
      $("#data-status").innerHTML = `<p><b>Modo heurístico.</b> ${esc(d.note)}</p>
        <p class="muted">Para usar dados reais: <code>crlab data crawl --top 100</code> (requer CR_API_TOKEN) ou
        <code>crlab data import --file partidas.jsonl</code>, depois <code>crlab data train</code>.</p>`;
      return;
    }
    const v = d.validation;
    $("#data-status").innerHTML = `${d.warning ? `<div class="warn">${esc(d.warning)}</div>` : ""}
      <table><tr><th>Partidas usadas</th><td>${d.battles}</td></tr>
      <tr><th>Período</th><td>${esc(d.first?.slice(0, 10))} a ${esc(d.last?.slice(0, 10))} (janela de ${d.days} dias, meia-vida ${d.half_life_days} dias)</td></tr>
      <tr><th>Fontes</th><td>${esc((d.sources || []).join(", "))}</td></tr>
      <tr><th>Descartadas (carta desconhecida)</th><td>${d.dropped}</td></tr>
      ${v ? `<tr><th>Validação temporal</th><td>log-loss ${v.logloss_model.toFixed(4)} (base ${v.logloss_baseline.toFixed(4)}) · acurácia ${pct(v.accuracy_model)} em ${v.holdout} partidas mais recentes</td></tr>` : ""}
      <tr><th>Treinado em</th><td>${esc(d.trained_at)}</td></tr></table>`;
  } catch (e) { $("#data-status").textContent = "Erro: " + e.message; }
}
async function banner() {
  try {
    const s = await api("/api/status");
    const d = s.data;
    $("#data-banner").innerHTML = d.model
      ? (d.warning ? `<div class="warn">${esc(d.warning)}</div>` : `<p class="muted">Modelo treinado com ${d.battles} partidas reais (${esc(d.first?.slice(0, 10))} a ${esc(d.last?.slice(0, 10))}).</p>`)
      : `<p class="muted">Modo heurístico: nenhum modelo de dados treinado. As estimativas são indicadas como heurísticas.</p>`;
  } catch { /* ignora */ }
}

// ------------------------------------------------------------------ init
(async function init() {
  try {
    state.cards = await api("/api/cards");
    state.byKey = Object.fromEntries(state.cards.map((c) => [c.key, c]));
    state.archetypes = await api("/api/archetypes");
    $("#build-style").innerHTML += state.archetypes.map((a) => `<option value="${a.key}">${esc(a.name)}</option>`).join("");
    state.deck = ["Hog Rider", "Musketeer", "Ice Golem", "Ice Spirit", "Skeletons", "Cannon", "Fireball", "The Log"];
    renderSlots(); refreshAnalyzePicker(); renderChips(); refreshBuildPicker(); banner();
  } catch (e) { toast("Falha ao carregar: " + e.message, 8000); }
})();
