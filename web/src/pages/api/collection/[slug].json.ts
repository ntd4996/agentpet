import type { APIRoute } from "astro";
import { getDB, ensureSchema, getCollection, collectionSlugs } from "../../../lib/db";

export const prerender = false;

// Public: one collection's metadata + member slugs. The page maps slugs to names
// via /api/pets.json (so the origin stays hidden and names stay consistent).
export const GET: APIRoute = async ({ params }) => {
  const slug = params.slug ?? "";
  const db = getDB();
  if (!db) return new Response(JSON.stringify({ error: "unavailable" }), { status: 500 });
  await ensureSchema(db);
  const col = await getCollection(db, slug);
  if (!col) return new Response(JSON.stringify({ error: "not found" }), { status: 404 });
  const slugs = await collectionSlugs(db, col.id);
  return new Response(JSON.stringify({ title: col.title, slug: col.slug, description: col.description, slugs }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=60" },
  });
};
