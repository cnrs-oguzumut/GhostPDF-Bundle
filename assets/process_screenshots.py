import os
import subprocess
import sys

# Configuration
# Mac App Store Screenshot size (16:10 aspect ratio)
TARGET_WIDTH = 2560  # Retina preferred
TARGET_HEIGHT = 1600
BG_COLOR = "000000"  # Black letterboxing

def get_image_dimensions(path):
    # Use sips to get dimensions
    try:
        out = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', path])
        lines = out.decode('utf-8').strip().split('\n')
        w = int(lines[1].split(':')[1].strip())
        h = int(lines[2].split(':')[1].strip())
        return w, h
    except:
        return 0, 0

def process_image(path):
    filename = os.path.basename(path)
    if not filename.startswith("Screen_Shot") or not filename.endswith(".png"):
        return

    print(f"Processing {filename}...")
    
    # Get current dimensions
    w, h = get_image_dimensions(path)
    if w == 0: return

    # Calculate scale to fit
    scale_w = TARGET_WIDTH / w
    scale_h = TARGET_HEIGHT / h
    scale = min(scale_w, scale_h)
    
    new_w = int(w * scale)
    new_h = int(h * scale)
    
    # 1. Resize main image to fit box
    temp_resized = f"temp_{filename}"
    subprocess.call(['sips', '-z', str(new_h), str(new_w), path, '--out', temp_resized], stdout=subprocess.DEVNULL)
    
    # 2. Pad to target size
    output_filename = f"AppStore_{filename.replace(' ', '_')}"
    subprocess.call([
        'sips', 
        '--padTo', str(TARGET_HEIGHT), str(TARGET_WIDTH), 
        '--padColor', BG_COLOR, 
        temp_resized, 
        '--out', output_filename
    ], stdout=subprocess.DEVNULL)
    
    # Cleanup
    os.remove(temp_resized)
    print(f"Created {output_filename} ({TARGET_WIDTH}x{TARGET_HEIGHT})")

def main():
    files = [f for f in os.listdir('.') if f.endswith('.png') and f.startswith('Screen_Shot')]
    files.sort()
    
    if not files:
        print("No screenshots found starting with 'Screen_Shot'...")
        return

    print(f"Found {len(files)} screenshots. Converting to {TARGET_WIDTH}x{TARGET_HEIGHT}...")
    
    for f in files:
        process_image(f)
        
    print("\nDone! Upload 'AppStore_...' files to App Store Connect.")

if __name__ == "__main__":
    main()
