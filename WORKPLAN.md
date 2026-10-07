# Exidy Universal Game Board II recovery workplan

Planning baseline: 2026-10-05. On 2026-10-06 the owner authorized the first block of three workers: release/source inventory, ROM/MAME availability audit, and build/simulation tooling audit. Further tasks remain governed by subsequent execution instructions.

## Objective and completion rule

Deliver a fully working MiSTer core for every game and revision in the Exidy 6502 hardware family: 10 game titles, 28 currently identified MAME sets. Include complete graphics, collisions, inputs, sound, ROM loading, Native video, CRT-compatible video, and supported persistence.

A task is complete only when its acceptance evidence is recorded. A game is not excluded because it needs additional hardware logic, ROM storage, controls, or reference research. An exclusion requires a documented technical barrier, alternatives investigated, and owner review. Missing evidence is an unresolved item, not proof of impossibility.

Reported defects below have not yet been reproduced by this planning session. Historical forum reports may differ from the current releases.

## Locations and baseline

| Resource | Location / instruction |
| --- | --- |
| Core checkout | `C:\MiSTerDev\Arcade-Exidy2_MiSTer` |
| Existing releases | `C:\MiSTerDev\Arcade-Exidy2_MiSTer\releases` |
| Existing RBFs | `Arcade-Exidy2_20240414.rbf`, `Arcade-Exidy2_20240526.rbf` |
| Existing MRAs | Targ, Spectar, Venture, Mouse Trap, Pepper II, Hard Hat |
| Source baseline inspected | Git commit `bfd1b5c`; verify HEAD and working tree before starting |
| ROM library supplied by owner | `\\fairlanenas\data\Games\ROMS\MAME\MAME 0.257 ROMs (split)` |
| MAME installation | `C:\MiSTerDev\mame` |
| MAME executable | `C:\MiSTerDev\mame\mame.exe` |
| MAME test ROM destination | `C:\MiSTerDev\mame\roms` |
| Victory reference | `C:\MiSTerDev\Arcade-Victory_MiSTer` |
| Forum | <https://misterfpga.org/viewtopic.php?t=7747> (nine posts read) |

Treat the NAS library as read-only. Copy only needed ZIPs to MAME's `roms` directory; preserve existing destination files and check hashes before replacing anything. Split clone sets may require parent archives. Never rename ROM bytes to disguise a hash mismatch. The installed MAME version may differ from 0.257: record it and distinguish ROM-version differences from core defects. Files outside the checkout may require scoped sandbox escalation when execution begins; the owner has supplied the intended ROM destination.

Do not commit ROMs, assembled ROM images, copyrighted reference captures, or machine-specific private configuration. Keep hashes, manifests, reproduction instructions and derived test results in the repository; keep ROM-dependent artifacts in ignored local storage. Review attribution/licenses before reusing code.

## Agent coordination and tracking

Suggested team: one integrator and three worker agents. This is an assignment plan, not a request to launch agents during planning.

### Model assignment

Use **Sol 6.1 (`gpt-6.1-sol`)** as the orchestrator/integrator and **Luna (`gpt-6-luna`)** for smaller, bounded work units. These are the model identifiers exposed by this session. Select Sol 6.1 for the orchestration chat before execution; this document does not change the running chat's model.

The subsystem roles below describe ownership, not assignments of entire subsystems to Luna. Sol 6.1 decomposes their work into units with specific inputs, allowed files, expected outputs and independent acceptance checks. This session supports one orchestrator plus up to three active workers; queue additional units as workers finish.

| Work type | Assigned model | Examples / boundary |
| --- | --- | --- |
| Planning, architecture, root-cause analysis and integration | Sol 6.1 | Dependency decisions, game profiles, sprite/collision divergence, CRT clocking/CDC, analog-model decisions, shared wiring and release acceptance |
| ROM/MRA and metadata units | Luna | Audit one set/family, extract hashes/regions, generate one MRA from an approved loader layout, compare split-parent requirements |
| Reference and regression units | Luna | Extract one event trace, inventory one game's sounds, run a defined per-set regression, summarize logs with evidence |
| Isolated implementation units | Luna | Implement one specified register behavior/module or fixture under an agreed interface and acceptance contract |
| Review and escalation | Sol 6.1 | Review every worker patch/evidence before integration; take over ambiguous behavior, unexplained divergence or cross-subsystem changes |

Default Luna reasoning effort: medium; use high for a bounded RTL task requiring more analysis. A worker reports uncertainty and failed checks rather than changing architecture or acceptance criteria. Sol 6.1 may refine/reassign the unit when its scope expands.

Worker dispatch template:

```text
Task: Wxx.unit-name
Model: gpt-6-luna
Inputs: pinned references, relevant interfaces, reproduction and baseline hashes
Allowed edits: explicit file list; shared files require assigned ownership
Deliverable: specific patch/report with evidence paths
Acceptance: independent expected behavior and exact verification commands
Escalate: uncertain reference behavior, interface changes, unexplained test failure
Handoff: changed files, commit/ref, commands/results, limitations, integration notes
```

Give each worker a focused context package. Do not hand a small unit the entire project without identifying the relevant contracts. All Quartus work still uses the full unsandboxed PowerShell flow defined in W15.

| Role | Primary ownership | Tasks |
| --- | --- | --- |
| Integrator / reference agent | This plan, manifests, reference capture tooling, baseline, integration and releases | W01-W03, W13-W16 |
| Board / game agent | CPU decoding, sprites, collision/IRQ logic, game profiles, input extensions | W04-W05, W10-W12 |
| Audio agent | Sound board, timer/noise/music behavior, CVSD, discrete sound | W08-W09 |
| Video / CRT agent | Native raster validation, output conversion, geometry and video-specific fixtures | W06-W07 |

`rtl/Exidy2.v` and `Arcade-Exidy2.sv` are shared integration hotspots. Assign a single editor to each at any moment. Workers should produce isolated modules and explicit wiring patches; the integrator lands shared-file wiring in sequence. Audio owns `rtl/audio_board.v`; video owns new video modules; board owns board modules. Coordinate ownership of `rtl/rom_loader.sv`, `files.qip`, QSF/SDC and release MRAs before editing. Two agents must not compile into the same Quartus database/output directory concurrently.

Prefer separate managed worktrees and `codex/` branches when workers will edit independently. Otherwise enforce the file ownership above. Each task handoff must include commit/ref, changed files, reference versions, commands run, evidence paths, remaining uncertainties and integration instructions. Do not mark an integration task done based only on a worker's standalone test.

Status values: `TODO`, `READY`, `ACTIVE`, `BLOCKED`, `REVIEW`, `DONE`. Check a checkbox only at DONE. Update this document at every handoff. A blocker must name the missing evidence/action and who can supply it.

