import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { currentUser } from "../../lib/admin";
import { slugify, KIND_OPTIONS } from "../../lib/pets";
import { getDB, ensureSchema, insertSubmission } from "../../lib/db";

export const prerender = false;

const MAX_BYTES = 5 * 1024 * 1024; // 5 MB
const EXT: Record<string, string> = { "image/png": "png", "image/webp": "webp" };

// Community pet submission: a logged-in user uploads a spritesheet + metadata. It
// lands in the review queue (pending) until an admin approves it. The sprite is
// stored in R2 under submissions/<id>.<ext>; on approval it's published to
// pets/<slug>/ (see /api/admin/submission).
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await currentUser(cookies);
  if (!user) return json({ error: "sign in to submit a pet" }, 401);

  let form: FormData;
  try { form = await request.formData(); } catch { return json({ error: "bad form" }, 400); }

  const name = String(form.get("name") || "").trim();
  const kind = String(form.get("kind") || "");
  const description = String(form.get("description") || "").trim();
  const file = form.get("sprite");

  if (name.length < 2 || name.length > 60) return json({ error: "name must be 2-60 characters" }, 400);
  if (!KIND_OPTIONS.includes(kind)) return json({ error: "pick a category" }, 400);
  if (!(file instanceof Blob) || file.size === 0) return json({ error: "attach a spritesheet" }, 400);
  if (file.size > MAX_BYTES) return json({ error: "spritesheet too large (max 5 MB)" }, 400);
  const ext = EXT[(file as any).type];
  if (!ext) return json({ error: "spritesheet must be PNG or WebP" }, 400);

  const db = getDB();
  if (!db) return json({ error: "storage unavailable" }, 500);
  const bucket = (env as any).PETS;
  if (!bucket) return json({ error: "storage unavailable" }, 500);
  await ensureSchema(db);

  const id = crypto.randomUUID();
  const slug = `${slugify(name)}-c${id.slice(0, 4)}`;
  try {
    await bucket.put(`submissions/${id}.${ext}`, await file.arrayBuffer(), {
      httpMetadata: { contentType: (file as any).type },
    });
  } catch {
    return json({ error: "upload failed, try again" }, 502);
  }

  await insertSubmission(db, {
    id, slug, name, kind, description: description || null, sheet_ext: ext,
    user_id: user.id, login: user.login, avatar: user.avatar, created_at: Date.now(),
  });

  return json({ ok: true, id, slug });
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
