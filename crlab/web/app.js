"use strict";
// Interface web do Clash Deck Lab (sem dependências externas). Todo texto dinâmico passa por esc().

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const num = (v) => (typeof v === "number" && isFinite(v) ? v : 0);
const pct = (p, d = 0) => (100 * num(p)).toFixed(d) + "%";
const pp = (x) => (x >= 0 ? "+" : "−") + Math.abs(100 * num(x)).toFixed(1);
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");

const state = { cards: [], byKey: {}, archetypes: [], archName: {}, deck: [], build: { wincon: [], must: [], exclude: [] } };
const COL_KEY = "crlab.collection.v1", PLAYER_KEY = "crlab.player.v1", DECK_KEY = "crlab.deck.v1";

// Rótulos curtos (o texto completo fica no tooltip)
const STRONG = { air_defense: "Defesa aérea", air_swarm: "Área aérea", ground_swarm: "Área terrestre", tank_killing: "Anti-tanque",
  building_def: "Segura Corredor/RG", cheap_answers: "Respostas baratas", cycle: "Ciclo rápido", elixir_eff: "Custo baixo",
  spells: "Feitiços completos", reset: "Tem reset", pressure: "Boa pressão", siege_breaking: "Quebra construções",
  counterattack: "Contra-ataque", anti_graveyard: "Anti-Cemitério", defense_volume: "Defesa robusta" };
const WEAK = { air_defense: "Defesa aérea fraca", air_swarm: "Pouca área aérea", ground_swarm: "Pouca área terrestre",
  tank_killing: "Pouco anti-tanque", building_def: "Exposto a Corredor/RG", cycle: "Ciclo lento", anti_graveyard: "Exposto a Cemitério",
  siege_breaking: "Sofre com siege", defense_volume: "Defesa frágil", pressure: "Pouca pressão", spells: "Feitiços incompletos",
  reset: "Sem reset" };
const GROUPS = [
  ["✈️", "Defesa aérea", ["air_defense", "air_swarm"]],
  ["🛡️", "Contra tanques", ["tank_killing", "defense_volume"]],
  ["💥", "Contra enxames", ["ground_swarm", "anti_graveyard"]],
  ["🏰", "Contra Corredor/RG", ["building_def"]],
  ["🔄", "Ciclo e custo", ["cycle", "elixir_eff", "cheap_answers"]],
  ["⚔️", "Ataque", ["pressure", "siege_breaking", "counterattack"]],
  ["✨", "Feitiços", ["spells", "reset"]],
];

// ------------------------------------------------------------------ utilidades
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
const cardName = (k) => esc(state.byKey[k]?.name_pt || k);
const loading = (msg) => `<div class="panel loading"><span class="spinner"></span>${esc(msg)}</div>`;

// Tooltip único: qualquer elemento com data-tip (texto puro, quebras de linha preservadas)
const tipEl = () => $("#tip");
document.addEventListener("mouseover", (e) => {
  const el = e.target.closest("[data-tip]");
  if (!el) { tipEl().style.display = "none"; return; }
  tipEl().textContent = el.dataset.tip;
  tipEl().style.whiteSpace = "pre-line";
  tipEl().style.display = "block";
});
document.addEventListener("mousemove", (e) => {
  const t = tipEl();
  if (t.style.display !== "block") return;
  const x = Math.min(e.clientX + 14, window.innerWidth - t.offsetWidth - 8);
  const y = e.clientY + 16 + t.offsetHeight > window.innerHeight ? e.clientY - t.offsetHeight - 10 : e.clientY + 16;
  t.style.left = x + "px"; t.style.top = y + "px";
});

// ------------------------------------------------------------------ navegação
function showTab(name) {
  $$("nav button").forEach((x) => x.classList.toggle("active", x.dataset.tab === name));
  $$(".tab").forEach((t) => t.classList.toggle("active", t.id === "tab-" + name));
  if (name === "collection") renderCollection();
  if (name === "data") renderStatus();
  if (name === "analyze") renderSlots();
}
$$("nav button").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));

// ------------------------------------------------------------------ cartas
const imgUrl = (c, size, evo = false) => `/img/card/${size}/${encodeURIComponent(c.slug)}${evo ? "-ev1" : ""}.png`;
// Imagem quebrada: tenta a versão sem evolução; se falhar, mostra a inicial da carta.
document.addEventListener("error", (e) => {
  const img = e.target;
  if (!(img instanceof HTMLImageElement)) return;
  if (img.dataset.fallback) { img.src = img.dataset.fallback; delete img.dataset.fallback; return; }
  img.closest(".ctile, .mini")?.classList.add("noimg");
}, true);

