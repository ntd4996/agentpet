import AppKit
import SwiftUI

/// A multiline text editor with a capped height and built-in scroll support.
/// Grows up to `maxHeight` then scrolls internally, so the surrounding form never
/// gets pushed past a comfortable size.
struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var maxHeight: CGFloat = 200

    func makeNSView(context: Context) -> NSScrollView {
        let textView = AutoTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .preferredFont(forTextStyle: .callout)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 2

        let scroll = BoundedScrollView(maxHeight: maxHeight)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets()
        scroll.scrollerStyle = .overlay
        return scroll
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let view = scrollView.documentView as? NSTextView else { return }
        if view.string != text {
            view.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

/// NSTextView that reports its content height so the scroll view can size accordingly.
private final class AutoTextView: NSTextView {
    override var intrinsicContentSize: NSSize {
        guard let layoutManager, let textContainer else { return super.intrinsicContentSize }
        layoutManager.ensureLayout(for: textContainer)
        let height = layoutManager.usedRect(for: textContainer).height + textContainerInset.height * 2
        return NSSize(width: NSView.noIntrinsicMetric, height: max(height, 40))
    }

    override func didChangeText() {
        super.didChangeText()
        invalidateIntrinsicContentSize()
    }
}

/// NSScrollView that caps its height at `maxHeight` while letting its content
/// grow naturally. When the text overflows, the scroller appears.
private final class BoundedScrollView: NSScrollView {
    let maxHeight: CGFloat

    init(maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        guard let textView = documentView as? AutoTextView else { return super.intrinsicContentSize }
        let textSize = textView.intrinsicContentSize
        let clamped = min(textSize.height, maxHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: max(clamped, 44))
    }
}
