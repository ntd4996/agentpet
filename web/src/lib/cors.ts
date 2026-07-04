// CORS for the endpoints the desktop apps call cross-origin (the Tauri Windows
// WebView enforces CORS on fetch). These authenticate with a Bearer device
// token or a one-time pair code, never cookies, so a wildcard origin is safe.
import type { APIRoute } from "astro";

export const CORS: Record<string, string> = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, OPTIONS",
  "access-control-allow-headers": "authorization, content-type",
};

export const OPTIONS: APIRoute = () => new Response(null, { status: 204, headers: CORS });

/** JSON response with CORS headers merged in. */
export const corsJson = (obj: unknown, status = 200, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json", "cache-control": "no-store", ...CORS, ...extra },
  });
