import Foundation

/// Ensures Codex's hook feature is enabled in `~/.codex/config.toml`. Codex only
/// reads our `~/.codex/hooks.json` when hooks are on. They are on by default on
/// recent Codex, but older versions need `[features] hooks = true` (the key
/// `codex_hooks` is a deprecated alias). We set it conservatively so the
/// integration works regardless of version, without touching any other config.
///
/// The string transform is pure (and tested); `enableHooksOnDisk` wraps it with
/// atomic file IO. It never adds a duplicate key and never edits unrelated keys.
public enum CodexHookConfig {
    public static func defaultConfigPath() -> String {
        NSHomeDirectory() + "/.codex/config.toml"
    }

    /// Finds only the top-level features table, including quoted names and
    /// trailing comments. Nested tables end its body just like unrelated ones.
    private static func featuresBody(_ lines: [String]) -> (header: Int, end: Int)? {
        let pattern = #"^\s*\[\s*(?:features|"features"|'features')\s*\]\s*(?:#.*)?$"#
        guard let header = lines.firstIndex(where: { $0.range(of: pattern, options: .regularExpression) != nil }) else { return nil }
        var end = header + 1
        while end < lines.count, !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("[") { end += 1 }
        return (header, end)
    }

    private static func hooksValueRange(_ line: String) -> Range<String.Index>? {
        let pattern = #"^\s*(?:hooks|"hooks"|'hooks')\s*=\s*(true|false)\s*(?:#.*)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return Range(match.range(at: 1), in: line)
    }

    /// Only the modern `features.hooks` flag counts. The deprecated alias is
    /// ignored by recent Codex, and unrelated tables may have their own hooks.
    static func alreadyEnabled(_ toml: String) -> Bool {
        let lines = toml.components(separatedBy: "\n")
        guard let body = featuresBody(lines) else { return false }
        return (body.header + 1..<body.end).contains { index in
            hooksValueRange(lines[index]).map { lines[index][$0] == "true" } ?? false
        }
    }

    /// Returns `toml` with the hooks feature enabled, or `nil` if it was already
    /// on or its layout cannot safely be edited (so the caller skips writing).
    public static func enableHooks(in toml: String) -> String? {
        if alreadyEnabled(toml) { return nil }

        var lines = toml.components(separatedBy: "\n")

        // simplify: multiline strings and root inline/dotted features need a
        // full TOML parser. Leave them untouched rather than risk a duplicate
        // table or treating string content as a real header.
        if toml.contains("\"\"\"") || toml.contains("'''") { return nil }
        let rootEnd = lines.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.count
        let rootFeature = #"^\s*(?:features|"features"|'features')\s*[.=]"#
        if lines[..<rootEnd].contains(where: { $0.range(of: rootFeature, options: .regularExpression) != nil }) { return nil }

        if let body = featuresBody(lines) {
            for i in body.header + 1..<body.end {
                let hooksKey = #"^\s*(?:hooks|"hooks"|'hooks')\s*="#
                if lines[i].range(of: hooksKey, options: .regularExpression) != nil,
                   hooksValueRange(lines[i]) == nil { return nil }
                if let range = hooksValueRange(lines[i]) {
                    lines[i].replaceSubrange(range, with: "true")
                    return lines.joined(separator: "\n")
                }
            }
            lines.insert("hooks = true", at: body.header + 1)
            return lines.joined(separator: "\n")
        }

        // Otherwise append a new [features] table.
        var result = toml
        if !result.isEmpty && !result.hasSuffix("\n") { result += "\n" }
        result += "\n[features]\nhooks = true\n"
        return result
    }

    /// Reads the config (empty if missing), enables hooks if needed, and writes
    /// it back atomically. No-op if already enabled.
    public static func enableHooksOnDisk(path: String = defaultConfigPath()) throws {
        let existing = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard let updated = enableHooks(in: existing) else { return }
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try Data(updated.utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}
