import SwiftUI
import AppKit

// A terminal color scheme: background, foreground, 16 ANSI colors, optional selection.
struct TermTheme: Identifiable, Codable, Equatable {
    var name: String
    var bg: String
    var fg: String
    var ansi: [String]        // 16 hex strings
    var selection: String?
    var id: String { name }

    func col(_ hex: String) -> NSColor { NSColor(hex: hex) ?? .gray }
    var bgC: NSColor { col(bg) }
    var fgC: NSColor { col(fg) }
    func a(_ i: Int) -> NSColor { col(ansi[min(max(i, 0), 15)]) }
    var selC: NSColor? { selection.flatMap { NSColor(hex: $0) } }
    var isDark: Bool { bgC.luminance < 0.4 }

    // Major colour family, from the theme's most vivid primary color.
    var colorGroup: String {
        let primaries = [1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14].map { a($0) }
        let pick = primaries.max { ($0.usingColorSpace(.sRGB)?.saturationComponent ?? 0) < ($1.usingColorSpace(.sRGB)?.saturationComponent ?? 0) }
        guard let c = pick?.usingColorSpace(.sRGB) else { return "Mono" }
        if c.saturationComponent < 0.12 { return "Mono" }
        let h = c.hueComponent * 360
        switch h {
        case ..<15, 345...: return "Red"
        case 15..<45: return "Orange"
        case 45..<70: return "Yellow"
        case 70..<165: return "Green"
        case 165..<195: return "Cyan"
        case 195..<255: return "Blue"
        case 255..<285: return "Purple"
        default: return "Pink"
        }
    }
}

// Map a terminal theme onto the app palette.
extension Pal {
    init(theme t: TermTheme) {
        let dark = t.isDark
        let bg = t.bgC, fg = t.fgC
        let green = (dark ? t.a(10) : t.a(2))
        let red = (dark ? t.a(9) : t.a(1))
        let blue = (dark ? t.a(12) : t.a(4))
        self.init(
            paper: bg,
            paperEdge: bg.mix(fg, 0.08),
            sidebar: bg.mix(fg, 0.045),
            ink: fg,
            inkSoft: fg.mix(bg, 0.32),
            inkFaint: fg.mix(bg, 0.54),
            accent: blue,
            rule: fg.withAlphaComponent(0.12),
            selection: t.selC ?? blue.withAlphaComponent(dark ? 0.32 : 0.18),
            insFg: green, insBg: green.withAlphaComponent(0.15),
            delFg: red, delBg: red.withAlphaComponent(0.13))
    }
}

