#!/usr/bin/env python3
"""Prepare a standalone full-flow Quartus probe for the MC3417 filter."""
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation/mc3417_filter/fit"
PROJECT = "mc3417_filter_probe"
TOP = "exidyMc3417Filter"
PERIOD_NS = 69.604
SOURCES = (ROOT / "rtl/exidy_biquad.v", ROOT / "rtl/mc3417_filter.v")
PORTS = (
    ("clk", 1),
    ("cold_reset_n", 1),
    ("sample_ce", 1),
    ("sample_q24", 32),
    ("audio_base", 16),
    ("mute", 1),
    ("filtered_q24", 32),
    ("pcm", 16),
    ("pcm_valid", 1),
    ("overrun", 1),
    ("mono", 16),
    ("clipped", 1),
)


def main():
    for source in SOURCES:
        if not source.is_file():
            raise SystemExit(f"Candidate RTL is missing: {source}")

    qsf = ROOT / "Arcade-Exidy2.qsf"
    match = re.search(r"-name DEVICE (\S+)", qsf.read_text(encoding="utf-8"))
    if not match:
        raise SystemExit("Could not read the production device from Arcade-Exidy2.qsf")
    device = match.group(1)

    OUT.mkdir(parents=True, exist_ok=True)
    lines = [
        'set_global_assignment -name FAMILY "Cyclone V"',
        f"set_global_assignment -name DEVICE {device}",
        f"set_global_assignment -name TOP_LEVEL_ENTITY {TOP}",
        "set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files",
        "set_global_assignment -name NUM_PARALLEL_PROCESSORS 2",
        'set_global_assignment -name OPTIMIZATION_MODE "BALANCED"',
        "set_global_assignment -name SDC_FILE probe.sdc",
        "set_location_assignment PIN_V11 -to clk",
        'set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk',
    ]
    for source in SOURCES:
        lines.append(f'set_global_assignment -name VERILOG_FILE "{source.as_posix()}"')
    for port, width in PORTS:
        if port == "clk":
            continue
        targets = [port] if width == 1 else [f"{port}[{bit}]" for bit in range(width)]
        for target in targets:
            lines.append(f"set_instance_assignment -name VIRTUAL_PIN ON -to {target}")

    (OUT / f"{PROJECT}.qsf").write_text("\n".join(lines) + "\n", encoding="utf-8")
    (OUT / f"{PROJECT}.qpf").write_text(
        f'QUARTUS_VERSION = "17.0"\nPROJECT_REVISION = "{PROJECT}"\n',
        encoding="utf-8",
    )
    (OUT / "probe.sdc").write_text(
        "# Standalone filter candidate at the production 192 kHz sample period.\n"
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
        "schema": "exidy2-mc3417-filter-fit-probe/v1",
        "project": str(OUT.relative_to(ROOT)),
        "top": TOP,
        "device": device,
        "sampleRateHz": 192000,
        "periodNs": PERIOD_NS,
        "ports": {port: width for port, width in PORTS},
        "sourceSha256": {
            str(source.relative_to(ROOT)): hashlib.sha256(source.read_bytes()).hexdigest()
            for source in SOURCES
        },
        "productionQsfSha256": hashlib.sha256(qsf.read_bytes()).hexdigest(),
        "coverage": {
            "status": "pending-full-flow",
            "reports": [
                "check-timing.rpt",
                "clocks.rpt",
                "setup-timing.rpt",
                "hold-timing.rpt",
            ],
        },
        "limits": [
            "Standalone filter only; virtual I/O; no whole-core or CDC/reset acceptance.",
            "Timing coverage is limited to the supplied 69.604 ns audio clock and no board I/O delays.",
            "Record fit/resource and timing outcomes only after a successful full-flow compile.",
        ],
    }
    (OUT / "source.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(OUT)
    print("Run from inside that directory after this script has generated the project:")
    print(f"  quartus_sh --flow compile {PROJECT}")


if __name__ == "__main__":
    main()
