#!/usr/bin/env python3
"""Summarize callback-row PIA status/request order in a frozen capture run.

This intentionally never reads `time_s`: cross-CPU callback timestamps are not
used as an elapsed-time or ordering source.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from bisect import bisect_right
from collections import Counter
from pathlib import Path
import statistics
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def pc_name(event: dict[str, Any] | None) -> str:
    return "none" if event is None else f"0x{event['pc']:04X}"


def analyze_set(run_dir: Path, set_name: str) -> dict[str, Any]:
    path = run_dir / set_name / "pia-bus.csv"
    rows: list[dict[str, Any]] = []
    controls: dict[str, dict[str, int | None]] = {
        cpu: {"CRA": None, "CRB": None, "DDRA": None, "DDRB": None}
        for cpu in ("main", "audio")
    }
    counts: Counter[str] = Counter()
    with path.open("r", newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        expected = {"cpu", "op", "address", "kind", "data", "pc"}
        if not reader.fieldnames or not expected.issubset(reader.fieldnames):
            raise ValueError(f"unexpected CSV header in {path}: {reader.fieldnames}")
        for row_index, raw in enumerate(reader):
            cpu, op, kind = raw["cpu"], raw["op"], raw["kind"]
            if cpu not in controls:
                raise ValueError(f"unknown CPU {cpu!r} in {path}:{row_index + 2}")
            value = int(raw["data"], 16)
            event = {
                "row": row_index,
                "cpu": cpu,
                "op": op,
                "kind": kind,
                "value": value,
                "address": int(raw["address"], 16),
                "pc": int(raw["pc"], 16),
                **controls[cpu],
            }
            counts[f"{cpu}_{op}_{kind}"] += 1
            if op == "W" and kind in ("CRA", "CRB"):
                controls[cpu][kind] = value & 0x3F
            elif op == "W" and kind in ("DDRA", "DDRB"):
                controls[cpu][kind] = value
            # Match the established capture analyzer: an audio PB write is a
            # source byte only with CRB data selected and all DDRB bits output;
            # a main PA read is a destination byte only with CRA data selected
            # and DDRA all input.
            event.update(controls[cpu])
            rows.append(event)

    source_writes = [
        row for row in rows
        if row["cpu"] == "audio" and row["op"] == "W" and row["kind"] == "PB_DATA"
    ]
    main_pa_reads = [
        row for row in rows
        if row["cpu"] == "main" and row["op"] == "R" and row["kind"] == "PA_DATA"
    ]
    main_cra_reads = [
        row for row in rows
        if row["cpu"] == "main" and row["op"] == "R" and row["kind"] == "CRA"
    ]
    main_pb_writes = [
        row for row in rows
        if row["cpu"] == "main" and row["op"] == "W" and row["kind"] == "PB_DATA"
    ]

    pairs: list[dict[str, Any]] = []
    counters: Counter[str] = Counter()
    per_source_pc: dict[str, Counter[str]] = {}
    source_hold_rows: dict[str, list[int]] = {}
    per_pa_pc: dict[str, Counter[str]] = {}
    status_pc: Counter[str] = Counter()
    request_pc: Counter[str] = Counter()

    read_index = 0
    poll_index = 0
    request_index = 0
    consumed_request_index = 0
    for index, write in enumerate(source_writes):
        next_write = source_writes[index + 1] if index + 1 < len(source_writes) else None
        while request_index < len(main_pb_writes) and main_pb_writes[request_index]["row"] < write["row"]:
            request_index += 1
        requests_before_write = main_pb_writes[consumed_request_index:request_index]
        consumed_request_index = request_index
        write_qualified = write["CRB"] is not None and (write["CRB"] & 0x04) and write["DDRB"] == 0xFF
        if not write_qualified:
            counters["sourceWritesUnqualified"] += 1
            continue
        counters["sourceWritesQualified"] += 1
        boundary = next_write["row"] if next_write else None
        while read_index < len(main_pa_reads) and main_pa_reads[read_index]["row"] <= write["row"]:
            read_index += 1
        read = main_pa_reads[read_index] if read_index < len(main_pa_reads) and (
            boundary is None or main_pa_reads[read_index]["row"] < boundary
        ) else None
        if read is None:
            counters["qualifiedWritesWithoutNextPaReadBeforeOverwriteOrEnd"] += 1
            continue
        read_qualified = read["CRA"] is not None and (read["CRA"] & 0x04) and read["DDRA"] == 0
        if not read_qualified:
            counters["firstPaReadsUnqualified"] += 1
            continue
        counters["qualifiedSourceReadPairs"] += 1

        # Callback order is the only ordering relation used. Count CA1 status
        # reads after this audio write and before its matched main PA read.
        while poll_index < len(main_cra_reads) and main_cra_reads[poll_index]["row"] <= write["row"]:
            poll_index += 1
        polls: list[dict[str, Any]] = []
        while poll_index < len(main_cra_reads) and main_cra_reads[poll_index]["row"] < read["row"]:
            polls.append(main_cra_reads[poll_index])
            poll_index += 1
        last_poll = polls[-1] if polls else None
        counters["pairsWithCraReadAfterSourceWrite"] += bool(polls)
        counters["pairsBypassingCraReadAfterSourceWrite"] += not bool(polls)
        counters["ca1Bit7SetPollsBetweenWriteAndRead"] += sum((poll["value"] & 0x80) != 0 for poll in polls)
        counters["ca1Bit7ClearPollsBetweenWriteAndRead"] += sum((poll["value"] & 0x80) == 0 for poll in polls)
        if last_poll:
            counters["lastCraPollBit7Set"] += (last_poll["value"] & 0x80) != 0
            counters["lastCraPollBit7Clear"] += (last_poll["value"] & 0x80) == 0

        requests_during_reply: list[dict[str, Any]] = []
        while request_index < len(main_pb_writes) and main_pb_writes[request_index]["row"] < read["row"]:
            requests_during_reply.append(main_pb_writes[request_index])
            request_index += 1
        consumed_request_index = request_index
        previous_request = requests_before_write[-1] if requests_before_write else None
        request_pc.update([pc_name(event) for event in requests_before_write])

        expected = write["value"] & write["DDRB"]
        matching = read["value"] == expected
        counters["matchedDataPairs"] += matching
        counters["mismatchedDataPairs"] += not matching
        rows_until_next = (next_write["row"] - write["row"] - 1) if next_write else None
        source_pc = pc_name(write)
        pa_pc = pc_name(read)
        source_counts = per_source_pc.setdefault(source_pc, Counter())
        pa_counts = per_pa_pc.setdefault(pa_pc, Counter())
        source_counts["pairs"] += 1
        source_counts["statusPollAfterWrite"] += bool(polls)
        source_counts["statusBypass"] += not bool(polls)
        source_counts["matched"] += matching
        source_counts["pairsWithPriorMainPbRequest"] += previous_request is not None
        source_counts["pairsWithoutPriorMainPbRequest"] += previous_request is None
        source_counts["pairsWithPbRequestDuringReply"] += bool(requests_during_reply)
        pa_counts["pairs"] += 1
        pa_counts["statusPollAfterWrite"] += bool(polls)
        pa_counts["statusBypass"] += not bool(polls)
        pa_counts["matched"] += matching
        if rows_until_next is not None:
            source_hold_rows.setdefault(source_pc, []).append(rows_until_next)
        if last_poll:
            status_pc[pc_name(last_poll)] += 1

        pairs.append({
            "sourceRow": write["row"],
            "sourcePc": source_pc,
            "sourceData": f"0x{write['value']:02X}",
            "sourceCRB": f"0x{write['CRB']:02X}" if write["CRB"] is not None else None,
            "sourceDDRB": f"0x{write['DDRB']:02X}" if write["DDRB"] is not None else None,
            "previousRequestPc": pc_name(previous_request),
            "previousRequestData": f"0x{previous_request['value']:02X}" if previous_request else None,
            "previousRequestCRB": f"0x{previous_request['CRB']:02X}" if previous_request and previous_request["CRB"] is not None else None,
            "previousRequestDDRB": f"0x{previous_request['DDRB']:02X}" if previous_request and previous_request["DDRB"] is not None else None,
            "requestsBetweenSourceAndRead": len(requests_during_reply),
            "statusPollsBetweenSourceAndRead": len(polls),
            "statusPolls": [
                {"pc": pc_name(poll), "data": f"0x{poll['value']:02X}", "ca1Bit7": (poll["value"] >> 7) & 1}
                for poll in polls
            ],
            "lastStatusPollPc": pc_name(last_poll),
            "paReadRow": read["row"],
            "paReadPc": pa_pc,
            "paReadData": f"0x{read['value']:02X}",
            "mainCRA": f"0x{read['CRA']:02X}" if read["CRA"] is not None else None,
            "mainDDRA": f"0x{read['DDRA']:02X}" if read["DDRA"] is not None else None,
            "matchesSourceData": matching,
            "callbackRowsUntilNextAudioPbWrite": rows_until_next,
        })

    paired_read_rows = {pair["paReadRow"] for pair in pairs}
    all_source_rows = [event["row"] for event in source_writes]
    cra_rows = [event["row"] for event in main_cra_reads]
    unpaired_pc: dict[str, Counter[str]] = {}
    for read in main_pa_reads:
        if read["row"] in paired_read_rows:
            continue
        pc = pc_name(read)
        summary = unpaired_pc.setdefault(pc, Counter())
        summary["unpairedQualifiedPaReadCallbacks"] += bool(
            read["CRA"] is not None and (read["CRA"] & 0x04) and read["DDRA"] == 0
        )
        source_index = bisect_right(all_source_rows, read["row"]) - 1
        if source_index < 0:
            summary["beforeAnyQualifiedSourceWrite"] += 1
            continue
        source = source_writes[source_index]
        source_qualified = source["CRB"] is not None and (source["CRB"] & 0x04) and source["DDRB"] == 0xFF
        next_source_row = all_source_rows[source_index + 1] if source_index + 1 < len(all_source_rows) else None
        if not source_qualified:
            summary["latestSourceWriteUnqualified"] += 1
        elif next_source_row is None or read["row"] < next_source_row:
            summary["additionalReadInSourceHoldingWindow"] += 1
        status_index = bisect_right(cra_rows, source["row"])
        has_status = status_index < len(cra_rows) and cra_rows[status_index] < read["row"]
        summary["craReadAfterLatestSourceWrite"] += has_status
        summary["bypassesCraReadAfterLatestSourceWrite"] += not has_status

    return {
        "set": set_name,
        "traceSha256": sha256(path),
        "callbackOrderOnly": True,
        "timestampFieldsRead": False,
        "eventCounts": dict(sorted(counts.items())),
        "summary": dict(sorted(counters.items())),
        "lastStatusPollPcCounts": dict(sorted(status_pc.items())),
        "mainRequestPcCountsInSourceIntervals": dict(sorted(request_pc.items())),
        "sourceWritePcSummary": {pc: dict(sorted(value.items())) for pc, value in sorted(per_source_pc.items())},
        "sourceRowsUntilNextPbWriteByPc": {
            pc: {"count": len(values), "minRows": min(values), "maxRows": max(values),
                 "medianRows": statistics.median(values)}
            for pc, values in sorted(source_hold_rows.items())
        },
        "mainPaReadPcSummary": {pc: dict(sorted(value.items())) for pc, value in sorted(per_pa_pc.items())},
        "unpairedMainPaReadPcSummary": {pc: dict(sorted(value.items())) for pc, value in sorted(unpaired_pc.items())},
        "pairs": pairs,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-dir", type=Path, required=True, help="frozen run directory containing manifest.json")
    parser.add_argument("--output", type=Path, required=True, help="JSON path, normally under ignored simulation/")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.relative_to(Path(__file__).resolve().parents[2] / "simulation")
    run_dir = args.run_dir.resolve()
    manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8-sig"))
    results = [analyze_set(run_dir, item["set"]) for item in manifest["results"]]
    output = {
        "schemaVersion": 1,
        "rowIndexConvention": "zero-based data rows, excluding CSV header; add 2 for physical CSV line",
        "run": manifest.get("run"),
        "pinnedSourceCommit": manifest.get("pinnedSourceCommit"),
        "mameVersion": manifest.get("mameVersion"),
        "qualification": {
            "source": "audio PB_DATA write with CRB bit 2 set and DDRB 0xFF",
            "destination": "first main PA_DATA read after source callback row and before next audio PB_DATA row; CRA bit 2 set and DDRA 0x00",
            "statusWindow": "main CRA read callbacks strictly after source write row and before paired PA read row; CA1 status is data bit 7",
            "requestWindow": "last main PB_DATA write since previous audio PB_DATA write and before current source write; any additional requests between source and paired read counted separately",
            "ordering": "CSV callback row order only; time_s is not loaded or used",
        },
        "games": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": str(args.output.resolve()), "run": output["run"],
                      "games": {item["set"]: item["summary"] for item in results}}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
