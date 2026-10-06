#!/usr/bin/env python3
"""Extract and measure the Exidy raw raster RTL with Verilator."""
from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation" / "raster"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract(source: str, start: str, end: str) -> str:
    a = source.index(start)
    b = source.index(end, a) + len(end)
    return source[a:b]


def write_fixture() -> dict:
    src_path = ROOT / "rtl" / "Exidy2.v"
    source = src_path.read_text(encoding="utf-8")
    clock = extract(source, "reg CLK22,CLK11;", "assign core_pix_clk=BCLK;")
    raster = extract(source, "reg [5:0] hscnt =6'd0;", "wire BLANK = (V_BLANK|H_BLANK);")
    for marker in ("cencnt  <= cencnt+7'd1;", "hscnt  <= (hscnt[5:0]==6'b100000) ? mod_shift[5:0] : hscnt+6'd1;", "vscnt <= (vscnt==9'd280) ? 9'd0 :", "VL1  <= ((vscnt==9'd256)&(hscnt==60));"):
        if marker not in clock + raster:
            raise RuntimeError(f"Expected source marker missing: {marker}")
    wrapper = """`timescale 1ns/1ps
module exidy_raster(input wire master_clock, input wire [7:0] mod_shift,
 output wire core_pix_clk, output wire H_SYNC, output wire V_SYNC,
 output wire H_BLANK, output wire V_BLANK);
reg CLK22,CLK11;
reg BCLK,BCLKB,HCLK,CLD,BCLKX;
reg PH_1x,PH_1,PH_6,PH_6B,PH_6C,CCRY;
reg HCNT;
reg [6:0] cencnt=7'd0;
""" + clock[clock.index("always @(posedge master_clock)"):]
    wrapper += "\n" + raster + "\nendmodule\n"
    tb_path = ROOT / "sim" / "raster" / "tb.sv"
    tb = tb_path.read_text(encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "extracted_raster.sv").write_text(wrapper, encoding="utf-8")
    (OUT / "tb.sv").write_text(tb, encoding="utf-8")
    return {"source": str(src_path.relative_to(ROOT)).replace("\\", "/"), "sourceSha256": sha256(src_path), "extractedMarkers": ["reg CLK22,CLK11;", "assign core_pix_clk=BCLK;", "reg [5:0] hscnt =6'd0;", "wire BLANK = (V_BLANK|H_BLANK);"], "generatedRtlSha256": sha256(OUT / "extracted_raster.sv"), "testbenchTemplate": "sim/raster/tb.sv", "testbenchSha256": sha256(tb_path)}


def file_byte(path: pathlib.Path) -> int:
    root = ET.parse(path).getroot()
    part = root.find("./rom[@index='2']/part")
    if part is None or not part.text:
        raise RuntimeError(f"Missing ROM index 2 byte in {path.name}")
    token = part.text.strip().split()[0]
    # MRA inline part text is a sequence of hexadecimal byte tokens.
    return int(token, 16)


def parse_rows(text: str) -> list[tuple[int, ...]]:
    rows = []
    for line in text.splitlines():
        if not re.match(r"^\d+,", line):
            continue
        rows.append(tuple(map(int, line.split(","))))
    return rows


def spans(values: list[int], target: int) -> list[tuple[int, int]]:
    result = []
    start = None
    for i, value in enumerate(values + [1 - target]):
        if value == target and start is None:
            start = i
        elif value != target and start is not None:
            result.append((start, i))
            start = None
    return result


