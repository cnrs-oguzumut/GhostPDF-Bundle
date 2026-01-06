# GhostPDF+ - PDF Compressor for macOS

<p align="center">
  <img src="../assets/app-preview.png" alt="GhostPDF+ Screenshot" width="450">
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
- ↕️ **Reorder Pages** — Drag-and-drop page organization
- 📏 **Resize to A4** — Standardize page size to A4
- 🎨 **Rasterize** — Convert pages to bitmaps to prevent editing
- 🖼️ **Extract Images** — Save pages as high-quality JPEG/PNG images or extract original embedded photos
- 🔄 **Rotate & Delete** — Fix orientation or remove specific pages

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

👉 **[Download GhostPDF+.dmg (Ko-fi)](https://ko-fi.com/s/bd1e3fd34d)**

> **✨ NEW in v2.0:** Ghostscript 10.06.0 is now **bundled** with GhostPDF+! No separate installation required.

## Installation

1. Download **GhostPDF+.dmg** from [Ko-fi](https://ko-fi.com/s/bd1e3fd34d)
2. Open the DMG
3. Drag GhostPDF+ to your Applications folder
4. Done!

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

This project is licensed under the MIT License.

**📜 Ghostscript License:** GhostPDF+ v2.0+ bundles Ghostscript 10.06.0, which is licensed under the AGPL. Ghostscript is used as a separate executable (not linked as a library), ensuring license compatibility.
