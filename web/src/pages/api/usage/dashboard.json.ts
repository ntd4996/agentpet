import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { verifySession, SESSION_COOKIE } from "../../../lib/auth";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};
const empty = { projects: [], agents: [], daily: [], monthly: [], totalTokens: 0, totalSessions: 0 };
const json = (obj: unknown) => new Response(JSON.stringify(obj), { headers: { "content-type": "application/json", "cache-control": "no-store" } });

// The signed-in user's own token usage, grouped for the /dashboard charts.
// Optional filters: ?project=<id>&agent=<name>. Always returns the project/agent
// lists (unfiltered) so the page can build its dropdowns.
export const GET: APIRoute = async ({ cookies, url }) => {
  const token = cookies.get(SESSION_COOKIE)?.value || "";
  const user = token ? await verifySession(token, v("SESSION_SECRET")) : null;
  if (!user) return json(empty);

  const db = getDB();
  if (!db) return json(empty);
  await ensureSchema(db);

  const project = url.searchParams.get("project") || "";
  const agent = url.searchParams.get("agent") || "";
  const where = ["user_id=?"];
  const args: any[] = [user.id];
  if (project) { where.push("project_id=?"); args.push(project); }
  if (agent) { where.push("agent=?"); args.push(agent); }
  const W = where.join(" AND ");

  const [projects, agents, daily, monthly, totals] = await Promise.all([
    db.prepare("SELECT project_id AS id, project_name AS name, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE user_id=? GROUP BY project_id ORDER BY tokens DESC").bind(user.id).all(),
    db.prepare("SELECT agent, SUM(tokens) AS tokens FROM usage_daily WHERE user_id=? GROUP BY agent ORDER BY tokens DESC").bind(user.id).all(),
    db.prepare(`SELECT day, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE ${W} GROUP BY day ORDER BY day DESC LIMIT 120`).bind(...args).all(),
    db.prepare(`SELECT substr(day,1,7) AS month, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE ${W} GROUP BY month ORDER BY month DESC LIMIT 24`).bind(...args).all(),
    db.prepare(`SELECT SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE ${W}`).bind(...args).first(),
  ]);

  return json({
    projects: projects?.results ?? [],
    agents: agents?.results ?? [],
    daily: (daily?.results ?? []).reverse(),      // oldest -> newest for charting
    monthly: (monthly?.results ?? []).reverse(),
    totalTokens: (totals as any)?.tokens ?? 0,
    totalSessions: (totals as any)?.sessions ?? 0,
  });
};
