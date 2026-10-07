# PIA data/valid full-flow result — 2026-10-07

Production commit `07a49c5` completed the full unsandboxed PowerShell Quartus 17.0.2 flow at 14:48:26 local time, in 12m38s: zero errors, 285 warnings. Successful compilation does not establish timing acceptance. The RBF is unaccepted and releases are untouched.

## Reported timing

| Path/domain | Setup ns | Hold ns |
|---|---:|---:|
| Master, overall | -0.439 | +0.252 |
| Audio, overall | +25.120 | +0.253 |
| Registered PIA source byte to master data | -0.439 | +0.511 |
| Valid mask to main CPU registered input | +16.337 | +2.126 |
| BCLK | +8.722 | +0.760 |
| PH_1 | +17.012 | +0.645 |
| PH_6 | +9.114 | +1.179 |
| auPH0 | +53.654 | +0.444 |
| auPH0B | +54.079 | +0.440 |

The valid-bit reset has reported recovery +17.187 ns and removal +1.383 ns. Pause first-to-second stage setup is +68.315 ns. These results do not close the remaining unmodeled event clocks or prove physical/game acceptance.

All eight failing setup paths remain `audio_byte_stage[*]` to `main_byte_data[*]`, with master TNS -2.634 ns. Worst bit 5 has a 3.150 ns relationship, -0.767 ns skew and 2.492 ns data delay: 1.880 ns interconnect plus 0.612 ns destination-cell delay, from `FF_X37_Y16_N26` to `FF_X37_Y20_N8`.

The reset-free destination still uses the fitted `asdata` pin on the worst path. Its name does **not** establish asynchronous reset behavior or a reset-specific delay penalty. Removing reset from the byte did not improve setup relative to the previous -0.427 ns fit. The data/valid split preserves the simulated reset/latency contract, but its timing-repair hypothesis is not supported by this build. Next: inspect every bit's physical route and evaluate a bounded packing/placement experiment while retaining ordinary setup/hold constraints. Do not waive the byte transfer.

## Reproduction and retained evidence

Full build: `quartus_sh --flow compile Arcade-Exidy2`. Post-fit read-only reports: `quartus_sta -t tools/timing/replay_constraints.tcl Arcade-Exidy2.sdc simulation/timing-07a49c5`. Both completed with zero tool errors. No active netlist was inspected during the full flow.

Ignored evidence: `simulation/quartus-pia-data-valid-2026-10-07.log`, `simulation/timing-07a49c5/`, and snapshot `simulation/full-core/07a49c5/`. RBF SHA256: `16169BB071C09D0A1CE69F2CAE65A7930D9770D92FC2BC36F4E4C4D6BF4B7457`.

Resources: 15,472 ALMs, 22,983 registers, 162 RAM blocks / 1,179,264 bits, 35 DSP blocks, three PLLs. The [remaining-clock review](remaining-clock-coverage.md) identifies event-path gates still open. The first coverage diagnostic could not classify register clock propagation and rejected `check_timing -verbose`. The corrected rerun successfully generated `check_timing`, exception and SDC reports, and resolved wildcard clock-group membership. About 170 no-clock entries belong to the Exidy hierarchy; the other entries largely concern HPS/system interfaces. Both emu PLL outputs share a group, so their byte-transfer path remains timed. Complete event-path coverage is still open.
