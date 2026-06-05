import Foundation

struct DiffOp {
    var type: String   // "eq" | "ins" | "del"
    var text: String
    var g: Int?        // group id for change runs
}

struct ChangeGroup: Identifiable {
    let id: Int
    var del: String
    var ins: String
}

enum Diff {
    static func tokenize(_ s: String) -> [String] {
        var toks: [String] = []
        var cur = ""
        var curWS: Bool? = nil
        for ch in s {
            let ws = ch.isWhitespace
            if curWS == nil { curWS = ws; cur.append(ch) }
            else if ws == curWS { cur.append(ch) }
            else { toks.append(cur); cur = String(ch); curWS = ws }
        }
        if !cur.isEmpty { toks.append(cur) }
        return toks
    }

    private static func push(_ ops: inout [DiffOp], _ type: String, _ text: String) {
        if let last = ops.last, last.type == type { ops[ops.count - 1].text += text }
        else { ops.append(DiffOp(type: type, text: text)) }
    }

    private static func lcs(_ a: [String], _ b: [String]) -> [DiffOp] {
        let n = a.count, m = b.count
        var ops: [DiffOp] = []
        if n == 0 && m == 0 { return ops }
        if n == 0 { ops.append(DiffOp(type: "ins", text: b.joined())); return ops }
        if m == 0 { ops.append(DiffOp(type: "del", text: a.joined())); return ops }
        if n * m > 700_000 {
            ops.append(DiffOp(type: "del", text: a.joined()))
            ops.append(DiffOp(type: "ins", text: b.joined()))
            return ops
        }
        let w = m + 1
        var dp = [Int](repeating: 0, count: (n + 1) * w)
        var i = n - 1
        while i >= 0 {
            var j = m - 1
            while j >= 0 {
                dp[i * w + j] = a[i] == b[j] ? dp[(i + 1) * w + (j + 1)] + 1
                    : max(dp[(i + 1) * w + j], dp[i * w + (j + 1)])
                j -= 1
            }
            i -= 1
        }
        i = 0; var j = 0
        while i < n && j < m {
            if a[i] == b[j] { push(&ops, "eq", a[i]); i += 1; j += 1 }
            else if dp[(i + 1) * w + j] >= dp[i * w + (j + 1)] { push(&ops, "del", a[i]); i += 1 }
            else { push(&ops, "ins", b[j]); j += 1 }
        }
        while i < n { push(&ops, "del", a[i]); i += 1 }
        while j < m { push(&ops, "ins", b[j]); j += 1 }
        return ops
    }

    static func build(_ oldText: String, _ newText: String) -> [DiffOp] {
        let a = tokenize(oldText), b = tokenize(newText)
        var s = 0
        while s < a.count && s < b.count && a[s] == b[s] { s += 1 }
        var ea = a.count, eb = b.count
        while ea > s && eb > s && a[ea - 1] == b[eb - 1] { ea -= 1; eb -= 1 }
        var ops: [DiffOp] = []
        if s > 0 { push(&ops, "eq", a[0..<s].joined()) }
        for op in lcs(Array(a[s..<ea]), Array(b[s..<eb])) { push(&ops, op.type, op.text) }
        if ea < a.count { push(&ops, "eq", a[ea...].joined()) }
        // assign group ids
        var gid = 0, inGroup = false
        for k in ops.indices {
            if ops[k].type == "eq" { inGroup = false; ops[k].g = nil }
            else { if !inGroup { gid += 1; inGroup = true }; ops[k].g = gid }
        }
        return ops
    }

    static func groups(_ ops: [DiffOp]) -> [ChangeGroup] {
        var map: [Int: ChangeGroup] = [:]
        for op in ops {
            guard let g = op.g else { continue }
            var grp = map[g] ?? ChangeGroup(id: g, del: "", ins: "")
            if op.type == "ins" { grp.ins += op.text } else { grp.del += op.text }
            map[g] = grp
        }
        return map.values.sorted { $0.id < $1.id }
    }

