#!/usr/bin/env bash
set -euo pipefail
run="${1:?usage: run_charrom_palette.sh RUN_NAME}"
[[ "$run" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "invalid run name" >&2; exit 2; }
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="$root/simulation/side_trak/character_path/$run"
python3 "$root/tools/side_trak/build_char_vectors.py" \
  --rom-zip "$root/simulation/side_trak/roms/sidetrac.zip" \
  --mame-window "$out/mame-char-window.bin" \
  --out-dir "$out"
verilator --binary --timing -Wno-fatal --top-module tb_charrom_palette \
  --Mdir "$out/obj_dir" \
  "$root/candidates/side_trak/exidy_sidetrak_charrom.sv" \
  "$root/sim/side_trak/tb_charrom_palette.sv" >"$out/build.log" 2>&1 || {
    cat "$out/build.log"
    exit 1
  }
"$out/obj_dir/Vtb_charrom_palette" \
  +ROM="$out/char_image.hex" \
  +VECTORS="$out/glyph_vectors.txt" \
  +PALETTE="$out/palette_vectors.txt" | tee "$out/simulation.log"
