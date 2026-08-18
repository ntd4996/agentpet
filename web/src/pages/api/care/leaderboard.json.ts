import type { APIRoute } from "astro";
import { getDB, ensureSchema, getOverrides } from "../../../lib/db";
import { loadManifest } from "../../../lib/pets";

export const prerender = false;

// Same sanitiser the leaderboard client uses to derive a pet's URL slug.
const urlSlug = (s: string) => String(s).replace(/[^a-zA-Z0-9 ._-]/g, "");

// Public top-companions board. `?by=tokens` ranks by lifetime tokens fed;
// anything else ranks by XP (level). The owner comes from the users table.
export const GET: APIRoute = async ({ url }) => {
  const db = getDB();
  if (!db) {
    return new Response(JSON.stringify({ pets: [] }), { headers: { "content-type": "application/json" } });
  }
  await ensureSchema(db);

  // by=tokens → lifetime tokens (Claude only); by=sessions → finished sessions
  // (fair across every agent); default → XP/level (overall).
  const by = url.searchParams.get("by");
  const orderCol = by === "tokens" ? "c.tokens" : by === "sessions" ? "c.meals" : "c.xp";
  const guard = by === "tokens" ? "c.tokens > 0" : by === "sessions" ? "c.meals > 0" : "c.xp > 0";

  const rows: any = await db
    .prepare(
      `SELECT c.pet_id, c.name, c.xp, c.tokens, c.meals, c.streak, c.thumb,
              u.login AS login, u.avatar AS avatar
       FROM care_pets c
       LEFT JOIN users u ON u.id = c.user_id
       WHERE ${guard}
       ORDER BY ${orderCol} DESC
       LIMIT 300`
    )
    .all();

  // Which pets have a public detail page (/pet/<slug>): those in the gallery
  // manifest and not hidden. Custom/local pets have no detail page, so their
  // name stays plain text on the board instead of a broken link.
  let gallery = new Set<string>();
  try {
    const ovr: any = await getOverrides(db);
    gallery = new Set(
      (await loadManifest()).map((p) => p.slug).filter((sl) => !ovr?.[sl]?.hidden)
    );
  } catch {}

  const pets = (rows?.results ?? []).map((r: any) => {
    const sl = urlSlug(r.pet_id);
    return {
      id: r.pet_id,
      name: r.name || r.pet_id,
      xp: r.xp,
      tokens: r.tokens,
      meals: r.meals,
      streak: r.streak,
      thumb: r.thumb || null,
      owner: r.login || null,
      ownerAvatar: r.avatar || null,
      // Non-null only when a /pet/<slug> detail page exists.
      slug: gallery.has(sl) ? sl : null,
    };
  });

  return new Response(JSON.stringify({ pets }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=60" },
  });
};
