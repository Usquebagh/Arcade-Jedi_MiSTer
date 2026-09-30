#!/bin/bash
# Coin at frame 300, trigger at 420 (start) and 600 (level select), 30 s run.
# Compares screenshots and audio loudness with the MAME capture in ~/mame_play3.
cd "$(dirname "$0")"
INPUTS=300:7f,306:ff,420:fd,426:ff,600:fd,606:ff bash run.sh "${1:-1800}" 60 > out/play.log 2>&1 || { tail out/play.log; exit 1; }
python3 raw2wav.py out/audio.raw out/play.wav
python3 wavinfo.py out/play.wav > out/play_loudness.txt
python3 wavinfo.py "$HOME/mame_play3/play.wav" > out/mame_loudness.txt
paste -d'|' out/play_loudness.txt out/mame_loudness.txt | cut -c1-120
python3 contact.py out/play_sheet.png 6 out/frame_*.png
