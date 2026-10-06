`timescale 1ns/1ps
// Isolated transport regressions; full HPS/loader integration remains open.
module tb_review;
  reg clk=0;
  always #5 clk=~clk;
  reg reset_n=0,raw_download=0,raw_wr=0,cvsd_quarantine_ack=0;
  reg cvsd_ack_generation=0;
  wire quarantine_generation;
  reg [15:0] raw_index=0;
  reg [26:0] raw_addr=0;
  reg [7:0] raw_data=0;
  wire ioctl_wait,quarantine_request,transfer_begin,transfer_end,ioctl_wr,adapter_fault,transfer_active;
  wire [7:0] ioctl_index,ioctl_data;
  wire [23:0] ioctl_addr;
  exidy_transport_adapter dut(.*);
  integer testcase=0,writes=0,last_index=-1,begins=0;
  reg [23:0] observed_addr[0:7];
  reg [7:0] observed_data[0:7],observed_index[0:7];
  reg [7:0] expected_data[0:5];
  always @(posedge clk) begin
    if(ioctl_wr) begin
      if(writes<8) begin
        observed_addr[writes]=ioctl_addr; observed_data[writes]=ioctl_data;
        observed_index[writes]=ioctl_index;
      end
      writes++;
    end
    if(transfer_begin) begin last_index=ioctl_index; begins++; end
  end
  task automatic start(input integer idx);
    @(negedge clk); raw_index=16'(idx); raw_download=1;
    @(negedge clk);
  endtask
  task automatic check_begin(input integer idx);
    start(idx);
    if(!transfer_begin || ioctl_index!=idx) $fatal(1,"begin index not latched");
    @(negedge clk);
    if(last_index!=idx) $fatal(1,"downstream sampled stale begin index");
    raw_download=0;
    repeat(7) @(negedge clk);
    if(transfer_active) $fatal(1,"transfer did not end");
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",testcase)) testcase=0;
    repeat(3) @(negedge clk); reset_n=1;
    if(testcase==0) begin
      check_begin(0); check_begin(7); check_begin(6);
      if(begins!=3 || adapter_fault) $fatal(1,"valid index transitions failed");
      $display("BEGIN_PASS transitions=3 indices=0,7,6 downstream_index=%0d",last_index);
    end else if(testcase==1) begin
      // Six distinct bytes: start+write, consecutive arrivals during dequeue,
      // a last byte on stop, and one delayed raw write while end is pending.
      expected_data[0]=8'haa; expected_data[1]=8'hbb; expected_data[2]=8'hcc;
      expected_data[3]=8'hdd; expected_data[4]=8'hee; expected_data[5]=8'hff;
      @(negedge clk); raw_index=0; raw_download=1; raw_wr=1; raw_addr=0; raw_data=8'haa;
      @(negedge clk); raw_addr=1; raw_data=8'hbb;
      @(negedge clk); raw_addr=2; raw_data=8'hcc;
      @(negedge clk); raw_addr=3; raw_data=8'hdd;
      @(negedge clk); raw_download=0; raw_addr=4; raw_data=8'hee;
      @(negedge clk); raw_addr=5; raw_data=8'hff;
      @(negedge clk); raw_wr=0;
      repeat(8) @(negedge clk);
      if(writes!=6 || adapter_fault || transfer_active || dut.pending_valid)
        $fatal(1,"skid stream did not drain exactly six bytes");
      for(integer i=0;i<6;i++)
        if(observed_addr[i]!=i || observed_data[i]!==expected_data[i] || observed_index[i]!=0)
          $fatal(1,"skid stream byte order/data/index mismatch at %0d",i);
      $display("SKID_PASS writes=6 addresses=0..5 data=aa,bb,cc,dd,ee,ff");
    end else if(testcase==2) begin
      // Acknowledge boot quarantine; release only after a complete stream.
      cvsd_quarantine_ack=1; repeat(4) @(negedge clk); start(6);
      cvsd_ack_generation=quarantine_generation;
      repeat(4) @(negedge clk);
      for(integer i=0;i<16384;i++) begin
        raw_wr=1; raw_addr=27'(i); raw_data=8'(i);
        @(negedge clk); raw_wr=0; @(negedge clk);
      end
      raw_download=0; repeat(6) @(negedge clk);
      if(quarantine_request) $fatal(1,"valid completion did not release quarantine");
      // Remote clock may be stopped, so old acknowledgement stays high.
      writes=0; start(6); raw_wr=1; raw_addr=0; raw_data=8'hcc;
      @(negedge clk); raw_wr=0; repeat(3) @(negedge clk);
      $display("STALE_ACK writes=%0d wait=%0d expectedWrites=0",writes,ioctl_wait);
      if(writes!=0 || !ioctl_wait) $fatal(1,"stale acknowledgement permits overwrite");
    end else if(testcase==3) begin
      // Reject a 16-bit index whose low byte aliases index 6, including a
      // first byte concurrent with start. It must never create a transaction.
      @(negedge clk); raw_index=16'h0106; raw_download=1; raw_wr=1; raw_addr=0; raw_data=8'hcc;
      @(negedge clk); raw_wr=0;
      repeat(5) @(negedge clk);
      if(!adapter_fault || transfer_active || begins!=0 || writes!=0 || dut.pending_valid)
        $fatal(1,"upper index bits aliased or leaked first byte");
      $display("INDEX_REJECT_PASS index=0106 begins=%0d writes=%0d",begins,writes);
    end else begin
      // A full skid entry cannot absorb another byte while speech writes are
      // quarantined. Flag overflow, then discard the faulted pending byte.
      @(negedge clk); raw_index=6; raw_download=1; raw_wr=1; raw_addr=0; raw_data=8'haa;
      @(negedge clk); raw_addr=1; raw_data=8'hbb;
      @(negedge clk); raw_wr=0;
      repeat(3) @(negedge clk);
      if(!adapter_fault || writes!=0 || dut.pending_valid || !ioctl_wait)
        $fatal(1,"blocked skid overflow did not close faulted session");
      cvsd_quarantine_ack=1; cvsd_ack_generation=quarantine_generation;
      repeat(6) @(negedge clk);
      if(writes!=0 || dut.pending_valid || !quarantine_request)
        $fatal(1,"faulted skid replayed after acknowledgement");
      $display("OVERFLOW_PASS fault=1 writes=0 pending_discarded=1");
    end
    $display("PASS"); $finish;
  end
endmodule
