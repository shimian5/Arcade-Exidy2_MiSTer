# PIA destination-stage full-flow result

Production checkpoint `3341f08` was compiled with a complete unsandboxed PowerShell `quartus_sh --flow compile Arcade-Exidy2`. It finished on 2026-10-07 at 10:37:11 local, exit0, 0 errors and297 warnings, after14m07s. **Timing still fails.**

| Check | Result |
| --- | --- |
| Master setup | -0.556 ns; TNS -3.700 ns |
| Audio setup | -0.193 ns; TNS -0.193 ns |
| HDMI nominal setup | +0.441 ns |
| Minimum reported hold | +0.251 ns |
| Resources | 15,444 ALMs;22,446 registers;168 RAM blocks;1,179,813 RAM bits;35 DSPs;3 PLLs |
| RBF SHA-256 | `A3B4E7DC16A31143A3F20213D434971E5D59B8E98E95661AE55F1D6978400F6B` |

Ignored log: `simulation/quartus-pia-return-2026-10-07.log`. RBF remains ignored and unaccepted; release artifacts were not replaced. Read-only reports under `simulation/timing-3341f08/` identify the worst master path as PIA8 `portb_ddr[2]` → `pia_return_data|main_byte[2]`, setup relationship3.150ns, skew-0.763ns, data delay2.613ns. The mask logic is still on the crossing into the new destination register. Audio's only reported negative path is `pause_cpu` → `audio_pause|pause_meta`, relationship3.166ns, skew-1.025ns, data delay2.004ns.

Next candidate registers the complete masked PIA byte on the audio clock before its normally timed transfer to the master register, subject to renewed paired-PIA tests and full fit. The separate held single-bit pause synchronizer gets forced identification and a first-stage-only exception; see [pause contract](pause-first-stage-constraint.md). The byte is not exempted. Full generated-clock/reset coverage and firmware/hardware acceptance remain open.

The existing runner after destination-stage integration reports11 PASS,0 FAIL,0 SKIP, including all three fresh MAME audio-RAM traces. The paired production-PIA test passes all seven phases and actual Verilog register checks, with the CPU observer consuming its previous registered input. These are functional simulation results, not timing closure.
