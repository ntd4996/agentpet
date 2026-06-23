import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;

// The desktop app pushes per-pet care stats with its device token. Upserts:
// stats only ever move forward (MAX) so an out-of-date device can't shrink a
// pet that levelled up elsewhere.
export const POST: APIRoute = async ({ request }) => {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/.test(token)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  const db = getDB();
  if (!db) return new Response(JSON.stringify({ error: "no db" }), { status: 500 });
  await ensureSchema(db);

  const device: any = await db
    .prepare("SELECT user_id FROM care_devices WHERE token=?")
    .bind(token)
    .first();
  if (!device) return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });

  let pets: any[] = [];
  try {
    const body: any = await request.json();
    pets = Array.isArray(body?.pets) ? body.pets.slice(0, 50) : [];
  } catch {}
  if (!pets.length) {
    return new Response(JSON.stringify({ ok: true, synced: 0 }), {
      headers: { "content-type": "application/json" },
    });
  }

  const now = Date.now();
  const int = (x: any) => Math.max(0, Math.min(Number.MAX_SAFE_INTEGER, Math.floor(Number(x) || 0)));
  const thumbOf = (p: any): string | null => {
    const t = p?.thumb;
    if (typeof t !== "string" || t.length > 70_000) return null;
    return t.startsWith("data:image/png;base64,") ? t : null;
  };
  const weekOf = (p: any): string | null => {
    if (!Array.isArray(p?.week)) return null;
    const nums = p.week.slice(0, 7).map((n: any) => Math.max(0, Math.floor(Number(n) || 0)));
    return JSON.stringify(nums);
  };
  const achievementsOf = (p: any): string | null => {
    if (!Array.isArray(p?.achievements)) return null;
    const keys = p.achievements
      .filter((k: any) => typeof k === "string" && /^[a-zA-Z0-9]{1,40}$/.test(k))
      .slice(0, 40);
    return JSON.stringify(keys);
  };
  const statements = pets
    .filter((p) => typeof p?.id === "string" && p.id.length > 0 && p.id.length <= 120)
    .map((p) =>
      db
        .prepare(
          `INSERT INTO care_pets (user_id, pet_id, name, xp, tokens, meals, streak, last_fed_at, updated_at, thumb, week, achievements)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?)
           ON CONFLICT (user_id, pet_id) DO UPDATE SET
             name=excluded.name,
             xp=MAX(care_pets.xp, excluded.xp),
             tokens=MAX(care_pets.tokens, excluded.tokens),
             meals=MAX(care_pets.meals, excluded.meals),
             streak=excluded.streak,
             last_fed_at=excluded.last_fed_at,
             updated_at=excluded.updated_at,
             thumb=COALESCE(excluded.thumb, care_pets.thumb),
             week=COALESCE(excluded.week, care_pets.week),
             achievements=COALESCE(excluded.achievements, care_pets.achievements)`
        )
        .bind(
          device.user_id,
          String(p.id).slice(0, 120),
          String(p.name ?? p.id).slice(0, 60),
          int(p.xp),
          int(p.tokens),
          int(p.meals),
          int(p.streak),
          p.lastFedAt ? int(p.lastFedAt) * 1000 : null,
          now,
          thumbOf(p),
          weekOf(p),
          achievementsOf(p)
        )
    );
  if (statements.length) await db.batch(statements);

  return new Response(JSON.stringify({ ok: true, synced: statements.length }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
