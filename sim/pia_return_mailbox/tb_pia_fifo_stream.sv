`timescale 1ns/1ps
// Saturated source traffic: every observed source tuple must arrive in order.
module tb_pia_fifo_stream;
  parameter integer PHASE_NS = 0;
  parameter integer SHIFT_PS = 0;
  reg master_clk=0, audio_clk=0, reset_n=0;
  reg [7:0] audio_byte=0;
  reg audio_notify=0;
  wire [7:0] main_byte;
  wire main_notify, overflow;
  integer received=0, sent=0;
  reg [7:0] last_byte=0;
  reg check_notification=0, expected_notification=0;
`ifdef PIA_PRODUCTION
  exidyPiaReturn dut(.audio_clk(audio_clk),.master_clk(master_clk),
`else
  exidyPiaReturnFifo dut(.audio_clk(audio_clk),.master_clk(master_clk),
`endif
    .audio_reset_n(reset_n),.master_reset_n(reset_n),.audio_byte(audio_byte),
    .audio_notify(audio_notify),.main_byte(main_byte),.main_notify(main_notify),
    .overflow(overflow));
  always #3.5 master_clk=~master_clk;
  initial begin #(PHASE_NS + SHIFT_PS/1000.0); forever #11 audio_clk=~audio_clk; end
  always @(posedge master_clk) begin
    #0.1;
    if (reset_n) begin
      if (overflow) $fatal(1,"overflow at phase %0d sent=%0d received=%0d",PHASE_NS,sent,received);
      if (check_notification && main_notify !== expected_notification)
        $fatal(1,"notification ordering error at received=%0d",received);
      check_notification=0;
      if (main_byte !== last_byte) begin
        received=received+1;
        if (main_byte !== (received & 255))
          $fatal(1,"snapshot lost/reordered: received=%0d byte=%02x",received,main_byte);
        last_byte=main_byte;
        expected_notification=received & 1;
        check_notification=1;
      end
    end
  end
  initial begin
    repeat(4) @(negedge audio_clk);
    reset_n=1;
    repeat(4) @(negedge audio_clk);
    for (sent=1;sent<=4096;sent=sent+1) begin
      audio_byte=sent & 255;
      audio_notify=sent & 1;
      @(negedge audio_clk);
    end
    repeat(20) @(posedge master_clk);
    #1;
    if (received != 4096 || overflow) $fatal(1,"stream incomplete received=%0d overflow=%b",received,overflow);
    $display("PASS FIFO saturated stream phase=%0d shift=%0dps snapshots=%0d",PHASE_NS,SHIFT_PS,received);
    $finish;
  end
  initial begin #200000; $fatal(1,"stream watchdog"); end
endmodule
