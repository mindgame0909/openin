#!/usr/bin/swift
// Generates AppIcon.iconset for OpenIn.
// Usage: swift make_icon.swift <output-dir> [variant 1-5]
//
// Variants:
//  1 — Globe Blue      (deep blue → sky blue gradient  + globe)
//  2 — Arrow Indigo    (indigo → violet gradient       + arrow.up.right.square.fill)
//  3 — Link Teal       (teal → emerald gradient        + link)
//  4 — Bolt Dark       (charcoal → dark navy gradient  + bolt.fill)
//  5 — Safari Flame    (orange → red gradient          + safari / compass style)

import AppKit
import Foundation

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift make_icon.swift <output-dir> [variant]\n", stderr); exit(1)
}
let outDir  = CommandLine.arguments[1]
let variant = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1 : 1
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// ─────────────────────────────────────────────────────────────
// Per-variant config
// ─────────────────────────────────────────────────────────────
struct IconConfig {
    let color1: (CGFloat, CGFloat, CGFloat)   // top-left (R G B)
    let color2: (CGFloat, CGFloat, CGFloat)   // bottom-right
    let symbol: String
    let gradientAngle: Bool                    // true = top→bottom, false = diagonal
}

let configs: [IconConfig] = [
    // 1: Globe Blue
    IconConfig(color1: (0.00, 0.29, 0.73), color2: (0.09, 0.62, 0.98),
               symbol: "globe", gradientAngle: false),
    // 2: Arrow Indigo
    IconConfig(color1: (0.27, 0.15, 0.78), color2: (0.56, 0.20, 0.92),
               symbol: "arrow.up.right.square.fill", gradientAngle: false),
    // 3: Link Teal
    IconConfig(color1: (0.00, 0.50, 0.50), color2: (0.07, 0.82, 0.60),
               symbol: "link", gradientAngle: false),
    // 4: Bolt Dark
    IconConfig(color1: (0.10, 0.10, 0.20), color2: (0.22, 0.28, 0.50),
               symbol: "bolt.fill", gradientAngle: true),
    // 5: Safari Flame
    IconConfig(color1: (0.85, 0.25, 0.10), color2: (1.00, 0.60, 0.10),
               symbol: "safari", gradientAngle: false),
]

let cfg = configs[min(max(variant - 1, 0), configs.count - 1)]

// ─────────────────────────────────────────────────────────────
// Render one size
// ─────────────────────────────────────────────────────────────
func renderIcon(pixelSize: Int) -> Data {
    let s  = CGFloat(pixelSize)
    let cs = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(data: nil, width: pixelSize, height: pixelSize,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext failed") }

    // Rounded-rect clip (Apple icon corner radius)
    let radius = s * 0.2237
    let rect   = CGRect(x: 0, y: 0, width: s, height: s)
    let path   = CGMutablePath()
    path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
    ctx.addPath(path); ctx.clip()

    // Gradient background
    let c1 = CGColor(colorSpace: cs, components: [cfg.color1.0, cfg.color1.1, cfg.color1.2, 1.0])!
    let c2 = CGColor(colorSpace: cs, components: [cfg.color2.0, cfg.color2.1, cfg.color2.2, 1.0])!
    let grad = CGGradient(colorsSpace: cs, colors: [c1, c2] as CFArray, locations: [0, 1])!
    let startPt = CGPoint(x: 0,   y: cfg.gradientAngle ? s : 0)
    let endPt   = CGPoint(x: s,   y: cfg.gradientAngle ? 0 : s)
    ctx.drawLinearGradient(grad, start: startPt, end: endPt, options: [])

    // Subtle inner highlight
    let hlColor = CGColor(colorSpace: cs, components: [1, 1, 1, 0.10])!
    ctx.setFillColor(hlColor)
    ctx.fillEllipse(in: CGRect(x: s * 0.35, y: s * 0.52, width: s * 0.80, height: s * 0.64))

    // SF Symbol centred at 58% of icon size
    let symSize = s * 0.58
    let symPad  = (s - symSize) / 2.0
    let symRect = CGRect(x: symPad, y: symPad, width: symSize, height: symSize)

    let nsSize = NSSize(width: symSize, height: symSize)
    let symImg = NSImage(size: nsSize, flipped: false) { _ in
        guard let sym = NSImage(systemSymbolName: cfg.symbol, accessibilityDescription: nil) else { return false }
        let conf = NSImage.SymbolConfiguration(pointSize: symSize * 0.72, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor.white]))
        let configured = sym.withSymbolConfiguration(conf) ?? sym
        configured.draw(in: NSRect(origin: .zero, size: nsSize),
                        from: .zero, operation: .sourceOver, fraction: 0.95)
        return true
    }

    if let cgSym = symImg.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cgSym, in: symRect)
    }

    guard let cgImg = ctx.makeImage() else { fatalError("makeImage failed") }
    let nsImg = NSImage(cgImage: cgImg, size: NSSize(width: s, height: s))
    guard let tiff = nsImg.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:])
    else { fatalError("PNG export failed") }
    return png
}

// ─────────────────────────────────────────────────────────────
// Write all sizes
// ─────────────────────────────────────────────────────────────
let specs: [(String, Int)] = [
    ("icon_16x16.png",      16), ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",      32), ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",   128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",   256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",   512), ("icon_512x512@2x.png",1024),
]

for (filename, px) in specs {
    try! renderIcon(pixelSize: px).write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
}
print("Variant \(variant) → \(outDir)")
