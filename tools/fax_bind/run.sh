#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
out="$root/simulation/fax_bind"
mkdir -p "$out/profile_obj" "$out/window_obj"

verilator --binary --timing -Wno-fatal --top-module tb_fax_profile_controls \
  --Mdir "$out/profile_obj" \
  "$root/rtl/fax_controls.v" \
  "$root/rtl/fax_profile_controls.v" \
  "$root/sim/fax_controls/tb_fax_profile_controls.sv" \
  -o sim
"$out/profile_obj/sim"

verilator --binary --timing -Wno-fatal --top-module tb_fax_question_window \
  --Mdir "$out/window_obj" \
  "$root/rtl/fax_question_window.v" \
  "$root/sim/fax_controls/tb_fax_question_window.sv" \
  -o sim
"$out/window_obj/sim"
