import XCTest
@testable import agentpet

/// Per-window limits and provider hiding.
@MainActor
final class UsageWindowsTests: XCTestCase {

    private func json(_ s: String) throws -> [String: Any] { try UsageTestSupport.json(s) }

    // MARK: - Every window is kept

    func testClaudeKeepsBothWindowsWithResets() throws {
        let body = try json("""
        {"five_hour": {"utilization": 37.0, "resets_at": "2026-10-02T23:59:59.536032+00:00"},
         "seven_day": {"utilization": 79.0, "resets_at": "2026-10-05T03:59:59.536051+00:00"}}
        """)
        let p = try XCTUnwrap(NativeUsageProbe.claudeProvider(from: body))
        XCTAssertEqual(p.windows.map(\.label), ["Session", "Weekly"])
        XCTAssertEqual(p.windows.map { LimitFormat.shortLabel($0) }, ["5h", "7d"])
        XCTAssertEqual(p.windows[0].fractionLeft, 0.63, accuracy: 0.001)
        XCTAssertEqual(p.windows[1].fractionLeft, 0.21, accuracy: 0.001)
        XCTAssertNotNil(p.windows[0].resetsAt)
        XCTAssertNotNil(p.windows[1].resetsAt)
        // The summary fields still describe the tightest window.
        XCTAssertEqual(p.fractionLeft ?? -1, 0.21, accuracy: 0.001)
        XCTAssertEqual(p.windowLabel, "Weekly")
    }

    func testCodexKeepsBothWindowsWithPeriods() throws {
        let body = try json("""
        {"rate_limit": {
          "primary_window": {"used_percent": 16, "limit_window_seconds": 18000, "reset_at": 1790997688},
          "secondary_window": {"used_percent": 3, "limit_window_seconds": 604800, "reset_at": 1791584488}}}
        """)
        let p = try XCTUnwrap(NativeUsageProbe.codexProvider(from: body, now: Date()) { _ in nil })
        XCTAssertEqual(p.windows.map { LimitFormat.shortLabel($0) }, ["5h", "7d"])
        XCTAssertEqual(p.windows.compactMap(\.resetsAt).map(\.timeIntervalSince1970),
                       [1_790_997_688, 1_791_584_488])
    }

    func testOpenUsageKeepsEveryProgressLine() throws {
        let body = try json("""
        {"providerId": "antigravity", "plan": "Ultra", "lines": [
          {"type": "progress", "label": "Session", "used": 0, "limit": 100,
           "resetsAt": "2026-10-03T04:00:08.000Z", "periodDurationMs": 18000000},
          {"type": "progress", "label": "Weekly", "used": 9, "limit": 100,
           "resetsAt": "2026-10-07T02:26:05.000Z", "periodDurationMs": 604800000},
          {"type": "text", "label": "Last 30 Days", "value": "$7.96"}]}
        """)
        let p = try XCTUnwrap(OpenUsageClient.provider(from: body))
        XCTAssertEqual(p.windows.map(\.label), ["Session", "Weekly"])
        XCTAssertEqual(p.windows.map { LimitFormat.shortLabel($0) }, ["5h", "7d"])
        XCTAssertEqual(p.windows.compactMap(\.resetsAt).count, 2)
    }

    // MARK: - Labels

    func testWindowTitle() {
        let session = OpenUsageClient.Window(label: "Session", fractionLeft: 1, period: 18000)
        let weekly = OpenUsageClient.Window(label: "Weekly limit", fractionLeft: 1, period: nil)
        let bare = OpenUsageClient.Window(label: "", fractionLeft: 1, period: 604800)
        XCTAssertEqual(LimitFormat.title(session), "Session · 5h")
        XCTAssertEqual(LimitFormat.title(weekly), "Weekly limit")
        XCTAssertEqual(LimitFormat.title(bare), "7d")
    }

    func testShortWindowsAndEmptyLabels() {
        let tenMin = OpenUsageClient.Window(label: "Burst", fractionLeft: 1, period: 600)
        XCTAssertEqual(LimitFormat.shortLabel(tenMin), "10m")
        XCTAssertEqual(LimitFormat.title(tenMin), "Burst · 10m")
        let blank = OpenUsageClient.Window(label: "", fractionLeft: 1, period: nil)
        XCTAssertFalse(LimitFormat.title(blank).isEmpty)
    }

