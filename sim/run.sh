#!/bin/bash
# Build and run the Verilator simulation.
#   sim/run.sh [frames] [dump_every] [test]
# ROMs are read from $JEDI_ROMS (default ~/roms/jedi); output goes to sim/out/.
set -e
cd "$(dirname "$0")"
ROMS=${JEDI_ROMS:-$HOME/roms/jedi}
mkdir -p out/roms
python3 mkroms.py "$ROMS" out/roms > /dev/null

verilator --cc --exe --build -j "$(nproc)" -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
  --top-module jedi_core \
  -GMAIN_ROM_INIT='"roms/main.hex"' -GSND_ROM_INIT='"roms/snd.hex"' -GTX_ROM_INIT='"roms/tx.hex"' \
  -Mdir obj_dir \
  ../rtl/cpu6502/ALU.v ../rtl/cpu6502/cpu.v ../rtl/dpram.v ../rtl/jedi_timing.v ../rtl/jedi_core.v \
  sim_main.cpp > out/build.log 2>&1 || { tail -30 out/build.log; exit 1; }
grep -E "%(Error|Warning)" out/build.log | grep -v "cpu6502" | head -20 || true

cd out
rm -f frame_*.ppm frame_*.png
time ../obj_dir/Vjedi_core "${1:-60}" "${2:-10}" ${3:-}
python3 - <<'EOF'
import glob
from PIL import Image
for f in sorted(glob.glob("frame_*.ppm")):
    Image.open(f).resize((296 * 2, 240 * 2), Image.NEAREST).save(f[:-4] + ".png")
EOF
ls frame_*.png 2>/dev/null | tail -3
