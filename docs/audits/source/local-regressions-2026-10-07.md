# Local regression rerun — 2026-10-07

Later checkpoint: fresh local MAME 0.288 traces and the pause synchronizer now produce **11 PASS, 0 FAIL, 0 SKIP**. See [local audio-RAM replay](local-audio-ram-replay.md). The six-pass recovery below remains historical evidence of the earlier run; its trace skip is superseded.

The completed local rerun used Arch WSL and Verilator **5.052**. It returned **0** with **6 PASS, 0 FAIL, 1 SKIP**. The initial worker attempt below was incomplete; the recovery and accepted result are recorded first.

From unsandboxed PowerShell at the repository root:

```powershell
wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer -e bash -lc 'export MAKEFLAGS="OPT_FAST=-O0"; python3 -u tools/run_tests.py'
```

Passed: mono mix and required-failure mutant; interrupt profiles; audio reset synchronizer; expansion reset release and two negative controls; connected expansion suite. The connected metadata contains **29 expectations met**: 28 positive cases, including the Mouse Trap/FAX/FAX 2 ROM-backed cases, and the missing-verdict-hold mutant rejected at its intended contract. Audio-RAM trace replay was skipped because the three local CSVs were unavailable. Slow GHDL replay was not rerun.

The `OPT_FAST` setting changes generated C++ compilation optimization, not RTL or expectations. The successful aggregate log is `simulation/test-logs/root-runner-clean-O0-2026-10-07.log`; connected metadata is `simulation/test-logs/connected.json`, with all 29 `expectationMet` fields true. The harness verifies the staged ROM lengths and SHA-256 before simulation. ROMs, generated metadata and logs remain ignored.

A retained root rerun exposed an invalid precompiled header in the interrupted negative build. That directory was preserved as `negative-obj-interrupted-20261007`. A fresh optimized compile then ended during a WSL shutdown, before its compiler returned; kernel messages show systemd shutdown and filesystem unmount, but do not establish who initiated it. That directory was preserved as `negative-obj-interrupted2-20261007`. Changing optimization requires fresh precompiled headers: the clean negative build with `OPT_FAST=-O0` completed and the full runner passed. No harness or production RTL change was needed.

This validates isolated logic and bounded expansion transport. Full CPU/gameplay, audible waveform, physical CDC and production expansion integration remain unaccepted.

## Historical initial worker attempt

Command run inside WSL Arch Linux from the repository root:

```sh
python3 -u tools/run_tests.py
```

Toolchain reported `Verilator 5.052 2026-09-05 rev v5.052`.

The runner printed these five passing results before the WSL invocation ended:

- audio mono mix
- audio mono mix: mutant must fail
- interrupt cause profiles
- audio reset synchronizer
- reset release (module, bridge, 2 negative controls)

The runner did not print its final result summary. The WSL process returned exit status 1 while the connected expansion suite was underway; `simulation/test-logs/connected.log` and `connected.json` were not produced. Its case logs establish three ROM-backed passes: `mtrap-rom-speech.log` reports connected case 21, `fax-rom-questions.log` reports matrix case 22, and `fax2-rom-questions.log` reports matrix case 23. The connected suite had built its Verilated executable and created these case logs, but the full suite result remains unreported. A `negative-obj` directory was also left without a corresponding completed negative-build log, consistent with the runner ending during the negative-control build. The available evidence does not establish why the WSL invocation ended or identify a runner defect, so no harness change was made.

The `simulation/expansion_adapter/rom-images` directory contained `fax.hex`, `fax2.hex`, and `mtrap.hex`; the three passing ROM-backed cases above used these images. No `seq_venture.csv`, `seq_pepper2.csv`, or `seq_mtrap.csv` traces were found under the repository or the usual `C:\\MiSTerDev` / user-data locations. The trace replay branch was therefore not run.

Final runner count: unavailable (no summary line). Confirmed from emitted output: 5 PASS, 0 reported FAIL, 0 reported SKIP; remaining coverage is unreported because the process ended before the runner finished.
