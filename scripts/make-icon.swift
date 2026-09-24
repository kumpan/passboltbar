// Renders the app icon.
//   swift scripts/make-icon.swift preview <out.png>   contact sheet of all variants
//   swift scripts/make-icon.swift <variant>           writes Resources/AppIcon.icns
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func gradient(_ hexes: [UInt32], _ alpha: [CGFloat]? = nil) -> CGGradient {
    let colors = hexes.enumerated().map { color($1, alpha?[$0] ?? 1) }
    let locs = (0..<hexes.count).map { CGFloat($0) / CGFloat(max(hexes.count - 1, 1)) }
    return CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: locs)!
}

/// macOS icon body: 824 pt squircle centered on a 1024 canvas (superellipse, n = 5).
func squircle(in r: CGRect) -> CGPath {
    let path = CGMutablePath(), n = 5.0, steps = 720
    for i in 0...steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = pow(abs(c), 2 / n) * (c < 0 ? -1 : 1), y = pow(abs(s), 2 / n) * (s < 0 ? -1 : 1)
        let p = CGPoint(x: r.midX + x * r.width / 2, y: r.midY + y * r.height / 2)
        i == 0 ? path.move(to: p) : path.addLine(to: p)
    }
    path.closeSubpath()
    return path
}

func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

/// Key pointing right, centered near the origin.
func keyShape() -> CGPath {
    let bow = CGPath(ellipseIn: CGRect(x: -330, y: -140, width: 280, height: 280), transform: nil)
    let hole = CGPath(ellipseIn: CGRect(x: -250, y: -60, width: 120, height: 120), transform: nil)
    return bow.union(rrect(-80, -34, 400, 68, 34))
        .union(rrect(170, -120, 52, 110, 14))
        .union(rrect(250, -95, 52, 85, 14))
        .subtracting(hole)
}

func shieldShape() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: 260))
    p.addCurve(to: CGPoint(x: 240, y: 190), control1: CGPoint(x: 90, y: 260), control2: CGPoint(x: 170, y: 230))
    p.addLine(to: CGPoint(x: 240, y: 30))
    p.addCurve(to: CGPoint(x: 0, y: -290), control1: CGPoint(x: 240, y: -140), control2: CGPoint(x: 120, y: -240))
    p.addCurve(to: CGPoint(x: -240, y: 30), control1: CGPoint(x: -120, y: -240), control2: CGPoint(x: -240, y: -140))
    p.addLine(to: CGPoint(x: -240, y: 190))
    p.addCurve(to: CGPoint(x: 0, y: 260), control1: CGPoint(x: -170, y: 230), control2: CGPoint(x: -90, y: 260))
    p.closeSubpath()
    return p
}

func keyholeShape() -> CGPath {
    let circle = CGPath(ellipseIn: CGRect(x: -66, y: -6, width: 132, height: 132), transform: nil)
    let slot = CGMutablePath()
    slot.move(to: CGPoint(x: -30, y: 30)); slot.addLine(to: CGPoint(x: 30, y: 30))
    slot.addLine(to: CGPoint(x: 52, y: -150)); slot.addLine(to: CGPoint(x: -52, y: -150)); slot.closeSubpath()
    return circle.union(slot)
}

struct Style { let bg: [UInt32]; let glow: CGFloat }

enum Variant: Int, CaseIterable {
    case key = 1, shield, field, dark

    var style: Style {
        switch self {
        case .key: Style(bg: [0x5AA2FF, 0x4B5BF0, 0x3A22B8], glow: 0.28)
        case .shield: Style(bg: [0x34D3C0, 0x1F8FA8, 0x173E73], glow: 0.22)
        case .field: Style(bg: [0xB57BFF, 0x7A4DF2, 0x4424B8], glow: 0.2)
        case .dark: Style(bg: [0x3A3D46, 0x1D1F25, 0x0C0D10], glow: 0.0)
        }
    }
}

func place(_ path: CGPath, rotate: CGFloat = 0, dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1) -> CGPath {
    var t = CGAffineTransform(translationX: 512 + dx, y: 512 + dy).rotated(by: rotate).scaledBy(x: scale, y: scale)
    return path.copy(using: &t)!
}

