# Corrected-clock full-core build — 2026-10-07

Production checkpoint `594b8dd` includes the incoming tree, the audio pause synchronizer (`30dbc10`, attribute quoting correction `594b8dd`), and fixed-PLL constraint repair (`07a1f21`). The complete unsandboxed PowerShell flow `quartus_sh --flow compile Arcade-Exidy2` finished at 09:55:50 local, exit 0, with 0 errors and 297 warnings. **Timing acceptance fails.** Quartus flow exit status alone does not establish timing closure.

| Check | Result |
| --- | --- |
| Master setup | -0.948 ns; total negative slack -6.020 ns |
| Audio setup | +0.082 ns; no negative slack |
| HDMI nominal setup | +0.593 ns |
| Minimum reported hold | +0.184 ns |
| Resources | 15,529 ALMs; 22,448 registers; 168 RAM blocks; 1,179,813 RAM bits; 35 DSPs; 3 PLLs |
| RBF | 3,045,788 bytes; SHA-256 `EF10C734ADC6795F7F72423B6CD8C2574C29588A5498381D0AEAC14264FA785A` |

Ignored build log: `simulation/quartus-corrected-clock-pause-quoted-2026-10-07.log`. Ignored RBF: `output_files/Arcade-Exidy2.rbf`. This image is not a timing-accepted hardware candidate. The earlier `55e3300` image/reports are preserved under ignored `simulation/full-core/55e3300/`; its positive timing summary used incorrect PLL clocks.

Read-only TimeQuest replay after the completed full flow writes `simulation/timing-594b8dd/`. All eight worst setup paths are PIA_8B registered port-B data or DDR, through PIA_9B's combinational port-A read mux, into the main `CPU_databus_in` register. Worst source is `PIA_8B|portb_ddr[3]`, destination `CPU_databus_in[3]`; setup relationship 3.150 ns, clock skew -0.717 ns, data delay 3.051 ns. Both clocks come from the same PLL; master period 22.146 ns and audio period 69.604 ns. The pause repair no longer appears among these worst paths. No additional false path or multicycle constraint was introduced.

Next gate: reduce this timed return-data path while establishing whole-byte coherence and CPU/handshake latency, then run another complete flow. Review [PIA return-data contract](pia-return-data-contract.md) before implementing a remedy. Generated board clocks and asynchronous reset/data-event coverage remain open even if summary slack later becomes positive. Audio pause chain placement/identification, hardware behavior, all-game regression and W15 remain separate gates.

Fresh local MAME RAM traces now replay with **11 PASS, 0 FAIL, 0 SKIP**; all three mirrored maps have zero mismatches, while the Mouse Trap flat-map negative control has 6,188 mismatches. See [local audio-RAM replay](local-audio-ram-replay.md). This closes the earlier local trace gap, not complete audio or voice acceptance.
