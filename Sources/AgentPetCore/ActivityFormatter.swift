import Foundation

/// Tool arguments Claude Code sends on PreToolUse / PostToolUse hooks.
public struct ToolActivityInput: Decodable, Equatable, Sendable {
    public let filePath: String?
    public let command: String?
    public let description: String?
    public let pattern: String?
    public let query: String?
    public let url: String?
    public let prompt: String?
    public let subagentType: String?

    public init(
        filePath: String? = nil, command: String? = nil, description: String? = nil,
        pattern: String? = nil, query: String? = nil, url: String? = nil,
        prompt: String? = nil, subagentType: String? = nil
    ) {
        self.filePath = filePath; self.command = command; self.description = description
        self.pattern = pattern; self.query = query; self.url = url
        self.prompt = prompt; self.subagentType = subagentType
    }

    public init(from decoder: Decoder) throws {
        struct DynamicKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue; self.intValue = nil }
            init?(intValue: Int) { self.stringValue = "\(intValue)"; self.intValue = intValue }
        }
        let container = try decoder.container(keyedBy: DynamicKey.self)
        func findString(_ candidates: [String]) -> String? {
            for c in candidates {
                if let key = DynamicKey(stringValue: c),
                   let val = try? container.decodeIfPresent(String.self, forKey: key) {
                    let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }
        self.filePath = findString(["file_path", "filePath", "path", "Path"])
        self.command = findString(["command", "CommandLine", "command_line", "cmd"])
        self.description = findString(["description", "toolSummary", "tool_summary", "summary"])
        self.pattern = findString(["pattern"])
        self.query = findString(["query", "q"])
        self.url = findString(["url", "uri"])
        self.prompt = findString(["prompt", "Prompt"])
        self.subagentType = findString(["subagent_type", "subagentType", "role", "Role", "type"])
    }
}

// MARK: - Activity Theme

public enum ActivityTheme: String, CaseIterable, Codable, Sendable {
    case chef, engineer, wizard, explorer, scientist, literal

    public var displayName: String {
        switch self {
        case .chef:      return NSLocalizedString("Chef", comment: "activity theme")
        case .engineer:  return NSLocalizedString("Engineer", comment: "activity theme")
        case .wizard:    return NSLocalizedString("Wizard", comment: "activity theme")
        case .explorer:  return NSLocalizedString("Explorer", comment: "activity theme")
        case .scientist: return NSLocalizedString("Scientist", comment: "activity theme")
        case .literal:   return NSLocalizedString("Literal", comment: "activity theme")
        }
    }

    public var emoji: String {
        switch self {
        case .chef:      return "👨‍🍳"
        case .engineer:  return "⚙️"
        case .wizard:    return "🧙"
        case .explorer:  return "🧭"
        case .scientist: return "🔬"
        case .literal:   return "⚡️"
        }
    }

    // MARK: Phrase pools

    var reading: [String] {
        switch self {
        case .chef:      return ["Perusing…", "Leafing through…", "Absorbing…", "Studying…", "Browsing…"]
        case .engineer:  return ["Inspecting…", "Reviewing…", "Parsing…", "Auditing…", "Loading…"]
        case .wizard:    return ["Studying the scrolls…", "Deciphering…", "Consulting the tome…", "Peering within…"]
        case .explorer:  return ["Surveying…", "Mapping the terrain…", "Examining the site…", "Charting…"]
        case .scientist: return ["Observing…", "Reviewing the data…", "Analyzing the sample…", "Examining…"]
        case .literal:   return ["Reading…", "Inspecting…"]
        }
    }

    var writing: [String] {
        switch self {
        case .chef:      return ["Cooking…", "Baking…", "Crafting…", "Whittling…", "Sculpting…", "Stitching…"]
        case .engineer:  return ["Refactoring…", "Implementing…", "Patching…", "Scaffolding…", "Committing…"]
        case .wizard:    return ["Inscribing…", "Enchanting…", "Weaving a spell…", "Scribing…"]
        case .explorer:  return ["Logging the expedition…", "Marking the map…", "Recording findings…", "Documenting…"]
        case .scientist: return ["Synthesizing…", "Documenting findings…", "Writing the report…", "Formulating…"]
        case .literal:   return ["Editing…", "Writing…"]
        }
    }

