# Third worker block

Started 2026-10-06 after owner requested the next block. Existing Luna workers are reused under disjoint file ownership; the integrator owns WORKPLAN.md and this index.

| Unit | Worker | Owned paths | Status |
| --- | --- | --- | --- |
| Deterministic MAME reference cases | sim_harness | tools/reference_cases/, docs/reference_cases/, simulation/reference_cases/ | Reviewed bounded Targ/Spectar pairs; Venture retained as a failed startup probe, gameplay case remains open |
| CVSD/FAX loader and storage contract | mra_byte_audit | tools/rom_expansion/, docs/design/rom-expansion/, simulation/rom_expansion/ | Reviewed; six model checks and independent 95-ROM audit pass; PROM routing/fit remain open |
| Victory-derived CRT scheduling contract | baseline_releases | tools/crt_schedule/, docs/design/crt/, simulation/crt_schedule/ | Reviewed; independent final arithmetic replay passes; same-source PLL candidate remains conditional on actual counters, routing and fit |

Generated and ROM-dependent artifacts stay in ignored simulation/ subdirectories. The NAS is read-only. This block prepares actual reference evidence and architecture contracts; it does not authorize a worker to edit production RTL, release MRAs or RBFs. No Quartus build is part of these units.

Acceptance requires concrete replayable commands, measured or source-backed results, explicit unresolved assumptions, and independent integrator review. MAME reference behavior does not itself reproduce a core defect. Ideal scheduling arithmetic does not establish realizable PLL frequency, CDC safety or physical CRT lock. Storage budgets are estimates until fitted.

[Integration gates](integration-gates.md) record cross-unit constraints. The [CRT candidate](crt/README.md) and [derived results](crt/results.json) establish a 32-row recommendation under an exact-rate arithmetic contract: 2,359,296 pixel ownership checks, an 18-row mathematical minimum, missing-row and undersized-ring checks, modular sequence wrap, and finite drift cases. A +1 ppm free-running output mismatch causes modeled underflow at frame index 9; rounded PLL metadata is insufficient to establish continuous output. Actual clocks and the RGB-valid tap must be resolved before treating a converter implementation as accepted.

The [MAME reference report](../reference_cases/README.md) preserves final Targ and Spectar attract pairs: seven matching decoded frames per case and respectively 22,847/59,186 passive bus events through frame 3599. The integrator independently replayed Targ twice and compared both final worker pairs. Venture's startup snapshots remain STAND BY and fail the gameplay-capture validity threshold; sampled main/audio CPU state is diagnostic evidence only. No equivalent full-board RTL run or forum-defect reproduction has passed.

The [expansion contract](rom-expansion/expansion-storage-contract.md), [budget](rom-expansion/region-budget.json) and [actual-ROM report](rom-expansion/verified-rom-regions.json) specify proposed streams and session handling: retain index 0 bytes, use indices 5/6 for question/voice data and index 7 for a descriptor, avoid high-score indices 3/4, require fresh complete base and expansion transfers, and distinguish existing legacy transfer order. The recommended question store is 24 banks of 8 KiB, with 16 KiB of separate CVSD storage. Its approximately 208 byte-wide M10K estimate remains unfitted. FAX's extra PROM region, invalid-bank parity and actual CPU read latency still require investigation.

The preferred clock proposal references the original PLL's currently unused output 1. Conditional on an actual 4:1 output-0/output-1 counter relationship, a downstream integer M131/N1/C35 clock has exactly 131/140 of the source rate. Original rounded metadata differs from 4:1 by 1 Hz; actual counter, cascade bandwidth, routing and fit evidence are still required. Native transport requires its own image and timing proof.

## Proposed next three bounded units

These units were assigned on the next owner continuation; their dispatch and review are recorded in the [fourth block](fourth-block.md).

| Unit | Scope and ownership | Acceptance and needed information |
| --- | --- | --- |
| Venture startup reference | Reference tooling/diagnostic report only; investigate startup before attempting horizontal shots. | Identify the startup loop from MAME debugger/source and passive traces; demonstrate a fresh boot reaches gameplay, or retain an exact blocker and next experiment. Use supplied ROMs first; request owner input only if a known working MAME configuration or hardware sequence is still needed. |
| Source video/clock fixture | Separate simulation fixture and evidence; observe actual post-mixer active coordinates and original PLL configuration. | Verify all 256 rows and image direction, measured pipeline latency and native pulse phases; establish original PLL counter evidence and a cascade feasibility checklist. Later physical acceptance needs the owner's CRT/adapter/settings. |
| Expansion transport model | Isolated model/fixture implementing the proposed session contract; preserve production loader until the model is reviewed. | Test real MRA document ordering, contiguous addresses, truncation, stale data, extended-to-legacy reload and CPU read latency. Use the pinned MiSTer loader and MAME memory maps; keep unresolved FAX PROM wiring and banks 24–31 explicit. |
