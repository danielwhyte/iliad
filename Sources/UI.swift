import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Loads a dropped item-provider's path string and moves it into `folder` on the main actor.
func handleSidebarDrop(_ providers: [NSItemProvider], into folder: String, store: Store) -> Bool {
    guard let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
    p.loadObject(ofClass: NSString.self) { obj, _ in
        guard let s = obj as? String else { return }
        DispatchQueue.main.async { _ = store.move(s, into: folder) }
    }
    return true
}

// ----------  Native vibrant material (Xcode/Finder-style sidebar)  ----------
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = 0
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .followsWindowActiveState
        apply(v)
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
        apply(v)
    }
    private func apply(_ v: NSVisualEffectView) {
        guard cornerRadius > 0 else { return }
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.cornerCurve = .continuous
        v.layer?.masksToBounds = true
    }
}

// ----------  Sidebar tree model  ----------
final class TNode {
    var name = ""
    var path = ""
    var dirs: [String: TNode] = [:]
    var files: [DocMeta] = []
}
func buildTree(folders: [String], files: [DocMeta]) -> TNode {
    let root = TNode()
    func node(_ path: String) -> TNode {
        if path.isEmpty { return root }
        var cur = root
        var acc = ""
        for part in path.split(separator: "/").map(String.init) {
            acc = acc.isEmpty ? part : acc + "/" + part
            if cur.dirs[part] == nil { let n = TNode(); n.name = part; n.path = acc; cur.dirs[part] = n }
            cur = cur.dirs[part]!
        }
        return cur
    }
    for f in folders { _ = node(f) }
    for file in files { node(file.folder).files.append(file) }
    return root
}

// ----------  Sidebar  ----------
struct SidebarView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeManager
    @State private var rootDrop = false
    var pal: Pal { theme.pal }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.hasFolder ? store.rootName.uppercased() : "NO FOLDER")
                    .font(.system(size: 11).weight(.semibold))
                    .tracking(0.4)
                    .foregroundColor(pal.cInkFaint).lineLimit(1)
                    .onTapGesture { store.openFolderPanel() }
                Spacer()
                Button(action: { store.openFolderPanel() }) { Image(systemName: "folder").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundColor(pal.cInkFaint).help("Open folder (⌘O)")
                Button(action: { store.newFolder() }) { Image(systemName: "folder.badge.plus").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundColor(pal.cInkFaint).help("New folder (⇧⌘N)")
                    .disabled(!store.hasFolder)
                Button(action: { store.newFile() }) { Image(systemName: "square.and.pencil").font(.system(size: 11.5)) }
                    .buttonStyle(.plain).foregroundColor(pal.cInkFaint).help("New Markdown file (⌘N)")
                    .disabled(!store.hasFolder)
            }
            .padding(.top, 30).padding(.horizontal, 14).padding(.bottom, 6)

            ScrollView {
                let root = buildTree(folders: store.folders, files: store.files)
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(root.files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) { FileRow(meta: $0) }
                    ForEach(root.dirs.keys.sorted(), id: \.self) { key in
                        FolderRow(node: root.dirs[key]!)
                    }
                    if !store.hasFolder {
                        Text("Open a folder to read its files.")
                            .font(.system(size: 12)).italic()
                            .foregroundColor(pal.cInkFaint).padding(14)
                    } else if store.files.isEmpty && store.folders.isEmpty {
                        Text("This folder has no text or Markdown files.")
                            .font(.system(size: 12)).italic()
                            .foregroundColor(pal.cInkFaint).padding(14)
                    }
                }
                .padding(.horizontal, 6).padding(.bottom, 12)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
                .contentShape(Rectangle())
            }
            .onDrop(of: [.text], isTargeted: $rootDrop) { handleSidebarDrop($0, into: "", store: store) }
            .overlay(rootDrop ? RoundedRectangle(cornerRadius: 8).strokeBorder(pal.cAccent.opacity(0.4), lineWidth: 1.5).padding(4) : nil)

            HStack {
                Button("Open…") { store.openFolderPanel() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(pal.cInkFaint)
                    .help("Open a different folder (⌘O)")
                Spacer()
                if store.hasFolder {
                    Button("\(store.files.count) \(store.files.count == 1 ? "file" : "files")") { store.reveal() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundColor(pal.cInkFaint)
                        .help("Reveal in Finder")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(pal.cRule), alignment: .top)
        }
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background {
            VisualEffectView(material: .sidebar, cornerRadius: 13)
                .overlay(pal.cSidebar.opacity(0.9))   // ~90% opaque: keeps a hint of vibrancy, hides the desktop
        }
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(pal.cRule.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 6)
        .padding(.top, 6)
        .padding(.leading, 12)
        .padding(.bottom, 12)
        .padding(.trailing, 4)
    }
}