    var running: [String] {
        switch self {
        case .chef:      return ["Brewing…", "Simmering…", "Stirring the pot…", "Running the numbers…"]
        case .engineer:  return ["Compiling…", "Building…", "Executing…", "Deploying…", "Running the pipeline…"]
        case .wizard:    return ["Casting…", "Invoking…", "Summoning…", "Channeling magic…"]
        case .explorer:  return ["Blazing a trail…", "Trekking…", "Venturing forth…", "Pushing on…"]
        case .scientist: return ["Running the experiment…", "Executing the protocol…", "Testing the hypothesis…", "Processing…"]
        case .literal:   return ["Executing…", "Running…"]
        }
    }

    var searching: [String] {
        switch self {
        case .chef:      return ["Foraging…", "Scouting…", "Hunting…", "Exploring…", "Investigating…"]
        case .engineer:  return ["Scanning…", "Grepping…", "Indexing…", "Tracing…", "Profiling…"]
        case .wizard:    return ["Divining…", "Scrying…", "Seeking…", "Gazing into the orb…"]
        case .explorer:  return ["Scouting ahead…", "Seeking passage…", "Exploring…", "Reconnoitering…"]
        case .scientist: return ["Scanning the dataset…", "Cross-referencing…", "Searching for patterns…", "Correlating…"]
        case .literal:   return ["Searching…", "Scanning…"]
        }
    }

    var delegating: [String] {
        switch self {
        case .chef:      return ["Delegating…", "Hatching a plan…", "Spawning help…", "Rounding up agents…"]
        case .engineer:  return ["Spawning a process…", "Forking…", "Dispatching…", "Queueing a job…"]
        case .wizard:    return ["Calling forth…", "Summoning a familiar…", "Conjuring help…"]
        case .explorer:  return ["Sending a scout…", "Dispatching a guide…", "Rallying the crew…"]
        case .scientist: return ["Assigning to the lab…", "Tasking the team…", "Delegating to an assistant…"]
        case .literal:   return ["Delegating…", "Spawning…"]
        }
    }

    var thinking: [String] {
        switch self {
        case .chef:      return ["Photosynthesizing…", "Sprouting…", "Planning…", "Pondering…", "Germinating…", "Marinating…", "Noodling…"]
        case .engineer:  return ["Architecting…", "Designing…", "Calculating…", "Debugging…", "Optimizing…"]
        case .wizard:    return ["Meditating…", "Pondering the arcane…", "Consulting the stars…", "Prophesying…"]
        case .explorer:  return ["Plotting a course…", "Reading the stars…", "Studying the map…", "Planning the route…"]
        case .scientist: return ["Hypothesizing…", "Theorizing…", "Modeling…", "Calculating…", "Reasoning…"]
        case .literal:   return ["Thinking…", "Analyzing request…", "Processing…"]
        }
    }

    var done: [String] {
        switch self {
        case .chef:      return ["All done!", "Wrapped up!", "Delivered!", "Finished!", "Mission complete!"]
        case .engineer:  return ["Build complete!", "Shipped!", "Merged!", "All green!", "Tests passing!"]
        case .wizard:    return ["The spell is cast!", "It is done!", "Magic complete!", "Quest fulfilled!"]
        case .explorer:  return ["Base camp reached!", "Trail blazed!", "Discovery made!", "Expedition complete!"]
        case .scientist: return ["Hypothesis confirmed!", "Results in!", "Experiment complete!", "Published!"]
        case .literal:   return ["Done", "Task complete", "Finished"]
        }
    }

    var waiting: [String] {
        switch self {
        case .chef:      return ["Awaiting instructions…", "Standing by…", "Listening…"]
        case .engineer:  return ["Awaiting input…", "Blocked on dependency…", "Polling…"]
        case .wizard:    return ["Awaiting the omens…", "The stars are aligning…", "Patience, young apprentice…"]
        case .explorer:  return ["Awaiting the tide…", "Resting at camp…", "Holding position…"]
        case .scientist: return ["Awaiting results…", "Incubating…", "Waiting for the reaction…"]
        case .literal:   return ["Waiting for input…", "Needs approval…"]
        }
    }

    var skill: [String] {
        switch self {
        case .chef:      return ["Consulting the recipe…", "Checking the cookbook…", "Following the method…"]
        case .engineer:  return ["Reading the manual…", "Checking the docs…", "Loading the module…"]
        case .wizard:    return ["Consulting the scrolls…", "Channeling a skill…", "Reading the grimoire…"]
        case .explorer:  return ["Consulting the guide…", "Reading the field notes…", "Checking the compass…"]
        case .scientist: return ["Consulting the protocol…", "Reviewing the literature…", "Checking the procedure…"]
        case .literal:   return ["Running skill…", "Executing workflow…"]
        }
    }

