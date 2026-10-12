#!/usr/bin/env python3
"""Prepare reproducible MAME-derived coefficients and sample vectors.

Run from the repository root. All generated files stay under the ignored
simulation/reference_sources/mc3417_filter_generated directory.
"""

from __future__ import annotations

import csv
import argparse
import hashlib
import json
import math
import random
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "simulation/reference_sources"
OUT = SRC / "mc3417_filter_generated"
FS = 192_000.0
Q24 = 1 << 24
Q28 = 1 << 28
PREFILTER_ROUTE_GAIN = 0.3086
FIRMWARE_PCM = None
PINS = {
    "flt_biquad.cpp": "c5c3bfa36c889362313bd4e8c18a27c471e877585fef5059f700ad1384c41190",
    "flt_biquad.h": "cda165401b980b05e9bf39e1085c89aa4db595b5657f895508c80ce6845da9e5",
    "exidysound.cpp": "57c0edc71e9faf0a37e48eef406586e95a95902ef0f9e53275a7ad3326fad660",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def derive() -> dict:
    actual_hashes = {name: sha256(SRC / name) for name in PINS}
    if actual_hashes != PINS:
        differences = [f"{name}: expected {PINS[name]}, got {actual_hashes[name]}"
                       for name in PINS if actual_hashes[name] != PINS[name]]
        raise SystemExit("Pinned MAME source changed; refusing to generate oracle vectors:\n" + "\n".join(differences))
    # Values and equations are those of opamp_mfb_lowpass_calc() followed by
    # filter_biquad_device::recalc() in the pinned flt_biquad.cpp.
    r1, r2, r3 = 10_000.0, 3_900.0, 18_000.0
    c1, c2 = 20e-9, 2.2e-9
    gain = -r3 / r1
    fc = 1.0 / (2.0 * math.pi * math.sqrt(r2 * r3 * c1 * c2))
    q = math.sqrt(r2 * r3 * c1 * c2) / (r3 * c2 + r2 * c2 + (r2 * c2) * -gain)
    k = math.tan(math.pi * fc / FS)
    normal = 1.0 / (1.0 + k / q + k * k)
    b0 = k * k * normal
    b1, b2 = 2.0 * b0, b0
    a1 = 2.0 * (k * k - 1.0) * normal
    a2 = (1.0 - k / q + k * k) * normal
    # MAME applies the analog circuit gain after the LOWPASS coefficients.
    coeff = [b0 * gain, b1 * gain, b2 * gain, a1, a2]
    return {
        "sample_rate_hz": int(FS),
        "prefilter_route_gain": PREFILTER_ROUTE_GAIN,
        "topology": "opamp_mfb_lowpass",
        "components_ohms_farads": {"R1": r1, "R2": r2, "R3": r3, "C1": c1, "C2": c2},
        "analog": {"gain": gain, "cutoff_hz": fc, "q": q},
        "mame_coefficients_order_b0_b1_b2_a1_a2": coeff,
        "q28_nearest_integer_order_b0_b1_b2_a1_a2": [round(v * Q28) for v in coeff],
        "single_stage_dc_gain": sum(coeff[:3]) / (1.0 + coeff[3] + coeff[4]),
        "two_stage_dc_gain": (sum(coeff[:3]) / (1.0 + coeff[3] + coeff[4])) ** 2,
        "source_sha256": actual_hashes,
    }


def stimuli() -> list[tuple[str, list[int]]]:
    cases: list[tuple[str, list[int]]] = []
    for name, amp in (("impulse_pos_half", Q24 // 2), ("impulse_neg_half", -(Q24 // 2))):
        cases.append((name, [amp] + [0] * 255))
    for name, amp in (("step_pos_quarter", Q24 // 4), ("step_neg_quarter", -(Q24 // 4))):
        cases.append((name, [0] * 16 + [amp] * 1024))
    cases.append(("dc_settle_quarter", [Q24 // 4] * 8192))
    for hz in (1_000, 10_000):
        values = [round((Q24 / 4) * math.sin(2 * math.pi * hz * n / FS)) for n in range(2048)]
        cases.append((f"tone_{hz}hz_quarter", values))
    rng = random.Random(0x3417_2026)
    cases.append(("random_seed_34172026", [rng.randint(-(Q24 // 4), Q24 // 4) for _ in range(2048)]))
    # Exercise final 16-bit clipping while retaining internal filter headroom.
    cases.append(("step_pos_two", [Q24 * 2] * 1024))
    cases.append(("step_neg_two", [-Q24 * 2] * 1024))
    if FIRMWARE_PCM is not None:
        with FIRMWARE_PCM.open(encoding="utf-8") as stream:
            values = [int(row["pcm_q24"]) for row in csv.DictReader(stream)]
        if not values or any(not -(1 << 31) <= x < (1 << 31) for x in values):
            raise SystemExit("Invalid firmware renderer PCM input")
        cases.append(("firmware_renderer_replay", values))
    return cases


def make_cpp_oracle() -> Path:
    """Build a small standalone harness around the pinned source step() body."""
    source = (SRC / "flt_biquad.cpp").read_text(encoding="utf-8")
    match = re.search(r"void filter_biquad_device::step\(\)\s*\{(?P<body>.*?)\n\}", source, re.S)
    if not match:
        raise SystemExit("Could not extract filter_biquad_device::step() from pinned source")
    body = match.group("body")
    harness = r'''#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif
#ifndef M_SQRT2
#define M_SQRT2 1.41421356237309504880
#endif
struct Filter {
  float m_input = 0.0f;
  double m_w0 = 0.0, m_w1 = 0.0, m_w2 = 0.0;
  float m_output = 0.0f;
  double m_a1 = 0.0, m_a2 = 0.0, m_b0 = 0.0, m_b1 = 0.0, m_b2 = 0.0;
  void step() {
__STEP_BODY__
  }
};
static void configure(Filter &f) {
  const double r1=10000.0, r2=3900.0, r3=18000.0, c1=20e-9, c2=2.2e-9, fs=192000.0;
  const double gain=-r3/r1;
  const double fc=1.0/(2.0*M_PI*std::sqrt(r2*r3*c1*c2));
  const double q=std::sqrt(r2*r3*c1*c2)/(r3*c2+r2*c2+(r2*c2)*-gain);
  const double K=std::tan(M_PI*fc/fs), Ksquared=K*K, KoverQ=K/q;
  const double normal=1.0/(1.0+KoverQ+Ksquared);
  f.m_b0=Ksquared*normal;
  f.m_b1=2.0*f.m_b0;
  f.m_b2=f.m_b0;
  f.m_a1=2.0*(Ksquared-1.0)*normal;
  f.m_a2=(1.0-KoverQ+Ksquared)*normal;
  f.m_b0*=gain; f.m_b1*=gain; f.m_b2*=gain;
}
int main(int argc, char **argv) {
  if (argc != 4) return 2;
  std::ifstream input(argv[1]); std::ofstream output(argv[2]), coeffout(argv[3]);
  if (!input || !output || !coeffout) return 3;
  std::string name, previous; int sample; long long xq;
  Filter first, second; configure(first); configure(second);
  coeffout << std::setprecision(17) << first.m_b0 << '\n' << first.m_b1 << '\n' << first.m_b2 << '\n' << first.m_a1 << '\n' << first.m_a2 << '\n';
  output << std::setprecision(9);
  while (input >> name >> sample >> xq) {
    if (name != previous) { first=Filter{}; second=Filter{}; configure(first); configure(second); previous=name; }
    first.m_input = static_cast<float>((static_cast<double>(xq) / 16777216.0) * 0.3086);
    first.step(); second.m_input=first.m_output; second.step();
    output << name << '\t' << sample << '\t' << xq << '\t'
           << std::llround(static_cast<double>(second.m_output)*16777216.0) << '\t'
           << second.m_output << '\n';
  }
  return 0;
}
'''.replace("__STEP_BODY__", body)
    path = OUT / "mame_step_oracle.cpp"
    path.write_text(harness, encoding="utf-8")
    return path


def compile_and_run_oracle(harness: Path) -> list[float]:
    compiler = next((shutil.which(name) for name in ("g++", "c++", "clang++") if shutil.which(name)), None)
    if compiler is None:
        raise SystemExit("No g++/c++/clang++ compiler found. Harness is prepared; run this script on a host with a C++ compiler.")
    exe = OUT / ("mame_step_oracle.exe" if sys.platform == "win32" else "mame_step_oracle")
    inputs = OUT / "stimulus_inputs.txt"
    raw_vectors = OUT / "mame_oracle_vectors.txt"
    with inputs.open("w", encoding="ascii", newline="\n") as f:
        for name, values in stimuli():
            for i, value in enumerate(values):
                f.write(f"{name} {i} {value}\n")
    subprocess.run([compiler, "-std=c++17", "-O2", str(harness), "-o", str(exe)], check=True)
    c_coeff = OUT / "cpp_coefficients.txt"
    subprocess.run([str(exe), str(inputs), str(raw_vectors), str(c_coeff)], check=True)
    return [float(v) for v in c_coeff.read_text(encoding="ascii").splitlines()]


def finalize_outputs(meta: dict) -> int:
    raw_vectors = OUT / "mame_oracle_vectors.txt"
    if not raw_vectors.exists():
        raise SystemExit("C++ oracle output is missing; compile and run the prepared harness first.")
    rows = 0
    with (OUT / "vectors.csv").open("w", newline="", encoding="utf-8") as csv_file, \
         (OUT / "vectors.tsv").open("w", newline="", encoding="utf-8") as tsv_file:
        writer = csv.writer(csv_file)
        writer.writerow(["case", "sample", "stimulus_q24", "expected_q24", "expected_float"])
        tsv = csv.writer(tsv_file, delimiter="\t", lineterminator="\n")
        with raw_vectors.open(encoding="ascii") as oracle:
            for line in oracle:
                name, sample, xq, outq, outf = line.rstrip("\n").split("\t")
                writer.writerow([name, sample, xq, outq, outf])
                tsv.writerow([name, sample, xq, outq])
                rows += 1
    return rows


def main() -> None:
    global FIRMWARE_PCM
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--firmware-pcm", type=Path)
    args = parser.parse_args()
    FIRMWARE_PCM = args.firmware_pcm
    OUT.mkdir(parents=True, exist_ok=True)
    # Never leave prior oracle vectors looking current after a prepare-only
    # run or a later compiler failure.
    for stale in ("vectors.csv", "vectors.tsv", "mame_oracle_vectors.txt"):
        (OUT / stale).unlink(missing_ok=True)
    meta = derive()
    (OUT / "coefficients.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
    harness = make_cpp_oracle()
    if not args.prepare_only:
        c_coeff = compile_and_run_oracle(harness)
        py_coeff = meta["mame_coefficients_order_b0_b1_b2_a1_a2"]
        if any(abs(a-b) > 1e-14 for a, b in zip(py_coeff, c_coeff)):
            raise SystemExit(f"Python/C++ MAME coefficient parity failed: Python={py_coeff}, C++={c_coeff}")
        meta["cpp_mame_coefficients_order_b0_b1_b2_a1_a2"] = c_coeff
        meta["coefficient_parity"] = "pass"
        (OUT / "coefficients.json").write_text(json.dumps(meta, indent=2) + "\n", encoding="utf-8")
        rows = finalize_outputs(meta)
    else:
        rows = 0
    print(json.dumps({"output_dir": str(OUT), "coefficients": meta["mame_coefficients_order_b0_b1_b2_a1_a2"],
                      "q28": meta["q28_nearest_integer_order_b0_b1_b2_a1_a2"],
                      "two_stage_dc_gain": meta["two_stage_dc_gain"], "vector_rows": rows,
                      "oracle_source": str(harness)}, indent=2))


if __name__ == "__main__":
    main()
