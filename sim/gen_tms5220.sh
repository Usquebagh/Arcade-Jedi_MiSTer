#!/bin/bash
# Convert the TMS5220 VHDL model to a Verilog netlist for Verilator (simulation only;
# Quartus uses rtl/tms5220/TMS5220.vhd directly). Output: sim/out/tms5220_gen.v
set -e
cd "$(dirname "$0")"
mkdir -p out
# Ubuntu's yosys-plugin-ghdl looks for the gcc backend's libraries; point it at mcode's
export GHDL_PREFIX=/usr/lib/ghdl/mcode/vhdl
yosys -q -m ghdl -p "ghdl -fsynopsys --std=08 ../rtl/tms5220/TMS5220.vhd -e TMS5220; \
  proc; opt_clean; rename TMS5220 TMS5220; write_verilog -noattr out/tms5220_gen.v" \
  > out/tms5220_gen.log 2>&1 || { tail -30 out/tms5220_gen.log; exit 1; }
grep -m1 -A20 "^module" out/tms5220_gen.v
wc -l out/tms5220_gen.v
