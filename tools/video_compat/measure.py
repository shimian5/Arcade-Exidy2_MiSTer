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
OUT = ROOT / "simulation" / "video_compat"


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


def compatibility_mixer() -> tuple[Path, dict]:
    source = ROOT / "sys" / "video_mixer.sv"
    text = source.read_text(encoding="utf-8")
    old = """generate
	if(GAMMA && HALF_DEPTH) begin
		wire [7:0] R_in  = frz ? 8'd0 : {R,R};
		wire [7:0] G_in  = frz ? 8'd0 : {G,G};
		wire [7:0] B_in  = frz ? 8'd0 : {B,B};
	end else begin
		wire [DWIDTH:0] R_in = frz ? 1'd0 : R;
		wire [DWIDTH:0] G_in = frz ? 1'd0 : G;
		wire [DWIDTH:0] B_in = frz ? 1'd0 : B;
	end
endgenerate"""
    new = """// SIMULATION-COMPAT ONLY: module-scope nets replace generate-scope nets
// that are referenced after the generate block by gamma_corr.
wire [7:0] R_in, G_in, B_in;
generate
	if(GAMMA && HALF_DEPTH) begin
		assign R_in = frz ? 8'd0 : {R,R};
		assign G_in = frz ? 8'd0 : {G,G};
		assign B_in = frz ? 8'd0 : {B,B};
	end else begin
		assign R_in = frz ? 1'd0 : R;
		assign G_in = frz ? 1'd0 : G;
		assign B_in = frz ? 1'd0 : B;
	end
endgenerate"""
    if text.count(old) != 1:
        raise RuntimeError("Expected exact single production video_mixer generated-net block; source changed")
    compat = text.replace(old, new, 1)
    out = OUT / "video_mixer_scope_compat.sv"
    OUT.mkdir(parents=True, exist_ok=True)
    out.write_text(compat, encoding="utf-8")
    return out, {"source": "sys/video_mixer.sv", "sourceSha256": sha(source), "compatSha256": sha(out), "transformation": "exact generated-net block assertion, then replace branch-local wire initializers with module-scope 8-bit wires and branch-local continuous assignments; no other text changed", "changedBlockSha256Before": hashlib.sha256(old.encode()).hexdigest(), "changedBlockSha256After": hashlib.sha256(new.encode()).hexdigest(), "purpose": "Verilator-visible module-scope names preserve production width/value expressions while avoiding implicit undriven nets caused by generate-scope visibility", "productionFileModified": False}


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
    tb_path = ROOT / "sim" / "video_compat" / "tb.sv"
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
    p.add_argument("--report", type=Path, default=ROOT / "docs" / "design" / "video-compat" / "results.json")
    args = p.parse_args()
    meta = create_fixture()
    compat_path, compat_meta = compatibility_mixer()
    pll_evidence = pll_divider_evidence()
    run_dir = args.run_dir.resolve()
    run_dir.mkdir(parents=True, exist_ok=True)
    srcfiles = [
        OUT / "source_video.sv", ROOT / "sys" / "arcade_video.v", compat_path,
        ROOT / "sys" / "gamma_corr.sv", ROOT / "sys" / "scandoubler.v", ROOT / "sys" / "hq2x.sv",
        ROOT / "sys" / "video_freezer.sv", ROOT / "sim" / "video_compat" / "tb.sv",
    ]
    compile_logs = {}
    executables = {}
    for gamma_mode in (1,):
        exe = run_dir / f"video_compat_gamma{gamma_mode}"
        compile_run = subprocess.run([args.verilator, "--binary", "--timing", "-Wno-fatal", "-Wno-PROCASSWIRE", "--top-module", "tb", f"-GGAMMA_MODE={gamma_mode}", "--Mdir", str(run_dir / f"obj_dir_gamma{gamma_mode}"), *map(str, srcfiles), "-o", str(exe)], text=True, capture_output=True)
        (run_dir / f"compile_gamma{gamma_mode}.stdout.log").write_text(compile_run.stdout, encoding="utf-8")
        (run_dir / f"compile_gamma{gamma_mode}.stderr.log").write_text(compile_run.stderr, encoding="utf-8")
        compile_logs[str(gamma_mode)] = {"returnCode": compile_run.returncode, "stderrTail": compile_run.stderr[-3000:], "fullStdout": str((run_dir / f"compile_gamma{gamma_mode}.stdout.log").relative_to(ROOT)), "fullStderr": str((run_dir / f"compile_gamma{gamma_mode}.stderr.log").relative_to(ROOT))}
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
        for gamma_mode in (1,):
          for phase in range(8):
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
            first_color = re.search(r"PIXEL_MISMATCH x=(\d+) y=(\d+) got=([0-9a-fA-F]+) expected=([0-9a-fA-F]+)", run.stdout)
            first_missing = re.search(r"LATENCY_SOURCE_MISSING x=(\d+) y=(\d+)", run.stdout)
            profile_tests.append({"mrasUsingShift": [mra.name for mra in shift_mras], "mraSha256": {mra.name: sha(mra) for mra in shift_mras}, "modShift": shift, "gammaMode": gamma_mode, "phase": phase, "returnCode": run.returncode, "metrics": fields, "firstColorDivergence": ({"x": int(first_color.group(1)), "y": int(first_color.group(2)), "gotRgb": first_color.group(3), "expectedRgb": first_color.group(4)} if first_color else None), "firstMissingTapCoordinate": ({"x": int(first_missing.group(1)), "y": int(first_missing.group(2))} if first_missing else None), "fullRunLog": str((run_dir / log_name).relative_to(ROOT)), "diagnostic": "native uncompensated stimulus; color/tap mismatch is intentionally recorded as an alignment failure"})
    negative_control = None
    if 1 in executables and profile_tests:
        baseline = next(x for x in profile_tests if x["gammaMode"] == 1 and x["phase"] == 0)
        run = subprocess.run([str(executables[1]), "+SHIFT=54", "+PHASE=0"], text=True, capture_output=True)
        name = "negative_shift36_phase0.log"
        (run_dir / name).write_text(run.stdout + "\n--- stderr ---\n" + run.stderr, encoding="utf-8")
        match = re.search(r"RESULT ([^\r\n]+)", run.stdout)
        perturbed = {key: int(value) for key, value in re.findall(r"(\w+)=(-?\d+)", match.group(1))} if match else None
        compared_fields = ("output_events", "hs_width_min", "hs_to_de_min", "vs_width_min", "vs_to_de_min")
        detected_fields = [field for field in compared_fields if perturbed and perturbed.get(field) != baseline["metrics"].get(field)]
        negative_control = {"type": "controlled mod_shift perturbation", "baselineShift": 55, "perturbedShift": 54, "returnCode": run.returncode, "metrics": perturbed, "detectedByFields": detected_fields, "detected": bool(detected_fields), "fullRunLog": str((run_dir / name).relative_to(ROOT))}
    result = {
        "schema": "exidy2-source-video-capture/v1",
        "method": "Verilator: production extracted Exidy divider/raster and exact arcade_video/video_mixer/gamma/scandoubler dependency source; coordinate-bitplane stimulus feeds production RGB3-to-RGB6 expansion. Eight x/y bitplanes (phase 0..7), default GAMMA=1 with gamma enable disabled, per distinct current MRA mod_shift.",
        "verilator": subprocess.run([args.verilator, "--version"], check=True, capture_output=True, text=True).stdout.strip(),
        "fixture": meta,
        "simulationCompatibilityCopy": compat_meta,
        "originalPllDividerEvidence": pll_evidence,
        "compile": {"commandShape": "verilator --binary --timing -Wno-fatal -Wno-PROCASSWIRE --top-module tb -GGAMMA_MODE=1 [extracted RTL + checked-in production video dependency sources + sim/video_compat/tb.sv]", "perGammaMode": compile_logs},
        "diagnosticRuns": profile_tests,
        "negativeControl": negative_control,
        "limits": ["Native uncompensated raster-label alignment fails: phase sweeps and capture-edge timestamps are in diagnosticRuns; no RGB/DE acceptance is claimed.", "The input coordinate tracker stops at x=254; output DE asks for x=255 on each row, yielding 256 missing coordinate timestamps. The first native color divergence is retained in run logs.", "Mixer scope correction exists only in the source-asserted compatibility copy; exact production-source failure remains in docs/design/video-capture/results.json.", "Gamma is default GAMMA=1 but gamma enable is held low; gamma-table contents/writes are not tested.", "HDMI_FREEZE is tied low only at the unconnected child port; no full OSD/HDMI path, game renderer, CRT retimer, physical receiver, or gameplay test is included.", "HS/VS widths and normalized phases describe the sampled arcade_video output raster only; they are not physical receiver phase claims."],
    }
    OUT.mkdir(parents=True, exist_ok=True)
    out = args.report.resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"results": str(out.relative_to(ROOT)), "diagnosticRuns": profile_tests, "verilator": result["verilator"], "compileWarnings": {mode: details["stderrTail"][-700:] for mode, details in compile_logs.items()}, "originalPllDividerEvidence": pll_evidence}, indent=2))


if __name__ == "__main__":
    main()
