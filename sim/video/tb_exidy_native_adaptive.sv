`timescale 1ns/1ps
module tb_exidy_native_adaptive;
  reg master_clock=0;
  always #1 master_clock=~master_clock;
  reg [7:0] mod_shift=8'h37;
  reg [2:0] fx=0;
  reg forced_scandoubler=0;
  reg [2:0] source_rgb3=0;
  wire core_pix_clk,hsync_raw,vsync_raw,hblank_raw,vblank_raw,clk_video,ce_pixel;
  wire [7:0] r,g,b;
  wire hs,vs,de;
  wire [1:0] scanline;
  wire [5:0] hscnt,hspcnt;
  wire [8:0] vscnt;
  wire vl1;
  source_video #(1) source(.master_clock(master_clock),.mod_shift(mod_shift),.source_rgb3(source_rgb3),
    .fx(fx),.forced_scandoubler(forced_scandoubler),.core_pix_clk(core_pix_clk),
    .hsync_raw(hsync_raw),.vsync_raw(vsync_raw),.hblank_raw(hblank_raw),.vblank_raw(vblank_raw),
    .clk_video(clk_video),.ce_pixel(ce_pixel),.vga_r(r),.vga_g(g),.vga_b(b),
    .vga_hs(hs),.vga_vs(vs),.vga_de(de),.raw_hscnt(hscnt),.raw_hspcnt(hspcnt),
    .raw_vscnt(vscnt),.raw_vl1(vl1));

  reg reset_async=1;
  wire ce_packet,native_frame;
  wire [23:0] rgb_packet;
  wire de_packet,hs_packet,vs_packet;
  exidy_native_capture capture(.clk(master_clock),.reset_n(!reset_async),
    .ce_mixer(ce_pixel),.rgb_mixer({r,g,b}),.de_mixer(de),.hs_mixer(hs),.vs_mixer(vs),
    .ce_packet(ce_packet),.rgb_packet(rgb_packet),.de_packet(de_packet),
    .hs_packet(hs_packet),.vs_packet(vs_packet),.native_frame(native_frame));

  reg clk_output=0;
  integer clock_phase_ps=333;
  initial begin
    if(!$value$plusargs("CLOCK_PHASE_PS=%d",clock_phase_ps)) clock_phase_ps=333;
    $display("RUN output phase_ps=%0d",clock_phase_ps);
    #(clock_phase_ps*1ps); forever #1 clk_output=~clk_output;
  end
  reg [1:0] cadence=0;
  wire ce_render,ce_video,ce_master;
  wire [23:0] rgb_out;
  wire hs_out,vs_out,hb_out,vb_out;
  wire [8:0] hpos_out,vpos_out;
  wire fault;
  exidy_native_bridge_adaptive #(.EXTERNAL_PACKETS(1)) bridge(
    .clk_sys(master_clock),.clk_video(clk_output),.reset_async(reset_async),
    .ce_packet(ce_packet),.cadence(cadence),.rgb_in(rgb_packet),
    .hs_in(hs_packet),.vs_in(vs_packet),.hb_in(!de_packet),.vb_in(1'b0),
    .hpos_in(9'd0),.vpos_in(9'd0),.ce_render(ce_render),.ce_video(ce_video),
    .ce_master(ce_master),.rgb_out(rgb_out),.hs_out(hs_out),.vs_out(vs_out),
    .hb_out(hb_out),.vb_out(vb_out),.hpos_out(hpos_out),.vpos_out(vpos_out),.fault(fault));

  reg [31:0] expected_packets[0:2097151];
  integer tail=0,head=0,src_cycle=0,last_source_ce=-1,source_period_errors=0,source_ce_count=0;
  integer consumed=0,packet_mismatches=0,frames=0,frame_pulses=0,output_frames=0,active_reset_count=0;
  integer output_cycle=0,last_video_ce=-1,output_period_errors=0,output_pixel_count=0,master_request_count=0;
  reg expected_ce_delayed=0, previous_vs=0;
  reg [31:0] expected_packet,actual_packet;
  integer expected_period=8;
  always @(posedge master_clock) begin
    src_cycle=src_cycle+1;
    // Input image is synthetic; the oracle begins at accepted post-mixer packets.
    source_rgb3={hscnt[0],vscnt[0],hscnt[1]^vscnt[1]};
    if(reset_async) begin
      expected_ce_delayed=0; tail=0; last_source_ce=-1; source_period_errors=0; source_ce_count=0;
      frames=0; frame_pulses=0; previous_vs=0;
      master_request_count=0;
    end else begin
      if(ce_master) master_request_count=master_request_count+1;
      if(ce_pixel) begin
        if(expected_period>0 && last_source_ce>=0 && source_ce_count>=3 && src_cycle-last_source_ce!=expected_period)
          source_period_errors=source_period_errors+1;
        last_source_ce=src_cycle;
        source_ce_count=source_ce_count+1;
      end
      if(expected_ce_delayed) begin
        if(tail>=2097152) $fatal(1,"oracle queue overflow");
        expected_packets[tail]={r,g,b,de,hs,vs};
        tail=tail+1;
        if(vs && !previous_vs) frames=frames+1;
        previous_vs=vs;
      end
      if(native_frame) frame_pulses=frame_pulses+1;
      expected_ce_delayed=ce_pixel;
    end
  end

  reg previous_output_vs=0;
  always @(posedge clk_output) begin
    if(reset_async) begin
      head=0; consumed=0; packet_mismatches=0; output_cycle=0; last_video_ce=-1; output_frames=0;
      previous_output_vs=0;
      output_period_errors=0; output_pixel_count=0;
    end else begin
      output_cycle=output_cycle+1;
      if(ce_video) begin
        if(last_video_ce>=0 && output_cycle-last_video_ce!=expected_period && expected_period>0)
          output_period_errors=output_period_errors+1;
        last_video_ce=output_cycle; output_pixel_count=output_pixel_count+1;
        if(bridge.stream_started && !bridge.empty) begin
          if(head>=tail) $fatal(1,"output consumed packet not yet accepted head=%0d tail=%0d",head,tail);
          expected_packet=expected_packets[head];
          actual_packet={rgb_out,!hb_out && !vb_out,hs_out,vs_out};
          if(actual_packet!==expected_packet) begin
            packet_mismatches=packet_mismatches+1;
            $fatal(1,"post-mixer packet mismatch mode=%0d head=%0d got=%08x expected=%08x",fx,head,actual_packet,expected_packet);
          end
          if(vs_out && !previous_output_vs) output_frames=output_frames+1;
          previous_output_vs=vs_out;
          if(hpos_out!=0 || vpos_out!=0) $fatal(1,"unused coordinate metadata changed");
          head=head+1; consumed=consumed+1;
        end
      end
    end
  end

  integer full_frames=0;
  reg mode_started=0;
  task automatic run_mode(input [2:0] mode,input [1:0] rate,input integer period,input bit forced,input integer cycles,input bit require_frame,input bit expect_fault);
    integer i;
    begin
      if(mode_started) begin
        // Drop transport during visible source content, then switch FX only
        // while both bridge domains remain held in shared reset.
        while(!de_packet) @(negedge master_clock);
        reset_async=1; active_reset_count=active_reset_count+1;
        repeat(8) @(negedge master_clock);
        fx=mode; cadence=rate; forced_scandoubler=forced; expected_period=period;
        repeat(4) @(negedge master_clock);
      end else begin
        reset_async=1; fx=mode; cadence=rate; forced_scandoubler=forced; expected_period=period;
        repeat(8) @(negedge master_clock);
        mode_started=1;
      end
      reset_async=0;
      if(full_frames && !expect_fault) begin
        i=0;
        while((frames<2 || output_frames<2) && i<2200000) begin
          @(negedge master_clock); i=i+1;
        end
        if(i==2200000) $fatal(1,"two-frame transport timeout FX=%0d source=%0d output=%0d",mode,frames,output_frames);
      end else begin
        for(i=0;i<cycles;i=i+1) @(negedge master_clock);
      end
      if(fault!==expect_fault) $fatal(1,"bridge fault expectation mismatch FX=%0d cadence=%0d got=%b expected=%b",mode,rate,fault,expect_fault);
      if(source_period_errors) $fatal(1,"mixer CE period mismatch FX=%0d period=%0d errors=%0d",mode,period,source_period_errors);
      if(period>0 && output_period_errors) $fatal(1,"bridge CE period mismatch FX=%0d period=%0d errors=%0d",mode,period,output_period_errors);
      if(period>0 && (master_request_count<2*output_pixel_count-4 || master_request_count>2*output_pixel_count+4))
        $fatal(1,"HSC request cadence not twice output pixel cadence FX=%0d master=%0d pixels=%0d",mode,master_request_count,output_pixel_count);
      if(consumed<3000 || consumed>tail || packet_mismatches)
        $fatal(1,"coverage failure FX=%0d accepted=%0d consumed=%0d mismatches=%0d",mode,tail,consumed,packet_mismatches);
      if(require_frame && (frames<1 || frame_pulses!=frames || output_frames!=frames))
        $fatal(1,"VS frame marker mismatch FX=%0d source=%0d capture=%0d output=%0d",mode,frames,frame_pulses,output_frames);
      if(full_frames && !expect_fault && (frames<2 || output_frames<2))
        $fatal(1,"two full VS edges not transported FX=%0d source=%0d output=%0d",mode,frames,output_frames);
      $display("PASS native FX=%0d force=%0d cadence=/ %0d accepted=%0d consumed=%0d frames=%0d output_frames=%0d",mode,forced,period,tail,consumed,frames,output_frames);
    end
  endtask

  integer i;
  initial begin
    force source.arcade_video.video_mixer.HDMI_FREEZE=0;
    if(!$value$plusargs("FULL_FRAMES=%d",full_frames)) full_frames=0;
    run_mode(3'd0,2'b00,8,0,1200000,1,0);
    run_mode(3'd2,2'b01,4,0,50000,0,0);
    run_mode(3'd0,2'b01,4,1,50000,0,0);
    run_mode(3'd1,2'b10,2,0,50000,0,0);
    run_mode(3'd0,2'b01,0,0,50000,0,1); // Deliberately wrong cadence: /4 consumer outruns /8 source.
    if(full_frames && active_reset_count<4) $fatal(1,"did not exercise reset during active frame before every FX change");
    $display("PASS negative control: incorrect /4 transport against native /8 source raises FIFO fault");
    $finish;
  end
  initial begin #50000000; $fatal(1,"global timeout"); end
endmodule
