# Source-derived video capture diagnostic

`tools/video_capture/measure.py` extracts the actual Exidy divider/raster spans from `rtl/Exidy2.v`, `sync_fix` from `sys/sys_top.v`, and the production RGB3-to-RGB6 expression from `Arcade-Exidy2.sv`. It instantiates the checked-in `sys/arcade_video.v`, `sys/video_mixer.sv`, gamma, scandoubler, HQ2x, and freezer dependencies. The deterministic fixture disables FX/scandoubling, leaves gamma instantiated with its enable bit low, and ties the otherwise unconnected mixer `HDMI_FREEZE` input low in the testbench. It performs one phase-zero diagnostic image at each distinct mod_shift found in the six current MRA files; all six currently use `0x37`.

Reproduce from PowerShell with the installed WSL Arch Linux Verilator environment:

```powershell
wsl.exe -d archlinux -- bash -lc 'cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer && python3 tools/video_capture/measure.py --verilator verilator --run-dir simulation/video_capture'
```

The saved machine-readable result is [results.json](results.json). It contains SHA256 hashes for every extracted RTL/dependency source, the generated fixture and TB, and all six MRAs, plus references to the complete compiler and simulation logs retained under ignored `simulation/video_capture/`. Verilator 5.052 compiled both the actual default `GAMMA_MODE=1` path and a diagnostic `GAMMA_MODE=0` override. In both runs it observed one 256-row image with 65,536 DE pixels, zero line-geometry errors, and an 8-master-cycle output pixel cadence. It reported 49,152 color mismatches and 256 missing source-coordinate timestamps in each run. The provisional input-to-output latency was 18 master cycles in mode 1 and 2 in mode 0 for 65,280 samples.

These results do **not** establish correct RGB capture or pixel order. Verilator reports implicit undriven `R_in`, `G_in`, and `B_in` at `sys/video_mixer.sv:124`; production mixer source is left untouched and no compatibility-normalized copy is used. The black/mismatching final RGB result is therefore an unresolved simulation/elaboration compatibility finding, not a claim of a hardware defect. The measured geometry and latency are diagnostic only. The test covers one x/y bitplane, not all coordinate bits; final RGB ordering is unverified. It does not instantiate the full game, OSD/HDMI path, CRT retimer, or hardware. Sync widths and normalized sync phase relative to DE remain unmeasured. Gamma tables/writes are not tested.

The compile uses `-Wno-PROCASSWIRE` because unmodified `sys/hq2x.sv` procedurally assigns a `wire`; that compatibility warning suppression is explicit in the saved command metadata. Full stdout/stderr for each gamma mode and the two run logs are retained under ignored `simulation/video_capture/`.

## Generated PLL evidence and candidate arithmetic

The decoded `rtl/pll.qip` GUI-named divider metadata gives M=177, N=7, C0=28, C1=112, C2=88. The resulting 4:1 out0:out1 ratio and all three frequencies agree with `rtl/pll/pll_0002.v` after its MHz values are rounded. The generated metadata reports VCO 1264.285714 MHz. The decoded fields contain no counter bypass/odd-mode flags; `pll_0002.qip` says bandwidth `AUTO`, and the QIP metadata says cascade input/output are false. This is generated-IP parameter evidence, not a Quartus fit report or physical counter proof. There is no fitter result, cascade/routing legality result, lock/jitter measurement, or silicon frequency measurement here.

For a separate CRT-output PLL, direct use of original outclk0 as the reference avoids depending on the out0:out1 relationship: native M32/N1/C32 is 1:1, while candidate CRT M131/N4/C35 is exactly 131/140 of that source. Their nominal VCOs are approximately 1444.898 and 1478.765 MHz. This is arithmetic only. Device VCO limits, reference/cascade routing, PLL input legality, generated-IP realization, lock, jitter, and a full fit remain gates; it is not a physical CRT-support claim.

