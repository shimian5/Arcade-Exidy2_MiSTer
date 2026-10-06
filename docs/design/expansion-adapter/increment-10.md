# Increment 10 — registered block-RAM candidate and successful full flow

Completed 2026-10-06. A separate loader candidate fixes the synthesis blocker while preserving the unchanged baseline. All [27 connected synthetic/ROM cases](increment-10.json) and [public-port/T65-deadline expectations](increment-10-public.json) pass. The corrected isolated [full-flow fit](increment-10-fit.json) succeeds on 5CSEBA6U23I7.

RAM write/read processes now use clocked, reset-free registered outputs. Reset, validity and zero-result selection stay outside the RAM processes, preserving the same visible reset and one-edge read contract. No memory contents are reset. Main question writes/read and dual-clock CVSD writes/read infer as altsyncram. The full-size 192 KiB question store and 16 KiB speech store retain their exact region sizes.

| Standalone fitted resource | Result |
| --- | --- |
| RAM blocks | 208 / 553 (38%) |
| Stored memory bits | 1,703,936 / 5,662,720 (30%) |
| ALMs | 485 / 41,910 (1%) |
| Registers | 456 |

The complete unsandboxed Quartus flow includes synthesis, fit, assembly and TimeQuest; exit 0, 16 warnings. Minimum constrained slack across abstract main 50 MHz/speech 10 MHz setup/hold/pulse-width reports is +0.167 ns. Virtual data/control I/O and reset are not fully constrained, and asynchronous clock groups exclude crossing timing. These figures do not establish whole-core capacity or physical timing/CDC safety.

The first two candidate attempts inferred RAM but failed in probe scaffolding: global virtual-pin assignment swallowed clock pins, then brace syntax was interpreted as literal node names. Their logs remain in ignored fit10 storage; explicit per-port virtual assignments with physical clock pins resolved the harness faults. Production pin/clock assignments were never changed.

Quartus warns that generic `async_reg` attributes are unrecognized; Intel-specific synchronizer identification/placement and reset-release handling still need work. Dual-clock read-during-write is undefined, so the proven logical drain-before-overwrite contract must survive physical implementation. Actual CPU/audio wiring, FAX PROM/banks24..31 parity, whole-core fit and hardware acceptance remain open. Generated probe SOF is ignored and has not been deployed.

Replay connected/public tests with `connected.py --rom-images simulation/expansion_adapter/rom-images --ram-loader` and `public_read.py` under WSL. Generate the project with `python tools/expansion_adapter/fit_probe.py --ram-loader`; build from ignored fit10 using unsandboxed PowerShell and the full `quartus_sh --flow compile expansion_probe` command. Baseline loader and production/release files remain unchanged.
