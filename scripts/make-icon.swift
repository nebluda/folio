import AppKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels) / 1024); transform.concat()
        // Draw every icon size directly from paths for crisp small-size rendering.
        let outer = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206)
        NSGraphicsContext.saveGraphicsState()
        let tileShadow = NSShadow()
        tileShadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        tileShadow.shadowBlurRadius = 22; tileShadow.shadowOffset = NSSize(width: 0, height: -10)
        tileShadow.set(); NSColor.black.setFill(); outer.fill()
        NSGraphicsContext.restoreGraphicsState()
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.23, blue: 0.40, alpha: 1), ending: NSColor(calibratedRed: 0.035, green: 0.075, blue: 0.16, alpha: 1))!
        gradient.draw(in: outer, angle: -90)
        NSColor.white.withAlphaComponent(0.13).setStroke()
        outer.lineWidth = 2; outer.stroke()

        // Three quiet geometric panels suggest a page layout, with no lettering.
        let panels: [(NSRect, NSColor)] = [
            (NSRect(x: 280, y: 600, width: 464, height: 132), NSColor(calibratedWhite: 0.97, alpha: 1)),
            (NSRect(x: 280, y: 292, width: 216, height: 260), NSColor(calibratedWhite: 0.97, alpha: 1)),
            (NSRect(x: 544, y: 292, width: 200, height: 260), NSColor(calibratedRed: 0.52, green: 0.67, blue: 0.88, alpha: 1))
        ]
        for (rect, color) in panels {
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 24, yRadius: 24).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
