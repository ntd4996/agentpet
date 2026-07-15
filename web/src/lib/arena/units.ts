// Arena roster: 18 units across 6 kinds x 3 tiers, plus battle-summoned tokens.
// Design intentionally diverges from other auto-battlers: 6 team slots, no
// merge-to-level (you TRAIN units by feeding tokens, like the app's pets eat
// tokens), kind synergies at 2+ of a kind, and a carry-over economy.

export type Kind = "beast" | "bird" | "aqua" | "bug" | "spirit" | "mech";

export interface UnitDef {
  id: string;
  name: string;
  kind: Kind;
  tier: 1 | 2 | 3;
  atk: number;
  hp: number;
  /** Battle-summoned unit, never appears in the shop. */
  token?: boolean;
  /** Short ability text shown in the UI ({p} = ability power = level). */
  ability: string;
}

export const KINDS: Kind[] = ["beast", "bird", "aqua", "bug", "spirit", "mech"];

export const KIND_META: Record<Kind, { name: string; color: string; synergy: string }> = {
  beast:  { name: "Beast",  color: "#e8863a", synergy: "2+ Beasts: your whole team gets +1 attack." },
  bird:   { name: "Bird",   color: "#58b7e8", synergy: "2+ Birds: every Bird gets +1/+1." },
  aqua:   { name: "Aqua",   color: "#3f7de0", synergy: "2+ Aqua: your whole team gets +2 health." },
  bug:    { name: "Bug",    color: "#7bb662", synergy: "2+ Bugs: a wild Grub joins the back of your team." },
  spirit: { name: "Spirit", color: "#a06de0", synergy: "2+ Spirits: first time an ally faints, the team gets +1/+1." },
  mech:   { name: "Mech",   color: "#8a94a6", synergy: "2+ Mechs: every Mech gets +1 armor." },
};

export const UNITS: UnitDef[] = [
  // ------------------------------- Tier 1 -----------------------------------
  { id: "pup",   name: "Pup",   kind: "beast",  tier: 1, atk: 3, hp: 2,
    ability: "Sold: the ally in front of it gains +{p}/+{p} for the run." },
  { id: "peep",  name: "Peep",  kind: "bird",   tier: 1, atk: 1, hp: 3,
    ability: "Faint: the ally behind gains +{2p} attack." },
  { id: "bloop", name: "Bloop", kind: "aqua",   tier: 1, atk: 1, hp: 3,
    ability: "Sells for 3 tokens (full refund)." },
  { id: "grub",  name: "Grub",  kind: "bug",    tier: 1, atk: 2, hp: 1,
    ability: "Faint: leaves a Cocoon with {3+2p} health." },
  { id: "wisp",  name: "Wisp",  kind: "spirit", tier: 1, atk: 2, hp: 1,
    ability: "Faint: every Spirit ally gains +{p}/+{p}." },
  { id: "zip",   name: "Zip",   kind: "mech",   tier: 1, atk: 3, hp: 1,
    ability: "Swift: strikes first in its first {p} clash(es)." },
  // ------------------------------- Tier 2 -----------------------------------
  { id: "fang",  name: "Fang",  kind: "beast",  tier: 2, atk: 5, hp: 4,
    ability: "Kill: gains +{2p} attack and +{p} health." },
  { id: "swoop", name: "Swoop", kind: "bird",   tier: 2, atk: 4, hp: 3,
    ability: "Battle start: dives the last enemy for {2+p} damage." },
  { id: "shelly", name: "Shelly", kind: "aqua", tier: 2, atk: 2, hp: 6,
    ability: "Shell: blocks the first {2+2p} damage taken." },
  { id: "chomp", name: "Chomp", kind: "bug",    tier: 2, atk: 3, hp: 6,
    ability: "Hurt: gains +{p} attack." },
  { id: "shade", name: "Shade", kind: "spirit", tier: 2, atk: 3, hp: 3,
    ability: "Phase: the first {p} hit(s) against it deal half damage." },
  { id: "gizmo", name: "Gizmo", kind: "mech",   tier: 2, atk: 3, hp: 3,
    ability: "Battle start: zaps the strongest enemy for {2+p} damage." },
  // ------------------------------- Tier 3 -----------------------------------
  { id: "alpha", name: "Alpha", kind: "beast",  tier: 3, atk: 5, hp: 5,
    ability: "Ally faints: gains +{p}/+{p}." },
  { id: "ember", name: "Ember", kind: "bird",   tier: 3, atk: 5, hp: 4,
    ability: "First faint: reignites with {2p} health." },
  { id: "tide",  name: "Tide",  kind: "aqua",   tier: 3, atk: 5, hp: 8,
    ability: "Battle start: soaks the front enemy, -{1+p} attack." },
  { id: "hive",  name: "Hive",  kind: "bug",    tier: 3, atk: 5, hp: 7,
    ability: "Battle start: {p} Buzz(es) rush to the front." },
  { id: "wraith", name: "Wraith", kind: "spirit", tier: 3, atk: 6, hp: 3,
    ability: "Drain: heals for half the damage it deals." },
  { id: "atlas", name: "Atlas", kind: "mech",   tier: 3, atk: 5, hp: 7,
    ability: "Plating: every hit taken is reduced by {p}." },
  // ------------------------------- Tokens ------------------------------------
  { id: "buzz",   name: "Buzz",   kind: "bug", tier: 1, atk: 3, hp: 3, token: true,
    ability: "A loyal worker summoned by Hive." },
  { id: "cocoon", name: "Cocoon", kind: "bug", tier: 1, atk: 0, hp: 3, token: true,
    ability: "Just a cocoon. Soaks hits." },
];

