# Audio pause synchronizer — 2026-10-07

The audio board previously drove `T65.rdy` and the combinational audio-mixer mute directly from the top-level `pause_cpu` level, registered on `clk_sys` (45.153061 MHz). Timing analysis identified a failing path from that source into the audio T65. The audio board runs from `audio_clk` (14.366883 MHz), a distinct output of the core PLL. The main-domain pause output remains connected directly to the main CPU; only the audio-domain consumers now use a local synchronized copy.

`rtl/pause_sync.v` adds `exidyPauseSync`. It shifts the pause level through two registers clocked by `audio_clk`, initializes both to unpaused, and marks each register with Intel's `SYNCHRONIZER_IDENTIFICATION FORCED IF ASYNCHRONOUS` attribute. `rtl/audio_board.v` instantiates it once; the second stage drives both the audio T65 ready input and `exidyAudioMix.mute`, so CPU pause and audio mute stay aligned. The first stage has no functional fanout. Reset does not gate this level synchronizer; the source pause controller resets its output low, and the synchronizer follows the source after two audio edges.

`sim/pause_sync/tb_pause_sync.sv` checks startup, pause assertion and release, the two-edge latency, no change between destination edges, and equal CPU-ready/mute behavior. A raw-pause mixer instance is the negative control: it mutes immediately between audio edges, while the synchronized instance remains unchanged until the second edge. The runner reports `PASS audio pause synchronizer and mute/ready alignment`.

Full requested runner invocation from WSL Arch Linux:

```sh
python3 -u tools/run_tests.py
```

Result: Verilator 5.052; 8 results, 7 PASS, 0 FAIL, 1 SKIP. The passing results were audio mono mix, pause synchronizer and mute/ready alignment, audio-mix mutant rejection, interrupt cause profiles, audio reset synchronizer, reset release (including bridge and two negative controls), and connected expansion suite including ROM cases. Audio RAM MAME trace replay was skipped because no `--traces DIR` was supplied and the sequence traces were unavailable. No Quartus run was part of this change.

Implementation evidence is simulation-level only. The runner test does not instantiate the full T65 or prove physical metastability resolution, placement, or timing closure. Add `rtl/pause_sync.v` to `rtl/index.qip` and verify the synchronizer-chain identification, first-stage exception scope if one is needed, and the former critical path in a fresh Quartus report. Keep the second-stage-to-consumer paths timed and avoid a broad pause or audio-clock exception.

## Full-flow integration follow-up

The module is now included in `rtl/index.qip`. The first full-flow attempt failed during elaboration because the multiword `SYNCHRONIZER_IDENTIFICATION` attribute value was unquoted. The value is now escaped and quoted inside the Verilog attribute string. This changes tool metadata only; full-flow verification follows. The functional test passed before the metadata repair, and no timing exception was added for pause.

The subsequent complete flow at `594b8dd` succeeds in compilation, with audio setup +0.082 ns. Main setup remains -0.948 ns on the separate PIA return-data path. See [corrected-clock build](local-corrected-clock-build-2026-10-07.md). Fresh MAME trace replay also passes the runner with 11 PASS, 0 FAIL, 0 SKIP. Physical synchronizer placement/recognition and hardware pause/reset acceptance remain open.
