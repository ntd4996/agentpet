// Server-authoritative shop/run state machine. Every mutation happens here so
// the client can never fake tokens, units or levels. Shop rolls derive from the
// run seed + turn + reroll count, so a given roll is reproducible.

import { prng, type TeamUnit } from "./engine";
import { RULES, UNIT_BY_ID, rollTier, shopPool, shopSize } from "./units";

export interface RunState {
  turn: number;
  tokens: number;
  pins: number;
  wins: number;
  team: TeamUnit[];      // index 0 = front
  shop: (string | null)[]; // unit ids; null = bought this turn
  rerolls: number;
  seed: string;
  status: "active" | "won" | "lost";
}

export function newRun(seed: string): RunState {
  const run: RunState = {
    turn: 1, tokens: RULES.income, pins: RULES.startPins, wins: 0,
    team: [], shop: [], rerolls: 0, seed, status: "active",
  };
  run.shop = rollShop(run);
  return run;
}

export function rollShop(run: RunState): (string | null)[] {
  const rnd = prng(`${run.seed}:shop:${run.turn}:${run.rerolls}`);
  const out: string[] = [];
  for (let i = 0; i < shopSize(run.turn); i++) {
    const tier = rollTier(run.turn, rnd());
    const pool = shopPool(tier);
    out.push(pool[Math.floor(rnd() * pool.length)].id);
  }
  return out;
}

export type ShopAction =
  | { a: "buy"; shopIdx: number; slot: number }
  | { a: "sell"; slot: number }
  | { a: "train"; slot: number }
  | { a: "reroll" }
  | { a: "move"; from: number; to: number };

/** Applies one shop action in place. Returns an error string or null. */
export function apply(run: RunState, act: ShopAction): string | null {
  if (run.status !== "active") return "run is over";
  switch (act.a) {
    case "buy": {
      const id = run.shop[act.shopIdx];
      if (!id) return "that slot is empty";
      if (run.tokens < RULES.buyCost) return "not enough tokens";
      if (act.slot < 0 || act.slot >= RULES.teamSlots) return "bad slot";
      if (run.team.length >= RULES.teamSlots && !run.team[act.slot]) return "team is full";
      if (run.team[act.slot]) return "slot taken";
      run.tokens -= RULES.buyCost;
      run.shop[act.shopIdx] = null;
      // team is a sparse-by-slot array; keep it dense with explicit slots
      run.team[act.slot] = { id, level: 1 };
      run.team = run.team.filter(Boolean);
      return null;
    }
    case "sell": {
      const u = run.team[act.slot];
      if (!u) return "no unit there";
      const refund = u.id === "bloop" ? 3 : RULES.sellRefund;
      run.team.splice(act.slot, 1);
      run.tokens += refund;
      // Pup: parting gift — the ally that was in front of it gains a permanent
      // +level/+level for the rest of the run.
      if (u.id === "pup" && run.team.length) {
        const target = run.team[Math.max(0, act.slot - 1)] ?? run.team[run.team.length - 1];
        target.ba = (target.ba ?? 0) + u.level;
        target.bh = (target.bh ?? 0) + u.level;
      }
      return null;
    }
    case "train": {
      const u = run.team[act.slot];
      if (!u) return "no unit there";
      if (u.level >= 3) return "already max level";
      const cost = RULES.trainCost[u.level];
      if (run.tokens < cost) return "not enough tokens";
      run.tokens -= cost;
      u.level += 1;
      return null;
    }
    case "reroll": {
      if (run.tokens < RULES.rerollCost) return "not enough tokens";
      run.tokens -= RULES.rerollCost;
      run.rerolls += 1;
      run.shop = rollShop(run);
      return null;
    }
    case "move": {
      const { from, to } = act;
      if (from < 0 || from >= run.team.length || to < 0 || to >= run.team.length) return "bad move";
      const [u] = run.team.splice(from, 1);
      run.team.splice(to, 0, u);
      return null;
    }
  }
}

/** Advances to the next turn after a battle: income + fresh shop. */
export function nextTurn(run: RunState) {
  run.turn += 1;
  run.tokens = Math.min(run.tokens, RULES.carryCap) + RULES.income;
  run.rerolls = 0;
  run.shop = rollShop(run);
}

export function sanitizeTeam(team: unknown): TeamUnit[] {
  if (!Array.isArray(team)) return [];
  return team
    .filter((u: any) => u && typeof u.id === "string" && UNIT_BY_ID[u.id] && !UNIT_BY_ID[u.id].token)
    .slice(0, RULES.teamSlots)
    .map((u: any) => ({
      id: u.id,
      level: Math.max(1, Math.min(3, Number(u.level) || 1)),
      ba: Math.max(0, Math.min(30, Number(u.ba) || 0)),
      bh: Math.max(0, Math.min(30, Number(u.bh) || 0)),
    }));
}
