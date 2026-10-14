// Renders the app icon (1024×1024 PNG).
// Usage: swift tools/make_icon.swift output.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(white: v, alpha: a) }

// Icon body (standard macOS grid: 824×824 with a 100px margin).
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
gray(0.12).setFill()
bodyPath.fill()
NSGraphicsContext.restoreGraphicsState()

// Subtle graphite
NSGradient(colors: [gray(0.20), gray(0.09)])!.draw(in: bodyPath, angle: -90)

// Same symbol used in the menu bar (macwindow.on.rectangle)
let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .regular)
    .applying(NSImage.SymbolConfiguration(paletteColors: [gray(1, 0.92)]))
let symbol = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: nil)!
    .withSymbolConfiguration(config)!
let s = symbol.size
symbol.draw(in: NSRect(x: body.midX - s.width / 2, y: body.midY - s.height / 2,
                       width: s.width, height: s.height))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("icon saved to \(out)")
