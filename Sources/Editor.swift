import SwiftUI
import AppKit

// Hosting view for the inline diff pills that claims the arrow cursor over its bounds. As a
// direct subview of the text view, its cursor rect takes precedence over the text view's I-beam.
final class CursorHostingView<V: View>: NSHostingView<V> {
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

// An overlay that claims the arrow cursor over its bounds (so floating controls over the editor
// never inherit the text view's I-beam) while passing clicks through to the buttons beneath it.
// Uses both a cursor rect and a cursorUpdate tracking area so it survives click-driven re-renders.
struct ArrowCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) { v.window?.invalidateCursorRects(for: v) }
    final class V: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // clicks pass through to the buttons
        override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .cursorUpdate, .inVisibleRect], owner: self))
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.arrow.set() }
    }
}
extension View { func arrowCursorOverlay() -> some View { overlay(ArrowCursorOverlay()) } }

// A transparent overlay that forces the arrow (pointer) cursor over its bounds via an AppKit
// cursor rect, which the window maintains across clicks (unlike hover-based .set, which needs a move).
struct PointerCursor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { V() }
    func updateNSView(_ v: NSView, context: Context) { v.window?.invalidateCursorRects(for: v) }
    final class V: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // pass clicks through to the buttons
    }
}

// An icon button with an Apple-style hover state: a soft tinted capsule fill behind the glyph.
// Use inside a grouped bubble (each button highlights its own capsule region).
struct HoverIconButton: View {
    let icon: String
    var color: Color
    var faint: Color
    var size: CGFloat = 13
    var w: CGFloat = 30
    var h: CGFloat = 26
    var disabled: Bool = false
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold))
                .foregroundColor(disabled ? faint.opacity(0.5) : color)
                .frame(width: w, height: h)
                .background(Capsule().fill(color.opacity(hover && !disabled ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(help).disabled(disabled)
        .onHover { hover = $0 && !disabled; if $0 { NSCursor.arrow.set() } }
        .onContinuousHover { if case .active = $0 { NSCursor.arrow.set() } }
    }
}

// A standalone capsule pill button: the whole pill is the hover target and the tint fills it.
struct HoverPillButton: View {
    let icon: String
    var color: Color
    var faint: Color
    var paperEdge: Color
    var rule: Color
    var size: CGFloat = 13
    var w: CGFloat = 30
    var h: CGFloat = 26
    var disabled: Bool = false
    var help: String = ""
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: size, weight: .semibold))
                .foregroundColor(disabled ? faint.opacity(0.5) : color)
                .frame(width: w, height: h)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(Capsule().fill(hover && !disabled ? color.opacity(0.16) : paperEdge))
                .overlay(Capsule().stroke(rule, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain).help(help).disabled(disabled)
        .onHover { hover = $0 && !disabled; if $0 { NSCursor.arrow.set() } }
        .onContinuousHover { if case .active = $0 { NSCursor.arrow.set() } }
    }
}

// Floating per-change accept/reject pill, anchored to the first changed word in each block.
struct DiffPill: View {
    let pal: Pal
    let accept: () -> Void
    let reject: () -> Void
    var body: some View {
        HStack(spacing: 2) {
            HoverIconButton(icon: "checkmark", color: pal.cAccent, faint: pal.cInkFaint, size: 11, w: 24, h: 22, help: "Accept", action: accept)
            HoverIconButton(icon: "xmark", color: pal.cInkSoft, faint: pal.cInkFaint, size: 11, w: 24, h: 22, help: "Reject", action: reject)
        }
        .padding(.horizontal, 3).padding(.vertical, 2)
        .background(pal.cPaperEdge, in: Capsule())
        .overlay(Capsule().stroke(pal.cRule, lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 5, y: 1)
        .fixedSize()
    }
}

// Clip view that always keeps an integral (whole-pixel) width. A non-integral clip width breaks
// the "same width" contract with the text view and makes it creep/jump every time the scroll view
// resizes through fractional widths, which is exactly what the sidebar push animation does.
final class IntegralClipView: NSClipView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(NSSize(width: floor(newSize.width), height: newSize.height))
    }
    override var frame: NSRect {
        get { super.frame }
        set { var f = newValue; f.size.width = floor(f.size.width); super.frame = f }
    }
}

