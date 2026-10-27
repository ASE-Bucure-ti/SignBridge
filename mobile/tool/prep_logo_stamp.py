"""Build a cropped, transparent SignBridge stamp PNG from host/logo.png.

Near-black background pixels become fully transparent so the PDF appearance
can sit on a light gray field without a black rectangle.
"""

from pathlib import Path

from PIL import Image

src = Path(__file__).resolve().parents[2] / "host" / "logo.png"
out = Path(__file__).resolve().parents[1] / "assets" / "images" / "logo_stamp.png"

img = Image.open(src).convert("RGBA")
pixels = img.load()
w, h = img.size

# Black (and near-black) → transparent; keep cyan logo.
for y in range(h):
    for x in range(w):
        r, g, b, a = pixels[x, y]
        if r < 28 and g < 28 and b < 28:
            pixels[x, y] = (0, 0, 0, 0)

# Crop to non-transparent content with a small pad.
bbox = img.getbbox()
if bbox is None:
    raise SystemExit("logo became fully transparent")
pad = 8
x0 = max(0, bbox[0] - pad)
y0 = max(0, bbox[1] - pad)
x1 = min(w, bbox[2] + pad)
y1 = min(h, bbox[3] + pad)
cropped = img.crop((x0, y0, x1, y1))

# Keep a reasonable pixel size for embedding.
cropped.thumbnail((256, 256), Image.Resampling.LANCZOS)
cropped.save(out, "PNG")
print(f"wrote {out} size={cropped.size} bytes={out.stat().st_size}")
