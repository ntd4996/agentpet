import type { APIRoute } from "astro";
import { getDB, ensureSchema, listCollections } from "../../lib/db";

export const prerender = false;

// Public: all collections with member counts + a few sample slugs (for thumbnails).
export const GET: APIRoute = async () => {
  const db = getDB();
  let collections: any[] = [];
  if (db) { await ensureSchema(db); collections = await listCollections(db); }
  return new Response(JSON.stringify({ collections }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=60" },
  });
};
