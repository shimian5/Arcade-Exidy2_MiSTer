# Teeter 600 Hz NMI candidate

This is a standalone candidate and source-backed test unit. It does not connect an NMI to production `Exidy2.v`, add a QIP entry, alter constraints, or claim Teeter support.

## Source contract and candidate

Pinned MAME 0.288 [`exidy.cpp`](https://github.com/mamedev/mame/blob/mame0288/src/mame/exidy/exidy.cpp#L1514-L1522) configures `teetert_state::teetert` to call `nmi_line_pulse` every `from_hz(10*60)`, or 600 Hz. The live main T65 uses `master_clock`, `PH_1` enable, `rdy(~pause)`, and currently ties `nmi_n` high. In `rtl/Exidy2.v`, `PH_1` is a one-master-tick enable generated once every 64 master ticks by the `cencnt[5:0] == 31` comparison.

`rtl/teeter_nmi.v` defines an isolated `exidyTeeterNmi` generator. Its default period is 75,260 master ticks, exactly 600 Hz at the nominal 45.156 MHz board clock. It clears phase and holds NMI inactive during reset or when `teeter_profile` is false. On expiry it asserts active-low NMI and keeps it low until `ph1_enable` is sampled, then releases it. Because the module and T65 sample on the same master-clock edge, nonblocking update semantics ensure T65 observes the low request on its enabled sampling edge before the generator releases it.

The selected T65 implementation is `modules/cpu-t65/T65.vhd`. The edge detector updates on rising `Clk` edges with `Enable='1'` and captures a falling `NMI_n` edge outside the `really_rdy` condition. `NMIAct` is therefore set while paused even though `Rdy` is low; instruction and interrupt-request state progression remains gated by `really_rdy`. The generator needs to stretch the event until a `PH_1` sample. It does not need a second pause-pending queue. The nominal period counter is an integer divider; a fractional accumulator is unnecessary at the nominal 45.156 MHz board clock. If the implementation contract instead requires 600 Hz against the fitted frequency, derive the interval from that selected frequency explicitly.

## Focused verification

Run `make -C sim/teeter_nmi test` in WSL. It runs two intentionally separate fixtures:

- Verilator 5.052 compiles the production `rtl/teeter_nmi.v` directly. It checks disabled-profile inactivity, exact 75,260-tick event spacing, release after a PH_1 sample, async reset inactivity, and reset period restart. The current simulated pulse width is 33 master ticks for the tested phase.
- GHDL 6.0 analyzes and runs the production-selected `modules/cpu-t65/T65.vhd` with its package, ALU, and microcode dependencies against an original synthetic 6502 memory image. It drives `Enable` at the source `PH_1` cadence (one master tick every 64), holds `Rdy` low, and applies an NMI edge long enough to reach an enabled sample. It checks `NMI_ack` latches and the CPU bus address remains stopped, then releases `Rdy` and checks the synthetic NMI vector target is fetched. The test is independent of the Verilog generator test; it does not claim a mixed-language generator-to-T65 co-simulation.

Both checks passed. The Verilator generator test reports a 33-master-tick low pulse for its tested phase and confirms its event period is exactly 75,260 master ticks. The GHDL T65 fixture reaches its explicit PASS marker and stops at 11.246 µs. GHDL reports time-zero metavalue warnings from internal T65 signals before its reset sequence settles. Generated output and logs are under ignored `simulation/harness/` paths.

## Limits before integration

The generator uses nominal 45.156 MHz timing. The current fitted master frequency is slightly offset from that nominal value; decide whether the game contract follows board nominal or fitted physical clock before using the literal divider in production. A future top-level integration must select Teeter's index-1 profile, wire the actual `PH_1`, and ensure the timer is reset/gated with the intended profile lifecycle. The tests establish generator periodicity/hold behavior and independently establish T65's paused-edge retention and resume vectoring. They do not establish the integrated signal path, exact fitted 600 Hz, Teeter firmware behavior, MAME gameplay equivalence, or hardware acceptance.
