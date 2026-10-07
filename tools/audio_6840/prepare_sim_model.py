#!/usr/bin/env python3
"""Create a guarded, simulation-only initialized copy of the selected 6840 VHDL."""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path


EXPECTED_SOURCE_SHA256 = "CC8A67374B764B4DB58B6FF4509BBA742F2469070F26FFC0E655AC501156BAB7"
INITIALIZATIONS = {
    "signal ena_internal_clock  : std_logic;": "signal ena_internal_clock  : std_logic := '0';",
    "signal ptm6840_msb_buffer : std_logic_vector(7 downto 0);": "signal ptm6840_msb_buffer : std_logic_vector(7 downto 0) := (others => '0');",
    "signal ptm6840_max1 : std_logic_vector(15 downto 0);": "signal ptm6840_max1 : std_logic_vector(15 downto 0) := (others => '0');",
    "signal ptm6840_max2 : std_logic_vector(15 downto 0);": "signal ptm6840_max2 : std_logic_vector(15 downto 0) := (others => '0');",
    "signal ptm6840_max3 : std_logic_vector(15 downto 0);": "signal ptm6840_max3 : std_logic_vector(15 downto 0) := (others => '0');",
    "signal ptm6840_cnt1 : std_logic_vector(15 downto 0);": "signal ptm6840_cnt1 : std_logic_vector(15 downto 0) := (others => '0');",
    "signal ptm6840_cnt2 : std_logic_vector(15 downto 0);": "signal ptm6840_cnt2 : std_logic_vector(15 downto 0) := (others => '0');",
    "signal ptm6840_cnt3 : std_logic_vector(15 downto 0);": "signal ptm6840_cnt3 : std_logic_vector(15 downto 0) := (others => '0');",
    "signal ptm6840_q1 : std_logic;": "signal ptm6840_q1 : std_logic := '0';",
    "signal ptm6840_q2 : std_logic;": "signal ptm6840_q2 : std_logic := '0';",
    "signal ptm6840_q3 : std_logic;": "signal ptm6840_q3 : std_logic := '0';",
    "signal ptm6840_q1_r : std_logic;": "signal ptm6840_q1_r : std_logic := '0';",
    "signal ena_q1_clock : std_logic;": "signal ena_q1_clock : std_logic := '0';",
    "signal noise_xor, noise_xor_r : std_logic;": "signal noise_xor, noise_xor_r : std_logic := '0';",
    "signal noise_shift_reg_95_r : std_logic;": "signal noise_shift_reg_95_r : std_logic := '1';",
    "signal ena_external_clock : std_logic;": "signal ena_external_clock : std_logic := '0';",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="production VHDL source (read only)")
    parser.add_argument("--output", type=Path, required=True, help="simulation-only output copy")
    args = parser.parse_args()

    source = args.source.resolve()
    output = args.output.resolve()
    if source == output:
        parser.error("--output must differ from the production source")

    raw = source.read_bytes()
    observed = sha256(raw)
    if observed != EXPECTED_SOURCE_SHA256:
        raise SystemExit(
            f"refusing to transform unexpected source SHA-256 {observed}; "
            f"expected {EXPECTED_SOURCE_SHA256}"
        )

    text = raw.decode("utf-8-sig")
    for old, new in INITIALIZATIONS.items():
        count = text.count(old)
        if count != 1:
            raise SystemExit(f"expected exactly one source anchor {old!r}, found {count}")
        text = text.replace(old, new, 1)

    output.parent.mkdir(parents=True, exist_ok=True)
    result = text.encode("utf-8")
    output.write_bytes(result)
    print(f"source_sha256={observed}")
    print(f"simulation_copy={output}")
    print(f"simulation_copy_sha256={sha256(result)}")
    print(f"initialized_declarations={len(INITIALIZATIONS)}")


if __name__ == "__main__":
    main()
