"use strict";
// Interface web do Clash Deck Lab (sem dependências externas). Todo texto dinâmico passa por esc().

const $ = (s, el = document) => el.querySelector(s);
const $$ = (s, el = document) => [...el.querySelectorAll(s)];
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const num = (v) => (typeof v === "number" && isFinite(v) ? v : 0);
const pct = (p, d = 0) => (100 * num(p)).toFixed(d) + "%";
const pp = (x) => (x >= 0 ? "+" : "−") + Math.abs(100 * num(x)).toFixed(1);
const norm = (s) => s.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9]/g, "");

const state = { cards: [], byKey: {}, archetypes: [], archName: {}, deck: Array(8).fill(null), forms: Array(8).fill("normal"),
  contrib: null, meta: null, metaSort: "games",
  build: { wincon: [], must: [], exclude: [] } };
const COL_KEY = "crlab.collection.v1", PLAYER_KEY = "crlab.player.v1", DECK_KEY = "crlab.deck.v2";
// Posições especiais do jogo: 1ª Evo, 2ª Herói, 3ª Evo ou Herói (todas aceitam carta normal).
const SLOT_FORMS = [["normal", "evo"], ["normal", "hero"], ["normal", "evo", "hero"]];
const SLOT_LABEL = ["Evolução", "Herói", "Evo ou Herói"];
const SLOT_SHORT = ["Evo", "Herói", "Evo/Herói"];
const FORM_SHORT = { normal: "—", evo: "Evo", hero: "Herói" };
const FORM_PT = { normal: "Normal", evo: "Evo", hero: "Herói" };
const deckKeys = () => state.deck.filter(Boolean);
function saveDeck() { store(DECK_KEY, { deck: state.deck, forms: state.forms }); }
function setDeck(keys, forms = null) {
  state.deck = Array(8).fill(null);
  state.forms = Array(8).fill("normal");
  keys.slice(0, 8).forEach((k, i) => { state.deck[i] = k; if (forms) state.forms[i] = forms[i] || "normal"; });
  if (!forms) autoForms();
  saveDeck();
}
// Pode usar a forma? (a carta precisa ter a forma; com coleção ativa, precisa estar desbloqueada)
function formAvailable(key, form) {
  if (form === "normal") return true;
  const c = state.byKey[key];
  if (!c || (form === "evo" && !c.evo) || (form === "hero" && !c.hero)) return false;
  if (!$("#analyze-use-col")?.checked || !hasCollection()) return true;
  const col = loadCollection();
  return form === "evo" ? col.evolutions.includes(key) : (col.heroes || []).includes(key);
}
// Preenche as posições especiais com a melhor forma disponível de cada carta (sem trocar cartas de lugar).
function autoForms() {
  state.forms = state.forms.map((f, i) => {
    const k = state.deck[i];
    if (!k || i > 2) return "normal";
    if (f !== "normal" && SLOT_FORMS[i].includes(f) && formAvailable(k, f)) return f;
    const pref = i === 0 ? ["evo"] : i === 1 ? ["hero"] : ["evo", "hero"];
    return pref.find((x) => formAvailable(k, x)) || "normal";
  });
}

// ------------------------------------------------------------------ ícones (SVG em linha, sem emojis)
const ICONS = {
  shield: '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>',
  trash: '<path d="M3 6h18"/><path d="M19 6l-1 14H6L5 6"/><path d="M8 6V4h8v2"/>',
  clipboard: '<rect x="8" y="2" width="8" height="4" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/>',
  external: '<path d="M15 3h6v6"/><path d="M10 14 21 3"/><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
  copy: '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  crown: '<path d="m2 7 5 5 5-8 5 8 5-5-2 12H4z"/>',
  check: '<path d="M20 6 9 17l-5-5"/>',
  ban: '<circle cx="12" cy="12" r="10"/><path d="m4.9 4.9 14.2 14.2"/>',
  sparkles: '<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9z"/><path d="M19 16v5M16.5 18.5h5"/>',
  drop: '<path d="M12 2.7s6 6.3 6 11.3a6 6 0 0 1-12 0c0-5 6-11.3 6-11.3z"/>',
  cycle: '<path d="M3 12a9 9 0 0 1 15-6.7L21 8"/><path d="M21 3v5h-5"/><path d="M21 12a9 9 0 0 1-15 6.7L3 16"/><path d="M8 16H3v5"/>',
  layers: '<path d="m12 2 10 5-10 5L2 7z"/><path d="m2 17 10 5 10-5"/><path d="m2 12 10 5 10-5"/>',
  level: '<path d="M4 20V14M10 20V9M16 20V4M2 20h20"/>',
  air: '<path d="M2 16l20-8-6 14-3-6z"/><path d="m13 16-4 4"/>',
  tank: '<circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.5"/>',
  swarm: '<circle cx="6" cy="7" r="2.5"/><circle cx="18" cy="7" r="2.5"/><circle cx="12" cy="13" r="2.5"/><circle cx="6" cy="19" r="2.5"/><circle cx="18" cy="19" r="2.5"/>',
  castle: '<path d="M3 21V8l3 2V6l3 2V4h6v4l3-2v4l3-2v13z"/><path d="M10 21v-5h4v5"/>',
  swords: '<path d="M14.5 17.5 3 6V3h3l11.5 11.5"/><path d="m13 19 6-6"/><path d="m16 16 4 4"/><path d="m19 21 2-2"/>',
  bolt: '<path d="M13 2 3 14h9l-1 8 10-12h-9z"/>',
  alert: '<path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/>',
  arrow: '<path d="M5 12h14M12 5l7 7-7 7"/>',
  up: '<path d="m18 15-6-6-6 6"/>', down: '<path d="m6 9 6 6 6-6"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/>',
  trophy: '<path d="M8 21h8M12 17v4M7 4h10v5a5 5 0 0 1-10 0z"/><path d="M17 5h3v2a3 3 0 0 1-3 3M7 5H4v2a3 3 0 0 0 3 3"/>',
  x: '<path d="M18 6 6 18M6 6l12 12"/>',
};
const icon = (n) => `<svg class="i" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[n] || ""}</svg>`;
function hydrateIcons(root = document) { $$("[data-icon]", root).forEach((el) => { el.innerHTML = icon(el.dataset.icon); }); }

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
  ["air", "Defesa aérea", ["air_defense", "air_swarm"]],
  ["tank", "Contra tanques", ["tank_killing", "defense_volume"]],
  ["swarm", "Contra enxames", ["ground_swarm", "anti_graveyard"]],
  ["castle", "Contra Corredor/RG", ["building_def"]],
  ["cycle", "Ciclo e custo", ["cycle", "elixir_eff", "cheap_answers"]],
  ["swords", "Ataque", ["pressure", "siege_breaking", "counterattack"]],
  ["bolt", "Feitiços", ["spells", "reset"]],
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
const emptyCol = () => ({ cards: {}, evolutions: [], heroes: [], reference_level: null });
const loadCollection = () => ({ ...emptyCol(), ...load(COL_KEY, emptyCol()) });
const saveCollection = (c) => store(COL_KEY, c);
const hasCollection = () => Object.keys(loadCollection().cards).length > 0;
function collectionPayload() {
  const c = loadCollection();
  if (!Object.keys(c.cards).length) return null;
  return { cards: c.cards, evolutions: c.evolutions, heroes: c.heroes || [], reference_level: c.reference_level || null };
}
function refLevel(col) {
  const v = Object.values(col.cards).filter((x) => typeof x === "number").sort((a, b) => a - b);
  return v.length ? v[Math.floor(0.75 * (v.length - 1))] : null;
}
function deckLevel(keys) {
  const col = loadCollection();
  const v = keys.map((k) => col.cards[k]).filter((x) => typeof x === "number");
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null;
}
const loading = (msg) => `<div class="panel loading"><span class="spinner"></span>${esc(msg)}</div>`;
const options = (vals, sel, fmt = (v) => v) => vals.map((v) => `<option value="${esc(v)}" ${String(v) === String(sel) ? "selected" : ""}>${esc(fmt(v))}</option>`).join("");

