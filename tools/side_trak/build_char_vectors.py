#!/usr/bin/env python3
"""Verify Side Trak character ROM and build ignored MAME-derived pixel vectors."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MAME_SOURCE = ROOT / "simulation/reference_sources/exidy.cpp"
CHAR_NAME = "stl9c-1"
CHAR_BYTES = 0x400
MAME_WINDOW_BYTES = 0x800
EXPECTED_CRC = 0x08710A84


def method_body(text: str, signature: str) -> str:
    start = text.index(signature)
    brace = text.index("{", start)
    depth = 0
    for i in range(brace, len(text)):
        if text[i] == "{": depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0: return text[brace + 1:i]
    raise ValueError(f"unterminated MAME method {signature}")


def source_expectations(source: str) -> list[int]:
    init = method_body(source, "void spectar_state::init_sidetrac()")
    latch = {}
    for match in re.finditer(r"m_color_latch\[(\d+)\]\s*=\s*(0x[0-9a-fA-F]+)", init):
        latch[int(match.group(1))] = int(match.group(2), 16)
    if latch != {2: 0xF8, 1: 0xDC, 0: 0xB8}:
        raise ValueError(f"unexpected Side Trak MAME color latch initialization: {latch}")

    set_colors = method_body(source, "void exidy_state::set_colors()")
    pen_rows = [(int(a), int(b)) for a, b in re.findall(r"set_1_color\((\d+),\s*(\d+)\)", set_colors)]
    if pen_rows != [(0, 0), (1, 7), (2, 0), (3, 6), (4, 4), (5, 3), (6, 2), (7, 1)]:
        raise ValueError(f"unexpected MAME indexed palette wiring: {pen_rows}")
    color_method = method_body(source, "inline void exidy_state::set_1_color(int index, int which)")
    if not all(s in color_method for s in (
        "pal1bit(m_color_latch[2] >> which)",
        "pal1bit(m_color_latch[1] >> which)",
        "pal1bit(m_color_latch[0] >> which)",
    )):
        raise ValueError("MAME set_1_color channel order changed")
    rgb = []
    for _, which in pen_rows:
        red = (latch[2] >> which) & 1
        green = (latch[1] >> which) & 1
        blue = (latch[0] >> which) & 1
        rgb.append((red << 2) | (green << 1) | blue)

    draw = method_body(source, "void exidy_state::draw_background()")
    required = (
        "uint8_t const code = m_videoram[offs]",
        "uint8_t data = cram[(code << 3) | cy]",
        "(data & 0x80) ? on_pen_1 : off_pen",
        "data <<= 1",
        "4 + ((code >> 6) & 0x03)",
    )
    if not all(s in draw for s in required):
        raise ValueError("pinned MAME 1bpp glyph extraction or color selection changed")
    return rgb


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom-zip", type=Path, required=True)
    ap.add_argument("--mame-window", type=Path, required=True)
    ap.add_argument("--out-dir", type=Path, required=True)
    args = ap.parse_args()

    with zipfile.ZipFile(args.rom_zip) as zf:
        names = {name.lower(): name for name in zf.namelist()}
        member = next((v for k, v in names.items() if Path(k).name.lower() == CHAR_NAME), None)
        if member is None: raise ValueError(f"{CHAR_NAME} missing from ROM archive")
        rom = zf.read(member)
    crc = zlib.crc32(rom) & 0xFFFFFFFF
    if len(rom) != CHAR_BYTES or crc != EXPECTED_CRC:
        raise ValueError(f"character PROM mismatch: length={len(rom):#x} CRC={crc:08x}")

    mame_window = args.mame_window.read_bytes()
    if len(mame_window) != MAME_WINDOW_BYTES:
        raise ValueError(f"MAME probe returned {len(mame_window)} bytes, expected {MAME_WINDOW_BYTES}")
    if mame_window[:CHAR_BYTES] != rom:
        raise ValueError("MAME mapped character ROM does not match verified archive member")
    tail = mame_window[CHAR_BYTES:]
    if any(tail):
        raise ValueError(f"MAME's unpopulated upper character half is not zero-filled; observed {sorted(set(tail))}")

    source = MAME_SOURCE.read_text(encoding="utf-8")
    rgb_table = source_expectations(source)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    (args.out_dir / "char_image.hex").write_text("".join(f"{v:02x}\n" for v in rom), encoding="ascii")
    with (args.out_dir / "glyph_vectors.txt").open("w", encoding="ascii", newline="\n") as vectors:
        for code in range(256):
            for row in range(8):
                byte = mame_window[(code << 3) | row]
                for x in range(8):
                    on = (byte >> (7 - x)) & 1
                    pen = (4 + ((code >> 6) & 0x03)) if on else 0
                    vectors.write(f"{code:02x} {row:x} {x:x} {byte:02x} {on:x} {pen:x} {rgb_table[pen]:x}\n")
    (args.out_dir / "palette_vectors.txt").write_text(
        "".join(f"{pen:x} {rgb:x}\n" for pen, rgb in enumerate(rgb_table)), encoding="ascii")
    report = {
        "source": "simulation/reference_sources/exidy.cpp",
        "sourceSha256": hashlib.sha256(source.encode("utf-8")).hexdigest(),
        "romMember": member,
        "romLength": len(rom),
        "romCrc32": f"{crc:08x}",
        "romSha256": hashlib.sha256(rom).hexdigest(),
        "mameMappedWindowLength": len(mame_window),
        "mameMappedWindowSha256": hashlib.sha256(mame_window).hexdigest(),
        "mappedWindowUpperHalfFill": "00, independently observed through MAME program-space read at $4c00-$4fff",
        "glyphCoverage": "256 character codes x 8 rows x 8 columns, MSB-first pixels",
        "paletteRGBByPen": [f"{rgb:03b}" for rgb in rgb_table],
        "expectedCharacters": "ROM contains codes 0-127; codes 128-255 render blank because MAME mapped region tail is zero",
        "romBytesOrDecodedImages": "derived vectors/images are confined to ignored simulation/ output",
    }
    (args.out_dir / "source-audit.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
