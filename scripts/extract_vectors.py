import fitz  # not yet:-)
import sys
import os
import re

def rects_are_close(r1, r2, threshold=15):
    """Check if two rectangles are close enough to be merged."""
    if r1.intersects(r2):
        return True
    
    # Check vertical/horizontal distance
    v_dist = 0
    if r1.y1 < r2.y0: v_dist = r2.y0 - r1.y1
    elif r2.y1 < r1.y0: v_dist = r1.y0 - r2.y1
    
    h_dist = 0
    if r1.x1 < r2.x0: h_dist = r2.x0 - r1.x1
    elif r2.x1 < r1.x0: h_dist = r1.x0 - r2.x1
    
    return v_dist < threshold and h_dist < threshold

def merge_rects(rects, threshold=15, gutter_midline=None):
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
                
                should_merge = False
                if rects_are_close(current, candidate, threshold):
                    should_merge = True
                    
                    # GUTTER GUARD CHECK (Step 2)
                    if gutter_midline is not None:
                         u_cx = (current.x0 + current.x1) / 2
                         obj_cx = (candidate.x0 + candidate.x1) / 2
                         if (u_cx < gutter_midline and obj_cx > gutter_midline) or \
                            (obj_cx < gutter_midline and u_cx > gutter_midline):
                             should_merge = False
                             # print(f"DEBUG: Gutter Guard PREVENTED Merge Step 2: {current} | {candidate}")

                if should_merge:
                    current = current | candidate
                    clusters.pop(i)
                    changed = True
                else:
                    i += 1
            new_clusters.append(current)
        clusters = new_clusters
    return clusters

def trim_pixmap(pix):
    """Find the tightest bounding box of non-white pixels in a pixmap."""
    try:
        gray = fitz.Pixmap(fitz.csGRAY, pix)
    except:
        return None
        
    samples = gray.samples
    width = gray.width
    height = gray.height
    
    xmin, ymin, xmax, ymax = width, height, 0, 0
    found = False
    
    for y in range(height):
        # Samples is a bytes object, 1 byte per pixel in GRAY
        row = samples[y * width : (y + 1) * width]
        for x, pixel_val in enumerate(row):
            if pixel_val < 250: # Anything not pure white
                found = True
                if x < xmin: xmin = x
                if x > xmax: xmax = x
                if y < ymin: ymin = y
                if y > ymax: ymax = y
    
    if not found:
        return None
        
    return fitz.IRect(xmin, ymin, xmax + 1, ymax + 1)

def find_figure_captions(page):
    captions = []
    text_dict = page.get_text("dict")
    fig_patterns = [
        r'(?i)figure\s+\d+',
        r'(?i)fig\.?\s+\d+',
        r'\([a-z]\)',
        r'\b[a-z]\)',
    ]
    for block in text_dict.get("blocks", []):
        if block.get("type") != 0: continue
        block_text = ""
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                block_text += " " + span.get("text", "")

        for pattern in fig_patterns:
            if re.search(pattern, block_text):
                bbox = fitz.Rect(block["bbox"])
                # Enhanced Label Detection:
                # If text is short OR consists ONLY of labels (e.g. "(a) (b)"), treat as label
                # This prevents "(a) (b)" from acting as a hard floor that cuts off the figure
                is_pure_label = re.match(r'^(\([a-z0-9]+\)\s*)+$', block_text.strip(), re.IGNORECASE)
                
                captions.append({
                    "text": block_text.strip(),
                    "rect": bbox,
                    "type": "label" if (len(block_text.strip()) <= 5 or is_pure_label) else "caption"
                })
                break
    return captions

