#!/bin/bash

# build-bundled-notarized.sh
# Builds GhostPDF+ Bundled - includes Ghostscript, non-sandboxed, notarized

set -e

# Configuration
APP_NAME="GhostPDF+"
BUNDLE_ID="com.ghostpdf.app"
VERSION="2.6"
BUILD_NUMBER="1"
DIST_DIR="dist"

# Load secrets from .env if present
if [ -f .env ]; then
    export $(cat .env | xargs)
fi

SIGNING_IDENTITY="Developer ID Application: Lale Taneri (UM63FN2P72)"

echo "========================================="
echo "Building GhostPDF+ Bundled $VERSION (Notarized)"
echo "========================================="

# Clean previous builds
rm -rf .build
rm -rf build

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
mkdir -p "$DIST_DIR"

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# Handle Icon
echo ""
echo "Processing Icon..."
ICON_SOURCE="assets/icon.png"
if [ -f "$ICON_SOURCE" ]; then
    echo "Converting $ICON_SOURCE to AppIcon.icns..."
    
    ICONSET_DIR="MyIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    sips -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null
    
    iconutil -c icns "$ICONSET_DIR"
    cp "MyIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    rm "MyIcon.icns"
    
    echo "Icon processed successfully."
else
    echo "Warning: $ICON_SOURCE not found."
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

# Create Info.plist (NO sandbox entitlements referenced)
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
if [ -d "$RESOURCES_DIR/ghostscript/lib" ]; then
    for dylib in "$RESOURCES_DIR"/ghostscript/lib/*.dylib; do
        if [ -f "$dylib" ]; then
            echo "  Signing: $(basename $dylib)"
            codesign --force --options runtime \
                --sign "$SIGNING_IDENTITY" \
                --timestamp "$dylib"
        fi
    done
fi

# Sign the Ghostscript binary (no entitlements for non-sandboxed)
if [ -f "$RESOURCES_DIR/ghostscript/bin/gs" ]; then
    echo "  Signing: gs binary"
    codesign --force --options runtime \
        --sign "$SIGNING_IDENTITY" \
        --timestamp "$RESOURCES_DIR/ghostscript/bin/gs"
fi

echo ""
echo "Signing app bundle..."
codesign --deep --force --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --timestamp "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo ""
echo "Creating DMG..."
DMG_NAME="$APP_NAME-$VERSION-Bundled"
hdiutil create -volname "${APP_NAME} Bundled ${VERSION}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DIST_DIR/$DMG_NAME.dmg"

echo ""
echo "Notarizing..."
xcrun notarytool submit "$DIST_DIR/$DMG_NAME.dmg" \
    --keychain-profile "notarytool-profile" \
    --wait

echo ""
echo "Stapling notarization ticket..."
xcrun stapler staple "$DIST_DIR/$DMG_NAME.dmg"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "App bundle: $APP_BUNDLE"
echo "DMG file: $DIST_DIR/$DMG_NAME.dmg"
echo ""
echo "This bundled version includes Ghostscript and is ready for distribution."
