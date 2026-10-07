#!/usr/bin/env python3
"""Guard the selected-T65 write fixture against changes to live write decodes."""
from __future__ import annotations

import hashlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def normalize(line: str) -> str:
    return re.sub(r"\s+", "", line.split("//", 1)[0])


def exact_source_line(source: str, anchor: str, expected: str) -> None:
    matches = [line for line in source.splitlines() if anchor in line and not line.lstrip().startswith("//")]
    if len(matches) != 1 or normalize(matches[0]) != normalize(expected):
        raise SystemExit(f"FAIL write-strobe source guard: production equation changed: {anchor}")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main() -> int:
    core_path = ROOT / "rtl/Exidy2.v"
    audio_path = ROOT / "rtl/audio_board.v"
    fixture_path = ROOT / "sim/teeter_nmi/tb_t65_write_strobes.vhd"
    core = core_path.read_text(encoding="utf-8")
    audio = audio_path.read_text(encoding="utf-8")
    fixture = fixture_path.read_text(encoding="utf-8")

    for line in (
        "assign nWM2V = (CPU_addrbus[15:0]==16'h50C0 & !CPU_RWn );",
        "assign nWM2H = (CPU_addrbus[15:0]==16'h5080 & !CPU_RWn );",
        "assign nWM1V = (CPU_addrbus[15:0]==16'h5040 & !CPU_RWn );",
        "assign nWM1H = (CPU_addrbus[15:0]==16'h5000 & !CPU_RWn );",
        "wire nWMOL = !(!IOSEL & CPU_addrbus[1:0]==2'b00 & !CPU_RWn);",
        "wire nWCPL = !(!IOSEL & CPU_addrbus[1:0]==2'b01 & !CPU_RWn);",
    ):
        exact_source_line(core, line.split(" = ")[0], line)
    exact_source_line(core, "cencnt[5:0] == 6'd31", "PH_1 <= cencnt[5:0] == 6'd31;")
    exact_source_line(core, "cencnt  <=", "cencnt <= cencnt+7'd1;")
    if ".enable(PH_1)" not in core or ".rdy(~pause)" not in core:
        raise SystemExit("FAIL write-strobe source guard: T65 PH_1/RDY binding changed")
    exact_source_line(audio, "wire WEVEN =", "wire WEVEN = !ABSEL & !CPU_RWn & !CPU_addrbus[0];")
    exact_source_line(audio, "wire WODD  =", "wire WODD  = !ABSEL & !CPU_RWn &  CPU_addrbus[0];")

    for address in ("5000", "5040", "5080", "50C0", "5100", "5101", "5200", "5201"):
        if f'x"{address}"' not in fixture:
            raise SystemExit(f"FAIL write-strobe source guard: fixture does not include ${address}")
    for token in ("wait until rising_edge(clk)", "if phase_count = 31 then enable <= '1'", "if phase_count = 63 then phase_count <= 0", "enable = '1'", "rdy <= '0'", "rdy <= '1'", "address(15 downto 0) = last_address", "strobe_edge_capture : process"):
        if token not in fixture:
            raise SystemExit(f"FAIL write-strobe source guard: fixture missing bus/PH1/pause evidence {token!r}")

    print("PASS T65 write-strobe source guard: current nWM/nWMO/W* equations and fixture coverage match")
    print(f"rtl/Exidy2.v SHA256={sha256(core_path)}")
    print(f"rtl/audio_board.v SHA256={sha256(audio_path)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
