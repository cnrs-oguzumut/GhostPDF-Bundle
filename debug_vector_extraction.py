import sys
import os
import fitz  # PyMuPDF
import re

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

def debug_extraction(pdf_path):
    doc = fitz.open(pdf_path)
    page = doc[0] # Analyze page 1
    
    paths = page.get_drawings()
    print(f"DEBUG: Found {len(paths)} paths.")
    
    rects = [p["rect"] for p in paths if p["rect"].width > 0.1]
    clusters = merge_rects(rects)
    print(f"DEBUG: Found {len(clusters)} clusters.")
    
    if not clusters:
        print("No clusters found.")
        return

    cluster = clusters[0]
    print(f"DEBUG: Cluster 1 Rect: {cluster}")
    
    # Check RAW SVG output
    svg_raw = page.get_svg_image(crop=False)
    print("\n--- RAW SVG HEAD (first 300 chars) ---")
    print(svg_raw[:300])
    
    # Check what the patching would do
    width = cluster.width
    height = cluster.height
    viewbox = f"{cluster.x0} {cluster.y0} {cluster.width} {cluster.height}"
    
    pattern = r"<svg([^>]*)>"
    match = re.search(pattern, svg_raw)
    if match:
        print(f"\nDEBUG: Regex matched: {match.group(0)}")
        new_tag = f'<svg width="{width}pt" height="{height}pt" viewBox="{viewbox}">'
        print(f"DEBUG: Proposed Replacement: {new_tag}")
    else:
        print("\nDEBUG: Regex failed to match <svg> tag.")
        
    print("\n--- MATRIX TEST ---")
    mat = fitz.Matrix(1, 0, 0, 1, -cluster.x0, -cluster.y0)
    svg_matrix = page.get_svg_image(matrix=mat, crop=False)
    print("\nMatrix SVG Head:")
    print(svg_matrix[:300])

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: debug.py <pdf_path>")
        sys.exit(1)
    debug_extraction(sys.argv[1])
