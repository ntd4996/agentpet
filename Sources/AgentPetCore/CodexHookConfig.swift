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
        AgentPetPaths.homePath(".codex", "config.toml")
    }

    /// True if some uncommented line already enables hooks (either key truthy).
    static func alreadyEnabled(_ toml: String) -> Bool {
        for raw in toml.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            let compact = line.replacingOccurrences(of: " ", with: "")
            if compact.hasPrefix("hooks=true") || compact.hasPrefix("codex_hooks=true") { return true }
        }
        return false
    }

    /// Returns `toml` with the hooks feature enabled, or `nil` if it was already
    /// on (so the caller can skip writing).
    public static func enableHooks(in toml: String) -> String? {
        if alreadyEnabled(toml) { return nil }

        var lines = toml.components(separatedBy: "\n")

        // If a hooks / codex_hooks key already exists (e.g. set to false), flip
        // that line to true rather than adding a duplicate key.
        for i in lines.indices {
            let compact = lines[i].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
            if compact.hasPrefix("codex_hooks=") { lines[i] = "codex_hooks = true"; return lines.joined(separator: "\n") }
            if compact.hasPrefix("hooks=") { lines[i] = "hooks = true"; return lines.joined(separator: "\n") }
        }

        // Add `hooks = true` under an existing [features] table if present.
        if let idx = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[features]" }) {
            lines.insert("hooks = true", at: idx + 1)
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
