import SwiftUI
import AppKit

// A parsed GFM pipe table and the document range it occupies.
struct MDTable {
    let range: NSRange            // whole block, including the line terminators
    let lineCount: Int            // raw lines the block spans (height is reserved across these)
    let rows: [[String]]          // header is row 0; the separator row is dropped
    let aligns: [TextAlignment]
    let rowRanges: [NSRange]      // document range of each rendered row's source line (header + body)
}

// Find every GFM table: a header row of `|...|`, a separator row `|---|`, then body rows.
func parseTables(_ s: String) -> [MDTable] {
    let ns = s as NSString
    var lineRanges: [NSRange] = []
    ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, _, encl, _ in
        lineRanges.append(encl)   // enclosing range includes the trailing newline
    }
    func text(_ r: NSRange) -> String { ns.substring(with: r).trimmingCharacters(in: .newlines) }
    func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    func isSeparator(_ line: String) -> Bool {
        line.range(of: "^\\s*\\|?[\\s:|-]*-[\\s:|-]*$", options: .regularExpression) != nil && line.contains("-")
    }
    func isRow(_ line: String) -> Bool { line.range(of: "^\\s*\\|", options: .regularExpression) != nil }

    var tables: [MDTable] = []
    var i = 0
    while i < lineRanges.count {
        if i + 1 < lineRanges.count, isRow(text(lineRanges[i])), isSeparator(text(lineRanges[i + 1])) {
            let header = cells(text(lineRanges[i]))
            let aligns = cells(text(lineRanges[i + 1])).map { sep -> TextAlignment in
                let l = sep.hasPrefix(":"), r = sep.hasSuffix(":")
                return (l && r) ? .center : (r ? .trailing : .leading)
            }
            var rows = [header]
            var rowRanges = [lineRanges[i]]   // header line; separator is skipped
            var j = i + 2
            while j < lineRanges.count, isRow(text(lineRanges[j])), !isSeparator(text(lineRanges[j])) {
                rows.append(cells(text(lineRanges[j]))); rowRanges.append(lineRanges[j]); j += 1
            }
            let start = lineRanges[i].location
            let end = NSMaxRange(lineRanges[j - 1])
            // normalize ragged rows to the column count
            let cols = max(header.count, aligns.count)
            let padded = rows.map { r -> [String] in r + Array(repeating: "", count: max(0, cols - r.count)) }
            let al = aligns + Array(repeating: TextAlignment.leading, count: max(0, cols - aligns.count))
            tables.append(MDTable(range: NSRange(location: start, length: end - start),
                                  lineCount: j - i, rows: padded, aligns: al, rowRanges: rowRanges))
            i = j
        } else { i += 1 }
    }
    return tables
}

// The rendered table: a bordered grid in the body font. Cells are editable inline (single click);
// a double-click hands off to the raw Markdown at that cell.
struct MarkdownTableView: View {
    let table: MDTable
    let width: CGFloat
    let font: Font
    let ink: Color
    let headerInk: Color
    let rule: Color
    let stripe: Color
    let accent: Color
    var onCellEdit: (Int, Int, String) -> Void = { _, _, _ in }   // committed cell text -> source
    var onMdEdit: (Int, Int) -> Void = { _, _ in }                // double-click -> raw Markdown
    @State private var draft: [[String]]

    init(table: MDTable, width: CGFloat, font: Font, ink: Color, headerInk: Color, rule: Color, stripe: Color,
         accent: Color, onCellEdit: @escaping (Int, Int, String) -> Void = { _, _, _ in },
         onMdEdit: @escaping (Int, Int) -> Void = { _, _ in }) {
        self.table = table; self.width = width; self.font = font; self.ink = ink; self.headerInk = headerInk
        self.rule = rule; self.stripe = stripe; self.accent = accent
        self.onCellEdit = onCellEdit; self.onMdEdit = onMdEdit
        _draft = State(initialValue: table.rows)
    }

