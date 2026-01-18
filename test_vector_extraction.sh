#!/bin/bash

# Test script for embedded vectorial image extraction
# Usage: ./test_vector_extraction.sh <input.pdf>

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <input.pdf>"
    exit 1
fi

INPUT_PDF="$1"
OUTPUT_DIR="${INPUT_PDF%.pdf}_Vectors"

echo "=========================================="
echo "Vector Image Extraction Test"
echo "=========================================="
echo "Input PDF: $INPUT_PDF"
echo "Output Dir: $OUTPUT_DIR"
echo ""

# Check if input file exists
if [ ! -f "$INPUT_PDF" ]; then
    echo "Error: File not found: $INPUT_PDF"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Run the vector extractor binary
EXTRACTOR="./scripts/dist/cvector_extractor"

if [ ! -f "$EXTRACTOR" ]; then
    echo "Error: Vector extractor not found at $EXTRACTOR"
    exit 1
fi

echo "Running vector extractor..."
"$EXTRACTOR" "$INPUT_PDF" "$OUTPUT_DIR"

echo ""
echo "=========================================="
echo "Extraction Complete"
echo "=========================================="

# Show results
if [ -d "$OUTPUT_DIR" ]; then
    SVG_COUNT=$(find "$OUTPUT_DIR" -name "*.svg" | wc -l)
    echo "Total SVG files extracted: $SVG_COUNT"
    echo ""
    if [ "$SVG_COUNT" -gt 0 ]; then
        echo "Extracted files:"
        ls -lh "$OUTPUT_DIR"/*.svg 2>/dev/null
    else
        echo "No vector drawings found in the PDF."
    fi
fi

echo ""
echo "Output directory: $OUTPUT_DIR"
