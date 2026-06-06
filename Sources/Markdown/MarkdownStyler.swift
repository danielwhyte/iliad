import AppKit

// Live-Markdown styling for the editor, split out of the coordinator by element.
// These are Coordinator methods (the whole target is one module, so no import is needed);
// they apply attributes to the text storage and conceal/reveal syntax markers per line.
extension EditorView.Coordinator {

    // ---- shared helpers ----

    func setFont(_ ts: NSTextStorage, _ font: NSFont, _ r: NSRange) { ts.addAttribute(.font, value: font, range: r) }
    func dim(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange) { ts.addAttribute(.foregroundColor, value: pal.inkFaint, range: r) }
    func shift(_ r: NSRange, _ off: Int) -> NSRange { NSRange(location: r.location + off, length: r.length) }
    func full(_ s: NSString) -> NSRange { NSRange(location: 0, length: s.length) }

    // A syntax marker: dimmed when its line is being edited, concealed otherwise.
    func marker(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange, _ active: Bool) {
        guard r.length > 0 else { return }
        if active { ts.addAttribute(.foregroundColor, value: pal.inkFaint, range: r) }
        else { concealed.add(in: r) }
    }
    func markerEdges(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange, _ n: Int, _ off: Int, _ active: Bool) {
        marker(ts, pal, shift(NSRange(location: r.location, length: n), off), active)
        marker(ts, pal, shift(NSRange(location: r.location + r.length - n, length: n), off), active)
    }
    func dimEdges(_ ts: NSTextStorage, _ pal: Pal, _ r: NSRange, _ n: Int, _ off: Int) {
        dim(ts, pal, shift(NSRange(location: r.location, length: n), off))
        dim(ts, pal, shift(NSRange(location: r.location + r.length - n, length: n), off))
    }

    // ---- block elements: dispatch one line to its element styler ----

    func styleLine(_ ts: NSTextStorage, _ line: String, _ subRange: NSRange, _ pal: Pal, active: Bool) {
        let b = parent.baseSize * parent.zoom
        let nsLine = line as NSString
        if inCodeBlock(subRange.location) { styleCodeLine(ts, line, subRange, pal); return }
        if styleTableRow(ts, line, nsLine, subRange, pal, b) { return }
        if styleHorizontalRule(ts, line, nsLine, subRange, pal, active) { return }
        if styleHeading(ts, line, nsLine, subRange, pal, b, active) { return }
        if styleBlockquote(ts, line, nsLine, subRange, pal, b, active) { return }
        styleListMarker(ts, line, nsLine, subRange, pal, active)
        inlineStyle(ts, line, subRange, pal, active: active)
    }

    // Table row: monospace + dimmed pipes (manual cell padding then aligns in the column).
    private func styleTableRow(_ ts: NSTextStorage, _ line: String, _ nsLine: NSString, _ subRange: NSRange, _ pal: Pal, _ b: CGFloat) -> Bool {
        guard regex("^\\s*\\|").firstMatch(in: line, range: full(nsLine)) != nil else { return false }
        setFont(ts, Fonts.monoSized(b * 0.85), subRange)
        let separator = regex("^\\s*\\|?[\\s:|-]*-[\\s:|-]*$").firstMatch(in: line, range: full(nsLine)) != nil
        ts.addAttribute(.foregroundColor, value: separator ? pal.inkFaint : pal.ink, range: subRange)
        if !separator {
            for m in regex("\\|").matches(in: line, range: full(nsLine)) {
                ts.addAttribute(.foregroundColor, value: pal.inkFaint, range: shift(m.range, subRange.location))
            }
        }
        return true
    }

    // Horizontal rule: a line is drawn across the column in the gutter. Hide the dashes with a clear
    // color (rather than concealing them to null glyphs, which collapses the line and makes the rule
    // anchor to the wrong line); revealed dimmed when the line is being edited.
    private func styleHorizontalRule(_ ts: NSTextStorage, _ line: String, _ nsLine: NSString, _ subRange: NSRange, _ pal: Pal, _ active: Bool) -> Bool {
        guard regex("^\\s*([-*_])(\\s*\\1){2,}\\s*$").firstMatch(in: line, range: full(nsLine)) != nil else { return false }
        ts.addAttribute(.foregroundColor, value: active ? pal.inkFaint : NSColor.clear, range: subRange)
        return true
    }

    private func styleHeading(_ ts: NSTextStorage, _ line: String, _ nsLine: NSString, _ subRange: NSRange, _ pal: Pal, _ b: CGFloat, _ active: Bool) -> Bool {
        guard let m = regex("^(\\s*)(#{1,6})(\\s+)").firstMatch(in: line, range: full(nsLine)) else { return false }
        let level = m.range(at: 2).length
        let ratios: [CGFloat] = [1.55, 1.38, 1.22, 1.1, 1.0, 0.92]
        setFont(ts, Fonts.serif(b * ratios[min(level - 1, 5)], weight: Fonts.titleWeight), subRange)
        marker(ts, pal, shift(NSRange(location: m.range(at: 2).location, length: m.range(at: 2).length + m.range(at: 3).length), subRange.location), active)
        inlineStyle(ts, line, subRange, pal, active: active)
        return true
    }

    private func styleBlockquote(_ ts: NSTextStorage, _ line: String, _ nsLine: NSString, _ subRange: NSRange, _ pal: Pal, _ b: CGFloat, _ active: Bool) -> Bool {
        guard let m = regex("^(\\s*)(>)(\\s?)").firstMatch(in: line, range: full(nsLine)) else { return false }
        setFont(ts, Fonts.serif(b, weight: Fonts.bodyWeight, italic: true), subRange)
        ts.addAttribute(.foregroundColor, value: pal.inkSoft, range: subRange)
        marker(ts, pal, shift(NSRange(location: m.range(at: 2).location, length: m.range(at: 2).length + m.range(at: 3).length), subRange.location), active)
        inlineStyle(ts, line, subRange, pal, active: active)
        return true
    }

    // List bullet/number marker + task checkbox markup (both rendered in the margin gutter).
    private func styleListMarker(_ ts: NSTextStorage, _ line: String, _ nsLine: NSString, _ subRange: NSRange, _ pal: Pal, _ active: Bool) {
        guard let m = regex("^(\\s*)([-*+]|\\d+\\.)(\\s+)").firstMatch(in: line, range: full(nsLine)) else { return }
        let task = regex("^(\\s*)[-*+](\\s+)(\\[[ xX]\\])(\\s?)").firstMatch(in: line, range: full(nsLine))
        // A task line renders as a margin checkbox. Keep its `- [x] ` markup hidden even while the line
        // is being edited, so the checkbox stays locked in place (revealing it would shift the text and
        // drag the checkbox along with it).
        marker(ts, pal, shift(m.range(at: 2), subRange.location), task == nil ? active : false)
        if let tm = task {
            let box = NSRange(location: tm.range(at: 3).location, length: tm.range(at: 3).length + tm.range(at: 4).length)
            marker(ts, pal, shift(box, subRange.location), false)
        }
    }
}
