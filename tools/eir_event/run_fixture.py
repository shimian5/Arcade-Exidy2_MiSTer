#!/usr/bin/env python3
"""Extract the live Exidy2 IRQ/EIR span and test directed event ordering."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shlex
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl" / "Exidy2.v"
CAUSE = ROOT / "rtl" / "int_cause.v"
TB = ROOT / "sim" / "eir_event" / "tb.sv"
DEFAULT_RUN = ROOT / "simulation" / "eir_event"
START = "reg cDET,rCPU_IRQ,COINT;"
END = "always @(posedge rCPU_IRQ) EIR <="
EXPECTED_ASSERTIONS = 14
EXPECTED_CHECK_SITES = 10


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def span(source: str, start: str, end: str) -> str:
    if source.count(start) != 1:
        raise RuntimeError(f"guard anchor count mismatch: {start!r}={source.count(start)}")
    a = source.index(start)
    end_lines = [line for line in source.splitlines() if end in line and not line.lstrip().startswith("//")]
    if len(end_lines) != 1:
        raise RuntimeError(f"expected one active end anchor {end!r}, got {len(end_lines)}")
    b = source.index(end_lines[0], a)
    line_end = source.find("\n", b)
    if line_end < 0:
        line_end = len(source)
    block = source[a:line_end].rstrip()
    if "INT_CAUSE(" not in block or "always @(negedge BCLK or negedge COINT or negedge nEIR) rCPU_IRQ" not in block:
        raise RuntimeError("extracted span no longer contains expected helper and IRQ event logic")
    return block


def emit(run_dir: Path) -> dict:
    source = RTL.read_text(encoding="utf-8")
    template = TB.read_text(encoding="utf-8")
    actual = span(source, START, END)
    marker = "    // The runner inserts the guarded source span here, unchanged."
    if template.count(marker) != 1:
        raise RuntimeError("testbench insertion marker missing or duplicated")
    fixture = template.replace(marker, actual)
    # Convert the module template's externally visible probes to assignments
    # from the exact internal production signal names in the inserted span.
    fixture = fixture.replace("    // It includes declarations and assignments for cDET, rCPU_IRQ, COINT,\n    // INT_CAUSE, cDET_sel, and the IRQ/EIR event blocks.\nendmodule", """    // The span above is copied unchanged from rtl/Exidy2.v.
    assign eir_state = EIR;
    assign irq = rCPU_IRQ;
    assign coint = COINT;
    assign cause = int_cause;
    assign collision_irq = int_coll_irq;
    assign collision_select = cDET_sel;
