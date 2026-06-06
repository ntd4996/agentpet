import Foundation
import AgentPetCore

/// Owns the live session state inside the running app: starts the socket
/// server, drains any queued events on launch, applies incoming events and
/// prunes stale ones, and publishes a display-ordered list to the UI.
///
/// All `SessionStore` access is confined to the main actor.
@MainActor
final class AppDaemon: ObservableObject {
    static let shared = AppDaemon()

    @Published private(set) var sessions: [AgentSession] = []

    private let store = SessionStore()
    private let server = EventSocketServer(path: AgentPetPaths.socketPath)
    private var pruneTimer: Timer?

    func start() {
        try? FileManager.default.createDirectory(
            atPath: AgentPetPaths.baseDir, withIntermediateDirectories: true
        )

        // Replay queued events with their original timestamps (not "now"), so
        // sessions that ended while the app was closed look stale and get
        // pruned immediately instead of resurrecting as "working".
        EventSocketServer.drainQueue(directory: AgentPetPaths.queueDir) { [store] event in
            store.apply(event, now: event.timestamp)
        }
        store.prune(now: Date())
        refresh()

        try? server.start { event in
            Task { @MainActor [weak self] in self?.ingest(event) }
        }

        pruneTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.prune() }
        }
    }

    /// Clears the tracked sessions (e.g. after disconnecting an integration).
    func clearSessions() {
        store.clear()
        refresh()
    }

    /// Dismisses a single session (e.g. a stuck agent).
    func removeSession(_ id: String) {
        store.remove(id: id)
        refresh()
    }

    private func ingest(_ event: AgentEvent) {
        let before = store.session(id: event.sessionId)?.state
        if let updated = store.apply(event, now: Date()) {
            notifyIfNeeded(before: before, session: updated)
            resolveTitle(for: event)
        }
        refresh()
    }

    private func resolveTitle(for event: AgentEvent) {
        let sessionId = event.sessionId
        let path: String? = event.transcriptPath
            ?? event.project.map { TranscriptReader.inferredPath(sessionId: sessionId, cwd: $0) }
        guard let path else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let title = TranscriptReader.title(at: path) else { return }
            await MainActor.run { [weak self] in
                self?.store.updateTitle(id: sessionId, title: title)
                self?.refresh()
            }
        }
    }

    private func notifyIfNeeded(before: AgentState?, session: AgentSession) {
        guard session.state != before else { return }
        let project = session.project.map { ($0 as NSString).lastPathComponent } ?? session.id
        switch session.state {
        case .waiting:
            NotificationManager.shared.notify(
                title: "\(project) needs input", body: session.message ?? "Waiting for you")
            SoundSettings.shared.play(.waiting)
        case .done:
            NotificationManager.shared.notify(
                title: "\(project) finished", body: "Agent completed its turn")
            SoundSettings.shared.play(.done)
        default:
            break
        }
    }

    private func prune() {
        store.prune(now: Date())
        refresh()
    }

    private func refresh() {
        sessions = store.sorted
        PetController.shared.update(sessions: sessions)
        StatusBarController.shared.updateStatus(sessions)
    }
}
