import type { APIRoute } from "astro";
import { adminUser } from "../../../lib/admin";
import { slugify } from "../../../lib/pets";
import { getDB, ensureSchema, getCollection, createCollection, deleteCollection, addPetToCollection, removePetFromCollection } from "../../../lib/db";

export const prerender = false;

// Admin-only: manage collections. Body: { action, ... }.
//   create { title, description? }   delete { id }
//   add { id, slug }                 remove { id, slug }
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await adminUser(cookies);
  if (!user) return json({ error: "forbidden" }, 403);

  let body: any;
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const action = String(body?.action || "");

  const db = getDB();
  if (!db) return json({ error: "no db" }, 500);
  await ensureSchema(db);

  if (action === "create") {
    const title = String(body.title || "").trim();
    if (title.length < 2 || title.length > 60) return json({ error: "title must be 2-60 chars" }, 400);
    const description = String(body.description || "").trim() || null;
    let slug = slugify(title); let n = 2;
    while (await getCollection(db, slug)) slug = `${slugify(title)}-${n++}`;
    const id = crypto.randomUUID();
    await createCollection(db, id, title, slug, description);
    return json({ ok: true, collection: { id, title, slug, description } });
  }
  if (action === "delete") {
    if (!body.id) return json({ error: "id required" }, 400);
    await deleteCollection(db, String(body.id));
    return json({ ok: true });
  }
  if (action === "add" || action === "remove") {
    const id = String(body.id || ""); const slug = String(body.slug || "").trim();
    if (!id || !slug) return json({ error: "id + slug required" }, 400);
    if (action === "add") await addPetToCollection(db, id, slug);
    else await removePetFromCollection(db, id, slug);
    return json({ ok: true, id, slug });
  }
  return json({ error: "bad action" }, 400);
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
