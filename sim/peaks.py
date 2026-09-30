#!/usr/bin/env python3
"""Strongest spectral peaks (Hz) of each WAV over [t0, t1].
Usage: peaks.py <t0> <t1> <wav> [wav...]"""
import sys
import wave

import numpy as np

t0, t1 = float(sys.argv[1]), float(sys.argv[2])
for f in sys.argv[3:]:
    w = wave.open(f)
    ch, rate = w.getnchannels(), w.getframerate()
    x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2")[::ch].astype(float)
    x = x[int(t0 * rate):int(t1 * rate)]
    x = (x - x.mean()) * np.hanning(len(x))
    s = np.abs(np.fft.rfft(x))
    hz = np.fft.rfftfreq(len(x), 1 / rate)
    # local maxima above 60 Hz, strongest first
    idx = [i for i in range(2, len(s) - 2)
           if hz[i] > 60 and s[i] == max(s[i - 2:i + 3])]
    idx.sort(key=lambda i: -s[i])
    top = sorted(round(hz[i]) for i in idx[:12])
    print(f"{f.rsplit('/', 1)[-1]:>10}: {top}")
