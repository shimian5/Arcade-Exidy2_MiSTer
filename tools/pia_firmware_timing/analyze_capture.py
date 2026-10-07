#!/usr/bin/env python3
"""Summarize passive Exidy MAME PIA bus captures without changing the traces."""

from __future__ import annotations

import argparse
import bisect
import csv
import hashlib
import json
import math
import statistics
from collections import Counter
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def percentile_floor(values: list[float], p: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[math.floor((len(ordered) - 1) * p)]


def stats(values: list[float], unit_scale: float) -> dict[str, float | int | None]:
    if not values:
        return {"count": 0, "min": None, "median": None, "p95_floor_index": None, "max": None}
    return {
        "count": len(values),
        "min": min(values) * unit_scale,
        "median": statistics.median(values) * unit_scale,
        "p95_floor_index": percentile_floor(values, 0.95) * unit_scale,  # type: ignore[operator]
        "max": max(values) * unit_scale,
    }


def load_manifest(run_dir: Path) -> dict[str, Any]:
    path = run_dir / "manifest.json"
    return json.loads(path.read_text(encoding="utf-8-sig"))


def analyze_game(run_dir: Path, set_name: str) -> dict[str, Any]:
    trace_path = run_dir / set_name / "pia-bus.csv"
    rows: list[dict[str, Any]] = []
    counts: Counter[str] = Counter()
    # These are the register values that qualify each PIA byte access.
    ctrl: dict[str, dict[str, int | None]] = {
        "main": {"CRA": None, "CRB": None},
        "audio": {"CRA": None, "CRB": None},
    }
    ddr: dict[str, dict[str, int | None]] = {
        "main": {"DDRA": None, "DDRB": None},
        "audio": {"DDRA": None, "DDRB": None},
    }
    status_flag_reads: Counter[str] = Counter()

    with trace_path.open("r", newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        expected = {"cpu", "op", "frame", "time_s", "address", "reg", "kind", "data", "mask", "pc", "crA", "crB"}
        if not reader.fieldnames or not expected.issubset(reader.fieldnames):
            raise ValueError(f"unexpected PIA CSV header in {trace_path}: {reader.fieldnames}")
        for row_index, raw in enumerate(reader):
            cpu = raw["cpu"]
            if cpu not in ctrl:
                raise ValueError(f"unknown CPU label {cpu!r} at {trace_path}:{row_index + 2}")
            op = raw["op"]
            kind = raw["kind"]
            value = int(raw["data"], 16)
            event = {
                "row": row_index,
                "cpu": cpu,
                "op": op,
                "time": float(raw["time_s"]),
                "frame": int(raw["frame"]),
                "address": int(raw["address"], 16),
                "kind": kind,
                "data": value,
                "pc": int(raw["pc"], 16),
                "ddra": ddr[cpu]["DDRA"],
                "ddrb": ddr[cpu]["DDRB"],
                "cra": ctrl[cpu]["CRA"],
                "crb": ctrl[cpu]["CRB"],
            }
            counts[f"{cpu}_{op}_{kind}"] += 1
            if op == "W" and kind in ("CRA", "CRB"):
                ctrl[cpu][kind] = value & 0x3F
            elif op == "W" and kind in ("DDRA", "DDRB"):
                ddr[cpu][kind] = value
            elif op == "R" and kind in ("CRA", "CRB") and (value & 0x80):
                status_flag_reads[f"{cpu}_{kind}_bit7"] += 1
            # Save state after updates too, so a data-register write carries
            # the DDR/control setting that applies to that access.
            event["ddra"] = ddr[cpu]["DDRA"]
            event["ddrb"] = ddr[cpu]["DDRB"]
            event["cra"] = ctrl[cpu]["CRA"]
            event["crb"] = ctrl[cpu]["CRB"]
            rows.append(event)

    audio_pb_writes = [
        row for row in rows
        if row["cpu"] == "audio" and row["op"] == "W" and row["kind"] == "PB_DATA"
    ]
    main_pa_reads = [
        row for row in rows
        if row["cpu"] == "main" and row["op"] == "R" and row["kind"] == "PA_DATA"
    ]
    # The raw file order resolves same-timestamp bus accesses, which can occur
    # when both CPUs are scheduled at the same emulation instant.
    pa_keys = [(row["time"], row["row"]) for row in main_pa_reads]
    pb_keys = [(row["time"], row["row"]) for row in audio_pb_writes]

    qualified_writes = 0
    unqualified_writes = 0
    read_before_overwrite = 0
    matching = 0
    mismatching = 0
    overwritten_before_read = 0
    no_read_until_capture_end = 0
    unqualified_first_read = 0
    latencies: list[float] = []
    output_intervals: list[float] = []
    examples: list[dict[str, Any]] = []

    for index, write in enumerate(audio_pb_writes):
        # The output byte only represents a complete driven source byte when
        # PB is selected and all source PB pins are configured as outputs.
        write_qualified = write["crb"] is not None and (write["crb"] & 0x04) != 0 and write["ddrb"] == 0xFF
        if not write_qualified:
            unqualified_writes += 1
            continue
        qualified_writes += 1

        write_time = write["time"]
        write_key = (write["time"], write["row"])
        next_write_key = pb_keys[index + 1] if index + 1 < len(pb_keys) else None
        if next_write_key is not None:
            output_intervals.append(next_write_key[0] - write_time)

        read_index = bisect.bisect_left(pa_keys, write_key)
        has_read = read_index < len(main_pa_reads)
        before_next_write = has_read and (
            next_write_key is None or pa_keys[read_index] < next_write_key
        )
        if not before_next_write:
            if next_write_key is None:
                no_read_until_capture_end += 1
            else:
                overwritten_before_read += 1
            continue

        read_before_overwrite += 1
        read = main_pa_reads[read_index]
        read_qualified = read["cra"] is not None and (read["cra"] & 0x04) != 0 and read["ddra"] == 0x00
        if not read_qualified:
            unqualified_first_read += 1
            continue

        expected_byte = write["data"] & write["ddrb"]
        observed_byte = read["data"]
        latency = read["time"] - write_time
        if observed_byte == expected_byte:
            matching += 1
            latencies.append(latency)
        else:
            mismatching += 1
            if len(examples) < 12:
                examples.append({
                    "writeFrame": write["frame"],
                    "writeTimeSeconds": write_time,
                    "writeAddress": f"0x{write['address']:04X}",
                    "writePc": f"0x{write['pc']:04X}",
                    "audioDdrb": f"0x{write['ddrb']:02X}",
                    "writtenData": f"0x{write['data']:02X}",
                    "readFrame": read["frame"],
                    "readTimeSeconds": read["time"],
                    "readAddress": f"0x{read['address']:04X}",
                    "readPc": f"0x{read['pc']:04X}",
                    "mainDdra": f"0x{read['ddra']:02X}",
                    "readData": f"0x{observed_byte:02X}",
                    "latencyUs": latency * 1_000_000,
                })

    return {
        "set": set_name,
        "tracePath": str(trace_path),
        "traceSha256": sha256(trace_path),
        "traceRows": len(rows),
        "busEventCounts": dict(sorted(counts.items())),
        "controlStatusBit7Reads": dict(sorted(status_flag_reads.items())),
        "audioPbDataWrites": len(audio_pb_writes),
        "mainPaDataReads": len(main_pa_reads),
        "ddrQualified": {
            "fullByteWrites": qualified_writes,
            "writesNotFullyDrivenOrNotSelected": unqualified_writes,
            "fullByteMainPaReads": sum(
                1 for row in main_pa_reads
                if row["cra"] is not None and (row["cra"] & 0x04) != 0 and row["ddra"] == 0x00
            ),
        },
        "firstReadBeforeNextPbWrite": read_before_overwrite,
        "matchingFirstReads": matching,
        "mismatchingFirstReads": mismatching,
        "unqualifiedFirstReads": unqualified_first_read,
        "writesOverwrittenBeforeRead": overwritten_before_read,
        "finalWritesWithNoReadBeforeCaptureEnd": no_read_until_capture_end,
        "matchingReadLatencyMicroseconds": stats(latencies, 1_000_000),
        "outputWriteSpacingMilliseconds": stats(output_intervals, 1_000),
        "firstMismatchExamples": examples,
    }


def comparison(current: dict[str, Any], other: dict[str, Any]) -> dict[str, Any]:
    fields = (
        "mameVersion", "mameSha256", "pinnedSourceCommit", "exidyCppSha256",
        "exidySoundCppSha256", "seconds", "inputs", "romRoot",
    )
    return {
        "runs": [other.get("run"), current.get("run")],
        "sameRunMetadata": {field: other.get(field) == current.get(field) for field in fields},
        "sameMetadataFields": [field for field in fields if other.get(field) == current.get(field)],
        "differentMetadataFields": [field for field in fields if other.get(field) != current.get(field)],
        "luaScriptHashesByRun": {
            "other": {item["set"]: item.get("scriptSha256") for item in other.get("results", [])},
            "current": {item["set"]: item.get("scriptSha256") for item in current.get("results", [])},
        },
        "romHashesEqualBySet": {
            item["set"]: item.get("romSha256") == next(
                (candidate.get("romSha256") for candidate in other.get("results", []) if candidate.get("set") == item["set"]),
                None,
            )
            for item in current.get("results", [])
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", required=True, type=Path, help="capture directory containing manifest.json and per-set CSVs")
    parser.add_argument("--compare-run-dir", type=Path, help="optional second capture directory to compare trace and manifest hashes")
    parser.add_argument("--output", required=True, type=Path, help="JSON output path, normally under ignored simulation/")
    args = parser.parse_args()

    run_dir = args.run_dir.resolve()
    manifest = load_manifest(run_dir)
    results = {item["set"]: analyze_game(run_dir, item["set"]) for item in manifest["results"]}
    comparison_data = None
    if args.compare_run_dir:
        other_dir = args.compare_run_dir.resolve()
        other_manifest = load_manifest(other_dir)
        other_results = {
            item["set"]: analyze_game(other_dir, item["set"])
            for item in other_manifest["results"]
        }
        comparison_data = comparison(manifest, other_manifest)
        comparison_data["traceSha256EqualBySet"] = {
            set_name: results[set_name]["traceSha256"] == other_results[set_name]["traceSha256"]
            for set_name in results.keys() & other_results.keys()
        }
        comparison_data["setsOnlyInCurrent"] = sorted(results.keys() - other_results.keys())
        comparison_data["setsOnlyInOther"] = sorted(other_results.keys() - results.keys())

    output = {
        "schemaVersion": 1,
        "run": manifest.get("run"),
        "sourceRunDirectory": str(run_dir),
        "manifestSourceHashes": {
            "mameSha256": manifest.get("mameSha256"),
            "pinnedSourceCommit": manifest.get("pinnedSourceCommit"),
            "exidyCppSha256": manifest.get("exidyCppSha256"),
            "exidySoundCppSha256": manifest.get("exidySoundCppSha256"),
        },
        "analysisDefinition": {
            "sourceByteQualification": "audio CRB bit 2 selects PB data and the last written DDRB is 0xFF",
            "destinationByteQualification": "main CRA bit 2 selects PA data and the last written DDRA is 0x00",
            "readRule": "first qualified main PA data read at or after an audio PB data write and before the next audio PB data write",
            "matchRule": "main PA read byte equals audio PB write data masked by DDRB",
            "p95Rule": "sorted floor index floor((n-1)*0.95)",
        },
        "comparison": comparison_data,
        "games": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.output.resolve()),
        "run": output["run"],
        "comparison": comparison_data,
        "games": {
            key: {
                "traceSha256": value["traceSha256"],
                "audioPbDataWrites": value["audioPbDataWrites"],
                "mainPaDataReads": value["mainPaDataReads"],
                "ddrQualified": value["ddrQualified"],
                "firstReadBeforeNextPbWrite": value["firstReadBeforeNextPbWrite"],
                "matchingFirstReads": value["matchingFirstReads"],
                "mismatchingFirstReads": value["mismatchingFirstReads"],
                "writesOverwrittenBeforeRead": value["writesOverwrittenBeforeRead"],
                "matchingReadLatencyMicroseconds": value["matchingReadLatencyMicroseconds"],
            }
            for key, value in results.items()
        },
    }, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
