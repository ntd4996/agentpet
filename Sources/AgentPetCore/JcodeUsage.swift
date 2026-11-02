import Foundation

/// Token usage of a jcode session. jcode's hooks carry no token counts, so the
/// session files are the only source: a snapshot `~/.jcode/sessions/<id>.json`
/// plus a journal `<id>.journal.jsonl` of messages appended since the last
/// snapshot (folded back into the snapshot, and deleted, once it passes
/// 512 KB). Each assistant message has a `token_usage` object, so the
/// session's total is the sum over both files.
///
/// simplify: both files are rescanned whole once per turn (tens of MB for a
/// long session). If jcode adds token fields to its `turn_end` hook, read
/// those instead and drop this.
public enum JcodeUsage {
    /// `~/.jcode/sessions/<id>.json`, or nil for an id that could escape the
    /// sessions directory.
    public static func sessionPath(sessionId: String, home: String) -> String? {
        guard !sessionId.isEmpty, !sessionId.contains("/"), !sessionId.contains("..") else { return nil }
        return home + "/.jcode/sessions/" + sessionId + ".json"
    }

    /// The journal next to a snapshot path (`<id>.json` -> `<id>.journal.jsonl`).
    public static func journalPath(snapshotPath: String) -> String {
        (snapshotPath as NSString).deletingPathExtension + ".journal.jsonl"
    }

    /// Session total from the snapshot and journal on disk. A missing file
    /// counts as 0 (no journal yet, or jcode just checkpointed it away).
    /// Snapshot first: a checkpoint landing between the two reads then makes
    /// this read low, and the tracker feeds the rest at the next turn.
    /// Not covered: a read inside jcode's own write-snapshot/delete-journal
    /// gap (microseconds) counts the journal twice.
    public static func totalTokens(snapshotPath: String) -> Int {
        [snapshotPath, journalPath(snapshotPath: snapshotPath)].reduce(0) { sum, path in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else { return sum }
            return sum + totalTokens(sessionData: data)
        }
    }

    /// Tokens the model actually processed for one response, cached prompt
    /// tokens excluded. Matches how Claude transcripts (input + output) and
    /// Codex rollouts (input - cached + output) are counted.
    /// jcode reports `prompt_tokens` = uncached + cache read + cache write for
    /// every provider, so subtracting both cache fields works for Anthropic
    /// (where `input_tokens` is already uncached) and OpenAI (where it is not).
    static func billableTokens(_ usage: [String: Any]) -> Int {
        let output = int(usage["output_tokens"])
        guard let prompt = usage["prompt_tokens"].map(int) else {
            return int(usage["input_tokens"]) + output
        }
        let cached = int(usage["cache_read_input_tokens"]) + int(usage["cache_creation_input_tokens"])
        return max(0, prompt - cached) + output
    }

    private static let key = Data("\"token_usage\":".utf8)

    /// Sum of `billableTokens` over every `"token_usage":{…}` object in the
    /// session file. Scans bytes instead of parsing the whole document: a
    /// 40 MB session took 114 MB of RAM to parse, the scan only needs the
    /// (memory-mapped) file. Safe because the key cannot occur inside a JSON
    /// string unescaped, and the usage object is flat (no nested braces).
    public static func totalTokens(sessionData data: Data) -> Int {
        var total = 0
        var cursor = data.startIndex
        while let hit = data.range(of: key, in: cursor..<data.endIndex) {
            var open = hit.upperBound
            while open < data.endIndex, data[open] == UInt8(ascii: " ") { open += 1 }
            guard open < data.endIndex, data[open] == UInt8(ascii: "{"),
                  let close = data[open...].firstIndex(of: UInt8(ascii: "}")) else {
                cursor = hit.upperBound
                continue
            }
            if let usage = try? JSONSerialization.jsonObject(with: data[open...close]) as? [String: Any] {
                total += billableTokens(usage)
            }
            cursor = close + 1
        }
        return total
    }

    private static func int(_ any: Any?) -> Int {
        (any as? NSNumber)?.intValue ?? 0
    }
}

/// Turns session totals into per-turn deltas. A session seen for the first
/// time only sets the baseline, so tokens spent before AgentPet saw it are not
/// fed in one go. A total that shrinks (jcode compacting history) also just
/// moves the baseline.
public struct JcodeUsageTracker {
    private struct Entry { var total: Int; var touched: Int }
    private var seen: [String: Entry] = [:]
    private var tick = 0

    /// A session that never sends session_end (jcode killed, machine slept)
    /// would stay here forever, so the least recently touched go once there are
    /// more than this. A dropped session only loses its baseline: the next turn
    /// re-baselines instead of feeding anything.
    public static let maxSessions = 200

    public init() {}

    private mutating func touch(_ total: Int, for sessionId: String) {
        tick += 1
        seen[sessionId] = Entry(total: total, touched: tick)
        guard seen.count > Self.maxSessions else { return }
        let drop = seen.sorted { $0.value.touched < $1.value.touched }
            .prefix(seen.count - Self.maxSessions)
        for (key, _) in drop { seen.removeValue(forKey: key) }
    }

    /// Records `total` as the baseline if the session is new. Returns nothing:
    /// called at the start of a turn, before the turn's tokens exist.
    public mutating func baseline(sessionId: String, total: Int) {
        if seen[sessionId] == nil { touch(total, for: sessionId) }
    }

    /// Tokens added since the last call for this session (0 the first time).
    public mutating func delta(sessionId: String, total: Int) -> Int {
        let last = seen[sessionId]?.total
        touch(total, for: sessionId)
        guard let last, total > last else { return 0 }
        return total - last
    }

    public mutating func forget(sessionId: String) {
        seen.removeValue(forKey: sessionId)
    }

    public func isTracking(_ sessionId: String) -> Bool { seen[sessionId] != nil }

    public var count: Int { seen.count }
}