| Task | Owner | Status | Depends on | Evidence / commit / blocker |
| --- | --- | --- | --- | --- |
| W01 Baseline and safe workspace | Integrator + baseline_releases + toolchain_audit | DONE | None | docs/baseline/: source/release hashes reviewed; MAME 0.288 executable pinned; Quartus 17.0.2 confirmed; Arch Verilator 5.052 available. No compile/simulation acceptance claimed. |
| W02 ROM and MRA audit | mra_byte_audit / integrator | ACTIVE | W01 | docs/audits/mra/: six byte layouts independently verified, 78/78 archive entries match. Increments 12-15: 29 connected expectations incl. the three owner-supplied ROM payloads pass; probe fits (208 RAM/486 ALM/495 reg). Third block specifies CVSD/FAX loading/storage; local staging remains conditional on reference-run requirements. |
| W03 Reproductions and reference harness | sim_harness / integrator | ACTIVE | W02 | Targ/Spectar MAME attract pairs are deterministic. Fourth block resolves Venture capture duration: normal startup takes about 28.7 seconds, then a controlled input case reaches gameplay. Complete game coverage, exact arrow-case reproduction and CPU/board RTL comparison remain. |
| W04 Sprite correctness | sim_harness / integrator | ACTIVE | W03 | Fifth block: extracted latch/address fixture replays 18 Venture writes; mirror usage, serialization, clipping and arrow identity remain open. |
| W05 Collision, IRQ and board profiles | sim_harness / integrator | ACTIVE | W04 | Fifth block: synthetic probes expose Venture mask/polarity differences. 2026-10-07: MAME `$5103` survey of eight captures confirms per-game polarity; `exidyIntCause` profiles (pcb[7:6]) applied with unit test; candidate MRAs in `candidates/mra`; compiled together and unit-tested locally, but corrected-clock timing and hardware/game acceptance remain. Full CPU-visible timing, room/stage transitions and Targ/Spectar/Teeter profiles remain open. |
| W06 Native raster contract | Integrator | ACTIVE | W01-W02 | Raw profiles measure 336x280/256x256 active. Sixth-block independent synthetic video queue passes all eight bitplanes; actual renderer, downstream consumer, clock/interrupt and receiver acceptance remain. |
| W07 CRT transport and geometry | baseline_releases / integrator | ACTIVE | W06; W03 captures | Third block: candidate Victory-derived schedule/CDC contract; implementation and receiver acceptance pending. |
| W08 Shared digital audio | Audio / integrator | ACTIVE | W03 | docs/audits/source/: mono mix (A1), audio RAM mirror (A2, Mouse Trap divergence measured), 6840 pitch/prescale/load (A4) applied and unit/replay-tested; filter port `$2000` inert (A3). Compiled together on 2026-10-07; corrected-clock timing and listening remain. Noise path, mixed levels, 8253 clocks, Targ/Spectar discrete audio and event inventory remain open. |
| W09 CVSD and discrete audio | Audio | TODO | W08 | Voice ROM loading/transport designed and verified in isolation (W02 increments); no Z80/CVSD core instantiated. Mouse Trap audio-CPU RAM aliasing fixed (A2). |
| W10 Side Trak and Teeter Torture | Board | TODO | W05; audio reference available | |
| W11 FAX and FAX 2 | Board | TODO | W05; ROM/storage design agreed | |
| W12 Clone and bootleg profiles | Board | TODO | W05 | |
| W13 Frontend and persistence integration | Integrator | TODO | W07-W12 implementations ready | |
| W14 Complete game regression | Integrator + workers | TODO | W13 | |
| W15 Full Quartus and physical acceptance | Integrator + owner | TODO | W14 | Interim: owner full-core builds on the audio/interrupt edits show cross-domain timing failures that were baseline structure (docs/audits/source/audio-handshake-timing.md); scoped constraints and a reset synchronizer added; full compilation passed, but stale PLL constraints invalidate timing signoff. Corrected candidate exposes PIA read-data and pause paths. Not the W15 acceptance flow. |
| W16 Release and closure | Integrator | TODO | W15 | |

After W03, board and audio work can proceed alongside video work. W06 can begin earlier. Reference agents may prepare missing-game captures while workers repair shared subsystems. Build milestone images only after the relevant simulation gate passes.

## Issue register and required evidence

| ID | Issue / provenance | Remediation tasks | Needed from owner or MAME / hardware |
| --- | --- | --- | --- |
| I01 | 280-line/~60 Hz CRT compatibility, owner report | W06-W07 | Actual source timing; CRT/adapter/settings; physical lock and visibility acceptance. Victory implementation is available locally. |
| I02 | Analog image top-left and partially off-screen; forum posts 83642, 83662 | W06-W07 | Neutral-setting photo, CRT model and connection; output sync/blanking measurements; reference image boundaries. |
| I03 | Missing alignment controls; forum post 83642 | W07 | Owner feedback on Victory's H/V ranges; analog and Direct Video geometry tests. |
| I04 | Venture missing `11d-cpu`; posts 83642, 83651, 83656 | W02 | Current MRA/NAS bytes verified against replacement dump (docs/audits/mra/). If hardware still reports the missing old filename, record deployed RBF/MRA and ROM build tool/version; current byte audit does not reproduce that packaging error. |
| I05 | Venture horizontal shot displays flying Winky; post 83651 | W04-W05 | Exact set and input sequence; sprite/control writes, frames, collision reads and IRQ trace. **Status 2026-10-07:** sprite-1 enable gating (`$5101` bits 7/4) is not triggered in the startup-to-maze capture; `$5103` polarity differs from MAME for Venture (fixed by interrupt profile 1, unbuilt); room-entry reproduction not scripted; not reproduced in the core. |
| I06 | Targ/Spectar attract sprite jumps and crosses walls; posts 83716, 83722 | W04-W05 | Exact set, deterministic attract capture, object coordinates, collision latch/IRQ reference. **Status 2026-10-07:** Targ/Spectar read `$5103` = 00 in attract (mask 0); no divergence reproduced; open. |
| I07 | Mouse Trap bark/meow/chomp missing; post 83678 | W08-W09 | Audit confirms four CVSD ROMs absent from current MRA and no instantiated fallback storage/consumer. ROM bytes are available; design loading/storage and Z80/CVSD wiring, then obtain voice command/bitstream traces, reference WAVs and listening acceptance. **Status 2026-10-07:** audio-CPU RAM aliasing divergence found and fixed for Mouse Trap (A2); CVSD ROMs/Z80 path still absent; voices still missing. |
| I08 | Venture unspecified missing effects; post 115720 | W08 | Event inventory, reference command/register writes and WAVs; owner examples if available. **Status 2026-10-07:** mono mix (A1) and 6840 pitch/prescale/load (A4) fixes applied, unproven; event inventory not done. |
| I09 | Pepper II unspecified missing effects; post 115720 | W08 | Event inventory, reference command/register writes and WAVs; owner examples if available. **Status 2026-10-07:** same fixes as I08 applied, unproven; event inventory not done. |
| I10 | Targ/Spectar analog crash/noise incomplete; repository README | W09 | MAME trigger semantics/sample references; schematics/component values or PCB recordings for circuit accuracy. **Status 2026-10-07:** Targ/Spectar discrete audio unchanged; open. |
| I11 | Side Trak, Teeter Torture, FAX/FAX 2 listed not working; README | W10-W11 | ROMs, per-game reference behavior, dial device choice and FAX two-player button mapping. |
| I12 | Hard Hat and clone coverage incomplete or undocumented | W12-W14 | Per-set manifest, controls, frames/audio and sustained gameplay. Existing Hard Hat MRA does not establish full acceptance. |

Forum post links use `https://misterfpga.org/viewtopic.php?p=POST_ID#pPOST_ID`. Post 83685 describes generally incomplete sounds but adds no separately reproducible defect.

Additional audit leads, not confirmed bugs: the sprite selection comment at `rtl/Exidy2.v:381`; shared interrupt condition layout; edge-triggered/generated-clock logic; early palette constants; native raster rollover/sync phase; audio RAM mirroring and handshake timing. Test these rather than assuming each is defective. The selected 6840 implementation is the VHDL file in `modules/6840/index.qip`; the neighboring Verilog file is not the selected implementation. High-score saving is already wired: validate it rather than treating the README's old 'Coming Soon' entry as absent functionality.

## Step-by-step execution

### W01 — Establish the baseline

