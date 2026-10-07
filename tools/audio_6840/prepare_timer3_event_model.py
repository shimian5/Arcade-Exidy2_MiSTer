#!/usr/bin/env python3
"""Create a simulation-only debug-port copy for the timer-3 event fixture."""

import argparse
import hashlib
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "modules/6840/berzerk_sound_fx.vhd"
EXPECTED_SHA256 = "CC8A67374B764B4DB58B6FF4509BBA742F2469070F26FFC0E655AC501156BAB7"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "simulation/audio_6840_timer3/berzerk_sound_fx.vhd")
    args = parser.parse_args()
    args.output = args.output.resolve()
    args.output.relative_to((ROOT / "simulation").resolve())
    source_bytes = SOURCE.read_bytes()
    digest = hashlib.sha256(source_bytes).hexdigest().upper()
    if digest != EXPECTED_SHA256:
        raise SystemExit(f"production source hash changed: {digest}")
    source = source_bytes.decode("utf-8").replace("\r\n", "\n")

    source, count = re.subn(
        r"snd3\s+: out signed\(8 downto 0\)\s*\n\);",
        "snd3 : out signed(8 downto 0);\n"
        "\tnoise_debug : out std_logic_vector(127 downto 0);\n"
        "\texternal_debug : out std_logic;\n"
        "\tpre3_debug : out std_logic_vector(2 downto 0);\n"
        "\traw3_debug : out std_logic;\n"
        "\ttick3_debug : out std_logic;\n"
        "\tcnt3_debug : out std_logic_vector(15 downto 0);\n"
        "\tq3_debug : out std_logic\n);",
        source,
    )
    assert count == 1, "entity-port anchor changed"

    guards = {
        r"signal noise_xor, noise_xor_r : std_logic;":
            "signal noise_xor, noise_xor_r : std_logic := '0'; -- simulation guard; MAME reset oldxor=0",
        r"signal noise_shift_reg_95_r : std_logic;":
            "signal noise_shift_reg_95_r : std_logic := '0'; -- simulation-only edge-history guard",
        r"signal ena_external_clock : std_logic;":
            "signal ena_external_clock : std_logic := '0'; -- simulation-only pulse guard",
    }
    for anchor, replacement in guards.items():
        source, count = re.subn(anchor, replacement, source)
        assert count == 1, f"guard anchor changed: {anchor}"

    source, count = re.subn(
        r"begin\n\n--sample",
        "begin\n\n"
        "noise_debug <= noise_shift_reg;\n"
        "external_debug <= ena_external_clock;\n"
        "pre3_debug <= std_logic_vector(pre3);\n"
        "raw3_debug <= raw3;\n"
        "tick3_debug <= tick3;\n"
        "cnt3_debug <= ptm6840_cnt3;\n"
        "q3_debug <= ptm6840_q3;\n\n"
        "--sample",
        source,
    )
    assert count == 1, "architecture output anchor changed"

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(source, encoding="utf-8")
    args.output.with_suffix(".source.sha256").write_text(
        f"{digest}  modules/6840/berzerk_sound_fx.vhd\n", encoding="ascii"
    )
    print(f"PASS generated guarded model from production SHA256 {digest}")


if __name__ == "__main__":
    main()
