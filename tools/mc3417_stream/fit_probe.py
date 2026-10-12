#!/usr/bin/env python3
"""Prepare a standalone full-flow MC3417 stream fit probe.

This creates an isolated project under simulation/ and does not modify the
production Quartus assignments.
"""
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation/mc3417_stream/fit"
PROJECT = "mc3417_stream_probe"
SOURCE = ROOT / "rtl/mc3417_stream.v"
PERIOD_NS = 69.604


def main():
    if not SOURCE.is_file():
        raise SystemExit(f"Candidate RTL is missing: {SOURCE}")
    qsf = (ROOT / "Arcade-Exidy2.qsf").read_text(encoding="utf-8")
    match = re.search(r"-name DEVICE (\S+)", qsf)
    if not match:
        raise SystemExit("Could not read the production device from Arcade-Exidy2.qsf")
    device = match.group(1)

    OUT.mkdir(parents=True, exist_ok=True)
    lines = [
        'set_global_assignment -name FAMILY "Cyclone V"',
        f"set_global_assignment -name DEVICE {device}",
        f"set_global_assignment -name TOP_LEVEL_ENTITY exidyMc3417Stream",
        "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files",
        "set_global_assignment -name NUM_PARALLEL_PROCESSORS 2",
        'set_global_assignment -name OPTIMIZATION_MODE "BALANCED"',
        "set_global_assignment -name SDC_FILE probe.sdc",
        f'set_global_assignment -name VERILOG_FILE "{SOURCE.as_posix()}"',
        "set_location_assignment PIN_V11 -to clk",
        'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk',
    ]
    ports = (
        ("cold_reset_n", 1),
        ("sample_ce", 1),
        ("clock_transition", 1),
        ("sample_valid", 1),
        ("sample_q24", 32),
        ("pcm_q24", 32),
        ("idle", 1),
    )
    for port, width in ports:
        targets = [port] if width == 1 else [f"{port}[{bit}]" for bit in range(width)]
        for target in targets:
            lines.append(f"set_instance_assignment -name VIRTUAL_PIN ON -to {target}")
    (OUT / f"{PROJECT}.qsf").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (OUT / f"{PROJECT}.qpf").write_text(
        f'QUARTUS_VERSION = "17.0"\nPROJECT_REVISION = "{PROJECT}"\n',
        encoding="utf-8",
    )
    (OUT / "probe.sdc").write_text(
        "# Standalone candidate at the production audio-clock period.\n"
        f"create_clock -name audio -period {PERIOD_NS} [get_ports clk]\n"
        "derive_clock_uncertainty\n"
        "# Virtual control/data I/O has no board delay assumptions.\n"
        "# No false path or multicycle timing exceptions are applied.\n",
        encoding="utf-8",
    )
    (OUT / "coverage.tcl").write_text(
        f"load_package sta\nproject_open {PROJECT}\n"
        "create_timing_netlist\nread_sdc probe.sdc\nupdate_timing_netlist\n"
        "check_timing -file check-timing.rpt\n"
        "report_clocks -file clocks.rpt\n"
        "report_timing -setup -npaths 20 -detail full_path -file setup-timing.rpt\n"
        "report_timing -hold -npaths 20 -detail full_path -file hold-timing.rpt\n"
        "delete_timing_netlist\nproject_close\n",
        encoding="utf-8",
    )
    manifest = {
        "source": str(SOURCE.relative_to(ROOT)),
        "sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
        "top": "exidyMc3417Stream",
        "device": device,
        "periodNs": PERIOD_NS,
        "ports": {port: width for port, width in ports},
        "limits": "Standalone only; virtual I/O; no whole-core/CDC/reset acceptance.",
    }
    (OUT / "source.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(OUT)


if __name__ == "__main__":
    main()
