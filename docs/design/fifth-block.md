# Fifth worker block

Started 2026-10-06 on owner instruction to continue three Luna workers. The integrator owns WORKPLAN.md and this index. Production RTL, framework files, release MRAs and RBFs stay unchanged; no Quartus build is part of these units.

| Unit | Worker | Owned paths | Status |
| --- | --- | --- | --- |
| Video simulation compatibility and tap origin | baseline_releases | tools/video_compat/, sim/video_compat/, docs/design/video-compat/, simulation/video_compat/ | Reviewed diagnostic; native image gate fails |
| Sprite/collision reference-to-RTL fixture | sim_harness | tools/sprite_fixture/, sim/sprite_fixture/, docs/design/sprite-fixture/, simulation/sprite_fixture/ | Reviewed bounded fixture |
| Isolated expansion loader RTL prototype | mra_byte_audit | tools/expansion_loader/, sim/expansion_loader/, docs/design/expansion-loader/, simulation/expansion_loader/ | Reviewed isolated prototype |

Prior [fourth-block findings](fourth-block.md) remain the baseline. Generated compatibility copies must retain source assertions, hashes and attribution; they do not establish how Quartus elaborates the original framework. ROM-derived bytes/disassembly/images and generated binaries/logs stay ignored. Reference event replay does not establish full CPU or gameplay parity. An isolated RTL prototype does not establish top-level transport/CDC or fitted capacity.

## Review gates

- Video: describe the exact source transformation; independently check all eight X/Y bit planes, complete row zero and row 255, RGB/CE/DE alignment, native sync widths/phases, and a deliberately wrong alignment or pattern. Do not hide the prior 256 missing-coordinate samples through warmup or assertion changes.
- Sprite/collision: preserve original production register/serialization logic, identify every synthetic input/ROM-memory substitution, and compare source-backed expectations. Record concrete first divergences; an arrow identity claim requires control/image or visual evidence.
- Loader: use published literal descriptors and adversarial transactions against RTL, preserve live base writes during validation/faults, prevent stale expansion reads, and exercise reset/ready behavior in both session directions. Distinguish the proposed synchronous read path from actual FPGA RAM and CDC timing.

## Review and next handoff

The [video compatibility report](video-compat/README.md) and [results](video-compat/results.json) reproduce an uncompensated alignment failure. The integrator independently reran all eight bitplanes and the altered-raster sensitivity control; all metrics match. Each output has 65,536 pixels in 256 rows with no line-length errors, but the source tracker covers 65,280 unique coordinates: x=255 is missing on every row. Phase-zero first color divergence is x=1/y=0, black versus magenta. A compensated stimulus experiment was rejected during review and is excluded from native acceptance. The source-asserted mixer copy resolves Verilator RGB scope visibility only; production behavior in Quartus remains unproved. Output HS is 16 pixels, VS 1,680 pixels, HS-to-DE 16 pixels and VS-to-first-active-DE 1,696 pixels. Matched-coordinate interval 10 master clocks is diagnostic and is not an accepted CRT tap latency.

The [sprite/collision fixture](sprite-fixture/README.md) and [retained positive report](sprite-fixture/fixture-report.json) pass independent replay of 18 Venture writes from frames 2400–2402, both register/address banks and synthetic collision/IRQ/acknowledge probes. The deliberately corrupted expectation exits nonzero at the intended first `$5100` event (expected object-1 nibble 0, actual 1). Checks compare captured bytes to RTL internal latch conventions; vertical +1 is not MAME position parity. Source differences remain: exact-address RTL versus MAME mirrors, Venture sprite-2/background IRQ policy, and sprite-1/background latch polarity. Old captures canonicalize addresses and cannot prove runtime mirror usage. Projectile identity, serialization, clipping, physical scan timing and complete frame comparison remain open.

The [loader prototype report](expansion-loader/prototype-report.md) passes independent Verilator execution at 8 ms simulated time with the full 192 KiB question and 16 KiB speech stores. Tests cover bank-sensitive literal reads, 64-clock main-CPU sampling and a deliberately late address, valid sessions and trailing options, live legacy writes/recovery, malformed descriptors, address holes, nested begin, stray streams, and a full payload following a duplicate-base fault. Integrator review exposed and the worker fixed both a later-payload readiness bypass and an unknown-stream fault that left speech reads enabled. The final regression verifies remote speech readiness clears after synchronization. Physical readiness revocation before overwrite, HPS boundary semantics, actual RAM inference/timing, FAX2 coverage, complete length/order matrix, FAX PROM routing and invalid-bank parity remain open. No synthesis or fitted-capacity claim is made.

W02/W03/W04/W05/W06/W07 remain ACTIVE; no complete gameplay, CRT, expanded-game or release gate is closed. The [independent review record](fifth-review.json) retains artifact hashes, replay outcomes and ignored-log paths. Baseline review checks all 133 original tracked hashes; only `.gitignore` differs. Production RTL, framework, releases and RBF are unchanged. No Quartus build was run.

## Next three bounded units

| Unit | Scope | Acceptance / information needed |
| --- | --- | --- |
| Independent video source queue and boundary origin | Build a pixel queue at the actual RGB/HBlank/VBlank capture edge and trace first/last active samples without compensating stimulus. | Separate fixture-coordinate error from production RGB/DE phase error; prove all 65,536 source/output samples and first divergence before selecting a production fix. Preserve raw raster, wrapper and receiver distinctions. Existing source and fixtures suffice. |
| Sprite serialization and raw-address reference | Capture uncanonicalized MAME register writes; decode actual sprite graphics/control for the matched right/fire case and instantiate source serialization dependencies. | Identify projectile pixels from ROM/image evidence, verify both banks and coordinate/clipping boundaries, and test per-game collision policy. Use supplied NAS ROMs and pinned MAME first; do not infer arrow identity from coordinate motion. |
| Expansion transport adapter and read quarantine | Bind isolated prototype assumptions to actual HPS begin/write/end semantics and both CPU/read domains in a simulation adapter. | Cover simultaneous boundary events, full length/order matrix, faulted reads, CVSD readiness revocation before overwrite, FAX2 and extra PROM/decoder implications. Keep production wiring and full-flow Quartus fit behind explicit integration gates. |

These units were dispatched on the next owner continuation; see the [sixth block](sixth-block.md).
