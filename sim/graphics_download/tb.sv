`timescale 1ns/1ps
module tb_graphics_download;
 reg master_clock=0; always #10 master_clock=!master_clock;
 reg [10:0] read_addr=0;
 reg [24:0] dn_addr=0; reg [7:0] dn_data=0;
 reg dn_wr=0,ep1_cs_i=0;
 wire [7:0] MVD;
 `include "production_gfx_instance.vh"
 function automatic [7:0] pattern(input integer a,input integer pass);
  pattern=((a*29) ^ (a>>3) ^ (pass*101)) & 255;
 endfunction
 integer pass,a,checks=0,corrupt=0;
 initial if(!$value$plusargs("CORRUPT=%d",corrupt)) corrupt=0;
 initial begin
  // Accepted loader tuples update on the rising edge, including adjacent writes.
  for(pass=0;pass<2;pass++) begin
   for(a=0;a<2048;a++) begin
    @(posedge master_clock);dn_addr<=25'h14000+a;dn_data<=pattern(a,pass);dn_wr<=1;ep1_cs_i<=1;
    if(a%7==0) begin @(posedge master_clock);dn_wr<=0;end
   end
   @(posedge master_clock);dn_wr<=0;ep1_cs_i<=0;
   repeat(2) @(posedge master_clock);
   for(a=0;a<2048;a++) begin
    @(negedge master_clock);read_addr=a;
    @(posedge master_clock);#1;
    if(MVD !== (pattern(a,pass) ^ ((corrupt && a==0 && pass==0) ? 8'h01 : 8'h00))) $fatal(1,"graphics byte mismatch pass=%0d addr=%0d got=%02x expected=%02x",pass,a,MVD,pattern(a,pass));
    checks++;
   end
  end
  $display("PASS actual graphics RAM download/read: checks=%0d consecutive/gapped writes and reload",checks);$finish;
 end
 initial begin #1000000;$fatal(1,"timeout");end
endmodule
