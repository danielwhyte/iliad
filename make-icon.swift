import Cocoa

// Renders a single icon PNG at the given size: a warm rounded tile with a
// minimalist ink "leaf" mark. Usage: swift make-icon.swift <size> <outPath>
let args = CommandLine.arguments
guard args.count == 3, let size = Int(args[1]) else {
    FileHandle.standardError.write("usage: make-icon.swift <size> <out.png>\n".data(using: .utf8)!)
    exit(1)
}
let out = args[2]
let s = CGFloat(size)

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                          bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}

func rounded(_ rect: CGRect, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

// Background gradient tile (macOS "squircle"-ish rounded rect).
let inset = s * 0.06
let tile = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
ctx.addPath(rounded(tile, s * 0.225))
ctx.clip()

let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.345, green: 0.651, blue: 1.000, alpha: 1),   // #58a6ff
    CGColor(red: 0.122, green: 0.435, blue: 0.922, alpha: 1)    // #1f6feb
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: s, y: 0), options: [])

// Leaf mark: two overlapping arcs forming a leaf with a center vein.
ctx.setFillColor(CGColor(red: 0.902, green: 0.929, blue: 0.953, alpha: 1))   // #e6edf3
let cx = s/2, cy = s/2
let w = s * 0.30
let h = s * 0.40
let leaf = CGMutablePath()
leaf.move(to: CGPoint(x: cx, y: cy - h))
leaf.addQuadCurve(to: CGPoint(x: cx, y: cy + h),
                  control: CGPoint(x: cx + w, y: cy))
leaf.addQuadCurve(to: CGPoint(x: cx, y: cy - h),
                  control: CGPoint(x: cx - w, y: cy))
ctx.addPath(leaf)
ctx.fillPath()

// Vein (cut out by drawing in the tile-ish accent color).
ctx.setStrokeColor(CGColor(red: 0.122, green: 0.435, blue: 0.922, alpha: 1))
ctx.setLineWidth(s * 0.022)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: cx, y: cy - h * 0.82))
ctx.addLine(to: CGPoint(x: cx, y: cy + h * 0.82))
ctx.strokePath()

guard let img = ctx.makeImage() else { exit(1) }
let rep = NSBitmapImageRep(cgImage: img)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try? data.write(to: URL(fileURLWithPath: out))
