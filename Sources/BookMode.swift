import SwiftUI
import AppKit

// ---------------------------------------------------------------------------
// Book Mode: an InDesign-style layout view that typesets the Markdown into real
// facing pages (book trims, mm margins) and exports to PDF. Write Mode stays the
// live editor; Book Mode is a paginated preview + page/typography tools.
// ---------------------------------------------------------------------------

struct BookStyle: Equatable {
    static let mmToPt: CGFloat = 72.0 / 25.4

    enum PageSize: String, CaseIterable, Identifiable {
        case trade = "Trade 150×210", a5 = "A5", digest = "Digest 6×9", pocket = "Pocket 5×8"
        case letter = "US Letter", a4 = "A4"
        var id: String { rawValue }
        var mm: CGSize {   // width × height in millimetres
            switch self {
            case .trade:  return CGSize(width: 150, height: 210)
            case .a5:     return CGSize(width: 148, height: 210)
            case .digest: return CGSize(width: 152.4, height: 228.6)
            case .pocket: return CGSize(width: 127, height: 203.2)
            case .letter: return CGSize(width: 215.9, height: 279.4)
            case .a4:     return CGSize(width: 210, height: 297)
            }
        }
    }

    var page: PageSize = .trade
    var facing: Bool = true
    // margins in millimetres; inside = spine edge, outside = fore-edge
    var marginTop: CGFloat = 20
    var marginBottom: CGFloat = 20
    var marginInside: CGFloat = 20
    var marginOutside: CGFloat = 20
    var bodySize: CGFloat = 12        // points
    var leading: CGFloat = 18         // absolute leading in points (baseline-to-baseline), InDesign-style
    var justified: Bool = true
    var hyphenate: Bool = true
    var indentParagraphs: Bool = true
    var bodyFont: String = "Literata"      // book fonts are independent of the editor's font
    var headingFont: String = "Literata"
    var headingSizes: [CGFloat] = [24, 19, 16, 14, 13, 12]   // h1…h6, points
    // tables
    var tableBorder: CGFloat = 0.75   // border line width, points
    var tablePadding: CGFloat = 5     // cell padding, points
    var tableHeaderBold: Bool = true
    var tableZebra: Bool = true
    func headingSize(_ level: Int) -> CGFloat { headingSizes[max(0, min(level - 1, 5))] }

    var pageW: CGFloat { page.mm.width * Self.mmToPt }
    var pageH: CGFloat { page.mm.height * Self.mmToPt }
    var topPt: CGFloat { marginTop * Self.mmToPt }
    var bottomPt: CGFloat { marginBottom * Self.mmToPt }
    var insidePt: CGFloat { marginInside * Self.mmToPt }
    var outsidePt: CGFloat { marginOutside * Self.mmToPt }
    var contentSize: CGSize { CGSize(width: pageW - insidePt - outsidePt, height: pageH - topPt - bottomPt) }
    // Left margin of a given 1-based page: recto (odd) spine on the left = inside; verso = outside.
    func leftMargin(page n: Int) -> CGFloat { facing ? (n % 2 == 1 ? insidePt : outsidePt) : insidePt }
}

// ---- Markdown -> typeset NSAttributedString (clean: markers removed) ----

