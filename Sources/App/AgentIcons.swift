import AppKit
import SwiftUI
import AgentPetCore

/// Renders the real brand logo for each agent kind as an NSImage from embedded
/// SVG data. No external dependency or resource bundle — the SVG strings are
/// compiled into the binary. Falls back to an SF Symbol for unknown kinds.
///
/// `NSImage(data:)` does not recognise SVG from raw bytes; macOS needs a `.svg`
/// file URL to select the SVG renderer. Each icon is written to a temp file once
/// and cached in memory for all subsequent calls.
enum AgentIcons {

    // Cache is MainActor-isolated: all call sites are SwiftUI views on the main actor.
    @MainActor private static var cache: [AgentKind: NSImage] = [:]

    @MainActor
    static func image(for kind: AgentKind) -> NSImage? {
        if let hit = cache[kind] { return hit }
        guard let svg = svgString(for: kind),
              let data = svg.data(using: .utf8) else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agentpet-icon-\(kind.rawValue).svg")
        // Write and read are separate: a write failure must not fall through to
        // reading a stale file left by a previous run for a different kind.
        do { try data.write(to: url) } catch { return nil }
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[kind] = img
        return img
    }

    /// Pre-renders all brand SVG icons at launch so the first render frame is never blocked.
    @MainActor
    static func prewarm() {
        for kind in brandKinds { _ = image(for: kind) }
    }

    private static func svgString(for kind: AgentKind) -> String? {
        switch kind {
        case .claude:    return anthropicSVG
        case .cursor:    return cursorSVG
        case .codex:     return openaiSVG
        case .gemini:    return geminiSVG
        case .windsurf:  return windsurfSVG
        case .opencode:  return opencodeSVG
        case .antigravity, .cli, .unknown: return nil
        }
    }

    // MARK: - Embedded SVG strings (sourced from thesvg.org CDN, MIT codebase)

    /// Anthropic "A" wordmark — mono variant, 24×24 viewBox.
    private static let anthropicSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path fill="#CC785C" d="M17.3041 3.541h-3.6718l6.696 16.918H24Zm-10.6082 \
    0L0 20.459h3.7442l1.3693-3.5527h7.0052l1.3693 3.5528h3.7442L10.5363 \
    3.5409Zm-.3712 10.2232 2.2914-5.9456 2.2914 5.9456Z"/>
    </svg>
    """

    /// Cursor hexagonal logo — mono variant, 24×24 viewBox.
    private static let cursorSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path fill="#1A65E0" d="M11.503.131 1.891 5.678a.84.84 0 0 0-.42.726v11.188\
    c0 .3.162.575.42.724l9.609 5.55a1 1 0 0 0 .998 0l9.61-5.55a.84.84 0 0 0 \
    .42-.724V6.404a.84.84 0 0 0-.42-.726L12.497.131a1.01 1.01 0 0 0-.996 0M2.657 \
    6.338h18.55c.263 0 .43.287.297.515L12.23 22.918c-.062.107-.229.064-.229-.06V\
    12.335a.59.59 0 0 0-.295-.51l-9.11-5.257c-.109-.063-.064-.23.061-.23"/>
    </svg>
    """

    /// OpenAI gear logo — default variant, coloured green (Codex brand).
    private static let openaiSVG = """
    <svg viewBox="0 0 256 260" xmlns="http://www.w3.org/2000/svg">
      <path fill="#10A37F" d="M239.184 106.203a64.716 64.716 0 0 0-5.576-53.103C219.452 \
    28.459 191 15.784 163.213 21.74A65.586 65.586 0 0 0 52.096 45.22a64.716 64.716 \
    0 0 0-43.23 31.36c-14.31 24.602-11.061 55.634 8.033 76.74a64.665 64.665 0 0 0 \
    5.525 53.102c14.174 24.65 42.644 37.324 70.446 31.36a64.72 64.72 0 0 0 48.754 \
    21.744c28.481.025 53.714-18.361 62.414-45.481a64.767 64.767 0 0 0 43.229-31.36\
    c14.137-24.558 10.875-55.423-8.083-76.483Zm-97.56 136.338a48.397 48.397 0 0 \
    1-31.105-11.255l1.535-.87 51.67-29.825a8.595 8.595 0 0 0 4.247-7.367v-72.85\
    l21.845 12.636c.218.111.37.32.409.563v60.367c-.056 26.818-21.783 48.545-48.601 \
    48.601Zm-104.466-44.61a48.345 48.345 0 0 1-5.781-32.589l1.534.921 51.722 29.826\
    a8.339 8.339 0 0 0 8.441 0l63.181-36.425v25.221a.87.87 0 0 1-.358.665l-52.335 \
    30.184c-23.257 13.398-52.97 5.431-66.404-17.803ZM23.549 85.38a48.499 48.499 0 \
    0 1 25.58-21.333v61.39a8.288 8.288 0 0 0 4.195 7.316l62.874 36.272-21.845 \
    12.636a.819.819 0 0 1-.767 0L41.353 151.53c-23.211-13.454-31.171-43.144-17.804\
    -66.405v.256Zm179.466 41.695-63.08-36.63L161.73 77.86a.819.819 0 0 1 .768 \
    0l52.233 30.184a48.6 48.6 0 0 1-7.316 87.635v-61.391a8.544 8.544 0 0 \
    0-4.4-7.213Zm21.742-32.69-1.535-.922-51.619-30.081a8.39 8.39 0 0 0-8.492 \
    0L99.98 99.808V74.587a.716.716 0 0 1 .307-.665l52.233-30.133a48.652 48.652 \
    0 0 1 72.236 50.391v.205ZM88.061 139.097l-21.845-12.585a.87.87 0 0 \
    1-.41-.614V65.685a48.652 48.652 0 0 1 79.757-37.346l-1.535.87-51.67 \
    29.825a8.595 8.595 0 0 0-4.246 7.367l-.051 72.697Zm11.868-25.58 28.138-16.217\
     28.188 16.218v32.434l-28.086 16.218-28.188-16.218-.052-32.434Z"/>
    </svg>
    """

