#!/usr/bin/env python3
"""Compare passive native MAME voice writes with actual-ROM T80 simulation writes.

The tool compares ordered bus events and their cadence. It deliberately makes
no PCM/WAV equality claim: the native and production renderer/filter models are
different paths, and a byte-stream match is not an audio identity claim.
"""

from __future__ import annotations

import argparse
import csv
import json
import statistics
from pathlib import Path
from typing import Any


def load_native(path: Path) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    digits: list[dict[str, Any]] = []
    callbacks: list[dict[str, Any]] = []
    ora = 0
    ddra = 0
    clock_state: int | None = None
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        needed = {"kind", "bus", "frame", "time_s", "pc", "address", "data"}
        if not needed.issubset(reader.fieldnames or []):
            raise ValueError(f"native capture lacks columns: {sorted(needed - set(reader.fieldnames or []))}")
        for row_num, row in enumerate(reader, 2):
            address = int(row["address"], 16)
            if row["bus"] == "z80io" and row["kind"] == "R" and (address & 0xC0) == 0x80:
                clock_state = (int(row["data"], 16) >> 7) & 1
            if row["bus"] == "z80io" and row["kind"] == "W":
                address &= 0xFF
                if (address & 0x10) == 0:  # MAME voiceio_w digit strobe
                    digits.append({
                        "port": address,
                        "bit": int(row["data"], 16) & 1,
                        "time_ps": round(float(row["time_s"]) * 1_000_000_000_000),
                        "frame": int(row["frame"]),
                        "pc": row["pc"],
                        "row": row_num,
                        "clock": clock_state,
                    })
            elif row["bus"] == "audio" and row["kind"] == "W":
                address = int(row["address"], 16)
                # The RIOT registers are mirrored; A0/A1 select the register
                # while higher mirrored address bits are not part of decode.
                register_offset = address & 0x1F
                # A2 selects the timer/edge registers. A3/A4 are ignored for
                # PA/DDR selection, creating aliases at 08/09/10/11/18/19.
                if register_offset & 0x04:
                    continue
                register = register_offset & 0x03
                value = int(row["data"], 16) & 0xFF
                if register == 0:
                    ora = value
                elif register == 1:
                    ddra = value
                else:
                    continue
                resolved = (ora & ddra) | (~ddra & 0xFF)
                callbacks.append({
                    "time_ps": round(float(row["time_s"]) * 1_000_000_000_000),
                    "frame": int(row["frame"]),
                    "pc": row["pc"],
                    "address": address,
                    "register": "ORA" if register == 0 else "DDRA",
                    "value": value,
                    "ora": ora,
                    "ddra": ddra,
                    "resolved_pa": resolved,
                    "speech_cpu_released": bool(resolved & 0x10),
                })
    return digits, callbacks


def load_production(path: Path) -> list[dict[str, Any]]:
    digits: list[dict[str, Any]] = []
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        needed = {"time_ps", "kind", "address", "data"}
        if not needed.issubset(reader.fieldnames or []):
            raise ValueError(f"production I/O trace lacks columns: {sorted(needed - set(reader.fieldnames or []))}")
        for row_num, row in enumerate(reader, 2):
            if row["kind"] != "W":
                continue
            address = int(row["address"], 16) & 0xFF
            if (address & 0x10) != 0:  # A4 high is not a digit write
                continue
            digits.append({
                "port": address,
                "bit": int(row["data"], 16) & 1,
                "time_ps": int(row["time_ps"]),
                "row": row_num,
                "clock": int(row["clock"]) if "clock" in row and row["clock"] != "" else None,
            })
    return digits


def cadence_stats(native: list[dict[str, Any]], production: list[dict[str, Any]], prefix: int) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for name, rows in (("native", native), ("production", production)):
        dts = [b["time_ps"] - a["time_ps"] for a, b in zip(rows, rows[1:])]
        result[name] = {
            "interval_count": len(dts),
            "median_us": round(statistics.median(dts) / 1_000_000, 6) if dts else None,
            "min_us": round(min(dts) / 1_000_000, 6) if dts else None,
            "max_us": round(max(dts) / 1_000_000, 6) if dts else None,
        }
    aligned = min(max(prefix - 1, 0), len(native) - 1, len(production) - 1)
    errors_us = [
        ((production[i + 1]["time_ps"] - production[i]["time_ps"])
         - (native[i + 1]["time_ps"] - native[i]["time_ps"])) / 1_000_000
        for i in range(aligned)
    ]
    result["aligned_prefix"] = {
        "intervals_compared": len(errors_us),
        "exact_interval_matches": sum(error == 0 for error in errors_us),
        "within_0_1us": sum(abs(error) <= 0.1 for error in errors_us),
        "median_signed_delta_us": round(statistics.median(errors_us), 6) if errors_us else None,
        "max_abs_delta_us": round(max(map(abs, errors_us)), 6) if errors_us else None,
    }
    return result