enum TermThemes {
    static let builtins: [TermTheme] = [
        TermTheme(name: "GitHub Dark", bg: "#0d1117", fg: "#e6edf3",
                  ansi: ["#484f58","#ff7b72","#3fb950","#d29922","#58a6ff","#bc8cff","#39c5cf","#b1bac4",
                         "#6e7681","#ffa198","#56d364","#e3b341","#79c0ff","#d2a8ff","#56d4dd","#ffffff"],
                  selection: "#264f78"),
        TermTheme(name: "GitHub Light", bg: "#ffffff", fg: "#1f2328",
                  ansi: ["#24292f","#cf222e","#116329","#4d2d00","#0969da","#8250df","#1b7c83","#6e7781",
                         "#57606a","#a40e26","#1a7f37","#633c01","#218bff","#a475f9","#3192aa","#8c959f"],
                  selection: nil),
        TermTheme(name: "Dracula", bg: "#282a36", fg: "#f8f8f2",
                  ansi: ["#21222c","#ff5555","#50fa7b","#f1fa8c","#bd93f9","#ff79c6","#8be9fd","#f8f8f2",
                         "#6272a4","#ff6e6e","#69ff94","#ffffa5","#d6acff","#ff92df","#a4ffff","#ffffff"],
                  selection: "#44475a"),
        TermTheme(name: "Nord", bg: "#2e3440", fg: "#d8dee9",
                  ansi: ["#3b4252","#bf616a","#a3be8c","#ebcb8b","#81a1c1","#b48ead","#88c0d0","#e5e9f0",
                         "#4c566a","#bf616a","#a3be8c","#ebcb8b","#81a1c1","#b48ead","#8fbcbb","#eceff4"],
                  selection: "#434c5e"),
        TermTheme(name: "Solarized Dark", bg: "#002b36", fg: "#839496",
                  ansi: ["#073642","#dc322f","#859900","#b58900","#268bd2","#d33682","#2aa198","#eee8d5",
                         "#002b36","#cb4b16","#586e75","#657b83","#839496","#6c71c4","#93a1a1","#fdf6e3"],
                  selection: "#073642"),
        TermTheme(name: "Solarized Light", bg: "#fdf6e3", fg: "#657b83",
                  ansi: ["#073642","#dc322f","#859900","#b58900","#268bd2","#d33682","#2aa198","#eee8d5",
                         "#002b36","#cb4b16","#586e75","#657b83","#839496","#6c71c4","#93a1a1","#fdf6e3"],
                  selection: "#eee8d5"),
        TermTheme(name: "Gruvbox Dark", bg: "#282828", fg: "#ebdbb2",
                  ansi: ["#282828","#cc241d","#98971a","#d79921","#458588","#b16286","#689d6a","#a89984",
                         "#928374","#fb4934","#b8bb26","#fabd2f","#83a598","#d3869b","#8ec07c","#ebdbb2"],
                  selection: "#3c3836"),
        TermTheme(name: "One Dark", bg: "#282c34", fg: "#abb2bf",
                  ansi: ["#282c34","#e06c75","#98c379","#e5c07b","#61afef","#c678dd","#56b6c2","#abb2bf",
                         "#5c6370","#e06c75","#98c379","#e5c07b","#61afef","#c678dd","#56b6c2","#ffffff"],
                  selection: "#3e4451"),
        TermTheme(name: "Tokyo Night", bg: "#1a1b26", fg: "#c0caf5",
                  ansi: ["#15161e","#f7768e","#9ece6a","#e0af68","#7aa2f7","#bb9af7","#7dcfff","#a9b1d6",
                         "#414868","#f7768e","#9ece6a","#e0af68","#7aa2f7","#bb9af7","#7dcfff","#c0caf5"],
                  selection: "#283457"),
        TermTheme(name: "Catppuccin Mocha", bg: "#1e1e2e", fg: "#cdd6f4",
                  ansi: ["#45475a","#f38ba8","#a6e3a1","#f9e2af","#89b4fa","#f5c2e7","#94e2d5","#bac2de",
                         "#585b70","#f38ba8","#a6e3a1","#f9e2af","#89b4fa","#f5c2e7","#94e2d5","#a6adc8"],
                  selection: "#414458"),
        TermTheme(name: "Monokai", bg: "#272822", fg: "#f8f8f2",
                  ansi: ["#272822","#f92672","#a6e22e","#f4bf75","#66d9ef","#ae81ff","#a1efe4","#f8f8f2",
                         "#75715e","#f92672","#a6e22e","#f4bf75","#66d9ef","#ae81ff","#a1efe4","#f9f8f5"],
                  selection: "#49483e"),
        TermTheme(name: "Everforest Dark", bg: "#2d353b", fg: "#d3c6aa",
                  ansi: ["#475258","#e67e80","#a7c080","#dbbc7f","#7fbbb3","#d699b6","#83c092","#d3c6aa",
                         "#475258","#e67e80","#a7c080","#dbbc7f","#7fbbb3","#d699b6","#83c092","#d3c6aa"],
                  selection: "#414b50"),
    ]

    // ---- persistence of imported themes ----
    private static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Iliad", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    private static var importedFile: URL { supportDir.appendingPathComponent("themes.json") }

    static func loadImported() -> [TermTheme] {
        guard let data = try? Data(contentsOf: importedFile) else { return [] }
        return (try? JSONDecoder().decode([TermTheme].self, from: data)) ?? []
    }

