// Builds the combined Tauri updater manifest served at
// https://agentpet.thenightwatcher.online/latest.json , covering BOTH the
// Windows and Linux (AppImage) desktop builds. Decoupled from GitHub's "Latest"
// release tag (which belongs to the native macOS app), so auto-update is stable.
//
// Run AFTER both `win-v<VER>` and `linux-v<VER>` releases exist (their signed
// updater artifacts are attached), then deploy web/ to publish it:
//   node scripts/make-latest-json.mjs 0.1.5
//
// It fetches each platform's `.sig` from its release and writes
// web/public/latest.json. Requires network + Node 18+ (global fetch).
import { writeFileSync } from "fs";

const version = process.argv[2];
if (!version) {
  console.error("usage: node scripts/make-latest-json.mjs <version>   e.g. 0.1.5");
  process.exit(1);
}

const REPO = "https://github.com/ntd4996/agentpet/releases/download";
const winTag = `win-v${version}`;
const linuxTag = `linux-v${version}`;

// Tauri's Windows updater ships the NSIS .exe; its Linux updater ships the
// AppImage itself (both with a sibling .sig).
const winExe = `AgentPet_${version}_x64-setup.exe`;
const linuxAppImage = `AgentPet_${version}_amd64.AppImage`;

async function sig(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch ${url} , ${res.status}`);
  return (await res.text()).trim();
}

const [winSig, linuxSig] = await Promise.all([
  sig(`${REPO}/${winTag}/${winExe}.sig`),
  sig(`${REPO}/${linuxTag}/${linuxAppImage}.sig`),
]);

const latest = {
  version,
  notes: "See the GitHub release notes for what's new.",
  pub_date: new Date().toISOString(),
  platforms: {
    "windows-x86_64": { signature: winSig, url: `${REPO}/${winTag}/${encodeURIComponent(winExe)}` },
    "linux-x86_64": { signature: linuxSig, url: `${REPO}/${linuxTag}/${encodeURIComponent(linuxAppImage)}` },
  },
};

writeFileSync("web/public/latest.json", JSON.stringify(latest, null, 2) + "\n");
console.log("wrote web/public/latest.json", { version, win: winTag, linux: linuxTag });
