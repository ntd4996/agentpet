import { env } from "cloudflare:workers";

// D1 access. Binding `DB` comes from wrangler.jsonc (local in dev via platformProxy,
// real database in prod). Returns null if the binding isn't available.
export function getDB(): any {
  try {
    return (env as any)?.DB ?? null;
  } catch {
    return null;
  }
}

let ready = false;

// Idempotent schema bootstrap, avoids a separate migration step in dev. Cheap and
// safe to call before each query (cached per isolate after the first run).
// `pet_stats` keeps a running like count per pet so the public counts query reads
// one small row per liked pet instead of scanning the whole pet_likes table.
export async function ensureSchema(db: any): Promise<void> {
  if (ready || !db) return;
  await db.batch([
    db.prepare(
      "CREATE TABLE IF NOT EXISTS pet_likes (slug TEXT NOT NULL, user_id INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY (slug, user_id))"
    ),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_pet_likes_user ON pet_likes (user_id)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_stats (slug TEXT PRIMARY KEY, likes INTEGER NOT NULL DEFAULT 0)"),
    db.prepare("CREATE TABLE IF NOT EXISTS users (id INTEGER PRIMARY KEY, login TEXT, avatar TEXT, updated_at INTEGER NOT NULL DEFAULT 0)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_overrides (slug TEXT PRIMARY KEY, kind TEXT, hidden INTEGER NOT NULL DEFAULT 0, name TEXT, description TEXT, reviewed INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_installs (slug TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_downloads (slug TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL DEFAULT 0)"),
    db.prepare("CREATE TABLE IF NOT EXISTS submissions (id TEXT PRIMARY KEY, slug TEXT NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL, description TEXT, sheet_ext TEXT NOT NULL, user_id INTEGER NOT NULL, login TEXT NOT NULL, avatar TEXT, status TEXT NOT NULL DEFAULT 'pending', created_at INTEGER NOT NULL, reviewed_at INTEGER)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_submissions_status ON submissions (status)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_submissions_user ON submissions (user_id)"),
    db.prepare("CREATE TABLE IF NOT EXISTS collections (id TEXT PRIMARY KEY, title TEXT NOT NULL, slug TEXT NOT NULL UNIQUE, description TEXT, created_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS collection_pets (collection_id TEXT NOT NULL, slug TEXT NOT NULL, added_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (collection_id, slug))"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_collection_pets_slug ON collection_pets (slug)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_requests (id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, user_id INTEGER NOT NULL, login TEXT NOT NULL, avatar TEXT, status TEXT NOT NULL DEFAULT 'open', created_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS request_votes (request_id TEXT NOT NULL, user_id INTEGER NOT NULL, created_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (request_id, user_id))"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_pet_requests_status ON pet_requests (status)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_numbers (slug TEXT PRIMARY KEY, num INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS pet_meta (slug TEXT PRIMARY KEY, color TEXT)"),
  ]);
  ready = true;
}

// Analyzed dominant colour per pet (slug -> colour name), from the seed pipeline.
export async function getColors(db: any): Promise<Record<string, string>> {
  if (!db) return {};
  const r: any = await db.prepare("SELECT slug, color FROM pet_meta").all();
  const m: Record<string, string> = {};
  for (const row of r?.results ?? []) m[row.slug] = row.color;
  return m;
}

export async function getColor(db: any, slug: string): Promise<string> {
  if (!db) return "";
  const r: any = await db.prepare("SELECT color FROM pet_meta WHERE slug=?").bind(slug).first();
  return r?.color ?? "";
}

// Stable dex numbers (slug -> NNNNN), assigned by the data seed. Map for bulk views.
export async function getNumbers(db: any): Promise<Record<string, number>> {
  if (!db) return {};
  const r: any = await db.prepare("SELECT slug, num FROM pet_numbers").all();
  const m: Record<string, number> = {};
  for (const row of r?.results ?? []) m[row.slug] = row.num;
  return m;
}

export async function getNumber(db: any, slug: string): Promise<number | null> {
  if (!db) return null;
  const r: any = await db.prepare("SELECT num FROM pet_numbers WHERE slug=?").bind(slug).first();
  return r?.num ?? null;
}

// ---- pet requests (community wishlist) ----
export interface PetRequest { id: string; title: string; description: string | null; user_id: number; login: string; avatar: string | null; status: string; created_at: number; votes: number; }

export async function createRequest(db: any, r: { id: string; title: string; description: string | null; user_id: number; login: string; avatar: string | null; created_at: number }): Promise<void> {
  await db.prepare("INSERT INTO pet_requests (id, title, description, user_id, login, avatar, status, created_at) VALUES (?, ?, ?, ?, ?, ?, 'open', ?)")
    .bind(r.id, r.title, r.description, r.user_id, r.login, r.avatar, r.created_at).run();
}

export async function listRequests(db: any, status?: string): Promise<PetRequest[]> {
  const base = "SELECT r.*, (SELECT COUNT(*) FROM request_votes v WHERE v.request_id = r.id) AS votes FROM pet_requests r";
  const q = status
    ? db.prepare(`${base} WHERE r.status=? ORDER BY votes DESC, r.created_at DESC`).bind(status)
    : db.prepare(`${base} ORDER BY votes DESC, r.created_at DESC`);
  const res: any = await q.all();
  return res?.results ?? [];
}

export async function getRequest(db: any, id: string): Promise<PetRequest | null> {
  return (await db.prepare("SELECT * FROM pet_requests WHERE id=?").bind(id).first()) ?? null;
}

// Which of these request ids the user has voted for.
export async function userVotes(db: any, userId: number): Promise<string[]> {
  const r: any = await db.prepare("SELECT request_id FROM request_votes WHERE user_id=?").bind(userId).all();
  return (r?.results ?? []).map((x: any) => x.request_id);
}

export async function toggleRequestVote(db: any, requestId: string, userId: number): Promise<{ voted: boolean; votes: number }> {
  const existing: any = await db.prepare("SELECT 1 FROM request_votes WHERE request_id=? AND user_id=?").bind(requestId, userId).first();
  if (existing) await db.prepare("DELETE FROM request_votes WHERE request_id=? AND user_id=?").bind(requestId, userId).run();
  else await db.prepare("INSERT OR IGNORE INTO request_votes (request_id, user_id, created_at) VALUES (?, ?, ?)").bind(requestId, userId, Date.now()).run();
  const c: any = await db.prepare("SELECT COUNT(*) AS n FROM request_votes WHERE request_id=?").bind(requestId).first();
  return { voted: !existing, votes: c?.n ?? 0 };
}

export async function setRequestStatus(db: any, id: string, status: string): Promise<void> {
  await db.prepare("UPDATE pet_requests SET status=? WHERE id=?").bind(status, id).run();
}

export async function deleteRequest(db: any, id: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM request_votes WHERE request_id=?").bind(id),
    db.prepare("DELETE FROM pet_requests WHERE id=?").bind(id),
  ]);
}