struct FolderRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeManager
    let node: TNode
    @State private var hover = false
    @State private var renaming = false
    @State private var renameValue = ""
    @State private var dropTargeted = false
    @State private var lastTap = Date.distantPast
    @FocusState private var fieldFocused: Bool
    var pal: Pal { theme.pal }
    var collapsed: Bool { store.collapsed.contains(node.path) }

    var crumb: String {
        let parts = node.path.split(separator: "/").map(String.init)
        return parts.dropLast().joined(separator: " ▸ ")
    }

    private func startRename() { renameValue = node.name; renaming = true }
    private func commitRename() {
        guard renaming else { return }
        renaming = false
        let v = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty && v != node.name { store.renameFolder(node.path, to: v) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold)).foregroundColor(pal.cInkFaint)
                    .rotationEffect(.degrees(collapsed ? 0 : 90)).frame(width: 9)
                Image(systemName: "book.closed.fill").font(.system(size: 10.5)).foregroundColor(.orange)
                if renaming {
                    TextField("", text: $renameValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12).weight(.medium))
                        .foregroundColor(pal.cInk)
                        .focused($fieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { renaming = false }
                        .fixedSize()
                } else {
                    Text(node.name).font(.system(size: 12).weight(.medium))
                        .foregroundColor(pal.cInk).lineLimit(1)
                    if !crumb.isEmpty {
                        Text(crumb).font(.system(size: 10)).foregroundColor(pal.cInkFaint).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if hover {
                    Button(action: {
                        if !store.deleteFolder(node.path) { NSSound.beep() }
                    }) { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.plain).foregroundColor(pal.cInkFaint)
                } else if !node.files.isEmpty {
                    Text("\(node.files.count)").font(.system(size: 10.5)).foregroundColor(pal.cInkFaint)
                }
            }
            .padding(.vertical, 2.5).padding(.horizontal, 5)
            .background(RoundedRectangle(cornerRadius: 5).fill(dropTargeted ? pal.cAccent.opacity(0.25) : (store.selectedFolder == node.path ? pal.cAccent.opacity(0.12) : .clear)))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .onDrag { NSItemProvider(object: node.path as NSString) }
            .onDrop(of: [.text], isTargeted: $dropTargeted) { handleSidebarDrop($0, into: node.path, store: store) }
            .onTapGesture {   // immediate single tap; double = rename
                let now = Date()
                if now.timeIntervalSince(lastTap) < 0.3 {
                    startRename()
                } else {
                    store.selectedFolder = node.path; store.toggleCollapse(node.path)
                }
                lastTap = now
            }
            .onChange(of: renaming) { if $0 { DispatchQueue.main.async { fieldFocused = true } } }
            .onChange(of: fieldFocused) { if !$0 { commitRename() } }
            .contextMenu {
                Button("New File") { store.selectedFolder = node.path; store.newFile() }
                Button("New Folder") { store.selectedFolder = node.path; store.newFolder() }
                Divider()
                Button("Rename…") { startRename() }
                Button("Paste") { store.pasteInto(node.path) }.disabled(!store.canPaste)
                Button("Reveal in Finder") { store.revealItem(node.path) }
                Divider()
                Button("Delete", role: .destructive) { if !store.deleteFolder(node.path) { NSSound.beep() } }
            }

            if !collapsed {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(node.files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }) { FileRow(meta: $0) }
                    ForEach(node.dirs.keys.sorted(), id: \.self) { key in FolderRow(node: node.dirs[key]!) }
                }
                .padding(.leading, 13)
            }
        }
    }
}

