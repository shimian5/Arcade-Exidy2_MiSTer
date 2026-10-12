#!/usr/bin/env python3
"""Summarize passive Mouse Trap MAME voice-bus captures."""
import argparse
import csv
from collections import Counter
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("capture", type=Path, help="mousetrap_voice_bus.csv")
    args = ap.parse_args()
    counts = Counter()
    first = {bus: [] for bus in ("z80io", "audio", "main")}
    z80_writes = Counter()
    clock_reads = Counter()
    clock_state = None
    clock_changes = []
    command_reads = Counter()
    audio_writes = []
    row_count = 0
    with args.capture.open(newline="", encoding="utf-8-sig") as capture:
        for r in csv.DictReader(capture):
            row_count += 1
            kind, bus = r["kind"], r["bus"]
            counts[(kind, bus)] += 1
            if len(first[bus]) < 20:
                first[bus].append(r)
            if bus == "z80io" and kind == "W":
                address = int(r["address"], 16)
                z80_writes["digit_w candidates (A4=0)"] += (address & 0x10) == 0
                z80_writes["busy PB0 candidates (A5=0)"] += (address & 0x20) == 0
                z80_writes["both candidates"] += (address & 0x30) == 0
            if bus == "z80io" and kind == "R":
                address = int(r["address"], 16)
                if (address & 0xc0) == 0x80:  # A7 high, A6 low: CVSD clock only
                    state = (int(r["data"], 16) >> 7) & 1
                    clock_reads[state] += 1
                    if state != clock_state and len(clock_changes) < 20:
                        clock_changes.append(r)
                    clock_state = state
                elif (address & 0x80) == 0:  # A7 low: command/status bits
                    command_reads[(r["address"], r["data"])] += 1
            if bus == "audio" and kind == "W":
                audio_writes.append(r)
    print(f"rows={row_count}")
    for (kind, bus), n in sorted(counts.items()):
        print(f"{bus} {kind}: {n}")
    for bus in ("z80io", "audio", "main"):
        if not first[bus]:
            continue
        print(f"\n[{bus}] first 20 events")
        for r in first[bus]:
            print("{frame} {time_s}s {kind} pc={pc} addr={address} data={data} mask={mask}".format(**r))
    # Z80 output address decode is the native MAME handler behavior:
    # A4 low clocks CVSD digit, A5 low writes RIOT PB0 busy, A4/A5 low does both.
    print("\n[z80io write decode]")
    for label, count in z80_writes.items():
        print(f"{label}: {count}")
    print("\n[z80io clock-only reads (A7=1, A6=0)]")
    print(f"count={sum(clock_reads.values())} states={dict(clock_reads)}")
    for r in clock_changes:
        print(f"state={int(r['data'],16) >> 7} {r['time_s']}s frame={r['frame']} pc={r['pc']} addr={r['address']} data={r['data']}")
    print("\n[z80io command/status reads (A7=0)]")
    print(command_reads)
    # RIOT decode convention: register index in low address bits. Preserve raw
    # addresses because mirrors and MAME device map semantics can vary by version.
    print("\n[audio RIOT write addresses]")
    print(Counter(r["address"] for r in audio_writes))
    ora, ddra = 0, 0
    print("accepted PA callback values (ORA/DDRA resolved):")
    for r in audio_writes:
        reg = int(r["address"], 16) & 3
        value = int(r["data"], 16)
        if reg == 0:
            ora = value
        elif reg == 1:
            ddra = value
        else:
            continue
        resolved = (ora & ddra) | (~ddra & 0xff)
        print(f"{r['time_s']}s frame={r['frame']} pc={r['pc']} addr={r['address']} ORA={ora:02X} DDRA={ddra:02X} callback={resolved:02X} reset_released={(resolved & 0x10) != 0}")


if __name__ == "__main__":
    main()
