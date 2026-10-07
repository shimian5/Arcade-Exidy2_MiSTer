# Audio clock-domain contract — source review

This is a source-only review of the current audio clock, reset, and pause wiring. It does not establish Quartus clock recognition, CDC placement, or hardware behavior.

## Clock ownership

`Arcade-Exidy2.sv` instantiates one `pll` from `CLK_50M`. Its `outclk_0` is `clkm_45MHZ` (45.153061 MHz), used as `clk_sys` and passed as `exidy2.master_clock`; `outclk_2` is `clk_audio` (14.366883 MHz), passed into `exidy2` and `exidyAB`. These outputs come from the same PLL, so the source indicates related clocks with different rates, not two unrelated oscillators. The current SDC models the PLL output clocks together; do not mark the entire main/audio clock pair asynchronous without checking the generated-clock graph and paths.

Inside `exidy2`, `PH_1` is a register updated on `master_clock` from a counter comparison. It is then used as a clock for legacy logic and sprite/interrupt state. In `exidyAB`, the main-side `PIA_9B` is clocked by `master_clock` (the comment says `PH_1`, but the port connection is `master_clock`). The audio counter and `auCLK`, `auPH0`, and `auPH0B` are registered on `audio_clk`; the T65 audio CPU uses `audio_clk` with `auPH0` as its enable. `PIA_8B` and the audio RAM use `audio_clk`. The 6840 model receives `auPH0B` as its clock; its source comment says that this pulse is already the PTM E clock and sets `CLK_DIV=1`.

The `auPH0*` signals are registered clock enables in intent, but some are used as actual clock pins (`auPH0` on `R6532.phi2`, `auPH0B` on the 6840). They therefore create additional clock domains in the implemented netlist unless Quartus safely converts them. Review generated-clock coverage for those nodes and prefer clock enables on the parent `audio_clk` where the model permits it. This note does not recommend changing the legacy clocking without behavioral review.

## Reset ownership and first-download behavior

At the top level, `reset = RESET | status[0] | buttons[1] | ioctl_download`; the core passes its inverse as `RESET_n` to `exidy2`. This combines power/user reset sources with the download-active level. `RESET_n` reaches the main T65 directly and reaches `exidyAB` as its raw reset input.

`exidyAB` currently feeds raw `RESET_n` to `exidyResetSync`, whose `rst_meta` and `rst_sync` sample it on `audio_clk`. Both assertion and release take two audio edges, and the flops initialize low. Thus an asserted download does not immediately reset audio-domain consumers: they can run for up to two `audio_clk` edges after `ioctl_download` rises. On download completion the audio reset remains asserted until two audio edges after `ioctl_download` falls. If `audio_clk` stops, neither edge is observed and the synchronized reset does not change until the clock resumes.

The reset consumers do not all have the same semantics:

- T65 sees `RESET_n_au` on its active-low reset input. Its VHDL uses asynchronous assertion and internally synchronizes its reset sequence to its clock.
- `PIA_8B` receives active-high `!RESET_n_au`; its VHDL reset branch is asynchronous to `clk`.
- `berzerk_sound_fx` receives active-high `!RESET_n_au`. Its control, counter, prescaler, and noise processes include `reset` in the sensitivity list and reset asynchronously. Its programmed counter loads are otherwise performed on `rising_edge(clock)`; they are not asynchronous reset inputs.
- `R6532` receives active-low `RESET_n_au` but tests it only inside `rising_edge(phi2)`, so its reset action is synchronous to `auPH0`.
- `PIA_9B` uses raw `!RESET_n`; its reset branch is asynchronous. The main CPU also sees raw reset.
- The 8253, JT49 enable/filter blocks, and reset-conditioned audio counters use the synchronized audio reset. Their local reset polarity is shown in `audio_board.v`.

