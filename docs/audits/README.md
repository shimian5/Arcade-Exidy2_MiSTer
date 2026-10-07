# Second worker block

Started 2026-10-06 after owner requested continuation. Three bounded Luna units prepare evidence and reusable tools without editing production core logic or release artifacts.

| Unit | Worker | Owned paths | Review status |
| --- | --- | --- | --- |
| Six existing MRA download layouts | mra_byte_audit | tools/mra_audit/, docs/audits/mra/ | Reviewed; independent real audit and four synthetic tests pass |
| Minimal simulation harness and selected VHDL strategy | sim_harness | sim/harness/, docs/audits/simulation/ | Reviewed; independent decoder smoke and VHDL analysis/translation/lint pass |
| Source-derived raw raster measurement | baseline_releases (reused worker) | tools/raster/, docs/audits/raster/ | Reviewed; independent six-profile replay passes |

Generated binaries, private ROM-dependent artifacts and logs belong in separate ignored `simulation/` subdirectories. Workers share the checkout under explicit file ownership. The integrator owns this index and WORKPLAN.md. No Quartus stage is run in this block.

Acceptance boundaries:

- MRA audit must resolve actual archive bytes by hashes, follow loader address truncation and compare physical regions; archive verification alone is insufficient.
- A harness smoke test must exercise an actual module with semantic checks. It does not establish full CPU/board execution or gameplay acceptance.
- Raster measurements must come from the actual extracted source and distinguish raw core sync from MiSTer mixer/receiver output. Frequency conversion uses the checked-in PLL configuration, not comments alone.
- Every worker result is reviewed and focused verification rerun before workplan checkboxes are completed.

## Accepted evidence and remaining work

- [Six-MRA audit](mra/six-mra-audit.md): all 78 selected MAME archive entries match size/CRC/SHA1. Existing download parts land at the expected physical addresses. Venture includes the current replacement graphics ROM. Mouse Trap omits four CVSD ROMs (16 KiB), and the selected fallback bank has no core storage/consumer. Its future layout must handle 14-bit address wrapping explicitly. Hard Hat's three extra shared PROMs are archive-valid; board behavior remains to validate.
- [Simulation smoke](simulation/w03-smoke.md): six checks exercise the production `ls139`; selected 6840 VHDL analyzes, translates and passes lint. CPU execution, timer behavior, RAM semantics and gameplay remain untested. Official MAME 0.288 source is pinned for subsequent reference work.
- [Native raster contract](raster/README.md): all six MRAs use reload byte `0x37`; extracted production raster logic measures eight master cycles per pixel, 336x280 total, 256x256 active, with explicit sync/blank/VL1 phases. Nominal configured frequency gives 59.992906303 Hz. The short captures contain one complete stable frame interval; full image, reset, mixer and receiver acceptance remain open.

Integrator independently replayed these checks on 2026-10-06. Windows sandbox restrictions on temporary files/NAS access and WSL were resolved through scoped unsandboxed commands. The only changed original tracked file is `.gitignore`, permitting the simulation report to be tracked and excluding Python caches. Production source, MRAs and original RBF hashes remain unchanged. No Quartus build, ROM staging, commits or release acceptance occurred.

The next three bounded units should prepare deterministic Venture/Targ/Spectar reference cases (W03-W05), specify backward-compatible CVSD/FAX loading and storage (W02/W09/W11), and derive the Exidy2 CRT conversion schedule from the accepted raster and Victory implementation (W06-W07). The integrator reviews shared interfaces before implementation.

## Source audits (2026-10-06/07)
- [W05/W08 source audit](source/w05-w08-source-audit.md): 14 RTL-versus-MAME findings, with the applied changes (A1 mono mix, A2 audio RAM mirror, S2/S3 interrupt profiles).
- [A3/A4 audio effects](source/a3-a4-audio-effects.md): `$2000` inert; 6840 pitch/prescale/load measured on real Venture writes and fixed.
- [Audio handshake timing](source/audio-handshake-timing.md): owner Quartus timing failures traced to baseline clock-domain crossings; constraints and reset synchronizer.

## Local continuation (2026-10-07)

