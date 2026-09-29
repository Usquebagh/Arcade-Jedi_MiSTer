#!/bin/bash
# Frame-stamped timeline of CPU<->sound traffic and ADC values from out/trace_io.log
cd "$(dirname "$0")"
awk '/^frame /{f=$2} /^IO (snd_cmd|snd_ack|m_rd 14)/{print "frame", f, $0}' out/trace_io.log
echo "== ADC values read"
grep '^IO m_rd 18' out/trace_io.log | awk '{print $3}' | sort | uniq -c
