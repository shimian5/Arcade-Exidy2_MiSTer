# Stopping point — 2026-10-06

**Increment 13 (cloud session):** per-domain reset-release module and stopped-clock bench pass with a failing unsafe negative control; connected suite replays 26/26 non-ROM cases under Verilator 5.052. Not yet wired into the bridge. See [increment-13](docs/design/expansion-adapter/increment-13.md). Use Verilator 5.052; 5.020 gives false failures in cases 25/26.

Current owner instruction: continue bounded increments until weekly usage is approximately 98% used, then preserve roughly 2% for the owner. **Stopped after increment 12 at 98% weekly usage (approximately 2% remaining).** No agent or build is running; no next increment was started. Luna workers previously reached their usage limit; the integrator completed these bounded increments. Resume only on a new owner instruction.

Increment 12 closes duplicate-speech quarantine through the loader-verdict edge. All 29 connected expectations pass, including 28 positives and a missing-hold negative control. Exact-source isolated full Quartus flow succeeds: 208 RAM blocks, 484 ALMs, 467 registers; five two-register synchronizers have calculable estimates under probe assumptions. [Report](docs/design/expansion-adapter/increment-12.md), [simulation](docs/design/expansion-adapter/increment-12.json) and [fit](docs/design/expansion-adapter/increment-12-fit.json) preserve evidence. Next: reset release per domain before production integration.

Production RTL/framework, existing MRAs and RBF remain at the original baseline. Isolated full-flow probes include the failed baseline and successful RAM candidate; no production compile, deployment, commit or PR was performed. Generated ROM/media/binaries/logs remain ignored under `simulation/`. [WORKPLAN.md](WORKPLAN.md) remains the full game/issue tracker; W02–W07 are ACTIVE, with other game/audio/build/acceptance work still pending.

## Reviewed results

| Area | Accepted at this checkpoint | Still unaccepted |
| --- | --- | --- |
| Video source boundary | Independent input-raster stimulus and queue pass eight bitplanes, all 65,536 pixels, first/last rows and column 255. Wrong expectation fails. Capture-to-output-register-update interval is 18 master clocks. | Production mixer elaboration, game-renderer tap, downstream consumer sampling, enabled gamma/FX/OSD, Native/CRT CDC/PLL/fit and physical output. |
| Sprites | Raw-address Venture right/fire and right-only cases; zero position mirrors in this sequence; exact accepted-bus/common-frame match. All 64 graphic images pass 16,384 source-primitive bits; negative fails. | Inside-room horizontal-shot reproduction/arrow identity, complete control-PROM/ROM-latency/window scheduling, clipping, per-game collision/IRQ and full CPU/frame parity. |
| Expansion transport | Index/skid, fresh read-drain handshake, reset/fault/abort closure; 21 synthetic connected cases and three actual ROM expansion cases pass. Baseline loader unchanged. | Reset-release synchronization, actual clocks/CPU/audio wiring, whole-core fit, remaining boundaries and FAX PROM/banks24..31 parity. Standalone fit is not full-core acceptance. |

[Sixth-block review](docs/design/sixth-block.md) links all evidence. The fifth-block video failure was resolved as a fixture input preparation/timestamp-origin error; it is not proof that production RGB/DE is broken. The original mixer generate-scope issue still needs Quartus elaboration evidence.

## Remaining current-unit work, in resume order

1. **Finish reset release and physical integration before wiring.** Separate RAM candidate, combined reset/read/verdict gating and scoped Intel synchronizers pass isolated behavioral/full-flow checks. Next: async assertion with synchronized reset release per clock domain and its stopped-clock adversaries. Then bind actual clocks/CPU/audio and prove whole-core fit. Remaining boundaries and FAX PROM/bank parity stay open.
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










