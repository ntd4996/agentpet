import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";
import { corsJson, OPTIONS } from "../../../lib/cors";
import { arenaUser } from "../../../lib/arena/auth";
import { apply, nextTurn, sanitizeTeam, type RunState, type ShopAction } from "../../../lib/arena/shop";
import { battle } from "../../../lib/arena/engine";
import { botTeam, botName } from "../../../lib/arena/bots";
import { RULES } from "../../../lib/arena/units";

export const prerender = false;
export { OPTIONS };

// One shop action, or "end" to fight this turn's battle. Server-authoritative:
// the client only ever sends intents; all state math happens here.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await arenaUser(cookies, request);
  if (!user) return corsJson({ error: "sign in" }, 401);
  const db = getDB();
  if (!db) return corsJson({ error: "no db" }, 500);
  await ensureSchema(db);

  let body: any = {};
  try { body = await request.json(); } catch { return corsJson({ error: "bad json" }, 400); }

  const row: any = await db
    .prepare("SELECT * FROM arena_runs WHERE user_id=? AND status='active' ORDER BY created_at DESC LIMIT 1")
    .bind(user.id).first();
  if (!row) return corsJson({ error: "no active run" }, 404);

  const run: RunState = {
    turn: row.turn, tokens: row.tokens, pins: row.pins, wins: row.wins,
    team: sanitizeTeam(JSON.parse(row.team)), shop: JSON.parse(row.shop),
    rerolls: row.rerolls, seed: row.seed, status: "active",
  };

  const save = () =>
    db.prepare("UPDATE arena_runs SET status=?, turn=?, tokens=?, pins=?, wins=?, team=?, shop=?, rerolls=?, updated_at=? WHERE id=?")
      .bind(run.status, run.turn, run.tokens, run.pins, run.wins,
            JSON.stringify(run.team), JSON.stringify(run.shop), run.rerolls, Date.now(), row.id).run();

  const a = String(body?.a || "");
  if (["buy", "sell", "train", "reroll", "move"].includes(a)) {
    const err = apply(run, body as ShopAction);
    if (err) return corsJson({ error: err }, 400);
    await save();
    return corsJson({ run });
  }

  if (a !== "end") return corsJson({ error: "unknown action" }, 400);
  if (!run.team.length) return corsJson({ error: "recruit at least one pet first" }, 400);

  // ------- battle: ghost snapshot at this turn (closest wins), else a bot -----
  const ghost: any = await db
    .prepare("SELECT * FROM arena_snapshots WHERE turn=? AND user_id!=? ORDER BY ABS(wins-?) ASC, RANDOM() LIMIT 1")
    .bind(run.turn, user.id, run.wins).first();
  const oppTeam = ghost ? sanitizeTeam(JSON.parse(ghost.team)) : botTeam(run.turn, `${row.id}:${run.turn}`);
  const oppName = ghost ? (ghost.login || "a rival trainer") : botName(`${row.id}:${run.turn}`);

  const result = battle(run.team, oppTeam, `${run.seed}:battle:${run.turn}`);
  const won = result.winner === 0;
  const lost = result.winner === 1;

  // Save this turn's lineup as a ghost for others (keep the pool tidy).
  await db.prepare("INSERT INTO arena_snapshots (id, user_id, login, turn, wins, team, created_at) VALUES (?,?,?,?,?,?,?)")
    .bind(crypto.randomUUID(), user.id, user.login, run.turn, run.wins, JSON.stringify(run.team), Date.now()).run();
  await db.prepare(
    "DELETE FROM arena_snapshots WHERE turn=? AND id NOT IN (SELECT id FROM arena_snapshots WHERE turn=? ORDER BY created_at DESC LIMIT 300)"
  ).bind(run.turn, run.turn).run();

  if (won) run.wins += 1;
  if (lost) run.pins -= 1;

  if (run.wins >= RULES.crownsToWin) run.status = "won";
  else if (run.pins <= 0) run.status = "lost";
  else if (run.turn >= RULES.maxTurns) run.status = "lost";
  else nextTurn(run);
  await save();

  if (run.status !== "active") {
    await db.prepare(
      `INSERT INTO arena_stats (user_id, login, crowns, runs, best_wins, updated_at) VALUES (?,?,?,?,?,?)
       ON CONFLICT(user_id) DO UPDATE SET login=excluded.login,
         crowns=arena_stats.crowns+excluded.crowns, runs=arena_stats.runs+1,
         best_wins=MAX(arena_stats.best_wins, excluded.best_wins), updated_at=excluded.updated_at`
    ).bind(user.id, user.login, run.status === "won" ? 1 : 0, 1, run.wins, Date.now()).run();
  }

  return corsJson({
    run,
    battle: { log: result.log, won, draw: result.winner === -1, opponent: oppName, ghost: !!ghost },
  });
};
