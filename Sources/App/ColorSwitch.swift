import SwiftUI

/// A custom switch drawn with explicit colors so its ON state always shows the
/// system accent, even in a non-key window (native switches desaturate when
/// their window is not key, which our non-activating panels never are).
struct ColorSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        // A Button (not a bare .onTapGesture) so taps register reliably inside a
        // grouped Form/List, where a tap gesture on a plain shape is often
        // swallowed by the row. Works in the popover too.
        Button {
            isOn.toggle()
        } label: {
            Capsule()
                .fill(isOn ? Color.systemAccent : Color(white: 0.42))
                .frame(width: 34, height: 18)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
                        .padding(2)
                }
                .animation(.easeInOut(duration: 0.18), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}
