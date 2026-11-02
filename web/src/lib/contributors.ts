// Shared contributor data for /contributors and the homepage strip.

export const REPO = "ntd4996/agentpet";

export type Person = { login: string; name: string; role: string; avatar_url: string; html_url: string };

// Founders are listed first; everyone is shown with the same card.
export const FOUNDERS: Person[] = [
  { login: "ntd4996", name: "Nguyễn Thành Đạt", role: "Founder & maintainer", avatar_url: "https://avatars.githubusercontent.com/u/46896275?v=4", html_url: "https://github.com/ntd4996" },
  { login: "hoangphison", name: "Sơn Hoàng", role: "Cofounder", avatar_url: "https://avatars.githubusercontent.com/u/9270621?v=4", html_url: "https://github.com/hoangphison" },
];
export const FOUNDER_LOGINS = new Set(FOUNDERS.map((f) => f.login));

// Always-include set: merged contributors that GitHub's cached contributor
// API can lag behind by hours, so we union them in to show credit right away.
export const KNOWN = [
  { login: "3xhvy", avatar_url: "https://avatars.githubusercontent.com/u/127609002?v=4", html_url: "https://github.com/3xhvy" },
  { login: "aiexkwan", avatar_url: "https://avatars.githubusercontent.com/u/203569546?v=4", html_url: "https://github.com/aiexkwan" },
  { login: "23092003e", avatar_url: "https://avatars.githubusercontent.com/u/114332653?v=4", html_url: "https://github.com/23092003e" },
  { login: "tranhuuhuy297", avatar_url: "https://avatars.githubusercontent.com/u/46334604?v=4", html_url: "https://github.com/tranhuuhuy297" },
  { login: "heo001997", avatar_url: "https://avatars.githubusercontent.com/u/20258751?v=4", html_url: "https://github.com/heo001997" },
  { login: "minhat-dg", avatar_url: "https://avatars.githubusercontent.com/u/70907443?v=4", html_url: "https://github.com/minhat-dg" },
  { login: "hhoangg", avatar_url: "https://avatars.githubusercontent.com/u/19337273?v=4", html_url: "https://github.com/hhoangg" },
  { login: "hoangdq08", avatar_url: "https://avatars.githubusercontent.com/u/224021259?v=4", html_url: "https://github.com/hoangdq08" },
  { login: "hocdo278", avatar_url: "https://avatars.githubusercontent.com/u/236560667?v=4", html_url: "https://github.com/hocdo278" },
  { login: "htdangkhoa", avatar_url: "https://avatars.githubusercontent.com/u/15341301?v=4", html_url: "https://github.com/htdangkhoa" },
  { login: "svcrashh", avatar_url: "https://avatars.githubusercontent.com/u/76575380?v=4", html_url: "https://github.com/svcrashh" },
];

export const NAMES: Record<string, string> = { "3xhvy": "Hồ Hoàng Huy", "23092003e": "Mạnh Hoàng", "hoangdq08": "Đỗ Quốc Hoàng", "htdangkhoa": "Huỳnh Trần Đăng Khoa" };
export const ROLES: Record<string, string> = {
  "3xhvy": "Multi-agent bubble",
  "aiexkwan": "Achievements, reactive bubbles & perf",
  "23092003e": "Windows hooks",
  "hhoangg": "Per-project pets, break reminder & CPU perf",
  "hoangdq08": "jcode, usage limits, project names & stats card",
  "hocdo278": "Usage dashboard & Windows parity",
  "htdangkhoa": "Multi-device streak sync",
  "svcrashh": "Accurate token counting",
};

export function toPerson(c: { login: string; avatar_url: string; html_url: string }): Person {
  return { login: c.login, name: NAMES[c.login] || c.login, role: ROLES[c.login] || "Contributor", avatar_url: c.avatar_url, html_url: c.html_url };
}

// Founders plus the always-include list. No network call, safe for the homepage.
export function knownPeople(): Person[] {
  return [...FOUNDERS, ...KNOWN.filter((c) => !FOUNDER_LOGINS.has(c.login)).map(toPerson)];
}