// Tooltip único: qualquer elemento com data-tip (texto puro, quebras de linha preservadas)
document.addEventListener("mouseover", (e) => {
  const el = e.target.closest("[data-tip]");
  const tip = $("#tip");
  if (!el) { tip.style.display = "none"; return; }
  tip.textContent = el.dataset.tip;
  tip.style.display = "block";
});
document.addEventListener("mousemove", (e) => {
  const t = $("#tip");
  if (t.style.display !== "block") return;
  const x = Math.min(e.clientX + 14, window.innerWidth - t.offsetWidth - 8);
  const y = e.clientY + 16 + t.offsetHeight > window.innerHeight ? e.clientY - t.offsetHeight - 10 : e.clientY + 16;
  t.style.left = x + "px"; t.style.top = y + "px";
});

// ------------------------------------------------------------------ copiar deck para o jogo
// Link oficial do jogo: abre o Clash Royale com o deck pronto para copiar. Cartas com evolução
// desbloqueada vão primeiro (posições de evolução).
function deckLink(keys) {
  // keys já vêm na ordem das posições (1ª Evo, 2ª Herói, 3ª Evo/Herói); o jogo aplica a forma
  // automaticamente se a carta estiver desbloqueada na conta.
  const ids = keys.map((k) => state.byKey[k]?.id);
  if (ids.length !== 8 || ids.some((x) => !x)) return null;
  return `https://link.clashroyale.com/en/?clashroyale://copyDeck?deck=${ids.join(";")}&l=Royals&tt=159000000`;
}
function openInGame(keys) {
  const url = deckLink(keys);
  if (!url) return toast(keys.length !== 8 ? "O deck precisa de 8 cartas." : "Uma das cartas ainda não tem ID oficial para o link.");
  window.open(url, "_blank", "noopener");
}
async function copyLink(keys) {
  const url = deckLink(keys);
  if (!url) return toast("Não foi possível gerar o link deste deck.");
  try { await navigator.clipboard.writeText(url); toast("Link copiado. Abra no celular para copiar o deck no jogo."); }
  catch { prompt("Copie o link do deck:", url); }
}
const deckButtons = (keys, analyze = true, forms = null) => `<div class="btns">
  ${analyze ? `<button class="sm act-analyze" data-deck="${esc(JSON.stringify(keys))}" ${forms ? `data-forms="${esc(JSON.stringify(forms))}"` : ""}>Analisar</button>` : ""}
  <button class="sm act-game" data-deck="${esc(JSON.stringify(keys))}" data-tip="Abrir no Clash Royale e copiar o deck">${icon("external")} Jogo</button>
  <button class="sm act-link" data-deck="${esc(JSON.stringify(keys))}" data-tip="Copiar link do deck">${icon("copy")}</button></div>`;
document.addEventListener("click", (e) => {
  const b = e.target.closest(".act-analyze, .act-game, .act-link");
  if (!b) return;
  const keys = JSON.parse(b.dataset.deck);
  if (b.classList.contains("act-game")) return openInGame(keys);
  if (b.classList.contains("act-link")) return copyLink(keys);
  setDeck(keys, b.dataset.forms ? JSON.parse(b.dataset.forms) : null); deckChanged();
  showTab("analyze"); analyzeDeck(!b.dataset.forms); window.scrollTo({ top: 0, behavior: "smooth" });
});

// ------------------------------------------------------------------ navegação
function showTab(name) {
  $$("nav button").forEach((x) => x.classList.toggle("active", x.dataset.tab === name));
  $$(".tab").forEach((t) => t.classList.toggle("active", t.id === "tab-" + name));
  if (name === "collection") renderCollection();
  if (name === "data") renderStatus();
  if (name === "meta") renderMeta();
  if (name === "analyze") renderSlots();
}
$$("nav button").forEach((b) => b.addEventListener("click", () => showTab(b.dataset.tab)));

// ------------------------------------------------------------------ cartas
const imgUrl = (c, size, form = "normal") => `/img/card/${size}/${encodeURIComponent(c.slug)}${form === "evo" || form === true ? "-ev1" : form === "hero" ? "-hero" : ""}.png`;
// Imagem quebrada: tenta a versão sem evolução; se falhar, mostra a inicial da carta.
document.addEventListener("error", (e) => {
  const img = e.target;
  if (!(img instanceof HTMLImageElement)) return;
  if (img.dataset.fallback) { img.src = img.dataset.fallback; delete img.dataset.fallback; return; }
  img.closest(".ctile, .mini")?.classList.add("noimg");
}, true);

function tile(c, { size = "s", inDeck = false, extraTip = "", form = "normal", showLevel = true } = {}) {
  if (!c) return "";
  const col = loadCollection();
  const lvl = col.cards[c.key];
  const ref = col.reference_level || refLevel(col);
  let badge = "";
  if (form === "evo") badge = `<span class="badge evo">EVO</span>`;
  else if (form === "hero") badge = `<span class="badge hero">HERÓI</span>`;
  else if (showLevel && lvl != null) badge = `<span class="badge ${ref && lvl < ref - 0.5 ? "low" : ""}">${num(lvl)}</span>`;
  const fb = form !== "normal" ? ` data-fallback="${imgUrl(c, size)}"` : "";
  const tip = `${c.name_pt}  ·  ${c.elixir} de elixir${lvl != null ? "  ·  nível " + lvl : ""}${extraTip ? "\n" + extraTip : ""}`;
  return `<div class="ctile r-${esc(c.rarity)} ${inDeck ? "in" : ""}" data-key="${esc(c.key)}" data-tip="${esc(tip)}">
    <div class="art" data-initial="${esc(c.name_pt.slice(0, 1))}"><img src="${imgUrl(c, size, form)}"${fb} alt="${esc(c.name_pt)}" loading="lazy"></div>
    <span class="drop"><span>${num(c.elixir)}</span></span>${badge}<span class="nm">${esc(c.name_pt)}</span></div>`;
}
function mini(k, form = "normal") {
  const c = state.byKey[k];
  if (!c) return esc(k);
  const fb = form !== "normal" ? ` data-fallback="${imgUrl(c, "s")}"` : "";
  const suffix = form === "evo" ? " (Evo)" : form === "hero" ? " (Herói)" : "";
  return `<span class="mini"><img src="${imgUrl(c, "s", form)}"${fb} alt="" loading="lazy">${esc(c.name_pt + suffix)}</span>`;
}
// slots = [{card, form}] (ordem das posições) ou lista simples de cartas
const deckTiles = (slots) => `<div class="slots">${slots.map((x) => typeof x === "string"
  ? tile(state.byKey[x]) : tile(state.byKey[x.card], { form: x.form })).join("")}</div>`;
