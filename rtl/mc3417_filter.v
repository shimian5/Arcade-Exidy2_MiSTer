`timescale 1ns/1ps
// Unbound Mouse Trap speech board path at 192kHz: MAME's .3086 route gain,
// then two identical inverting MFB low-pass sections (10k/3.9k/18k,
// 20nF/2.2nF). Coefficients/pins are synchronous to clk. Accept sample commits
// only with sufficient spacing for the two five-term serialized sections.
module exidyMc3417Filter (
    input wire clk,
    input wire cold_reset_n,
    input wire sample_ce,
    input wire signed [31:0] sample_q24,
    input wire signed [15:0] audio_base,
    input wire mute,
    output wire signed [31:0] filtered_q24,
    output wire signed [15:0] pcm,
    output wire pcm_valid,
    output wire overrun,
    output wire signed [15:0] mono,
    output wire clipped
);
    localparam signed [31:0] ROUTE_GAIN=32'sd82839182;
    wire signed [63:0] gain_product=sample_q24*ROUTE_GAIN;
    wire signed [35:0] gained=gain_product[63:28];
    reg signed [31:0] gain_q24;
    reg gain_valid;
    wire first_valid,first_overrun,second_overrun;
    wire signed [31:0] first_q24;
    always @(posedge clk or negedge cold_reset_n) begin
        if(!cold_reset_n) begin gain_q24<=0; gain_valid<=0; end
        else begin
            gain_valid<=sample_ce;
            if(sample_ce) gain_q24<=gained[31:0];
        end
    end
    exidyBiquad first(.clk(clk),.cold_reset_n(cold_reset_n),
        .input_valid(gain_valid),.input_q24(gain_q24),
        .output_valid(first_valid),.output_q24(first_q24),.overrun(first_overrun));
    exidyBiquad second(.clk(clk),.cold_reset_n(cold_reset_n),
        .input_valid(first_valid),.input_q24(first_q24),
        .output_valid(pcm_valid),.output_q24(filtered_q24),.overrun(second_overrun));
    assign overrun=first_overrun || second_overrun;
    // Q24 normalized to signed 16-bit PCM: arithmetic floor, then saturation.
    // Filter state retains headroom; conversion never wraps a large signal.
    wire signed [22:0] pcm_wide=filtered_q24[31:9];
    assign pcm=(pcm_wide>23'sd32767) ? 16'sh7fff :
               (pcm_wide< -23'sd32768) ? 16'sh8000 : pcm_wide[15:0];
    exidySpeechMix mix(.base(audio_base),.speech(pcm),.mute(mute),
        .mono(mono),.clipped(clipped));
endmodule

// Existing base mono level is retained; speech adds at the reference-derived
// gain. Saturation is explicit, with a flag for later gain/headroom acceptance.
// Hardware listening/reference levels must qualify the eventual production mix.
module exidySpeechMix (
    input wire signed [15:0] base,
    input wire signed [15:0] speech,
    input wire mute,
    output wire signed [15:0] mono,
    output wire clipped
);
    wire signed [16:0] sum=$signed({base[15],base})+$signed({speech[15],speech});
    wire high_clip=sum>17'sd32767;
    wire low_clip=sum< -17'sd32768;
    assign clipped=!mute && (high_clip || low_clip);
    assign mono=mute ? 16'sd0 : high_clip ? 16'sh7fff : low_clip ? 16'sh8000 : sum[15:0];
endmodule