struct FileRow: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeManager
    let meta: DocMeta
    @State private var hover = false
    @State private var confirmDelete = false
    @State private var renaming = false
    @State private var renameValue = ""
    @State private var lastTap = Date.distantPast
    @FocusState private var fieldFocused: Bool
    var pal: Pal { theme.pal }
    var active: Bool { meta.path == store.currentPath }

    private func startRename() { renameValue = displayName; renaming = true }
    private func commitRename() {
        guard renaming else { return }
        renaming = false
        let v = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !v.isEmpty && v != displayName { store.rename(meta.path, to: v) }
    }

    private var displayName: String {
        let f = (meta.path as NSString).lastPathComponent
        return (f as NSString).deletingPathExtension
    }
    private var ext: String {
        let e = (meta.path as NSString).pathExtension
        return e.isEmpty ? "" : "." + e
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.text").font(.system(size: 11)).foregroundColor(active ? pal.cAccent : pal.cInkFaint).frame(width: 14)
            if renaming {
                HStack(spacing: 0) {
                    TextField("", text: $renameValue)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12).weight(.medium))
                        .foregroundColor(pal.cInk)
                        .focused($fieldFocused)
                        .onSubmit { commitRename() }
                        .onExitCommand { renaming = false }
                        .fixedSize()
                    Text(ext).font(.system(size: 12)).foregroundColor(pal.cInkFaint)
                }
            } else {
                (Text(displayName).font(.system(size: 12).weight(active ? .medium : .regular)).foregroundColor(active ? pal.cAccent : pal.cInk)
                 + Text(ext).font(.system(size: 12)).foregroundColor(pal.cInkFaint))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if meta.pending {
                Circle().fill(pal.cAccent).frame(width: 5, height: 5)
            }
            if hover {
                Button(action: { confirmDelete = true }) { Image(systemName: "xmark").font(.system(size: 9)) }
                    .buttonStyle(.plain).foregroundColor(pal.cInkFaint)
            }
        }
        .padding(.vertical, 2.5).padding(.horizontal, 5)
        .background(RoundedRectangle(cornerRadius: 5).fill(active ? pal.cAccent.opacity(0.15) : (hover ? pal.cInk.opacity(0.05) : .clear)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onDrag { NSItemProvider(object: meta.path as NSString) }
        .onTapGesture {   // single tap acts immediately (no double-tap disambiguation lag); double = rename
            let now = Date()
            if now.timeIntervalSince(lastTap) < 0.3 {
                startRename()
            } else {
                store.selectedFolder = meta.folder
                if meta.path != store.currentPath { store.open(meta.path) }
            }
            lastTap = now
        }
        .onChange(of: renaming) { if $0 { DispatchQueue.main.async { fieldFocused = true } } }
        .onChange(of: fieldFocused) { if !$0 { commitRename() } }
        .contextMenu {
            Button("Open") { store.open(meta.path) }
            Button("Rename…") { startRename() }
            Button("Duplicate") { store.duplicate(meta.path) }
            Divider()
            Button("Copy") { store.copyToPasteboard(meta.path) }
            Button("Paste") { store.pasteInto(meta.folder) }.disabled(!store.canPaste)
            Button("Reveal in Finder") { store.revealItem(meta.path) }
            Divider()
            Button("Delete", role: .destructive) { confirmDelete = true }
        }
        .confirmationDialog("Delete “\(meta.title.isEmpty ? "Untitled" : meta.title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete File", role: .destructive) { store.delete(meta.path) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes \(meta.path).")
        }
    }
    func fmtDate(_ ms: Double) -> String {
        if ms == 0 { return "" }
        let diff = Date().timeIntervalSince1970 - ms / 1000
        if diff < 60 { return "just now" }
        if diff < 3600 { return "\(Int(diff / 60))m ago" }
        if diff < 86400 { return "\(Int(diff / 3600))h ago" }
        let df = DateFormatter(); df.dateFormat = "MMM d"
        return df.string(from: Date(timeIntervalSince1970: ms / 1000))
    }
}

