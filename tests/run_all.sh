#!/bin/bash
cd "$(dirname "$0")/.."
G=${GODOT:-/c/Users/admin/tools/godot/Godot_v4.3-stable_win64_console.exe}
for n in eject player save caravan god spy weather input fryhtan_player model_timing goals items special_firms campaign reports tutorial editor waypoint wish diplomacy events fire rebel wagon options fidelity training setup economy town scenarios features; do
  t0=$(date +%s)
  r=$(timeout 600 $G --headless --path . res://tests/${n}_test.tscn 2>&1 | grep -E "RESULT|SCRIPT ERROR|^FAIL" | sort -u | head -4 | tr '\n' ' ')
  echo "${n}_test ($(( $(date +%s) - t0 ))s): $r"
done
