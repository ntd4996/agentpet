import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { Pet } from "./pet";
import { SessionStore } from "./state";
import { loadCatalog, savedSlug, saveSlug } from "./catalog";
import { t, setLang, type Lang } from "./i18n";
import { themePhrase } from "./activity";
import { sendNotification, isPermissionGranted, requestPermission } from "@tauri-apps/plugin-notification";

function msgFor(state: string, seed: string, agent: string | undefined, live: string): string {
  const custom = customLine(state, seed, agent);
  if (custom) return custom;
  const theme = localStorage.getItem("ap_theme_phrases") || "off";
  if (theme !== "off") {
    const p = themePhrase(theme, state, seed);
    if (p) return p;
  }
  return live || t(STATE_LABEL[state] ?? "");
}

const canvas = document.getElementById("pet") as HTMLCanvasElement;
const bubble = document.getElementById("bubble") as HTMLDivElement;
const pet = new Pet(canvas);
const store = new SessionStore();

const IDLE_LINES = [
  "Let's grill some bugs.",
  "Tiny commit, tiny dopamine.",
  "The build is quiet. Too quiet.",
  "Ship something small.",
];
const STATE_LABEL: Record<string, string> = {
  working: "Working", waiting: "Needs you", done: "Done", registered: "Ready", idle: "Idle",
};

// --- bubble customization (theme / opacity / custom messages) ----------------
const FONT_FAMILIES: Record<string, string> = {
  system: '"Segoe UI", system-ui, sans-serif',
  rounded: '"Segoe UI Rounded", "Nunito", "Segoe UI", sans-serif',
  mono: 'Consolas, "Courier New", monospace',
};

function applyBubble() {
  let theme = localStorage.getItem("ap_theme") || "dark";
  if (theme === "system") theme = matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  const op = (parseInt(localStorage.getItem("ap_opacity") || "92", 10) || 92) / 100;
  const r = document.documentElement.style;
  if (theme === "light") {
    r.setProperty("--bubble-bg", `rgba(255,255,255,${op})`);
    r.setProperty("--bubble-fg", "#1a1d2e");
    r.setProperty("--bubble-border", "rgba(0,0,0,0.08)");
  } else {
    r.setProperty("--bubble-bg", `rgba(22,24,38,${op})`);
    r.setProperty("--bubble-fg", "#ffffff");
    r.setProperty("--bubble-border", "rgba(255,255,255,0.10)");
  }
  r.setProperty("--bubble-font-size", `${parseInt(localStorage.getItem("ap_font_size") || "12", 10) || 12}px`);
  r.setProperty("--bubble-font-family", FONT_FAMILIES[localStorage.getItem("ap_font_family") || "system"] ?? FONT_FAMILIES.system);
}
applyBubble();

// Pet size + idle bob FX.
function applyPet() {
  const size = (parseInt(localStorage.getItem("ap_pet_size") || "100", 10) || 100) / 100;
  canvas.style.transform = `scale(${size})`;
  canvas.style.transformOrigin = "bottom center";
  canvas.classList.toggle("bob", localStorage.getItem("ap_fx") !== "0");
}

// Simple synthesized chimes (no audio assets needed).
let audioCtx: AudioContext | null = null;
function beep(freq: number) {
  if (localStorage.getItem("ap_sound") === "0") return;
  try {
    audioCtx = audioCtx || new AudioContext();
    const o = audioCtx.createOscillator();
    const g = audioCtx.createGain();
    o.type = "sine";
    o.frequency.value = freq;
    g.gain.value = 0.05;
    o.connect(g);
    g.connect(audioCtx.destination);
    o.start();
    o.stop(audioCtx.currentTime + 0.13);
  } catch {}
}
applyPet();

// A stable custom line for a state (seeded by session id). Per-agent overrides
// the "all" set; returns null when nothing custom is set (use the default).
function customLine(state: string, seed: string, agent?: string): string | null {
  const keys = agent ? [`ap_msg_${agent}_${state}`, `ap_msg_all_${state}`] : [`ap_msg_all_${state}`];
  for (const k of keys) {
    const raw = localStorage.getItem(k);
    if (!raw) continue;
    const lines = raw.split("\n").map((s) => s.trim()).filter(Boolean);
    if (!lines.length) continue;
    let h = 5381;
    for (const c of seed) h = (Math.imul(h, 33) + c.charCodeAt(0)) | 0;
    return lines[Math.abs(h) % lines.length];
  }
  return null;
}

