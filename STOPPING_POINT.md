# Stopping point — 2026-10-07

Work is on `main`, fast-forwarded to the incoming production tree at `55e3300`. Commits are authored as shimian5. The owner authorized local full Quartus flows in unsandboxed PowerShell. No PR has been opened.

## Local checkpoint and immediate continuation

Latest completed production flow: `07a49c5`, zero compile errors, **master setup -0.439 ns**, audio +25.120 ns. All five added counter clocks pass reported setup/hold; minimum overall hold +0.252 ns. All eight negative setup paths are the registered audio byte to the master byte register. The isolated bit-5 placement flow completed: assignments honored, worst byte setup -0.330 ns, bit 5 -0.236 ns and byte hold +0.528 ns; all eight bits still fail setup. Its outputs are archived under ignored `simulation/placement-bit5/completed-placement-only/`. The tighter setup-target flow completed; original production-SDC replay still fails all eight byte paths at -0.431 ns, hold +0.565 ns. This fit is rejected. Opposite-edge capture is a proposal undergoing isolated functional checks, not a production edit. Production QSF/RTL are unchanged. RBF remains unaccepted; releases are unchanged. [Latest production full-flow evidence](docs/audits/source/pia-data-valid-build-2026-10-07.md), [steering trial](docs/audits/source/pia-setup-steering-trial.md).

The normal data register plus separately reset validity/output mask is implemented in `07a49c5`. Paired production-PIA tests pass all seven clock offsets, including hidden retained data through reset. The full fit passes valid-mask read timing and valid reset recovery/removal, but byte setup remains negative. Reset removal did not improve timing; the fitted `asdata` name is not evidence of async-reset behavior. Next: review per-bit route/clock skew and a narrow physical packing/placement experiment, keeping byte constraints intact. Remaining event-clock coverage, firmware coherence and hardware/game acceptance stay open.

The owner requested continuation after the usage window reset. Luna units completed a reviewed but unapplied Teeter patch, MAME PIA instrumentation, remaining event-clock diagnostics, actual-T65 write-strobe fixtures, source-extracted IRQ/EIR tests, FAX integration/bank contracts and a 6840 noise recurrence comparison. Independent root replays pass their bounded checks. The seven apparent Venture discrepancies were callback-order artifacts in the analyzer; corrected row-order analysis gives 5,790 matching responses and zero mismatches. Earlier timestamp-derived latency bounds are withdrawn. Firmware/RTL coherence and hardware acceptance remain separate open gates. Existing owner probe files are preserved.

Reviewed evidence:

- Fresh MAME audio-RAM replay: 11 PASS, zero FAIL/SKIP, three mirror traces and flat-map negative control. Guarded 6840 timer window passes pitch medians 0.997; waveform/noise/levels remain open.
- PIA pipeline passes seven related-clock offsets and actual Verilog checks. Corrected callback-row analysis gives Venture 5,790/5,790 matches, Mouse Trap 88/88, Pepper II 1/1 and Hard Hat 1/1, with no mismatches or overwritten responses. Cross-CPU timestamps cannot establish physical response latency; zero-only/startup-limited coverage is still a limitation.
- 6840 noise states match the independent MAME recurrence for 512 transitions, but literal tap event positions differ at 22 steps. Neither the electrically correct tap nor audible output is established. FAX archive-backed bank/PROM audit passes; MAME banks 24-31 point outside its region. FAX2 startup selects bank24 then resets to bank0 without an intervening read; independently reproduced. This does not establish global parity for the adapter's valid-zero policy. Actual timer3 ordering fixture also independently passes its internal checks but records 1,615 output-phase differences from the synthetic MAME model.
- Unchanged 8253 passes mode 0/3, raw mode-7 alias, live divisor changes and warm reset. PCM equivalence remains open.
- Standalone Teeter spinner/D-pad/analog and FAX four-button-per-player helpers pass. Teeter's 17-part MRA candidate passes metadata/loading audit; actual controls and 600 Hz NMI remain unwired; standalone NMI period and actual-T65 pause/vector fixtures pass. These are not working-game releases.
- Local Z80 source exists. Standalone speech-ROM wait/reset-drain helper passes, but actual CPU fetch, variable-latency expansion reset, CVSD and audio mix remain integration gates.
- Profile-0 sprite replay passes; Venture inside-room arrow is still unreproduced.

Owner test paths: HDMI and Direct Video through S-Video to a 15 kHz JVC. Teeter requires spinner plus joystick/D-pad following local Super Off Road; FAX requires four answer buttons per player in its MRA. Record exact display/adapter/settings and running RBF/MRA at hardware acceptance. No additional input is needed for the immediate timing work.

Read [HANDOFF.md](HANDOFF.md) for production rollback commits and [WORKPLAN.md](WORKPLAN.md) for remaining game/issue gates. Owner probe files and increment-14 metadata changes are preserved. Release files and ROM archives are unchanged.

