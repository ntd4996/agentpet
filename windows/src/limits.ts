// Subscription limits , a port of the macOS NativeUsageProbe consumers
// (UsageVisibility, LimitFormat, LimitWindowsView). Rust reads the provider
// sign-in and calls the usage API (`get_limits`); only percentages and reset
// times reach the webview. Each window (pet / settings) polls on its own and
// caches the last answer in localStorage so the Care tab paints instantly.

import { invoke } from "@tauri-apps/api/core";
import { t } from "./i18n";

export interface LimitWindow {
  label: string;
  fraction_left: number;
  resets_at: string | null;
  period: number;
}
export interface LimitProvider {
  id: string;
  display_name: string;
  windows: LimitWindow[];
}

const CACHE_KEY = "ap_limits";
const HIDDEN_KEY = "ap_limits_hidden";
const AT_KEY = "ap_limits_at";
export const POLL_MS = 300_000; // mac NativeUsageProbe.pollInterval
/// Below this much left the pet turns anxious (mac Thresholds.RateLimit.low).
export const LOW = 0.15;

export function cached(): LimitProvider[] {
  try {
    const v = JSON.parse(localStorage.getItem(CACHE_KEY) || "[]");
    return Array.isArray(v) ? v : [];
  } catch { return []; }
}

/// Asks Rust for fresh limits. A failed probe (offline, expired sign-in) keeps
/// nothing: stale numbers would make the pet worry about an old window.
export async function refresh(): Promise<LimitProvider[]> {
  let found: LimitProvider[] = [];
  try { found = await invoke<LimitProvider[]>("get_limits"); } catch { found = []; }
  localStorage.setItem(CACHE_KEY, JSON.stringify(found));
  localStorage.setItem(AT_KEY, String(Date.now()));
  return found;
}

/// Refreshes only when the cached answer is older than `maxAgeMs`, so opening
/// the Care tab repeatedly doesn't hammer the provider.
export async function refreshIfStale(maxAgeMs = 60_000): Promise<LimitProvider[]> {
  const at = Number(localStorage.getItem(AT_KEY) || 0);
  if (Date.now() - at < maxAgeMs) return cached();
  return refresh();
}

// ---- visibility (mac UsageVisibility) -----------------------------------------

function hiddenSet(): Set<string> {
  try { return new Set(JSON.parse(localStorage.getItem(HIDDEN_KEY) || "[]")); } catch { return new Set(); }
}
export function isVisible(id: string): boolean { return !hiddenSet().has(id); }
export function setVisible(id: string, on: boolean) {
  const h = hiddenSet();
  if (on) h.delete(id); else h.add(id);
  localStorage.setItem(HIDDEN_KEY, JSON.stringify([...h].sort()));
}
export function visible(providers: LimitProvider[]): LimitProvider[] {
  return providers.filter((p) => isVisible(p.id));
}

/// Tightest budget left among visible providers; feeds the rate-limit bubble.
export function lowestFractionLeft(providers: LimitProvider[]): number | null {
  const all = visible(providers).flatMap((p) => p.windows.map((w) => w.fraction_left));
  return all.length ? Math.min(...all) : null;
}
/// True when a visible provider is nearly spent; feeds the anxious idle lines.
export function limitLow(providers: LimitProvider[]): boolean {
  const left = lowestFractionLeft(providers);
  return left != null && left < LOW;
}

// ---- formatting (mac LimitFormat) ---------------------------------------------

/// "Session · 5h" / "Weekly · 7d".
export function title(w: LimitWindow): string {
  const hours = Math.round(w.period / 3600);
  const short = w.period > 0 ? (hours < 24 ? `${hours}h` : `${Math.round(w.period / 86400)}d`) : "";
  const label = t(w.label);
  if (!short) return label;
  return label ? `${label} · ${short}` : short;
}

function fmt(key: string, n: number): string { return t(key).replace("%d", String(n)); }

/// "resets in 3h · 14:30" (same-day clock, weekday within 6 days, else date).
/// Empty when unknown or already past.
export function resetText(iso: string | null, now = new Date()): string {
  if (!iso) return "";
  const ms = /^\d+(\.\d+)?$/.test(iso) ? Number(iso) * 1000 : Date.parse(iso);
  if (!Number.isFinite(ms)) return "";
  const secs = (ms - now.getTime()) / 1000;
  if (secs <= 0) return "";
  const rel = secs >= 86400 ? fmt("resets in %dd", Math.floor(secs / 86400))
    : secs >= 3600 ? fmt("resets in %dh", Math.floor(secs / 3600))
    : fmt("resets in %dm", Math.max(1, Math.floor(secs / 60)));
  const d = new Date(ms);
  const sameDay = d.toDateString() === now.toDateString();
  const opts: Intl.DateTimeFormatOptions = sameDay ? { hour: "2-digit", minute: "2-digit" }
    : secs < 6 * 86400 ? { weekday: "short", hour: "2-digit", minute: "2-digit" }
    : { month: "short", day: "numeric" };
  return `${rel} · ${d.toLocaleString([], opts)}`;
}

/// Bar colour: red past 90% used, orange past 75%, else the pet's tint.
export function barColor(used: number): string {
  return used > 0.9 ? "#e5484d" : used > 0.75 ? "#f5a623" : "#30a46c";
}

function resetMs(iso: string | null): number {
  if (!iso) return NaN;
  return /^\d+(\.\d+)?$/.test(iso) ? Number(iso) * 1000 : Date.parse(iso);
}

/// "↻ 14:30" / "↻ Mon 11:00" for tight spaces (mac LimitFormat.compactReset).
export function compactReset(iso: string | null, now = new Date()): string {
  const ms = resetMs(iso);
  if (!Number.isFinite(ms) || ms <= now.getTime()) return "";
  const d = new Date(ms);
  const sameDay = d.toDateString() === now.toDateString();
  const opts: Intl.DateTimeFormatOptions = sameDay ? { hour: "2-digit", minute: "2-digit" }
    : (ms - now.getTime()) < 6 * 86400_000 ? { weekday: "short", hour: "2-digit", minute: "2-digit" }
    : { month: "short", day: "numeric" };
  return `↻ ${d.toLocaleString([], opts)}`;
}

function escH(s: string): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

/// One provider's windows as bar rows (mac LimitWindowsView). `compact` uses
/// the short reset clock for the popover; the Care tab has room for the full one.
export function windowRowsHtml(p: LimitProvider, compact: boolean): string {
  return p.windows.map((w) => {
    const used = Math.min(1, Math.max(0, 1 - w.fraction_left));
    const color = barColor(used);
    const rst = compact ? compactReset(w.resets_at) : resetText(w.resets_at);
    const pct = t("%d%% used").replace("%d", String(Math.round(used * 100))).replace("%%", "%");
    return `<div class="limit-row">
      <div class="limit-head"><span class="lbl">${escH(title(w))}</span>
        <span class="pct" style="color:${color}">${escH(pct)}</span>
        ${rst ? `<span class="rst">· ${escH(rst)}</span>` : ""}</div>
      <div class="limit-bar"><div style="width:${(used * 100).toFixed(1)}%;background:${color}"></div></div>
    </div>`;
  }).join("");
}

// ---- pet bubble lines (mac ReactiveEngine.rateLimit + CareChat.anxious) ------

export const ANXIOUS = [
  "Careful… your AI budget is almost gone.",
  "Low fuel: a usage limit is nearly reached!",
  "Maybe save some tokens for tomorrow…",
];
