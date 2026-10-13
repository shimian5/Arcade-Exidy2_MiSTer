#!/usr/bin/env python3
"""Generate full-flow PLL/controller probes for both initial counter configurations."""
from pathlib import Path
import argparse
ROOT=Path(__file__).resolve().parents[2]
a=argparse.ArgumentParser();a.add_argument('--initial-crt',type=int,choices=(0,1),default=0);a.add_argument('--framework-hooks',action='store_true');a=a.parse_args()
label='reconfig-hooks' if a.framework_hooks else 'reconfig';out=ROOT/f'simulation/crt_pll/{label}-{a.initial_crt}';out.mkdir(parents=True,exist_ok=True)
(out/'probe.sv').write_text(f"""module probe(input wire FPGA_CLK1_50, output wire [31:0] observed);
wire native_clk,ref_clk,audio_clk,output_clk,source_locked,output_locked;
pll_0002 source_pll(.refclk(FPGA_CLK1_50),.rst(1'b0),.outclk_0(native_clk),.outclk_1(ref_clk),.outclk_2(audio_clk),.locked(source_locked));
wire [63:0] to_pll,from_pll; wire write_cfg,wait_cfg;
wire [5:0] address; wire [31:0] data; wire selected,hold_transport,blank;
exidy_output_pll #(.INITIAL_CRT({a.initial_crt})) output_pll(.refclk(ref_clk),.reset(!source_locked),.reconfig_to_pll(to_pll),.reconfig_from_pll(from_pll),.clk_output(output_clk),.locked(output_locked));
pll_cfg config_pll(.mgmt_clk(native_clk),.mgmt_reset(!source_locked),.mgmt_read(1'b0),.mgmt_write(write_cfg),.mgmt_address(address),.mgmt_writedata(data),.mgmt_readdata(),.mgmt_waitrequest(wait_cfg),.reconfig_to_pll(to_pll),.reconfig_from_pll(from_pll));
reg [15:0] n=0,c=0;
always @(posedge native_clk) n<=n+1'b1;
always @(posedge output_clk) c<=c+1'b1;
exidy_output_control controller(.clk_sys(native_clk),.clk_output(output_clk),.management_reset(!source_locked),.user_reset(1'b0),.native_locked(source_locked),.output_locked(output_locked),.request_crt(n[15]),.native_frame(n==0),.output_frame(c==0),.cfg_waitrequest(wait_cfg),.cfg_write(write_cfg),.cfg_address(address),.cfg_writedata(data),.selected_crt(selected),.transport_reset(hold_transport),.blank_output(blank));
assign observed={{n,c}} ^ {{32{{selected^hold_transport^blank}}}};
endmodule
""")
if a.framework_hooks:
 text=(out/'probe.sv').read_text().replace('FPGA_CLK1_50','FPGA_CLK2_50')
 hooks="""wire hdmi_clk,hdmi_tx_clk,vga_tx_clk;
pll_hdmi hdmi_pll(.refclk(FPGA_CLK2_50),.rst(1'b0),.outclk_0(hdmi_clk),.reconfig_to_pll(64'd0),.reconfig_from_pll());
cyclonev_clkselect hdmi_clk_sw(.clkselect({1'b1,n[13]}),.inclk({output_clk,hdmi_clk,2'b00}),.outclk(hdmi_tx_clk));
cyclonev_clkselect vga_clk_sw(.clkselect({1'b1,n[14]}),.inclk({output_clk,hdmi_clk,2'b00}),.outclk(vga_tx_clk));
reg [3:0] hd=0,vg=0;
always @(posedge hdmi_tx_clk) hd<=hd+1'b1;
always @(posedge vga_tx_clk) vg<=vg+1'b1;
"""
 text=text.replace('assign observed=',hooks+'assign observed=').replace(' ^ {32{selected^hold_transport^blank}}'," ^ {32{selected^hold_transport^blank}} ^ {24'd0,hd,vg}")
 (out/'probe.sv').write_text(text)
qsf=['set_global_assignment -name FAMILY "Cyclone V"','set_global_assignment -name DEVICE 5CSEBA6U23I7','set_global_assignment -name TOP_LEVEL_ENTITY probe','set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files','set_global_assignment -name NUM_PARALLEL_PROCESSORS 2','set_global_assignment -name SYSTEMVERILOG_FILE probe.sv']
for f in (('rtl/pll.qip','sys/pll_cfg.qip','sys/pll_hdmi.qip') if a.framework_hooks else ('rtl/pll.qip','sys/pll_cfg.qip')):qsf.append(f'set_global_assignment -name QIP_FILE "{(ROOT/f).as_posix()}"')
for f in ('candidates/video/exidy_output_pll.sv','candidates/video/exidy_output_control.sv'):qsf.append(f'set_global_assignment -name SYSTEMVERILOG_FILE "{(ROOT/f).as_posix()}"')
qsf+=['set_global_assignment -name SDC_FILE probe.sdc',f'set_global_assignment -name SDC_FILE "{(ROOT/"candidates/video/exidy_output_control.sdc").as_posix()}"','set_location_assignment PIN_V11 -to FPGA_CLK1_50','set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to FPGA_CLK1_50','set_instance_assignment -name VIRTUAL_PIN ON -to observed[*]']
(out/'probe.qsf').write_text('\n'.join(qsf)+'\n');(out/'probe.qpf').write_text('PROJECT_REVISION = "probe"\n')
(out/'probe.sdc').write_text('create_clock -name FPGA_CLK1_50 -period 20.000 [get_ports FPGA_CLK1_50]\nderive_pll_clocks\nderive_clock_uncertainty\n')
if a.framework_hooks:
 qsf_text=(out/'probe.qsf').read_text().replace('PIN_V11','PIN_Y13').replace('FPGA_CLK1_50','FPGA_CLK2_50');(out/'probe.qsf').write_text(qsf_text)
 sdc=(out/'probe.sdc').read_text().replace('FPGA_CLK1_50','FPGA_CLK2_50');(out/'probe.sdc').write_text(sdc)
print(out)
