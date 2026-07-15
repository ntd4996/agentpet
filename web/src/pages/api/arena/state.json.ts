import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";
import { corsJson, OPTIONS } from "../../../lib/cors";
import { arenaUser, bestCareLevel } from "../../../lib/arena/auth";
import { careTitle, runsPerDay, RULES } from "../../../lib/arena/units";

export const prerender = false;
export { OPTIONS };

const today = () => new Date().toISOString().slice(0, 10);

// Current arena profile + active run (if any).
export const GET: APIRoute = async ({ cookies, request }) => {
  const user = await arenaUser(cookies, request);
  if (!user) return corsJson({ error: "sign in" }, 401);
  const db = getDB();
  if (!db) return corsJson({ error: "no db" }, 500);
  await ensureSchema(db);

  const [run, stats, level, used] = await Promise.all([
    db.prepare("SELECT * FROM arena_runs WHERE user_id=? AND status='active' ORDER BY created_at DESC LIMIT 1").bind(user.id).first(),
    db.prepare("SELECT crowns, runs, best_wins FROM arena_stats WHERE user_id=?").bind(user.id).first(),
    bestCareLevel(db, user.id),
    db.prepare("SELECT COUNT(*) AS c FROM arena_runs WHERE user_id=? AND day=?").bind(user.id, today()).first(),
  ]);

  return corsJson({
    user: { id: user.id, login: user.login, avatar: user.avatar ?? null },
    careLevel: level,
    title: careTitle(level),
    runsToday: (used as any)?.c ?? 0,
    runsPerDay: runsPerDay(level),
    crowns: (stats as any)?.crowns ?? 0,
    bestWins: (stats as any)?.best_wins ?? 0,
    rules: RULES,
    run: run
      ? {
          turn: (run as any).turn, tokens: (run as any).tokens, pins: (run as any).pins,
          wins: (run as any).wins, team: JSON.parse((run as any).team), shop: JSON.parse((run as any).shop),
          rerolls: (run as any).rerolls, status: (run as any).status,
        }
      : null,
  });
};
