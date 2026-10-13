#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
out="$root/simulation/fax_bind"
python3 "$root/tools/fax_bind/build_mra_images.py"
mkdir -p "$out/mra_loader_obj"
verilator --binary --timing -Wno-fatal --top-module tb_fax_mra_loader \
  --Mdir "$out/mra_loader_obj" \
  "$root/candidates/fax/fax_exidy_expansion_loader.sv" \
  "$root/candidates/fax/fax_expansion_wrapper.sv" \
  "$root/candidates/fax/tb_fax_mra_loader.sv" \
  -o sim
"$out/mra_loader_obj/sim" +IMAGE_DIR="$out/mra_images" +SET=fax
"$out/mra_loader_obj/sim" +IMAGE_DIR="$out/mra_images" +SET=fax2
