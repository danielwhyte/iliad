import SwiftUI
import AppKit
import SwiftTerm

// Terminal that accepts dropped files/folders and types their (shell-quoted) paths at the prompt.
final class DropTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        window?.makeFirstResponder(self)
        send(txt: urls.map { shellQuote($0.path) }.joined(separator: " ") + " ")
        return true
    }

    // Quote a path for the shell only when it contains characters that need it.
    private func shellQuote(_ p: String) -> String {
        if p.range(of: "[^A-Za-z0-9._/@%+=:,-]", options: .regularExpression) == nil { return p }
        return "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// Real VT100 terminal powered by SwiftTerm's LocalProcessTerminalView.
// Runs a login shell over a PTY, so full-screen TUIs (Claude Code, vim, htop)
// render correctly. Themed by the current terminal color scheme.
struct TerminalView: NSViewRepresentable {
    let theme: TermTheme
    let cwd: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let tv = DropTerminalView(frame: NSRect(x: 0, y: 0, width: 700, height: 320))
        apply(tv)

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["TERM_PROGRAM"] = "Iliad"
        let envArr = env.map { "\($0.key)=\($0.value)" }

        tv.startProcess(executable: shell, args: ["-l", "-i"], environment: envArr,
                        execName: nil, currentDirectory: cwd)
        DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        return tv
    }

    func updateNSView(_ tv: LocalProcessTerminalView, context: Context) { apply(tv) }

    private func apply(_ tv: LocalProcessTerminalView) {
        tv.nativeBackgroundColor = theme.bgC
        tv.nativeForegroundColor = theme.fgC
        tv.caretColor = theme.fgC
        if let sel = theme.selC { tv.selectedTextBackgroundColor = sel }
        tv.installColors(theme.ansi.map { st($0) })
        tv.font = NSFont(name: "SF Mono", size: 12.5) ?? NSFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
    }

    private func st(_ hex: String) -> SwiftTerm.Color {
        let c = (NSColor(hex: hex) ?? .gray).usingColorSpace(.sRGB) ?? .gray
        return SwiftTerm.Color(red: UInt16(c.redComponent * 65535),
                               green: UInt16(c.greenComponent * 65535),
                               blue: UInt16(c.blueComponent * 65535))
    }
}
