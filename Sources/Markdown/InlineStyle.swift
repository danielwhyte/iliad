import AppKit

// Inline Markdown elements: `code`, **bold**, *italic* / _italic_, ~~strike~~, and [links](url).
// The text is kept; the surrounding syntax markers are concealed when the line isn't being edited.
extension EditorView.Coordinator {
    func inlineStyle(_ ts: NSTextStorage, _ line: String, _ subRange: NSRange, _ pal: Pal, active: Bool) {
        let b = parent.baseSize * parent.zoom
        let nsLine = line as NSString
        let off = subRange.location

        for m in regex("`([^`]+)`").matches(in: line, range: full(nsLine)) {                 // inline code
            setFont(ts, Fonts.monoSized(b * 0.9), shift(m.range, off))
            ts.addAttribute(.foregroundColor, value: pal.inkSoft, range: shift(m.range, off))
            markerEdges(ts, pal, m.range, 1, off, active)
        }
        for m in regex("\\*\\*([^*\\n]+)\\*\\*").matches(in: line, range: full(nsLine)) {       // **bold**
            setFont(ts, Fonts.serif(b, weight: Fonts.boldWeight), shift(m.range(at: 1), off))
            markerEdges(ts, pal, m.range, 2, off, active)
        }
        for m in regex("(^|[^*\\w])\\*([^*\\n]+)\\*").matches(in: line, range: full(nsLine)) {  // *italic*
            setFont(ts, Fonts.serif(b, weight: Fonts.bodyWeight, italic: true), shift(m.range(at: 2), off))
            marker(ts, pal, shift(NSRange(location: m.range(at: 2).location - 1, length: 1), off), active)
            marker(ts, pal, shift(NSRange(location: m.range(at: 2).location + m.range(at: 2).length, length: 1), off), active)
        }
        for m in regex("(^|[^_\\w])_([^_\\n]+)_").matches(in: line, range: full(nsLine)) {      // _italic_
            setFont(ts, Fonts.serif(b, weight: Fonts.bodyWeight, italic: true), shift(m.range(at: 2), off))
            marker(ts, pal, shift(NSRange(location: m.range(at: 2).location - 1, length: 1), off), active)
            marker(ts, pal, shift(NSRange(location: m.range(at: 2).location + m.range(at: 2).length, length: 1), off), active)
        }
        for m in regex("~~([^~\\n]+)~~").matches(in: line, range: full(nsLine)) {               // ~~strike~~
            ts.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: shift(m.range(at: 1), off))
            markerEdges(ts, pal, m.range, 2, off, active)
        }
        for m in regex("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)").matches(in: line, range: full(nsLine)) {  // [text](url)
            ts.addAttribute(.foregroundColor, value: pal.accent, range: shift(m.range(at: 1), off))
            marker(ts, pal, shift(NSRange(location: m.range.location, length: 1), off), active)   // [
            let tail = NSRange(location: NSMaxRange(m.range(at: 1)), length: NSMaxRange(m.range) - NSMaxRange(m.range(at: 1)))
            marker(ts, pal, shift(tail, off), active)   // ](url)
        }
    }
}
