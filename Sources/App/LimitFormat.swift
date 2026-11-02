import Foundation

/// Text for one limit window: short label ("5h", "7d") and reset time.
enum LimitFormat {
    /// "5h" / "7d" / "30d" from the window length, else the provider's label.
    static func shortLabel(_ w: OpenUsageClient.Window) -> String {
        guard let p = w.period, p > 0 else { return w.label }
        if p < 3600 { return "\(max(1, Int((p / 60).rounded())))m" }
        let hours = Int((p / 3600).rounded())
        if hours < 24 { return "\(hours)h" }
        return "\(Int((p / 86400).rounded()))d"
    }

    /// "Session" + "5h" -> "Session · 5h"; drops the length when it adds nothing.
    static func title(_ w: OpenUsageClient.Window) -> String {
        let short = shortLabel(w)
        if w.label.isEmpty {
            return short.isEmpty ? NSLocalizedString("Limit", comment: "limit window with no label and no length") : short
        }
        if short == w.label { return w.label }
        return "\(w.label) · \(short)"
    }

    /// "resets in 3h" / "in 12m". Nil when the time is unknown or already past.
    static func relative(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let secs = date.timeIntervalSince(now)
        guard secs > 0 else { return nil }
        if secs >= 86400 { return String(format: NSLocalizedString("resets in %dd", comment: ""), Int(secs / 86400)) }
        if secs >= 3600 { return String(format: NSLocalizedString("resets in %dh", comment: ""), Int(secs / 3600)) }
        return String(format: NSLocalizedString("resets in %dm", comment: ""), max(1, Int(secs / 60)))
    }

    /// Wall-clock reset time: "14:30" today, "Mon 14:30" within a week,
    /// "Nov 1" further out.
    static func clock(_ date: Date, now: Date = Date(), calendar: Calendar = .current,
                      locale: Locale = .current) -> String {
        let secs = date.timeIntervalSince(now)
        let template: String
        if calendar.isDate(date, inSameDayAs: now) {
            template = "jmm"
        } else if secs < 6 * 86400 {
            template = "EEEjmm"
        } else {
            template = "MMMd"
        }
        return formatter(template: template, calendar: calendar, locale: locale).string(from: date)
    }

    /// One DateFormatter per template and locale/calendar/zone: building one is
    /// slow and this runs for every limit row on every render.
    // Guarded by formattersLock.
    nonisolated(unsafe) private static var formatters: [String: DateFormatter] = [:]
    private static let formattersLock = NSLock()

    static func formatter(template: String, calendar: Calendar, locale: Locale) -> DateFormatter {
        let key = [template, locale.identifier, "\(calendar.identifier)", calendar.timeZone.identifier].joined(separator: "|")
        formattersLock.lock()
        defer { formattersLock.unlock() }
        if let cached = formatters[key] { return cached }
        let f = DateFormatter()
        f.locale = locale
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(template)
        formatters[key] = f
        return f
    }

    /// "resets in 3h · 14:30". Nil when the time is unknown or already past.
    static func reset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date, let relative = relative(date, now: now) else { return nil }
        return "\(relative) · \(clock(date, now: now))"
    }

    /// "↻ 14:30" for tight spaces. Nil when unknown or already past.
    static func compactReset(_ date: Date?, now: Date = Date()) -> String? {
        guard let date, date > now else { return nil }
        return "↻ \(clock(date, now: now))"
    }
}
