`timescale 1ns/1ps
module tb;
  reg clk=0,pe_left=1,pe_right=1,clr=1;
  reg [7:0] pin_left=0,pin_right=0;
  wire link,serial;
  // Same two-stage serial chain and active-low load as Exidy2; gated clock is
  // modeled by issuing clocks only after both loads and when the window opens.
  oLS166 right_half(.clk(clk),.CE(1'b0),.S(1'b0),.pin(pin_right),.PE(pe_right),.clr(clr),.QH(link));
  oLS166 left_half(.clk(clk),.CE(1'b0),.S(link),.pin(pin_left),.PE(pe_left),.clr(clr),.QH(serial));
  reg [7:0] rom[0:2047];
  reg [1023:0] path;
  integer image,row,x,checks=0,negative=0;
  reg expected;
  initial begin
    if(!$value$plusargs("ROM=%s",path)) $fatal(1,"ROM path required");
    if(!$value$plusargs("NEGATIVE=%d",negative)) negative=0;
    $readmemh(path,rom);
    for(image=0;image<64;image++) for(row=0;row<16;row++) begin
      clr=0; #1; clr=1; #1;
      pin_right=rom[image*32+row+16]; pin_left=rom[image*32+row];
      pe_right=0; #1; pe_right=1; pe_left=0; #1; pe_left=1; #1;
      for(x=0;x<16;x++) begin
        expected=rom[image*32+row+(x>=8?16:0)][7-(x%8)];
        if(negative && image==0 && row==0 && x==0) expected=~expected;
        if(serial!==expected) begin
          $display("DIVERGENCE image=%0d row=%0d x=%0d got=%0d expected=%0d",image,row,x,serial,expected);
          $fatal(1,"serializer bit order");
        end
        checks++; clk=1; #1; clk=0; #1;
      end
    end
    // Characterize asynchronous edge-only loading: changing pin while PE low
    // without a clock/PE edge leaves Q unchanged. TI's synchronous load requires
    // a clock instead; unchanged core gates prevent that clock while PE is low.
    pin_left=8'h80; pe_left=0; #1;
    if(serial!==1) $fatal(1,"source asynchronous load");
    pin_left=0; #1;
    if(serial!==1) $fatal(1,"source edge-only hold changed");
    $display("PASS checks=%0d images=64 rows=16 bits=16 source_async_load=1",checks);
    $finish;
  end
endmodule
