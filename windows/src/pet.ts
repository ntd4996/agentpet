// Renders + animates a pet spritesheet on a canvas. Sheets are sliced with
// alpha-gutter detection (a port of the macOS app's SpriteSlicer): transparent
// gaps split the sheet into rows, then each row into frames. That way empty
// cells in a row simply don't exist , the pet never blinks out on sparse rows,
// and ragged/AI-generated sheets slice correctly. Falls back to a fixed 8x9
// grid when pixels can't be read (no CORS).

const COLS = 8;
const ROWS = 9;
const ALPHA_THRESHOLD = 16;

// Row index per state, matching the macOS app's spritesheet layout:
// 0 Idle, 1 RunRight, 2 RunLeft, 3 Waving, 4 Jumping, 5 Failed, 6 Waiting, 7 Running, 8 Review
const STATE_ROW: Record<string, number> = {
  idle: 0,
  registered: 0,
  working: 7,
  waiting: 6,
  done: 3,       // waving goodbye to the finished task
  celebrate: 4,  // jumping , the 3s burst when all work completes
};

// Frame rate varies by mood (faster while working), like the macOS app.
const STATE_FPS: Record<string, number> = {
  working: 8,
  celebrate: 8,
  waiting: 4,
  done: 3,
  idle: 3,
  registered: 3,
};

export interface Rect {
  x: number; y: number; w: number; h: number;
  /// Tight box of the visible (non-transparent) pixels, relative to this frame's
  /// top-left. The frame itself is a grid cell (whole row band x column run), so it
  /// usually has transparent padding; `ink` is what the pet really covers.
  ink?: { x: number; y: number; w: number; h: number };
  /// Per source row of this frame: [minX, maxX] of the visible pixels relative to the
  /// frame's left edge, or minX = -1 for an empty row. Drives the silhouette hit region.
  rows?: Int16Array;
}

/// Contiguous runs of `true` in an occupancy array → [start, end) pairs.
function segments(occ: Uint8Array): Array<[number, number]> {
  const out: Array<[number, number]> = [];
  let start = -1;
  for (let i = 0; i < occ.length; i++) {
    if (occ[i] && start < 0) start = i;
    else if (!occ[i] && start >= 0) { out.push([start, i]); start = -1; }
  }
  if (start >= 0) out.push([start, occ.length]);
  return out;
}

/// Tight bounds of the visible pixels inside [x0,x1) x [y0,y1), relative to (x0,y0).
/// Same alpha threshold as the slicer, so "visible" means the same everywhere.
function inkBox(data: Uint8ClampedArray, w: number, x0: number, y0: number, x1: number, y1: number): Rect["ink"] {
  let minX = x1, minY = y1, maxX = -1, maxY = -1;
  for (let y = y0; y < y1; y++) {
    const off = y * w * 4;
    for (let x = x0; x < x1; x++) {
      if (data[off + x * 4 + 3] > ALPHA_THRESHOLD) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        maxY = y; // rows ascend, so the last hit is the lowest
      }
    }
  }
  if (maxX < 0) return undefined; // empty frame: caller falls back to the cell
  return { x: minX - x0, y: minY - y0, w: maxX - minX + 1, h: maxY - minY + 1 };
}

/// Visible extent [minX, maxX] of every row of the frame (relative to x0); -1 when empty.
function rowExtents(data: Uint8ClampedArray, w: number, x0: number, y0: number, x1: number, y1: number): Int16Array {
  const out = new Int16Array((y1 - y0) * 2);
  for (let y = y0; y < y1; y++) {
    const off = y * w * 4;
    let lo = -1, hi = -1;
    for (let x = x0; x < x1; x++) {
      if (data[off + x * 4 + 3] > ALPHA_THRESHOLD) { if (lo < 0) lo = x - x0; hi = x - x0; }
    }
    out[(y - y0) * 2] = lo;
    out[(y - y0) * 2 + 1] = hi;
  }
  return out;
}

