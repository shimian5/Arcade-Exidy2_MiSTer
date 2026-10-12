# Mouse Trap production boot and warm-reset audit — 2026-10-12

## Scope

This audit checks the T80 register-bank startup behavior used by the Mouse Trap speech CPU, the staged private ROM, and retention across the voice helper's PA4-controlled warm reset. It does not qualify the complete audio subsystem, renderer, or production ROM latency path. The fixture uses source-identical simulation copies of `T80_Reg`, `T80se`, and `Z80` only to seed and observe T80's internal `REG` bus; no production RTL was changed.

## Source and fitted-netlist findings

`modules/cpu-t80/T80_Reg.vhd` declares `RegsH` and `RegsL` without initialization and without a reset input. `modules/cpu-t80/T80.vhd` resets core control state, including PC, but does not reset those arrays. Therefore CPU reset alone does not define the register-bank values; the source explicitly preserves them on reset.

The current `Arcade-Exidy2.qsf` enables `ALLOW_POWER_UP_DONT_CARE`. The reproducible read-only query is `sim/mousetrap_boot/inspect_powerup.tcl`; against the existing mapped netlist (`read_atom_netlist -type map`, `get_atom_nodes -type FF`) it found exactly 128 T80 register-bank FF atoms under `mousetrapSpeechSubsystem`. Every one reported `BOOL_POWER_UP_DONT_CARE=1` and `BOOL_POWERS_UP=0`. This provides no cold-start value guarantee. The generic `POWER_UP_HIGH` report rows do not establish a value for these bank bits. I could not load an assembler/post-fit atom netlist from the existing CDB; Quartus CDB reported that it required the Quartus Prime elaboration/map stage for that netlist type. Thus the evidence is for the mapped register atoms and project power-up policy, not a measured post-fit per-bit value.

The raw simulator case confirms the distinction: the uninitialized VHDL arrays are X before firmware release and the real ROM reaches an unknown first firmware output. This is not a proof that hardware will power up X; it demonstrates that the previous fixture's zero initialization was an assumption, not a consequence of T80 reset. Seed cases deliberately use different initialized register banks to test sensitivity without asserting that any pattern is a physical cold-start value.

## Fixture and results

Run `sim/mousetrap_boot/run_boot.ps1`. It checks that the staged ROM has 16,384 bytes and matches `docs/design/expansion-adapter/increment-07-roms.json` SHA-256 `96aabec1a71953afb98f4a28d090c9d2b3564cf7b487cf55604c96aaeba23bf0`. Run output is under ignored `simulation/mousetrap_boot/`; the verified run was `modelsim-boot-20261012-134417-175`.

The fixture has five cases:

- `raw`: leaves the original register declarations uninitialized, confirms their pre-release state is unknown, and observes the expected unknown firmware I/O at 88.643 µs.
- `zero`: initializes both banks to zero in a generated simulation-only source copy.
- `seed_a`: initializes H to `20+n` and L to `80+n` for banks 0–7.
- `seed_b`: initializes H to `D0+n` and L to `30+3n` for banks 0–7.
- `seed_odd`: initializes H to `21+n` and L to `81+n` for banks 0–7, making the first firmware output bit differ from the even seeds.

Each initialized case used the staged ROM and produced 642 ROM reads, 24 I/O writes, and 20 digit writes in the bounded run. Zero, seed A, and seed B produced the same first 20 D0 speech bits: `01010110110101011001`. Their full output bytes differ, but `mousetrapVoiceIo` captures only `io_data_in[0]` as the CVSD digit, so those upper-byte differences do not change the speech stream. The odd seed's first 20 bits were `10010110110101011001`; compared with zero it differed at digit positions 1 and 2, both in epoch 0 before the warm reset, then matched for the remaining 18 bits. This shows a two-bit startup sensitivity for the tested odd bank pattern, not a persistent stream divergence and not proof that all possible cold values behave identically. At 16 digit writes, the fixture drained the synchronous ROM response, drove PA4 low to assert the CPU reset, and verified all 128 bank bits remained unchanged after eight clocks. It then released PA4 and observed the twentieth digit write. All five cases passed their expected checks. ModelSim emitted startup metavalue warnings (26 in the raw case and 20 in each initialized case); these are retained in the logs and are not suppressed by the runner.

## Boundaries and follow-up

The fixture uses the actual T80 core, actual staged ROM, `speechRomBus`, and `mousetrapVoiceIo`, with a variable 32.32152 µs RC half-clock needed by firmware polling. It is a startup and warm-retention test, not a complete production wrapper or full-game replay. Seeded bank contents are test controls only.

The production cold-start bit value remains unqualified because the fitted per-bit startup value was not available from the existing CDB inspection. The current source and mapped-netlist evidence do not by themselves justify initializing the whole register bank: the three even seeds yielded identical speech bits, while the tested odd seed changed the first two bits and then converged. This audit makes no claim that every possible cold value is harmless. Any decision about masking or defining those initial bits should weigh the bounded voice-bit evidence against the lack of a cold-value guarantee. No production repair was made.

Parent independently reran all five modes successfully at `simulation/mousetrap_boot/modelsim-boot-20261012-134503-333` and the read-only mapped power-up query at `simulation/mousetrap_boot/parent-powerup-audit.log` (zero errors/warnings, all 128 atoms power-up-don't-care).
