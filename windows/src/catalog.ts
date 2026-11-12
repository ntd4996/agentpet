// Pulls the public pet catalog (same CDN the macOS app + web use). Open, no auth.

const MANIFEST = "https://pets.thenightwatcher.online/manifest.json";

export interface Pet {
  slug: string;
  name: string;
  spritesheetUrl: string;
  petJsonUrl?: string;
  kind: string;
}

export async function loadCatalog(): Promise<Pet[]> {
  try {
    const r = await fetch(MANIFEST);
    const j: any = await r.json();
    return (j.pets ?? []).map((p: any) => ({
      slug: p.slug,
      name: p.displayName ?? p.slug,
      spritesheetUrl: p.spritesheetUrl,
      petJsonUrl: p.petJsonUrl,
      kind: p.kind ?? "creature",
    }));
  } catch {
    return [];
  }
}

const KEY = "agentpet.petSlug";

export function savedSlug(): string | null {
  try { return localStorage.getItem(KEY); } catch { return null; }
}
export function saveSlug(slug: string) {
  try { localStorage.setItem(KEY, slug); } catch {}
}

// ---- Installed-pet library (the macOS ImagePetStore equivalent) -------------
// Pets the user "downloaded" (Get) or created. The Pet tab pager shows ONLY
// these; the full catalog lives in the Browse dialog.

export interface LibPet {
  slug: string;
  name: string;
  url: string;          // spritesheet URL (CDN) or data URL (created pets)
  petJsonUrl?: string;
  custom?: boolean;
}

const LIB_KEY = "ap_library";

export function getLibrary(): LibPet[] {
  try {
    const v = JSON.parse(localStorage.getItem(LIB_KEY) || "[]");
    return Array.isArray(v) ? v : [];
  } catch { return []; }
}

export function saveLibrary(lib: LibPet[]): boolean {
  try { localStorage.setItem(LIB_KEY, JSON.stringify(lib)); return true; } catch { return false; }
}

/// False when localStorage is full (created pets keep their whole sheet as a data URL).
export function addToLibrary(p: LibPet): boolean {
  const lib = getLibrary().filter((x) => x.slug !== p.slug);
  lib.unshift(p);
  return saveLibrary(lib);
}

/// Remembers the selected sheet URL for startup. A data URL is never copied
/// into `ap_pet_url`: it already lives in the library, and a second copy of a
/// 1-2 MB sheet overflows the localStorage quota (issue #94).
export function rememberPetUrl(url: string) {
  try {
    if (url.startsWith("data:")) localStorage.removeItem("ap_pet_url");
    else localStorage.setItem("ap_pet_url", url);
  } catch {}
}

/// The selected pet's sheet: library entry for the saved slug first, then the
/// legacy keys.
export function selectedPetUrl(): string | null {
  const slug = savedSlug();
  const lib = slug ? getLibrary().find((x) => x.slug === slug)?.url : undefined;
  return lib || localStorage.getItem("ap_pet_custom") || localStorage.getItem("ap_pet_url");
}

export function removeFromLibrary(slug: string) {
  saveLibrary(getLibrary().filter((x) => x.slug !== slug));
}

// ---- Pet rename (macOS ImagePetStore.nameOverrides equivalent) --------------
// A per-slug custom name; falls back to the library/catalog name, then the slug.

const NAMES_KEY = "agentpet.petNames";

function nameOverrides(): Record<string, string> {
  try { return JSON.parse(localStorage.getItem(NAMES_KEY) || "{}"); } catch { return {}; }
}

function defaultName(slug: string): string {
  return getLibrary().find((p) => p.slug === slug)?.name || slug;
}

export function petDisplayName(slug: string): string {
  const custom = nameOverrides()[slug];
  if (custom && custom.trim()) return custom;
  return defaultName(slug);
}

/// Sets or clears a pet's custom name. Clearing (empty or same as default)
/// removes the override so the library name shows again. Capped at 40 chars.
export function renamePet(slug: string, name: string) {
  const overrides = nameOverrides();
  const trimmed = name.trim().slice(0, 40);
  if (!trimmed || trimmed === defaultName(slug)) delete overrides[slug];
  else overrides[slug] = trimmed;
  try { localStorage.setItem(NAMES_KEY, JSON.stringify(overrides)); } catch {}
}
