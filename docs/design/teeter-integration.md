# Teeter production-integration patch proposal

[`candidates/teeter-integration.patch`](../../candidates/teeter-integration.patch) is a reviewable, unapplied unified diff against the current `HEAD`. It proposes top-level input binding, an isolated Teeter-only `$5101` dial path, periodic NMI, and QIP source registration. It changes no production file until a reviewer explicitly applies it; no Quartus or top-level simulation was run for this preparation.

## Signal and behavior map

| Function | Proposed source / use |
|---|---|
| Spinner | `sys/hps_io.sv` declares `spinner_0[8:0]`; bit 8 toggles per update and `[7:0]` is signed delta. The proposal wires this to `exidy2.spinner` and then `teeterControls.spinner`. The HPS block uses the same `clk_sys` passed at the top. |
| Analog steering | `joystick_l_analog_0[15:0]` is already an HPS output, with signed X in bits 7:0 and Y in bits 15:8. The proposal binds X. This core’s `clk_sys` and Exidy `master_clock` are both `clkm_45MHZ`. |
| D-pad steering mode | OSD option `O[24]` selects velocity ramp (default) or position spring mode, modeled on Super Off Road’s `O[10]` choice. Repository search found no existing `status[24]` use. The `teeterControls` candidate accepts this mode. |
| Frame tick | The proposal detects a rising edge of the existing top-level `vblank` wire. Exidy drives `V_BLANK` from `vscnt[8]`; `vscnt` wraps at 280, so this creates one pulse per generated frame at the start of vertical blank. The edge history samples `vblank` even while reset is asserted, preventing a synthetic frame pulse when reset is released during blanking. This is the same edge-detect pattern used by Super Off Road. |
| Pause / T65 read | The existing `pause_cpu` drives `exidy2.pause` and T65 `rdy(~pause)`. Within Exidy2, a one-cycle pending flag accompanies the continuously registered `CPU_databus_in` byte. The pending flag mirrors the actual read-mux priority: it requires `RAMSEL`, `ROMSEL`, `SRAMSEL`, `CHARSEL`, and `EXTVID` all inactive as selected sources, then requires `!IOSEL`, address low bits `01`, and `CPU_RWn`. `teeter_read_strobe` is asserted only on `PH_1 && !pause`; `teeterControls` consumes that previous registered byte and its `$5101` event/direction bits, matching the T65 sample on that enabled, ready edge. |
| Teeter `$5101` input | Only `pcb == 8'hD0` selects the Teeter path. This is the exact index-1 byte in `candidates/mra/Teeter Torture (integration candidate).mra` (Venture base plus profile 3). Teeter base bits 5 and 3 are set high as MAME’s unused inputs require; coin, fire, and starts use the already connected signals; the dial module replaces only bits 6 and 2. The existing generic ESR byte remains selected for every other `pcb` value. |
| 600 Hz NMI | `exidyTeeterNmi` runs from `master_clock`, is reset by `RESET_n`, is enabled only by exact byte D0, and holds active-low NMI until it sees the actual `PH_1` enable. The T65 instance receives this signal; for non-Teeter profiles the candidate drives it inactive-high. The default counter period 75,260 is 600 Hz at nominal 45.156 MHz. |
| QIP | `rtl/index.qip` registers the existing candidate sources `teeter_controls.v` and `teeter_nmi.v`. Those files are separate candidate artifacts in this workspace and must accompany the production diff. |

The MRA remains under `candidates/mra/`; this patch does not copy it into `releases/`. Existing release MRAs retain their index-1 bytes and continue to take the generic input path.

## Review points before application

