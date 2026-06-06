import AppKit

// Knuth-Plass optimal line breaking — the algorithm behind TeX and InDesign's Paragraph Composer.
// It breaks a whole paragraph at once to minimise total "badness" (uneven word spacing), instead of
// the greedy line-at-a-time breaker TextKit uses. We return the styled string with U+2028 line
// separators inserted at the optimal points, so the layout manager then justifies each line evenly.
enum KnuthPlass {
    static func breakParagraph(_ attr: NSAttributedString, width: CGFloat, firstIndent: CGFloat = 0) -> NSAttributedString {
        let s = attr.string as NSString
        let n = s.length
        guard width > 1, n > 0 else { return attr }

        // Tokenise into words separated by spaces; remember each word's range.
        var words: [NSRange] = []
        var i = 0
        while i < n {
            while i < n && s.character(at: i) == 32 { i += 1 }       // skip spaces
            let start = i
            while i < n && s.character(at: i) != 32 { i += 1 }
            if i > start { words.append(NSRange(location: start, length: i - start)) }
        }
        let wc = words.count
        guard wc > 2 else { return attr }

        // Width of each word with its own attributes, plus a representative space width.
        let widths = words.map { ceil(attr.attributedSubstring(from: $0).size().width) }
        let spaceW: CGFloat = {
            let probe = NSAttributedString(string: " ", attributes: attr.attributes(at: words[0].location, effectiveRange: nil))
            return max(1, ceil(probe.size().width))
        }()
        var pre = [CGFloat](repeating: 0, count: wc + 1)
        for k in 0..<wc { pre[k + 1] = pre[k] + widths[k] }
        func natural(_ a: Int, _ b: Int) -> CGFloat { pre[b] - pre[a] + CGFloat(b - a - 1) * spaceW }
        func avail(_ a: Int) -> CGFloat { a == 0 ? width - firstIndent : width }

        // DP over break points: best[b] = least demerits to fill words[0..<b].
        var best = [Double](repeating: .infinity, count: wc + 1)
        var prev = [Int](repeating: 0, count: wc + 1)
        best[0] = 0
        for b in 1...wc {
            var a = b - 1
            while a >= 0 {
                let L = natural(a, b)
                let W = avail(a)
                if L > W && (b - a) > 1 { break }                   // line too wide; widening further only worsens
                guard best[a].isFinite else { a -= 1; continue }
                var d: Double
                if b == wc {                                        // last line is set ragged (no stretch penalty)
                    d = 0
                } else {
                    let stretch = max(1, CGFloat(b - a - 1)) * spaceW * 0.6
                    let r = Double((W - L) / stretch)               // adjustment ratio
                    let badness = 100 * abs(r) * r * r              // ~ 100·|r|³
                    let pen = 10.0 + badness
                    d = pen * pen
                }
                let tot = best[a] + d
                if tot < best[b] { best[b] = tot; prev[b] = a }
                a -= 1
            }
        }
        guard best[wc].isFinite else { return attr }                // fell back (e.g. an over-long word)

        // Reconstruct the line-start word indices.
        var starts: [Int] = []
        var b = wc
        while b > 0 { let a = prev[b]; starts.append(a); b = a }
        starts.reverse()

        // Replace the space before each new line's first word with a line separator (back-to-front).
        let out = NSMutableAttributedString(attributedString: attr)
        var cuts: [Int] = []
        for k in 1..<starts.count {
            let loc = words[starts[k]].location
            if loc - 1 >= 0 && s.character(at: loc - 1) == 32 { cuts.append(loc - 1) }
        }
        for c in cuts.sorted(by: >) {
            out.replaceCharacters(in: NSRange(location: c, length: 1), with: "\u{2028}")
        }
        return out
    }
}