Because the audio reset output drives both asynchronous-reset blocks and a synchronous-reset block, the current two-edge-delayed assertion is a deliberate functional choice only if a two-audio-edge delay is acceptable. A common reset pattern for the asynchronous-reset consumers is asynchronous assertion with synchronized release: clear both reset-chain stages from raw active-low `RESET_n`, then shift in ones on `audio_clk`. This asserts reset immediately and releases it after two audio edges. Before adopting it, verify the 6532's synchronous reset still sees an active reset level on a `phi2` edge and check that the CPU/PIA handshakes tolerate the difference. Keep reset-stage metastability identification on the synchronizer stages, and scope any timing exception only to the first stage's data input; do not false-path the reset output fanout wholesale.

The source establishes a useful download window: `ioctl_download` is part of `reset`, so raw reset is asserted for the whole HPS download interval, including payload writes. ROM upload ports in `audio_board.v` use `dn_wr` and `master_clock`; their write operation is not reset-gated by the audio CPU reset. On deassertion, the two audio-clock release cycles give a small settle interval before the audio CPU resumes. This contract assumes `ioctl_download` stays asserted through the final `dn_wr` write and that ROM/data writes are complete before it drops. Source alone does not prove the host transport's final-write ordering or that two cycles cover every downstream setup requirement. It also does not cover the reset-only path from a short user/status pulse that does not span an `audio_clk` edge; the current synchronous-assert reset chain can miss such a pulse.

## Pause crossing recommendation

`pause_cpu` is registered in `pause.v` on `clk_sys`, which is `clkm_45MHZ`. It is consumed directly in the audio board as `T65.rdy(~pause)` and as the combinational audio mix mute input. Although the source and destination clocks are outputs of the same PLL, the pause level crosses from the 45.153 MHz domain into 14.366883 MHz logic and is not currently resampled there. The main CPU's `pause_cpu` connection should remain unchanged; add a local audio-domain level synchronizer in `exidyAB` and use only its second stage for the audio T65 ready input and mute input.

Recommended structure:

```verilog
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg pause_meta = 1'b0;
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) reg pause_au   = 1'b0;

always @(posedge audio_clk) begin
    pause_meta <= pause;
    pause_au   <= pause_meta;
end
```

Keep the two registers adjacent in source and fan out only `pause_au`; do not use `pause_meta` for ready, mute, or other logic. Do not add reset dependence that can leave one stage stale: initialize both stages to zero for FPGA power-up, and decide separately whether a later reset must clear them. The existing pause controller clears user pause on reset, but its registered output can remain high briefly as reset propagates. If the synchronizer is reset by audio reset, its output should be forced to the unpaused state and then track the source after release.

Apply Intel's synchronizer-identification attribute to the actual chain registers (or their exact elaborated register nodes), not the `pause` input port or all of `exidyAB`. After implementation, check Quartus's synchronizer-chain recognition and metastability report to confirm it identifies the first-to-second-stage path. Keep ordinary timing between the stages so placement can preserve settling time. The current source does not contain a pause false path. Since both clocks derive from the same PLL and the output clock paths are represented in the SDC, retain timing analysis unless a fresh clock/path report demonstrates that the crossing is intentionally asynchronous and cannot be analyzed as related. If a narrow exception is required for the first stage, scope it only from the `pause` source to `pause_meta` D; never cut `pause_meta` to `pause_au` or `pause_au` to its audio consumers.

## Open checks

The SDC contains false paths between the two PIAs and from `mod_other` to the audio-board hierarchy. Those exceptions do not synchronize the PIA handshake signals; they only suppress timing analysis. The PIA CA/CB handshake wires cross between `PIA_9B` and `PIA_8B` directly. This source review does not prove pulse capture or metastability tolerance. Fresh TimeQuest output should confirm that the PLL outputs and the `auPH0`/`auPH0B` derived clocks are recognized, report exception matches, and show the pause and reset paths after any implementation change. Functional checks should cover pause transitions, download start/end, reset-only operation, and all audio-board profiles.
