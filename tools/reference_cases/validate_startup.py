#!/usr/bin/env python3
"""Validate a bounded Venture startup/gameplay capture and freeze its hashes."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate_capture import decode_png, sha256


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run", type=Path)
    args = ap.parse_args()
    root = args.run.resolve()
    manifest_path = root / "run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    if manifest.get("set") != "venture" or manifest.get("mameExitCode") != 0 or manifest.get("verifyRomExitCode") != 0:
        raise SystemExit("FAIL: Venture MAME/ROM verification metadata is incomplete or failed")
    events = (root / "events.log").read_text(encoding="utf-8")
    if "ERROR" in events or "complete frame=3600" not in events:
        raise SystemExit("FAIL: capture reported an error or did not reach frame 3600")
    rows = list(csv.DictReader((root / "bus.csv").open(newline="", encoding="utf-8")))
    if not rows:
        raise SystemExit("FAIL: no actual CPU bus events captured")
    snapshots = []
    for path in sorted(root.glob("venture_startup_*.png")):
        width, height, rgb_hash, colors, nonblack = decode_png(path)
        if (width, height) != (256, 256):
            raise SystemExit(f"FAIL: {path.name} is {width}x{height}, expected 256x256")
        snapshots.append({"name": path.name, "sha256File": sha256(path), "sha256RgbPixels": rgb_hash,
                          "width": width, "height": height, "distinctRgbColors": colors,
                          "nonblackPixels": nonblack})
    active = bool(manifest.get("inputProbe"))
    mode = manifest.get("inputMode", "zero-input")
    expected_snapshot_count = 13 if active else 6
    if len(snapshots) != expected_snapshot_count:
        raise SystemExit(f"FAIL: expected {expected_snapshot_count} scheduled images, found {len(snapshots)}")
    outputs = {}
    for name in ("events.log", "bus.csv", "ram_writes_early.csv", "verifyroms.log", "mame.log", "venture_startup.lua"):
        p = root / name
        if p.exists():
            outputs[name] = {"sha256": sha256(p), "bytes": p.stat().st_size}
    bus_late = [r for r in rows if int(r["frame"]) >= 3000]
    if not bus_late:
        raise SystemExit("FAIL: no actual bus events after frame 3000")

    evidence = {"mode": "post-startup coin/start/right/fire" if active else "zero-input startup transition",
                "busEventCount": len(rows), "busLastFrame": max(int(r["frame"]) for r in rows),
                "lateBusEventCount": len(bus_late)}
    if active:
        for token in ("input frame=2100 field=Coin 1 active=true", "input frame=2160 field=1 Player Start active=true",
                      "input frame=2400 field=P1 Right active=true"):
            if token not in events:
                raise SystemExit(f"FAIL: scheduled input missing: {token}")
        fire = mode == "right-and-fire"
        if fire and "input frame=2400 field=P1 Button 1 active=true" not in events:
            raise SystemExit("FAIL: right-and-fire case did not assert Button 1")
        if not fire and "input frame=2400 field=P1 Button 1 active=true" in events:
            raise SystemExit("FAIL: right-only control unexpectedly asserted Button 1")
        expected_in0 = "EB" if fire else "FB"
        if not re.search(rf"sample frame=2460 .* IN0={expected_in0} ", events):
            raise SystemExit(f"FAIL: CPU-side IN0 sample did not show expected input value {expected_in0}")
        xs = {r["data"] for r in rows if r["kind"] == "W" and r["address"] == "5000" and 2400 <= int(r["frame"]) <= 2519}
        projectile_xs = {r["data"] for r in rows if r["kind"] == "W" and r["address"] == "5080" and 2400 <= int(r["frame"]) <= 2519}
        acknowledgements = sum(r["kind"] == "R" and r["address"] == "5103" for r in rows)
        if len(xs) < 10 or len(projectile_xs) < 10 or acknowledgements < 100:
            raise SystemExit("FAIL: no horizontal sprite/second-object movement or active gameplay IRQ evidence")
        gameplay_images = [s for s in snapshots if int(re.search(r"_(\d+)\.png$", s["name"]).group(1)) >= 2400]
        if not gameplay_images or any(s["distinctRgbColors"] < 3 or s["nonblackPixels"] < 512 for s in gameplay_images):
            raise SystemExit("FAIL: post-input snapshots do not show nontrivial gameplay content")
        evidence.update({"inputMode": mode, "rightButtonCpuPortValue": expected_in0, "sprite1XDistinctDataDuringInput": len(xs),
                         "sprite2XDistinctDataDuringInput": len(projectile_xs),
                         "irqAcknowledgeReadCount": acknowledgements,
                         "piaReadCount": sum(r["kind"] == "R" and 0x5200 <= int(r["address"], 16) <= 0x520f for r in rows),
                         "snapshotFrames": [2400, 2520, 2700, 3000, 3600]})
        manifest["validated"] = True
        manifest["captureStatus"] = "gameplay_horizontal_motion_reference" if fire else "gameplay_right_only_control"
    else:
        if "sample frame=1800" not in events:
            raise SystemExit("FAIL: startup diagnostic lacks frame 1800 sample")
        manifest["validated"] = False
        manifest["captureStatus"] = "startup_transition_observed_no_input"
        evidence["firstIrqAcknowledgeFrame"] = min(int(r["frame"]) for r in rows if r["kind"] == "R" and r["address"] == "5103") if any(r["kind"] == "R" and r["address"] == "5103" for r in rows) else None

    manifest["ventureEvidence"] = evidence
    manifest["snapshots"] = snapshots
    manifest["outputFiles"] = outputs
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"PASS {manifest['captureStatus']} {manifest['run']}: {len(rows)} CPU bus events; {len(snapshots)} 256x256 images; {evidence}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
