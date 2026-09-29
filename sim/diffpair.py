#!/usr/bin/env python3
"""Zoomed sim | reference | diff image for one frame pair, plus where the diffs are.
Usage: diffpair.py <sim> <ref> <out.png>"""
import sys
from PIL import Image, ImageChops

a = Image.open(sys.argv[1]).convert("RGB")
b = Image.open(sys.argv[2]).convert("RGB")
d = ImageChops.difference(a, b)
W, H = a.size
sheet = Image.new("RGB", (W * 6, H * 2))
for i, im in enumerate([a, b, d.point(lambda v: min(255, v * 4))]):
    sheet.paste(im.resize((W * 2, H * 2), Image.NEAREST), (i * W * 2, 0))
sheet.save(sys.argv[3])

rows, cols = {}, {}
for y in range(H):
    for x in range(W):
        if max(d.getpixel((x, y))) > 24:
            rows[y] = rows.get(y, 0) + 1
            cols[x] = cols.get(x, 0) + 1
print("differing pixels:", sum(rows.values()))
print("rows:", len(rows), "first", sorted(rows)[:8], "last", sorted(rows)[-4:])
print("cols:", len(cols), "first", sorted(cols)[:8], "last", sorted(cols)[-4:])
