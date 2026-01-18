#!/bin/bash

# Script to build the Vector Extraction binary using PyInstaller

# Exit on error
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_NAME="cvector_extractor"

echo "Building Vector Extractor..."

# Check requirements
if ! command -v pyinstaller &> /dev/null; then
    echo "Error: pyinstaller not found."
    echo "Please install it: pip install pyinstaller"
    exit 1
fi

if ! python3.10 -c "import fitz" &> /dev/null; then
    echo "Error: PyMuPDF (fitz) not found for python3.10."
    echo "Please install it: pip3.10 install pymupdf"
    exit 1
fi

# Go to script dir
cd "$SCRIPT_DIR"

# Clean previous build
rm -rf build dist "$OUTPUT_NAME.spec"

# Build
echo "Running PyInstaller with python3.10..."
python3.10 -m PyInstaller --clean --onefile --name "$OUTPUT_NAME" extract_vectors.py

# Verify
if [ -f "dist/$OUTPUT_NAME" ]; then
    echo "Build successful!"
    echo "Binary located at: $SCRIPT_DIR/dist/$OUTPUT_NAME"
    
    # Optional: Copy to convenient location for Xcode
    # DEST="$PROJECT_ROOT/Sources/Resources/$OUTPUT_NAME"
    # mkdir -p "$(dirname "$DEST")"
    # cp "dist/$OUTPUT_NAME" "$DEST"
    # echo "Copied to: $DEST"
else
    echo "Build failed - binary not found."
    exit 1
fi
