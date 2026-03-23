#!/usr/bin/swift
// Converts a flat PNG into a proper macOS .iconset
// Usage: swift Scripts/make_icon_from_png.swift <source.png> <output-iconset-dir>
//
// Applies Apple's round-rect clip (radius = size × 0.2237) and exports
// all 10 required sizes.

import AppKit
import Foundation

guard CommandLine.arguments.count > 2 else {
    fputs("Usage: swift make_icon_from_png.swift <source.png> <output-iconset-dir>\n", stderr)
    exit(1)
}

let sourcePath = CommandLine.arguments[1]
let outDir     = CommandLine.arguments[2]

guard let sourceImage = NSImage(contentsOfFile: sourcePath) else {
    fputs("Cannot load image: \(sourcePath)\n", stderr); exit(1)
}

try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func renderSize(_ px: Int) -> Data {
    let s  = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()

    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("CGContext failed at size \(px)") }

    // ── Round-rect clip (Apple's icon corner radius) ────────────────
    let radius = s * 0.2237
    let path   = CGMutablePath()
    path.addRoundedRect(in: CGRect(x: 0, y: 0, width: s, height: s),
                        cornerWidth: radius, cornerHeight: radius)
    ctx.addPath(path)
    ctx.clip()

    // ── Draw white background ────────────────────────────────────────
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // ── Draw the source image centred, with a small inset (4%) ───────
    let inset  = s * 0.04
    let imgRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)

    if let cgSrc = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        ctx.draw(cgSrc, in: imgRect)
    }

    guard let cgImg = ctx.makeImage() else { fatalError("makeImage failed") }
    let ns = NSImage(cgImage: cgImg, size: NSSize(width: s, height: s))
    guard let tiff = ns.tiffRepresentation,
          let rep  = NSBitmapImageRep(data: tiff),
          let png  = rep.representation(using: .png, properties: [:])
    else { fatalError("PNG export failed") }
    return png
}

let specs: [(String, Int)] = [
    ("icon_16x16.png",      16), ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",      32), ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",   128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",   256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",   512), ("icon_512x512@2x.png",1024),
]

// For 1024 px we bicubic-upscale the 512 source
for (filename, px) in specs {
    let png = renderSize(px)
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(filename)"))
}
print("✓ Iconset written to \(outDir)")