function tile(c, { size = "s", inDeck = false, off = false, extraTip = "", evoArt = false, showLevel = true } = {}) {
  if (!c) return "";
  const col = loadCollection();
  const lvl = col.cards[c.key];
  const ref = col.reference_level || refLevel(col);
  const hasEvo = col.evolutions.includes(c.key);
  let badge = "";
  if (showLevel && hasEvo) badge = `<span class="badge evo">EVO</span>`;
  else if (showLevel && lvl != null) badge = `<span class="badge ${ref && lvl < ref - 0.5 ? "low" : ""}">${num(lvl)}</span>`;
  const useEvo = evoArt && hasEvo && c.evo;
  const src = imgUrl(c, size, useEvo);
  const fb = useEvo ? ` data-fallback="${imgUrl(c, size)}"` : "";
  const tip = `${c.name_pt}  ·  ${c.elixir} de elixir${lvl != null ? "  ·  nível " + lvl : ""}${extraTip ? "\n" + extraTip : ""}`;
  return `<div class="ctile r-${esc(c.rarity)} ${inDeck ? "in" : ""} ${off ? "off" : ""}" data-key="${esc(c.key)}" data-tip="${esc(tip)}">
    <div class="art" data-initial="${esc(c.name_pt.slice(0, 1))}"><img src="${src}"${fb} alt="${esc(c.name_pt)}" loading="lazy"></div>
    <span class="drop"><span>${num(c.elixir)}</span></span>${badge}<span class="nm">${esc(c.name_pt)}</span></div>`;
}
function refLevel(col) {
  const v = Object.values(col.cards).filter((x) => typeof x === "number").sort((a, b) => a - b);
  return v.length ? v[Math.floor(0.75 * (v.length - 1))] : null;
}
function mini(k) {
  const c = state.byKey[k];
  if (!c) return esc(k);
  return `<span class="mini"><img src="${imgUrl(c, "s")}" alt="" loading="lazy">${esc(c.name_pt)}</span>`;
}
function matches(card, q) {
  if (!q) return true;
  const n = norm(q);
  return norm(card.key).includes(n) || norm(card.name_pt).includes(n);
}

// ------------------------------------------------------------------ seletor de cartas (janela)
const picker = { mode: "deck", slot: null, elixir: "all", type: "all" };
const MODE_TITLE = { wincon: "Condições de vitória", must: "Cartas obrigatórias", exclude: "Cartas a evitar" };
function openPicker(mode, slot = null) {
  Object.assign(picker, { mode, slot, elixir: "all", type: "all" });
  $$("#m-elixir button, #m-type button").forEach((b) => b.classList.toggle("on", b.dataset.v === "all"));
  $("#m-search").value = "";
  const hasCol = Object.keys(loadCollection().cards).length > 0;
  $("#m-owned").checked = hasCol && (mode === "deck" ? $("#analyze-use-col").checked : $("#build-use-col").checked);
  $("#m-owned").parentElement.style.display = hasCol ? "" : "none";
  $("#modal").hidden = false;
  renderModal();
  setTimeout(() => $("#m-search").focus(), 30);
}
function closePicker() {
  $("#modal").hidden = true;
  if (picker.mode === "deck") { renderSlots(); } else { renderChips(); }
}
function pickerSelected() { return picker.mode === "deck" ? state.deck : state.build[picker.mode]; }
function renderModal() {
  const col = loadCollection();
  const sel = pickerSelected();
  let list = state.cards;
  if (picker.mode === "wincon") list = list.filter((c) => c.tags.includes("wc") || c.tags.includes("wc2"));
  if ($("#m-owned").checked) list = list.filter((c) => c.key in col.cards);
  if (picker.elixir !== "all") list = list.filter((c) => (picker.elixir === "6" ? c.elixir >= 6 : c.elixir === +picker.elixir));
  if (picker.type !== "all") list = list.filter((c) => c.type === picker.type);
  list = list.filter((c) => matches(c, $("#m-search").value)).sort((a, b) => a.elixir - b.elixir || a.name_pt.localeCompare(b.name_pt));
  const title = picker.mode === "deck"
    ? (picker.slot != null && state.deck[picker.slot] ? `Trocar ${state.byKey[state.deck[picker.slot]].name_pt}` : `Montar deck · ${state.deck.length}/8`)
    : MODE_TITLE[picker.mode];
  $("#modal-title").textContent = title;
  $("#m-grid").innerHTML = list.map((c) => tile(c, { inDeck: sel.includes(c.key) })).join("") || "<p class='muted'>Nenhuma carta com esses filtros.</p>";
  $$("#m-grid .ctile").forEach((el) => el.addEventListener("click", () => pickCard(el.dataset.key)));
}
function pickCard(k) {
  if (picker.mode === "deck") {
    const i = state.deck.indexOf(k);
    if (picker.slot != null && state.deck[picker.slot]) {
      if (i >= 0) { [state.deck[i], state.deck[picker.slot]] = [state.deck[picker.slot], state.deck[i]]; }
      else state.deck[picker.slot] = k;
      store(DECK_KEY, state.deck); deckChanged(); closePicker(); return;
    }
    if (i >= 0) state.deck.splice(i, 1);
    else if (state.deck.length < 8) state.deck.push(k);
    else return toast("Deck completo. Remova uma carta primeiro.");
    store(DECK_KEY, state.deck); deckChanged();
    renderSlots();
    if (state.deck.length === 8 && i < 0) { closePicker(); return; }
  } else {
    for (const m of ["wincon", "must", "exclude"]) if (m !== picker.mode) state.build[m] = state.build[m].filter((x) => x !== k);
    const arr = state.build[picker.mode];
    const i = arr.indexOf(k);
    if (i >= 0) arr.splice(i, 1); else arr.push(k);
  }
  renderModal();
}
(function initModal() {
  const seg = (el, items, key) => {
    el.innerHTML = items.map(([v, label]) => `<button data-v="${v}" class="${picker[key] === v ? "on" : ""}">${label}</button>`).join("");
    $$("button", el).forEach((b) => b.addEventListener("click", () => {
      picker[key] = b.dataset.v;
      $$("button", el).forEach((x) => x.classList.toggle("on", x === b));
      renderModal();
    }));
  };
  seg($("#m-elixir"), [["all", "💧 Todos"], ["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"], ["6", "6+"]], "elixir");
  seg($("#m-type"), [["all", "Todas"], ["troop", "Tropas"], ["spell", "Feitiços"], ["building", "Construções"]], "type");
  $("#m-search").addEventListener("input", renderModal);
  $("#m-owned").addEventListener("change", renderModal);
  $("#modal-done").addEventListener("click", closePicker);
  $("#modal").addEventListener("click", (e) => { if (e.target.id === "modal") closePicker(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("#modal").hidden) closePicker(); });
})();

