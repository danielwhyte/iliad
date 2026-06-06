import SwiftUI
import AppKit

// One thing to hang in the margin: a SwiftUI view anchored to a character's line.
struct MarginEntry {
    let anchor: Int       // character index whose line this sits beside
    let width: CGFloat
    let view: AnyView
    var cursor: NSCursor = .arrow
    var fullWidth: Bool = false   // span the whole column (e.g. a horizontal rule) instead of hanging in the margin
    var centerVertically: Bool = false   // icons (checkbox, link) center on the line; text bullets top-align
    var inlineGap: Bool = false   // sit in a reserved gap just before the anchor (mid-line link buttons)
    var pinLeft: Bool = false     // pin to the left margin via the line fragment (stable; ignores content glyphs)
}

// A horizontal rule that fills the reading column, vertically centered on its line.
struct HRLine: View {
    let color: Color
    var body: some View {
        Rectangle().fill(color).frame(height: 1).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Hosting view that claims its own cursor (e.g. the pointing hand for link buttons) via a cursor
// rect, which beats the text view's I-beam since it's a subview of the text view.
final class MarginHost: NSHostingView<AnyView> {
    var cursor: NSCursor = .arrow
    override func resetCursorRects() { addCursorRect(bounds, cursor: cursor) }
    // A .cursorUpdate tracking area reliably overrides the text view's I-beam while over this view.
    override func cursorUpdate(with event: NSEvent) { cursor.set() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.cursorUpdate, .activeAlways, .inVisibleRect], owner: self))
    }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); window?.invalidateCursorRects(for: self) }
    override func setFrameOrigin(_ newOrigin: NSPoint) { super.setFrameOrigin(newOrigin); window?.invalidateCursorRects(for: self) }
}

// A reusable left-margin gutter for the editor. It hangs small views (list bullets/numbers,
// link buttons, future task checkboxes) just left of the reading column, aligned to a line.
// `build` creates the views (call on content change); `reposition` only moves them (call on layout).
final class MarginGutter {
    weak var textView: NSTextView?
    private struct Hosted { let anchor: Int; let width: CGFloat; let host: NSView; let fullWidth: Bool; let centerV: Bool; let inlineGap: Bool; let pinLeft: Bool }
    private var hosted: [Hosted] = []

    func clear() { hosted.forEach { $0.host.removeFromSuperview() }; hosted = [] }

    func build(_ entries: [MarginEntry]) {
        clear()
        guard let tv = textView else { return }
        hosted = entries.map { e in
            let host = MarginHost(rootView: e.view)
            host.cursor = e.cursor
            host.translatesAutoresizingMaskIntoConstraints = true
            tv.addSubview(host)
            return Hosted(anchor: e.anchor, width: e.width, host: host, fullWidth: e.fullWidth, centerV: e.centerVertically, inlineGap: e.inlineGap, pinLeft: e.pinLeft)
        }
        reposition()
    }

    // Update only the frames from the current layout (cheap; safe to call every resize frame).
    // Pass ensureLayout:false when called from inside the text view's own layout pass (already laid out).
    func reposition(ensureLayout: Bool = true) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, !hosted.isEmpty else { return }
        if ensureLayout { lm.ensureLayout(for: tc) }
        let origin = tv.textContainerOrigin          // container -> text-view (document) coords
        let len = (tv.string as NSString).length
        var prevLineY = CGFloat.nan
        var stack: CGFloat = 0
        let columnW = tc.size.width
        for h in hosted {
            let loc = min(h.anchor, max(0, len - 1))
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: loc, length: 1), actualCharacterRange: nil)
            if h.fullWidth {
                // Span the whole column on its line (the rule centers itself within the line height).
                let frag = lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
                h.host.frame = NSRect(x: origin.x, y: origin.y + frag.minY, width: columnW, height: frag.height)
                continue
            }
            if h.pinLeft {
                // Pin to the left margin off the LINE fragment (not the content glyph), so editing the
                // line — which conceals/reveals markers on a deferred pass — can't make it drift.
                let lf = lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
                let viewH = max(h.host.fittingSize.height, 14)
                let y = origin.y + lf.minY + (h.centerV ? (lf.height - viewH) / 2 : 0)
                h.host.frame = NSRect(x: origin.x - h.width - 3, y: y, width: h.width, height: viewH)
                continue
            }
            let frag = lm.boundingRect(forGlyphRange: NSRange(location: gr.location, length: max(1, gr.length)), in: tc)
            let viewH = max(h.host.fittingSize.height, 14)
            // Body text sits at the TOP of the line box (interline spacing is below it), and the
            // marker uses the same font, so top-aligning the two makes their baselines match.
            // Icons (checkbox, link) center on the line instead, so they sit level with the text.
            let y = h.centerV ? origin.y + frag.minY + (frag.height - viewH) / 2 : origin.y + frag.minY
            if h.inlineGap {
                // Mid-line link button: sit in the reserved gap just before the link text (no stacking).
                h.host.frame = NSRect(x: origin.x + frag.minX - h.width - 3, y: y, width: h.width, height: viewH)
                continue
            }
            // Hang just left of the line's first glyph (frag.minX includes any nesting indent),
            // so nested items inset with their text. Multiple items on a line stack leftward.
            if abs(y - prevLineY) < 1 { stack += h.width + 4 } else { stack = 0; prevLineY = y }
            let x = origin.x + frag.minX - h.width - 10 - stack
            h.host.frame = NSRect(x: max(2, x), y: y, width: h.width, height: viewH)
        }
    }
}

// ---- margin element views ----

// A list bullet ("•") or ordered number ("1."), right-aligned toward the column edge,
// drawn in the same font/size/color as the body text.
struct MarginBullet: View {
    let label: String
    let color: Color
    let font: Font
    var body: some View {
        Text(label)
            .font(font)
            .foregroundColor(color)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

// A circular task checkbox; clicking flips the underlying `- [ ]` / `- [x]` in the Markdown.
struct MarginCheckbox: View {
    let checked: Bool
    let onColor: Color
    let offColor: Color
    let size: CGFloat
    let toggle: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: toggle) {
            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                .font(.system(size: size, weight: .regular))
                .foregroundColor(checked ? onColor : offColor.opacity(hover ? 1 : 0.7))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .buttonStyle(.plain)
        .help(checked ? "Mark incomplete" : "Mark complete")
        .onHover { hover = $0 }
    }
}

// A small button beside a line that contains a link; opens the URL.
struct MarginLinkButton: View {
    let url: URL
    let color: Color
    @State private var hover = false
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Image(systemName: "arrow.up.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(color)
                .frame(width: 18, height: 18)
                .background(Circle().fill(color.opacity(hover ? 0.22 : 0.12)))
        }
        .buttonStyle(.plain)
        .help(url.absoluteString)
        .onHover { hover = $0; if $0 { NSCursor.pointingHand.set() } }
    }
}