// ---- collections (admin-curated groups of pets) ----
export interface Collection { id: string; title: string; slug: string; description: string | null; created_at: number; }

export async function listCollections(db: any): Promise<(Collection & { count: number; samples: string[] })[]> {
  const c: any = await db.prepare("SELECT * FROM collections ORDER BY created_at DESC, slug ASC").all();
  const cols: Collection[] = c?.results ?? [];
  if (!cols.length) return [];
  const m: any = await db.prepare("SELECT collection_id, slug FROM collection_pets ORDER BY added_at ASC").all();
  const byCol: Record<string, string[]> = {};
  for (const r of m?.results ?? []) (byCol[r.collection_id] ||= []).push(r.slug);
  return cols.map((col) => ({ ...col, count: (byCol[col.id] || []).length, samples: (byCol[col.id] || []).slice(0, 5) }));
}

export async function getCollection(db: any, slug: string): Promise<Collection | null> {
  return (await db.prepare("SELECT * FROM collections WHERE slug=?").bind(slug).first()) ?? null;
}

export async function collectionSlugs(db: any, collectionId: string): Promise<string[]> {
  const r: any = await db.prepare("SELECT slug FROM collection_pets WHERE collection_id=? ORDER BY added_at ASC").bind(collectionId).all();
  return (r?.results ?? []).map((x: any) => x.slug);
}

