#!/usr/bin/env python3
"""Total RNG-loop iterations over the traced window, MAME vs simulation."""
import sys
sys.argv = sys.argv[:3]
exec(open("rng_loops.py").read().split("# Align")[0])
print("total loops  MAME:", sum(mame), " sim:", sum(sim))
print("per-interval |diff| histogram:",
      {d: sum(1 for a, b in zip(mame, sim) if abs(a - b) == d) for d in range(4)})
