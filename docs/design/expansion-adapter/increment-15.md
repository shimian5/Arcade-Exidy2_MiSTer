# Increment 15 — bridge-level stopped-speech-clock reset and Quartus probe preparation

Completed 2026-10-06 (cloud, Verilator 5.052). [`tb_bridge_reset`](../../../sim/expansion_adapter/tb_bridge_reset.sv) drives the increment 14 bridge with the speech clock stopped across a reset pulse and release: `reset_hold` asserts immediately; the main domain releases without the speech clock; the speech-domain reset stays asserted with no speech edges, with no `cvsd_valid`/`read_accept`; after restart it releases on exactly the second speech edge. A mutant bridge that bypasses the speech synchronizer fails 3 checks. Replay: `python3 tools/expansion_adapter/reset_release.py` ([report](increment-15.json), 4 cases met, includes the increment 13 module cases).

`fit_probe.py --reset-sync` now generates the increment 14 probe (`simulation/expansion_adapter/fit14`, top `exidy_expansion_bridge_rr`, derived loader copy, `rst_meta`/`rst_sync` plus the existing five chains marked `SYNCHRONIZER_IDENTIFICATION "FORCED IF ASYNCHRONOUS"`). It has not been compiled. Owner batch step: generate it on the Windows checkout and run `quartus_sh --flow compile expansion_probe` unsandboxed; compare with increment 12 (208 RAM / 484 ALM / 467 registers).

Still open: Quartus result, PLL-lock reset sources, actual CPU/audio wiring, whole-core fit.
