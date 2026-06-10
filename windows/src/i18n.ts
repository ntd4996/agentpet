// Client-side i18n , same approach as the web app. Strings are keyed by their
// English text; `t()` returns the key itself for English. Auto-detects from the
// system language, remembers the choice, and exposes the current language.
// "AgentPet" + agent brand names are never translated.

export type Lang = "en" | "vi" | "zh";

const DICT: Record<Exclude<Lang, "en">, Record<string, string>> = {
  vi: {
    "Your pet": "Pet của bạn",
    "Pick the companion that floats on your desktop.": "Chọn người bạn nổi trên màn hình của bạn.",
    "Search pets by name...": "Tìm pet theo tên...",
    "Showing:": "Đang hiện:",
    "(default)": "(mặc định)",
    "Agent integrations": "Tích hợp agent",
    "Install a hook so AgentPet can see when an agent works, finishes, or needs you.":
      "Cài hook để AgentPet biết khi agent đang làm, xong, hoặc cần bạn.",
    "Install": "Cài",
    "Remove": "Gỡ",
    "Hook installed": "Đã cài hook",
    "After enabling, run /hooks in Codex and Trust the AgentPet hook":
      "Sau khi bật, chạy /hooks trong Codex và Trust hook AgentPet",
    "Copilot CLI only (~/.copilot/hooks)": "Chỉ Copilot CLI (~/.copilot/hooks)",
    "No \"needs input\" alerts (Windsurf has no such hook)":
      "Không có cảnh báo \"cần nhập\" (Windsurf không có hook đó)",
    "No \"needs input\" alerts (Antigravity has no notification hook)":
      "Không có cảnh báo \"cần nhập\" (Antigravity không có hook thông báo)",
    "Hooks the default Kiro CLI agent": "Gắn vào agent mặc định của Kiro CLI",
    "Startup": "Khởi động",
    "Start AgentPet when Windows starts": "Chạy AgentPet khi khởi động Windows",
    "Couldn't load pets , check your internet connection.":
      "Không tải được pet , kiểm tra kết nối mạng.",
    "Language": "Ngôn ngữ",
    "Working": "Đang làm",
    "Needs you": "Cần bạn",
    "Done": "Xong",
    "Ready": "Sẵn sàng",
    "Idle": "Rảnh",
    "Let's grill some bugs.": "Đi săn bug nào.",
    "Tiny commit, tiny dopamine.": "Commit nhỏ, dopamine nhỏ.",
    "The build is quiet. Too quiet.": "Build im ắng quá.",
    "Ship something small.": "Ship cái gì nhỏ nhỏ đi.",
  },
  zh: {
    "Your pet": "你的宠物",
    "Pick the companion that floats on your desktop.": "选择漂浮在你桌面上的伙伴。",
    "Search pets by name...": "按名称搜索宠物...",
    "Showing:": "正在显示：",
    "(default)": "（默认）",
    "Agent integrations": "Agent 集成",
    "Install a hook so AgentPet can see when an agent works, finishes, or needs you.":
      "安装 hook，让 AgentPet 知道 agent 何时在工作、完成或需要你。",
    "Install": "安装",
    "Remove": "移除",
    "Hook installed": "已安装 hook",
    "After enabling, run /hooks in Codex and Trust the AgentPet hook":
      "启用后，在 Codex 中运行 /hooks 并信任 AgentPet hook",
    "Copilot CLI only (~/.copilot/hooks)": "仅限 Copilot CLI (~/.copilot/hooks)",
    "No \"needs input\" alerts (Windsurf has no such hook)":
      "没有\"需要输入\"提醒（Windsurf 没有该 hook）",
    "No \"needs input\" alerts (Antigravity has no notification hook)":
      "没有\"需要输入\"提醒（Antigravity 没有通知 hook）",
    "Hooks the default Kiro CLI agent": "挂接 Kiro CLI 的默认 agent",
    "Startup": "启动",
    "Start AgentPet when Windows starts": "Windows 启动时运行 AgentPet",
    "Couldn't load pets , check your internet connection.": "无法加载宠物 , 请检查网络连接。",
    "Language": "语言",
    "Working": "进行中",
    "Needs you": "需要你",
    "Done": "完成",
    "Ready": "就绪",
    "Idle": "空闲",
    "Let's grill some bugs.": "来抓点 bug 吧。",
    "Tiny commit, tiny dopamine.": "小提交，小多巴胺。",
    "The build is quiet. Too quiet.": "构建太安静了。",
    "Ship something small.": "发布点小东西吧。",
  },
};

const KEY = "ap_lang";

function detect(): Lang {
  try {
    const saved = localStorage.getItem(KEY);
    if (saved === "en" || saved === "vi" || saved === "zh") return saved;
  } catch {}
  const n = (navigator.language || "en").toLowerCase();
  if (n.startsWith("vi")) return "vi";
  if (n.startsWith("zh")) return "zh";
  return "en";
}

let lang: Lang = detect();

export function getLang(): Lang {
  return lang;
}

export function setLang(l: Lang) {
  lang = l;
  try { localStorage.setItem(KEY, l); } catch {}
}

export function t(key: string): string {
  if (lang === "en") return key;
  return DICT[lang]?.[key] ?? key;
}
