import type { APIRoute } from "astro";
import { currentUser } from "../../../lib/admin";
import { getDB, ensureSchema, createRequest } from "../../../lib/db";

export const prerender = false;

// A signed-in user adds a pet request (wishlist). Body: { title, description? }.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await currentUser(cookies);
  if (!user) return json({ error: "sign in to request a pet" }, 401);

  let body: any;
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const title = String(body?.title || "").trim();
  const description = String(body?.description || "").trim();
  if (title.length < 3 || title.length > 80) return json({ error: "title must be 3-80 characters" }, 400);
  if (description.length > 400) return json({ error: "description too long" }, 400);

  const db = getDB();
  if (!db) return json({ error: "unavailable" }, 500);
  await ensureSchema(db);
  const id = crypto.randomUUID();
  await createRequest(db, { id, title, description: description || null, user_id: user.id, login: user.login, avatar: user.avatar, created_at: Date.now() });
  return json({ ok: true, id });
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
