// Web profile / leaderboard sync , a TypeScript port of the macOS
// CareSyncController. Pairs the app to a GitHub profile with a short code, then
// pushes per-pet care stats and can restore them on a new machine. All optional;
// the pet works fully offline without ever signing in.

import * as care from "./care";
import { petDisplayName } from "./catalog";

const BASE = "https://agentpet.thenightwatcher.online";
const TOKEN_KEY = "ap_care_token";
const LOGIN_KEY = "ap_care_login";

export function token(): string | null {
  try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
}
export function signedIn(): boolean {
  return !!token();
}
export function login(): string | null {
  try { return localStorage.getItem(LOGIN_KEY); } catch { return null; }
}
export function disconnect() {
  try { localStorage.removeItem(TOKEN_KEY); localStorage.removeItem(LOGIN_KEY); } catch {}
}

/** Exchanges a 6-char pairing code for a device token, then restores + pushes. */
export async function pair(code: string): Promise<{ ok: boolean; error?: string }> {
  const clean = code.trim().toUpperCase();
  if (!/^[A-Z2-9]{6}$/.test(clean)) return { ok: false, error: "bad code" };
  try {
    const res = await fetch(`${BASE}/api/care/pair`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code: clean }),
    });
    if (res.status === 404) return { ok: false, error: "expired" };
    if (!res.ok) return { ok: false, error: "failed" };
    const d: any = await res.json();
    if (!d?.token) return { ok: false, error: "failed" };
    localStorage.setItem(TOKEN_KEY, d.token);
    await restore();
    schedulePush(1000);
    return { ok: true };
  } catch {
    return { ok: false, error: "network" };
  }
}

function petName(id: string): string {
  return petDisplayName(id);
}

/** Pushes every raised pet's stats to the profile. */
export async function push(): Promise<void> {
  const tok = token();
  if (!tok) return;
  const states = care.allStates();
  const pets = Object.entries(states).map(([id, s]) => ({
    id,
    name: petName(id),
    xp: s.xp,
    tokens: s.totalTokens,
    meals: s.totalMeals,
    streak: s.streakDays,
    lastFedAt: s.lastFedAt ? Math.floor(s.lastFedAt / 1000) : null,
    week: care.recentDays(s, 7).map((d) => d.tokens),
    achievements: s.unlockedAchievements || [],
  }));
  if (!pets.length) return;
  try {
    const res = await fetch(`${BASE}/api/care/sync`, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${tok}` },
      body: JSON.stringify({ pets }),
    });
    if (res.status === 401) disconnect();
  } catch {}
}

let pushTimer: number | undefined;
export function schedulePush(afterMs = 30_000) {
  if (!signedIn()) return;
  clearTimeout(pushTimer);
  pushTimer = window.setTimeout(() => { void push(); }, afterMs);
}

/** Pulls cloud stats and merges them grow-only into local pets. Returns count. */
export async function restore(): Promise<number> {
  const tok = token();
  if (!tok) return 0;
  let data: any;
  try {
    const res = await fetch(`${BASE}/api/care/restore`, { headers: { authorization: `Bearer ${tok}` } });
    if (res.status === 401) { disconnect(); return 0; }
    if (!res.ok) return 0;
    data = await res.json();
  } catch { return 0; }

  let changed = 0;
  for (const c of data?.pets ?? []) {
    const id = String(c.id || "");
    if (!id) continue;
    const hasProgress = (c.xp || 0) > 0 || (c.tokens || 0) > 0 || (c.meals || 0) > 0;
    const existing = care.allStates()[id];
    if (!existing && !hasProgress) continue;
    care.mutate(id, (s) => {
      // Grow-only: never shrink a pet further along on this machine.
      s.xp = Math.max(s.xp, c.xp || 0);
      s.totalTokens = Math.max(s.totalTokens, c.tokens || 0);
      s.totalMeals = Math.max(s.totalMeals, c.meals || 0);
      // Streak follows the most recent feeding (not max).
      if (c.lastFedAt) {
        const cloudFed = c.lastFedAt * 1000;
        if (s.lastFedAt == null || cloudFed > s.lastFedAt) {
          s.lastFedAt = cloudFed;
          s.streakDays = c.streak || 0;
        }
      }
      // Achievements union, then reconcile against the merged (higher) stats.
      if (Array.isArray(c.achievements) && c.achievements.length) {
        const merged = new Set([...(s.unlockedAchievements || []), ...c.achievements.map(String)]);
        s.unlockedAchievements = [...merged];
      }
      care.unlockNewAchievements(s);
    });
    changed++;
  }
  return changed;
}
