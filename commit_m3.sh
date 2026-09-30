#!/bin/bash
cd "$(dirname "$0")"
chmod +x build.sh sim/*.sh
git add -A
git status --short | grep -v '^A  sys/' | head -40
echo "sys files: $(git status --short | grep -c '^A  sys/')"
git commit -q -F - <<'MSG'
Milestone 3: sound, speech, MiSTer integration, first Quartus build

- POKEY (rtl/pokey.v): MAME poly generators, 8/16-bit dividers, high-pass,
  1.79 MHz modes; 4 instances at 0800-083F. Pitch and rhythm match MAME.
- TMS5220 speech: d18c7db's VHDL model (GPL-3.0), variable slices rewritten
  for GHDL; converted to Verilog with GHDL+Yosys for Verilator.
- MiSTer top (Arcade-Jedi.sv): hps_io OSD, ROM download, NVRAM save/load
  (ioctl index 4), yoke via Videodr0me's adapter, arcade_video, 48.384 MHz PLL.
- MRA for the MAME jedi set; build.sh (Quartus 17.0.2 in Docker).
- First build: 44% ALMs, 409/553 M10K, timing met.
MSG
git push -q
git log --oneline -1
