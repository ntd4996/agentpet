// Tracks live agent sessions and derives the pet's mood , a port of the macOS
// SessionStore + MoodResolver. The live activity text is formatted once per
// event (like the macOS app formats at payload-decode time), so the whimsical
// phrase doesn't re-roll on every render tick.

import { activityMessage } from "./activity";

export interface Session {
  agent: string;
  session: string;
  state: string;
  project: string;
  /// Live activity line frozen at event time ("Brewing…", "Editing X…").
  live: string;
  /// Conversation title from the transcript (Claude), when known.
  title: string;
  tool: string;
  updatedAt: number;
  stateSince: number;
  /// Terminal this session runs in (for click-to-focus). Sticky.
  terminalProgram: string;
  terminalFocusUrl: string;
}

export interface AgentEventPayload {
  agent: string;
  state: string;
  session: string;
  project: string;
  message: string;
  tool?: string;
  file?: string;
  desc?: string;
  event?: string;
  title?: string | null;
  ts?: number;
  terminalProgram?: string;
  terminalFocusUrl?: string;
}

const PRIORITY: Record<string, number> = { working: 4, waiting: 3, done: 2, registered: 1, idle: 0 };
// Timeouts mirror the macOS SessionStore: done sessions linger briefly, then
// drop; sessions that go quiet are removed (the agent died without a Stop).
const DONE_LINGER_MS = 30_000;
const STALE_ACTIVE_MS = 300_000;
const STALE_REGISTERED_MS = 90_000;

export class SessionStore {
  private sessions = new Map<string, Session>();

  update(e: AgentEventPayload) {
    const key = `${e.agent}:${e.session}`;
    // Queued events replay with their original timestamp so sessions that
    // ended while the app was closed prune instead of resurrecting.
    const now = e.ts && e.ts > 0 ? e.ts : Date.now();
    const prev = this.sessions.get(key);

    // Live activity: explicit description (Bash) wins, else the themed
    // formatter, else "Tool · file", else keep nothing (state label shows).
    const live =
      e.desc?.trim() ||
      activityMessage(e.event ?? "", e.tool ?? "", e.file || undefined, e.message) ||
      (e.tool && e.file ? `${e.tool} · ${basename(e.file)}` : "") ||
      (e.tool ? `Using ${e.tool}` : "") ||
      prev?.live ||
      "";

    this.sessions.set(key, {
      agent: e.agent,
      session: e.session,
      state: e.state,
      project: e.project || prev?.project || "",
      live,
      title: e.title ?? prev?.title ?? "",
      tool: e.tool ?? "",
      updatedAt: now,
      stateSince: prev && prev.state === e.state ? prev.stateSince : now,
      terminalProgram: e.terminalProgram || prev?.terminalProgram || "",
      terminalFocusUrl: e.terminalFocusUrl || prev?.terminalFocusUrl || "",
    });
  }

  remove(session: string) {
    for (const k of [...this.sessions.keys()]) {
      if (k.endsWith(`:${session}`)) this.sessions.delete(k);
    }
  }

  /// Insert a session verbatim (snapshot sync between windows).
  seed(s: Session) {
    this.sessions.set(`${s.agent}:${s.session}`, s);
  }

  snapshot(): Session[] {
    return [...this.sessions.values()];
  }

  removeKey(key: string) {
    this.sessions.delete(key);
  }

  clear() {
    this.sessions.clear();
  }

  /// Drop done/stale sessions; returns the list (highest priority first).
  active(): Session[] {
    const now = Date.now();
    for (const [k, s] of [...this.sessions]) {
      const quiet = now - s.updatedAt;
      if (s.state === "done" && quiet > DONE_LINGER_MS) this.sessions.delete(k);
      else if (s.state === "registered" && quiet > STALE_REGISTERED_MS) this.sessions.delete(k);
      else if ((s.state === "working" || s.state === "waiting") && quiet > STALE_ACTIVE_MS) this.sessions.delete(k);
    }
    return [...this.sessions.values()].sort(
      (a, b) => (PRIORITY[b.state] ?? 0) - (PRIORITY[a.state] ?? 0) || b.updatedAt - a.updatedAt
    );
  }

  topState(): string {
    return this.active()[0]?.state ?? "idle";
  }
}

/// Aggregate pet mood (port of MoodResolver): running work wins; `registered`
/// (agent open but idle) is not "working". `celebrate` is a transient the
/// caller layers on top when entering done.
export function aggregateMood(sessions: Session[]): "working" | "waiting" | "done" | "idle" {
  if (sessions.some((s) => s.state === "working")) return "working";
  if (sessions.some((s) => s.state === "waiting")) return "waiting";
  if (sessions.some((s) => s.state === "done")) return "done";
  return "idle";
}

export function basename(p: string): string {
  return p.split(/[\\/]/).filter(Boolean).pop() ?? p;
}

/// Short display label for an agent kind (port of TickerFormatter.agentLabel).
export function agentLabel(kind: string): string {
  switch (kind) {
    case "claude": return "Claude";
    case "cursor": return "Cursor";
    case "codex": return "Codex";
    case "gemini": return "Gemini";
    case "opencode": return "Opencode";
    case "windsurf": return "Windsurf";
    case "antigravity": return "Antigravity";
    case "copilot": return "Copilot";
    case "kiro": return "Kiro";
    default: return "Agent";
  }
}
