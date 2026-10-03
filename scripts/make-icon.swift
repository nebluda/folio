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
        // Flat monochrome tile and a single folded-page outline.
        let outer = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206)
        NSColor(calibratedWhite: 0.16, alpha: 1).setFill()
        outer.fill()

        let page = NSBezierPath()
        page.move(to: NSPoint(x: 344, y: 260))
        page.line(to: NSPoint(x: 680, y: 260))
        page.line(to: NSPoint(x: 680, y: 650))
        page.line(to: NSPoint(x: 582, y: 748))
        page.line(to: NSPoint(x: 344, y: 748))
        page.close()
        page.move(to: NSPoint(x: 582, y: 748))
        page.line(to: NSPoint(x: 582, y: 650))
        page.line(to: NSPoint(x: 680, y: 650))
        page.lineWidth = 42
        page.lineJoinStyle = .round
        page.lineCapStyle = .round
        NSColor(calibratedWhite: 0.56, alpha: 1).setStroke()
        page.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
