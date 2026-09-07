#!/usr/bin/env swift
//
// Erzeugt die App-Icons (hell, dunkel, getönt) als 1024×1024-PNG.
//
// Zwei Sätze:
//   AppIcon.appiconset      – die App, wie sie verteilt wird
//   AppIconDev.appiconset   – dieselbe Zeichnung mit DEV-Band, für den Debug-Build
//
// Beide liegen gleichzeitig auf dem Gerät (verschiedene Bundle-IDs), deshalb muss
// man sie auf dem Homescreen auf einen Blick unterscheiden können.
//
// Aufruf aus dem Projektordner:
//   swift Tools/MakeAppIcon.swift
//
// Kein Pillow, kein ImageMagick – nur CoreGraphics/AppKit.

import AppKit
import CoreGraphics

enum Variant: String {
    case light = "AppIcon-Light"
    case dark = "AppIcon-Dark"
    case tinted = "AppIcon-Tinted"

    var suffix: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .tinted: return "Tinted"
        }
    }
}

let size: CGFloat = 1024
let assetsDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Wyychaellerli/Assets.xcassets")

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [r, g, b, a])!
}

// MARK: - Hintergrund

func drawBackground(_ ctx: CGContext, variant: Variant) {
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    switch variant {
    case .light:
        // Bordeaux-Verlauf von oben links nach unten rechts
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(0.62, 0.16, 0.29), color(0.42, 0.09, 0.19), color(0.24, 0.05, 0.11)] as CFArray,
            locations: [0, 0.55, 1]
        )!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        // Weiches Licht oben links
        let glow = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(1, 0.85, 0.7, 0.28), color(1, 0.85, 0.7, 0)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 300, y: 800), startRadius: 0,
                               endCenter: CGPoint(x: 300, y: 800), endRadius: 700, options: [])
    case .dark:
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [color(0.16, 0.09, 0.12), color(0.07, 0.04, 0.06)] as CFArray,
            locations: [0, 1]
        )!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    case .tinted:
        // Transparent – iOS färbt das Graustufenbild selbst ein.
        ctx.clear(rect)
    }
}

// MARK: - Weinglas

/// Pfad der Glasschale (Kelch), oben offen, unten spitz zulaufend zum Stiel.
func bowlPath() -> CGPath {
    let path = CGMutablePath()
    let rimY: CGFloat = 790, rimHalfWidth: CGFloat = 215
    let bottom = CGPoint(x: 512, y: 372)
    path.move(to: CGPoint(x: 512 - rimHalfWidth, y: rimY))
    path.addCurve(to: bottom,
                  control1: CGPoint(x: 512 - rimHalfWidth - 10, y: 560),
                  control2: CGPoint(x: 512 - 110, y: 380))
    path.addCurve(to: CGPoint(x: 512 + rimHalfWidth, y: rimY),
                  control1: CGPoint(x: 512 + 110, y: 380),
                  control2: CGPoint(x: 512 + rimHalfWidth + 10, y: 560))
    path.closeSubpath()
    return path
}

