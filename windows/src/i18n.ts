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
    "Notifications": "Thông báo",
    "Notify when an agent finishes or needs you": "Báo khi agent xong hoặc cần bạn",
    "Startup": "Khởi động",
    "Start AgentPet when Windows starts": "Chạy AgentPet khi khởi động Windows",
    "Couldn't load pets , check your internet connection.":
      "Không tải được pet , kiểm tra kết nối mạng.",
    "Language": "Ngôn ngữ",
    "Bubble": "Bong bóng",
    "Theme": "Giao diện",
    "Opacity": "Độ mờ",
    "Custom messages (one per line, leave empty for default)":
      "Tin tùy chỉnh (mỗi dòng một câu, để trống = mặc định)",
    "Dark": "Tối",
    "Light": "Sáng",
    "Text size": "Cỡ chữ",
    "Font": "Phông chữ",
    "System": "Hệ thống",
    "Rounded": "Bo tròn",
    "Monospace": "Đơn cách",
    "For agent": "Cho agent",
    "All agents": "Tất cả agent",
    "Activity phrases": "Câu hoạt động",
    "Off": "Tắt",
    "Chef": "Đầu bếp",
    "Wizard": "Phù thủy",
    "Scientist": "Nhà khoa học",
    "Explorer": "Nhà thám hiểm",
    "Show idle chatter": "Hiện câu khi rảnh",
    "Pet size": "Cỡ pet",
    "Idle bobbing animation": "Hiệu ứng nhún khi rảnh",
    "Use my own spritesheet…": "Dùng spritesheet của tôi…",
    "Show more": "Xem thêm",
    "General": "Chung",
    "Pet": "Pet",
    "About": "Giới thiệu",
    "Launch at login": "Chạy khi đăng nhập",
    "AgentPet starts automatically when you sign in.": "AgentPet tự khởi động khi bạn đăng nhập.",
    "Alerts when an agent finishes or needs input": "Báo khi agent xong việc hoặc cần bạn nhập",
    "App": "Ứng dụng",
    "Version": "Phiên bản",
    "Quit AgentPet": "Thoát AgentPet",
    "Choose pet": "Chọn pet",
    "Size on screen": "Kích cỡ trên màn hình",
    "Custom messages": "Tin nhắn tùy chỉnh",
    "A desktop pet that watches your AI coding agents.": "Pet trên desktop dõi theo các AI coding agent của bạn.",
    "Star on GitHub": "Thả sao trên GitHub",
    "Join the Discord": "Tham gia Discord",
    "Buy me a coffee": "Mời tôi cà phê",
    "Author": "Tác giả",
    "Live preview": "Xem trước",
    "Try the bubble without running an agent.": "Thử bong bóng mà không cần chạy agent.",
    "Play a sound": "Phát âm thanh",
    "(your image)": "(ảnh của bạn)",
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
    "Notifications": "通知",
    "Notify when an agent finishes or needs you": "当 agent 完成或需要你时通知",
    "Startup": "启动",
    "Start AgentPet when Windows starts": "Windows 启动时运行 AgentPet",
    "Couldn't load pets , check your internet connection.": "无法加载宠物 , 请检查网络连接。",
    "Language": "语言",
    "Bubble": "气泡",
    "Theme": "主题",
    "Opacity": "不透明度",
    "Custom messages (one per line, leave empty for default)": "自定义消息（每行一条，留空使用默认）",
    "Dark": "深色",
    "Light": "浅色",
    "Text size": "字号",
    "Font": "字体",
    "System": "系统",
    "Rounded": "圆体",
    "Monospace": "等宽",
    "For agent": "针对 agent",
    "All agents": "所有 agent",
    "Activity phrases": "活动短语",
    "Off": "关闭",
    "Chef": "厨师",
    "Wizard": "巫师",
    "Scientist": "科学家",
    "Explorer": "探险家",
    "Show idle chatter": "显示空闲时的话",
    "Pet size": "宠物大小",
    "Idle bobbing animation": "空闲时上下浮动动画",
    "Use my own spritesheet…": "使用我自己的精灵图…",
    "Show more": "显示更多",
    "General": "通用",
    "Pet": "宠物",
    "About": "关于",
    "Launch at login": "登录时启动",
    "AgentPet starts automatically when you sign in.": "登录后 AgentPet 会自动启动。",
    "Alerts when an agent finishes or needs input": "当 agent 完成或需要输入时提醒",
    "App": "应用",
    "Version": "版本",
    "Quit AgentPet": "退出 AgentPet",
    "Choose pet": "选择宠物",
    "Size on screen": "屏幕上的大小",
    "Custom messages": "自定义消息",
    "A desktop pet that watches your AI coding agents.": "一只看着你的 AI 编程 agent 的桌面宠物。",
    "Star on GitHub": "在 GitHub 上加星",
    "Join the Discord": "加入 Discord",
    "Buy me a coffee": "请我喝咖啡",
    "Author": "作者",
    "Live preview": "实时预览",
    "Try the bubble without running an agent.": "无需运行 agent 即可试用气泡。",
    "Play a sound": "播放声音",
    "(your image)": "（你的图片）",
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