def measure(rows: list[tuple[int, ...]], master_hz: float) -> dict:
    # columns: master-edge sample, pixel marker, h, hprev, v, VL1, HS, VS, HB, VB
    n = len(rows)
    hs_spans = spans([r[6] for r in rows], 1)
    vs_spans = spans([r[7] for r in rows], 1)
    hb_spans = spans([r[8] for r in rows], 1)
    vb_spans = spans([r[9] for r in rows], 1)
    vl_spans = spans([r[5] for r in rows], 1)
    line_starts = [i for i in range(1, n) if rows[i][2] < rows[i - 1][2]]
    frame_starts = [i for i in range(1, n) if rows[i][4] < rows[i - 1][4]]
    # Count unique raster coordinate states in stable complete intervals.
    def diffs(points: list[int]) -> list[int]:
        return [b - a for a, b in zip(points, points[1:])]
    line_periods = diffs(line_starts)
    frame_periods = diffs(frame_starts)
    frame0 = frame_starts[0] if frame_starts else 0
    frame1 = frame_starts[1] if len(frame_starts) > 1 else n
    active_by_line = []
    full_line_starts = [i for i in line_starts if frame0 <= i and i + (line_periods[0] if line_periods else 0) <= frame1]
    for start in full_line_starts:
        stop = start + (line_periods[0] if line_periods else 0)
        if stop > start and rows[start][9] == 0:
            active_by_line.append(sum(1 for r in rows[start:stop] if not r[8] and not r[9]))
    hsw = [b - a for a, b in hs_spans if b < n]
    vsw = [b - a for a, b in vs_spans if b < n]
    vlcad = diffs([a for a, _ in vl_spans])
    def phase(event_spans: list[tuple[int, int]], interval_start: int, interval_stop: int, origin_points: list[int], period: int) -> dict | None:
        events = [a for a, _ in event_spans if interval_start <= a < interval_stop]
        if not events:
            return None
        event = events[0]
        prior = max((point for point in origin_points if point <= event), default=None)
        return {"withinFramePixelClocks": event - interval_start, "withinFrameMasterCycles": rows[event][0] - rows[interval_start][0], "withinLinePixelClocks": event - prior if prior is not None else None, "withinLineMasterCycles": rows[event][0] - rows[prior][0] if prior is not None else None, "pulseWidthPixelClocks": next((b-a for a,b in event_spans if a==event), None), "pulseWidthMasterCycles": next((rows[b][0]-rows[a][0] for a,b in event_spans if a==event and b < n), None)}
    frame_end = frame1
    line_points = line_starts
    pixel_master_diffs = [b[0] - a[0] for a,b in zip(rows, rows[1:])]
    measured_line = max(set(line_periods), key=line_periods.count) if line_periods else None
    measured_frame = max(set(frame_periods), key=frame_periods.count) if frame_periods else None
    active_line_count = len(set(r[4] for r in rows[frame0:frame1] if r[9] == 0)) if frame1 > frame0 else None
    checks = {
      "uniform8MasterCyclesPerPixel": bool(pixel_master_diffs) and set(pixel_master_diffs) == {8},
      "uniform336PixelClocksPerLine": measured_line == 336 and len(set(line_periods)) == 1,
      "uniform94080PixelClocksPerFrame": measured_frame == 94080 and len(set(frame_periods)) == 1,
      "256ActivePixelsPerActiveLine": bool(active_by_line) and set(active_by_line) == {256},
      "256ActiveLinesPerFrame": active_line_count == 256,
    }
    if not all(checks.values()):
        raise RuntimeError(f"Raster independent measurement assertions failed: {checks}")
    hs_phase = phase(hs_spans, frame0, frame_end, line_points, measured_frame or 0)
    vs_phase = phase(vs_spans, frame0, frame_end, line_points, measured_frame or 0)
    hb_phase = phase(hb_spans, frame0, frame_end, line_points, measured_frame or 0)
    vb_phase = phase(vb_spans, frame0, frame_end, line_points, measured_frame or 0)
    vl_phase = phase(vl_spans, frame0, frame_end, line_points, measured_frame or 0)
    return {
      "samples": n,
      "masterCyclesPerPixelClock": sorted(set(pixel_master_diffs)),
      "linePeriodsPixelClocks": line_periods[:8],
      "framePeriodsPixelClocks": frame_periods[:4],
      "totalPixelClocksPerLine": measured_line,
      "totalPixelClocksPerFrame": measured_frame,
      "totalLinesPerFrame": (measured_frame // measured_line) if measured_frame and measured_line else None,
      "frameRateHzFromPll": (master_hz / 8) / frame_periods[0] if frame_periods else None,
      "activePixelsPerActiveLineCounts": sorted(set(active_by_line)),
      "activeLinesPerFrame": active_line_count,
      "hsHighWidthsPixelClocks": sorted(set(hsw)),
      "vsHighWidthsPixelClocks": sorted(set(vsw)),
      "hblankHighWidthsByLine": sorted(set(b - a for a, b in spans([r[8] for r in rows], 1) if b < n)),
      "vblankHighWidthsPixelClocks": sorted(set(b-a for a,b in vb_spans if b < n)),
      "vblankLineValues": sorted(set(r[4] for r in rows if r[9] == 1)),
      "vl1HighWidthsPixelClocks": sorted(set(b - a for a, b in vl_spans if b < n)),
      "vl1StartCadencePixelClocks": vlcad[:5],
      "normalizedPhasesFromStableFrameOrigin": {"HS": hs_phase, "HB": hb_phase, "VS": vs_phase, "VB": vb_phase, "VL1": vl_phase},
      "stableFrameOrigin": {"pixelIndex": frame0, "masterCycle": rows[frame0][0], "hscnt": rows[frame0][2], "vscnt": rows[frame0][4], "offsetWithinLinePixelClocks": (frame0 - max((i for i in line_starts if i <= frame0), default=frame0))},
      "initialCoordinates": [list(r[2:5]) for r in rows[:4]],
      "firstFrameStartSample": frame_starts[0] if frame_starts else None,
      "firstLineStartSample": line_starts[0] if line_starts else None,
      "hsAssertAt": hs_spans[0][0] if hs_spans else None,
      "vsAssertAt": vs_spans[0][0] if vs_spans else None,
      "vl1AssertAt": vl_spans[0][0] if vl_spans else None,
      "independentMeasurementChecks": checks,
    }


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--verilator", default="verilator")
    p.add_argument("--run-dir", type=pathlib.Path, default=OUT)
    args = p.parse_args()
    meta = write_fixture()
    run_dir = args.run_dir.resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    exe = run_dir / "raster_sim"
    subprocess.run([args.verilator, "--binary", "--timing", "-Wno-fatal", "--top-module", "tb", "--Mdir", str(run_dir / "obj_dir"), str(OUT / "extracted_raster.sv"), str(OUT / "tb.sv"), "-o", str(exe)], check=True)
    pll = (ROOT / "rtl" / "pll.v").read_text(encoding="utf-8", errors="replace")
    pll_impl_path = ROOT / "rtl" / "pll" / "pll_0002.v"
    pll_impl = pll_impl_path.read_text(encoding="utf-8", errors="replace")
    pll_actual_match = re.search(r'output_clock_frequency0\("([0-9.]+) MHz"\)', pll_impl)
    pll_desired_match = re.search(r'gui_output_clock_frequency0" value="([^"]+)', pll)
    pll_actual_mhz = float(pll_actual_match.group(1)) if pll_actual_match else None
    if pll_actual_mhz is None:
        raise RuntimeError("Could not read instantiated PLL output clock frequency from rtl/pll/pll_0002.v")
    mras = sorted((ROOT / "releases").glob("*.mra"))
    results = []
    for mra in mras:
        shift = file_byte(mra) & 0x3F
        run = subprocess.run([str(exe), f"+SHIFT={shift}", "+SAMPLES=250000"], check=True, capture_output=True, text=True)
        data_path = run_dir / (mra.stem.replace(" ", "_") + ".csv")
        data_path.write_text(run.stdout, encoding="utf-8")
        rows = parse_rows(run.stdout)
        results.append({"mra": str(mra.relative_to(ROOT)).replace("\\", "/"), "mraSha256": sha256(mra), "modShiftByteHex": f"0x{shift:02x}", "modShiftDecimal": shift, "measurements": measure(rows, pll_actual_mhz * 1_000_000), "rawCsv": str(data_path.relative_to(ROOT)).replace("\\", "/")})
    payload = {"schema": "exidy2-native-raster-measurement/v1", "method": "Verilator simulation of automatically extracted counter/clock/sync/blank/VL1 RTL spans", "verilator": subprocess.run([args.verilator, "--version"], check=True, capture_output=True, text=True).stdout.strip(), "sourceFiles": {"rtl/Exidy2.v": sha256(ROOT / "rtl" / "Exidy2.v"), "Arcade-Exidy2.sv": sha256(ROOT / "Arcade-Exidy2.sv"), "rtl/pll.v": sha256(ROOT / "rtl" / "pll.v"), "rtl/pll/pll_0002.v": sha256(pll_impl_path), "rtl/pll.qip": sha256(ROOT / "rtl" / "pll.qip")}, "fixture": meta, "pll": {"wrapperDesiredOutput0MHz": float(pll_desired_match.group(1)) if pll_desired_match else None, "instantiatedGeneratedOutput0MHz": pll_actual_mhz, "frequencyBasis": "45.153061 MHz from rtl/pll/pll_0002.v output_clock_frequency0; generated PLL configuration metadata, not a measured silicon frequency. Wrapper wizard GUI desired setting is 45.156 MHz and rtl/pll.v also contains a stale/inconsistent actual-output annotation of 10.079999 MHz."}, "results": results}
    (run_dir / "measurements.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    audit_json = ROOT / "docs" / "audits" / "raster" / "measurements.json"
    audit_json.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(run_dir / "measurements.json", audit_json)
    print(json.dumps({"measurements": str((run_dir / "measurements.json").relative_to(ROOT)), "profiles": len(results), "pll": payload["pll"], "summary": [{"mra": x["mra"], **x["measurements"]} for x in results]}, indent=2))


if __name__ == "__main__":
    main()
