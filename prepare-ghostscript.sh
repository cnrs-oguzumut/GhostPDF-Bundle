#!/bin/bash

set -e

echo "========================================="
echo "Preparing Ghostscript for Bundling"
echo "========================================="

# Check if Ghostscript is installed via Homebrew
# Check if Ghostscript is installed via Homebrew
if ! command -v brew &> /dev/null; then
    if [ -d "ghostscript-bundle/bin" ] && [ -f "ghostscript-bundle/bin/gs" ]; then
        echo "Homebrew not found, but valid ghostscript-bundle exists. Using existing bundle."
        exit 0
    else
        echo "Error: Homebrew is not installed and no bundle exists. Please install Homebrew first."
        exit 1
    fi
fi

# Install Ghostscript if not already installed
if ! brew list ghostscript &> /dev/null; then
    echo "Installing Ghostscript via Homebrew..."
    brew install ghostscript
else
    echo "Ghostscript is already installed via Homebrew"
fi

# Get Ghostscript installation path
GS_PREFIX=$(brew --prefix ghostscript)
echo "Ghostscript prefix: $GS_PREFIX"

# Create bundle directory structure
BUNDLE_DIR="ghostscript-bundle"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/bin"
mkdir -p "$BUNDLE_DIR/lib"
mkdir -p "$BUNDLE_DIR/share"

echo ""
echo "Copying Ghostscript binary..."
cp "$GS_PREFIX/bin/gs" "$BUNDLE_DIR/bin/"

echo "Copying shared libraries (including all dependencies)..."
# Function to recursively copy library dependencies
copy_lib_deps() {
    local lib_path="$1"
    local libname=$(basename "$lib_path")
    
    # Skip if already copied or if it's a system library
    if [ -f "$BUNDLE_DIR/lib/$libname" ] || [[ "$lib_path" == /usr/lib/* ]] || [[ "$lib_path" == /System/* ]]; then
        return
    fi
    
    # If the path doesn't exist as-is, try to resolve it
    if [ ! -f "$lib_path" ]; then
        # Try under Homebrew prefix
        local test_path="$GS_PREFIX/lib/$libname"
        if [ -f "$test_path" ]; then
            lib_path="$test_path"
        else
            # Try to find it in other Homebrew packages
            for pkg_lib in /opt/homebrew/opt/*/lib/"$libname"; do
                if [ -f "$pkg_lib" ]; then
                    lib_path="$pkg_lib"
                    break
                fi
            done
        fi
    fi
    
    if [ ! -f "$lib_path" ]; then
        return
    fi
    
    echo "  Copying: $libname"
    cp "$lib_path" "$BUNDLE_DIR/lib/"
    
    # Recursively copy this library's dependencies
    otool -L "$lib_path" | grep -E '\.dylib' | awk '{print $1}' | while read -r dep; do
        if [[ "$dep" != /usr/lib/* ]] && [[ "$dep" != /System/* ]]; then
            copy_lib_deps "$dep"
        fi
    done
}

# Start with gs binary dependencies
otool -L "$BUNDLE_DIR/bin/gs" | grep -E '\.dylib' | awk '{print $1}' | while read -r dylib_path; do
    copy_lib_deps "$dylib_path"
done

# Also check all Ghostscript libs in the prefix
for lib in "$GS_PREFIX"/lib/*.dylib; do
    if [ -f "$lib" ]; then
        copy_lib_deps "$lib"
    fi
done

echo "Copying Ghostscript resources..."
# Copy Ghostscript resource files (fonts, initialization files, etc.)
if [ -d "$GS_PREFIX/share/ghostscript" ]; then
    cp -R "$GS_PREFIX/share/ghostscript" "$BUNDLE_DIR/share/"
fi

echo ""
echo "Updating library paths in binary..."
# Update the binary to use @executable_path for library loading
# This makes the bundle relocatable
cd "$BUNDLE_DIR"

# Get all dynamic libraries referenced by the gs binary
echo "Processing gs binary dependencies..."
otool -L "bin/gs" | grep -E '\.dylib' | awk '{print $1}' | while read -r dylib_path; do
    # Skip system libraries
    if [[ "$dylib_path" == /usr/lib/* ]] || [[ "$dylib_path" == /System/* ]]; then
        continue
    fi
    
    # Extract the library name
    libname=$(basename "$dylib_path")
    
    # Check if we have this library in our bundle
    if [ -f "lib/$libname" ]; then
        echo "  Relinking: $libname"
        install_name_tool -change "$dylib_path" "@executable_path/../lib/$libname" "bin/gs" 2>/dev/null || true
    fi
done

# Update library dependencies in the dylibs themselves
echo "Processing library interdependencies..."
for dylib in lib/*.dylib; do
    if [ ! -f "$dylib" ]; then
        continue
    fi
    
    libname=$(basename "$dylib")
    
    # Update the library's own ID
    install_name_tool -id "@executable_path/../lib/$libname" "$dylib" 2>/dev/null || true
    
    # Update dependencies within this library
    otool -L "$dylib" | grep -E '\.dylib' | awk '{print $1}' | while read -r dep_path; do
        # Skip system libraries and self-reference
        if [[ "$dep_path" == /usr/lib/* ]] || [[ "$dep_path" == /System/* ]] || [[ "$dep_path" == "$dylib" ]]; then
            continue
        fi
        
        depname=$(basename "$dep_path")
        
        # Check if this dependency exists in our bundle
        if [ -f "lib/$depname" ]; then
            install_name_tool -change "$dep_path" "@executable_path/../lib/$depname" "$dylib" 2>/dev/null || true
        fi
    done
done

cd ..

echo ""
echo "Re-signing binaries after modification..."
# Re-sign all modified libraries and binary with adhoc signature
# This is necessary because install_name_tool invalidates the original signature
for dylib in "$BUNDLE_DIR"/lib/*.dylib; do
    if [ -f "$dylib" ]; then
        codesign --force --sign - "$dylib" 2>/dev/null || true
    fi
done

# Re-sign the gs binary
codesign --force --sign - "$BUNDLE_DIR/bin/gs" 2>/dev/null ||true

echo ""
echo "Verifying binary..."
file "$BUNDLE_DIR/bin/gs"
lipo -info "$BUNDLE_DIR/bin/gs"

echo ""
echo "========================================="
echo "Ghostscript Bundle Ready!"
echo "========================================="
echo ""
echo "Bundle location: $BUNDLE_DIR"
echo "Binary: $BUNDLE_DIR/bin/gs"
echo "Libraries: $BUNDLE_DIR/lib/"
echo "Resources: $BUNDLE_DIR/share/"
echo ""
echo "This bundle will be included in the app during build."
echo ""
