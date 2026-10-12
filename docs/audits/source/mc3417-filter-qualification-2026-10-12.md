# Mouse Trap board filter and mix candidate - 2026-10-12

## Candidate behavior

The unbound `exidyMc3417Filter` applies Q28 route gain 0.3086, then two identical inverting low-pass stages. Board values from the pinned Exidy sound source are R1=10k, R2=3.9k, R3=18k, C1=20nF, C2=2.2nF: cutoff 2863.68495 Hz, Q 0.87352216 and gain -1.8 per stage. Pair gain including route is 0.999864 at DC. Coefficients target an explicit **192 kHz** sample cadence. MAME's native biquad stream is adaptive; native WAV/resampling equality is not implied.

`rtl/exidy_biquad.v` uses direct-form I with Q24 input/history and Q28 coefficients. Five serialized multiply/accumulate terms share one multiplier per stage. The signed accumulator retains guard bits; final state saturates to signed 32 bits rather than wrapping. The pair and prefilter gain produce a result 12 master clocks after input capture; sample enable must allow pipeline completion. Normal 74/75-clock spacing at the nominal master easily exceeds this requirement. An overlapping stage commit sets sticky `overrun`; the rejected input is not silently queued. The caller must maintain valid spacing and monitor overrun. Cold reset clears histories/pipeline; warm CPU reset must preserve them.

The output remains Q24 until final signed-16 conversion by arithmetic shift and saturation. `exidySpeechMix` adds existing base mono and speech in signed 17 bits, clamps to signed 16 bits, reports mix clipping and forces mute output to zero. Existing base level is retained, with speech at the reference-derived route gain. Actual production gain/headroom, clock domains, pause/reset and listening still need acceptance; this candidate changes no existing production audio path.

## Independent reference and simulation

The [reference generator/audit](mc3417-filter-reference-2026-10-12.md) strictly verifies pinned source hashes and extracts MAME's actual C++ DF-II `step()` into an ignored wrapper. Its double-state/float-input/output oracle is independent of the RTL DFI recurrence. Coefficient equations are separately translated in Python and C++ and compared. Expected sample vectors use the C++ method and float stream boundaries, not the RTL equations.

Final ModelSim passes **63,910 assertions over 63,903 samples in 11 cases**, maximum error **170 Q24 units = 0.33203125 of a 16-bit PCM step**, below the 256-unit / half-step limit. Cases include positive/negative impulses and steps, DC settling, 1/10 kHz tones, deterministic noise, over-full-scale steps and **44,927 captured actual-firmware-renderer samples**. Each reference case resets histories. PCM shift/clamping, mixer positive/negative saturation and mute, valid-cadence no-overrun, output hold after completion and sticky overrun are checked. A wrong B1 coefficient is rejected by the specific oracle-mismatch assertion. Input commits are tested at exact 75-clock spacing, with output order/latency accounted for.

Run `./sim/mc3417_filter/run_fixture.ps1` from an unsandboxed PowerShell because its pinned oracle compilation uses WSL. Add `-FirmwarePcm simulation/mousetrap_firmware/modelsim-firmware-20261012-120417-671/pcm.csv` for the private optional firmware trace. Requires Archlinux WSL/g++, native ModelSim and the pinned ignored sources. The runner generates vectors afresh, records all outputs under ignored `simulation/mc3417_filter/`, and rejects a mutant in a separate generated library. Final evidence: `simulation/mc3417_filter/modelsim-20261012-121631-789/`. No ROM bytes, CSVs, game audio or logs are committed.

This is filtered-sample agreement **given the same input trace and cadence**. The trace comes from the existing firmware fixture's diagnostic command and explicit boot assumption. It does not demonstrate bark/meow/chomp, native MAME scheduler/rate equality, complete audio-CPU command integration or hardware sound.

## Full-flow build and timing

Final unsandboxed PowerShell full flow `quartus_sh --flow compile mc3417_filter_probe`, run inside its generated directory, completed 2026-10-12 at 12:15:09: **0 errors, 1 free-edition LogicLock warning**. Resource use: **368 ALMs, 517 registers, 9 DSP blocks, no RAM**. Minimum setup **+49.639 ns**, hold **+0.170 ns**, minimum pulse width **+33.848 ns**, all TNS zero. Post-flow physical timing/coverage reports show zero no-clock/multiple-clock objects, latches or loops in this candidate. Virtual data/control/reset I/O has no board delay qualification, so full-core CDC/reset and binding timing remain open.

`tools/mc3417_filter/fit_probe.py` prepares the isolated Cyclone V project and source manifest at `simulation/mc3417_filter/fit/`. Clock period is 69.604 ns; coefficient sample cadence is 192 kHz, not the master clock period. Exact final source hashes: `rtl/exidy_biquad.v` = `66156c7c408c49e1398a662bd3c795b3568efe2d9b9c5a73320c4d62971c43fd`; `rtl/mc3417_filter.v` = `3641e654dce961e22ca43659fba5e79a26fe4e7d1c92337c186ee12da7c7ed1c`. Both candidates remain outside production QIP; last production build is still `020b2ae`.

## Next integration unit

Bind accepted RIOT output callbacks to ordered speech-command delivery in the real clock domains, preserving DDR pull-ups, busy and CPU reset. Then bind the validated voice image/expansion endpoint and hold execution until readiness. Join the qualified renderer/filter/mix under the production sample cadence and run full-core resource/timing plus reset/reload/pause regressions. Native game-issued command/phrase, initial clock phase and T80 boot-state evidence, native WAV/rate comparison and hardware listening remain explicit gates.