enum BookFormatter {
    static func attributed(_ markdown: String, _ s: BookStyle, ink: NSColor, soft: NSColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var para: [String] = []
        var inFence = false
        var firstBlock = true
        var lastWasHeading = false

        func bodyPara(_ joined: String, afterHeading: Bool) -> NSAttributedString {
            let ps = NSMutableParagraphStyle()
            ps.alignment = s.justified ? .justified : .natural
            ps.minimumLineHeight = s.leading; ps.maximumLineHeight = s.leading   // absolute leading
            ps.paragraphSpacing = s.bodySize * 0.2
            ps.hyphenationFactor = s.hyphenate ? 1 : 0   // hyphenate to even out word spacing
            if s.indentParagraphs && !afterHeading { ps.firstLineHeadIndent = s.bodySize * 1.6 }
            let a = inline(joined, base: Fonts.serif(s.bodySize, weight: 400, family: s.bodyFont), ink: ink, soft: soft, size: s.bodySize, family: s.bodyFont)
            a.addAttribute(.ligature, value: 1, range: NSRange(location: 0, length: a.length))   // standard ligatures
            a.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: a.length))
            a.append(NSAttributedString(string: "\n"))
            return a
        }
        func flush() {
            guard !para.isEmpty else { return }
            out.append(bodyPara(para.joined(separator: " "), afterHeading: lastWasHeading))
            lastWasHeading = false; para = []
        }
        var tableBuf: [String] = []
        func flushTable() {
            guard !tableBuf.isEmpty else { return }
            out.append(tableAttributed(tableBuf, s, ink: ink, soft: soft)); tableBuf = []
        }

        for line in lines {
            let isTableRow = !inFence && line.range(of: "^\\s*\\|", options: .regularExpression) != nil
            if !isTableRow { flushTable() }
            if isTableRow { flush(); tableBuf.append(line); firstBlock = false; continue }
            if line.range(of: "^\\s*(```|~~~)", options: .regularExpression) != nil { flush(); inFence.toggle(); continue }
            if inFence {
                let ps = NSMutableParagraphStyle(); ps.lineHeightMultiple = 1.2
                out.append(NSAttributedString(string: line + "\n",
                    attributes: [.font: Fonts.monoSized(s.bodySize * 0.92), .foregroundColor: soft, .paragraphStyle: ps]))
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }

            if let m = regex("^(#{1,6})\\s+(.*)$").firstMatch(in: line, range: nsRange(line)) {
                flush()
                let level = (line as NSString).substring(with: m.range(at: 1)).count
                let text = (line as NSString).substring(with: m.range(at: 2))
                let ps = NSMutableParagraphStyle()
                ps.paragraphSpacingBefore = firstBlock ? 0 : s.bodySize * (level == 1 ? 1.6 : 1.0)
                ps.paragraphSpacing = s.bodySize * 0.5; ps.lineHeightMultiple = 1.1
                let a = inline(text, base: Fonts.serif(s.headingSize(level), weight: 600, family: s.headingFont), ink: ink, soft: soft, size: s.bodySize, family: s.headingFont)
                a.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: a.length))
                a.append(NSAttributedString(string: "\n"))
                out.append(a); lastWasHeading = true; firstBlock = false; continue
            }
            if line.range(of: "^\\s*([-*_])(\\s*\\1){2,}\\s*$", options: .regularExpression) != nil {
                flush()
                let ps = NSMutableParagraphStyle(); ps.alignment = .center
                ps.paragraphSpacingBefore = s.bodySize; ps.paragraphSpacing = s.bodySize
                out.append(NSAttributedString(string: "* * *\n",
                    attributes: [.font: Fonts.serif(s.bodySize, weight: 400), .foregroundColor: soft, .paragraphStyle: ps]))
                continue
            }
            if let m = regex("^\\s*>\\s?(.*)$").firstMatch(in: line, range: nsRange(line)) {
                flush()
                let text = (line as NSString).substring(with: m.range(at: 1))
                let ps = NSMutableParagraphStyle()
                ps.headIndent = s.bodySize * 1.6; ps.firstLineHeadIndent = s.bodySize * 1.6
                ps.minimumLineHeight = s.leading; ps.maximumLineHeight = s.leading; ps.paragraphSpacing = s.bodySize * 0.3
                let a = inline(text, base: Fonts.serif(s.bodySize, weight: 400, italic: true, family: s.bodyFont), ink: soft, soft: soft, size: s.bodySize, family: s.bodyFont)
                a.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: a.length))
                a.append(NSAttributedString(string: "\n")); out.append(a); continue
            }
            if let m = regex("^(\\s*)([-*+]|\\d+\\.)(\\s+)(.*)$").firstMatch(in: line, range: nsRange(line)) {
                flush()
                let indent = (line as NSString).substring(with: m.range(at: 1)).count
                let markerStr = (line as NSString).substring(with: m.range(at: 2))
                var text = (line as NSString).substring(with: m.range(at: 4))
                var bullet = markerStr.hasSuffix(".") ? markerStr + " " : "•  "
                if let t = regex("^\\[([ xX])\\]\\s+(.*)$").firstMatch(in: text, range: nsRange(text)) {
                    let checked = (text as NSString).substring(with: t.range(at: 1)).lowercased() == "x"
                    bullet = checked ? "☑  " : "☐  "
                    text = (text as NSString).substring(with: t.range(at: 2))
                }
                let lead = CGFloat(indent) / 2 * s.bodySize + s.bodySize * 1.4
                let ps = NSMutableParagraphStyle()
                ps.headIndent = lead; ps.firstLineHeadIndent = lead - s.bodySize * 1.4
                ps.minimumLineHeight = s.leading; ps.maximumLineHeight = s.leading; ps.paragraphSpacing = s.bodySize * 0.15
                let a = NSMutableAttributedString(string: bullet, attributes: [.font: Fonts.serif(s.bodySize, weight: 400, family: s.bodyFont), .foregroundColor: soft])
                a.append(inline(text, base: Fonts.serif(s.bodySize, weight: 400, family: s.bodyFont), ink: ink, soft: soft, size: s.bodySize, family: s.bodyFont))
                a.addAttribute(.paragraphStyle, value: ps, range: NSRange(location: 0, length: a.length))
                a.append(NSAttributedString(string: "\n")); out.append(a); firstBlock = false; continue
            }
            para.append(line.trimmingCharacters(in: .whitespaces)); firstBlock = false
        }
        flush(); flushTable()
        return out
    }

    // A real bordered table via NSTextTable (flows through the page layout; honours the table settings).
    static func tableAttributed(_ lines: [String], _ s: BookStyle, ink: NSColor, soft: NSColor) -> NSAttributedString {
        func cells(_ l: String) -> [String] {
            var t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("|") { t.removeFirst() }
            if t.hasSuffix("|") { t.removeLast() }
            return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        func isSep(_ l: String) -> Bool { l.range(of: "^\\s*\\|?[\\s:|-]*-[\\s:|-]*$", options: .regularExpression) != nil }
        var rows: [[String]] = []
        var aligns: [NSTextAlignment] = []
        for (i, l) in lines.enumerated() {
            if i == 1 && isSep(l) {
                aligns = cells(l).map { sep in
                    let lft = sep.hasPrefix(":"), rgt = sep.hasSuffix(":")
                    return (lft && rgt) ? .center : (rgt ? .right : .left)
                }
                continue
            }
            if isSep(l) { continue }
            rows.append(cells(l))
        }
        guard !rows.isEmpty else { return NSAttributedString(string: "") }
        let cols = rows.map { $0.count }.max() ?? 1
        let table = NSTextTable(); table.numberOfColumns = cols
        let border = NSColor(white: 0.45, alpha: 1)
        let out = NSMutableAttributedString()
        for (r, row) in rows.enumerated() {
            let header = r == 0
            for c in 0..<cols {
                let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                block.setValue(100.0 / CGFloat(cols), type: .percentageValueType, for: .width)
                block.setBorderColor(border)
                block.setWidth(s.tableBorder, type: .absoluteValueType, for: .border)
                block.setWidth(s.tablePadding, type: .absoluteValueType, for: .padding)
                if header { block.backgroundColor = NSColor(white: 0.90, alpha: 1) }
                else if s.tableZebra && r % 2 == 1 { block.backgroundColor = NSColor(white: 0.95, alpha: 1) }
                let ps = NSMutableParagraphStyle()
                ps.alignment = c < aligns.count ? aligns[c] : .left
                ps.textBlocks = [block]
                let font = Fonts.serif(s.bodySize * 0.95, weight: (header && s.tableHeaderBold) ? 700 : 400, family: s.bodyFont)
                let text = c < row.count ? row[c] : ""
                out.append(NSAttributedString(string: text + "\n", attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: ps]))
            }
        }
        out.append(NSAttributedString(string: "\n", attributes: [.font: Fonts.serif(s.bodySize * 0.5, weight: 400)]))
        return out
    }

    private static func inline(_ line: String, base: NSFont, ink: NSColor, soft: NSColor, size: CGFloat, family: String = "Literata") -> NSMutableAttributedString {
        let a = NSMutableAttributedString(string: line, attributes: [.font: base, .foregroundColor: ink])
        let bold = Fonts.serif(size, weight: 700, family: family)
        let italic = Fonts.serif(size, weight: 400, italic: true, family: family)
        let mono = Fonts.monoSized(size * 0.92)
        func wrap(_ pattern: String, content: Int, _ attrs: [NSAttributedString.Key: Any]) {
            for m in regex(pattern).matches(in: a.string, range: nsRange(a.string)).reversed() {
                let text = (a.string as NSString).substring(with: m.range(at: content))
                a.replaceCharacters(in: m.range, with: NSAttributedString(string: text, attributes: attrs))
            }
        }
        wrap("`([^`]+)`", content: 1, [.font: mono, .foregroundColor: soft])
        wrap("\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)", content: 1, [.font: base, .foregroundColor: ink])
        wrap("\\*\\*([^*\\n]+)\\*\\*", content: 1, [.font: bold, .foregroundColor: ink])
        wrap("(?<![*\\w])\\*([^*\\n]+)\\*(?![*\\w])", content: 1, [.font: italic, .foregroundColor: ink])
        wrap("(?<![_\\w])_([^_\\n]+)_(?![_\\w])", content: 1, [.font: italic, .foregroundColor: ink])
        wrap("~~([^~\\n]+)~~", content: 1, [.font: base, .foregroundColor: ink, .strikethroughStyle: NSUnderlineStyle.single.rawValue])
        return a
    }
}

