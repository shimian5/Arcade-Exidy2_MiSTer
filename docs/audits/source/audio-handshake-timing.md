# Audio-board PIA handshake: timing failure diagnosis (2026-10-06)

Owner full-core Quartus run on the branch with the mono audio mix and interrupt-profile edits reported: setup −2.888 ns (TNS −1800.391) on PLL output 2 (14.367 MHz audio clock), −0.612 ns (TNS −2.810) on PLL output 0 (45.153 MHz master clock); all other clocks positive.

Every reported failing path (top eight per clock, supplied by the owner) is between `exidyAB:sound_board|pia6821:PIA_9B` (master clock) and `pia6821:PIA_8B` or `T65:A6502` (audio clock): handshake registers such as `ca1_fall`, `ca1_del`, `cb1_rise`, `cb1_del` and bus registers feeding `BAL`. The setup window on the worst paths is 0.006–0.4 ns because the 45.153/14.367 MHz clocks are unrelated and `Arcade-Exidy2.sdc` places all PLL outputs in one group, so every crossing is timed as synchronous. No failing path involves `exidyAudioMix`, `exidyIntCause`, `rCPU_IRQ`, `EIR` or `cDET`. The structure is in unmodified baseline logic, so the failure is very likely inherited; a baseline (`bfd1b5c`) build would confirm it and was not run.

Change: `Arcade-Exidy2.sdc` adds two scoped `set_false_path` constraints (PIA_9B → PIA_8B/T65, PIA_8B → PIA_9B). No RTL change; behavior is unchanged. This is a constraint, not a clock-domain-crossing fix: the CA1/CB1 inputs are still sampled without synchronizers, as in the baseline and on the original board's two asynchronous processors, where the firmware handshake provides safety. Candidate hardening (not done): two-flop synchronizers on the four handshake lines, which adds up to two audio-clock cycles of latency; would need a Venture/Mouse Trap audio comparison against MAME.

Expected on the next full build: no setup failure on either PLL output from these paths. If the build still reports negative slack, send the new top paths: they would be non-handshake crossings that remain timed.

## Follow-up (second owner run)
After the handshake false paths the master clock met timing (+0.050 ns) and the audio clock still failed (−1.022 ns, TNS −1400.432). The new worst paths all start at the reset sources (`hps_io|ioctl_download`, `hps_io|status[0]`, master clock) and end at audio-clock filter state (`jtframe_fir` RAM bits, `jtframe_dcrm`), i.e. `RESET_n` crossing into the audio domain's synchronous resets (baseline structure).

Change: `rtl/reset_sync.v` (`exidyResetSync`, two flops, no asynchronous path) provides `RESET_n_au` inside `rtl/audio_board.v` for the eight audio-clock reset users (T65, 6532, `PIA_8B`, 6840, 8253, jt49 clock enable, both filters). `PIA_9B` (master clock) keeps the raw reset. A scoped `set_false_path` in `Arcade-Exidy2.sdc` exempts the synchronizer's first flop (`rst_meta`). Unit test `sim/reset_sync/tb_reset_sync.sv` passes (exactly two destination edges for assert and release, glitch behavior, output only changes on clock edges). Behavior difference: audio-domain reset assert/release is delayed by two audio-clock cycles (about 140 ns). Not Quartus-built.

Remaining possible crossings (not yet seen in a report): `pause` into the audio CPU `rdy` and into the mono-mix mute. If another run lists them, treat the same way.
