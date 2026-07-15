// Procedural pixel-art generator for the arena roster. Every unit gets a
// deterministic 16x16 critter: a mirrored body blob + kind-specific features
// (ears/wings/fins/antennae...), rendered crisp at 12x (192px PNG).
// Usage: node scripts/gen-arena-art.mjs   (writes web/public/arena/*.png + sheet)
import sharp from "sharp";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "public", "arena");
mkdirSync(OUT, { recursive: true });

const S = 16; // grid
const SCALE = 12;

function prng(seed) {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) { h = Math.imul(h ^ seed.charCodeAt(i), 3432918353); h = (h << 13) | (h >>> 19); }
  let a = h >>> 0;
  return () => { a |= 0; a = (a + 0x6d2b79f5) | 0; let t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

const PALETTES = {
  beast:  { body: "#e8863a", dark: "#a4571d", light: "#f7b877", accent: "#8a4514" },
  bird:   { body: "#58b7e8", dark: "#2b7fb0", light: "#a5dcf5", accent: "#f2c14e" },
  aqua:   { body: "#3f7de0", dark: "#2554a3", light: "#8fb7f0", accent: "#63e0d0" },
  bug:    { body: "#7bb662", dark: "#4c7f38", light: "#b4dba2", accent: "#e0d063" },
  spirit: { body: "#a06de0", dark: "#6d41a8", light: "#cdaef2", accent: "#f0e6ff" },
  mech:   { body: "#8a94a6", dark: "#57606f", light: "#c3cbd8", accent: "#e05e5e" },
};

// unit id -> { kind, tier, seed } (seed hand-picked; bump if a critter looks off)
const UNITS = [
  ["pup", "beast", 1, 7], ["peep", "bird", 1, 3], ["bloop", "aqua", 1, 5],
  ["grub", "bug", 1, 11], ["wisp", "spirit", 1, 2], ["zip", "mech", 1, 6],
  ["fang", "beast", 2, 13], ["swoop", "bird", 2, 9], ["shelly", "aqua", 2, 4],
  ["chomp", "bug", 2, 8], ["shade", "spirit", 2, 10], ["gizmo", "mech", 2, 1],
  ["alpha", "beast", 3, 21], ["ember", "bird", 3, 14], ["tide", "aqua", 3, 18],
  ["hive", "bug", 3, 16], ["wraith", "spirit", 3, 23], ["atlas", "mech", 3, 12],
  ["buzz", "bug", 1, 31], ["cocoon", "bug", 1, 33],
];

function drawCritter(kind, tier, seedNum, id) {
  const rnd = prng(`${id}:${seedNum}`);
  const g = Array.from({ length: S }, () => Array(S).fill(null)); // color grid
  const P = PALETTES[kind];
  const cx = 8; // mirror axis between col 7 and 8

  const put = (x, y, c) => { if (x >= 0 && x < S && y >= 0 && y < S) g[y][x] = c; };
  const mput = (x, y, c) => { put(x, y, c); put(2 * cx - 1 - x, y, c); };

  // Body blob: tier controls size. Rows of mirrored widths with jitter.
  const bodyH = tier === 1 ? 6 : tier === 2 ? 7 : 9;
  const bodyW = tier === 1 ? 5 : tier === 2 ? 6 : 7; // half-ish width
  const top = 11 - bodyH;
  const widths = [];
  for (let r = 0; r < bodyH; r++) {
    const t = r / (bodyH - 1);
    let w = Math.round(bodyW * (0.55 + 0.9 * Math.sin(Math.PI * (0.15 + 0.75 * t))) / 1.4) + 1;
    if (rnd() < 0.3) w += rnd() < 0.5 ? -1 : 1;
    widths.push(Math.max(2, Math.min(bodyW, w)));
  }
  if (id === "cocoon") { widths.length = 0; for (let r = 0; r < 7; r++) widths.push(r === 0 || r === 6 ? 2 : 3); }
  widths.forEach((w, r) => {
    const y = (id === "cocoon" ? 5 : top) + r;
    for (let x = cx - w; x < cx; x++) mput(x, y, P.body);
  });

  // Belly light patch (bottom-center rows)
  const bh = Math.max(1, Math.floor(bodyH / 3));
  for (let r = bodyH - bh - 1; r < bodyH - 1; r++) {
    const w = Math.max(1, widths[r] - 2);
    const y = top + r;
    for (let x = cx - w; x < cx; x++) mput(x, y, P.light);
  }

  // Kind features (a cocoon is just a plain wrap: no ears, legs or eyes)
  const headY = top;
  if (id === "cocoon") {
    for (let r = 1; r < 6; r += 2) mput(cx - 2, 5 + r, P.light); // silk bands
    return g;
  }
  if (kind === "beast") {
    mput(cx - widths[0], headY - 1, P.body); mput(cx - widths[0], headY - 2, P.dark); // ears
    mput(cx - 1, top + bodyH, P.dark); mput(cx - 3, top + bodyH, P.dark); // paws
    put(cx + widths[Math.floor(bodyH / 2)] , top + Math.floor(bodyH / 2), P.dark); // tail nub
  } else if (kind === "bird") {
    const wy = top + Math.floor(bodyH / 2);
    mput(cx - bodyW - 1, wy, P.dark); mput(cx - bodyW - 1, wy + 1, P.body); // wings
    put(cx, headY + 1, P.accent); put(cx - 1, headY + 1, P.accent); // beak
    mput(cx - 2, top + bodyH, P.accent); // feet
    mput(cx - widths[0] + 1, headY - 1, P.body); // crest
  } else if (kind === "aqua") {
    mput(cx - 1, headY - 1, P.accent); // top fin
    const fy = top + Math.floor(bodyH / 2);
    mput(cx - bodyW - 1, fy, P.accent); // side fins
    mput(cx - 2, top + bodyH, P.accent); // tail fin hint
  } else if (kind === "bug") {
    mput(cx - 2, headY - 1, P.dark); mput(cx - 3, headY - 2, P.accent); // antennae
    for (let l = 0; l < 3; l++) mput(cx - widths[Math.min(bodyH - 1, 2 + l)] - 1, top + 2 + l * 2, P.dark); // legs
  } else if (kind === "spirit") {
    // wavy ghost bottom: erase alternating bottom pixels
    const y = top + bodyH - 1;
    for (let x = cx - widths[bodyH - 1]; x < cx; x++) if ((x + cx) % 2) { put(x, y, null); put(2 * cx - 1 - x, y, null); }
    mput(cx - 1, headY - 1, P.accent); // little flame tuft
  } else if (kind === "mech") {
    put(cx - 1, headY - 2, P.dark); put(cx - 1, headY - 3, P.accent); // antenna
    mput(cx - widths[1], top + 1, P.dark); // shoulder rivets
    mput(cx - 2, top + bodyH, P.dark); // treads/feet
  }

  // Eyes (skip cocoon)
  if (id !== "cocoon") {
    const eyeY = headY + (kind === "mech" ? 2 : 1) + (rnd() < 0.3 ? 1 : 0);
    const eyeX = cx - Math.max(2, Math.floor(widths[0] / 2) + 1);
    if (kind === "mech") { mput(eyeX, eyeY, P.accent); }
    else { mput(eyeX, eyeY, "#ffffff"); mput(eyeX, eyeY + 0, null); mput(eyeX, eyeY, "#ffffff"); mput(eyeX, eyeY, "#ffffff"); mput(eyeX, eyeY, "#ffffff"); mput(eyeX, eyeY, "#ffffff"); put(eyeX, eyeY, "#1a1a1a"); put(2 * cx - 1 - eyeX, eyeY, "#1a1a1a"); }
  }

  // Outline: any body pixel adjacent to empty gets darkened edge below
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (g[y][x] && (y + 1 >= S || !g[y + 1]?.[x])) if (g[y][x] === P.body) g[y][x] = g[y][x]; // keep
  }
  return g;
}

function gridToSvg(g) {
  let rects = "";
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (g[y][x]) rects += `<rect x="${x}" y="${y}" width="1" height="1" fill="${g[y][x]}"/>`;
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${S * SCALE}" height="${S * SCALE}" viewBox="0 0 ${S} ${S}" shape-rendering="crispEdges">${rects}</svg>`;
}

const tiles = [];
for (const [id, kind, tier, seed] of UNITS) {
  const g = drawCritter(kind, tier, seed, id);
  const svg = gridToSvg(g);
  const png = await sharp(Buffer.from(svg)).png().toBuffer();
  await sharp(png).toFile(join(OUT, `${id}.png`));
  tiles.push({ id, png });
}

// Contact sheet for quick review (5 cols)
const COLS = 5, CELL = S * SCALE;
const rows = Math.ceil(tiles.length / COLS);
await sharp({ create: { width: COLS * CELL, height: rows * CELL, channels: 4, background: "#1e2130" } })
  .composite(tiles.map((t, i) => ({ input: t.png, left: (i % COLS) * CELL, top: Math.floor(i / COLS) * CELL })))
  .png().toFile(join(OUT, "_sheet.png"));

console.log(`wrote ${tiles.length} sprites + _sheet.png -> ${OUT}`);
