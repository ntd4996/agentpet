import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";
import { corsJson, OPTIONS } from "../../../lib/cors";
import { arenaUser, bestCareLevel } from "../../../lib/arena/auth";
import { newRun } from "../../../lib/arena/shop";
import { runsPerDay } from "../../../lib/arena/units";

export const prerender = false;
export { OPTIONS };

const today = () => new Date().toISOString().slice(0, 10);

// Starts a new run (or returns the active one). Body: { abandon?: boolean } to
// forfeit the current run first.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await arenaUser(cookies, request);
  if (!user) return corsJson({ error: "sign in" }, 401);
  const db = getDB();
  if (!db) return corsJson({ error: "no db" }, 500);
  await ensureSchema(db);

  let abandon = false;
  try { const b: any = await request.json(); abandon = !!b?.abandon; } catch {}

  const active: any = await db
    .prepare("SELECT * FROM arena_runs WHERE user_id=? AND status='active' ORDER BY created_at DESC LIMIT 1")
    .bind(user.id).first();
  if (active && !abandon) {
    return corsJson({
      run: { turn: active.turn, tokens: active.tokens, pins: active.pins, wins: active.wins,
             team: JSON.parse(active.team), shop: JSON.parse(active.shop), rerolls: active.rerolls, status: active.status },
      resumed: true,
    });
  }
  if (active && abandon) {
    await db.prepare("UPDATE arena_runs SET status='lost', updated_at=? WHERE id=?").bind(Date.now(), active.id).run();
  }

  const level = await bestCareLevel(db, user.id);
  const used: any = await db.prepare("SELECT COUNT(*) AS c FROM arena_runs WHERE user_id=? AND day=?").bind(user.id, today()).first();
  if ((used?.c ?? 0) >= runsPerDay(level)) return corsJson({ error: "daily runs used up, come back tomorrow" }, 429);

  const id = crypto.randomUUID();
  const run = newRun(id);
  await db.prepare(
    "INSERT INTO arena_runs (id, user_id, status, turn, tokens, pins, wins, team, shop, rerolls, seed, day, created_at, updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)"
  ).bind(
    id, user.id, "active", run.turn, run.tokens, run.pins, run.wins,
    JSON.stringify(run.team), JSON.stringify(run.shop), run.rerolls, run.seed, today(), Date.now(), Date.now()
  ).run();

  return corsJson({
    run: { turn: run.turn, tokens: run.tokens, pins: run.pins, wins: run.wins, team: run.team, shop: run.shop, rerolls: run.rerolls, status: run.status },
  });
};
