#!/usr/bin/env bash
set -euo pipefail
root="$(git rev-parse --show-toplevel)"
out="$root/simulation/fax_bind"
python3 "$root/tools/fax_bind/build_mra_images.py"
python3 "$root/tools/fax_bind/build_source_transport.py"
obj="$out/production_wrapper_$(date +%s)"
mkdir -p "$obj"
if ! verilator --binary --timing -Wno-fatal --top-module tb_fax_wrapper_transport \
  --Mdir "$obj" \
  "$out/source_transport/source_transport.sv" \
  "$root/rtl/speech_loader.sv" \
  "$root/rtl/expansion/exidy_reset_sync.sv" \
  "$root/rtl/expansion/exidy_transport_adapter.sv" \
  "$root/rtl/expansion/exidy_expansion_loader_rr.sv" \
  "$root/rtl/expansion/exidy_expansion_bridge_rr.sv" \
  "$root/sim/speech_loader/tb_fax_wrapper_transport.sv" \
  -o sim; then
  # Verilator 5.052 can leave valid PCH output without source aliases after
  # an interrupted WSL build. Restore them before finishing its generated make.
  cp "$obj/Vtb_fax_wrapper_transport__pch.h" "$obj/Vtb_fax_wrapper_transport__pch.h.fast"
  cp "$obj/Vtb_fax_wrapper_transport__pch.h" "$obj/Vtb_fax_wrapper_transport__pch.h.slow"
  make -C "$obj" -f Vtb_fax_wrapper_transport.mk -j1
fi
"$obj/sim" +IMAGE_DIR="$out/mra_images" +SET=fax +ORDER_COUNT=5
"$obj/sim" +IMAGE_DIR="$out/mra_images" +SET=fax2 +ORDER_COUNT=5
