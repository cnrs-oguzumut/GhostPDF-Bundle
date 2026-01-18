import sys
import os
import fitz  # PyMuPDF
import re

print("VectorExtractor v2.2 (Caption-Aware)")

def find_figure_captions(page):
    """Find figure captions and subfigure labels on the page"""
    captions = []
    text_dict = page.get_text("dict")

    # Patterns for figure captions and labels
    fig_patterns = [
        r'(?i)figure\s+\d+',  # "Figure 1", "figure 2", etc.
        r'(?i)fig\.?\s+\d+',  # "Fig. 1", "fig 2", etc.
        r'\([a-z]\)',          # "(a)", "(b)", "(c)", etc.
        r'\b[a-z]\)',          # "a)", "b)", "c)", etc.
    ]

    for block in text_dict.get("blocks", []):
        if block.get("type") != 0:  # Skip non-text blocks
            continue
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                text = span.get("text", "").strip()
                for pattern in fig_patterns:
                    if re.search(pattern, text):
                        bbox = fitz.Rect(span["bbox"])
                        captions.append({
                            "text": text,
                            "rect": bbox,
                            "type": "label" if len(text) <= 4 else "caption"
                        })
                        break

    return captions

def group_by_captions(rects, captions, page_rect):
    """Group rectangles based on nearby captions"""
    if not captions:
        return None

    # Find main figure captions (not subfigure labels)
    main_captions = [c for c in captions if c["type"] == "caption"]
    if not main_captions:
        return None

    # Sort captions by vertical position (top to bottom)
    main_captions.sort(key=lambda c: c["rect"].y0)

    # For each main caption, find all graphics below/beside it
def rects_are_close(r1, r2, threshold=15):
    """Check if two rectangles are within threshold distance"""
    # Check horizontal gap
    x_gap = max(0, r1.x0 - r2.x1, r2.x0 - r1.x1)
    # Check vertical gap
    y_gap = max(0, r1.y0 - r2.y1, r2.y0 - r1.y1)
    
    return x_gap <= threshold and y_gap <= threshold

def merge_rects(rects, threshold=15):
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
    
    if output_dir is None:
        output_dir = os.path.splitext(pdf_path)[0] + "_vectors"
    
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

        # 1. Pre-cluster ALL vectors into "visual objects" first
        # This identifies distinct parts (graphs, sub-figures) based on proximity
        if rects:
            # Low threshold (15) to maintain separation of distinct visual elements
            # The Partition Strategy will unify elements belonging to the same figure zone.
            visual_objects = merge_rects(rects, threshold=15)
        else:
            visual_objects = []

        # 2. Find captions
        captions = find_figure_captions(page)

        # 3. Partition-Based Association: Link captions to visual objects by vertical zones
        caption_groups = []
        used_object_ids = set()

        # Sort captions by vertical position from top to bottom
        # ONLY use "caption" type (detected with Fig/Figure) as splitters.
        main_captions = [c for c in captions if c["type"] == "caption"]
        main_captions.sort(key=lambda c: c["rect"].y0)

        # Track the bottom of the previous caption to act as a "ceiling"
        prev_caption_bottom = 0

        for caption in main_captions:
            group_rects = []

            # Define the vertical zone for this figure:
            # Floor: Top of the current caption
            # Ceiling: Bottom of the previous caption (or 0 for the first one)
            floor_y = caption["rect"].y0
            ceiling_y = prev_caption_bottom
            
            # To be tolerant of slight overlaps/alignment issues, we check if the 
            # CENTER of the object is within the zone, rather than strict containment.
            
            for obj in visual_objects:
                if id(obj) in used_object_ids:
                    continue

                obj_center_y = (obj.y0 + obj.y1) / 2
                
                # Check: Is the object's center vertically between ceiling and floor?
                # This assigns the object to the caption immediately below it.
                if obj_center_y < floor_y and obj_center_y > ceiling_y:
                    group_rects.append(obj)
                    used_object_ids.add(id(obj))
            
            if group_rects:
                # Calculate the union rect for the whole group
                union = group_rects[0]
                for r in group_rects[1:]:
                    union = union | r

                # FIX: Clip the bottom to the caption top
                # This ensures no caption text is included in the vector crop
                if union.y1 > floor_y:
                    union = fitz.Rect(union.x0, union.y0, union.x1, floor_y)

                caption_groups.append({
                    "caption": caption["text"],
                    "rect": union
                })

            # Update ceiling for next caption
            prev_caption_bottom = caption["rect"].y1

        valid_groups = []
        
        # Add caption-based groups
        if caption_groups:
            print(f"  Found {len(caption_groups)} figures via 'Climb-Up' strategy")
            for g in caption_groups:
                valid_groups.append(g["rect"])

        # Add remaining uncaptioned objects (that weren't linked to any caption)
        uncaptioned_count = 0
        for obj in visual_objects:
            if id(obj) not in used_object_ids:
                # Standard filtering
                if obj.width <= 5 or obj.height <= 5: continue
                
                # Prevent full-page duplicates if any
                page_area = page.rect.width * page.rect.height
                if (obj.width * obj.height) > (page_area * 0.95):
                    continue
                    
                valid_groups.append(obj)
                uncaptioned_count += 1
        
        if uncaptioned_count > 0:
             print(f"  Found {uncaptioned_count} uncaptioned graphics")

        if not valid_groups:
            print(f"  No valid vector groups found on Page {i+1}")
            continue

        print(f"  Extracting {len(valid_groups)} vector group(s) on Page {i+1}")
        
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
                pix = new_page.get_pixmap(dpi=dpi)

                # Save as high-quality PNG
                png_filename = f"Page{i+1}_Vector{j+1}.png"
                png_path = os.path.join(output_dir, png_filename)
                pix.save(png_path)
                
                # SVG export removed per user request
                # svg = new_page.get_svg_image(matrix=fitz.Matrix(1, 1))
                # ...
                
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
