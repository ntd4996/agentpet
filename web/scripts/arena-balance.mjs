// Balance harness: thousands of seeded bot-vs-bot battles, reporting per-unit
// win contribution. Usage:
//   npx esbuild src/lib/arena/harness-entry.ts --bundle --format=esm --outfile=/tmp/arena-harness.mjs
//   node scripts/arena-balance.mjs
import { battle, botTeam } from "/tmp/arena-harness.mjs";

const N = Number(process.env.N || 4000);
const stats = new Map(); // unit id -> { present: number, wins: number }
const turnBuckets = [2, 4, 6, 8, 10];
let draws = 0;

function bump(team, won) {
  for (const u of team) {
    const s = stats.get(u.id) ?? { present: 0, wins: 0 };
    s.present += 1;
    if (won) s.wins += 1;
    stats.set(u.id, s);
  }
}

let totalEvents = 0;
for (let i = 0; i < N; i++) {
  const turn = turnBuckets[i % turnBuckets.length];
  const a = botTeam(turn, `bal:a:${i}`);
  const b = botTeam(turn, `bal:b:${i}`);
  const r = battle(a, b, `bal:seed:${i}`);
  totalEvents += r.log.length;
  if (r.winner === -1) { draws++; bump(a, false); bump(b, false); continue; }
  bump(a, r.winner === 0);
  bump(b, r.winner === 1);
}

const rows = [...stats.entries()]
  .map(([id, s]) => ({ id, present: s.present, wr: (100 * s.wins) / s.present }))
  .sort((x, y) => y.wr - x.wr);

console.log(`battles=${N} draws=${draws} (${((100 * draws) / N).toFixed(1)}%) avgLog=${Math.round(totalEvents / N)}`);
for (const r of rows) console.log(`${r.id.padEnd(8)} wr=${r.wr.toFixed(1)}%  n=${r.present}`);
