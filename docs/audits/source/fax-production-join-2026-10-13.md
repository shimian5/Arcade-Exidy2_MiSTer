# FAX production join — 2026-10-13

Production binding is committed as `98ec95a`. Exact extended profiles are FAX marker F4 → PCB74/profile1 and FAX2 marker F8 → PCB78/profile2. The existing speech profile and legacy B0/D0 bytes remain preserved. Both candidate MRAs carry four answer buttons for each player, full verified base tuples and a 192 KiB question stream. These are candidate MRAs; Releases remain untouched.

## Functional evidence

- Actual source FIO/GPIO acknowledgement path into the production wrapper passes both MRA streams: every base and question byte, all 24 bank boundaries, deterministic invalid-bank quarantine, mismatch faults, reload, legacy fallthrough and speech preservation.
- Actual T65 executes synthetic bytecode through the verbatim extracted production input/read mux. Independent $0000/$0400 work RAM, question read/bank latency, P1/P2/start inputs, startup-check bit and legacy fallthrough pass (4,506 cycles). Root independently reran the fixture.
- Existing regressions report seven PASS, zero FAIL and one optional trace SKIP.

These fixtures do not run the full FAX game/video/audio path. The startup strap is unresolved, so Skip/Run remains a visible diagnostic option. FAX's two NO_DUMP question banks remain unavailable. Zero for selectors 24–31 is an explicit quarantine policy, not physical/MAME parity.

## Full-flow timing finding and repair in progress

The first full unsandboxed Quartus flow completes with zero errors/301 warnings but fails hold at -4.773 ns. Exact inspected path: graphics RAM download write-enable register to `U13D_M1VA` sprite shifter, launch master clock and capture inverted PH_6. Its clocks were kept related and timed; no exception was added.

The bounded repair changes only `U11D_gfx.CLK_DL` to the falling edge of master clock. Accepted download tuples settle after a rising edge, giving the write port the opposite half-cycle; the gameplay read port and sprite clocks retain their existing wiring. The actual production graphics instance and vendor RAM model pass all 2,048 bytes on each of two uploads, with consecutive writes and inserted gaps. An independent wrong-expected-byte control fails. ModelSim's RAM model crashes on the production blank init-file name, so the private simulation copy uses its UNUSED sentinel; every byte is overwritten before checking and no initial-state claim follows.

The full phase-repair flow at `simulation/full-core/fax-gfx-phase-20261013` completes with zero errors/302 warnings. The download-to-shifter failure is absent; a different internal U13D shifter-register hold path remains at -0.785 ns. A placement-seed-2 full refit is now running at `simulation/full-core/fax-gfx-seed2-20261013`, with the original related-clock constraints intact. Timing acceptance remains open. The rejected first-flow RBF is preserved privately for diagnosis and is not a hardware test candidate.
