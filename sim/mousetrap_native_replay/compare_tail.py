#!/usr/bin/env python3
"""Compare a native F9-to-next-reset interval with the conditioned T80 replay.

Reports serial digit/address equality and sampled clock-level agreement. It
does not compare MC3417 internals, filtered audio, or PCM/WAV samples.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
from pathlib import Path


def native_segment(path: Path) -> list[tuple[int, int, int]]:
    ora = 0
    ddra = 0
    clock: int | None = None
    start: float | None = None
    end: float | None = None
    digits: list[tuple[int, int, int]] = []
    with path.open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            address = int(row["address"], 16)
            if row["bus"] == "audio" and row["kind"] == "W":
                offset = address & 0x1F
                if offset & 4:
                    continue
                register = offset & 3
                if register == 0:
                    ora = int(row["data"], 16)
                elif register == 1:
                    ddra = int(row["data"], 16)
                else:
                    continue
                resolved = (ora & ddra) | (~ddra & 0xFF)
                time_s = float(row["time_s"])
                if start is None and resolved == 0xF9 and register == 0:
                    start = time_s
                elif start is not None and end is None and resolved == 0xEF and register == 0 and time_s > start:
                    end = time_s
            elif row["bus"] == "z80io" and row["kind"] == "R" and (address & 0xC0) == 0x80:
                clock = (int(row["data"], 16) >> 7) & 1
            elif row["bus"] == "z80io" and row["kind"] == "W" and (address & 0x10) == 0:
                time_s = float(row["time_s"])
                if start is not None and time_s >= start and (end is None or time_s < end):
                    digits.append((address & 0xFF, int(row["data"], 16) & 1, -1 if clock is None else clock))
    if start is None or end is None:
        raise ValueError(f"could not locate F9 release/next EF in {path}")
    return digits


def replay_segment(io_path: Path, pa_path: Path) -> list[tuple[int, int, int]]:
    callbacks: list[tuple[int, int]] = []
    with pa_path.open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            callbacks.append((int(row["time_ps"]), int(row["PA"], 16)))
    start = next((t for t, value in callbacks if value == 0xF9), None)
    end = next((t for t, value in callbacks if value == 0xEF and start is not None and t > start), None)
    if start is None or end is None:
        raise ValueError(f"could not locate F9 release/next EF in {pa_path}")
    digits: list[tuple[int, int, int]] = []
    with io_path.open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            if row["kind"] != "W":
                continue
            address = int(row["address"], 16) & 0xFF
            time_ps = int(row["time_ps"])
            if (address & 0x10) == 0 and start <= time_ps < end:
                digits.append((address, int(row["data"], 16) & 1, int(row["clock"])))
    return digits


def digest(rows: list[tuple[int, int, int]]) -> str:
    payload = "".join(str(bit) for _, bit, _ in rows).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("native_bus", type=Path)
    parser.add_argument("replay_io", type=Path)
    parser.add_argument("replay_pa", type=Path)
    args = parser.parse_args()
    native = native_segment(args.native_bus)
    replay = replay_segment(args.replay_io, args.replay_pa)
    common = min(len(native), len(replay))
    prefix = 0
    while prefix < common and native[prefix][:2] == replay[prefix][:2]:
        prefix += 1
    clock_pairs = [(n[2], r[2]) for n, r in zip(native, replay) if n[2] >= 0 and r[2] >= 0]
    clock_match = sum(a == b for a, b in clock_pairs)
    port_mismatches = sum(a[0] != b[0] for a, b in zip(native, replay))
    bit_mismatches = sum(a[1] != b[1] for a, b in zip(native, replay))
    tuple_mismatches = sum(a != b for a, b in zip(native, replay))
    clock_mismatches = sum(a[2] != b[2] for a, b in zip(native, replay))
    print(f"native_digits={len(native)} replay_digits={len(replay)} ordered_equal_prefix={prefix}")
    print(f"complete_address_and_bit_equality={len(native)==len(replay) and prefix==len(native)}")
    print(f"ordinal_mismatches: address={port_mismatches} bit={bit_mismatches} tuple={tuple_mismatches} clock={clock_mismatches}")
    print(f"native_ascii_bits_sha256={digest(native)}")
    print(f"replay_ascii_bits_sha256={digest(replay)}")
    print(f"ordinal_clock_levels_compared={len(clock_pairs)} matches={clock_match}")
    if prefix < common:
        print(f"first_mismatch_index={prefix+1} native={native[prefix]} replay={replay[prefix]}")
        differing = [i for i, (n, r) in enumerate(zip(native, replay)) if n != r]
        print(f"mismatch_positions_1based={[i + 1 for i in differing[:20]]}")
        print(f"first_mismatch_tuples={[(i + 1, native[i], replay[i]) for i in differing[:20]]}")


if __name__ == "__main__":
    main()