- [Timing source review](source/local-timing-review-2026-10-07.md): exception scope, profile transfer/reset contract, remaining pause and PIA crossings, and generated-clock coverage limits.
- [Sprite fixture rerun](source/local-sprite-rerun-2026-10-07.md): 18 captured writes pass under the profile-0 extraction; corrupted expectation fails. Venture arrow reproduction remains open.
- [Local regressions](source/local-regressions-2026-10-07.md): recovered complete run passes, including 29 connected expectations; audio-RAM trace replay skipped.
- [Full-core build](source/local-full-core-build-2026-10-07.md): incoming edits compile together; PLL-model mismatch prevents timing signoff.
- [PLL constraint contract](source/pll-constraint-contract.md), [generated-clock inventory](source/generated-clock-inventory.md), and [audio domain contract](source/audio-clock-domain-contract.md): next timing repair and clock/reset ownership.


## Current local validation and controls

- [Corrected-clock full flow](source/local-corrected-clock-build-2026-10-07.md): compiles; master timing remains negative, audio positive.
- [Local audio-RAM replay](source/local-audio-ram-replay.md): fresh MAME 0.288 traces, 11 passing results and meaningful flat-map negative control.
- [PIA return-data contract](source/pia-return-data-contract.md) and [PLL candidate review](source/pll-candidate-review.md): exact paths and coherence/constraint limits.
- [8253 source audit](source/a5-8253-clock-audit.md): clock ratio, selected module and remaining mode/level evidence.
- [Hardware acceptance checklist](hardware/audio-irq-candidate-checklist.md): supplied display/control requirements and pending observations.

- [Teeter control references](source/teeter-control-reference.md): local Super Off Road and Victory mappings and planned integration.
- [FAX control map](source/fax-controls.md): required four buttons per player, exact MAME addresses and current core gaps.
- [PIA return-register review](source/pia-return-register-review.md): related-clock register proposal and required paired-PIA evidence.

- [Local 6840 replay](source/local-6840-replay.md): guarded timer window, all three pitch medians0.997, source preparation helpers and limits.
- [Teeter input contract](source/teeter-input-contract.md): callback shifting, per-read step semantics and actual local MAME input-address capture.

- [PIA staging candidate](source/pia-return-register-candidate.md): all seven phases pass, including previous-register CPU sampling; new full-flow result pending.
- [Teeter controls candidate](source/teeter-controls-candidate.md): standalone spinner/D-pad/analog and per-read event logic with registered-byte boundary checks; production/profile/MRA integration pending.

- [PIA destination-stage build](source/local-pia-stage-build-2026-10-07.md): exact residual DDR and pause setup paths; compilation does not establish timing closure.
- [Pause first-stage contract](source/pause-first-stage-constraint.md): one held-level synchronizer destination exempted; stage-to-stage paths remain timed.
- [8253 output fixtures](source/a5-8253-mode-tests.md): observed mode 0/3 behavior, live programming and warm reset; no timer production change.
- [Counter pulse plan](source/counter-clock-constraint-plan.md): source-guarded pulse recurrence and edge tuples, fitted pin/coverage validation pending.
- [FAX input candidate](../design/fax-controls.md): profile-gated four-answer inputs and eventual MRA element; no production wiring yet.
- [Mouse Trap speech reuse](../design/mousetrap-speech-reuse.md): local Z80 and CVSD candidate availability, with missing bus/clock/audio bindings.

- [Teeter MRA candidate](mra/teeter-candidate.md) and [NMI contract](source/teeter-nmi-contract.md): 17-part loader metadata passes; missing periodic interrupt identified, production controls/NMI still open.
- [Counter clock discovery](source/counter-clock-discovery.md): post-fit diagnostic helper with singleton collection guards; awaiting completed fit.

- [Speech ROM bus candidate](../design/speech-rom-bus.md): independently passing wait/reset-drain fixture; actual Z80 and expansion bridge remain integration gates.

- [PIA source-stage full flow](source/local-pia-source-build-2026-10-07.md): master setup still negative, audio positive; generated counter clocks reveal PH6 hold gaps.
- [PIA firmware timing](source/pia-firmware-response-timing.md): passive four-game captures and reusable DDR-qualified analyzer; exceptions and limited coverage retained.

- [Teeter NMI candidate](source/teeter-nmi-candidate.md): independent generator and selected-T65 fixtures pass; production binding pending.
- [EIR hold contract](source/eir-counter-clock-hold-contract.md): static profile, live coins and collision paths require distinct review.
- [Venture response mismatch review](source/pia-response-mismatch-review.md): seven MAME-only exceptions, DDR qualification intact; callback-level cause still open.
