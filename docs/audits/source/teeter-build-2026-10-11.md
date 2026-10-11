# Teeter production build and timing checkpoint — 2026-10-11

Production source `020b2ae` integrates the reviewed Teeter controls and stretched NMI under exact profile `0xD0`. The full unsandboxed PowerShell command `quartus_sh --flow compile Arcade-Exidy2` completed at 16:08:19 on October 11: exit 0, zero errors, 285 warnings, elapsed 17m01s. No isolated stage replaced the acceptance flow. Release files remain unchanged.

## Fitted result

| Check | Result |
| --- | --- |
| Master setup / hold | +2.817 / +0.249 ns |
| Audio setup / hold | +16.411 / +0.243 ns |
| Global minimum setup / hold | +0.392 / +0.243 ns |
| Global minimum recovery / removal | +3.549 / +0.717 ns |
| Minimum pulse width | +0.395 ns |
| All 59 timing summaries | Positive slack, zero TNS |
| Resources | 15,672 ALMs; 23,074 registers; 162 RAM blocks; 35 DSP; 3 PLLs |

Ignored build archive: `simulation/full-core/020b2ae/`. Development RBF SHA-256: `65F631ADD85143EF44408C22C9107AE816C456C1177FE93518F6CD3A3C4039B8`. Revert `020b2ae` to remove this production integration; later fixture/document commits do not change its fitted RTL.

## Independent post-fit checks

After the full flow, read-only `quartus_sta -t tools/timing/report_pia_fifo.tcl simulation/timing-020b2ae` completed at 16:13:10, zero errors. The report script adds no constraints. Initial diagnostic runs failed strict physical cardinality because Quartus duplicated registers. The diagnostic now validates logical pointer indices and counts logical reset state while including every physical replica in path reports; production RTL and SDC were not relaxed.

The 36 bundle keepers and nine capture registers resolve. Write/read Gray pointers retain three logical bits each, with four/five fitted physical registers respectively. Audio reset state has 21 logical / 23 physical registers; master has 23 logical / 25 physical. All targeted paths pass:

| Target | Setup / hold or recovery / removal (ns) |
| --- | --- |
| FIFO bundle | +15.657 / +0.476 |
| Write Gray to meta | +16.310 / +0.526 |
| Read Gray to meta | +16.411 / +0.438 |
| Write synchronizer D stages | +20.699 / +0.454 |
| Read synchronizer D stages | +68.132 / +0.529 |
| Audio reset meta to release | +68.367 / +0.482 |
| Master reset meta to release | +20.565 / +0.662 |
| Audio local reset release | +67.852 / +0.717 |
| Master local reset release | +19.998 / +0.811 |
| FIFO output to CPU DI | +17.760 / +1.621 |
| Reset mask to CPU DI | +17.942 / +1.760 |

BCLK, PH_1, PH_6, auPH0 and auPH0B targeted setup/hold reports also pass. The existing exception on four reset-conditioner clear inputs remains; absent recovery/removal there is not timing proof. Reports are in ignored `simulation/timing-020b2ae/`.

## Coverage and remaining gates

Fresh `check_timing`: 3,265 no-clock objects, 118 multiple-clock objects, 96 latches, one loop, 13 inputs and 129 outputs without delays, three partial min/max delays. Of the no-clock entries, 171 are in Exidy hierarchy (169 in the prior fit). These legacy coverage warnings remain real work; positive constrained timing is not whole-design signoff. See [event coverage](event-coverage-2026-10-11.md). The sticky IRQ candidate passed simulation but failed its isolated **full** Quartus flow and is rejected; it was not applied to production.

Root independently passed the actual generator/T65 paused NMI join and the [source-extracted actual T65 bus join](teeter-bus-join-2026-10-11.md). The latter checks registered read consumption, five higher-priority sources, generic profile fallback and pause. Neither uses complete Teeter firmware or establishes gameplay. Next acceptance: load the development RBF with `candidates/mra/Teeter Torture (integration candidate).mra`; check boot, spinner, joystick/D-pad, pause and NMI-driven gameplay on hardware. Sensitivity, exact physical rate and full ROM behavior remain open.
