import Foundation

/// Tool arguments Claude Code sends on PreToolUse / PostToolUse hooks.
public struct ClaudeToolInput: Decodable, Equatable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case filePath = "file_path"
        case command, description, pattern, query, url, prompt
        case subagentType = "subagent_type"
    }
}

// MARK: - Activity Theme

public enum ActivityTheme: String, CaseIterable, Codable, Sendable {
    case chef, engineer, wizard, explorer, scientist

    public var displayName: String {
        switch self {
        case .chef:      return "Chef"
        case .engineer:  return "Engineer"
        case .wizard:    return "Wizard"
        case .explorer:  return "Explorer"
        case .scientist: return "Scientist"
        }
    }

    public var emoji: String {
        switch self {
        case .chef:      return "👨‍🍳"
        case .engineer:  return "⚙️"
        case .wizard:    return "🧙"
        case .explorer:  return "🧭"
        case .scientist: return "🔬"
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
        }
    }

    var writing: [String] {
        switch self {
        case .chef:      return ["Cooking…", "Baking…", "Crafting…", "Whittling…", "Sculpting…", "Stitching…"]
        case .engineer:  return ["Refactoring…", "Implementing…", "Patching…", "Scaffolding…", "Committing…"]
        case .wizard:    return ["Inscribing…", "Enchanting…", "Weaving a spell…", "Scribing…"]
        case .explorer:  return ["Logging the expedition…", "Marking the map…", "Recording findings…", "Documenting…"]
        case .scientist: return ["Synthesizing…", "Documenting findings…", "Writing the report…", "Formulating…"]
        }
    }

    var running: [String] {
        switch self {
        case .chef:      return ["Brewing…", "Simmering…", "Stirring the pot…", "Running the numbers…"]
        case .engineer:  return ["Compiling…", "Building…", "Executing…", "Deploying…", "Running the pipeline…"]
        case .wizard:    return ["Casting…", "Invoking…", "Summoning…", "Channeling magic…"]
        case .explorer:  return ["Blazing a trail…", "Trekking…", "Venturing forth…", "Pushing on…"]
        case .scientist: return ["Running the experiment…", "Executing the protocol…", "Testing the hypothesis…", "Processing…"]
        }
    }

    var searching: [String] {
        switch self {
        case .chef:      return ["Foraging…", "Scouting…", "Hunting…", "Exploring…", "Investigating…"]
        case .engineer:  return ["Scanning…", "Grepping…", "Indexing…", "Tracing…", "Profiling…"]
        case .wizard:    return ["Divining…", "Scrying…", "Seeking…", "Gazing into the orb…"]
        case .explorer:  return ["Scouting ahead…", "Seeking passage…", "Exploring…", "Reconnoitering…"]
        case .scientist: return ["Scanning the dataset…", "Cross-referencing…", "Searching for patterns…", "Correlating…"]
        }
    }

    var delegating: [String] {
        switch self {
        case .chef:      return ["Delegating…", "Hatching a plan…", "Spawning help…", "Rounding up agents…"]
        case .engineer:  return ["Spawning a process…", "Forking…", "Dispatching…", "Queueing a job…"]
        case .wizard:    return ["Calling forth…", "Summoning a familiar…", "Conjuring help…"]
        case .explorer:  return ["Sending a scout…", "Dispatching a guide…", "Rallying the crew…"]
        case .scientist: return ["Assigning to the lab…", "Tasking the team…", "Delegating to an assistant…"]
        }
    }

    var thinking: [String] {
        switch self {
        case .chef:      return ["Photosynthesizing…", "Sprouting…", "Planning…", "Pondering…", "Germinating…", "Marinating…", "Noodling…"]
        case .engineer:  return ["Architecting…", "Designing…", "Calculating…", "Debugging…", "Optimizing…"]
        case .wizard:    return ["Meditating…", "Pondering the arcane…", "Consulting the stars…", "Prophesying…"]
        case .explorer:  return ["Plotting a course…", "Reading the stars…", "Studying the map…", "Planning the route…"]
        case .scientist: return ["Hypothesizing…", "Theorizing…", "Modeling…", "Calculating…", "Reasoning…"]
        }
    }

    var done: [String] {
        switch self {
        case .chef:      return ["All done!", "Wrapped up!", "Delivered!", "Finished!", "Mission complete!"]
        case .engineer:  return ["Build complete!", "Shipped!", "Merged!", "All green!", "Tests passing!"]
        case .wizard:    return ["The spell is cast!", "It is done!", "Magic complete!", "Quest fulfilled!"]
        case .explorer:  return ["Base camp reached!", "Trail blazed!", "Discovery made!", "Expedition complete!"]
        case .scientist: return ["Hypothesis confirmed!", "Results in!", "Experiment complete!", "Published!"]
        }
    }

