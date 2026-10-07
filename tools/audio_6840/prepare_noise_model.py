#!/usr/bin/env python3
"""Create a guarded, debug-port-only copy of the production 6840 for GHDL."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "modules/6840/berzerk_sound_fx.vhd"
OUT = ROOT / "simulation/harness/a4_noise_ghdl/berzerk_sound_fx.vhd"
source_bytes = SRC.read_bytes()
source = source_bytes.decode("utf-8").replace("\r\n", "\n")
digest = hashlib.sha256(source_bytes).hexdigest()
if digest.lower() != "cc8a67374b764b4db58b6ff4509bba742f2469070f26ffc0e655ac501156bab7":
    raise RuntimeError("Production 6840 changed; review the noise model instrumentation before regenerating")
assert "noise_xor_r" in source and "noise_shift_reg(95)" in source

source, n = re.subn(
    r"snd3\s+: out signed\(8 downto 0\)\s*\n\);",
    "snd3 : out signed(8 downto 0);\n\tnoise_debug : out std_logic_vector(127 downto 0);\n\texternal_debug : out std_logic\n);",
    source,
)
assert n == 1, "production entity port anchor changed"
source, n = re.subn(
    r"signal noise_xor, noise_xor_r : std_logic;",
    "signal noise_xor, noise_xor_r : std_logic := '0'; -- simulation guard for omitted RTL reset",
    source,
)
assert n == 1, "production LFSR state anchor changed"
source, n = re.subn(r"signal noise_shift_reg_95_r : std_logic;", "signal noise_shift_reg_95_r : std_logic := '0'; -- simulation-only startup guard", source)
assert n == 1, "production tap-history anchor changed"
source, n = re.subn(r"signal ena_external_clock : std_logic;", "signal ena_external_clock : std_logic := '0'; -- simulation-only startup guard", source)
assert n == 1, "production external-enable anchor changed"
source, n = re.subn(r"begin\n\n--sample", "begin\n\nnoise_debug <= noise_shift_reg;\nexternal_debug <= ena_external_clock;\n\n--sample", source)
assert n == 1, "production architecture anchor changed"
dest = OUT
dest.parent.mkdir(parents=True, exist_ok=True)
dest.write_text(source, encoding="utf-8")
(dest.parent / "source.sha256").write_text(digest + "  modules/6840/berzerk_sound_fx.vhd\n", encoding="ascii")
print(f"PASS guarded simulation model generated from production SHA256 {digest}")
