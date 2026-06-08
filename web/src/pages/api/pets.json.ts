import type { APIRoute } from "astro";
import { loadManifest, applyOverrides } from "../../lib/pets";
import { getDB, ensureSchema, getOverrides, approvedCommunityPets, getNumbers, getColors } from "../../lib/db";

export const prerender = false;

// Public pet list for the gallery / home / leaderboard. Real `kind` + `source` from
// the manifest + approved community submissions, with admin overrides applied
// (edited kinds, hidden pets dropped).
export const GET: APIRoute = async () => {
  const manifest = await loadManifest();

  let ovr = {};
  let community: any[] = [];
  let nums: Record<string, number> = {};
  let colors: Record<string, string> = {};
  const db = getDB();
  if (db) { await ensureSchema(db); ovr = await getOverrides(db); community = await approvedCommunityPets(db); nums = await getNumbers(db); colors = await getColors(db); }
  if (!manifest.length && !community.length) return new Response(JSON.stringify({ pets: [] }), { status: 502 });

  const pets = applyOverrides([...community, ...manifest], ovr).map((p) => ({ slug: p.slug, name: p.name, kind: p.kind, source: p.source, num: nums[p.slug] || 0, color: colors[p.slug] || "" }));
  return new Response(JSON.stringify({ pets }), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=60" },
  });
};
