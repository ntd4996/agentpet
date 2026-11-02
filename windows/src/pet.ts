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

export interface Rect { x: number; y: number; w: number; h: number }

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
    const clip = segments(colHas).map(([x0, x1]) => ({ x: x0, y: y0, w: x1 - x0, h: y1 - y0 }));
    if (clip.length) clips.push(clip);
  }
  return clips;
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

  /// True when a CSS-pixel point inside the canvas hits the SPRITE (alpha
  /// test), so clicks on the empty area around the pet don't drag the window.
  hitTest(cssX: number, cssY: number): boolean {
    const r = this.spriteRect;
    if (!r) return false;
    const kx = this.canvas.width / (this.canvas.clientWidth || 1);
    const ky = this.canvas.height / (this.canvas.clientHeight || 1);
    const x = cssX * kx, y = cssY * ky;
    if (x < r.x || x > r.x + r.w || y < r.y || y > r.y + r.h) return false;
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
    this.spriteRect = { x: (W - dw) / 2, y: H - dh, w: dw, h: dh };
    this.ctx.drawImage(this.img, r.x, r.y, r.w, r.h, (W - dw) / 2, H - dh, dw, dh);
  }
}
