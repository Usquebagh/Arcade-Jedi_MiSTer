#!/usr/bin/env python3
"""For each simulation frame, find the reference frame with the fewest differing pixels.
Usage: bestmatch.py '<sim glob>' '<ref glob>'"""
import glob
import sys
from PIL import Image, ImageChops


def load(f):
    return Image.open(f).convert("RGB")


def bad(a, b):
    return sum(1 for p in ImageChops.difference(a, b).getdata() if max(p) > 24)


sims = sorted(glob.glob(sys.argv[1]))
refs = {f: load(f) for f in sorted(glob.glob(sys.argv[2]))}
for s in sims:
    img = load(s)
    scores = sorted((bad(img, r), f) for f, r in refs.items())
    best = scores[0]
    print(f"{s.rsplit('/', 1)[-1]:>16} -> {best[1].rsplit('/', 1)[-1]:>16}  {best[0]:6d} px differ")
