# Full flow with PIA reset repair and five counter clocks

Production inputs at `444211d` completed the full unsandboxed PowerShell flow on 2026-10-07 at 11:34:18 local, exit 0, zero errors and 284 warnings, in 15m09s. **Master setup still fails; this is not a release candidate.**

| Check | Setup | Hold |
|---|---:|---:|
| Master PLL output | -0.427 ns, TNS -2.841 ns | +0.248 ns |
| Audio PLL output | +24.847 ns | +0.255 ns |
| BCLK | +7.292 ns | +0.815 ns |
| PH1 | +17.419 ns | +0.665 ns |
| PH6 | +7.457 ns | +1.038 ns |
| auPH0 | +56.295 ns | +0.416 ns |
| auPH0B | +56.705 ns | +0.385 ns |
| Nominal HDMI | +0.641 ns | +0.204 ns |

The five newly constrained clocks now pass the reported setup/hold checks in a complete fit; cached PH6 hold failures were repaired by the fitter without added exceptions. The exact EIR and 6840 functional sampling contracts still require review, as do remaining gated/event clocks. TimeQuest still reports incomplete setup/hold coverage. These results do not establish whole-design signoff or hardware/game acceptance.

All eight worst setup paths remain `audio_byte_stage` to `main_byte`. Worst bit 2 has 3.150 ns edge relationship, -0.777 ns clock skew and 2.470 ns data delay. The destination reset LUT is gone. The path now enters the destination FF `asdata` pin with 1.857 ns interconnect and 0.613 ns FF cell delay; removing the mux did not close the transfer. Reported reset recovery/removal margins remain positive (master +5.566/+0.959 ns), but this does not waive reset coverage elsewhere.

Pause stage-to-stage setup is +67.339 ns and hold +0.618 ns. The first-stage exception remains narrow; no byte exception was added. Forced-register report recognition is not a complete chain-grouping/MTBF audit.

Resources: 15,538 ALMs, 22,879 registers, 162 RAM blocks, 1,179,264 RAM bits, 35 DSPs and 3 PLLs. RBF SHA-256: `8447BB3E982075FAB2A5D3948F411692147AF2F71D1A464A1AE7CAD78E3B7128`.

Ignored artifacts: `simulation/quartus-pia-reset-counter-clocks-2026-10-07.log`, `simulation/full-core/444211d/`, and `simulation/timing-444211d/`. The latter includes separate setup/hold reports for every added counter clock and the pause stage-to-stage path. Releases are unchanged.

## Next bounded repair

Keep the byte transfer timed. Investigate an ordinary unreset data register plus a separately reset validity bit that masks the output during reset. This may remove the asynchronous FF data-pin penalty while preserving immediate reset assertion and delayed capture on release. It is a proposal only: prove equivalence with the existing paired PIA/reset/registered-CPU fixtures, including independent resets and first post-reset reads, then run the complete flow and inspect actual data/recovery/removal paths. A placement or source-edge change is another option only after a source/destination and handshake-latency review. Do not apply a false path or multicycle to conceal this failed byte path.
