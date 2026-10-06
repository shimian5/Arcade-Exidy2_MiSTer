#!/usr/bin/env python3
"""Extract selected live RTL equations, replay accepted bus traces, and emit source evidence."""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl/Exidy2.v"
MAME = ROOT / "simulation/reference_sources/exidy.cpp"
PINNED_MAME_EXIDY_SHA256 = "0F58186AD90F0592454C505FF10FBCA948EBA14E7815704B2D24B13F69327486"


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def one_line(lines: list[str], needle: str) -> str:
    matches = [line.rstrip() for line in lines if needle in line and not line.lstrip().startswith("//")]
    if len(matches) != 1:
        raise RuntimeError(f"expected one source line containing {needle!r}, got {len(matches)}")
    return matches[0]


def always_block(lines: list[str], needle: str) -> list[str]:
    hit = next((i for i, line in enumerate(lines) if needle in line), None)
    if hit is None:
        raise RuntimeError(f"missing production block anchor {needle!r}")
    start = next((i for i in range(hit, -1, -1) if "always" in lines[i]), None)
    if start is None:
        raise RuntimeError(f"no always block for {needle!r}")
    end = next((i for i in range(hit, len(lines)) if lines[i].strip() == "end"), None)
    if end is None:
        raise RuntimeError(f"unterminated production block for {needle!r}")
    return [line.rstrip() for line in lines[start : end + 1]]


def extract_rtl(out: Path) -> tuple[str, list[str]]:
    lines = RTL.read_text(encoding="utf-8").splitlines()
    picked = [
        one_line(lines, "assign nWM2V ="),
        one_line(lines, "assign nWM2H ="),
        one_line(lines, "assign nWM1V ="),
        one_line(lines, "assign nWM1H ="),
        one_line(lines, "wire nWMOL ="),
        one_line(lines, "wire nWCPL ="),
        one_line(lines, "always @(posedge nWM1H)"),
        one_line(lines, "always @(posedge nWM1V)"),
        one_line(lines, "always @(posedge nWM2H)"),
        one_line(lines, "always @(posedge nWM2V)"),
        always_block(lines, "M1H <="),
        always_block(lines, "M1V <="),
        one_line(lines, "always @(posedge nWMOL)"),
        one_line(lines, "always @(posedge nWCPL)"),
        one_line(lines, "assign SPRITE_ADDR ="),
        one_line(lines, "assign nM01VDT="),
        one_line(lines, "assign nM02VDT="),
        one_line(lines, "assign nSGCVID=!SGCVID;"),
        one_line(lines, "always @(*) cDET<="),
        one_line(lines, "always @(negedge BCLK or negedge COINT or negedge nEIR) rCPU_IRQ"),
        one_line(lines, "always @(posedge rCPU_IRQ) EIR"),
    ]
    flattened = []
    for item in picked:
        flattened.extend(item if isinstance(item, list) else [item])
    # The fixture pins the baseline (interrupt profile 0) wiring: substitute the
    # legacy expressions for the profile-selected names added in rtl/Exidy2.v.
    legacy_eir = "!(nM01VDT|nM02VDT),1'b0,!((nSGCVID|nM01VDT)|CBLB)"
    flattened = [line.replace("int_cause[4],int_cause[3],int_cause[2]", legacy_eir).replace("cDET_sel", "cDET") for line in flattened]
    text = "\n".join(flattened) + "\n"
    (out / "rtl_extracted.svh").write_text(text, encoding="utf-8", newline="\n")
    return text, flattened


def replay_trace(path: Path) -> dict:
    counts: Counter[int] = Counter()
    value_sets: dict[int, set[int]] = {a: set() for a in (0x5000, 0x5040, 0x5080, 0x50C0, 0x5100, 0x5101)}
    fire_values: dict[int, set[int]] = {a: set() for a in (0x5000, 0x5040, 0x5080, 0x50C0)}
    last: dict[int, int] = {}
    active_window = 0
    aliases_seen = Counter()
    with path.open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            if row["kind"] != "W":
                continue
            address = int(row["address"], 16)
            value = int(row["data"], 16)
            frame = int(row["frame"])
            if 0x5000 <= address <= 0x50FF and address not in value_sets:
                aliases_seen[address] += 1
            if address in value_sets:
                counts[address] += 1
                value_sets[address].add(value)
                last[address] = value
                if address in fire_values and 2400 <= frame <= 2519:
                    fire_values[address].add(value)
                    active_window += 1
    if not all(counts[a] for a in value_sets):
        raise RuntimeError(f"accepted trace lacks required write-bank events: {dict(counts)}")
    return {
        "path": str(path.relative_to(ROOT)),
        "sha256": sha256(path),
        "addressPolicy": "accepted Lua tap canonicalizes sprite mirrors to base addresses; alias use is unavailable",
        "writeCounts": {f"{a:04X}": counts[a] for a in sorted(counts)},
        "distinctWriteData": {f"{a:04X}": len(value_sets[a]) for a in sorted(value_sets)},
        "distinctCoordinateDataDuringRightFire": {f"{a:04X}": len(fire_values[a]) for a in sorted(fire_values)},
        "lastWrittenData": {f"{a:04X}": f"{last[a]:02X}" for a in sorted(last)},
        "rightFireWindowCoordinateWriteRows": active_window,
        "rawMirroredAddressWritesObserved": sum(aliases_seen.values()),
    }