// ----------  Status bar  ----------
struct StatusBar: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeManager
    var pal: Pal { theme.pal }
    var body: some View {
        HStack(spacing: 18) {
            Text("\(store.stats.words) words")
            Circle().fill(pal.cInkFaint).frame(width: 3, height: 3)
            Text("\(store.stats.chars) characters")
            Circle().fill(pal.cInkFaint).frame(width: 3, height: 3)
            Text("\(store.stats.read) min read")
            if store.saving {
                Circle().fill(pal.cInkFaint).frame(width: 3, height: 3)
                Text("saving…").foregroundColor(pal.cAccent)
            }
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(pal.cInkFaint)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(pal.cPaper.opacity(0.82))
    }
}

// ----------  Inline diff (per-paragraph, glass controls)  ----------
struct InlineDiffView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeManager
    let review: Review
    let fontSize: Double
    let lineHeight: Double
    let measure: Double
    var pal: Pal { theme.pal }
    private var font: Font { .custom(theme.fontName == "Literata" ? "Literata" : theme.fontName, size: CGFloat(fontSize)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(review.blocks) { blk in
                    if blk.changed { changeRow(blk) }
                    else if !blk.oldText.isEmpty {
                        Text(blk.oldText).font(font).foregroundColor(pal.cInk)
                            .lineSpacing(CGFloat(fontSize) * (lineHeight - 1))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(width: CGFloat(measure), alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(.top, 64).padding(.bottom, 80)
        }
        .background(pal.cPaper)
    }

    func changeRow(_ blk: DiffBlock) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                if !blk.oldText.isEmpty {
                    Text(blk.oldText).font(font).strikethrough().foregroundColor(pal.cDelFg)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(pal.cDelBg).cornerRadius(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !blk.newText.isEmpty {
                    Text(blk.newText).font(font).foregroundColor(pal.cInsFg)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(pal.cInsBg).cornerRadius(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 2) {   // glass pill, matching the toolbar
                Button { store.resolve([blk.id: "accept"]) } label: {
                    Image(systemName: "checkmark").font(.system(size: 12)).foregroundColor(pal.cInsFg).frame(width: 28, height: 24)
                }.buttonStyle(.plain).help("Accept")
                Button { store.resolve([blk.id: "reject"]) } label: {
                    Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(pal.cDelFg).frame(width: 28, height: 24)
                }.buttonStyle(.plain).help("Reject")
            }
            .padding(.horizontal, 3).padding(.vertical, 2)
            .background(pal.cPaperEdge, in: Capsule())
            .overlay(Capsule().stroke(pal.cRule, lineWidth: 1))
            .shadow(color: pal.cInk.opacity(0.10), radius: 6, y: 1)
        }
    }
}

// ----------  Root layout  ----------
struct ContentView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var theme: ThemeManager
    @AppStorage("iliad.showSidebar") private var showSidebar = true
    @AppStorage("iliad.focus") private var focus = true
    @AppStorage("iliad.typewriter") private var typewriter = false
    @AppStorage("iliad.spellcheck") private var spellcheck = true
    @AppStorage("iliad.showStats") private var showStats = true
    @AppStorage("iliad.zen") private var zen = false
    @AppStorage("iliad.showTerminal") private var showTerminal = false
    @AppStorage("iliad.termHeight") private var termHeight: Double = 260
    @AppStorage("iliad.zoom") private var zoom: Double = 1.0
    @AppStorage("iliad.fontSize") private var fontSize: Double = 20
    @AppStorage("iliad.lineHeight") private var lineHeight: Double = 1.3
    @AppStorage("iliad.measure") private var measure: Double = 680
    @State private var peekChrome = false
    @State private var peekSidebar = false
    @State private var terminalEverShown = false
    @State private var chromeHideWork: DispatchWorkItem?
    @State private var sideHideWork: DispatchWorkItem?
    @State private var newFileName = ""
    @State private var newFolderName = ""

    // Reveal the hidden toolbar while the pointer is in the top area; hide shortly after leaving.
    func peekTop(_ inside: Bool) {
        chromeHideWork?.cancel()
        if inside { withAnimation(.easeOut(duration: 0.15)) { peekChrome = true } }
        else {
            let w = DispatchWorkItem { withAnimation(.easeOut(duration: 0.2)) { peekChrome = false } }
            chromeHideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        }
    }

    // Peek the sidebar from the left edge; debounced hide so it doesn't flicker in/out
    // (the peeked sidebar itself keeps the peek alive while hovered).
    func peekSide(_ inside: Bool) {
        sideHideWork?.cancel()
        if inside { withAnimation(.easeOut(duration: 0.18)) { peekSidebar = true } }
        else {
            let w = DispatchWorkItem { withAnimation(.easeOut(duration: 0.2)) { peekSidebar = false } }
            sideHideWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        }
    }

    let poll = Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()
    var pal: Pal { theme.pal }

    var sidebarVisible: Bool { (showSidebar && !zen) || peekSidebar }   // zen hides it; the left-edge peek brings it back
    var chromeVisible: Bool { !zen || peekChrome }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
                SidebarView()
                    .onHover { peekSide($0) }   // keep the peek alive while hovering it
                    .transition(.move(edge: .leading))
            }
            VStack(spacing: 0) {
                editorArea
                if terminalEverShown {   // mount once, then keep alive (collapsed) to preserve shell state
                    terminalPanel
                        .frame(height: showTerminal ? nil : 0)
                        .opacity(showTerminal ? 1 : 0)
                        .clipped()
                        .allowsHitTesting(showTerminal)
                }
            }
            .background { pal.cPaper.ignoresSafeArea() }
            // Left-edge hover zone reveals the sidebar whenever it's hidden (zen or toggled off).
            .overlay(alignment: .leading) {
                if !sidebarVisible {
                    Color.clear.frame(width: 12).frame(maxHeight: .infinity)
                        .contentShape(Rectangle()).onHover { peekSide($0) }
                }
            }
        }
        .animation(.easeOut(duration: 0.24), value: sidebarVisible)
        .overlay(alignment: .bottom) {
            if store.savedFlash {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(pal.cAccent)
                    Text("Saved")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(pal.cInkSoft)
                .padding(.horizontal, 13).padding(.vertical, 7)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(pal.cRule.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                .padding(.bottom, 26)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.savedFlash)
        .animation(.easeOut(duration: 0.2), value: store.review != nil)
        .preferredColorScheme(theme.dark ? .dark : .light)
        .onReceive(poll) { _ in store.refresh() }
        .onAppear { installCommandObserver(); applyWindowChrome(); if showTerminal { terminalEverShown = true } }
        .onChange(of: theme.currentName) { _ in applyWindowChrome() }
        .onChange(of: store.namingNewFile) { if $0 { newFileName = "Untitled" } }
        .alert("Name new file", isPresented: $store.namingNewFile) {
            TextField("Name", text: $newFileName)
            Button("Create") { store.createFile(named: newFileName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A “.md” file will be created in your folder.")
        }
        .onChange(of: store.namingNewFolder) { if $0 { newFolderName = "New Folder" } }
        .alert("Name new folder", isPresented: $store.namingNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Create") { store.createFolder(named: newFolderName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new folder will be created in your library.")
        }
    }

    // Tint the native window (titlebar / traffic-light backing) to the theme.
    func applyWindowChrome() {
        DispatchQueue.main.async {
            for w in NSApplication.shared.windows {
                w.backgroundColor = theme.pal.paper          // paper fills the gutter around the floating sidebar card
                w.appearance = NSAppearance(named: theme.dark ? .darkAqua : .aqua)
                w.titlebarAppearsTransparent = true
                w.titleVisibility = .hidden
                w.styleMask.insert(.fullSizeContentView)   // content runs under the titlebar (no top gap)
            }
        }
    }

    var editorToolbar: some View {
        let inset: CGFloat = 10
        return HStack(spacing: 0) {
            Spacer()
            HStack(spacing: 8) {
                // Panels & UI state
                bubble {
                    toolBtn("sidebar.left", showSidebar, "Toggle library (⌘0)") { withAnimation(.easeOut(duration: 0.2)) { showSidebar.toggle() } }
                    toolBtn(zen ? "eye.slash" : "eye", zen, "Zen (⌘⌃F)") { withAnimation(.easeOut(duration: 0.2)) { zen.toggle() } }
                    toolBtn("terminal", showTerminal, "Terminal (⌘J)") { toggleTerminal() }
                    toolBtn("info.circle", showStats, "Word count (⌘/)") { showStats.toggle() }
                }
                // Writing-mode / text interactions
                bubble {
                    toolBtn("circle.and.line.horizontal", focus, "Focus mode (⌘.)") { focus.toggle() }
                    toolBtn("character.cursor.ibeam", typewriter, "Typewriter (⌘T)") { typewriter.toggle() }
                }
                // Theme & appearance
                bubble {
                    toolBtn("textformat.characters.dottedunderline", spellcheck, "Spell check") { spellcheck.toggle() }
                    toolBtn(theme.dark ? "sun.max" : "moon", false, "Toggle light / dark (⌘D)") { theme.toggle() }
                    themeMenu
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.arrow.set()   // override the text view's I-beam on every move
                    peekTop(true)
                case .ended:
                    peekTop(false)
                }
            }
        }
        .padding(.top, inset)
        .padding(.trailing, inset + 16)   // clear the scrollbar gutter
    }

    // A single rounded segment of the toolbar.
    @ViewBuilder func bubble<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        HStack(spacing: 2) { content() }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(pal.cPaperEdge, in: Capsule())
            .overlay(Capsule().stroke(pal.cRule, lineWidth: 1))
    }

    // Floating top-left bar shown while an AI review is pending: count, change navigation, accept/reject all.
    @ViewBuilder var diffBar: some View {
        if let review = store.review {
            let n = review.blocks.filter { $0.changed }.count
            let idx = store.diffNavIndex
            HStack(spacing: 8) {
                bubble {
                    let pos = idx < 0 ? 1 : idx + 1
                    (Text("\(pos) of \(n)").font(.system(size: 12, weight: .bold))
                     + Text(" \(n == 1 ? "Change" : "Changes") pending approval").font(.system(size: 12, weight: .medium)))
                        .foregroundColor(pal.cInkSoft)
                        .frame(height: 26).padding(.horizontal, 6)
                }
                bubble {
                    barBtn("chevron.up", pal.cInkSoft, "Previous change", disabled: idx == 0) {
                        NotificationCenter.default.post(name: .iliadDiffNav, object: "prev")
                    }
                    barBtn("chevron.down", pal.cInkSoft, "Next change", disabled: n == 0 || idx == n - 1) {
                        NotificationCenter.default.post(name: .iliadDiffNav, object: "next")
                    }
                }
                HoverPillButton(icon: "checkmark", color: pal.cAccent, faint: pal.cInkFaint, paperEdge: pal.cPaperEdge, rule: pal.cRule, help: "Accept all") { store.resolveAll("accept") }
                HoverPillButton(icon: "xmark", color: pal.cInkSoft, faint: pal.cInkFaint, paperEdge: pal.cPaperEdge, rule: pal.cRule, help: "Reject all") { store.resolveAll("reject") }
            }
            .padding(.top, 10)
            .padding(.leading, 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    func barBtn(_ icon: String, _ color: Color, _ help: String, disabled: Bool = false, _ action: @escaping () -> Void) -> some View {
        HoverIconButton(icon: icon, color: color, faint: pal.cInkFaint, disabled: disabled, help: help, action: action)
    }

    var reviewPending: Bool {
        store.review != nil || (store.files.first(where: { $0.path == store.currentPath })?.pending ?? false)
    }

    func toolBtn(_ icon: String, _ on: Bool, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: {
            action()
            // The action's re-render makes the window re-pick the text view's I-beam; restore the pointer.
            DispatchQueue.main.async { NSCursor.arrow.set() }
        }) {
            Image(systemName: icon).font(.system(size: 15))
                .frame(width: 34, height: 30)
                .foregroundColor(on ? pal.cAccent : pal.cInkSoft)
        }.buttonStyle(.plain).help(help)
    }

    @ViewBuilder func weightButton(body: Bool, _ w: Int) -> some View {
        Button {
            if body { theme.bodyWeight = Double(w) } else { theme.headingWeight = Double(w) }
        } label: {
            let cur = Int((body ? theme.bodyWeight : theme.headingWeight).rounded())
            HStack { if cur == w { Image(systemName: "checkmark") }; Text("\(w)") }
        }
    }

    @ViewBuilder func themeItem(_ t: TermTheme) -> some View {
        Button { theme.apply(t.name); DispatchQueue.main.async { NSCursor.arrow.set() } } label: {
            Label {
                Text((t.name == theme.currentName ? "✓ " : "") + t.name)
            } icon: {
                Image(nsImage: themeSwatch(t)).renderingMode(.original)
            }
        }
    }

    var themeMenu: some View {
        Menu {
            Menu("Light") { ForEach(theme.popular(dark: false)) { t in themeItem(t) } }
            Menu("Dark") { ForEach(theme.popular(dark: true)) { t in themeItem(t) } }
            if !theme.imported.isEmpty { Menu("Imported") { ForEach(theme.imported) { t in themeItem(t) } } }
            Button("Import Terminal Theme…") { theme.importThemes() }
            Divider()
            ForEach(Fonts.writingFonts, id: \.self) { f in
                Button { theme.setFont(f); DispatchQueue.main.async { NSCursor.arrow.set() } } label: {
                    HStack { if theme.fontName == f { Image(systemName: "checkmark") }; Text(f) }
                }
            }
            Divider()
            Menu("Body Weight") {
                ForEach([200, 250, 300, 350, 400, 450], id: \.self) { w in weightButton(body: true, w) }
            }
            Menu("Heading Weight") {
                ForEach([400, 450, 500, 550, 600, 650, 700], id: \.self) { w in weightButton(body: false, w) }
            }
        } label: {
            Image(systemName: "paintpalette").font(.system(size: 15)).foregroundColor(pal.cInkSoft)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden)
        .frame(width: 34, height: 30)
        .help("Theme & font")
    }

    var terminalPanel: some View {
        VStack(spacing: 0) {
            ZStack {
                Rectangle().fill(pal.cRule).frame(height: 1)
                Rectangle().fill(Color.clear).frame(height: 8).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active = phase { NSCursor.resizeUpDown.set() }   // override the I-beam reliably
                    }
                    .gesture(DragGesture().onChanged { v in
                        termHeight = min(640, max(120, termHeight - Double(v.translation.height)))
                    })
            }
            TerminalView(theme: theme.current, cwd: store.workspacePath)
                .frame(height: CGFloat(termHeight))
                .id("term")   // keep one session alive while toggled on
        }
    }

    var editorArea: some View {
        ZStack(alignment: .top) {
                Group {
                    if !store.hasFolder {
                        emptyState(icon: "folder", title: "Open a folder", subtitle: "Iliad reads the files in a folder you choose.", button: "Open Folder…") { store.openFolderPanel() }
                    } else if store.currentPath == nil {
                        emptyState(icon: "doc.text", title: "No file open", subtitle: "Select a file from the library on the left.", button: nil) {}
                    } else {
                        EditorView(text: store.currentText, docID: store.currentPath ?? "",
                                   token: store.loadToken, pal: pal,
                                   themeID: theme.currentName + "|" + theme.fontName + "|" + String(zoom) + "|" + String(fontSize) + "|" + String(lineHeight) + "|" + String(theme.bodyWeight) + "|" + String(theme.headingWeight),
                                   zoom: CGFloat(zoom), baseSize: CGFloat(fontSize), lineHeight: CGFloat(lineHeight), measure: CGFloat(measure),
                                   focusMode: focus, typewriter: typewriter, spellcheck: spellcheck,
                                   review: store.review,
                                   onChange: { store.edited($0) },
                                   onResolve: { id, decision in store.resolve([id: decision]) },
                                   onNav: { store.diffNavIndex = $0 })
                    }
                }
                if chromeVisible {
                    VStack(spacing: 0) {
                        editorToolbar
                        Spacer()
                        if showStats && store.review == nil { StatusBar() }
                    }
                }
                // reveal the toolbar by hovering the top area while it's hidden
                if !chromeVisible {
                    VStack {
                        Color.clear.frame(height: 52).frame(maxWidth: .infinity).contentShape(Rectangle())
                            .onHover { peekTop($0) }
                        Spacer()
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { diffBar }
    }

    @ViewBuilder func emptyState(icon: String, title: String, subtitle: String, button: String?, action: @escaping () -> Void) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 40, weight: .thin)).foregroundColor(pal.cInkFaint)
            Text(title).font(.system(size: 20).weight(.medium)).foregroundColor(pal.cInkSoft)
            Text(subtitle).font(.system(size: 14)).foregroundColor(pal.cInkFaint)
            if let button = button {
                GlassButton(title: button, tint: pal.cInkSoft, action: action).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(pal.cPaper)
    }

    func toggleTerminal() {
        withAnimation(.easeOut(duration: 0.2)) { showTerminal.toggle() }
        if showTerminal { terminalEverShown = true }
    }

    func installCommandObserver() {
        NotificationCenter.default.addObserver(forName: .iliadCommand, object: nil, queue: .main) { note in
            guard let cmd = note.object as? String else { return }
            switch cmd {
            case "save": store.saveNow()
            case "newFile": store.newFile()
            case "newFolder": store.newFolder()
            case "open": store.openFolderPanel()
            case "theme": theme.toggle()
            case "sidebar": withAnimation { showSidebar.toggle() }
            case "stats": showStats.toggle()
            case "focus": focus.toggle()
            case "typewriter": typewriter.toggle()
            case "zen": withAnimation { zen.toggle() }
            case "terminal": toggleTerminal()
            case "zoomIn": zoom = min(2.6, zoom + 0.1)
            case "zoomOut": zoom = max(0.6, zoom - 0.1)
            case "zoomReset": zoom = 1.0
            default: break
            }
        }
    }
}

extension Notification.Name {
    static let iliadCommand = Notification.Name("IliadCommand")
    static let iliadDiffNav = Notification.Name("IliadDiffNav")   // bottom-bar up/down navigation
}

// Native Liquid Glass on macOS 26+, the hand-built approximation on older systems.
struct GlassButton: View {
    let title: String
    var tint: Color
    let action: () -> Void
    var body: some View {
        if #available(macOS 26.0, *) {
            Button(action: action) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 18).padding(.vertical, 8)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        } else {
            LegacyGlassButton(title: title, tint: tint, action: action)
        }
    }
}

// A translucent "liquid glass" capsule button: a refracting blurred body with a glossy sheen,
// a bright curved rim that catches light along the top, and depth shading.
struct LegacyGlassButton: View {
    let title: String
    var tint: Color
    let action: () -> Void
    @State private var hover = false
    @State private var pressed = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(tint)
                .padding(.horizontal, 26).padding(.vertical, 13)
                .background {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)                 // refracts the background
                        Capsule().fill(                                    // glossy sheen, light at top
                            LinearGradient(stops: [
                                .init(color: .white.opacity(hover ? 0.34 : 0.24), location: 0),
                                .init(color: .white.opacity(0.06), location: 0.42),
                                .init(color: .clear, location: 0.6),
                                .init(color: .black.opacity(0.10), location: 1)
                            ], startPoint: .top, endPoint: .bottom))
                        Capsule().fill(tint.opacity(hover ? 0.12 : 0.06))  // faint theme tint
                    }
                }
                .overlay {                                                 // bright curved glass rim
                    Capsule().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.22), .white.opacity(0.04)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
                }
                .clipShape(Capsule())
                .scaleEffect(pressed ? 0.98 : 1)                           // subtle press, never grows
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.easeOut(duration: 0.18)) { hover = h } }
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeOut(duration: 0.1)) { pressed = true } }
            .onEnded { _ in withAnimation(.easeOut(duration: 0.15)) { pressed = false } })
    }
}
