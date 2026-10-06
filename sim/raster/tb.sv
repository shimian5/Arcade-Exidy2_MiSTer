`timescale 1ns/1ps
module tb;
reg master_clock=0;
reg [7:0] shift;
wire pixel,hs,vs,hb,vb;
integer n=0;
integer max_samples=250000;
integer master_cycles=0;
exidy_raster dut(master_clock,shift,pixel,hs,vs,hb,vb);
always #1 master_clock=~master_clock;
always @(posedge master_clock) master_cycles<=master_cycles+1;
initial begin
 if (!$value$plusargs("SHIFT=%d",shift)) shift=8'h37;
 if (!$value$plusargs("SAMPLES=%d",max_samples)) max_samples=250000;
 $display("master_cycle,pixel_index,hscnt,hspcnt,vscnt,vl1,hs,vs,hb,vb");
 while(n<max_samples) begin
   @(posedge pixel); #0.1;
   $display("%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",master_cycles,n,dut.hscnt,dut.hspcnt,dut.vscnt,dut.VL1,hs,vs,hb,vb);
   n=n+1;
 end
 $finish;
end
endmodule
