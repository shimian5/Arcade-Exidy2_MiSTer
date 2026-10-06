`timescale 1ns/1ps
module tb_reset_sync;
  reg clk=0, reset_n=0; wire q; integer errors=0, i;
  always #35 clk=~clk;                       // 14.3 MHz-like
  exidyResetSync dut(.clk,.reset_n,.reset_n_sync(q));
  task automatic check(input bit c,input string m); if(!c) begin errors++; $display("FAIL %s @%0t",m,$time); end endtask
  initial begin
    check(q===0,"power-up not in reset");
    repeat(4) @(posedge clk); check(q===0,"released while source in reset");
    @(negedge clk); reset_n=1;                 // release: exactly two edges
    @(posedge clk); #1; check(q===0,"released after 1 edge");
    @(posedge clk); #1; check(q===1,"not released after 2 edges");
    @(negedge clk); reset_n=0;                 // assert: exactly two edges
    @(posedge clk); #1; check(q===1,"asserted after 1 edge");
    @(posedge clk); #1; check(q===0,"not asserted after 2 edges");
    // source glitch shorter than a clock period that spans no edge is ignored; one spanning an edge resets
    @(negedge clk); reset_n=1; repeat(4) @(posedge clk); #1; check(q===1,"setup release");
    @(negedge clk); reset_n=0; @(posedge clk); reset_n=1; repeat(4) @(posedge clk); #1;
    check(q===1,"one-edge glitch should pass as a 1-cycle reset then release");
    // output changes only at rising clk edges
    for (i=0;i<5;i++) begin end
    if (errors==0) $display("PASS reset sync"); else $display("FAILED %0d",errors);
    $finish;
  end
  time last=0; always @(posedge clk) last=$time;
  always @(q) if ($time>0 && $time!=last) begin errors++; $display("FAIL output changed off a clock edge @%0t",$time); end
endmodule
