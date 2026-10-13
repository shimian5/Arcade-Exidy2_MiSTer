#!/usr/bin/env python3
"""Expand the FAX candidate MRAs into ignored byte streams for RTL fixtures."""
from __future__ import annotations

import hashlib
import json
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MRA_DIR = ROOT / "candidates" / "mra"
ROM_DIR = ROOT / "simulation" / "fax_bank_capture" / "roms"
OUT_DIR = ROOT / "simulation" / "fax_bind" / "mra_images"
EXPECTED_QUESTION_SHA256 = {
    "fax": "462bf48564d2e40647dfad3f35bc794bed6432f6d20da8282d0b9aa11145817a",
    "fax2": "9171f92c9a84e193bb875cd3b197634ef5803f48104a2028f9aed6b73ab892ae",
}
EXPECTED_ORDER = [1, 7, 0, 5, 2]
EXPECTED_BASE_BYTES = 0x14A40
EXPECTED_QUESTION_BYTES = 0x30000


def part_payload(part: ET.Element, archive_names: list[str]) -> bytes:
    if "repeat" in part.attrib:
        count = int(part.attrib["repeat"], 0)
        value = bytes.fromhex(part.text or "")
        if len(value) != 1:
            raise ValueError("repeat part must contain one byte")
        return value * count
    if "name" in part.attrib:
        expected_crc = int(part.attrib["crc"], 16)
        for archive_name in archive_names:
            archive_path = ROM_DIR / archive_name
            with zipfile.ZipFile(archive_path) as archive:
                try:
                    info = archive.getinfo(part.attrib["name"])
                except KeyError:
                    continue
                if info.CRC != expected_crc:
                    raise ValueError(f"CRC mismatch for {part.attrib['name']}")
                return archive.read(info)
        raise FileNotFoundError(f"{part.attrib['name']} not found in {archive_names}")
    return bytes.fromhex(part.text or "")


def write_mem(path: Path, data: bytes) -> None:
    path.write_text("\n".join(f"{byte:02x}" for byte in data) + "\n", encoding="ascii")


def build(mra_path: Path) -> dict:
    root = ET.parse(mra_path).getroot()
    set_name = root.findtext("setname")
    if set_name not in EXPECTED_QUESTION_SHA256:
        raise ValueError(f"unexpected set name: {set_name}")

    streams: dict[int, bytes] = {}
    order: list[int] = []
    for rom in root.findall("rom"):
        index = int(rom.attrib["index"])
        if index in streams:
            raise ValueError(f"duplicate MRA ROM index {index}")
        archive_names = rom.attrib.get("zip", "").split("|")
        payload = b"".join(part_payload(part, archive_names) for part in rom.findall("part"))
        streams[index] = payload
        order.append(index)

    if order != EXPECTED_ORDER:
        raise ValueError(f"{set_name} ROM XML order {order} != {EXPECTED_ORDER}")
    marker = streams[1]
    descriptor = streams[7]
    questions = streams[5]
    if len(marker) != 1 or marker[0] != (0xF4 if set_name == "fax" else 0xF8):
        raise ValueError(f"{set_name} marker is invalid: {marker.hex()}")
    if len(descriptor) != 16 or descriptor[:5] != bytes((0x45, 0x58, 1, 1 if set_name == "fax" else 2, 3)):
        raise ValueError(f"{set_name} descriptor prefix is invalid: {descriptor.hex()}")
    base_length = int.from_bytes(descriptor[5:8], "little")
    question_length = int.from_bytes(descriptor[8:11], "little")
    cvsd_length = int.from_bytes(descriptor[11:14], "little")
    if len(streams[0]) != EXPECTED_BASE_BYTES or base_length != len(streams[0]):
        raise ValueError(f"{set_name} base length mismatch: {len(streams[0])} vs {base_length}")
    if len(questions) != EXPECTED_QUESTION_BYTES or question_length != len(questions) or cvsd_length != 0:
        raise ValueError(f"{set_name} question/CVSD length mismatch")
    question_sha256 = hashlib.sha256(questions).hexdigest()
    if question_sha256 != EXPECTED_QUESTION_SHA256[set_name]:
        raise ValueError(f"{set_name} question image SHA-256 mismatch: {question_sha256}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for index, payload in streams.items():
        write_mem(OUT_DIR / f"{set_name}_index{index}.mem", payload)
    write_mem(OUT_DIR / f"{set_name}_order.mem", bytes(order))
    return {
        "set": set_name,
        "mra": str(mra_path.relative_to(ROOT)),
        "xmlRomOrder": order,
        "streamBytes": {str(index): len(stream) for index, stream in streams.items()},
        "questionSha256": question_sha256,
        "marker": marker.hex(),
        "profile": descriptor[3],
        "baseLength": base_length,
        "questionLength": question_length,
    }


def main() -> None:
    if not ROM_DIR.is_dir():
        raise FileNotFoundError(f"staged private ROM directory missing: {ROM_DIR}")
    reports = [
        build(MRA_DIR / "FAX (question expansion candidate).mra"),
        build(MRA_DIR / "FAX 2 (question expansion candidate).mra"),
    ]
    (OUT_DIR / "manifest.json").write_text(json.dumps({"images": reports}, indent=2) + "\n", encoding="utf-8")
    for report in reports:
        print(f"PASS MRA streams {report['set']}: order={report['xmlRomOrder']} "
              f"base={report['baseLength']} questions={report['questionLength']} "
              f"sha256={report['questionSha256']}")


if __name__ == "__main__":
    main()
