#!/usr/bin/env python3
"""Wrap signed 16-bit mono 48 kHz raw audio in a WAV header. Usage: raw2wav.py in.raw out.wav"""
import sys
import wave

data = open(sys.argv[1], "rb").read()
with wave.open(sys.argv[2], "wb") as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(48000)
    w.writeframes(data)
