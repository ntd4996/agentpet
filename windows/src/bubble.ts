// The multi-agent bubble , a faithful port of the macOS AgentBubble:
// filter (hidden kinds, min-state) → sort → group by kind (×N) → cap, then
// render in one of three display modes (list / carousel / compact), each row
// laid out from the user's token order with the same animated message text
// (erase → retype → ellipsis-cycle/shimmer), state dots, and brand icons.

import { invoke } from "@tauri-apps/api/core";
import { Session, basename, agentLabel } from "./state";
import { agentIconUrl, uiIcon } from "./icons";
import { stateMessage, bubbleLine } from "./activity";
import { t } from "./i18n";

export type BubbleToken =
  | "dot" | "icon" | "title" | "project" | "separator" | "message" | "stateLabel" | "elapsed";

export interface TokenItem { token: BubbleToken; isVisible: boolean }

export const LAYOUT_PRESETS: Record<string, TokenItem[]> = {
  original: [
    { token: "dot", isVisible: true },
    { token: "icon", isVisible: true },
    { token: "project", isVisible: true },
    { token: "separator", isVisible: true },
    { token: "message", isVisible: true },
    { token: "title", isVisible: false },
    { token: "stateLabel", isVisible: false },
    { token: "elapsed", isVisible: false },
  ],
  standard: [
    { token: "dot", isVisible: true },
    { token: "icon", isVisible: true },
    { token: "title", isVisible: true },
    { token: "project", isVisible: true },
    { token: "separator", isVisible: true },
    { token: "message", isVisible: true },
    { token: "stateLabel", isVisible: false },
    { token: "elapsed", isVisible: false },
  ],
  detailed: [
    { token: "dot", isVisible: true },
    { token: "icon", isVisible: true },
    { token: "title", isVisible: true },
    { token: "project", isVisible: true },
    { token: "separator", isVisible: true },
    { token: "message", isVisible: true },
    { token: "stateLabel", isVisible: true },
    { token: "elapsed", isVisible: true },
  ],
};

export interface BubbleConfig {
  mode: "list" | "carousel" | "compact";
  grouping: "byKind" | "all";
  sortByKind: boolean;
  maxSessions: number;
  filter: "all" | "doneAndAbove" | "workingAndWaiting" | "workingOnly";
  hidden: string[];
  tokens: TokenItem[];
  separator: string;
  dotStyle: "plain" | "claude";
}

export function readBubbleConfig(): BubbleConfig {
  const ls = localStorage;
  let tokens: TokenItem[] = LAYOUT_PRESETS.original;
  try {
    const raw = ls.getItem("ap_bub_tokens");
    if (raw) {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length) tokens = parsed;
    }
  } catch {}
  let hidden: string[] = [];
  try { hidden = JSON.parse(ls.getItem("ap_bub_hidden") || "[]"); } catch {}
  return {
    mode: (ls.getItem("ap_bub_mode") as BubbleConfig["mode"]) || "carousel",
    grouping: (ls.getItem("ap_bub_grouping") as BubbleConfig["grouping"]) || "byKind",
    sortByKind: ls.getItem("ap_bub_sortkind") === "1",
    maxSessions: Math.min(10, Math.max(1, parseInt(ls.getItem("ap_bub_max") || "5", 10) || 5)),
    filter: (ls.getItem("ap_bub_filter") as BubbleConfig["filter"]) || "all",
    hidden,
    tokens,
    separator: ls.getItem("ap_bub_sep") || "·",
    dotStyle: (ls.getItem("ap_bub_dot") as BubbleConfig["dotStyle"]) || "plain",
  };
}

function filterIncludes(filter: BubbleConfig["filter"], state: string): boolean {
  switch (filter) {
    case "doneAndAbove": return state === "working" || state === "waiting" || state === "done";
    case "workingAndWaiting": return state === "working" || state === "waiting";
    case "workingOnly": return state === "working";
    default: return true;
  }
}

const RANK: Record<string, number> = { working: 4, waiting: 3, done: 2, registered: 1, idle: 0 };

export interface Group { session: Session; count: number; id: string }

