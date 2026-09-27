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
        let outer = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 206, yRadius: 206)
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.27, green: 0.47, blue: 0.59, alpha: 1), ending: NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.38, alpha: 1))!
        gradient.draw(in: outer, angle: -90)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.2); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.set()
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 264, y: 198, width: 496, height: 638), xRadius: 32, yRadius: 32).fill()
        NSGraphicsContext.restoreGraphicsState()
        let ink = NSColor(calibratedRed: 0.19, green: 0.34, blue: 0.44, alpha: 1)
        let text: NSString = "#"
        text.draw(at: NSPoint(x: 318, y: 586), withAttributes: [.font: NSFont.systemFont(ofSize: 175, weight: .semibold), .foregroundColor: ink])
        for (y, width) in [(514, 352), (426, 352), (338, 252)] {
            ink.withAlphaComponent(y == 514 ? 0.65 : 0.27).setFill()
            NSBezierPath(roundedRect: NSRect(x: 332, y: y, width: width, height: 24), xRadius: 12, yRadius: 12).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
