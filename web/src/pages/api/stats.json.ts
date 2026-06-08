import type { APIRoute } from "astro";
import { getDB, ensureSchema } from "../../lib/db";

export const prerender = false;

// Public like counts (slug -> count) from the small aggregate table. Cacheable so
// repeated page loads don't re-hit D1. Per-user liked state lives in /api/my-likes.json.
export const GET: APIRoute = async () => {
  const db = getDB();
  const likes: Record<string, number> = {};
  const installs: Record<string, number> = {};
  const downloads: Record<string, number> = {};
  if (db) {
    await ensureSchema(db);
    const rows: any = await db.prepare("SELECT slug, likes FROM pet_stats WHERE likes > 0").all();
    for (const r of rows?.results ?? []) likes[r.slug] = r.likes;
    const ins: any = await db.prepare("SELECT slug, count FROM pet_installs WHERE count > 0").all();
    for (const r of ins?.results ?? []) installs[r.slug] = r.count;
    const dl: any = await db.prepare("SELECT slug, count FROM pet_downloads WHERE count > 0").all();
    for (const r of dl?.results ?? []) downloads[r.slug] = r.count;
  }
  return new Response(JSON.stringify({ likes, installs, downloads }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=120" },
  });
};
