import AppKit
import SwiftUI
import Combine
import AgentPetCore

/// Owns the floating pet panels. A registry keyed by group key ("default" or a
/// project path): each entry is one borderless, always-on-top, draggable
/// `NSPanel` hosting a `FloatingPetView(model:)`. Single-pet mode is just N=1
/// (one "default" window); Split mode spawns one window per active project.
@MainActor
final class PetWindowController: ObservableObject {
    static let shared = PetWindowController()

    @Published var isVisible: Bool = true {
        didSet { applyVisibility(isVisible) }
    }

    /// One managed panel + its per-window model and observers/measurement state.
    private final class ManagedPetWindow {
        let panel: NSPanel
        let model: PetWindowModel
        var moveObserver: Any?
        var occlusionObserver: Any?

        /// Screen position of the pet's bottom-center; kept stable across resizes.
        var anchorBottomCenter: NSPoint?
        var lastContentSize: CGSize = .zero
        var resizeDebounce: DispatchWorkItem?
        /// Re-fits the window onto the pet's screen once a drag settles.
        var relayoutDebounce: DispatchWorkItem?

        init(panel: NSPanel, model: PetWindowModel) {
            self.panel = panel
            self.model = model
        }
    }

    /// All live pet panels, keyed by spec key.
    private var windows: [String: ManagedPetWindow] = [:]

    private var sizeCancellable: AnyCancellable?
    private var chatLineCancellable: AnyCancellable?
    private var rightClickMonitor: Any?
    private var screenObserver: Any?
    private var sleepObservers: [Any] = []
    /// True while displays sleep or the session is locked/switched away.
    private var screensAsleep = false

    private static let positionsKey = "agentpet.petPositions"

    func start() {
        // Create the default ("home") window up front so the pet appears at
        // launch, before the daemon's first session update arrives.
        _ = ensureWindow(for: PetWindowPlanner.defaultKey)
        applyVisibility(isVisible)

        // On pet-size change, re-measure every window after SwiftUI relayouts.
        sizeCancellable = PetController.shared.$petPoint.sink { [weak self] _ in
            self?.remeasureAll()
        }

        // On agent rows added/removed, re-measure after SwiftUI relayouts.
        chatLineCancellable = PetController.shared.$chatLineCount.sink { [weak self] _ in
            self?.remeasureAll()
        }

        // If displays change (e.g. a monitor is unplugged), keep every pet on screen.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.ensureAllOnScreen() }
        }

