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
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 131_072
        try? handle.seek(toOffset: fileSize > maxBytes ? fileSize - maxBytes : 0)
        let raw = handle.readDataToEndOfFile()
        guard let text = String(data: raw, encoding: .utf8) else { return nil }

        for line in text.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let assistantText = extractAssistantText(from: json)
            else { continue }
            return String(assistantText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        }

        return nil
    }

    /// Clears cached titles — useful after fixing the extraction logic at runtime.
    public static func clearCache() {
        summaryCache.removeAll()
        recapCache.removeAll()
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
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 131_072
        try? handle.seek(toOffset: fileSize > maxBytes ? fileSize - maxBytes : 0)
        let raw = handle.readDataToEndOfFile()
        guard let text = String(data: raw, encoding: .utf8) else { return nil }

        for line in text.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let assistantText = extractAssistantText(from: json),
                  let recap = cleanRecap(assistantText)
            else { continue }
            return recap
        }

        return nil
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
