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
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.40, blue: 0.52, alpha: 1), ending: NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.29, alpha: 1))!
        gradient.draw(in: outer, angle: -90)
        NSColor.white.withAlphaComponent(0.13).setStroke()
        outer.lineWidth = 2; outer.stroke()

        // One folded ivory sheet: the F is also three typeset lines on the page.
        let paper = NSBezierPath()
        paper.move(to: NSPoint(x: 310, y: 212))
        paper.line(to: NSPoint(x: 714, y: 212))
        paper.curve(to: NSPoint(x: 750, y: 248), controlPoint1: NSPoint(x: 738, y: 212), controlPoint2: NSPoint(x: 750, y: 224))
        paper.line(to: NSPoint(x: 750, y: 692))
        paper.line(to: NSPoint(x: 618, y: 824))
        paper.line(to: NSPoint(x: 310, y: 824))
        paper.curve(to: NSPoint(x: 274, y: 788), controlPoint1: NSPoint(x: 286, y: 824), controlPoint2: NSPoint(x: 274, y: 812))
        paper.line(to: NSPoint(x: 274, y: 248))
        paper.curve(to: NSPoint(x: 310, y: 212), controlPoint1: NSPoint(x: 274, y: 224), controlPoint2: NSPoint(x: 286, y: 212))
        paper.close()
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.25); shadow.shadowBlurRadius = 26; shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.set()
        NSColor(calibratedRed: 0.98, green: 0.97, blue: 0.93, alpha: 1).setFill()
        paper.fill()
        NSGraphicsContext.restoreGraphicsState()
        let fold = NSBezierPath()
        fold.move(to: NSPoint(x: 618, y: 824)); fold.line(to: NSPoint(x: 618, y: 724))
        fold.curve(to: NSPoint(x: 650, y: 692), controlPoint1: NSPoint(x: 618, y: 703), controlPoint2: NSPoint(x: 629, y: 692))
        fold.line(to: NSPoint(x: 750, y: 692)); fold.close()
        NSColor(calibratedRed: 0.79, green: 0.84, blue: 0.84, alpha: 1).setFill(); fold.fill()
        let ink = NSColor(calibratedRed: 0.15, green: 0.29, blue: 0.39, alpha: 1)
        ink.setFill()
        NSBezierPath(roundedRect: NSRect(x: 376, y: 352, width: 58, height: 294), xRadius: 9, yRadius: 9).fill()
        NSBezierPath(roundedRect: NSRect(x: 376, y: 590, width: 244, height: 56), xRadius: 9, yRadius: 9).fill()
        NSBezierPath(roundedRect: NSRect(x: 376, y: 474, width: 194, height: 52), xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
