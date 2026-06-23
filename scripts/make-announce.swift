import AppKit

// Premium announcement card (Droid + Pi), 1200x675 rendered at 2x.
let scale: CGFloat = 2
let W: CGFloat = 1200, H: CGFloat = 675
let px = NSSize(width: W * scale, height: H * scale)
let ROOT = "/Users/datnt/Project/datnt/agentpet"

let image = NSImage(size: px)
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.scaleBy(x: scale, y: scale)

func color(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> NSColor {
    NSColor(srgbRed: r, green: g, blue: b, alpha: a)
}

// Background gradient (navy -> indigo).
NSGradient(colors: [color(0.04, 0.05, 0.13), color(0.09, 0.07, 0.22), color(0.05, 0.06, 0.16)])?
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -55)
// Glows.
NSGradient(colors: [color(0.49, 0.36, 1.0, 0.34), .clear])?
    .draw(in: NSRect(x: W - 560, y: H - 420, width: 760, height: 760), relativeCenterPosition: .zero)
NSGradient(colors: [color(0.18, 0.83, 0.75, 0.20), .clear])?
    .draw(in: NSRect(x: -240, y: -260, width: 720, height: 720), relativeCenterPosition: .zero)

// Helper: draw text from the TOP (y measured from top edge).
func text(_ s: String, x: CGFloat, top: CGFloat, font: NSFont, color c: NSColor,
          width: CGFloat = 900, kern: CGFloat = 0) {
    let p = NSMutableParagraphStyle(); p.lineBreakMode = .byWordWrapping
    let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c, .paragraphStyle: p, .kern: kern]
    let attr = NSAttributedString(string: s, attributes: a)
    let h = attr.boundingRect(with: NSSize(width: width, height: 400), options: [.usesLineFragmentOrigin]).height
    attr.draw(with: NSRect(x: x, y: H - top - h, width: width, height: h), options: [.usesLineFragmentOrigin])
}

func rounded(_ font: CGFloat, _ w: NSFont.Weight = .bold) -> NSFont {
    NSFont(name: "Arial Rounded MT Bold", size: font) ?? NSFont.systemFont(ofSize: font, weight: w)
}
func sys(_ s: CGFloat, _ w: NSFont.Weight = .regular) -> NSFont { NSFont.systemFont(ofSize: s, weight: w) }
func mono(_ s: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: s, weight: .semibold) }

// App icon (logo.png) squircle.
if let logo = NSImage(contentsOfFile: "\(ROOT)/web/public/logo.png") {
    let r = NSRect(x: 80, y: H - 110, width: 56, height: 56)
    let clip = NSBezierPath(roundedRect: r, xRadius: 15, yRadius: 15); clip.addClip()
    logo.draw(in: r)
    NSGraphicsContext.current!.cgContext.resetClip()
}
text("AgentPet", x: 150, top: 56, font: rounded(30), color: .white)

// Pixel-ish update label.
text("UPDATE · MAC 1.7.1 · WIN 0.1.2", x: 82, top: 150, font: mono(15),
     color: color(0.45, 0.85, 0.95), kern: 2)

// Headline.
text("Now tracking", x: 78, top: 186, font: rounded(60), color: .white)
// Second line with an accent number.
text("11", x: 80, top: 256, font: rounded(60), color: color(0.40, 0.78, 1.0))
text("coding agents", x: 80 + 78, top: 256, font: rounded(60), color: .white)

text("Factory Droid and Pi just joined the family.", x: 82, top: 338,
     font: sys(23, .regular), color: color(0.66, 0.72, 0.86))

// Feature bullets.
struct Bullet { let c: NSColor; let title: String; let sub: String }
let bullets = [
    Bullet(c: color(0.28, 0.83, 0.75), title: "Factory Droid", sub: "Lifecycle hooks + waiting-for-review"),
    Bullet(c: color(0.49, 0.40, 1.0), title: "Pi (pi.dev)", sub: "Auto-installed session extension"),
    Bullet(c: color(0.98, 0.74, 0.36), title: "Live in v1.7.1", sub: "Update via Homebrew or the in-app updater"),
]
var by: CGFloat = 408
for b in bullets {
    let dot = NSBezierPath(roundedRect: NSRect(x: 82, y: H - by - 30, width: 30, height: 30), xRadius: 9, yRadius: 9)
    b.c.withAlphaComponent(0.22).setFill(); dot.fill()
    b.c.setFill(); NSBezierPath(roundedRect: NSRect(x: 93, y: H - by - 19, width: 8, height: 8), xRadius: 4, yRadius: 4).fill()
    text(b.title, x: 128, top: by - 2, font: sys(20, .semibold), color: .white)
    text(b.sub, x: 128, top: by + 24, font: sys(16, .regular), color: color(0.60, 0.66, 0.80))
    by += 64
}

// OS pills.
func pill(_ s: String, x: CGFloat, top: CGFloat) -> CGFloat {
    let f = sys(17, .semibold)
    let w = (s as NSString).size(withAttributes: [.font: f]).width + 44
    let r = NSRect(x: x, y: H - top - 38, width: w, height: 38)
    color(1, 1, 1, 0.10).setFill(); NSBezierPath(roundedRect: r, xRadius: 19, yRadius: 19).fill()
    text(s, x: x + 22, top: top + 9, font: f, color: color(0.9, 0.92, 0.98))
    return x + w + 14
}
let nx = pill("macOS", x: 82, top: 610)
_ = pill("Windows", x: nx, top: 610)

