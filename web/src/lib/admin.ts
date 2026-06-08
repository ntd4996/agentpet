import { env } from "cloudflare:workers";
import { verifySession, SESSION_COOKIE, type SessionUser } from "./auth";

// Who may use /admin. Configurable via the ADMIN_LOGINS env (comma-separated GitHub
// logins); defaults to the project owner. Compared case-insensitively.
export function adminLogins(): string[] {
  let raw = "";
  try { const e = (env as any)?.ADMIN_LOGINS; if (e) raw = String(e); } catch {}
  if (!raw) raw = (import.meta as any).env?.ADMIN_LOGINS ?? "";
  if (!raw) raw = "ntd4996";
  return raw.split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
}

export function isAdmin(login?: string | null): boolean {
  if (!login) return false;
  return adminLogins().includes(login.toLowerCase());
}

function sessionSecret(): string {
  try { const e = (env as any)?.SESSION_SECRET; if (e) return String(e); } catch {}
  return (import.meta as any).env?.SESSION_SECRET ?? "";
}

// Returns the signed-in user only if they are an admin, else null. Used to gate the
// /admin page and /api/admin/* routes. `cookies` is Astro's cookie accessor.
export async function adminUser(cookies: { get(n: string): { value: string } | undefined }): Promise<SessionUser | null> {
  const token = cookies.get(SESSION_COOKIE)?.value || "";
  if (!token) return null;
  const user = await verifySession(token, sessionSecret());
  if (!user || !isAdmin(user.login)) return null;
  return user;
}

// Any signed-in user (or null). Used to gate community actions like /submit.
export async function currentUser(cookies: { get(n: string): { value: string } | undefined }): Promise<SessionUser | null> {
  const token = cookies.get(SESSION_COOKIE)?.value || "";
  if (!token) return null;
  return verifySession(token, sessionSecret());
}
