#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetURL = URL(fileURLWithPath: "native/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for icon in icons {
    let image = drawIcon(size: CGFloat(icon.pixels))
    let destination = iconsetURL.appendingPathComponent(icon.name)
    try writePNG(image: image, to: destination)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let background = NSBezierPath(roundedRect: canvas.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: size * 0.18, yRadius: size * 0.18)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.10, green: 0.35, blue: 0.95, alpha: 1),
        NSColor(calibratedRed: 0.05, green: 0.68, blue: 0.58, alpha: 1),
    ])
    gradient?.draw(in: background, angle: 135)

    drawRoute(size: size)
    drawPin(size: size)
    drawCar(size: size)
    drawYuan(size: size)

    return image
}

func drawRoute(size: CGFloat) {
    let route = NSBezierPath()
    route.move(to: CGPoint(x: size * 0.18, y: size * 0.28))
    route.curve(
        to: CGPoint(x: size * 0.78, y: size * 0.70),
        controlPoint1: CGPoint(x: size * 0.34, y: size * 0.18),
        controlPoint2: CGPoint(x: size * 0.58, y: size * 0.86)
    )
    route.lineWidth = max(2, size * 0.035)
    NSColor.white.withAlphaComponent(0.32).setStroke()
    route.stroke()
}

func drawPin(size: CGFloat) {
    let pin = NSBezierPath()
    pin.move(to: CGPoint(x: size * 0.70, y: size * 0.78))
    pin.curve(
        to: CGPoint(x: size * 0.57, y: size * 0.58),
        controlPoint1: CGPoint(x: size * 0.60, y: size * 0.78),
        controlPoint2: CGPoint(x: size * 0.52, y: size * 0.70)
    )
    pin.curve(
        to: CGPoint(x: size * 0.70, y: size * 0.34),
        controlPoint1: CGPoint(x: size * 0.58, y: size * 0.48),
        controlPoint2: CGPoint(x: size * 0.66, y: size * 0.40)
    )
    pin.curve(
        to: CGPoint(x: size * 0.83, y: size * 0.58),
        controlPoint1: CGPoint(x: size * 0.74, y: size * 0.40),
        controlPoint2: CGPoint(x: size * 0.82, y: size * 0.48)
    )
    pin.curve(
        to: CGPoint(x: size * 0.70, y: size * 0.78),
        controlPoint1: CGPoint(x: size * 0.88, y: size * 0.70),
        controlPoint2: CGPoint(x: size * 0.80, y: size * 0.78)
    )
    pin.close()
    NSColor(calibratedRed: 0.99, green: 0.88, blue: 0.28, alpha: 1).setFill()
    pin.fill()

    let dot = NSBezierPath(ovalIn: NSRect(x: size * 0.66, y: size * 0.58, width: size * 0.08, height: size * 0.08))
    NSColor(calibratedRed: 0.08, green: 0.30, blue: 0.70, alpha: 1).setFill()
    dot.fill()
}

func drawCar(size: CGFloat) {
    let bodyRect = NSRect(x: size * 0.18, y: size * 0.30, width: size * 0.52, height: size * 0.23)
    let body = NSBezierPath(roundedRect: bodyRect, xRadius: size * 0.06, yRadius: size * 0.06)
    NSColor.white.setFill()
    body.fill()

    let cabin = NSBezierPath()
    cabin.move(to: CGPoint(x: size * 0.29, y: size * 0.53))
    cabin.line(to: CGPoint(x: size * 0.39, y: size * 0.66))
    cabin.line(to: CGPoint(x: size * 0.56, y: size * 0.66))
    cabin.line(to: CGPoint(x: size * 0.64, y: size * 0.53))
    cabin.close()
    NSColor.white.setFill()
    cabin.fill()

    NSColor(calibratedRed: 0.10, green: 0.42, blue: 0.82, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: size * 0.38, y: size * 0.55, width: size * 0.18, height: size * 0.07), xRadius: size * 0.02, yRadius: size * 0.02).fill()

    let wheelColor = NSColor(calibratedRed: 0.06, green: 0.12, blue: 0.22, alpha: 1)
    wheelColor.setFill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.25, y: size * 0.24, width: size * 0.11, height: size * 0.11)).fill()
    NSBezierPath(ovalIn: NSRect(x: size * 0.55, y: size * 0.24, width: size * 0.11, height: size * 0.11)).fill()
}

func drawYuan(size: CGFloat) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let fontSize = size * 0.20
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    let rect = NSRect(x: size * 0.58, y: size * 0.15, width: size * 0.27, height: size * 0.24)
    "¥".draw(in: rect, withAttributes: attributes)
}

func writePNG(image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not render PNG"])
    }

    try png.write(to: url)
}