// ---- TextKit pagination ----

final class BookLayout {
    let textStorage: NSTextStorage
    let layoutManager = NSLayoutManager()
    private(set) var containers: [NSTextContainer] = []
    let style: BookStyle

    init(_ text: NSAttributedString, _ style: BookStyle) {
        self.style = style
        textStorage = NSTextStorage(attributedString: text)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.usesFontLeading = true
        repeat {
            let c = NSTextContainer(size: style.contentSize)
            c.lineFragmentPadding = 0
            layoutManager.addTextContainer(c)
            containers.append(c)
        } while NSMaxRange(layoutManager.glyphRange(for: containers.last!)) < layoutManager.numberOfGlyphs
            && containers.count < 4000
    }
    var pageCount: Int { containers.count }
}

// ---- Facing-page canvas ----

final class BookPagesView: NSView {
    private var layout: BookLayout?
    var pageGap: CGFloat = 34
    var guideColor = NSColor.systemPurple.withAlphaComponent(0.5)
    var showGuides = true
    override var isFlipped: Bool { true }

    // Keep the layer rasterizing at the screen's pixel density × the zoom, so glyphs stay crisp
    // (SwiftUI hosts us layer-backed; a stale 1× contentsScale is what makes text look soft).
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); fixScale() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); fixScale() }
    func fixScale() {
        guard let layer = layer, let w = window else { return }
        let scale = w.backingScaleFactor * (enclosingScrollView?.magnification ?? 1)
        if abs(layer.contentsScale - scale) > 0.01 { layer.contentsScale = scale; needsDisplay = true }
    }

    // Spread index (0-based) and which half a 1-based page occupies (recto = right).
    private func place(_ n: Int) -> (spread: Int, recto: Bool) {
        let recto = n % 2 == 1
        return (n == 1 ? 0 : n / 2, recto)
    }

    func render(_ layout: BookLayout) {
        self.layout = layout
        let s = layout.style
        let lastSpread = layout.pageCount <= 1 ? 0 : layout.pageCount / 2
        let rows = s.facing ? lastSpread + 1 : layout.pageCount
        setFrameSize(NSSize(width: s.facing ? s.pageW * 2 : s.pageW,
                            height: CGFloat(rows) * (s.pageH + pageGap) + pageGap))
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let layout = layout else { return }
        let s = layout.style
        let lm = layout.layoutManager
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setShouldAntialias(true); ctx.setShouldSmoothFonts(true)   // fuller, crisper glyphs on the white page

        if !s.facing {
            for (i, c) in layout.containers.enumerated() {
                let page = NSRect(x: 0, y: pageGap + CGFloat(i) * (s.pageH + pageGap), width: s.pageW, height: s.pageH)
                paper(ctx, page); content(lm, c, n: i + 1, page: page, left: s.leftMargin(page: i + 1), s: s, ctx: ctx)
            }
            return
        }
        let pages = layout.pageCount
        let lastSpread = pages <= 1 ? 0 : pages / 2
        for spread in 0...lastSpread {
            let pageY = pageGap + CGFloat(spread) * (s.pageH + pageGap)
            let versoN = spread == 0 ? 0 : 2 * spread
            let rectoN = spread == 0 ? 1 : 2 * spread + 1
            let hasVerso = versoN >= 1 && versoN <= pages, hasRecto = rectoN >= 1 && rectoN <= pages
            // One sheet for the whole spread (so there is no shadow in the gutter, only the outer edge).
            let sheetX: CGFloat = hasVerso ? 0 : s.pageW
            let sheetW: CGFloat = (hasVerso && hasRecto) ? s.pageW * 2 : s.pageW
            paper(ctx, NSRect(x: sheetX, y: pageY, width: sheetW, height: s.pageH))
            // The spine: a single black hairline down the centre of a full spread.
            if hasVerso && hasRecto {
                ctx.saveGState(); NSColor.black.setStroke(); ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: s.pageW, y: pageY)); ctx.addLine(to: CGPoint(x: s.pageW, y: pageY + s.pageH))
                ctx.strokePath(); ctx.restoreGState()
            }
            if hasVerso { content(lm, layout.containers[versoN - 1], n: versoN, page: NSRect(x: 0, y: pageY, width: s.pageW, height: s.pageH), left: s.leftMargin(page: versoN), s: s, ctx: ctx) }
            if hasRecto { content(lm, layout.containers[rectoN - 1], n: rectoN, page: NSRect(x: s.pageW, y: pageY, width: s.pageW, height: s.pageH), left: s.leftMargin(page: rectoN), s: s, ctx: ctx) }
        }
    }

    private func paper(_ ctx: CGContext, _ rect: NSRect) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 11, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        NSColor.white.setFill(); rect.fill()
        ctx.restoreGState()
    }
    private func content(_ lm: NSLayoutManager, _ c: NSTextContainer, n: Int, page: NSRect, left: CGFloat, s: BookStyle, ctx: CGContext) {
        let box = NSRect(x: page.minX + left, y: page.minY + s.topPt, width: s.contentSize.width, height: s.contentSize.height)
        if showGuides {
            ctx.saveGState(); guideColor.setStroke(); ctx.setLineWidth(0.5); ctx.stroke(box.insetBy(dx: 0.25, dy: 0.25)); ctx.restoreGState()
        }
        lm.drawGlyphs(forGlyphRange: lm.glyphRange(for: c), at: NSPoint(x: box.minX, y: box.minY))
        BookPDF.drawFolio(n, page: page, s: s)
    }
}

