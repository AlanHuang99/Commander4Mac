import AppKit
import Foundation

// Format preparation for the legacy macOS .icns pipeline. The original
// unmasked artwork is retained separately for a future layered icon.
guard CommandLine.arguments.count == 3 else { fatalError("usage: render_icon.swift master.png output.iconset") }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
guard let artwork = NSImage(contentsOf: input), artwork.size.width == artwork.size.height else { fatalError("Expected square artwork") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: pixels * 4, bitsPerPixel: 32),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate icon bitmap") }
        bitmap.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.imageInterpolation = .high
        context.cgContext.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let unit = CGFloat(pixels) / 1024
        let tile = NSRect(x: 96 * unit, y: 96 * unit, width: 832 * unit, height: 832 * unit)
        NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit).addClip()
        artwork.draw(in: tile, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
        let suffix = scale == 2 ? "@2x" : ""
        try data.write(to: output.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
    }
}
