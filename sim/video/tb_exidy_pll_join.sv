`timescale 1ns/1ps
module tb_exidy_pll_join;
 reg reference50=0; always #10 reference50=!reference50;
 wire native_clk,ref_clk,audio_clk,source_locked,output_clk,output_locked;
 pll_0002 source_pll(.refclk(reference50),.rst(1'b0),.outclk_0(native_clk),.outclk_1(ref_clk),.outclk_2(audio_clk),.locked(source_locked));
 wire [63:0] to_pll,from_pll;
 wire cfg_write,cfg_wait,selected,transport_reset,blank;
 wire [5:0] cfg_address; wire [31:0] cfg_data;
 reg request_crt=0,user_reset=0;
 exidy_output_pll output_pll(.refclk(ref_clk),.reset(!source_locked),.clk_output(output_clk),.locked(output_locked),.reconfig_to_pll(to_pll),.reconfig_from_pll(from_pll));
 pll_cfg config_pll(.mgmt_clk(native_clk),.mgmt_reset(!source_locked),.mgmt_read(1'b0),.mgmt_write(cfg_write),.mgmt_address(cfg_address),.mgmt_writedata(cfg_data),.mgmt_readdata(),.mgmt_waitrequest(cfg_wait),.reconfig_to_pll(to_pll),.reconfig_from_pll(from_pll));
 reg [8:0] source_frame_counter=0,output_frame_counter=0;
 always @(posedge native_clk) source_frame_counter<=source_frame_counter+1'b1;
 always @(posedge output_clk) output_frame_counter<=output_frame_counter+1'b1;
 exidy_output_control controller(.clk_sys(native_clk),.clk_output(output_clk),.management_reset(!source_locked),.user_reset(user_reset),.native_locked(source_locked),.output_locked(output_locked),.request_crt(request_crt),.native_frame(source_frame_counter==0),.output_frame(output_frame_counter==0),.cfg_waitrequest(cfg_wait),.cfg_write(cfg_write),.cfg_address(cfg_address),.cfg_writedata(cfg_data),.selected_crt(selected),.transport_reset(transport_reset),.blank_output(blank));
 integer transactions=0,native_edges=0,output_edges=0,native_baseline=0;
 always @(posedge native_clk) begin
  native_edges=native_edges+1;
  if(cfg_write && !cfg_wait) begin
   $display("CFG time=%0t address=%0d data=%08x",$time,cfg_address,cfg_data);transactions++;
  end
 end
 always @(posedge output_clk) output_edges++;
 task measure(input bit crt);
  integer n0,o0,dn,do_; begin
   @(negedge native_clk);n0=native_edges;o0=output_edges;
   #100000;
   dn=native_edges-n0;do_=output_edges-o0;
   $display("RATE crt=%0d native=%0d output=%0d",crt,dn,do_);
   // Vendor model clocks quantize internal VCO periods; fit reports establish
   // physical counters. This checks source stability and the modelled rate join.
   if(!native_baseline) native_baseline=dn;
   if(dn<native_baseline-1 || dn>native_baseline+1) $fatal(1,"native source rate changed");
   if(!crt && (do_<dn-1 || do_>dn+1)) $fatal(1,"Native output frequency incorrect");
   if(crt && (do_*140-dn*131 < -400 || do_*140-dn*131 > 400)) $fatal(1,"CRT output frequency incorrect");
  end
 endtask
 initial begin
  wait(source_locked && output_locked);wait(!blank);
  if(selected) $fatal(1,"startup mode");measure(0);
  request_crt=1;wait(blank);wait(selected && !blank);measure(1);
  user_reset=1;#5000;if(!blank || !selected) $fatal(1,"reset mode retention");
  user_reset=0;wait(!blank);if(!selected) $fatal(1,"reset changed mode");
  request_crt=0;wait(blank);wait(!selected && !blank);measure(0);
  if(transactions!=9) $fatal(1,"expected three M/C/START sequences");
  $display("PASS actual PLL configuration join: Native/CRT/Native, rates, reset retention, transactions=%0d",transactions);$finish;
 end
 initial begin #2000000;$display("TIMEOUT source_locked=%b output_locked=%b state=%0d wait=%b transactions=%0d",source_locked,output_locked,controller.state,cfg_wait,transactions);$fatal(1,"PLL join timeout");end
endmodule