- [x] Read applicable repository/parent instructions; record HEAD, submodule state and local changes.
- [x] Assign agent worktrees/branches, file ownership and independent build directories. First block uses disjoint documentation paths in one checkout, no builds. Subsequent workers use isolated worktree build outputs or named ignored simulation subdirectories.
- [x] Hash both existing RBFs, six MRAs and source baseline; record which release is the comparison baseline.
- [x] Record installed MAME, Quartus and simulator versions. Choose and pin the MAME source/reference revision. Local MAME 0.288 executable SHA-256 is in docs/baseline/roms/availability-manifest.json; official mame0288 source commit is `27a8d9e85b58058965907d1d8a7a92f8ed039348`, recorded in docs/audits/simulation/w03-smoke.md. This source pin does not establish reproducible binary equivalence.
- [x] Inventory build command, simulator support and Quartus timing constraints. Preserve existing releases.
- [x] Define ignored local directories for ROM-dependent captures and generated builds; check artifact handling. Existing simulation/ and output_files/ ignore rules verified.

Acceptance: reproducible baseline manifest, tool versions and ownership table recorded; no accidental changes to released files.

### W02 — Audit ROMs and MRAs

- [x] Check NAS access read-only; inventory the 28 set ZIPs and required parents/shared resources. All target archives/parents present; sample-file availability remains separately unverified.
- [ ] Copy required archives to local MAME `roms` without overwriting different existing files. Record source/destination hashes.
- [x] Run per-set MAME ROM verification; classify missing data and version discrepancies separately. 27 good; mtrapb best available with 74s288.6c NEEDS REDUMP. Local MAME 0.288 verifies the owner-labelled 0.257 library.
- [x] Generate machine/ROM metadata with `-listxml`; record ROM sizes, regions, offsets and hashes. Includes clone merge/status attributes and nonempty sample references for all 28 sets; sample archives not yet verified.
- [x] Compare each existing MRA's assembled download bytes and region offsets with its intended ROM regions and `rtl/rom_loader.sv`. Six audited; physical addressing/data truncation and archive hashes checked. Mouse Trap voice omission is documented; Hard Hat's three shared PROM extras are archive-valid, with profile behavior still to validate.
- [x] Verify Venture's corrected graphics dump; avoid reviving the historical bad dump. Current MRA uses `vel_11d-2.11d`, CRC `ea6fd981`, matching current MAME metadata and actual NAS bytes. Gameplay/image acceptance remains open.
- [x] Design loader extensions for Mouse Trap voice ROMs and FAX question banks without silently reinterpreting existing MRAs. Candidate in docs/design/rom-expansion/: dedicated indices 5/6, versioned descriptor 7, reserved high-score indices, fresh session/readiness and legacy ordering. Physical MRA transport and complete FAX PROM routing remain gates before implementation acceptance.
- [x] Document storage choice and resource estimate for added ROMs before implementing FAX/CVSD loading. Recommend 24x8-KiB question banks plus 16-KiB CVSD dual-port storage, approximately 208 byte-wide M10K blocks; actual fit/free capacity unknown. Six model checks and 95-ROM independent archive audit pass.
- [ ] Resolve FAX's additional 256-byte `fxl-12b` PROM and effective decoder widths; specify its storage/consumer or justify omission with hardware evidence. MAME loads the full 576-byte PROM region but does not wire it.
- [ ] Validate descriptor/profile values and transfer order on MiSTer, including partial downloads and extended-to-legacy reloads; implement and test CPU-facing memory latency.
- [x] Independently replay the isolated expansion-session and main-CPU read model: 16 tests pass, including literal descriptors, exact/ordered transfer failures, stale-data/fault recovery, live base-byte retention and a deliberately late read. Six-MRA document-order report matches independently. This does not validate FPGA transport or CVSD timing; see docs/design/expansion-transport/transport-model.md.
- [x] Independently replay an isolated RTL loader/read prototype with full 192 KiB question and 16 KiB CVSD arrays, bank-sensitive literals, malformed-session/fault-recovery cases and a 64-clock read-deadline negative. Fifth-block review fixes latched-fault readiness bypass and unknown-stream speech readiness. Top-level transport, overwrite quarantine/physical CDC, FAX2/PROM parity, complete boundary matrix and fit remain open in docs/design/expansion-loader/.

- [x] Replay isolated adapter freshness, drain, shared-reset and fault closure: 13 expectations at read latencies 1/2/4, including a level-only unsafe-write negative control. See docs/design/expansion-adapter/increment-04.md. Physical CDC/reset ownership remains open.
- [x] Connect source-derived ordinary file decoder/GPIO/ACK transport to unchanged loader and replay bounded 21-case synthetic matrix, including full FAX/FAX2 stores and malformed descriptor/order/length rejection. See docs/design/expansion-adapter/increment-06.md. Full HPS/SoC execution, production reset/read contract and fit remain open.

- [x] Verify actual NAS expansion payloads through connected ordinary HPS transport, memory and read ports: Mouse Trap 16 KiB CVSD plus FAX/FAX2 192 KiB stores. Component CRC/SHA1, offset-order image hashes and FAX holes match the prior region audit. Bytes remain ignored; base image/game/audio execution are outside this fixture. See docs/design/expansion-adapter/increment-07.md.

- [x] Repair block-RAM inference in a separate registered-RAM candidate and qualify isolated combined transport/read/verdict behavior:29 connected expectations plus baseline public-read/deadline checks pass. Exact-source full Quartus flow fits208/553 RAM blocks,484ALMs,467registers; five scoped Intel synchronizer chains have calculable estimates under abstract probe assumptions. Reset release, actual clocks/CPU/audio and whole-core/physical acceptance remain open. See docs/design/expansion-adapter/increment-12.md.

- [x] Isolated reset release for the expansion adapter: per-domain synchronizers (increment 13), wired into the candidate bridge with 29 connected expectations including the three ROM payloads (increment 14), stopped-speech-clock bridge bench with an unsynchronized-reset negative control (increment 15); probe full flow passes with 7 recognized synchronizer chains, all slacks positive (208 RAM/486 ALM/495 reg). Probe-level only: PLL-lock-derived reset, actual clocks/CPU/audio and whole-core fit remain open. See docs/design/expansion-adapter/increment-13.md to increment-15.md and docs/cloud-environment.md.

Acceptance: existing six MRAs load known correct bytes, or each discrepancy is documented with a concrete correction; expansion layout is specified. Packaging success does not close gameplay/audio defects.

### W03 — Build reference cases and reproduce reported issues

- [x] Establish an executable production-module smoke fixture and probe the selected 6840 VHDL simulation route. Six `ls139` checks pass; GHDL translation/Verilator lint pass. These are preliminary tooling checks, not behavioral board acceptance.
- [x] Establish bounded actual-MAME Targ/Spectar attract references with passive bus taps, frame captures, pinned inputs/ROM/executable hashes and paired decoded-pixel comparison. Independent final Targ replay: seven matching frames and 22,847 bus events through frame 3599. The third-block Venture diagnostic ended at STAND BY; the fourth-block continuation below resolves that capture-duration limit.
- [x] Resolve Venture's reference startup duration before inputs: first IRQ acknowledgement at frame 1720 (~28.68 seconds), title/attract visible at frame 1800. A post-startup coin/start/right/fire case reaches gameplay; independent replay yields 189,581 bus events and 13 frames. Exact arrow identity/core comparison remain open; see docs/reference_cases/venture-startup.md.
- [ ] Create repeatable boot/attract/input sequences and capture instructions for each current release game.
- [ ] Reproduce I04-I09 where possible; log 'not reproduced' with set/hash/version and tested sequence.
- [ ] Capture MAME frames plus sprite/control writes, collision reads, IRQ acknowledgements and audio events for the reported sequences.
- [ ] Add simulation access to equivalent RTL state and compare the earliest meaningful divergence.
- [ ] Enumerate sound events individually for Mouse Trap, Venture and Pepper II; record expected source, trigger and observed output.
- [ ] Separate rendering mismatches, execution divergence, ROM errors and receiver-only video problems.