def compare(native: list[dict[str, Any]], production: list[dict[str, Any]]) -> dict[str, Any]:
    common = min(len(native), len(production))
    first_mismatch = None
    for i in range(common):
        if (native[i]["port"], native[i]["bit"]) != (production[i]["port"], production[i]["bit"]):
            first_mismatch = {
                "index_zero_based": i,
                "index_one_based": i + 1,
                "native": {k: native[i][k] for k in ("port", "bit", "time_ps", "frame", "pc", "row") if k in native[i]},
                "production": {k: production[i][k] for k in ("port", "bit", "time_ps", "row") if k in production[i]},
            }
            break
    prefix = first_mismatch["index_zero_based"] if first_mismatch else common
    phase_pairs = [
        (i, native[i].get("clock"), production[i].get("clock"))
        for i in range(prefix)
        if native[i].get("clock") is not None and production[i].get("clock") is not None
    ]
    phase_mismatches = [(i, n, p) for i, n, p in phase_pairs if n != p]
    return {
        "native_digit_writes": len(native),
        "production_digit_writes": len(production),
        "ordered_matching_prefix": prefix,
        "first_ordered_mismatch": first_mismatch,
        "complete_stream_equality": len(native) == len(production) and prefix == len(native),
        "native_uncompared_tail": max(len(native) - prefix, 0),
        "production_uncompared_tail": max(len(production) - prefix, 0),
        "clock_phase": {
            "compared_events": len(phase_pairs),
            "matching_levels": len(phase_pairs) - len(phase_mismatches),
            "mismatched_levels": len(phase_mismatches),
            "first_mismatch": ({"index_zero_based": phase_mismatches[0][0], "native": phase_mismatches[0][1], "production": phase_mismatches[0][2]} if phase_mismatches else None),
            "phase_basis": "native last captured BF clock-only read state at each digit write; production clock column at its digit write",
        },
        "first_digit_time_us": {
            "native": round(native[0]["time_ps"] / 1_000_000, 6) if native else None,
            "production": round(production[0]["time_ps"] / 1_000_000, 6) if production else None,
        },
        "cadence": cadence_stats(native, production, prefix),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("native_capture", type=Path)
    parser.add_argument("production_io", type=Path)
    parser.add_argument("run_manifest", type=Path)
    parser.add_argument("output_json", type=Path)
    args = parser.parse_args()

    native, callbacks = load_native(args.native_capture)
    production = load_production(args.production_io)
    manifest = json.loads(args.run_manifest.read_text(encoding="utf-8-sig"))
    if not native or not production:
        raise SystemExit("Both native and production digit traces must contain at least one digit write")
    result = {
        "scope": "ordered native MAME digit writes versus actual-ROM T80 I/O write trace",
        "native_capture": str(args.native_capture),
        "production_io_trace": str(args.production_io),
        "production_command_byte": int(manifest["command"]) & 0xFF,
        "production_zero_initialized_register_banks": manifest.get("zero_initialized_register_banks"),
        "production_simulation_scope": manifest.get("scope"),
        "digit_stream": compare(native, production),
        "native_riot_pa_callbacks": callbacks,
        "native_callback_count": len(callbacks),
        "native_final_pa_callback": callbacks[-1]["resolved_pa"] if callbacks else None,
        "native_pa4_release_transitions": sum(c["speech_cpu_released"] and (i == 0 or not callbacks[i - 1]["speech_cpu_released"]) for i, c in enumerate(callbacks)),
        "production_command_matches_final_native_pa": bool(callbacks) and ((int(manifest["command"]) & 0xFF) == callbacks[-1]["resolved_pa"]),
        "phrase_identity_evidence": "unclassified: this tool reports observed callbacks and ordered digits; phrase names and genuine gameplay require separate evidence",
        "pcm_policy": "byte/digit ordering and cadence only; no exact PCM/WAV equality is asserted across different renderer/filter paths",
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    stream = result["digit_stream"]
    print(f"native digit writes={stream['native_digit_writes']}")
    print(f"production digit writes={stream['production_digit_writes']}")
    print(f"ordered matching prefix={stream['ordered_matching_prefix']}; complete equality={stream['complete_stream_equality']}")
    print(f"native final PA callback={result['native_final_pa_callback']:#04x}; production command={result['production_command_byte']:#04x}; match={result['production_command_matches_final_native_pa']}")
    print(f"report={args.output_json}")


if __name__ == "__main__":
    main()
