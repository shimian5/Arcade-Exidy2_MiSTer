#!/usr/bin/env python3
"""Build an exhaustive oracle from pinned MAME's base and Side Trak maps."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "simulation/reference_sources/exidy.cpp"
BITS = {
    "program_rom": 0, "character_rom": 1,
    "work_ram_read": 2, "work_ram_write": 3,
    "video_ram_read": 4, "video_ram_write": 5,
    "dip_read": 6, "in0_read": 7, "irq_read": 8, "in2_read": 9,
    "sprite1_x_write": 10, "sprite1_y_write": 11,
    "sprite2_x_write": 12, "sprite2_y_write": 13,
    "sprite_number_write": 14, "sprite_enable_write": 15,
    "color_latch_write": 16, "audio0_write": 17, "audio1_write": 18,
}


def method_body(text: str, signature: str) -> str:
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                return text[brace + 1:i]
    raise ValueError(f"unterminated method {signature}")


def declarations(body: str) -> list[dict]:
    rows = []
    for line_no, line in enumerate(body.splitlines(), 1):
        line = line.strip()
        if not line.startswith("map("):
            continue
        m = re.match(r"map\((0x[0-9a-fA-F]+),\s*(0x[0-9a-fA-F]+)\)(.*);", line)
        if not m:
            raise ValueError(f"cannot parse MAME map declaration: {line}")
        lo, hi, ops = int(m.group(1), 16), int(m.group(2), 16), m.group(3)
        mirror_match = re.search(r"\.mirror\((0x[0-9a-fA-F]+)\)", ops)
        mirror = int(mirror_match.group(1), 16) if mirror_match else 0
        rows.append({"lo": lo, "hi": hi, "mirror": mirror, "ops": ops, "line": line_no})
    return rows


def classify(row: dict) -> list[tuple[str, str]]:
    ops = row["ops"]
    result: list[tuple[str, str]] = []
    share = re.search(r'\.share\("([^"]+)"\)', ops)
    port = re.search(r'\.portr\("([^"]+)"\)', ops)
    handler = re.search(r"\.([rw])\(FUNC\([^:]+::([^)]+)\)\)", ops)
    if ".ram()" in ops:
        name = "work_ram" if row["lo"] == 0x0000 else "video_ram"
        result.extend(((name + "_read", "read"), (name + "_write", "write")))
    elif ".rom()" in ops:
        if row["lo"] == 0x4800:
            result.append(("character_rom", "read"))
        else:
            result.append(("program_rom", "read"))
    if port:
        name = {"DSW": "dip_read", "IN0": "in0_read", "IN2": "in2_read"}.get(port.group(1))
        if not name:
            raise ValueError(f"unclassified input port {port.group(1)}")
        result.append((name, "read"))
    if handler:
        direction, name = handler.groups()
        if direction == "r" and name == "exidy_interrupt_r":
            result.append(("irq_read", "read"))
        elif direction == "w" and name == "spectar_audio_1_w":
            result.append(("audio0_write", "write"))
        elif direction == "w" and name == "spectar_audio_2_w":
            result.append(("audio1_write", "write"))
        else:
            raise ValueError(f"unclassified handler {handler.group(0)}")
    if ".writeonly()" in ops:
        target = {
            "sprite1_xpos": "sprite1_x_write", "sprite1_ypos": "sprite1_y_write",
            "sprite2_xpos": "sprite2_x_write", "sprite2_ypos": "sprite2_y_write",
            "spriteno": "sprite_number_write", "sprite_enable": "sprite_enable_write",
            "color_latch": "color_latch_write",
        }.get(share.group(1) if share else "")
        if not target:
            raise ValueError(f"unclassified write-only map {ops}")
        result.append((target, "write"))
    return result


def match(row: dict, address: int) -> bool:
    effective = address & (0xFFFF ^ row["mirror"])
    return row["lo"] <= effective <= row["hi"]


def build_rows() -> tuple[list[dict], list[dict]]:
    source = SOURCE.read_text(encoding="utf-8")
    base = declarations(method_body(source, "void exidy_state::exidy_map(address_map &map)"))
    side = declarations(method_body(source, "void spectar_state::sidetrac_map(address_map &map)"))
    if len(base) != 13 or len(side) != 5:
        raise ValueError(f"unexpected source map declaration counts: base={len(base)} sidetrac={len(side)}")
    return base, side


def expected(address: int, is_read: bool, maps: list[dict]) -> tuple[int, int]:
    mask, rom_address = 0, 0
    for row in maps:
        if not match(row, address):
            continue
        for name, direction in classify(row):
            if direction == ("read" if is_read else "write"):
                mask |= 1 << BITS[name]
                if name in ("program_rom", "character_rom"):
                    if row["lo"] == 0xFF00:
                        # MAME's explicit ROM-region offset on the vector mirror.
                        rom_address = 0x3F00 + (address & 0xFF)
                    else:
                        rom_address = address
    return mask, rom_address


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--vectors", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    base, side = build_rows()
    maps = base + side
    args.vectors.parent.mkdir(parents=True, exist_ok=True)
    mapped = {"read": 0, "write": 0}
    with args.vectors.open("w", encoding="ascii", newline="\n") as out:
        for is_read in (1, 0):
            for address in range(0x10000):
                mask, rom_address = expected(address, bool(is_read), maps)
                if mask:
                    mapped["read" if is_read else "write"] += 1
                out.write(f"{address:04x} {is_read:d} {1-is_read:d} {mask:05x} {rom_address:04x}\n")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    report = {
        "source": "simulation/reference_sources/exidy.cpp",
        "sourceSha256": source_hash,
        "mapDeclarations": [{"lo": f"{r['lo']:04x}", "hi": f"{r['hi']:04x}", "mirror": f"{r['mirror']:04x}", "ops": r["ops"].strip()} for r in maps],
        "profileProposal": "0x00 (matches current legacy B/W decode; not hardware validated)",
        "profileNegativeControl": "all selects zero for every profile other than 0x00",
        "exhaustiveCases": 0x10000 * 2,
        "mappedReadAddressCount": mapped["read"],
        "mappedWriteAddressCount": mapped["write"],
        "mirrorPolicy": "MAME mirror mask bits are ignored; vector ROM region maps ff00-ffff to maincpu 3f00-3fff",
        "romBytes": "not read, generated, or committed by this oracle",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
