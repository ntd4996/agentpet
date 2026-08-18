// Web profile / leaderboard sync , a TypeScript port of the macOS
// CareSyncController. Pairs the app to a GitHub profile with a short code, then
// pushes per-pet care stats and can restore them on a new machine. All optional;
// the pet works fully offline without ever signing in.

import * as care from "./care";
import { petDisplayName, getLibrary } from "./catalog";
import { slice } from "./pet";

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

/// Renders a pet's first sprite frame to a small PNG data URL so the web
/// leaderboard/profile can show the actual pet , including local custom pets
/// whose sprite the site has never seen (parity with the macOS thumbDataURL).
/// Returns null if the sheet can't be loaded/read (e.g. CORS) , the site then
/// falls back to resolving the sprite by slug, or a letter.
function makeThumb(slug: string): Promise<string | null> {
  const url = getLibrary().find((p) => p.slug === slug)?.url;
  if (!url) return Promise.resolve(null);
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = "anonymous"; // CDN sends CORS so the canvas isn't tainted
    img.onload = () => {
      try {
        const rect = slice(img)[0]?.[0];
        if (!rect || rect.w <= 0 || rect.h <= 0) { resolve(null); return; }
        const cv = document.createElement("canvas");
        const ctx = cv.getContext("2d");
        if (!ctx) { resolve(null); return; }
        ctx.imageSmoothingEnabled = false; // crisp pixel art
        // Downscale until the data URL fits the server's 70k-char cap (matches
        // the macOS thumbDataURL loop); a smaller thumb beats a bare letter.
        for (const maxSide of [96, 72, 56, 44]) {
          const scale = Math.max(1, Math.floor(Math.min(maxSide / rect.w, maxSide / rect.h)));
          cv.width = rect.w * scale; cv.height = rect.h * scale;
          ctx.imageSmoothingEnabled = false;
          ctx.clearRect(0, 0, cv.width, cv.height);
          ctx.drawImage(img, rect.x, rect.y, rect.w, rect.h, 0, 0, cv.width, cv.height);
          const data = cv.toDataURL("image/png");
          if (data.length < 68_000) { resolve(data); return; }
        }
        resolve(null);
      } catch { resolve(null); }
    };
    img.onerror = () => resolve(null);
    img.src = url.startsWith("data:") ? url : url + (url.includes("?") ? "&" : "?") + "cors=1";
  });
}

/** Pushes every raised pet's stats to the profile. */
export async function push(): Promise<void> {
  const tok = token();
  if (!tok) return;
  const states = care.allStates();
  const pets = await Promise.all(Object.entries(states).map(async ([id, s]) => ({
    id,
    name: petName(id),
    xp: s.xp,
    tokens: s.totalTokens,
    meals: s.totalMeals,
    streak: s.streakDays,
    lastFedAt: s.lastFedAt ? Math.floor(s.lastFedAt / 1000) : null,
    thumb: await makeThumb(id),
    week: care.recentDays(s, 7).map((d) => d.tokens),
    achievements: s.unlockedAchievements || [],
  })));
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
          // Keep the day bookkeeping in sync with the adopted feeding, or the
          // next local feed sees a stale key and resets the streak to 1.
          s.lastFedDayKey = care.dayKey(new Date(cloudFed));
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