/// Fills `path` with a vertical gradient and a soft shadow.
func drawGlyph(_ ctx: CGContext, _ path: CGPath, _ fill: CGGradient = gradient([0xFFFFFF, 0xDCE4FF]), shadow: CGFloat = 0.45) {
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x0A0626, shadow))
    ctx.addPath(path); ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let box = path.boundingBox
    ctx.drawLinearGradient(fill, start: CGPoint(x: box.minX, y: box.maxY), end: CGPoint(x: box.maxX, y: box.minY), options: [])
    ctx.restoreGState()
}

func render(_ variant: Variant, size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    let shape = squircle(in: CGRect(x: 100, y: 100, width: 824, height: 824))
    let style = variant.style

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape); ctx.setFillColor(color(style.bg[1])); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.drawLinearGradient(gradient(style.bg), start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    if style.glow > 0 {
        ctx.drawRadialGradient(gradient([0xFFFFFF, 0xFFFFFF], [style.glow, 0]), startCenter: CGPoint(x: 512, y: 560),
                               startRadius: 0, endCenter: CGPoint(x: 512, y: 560), endRadius: 420, options: [])
    }
    ctx.drawLinearGradient(gradient([0xFFFFFF, 0xFFFFFF], [0.3, 0]), start: CGPoint(x: 512, y: 924),
                           end: CGPoint(x: 512, y: 700), options: [])
    ctx.addPath(shape); ctx.setStrokeColor(color(0xFFFFFF, 0.22)); ctx.setLineWidth(6); ctx.strokePath()
    ctx.restoreGState()

    switch variant {
    case .key:
        drawGlyph(ctx, place(keyShape(), rotate: -.pi / 4, dx: -5))
    case .shield:
        drawGlyph(ctx, place(shieldShape(), dy: 10).subtracting(place(keyholeShape(), dy: 20)), gradient([0xFFFFFF, 0xD8F4F4]))
    case .field:
        let field = place(rrect(-300, -95, 600, 190, 95))
        let dots = (0..<4).reduce(CGMutablePath() as CGPath) { acc, i in
            acc.union(place(CGPath(ellipseIn: CGRect(x: -225 + CGFloat(i) * 110, y: -34, width: 68, height: 68), transform: nil)))
        }
        let cursor = place(rrect(212, -60, 16, 120, 8))
        drawGlyph(ctx, field.subtracting(dots).subtracting(cursor), gradient([0xFFFFFF, 0xE9E0FF]))
    case .dark:
        drawGlyph(ctx, place(keyShape(), rotate: -.pi / 4, dx: -5), gradient([0x6EF0E0, 0x3B82F6, 0x8B5CF6]), shadow: 0.7)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let args = CommandLine.arguments.dropFirst()
if args.first == "preview", let out = args.dropFirst().first {
    // Contact sheet: all variants in a row on a neutral background, plus a 32 px (menu/Dock-small) row.
    let tile = 512, pad = 40, count = Variant.allCases.count
    let w = count * tile + (count + 1) * pad, h = tile + 2 * pad + 32 + pad
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(color(0xECECEF)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    for (i, v) in Variant.allCases.enumerated() {
        let x = pad + i * (tile + pad)
        ctx.draw(render(v, size: tile), in: CGRect(x: x, y: pad + 32 + pad, width: tile, height: tile))
        ctx.draw(render(v, size: 64), in: CGRect(x: x + tile / 2 - 16, y: pad, width: 32, height: 32))
    }
    writePNG(ctx.makeImage()!, to: URL(fileURLWithPath: out))
    print("Wrote \(out)")
    exit(0)
}

guard let v = args.first.flatMap(Int.init).flatMap(Variant.init) else {
    print("usage: make-icon.swift preview <out.png> | <variant 1-\(Variant.allCases.count)>"); exit(1)
}
let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        writePNG(render(v, size: base * scale), to: iconset.appendingPathComponent(name))
    }
}
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try proc.run()
proc.waitUntilExit()
print(proc.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns (variant \(v.rawValue))" : "iconutil failed")
