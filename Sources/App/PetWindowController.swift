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
    private var chatLineCancellable: AnyCancellable?
    private var rightClickMonitor: Any?
    private var screenObserver: Any?
    private var moveObserver: Any?

    /// Screen position of the pet's bottom-center; kept stable across resizes.
    private var anchorBottomCenter: NSPoint?
    private var lastContentSize: CGSize = .zero
    private var resizeDebounce: DispatchWorkItem?

    func start() {
        let pet = PetController.shared.petPoint
        let size = CGSize(width: pet + 24, height: pet + 24)
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

        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncAnchorFromWindow() }
        }

        placeInitially(size: size)
        syncAnchorFromWindow()
        applyVisibility(isVisible)

        // On pet-size change, re-measure after SwiftUI relayouts.
        sizeCancellable = PetController.shared.$petPoint.sink { [weak self] _ in
            self?.remeasureContent()
        }

        // On agent rows added/removed, re-measure after SwiftUI relayouts.
        chatLineCancellable = PetController.shared.$chatLineCount.sink { [weak self] _ in
            self?.remeasureContent()
        }

        // If displays change (e.g. a monitor is unplugged), keep the pet on screen.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureOnScreen() }
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

    /// First-time placement: bottom-right of the main screen.
    private func placeInitially(size: CGSize) {
        guard let panel, let visible = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 24)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    /// Sizes the panel to hug the pet + bubble content.
    func resizeToContent(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }

        resizeDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.applyContentResize(size)
        }
        resizeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func applyContentResize(_ size: CGSize) {
        let padded = CGSize(width: size.width + 4, height: size.height + 4)
        let dw = abs(padded.width - lastContentSize.width)
        let dh = abs(padded.height - lastContentSize.height)
        guard dw > 1 || dh > 1 || lastContentSize == .zero else { return }
        lastContentSize = padded
        resizeInPlace(to: padded)
    }

    private func remeasureContent() {
        DispatchQueue.main.async { [weak self] in
            guard let host = self?.panel?.contentView as? NSHostingView<FloatingPetView> else { return }
            host.invalidateIntrinsicContentSize()
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            guard size.width > 0, size.height > 0 else { return }
            self?.resizeToContent(size)
        }
    }

    private func syncAnchorFromWindow() {
        guard let panel else { return }
        let frame = panel.frame
        anchorBottomCenter = NSPoint(x: frame.midX, y: frame.minY)
    }

    /// Resizes around a fixed bottom-center anchor so the pet doesn't drift.
    private func resizeInPlace(to size: CGSize) {
        guard let panel else { return }
        if anchorBottomCenter == nil { syncAnchorFromWindow() }
        guard let anchor = anchorBottomCenter else { return }

        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y)
        let probe = NSRect(origin: origin, size: size)
        if let visible = currentScreen(for: probe)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    /// Keeps the pet visible after a display configuration change: if its
    /// screen vanished (unplugged), move it onto the main screen.
    private func ensureOnScreen() {
        guard let panel else { return }
        let frame = panel.frame
        if currentScreen(for: frame) != nil { return }   // still on a live screen
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - frame.width - 16, y: visible.minY + 24)
        panel.setFrameOrigin(origin)
        syncAnchorFromWindow()
    }

    /// The screen whose frame contains the window's center, if any.
    private func currentScreen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { NSPointInRect(center, $0.frame) }
    }

    private func applyVisibility(_ visible: Bool) {
        if visible {
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }
}
