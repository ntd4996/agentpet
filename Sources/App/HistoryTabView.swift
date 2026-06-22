import SwiftUI
import AgentPetCore

struct HistoryTabView: View {
    enum Filter: String, CaseIterable {
        case today = "Today"
        case week = "Past 7 Days"
        case month = "Past 30 Days"
    }

    @State private var filter: Filter = .today
    @State private var records: [SessionArchive] = []

    var body: some View {
        Form {
            Section {
                Picker("Period", selection: $filter) {
                    ForEach(Filter.allCases, id: \.self) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if records.isEmpty {
                Section {
                    Text("No sessions yet")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                }
            } else {
                Section {
                    SummaryBar(records: records)
                }
                ForEach(groupedByDay, id: \.0) { day, dayRecords in
                    Section(header: DaySectionHeader(date: day, count: dayRecords.count)) {
                        ForEach(dayRecords, id: \.sessionId) { record in
                            SessionRow(record: record)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task(id: filter) {
            await loadRecords()
        }
    }

    // MARK: - Helpers

    private var groupedByDay: [(Date, [SessionArchive])] {
        let cal = Calendar.current
        var dict: [Date: [SessionArchive]] = [:]
        for record in records {
            let day = cal.startOfDay(for: record.startedAt)
            dict[day, default: []].append(record)
        }
        return dict.keys
            .sorted(by: >)
            .map { day in (day, dict[day]!.sorted { $0.startedAt > $1.startedAt }) }
    }

    private func loadRecords() async {
        let store = SessionArchiveStore.shared
        let now = Date()
        let since: Date?
        switch filter {
        case .today:
            since = nil
        case .week:
            since = Calendar.current.date(byAdding: .day, value: -6, to: now)
        case .month:
            since = Calendar.current.date(byAdding: .day, value: -29, to: now)
        }
        let fetched: [SessionArchive]
        if let since {
            fetched = await Task.detached { store.allRecords(since: since) }.value
        } else {
            fetched = await Task.detached { store.records(for: now) }.value
        }
        records = fetched.sorted { $0.startedAt > $1.startedAt }
    }
}

// MARK: - Summary Bar

private struct SummaryBar: View {
    let records: [SessionArchive]

    private var totalDuration: TimeInterval { records.reduce(0) { $0 + $1.duration } }

    private var kindCounts: [(AgentKind, Int)] {
        var dict: [AgentKind: Int] = [:]
        for r in records { dict[r.agentKind, default: 0] += 1 }
        return dict.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Label("\(records.count) sessions", systemImage: "clock.arrow.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                Label(formatBarDuration(totalDuration), systemImage: "timer")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(kindCounts, id: \.0.rawValue) { kind, count in
                        KindChip(kind: kind, count: count)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct KindChip: View {
    let kind: AgentKind
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: sfSymbol(for: kind))
                .font(.system(size: 10))
            Text("\(kind.rawValue) ×\(count)")
                .font(.caption2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.systemAccent.opacity(0.15)))
        .foregroundStyle(Color.systemAccent)
    }
}

// MARK: - Section Header

private struct DaySectionHeader: View {
    let date: Date
    let count: Int

    var body: some View {
        HStack {
            Text(date, style: .date)
            Spacer()
            Text("\(count) session\(count == 1 ? "" : "s")")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

// MARK: - Row

private struct SessionRow: View {
    let record: SessionArchive

    private var displayTitle: String {
        if let t = record.title, !t.isEmpty { return t }
        if let m = record.message, !m.isEmpty { return String(m.prefix(50)) }
        return record.sessionId
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: sfSymbol(for: record.agentKind))
                .font(.system(size: 16))
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.systemAccent.opacity(0.12)))
                .foregroundStyle(Color.systemAccent)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                if let project = record.project, !project.isEmpty {
                    Text(project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(formatRowDuration(record.duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let tokens = record.tokenCount {
                    Text("\(tokens)t")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Helpers

private func formatBarDuration(_ interval: TimeInterval) -> String {
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}

private func formatRowDuration(_ interval: TimeInterval) -> String {
    let h = Int(interval) / 3600
    let m = (Int(interval) % 3600) / 60
    let s = Int(interval) % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

// MARK: - SF Symbol mapping

private func sfSymbol(for kind: AgentKind) -> String {
    switch kind {
    case .claude:      return "a.circle.fill"
    case .codex:       return "gearshape.fill"
    case .gemini:      return "sparkle"
    case .cursor:      return "cursorarrow"
    case .opencode:    return "chevron.left.forwardslash.chevron.right"
    case .windsurf:    return "wind"
    case .antigravity: return "arrow.up.circle.fill"
    case .copilot:     return "airplane"
    case .kiroCLI:     return "k.circle.fill"
    case .droid:       return "cpu.fill"
    case .pi:          return "pi"
    case .cli:         return "terminal.fill"
    case .unknown:     return "questionmark.circle"
    }
}
