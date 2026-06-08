// Composite several pets into ONE framed scene (a bottom-anchored line-up on a soft
// sky gradient) for collection thumbnails , fancier than separate tiles. Shared by
// the home "Browse by collection" cards and the /collections list.

type Frame = { x: number; y: number; w: number; h: number };

function seg(a: boolean[]): [number, number][] {
  const r: [number, number][] = []; let s: number | null = null;
  for (let i = 0; i < a.length; i++) { if (a[i] && s === null) s = i; else if (!a[i] && s !== null) { r.push([s, i]); s = null; } }
  if (s !== null) r.push([s, a.length]); return r;
}

// Bounding box of the first frame (first row, first column blob) of a spritesheet.
function firstFrame(img: HTMLImageElement): Frame | null {
  const w = img.naturalWidth, h = img.naturalHeight, TH = 16;
  const off = document.createElement("canvas"); off.width = w; off.height = h;
  const o = off.getContext("2d"); if (!o) return null;
  o.drawImage(img, 0, 0);
  let px: Uint8ClampedArray; try { px = o.getImageData(0, 0, w, h).data; } catch { return null; }
  const rowHas: boolean[] = new Array(h).fill(false);
  for (let y = 0; y < h; y++) { const b = y * w * 4; for (let x = 0; x < w; x++) if (px[b + x * 4 + 3] > TH) { rowHas[y] = true; break; } }
  const rows = seg(rowHas); if (!rows.length) return null;
  const [y0, y1] = rows[0];
  const colHas: boolean[] = new Array(w).fill(false);
  for (let x = 0; x < w; x++) for (let y = y0; y < y1; y++) if (px[(y * w + x) * 4 + 3] > TH) { colHas[x] = true; break; }
  const cols = seg(colHas); if (!cols.length) return null;
  const [x0, x1] = cols[0];
  return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
}

export function drawComposite(cv: HTMLCanvasElement, slugs: string[]): void {
  const ctx = cv.getContext("2d"); if (!ctx) return;
  ctx.imageSmoothingEnabled = false;
  const W = cv.width, H = cv.height;
  // soft sky gradient backdrop
  const g = ctx.createLinearGradient(0, 0, 0, H);
  g.addColorStop(0, "#cfe0ff"); g.addColorStop(1, "#eef4ff");
  ctx.fillStyle = g; ctx.fillRect(0, 0, W, H);

  const picks = slugs.slice(0, 5);
  const n = picks.length || 1;
  const mid = Math.floor((n - 1) / 2);
  picks.forEach((slug, i) => {
    const img = new Image();
    img.onload = () => {
      const f = firstFrame(img); if (!f) return;
      const slot = W / n;
      const targetH = H * (i === mid ? 0.86 : 0.64);
      const s = Math.min(targetH / f.h, (slot * 1.15) / f.w);
      const dw = f.w * s, dh = f.h * s;
      const cx = slot * (i + 0.5);
      ctx.drawImage(img, f.x, f.y, f.w, f.h, cx - dw / 2, H - dh - H * 0.06, dw, dh);
    };
    img.src = "/api/sprite/" + slug;
  });
}
