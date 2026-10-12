# MC3417 stream contract (pinned MAME reference)

Audit date: 2026-10-12  
Sources: `simulation/reference_sources/hc55516.cpp`, `hc55516.h`, and `exidysound.cpp` in this checkout. This records the behavior of that source revision, not a claim about analog MC3417 hardware or parity with an FPGA core.

## Exidy wiring and event order

Mouse Trap instantiates `MC3417(config, m_cvsd, 0)`: clock argument zero selects software-driven clocking. Its timer toggles `m_cvsd_clk` and calls `clock_w` on both transitions, with a timer rate of `CVSD_CLOCK * 2`. `voiceio_w` writes the digit when address bit 4 is clear. The digit and clock are therefore independent host events; this code does not queue a digit against a future edge.

The common handlers impose a strict order:

1. `digit_w(d)` calls `m_stream->update()` using all old state, then stores `bool(d)` in `m_buffered_bit`.
2. `clock_w(c)` also calls `m_stream->update()` first. If `c` differs from `m_last_clock_state`, it clears `m_samples_generated`, then calls `process_bit(m_buffered_bit, c)`. Finally it stores `c` as the last clock state.
3. MC3417 `process_bit` acts only when the changed state is the active edge, which is FALLING. On that edge it shifts the buffered bit, updates the integrator and step estimator, applies leakage, and sets `m_next_sample` from the new integrator. A rising edge has no MC3417 state effect.

Thus the audio up to an event is rendered before that event changes digit or clock state. A digit write immediately before a falling edge is consumed by that edge. A repeated same-level `clock_w` still updates/flushes the stream first, but does not clear the count or process a bit. A repeated digit write likewise splits the stream at the write time even when the value is unchanged.

## Software-clock stream update

At 192,000 samples/second, each software-clock `sound_stream_update` first adds the whole callback block size to `m_samples_generated`. If the result is **strictly greater than** `SAMPLE_RATE / 32` (6,000 samples, 31.25 ms), it sets the count to 192,000 and sets `m_next_sample = 0`. Equality at 6,000 does not silence. This test happens once before rendering the block, so a block that crosses the boundary is silenced from the start of that block, including samples that mathematically precede the 6,001st no-clock sample. A later changed clock edge clears the counter; a same-level call does not.

Interpolation is recomputed once per callback block. With `N = stream.samples()`, it starts at `m_curr_sample`, uses slope `(m_next_sample - m_curr_sample) / N`, then emits `N` samples while adding that slope after each sample. It sets `m_curr_sample = m_next_sample` before the loop. Consequently sample zero is the previous current value; the last emitted sample is one slope increment short of the target, while internal current state is set exactly to the target. `N` is assumed positive by this implementation.

In software-clock mode, the stream loop itself does not clock the chip. State changes come only from explicit handlers after their pre-event `update()`. The block length `N` therefore changes the emitted ramp: dividing the same endpoint difference by different `N` yields different intermediate samples. More frequent updates also create more interpolation segments. Extra no-op digit writes and repeated clock levels can therefore alter the discrete waveform segmentation without altering the decoded bit sequence. This is an implementation property called out as questionable in the source TODO (“MC3417 interpolation slope being determined by the number of samples in the current stream slice doesn't make sense”).

## Reset behavior and what it does not reset

The common `device_reset()` resets only `m_last_clock_state` to low. The MC3417 class declares no reset override, so a device reset does not reinitialize its shift register, buffered digit, integrator, step filter, `m_curr_sample`, or `m_next_sample`; nor does it clear `m_samples_generated`. A falling level immediately after this reset is unchanged from saved low; a high transition must be observed before the next falling transition is decoded. Treat this as warm-reset behavior of this reference implementation, not a chip power-on model. Constructor initializers do establish zeros for the MC3417 analog/sample state and common buffered state on initial creation.

## FPGA interpretation and limits

An FPGA clocked at a fixed audio sample rate can implement deterministic state updates on the specified falling input edge, plus an explicit idle timeout based on elapsed sample ticks. It can also render a chosen interpolation rule between decoded values. That can match the digital decoder trajectory and a deliberately specified fixed-rate audio contract.

It cannot claim bit-for-bit MAME stream parity from the decoder equations alone. Exact output depends on MAME callback boundaries, block lengths, and calls to `update()` before every digit/clock handler—including redundant writes. Those host scheduling boundaries are not represented by the MC3417 pins. Reproducing them would require feeding the FPGA or a comparator the same event timestamps and stream-block boundaries and duplicating MAME's pre-event rendering and endpoint arithmetic. A stable hardware interpretation should instead define a fixed audio sample cadence and interpolation convention, then compare decoder state separately from the host-specific stream waveform. Do not describe that as hardware parity or exact MAME audio parity without such a boundary-matched comparison.

The external-oscillator branch is not the Exidy configuration audited here: it advances `m_samples_generated` per audio sample and derives clock level from sample count and configured clock frequency. The software-clock timeout and callback-block analysis above must not be transferred to that branch.

## Executable reference qualification

`tools/mc3417_stream/qualify.py` verifies the full pinned `hc55516.cpp` hash (`4eef48eb9589f8fd914692cd0251457495d6dc65a491326d542f20a5d8571ba4`), extracts its actual bit and stream methods, and builds a small software-clock wrapper with float `sample_t`. Generated C++ retains the source license/copyright header and stays ignored. This is the actual method under a bounded wrapper, not the complete MAME sound scheduler.

The final run passes **12 directed assertions**: half-open positive/negative ramps at 1/2/13/4096 samples, strict timeout boundary and crossing-block ramp, subsequent silence, repeated-clock count retention, warm-reset stream retention, rising/falling edge count behavior and segmentation sensitivity. A zero-slope mutant is rejected at the two-sample ramp; an early `>= 6000` timeout mutant is rejected at the exact threshold. The runner demands those specific failure reasons and checks exact ramp output lengths.

A diagnostic replay of 3,093 private firmware-decoder endpoints renders 44,414 samples at 192 kHz, including a stopped-clock tail that settles to zero; normalized peak is 0.133033812. This uses chosen event blocks and quantized timestamps, injecting captured Q24 endpoints. It is not native MAME scheduling, firmware/bus timing, filtered PCM, a spoken phrase or hardware equality. Generated CSVs/report/source/binaries remain in ignored `simulation/mc3417_stream/`.

Reproduce from WSL in the repository: `python3 tools/mc3417_stream/qualify.py --firmware-samples simulation/mousetrap_firmware/modelsim-firmware-20261012-113048-513/samples.csv`. The directed contract checks also run without the private optional replay. Requires g++ and the documented pinned local source. No production RTL, QIP or release artifact changed; a new Quartus build is therefore not part of this reference-only increment.

Next implementation unit: a deterministic fixed-rate FPGA stream renderer with explicit cold/warm reset, edge/idle timeout and interpolation cadence; compare it under matched boundaries. Then derive both Mouse Trap low-pass stages and gain/mix, followed by production command/loader binding and fresh full Quartus/hardware acceptance. The 31.25 ms threshold is a MAME emulation behavior, not established physical MC3417 silence behavior.
