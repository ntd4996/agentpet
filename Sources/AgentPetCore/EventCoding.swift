import Foundation

/// Shared JSON coders so the CLI helper and the daemon agree on the wire
/// format (notably the date strategy).
public enum EventCoding {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()
}

/// Default on-disk locations used by both the daemon and the CLI helper.
public enum AgentPetPaths {
    public static var homeDir: String { FileManager.default.homeDirectoryForCurrentUser.path }

    public static var baseDir: String { baseDirURL.path }
    public static var socketPath: String { baseDirURL.appendingPathComponent("agentpet.sock").path }
    public static var queueDir: String { baseDirURL.appendingPathComponent("queue", isDirectory: true).path }

    public static func homePath(_ components: String...) -> String {
        components.reduce(FileManager.default.homeDirectoryForCurrentUser) { url, component in
            url.appendingPathComponent(component)
        }.path
    }

    private static var baseDirURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".agentpet", isDirectory: true)
    }
}
