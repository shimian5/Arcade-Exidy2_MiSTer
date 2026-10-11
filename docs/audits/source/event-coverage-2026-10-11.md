# Exidy event and timing coverage review — 2026-10-11

This review reads the fitted `check_timing` report from `simulation/timing-016b4c9/check-timing.rpt`, source RTL, and the existing event-clock audit and IRQ fixture. The report belongs to production FIFO timing candidate `016b4c9`; the source tree inspected here is HEAD `012917a`. No Quartus flow, RTL, SDC, project file, or timing constraint was changed or run for this review.

## Fit report classification

The summary reports 3263 `no_clock`, 118 `multiple_clock`, 96 latch, and one loop issue. These are whole-design totals. The HPS and system hierarchy accounts for most no-clock rows, so those totals are not an Exidy defect count.

Within `emu|ex2`, the multiple-clock table contains exactly 32 endpoints: eight bits each in `U12D_M1VA`, `U13D_M1VA`, `U14D_M1VA`, and `U15D_M1VA`. These are the four sprite `oLS166` instances clocked by combinational gated BCLK expressions. The latch table contains 48 bits from three 16-bit `berzerk_sound_fx:U3D_6840` counters and 48 bits from six 8-bit `oLS166` shifters (`U12B_CHAR_OUT`, `U12D_M1VA`, `U13D_M1VA`, `U14D_M1VA`, `U15D_M1VA`, `U4_VIVY`). The report explicitly says the latches come from analyzed combinational loops; source review must distinguish Quartus's inferred implementation artifacts from intentional behavioral event logic.

The single loop is the four-node feedback path through `rCPU_IRQ` (`rCPU_IRQ~3` and `rCPU_IRQ~2`). Source has a multi-event latch assignment at `rtl/Exidy2.v:673`, sensitive to `negedge BCLK`, `negedge COINT`, and `negedge nEIR`, with the event equation `(rCPU_IRQ|VL1|COINT|cDET_sel)&nEIR`. `EIR` captures on `posedge rCPU_IRQ` at line 678. This is functional sticky-event/read-clear behavior, not a free-running domain and not a safe target for an SDC exception.

The `no_clock` event-source list identifies seven Exidy nodes that feed clock pins without an assignment: `T65:M6502|AD[0]`, `hscnt[5]`, audio `rst_sync`, `U3AB_counter[0]`, `U1AB_counter[0]`, `NINC`, and `PH_6B`. These classify as follows:

| Fitted source | Source role | Endpoint family / interpretation |
|---|---|---|
| `T65:M6502|AD[0]` | CPU address bus bit | Participates in decoded CPU write events (`nWM*`, `nWMOL`, `nWCPL`, `WODD`, `WEVEN`). These are transaction events and must be validated against T65 bus phase before conversion to clock enables. |
| `hscnt[5]` | Raster counter state | Feeds `CBLB`, `X5SRLD`, gated shifter clocks, and related raster/load behavior. It is state-derived event logic, not an oscillator. |
| `PH_6B` | Registered counter-phase pulse | Participates in `X5SRLD` and character capture/load. Preserve the source phase and pixel alignment if consolidating into a parent-clock enable. |
| `U1AB_counter[0]`, `U3AB_counter[0]` | 6840 timer terminal-event logic | Derived from timer counters/reloads; event cadence varies with control/profile. Keep within the audio timer event contract rather than assigning a periodic clock. |
| `NINC` | Audio timer increment event | Registered on `PH_1`, then clocks timer state. A candidate must preserve the exact pre-edge count, reload, and `GAME` reset ordering. |
| audio `rst_sync` | Reset synchronizer output | Reset/control node detected as a clock due downstream use in audio logic; it is not a functional clock domain. Audit its reset recovery/removal separately. |

The report contains 169 Exidy-hierarchy `no_clock` rows: 79 directly under the core, 75 under the sound-board hierarchy, and 15 mapped `AUDIO_RAM` address/data input registers. Other event-state rows cover sprite counters captured by CPU write decodes, raster-boundary state, audio-timer state and output state, and IRQ/EIR state. These require their own behavioral contract; the presence of a row is not evidence that every endpoint can simply move to `master_clock`.

## Smallest source-side remedy and contract

The most bounded high-value next production experiment is the `rCPU_IRQ` process because it is the only reported combinational loop and an existing fixture already extracts the real event/EIR source. The implementation candidate should replace the multi-event procedural feedback with one explicit sticky request state and a combinational next-state equation, then capture EIR only on the request's asserted transition. It must preserve this contract:

