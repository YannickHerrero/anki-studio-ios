#!/usr/bin/env swift
// Renders the app icon: minimalist white-and-green liquid glass, using the
// Anki card template's accent greens (styling.css --accent). A frosted glass
// squircle floating on white, top light sheen, soft inner rim, and a white あ.
//
//   swift Scripts/render-icon.swift Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png

import AppKit
import CoreText

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "icon-1024.png"

let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size),
    bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// ---- Background: white with the faintest warm-green vertical wash
let bg = CGGradient(
    colorsSpace: nil,
    colors: [rgba(255, 255, 255), rgba(238, 246, 241)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// ---- Glass squircle
let cardRect = CGRect(x: 152, y: 152, width: 720, height: 720)
let card = CGPath(roundedRect: cardRect, cornerWidth: 180, cornerHeight: 180, transform: nil)

// Soft ambient shadow behind the glass
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 70, color: rgba(51, 81, 60, 0.30))
ctx.addPath(card)
ctx.setFillColor(rgba(255, 255, 255))
ctx.fillPath()
ctx.restoreGState()

// Green glass body (deep → bright, bottom-left to top-right) — the card
// template's --accent #3f7d5f rising to its dark-mode #84c9a6.
ctx.saveGState()
ctx.addPath(card)
ctx.clip()
let glass = CGGradient(
    colorsSpace: nil,
    colors: [rgba(63, 125, 95), rgba(132, 201, 166)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    glass,
    start: CGPoint(x: cardRect.minX, y: cardRect.minY),
    end: CGPoint(x: cardRect.maxX, y: cardRect.maxY),
    options: []
)

// Liquid sheen: bright diagonal band across the upper half
let sheen = CGGradient(
    colorsSpace: nil,
    colors: [rgba(255, 255, 255, 0.42), rgba(255, 255, 255, 0.05), rgba(255, 255, 255, 0)] as CFArray,
    locations: [0, 0.55, 1]
)!
ctx.drawLinearGradient(
    sheen,
    start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
    end: CGPoint(x: cardRect.midX, y: cardRect.midY - 60),
    options: []
)

// Bottom-edge glow (light refracting through the glass)
let glow = CGGradient(
    colorsSpace: nil,
    colors: [rgba(214, 240, 226, 0.55), rgba(214, 240, 226, 0)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(
    glow,
    start: CGPoint(x: cardRect.midX, y: cardRect.minY),
    end: CGPoint(x: cardRect.midX, y: cardRect.minY + 200),
    options: []
)
ctx.restoreGState()

// Inner rim highlight
ctx.saveGState()
ctx.addPath(CGPath(
    roundedRect: cardRect.insetBy(dx: 7, dy: 7),
    cornerWidth: 173, cornerHeight: 173, transform: nil))
ctx.setStrokeColor(rgba(255, 255, 255, 0.55))
ctx.setLineWidth(4)
ctx.strokePath()
ctx.restoreGState()

// ---- あ glyph, white, centered
let font = CTFontCreateWithName("HiraginoSans-W6" as CFString, 500, nil)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
]
let line = CTLineCreateWithAttributedString(
    NSAttributedString(string: "あ", attributes: attributes))
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgba(38, 77, 58, 0.45))
ctx.textPosition = CGPoint(
    x: cardRect.midX - bounds.midX,
    y: cardRect.midY - bounds.midY
)
CTLineDraw(line, ctx)
ctx.restoreGState()

// ---- Write PNG
let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out)")
