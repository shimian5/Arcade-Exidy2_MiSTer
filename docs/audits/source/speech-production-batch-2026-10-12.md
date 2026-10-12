# Mouse Trap production speech integration — five-step checkpoint

Date: 2026-10-12. Parent coordinates three Luna workers; source and private outputs remain separate. This integrates development RTL, not release acceptance.

## 1. Accepted RIOT callbacks and busy input

DONE for the bounded production binding. `audio_board.v` predicts registered `auPH0` rising from the parent counter while T65's bus is stable. The real R6532 fixture accepts the same ten writes, including mirrored ORA/DDRA callbacks; reads and non-PA writes do not emit callbacks. PA input is pulled high and PB0 carries speech busy only while speech is enabled. Callbacks and speech now share `audio_clk`; no new command mailbox/CDC is needed. Strict source guards bind fixture assumptions to the production connections. Derived-clock physical coverage of the old RIOT remains open. See [join audit](speech-production-join-2026-10-12.md).

## 2. Joined speech CPU, decoder, rendering and audio

DONE for implementation and bounded simulation. `mousetrapSpeechSubsystem` joins T80, synchronous ROM adapter, voice I/O, MC3417, fixed-rate renderer, both board filters and saturated mono mixing on `audio_clk`. Threshold-sized phase accumulators generate nominal 1,789,772.5 Hz CPU enables, 30,939.14 Hz RC toggles and 192 kHz samples. Disabled speech preserves base audio exactly; pause mutes and holds the generated phases. The 200 ms private firmware run passes 69,054 ordered ROM requests/responses with varying 3–11-cycle latency, 3,086 digit writes, 3,093 decoder events, 38,399 filter accepts and 38,340 nonzero filtered outputs without overflow. Reset/disable/image/no-X checks pass. Only the first 32 digit bits are checked against the known firmware prefix; no complete native phrase equality is claimed.

The positive simulation explicitly initializes T80 register banks to zero in an ignored generated copy. Production T80 sources are unchanged. The production binding maps core/manual/download reset to the existing audio reset conditioner and clears the whole speech subsystem; only PA4 speech-CPU reset retains decoder/filter history. The wrapper-only global-reset retention test does not prove the core manual-reset policy matches MAME. Cold FPGA power-up values, warm boot history and native MAME clock phase are unresolved acceptance gates, not established by this simulation. See [subsystem audit](mousetrap-subsystem-join-2026-10-12.md).

## 3. Validated production speech loading and MRA

DONE for binding and the bounded production-wrapper fixture. The promoted reset-conditioned sources are under `rtl/expansion/`. They match the qualified candidate sources, except the loader includes the previously qualified separate speech-domain reset port. The production QIP includes the canonical promoted files; the wrapper fixture compiles these actual files.

Only new marker `90` selects speech expansion. Raw existing B0/D0 interrupt-profile bytes remain intact for the game; their marker bit is masked only at the expansion-loader input. `90` becomes the core PCB byte `10`. Download reset does not erase loader state: external RESET resets the loader, while pending/fault/session hold joins CPU reset. Only indices 0/1/6/7 enter this speech binding; DIP/config/NVRAM streams remain with their existing consumers. Normalized write, address and data travel together to the legacy ROM selector. Speech enable is a synchronized held level based on the validated profile-3 image verdict; quarantine/drain/generation handshakes protect the dual-clock ROM.

The candidate MRA uses XML ROM order `1,7,0,6,2,3`, as required by Main_MiSTer's XML-order sender. Descriptor bytes are `45 58 01 03 05 40 49 01 00 00 00 00 40 00 00 00`; base image is 84,288 bytes (`14940`), speech image is 16,384 bytes. The fixture passes every normalized base byte/address tuple, private speech reads, 10/30/50/B0/D0 compatibility, unrelated indices, short-image fault/reset recovery and speech-to-legacy reload. See [loader audit](../../design/speech-loader-production-2026-10-12.md). Releases remain unchanged.

## 4. Full production Quartus and timing

DONE for the full production flow. Production source `7c69900` passes the required full unsandboxed PowerShell `quartus_sh --flow compile Arcade-Exidy2` (16m52s, zero errors/301 warnings). All 59 timing summaries are positive with zero TNS; master setup +2.393 ns, core audio setup +15.912 ns, minimum reported slack +0.247 ns. New first-stage/control and raw-reset-clear exceptions are narrowly counted; stage-to-stage synchronization, local reset and speech data paths remain timed. All six handshake/enable pairs have recognized fitted stages and positive stage timing; both reset pairs have two physical fitted stages and positive direct setup/hold paths. No speech synchronizer assignments are ignored. Internal speech setup/hold is +46.587/+0.258 ns; local reset recovery/removal reports are positive. Detailed fitted review is in [STA audit](speech-production-sta-2026-10-12.md); legacy clock/latch/loop coverage remains open.

The first completed fit also passed constrained timing, but review caught 16 ignored bare-hierarchy QSF synchronizer targets. The correction removes those targets and uses direct RTL FORCED identification attributes, matching the established pause synchronizer. A fresh complete flow built that correction. No isolated stage substitutes for the full project build, and no timing exception was broadened to resolve this metadata issue.

Development RBF: `simulation/full-core/speech-production-20261012/Arcade-Exidy2.rbf`, SHA256 `77a7d6ccecf5d9817468914aed1ed5752dfe1ea4de7e9505643c9722f2e1e303`. The ignored build manifest records source hashes and every timing summary. Intermediate first-fit artifacts are preserved in the ignored `attempt-3-intermediate/` directory; final targeted reports use `speech-sta-final/`. Releases remain unchanged.

## 5. Regression, documentation and reviewable checkpoint

DONE for this bounded batch and its reviewable checkpoint. The existing regression runner reports seven PASS, zero FAIL and one SKIP (optional captured audio-RAM replay not supplied). Focused RIOT, subsystem and actual production-loader fixtures pass separately. No ROM, capture, build output or RBF is tracked. Owner's dirty expansion probe/project files remain untouched. Implementation commits: `917ca00` (joined speech/helpers and tests), `ff7659b` (production loader/audio binding and candidate MRA), `7c69900` (fitted synchronizer identification). Documentation/STA source follow as a separate checkpoint commit. To remove this production integration, revert `7c69900` then `ff7659b`; `917ca00` can remain as unbound helper/test work or be reverted afterward. This is a rollback map, not an instruction to execute it. The previous fitted development baseline is `020b2ae`; its private artifact remains under `simulation/full-core/020b2ae/`.

Stop after these five steps. Next increment is production T80 startup/native game-issued speech evidence; no full speech/game/release DONE claim is made.

## Next acceptance work after this batch

1. Establish production T80 cold/warm startup and full native game-issued bark/meow/chomp command/bitstream/WAV evidence; listen on hardware and check base/speech gain and clipping.
2. Finish FAX/FAX2 question storage/map/input/MRAs and gameplay, then Side Trak and independent clone/bootleg/Hard Hat coverage. Teeter controls/NMI are implemented; full game and physical controls need acceptance.
3. Reproduce Venture room-arrow failure, complete sprite/collision/IRQ investigations and remaining early/discrete and board audio events.
4. Finish native/CRT video work, full clock/latch coverage and per-set pause/reset/reload/persistence/hardware matrix, then prepare small issue-scoped upstream PRs and release artifacts.
