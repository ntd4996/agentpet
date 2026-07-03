import type { APIRoute } from "astro";
import { adminUser } from "../../../lib/admin";
import { getDB, ensureSchema } from "../../../lib/db";

export const prerender = false;
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { "content-type": "application/json", "cache-control": "no-store" } });

// Admin usage dashboard. No ?user → community-wide aggregates + a user list for
// drill-down. With ?user=<id> → that user's per-project / per-agent breakdown.
export const GET: APIRoute = async ({ cookies, url }) => {
  const admin = await adminUser(cookies);
  if (!admin) return json({ error: "forbidden" }, 403);

  const db = getDB();
  if (!db) return json({ error: "no db" }, 500);
  await ensureSchema(db);

  const userId = url.searchParams.get("user");

  if (userId) {
    const uid = Number(userId) || 0;
    const [who, byProject, byAgent, daily, monthly, totals] = await Promise.all([
      db.prepare("SELECT id, login, avatar FROM users WHERE id=?").bind(uid).first(),
      db.prepare("SELECT project_id AS id, project_name AS name, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE user_id=? GROUP BY project_id ORDER BY tokens DESC LIMIT 100").bind(uid).all(),
      db.prepare("SELECT agent, SUM(tokens) AS tokens FROM usage_daily WHERE user_id=? GROUP BY agent ORDER BY tokens DESC").bind(uid).all(),
      db.prepare("SELECT day, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE user_id=? GROUP BY day ORDER BY day DESC LIMIT 120").bind(uid).all(),
      db.prepare("SELECT substr(day,1,7) AS month, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE user_id=? GROUP BY month ORDER BY month DESC LIMIT 24").bind(uid).all(),
      db.prepare("SELECT SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily WHERE user_id=?").bind(uid).first(),
    ]);
    return json({
      user: who ?? { id: uid, login: "user " + uid, avatar: null },
      byProject: byProject?.results ?? [],
      byAgent: byAgent?.results ?? [],
      daily: (daily?.results ?? []).reverse(),
      monthly: (monthly?.results ?? []).reverse(),
      totalTokens: (totals as any)?.tokens ?? 0,
      totalSessions: (totals as any)?.sessions ?? 0,
    });
  }

  // Community-wide overview.
  const [totals, byProject, byAgent, daily, monthly, users] = await Promise.all([
    db.prepare("SELECT SUM(tokens) AS tokens, SUM(sessions) AS sessions, COUNT(DISTINCT user_id) AS users, COUNT(DISTINCT project_id) AS projects FROM usage_daily").first(),
    db.prepare("SELECT project_name AS name, SUM(tokens) AS tokens, SUM(sessions) AS sessions, COUNT(DISTINCT user_id) AS users FROM usage_daily GROUP BY project_id ORDER BY tokens DESC LIMIT 50").all(),
    db.prepare("SELECT agent, SUM(tokens) AS tokens, COUNT(DISTINCT user_id) AS users FROM usage_daily GROUP BY agent ORDER BY tokens DESC").all(),
    db.prepare("SELECT day, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily GROUP BY day ORDER BY day DESC LIMIT 120").all(),
    db.prepare("SELECT substr(day,1,7) AS month, SUM(tokens) AS tokens, SUM(sessions) AS sessions FROM usage_daily GROUP BY month ORDER BY month DESC LIMIT 24").all(),
    db.prepare(`SELECT u.user_id AS id, us.login AS login, us.avatar AS avatar, u.tokens AS tokens, u.sessions AS sessions, u.projects AS projects
                FROM (SELECT user_id, SUM(tokens) AS tokens, SUM(sessions) AS sessions, COUNT(DISTINCT project_id) AS projects FROM usage_daily GROUP BY user_id) u
                LEFT JOIN users us ON us.id = u.user_id
                ORDER BY u.tokens DESC LIMIT 200`).all(),
  ]);

  return json({
    totalTokens: (totals as any)?.tokens ?? 0,
    totalSessions: (totals as any)?.sessions ?? 0,
    activeUsers: (totals as any)?.users ?? 0,
    projectCount: (totals as any)?.projects ?? 0,
    byProject: byProject?.results ?? [],
    byAgent: byAgent?.results ?? [],
    daily: (daily?.results ?? []).reverse(),
    monthly: (monthly?.results ?? []).reverse(),
    users: users?.results ?? [],
  });
};
