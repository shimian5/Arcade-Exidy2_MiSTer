`timescale 1ns/1ps
// Bridge-level reset release with the speech clock stopped (increment 15).
module tb_bridge_reset;
  reg clk=0,cvsd_clk=0,cvsd_run=1,reset_n=0;
  always #5 clk=~clk;
  always #37 if(cvsd_run) cvsd_clk=~cvsd_clk;
  wire [7:0] question_data,cvsd_data,active_profile,ioctl_index,ioctl_data;
  wire [23:0] ioctl_addr;
  wire question_valid,cvsd_valid,ioctl_wait,legacy_base_wr,reset_hold,expansion_ready;
  wire adapter_fault,protocol_fault,ioctl_wr,transfer_begin,transfer_end,transfer_active;
  wire quarantine_request,quarantine_generation,read_accept,cvsd_quarantine_ack,cvsd_ack_generation;
  integer errors=0;
  task automatic check(input bit c,input string m); if(!c) begin errors++; $display("FAIL: %s @%0t",m,$time); end endtask
  exidy_expansion_bridge_rr bridge(.clk,.reset_n,.cvsd_clk,.raw_download(1'b0),.raw_wr(1'b0),.raw_index(16'd0),
    .raw_addr(27'd0),.raw_data(8'd0),.question_read(1'b0),.question_bank(5'd0),.question_cpu_addr(16'd0),
    .cvsd_read(1'b1),.cvsd_addr(14'd0),.*);
  initial begin
    // Idle after reset with clocks running: core released, no reads, no faults.
    repeat(6) @(negedge clk); reset_n=1; repeat(8) @(negedge clk);
    check(!reset_hold,"reset_hold stuck after release");
    check(!adapter_fault && !protocol_fault,"fault after idle release");
    // Stop the speech clock, pulse reset, release while stopped.
    cvsd_run=0; #20; reset_n=0; #1;
    check(reset_hold,"reset_hold not asserted on async reset");
    check(!bridge.reset_n_cvsd,"speech reset needs a clock to assert");
    #50 reset_n=1; repeat(8) @(negedge clk);
    check(!reset_hold,"main domain should release without the speech clock");
    check(!bridge.reset_n_cvsd,"speech reset released with no speech clock");
    check(!cvsd_valid && !read_accept,"speech read active while speech domain in reset");
    // Restart the speech clock: exactly two edges to release.
    cvsd_run=1; @(posedge cvsd_clk); #1; check(!bridge.reset_n_cvsd,"speech released after 1 edge");
    @(posedge cvsd_clk); #1; check(bridge.reset_n_cvsd,"speech not released after 2 edges");
    check(!cvsd_valid,"spurious cvsd_valid after release");
    if(errors==0) $display("PASS bridge reset adversaries"); else $display("FAILED %0d",errors);
    $finish;
  end
endmodule
