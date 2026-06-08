import type { APIRoute } from "astro";
import { currentUser } from "../../../lib/admin";
import { getDB, ensureSchema, getRequest, toggleRequestVote } from "../../../lib/db";

export const prerender = false;

// Toggle the signed-in user's vote on a request. Body: { id }.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await currentUser(cookies);
  if (!user) return json({ error: "sign in to vote" }, 401);

  let body: any;
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const id = String(body?.id || "");
  if (!id) return json({ error: "id required" }, 400);

  const db = getDB();
  if (!db) return json({ error: "unavailable" }, 500);
  await ensureSchema(db);
  if (!(await getRequest(db, id))) return json({ error: "not found" }, 404);
  const res = await toggleRequestVote(db, id, user.id);
  return json({ ok: true, id, ...res });
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
