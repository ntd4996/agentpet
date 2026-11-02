import Foundation

/// Reads AI subscription usage from OpenUsage (openusage.ai) when it is
/// running: the app exposes a read-only local API on 127.0.0.1:6736. Entirely
/// optional — when OpenUsage isn't installed the poll fails silently and the
/// Care panel just shows how to get it.
@MainActor
final class OpenUsageClient: ObservableObject {
    static let shared = OpenUsageClient()

    struct Provider: Identifiable, Equatable {
        let id: String
        let displayName: String
        let plan: String?
        /// First text line, e.g. "$1.33 · 4.6M tokens".
        let todayLabel: String?
        /// Every limit window in provider order (e.g. 5h session, then weekly).
        var windows: [Window] = []

        /// The window with the least left (the first one on a tie).
        var tightest: Window? { windows.min { $0.fractionLeft < $1.fractionLeft } }
        /// Smallest "amount left" across the windows, 0…1.
        var fractionLeft: Double? { tightest?.fractionLeft }
        /// When the tightest window resets, if known.
        var resetsAt: Date? { tightest?.resetsAt }
        /// Label of the tightest window ("Session", "Weekly"), if known.
        var windowLabel: String? { tightest?.label }
    }

    /// One rate-limit window of a provider.
    struct Window: Equatable {
        let label: String
        /// Amount left, 0…1.
        let fractionLeft: Double
        var resetsAt: Date? = nil
        /// Window length in seconds (18000 for a 5h session), if known.
        var period: TimeInterval? = nil
    }

    @Published private(set) var providers: [Provider] = []
    /// True when the last poll reached a running OpenUsage instance.
    @Published private(set) var available = false
    /// True when OpenUsage answered earlier in this run but not on the latest
    /// poll, so the providers only it supplies have dropped out. In-memory on
    /// purpose: someone who never installed (or removed) OpenUsage is not nagged.
    @Published private(set) var lost = false
    private var everReached = false
    private var missedPolls = 0

    /// One slow answer (the request times out after 2s) must not raise the
    /// warning for a whole poll interval, so it takes two misses in a row.
    nonisolated static let missesBeforeLost = 2

    nonisolated static func isLost(missedPolls: Int, everSeen: Bool) -> Bool {
        everSeen && missedPolls >= missesBeforeLost
    }

    private var timer: Timer?
    private static let endpoint = URL(string: "http://127.0.0.1:6736/v1/usage")!
    private static let pollInterval: TimeInterval = 300

    func start() {
        guard timer == nil else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
    }

    /// The tightest remaining budget across all providers, 0…1.
    var lowestFractionLeft: Double? {
        UsageVisibility.shared.lowestFractionLeft(providers)
    }

    /// True when some visible subscription is nearly exhausted (pet anxious).
    var limitLow: Bool {
        UsageVisibility.shared.limitLow(providers)
    }

    func poll() {
        var request = URLRequest(url: Self.endpoint)
        request.timeoutInterval = 2
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            let parsed: [Provider]? = {
                guard let data,
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                else { return nil }
                return array.compactMap(Self.provider(from:))
            }()
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let parsed {
                    self.providers = parsed
                    self.available = true
                    self.everReached = true
                    self.missedPolls = 0
                } else {
                    self.providers = []
                    self.available = false
                    self.missedPolls += 1
                }
                self.lost = Self.isLost(missedPolls: self.missedPolls, everSeen: self.everReached)
            }
        }
        task.resume()
    }

    nonisolated static func provider(from json: [String: Any]) -> Provider? {
        guard let id = json["providerId"] as? String else { return nil }
        let lines = json["lines"] as? [[String: Any]] ?? []

        var todayLabel: String?
        var windows: [Window] = []
        for line in lines {
            switch line["type"] as? String {
            case "progress":
                guard let used = doubleValue(line["used"]),
                      let limit = doubleValue(line["limit"]), limit > 0 else { continue }
                windows.append(Window(
                    label: line["label"] as? String ?? "",
                    fractionLeft: max(0, min(1, (limit - used) / limit)),
                    resetsAt: resetDate(line["resetsAt"]),
                    period: doubleValue(line["periodDurationMs"]).map { $0 / 1000 }
                ))
            case "text":
                if todayLabel == nil { todayLabel = line["value"] as? String }
            default:
                break
            }
        }

        return Provider(
            id: id,
            displayName: json["displayName"] as? String ?? id.capitalized,
            plan: json["plan"] as? String,
            todayLabel: todayLabel,
            windows: windows
        )
    }

    nonisolated private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    /// A reset timestamp as providers send it: epoch seconds, or ISO 8601
    /// with or without fractional seconds ("…:59.536032+00:00", "….000Z").
    /// The default `ISO8601DateFormatter` rejects fractional seconds.
    nonisolated static func resetDate(_ any: Any?) -> Date? {
        if let secs = doubleValue(any) { return Date(timeIntervalSince1970: secs) }
        guard let text = any as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