// Scroll view that can ignore AppKit's *programmatic* re-scroll (the "centered scroll to visible"
// that fires when the text inset changes during a resize). User trackpad/scroller scrolling goes
// through a different path and is unaffected, so suppressing this only kills the resize jolt.
final class StableScrollView: NSScrollView {
    var suppressAutoScroll = false
    override func scroll(_ clipView: NSClipView, to point: NSPoint) {
        if suppressAutoScroll { return }
        super.scroll(clipView, to: point)
    }
}

// A text view that keeps a fixed-width reading column, flexing the side padding
// down to a minimum, then letting the column go fluid (relative to the window).
final class ColumnTextView: NSTextView {
    var columnMeasure: CGFloat = 680
    var minPad: CGFloat = 24
    var topInset: CGFloat = 60
    private var unsuppressWork: DispatchWorkItem?

    // Block AppKit's auto re-scroll for a short burst around any width change (covers the whole
    // resize/animation and the settle just after the mouse is released), then re-enable it.
    private func holdScroll() {
        guard let sv = enclosingScrollView as? StableScrollView else { return }
        sv.suppressAutoScroll = true
        unsuppressWork?.cancel()
        let w = DispatchWorkItem { [weak sv] in sv?.suppressAutoScroll = false }
        unsuppressWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: w)
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        holdScroll()
    }
    override func viewDidEndLiveResize() {
        holdScroll()   // keep blocking through AppKit's end-of-resize "centered scroll"
        super.viewDidEndLiveResize()
    }

    override func layout() {
        let viewW = enclosingScrollView?.contentSize.width ?? bounds.width
        // The column is a FIXED width (rounded), centered by the inset. Wrapping depends only on the
        // container width, so holding it constant means words never re-wrap while the window stays wide;
        // it only shrinks once the window is too narrow to fit the full measure plus the minimum padding.
        let colW = min(columnMeasure, max(120, viewW - minPad * 2)).rounded()
        let side = max(0, (viewW - colW) / 2).rounded()
        let tc = textContainer
        let widthChanged = tc != nil && abs(tc!.size.width - colW) > 0.5
        let insetChanged = abs(textContainerInset.width - side) > 0.5 || textContainerInset.height != topInset
        guard widthChanged || insetChanged else { super.layout(); return }
        holdScroll()   // suppress the inset-change re-scroll for this resize burst
        let clip = enclosingScrollView?.contentView
        let savedY = clip?.bounds.origin.y ?? 0
        if let tc = tc, widthChanged { tc.size = NSSize(width: colW, height: tc.size.height) }
        if insetChanged { textContainerInset = NSSize(width: side, height: topInset) }
        super.layout()
        if let clip = clip, abs(clip.bounds.origin.y - savedY) > 0.5 {
            clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: savedY))
            enclosingScrollView?.reflectScrolledClipView(clip)
        }
    }

    // Keep the caret at the glyph's natural height, centered in the (taller) line.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        let loc = selectedRange().location
        let f: NSFont
        if let ts = textStorage, ts.length > 0, loc <= ts.length,
           let attr = ts.attribute(.font, at: min(loc, ts.length - 1), effectiveRange: nil) as? NSFont {
            f = attr
        } else {
            f = (typingAttributes[.font] as? NSFont) ?? font ?? NSFont.systemFont(ofSize: 14)
        }
        let glyphH = f.ascender - f.descender
        var r = rect
        if glyphH > 2, glyphH < rect.height {
            // Text sits at the top of the line box (extra space is interline spacing below),
            // so keep the caret over the glyphs instead of centering it in the taller box.
            r.size.height = glyphH
        }
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect, avoidAdditionalLayout flag: Bool) {
        // expand the invalidation a touch so the shorter caret clears cleanly
        super.setNeedsDisplay(invalidRect.insetBy(dx: -1, dy: -2), avoidAdditionalLayout: flag)
    }
}

// Live-Markdown NSTextView wrapped for SwiftUI.
struct EditorView: NSViewRepresentable {
    let text: String
    let docID: String
    let token: Int
    let pal: Pal
    let themeID: String
    let zoom: CGFloat
    let baseSize: CGFloat
    let lineHeight: CGFloat
    let measure: CGFloat
    let focusMode: Bool
    let typewriter: Bool
    let spellcheck: Bool
    let review: Review?
    let onChange: (String) -> Void
    let onResolve: (Int, String) -> Void
    var onNav: (Int) -> Void = { _ in }

    func diffKey(_ r: Review) -> String {
        r.path + "|" + r.blocks.map { "\($0.id)\($0.changed ? "c" : "e")\($0.oldText.count)-\($0.newText.count)" }.joined(separator: ",")
    }

