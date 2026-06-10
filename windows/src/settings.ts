import { invoke } from "@tauri-apps/api/core";
import { emit } from "@tauri-apps/api/event";
import { getVersion } from "@tauri-apps/api/app";
import { exit } from "@tauri-apps/plugin-process";
import { enable, disable, isEnabled } from "@tauri-apps/plugin-autostart";
import { loadCatalog, savedSlug, saveSlug, type Pet } from "./catalog";
import { t, getLang, setLang, type Lang } from "./i18n";

// ------------------------------------------------------------------ tabs ----
function initTabs() {
  const tabs = document.querySelectorAll<HTMLButtonElement>(".tabbar .tab");
  tabs.forEach((b) => {
    b.onclick = () => {
      tabs.forEach((x) => x.classList.toggle("sel", x === b));
      document.querySelectorAll<HTMLElement>(".page").forEach((p) => {
        p.classList.toggle("sel", p.dataset.page === b.dataset.tab);
      });
    };
  });
}

// ---------------------------------------------------------------- agents ----
interface AgentInfo {
  kind: string;
  display_name: string;
  installed: boolean;
  note: string | null;
}

const agentsRoot = document.getElementById("agents")!;
let agentsCache: AgentInfo[] = [];

async function loadAgents() {
  agentsCache = await invoke<AgentInfo[]>("list_agents");
  renderAgents();
}

function renderAgents() {
  agentsRoot.innerHTML = "";
  for (const a of agentsCache) {
    const row = document.createElement("div");
    row.className = "agent-row";

    const meta = document.createElement("div");
    meta.className = "meta";
    const status = a.note
      ? `<div class="note">${esc(t(a.note))}</div>`
      : a.installed
      ? `<div class="ok">${esc(t("Hook installed"))}</div>`
      : "";
    meta.innerHTML = `<div class="name">${esc(a.display_name)}</div>${status}`;

    const btn = document.createElement("button");
    btn.textContent = a.installed ? t("Remove") : t("Install");
    if (a.installed) btn.classList.add("remove");
    btn.onclick = async () => {
      btn.disabled = true;
      try { await invoke("toggle_install", { kind: a.kind }); } catch (e) { alert(String(e)); }
      await loadAgents();
    };

    row.appendChild(meta);
    row.appendChild(btn);
    agentsRoot.appendChild(row);
  }
}

// ------------------------------------------------------------------ pet ----
const current = document.getElementById("pet-current") as HTMLDivElement;
const search = document.getElementById("pet-search") as HTMLInputElement;
const random = document.getElementById("pet-random") as HTMLButtonElement;
const results = document.getElementById("pet-results") as HTMLDivElement;

let catalog: Pet[] = [];
let currentPet: Pet | undefined;

async function pick(p: Pet) {
  saveSlug(p.slug);
  localStorage.removeItem("ap_pet_custom"); // back to a catalog pet
  await emit("set-pet", { slug: p.slug, url: p.spritesheetUrl });
  currentPet = p;
  showCurrent();
  results.querySelectorAll(".pet-item.sel").forEach((el) => el.classList.remove("sel"));
  results.querySelector(`.pet-item[data-slug="${CSS.escape(p.slug)}"]`)?.classList.add("sel");
}

function showCurrent() {
  if (!catalog.length) { current.textContent = t("Couldn't load pets , check your internet connection."); return; }
  current.textContent = currentPet ? currentPet.name : t("(default)");
  const hero = document.getElementById("hero-thumb") as HTMLCanvasElement;
  const url = localStorage.getItem("ap_pet_custom") || currentPet?.spritesheetUrl;
  if (url) drawThumb(hero, url);
}

// Browsable grid: shows the whole catalog a page at a time. Thumbnails only
// load when scrolled into view (the catalog is ~4000 spritesheets).
const PAGE = 48;
const more = document.getElementById("pet-more") as HTMLButtonElement;
let view: Pet[] = [];
let shown = 0;

const thumbObserver = new IntersectionObserver((entries) => {
  for (const e of entries) {
    if (!e.isIntersecting) continue;
    const cv = e.target as HTMLCanvasElement;
    thumbObserver.unobserve(cv);
    drawThumb(cv, cv.dataset.url!);
  }
}, { root: results, rootMargin: "120px" });

function setView(list: Pet[]) {
  view = list;
  shown = 0;
  results.innerHTML = "";
  appendPage();
}

