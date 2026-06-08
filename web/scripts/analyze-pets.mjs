// AI/data analysis of EVERY pet's pixel art: decode each spritesheet (sharp) and
// derive a dominant colour (like petdex's COLOR facet) + vibrance. Writes
// scripts/seed-colors.sql (pet_meta rows + auto-color-* collections). Long job
// (downloads every sprite); run in background, then apply with:
//   npx wrangler d1 execute agentpet-web --remote --file=scripts/seed-colors.sql
import sharp from "sharp";
import { writeFileSync } from "node:fs";

const MANIFEST = "https://pets.thenightwatcher.online/manifest.json";
const ORIGIN = "https://pets.thenightwatcher.online";
const TS = Date.now();
const CONC = 16;

const COLORS = [
  { id: "auto-color-red", name: "Red", slug: "red-pets" },
  { id: "auto-color-orange", name: "Orange", slug: "orange-pets" },
  { id: "auto-color-yellow", name: "Yellow", slug: "yellow-pets" },
  { id: "auto-color-green", name: "Green", slug: "green-pets" },
  { id: "auto-color-teal", name: "Teal", slug: "teal-pets" },
  { id: "auto-color-blue", name: "Blue", slug: "blue-pets" },
  { id: "auto-color-purple", name: "Purple", slug: "purple-pets" },
  { id: "auto-color-pink", name: "Pink", slug: "pink-pets" },
  { id: "auto-color-brown", name: "Brown", slug: "brown-pets" },
  { id: "auto-color-mono", name: "Monochrome", slug: "monochrome-pets" },
];
const COLOR_BY_KEY = Object.fromEntries(COLORS.map((c) => [c.name.toLowerCase(), c]));

function rgbToHsl(r, g, b) {
  r /= 255; g /= 255; b /= 255;
  const max = Math.max(r, g, b), min = Math.min(r, g, b), d = max - min;
  let h = 0; const l = (max + min) / 2;
  const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
  if (d !== 0) {
    if (max === r) h = ((g - b) / d) % 6;
    else if (max === g) h = (b - r) / d + 2;
    else h = (r - g) / d + 4;
    h *= 60; if (h < 0) h += 360;
  }
  return [h, s, l];
}
function hueName(h) {
  if (h < 15 || h >= 345) return "red";
  if (h < 40) return "orange";
  if (h < 70) return "yellow";
  if (h < 165) return "green";
  if (h < 200) return "teal";
  if (h < 255) return "blue";
  if (h < 300) return "purple";
  return "pink";
}

// Dominant colour from saturation-weighted hue histogram over vivid pixels.
function dominantColor(data, w, h) {
  const hue = new Array(360).fill(0);
  let vivid = 0, sumL = 0, lowSatLight = 0, total = 0;
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] < 40) continue;
    total++;
    const [H, S, L] = rgbToHsl(data[i], data[i + 1], data[i + 2]);
    if (L > 0.96 || L < 0.06) continue; // skip pure white/black (often outline/bg)
    if (S > 0.22) { hue[Math.floor(H) % 360] += S; vivid++; sumL += L; }
    else lowSatLight++;
  }
  if (!total) return "mono";
  if (vivid < total * 0.04) return "mono"; // mostly grey/black/white
  // smoothed argmax over hue histogram
  let best = 0, bestI = 0;
  for (let i = 0; i < 360; i++) { const v = hue[i] + hue[(i + 359) % 360] + hue[(i + 1) % 360]; if (v > best) { best = v; bestI = i; } }
  const avgL = sumL / Math.max(1, vivid);
  let name = hueName(bestI);
  if ((name === "orange" || name === "red") && avgL < 0.46) name = "brown";
  return name;
}

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
console.error(`wrote seed-colors.sql (${metaRows.length} meta, ${COLORS.length} colour collections)`);
