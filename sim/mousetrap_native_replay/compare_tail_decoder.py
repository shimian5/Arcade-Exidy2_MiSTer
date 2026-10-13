#!/usr/bin/env python3
"""Check captured replay decoder rows against the pinned MAME bit-event method.

The oracle receives every replay digit write as one low-clock transition. Only
rows actually sampled by the HDL are compared; this does not invent or claim
the unobserved internal decoder history of native MAME.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shlex
import subprocess
from pathlib import Path

SCALE = 1 << 24
ROOT = Path(__file__).resolve().parents[2]
PINNED_SOURCE_SHA256 = "4eef48eb9589f8fd914692cd0251457495d6dc65a491326d542f20a5d8571ba4"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path, help="completed native replay result directory")
    args = parser.parse_args()
    run = args.run.resolve()
    io_path, samples_path = run / "io.csv", run / "samples.csv"
    digit_events: list[tuple[int, int]] = []
    with io_path.open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            address = int(row["address"], 16)
            if row["kind"] == "W" and (address & 0x10) == 0:
                digit_events.append((int(row["time_ps"]), int(row["data"], 16) & 1))
    samples = list(csv.DictReader(samples_path.open(newline="", encoding="utf-8-sig")))
    if not digit_events or not samples:
        raise SystemExit("Replay digit or sampled decoder log is empty")

    # Recreate the D0 level at each actual falling RC edge, rather than
    # incorrectly treating every port write as a decoder edge. Writes just
    # after an edge affect the following edge. The sparse sample timestamps
    # reveal the simulation's accumulated period (10,000 falling edges).
    first_sample_ps = int(samples[0]["time_ps"])
    edge_bits: list[int] = []
    event_index = 0
    digit = 0
    edge_count = len(samples) * 10_000
    for ordinal in range(1, edge_count + 1):
        edge_time = first_sample_ps * ordinal // 10_000
        while event_index < len(digit_events) and digit_events[event_index][0] <= edge_time:
            digit = digit_events[event_index][1]
            event_index += 1
        edge_bits.append(digit)
    for index, row in enumerate(samples):
        ordinal = (index + 1) * 10_000
        if int(row["digit"]) != edge_bits[ordinal - 1]:
            raise SystemExit(f"Captured digit disagrees with event-derived falling edge {ordinal}")

    stimulus = run / "decoder-oracle-stimulus.txt"
    reference = run / "decoder-oracle-reference.txt"
    with stimulus.open("w", encoding="ascii", newline="\n") as out:
        out.write("1 0 0 0\n")
        for bit in edge_bits:
            out.write(f"0 0 1 {bit}\n0 0 0 {bit}\n")

    cpp = ROOT / "simulation" / "mc3417" / "oracle.cpp"
    pinned_source = ROOT / "simulation" / "reference_sources" / "hc55516.cpp"
    if hashlib.sha256(pinned_source.read_bytes()).hexdigest() != PINNED_SOURCE_SHA256:
        raise SystemExit("Pinned MAME MC3417 source hash mismatch")
    if not cpp.exists():
        raise SystemExit("Missing extracted oracle harness; run tools/mc3417/prepare_reference.py first")
    oracle_cpp_sha = hashlib.sha256(cpp.read_bytes()).hexdigest()
    binary = run / "decoder-oracle"

    def linux_path(path: Path) -> str:
        raw = path.resolve().as_posix()
        if len(raw) < 3 or raw[1:3] != ":/":
            raise ValueError(f"Expected a Windows drive path: {raw}")
        return "/mnt/" + raw[0].lower() + raw[2:]

    command = "g++ -std=c++17 -O2 {} -o {} && {} {} {}".format(
        shlex.quote(linux_path(cpp)), shlex.quote(linux_path(binary)),
        shlex.quote(linux_path(binary)), shlex.quote(linux_path(stimulus)),
        shlex.quote(linux_path(reference)))
    result = subprocess.run(
        ["wsl.exe", "-d", "archlinux", "--", "bash", "-lc", command],
        check=False, text=True, capture_output=True)
    if result.returncode:
        raise SystemExit(f"Pinned MAME oracle failed: {result.stdout}{result.stderr}")

    expected = reference.read_text(encoding="ascii").splitlines()
    if len(expected) != 1 + 2 * len(edge_bits):
        raise SystemExit("Pinned oracle row count differs from captured digits")
    worst = 0.0
    for index, row in enumerate(samples):
        # HDL captures every 10,000th falling edge. Oracle row 2*n is the
        # post-falling-edge state for one-based digit event n.
        ordinal = (index + 1) * 10_000
        if ordinal > len(edge_bits):
            raise SystemExit(f"Sample {index + 1} exceeds replay digit count")
        ref = expected[2 * ordinal].split()
        if int(ref[3]) != edge_bits[ordinal - 1]:
            raise SystemExit(f"Digit stimulus mismatch at falling edge {ordinal}")
        if int(row["history"]) != int(ref[4]):
            raise SystemExit(f"History mismatch at falling edge {ordinal}")
        for field, column in (("step_q24", 5), ("integrator_q24", 6)):
            error = abs(int(row[field]) / SCALE - float(ref[column])) * SCALE
            if error >= 256:
                raise SystemExit(f"{field} mismatch {error:.3f} Q24 at edge {ordinal}")
        error = abs(int(row["sample_q24"]) / SCALE - float(ref[7])) * 32768
        worst = max(worst, error)
        if error >= 0.5:
            raise SystemExit(f"Sample mismatch {error:.6f} PCM LSB at edge {ordinal}")

    report = {
        "digit_port_writes": len(digit_events),
        "decoder_falling_edges": len(edge_bits),
        "compared_sampled_states": len(samples),
        "sampled_every_falling_edges": 10_000,
        "max_sample_error_pcm_lsb": worst,
        "pinned_mame_source_sha256": PINNED_SOURCE_SHA256,
        "extracted_oracle_harness_sha256": oracle_cpp_sha,
        "scope": "captured replay state rows checked against pinned MAME MC3417 process_bit method; sparse sampled states only, not native MAME state or PCM equality",
    }
    (run / "decoder-oracle-comparison.json").write_text(
        json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"PASS pinned MC3417 reference: {len(samples)} sampled states, {len(edge_bits)} derived falling edges from {len(digit_events)} port writes, max sample error {worst:.6f} PCM LSB")
    print(result.stdout.strip())


if __name__ == "__main__":
    main()
