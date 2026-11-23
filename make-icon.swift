import AppKit

let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)

func render(pixels: Int, filename: String) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(pixels) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880),
                            xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(calibratedRed: 0.24, green: 0.29, blue: 0.38, alpha: 1),
               ending: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.15, alpha: 1))!
        .draw(in: tile, angle: -90)
    let symbol = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 512, weight: .regular))!
    let ratio = symbol.size.height / symbol.size.width
    let rect = NSRect(x: 208, y: (1024 - 608 * ratio) / 2, width: 608, height: 608 * ratio)
    // Render an opaque white symbol with its existing transparent button cutouts.
    let whiteSymbol = NSImage(size: symbol.size, flipped: false) { bounds in
        symbol.draw(in: bounds)
        NSColor.white.setFill()
        bounds.fill(using: .sourceIn)
        return true
    }
    whiteSymbol.draw(in: rect)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
}

for size in [16, 32, 128, 256, 512] {
    try render(pixels: size, filename: "icon_\(size)x\(size).png")
    try render(pixels: size * 2, filename: "icon_\(size)x\(size)@2x.png")
}
