# Increment 12 — retain speech quarantine through loader verdict

Completed 2026-10-06. All [29 connected expectations](increment-12.json) pass: 28 positives, including actual NAS ROM payloads, plus an expected failure of the missing-verdict-hold mutant. The exact final source also passes the complete unsandboxed [Quartus flow](increment-12-fit.json).

Speech quarantine now includes raw/active/begin/end transport phases through the loader's verdict edge. A duplicate full speech stream cannot briefly enable reads while the previously accepted image still has readiness asserted. The new duplicate-speech case remains faulted/reset-held/read-quarantined. Removing the phase hold in an ignored copy fails specifically at `speech quarantine released before loader verdict`, independent of whether a remote clock happens to sample that narrow gap.

The full-size registered-RAM candidate fits 208/553 RAM blocks, 484 ALMs and 467 registers. TimeQuest identifies five two-register synchronizer chains with calculable estimates under probe assumptions. Full flow exits 0 with 17 warnings. Abstract clocks, virtual I/O/reset and asynchronous clock grouping still prevent board timing/CDC/reset acceptance. Production sources, existing MRAs and RBF are unchanged; generated ROMs and SOF remain ignored and undeployed.

Next dependent work: asynchronous assertion/synchronized reset release per clock domain, then actual clock/CPU/audio integration and whole-core fit. FAX extra PROM/out-of-region banks, complete game/arrow/audio comparisons and CRT transport/hardware acceptance remain open. No claim of game or full-core support follows from these isolated passes.

Current replay: `connected.py --rom-images simulation/expansion_adapter/rom-images --ram-loader` under WSL. For an independent replay use separate `--run-dir`/`--report` paths. Generate the exact probe using `fit_probe.py --synchronizers --increment 12`, then use unsandboxed PowerShell and the complete `quartus_sh --flow compile expansion_probe` flow in ignored fit12.
