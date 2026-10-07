# PIA return data/valid reset candidate

This candidate keeps the complete PIA return byte on ordinary clocked data registers and gives reset behavior to a separate valid bit. It is limited to `rtl/pia_return.v` and the focused PIA simulation sources. No top-level wiring, QIP, timing constraints, or production handshake is changed.

## Reset and transfer behavior

The current source/master pipeline first captures the full DDR-masked `audio_DO_bus` on `audio_clk`, then captures that byte on `master_clk`. The destination data register is deliberately not reset. A separate `main_byte_valid` FF clears asynchronously from `master_reset_n` and sets on the first master edge after reset release; `main_byte` is the registered byte masked to zero while valid is clear.

This preserves the visible reset contract: assertion forces `main_byte` to zero without waiting for a master edge; deassertion leaves it zero until the first master edge; that edge simultaneously captures the current source-stage byte and raises valid, so the prior data latency is unchanged. A full old byte may remain internally in the data FF during reset, but the single validity bit hides all eight bits together. Reset release at the validity FF still has recovery/removal timing requirements.

## Timing implications

The earlier full-flow report `simulation/timing-2fafa6b/setup.rpt` showed the eight `audio_byte_stage[*]` to `main_byte[*]` related-clock paths violating setup by up to 0.375 ns. The detailed path's 2.456 ns data delay included a one-LUT reset selection before the destination FF. The latest completed `444211d` fit removed that LUT but still failed by 0.427 ns at the asynchronous destination FF `asdata` path (0.613 ns FF cell delay). This candidate also removes reset from the destination data FF, targeting that remaining pin/cell penalty. With this candidate, the `audio_byte_stage` to `main_byte_data` transfer has no reset mux and remains a normally timed related-clock setup/hold path. There are no false paths, multicycle paths, per-bit synchronizers, or asynchronous clock groups.

The validity mask adds a separate master-domain path: `main_byte_valid` FF Q through the output AND mask and PIA_9B's combinational PA read mux to the main CPU's registered data input when that path is active. This should be reported as a normal master-to-master timing path. It adds a logic level after the data FF and may become the new critical path. TimeQuest must confirm both path classes, valid reset recovery/removal, and the output mask's actual implementation; these simulations cannot establish timing closure.

## Focused tests

`make -C sim/harness pia-return` passed. The GHDL test runs the actual production PIA VHDL pair over seven distinct phases of the 7:22 master/audio ratio, with the same PB/CB2 to PA/CA1 wiring and byte/read protocol. It checks IRQ and earliest modeled T65 read boundaries, whole-byte/partial-DDR results, reset during an outstanding response, and a retained `0x96` byte hidden during async reset and after release until the first master edge. It then confirms that byte reappears on the first clock, proving the one-master-cycle validity rearm has not added a data stage.

The separate Verilator 5.052 test compiles the actual production `rtl/pia_return.v`. It checks whole-byte source/master latency and that a retained `0xE7` data word remains hidden under asynchronous destination reset, remains hidden immediately after release, and is exposed after the first master edge. This is not a mixed-language simulation and does not model PLL jitter, metastability, reset recovery/removal, the full production T65 memory path, game firmware timing, or electrical hardware.