function appendPage() {
  for (const p of view.slice(shown, shown + PAGE)) {
    const item = document.createElement("button");
    item.className = "pet-item";
    item.dataset.slug = p.slug;
    if (p.slug === savedSlug()) item.classList.add("sel");
    const cv = document.createElement("canvas");
    cv.width = 44; cv.height = 44; cv.className = "pet-thumb";
    cv.dataset.url = p.spritesheetUrl;
    thumbObserver.observe(cv);
    const label = document.createElement("span");
    label.textContent = p.name;
    item.appendChild(cv);
    item.appendChild(label);
    item.onclick = () => pick(p);
    results.appendChild(item);
  }
  shown = Math.min(shown + PAGE, view.length);
  more.style.display = shown < view.length ? "" : "none";
}

// Draws frame 0 (first column of the Idle row) of an 8x9 spritesheet as a preview.
function drawThumb(cv: HTMLCanvasElement, url: string) {
  const ctx = cv.getContext("2d");
  if (!ctx) return;
  ctx.imageSmoothingEnabled = false;
  const img = new Image();
  img.onload = () => {
    const fw = img.naturalWidth / 8, fh = img.naturalHeight / 9;
    if (!fw || !fh) return;
    const s = Math.min(cv.width / fw, cv.height / fh);
    const dw = fw * s, dh = fh * s;
    ctx.clearRect(0, 0, cv.width, cv.height);
    ctx.drawImage(img, 0, 0, fw, fh, (cv.width - dw) / 2, (cv.height - dh) / 2, dw, dh);
  };
  img.src = url;
}

async function initPet() {
  // Keep retrying , the app may have launched before the network was up.
  for (;;) {
    catalog = await loadCatalog();
    if (catalog.length) break;
    showCurrent(); // "couldn't load" hint while we wait
    await new Promise((r) => setTimeout(r, 15000));
  }
  currentPet = catalog.find((p) => p.slug === savedSlug());
  showCurrent();
  setView(catalog);
  search.addEventListener("input", () => {
    const q = search.value.trim().toLowerCase();
    setView(q ? catalog.filter((p) => p.name.toLowerCase().includes(q)) : catalog);
  });
  random.addEventListener("click", () => {
    if (catalog.length) pick(catalog[Math.floor(Math.random() * catalog.length)]);
  });
  more.addEventListener("click", appendPage);
}

// ---------------------------------------------------------------- bubble ----
const MSG_STATES: [string, string][] = [
  ["working", "Working"], ["waiting", "Needs you"], ["done", "Done"], ["idle", "Idle"],
];
const MSG_AGENTS: [string, string][] = [
  ["all", "All agents"], ["claude", "Claude Code"], ["codex", "Codex"], ["gemini", "Gemini CLI"],
  ["cursor", "Cursor"], ["opencode", "opencode"], ["windsurf", "Windsurf"],
  ["antigravity", "Antigravity"], ["kiro", "Kiro CLI"], ["copilot", "GitHub Copilot"],
];

function initBubble() {
  const changed = () => { emit("bubble-changed", null); };
  const theme = document.getElementById("theme") as HTMLSelectElement;
  const opacity = document.getElementById("opacity") as HTMLInputElement;
  const fontSize = document.getElementById("font-size") as HTMLInputElement;
  const fontFamily = document.getElementById("font-family") as HTMLSelectElement;
  const msgAgent = document.getElementById("msg-agent") as HTMLSelectElement;
  const editors = document.getElementById("msg-editors")!;

  theme.value = localStorage.getItem("ap_theme") || "dark";
  opacity.value = localStorage.getItem("ap_opacity") || "92";
  fontSize.value = localStorage.getItem("ap_font_size") || "12";
  fontFamily.value = localStorage.getItem("ap_font_family") || "system";

  theme.onchange = () => { localStorage.setItem("ap_theme", theme.value); changed(); };
  opacity.oninput = () => { localStorage.setItem("ap_opacity", opacity.value); changed(); };
  fontSize.oninput = () => { localStorage.setItem("ap_font_size", fontSize.value); changed(); };
  fontFamily.onchange = () => { localStorage.setItem("ap_font_family", fontFamily.value); changed(); };

  msgAgent.innerHTML = "";
  for (const [k, name] of MSG_AGENTS) {
    const o = document.createElement("option");
    o.value = k;
    o.textContent = k === "all" ? t("All agents") : name; // brand names stay
    msgAgent.appendChild(o);
  }

  const build = (agent: string) => {
    editors.innerHTML = "";
    for (const [st, label] of MSG_STATES) {
      const wrap = document.createElement("div");
      wrap.className = "msg-editor";
      const lbl = document.createElement("div");
      lbl.className = "msg-label";
      lbl.dataset.label = label;
      lbl.textContent = t(label);
      const ta = document.createElement("textarea");
      const key = `ap_msg_${agent}_${st}`;
      ta.value = localStorage.getItem(key) || "";
      ta.addEventListener("input", () => { localStorage.setItem(key, ta.value); changed(); });
      wrap.appendChild(lbl);
      wrap.appendChild(ta);
      editors.appendChild(wrap);
    }
  };
  msgAgent.onchange = () => build(msgAgent.value);
  build("all");

  const phrases = document.getElementById("phrases") as HTMLSelectElement;
  phrases.value = localStorage.getItem("ap_theme_phrases") || "off";
  phrases.onchange = () => { localStorage.setItem("ap_theme_phrases", phrases.value); changed(); };

  const idle = document.getElementById("idle") as HTMLInputElement;
  idle.checked = localStorage.getItem("ap_idle") !== "0";
  idle.onchange = () => localStorage.setItem("ap_idle", idle.checked ? "1" : "0");
}