    var generic: [String] {
        switch self {
        case .chef:      return ["Working…", "Tinkering…", "Doing the thing…"]
        case .engineer:  return ["Processing…", "Running…", "Executing…"]
        case .wizard:    return ["Weaving…", "Working the magic…", "At work…"]
        case .explorer:  return ["Moving forward…", "Pressing on…", "On the trail…"]
        case .scientist: return ["Analyzing…", "Processing…", "At work…"]
        case .literal:   return ["Working…", "Processing…"]
        }
    }
}

// MARK: - Formatter

/// Turns Claude Code hook payloads into whimsical activity lines.
/// Vocabulary is controlled by `currentTheme` (default: `.chef`).
public enum ActivityFormatter {

    /// Loads the stored activity theme from user preferences (checking the app suite first
    /// so CLI helper processes invoked by agent hooks pick up the GUI's selection).
    public static func loadStoredTheme() {
        let ud: UserDefaults = {
            if Bundle.main.bundleIdentifier == "com.agentpet.app" {
                return UserDefaults.standard
            }
            return UserDefaults(suiteName: "com.agentpet.app") ?? UserDefaults.standard
        }()
        if let raw = ud.string(forKey: "agentpet.bubble.activityTheme"),
           let theme = ActivityTheme(rawValue: raw) {
            currentTheme = theme
        }
    }

    /// Set from `BubbleSettings.activityTheme.didSet` on the main thread, or loaded from preferences.
    public nonisolated(unsafe) static var currentTheme: ActivityTheme = {
        let ud: UserDefaults = {
            if Bundle.main.bundleIdentifier == "com.agentpet.app" {
                return UserDefaults.standard
            }
            return UserDefaults(suiteName: "com.agentpet.app") ?? UserDefaults.standard
        }()
        if let raw = ud.string(forKey: "agentpet.bubble.activityTheme"),
           let theme = ActivityTheme(rawValue: raw) {
            return theme
        }
        return .chef
    }()

    public static func activityMessage(
        eventName: String,
        sessionId: String,
        toolName: String?,
        toolInput: ToolActivityInput?,
        explicitMessage: String?
    ) -> String? {
        if eventName == "Notification" {
            return trimmed(explicitMessage)
        }
        switch eventName {
        case "UserPromptSubmit", "PreInvocation", "turn_start", "agent_start":
            return pick(from: currentTheme.thinking, key: "thinking")
        case "PreToolUse", "PostToolUse":
            return toolActivity(toolName: toolName, toolInput: toolInput)
        default:
            if toolName != nil {
                return toolActivity(toolName: toolName, toolInput: toolInput)
            }
            if let explicit = trimmed(explicitMessage) {
                return explicit
            }
            if eventName == "working" {
                return pick(from: currentTheme.thinking, key: "thinking")
            }
            return nil
        }
    }

    public static func stateMessage(for state: AgentState) -> String? {
        switch state {
        case .done:    return pick(from: currentTheme.done,    key: "state.done")
        case .waiting: return pick(from: currentTheme.waiting, key: "state.waiting")
        default:       return nil
        }
    }

    // MARK: Private

    private enum ActivityCategory {
        case reading, writing, running, searching, delegating, skill, generic
    }

    /// Maps a tool name to a category by keyword, case-insensitively. Works for
    /// both Claude Code's tool names (`Read`, `Edit`, `Bash`, `Glob`, `Grep`,
    /// `WebSearch`, `WebFetch`, `Agent`, `Task`, `Skill`) and other agents'
    /// (e.g. Cursor's `read_file`, `edit_file`, `run_terminal_cmd`,
    /// `codebase_search`, `list_dir`). Order matters: more specific categories
    /// are checked first to avoid collisions.
    private static func category(forToolName toolName: String) -> ActivityCategory {
        let n = toolName.lowercased()
        if n.contains("task") || n.contains("agent") { return .delegating }
        if n.contains("skill") { return .skill }
        if n.contains("search") || n.contains("grep") || n.contains("glob")
            || n.contains("find") || n.contains("list") || n.contains("fetch") { return .searching }
        if n.contains("run") || n.contains("shell") || n.contains("terminal")
            || n.contains("bash") || n.contains("exec") || n.contains("command") { return .running }
        if n.contains("edit") || n.contains("write") || n.contains("create")
            || n.contains("patch") || n.contains("delete") { return .writing }
        if n.contains("read") || n.contains("view") { return .reading }
        return .generic
    }

    public static func literalAction(toolName: String, toolInput: ToolActivityInput?) -> String? {
        let cat = category(forToolName: toolName)
        return literalAction(category: cat, toolName: toolName, toolInput: toolInput)
    }

