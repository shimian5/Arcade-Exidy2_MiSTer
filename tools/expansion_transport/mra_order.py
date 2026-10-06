"""Inspect MiSTer MRA ROM transfer order from XML document order."""
import argparse
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path


def inspect_mra(path: Path) -> dict:
    root = ET.parse(path).getroot()
    rows = []
    for ordinal, rom in enumerate(root.iter("rom")):
        index = int(rom.get("index", "0"), 0)
        first_payload = None
        for part in rom.iter("part"):
            text = part.text or ""
            tokens = re.findall(r"(?<![0-9A-Fa-f])[0-9A-Fa-f]{1,2}(?![0-9A-Fa-f])", text)
            if tokens:
                first_payload = bytes(int(token, 16) for token in tokens)
                break
        rows.append({"ordinal": ordinal, "index": index, "address": int(rom.get("address", "0"), 0),
                     "firstInlinePayloadHex": first_payload[:8].hex() if first_payload else None})
    return {"path": str(path), "name": root.findtext("name"), "romNodes": rows,
            "transferOrder": [row["index"] for row in rows]}


def inspect_many(paths):
    rows = [inspect_mra(path) for path in paths]
    for row in rows:
        order = row["transferOrder"]
        if not order or order[0] != 0 or order != [0, 1, 2, 3]:
            raise AssertionError(f"Existing legacy MRA order changed/unexpected: {row['path']} {order}")
        if any(node["address"] != 0 for node in row["romNodes"]):
            raise AssertionError(f"Existing MRA uses direct-memory address mode: {row['path']}")
        if row["romNodes"][1]["firstInlinePayloadHex"] not in ("01", "02", "10", "30"):
            raise AssertionError(f"Unexpected legacy PCB byte in {row['path']}")
        if any(index in (5, 6, 7) for index in order):
            raise AssertionError(f"Legacy MRA unexpectedly uses extension index: {row['path']}")
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*", type=Path, help="MRA files; default is releases/*.mra")
    ap.add_argument("--output", type=Path)
    args = ap.parse_args()
    paths = args.paths or sorted(Path("releases").glob("*.mra"))
    report = {"scope": "existing MRA XML sequence only; no real extended MRA exists",
              "transferRule": "mra_loader.cpp calls rom_finish when each </rom> closes; transfer order follows XML document order",
              "mrAs": inspect_many(paths)}
    encoded = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
    print(encoded, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
