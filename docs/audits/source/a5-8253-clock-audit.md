# A5: 8253 audio clock and counter source audit

Date: 2026-10-07. Scope: read-only comparison of the selected FPGA 8253 implementation with the pinned MAME 0.288 Exidy sound-board source. This is a source audit, not a timer-level equivalence test, audio capture, or hardware acceptance result.

## Selected implementation and wiring

The Quartus QIP path selects `modules/k580vi53/k580vi53.v` through `modules/k580vi53/index.qip`; `rtl/audio_board.v` instantiates one `k580vi53` as `i8253_2B`. The neighboring module source is the actual counter implementation, not an alternate or simulation-only PIT. The three channels receive `clk_sys=audio_clk`, `clk_timer={~auCLK,~auCLK,~auCLK}`, and `gate=3'b111`. Writes are decoded when the audio CPU writes the `$1800-$1fff` window (`io18_1F`), with `addr[1:0]` selecting channel 0-2 or control register 3. Reads are tied off. This matches the MAME Venture audio map's `$1800-$1803` PIT write-only decode mirrored through `$1fff`; MAME explicitly marks it `nopr()` for reads.

The QIP also selects the `audio_board.v` instance. `i8253_active` is generated but not used in the actual filter input: `i8253_snd = i8253_audio_out & i8253_active` is declared but unreferenced, and the filters consume `i8253_audio_out` directly. Thus the hardware model does not suppress a PIT output based on its `sound_active` classification.

## Clock contract and rate difference

Pinned `simulation/reference_sources/exidysound.cpp` is from MAME 0.288 commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`, SHA-256 `57c0edc71e9faf0a37e48eef406586e95a95902ef0f9e53275a7ad3326fad660`. Its Exidy board constants are `CRYSTAL_OSC = 3.579545 MHz`, `SH8253_CLOCK = CRYSTAL_OSC / 2 = 1.7897725 MHz`, and `SH6532_CLOCK = CRYSTAL_OSC / 4 = 894.88625 kHz`. All three PIT input clocks use `SH8253_CLOCK`; all gates are initialized high. This gives the expected 2:1 PIT-to-audio-CPU clock ratio.

In RTL, `audio_clk` is the fitted core PLL output 2 at 14.366883 MHz. `auCLK` is registered high for one `audio_clk` cycle whenever the 3-bit phase counter is zero; its inverted output is connected to the PIT. The timer samples that signal on `clk_sys` and advances on each detected falling edge, so there is one counter tick every eight `audio_clk` cycles: 1.795860375 MHz. `auPH0` enables the audio CPU every 16 `audio_clk` cycles: 897.930188 kHz. The ratio remains exactly 2:1, but both rates are about 0.340% above MAME's nominal crystal-derived rates (about +6.09 kHz for the PIT and +3.04 kHz for the CPU). That is the consequence of the fitted PLL frequency, not a further integer divider error. The documented `/8` tick also depends on the registered pulse edge as described above; it is not an 8253 clock enable.

## Counter-control behavior visible in RTL

The RTL recognizes the 8253 count-control read/write selection fields and separate LSB/MSB read and write sequencing. RW=`00` latches the current counter once and does not write a control word. RW=`01` loads the low byte, RW=`10` loads the high byte, and RW=`11` alternates low then high; BCD mode (`cw[0]`) clamps each digit above 9 and uses a BCD decrement. Counter ticking is edge-detected in `clk_sys`; because the clock input is passed to each timer as an inverted pulse, the selected edge is once per `auCLK` pulse. The implementation has cases for modes 0 through 5, with gate/start behavior differentiated by mode.

The RTL comments explicitly identify two implemented mode bugs: modes 0/1/4/5 wrap rather than stop at terminal count, and programming a control word in modes 1/5 does not reset the old counter. Other visible caveats are that the reset branch clears only `stop1`, `ld_count`, and `cw` (and forces the read-data output to `0xff`); it does not explicitly initialize `counter`, `out`, `sound_active`, read/write edge-history registers, or mode state. Counter readback is inaccessible in this integration because `rd=0`. `sound_active` is sampled on PIT input edges and describes only modes 0 and 3 (`!cw[3:1]` or mode 3), but its intended gating is currently unused.

MAME's Exidy source proves the channel clock values, write-only mapping, output callback wiring, initial `m_pit_out=0`, high gates, and mixing of each high PIT output into the sample. It delegates counter details to MAME's generic `PIT8253` device, whose implementation is not part of the pinned local reference-source bundle inspected here. Therefore this audit does not claim exact agreement or disagreement for the RTL's mode 0-5 edge cases, latch semantics, BCD handling, or reset behavior against MAME's generic device. It also did not establish which modes/byte-write sequences the captured games exercise: existing game captures are main-CPU traces and do not record the audio CPU's PIT writes. No unsupported mode should be fixed based on assumptions about game usage.

## Output level and evidence boundary

MAME's `generate_music_sample()` adds `BASE_VOLUME = 32767 / 6 = 5461` for each asserted channel (up to 16383 before stream normalization); `pit_out()` updates a three-bit state mask and forces a stream update at transitions. The FPGA sends each timer's one-bit `out` as bit 5 of a 12-bit filter input, i.e. a pre-filter value of 32 per channel. The three channels are routed independently through `jtframe_jt49_filters`; the common mixer later halves and sums the filtered 8253 and 6840 sources. The raw constants are visibly very different, but they are at different points in the filtering and output pipeline. Without evaluating the filter transfer response and capturing the same register writes, this is not enough evidence to assert a final audible gain ratio or specify a safe scaling change. `sound_active` not being wired into the stream is a concrete integration difference; whether it changes game output depends on modes/output states in actual traffic.

## Focused follow-up evidence needed

1. Capture audio-CPU writes to `$1800-$1803` for each CPU-board game under the pinned MAME run, preserving timestamp, address, and data. Decode control words and report observed modes, RW formats, BCD selection, reload sequences, and channel use. Existing main-CPU reference traces cannot answer this.
2. Build a small RTL timer bench that checks reset/start, control-word writes, RW byte ordering, latch/read behavior at module level despite the integrated `rd=0`, gates, and terminal/output timing for modes actually observed in the captures. Include the specific documented mode 0/1/4/5 wrap and mode 1/5 reprogram cases as characterization, not assumed acceptance criteria.
3. Compare the same observed PIT command streams against the exact pinned MAME 0.288 generic PIT implementation, then compare output transition times at each model's declared clock. Keep the nominal crystal and current fitted PLL rate as separate tests.
4. For volume, feed equivalent MAME/RTL PIT output transitions through the complete audio paths, capture normalized PCM, and compare per-channel and mixed peak/RMS levels. Do not adjust the bit-5 input scale from raw-value comparison alone.

No production files, simulations, MAME process, Quartus flow, or generated outputs were changed or run for this audit.
