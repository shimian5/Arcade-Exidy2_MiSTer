# Increment 13 — per-domain reset release (isolated module)

Completed 2026-10-06 in the cloud session. [`exidy_reset_sync`](../../../sim/expansion_adapter/exidy_reset_sync.sv) provides asynchronous assertion and two-edge synchronized release per clock domain, with registers named `rst_meta`/`rst_sync` for later QSF `SYNCHRONIZER_IDENTIFICATION` assignments. [Report](increment-13.json); replay with `python3 tools/expansion_adapter/reset_release.py`.

The [stopped-clock bench](../../../sim/expansion_adapter/tb_reset_release.sv) passes with 0 failures on both domains (50 MHz and 10 MHz abstract clocks): assertion with both clocks stopped; release with clocks stopped stays held; restart of only the speech clock releases only that domain; sub-period reset glitch; release 1 ns before a clock edge; every release observed only on its own rising edge. The `exidy_reset_sync_unsafe` negative control (release passes straight through) fails with 16 checks.

## Environment notes
- Cloud container: Verilator 5.020 (Debian) mis-handles `$finish` inside tasks: connected cases 25/26 print PASS then trip the trailing `assert_closed`. Verilator 5.052 (the pinned version) was built from tag `v5.052` and used for all results here. Use 5.052.
- Main_MiSTer was cloned shallow from upstream. `fpga_io.cpp`, `spi.h`, `spi.cpp` match the pinned hashes; `user_io.cpp` differs (upstream newer; the script's string assertions still hold). Treat host-source evidence as pinned to the Windows copy.
- With 5.052 and no ROM images, the connected suite (`--ram-loader`) passes all 26 non-ROM cases including the missing-verdict-hold negative. The 3 ROM-backed cases need the NAS payloads and were not run.

## Not claimed
The module is not yet instantiated in the bridge, loader or adapter (they still use raw `reset_n`). (Done in [increment 14](increment-14.md) and [increment 15](increment-15.md).) Next was: wire one synchronizer per domain into the bridge, replay the connected suite for added release latency, add QSF assignments to the probe, then full-flow Quartus on the owner's machine. Actual PLL-lock-derived reset, CPU/audio wiring and whole-core fit remain open.