        // Pause animations while nobody can see the pets: displays asleep,
        // screen locked / fast user switch. Occlusion (covered, hidden) is
        // tracked per panel in `ensureWindow`.
        let ws = NSWorkspace.shared.notificationCenter
        let pauses: [(Notification.Name, Bool)] = [
            (NSWorkspace.screensDidSleepNotification, true),
            (NSWorkspace.screensDidWakeNotification, false),
            (NSWorkspace.sessionDidResignActiveNotification, true),
            (NSWorkspace.sessionDidBecomeActiveNotification, false),
        ]
        sleepObservers = pauses.map { name, asleep in
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.screensAsleep = asleep
                    for managed in self.windows.values { self.updateOnScreen(managed) }
                }
            }
        }

        // Right-click a pet to show ITS stats card (info only — controls stay in
        // the menu bar popover and Settings). Resolve which window via its panel.
        rightClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self,
                      let managed = self.windows.values.first(where: { event.window === $0.panel }),
                      let content = managed.panel.contentView else { return false }
                // Anchor to a full-height sliver at the pet's x: full height so
                // the popover sits entirely above the window and never overlaps
                // the pet, and centred on the pet (window centre + petOffset)
                // so the arrow points at it when the pet is offset inside a
                // window pushed back on screen. A shifted full-width rect would
                // be clipped to the view, moving the arrow only half as far.
                let b = content.bounds
                let anchor = NSRect(x: b.midX + managed.model.petOffset - 1, y: b.minY,
                                    width: 2, height: b.height)
                self.showStatsPopover(relativeTo: anchor, of: content, petID: managed.model.petID)
                return true
            }
            return handled ? nil : event
        }
    }

    // MARK: - Multi-window sync

    /// The per-window state the coordinator resolves for a spec: the displayed
    /// mood (may differ from `spec.mood` — e.g. a transient celebrate burst),
    /// the structured sessions for the bubble, the petID (after the missing-pet
    /// fallback), and the chat line. Built by `PetController` from the existing
    /// chat / celebrate logic.
    struct WindowState {
        var petID: String?
        var mood: PetMood
        var sessions: [AgentSession]
        var count: Int
        var chatLine: String
    }

    /// Reconciles the live panels with the planned specs. Existing keys update
    /// their model in place (no new panel); new keys create a panel; keys absent
    /// from `specs` are torn down. `stateFor` supplies the resolved per-window
    /// state for each spec (computed by the coordinator from the existing chat /
    /// celebrate logic).
    func sync(specs: [PetWindowSpec], stateFor: (PetWindowSpec) -> WindowState) {
        let wanted = Set(specs.map(\.key))

        // Tear down windows whose group disappeared.
        for key in windows.keys where !wanted.contains(key) {
            teardownWindow(forKey: key)
        }

        for (index, spec) in specs.enumerated() {
            let managed = windows[spec.key] ?? createWindow(
                key: spec.key, petID: spec.petID, mood: spec.mood,
                projectName: spec.projectName, count: spec.count, index: index)
            apply(stateFor(spec), to: managed.model)
            if isVisible { managed.panel.orderFrontRegardless() }
        }
    }

    /// Pushes resolved state into a window's model. Keeps the `key` (immutable)
    /// and only mutates the per-window published state.
    private func apply(_ state: WindowState, to model: PetWindowModel) {
        model.petID = state.petID
        model.mood = state.mood
        model.sessions = state.sessions
        model.count = state.count
        model.chatLine = state.chatLine
    }

    // MARK: - Window lifecycle

    /// Returns the window for `key`, creating a bare default-anchored one if absent.
    @discardableResult
    private func ensureWindow(for key: String) -> ManagedPetWindow {
        if let existing = windows[key] { return existing }
        return createWindow(key: key, petID: PetController.shared.selectedPetID,
                            mood: .idle, projectName: nil, count: 0, index: windows.count)
    }

    /// Builds a panel for a window key, positions it (saved position or
    /// auto-offset), wires its move observer, registers it, and seeds its model.
    /// The model's `sessions`/`chatLine` are filled immediately after by `sync`.
    @discardableResult
    private func createWindow(key: String, petID: String?, mood: PetMood,
                              projectName: String?, count: Int, index: Int) -> ManagedPetWindow {
        let pet = PetController.shared.petPoint
        let size = CGSize(width: pet + 24, height: pet + 24)
        let model = PetWindowModel(key: key, petID: petID, mood: mood,
                                   projectName: projectName, count: count)
        let panel = makePanel(size: size, model: model)
        let managed = ManagedPetWindow(panel: panel, model: model)
        windows[key] = managed

        // Save position whenever the user drags this specific panel. Capture the
        // Sendable `key` (not the non-Sendable `managed`) and re-resolve on the
        // main actor to satisfy Swift 6 concurrency.
        managed.moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self, key] _ in
            MainActor.assumeIsolated {
                guard let self, let managed = self.windows[key] else { return }
                self.syncAnchor(managed)
                self.savePosition(managed)
                self.scheduleRelayout(managed)
            }
        }
        managed.occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: panel, queue: .main
        ) { [weak self, key] _ in
            MainActor.assumeIsolated {
                guard let self, let managed = self.windows[key] else { return }
                self.updateOnScreen(managed)
            }
        }

        placeWindow(managed, size: size, index: index)
        syncAnchor(managed)
        return managed
    }

    /// Recomputes whether a pet can be seen; only publishes on change so
    /// SwiftUI is not invalidated by redundant occlusion callbacks.
    private func updateOnScreen(_ managed: ManagedPetWindow) {
        let visible = !screensAsleep && managed.panel.occlusionState.contains(.visible)
        if managed.model.isOnScreen != visible { managed.model.isOnScreen = visible }
    }

    /// Factory: a borderless, non-activating, floating, click-through panel.
    private func makePanel(size: CGSize, model: PetWindowModel) -> NSPanel {
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
        panel.contentView = ClickThroughHostingView(rootView: FloatingPetView(model: model))
        return panel
    }

    /// Loads a saved position for this window's key, else places it at the
    /// bottom-right anchor shifted left by `index` so windows don't stack.
    private func placeWindow(_ managed: ManagedPetWindow, size: CGSize, index: Int) {
        if let origin = savedPosition(forKey: managed.model.key) {
            // Clamp the restored position onto a live screen: a coordinate saved
            // on a larger/other display can land off-screen after a resolution or
            // monitor change, hiding the pet forever otherwise (issue #47).
            let clamped = clampedOntoScreen(origin, size: size)
            managed.panel.setFrame(NSRect(origin: clamped, size: size), display: true, animate: false)
            return
        }
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let step = PetController.shared.petPoint + 40
        let origin = NSPoint(
            x: visible.maxX - size.width - 16 - CGFloat(index) * step,
            y: visible.minY + 24
        )
        managed.panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
    }

    private func teardownWindow(forKey key: String) {
        guard let managed = windows.removeValue(forKey: key) else { return }
        managed.resizeDebounce?.cancel()
        managed.relayoutDebounce?.cancel()
        if let obs = managed.moveObserver { NotificationCenter.default.removeObserver(obs) }
        if let obs = managed.occlusionObserver { NotificationCenter.default.removeObserver(obs) }
        managed.panel.orderOut(nil)
    }

    // MARK: - Position persistence (agentpet.petPositions)

    private func loadPositions() -> [String: [Double]] {
        guard let data = UserDefaults.standard.data(forKey: Self.positionsKey),
              let decoded = try? JSONDecoder().decode([String: [Double]].self, from: data) else { return [:] }
        return decoded
    }

    private func savedPosition(forKey key: String) -> NSPoint? {
        guard let xy = loadPositions()[key], xy.count == 2 else { return nil }
        return NSPoint(x: xy[0], y: xy[1])
    }

    private func savePosition(_ managed: ManagedPetWindow) {
        // Store the origin a pet-centred window would have (undo the in-window
        // pet offset), so a relaunch restores the pet, not the shifted window.
        var origin = managed.panel.frame.origin
        origin.x += managed.model.petOffset
        var all = loadPositions()
        all[managed.model.key] = [Double(origin.x), Double(origin.y)]
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: Self.positionsKey)
        }
    }

    // MARK: - Drag to move (pet body)

    /// Current on-screen origin of a window, so a pet-body drag can anchor from it.
    func windowOrigin(forKey key: String) -> NSPoint? {
        windows[key]?.panel.frame.origin
    }

    /// Moves a window during a pet-body drag. `didMoveNotification` fires, which
    /// re-anchors and persists the position exactly like a window-background drag.
    func moveWindow(forKey key: String, to origin: NSPoint) {
        windows[key]?.panel.setFrameOrigin(origin)
    }

    // MARK: - Stats popover (per window)

    /// Transient stats-only popover anchored at the pet.
    private var statsPopover: NSPopover?

    /// Closes the stats popover (e.g. when its footer opens Settings).
    func closeStatsPopover() {
        statsPopover?.performClose(nil)
    }

    private func showStatsPopover(relativeTo rect: NSRect, of view: NSView, petID: String?) {
        if let shown = statsPopover, shown.isShown {
            shown.performClose(nil)
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PetStatsView(petID: petID))
        statsPopover = popover
        // Prefer above the pet; AppKit flips to below only if there's no room.
        // In a flipped content view "above" is the minY edge.
        popover.show(relativeTo: rect, of: view, preferredEdge: view.isFlipped ? .minY : .maxY)
        // The pet lives in a non-activating panel, so the popover opens without
        // key focus and the first click would just be "focus me". Activate the
        // app and make the popover window key so clicks land immediately.
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }

    // MARK: - Resize (per window)

    /// Sizes the panel hosting `key` to hug the pet + bubble content.
    func resizeToContent(_ size: CGSize, forKey key: String) {
        guard size.width > 0, size.height > 0, let managed = windows[key] else { return }
        ResizeMetrics.log("content", size)

        managed.resizeDebounce?.cancel()
        // Growing content is drawn clipped until the window catches up, so
        // widen/heighten right away (never shrinking in this step). The exact
        // fit, including any shrink, still waits for the debounce so a burst
        // of intermediate sizes (spring animations) doesn't jitter the window.
        let current = managed.panel.frame.size
        let target = Self.padded(size)
        if target.width > current.width + 1 || target.height > current.height + 1 {
            resizeIfChanged(managed, to: CGSize(width: max(target.width, current.width),
                                                height: max(target.height, current.height)))
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let managed = self.windows[key] else { return }
            self.resizeIfChanged(managed, to: Self.padded(size))
        }
        managed.resizeDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    /// Window size for measured content: a small margin on every side.
    private static func padded(_ content: CGSize) -> CGSize {
        CGSize(width: content.width + 4, height: content.height + 4)
    }

    /// Resizes to `padded` unless it is within 1pt of the last applied size.
    private func resizeIfChanged(_ managed: ManagedPetWindow, to padded: CGSize) {
        let dw = abs(padded.width - managed.lastContentSize.width)
        let dh = abs(padded.height - managed.lastContentSize.height)
        guard dw > 1 || dh > 1 || managed.lastContentSize == .zero else { return }
        managed.lastContentSize = padded
        resizeInPlace(managed, to: padded)
    }

    private func remeasureAll() {
        for managed in windows.values { remeasureContent(managed) }
    }

    private func remeasureContent(_ managed: ManagedPetWindow) {
        let key = managed.model.key
        DispatchQueue.main.async { [weak self] in
            guard let self, let managed = self.windows[key],
                  let host = managed.panel.contentView as? ClickThroughHostingView<FloatingPetView> else { return }
            host.invalidateIntrinsicContentSize()
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            guard size.width > 0, size.height > 0 else { return }
            self.resizeToContent(size, forKey: key)
        }
    }

    private func syncAnchor(_ managed: ManagedPetWindow) {
        let frame = managed.panel.frame
        managed.anchorBottomCenter = NSPoint(x: frame.midX + managed.model.petOffset, y: frame.minY)
    }

    /// Resizes around a fixed bottom-center anchor so the pet doesn't drift.
    /// The window is kept inside the visible frame of the pet's screen so a wide
    /// bubble never spills onto a neighbouring display; when that pushes the
    /// window sideways, the pet (and the bubble's tail) is offset inside the
    /// window by the same amount, so the pet itself stays put on screen.
    private func resizeInPlace(_ managed: ManagedPetWindow, to size: CGSize) {
        if managed.anchorBottomCenter == nil { syncAnchor(managed) }
        guard let anchor = managed.anchorBottomCenter else { return }

        var origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y)
        let probe = NSRect(origin: origin, size: size)
        // A pet dropped outside every screen still gets fitted, onto the
        // closest one, instead of being left off screen.
        let visible = (screen(containing: anchor, fallback: probe) ?? nearestScreen(to: anchor))?.visibleFrame
        var petOffset: CGFloat = 0
        if let visible {
            let petWidth = PetController.shared.petPoint
            let layout = PetWindowGeometry.horizontalLayout(
                anchorX: anchor.x, width: size.width, petWidth: petWidth,
                visibleMinX: visible.minX, visibleMaxX: visible.maxX)
            origin.x = layout.originX
            petOffset = layout.petOffset
        }
        // Y: keep the window between the screen's bottom (or the Dock) and the
        // menu bar, so a pet dragged past either edge comes back on release.
        // X stays as horizontalLayout placed it (the pet may sit offset inside).
        if let visible {
            origin.y = PetWindowGeometry.clampOrigin(origin, size: size, into: visible).y
        }
        // Publish the offset before moving: the didMove observer re-derives
        // the anchor from frame + petOffset.
        if managed.model.petOffset != petOffset || managed.model.windowWidth != size.width {
            managed.model.petOffset = petOffset
            managed.model.windowWidth = size.width
            // Flush the new offset into the hosting view now, so the window
            // move and the pet's counter-shift land in the same frame
            // (otherwise the pet flashes at the old spot for one frame).
            managed.panel.contentView?.layoutSubtreeIfNeeded()
        }
        managed.panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: false)
        ResizeMetrics.log("window", size)
    }

    /// After the user drags a pet (window or pet body), re-fit it onto the
    /// pet's screen once the mouse is released. Waiting for release keeps the
    /// pet-body drag math (start origin + mouse delta) consistent mid-drag.
    private func scheduleRelayout(_ managed: ManagedPetWindow) {
        managed.relayoutDebounce?.cancel()
        let key = managed.model.key
        let work = DispatchWorkItem { [weak self] in
            guard let self, let managed = self.windows[key] else { return }
            if NSEvent.pressedMouseButtons & 1 != 0 { self.scheduleRelayout(managed); return }
            let before = managed.panel.frame
            self.resizeInPlace(managed, to: before.size)
            if managed.panel.frame != before { self.savePosition(managed) }
        }
        managed.relayoutDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    /// The screen holding the pet's bottom-center (so a wide window is fitted
    /// to the display the pet is on), else the one holding the window center.
    private func screen(containing anchor: NSPoint, fallback frame: NSRect) -> NSScreen? {
        let p = NSPoint(x: anchor.x, y: anchor.y + 1)
        return NSScreen.screens.first { NSPointInRect(p, $0.frame) } ?? currentScreen(for: frame)
    }

    /// The screen whose visible area is closest to `point`.
    private func nearestScreen(to point: NSPoint) -> NSScreen? {
        let screens = NSScreen.screens
        return PetWindowGeometry.nearestRectIndex(to: point, in: screens.map(\.visibleFrame)).map { screens[$0] }
    }

    /// Keeps every pet visible after a display configuration change: if a pet's
    /// screen vanished (unplugged), move it onto the main screen.
    private func ensureAllOnScreen() {
        for managed in windows.values { ensureOnScreen(managed) }
    }

    private func ensureOnScreen(_ managed: ManagedPetWindow) {
        let frame = managed.panel.frame
        let clamped = clampedOntoScreen(frame.origin, size: frame.size)
        guard clamped != frame.origin else { return }   // already fully visible
        managed.panel.setFrameOrigin(clamped)
        syncAnchor(managed)
    }

    /// Clamps `origin` so a window of `size` sits fully inside the visible frame
    /// of the screen it's mostly on (or the main screen if it's off every screen).
    private func clampedOntoScreen(_ origin: NSPoint, size: CGSize) -> NSPoint {
        let frame = NSRect(origin: origin, size: size)
        let screen = currentScreen(for: frame) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return origin }
        return PetWindowGeometry.clampOrigin(origin, size: size, into: visible)
    }

    /// The screen whose frame contains the window's center, if any.
    private func currentScreen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { NSPointInRect(center, $0.frame) }
    }

    private func applyVisibility(_ visible: Bool) {
        for managed in windows.values {
            if visible {
                managed.panel.orderFrontRegardless()
            } else {
                managed.panel.orderOut(nil)
            }
        }
    }
}
