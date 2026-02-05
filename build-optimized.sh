#!/bin/bash

set -e

# Configuration
APP_NAME="GhostPDF+"
BUNDLE_ID="com.ghostpdf.app"
VERSION="6.1.2"
BUILD_NUMBER="2"
TEAM_ID="UM63FN2P72"

# Developer ID signing identity (for notarization, NOT App Store)
SIGNING_IDENTITY="Developer ID Application: Lale Taneri (UM63FN2P72)"

echo "========================================="
echo "Building GhostPDF+ (Optimized, No Notarization)"
echo "========================================="

# Clean previous builds
rm -rf .build
rm -rf build
rm -rf scripts/dist scripts/build

# Build release binary
echo "Building release binary..."
swift build -c release

# Create app bundle structure
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p dist

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# Copy icon
if [ -f "AppIcon.icns" ]; then
    cp "AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "../icon.icns" ]; then
    cp "../icon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Build Vector Extractor with AGGRESSIVE SIZE OPTIMIZATION
echo ""
echo "Building Vector Extractor binary (Python) with size optimization..."

# Ensure we use the correct PyInstaller
PYINSTALLER_CMD="pyinstaller"
if command -v /opt/homebrew/bin/pyinstaller &> /dev/null; then
    PYINSTALLER_CMD="/opt/homebrew/bin/pyinstaller"
fi

echo "Using PyInstaller: $PYINSTALLER_CMD"

# AGGRESSIVE EXCLUSIONS: Only include PyMuPDF and essential stdlib
# This should reduce the binary from 94MB to ~15-20MB
$PYINSTALLER_CMD --clean --onefile --name cvector_extractor \
    --strip \
    --exclude-module scipy \
    --exclude-module numpy \
    --exclude-module pandas \
    --exclude-module tkinter \
    --exclude-module _tkinter \
    --exclude-module tcl \
    --exclude-module tk \
    --exclude-module torch \
    --exclude-module tensorflow \
    --exclude-module matplotlib \
    --exclude-module PyQt5 \
    --exclude-module PyQt6 \
    --exclude-module PySide2 \
    --exclude-module PySide6 \
    --exclude-module PIL \
    --exclude-module Pillow \
    --exclude-module IPython \
    --exclude-module jedi \
    --exclude-module jsonschema \
    --exclude-module aiohttp \
    --exclude-module asyncio \
    --exclude-module unittest \
    --exclude-module pydoc \
    --exclude-module doctest \
    --exclude-module test \
    --exclude-module setuptools \
    --exclude-module pkg_resources \
    --exclude-module distutils \
    --exclude-module sqlite3 \
    --exclude-module xml \
    --exclude-module xmlrpc \
    --exclude-module email \
    --exclude-module html \
    --exclude-module http \
    --exclude-module urllib3 \
    --exclude-module certifi \
    --exclude-module cryptography \
    --exclude-module OpenSSL \
    scripts/extract_vectors.py --distpath scripts/dist --workpath scripts/build --specpath scripts

echo ""
echo "Vector Extractor build complete. Size:"
du -sh scripts/dist/cvector_extractor

echo ""
echo "Copying Vector Extractor to app..."
if [ -f "scripts/dist/cvector_extractor" ]; then
    cp "scripts/dist/cvector_extractor" "$RESOURCES_DIR/"
    echo "Vector Extractor bundled successfully."
else
    echo "Error: Vector Extractor binary build failed!"
    exit 1
fi

# Prepare and copy Ghostscript bundle
echo ""
echo "Preparing Ghostscript bundle..."
./prepare-ghostscript.sh

echo "Copying Ghostscript bundle to app..."
if [ -d "ghostscript-bundle" ]; then
    cp -R "ghostscript-bundle" "$RESOURCES_DIR/ghostscript"
    echo "Ghostscript bundle copied to $RESOURCES_DIR/ghostscript"
else
    echo "Error: ghostscript-bundle directory not found!"
    exit 1
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>
            <string>PDF Document</string>
            <key>CFBundleTypeRole</key>
            <string>Viewer</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>com.adobe.pdf</string>
            </array>
        </dict>
    </array>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Lale Taneri. All rights reserved.</string>
</dict>
</plist>
EOF

echo ""
echo "Signing Ghostscript binaries and libraries..."
# Sign all dylibs first
for dylib in "$RESOURCES_DIR"/ghostscript/lib/*.dylib; do
    if [ -f "$dylib" ]; then
        echo "  Signing: $(basename $dylib)"
        codesign --force --options runtime \
            --sign "$SIGNING_IDENTITY" \
            --timestamp "$dylib"
    fi
done

# Sign the Ghostscript binary
echo "  Signing: gs binary"
codesign --force --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --timestamp "$RESOURCES_DIR/ghostscript/bin/gs"

# Sign the Vector Extractor binary
echo "  Signing: cvector_extractor"
if [ -f "$RESOURCES_DIR/cvector_extractor" ]; then
    if [ -f "scripts/cvector.entitlements" ]; then
        codesign --force --options runtime \
            --entitlements "scripts/cvector.entitlements" \
            --sign "$SIGNING_IDENTITY" \
            --timestamp "$RESOURCES_DIR/cvector_extractor"
    else
        codesign --force --options runtime \
            --sign "$SIGNING_IDENTITY" \
            --timestamp "$RESOURCES_DIR/cvector_extractor"
    fi
else
    echo "Warning: cvector_extractor not found for signing"
fi


echo ""
echo "Signing app bundle with hardened runtime (no sandbox)..."
codesign --deep --force --options runtime \
    --entitlements "../NanoPDF.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Create DMG
echo ""
echo "Creating DMG for distribution..."
# Detach if exists (forcefully)
hdiutil detach "/Volumes/GhostPDF_Plus_Optimized" -force 2>/dev/null || true
# Create DMG with unique volname
hdiutil create -volname "GhostPDF_Plus_Optimized" -srcfolder "$APP_BUNDLE" -ov -format UDZO "dist/$APP_NAME-$VERSION-Optimized.dmg"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "App bundle: $APP_BUNDLE"
echo "DMG file: dist/$APP_NAME-$VERSION-Optimized.dmg"
echo ""
echo "Final sizes:"
du -sh "$APP_BUNDLE"
du -sh "dist/$APP_NAME-$VERSION-Optimized.dmg"
echo ""
echo "NOTE: Notarization skipped. App is signed but not notarized."
echo "To notarize, run the full build-notarized.sh script."
echo ""