    var waiting: [String] {
        switch self {
        case .chef:      return ["Awaiting instructions…", "Standing by…", "Listening…"]
        case .engineer:  return ["Awaiting input…", "Blocked on dependency…", "Polling…"]
        case .wizard:    return ["Awaiting the omens…", "The stars are aligning…", "Patience, young apprentice…"]
        case .explorer:  return ["Awaiting the tide…", "Resting at camp…", "Holding position…"]
        case .scientist: return ["Awaiting results…", "Incubating…", "Waiting for the reaction…"]
        }
    }

    var skill: [String] {
        switch self {
        case .chef:      return ["Consulting the recipe…", "Checking the cookbook…", "Following the method…"]
        case .engineer:  return ["Reading the manual…", "Checking the docs…", "Loading the module…"]
        case .wizard:    return ["Consulting the scrolls…", "Channeling a skill…", "Reading the grimoire…"]
        case .explorer:  return ["Consulting the guide…", "Reading the field notes…", "Checking the compass…"]
        case .scientist: return ["Consulting the protocol…", "Reviewing the literature…", "Checking the procedure…"]
        }
    }

    var generic: [String] {
        switch self {
        case .chef:      return ["Working…", "Tinkering…", "Doing the thing…"]
        case .engineer:  return ["Processing…", "Running…", "Executing…"]
        case .wizard:    return ["Weaving…", "Working the magic…", "At work…"]
        case .explorer:  return ["Moving forward…", "Pressing on…", "On the trail…"]
        case .scientist: return ["Analyzing…", "Processing…", "At work…"]
        }
    }
}

// MARK: - Formatter

/// Turns Claude Code hook payloads into whimsical activity lines.
/// Vocabulary is controlled by `currentTheme` (default: `.chef`).
public enum ClaudeActivityFormatter {

    /// Set from `BubbleSettings.activityTheme.didSet` on the main thread.
    public nonisolated(unsafe) static var currentTheme: ActivityTheme = .chef

    public static func activityMessage(
        eventName: String,
        sessionId: String,
        toolName: String?,
        toolInput: ClaudeToolInput?,
        explicitMessage: String?
    ) -> String? {
        if eventName == "Notification" {
            return trimmed(explicitMessage)
        }
        switch eventName {
        case "UserPromptSubmit":
            return pick(from: currentTheme.thinking, key: eventName)
        case "PreToolUse", "PostToolUse":
            return toolActivity(toolName: toolName, toolInput: toolInput)
        default:
            if toolName != nil {
                return toolActivity(toolName: toolName, toolInput: toolInput)
            }
            return trimmed(explicitMessage)
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

    private static func toolActivity(toolName: String?, toolInput: ClaudeToolInput?) -> String? {
        guard let toolName else { return nil }
        if let hint = extensionHint(toolName: toolName, filePath: toolInput?.filePath) { return hint }
        let phrases: [String]
        switch toolName {
        case "Read":
            phrases = currentTheme.reading
        case "Edit", "Write", "MultiEdit":
            phrases = currentTheme.writing
        case "Bash":
            phrases = currentTheme.running
        case "Glob", "Grep", "WebSearch", "WebFetch":
            phrases = currentTheme.searching
        case "Agent", "Task":
            phrases = currentTheme.delegating
        case "Skill":
            phrases = currentTheme.skill
        default:
            phrases = currentTheme.generic
        }
        return pick(from: phrases, key: toolName)
    }

    private static func extensionHint(toolName: String, filePath: String?) -> String? {
        guard let path = filePath else { return nil }
        let lower = path.lowercased()
        let isTest = lower.contains("tests/") || lower.hasSuffix("tests.swift") || lower.hasSuffix("test.swift")
        let isDoc  = lower.hasSuffix(".md") || lower.hasSuffix(".txt") || lower.hasSuffix(".rst")
        let isCfg  = lower.hasSuffix(".json") || lower.hasSuffix(".yaml") || lower.hasSuffix(".yml")
                  || lower.hasSuffix(".plist") || lower.hasSuffix(".toml")
        let isRead  = toolName == "Read"
        let isWrite = toolName == "Edit" || toolName == "Write" || toolName == "MultiEdit"
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