// Keeps the pages centered in the scroll view when they're smaller than the viewport.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        if doc.frame.width < rect.width { rect.origin.x = (doc.frame.width - rect.width) / 2 }
        if doc.frame.height < rect.height { rect.origin.y = (doc.frame.height - rect.height) / 2 }
        return rect
    }
}

struct BookCanvas: NSViewRepresentable {
    let markdown: String
    let style: BookStyle
    let pal: Pal
    let zoom: CGFloat
    let showGuides: Bool

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.contentView = CenteringClipView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.drawsBackground = true
        scroll.allowsMagnification = true
        scroll.documentView = BookPagesView()
        // Re-rasterize crisply after a pinch-zoom settles.
        context.coordinator.token = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: scroll, queue: .main) { _ in
            (scroll.documentView as? BookPagesView)?.fixScale()
        }
        rebuild(scroll)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) { rebuild(scroll) }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var token: Any?; deinit { if let t = token { NotificationCenter.default.removeObserver(t) } } }

    private func rebuild(_ scroll: NSScrollView) {
        scroll.backgroundColor = pal.paperEdge
        if abs(scroll.magnification - zoom) > 0.001 { scroll.magnification = zoom }
        guard let pages = scroll.documentView as? BookPagesView else { return }
        pages.showGuides = showGuides
        let attr = BookFormatter.attributed(markdown, style, ink: .black, soft: NSColor(white: 0.35, alpha: 1))
        pages.render(BookLayout(attr, style))   // CenteringClipView keeps it centered
        pages.fixScale()                          // keep rasterization at screen × zoom resolution
    }
}

