#!/usr/bin/env python3
"""Audit index-0 MRA streams against MAME ROM metadata and Exidy2 loader wiring."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import zipfile
import zlib
from collections import defaultdict
from pathlib import Path
from xml.etree import ElementTree as ET


# Mirrors selector in rtl/rom_loader.sv. widths are the physical RAM address bits.
SELECTORS = [
    (0x00000, 0x10000, "eprom_0/maincpu", 16),
    (0x10000, 0x14000, "eprom_6/audio", 14),
    (0x14000, 0x14800, "eprom_1/gfx", 11),
    (0x14800, 0x14900, "eprom_2/decoder", 8),
    (0x14900, 0x14920, "eprom_3/vram_ctrl", 5),
    (0x14920, 0x14940, "eprom_4/sprite_ctrl", 5),
    (0x14940, 0x14960, "eprom_5/tone", 5),
    (0x14960, 0x2000000, "eprom_7/fallback", 14),
]


def selector_at(address: int) -> tuple[str, int, int]:
    for start, stop, name, width in SELECTORS:
        if start <= address < stop:
            return name, width, address & ((1 << width) - 1)
    raise ValueError(f"loader address outside modeled range: {address:#x}")


def sha(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


def bytes_match_after_bus_mask(expected: bytes, observed: bytes, bits: int = 8) -> bool:
    mask = (1 << bits) - 1
    return len(expected) == len(observed) and all((a & mask) == (b & mask) for a, b in zip(expected, observed))


def read_mra(path: Path) -> tuple[str, list[dict]]:
    root = ET.parse(path).getroot()
    name = root.findtext("setname") or path.stem
    rom = root.find("rom[@index='0']")
    if rom is None:
        raise ValueError(f"{path}: no ROM index 0")
    archives = [x.strip() for x in (rom.get("zip") or f"{name}.zip").split("|") if x.strip()]
    parts = []
    for part in rom.findall("part"):
        repeat = part.get("repeat")
        if repeat is not None:
            value = bytes.fromhex("".join((part.text or "").split()))
            if len(value) != 1:
                raise ValueError(f"{path}: repeat literal must be one byte")
            parts.append({"kind": "repeat", "length": int(repeat, 0), "value": value[0]})
        elif part.get("crc"):
            parts.append({"kind": "rom", "crc": part.get("crc", "").lower(), "name": part.get("name", ""), "archives": archives})
        elif part.text and part.text.strip():
            data = bytes.fromhex("".join(part.text.split()))
            parts.append({"kind": "literal", "data": data})
        else:
            raise ValueError(f"{path}: unsupported empty part")
    return name, parts


class ArchiveSet:
    def __init__(self, rom_dir: Path):
        self.rom_dir = rom_dir
        self.cache: dict[str, dict[str, tuple[bytes, str]]] = {}
        self.archive_paths: dict[str, Path] = {}

    def load_archive(self, archive: str) -> dict[str, tuple[bytes, str]]:
        if archive in self.cache:
            return self.cache[archive]
        path = self.rom_dir / archive
        if not path.exists():
            self.cache[archive] = {}
            return {}
        self.archive_paths[archive] = path
        entries = {}
        with zipfile.ZipFile(path) as zf:
            for info in zf.infolist():
                if info.is_dir():
                    continue
                data = zf.read(info)
                crc = f"{zlib.crc32(data) & 0xffffffff:08x}"
                entries.setdefault(crc, (data, info.filename))
        self.cache[archive] = entries
        return entries

    def resolve(self, crc: str, archives: list[str]) -> tuple[bytes, str, str]:
        for archive in archives:
            found = self.load_archive(archive).get(crc.lower())
            if found:
                data, name = found
                return data, archive, name
        raise KeyError(f"CRC {crc} absent from archive aliases {archives}")


def mame_rows(manifest: dict, setname: str) -> list[dict]:
    row = next((s for s in manifest["sets"] if s["set"] == setname), None)
    if row is None:
        raise KeyError(f"{setname}: not in MAME manifest")
    return row["roms"]


def check_manifest_archives(manifest: dict, setnames: set[str], rom_dir: Path) -> list[dict]:
    """Check each selected set's raw archive members against MAME size/CRC/SHA1."""
    checks = []
    for setname in sorted(setnames):
        row = next(s for s in manifest["sets"] if s["set"] == setname)
        archive = f"{setname}.zip"
        index = ArchiveSet(rom_dir).load_archive(archive)
        for expected in row["roms"]:
            found = index.get(expected["crc"].lower())
            if not found:
                checks.append({"set": setname, "name": expected["name"], "status": "missing_crc", "expectedCrc": expected["crc"]})
                continue
            data, member = found
            actual = {"size": len(data), "crc": f"{zlib.crc32(data) & 0xffffffff:08x}", "sha1": sha(data)}
            wanted = {"size": int(expected["size"]), "crc": expected["crc"].lower(), "sha1": expected["sha1"].lower()}
            ok = actual == wanted
            checks.append({"set": setname, "name": expected["name"], "member": member, "status": "match" if ok else "mismatch",
                           "expected": wanted, "actual": actual})
    return checks