// --- pick + load a pet sprite -------------------------------------------------
(async () => {
  const custom = localStorage.getItem("ap_pet_custom");
  if (custom) { pet.load(custom); return; } // user's own spritesheet
  const pets = await loadCatalog();
  if (!pets.length) return;
  const slug = savedSlug();
  const chosen = pets.find((p) => p.slug === slug) ?? pets[Math.floor(pets.length / 2)];
  saveSlug(chosen.slug);
  pet.load(chosen.spritesheetUrl);
})();

// --- render loop for state + bubble ------------------------------------------
function render() {
  const active = store.active().filter((s) => s.state !== "idle");
  pet.setState(active[0]?.state ?? "idle");

  if (active.length) {
    // Show every active agent (multi-agent), one row each, capped.
    bubble.innerHTML = active.slice(0, 4).map((s) => {
      const label = t(STATE_LABEL[s.state] ?? "");
      const msg = msgFor(s.state, s.session, s.agent, s.message);
      const proj = s.project ? s.project.split(/[\\/]/).pop() : "";
      return `<div class="brow" data-state="${esc(s.state)}"><span class="dot"></span>` +
        `<span class="agent">${esc(s.agent)}</span>${proj ? " · " + esc(proj) : ""} ` +
        `${esc(msg)}<span class="state">${esc(label)}</span></div>`;
    }).join("");
    bubble.hidden = false;
  } else {
    bubble.hidden = true;
  }
}
setInterval(render, 500);

function esc(s: string): string {
  return s.replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c] || c));
}

// --- notifications ------------------------------------------------------------
let notifyReady = false;
(async () => {
  try { notifyReady = (await isPermissionGranted()) || (await requestPermission()) === "granted"; } catch {}
})();
const lastState = new Map<string, string>();
function maybeNotify(e: { agent: string; session: string; state: string; project: string }) {
  const key = `${e.agent}:${e.session}`;
  const prev = lastState.get(key);
  lastState.set(key, e.state);
  if (e.state === prev) return;
  if (e.state !== "done" && e.state !== "waiting") return;
  beep(e.state === "done" ? 880 : 560); // chime (gated by ap_sound)
  if (!notifyReady || localStorage.getItem("ap_notify") === "0") return;
  const proj = (e.project ? e.project.split(/[\\/]/).pop() : "") || e.agent;
  const label = t(e.state === "done" ? "Done" : "Needs you");
  try { sendNotification({ title: `AgentPet , ${label}`, body: `${e.agent} · ${proj}` }); } catch {}
}

// --- agent events from the Rust listener -------------------------------------
listen<any>("agent-event", (e) => { maybeNotify(e.payload); store.update(e.payload); render(); });
listen<string>("agent-end", (e) => {
  for (const k of [...lastState.keys()]) if (k.endsWith(`:${e.payload}`)) lastState.delete(k);
  store.remove(e.payload);
  render();
});
// Pet changed from the Settings window.
listen<{ slug: string; url: string }>("set-pet", (e) => {
  pet.load(e.payload.url);
  saveSlug(e.payload.slug);
});
// Language changed from Settings , re-render the bubble in the new language.
listen<Lang>("lang-changed", (e) => { setLang(e.payload); render(); });
// Bubble theme / opacity / messages changed from Settings.
listen("bubble-changed", () => { applyBubble(); applyPet(); render(); });

// --- interactions ------------------------------------------------------------
// Drag the pet to reposition it. Settings/Quit live in the tray menu (the
// overlay is frameless, and starting an OS drag here would swallow clicks).
canvas.addEventListener("mousedown", async (e) => {
  if (e.button === 0) await getCurrentWindow().startDragging();
});

// Occasional idle chatter.
setInterval(() => {
  if (localStorage.getItem("ap_idle") === "0") return; // idle chatter disabled
  if (store.topState() === "idle") {
    const theme = localStorage.getItem("ap_theme_phrases") || "off";
    bubble.textContent =
      customLine("idle", "idle") ||
      (theme !== "off" ? themePhrase(theme, "idle", String(Date.now())) : null) ||
      t(IDLE_LINES[Math.floor(Date.now() / 1000) % IDLE_LINES.length]);
    bubble.hidden = false;
    setTimeout(() => { if (store.topState() === "idle") bubble.hidden = true; }, 4000);
  }
}, 30000);
