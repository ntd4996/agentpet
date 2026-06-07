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
    private var screenObserver: Any?

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

        placeInitially(size: size)
        applyVisibility(isVisible)

        // On size change, resize in place (keep the pet where the user put it).
        sizeCancellable = PetController.shared.$petPoint.sink { [weak self] point in
            self?.resizeInPlace(to: PetController.windowSize(forPoint: point))
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

        // Start wandering when the pet is visible and active.
        startWandering()
    }

    @Published private(set) var isMoving = false
    @Published private(set) var isResting = false
    @Published private(set) var direction: CGFloat = 1
    /// Random clip index cycled while idle so all spritesheet clips get used.
    @Published private(set) var idleClipIndex: Int = 0
    /// Active movement clip index randomized from movement clips.
    @Published private(set) var moveClipIndex: Int = 1
    /// The horizontal scale factor (1 or -1) to apply to the sprite when moving.
    @Published private(set) var moveScaleX: CGFloat = 1

    // MARK: - Wandering animation

    private enum WanderState { case idle, walking, resting }

    private var wanderState: WanderState = .idle
    private var wanderDirection: CGFloat = 1
    private var nextStateTime: Date = .init()
    private var stateTimer: Timer?
    private var moveTimer: Timer?
    private var animClipTimer: Timer?
    private static let moveInterval = 1.0 / 30.0

    private func startWandering() {
        nextStateTime = .init()
        // State transition: check every 0.5s whether to walk/idle/rest.
        stateTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.wanderStateTick() }
        }
        // Smooth movement at 30fps during walk phases.
        moveTimer = Timer.scheduledTimer(withTimeInterval: Self.moveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.moveTick() }
        }
        // Randomise the idle clip every few seconds so all animations are seen.
        animClipTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.randomizeIdleClip() }
        }
    }

    private func randomizeIdleClip() {
        guard !isMoving && !isResting else { return }
        guard let id = PetController.shared.selectedPetID,
              let pack = ImagePetStore.shared.pack(id: id) else { return }
        let allIndices = Array(0..<pack.clipCount)
        let idleIndices = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .inplace }
        if !idleIndices.isEmpty {
            idleClipIndex = idleIndices.randomElement() ?? 0
        } else {
            idleClipIndex = Int.random(in: 0..<pack.clipCount)
        }
    }

    private func updateMoveClip(for physicalDir: CGFloat) {
        guard let id = PetController.shared.selectedPetID,
              let pack = ImagePetStore.shared.pack(id: id) else { return }
        
        let allIndices = Array(0..<pack.clipCount)
        
        if physicalDir > 0 {
            // Moving Right
            let runRight = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .runRight }
            let rightAutoFlip = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .runRightAutoFlip }
            let leftAutoFlip = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .runLeftAutoFlip }
            
            if let chosen = (runRight + rightAutoFlip).randomElement() {
                moveClipIndex = chosen
                moveScaleX = 1
            } else if let chosen = leftAutoFlip.randomElement() {
                moveClipIndex = chosen
                moveScaleX = -1 // Flip left-facing artwork to face right
            } else {
                // Default fallback: use clip 1, auto-flip based on direction
                moveClipIndex = min(1, max(pack.clipCount - 1, 0))
                moveScaleX = 1
            }
        } else {
            // Moving Left
            let runLeft = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .runLeft }
            let leftAutoFlip = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .runLeftAutoFlip }
            let rightAutoFlip = allIndices.filter { PetBindingsStore.shared.category(packId: pack.id, clipIndex: $0) == .runRightAutoFlip }
            
            if let chosen = (runLeft + leftAutoFlip).randomElement() {
                moveClipIndex = chosen
                moveScaleX = 1
            } else if let chosen = rightAutoFlip.randomElement() {
                moveClipIndex = chosen
                moveScaleX = -1 // Flip right-facing artwork to face left
            } else {
                // Default fallback: use clip 1, auto-flip based on direction
                moveClipIndex = min(1, max(pack.clipCount - 1, 0))
                moveScaleX = -1
            }
        }
    }

    private func wanderStateTick() {
        let mood = PetController.shared.mood

        // If mood is not idle, we should not rest.
        if mood != .idle {
            isResting = false
        }

        // Working mood: stand still and play the custom working animation.
        if mood == .working {
            if wanderState != .idle {
                wanderState = .idle
                isMoving = false
                nextStateTime = .distantFuture
            }
            return
        }

        // Non-working: normal idle/walk state machine.
        guard PetController.shared.selectedPetID != nil else { return }

        // Re-entry after a working phase: pause briefly before wandering.
        if nextStateTime == .distantFuture {
            nextStateTime = Date().addingTimeInterval(1.0)
            wanderState = .idle
            isMoving = false
            isResting = false
            return
        }

        guard Date() >= nextStateTime else { return }

        switch wanderState {
        case .idle:
            // Transition from idle: 60% chance to walk, 40% chance to rest
            if Double.random(in: 0...1) < 0.6 {
                wanderState = .walking
                isMoving = true
                isResting = false
                if Double.random(in: 0...1) < 0.3 { wanderDirection *= -1 }
                direction = wanderDirection > 0 ? 1 : -1
                nextStateTime = Date().addingTimeInterval(Double.random(in: 3.0...6.0))
                updateMoveClip(for: direction)
            } else {
                wanderState = .resting
                isMoving = false
                isResting = true
                nextStateTime = Date().addingTimeInterval(Double.random(in: 6.0...15.0))
            }
        case .walking:
            // Transition from walking: 50% chance to rest, 50% chance to idle
            if Double.random(in: 0...1) < 0.5 {
                wanderState = .resting
                isMoving = false
                isResting = true
                nextStateTime = Date().addingTimeInterval(Double.random(in: 6.0...15.0))
            } else {
                wanderState = .idle
                isMoving = false
                isResting = false
                nextStateTime = Date().addingTimeInterval(Double.random(in: 4.0...10.0))
            }
        case .resting:
            // Transition from resting: 60% chance to walk, 40% chance to idle
            if Double.random(in: 0...1) < 0.6 {
                wanderState = .walking
                isMoving = true
                isResting = false
                if Double.random(in: 0...1) < 0.3 { wanderDirection *= -1 }
                direction = wanderDirection > 0 ? 1 : -1
                nextStateTime = Date().addingTimeInterval(Double.random(in: 3.0...6.0))
                updateMoveClip(for: direction)
            } else {
                wanderState = .idle
                isMoving = false
                isResting = false
                nextStateTime = Date().addingTimeInterval(Double.random(in: 4.0...10.0))
            }
        }
    }

    private func moveTick() {
        guard wanderState == .walking,
              let panel,
              let screen = currentScreen(for: panel.frame)?.visibleFrame
        else { return }

        let speed: CGFloat = 3.0
        var newX = panel.frame.minX + wanderDirection * speed
        let margin: CGFloat = 16
        let minX = screen.minX + margin
        let maxX = screen.maxX - panel.frame.width - margin

        // Hit wall → bounce off the wall and continue moving.
        if newX < minX {
            newX = minX
            wanderDirection = 1
            direction = 1
            updateMoveClip(for: 1)
        } else if newX > maxX {
            newX = maxX
            wanderDirection = -1
            direction = -1
            updateMoveClip(for: -1)
        }

        panel.setFrameOrigin(NSPoint(x: newX, y: panel.frame.minY))
    }

    /// First-time placement: bottom-right of the main screen.
    private func placeInitially(size: CGSize) {
        guard let panel, let visible = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(x: visible.maxX - size.width - 16, y: visible.minY + 24)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    /// Resizes around the pet's bottom-center so it stays where the user
    /// dragged it, clamped to whichever screen it currently sits on.
    private func resizeInPlace(to size: CGSize) {
        guard let panel else { return }
        let old = panel.frame
        var origin = NSPoint(x: old.midX - size.width / 2, y: old.minY)
        if let visible = currentScreen(for: old)?.visibleFrame {
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
