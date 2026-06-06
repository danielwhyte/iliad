import AppKit

// Fenced code blocks (``` or ~~~). Unlike the other elements, a fenced block spans many lines, so the
// per-line styler can't decide in isolation whether a line is code. We scan the whole document for
// fence pairs, cache their character ranges, and consult that while styling, parsing, and gutter-building.
extension EditorView.Coordinator {

    // Recompute the ranges covered by fenced code blocks (the fence lines themselves included).
    // An unterminated opening fence runs to the end of the document.
    func scanCodeBlocks() {
        guard let tv = textView else { codeBlocks = []; return }
        let ns = tv.string as NSString
        var ranges: [NSRange] = []
        var open = -1
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: .byLines) { sub, _, encl, _ in
            guard let sub, sub.range(of: "^\\s*(```|~~~)", options: .regularExpression) != nil else { return }
            if open < 0 { open = encl.location }
            else { ranges.append(NSRange(location: open, length: NSMaxRange(encl) - open)); open = -1 }
        }
        if open >= 0 { ranges.append(NSRange(location: open, length: ns.length - open)) }
        codeBlocks = ranges
    }

    func inCodeBlock(_ loc: Int) -> Bool { codeBlocks.contains { NSLocationInRange(loc, $0) } }

    // A line inside a fence: monospace body; the opening/closing ``` fences are dimmed.
    func styleCodeLine(_ ts: NSTextStorage, _ line: String, _ subRange: NSRange, _ pal: Pal) {
        let b = parent.baseSize * parent.zoom
        setFont(ts, Fonts.monoSized(b * 0.9), subRange)
        let isFence = line.range(of: "^\\s*(```|~~~)", options: .regularExpression) != nil
        ts.addAttribute(.foregroundColor, value: isFence ? pal.inkFaint : pal.inkSoft, range: subRange)
    }
}
