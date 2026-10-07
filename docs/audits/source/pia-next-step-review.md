# PIA return-byte next-step review

This is a design proposal only. The active setup-steering fit is not complete, and no production RTL or SDC is changed here.

## Current contract visible in RTL

`PIA_8B` and its PB output register run on `audio_clk`; `audio_DO_bus` is the DDR-masked PB output and is sampled by `audio_byte_stage`. The PIA write process updates PB data on an audio rising edge. In CB2 mode `"100"` (write-PB-clears, CB1-edge-sets), `portb_write` is registered by that write, so the CB2 output clears on a later audio rising edge. The return pipeline samples the full byte on audio rising edges and then on master rising edges.

The source CB2 output is wired to `PIA_9B.ca1`. The PIA CA1 edge detector samples on falling `master_clock` edges and registers its edge/IRQ state; `PIA_9B` PA data selection is combinational from `pa_i`, while its PA read/CA2 handshake effects are clocked on the master rising edge. The main `CPU_databus_in` is also registered on every master rising edge. `T65` sees that prior registered byte at its `PH_1` enable, which occurs once per 64 master ticks. The paired fixture already checks this prior-bus observation and the earliest modeled CPU read after the CA1 handshake event.

Reset and pause constrain any change. The audio source stage clears from synchronized `RESET_n_au`; `PIA_9B` has raw asynchronous reset. The separate master-domain valid bit masks retained byte data immediately on reset and only exposes it again after a master edge. Pause affects the two CPUs' ready inputs (audio pause is synchronized), but neither PIA clock nor the return registers stop. A repair cannot use pause as a data-stability gate or remove the immediate destination reset mask.

## Candidate if the setup-steering fit does not close the path

The next bounded physical experiment would move only the destination byte capture from `posedge master_clk` to `negedge master_clk`, retaining the same full-byte register, source stage, validity/reset logic, PIA wiring, and CA/CB protocol. The intent is to sample the already-held response on the opposite master phase, making it available before the next positive edge that updates the PIA read-side and CPU data-bus registers. It adds no byte pipeline stage, uses an ordinary related-clock path, and can be judged with normal setup and hold timing. It is an experiment, not a claim that half-cycle capture is already behavior-preserving: it changes when `PIA_9B.pa_i` can change relative to its read mux and CA1 detector.

Before considering this, extend the paired production-PIA fixture to the negative-edge candidate and cover every supported relative PLL phase, source write coincident with source capture, CB2 falling notification, PIA9 CA1 edge/IRQ visibility, earliest legal PA read and the prior registered `CPU_databus_in` sample, plus CA2 acknowledgement and response hold until acknowledgement. Include full/partial PB DDR, distinct multi-bit patterns, back-to-back transactions, source reset, asynchronous PIA9 reset assertion/release, and pause while a response is outstanding. Assert that the correct whole byte reaches the first legal CPU sample and remains stable until CA2 ack; do not relax the earliest-read assertion to make a phase pass. Verify that PIA clocks and return capture continue during CPU pause.

The candidate timing review must report all eight audio-stage-to-master-data paths on the new opposite edge, their hold checks, the valid-mask/read path, and reset recovery/removal. Replay the original unmodified SDC on the fitted candidate. Reject the experiment if any edge/phase yields stale data, if the CA1/CA2 ordering changes, if hold or reset timing fails, or if setup closure exists only under a retained steering exception.

## Evidence limit

This phase change has a plausible timing mechanism but is not yet justified as a functional repair. The pinned MAME callback-order audit corrected the earlier timestamp interpretation: the seven associated main-PA reads occurred before their apparent audio-PB writes, so they do not establish a write-then-read hold interval or its latency. The current synthetic PIA fixture establishes its tested protocol schedule, not every game's firmware schedule. Therefore do not apply a multicycle exception, data capture enable, extra synchronizer, or opposite-edge capture to production without the fixture extension and actual firmware/read-order evidence. If a fail-safe opposite-edge test cannot prove the earliest legal read, the correct result is insufficient evidence for a further protocol-based repair.
