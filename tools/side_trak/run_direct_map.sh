#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/simulation/side_trak/direct_map"
mkdir -p "$out"
python3 "$root/tools/side_trak/build_map_vectors.py" \
  --vectors "$out/mame-map-vectors.txt" \
  --report "$out/source-map-audit.json"
verilator --binary --timing -Wno-fatal --top-module tb_direct_map \
  --Mdir "$out/obj_dir" \
  "$root/candidates/side_trak/exidy_sidetrak_direct_map.sv" \
  "$root/sim/side_trak/tb_direct_map.sv" >"$out/build.log" 2>&1 || {
    cat "$out/build.log"
    exit 1
  }
"$out/obj_dir/Vtb_direct_map" +VECTORS="$out/mame-map-vectors.txt" \
  | tee "$out/simulation.log"
