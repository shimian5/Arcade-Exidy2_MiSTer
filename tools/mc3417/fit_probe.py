#!/usr/bin/env python3
"""Prepare a standalone MC3417 full-flow probe; never edit core assignments."""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation/mc3417/fit"


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = ROOT / "rtl/mc3417.v"
    device = re.search(
        r"-name DEVICE (\S+)", (ROOT / "Arcade-Exidy2.qsf").read_text()).group(1)
    lines = [
        'set_global_assignment -name FAMILY "Cyclone V"',
        f"set_global_assignment -name DEVICE {device}",
        "set_global_assignment -name TOP_LEVEL_ENTITY exidyMc3417",
        "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files",
        "set_global_assignment -name NUM_PARALLEL_PROCESSORS 2",
        'set_global_assignment -name OPTIMIZATION_MODE "BALANCED"',
        "set_global_assignment -name SDC_FILE probe.sdc",
        f'set_global_assignment -name VERILOG_FILE "{source.as_posix()}"',
        "set_location_assignment PIN_V11 -to clk",
        'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk',
    ]
    for port in ("cold_reset_n", "clock_reset", "cvsd_clock", "digit"):
        lines.append(f"set_instance_assignment -name VIRTUAL_PIN ON -to {port}")
    for port, width in (("sample_q24", 32), ("history", 3),
                        ("step_q24", 32), ("integrator_q24", 32)):
        for index in range(width):
            target = port + "[" + str(index) + "]"
            lines.append(f"set_instance_assignment -name VIRTUAL_PIN ON -to {target}")
    (OUT / "mc3417_probe.qsf").write_text("\n".join(lines) + "\n")
    (OUT / "mc3417_probe.qpf").write_text(
        'QUARTUS_VERSION = "17.0"\nPROJECT_REVISION = "mc3417_probe"\n')
    (OUT / "probe.sdc").write_text(
        "# Standalone candidate at the current production audio-clock period.\n"
        "create_clock -name audio -period 69.604 [get_ports clk]\n"
        "derive_clock_uncertainty\n"
        "# Virtual control/data I/O has no board delay assumptions here.\n"
        "# No false path or multicycle timing exceptions are applied.\n")
    (OUT / "coverage.tcl").write_text(
        "load_package sta\nproject_open mc3417_probe\n"
        "create_timing_netlist\nread_sdc probe.sdc\nupdate_timing_netlist\n"
        "check_timing -file check-timing.rpt\n"
        "delete_timing_netlist\nproject_close\n")
    (OUT / "source.json").write_text(json.dumps({
        "source": str(source.relative_to(ROOT)),
        "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "device": device,
        "periodNs": 69.604,
        "limits": "Standalone only; virtual I/O; no whole-core/CDC/reset acceptance.",
    }, indent=2) + "\n")
    print(OUT)


if __name__ == "__main__":
    main()
