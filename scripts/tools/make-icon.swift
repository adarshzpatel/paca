// Renders a macOS app icon (Big Sur grid: 824pt squircle on a 1024 canvas, soft drop
// shadow) from square artwork, then writes every .iconset size.
//   swift scripts/tools/make-icon.swift ART.png OUT.iconset
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let art = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-icon.swift ART.png OUT.iconset\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 20 * s
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.set()
    NSColor(srgbRed: 0xB8 / 255, green: 0xA2 / 255, blue: 0xE8 / 255, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    art.draw(in: tile, from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try! render(size).write(to: outDir.appendingPathComponent("icon_\(size)x\(size).png"))
    try! render(size * 2).write(to: outDir.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("wrote \(outDir.path)")
