import type { APIRoute } from "astro";
import { petsBase } from "../../../lib/pets";
import { getDB, ensureSchema, incrementDownload } from "../../../lib/db";
import { zipStore } from "../../../lib/zip";

export const prerender = false;
const SLUG = /^[a-z0-9][a-z0-9._-]{0,80}$/i;

// Downloads a pet pack and counts the download. Proxied so the origin stays hidden.
//   (default)     -> <slug>.zip  (pet.json + spritesheet)
//   ?kind=json    -> pet.json
//   ?kind=sprite  -> spritesheet
export const GET: APIRoute = async ({ params, url }) => {
  const slug = params.slug ?? "";
  if (!SLUG.test(slug)) return new Response("bad request", { status: 400 });
  const base = petsBase();
  if (!base) return new Response("not configured", { status: 500 });
  const kind = url.searchParams.get("kind") || "zip";

  const fetchSheet = async () => {
    let r = await fetch(`${base}/pets/${slug}/spritesheet.webp`); let ext = "webp";
    if (!r.ok) { r = await fetch(`${base}/pets/${slug}/spritesheet.png`); ext = "png"; }
    return { r, ext };
  };

  const db = getDB();
  const count = async () => { if (db) { await ensureSchema(db); await incrementDownload(db, slug); } };

  if (kind === "json") {
    const r = await fetch(`${base}/pets/${slug}/pet.json`);
    if (!r.ok) return new Response("not found", { status: r.status });
    await count();
    return new Response(r.body, { headers: { "content-type": "application/json", "content-disposition": `attachment; filename="${slug}.pet.json"`, "cache-control": "no-store" } });
  }
  if (kind === "sprite") {
    const { r, ext } = await fetchSheet();
    if (!r.ok) return new Response("not found", { status: r.status });
    await count();
    return new Response(r.body, { headers: { "content-type": r.headers.get("content-type") || "image/webp", "content-disposition": `attachment; filename="${slug}.${ext}"`, "cache-control": "no-store" } });
  }

  // default: zip the whole pack
  const [pj, sheet] = await Promise.all([fetch(`${base}/pets/${slug}/pet.json`), fetchSheet()]);
  if (!sheet.r.ok) return new Response("not found", { status: sheet.r.status });
  const petJson = pj.ok ? new Uint8Array(await pj.arrayBuffer()) : new TextEncoder().encode("{}");
  const sheetBytes = new Uint8Array(await sheet.r.arrayBuffer());
  const zip = zipStore([
    { name: "pet.json", data: petJson },
    { name: `spritesheet.${sheet.ext}`, data: sheetBytes },
  ]);
  await count();
  return new Response(zip, { headers: { "content-type": "application/zip", "content-disposition": `attachment; filename="${slug}.zip"`, "cache-control": "no-store" } });
};
