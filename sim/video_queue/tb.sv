`timescale 1ns/1ps
module tb;
  reg master_clock=0;
  always #1 master_clock=~master_clock;
  reg [7:0] mod_shift=8'h37;
  reg [2:0] source_rgb3=0;
  wire core_pix_clk,hsync_raw,vsync_raw,hblank_raw,vblank_raw,clk_video,ce_pixel;
  wire [7:0] r,g,b;
  wire hs,vs,de;
  wire [1:0] scanline;
  wire [5:0] hscnt,hspcnt;
  wire [8:0] vscnt;
  wire vl1;
  source_video #(1) dut(.master_clock(master_clock),.mod_shift(mod_shift),.source_rgb3(source_rgb3),
    .core_pix_clk(core_pix_clk),.hsync_raw(hsync_raw),.vsync_raw(vsync_raw),
    .hblank_raw(hblank_raw),.vblank_raw(vblank_raw),.clk_video(clk_video),.ce_pixel(ce_pixel),
    .vga_r(r),.vga_g(g),.vga_b(b),.vga_hs(hs),.vga_vs(vs),.vga_de(de),
    .raw_hscnt(hscnt),.raw_hspcnt(hspcnt),.raw_vscnt(vscnt),.raw_vl1(vl1));
  integer phase=0,corrupt=0,cycle=0;
  reg old_input_ce=0,previous_input_blank=1,source_line_blank=1;
  integer ix=-1,iy=-1,frame=-1;
  integer dx,dy;
  reg predicted_vblank;
  function automatic [2:0] pattern(input integer x,y);
    pattern={1'((x>>phase)&1),1'((y>>phase)&1),1'(((x>>phase)^(y>>phase))&1)};
  endfunction
  // Only input raster history determines the pre-capture stimulus.
  always @(negedge master_clock) begin
    if(core_pix_clk && !old_input_ce) begin
      predicted_vblank=source_line_blank;
      if(previous_input_blank && !hblank_raw) predicted_vblank=vblank_raw;
      dx=previous_input_blank ? 0 : ix+1; dy=iy;
      if(previous_input_blank && !hblank_raw) dy=source_line_blank ? 0 : iy+1;
      source_rgb3=(!hblank_raw && !predicted_vblank) ? pattern(dx,dy) : 0;
    end
  end
  reg [23:0] fifo_rgb[0:65535];
  integer fifo_time[0:65535],fifo_x[0:65535],fifo_y[0:65535];
  integer tail=0,head=0,input_errors=0,count_row0=0,count_row255=0;
  integer last_x=-1,last_y=-1,output_x=0,output_y=-1,output_rows=0,compared=0;
  integer lat_min=999999,lat_max=0,input_line_errors=0;
  reg previous_de=0,started=0,old_output_ce;
  reg [2:0] want;
  reg [23:0] actual;
  always @(posedge master_clock) begin
    cycle=cycle+1;
    if(core_pix_clk && !old_input_ce) begin
      if(previous_input_blank && !hblank_raw) begin
        if(source_line_blank && !vblank_raw) begin iy=0; frame=frame+1; end
        else if(!source_line_blank && !vblank_raw) iy=iy+1;
        source_line_blank=vblank_raw; ix=0;
      end else if(!hblank_raw) ix=ix+1;
      if(!previous_input_blank && hblank_raw && frame==2 && !source_line_blank && ix!=255) input_line_errors++;
      if(!hblank_raw && !source_line_blank && frame==2) begin
        want=pattern(ix,iy);
        if(source_rgb3!==want) input_errors++;
        if(tail>=65536) $fatal(1,"input overflow");
        fifo_rgb[tail]={{8{source_rgb3[2]}},{8{source_rgb3[1]}},{8{source_rgb3[0]}}};
        fifo_x[tail]=ix; fifo_y[tail]=iy; fifo_time[tail]=cycle; tail++;
        if(iy==0) count_row0++; if(iy==255) count_row255++;
        last_x=ix; last_y=iy;
      end
      previous_input_blank=hblank_raw;
    end
    old_input_ce=core_pix_clk; old_output_ce=ce_pixel;
    #0.01;
    if(old_output_ce) begin
      if(!previous_de && de && !started && frame==2 && iy==0) begin started=1; output_y=-1; end
      if(started) begin
        if(!previous_de && de) begin output_x=0; output_y++; output_rows++; end
        if(de) begin
          if(head>=tail) $fatal(1,"FIFO underflow head=%0d tail=%0d",head,tail);
          actual={r,g,b};
          if(corrupt && head==0) fifo_rgb[head]=fifo_rgb[head]^24'h010000;
          if(actual!==fifo_rgb[head] || fifo_x[head]!=output_x || fifo_y[head]!=output_y) begin
            $display("FIFO_MISMATCH head=%0d x=%0d y=%0d source_x=%0d source_y=%0d got=%06x expected=%06x",head,output_x,output_y,fifo_x[head],fifo_y[head],actual,fifo_rgb[head]);
            $fatal(1,"independent queue parity failed");
          end
          if(cycle-fifo_time[head]<lat_min) lat_min=cycle-fifo_time[head];
          if(cycle-fifo_time[head]>lat_max) lat_max=cycle-fifo_time[head];
          head++; compared++; output_x++;
        end
        if(previous_de && !de) begin
          if(output_x!=256) $fatal(1,"output row width");
          if(output_rows==256) begin
            $display("RESULT phase=%0d input=%0d output=%0d row0=%0d row255=%0d last_x=%0d last_y=%0d input_errors=%0d input_line_errors=%0d latency_min=%0d latency_max=%0d",phase,tail,compared,count_row0,count_row255,last_x,last_y,input_errors,input_line_errors,lat_min,lat_max);
            if(tail!=65536 || compared!=65536 || input_errors || input_line_errors || count_row0!=256 || count_row255!=256) $fatal(1,"independent coverage failed");
            $finish;
          end
        end
      end
      previous_de=de;
    end
  end
  initial begin
    if(!$value$plusargs("PHASE=%d",phase)) phase=0;
    if(!$value$plusargs("CORRUPT=%d",corrupt)) corrupt=0;
    force dut.arcade_video.video_mixer.HDMI_FREEZE=0;
    repeat(4000000) @(posedge master_clock); $fatal(1,"timeout");
  end
endmodule
