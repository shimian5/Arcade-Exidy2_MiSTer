# PIA return-register candidate

Date: 2026-10-07. This candidate registers the complete DDR-masked audio PIA_8B PB byte once on `audio_clk`, then once on related `master_clock`, before main PIA_9B PA input. The cross-coupled CA/CB handshake wires are unchanged. The audio-to-source-register and source-register-to-master-register paths remain normally timed; no SDC exception or per-bit synchronizer was added. It adds one audio-clock period (about 69.6 ns in the current STA model) plus one master-clock period (about 22.1 ns).

## Implementation

`rtl/pia_return.v` defines `exidyPiaReturn`: on each audio rising edge it samples the full already-DDR-masked `audio_DO_bus`, clearing its source stage while `RESET_n_au` is low; on each master rising edge it samples that complete byte. The destination `main_byte` register now uses an asynchronous active-low reset, matching the directly connected PIA_9B's asynchronous active-high reset. This removes the synchronous reset selection from the destination D input and allows the fitter to use the FF's dedicated clear input. `rtl/audio_board.v` feeds the output only to PIA_9B `pa_i`; PIA_8B `pb_o`, the PIA 9B bus mux, and CA/CB handshake wires are otherwise unchanged. `rtl/index.qip` includes the module.

The fresh full-flow report `simulation/timing-2fafa6b/setup.rpt` has eight negative paths from `audio_byte_stage[*]` to `main_byte[*]`, worst slack -0.375 ns. Its worst data delay is 2.456 ns across one LUT level, consistent with the destination reset mux in the prior RTL; the related output clocks have a 3.150 ns setup relationship and -0.739 ns skew. The asynchronous-reset change is intended to remove that D-input mux while preserving the whole-byte setup/hold path; only a new full-flow report can confirm the fitted implementation. Reset assertion now clears the destination register without waiting for `master_clk`, matching the PIA's behavior. Reset release does not alter the register until the next master edge. Since the core feeds `RESET_n` directly to the asynchronous reset pins of both the PIA and return register, release recovery/removal remains a system reset requirement and must be inspected in the next full-flow timing reports.

## Test source and coverage

`sim/pia_return/tb_pia_return_pair.vhd` instantiates two production `modules/pia/pia6821.vhd` entities with the cross-wiring in `audio_board.v`. It models both byte stages in VHDL and pairs them with a top-level-style continuously registered CPU data bus and a PH_1 sample every 64 master clocks. The master clock has a positive edge at time zero; the seven audio offsets therefore include coincident positive edges and all distinct integer-nanosecond offsets within the 7 ns master period. Its cases are:

- seven relative phase offsets for the fitted 7:22 master/audio clock period ratio;
- PIA_8B PB DDR/data write with CB2 handshake and PIA_9B CA1 IRQ / PA-read CA2 handshake;
- reads immediately after main-side IRQ visibility and at the first modeled T65 PH_1 sample, checking the PIA read mux and registered main CPU bus;
- multi-bit patterns (`00`, `FF`, `A5`, `5A`, `96`), partial PB DDR (`0F`) with undriven input bits tied low, and reset during a pending response;
- response stability through read/ack and a successful post-reset exchange;
- audio-stage reset in its audio domain; asynchronous destination reset assertion between master edges and release followed by a later master-edge capture.

The paired bench has a 100 µs failure watchdog, and the Makefile requires its
per-phase `PASS` marker as well as a zero simulator exit code.

`sim/pia_return/tb_pia_return.sv` separately exercises the actual production Verilog module for both-stage latency, whole-byte capture, source reset propagation, destination-only reset behavior, and clearing both stages. Run both parts with `make -C sim/harness pia-return`; generated logs and simulator outputs go under ignored `simulation/harness/`.

## Validation status and limits

`make -C sim/harness pia-return` passed after the asynchronous destination-reset update. GHDL reported the paired production-PIA test's explicit PASS marker for all seven phase offsets (0 through 6 ns); each case completed at 5.1575 µs, below the 100 µs watchdog. The test covered all listed byte patterns, the partial-DDR expected value `0x05`, reset during an outstanding response, asynchronous destination reset assertion without a master edge, and a successful post-reset exchange. The Verilator 5.052 test of the actual Verilog module passed its two-stage latency, whole-byte capture, source reset propagation, and asynchronous destination reset/release assertions. No stale-byte or protocol-loss assertion fired. The Makefile checks both simulator exit status and the per-phase PASS marker.

The first fixture draft exposed an invalid test boundary: asserting PIA read CS immediately when the interrupt pin changed created an acknowledge before the modeled T65 could issue a bus cycle. The fixture now separates IRQ visibility from the earliest PH_1-driven read request and holds the read for a CPU interval. This reflects the actual 64-master-tick T65 enable and keeps the assertion strict at that first modeled CPU read; it does not claim that every game's firmware follows that schedule.

Even a pass proves only simulated RTL ordering at the tested ideal phases. It does not model metastability, PLL jitter, the production T65 internal bus behavior in full, game firmware's actual read timing, or electrical hardware. The asynchronous reset may trade the D-path mux for recovery/removal checks; the next full-flow TimeQuest run must confirm the reset implementation, setup/hold closure on the timed byte path, and no new critical reset paths. No byte false path, multicycle, or asynchronous clock grouping is proposed. Hardware and game-level acceptance remain separate.

Integrator review corrected the modeled CPU observation to latch the **previous** registered data bus on PH_1, matching T65's edge sampling rather than checking the data bus after its same-edge update. All seven phases and the actual Verilog module test still pass after both source and destination stages were added. The pipeline adds about 92 ns total in the current timing model; the paired fixture verifies the tested PIA handshake/read boundary but does not prove every game's firmware hold time, active reads outside that handshake, or physical CDC behavior. This is a timed pipeline, not an asynchronous bus synchronizer or a complete firmware-coherence proof.
