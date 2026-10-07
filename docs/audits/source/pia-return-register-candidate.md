# PIA return-register candidate

Date: 2026-10-07. This candidate inserts a whole-byte, one-`master_clock` staging register between audio PIA_8B PB output and main PIA_9B PA input. The cross-coupled CA/CB handshake wires are unchanged. The new audio-to-master path remains normally timed; no SDC exception or per-bit synchronizer was added.

## Implementation

`rtl/pia_return.v` defines `exidyPiaReturn`: on each master rising edge it samples all eight audio bits together and synchronously clears to zero while `RESET_n` is low. `rtl/audio_board.v` feeds its output only to PIA_9B `pa_i`; PIA_8B `pb_o`, PIA 9B bus mux, and CA/CB handshakes remain otherwise as before. `rtl/index.qip` includes the module.

## Test source and coverage

`sim/pia_return/tb_pia_return_pair.vhd` instantiates two production `modules/pia/pia6821.vhd` entities with the cross-wiring in `audio_board.v`. It models the new one-edge register in VHDL and pairs it with a top-level-style continuously registered CPU data bus and a PH_1 sample every 64 master clocks. The master clock has a positive edge at time zero; the seven audio offsets therefore include coincident positive edges and all distinct integer-nanosecond offsets within the 7 ns master period. Its cases are:

- seven relative phase offsets for the fitted 7:22 master/audio clock period ratio;
- PIA_8B PB DDR/data write with CB2 handshake and PIA_9B CA1 IRQ / PA-read CA2 handshake;
- reads immediately after main-side IRQ visibility and at the first modeled T65 PH_1 sample, checking the PIA read mux and registered main CPU bus;
- multi-bit patterns (`00`, `FF`, `A5`, `5A`, `96`), partial PB DDR (`0F`) with undriven input bits tied low, and reset during a pending response;
- response stability through read/ack and a successful post-reset exchange.

The paired bench has a 100 µs failure watchdog, and the Makefile requires its
per-phase `PASS` marker as well as a zero simulator exit code.

`sim/pia_return/tb_pia_return.sv` separately exercises the actual production Verilog register for one-cycle latency, whole-byte capture, and reset clearing. Run both parts with `make -C sim/harness pia-return`; generated logs and simulator outputs go under ignored `simulation/harness/`.

## Validation status and limits

`make -C sim/harness pia-return` passed on 2026-10-07. GHDL reported the paired production-PIA test's explicit PASS marker for all seven phase offsets (0 through 6 ns); each case completed at 5.1575 µs, below the 100 µs watchdog. The test covered all listed byte patterns, the partial-DDR expected value `0x05`, reset during an outstanding response, and a successful post-reset exchange. The Verilator 5.052 test of the actual Verilog register passed its reset, whole-byte capture, and one-cycle latency assertions. No stale-byte or protocol-loss assertion fired. `git diff --check` is clean.

The first fixture draft exposed an invalid test boundary: asserting PIA read CS immediately when the interrupt pin changed created an acknowledge before the modeled T65 could issue a bus cycle. The fixture now separates IRQ visibility from the earliest PH_1-driven read request and holds the read for a CPU interval. This reflects the actual 64-master-tick T65 enable and keeps the assertion strict at that first modeled CPU read; it does not claim that every game's firmware follows that schedule.

Even a pass proves only simulated RTL ordering at the tested ideal phases. It does not model metastability, PLL jitter, the production T65 internal bus behavior in full, game firmware's actual read timing, or electrical hardware. Fresh full-flow TimeQuest must still show setup/hold closure to the new register and preserve the related-clock paths; hardware and game-level acceptance remain separate.

Integrator review corrected the modeled CPU observation to latch the **previous** registered data bus on PH_1, matching T65's edge sampling rather than checking the data bus after its same-edge update. All seven phases and the actual Verilog register test still pass after this correction. The source register adds one master cycle of input latency; already-active reads, non-handshake firmware polling and actual per-game hold times remain unproved. This candidate is a timed pipeline, not an asynchronous bus synchronizer or a complete firmware-coherence proof.
