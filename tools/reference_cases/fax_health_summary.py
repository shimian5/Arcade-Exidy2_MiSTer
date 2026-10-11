#!/usr/bin/env python3
"""Validate completion of a passive FAX health capture and summarize progress."""
import argparse
import csv
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("run_dir", type=Path)
args = parser.parse_args()
events = (args.run_dir / "events.log").read_text(encoding="utf-8")
rows = list(csv.DictReader((args.run_dir / "health.csv").open(newline="")))
if "ERROR" in events or "complete frame=7200" not in events:
    raise SystemExit("FAIL: capture did not finish its declared 7200-frame sequence")
if events.count("input_check ") != 18:
    raise SystemExit("FAIL: expected 18 checked control press/release events")
if len(rows) != 121 or [int(row["frame"]) for row in rows] != list(range(0, 7201, 60)):
    raise SystemExit("FAIL: missing, duplicate or reordered CPU progress samples")
late = [row for row in rows if int(row["frame"]) >= 3600]
summary = {
    "samples": len(rows),
    "lateSamples": len(late),
    "lateInterruptDisableSetSamples": sum(bool(int(row["p"], 16) & 4) for row in late),
    "lateDistinctPCs": len({row["pc"] for row in late}),
    "latePointerMin": f'{min(int(row["pointer07"], 16) for row in late):04X}',
    "latePointerMax": f'{max(int(row["pointer07"], 16) for row in late):04X}',
    "finalVectorReadCounts": {key: int(rows[-1][key]) for key in
        ("nmi_lo_reads", "nmi_hi_reads", "irq_lo_reads", "irq_hi_reads")},
}
print("PASS completed FAX diagnostic; gameplay remains a separate gate")
print(json.dumps(summary, indent=2))
