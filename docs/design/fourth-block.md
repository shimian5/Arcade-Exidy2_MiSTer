# Fourth worker block

Started 2026-10-06 on owner instruction to continue the next batch of three. Sol orchestration/review and three existing Luna workers; no production edits or Quartus build in these units.

| Unit | Worker | Owned paths | Status |
| --- | --- | --- | --- |
| Venture startup/reference diagnosis | sim_harness | tools/reference_cases/, docs/reference_cases/, simulation/venture_startup/ | Reviewed: final paired capture and independent replay match; exact arrow identity/core comparison remain open |
| Actual video pipeline and clock evidence | baseline_releases | sim/video_capture/, tools/video_capture/, docs/design/video-capture/, simulation/video_capture/ | Reviewed diagnostic: reproduced RGB-scope and missing-coordinate failures; production pixel order remains unaccepted |
| Expansion transaction and memory-latency fixture | mra_byte_audit | tools/expansion_transport/, sim/expansion_transport/, docs/design/expansion-transport/, simulation/expansion_transport/ | Reviewed model: 16 tests pass; independent six-MRA report matches |

The integrator owns WORKPLAN.md and this index. Prior accepted reference captures stay unchanged. ROM data, disassembly and images stay in ignored simulation paths; NAS access is read-only.

Acceptance follows the [integration gates](integration-gates.md). A reference startup diagnosis is not a core fix; a synthetic video pattern verifies transport, not game rendering; an isolated session model is not a production loader. PLL parameter reconstruction is distinct from actual generated counter/fit evidence. Each worker must retain executable commands, relevant hashes and concrete failures/limits for independent replay.

## Integrator review checklist

- Venture: derive the startup-loop purpose from observed instructions and state before changing configuration; preserve original failed evidence. Distinguish a longer self-test from a permanent hang. Record the earliest point normal interrupt/PIA/gameplay activity starts, if reached.
- Video: instantiate production wrapper/mixer dependencies, record any synthetic upstream substitution, compare every active pixel to an independent coordinate scoreboard, and expose boundary/off-by-one failures. Test the actual Exidy three-bit-to-six-bit replication. A known gamma-bypass result does not prove enabled gamma/effects or game imagery.
- Clock: source frequency declarations are requested values; a rational reconstruction that rounds to them does not identify fitted M/N/C counters. No cascade feasibility or long-term clock alignment claim without the relevant fitted evidence.
- Transport: test actual legacy MRA entry ordering and both session directions. A completed session must retain valid expansion contents while its next-session marker is disarmed. Stale data must not become visible when an unrelated or failed new transaction occurs. Specify whether late index-2 raster/config updates are inside reset/readiness policy.
- CPU memory: follow registered PH_1/T65 enable and registered CPU data selection, including same-edge nonblocking behavior. Demonstrate safe and deliberately missed deadlines; specify proposed CVSD CPU clock separately. No raw multibit CDC proof follows from a Python timing model.

## Review and next handoff

All three bounded units are reviewed. W02/W03/W06/W07 remain active; no production RTL/MRA/RBF changes or Quartus build occurred.

[Expansion transport report](expansion-transport/transport-model.md): independent 16-test replay passes. The separately regenerated six-MRA order report has SHA-256 `98f767226294887537f3818039a0309dc05d7a8537bf66b49088d1d0e2155aba`, matching the retained document. Hardware transfer/CDC, expanded MRA/profile encoding, actual fitted RAM timing, FAX PROM routing and CVSD clock-domain access remain gates.

[Venture startup findings](../reference_cases/venture-startup.md): the longer zero-input probe reaches normal IRQ activity at frame 1720 (~28.68 seconds) and a title/attract screen at frame 1800. Root independently replayed the post-startup input case: 189,581 bus events, 13 images, 82/81 distinct object-X values during input and 2,990 IRQ acknowledgement reads. Held right/fire CPU-port value is `$EB`. This validates a gameplay/input reference; object position changes alone do not establish arrow identity or reproduce a defect in the FPGA core.

Final Venture worker runs `active03/active04` and root `integrator_active02` match metadata, exact bus/events bytes and all 13 decoded frames. ROM-verification text also matches after normalizing UTF-16/UTF-8 BOM and newline differences between PowerShell versions; raw file hashes remain recorded. The [retained review manifests](venture-reviewed-manifests.json) include the pair, right-only control and final independent run. Right-only input `$FB` preserves the player-coordinate sequence while the second object diverges after fire is added; this is correlated movement evidence, not confirmed arrow identity.

Clock arithmetic refinement: using the actual source output 0 as the downstream reference permits Native `M32/N1/C32 = 1` and CRT `M131/N4/C35 = 131/140 = 262/280`. This removes dependence on proving source outputs 0/1 have a 4:1 ratio. It remains a conditional proposal: legal PLL routing/cascade bandwidth, actual programmed counters, lock/jitter, Native transport and fitted timing are unverified.

[Video diagnostic](video-capture/README.md) and [retained results](video-capture/results.json): independent WSL replay matches both gamma-mode diagnostics and every retained source hash. Each compares 65,536 DE pixels over 256 rows with cadence eight master clocks and no line-length errors, but records 49,152 color mismatches and 256 missing source coordinates. The unchanged mixer emits implicit undriven RGB-net warnings in Verilator. Neither gamma mode passes RGB/order acceptance; provisional latency 18/2 clocks is not an accepted CRT tap contract. Sync widths/phases, enabled gamma/effects and physical output remain open.

The PLL QIP decoder independently yields generated metadata M177/N7 and C28/112/88, matching all three rounded frequency declarations. It supports the configured relationship more strongly than decimal reconstruction, while actual fitted counter/cascade evidence remains absent.

## Next three bounded assignments

Assigned on the next owner continuation; dispatch and review are recorded in the [fifth block](fifth-block.md).

| Unit | Scope | Acceptance |
| --- | --- | --- |
| Video simulation compatibility and tap origin | Explicitly labeled generated compatibility copy, leaving production framework unchanged; resolve generated-net scope and the missing 256 coordinate samples. | Preserve source assertions/attribution, distinguish normalization from source fixes, then pass all eight coordinate-bit planes and measure native sync widths/phases. No RGB acceptance from a zero-output diagnostic. |
| Sprite/collision reference-to-RTL fixture | Identify Venture's relevant object/control state and add a bounded source-derived sprite/collision fixture using accepted MAME cases. | Record exact compared state, ROM provenance and first divergence; distinguish isolated event replay from CPU/full-board acceptance. Keep exact arrow identity open until evidenced. |
| Expansion loader RTL prototype | Isolated synthesizable session/control prototype and runtime read fixture from the accepted model; no production top-level wiring yet. | Replay adversarial transaction cases against RTL, demonstrate reset/readiness and retained base writes, test read deadlines and identify CDC/fit gates. Preserve legacy stream interpretation and provisional FAX profile/PROM limits. |