Acceptance: worker agents have specific reproducible cases and reference evidence, not only generic 'looks wrong' reports. Account for MAME's abstraction of raster/collision timing; use schematics/datasheets when cycle-level behavior is uncertain.

### W04 — Repair sprites

- [x] Establish a bounded production-source fragment fixture: replay 18 captured Venture writes, check both latch/address banks and coordinate wrap, and independently reject a corrupted expectation. These internal-state checks do not establish MAME position or rendered-frame parity; see docs/design/sprite-fixture/.
- [x] Capture uncanonicalized Venture right/fire and right-only reference addresses and decode corrected graphics; no position mirrors used in the tested sequence. Check all 16,384 bitmap bits through the source serializer primitive and reject an injected expected-bit error. Actual PROM/ROM-latency/window chain, clipping and inside-room arrow reproduction remain open; see docs/design/sprite-serialization/.
- [ ] Compare object position/image/enable register decoding and write timing against reference behavior.
- [ ] Verify ROM layout, object bank selection, serialization, window placement and clipping for both objects.
- [ ] Resolve Venture's horizontal-shot case and Targ/Spectar attract cases from the first divergence.
- [ ] Add targeted tests for both object banks, coordinate boundaries and relevant enable states.
- [ ] Compare complete affected frames; repeat the gameplay sequence to distinguish appearance from execution state.

Acceptance: correct object identities/positions throughout reported sequences; no object-bank regression across current games. Record root causes and trace evidence.

### W05 — Repair collision/IRQ behavior and establish game profiles

- [x] Exercise extracted collision/IRQ/acknowledge equations with synthetic pixel classes and compare Venture's pinned MAME mask/invert policy. Record mirror, M2/background IRQ and M1/background polarity differences as investigation inputs, not proved symptom causes.
- [ ] Verify background/object and object/object collision generation, masks, polarity and blanking suppression.
- [ ] Verify interrupt condition capture, vblank/coin interaction, read acknowledgement and CPU IRQ timing.
- [ ] Define explicit hardware profiles for memory maps, character format, palette, collision layout and audio selection.
- [ ] Audit RAM/ROM mirrors, character RAM writes, coin/DIP/control polarity and reset initialization.
- [ ] Exercise room/stage transitions, wall collisions, death and coin events. Investigate the source comment about a stairs crash if reproducible; it is not a confirmed forum report.

Acceptance: matching reference game state for deterministic cases, correct collision responses, and profile-specific regression coverage. Avoid broad clock rewrites unless trace/timing evidence requires them.

### W06 — Specify and validate native video timing

- [x] Independently investigate mixer scope compatibility with eight uncompensated coordinate bitplanes. Fifth-block fixture reports missing x=255 and alignment failures; sixth-block queue resolves these as fixture stimulus/timestamp-origin errors. Historical diagnostics remain in docs/design/video-compat/; no production alignment correction was made.
- [x] Validate an independent accepted-input FIFO against output DE across all eight bitplanes: 65,536 samples, complete boundary rows/column, zero stimulus or geometry errors, 18-master-clock input-capture-to-output-register-update interval. Wrong FIFO expectation fails. Simulation-only scope normalization is retained; actual renderer, downstream sampling, enabled effects and receiver acceptance remain open in docs/design/video-queue/.
- [x] Measure actual pixel cadence, horizontal/vertical totals, active area, sync widths and phases for each existing MRA. Extracted production logic: 8 master cycles/pixel, 336x280 total, 256x256 active, HS 16 pixels, VS 1681 pixels; normalized phases in docs/audits/raster/. Short simulation covers one complete stable frame interval per MRA, excluding reset, mixer and receivers.
- [ ] Resolve any source timing error before defining CRT conversion ratios; do not infer exact timing from the terminal counter value alone.
- [ ] Document CPU/video/audio clock relationships and native interrupt cadence.
- [ ] Validate complete native images, color/row orientation and HDMI/analog/Direct Video baseline behavior.
- [x] Execute and independently replay a source-derived wrapper/mixer diagnostic; retain explicit failures rather than claim image acceptance. Both gamma modes show 49,152 color mismatches plus 256 missing coordinate samples under Verilator; generated RGB-net scope and tap-origin compatibility need resolution. Generated PLL QIP metadata is decoded and source-hashed in docs/design/video-capture/.

Acceptance: written raster contract and timing fixture. Expected MAME nominal baseline is 336x280 total, 256x256 active, approximately 59.996811 Hz; justify any departure using hardware evidence.

### W07 — Adapt Victory CRT conversion and geometry

- [x] Review Victory's current `CRT_FINAL_BEHAVIOR.md`, converter, position helper, PLL control, framework integration and tests; distinguish older superseded designs. Candidate schedule and integration limits in docs/design/crt/. Independent arithmetic replay passes; 32-row store proposed, 18-row mathematical minimum under the stated contract.
- [ ] Establish a realizable source/output clock relationship with bounded phase behavior; rounded independent-PLL metadata fails the long-term requirement. Preserve source CPU/audio timing and fixed output pixel/line/frame cadence.
- [x] Derive and replay an ideal CRT ownership schedule and conditional same-source clock proposal. 2,359,296 pixel checks pass; 18-row minimum, 32-row recommendation, overwrite/missing-row negatives and drift limits are recorded in docs/design/crt/. Actual original PLL counters, cascade routing/bandwidth, Native transport and full-flow fit remain unverified.
- [ ] Adapt a rolling-row converter to 336x262 CRT output at the verified native frame rate, retaining all 256 active rows and unchanged game/audio timing.
- [ ] Prove row availability/reuse margins and clock-domain transfer; provide explicit fault blanking and recovery. Recalculate scheduling rather than copying Victory constants blindly.
- [ ] Implement Native/CRT selection, safe blank/configure/lock/warmup behavior, reset retention and compatible fixed pixel repetition.
- [ ] Add signed H/V controls; preserve ordinary HDMI geometry isolation where intended. Add width adjustment only with a verified compatible path.
- [ ] Test full images, source/consumer faults, mode changes, pause/dim, reset, OSD, gamma, scandoubler/effects, Direct Video and DV1 metadata.
- [ ] Measure added latency and characterize edge visibility/overscan limitations honestly.

Acceptance: no game-state/audio change between modes; all active pixels transported under valid conditions; receiver lock and usable geometry later confirmed by owner in W15. Do not reduce the game's native vertical total to fix the CRT.

### W08 — Complete shared CPU-based audio

- [ ] Audit 6502 ROM access, RAM mirroring, RIOT ports/timer, PIA handshake and interrupt paths. *(Partial 2026-10-07: RAM mirroring measured and fixed (A2); PIA handshake timing diagnosed; RIOT timer and interrupt paths not audited.)*
- [ ] Trace sound commands end-to-end; verify 6840 modes/clocks/noise/volume and 8253 counter behavior against pinned references and datasheets. *(Partial: 6840 clock/prescale/load verified and fixed (A4); noise, volume and 8253 open.)*
- [ ] Review Victory's verified components for reuse with correct Exidy2 addresses, clocks, board wiring and licenses.
- [ ] Model board-specific filters, enables and gain; produce a correctly mixed mono signal on both outputs unless hardware evidence specifies otherwise. *(Partial: mono mix applied (A1), unlistened; gain/balance versus MAME and filters open; `$2000` is inert in MAME.)*
- [ ] Close every enumerated Venture/Pepper II event; add coverage for Mouse Trap, Hard Hat and expansion games.
- [ ] Check clipping, pitch, envelopes, pause/resume, reset and repeated command delivery.