export async function collectionsForPet(db: any, slug: string): Promise<{ title: string; slug: string }[]> {
  const r: any = await db
    .prepare("SELECT c.title AS title, c.slug AS slug FROM collection_pets cp JOIN collections c ON c.id = cp.collection_id WHERE cp.slug=? ORDER BY c.created_at ASC")
    .bind(slug)
    .all();
  return r?.results ?? [];
}

export async function createCollection(db: any, id: string, title: string, slug: string, description: string | null): Promise<void> {
  await db.prepare("INSERT INTO collections (id, title, slug, description, created_at) VALUES (?, ?, ?, ?, ?)").bind(id, title, slug, description, Date.now()).run();
}

export async function deleteCollection(db: any, id: string): Promise<void> {
  await db.batch([
    db.prepare("DELETE FROM collection_pets WHERE collection_id=?").bind(id),
    db.prepare("DELETE FROM collections WHERE id=?").bind(id),
  ]);
}

export async function addPetToCollection(db: any, id: string, slug: string): Promise<void> {
  await db.prepare("INSERT OR IGNORE INTO collection_pets (collection_id, slug, added_at) VALUES (?, ?, ?)").bind(id, slug, Date.now()).run();
}

export async function removePetFromCollection(db: any, id: string, slug: string): Promise<void> {
  await db.prepare("DELETE FROM collection_pets WHERE collection_id=? AND slug=?").bind(id, slug).run();
}

// ---- community submissions ----
export interface Submission {
  id: string; slug: string; name: string; kind: string; description: string | null;
  sheet_ext: string; user_id: number; login: string; avatar: string | null;
  status: string; created_at: number; reviewed_at: number | null;
}

export async function insertSubmission(db: any, s: Omit<Submission, "status" | "reviewed_at">): Promise<void> {
  await db
    .prepare("INSERT INTO submissions (id, slug, name, kind, description, sheet_ext, user_id, login, avatar, status, created_at, reviewed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, NULL)")
    .bind(s.id, s.slug, s.name, s.kind, s.description, s.sheet_ext, s.user_id, s.login, s.avatar, s.created_at)
    .run();
}

export async function getSubmission(db: any, id: string): Promise<Submission | null> {
  return (await db.prepare("SELECT * FROM submissions WHERE id=?").bind(id).first()) ?? null;
}

export async function listSubmissions(db: any, status?: string): Promise<Submission[]> {
  const q = status
    ? db.prepare("SELECT * FROM submissions WHERE status=? ORDER BY created_at DESC").bind(status)
    : db.prepare("SELECT * FROM submissions ORDER BY created_at DESC");
  const r: any = await q.all();
  return r?.results ?? [];
}

export async function setSubmissionStatus(db: any, id: string, status: string): Promise<void> {
  await db.prepare("UPDATE submissions SET status=?, reviewed_at=? WHERE id=?").bind(status, Date.now(), id).run();
}

// Approved community pets, shaped like manifest entries for the gallery/home.
export async function approvedCommunityPets(db: any): Promise<{ slug: string; name: string; kind: string; source: string; submittedBy: string }[]> {
  const r: any = await db.prepare("SELECT slug, name, kind, login FROM submissions WHERE status='approved'").all();
  return (r?.results ?? []).map((x: any) => ({ slug: x.slug, name: x.name, kind: x.kind, source: "community", submittedBy: x.login }));
}

// Creator leaderboard: approved-pet counts per submitter (real creators only).
export async function creatorCounts(db: any, limit = 20): Promise<{ login: string; avatar: string | null; count: number }[]> {
  const r: any = await db
    .prepare("SELECT login, MAX(avatar) AS avatar, COUNT(*) AS count FROM submissions WHERE status='approved' GROUP BY login ORDER BY count DESC, login ASC LIMIT ?")
    .bind(limit)
    .all();
  return r?.results ?? [];
}

