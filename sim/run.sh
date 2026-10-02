#!/bin/bash
# Build and run the Verilator simulation.
#   sim/run.sh [frames] [dump_every] [test]
# ROMs are read from $JEDI_ROMS (default ~/roms/jedi); output goes to sim/out/.
set -e
cd "$(dirname "$0")"
ROMS=${JEDI_ROMS:-$HOME/roms/jedi}
mkdir -p out/roms
python3 mkroms.py "$ROMS" out/roms > /dev/null
# Verilog netlist of the VHDL TMS5220 for Verilator (regenerated when the VHDL changes)
[ out/tms5220_gen.v -nt ../rtl/tms5220/TMS5220.vhd ] || bash gen_tms5220.sh > /dev/null

verilator --cc --exe --build -j "$(nproc)" -O3 --x-assign fast --x-initial fast \
  -Wno-fatal -Wno-WIDTH -Wno-CASEINCOMPLETE -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY \
  --top-module jedi_core \
  -GMAIN_ROM_INIT='"roms/main.hex"' -GSND_ROM_INIT='"roms/snd.hex"' -GTX_ROM_INIT='"roms/tx.hex"' \
  -GBG1_ROM_INIT='"roms/bg1.hex"' -GBG2_ROM_INIT='"roms/bg2.hex"' \
  -GSPR1_ROM_INIT='"roms/spr1.hex"' -GSPR2_ROM_INIT='"roms/spr2.hex"' \
  -GPROM1_INIT='"roms/prom1.hex"' -GPROM2_INIT='"roms/prom2.hex"' \
  -GNOVRAM_INIT='"../../rtl/novram_init.hex"' \
  -Mdir obj_dir ${JEDI_TRACE:+-DJEDI_TRACE} ${JEDI_TRACE_IO:+-DJEDI_TRACE_IO} \
  ${V_START:+-GV_START=$V_START} \
  ${PC_FROM:+-DJEDI_TRACE_PC -DPC_FROM=$PC_FROM -DPC_TO=$PC_TO} \
  ${RD_FROM:+-DJEDI_RAMDUMP -DRD_FROM=$RD_FROM} \
  ${WATCH:+-DJEDI_WATCH -DW0=16\'h${WATCH:0:4} -DW1=16\'h${WATCH:5:4} -DW2=16\'h${WATCH:10:4} -DW3=16\'h${WATCH:15:4}} \
  ../rtl/cpu6502/ALU.v ../rtl/cpu6502/cpu.v ../rtl/dpram.v ../rtl/jedi_timing.v ../rtl/pokey.v \
  ../rtl/jedi_cheats.v \
  out/tms5220_gen.v ../rtl/jedi_core.v \
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
