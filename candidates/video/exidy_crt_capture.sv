// SPDX-License-Identifier: GPL-3.0-or-later
// Normalize the actual arcade_video output after its registered RGB/DE update.
// Native raster/game clocks remain unchanged. Caller supplies conditioned reset.
module exidy_crt_capture (
 input wire clk, reset_n,
 input wire ce_mixer,
 input wire [23:0] rgb_mixer,
 input wire de_mixer, vs_mixer,
 output reg ce_out,
 output reg [23:0] rgb_out,
 output reg [8:0] x_out, y_out,
 output reg hb_out, vb_out,
 output reg [31:0] malformed_rows
);
 reg ce_delayed, previous_de, previous_vs;
 reg armed, new_frame;
 reg [8:0] next_x, row_y;
 always @(posedge clk or negedge reset_n) begin
  if(!reset_n) begin
   ce_delayed<=0; previous_de<=0; previous_vs<=0; armed<=0; new_frame<=1;
   next_x<=0; row_y<=0; ce_out<=0; rgb_out<=0; x_out<=0; y_out<=0;
   hb_out<=1; vb_out<=1; malformed_rows<=0;
  end else begin
   // CE_PIXEL is registered before VGA_RGB's CE-qualified update. Sampling
   // one native clock later takes stable post-mixer pixels without delta-cycle
   // assumptions or peeking into the mixer hierarchy.
   ce_delayed<=ce_mixer;
   ce_out<=0;
   if(ce_delayed) begin
    ce_out<=1;
    if(vs_mixer && !previous_vs) begin armed<=1; new_frame<=1; end
    previous_vs<=vs_mixer;
    hb_out<=!de_mixer || !armed;
    vb_out<=!armed;
    rgb_out<=de_mixer && armed ? rgb_mixer : 24'd0;
    if(de_mixer && armed) begin
     if(!previous_de) begin
      x_out<=0; next_x<=1;
      if(new_frame) begin y_out<=0; row_y<=0; new_frame<=0; end
      else begin y_out<=row_y+9'd1; row_y<=row_y+9'd1; end
     end else begin x_out<=next_x; next_x<=next_x+9'd1; y_out<=row_y; end
    end
    if(previous_de && !de_mixer && armed && next_x!=9'd256) begin
     malformed_rows<=malformed_rows+32'd1; armed<=0; rgb_out<=0; hb_out<=1; vb_out<=1;
    end
    previous_de<=de_mixer;
   end
  end
 end
endmodule