/// Alpha-gutter slice: rows by transparent bands, then frames within each row.
export function slice(img: HTMLImageElement): Rect[][] {
  const w = img.naturalWidth, h = img.naturalHeight;
  if (!w || !h) return [];
  const cv = document.createElement("canvas");
  cv.width = w; cv.height = h;
  const ctx = cv.getContext("2d", { willReadFrequently: true });
  if (!ctx) return [];
  ctx.drawImage(img, 0, 0);
  let data: Uint8ClampedArray;
  try {
    data = ctx.getImageData(0, 0, w, h).data;
  } catch {
    return []; // tainted (no CORS) , caller falls back to the fixed grid
  }
  const rowHas = new Uint8Array(h);
  for (let y = 0; y < h; y++) {
    const off = y * w * 4;
    for (let x = 0; x < w; x++) {
      if (data[off + x * 4 + 3] > ALPHA_THRESHOLD) { rowHas[y] = 1; break; }
    }
  }
  const clips: Rect[][] = [];
  for (const [y0, y1] of segments(rowHas)) {
    const colHas = new Uint8Array(w);
    for (let y = y0; y < y1; y++) {
      const off = y * w * 4;
      for (let x = 0; x < w; x++) {
        if (data[off + x * 4 + 3] > ALPHA_THRESHOLD) colHas[x] = 1;
      }
    }
    const clip = segments(colHas).map(([x0, x1]) => ({ x: x0, y: y0, w: x1 - x0, h: y1 - y0, ink: inkBox(data, w, x0, y0, x1, y1), rows: rowExtents(data, w, x0, y0, x1, y1) }));
    if (clip.length) clips.push(clip);
  }
  return clips;
}

/// Hit bands of a whole clip: the union of the visible rows of EVERY frame, each
/// drawn centred and bottom-anchored like draw() does, merged per canvas row and
/// grouped into bands about BAND_PX tall. Only depends on the clip and the scale,
/// so it stays still while the animation plays (no flicker at the pet's edge).
const BAND_PX = 4;
/// CSS px of slack around the hit region so grabbing right at the edge still works.
export const HIT_PAD = 4;
function clipBands(clip: Rect[], s: number, W: number, H: number): { x: number; y: number; w: number; h: number }[] {
  const lo = new Float64Array(H).fill(Infinity);
  const hi = new Float64Array(H).fill(-Infinity);
  for (const f of clip) {
    if (!f.rows) return [];
    const ox = Math.round((W - f.w * s) / 2), oy = Math.round(H - f.h * s);
    const n = f.rows.length / 2;
    for (let ry = 0; ry < n; ry++) {
      const a = f.rows[ry * 2], b = f.rows[ry * 2 + 1];
      if (a < 0) continue;
      const y0 = Math.max(0, Math.floor(oy + ry * s));
      const y1 = Math.min(H, Math.ceil(oy + (ry + 1) * s));
      for (let y = y0; y < y1; y++) {
        lo[y] = Math.min(lo[y], ox + a * s);
        hi[y] = Math.max(hi[y], ox + (b + 1) * s);
      }
    }
  }
  const out: { x: number; y: number; w: number; h: number }[] = [];
  for (let y0 = 0; y0 < H; y0 += BAND_PX) {
    const y1 = Math.min(H, y0 + BAND_PX);
    let l = Infinity, r = -Infinity;
    for (let y = y0; y < y1; y++) { if (lo[y] < l) l = lo[y]; if (hi[y] > r) r = hi[y]; }
    if (r > l) out.push({ x: l, y: y0, w: r - l, h: y1 - y0 });
  }
  return out;
}

export class Pet {
  private ctx: CanvasRenderingContext2D;
  private img = new Image();
  private loaded = false;
  private clips: Rect[][] = [];
  private frame = 0;
  private row = 0;
  private fps = 3;
  /// Unused space above the sprite, as a fraction of canvas height. The bubble
  /// uses it to sit right above the pet's head instead of the canvas top.
  headroom = 0;
  /// Last drawn sprite rect in backing-store pixels , the pet's true bounds.
  spriteRect: { x: number; y: number; w: number; h: number } | null = null;
  /// Hit region that follows the pet's outline: horizontal bands (backing-store px) of the
  /// CURRENT frame, each as wide as the visible pixels in it. Gaps inside a band (between the
  /// legs, between arm and body) count as hit, so the pet is still easy to grab.
  silhouette: { x: number; y: number; w: number; h: number }[] = [];
  /// Called when the hit region changed (clip, state or size), not on every frame.
  onFrame: (() => void) | null = null;
  private bandCache = new Map<string, { x: number; y: number; w: number; h: number }[]>();
  private lastBandKey = "";

