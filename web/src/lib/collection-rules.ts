// Auto ("auto-*") theme collection rules. Shared by scripts/seed-data.mjs (bulk
// seed) and the admin approval flow, so newly approved pets join the same collections.
// Theme rules: a pet joins a collection if its name contains any keyword, or its
// kind is in `kind`. Keep keywords lowercase.
export const RULES: { id: string; title: string; slug: string; desc: string; kw: string[]; kind?: string[] }[] = [
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

// Theme collections a pet belongs to, by display name keywords or kind.
export function matchRules(name: string, kind: string): string[] {
  const n = name.toLowerCase();
  const k = kind.toLowerCase();
  return RULES.filter((r) => r.kw.some((kw) => n.includes(kw)) || (r.kind || []).includes(k)).map((r) => r.id);
}
