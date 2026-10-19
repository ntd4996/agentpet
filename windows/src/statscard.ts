// The pet's right-click stats card, a port of the macOS PetStatsView:
// header (sprite, level, stage, hunger), XP, achievements, the four stat
// cells, 7-day burn, cost, subscription limits, last fed, and a footer.
// Pure HTML builders live here so they can be tested without a webview.

import * as care from "./care";
import * as limits from "./limits";
import { t } from "./i18n";

// mac PetStatsView.stageColors: green, teal, blue, purple, orange.
export const STAGE_COLORS = ["#30d158", "#40c8e0", "#0a84ff", "#bf5af2", "#ff9f0a"];

export const ACH_HINT: Record<string, string> = {
  firstMeal: "Finish your first agent session", sessions100: "Finish 100 agent sessions",
  sessions500: "Finish 500 agent sessions", tokens1M: "Burn 1M tokens", tokens10M: "Burn 10M tokens",
  tokens50M: "Burn 50M tokens", level5: "Reach Level 5", level10: "Reach Level 10",
  level20: "Reach Level 20", level35: "Reach Level 35 (Legend)", streak7: "Feed your pet 7 days in a row",
  streak14: "Feed your pet 14 days in a row", streak30: "Feed your pet 30 days in a row",
  nightOwl: "Finish a session after midnight",
};

