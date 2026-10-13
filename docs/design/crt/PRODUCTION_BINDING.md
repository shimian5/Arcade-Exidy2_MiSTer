# CRT production binding: next executable block

Prerequisite: current integrated FAX/speech production `2b9eb2b` meets its 59 reported timing summaries. Preserve that RBF as the rollback/hardware comparison. This document is the remaining integration plan, not an implemented wrapper or CRT acceptance claim.

## Accepted building blocks

- [x] Actual production mixer RGB scope fix and source-side pixel oracle.
- [x] Generic Native post-mixer packet collector and adaptive /8,/4,/2 bridge; actual FX streams, two frame edges per mode, reset and phase checks.
- [x] Fixed-width CRT collector plus rolling-row 336×262 stream; all 256 active rows, independent pixel/ownership/fault checks.
- [x] Exact output PLL ratios: Native M128/N1/C32 and CRT M131/N1/C35 referenced to existing master/4. Native game/audio clocks stay fixed.
- [x] Real vendor PLL/configuration/controller join; M/C accepted staging plus 256-cycle gaps, busy/done only after START, lock guard and two output-frame warmup.
- [x] Isolated Native/CRT controller timing with guarded first-stage and reset-CLR constraints.
- [x] Y13 physical routing with actual framework selector primitives. This probe is not timing accepted: its mutually exclusive clock aliases are not modelled as a complete production clock contract.

## One increment at a time

1. **Common output/options wrapper, Luna unit.** Add an unbound wrapper joining both collectors, both transports and the controller. Keep a continuously available native frame pulse for mode requests. Native transports the actual mixer RGB/HS/VS/DE; the CRT path consumes normalized 256×256 rows. Native frame detection uses sampled VS, CRT warmup uses complete raster boundaries. Never feed transport timing back into the game.
2. **Safe FX/options changes, same unit.** Hold both packet domains in reset and blank before changing applied FX/forced-scandoubler/cadence. Wait for asynchronous assertion to propagate, apply stable options, let the source mixer settle, then release through local synchronizers and require two output frames. FX forces Native; CRT always uses FX0 and /8. Changes within Native mode must restart the pipeline even if the PLL ratio stays unchanged. User/ROM reset preserves selected mode.
3. **Joined independent fixture, separate Luna unit.** Extract the actual source raster/mixer and wrapper. Check all eight bitplanes, first/last active rows, Native→CRT→Native, all FX/cadences, reset mid-frame, pause, stopped source, ROM-reload readiness and wrong-data/cadence controls. PLL simulation and digital transport simulation remain separate evidence where vendor models are unsuitable for Verilator. Never normalize away source behavior.
4. **Root production binding.** Expose source PLL lock without changing its counters/instance names. Connect a direct reconfigurable output PLL to CLK_VIDEO and preserve the inherited framework selectors. Route source mixer outputs into the collectors; route selected transport RGB/sync/DE/CE to framework outputs. Keep gamma writes on the existing source/system path; carry scanline metadata only while stable. Add the explicit timing menu and FX override behavior. Add only final required modules to QIP; keep obsolete probes outside production.
5. **Root constraint review.** Identify exact fitted endpoints before adding constraints. Keep all first→second synchronizer stages and functional paths timed. Bound Gray-pointer and held packet-data paths for the shortest /2 cadence. Cut only asynchronous first-stage control inputs and reset CLR pins with count guards. Preserve the existing framework selector/clock contract and all legacy generated clocks; do not hide timing failures with whole-clock exceptions. Analyse both Native and CRT counter configurations, not only startup Native.
6. **Root complete project flow.** Build from unsandboxed PowerShell with the full project flow. Record source/RBF hashes, all timing summaries, storage/DSP/PLL use and reset/CDC/clock coverage. Inspect any failing source and destination before repair. Run required focused regressions once source is frozen. W15 remains open for legacy no_clock/latch/loop coverage.
7. **Owner hardware session.** Compare against the preserved native build over HDMI and Direct Video→S-Video→15 kHz JVC. Check lock, all 256 rows, sync/cropping/color, FX auto-Native, repeated mode changes, pause, warm/cold reset and title reload. Record exact RBF/MRA/settings and A/V observations. Only then close physical CRT/complete-video acceptance.

Root owns shared top/core/QIP/SDC and all full builds. Luna units own isolated wrapper/fixtures until reviewed and frozen. Do not mark the whole W07 task DONE when only a candidate helper passes. Keep ROMs, captures, generated projects and RBFs ignored; preserve source licenses.
