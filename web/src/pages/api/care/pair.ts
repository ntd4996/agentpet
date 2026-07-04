import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";
import { corsJson, OPTIONS } from "../../../lib/cors";

export const prerender = false;
export { OPTIONS };

// The desktop app exchanges a pairing code (shown on the profile page) for a
// long-lived device token. The code is single-use and expires after 10 minutes.
export const POST: APIRoute = async ({ request }) => {
  let code = "";
  try {
    const body: any = await request.json();
    code = String(body?.code ?? "").trim().toUpperCase();
  } catch {}
  if (!/^[A-Z2-9]{6}$/.test(code)) return corsJson({ error: "bad code" }, 400);

  const db = getDB();
  if (!db) return corsJson({ error: "no db" }, 500);
  await ensureSchema(db);

  const row: any = await db
    .prepare("SELECT user_id, expires_at FROM care_pair_codes WHERE code=?")
    .bind(code)
    .first();
  if (!row || row.expires_at < Date.now()) return corsJson({ error: "expired" }, 404);

  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  const token = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");

  await db.batch([
    db.prepare("DELETE FROM care_pair_codes WHERE code=?").bind(code),
    db.prepare("INSERT INTO care_devices (token, user_id, created_at) VALUES (?,?,?)")
      .bind(token, row.user_id, Date.now()),
  ]);

  return corsJson({ token });
};
