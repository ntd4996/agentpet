// Reactive bubbles , a TypeScript port of the macOS ReactiveEngine. The pet
// spontaneously comments on live metrics (daily tokens, session count, hunger,
// streak, daily meals) with tiered phrases and per-metric cooldowns. The macOS
// rate-limit metric is omitted: it needs OpenUsage data the Tauri app lacks.

import { t } from "./i18n";
import type { Hunger } from "./care";

export type Metric = "dailyTokens" | "sessionCount" | "hunger" | "streak" | "dailyMeals";

const TH = {
  dailyTokens: { silent: 1_000_000, low: 3_000_000, mid: 6_000_000 },
  sessionCount: { silent: 5, low: 8 },
  streak: { silent: 4, low: 7, mid: 14 },
  dailyMeals: { silent: 20, low: 50, mid: 100 },
  cooldown: { sameMetric: 600_000, crossMetric: 30_000 }, // ms
  hungerDailyLimit: 2,
};

const PHRASES: Record<string, string[]> = {
  dailyTokensLow: ["Burned quite a few tokens today~", "Eaten a lot of tokens", "Token usage rising"],
  dailyTokensMid: ["Big appetite mode!", "Great appetite today~", "Tokens going fast"],
  dailyTokensHigh: ["Token usage off the charts today 🔥", "Token burn is extreme!", "Heavy burn today"],
  sessionCountLow: ["5 agents running at once~", "Lots of agents at work", "Parallelism is up"],
  sessionCountHigh: ["Command center mode 😳", "So many sessions!", "Full throttle"],
  hungerLow: ["A little hungry…", "Hmm… want food", "Tummy rumbling"],
  hungerMid: ["Haven't been fed in a while 😢", "Hungry…", "Want food…"],
  hungerHigh: ["Where did you go… 😭", "About to faint from hunger", "So hungry"],
  streakLow: ["Days in a row! Keep going", "Going strong~", "Keeping it up"],
  streakMid: ["A whole week straight!", "Such persistence~", "So consistent"],
  streakHigh: ["Legendary streak!", "Incredible!", "Unstoppable"],
  dailyMealsLow: ["Lots of sessions today~", "Good productivity", "Got quite a bit done"],
  dailyMealsMid: ["Fifty sessions! Efficiency beast", "50+!", "Super productive"],
  dailyMealsHigh: ["Over 100! Not sleeping today?", "100+ sessions!", "Superhuman"],
};

function utcDayKey(d: Date): string {
  return `${d.getUTCFullYear()}-${d.getUTCMonth() + 1}-${d.getUTCDate()}`;
}

// Cooldown gates: 10 min per metric, 30 s across metrics, hunger max 2×/day.
const lastFiredAt: Partial<Record<Metric, number>> = {};
let lastAnyFiredAt = 0;
let lastAnyMetric: Metric | null = null;
let hungerDayKey = "";
let hungerDayCount = 0;

function checkCooldown(metric: Metric, now: number): boolean {
  const last = lastFiredAt[metric];
  if (last != null && now - last < TH.cooldown.sameMetric) return false;
  if (lastAnyMetric != null && lastAnyMetric !== metric && now - lastAnyFiredAt < TH.cooldown.crossMetric) {
    return false;
  }
  if (metric === "hunger") {
    const today = utcDayKey(new Date(now));
    if (hungerDayKey !== today) { hungerDayKey = today; hungerDayCount = 0; }
    if (hungerDayCount >= TH.hungerDailyLimit) return false;
    hungerDayCount += 1;
  }
  lastFiredAt[metric] = now;
  lastAnyFiredAt = now;
  lastAnyMetric = metric;
  return true;
}

function pool(metric: Metric, value: number | Hunger): string[] | null {
  switch (metric) {
    case "dailyTokens": {
      const v = value as number;
      if (v < TH.dailyTokens.silent) return null;
      if (v < TH.dailyTokens.low) return PHRASES.dailyTokensLow;
      if (v < TH.dailyTokens.mid) return PHRASES.dailyTokensMid;
      return PHRASES.dailyTokensHigh;
    }
    case "sessionCount": {
      const v = value as number;
      if (v < TH.sessionCount.silent) return null;
      if (v < TH.sessionCount.low) return PHRASES.sessionCountLow;
      return PHRASES.sessionCountHigh;
    }
    case "hunger": {
      switch (value as Hunger) {
        case "full": case "satisfied": return null;
        case "peckish": return PHRASES.hungerLow;
        case "hungry": return PHRASES.hungerMid;
        case "starving": return PHRASES.hungerHigh;
      }
      return null;
    }
    case "streak": {
      const v = value as number;
      if (v < TH.streak.silent) return null;
      if (v < TH.streak.low) return PHRASES.streakLow;
      if (v < TH.streak.mid) return PHRASES.streakMid;
      return PHRASES.streakHigh;
    }
    case "dailyMeals": {
      const v = value as number;
      if (v < TH.dailyMeals.silent) return null;
      if (v < TH.dailyMeals.low) return PHRASES.dailyMealsLow;
      if (v < TH.dailyMeals.mid) return PHRASES.dailyMealsMid;
      return PHRASES.dailyMealsHigh;
    }
  }
}

export function enabled(): boolean {
  return localStorage.getItem("ap_reactive") !== "0";
}

/// Returns a localized reactive line if the metric warrants one and its cooldown
/// has elapsed, else null. Mutates cooldown state when it fires.
export function evaluate(metric: Metric, value: number | Hunger, now = Date.now()): string | null {
  if (!enabled()) return null;
  const phrases = pool(metric, value);
  if (!phrases) return null;
  if (!checkCooldown(metric, now)) return null;
  const phrase = phrases[Math.floor(Math.random() * phrases.length)];
  return t(phrase);
}
