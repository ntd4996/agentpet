import Foundation

/// Extracts a human-readable conversation title from an agent transcript file.
///
/// For Claude Code the transcript is a JSONL file. Each line is a JSON object.
/// The reader looks for:
/// 1. A `{"type":"summary","summary":"..."}` event — Claude names conversations
///    with this after the first exchange.
/// 2. Fallback: the first `{"type":"user","message":{"content":[{"type":"text","text":"..."}]}}`
///    line, truncated to 60 characters.
///
/// Results are cached per path so repeated calls within the same run are free.
public enum TranscriptReader {

    // Summary-based titles are final — once cached, never re-read.
    // Provisional titles (first user message) are not cached: a later summary
    // event should supersede them on the next call.
    nonisolated(unsafe) private static var summaryCache: [String: String] = [:]
    nonisolated(unsafe) private static var recapCache: [String: String] = [:]
    // Byte offset already consumed by `newUsageTokens` per transcript path.
    nonisolated(unsafe) private static var usageOffsets: [String: UInt64] = [:]
    // Guards `usageOffsets` and the token/cost scan against concurrent callers.
    private static let stateLock = NSLock()

    /// Tokens + estimated USD cost computed together from one scan, so callers
    /// never observe a token count paired with a mismatched cost.
    public struct UsageDelta: Equatable {
        public let tokens: Int
        public let costUSD: Double
    }

    /// Returns the title for the transcript at `path`, or `nil` if unreadable.
    public static func title(at path: String) -> String? {
        if let hit = summaryCache[path] { return hit }
        guard let (result, isSummary) = read(path) else { return nil }
        if isSummary { summaryCache[path] = result }
        return result
    }

    /// Returns the latest Claude assistant recap from the transcript, collapsed
    /// to one display line, or `nil` when the transcript has no recap marker.
    public static func latestAssistantRecap(at path: String) -> String? {
        if let hit = recapCache[path] { return hit }
        guard let result = readLatestAssistantRecap(path) else { return nil }
        recapCache[path] = result
        return result
    }

    /// Returns the raw, trimmed text of the most recent Claude assistant
    /// message in the transcript (capped at 400 characters), or `nil` if none
    /// is found. Unlike `latestAssistantRecap`, this returns ordinary
    /// turn-ending text too — it's used to check whether Claude ended its
    /// turn by asking the user a question, not to extract a named recap.
    public static func latestAssistantText(at path: String) -> String? {
        guard let lines = tailLinesReversed(path) else { return nil }

        for trimmed in lines {
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let assistantText = extractAssistantText(from: json)
            else { continue }
            return String(assistantText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        }

        return nil
    }

    /// Returns the model identifier (e.g. "claude-opus-4-1-20250805") used for
    /// the most recent assistant message, or `nil` if none is found. Hook
    /// payloads only report the model at `SessionStart`, so this lets the
    /// bubble follow `/model` switches made mid-session.
    public static func latestAssistantModel(at path: String) -> String? {
        guard let lines = tailLinesReversed(path) else { return nil }

        for trimmed in lines {
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let model = message["model"] as? String
            else { continue }
            return model
        }

        return nil
    }

    /// Clears cached titles — useful after fixing the extraction logic at runtime.
    public static func clearCache() {
        stateLock.lock()
        defer { stateLock.unlock() }
        summaryCache.removeAll()
        recapCache.removeAll()
        usageOffsets.removeAll()
    }

    /// Sums the model usage tokens (input + output) appended since the previous call for `path`. The first call consumes the whole file; returns `nil` if unreadable, `0` if nothing new.
    public static func newUsageTokens(at path: String) -> Int? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return scanUsageDelta(path)?.tokens
    }

