// Backup / restore of everything AgentPet keeps in localStorage (pet level and
// care state, pet library with its spritesheets, bubble/sound settings...).
// The WebView profile folder is fragile (a reinstall that wipes it took the pet
// level once), so this gives a plain JSON file to keep elsewhere.
//
// Scope: only keys that belong to AgentPet (prefix `ap_` or `agentpet.`).
// Anything else in localStorage (WebView internals, other origins) is ignored.

const PREFIXES = ["ap_", "agentpet."];
const FORMAT = "agentpet-backup";
const VERSION = 1;

export interface BackupFile {
  format: typeof FORMAT;
  version: number;
  exportedAt: string;
  appVersion?: string;
  data: Record<string, string>;
}

export function isOurs(key: string): boolean {
  return PREFIXES.some((p) => key.startsWith(p));
}

/// Snapshot of every AgentPet key currently in localStorage.
export function snapshot(ls: Storage = localStorage): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < ls.length; i++) {
    const k = ls.key(i);
    if (k && isOurs(k)) {
      const v = ls.getItem(k);
      if (v !== null) out[k] = v;
    }
  }
  return out;
}

export function buildBackup(appVersion?: string, ls: Storage = localStorage): BackupFile {
  return { format: FORMAT, version: VERSION, exportedAt: new Date().toISOString(), appVersion, data: snapshot(ls) };
}

/// Parses and validates a backup file's text. Throws a user-facing Error.
export function parseBackup(text: string): BackupFile {
  let v: unknown;
  try { v = JSON.parse(text); } catch { throw new Error("Not a valid backup file (invalid JSON)"); }
  const o = v as Partial<BackupFile> | null;
  if (!o || typeof o !== "object" || o.format !== FORMAT) throw new Error("Not an AgentPet backup file");
  if (typeof o.version !== "number" || o.version > VERSION) throw new Error("This backup was made by a newer AgentPet");
  if (!o.data || typeof o.data !== "object" || Array.isArray(o.data)) throw new Error("Backup has no data");
  const data: Record<string, string> = {};
  for (const [k, val] of Object.entries(o.data)) {
    // Skip foreign keys and non-strings instead of failing the whole restore.
    if (isOurs(k) && typeof val === "string") data[k] = val;
  }
  if (!Object.keys(data).length) throw new Error("Backup has no AgentPet data");
  return { ...(o as BackupFile), data };
}

/// Writes the backup's keys into localStorage, then removes AgentPet keys that
/// are NOT in the backup so the result matches it (a restore, not a merge).
/// Order matters: nothing is deleted until every new value was written, and a
/// failed write puts the previous values back, so a half restore can never leave
/// the user with less data than before. Returns how many keys were written.
export function applyBackup(b: BackupFile, ls: Storage = localStorage): number {
  const old = snapshot(ls);
  try {
    for (const [k, v] of Object.entries(b.data)) ls.setItem(k, v);
  } catch (e) {
    // Quota or write error: restore every previous value, drop keys we added.
    for (const k of Object.keys(b.data)) if (!(k in old)) ls.removeItem(k);
    for (const [k, v] of Object.entries(old)) {
      try { ls.setItem(k, v); } catch { /* the old value is still there if the write failed */ }
    }
    throw e;
  }
  for (const k of Object.keys(old)) if (!(k in b.data)) ls.removeItem(k);
  return Object.keys(b.data).length;
}
