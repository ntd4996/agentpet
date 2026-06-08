// Data seed: assigns stable dex numbers (00001..N) to every pet and auto-builds
// themed collections from pet names + kinds (referencing the petdex/openpets
// catalogs we mirror). Emits idempotent SQL to scripts/seed.sql, then apply with:
//   npx wrangler d1 execute agentpet-web --remote --file=scripts/seed.sql
// Auto rows use fixed ids ("auto-*" collections) so re-running is safe and never
// touches admin-made collections. Original author info (submittedBy) is preserved.

import { writeFileSync } from "node:fs";

const MANIFEST = "https://pets.thenightwatcher.online/manifest.json";
const TS = Date.now();

// Theme rules: a pet joins a collection if its name contains any keyword, or its
// kind is in `kind`. Keep keywords lowercase.
const RULES = [
  { id: "auto-cats", title: "Cats & Kitties", slug: "cats-and-kitties", desc: "Whiskered companions, from sleepy tabbies to chaotic kittens.", kw: ["cat", "kitt", "neko", "meow", "feline", "tabby", "purr", "calico"] },
  { id: "auto-dogs", title: "Good Dogs", slug: "good-dogs", desc: "Loyal pups and very good boys for your desktop.", kw: ["dog", "puppy", "pup", "corgi", "shiba", "husky", "hound", "doggo", "retriever", "poodle", "akita"] },
  { id: "auto-dragons", title: "Dragons & Dinos", slug: "dragons-and-dinos", desc: "Scaly legends, wyrms, and pocket dinosaurs.", kw: ["dragon", "wyrm", "drake", "dino", "raptor", "rex", "lizard", "reptile", "godzilla"] },
  { id: "auto-robots", title: "Robots & AI", slug: "robots-and-ai", desc: "Mechs, droids, and digital helpers.", kw: ["robot", "mech", "droid", "android", "cyborg", "machine", "automa", "-bot", "bot ", "ai "] },
  { id: "auto-food", title: "Foodies", slug: "foodies", desc: "Snacks, drinks, and delicious little friends.", kw: ["boba", "tea", "coffee", "cake", "sushi", "pizza", "burger", "donut", "bread", "food", "snack", "fruit", "taco", "ramen", "egg", "milk", "candy", "cookie", "noodle", "soup", "banana", "apple", "peach", "berry"] },
  { id: "auto-birds", title: "Birds of a Feather", slug: "birds-of-a-feather", desc: "Feathered friends of every size.", kw: ["bird", "duck", "chick", "owl", "penguin", "parrot", "crow", "eagle", "hen", "goose", "chicken", "pigeon", "sparrow", "robin", "finch", "conure"] },
  { id: "auto-ocean", title: "Ocean Friends", slug: "ocean-friends", desc: "Aquatic pals from the deep blue.", kw: ["fish", "octopus", "shark", "whale", "crab", "otter", "seal", "jelly", "turtle", "axolotl", "squid", "dolphin", "koi", "shrimp", "starfish", "puffer"] },
  { id: "auto-mythic", title: "Mythical & Spirits", slug: "mythical-and-spirits", desc: "Ghosts, fairies, and otherworldly beings.", kw: ["ghost", "spirit", "fairy", "slime", "demon", "angel", "witch", "wizard", "mage", "phantom", "kitsune", "yokai", "spectre", "goblin", "elf", "unicorn"] },
  { id: "auto-critters", title: "Cute Critters", slug: "cute-critters", desc: "Tiny mammals and pocket-sized buddies.", kw: ["bunny", "rabbit", "hamster", "mouse", "rat", "hedgehog", "fox", "panda", "bear", "squirrel", "raccoon", "sloth", "koala", "frog", "snail", "deer"] },
  { id: "auto-bugs", title: "Bugs & Beasties", slug: "bugs-and-beasties", desc: "Creepy-crawly companions.", kw: ["bug", "bee", "ant", "spider", "beetle", "butterfly", "moth", "ladybug", "caterpillar", "worm"] },
  { id: "auto-plants", title: "Plants & Nature", slug: "plants-and-nature", desc: "Leafy, blooming, growing things.", kw: ["plant", "flower", "tree", "cactus", "leaf", "sprout", "seed", "garden", "mushroom", "bloom", "fungus", "moss"] },
  { id: "auto-foxwolf", title: "Foxes & Wolves", slug: "foxes-and-wolves", desc: "Sly foxes and howling wolves.", kw: ["fox", "wolf", "vulpix", "kitsune"] },
  { id: "auto-bears", title: "Bears & Pandas", slug: "bears-and-pandas", desc: "Cuddly bears and bamboo-munching pandas.", kw: ["bear", "panda", "teddy", "polar"] },
  { id: "auto-space", title: "Space & Aliens", slug: "space-and-aliens", desc: "Cosmic visitors from far away.", kw: ["alien", "space", "ufo", "astronaut", "rocket", "cosmic", "galaxy", "moon", "planet", "star", "meteor", "comet", "nebula"] },
  { id: "auto-royal", title: "Royals & Heroes", slug: "royals-and-heroes", desc: "Knights, royalty, and brave warriors.", kw: ["king", "queen", "prince", "princess", "knight", "hero", "warrior", "samurai", "ninja", "paladin", "guard", "lord"] },
  { id: "auto-music", title: "Music & Party", slug: "music-and-party", desc: "Beats, bops, and a good time.", kw: ["music", "dj", "guitar", "drum", "party", "disco", "band", "song", "piano", "violin"] },
  { id: "auto-spooky", title: "Spooky Squad", slug: "spooky-squad", desc: "Ghouls, bones, and things that go bump.", kw: ["pumpkin", "skull", "bat", "zombie", "vampire", "mummy", "skeleton", "grim", "spooky", "halloween", "reaper", "spooky"] },
  { id: "auto-festive", title: "Festive Friends", slug: "festive-friends", desc: "Holiday cheer in pixel form.", kw: ["santa", "snowman", "christmas", "gift", "reindeer", "holiday", "festive", "snow", "elf"] },
  { id: "auto-gaming", title: "Gaming & Retro", slug: "gaming-and-retro", desc: "Arcade vibes and retro souls.", kw: ["controller", "gamer", "arcade", "retro", "console", "joystick", "gameboy", "8bit", "pixel"] },
  { id: "auto-magic", title: "Magic & Potions", slug: "magic-and-potions", desc: "Spellcasters and arcane trinkets.", kw: ["magic", "potion", "crystal", "spell", "sorcerer", "alchemy", "rune", "enchant", "staff"] },
  { id: "auto-slime", title: "Slimes & Blobs", slug: "slimes-and-blobs", desc: "Squishy, jiggly little blobs.", kw: ["slime", "blob", "goo", "gel"] },
  { id: "auto-monster", title: "Monsters", slug: "monsters", desc: "Beasts, ogres, and friendly fiends.", kw: ["monster", "beast", "ogre", "troll", "kraken", "behemoth", "fiend", "yeti"] },
  { id: "auto-anime", title: "Anime & Manga", slug: "anime-and-manga", desc: "Icons and heroes from anime and manga.", kw: ["anime", "manga", "naruto", "sasuke", "goku", "saiyan", "dragon ball", "luffy", "zoro", "sailor moon", "gojo", "tanjiro", "nezuko", "eren", "mikasa", "waifu", "senpai", "jojo", "ichigo", "deku", "chainsaw man", "makima"] },
  { id: "auto-pokemon", title: "Pokemon Pals", slug: "pokemon-pals", desc: "Pocket monsters and their friends.", kw: ["pokemon", "pikachu", "charizard", "bulbasaur", "eevee", "snorlax", "gengar", "mewtwo", "squirtle", "jigglypuff", "psyduck", "charmander", "ditto", "pichu"] },
  { id: "auto-lol", title: "League of Legends", slug: "league-of-legends", desc: "Champions straight from the Rift.", kw: ["league of legends", "jinx", "yasuo", "ahri", "teemo", "lux", "garen", "zed", "akali", "ezreal", "katarina", "lee sin", "poro", "darius", "yuumi"] },
  { id: "auto-games", title: "Gaming Icons", slug: "gaming-icons", desc: "Faces from the games we love.", kw: ["minecraft", "creeper", "mario", "luigi", "zelda", "sonic", "kirby", "among us", "fortnite", "valorant", "genshin", "elden", "stardew", "roblox", "pacman", "pac-man", "tetris", "fall guys", "undertale", "cuphead", "doomguy"] },
  { id: "auto-ghibli", title: "Studio Ghibli", slug: "studio-ghibli", desc: "Cozy spirits from Ghibli films.", kw: ["ghibli", "totoro", "no-face", "kaonashi", "kiki", "howl", "ponyo", "calcifer", "soot sprite"] },
  { id: "auto-objects", title: "Curious Objects", slug: "curious-objects", desc: "Everyday things brought to pixel life.", kw: [], kind: ["object"] },
  { id: "auto-asian", title: "Eastern Art Style", slug: "eastern-style", desc: "Companions drawn in an Eastern art style.", kw: [], kind: ["asian"] },
  { id: "auto-western", title: "Western Art Style", slug: "western-style", desc: "Companions drawn in a Western art style.", kw: [], kind: ["western"] },
];