// ------------------------------------------------------------------ conta (tag)
function renderAccount() {
  const p = load(PLAYER_KEY, null);
  if (!p) return;
  $("#account").innerHTML = `<div class="player-chip" data-tip="${esc(`${p.tag}\n${num(p.n_cards)} cartas · ${num(p.n_evos)} evoluções${p.arena ? "\n" + p.arena : ""}`)}">
    👤 <b>${esc(p.name)}</b>${p.trophies != null ? ` 🏆 ${num(p.trophies)}` : ""}<button id="btn-switch">Atualizar</button></div>`;
  $("#btn-switch").addEventListener("click", () => importTag(p.tag));
}
async function importTag(rawTag) {
  const tag = String(rawTag || "").trim().replace(/^#/, "").toUpperCase();
  if (!tag) return toast("Digite sua tag (ex.: #2PQ8RJ0LV).");
  toast("Buscando sua conta…", 10000);
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
    renderAccount(); renderSlots(); renderChips();
    if ($("#tab-collection").classList.contains("active")) renderCollection();
    toast(`Conta importada: ${Object.keys(col.cards).length} cartas${deck.length === 8 ? " e deck atual" : ""}.`);
  } catch (e) { toast("Erro: " + e.message, 6000); }
}
function bindAccountInput() {
  const btn = $("#btn-tag");
  if (!btn) return;
  btn.addEventListener("click", () => importTag($("#tag-input").value));
  $("#tag-input").addEventListener("keydown", (e) => { if (e.key === "Enter") importTag($("#tag-input").value); });
}

// ------------------------------------------------------------------ ANALISAR
function deckChanged() {
  state.contrib = null;
  $("#analyze-result").innerHTML = "";
}
function renderSlots() {
  const slots = $("#deck-slots");
  slots.innerHTML = "";
  for (let i = 0; i < 8; i++) {
    const c = state.deck[i] && state.byKey[state.deck[i]];
    const info = c && state.contrib ? state.contrib[c.key] : null;
    const d = document.createElement("div");
    d.className = "cell";
    d.innerHTML = c ? tile(c, { size: "l", evoArt: true, extraTip: (info ? info.tip + "\n" : "") + "Toque para trocar" })
      : `<div class="ctile empty" data-tip="Adicionar carta"><div class="art">+</div><span class="nm">&nbsp;</span></div>`;
    if (info) {
      d.insertAdjacentHTML("beforeend", `<div class="contrib" data-tip="Contribuição para o deck: ${pp(info.v)} p.p. de chance de vitória">
        <i style="width:${info.w.toFixed(0)}%;${info.v < 0 ? "background:var(--neg)" : ""}"></i></div><div class="contrib-v">${pp(info.v)}</div>`);
    }
    d.querySelector(".ctile").addEventListener("click", () => openPicker("deck", c ? i : null));
    slots.appendChild(d);
  }
  const els = state.deck.map((k) => state.byKey[k]?.elixir || 0);
  const avg = els.length ? els.reduce((a, b) => a + b, 0) / els.length : 0;
  const cyc = [...els].sort((a, b) => a - b).slice(0, 4).reduce((a, b) => a + b, 0);
  $("#deck-meta").innerHTML = `<span class="stat-chip" data-tip="Custo médio de elixir">💧 <b>${avg.toFixed(1)}</b></span>
    <span class="stat-chip" data-tip="Soma das 4 cartas mais baratas (velocidade de ciclo)">🔄 <b>${els.length >= 4 ? cyc : "—"}</b></span>
    <span class="stat-chip">🃏 <b>${state.deck.length}</b>/8</span>`;
}
$("#btn-clear").addEventListener("click", () => { state.deck = []; store(DECK_KEY, []); deckChanged(); renderSlots(); openPicker("deck"); });
$("#btn-paste").addEventListener("click", () => {
  const txt = prompt("Cole as 8 cartas separadas por vírgula (português ou inglês):");
  if (!txt) return;
  const found = [], missing = [];
  for (const raw of txt.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)) {
    const c = state.cards.find((x) => norm(x.key) === norm(raw) || norm(x.name_pt) === norm(raw));
    if (c) found.push(c.key); else missing.push(raw);
  }
  state.deck = [...new Set(found)].slice(0, 8);
  store(DECK_KEY, state.deck); deckChanged(); renderSlots();
  if (missing.length) toast("Não reconhecidas: " + missing.join(", "));
});
$("#btn-analyze").addEventListener("click", () => analyzeDeck());

