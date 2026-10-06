# Increment 4 — reset, abort and fault closure

Completed 2026-10-06. [Results](increment-04.json) record 13 successful expectations; isolated adapter only.

A latched transport fault now suppresses all subsequent forwarded bytes and rejects new starts until shared reset. A pending byte is discarded on the next clock after a fault, preventing its replay when a delayed acknowledgement arrives. Errors immediately retain/assert speech quarantine. This deliberately replaces increment 2's diagnostic-only retention policy with closed-session behavior; historical reports describe the old behavior.

New adversaries pass: empty abort/restart while revocation is unacknowledged cannot cancel its generation; shared asynchronous reset with the remote clock stopped clears a held byte and blocks reads; upper address 0x1000001 cannot alias address 1; subsequent valid-looking bytes and restart are rejected after that fault. Slow/stopped remote read-drain cases also pass at latencies 1, 2 and 4. All prior applicable regressions pass, and the level-only acknowledgement mutant still fails specifically at unsafe overwrite.

Shared reset is a contract: independently resetting one clock domain is not accepted. Asynchronous assertion, release synchronization, CDC constraints and memory implementation need physical integration review. The adapter does not understand descriptors or full session readiness; its quarantine release on exact transport length must be combined with loader protocol acceptance before wiring. Next: source-derived HPS command/ACK fixture connected to the unchanged baseline loader, followed by full descriptor/order/length and FAX2 coverage. No production, MRA/RBF or Quartus changes.
