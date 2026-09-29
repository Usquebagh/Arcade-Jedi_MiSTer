#!/usr/bin/env python3
"""Side-by-side of simulation frames and MAME reference frames, plus a diff image.
Usage: compare.py <out.png> <sim.png|ppm> <mame.png> [...pairs]"""
import sys
from PIL import Image, ImageChops, ImageDraw

out, pairs = sys.argv[1], list(zip(sys.argv[2::2], sys.argv[3::2]))
W, H = 296, 240
sheet = Image.new("RGB", (W * 3, len(pairs) * (H + 14)), "black")
d = ImageDraw.Draw(sheet)
for i, (a, b) in enumerate(pairs):
    ia = Image.open(a).convert("RGB").resize((W, H), Image.NEAREST)
    ib = Image.open(b).convert("RGB").resize((W, H), Image.NEAREST)
    diff = ImageChops.difference(ia, ib)
    bad = sum(1 for p in diff.getdata() if max(p) > 24)
    y = i * (H + 14)
    for j, (img, label) in enumerate([(ia, a), (ib, b), (diff.point(lambda v: min(255, v * 4)), f"diff: {bad} px")]):
        sheet.paste(img, (j * W, y + 14))
        d.text((j * W + 2, y + 1), label.rsplit("/", 1)[-1], fill="yellow")
sheet.save(out)
