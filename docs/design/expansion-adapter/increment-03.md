# Increment 3 — fresh speech overwrite acknowledgement

Completed 2026-10-06. Isolated simulation RTL only; production integration remains unaccepted.

The adapter now asserts backpressure on a speech start and uses a generation token in addition to the remote level acknowledgement. Each acknowledged generation changes on the next speech transfer. An unacknowledged generation is retained, preventing an aborted transfer from toggling back to an old acknowledgement. The remote clock domain blocks new reads on either quarantine or generation mismatch, drains its accepted-read pipeline, then echoes the generation. Both sides use two-stage synchronizers; physical CDC constraints and common reset ownership still require review.

Eight expectations pass in [results](increment-03.json): five existing transport regressions, a stale-high remote acknowledgement, an outstanding-read revoke with the remote clock stopped/restarted, and the expected failure of a level-only acknowledgement mutant. Each remote positive sends two complete 16 KiB streams with exact byte/address/index checks. Every observed write requires remote acknowledgement, matching generation, no accepted read and an empty outstanding-read pipeline. The mutant fails specifically at unsafe overwrite, rather than a timeout.

The read-pipeline shift now supports latency 1 without a negative slice; this increment tests latency 2 only. Shared asynchronous reset, faulted-session write suppression, abort/restart adversaries and a latency matrix are the next bounded increment. Actual HPS SPI/ACK transport, the connected loader, descriptor/order/length/FAX2 tests, production memory and physical CDC remain open. A cleared quarantine here is a transport result, not full descriptor/session acceptance.

Replay: `wsl.exe -d archlinux --cd /mnt/c/MiSTerDev/Arcade-Exidy2_MiSTer python3 tools/expansion_adapter/review.py`. Historical increment 1/2 reports are retained. No Quartus build or release changes.
