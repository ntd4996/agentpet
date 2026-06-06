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

    /// Returns the title for the transcript at `path`, or `nil` if unreadable.
    public static func title(at path: String) -> String? {
        if let hit = summaryCache[path] { return hit }
        guard let (result, isSummary) = read(path) else { return nil }
        if isSummary { summaryCache[path] = result }
        return result
    }

    /// Clears cached titles — useful after fixing the extraction logic at runtime.
    public static func clearCache() {
        summaryCache.removeAll()
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
