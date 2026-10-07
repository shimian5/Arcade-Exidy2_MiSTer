# Bounded MAME reference cases

Reviewed 2026-10-06. These are MAME references and a startup diagnostic, not evidence that production RTL matches MAME or that a forum defect has been reproduced.

| Case | Retained ignored runs | Result |
| --- | --- | --- |
| Targ zero-input attract | targ/run04, run05 | PASS: seven matching 256x256 decoded frames, 22,847 bus events through frame 3599, identical events and ROM-verification logs. |
| Spectar zero-input attract | spectar/run03, run04 | PASS: seven matching decoded frames, 59,186 bus events through frame 3599, identical events and ROM-verification logs. |
| Independent Targ replay | targ/integrator_final01, integrator_final02 | PASS: seven matching decoded frames and 22,847 bus events. |
| Venture startup + right/fire input | venture_startup/active03, active04 | PASS: deterministic 60-second pair reaches the maze; 189,581 bus events through frame 3600 and 13 matching decoded frames. Right/fire input is observed; exact arrow identity remains unproven. |
| Venture right-only control | venture_startup/right_only01 | PASS: matched single-run control reaches the same gameplay; `$FB` confirms right active with Button 1 released. |

[Reviewed derived manifests](reviewed-manifests.json) retain hashes, settings, counts and frame hashes without ROM bytes or images. Actual outputs remain under ignored `simulation/reference_cases/` and `simulation/venture_startup/`. Older exploratory runs remain local evidence and are not the final accepted pairs.

The runner uses MAME 0.288, pinned board-driver commit `27a8d9e85b58058965907d1d8a7a92f8ed039348`, NAS ROMs directly, fresh private configuration/state paths, no plugins, no throttle, video none and sound auto at -32 dB. Each run freezes its Lua script. Targ/Spectar stop at frame 3600; Venture startup/gameplay runs stop at frame 3600. Frame callbacks capture actual rendered screens. Strongly retained passive memory taps record actual CPU reads/writes, including sprite mirrors and IRQ acknowledgements; the observer never reads the IRQ register itself.

The validator checks completion/errors, nontrivial 256x256 images, late-run tap activity and decoded RGB hashes. The comparator requires matching executable/ROM/script/reference hashes, input and emulator settings, bus/events/verification logs and decoded frame pixels. It normalizes the verification log's encoding and line endings for PowerShell-version differences; other event logs remain byte-exact. Performance logs are hashed but not required to match. Explicit settings were backfilled from recorded commands in runs created before the manifest field was added; capture files were unchanged. The final integrator replay independently checked the Targ/Spectar pairs.

## Venture evidence

The former 15-second `venture/run05` ended during startup and does not demonstrate a permanent hang. A fresh zero-input 60-second diagnostic first observes a `$5103` IRQ acknowledgement at frame 1720 (28.68 seconds), then reaches the attract display. `venture_startup/active03` and `active04` replay a coin/start/right+Button 1 schedule after startup; a right-only matched-control run confirms the CPU-visible input distinction. The paired captures prove horizontal movement under right/fire but do not conclusively identify the second moving object as an arrow/projectile or reproduce a core defect. Details and exact commands are in [venture-startup.md](venture-startup.md). Use `venture_startup.ps1` for Venture; the generic `run_case.ps1` remains a short 16-second diagnostic.

## Replay

From an unsandboxed PowerShell session at the repository root for read-only NAS access, choose fresh run names:

```powershell
& tools/reference_cases/run_case.ps1 -Set targ -Run reviewA
& tools/reference_cases/run_case.ps1 -Set targ -Run reviewB
python tools/reference_cases/validate_capture.py simulation/reference_cases/targ/reviewA
python tools/reference_cases/validate_capture.py simulation/reference_cases/targ/reviewB
python tools/reference_cases/compare_runs.py simulation/reference_cases/targ/reviewA simulation/reference_cases/targ/reviewB
```

Repeat with `spectar`. For Venture's long startup and input case, use the dedicated command sequence in [venture-startup.md](venture-startup.md). Full-board RTL comparison, exact projectile identity, other release games, detailed audio events and cycle-level collision timing remain open work.

## Interrupt-latch survey (2026-10-07)
[int-latch-survey.json](int-latch-survey.json) records `$5101` writes and `$5103` reads for Targ, Spectar, Side Trak, Mouse Trap, Pepper II, Hard Hat, Teeter Torture and Venture (zero-input attract, plus the Venture coin/start/right[+fire] case) on MAME 0.264. Replay with `tools/reference_cases/survey_int_latch.py`. Audio-CPU RAM-window traces use `tools/reference_cases/audio_ram_seq.lua`.

