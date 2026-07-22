import AppKit
import Foundation

/// Brings the terminal running a given agent session to the front. Terminal.app
/// and iTerm2 expose a per-tab/session `tty` over AppleScript, so we can focus
/// the *exact* window and tab. Warp has no scripting dictionary, so the best we
/// can do there is activate the app. Everything else falls back to activation.
enum TerminalFocus {
    /// osascript can block for a beat while the target app comes forward; keep it
    /// off the main thread so the bubble stays responsive.
    private static let queue = DispatchQueue(label: "agentpet.terminal-focus", qos: .userInitiated)

    /// Bundle id per `TERM_PROGRAM`, used to activate terminals we can't script.
    private static let bundleIDs: [String: String] = [
        "Apple_Terminal": "com.apple.Terminal",
        "iTerm.app": "com.googlecode.iterm2",
        "WarpTerminal": "dev.warp.Warp-Stable",
        "vscode": "com.microsoft.VSCode",
        "ghostty": "com.mitchellh.ghostty",
        "Hyper": "co.zeit.hyper",
        "Tabby": "org.tabby",
        "kitty": "net.kovidgoyal.kitty",
        "alacritty": "org.alacritty",
    ]

    static func focus(program: String?, tty: String?, focusURL: String? = nil) {
        guard let program else { return }
        queue.async {
            switch program {
            case "Apple_Terminal" where tty != nil:
                runScript(appleTerminalScript(tty: tty!))
            case "iTerm.app" where tty != nil:
                runScript(iTermScript(tty: tty!))
            default:
                // Warp has no tab scripting but exposes a warp:// deep link that
                // focuses the exact pane; open it. Otherwise just bring the app
                // to the front if we recognise its bundle id.
                if let focusURL, let url = URL(string: focusURL), url.scheme != nil {
                    NSWorkspace.shared.open(url)
                } else if let bid = bundleIDs[program] {
                    runScript("tell application id \"\(bid)\" to activate")
                }
            }
        }
    }

    private static func appleTerminalScript(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    try
                        if (tty of t) is "\(tty)" then
                            set selected of t to true
                            set frontmost of w to true
                            return
                        end if
                    end try
                end repeat
            end repeat
        end tell
        """
    }

    private static func iTermScript(tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            activate
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (tty of s) is "\(tty)" then
                                select w
                                select t
                                select s
                                return
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
        end tell
        """
    }

    private static func runScript(_ source: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        try? process.run()
    }
}