    // decisions: group id -> "accept" (take new) or "reject" (keep old)
    static func reconstruct(_ ops: [DiffOp], _ decisions: [Int: String]) -> (file: String, base: String) {
        var file = "", base = ""
        for op in ops {
            switch op.type {
            case "eq":
                file += op.text; base += op.text
            case "ins":
                let d = op.g.flatMap { decisions[$0] }
                if d == "accept" { file += op.text; base += op.text }
                else if d == "reject" { /* drop */ }
                else { file += op.text }
            default: // del
                let d = op.g.flatMap { decisions[$0] }
                if d == "accept" { /* drop */ }
                else if d == "reject" { file += op.text; base += op.text }
                else { base += op.text }
            }
        }
        return (file, base)
    }
}

// A paragraph/region-level change unit (for per-paragraph accept/reject).
struct DiffBlock: Identifiable {
    let id: Int
    let changed: Bool
    let oldLines: [String]
    let newLines: [String]
    var oldText: String { oldLines.joined(separator: "\n") }
    var newText: String { newLines.joined(separator: "\n") }
}

extension Diff {
    // Line-level diff grouped into contiguous change blocks (≈ paragraphs).
    static func blocks(_ oldText: String, _ newText: String) -> [DiffBlock] {
        let a = oldText.components(separatedBy: "\n")
        let b = newText.components(separatedBy: "\n")
        let n = a.count, m = b.count
        var ops: [(Int, String)] = []   // 0 eq, 1 del, 2 ins
        if n * m > 500_000 {
            ops = a.map { (1, $0) } + b.map { (2, $0) }
        } else {
            let w = m + 1
            var dp = [Int](repeating: 0, count: (n + 1) * w)
            var i = n - 1
            while i >= 0 { var j = m - 1
                while j >= 0 {
                    dp[i * w + j] = a[i] == b[j] ? dp[(i + 1) * w + (j + 1)] + 1
                        : max(dp[(i + 1) * w + j], dp[i * w + (j + 1)]); j -= 1
                }; i -= 1 }
            var i2 = 0, j2 = 0
            while i2 < n && j2 < m {
                if a[i2] == b[j2] { ops.append((0, a[i2])); i2 += 1; j2 += 1 }
                else if dp[(i2 + 1) * w + j2] >= dp[i2 * w + (j2 + 1)] { ops.append((1, a[i2])); i2 += 1 }
                else { ops.append((2, b[j2])); j2 += 1 }
            }
            while i2 < n { ops.append((1, a[i2])); i2 += 1 }
            while j2 < m { ops.append((2, b[j2])); j2 += 1 }
        }
        var blocks: [DiffBlock] = []; var id = 0; var k = 0
        while k < ops.count {
            if ops[k].0 == 0 {
                var lines: [String] = []
                while k < ops.count && ops[k].0 == 0 { lines.append(ops[k].1); k += 1 }
                blocks.append(DiffBlock(id: id, changed: false, oldLines: lines, newLines: lines)); id += 1
            } else {
                var old: [String] = [], new: [String] = []
                while k < ops.count && ops[k].0 != 0 {
                    if ops[k].0 == 1 { old.append(ops[k].1) } else { new.append(ops[k].1) }; k += 1
                }
                blocks.append(DiffBlock(id: id, changed: true, oldLines: old, newLines: new)); id += 1
            }
        }
        return blocks
    }

    // decisions: block id -> "accept" (new) / "reject" (old); undecided keeps file=new, base=old
    static func reconstructBlocks(_ blocks: [DiffBlock], _ dec: [Int: String]) -> (file: String, base: String) {
        var f: [String] = [], bs: [String] = []
        for blk in blocks {
            if !blk.changed { f += blk.newLines; bs += blk.newLines }
            else {
                switch dec[blk.id] {
                case "accept": f += blk.newLines; bs += blk.newLines
                case "reject": f += blk.oldLines; bs += blk.oldLines
                default:       f += blk.newLines; bs += blk.oldLines
                }
            }
        }
        return (f.joined(separator: "\n"), bs.joined(separator: "\n"))
    }
}

struct Review {
    var path: String
    var blocks: [DiffBlock]
}
