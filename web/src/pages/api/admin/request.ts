import type { APIRoute } from "astro";
import { adminUser } from "../../../lib/admin";
import { getDB, ensureSchema, setRequestStatus, deleteRequest } from "../../../lib/db";

export const prerender = false;

// Admin-only: moderate a request. Body: { id, action: fulfill|reopen|delete }.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await adminUser(cookies);
  if (!user) return json({ error: "forbidden" }, 403);

  let body: any;
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const id = String(body?.id || "");
  const action = String(body?.action || "");
  if (!id) return json({ error: "id required" }, 400);

  const db = getDB();
  if (!db) return json({ error: "no db" }, 500);
  await ensureSchema(db);

  if (action === "fulfill") { await setRequestStatus(db, id, "fulfilled"); return json({ ok: true, status: "fulfilled" }); }
  if (action === "reopen") { await setRequestStatus(db, id, "open"); return json({ ok: true, status: "open" }); }
  if (action === "delete") { await deleteRequest(db, id); return json({ ok: true, deleted: true }); }
  return json({ error: "bad action" }, 400);
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
