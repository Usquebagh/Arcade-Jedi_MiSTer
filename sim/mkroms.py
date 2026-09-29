#!/usr/bin/env python3
"""Convert the MAME 'jedi' ROM set into $readmemh files for simulation.
Usage: mkroms.py <dir with unzipped jedi ROMs> <output dir>"""
import os
import sys

REGIONS = {
    # file order = address order inside each region
    "main.hex": ["136030-221.14f", "136030-222.13f",                         # 8000, C000
                 "136030-123.13d", "136030-124.13b", "136030-122.13a"],      # banks 0-2
    "snd.hex":  ["136030-133.01c", "136030-134.01a"],                        # 8000, C000
    "tx.hex":   ["136030-215.11t"],
    "bg.hex":   ["136030-126.06r", "136030-127.06n"],
    "spr.hex":  ["136030-130.01h", "136030-131.01f", "136030-128.01m", "136030-129.01k"],
    "prom.hex": ["136030-117.bin", "136030-118.bin"],
}

src, dst = sys.argv[1], sys.argv[2]
os.makedirs(dst, exist_ok=True)
for out, files in REGIONS.items():
    data = b"".join(open(os.path.join(src, f), "rb").read() for f in files)
    with open(os.path.join(dst, out), "w") as fh:
        fh.write("\n".join(f"{b:02x}" for b in data) + "\n")
    print(f"{out}: {len(data)} bytes")
