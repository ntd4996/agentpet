// Per-project, per-agent daily token usage , a TypeScript port of the macOS
// ProjectUsageStore. Logs where tokens go so the web dashboard can show it.
// Pushed with the same device token as care sync; fully local until connected.

import { token as syncToken } from "./sync";

const BASE = "https://agentpet.thenightwatcher.online";
const STORE_KEY = "ap_usage";
const DIRTY_KEY = "ap_usage_dirty";

interface Row {
  projectId: string;
  projectName: string;
  agent: string;
  day: string;
  tokens: number;
  sessions: number;
  costUSD?: number;
  /// Breakdown (Claude only). `tokens` stays input+output, the pet's XP basis;
  /// cache is tracked separately and never feeds the pet.
  inputTokens?: number;
  outputTokens?: number;
  cacheRead?: number;
  cacheWrite?: number;
}

export interface Breakdown { input?: number; output?: number; cacheRead?: number; cacheWrite?: number }

function fnv1a(s: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return "p" + (h >>> 0).toString(16).padStart(8, "0");
}

/// Stable id for a project path (shared with per-project pet mapping).
export function projectId(path: string): string {
  return fnv1a(path);
}

function projectIdentity(path: string): { id: string; name: string } {
  const parts = path.replace(/[\\/]+$/, "").split(/[\\/]/);
  const last = parts[parts.length - 1] || path;
  return { id: fnv1a(path), name: last.slice(0, 60) };
}

