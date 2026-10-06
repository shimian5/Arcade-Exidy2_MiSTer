#!/usr/bin/env python3
"""Build a compact machine-readable storage budget from the byte audit report."""
import argparse
import json
from pathlib import Path

from contract import CVSD_BYTES, INDEX_EXPANSION_DESCRIPTOR, INDEX_FAX_QUESTIONS, INDEX_MOUSETRAP_CVSD, Q_BANK_BYTES


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--audit", type=Path, default=Path("docs/design/rom-expansion/verified-rom-regions.json"))
    ap.add_argument("--output", type=Path, default=Path("docs/design/rom-expansion/region-budget.json"))
    args = ap.parse_args()
    audit = json.loads(args.audit.read_text(encoding="utf-8"))
    sets = audit["sets"]
    questions = {}
    for setname in ("fax", "fax2"):
        questions[setname] = sets[setname]["regions"]["questionBanks"]
    voice = sets["mtrap"]["regions"]["soundbd:cvsdcpu"]
    fax_proms = sets["fax"]["regions"]["proms"]
    budget = {
        "reference": audit["reference"],
        "verifiedArchiveRows": audit["archiveCheckCount"],
        "allArchiveBytesMatchManifest": audit["allArchiveBytesMatchManifest"],
        "transport": {
            "legacyIndex0Unchanged": True,
            "questionIndex": INDEX_FAX_QUESTIONS,
            "cvsdIndex": INDEX_MOUSETRAP_CVSD,
            "descriptorIndex": INDEX_EXPANSION_DESCRIPTOR,
            "descriptorFormat": {"bytes": 16, "magic": "EX", "version": 1,
                                 "profileIds": {"fax": 1, "fax2": 2, "mtrap-cvsd": 3},
                                 "requiredStreamMask": {"index0": 1, "index5": 2, "index6": 4},
                                 "lengthFields": "uint24 little-endian; index0 then index5 then index6; final two bytes reserved zero"},
        },
        "storage": {
            "question": {"banks": 24, "bytesPerBank": Q_BANK_BYTES, "logicalBytes": 24 * Q_BANK_BYTES,
                         "physicalOrganization": "24 independently addressed 8-KiB banks; do not infer a flat 256-KiB RAM",
                         "faxMissingBanks": {"22": "zero-filled stream slot", "23": "zero-filled stream slot"},
                         "fax2MissingBanks": {}, "selects24to31": "deterministic 0x00; parity unverified"},
            "cvsd": {"bytes": CVSD_BYTES, "logicalBytes": CVSD_BYTES, "partBytes": 0x1000,
                     "parts": voice},
            "combinedLogicalBytes": 24 * Q_BANK_BYTES + CVSD_BYTES,
            "estimatedM10KByteBlocksAt1024x8": (24 * Q_BANK_BYTES + CVSD_BYTES) // 1024,
            "deviceNominalM10KBlocks": 553,
            "deviceNominalM10KBits": 5530 * 1024,
            "fitStatus": "theoretical only; free blocks and timing unverified",
            "externalMemory": {"ddramInterfaceAtTop": True, "activeRequestEngineFound": False,
                               "boardSdramForcedHighImpedance": True},
        },
        "questionBankMaps": questions,
        "faxProms": {"mameRegionBytes": 0x240, "mameLoadedButNotHookedUp": True,
                     "image": sets["fax"]["regions"]["promImage"], "parts": fax_proms,
                     "hardwareUsageAndCoreRouting": "unresolved; do not infer that current PROMs cover this region"},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(budget, indent=2) + "\n", encoding="utf-8")
    print(f"budget={args.output} archiveMatch={budget['allArchiveBytesMatchManifest']} m10kByteBlocks={budget['storage']['estimatedM10KByteBlocksAt1024x8']}")
    return 0 if budget["allArchiveBytesMatchManifest"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
