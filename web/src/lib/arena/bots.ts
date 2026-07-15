// Ghost-team builder: when no real player snapshot exists for a turn, the
// opponent is a deterministic bot team tuned to that turn's economy. Also used
// by the balance harness to generate thousands of varied teams.

import { prng, type TeamUnit } from "./engine";
import { KINDS, UNITS, tierMax } from "./units";

const BOT_NAMES = [
  "Sparky", "Nibbles", "Mochi", "Pixel", "Biscuit", "Ziggy", "Waffles", "Turbo",
  "Noodle", "Pepper", "Clover", "Gadget", "Miso", "Bubbles", "Comet", "Tofu",
];

export function botName(seed: string): string {
  const rnd = prng(`${seed}:name`);
  return BOT_NAMES[Math.floor(rnd() * BOT_NAMES.length)];
}

/**
 * Builds a ghost team for a given turn. Teams lean into one or two kinds so
 * synergies fire (like a decent human player would), and training levels track
 * what the turn's cumulative economy allows.
 */
export function botTeam(turn: number, seed: string): TeamUnit[] {
  const rnd = prng(`${seed}:team:${turn}`);
  const maxTier = tierMax(turn);
  const size = Math.min(6, turn <= 1 ? 2 : turn <= 2 ? 3 : turn <= 4 ? 4 : turn <= 6 ? 5 : 6);

  // Pick a primary kind (synergy anchor) and a splash kind.
  const primary = KINDS[Math.floor(rnd() * KINDS.length)];
  let splash = KINDS[Math.floor(rnd() * KINDS.length)];
  if (splash === primary) splash = KINDS[(KINDS.indexOf(primary) + 1) % KINDS.length];

  const pool = UNITS.filter((u) => !u.token && u.tier <= maxTier);
  const byKind = (k: string) => pool.filter((u) => u.kind === k);

  const picks: TeamUnit[] = [];
  for (let i = 0; i < size; i++) {
    const wantPrimary = i < 2 || rnd() < 0.5;
    const options = byKind(wantPrimary ? primary : splash);
    const all = options.length ? options : pool;
    // Prefer the highest tier available as turns go on.
    const sorted = [...all].sort((a, b) => b.tier - a.tier);
    const idx = rnd() < 0.6 ? 0 : Math.floor(rnd() * sorted.length);
    picks.push({ id: sorted[Math.min(idx, sorted.length - 1)].id, level: 1 });
  }

  // Training: rough token budget after buys, spent front-to-back.
  let trainBudget = Math.max(0, (turn - 1) * 3 + Math.floor(rnd() * 4) - 2);
  for (const u of picks) {
    if (trainBudget >= 3 && u.level === 1 && rnd() < 0.7) { u.level = 2; trainBudget -= 3; }
    if (trainBudget >= 5 && u.level === 2 && turn >= 6 && rnd() < 0.4) { u.level = 3; trainBudget -= 5; }
  }

  // Tanks forward: order by hp descending-ish with a little noise.
  picks.sort((a, b) => rnd() - 0.5 > 0 ? 1 : -1);
  return picks;
}
