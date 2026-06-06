import AppKit
import SwiftUI
import AgentPetCore

/// Owns the menu bar status item and a native `NSPopover` (the pattern used by
/// polished menu bar apps): smooth open/close animation, a real arrow pointing
/// at the icon, and transient auto-dismiss on outside clicks.
@MainActor
final class StatusBarController: NSObject, ObservableObject {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var lastSessions: [AgentSession] = []

    /// Whether to show the agent count next to the menu bar icon.
    @Published var showCount: Bool {
        didSet {
            UserDefaults.standard.set(showCount, forKey: "agentpet.showCount")
            updateStatus(lastSessions)
        }
    }
    /// Whether to show the pet's chat line next to the menu bar icon (default off).
    @Published var showChatOnMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showChatOnMenuBar, forKey: "agentpet.showChatMenuBar")
            updateStatus(lastSessions)
        }
    }
    /// Whether to show the agent bubble (same as the floating pet) hanging below
    /// the menu bar icon.
    @Published var showBubbleOnMenuBar: Bool {
        didSet {
            UserDefaults.standard.set(showBubbleOnMenuBar, forKey: "agentpet.showBubbleMenuBar")
            refreshAgentBubble()
        }
    }

    override init() {
        showCount = (UserDefaults.standard.object(forKey: "agentpet.showCount") as? Bool) ?? true
        showChatOnMenuBar = (UserDefaults.standard.object(forKey: "agentpet.showChatMenuBar") as? Bool) ?? false
        showBubbleOnMenuBar = (UserDefaults.standard.object(forKey: "agentpet.showBubbleMenuBar") as? Bool) ?? false
        super.init()
    }

    /// Recomputes the menu bar title (called when the chat line changes).
    func refreshTitle() { updateStatus(lastSessions) }

    func start() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = Self.menuBarImage(count: nil, waiting: false)
        item.button?.imagePosition = .imageLeading
        item.button?.target = self
        item.button?.action = #selector(toggle)
        statusItem = item

        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingController(rootView: MenuContentView(dismiss: { [weak self] in
            self?.popover.performClose(nil)
        }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
    }

    /// Closes the popover when the user clicks anywhere outside it (including
    /// other apps / the desktop), which a transient popover can miss for a
    /// non-activating menu bar app.
    private var outsideClickMonitor: Any?

    @objc private func toggle() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    /// Reflects live agent state in the menu bar: a count of running agents, or
    /// an orange count when some need input, so it reads at a glance.
    func updateStatus(_ sessions: [AgentSession]) {
        lastSessions = sessions
        guard let button = statusItem?.button else { return }
        let active = sessions.filter { $0.state != .idle }
        let waiting = active.filter { $0.state == .waiting }.count
        // `registered` (agent open but idle) doesn't count as running, so just
        // opening an agent doesn't inflate the menu bar count.
        let running = active.filter { $0.state == .working }.count

        let hasAgents = waiting > 0 || running > 0

        button.title = ""
        if showCount, hasAgents {
            let count = waiting > 0 ? waiting : running
            button.image = Self.menuBarImage(count: count, waiting: waiting > 0)
        } else {
            button.image = Self.menuBarImage(count: nil, waiting: false)
        }

        refreshChatBubble()
        refreshAgentBubble()
    }

    /// Builds the menu bar image: the paw alone, or the paw plus a count laid out
    /// as a centered row (both centered vertically by their bounding boxes, so the
    /// digit never sits high or low relative to the icon).
    private static func menuBarImage(count: Int?, waiting: Bool) -> NSImage? {
        guard let paw = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "AgentPet") else { return nil }

        guard let count else {
            paw.isTemplate = true
            return paw
        }

        let font = NSFont.systemFont(ofSize: 13, weight: .bold)
        let text = "\(count)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let textSize = text.size(withAttributes: attrs)
        let pawSize = paw.size
        let gap: CGFloat = 3
        let w = ceil(pawSize.width + gap + textSize.width)
        let h = ceil(max(pawSize.height, textSize.height))

        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        paw.draw(in: NSRect(x: 0, y: (h - pawSize.height) / 2, width: pawSize.width, height: pawSize.height))
        text.draw(at: NSPoint(x: pawSize.width + gap, y: (h - textSize.height) / 2), withAttributes: attrs)
        if waiting {
            NSColor.systemOrange.set()
            NSRect(x: 0, y: 0, width: w, height: h).fill(using: .sourceAtop)
        }
        img.unlockFocus()
        img.isTemplate = !waiting
        return img
    }

    // MARK: - Chat bubble dropping from the menu bar

    private var chatPanel: NSPanel?
    private var chatHideTimer: Timer?
    private var lastShownChat = ""

    private func refreshChatBubble() {
        let chat = PetController.shared.chatLine
        guard showChatOnMenuBar, !chat.isEmpty else {
            hideChatBubble()
            return
        }
        guard chat != lastShownChat else { return }
        lastShownChat = chat
        showChatBubble(chat)
    }

    private func showChatBubble(_ text: String) {
        guard let button = statusItem?.button, let buttonWindow = button.window else { return }

        let host = NSHostingView(rootView: MenuBarChatBubble(text: text))
        host.setFrameSize(host.fittingSize)
        let size = host.fittingSize

        let panel = chatPanel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.level = .popUpMenu
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = false
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            chatPanel = p
            return p
        }()
        panel.contentView = host
        panel.setContentSize(size)

        let frame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = frame.midX - size.width / 2
        panel.setFrameOrigin(NSPoint(x: originX, y: frame.minY - size.height + 2))
        panel.orderFrontRegardless()

        chatHideTimer?.invalidate()
        chatHideTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.hideChatBubble() }
        }
    }

    private func hideChatBubble() {
        chatHideTimer?.invalidate()
        chatPanel?.orderOut(nil)
        lastShownChat = ""
    }

    // MARK: - Agent bubble hanging from menu bar

    private var agentBubblePanel: NSPanel?
    /// Holds the hosting controller so SwiftUI's @ObservedObject subscriptions
    /// stay alive and the view auto-updates without recreating the panel.
    private var agentBubbleHost: NSHostingView<AnyView>?

    private func refreshAgentBubble() {
        guard showBubbleOnMenuBar, !popover.isShown else {
            hideAgentBubble()
            return
        }
        let sessions = PetController.shared.activeAgentSessions
        guard !sessions.isEmpty else {
            hideAgentBubble()
            return
        }
        positionAgentBubble()
    }

    private func positionAgentBubble() {
        guard let button = statusItem?.button,
              let buttonWindow = button.window else { return }

        // Create the panel and a self-updating SwiftUI view once; reuse forever.
        if agentBubblePanel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .popUpMenu
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // MenuBarBubbleView observes PetController directly so it refreshes
            // automatically whenever sessions change.
            let host = NSHostingView(rootView: AnyView(MenuBarBubbleView()))
            agentBubbleHost = host
            panel.contentView = host
            agentBubblePanel = panel
        }

        // Re-fit and reposition on every call (window could have moved).
        if let host = agentBubbleHost {
            host.setFrameSize(host.fittingSize)
        }
        let size = agentBubbleHost?.fittingSize ?? CGSize(width: 300, height: 60)
        agentBubblePanel?.setContentSize(size)

        let btnFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let originX = btnFrame.midX - size.width / 2
        let originY = btnFrame.minY - size.height - 4
        agentBubblePanel?.setFrameOrigin(NSPoint(x: originX, y: originY))
        agentBubblePanel?.orderFrontRegardless()
    }

    private func hideAgentBubble() {
        agentBubblePanel?.orderOut(nil)
    }

    /// Shows the same popover anchored to an arbitrary view (e.g. the floating
    /// pet on right-click).
    func showPopover(relativeTo rect: NSRect, of view: NSView, edge: NSRectEdge) {
        if popover.isShown { popover.performClose(nil) }
        popover.show(relativeTo: rect, of: view, preferredEdge: edge)
    }

    // MARK: - Deferred close actions

    /// Action to run once the popover finishes its close animation.
    /// Use this instead of `DispatchQueue.main.asyncAfter` so the action fires
    /// at the exact moment the popover delegate confirms it is closed.
    private var pendingCloseAction: (() -> Void)?

    /// Closes the popover and invokes `action` only after the close animation
    /// has fully completed (via `NSPopoverDelegate.popoverDidClose`).
    func closeAndThen(_ action: @escaping () -> Void) {
        pendingCloseAction = action
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Already closed — fire immediately.
            let pending = pendingCloseAction
            pendingCloseAction = nil
            pending?()
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidShow(_ notification: Notification) {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover.performClose(nil)
        }
        // Hide the bubble while the full popover is open — they'd overlap.
        hideAgentBubble()
    }

    func popoverDidClose(_ notification: Notification) {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        // Restore bubble after popover closes.
        refreshAgentBubble()
        // Fire any deferred action now that the close animation has finished.
        let pending = pendingCloseAction
        pendingCloseAction = nil
        pending?()
    }
}
