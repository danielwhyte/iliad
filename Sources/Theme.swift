import SwiftUI
import AppKit

extension NSColor {
    convenience init(_ rgb: UInt, _ a: CGFloat = 1) {
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xff) / 255,
                  green: CGFloat((rgb >> 8) & 0xff) / 255,
                  blue: CGFloat(rgb & 0xff) / 255, alpha: a)
    }
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.hasPrefix("0x") || s.hasPrefix("0X") { s.removeFirst(2) }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        if s.count == 8 {
            self.init(srgbRed: CGFloat((v >> 24) & 0xff) / 255, green: CGFloat((v >> 16) & 0xff) / 255,
                      blue: CGFloat((v >> 8) & 0xff) / 255, alpha: CGFloat(v & 0xff) / 255)
        } else {
            self.init(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                      blue: CGFloat(v & 0xff) / 255, alpha: 1)
        }
    }
    private var srgb: NSColor { usingColorSpace(.sRGB) ?? self }
    func mix(_ other: NSColor, _ t: CGFloat) -> NSColor {
        let a = srgb, b = other.srgb
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
                       green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: 1)
    }
    var luminance: CGFloat {
        let c = srgb
        return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
    }
}

// GitHub Light / Dark palette (terminalcolors.com/themes/github)
struct Pal {
    let paper, paperEdge, sidebar, ink, inkSoft, inkFaint, accent, rule, selection, insFg, insBg, delFg, delBg: NSColor

    static let light = Pal(
        paper: NSColor(0xffffff), paperEdge: NSColor(0xf6f8fa), sidebar: NSColor(0xf6f8fa),
        ink: NSColor(0x1f2328), inkSoft: NSColor(0x656d76), inkFaint: NSColor(0x8c959f),
        accent: NSColor(0x0969da), rule: NSColor(0x1f2328, 0.12), selection: NSColor(0x0969da, 0.18),
        insFg: NSColor(0x1a7f37), insBg: NSColor(0x1a7f37, 0.12),
        delFg: NSColor(0xcf222e), delBg: NSColor(0xcf222e, 0.10))

    static let dark = Pal(
        paper: NSColor(0x0d1117), paperEdge: NSColor(0x161b22), sidebar: NSColor(0x010409),
        ink: NSColor(0xe6edf3), inkSoft: NSColor(0x848d97), inkFaint: NSColor(0x6e7681),
        accent: NSColor(0x58a6ff), rule: NSColor(0xf0f6fc, 0.10), selection: NSColor(0x264f78),
        insFg: NSColor(0x3fb950), insBg: NSColor(0x3fb950, 0.15),
        delFg: NSColor(0xff7b72), delBg: NSColor(0xff7b72, 0.15))
}

// SwiftUI Color accessors
extension Pal {
    var cPaper: Color { Color(nsColor: paper) }
    var cPaperEdge: Color { Color(nsColor: paperEdge) }
    var cSidebar: Color { Color(nsColor: sidebar) }
    var cInk: Color { Color(nsColor: ink) }
    var cInkSoft: Color { Color(nsColor: inkSoft) }
    var cInkFaint: Color { Color(nsColor: inkFaint) }
    var cAccent: Color { Color(nsColor: accent) }
    var cRule: Color { Color(nsColor: rule) }
    var cInsFg: Color { Color(nsColor: insFg) }
    var cInsBg: Color { Color(nsColor: insBg) }
    var cDelFg: Color { Color(nsColor: delFg) }
    var cDelBg: Color { Color(nsColor: delBg) }
}

// Literata, bundled as variable fonts; weight/optical size via CoreText variations.
enum Fonts {
    static func register() {
        for name in ["Literata", "Literata-Italic"] {
            let url = Bundle.module.url(forResource: name, withExtension: "ttf")
                ?? Bundle.main.url(forResource: name, withExtension: "ttf")
            if let url = url { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }

    private static let wghtAxis = 0x77676874  // 'wght'
    private static let opszAxis = 0x6F70737A  // 'opsz'

    // Apple system faces + Literata (bundled) + classic macOS book faces.
    static let writingFonts = ["Literata", "New York", "San Francisco", "SF Rounded", "SF Mono",
                               "Georgia", "Iowan Old Style", "Palatino", "Charter", "Baskerville",
                               "Hoefler Text", "Cochin", "Times New Roman"]
    static var family = "Literata"

    // Tunable weights (Literata variable `wght` axis); driven by ThemeManager settings.
    static var bodyWeight: CGFloat = 300    // paragraph / body text
    static var titleWeight: CGFloat = 500   // headings
    static let boldWeight: CGFloat = 620    // inline **bold**

    // Line height via interline SPACING (extra gap below each line) rather than lineHeightMultiple,
    // which inflates each line box and floats the caret too high.
    static func paragraph(lineHeight: CGFloat, size: CGFloat) -> NSMutableParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = max(0, (lineHeight - 1) * size)
        return ps
    }

    // `family: nil` uses the app's current font; pass an explicit family (e.g. for Book Mode) to override.
    static func serif(_ size: CGFloat, weight: CGFloat = 400, italic: Bool = false, opticalSize: CGFloat? = nil, family: String? = nil) -> NSFont {
        let fam = family ?? Fonts.family
        switch fam {
        case "Literata":      return literata(size, weight: weight, italic: italic, opticalSize: opticalSize)
        case "New York":      return sysFont(size, weight: weight, italic: italic, design: .serif)
        case "San Francisco": return sysFont(size, weight: weight, italic: italic, design: .default)
        case "SF Rounded":    return sysFont(size, weight: weight, italic: italic, design: .rounded)
        case "SF Mono":
            var d = NSFont.monospacedSystemFont(ofSize: size, weight: weight >= 600 ? .semibold : .regular).fontDescriptor
            if italic { d = d.withSymbolicTraits(.italic) }
            return NSFont(descriptor: d, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        default:
            var traits: NSFontTraitMask = []
            if italic { traits.insert(.italicFontMask) }
            let w = weight >= 600 ? 9 : 5
            return NSFontManager.shared.font(withFamily: fam, traits: traits, weight: w, size: size)
                ?? NSFont(name: fam, size: size) ?? NSFont.systemFont(ofSize: size)
        }
    }

    private static func sysFont(_ size: CGFloat, weight: CGFloat, italic: Bool, design: NSFontDescriptor.SystemDesign) -> NSFont {
        let w: NSFont.Weight = weight >= 600 ? .semibold : .regular
        var d = NSFont.systemFont(ofSize: size, weight: w).fontDescriptor
        if let dd = d.withDesign(design) { d = dd }
        if italic { d = d.withSymbolicTraits(.italic) }
        return NSFont(descriptor: d, size: size) ?? NSFont.systemFont(ofSize: size, weight: w)
    }

    private static func literata(_ size: CGFloat, weight: CGFloat, italic: Bool, opticalSize: CGFloat?) -> NSFont {
        let fam = italic ? "Literata-Italic" : "Literata"
        var variations: [Int: CGFloat] = [wghtAxis: weight]
        variations[opszAxis] = opticalSize ?? size
        let desc = NSFontDescriptor(fontAttributes: [
            .name: fam,
            NSFontDescriptor.AttributeName(kCTFontVariationAttribute as String): variations
        ])
        return NSFont(descriptor: desc, size: size) ?? NSFont.systemFont(ofSize: size)
    }

    static let mono = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    static func monoSized(_ size: CGFloat) -> NSFont { NSFont.monospacedSystemFont(ofSize: size, weight: .regular) }
}
