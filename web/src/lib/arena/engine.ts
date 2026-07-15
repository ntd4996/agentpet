// Deterministic auto-battle engine. Given two teams and a seed it produces a
// winner plus a full event log the client replays visually. Runs server-side
// (the client never simulates, so it can't cheat) and in balance scripts.

import { UNIT_BY_ID, statAt, type Kind } from "./units";

export interface TeamUnit {
  id: string;
  level: number;
  /** Permanent bonus stats earned during the run (e.g. Pup's parting gift). */
  ba?: number;
  bh?: number;
}

export interface BUnit {
  uid: number;
  id: string;
  name: string;
  kind: Kind;
  level: number;
  atk: number;
  hp: number;
  maxHp: number;
  side: 0 | 1;
  token: boolean;
  // status
  shield: number;
  dodges: number;
  armor: number;
  lifesteal: boolean;
  swiftCharges: number;
  canRevive: boolean;
}

export type Ev =
  | { t: "start"; teams: [BUnitView[], BUnitView[]] }
  | { t: "synergy"; side: 0 | 1; kind: Kind }
  | { t: "cast"; uid: number; name: string }
  | { t: "clash"; a: number; b: number }
  | { t: "hit"; uid: number; amount: number; hp: number }
  | { t: "dodge"; uid: number }
  | { t: "buff"; uid: number; atk: number; hp: number }
  | { t: "faint"; uid: number }
  | { t: "spawn"; side: 0 | 1; unit: BUnitView; front: boolean }
  | { t: "revive"; uid: number; hp: number }
  | { t: "end"; winner: 0 | 1 | -1 };

export interface BUnitView {
  uid: number; id: string; name: string; level: number; atk: number; hp: number; side: 0 | 1;
}

export interface BattleResult { winner: 0 | 1 | -1; log: Ev[] }

