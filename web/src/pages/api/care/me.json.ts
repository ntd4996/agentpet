import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { verifySession, SESSION_COOKIE } from "../../../lib/auth";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};

// The signed-in user's raised companions, for the profile page.
export const GET: APIRoute = async ({ cookies }) => {
  const token = cookies.get(SESSION_COOKIE)?.value || "";
  const user = token ? await verifySession(token, v("SESSION_SECRET")) : null;
  if (!user) return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });

  const db = getDB();
  if (!db) return new Response(JSON.stringify({ pets: [] }), { headers: { "content-type": "application/json" } });
  await ensureSchema(db);

  const rows: any = await db
    .prepare("SELECT pet_id, name, xp, tokens, meals, streak, last_fed_at, updated_at, thumb, week, achievements FROM care_pets WHERE user_id=? ORDER BY xp DESC")
    .bind(user.id)
    .all();

  const pets = (rows?.results ?? []).map((r: any) => {
    let week: number[] | null = null;
    try { week = r.week ? JSON.parse(r.week) : null; } catch {}
    let achievements: string[] | null = null;
    try { achievements = r.achievements ? JSON.parse(r.achievements) : null; } catch {}
    return {
      id: r.pet_id,
      name: r.name || r.pet_id,
      xp: r.xp,
      tokens: r.tokens,
      meals: r.meals,
      streak: r.streak,
      lastFedAt: r.last_fed_at,
      updatedAt: r.updated_at,
      thumb: r.thumb || null,
      week,
      achievements,
    };
  });

  return new Response(JSON.stringify({ pets }), {
    headers: { "content-type": "application/json", "cache-control": "no-store" },
  });
};
