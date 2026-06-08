import type { APIRoute } from "astro";
import { adminUser } from "../../../lib/admin";
import { petsBase } from "../../../lib/pets";
import { getDB, ensureSchema, listSubmissions } from "../../../lib/db";

export const prerender = false;

// Admin-only: the submission queue (default pending) with a preview URL for each.
export const GET: APIRoute = async ({ cookies, url }) => {
  const user = await adminUser(cookies);
  if (!user) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });

  const status = url.searchParams.get("status") || "pending";
  const db = getDB();
  if (!db) return new Response(JSON.stringify({ submissions: [] }), { status: 200 });
  await ensureSchema(db);
  const base = petsBase();
  const rows = await listSubmissions(db, status === "all" ? undefined : status);
  const submissions = rows.map((s) => ({
    id: s.id, slug: s.slug, name: s.name, kind: s.kind, description: s.description,
    login: s.login, avatar: s.avatar, status: s.status, created_at: s.created_at,
    previewUrl: `${base}/submissions/${s.id}.${s.sheet_ext}`,
  }));
  return new Response(JSON.stringify({ submissions }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
};
