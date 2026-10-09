// AI/data analysis of EVERY pet's pixel art: decode each spritesheet (sharp) and
// derive a dominant colour (like petdex's COLOR facet) + vibrance. Writes
// scripts/seed-colors.sql (pet_meta rows + auto-color-* collections). Long job
// (downloads every sprite); run in background, then apply with:
//   npx wrangler d1 execute agentpet-web --remote --file=scripts/seed-colors.sql
import sharp from "sharp";
import { writeFileSync, readFileSync } from "node:fs";
import { COLORS, dominantColor } from "../src/lib/pet-color.ts";

const MANIFEST = "https://pets.thenightwatcher.online/manifest.json";
const ORIGIN = "https://pets.thenightwatcher.online";
const TS = Date.now();
const CONC = 16;

const res = await fetch(MANIFEST);
const pets = (await res.json()).pets || [];
console.error(`analyzing ${pets.length} pets...`);

const result = {}; // slug -> color
let done = 0, failed = 0;
async function worker(list) {
  for (const p of list) {
    try {
      const buf = Buffer.from(await (await fetch(`${ORIGIN}/pets/${p.slug}/spritesheet.webp`)).arrayBuffer());
      const { data, info } = await sharp(buf).resize({ width: 240 }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      result[p.slug] = dominantColor(data, info.width, info.height);
    } catch { failed++; result[p.slug] = "mono"; }
    if (++done % 200 === 0) console.error(`  ${done}/${pets.length} (failed ${failed})`);
  }
}
const chunks = Array.from({ length: CONC }, (_, i) => pets.filter((_, j) => j % CONC === i));
await Promise.all(chunks.map(worker));
console.error(`done. failed ${failed}`);

// counts
const counts = {};
for (const s of Object.values(result)) counts[s] = (counts[s] || 0) + 1;
console.error("by colour:", counts);

// emit SQL
const esc = (s) => String(s).replace(/'/g, "''");
const chunk = (a, n) => { const o = []; for (let i = 0; i < a.length; i += n) o.push(a.slice(i, i + n)); return o; };
let sql = "";
sql += "CREATE TABLE IF NOT EXISTS pet_meta (slug TEXT PRIMARY KEY, color TEXT);\n";
sql += "CREATE TABLE IF NOT EXISTS collections (id TEXT PRIMARY KEY, title TEXT NOT NULL, slug TEXT NOT NULL UNIQUE, description TEXT, created_at INTEGER NOT NULL);\n";
sql += "CREATE TABLE IF NOT EXISTS collection_pets (collection_id TEXT NOT NULL, slug TEXT NOT NULL, added_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (collection_id, slug));\n";
sql += "DELETE FROM pet_meta;\n";
const metaRows = Object.entries(result).map(([s, c]) => `('${esc(s)}','${esc(c)}')`);
for (const c of chunk(metaRows, 400)) sql += `INSERT INTO pet_meta (slug, color) VALUES ${c.join(",")};\n`;

sql += "DELETE FROM collection_pets WHERE collection_id LIKE 'auto-color-%';\n";
for (const c of COLORS) sql += `INSERT INTO collections (id, title, slug, description, created_at) VALUES ('${c.id}','${esc(c.name + " pets")}','${esc(c.slug)}','${esc("Companions where " + c.name.toLowerCase() + " leads the palette.")}',${TS}) ON CONFLICT(id) DO UPDATE SET title=excluded.title, slug=excluded.slug, description=excluded.description;\n`;
for (const c of COLORS) {
  const key = c.name.toLowerCase();
  const slugs = Object.entries(result).filter(([, col]) => col === key).map(([s]) => s);
  for (const ch of chunk(slugs.map((s) => `('${c.id}','${esc(s)}',${TS})`), 400)) sql += `INSERT OR IGNORE INTO collection_pets (collection_id, slug, added_at) VALUES ${ch.join(",")};\n`;
}
writeFileSync(new URL("./seed-colors.sql", import.meta.url), sql);
writeFileSync(new URL("./colors.json", import.meta.url), JSON.stringify(result));

// Bundled copies for the site (src/data); redeploy after re-running this script.
const dataDir = new URL("../src/data/", import.meta.url);
writeFileSync(new URL("pet-colors.json", dataDir), JSON.stringify(result));
const autoFile = new URL("auto-collection-pets.json", dataDir);
let autoMembers = {};
try { autoMembers = JSON.parse(readFileSync(autoFile, "utf8")); } catch {}
for (const id of Object.keys(autoMembers)) if (id.startsWith("auto-color-")) delete autoMembers[id];
for (const c of COLORS) {
  const slugs = Object.entries(result).filter(([, col]) => col === c.name.toLowerCase()).map(([s]) => s);
  if (slugs.length) autoMembers[c.id] = slugs;
}
writeFileSync(autoFile, JSON.stringify(autoMembers));
console.error(`wrote seed-colors.sql (${metaRows.length} meta, ${COLORS.length} colour collections)`);