const esc = (s) => String(s).replace(/'/g, "''");
const chunk = (arr, n) => { const out = []; for (let i = 0; i < arr.length; i += n) out.push(arr.slice(i, i + n)); return out; };

const res = await fetch(MANIFEST);
const data = await res.json();
const pets = data.pets || [];
console.error(`fetched ${pets.length} pets`);

// 1) numbering: stable order by displayName then slug
const ordered = [...pets].sort((a, b) => (a.displayName || a.slug).localeCompare(b.displayName || b.slug) || a.slug.localeCompare(b.slug));
const numRows = ordered.map((p, i) => `('${esc(p.slug)}',${i + 1})`);

// 2) collections membership
const members = {}; // id -> [slug]
for (const r of RULES) members[r.id] = [];
for (const p of pets) {
  const name = (p.displayName || p.slug).toLowerCase();
  const kind = (p.kind || "").toLowerCase();
  for (const r of RULES) {
    const hitKw = r.kw.some((k) => name.includes(k));
    const hitKind = (r.kind || []).includes(kind);
    if (hitKw || hitKind) members[r.id].push(p.slug);
  }
}

let sql = "";
sql += "CREATE TABLE IF NOT EXISTS pet_numbers (slug TEXT PRIMARY KEY, num INTEGER NOT NULL);\n";
sql += "CREATE TABLE IF NOT EXISTS collections (id TEXT PRIMARY KEY, title TEXT NOT NULL, slug TEXT NOT NULL UNIQUE, description TEXT, created_at INTEGER NOT NULL);\n";
sql += "CREATE TABLE IF NOT EXISTS collection_pets (collection_id TEXT NOT NULL, slug TEXT NOT NULL, added_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (collection_id, slug));\n";
sql += "DELETE FROM pet_numbers;\n";
for (const c of chunk(numRows, 400)) sql += `INSERT INTO pet_numbers (slug, num) VALUES ${c.join(",")};\n`;

// upsert auto collections (fixed ids; safe re-run), then reset their members
sql += "DELETE FROM collection_pets WHERE collection_id LIKE 'auto-%' AND collection_id NOT LIKE 'auto-color-%';\n";
for (const r of RULES) {
  sql += `INSERT INTO collections (id, title, slug, description, created_at) VALUES ('${r.id}','${esc(r.title)}','${esc(r.slug)}','${esc(r.desc)}',${TS}) ON CONFLICT(id) DO UPDATE SET title=excluded.title, slug=excluded.slug, description=excluded.description;\n`;
}
let total = 0;
for (const r of RULES) {
  const rows = members[r.id].map((s) => `('${r.id}','${esc(s)}',${TS})`);
  total += rows.length;
  for (const c of chunk(rows, 400)) sql += `INSERT OR IGNORE INTO collection_pets (collection_id, slug, added_at) VALUES ${c.join(",")};\n`;
  console.error(`${r.id}: ${members[r.id].length}`);
}

writeFileSync(new URL("./seed.sql", import.meta.url), sql);
console.error(`\nwrote seed.sql | ${numRows.length} numbers, ${RULES.length} collections, ${total} memberships`);