    // The bundled iTerm2-Color-Schemes collection.
    static func loadLibrary() -> [TermTheme] {
        guard let url = Bundle.module.url(forResource: "themes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([TermTheme].self, from: data)) ?? []
    }
    static func saveImported(_ themes: [TermTheme]) {
        if let data = try? JSONEncoder().encode(themes) { try? data.write(to: importedFile) }
    }

    // ---- import / parse common terminal theme formats ----
    static func parse(_ url: URL) -> TermTheme? {
        let name = url.deletingPathExtension().lastPathComponent
        // iTerm2 .itermcolors (plist)
        if let data = try? Data(contentsOf: url),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           plist["Ansi 0 Color"] != nil {
            func comp(_ key: String) -> String? {
                guard let d = plist[key] as? [String: Any],
                      let r = d["Red Component"] as? Double,
                      let g = d["Green Component"] as? Double,
                      let b = d["Blue Component"] as? Double else { return nil }
                return hex(r, g, b)
            }
            var ansi: [String] = []
            for i in 0..<16 { ansi.append(comp("Ansi \(i) Color") ?? "#808080") }
            return TermTheme(name: name, bg: comp("Background Color") ?? "#101010",
                             fg: comp("Foreground Color") ?? "#e0e0e0", ansi: ansi, selection: comp("Selection Color"))
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseText(name, text)
    }

    private static let names = ["black","red","green","yellow","blue","magenta","cyan","white"]

    private static func parseText(_ name: String, _ text: String) -> TermTheme? {
        var bg: String?, fg: String?, sel: String?
        var ansi = [String?](repeating: nil, count: 16)
        var section = ""

        // Ghostty: palette = N=#hex
        for m in regex("(?i)palette\\s*=\\s*(\\d+)\\s*=\\s*(#?[0-9a-fA-F]{6})").matches(in: text, range: nsRange(text)) {
            let ns = text as NSString
            if let idx = Int(ns.substring(with: m.range(at: 1))), idx < 16 {
                ansi[idx] = norm(ns.substring(with: m.range(at: 2)))
            }
        }

        // Cursor / numbered style: color-N = "#hex"  (and bg-color / fg-color handled in the loop)
        for m in regex("(?i)(?:^|\\n)\\s*color[-_ ]?(\\d+)\\s*[=:]\\s*\"?(#?[0-9a-fA-F]{6})").matches(in: text, range: nsRange(text)) {
            let ns = text as NSString
            if let idx = Int(ns.substring(with: m.range(at: 1))), idx < 16, ansi[idx] == nil {
                ansi[idx] = norm(ns.substring(with: m.range(at: 2)))
            }
        }

        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let low = line.lowercased()
            if low.hasPrefix("[") {
                section = low; continue
            }
            if low.hasSuffix(":") && (low.contains("normal") || low.contains("bright")) { section = low; continue }
            guard let h = firstHex(line) else { continue }
            let key = low
            func has(_ s: String) -> Bool { key.contains(s) }
            if has("highlight") {                 // Cursor highlight-bg/fg -> selection
                if has("bg") { sel = sel ?? h }
                continue
            }
            if has("foreground") || has("fg-color") || has("fg_color") { fg = fg ?? h; continue }
            if has("background") || has("bg-color") || has("bg_color") {
                if section.contains("selection") { sel = h } else { bg = bg ?? h }
                continue
            }
            if has("selection") { sel = sel ?? h; continue }
            // named ansi inside a normal/bright section
            let bright = section.contains("bright")
            for (i, nm) in names.enumerated() where has(nm) {
                let idx = bright ? i + 8 : i
                if ansi[idx] == nil { ansi[idx] = h }
                break
            }
        }

        let filled = ansi.compactMap { $0 }.count
        guard bg != nil || fg != nil || filled >= 16 else { return nil }
        return TermTheme(name: name, bg: bg ?? "#101010", fg: fg ?? "#e0e0e0",
                         ansi: ansi.map { $0 ?? "#808080" }, selection: sel)
    }

    private static func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(format: "#%02x%02x%02x", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }
    private static func norm(_ s: String) -> String { s.hasPrefix("#") ? s.lowercased() : "#" + s.lowercased() }
    private static func firstHex(_ s: String) -> String? {
        guard let m = regex("#?[0-9a-fA-F]{6}\\b").firstMatch(in: s, range: nsRange(s)) else { return nil }
        return norm((s as NSString).substring(with: m.range))
    }
}

func nsRange(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

// A small rounded pill showing a theme's palette, for the menu rows.
func themeSwatch(_ t: TermTheme) -> NSImage {
    let w: CGFloat = 50, h: CGFloat = 14
    let img = NSImage(size: NSSize(width: w, height: h))
    img.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: w, height: h)
    let path = NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7)
    path.addClip()
    let cols = [t.bgC, t.a(1), t.a(2), t.a(3), t.a(4), t.a(5), t.fgC]
    let seg = w / CGFloat(cols.count)
    for (i, c) in cols.enumerated() {
        (c.usingColorSpace(.sRGB) ?? c).setFill()
        NSRect(x: CGFloat(i) * seg, y: 0, width: seg + 0.6, height: h).fill()
    }
    NSColor.gray.withAlphaComponent(0.45).setStroke(); path.lineWidth = 1; path.stroke()
    img.unlockFocus()
    img.isTemplate = false
    return img
}

