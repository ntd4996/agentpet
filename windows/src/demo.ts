// Live-preview demo panel , a port of the macOS SettingsDemoPanel. Drives a
// LOCAL list of fake agent webhooks (never the real pet): a stage with the
// selected pet + bubble, quick scenarios, an editable webhook list, and an
// "Add webhook" column. The Settings window widens while the panel is open,
// like the macOS window growing from 640 → 1380 pt.

import { getCurrentWindow, LogicalSize } from "@tauri-apps/api/window";
import { Pet } from "./pet";
import { BubbleRenderer } from "./bubble";
import { bubbleLines, PET_CHAT } from "./activity";
import { loadCatalog, savedSlug } from "./catalog";
import { agentIconUrl, uiIcon } from "./icons";
import { agentLabel, aggregateMood, type Session } from "./state";
import { t } from "./i18n";

const AGENTS = ["claude", "codex", "gemini", "cursor", "opencode", "windsurf", "antigravity"];
const EDITABLE_STATES = ["working", "waiting", "done", "idle"];

const SAMPLE_PROJECT: Record<string, string> = {
  claude: "agentpet", codex: "api-server", gemini: "ml-pipeline", cursor: "web-app",
  opencode: "cli-tools", windsurf: "dashboard", antigravity: "mobile-app",
};
const SAMPLE_TITLE: Record<string, string> = {
  claude: "Fix the login redirect", codex: "Add pagination to /pets",
  gemini: "Tune the ranking model", cursor: "Refactor the gallery grid",
};
function sampleMessage(state: string): string {
  switch (state) {
    case "working": return "Editing PetView.swift…";
    case "waiting": return "Waiting for your input";
    case "done": return t("Done");
    default: return "";
  }
}

const BASE_W = 640, BASE_H = 620, DEMO_W = 1380;