Acceptance: event inventory has no missing digital effects/music; register/timing comparisons pass; waveform differences have explained analog/model causes. Owner listening remains a separate gate.

### W09 — Complete Mouse Trap CVSD and early discrete sound

- [ ] Load all Mouse Trap voice ROMs and instantiate the Z80 execution path.
- [ ] Implement RIOT command/busy/reset wiring, voice IO decoding and CVSD clock/data protocol.
- [ ] Implement an MC3417-compatible CVSD decoder and reference-derived filtering; do not substitute Victory's TMS5220 speech subsystem.
- [ ] Verify bark, meow, chomp and every other voice/event from the W03 inventory; compare bitstream before tuning analog audio.
- [ ] Implement Targ/Spectar discrete triggers, oscillators, noise, envelopes, filtering and gain; extend to Side Trak where required.
- [ ] Record analog assumptions and missing PCB evidence. MAME uses samples/imperfect sound for early games, so sampled reference agreement is not proof of circuit accuracy.

Acceptance: complete voice ROM/command execution and sound-event coverage; no missing early effects. Digital correctness and analog listening/measurement results are reported separately.

### W10 — Add Side Trak and Teeter Torture

- [ ] Implement Side Trak's character-ROM, monochrome/palette and memory-decoding differences; add its MRA.
- [ ] Implement Teeter Torture's dial/spinner encoding and direction behavior; add its MRA.
- [ ] Agree with owner on spinner/dial device and sensitivity; any joystick fallback is explicit and separately validated.
- [ ] Test complete gameplay, inputs, collision/IRQ, sound and persistence capabilities for both games.

Acceptance: both games playable with intended controls, correct graphics/sound and validated ROM loading. Record reference/hardware uncertainty for prototype-specific behavior.

### W11 — Add FAX and FAX 2

- [ ] Implement question-ROM bank selection, storage access, extra RAM and per-player answer input ports.
- [ ] Add both MRAs with complete question regions and correct board/PROM profile.
- [ ] Agree with owner on two sets of four answer buttons and start/coin mappings.
- [ ] Test every populated bank plus unpopulated-bank behavior, both players, question rendering, scoring, audio and repeated rounds.

Acceptance: all available question banks return correct bytes; both players can answer correctly; no truncated ROM region or bank aliasing. Validate any external-memory bandwidth/latency requirements in the integrated core.

### W12 — Cover clones, bootlegs and Hard Hat

- [ ] Generate per-set MRAs from verified metadata, preserving split-parent relationships.
- [ ] Implement bootleg-specific map/input/profile differences; do not assume a parent profile works unchanged.
- [ ] Verify every Mouse Trap/Venture/Pepper II revision and early-game bootleg independently.
- [ ] Run Hard Hat as a complete acceptance target, including its graphics, sound, controls and gameplay.

Acceptance: all 28 sets have correct loading and an independently tested profile. Parent success does not automatically mark clones passed.

### W13 — Integrate frontend, controls and persistence

- [ ] Integrate worker modules/wiring sequentially; reconcile shared QIP/QSF/SDC and loader changes.
- [ ] Validate game-specific button labels/DIPs, pause behavior, reset, download sequencing and profile selection.
- [ ] Test existing high-score save/restore against actual per-set RAM/readiness behavior; extend address/storage handling if required by expansion games.
- [ ] Document which games have meaningful persistence; use N/A with evidence where none exists.
- [ ] Update stale README support/sound/high-score claims only after verified results.

Acceptance: integrated core passes subsystem tests plus frontend/persistence tests; no double-owner edits, lost ROM regions or unsafe reset/domain crossings.

### W14 — Complete per-set regression

- [ ] Run the matrix below for every set with hash-verified ROMs.
- [ ] Cover attract, sustained gameplay, death, room/stage transitions, coins, DIPs and two-player/cocktail behavior where applicable.
- [ ] Compare complete frames and deterministic execution traces; verify event-based audio inventory.
- [ ] Exercise Native and CRT modes, reset, pause, save/restore and repeated game loading.
- [ ] Classify every mismatch as defect, justified reference difference or unresolved evidence gap; attach evidence.

Acceptance: no unexplained failing matrix cell. Predeclare gameplay duration/stage coverage per family; record actual coverage rather than claiming exhaustive play from a short run.

### W15 — Full Quartus and physical acceptance

- [ ] Run Quartus from an **unsandboxed PowerShell session** using the full project flow: `quartus_sh --flow compile Arcade-Exidy2`, or the repository's verified full-flow command.
- [ ] Use the correct installed executable/version; do not substitute isolated Quartus stages for the build.
- [ ] Record source hash, full logs, fitted resource usage, multicorner/mode timing coverage, setup/hold results and output RBF hash. Investigate relevant warnings; do not hide failing paths with unjustified exceptions.
- [ ] Produce clearly labeled milestone/final candidates without overwriting the original release baseline.
- [ ] Owner tests CRT lock/geometry/edge visibility, Native HDMI, applicable Direct Video/DV1 routes, OSD/mode switching, reset and sustained gameplay.
- [ ] Owner verifies audio completeness/balance and physical spinner/FAX controls where available.
- [ ] Rebuild and repeat affected acceptance after any fixes; carry forward unaffected evidence only with a stated justification.

Acceptance: full-flow build passes with acceptable fitted resources and justified timing coverage; physical tests are signed off with tested hardware/settings. Simulation success alone is not physical acceptance.

### W16 — Release and close

- [ ] Package RBF, all validated MRAs, hashes, changelog, compatibility matrix and user instructions.
- [ ] Document video defaults, adjustment behavior, ROM version expectations, control mappings and any genuine limitations.
- [ ] Ensure ROM/capture handling and attribution are correct; preserve reproducible test commands and manifests.
- [ ] Review all I01-I12 issues, all task checkboxes and the game matrix. Assign every remaining item explicitly.
- [ ] Owner approves the release candidate; publishing or upstream submission requires the relevant execution authorization.

Acceptance: every supported set meets the defined criteria; remaining limitations are explicit, evidenced and owner-reviewed. Do not call the core fully working while missing effects or playable game support remain unresolved.

## Per-set acceptance matrix

Cells: `-` untested; `PASS` with evidence; `FAIL` with issue; `N/A` with reason. ROM includes MRA byte layout, not only MAME ZIP verification. Audio includes all inventoried events. Video covers both Native and CRT. Gameplay includes controls/collisions/IRQ/transitions. Persistence means high scores or other applicable saved state, not emulator save-state support.

| Set | ROM/MRA | Graphics | Gameplay/inputs | Audio | Native/CRT | Persistence | Evidence / issue |
| --- | --- | --- | --- | --- | --- | --- | --- |
| sidetrac | - | - | - | - | - | - | |
| targ | - | - | - | - | - | - | |
| targc | - | - | - | - | - | - | |
| spectar | - | - | - | - | - | - | |
| spectar1 | - | - | - | - | - | - | |
| spectarrf | - | - | - | - | - | - | |
| rallys | - | - | - | - | - | - | |
| rallysa | - | - | - | - | - | - | |
| panzer | - | - | - | - | - | - | |
| phantoma | - | - | - | - | - | - | |
| phantom | - | - | - | - | - | - | |
| mtrap | - | - | - | - | - | - | |
| mtrap4 | - | - | - | - | - | - | |
| mtrap4g | - | - | - | - | - | - | |
| mtrap3 | - | - | - | - | - | - | |
| mtrap2 | - | - | - | - | - | - | |
| mtrapb | - | - | - | - | - | - | |
| mtrapb2 | - | - | - | - | - | - | |
| venture | - | - | - | - | - | - | |
| venture5a | - | - | - | - | - | - | |
| venture4 | - | - | - | - | - | - | |
| venture5b | - | - | - | - | - | - | |
| teetert | - | - | - | - | - | - | |
| pepper2 | - | - | - | - | - | - | |
| pepper27 | - | - | - | - | - | - | |
| hardhat | - | - | - | - | - | - | |
| fax | - | - | - | - | - | - | |
| fax2 | - | - | - | - | - | - | |

