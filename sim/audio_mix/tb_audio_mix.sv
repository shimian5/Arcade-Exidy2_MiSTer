`timescale 1ns/1ps
module tb_audio_mix;
  reg signed [15:0] a=0,b=0; reg mute=0; wire signed [15:0] m;
  exidyAudioMix dut(.src_a(a),.src_b(b),.mute(mute),.mono(m));
  integer errors=0, i;
  task automatic check(input signed [15:0] ea, input signed [15:0] eb, input bit mu);
    integer want;
    begin
      a=ea; b=eb; mute=mu; #1;
      want = mu ? 0 : ((ea>>>1)+(eb>>>1));
      if (m!==want[15:0]) begin errors++; $display("FAIL a=%0d b=%0d mute=%0d got=%0d want=%0d",ea,eb,mu,m,want); end
    end
  endtask
  initial begin
    check(0,0,0); check(1000,0,0); check(0,1000,0); check(1000,-1000,0);
    check(16'sh7fff,16'sh7fff,0); check(-16'sh8000,-16'sh8000,0);
    check(16'sh7fff,-16'sh8000,0); check(5,7,1);
    // Each source alone must be audible in the mono result (the baseline bug).
    a=2000; b=0; mute=0; #1; if (m==0) begin errors++; $display("FAIL source A silent"); end
    a=0; b=2000; #1; if (m==0) begin errors++; $display("FAIL source B silent"); end
    for (i=0;i<2000;i++) check($random, $random, 0);
    if (errors==0) $display("PASS audio mix"); else $display("FAILED %0d",errors);
    $finish;
  end
endmodule
