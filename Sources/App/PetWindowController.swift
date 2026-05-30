import AppKit
import SwiftUI
import Combine

/// A borderless, always-on-top, draggable floating window that hosts the pet.
/// Visibility is user-toggleable; size follows the pet-size setting.
@MainActor
final class PetWindowController: ObservableObject {
    static let shared = PetWindowController()

    @Published var isVisible: Bool = true {
        didSet { applyVisibility(isVisible) }
    }

    private var panel: NSPanel?
    private var sizeCancellable: AnyCancellable?
    private var rightClickMonitor: Any?

    func start() {
        let size = PetController.shared.windowSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = ClickThroughHostingView(rootView: FloatingPetView())
        self.panel = panel

        applyFrame(size: size)
        applyVisibility(isVisible)

        sizeCancellable = PetController.shared.$petPoint.sink { [weak self] point in
            self?.applyFrame(size: PetController.windowSize(forPoint: point))
        }

        // Right-click the pet to open the popover anchored at the pet.
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let panel = self.panel, event.window === panel,
                      let content = panel.contentView else { return false }
                let petPoint = PetController.shared.petPoint
                let rect = NSRect(x: (content.bounds.width - petPoint) / 2, y: 0,
                                  width: petPoint, height: petPoint)
                StatusBarController.shared.showPopover(relativeTo: rect, of: content, edge: .maxY)
                return true
            }
            return handled ? nil : event
        }
    }

    /// Resizes and repositions the panel in a single frame change (no jump),
    /// keeping it anchored to the bottom-right of the main screen.
    private func applyFrame(size: CGSize) {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 24)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    private func applyVisibility(_ visible: Bool) {
        if visible {
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }
}
