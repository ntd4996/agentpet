# AgentPet Arena , design notes

A fair, skill-based async auto-battler inside the AgentPet universe. Everyone
starts every run equal; pet-raising level (real coding) unlocks only titles and
extra daily runs, never in-battle power. Care data flows one way: care → arena.

## How it diverges from other auto-battlers

- **6 team slots** in a single line (front fights first).
- **No merge-to-level.** Units are TRAINED by paying tokens (L2 = 3, L3 = 5),
  mirroring how AgentPet pets eat tokens to grow. No duplicate-hunting.
- **Kind synergies** (6 kinds, wake at 2+ of a kind) add a composition axis.
- **Carry-over economy**: up to 3 unspent tokens carry to the next round.
- **Battery/crowns**: 5 🔋 lives, 7 👑 wins to take the crown, 14-round cap.
- Own theme, names, procedural pixel art; currency is tokens (AgentPet lore).

## Roster (18 units, 6 kinds x 3 tiers + 2 battle tokens)

See `web/src/lib/arena/units.ts` (stats/abilities) and `engine.ts` (hooks:
battleStart, clash, onHurt, onFaint, onAllyFaint, onKill, revive, spawn;
statuses: shield, phase/dodge, armor, lifesteal, swift charges).

## Economy

Income 10/round (+carry ≤3), buy 3, reroll 1, sell 1 (Bloop 3, Pup gifts stats),
shop 3→5 slots, tiers gate at rounds 1/3/5.

## Server model

- Server-authoritative: the client only sends intents (`/api/arena/action`),
  all math and the battle sim run in the Worker. Deterministic seeded engine.
- Async ghosts: each end-turn stores the lineup in `arena_snapshots`; opponents
  are ghosts at the same round with the closest wins, else a deterministic bot
  (`bots.ts`) so there is never a cold-start gap. Pool pruned to 300/turn.
- Tables: `arena_runs`, `arena_snapshots`, `arena_stats` (crowns/runs/best).
- Auth: web session cookie OR care device token (Bearer), so desktop apps can
  play through the same identity.
- Daily runs: 5 + care-level perk (max +3 at Lv 30).

## Balance (bot-vs-bot, 4000 seeded battles)

Combat units land in a 41–58% win band; economy/fodder units (Pup, Bloop, Grub)
sit lower by design , the harness can't price sell-value. Rebalance by editing
`units.ts` numbers and re-running `scripts/arena-balance.mjs` (esbuild bundle →
node). The engine is deterministic, so past replays never break.

## Art

`scripts/gen-arena-art.mjs` procedurally draws each critter (mirrored pixel
blob + kind features: ears/wings/fins/antennae/ghost-hem/antenna) into
`public/arena/*.png` (192px, crisp). Tweak a unit's look by bumping its seed.

## Future (not in v1)

Skins from raised pets (cosmetic), achievements-as-relics, weekly seasons with
leaderboard resets, shared replay links, spectate, Windows app integration.
