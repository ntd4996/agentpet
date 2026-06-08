import type { APIRoute } from "astro";
import { adminUser } from "../../../lib/admin";
import { KIND_OPTIONS } from "../../../lib/pets";
import { getDB, ensureSchema, patchOverride } from "../../../lib/db";

export const prerender = false;

// Admin-only: edit a pet's category or hide/restore it. Body: { slug, kind?, hidden? }.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await adminUser(cookies);
  if (!user) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });

  let body: any;
  try { body = await request.json(); } catch { return new Response(JSON.stringify({ error: "bad json" }), { status: 400 }); }
  const slug = String(body?.slug || "").trim();
  if (!slug) return new Response(JSON.stringify({ error: "slug required" }), { status: 400 });

  const patch: { kind?: string; hidden?: boolean; name?: string; description?: string; reviewed?: boolean } = {};
  if (body.kind !== undefined) {
    const kind = String(body.kind || "");
    if (kind && !KIND_OPTIONS.includes(kind)) return new Response(JSON.stringify({ error: "bad kind" }), { status: 400 });
    patch.kind = kind;
  }
  if (body.hidden !== undefined) patch.hidden = !!body.hidden;
  if (body.name !== undefined) patch.name = String(body.name || "").trim().slice(0, 80);
  if (body.description !== undefined) patch.description = String(body.description || "").trim().slice(0, 400);
  if (body.reviewed !== undefined) patch.reviewed = !!body.reviewed;
  if (patch.kind === undefined && patch.hidden === undefined && patch.name === undefined && patch.description === undefined && patch.reviewed === undefined)
    return new Response(JSON.stringify({ error: "nothing to update" }), { status: 400 });

  const db = getDB();
  if (!db) return new Response(JSON.stringify({ error: "no db" }), { status: 500 });
  await ensureSchema(db);
  const res = await patchOverride(db, slug, patch);
  return new Response(JSON.stringify({ ok: true, slug, ...res }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
};
