// Per-project pets + split-pet , a port of the macOS ProjectPetSettings. When
// split is ON, each configured project gets its own pet window (spawned by the
// Rust `sync_project_windows` command); the main window shows the rest. OFF by
// default, so the single-pet experience is unchanged unless the user opts in.

import { getLibrary } from "./catalog";

const SPLIT_KEY = "ap_split";
const MAP_KEY = "ap_project_pets";

export function splitEnabled(): boolean {
  return localStorage.getItem(SPLIT_KEY) === "1";
}
export function setSplit(on: boolean) {
  localStorage.setItem(SPLIT_KEY, on ? "1" : "0");
}

/// Map of projectId → pet slug for the projects the user gave a dedicated pet.
export function projectPetMap(): Record<string, string> {
  try { return JSON.parse(localStorage.getItem(MAP_KEY) || "{}"); } catch { return {}; }
}
function saveMap(m: Record<string, string>) {
  localStorage.setItem(MAP_KEY, JSON.stringify(m));
}
export function setProjectPet(id: string, slug: string) {
  const m = projectPetMap();
  if (slug) m[id] = slug; else delete m[id];
  saveMap(m);
}
export function configuredProjectIds(): string[] {
  return Object.keys(projectPetMap());
}
export function petForProject(id: string): string | null {
  return projectPetMap()[id] || null;
}
export function libUrlForSlug(slug: string): string | null {
  return getLibrary().find((p) => p.slug === slug)?.url || null;
}