def emit_replay_include(path: Path, out: Path, inject_wrong_expected: bool = False) -> list[dict]:
    selected = []
    addresses = {0x5000, 0x5040, 0x5080, 0x50C0, 0x5100, 0x5101}
    with path.open(newline="", encoding="utf-8-sig") as stream:
        for row in csv.DictReader(stream):
            address = int(row["address"], 16)
            frame = int(row["frame"])
            if row["kind"] == "W" and address in addresses and 2400 <= frame <= 2402:
                data = int(row["data"], 16)
                expected = ((data + 1) & 0xFF) if address in (0x5040, 0x50C0) else data
                selected.append({"frame": frame, "address": address, "data": data, "expected": expected})
    if not selected:
        raise RuntimeError("no accepted CPU register writes found in bounded frame replay interval")
    if inject_wrong_expected:
        selected[0]["expected"] ^= 1
    lines = [f"replay_event(16'h{row['address']:04X}, 8'h{row['data']:02X}, 8'h{row['expected']:02X}, {row['frame']});" for row in selected]
    (out / "replay_events.svh").write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return selected


def source_oracle() -> tuple[list[dict], dict]:
    lines = MAME.read_text(encoding="utf-8").splitlines()
    selected = []
    for needle in (
        "map(0x5000, 0x5000).mirror(0x003f)",
        "map(0x5040, 0x5040).mirror(0x003f)",
        "map(0x5080, 0x5080).mirror(0x003f)",
        "map(0x50c0, 0x50c0).mirror(0x003f)",
        "void exidy_state::venture(machine_config &config)",
        "exidy_video_config(0x04, 0x04, false);",
        "inline int exidy_state::sprite_1_enabled()",
        "return (!(*m_sprite_enable & 0x80) || (*m_sprite_enable & 0x10) || (m_collision_mask == 0x00));",
        "int sprite_set_2 = ((*m_sprite_enable & 0x40) != 0);",
        "int sprite_set_1 = ((*m_sprite_enable & 0x20) != 0);",
        "int sx = 236 - *m_sprite2_xpos - 4;",
        "int sy = 244 - *m_sprite2_ypos - 4;",
        "if ((current_collision_mask & m_collision_mask) && count < 128)",
    ):
        ix = next((i for i, line in enumerate(lines) if needle in line), None)
        if ix is None:
            raise RuntimeError(f"pinned MAME source missing expected anchor {needle!r}")
        selected.append({"line": ix + 1, "text": lines[ix].strip()})
    if sha256(MAME) != PINNED_MAME_EXIDY_SHA256:
        raise RuntimeError("pinned exidy.cpp hash changed")

    # Independent policy oracle from MAME's public register map/configuration comments.
    cases = []
    for m1, m2, bg, blank in ((1,0,1,0),(0,1,1,0),(1,1,0,0),(1,1,1,0),(1,0,1,1),(0,0,1,0)):
        rtl_cdet = bool((m1 and bg) or (m2 and bg)) and not bool(blank)
        venture_collision_irq = bool(m1 and bg) and not bool(blank)  # mask 0x04 excludes M2CHAR/M1M2.
        cases.append({"m1":m1,"m2":m2,"background":bg,"blank":blank,
                      "mameVentureCollisionEventExpected":venture_collision_irq,
                      "rtlExtractedCdetExpected":rtl_cdet,
                      "expectedDifference":venture_collision_irq != rtl_cdet})
    return selected, {"ventureCollisionMask": "04", "ventureCollisionInvert": "04",
                      "mameSprite1ScreenX": "236 - x - 4", "mameSprite1ScreenY": "244 - y - 4",
                      "collisionCases": cases}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-only", action="store_true", help="extract/check and write reports without invoking WSL/Verilator")
    parser.add_argument("--run", default="active03")
    parser.add_argument("--inject-wrong-expected", action="store_true", help="deliberately corrupt the first replay oracle byte; expected to fail in RTL check")
    parser.add_argument("--build-name", default="build", help="unique ignored build subdirectory name")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.build_name):
        parser.error("--build-name must contain only letters, digits, underscore, or hyphen")
    out = ROOT / "simulation/sprite_fixture/generated"
    out.mkdir(parents=True, exist_ok=True)
    fragment, _ = extract_rtl(out)
    mame_lines, oracle = source_oracle()
    (out / "pinned_mame_source_lines.json").write_text(json.dumps(mame_lines, indent=2) + "\n", encoding="utf-8")
    run_dir = ROOT / "simulation/venture_startup" / args.run
    replay = replay_trace(run_dir / "bus.csv")
    replay_events = emit_replay_include(run_dir / "bus.csv", out, args.inject_wrong_expected)
    report = {
        "fixtureKind": "source-extracted RTL fragment simulation plus accepted MAME bus-event replay",
        "fullCPUorGameRenderer": False,
        "arrowIdentityProven": False,
        "rtlExidy2Sha256": sha256(RTL),
        "pinnedMameExidyCppSha256": sha256(MAME),
        "harnessDriverSha256": sha256(Path(__file__).resolve()),
        "testbenchSha256": sha256(ROOT / "sim/sprite_fixture/tb_sprite_fixture.sv"),
        "extractedFragmentSha256": hashlib.sha256(fragment.encode()).hexdigest().upper(),
        "mameSourceLines": mame_lines,
        "independentMameOracle": oracle,
        "capturedEventReplay": replay,
        "rtlReplayExcerpt": {"frameRange": [2400, 2402], "eventCount": len(replay_events),
                             "events": replay_events, "generatedInclude": "simulation/sprite_fixture/generated/replay_events.svh"},
        "faultInjection": "first independent expected byte XOR 1" if args.inject_wrong_expected else None,
        "firstDivergences": [
            {"case":"mirrored sprite address $503F", "MAME_expected":"sprite-1-X bank accepts mirror; latched data 0x99",
             "RTL_extracted":"exact compare rejects mirror; prior latched data 0x21 remains", "provenance":"synthetic address-boundary probe; accepted bus tap canonicalizes aliases"},
            {"case":"Venture sprite-2/background overlap", "MAME_expected":"no collision IRQ for this pixel class under mask 0x04",
             "RTL_extracted":"cDET=1 outside blanking; IRQ equation can latch it", "provenance":"synthetic pixel probe; no event timing inferred from MAME frame trace"},
            {"case":"Venture sprite-1/background overlap polarity", "MAME_expected":"collision input 0x04 XOR invert 0x04 -> latched bit 2 low",
             "RTL_extracted":"EIR[2] is active-high sprite1/background overlap", "provenance":"source policy comparison; not CPU-visible whole-system read proof"},
        ],
        "limitations": ["synthetic pixel/address probes only", "accepted bus addresses were canonicalized", "no ROM bytes or game images embedded", "no arrow identity claim", "not cycle-accurate MAME collision scheduling", "no full CPU/game-rendering RTL simulation"],
    }
    (out / "fixture-report.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"EXTRACT PASS RTL={report['rtlExidy2Sha256']} fragment={report['extractedFragmentSha256']}")
    print(f"REPLAY PASS {replay['path']} rows={sum(replay['writeCounts'].values())} right-fire-coordinate-rows={replay['rightFireWindowCoordinateWriteRows']}")
    print(f"ORACLE Venture collision mask/invert={oracle['ventureCollisionMask']}/{oracle['ventureCollisionInvert']}; {sum(x['expectedDifference'] for x in oracle['collisionCases'])} of {len(oracle['collisionCases'])} selected cases differ from extracted aggregate cDET")
    if not args.build_only:
        makefile = ROOT / "sim/sprite_fixture/Makefile"
        import subprocess
        root_wsl = "/mnt/" + ROOT.drive[0].lower() + ROOT.as_posix()[2:]
        makefile_wsl = root_wsl + "/sim/sprite_fixture"
        build_dir = f"../../simulation/sprite_fixture/{args.build_name}"
        command = f"cd '{makefile_wsl}' && make BUILD_DIR={build_dir} GEN_DIR=../../simulation/sprite_fixture/generated"
        proc = subprocess.run(["wsl.exe", "-d", "archlinux", "-e", "bash", "-lc", command], text=True, capture_output=True)
        (out / f"{args.build_name}.stdout.log").write_text(proc.stdout + proc.stderr, encoding="utf-8")
        if proc.returncode:
            print(proc.stdout)
            print(proc.stderr)
            raise SystemExit(proc.returncode)
        print(proc.stdout.strip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
