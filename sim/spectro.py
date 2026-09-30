#!/usr/bin/env python3
"""Stacked spectrograms (log magnitude, 0-6 kHz) of WAV files over a time window.
Usage: spectro.py <out.png> <t0> <t1> <wav> [wav...]   (first channel of each file)"""
import sys
import wave

import numpy as np
from PIL import Image, ImageDraw

out, t0, t1, files = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4:]
import os
N, HOP, FMAX = 4096, 256, int(os.environ.get("FMAX", 6000))
rows = []
for f in files:
    w = wave.open(f)
    ch, rate = w.getnchannels(), w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")[::ch].astype(float)
    x = x[int(t0 * rate):int(t1 * rate)]
    x -= x.mean()
    win = np.hanning(N)
    frames = [np.abs(np.fft.rfft(x[i:i + N] * win)) for i in range(0, len(x) - N, HOP)]
    s = np.array(frames).T[: int(FMAX * N / rate)]
    s = 20 * np.log10(s + 1e-3)
    s = np.clip((s - (s.max() - 70)) / 70, 0, 1)
    img = Image.fromarray((255 * s[::-1]).astype(np.uint8)).resize((900, 220))
    rows.append((f.rsplit("/", 1)[-1], img))

sheet = Image.new("L", (900, len(rows) * 236), 0)
d = ImageDraw.Draw(sheet)
for i, (name, img) in enumerate(rows):
    sheet.paste(img, (0, i * 236 + 16))
    d.text((4, i * 236 + 2), f"{name}  {t0}-{t1}s  0-{FMAX} Hz", fill=255)
sheet.save(out)