// Bump a pet's install counter (the desktop app pings this on a successful install).
// Returns the new total.
export async function incrementInstall(db: any, slug: string): Promise<number> {
  if (!db) return 0;
  await db
    .prepare("INSERT INTO pet_installs (slug, count, updated_at) VALUES (?, 1, ?) ON CONFLICT(slug) DO UPDATE SET count=count+1, updated_at=excluded.updated_at")
    .bind(slug, Date.now())
    .run();
  const r: any = await db.prepare("SELECT count FROM pet_installs WHERE slug=?").bind(slug).first();
  return r?.count ?? 0;
}

// Bump a pet's web download counter (sprite / pet.json downloaded from the site).
export async function incrementDownload(db: any, slug: string): Promise<number> {
  if (!db) return 0;
  await db
    .prepare("INSERT INTO pet_downloads (slug, count, updated_at) VALUES (?, 1, ?) ON CONFLICT(slug) DO UPDATE SET count=count+1, updated_at=excluded.updated_at")
    .bind(slug, Date.now())
    .run();
  const r: any = await db.prepare("SELECT count FROM pet_downloads WHERE slug=?").bind(slug).first();
  return r?.count ?? 0;
}

// All admin overrides as a map (small table: only edited/hidden pets have rows).
export async function getOverrides(db: any): Promise<Record<string, { kind?: string; hidden?: boolean; name?: string; description?: string; reviewed?: boolean }>> {
  if (!db) return {};
  const r: any = await db.prepare("SELECT slug, kind, hidden, name, description, reviewed FROM pet_overrides").all();
  const map: Record<string, { kind?: string; hidden?: boolean; name?: string; description?: string; reviewed?: boolean }> = {};
  for (const row of r?.results ?? []) map[row.slug] = { kind: row.kind || undefined, hidden: !!row.hidden, name: row.name || undefined, description: row.description ?? undefined, reviewed: !!row.reviewed };
  return map;
}

// Upsert an override, merging with the existing row so a partial patch leaves the
// other fields untouched. Supports kind / hidden / name / description / reviewed.
export async function patchOverride(db: any, slug: string, patch: { kind?: string; hidden?: boolean; name?: string; description?: string; reviewed?: boolean }): Promise<{ kind: string | null; hidden: boolean; name: string | null; description: string | null; reviewed: boolean }> {
  const cur: any = await db.prepare("SELECT kind, hidden, name, description, reviewed FROM pet_overrides WHERE slug=?").bind(slug).first();
  const kind = patch.kind !== undefined ? (patch.kind || null) : (cur?.kind ?? null);
  const hidden = patch.hidden !== undefined ? (patch.hidden ? 1 : 0) : (cur?.hidden ?? 0);
  const name = patch.name !== undefined ? (patch.name || null) : (cur?.name ?? null);
  const description = patch.description !== undefined ? (patch.description || null) : (cur?.description ?? null);
  const reviewed = patch.reviewed !== undefined ? (patch.reviewed ? 1 : 0) : (cur?.reviewed ?? 0);
  await db
    .prepare("INSERT INTO pet_overrides (slug, kind, hidden, name, description, reviewed, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(slug) DO UPDATE SET kind=excluded.kind, hidden=excluded.hidden, name=excluded.name, description=excluded.description, reviewed=excluded.reviewed, updated_at=excluded.updated_at")
    .bind(slug, kind, hidden, name, description, reviewed, Date.now())
    .run();
  return { kind, hidden: !!hidden, name, description, reviewed: !!reviewed };
}

// Upsert the signed-in user's public profile so leaderboards can show login + avatar.
export async function upsertUser(db: any, u: { id: number; login: string; avatar: string }): Promise<void> {
  if (!db) return;
  await db
    .prepare(
      "INSERT INTO users (id, login, avatar, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET login=excluded.login, avatar=excluded.avatar, updated_at=excluded.updated_at"
    )
    .bind(u.id, u.login, u.avatar, Date.now())
    .run();
}
