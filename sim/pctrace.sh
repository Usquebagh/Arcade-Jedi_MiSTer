#!/bin/bash
# Main-CPU instruction trace for frames $1..$2, compared with the MAME trace by
# RNG loop iterations per IRQ.
cd "$(dirname "$0")"
PC_FROM=${1:-640} PC_TO=${2:-700} bash run.sh "${2:-700}" 100000 > out/pctrace_raw.log 2>&1
echo "PC lines: $(grep -c '^PC ' out/pctrace_raw.log)"
grep -c 'PC %04X' obj_dir/*.cpp | grep -v ':0' | head -3
python3 rng_loops.py "$HOME/mame_trace.log" out/pctrace_raw.log
