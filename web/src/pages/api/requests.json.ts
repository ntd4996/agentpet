import type { APIRoute } from "astro";
import { currentUser } from "../../lib/admin";
import { getDB, ensureSchema, listRequests, userVotes } from "../../lib/db";

export const prerender = false;

// Public: the request queue (default open), sorted by votes. If signed in, also
// returns which requests the user has voted for.
export const GET: APIRoute = async ({ cookies, url }) => {
  const db = getDB();
  if (!db) return new Response(JSON.stringify({ requests: [], mine: [] }), { status: 200 });
  await ensureSchema(db);
  const status = url.searchParams.get("status") || "open";
  const requests = await listRequests(db, status === "all" ? undefined : status);
  const user = await currentUser(cookies);
  const mine = user ? await userVotes(db, user.id) : [];
  return new Response(JSON.stringify({ requests, mine }), { headers: { "content-type": "application/json", "cache-control": "no-store" } });
};
