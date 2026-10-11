# Teeter integration readiness review — 2026-10-11

## Scope and source baseline

Reviewed the unapplied `candidates/teeter-integration.patch` against production `HEAD` `012917a` (commit `Record passing PIA FIFO production timing and remaining coverage gates`). `git apply --check candidates/teeter-integration.patch` succeeds. No production RTL, shared documentation, ROM, or media was changed for this review. The candidate remains unapplied.

The patch gates the controls and NMI profile on `pcb == 8'hD0`, matching byte 1 in `candidates/mra/Teeter Torture (integration candidate).mra`. The current top-level routes `mod_other` to `exidy2.pcb`; `rtl/Exidy2.v` retains the legacy ESR byte and maps Teeter's alternate `IN0` byte only for this profile. The additions use existing HPS analog/spinner buses, the top's 45 MHz system clock, and the existing frame-vblank transition. These are source bindings, not evidence of a successful Quartus build or playable game.

## Input mux and sample contract

The new qualifier in the patch requires the Teeter profile, a read cycle, `$5101` low address bits, and every higher-priority memory source to be inactive (`RAMSEL`, `ROMSEL`, `SRAMSEL`, `CHARSEL`, `EXTVID`). This follows the registered `CPU_databus_in` mux order in current production `rtl/Exidy2.v`. The qualifier is registered on the same master edge as the mux byte, then `teeter_read_strobe` combines the previous qualifier with `PH_1` and `!pause`. The controls consume the prior registered `CPU_databus_in` byte, matching the T65's `.enable(PH_1)`, `.rdy(~pause)`, and `.di(CPU_databus_in)` bindings. This preserves event/direction from the actual byte T65 sampled, including when a new spinner update changes the combinational event around the sampling edge.

The existing `sim/teeter_controls/tb_teeter_integration_mux.sv` is a boundary model, not a production-core simulation. It exercises all five higher-priority mux sources, confirms they suppress read consumption, confirms profile fallback to the generic ESR byte, and checks pause/resume behavior and the registered-byte edge. `tools/teeter_integration_source_guard.py` binds the expected priority, T65 pins, HPS widths, and candidate qualifier to current `HEAD`; it passed in this review.

## NMI behavior and evidence

`rtl/teeter_nmi.v` is a 600 Hz nominal divider candidate (75,260 master ticks at 45.156 MHz) that holds active-low NMI through a `PH_1` sample and resets/gates its phase when reset/profile is inactive. `sim/teeter_nmi/tb_teeter_nmi.sv` tests exact nominal period, PH_1 release, profile disable, asynchronous reset, and period restart against that module. `sim/teeter_nmi/tb_t65_nmi.vhd` instantiates the selected production `modules/cpu-t65/T65.vhd` with its real dependencies and a synthetic 6502 image. It checks NMI edge capture on a PH_1 enable while `Rdy` is low, no bus advance while paused, and vector fetch after `Rdy` resumes.

The direct mixed-language join in `sim/teeter_nmi/tb_teeter_nmi_join.sv` connects the actual `rtl/teeter_nmi.v` generator to the actual selected T65 VHDL, at the full 75,260-tick interval. `sim/teeter_nmi/run_modelsim_join.ps1` compiles the production T65 dependencies and runs the fixture with installed ModelSim 10.5b. It confirms T65 captures the generator event at PH_1 while paused, keeps its address stable after the generator releases NMI, and fetches the synthetic vector target after resume. This is stronger than the independent fixtures, but still does not load the Teeter ROM, execute the whole production core, or establish hardware/gameplay acceptance.

The source contract is recorded in `docs/audits/source/teeter-input-contract.md` and `docs/audits/source/teeter-nmi-contract.md`. The former resolves callback event/direction placement to actual `$5101` bits 6 and 2 and per-read consumption. The latter documents the 600 Hz rate and T65 edge/pause semantics. The MRA labels itself a candidate requiring controls and NMI integration.

## Verification attempted

- Passed: `python tools/teeter_integration_source_guard.py` — `PASS Teeter source guard: production mux/T65 bindings match unapplied patch and boundary fixture`.
- Passed: `git apply --check candidates/teeter-integration.patch` — no output, exit status 0.
- Passed: In Archlinux WSL with `MAKEFLAGS=OPT_FAST=-O0`, the Verilator controls fixture reported `PASS read-strobe negative control` and `PASS teeter controls`; the mux fixture reported `PASS Teeter integration mux`; `make -C sim/teeter_nmi test` completed both the 75,260-tick generator test and the selected-T65 paused capture/resume test.
- Passed: `& .\\sim\\teeter_nmi\\run_modelsim_join.ps1` compiled the actual T65 VHDL dependencies and actual `rtl/teeter_nmi.v`, then reported `PASS actual Teeter NMI generator -> T65: period=75260 paused capture and resume vector`. ModelSim 10.5b logs are under ignored `simulation/harness/teeter_nmi/modelsim-join-20261011-154949-459/`.
- Not run: Quartus full project compile; it was outside this source and simulation qualification. No stage-only substitute was used.

## Ready-to-apply candidate and remaining gates

The review found no source mismatch requiring edits to the candidate patch. The focused controls, mux, generator, selected-T65, and mixed-language join tests pass. Before calling the game integrated, apply the candidate, run the repository's full Quartus project flow, test Teeter boot and controls on MiSTer hardware, and assess analog/spinner scaling and D-pad feel. Current evidence supports a source-aligned patch and tested CPU/NMI integration boundary; it does not establish gameplay or hardware acceptance.

## Root integration checkpoint

Root applied the reviewed patch to production on 2026-10-11, added a working-tree `--production` source guard and independently replayed the direct ModelSim join. PASS: full nominal period, paused capture and resume vector. Root evidence: ignored `simulation/harness/teeter_nmi/modelsim-join-20261011-155026-165/`. Source guard passes applied top/core/QIP bindings. Full Quartus flow is the next gate; candidate MRA remains outside releases and playable Teeter/physical controls are unaccepted. The 75,260-tick interval follows nominal board timing; fitted PLL offset is not claimed to be exactly 600 Hz.