/// Filter → sort → group → cap (port of AgentBubble.groupedSessions).
export function groupSessions(sessions: Session[], cfg: BubbleConfig): Group[] {
  const filtered = sessions
    .filter((s) => !cfg.hidden.includes(s.agent))
    .filter((s) => filterIncludes(cfg.filter, s.state));

  const sortByKind = cfg.grouping === "byKind" || cfg.sortByKind;
  const sorted = [...filtered].sort((a, b) => {
    if (sortByKind && a.agent !== b.agent) return a.agent < b.agent ? -1 : 1;
    if ((RANK[a.state] ?? 0) !== (RANK[b.state] ?? 0)) return (RANK[b.state] ?? 0) - (RANK[a.state] ?? 0);
    return b.updatedAt - a.updatedAt;
  });

  let groups: Group[];
  if (cfg.grouping === "byKind") {
    const seen = new Map<string, number>();
    groups = [];
    for (const s of sorted) {
      const idx = seen.get(s.agent);
      if (idx !== undefined) {
        groups[idx] = { ...groups[idx], count: groups[idx].count + 1 };
      } else {
        seen.set(s.agent, groups.length);
        groups.push({ session: s, count: 1, id: `${s.agent}-${s.session}` });
      }
    }
  } else {
    groups = sorted.map((s) => ({ session: s, count: 1, id: `${s.agent}-${s.session}` }));
  }

  if (cfg.mode === "carousel") return groups; // carousel pages through all
  return groups.slice(0, cfg.maxSessions);
}

// ---- Animated status text (port of AnimatedStatusText) ----------------------

const ERASE_MS = 80;
const TYPE_MS = 45;
const DOT_CYCLE_MS = 400;
const ELLIPSIS_FRAMES = [".", "..", "..."];

class AnimatedText {
  private current = "";
  private displayed = "";
  private base = "";
  private hasEllipsis = false;
  private typeTarget = "";
  private typeIndex = 0;
  private eraseTimer: number | null = null;
  private typeTimer: number | null = null;
  private dotTimer: number | null = null;
  private dotFrame = 0;

  constructor(public el: HTMLElement) {}

  set(message: string, animated: boolean) {
    if (message === this.current) return;
    this.current = message;
    this.cancelAll();
    this.el.classList.remove("shimmer");
    if (!animated) {
      this.displayed = message;
      this.el.textContent = message;
      return;
    }
    if (!this.displayed) this.startTyping(message);
    else this.startErasing(message);
  }

  private startErasing(next: string) {
    this.eraseTimer = window.setInterval(() => {
      const words = this.displayed.split(" ");
      words.pop();
      this.displayed = words.join(" ");
      this.el.textContent = this.displayed;
      if (!this.displayed) {
        if (this.eraseTimer) clearInterval(this.eraseTimer);
        this.eraseTimer = null;
        this.startTyping(next);
      }
    }, ERASE_MS);
  }

  private startTyping(message: string) {
    const stripped = stripEllipsis(message);
    this.base = stripped.text;
    this.hasEllipsis = stripped.hasEllipsis;
    this.typeTarget = this.hasEllipsis ? stripped.text : message;
    this.typeIndex = 0;
    this.displayed = "";
    this.el.textContent = "";
    this.typeTimer = window.setInterval(() => {
      if (this.typeIndex >= this.typeTarget.length) {
        if (this.typeTimer) clearInterval(this.typeTimer);
        this.typeTimer = null;
        this.enterStable();
        return;
      }
      this.displayed += this.typeTarget[this.typeIndex++];
      this.el.textContent = this.displayed;
    }, TYPE_MS);
  }

  private enterStable() {
    if (this.hasEllipsis) {
      this.dotFrame = 0;
      this.dotTimer = window.setInterval(() => {
        this.dotFrame = (this.dotFrame + 1) % ELLIPSIS_FRAMES.length;
        this.el.textContent = this.base + ELLIPSIS_FRAMES[this.dotFrame];
      }, DOT_CYCLE_MS);
    } else {
      this.el.classList.add("shimmer"); // sweeping highlight, like macOS
    }
  }

  cancelAll() {
    if (this.eraseTimer) clearInterval(this.eraseTimer);
    if (this.typeTimer) clearInterval(this.typeTimer);
    if (this.dotTimer) clearInterval(this.dotTimer);
    this.eraseTimer = this.typeTimer = this.dotTimer = null;
  }

  dispose() {
    this.cancelAll();
  }
}

function stripEllipsis(text: string): { text: string; hasEllipsis: boolean } {
  if (text.endsWith("…")) return { text: text.slice(0, -1).trim(), hasEllipsis: true };
  if (text.endsWith("...")) return { text: text.slice(0, -3).trim(), hasEllipsis: true };
  return { text, hasEllipsis: false };
}

