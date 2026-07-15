#!/usr/bin/env swift
import AppKit

/// macOS app icons (as rendered by NSWorkspace / Dock) sit on a plate that fills
/// ~80.47% of the canvas — measured from System Settings & Reminders (824/1024).
/// Corner shape is Apple's continuous rounded rect at 22.5% of the plate side
/// (reverse-engineered UIBezierPath continuous corners; see liamrosenfeld.com).

let root = URL(fileURLWithPath: CommandLine.arguments[0])
    .standardizedFileURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()

let iconset = root.appendingPathComponent("AppIcon.iconset")
let icns = root.appendingPathComponent("AppIcon.icns")
let sizes = [16, 32, 128, 256, 512]

// System icon plate fill ratio (opaque bounds of Settings/Reminders via NSWorkspace).
let plateFill: CGFloat = 824.0 / 1024.0
// Continuous corner radius as fraction of plate side (Apple continuous style).
let cornerRadiusFraction: CGFloat = 0.225
// Glyph size relative to plate (matches monochrome system utility icons).
let glyphFraction: CGFloat = 0.52

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

/// Apple continuous-corner path (UIBezierPath roundedRect continuous style).
func continuousRoundedRect(in rect: CGRect, cornerRadius r: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    let ox = rect.origin.x
    let oy = rect.origin.y
    let w = rect.size.width
    let h = rect.size.height

    func tl(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + x * r, y: oy + h - y * r)
    }
    func tr(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + w - x * r, y: oy + h - y * r)
    }
    func br(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + w - x * r, y: oy + y * r)
    }
    func bl(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: ox + x * r, y: oy + y * r)
    }

    // Constants from UIKit continuous rounded rect (top-left origin); flipped for AppKit.
    path.move(to: tl(1.528665, 0.0))
    path.line(to: tr(1.528665, 0.0))
    path.curve(
        to: tr(0.63149379, 0.07491139),
        controlPoint1: tr(1.08849296, 0.0),
        controlPoint2: tr(0.86840694, 0.0)
    )
    path.curve(
        to: tr(0.07491139, 0.63149379),
        controlPoint1: tr(0.37282383, 0.16905956),
        controlPoint2: tr(0.16905956, 0.37282383)
    )
    path.curve(
        to: tr(0.0, 1.52866498),
        controlPoint1: tr(0.0, 0.86840694),
        controlPoint2: tr(0.0, 1.08849296)
    )
    path.line(to: br(0.0, 1.528665))
    path.curve(
        to: br(0.07491139, 0.63149379),
        controlPoint1: br(0.0, 1.08849296),
        controlPoint2: br(0.0, 0.86840694)
    )
    path.curve(
        to: br(0.63149379, 0.07491139),
        controlPoint1: br(0.16905956, 0.37282383),
        controlPoint2: br(0.37282383, 0.16905956)
    )
    path.curve(
        to: br(1.52866498, 0.0),
        controlPoint1: br(0.86840694, 0.0),
        controlPoint2: br(1.08849296, 0.0)
    )
    path.line(to: bl(1.528665, 0.0))
    path.curve(
        to: bl(0.63149379, 0.07491139),
        controlPoint1: bl(1.08849296, 0.0),
        controlPoint2: bl(0.86840694, 0.0)
    )
    path.curve(
        to: bl(0.07491139, 0.63149379),
        controlPoint1: bl(0.37282383, 0.16905956),
        controlPoint2: bl(0.16905956, 0.37282383)
    )
    path.curve(
        to: bl(0.0, 1.52866498),
        controlPoint1: bl(0.0, 0.86840694),
        controlPoint2: bl(0.0, 1.08849296)
    )
    path.line(to: tl(0.0, 1.528665))
    path.curve(
        to: tl(0.07491139, 0.63149379),
        controlPoint1: tl(0.0, 1.08849296),
        controlPoint2: tl(0.0, 0.86840694)
    )
    path.curve(
        to: tl(0.63149379, 0.07491139),
        controlPoint1: tl(0.16905956, 0.37282383),
        controlPoint2: tl(0.37282383, 0.16905956)
    )
    path.curve(
        to: tl(1.52866498, 0.0),
        controlPoint1: tl(0.86840694, 0.0),
        controlPoint2: tl(1.08849296, 0.0)
    )
    path.close()
    return path
}

func drawIcon(pixelSize: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let canvas = CGFloat(pixelSize)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill()

    let plateSide = canvas * plateFill
    let inset = (canvas - plateSide) / 2
    let plate = CGRect(x: inset, y: inset, width: plateSide, height: plateSide)
    let radius = plateSide * cornerRadiusFraction
    let path = continuousRoundedRect(in: plate, cornerRadius: radius)

    // Graphite plate with subtle top-to-bottom gradient (system utility style).
    let top = NSColor(srgbRed: 0.30, green: 0.30, blue: 0.32, alpha: 1)
    let bottom = NSColor(srgbRed: 0.18, green: 0.18, blue: 0.20, alpha: 1)
    NSGradient(starting: top, ending: bottom)!.draw(in: path, angle: -90)

    // Soft top sheen clipped to plate
    NSGraphicsContext.current?.saveGraphicsState()
    path.addClip()
    NSGradient(
        colors: [
            NSColor.white.withAlphaComponent(0.12),
            NSColor.white.withAlphaComponent(0.0),
        ],
        atLocations: [0, 0.5],
        colorSpace: .deviceRGB
    )!.draw(in: NSRect(x: plate.minX, y: plate.midY, width: plate.width, height: plate.height / 2), angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    // microphone.fill, centered on plate
    let pointSize = plateSide * glyphFraction
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "microphone.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let s = symbol.size
        let dest = NSRect(
            x: plate.midX - s.width / 2,
            y: plate.midY - s.height / 2,
            width: s.width,
            height: s.height
        )
        symbol.draw(in: dest, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to encode \(url.lastPathComponent)\n", stderr)
        exit(1)
    }
    try data.write(to: url)
}

for size in sizes {
    try writePNG(drawIcon(pixelSize: size), to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try writePNG(drawIcon(pixelSize: size * 2), to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

try? FileManager.default.removeItem(at: icns)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", icns.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fputs("iconutil failed\n", stderr)
    exit(1)
}

print("Created \(icns.path)")
print("Plate fill: \(plateFill)  corner r: \(cornerRadiusFraction) of plate  glyph: \(glyphFraction) of plate")
