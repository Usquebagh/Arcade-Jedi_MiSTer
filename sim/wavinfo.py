#!/usr/bin/env python3
"""AC loudness (mean removed) per second of a WAV file, first channel only."""
import math
import struct
import sys
import wave

w = wave.open(sys.argv[1])
ch, rate, n = w.getnchannels(), w.getframerate(), w.getnframes()
data = struct.unpack(f"<{n * ch}h", w.readframes(n))[::ch]
print(f"{rate} Hz, {ch} ch, {n / rate:.1f} s")
for s in range(int(n / rate)):
    seg = data[s * rate:(s + 1) * rate]
    mean = sum(seg) / len(seg)
    rms = math.sqrt(sum((v - mean) ** 2 for v in seg) / len(seg))
    print(f"{s:3d}s rms {rms:7.0f} " + "#" * int(rms / 250))