    /// Same scan as `newUsageTokens`, but returns tokens and estimated USD cost together from one pass so the two values can never mismatch. `nil` when unreadable.
    public static func newUsageDelta(at path: String) -> UsageDelta? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return scanUsageDelta(path)
    }

    // Advances usageOffsets[path] past every complete new line and returns the summed tokens/cost. Callers must hold stateLock.
    private static func scanUsageDelta(_ path: String) -> UsageDelta? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var start = usageOffsets[path] ?? 0
        if start > size { start = 0 }   // truncated/replaced file: start over
        guard size > start else { return UsageDelta(tokens: 0, costUSD: 0) }

        try? handle.seek(toOffset: start)
        let raw = handle.readDataToEndOfFile()
        // Only consume up to the last full line; a partial trailing line is left for the next call.
        let consumable: Data
        if let nl = raw.lastIndex(of: UInt8(ascii: "\n")) {
            consumable = raw[raw.startIndex...nl]
        } else {
            return UsageDelta(tokens: 0, costUSD: 0)
        }
        usageOffsets[path] = start + UInt64(consumable.count)

        guard let text = String(data: consumable, encoding: .utf8) else { return UsageDelta(tokens: 0, costUSD: 0) }
        var total = 0
        var costAccumulator = 0.0
        for line in text.components(separatedBy: "\n") {
            // Fast reject: most lines carry no usage object at all.
            guard line.contains("\"usage\"") else { continue }
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = json["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any]
            else { continue }
            let inputTokens = usage["input_tokens"] as? Int ?? 0
            let outputTokens = usage["output_tokens"] as? Int ?? 0
            total += inputTokens
            total += outputTokens
            costAccumulator += ModelPricing.costUSD(
                model: message["model"] as? String,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheCreateTokens: usage["cache_creation_input_tokens"] as? Int ?? 0,
                cacheReadTokens: usage["cache_read_input_tokens"] as? Int ?? 0
            )
        }
        return UsageDelta(tokens: total, costUSD: costAccumulator)
    }

    // MARK: - Codex (rollout) usage

    /// Sums new Codex token usage appended to a rollout JSONL since the previous
    /// call for the same path (offset-based, like `newUsageTokens`). Codex writes
    /// `{"payload":{"type":"token_count","info":{"last_token_usage":{...}}}}` once
    /// per turn; we sum fresh input (minus cached) + output to mirror Claude's
    /// `input_tokens + output_tokens`, so the leaderboard is comparable (#29).
    public static func newCodexUsageTokens(at path: String) -> Int? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        var start = usageOffsets[path] ?? 0
        if start > size { start = 0 }
        guard size > start else { return 0 }

        try? handle.seek(toOffset: start)
        let raw = handle.readDataToEndOfFile()
        guard let nl = raw.lastIndex(of: UInt8(ascii: "\n")) else { return 0 }
        let consumable = raw[raw.startIndex...nl]
        usageOffsets[path] = start + UInt64(consumable.count)

        guard let text = String(data: consumable, encoding: .utf8) else { return 0 }
        var total = 0
        for line in text.components(separatedBy: "\n") {
            guard line.contains("\"last_token_usage\"") else { continue }
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any]
            else { continue }
            let input = last["input_tokens"] as? Int ?? 0
            let cached = last["cached_input_tokens"] as? Int ?? 0
            let output = last["output_tokens"] as? Int ?? 0
            total += max(0, input - cached) + output
        }
        return total
    }

    /// Locates a Codex session's rollout file. Primary: a filename containing the
    /// session id (`rollout-<ts>-<uuid>.jsonl`). Fallback: the most recently
    /// modified rollout whose `session_meta.cwd` matches `cwd`.
    public static func codexRolloutPath(sessionId: String, cwd: String?) -> String? {
        let root = NSHomeDirectory() + "/.codex/sessions"
        let fm = FileManager.default
        guard let en = fm.enumerator(atPath: root) else { return nil }
        var candidates: [(path: String, mtime: Date)] = []
        for case let rel as String in en where rel.hasSuffix(".jsonl") && rel.contains("rollout-") {
            let full = root + "/" + rel
            if rel.contains(sessionId) { return full }   // exact session match
            let m = (try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date) ?? nil
            candidates.append((full, m ?? .distantPast))
        }
        guard let cwd, !cwd.isEmpty else { return nil }
        let target = ProjectPetResolver.normalize(cwd)
        // Newest first; match the rollout whose session_meta cwd is this project.
        for (path, _) in candidates.sorted(by: { $0.mtime > $1.mtime }).prefix(40) {
            guard let line = firstLine(ofFile: path),
                  let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["payload"] as? [String: Any],
                  let c = payload["cwd"] as? String else { continue }
            if ProjectPetResolver.normalize(c) == target { return path }
        }
        return nil
    }

    private static func firstLine(ofFile path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let chunk = handle.readData(ofLength: 4096)
        guard let s = String(data: chunk, encoding: .utf8) else { return nil }
        return s.components(separatedBy: "\n").first
    }

    /// Path to a subagent's transcript for a `SubagentStop` event. Claude Code
    /// stores them at `<parent-without-.jsonl>/subagents/<agent-id>.jsonl`, i.e.
    /// `~/.claude/projects/<sanitized-cwd>/<session-id>/subagents/<agent-id>.jsonl`.
    public static func subagentTranscriptPath(parentTranscriptPath: String, agentId: String) -> String {
        let parentDir = (parentTranscriptPath as NSString).deletingPathExtension
        return parentDir + "/subagents/" + agentId + ".jsonl"
    }

    /// Constructs the expected transcript path for a Claude Code session.
    ///
    /// Claude Code stores transcripts at `~/.claude/projects/<sanitized-cwd>/<session-id>.jsonl`
    /// where the sanitized CWD replaces every `/` with `-` and prepends a leading `-`.
    /// Use this when `transcript_path` is absent from the hook payload.
    public static func inferredPath(sessionId: String, cwd: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // The leading '/' in an absolute path becomes the leading '-' after replacement,
        // so no extra prefix is needed. e.g. /Users/foo → -Users-foo
        let sanitized = cwd.replacingOccurrences(of: "/", with: "-")
        return "\(home)/.claude/projects/\(sanitized)/\(sessionId).jsonl"
    }

    // Returns (title, isSummary) — isSummary true means the title came from a
    // Claude-generated summary event and can be cached permanently.
    private static func read(_ path: String) -> (String, Bool)? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        // Read first 32 KB — enough to cover the summary event which appears early.
        let raw = handle.readData(ofLength: 32_768)
        // Truncate to the last newline to avoid splitting a multi-byte UTF-8 sequence
        // at the read boundary, which would make String(data:encoding:) return nil.
        let safeRaw: Data
        if raw.count == 32_768, let nl = raw.lastIndex(of: UInt8(ascii: "\n")) {
            safeRaw = raw[...nl]
        } else {
            safeRaw = raw
        }
        guard let text = String(data: safeRaw, encoding: .utf8) else { return nil }

        var firstUserText: String?

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = json["type"] as? String
            else { continue }

            // Claude Code writes a "summary" event when it names the conversation.
            if type == "summary",
               let summary = json["summary"] as? String,
               !summary.trimmingCharacters(in: .whitespaces).isEmpty {
                return (summary, true)
            }

            // Scan every user event; keep the first that yields real human text.
            if firstUserText == nil, type == "user" {
                firstUserText = extractUserText(from: json)
            }
        }

        return firstUserText.map { ($0, false) }
    }

    private static func readLatestAssistantRecap(_ path: String) -> String? {
        guard let lines = tailLinesReversed(path) else { return nil }

        for trimmed in lines {
            guard let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let assistantText = extractAssistantText(from: json),
                  let recap = cleanRecap(assistantText)
            else { continue }
            return recap
        }

        return nil
    }

    /// Reads the tail of `path` (last 128 KB) and returns its non-empty,
    /// trimmed lines in reverse order (most recent first), or `nil` if the
    /// file can't be read.
    private static func tailLinesReversed(_ path: String) -> [String]? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 131_072
        try? handle.seek(toOffset: fileSize > maxBytes ? fileSize - maxBytes : 0)
        let raw = handle.readDataToEndOfFile()
        guard let text = String(data: raw, encoding: .utf8) else { return nil }

        return text.components(separatedBy: "\n").reversed()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func extractUserText(from json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any] else { return nil }

        // Array-of-blocks format (tool results, text blocks, etc.)
        if let blocks = message["content"] as? [[String: Any]] {
            for block in blocks {
                // Only plain text blocks — skip tool_result, tool_use, image, etc.
                guard block["type"] as? String == "text",
                      let raw = block["text"] as? String else { continue }
                if let clean = humanReadable(raw) { return clean }
            }
            return nil
        }

        // Plain-string format (common in older / simple sessions).
        if let raw = message["content"] as? String {
            return humanReadable(raw)
        }

        return nil
    }

    private static func extractAssistantText(from json: [String: Any]) -> String? {
        guard let message = json["message"] as? [String: Any] else { return nil }

        if let blocks = message["content"] as? [[String: Any]] {
            let text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }

        if let raw = message["content"] as? String {
            return raw
        }

        return nil
    }

    private static func cleanRecap(_ text: String) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let markers = [
            #"(?i)(?:^|\s)(?:[※*#\-\s]*)recap\s*:\s*"#,
            #"(?i)(?:^|\s)(?:all\s+changes\s+done|done)\.?\s+summary(?:\s+of\s+all\s+changes)?\s*:\s*"#,
            #"(?i)(?:^|\s)summary\s+of\s+all\s+changes\s*:\s*"#
        ]

        guard let range = markers.compactMap({
            collapsed.range(of: $0, options: .regularExpression)
        }).first else { return nil }

        let recap = collapsed[range.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return recap.isEmpty ? nil : String(recap)
    }

    /// Returns `text` trimmed and capped at 60 chars, or `nil` if it looks like
    /// a system injection (XML tags such as `<local-command>`, tool wrappers, etc.)
    private static func humanReadable(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Skip XML-style system injections ("<local-command>…", "<result>…", etc.)
        guard !trimmed.hasPrefix("<") else { return nil }
        return String(trimmed.prefix(60))
    }
}