const slotKeys = (slots) => slots.map((x) => (typeof x === "string" ? x : x.card));
const slotForms = (slots) => slots.map((x) => (typeof x === "string" ? "normal" : x.form));
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
  const hasCol = hasCollection();
  $("#m-owned").checked = hasCol && (mode === "deck" ? $("#analyze-use-col").checked : $("#build-use-col").checked);
  $("#m-owned").closest(".switch").style.display = hasCol ? "" : "none";
  $("#modal").hidden = false;
  renderModal();
  setTimeout(() => $("#m-search").focus(), 30);
}
function closePicker() {
  $("#modal").hidden = true;
  if (picker.mode === "deck") renderSlots(); else renderChips();
}
const pickerSelected = () => (picker.mode === "deck" ? deckKeys() : state.build[picker.mode]);
function renderModal() {
  const col = loadCollection();
  const sel = pickerSelected();
  let list = state.cards;
  if (picker.mode === "wincon") list = list.filter((c) => c.tags.includes("wc") || c.tags.includes("wc2"));
  if ($("#m-owned").checked) list = list.filter((c) => c.key in col.cards);
  if (picker.elixir !== "all") list = list.filter((c) => (picker.elixir === "6" ? c.elixir >= 6 : c.elixir === +picker.elixir));
  if (picker.type !== "all") list = list.filter((c) => c.type === picker.type);
  list = list.filter((c) => matches(c, $("#m-search").value)).sort((a, b) => a.elixir - b.elixir || a.name_pt.localeCompare(b.name_pt));
  const slotTxt = picker.slot != null && picker.slot < 3 ? ` · posição ${picker.slot + 1} (${SLOT_LABEL[picker.slot]})` : "";
  $("#modal-title").textContent = picker.mode === "deck"
    ? (picker.slot != null && state.deck[picker.slot] ? `Trocar ${state.byKey[state.deck[picker.slot]].name_pt}${slotTxt}` : `Montar deck · ${deckKeys().length}/8${slotTxt}`)
    : MODE_TITLE[picker.mode];
  $("#modal-remove").hidden = !(picker.mode === "deck" && picker.slot != null && state.deck[picker.slot]);
  $("#m-grid").innerHTML = list.map((c) => tile(c, { inDeck: sel.includes(c.key) })).join("") || "<p class='muted'>Nenhuma carta com esses filtros.</p>";
  $$("#m-grid .ctile").forEach((el) => el.addEventListener("click", () => pickCard(el.dataset.key)));
}
function pickCard(k) {
  if (picker.mode === "deck") {
    const i = state.deck.indexOf(k);
    if (picker.slot != null) {
      // posição escolhida: coloca (ou troca de lugar, se a carta já está no deck)
      if (i >= 0) {
        [state.deck[i], state.deck[picker.slot]] = [state.deck[picker.slot], state.deck[i]];
        state.forms[i] = "normal";
      } else state.deck[picker.slot] = k;
      state.forms[picker.slot] = "normal";
      autoForms(); saveDeck(); deckChanged(); closePicker(); return;
    }
    if (i >= 0) { state.deck[i] = null; state.forms[i] = "normal"; }
    else {
      const free = state.deck.indexOf(null);
      if (free < 0) return toast("Deck completo. Remova uma carta primeiro.");
      state.deck[free] = k;
    }
    autoForms(); saveDeck(); deckChanged(); renderSlots();
    if (deckKeys().length === 8 && i < 0) { closePicker(); return; }
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
    el.innerHTML = items.map(([v, label]) => `<button data-v="${v}" class="${v === "all" ? "on" : ""}">${label}</button>`).join("");
    $$("button", el).forEach((b) => b.addEventListener("click", () => {
      picker[key] = b.dataset.v;
      $$("button", el).forEach((x) => x.classList.toggle("on", x === b));
      renderModal();
    }));
  };
  seg($("#m-elixir"), [["all", `${icon("drop")} Todos`], ["1", "1"], ["2", "2"], ["3", "3"], ["4", "4"], ["5", "5"], ["6", "6+"]], "elixir");
  seg($("#m-type"), [["all", "Todas"], ["troop", "Tropas"], ["spell", "Feitiços"], ["building", "Construções"]], "type");
  $("#m-search").addEventListener("input", renderModal);
  $("#m-owned").addEventListener("change", renderModal);
  $("#modal-done").addEventListener("click", closePicker);
  $("#modal-remove").addEventListener("click", () => {
    state.deck[picker.slot] = null; state.forms[picker.slot] = "normal";
    saveDeck(); deckChanged(); closePicker();
  });
  $("#modal").addEventListener("click", (e) => { if (e.target.id === "modal") closePicker(); });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape" && !$("#modal").hidden) closePicker(); });
})();

// ------------------------------------------------------------------ conta (tag)
function renderAccount() {
  const p = load(PLAYER_KEY, null);
  if (!p) return;
  $("#account").innerHTML = `<div class="player-chip" data-tip="${esc(`${p.tag}\n${num(p.n_cards)} cartas · ${num(p.n_evos)} evoluções · ${num(p.n_heroes)} heróis${p.arena ? "\n" + p.arena : ""}`)}">
    ${icon("user")} <b>${esc(p.name)}</b>${p.trophies != null ? `<span class="tr">${icon("trophy")} ${num(p.trophies)}</span>` : ""}<button id="btn-switch">Atualizar</button></div>`;
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
    col.heroes = (r.heroes || []).filter((k) => state.byKey[k]);
    saveCollection(col);
    store(PLAYER_KEY, { ...r.player, n_cards: Object.keys(col.cards).length, n_evos: col.evolutions.length, n_heroes: col.heroes.length });
    $("#analyze-use-col").checked = true;
    const deck = (r.current_deck || []).filter((k) => state.byKey[k]);
    if (deck.length === 8) { setDeck(deck); deckChanged(); }
    $("#analyze-use-col").checked = true;
    renderAccount(); renderSlots(); renderChips();
    if ($("#tab-collection").classList.contains("active")) renderCollection();
    toast(`Conta importada: ${Object.keys(col.cards).length} cartas${deck.length === 8 ? " e deck atual" : ""}.`);
  } catch (e) { toast("Erro: " + e.message, 6000); }
}

