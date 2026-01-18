import sys
import os
import fitz  # PyMuPDF
import re

print("VectorExtractor v2.1 (Upscale + TextAsPath)")

def rects_are_close(r1, r2, threshold=40):
    if r1.intersects(r2):
        return True
    expanded_r1 = fitz.Rect(r1.x0 - threshold, r1.y0 - threshold, r1.x1 + threshold, r1.y1 + threshold)
    return expanded_r1.intersects(r2)

def merge_rects(rects, threshold=40):
    if not rects:
        return []
    clusters = [r for r in rects]
    changed = True
    while changed:
        changed = False
        new_clusters = []
        while clusters:
            current = clusters.pop(0)
            i = 0
            while i < len(clusters):
                candidate = clusters[i]
                if rects_are_close(current, candidate, threshold):
                    current = current | candidate
                    clusters.pop(i)
                    changed = True
                else:
                    i += 1
            new_clusters.append(current)
        clusters = new_clusters
    return clusters

def extract_vectors(pdf_path, output_dir=None):
    if not os.path.exists(pdf_path):
        print(f"Error: File not found: {pdf_path}", file=sys.stderr)
        sys.exit(1)

    try:
        src_doc = fitz.open(pdf_path)
    except Exception as e:
        print(f"Error opening PDF: {e}", file=sys.stderr)
        sys.exit(1)
    
    if not output_dir:
        base_name = os.path.splitext(os.path.basename(pdf_path))[0]
        output_dir = os.path.join(os.path.dirname(pdf_path), f"{base_name}_Vectors")
    
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    print(f"Extracting to: {output_dir}")

    total_images = 0

    for i, page in enumerate(src_doc):
        paths = page.get_drawings()
        if not paths:
            continue
            
        print(f"Page {i+1}: Analyzing {len(paths)} vector paths...")
        
        rects = []
        for path in paths:
            r = path["rect"]
            if r.width <= 1.0 or r.height <= 1.0:
                continue
            rects.append(r)
            
        merged_groups = merge_rects(rects, threshold=40)
        
        valid_groups = []
        page_area = page.rect.width * page.rect.height

        for r in merged_groups:
            if r.width <= 5 or r.height <= 5: continue

            group_area = r.width * r.height
            if group_area > (page_area * 0.95):
                print(f"  Skipping group covering >95% of page.")
                continue

            valid_groups.append(r)
        
        if not valid_groups:
            print(f"  No valid vector groups found on Page {i+1}")
            continue
            
        print(f"  Found {len(valid_groups)} vector groups on Page {i+1}")
        
        for j, rect in enumerate(valid_groups):
            try:
                # Extract at very high resolution for maximum quality
                # Using DPI-based approach instead of matrix scaling
                dpi = 300  # High DPI for crisp output (4x higher than standard 72 dpi)

                temp_doc = fitz.open()
                new_page = temp_doc.new_page(width=rect.width, height=rect.height)

                # Copy content from source PDF, cropped to rect
                new_page.show_pdf_page(new_page.rect, src_doc, i, clip=rect)

                # Export as high-resolution pixmap first for maximum quality
                # Then convert to SVG - this ensures crisp rasterization
                pix = new_page.get_pixmap(dpi=dpi)

                # Save as high-quality PNG instead of SVG for better quality in Pixelmator
                output_filename = f"Page{i+1}_Vector{j+1}.png"
                output_path = os.path.join(output_dir, output_filename)

                pix.save(output_path)

                temp_doc.close()
                total_images += 1

            except Exception as e:
                print(f"  Error extracting group {j}: {e}")

    print(f"Successfully extracted {total_images} vector drawings to {output_dir}")
    print(f"OUTPUT_DIR:{output_dir}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: extract_vectors.py <pdf_path> [output_dir]", file=sys.stderr)
        sys.exit(1)
    
    pdf_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else None
    
    try:
        extract_vectors(pdf_path, output_dir)
    except Exception as e:
        if output_dir:
            print(f"OUTPUT_DIR:{output_dir}")
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