    var body: some View {
        let cols = table.rows.first?.count ?? 0
        VStack(spacing: 0) {
            ForEach(0..<table.rows.count, id: \.self) { ri in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { ci in cell(ri, ci) }
                }
                .background((ri > 0 && ri % 2 == 0) ? stripe : .clear)
                .overlay(ri < table.rows.count - 1 ? Rectangle().frame(height: 1).foregroundColor(rule) : nil,
                         alignment: .bottom)
            }
        }
        .frame(width: width)
        .overlay(columnWalls(cols))   // continuous full-height dividers between columns
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(rule, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .fixedSize(horizontal: false, vertical: true)
        .help("Click a cell to edit · double-click for Markdown")
    }

    private func columnWalls(_ cols: Int) -> some View {
        GeometryReader { geo in
            Path { p in
                for i in 1..<max(1, cols) {
                    let x = (geo.size.width * CGFloat(i) / CGFloat(cols)).rounded()
                    p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
            }.stroke(rule, lineWidth: 1)
        }
    }

    @ViewBuilder private func cell(_ ri: Int, _ ci: Int) -> some View {
        TableCell(text: binding(ri, ci), font: font, header: ri == 0,
                  ink: ri == 0 ? headerInk : ink, accent: accent,
                  align: table.aligns[safe: ci] ?? .leading,
                  onCommit: { onCellEdit(ri, ci, draft[safe: ri]?[safe: ci] ?? "") },
                  onMdEdit: { onMdEdit(ri, ci) })
    }

    private func binding(_ ri: Int, _ ci: Int) -> Binding<String> {
        Binding(get: { draft[safe: ri]?[safe: ci] ?? "" },
                set: { v in if ri < draft.count, ci < draft[ri].count { draft[ri][ci] = v } })
    }
}

// One editable table cell. Wraps like the body text (multi-line), with its own hover highlight,
// and commits its text back to the source when it loses focus.
private struct TableCell: View {
    @Binding var text: String
    let font: Font
    let header: Bool
    let ink: Color
    let accent: Color
    let align: TextAlignment
    let onCommit: () -> Void
    let onMdEdit: () -> Void
    @State private var hover = false
    @FocusState private var focused: Bool
    var body: some View {
        TextField("", text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(font)
            .fontWeight(header ? .semibold : .regular)
            .foregroundColor(ink)
            .multilineTextAlignment(align)
            .focused($focused)
            .onChange(of: focused) { if !$0 { onCommit() } }   // commit on blur (newlines are sanitized to spaces)
            .frame(maxWidth: .infinity, alignment: frameAlignment)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)   // fill row height, equal top/bottom
            .contentShape(Rectangle())
            .overlay(hover ? Rectangle().strokeBorder(accent, lineWidth: 1) : nil)
            .onHover { hover = $0 }
            .simultaneousGesture(TapGesture(count: 2).onEnded(onMdEdit))
    }
    private var frameAlignment: Alignment {
        switch align { case .leading: return .leading; case .center: return .center; case .trailing: return .trailing }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// Hosts rendered table widgets over their (concealed) source lines, full column width.
final class TableLayer {
    weak var textView: NSTextView?
    private var hosts: [(anchor: Int, height: CGFloat, host: NSView)] = []
    func clear() { hosts.forEach { $0.host.removeFromSuperview() }; hosts = [] }
    func add(anchor: Int, height: CGFloat, host: NSView) {
        textView?.addSubview(host)
        hosts.append((anchor, height, host))
    }
    func reposition(ensureLayout: Bool = true) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer, !hosts.isEmpty else { return }
        if ensureLayout { lm.ensureLayout(for: tc) }
        let origin = tv.textContainerOrigin
        let colW = tc.size.width
        let len = (tv.string as NSString).length
        for h in hosts {
            let loc = min(h.anchor, max(0, len - 1))
            let gr = lm.glyphRange(forCharacterRange: NSRange(location: loc, length: 1), actualCharacterRange: nil)
            let frag = lm.lineFragmentRect(forGlyphAt: gr.location, effectiveRange: nil)
            h.host.frame = NSRect(x: origin.x, y: origin.y + frag.minY, width: colW, height: h.height)
        }
    }
}