The pending-read scheme relies on the current T65 interface: `CPU_databus_in` is updated on every master edge, T65 samples it when `PH_1` is high and `rdy` is true, and the read qualifier is delayed in parallel. The new [`tb_teeter_integration_mux.sv`](../../sim/teeter_controls/tb_teeter_integration_mux.sv) is a provisional boundary model mirroring the production mux's five higher-priority RAM/ROM clauses and registered DI timing. It passes under Verilator 5.052 and checks that each earlier source suppresses the consume qualifier, that a selected Teeter byte is consumed from the previous register at PH_1, that pause/RDY blocks consumption until resume, and that a non-Teeter profile retains the generic ESR byte. It does not instantiate production T65 or `Exidy2`, so it is not integrated-core acceptance.

[`teeter_integration_source_guard.py`](../../tools/teeter_integration_source_guard.py) binds the boundary model to current source: it checks the production read-mux priority and T65 `.enable/.rdy/.di` connections, then checks the candidate diff and fixture for corresponding qualifier, registered-byte, and sample-edge terms. This source-shape guard does not extract or execute the production mux; if source shape changes, the guard fails and the model needs review. Actual integrated wiring still needs a compile and an end-to-end bus test after the timing build.

The proposed read qualifier’s source review follows `rtl/Exidy2.v`: `CPU_databus_in` is a continuously updated register; T65 receives that register through `.di(CPU_databus_in)`, uses `.enable(PH_1)`, and receives `.rdy(~pause)`. The input selection chain prioritizes RAM, program ROM, screen RAM, character RAM, and extended video RAM ahead of the `$5101` ESR branch. The patch’s pending flag excludes all five selections before declaring an ESR byte valid. The qualifier is sampled in parallel with the CPU input byte; at the later enabled edge, both use their prior values. `pause` is included in the consume strobe so a PH_1 pulse while T65 RDY is low cannot advance the dial.

The frame pulse is one master edge after the registered `V_BLANK` transition becomes visible in the wrapper. `vblank_d` tracks the live level through reset, and `ce_frame` is masked while reset is asserted, so reset release during blanking does not invent a frame event. The NMI divider is based on the documented nominal master rate; if exact fitted 600 Hz is required, recompute the divider from the accepted PLL frequency. Local `sys/hps_io.sv` declares analog X/Y as a 16-bit output and spinner 0 as a 9-bit output; the spinner update toggles bit 8 and stores the 8-bit delta. `clk_sys` and Exidy `master_clock` both use `clkm_45MHZ`. The wrapper has no existing `status[24]` consumer, and the proposed OSD syntax follows the existing Super Off Road `O[10]` style. Confirm status-bit mapping on the target MiSTer framework before application.

Finally, D0 gates support on one exact image metadata byte, but the candidate MRA and source ROM assembly have not passed whole-system Teeter gameplay acceptance. Before release, verify the actual index-1 load lifecycle, reset release, `$5101` poll timing, NMI handler execution, dial feel, pause/resume, and that all non-Teeter profiles retain byte-for-byte generic ESR behavior. This patch is a proposed integration, not a statement that Teeter is complete.

## Patch validation

The patch was generated against `HEAD` source for `Arcade-Exidy2.sv`, `rtl/Exidy2.v`, and `rtl/index.qip`; `git apply --check candidates/teeter-integration.patch` passed. The patch was not applied. Existing focused controls and NMI candidate tests are separate evidence and do not compile or validate the integrated top.

The added integration-mux fixture was run with:

```sh
verilator --binary --timing -Wno-fatal --top-module tb_teeter_integration_mux \
  --Mdir simulation/test-logs/teeter-integration-mux-obj \
  rtl/teeter_controls.v sim/teeter_controls/tb_teeter_integration_mux.sv -o sim
simulation/test-logs/teeter-integration-mux-obj/sim
```

Result: `PASS Teeter integration mux` (Verilator 5.052, 286 ns simulated). This is a fixture around the candidate controls module and a behavioral model of the production mux priority; it is not a full-core integration test.

The source binding guard was run with:

```sh
py -3 tools/teeter_integration_source_guard.py
```

Result: `PASS Teeter source guard: production mux/T65 bindings match unapplied patch and boundary fixture`. It compares expected source terms and ordering; it does not prove behavioral equivalence or instantiate production RTL.
