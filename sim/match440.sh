#!/bin/bash
# Match simulation frames 440-460 against the per-frame MAME captures
cd "$(dirname "$0")"
python3 bestmatch.py 'out/frame_04[4-6]*.ppm' "$HOME/mame_ref2/mame_*.png"
