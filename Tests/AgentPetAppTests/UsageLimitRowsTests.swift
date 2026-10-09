import XCTest
@testable import agentpet

/// Which providers get a row in the Limits sections (HUD and Care tab).
@MainActor
final class UsageLimitRowsTests: XCTestCase {

    private func provider(_ id: String, left: Double?) -> OpenUsageClient.Provider {
        OpenUsageClient.Provider(id: id, displayName: id, plan: nil, fractionLeft: left, todayLabel: nil)
    }

    /// A provider with only text lines has no limit, so it gets no row instead
    /// of a full red "100% used" bar.
    func testProviderWithoutLimitIsLeftOut() {
        let rows = NativeUsageProbe.combine(
            native: [provider("claude", left: 0.21)],
            openUsage: [provider("openrouter", left: nil), provider("grok", left: 1)])
        XCTAssertEqual(rows.map(\.id), ["claude", "grok"])
    }

    /// Native probes still win over OpenUsage for the same provider.
    func testNativeProviderWinsOverOpenUsage() {
        let rows = NativeUsageProbe.combine(
            native: [provider("claude", left: 0.21)],
            openUsage: [provider("claude", left: 0.9), provider("copilot", left: 1)])
        XCTAssertEqual(rows.map(\.id), ["claude", "copilot"])
        XCTAssertEqual(rows.first?.fractionLeft, 0.21)
    }
}