// ------------------------------------------------------------------ ANALISAR
function deckChanged() {
  state.contrib = null;
  $("#result-left").innerHTML = "";
  $("#result-bottom").innerHTML = "";
  renderSidebarMeta();
}
function renderSlots() {
  const slots = $("#deck-slots");
  slots.innerHTML = "";
  for (let i = 0; i < 8; i++) {
    const key = state.deck[i];
    const c = key && state.byKey[key];
    const form = state.forms[i] || "normal";
    const info = c && state.contrib ? state.contrib[c.key] : null;
    const d = document.createElement("div");
    d.className = "cell" + (i < 3 ? " special" : "");
    const head = i < 3 ? `<div class="slot-label"><span class="l">${SLOT_LABEL[i]}</span><span class="s">${SLOT_SHORT[i]}</span></div>`
      : `<div class="slot-label blank"></div>`;
    d.innerHTML = head + (c ? tile(c, { size: "l", form, extraTip: (info ? info.tip + "\n" : "") + "Toque para trocar" })
      : `<div class="ctile empty" data-tip="Adicionar carta"><div class="art">+</div><span class="nm">&nbsp;</span></div>`);
    if (c && i < 3) {
      const opts = SLOT_FORMS[i].filter((f) => f === "normal" || (f === "evo" ? c.evo : c.hero));
      if (opts.length > 1) {
        d.insertAdjacentHTML("beforeend", `<div class="form-pick">${opts.map((f) => {
          const ok = formAvailable(c.key, f);
          return `<button data-f="${f}" class="${f === form ? "on" : ""} ${f}" ${ok ? "" : "disabled"}
            data-tip="${esc(ok ? `Usar como ${FORM_PT[f]}` : `Você não tem ${f === "evo" ? "a Evolução" : "o Herói"} desta carta`)}"><span class="l">${FORM_PT[f]}</span><span class="s">${FORM_SHORT[f]}</span></button>`;
        }).join("")}</div>`);
        $$(".form-pick button", d).forEach((b) => b.addEventListener("click", (e) => {
          e.stopPropagation();
          state.forms[i] = b.dataset.f; saveDeck(); deckChanged(); renderSlots();
        }));
      }
    }
    if (info) {
      d.insertAdjacentHTML("beforeend", `<div class="contrib" data-tip="Contribuição para o deck: ${pp(info.v)} p.p. de chance de vitória">
        <i style="width:${info.w.toFixed(0)}%;${info.v < 0 ? "background:var(--neg)" : ""}"></i></div><div class="contrib-v">${pp(info.v)}</div>`);
    }
    d.querySelector(".ctile").addEventListener("click", () => openPicker("deck", i));
    slots.appendChild(d);
  }
  const keys = deckKeys();
  const els = keys.map((k) => state.byKey[k]?.elixir || 0);
  const avg = els.length ? els.reduce((a, b) => a + b, 0) / els.length : 0;
  const cyc = [...els].sort((a, b) => a - b).slice(0, 4).reduce((a, b) => a + b, 0);
  const lvl = deckLevel(keys);
  $("#deck-meta").innerHTML = `<span class="stat-chip" data-tip="Custo médio de elixir">${icon("drop")} <b>${avg.toFixed(1)}</b> elixir</span>
    <span class="stat-chip" data-tip="Soma das 4 cartas mais baratas (velocidade de ciclo)">${icon("cycle")} ciclo <b>${els.length >= 4 ? cyc : "—"}</b></span>
    ${lvl != null ? `<span class="stat-chip" data-tip="Nível médio das cartas do deck na sua coleção">${icon("level")} nível <b>${lvl.toFixed(1)}</b></span>` : ""}
    <span class="stat-chip">${icon("layers")} <b>${keys.length}</b>/8</span>`;
}
$("#btn-clear").addEventListener("click", () => { setDeck([]); deckChanged(); renderSlots(); openPicker("deck"); });
$("#btn-paste").addEventListener("click", () => {
  const txt = prompt("Cole as 8 cartas separadas por vírgula (português ou inglês):");
  if (!txt) return;
  const found = [], missing = [];
  for (const raw of txt.split(/[,;\n]/).map((s) => s.trim()).filter(Boolean)) {
    const c = state.cards.find((x) => norm(x.key) === norm(raw) || norm(x.name_pt) === norm(raw));
    if (c) found.push(c.key); else missing.push(raw);
  }
  setDeck([...new Set(found)].slice(0, 8)); deckChanged(); renderSlots();
  if (missing.length) toast("Não reconhecidas: " + missing.join(", "));
});
$("#btn-copy-deck").addEventListener("click", () => openInGame(state.deck.filter(Boolean)));
$("#analyze-use-col").addEventListener("change", () => { autoForms(); saveDeck(); deckChanged(); renderSlots(); });
$("#btn-analyze").addEventListener("click", () => analyzeDeck());