    private static func literalAction(
        category: ActivityCategory,
        toolName: String,
        toolInput: ToolActivityInput?
    ) -> String? {
        if let desc = toolInput?.description?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
            return desc
        }

        if let path = toolInput?.filePath?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty {
            let fileName = (path as NSString).lastPathComponent
            switch category {
            case .writing:
                return "Editing \(fileName)"
            case .reading:
                return "Reading \(fileName)"
            default:
                return "\(fileName)"
            }
        }

        if let cmd = toolInput?.command?.trimmingCharacters(in: .whitespacesAndNewlines), !cmd.isEmpty {
            let firstLine = cmd.components(separatedBy: .newlines).first ?? cmd
            let clean = firstLine.trimmingCharacters(in: .whitespaces)
            let truncated = clean.count > 35 ? String(clean.prefix(32)) + "…" : clean
            return "Running: \(truncated)"
        }

        if let q = (toolInput?.query ?? toolInput?.pattern)?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty {
            let truncated = q.count > 30 ? String(q.prefix(27)) + "…" : q
            return "Searching: \"\(truncated)\""
        }

        if let sub = toolInput?.subagentType?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            return "Subagent: \(sub)"
        }
        if let prompt = toolInput?.prompt?.trimmingCharacters(in: .whitespacesAndNewlines), !prompt.isEmpty {
            let truncated = prompt.count > 30 ? String(prompt.prefix(27)) + "…" : prompt
            return "Subagent: \(truncated)"
        }

        return formatToolName(toolName)
    }

    private static func formatToolName(_ toolName: String) -> String {
        let n = toolName.lowercased()
        if n == "run_command" || n == "bash" || n == "run_terminal_cmd" {
            return "Running command…"
        }
        if n == "read_file" || n == "read" || n == "view" {
            return "Reading file…"
        }
        if n == "edit_file" || n == "write_file" || n == "edit" || n == "write" {
            return "Editing file…"
        }
        if n == "search_web" || n == "websearch" || n == "web_search" {
            return "Searching web…"
        }
        if n == "grep" || n == "glob" || n == "codebase_search" || n == "grep_search" {
            return "Searching codebase…"
        }
        if n == "invoke_subagent" || n == "agent" || n == "task" {
            return "Delegating task…"
        }
        if n == "ask_question" {
            return "Asking question…"
        }
        return "Using \(toolName)…"
    }

    private static func toolActivity(toolName: String?, toolInput: ToolActivityInput?) -> String? {
        guard let toolName else { return nil }
        let cat = category(forToolName: toolName)

        if currentTheme == .literal {
            if let literal = literalAction(category: cat, toolName: toolName, toolInput: toolInput) {
                return literal
            }
            return currentTheme.generic.first ?? "Working…"
        }

        if let hint = extensionHint(category: cat, filePath: toolInput?.filePath) { return hint }
        let phrases: [String]
        switch cat {
        case .reading:    phrases = currentTheme.reading
        case .writing:    phrases = currentTheme.writing
        case .running:    phrases = currentTheme.running
        case .searching:  phrases = currentTheme.searching
        case .delegating: phrases = currentTheme.delegating
        case .skill:      phrases = currentTheme.skill
        case .generic:    phrases = currentTheme.generic
        }
        return pick(from: phrases, key: toolName)
    }

    private static func extensionHint(category: ActivityCategory, filePath: String?) -> String? {
        guard let path = filePath else { return nil }
        let lower = path.lowercased()
        let isTest = lower.contains("tests/") || lower.hasSuffix("tests.swift") || lower.hasSuffix("test.swift")
        let isDoc  = lower.hasSuffix(".md") || lower.hasSuffix(".txt") || lower.hasSuffix(".rst")
        let isCfg  = lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml")
                  || lower.hasSuffix(".plist") || lower.hasSuffix(".toml")
        let isRead  = category == .reading
        let isWrite = category == .writing
        if isTest  && isRead  { return "Reviewing tests…" }
        if isTest  && isWrite { return "Refining tests…" }
        if isDoc   && isRead  { return "Reading the docs…" }
        if isDoc   && isWrite { return "Updating the docs…" }
        if isCfg   && isRead  { return "Parsing config…" }
        if isCfg   && isWrite { return "Adjusting config…" }
        return nil
    }

    nonisolated(unsafe) private static var callCounts: [String: Int] = [:]

    private static func pick(from phrases: [String], key: String) -> String {
        guard !phrases.isEmpty else { return "Working…" }
        let n = (callCounts[key, default: 0] + 1) % phrases.count
        callCounts[key] = n
        return phrases[n]
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        return text
    }
}