// ---- PDF export (single pages, mirror margins) ----

enum BookPDF {
    // Centered page number ("folio") in the bottom margin. Works in any current (flipped) context.
    static func drawFolio(_ n: Int, page: NSRect, s: BookStyle) {
        let str = NSAttributedString(string: "\(n)", attributes: [
            .font: Fonts.serif(s.bodySize * 0.85, weight: 400), .foregroundColor: NSColor.black])
        let sz = str.size()
        str.draw(at: NSPoint(x: page.midX - sz.width / 2, y: page.maxY - s.bottomPt + (s.bottomPt - sz.height) / 2))
    }

    static func write(_ markdown: String, _ style: BookStyle, to url: URL) {
        let attr = BookFormatter.attributed(markdown, style, ink: .black, soft: NSColor(white: 0.35, alpha: 1))
        let layout = BookLayout(attr, style)
        let data = NSMutableData()
        var media = CGRect(x: 0, y: 0, width: style.pageW, height: style.pageH)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &media, nil) else { return }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        for (i, c) in layout.containers.enumerated() {
            ctx.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = ns
            ctx.translateBy(x: 0, y: style.pageH)   // PDF origin bottom-left; flip to draw top-down
            ctx.scaleBy(x: 1, y: -1)
            let gr = layout.layoutManager.glyphRange(for: c)
            layout.layoutManager.drawGlyphs(forGlyphRange: gr, at: NSPoint(x: style.leftMargin(page: i + 1), y: style.topPt))
            drawFolio(i + 1, page: NSRect(x: 0, y: 0, width: style.pageW, height: style.pageH), s: style)
            NSGraphicsContext.restoreGraphicsState()
            ctx.endPDFPage()
        }
        ctx.closePDF()
        data.write(to: url, atomically: true)
    }
}

