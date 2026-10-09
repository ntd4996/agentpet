import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { adminUser } from "../../../lib/admin";
import { getDB, ensureSchema, getSubmission, setSubmissionStatus, addNotification, assignCommunityMeta, removeCommunityMeta } from "../../../lib/db";

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

  const pendingKey = `submissions/${sub.id}.${sub.sheet_ext}`;
  const dir = `pets/${sub.slug}`;
  // Re-deciding a pet should not leave a stale opposite notification behind.
  const clearDecisionNotis = async () => {
    try { await db.prepare("DELETE FROM notifications WHERE user_id=? AND slug=? AND type IN ('approved','rejected')").bind(sub.user_id, sub.slug).run(); } catch {}
  };

  if (action === "reject") {
    await setSubmissionStatus(db, id, "rejected");
    try { await removeCommunityMeta(db, sub.slug); } catch {}
    // If it was previously approved, pull the published files from the gallery.
    try { await bucket.delete(`${dir}/spritesheet.${sub.sheet_ext}`); } catch {}
    try { await bucket.delete(`${dir}/pet.json`); } catch {}
    // Keep the pending upload so the pet can be approved again later.
    await clearDecisionNotis();
    await addNotification(db, sub.user_id, "rejected", sub.name,
      null, "/submit", sub.slug);
    return json({ ok: true, id, status: "rejected" });
  }

  // approve: publish to the live prefix. Prefer the pending upload; fall back to an
  // already-published sprite (re-approving a pet that was approved before).
  const sheetName = `spritesheet.${sub.sheet_ext}`;
  const obj = (await bucket.get(pendingKey)) || (await bucket.get(`${dir}/${sheetName}`));
  if (!obj) return json({ error: "upload missing, ask them to resubmit" }, 410);
  await bucket.put(`${dir}/${sheetName}`, obj.body, {
    httpMetadata: { contentType: sub.sheet_ext === "png" ? "image/png" : "image/webp", cacheControl: "public, max-age=31536000, immutable" },
  });
  await bucket.put(`${dir}/pet.json`, JSON.stringify({
    id: sub.slug, displayName: sub.name, description: sub.description || "",
    spritesheetPath: sheetName, category: sub.kind, source: "community", submittedBy: sub.login,
  }), { httpMetadata: { contentType: "application/json", cacheControl: "public, max-age=31536000, immutable" } });

  await setSubmissionStatus(db, id, "approved");
  // Dex number + colour + auto collections, same rules as the seed scripts. The
  // colour is measured from the sprite in the admin's browser (body.color).
  try { await assignCommunityMeta(db, sub.slug, sub.name, sub.kind, typeof body.color === "string" ? body.color : null); } catch {}
  // Un-hide if it had been hidden before (e.g. previously deleted by the owner).
  try { await db.prepare("UPDATE pet_overrides SET hidden=0 WHERE slug=?").bind(sub.slug).run(); } catch {}
  // Keep the pending upload so a later re-reject + re-approve still works.
  await clearDecisionNotis();
  await addNotification(db, sub.user_id, "approved", sub.name,
    null, `/pet/${sub.slug}`, sub.slug);
  return json({ ok: true, id, status: "approved", slug: sub.slug });
};

const json = (data: any, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });
