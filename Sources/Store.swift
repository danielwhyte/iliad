import SwiftUI
import AppKit
import CoreServices

struct DocMeta: Identifiable, Hashable {
    var path: String          // relative to workspace root
    var title: String
    var snippet: String
    var mtime: Double
    var pending: Bool
    var id: String { path }
    var folder: String { path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : "" }
}

// Workspace model: Iliad opens a folder you choose (like a code editor) and only
// reads its structure. It never creates a dedicated app folder and never seeds
// files. The only file-management actions are Open Folder and New Folder.
final class Store: ObservableObject {
    @Published var root: URL? = nil
    @Published var rootName: String = ""
    @Published var folders: [String] = []
    @Published var files: [DocMeta] = []
    @Published var currentPath: String? = nil
    @Published var currentText: String = ""
    @Published var loadToken: Int = 0
    @Published var selectedFolder: String = ""
    @Published var collapsed: Set<String> = []
    @Published var namingNewFile = false      // drives the "name your new file" dialog
    private var newFileFolder = ""            // folder the pending new file lands in
    @Published var review: Review? = nil
    @Published var diffNavIndex: Int = -1     // current change index in the diff bar (for ▲▼ grey-out)
    @Published var stats: (words: Int, chars: Int, read: Int) = (0, 0, 0)
    @Published var saving: Bool = false

    private let fm = FileManager.default
    private var saveWork: DispatchWorkItem?
    private var statsWork: DispatchWorkItem?
    private var liveText = ""
    private var isDirty = false

    var hasFolder: Bool { root != nil }
    var workspacePath: String { root?.path ?? NSHomeDirectory() }
    private var baseDir: URL? { root?.appendingPathComponent(".iliad", isDirectory: true) }

