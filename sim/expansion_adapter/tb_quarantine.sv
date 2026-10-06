`timescale 1ns/1ps
module tb_quarantine;
  parameter integer READ_LATENCY=2;
  reg clk=0,cvsd_clk=0,remote_running=1;
  always #5 clk=~clk;
  always #37 if(remote_running) cvsd_clk=~cvsd_clk;
  reg reset_n=0,raw_download=0,raw_wr=0;
  reg [15:0] raw_index=6;
  reg [26:0] raw_addr=0;
  reg [7:0] raw_data=0;
  wire cvsd_quarantine_ack,cvsd_ack_generation,quarantine_generation;
  wire ioctl_wait,quarantine_request,transfer_begin,transfer_end,ioctl_wr,adapter_fault,transfer_active;
  wire [7:0] ioctl_index,ioctl_data;
  wire [23:0] ioctl_addr;
  wire read_accept;
  exidy_transport_adapter dut(.*);
  exidy_cvsd_read_quarantine #(.READ_LATENCY(READ_LATENCY)) remote(
    .cvsd_clk(cvsd_clk),.reset_n(reset_n),.quarantine_request(quarantine_request),
    .quarantine_generation(quarantine_generation),.read_request(1'b1),
    .read_accept(read_accept),.quarantine_ack(cvsd_quarantine_ack),.ack_generation(cvsd_ack_generation));
  integer writes=0,reads=0,testcase=0;
  reg old_generation;
  always @(posedge clk) if(reset_n && ioctl_wr) begin
    if(!cvsd_quarantine_ack || cvsd_ack_generation!=quarantine_generation ||
       read_accept || (|remote.outstanding)) $fatal(1,"overwrite before remote drain");
    if(ioctl_addr!=writes || ioctl_index!=6 || ioctl_data!=8'(writes))
      $fatal(1,"speech byte count/order/data mismatch");
    writes++;
  end
  always @(posedge cvsd_clk) if(read_accept) reads++;
  task automatic await_ready;
    integer timeout;
    begin
      timeout=0;
      while(ioctl_wait && timeout<200) begin @(negedge clk); timeout++; end
      if(ioctl_wait) $fatal(1,"fresh acknowledgement timeout");
    end
  endtask
  task automatic begin_stream;
    @(negedge clk); raw_download=1;
    #1; if(!ioctl_wait) $fatal(1,"start did not assert backpressure");
    @(negedge clk);
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",testcase)) testcase=0;
    repeat(5) @(negedge clk); reset_n=1;
    begin_stream(); await_ready();
    // Full overwrite before release, checked byte-for-byte by the monitor.
    for(integer i=0;i<16384;i++) begin
      raw_wr=1; raw_addr=27'(i); raw_data=8'(i);
      @(negedge clk); raw_wr=0; @(negedge clk);
    end
    raw_download=0; repeat(8) @(negedge clk);
    if(quarantine_request || writes!=16384 || adapter_fault || transfer_active)
      $fatal(1,"first full stream failed");
    if(testcase==1) begin
      // Exercise accepted reads/outstanding pipeline before a new revoke.
      repeat(8) @(negedge cvsd_clk);
      if(reads==0 || !(|remote.outstanding)) $fatal(1,"no outstanding read stimulus");
    end else if(!cvsd_quarantine_ack) $fatal(1,"stale-high stimulus missed");
    @(negedge cvsd_clk); remote_running=0;
    old_generation=cvsd_ack_generation; writes=0;
    begin_stream();
    if(testcase==2) begin
      // No pending byte: stop can retire while revocation is unacknowledged.
      raw_download=0; repeat(8) @(negedge clk);
      if(transfer_active) $fatal(1,"empty abort did not retire");
      begin_stream();
      if(quarantine_generation==old_generation)
        $fatal(1,"abort restart cancelled pending generation");
    end
    raw_wr=1; raw_addr=0; raw_data=0;
    @(negedge clk); raw_wr=0;
    repeat(25) @(negedge clk);
    if(writes!=0 || !ioctl_wait || quarantine_generation==old_generation)
      $fatal(1,"stopped remote clock permits overwrite");
    if(testcase==3) begin
      // Shared asynchronous reset must clear a blocked byte even when the
      // remote clock is stopped, and keep remote reads blocked on restart.
      #2; reset_n=0; raw_download=0; #1;
      if(ioctl_wr || read_accept || dut.pending_valid || transfer_active ||
         !quarantine_request || (|remote.outstanding))
        $fatal(1,"shared reset did not quarantine pending session");
      repeat(3) @(negedge clk); reset_n=1;
      repeat(3) @(negedge clk);
      if(writes!=0 || read_accept || adapter_fault) $fatal(1,"reset leaked pending byte/read");
      begin_stream(); raw_wr=1; raw_addr=0; raw_data=0;
      @(negedge clk); raw_wr=0;
    end
    remote_running=1; await_ready(); repeat(3) @(negedge clk);
    if(writes!=1 || adapter_fault || dut.pending_valid)
      $fatal(1,"held byte did not drain exactly once");
    if(testcase==4) begin
      // Width truncation must not alias address 0x1000001 to address 1.
      raw_wr=1; raw_addr=27'h1000001; raw_data=1;
      @(negedge clk); raw_wr=0; repeat(3) @(negedge clk);
      if(!adapter_fault || writes!=1 || !quarantine_request)
        $fatal(1,"upper address aliased or failed to fault");
      raw_wr=1; raw_addr=1; raw_data=1;
      @(negedge clk); raw_wr=0; raw_download=0;
      repeat(10) @(negedge clk);
      if(writes!=1 || transfer_active || !quarantine_request)
        $fatal(1,"faulted session forwarded later byte");
      begin_stream(); raw_wr=1; raw_addr=0; raw_data=0;
      @(negedge clk); raw_wr=0; repeat(4) @(negedge clk);
      if(writes!=1 || transfer_active || dut.pending_valid)
        $fatal(1,"faulted restart accepted a transaction");
      $display("PASS fault_and_upper_address writes=1 restart_rejected=1");
      $finish;
    end
    for(integer i=1;i<16384;i++) begin
      raw_wr=1; raw_addr=27'(i); raw_data=8'(i);
      @(negedge clk); raw_wr=0; @(negedge clk);
    end
    raw_download=0; repeat(8) @(negedge clk);
    if(writes!=16384 || adapter_fault || transfer_active || quarantine_request)
      $fatal(1,"second full stream failed");
    $display("PASS remote_case=%0d latency=%0d second_writes=%0d reads=%0d",testcase,READ_LATENCY,writes,reads);
    $finish;
  end
  initial begin #2000000; $fatal(1,"watchdog timeout"); end
endmodule
