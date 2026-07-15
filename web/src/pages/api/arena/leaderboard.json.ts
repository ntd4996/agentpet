import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";
import { corsJson, OPTIONS } from "../../../lib/cors";

export const prerender = false;
export { OPTIONS };

// Arena leaderboard: crowns won (completed victorious runs), with avatars.
export const GET: APIRoute = async () => {
  const db = getDB();
  if (!db) return corsJson({ players: [] });
  await ensureSchema(db);
  const rows: any = await db.prepare(
    `SELECT s.user_id AS id, COALESCE(u.login, s.login) AS login, u.avatar AS avatar,
            s.crowns, s.runs, s.best_wins
     FROM arena_stats s LEFT JOIN users u ON u.id = s.user_id
     ORDER BY s.crowns DESC, s.best_wins DESC, s.runs ASC LIMIT 50`
  ).all();
  return corsJson({ players: rows?.results ?? [] });
};
