# Increment 14 — synchronized reset release wired into the isolated bridge

Completed 2026-10-06 (cloud, Verilator 5.052). [`exidy_expansion_bridge_rr`](../../../sim/expansion_adapter/exidy_expansion_bridge_rr.sv) conditions the raw asynchronous `reset_n` with one [`exidy_reset_sync`](../../../sim/expansion_adapter/exidy_reset_sync.sv) per domain (main `clk`, speech `cvsd_clk`). The adapter, loader main-domain logic and read quarantine see the main copy; the loader's speech-domain block and the remote read quarantine see the speech copy. `reset_hold` also stays asserted while the main synchronizer is in reset, so the core is not released ahead of the loader.

Replay: `python3 tools/expansion_adapter/connected.py --reset-sync --rom-images simulation/expansion_adapter/rom-images` ([report](increment-14.json)). All 29 expectations pass (28 positives including the three actual ROM payload cases, plus the missing-verdict-hold negative). The runner derives the loader copy (extra `cvsd_reset_n` port, two exact-count replacements) and bench copy in the ignored run directory; the accepted bridge, loader and bench files are unchanged. The default `connected.py` behavior and increment 12 evidence are unchanged.

Staged ROM images were regenerated from supplied MAME zips and match the committed increment-07 hashes and empty banks (FAX banks 22/23).

## Not claimed
The bench releases reset on the main clock with both clocks running; bridge-level stopped-speech-clock release is covered only by the standalone increment 13 bench. No QSF synchronizer assignments or Quartus run for this wiring yet (owner machine), and no actual PLL-lock reset, CPU/audio wiring or whole-core fit.