async function analyzeDeck() {
  if (state.deck.length !== 8) return toast("Selecione exatamente 8 cartas.");
  const btn = $("#btn-analyze");
  btn.disabled = true;
  $("#analyze-result").innerHTML = loading("Analisando…");
  try {
    const body = { deck: state.deck };
    if ($("#analyze-use-col").checked) {
      const col = collectionPayload();
      if (col) body.collection = col;
    }
    const r = await api("/api/analyze", body);
    const maxC = Math.max(0.01, ...r.cards.map((c) => Math.abs(num(c.fit.ev_contribution))));
    state.contrib = Object.fromEntries(r.cards.map((c) => [c.card, {
      v: num(c.fit.ev_contribution), w: (Math.abs(num(c.fit.ev_contribution)) / maxC) * 100,
      tip: [
        `Força teórica: ${"★".repeat(num(c.theoretical.tier))}`,
        c.at_level.level != null ? `Seu nível: ${c.at_level.level} (${c.at_level.gap >= 0 ? "+" : ""}${c.at_level.gap} vs referência; atributos ×${c.at_level.stat_factor})` : null,
        c.meta ? `No meta: ${pct(c.meta.winrate_shrunk, 1)} de vitórias em ${c.meta.games} partidas` : null,
        `Contribuição: ${pp(c.fit.ev_contribution)} p.p.`,
      ].filter(Boolean).join("\n"),
    }]));
    renderSlots();
    $("#analyze-result").innerHTML = renderAnalysis(r, true);
    bindSuggest(body);
  } catch (e) { $("#analyze-result").innerHTML = ""; toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
}

// --- peças visuais
function ring(p) {
  const r = 52, c = 2 * Math.PI * r, v = Math.max(0, Math.min(1, num(p)));
  const color = v >= 0.5 ? "var(--pos)" : "var(--neg)";
  return `<div class="ring" data-tip="Chance média de vitória contra o meta (ponderada pela frequência de cada arquétipo)">
    <svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="${r}" fill="none" stroke="var(--meter-bg)" stroke-width="11"/>
    <circle cx="60" cy="60" r="${r}" fill="none" stroke="${color}" stroke-width="11" stroke-linecap="round" stroke-dasharray="${(v * c).toFixed(1)} ${c.toFixed(1)}"/></svg>
    <div class="val"><div><b>${pct(v, 1)}</b><span>vs meta</span></div></div></div>`;
}
function divergingChart(matchups) {
  const rows = [...matchups].sort((a, b) => b.win_prob - a.win_prob).map((m) => {
    const d = num(m.win_prob) - 0.5;
    const w = Math.min(50, (Math.abs(d) / 0.2) * 50); // ±20 p.p. = meia largura
    const tip = `${m.name}: ${pct(m.win_prob, 1)} (${m.label})\n${m.explanation}\nConfiança: ${m.confidence} · fonte: ${m.source}`
      + (m.interval ? `\nIntervalo 90%: ${pct(m.interval[0])}–${pct(m.interval[1])}` : "")
      + (m.exact_games ? `\n${m.exact_games} partidas deste deck` : "");
    return `<div class="div-row" data-tip="${esc(tip)}">
      <div class="nm">${esc(m.name)}<small>${pct(m.meta_share)} do meta</small></div>
      <div class="div-track"><div class="div-bar ${d >= 0 ? "pos" : "neg"}" style="width:${w.toFixed(1)}%"></div></div>
      <div class="v">${pct(m.win_prob)}</div></div>`;
  }).join("");
  return `<div class="div-chart">${rows}</div>
    <div class="axis"><span></span><div class="ticks"><span>30%</span><span>40%</span><span>50%</span><span>60%</span><span>70%</span></div><span></span></div>`;
}
function profile(caps) {
  const by = Object.fromEntries(caps.map((c) => [c.key, c]));
  return GROUPS.map(([ic, name, keys]) => {
    const items = keys.map((k) => by[k]).filter(Boolean);
    const v = items.reduce((a, c) => a + num(c.value), 0) / items.length;
    const b = items.reduce((a, c) => a + num(c.baseline), 0) / items.length;
    const tip = items.map((c) => `${c.name}: ${(100 * c.value).toFixed(0)} (média ${(100 * c.baseline).toFixed(0)})`).join("\n");
    return `<div class="meter" data-tip="${esc(tip)}"><span><span class="ic">${ic}</span>${esc(name)}</span>
      <div class="track"><div class="fill" style="width:${(100 * v).toFixed(0)}%"></div><div class="base" style="left:${(100 * b).toFixed(0)}%"></div></div>
      <span class="n">${(100 * v).toFixed(0)}</span></div>`;
  }).join("") + `<div class="legend" style="margin-top:8px"><span><i style="background:var(--meter)"></i>seu deck</span><span><i style="background:var(--text-2);width:2px"></i>média de decks conhecidos</span></div>`;
}
function verdictLine(ms) {
  const sorted = [...ms].sort((a, b) => b.win_prob - a.win_prob);
  const good = sorted.filter((m) => m.win_prob >= 0.53).slice(0, 2).map((m) => m.name);
  const bad = sorted.filter((m) => m.win_prob < 0.47).reverse().slice(0, 2).map((m) => m.name);
  const parts = [];
  if (good.length) parts.push(`Forte contra <b>${good.map(esc).join(" e ")}</b>`);
  if (bad.length) parts.push(`fraco contra <b>${bad.map(esc).join(" e ")}</b>`);
  return parts.length ? parts.join(" · ") : "Matchups equilibrados, sem grandes forças ou fraquezas.";
}

function renderAnalysis(r, withSuggest) {
  const strengths = r.capabilities.filter((c) => c.rating === "forte").sort((a, b) => (b.value - b.baseline) - (a.value - a.baseline)).slice(0, 3);
  const seen = new Set();
  const weak = r.vulnerabilities.filter((v) => WEAK[v.dimension] && !seen.has(v.dimension) && seen.add(v.dimension)).slice(0, 3);
  const tags = [
    ...strengths.map((c) => `<span class="tag good" data-tip="${esc(c.name)}: ${(100 * c.value).toFixed(0)} (média ${(100 * c.baseline).toFixed(0)})">✓ ${esc(STRONG[c.key] || c.name)}</span>`),
    ...weak.map((v) => `<span class="tag bad" data-tip="${esc(v.message)}">! ${esc(WEAK[v.dimension])}</span>`),
  ];
  const confTip = r.confidence.text;
  tags.push(`<span class="tag neutral" data-tip="${esc(confTip)}">◎ confiança ${esc(r.confidence.level)}</span>`);
  const lv = r.levels;
  if (lv.provided && Math.abs(lv.impact_ev) >= 0.005) {
    tags.push(`<span class="tag ${lv.impact_ev < 0 ? "bad" : "good"}" data-tip="${esc(`Diferença de nível ${lv.effective_gap >= 0 ? "+" : ""}${lv.effective_gap} vs referência ${lv.reference_level}. ${lv.note}`)}">⬆ níveis ${pp(lv.impact_ev)} p.p.</span>`);
  }
  if (lv.provided && lv.not_owned.length) tags.push(`<span class="tag bad" data-tip="${esc("Você não possui: " + lv.not_owned.map((k) => state.byKey[k]?.name_pt || k).join(", "))}">✕ ${lv.not_owned.length} carta(s) que você não tem</span>`);
  const notice = r.data && r.data.warning ? `<div class="notice">⚠ ${esc(r.data.warning)}</div>` : "";

  const syn = r.synergies.filter((s) => s.value > 0).slice(0, 5).map((s) =>
    `<div class="syn" data-tip="${esc(s.reason + " (" + s.source + ")")}">${mini(s.cards[0])}<span class="muted">+</span>${mini(s.cards[1])}</div>`).join("");
  const conf = r.synergies.filter((s) => s.value < 0).slice(0, 3).map((s) =>
    `<div class="syn" data-tip="${esc(s.reason)}">${mini(s.cards[0])}<span class="muted">✕</span>${mini(s.cards[1])}</div>`).join("");
  const issues = r.coherence.issues.map((i) => `<span class="tag bad" data-tip="${esc(i)}">! ${esc(i.split(":")[0].split("—")[0])}</span>`).join(" ");

  const tech = r.matchups.map((m) => `<tr><td>${esc(m.name)}</td><td>${pct(m.win_prob, 1)}</td><td>${m.interval ? `${pct(m.interval[0])}–${pct(m.interval[1])}` : "—"}</td>
    <td>${esc(m.confidence)}</td><td>${esc(m.source)}</td><td>${num(m.exact_games)}</td></tr>`).join("");
  const factors = r.factors.items.filter((f) => f.available).map((f) => `<tr><td>${esc(f.factor.replace(/_/g, " "))}</td><td>${(100 * num(f.value)).toFixed(0)}</td><td>${num(f.weight)}</td></tr>`).join("");

  return `
  <div class="panel">
    <div class="result-head">
      ${ring(r.overall.ev)}
      <div class="verdict">
        <h2>${esc(r.archetype.primary_pt)}</h2>
        <div class="line">${verdictLine(r.matchups)}</div>
        <div class="tags">${tags.join("")}</div>
        ${notice}
      </div>
    </div>
  </div>
  <div class="panel">
    <div class="panel-head"><h2>Matchups</h2><span class="spacer"></span>
      <div class="legend"><span><i style="background:var(--pos)"></i>favorável</span><span><i style="background:var(--neg)"></i>desfavorável</span></div></div>
    ${divergingChart(r.matchups)}
    <p class="muted" style="margin:10px 0 0">Passe o mouse em cada arquétipo para ver o motivo.</p>
  </div>
  <div class="grid-2">
    <div class="panel"><h2>Perfil do deck</h2>${profile(r.capabilities)}</div>
    <div class="panel"><h2>Combinações</h2>
      ${syn ? `<div class="sub">Sinergias</div><div class="syn-list">${syn}</div>` : `<p class="muted">Nenhuma sinergia catalogada.</p>`}
      ${conf || issues ? `<div class="sub">Conflitos</div><div class="syn-list">${conf}</div><div class="tags" style="margin-top:6px">${issues}</div>` : ""}
    </div>
  </div>
  ${withSuggest ? `<div class="panel"><div class="panel-head"><h2>Melhorar o deck</h2><span class="spacer"></span>
      <select id="sg-target"><option value="">média geral</option>${state.archetypes.map((a) => `<option value="${esc(a.key)}">vs ${esc(a.name)}</option>`).join("")}</select>
      <label class="check"><input type="checkbox" id="sg-keep"> manter condição de vitória</label>
      <label class="check"><input type="checkbox" id="sg-owned" checked> só minhas cartas</label>
      <button id="btn-suggest" class="primary">Sugerir trocas</button></div><div id="suggest-result"></div></div>` : ""}
  <details class="panel"><summary>Detalhes técnicos</summary>
    <p style="margin-top:12px">${esc(r.summary)}</p>
    <p class="muted">Meta: ${esc(r.overall.meta_source)} · score ${esc(r.overall.objective_mode)} ${(100 * r.overall.score).toFixed(1)} · desvio entre matchups ±${(100 * r.overall.sd).toFixed(1)} p.p. · custo médio ${num(r.avg_elixir)} · ciclo ${num(r.cycle_cost)}</p>
    <div class="table-wrap"><table><tr><th>Arquétipo</th><th>Chance</th><th>Intervalo 90%</th><th>Confiança</th><th>Fonte</th><th>Partidas do deck</th></tr>${tech}</table></div>
    <p class="muted" style="margin-top:12px">Índice de fatores (secundário): ${r.factors.index ?? "—"}</p>
    <div class="table-wrap"><table><tr><th>Fator</th><th>Valor</th><th>Peso</th></tr>${factors}</table></div>
  </details>`;
}

function bindSuggest(baseBody) {
  const btn = $("#btn-suggest");
  if (!btn) return;
  btn.addEventListener("click", async () => {
    btn.disabled = true;
    $("#suggest-result").innerHTML = `<div class="loading"><span class="spinner"></span>Testando trocas…</div>`;
    try {
      const body = { ...baseBody, keep_win_condition: $("#sg-keep").checked, target: $("#sg-target").value || null, top: 5 };
      if ($("#sg-owned").checked) { const col = collectionPayload(); if (col) body.collection = col; } else delete body.collection;
      const r = await api("/api/suggest", body);
      if (!r.swaps.length) { $("#suggest-result").innerHTML = "<p class='muted'>Nenhuma troca melhora o deck segundo o modelo atual.</p>"; return; }
      $("#suggest-result").innerHTML = r.swaps.map((s) => {
        const ds = Object.entries(s.delta_by_archetype).filter(([, v]) => Math.abs(v) >= 0.01).sort((a, b) => b[1] - a[1]);
        const eff = [...ds.slice(0, 2), ...ds.slice(-2).filter(([, v]) => v < 0)]
          .filter((x, i, arr) => arr.indexOf(x) === i)
          .map(([a, v]) => `<span class="tag small ${v > 0 ? "good" : "bad"}">${v > 0 ? "▲" : "▼"} ${esc(state.archName[a] || a)} ${pp(v)}</span>`).join("");
        return `<div class="swap" data-tip="${esc(s.explanation)}">${mini(s.out)}<span class="arrow">→</span>${mini(s.in)}
          <div class="eff">${eff}</div><span class="delta ${s.delta_ev >= 0 ? "up" : "down"}">${pp(s.delta_ev)} p.p.</span></div>`;
      }).join("");
    } catch (e) { $("#suggest-result").innerHTML = ""; toast("Erro: " + e.message); }
    finally { btn.disabled = false; }
  });
}

// ------------------------------------------------------------------ CRIAR
function renderChips() {
  for (const k of ["wincon", "must", "exclude"]) {
    const el = $("#chips-" + k);
    el.innerHTML = state.build[k].map((c) => tile(state.byKey[c], { extraTip: "Clique para remover", showLevel: false })).join("")
      + `<button class="add-tile" data-mode="${k}" data-tip="Adicionar">+</button>`;
    $$(".ctile", el).forEach((t) => t.addEventListener("click", () => { state.build[k] = state.build[k].filter((x) => x !== t.dataset.key); renderChips(); }));
    $(".add-tile", el).addEventListener("click", () => openPicker(k));
  }
}
const cellColor = (p) => {
  const t = Math.max(-1, Math.min(1, (num(p) - 0.5) / 0.15));
  return `color-mix(in srgb, ${t >= 0 ? "var(--pos)" : "var(--neg)"} ${Math.round(Math.abs(t) * 100)}%, var(--mid))`;
};
$("#btn-build").addEventListener("click", async () => {
  const btn = $("#btn-build");
  btn.disabled = true;
  $("#build-result").innerHTML = loading("Buscando as melhores combinações…");
  try {
    const body = {
      must_include: state.build.must, exclude: state.build.exclude, win_conditions: state.build.wincon,
      style: $("#build-style").value || null,
      max_avg_elixir: parseFloat($("#build-max").value) || null, min_avg_elixir: parseFloat($("#build-min").value) || null,
      top_k: parseInt($("#build-top").value) || 5,
    };
    if ($("#build-use-col").checked) {
      body.collection = collectionPayload();
      if (!body.collection) toast("Sem coleção: usando todas as cartas. Importe sua conta para considerar níveis.");
    }
    const r = await api("/api/build", body);
    const order = state.archetypes.map((a) => a.key);
    $("#build-result").innerHTML = r.decks.map((d) => {
      const a = d.analysis, by = Object.fromEntries(a.matchups.map((m) => [m.archetype, m]));
      const worst = a.matchups.reduce((x, y) => (y.win_prob < x.win_prob ? y : x));
      const strip = order.map((k) => `<i style="background:${cellColor(by[k].win_prob)}" data-tip="${esc(by[k].name)}: ${pct(by[k].win_prob, 1)}"></i>`).join("");
      return `<div class="panel deck-result">
        <div class="rank">#${num(d.rank)}</div>
        <div><div class="muted" style="margin-bottom:6px"><b style="color:var(--text)">${esc(a.archetype.primary_pt)}</b> · 💧 ${num(a.avg_elixir)}${a.levels.provided ? ` · nível ${a.levels.effective_gap >= 0 ? "+" : ""}${num(a.levels.effective_gap)}` : ""}</div>
          <div class="slots">${a.deck.map((k) => tile(state.byKey[k], { evoArt: true })).join("")}</div>
          <div class="strip">${strip}</div><div class="strip-legend"><span>matchups (passe o mouse)</span></div></div>
        <div class="side"><b>${pct(a.overall.ev, 1)}</b><span class="muted">vs meta · pior ${pct(worst.win_prob)}</span>
          <button class="use-deck" data-deck="${esc(JSON.stringify(a.deck))}">Ver análise</button></div>
      </div>`;
    }).join("") || "<div class='panel muted'>Nenhum deck encontrado com essas restrições.</div>";
    $$(".use-deck").forEach((b) => b.addEventListener("click", () => {
      state.deck = JSON.parse(b.dataset.deck); store(DECK_KEY, state.deck);
      showTab("analyze"); analyzeDeck(); window.scrollTo({ top: 0, behavior: "smooth" });
    }));
  } catch (e) { $("#build-result").innerHTML = ""; toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
});

// ------------------------------------------------------------------ COLEÇÃO
function renderCollection() {
  const col = loadCollection();
  $("#col-ref").value = col.reference_level ?? "";
  const q = $("#col-filter").value;
  const ownedOnly = $("#col-owned").checked;
  const list = state.cards.filter((c) => matches(c, q) && (!ownedOnly || c.key in col.cards))
    .sort((a, b) => a.elixir - b.elixir || a.name_pt.localeCompare(b.name_pt));
  $("#col-count").textContent = `${Object.keys(col.cards).length} cartas · ${col.evolutions.length} evoluções`;
  $("#col-table").innerHTML = `<div class="col-grid">${list.map((c) => `<div class="col-card ${c.key in col.cards ? "owned" : ""}">
      ${tile(c, { evoArt: true, showLevel: false })}
      <div class="col-ctrl"><input type="number" min="1" max="16" data-key="${esc(c.key)}" value="${col.cards[c.key] ?? ""}" placeholder="nív." aria-label="Nível de ${esc(c.name_pt)}">
      ${c.evo ? `<button class="evo-toggle ${col.evolutions.includes(c.key) ? "on" : ""}" data-evo="${esc(c.key)}" data-tip="Evolução desbloqueada">EVO</button>` : ""}</div>
    </div>`).join("")}</div>`;
  $$("#col-table input[type=number]").forEach((inp) => inp.addEventListener("change", () => {
    const c = loadCollection();
    const v = parseFloat(inp.value);
    if (isNaN(v)) delete c.cards[inp.dataset.key]; else c.cards[inp.dataset.key] = Math.max(1, Math.min(16, v));
    saveCollection(c); renderCollection();
  }));
  $$("#col-table .evo-toggle").forEach((b) => b.addEventListener("click", () => {
    const c = loadCollection();
    const k = b.dataset.evo;
    c.evolutions = c.evolutions.includes(k) ? c.evolutions.filter((x) => x !== k) : [...c.evolutions, k];
    if (!(k in c.cards)) c.cards[k] = c.reference_level || refLevel(c) || 14;
    saveCollection(c); renderCollection();
  }));
}
$("#col-filter").addEventListener("input", renderCollection);
$("#col-owned").addEventListener("change", renderCollection);
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
  saveCollection(emptyCol()); store(PLAYER_KEY, null); location.reload();
});
$("#btn-export").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify(loadCollection(), null, 1)], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob); a.download = "colecao.json"; a.click();
});
$("#btn-import").addEventListener("click", () => {
  const txt = prompt("Cole o JSON da coleção:");
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
    const d = s.data, c = s.collector || {};
    const v = d.validation;
    const kpi = (k, val, sub, tip = "") => `<div class="kpi" ${tip ? `data-tip="${esc(tip)}"` : ""}><div class="k">${esc(k)}</div><div class="v">${val}</div><div class="s">${esc(sub)}</div></div>`;
    $("#data-status").innerHTML = `<div class="kpis">
      ${kpi("Fonte das estimativas", d.model ? (d.warning ? "Sintética" : "Dados reais") : "Heurística", d.model ? "modelo treinado" : "sem partidas suficientes", d.warning || d.note || "")}
      ${kpi("Partidas no modelo", d.model ? num(d.battles).toLocaleString("pt-BR") : "0", d.model ? `${String(d.first || "").slice(5, 10)} → ${String(d.last || "").slice(5, 10)}` : "—")}
      ${kpi("Acurácia (recentes)", v ? pct(v.accuracy_model, 1) : "—", v ? `${num(v.holdout)} partidas de teste` : "sem validação", v ? `log-loss ${num(v.logloss_model).toFixed(4)} vs ${num(v.logloss_baseline).toFixed(4)} (base)` : "")}
      ${kpi("Treinado em", d.model ? esc(String(d.trained_at || "").slice(0, 16).replace("T", " ")) : "—", d.model ? `janela ${num(d.days)} dias` : "")}
    </div>`;
    $("#collector-pill").innerHTML = !c.enabled ? `<span class="tag neutral">desativada</span>`
      : c.running ? `<span class="tag neutral"><span class="spinner"></span>coletando</span>` : `<span class="tag good">✓ ativa · a cada ${num(c.interval_hours)} h</span>`;
    $("#collector-status").innerHTML = !c.enabled
      ? `<p class="muted">O servidor precisa da chave da API (<code>CR_API_TOKEN</code>) para coletar partidas reais.</p>`
      : `<p class="muted">${c.last_run ? `Última coleta: ${esc(c.last_run.replace("T", " "))}` : "Primeira coleta em andamento."}
         ${c.last_result ? ` · ${num(c.last_result.new_battles)} partidas novas · ${num(c.last_result.total)} no banco` : ""}</p>
         ${c.last_error ? `<span class="tag bad">! ${esc(c.last_error)}</span>` : ""}
         ${c.log?.length ? `<details class="picker-box"><summary>Registro</summary><div class="log">${c.log.map(esc).join("\n")}</div></details>` : ""}`;
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
    if (d.model && !d.warning) { pill.classList.add("real"); pill.textContent = `● dados reais · ${num(d.battles).toLocaleString("pt-BR")} partidas`; }
    else if (d.model) { pill.classList.add("synthetic"); pill.textContent = "● dados de demonstração"; }
    else pill.textContent = s.collector?.running ? "● coletando partidas…" : "● modo heurístico";
    pill.dataset.tip = d.warning || d.note || "Estimativas baseadas em partidas reais.";
  } catch { /* ignora */ }
}

// ------------------------------------------------------------------ init
(async function init() {
  try {
    state.cards = await api("/api/cards");
    state.byKey = Object.fromEntries(state.cards.map((c) => [c.key, c]));
    state.archetypes = await api("/api/archetypes");
    state.archName = Object.fromEntries(state.archetypes.map((a) => [a.key, a.name]));
    $("#build-style").innerHTML += state.archetypes.map((a) => `<option value="${esc(a.key)}">${esc(a.name)}</option>`).join("");
    const saved = load(DECK_KEY, null);
    state.deck = Array.isArray(saved) && saved.length && saved.every((k) => state.byKey[k])
      ? saved : ["Hog Rider", "Musketeer", "Ice Golem", "Ice Spirit", "Skeletons", "Cannon", "Fireball", "The Log"];
    if (collectionPayload()) $("#analyze-use-col").checked = true;
    bindAccountInput(); renderAccount(); renderSlots(); renderChips(); refreshPill();
    setInterval(refreshPill, 60000);
  } catch (e) { toast("Falha ao carregar: " + e.message, 8000); }
})();