    // Mark every misspelled word's underline now (synchronous, no selection change), instead of
    // waiting on the continuous checker's lazy pass.
    private func remarkSpelling(_ tv: NSTextView) {
        guard let lm = tv.layoutManager else { return }
        let str = tv.string
        let len = (str as NSString).length
        lm.removeTemporaryAttribute(.spellingState, forCharacterRange: NSRange(location: 0, length: len))
        let checker = NSSpellChecker.shared
        var start = 0
        while start < len {
            let r = checker.checkSpelling(of: str, startingAt: start, language: nil, wrap: false,
                                          inSpellDocumentWithTag: 0, wordCount: nil)
            guard r.location != NSNotFound, r.length > 0 else { break }
            lm.addTemporaryAttribute(.spellingState, value: NSAttributedString.SpellingState.spelling.rawValue,
                                     forCharacterRange: r)
            start = r.location + r.length
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = StableScrollView()
        scroll.contentView = IntegralClipView()   // whole-pixel width -> no creep/jump on resize
        scroll.drawsBackground = true
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.autoresizingMask = [.width, .height]

        let container = NSTextContainer(containerSize: NSSize(width: measure, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = false   // we pin an exact column width in layout() so words don't re-wrap on resize
        container.lineFragmentPadding = 0
        let lm = NSLayoutManager(); lm.addTextContainer(container)
        let ts = NSTextStorage(); ts.addLayoutManager(lm)

        let tv = ColumnTextView(frame: NSRect(x: 0, y: 0, width: 700, height: 400), textContainer: container)
        tv.columnMeasure = measure
        tv.delegate = context.coordinator
        tv.isRichText = true
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false        // never em-dash
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = spellcheck
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.autoresizingMask = [.width]
        tv.usesFindBar = true
        ts.delegate = context.coordinator
        lm.delegate = context.coordinator   // for concealing markdown markers
        scroll.documentView = tv
        context.coordinator.textView = tv

        applyTheme(tv, scroll)
        tv.string = text
        context.coordinator.loadedToken = token
        context.coordinator.highlightAll()
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView else { return }
        let c = context.coordinator
        c.parent = self
        applyTheme(tv, scroll)

        if tv.isContinuousSpellCheckingEnabled != spellcheck {
            tv.isContinuousSpellCheckingEnabled = spellcheck
            if spellcheck { remarkSpelling(tv) }               // show squiggles immediately, no cursor move
            else {                                             // hide existing red underlines
                let len = (tv.string as NSString).length
                tv.layoutManager?.removeTemporaryAttribute(.spellingState, forCharacterRange: NSRange(location: 0, length: len))
            }
        }

        // Diff mode: render changes inline in the SAME text view (scroll + styling preserved).
        if let review = review {
            let key = diffKey(review)
            if c.shownDiffKey != key {
                if c.shownDiffKey == nil { c.savedOffset = scroll.contentView.bounds.origin }  // remember scroll on enter
                c.shownDiffKey = key
                tv.isEditable = false
                c.renderDiff(review)
            }
            c.lastThemeID = themeID
            return
        }
        // Leaving diff -> reload the (resolved) document but keep the scroll position.
        if c.shownDiffKey != nil {
            c.shownDiffKey = nil
            c.removeDiffPills()
            tv.isEditable = true
            c.pendingRestore = c.savedOffset
            c.savedOffset = nil
            c.loadedToken = -1
        }

        if c.loadedToken != token {
            c.loadedToken = token
            if tv.string != text { tv.string = text }
            c.highlightAll()
            if let off = c.pendingRestore {                 // returning from diff: keep position
                c.pendingRestore = nil
                tv.layoutManager?.ensureLayout(for: tv.textContainer!)
                scroll.contentView.scroll(to: off); scroll.reflectScrolledClipView(scroll.contentView)
            } else {                                        // fresh file: start at the top
                tv.setSelectedRange(NSRange(location: 0, length: 0))
                tv.scroll(NSPoint.zero)
            }
        } else if c.lastThemeID != themeID {
            c.highlightAll()
        }
        c.lastThemeID = themeID
        c.applyFocus()
    }

    private func applyTheme(_ tv: NSTextView, _ scroll: NSScrollView) {
        let dark = pal.paper.luminance < 0.4
        tv.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)   // caret renders correctly per theme
        tv.backgroundColor = pal.paper
        scroll.backgroundColor = pal.paper
        tv.insertionPointColor = pal.accent
        tv.selectedTextAttributes = [.backgroundColor: pal.selection]
        let ps = Fonts.paragraph(lineHeight: lineHeight, size: baseSize * zoom)
        tv.typingAttributes = [.font: Fonts.serif(baseSize * zoom, weight: Fonts.bodyWeight), .foregroundColor: pal.ink, .paragraphStyle: ps]
        if let col = tv as? ColumnTextView, col.columnMeasure != measure {
            col.columnMeasure = measure
            col.needsLayout = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate {
        var parent: EditorView
        weak var textView: NSTextView?
        var loadedToken: Int = -1
        var lastThemeID: String = ""
        var shownDiffKey: String? = nil
        var savedOffset: CGPoint? = nil
        var pendingRestore: CGPoint? = nil
        private var inDiff = false
        private var highlighting = false
        private let concealed = NSMutableIndexSet()                 // char indexes whose glyphs are hidden
        private var lastActive = NSRange(location: NSNotFound, length: 0)
        var changeStarts: [Int] = []            // char location of each changed block (for nav)
        var changeAnchors: [Int] = []           // char location of the first changed word (for pill placement)
        var changeIds: [Int] = []               // parallel block ids (for the per-change pills)
        private var navIndex = -1
        private var navObserver: NSObjectProtocol?
        private var frameObserver: NSObjectProtocol?
        private var diffPills: [NSView] = []

        func startDiffNavObserver() {
            if navObserver == nil {
                navObserver = NotificationCenter.default.addObserver(forName: .iliadDiffNav, object: nil, queue: .main) { [weak self] note in
                    self?.scrollToChange((note.object as? String) == "prev" ? -1 : 1)
                }
            }
            if frameObserver == nil, let tv = textView {
                tv.postsFrameChangedNotifications = true
                frameObserver = NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: tv, queue: .main) { [weak self] _ in
                    guard let self, self.shownDiffKey != nil else { return }
                    self.placeDiffPills()   // text reflows on resize; keep pills aligned
                }
            }
        }
        deinit {
            if let o = navObserver { NotificationCenter.default.removeObserver(o) }
            if let o = frameObserver { NotificationCenter.default.removeObserver(o) }
        }

        func removeDiffPills() { diffPills.forEach { $0.removeFromSuperview() }; diffPills = [] }

        func placeDiffPills() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            removeDiffPills()
            lm.ensureLayout(for: tc)
            let inset = tv.textContainerInset
            let len = (tv.string as NSString).length
            let columnW = max(0, tv.bounds.width - inset.width * 2)
            for (i, loc) in changeAnchors.enumerated() where i < changeIds.count {
                let id = changeIds[i]
                let safe = NSRange(location: min(loc, max(0, len - 1)), length: min(1, max(0, len - loc)))
                let r = lm.boundingRect(forGlyphRange: safe, in: tc)
                let pill = CursorHostingView(rootView: DiffPill(
                    pal: parent.pal,
                    accept: { [weak self] in self?.parent.onResolve(id, "accept") },
                    reject: { [weak self] in self?.parent.onResolve(id, "reject") }))
                let size = pill.fittingSize
                let x = min(inset.width + columnW + 8, tv.bounds.width - size.width - 4)
                pill.frame = NSRect(x: x, y: inset.height + r.minY - 3, width: size.width, height: size.height)
                tv.addSubview(pill)
                diffPills.append(pill)
            }
        }

        func scrollToChange(_ dir: Int) {
            guard let tv = textView, let scroll = tv.enclosingScrollView,
                  let lm = tv.layoutManager, let tc = tv.textContainer, !changeStarts.isEmpty else { return }
            navIndex = navIndex < 0 ? (dir > 0 ? 0 : changeStarts.count - 1)
                                    : (navIndex + dir + changeStarts.count) % changeStarts.count
            lm.ensureLayout(for: tc)
            let len = (tv.string as NSString).length
            guard len > 0 else { return }
            let loc = min(changeStarts[navIndex], len - 1)
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: loc, length: 1), actualCharacterRange: nil)
            let r = lm.boundingRect(forGlyphRange: gr, in: tc)
            let yTop = r.minY + tv.textContainerInset.height       // container -> document coords
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, yTop - 80)))
            scroll.reflectScrolledClipView(scroll.contentView)
            parent.onNav(navIndex)
        }

        // Render the diff inline into the editor's own text storage.
        func renderDiff(_ review: Review) {
            guard let tv = textView, let ts = tv.textStorage else { return }
            inDiff = true
            startDiffNavObserver(); navIndex = -1
            concealed.remove(in: NSRange(location: 0, length: (ts.string as NSString).length))
            tv.linkTextAttributes = [.foregroundColor: parent.pal.accent, .underlineStyle: 0, .cursor: NSCursor.pointingHand]
            let pal = parent.pal
            let b = parent.baseSize * parent.zoom
            let body = Fonts.serif(b, weight: Fonts.bodyWeight)
            let ps = Fonts.paragraph(lineHeight: parent.lineHeight, size: b)
            let out = NSMutableAttributedString()
            var eqRanges: [NSRange] = []
            func appendNL() { out.append(NSAttributedString(string: "\n", attributes: [.font: body, .paragraphStyle: ps])) }
            // Append text but paint the highlight per-paragraph (blank separator lines stay uncolored,
            // so multi-paragraph changes read as separate boxes rather than one giant block).
            func appendBoxed(_ s: String, fg: NSColor, bg: NSColor?, strike: Bool) {
                var attrs: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: fg, .paragraphStyle: ps]
                if strike { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                let start = out.length
                out.append(NSAttributedString(string: s, attributes: attrs))
                guard let bg else { return }
                let nss = s as NSString
                nss.enumerateSubstrings(in: NSRange(location: 0, length: nss.length), options: .byParagraphs) { sub, r, _, _ in
                    guard let sub, !sub.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    out.addAttribute(.backgroundColor, value: bg, range: NSRange(location: start + r.location, length: r.length))
                }
            }
            changeStarts = []; changeAnchors = []; changeIds = []
            for (idx, blk) in review.blocks.enumerated() {
                if !blk.changed {
                    let start = out.length
                    out.append(NSAttributedString(string: blk.newText, attributes: [.font: body, .foregroundColor: pal.ink, .paragraphStyle: ps]))
                    eqRanges.append(NSRange(location: start, length: out.length - start))
                } else {
                    let blockStart = out.length
                    changeStarts.append(blockStart); changeIds.append(blk.id)
                    let ops = Diff.build(blk.oldText, blk.newText)
                    let eqLen = ops.filter { $0.type == "eq" }.reduce(0) { $0 + $1.text.count }
                    let maxLen = max(blk.oldText.count, blk.newText.count)
                    var anchor = blockStart   // where the per-change pill sits (first changed word)
                    // Small edit -> inline word-level diff (only changed words). Big rewrite -> whole-block view.
                    if maxLen > 0 && Double(eqLen) / Double(maxLen) >= 0.4 {
                        var found = false
                        for op in ops {
                            let here = out.length
                            switch op.type {
                            case "del": if !found { anchor = here; found = true }; appendBoxed(op.text, fg: pal.delFg, bg: pal.delBg, strike: true)
                            case "ins": if !found { anchor = here; found = true }; appendBoxed(op.text, fg: pal.insFg, bg: pal.insBg, strike: false)
                            default:    appendBoxed(op.text, fg: pal.ink, bg: nil, strike: false)
                            }
                        }
                    } else {
                        if !blk.oldText.isEmpty {
                            appendBoxed(blk.oldText, fg: pal.delFg, bg: pal.delBg, strike: true)
                            if !blk.newText.isEmpty { appendNL() }
                        }
                        if !blk.newText.isEmpty {
                            appendBoxed(blk.newText, fg: pal.insFg, bg: pal.insBg, strike: false)
                        }
                    }
                    changeAnchors.append(anchor)
                }
                if idx < review.blocks.count - 1 { appendNL() }
            }
            ts.setAttributedString(out)
            // re-apply markdown styling to the unchanged regions (keeps the editor look)
            let ns = ts.string as NSString
            for r in eqRanges {
                ns.enumerateSubstrings(in: r, options: .byLines) { sub, subRange, _, _ in
                    guard let line = sub else { return }
                    self.styleLine(ts, line, subRange, pal, active: true)
                }
            }
            inDiff = false
            DispatchQueue.main.async { [weak self] in self?.placeDiffPills() }   // anchor pills after layout
        }

        func textView(_ tv: NSTextView, clickedOnLink link: Any, at idx: Int) -> Bool {
            guard let url = (link as? URL) ?? URL(string: "\(link)"),
                  url.scheme == "iliad", let host = url.host, let id = Int(host) else { return false }
            parent.onResolve(id, url.path.replacingOccurrences(of: "/", with: ""))
            return true
        }

        init(_ p: EditorView) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.onChange(tv.string)
            if parent.typewriter { centerCaret() }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            // While a diff is on screen the text view is read-only; restyling the active
            // line here would wipe its diff highlight (looks like it got "approved" on select).
            if shownDiffKey != nil { return }
            if parent.focusMode { applyFocus() }
            if parent.typewriter { centerCaret() }
            revealSelectionGlyphs()
            updateActiveLine()
        }

        // Regenerate glyphs over the changed selection span so concealed markers under the
        // selection get revealed (and re-hidden once the selection moves off them).
        private var lastSel = NSRange(location: 0, length: 0)
        private func revealSelectionGlyphs() {
            guard concealed.count > 0, let tv = textView, let lm = tv.layoutManager else {
                lastSel = textView?.selectedRange() ?? lastSel; return
            }
            let len = (tv.string as NSString).length
            let new = tv.selectedRange()
            func span(_ r: NSRange) -> NSRange? {
                guard r.length > 0 else { return nil }
                let loc = max(0, min(r.location, len))
                let end = min(NSMaxRange(r) + 1, len)
                return end > loc ? NSRange(location: loc, length: end - loc) : nil
            }
            for s in [span(lastSel), span(new)].compactMap({ $0 }) {
                lm.invalidateGlyphs(forCharacterRange: s, changeInLength: 0, actualCharacterRange: nil)
            }
            lastSel = new
        }

        // Reveal markers on the paragraph with the caret; conceal the one we left.
        private func updateActiveLine() {
            guard let tv = textView, let ts = tv.textStorage else { return }
            let ns = ts.string as NSString
            let sel = tv.selectedRange()
            let para = ns.paragraphRange(for: NSRange(location: min(sel.location, ns.length), length: 0))
            if NSEqualRanges(para, lastActive) { return }
            let old = lastActive
            lastActive = para
            if old.location != NSNotFound, NSMaxRange(old) <= ns.length { highlight(range: old) }
            highlight(range: para)
        }

        // Hide concealed marker glyphs (zero width) so inactive lines read as rendered.
        func layoutManager(_ lm: NSLayoutManager,
                           shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                           properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                           characterIndexes charIndexes: UnsafePointer<Int>,
                           font: NSFont, forGlyphRange glyphRange: NSRange) -> Int {
            guard concealed.count > 0 else { return 0 }
            // Reveal concealed markers that fall inside the selection, otherwise their hidden
            // (.null) glyphs render as little boxes under the selection highlight.
            let sel = textView?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
            let hasSel = sel.location != NSNotFound && sel.length > 0
            let n = glyphRange.length
            let newProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>.allocate(capacity: n)
            defer { newProps.deallocate() }
            var changed = false
            for i in 0..<n {
                var p = props[i]
                let ci = charIndexes[i]
                let inSel = hasSel && ci >= sel.location && ci < NSMaxRange(sel)
                if concealed.contains(ci) && !inSel { p.insert(.null); changed = true }
                newProps[i] = p
            }
            guard changed else { return 0 }
            lm.setGlyphs(glyphs, properties: newProps, characterIndexes: charIndexes, font: font, forGlyphRange: glyphRange)
            return n
        }

        // Re-highlight edited paragraph(s)
        func textStorage(_ ts: NSTextStorage, didProcessEditing edited: NSTextStorageEditActions,
                         range editedRange: NSRange, changeInLength delta: Int) {
            guard edited.contains(.editedCharacters), !highlighting, !inDiff else { return }
            let ns = ts.string as NSString
            // keep concealed indexes aligned with the edit, then re-highlight the
            // edited paragraph synchronously so typed text never flashes unstyled
            if delta != 0 { concealed.shiftIndexesStarting(at: editedRange.location, by: delta) }
            highlight(range: ns.paragraphRange(for: editedRange))
        }

        func highlightAll() {
            guard let ts = textView?.textStorage, let tv = textView else { return }
            let ns = ts.string as NSString
            concealed.remove(in: NSRange(location: 0, length: ns.length))
            lastActive = ns.paragraphRange(for: NSRange(location: min(tv.selectedRange().location, ns.length), length: 0))
            highlight(range: NSRange(location: 0, length: ns.length))
        }

        private func highlight(range: NSRange) {
            guard let ts = textView?.textStorage, let tv = textView else { return }
            let ns = ts.string as NSString
            let clamped = NSRange(location: min(range.location, ns.length),
                                  length: min(range.length, max(0, ns.length - range.location)))
            let lineRange = ns.lineRange(for: clamped)
            let pal = parent.pal
            let sel = tv.selectedRange()
            highlighting = true
            concealed.remove(in: lineRange)
            ts.beginEditing()
            let base = Fonts.serif(parent.baseSize * parent.zoom, weight: Fonts.bodyWeight)
            let ps = Fonts.paragraph(lineHeight: parent.lineHeight, size: parent.baseSize * parent.zoom)
            ts.setAttributes([.font: base, .foregroundColor: pal.ink, .paragraphStyle: ps], range: lineRange)
            ns.enumerateSubstrings(in: lineRange, options: .byLines) { sub, subRange, _, _ in
                guard let line = sub else { return }
                let active = sel.location != NSNotFound && sel.location >= subRange.location && sel.location <= NSMaxRange(subRange)
                self.styleLine(ts, line, subRange, pal, active: active)
            }
            ts.endEditing()
            highlighting = false
            // Defer glyph concealment out of the edit-processing callback (calling
            // invalidateGlyphs/ensureLayout during didProcessEditing breaks input).
            let lr = lineRange
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tv = self.textView, let lm = tv.layoutManager else { return }
                lm.invalidateGlyphs(forCharacterRange: lr, changeInLength: 0, actualCharacterRange: nil)
                tv.needsDisplay = true
            }
        }

        private func setFont(_ ts: NSTextStorage, _ font: NSFont, _ r: NSRange) { ts.addAttribute(.font, value: font, range: r) }
        private func dim(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange) { ts.addAttribute(.foregroundColor, value: pal.inkFaint, range: r) }
        // A syntax marker: dimmed when its line is being edited, concealed otherwise.
        private func marker(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange, _ active: Bool) {
            guard r.length > 0 else { return }
            if active { ts.addAttribute(.foregroundColor, value: pal.inkFaint, range: r) }
            else { concealed.add(in: r) }
        }
        private func markerEdges(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange, _ n: Int, _ off: Int, _ active: Bool) {
            marker(ts, pal, shift(NSRange(location: r.location, length: n), off), active)
            marker(ts, pal, shift(NSRange(location: r.location + r.length - n, length: n), off), active)
        }

        private func styleLine(_ ts: NSTextStorage, _ line: String, _ subRange: NSRange, _ pal: Pal, active: Bool) {
            let z = parent.zoom
            let b = parent.baseSize * z
            let nsLine = line as NSString
            if let m = regex("^(\\s*)(#{1,6})(\\s+)").firstMatch(in: line, range: full(nsLine)) {
                let level = m.range(at: 2).length
                let ratios: [CGFloat] = [1.55, 1.38, 1.22, 1.1, 1.0, 0.92]
                setFont(ts, Fonts.serif(b * ratios[min(level - 1, 5)], weight: Fonts.titleWeight), subRange)
                // conceal "### " (marker + following space) when inactive
                marker(ts, pal, shift(NSRange(location: m.range(at: 2).location, length: m.range(at: 2).length + m.range(at: 3).length), subRange.location), active)
                inlineStyle(ts, line, subRange, pal, active: active)
                return
            }
            if let m = regex("^(\\s*)(>)(\\s?)").firstMatch(in: line, range: full(nsLine)) {
                setFont(ts, Fonts.serif(b, weight: Fonts.bodyWeight, italic: true), subRange)
                ts.addAttribute(.foregroundColor, value: pal.inkSoft, range: subRange)
                marker(ts, pal, shift(NSRange(location: m.range(at: 2).location, length: m.range(at: 2).length + m.range(at: 3).length), subRange.location), active)
                inlineStyle(ts, line, subRange, pal, active: active)
                return
            }
            if let m = regex("^(\\s*)([-*+]|\\d+\\.)(\\s+)").firstMatch(in: line, range: full(nsLine)) {
                marker(ts, pal, shift(m.range(at: 2), subRange.location), active)
            }
            inlineStyle(ts, line, subRange, pal, active: active)
        }

        private func inlineStyle(_ ts: NSTextStorage, _ line: String, _ subRange: NSRange, _ pal: Pal, active: Bool) {
            let b = parent.baseSize * parent.zoom
            let nsLine = line as NSString
            let off = subRange.location
            for m in regex("`([^`]+)`").matches(in: line, range: full(nsLine)) {
                setFont(ts, Fonts.monoSized(b * 0.9), shift(m.range, off))
                ts.addAttribute(.foregroundColor, value: pal.inkSoft, range: shift(m.range, off))
                markerEdges(ts, pal, m.range, 1, off, active)
            }
            for m in regex("\\*\\*([^*\\n]+)\\*\\*").matches(in: line, range: full(nsLine)) {
                setFont(ts, Fonts.serif(b, weight: Fonts.boldWeight), shift(m.range(at: 1), off))
                markerEdges(ts, pal, m.range, 2, off, active)
            }
            for m in regex("(^|[^*\\w])\\*([^*\\n]+)\\*").matches(in: line, range: full(nsLine)) {
                setFont(ts, Fonts.serif(b, weight: Fonts.bodyWeight, italic: true), shift(m.range(at: 2), off))
                marker(ts, pal, shift(NSRange(location: m.range(at: 2).location - 1, length: 1), off), active)
                marker(ts, pal, shift(NSRange(location: m.range(at: 2).location + m.range(at: 2).length, length: 1), off), active)
            }
            for m in regex("(^|[^_\\w])_([^_\\n]+)_").matches(in: line, range: full(nsLine)) {
                setFont(ts, Fonts.serif(b, weight: Fonts.bodyWeight, italic: true), shift(m.range(at: 2), off))
                marker(ts, pal, shift(NSRange(location: m.range(at: 2).location - 1, length: 1), off), active)
                marker(ts, pal, shift(NSRange(location: m.range(at: 2).location + m.range(at: 2).length, length: 1), off), active)
            }
            for m in regex("~~([^~\\n]+)~~").matches(in: line, range: full(nsLine)) {
                ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: shift(m.range(at: 1), off))
                markerEdges(ts, pal, m.range, 2, off, active)
            }
            // links [text](url): keep the text, conceal the brackets + url when inactive
            for m in regex("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)").matches(in: line, range: full(nsLine)) {
                ts.addAttribute(.foregroundColor, value: pal.accent, range: shift(m.range(at: 1), off))
                marker(ts, pal, shift(NSRange(location: m.range.location, length: 1), off), active)   // [
                let tail = NSRange(location: NSMaxRange(m.range(at: 1)), length: NSMaxRange(m.range) - NSMaxRange(m.range(at: 1)))
                marker(ts, pal, shift(tail, off), active)   // ](url)
            }
        }

        private func dimEdges(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange, _ n: Int, _ off: Int) {
            dim(ts, pal, shift(NSRange(location: r.location, length: n), off))
            dim(ts, pal, shift(NSRange(location: r.location + r.length - n, length: n), off))
        }
        private func shift(_ r: NSRange, _ off: Int) -> NSRange { NSRange(location: r.location + off, length: r.length) }
        private func full(_ s: NSString) -> NSRange { NSRange(location: 0, length: s.length) }

        // Focus mode: dim every paragraph except the one with the caret.
        func applyFocus() {
            guard let tv = textView, let lm = tv.layoutManager, let ts = tv.textStorage else { return }
            let ns = ts.string as NSString
            let whole = NSRange(location: 0, length: ns.length)
            lm.removeTemporaryAttribute(.foregroundColor, forCharacterRange: whole)
            guard parent.focusMode else { return }
            let active = ns.paragraphRange(for: tv.selectedRange())
            let dimColor = parent.pal.ink.withAlphaComponent(0.28)
            if active.location > 0 {
                lm.addTemporaryAttributes([.foregroundColor: dimColor], forCharacterRange: NSRange(location: 0, length: active.location))
            }
            let tail = NSRange(location: active.location + active.length, length: ns.length - (active.location + active.length))
            if tail.length > 0 {
                lm.addTemporaryAttributes([.foregroundColor: dimColor], forCharacterRange: tail)
            }
        }

        func centerCaret() {
            guard let tv = textView, let scroll = tv.enclosingScrollView else { return }
            let r = tv.firstRect(forCharacterRange: tv.selectedRange(), actualRange: nil)
            guard r.origin.y.isFinite else { return }
            let local = tv.convert(r, from: nil)
            let target = local.midY - scroll.contentSize.height / 2
            scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, target)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private var _regexCache: [String: NSRegularExpression] = [:]
func regex(_ pattern: String) -> NSRegularExpression {
    if let r = _regexCache[pattern] { return r }
    let r = try! NSRegularExpression(pattern: pattern)
    _regexCache[pattern] = r
    return r
}
extension NSRegularExpression {
    func matches(in s: String, range: NSRange) -> [NSTextCheckingResult] { matches(in: s, options: [], range: range) }
    func firstMatch(in s: String, range: NSRange) -> NSTextCheckingResult? { firstMatch(in: s, options: [], range: range) }
}