  /// True when a CSS-pixel point inside the canvas hits the SPRITE (alpha
  /// test), so clicks on the empty area around the pet don't drag the window.
  hitTest(cssX: number, cssY: number): boolean {
    const r = this.spriteRect;
    if (!r) return false;
    const kx = this.canvas.width / (this.canvas.clientWidth || 1);
    const ky = this.canvas.height / (this.canvas.clientHeight || 1);
    const x = cssX * kx, y = cssY * ky;
    if (x < r.x || x > r.x + r.w || y < r.y || y > r.y + r.h) return false;
    if (this.silhouette.length) {
      // Same bands (and slack) the click-through region uses, so gaps inside the
      // outline (between the legs, arm and body) still grab the pet.
      const padX = HIT_PAD * kx, padY = HIT_PAD * ky;
      return this.silhouette.some((b) => x >= b.x - padX && x <= b.x + b.w + padX && y >= b.y - padY && y <= b.y + b.h + padY);
    }
    try {
      return this.ctx.getImageData(Math.floor(x), Math.floor(y), 1, 1).data[3] > 16;
    } catch {
      return true; // tainted canvas (no CORS): fall back to the rect test
    }
  }

  constructor(private canvas: HTMLCanvasElement) {
    const c = canvas.getContext("2d");
    if (!c) throw new Error("no 2d context");
    this.ctx = c;
    this.ctx.imageSmoothingEnabled = false;
    this.loop();
  }

  /// Widest frame of each clip , scale is computed per CLIP (not per frame)
  /// so the pet doesn't pulse and the bubble doesn't bounce as frames of
  /// slightly different widths cycle.
  private clipMaxW: number[] = [];

  load(spritesheetUrl: string) {
    this.loaded = false;
    const img = new Image();
    img.crossOrigin = "anonymous"; // CDN sends CORS , lets us read alpha
    img.onload = () => {
      this.img = img;
      this.clips = slice(img);
      this.clipMaxW = this.clips.map((clip) => Math.max(...clip.map((r) => r.w)));
      this.bandCache.clear();
      this.lastBandKey = "";
      this.frame = 0;
      this.loaded = true;
      this.draw();
    };
    // A pre-CORS cached copy makes the crossOrigin load fail , retry plain
    // (displayable, but slicing falls back to the fixed grid).
    img.onerror = () => {
      // Diagnostics for the Windows build (debug.log via Rust).
      try {
        // @ts-ignore tauri global (withGlobalTauri)
        window.__TAURI__?.core?.invoke?.("log_debug", { msg: `sprite CORS load failed, plain retry: ${spritesheetUrl.slice(0, 80)}` });
      } catch {}
      const plain = new Image();
      plain.onload = () => {
        this.img = plain;
        this.clips = [];
        this.frame = 0;
        this.loaded = true;
        this.draw();
      };
      plain.src = spritesheetUrl;
    };
    // Cache-bust http(s) URLs so the request actually carries CORS headers
    // instead of replaying a cached non-CORS response.
    img.src = spritesheetUrl.startsWith("data:")
      ? spritesheetUrl
      : spritesheetUrl + (spritesheetUrl.includes("?") ? "&" : "?") + "cors=1";
  }

  setState(state: string) {
    this.fps = STATE_FPS[state] ?? 3;
    // User binding (Settings → Pet → Animations) overrides the default row,
    // like the macOS PetBindings store.
    const bound = parseInt(localStorage.getItem(`ap_bind_${state}`) ?? "", 10);
    const row = Number.isFinite(bound) && bound >= 0 ? bound : (STATE_ROW[state] ?? 0);
    if (row !== this.row) { this.row = row; this.frame = 0; }
  }

