import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;

// The desktop app pulls the user's per-pet care stats with its device token, so a
// fresh install (or a second machine) can restore each pet's level/progress
// instead of starting over. Mirrors what /api/care/sync stores.
export const GET: APIRoute = async ({ request }) => {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/.test(token)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  const db = getDB();
  if (!db) return new Response(JSON.stringify({ error: "no db" }), { status: 500 });
  await ensureSchema(db);

  const device: any = await db.prepare("SELECT user_id FROM care_devices WHERE token=?").bind(token).first();
  if (!device) return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });

  const rows: any = await db
    .prepare("SELECT pet_id, name, xp, tokens, meals, streak, last_fed_at, week, achievements FROM care_pets WHERE user_id=?")
    .bind(device.user_id)
    .all();

  const pets = (rows?.results ?? []).map((r: any) => ({
    id: r.pet_id,
    name: r.name,
    xp: r.xp ?? 0,
    tokens: r.tokens ?? 0,
    meals: r.meals ?? 0,
    streak: r.streak ?? 0,
    // Stored in ms; hand back seconds to match the app's lastFedAt unit.
    lastFedAt: r.last_fed_at ? Math.floor(r.last_fed_at / 1000) : null,
    week: safeJson(r.week, []),
    achievements: safeJson(r.achievements, []),
  }));

  return new Response(JSON.stringify({ pets }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};

function safeJson(s: any, fallback: any) {
  if (typeof s !== "string") return fallback;
  try { return JSON.parse(s); } catch { return fallback; }
}
