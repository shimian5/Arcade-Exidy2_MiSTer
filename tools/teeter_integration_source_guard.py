#!/usr/bin/env python3
"""Bind the Teeter boundary-model fixture to current Exidy2 source and candidate patch.

This is a source-shape guard, not a production compile or integrated-core test.
It fails if the existing CPU mux/T65 wiring changes or if the unapplied candidate
patch/testbench stop modeling those same source-selection and sample contracts.
"""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def read_head(path: str) -> str:
    return subprocess.check_output(["git", "show", f"HEAD:{path}"], cwd=ROOT, text=True)


def require(ok: bool, message: str) -> None:
    if not ok:
        raise SystemExit(f"FAIL Teeter source guard: {message}")


def positions_in_order(text: str, tokens: list[str], label: str) -> None:
    cursor = -1
    for token in tokens:
        found = text.find(token, cursor + 1)
        require(found >= 0, f"{label} missing or reorders {token!r}")
        cursor = found


def main() -> int:
    core = read_head("rtl/Exidy2.v")
    top = read_head("Arcade-Exidy2.sv")
    patch = (ROOT / "candidates/teeter-integration.patch").read_text(encoding="utf-8")
    bench = (ROOT / "sim/teeter_controls/tb_teeter_integration_mux.sv").read_text(encoding="utf-8")
    hps = (ROOT / "sys/hps_io.sv").read_text(encoding="utf-8")

    mux_start = core.find("CPU_databus_in <=")
    mux_end = core.find(";", mux_start)
    require(mux_start >= 0 and mux_end > mux_start, "could not locate registered CPU input mux")
    mux = core[mux_start:mux_end]
    mux_tokens = [
        "(!RAMSEL", "CPU_RAM_out", "(!ROMSEL", "CPU_PROM_out",
        "(!SRAMSEL", "VRAM_CPU_out", "(!CHARSEL", "VRAM_out_CSCG1_CPU",
        "(!EXTVID", "VRAM_out_CSCG2_CPU", "(!IOSEL & CPU_addrbus[1:0]==2'b01", "ESR",
    ]
    positions_in_order(mux, mux_tokens, "production read mux priority")

    t65_start = core.find("T65 M6502(")
    t65_end = core.find("\n);", t65_start)
    require(t65_start >= 0 and t65_end > t65_start, "could not locate T65 instance")
    t65 = core[t65_start:t65_end]
    for pin in (".enable(PH_1)", ".rdy(~pause)", ".di(CPU_databus_in)"):
        require(pin in t65, f"T65 source binding changed: {pin}")

    expected_pending = (
        "teeter_profile && CPU_RWn && RAMSEL && ROMSEL && SRAMSEL && "
        "CHARSEL && EXTVID && !IOSEL && (CPU_addrbus[1:0] == 2'b01)"
    )
    require(expected_pending in patch, "candidate pending qualifier no longer excludes mux priorities")
    require("wire teeter_read_strobe = teeter_read_pending && PH_1 && !pause;" in patch,
            "candidate read strobe no longer matches enabled, ready T65 edge")
    require(".cpu_read_data(CPU_databus_in)" in patch,
            "candidate does not consume the registered CPU input byte")
    require("wire [7:0] ESR = teeter_profile ? teeter_in0 : ESR_GENERIC;" in patch,
            "candidate no longer gates only the Teeter ESR profile")
    require("wire teeter_profile = (pcb == 8'hD0);" in patch,
            "candidate profile guard is not exact byte D0")

    # Ensure the boundary model has the same mux branch order and qualifier contract.
    bench_mux_start = bench.find("assign cpu_mux_data =")
    bench_mux_end = bench.find(";", bench_mux_start)
    require(bench_mux_start >= 0 and bench_mux_end > bench_mux_start, "bench mux model is missing")
    bench_mux = bench[bench_mux_start:bench_mux_end]
    positions_in_order(bench_mux, ["!RAMSEL", "!ROMSEL", "!SRAMSEL", "!CHARSEL", "!EXTVID", "!IOSEL"],
                       "fixture read mux priority")
    compact_bench = " ".join(bench.split())
    require("profile_d0 && cpu_rw_n && RAMSEL && ROMSEL && SRAMSEL && CHARSEL && EXTVID && !IOSEL && (addr_lo == 2'b01)" in compact_bench,
            "fixture qualifier diverges from candidate source qualifier")
    require("if (ph1 && !pause)\n                cpu_sampled_data <= CPU_databus_in;" in bench,
            "fixture no longer models prior DI sampling on PH_1/RDY")

    require("output reg [15:0] joystick_l_analog_0" in hps and "output reg  [8:0] spinner_0" in hps,
            "HPS analog/spinner port widths changed")
    require("wire clk_sys=clkm_45MHZ;" in top and ".master_clock(clkm_45MHZ)" in top,
            "top-level HPS/core master clock relationship changed")

    print("PASS Teeter source guard: production mux/T65 bindings match unapplied patch and boundary fixture")
    return 0


if __name__ == "__main__":
    sys.exit(main())
