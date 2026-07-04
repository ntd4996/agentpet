// Tamagotchi care engine , a TypeScript port of the macOS app's PetCare. The
// pet is fed by the real tokens agents burn and the sessions they finish; it
// earns XP, levels up, and evolves through five stages. State is per-pet and
// persisted to localStorage. Web sync (leaderboard/profile) lives in sync.ts.

export const TOKENS_PER_XP = 5_000;
export const MEAL_XP = 25;

export type Hunger = "full" | "satisfied" | "peckish" | "hungry" | "starving";

export interface CareState {
  xp: number;
  tokenCarry: number;
  tokensToday: number;
  mealsToday: number;
  totalTokens: number;
  totalMeals: number;
  lastFedAt: number | null; // ms epoch
  dayKey: string;
  streakDays: number;
  lastFedDayKey: string | null;
  days: Record<string, number>; // dayKey -> tokens (last 14)
}

export function emptyState(): CareState {
  return {
    xp: 0, tokenCarry: 0, tokensToday: 0, mealsToday: 0,
    totalTokens: 0, totalMeals: 0, lastFedAt: null,
    dayKey: dayKey(new Date()), streakDays: 0, lastFedDayKey: null, days: {},
  };
}

// ---- level / stage math (must match PetCare.swift) --------------------------

// Total XP to *reach* level n is 60·n·(n-1).
export function xpToReach(level: number): number {
  if (level <= 1) return 0;
  return 60 * level * (level - 1);
}

export function levelForXP(xp: number): number {
  let level = 1;
  while (xpToReach(level + 1) <= xp) level += 1;
  return level;
}

// The level shown to the user (internal level minus one, floored at 0).
export function displayLevel(xp: number): number {
  return Math.max(0, levelForXP(xp) - 1);
}

export function stageIndex(level: number): number {
  if (level < 5) return 0;
  if (level < 10) return 1;
  if (level < 20) return 2;
  if (level < 35) return 3;
  return 4;
}

export const STAGE_NAMES = ["Hatchling", "Companion", "Scout", "Hero", "Legend"];
export function stageName(level: number): string {
  return STAGE_NAMES[stageIndex(level)];
}

// Progress (0..1) through the current level, for the XP bar.
export function levelProgress(xp: number): number {
  const level = levelForXP(xp);
  const floor = xpToReach(level);
  const ceiling = xpToReach(level + 1);
  if (ceiling <= floor) return 0;
  return Math.min(1, Math.max(0, (xp - floor) / (ceiling - floor)));
}

export function tokensToNextLevel(state: CareState): number {
  const xpNeeded = xpToReach(levelForXP(state.xp) + 1) - state.xp;
  return Math.max(0, xpNeeded * TOKENS_PER_XP - state.tokenCarry);
}

export function hunger(state: CareState, now = new Date()): Hunger {
  if (state.lastFedAt == null) return "peckish";
  const hours = (now.getTime() - state.lastFedAt) / 3_600_000;
  if (hours < 4) return "full";
  if (hours < 10) return "satisfied";
  if (hours < 24) return "peckish";
  if (hours < 48) return "hungry";
  return "starving";
}

// ---- feeding ----------------------------------------------------------------

export function dayKey(d: Date): string {
  const y = d.getFullYear(), m = d.getMonth() + 1, day = d.getDate();
  return `${y.toString().padStart(4, "0")}-${m.toString().padStart(2, "0")}-${day.toString().padStart(2, "0")}`;
}

function rollover(s: CareState, now: Date) {
  const today = dayKey(now);
  if (s.dayKey === today) return;
  s.dayKey = today;
  s.tokensToday = 0;
  s.mealsToday = 0;
}

function markFed(s: CareState, now: Date) {
  s.lastFedAt = now.getTime();
  const today = dayKey(now);
  if (s.lastFedDayKey === today) {
    // already fed today, streak unchanged
  } else {
    const yesterday = dayKey(new Date(now.getTime() - 86_400_000));
    s.streakDays = s.lastFedDayKey === yesterday ? s.streakDays + 1 : 1;
    s.lastFedDayKey = today;
  }
}

/** Feeds token usage. XP accrues at TOKENS_PER_XP with the remainder carried. */
export function feedTokens(s: CareState, tokens: number, now = new Date()): number {
  if (tokens <= 0) return 0;
  rollover(s, now);
  s.totalTokens += tokens;
  s.tokensToday += tokens;
  const today = dayKey(now);
  s.days[today] = (s.days[today] ?? 0) + tokens;
  const keys = Object.keys(s.days).sort();
  if (keys.length > 14) for (const k of keys.slice(0, keys.length - 14)) delete s.days[k];
  const pool = s.tokenCarry + tokens;
  const gained = Math.floor(pool / TOKENS_PER_XP);
  s.tokenCarry = pool % TOKENS_PER_XP;
  s.xp += gained;
  markFed(s, now);
  return gained;
}

/** Records a finished session (a "proper meal"). */
export function recordMeal(s: CareState, now = new Date()): number {
  rollover(s, now);
  s.totalMeals += 1;
  s.mealsToday += 1;
  s.xp += MEAL_XP;
  markFed(s, now);
  return MEAL_XP;
}

/** Tokens per day for the trailing `count` days, oldest first, for the chart. */
export function recentDays(s: CareState, count = 7, now = new Date()): { label: string; tokens: number }[] {
  const out: { label: string; tokens: number }[] = [];
  for (let offset = count - 1; offset >= 0; offset--) {
    const d = new Date(now.getTime() - offset * 86_400_000);
    out.push({ label: String(d.getDate()), tokens: s.days[dayKey(d)] ?? 0 });
  }
  return out;
}

// ---- per-pet persistence ----------------------------------------------------

const KEY = "ap_care";

type Store = Record<string, CareState>;

function load(): Store {
  try { return JSON.parse(localStorage.getItem(KEY) || "{}"); } catch { return {}; }
}
function save(store: Store) {
  localStorage.setItem(KEY, JSON.stringify(store));
}

export function stateFor(petId: string): CareState {
  const store = load();
  return { ...emptyState(), ...(store[petId] || {}) };
}

export function mutate(petId: string, change: (s: CareState) => void): CareState {
  const store = load();
  const s = { ...emptyState(), ...(store[petId] || {}) };
  change(s);
  store[petId] = s;
  save(store);
  return s;
}

export function allStates(): Store {
  return load();
}
