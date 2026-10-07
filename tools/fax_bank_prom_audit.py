#!/usr/bin/env python3
"""Verify pinned MAME FAX question-bank and PROM boundaries from local archives.

Only JSON metadata is written, under ignored simulation storage. ROM bytes remain
in the source archives and in memory; none are emitted to the report.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGION_START = 0x10000
REGION_END = 0x40000
BANK_BYTES = 0x2000


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def archive_member(rom_dir: Path, game: str, member: str, cloneof: str | None) -> tuple[bytes, str]:
    names = [game] + ([cloneof] if cloneof else [])
    for name in names:
        archive = rom_dir / f"{name}.zip"
        if not archive.is_file():
            continue
        with zipfile.ZipFile(archive) as zf:
            info = next((info for info in zf.infolist() if info.filename.lower() == member.lower()), None)
            if info is not None:
                return zf.read(info), archive.name
    raise RuntimeError(f"ROM member {member!r} not found in {names} archives")


def verify_row(data: bytes, row: dict, game: str) -> None:
    require(len(data) == int(row["size"]), f"{game}/{row['name']}: size mismatch")
    require(f"{zlib.crc32(data) & 0xffffffff:08x}" == row["crc"].lower(), f"{game}/{row['name']}: CRC mismatch")
    require(hashlib.sha1(data).hexdigest() == row["sha1"].lower(), f"{game}/{row['name']}: SHA1 mismatch")


def source_contract(source: str, adapter: str) -> dict:
    bank_fn = re.search(r"void fax_state::fax_bank_select_w\(uint8_t data\)\s*\{(.*?)\n\}", source, re.S)
    setup_fn = re.search(r"void fax_state::machine_start\(\)\s*\{(.*?)\n\}", source, re.S)
    map_fn = re.search(r"void fax_state::fax_map\(address_map &map\)\s*\{(.*?)\n\}", source, re.S)
    require(bank_fn and "m_rom_bank->set_entry(data & 0x1f);" in bank_fn.group(1), "MAME bank-select source changed")
    require("if ((data & 0x1f) > 0x17)" in bank_fn.group(1), "MAME unpopulated-bank warning changed")
    require(setup_fn and "configure_entries(0, 32, memregion(\"maincpu\")->base() + 0x10000, 0x2000)" in setup_fn.group(1), "MAME bank geometry changed")
    require(map_fn and 'map(0x2000, 0x2000).w(FUNC(fax_state::fax_bank_select_w));' in map_fn.group(1), "MAME bank register address changed")
    require('map(0x2000, 0x3fff).bankr(m_rom_bank);' in map_fn.group(1), "MAME bank-read window changed")
    require('ROM_REGION( 0x40000, "maincpu", 0 )' in source, "MAME main CPU region size changed")
    require('ROM_LOAD( "fxl-12b",  0x0140, 0x0100, CRC(6b5aa3d7)' in source, "MAME fxl-12b declaration changed")
    # Current MAME source contains PROM declarations only; it has no consumer or lookup.
    require('memregion("proms")' not in source and 'fxl-12b' not in source.replace('ROM_LOAD( "fxl-12b"', ''),
            "unexpected MAME PROM consumer/reference appeared")

    require("question_offset = {bank, address_low};" in adapter, "candidate bank-to-byte mapping changed")
    require("localparam int Q_DEPTH = 196608;" in adapter, "candidate question storage capacity changed")
    require("question_ram_read = question_read && question_window_ready && (question_bank < 5'd24);" in adapter,
            "candidate valid-bank limit changed")
    require("assign question_data = question_result_from_ram ? question_ram_data : 8'd0;" in adapter,
            "candidate invalid-bank data policy changed")
    require("question_result_from_ram <= question_ram_read;" in adapter and "question_valid <= 1'b1;" in adapter,
            "candidate public question-read result policy changed")
    return {"mameBankSelectMask": "0x1f", "mameBankCount": 32, "mameBankBytes": BANK_BYTES,
            "mameCpuRegionBytes": REGION_END, "mameQuestionRegionStart": REGION_START,
            "mameReadWindow": "0x2000-0x3fff", "adapterImplementedBanks": 24,
            "adapterOutOfRangePolicy": "question_valid when profile/window ready; data 0 for bank >= 24"}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rom-dir", type=Path, required=True, help="Read-only directory containing fax.zip and fax2.zip")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "simulation/fax_bank_prom")
    args = parser.parse_args()
    rom_dir = args.rom_dir.resolve()
    out_dir = args.out_dir.resolve()
    out_dir.relative_to((ROOT / "simulation").resolve())
    out_dir.mkdir(parents=True, exist_ok=True)

    availability_path = ROOT / "docs/baseline/roms/availability-manifest.json"
    prior_path = ROOT / "docs/design/expansion-adapter/increment-07-roms.json"
    mame_path = ROOT / "simulation/reference_sources/exidy.cpp"
    adapter_path = ROOT / "sim/expansion_adapter/exidy_expansion_loader_ram.sv"
    availability = json.loads(availability_path.read_text(encoding="utf-8"))
    prior = json.loads(prior_path.read_text(encoding="utf-8"))
    sets = {row["set"]: row for row in availability["sets"]}
    source = mame_path.read_text(encoding="utf-8")
    adapter = adapter_path.read_text(encoding="utf-8")
    source_info = source_contract(source, adapter)

    set_results = {}
    prom_payloads = {}
    for game in ("fax", "fax2"):
        set_row = sets[game]
        rows = set_row["roms"]
        question_rows = [row for row in rows if row["region"] == "maincpu" and
                         REGION_START <= int(row["offset"], 16) < REGION_END]
        image = bytearray(REGION_END - REGION_START)
        occupied = bytearray(len(image))
        components = []
        for row in question_rows:
            data, archive = archive_member(rom_dir, game, row["name"], set_row.get("cloneof"))
            verify_row(data, row, game)
            offset = int(row["offset"], 16) - REGION_START
            require(offset + len(data) <= len(image), f"{game}/{row['name']}: outside question region")
            require(not any(occupied[offset:offset + len(data)]), f"{game}/{row['name']}: overlapping question ROM")
            image[offset:offset + len(data)] = data
            occupied[offset:offset + len(data)] = b"\1" * len(data)
            components.append({"member": row["name"], "archive": archive, "offset": offset,
                               "bytes": len(data), "crc32": row["crc"].lower(), "sha1": row["sha1"].lower()})

        expected = prior["images"][game]
        require(len(image) == expected["bytes"], f"{game}: region size differs from prior verified image")
        require(sha256(image) == expected["sha256"], f"{game}: assembled question image differs from prior independent SHA-256")
        empty_banks = [bank for bank in range(24) if not any(occupied[bank * BANK_BYTES:(bank + 1) * BANK_BYTES])]
        require(empty_banks == expected["emptyBanks"], f"{game}: empty-bank map differs from prior audit")

        staged = ROOT / expected["hexFile"]
        if staged.is_file():
            staged_bytes = bytes(int(line, 16) for line in staged.read_text(encoding="ascii").split())
            require(staged_bytes == image, f"{game}: ignored staged adapter image differs from fresh archive assembly")

        bank_rows = []
        for bank in range(32):
            start = REGION_START + bank * BANK_BYTES
            in_region = start + BANK_BYTES <= REGION_END
            row = {"bank": bank, "selectDataExamples": [f"0x{bank:02x}", f"0x{bank | 0x20:02x}", f"0x{bank | 0x80:02x}"],
                   "maskedBank": bank & 0x1f, "regionOffset": f"0x{start:05x}", "mameRegionValid": in_region}
            if in_region:
                offset = bank * BANK_BYTES
                data = image[offset:offset + BANK_BYTES]
                row.update({"sha256": sha256(data), "allZero": not any(data),
                            "firstByte": f"{data[0]:02x}", "lastByte": f"{data[-1]:02x}"})
            else:
                row["expectedRead"] = "undefined/out-of-region: MAME configures this pointer beyond the 0x40000 maincpu region"
                row["candidateAdapterRead"] = "valid zero when expansion profile/window ready; no backing-bank read"
            bank_rows.append(row)

        prom_row = next(row for row in rows if row["region"] == "proms" and row["name"] == "fxl-12b")
        prom_data, prom_archive = archive_member(rom_dir, game, prom_row["name"], set_row.get("cloneof"))
        verify_row(prom_data, prom_row, game)
        prom_payloads[game] = prom_data
        set_results[game] = {"questionImageBytes": len(image), "questionImageSha256": sha256(image),
                             "populatedBanks": 24 - len(empty_banks), "emptyBanks": empty_banks,
                             "components": components, "banks": bank_rows,
                             "fxl12b": {"archive": prom_archive, "bytes": len(prom_data),
                                        "crc32": f"{zlib.crc32(prom_data) & 0xffffffff:08x}",
                                        "sha1": hashlib.sha1(prom_data).hexdigest(),
                                        "sha256": sha256(prom_data), "uniqueByteValues": len(set(prom_data))}}
    require(prom_payloads["fax"] == prom_payloads["fax2"], "FAX/FAX 2 fxl-12b bytes differ")

    report = {"kind": "MAME source plus read-only private archive boundary audit",
              "mameSourceSha256": sha256(source.encode()), "availabilityManifestSha256": sha256(availability_path.read_bytes()),
              "priorQuestionImageManifestSha256": sha256(prior_path.read_bytes()),
              "romArchivesModified": False, "rawRomBytesWritten": False,
              "sourceContract": source_info, "sets": set_results,
              "conclusions": ["MAME selects data & 0x1f; entries 0-31 are configured with 0x2000 stride from maincpu+0x10000.",
                              "Banks 22/23 are in-region zero-filled for FAX; banks 24-31 start at or beyond the 0x40000 region and have no valid expected bytes.",
                              "The current adapter stores 24 banks and returns valid zero for indices 24-31; that is safe deterministic behavior, not proven MAME parity.",
                              "fxl-12b is loaded into the PROM region for both sets but has no reference/consumer in the pinned MAME driver source."]}
    report_path = out_dir / "report.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("PASS FAX source/archive audit")
    for game, result in set_results.items():
        print(f"{game}: image={result['questionImageSha256']} empty_banks={result['emptyBanks']} "
              f"fxl-12b={result['fxl12b']['sha256']} unique_values={result['fxl12b']['uniqueByteValues']}")
        print(f"  valid MAME banks=0-23; banks 24-31 out-of-region; report={report_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, RuntimeError, ValueError, zipfile.BadZipFile) as exc:
        print(f"FAIL FAX source/archive audit: {exc}", file=sys.stderr)
        raise SystemExit(1)
