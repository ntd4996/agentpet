// Generates the social/OG image (1200x630) from the island art on a sky gradient.
//   node scripts/make-og.mjs   ->   public/og.png
import sharp from "sharp";
import { writeFileSync } from "node:fs";

const W = 1200, H = 630;

const bg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}">
  <defs>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#cfe0ff"/><stop offset="1" stop-color="#eef4ff"/>
    </linearGradient>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#sky)"/>
  <ellipse cx="250" cy="120" rx="120" ry="42" fill="#ffffff" opacity="0.7"/>
  <ellipse cx="330" cy="135" rx="80" ry="34" fill="#ffffff" opacity="0.7"/>
  <ellipse cx="980" cy="90" rx="130" ry="46" fill="#ffffff" opacity="0.6"/>
  <text x="70" y="180" font-family="Verdana, Arial, sans-serif" font-size="26" font-weight="700" letter-spacing="3" fill="#2563eb">FREE · OPEN SOURCE</text>
  <text x="68" y="300" font-family="Verdana, Arial, sans-serif" font-size="104" font-weight="800" fill="#1f2747">Agent<tspan fill="#2563eb">Pet</tspan></text>
  <text x="72" y="372" font-family="Verdana, Arial, sans-serif" font-size="40" font-weight="600" fill="#3f4a6b">Pixel companions for your</text>
  <text x="72" y="424" font-family="Verdana, Arial, sans-serif" font-size="40" font-weight="600" fill="#3f4a6b">AI coding agents</text>
  <text x="72" y="500" font-family="Verdana, Arial, sans-serif" font-size="30" font-weight="700" fill="#2563eb">4,044 pets · macOS · free</text>
</svg>`;

const bgPng = await sharp(Buffer.from(bg)).png().toBuffer();
const island = await sharp("public/art/island-world.webp").resize({ height: 470 }).toBuffer();
const m = await sharp(island).metadata();
const out = await sharp(bgPng)
  .composite([{ input: island, top: H - (m.height || 470) - 24, left: W - (m.width || 470) - 24 }])
  .png()
  .toBuffer();
writeFileSync(new URL("../public/og.png", import.meta.url), out);
console.error(`wrote public/og.png (${out.length} bytes)`);
