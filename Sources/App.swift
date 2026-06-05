import SwiftUI
import AppKit

@main
struct IliadApp: App {
    @StateObject private var store = Store()
    @StateObject private var theme = ThemeManager()

    init() { Fonts.register() }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(theme)
                .frame(minWidth: 680, minHeight: 480)
                .onAppear { store.boot() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 920)

        Settings {
            SettingsView().environmentObject(theme)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File") { post("newFile") }.keyboardShortcut("n")
                Button("New Folder") { post("newFolder") }.keyboardShortcut("n", modifiers: [.command, .shift])
                Divider()
                Button("Open Folder…") { post("open") }.keyboardShortcut("o")
                Button("Reveal in Finder") { store.reveal() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { post("save") }.keyboardShortcut("s")
            }
            CommandMenu("View") {
                Button("Toggle Theme") { post("theme") }.keyboardShortcut("d")
                Button("Toggle Sidebar") { post("sidebar") }.keyboardShortcut("0", modifiers: .command)
                Button("Toggle Word Count") { post("stats") }.keyboardShortcut("/", modifiers: .command)
                Divider()
                Button("Focus Mode") { post("focus") }.keyboardShortcut(".", modifiers: .command)
                Button("Typewriter Scrolling") { post("typewriter") }.keyboardShortcut("t", modifiers: .command)
                Button("Zen Mode") { post("zen") }.keyboardShortcut("f", modifiers: [.command, .control])
                Button("Toggle Terminal") { post("terminal") }.keyboardShortcut("j", modifiers: .command)
                Divider()
                Button("Zoom In") { post("zoomIn") }.keyboardShortcut("+", modifiers: .command)
                Button("Zoom Out") { post("zoomOut") }.keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { post("zoomReset") }.keyboardShortcut("0", modifiers: [.command, .control])
            }
        }
    }

    private func post(_ cmd: String) {
        NotificationCenter.default.post(name: .iliadCommand, object: cmd)
    }
}
