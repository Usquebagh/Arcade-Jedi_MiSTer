#!/bin/bash
# Timing summary and PLL frequency from the last build
cd "$(dirname "$0")"
echo "== timing requirement warnings"
grep -i 'timing requirements not met' build.log | head -3 || true
echo "== per-clock setup slack (worst corner)"
awk '/Slow 1100mV 85C Model Setup Summary/{on=1} on && /^; /{print} /Slow 1100mV 85C Model Hold Summary/{exit}' output_files/Arcade-Jedi.sta.rpt | head -20
echo "== PLL output"
grep -iE 'emu.pll.*(Output|outclk|frequency)|48\.38' output_files/Arcade-Jedi.fit.rpt | head -6
