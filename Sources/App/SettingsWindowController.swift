import AppKit
import SwiftUI

/// Owns the onboarding/Settings window, shown on first launch and reopenable
/// from the menu bar.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// True while a Settings or onboarding window is open (and therefore the
    /// app should keep its `.regular` activation policy / Dock icon). Other
    /// transient `.regular` switches (e.g. Sparkle's update UI) check this
    /// before dropping back to `.accessory`.
    var hasOpenWindow: Bool { window != nil || onboardingWindow != nil }

    func show() {
        SettingsModel.shared.refresh()

        // Always rebuild so the window opens fresh (default tab, scrolled to top)
        // instead of restoring the previous session's state.
        window?.close()
        window = nil

        // Show a Dock icon while Settings is open (requires .regular policy).
        NSApp.setActivationPolicy(.regular)

        let host = NSHostingView(rootView: SetupView(
            onClose: { [weak self] in self?.window?.close() },
            onResize: { [weak self] width in self?.resize(toContentWidth: width) }
        ))
        // A normal window (not NSPanel) so SwiftUI text fields reliably receive
        // keyboard input. Settings intentionally takes focus (shows a Dock icon).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "AgentPet"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        self.window = window

        // Present on the next runloop tick so it reliably comes to the front
        // after the popover closes and the activation policy change settles.
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        // When the user cmd-tabs back to AgentPet, surface Settings again
        // instead of leaving it buried behind other apps' windows.
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(appBecameActive),
            name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func appBecameActive() {
        window?.makeKeyAndOrderFront(nil)
    }

    /// Animates the Settings window to a target content width, keeping the
    /// top-left corner fixed so the live-preview panel slides out to the right.
    private func resize(toContentWidth target: CGFloat) {
        guard let window else { return }
        let curContent = window.contentRect(forFrameRect: window.frame).width
        guard abs(curContent - target) > 0.5 else { return }
        var f = window.frame
        f.size.width += (target - curContent)   // origin unchanged -> top-left stays put
        window.setFrame(f, display: true, animate: true)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow {
            UserDefaults.standard.set(true, forKey: "agentpet.hasOnboarded")
            onboardingWindow = nil
        } else {
            window = nil
        }
        // Back to a menu bar accessory (no Dock icon) when no window is open.
        if window == nil && onboardingWindow == nil {
            NSApp.setActivationPolicy(.accessory)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
        }
    }

    /// Shows the welcome/onboarding window the first time the app is launched.
    func showOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: "agentpet.hasOnboarded") else { return }
        showOnboarding()
    }

    private var onboardingWindow: NSWindow?

    func showOnboarding() {
        SettingsModel.shared.refresh()
        let host = NSHostingView(rootView: OnboardingView(onFinish: { [weak self] in
            self?.onboardingWindow?.close()
        }))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "Welcome to AgentPet"
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        onboardingWindow = window

        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }
}
