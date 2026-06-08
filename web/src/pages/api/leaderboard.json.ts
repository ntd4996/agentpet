import type { APIRoute } from "astro";
import { getDB, ensureSchema, creatorCounts } from "../../lib/db";

export const prerender = false;

// Top pets by likes + top fans (most likes given) + top creators (most approved
// community pets). Public + cacheable.
export const GET: APIRoute = async () => {
  const db = getDB();
  const pets: Array<{ slug: string; likes: number }> = [];
  const fans: Array<{ login: string; avatar: string; count: number }> = [];
  let creators: Array<{ login: string; avatar: string | null; count: number }> = [];

  if (db) {
    await ensureSchema(db);
    const p: any = await db.prepare("SELECT slug, likes FROM pet_stats WHERE likes > 0 ORDER BY likes DESC, slug ASC LIMIT 20").all();
    for (const r of p?.results ?? []) pets.push({ slug: r.slug, likes: r.likes });

    const f: any = await db
      .prepare(
        "SELECT u.login AS login, u.avatar AS avatar, COUNT(*) AS count FROM pet_likes l JOIN users u ON u.id = l.user_id GROUP BY l.user_id ORDER BY count DESC, login ASC LIMIT 20"
      )
      .all();
    for (const r of f?.results ?? []) fans.push({ login: r.login, avatar: r.avatar, count: r.count });

    creators = await creatorCounts(db, 20);
  }

  return new Response(JSON.stringify({ pets, fans, creators }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=30" },
  });
};