def audit_one(mra_path: Path, manifest: dict, archives: ArchiveSet) -> dict:
    setname, parts = read_mra(mra_path)
    rows = mame_rows(manifest, setname)
    rows_by_crc = defaultdict(list)
    for row in rows:
        rows_by_crc[row["crc"].lower()].append(row)

    offset = 0
    placed = []
    stream_sha = hashlib.sha1()
    byte_counts = defaultdict(int)
    regions = defaultdict(lambda: {"sha1": hashlib.sha1(), "size": 0, "segments": []})
    physical = defaultdict(dict)
    raw_physical = defaultdict(dict)
    rom_part_data = {}
    mismatches = []
    for i, part in enumerate(parts):
        if part["kind"] == "repeat":
            data = bytes([part["value"]]) * part["length"]
            desc = f"repeat {part['value']:02x} x {part['length']:#x}"
        elif part["kind"] == "literal":
            data = part["data"]
            desc = f"literal {len(data):#x} bytes"
        else:
            data, archive, entry = archives.resolve(part["crc"], part["archives"])
            rom_part_data[i] = data
            desc = f"{part['name']} CRC {part['crc']} from {archive}:{entry}"
            if f"{zlib.crc32(data) & 0xffffffff:08x}" != part["crc"]:
                mismatches.append(f"part {i}: ZIP CRC mismatch for {part['name']}")
            candidates = rows_by_crc.get(part["crc"], [])
            if not candidates:
                # An MRA may deliberately borrow a shared PROM absent from this MAME set.
                placed.append({"part": i, "mraName": part["name"], "crc": part["crc"], "size": len(data), "streamOffset": offset,
                               "mameRegion": None, "mameOffset": None, "mameName": None})
            else:
                matching = [r for r in candidates if int(r["size"]) == len(data)]
                if not matching:
                    mismatches.append(f"part {i}: size {len(data)} differs from MAME size(s) {[r['size'] for r in candidates]}")
                for r in matching:
                    placed.append({"part": i, "mraName": part["name"], "crc": part["crc"], "size": len(data), "streamOffset": offset,
                                   "mameRegion": r["region"], "mameOffset": int(r["offset"], 16), "mameName": r["name"]})
        start = offset
        stream_sha.update(data)
        # Summarize exact selected physical regions for this part; each byte goes to one bank.
        for pos in range(start, start + len(data)):
            bank, width, phys = selector_at(pos)
            byte_counts[bank] += 1
            value = data[pos - start]
            raw_physical[bank][phys] = value
            # eprom_2 declares DATA_IN/DATA as four bits; upper input nibble is discarded.
            if bank == "eprom_2/decoder":
                value &= 0x0f
            if phys in physical[bank]:
                physical[bank][phys] = value
            else:
                physical[bank][phys] = value
            if part["kind"] == "rom":
                region = regions[bank]
                region["size"] += 1
                # Hash stream bytes per physical-write order without retaining assembled image.
                region["sha1"].update(data[pos - start:pos - start + 1])
        for p in range(start, start + len(data)):
            bank, width, phys = selector_at(p)
            if not placed or placed[-1].get("part") != i:
                break
            if placed[-1].get("segments") is None:
                placed[-1]["segments"] = []
            segs = placed[-1]["segments"]
            if segs and segs[-1]["bank"] == bank and segs[-1]["streamEnd"] == p and segs[-1]["physicalEnd"] == phys:
                segs[-1]["streamEnd"] += 1
                segs[-1]["physicalEnd"] += 1
            else:
                segs.append({"bank": bank, "streamStart": p, "streamEnd": p + 1, "physicalStart": phys, "physicalEnd": phys + 1})
        offset += len(data)

    # Cross-check each MAME region entry appears at the same physical address where its MRA bytes land.
    for entry in placed:
        for segment in entry.get("segments", []):
            expected = entry["mameOffset"]
            # MAME offsets are relative to their named region. The ROM bank names differ from MAME's region names;
            # use the physical byte offset only where a single segment maps to the corresponding component.
            if expected is not None and segment["physicalStart"] != expected and len(entry.get("segments", [])) == 1:
                entry["physicalVsMameOffset"] = segment["physicalStart"] - expected
    for entry in placed:
        entry["loaderSegments"] = entry.pop("segments", [])
        if entry.get("loaderSegments"):
            seg = entry["loaderSegments"][0]
            source = rom_part_data[entry["part"]]
            actual = bytes(physical[seg["bank"]][seg["physicalStart"] + n] for n in range(len(source)))
            bits = 4 if seg["bank"] == "eprom_2/decoder" else 8
            entry["physicalVerification"] = {"physicalOffset": seg["physicalStart"], "busBits": bits,
                "rawSourceSha1": sha(source), "effectiveSourceSha1": sha(bytes(x & ((1 << bits) - 1) for x in source)),
                "effectiveLoadedSha1": sha(actual), "byteMatchAfterBusMask": bytes_match_after_bus_mask(source, actual, bits)}
            if not entry["physicalVerification"]["byteMatchAfterBusMask"]:
                mismatches.append(f"part {entry['part']}: loaded bytes differ at {seg['bank']}:{seg['physicalStart']:#x}")
    mra_crcs = {p["crc"] for p in parts if p["kind"] == "rom"}
    mame_omissions = [r for r in rows if r["crc"].lower() not in mra_crcs]
    mra_extras = [p for p in parts if p["kind"] == "rom" and p["crc"] not in rows_by_crc]
    physical_regions = []
    for bank, memory in sorted(physical.items()):
        addrs = sorted(memory)
        ranges = []
        for addr in addrs:
            if ranges and addr == ranges[-1]["end"]:
                ranges[-1]["end"] += 1
                ranges[-1]["data"].append(memory[addr])
            else:
                ranges.append({"start": addr, "end": addr + 1, "data": [memory[addr]]})
        physical_regions.append({"bank": bank, "effectiveDataBits": 4 if bank == "eprom_2/decoder" else 8,
                                 "uniqueBytes": len(memory), "overwrites": max(0, byte_counts[bank] - len(memory)),
                                 "rawWrittenSha1": sha(bytes(raw_physical[bank][a] for a in addrs)),
                                 "effectiveStoredSha1": sha(bytes(memory[a] for a in addrs)),
                                 "segments": [{"offset": x["start"], "length": x["end"] - x["start"],
                                               "sha1": sha(bytes(x["data"]))} for x in ranges]})
    return {
        "mra": str(mra_path), "set": setname, "streamBytes": offset, "streamSha1": stream_sha.hexdigest(),
        "parts": len(parts), "romParts": sum(p["kind"] == "rom" for p in parts), "archiveFiles": sorted(archives.archive_paths),
        "bytesPerLoaderBank": dict(byte_counts), "physicalRegions": physical_regions,
        "romPlacements": placed,
        "mameRomPartsOmittedByMra": [{"name": r["name"], "region": r["region"], "offset": int(r["offset"], 16), "size": int(r["size"]), "crc": r["crc"]} for r in mame_omissions],
        "mraRomPartsOutsideMameSet": [{"name": p["name"], "crc": p["crc"]} for p in mra_extras],
        "mismatches": mismatches,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--mra-dir", type=Path, default=Path("releases"))
    ap.add_argument("--manifest", type=Path, default=Path("docs/baseline/roms/availability-manifest.json"))
    ap.add_argument("--rom-dir", type=Path, required=True, help="read-only ZIP directory; no members are extracted")
    ap.add_argument("--json", type=Path, help="optional report path; otherwise write JSON to stdout")
    ap.add_argument("mras", nargs="*", help="MRA file paths; default audits all *.mra in --mra-dir")
    args = ap.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    paths = [Path(p) for p in args.mras] if args.mras else sorted(args.mra_dir.glob("*.mra"))
    reports = []
    for path in paths:
        try:
            reports.append(audit_one(path, manifest, ArchiveSet(args.rom_dir)))
        except Exception as exc:
            reports.append({"mra": str(path), "error": f"{type(exc).__name__}: {exc}"})
    selected = {r["set"] for r in reports if r.get("set")}
    archive_checks = check_manifest_archives(manifest, selected, args.rom_dir)
    output = json.dumps({"schema": 1, "loaderModel": "rtl/rom_loader.sv selector plus physical address truncation",
                         "archiveMemberChecks": archive_checks, "audits": reports}, indent=2)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(output + "\n", encoding="utf-8")
    else:
        print(output)
    return int(any("error" in r or r.get("mismatches") for r in reports) or any(c["status"] != "match" for c in archive_checks))


if __name__ == "__main__":
    sys.exit(main())
