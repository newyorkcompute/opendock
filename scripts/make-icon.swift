#!/usr/bin/env swift
// Draws the OpenDock app icon with CoreGraphics and writes App/Resources/AppIcon.icns.
//
//   swift scripts/make-icon.swift
//
// Every size is rendered from vectors (no downscaling), then packed with `iconutil`.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry (in a 1024 x 1024 canvas, origin bottom-left)

let canvas: CGFloat = 1024
/// Apple's macOS icon grid: an 824pt body centered in the 1024pt canvas.
let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)

/// A continuous-corner ("squircle") rounded rect. Corner radius is ~22.37% of the side,
/// and the extra control-point distance gives the smooth curvature of macOS icons.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    // The curve starts a little before a circular arc would (1.2r instead of r) and
    // its control points sit closer to the corner, which removes the visible
    // "kink" where a plain rounded rect's arc meets the straight edge.
    let e = min(radius * 1.2, min(rect.width, rect.height) / 2)
    let k: CGFloat = 0.72 // control-point pull toward the corner
    let (minX, minY, maxX, maxY) = (rect.minX, rect.minY, rect.maxX, rect.maxY)

    path.move(to: CGPoint(x: minX + e, y: maxY))
    path.addLine(to: CGPoint(x: maxX - e, y: maxY))
    path.addCurve(to: CGPoint(x: maxX, y: maxY - e),
                  control1: CGPoint(x: maxX - e + e * k, y: maxY),
                  control2: CGPoint(x: maxX, y: maxY - e + e * k))
    path.addLine(to: CGPoint(x: maxX, y: minY + e))
    path.addCurve(to: CGPoint(x: maxX - e, y: minY),
                  control1: CGPoint(x: maxX, y: minY + e - e * k),
                  control2: CGPoint(x: maxX - e + e * k, y: minY))
    path.addLine(to: CGPoint(x: minX + e, y: minY))
    path.addCurve(to: CGPoint(x: minX, y: minY + e),
                  control1: CGPoint(x: minX + e - e * k, y: minY),
                  control2: CGPoint(x: minX, y: minY + e - e * k))
    path.addLine(to: CGPoint(x: minX, y: maxY - e))
    path.addCurve(to: CGPoint(x: minX + e, y: maxY),
                  control1: CGPoint(x: minX, y: maxY - e + e * k),
                  control2: CGPoint(x: minX + e - e * k, y: maxY))
    path.closeSubpath()
    return path
}

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func white(_ alpha: CGFloat) -> CGColor { CGColor(gray: 1, alpha: alpha) }

func linearGradient(_ colors: [CGColor], locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

// MARK: - Drawing

func drawIcon(in ctx: CGContext) {
    let body = continuousRoundedRect(bodyRect, radius: bodyRect.width * 0.2237)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0x1B2A6B))
    ctx.fillPath()
    ctx.restoreGState()

    // Body: dark blue at the top to indigo at the bottom.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    ctx.drawLinearGradient(
        linearGradient([rgb(0x1E3A8A), rgb(0x312E81), rgb(0x4C1D95)], locations: [0, 0.55, 1]),
        start: CGPoint(x: 0, y: bodyRect.maxY),
        end: CGPoint(x: 0, y: bodyRect.minY),
        options: []
    )

    // Glass highlight: a soft glow from the top edge.
    ctx.drawRadialGradient(
        linearGradient([white(0.28), white(0)]),
        startCenter: CGPoint(x: bodyRect.midX, y: bodyRect.maxY + 140),
        startRadius: 0,
        endCenter: CGPoint(x: bodyRect.midX, y: bodyRect.maxY + 140),
        endRadius: 620,
        options: []
    )
    // Faint reflected light at the bottom.
    ctx.drawLinearGradient(
        linearGradient([white(0), white(0.06)]),
        start: CGPoint(x: 0, y: bodyRect.minY + 220),
        end: CGPoint(x: 0, y: bodyRect.minY),
        options: []
    )
    ctx.restoreGState()

    // Inner rim.
    ctx.saveGState()
    ctx.addPath(continuousRoundedRect(bodyRect.insetBy(dx: 3, dy: 3), radius: (bodyRect.width - 6) * 0.2237))
    ctx.setStrokeColor(white(0.14))
    ctx.setLineWidth(4)
    ctx.strokePath()
    ctx.restoreGState()

    drawDock(in: ctx)
}