// auto = true: o servidor escolhe as melhores Evos/Heróis disponíveis e reorganiza as posições.
async function analyzeDeck(auto = false) {
  if (deckKeys().length !== 8) return toast("O deck precisa de 8 cartas.");
  const btn = $("#btn-analyze");
  btn.disabled = true;
  $("#result-right").innerHTML = loading("Analisando…");
  try {
    const body = { deck: [...state.deck], forms: auto ? null : [...state.forms] };
    if ($("#analyze-use-col").checked) { const col = collectionPayload(); if (col) body.collection = col; }
    const r = await api("/api/analyze", body);
    setDeck(slotKeys(r.slots), slotForms(r.slots));
    body.deck = [...state.deck]; body.forms = [...state.forms];
    (r.warnings || []).forEach((w) => toast(w, 5000));
    const maxC = Math.max(0.01, ...r.cards.map((c) => Math.abs(num(c.fit.ev_contribution))));
    state.contrib = Object.fromEntries(r.cards.map((c) => [c.card, {
      v: num(c.fit.ev_contribution), w: (Math.abs(num(c.fit.ev_contribution)) / maxC) * 100,
      tip: [
        `Força teórica: ${num(c.theoretical.tier)}/5`,
        c.at_level.level != null ? `Seu nível: ${c.at_level.level} (${c.at_level.gap >= 0 ? "+" : ""}${c.at_level.gap} vs referência; atributos ×${c.at_level.stat_factor})` : null,
        c.meta ? `No meta: ${pct(c.meta.winrate_shrunk, 1)} de vitórias em ${c.meta.games} partidas` : null,
        `Contribuição: ${pp(c.fit.ev_contribution)} p.p.`,
      ].filter(Boolean).join("\n"),
    }]));
    renderSlots();
    renderAnalysis(r, body);
  } catch (e) { $("#result-right").innerHTML = ""; renderSidebarMeta(); toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
}

function ring(p) {
  const r = 52, c = 2 * Math.PI * r, v = Math.max(0, Math.min(1, num(p)));
  return `<div class="ring" data-tip="Chance média de vitória contra o meta (ponderada pela frequência de cada arquétipo)">
    <svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="${r}" fill="none" stroke="var(--meter-bg)" stroke-width="11"/>
    <circle cx="60" cy="60" r="${r}" fill="none" stroke="${v >= 0.5 ? "var(--pos)" : "var(--neg)"}" stroke-width="11" stroke-linecap="round" stroke-dasharray="${(v * c).toFixed(1)} ${c.toFixed(1)}"/></svg>
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
    return `<div class="meter" data-tip="${esc(tip)}"><span class="ic">${icon(ic)}</span><span>${esc(name)}</span>
      <div class="track"><div class="fill" style="width:${(100 * v).toFixed(0)}%"></div><div class="base" style="left:${(100 * b).toFixed(0)}%"></div></div>
      <span class="n">${(100 * v).toFixed(0)}</span></div>`;
  }).join("") + `<div class="legend" style="margin-top:10px"><span><i style="background:var(--meter)"></i>seu deck</span><span><i style="background:var(--text-2);width:2px"></i>média de decks conhecidos</span></div>`;
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

function renderAnalysis(r, body) {
  const strengths = r.capabilities.filter((c) => c.rating === "forte").sort((a, b) => (b.value - b.baseline) - (a.value - a.baseline)).slice(0, 3);
  const seen = new Set();
  const weak = r.vulnerabilities.filter((v) => WEAK[v.dimension] && !seen.has(v.dimension) && seen.add(v.dimension)).slice(0, 3);
  const tags = [
    ...strengths.map((c) => `<span class="tag good" data-tip="${esc(c.name)}: ${(100 * c.value).toFixed(0)} (média ${(100 * c.baseline).toFixed(0)})">${icon("check")} ${esc(STRONG[c.key] || c.name)}</span>`),
    ...weak.map((v) => `<span class="tag bad" data-tip="${esc(v.message)}">${icon("alert")} ${esc(WEAK[v.dimension])}</span>`),
  ];
  const lv = r.levels;
  if (lv.provided && lv.not_owned.length) tags.push(`<span class="tag bad" data-tip="${esc("Você não possui: " + lv.not_owned.map((k) => state.byKey[k]?.name_pt || k).join(", "))}">${icon("x")} ${lv.not_owned.length} carta(s) que você não tem</span>`);
  const notice = r.data && r.data.warning ? `<div class="notice">${icon("alert")} ${esc(r.data.warning)}</div>` : "";
  const levelBox = lv.provided
    ? `<div data-tip="${esc(`Diferença efetiva ${lv.effective_gap >= 0 ? "+" : ""}${lv.effective_gap} em relação à referência ${lv.reference_level}. ${lv.note}`)}"><span>Efeito dos níveis</span><b style="color:${lv.impact_ev < -0.004 ? "var(--bad)" : lv.impact_ev > 0.004 ? "var(--ok)" : "inherit"}">${pp(lv.impact_ev)} p.p.</b></div>`
    : `<div data-tip="Ative 'meus níveis' para considerar a sua coleção"><span>Efeito dos níveis</span><b class="muted">—</b></div>`;

  $("#result-left").innerHTML = `
    <div class="panel">
      <div class="result-head">
        ${ring(r.overall.ev)}
        <div class="verdict">
          <div class="arch">${esc(r.archetype.primary_pt)}</div>
          <div class="line">${verdictLine(r.matchups)}</div>
          <div class="tags">${tags.join("")}</div>
        </div>
      </div>
      <div class="kv">
        <div data-tip="Pior matchup entre os arquétipos do meta"><span>Pior matchup</span><b>${pct(r.overall.worst)}</b></div>
        <div data-tip="${esc(r.confidence.text)}"><span>Confiança</span><b>${esc(r.confidence.level)}</b></div>
        ${levelBox}
      </div>
      ${notice}
    </div>
    ${improvementsPanel(r)}
    <div class="panel"><h2>Perfil do deck</h2>${profile(r.capabilities)}</div>`;

  const syn = r.synergies.filter((s) => s.value > 0).slice(0, 5).map((s) =>
    `<div class="syn" data-tip="${esc(s.reason + " (" + s.source + ")")}">${mini(s.cards[0])}<span class="op">+</span>${mini(s.cards[1])}</div>`).join("");
  const conf = r.synergies.filter((s) => s.value < 0).slice(0, 3).map((s) =>
    `<div class="syn" data-tip="${esc(s.reason)}">${mini(s.cards[0])}<span class="op">×</span>${mini(s.cards[1])}</div>`).join("");
  const issues = r.coherence.issues.map((i) => `<span class="tag bad" data-tip="${esc(i)}">${icon("alert")} ${esc(i.split(":")[0].split("—")[0])}</span>`).join(" ");

  $("#result-right").innerHTML = `
    <div class="panel">
      <div class="panel-head"><h2>Matchups</h2><span class="spacer"></span>
        <div class="legend"><span><i style="background:var(--pos)"></i>favorável</span><span><i style="background:var(--neg)"></i>desfavorável</span></div></div>
      ${divergingChart(r.matchups)}
    </div>
    <div class="panel">
      <div class="two">
        <div><div class="sub">Sinergias</div>${syn ? `<div class="syn-list">${syn}</div>` : `<p class="muted small">Nenhuma sinergia catalogada.</p>`}</div>
        <div><div class="sub">Conflitos</div>${conf || issues ? `<div class="syn-list">${conf}</div><div class="tags" style="margin-top:6px">${issues}</div>` : `<p class="muted small">Nenhum conflito encontrado.</p>`}</div>
      </div>
    </div>
    <div class="panel"><div class="panel-head"><h2>Melhorar o deck</h2><span class="spacer"></span>
        <select id="sg-target"><option value="">Média geral</option>${state.archetypes.map((a) => `<option value="${esc(a.key)}">Contra ${esc(a.name)}</option>`).join("")}</select>
        <button id="btn-suggest" class="primary">Sugerir trocas</button></div>
      <div class="row" style="gap:16px">
        <label class="switch"><input type="checkbox" id="sg-keep"><span></span>manter condição de vitória</label>
        <label class="switch"><input type="checkbox" id="sg-owned" ${hasCollection() ? "checked" : ""}><span></span>só minhas cartas</label>
      </div>
      <div id="suggest-result"></div></div>`;

  const tech = r.matchups.map((m) => `<tr><td>${esc(m.name)}</td><td>${pct(m.win_prob, 1)}</td><td>${m.interval ? `${pct(m.interval[0])}–${pct(m.interval[1])}` : "—"}</td>
    <td>${esc(m.confidence)}</td><td>${esc(m.source)}</td><td>${num(m.exact_games)}</td></tr>`).join("");
  const factors = r.factors.items.filter((f) => f.available).map((f) => `<tr><td>${esc(f.factor.replace(/_/g, " "))}</td><td>${(100 * num(f.value)).toFixed(0)}</td><td>${num(f.weight)}</td></tr>`).join("");
  $("#result-bottom").innerHTML = `<details class="panel"><summary>Detalhes técnicos</summary>
    <p style="margin-top:12px">${esc(r.summary)}</p>
    <p class="muted small">Meta: ${esc(r.overall.meta_source)} · score ${esc(r.overall.objective_mode)} ${(100 * r.overall.score).toFixed(1)} · desvio entre matchups ±${(100 * r.overall.sd).toFixed(1)} p.p.</p>
    <div class="two"><div class="table-wrap"><table><tr><th>Arquétipo</th><th>Chance</th><th>Intervalo 90%</th><th>Confiança</th><th>Fonte</th><th>Partidas</th></tr>${tech}</table></div>
    <div class="table-wrap"><table><tr><th>Fator (índice ${r.factors.index ?? "—"})</th><th>Valor</th><th>Peso</th></tr>${factors}</table></div></div>
  </details>`;
  bindSuggest(body);
}

function improvementsPanel(r) {
  const imp = r.improvements;
  if (!imp) return "";
  const items = [
    ...imp.unlocks.slice(0, 4).map((u) => ({ gain: u.gain, html: `${mini(u.card, u.kind)}<span class="imp-txt">Desbloquear ${u.kind === "evo" ? "a Evolução" : "o Herói"}</span>` })),
    ...imp.upgrades.slice(0, 4).map((u) => ({ gain: u.gain, html: `${mini(u.card)}<span class="imp-txt">Upar do nível ${num(u.from)} para ${num(u.to)}</span>` })),
  ].sort((a, b) => b.gain - a.gain).slice(0, 5);
  if (!items.length) return "";
  return `<div class="panel"><div class="panel-head"><h2>Para ficar mais forte</h2><span class="spacer"></span>
      ${imp.all_upgrades_gain ? `<span class="tag good" data-tip="Ganho se todas as cartas abaixo do nível de referência forem upadas">${icon("up")} todos os upgrades ${pp(imp.all_upgrades_gain)} p.p.</span>` : ""}</div>
    ${items.map((x) => `<div class="imp">${x.html}<span class="delta up">${pp(x.gain)}</span></div>`).join("")}
    <p class="muted small" style="margin:8px 0 0">Ganho estimado na chance média contra o meta.</p></div>`;
}

function bindSuggest(baseBody) {
  const btn = $("#btn-suggest");
  btn.addEventListener("click", async () => {
    btn.disabled = true;
    $("#suggest-result").innerHTML = `<div class="loading"><span class="spinner"></span>Testando trocas…</div>`;
    try {
      const body = { deck: baseBody.deck, collection: baseBody.collection, keep_win_condition: $("#sg-keep").checked,
        target: $("#sg-target").value || null, top: 5 };
      if ($("#sg-owned").checked) { const col = collectionPayload(); if (col) body.collection = col; } else delete body.collection;
      const r = await api("/api/suggest", body);
      if (!r.swaps.length) { $("#suggest-result").innerHTML = "<p class='muted small'>Nenhuma troca melhora o deck segundo o modelo atual.</p>"; return; }
      $("#suggest-result").innerHTML = r.swaps.map((s) => {
        const ds = Object.entries(s.delta_by_archetype).filter(([, v]) => Math.abs(v) >= 0.01).sort((a, b) => b[1] - a[1]);
        const eff = [...ds.slice(0, 2), ...ds.slice(-2).filter(([, v]) => v < 0)]
          .filter((x, i, arr) => arr.indexOf(x) === i)
          .map(([a, v]) => `<span class="tag small ${v > 0 ? "good" : "bad"}">${icon(v > 0 ? "up" : "down")} ${esc(state.archName[a] || a)} ${pp(v)}</span>`).join("");
        return `<div class="swap" data-tip="${esc(s.explanation)}">${mini(s.out)}<span class="arrow">${icon("arrow")}</span>${mini(s.in)}
          <div class="eff">${eff}</div><span class="delta ${s.delta_ev >= 0 ? "up" : "down"}">${pp(s.delta_ev)}</span></div>`;
      }).join("");
    } catch (e) { $("#suggest-result").innerHTML = ""; toast("Erro: " + e.message); }
    finally { btn.disabled = false; }
  });
}

// Coluna direita antes da análise: decks em alta
async function ensureMeta() {
  if (!state.meta) state.meta = await api("/api/meta");
  return state.meta;
}
async function renderSidebarMeta() {
  if (state.contrib) return;
  const box = $("#result-right");
  try {
    const m = await ensureMeta();
    if (state.contrib) return;
    box.innerHTML = `<div class="panel"><div class="panel-head"><h2>Decks em alta</h2><span class="spacer"></span>
      <button class="sm ghost" id="see-meta">Ver todos</button></div>
      ${metaList(m.decks.slice(0, 5), false)}</div>`;
    $("#see-meta").addEventListener("click", () => showTab("meta"));
  } catch { box.innerHTML = ""; }
}

// ------------------------------------------------------------------ META
function metaList(decks, withPos = true) {
  if (!decks.length) return "<p class='muted small'>Ainda não há decks com partidas suficientes.</p>";
  return decks.map((d, i) => `<div class="meta-deck ${withPos ? "" : "nopos"}">
    <div class="pos">${withPos ? i + 1 : ""}</div>
    <div><div class="info"><b>${esc(d.name || d.archetype_pt)}</b><span>${icon("drop")} ${num(d.avg_elixir).toFixed(1)}</span>
      ${d.games ? `<span>${num(d.games)} partidas · ${pct(d.usage, 1)} de uso</span>` : `<span>estimativa</span>`}</div>
      ${deckTiles(d.deck)}</div>
    <div class="wr"><b style="color:${d.winrate >= 0.5 ? "var(--pos)" : "var(--neg)"}">${pct(d.winrate, 1)}</b>
      <span class="muted small" data-tip="${esc(d.games ? `Taxa de vitória ajustada pelo tamanho da amostra (bruta: ${pct(d.winrate_raw, 1)})` : "Chance média estimada pela heurística (sem dados)")}">${d.games ? "vitórias" : "estimada"}</span>
      ${deckButtons(d.deck)}</div></div>`).join("");
}
async function renderMeta() {
  try {
    const m = await ensureMeta();
    const decks = [...m.decks].sort((a, b) => (state.metaSort === "winrate" ? b.winrate - a.winrate : b.games - a.games || b.winrate - a.winrate));
    $("#meta-note").textContent = m.source === "dados"
      ? `Com base nas partidas coletadas (${m.data.first ? m.data.first.slice(0, 10) : ""} a ${m.data.last ? m.data.last.slice(0, 10) : ""}).`
      : "Sem partidas coletadas ainda: mostrando decks de referência com estimativa heurística.";
    $("#meta-decks").innerHTML = metaList(decks);
    $("#meta-cards").innerHTML = m.cards.length
      ? `<div class="card-rank">${m.cards.slice(0, 24).map((c) => `<div class="cr">${tile(state.byKey[c.card], { extraTip: `Uso: ${pct(c.usage, 1)} · vitórias: ${pct(c.winrate, 1)}`, showLevel: false })}
          <small>${pct(c.usage, 0)} uso</small></div>`).join("")}</div>`
      : "<p class='muted small'>Disponível quando houver partidas coletadas.</p>";
  } catch (e) { $("#meta-decks").innerHTML = `<p class="muted">Erro: ${esc(e.message)}</p>`; }
}
$$("#meta-sort button").forEach((b) => b.addEventListener("click", () => {
  state.metaSort = b.dataset.v;
  $$("#meta-sort button").forEach((x) => x.classList.toggle("on", x === b));
  renderMeta();
}));
async function lookupPlayer() {
  const tag = $("#lookup-tag").value.trim().replace(/^#/, "").toUpperCase();
  if (!tag) return toast("Digite a tag do jogador.");
  const box = $("#lookup-result");
  box.innerHTML = `<div class="loading"><span class="spinner"></span>Buscando…</div>`;
  try {
    const r = await api(`/api/player/${encodeURIComponent(tag)}/decks`);
    const p = r.player;
    const cur = r.current_deck.length === 8 ? `<div class="sub">Deck atual</div>${deckTiles(r.current_deck)}<div style="margin-top:8px">${deckButtons(r.current_deck)}</div>` : "";
    const recent = r.recent_decks.map((d) => `<div class="meta-deck nopos"><div class="pos"></div><div>
        <div class="info"><span>${num(d.games)} partida(s) · ${num(d.wins)} vitória(s)${d.avg_level ? ` · nível ${d.avg_level}` : ""}</span></div>${deckTiles(d.deck)}</div>
        <div class="wr">${deckButtons(d.deck)}</div></div>`).join("");
    box.innerHTML = `<div class="player-head"><span class="av">${icon("user")}</span><div><b>${esc(p.name)}</b> <span class="muted">${esc(p.tag)}</span><br>
      <span class="muted small">${p.trophies != null ? `${num(p.trophies)} troféus · ` : ""}${num(r.n_cards)} cartas${r.avg_level ? ` · nível médio ${r.avg_level}` : ""}${p.arena ? " · " + esc(p.arena) : ""}</span></div></div>
      ${cur}${recent ? `<div class="sub">Decks recentes</div>${recent}` : ""}`;
  } catch (e) { box.innerHTML = `<p class="muted">Erro: ${esc(e.message)}</p>`; }
}
$("#btn-lookup").addEventListener("click", lookupPlayer);
$("#lookup-tag").addEventListener("keydown", (e) => { if (e.key === "Enter") lookupPlayer(); });

// ------------------------------------------------------------------ CRIAR
function renderChips() {
  for (const k of ["wincon", "must", "exclude"]) {
    const el = $("#chips-" + k);
    el.innerHTML = state.build[k].map((c) => tile(state.byKey[c], { extraTip: "Clique para remover", showLevel: false })).join("")
      + `<button class="add-tile" data-tip="Adicionar">+</button>`;
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
    const t0 = performance.now();
    const r = await api("/api/build", body);
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    const order = state.archetypes.map((a) => a.key);
    $("#build-result").innerHTML = `<p class="muted small" style="margin:0 4px">${r.decks.length} decks em ${secs} s · ${num(r.explored).toLocaleString("pt-BR")} combinações avaliadas</p>`
      + (r.decks.map((d) => {
        const a = d.analysis, by = Object.fromEntries(a.matchups.map((m) => [m.archetype, m]));
        const worst = a.matchups.reduce((x, y) => (y.win_prob < x.win_prob ? y : x));
        const strip = order.map((k) => `<i style="background:${cellColor(by[k].win_prob)}" data-tip="${esc(by[k].name)}: ${pct(by[k].win_prob, 1)}"></i>`).join("");
        const lvl = deckLevel(a.deck);
        const keys = slotKeys(a.slots), forms = slotForms(a.slots);
        return `<div class="panel deck-result">
          <div class="rank">${num(d.rank)}</div>
          <div><div class="head"><b>${esc(a.archetype.primary_pt)}</b>
              <span class="stat-chip">${icon("drop")} <b>${num(a.avg_elixir).toFixed(1)}</b></span>
              ${lvl != null ? `<span class="stat-chip">${icon("level")} nível <b>${lvl.toFixed(1)}</b></span>` : ""}</div>
            ${deckTiles(a.slots)}
            <div class="strip" data-tip="Matchups por arquétipo (azul = favorável, vermelho = desfavorável)">${strip}</div></div>
          <div class="side"><b style="color:${a.overall.ev >= 0.5 ? "var(--pos)" : "var(--neg)"}">${pct(a.overall.ev, 1)}</b>
            <span class="muted small">vs meta · pior ${pct(worst.win_prob)}</span>${deckButtons(keys, true, forms)}</div>
        </div>`;
      }).join("") || "<div class='panel muted'>Nenhum deck encontrado com essas restrições.</div>")
      + potentialSection(r.potential || []);
  } catch (e) { $("#build-result").innerHTML = ""; toast("Erro: " + e.message); }
  finally { btn.disabled = false; }
});

function potentialSection(list) {
  if (!list.length) return "";
  return `<div class="pot-head"><h2>${icon("up")} Com upgrades ou desbloqueios</h2>
      <p class="muted small">Decks que ficam melhores se você upar cartas abaixo do nível ou desbloquear Evoluções/Heróis.</p></div>`
    + list.map((p) => {
      const a = p.analysis;
      const chips = [
        ...p.upgrades.map((u) => `<span class="tag neutral">${icon("level")} ${esc(state.byKey[u.card]?.name_pt || u.card)} ${num(u.from)} → ${num(u.to)}</span>`),
        ...p.unlocks.map((u) => `<span class="tag neutral">${icon("sparkles")} ${u.kind === "evo" ? "Evo" : "Herói"} ${esc(state.byKey[u.card]?.name_pt || u.card)}</span>`),
      ].join("");
      return `<div class="panel deck-result potential">
        <div class="rank">${icon("up")}</div>
        <div><div class="head"><b>${esc(a.archetype.primary_pt)}</b><span class="stat-chip">${icon("drop")} <b>${num(a.avg_elixir).toFixed(1)}</b></span></div>
          ${deckTiles(p.potential_slots)}
          <div class="tags" style="margin-top:10px">${chips}</div></div>
        <div class="side"><b style="color:var(--pos)">${pct(p.potential_ev, 1)}</b>
          <span class="muted small">hoje ${pct(a.overall.ev, 1)} · ${pp(p.gain)} p.p.</span>
          ${deckButtons(slotKeys(a.slots), true, slotForms(a.slots))}</div></div>`;
    }).join("");
}

// ------------------------------------------------------------------ COLEÇÃO
const LEVELS = Array.from({ length: 16 }, (_, i) => 16 - i);
function renderCollection() {
  const col = loadCollection();
  const q = $("#col-filter").value;
  const ownedOnly = $("#col-owned").checked;
  const list = state.cards.filter((c) => matches(c, q) && (!ownedOnly || c.key in col.cards))
    .sort((a, b) => a.elixir - b.elixir || a.name_pt.localeCompare(b.name_pt));
  const lv = Object.values(col.cards).filter((x) => typeof x === "number");
  const avg = lv.length ? lv.reduce((a, b) => a + b, 0) / lv.length : null;
  $("#col-stats").innerHTML = `<span class="stat-chip">${icon("layers")} <b>${lv.length}</b> cartas</span>
    <span class="stat-chip">${icon("sparkles")} <b>${col.evolutions.length}</b> evoluções</span>
    <span class="stat-chip">${icon("crown")} <b>${(col.heroes || []).length}</b> heróis</span>
    ${avg != null ? `<span class="stat-chip">${icon("level")} nível médio <b>${avg.toFixed(1)}</b></span>` : ""}`;
  $("#col-ref").innerHTML = `<option value="">Automática${refLevel(col) ? ` (${refLevel(col)})` : ""}</option>` + options(LEVELS, col.reference_level ?? "");
  $("#col-table").innerHTML = `<div class="col-grid">${list.map((c) => `<div class="col-card ${c.key in col.cards ? "owned" : ""}">
      ${tile(c, { form: col.evolutions.includes(c.key) ? "evo" : (col.heroes || []).includes(c.key) ? "hero" : "normal", showLevel: false })}
      <div class="col-ctrl"><select data-key="${esc(c.key)}" aria-label="Nível de ${esc(c.name_pt)}"><option value="">—</option>${options(LEVELS, col.cards[c.key] ?? "")}</select>
      ${c.evo ? `<button class="evo-toggle ${col.evolutions.includes(c.key) ? "on" : ""}" data-evo="${esc(c.key)}" data-tip="Evolução desbloqueada">EVO</button>` : ""}
      ${c.hero ? `<button class="evo-toggle hero ${(col.heroes || []).includes(c.key) ? "on" : ""}" data-hero="${esc(c.key)}" data-tip="Herói desbloqueado">HERÓI</button>` : ""}</div>
    </div>`).join("")}</div>`;
  $$("#col-table select").forEach((sel) => sel.addEventListener("change", () => {
    const c = loadCollection();
    const v = parseInt(sel.value);
    if (isNaN(v)) delete c.cards[sel.dataset.key]; else c.cards[sel.dataset.key] = v;
    saveCollection(c); renderCollection();
  }));
  $$("#col-table .evo-toggle").forEach((b) => b.addEventListener("click", () => {
    const c = loadCollection();
    const k = b.dataset.evo || b.dataset.hero;
    const field = b.dataset.evo ? "evolutions" : "heroes";
    c[field] = c[field] || [];
    c[field] = c[field].includes(k) ? c[field].filter((x) => x !== k) : [...c[field], k];
    if (!(k in c.cards)) c.cards[k] = c.reference_level || refLevel(c) || 14;
    saveCollection(c); renderCollection();
  }));
}
$("#col-filter").addEventListener("input", renderCollection);
$("#col-owned").addEventListener("change", renderCollection);
$("#col-ref").addEventListener("change", () => { const c = loadCollection(); c.reference_level = parseInt($("#col-ref").value) || null; saveCollection(c); renderCollection(); });
$("#col-fill").addEventListener("change", () => {
  const v = parseInt($("#col-fill").value);
  if (isNaN(v)) return;
  if (!confirm(`Definir TODAS as cartas no nível ${v}?`)) { $("#col-fill").value = ""; return; }
  const c = loadCollection();
  for (const card of state.cards) c.cards[card.key] = v;
  saveCollection(c); $("#col-fill").value = ""; renderCollection();
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
    const c = { cards: {}, evolutions: (d.evolutions || []).filter((k) => state.byKey[k]),
      heroes: (d.heroes || []).filter((k) => state.byKey[k]), reference_level: d.reference_level ?? null };
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
      ${kpi("Partidas no modelo", d.model ? num(d.battles).toLocaleString("pt-BR") : "0", d.model ? `${String(d.first || "").slice(5, 10)} a ${String(d.last || "").slice(5, 10)}` : "—")}
      ${kpi("Acurácia (recentes)", v ? pct(v.accuracy_model, 1) : "—", v ? `${num(v.holdout)} partidas de teste` : "sem validação", v ? `log-loss ${num(v.logloss_model).toFixed(4)} vs ${num(v.logloss_baseline).toFixed(4)} (base)` : "")}
      ${kpi("Treinado em", d.model ? esc(String(d.trained_at || "").slice(0, 16).replace("T", " ")) : "—", d.model ? `janela de ${num(d.days)} dias` : "")}
    </div>`;
    $("#collector-pill").innerHTML = !c.enabled ? `<span class="tag neutral">desativada</span>`
      : c.running ? `<span class="tag neutral"><span class="spinner"></span>coletando</span>` : `<span class="tag good">${icon("check")} ativa · a cada ${num(c.interval_hours)} h</span>`;
    $("#collector-status").innerHTML = !c.enabled
      ? `<p class="muted small">O servidor precisa da chave da API (CR_API_TOKEN) para coletar partidas reais.</p>`
      : `<p class="muted small">${c.last_run ? `Última coleta: ${esc(c.last_run.replace("T", " "))}` : "Primeira coleta em andamento."}
         ${c.last_result ? ` · ${num(c.last_result.new_battles)} partidas novas · ${num(c.last_result.total)} no banco` : ""}</p>
         ${c.last_error ? `<span class="tag bad">${icon("alert")} ${esc(c.last_error)}</span>` : ""}
         ${c.log?.length ? `<details class="more"><summary>Registro</summary><div class="log">${c.log.map(esc).join("\n")}</div></details>` : ""}`;
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
    if (d.model && !d.warning) { pill.classList.add("real"); pill.textContent = `dados reais · ${num(d.battles).toLocaleString("pt-BR")} partidas`; }
    else if (d.model) { pill.classList.add("synthetic"); pill.textContent = "dados de demonstração"; }
    else if (s.collector?.running) { pill.classList.add("busy"); pill.textContent = "coletando partidas…"; }
    else pill.textContent = "modo heurístico";
    pill.dataset.tip = d.warning || d.note || "Estimativas baseadas em partidas reais.";
  } catch { /* ignora */ }
}

