// Renders Resources/AppIcon.icns: `swift scripts/make-icon.swift`
import AppKit

func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(pixels)
    let inset = size * 0.1
    let tile = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.28); shadow.shadowBlurRadius = size * 0.03; shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
    NSGraphicsContext.saveGraphicsState(); shadow.set(); NSColor.white.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 1, alpha: 1), ending: NSColor(white: 0.9, alpha: 1))!.draw(in: shape, angle: -90)

    // The eyes emoji, as the system draws it.
    let glyph = NSAttributedString(string: "👀", attributes: [.font: NSFont(name: "Apple Color Emoji", size: tile.width * 0.6) ?? NSFont.systemFont(ofSize: tile.width * 0.6)])
    let bounds = glyph.boundingRect(with: NSSize(width: size, height: size), options: [.usesLineFragmentOrigin])
    glyph.draw(at: NSPoint(x: tile.midX - bounds.width / 2 - bounds.minX, y: tile.midY - bounds.height / 2 - bounds.minY))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SideEye.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
exit(task.terminationStatus)