// ----------------------------------------------- pet size / fx / import ----
function initPetControls() {
  const changed = () => { emit("bubble-changed", null); };
  const size = document.getElementById("pet-size") as HTMLInputElement;
  size.value = localStorage.getItem("ap_pet_size") || "100";
  size.oninput = () => { localStorage.setItem("ap_pet_size", size.value); changed(); };

  const fx = document.getElementById("fx") as HTMLInputElement;
  fx.checked = localStorage.getItem("ap_fx") !== "0";
  fx.onchange = () => { localStorage.setItem("ap_fx", fx.checked ? "1" : "0"); changed(); };

  // Import a local spritesheet (stored as a data URL , no extra plugins).
  const btn = document.getElementById("import-pet") as HTMLButtonElement;
  const file = document.createElement("input");
  file.type = "file";
  file.accept = "image/png,image/webp,image/*";
  file.style.display = "none";
  document.body.appendChild(file);
  btn.onclick = () => file.click();
  file.onchange = () => {
    const f = file.files?.[0];
    if (!f) return;
    const reader = new FileReader();
    reader.onload = () => {
      const url = String(reader.result);
      localStorage.setItem("ap_pet_custom", url);
      emit("set-pet", { slug: "local", url });
      current.textContent = t("(your image)");
      drawThumb(document.getElementById("hero-thumb") as HTMLCanvasElement, url);
    };
    reader.readAsDataURL(f);
  };
}

// --------------------------------------------------------- live preview ----
function initPreview() {
  document.querySelectorAll<HTMLButtonElement>(".preview-btns button").forEach((b) => {
    b.onclick = () => {
      const state = b.dataset.prev!;
      emit("agent-event", { agent: "demo", session: "preview", state, project: "preview", message: "" });
      if (state === "done") setTimeout(() => emit("agent-end", "preview"), 4000);
    };
  });
}

// --------------------------------------------------------- notifications ----
function initNotify() {
  const box = document.getElementById("notify") as HTMLInputElement;
  box.checked = localStorage.getItem("ap_notify") !== "0";
  box.addEventListener("change", () => localStorage.setItem("ap_notify", box.checked ? "1" : "0"));
  const snd = document.getElementById("sound") as HTMLInputElement;
  snd.checked = localStorage.getItem("ap_sound") !== "0";
  snd.addEventListener("change", () => localStorage.setItem("ap_sound", snd.checked ? "1" : "0"));
}

// --------------------------------------------------------------- startup ----
async function initAutostart() {
  const box = document.getElementById("autostart") as HTMLInputElement;
  try { box.checked = await isEnabled(); } catch {}
  box.addEventListener("change", async () => {
    try { box.checked ? await enable() : await disable(); } catch (e) { alert(String(e)); }
  });
}