// ------------------------------------------------------------------ init
(async function init() {
  hydrateIcons();
  $("#build-top").innerHTML = options([3, 5, 8, 10], 5);
  const el = ["", "2.6", "2.8", "3.0", "3.2", "3.4", "3.6", "3.8", "4.0", "4.2", "4.5"];
  $("#build-min").innerHTML = options(el, "", (v) => (v ? v : "Sem mínimo"));
  $("#build-max").innerHTML = options(el, "", (v) => (v ? v : "Sem máximo"));
  $("#col-fill").innerHTML = `<option value="">Escolher…</option>` + options(LEVELS, "");
  $("#tag-input").addEventListener("keydown", (e) => { if (e.key === "Enter") importTag($("#tag-input").value); });
  $("#btn-tag").addEventListener("click", () => importTag($("#tag-input").value));
  try {
    state.cards = await api("/api/cards");
    state.byKey = Object.fromEntries(state.cards.map((c) => [c.key, c]));
    state.archetypes = await api("/api/archetypes");
    state.archName = Object.fromEntries(state.archetypes.map((a) => [a.key, a.name]));
    $("#build-style").innerHTML += state.archetypes.map((a) => `<option value="${esc(a.key)}">${esc(a.name)}</option>`).join("");
    if (hasCollection()) $("#analyze-use-col").checked = true;
    const saved = load(DECK_KEY, null);
    if (saved && Array.isArray(saved.deck) && saved.deck.every((k) => k === null || state.byKey[k])) setDeck(saved.deck.map((k) => k), saved.forms);
    else setDeck(["Skeletons", "Musketeer", "Ice Golem", "Hog Rider", "Ice Spirit", "Cannon", "Fireball", "The Log"]);
    renderAccount(); renderSlots(); renderChips(); renderSidebarMeta(); refreshPill();
    setInterval(refreshPill, 60000);
  } catch (e) { toast("Falha ao carregar: " + e.message, 8000); }
})();
