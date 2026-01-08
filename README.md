# GhostPDF+ - PDF Compressor for macOS

<p align="center">
  <img src="./app-preview.png" alt="GhostPDF+ Screenshot" width="450">
</p>

A modern, lightweight PDF compressor and toolkit for macOS, powered by Ghostscript.

## Features

### 📦 Compression & Optimization
- 🎯 **Drag & Drop** — Simply drop your PDF and compress
- ⚡ **Basic Mode** — Three presets: Light, Medium, Heavy compression
- 🔧 **Pro Mode** — Full control over DPI, quality, color, fonts, and more
- 📊 **Size Comparison** — See before/after file sizes instantly
- 🔍 **Visual Preview** — Thumbnail comparison before & after

### 🛠️ PDF Tools
- ✂️ **Split PDF** — Extract pages by range, selection, or split into individual pages
- 🔗 **Merge PDF** — Combine multiple PDFs into one document
- ↕️ **Reorder Pages** — Visual page organization with Reverse, Sort, Odd First, and Reset buttons
- 📏 **Resize to A4** — Standardize page size to A4
- 🎨 **Rasterize** — Convert pages to bitmaps to prevent editing
- 🖼️ **Extract Images** — Enhanced: Supports JPEG, PNG, JPEG 2000, CMYK, and complex color spaces (ICCBased, Indexed)
- 🔄 **Rotate & Delete** — Quick select buttons for Odd/Even/All pages

### 🚀 Advanced Tools (New!)
- 🛠️ **Repair & Sanitize** — Fix corrupted PDFs by rebuilding the file structure
- 🏛️ **Convert to PDF/A** — Archival conversion (PDF/A-2b) for long-term preservation

### 🔒 Security & Privacy
- 🔐 **Encrypt PDF** — Password protection with 128-bit AES
- 🔓 **Decrypt PDF** — Remove passwords from protected files
- 💧 **Watermarks** — Add custom text watermarks

### 🎨 Interface & Experience
- 🌙 **Modern Dark UI** — Beautiful, native SwiftUI interface (dark mode default)
- ⚡ **Batch Processing** — Process multiple PDFs simultaneously
- 💾 **Lightweight** — Native macOS app, minimal footprint

## Download

Choose the version that fits your Mac:

1.  **[Download Free Version (v1.5)](https://ko-fi.com/s/bd1e3fd34d)**
    *   *Best for Intel & Apple Silicon Macs (macOS 11+)*
    *   *Requires manual Ghostscript installation*

2.  **[Download Pro Bundle (v2.0)](https://ko-fi.com/s/c0f340b969)**
    *   *Best for Apple Silicon Macs (macOS 13+)*
    *   ✨ **NEW:** Ghostscript 10.06.0 is **bundled**! No separate installation required. Just drag & drop to run.

## Installation

### For Pro Bundle (v2.0)
1. Download **GhostPDF+ Bundle**
2. Open the DMG
3. Drag GhostPDF+ to your Applications folder
4. Done!

### For Free Version (v1.5)
You must install Ghostscript first:
1. Open Terminal
2. Run: `brew install ghostscript`
3. Download and Run GhostPDF+

### Mac App Store
🍎 **Coming Soon!** A sandboxed Mac App Store version is in development.

> **📦 Note:** GhostPDF+ v2.0+ includes Ghostscript binaries (AGPL license). The app is ~40MB larger but requires no external dependencies.

## Usage

### 📦 Tab Overview

1. **Basic / Pro**: Compression settings.
2. **Tools**: Split, Merge, Rasterize, Extract Images, Rotate/Delete.
3. **Security**: Watermark, Encrypt.
4. **Advanced**: Repair PDF, Convert to PDF/A.

## Build from Source

### Requirements
- macOS 13+ (Ventura or later)
- Xcode 15+ or Swift 5.9+
- Homebrew (for Ghostscript bundling)

### Steps

```bash
# Clone the repository
git clone https://github.com/cnrs-oguzumut/GhostPDFPlus.git
cd GhostPDFPlus/NanoPDF

# Build (automatically downloads and bundles Ghostscript)
./build.sh

# Run
open build/GhostPDF+.app
```

> **Note:** The build script automatically downloads Ghostscript via Homebrew and bundles it with the app.

## Why GhostPDF+?

| Feature | GhostPDF+ | Adobe Acrobat | PDF Squeezer |
|---------|----------|---------------|--------------|
| Price | **Free** | $15/month | €35 |
| Open Source | ✅ | ❌ | ❌ |
| Native SwiftUI | ✅ | ❌ | ❌ |
| Pro Controls | ✅ | ✅ | ✅ |
| PDF Tools (Split/Merge) | ✅ | ✅ | ❌ |
| Visual Page Reordering | ✅ | ✅ | ❌ |
| Page Numbers | ✅ | ✅ | ❌ |
| Watermarks | ✅ | ✅ | ❌ |
| Encryption | ✅ | ✅ | ❌ |
| Decrypt / Unlock | ✅ | ✅ | ❌ |
| PDF/A Conversion | ✅ | ✅ | ❌ |
| PDF Repair | ✅ | ✅ | ❌ |
| Native Image Extraction | ✅ | ✅ | ❓ |
| Batch Processing | ✅ | ✅ | ✅ |
| No Subscription | ✅ | ❌ | ✅ |
| Lightweight | ✅ | ❌ | ✅ |
| Notarized | ✅ | ✅ | ✅ |

## Contributing

Contributions are welcome! Feel free to:
- 🐛 Report bugs
- 💡 Suggest features
- 🔧 Submit pull requests

## License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPLv3)**.

### 📜 Ghostscript License & Source Offer
GhostPDF+ bundles **Ghostscript 10.06.0**, which is licensed under the **AGPL**.

In compliance with the AGPL, we provide the following:
1.  **GhostPDF+ Source:** The full source code for this application is available in this repository.
2.  **Ghostscript Source:** The source code for the bundled Ghostscript binary (v10.06.0) can be downloaded from the official Artifex repository or archives:
    *   [Ghostscript Source Code (Artifex)](https://github.com/ArtifexSoftware/ghostpdl-downloads/releases)

By using this software, you agree to the terms of the AGPLv3.