endmodule""")
    # The template declares same-named output ports only as aliases; source
    # registers remain internal and are observed through these named aliases.
    run_dir.mkdir(parents=True, exist_ok=True)
    generated = run_dir / "extracted_eir_event.sv"
    generated.write_text(fixture, encoding="utf-8", newline="\n")
    return {
        "rtl": "rtl/Exidy2.v",
        "rtlSha256": sha256(RTL),
        "collisionHelper": "rtl/int_cause.v",
        "collisionHelperSha256": sha256(CAUSE),
        "template": "sim/eir_event/tb.sv",
        "templateSha256": sha256(TB),
        "sourceAnchors": {"start": START, "endPrefix": END},
        "extractedSpanSha256": hashlib.sha256(actual.encode()).hexdigest().upper(),
        "generatedFixture": str(generated.relative_to(ROOT)).replace("\\", "/"),
        "generatedFixtureSha256": sha256(generated),
        "extractedProductionLogicUnmodified": True,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", type=Path, default=DEFAULT_RUN)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--extract-only", action="store_true")
    args = parser.parse_args()
    run_dir = args.run_dir.resolve()
    try:
        run_dir.relative_to((ROOT / "simulation").resolve())
    except ValueError:
        raise SystemExit("--run-dir must stay under ignored simulation/")
    report_path = args.report.resolve() if args.report else run_dir / "result.json"
    try:
        report_path.relative_to((ROOT / "simulation").resolve())
    except ValueError:
        raise SystemExit("--report must stay under ignored simulation/")
    meta = emit(run_dir)
    result = {"metadata": meta, "compile": {}, "simulation": {}, "assertionsExpected": EXPECTED_ASSERTIONS}
    test_count = len(re.findall(r"\bcheck\s*\(", TB.read_text(encoding="utf-8"))) - 1
    if test_count != EXPECTED_CHECK_SITES:
        raise SystemExit(f"testbench check-site count changed: expected {EXPECTED_CHECK_SITES}, found {test_count}")
    if not args.extract_only:
        # Every invocation gets fresh compile and simulation outputs, avoiding
        # stale executables/logs being mistaken for the current result.
        exec_dir = run_dir / f"run_{int(time.time_ns())}"
        exec_dir.mkdir()
        src = (run_dir / "extracted_eir_event.sv").as_posix().replace("C:/", "/mnt/c/")
        helper = CAUSE.as_posix().replace("C:/", "/mnt/c/")
        build = (exec_dir / "obj_dir").as_posix().replace("C:/", "/mnt/c/")
        compile_args = ["verilator", "--binary", "--timing", "-Wno-fatal", "--Mdir", build, "--top-module", "tb", src, helper]
        compile_shell = "export MAKEFLAGS=OPT_FAST=-O0; exec " + shlex.join(compile_args)
        compile_proc = subprocess.run(["wsl.exe", "-d", "archlinux", "--", "bash", "-lc", compile_shell], cwd=ROOT, text=True, capture_output=True)
        (exec_dir / "compile.stdout.log").write_text(compile_proc.stdout, encoding="utf-8")
        (exec_dir / "compile.stderr.log").write_text(compile_proc.stderr, encoding="utf-8")
        result["compile"] = {"command": compile_shell, "returnCode": compile_proc.returncode, "stdoutLog": (exec_dir / "compile.stdout.log").relative_to(ROOT).as_posix(), "stderrLog": (exec_dir / "compile.stderr.log").relative_to(ROOT).as_posix()}
        result["returnCode"] = compile_proc.returncode
        if compile_proc.returncode == 0:
            exe = build + "/Vtb"
            sim_shell = "exec " + shlex.quote(exe)
            sim_proc = subprocess.run(["wsl.exe", "-d", "archlinux", "--", "bash", "-lc", sim_shell], cwd=ROOT, text=True, capture_output=True)
            (exec_dir / "simulation.stdout.log").write_text(sim_proc.stdout, encoding="utf-8")
            (exec_dir / "simulation.stderr.log").write_text(sim_proc.stderr, encoding="utf-8")
            lines = sim_proc.stdout.splitlines()
            pass_lines = [line for line in lines if line.startswith("PASS ")]
            fail_lines = [line for line in lines if line.startswith("FAIL ")]
            final_marker = "PASS exidy eir event fixture" in pass_lines
            assertion_passes = sum(line != "PASS exidy eir event fixture" for line in pass_lines)
            assertions_ok = assertion_passes == EXPECTED_ASSERTIONS and not fail_lines and final_marker
            result["simulation"] = {
                "command": sim_shell,
                "returnCode": sim_proc.returncode,
                "stdoutLog": (exec_dir / "simulation.stdout.log").relative_to(ROOT).as_posix(),
                "stderrLog": (exec_dir / "simulation.stderr.log").relative_to(ROOT).as_posix(),
                "assertionsPassed": assertion_passes,
                "assertionsExpected": EXPECTED_ASSERTIONS,
                "finalPassMarker": final_marker,
                "failures": fail_lines,
            }
            result["returnCode"] = 0 if sim_proc.returncode == 0 and assertions_ok else 1
        else:
            result["simulation"] = {"notRun": True}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    status = "PASS" if result.get("returnCode", 0) == 0 else "FAIL"
    assertions = result.get("simulation", {}).get("assertionsPassed", "not run")
    print(f"{status} Exidy IRQ/EIR fixture: {assertions}/{EXPECTED_ASSERTIONS} assertions; report {report_path}")
    return int(result.get("returnCode", 0))


if __name__ == "__main__":
    sys.exit(main())
