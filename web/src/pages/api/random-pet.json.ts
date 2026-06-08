import type { APIRoute } from "astro";
import { loadManifest, applyOverrides, petsBase } from "../../lib/pets";
import { getDB, ensureSchema, getOverrides, getNumber } from "../../lib/db";

export const prerender = false;

// A random (non-hidden) pet for the home "Shuffle" button, with a real description.
export const GET: APIRoute = async () => {
  const manifest = await loadManifest();
  if (!manifest.length) return new Response(JSON.stringify({ error: "empty" }), { status: 404 });

  let ovr = {};
  const db = getDB();
  if (db) { await ensureSchema(db); ovr = await getOverrides(db); }
  const pets = applyOverrides(manifest, ovr);
  if (!pets.length) return new Response(JSON.stringify({ error: "empty" }), { status: 404 });

  const p = pets[Math.floor(Math.random() * pets.length)];
  let desc = "";
  try { const j: any = await (await fetch(`${petsBase()}/pets/${p.slug}/pet.json`)).json(); desc = (j.description ?? "").toString(); } catch {}
  const num = db ? await getNumber(db, p.slug) : null;
  return new Response(JSON.stringify({ slug: p.slug, name: p.name, kind: p.kind, num, desc }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
