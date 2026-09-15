import Foundation

/// Finds a user-supplied icon for a custom agent.
///
/// Users drop `~/.agentpet/icons/<agent-name>.png` (or `.svg`, `.jpg`,
/// `.jpeg`) and every session hooked with `--agent <agent-name>` shows that
/// image instead of the generated lettered badge. Lookup is case-insensitive
/// on the agent name, which is how AgentPet keys custom agents everywhere else.
public enum CustomIconLocator {
    public static let supportedExtensions = ["png", "svg", "jpg", "jpeg"]

    /// `~/.agentpet/icons`
    public static var defaultDirectory: URL {
        URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("icons", isDirectory: true)
    }

    /// The icon file for `agentName` inside `directory`, or `nil` when none.
    /// Prefers the extension order in `supportedExtensions` when several exist.
    public static func iconURL(forAgentName agentName: String,
                               in directory: URL = defaultDirectory) -> URL? {
        let wanted = agentName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !wanted.isEmpty else { return nil }
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        var best: (rank: Int, url: URL)?
        for url in entries {
            let ext = url.pathExtension.lowercased()
            guard let rank = supportedExtensions.firstIndex(of: ext) else { continue }
            guard url.deletingPathExtension().lastPathComponent.lowercased() == wanted else { continue }
            if best == nil || rank < best!.rank { best = (rank, url) }
        }
        return best?.url
    }
}
