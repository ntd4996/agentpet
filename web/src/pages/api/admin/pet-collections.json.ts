import type { APIRoute } from "astro";
import { adminUser } from "../../../lib/admin";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;

// Admin-only: which collection ids a given pet belongs to (for the editor).
export const GET: APIRoute = async ({ cookies, url }) => {
  const user = await adminUser(cookies);
  if (!user) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
  const slug = url.searchParams.get("slug") || "";
  if (!slug) return new Response(JSON.stringify({ ids: [] }), { status: 400 });
  const db = getDB();
  if (!db) return new Response(JSON.stringify({ ids: [] }), { status: 200 });
  await ensureSchema(db);
  const r: any = await db.prepare("SELECT collection_id FROM collection_pets WHERE slug=?").bind(slug).all();
  const ids = (r?.results ?? []).map((x: any) => x.collection_id);
  return new Response(JSON.stringify({ ids }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
};
