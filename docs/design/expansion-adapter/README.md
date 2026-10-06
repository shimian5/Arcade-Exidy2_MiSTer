# Expansion transport — current checkpoint after increment 12

Stopped at 98% weekly usage, preserving approximately 2%. The isolated registered-RAM bridge passes 29 connected expectations (28 positives plus a missing-verdict-hold negative), including actual Mouse Trap/FAX/FAX2 expansion bytes. Its exact-source unsandboxed full Quartus flow succeeds: 208/553 RAM blocks, 484 ALMs, 467 registers. Five intended two-register synchronizers have calculable tool estimates under abstract probe assumptions. Production and release files remain unchanged.

[Increment 12](increment-12.md), [simulation results](increment-12.json) and [fit results](increment-12-fit.json) are the current evidence. [STOPPING_POINT.md](../../../STOPPING_POINT.md) records resume order and commands; [WORKPLAN.md](../../../WORKPLAN.md) tracks the broader core/game work.

| Historical checkpoint | Scope |
| --- | --- |
| [Original review](review-results.json) | Begin-index, skid-arrival and stale-ack defects reproduced. |
| [1](increment-01.md), [2](increment-02.md) | Begin/index and ordered skid fixes. |
| [3](increment-03.md), [4](increment-04.md) | Fresh generation/drain, shared reset/fault/abort and latency boundaries. |
| [5](increment-05.md), [6](increment-06.md) | Source-derived ordinary file/GPIO/ACK connection and synthetic descriptor/FAX matrix. |
| [7](increment-07.md), [8](increment-08.md) | Actual ROM payloads and combined reset/read contract. |
| [9](increment-09.md), [10](increment-10.md) | Baseline RAM inference fails; separate registered-RAM candidate passes behavior and full flow. |
| [11](increment-11.md), [12](increment-12.md) | Intel synchronizer identification and duplicate-speech verdict-gap closure. |

Historical hashes/results describe their own source versions and are preserved. The baseline loader and its copied source remain unchanged; the fitted candidate is separate. ROM bytes, captures, binaries, logs and probe SOF remain in ignored simulation storage and have not been deployed.

Replay the latest connected candidate under WSL with `connected.py --rom-images simulation/expansion_adapter/rom-images --ram-loader`; `public_read.py` checks its baseline public-read/T65-deadline behavior, while `review.py` checks isolated adapter/read-drain behavior. Use explicit independent run/report paths to preserve historical metadata. Generate the exact full-flow project with `fit_probe.py --synchronizers --increment 12`, then compile from ignored fit12 using unsandboxed PowerShell.

Next: asynchronous assertion and synchronized reset release per clock domain, with stopped-clock adversaries, before actual clock/CPU/audio wiring. Whole-core capacity, physical CDC/board timing, other HPS/SoC/fast-MMIO paths, FAX extra PROM/banks24..31 parity, full game/audio execution and CRT/hardware acceptance remain open. Abstract clocks, virtual I/O/reset and asynchronous groups prevent treating this standalone fit or its MTBF estimates as physical signoff.
