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
    caption_groups = []
    for idx, caption in enumerate(main_captions):
        # Determine the bottom boundary: next caption or page end
        if idx + 1 < len(main_captions):
            bottom_boundary = main_captions[idx + 1]["rect"].y0
        else:
            bottom_boundary = page_rect.y1

        # Create search region: from caption to next caption/page bottom
        # Look both above and below caption (within reason)
        search_rect = fitz.Rect(
            page_rect.x0,  # Full width of page
            max(caption["rect"].y0 - 100, page_rect.y0),  # Look up to 100pt above
            page_rect.x1,
            bottom_boundary
        )

        # Find all graphics in this region
        group_rects = [r for r in rects if search_rect.intersects(r)]

        if group_rects:
            # Union all rects in this group
            union_rect = group_rects[0]
            for r in group_rects[1:]:
                union_rect = union_rect | r

            caption_groups.append({
                "caption": caption["text"],
                "rect": union_rect,
                "subfigures": group_rects
            })

    return caption_groups

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

        # 1. Pre-cluster ALL vectors into "visual objects" first
        # This identifies distinct parts (graphs, sub-figures) based on proximity
        if rects:
            # Low threshold (15) to keep figures separate. 
            # The Partition Strategy will collect all parts in the zone anyway.
            visual_objects = merge_rects(rects, threshold=15)
        else:
            visual_objects = []

        # 2. Find captions
        captions = find_figure_captions(page)
        
        # 3. Intelligent Association: Link captions to visual objects by "Climbing Up"
        # We start at the caption and look for the nearest object above.
        # If found, we continue looking above THAT object, forming a chain.
        
        caption_groups = []
        used_object_ids = set()
        
        # Sort captions by vertical position from top to bottom
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
            
            # Define horizontal bounds (with generous buffer)
            # Figures can be wider than captions, so we expand significantly
            caption_center_x = (caption["rect"].x0 + caption["rect"].x1) / 2
            
            for obj in visual_objects:
                if id(obj) in used_object_ids:
                    continue
                
                # Check 1: Vertical Inclusion
                # The object must be strictly above the caption line
                # And its center (or bottom) should be below the ceiling
                # To be safe, we check if the object *overlaps* the vertical zone or is contained in it
                # Logic: Object bottom must be < floor. Object top must be > ceiling.
                if obj.y1 <= floor_y and obj.y0 >= ceiling_y:
                    
                    # Check 2: Horizontal Alignment
                    # We check if the object is roughly within the same column
                    # If the page is single column, this is always true.
                    # If multi-column, we want to avoid grabbing figures from the other column
                    
                    # Simple check: Does the object overlap horizontally with the caption's extended vertical strip?
                    # Let's define a strip 200pt wider than the caption on each side
                    strip_x0 = caption["rect"].x0 - 200
                    strip_x1 = caption["rect"].x1 + 200
                    
                    if obj.x1 >= strip_x0 and obj.x0 <= strip_x1:
                        group_rects.append(obj)
                        used_object_ids.add(id(obj))
            
            if group_rects:
                # Calculate the union rect for the whole group
                union = group_rects[0]
                for r in group_rects[1:]:
                    union = union | r
                
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
                
                # ALSO Save as SVG for debugging
                svg = new_page.get_svg_image(matrix=fitz.Matrix(1, 1))
                svg_filename = f"Page{i+1}_Vector{j+1}.svg"
                svg_path = os.path.join(output_dir, svg_filename)
                with open(svg_path, "w") as f:
                    f.write(svg)
                
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
