# PLL constraint candidate review

Read-only review of `simulation/timing-candidate/Arcade-Exidy2.sdc` and `simulation/timing-candidate/replay.log` plus the replay reports. The replay applies the candidate SDC to the existing fitted timing netlist; these slack values are useful for constraint review but are not a new full fit. No production files or existing reports were changed.

## PLL model and SDC load order

The replay clock report shows the intended fitted PLL periods: core output 0 / master = 22.146 ns (45.153 MHz), output 2 / audio = 69.604 ns (14.367 MHz), and fixed audio PLL = 40.682 ns (24.58 MHz in the STA model; the physical IP fit is nominally 24.576 MHz). The HDMI nominal model remains 6.732 ns (148.54 MHz). The root candidate derives fixed PLL clocks from the fit database before root `set_clock_groups` is processed, so the root wildcard group sees the core PLL output clocks. It also derives clock uncertainty before the remaining explicit uncertainty settings.

The QSF includes `Arcade-Exidy2.sdc`; `sys/sys.qip` includes `sys/sys_top.sdc`. Replay confirms the root SDC is read first and `sys_top.sdc` second. The latter repeats the same primary-clock definitions, producing `332043` overwrite warnings, then repeats `derive_pll_clocks` and `derive_clock_uncertainty`. This is redundant but replay shows no clock conflict: the candidate-derived core/audio clocks remain at the expected periods, and the HDMI user-defined nominal clocks take priority. Retaining the early root `derive_pll_clocks` matters because the root `set_clock_groups` executes before the later system SDC is loaded; without the root derivation, its clock collections could be empty when grouped.

## New timing paths exposed

The replay finds 8 setup paths, all violated; worst setup slack is −0.993 ns. Worst hold slack is +0.168 ns with no hold violations. In this existing fitted placement, the top violations are:

- PIA_8B state (`portb_ddr[3]`) to main `CPU_databus_in[3]`, audio output 2 to master output 0: −0.993 ns. The other top paths include more PIA_8B port/data bits to the same CPU bus register (−0.943 to −0.767 ns).
- `pause_cpu` to audio T65 state, master output 0 to audio output 2: −0.776 to −0.762 ns.

The PIA data path is outside the existing falsepath endpoints. `audio_board.v` connects PIA_8B `pb_o` to PIA_9B `pa_i`; `audio_data_out` from PIA_9B is then selected into `CPU_databus_in` in `rtl/Exidy2.v`. Thus this is part of the PIA firmware handshake data path, but the present `PIA_8B -> PIA_9B` keeper exception does not cover its final parent-level CPU bus register. If the existing handshake rationale is accepted for this data transfer, the smallest constraint-only completion is a separately scoped path exception from PIA_8B state to the actual `exidy2:ex2|CPU_databus_in[*]` registers. Confirm its collection matches in TimeQuest. This would waive timing analysis only; it would not harden the CDC or establish handshake correctness.

The `pause_cpu` paths are a distinct issue in this cached replay. The replay predates the current working-tree `pause_sync` addition, so its pause violations must be re-evaluated in the next full-flow run. `pause_cpu` is a master-clock register and directly drives audio CPU `.rdy(~pause)`; the replay shows that path violates setup under the newly accurate clock relationship. Do not waive it as part of the PIA handshake exception. A synchronization/functional design decision is needed before deciding whether any timing exception is justified; the audio mixer mute is also driven combinationally by `pause` and is not covered by these register-to-register setup reports. The replay slack may shift after a full fit, but the CDC remains regardless of the final numeric slack.

## Remaining warnings and scope

The replay has no warning for the removed `general[1]` PLL clock or its former uncertainty assignments. It now derives only the two used core outputs. The expected unmatched constraint warnings are unrelated to the removed PLL clocks: `altera_reserved_tck` has no top-level port (empty `create_clock` at candidate SDC line 42, plus uncertainty/group references to that absent clock), and the pre-existing `mcp23009|sd_cd` falsepath source is unmatched. The same-period primary-clock overwrite warnings come from loading both SDC files.

The candidate correctly fixes the core/audio PLL clock model and preserves the existing nominal HDMI constraints. The reconfigurable HDMI PLL can still change frequency at runtime, which the nominal 148.5 MHz STA clock does not model. The full-flow run after landing any production SDC change remains necessary; it must be interpreted with the remaining setup/hold completeness and inferred-clock warnings, and it does not validate game behavior or hardware CDC reliability.