export const UNIT_BY_ID: Record<string, UnitDef> = Object.fromEntries(UNITS.map((u) => [u.id, u]));

/** Stat at a training level: base + ceil(base/2) per extra level (L1..L3). */
export function statAt(base: number, level: number): number {
  return base + Math.ceil(base / 2) * (Math.max(1, Math.min(3, level)) - 1);
}

/** Fills {p}-style placeholders in ability text for a given level. */
export function abilityText(def: UnitDef, level: number): string {
  const p = Math.max(1, Math.min(3, level));
  return def.ability
    .replace(/\{2\+2p\}/g, String(2 + 2 * p))
    .replace(/\{3\+2p\}/g, String(3 + 2 * p))
    .replace(/\{3\+p\}/g, String(3 + p))
    .replace(/\{2\+p\}/g, String(2 + p))
    .replace(/\{1\+p\}/g, String(1 + p))
    .replace(/\{2p\}/g, String(2 * p))
    .replace(/\{p\}/g, String(p));
}

// ------------------------------ economy rules --------------------------------

export const RULES = {
  teamSlots: 6,
  income: 10,
  carryCap: 3,          // unspent tokens carried into the next turn, capped
  buyCost: 3,
  rerollCost: 1,
  sellRefund: 1,
  trainCost: [0, 3, 5], // cost to reach level 2, level 3
  startPins: 5,
  crownsToWin: 7,
  maxTurns: 14,         // hard stop: a run can't idle forever
  baseRunsPerDay: 5,
};

export function shopSize(turn: number): number {
  return turn <= 2 ? 3 : turn <= 4 ? 4 : 5;
}
export function tierMax(turn: number): 1 | 2 | 3 {
  return turn <= 2 ? 1 : turn <= 4 ? 2 : 3;
}
/** Weighted tier pick for one shop slot. r in [0,1). */
export function rollTier(turn: number, r: number): 1 | 2 | 3 {
  const max = tierMax(turn);
  if (max === 1) return 1;
  if (max === 2) return r < 0.55 ? 1 : 2;
  return r < 0.3 ? 1 : r < 0.65 ? 2 : 3;
}

export function shopPool(tier: 1 | 2 | 3): UnitDef[] {
  return UNITS.filter((u) => !u.token && u.tier === tier);
}

/** Extra daily runs from the player's best care level (cosmetic-adjacent perk). */
export function runsPerDay(careLevel: number): number {
  return RULES.baseRunsPerDay + Math.min(3, Math.floor(careLevel / 10));
}

/** Title shown next to the player, unlocked by real pet-raising level. */
export function careTitle(careLevel: number): string {
  if (careLevel >= 35) return "Legend Trainer";
  if (careLevel >= 20) return "Hero Trainer";
  if (careLevel >= 10) return "Veteran Trainer";
  if (careLevel >= 5) return "Trainer";
  return "Rookie";
}
