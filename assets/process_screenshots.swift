#!/usr/bin/swift

import Foundation
import AppKit

// Configuration
// We use exact pixel dimensions
let targetWidth: Int = 2560
let targetHeight: Int = 1600
let backgroundColor = NSColor.black

func processImage(at url: URL) {
    let filename = url.lastPathComponent
    guard filename.hasPrefix("Screen_Shot") && filename.hasSuffix(".png") else { return }
    
    print("Processing \(filename)...")
    
    guard let image = NSImage(contentsOf: url) else {
        print("  Error: Could not load image")
        return
    }
    
    // Get exact pixel size of source
    guard let rep = image.representations.first as? NSBitmapImageRep else {
        print("  Error: Source is not a bitmap")
        return
    }
    
    let pixelWidth = CGFloat(rep.pixelsWide)
    let pixelHeight = CGFloat(rep.pixelsHigh)
    
    // Calculate scale to fit 2560x1600 box
    let scaleW = CGFloat(targetWidth) / pixelWidth
    let scaleH = CGFloat(targetHeight) / pixelHeight
    let scale = min(scaleW, scaleH)
    
    let newW = pixelWidth * scale
    let newH = pixelHeight * scale
    
    // Create output bitmap with exact pixel dimensions
    guard let outputRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: targetWidth,
        pixelsHigh: targetHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        print("  Error: Could not create output bitmap")
        return
    }
    
    // Setup drawing context
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: outputRep)
    NSGraphicsContext.current = context
    
    // Fill background
    backgroundColor.setFill()
    NSRect(x: 0, y: 0, width: CGFloat(targetWidth), height: CGFloat(targetHeight)).fill()
    
    // Draw centered
    let x = (CGFloat(targetWidth) - newW) / 2
    let y = (CGFloat(targetHeight) - newH) / 2
    let destRect = NSRect(x: x, y: y, width: newW, height: newH)
    
    // Draw the original image into the new context
    // We prefer drawing the representation directly to avoid point-scaling issues
    rep.draw(in: destRect, 
             from: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight), 
             operation: .sourceOver, 
             fraction: 1.0, 
             respectFlipped: false, 
             hints: nil)
    
    NSGraphicsContext.restoreGraphicsState()
    
    // Save
    let outputFilename = "AppStore_" + filename.replacingOccurrences(of: " ", with: "_")
    let outputUrl = url.deletingLastPathComponent().appendingPathComponent(outputFilename)
    
    if let pngData = outputRep.representation(using: .png, properties: [:]) {
        try? pngData.write(to: outputUrl)
        print("  Saved to \(outputFilename) (\(targetWidth)x\(targetHeight) px)")
    }
}

let fileManager = FileManager.default
let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

do {
    let files = try fileManager.contentsOfDirectory(at: currentDir, includingPropertiesForKeys: nil)
    print("Found \(files.count) files. Processing screenshots...")
    
    for file in files {
        processImage(at: file)
    }
    print("\nDone! Images saved as AppStore_*.png")
} catch {
    print("Error: \(error)")
}