// Right: a drawn "Connected agents" glass card, slightly tilted.
func textAt(_ s: String, x: CGFloat, baseline: CGFloat, font: NSFont, color c: NSColor, kern: CGFloat = 0) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .kern: kern])
        .draw(at: NSPoint(x: x, y: baseline))
}
func iconImage(_ name: String) -> NSImage? {
    NSImage(contentsOfFile: "\(ROOT)/web/public/agent-icons/\(name).svg")
}

do {
    let cw: CGFloat = 392, ch: CGFloat = 566
    let cx: CGFloat = 950, cy = H / 2 - 4
    ctx.saveGState()
    ctx.translateBy(x: cx, y: cy)
    ctx.rotate(by: -5 * .pi / 180)

    // Card with shadow + glass fill.
    let shadow = NSShadow(); shadow.shadowColor = NSColor(white: 0, alpha: 0.5)
    shadow.shadowBlurRadius = 44; shadow.shadowOffset = NSSize(width: 0, height: -18); shadow.set()
    let frame = NSRect(x: -cw/2, y: -ch/2, width: cw, height: ch)
    let cardPath = NSBezierPath(roundedRect: frame, xRadius: 30, yRadius: 30)
    color(0.07, 0.09, 0.17, 0.96).setFill(); cardPath.fill()
    NSShadow().set() // clear shadow for inner content
    color(1, 1, 1, 0.12).setStroke(); cardPath.lineWidth = 1.5; cardPath.stroke()

    let left = -cw/2 + 30
    // Header.
    textAt("Connected agents", x: left, baseline: ch/2 - 64, font: rounded(27), color: .white)
    textAt("11 supported · 2 new this release", x: left, baseline: ch/2 - 92,
           font: sys(15, .regular), color: color(0.6, 0.66, 0.8))

    // Rows.
    struct Row { let icon: String; let name: String; let state: String; let isNew: Bool }
    let rows = [
        Row(icon: "claude-code", name: "Claude Code", state: "working", isNew: false),
        Row(icon: "codex", name: "Codex", state: "done", isNew: false),
        Row(icon: "cursor", name: "Cursor", state: "idle", isNew: false),
        Row(icon: "gemini", name: "Gemini CLI", state: "idle", isNew: false),
        Row(icon: "droid", name: "Factory Droid", state: "waiting", isNew: true),
        Row(icon: "pi", name: "Pi", state: "working", isNew: true),
    ]
    var ry = ch/2 - 132
    for r in rows {
        let rowH: CGFloat = 62
        let cellTop = ry - rowH + 14
        // Row background for the new ones.
        if r.isNew {
            let bg = NSBezierPath(roundedRect: NSRect(x: left - 12, y: cellTop, width: cw - 36, height: rowH - 12), xRadius: 14, yRadius: 14)
            color(0.18, 0.83, 0.75, 0.10).setFill(); bg.fill()
        }
        // Icon chip.
        let chip = NSRect(x: left, y: cellTop + 4, width: 42, height: 42)
        color(1, 1, 1, 0.95).setFill(); NSBezierPath(roundedRect: chip, xRadius: 12, yRadius: 12).fill()
        if let img = iconImage(r.icon) {
            img.draw(in: NSRect(x: chip.minX + 9, y: chip.minY + 9, width: 24, height: 24))
        }
        // Name + state.
        textAt(r.name, x: left + 58, baseline: cellTop + 26, font: sys(19, .semibold), color: .white)
        // Status dot.
        let dotC = r.state == "working" ? color(0.30, 0.80, 0.45)
                 : r.state == "waiting" ? color(0.98, 0.70, 0.30)
                 : color(0.55, 0.60, 0.74)
        dotC.setFill(); NSBezierPath(ovalIn: NSRect(x: left + 58, y: cellTop + 6, width: 8, height: 8)).fill()
        textAt(r.state, x: left + 72, baseline: cellTop + 4, font: sys(13, .regular), color: color(0.62, 0.68, 0.82))
        // NEW pill.
        if r.isNew {
            let f = sys(12, .bold)
            let pw = ("NEW" as NSString).size(withAttributes: [.font: f]).width + 22
            let pr = NSRect(x: cw/2 - 30 - pw, y: cellTop + 12, width: pw, height: 24)
            color(0.18, 0.83, 0.75, 1).setFill(); NSBezierPath(roundedRect: pr, xRadius: 12, yRadius: 12).fill()
            textAt("NEW", x: pr.minX + 11, baseline: pr.minY + 7, font: f, color: color(0.03, 0.12, 0.12))
        }
        ry -= rowH
    }
    ctx.restoreGState()
}

// Footer URL.
text("agentpet.thenightwatcher.online", x: 82, top: 650, font: sys(16, .semibold),
     color: color(0.37, 0.89, 0.81))

image.unlockFocus()

guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: "/tmp/agentpet-announce.png"))
print("done")
