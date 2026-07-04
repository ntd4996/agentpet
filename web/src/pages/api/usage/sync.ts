import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../../lib/db";
import { corsJson, OPTIONS } from "../../../lib/cors";

export const prerender = false;
export { OPTIONS };

// The desktop app pushes per-project, per-agent daily token usage with its device
// token. Grow-only (MAX) so a stale device can't shrink a day that grew elsewhere.
export const POST: APIRoute = async ({ request }) => {
  const auth = request.headers.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  if (!/^[0-9a-f]{64}$/.test(token)) return corsJson({ error: "unauthorized" }, 401);

  const db = getDB();
  if (!db) return corsJson({ error: "no db" }, 500);
  await ensureSchema(db);

  const device: any = await db.prepare("SELECT user_id FROM care_devices WHERE token=?").bind(token).first();
  if (!device) return corsJson({ error: "unauthorized" }, 401);

  let rows: any[] = [];
  try {
    const body: any = await request.json();
    rows = Array.isArray(body?.rows) ? body.rows.slice(0, 2000) : [];
  } catch {}
  if (!rows.length) return corsJson({ ok: true, synced: 0 });

  const now = Date.now();
  const int = (x: any) => Math.max(0, Math.min(Number.MAX_SAFE_INTEGER, Math.floor(Number(x) || 0)));
  const str = (x: any, max: number) => String(x ?? "").slice(0, max);
  const isDay = (s: any) => typeof s === "string" && /^\d{4}-\d{2}-\d{2}$/.test(s);

  const statements = rows
    .filter((r) => r && typeof r.projectId === "string" && r.projectId.length > 0 && isDay(r.day) && typeof r.agent === "string" && r.agent.length > 0)
    .map((r) =>
      db.prepare(
        `INSERT INTO usage_daily (user_id, project_id, project_name, agent, day, tokens, sessions, updated_at)
         VALUES (?,?,?,?,?,?,?,?)
         ON CONFLICT (user_id, project_id, agent, day) DO UPDATE SET
           project_name=excluded.project_name,
           tokens=MAX(usage_daily.tokens, excluded.tokens),
           sessions=MAX(usage_daily.sessions, excluded.sessions),
           updated_at=excluded.updated_at`
      ).bind(
        device.user_id,
        str(r.projectId, 80),
        str(r.projectName || r.projectId, 80),
        str(r.agent, 40),
        r.day,
        int(r.tokens),
        int(r.sessions),
        now
      )
    );
  if (statements.length) await db.batch(statements);

  return corsJson({ ok: true, synced: statements.length });
};