## Production changes since the baseline (all unproven on hardware)

| Change | Files | Evidence | Build / test status |
| --- | --- | --- | --- |
| Mono mix of both audio groups (A1) | `rtl/audio_mix.v`, `rtl/audio_board.v` | `sim/audio_mix` unit test | Not listened to; levels versus MAME unverified |
| Profile-selected collision wiring for `$5103` (S2/S3), selected by `pcb[7:6]`; profile 0 = unchanged | `rtl/int_cause.v`, `rtl/Exidy2.v`, `candidates/mra/*` | `sim/int_cause` vs MAME formula and all observed `$5103` values | Release MRAs untouched; test MRAs in `candidates/mra`; profile-0 sprite fixture and negative control pass |
| Audio RAM as the 128-byte 6532 mirror (A2) | `rtl/audio_ram_map.v`, `rtl/audio_board.v` | `sim/audio_ram` replay of MAME audio-CPU traces: Mouse Trap flat map 6,188 mismatches, mirror 0 | Compiled together; hardware unproved |
| 6840 at the real E clock, immediate load, timer-3 prescale (A4) | `modules/6840/berzerk_sound_fx.vhd`, `rtl/audio_board.v` | GHDL replay of real Venture writes: timers 3.986/3.986/0.498 of MAME formula before, 0.997 after | Compiled together; noise path and levels not compared |
| Audio-clock reset synchronizer; scoped false paths for the PIA handshake, static profile byte and the synchronizer's first flop | `rtl/reset_sync.v`, `rtl/audio_board.v`, `Arcade-Exidy2.sdc` | `sim/reset_sync`; owner timing runs | Complete local flow includes this change; corrected-clock master timing still fails on PIA return data, audio +0.082 ns. Reset and generated-clock coverage remains open |

Environment, tool versions, capture and test commands: [docs/cloud-environment.md](docs/cloud-environment.md). Details: [source audit](docs/audits/source/w05-w08-source-audit.md), [A3/A4](docs/audits/source/a3-a4-audio-effects.md), [timing diagnosis](docs/audits/source/audio-handshake-timing.md), [interrupt-latch survey](docs/reference_cases/int-latch-survey.json).

## Isolated expansion adapter (W02)
Increments 1-15 are in `docs/design/expansion-adapter/`. Increment 14/15: per-domain reset synchronizers in the candidate bridge, 29 connected expectations including the three actual ROM payloads (Mouse Trap CVSD, FAX, FAX 2) pass under Verilator 5.052; the exact probe passes the full Quartus flow (208 RAM blocks, 486 ALMs, 495 registers, all slacks positive, 7 synchronizer chains recognized). This is still standalone; the adapter is not wired into the core.

## Open items

Owner hardware/input gates:
- Close the timed PIA reply-byte failure and complete generated-clock/reset coverage; then test the audio changes (effects two octaves higher, both ears, Mouse Trap audio) and the interrupt profiles with `candidates/mra` against the baseline MRAs.
- Control requirements are supplied: Teeter spinner and joystick/D-pad; FAX four answer buttons per player. Exact CRT model/adapter/settings and running RBF/MRA remain to record; sensitivities/layout need hardware validation.

Doable in the cloud (MAME 0.264, Verilator 5.052, GHDL are installed; ROM zips for mtrap, fax, fax2, targ, spectar, pepper2, hardhat, sidetrac, teetert, venture are staged locally and uncommitted):
- 6840 noise generator and output level versus MAME WAVs (A4 follow-up); 8253 clocks (A5); Targ/Spectar discrete tone path (A7).
- Mouse Trap CVSD path: voice ROM loading is designed and verified in isolation, but local Z80 source exists, but no production speech CPU/CVSD integration exists (W09).
- Venture arrow case (I05): MAME room-entry reproduction not yet scripted; sprite-1 enable gating (S1) is not supported as the cause in the startup-to-maze capture.
- FAX `fxl-12b` PROM routing and banks 24-31 parity; Side Trak, Teeter Torture and FAX/FAX2 profiles (W10-W11); clone/bootleg profiles (W12).
- Remaining reset-release/clock integration of the expansion adapter into the core (actual clocks, CPU, audio) and whole-core fit.

Needs both: native/CRT video integration (W06-W07), per-set regression (W14), physical acceptance (W15), release packaging (W16).

Generated ROM/media/binaries/logs remain ignored under `simulation/`; no ROM bytes are committed. [WORKPLAN.md](WORKPLAN.md) remains the full game/issue tracker.

## Reviewed results

