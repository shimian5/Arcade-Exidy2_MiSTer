#!/usr/bin/env python3
"""Compare paired MAME Exidy runs without relying on PNG container metadata."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def normalized_text_digest(path: Path) -> str:
    raw = path.read_bytes()
    if raw.startswith(b"\xff\xfe"):
        value = raw.decode("utf-16")
    elif raw.startswith(b"\xfe\xff"):
        value = raw.decode("utf-16")
    else:
        value = raw.decode("utf-8-sig")
    normalized = "\n".join(line.rstrip() for line in value.replace("\r\n", "\n").replace("\r", "\n").split("\n"))
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run_a", type=Path)
    ap.add_argument("run_b", type=Path)
    args = ap.parse_args()
    a, b = args.run_a.resolve(), args.run_b.resolve()
    ma = json.loads((a / "run-manifest.json").read_text(encoding="utf-8-sig"))
    mb = json.loads((b / "run-manifest.json").read_text(encoding="utf-8-sig"))
    if ma.get("validated") is not True or mb.get("validated") is not True:
        raise SystemExit("FAIL: both runs must pass validate_capture.py first")
    if ma["set"] != mb["set"]:
        raise SystemExit("FAIL: cannot compare different sets")
    for key in ("mameExeSha256", "romZipSha256", "luaScriptSha256", "pinnedExidySourceSha256", "input", "captureSettings"):
        if key not in ma or key not in mb:
            raise SystemExit(f"FAIL: required run metadata missing: {key}")
        if ma[key] != mb[key]:
            raise SystemExit(f"FAIL: run metadata differs at {key}")
    for name in ("bus.csv", "events.log", "verifyroms.log"):
        same = (normalized_text_digest(a / name) == normalized_text_digest(b / name)) if name == "verifyroms.log" else (digest(a / name) == digest(b / name))
        if not same:
            raise SystemExit(f"FAIL: deterministic file differs: {name}")
    ia = {x["name"]: x["sha256RgbPixels"] for x in ma["snapshots"]}
    ib = {x["name"]: x["sha256RgbPixels"] for x in mb["snapshots"]}
    if ia != ib:
        raise SystemExit("FAIL: decoded snapshot pixels differ")
    print(f"PASS deterministic {ma['set']}: {len(ia)} matching RGB frames, bus.csv, events.log, and verifyroms.log")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
