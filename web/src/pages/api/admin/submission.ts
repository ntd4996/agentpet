import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { adminUser } from "../../../lib/admin";
import { getDB, ensureSchema, getSubmission, setSubmissionStatus } from "../../../lib/db";

export const prerender = false;

// Admin-only: approve or reject a community submission.
//  - approve: publish the sprite + a generated pet.json to pets/<slug>/ (the live,
//    public-served prefix) and mark approved → it shows up in the gallery.
//  - reject: mark rejected and delete the pending upload.
export const POST: APIRoute = async ({ cookies, request }) => {
  const user = await adminUser(cookies);
  if (!user) return json({ error: "forbidden" }, 403);

  let body: any;
  try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
  const id = String(body?.id || "");
  const action = String(body?.action || "");
  if (!id || (action !== "approve" && action !== "reject")) return json({ error: "bad request" }, 400);

  const db = getDB();
  const bucket = (env as any).PETS;
  if (!db || !bucket) return json({ error: "storage unavailable" }, 500);
  await ensureSchema(db);

  const sub = await getSubmission(db, id);
  if (!sub) return json({ error: "not found" }, 404);
  if (sub.status !== "pending") return json({ error: "already reviewed" }, 409);

  const pendingKey = `submissions/${sub.id}.${sub.sheet_ext}`;

  if (action === "reject") {
    await setSubmissionStatus(db, id, "rejected");
    try { await bucket.delete(pendingKey); } catch {}
    return json({ ok: true, id, status: "rejected" });
  }

  // approve: publish to the live prefix
  const obj = await bucket.get(pendingKey);
  if (!obj) return json({ error: "upload missing" }, 410);
  const sheetName = `spritesheet.${sub.sheet_ext}`;
  const dir = `pets/${sub.slug}`;
  await bucket.put(`${dir}/${sheetName}`, obj.body, {
    httpMetadata: { contentType: sub.sheet_ext === "png" ? "image/png" : "image/webp", cacheControl: "public, max-age=31536000, immutable" },
  });
  await bucket.put(`${dir}/pet.json`, JSON.stringify({
    id: sub.slug, displayName: sub.name, description: sub.description || "",
    spritesheetPath: sheetName, category: sub.kind, source: "community", submittedBy: sub.login,
  }), { httpMetadata: { contentType: "application/json", cacheControl: "public, max-age=31536000, immutable" } });

  await setSubmissionStatus(db, id, "approved");
  try { await bucket.delete(pendingKey); } catch {}
  return json({ ok: true, id, status: "approved", slug: sub.slug });
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
