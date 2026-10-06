#!/usr/bin/env python3
"""Verify ROM expansion region bytes directly inside ZIP archives (no extraction)."""
import argparse
import hashlib
import json
import sys
import zipfile
import zlib
from pathlib import Path

from contract import CVSD_OFFSETS, CVSD_PART_BYTES, CVSD_BYTES, Q_BANK_BYTES, Q_FIRST_MAINCPU_OFFSET, question_bank_state


def index_zip(path: Path):
    out = {}
    with zipfile.ZipFile(path) as zf:
        for item in zf.infolist():
            if not item.is_dir():
                data = zf.read(item)
                crc = f"{zlib.crc32(data) & 0xffffffff:08x}"
                out.setdefault(crc, (data, item.filename))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", type=Path, default=Path("docs/baseline/roms/availability-manifest.json"))
    ap.add_argument("--rom-dir", type=Path, required=True, help="read-only split-ROM ZIP directory")
    ap.add_argument("--output", type=Path, required=True, help="metadata-only JSON destination")
    args = ap.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    sets = {s["set"]: s for s in manifest["sets"]}
    zip_cache = {}

    def get_index(zipname):
        if zipname not in zip_cache:
            p = args.rom_dir / zipname
            zip_cache[zipname] = index_zip(p) if p.exists() else {}
        return zip_cache[zipname]

    report = {"reference": {"mameVersion": manifest["mameVersion"], "manifest": str(args.manifest),
                             "sourceCommit": "27a8d9e85b58058965907d1d8a7a92f8ed039348"},
              "sets": {}, "allArchiveBytesMatchManifest": True}
    checks = []
    for setname in ("mtrap", "fax", "fax2"):
        setrow = sets[setname]
        ancestors = [setname]
        if setrow.get("cloneof"):
            ancestors.append(setrow["cloneof"])
        resolved_rows = []
        for row in setrow["roms"]:
            expected_crc = row["crc"].lower()
            found = None
            found_zip = None
            for candidate_set in ancestors:
                candidate = get_index(f"{candidate_set}.zip").get(expected_crc)
                if candidate:
                    found, found_zip = candidate, f"{candidate_set}.zip"
                    break
            expected = {"size": int(row["size"]), "crc": expected_crc, "sha1": row["sha1"].lower()}
            if found:
                data, member = found
                actual = {"size": len(data), "crc": f"{zlib.crc32(data) & 0xffffffff:08x}", "sha1": hashlib.sha1(data).hexdigest()}
                status = "match" if actual == expected else "mismatch"
                result = {"set": setname, "region": row["region"], "name": row["name"], "member": member,
                          "zip": found_zip, "expected": expected, "actual": actual, "status": status}
                resolved_rows.append((row, data))
            else:
                status = "missing"
                result = {"set": setname, "region": row["region"], "name": row["name"], "expected": expected, "status": status}
                resolved_rows.append((row, None))
            checks.append(result)
        regions = {}
        for region in ("soundbd:cvsdcpu", "maincpu", "proms"):
            components = []
            for row, data in resolved_rows:
                if row["region"] != region:
                    continue
                off = int(row["offset"], 16)
                components.append({"offset": off, "size": int(row["size"]), "name": row["name"], "crc": row["crc"],
                                   "sha1": row["sha1"], "archiveVerified": data is not None and hashlib.sha1(data).hexdigest() == row["sha1"].lower()})
            if components:
                regions[region] = components
        if setname == "mtrap":
            voice = regions["soundbd:cvsdcpu"]
            if [r["offset"] for r in voice] != list(CVSD_OFFSETS) or any(r["size"] != CVSD_PART_BYTES for r in voice):
                raise AssertionError("CVSD parts do not fill their reference 16-KiB region in offset order")
            if sum(r["size"] for r in voice) != CVSD_BYTES:
                raise AssertionError("CVSD part sizes do not equal 16 KiB")
            voice_image = bytearray(CVSD_BYTES)
            for row, data in resolved_rows:
                if row["region"] == "soundbd:cvsdcpu" and data is not None:
                    start = int(row["offset"], 16)
                    voice_image[start:start + len(data)] = data
            regions["cvsdImage"] = {"bytes": len(voice_image), "sha1": hashlib.sha1(voice_image).hexdigest(),
                                     "sha256": hashlib.sha256(voice_image).hexdigest()}
        if setname == "fax":
            prom_image = bytearray(0x240)
            for row, data in resolved_rows:
                if row["region"] == "proms" and data is not None:
                    start = int(row["offset"], 16)
                    prom_image[start:start + len(data)] = data
            regions["promImage"] = {"bytes": len(prom_image), "sha1": hashlib.sha1(prom_image).hexdigest(),
                                    "sha256": hashlib.sha256(prom_image).hexdigest(),
                                    "note": "MAME-loaded region; source comments mark it not hooked up"}
        if setname in ("fax", "fax2"):
            banks = []
            question_image = bytearray(24 * Q_BANK_BYTES)
            for bank in range(24):
                expected_offset = Q_FIRST_MAINCPU_OFFSET + bank * Q_BANK_BYTES
                matches = [x for x in regions["maincpu"] if x["offset"] == expected_offset]
                if len(matches) > 1 or any(x["size"] != Q_BANK_BYTES for x in matches):
                    raise AssertionError(f"{setname}: duplicate/invalid question bank {bank}")
                expected_present = question_bank_state(setname, bank) == "populated"
                if bool(matches) != expected_present:
                    raise AssertionError(f"{setname}: bank {bank} expected_present={expected_present}, found={len(matches)}")
                if matches and matches[0]["archiveVerified"]:
                    source_data = next((data for r, data in resolved_rows
                                        if r["region"] == "maincpu" and int(r["offset"], 16) == expected_offset and data is not None), None)
                    if source_data is None or len(source_data) != Q_BANK_BYTES:
                        raise AssertionError(f"{setname}: populated bank {bank} has no verified bytes")
                    local_offset = bank * Q_BANK_BYTES
                    question_image[local_offset:local_offset + Q_BANK_BYTES] = source_data
                    matches[0]["sha256"] = hashlib.sha256(source_data).hexdigest()
                banks.append({"bank": bank, "mameMaincpuOffset": expected_offset,
                              "status": question_bank_state(setname, bank),
                              "part": matches[0] if matches else None})
            regions["questionBanks"] = banks
            regions["questionImage"] = {"bytes": len(question_image), "sha1": hashlib.sha1(question_image).hexdigest(),
                                         "sha256": hashlib.sha256(question_image).hexdigest(),
                                         "emptyBanksZeroFilled": [bank for bank in range(24)
                                                                  if question_bank_state(setname, bank) != "populated"]}
        report["sets"][setname] = {"archiveParents": ancestors, "romCount": len(setrow["roms"]), "regions": regions}
    report["archiveChecks"] = checks
    report["allArchiveBytesMatchManifest"] = all(x["status"] == "match" for x in checks)
    report["archiveCheckCount"] = len(checks)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"checks={len(checks)} mismatches={sum(x['status'] != 'match' for x in checks)} output={args.output}")
    return 0 if report["allArchiveBytesMatchManifest"] else 1


if __name__ == "__main__":
    sys.exit(main())
