#!/bin/bash
# Run with JEDI_TRACE and show one frame's worth of events around frame 450
cd "$(dirname "$0")"
JEDI_TRACE=1 bash run.sh 452 1000 > out/trace.log 2>&1
awk '/^frame  450/{on=1} on' out/trace.log | grep -E "TRACE|^frame" | head -40
