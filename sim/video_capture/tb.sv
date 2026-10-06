`timescale 1ns/1ps
module tb #(parameter GAMMA_MODE = 1);
  reg master_clock = 0;
  reg [7:0] mod_shift = 8'h37;
  integer phase = 0;
  reg [2:0] source_rgb3 = 0;
  wire core_pix_clk, hsync_raw, vsync_raw, hblank_raw, vblank_raw;
  wire clk_video, ce_pixel;
  wire [7:0] r, g, b;
  wire hs, vs, de;
  wire [1:0] scanline;
  wire [5:0] hscnt;
  wire [8:0] vscnt;
  wire [5:0] hspcnt;
  wire vl1;

  source_video #(GAMMA_MODE) dut(
    .master_clock(master_clock), .mod_shift(mod_shift), .source_rgb3(source_rgb3),
    .core_pix_clk(core_pix_clk), .hsync_raw(hsync_raw), .vsync_raw(vsync_raw),
    .hblank_raw(hblank_raw), .vblank_raw(vblank_raw),
    .clk_video(clk_video), .ce_pixel(ce_pixel),
    .vga_r(r), .vga_g(g), .vga_b(b), .vga_hs(hs), .vga_vs(vs), .vga_de(de),
    .raw_hscnt(hscnt), .raw_hspcnt(hspcnt), .raw_vscnt(vscnt), .raw_vl1(vl1)
  );

  always #1 master_clock = ~master_clock;

  integer stim_x = 0;
  integer stim_y = 0;
  reg stim_prev_hblank = 1;
  reg stim_prev_vblank = 1;
  reg stim_line_vblank = 1;
  integer input_active_pixels = 0;
  integer master_cycle = 0;
  integer source_timestamp [0:65535];
  reg source_seen [0:65535];
  integer latency_min = 2147483647;
  integer latency_max = 0;
  integer latency_samples = 0;
  integer bit_index;
  reg line_start;

  always @(posedge master_clock) master_cycle = master_cycle + 1;

  function automatic [2:0] pattern(input integer x, input integer y);
    begin
      pattern[2] = (x >> phase) & 1;
      pattern[1] = (y >> phase) & 1;
      pattern[0] = pattern[2] ^ pattern[1];
    end
  endfunction

  // Update stimulus after a pixel event so it is stable before the next one.
  always @(negedge core_pix_clk) begin
    line_start = stim_prev_hblank && !hblank_raw;
    if (line_start) begin
      stim_x = 0;
      stim_line_vblank = vblank_raw;
      if (stim_line_vblank) begin
        stim_y = 0;
      end else if (stim_prev_vblank) begin
        stim_y = 0;
      end else begin
        stim_y = stim_y + 1;
      end
    end else if (!hblank_raw) begin
      stim_x = stim_x + 1;
    end else begin
      stim_x = 0;
    end
    if (line_start) stim_prev_vblank = stim_line_vblank;
    stim_prev_hblank = hblank_raw;
    if (!hblank_raw && !stim_line_vblank && stim_x < 256 && stim_y < 256) begin
      source_rgb3 = pattern(stim_x, stim_y);
      input_active_pixels = input_active_pixels + 1;
    end else begin
      source_rgb3 = 0;
    end
  end

  always @(posedge core_pix_clk) begin
    if (!hblank_raw && !stim_line_vblank && stim_x < 256 && stim_y < 256) begin
      source_timestamp[stim_y * 256 + stim_x] = master_cycle;
      source_seen[stim_y * 256 + stim_x] = 1'b1;
    end
  end

  integer active_frames = 0;
  integer active_rows = 0;
  integer line_pixels = 0;
  integer compared_pixels = 0;
  integer bad_pixels = 0;
  integer color_mismatches = 0;
  integer missing_source_coordinates = 0;
  integer line_count_errors = 0;
  integer last_vsync = 0;
  integer vsync_seen = 0;
  integer x = 0;
  integer y = 0;
  integer started_image = 0;
  reg previous_de = 0;
  reg previous_hs = 0;
  reg previous_vs = 0;
  integer hs_rises = 0;
  integer vs_rises = 0;
  integer output_pixel_events = 0;
  integer first_input_mark = -1;
  integer first_output_mark = -1;
  integer event_index = 0;
  integer previous_output_cycle = -1;
  integer output_cycle_min = 2147483647;
  integer output_cycle_max = 0;
  integer last_hs_rise = -1;
  integer hs_start = -1;
  integer hs_period_min = 2147483647;
  integer hs_period_max = 0;
  integer hs_width_min = 2147483647;
  integer hs_width_max = 0;
  integer last_vs_rise = -1;
  integer vs_start = -1;
  integer vs_period_min = 2147483647;
  integer vs_period_max = 0;
  integer vs_width_min = 2147483647;
  integer vs_width_max = 0;
  integer de_phase_min = 2147483647;
  integer de_phase_max = 0;
  integer vs_to_active_de = -1;

  task automatic compare_pixel(input integer px, input integer py);
    reg [2:0] expected;
    reg [23:0] expected_rgb;
    begin
      expected = pattern(px, py);
      expected_rgb = {{8{expected[2]}}, {8{expected[1]}}, {8{expected[0]}}};
      if ({r,g,b} !== expected_rgb) begin
        if (bad_pixels < 8) $display("PIXEL_MISMATCH x=%0d y=%0d got=%06x expected=%06x event=%0d", px, py, {r,g,b}, expected_rgb, event_index);
        bad_pixels = bad_pixels + 1;
        color_mismatches = color_mismatches + 1;
      end
      compared_pixels = compared_pixels + 1;
      if (source_seen[py * 256 + px]) begin
        if (master_cycle - source_timestamp[py * 256 + px] < latency_min) latency_min = master_cycle - source_timestamp[py * 256 + px];
        if (master_cycle - source_timestamp[py * 256 + px] > latency_max) latency_max = master_cycle - source_timestamp[py * 256 + px];
        latency_samples = latency_samples + 1;
      end else begin
        if (bad_pixels < 8) $display("LATENCY_SOURCE_MISSING x=%0d y=%0d cycle=%0d", px, py, master_cycle);
        bad_pixels = bad_pixels + 1;
        missing_source_coordinates = missing_source_coordinates + 1;
      end
    end
  endtask

  // Observe the final output only on its actual pixel enable. Coordinates are
  // reconstructed from output DE edges, independently of the input counters.
  always @(posedge ce_pixel) begin
    #0.01;
    event_index = event_index + 1;
    output_pixel_events = output_pixel_events + 1;
    if (previous_output_cycle >= 0) begin
      if (master_cycle - previous_output_cycle < output_cycle_min) output_cycle_min = master_cycle - previous_output_cycle;
      if (master_cycle - previous_output_cycle > output_cycle_max) output_cycle_max = master_cycle - previous_output_cycle;
    end
    previous_output_cycle = master_cycle;
    if (!previous_vs && vs) begin
      vs_rises = vs_rises + 1;
      if (vs_rises >= 2) vsync_seen = 1;
    end
    if (!previous_hs && hs) hs_rises = hs_rises + 1;
      if (vsync_seen && !started_image && !previous_de && de) begin
      started_image = 1;
      active_frames = 0;
      active_rows = 0;
      line_pixels = 0;
      y = 0;
    end
    if (started_image) begin
      if (!previous_de && de) begin
        if (active_rows > 0 && line_pixels != 256) line_count_errors = line_count_errors + 1;
        if (active_rows > 0) y = y + 1;
        x = 0;
        line_pixels = 0;
        active_rows = active_rows + 1;
      end
      if (de) begin
        if (active_rows <= 256 && x < 256) compare_pixel(x, y);
        x = x + 1;
        line_pixels = line_pixels + 1;
      end
      if (previous_de && !de && active_rows > 0) begin
        if (line_pixels != 256) line_count_errors = line_count_errors + 1;
        if (active_rows == 256) begin
          active_frames = active_frames + 1;
          if (active_frames >= 1) begin
            $display("RESULT gamma=%0d phase=%0d checked_images=%0d rows=%0d compared=%0d bad=%0d color_mismatches=%0d missing_source_coordinates=%0d line_errors=%0d input_active=%0d output_events=%0d hs_rises=%0d vs_rises=%0d output_cycle_min=%0d output_cycle_max=%0d latency_min_master=%0d latency_max_master=%0d latency_samples=%0d", GAMMA_MODE, phase, active_frames, active_rows, compared_pixels, bad_pixels, color_mismatches, missing_source_coordinates, line_count_errors, input_active_pixels, output_pixel_events, hs_rises, vs_rises, output_cycle_min, output_cycle_max, latency_min, latency_max, latency_samples);
            if (compared_pixels != 65536 || line_count_errors != 0) $fatal(1, "output active geometry diagnostic failed");
            $finish;
          end
          active_rows = 0;
          y = 0;
        end
      end
    end
    previous_de = de;
    previous_hs = hs;
    previous_vs = vs;
  end

  initial begin
    for (bit_index = 0; bit_index < 65536; bit_index = bit_index + 1) begin
      source_timestamp[bit_index] = 0;
      source_seen[bit_index] = 0;
    end
    if (!$value$plusargs("SHIFT=%d", mod_shift)) mod_shift = 8'h37;
    if (!$value$plusargs("PHASE=%d", phase)) phase = 0;
    if (phase < 0 || phase > 7) $fatal(1, "phase must be 0..7");
    // The production arcade_video instance leaves video_mixer.HDMI_FREEZE
    // unconnected. Tie that child input low for deterministic no-freeze tests.
    force dut.arcade_video.video_mixer.HDMI_FREEZE = 1'b0;
    repeat (4_000_000) @(posedge master_clock);
    $fatal(1, "timeout before a complete output image");
  end
endmodule
