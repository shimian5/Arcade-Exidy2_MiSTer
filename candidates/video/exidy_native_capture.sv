// SPDX-License-Identifier: GPL-3.0-or-later
// Generic post-arcade_video collector for Native transport. CE_PIXEL and the
// mixer RGB/DE/sync outputs are registered on the same clock; delaying CE by
// one clock samples their settled packet without relying on simulator deltas.
// Unlike the CRT-oriented capture helper, this has no 256x256 row contract.
module exidy_native_capture (
    input wire clk,
    input wire reset_n,
    input wire ce_mixer,
    input wire [23:0] rgb_mixer,
    input wire de_mixer, hs_mixer, vs_mixer,
    output reg ce_packet=0,
    output reg [23:0] rgb_packet=0,
    output reg de_packet=0, hs_packet=0, vs_packet=0,
    output reg native_frame=0
);
    reg ce_delayed=0, previous_vs=0;
    always @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            ce_delayed<=0; previous_vs<=0; ce_packet<=0;
            rgb_packet<=0; de_packet<=0; hs_packet<=0; vs_packet<=0;
            native_frame<=0;
        end else begin
            ce_delayed<=ce_mixer;
            ce_packet<=0;
            native_frame<=0;
            if(ce_delayed) begin
                ce_packet<=1;
                rgb_packet<=rgb_mixer;
                de_packet<=de_mixer;
                hs_packet<=hs_mixer;
                vs_packet<=vs_mixer;
                native_frame<=vs_mixer && !previous_vs;
                previous_vs<=vs_mixer;
            end
        end
    end
endmodule
