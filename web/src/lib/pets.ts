import { env } from "cloudflare:workers";

// Shared pet source. The list comes from the mirror manifest (origin hidden behind
// PETS_ORIGIN); admin overrides (kind edits / hidden pets) are layered on top so the
// gallery, home, leaderboard and admin all agree.

export function petsBase(): string {
  try { const e = (env as any)?.PETS_ORIGIN; if (e) return String(e); } catch {}
  return (import.meta as any).env?.PETS_ORIGIN ?? "";
}

export interface ManifestPet {
  slug: string;
  name: string;
  kind: string;
  source: string;
  submittedBy: string;
}

export async function loadManifest(): Promise<ManifestPet[]> {
  const base = petsBase();
  if (!base) return [];
  try {
    const m: any = await (await fetch(`${base}/manifest.json`)).json();
    return (m.pets ?? []).map((p: any) => ({
      slug: p.slug,
      name: p.displayName ?? p.slug,
      kind: p.kind || "creature",
      source: p.source || "community",
      submittedBy: p.submittedBy || "",
    }));
  } catch {
    return [];
  }
}

export type OverrideMap = Record<string, { kind?: string; hidden?: boolean; name?: string; description?: string }>;
export type EffectivePet = ManifestPet & { hidden: boolean };

// Layer admin overrides over the manifest: effective name + kind + hidden flag. By
// default hidden pets are dropped (public views); pass includeHidden for the admin view.
export function applyOverrides(pets: ManifestPet[], ovr: OverrideMap, includeHidden = false): EffectivePet[] {
  const out: EffectivePet[] = [];
  for (const p of pets) {
    const o = ovr[p.slug];
    const hidden = !!o?.hidden;
    if (hidden && !includeHidden) continue;
    out.push({ ...p, name: o?.name || p.name, kind: o?.kind || p.kind, hidden });
  }
  return out;
}

// The category vocabulary the gallery/admin offer. Derived from the real data
// (petdex: character/creature/object, openpets: asian/western).
export const KIND_OPTIONS = ["character", "creature", "asian", "western", "object"];

// URL/slug-safe id from a display name (community submissions get a short suffix
// added by the caller to guarantee global uniqueness vs the mirrored library).
export function slugify(name: string): string {
  return (
    name.toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 48) || "pet"
  );
}