// ---- Per-folder config persisted as book.yaml at the library root ----

extension BookStyle {
    func yaml() -> String {
        """
        # Iliad — book layout for this folder. Edit here or in Book Mode. Margins in mm.
        page: \(page.rawValue)
        facing: \(facing)
        marginTop: \(trim(marginTop))
        marginBottom: \(trim(marginBottom))
        marginInside: \(trim(marginInside))
        marginOutside: \(trim(marginOutside))
        bodySize: \(trim(bodySize))
        leading: \(trim(leading))
        justified: \(justified)
        hyphenate: \(hyphenate)
        indentParagraphs: \(indentParagraphs)
        headingSizes: \(headingSizes.map { trim($0) }.joined(separator: ","))
        tableBorder: \(trim(tableBorder))
        tablePadding: \(trim(tablePadding))
        tableHeaderBold: \(tableHeaderBold)
        tableZebra: \(tableZebra)
        bodyFont: \(bodyFont)
        headingFont: \(headingFont)
        """
    }
    init(yaml: String) {
        self.init()
        for line in yaml.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.hasPrefix("#"), let c = t.firstIndex(of: ":") else { continue }
            let key = String(t[..<c]).trimmingCharacters(in: .whitespaces)
            let v = String(t[t.index(after: c)...]).trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'"))
            switch key {
            case "page": if let p = PageSize(rawValue: v) { page = p }
            case "facing": facing = (v == "true")
            case "marginTop": if let d = Double(v) { marginTop = CGFloat(d) }
            case "marginBottom": if let d = Double(v) { marginBottom = CGFloat(d) }
            case "marginInside": if let d = Double(v) { marginInside = CGFloat(d) }
            case "marginOutside": if let d = Double(v) { marginOutside = CGFloat(d) }
            case "bodySize": if let d = Double(v) { bodySize = CGFloat(d) }
            case "leading": if let d = Double(v) { leading = CGFloat(d) }
            case "justified": justified = (v == "true")
            case "hyphenate": hyphenate = (v == "true")
            case "indentParagraphs": indentParagraphs = (v == "true")
            case "headingSizes":
                let nums = v.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)).map { CGFloat($0) } }
                if nums.count == 6 { headingSizes = nums }
            case "tableBorder": if let d = Double(v) { tableBorder = CGFloat(d) }
            case "tablePadding": if let d = Double(v) { tablePadding = CGFloat(d) }
            case "tableHeaderBold": tableHeaderBold = (v == "true")
            case "tableZebra": tableZebra = (v == "true")
            case "bodyFont": bodyFont = v
            case "headingFont": headingFont = v
            default: break
            }
        }
        if leading < 4 { leading = (leading * bodySize).rounded() }   // migrate old multiplier leading -> points
    }
    private func trim(_ v: CGFloat) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.2f", v) }
}

enum BookConfig {
    static func url(_ root: URL) -> URL { root.appendingPathComponent("book.yaml") }
    static func load(_ root: URL?) -> BookStyle {
        guard let root, let s = try? String(contentsOf: url(root), encoding: .utf8) else { return BookStyle() }
        return BookStyle(yaml: s)
    }
    static func save(_ style: BookStyle, _ root: URL?) {
        guard let root else { return }
        try? style.yaml().write(to: url(root), atomically: true, encoding: .utf8)
    }
    static func exists(_ root: URL?) -> Bool {
        guard let root else { return false }
        return FileManager.default.fileExists(atPath: url(root).path)
    }
}

