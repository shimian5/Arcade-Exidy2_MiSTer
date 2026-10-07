# Stopping point — 2026-10-07

Branch `claude/nice-goodall-idlhs4`, commits authored as shimian5. Work continues in bounded blocks; Quartus runs happen on the owner's machine on request. No pull request has been opened.

## Production changes since the baseline (all unproven on hardware)

| Change | Files | Evidence | Build / test status |
| --- | --- | --- | --- |
| Mono mix of both audio groups (A1) | `rtl/audio_mix.v`, `rtl/audio_board.v` | `sim/audio_mix` unit test | Not listened to; levels versus MAME unverified |
| Profile-selected collision wiring for `$5103` (S2/S3), selected by `pcb[7:6]`; profile 0 = unchanged | `rtl/int_cause.v`, `rtl/Exidy2.v`, `candidates/mra/*` | `sim/int_cause` vs MAME formula and all observed `$5103` values | Release MRAs untouched; test MRAs in `candidates/mra`; sprite fixture (WSL-only) not rerun |
| Audio RAM as the 128-byte 6532 mirror (A2) | `rtl/audio_ram_map.v`, `rtl/audio_board.v` | `sim/audio_ram` replay of MAME audio-CPU traces: Mouse Trap flat map 6,188 mismatches, mirror 0 | Not Quartus-built |
| 6840 at the real E clock, immediate load, timer-3 prescale (A4) | `modules/6840/berzerk_sound_fx.vhd`, `rtl/audio_board.v` | GHDL replay of real Venture writes: timers 3.986/3.986/0.498 of MAME formula before, 0.997 after | Not Quartus-built; noise path and levels not compared |
| Audio-clock reset synchronizer; scoped false paths for the PIA handshake, static profile byte and the synchronizer's first flop | `rtl/reset_sync.v`, `rtl/audio_board.v`, `Arcade-Exidy2.sdc` | `sim/reset_sync`; owner timing runs | Latest owner run: master clock met, audio clock about -0.3 ns from `mod_other[4]`; a false path for it was added after that run and is not yet built |

Environment, tool versions, capture and test commands: [docs/cloud-environment.md](docs/cloud-environment.md). Details: [source audit](docs/audits/source/w05-w08-source-audit.md), [A3/A4](docs/audits/source/a3-a4-audio-effects.md), [timing diagnosis](docs/audits/source/audio-handshake-timing.md), [interrupt-latch survey](docs/reference_cases/int-latch-survey.json).

## Isolated expansion adapter (W02)
Increments 1-15 are in `docs/design/expansion-adapter/`. Increment 14/15: per-domain reset synchronizers in the candidate bridge, 29 connected expectations including the three actual ROM payloads (Mouse Trap CVSD, FAX, FAX 2) pass under Verilator 5.052; the exact probe passes the full Quartus flow (208 RAM blocks, 486 ALMs, 495 registers, all slacks positive, 7 synchronizer chains recognized). This is still standalone; the adapter is not wired into the core.

## Open items

Blocked on the owner (build, listening or hardware):
- Rebuild the full core, report slacks and any new top paths (`pause` into the audio CPU `rdy` and the mono mute are the next suspects); then test the audio changes (effects two octaves higher, both ears, Mouse Trap audio) and the interrupt profiles with `candidates/mra` against the baseline MRAs.
- Rerun `tools/sprite_fixture/run_fixture.py` on WSL (it was edited to pin profile 0).
- Choices still owed: Teeter Torture control device, FAX answer-button mapping, CRT model/adapter/settings, which RBF/MRA is running on hardware.

Doable in the cloud (MAME 0.264, Verilator 5.052, GHDL are installed; ROM zips for mtrap, fax, fax2, targ, spectar, pepper2, hardhat, sidetrac, teetert, venture are staged locally and uncommitted):
- 6840 noise generator and output level versus MAME WAVs (A4 follow-up); 8253 clocks (A5); Targ/Spectar discrete tone path (A7).
- Mouse Trap CVSD path: voice ROM loading is designed and verified in isolation, but no Z80/CVSD core exists (W09).
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

Existing owner inputs remain supplied: NAS ROM library, local MAME and repository releases. Owner CRT/adapter/settings, control choices and physical acceptance are needed at their dependent gates. For the arrow case, first derive a room-entry reproduction from MAME; request an exact owner sequence only if it remains necessary. No new input is required to resume the immediate isolated adapter work.

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
