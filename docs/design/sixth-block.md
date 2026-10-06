# Sixth worker block

Started 2026-10-06 on owner instruction to continue the next three Luna workers. The integrator owns this index and WORKPLAN.md. The [fifth review](fifth-block.md) is the retained baseline; new fixtures preserve its evidence.

| Unit | Worker | Owned paths | Status |
| --- | --- | --- | --- |
| Independent video source queue and boundary origin | baseline_releases; integrator completion | tools/video_queue/, sim/video_queue/, docs/design/video-queue/, simulation/video_queue/ | Reviewed synthetic queue gate passes |
| Sprite serialization and raw-address reference | sim_harness; integrator completion | tools/sprite_serialization/, sim/sprite_serialization/, docs/design/sprite-serialization/, simulation/sprite_serialization/ | Reviewed raw references and primitive bits; complete chain unfinished |
| Expansion transport adapter and read quarantine | mra_byte_audit; integrator review | tools/expansion_adapter/, sim/expansion_adapter/, docs/design/expansion-adapter/, simulation/expansion_adapter/ | Draft rejected by three reproducible diagnostics; quarantine unfinished |

## Review gates

- Video: label accepted input RGB and blanking independently of output; establish all first/last active samples, FIFO correspondence and exact first divergence without compensating stimulus. Retain source assertions and compatibility-copy attribution. A reproduced failing gate can complete the bounded investigation if its next remedy is concrete.
- Sprites: new taps preserve raw addresses. Decode actual graphics/control state and test source serialization with independent bit-order/bank expectations. Coordinate movement alone cannot establish projectile identity. ROM-derived bytes, images and logs remain ignored; reports retain provenance and metrics.
- Expansion: ground adapter edges, addresses and backpressure in actual HPS source. Explicitly test simultaneous boundaries, strict length/order failures, FAX2 and both recovery directions. Revoke remote read permission and obtain an acknowledgement before overwrite; test slow/stopped read clocks. Logical simulation does not establish physical CDC or fitted RAM capacity.

No production RTL/framework/release edits, Quartus build or commit are in these assignments. W02–W07 remain ACTIVE as applicable. Root independently replays final fixtures and retains unresolved assumptions before accepting each bounded unit.

## Review and next handoff

The owner requested completion of this current step only, documentation of the stopping point, then a stop. All three Luna workers hit their usage limit before finishing. The integrator completed the bounded video queue, raw captures/graphics-bit tests and executable adapter review; incomplete original acceptance gates remain explicitly open.

- [Video queue](video-queue/README.md): all eight bitplanes pass 65,536 input/output samples, complete first/last rows and x=255, zero input-stimulus/geometry errors and 18-master-clock capture-to-register-update latency. Corrupting the first FIFO expectation fails. The fifth-block boundary error was a fixture input-stimulus/timestamp-origin problem; no production alignment fix was made. Production mixer scope in Quartus, downstream consumer sampling and actual renderer/CRT integration remain open.
- [Sprite evidence](sprite-serialization/README.md): fresh raw right/fire and right-only references contain 189,581/190,028 bus events, with no mirrored position writes in this tested sequence. Right/fire matches the accepted bus bytes and all 13 common decoded screenshots. Actual graphics pass 16,384 primitive serialization bit checks and an injected-bit negative. Active image selections show outside-room dot/blank state, not the reported arrow case. Coupled PROM/ROM-latency/window timing, clipping and inside-room reproduction remain unfinished.
- [Adapter review](expansion-adapter/README.md): lint passes, but begin-index, simultaneous skid-arrival and stale-acknowledgement expectations fail exactly as recorded. The adapter is not accepted. Fix those defects and validate a connected HPS/loader/read-domain model before considering production wiring. No full quarantine, transport matrix or FAX2 acceptance is claimed.

The [stopping point](../../STOPPING_POINT.md) is the resume entry point. The [review record](sixth-review.json) retains source/tool hashes, completed checks and explicit unaccepted gates. All 133 baseline tracked hashes were checked; only `.gitignore` differs. Documentation JSON parses and `git diff --check` passes. No next batch was dispatched, no production source/release changed, and no Quartus build or commit was run.
