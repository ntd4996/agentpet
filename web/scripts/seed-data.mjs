// Data seed: assigns stable dex numbers (00001..N) to every pet and auto-builds
// themed collections from pet names + kinds (referencing the petdex/openpets
// catalogs we mirror). Emits idempotent SQL to scripts/seed.sql, then apply with:
//   npx wrangler d1 execute agentpet-web --remote --file=scripts/seed.sql
// Auto rows use fixed ids ("auto-*" collections) so re-running is safe and never
// touches admin-made collections. Original author info (submittedBy) is preserved.

import { writeFileSync, readFileSync } from "node:fs";
import { RULES, matchRules } from "../src/lib/collection-rules.ts";

const MANIFEST = "https://pets.thenightwatcher.online/manifest.json";
const TS = Date.now();

const esc = (s) => String(s).replace(/'/g, "''");
const chunk = (arr, n) => { const out = []; for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n)); return out; };

const res = await fetch(MANIFEST);
const data = await res.json();
const pets = data.pets || [];
console.error(`fetched ${pets.length} pets`);

// 1) numbering: stable order by displayName then slug
const ordered = [...pets].sort((a, b) => (a.displayName || a.slug).localeCompare(b.displayName || b.slug) || a.slug.localeCompare(b.slug));
const numRows = ordered.map((p, i) => `('${esc(p.slug)}',${i + 1})`);

// 2) collections membership
const members = {}; // id -> [slug]
for (const r of RULES) members[r.id] = [];
for (const p of pets) {
  for (const id of matchRules(p.displayName || p.slug, p.kind || "")) members[id].push(p.slug);
}

let sql = "";
sql += "CREATE TABLE IF NOT EXISTS pet_numbers (slug TEXT PRIMARY KEY, num INTEGER NOT NULL);\n";
sql += "CREATE TABLE IF NOT EXISTS collections (id TEXT PRIMARY KEY, title TEXT NOT NULL, slug TEXT NOT NULL UNIQUE, description TEXT, created_at INTEGER NOT NULL);\n";
sql += "CREATE TABLE IF NOT EXISTS collection_pets (collection_id TEXT NOT NULL, slug TEXT NOT NULL, added_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (collection_id, slug));\n";
sql += "DELETE FROM pet_numbers;\n";
for (const c of chunk(numRows, 400)) sql += `INSERT INTO pet_numbers (slug, num) VALUES ${c.join(",")};\n`;

// upsert auto collections (fixed ids; safe re-run), then reset their members
sql += "DELETE FROM collection_pets WHERE collection_id LIKE 'auto-%' AND collection_id NOT LIKE 'auto-color-%';\n";
for (const r of RULES) {
  sql += `INSERT INTO collections (id, title, slug, description, created_at) VALUES ('${r.id}','${esc(r.title)}','${esc(r.slug)}','${esc(r.desc)}',${TS}) ON CONFLICT(id) DO UPDATE SET title=excluded.title, slug=excluded.slug, description=excluded.description;\n`;
}
let total = 0;
for (const r of RULES) {
  const rows = members[r.id].map((s) => `('${r.id}','${esc(s)}',${TS})`);
  total += rows.length;
  for (const c of chunk(rows, 400)) sql += `INSERT OR IGNORE INTO collection_pets (collection_id, slug, added_at) VALUES ${c.join(",")};\n`;
  console.error(`${r.id}: ${members[r.id].length}`);
}

writeFileSync(new URL("./seed.sql", import.meta.url), sql);

// Also write the same data as JSON bundled into the worker (src/data). The site
// reads these instead of scanning D1 on every page view; redeploy after re-seeding.
const dataDir = new URL("../src/data/", import.meta.url);
writeFileSync(new URL("pet-numbers.json", dataDir), JSON.stringify(Object.fromEntries(ordered.map((p, i) => [p.slug, i + 1]))));
const autoFile = new URL("auto-collection-pets.json", dataDir);
let autoMembers = {};
try { autoMembers = JSON.parse(readFileSync(autoFile, "utf8")); } catch {}
for (const id of Object.keys(autoMembers)) if (!id.startsWith("auto-color-")) delete autoMembers[id];
for (const r of RULES) if (members[r.id].length) autoMembers[r.id] = members[r.id];
writeFileSync(autoFile, JSON.stringify(autoMembers));
console.error(`\nwrote seed.sql | ${numRows.length} numbers, ${RULES.length} collections, ${total} memberships`);
