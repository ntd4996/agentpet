import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";
import { signSession, SESSION_COOKIE, type SessionUser } from "../../../lib/auth";

export const prerender = false;

const v = (n: string): string => {
  try { const e = (env as any)?.[n]; if (e) return String(e); } catch {}
  return (import.meta as any).env?.[n] ?? "";
};
const THIRTY_DAYS = 30 * 24 * 60 * 60;

// GitHub redirects here with ?code&state. Verify state, swap code for a token,
// load the profile, and drop a signed session cookie.
export const GET: APIRoute = async ({ request, cookies }) => {
  const url = new URL(request.url);
  const origin = url.origin;
  const secure = origin.startsWith("https");
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  const savedState = cookies.get("ap_oauth_state")?.value;
  cookies.delete("ap_oauth_state", { path: "/" });

  if (!code || !state || !savedState || state !== savedState) {
    return new Response("Invalid OAuth state. Please try signing in again.", { status: 400 });
  }

  const clientId = v("GITHUB_CLIENT_ID");
  const clientSecret = v("GITHUB_CLIENT_SECRET");
  const secret = v("SESSION_SECRET");
  if (!clientId || !clientSecret || !secret) return new Response("GitHub login is not configured yet.", { status: 500 });

  const tokenRes = await fetch("https://github.com/login/oauth/access_token", {
    method: "POST",
    headers: { "content-type": "application/json", accept: "application/json" },
    body: JSON.stringify({ client_id: clientId, client_secret: clientSecret, code, redirect_uri: `${origin}/api/auth/callback` }),
  });
  const tok: any = await tokenRes.json().catch(() => ({}));
  if (!tok?.access_token) return new Response("Token exchange failed.", { status: 401 });

  const ghRes = await fetch("https://api.github.com/user", {
    headers: { authorization: `Bearer ${tok.access_token}`, "user-agent": "AgentPet", accept: "application/vnd.github+json" },
  });
  const gh: any = await ghRes.json().catch(() => ({}));
  if (!gh?.id) return new Response("Could not load your GitHub profile.", { status: 401 });

  const user: SessionUser = {
    id: gh.id,
    login: gh.login,
    name: gh.name || gh.login,
    avatar: gh.avatar_url,
    exp: Date.now() + THIRTY_DAYS * 1000,
  };
  const token = await signSession(user, secret);
  cookies.set(SESSION_COOKIE, token, { httpOnly: true, secure, sameSite: "lax", path: "/", maxAge: THIRTY_DAYS });

  const returnTo = cookies.get("ap_oauth_return")?.value || "/";
  cookies.delete("ap_oauth_return", { path: "/" });
  const dest = `${origin}${returnTo.startsWith("/") ? returnTo : "/"}`;
  return new Response(null, { status: 302, headers: { Location: dest } });
};
