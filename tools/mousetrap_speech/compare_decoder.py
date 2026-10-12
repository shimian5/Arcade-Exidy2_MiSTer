#!/usr/bin/env python3
"""Prepare/check pinned MAME bit-event output for private firmware samples.

Run prepare, then the oracle built by tools/mc3417/prepare_reference.py,
then check. Inputs and outputs stay in the ignored simulation run directory.
This checks decoder arithmetic, not native MAME firmware/PCM equality.
"""
import argparse
import csv
import json
from pathlib import Path

SCALE = 1 << 24


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "check"))
    parser.add_argument("run", type=Path)
    parser.add_argument("--native-capture", type=Path,
                        help="Also check the native initial digit-write prefix; only valid for idle FF run")
    args = parser.parse_args()
    rows = list(csv.DictReader((args.run / "samples.csv").open(encoding="utf-8")))
    if not rows:
        raise SystemExit("No captured decoder samples")
    stimulus = args.run / "oracle-stimulus.txt"
    reference = args.run / "oracle-reference.txt"
    if args.mode == "prepare":
        with stimulus.open("w", encoding="utf-8") as out:
            out.write("1 0 0 0\n")
            for row in rows:
                bit = int(row["digit"])
                if bit not in (0, 1):
                    raise SystemExit("Invalid captured digit")
                out.write(f"0 0 1 {bit}\n0 0 0 {bit}\n")
        print(f"Prepared {len(rows)} firmware bit events for pinned-method oracle")
        return
    expected = [line.split() for line in reference.read_text(encoding="utf-8").splitlines()]
    if len(expected) != 1 + 2 * len(rows):
        raise SystemExit("Oracle row count differs from captured samples")
    worst = 0.0
    digit_counts = {"0": 0, "1": 0}
    for index, row in enumerate(rows):
        ref = expected[2 + 2 * index]
        if tuple(map(int, ref[:4])) != (0, 0, 0, int(row["digit"])):
            raise SystemExit(f"Oracle stimulus differs at sample {index}")
        if int(row["history"]) != int(ref[4]):
            raise SystemExit(f"History differs at sample {index}")
        # Each normalized state must stay within half a 16-bit quantum (256 Q24).
        for field, column in (("step_q24", 5), ("integrator_q24", 6)):
            error = abs(int(row[field]) / SCALE - float(ref[column])) * SCALE
            if error >= 256:
                raise SystemExit(f"{field} differs by {error:.3f} Q24 units at sample {index}")
        error = abs(int(row["sample_q24"]) / SCALE - float(ref[7])) * 32768
        worst = max(worst, error)
        if error >= 0.5:
            raise SystemExit(f"Sample differs by {error:.6f} PCM LSB at sample {index}")
        digit_counts[row["digit"]] += 1
    times = [int(row["time_ps"]) for row in rows]
    intervals = [b-a for a, b in zip(times, times[1:])]
    if any(not 64500000 <= delta <= 64750000 for delta in intervals):
        raise SystemExit("Unexpected sampled RC clock interval")
    result = dict(samples=len(rows), digit_counts=digit_counts,
                  max_error_pcm_lsb=worst, interval_ps_min=min(intervals),
                  interval_ps_max=max(intervals),
                  scope="pinned MAME method given RTL-sampled firmware bits; not native firmware/PCM equality")
    if args.native_capture:
        manifest = json.loads((args.run / "run-manifest.json").read_text(encoding="utf-8-sig"))
        if manifest["command"] != 255:
            raise SystemExit("Native startup prefix check requires idle callback FF")
        with (args.run / "io.csv").open(encoding="utf-8") as stream:
            rtl = [r for r in csv.DictReader(stream)
                   if r["kind"] == "W" and not (int(r["address"], 16) & 0x10)]
        native = []
        with args.native_capture.open(encoding="utf-8-sig", newline="") as stream:
            for r in csv.DictReader(stream):
                if r["kind"] == "W" and r["bus"] == "z80io" and not (int(r["address"], 16) & 0x10):
                    native.append(r)
                    if len(native) == len(rtl):
                        break
        if len(native) != len(rtl) or not rtl:
            raise SystemExit("Native digit-write prefix is shorter than fixture")
        for index, (a, b) in enumerate(zip(native, rtl)):
            if (int(a["address"], 16) & 255, int(a["data"], 16) & 1) != (
                    int(b["address"], 16) & 255, int(b["data"], 16) & 1):
                raise SystemExit(f"Native digit-write prefix differs at write {index}")
        result["native_initial_digit_write_prefix"] = len(rtl)
        result["native_prefix_limit"] = "ordered low-byte ports and D0 only; clock phase, write times, PCM and later commands not equal"
        print(f"PASS native initial digit-write prefix: {len(rtl)} writes; timing/phase equality unclaimed")
    (args.run / "decoder-comparison.json").write_text(
        json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(f"PASS {len(rows)} actual-ROM decoder samples; max error {worst:.6f} PCM LSB; digits {digit_counts}")


if __name__ == "__main__":
    main()
