// Renders an .iconset directory of PNGs for the Syncthing Notifier app icon.
// Usage: make_icon <output-iconset-dir>
//
// Pipe the resulting directory through `iconutil -c icns` to get an .icns.
// Pure Core Graphics + ImageIO — no AppKit, runs cleanly from a CLI.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("usage: make_icon <iconset-dir>\n".utf8))
    exit(2)
}
let outDir = args[1]
try? FileManager.default.createDirectory(
    atPath: outDir, withIntermediateDirectories: true)

// .iconset entries Apple expects for a complete icon family.
let entries: [(name: String, size: Int)] = [
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

func deg2rad(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

enum IconError: Error { case contextFailed, encodeFailed }

func renderImage(size: Int) throws -> CGImage {
    let s = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw IconError.contextFailed }

    // 1. Rounded-square background with vertical blue gradient.
    let radius = s * 0.2237  // matches macOS Big Sur+ app-icon mask ratio
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(
        roundedRect: bgRect,
        cornerWidth: radius, cornerHeight: radius,
        transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [
            CGColor(red: 0.22, green: 0.66, blue: 0.96, alpha: 1.0),
            CGColor(red: 0.04, green: 0.38, blue: 0.74, alpha: 1.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    // y-axis up: top of icon is y=s. Lighter top → darker bottom.
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: 0, y: 0),
        options: [])
    ctx.restoreGState()

    // 2. Two white circular arrows ("sync" glyph), drawn manually.
    let cx = s / 2, cy = s / 2
    let r = s * 0.28
    let lw = s * 0.10
    let arrowSize = lw * 1.3

    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)

    // Top half-arc: 160° → 20° clockwise (passes through 90°, top of circle).
    ctx.beginPath()
    ctx.addArc(
        center: CGPoint(x: cx, y: cy), radius: r,
        startAngle: deg2rad(160), endAngle: deg2rad(20),
        clockwise: true)
    ctx.strokePath()

    // Bottom half-arc: 340° → 200° clockwise (passes through 270°, bottom).
    ctx.beginPath()
    ctx.addArc(
        center: CGPoint(x: cx, y: cy), radius: r,
        startAngle: deg2rad(340), endAngle: deg2rad(200),
        clockwise: true)
    ctx.strokePath()

    // Arrowhead at end of each arc, pointing in the clockwise tangent direction.
    func arrowhead(atDeg deg: CGFloat) {
        let rad = deg2rad(deg)
        let tip = CGPoint(x: cx + r * cos(rad), y: cy + r * sin(rad))
        // Clockwise tangent unit vector at angle θ: (sin θ, -cos θ).
        let vx = sin(rad), vy = -cos(rad)
        // Outward radial unit vector: (cos θ, sin θ).
        let nx = cos(rad), ny = sin(rad)
        let backX = tip.x - arrowSize * vx
        let backY = tip.y - arrowSize * vy
        let half = arrowSize * 0.75
        ctx.beginPath()
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: backX + half * nx, y: backY + half * ny))
        ctx.addLine(to: CGPoint(x: backX - half * nx, y: backY - half * ny))
        ctx.closePath()
        ctx.fillPath()
    }
    arrowhead(atDeg: 20)   // end of top arc
    arrowhead(atDeg: 200)  // end of bottom arc

    guard let img = ctx.makeImage() else { throw IconError.contextFailed }
    return img
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1, nil
    ) else { throw IconError.encodeFailed }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { throw IconError.encodeFailed }
}

for (name, size) in entries {
    let image = try renderImage(size: size)
    let url = URL(fileURLWithPath: "\(outDir)/\(name)")
    try writePNG(image, to: url)
}

print("wrote \(entries.count) PNGs to \(outDir)")
