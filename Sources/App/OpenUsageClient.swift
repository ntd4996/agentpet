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
        /// Smallest "amount left" across the provider's progress lines, 0…1.
        let fractionLeft: Double?
        /// First text line, e.g. "$1.33 · 4.6M tokens".
        let todayLabel: String?
        /// When the tightest window resets, if known.
        var resetsAt: Date? = nil
        /// Label of the tightest window ("Session", "Weekly"), if known.
        var windowLabel: String? = nil
    }

    @Published private(set) var providers: [Provider] = []
    /// True when the last poll reached a running OpenUsage instance.
    @Published private(set) var available = false

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
        providers.compactMap(\.fractionLeft).min()
    }

    /// True when some subscription is nearly exhausted — makes the pet anxious.
    var limitLow: Bool {
        guard let left = lowestFractionLeft else { return false }
        return left < 0.15
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
                } else {
                    self.providers = []
                    self.available = false
                }
            }
        }
        task.resume()
    }

    nonisolated static func provider(from json: [String: Any]) -> Provider? {
        guard let id = json["providerId"] as? String else { return nil }
        let lines = json["lines"] as? [[String: Any]] ?? []

        var fractions: [Double] = []
        var todayLabel: String?
        var tightest: Double = 2  // track the window with the least left
        var resetsAt: Date?
        var windowLabel: String?
        for line in lines {
            switch line["type"] as? String {
            case "progress":
                guard let used = doubleValue(line["used"]),
                      let limit = doubleValue(line["limit"]), limit > 0 else { continue }
                let left = max(0, min(1, (limit - used) / limit))
                fractions.append(left)
                if left < tightest {
                    tightest = left
                    windowLabel = line["label"] as? String
                    resetsAt = resetDate(line["resetsAt"])
                }
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
            fractionLeft: fractions.min(),
            todayLabel: todayLabel,
            resetsAt: resetsAt,
            windowLabel: windowLabel
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
