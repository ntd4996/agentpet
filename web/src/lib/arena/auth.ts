// Arena auth: accepts the web session cookie OR a care device token (Bearer),
// so both the site and the desktop apps can play with one identity.

import { currentUser } from "../admin";
import { getDB, ensureSchema } from "../db";

export interface ArenaUser { id: number; login: string; avatar?: string | null }

export async function arenaUser(
  cookies: { get(n: string): { value: string } | undefined },
  request: Request
): Promise<ArenaUser | null> {
  const fromCookie = await currentUser(cookies);
  if (fromCookie) return { id: fromCookie.id, login: fromCookie.login, avatar: fromCookie.avatar };

  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/.test(token)) return null;
  const db = getDB();
  if (!db) return null;
  await ensureSchema(db);
  const row: any = await db
    .prepare("SELECT d.user_id AS id, u.login AS login, u.avatar AS avatar FROM care_devices d LEFT JOIN users u ON u.id = d.user_id WHERE d.token=?")
    .bind(token)
    .first();
  if (!row) return null;
  return { id: row.id, login: row.login || `user ${row.id}`, avatar: row.avatar };
}

/** The player's best raised-pet display level, for titles + daily-run perks. */
export async function bestCareLevel(db: any, userId: number): Promise<number> {
  const row: any = await db.prepare("SELECT MAX(xp) AS xp FROM care_pets WHERE user_id=?").bind(userId).first();
  const xp = Number(row?.xp) || 0;
  // display level = internal level - 1, xpToReach(n) = 60*n*(n-1)
  let level = 1;
  while (60 * (level + 1) * level <= xp) level += 1;
  return Math.max(0, level - 1);
}