// ---------------------------------------------------------------------------
// Book Mode UI
// ---------------------------------------------------------------------------

struct BookModeView: View {
    let markdown: String
    let pal: Pal
    let root: URL?
    @State private var style = BookStyle()
    @State private var zoom: CGFloat = 1.0
    @State private var tab = 0
    @AppStorage("iliad.book.showGuides") private var showGuides = true

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                BookCanvas(markdown: markdown, style: style, pal: pal, zoom: zoom, showGuides: showGuides)
                zoomControl.padding(.leading, 14).padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            inspector.frame(width: 268).background(pal.cSidebar)
        }
        .onAppear {
            style = BookConfig.load(root)
            if !BookConfig.exists(root) { BookConfig.save(style, root) }
        }
        .onChange(of: style) { BookConfig.save($0, root) }
        .onReceive(NotificationCenter.default.publisher(for: .iliadCommand)) { note in
            switch note.object as? String {            // ⌘+ / ⌘- / ⌘0 zoom the spread in Book Mode
            case "zoomIn":    zoom = min(4, zoom + 0.1)
            case "zoomOut":   zoom = max(0.25, zoom - 0.1)
            case "zoomReset": zoom = 1.0
            default: break
            }
        }
    }

    var pageCount: Int { BookLayout(BookFormatter.attributed(markdown, style, ink: .black, soft: .gray), style).pageCount }

    // Bottom-left zoom bar, matching the top-right toolbar bubbles.
    var zoomControl: some View {
        HStack(spacing: 2) {
            zoomBtn("minus") { zoom = max(0.25, zoom - 0.1) }
            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium)).foregroundColor(pal.cInkSoft)
                .frame(width: 42)
            zoomBtn("plus") { zoom = min(4, zoom + 0.1) }
            Rectangle().fill(pal.cRule).frame(width: 1, height: 16).padding(.horizontal, 2)
            zoomBtn("1.magnifyingglass") { zoom = 1.0 }
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(pal.cRule, lineWidth: 1))
    }
    func zoomBtn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13))
                .frame(width: 28, height: 24).foregroundColor(pal.cInkSoft).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    private func dbl(_ kp: WritableKeyPath<BookStyle, CGFloat>) -> Binding<Double> {
        Binding(get: { Double(style[keyPath: kp]) }, set: { style[keyPath: kp] = CGFloat($0) })
    }

    var inspector: some View {
        VStack(spacing: 0) {
            IconTabs(selection: $tab, tabs: [
                ("doc", "Page"), ("textformat", "Text"), ("tablecells", "Tables"), ("square.and.arrow.up", "Export")
            ], pal: pal)
            .padding(.top, 32).padding(.bottom, 10).padding(.horizontal, 12)
            .overlay(Rectangle().frame(height: 1).foregroundColor(pal.cRule), alignment: .bottom)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch tab {
                    case 0: pageTab
                    case 1: textTab
                    case 2: tablesTab
                    default: exportTab
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
            }
        }
    }

    var pageTab: some View {
        Group {
            section("PAGE") {
                labeled("Size") {
                    Picker("", selection: $style.page) {
                        ForEach(BookStyle.PageSize.allCases) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 130)
                }
                Toggle("Facing pages", isOn: $style.facing).controlSize(.small)
                Toggle("Show margins", isOn: $showGuides).controlSize(.small)
            }
            section("MARGINS") {
                slider("Top", dbl(\.marginTop), 0...40, unit: "mm")
                slider("Bottom", dbl(\.marginBottom), 0...40, unit: "mm")
                slider("Inside", dbl(\.marginInside), 0...40, unit: "mm")
                slider("Outside", dbl(\.marginOutside), 0...40, unit: "mm")
            }
        }
    }

    var textTab: some View {
        Group {
            section("PARAGRAPH") {
                fontPicker($style.bodyFont)
                slider("Size", dbl(\.bodySize), 8...18, unit: "pt")
                slider("Leading", dbl(\.leading), 6...48, unit: "pt", decimals: 1)
                Toggle("Justify text", isOn: $style.justified).controlSize(.small)
                Toggle("Hyphenate", isOn: $style.hyphenate).controlSize(.small)
                Toggle("Indent paragraphs", isOn: $style.indentParagraphs).controlSize(.small)
            }
            section("HEADINGS") {
                fontPicker($style.headingFont)
                ForEach(0..<6, id: \.self) { i in
                    slider("H\(i + 1)", headingBinding(i), 9...48, unit: "pt")
                }
            }
        }
    }

    var tablesTab: some View {
        section("TABLE") {
            slider("Border", dbl(\.tableBorder), 0...3, unit: "pt", decimals: 2)
            slider("Cell padding", dbl(\.tablePadding), 0...14, unit: "pt")
            Toggle("Bold header row", isOn: $style.tableHeaderBold).controlSize(.small)
            Toggle("Zebra rows", isOn: $style.tableZebra).controlSize(.small)
        }
    }

    var exportTab: some View {
        section("EXPORT") {
            Text("\(pageCount) page\(pageCount == 1 ? "" : "s")")
                .font(.system(size: 11)).foregroundColor(pal.cInkFaint)
            Button(action: exportPDF) {
                HStack { Image(systemName: "arrow.down.doc"); Text("Export PDF…") }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(pal.cAccent, in: RoundedRectangle(cornerRadius: 7))
                    .foregroundColor(.white)
            }.buttonStyle(.plain)
        }
    }

    private func headingBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { Double(style.headingSizes[i]) }, set: { style.headingSizes[i] = CGFloat($0) })
    }

    // Every font family installed on the system (plus bundled Literata).
    static let systemFonts: [String] = {
        var fams = NSFontManager.shared.availableFontFamilies
        if !fams.contains("Literata") { fams.append("Literata") }
        return fams.sorted()
    }()
    func fontPicker(_ binding: Binding<String>) -> some View {
        Picker("", selection: binding) {
            ForEach(Self.systemFonts, id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden().frame(maxWidth: .infinity).controlSize(.small)
    }

    @ViewBuilder func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 10, weight: .bold)).tracking(0.8).foregroundColor(pal.cInkFaint)
            content()
        }
    }
    @ViewBuilder func labeled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        HStack { Text(label).font(.system(size: 12)).foregroundColor(pal.cInkSoft); Spacer(); content() }
    }
    @ViewBuilder func slider(_ label: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, unit: String, decimals: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Text(label).font(.system(size: 12)).foregroundColor(pal.cInkSoft)
                Spacer()
                NumberBox(value: value, range: range, decimals: decimals, pal: pal)
                if !unit.isEmpty { Text(unit).font(.system(size: 11)).foregroundColor(pal.cInkFaint).frame(width: 18, alignment: .leading) }
            }
            Slider(value: value, in: range).controlSize(.small)
        }
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]; panel.nameFieldStringValue = "Book.pdf"
        panel.begin { resp in
            guard resp == .OK, let url = panel.url else { return }
            BookPDF.write(markdown, style, to: url); NSWorkspace.shared.open(url)
        }
    }
}

