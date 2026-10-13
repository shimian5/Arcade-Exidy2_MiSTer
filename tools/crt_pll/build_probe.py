#!/usr/bin/env python3
"""Create an ignored full-flow exact-ratio cascaded PLL probe; run Quartus in its directory."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
out=ROOT/'simulation/crt_pll/probe'
out.mkdir(parents=True,exist_ok=True)
(out/'probe.sv').write_text('''module probe(input wire FPGA_CLK1_50, output wire [31:0] observed);
wire native_clk, ref_clk, audio_clk, crt_clk, locked, source_locked;
pll_0002 source_pll(.refclk(FPGA_CLK1_50),.rst(1'b0),.outclk_0(native_clk),.outclk_1(ref_clk),.outclk_2(audio_clk),.locked(source_locked));
exidy_crt_output_pll output_pll(.refclk(ref_clk),.reset(!source_locked),.clk_output(crt_clk),.locked(locked));
reg [15:0] n=0,c=0;
always @(posedge native_clk) n<=n+1'b1;
always @(posedge crt_clk) c<=c+1'b1;
assign observed={n,c} ^ {32{locked}};
endmodule
''')
qsf=['set_global_assignment -name FAMILY "Cyclone V"','set_global_assignment -name DEVICE 5CSEBA6U23I7','set_global_assignment -name TOP_LEVEL_ENTITY probe','set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files','set_global_assignment -name NUM_PARALLEL_PROCESSORS 2','set_global_assignment -name SYSTEMVERILOG_FILE probe.sv',f'set_global_assignment -name QIP_FILE "{(ROOT/"rtl/pll.qip").as_posix()}"',f'set_global_assignment -name SYSTEMVERILOG_FILE "{(ROOT/"candidates/video/exidy_crt_output_pll.sv").as_posix()}"','set_global_assignment -name SDC_FILE probe.sdc','set_location_assignment PIN_V11 -to FPGA_CLK1_50','set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to FPGA_CLK1_50','set_instance_assignment -name VIRTUAL_PIN ON -to observed[*]']
(out/'probe.qsf').write_text('\n'.join(qsf)+'\n')
(out/'probe.qpf').write_text('PROJECT_REVISION = "probe"\n')
(out/'probe.sdc').write_text('create_clock -name FPGA_CLK1_50 -period 20.000 [get_ports FPGA_CLK1_50]\nderive_pll_clocks\nderive_clock_uncertainty\n')
print(out)