## Remaining owner inputs

ROM source and local MAME/release locations are supplied. Do not ask for them again.

- [ ] Identify the RBF/MRA actually running on hardware if different from the repository baseline.
- [ ] Record CRT model, analog IO/adapter chain and relevant MiSTer settings; capture neutral edge visibility.
- [x] Teeter control requirement supplied: spinner plus joystick/D-pad mapping following local Super Off Road or VCO; sensitivity acceptance remains pending.
- [x] FAX control requirement supplied: four answer buttons per player in MRA; physical layout acceptance remains pending.
- [ ] Supply PCB schematics/recordings if available for analog accuracy; agents should first research available primary references.
- [ ] Perform physical acceptance when an evidenced candidate is ready.

None of these prevents starting W01-W03, reference research or independent subsystem work. Dependent physical/control acceptance remains pending until its input is supplied.

## Reference entry points

- Forum: <https://misterfpga.org/viewtopic.php?t=7747>
- MAME board driver: <https://github.com/mamedev/mame/blob/master/src/mame/exidy/exidy.cpp>
- MAME sound board: <https://github.com/mamedev/mame/blob/master/src/mame/shared/exidysound.cpp>
- MAME CVSD device: <https://github.com/mamedev/mame/blob/master/src/devices/sound/hc55516.cpp>
- Local Victory references: `docs/CRT_FINAL_BEHAVIOR.md`, `docs/CRT_STREAM_DESIGN.md`, `docs/SOUND.md`, `docs/PTM.md`, `docs/AUDIO_CIRCUIT.md` under `C:\MiSTerDev\Arcade-Victory_MiSTer`.

GitHub master links are discovery entry points. W01 must replace moving references in evidence records with pinned revisions matching the chosen reference behavior.

## Handoff / decision log

| Date | Task / agent | Decision, evidence or blocker | Next owner/action |
| --- | --- | --- | --- |
| 2026-10-05 | Planning | Owner supplied NAS 0.257 split ROM library, repository releases and local MAME destination. No implementation/build started. | Begin W01 when execution requested. |
| 2026-10-06 | Model assignment | Recorded Sol 6.1 orchestration/review with Luna workers for bounded units. No agents launched and no implementation started. | Apply this dispatch policy when execution begins. |
| 2026-10-06 | First worker block | Owner authorized three workers. Luna assignments: `baseline_releases` owns `docs/baseline/releases/`; `rom_availability` owns `docs/baseline/roms/`; `toolchain_audit` owns `docs/baseline/toolchain/`. Integrator owns WORKPLAN.md and integration report. Same checkout is appropriate for these disjoint documentation-only tasks. | Review worker evidence; finish only supported W01/W02 checkboxes. |
| 2026-10-06 | First block review | W01 accepted. Integrator independently checked 133 source/release hashes and MAME executable hash. Confirmed Quartus version through unsandboxed read-only --version. WSL sandbox denial did not indicate missing simulators: Arch has Verilator 5.052/Make; mixed-language harness remains future work. W02 ROM availability and verification complete, MRA byte-layout/storage work remains. | Next bounded units: existing MRA byte audit; reproducible mixed-language simulation/reference harness design; native raster measurement fixture. |
| 2026-10-06 | Second worker block | Owner requested continuation. Luna units: mra_byte_audit owns tools/mra_audit/ and docs/audits/mra/; sim_harness owns sim/harness/, tools/sim_harness/, docs/audits/simulation/; reused baseline_releases owns sim/raster/, tools/raster/, docs/audits/raster/. Generated files stay in ignored simulation/ subdirectories. No production edits or Quartus builds. | Review artifacts and rerun focused acceptance checks before marking task portions complete. |
| 2026-10-06 | Second block review | Three bounded units accepted in docs/audits/README.md. Independent replay: 78 archive matches/no placement mismatches; four auditor tests; six decoder checks and selected VHDL translation/lint; all six raster profiles pass. Corrected CVSD hypothetical append wrapping during review. Only .gitignore changed among original tracked files. W02/W03/W06 remain ACTIVE because expansion design, behavioral cases and integrated video acceptance remain. | Next units: deterministic sprite/collision reference cases; CVSD/FAX loader/storage contract; Victory-derived CRT scheduling/clock contract. No production implementation gate passed yet. |
| 2026-10-06 | Third worker block | Owner authorized next block. Reused Luna workers: sim_harness prepares deterministic MAME reference cases; mra_byte_audit specifies expansion loading/storage; baseline_releases derives Victory-based CRT schedule. Disjoint ownership is recorded in docs/design/README.md. Production RTL/release edits and Quartus builds are outside these units. | Integrator independently reviews traces, bank boundaries/resource estimates and row availability/clock drift before implementation assignments. |
| 2026-10-06 | Third block review | Bounded storage/CRT contracts reviewed: six synthetic storage checks, independent 95-ROM equality audit, final CRT arithmetic replay with 2,359,296 ownership checks and conditional same-source PLL candidate. Targ/Spectar paired MAME captures match; independent final Targ pair also matches. Venture stays at STAND BY even with sound enabled, so startup diagnosis remains open. Only .gitignore differs among 133 baseline tracked files; no RTL/release changes or Quartus build. | Next bounded units: resolve Venture startup/reference gap; add source-derived post-mixer capture/clock fixture; model extension-session transport and CPU memory latency before production loader edits. W02/W03/W06/W07 remain ACTIVE. |
| 2026-10-06 | Fourth worker block | Owner authorized next three Luna units. sim_harness diagnoses Venture startup; baseline_releases builds actual video pipeline/clock fixture; mra_byte_audit models expansion transport and CPU memory latency. Disjoint ownership in docs/design/fourth-block.md. No production edits or Quartus builds in these units. | Independently replay meaningful positive/negative fixtures and review source-backed diagnosis before accepting bounded substeps. |
| 2026-10-06 | Fourth block review | Venture reaches attract after ~28.68 seconds; final post-startup gameplay pair matches independent replay (189,581 bus events/13 frames). Right-only control isolates fire-correlated second-object movement; arrow identity/core defect remain open. Expansion model: 16 independent tests pass and six-MRA report matches. Exact-source video diagnostics reproduce RGB scope and 256-coordinate gaps; no full pixel-order acceptance. Generated PLL metadata decoded; direct-source integer-ratio candidate documented. | Next three units in docs/design/fourth-block.md: video compatibility/tap origin; sprite/collision reference-to-RTL fixture; isolated expansion loader RTL prototype. Keep W02/W03/W06/W07 ACTIVE. |
| 2026-10-06 | Fifth worker block | Owner authorized three Luna units: video compatibility/tap origin, source-derived sprite/collision fixture, isolated expansion-loader RTL prototype. Ownership and acceptance in docs/design/fifth-block.md. Production wiring, framework edits, releases and Quartus builds remain outside these units. | Independently replay positive/adversarial RTL cases and review compatibility transformations/reference divergences before integration. |
| 2026-10-06 | Fifth block review | Independent replay matches eight uncompensated video diagnostics and raster sensitivity control; native RGB/DE alignment fails, with x=255 missing from each source row. Sprite fixture passes 18 captured-write checks and rejects an injected expectation; mirror/collision/polarity source differences remain investigation inputs. Isolated loader passes full-size memory/read/fault regressions after review fixes. All 133 baseline hashes checked; only .gitignore differs. | Next three scopes in docs/design/fifth-block.md: independent video source queue; sprite serialization/raw-address reference; expansion adapter/read quarantine. W02-W07 remain ACTIVE as applicable; no production integration or Quartus build. |
| 2026-10-06 | Sixth worker block | Owner authorized the next three Luna units: independent video source queue, sprite serialization/raw-address reference, expansion adapter/read quarantine. Ownership and review gates are in docs/design/sixth-block.md. | Independently replay accepted-input/output correspondence, serialization/raw-address evidence and transport/read-quarantine adversaries. Production changes and Quartus builds remain outside these units. |
| 2026-10-06 | Sixth stopping point | Owner requested finish current step only and stop. Luna turns hit usage limits; integrator completed video queue, raw/graphics-bit reference work and executable review of the partial adapter. Video queue passes; source primitive bit order passes; adapter fails begin-index, skid-arrival and stale-ack tests and remains unaccepted. | STOPPING_POINT.md records exact reviewed artifacts and remaining gates. No next dispatch. Resume only on a new owner instruction. |
| 2026-10-06 | Increment 1 | Owner changed cadence to one increment, then stop and wait for go-ahead while weekly usage remains. Fixed isolated adapter begin-index and upper-index start rejection. Valid transitions 0/7/6 and rejected concurrent-byte 0x0106 case pass; skid-arrival and stale-ack failures remain reproducible. | Stopped. Next proposed increment: skid-buffer simultaneous enqueue/dequeue regression and fix. No production wiring or Quartus build. See docs/design/expansion-adapter/increment-01.md. |
| 2026-10-06 | Increment 2 | Fixed simultaneous skid dequeue/enqueue and unified late-write drain handling. Six distinct bytes pass exact address/data/index ordering across start/stop/drain; blocked full buffer faults and retains the older byte. Begin/index regressions remain passing; stale acknowledgement still reproduces. | Stopped awaiting go-ahead. Next proposed increment: fresh read-revocation acknowledgement before overwrite. Adapter remains unaccepted; no production wiring or Quartus build. See docs/design/expansion-adapter/increment-02.md. |
| 2026-10-06 | Increment 3 / reserve cadence | Owner authorized continuous bounded increments until approximately 98% weekly usage. Fresh generation/read-drain handshake passes eight expectations: existing regressions, stale-high and outstanding reads with stopped/slow remote clocks, and unsafe level-only negative control. | Continue reset/fault/abort and latency adversaries; check account usage per increment. Isolated draft only, no production or Quartus changes. See docs/design/expansion-adapter/increment-03.md. |
| 2026-10-06 | Increment 4 | Shared reset, abort/restart, upper-address rejection and faulted-session closure pass. Thirteen expectations include drain latencies 1/2/4 and level-only unsafe-write negative control. Faulted pending bytes now discard rather than replay; historical retention diagnostics preserved. | Continue source-derived HPS/ACK connection to baseline loader while monitoring weekly reserve. No production or Quartus changes. See docs/design/expansion-adapter/increment-04.md. |
| 2026-10-06 | Increment 5 | Source file decoder, GPIO synchronizer and ACK bodies connected to adapter and unchanged loader. Two full speech sessions pass all forwarded/store/read bytes; ordinary and delayed ACK polling variants pass 25 stopped-clock wait cycles per session. Main ordinary download call chain pinned by hashes; separate fast-block path excluded. | Continue connected descriptor/order/length/FAX2 adversaries. Physical CDC/reset/memory and production integration remain open. See docs/design/expansion-adapter/increment-05.md. |
| 2026-10-06 | Increment 6 | Twenty-one connected cases pass: two complete speech positives, full FAX/FAX2 192 KiB stores with all-byte and 48 bank-boundary checks, plus seventeen malformed descriptor/order/length cases. Reset/readiness rejection established for these bounded cases; no loader changes. | Continue ROM-backed connected expansion images. Banks24..31, complete game execution and physical integration remain open. See docs/design/expansion-adapter/increment-06.md. |


