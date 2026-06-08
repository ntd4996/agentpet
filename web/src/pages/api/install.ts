import type { APIRoute } from "astro";
import { getDB, ensureSchema, incrementInstall } from "../../lib/db";

export const prerender = false;

// Records a pet install. The AgentPet desktop app posts here (fire-and-forget) after
// it successfully downloads a pet pack, so install counts are real (not derived).
// Body: { slug }. CORS-open so the app can call it cross-origin.
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

export const OPTIONS: APIRoute = () => new Response(null, { status: 204, headers: CORS });

export const POST: APIRoute = async ({ request }) => {
  let body: any;
  try { body = await request.json(); } catch { return new Response(JSON.stringify({ error: "bad json" }), { status: 400, headers: CORS }); }
  const slug = String(body?.slug || "").trim().slice(0, 200);
  if (!slug || !/^[a-z0-9._-]+$/i.test(slug)) return new Response(JSON.stringify({ error: "bad slug" }), { status: 400, headers: CORS });

  const db = getDB();
  if (!db) return new Response(JSON.stringify({ ok: false }), { status: 200, headers: CORS });
  await ensureSchema(db);
  const count = await incrementInstall(db, slug);
  return new Response(JSON.stringify({ ok: true, slug, count }), { headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS } });
};