    init() {
        if let saved = UserDefaults.standard.string(forKey: "IliadRoot") {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
                setRoot(URL(fileURLWithPath: saved, isDirectory: true), persist: false)
            }
        }
        if let c = UserDefaults.standard.array(forKey: "IliadCollapsed") as? [String] { collapsed = Set(c) }
    }

    private func setRoot(_ url: URL, persist: Bool = true) {
        root = url
        rootName = url.lastPathComponent
        if persist { UserDefaults.standard.set(url.path, forKey: "IliadRoot") }
        startWatching()
    }

    // ---- filesystem watcher: catch external (e.g. Claude) edits immediately ----
    private var stream: FSEventStreamRef?
    private func startWatching() {
        stopWatching()
        guard let root = root else { return }
        var ctx = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                       retain: nil, release: nil, copyDescription: nil)
        let cb: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let s = Unmanaged<Store>.fromOpaque(info).takeUnretainedValue()
            DispatchQueue.main.async { s.refresh() }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        stream = FSEventStreamCreate(kCFAllocatorDefault, cb, &ctx, [root.path] as CFArray,
                                     FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.3, flags)
        if let stream = stream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }
    private func stopWatching() {
        if let s = stream { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s); stream = nil }
    }

    // ---- path helpers ----
    private func fileURL(_ rel: String) -> URL? { root?.appendingPathComponent(rel) }
    private func baseURL(_ rel: String) -> URL? { baseDir?.appendingPathComponent(rel) }
    private func isDoc(_ url: URL) -> Bool { ["txt", "md", "markdown", "text", "mdown", "markdn"].contains(url.pathExtension.lowercased()) }
    private func readBase(_ rel: String) -> String? { baseURL(rel).flatMap { try? String(contentsOf: $0, encoding: .utf8) } }
    private func writeBase(_ rel: String, _ text: String) {
        guard let u = baseURL(rel) else { return }
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: u, atomically: true, encoding: .utf8)
    }
    private func relativePath(_ url: URL, _ rootURL: URL) -> String {
        let p = url.standardizedFileURL.path, r = rootURL.standardizedFileURL.path
        return p.hasPrefix(r + "/") ? String(p.dropFirst(r.count + 1)) : url.lastPathComponent
    }

    // ---- listing (read only) ----
    func refresh() {
        guard let root = root else { folders = []; files = []; return }
        var fl: [String] = []
        var fs: [DocMeta] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        if let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) {
            for case let u as URL in en {
                let vals = try? u.resourceValues(forKeys: Set(keys))
                let rel = relativePath(u, root)
                if vals?.isDirectory == true { fl.append(rel) }
                else if isDoc(u) {
                    let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
                    let lines = text.components(separatedBy: "\n")
                    let title = (lines.first ?? "").trimmingCharacters(in: .whitespaces)
                    let snippet = lines.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
                    let mtime = (vals?.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000
                    let base = readBase(rel)
                    fs.append(DocMeta(path: rel, title: title.isEmpty ? u.lastPathComponent : title,
                                      snippet: String(snippet.prefix(160)), mtime: mtime,
                                      pending: (base != nil && base != text)))
                }
            }
        }
        let sorted = fl.sorted()
        if folders != sorted { folders = sorted }   // only publish on real change (keeps menus open)
        if files != fs { files = fs }
        if let cur = currentPath, review == nil, !isDirty,
           let meta = fs.first(where: { $0.path == cur }), meta.pending {
            buildReview(cur)
        }
    }

    // ---- open / edit / save (edits existing files in place; no rename) ----
    func open(_ path: String) {
        flushSave()
        guard let u = fileURL(path) else { return }
        let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        var base = readBase(path)
        if base == nil { writeBase(path, text); base = text }
        currentPath = path
        selectedFolder = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : ""
        UserDefaults.standard.set(path, forKey: "IliadLast")
        if let b = base, b != text { buildReview(path); return }
        review = nil
        liveText = text; currentText = text; loadToken += 1
        recomputeStats(text)
    }

    func edited(_ text: String) {
        guard currentPath != nil else { return }
        liveText = text; isDirty = true
        if !saving { saving = true }                 // publish once per typing burst
        statsWork?.cancel()                          // debounce word count (avoids per-keystroke re-render)
        let sw = DispatchWorkItem { [weak self] in guard let s = self else { return }; s.recomputeStats(s.liveText) }
        statsWork = sw
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: sw)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.performSave() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }
    func flushSave() { if isDirty { saveWork?.cancel(); performSave() } }

    // ⌘S — writes immediately and flashes a "Saved" confirmation, even though saving is automatic.
    @Published var savedFlash = false
    private var flashWork: DispatchWorkItem?
    func saveNow() {
        flushSave()
        savedFlash = true
        flashWork?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.savedFlash = false }
        flashWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1, execute: w)
    }

    private func performSave() {
        guard isDirty, let path = currentPath, let u = fileURL(path) else { isDirty = false; saving = false; return }
        isDirty = false
        try? liveText.write(to: u, atomically: true, encoding: .utf8)
        writeBase(path, liveText)
        saving = false
        refreshSoon()
    }
    private var refreshTimer: DispatchWorkItem?
    private func refreshSoon() {
        refreshTimer?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshTimer = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    private func recomputeStats(_ text: String) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = body.isEmpty ? 0 : body.split { $0 == " " || $0 == "\n" || $0 == "\t" }.count
        stats = (words, body.count, max(0, Int((Double(words) / 220).rounded())))
    }

    // ---- new file ----
    // Opens the naming dialog; the file is created by createFile(named:) on confirm.
    func newFile() {
        guard hasFolder else { return }
        newFileFolder = selectedFolder
        namingNewFile = true
    }

    func createFile(named name: String) {
        guard let root = root else { return }
        flushSave()
        let pre = newFileFolder.isEmpty ? "" : newFileFolder + "/"
        let base = slug(name)
        var path = pre + base + ".md"; var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(path).path) { path = pre + base + " \(n).md"; n += 1 }
        let u = root.appendingPathComponent(path)
        try? fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "".write(to: u, atomically: true, encoding: .utf8)
        writeBase(path, "")
        refresh()
        open(path)
    }

    private func slug(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        let bad = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        t = String(String.UnicodeScalarView(t.unicodeScalars.map { bad.contains($0) ? " " : $0 }))
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Untitled" : t
    }

    // ---- standard file/folder actions ----
    func revealItem(_ path: String) { if let u = fileURL(path) { NSWorkspace.shared.activateFileViewerSelecting([u]) } }

    func rename(_ path: String, to newBare: String) {
        guard let root = root else { return }
        let folder = (path as NSString).deletingLastPathComponent
        let ext = (path as NSString).pathExtension
        let pre = folder.isEmpty ? "" : folder + "/"
        let suffix = ext.isEmpty ? "" : "." + ext
        let base = slug(newBare)
        var rel = pre + base + suffix; var n = 2
        while rel != path && fm.fileExists(atPath: root.appendingPathComponent(rel).path) { rel = pre + base + " \(n)" + suffix; n += 1 }
        if rel == path { return }
        try? fm.moveItem(at: root.appendingPathComponent(path), to: root.appendingPathComponent(rel))
        if let b1 = baseURL(path), let b2 = baseURL(rel) {
            try? fm.createDirectory(at: b2.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: b1, to: b2)
        }
        if currentPath == path { currentPath = rel; UserDefaults.standard.set(rel, forKey: "IliadLast") }
        refresh()
    }

    func renameFolder(_ path: String, to newName: String) {
        guard let root = root else { return }
        let parent = (path as NSString).deletingLastPathComponent
        let pre = parent.isEmpty ? "" : parent + "/"
        let base = slug(newName)
        var rel = pre + base; var n = 2
        while rel != path && fm.fileExists(atPath: root.appendingPathComponent(rel).path) { rel = pre + base + " \(n)"; n += 1 }
        if rel == path { return }
        try? fm.moveItem(at: root.appendingPathComponent(path), to: root.appendingPathComponent(rel))
        if let b1 = baseURL(path), let b2 = baseURL(rel) { try? fm.moveItem(at: b1, to: b2) }
        if let cur = currentPath, cur.hasPrefix(path + "/") { currentPath = rel + String(cur.dropFirst(path.count)) }
        if selectedFolder == path { selectedFolder = rel }
        refresh()
    }

    // ---- drag & drop move: relocate a file or folder into `folder` ("" = root) ----
    @discardableResult
    func move(_ path: String, into folder: String) -> Bool {
        guard let root = root else { return false }
        if folder == path || folder.hasPrefix(path + "/") { return false }   // can't drop onto self / own subtree
        if (path as NSString).deletingLastPathComponent == folder { return false }   // already here
        flushSave()
        let name = (path as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        let base = (name as NSString).deletingPathExtension
        let pre = folder.isEmpty ? "" : folder + "/"
        var rel = pre + name; var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(rel).path) { rel = pre + base + " \(n)" + suffix; n += 1 }
        do {
            try fm.createDirectory(at: root.appendingPathComponent(rel).deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: root.appendingPathComponent(path), to: root.appendingPathComponent(rel))
        } catch { return false }
        if let b1 = baseURL(path), let b2 = baseURL(rel), fm.fileExists(atPath: b1.path) {
            try? fm.createDirectory(at: b2.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: b1, to: b2)
        }
        if let cur = currentPath {
            if cur == path { currentPath = rel; UserDefaults.standard.set(rel, forKey: "IliadLast") }
            else if cur.hasPrefix(path + "/") {
                let moved = rel + String(cur.dropFirst(path.count))
                currentPath = moved; UserDefaults.standard.set(moved, forKey: "IliadLast")
            }
        }
        if selectedFolder == path { selectedFolder = rel }
        else if selectedFolder.hasPrefix(path + "/") { selectedFolder = rel + String(selectedFolder.dropFirst(path.count)) }
        collapsed.remove(folder)   // reveal the destination so the moved item is visible
        refresh()
        return true
    }

    func duplicate(_ path: String) {
        guard let root = root, let src = fileURL(path) else { return }
        let folder = (path as NSString).deletingLastPathComponent
        let ext = (path as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        let baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        let pre = folder.isEmpty ? "" : folder + "/"
        var rel = pre + baseName + " copy" + suffix; var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(rel).path) { rel = pre + baseName + " copy \(n)" + suffix; n += 1 }
        try? fm.copyItem(at: src, to: root.appendingPathComponent(rel))
        refresh()
    }

    func copyToPasteboard(_ path: String) {
        guard let u = fileURL(path) else { return }
        let pb = NSPasteboard.general; pb.clearContents(); pb.writeObjects([u as NSURL])
    }

    func pasteInto(_ folder: String) {
        guard let root = root,
              let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
              !urls.isEmpty else { return }
        let pre = folder.isEmpty ? "" : folder + "/"
        for src in urls {
            let name = src.lastPathComponent
            let ext = (name as NSString).pathExtension
            let suffix = ext.isEmpty ? "" : "." + ext
            let baseName = (name as NSString).deletingPathExtension
            var rel = pre + name; var n = 2
            while fm.fileExists(atPath: root.appendingPathComponent(rel).path) { rel = pre + baseName + " \(n)" + suffix; n += 1 }
            try? fm.copyItem(at: src, to: root.appendingPathComponent(rel))
        }
        refresh()
    }

    var canPaste: Bool { NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: nil) }

    // ---- folders ----
    @Published var namingNewFolder = false
    private var newFolderParent = ""
    // Opens the naming dialog; the folder is created by createFolder(named:) on confirm.
    func newFolder() {
        guard hasFolder else { return }
        newFolderParent = selectedFolder
        namingNewFolder = true
    }
    func createFolder(named name: String) {
        guard let root = root else { return }
        let pre = newFolderParent.isEmpty ? "" : newFolderParent + "/"
        let base = slug(name)
        var path = pre + base; var n = 2
        while fm.fileExists(atPath: root.appendingPathComponent(path).path) { path = pre + base + " \(n)"; n += 1 }
        try? fm.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        collapsed.remove(path); selectedFolder = path
        refresh()
    }
    func delete(_ path: String) {
        guard let u = fileURL(path) else { return }
        try? fm.removeItem(at: u)
        if let b = baseURL(path) { try? fm.removeItem(at: b) }
        if path == currentPath {
            currentPath = nil; review = nil
            refresh()
            if let first = files.sorted(by: { $0.mtime > $1.mtime }).first { open(first.path) }
            else { liveText = ""; currentText = ""; loadToken += 1; recomputeStats("") }
        } else { refresh() }
    }
    func deleteFolder(_ path: String) -> Bool {
        guard let u = fileURL(path) else { return false }
        let contents = (try? fm.contentsOfDirectory(atPath: u.path)) ?? []
        if !contents.isEmpty { return false }
        try? fm.removeItem(at: u)
        if let b = baseURL(path) { try? fm.removeItem(at: b) }
        if selectedFolder == path { selectedFolder = "" }
        refresh(); return true
    }
    func toggleCollapse(_ path: String) {
        if collapsed.contains(path) { collapsed.remove(path) } else { collapsed.insert(path) }
        UserDefaults.standard.set(Array(collapsed), forKey: "IliadCollapsed")
    }

    func reveal() { if let root = root { NSWorkspace.shared.activateFileViewerSelecting([root]) } }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Open"
        panel.message = "Choose a folder to open"
        panel.directoryURL = root
        if panel.runModal() == .OK, let url = panel.url {
            flushSave()
            setRoot(url)
            currentPath = nil; selectedFolder = ""; review = nil
            currentText = ""; liveText = ""; loadToken += 1; recomputeStats("")
            refresh()
            if let first = files.sorted(by: { $0.mtime > $1.mtime }).first { open(first.path) }
        }
    }

    // ---- track changes ----
    func buildReview(_ path: String) {
        guard let u = fileURL(path) else { return }
        let text = (try? String(contentsOf: u, encoding: .utf8)) ?? ""
        let base = readBase(path) ?? text
        guard base != text else { review = nil; return }
        review = Review(path: path, blocks: Diff.blocks(base, text))
        diffNavIndex = -1
        currentPath = path
    }
    func resolve(_ decisions: [Int: String]) {
        guard let r = review, let u = fileURL(r.path) else { return }
        let (file, base) = Diff.reconstructBlocks(r.blocks, decisions)
        try? file.write(to: u, atomically: true, encoding: .utf8)
        writeBase(r.path, base)
        review = nil
        refresh(); open(r.path)
    }
    func resolveAll(_ decision: String) {
        guard let r = review else { return }
        var dec: [Int: String] = [:]
        for b in r.blocks where b.changed { dec[b.id] = decision }
        resolve(dec)
    }

    deinit { stopWatching() }

    func boot() {
        guard root != nil else { return }
        refresh()
        let last = UserDefaults.standard.string(forKey: "IliadLast")
        if let last = last, files.contains(where: { $0.path == last }) { open(last) }
        else if let first = files.sorted(by: { $0.mtime > $1.mtime }).first { open(first.path) }
    }
}