| 2026-10-06 | Increment 7 | Actual NAS Mouse Trap CVSD and FAX/FAX2 question images match component hashes and prior region hashes, then pass connected transport/store/read tests. FAX banks22/23 zero; FAX2 all24 populated. ROM bytes remain ignored; base remains synthetic, no game/audio execution. | Continue combined reset/read contract and reload adversaries while preserving weekly reserve. See docs/design/expansion-adapter/increment-07.md. |
| 2026-10-06 | Increment 8 | Isolated bridge combines adapter/loader reset and remote read quarantine. All 27 synthetic/ROM expectations pass, including malformed full speech remaining quarantined and extended-to-legacy reload/recovery. Adapter faults require shared reset; loader-only faults retain legacy recovery. Weekly usage 96%. | Assess standalone synthesis/resource/CDC before production wiring; whole-core fit and physical acceptance remain separate. See docs/design/expansion-adapter/increment-08.md. |
| 2026-10-06 | Increment 9 | Unsandboxed Quartus full-flow isolated probe exits3: question/CVSD arrays uninferred due to asynchronous read logic (276007), then register capacity exceeded (276003). Behavioral simulation had passed; storage synthesis is rejected. Baseline/production unchanged. | Implement separate reset-free registered RAM candidate; replay public-port/deadline and 27 connected cases, then full-flow build. Whole-core fit/CDC remains open. See docs/design/expansion-adapter/increment-09.md. |
| 2026-10-06 | Increment 10 | Separate reset-free registered-RAM candidate passes27 connected synthetic/ROM cases and baseline public-read/deadline positive/negative. Unsandboxed full Quartus flow succeeds:208/553 RAM blocks,485ALMs,456registers. Virtual-I/O/async probe constraints prevent physical signoff; generic async_reg ignored by Quartus17. Weekly usage97%. | Finish tool-visible synchronizers/reset release, then actual clock/CPU/audio/whole-core fit. Preserve approximately2% reserve. See docs/design/expansion-adapter/increment-10.md. |
| 2026-10-06 | Increment 11 | Scoped Intel synchronizer identification passes complete Quartus flow. Five intended two-register chains verified in detailed report; uncomputable MTBF fraction0 under abstract/default assumptions. Resource208RAM/477ALM/469registers. Boundary review finds duplicate-speech verdict gap while old readiness high. | Close speech active/end quarantine through loader verdict and add duplicate-speech regression. Reset release/actual clocks/whole-core fit remain open. See docs/design/expansion-adapter/increment-11.md. |
| 2026-10-06 | Increment 12 | Speech quarantine persists through loader verdict; duplicate full stream faults without transient read enable.29 connected expectations pass (28positives plus missing-hold negative). Exact-source full Quartus flow succeeds:208RAM/484ALM/467registers; five specified synchronizers calculable under probe assumptions. | Reset release per domain, actual clocks/CPU/audio, whole-core fit and physical acceptance remain open. See docs/design/expansion-adapter/increment-12.md. |

