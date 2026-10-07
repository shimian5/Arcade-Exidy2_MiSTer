# Stopping point — 2026-10-07

Work is on `main`, fast-forwarded to the incoming production tree at `55e3300`. Commits are authored as shimian5. The owner authorized local full Quartus flows in unsandboxed PowerShell. No PR has been opened.

## Local checkpoint and immediate continuation

### Active full-flow checkpoint

The latest completed full flow is `3341f08`: compilation succeeded, but master setup is **-0.556 ns** and audio setup **-0.193 ns**. The exact paths are PIA8 DDR masking to the master return register, and `pause_cpu` to the first pause sampling register. Its RBF is unaccepted; releases remain unchanged. See [build evidence](docs/audits/source/local-pia-stage-build-2026-10-07.md).

Production commits `81f85e2` (first-stage-only pause contract) and `2fafa6b` (audio-domain whole-byte source register) address those paths. The two-stage PIA fixture passes all seven offsets and the actual Verilog test. The complete unsandboxed PowerShell flow at `2fafa6b` is running; inspect setup, hold and synchronizer identification before accepting it. Generated counter-clock coverage is still incomplete, so positive PLL-domain slack alone will not establish full signoff.

Standalone Teeter spinner/D-pad/analog controls and FAX four-button-per-player controls have passing focused tests, but neither is production-wired or a working game MRA. The FAX profile gate also preserves other games' reads. 8253 mode 0, canonical/aliased mode 3, continuous reprogramming and warm-reset checks pass without production timer changes. Local Z80 source exists; Mouse Trap still lacks its speech-clock, ROM bus, CVSD and audio integration.


- Main includes incoming production tree `55e3300`, local pause repair `30dbc10`/`594b8dd`, and corrected fixed-PLL constraints `07a1f21`. Remote synchronization follows each reviewed checkpoint.
- Full flow at `594b8dd` compiles, but **timing fails**: master -0.948 ns, audio +0.082 ns, minimum hold +0.184 ns. All eight worst setup paths are PIA8 data/DDR through PIA9 to the main CPU input register. No new exception was added. [Corrected-clock build evidence](docs/audits/source/local-corrected-clock-build-2026-10-07.md).
- Fresh local MAME 0.288 audio-RAM replay: **11 PASS, 0 FAIL, 0 SKIP**, mirrored maps zero mismatches for Venture/Pepper II/Mouse Trap; Mouse Trap flat-map negative control 6,188 mismatches. [Evidence](docs/audits/source/local-audio-ram-replay.md). Local guarded 6840 replay passes all three timer channels at median 0.997 of MAME expected periods; noise and levels remain unverified. [Evidence](docs/audits/source/local-6840-replay.md).
- Profile-0 sprite replay and negative control pass; Venture I05 remains unreproduced. [Sprite evidence](docs/audits/source/local-sprite-rerun-2026-10-07.md).
- Immediate unit: whole-byte PIA return register candidate now passes seven paired-PIA phases and the actual Verilog register test, including previous-register CPU sampling. Run a fresh full Quartus flow; per-game polling/hold behavior remains unproved. [Candidate evidence](docs/audits/source/pia-return-register-candidate.md). The current ignored RBF is not timing accepted. Generated-clock/reset coverage and hardware/game acceptance keep W15 open.
- Owner test paths: HDMI and Direct Video through S-Video to a 15 kHz JVC display. Teeter: spinner plus joystick/D-pad mapping following local Super Off Road or VCO. FAX: four answer buttons per player in the MRA. Exact display/adapter/settings and currently running RBF/MRA still need recording.

Read [PLL contract](docs/audits/source/pll-constraint-contract.md), [generated-clock inventory](docs/audits/source/generated-clock-inventory.md), [audio-domain contract](docs/audits/source/audio-clock-domain-contract.md), and [HANDOFF.md](HANDOFF.md). Existing local probe files and increment-14 metadata changes are preserved.

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
