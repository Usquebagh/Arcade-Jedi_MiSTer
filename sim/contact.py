#!/usr/bin/env python3
"""Tile a set of frame PNGs into one labelled contact sheet.
Usage: contact.py <out.png> <cols> <img>..."""
import sys
from PIL import Image, ImageDraw

out, cols, files = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
w, h = 296 // 2, 240 // 2
rows = (len(files) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 12)), "black")
draw = ImageDraw.Draw(sheet)
for i, f in enumerate(files):
    x, y = (i % cols) * w, (i // cols) * (h + 12)
    sheet.paste(Image.open(f).convert("RGB").resize((w, h)), (x, y + 12))
    draw.text((x + 2, y), f.rsplit("/", 1)[-1], fill="yellow")
sheet.save(out)
