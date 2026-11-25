import Foundation
import Combine
import AgentPetCore

/// Manages settings for receiving events from remote servers/VPS over SSH tunnel or local port.
@MainActor
public final class RemoteServerSettings: ObservableObject {
    public static let shared = RemoteServerSettings()

    public static let defaultPort: Int = 3838

    private let isEnabledKey = "agentpet.remote.enabled"
    private let portKey = "agentpet.remote.port"
    private let tokenKey = "agentpet.remote.token"

    @Published public var isEnabled: Bool { didSet { save() } }
    @Published public var port: Int { didSet { save() } }
    @Published public var authToken: String { didSet { save() } }
    @Published public private(set) var connectedHosts: [String: Date] = [:]

    public init() {
        let d = UserDefaults.standard
        self.isEnabled = (d.object(forKey: isEnabledKey) as? Bool) ?? true
        let savedPort = d.integer(forKey: portKey)
        self.port = savedPort > 0 ? savedPort : Self.defaultPort

        if let savedToken = d.string(forKey: tokenKey), !savedToken.isEmpty {
            self.authToken = savedToken
        } else {
            let newToken = Self.generateToken()
            self.authToken = newToken
            d.set(newToken, forKey: tokenKey)
        }
    }

    public static func generateToken() -> String {
        "pet_sec_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    nonisolated public static func currentAuthToken() -> String {
        UserDefaults.standard.string(forKey: "agentpet.remote.token") ?? ""
    }

    public func regenerateToken() {
        authToken = Self.generateToken()
    }

    public func recordHost(_ host: String) {
        connectedHosts[host] = Date()
    }

    public func sshConfigSnippet(host: String = "my-vps") -> String {
        """
        Host \(host)
            # HostName <your-vps-ip>
            # User <your-user>
            RemoteForward \(port) 127.0.0.1:\(port)
        """
    }

    public func sshCommandSnippet(user: String = "user", host: String = "vps-ip") -> String {
        "ssh -R \(port):127.0.0.1:\(port) \(user)@\(host)"
    }

    public func setupCommand() -> String {
        "curl -fsSL http://127.0.0.1:\(port)/setup.sh | bash -s -- --token \(authToken) --port \(port)"
    }

    private func save() {
        let d = UserDefaults.standard
        d.set(isEnabled, forKey: isEnabledKey)
        d.set(port, forKey: portKey)
        d.set(authToken, forKey: tokenKey)
        AppDaemon.shared.restartRemoteServer()
    }
}
