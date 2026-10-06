# Native raster contract from RTL

Captured 2026-10-06 from the current checkout. This is a raw raster-counter measurement, not an end-to-end image or hardware acceptance result.

## Result

All six existing MRAs encode the same raster reload byte at ROM index 2: `0x37` (55). The source uses `mod_shift[5:0]` when `hscnt` reaches 32. Running the clock-divider, horizontal/vertical counters, sync, blanking, and VL1 logic extracted from `rtl/Exidy2.v` yields the same stable raster for every MRA:

| Signal/quantity | Measured value | Phase from stable frame origin | Phase from preceding line wrap |
| --- | ---: | ---: | ---: |
| Master cycles per pixel-clock sample | 8 | — | — |
| Total line | 336 pixel clocks / 2,688 master cycles | — | — |
| Total frame | 94,080 pixel clocks / 752,640 master cycles | — | — |
| Total lines per frame | 280 | — | — |
| Active area | 256 pixels × 256 lines | — | — |
| HS high | 16 pixel clocks / 128 master cycles | pixel 7 | pixel 320 |
| HB high | 80 pixel clocks / 640 master cycles | pixel 279 | pixel 256 |
| VS high | 1,681 pixel clocks / 13,448 master cycles | pixel 92,399 | pixel 312 |
| VB high | 8,065 pixel clocks / 64,520 master cycles | pixel 86,015 | pixel 312 |
| VL1 high | 8 pixel clocks / 64 master cycles; repeats every 94,080 pixel clocks | pixel 86,343 | pixel 304 |

The stable frame origin is the sampled `vscnt: 280 -> 0` transition. It occurs at `hscnt=61`, 313 pixel clocks after the preceding `hscnt` wrap; it is not aligned with the horizontal line boundary. VS and VB pulses end at the frame origin. HS ends at the next line wrap. These phases preserve the ordering seen in the RTL counters and avoid treating terminal counter values as durations.

With the instantiated generated PLL output configuration of 45.153061 MHz, the counter-derived frame cadence is **59.992906303 Hz** (pixel cadence 5.644132625 MHz). `rtl/pll.v` gives a 45.156 MHz wizard desired setting and also contains an inconsistent 10.079999 MHz actual-output annotation. The instantiated `rtl/pll/pll_0002.v` output parameter is used for the rate calculation. These are generated configuration values, not fitted timing or a measured board clock. The expected MAME nominal 59.996811 Hz is therefore not substituted for the source-derived rate.

## Method and repeatability

`tools/raster/measure.py` searches exact source markers and extracts the actual divider/phase logic through `assign core_pix_clk=BCLK;` and the horizontal/vertical block through `wire BLANK = (V_BLANK|H_BLANK);`. It combines those unchanged spans in an isolated wrapper and compiles them with Verilator 5.052. The testbench drives a master clock and records 250,000 pixel-clock samples per profile. It reads MRA index-2 bytes directly from all six existing MRA files. No production RTL or MRA is modified.

The capture records 250,000 samples per profile (about 2.65 frames), including one full stable frame interval after startup. This is enough for repeating cadence checks, not exhaustive long-run characterization. The checked-in testbench is `sim/raster/tb.sv`; generated extracted RTL and raw captures remain under ignored `simulation/raster/`. The capture checks every adjacent pixel event is eight master cycles apart; all measured line periods are 336 samples; the stable frame interval is 94,080 samples; every complete active line contains 256 samples; and each stable frame contains 256 active lines. Those checks pass for all six profile records in `docs/audits/raster/measurements.json`. Raw CSV captures, generated wrapper/testbench, and Verilator output stay in the ignored `simulation/raster/` directory.

Run from Windows PowerShell at the repository root:

```powershell
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && python3 tools/raster/measure.py --verilator verilator --run-dir simulation/raster'
```

The script compiles with `verilator --binary --timing -Wno-fatal --top-module tb` using absolute paths to its generated sources and output directory, then runs the binary once for each MRA-derived byte. The executable, raw CSV, and newly generated JSON stay in ignored local output. The checked-in [measurements.json](measurements.json) retains derived timing results and provenance from the integrator's independent replay; it contains no ROM bytes.

## Inputs and provenance

SHA-256 values are recorded in `docs/audits/raster/measurements.json` for each source and MRA. Source hashes at capture:

| File | SHA-256 |
| --- | --- |
| `rtl/Exidy2.v` | `c8aa3946deda06f6d4e371cc4f64da7b6c99d6e599aa8f948c711aa60c0e51bd` |
| `Arcade-Exidy2.sv` | `840dc8fa7e4b21913fa348b3d569c345a4c51c257f77f0604fb52861f689e7aa` |
| `rtl/pll.v` | `184432600b35e9ef68db9623c04cf251a1228b9120ece2f2d33b9433bdfd74f9` |
| `rtl/pll/pll_0002.v` | `7e5f656c55f4d5dd1fe963201c386bd1df46faa2cd2ddb3fe35cbef5180dfffd` |
| `rtl/pll.qip` | `8dd225ffc2e8b174daf5c5b8a59e53dd81d8b04f38a79a6a8bc421fe7cb142a1` |

The generated extracted wrapper and testbench hashes are also in the JSON. The MRA hashes there pin the exact files whose index-2 bytes parameterized the run.

## Startup and scope limits

The extracted raster logic has no reset input or reset branch. `cencnt`, `hscnt`, `hspcnt`, and `vscnt` have RTL initial values of zero; the phase registers, BCLK, and VL1 do not. Verilator is two-state and initializes otherwise-unset state to zero, so its startup behavior does not establish FPGA power-up or reset behavior. In this run the first line wrap occurs at sample 332 and the first sampled frame wrap at sample 94,053; steady line/frame measurements use repeating boundaries after startup.

This fixture does not instantiate the complete core, MRA loader, RGB/color pipeline, `sys/arcade_video.v` sync fixes, video mixer, HDMI/analog/Direct Video output, CRT receiver, or hardware. It provides the source raster-counter contract for W07 and does not establish complete image correctness, color/row orientation, receiver lock, or physical timing.

