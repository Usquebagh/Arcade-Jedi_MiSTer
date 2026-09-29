#!/usr/bin/env python3
"""Compare MAME and simulation main-CPU traces by the number of RNG idle-loop
iterations (DE95) between IRQ handler entries (EF03).
Usage: rng_loops.py <mame trace> <sim trace>"""
import re
import sys

IRQ, LOOP = 0xEF03, 0xDE95


def pcs(path, pattern):
    rx = re.compile(pattern, re.IGNORECASE)
    for line in open(path):
        m = rx.match(line)
        if m:
            yield int(m.group(1), 16)


def loops_per_irq(seq):
    out, n, started = [], 0, False
    for pc in seq:
        if pc == IRQ:
            if started:
                out.append(n)
            started, n = True, 0
        elif pc == LOOP:
            n += 1
    return out


mame = loops_per_irq(pcs(sys.argv[1], r"^([0-9A-F]{4}): "))
sim = loops_per_irq(pcs(sys.argv[2], r"^PC ([0-9A-F]{4})"))
print("MAME intervals:", len(mame), "sim intervals:", len(sim))

# Align on the longest matching run, then report the first mismatch after it
best = (0, 0, 0)
for off in range(-12, 13):
    run = 0
    for i in range(min(len(mame), len(sim))):
        j = i + off
        if 0 <= j < len(sim) and mame[i] == sim[j]:
            run += 1
        else:
            if run > best[0]:
                best = (run, off, i - run)
            run = 0
    if run > best[0]:
        best = (run, off, min(len(mame), len(sim)) - run)
run, off, start = best
print(f"best alignment: sim index = mame index + {off}, {run} matching intervals from mame #{start}")
print("mame:", mame[max(0, start - 2):start + run + 6])
print("sim: ", sim[max(0, start - 2 + off):start + run + 6 + off])