// An editable number field that rejects out-of-range input with the standard shake + beep.
struct NumberBox: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let decimals: Int
    let pal: Pal
    @State private var text = ""
    @State private var shake: CGFloat = 0
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain).font(.system(size: 11, weight: .medium))
            .multilineTextAlignment(.trailing).foregroundColor(pal.cInkSoft)
            .frame(width: 38).padding(.horizontal, 5).padding(.vertical, 2)
            .background(pal.cPaperEdge, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(pal.cRule, lineWidth: 1))
            .focused($focused)
            .modifier(Shake(animatableData: shake))
            .onSubmit(commit)
            .onChange(of: focused) { if !$0 { commit() } }
            .onAppear { text = fmt(value) }
            .onChange(of: value) { if !focused { text = fmt($0) } }
    }
    private func commit() {
        if let v = Double(text.trimmingCharacters(in: .whitespaces)), range.contains(v) {
            value = v; text = fmt(v)
        } else {                                   // out of range -> reject the macOS way
            NSSound.beep()
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
            text = fmt(value)
        }
    }
    private func fmt(_ v: Double) -> String { decimals == 0 ? String(Int(v.rounded())) : String(format: "%.\(decimals)f", v) }
}

// The classic side-to-side "no" shake.
struct Shake: GeometryEffect {
    var travel: CGFloat = 6
    var shakes: CGFloat = 3
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * shakes * 2), y: 0))
    }
}
