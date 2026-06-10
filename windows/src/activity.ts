// Whimsical per-state phrases, ported from the macOS app's activity themes.
// Picked when the user hasn't set a custom message and the hook gave no live
// text. The theme is chosen in Settings (or "off" to just show state labels).
// Phrases are intentionally English (a playful flourish), like the macOS app.

type Phrases = { working: string[]; waiting: string[]; done: string[]; idle: string[] };

export const THEMES: Record<string, Phrases> = {
  chef: {
    working: ["Cooking…", "Simmering…", "Plating up…", "Seasoning to taste…"],
    waiting: ["Awaiting instructions…", "Chef needs a hand…", "Taste test?"],
    done: ["Bon appétit!", "Order up!", "Served hot!", "Dinner is ready!"],
    idle: ["Kitchen's quiet…", "Sharpening the knives.", "What's on the menu?"],
  },
  wizard: {
    working: ["Casting…", "Brewing a spell…", "Consulting the tomes…", "Channeling mana…"],
    waiting: ["Awaiting the omens…", "The stars must align…", "Patience, apprentice…"],
    done: ["The spell is cast!", "It is done!", "Magic complete!", "Quest fulfilled!"],
    idle: ["The orb is dim…", "Studying runes.", "A nap in the tower."],
  },
  scientist: {
    working: ["Computing…", "Running the experiment…", "Crunching numbers…", "Calibrating…"],
    waiting: ["Awaiting results…", "Incubating…", "Need a sample…"],
    done: ["Eureka!", "Hypothesis confirmed!", "Experiment complete!", "Results are in!"],
    idle: ["Lab is quiet.", "Reviewing notes.", "Waiting for inspiration."],
  },
  explorer: {
    working: ["Exploring…", "Charting the map…", "Trekking onward…", "Scouting ahead…"],
    waiting: ["Resting at camp…", "Awaiting the tide…", "Which way now?"],
    done: ["Summit reached!", "Treasure found!", "We made it!", "Journey complete!"],
    idle: ["Camp is set.", "Reading the stars.", "Where to next?"],
  },
};

export function themePhrase(theme: string, state: string, seed: string): string | null {
  const t = THEMES[theme];
  if (!t) return null;
  const pool = (t as any)[state] as string[] | undefined;
  if (!pool || !pool.length) return null;
  let h = 5381;
  for (const c of seed) h = (Math.imul(h, 33) + c.charCodeAt(0)) | 0;
  return pool[Math.abs(h) % pool.length];
}
