#!/usr/bin/env python3
"""Per-second AC loudness of two WAVs side by side, plus the ratio.
Usage: audio_compare.py <sim.wav> <mame.wav>"""
import math
import struct
import sys
import wave


def loudness(path):
    w = wave.open(path)
    ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
    data = struct.unpack(f"<{n * ch}h", w.readframes(n))[::ch]
    out = []
    for s in range(int(n / rate)):
        seg = data[s * rate:(s + 1) * rate]
        mean = sum(seg) / len(seg)
        out.append(math.sqrt(sum((v - mean) ** 2 for v in seg) / len(seg)))
    return out


a, b = loudness(sys.argv[1]), loudness(sys.argv[2])
print("  s      sim     mame   ratio")
for s, (x, y) in enumerate(zip(a, b)):
    r = f"{x / y:6.2f}" if y > 50 else "     -"
    print(f"{s:3d} {x:8.0f} {y:8.0f}  {r}")
