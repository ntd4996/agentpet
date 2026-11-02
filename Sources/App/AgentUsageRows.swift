import SwiftUI
import AgentPetCore

/// "By agent": tokens today and this month per agent. Shared by the stats card
/// and the Care tab. Hidden when no agent has usage this month.
struct AgentUsageRows: View {
    /// The stats card is tight, so it shows the top few; the Care tab shows all.
    var limit: Int? = nil
    @ObservedObject private var store = ProjectUsageStore.shared

    var body: some View {
        let rows = store.byAgent()
        let shown = limit.map { Array(rows.prefix($0)) } ?? rows
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("By agent")
                        .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                        .foregroundStyle(.white.opacity(0.35))
                    Spacer()
                    Text("Today · Month")
                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.35))
                }
                ForEach(shown, id: \.agent) { a in
                    HStack {
                        Text(verbatim: AgentUsage.label(for: a.agent))
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.7))
                        Spacer()
                        Text(verbatim: CareFormat.agentUsage(a))
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
        }
    }
}

/// Care tab version of "By agent": same data in the system Form style.
struct AgentUsageSection: View {
    @ObservedObject private var store = ProjectUsageStore.shared

    var body: some View {
        let rows = store.byAgent()
        if !rows.isEmpty {
            Section {
                ForEach(rows, id: \.agent) { a in
                    LabeledContent(AgentUsage.label(for: a.agent)) {
                        Text(verbatim: CareFormat.agentUsage(a))
                    }
                }
            } header: {
                HStack {
                    Text("By agent")
                    Spacer()
                    Text("Today · Month").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
