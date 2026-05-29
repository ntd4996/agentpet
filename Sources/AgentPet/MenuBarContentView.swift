import SwiftUI
import AppKit

struct MenuBarContentView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AgentPet")
                .font(.headline)
            Text("No agents running")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Divider()

            Button("Quit AgentPet") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240, alignment: .leading)
    }
}