    /// Gemini 4-pointed star shape extracted from the official logo mask.
    private static let geminiSVG = """
    <svg viewBox="0 0 296 298" xmlns="http://www.w3.org/2000/svg">
      <path fill="#4285F4" d="M141.201 4.886c2.282-6.17 11.042-6.071 13.184.148\
    l5.985 17.37a184.004 184.004 0 0 0 111.257 113.049l19.304 6.997c6.143 2.227 \
    6.156 10.91.02 13.155l-19.35 7.082a184.001 184.001 0 0 0-109.495 109.385\
    l-7.573 20.629c-2.241 6.105-10.869 6.121-13.133.025l-7.908-21.296a184 184 \
    0 0 0-109.02-108.658l-19.698-7.239c-6.102-2.243-6.118-10.867-.025-13.132\
    l20.083-7.467A183.998 183.998 0 0 0 133.291 26.28l7.91-21.394Z"/>
    </svg>
    """

    /// Windsurf "N" logo — mono variant, 24×24 viewBox.
    private static let windsurfSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path fill="#06B6D4" d="M23.55 5.067c-1.2038-.002-2.1806.973-2.1806 \
    2.1765v4.8676c0 .972-.8035 1.7594-1.7597 1.7594-.568 0-1.1352-.286-1.4718\
    -.7659l-4.9713-7.1003c-.4125-.5896-1.0837-.941-1.8103-.941-1.1334 0-2.1533\
    .9635-2.1533 2.153v4.8957c0 .972-.7969 1.7594-1.7596 1.7594-.57 0-1.1363\
    -.286-1.4728-.7658L.4076 5.1598C.2822 4.9798 0 5.0688 0 5.2882v4.2452c0 \
    .2147.0656.4228.1884.599l5.4748 7.8183c.3234.462.8006.8052 1.3509.9298\
    1.3771.313 2.6446-.747 2.6446-2.0977v-4.893c0-.972.7875-1.7593 1.7596\
    -1.7593h.003a1.798 1.798 0 0 1 1.4718.7658l4.9723 7.0994c.4135.5905 1.05\
    .941 1.8093.941 1.1587 0 2.1515-.9645 2.1515-2.153v-4.8948c0-.972.7875\
    -1.7594 1.7596-1.7594h.194a.22.22 0 0 0 .2204-.2202v-4.622a.22.22 0 0 \
    0-.2203-.2203Z"/>
    </svg>
    """

    /// Opencode bracket logo — mono variant, 24×24 viewBox.
    private static let opencodeSVG = """
    <svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
      <path fill="#F97316" fill-rule="evenodd" d="M16 6H8v12h8V6zm4 16H4V2h16v20z"/>
    </svg>
    """
}

// MARK: - SwiftUI view

/// Shows the brand logo for the agent kind; thin wrapper over `ResolvedIconView`.
struct AgentIconView: View {
    let kind: AgentKind
    var size: CGFloat = 14

    var body: some View {
        ResolvedIconView(choice: .brandLogo(kind), size: size)
    }
}

// MARK: - AgentKind identifiable (needed for popover(item:))

extension AgentKind: Identifiable {
    public var id: String { rawValue }
}

// MARK: - Curated SF Symbols for the icon picker

extension AgentIcons {
    /// All AgentKind cases that have embedded SVG brand logos.
    static let brandKinds: [AgentKind] = [.claude, .cursor, .codex, .gemini, .windsurf, .opencode]

    /// 28 curated SF Symbol names shown in the icon picker.
    static let curatedSymbols: [String] = [
        // Code & Terminal
        "terminal", "chevron.left.forwardslash.chevron.right", "curlybraces", "cpu", "command",
        // AI & Magic
        "brain", "wand.and.stars", "sparkles", "bolt",
        // Workflow
        "arrow.triangle.2.circlepath", "checklist", "tray.and.arrow.down", "doc.text",
        // Network
        "antenna.radiowaves.left.and.right", "network", "wifi", "cloud",
        // Interface
        "gear", "slider.horizontal.3", "paintbrush", "theatermasks", "person.crop.circle",
        // Objects
        "desktopcomputer", "laptopcomputer", "keyboard", "hammer", "wrench.and.screwdriver",
        // Extra
        "eye", "hourglass",
    ]
}

// MARK: - ResolvedIconView

/// Renders an `IconChoice` — either a brand SVG logo or an SF Symbol.
struct ResolvedIconView: View {
    let choice: IconChoice
    var size: CGFloat = 14

    var body: some View {
        switch choice {
        case .brandLogo(let kind):
            if let img = AgentIcons.image(for: kind) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            } else {
                Image(systemName: fallback(for: kind))
                    .font(.system(size: size * 0.8, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
            }
        case .sfSymbol(let name):
            Image(systemName: name)
                .font(.system(size: size * 0.8, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
    }

    private func fallback(for kind: AgentKind) -> String {
        switch kind {
        case .cli:     return "terminal"
        case .unknown: return "questionmark.circle"
        default:       return "sparkle"
        }
    }
}
