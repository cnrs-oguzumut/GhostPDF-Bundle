#!/bin/bash

# build-mas.sh
# Builds CleverGhost for Mac App Store submission
# Sandboxed, bundled with Ghostscript, packaged as PKG

set -e

# Configuration
APP_NAME="GhostPDF+"
BUNDLE_ID="com.nanopdf.app"
VERSION="6.1.1"
BUILD_NUMBER="11"
DIST_DIR="dist"
SCRIPTS_DIR="scripts"

# Signing Identities
APP_CERT="3rd Party Mac Developer Application: Lale Taneri (UM63FN2P72)"
INSTALLER_CERT="3rd Party Mac Developer Installer: Lale Taneri (UM63FN2P72)"

echo "========================================="
echo "Building GhostPDF+ for Mac App Store"
echo "========================================="
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $VERSION ($BUILD_NUMBER)"

# Clean previous builds
rm -rf .build
rm -rf build-mas
mkdir -p "$DIST_DIR"

# Build release binary
echo "Building release binary..."
swift build -c release

# Create app bundle structure
BUILD_DIR="build-mas"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy binary
cp ".build/release/$APP_NAME" "$MACOS_DIR/"

# Handle Icon
echo ""
echo "Processing Icon..."
if [ -f "CleverGhost.icns" ]; then
    echo "Using CleverGhost.icns..."
    cp "CleverGhost.icns" "$RESOURCES_DIR/AppIcon.icns"
elif [ -f "assets/icon.png" ]; then
    echo "Converting assets/icon.png to AppIcon.icns..."

    ICONSET_DIR="MyIcon.iconset"
    mkdir -p "$ICONSET_DIR"

    sips -z 16 16     "assets/icon.png" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
    sips -z 32 32     "assets/icon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
    sips -z 32 32     "assets/icon.png" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
    sips -z 64 64     "assets/icon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
    sips -z 128 128   "assets/icon.png" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
    sips -z 256 256   "assets/icon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
    sips -z 256 256   "assets/icon.png" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
    sips -z 512 512   "assets/icon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
    sips -z 512 512   "assets/icon.png" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
    sips -z 1024 1024 "assets/icon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null

    iconutil -c icns "$ICONSET_DIR"
    cp "MyIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    rm "MyIcon.icns"

    echo "Icon processed successfully."
else
    echo "Warning: No icon file found"
fi

# Build and Bundle Vector Extractor (PyInstaller)
echo ""
echo "Building Vector Extractor (onedir mode)..."
# Ensure PyInstaller is available
if ! command -v pyinstaller &> /dev/null; then
    echo "PyInstaller not found. Installing..."
    pip3 install pyinstaller
fi

# Build the extractor
# Exclude unnecessary packages that cause Apple Review rejection
# (scipy, tkinter, torch etc. contain non-public/deprecated Apple API symbols)
pyinstaller --clean --noconfirm --distpath "$SCRIPTS_DIR/build" --workpath "$SCRIPTS_DIR/build/build" --specpath "$SCRIPTS_DIR/build" --name "cvector_extractor" --onedir \
    --exclude-module scipy \
    --exclude-module tkinter \
    --exclude-module _tkinter \
    --exclude-module tcl \
    --exclude-module tk \
    --exclude-module torch \
    --exclude-module matplotlib \
    --exclude-module PyQt5 \
    --exclude-module PIL \
    --exclude-module numpy.distutils \
    --exclude-module IPython \
    --exclude-module jedi \
    --exclude-module jsonschema \
    --exclude-module aiohttp \
    --exclude-module unittest \
    --exclude-module pydoc \
    --exclude-module doctest \
    --exclude-module test \
    "$SCRIPTS_DIR/extract_vectors.py"

# Copy to Resources
echo "Copying Vector Extractor to app bundle..."
if [ -d "$SCRIPTS_DIR/build/cvector_extractor" ]; then
    cp -R "$SCRIPTS_DIR/build/cvector_extractor" "$RESOURCES_DIR/cvector_extractor"
    echo "Vector Extractor copied."
else
    echo "Error: PyInstaller build failed."
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
if [ -d "$RESOURCES_DIR/ghostscript/lib" ]; then
    for dylib in "$RESOURCES_DIR"/ghostscript/lib/*.dylib; do
        if [ -f "$dylib" ]; then
            echo "  Signing: $(basename $dylib)"
            codesign --force --sign "$APP_CERT" \
                --entitlements "Ghostscript.entitlements" \
                --options runtime \
                --timestamp "$dylib"
        fi
    done
fi

# Sign the Ghostscript binary with entitlements
if [ -f "$RESOURCES_DIR/ghostscript/bin/gs" ]; then
    echo "  Signing: gs binary"
    codesign --force --sign "$APP_CERT" \
        --entitlements "Ghostscript.entitlements" \
        --options runtime \
        --timestamp "$RESOURCES_DIR/ghostscript/bin/gs"
fi

# Sign the Vector Extractor
if [ -d "$RESOURCES_DIR/cvector_extractor" ]; then
    echo "  Signing: cvector_extractor (recursive)"
    # Sign all libraries inside first
    find "$RESOURCES_DIR/cvector_extractor" -name "*.dylib" -exec codesign --force --options runtime --sign "$APP_CERT" --timestamp {} \;
    find "$RESOURCES_DIR/cvector_extractor" -name "*.so" -exec codesign --force --options runtime --sign "$APP_CERT" --timestamp {} \;
    
    # Sign binaries in torch/bin
    if [ -d "$RESOURCES_DIR/cvector_extractor/_internal/torch/bin" ]; then
        find "$RESOURCES_DIR/cvector_extractor/_internal/torch/bin" -type f -exec codesign --force --options runtime --entitlements "scripts/cvector_sandbox.entitlements" --sign "$APP_CERT" --timestamp {} \;
    fi

    # Sign Python framework binary
    if [ -f "$RESOURCES_DIR/cvector_extractor/_internal/Python.framework/Versions/3.10/Python" ]; then
         codesign --force --options runtime --sign "$APP_CERT" --timestamp "$RESOURCES_DIR/cvector_extractor/_internal/Python.framework/Versions/3.10/Python"
    fi

    # Sign the main binary
    codesign --force --options runtime \
        --entitlements "scripts/cvector_sandbox.entitlements" \
        --sign "$APP_CERT" \
        --timestamp "$RESOURCES_DIR/cvector_extractor/cvector_extractor"
fi

echo ""
echo "Signing main app bundle with sandboxing entitlements..."
codesign --deep --force --sign "$APP_CERT" \
    --entitlements "CleverGhost.entitlements" \
    --options runtime \
    --timestamp "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo ""
echo "Fixing file permissions for App Store submission..."
# Ensure all files are readable by non-root users
find "$APP_BUNDLE" -type f -exec chmod a+r {} \;
find "$APP_BUNDLE" -type d -exec chmod a+rx {} \;

echo ""
echo "Creating installer package..."
PKG_NAME="$APP_NAME-$VERSION-MAS.pkg"
productbuild --component "$APP_BUNDLE" /Applications \
    --sign "$INSTALLER_CERT" \
    "$DIST_DIR/$PKG_NAME"

echo ""
echo "========================================="
echo "Build Complete!"
echo "========================================="
echo "App bundle: $APP_BUNDLE"
echo "Installer: $DIST_DIR/$PKG_NAME"
echo ""
echo "This package is ready for Mac App Store submission via App Store Connect."
echo ""
echo "Next steps:"
echo "1. Upload PKG to App Store Connect using Transporter"
echo "2. Complete app metadata in App Store Connect"
echo "3. Submit for review"
echo ""
