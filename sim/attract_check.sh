#!/bin/bash
# Regression check: run 30 s of attract mode and compare every 30th frame with the
# MAME 0.268 reference captures in ~/mame_ref (mame_NNNN.png, same frame numbering).
cd "$(dirname "$0")"
bash run.sh 1800 30 > out/attract.log 2>&1 || { tail out/attract.log; exit 1; }
python3 - <<'EOF'
import glob, os
from PIL import Image, ImageChops
worst = 0
for f in sorted(glob.glob("out/frame_*.ppm")):
    n = f[-8:-4]
    ref = os.path.expanduser(f"~/mame_ref/mame_{n}.png")
    if not os.path.exists(ref):
        continue
    d = ImageChops.difference(Image.open(f).convert("RGB"), Image.open(ref).convert("RGB"))
    bad = sum(1 for p in d.getdata() if max(p) > 24)
    worst = max(worst, bad)
    print(f"frame {n}: {bad} px differ")
print("WORST:", worst)
EOF
