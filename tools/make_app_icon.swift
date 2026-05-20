import AppKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    fputs("Usage: make_app_icon.swift <output.iconset> [emoji]\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: arguments[1])
let emoji = arguments.count >= 3 ? arguments[2] : "🧭"
let fileManager = FileManager.default

try? fileManager.removeItem(at: outputURL)
try fileManager.createDirectory(at: outputURL, withIntermediateDirectories: true)

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func drawIcon(pixels: Int) -> NSImage {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)

    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let rect = NSRect(origin: .zero, size: size)
    NSColor.clear.setFill()
    rect.fill()

    // Rounded square tile (standard macOS app icon shape).
    let tileRect = rect.insetBy(dx: CGFloat(pixels) * 0.055, dy: CGFloat(pixels) * 0.055)
    let cornerRadius = CGFloat(pixels) * 0.215
    let tile = NSBezierPath(roundedRect: tileRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let tileShadow = NSShadow()
    tileShadow.shadowBlurRadius = CGFloat(pixels) * 0.040
    tileShadow.shadowOffset = NSSize(width: 0, height: -CGFloat(pixels) * 0.018)
    tileShadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.20)
    tileShadow.set()

    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.49, blue: 0.96, alpha: 1),
        NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.78, alpha: 1)
    ])
    gradient?.draw(in: tile, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Subtle inner highlight along the top edge.
    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    let highlight = NSBezierPath(ovalIn: NSRect(
        x: CGFloat(pixels) * 0.18,
        y: CGFloat(pixels) * 0.62,
        width: CGFloat(pixels) * 0.64,
        height: CGFloat(pixels) * 0.22
    ))
    NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
    highlight.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Centered emoji as the focal element.
    let fontSize = CGFloat(pixels) * 0.62
    let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: emoji, attributes: attributes)
    let textSize = attributed.size()
    let textOrigin = NSPoint(
        x: (CGFloat(pixels) - textSize.width) / 2,
        // Optical center sits slightly above geometric center for emoji.
        y: (CGFloat(pixels) - textSize.height) / 2 - CGFloat(pixels) * 0.02
    )
    attributed.draw(at: textOrigin)

    return image
}

for size in sizes {
    let image = drawIcon(pixels: size.pixels)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(size.name)\n", stderr)
        exit(1)
    }

    try png.write(to: outputURL.appendingPathComponent(size.name))
}