// Small deterministic PRNG (mulberry32) seeded from a string.
export function prng(seed: string): () => number {
  let h = 1779033703 ^ seed.length;
  for (let i = 0; i < seed.length; i++) {
    h = Math.imul(h ^ seed.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  let a = h >>> 0;
  return () => {
    a |= 0; a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function view(u: BUnit): BUnitView {
  return { uid: u.uid, id: u.id, name: u.name, level: u.level, atk: u.atk, hp: u.hp, side: u.side };
}

export function battle(teamA: TeamUnit[], teamB: TeamUnit[], seed: string): BattleResult {
  const rnd = prng(seed);
  const log: Ev[] = [];
  let nextUid = 1;

  const build = (team: TeamUnit[], side: 0 | 1): BUnit[] =>
    team
      .filter((tu) => UNIT_BY_ID[tu.id])
      .slice(0, 6)
      .map((tu) => {
        const def = UNIT_BY_ID[tu.id];
        const level = Math.max(1, Math.min(3, tu.level));
        const p = level;
        const atk = statAt(def.atk, level) + (tu.ba ?? 0);
        const hp = statAt(def.hp, level) + (tu.bh ?? 0);
        return {
          uid: nextUid++, id: def.id, name: def.name, kind: def.kind, level,
          atk, hp, maxHp: hp, side, token: !!def.token,
          shield: def.id === "shelly" ? 2 + 2 * p : 0,
          dodges: def.id === "shade" ? p : 0,
          armor: def.id === "atlas" ? p : 0,
          lifesteal: def.id === "wraith",
          swiftCharges: def.id === "zip" ? p : 0,
          canRevive: def.id === "ember",
        };
      });

  const sides: [BUnit[], BUnit[]] = [build(teamA, 0), build(teamB, 1)];
  // Spirit synergy: one-time team buff when the first ally faints.
  const spiritCharge: [boolean, boolean] = [false, false];

  const alive = (s: 0 | 1) => sides[s].filter((u) => u.hp > 0);
  const front = (s: 0 | 1) => alive(s)[0];

  const buff = (u: BUnit, atk: number, hp: number) => {
    if (u.hp <= 0) return;
    u.atk += atk; u.hp += hp; u.maxHp += hp;
    if (atk || hp) log.push({ t: "buff", uid: u.uid, atk, hp });
  };

  /** Applies damage with dodge/shield/armor. Returns actual damage dealt. */
  const damage = (target: BUnit, amount: number): number => {
    if (target.hp <= 0 || amount <= 0) return 0;
    let dmg = amount;
    if (target.dodges > 0) {
      target.dodges--;
      dmg = Math.ceil(dmg / 2);
      log.push({ t: "dodge", uid: target.uid });
    }
    if (target.armor > 0) dmg = Math.max(1, dmg - target.armor);
    if (target.shield > 0) {
      const blocked = Math.min(target.shield, dmg);
      target.shield -= blocked;
      dmg -= blocked;
    }
    if (dmg <= 0) { log.push({ t: "hit", uid: target.uid, amount: 0, hp: target.hp }); return 0; }
    target.hp -= dmg;
    log.push({ t: "hit", uid: target.uid, amount: dmg, hp: Math.max(0, target.hp) });
    return dmg;
  };

  const spawn = (s: 0 | 1, id: string, level: number, atFront: boolean, hpOverride?: number) => {
    if (alive(s).length >= 8) return; // summon cap so battles stay readable
    const def = UNIT_BY_ID[id];
    if (!def) return;
    const hp = hpOverride ?? statAt(def.hp, level);
    const u: BUnit = {
      uid: nextUid++, id: def.id, name: def.name, kind: def.kind, level,
      atk: statAt(def.atk, level), hp, maxHp: hp, side: s, token: true,
      shield: 0, dodges: 0, armor: 0, lifesteal: false, swiftCharges: 0, canRevive: false,
    };
    const arr = sides[s];
    if (atFront) {
      const idx = arr.findIndex((x) => x.hp > 0);
      arr.splice(idx < 0 ? arr.length : idx, 0, u);
    } else {
      arr.push(u);
    }
    log.push({ t: "spawn", side: s, unit: view(u), front: atFront });
  };

  /** Resolves faints (in insertion order) until stable. */
  const settle = () => {
    for (let guard = 0; guard < 64; guard++) {
      const dead = sides.flat().find((u) => u.hp <= 0 && !(u as any).__fainted);
      if (!dead) return;
      (dead as any).__fainted = true;
      const s = dead.side;
      const arr = sides[s];
      const idx = arr.indexOf(dead);

      // Ember: reignite once instead of fainting.
      if (dead.canRevive) {
        dead.canRevive = false;
        dead.hp = 2 * dead.level;
        (dead as any).__fainted = false;
        log.push({ t: "revive", uid: dead.uid, hp: dead.hp });
        continue;
      }

      log.push({ t: "faint", uid: dead.uid });

      // Own faint hooks.
      if (dead.id === "peep") {
        const behind = arr.slice(idx + 1).find((u) => u.hp > 0);
        if (behind) { log.push({ t: "cast", uid: dead.uid, name: "Last Chirp" }); buff(behind, 2 * dead.level, 0); }
      } else if (dead.id === "grub") {
        log.push({ t: "cast", uid: dead.uid, name: "Cocoon" });
        spawn(s, "cocoon", dead.level, true, 3 + 2 * dead.level);
      } else if (dead.id === "wisp") {
        log.push({ t: "cast", uid: dead.uid, name: "Passing Light" });
        for (const u of alive(s)) if (u.kind === "spirit") buff(u, dead.level, dead.level);
      }

      // Ally-faint hooks (Alpha) + Spirit synergy charge.
      for (const u of alive(s)) {
        if (u.id === "alpha") { log.push({ t: "cast", uid: u.uid, name: "Pack Fury" }); buff(u, u.level, u.level); }
      }
      if (spiritCharge[s]) {
        spiritCharge[s] = false;
        log.push({ t: "synergy", side: s, kind: "spirit" });
        for (const u of alive(s)) buff(u, 1, 1);
      }

      arr.splice(arr.indexOf(dead), 1);
    }
  };

  // ------------------------------ battle start -------------------------------
  log.push({ t: "start", teams: [sides[0].map(view), sides[1].map(view)] });

  // Kind synergies (counted on the starting lineup, tokens excluded).
  for (const s of [0, 1] as const) {
    const counts = new Map<Kind, number>();
    for (const u of sides[s]) if (!u.token) counts.set(u.kind, (counts.get(u.kind) ?? 0) + 1);
    for (const [kind, n] of counts) {
      if (n < 2) continue;
      if (kind === "spirit") { spiritCharge[s] = true; continue; } // fires later
      log.push({ t: "synergy", side: s, kind });
      if (kind === "beast") for (const u of alive(s)) buff(u, 1, 0);
      if (kind === "bird") for (const u of alive(s)) if (u.kind === "bird") buff(u, 1, 1);
      if (kind === "aqua") for (const u of alive(s)) buff(u, 0, 2);
      if (kind === "bug") spawn(s, "grub", 1, false);
      if (kind === "mech") for (const u of alive(s)) if (u.kind === "mech") u.armor += 1;
    }
  }

  // Battle-start casts, interleaved by slot for fairness (A0,B0,A1,B1,...).
  const starters: BUnit[] = [];
  const maxLen = Math.max(sides[0].length, sides[1].length);
  for (let i = 0; i < maxLen; i++) {
    for (const s of [0, 1] as const) { const u = sides[s][i]; if (u) starters.push(u); }
  }
  for (const u of starters) {
    if (u.hp <= 0) continue;
    const enemies = alive(u.side === 0 ? 1 : 0);
    if (!enemies.length) break;
    const p = u.level;
    if (u.id === "swoop") {
      log.push({ t: "cast", uid: u.uid, name: "Dive" });
      damage(enemies[enemies.length - 1], 2 + p);
    } else if (u.id === "gizmo") {
      log.push({ t: "cast", uid: u.uid, name: "Zap" });
      const strongest = enemies.reduce((a, b) => (b.atk > a.atk ? b : a));
      damage(strongest, 2 + p);
    } else if (u.id === "tide") {
      log.push({ t: "cast", uid: u.uid, name: "Soak" });
      const f = enemies[0];
      f.atk = Math.max(1, f.atk - (1 + p));
      log.push({ t: "buff", uid: f.uid, atk: -Math.min(f.atk + (1 + p) - 1, 1 + p), hp: 0 });
    } else if (u.id === "hive") {
      log.push({ t: "cast", uid: u.uid, name: "Swarm" });
      for (let k = 0; k < p; k++) spawn(u.side, "buzz", 1, true);
    }
    settle();
  }

  // -------------------------------- clashes ----------------------------------
  for (let step = 0; step < 200; step++) {
    const a = front(0);
    const b = front(1);
    if (!a || !b) break;
    log.push({ t: "clash", a: a.uid, b: b.uid });

    const aSwift = a.swiftCharges > 0;
    const bSwift = b.swiftCharges > 0;
    if (aSwift) a.swiftCharges--;
    if (bSwift) b.swiftCharges--;
    const simultaneous = aSwift === bSwift;

    if (simultaneous) {
      const dealtA = damage(b, a.atk);
      const dealtB = damage(a, b.atk);
      if (a.lifesteal && dealtA > 0) { a.hp = Math.min(a.maxHp, a.hp + Math.floor(dealtA / 2)); log.push({ t: "hit", uid: a.uid, amount: -Math.floor(dealtA / 2), hp: a.hp }); }
      if (b.lifesteal && dealtB > 0) { b.hp = Math.min(b.maxHp, b.hp + Math.floor(dealtB / 2)); log.push({ t: "hit", uid: b.uid, amount: -Math.floor(dealtB / 2), hp: b.hp }); }
      onHurt(a, dealtB); onHurt(b, dealtA);
      onKill(a, b); onKill(b, a);
    } else {
      const [first, second] = aSwift ? [a, b] : [b, a];
      const dealt1 = damage(second, first.atk);
      if (first.lifesteal && dealt1 > 0) { first.hp = Math.min(first.maxHp, first.hp + Math.floor(dealt1 / 2)); log.push({ t: "hit", uid: first.uid, amount: -Math.floor(dealt1 / 2), hp: first.hp }); }
      onHurt(second, dealt1);
      onKill(first, second);
      if (second.hp > 0) {
        const dealt2 = damage(first, second.atk);
        if (second.lifesteal && dealt2 > 0) { second.hp = Math.min(second.maxHp, second.hp + Math.floor(dealt2 / 2)); log.push({ t: "hit", uid: second.uid, amount: -Math.floor(dealt2 / 2), hp: second.hp }); }
        onHurt(first, dealt2);
        onKill(second, first);
      }
    }
    settle();
  }

  function onHurt(u: BUnit, taken: number) {
    if (taken > 0 && u.hp > 0 && u.id === "chomp") buff(u, u.level, 0);
  }
  function onKill(killer: BUnit, victim: BUnit) {
    if (victim.hp <= 0 && killer.hp > 0 && killer.id === "fang") {
      log.push({ t: "cast", uid: killer.uid, name: "Feast" });
      buff(killer, 2 * killer.level, killer.level);
    }
  }

  const aAlive = alive(0).length;
  const bAlive = alive(1).length;
  const winner: 0 | 1 | -1 = aAlive && !bAlive ? 0 : bAlive && !aAlive ? 1 : -1;
  log.push({ t: "end", winner });
  // rnd reserved for future randomized abilities; referenced so builds don't prune it.
  void rnd;
  return { winner, log };
}