// ----------------------------------------------------------------- i18n ----
function applyStatic() {
  document.documentElement.lang = getLang();
  const set = (id: string, key: string) => { const el = document.getElementById(id); if (el) el.textContent = t(key); };
  // tabs
  set("tab-general", "General");
  set("tab-pet", "Pet");
  set("tab-bubble", "Bubble");
  set("tab-about", "About");
  // general
  set("t-lang", "Language");
  set("t-lang2", "Language");
  set("t-startup", "Startup");
  set("t-autostart", "Launch at login");
  set("t-autostart-sub", "AgentPet starts automatically when you sign in.");
  set("t-notif", "Notifications");
  set("t-notify", "Notifications");
  set("t-notify-sub", "Alerts when an agent finishes or needs input");
  set("t-sound", "Play a sound");
  set("t-agents", "Agent integrations");
  set("t-app", "App");
  set("t-version", "Version");
  set("quit-btn", "Quit AgentPet");
  // pet
  set("t-pet-sub", "Pick the companion that floats on your desktop.");
  set("t-choose", "Choose pet");
  set("pet-more", "Show more");
  set("import-pet", "Use my own spritesheet…");
  set("t-size", "Size on screen");
  set("t-petsize", "Pet size");
  set("t-fx", "Idle bobbing animation");
  // bubble
  set("t-bubble2", "Bubble");
  set("t-theme", "Theme");
  set("t-opacity", "Opacity");
  set("t-fontsize", "Text size");
  set("t-font", "Font");
  set("o-dark", "Dark");
  set("o-light", "Light");
  set("o-theme-system", "System");
  set("o-system", "System");
  set("o-rounded", "Rounded");
  set("o-mono", "Monospace");
  set("t-phrases", "Activity phrases");
  set("o-ph-off", "Off");
  set("o-ph-chef", "Chef");
  set("o-ph-wizard", "Wizard");
  set("o-ph-scientist", "Scientist");
  set("o-ph-explorer", "Explorer");
  set("t-idle", "Show idle chatter");
  set("t-messages", "Custom messages");
  set("t-msg-help", "Custom messages (one per line, leave empty for default)");
  set("t-msg-agent", "For agent");
  const allOpt = document.querySelector<HTMLOptionElement>('#msg-agent option[value="all"]');
  if (allOpt) allOpt.textContent = t("All agents");
  document.querySelectorAll<HTMLElement>(".msg-label").forEach((el) => {
    if (el.dataset.label) el.textContent = t(el.dataset.label);
  });
  // about
  set("t-tagline", "A desktop pet that watches your AI coding agents.");
  set("t-star", "Star on GitHub");
  set("t-discord", "Join the Discord");
  set("t-coffee", "Buy me a coffee");
  set("t-author", "Author");
  set("t-version2", "Version");
  // bottom bar
  set("t-preview-sub", "Try the bubble without running an agent.");
  set("t-pv-working", "Working");
  set("t-pv-waiting", "Needs you");
  set("t-pv-done", "Done");
  search.placeholder = t("Search pets by name...");
}

// ------------------------------------------------- version / quit / links ----
function initMisc() {
  getVersion().then((v) => {
    const a = document.getElementById("app-version");
    const b = document.getElementById("app-version2");
    if (a) a.textContent = v;
    if (b) b.textContent = v;
  }).catch(() => {});
  (document.getElementById("quit-btn") as HTMLButtonElement).onclick = () => { exit(0); };
  document.querySelectorAll<HTMLElement>("[data-url]").forEach((el) => {
    el.addEventListener("click", () => invoke("open_url", { url: el.dataset.url }).catch(() => {}));
  });
}

function initLang() {
  const sel = document.getElementById("lang") as HTMLSelectElement;
  sel.value = getLang();
  applyStatic();
  // Tell the tray (Rust) + the pet window about the initial language too.
  invoke("set_lang", { code: getLang() }).catch(() => {});
  sel.addEventListener("change", async () => {
    setLang(sel.value as Lang);
    applyStatic();
    renderAgents();
    showCurrent();
    invoke("set_lang", { code: getLang() }).catch(() => {});
    await emit("lang-changed", getLang());
  });
}

function esc(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] || c));
}

// Paint the filled-left part of every slider (drives the --fill CSS variable)
// and the numeric value label next to it.
function initSliders() {
  document.querySelectorAll<HTMLInputElement>('input[type="range"]').forEach((r) => {
    const val = document.getElementById(`${r.id}-val`);
    const paint = () => {
      const min = Number(r.min) || 0;
      const max = Number(r.max) || 100;
      const pct = ((Number(r.value) - min) / (max - min)) * 100;
      r.style.setProperty("--fill", `${pct}%`);
      if (val) val.textContent = r.value;
    };
    r.addEventListener("input", paint);
    paint();
  });
}

initTabs();
initLang();
loadAgents();
initPet();
initPetControls();
initBubble();
initPreview();
initNotify();
initAutostart();
initSliders();
initMisc();
