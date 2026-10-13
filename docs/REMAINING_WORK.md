# Remaining core recovery work - 2026-10-12

## Current checkpoint — 2026-10-13

- [x] Complete native Mouse Trap gameplay/command capture, long replay and retained-B boundary investigation.
- [ ] Native filtered PCM/gain, physical speech, power-cycle/reset/reload acceptance.
- [x] Full-fit production FAX binding with positive reported timing (`2b9eb2b`) and targeted speech/reset inspection.
- [ ] FAX/FAX2 full game/graphics/input/bank hardware checks; resolve startup strap and missing dumps.
- [x] CRT stream/actual mixer/Native phase/adaptive FX and real PLL/controller candidate qualification.
- [ ] CRT common output/options join, production clock/CDC constraints, binding/full fit and HDMI/Direct Video/S-Video receiver tests.
- [x] Side Trak native gameplay reference, exhaustive direct map and character/palette candidates.
- [ ] Side Trak full renderer/sprite scheduling/discrete audio, binding and MRA.
- [ ] Complete remaining titles/clones, Venture arrow/collision/graphics, sound comparisons and legacy timing coverage.

The ignored hardware package contains the accepted development RBF and isolated test MRAs, no ROMs. Hardware and complete-game gates remain open; do not replace Releases or count candidate helpers as full game support.


## 1. Finish Mouse Trap speech and bind the expansion path

- [x] Qualify the unbound deterministic fixed-rate PCM renderer and stopped-clock behavior: 2,867 assertions, actual firmware/tail and full isolated fit pass. Production cadence/binding is now implemented and bounded-tested; boot/native-phrase acceptance remains open. Decoder event math and actual private T80 firmware are qualified separately. The MAME stream method is callback-block-dependent; the candidate implements a stated causal cadence and makes no exact MAME PCM claim. [Evidence](audits/source/mc3417-renderer-2026-10-12.md).
- [x] Qualify unbound two-stage low-pass/0.3086 gain and saturated mono-mix candidates: 63,903 reference samples pass within half a PCM step; full isolated fit passes. [Evidence](audits/source/mc3417-filter-qualification-2026-10-12.md). Production cadence/mix binding is now implemented; native WAV/hardware gain acceptance remains open.
- [ ] Reconcile initial clock phase and production T80 cold/warm boot state. Simulation currently uses explicitly zero-initialized register-bank declarations; production CPU RTL is unchanged. The idle initial digit prefix matches native MAME, but write times differ.
- [ ] Obtain native game-issued bark/meow/chomp commands and verify complete phrases, command/busy/reset behavior and voice inventory. The current passive minute-long capture has only startup ORA/DDRA updates despite later normal inputs.
- [x] Bind accepted audio-CPU RIOT callbacks and PB0 busy with DDR pull-up semantics; speech shares the actual audio clock. Production-source guarded write/DDR/pause/reset fixtures pass; derived-clock physical coverage remains open.
- [x] Bind descriptor/index-6 validation, private voice storage/readiness and ROM adapter to production speech. Actual promoted-source wrapper passes all 84,288 base tuples, speech reads, B0/D0 compatibility, MRA XML order, fault/recovery and legacy reload. Full fit passes; hardware remains an acceptance gate.
- [x] Run bounded joined actual speech firmware: 200 ms, varying ROM latency, 69,054 ordered reads, 3,093 decoder events and 38,399 filtered ticks with no overflow; positive test has explicit simulation-only zeroed register banks. Complete native game/phrase and production boot evidence remains open.
- [x] Complete fresh full unsandboxed Quartus flow; targeted integration timing/coverage audit is recorded with the batch checkpoint.
- [ ] HDMI/Direct Video speech listening on hardware, full phrase/reset/reload/pause and gain acceptance. [Five-step batch](audits/source/speech-production-batch-2026-10-12.md).

## 2. Complete missing games and board profiles

- [ ] FAX/FAX2: bind banked question storage, bank/map/loader and startup-input helper; resolve routing/PROM and out-of-region banks; generate MRAs with four answer buttons per player; verify full gameplay. Reference questions currently require an explicit startup-bit2 diagnostic; candidate low strap is not a confirmed physical board strap.
- [ ] Teeter Torture: full ROM/gameplay comparison and physical spinner plus joystick/D-pad acceptance. Controls and stretched NMI are already integrated and fitted; they do not need to be implemented again.
- [ ] Side Trak: character/monochrome/palette/map differences, controls, audio, board profile and MRA, then complete gameplay.
- [ ] Hard Hat, clones and bootlegs: enumerate every set, apply the correct ROM/profile/input differences and verify sustained gameplay. Target is the full documented game/set matrix, not only the six existing MRAs.

## 3. Resolve sprites, collision and remaining audio

- [ ] Reproduce Venture's room arrow case with room-entry/fire input capture; compare actual sprite serialization, control PROM, ROM latency, clipping, collision and IRQ/frame behavior. Earlier apparent response mismatches were timestamp-order analysis artifacts; the arrow defect itself remains unreproduced.
- [ ] Resolve Targ/Spectar attract jumps/wall crossings against deterministic captures, with complete CPU-visible collision and interrupt timing.
- [ ] Finish Venture/Pepper II/Mouse Trap/Hard Hat sound-event inventories and reference WAV comparisons. Existing mono mix, audio RAM mirror and 6840 fixes are implemented/tested; hardware listening and gain calibration remain.
- [ ] Resolve 6840 noise/timer phase discrepancies, qualify 8253 clock/PCM behavior and finish early Targ/Spectar/Side Trak discrete effects, envelopes, noise and levels.

## 4. Complete video and CRT support

- [ ] Bind the tested native video queue to actual renderer and downstream consumers, including serializer scheduling, RGB/DE ordering and all effects/OSD configurations.
- [ ] Implement the Victory-derived transport/scheduling solution for the 280-line native raster, without changing game timing; qualify clock crossings, PLL/modes and full image transport.
- [ ] Add/validate H/V alignment controls and geometry; test HDMI and Direct Video through S-Video to the owner's 15 kHz JVC display for lock, position and visible boundaries.

## 5. Close whole-design timing coverage and regressions

- [ ] Classify/fix the remaining 3,265 no-clock objects (171 Exidy), 118 multiple-clock objects, 96 latches and one loop. Positive constrained slack does not close these coverage items. The rejected sticky IRQ candidate must not be integrated; preserve simultaneous coin/vblank/clear behavior in its replacement.
- [ ] Rebuild the full project after production speech/expansion/FAX/video changes and check CDC/reset constraints, physical paths, memory and resource budgets.
- [ ] Finish frontend/input/effects and validate existing high-score persistence; saving is already wired.
- [ ] Run the complete per-title/per-set matrix: gameplay, controls, graphics, collision/IRQ, sound, pause/reset/reload and persistence. Record reference-versus-hardware limits.

## 6. Hardware acceptance and release

- [ ] Test the development RBF/MRA combinations on hardware, including the existing audio/profile changes, Teeter controls, speech, FAX inputs and both video outputs.
- [ ] Package final MRAs/RBFs only after these gates; preserve baseline comparison and ROM hashes without committing bytes.
- [ ] Prepare reviewable upstream changes by issue/subsystem with dependencies and validation, rather than one undifferentiated PR. Opening a PR remains owner-requested.

Owner preferences are already settled: spinner plus D-pad/joystick for Teeter; four FAX answer buttons per player; HDMI and Direct Video over S-Video to the 15 kHz JVC. Later physical tests need the exact running RBF/MRA, adapter/settings and results. No additional owner answer is needed to continue the next implementation unit.