def has_subfigure_labels_nearby(rect, label_rects, threshold=50):
    """Check if a rectangle has subfigure labels (a), (b), (c) nearby."""
    nearby_count = 0
    for lr in label_rects:
        # Check if label is within threshold distance of the rect
        if rects_are_close(rect, lr, threshold):
            nearby_count += 1
            if nearby_count >= 2:  # At least 2 labels nearby suggests multi-panel figure
                return True
    return False

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

    print(f"VectorExtractor v2.4 (Label-Aware Multi-Panel Merging)")
    print(f"Extracting to: {output_dir}")
    total_images = 0

    for i, page in enumerate(src_doc):
        paths = page.get_drawings()
        if not paths: continue

        print(f"  Page {i+1}: Analyzing {len(paths)} vector paths...")
        
        # 0. Collect Image Rects early for Hybrid Clustering
        page_image_rects = []
        try:
            for img in page.get_images():
                xref = img[0]
                for r in page.get_image_rects(xref):
                    if r.width > 1 and r.height > 1:
                        page_image_rects.append((r, xref))
        except: pass

        # Filter valid visual paths (ignore tiny or invisible/white masking paths)
        rects = []
        for p in paths:
            # Skip tiny paths
            if p["rect"].width < 0.5 or p["rect"].height < 0.5: continue
            
            # Skip invisible paths (no color/fill) or White Masking paths
            # Note: (1, 1, 1) is RGB White
            has_stroke = p["color"] is not None and p["color"] != (1, 1, 1)
            has_fill = p["fill"] is not None and p["fill"] != (1, 1, 1)
            
            if has_stroke or has_fill:
                 rects.append(p["rect"])
        # ADD IMAGES TO CLUSTERING:
        for ir, _ in page_image_rects:
            rects.append(ir)
        
        # Initial clustering of paths
        visual_objects = merge_rects(rects, threshold=15)
        
        # Collect Image Rects for Hybrid check (copy of list for reference later)
        page_image_data = page_image_rects

        # 1. Harvest Captions and Body Text Obstacles
        captions = find_figure_captions(page)
        caption_rects = [c["rect"] for c in captions]
        main_captions = [c for c in captions if c["type"] == "caption"]
        
        gutter_guard_active = False
        page_mid_x = page.rect.width / 2
        
        # Robust Gutter Detection
        def detect_gutter_midline(p):
            try:
                blocks = p.get_text("blocks")
                if not blocks: return p.rect.width / 2
                left_text = [b for b in blocks if len(b[4].strip()) > 30 and b[2] < p.rect.width * 0.55]
                right_text = [b for b in blocks if len(b[4].strip()) > 30 and b[0] > p.rect.width * 0.45]
                if len(left_text) > 2 and len(right_text) > 2:
                    max_lx1 = max(b[2] for b in left_text)
                    min_rx0 = min(b[0] for b in right_text)
                    if min_rx0 > max_lx1: return (max_lx1 + min_rx0) / 2
                    return (max_lx1 + min_rx0) / 2
            except: pass
            return p.rect.width / 2

        page_mid_x = detect_gutter_midline(page)
        
        # HYBRID DETECTION: Text Density OR Side-by-Side Captions
        left_text_count = 0
        right_text_count = 0
        try:
            for block in page.get_text("blocks"):
                if len(block[4].strip()) > 50:
                    bx0, _, bx1, _ = block[:4]
                    if bx1 < page_mid_x: left_text_count += 1
                    elif bx0 > page_mid_x: right_text_count += 1
            if left_text_count > 1 and right_text_count > 1:
                gutter_guard_active = True
        except: pass
        
        if not gutter_guard_active:
            left_caps = [c for c in main_captions if c["rect"].x1 < page_mid_x]
            right_caps = [c for c in main_captions if c["rect"].x0 > page_mid_x]
            for lc in left_caps:
                for rc in right_caps:
                    if abs(lc["rect"].y0 - rc["rect"].y0) < 300:
                        gutter_guard_active = True
                        break
                if gutter_guard_active: break
            
        if gutter_guard_active:
             pass 
             for c in captions:
                 print(f"  - '{c['text'][:50]}...' at {c['rect']}")
        caption_rects = [c["rect"] for c in captions]
        main_captions = [c for c in captions if c["type"] == "caption"]
        
        obstacles = []      # Vertical barriers
        strict_blocks = []  # No-merge zones
        text_rects = []     # Potential labels
        all_text_blocks = [] # ALL text blocks for erasure
        try:
            text_dict = page.get_text("dict")
            for block in text_dict.get("blocks", []):
                if block.get("type") == 0:
                    block_text = ""
                    block_rect = fitz.Rect(block["bbox"])
                    
                    # Store Lines for Granular Erasure
                    for line in block.get("lines", []):
                        line_text = ""
                        line_rect = fitz.Rect(line["bbox"])
                        for span in line.get("spans", []):
                            line_text += " " + span.get("text", "").strip()
                            span_rect = fitz.Rect(span["bbox"])
                            
                            # Filter page margins
                            if span_rect.y0 < 40 or span_rect.y1 > page.rect.height - 40: continue
                            
                            is_caption = any(span_rect.intersects(cr) for cr in caption_rects)
                            if not is_caption and len(span.get("text", "").strip()) > 0:
                                 text_rects.append(span_rect)
                        
                        clean_line = line_text.strip()
                        if clean_line:
                            all_text_blocks.append({"rect": line_rect, "len": len(clean_line), "text": clean_line})
                            block_text += " " + clean_line

                    # Paragraph detection (Keep Block logic for Smart Crop obstacles)
                    clean_txt = block_text.strip()
                    if len(clean_txt) > 150:
                        # SAFETY CHECK: Does it start like a caption?
                        if len(clean_txt) > 10 and re.match(r'^(?:Figure|Fig)\.?\s*\d+', clean_txt, re.IGNORECASE):
                            pass
                        else:
                            obstacles.append(block_rect) # CEILING
                            strict_blocks.append(block_rect) # NO MERGE
                    elif len(clean_txt) > 50:
                        is_cap = any(block_rect.intersects(cr) for cr in caption_rects)
                        if not is_cap:
                            strict_blocks.append(block_rect) # NO MERGE

        except: pass

        # 2. Merge nearby labels (a, b) into visual objects
        # Fix: Also merge "Label Captions" (e.g. "(a)") which are excluded from text_rects
        label_rects = [c["rect"] for c in captions if c["type"] == "label"]
        all_text_candidates = text_rects + label_rects

        if visual_objects and all_text_candidates:
            temp_objects = []
            for obj in visual_objects:
                current = obj
                for tr in all_text_candidates:
                    # EXCLUSION: If text belongs to a body paragraph, don't merge it into a figure
                    if any(tr.intersects(sb) for sb in strict_blocks): continue
                    
                    if rects_are_close(current, tr, threshold=15):
                        current = current | tr
                temp_objects.append(current)
            
            # Step 2 Merge: Be permissive in Step 2 to catch "monster objects"
            # We will split them LATER in Step 4 if needed.
            # CRITICAL FIX: Use gutter_midline when gutter_guard_active to prevent cross-column merging
            # This prevents adjacent figures in different columns from incorrectly merging
            gutter_for_merge = page_mid_x if gutter_guard_active else None
            visual_objects = merge_rects(temp_objects, threshold=30, gutter_midline=gutter_for_merge)

        # 3. Obstacle-Aware Swath Association
        page_width = page.rect.width
        caption_groups = []
        used_object_ids = set()
        
        def get_col_zone(rect):
            """Determine if a rect belongs to left, right, or both (full) columns."""
            if rect.width > page_width * 0.6: return "full"
            
            # Simple Column Check: strictly based on overlap with the midline
            margin = 15
            if rect.x1 < page_mid_x + margin and rect.x1 < page_mid_x + 60: 
                if rect.x1 <= page_mid_x + 5: return "left"
            if rect.x0 > page_mid_x - margin and rect.x0 > page_mid_x - 60:
                if rect.x0 >= page_mid_x - 5: return "right"
            
            # Bridging detected
            if rect.x0 < page_mid_x - 10 and rect.x1 > page_mid_x + 10:
                return "mixed"
            
            # Default to centroid if ambiguous
            cx = (rect.x0 + rect.x1) / 2
            return "left" if cx < page_mid_x else "right"

        main_captions.sort(key=lambda c: c["rect"].y0)
        col_ceilings = {"left": 40.0, "right": 40.0, "full": 40.0, "mixed": 40.0}

        for cap in main_captions:
            c_rect = cap["rect"]
            c_col = get_col_zone(c_rect)

            # GUTTER GUARD OVERRIDE:
            # If Gutter Guard is active, force strict Left/Right for captions to prevent cross-contamination.
            # EXCEPTION: If the caption itself is clearly Full Width, respect that!
            if gutter_guard_active and c_col not in ["full", "mixed"]:
                c_cx = (c_rect.x0 + c_rect.x1) / 2
                if c_cx < page_mid_x: c_col = "left"
                else: c_col = "right"
                
            floor_y = c_rect.y0
            
            # Search ceiling: previous caption or obstacle in the same zone
            ceiling_y = col_ceilings["full"]
            if c_col in ["left", "mixed"]: ceiling_y = max(ceiling_y, col_ceilings["left"])
            if c_col in ["right", "mixed"]: ceiling_y = max(ceiling_y, col_ceilings["right"])
            
            # Refine ceiling with obstacles
            for obs in obstacles:
                obs_col = get_col_zone(obs)
                # Obstacle only blocks if it's in a relevant column
                if c_col != "full" and obs_col != "full" and c_col != obs_col and obs_col != "mixed":
                    continue
                if obs.y1 < floor_y and obs.y1 > ceiling_y:
                    ceiling_y = obs.y1
            
            group = []
            for obj in visual_objects:
                if id(obj) in used_object_ids: continue
                obj_col = get_col_zone(obj)

                # Broad matching: If either is 'full' or 'mixed' or they share a side
                relevant = False
                
                if gutter_guard_active and c_col in ["left", "right"]:
                    # STRICT MODE: Only accept objects strictly in the same column
                    # Reject "Full" and "Mixed" objects to prevent bridging
                    if obj_col in ["full", "mixed"]:
                        continue  # Skip full/mixed objects in strict mode
                    if c_col == obj_col: relevant = True
                else:
                    # Standard Mode
                    if c_col in ["full", "mixed"] or obj_col in ["full", "mixed"]: relevant = True
                    elif c_col == obj_col: relevant = True
                
                if not relevant: continue
                
                ocy = (obj.y0 + obj.y1) / 2
                if ocy < floor_y and ocy > ceiling_y:
                    group.append(obj)
                    used_object_ids.add(id(obj))
            
            # Aligned search: grab anything vertically within our span and horizontally near
            if group:
                u = group[0]
                for r in group[1:]: u = u | r

                for obj in visual_objects:
                    if id(obj) in used_object_ids: continue
                    # Vertical overlap check (at least 50% of the object's height)
                    overlap = max(0, min(u.y1, obj.y1) - max(u.y0, obj.y0))
                    if overlap > obj.height * 0.5:
                        # Calculate directional distances
                        x_dist = 0
                        if obj.x1 < u.x0: x_dist = u.x0 - obj.x1
                        elif u.x1 < obj.x0: x_dist = obj.x0 - u.x1

                        y_dist = 0
                        if obj.y1 < u.y0: y_dist = u.y0 - obj.y1
                        elif u.y1 < obj.y0: y_dist = obj.y0 - u.y1

                        # Total visual distance (Chebyshev)
                        dist = max(x_dist, y_dist)

                        # ADAPTIVE THRESHOLD: Detect multi-panel figures with (a), (b), (c) labels
                        # Check if either the current union or the candidate object has subfigure labels nearby
                        has_labels = has_subfigure_labels_nearby(u, label_rects, threshold=200) or \
                                     has_subfigure_labels_nearby(obj, label_rects, threshold=200)

                        # Use relaxed threshold for labeled multi-panel figures
                        horizontal_threshold = 150 if has_labels else 40
                        diagonal_threshold = 150 if has_labels else 40

                        # LOGIC:
                        # 1. Vertical Stacking: Allow huge gaps (150pt) because panels can be stacked far apart.
                        # 2. Horizontal Adjacent:
                        #    - RELAXED (150pt) for multi-panel figures with (a), (b), (c) labels
                        #    - STRICT (40pt) otherwise to avoid merging across column gutters (~20-50pt).

                        should_merge = False

                        # GUTTER GUARD CHECK
                        is_crossing_gutter = False
                        if gutter_guard_active:
                            # ROBUST: Use Centroids instead of Edges.
                            u_cx = (u.x0 + u.x1) / 2
                            obj_cx = (obj.x0 + obj.x1) / 2

                            if (u_cx < page_mid_x and obj_cx > page_mid_x) or \
                               (obj_cx < page_mid_x and u_cx > page_mid_x):
                                is_crossing_gutter = True

                        if is_crossing_gutter:
                            should_merge = False # HARD VETO
                        elif x_dist > 0 and y_dist <= 0: # Purely Horizontal (Side-by-Side)
                            if x_dist < horizontal_threshold: # ADAPTIVE HORIZONTAL LIMIT
                                should_merge = True
                        elif y_dist > 0 and x_dist <= 0: # Purely Vertical (Stacked)
                            if y_dist < 150: # RELAXED VERTICAL LIMIT
                                should_merge = True
                        else: # Diagonal or overlapping in one dim
                            if dist < diagonal_threshold: # ADAPTIVE diagonal threshold
                                should_merge = True
                                
                        if should_merge:
                            # GAP CHECK: Only stop if a STRICT BLOCK is strictly between them
                            # AND the gap is significant (>20pt)
                            gap_rect = None
                            if dist > 25:
                                if obj.x1 < u.x0: gap_rect = fitz.Rect(obj.x1, min(u.y0, obj.y0), u.x0, max(u.y1, obj.y1))
                                elif u.x1 < obj.x0: gap_rect = fitz.Rect(u.x1, min(u.y0, obj.y0), obj.x0, max(u.y1, obj.y1))
                            
                            if gap_rect and any(gap_rect.intersects(sb) for sb in strict_blocks):
                                if i == 2: # Debug for Page 3
                                    pass
                                continue
                                
                            group.append(obj)
                            used_object_ids.add(id(obj))
                            u = u | obj

            if group:
                union = group[0]
                for r in group[1:]: union = union | r

                # PADDING: Add padding for edges
                # Increased to capture axis labels and annotations
                px = 20 # Horizontal padding
                py = 24 # INCREASED: Vertical padding to capture axis labels

                # FIX: For double-column papers, extend single-column figures to the gutter
                # ONLY if there are visual elements within 30pt of the right edge
                px_right = px
                if gutter_guard_active:
                    union_cx = (union.x0 + union.x1) / 2
                    if union_cx < page_mid_x and union.x1 < page_mid_x - 20:  # Left column figure
                        # Check if there are visual elements near the right edge
                        has_right_elements = any(
                            obj.x1 > union.x1 - 30 for obj in visual_objects
                        )
                        if has_right_elements:
                            # Extend to gutter minus margin to capture right-side labels
                            px_right = max(px, page_mid_x - union.x1 - 10)
                        else:
                            # No visual elements near right edge, use standard padding
                            px_right = px
                    elif union_cx > page_mid_x and union.x0 > page_mid_x + 20:  # Right column figure
                        # Already correct, use standard padding
                        px_right = px

                # FIX: Small buffer above detected ceiling to avoid cutting figure tops
                # But not too much to prevent body text inclusion
                effective_ceiling = max(40, ceiling_y - 10)

                # FIX: Allow more space below figure to capture axis labels
                # The floor_y is the caption top, leave 5pt gap minimum
                floor_with_gap = floor_y - 5

                final_rect = fitz.Rect(
                    max(0, union.x0 - px),
                    max(effective_ceiling, union.y0 - py),
                    min(page_width, union.x1 + px_right),
                    min(floor_with_gap, union.y1 + py)
                )
                
                # FINAL TRIMMING: No more strict clipping! 
                # We will ERASE obstacles instead.
                # Just ensure we don't go off-page or cross the hard floor/ceiling logic
                caption_groups.append({"text": cap["text"], "rect": final_rect})
            
            # Update ceilings
            if c_col == "full": 
                col_ceilings["full"] = c_rect.y1
            elif c_col == "mixed":
                col_ceilings["left"] = c_rect.y1
                col_ceilings["right"] = c_rect.y1
            else:
                col_ceilings[c_col] = c_rect.y1

        # 4. Final Export Logic with Re-Association
        final_captions_map = {id(g): g for g in caption_groups} # Key by ID to allow removal
        
        # POST-ASSOCIATION COLUMN CLIPPING for Gutter Guard pages
        # Prevents caption-associated figures from bleeding into the opposite column
        # DISABLED FOR NOW - causing too many figures to be removed
        '''
        if gutter_guard_active:
            groups_to_remove = []
            for g_id, g in final_captions_map.items():
                rect = g["rect"]
                cap_left = rect.x0
                was_clipped = False
                
                # Determine which column this caption belongs to
                if cap_left < page_mid_x:
                    # Left column: clip right edge to page_mid_x
                    if rect.x1 > page_mid_x:
                        rect.x1 = page_mid_x - 5  # 5pt safety margin
                        was_clipped = True
                else:
                    # Right column: clip left edge to page_mid_x
                   if rect.x0 < page_mid_x:
                        rect.x0 = page_mid_x + 5  # 5pt safety margin
                        was_clipped = True
                
                # Only validate if clipping occurred
                # If clipping resulted in a too-small figure, remove it
                if was_clipped and (rect.width < 20 or rect.height < 20):
                    groups_to_remove.append(g_id)
            
            # Remove figures that became too small after clipping
            for g_id in groups_to_remove:
                del final_captions_map[g_id]
        '''
        
        # Create a COMPLETE list of all captions for orphan matching (including ones without visual content)
        # This ensures orphans can find captions even if the caption didn't get associated with any object
        all_captions_for_matching = []
        for cap in main_captions:
            cap_dict = {"text": cap["text"], "rect": cap["rect"]}
            all_captions_for_matching.append(cap_dict)
        
        orphans_to_export = []

        # Add loose uncaptioned objects as a fallback
        for obj in visual_objects:
            if id(obj) not in used_object_ids:
                if obj.width > 20 and obj.height > 20: 
                    # ORPHAN SPLITTING LOGIC for Gutter Guard Pages
                    orphans_from_obj = []
                    if gutter_guard_active and obj.x0 < page_mid_x - 10 and obj.x1 > page_mid_x + 10:
                         # Create Left Split (strictly left of midline)
                         left_rect = fitz.Rect(obj.x0, obj.y0, page_mid_x - 5, obj.y1)
                         if left_rect.width > 20: orphans_from_obj.append(left_rect)
                         
                         # Create Right Split (strictly right of midline)
                         right_rect = fitz.Rect(page_mid_x + 5, obj.y0, obj.x1, obj.y1)
                         if right_rect.width > 20: orphans_from_obj.append(right_rect)
                    else:
                        orphans_from_obj.append(obj)
                    
                    # Try to Re-Associate orphans with empty caption groups
                    captions_to_delete = []  # Track which captions to delete AFTER processing all orphans
                    
                    for orphan in orphans_from_obj:
                        matched = False
                        orphan_cx = (orphan.x0 + orphan.x1) / 2
                        
                        for g in all_captions_for_matching:
                            # Skip if already marked for deletion
                            if id(g) in captions_to_delete:
                                continue
                                
                            cap_rect = g["rect"]
                            cap_left = cap_rect.x0
                            
                            same_col = False
                            if gutter_guard_active:
                                if orphan_cx < page_mid_x and cap_left < page_mid_x: same_col = True
                                elif orphan_cx > page_mid_x and cap_left > page_mid_x: same_col = True
                            else:
                                cap_cx = (cap_rect.x0 + cap_rect.x1) / 2
                                if abs(orphan_cx - cap_cx) < 100: same_col = True
                            
                            is_below = cap_rect.y0 >= orphan.y1 - 150 and cap_rect.y0 < orphan.y1 + 400
                            is_aligned = False
                            if orphan.x0 < cap_rect.x1 + 50 and orphan.x1 > cap_rect.x0 - 50:
                                is_aligned = True

                            if same_col and is_below and is_aligned:
                                # Crop the orphan: keep only the part ABOVE the caption
                                cropped_orphan = fitz.Rect(orphan.x0, orphan.y0, orphan.x1, cap_rect.y0 - 5)
                                if cropped_orphan.height > 20:
                                    orphans_to_export.append(cropped_orphan)
                                captions_to_delete.append(id(g))
                                matched = True
                                break
                        if matched: continue
                        
                        # If no caption match, export the full orphan
                        if not matched:
                            # On Gutter Guard pages, be a bit more permissive with orphans
                            # but still filter out noise (thin vertical lines)
                            if gutter_guard_active and orphan.width < 15:
                                continue
                            orphans_to_export.append(orphan)
                    
                    # Now delete all matched captions
                    for cap_id in captions_to_delete:
                        if cap_id in final_captions_map:
                            del final_captions_map[cap_id]

        valid_final_rects = [g["rect"] for g in final_captions_map.values()] + orphans_to_export

        # --- SMART CROP: Post-Processing Sanity Check ---
        # Ensure no figure overlaps with known Text Blocks (Body Text / Non-Caption)
        # DISABLED: This was causing figures to be cut too early from top
        # The erasure logic should handle text removal instead
        '''
        for r in valid_final_rects:
            for item in all_text_blocks:
                # Use a lower length threshold (30) to catch short orphaned lines like "ve limits..."
                if item["len"] < 30: continue

                obs = item["rect"]

                # OPTIONAL: Check if this block is actually a known caption/label to avoid cropping valid labels
                # (Assuming 'captions' list contains all figure captions)
                # But typically body text is distinguishable by position.

                if not r.intersects(obs): continue

                # Overlap Analysis
                ix = r & obs
                if ix.is_empty: continue

                # If obstacle is largely at the TOP of the figure (Top Cut)
                # and takes up a small vertical slice relative to the figure
                if obs.y1 < r.y0 + r.height * 0.3:
                    # Snap figure TOP to obstacle BOTTOM
                    r.y0 = max(r.y0, obs.y1)

                # If obstacle is largely at the BOTTOM of the figure (Bottom Cut)
                elif obs.y0 > r.y1 - r.height * 0.3:
                        # Snap figure BOTTOM to obstacle TOP
                    r.y1 = min(r.y1, obs.y0)
        '''
        # ------------------------------------------------

        for j, rect in enumerate(valid_final_rects):
            try:
                # print(f"Processing Page{i+1}_Fig{j+1}...")
                print(f"Processing Page{i+1}_Fig{j+1}...")
                
                temp_doc = fitz.open()
                new_p = temp_doc.new_page(width=rect.width, height=rect.height)
                new_p.show_pdf_page(new_p.rect, src_doc, i, clip=rect)
                
                # TARGETED ERASURE: Paint white over any obstacles from the WRONG column
                shape = new_p.new_shape()
                
                # Determine figure column (based on center AND span)
                fig_cx = rect.x0 + rect.width / 2
                
                # Full Width Detection:
                # 1. Width > 60% of page
                # 2. Spans across midline with significant margin (75px) to avoid matching single-col with bleeding
                if rect.width > page.rect.width * 0.6: 
                    fig_col = "full"
                elif rect.x0 < page_mid_x - 75 and rect.x1 > page_mid_x + 75:
                    fig_col = "full"
                else:
                    fig_col = "left" if fig_cx < page_mid_x else "right"
                
                # VISUAL-AWARE ERASURE: Remove text strictly outside the visual content area
                # This handles body text above/below and side columns while preserving labels.
                
                # Filter out tiny noise from "core" definition
                relevant_visuals = [obj for obj in visual_objects if obj.intersects(rect) and obj.height > 5 and obj.width > 5]
                
                if relevant_visuals:
                    vis_x0 = min(obj.x0 for obj in relevant_visuals)
                    vis_y0 = min(obj.y0 for obj in relevant_visuals)
                    vis_x1 = max(obj.x1 for obj in relevant_visuals)
                    vis_y1 = max(obj.y1 for obj in relevant_visuals)
                    
                    # print(f"  Visual Bounds: x={vis_x0:.1f}-{vis_x1:.1f}, y={vis_y0:.1f}-{vis_y1:.1f}")
                    
                    # Define Safety Zones
                    # TIGHTENED MARGINS: Reduce top safety buffer to catch stray text lines like "take place."
                    top_strict_y = vis_y0 - 10   # Reduced from 20 to 10
                    top_buffer_y = vis_y0        # Buffer zone (0-10px above): Erase ONLY long text
                    
                    # TIGHTENED MARGINS: Reduce right safety buffer to catch close text
                    right_safe_x = vis_x1 + 8   # Reduced from 15 to 8
                    left_safe_x = vis_x0 - 50   
                    
                    # print(f"  Safety Zones: TopStrict={top_strict_y:.1f}, RightSafe={right_safe_x:.1f}, LeftSafe={left_safe_x:.1f}")
                    
                    for item in all_text_blocks:
                        obs_rect = item["rect"]
                        text_len = item["len"]
                        
                        if not obs_rect.intersects(rect): continue
                        if obs_rect.y0 > vis_y1: continue # Skip captions below

                        should_erase = False
                        reason = ""
                        is_side_erasure = False # Flag to override caption protection
                        
                        # CASE 0: OPPOSITE COLUMN GUARD (Strict)
                        # Only apply if NOT full width
                        if fig_col != "full":
                            # If figure is clearly Left and Obstacle is clearly Right (or vice versa)
                            obs_cx = (obs_rect.x0 + obs_rect.x1) / 2
                            if fig_col == "left" and obs_cx > page_mid_x:
                                should_erase = True
                                reason = "Opposite Col (Right)"
                                is_side_erasure = True
                            elif fig_col == "right" and obs_cx < page_mid_x:
                                should_erase = True
                                reason = "Opposite Col (Left)"
                                is_side_erasure = True
                        
                        # CASE 1: TOP TEXT
                        # Subcase A: Strictly above safe zone
                        if not should_erase and obs_rect.y1 < top_strict_y:
                            if text_len > 5: # Reduced from 10 to 5 to catch short stray text like "pattern."
                                should_erase = True
                                reason = "Top Strict"
                                # FORCE ERASURE: Even if it looks like a caption, if it's strictly above the visual
                                # content zone (>10px), it's likely the caption of the *figure above*, so erase it.
                                is_side_erasure = True
                        
                        # Subcase B: In Buffer Zone (near top edge)
                        # Erase long body text lines, keep short labels "(a)"
                        elif obs_rect.y1 < top_buffer_y:
                            if text_len > 15: # Reduced from 25 to 15 to be safer against body text
                                should_erase = True
                                reason = "Top Buffer"
                        
                        # Subcase C: Top Inner Guard (Overlapping top edge)
                        # If text is INSIDE the visual area but at the very top, and is clearly body text (long)
                        elif obs_rect.y0 < vis_y0 + 10: 
                             if text_len > 25:
                                 should_erase = True
                                 reason = "Top Inner Guard"
                        
                        # CASE 2: RIGHT SIDE
                        elif obs_rect.x0 > right_safe_x:
                            should_erase = True
                            reason = "Right Side"
                            is_side_erasure = True
                            
                        # CASE 3: LEFT SIDE
                        elif obs_rect.x1 < left_safe_x:
                            if text_len > 25: 
                                should_erase = True
                                reason = "Left Side"
                                is_side_erasure = True

                        if should_erase:
                            str_text = item.get("text", "")
                            # CAPTION PROTECTION MODIFIED:
                            # Only protect caption-like text if it's NOT a side erasure
                            # (i.e., allow erasing "Figure 12" if it's on the side or opposite column)
                            if re.match(r'^(?:Figure|Fig)\.?\s*\d+', str_text, re.IGNORECASE):
                                if not is_side_erasure:
                                    print(f"    IGNORED (Caption-like): '{str_text[:30]}...'")
                                    continue
                                else:
                                    reason += " + Caption Override"

                            # print(f"    ERASING: '{str_text[:30]}...' Reason={reason} Rect={obs_rect}")
                            ix = obs_rect & rect
                            if not ix.is_empty:
                                local_rect = fitz.Rect(
                                    ix.x0 - rect.x0, 
                                    ix.y0 - rect.y0, 
                                    ix.x1 - rect.x0, 
                                    ix.y1 - rect.y0
                                )
                                shape.draw_rect(local_rect)
                                shape.finish(color=(1, 1, 1), fill=(1, 1, 1), width=0)
                        else:
                             # Print what was kept for debugging
                             if obs_rect.y1 < top_buffer_y or obs_rect.x0 > right_safe_x or obs_rect.x1 < left_safe_x:
                                 pass
                
                shape.commit()
                
                pix = new_p.get_pixmap(dpi=300)
                
                # PIXEL-LEVEL TRIMMING
                trim_bbox = trim_pixmap(pix)
                if trim_bbox:
                    # Apply a small uniform aesthetic margin
                    margin = 8
                    final_bbox = fitz.IRect(
                        max(0, trim_bbox.x0 - margin),
                        max(0, trim_bbox.y0 - margin),
                        min(pix.width, trim_bbox.x1 + margin),
                        min(pix.height, trim_bbox.y1 + margin)
                    )
                    # Extract sub-pixmap using copy to bypass constructor bug
                    new_pix = fitz.Pixmap(pix.colorspace, final_bbox, pix.alpha)
                    new_pix.copy(pix, final_bbox)
                    pix = new_pix
                
                # Hybrid Logic
                hybrid_found = False
                for ir, xref in page_image_data:
                    if rect.intersects(ir):
                        hybrid_found = True
                        png_path = os.path.join(output_dir, f"Page{i+1}_Fig{j+1}_v.png")
                        pix.save(png_path)
                        try:
                            img_pix = fitz.Pixmap(src_doc, xref)
                            if img_pix.n - img_pix.alpha > 3: img_pix = fitz.Pixmap(fitz.csRGB, img_pix)
                            img_path = os.path.join(output_dir, f"Page{i+1}_Fig{j+1}_i.png")
                            img_pix.save(img_path)
                        except: pass
                        break
                
                if not hybrid_found:
                    pix.save(os.path.join(output_dir, f"Page{i+1}_Fig{j+1}.png"))
                
                total_images += 1
            except Exception as e:
                print(f"  Warning: Failed to extract Fig {j+1}: {e}")

    print(f"Successfully extracted {total_images} vector drawings to {output_dir}")
    print(f"OUTPUT_DIR:{output_dir}")

if __name__ == "__main__":
    if len(sys.argv) < 2: sys.exit(1)
    pdf_path = sys.argv[1]
    output_dir = sys.argv[2] if len(sys.argv) > 2 else None
    extract_vectors(pdf_path, output_dir)
