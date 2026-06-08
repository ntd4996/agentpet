import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { verifySession, SESSION_COOKIE } from "../../lib/auth";
import { getDB, ensureSchema } from "../../lib/db";
import { isAdmin } from "../../lib/admin";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};

// Authoritative session check (from the HttpOnly cookie) + the slugs this user has
// liked. The nav and like buttons both derive from this, so they can never drift
// out of sync. Never cached.
export const GET: APIRoute = async ({ cookies }) => {
  const token = cookies.get(SESSION_COOKIE)?.value || "";
  const user = token ? await verifySession(token, v("SESSION_SECRET")) : null;
  const safe = user ? { id: user.id, login: user.login, name: user.name, avatar: user.avatar, isAdmin: isAdmin(user.login) } : null;

  let mine: string[] = [];
  if (user) {
    const db = getDB();
    if (db) {
      await ensureSchema(db);
      const m: any = await db.prepare("SELECT slug FROM pet_likes WHERE user_id=?").bind(user.id).all();
      mine = (m?.results ?? []).map((r: any) => r.slug);
    }
  }

  return new Response(JSON.stringify({ user: safe, mine }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
