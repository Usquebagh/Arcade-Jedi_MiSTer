#!/bin/bash
# Progress of the background Quartus build and simulation
cd "$(dirname "$0")"
echo "== quartus"
grep -E '^(Error|Critical Warning)' build.log 2>/dev/null | head -10
grep -E 'Info: Running Quartus Prime (Analysis|Fitter|Assembler|Timing)' build.log 2>/dev/null
tail -1 build.log 2>/dev/null | cut -c1-150
echo "== sim"
tail -c 200 sim/out/play.log | tail -1
