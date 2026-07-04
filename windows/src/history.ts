// Session history , a lightweight port of the macOS SessionArchive store. Logs
// each finished session (agent, project, title, duration) to localStorage and
// keeps ~90 days, for the History tab.

export interface HistoryEntry {
  id: string;
  agent: string;
  project: string;
  title: string;
  startedAt: number; // ms
  endedAt: number;   // ms
}

const KEY = "ap_history";
const MAX_DAYS = 90;
const MAX_ENTRIES = 2000;

export function list(): HistoryEntry[] {
  try { return JSON.parse(localStorage.getItem(KEY) || "[]"); } catch { return []; }
}

export function log(e: HistoryEntry) {
  if (!e.id) return;
  const cutoff = Date.now() - MAX_DAYS * 86_400_000;
  const all = list().filter((x) => x.endedAt >= cutoff);
  // Replace an existing entry for the same session (a session can finish twice
  // across turns); keep the latest.
  const idx = all.findIndex((x) => x.id === e.id && x.startedAt === e.startedAt);
  if (idx >= 0) all[idx] = e; else all.push(e);
  all.sort((a, b) => b.endedAt - a.endedAt);
  localStorage.setItem(KEY, JSON.stringify(all.slice(0, MAX_ENTRIES)));
}
