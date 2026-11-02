import Foundation
import SwiftUI
import AgentPetCore

/// Custom display names for projects (issue: several sessions in one folder,
/// such as a home directory, all read the same in the bubble and the toast).
/// Persisted in UserDefaults as `projectId -> name`.
@MainActor
final class ProjectNameStore: ObservableObject {
    static let shared = ProjectNameStore()
    private static let key = "agentpet.projectNames"

    @Published private(set) var names: [String: String]

    init() {
        names = (UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String]) ?? [:]
    }

    /// Custom name, else the folder name. Use this wherever a project is shown.
    func label(for path: String) -> String {
        ProjectNames.label(for: path, names: names)
    }

    func customName(forID id: String) -> String {
        names[id] ?? ""
    }

    /// Blank clears the name. Keyed by project id so the settings list, which only
    /// knows ids from the usage store, can set it.
    func setName(_ name: String, forID id: String) {
        let clean = ProjectNames.clean(name)
        if clean.isEmpty { names.removeValue(forKey: id) } else { names[id] = clean }
        UserDefaults.standard.set(names, forKey: Self.key)
    }
}

/// Settings > Bubble > Project names: one text field per project AgentPet has
/// seen. Empty means the folder name.
struct ProjectNamesSection: View {
    @ObservedObject private var names = ProjectNameStore.shared
    @State private var projects: [(id: String, folder: String)] = []

    var body: some View {
        Section {
            if projects.isEmpty {
                Text("No projects seen yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(projects, id: \.id) { p in
                ProjectNameField(id: p.id, folder: p.folder)
            }
        } header: {
            Text("Project names")
        } footer: {
            Text("Projects used in the last 7 days. Show a friendlier name instead of the folder name in the bubble and notifications. Leave empty to use the folder name.")
        }
        .onAppear {
            var list = ProjectUsageStore.shared.knownProjects(alwaysInclude: Set(names.names.keys))
            // A named project whose usage rows aged out of the store has no folder
            // to show, so list it by its custom name; otherwise it could never be
            // cleared from here.
            let listed = Set(list.map(\.id))
            for (id, name) in names.names.sorted(by: { $0.value < $1.value }) where !listed.contains(id) {
                list.append((id: id, folder: name))
            }
            projects = list
        }
    }
}

private struct ProjectNameField: View {
    let id: String
    let folder: String
    @ObservedObject private var store = ProjectNameStore.shared
    @State private var text = ""

    var body: some View {
        TextField(folder, text: $text)
            .onAppear { text = store.customName(forID: id) }
            .onSubmit { store.setName(text, forID: id) }
            .onChange(of: text) { new in
                // Save as you type so closing the window never loses an edit.
                store.setName(new, forID: id)
            }
    }
}
