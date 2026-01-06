#!/bin/bash

set -e

# Configuration
APP_NAME="GhostPDF+"
BUNDLE_ID="com.ghostpdf.app"
VERSION="2.0.0"
BUILD_NUMBER="1"
TEAM_ID="UM63FN2P72"
APPLE_ID="laletaneri@gmail.com"
APP_PASSWORD="pcfl-wnws-xsch-mmdh"

# Developer ID signing identity (for notarization, NOT App Store)
SIGNING_IDENTITY="Developer ID Application: Lale Taneri (UM63FN2P72)"

echo "========================================="
echo "Building GhostPDF+ for Notarization"
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
mkdir -p dist

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# Copy icon
if [ -f "../icon.icns" ]; then
    cp "../icon.icns" "$RESOURCES_DIR/AppIcon.icns"
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

echo ""
echo "Signing app bundle with hardened runtime (no sandbox)..."
codesign --deep --force --options runtime \
    --entitlements "../NanoPDF.entitlements" \
    --sign "$SIGNING_IDENTITY" \
    --timestamp "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo ""
echo "Creating DMG for distribution..."
hdiutil create -volname "$APP_NAME" -srcfolder "$APP_BUNDLE" -ov -format UDZO "dist/$APP_NAME-$VERSION.dmg"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo ""
echo "App bundle: $APP_BUNDLE"
echo "DMG file: dist/$APP_NAME-$VERSION.dmg"
echo ""
echo "Submitting for notarization..."
echo ""

xcrun notarytool submit "dist/$APP_NAME-$VERSION.dmg" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_PASSWORD" \
    --wait

if [ $? -eq 0 ]; then
    echo ""
    echo "Notarization succeeded! Stapling ticket to DMG..."
    xcrun stapler staple "dist/$APP_NAME-$VERSION.dmg"
    
    echo ""
    echo "========================================="
    echo "SUCCESS! Ready for Distribution"
    echo "========================================="
    echo ""
    echo "Notarized DMG: dist/$APP_NAME-$VERSION.dmg"
    echo ""
    echo "You can now distribute this DMG file."
    echo "Users will be able to download and run it without warnings."
    echo ""
else
    echo ""
    echo "Notarization failed. Check the error above."
    echo "You can check the status with:"
    echo "  xcrun notarytool log <submission-id> --apple-id $APPLE_ID --team-id $TEAM_ID --password $APP_PASSWORD"
    echo ""
    exit 1
fi