export function esc(s: string): string {
  return String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

/// mac PetStatsView.tokenString: 1.2M / 962k / 512.
export function tokenString(n: number): string {
  n = Math.max(0, Math.floor(Number(n) || 0));
  if (n >= 1_000_000) return `${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `${Math.round(n / 1_000)}k`;
  return String(n);
}

/// Continuous fullness 0..1: 48 h since the last feeding is empty (mac `fullness`).
export function fullness(s: care.CareState, now = Date.now()): number {
  if (s.lastFedAt == null) return 0.5;
  return Math.max(0, Math.min(1, 1 - (now - s.lastFedAt) / 3_600_000 / 48));
}

/// XP earned inside the current level and the level's span (mac xpWithinLevel).
export function xpWithinLevel(xp: number): { inLevel: number; span: number } {
  const level = care.levelForXP(xp);
  const floor = care.xpToReach(level), ceil = care.xpToReach(level + 1);
  return { inLevel: Math.max(0, xp - floor), span: Math.max(1, ceil - floor) };
}

/// "4 minutes ago" in the UI language.
export function relativeAgo(ms: number, now = Date.now(), lang = "en"): string {
  const secs = Math.round((ms - now) / 1000);
  const rtf = new Intl.RelativeTimeFormat(lang === "zh-TW" ? "zh-Hant" : lang, { numeric: "auto" });
  const a = Math.abs(secs);
  if (a < 60) return rtf.format(secs, "second");
  if (a < 3600) return rtf.format(Math.round(secs / 60), "minute");
  if (a < 86400) return rtf.format(Math.round(secs / 3600), "hour");
  return rtf.format(Math.round(secs / 86400), "day");
}

const HUNGER_LABEL: Record<care.Hunger, string> = {
  full: "Full", satisfied: "Satisfied", peckish: "Peckish", hungry: "Hungry", starving: "Starving",
};

export interface CardInput {
  name: string;
  state: care.CareState;
  providers: limits.LimitProvider[];
  costToday: number;
  costMonth: number;
  now?: number;
  lang?: string;
}

/// Everything below the sprite thumbnail. The thumbnail is a canvas the caller
/// draws into (`#sc-thumb`), so the HTML stays pure.
export function cardHtml(inp: CardInput): string {
  const s = inp.state, now = inp.now ?? Date.now();
  const internal = care.levelForXP(s.xp);
  const level = care.displayLevel(s.xp);
  const stage = care.stageIndex(internal);
  const color = STAGE_COLORS[Math.min(stage, STAGE_COLORS.length - 1)];
  const progress = care.levelProgress(s.xp);
  const { inLevel, span } = xpWithinLevel(s.xp);
  const full = fullness(s, now);
  const fullColor = full > 0.5 ? "#30d158" : full > 0.25 ? "#ff9f0a" : "#ff453a";
  const hunger = care.hunger(s, new Date(now));
  const unlocked = new Set(s.unlockedAchievements || []);
  const days = care.recentDays(s, 7, new Date(now));
  const peak = Math.max(1, ...days.map((d) => d.tokens));
  const meals = s.mealsToday === 1 ? t("1 meal") : t("%d meals").replace("%d", String(s.mealsToday));
  const money = (v: number) => `$${v.toFixed(2)}`;
  const nf = new Intl.NumberFormat();

  const cell = (label: string, value: string, sub: string) =>
    `<div class="sc-cell"><div class="sc-cl">${esc(t(label).toUpperCase())}</div>` +
    `<div class="sc-cv">${esc(value)}</div><div class="sc-cs">${esc(sub)}</div></div>`;

  const badges = care.ACHIEVEMENTS.map((a) =>
    `<span class="sc-badge${unlocked.has(a) ? " on" : ""}" data-ach="${a}" style="${unlocked.has(a) ? `color:${color}` : ""}">${care.ACH_ICON[a]}</span>`).join("");

  const bars = days.map((d, i) =>
    `<div class="sc-bw" title="${esc(tokenString(d.tokens))}"><div class="sc-bar" style="height:${Math.max(3, Math.round((d.tokens / peak) * 34))}px;background:${color};opacity:${i === days.length - 1 ? 1 : 0.4}"></div><div class="sc-bl">${esc(d.label)}</div></div>`).join("");

  const shown = limits.visible(inp.providers);
  const limitsHtml = shown.length
    ? `<div class="sc-sec"><span>${esc(t("Limits"))}</span></div>` +
      shown.map((p) => `<div class="sc-prov"><div class="sc-pname">${esc(p.display_name)}</div>${limits.windowRowsHtml(p, true)}</div>`).join("")
    : "";

  return `
  <div class="sc-head">
    <div class="sc-thumbwrap" style="background:${color}24"><canvas id="sc-thumb" width="46" height="46"></canvas></div>
    <div class="sc-id">
      <div class="sc-name">${esc(inp.name)}</div>
      <div class="sc-lvrow"><b style="color:${color}">Lv ${level}</b>
        <span class="sc-stage" style="color:${color};background:${color}33">${esc(t(care.stageName(internal)))}</span></div>
    </div>
    <div class="sc-hunger"><div>${esc(t(HUNGER_LABEL[hunger]))}</div>
      <div class="sc-fbar"><div style="width:${Math.round(full * 100)}%;background:${fullColor}"></div></div></div>
  </div>
  <div class="sc-xp">
    <div class="sc-pbar"><div style="width:${(progress * 100).toFixed(1)}%;background:${color}"></div></div>
    <div class="sc-xprow"><span>${nf.format(inLevel)} / ${nf.format(span)} XP</span><b style="color:${color}">${Math.round(progress * 100)}%</b></div>
    <div class="sc-next" style="color:${color}">${esc(t("≈ %@ tokens to Lv %d").replace("%@", tokenString(care.tokensToNextLevel(s))).replace("%d", String(level + 1)))}</div>
  </div>
  <div class="sc-sec"><span>${esc(t("Achievements"))}</span><b>${unlocked.size} / ${care.ACHIEVEMENTS.length}</b></div>
  <div class="sc-badges">${badges}</div>
  <div class="sc-hint" id="sc-hint">${esc(t("Hover a badge to see how to unlock it"))}</div>
  <div class="sc-grid">
    ${cell("Today", tokenString(s.tokensToday), meals)}
    ${cell("Streak", String(s.streakDays), t("days fed"))}
    ${cell("Lifetime", tokenString(s.totalTokens), t("tokens eaten"))}
    ${cell("Sessions", String(s.totalMeals), t("completed"))}
  </div>
  <div class="sc-sec"><span>${esc(t("Burn, last 7 days"))}</span><b>${esc(tokenString(days.reduce((a, d) => a + d.tokens, 0)))}</b></div>
  <div class="sc-chart">${bars}</div>
  <div class="sc-sec"><span>${esc(t("Est. cost (Claude)"))}</span><b>${esc(t("Today %@ · Month %@").replace("%@", money(inp.costToday)).replace("%@", money(inp.costMonth)))}</b></div>
  ${limitsHtml}
  ${s.lastFedAt != null ? `<div class="sc-last"><span>${esc(t("Last fed"))}</span><span>${esc(relativeAgo(s.lastFedAt, now, inp.lang))}</span></div>` : ""}`;
}

/// Text for the hovered badge (mac achievementHint).
export function hintText(ach: string, unlocked: boolean): string {
  return `${unlocked ? "✓" : "🔒"} ${t(care.ACH_NAME[ach] || ach)} · ${t(ACH_HINT[ach] || "")}`;
}
