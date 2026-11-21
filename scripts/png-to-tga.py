"""Downscale rendered ear PNGs and write the 32-bit TGA textures WoW loads.

Usage: python3 scripts/png-to-tga.py <png dir> <out dir> <size>
"""
import sys
from pathlib import Path

from PIL import Image

src, out, size = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)
for png in sorted(src.glob("*.png")):
    image = Image.open(png).convert("RGBA").resize((size, size), Image.LANCZOS)
    # Uncompressed, 32 bits per pixel with alpha: the most widely supported TGA form.
    image.save(out / (png.stem + ".tga"), compression=None)
    print(f"{png.stem}.tga")