func drawGlass(_ ctx: CGContext, variant: Variant) {
    let glassStroke: CGColor
    let glassFill: CGColor
    let wineTop: CGColor
    let wineBottom: CGColor
    switch variant {
    case .light:
        glassStroke = color(1, 1, 1, 0.95)
        glassFill = color(1, 1, 1, 0.14)
        wineTop = color(0.98, 0.83, 0.52)
        wineBottom = color(0.88, 0.62, 0.30)
    case .dark:
        glassStroke = color(0.96, 0.92, 0.90, 0.95)
        glassFill = color(1, 1, 1, 0.10)
        wineTop = color(0.90, 0.36, 0.48)
        wineBottom = color(0.62, 0.16, 0.29)
    case .tinted:
        glassStroke = color(1, 1, 1, 1)
        glassFill = color(1, 1, 1, 0.22)
        wineTop = color(1, 1, 1, 0.75)
        wineBottom = color(1, 1, 1, 0.55)
    }

    let bowl = bowlPath()
    let lineWidth: CGFloat = 26

    // Schatten unter dem Glas (nur mit Hintergrund)
    if variant != .tinted {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: color(0, 0, 0, 0.35))
        ctx.addPath(bowl)
        ctx.setFillColor(color(0, 0, 0, 0.001))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // Glasfüllung (leicht transparent)
    ctx.saveGState()
    ctx.addPath(bowl)
    ctx.setFillColor(glassFill)
    ctx.fillPath()
    ctx.restoreGState()

    // Wein im Kelch: unterhalb der Weinlinie, auf den Kelch beschnitten
    ctx.saveGState()
    ctx.addPath(bowl)
    ctx.clip()
    let wineLevel: CGFloat = 610
    let wineGradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [wineTop, wineBottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(wineGradient,
                           start: CGPoint(x: 512, y: wineLevel),
                           end: CGPoint(x: 512, y: 372), options: [])
    // Oberfläche des Weins als flache Ellipse
    ctx.setFillColor(color(1, 1, 1, 0.22))
    ctx.fillEllipse(in: CGRect(x: 512 - 190, y: wineLevel - 22, width: 380, height: 44))
    ctx.restoreGState()

    // Kelch-Kontur
    ctx.saveGState()
    ctx.addPath(bowl)
    ctx.setStrokeColor(glassStroke)
    ctx.setLineWidth(lineWidth)
    ctx.setLineJoin(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Glanzlicht links im Kelch
    ctx.saveGState()
    let highlight = CGMutablePath()
    highlight.move(to: CGPoint(x: 360, y: 730))
    highlight.addQuadCurve(to: CGPoint(x: 395, y: 500), control: CGPoint(x: 330, y: 610))
    ctx.addPath(highlight)
    ctx.setStrokeColor(color(1, 1, 1, variant == .tinted ? 0.9 : 0.55))
    ctx.setLineWidth(16)
    ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()

    // Stiel
    ctx.saveGState()
    ctx.setFillColor(glassStroke)
    let stem = CGRect(x: 512 - 15, y: 205, width: 30, height: 180)
    ctx.addPath(CGPath(roundedRect: stem, cornerWidth: 15, cornerHeight: 15, transform: nil))
    ctx.fillPath()
    // Fuß
    let foot = CGRect(x: 512 - 165, y: 168, width: 330, height: 52)
    ctx.addPath(CGPath(roundedRect: foot, cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

// MARK: - Rendern und speichern

/// Band mit „DEV“ über die untere Ecke – auch in der kleinsten Darstellung lesbar.
func drawDevBadge(_ ctx: CGContext) {
    let height = size * 0.26
    let band = CGRect(x: 0, y: 0, width: size, height: height)
    ctx.saveGState()
    ctx.setFillColor(color(0.95, 0.55, 0.10, 0.95))
    ctx.fill(band)
    ctx.setFillColor(color(0, 0, 0, 0.18))
    ctx.fill(CGRect(x: 0, y: height - 8, width: size, height: 8))
    ctx.restoreGState()

    let text = NSAttributedString(string: "DEV", attributes: [
        .font: NSFont.systemFont(ofSize: size * 0.17, weight: .heavy),
        .foregroundColor: NSColor.white,
        .kern: size * 0.02
    ])
    let line = text.size()
    let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    text.draw(at: CGPoint(x: (size - line.width) / 2, y: (height - line.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
}

func render(_ variant: Variant, dev: Bool) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw NSError(domain: "MakeAppIcon", code: 1) }

    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    drawBackground(ctx, variant: variant)
    drawGlass(ctx, variant: variant)
    if dev { drawDevBadge(ctx) }

    guard let image = ctx.makeImage() else { throw NSError(domain: "MakeAppIcon", code: 2) }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "MakeAppIcon", code: 3)
    }
    let set = assetsDirectory.appendingPathComponent(dev ? "AppIconDev.appiconset" : "AppIcon.appiconset")
    let name = dev ? "AppIconDev-\(variant.suffix).png" : "\(variant.rawValue).png"
    try png.write(to: set.appendingPathComponent(name))
    print("✓ \(set.lastPathComponent)/\(name)")
}

for dev in [false, true] {
    let set = assetsDirectory.appendingPathComponent(dev ? "AppIconDev.appiconset" : "AppIcon.appiconset")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for variant in [Variant.light, .dark, .tinted] {
        try render(variant, dev: dev)
    }
}
