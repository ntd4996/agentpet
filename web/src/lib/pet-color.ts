// Dominant-colour analysis for pet spritesheets. Shared by scripts/analyze-pets.mjs
// (bulk seed, sharp-decoded pixels) and the admin approval flow (canvas pixels), so
// both classify a pet the same way. Input is RGBA bytes of the sheet scaled to 240px wide.
export const COLORS = [
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
export const COLOR_BY_KEY = Object.fromEntries(COLORS.map((c) => [c.name.toLowerCase(), c]));

export function rgbToHsl(r: number, g: number, b: number): [number, number, number] {
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
export function hueName(h: number): string {
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
export function dominantColor(data: ArrayLike<number>, w: number, h: number): string {
  const hue: number[] = new Array(360).fill(0);
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