export function initDemo() {
  const panel = document.getElementById("demo-panel") as HTMLElement;
  const toggleBtn = document.getElementById("demo-toggle") as HTMLButtonElement;
  const closeBtn = document.getElementById("demo-close") as HTMLButtonElement;
  const moodChip = document.getElementById("demo-mood") as HTMLElement;
  const stageBubble = document.getElementById("demo-bubble") as HTMLElement;
  const stageCanvas = document.getElementById("demo-pet") as HTMLCanvasElement;
  const list = document.getElementById("dp-list") as HTMLElement;
  const empty = document.getElementById("dp-empty") as HTMLElement;
  const countEl = document.getElementById("dp-count") as HTMLElement;
  const agentsRoot = document.getElementById("dp-agents") as HTMLElement;

  let open = false;
  let pet: Pet | null = null;
  let bubble: BubbleRenderer | null = null;
  let sessions: Session[] = [];
  let counter = 0;
  let celebrating = false;
  let celebrateTimer: number | null = null;
  let lastAgg = "idle";
  let tick: number | null = null;

  // The stage bubble uses the same CSS vars as the real pet window; the
  // Settings window must apply them itself (and re-apply as settings change)
  // so the preview updates LIVE with theme/opacity/font size.
  function applyBubbleVars() {
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
  }

  const count = (kind: string) => sessions.filter((s) => s.agent === kind).length;
  const active = () => sessions.filter((s) => s.state === "working" || s.state === "waiting");
  const mood = () => (celebrating ? "celebrate" : aggregateMood(sessions));

  function playSound(ev: "done" | "waiting") {
    const data = localStorage.getItem(`ap_sound_${ev}_data`);
    if (data) { try { void new Audio(data).play(); return; } catch {} }
    try {
      const ctx = new AudioContext();
      const o = ctx.createOscillator(); const g = ctx.createGain();
      o.type = "sine"; o.frequency.value = ev === "done" ? 880 : 560;
      g.gain.value = 0.05; o.connect(g); g.connect(ctx.destination);
      o.start(); o.stop(ctx.currentTime + 0.13);
    } catch {}
  }

  /// Deterministic preview line for idle/done/celebrate (first of the pool).
  function previewLine(m: string): string {
    const pool = bubbleLines(null, m);
    if (pool.length) return pool[0];
    return PET_CHAT[m]?.[0] ?? "";
  }

  function addSession(kind: string, state: string) {
    counter++;
    const n = count(kind) + 1;
    const now = Date.now();
    sessions.push({
      agent: kind,
      session: `demo-${kind}-${counter}`,
      state,
      project: SAMPLE_PROJECT[kind] + (n > 1 ? ` #${n}` : ""),
      title: SAMPLE_TITLE[kind] ?? "",
      live: sampleMessage(state),
      tool: "",
      updatedAt: now,
      stateSince: now,
      terminalProgram: "",
      terminalFocusUrl: "",
    });
    after();
    paint();
  }

  function setState(id: string, state: string) {
    const s = sessions.find((x) => x.session === id);
    if (!s) return;
    s.state = state;
    s.stateSince = Date.now();
    s.live = sampleMessage(state);
    if (state === "waiting") playSound("waiting");
    after();
    paint();
  }

  function removeSession(id: string) {
    sessions = sessions.filter((x) => x.session !== id);
    after();
    paint();
  }

  /// Fire the done sound + 3s celebrate burst on the →done edge (mac `after()`).
  function after() {
    const agg = aggregateMood(sessions);
    if (agg === "done" && lastAgg !== "done") {
      playSound("done");
      celebrating = true;
      if (celebrateTimer) clearTimeout(celebrateTimer);
      celebrateTimer = window.setTimeout(() => { celebrating = false; paint(); }, 3000);
    }
    if (agg !== "done") {
      celebrating = false;
      if (celebrateTimer) clearTimeout(celebrateTimer);
    }
    lastAgg = agg;
  }

  function paint() {
    applyBubbleVars();
    const m = mood();
    moodChip.textContent = t(m.charAt(0).toUpperCase() + m.slice(1));
    moodChip.dataset.mood = m;
    pet?.setState(m);

    // Stage bubble: rows while agents are active, else the mood line.
    const multi = localStorage.getItem("ap_multi") !== "0";
    if (multi && active().length) {
      bubble?.render(active());
    } else {
      const line = m === "idle" && localStorage.getItem("ap_idle") === "0" ? "" : previewLine(m);
      if (line) bubble?.renderLine(line);
      else bubble?.hide();
    }

    // Webhook list.
    countEl.textContent = sessions.length ? String(sessions.length) : "";
    empty.style.display = sessions.length ? "none" : "";
    list.innerHTML = "";
    for (const s of sessions) {
      const row = document.createElement("div");
      row.className = "dp-row";
      const icon = agentIconUrl(s.agent);
      const meta = document.createElement("div");
      meta.className = "dp-meta";
      meta.innerHTML =
        `<span class="dp-name">${agentLabel(s.agent)}</span>` +
        `<span class="cap">${s.project}</span>`;
      if (icon) {
        const img = document.createElement("img");
        img.className = "dp-icon";
        img.src = icon;
        row.appendChild(img);
      }
      row.appendChild(meta);
      const sel = document.createElement("select");
      sel.className = "dp-state";
      sel.dataset.state = s.state;
      for (const st of EDITABLE_STATES) {
        const o = document.createElement("option");
        o.value = st;
        o.textContent = t(st.charAt(0).toUpperCase() + st.slice(1));
        if (st === s.state) o.selected = true;
        sel.appendChild(o);
      }
      sel.onchange = () => setState(s.session, sel.value);
      row.appendChild(sel);
      const del = document.createElement("button");
      del.className = "dp-del ic-btn";
      del.innerHTML = uiIcon("trash");
      del.title = t("Delete this webhook");
      del.onclick = () => removeSession(s.session);
      row.appendChild(del);
      list.appendChild(row);
    }

    // Add column ×N badges refresh.
    agentsRoot.querySelectorAll<HTMLElement>(".dp-xn").forEach((el) => {
      const n = count(el.dataset.kind!);
      el.textContent = n > 0 ? `×${n}` : "";
    });
  }

  function buildAddColumn() {
    agentsRoot.innerHTML = "";
    for (const kind of AGENTS) {
      const row = document.createElement("div");
      row.className = "dp-row";
      const icon = agentIconUrl(kind);
      if (icon) {
        const img = document.createElement("img");
        img.className = "dp-icon";
        img.src = icon;
        row.appendChild(img);
      }
      const name = document.createElement("span");
      name.className = "dp-name";
      name.textContent = agentLabel(kind);
      row.appendChild(name);
      const xn = document.createElement("span");
      xn.className = "dp-xn dim";
      xn.dataset.kind = kind;
      row.appendChild(xn);
      const spacer = document.createElement("span");
      spacer.style.flex = "1";
      row.appendChild(spacer);
      const add = document.createElement("button");
      add.className = "dp-add";
      add.innerHTML = `<span class="ui-ic">${uiIcon("plus")}</span>${t("Add")}`;
      add.onclick = () => addSession(kind, "working");
      row.appendChild(add);
      agentsRoot.appendChild(row);
    }
  }

  async function setOpen(next: boolean) {
    open = next;
    panel.hidden = !open;
    document.body.classList.toggle("demo-open", open);
    try {
      await getCurrentWindow().setSize(new LogicalSize(open ? DEMO_W : BASE_W, BASE_H));
    } catch {}
    if (open) {
      if (!pet) {
        pet = new Pet(stageCanvas);
        bubble = new BubbleRenderer(stageBubble);
        const url = localStorage.getItem("ap_pet_custom") || localStorage.getItem("ap_pet_url");
        if (url) pet.load(url);
        else {
          const pets = await loadCatalog();
          const chosen = pets.find((p) => p.slug === savedSlug()) ?? pets[0];
          if (chosen) pet.load(chosen.spritesheetUrl);
        }
        buildAddColumn();
      }
      paint();
      tick = window.setInterval(paint, 700);
    } else if (tick) {
      clearInterval(tick);
      tick = null;
    }
  }

  toggleBtn.onclick = () => setOpen(!open);
  closeBtn.onclick = () => setOpen(false);
  (document.getElementById("dp-spawn") as HTMLButtonElement).onclick = () => {
    addSession("claude", "working"); addSession("cursor", "working"); addSession("codex", "working");
  };
  (document.getElementById("dp-finish") as HTMLButtonElement).onclick = () => {
    if (!sessions.length) return;
    sessions.forEach((s) => { s.state = "done"; s.stateSince = Date.now(); s.live = sampleMessage("done"); });
    after();
    paint();
  };
  (document.getElementById("dp-clear") as HTMLButtonElement).onclick = () => {
    sessions = [];
    celebrating = false;
    if (celebrateTimer) clearTimeout(celebrateTimer);
    after();
    paint();
  };
}
