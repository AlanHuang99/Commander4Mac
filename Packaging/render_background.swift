import AppKit
import Foundation

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let width: CGFloat = 720, height: CGFloat = 480
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: Int(width) * scale * 4, bitsPerPixel: 32)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    NSGradient(starting: color(0.96, 0.98, 1), ending: color(0.91, 0.95, 0.97))!.draw(in: canvas, angle: -75)
    func text(_ value: String, x: CGFloat, top: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
        (value as NSString).draw(in: NSRect(x: x, y: height - top - size * 1.5, width: width - x - 40, height: size * 1.5),
            withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink, .paragraphStyle: style])
    }
    let navy = color(0.08, 0.14, 0.24), secondary = color(0.29, 0.37, 0.46)
    text("COMMANDER4MAC", x: 44, top: 29, size: 11, weight: .semibold, ink: color(0.13, 0.36, 0.58))
    text("Install Commander4Mac", x: 44, top: 57, size: 29, weight: .semibold, ink: navy)
    text("Drag the app to Applications.", x: 44, top: 105, size: 16, weight: .regular, ink: secondary)
    // This is a directional cue, never a fake clickable control.
    let arrow = NSBezierPath(); arrow.move(to: NSPoint(x: 326, y: height - 232)); arrow.line(to: NSPoint(x: 393, y: height - 232))
    arrow.move(to: NSPoint(x: 380, y: height - 219)); arrow.line(to: NSPoint(x: 393, y: height - 232)); arrow.line(to: NSPoint(x: 380, y: height - 245))
    arrow.lineWidth = 2.5; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
    color(0.13, 0.51, 0.58).setStroke(); arrow.stroke()
    color(0.78, 0.84, 0.89).setStroke()
    let rule = NSBezierPath(); rule.move(to: NSPoint(x: 44, y: height - 348)); rule.line(to: NSPoint(x: 676, y: height - 348)); rule.lineWidth = 1; rule.stroke()
    text("After copying, open the app from Applications.", x: 44, top: 373, size: 14, weight: .medium, ink: navy)
    text("Then eject this disk image. First launch guides you through Full Disk Access.", x: 44, top: 402, size: 12, weight: .regular, ink: secondary)
    text("macOS 15 or later", x: 550, top: 29, size: 11, weight: .regular, ink: secondary)
    NSGraphicsContext.restoreGraphicsState()
    let suffix = scale == 1 ? "" : "@2x"
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("background\(suffix).png"), options: .atomic)
}
