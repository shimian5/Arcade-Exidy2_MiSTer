# Mouse Trap speech production join: RIOT timing audit

Read-only audit for the next production integration step. No production RTL was changed.

## RIOT write contract

`exidyAB` instantiates `R6532` with `phi2=auPH0`, `cs=!io08_0F`, `rw_n=audio_nWRITE`, `add=audio_addrbus[4:0]`, and `din=audio_databus_out` (`rtl/audio_board.v`, RIOT instance). The T65 also uses `auPH0` as its enable, with `clk=audio_clk`. `auPH0` is a registered one-audio-clock pulse derived from `cencnt_au[3:0]==0`; it is not a free-running clock (`rtl/audio_board.v`, clock-enable block).

The RIOT register state changes on `rising_edge(phi2)` only when `rst_n='1'`, `cs='1'`, `rw_n='0'`, and `add(2)='0'`. `add(1:0)` selects ORA, DDRA, ORB, DDRB for `00`, `01`, `10`, `11`. Thus the accepted PA callback predicate is a write to any mirrored address where `add(2)=0` and `add(1)=0`; `add(0)` distinguishes ORA from DDRA. Address bits 4:3 are ignored by this register decode. `add(2)=1` selects timer programming and must not trigger the callback. See `modules/riot/R6532.vhd`, write decode around lines 163–203.

Because `auPH0` is supplied as the RIOT's clock, its rising edge follows the `audio_clk` edge on which the registered value is set. With the current counter, this transition is predicted from the pre-edge state by `(cencnt_au == 0) && !auPH0`. The RIOT samples its stable bus on that derived edge; the T65 consumes the high enable at the following `audio_clk` edge. A callback helper clocked on `audio_clk` can therefore sample the prediction and current bus at the same parent edge that schedules the RIOT clock transition. The independently observed RIOT edge and the prediction are joined in `sim/mousetrap_riot_join/tb_mousetrap_riot_join.sv`.

The production candidate pulse is a bus-write timing pulse: `(cencnt_au == 0) && !auPH0 && !io08_0F && !audio_nWRITE`. The helper then filters to PA accesses with `!address[2] && !address[1]`, preserving mirrors; ORB, DDRB and timer writes may be accepted by the RIOT but must not update the speech callback. Do not create a separate address/data level detector. The existing `mousetrapVoiceCommand` helper maintains ORA/DDRA and emits a commit only for the PA registers (`rtl/mousetrap_voice_command.v`).

The callback byte is not simply the raw bus byte or `pa_out`. MAME's callback behavior is reproduced by retaining ORA and DDRA and emitting `(ORA & DDRA) | ~DDRA` after either accepted ORA or DDRA write. Reset emits `8'hff`. Input-configured PA bits therefore pull high independently of physical `pa_in`. The existing helper implements that contract and its tests cover reset, ORA/DDRA writes, aliases, back-to-back writes, and ensure timer writes do not update the command (`sim/mousetrap_voice_io`). The physical `pa_out` is updated on the RIOT falling edge from ORA/DDRA and `pa_in` (`R6532.vhd`, lines 344–350); it is not the callback's source because it includes external pin inputs.

For Mouse Trap, callback bit 4 controls the speech CPU reset through `mousetrapVoiceIo.z80_reset = z80_global_reset || !cvsd_data[4]`. The helper's PB0 input state is written by speech CPU OUT port `$10` and should feed RIOT `pb_in[0]`; RIOT DDRB/ORB then naturally determine whether the observed PB0 pin follows the input or output latch. This is already exercised in the isolated T80/RIOT join bench.

## Same-domain integration decision

Keep the speech T80, decoder, fixed-rate renderer and filters on `audio_clk`, using a clock enable at the intended speech CPU rate (proposed `/8`). This makes the accepted RIOT callback byte, callback pulse, and PB0 busy/input state local to the existing audio domain. It avoids adding a command-byte CDC and lets the native expansion ROM interface use `audio_clk` as its `speechclk`; continue to honor its request/valid and read-quarantine contract.

Minimal `audio_board.v` interface change: add only the Mouse Trap expansion read-side inputs needed by the speech ROM bus (speech readiness/data/valid and reset/read permission as defined by the final adapter binding), with `speechclk` driven internally from `audio_clk`. Keep `audio_l/audio_r` as the existing mixed output and add the filtered speech contribution there. Do not export a new clock or callback bus across the `exidyAB` boundary. Exact port names depend on the selected nativeexpansion top-level wiring; no broad interface change is justified by this audit.

The current production binding follows this domain plan: `exidyAB` clocks the command callback and speech subsystem from `audio_clk`; its RIOT receives `speech_busy` on PB0 while speech is enabled and a pulled-high idle input while disabled. The parent system clocks the expansion loader's CVSD side from `clk_audio`; its synchronized `speech_enable` reaches `exidyAB`, and `loader_hold` participates in core reset. The RIOT PA input is tied high, matching the callback's pull-up behavior for input-configured bits. The fixture runner now source-checks these production connections, the top-level joins, callback decode/formula, and the proven registered-`auPH0` predicate before compiling its independent RIOT timing simulation.

## Timing limitation to preserve

`auPH0` is a registered derived pulse that is used both as `T65.enable` and as the RIOT `phi2` clock. RTL simulation scheduling does not establish the physical phase relationship between the T65's enabled bus update and the RIOT's derived-clock edge. This audit supports using the RIOT's own accepted edge as the callback event, but it does not claim to fix or broadly characterize the existing audio CPU/RIOT clocking. Preserve this limitation explicitly; do not change the shared RIOT clocking or T65 enable as part of speech binding absent separate evidence and a scoped audio-clock investigation.

## Evidence and boundary

- `rtl/audio_board.v`: `auPH0` generation, T65 enable, and `A6532_RIOT` wiring.
- `modules/riot/R6532.vhd`: rising-edge writes, decoded register map, and falling-edge PA/PB output calculation.
- `rtl/mousetrap_voice_command.v` and `rtl/mousetrap_voice_io.v`: isolated accepted-write and callback semantics.
- `sim/mousetrap_voice_io/tb_mousetrap_voice_io.sv` and `tb_t80_voice_io_join.sv`: RIOT pin/callback behavior and T80 voice I/O join regressions. These fixtures are not production integration evidence and do not resolve the registered-`auPH0` timing limitation above.
- `sim/mousetrap_riot_join/tb_mousetrap_riot_join.sv`: independently compares the predicted parent-clock write pulse with actual accepted writes on the instantiated R6532's derived `auPH0` edge, covering PA aliases, rejected reads, non-PA writes, consecutive PA writes and PB0 pin behavior. Replay with `sim/mousetrap_riot_join/run_fixture.ps1`; ModelSim passes with 10 actual writes matching 10 predicted pulses.
- `docs/design/speech-rom-bus.md`: expansion speech read request/valid contract.

No production RTL edit, Quartus build, game boot, or physical CDC/timing claim is included in this audit.
