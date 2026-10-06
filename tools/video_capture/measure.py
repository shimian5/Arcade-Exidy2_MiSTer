#!/usr/bin/env python3
"""Exercise the checked-in arcade_video/mixer with extracted Exidy raster RTL."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "simulation" / "video_capture"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def span(text: str, start: str, end: str) -> str:
    a = text.index(start)
    b = text.index(end, a) + len(end)
    return text[a:b]


def mra_shift(path: Path) -> int:
    root = ET.parse(path).getroot()
    part = root.find("./rom[@index='2']/part")
    if part is None or not part.text:
        raise RuntimeError(f"Missing index-2 mod_shift byte in {path.name}")
    return int(part.text.strip().split()[0], 16) & 0x3F


def pll_divider_evidence() -> dict:
    qip_path = ROOT / "rtl" / "pll.qip"
    impl_path = ROOT / "rtl" / "pll" / "pll_0002.v"
    parts = {}
    for line in qip_path.read_text(encoding="utf-8").splitlines():
        m = re.search(r'IP_COMPONENT_PARAMETER "([^"]+)"', line)
        if not m:
            continue
        encoded = m.group(1).split("::")
        if len(encoded) != 3:
            continue
        name, value = (base64.b64decode(x).decode("utf-8") for x in encoded[:2])
        if name in ("gui_parameter_list", "gui_parameter_values"):
            parts[name] = value
    if not {"gui_parameter_list", "gui_parameter_values"} <= parts.keys():
        raise RuntimeError("Generated PLL QIP lacks divider parameter metadata")
    names = parts["gui_parameter_list"].split(",")
    values = parts["gui_parameter_values"].split(",")
    if len(names) != len(values):
        raise RuntimeError("Generated PLL QIP divider name/value vectors differ in length")
    params = dict(zip(names, values))
    impl = impl_path.read_text(encoding="utf-8")
    configured_outputs = {
        int(index): float(freq)
        for index, freq in re.findall(r'output_clock_frequency(\d+)\("([0-9.]+) MHz"\)', impl)
        if int(index) < 3
    }
    m_div = int(params["M-Counter Hi Divide"]) + int(params["M-Counter Low Divide"])
    n_div = int(params["N-Counter Hi Divide"]) + int(params["N-Counter Low Divide"])
    c_div = {
        i: int(params[f"C-Counter-{i} Hi Divide"]) + int(params[f"C-Counter-{i} Low Divide"])
        for i in range(3)
    }
    ref_mhz = 50
    output_mhz = {i: ref_mhz * m_div / (n_div * c_div[i]) for i in range(3)}
    assert c_div[1] / c_div[0] == 4
    return {
        "source": "rtl/pll.qip IP_COMPONENT_PARAMETER gui_parameter_list/gui_parameter_values",
        "sha256": sha(qip_path),
        "classification": "generated PLL IP parameter metadata (GUI-named QIP fields); not a Quartus fitted report or silicon measurement",
        "referenceMHz": ref_mhz,
        "M": m_div,
        "N": n_div,
        "C": c_div,
        "reportedVcoMHz": params["PLL Output VCO Frequency"],
        "frequencyFormula": "fout = fin * M / (N * C)",
        "calculatedOutputMHz": output_mhz,
        "generatedWrapperOutputFrequencyMHz": configured_outputs,
        "exactOutput0ToOutput1Ratio": f"{c_div[1]}/{c_div[0]} = 4/1",
        "assertionsPassed": True,
        "otherConfiguration": {"pll_0002BandwidthPreset": "AUTO (rtl/pll/pll_0002.qip)", "cascadeInputEnabled": "false (rtl/pll.qip metadata)", "cascadeOutputEnabled": "false (rtl/pll.qip metadata)"},
        "limits": "The metadata strongly supports the generated divider relationship; no current fit report proves placement/routing, downstream PLL cascade legality, lock/jitter, or silicon frequency.",
    }


def create_fixture() -> dict:
    exidy_path = ROOT / "rtl" / "Exidy2.v"
    arcade_top_path = ROOT / "Arcade-Exidy2.sv"
    sys_top_path = ROOT / "sys" / "sys_top.v"
    exidy = exidy_path.read_text(encoding="utf-8")
    arcade_top = arcade_top_path.read_text(encoding="utf-8")
    sys_top = sys_top_path.read_text(encoding="utf-8")
    clock = span(exidy, "reg CLK22,CLK11;", "assign core_pix_clk=BCLK;")
    raster = span(exidy, "reg [5:0] hscnt =6'd0;", "wire BLANK = (V_BLANK|H_BLANK);")
    sync_fix = span(sys_top, "module sync_fix\n", "endmodule") + "\n"
    rgb_match = re.search(r"wire\s+\[5:0\]\s+rgb\s*=\s*(\{[^;]+\});", arcade_top)
    if not rgb_match:
        raise RuntimeError("Could not find production RGB3-to-RGB6 expansion in Arcade-Exidy2.sv")
    rgb_expression = rgb_match.group(1)
    required = ("cencnt  <= cencnt+7'd1;", "hscnt  <= (hscnt[5:0]==6'b100000) ? mod_shift[5:0] : hscnt+6'd1;", "vscnt <= (vscnt==9'd280) ? 9'd0 :", "assign H_SYNC =   (hscnt>61) ? 1'b1 : 1'b0;", "VL1  <= ((vscnt==9'd256)&(hscnt==60));")
    if any(marker not in clock + raster for marker in required):
        raise RuntimeError("An expected source clock/raster marker changed")

    wrapper = """`timescale 1ns/1ps
module source_video #(parameter GAMMA_MODE=1) (
 input wire master_clock, input wire [7:0] mod_shift, input wire [2:0] source_rgb3,
 output wire core_pix_clk, output wire hsync_raw, vsync_raw, hblank_raw, vblank_raw,
 output wire clk_video, ce_pixel, output wire [7:0] vga_r, vga_g, vga_b,
 output wire vga_hs, vga_vs, vga_de, output wire [5:0] raw_hscnt, raw_hspcnt,
 output wire [8:0] raw_vscnt, output wire raw_vl1
);
reg CLK22,CLK11;
reg BCLK,BCLKB,HCLK,CLD,BCLKX;
reg PH_1x,PH_1,PH_6,PH_6B,PH_6C,CCRY;
reg HCNT;
reg [6:0] cencnt=7'd0;
wire H_SYNC, V_SYNC, H_BLANK, V_BLANK;
""" + clock[clock.index("always @(posedge master_clock)"):]
    wrapper += "\n" + raster + "\n"
    wrapper += """
assign hsync_raw = H_SYNC;
assign vsync_raw = V_SYNC;
assign hblank_raw = H_BLANK;
assign vblank_raw = V_BLANK;
assign raw_hscnt = hscnt;
assign raw_hspcnt = hspcnt;
assign raw_vscnt = vscnt;
assign raw_vl1 = VL1;
wire [2:0] rgb_out = source_rgb3;
wire [5:0] rgb = """ + rgb_expression + ";\n"
    wrapper += """
tri [21:0] gamma_bus;
assign gamma_bus[20:0] = 21'd0;
arcade_video #(256,6,GAMMA_MODE) arcade_video (
 .clk_video(master_clock), .ce_pix(core_pix_clk), .RGB_in(rgb),
 .HBlank(hblank_raw), .VBlank(vblank_raw), .HSync(hsync_raw), .VSync(vsync_raw),
 .CLK_VIDEO(clk_video), .CE_PIXEL(ce_pixel), .VGA_R(vga_r), .VGA_G(vga_g), .VGA_B(vga_b),
 .VGA_HS(vga_hs), .VGA_VS(vga_vs), .VGA_DE(vga_de), .VGA_SL(),
 .fx(3'b000), .forced_scandoubler(1'b0), .gamma_bus(gamma_bus)
);
endmodule
""" + sync_fix
    OUT.mkdir(parents=True, exist_ok=True)
    generated = OUT / "source_video.sv"
    generated.write_text(wrapper, encoding="utf-8")
    tb_path = ROOT / "sim" / "video_capture" / "tb.sv"
    sources = {
        "rtl/Exidy2.v": exidy_path,
        "Arcade-Exidy2.sv": arcade_top_path,
        "sys/sys_top.v": sys_top_path,
        "sys/arcade_video.v": ROOT / "sys" / "arcade_video.v",
        "sys/video_mixer.sv": ROOT / "sys" / "video_mixer.sv",
        "sys/gamma_corr.sv": ROOT / "sys" / "gamma_corr.sv",
        "sys/scandoubler.v": ROOT / "sys" / "scandoubler.v",
        "sys/hq2x.sv": ROOT / "sys" / "hq2x.sv",
        "sys/video_freezer.sv": ROOT / "sys" / "video_freezer.sv",
        "rtl/pll.v": ROOT / "rtl" / "pll.v",
        "rtl/pll/pll_0002.v": ROOT / "rtl" / "pll" / "pll_0002.v",
        "rtl/pll.qip": ROOT / "rtl" / "pll.qip",
        "rtl/pll/pll_0002.qip": ROOT / "rtl" / "pll" / "pll_0002.qip",
    }
    return {
        "sourceHashes": {name: sha(path) for name, path in sources.items()},
        "fixtureHashes": {"generatedExtractedRtl": sha(generated), "testbench": sha(tb_path)},
        "extractionMarkers": ["reg CLK22,CLK11;", "assign core_pix_clk=BCLK;", "reg [5:0] hscnt =6'd0;", "wire BLANK = (V_BLANK|H_BLANK);", "module sync_fix\n", "production RGB3-to-RGB6 wire rgb = exact extracted assignment"],
        "videoConfiguration": {"arcadeVideoInstantiation": "arcade_video #(256,6) (third GAMMA parameter omitted; production default GAMMA=1)", "gamma": "enabled pipeline instantiated; gamma_bus gamma_en bit19 held 0 to exercise bypass path", "scandoubler": "fx=0 and forced_scandoubler=0", "hdmiFreeze": "production arcade_video leaves video_mixer.HDMI_FREEZE unconnected; testbench force ties this child input low"},
    }


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--verilator", default="verilator")
    p.add_argument("--run-dir", type=Path, default=OUT)
    args = p.parse_args()
    meta = create_fixture()
    pll_evidence = pll_divider_evidence()
    run_dir = args.run_dir.resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    srcfiles = [
        OUT / "source_video.sv", ROOT / "sys" / "arcade_video.v", ROOT / "sys" / "video_mixer.sv",
        ROOT / "sys" / "gamma_corr.sv", ROOT / "sys" / "scandoubler.v", ROOT / "sys" / "hq2x.sv",
        ROOT / "sys" / "video_freezer.sv", ROOT / "sim" / "video_capture" / "tb.sv",
    ]
    compile_logs = {}
    executables = {}
    for gamma_mode in (1, 0):
        exe = run_dir / f"video_capture_gamma{gamma_mode}"
        compile_run = subprocess.run([args.verilator, "--binary", "--timing", "-Wno-fatal", "-Wno-PROCASSWIRE", "--top-module", "tb", f"-GGAMMA_MODE={gamma_mode}", "--Mdir", str(run_dir / f"obj_dir_gamma{gamma_mode}"), *map(str, srcfiles), "-o", str(exe)], text=True, capture_output=True)
        (run_dir / f"compile_gamma{gamma_mode}.stdout.log").write_text(compile_run.stdout, encoding="utf-8")
        (run_dir / f"compile_gamma{gamma_mode}.stderr.log").write_text(compile_run.stderr, encoding="utf-8")
        compile_logs[str(gamma_mode)] = {"returnCode": compile_run.returncode, "stderrTail": compile_run.stderr[-3000:], "fullStdout": f"simulation/video_capture/compile_gamma{gamma_mode}.stdout.log", "fullStderr": f"simulation/video_capture/compile_gamma{gamma_mode}.stderr.log"}
        if compile_run.returncode == 0:
            executables[gamma_mode] = exe
    mras = sorted((ROOT / "releases").glob("*.mra"))
    if len(mras) != 6:
        raise RuntimeError(f"Expected six baseline MRA profiles, got {len(mras)}")
    shifts: dict[int, list[Path]] = {}
    for mra in mras:
        shifts.setdefault(mra_shift(mra), []).append(mra)
    profile_tests = []
    for shift, shift_mras in shifts.items():
        for gamma_mode in (1, 0):
            phase = 0
            if gamma_mode not in executables:
                profile_tests.append({"mrasUsingShift": [mra.name for mra in shift_mras], "mraSha256": {mra.name: sha(mra) for mra in shift_mras}, "modShift": shift, "gammaMode": gamma_mode, "phase": phase, "returnCode": None, "metrics": None, "fullRunLog": None, "diagnostic": "not run because Verilator compilation failed; see per-mode compile logs"})
                continue
            run = subprocess.run([str(executables[gamma_mode]), f"+SHIFT={shift}", f"+PHASE={phase}"], text=True, capture_output=True)
            log_name = f"run_gamma{gamma_mode}_shift{shift:02x}_phase{phase}.log"
            (run_dir / log_name).write_text(run.stdout + "\n--- stderr ---\n" + run.stderr, encoding="utf-8")
            match = re.search(r"RESULT ([^\r\n]+)", run.stdout)
            if not match:
                raise RuntimeError(f"No diagnostic RESULT for GAMMA_MODE={gamma_mode}, shift=0x{shift:02x}:\n{run.stdout[-1000:]}\n{run.stderr[-1000:]}")
            fields = {key: int(value) for key, value in re.findall(r"(\w+)=(-?\d+)", match.group(1))}
            profile_tests.append({"mrasUsingShift": [mra.name for mra in shift_mras], "mraSha256": {mra.name: sha(mra) for mra in shift_mras}, "modShift": shift, "gammaMode": gamma_mode, "phase": phase, "returnCode": run.returncode, "metrics": fields, "fullRunLog": f"simulation/video_capture/{log_name}", "diagnostic": "recorded as observed; color mismatch does not abort the evidence report"})
    result = {
        "schema": "exidy2-source-video-capture/v1",
        "method": "Verilator: production extracted Exidy divider/raster and exact arcade_video/video_mixer/gamma/scandoubler dependency source; coordinate-bitplane stimulus feeds production RGB3-to-RGB6 expansion. One phase-zero diagnostic pass per distinct current MRA mod_shift.",
        "verilator": subprocess.run([args.verilator, "--version"], check=True, capture_output=True, text=True).stdout.strip(),
        "fixture": meta,
        "originalPllDividerEvidence": pll_evidence,
        "compile": {"commandShape": "verilator --binary --timing -Wno-fatal -Wno-PROCASSWIRE --top-module tb -GGAMMA_MODE={0,1} [extracted RTL + checked-in production video dependency sources + sim/video_capture/tb.sv]", "perGammaMode": compile_logs},
        "diagnosticRuns": profile_tests,
        "limits": ["No game renderer, full core, full HDMI/OSD path, CRT retimer, or hardware is instantiated.", "Only coordinate bitplane 0 was run; this does not prove full 8-bit x/y order.", "Exact GAMMA_MODE=1 path and separately overridden GAMMA_MODE=0 diagnostic both produce final VGA RGB black in Verilator; neither is accepted as correct RGB transport.", "Verilator warns video_mixer.sv creates implicit undriven R_in/G_in/B_in at the gamma callsite; this source elaboration issue is left unmodified and no compatibility-normalized copy is used.", "Gamma logic is instantiated with gamma disabled (gamma_bus bit19=0); gamma-table contents/writes are not tested.", "HDMI_FREEZE is tied low only at the unconnected child port for deterministic no-freeze tests.", "DE geometry, pixel cadence, and provisional RGB-coordinate latency numbers are diagnostic only until the production RGB path elaborates correctly; final VGA RGB order is unverified.", "Sync widths and normalized phase relative to DE are not measured by this fixture.", "Generated PLL QIP divider values decode to M177/N7/C0=28,C1=112,C2=88 and have no reported counter bypass/odd mode flags in the decoded counter field set; wrapper frequencies agree after rounding. This remains generated-IP parameter evidence, not fit evidence.", "A separate output-PLL arithmetic candidate can use original outclk0 directly: native M32/N1/C32 and CRT M131/N4/C35 (131/140 of source), with nominal VCOs about 1444.898 and 1478.765 MHz. Cascade path legality, VCO/device limits, routing, lock, jitter, and fitted realization remain implementation gates."],
    }
    OUT.mkdir(parents=True, exist_ok=True)
    out = OUT / "results.json"
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"results": str(out.relative_to(ROOT)), "diagnosticRuns": profile_tests, "verilator": result["verilator"], "compileWarnings": {mode: details["stderrTail"][-700:] for mode, details in compile_logs.items()}, "originalPllDividerEvidence": pll_evidence}, indent=2))


if __name__ == "__main__":
    main()