/// A translucent dock pill with four app tiles and one wider widget tile.
func drawDock(in ctx: CGContext) {
    let tile: CGFloat = 96
    let widgetWidth: CGFloat = 176
    let gap: CGFloat = 18
    let padding: CGFloat = 24
    let contentWidth = tile * 4 + widgetWidth + gap * 4
    let pill = CGRect(
        x: canvas / 2 - (contentWidth + padding * 2) / 2,
        y: 392,
        width: contentWidth + padding * 2,
        height: tile + padding * 2
    )
    let pillPath = continuousRoundedRect(pill, radius: 52)

    // Pill: frosted white with a soft shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(pillPath)
    ctx.setFillColor(white(0.16))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(pillPath)
    ctx.clip()
    ctx.drawLinearGradient(
        linearGradient([white(0.16), white(0.02)]),
        start: CGPoint(x: 0, y: pill.maxY),
        end: CGPoint(x: 0, y: pill.minY),
        options: []
    )
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(continuousRoundedRect(pill.insetBy(dx: 1.5, dy: 1.5), radius: 50.5))
    ctx.setStrokeColor(white(0.38))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // App tiles in soft colors, top-to-bottom gradient each.
    let palettes: [(UInt32, UInt32)] = [
        (0xFFB4A2, 0xF0727A), // coral
        (0xFFE29A, 0xF6B04B), // amber
        (0xB5F5D8, 0x4FD1A5), // mint
        (0xA9D0FF, 0x5B8DEF), // sky
    ]
    var x = pill.minX + padding
    let y = pill.minY + padding
    for (index, palette) in palettes.enumerated() {
        let rect = CGRect(x: x, y: y, width: tile, height: tile)
        drawTile(rect, radius: 26, top: rgb(palette.0), bottom: rgb(palette.1), in: ctx)
        // Running indicators under the first two apps.
        if index < 2 {
            ctx.setFillColor(white(0.85))
            ctx.fillEllipse(in: CGRect(x: rect.midX - 5, y: pill.minY + 8, width: 10, height: 10))
        }
        x += tile + gap
    }

    // Widget tile: a light pill with two "lines of text".
    let widget = CGRect(x: x, y: y, width: widgetWidth, height: tile)
    drawTile(widget, radius: 26, top: white(0.92), bottom: rgb(0xD9DEFF), in: ctx)
    ctx.setFillColor(rgb(0x312E81, 0.85))
    ctx.addPath(CGPath(roundedRect: CGRect(x: widget.minX + 22, y: widget.midY + 4, width: 104, height: 22),
                       cornerWidth: 11, cornerHeight: 11, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(rgb(0x312E81, 0.4))
    ctx.addPath(CGPath(roundedRect: CGRect(x: widget.minX + 22, y: widget.midY - 26, width: 70, height: 16),
                       cornerWidth: 8, cornerHeight: 8, transform: nil))
    ctx.fillPath()
}

func drawTile(_ rect: CGRect, radius: CGFloat, top: CGColor, bottom: CGColor, in ctx: CGContext) {
    let path = continuousRoundedRect(rect, radius: radius)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 12, color: CGColor(gray: 0, alpha: 0.28))
    ctx.addPath(path)
    ctx.setFillColor(bottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(linearGradient([top, bottom]),
                           start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
    // Glossy top edge.
    ctx.drawLinearGradient(linearGradient([white(0.35), white(0)]),
                           start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.midY), options: [])
    ctx.restoreGState()
}

// MARK: - Output

func renderPNG(pixels: Int, to url: URL) throws {
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw IconError.context }
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    drawIcon(in: ctx)

    guard let image = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw IconError.encode }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw IconError.encode }
}

enum IconError: Error { case context, encode, iconutil(Int32) }

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let output = root.appendingPathComponent("App/Resources/AppIcon.icns")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points, to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2, to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { throw IconError.iconutil(iconutil.terminationStatus) }

try? FileManager.default.removeItem(at: iconset)
print("Wrote \(output.path)")
