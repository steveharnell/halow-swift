import AppKit

guard CommandLine.arguments.count == 2 else { exit(1) }
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let tile = NSBezierPath(roundedRect: NSRect(x: 52, y: 52, width: 920, height: 920), xRadius: 202, yRadius: 202)
NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.62, blue: 0.58, alpha: 1),
           ending: NSColor(srgbRed: 0.025, green: 0.25, blue: 0.32, alpha: 1))?.draw(in: tile, angle: -65)
if let symbol = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right", accessibilityDescription: nil)?
    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 440, weight: .medium)) {
    let glyph = NSImage(size: symbol.size)
    glyph.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.setFill()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    glyph.unlockFocus()
    let width: CGFloat = 600
    let height = width * glyph.size.height / glyph.size.width
    glyph.draw(in: NSRect(x: (1024 - width) / 2, y: (1024 - height) / 2, width: width, height: height))
}
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
