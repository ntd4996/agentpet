import type { APIRoute } from "astro";
import { env } from "cloudflare:workers";

export const prerender = false;

// Proxies a pet spritesheet from our private origin so the source is never
// exposed to the client (same-origin also lets the gallery slice frames on a
// canvas without CORS). The origin lives only in env, never in the repo.
const SLUG = /^[a-z0-9][a-z0-9._-]{0,80}$/i;

export const GET: APIRoute = async ({ params }) => {
  const slug = params.slug ?? "";
  if (!SLUG.test(slug)) return new Response("bad request", { status: 400 });
  const base = (env as any).PETS_ORIGIN || import.meta.env.PETS_ORIGIN || "";
  if (!base) return new Response("not configured", { status: 500 });

  // Mirrored pets are .webp; community uploads may be .png, so fall back.
  let upstream = await fetch(`${base}/pets/${slug}/spritesheet.webp`);
  if (!upstream.ok) upstream = await fetch(`${base}/pets/${slug}/spritesheet.png`);
  if (!upstream.ok) return new Response("not found", { status: upstream.status });

  return new Response(upstream.body, {
    headers: {
      "content-type": upstream.headers.get("content-type") || "image/webp",
      "cache-control": "public, max-age=31536000, immutable",
    },
  });
};
