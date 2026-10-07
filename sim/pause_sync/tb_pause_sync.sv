`timescale 1ns/1ps
module tb_pause_sync;
  reg audio_clk=0;
  reg pause_async=0;
  wire pause_au;
  wire signed [15:0] mixed_audio, unsafe_audio;
  wire cpu_ready = ~pause_au;
  integer errors=0;

  always #5 audio_clk = ~audio_clk;

  exidyPauseSync dut(.audio_clk(audio_clk),.pause_in(pause_async),.pause_audio(pause_au));
  exidyAudioMix mix_sync(.src_a(16'sd1200),.src_b(16'sd800),.mute(pause_au),.mono(mixed_audio));
  exidyAudioMix mix_unsafe(.src_a(16'sd1200),.src_b(16'sd800),.mute(pause_async),.mono(unsafe_audio));

  task automatic check(input bit condition, input [255:0] message);
    begin
      if (!condition) begin errors=errors+1; $display("FAIL %0s",message); end
    end
  endtask

  initial begin
    #1;
    check(pause_au===0 && cpu_ready===1 && mixed_audio===1000,"initial state");

    // Change pause midway between audio edges. The unsynchronized control
    // mutes immediately; the synchronized outputs stay unchanged until edge 2.
    @(negedge audio_clk); #1; pause_async=1;
    #1;
    check(pause_au===0 && cpu_ready===1 && mixed_audio===1000,"must not react between edges");
    check(unsafe_audio===0,"negative control should expose immediate asynchronous mute");
    @(posedge audio_clk); #1;
    check(pause_au===0 && cpu_ready===1 && mixed_audio===1000,"first edge only fills metastability stage");
    @(posedge audio_clk); #1;
    check(pause_au===1 && cpu_ready===0 && mixed_audio===0,"pause follows after two edges");

    // Deassertion follows the same two-edge level synchronization.
    @(negedge audio_clk); #1; pause_async=0;
    #1;
    check(pause_au===1 && cpu_ready===0 && mixed_audio===0,"release must not react between edges");
    @(posedge audio_clk); #1;
    check(pause_au===1 && cpu_ready===0 && mixed_audio===0,"release first edge");
    @(posedge audio_clk); #1;
    check(pause_au===0 && cpu_ready===1 && mixed_audio===1000,"release after two edges");

    if(errors==0) $display("PASS pause sync"); else $display("FAILED %0d",errors);
    $finish;
  end
endmodule