function today(): string {
  return dayString(new Date());
}
function dayString(d: Date): string {
  const y = d.getFullYear(), m = d.getMonth() + 1, day = d.getDate();
  return `${y.toString().padStart(4, "0")}-${m.toString().padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

// Keep ~120 days of per-day rows (matches macOS ProjectUsageStore.pruneOld); the
// zero-padded YYYY-MM-DD keys compare lexicographically, so a string cutoff works.
const RETAIN_DAYS = 120;
function prune(store: Record<string, Row>) {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - RETAIN_DAYS);
  const cut = dayString(cutoff);
  for (const [k, r] of Object.entries(store)) {
    if (r.day < cut) delete store[k];
  }
}

function load(): Record<string, Row> {
  try { return JSON.parse(localStorage.getItem(STORE_KEY) || "{}"); } catch { return {}; }
}
function save(store: Record<string, Row>) { localStorage.setItem(STORE_KEY, JSON.stringify(store)); }
function loadDirty(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(DIRTY_KEY) || "[]")); } catch { return new Set(); }
}
function saveDirty(d: Set<string>) { localStorage.setItem(DIRTY_KEY, JSON.stringify([...d])); }

/// Shown for usage from agents whose hook carries no workspace (Antigravity IDE).
export const NO_PROJECT = "(no project)";

function record(project: string, agent: string, tokens: number, sessions: number, cost = 0, bd: Breakdown = {}) {
  if (!agent || (tokens <= 0 && sessions <= 0)) return;
  const { id, name } = projectIdentity(project || NO_PROJECT);
  const day = today();
  const key = `${id}|${agent}|${day}`;
  const store = load();
  const r = store[key] || { projectId: id, projectName: name, agent, day, tokens: 0, sessions: 0, costUSD: 0 };
  r.tokens += tokens;
  r.sessions += sessions;
  r.costUSD = (r.costUSD || 0) + cost;
  r.inputTokens = (r.inputTokens || 0) + (bd.input || 0);
  r.outputTokens = (r.outputTokens || 0) + (bd.output || 0);
  r.cacheRead = (r.cacheRead || 0) + (bd.cacheRead || 0);
  r.cacheWrite = (r.cacheWrite || 0) + (bd.cacheWrite || 0);
  r.projectName = name;
  store[key] = r;
  prune(store);
  save(store);
  const dirty = loadDirty();
  dirty.add(key);
  saveDirty(dirty);
  schedulePush();
}

export function recordTokens(project: string, agent: string, tokens: number, cost = 0, bd: Breakdown = {}) { record(project, agent, tokens, 0, cost, bd); }
export function recordSession(project: string, agent: string) { record(project, agent, 0, 1); }

function monthPrefix(): string {
  const d = new Date();
  return `${d.getFullYear().toString().padStart(4, "0")}-${(d.getMonth() + 1).toString().padStart(2, "0")}`;
}

/// Estimated Claude USD cost recorded for today (all projects/agents).
export function todayCostUSD(): number {
  const t = today();
  return Object.values(load()).reduce((s, r) => (r.day === t ? s + (r.costUSD || 0) : s), 0);
}

/// Estimated Claude USD cost recorded this calendar month.
export function monthlyCostUSD(): number {
  const p = monthPrefix();
  return Object.values(load()).reduce((s, r) => (r.day.startsWith(p) ? s + (r.costUSD || 0) : s), 0);
}

export interface AgentTotal { agent: string; today: number; month: number; sessions: number }

/// Tokens and finished sessions per agent: today and this calendar month, most
/// tokens this month first. Agents with nothing this month are left out.
export function byAgent(): AgentTotal[] {
  const t = today();
  const p = monthPrefix();
  const m = new Map<string, AgentTotal>();
  for (const r of Object.values(load())) {
    if (!r.day.startsWith(p)) continue;
    const cur = m.get(r.agent) || { agent: r.agent, today: 0, month: 0, sessions: 0 };
    cur.month += r.tokens;
    cur.sessions += r.sessions;
    if (r.day === t) cur.today += r.tokens;
    m.set(r.agent, cur);
  }
  return [...m.values()].filter((a) => a.month > 0 || a.sessions > 0).sort((a, b) => b.month - a.month);
}

/// Projects seen in usage history (for the split-pet assignment UI), most tokens
/// first. Deduped by projectId.
export function knownProjects(): { id: string; name: string }[] {
  const byId = new Map<string, { id: string; name: string; tokens: number }>();
  for (const r of Object.values(load())) {
    if (r.projectName === NO_PROJECT) continue; // not a real project: nothing to assign a pet to
    const cur = byId.get(r.projectId);
    if (cur) cur.tokens += r.tokens;
    else byId.set(r.projectId, { id: r.projectId, name: r.projectName, tokens: r.tokens });
  }
  return [...byId.values()].sort((a, b) => b.tokens - a.tokens).map(({ id, name }) => ({ id, name }));
}

let pushTimer: number | undefined;
export function schedulePush(afterMs = 30_000) {
  if (!syncToken()) return;
  clearTimeout(pushTimer);
  pushTimer = window.setTimeout(() => { void push(); }, afterMs);
}

export async function push(): Promise<void> {
  const tok = syncToken();
  if (!tok) return;
  const dirty = loadDirty();
  if (!dirty.size) return;
  const store = load();
  const snapshot = [...dirty].map((k) => store[k]).filter(Boolean) as Row[];
  if (!snapshot.length) { saveDirty(new Set()); return; }
  try {
    const res = await fetch(`${BASE}/api/usage/sync`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${tok}` },
      body: JSON.stringify({ rows: snapshot }),
    });
    if (res.status === 401) return;
    if (!res.ok) return;
    // Clear only rows unchanged since the snapshot, so tokens recorded during the
    // push stay dirty and get sent next time.
    const now = load();
    const still = loadDirty();
    for (const s of snapshot) {
      const k = `${s.projectId}|${s.agent}|${s.day}`;
      const cur = now[k];
      if (cur && cur.tokens === s.tokens && cur.sessions === s.sessions && (cur.costUSD || 0) === (s.costUSD || 0)
        && (cur.cacheRead || 0) === (s.cacheRead || 0)) still.delete(k);
    }
    saveDirty(still);
  } catch {}
}
