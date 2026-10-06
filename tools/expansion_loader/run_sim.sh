#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
mkdir -p simulation/expansion_loader/obj_dir
verilator --binary --timing -Wno-fatal --top-module tb_exidy_expansion_loader \
  --Mdir simulation/expansion_loader/obj_dir \
  sim/expansion_loader/exidy_expansion_loader.sv \
  sim/expansion_loader/tb_exidy_expansion_loader.sv
simulation/expansion_loader/obj_dir/Vtb_exidy_expansion_loader