// ----------  Theme manager  ----------
final class ThemeManager: ObservableObject {
    @Published var currentName: String { didSet { UserDefaults.standard.set(currentName, forKey: "IliadTheme") } }
    @Published var imported: [TermTheme]
    @Published var fontName: String {
        didSet { UserDefaults.standard.set(fontName, forKey: "IliadFont"); Fonts.family = fontName }
    }
    @Published var bodyWeight: Double {
        didSet { UserDefaults.standard.set(bodyWeight, forKey: "IliadBodyWeight"); Fonts.bodyWeight = CGFloat(bodyWeight) }
    }
    @Published var headingWeight: Double {
        didSet { UserDefaults.standard.set(headingWeight, forKey: "IliadHeadingWeight"); Fonts.titleWeight = CGFloat(headingWeight) }
    }
    let library: [TermTheme]   // the imported iTerm2 collection

    var builtins: [TermTheme] { TermThemes.builtins }
    var all: [TermTheme] {
        var seen = Set<String>(); var r: [TermTheme] = []
        for t in builtins + library + imported where !seen.contains(t.name) { seen.insert(t.name); r.append(t) }
        return r
    }
    var current: TermTheme { all.first { $0.name == currentName } ?? builtins[0] }
    var pal: Pal { Pal(theme: current) }
    var dark: Bool { current.isDark }

    init() {
        imported = TermThemes.loadImported()
        library = TermThemes.loadLibrary()
        currentName = UserDefaults.standard.string(forKey: "IliadTheme") ?? "GitHub Dark"
        fontName = UserDefaults.standard.string(forKey: "IliadFont") ?? "Literata"
        let bw = UserDefaults.standard.object(forKey: "IliadBodyWeight") as? Double ?? 300
        let hw = UserDefaults.standard.object(forKey: "IliadHeadingWeight") as? Double ?? 500
        bodyWeight = bw
        headingWeight = hw
        Fonts.family = fontName
        Fonts.bodyWeight = CGFloat(bw)
        Fonts.titleWeight = CGFloat(hw)
    }

    func apply(_ name: String) { currentName = name }
    func setFont(_ name: String) { fontName = name }
    func toggle() { currentName = current.isDark ? "GitHub Light" : "GitHub Dark" }

    // The greatest-hits list, in popularity order.
    private static let popularNames = [
        "GitHub Dark", "GitHub Light", "Dracula", "Nord", "Solarized Dark", "Solarized Light",
        "Gruvbox Dark", "Gruvbox Light", "Tokyo Night", "Catppuccin Mocha", "Catppuccin Latte",
        "Catppuccin Frappe", "Monokai", "One Dark", "One Half Dark", "One Half Light", "Tomorrow",
        "Tomorrow Night", "Tomorrow Night Eighties", "Cobalt2", "Material", "Material Darker",
        "Oceanic Next", "Snazzy", "Night Owl", "Ayu", "Ayu Light", "Ayu Mirage", "Everforest Dark",
        "Everforest Dark Hard", "Horizon", "Zenburn", "Wombat", "Spacegray", "Afterglow",
        "Belafonte Night", "Belafonte Day", "Pencil Dark", "Pencil Light", "Builtin Light",
        "Argonaut", "Firewatch", "Molokai", "Seti",
    ]
    func popular(dark: Bool) -> [TermTheme] {
        var r: [TermTheme] = []; var seen = Set<String>()
        for n in Self.popularNames {
            guard !seen.contains(n), let t = all.first(where: { $0.name == n }), t.isDark == dark else { continue }
            seen.insert(n); r.append(t)
            if r.count >= 20 { break }
        }
        return r
    }

    // grouping for the menu: Light/Dark -> colour group -> themes
    func groupNames(dark: Bool) -> [String] {
        let order = ["Mono", "Red", "Orange", "Yellow", "Green", "Cyan", "Blue", "Purple", "Pink"]
        let present = Set(all.filter { $0.isDark == dark }.map { $0.colorGroup })
        return order.filter { present.contains($0) }
    }
    func themes(dark: Bool, group: String) -> [TermTheme] {
        all.filter { $0.isDark == dark && $0.colorGroup == group }.sorted { $0.name < $1.name }
    }

    func importThemes() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Choose terminal theme files (.itermcolors, .toml, .yaml, .conf, Ghostty configs)"
        if panel.runModal() == .OK {
            for url in panel.urls { if let t = TermThemes.parse(url) { addImported(t) } else { NSSound.beep() } }
        }
    }
    func addImported(_ t: TermTheme) {
        imported.removeAll { $0.name == t.name }
        imported.append(t)
        TermThemes.saveImported(imported)
        currentName = t.name
    }
    func removeImported(_ name: String) {
        imported.removeAll { $0.name == name }
        TermThemes.saveImported(imported)
        if currentName == name { currentName = "GitHub Dark" }
    }
}