// ---- Message resolution (port of AgentRow.messageText) ----------------------

function messageFor(s: Session): string {
  const mood = s.state === "working" || s.state === "registered" ? "working"
    : s.state === "waiting" ? "waiting"
    : s.state === "done" ? "done" : "idle";
  if (mood === "working") {
    if ((localStorage.getItem("ap_msg_src") || "system") === "custom") {
      const custom = bubbleLine(s.agent, "working", s.session);
      if (custom) return custom;
    }
    if (s.live.trim()) return s.live.trim();
    return stateMessage(s.state) ?? cap(s.state);
  }
  const line = bubbleLine(s.agent, mood, s.session);
  if (line) return line;
  return stateMessage(s.state) ?? cap(s.state);
}

function cap(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

/// Elapsed format, mac style: "5s", "3m", "1h 4m".
export function elapsedString(since: number, now = Date.now()): string {
  const s = Math.max(0, Math.floor((now - since) / 1000));
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  if (m < 60) return `${m}m`;
  return `${Math.floor(m / 60)}h ${m % 60}m`;
}

// ---- Renderer ----------------------------------------------------------------

export class BubbleRenderer {
  private rows = new Map<string, { el: HTMLElement; anim: AnimatedText; sig: string }>();
  private carouselIndex = 0;
  private carouselTimer: number | null = null;
  private carouselIds = "";
  private compactExpanded = false;
  private structureSig = "";

  constructor(private root: HTMLElement) {}

  /// Renders the bubble for the given (already pruned) sessions.
  render(sessions: Session[]) {
    const cfg = readBubbleConfig();
    const groups = groupSessions(sessions, cfg);
    if (!groups.length) {
      this.clear();
      this.root.hidden = true;
      return;
    }
    this.root.hidden = false;

    const ids = groups.map((g) => g.id).join(",");
    const structure = `${cfg.mode}|${cfg.grouping}|${JSON.stringify(cfg.tokens)}|${cfg.separator}|${cfg.dotStyle}`;
    if (structure !== this.structureSig) {
      this.clear();
      this.structureSig = structure;
    }

    // Single visible row gets the capsule look (mac useCapsule).
    const visibleCount = cfg.mode === "carousel" ? 1 : Math.min(groups.length, cfg.maxSessions);
    this.root.classList.toggle("capsule", visibleCount <= 1 && cfg.mode !== "compact");

    switch (cfg.mode) {
      case "carousel": this.renderCarousel(groups, cfg, ids); break;
      case "compact": this.renderCompact(groups, cfg, ids); break;
      default: this.renderList(groups, cfg);
    }
    this.tickClocks();
  }

  /// Single plain line (idle / done / celebrate) , the mac ChatBubble.
  /// Re-entrant: repeated calls with the same text are no-ops (no DOM churn,
  /// no flicker) , only an actual text change cross-fades.
  renderLine(text: string) {
    let line = this.root.querySelector<HTMLElement>(".single-line");
    if (!line) {
      this.clear(); // leaving rows mode , rebuild as a single capsule line
      line = document.createElement("div");
      line.className = "single-line";
      line.textContent = text;
      this.root.appendChild(line);
      this.root.classList.add("capsule");
      this.root.hidden = false;
      return;
    }
    this.root.hidden = false;
    if (line.textContent !== text) {
      // Cross-fade the text swap (mac contentTransition(.opacity)).
      line.classList.add("fade");
      line.textContent = text;
      requestAnimationFrame(() => line!.classList.remove("fade"));
    }
  }

  hide() {
    this.clear();
    this.root.hidden = true;
  }

  /// Refresh elapsed clocks (called by the app's 1s ticker too).
  tickClocks() {
    this.root.querySelectorAll<HTMLElement>(".clock[data-since]").forEach((el) => {
      el.textContent = elapsedString(Number(el.dataset.since));
    });
  }

  private clear() {
    for (const r of this.rows.values()) r.anim.dispose();
    this.rows.clear();
    if (this.carouselTimer) { clearInterval(this.carouselTimer); this.carouselTimer = null; }
    this.carouselIds = "";
    this.compactExpanded = false;
    this.root.classList.remove("capsule");
    this.root.textContent = "";
  }

  // ---- modes ----

  private renderList(groups: Group[], cfg: BubbleConfig) {
    this.syncRows(groups, cfg, this.root);
  }

  private renderCarousel(groups: Group[], cfg: BubbleConfig, ids: string) {
    if (ids !== this.carouselIds) {
      this.carouselIds = ids;
      this.carouselIndex = 0;
      if (this.carouselTimer) clearInterval(this.carouselTimer);
      this.carouselTimer = groups.length > 1
        ? window.setInterval(() => {
            this.carouselIndex = (this.carouselIndex + 1) % Math.max(1, this.lastCount);
            this.dirty = true;
          }, 3000)
        : null;
    }
    this.lastCount = groups.length;
    if (this.carouselIndex >= groups.length) this.carouselIndex = 0;

    let rowHost = this.root.querySelector<HTMLElement>(".car-row");
    let dots = this.root.querySelector<HTMLElement>(".car-dots");
    if (!rowHost) {
      this.root.textContent = "";
      rowHost = document.createElement("div");
      rowHost.className = "car-row";
      dots = document.createElement("div");
      dots.className = "car-dots";
      this.root.appendChild(rowHost);
      this.root.appendChild(dots);
    }
    this.syncRows([groups[this.carouselIndex]], cfg, rowHost);

    if (dots) {
      if (groups.length > 1) {
        dots.style.display = "";
        if (dots.childElementCount !== groups.length) {
          dots.textContent = "";
          for (let i = 0; i < groups.length; i++) {
            const d = document.createElement("span");
            d.className = "car-dot";
            d.onclick = () => { this.carouselIndex = i; this.dirty = true; };
            dots.appendChild(d);
          }
        }
        [...dots.children].forEach((d, i) => d.classList.toggle("sel", i === this.carouselIndex));
      } else {
        dots.style.display = "none";
      }
    }
  }
  private lastCount = 0;
  /// Set when the carousel advances; the app's render loop repaints promptly.
  dirty = false;

  private renderCompact(groups: Group[], cfg: BubbleConfig, _ids: string) {
    let head = this.root.querySelector<HTMLElement>(".cmp-head");
    let rowHost = this.root.querySelector<HTMLElement>(".cmp-rows");
    let fold = this.root.querySelector<HTMLButtonElement>(".cmp-fold");
    if (!rowHost) {
      this.root.textContent = "";
      head = document.createElement("div");
      head.className = "cmp-head";
      rowHost = document.createElement("div");
      rowHost.className = "cmp-rows";
      fold = document.createElement("button");
      fold.className = "cmp-fold";
      fold.onclick = () => { this.compactExpanded = !this.compactExpanded; this.dirty = true; };
      this.root.appendChild(head);
      this.root.appendChild(rowHost);
      this.root.appendChild(fold);
    }

    const total = groups.reduce((n, g) => n + g.count, 0);
    const kinds = groups.length;
    if (head) {
      head.textContent = kinds <= 1
        ? `${total} ${total === 1 ? t("agent") : t("agents")}`
        : `${total} ${total === 1 ? t("agent") : t("agents")} · ${kinds} ${t("kinds")}`;
    }

    const visible = this.compactExpanded ? groups : groups.slice(0, 2);
    this.syncRows(visible, cfg, rowHost);

    const hiddenCount = Math.max(0, groups.length - 2);
    if (fold) {
      fold.style.display = hiddenCount > 0 ? "" : "none";
      fold.textContent = this.compactExpanded ? t("Show less") : `+${hiddenCount} ${t("more")}`;
    }
  }

  // ---- rows ----

  /// Adds/updates/removes row elements inside `host` to match `groups`.
  private syncRows(groups: Group[], cfg: BubbleConfig, host: HTMLElement) {
    const want = new Set(groups.map((g) => g.id));
    for (const [key, row] of [...this.rows]) {
      if (!want.has(key) || row.el.parentElement !== host) {
        row.anim.dispose();
        row.el.remove();
        this.rows.delete(key);
      }
    }

    let prev: HTMLElement | null = null;
    for (const g of groups) {
      let row = this.rows.get(g.id);
      if (!row) {
        const el = this.buildRow(cfg);
        host.insertBefore(el.el, prev ? prev.nextSibling : host.firstChild);
        this.rows.set(g.id, el);
        row = el;
      }
      this.updateRow(row, g, cfg);
      // Keep DOM order without re-appending (which restarts CSS animations).
      if (prev && prev.nextSibling !== row.el) host.insertBefore(row.el, prev.nextSibling);
      else if (!prev && host.firstChild !== row.el) host.insertBefore(row.el, host.firstChild);
      prev = row.el;
    }
  }

  private buildRow(cfg: BubbleConfig): { el: HTMLElement; anim: AnimatedText; sig: string } {
    const el = document.createElement("div");
    el.className = "brow";
    let anim: AnimatedText | null = null;
    for (const item of cfg.tokens) {
      if (!item.isVisible) continue;
      switch (item.token) {
        case "dot": {
          const d = document.createElement("span");
          d.className = `sdot ${cfg.dotStyle}`;
          el.appendChild(d);
          break;
        }
        case "icon": {
          const slot = document.createElement("span");
          slot.className = "icon-slot";
          el.appendChild(slot);
          break;
        }
        case "title": {
          const s = document.createElement("span");
          s.className = "rtitle";
          el.appendChild(s);
          break;
        }
        case "project": {
          const s = document.createElement("span");
          s.className = "rproject";
          el.appendChild(s);
          break;
        }
        case "separator": {
          const s = document.createElement("span");
          s.className = "rsep";
          s.textContent = cfg.separator;
          el.appendChild(s);
          break;
        }
        case "message": {
          const s = document.createElement("span");
          s.className = "amsg";
          el.appendChild(s);
          anim = new AnimatedText(s);
          break;
        }
        case "stateLabel": {
          const s = document.createElement("span");
          s.className = "rstate";
          el.appendChild(s);
          break;
        }
        case "elapsed": {
          const s = document.createElement("span");
          s.className = "clock";
          el.appendChild(s);
          break;
        }
      }
    }
    const badge = document.createElement("span");
    badge.className = "xn";
    badge.style.display = "none";
    el.appendChild(badge);
    return { el, anim: anim ?? new AnimatedText(document.createElement("span")), sig: "" };
  }

  private updateRow(row: { el: HTMLElement; anim: AnimatedText; sig: string }, g: Group, _cfg: BubbleConfig) {
    const s = g.session;
    const el = row.el;
    el.dataset.state = s.state;
    el.classList.toggle("waiting", s.state === "waiting");

    // Click a row to focus the terminal running it (Warp deep-link; see the
    // focus_terminal Rust command). Highlight + pointer only when focusable.
    const canFocus = !!(s.terminalProgram || s.terminalFocusUrl);
    el.classList.toggle("focusable", canFocus);
    el.onclick = canFocus
      ? () => { void invoke("focus_terminal", { program: s.terminalProgram, focusUrl: s.terminalFocusUrl }); }
      : null;

    const dot = el.querySelector<HTMLElement>(".sdot");
    if (dot) dot.classList.toggle("spin", s.state !== "idle");

    const slot = el.querySelector<HTMLElement>(".icon-slot");
    if (slot) {
      // Per-agent icon override (Settings → Agent icons): brand logo or symbol.
      const choice = localStorage.getItem(`ap_icon_${s.agent}`) ?? `brand:${s.agent}`;
      if (slot.dataset.choice !== choice) {
        slot.dataset.choice = choice;
        slot.title = agentLabel(s.agent);
        if (choice.startsWith("sym:")) {
          slot.innerHTML = uiIcon(choice.slice(4));
          slot.className = "icon-slot sym";
        } else if (choice.startsWith("emoji:")) { // pre-SVG saves
          slot.textContent = choice.slice(6);
          slot.className = "icon-slot emoji";
        } else {
          const url = agentIconUrl(choice.slice(6));
          slot.className = "icon-slot";
          slot.innerHTML = url ? `<img class="aicon" src="${url}" alt="">` : "";
        }
      }
    }

    const title = el.querySelector<HTMLElement>(".rtitle");
    if (title) {
      title.textContent = s.title;
      title.style.display = s.title ? "" : "none";
    }

    const project = el.querySelector<HTMLElement>(".rproject");
    if (project) project.textContent = s.project ? basename(s.project) : s.session;

    row.anim.set(messageFor(s), s.state !== "done");

    const state = el.querySelector<HTMLElement>(".rstate");
    if (state) state.textContent = t(cap(s.state));

    const clock = el.querySelector<HTMLElement>(".clock");
    if (clock) {
      clock.dataset.since = String(s.stateSince);
      clock.textContent = elapsedString(s.stateSince);
    }

    const badge = el.querySelector<HTMLElement>(".xn");
    if (badge) {
      badge.style.display = g.count > 1 ? "" : "none";
      badge.textContent = `×${g.count}`;
    }
  }
}