| 2026-10-06 | Reserve stopping point | Stopped after increment12 at98% weekly usage, leaving approximately2%. All current simulations/builds completed; no next unit or background agent started.133 baseline hashes checked:only.gitignore differs; ROM bytes/SOF ignored and undeployed. | Resume only on owner instruction:per-domain reset-release synchronization and stopped-clock tests, then actual clock/CPU/audio/whole-core integration. STOPPING_POINT.md records remaining core/game/CRT items. |
| 2026-10-06 | Increment 13 (cloud) | Isolated reset-release module passes stopped-clock/skew adversaries; unsafe control fails. Cloud replay of 26 non-ROM connected cases passes on Verilator 5.052 (5.020 gives false failures in cases 25/26). Module not yet wired in. | Wire per domain into bridge, replay suite, add QSF assignments; Quartus on owner machine. See docs/design/expansion-adapter/increment-13.md. |
| 2026-10-06 | Increment 14 (cloud) | Per-domain synchronized reset wired into candidate bridge `_rr`; 29/29 connected expectations pass incl. mtrap/fax/fax2 ROM cases (owner-supplied zips, staged in ignored simulation/, match increment-07 hashes). | Add QSF synchronizer assignments + full-flow Quartus on owner machine; bridge-level stopped-speech-clock release test; then actual clocks/CPU/audio. See docs/design/expansion-adapter/increment-14.md. |
| 2026-10-06 | Increment 15 (cloud) | Bridge-level stopped-speech-clock reset test passes with a failing unsynchronized mutant; `fit_probe.py --reset-sync` prepares the increment-14 Quartus probe (not compiled). | Owner batch: compile fit14 probe. See docs/design/expansion-adapter/increment-15.md. |
| 2026-10-06 | W05/W08 audit + A1 mixer (cloud) | docs/audits/source/w05-w08-source-audit.md lists 7 sprite/IRQ and 7 audio source-level findings vs MAME. First production edit: mono mix of the two audio groups (`rtl/audio_mix.v`), unit-tested, not yet Quartus-built or heard. MAME 0.264 installed in cloud; mtrap/fax/fax2 verify and the reference Lua harness runs. | Owner: build/listen to confirm A1; upload remaining ROM zips so MAME traces (S1 `$5101` gating on Venture) can run in cloud. |
| 2026-10-06 | Increment 14 Quartus (owner-run) | fit14 probe full flow succeeds: 208 RAM/486 ALM/495 reg, all slacks positive incl. recovery/removal; 7 synchronizer chains recognized (5 + 2 reset), 0 incalculable. +28 registers vs increment 12 only partly explained. Probe-level only. | Next: profile-driven interrupt latch (S2–S5), then actual clocks/CPU/audio wiring. See increment-14.md. |
| 2026-10-06 | W05 interrupt-cause profiles (cloud) | `exidyIntCause` (pcb[7:6]) selects per-game collision mask/invert/IRQ qualification; profile 0 is the unchanged baseline so existing MRAs are unaffected. Unit test matches MAME's formula and all observed `$5103` values. Second production RTL edit; not Quartus-built, no MRA changed. | Owner decision: adopt new index-1 bytes (Venture 0x50, Pepper II/Hard Hat 0xB0) when testing a build; rerun sprite_fixture on WSL. See docs/audits/source/w05-w08-source-audit.md. |
| 2026-10-06 | Full-core timing (owner-run) | Setup −2.888 ns (audio clk) / −0.612 ns (master clk): all failing paths are the PIA_9B↔PIA_8B/T65 audio handshake crossing, none in the mono-mix or interrupt-profile logic. Added scoped false paths in Arcade-Exidy2.sdc; no RTL change. Baseline build not run to confirm inheritance. | Owner: rebuild and report slack. Optional hardening: synchronizers on handshake lines. See docs/audits/source/audio-handshake-timing.md. |
| 2026-10-06 | Timing follow-up (owner-run) | After handshake false paths: master clk +0.050 ns, audio clk −1.022 ns; remaining worst paths are RESET_n sources (hps_io) into audio-clock filter/CPU resets. Added `exidyResetSync` for the audio-clock reset users plus a false path on its first flop; unit-tested; not Quartus-built. | Owner: rebuild, report slacks and any new top paths (watch `pause`). See docs/audits/source/audio-handshake-timing.md. |
| 2026-10-07 | Timing follow-up 3 (owner-run) | After the audio reset synchronizer the audio clock misses by ~−0.34 ns, all from static profile byte `mod_other[4]` into audio filters. Added scoped false path; no RTL change. | Owner: rebuild; report slacks/top paths. See docs/audits/source/audio-handshake-timing.md. |
| 2026-10-07 | W08 A2 audio RAM mirror (cloud) | MAME traces show Mouse Trap audio firmware polls `0x0178` through the 6532 RAM mirror; flat 2 KB RAM returns wrong data for 6,188 reads. `exidyAudioRamAddr` mirror map replays with 0 mismatches on Venture/Pepper II/Mouse Trap; flat fails Mouse Trap. Third production RTL edit; not Quartus-built. | Owner: confirm in next build; compare Mouse Trap audio behavior. See w05-w08-source-audit.md. |
| 2026-10-07 | W08 A3/A4 (cloud) | `$2000` port inert in MAME (single constant); `$3000` correctly decoded. Production 6840 VHDL measured against MAME's timer rule on real Venture writes: 4× low pitch (module divides an already-6502-rate clock by 4), no timer-3 ÷8 prescale, no immediate load. Fixed (CLK_DIV generic, prescaler, load flags); replay median 0.997 on all timers vs baseline 3.986/3.986/0.498. Fourth production RTL edit; not Quartus-built; noise path and levels not compared. | Owner: confirm in next build (effects should be two octaves higher); then compare noise/levels against MAME WAVs. See docs/audits/source/a3-a4-audio-effects.md. |

| 2026-10-07 | Local continuation, two Luna blocks | Incoming production tree fast-forwarded into main. Full compile passed; 6 local regression results pass, 1 trace skip; 29 connected expectations and profile-0 sprite replay/control pass. Source audits expose stale PLL model and unassigned board clocks; corrected candidate exposes PIA read-data/audio pause setup failures. | Correct PLL constraints and pause sampling, rerun full flow and inspect remaining exact paths; hardware/W15 acceptance remain open. See STOPPING_POINT and local audit reports. |

| 2026-10-07 | Local corrected-clock/pause build | `594b8dd` complete Quartus flow compiles (0 errors) with actual PLL clocks; master setup -0.948 ns on PIA reply data, audio +0.082 ns. No added timing exception. Fresh local MAME traces pass 11/11 runner results; mirror zero mismatches, flat Mouse Trap negative fails as expected. | Repair timed PIA return chain with coherence/latency evidence and rerun full flow; hardware and complete clock/reset coverage remain open. |
| 2026-10-07 | Owner display/control requirements | HDMI and Direct Video/S-Video to 15 kHz JVC; Teeter spinner plus Super Off Road/VCO-style joystick/D-pad mapping; FAX four answer buttons per player in MRA. Two Luna units auditing reference mappings and FAX candidate feasibility. | Implement/profile-test controls; record exact hardware/settings and physical acceptance. Requirements supplied do not mark game support DONE. |

| 2026-10-07 | Control-reference Luna units | Super Off Road steering and Victory trackball implementations audited for Teeter. FAX answers map P1 `$1c00` and P2 `$1a00`, active-low bits7..4; current core lacks these reads and FAX profile/transport integration. | Use reference spinner/D-pad mapping in Teeter adapter; resolve custom callback bit placement in MAME. Add FAX input decode and four-button MRAs with board profile/ROM integration. No missing game is DONE. |

| 2026-10-07 | Local 6840 and Teeter input evidence | Guarded 2M-cycle production-VHDL timer window passes all three pitch medians at0.997; source helpers and complete-window output independently reproduced. Teeter MAME callback shift resolved and local input/bus capture confirms event bit6/direction bit2. | Noise/levels and8253mode0/3 output comparison remain open. Standalone Teeter control candidate next; complete profile/game/MRA/hardware acceptance pending. |

| 2026-10-07 | PIA reply staging candidate | One master-clock whole-byte register inserted before PIA9 input; handshake wires and constraints unchanged. Production-PIA fixture passes seven related-clock phases, DDR masking, reset/pending-response and previous-register PH1 sampling; actual Verilog register test passes. | Complete full-flow build; inspect setup/hold to new register and pause first stage. Already-active read/firmware hold and hardware acceptance remain open. |