| Area | Accepted at this checkpoint | Still unaccepted |
| --- | --- | --- |
| Video source boundary | Independent input-raster stimulus and queue pass eight bitplanes, all 65,536 pixels, first/last rows and column 255. Wrong expectation fails. Capture-to-output-register-update interval is 18 master clocks. | Production mixer elaboration, game-renderer tap, downstream consumer sampling, enabled gamma/FX/OSD, Native/CRT CDC/PLL/fit and physical output. |
| Sprites | Raw-address Venture right/fire and right-only cases; zero position mirrors in this sequence; exact accepted-bus/common-frame match. All 64 graphic images pass 16,384 source-primitive bits; negative fails. | Inside-room horizontal-shot reproduction/arrow identity, complete control-PROM/ROM-latency/window scheduling, clipping, per-game collision/IRQ and full CPU/frame parity. |
| Expansion transport | Index/skid, fresh read-drain handshake, reset/fault/abort closure; 21 synthetic connected cases and three actual ROM expansion cases pass. Baseline loader unchanged. | Reset-release synchronization, actual clocks/CPU/audio wiring, whole-core fit, remaining boundaries and FAX PROM/banks24..31 parity. Standalone fit is not full-core acceptance. |

[Sixth-block review](docs/design/sixth-block.md) links all evidence. The fifth-block video failure was resolved as a fixture input preparation/timestamp-origin error; it is not proof that production RGB/DE is broken. The original mixer generate-scope issue still needs Quartus elaboration evidence.

## Remaining current-unit work, in resume order

1. **Integrate the expansion adapter into the core.** Per-domain reset release is done and fit at probe level (increments 13-15). Next: bind actual clocks, CPU and audio, prove whole-core fit, then FAX PROM/bank parity and remaining boundaries.
2. **Complete serializer scheduling and actual symptom reproduction.** Instantiate source control PROM, actual ROM latency and gated-clock windows with independent bitmap expectations. The existing async PE-load model and synchronous TI component behavior cannot be swapped without revisiting clock wiring. Script room entry and horizontal firing; current outside-room control/image states select dot/blank graphics and do not identify the reported arrow. Compare clipping, pixel-time image selection and complete affected frames; verify collision masks/polarity and IRQ timing per game.
3. **Bind reviewed video queue to the real renderer and transport.** Preserve the independently measured input acceptance contract; verify actual game RGB/blanking and downstream consumer edges. Establish legal PLL/cascade/Native ownership, implement reviewed CRT scheduling/CDC/mode/geometry work and simulate complete images/effects/faults before the first production build.

## Broader work still pending

- W02: complete FPGA transport/read path, FAX extra `fxl-12b` PROM/decoder routing and out-of-region bank parity, FAX/FAX2 board RAM/maps, fitted memory budget.
- W03–W05: reference cases for remaining release games and missing/clone games; exact forum reproductions; sprites, collision/IRQ, mirrors and game-profile regressions through complete CPU execution and rendered frames.
- W08–W09: shared audio accuracy and complete Mouse Trap CVSD hardware/command/ROM execution; capture/compare each missing voice/sound event.
- W10–W12: Side Trak, Teeter Torture, FAX/FAX2 and clone/bootleg support, including controls and complete game acceptance. Existing ROM availability is not game support.
- W13–W16: frontend/persistence/effects integration, full-flow Quartus builds/timing/resource review, physical acceptance and only then release packaging/regression.

Existing owner inputs remain supplied: NAS ROM library, local MAME and repository releases. Owner supplied the video paths and control requirements above; exact adapter/settings and physical acceptance remain needed at their dependent gates. For the arrow case, first derive a room-entry reproduction from MAME; request an exact owner sequence only if it remains necessary. No new input is required to resume the immediate isolated adapter work.

## Replay commands

```powershell
# Video queue positive eight planes plus expected-failure FIFO control:
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/video_queue/measure.py

# Retained raw-reference analysis uses the read-only NAS archive:
python tools/sprite_serialization/analyze.py
# Source primitive bitmap positives plus expected-failure bit control:
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/sprite_serialization/run_sim.py

# Isolated transport/read-drain positives and unsafe level-only negative control:
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/review.py
```

```powershell
# Latest connected registered-RAM candidate: 28 positives + verdict-hold negative:
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/connected.py --rom-images simulation/expansion_adapter/rom-images --ram-loader
# Baseline public-read/T65-deadline checks on the RAM candidate:
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/public_read.py
# Generate latest isolated Quartus probe; full compile must be unsandboxed PowerShell:
python tools/expansion_adapter/fit_probe.py --synchronizers --increment 12
# In simulation/expansion_adapter/fit12:
# & 'C:\MiSTerDev\intelFPGA_lite\17.0\quartus\bin64\quartus_sh.exe' --flow compile expansion_probe
```

Each runner supports a separate ignored run directory where appropriate. Do not replace historical accepted capture files. Further Quartus work must use unsandboxed PowerShell and the full project flow per the owner's global instructions. Preserve historical reports with separate replay destinations.

```bash
# Self-contained tests added in the cloud work (quiet: one line per test, logs under simulation/test-logs):
python3 tools/run_tests.py --traces <dir with seq_venture.csv, seq_pepper2.csv, seq_mtrap.csv>
```
