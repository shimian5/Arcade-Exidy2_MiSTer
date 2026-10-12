# Mouse Trap speech subsystem join — 2026-10-12

## Result

The new `mousetrapSpeechSubsystem` wrapper passes an actual-ROM, actual-T80 simulation through `speechRomBus`, `mousetrapVoiceIo`, the MC3417 event model, fixed-rate renderer, both board filter sections, and the mono mix. The ROM backend returns data after a deterministic varying delay of 3–11 audio-clock cycles. The run completed at 200 ms with 69,054 ROM requests and 69,054 ordered responses, 3,090 T80 I/O writes, 3,086 digit writes, and 3,093 falling-edge decoder events. The first 32 digit bits match the prior actual-firmware run's ordered prefix: `01010110110101010101010101010101`.

The renderer/filter accepted 38,399 sample ticks; 38,340 produced nonzero filtered PCM. The fixture rejects unknown values across the digit, decoder, renderer, filter, mixed output, and PB0 paths; it also checks that every request has a corresponding response before the final gating phase. The sticky filter overrun and clipping indicators stayed clear, and the mixed output moved from the fixed base input during active speech. The final log is `simulation/mousetrap_subsystem/modelsim-subsystem-20261012-124220-947/vsim.log` (ignored). Its generated run manifest records the staged ROM hash and simulation-only CPU initialization.

## Clock and lifecycle checks

The test uses `CLK_HZ=14,366,883`. The wrapper's integer phase accumulators use 25 bits for the 1,789,772.5 Hz nominal CPU enable, 34 bits for the 30,939.14 Hz RC toggle, and 24 bits for the 192 kHz renderer enable. Over a 10 ms interval, the fixture requires respectively 17,896–17,899 CPU enables, 308–311 RC toggles, and 1,919–1,921 sample enables; the run passes those bounds. Sum widths add one carry bit and compare against threshold-sized constants.

Before speech enable and image readiness, the CPU remains held reset, there are no ROM reads, and `mono` equals `audio_base` exactly. During pause, the output mutes, CPU enable and both generated audio enables stay low, and all three phase accumulators hold. With pause still active, asserting the global CPU reset preserves decoder history, step, and integrator. Disabling speech and then removing image readiness each holds the speech CPU reset while returning the base audio unchanged.

The decoder endpoint-valid pulse is retimed by one audio clock before the stream renderer consumes it. Renderer sample enable is delayed one clock before the filter input. Activity counts, known data, fresh nonzero filter output, and zero overrun across the complete firmware interval exercise these boundaries at their normal cadence.

## Reproduction and assumptions

Run from the repository root in PowerShell:

```powershell
./sim/mousetrap_subsystem/run_subsystem.ps1
```

The runner verifies the 16 KiB staged `mtrap.hex` against `docs/design/expansion-adapter/increment-07-roms.json`; payload SHA-256 is `96aabec1a71953afb98f4a28d090c9d2b3564cf7b487cf55604c96aaeba23bf0`. No ROM bytes are embedded in the testbench. As in the earlier actual-firmware fixture, the runner makes a simulation-only copy of `T80_Reg.vhd` with the `RegsH` and `RegsL` banks initialized to zero, matching the MAME constructor assumption. The production CPU source is unchanged by the runner; the production cold-boot register values remain a separate acceptance question.

The delayed backend has one outstanding request and does not test cancellation of an arbitrarily late response across a CPU reset. The run waits for the ordinary firmware stream and checks request/response counts at completion; production loader reset/cancel behavior remains a separate boundary. It also does not establish native MAME phrase, analog, or hardware listening parity. The generated wrapper has not been requalified by a full production Quartus flow in this audit; that flow is being run by the parent task after wrapper freeze.