1. A vblank, sampled coin, or selected collision request sets the sticky request.
2. An active `$5103` read (`nEIR` falling) clears the request and suppresses a coincident event, matching the existing `& nEIR` gate and event ordering.
3. EIR snapshots the same source fields on the request assertion and retains them through read-clear until the next request.
4. Coin request detection continues to use sampled `COINT`, while the EIR coin bits continue to use the live `m_coina/m_coinb` values, unless a separate behavioral change is explicitly intended.
5. Profile 0 and profile 1 collision paths, vblank, coin, clear, coincidence, and held-source cases are all covered. Cold-start behavior remains unspecified until a reset contract is separately established.

The isolated candidate is [irq_event_sticky.sv](../../../candidates/timing/irq_event_sticky.sv). It replaces the feedback expression with explicit asynchronous clear and sticky set branches while retaining the legacy `negedge BCLK`, `negedge COINT`, and `negedge nEIR` sensitivities. The extracted differential fixture now instantiates both the unchanged production event span and this candidate, and compares IRQ and EIR state after each directed step. Run it with `python tools/eir_event/run_fixture.py`; the recorded run used Verilator 5.052 through WSL with `MAKEFLAGS=OPT_FAST=-O0` and passed all 34 assertions. Coverage includes profiles 0–3, expected profile-specific collision snapshot values, coin sample/live-value timing, vblank, sticky hold, read-clear acknowledgment, simultaneous vblank/read-clear priority, and source held during the read.

The candidate and fixture prove source-level functional equivalence for the directed scenarios, but the isolated full Quartus compile rejected the candidate before fitting. Quartus 17.0.2 Analysis & Synthesis reported Error 10200 at the conditional inside the multi-event `always`: it could not match the condition operands to the event-control edges. It also emitted Warning 10240 and Info 10041, explicitly inferring a latch for `irq`; hierarchy elaboration then failed. The probe uses Cyclone V `5CSEBA6U23I7`, a minimal top wiring the candidate and real `exidyIntCause` payload, and a minimal SDC with `master_clock` and BCLK clocks. The full command was `quartus_sh --flow compile irq_sticky_probe` in ignored `simulation/irq-sticky-probe/`. No fitted netlist was produced, so this candidate did not resolve the timing report's loop and has no post-fit timing evidence.

The production block has no reset input or specified power-on value for either `rCPU_IRQ` or `EIR`, so adding reset behavior would change the source contract. The fixture establishes known state by generating a real event and tests `$5103` clear/re-arm; cold-start behavior remains unspecified. The next implementable remedy must use one real parent clock and an explicit request-capture contract. Before choosing the sample edge, prove `VL1`, `cDET_sel`, and the decoded `nEIR` read-select persist or are synchronous across that edge, and preserve the sampled-COINT versus live-coin snapshot distinction. A regression must compare set/clear coincidence and EIR payload against the current event ordering, including all four profiles, before any production change. Do not add a clock declaration, false path, or broad exception to hide these event-source crossings.

## Other endpoint families

The 32 shifter multi-clock endpoints should be handled as one dedicated serialization candidate, retaining the asynchronous `PE` load and `clr` behavior while converting the state update to BCLK plus a qualified shift enable. The enable must be shown to match the gated-clock rising-edge sequence, including when the gate changes while BCLK is high. This remains a higher-risk display-equivalence task than the IRQ candidate.

The 96 latch findings span both 6840 timer counters and six shifters. They do not justify blanket lint suppression or timing waivers. The timer counters need a legacy-versus-candidate waveform contract for supported profiles and reset/reload cases. The shifters need the load/shift/clear sequence contract above. Until then, preserve their source semantics and treat TimeQuest latch classification as a diagnostic limitation.

The mapped `AUDIO_RAM` input endpoints are implementation-generated RAM port registers. First identify the specific port and its intended clock from the `dpram_dc` instantiation and fitted RAM settings; do not infer a clock from the generated endpoint name or suppress these checks broadly.

## Evidence and limits

The report is static fitted-netlist timing evidence only. It does not establish asynchronous event capture robustness, functional equivalence after a rewrite, reset recovery on hardware, or game acceptance. No post-fit report was regenerated here. Report counts and endpoint names refer specifically to `simulation/timing-016b4c9/check-timing.rpt`; later fits may renumber or alter inferred nodes.
