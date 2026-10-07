# PIA return-byte candidate tests

`tb_pia_return_pair.vhd` exercises the production `modules/pia/pia6821.vhd`
instances with the same cross-coupled PIA handshake lines as `rtl/audio_board.v`.
The bench models the source-audio and destination-master byte registers in
VHDL so the two PIAs can run in one GHDL simulation. It uses a 7 ns master
period and 22 ns audio period (the fitted PLL's 7:22 frequency ratio), with a
coincident positive edge at phase zero; the Makefile sweeps all seven distinct
integer-nanosecond offsets. `tb_pia_return.sv` separately compiles and tests
the actual production Verilog module with Verilator, including independent
source/destination reset behavior.

These are logic/ordering tests. They do not model metastability, PLL jitter,
the T65 internal bus protocol, a game sound CPU program, or physical hardware.
The paired test checks data at IRQ visibility, then begins the read immediately
after the first modeled PH_1/T65 enable and holds it through the next enable.
This separates IRQ visibility from a CPU-legal read boundary; it does not claim
that every game's firmware takes that path.
