import AppKit

// Native vector drawing of the menu-bar mark, rendered as a 1024 px app icon.
let destination = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.png"
let size = NSSize(width: 1024, height: 1024)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.black.setFill()
NSBezierPath(roundedRect: CGRect(x: 42, y: 42, width: 940, height: 940), xRadius: 210, yRadius: 210).fill()
NSColor.white.setStroke()
let frame = NSBezierPath(roundedRect: CGRect(x: 218, y: 302, width: 588, height: 420), xRadius: 65, yRadius: 65)
frame.lineWidth = 45
frame.stroke()
NSColor.white.setFill()
NSBezierPath(ovalIn: CGRect(x: 426, y: 426, width: 172, height: 172)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
