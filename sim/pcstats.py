#!/usr/bin/env python3
"""Most frequent PCs in a sim trace, and context around the first hit of a given PC prefix."""
import collections
import sys

pcs = [l.split()[1].upper() for l in open(sys.argv[1]) if l.startswith("PC ")]
print(collections.Counter(pcs).most_common(8))
prefix = sys.argv[2] if len(sys.argv) > 2 else "EF0"
for i, pc in enumerate(pcs):
    if pc.startswith(prefix):
        print("context:", pcs[max(0, i - 6):i + 6])
        break
else:
    print("no PC starting with", prefix)
