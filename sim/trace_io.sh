#!/bin/bash
# Summarise main-CPU I/O and sound traffic over the first 700 frames
cd "$(dirname "$0")"
JEDI_TRACE_IO=1 bash run.sh 700 1000 > out/trace_io.log 2>&1
echo "== counts by kind/address"
grep "^IO" out/trace_io.log | awk '{print $2, ($2=="m_rd" ? substr($3,1,4) : "")}' | sort | uniq -c
echo "== distinct values read from 1400 (sound ack) / 0C01"
grep "^IO m_rd 14" out/trace_io.log | awk '{print $3}' | sort | uniq -c | head
grep "^IO m_rd 0c01\|^IO m_rd 0C01" out/trace_io.log | awk '{print $3}' | sort | uniq -c | head
echo "== sound commands (first 30)"
grep "^IO snd_cmd" out/trace_io.log | head -30 | awk '{printf "%s ", $3} END {print ""}'
echo "== pokey reads (addresses)"
grep "^IO pokey_rd" out/trace_io.log | awk '{print $3}' | sort | uniq -c | head