  /// The frames of the current row (clamped to what the sheet actually has).
  private currentClip(): Rect[] | null {
    if (!this.clips.length) return null;
    return this.clips[Math.min(this.row, this.clips.length - 1)];
  }

  // Paced by the clip's fps (3-8) instead of a 60Hz requestAnimationFrame that
  // woke the renderer ~8-20x more often than it drew. Skips while hidden.
  private loop() {
    if (this.loaded && !document.hidden) {
      this.frame++;
      this.draw();
    }
    window.setTimeout(() => this.loop(), 1000 / this.fps);
  }

  /// Union of the frames' visible boxes in canvas pixels, at scale `s`.
  private clipInkRect(clip: Rect[], s: number, W: number, H: number): { x: number; y: number; w: number; h: number } {
    let l = Infinity, t = Infinity, r = -Infinity, b = -Infinity;
    for (const f of clip) {
      const dw = f.w * s, dh = f.h * s;
      const ox = Math.round((W - dw) / 2), oy = Math.round(H - dh);
      const ink = f.ink ?? { x: 0, y: 0, w: f.w, h: f.h };
      l = Math.min(l, ox + ink.x * s);
      t = Math.min(t, oy + ink.y * s);
      r = Math.max(r, ox + (ink.x + ink.w) * s);
      b = Math.max(b, oy + (ink.y + ink.h) * s);
    }
    return { x: l, y: t, w: r - l, h: b - t };
  }

  private draw() {
    const { width: W, height: H } = this.canvas;
    this.ctx.clearRect(0, 0, W, H);

    let r: Rect;
    let scaleW: number; // width used for the scale , per CLIP, not per frame
    const clip = this.currentClip();
    if (clip) {
      r = clip[this.frame % clip.length];
      scaleW = this.clipMaxW[Math.min(this.row, this.clips.length - 1)] || r.w;
    } else {
      // Fallback: fixed 8x9 grid (pixels unreadable , e.g. no CORS).
      const fw = this.img.naturalWidth / COLS;
      const fh = this.img.naturalHeight / ROWS;
      if (!fw || !fh) return;
      r = { x: (this.frame % COLS) * fw, y: Math.min(this.row, ROWS - 1) * fh, w: fw, h: fh };
      scaleW = fw;
    }

    // Fit into the canvas, anchored bottom-center; snap to an integer scale so
    // pixel-art stays crisp. The scale comes from the clip's widest frame so
    // every frame of an animation renders at the SAME size (no pulsing, and a
    // stable headroom = the bubble above never bounces).
    const fit = Math.min(W / scaleW, H / r.h);
    const s = fit >= 1 ? Math.floor(fit) : fit;
    const dw = r.w * s, dh = r.h * s;
    this.headroom = (H - dh) / H;
    // Hit region = union of the visible pixels of EVERY frame of this clip (each
    // drawn centred and bottom-anchored like this one), so it hugs the pet but
    // stays steady while the animation plays instead of changing per frame.
    // Whole pixels only: an odd-width frame centred in an even canvas (or the
    // reverse) lands on x.5, and with smoothing off the browser then doubles or
    // drops pixel columns for that frame only (visible as noise, e.g. when the
    // kneel clip stands up: 103px frame at x=28.5). The same value feeds the hit rect.
    const dx = Math.round((W - dw) / 2), dy = Math.round(H - dh);
    this.spriteRect = clip ? this.clipInkRect(clip, s, W, H) : { x: dx, y: dy, w: dw, h: dh };
    this.ctx.drawImage(this.img, r.x, r.y, r.w, r.h, dx, dy, dw, dh);
    // Recomputed only when the clip, scale or canvas size changes.
    const key = `${clip ? this.row : "grid"}|${s}|${W}|${H}`;
    if (key !== this.lastBandKey) {
      this.lastBandKey = key;
      let bands = this.bandCache.get(key);
      if (!bands) {
        bands = clip ? clipBands(clip, s, W, H) : [];
        if (!bands.length) bands = [{ x: this.spriteRect.x, y: this.spriteRect.y, w: this.spriteRect.w, h: this.spriteRect.h }];
        this.bandCache.set(key, bands);
      }
      this.silhouette = bands;
      this.onFrame?.();
    }
  }
}
