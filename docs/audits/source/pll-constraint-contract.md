# PLL timing constraint contract

Source-only audit of the PLL constraints present at `55e3300`. No RTL/SDC edits or Quartus runs were made. Evidence includes `Arcade-Exidy2.sdc`, `sys/sys_top.sdc`, generated PLL IP wrappers, and the 2026-10-07 `output_files/Arcade-Exidy2.fit.rpt` and `.sta.rpt`.

## Core PLL (master and audio domains)

`Arcade-Exidy2.sv` instantiates `pll` from `FPGA_CLK2_50`: `outclk_0` drives `clkm_45MHZ` (the core/master clock), `outclk_1` drives `clkm_11MHZ`, and `outclk_2` drives `clk_audio`. The audio board consumes `clk_audio`. The fitted PLL report lists only output counters 0 and 2; output 1 is unused and optimized away.

The IP source `rtl/pll/pll_0002.v` requests 45.153061, 11.288265, and 14.366883 MHz from a 50 MHz reference. The fitted report confirms actual VCO = 1264.285714 MHz, M=177, N=7; output 0 is 45.153061 MHz with C0=28; output 2 is 14.366883 MHz with C2=88. The configured output 1 would use C1=112 for 11.288265 MHz, but it has no fitted output counter.

Current manual constraints in `Arcade-Exidy2.sdc` do not match that fitted configuration:

- Line 59 constrains the VCO to 50×48/5 = 480 MHz. TimeQuest reports the PLL cross-check expects M/N=177/7, not 48/5.
- Line 60 then divides this incorrect VCO by 10, producing a modeled 48 MHz master clock instead of 45.153061 MHz.
- Line 61 targets general[1], but the output was optimized away. The constraint is rejected for empty target/source collections; uncertainty entries for general[1] are also ignored.
- `derive_pll_clocks` already runs from `sys/sys_top.sdc`. Because the user-created clocks take precedence, output 2 is auto-derived from the bad 480 MHz user VCO as 480/88 = 5.45 MHz instead of 14.366883 MHz. The STA clock table confirms the erroneous modeled 48 MHz and 5.45 MHz clocks.

This makes the reported master/audio slack unsuitable as signoff for the actual clocks. The fitted design facts are credible; the timing model feeding TimeQuest is not.

## Audio and HDMI PLLs

The audio PLL IP (`sys/pll_audio/pll_audio_0002.v`) is fixed at 24.576 MHz from 50 MHz. Fit reports VCO=417.792 MHz and C0=17; STA currently models about 24.58 MHz from a manual 4279/512 VCO and /17 output. Removing those manual audio commands and letting the already-present `derive_pll_clocks` use the IP configuration should yield the exact fitted clock.

The HDMI PLL IP (`sys/pll_hdmi/pll_hdmi_0002.v`) has a nominal 148.5 MHz output, VCO=445.499998 MHz and C0=3 in the fit report. The current manual root constraints at lines 55–56 model about 148.54 MHz and match the nominal IP setup. However, `pll_hdmi_adj` and `pll_cfg_hdmi` route live reconfiguration writes into the PLL; the VHDL adjusts M and fractional M values. Static constraints cannot follow that changing clock. The current generated clock represents only the nominal/startup rate. The reconfiguration hardware should remain intact; before claiming video timing coverage across modes, bound the runtime frequency range and time the highest supported rate, or otherwise document that this dynamic output's downstream timing is outside the static model.

## Candidate constraint strategy

Prefer the existing `derive_pll_clocks` in `sys/sys_top.sdc` for the fixed core and audio PLLs. Remove the manual generated-clock commands for `emu|pll` at root SDC lines 59–61 and for `pll_audio` at lines 57–58. This lets TimeQuest derive clocks from fitter/IP data rather than overriding it. Expected core clocks are 45.153061 MHz (period about 22.146 ns) on output 0 and 14.366883 MHz (about 69.605 ns) on output 2; no output-1 clock should be expected. Expected audio PLL output is 24.576 MHz (about 40.690 ns).

For HDMI, retain the existing nominal generated clocks (lines 55–56) during this focused repair so the dynamic reconfiguration design and its nominal STA model remain unchanged. These constraints are an initial-rate model only; their limitation must stay explicit until the allowed reconfiguration envelope is bounded. `derive_pll_clocks` already runs, so adding another call is unnecessary.

Remove the uncertainty assignments that reference the nonexistent core general[1] output (root SDC lines 108–141). The core master self setup uncertainty is manually fixed at 0.290 ns on lines 132–145; TimeQuest says this is below its 0.380 ns recommendation. After correcting clock derivation, remove that lower override and use the existing `derive_clock_uncertainty`, then inspect `report_sdc` / clock-transfer uncertainty. If a project-specific value is required, document its source and ensure it is not below the justified requirement. Do not preserve hard-coded cross-output values that refer to the dead general[1] clock.

If manual core constraints are required instead of derive, the fitted values imply VCO multiply/divide 177/7 from `FPGA_CLK2_50`, then output 0 divide 28 and output 2 divide 88 from that VCO. The actual fitted report confirms those values. Auto-derivation is less dependent on private fitter hierarchy paths and should be tested first.

## Checks for the next TimeQuest run

Confirm the generated core clock periods and source/targets against `report_clocks`; confirm no 332056 PLL mismatch, no empty-collection warning for root SDC line 61, and no uncertainty assignments that still target the unused output. Check `report_sdc` to confirm `derive_clock_uncertainty` produces justified master and audio setup uncertainty. Then review unconstrained-path and inferred-clock reports; the existing `332102` incomplete setup/hold status and 332060 derived/gated-clock warnings are separate timing-coverage issues that a correct PLL model will not automatically fix.
