#!/usr/bin/env python3
"""Validate and hash one private MAME Exidy reference capture directory."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import struct
import zlib
from pathlib import Path


def decode_png(path: Path) -> tuple[int, int, str, int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"not a PNG: {path}")
    off = 8
    width = height = bit_depth = color_type = None
    palette = b""
    compressed = bytearray()
    while off < len(data):
        length = struct.unpack_from(">I", data, off)[0]
        kind = data[off + 4 : off + 8]
        payload = data[off + 8 : off + 8 + length]
        off += length + 12
        if kind == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", payload)
            if interlace != 0:
                raise ValueError(f"interlaced PNG unsupported: {path}")
        elif kind == b"PLTE":
            palette = payload
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break
    if width is None or height is None or bit_depth not in (8, 16):
        raise ValueError(f"unsupported PNG header: {path}")
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}.get(color_type)
    if channels is None or (color_type == 3 and bit_depth != 8):
        raise ValueError(f"unsupported PNG color type/depth {color_type}/{bit_depth}: {path}")
    bpp = max(1, channels * bit_depth // 8)
    raw = zlib.decompress(compressed)
    stride = (width * channels * bit_depth + 7) // 8
    previous = bytearray(stride)
    pixels = hashlib.sha256()
    colors: set[tuple[int, int, int]] = set()
    nonzero = 0
    cursor = 0

    for _ in range(height):
        filt = raw[cursor]
        scan = bytearray(raw[cursor + 1 : cursor + 1 + stride])
        cursor += stride + 1
        for i in range(stride):
            left = scan[i - bpp] if i >= bpp else 0
            up = previous[i]
            upper_left = previous[i - bpp] if i >= bpp else 0
            if filt == 1:
                scan[i] = (scan[i] + left) & 255
            elif filt == 2:
                scan[i] = (scan[i] + up) & 255
            elif filt == 3:
                scan[i] = (scan[i] + ((left + up) // 2)) & 255
            elif filt == 4:
                p = left + up - upper_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - upper_left)
                predictor = left if pa <= pb and pa <= pc else up if pb <= pc else upper_left
                scan[i] = (scan[i] + predictor) & 255
            elif filt != 0:
                raise ValueError(f"unknown PNG filter {filt}: {path}")

        if color_type == 3:
            row_rgb = bytearray(width * 3)
            for x, idx in enumerate(scan):
                p = idx * 3
                if p + 2 >= len(palette):
                    raise ValueError(f"PNG palette index out of range: {path}")
                row_rgb[x * 3 : x * 3 + 3] = palette[p : p + 3]
        elif color_type in (2, 6):
            step = channels * (bit_depth // 8)
            row_rgb = bytearray(width * 3)
            for x in range(width):
                p = x * step
                values = scan[p : p + step]
                if bit_depth == 16:
                    rgb = tuple(values[c * 2] for c in range(3))
                else:
                    rgb = tuple(values[:3])
                row_rgb[x * 3 : x * 3 + 3] = bytes(rgb)
        else:
            # Grayscale forms are expanded to RGB for content comparison.
            row_rgb = bytearray(width * 3)
            step = channels * (bit_depth // 8)
            for x in range(width):
                p = x * step
                value = scan[p] if bit_depth == 8 else scan[p]
                row_rgb[x * 3 : x * 3 + 3] = bytes((value, value, value))

        pixels.update(row_rgb)
        for p in range(0, len(row_rgb), 3):
            color = (row_rgb[p], row_rgb[p + 1], row_rgb[p + 2])
            colors.add(color)
            if color != (0, 0, 0):
                nonzero += 1
        previous = scan
    return width, height, pixels.hexdigest(), len(colors), nonzero


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("run_dir", type=Path)
    args = parser.parse_args()
    root = args.run_dir.resolve()
    manifest_path = root / "run-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    events = (root / "events.log").read_text(encoding="utf-8")
    if "complete frame=" not in events:
        raise SystemExit("FAIL: completion marker missing")
    if "ERROR" in events:
        raise SystemExit("FAIL: ERROR marker in events.log")
    if int(manifest["mameExitCode"]) != 0 or int(manifest["verifyRomExitCode"]) != 0:
        raise SystemExit("FAIL: MAME or ROM verification exit code is nonzero")

    images = []
    for path in sorted(root.glob("*.png")):
        width, height, pixel_hash, colors, nonblack_pixels = decode_png(path)
        if (width, height) != (256, 256):
            raise SystemExit(f"FAIL: {path.name} dimensions {width}x{height}, expected 256x256")
        if colors < 3 or nonblack_pixels < 512:
            raise SystemExit(f"FAIL: {path.name} has weak content: colors={colors}, nonblack_pixels={nonblack_pixels}")
        images.append({
            "name": path.name,
            "sha256File": sha256(path),
            "sha256RgbPixels": pixel_hash,
            "width": width,
            "height": height,
            "distinctRgbColors": colors,
            "nonblackPixels": nonblack_pixels,
        })
    if not images:
        raise SystemExit("FAIL: no PNG snapshots were produced")

    files = {}
    for name in ("events.log", "bus.csv", "verifyroms.log", "mame.log"):
        path = root / name
        if not path.exists():
            raise SystemExit(f"FAIL: required output missing: {name}")
        files[name] = {"sha256": sha256(path), "bytes": path.stat().st_size}
    bus_rows = list(csv.DictReader((root / "bus.csv").open(newline="", encoding="utf-8")))
    if not bus_rows:
        raise SystemExit("FAIL: no bus events captured")
    max_frame = 900 if manifest["set"] == "venture" else 3600
    late_threshold = max_frame - 600
    late_rows = [row for row in bus_rows if int(row["frame"]) >= late_threshold]
    if not late_rows:
        raise SystemExit(f"FAIL: no bus events at/after frame {late_threshold}; tap did not span the run")
    manifest["validated"] = True
    manifest["snapshotCount"] = len(images)
    manifest["busEventCount"] = len(bus_rows)
    manifest["busLastFrame"] = max(int(row["frame"]) for row in bus_rows)
    manifest["busEventsAtOrAfterFrame"] = late_threshold
    manifest["lateBusEventCount"] = len(late_rows)
    manifest["snapshots"] = images
    manifest["outputFiles"] = files
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"PASS {manifest['set']} {manifest['run']}: {len(images)} valid 256x256 snapshots; {len(bus_rows)} bus events through frame {manifest['busLastFrame']}; {len(late_rows)} late-run events")
    for image in images:
        print(f"{image['name']} colors={image['distinctRgbColors']} nonblack_pixels={image['nonblackPixels']} rgb_sha256={image['sha256RgbPixels']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
