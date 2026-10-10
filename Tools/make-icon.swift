// Renders Hop's app icon into an .iconset folder: swift make-icon.swift <out.iconset>
import AppKit

let outDir = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)

    // Standard macOS icon body: 824/1024 of the canvas, centred.
    let body = NSRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.width * 0.225)
    NSGradient(colors: [NSColor(srgbRed: 0.42, green: 0.40, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.25, green: 0.22, blue: 0.78, alpha: 1)])!.draw(in: shape, angle: -90)

    // 2×2 grid of keys, top-left one lit.
    let tile = body.width * 0.26, gap = body.width * 0.07
    let start = NSPoint(x: body.midX - tile - gap / 2, y: body.midY - tile - gap / 2)
    for (i, (col, row)) in [(0, 1), (1, 1), (0, 0), (1, 0)].enumerated() {
        let r = NSRect(x: start.x + CGFloat(col) * (tile + gap), y: start.y + CGFloat(row) * (tile + gap),
                       width: tile, height: tile)
        NSColor.white.withAlphaComponent(i == 0 ? 1 : 0.45).setFill()
        NSBezierPath(roundedRect: r, xRadius: tile * 0.26, yRadius: tile * 0.26).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size).png"))
    try render(size * 2).write(to: URL(fileURLWithPath: "\(outDir)/icon_\(size)x\(size)@2x.png"))
}