    func testResetClockTodayThisWeekAndLater() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        let locale = Locale(identifier: "en_GB")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T06:00:00+07:00"))
        let today = now.addingTimeInterval(3 * 3600)          // Sat 09:00
        let monday = now.addingTimeInterval(2 * 86400 + 3600) // Mon 07:00
        let later = now.addingTimeInterval(29 * 86400)        // Nov 1
        XCTAssertEqual(LimitFormat.clock(today, now: now, calendar: cal, locale: locale), "09:00")
        XCTAssertEqual(LimitFormat.clock(monday, now: now, calendar: cal, locale: locale), "Mon 07:00")
        XCTAssertEqual(LimitFormat.clock(later, now: now, calendar: cal, locale: locale), "1 Nov")
    }

    /// The formatter is built once per template, locale and time zone, not once
    /// per row per render.
    func testClockReusesFormatterPerTemplateLocaleAndZone() throws {
        var hcm = Calendar(identifier: .gregorian)
        hcm.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Ho_Chi_Minh"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let gb = Locale(identifier: "en_GB")
        let us = Locale(identifier: "en_US")

        let a = LimitFormat.formatter(template: "jmm", calendar: hcm, locale: gb)
        XCTAssertTrue(a === LimitFormat.formatter(template: "jmm", calendar: hcm, locale: gb))
        XCTAssertFalse(a === LimitFormat.formatter(template: "MMMd", calendar: hcm, locale: gb))
        XCTAssertFalse(a === LimitFormat.formatter(template: "jmm", calendar: hcm, locale: us))
        XCTAssertFalse(a === LimitFormat.formatter(template: "jmm", calendar: utc, locale: gb))

        // Reuse must not leak one zone's output into another.
        // 12:00 and 15:00 +07:00 are 05:00 and 08:00 UTC: the same day in both zones.
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-03T12:00:00+07:00"))
        let at = now.addingTimeInterval(3 * 3600)
        XCTAssertEqual(LimitFormat.clock(at, now: now, calendar: hcm, locale: gb), "15:00")
        XCTAssertEqual(LimitFormat.clock(at, now: now, calendar: utc, locale: gb), "08:00")
        XCTAssertEqual(LimitFormat.clock(at, now: now, calendar: hcm, locale: gb), "15:00")
    }

    func testResetTextNilWhenPastOrUnknown() {
        let now = Date()
        XCTAssertNil(LimitFormat.reset(nil, now: now))
        XCTAssertNil(LimitFormat.reset(now.addingTimeInterval(-60), now: now))
        XCTAssertNotNil(LimitFormat.reset(now.addingTimeInterval(3 * 3600 + 60), now: now))
        XCTAssertNil(LimitFormat.compactReset(nil, now: now))
        XCTAssertNil(LimitFormat.compactReset(now.addingTimeInterval(-60), now: now))
        XCTAssertEqual(LimitFormat.compactReset(now.addingTimeInterval(3600), now: now)?.hasPrefix("↻ "), true)
    }

    // MARK: - Hiding providers

    func testHiddenProvidersAreFilteredAndPersisted() throws {
        try UsageTestSupport.withCleanDefaults { defaults in
        let store = UsageVisibility(defaults: defaults)
        let providers = ["claude", "codex", "grok"].map { UsageTestSupport.provider($0, left: 0.5) }
        XCTAssertEqual(store.visible(providers).map(\.id), ["claude", "codex", "grok"])

        store.setVisible("grok", false)
        XCTAssertEqual(store.visible(providers).map(\.id), ["claude", "codex"])

        // A fresh store reads the same choice back.
        XCTAssertEqual(UsageVisibility(defaults: defaults).visible(providers).map(\.id), ["claude", "codex"])

        store.setVisible("grok", true)
        XCTAssertEqual(UsageVisibility(defaults: defaults).visible(providers).map(\.id), ["claude", "codex", "grok"])
        }
    }

    /// A nearly spent provider the user hid must not make the pet anxious
    /// (limitLow) or trigger the rate-limit bubble (lowestFractionLeft).
    func testHiddenProviderDoesNotDriveMoodOrBubble() throws {
        try UsageTestSupport.withCleanDefaults { defaults in
        let store = UsageVisibility(defaults: defaults)
        let providers = [UsageTestSupport.provider("claude", left: 0.6),
                         UsageTestSupport.provider("grok", left: 0.05)]
        XCTAssertTrue(store.limitLow(providers))
        XCTAssertEqual(store.lowestFractionLeft(providers) ?? -1, 0.05, accuracy: 0.0001)
        let engine = ReactiveEngine()
        XCTAssertNotNil(engine.evaluate(metric: .rateLimit, value: store.lowestFractionLeft(providers)))

        store.setVisible("grok", false)
        XCTAssertFalse(store.limitLow(providers))
        XCTAssertEqual(store.lowestFractionLeft(providers) ?? -1, 0.6, accuracy: 0.0001)
        XCTAssertNil(ReactiveEngine().evaluate(metric: .rateLimit, value: store.lowestFractionLeft(providers)))

        // Everything hidden: nothing to worry about.
        store.setVisible("claude", false)
        XCTAssertFalse(store.limitLow(providers))
        XCTAssertNil(store.lowestFractionLeft(providers))
        }
    }

    /// The summary fields come from the windows: the tightest one wins, and a
    /// provider with no limit (text/badge only) has none at all.
    func testSummaryFollowsTightestWindow() {
        let p = OpenUsageClient.Provider(id: "x", displayName: "X", plan: nil, todayLabel: nil, windows: [
            .init(label: "Session", fractionLeft: 0.9, resetsAt: Date(timeIntervalSince1970: 1)),
            .init(label: "Weekly", fractionLeft: 0.2, resetsAt: Date(timeIntervalSince1970: 2)),
        ])
        XCTAssertEqual(p.fractionLeft, 0.2)
        XCTAssertEqual(p.windowLabel, "Weekly")
        XCTAssertEqual(p.resetsAt, Date(timeIntervalSince1970: 2))
        let none = OpenUsageClient.Provider(id: "y", displayName: "Y", plan: nil, todayLabel: "$3")
        XCTAssertNil(none.fractionLeft)
        XCTAssertNil(none.windowLabel)
        XCTAssertNil(none.resetsAt)
    }
}
