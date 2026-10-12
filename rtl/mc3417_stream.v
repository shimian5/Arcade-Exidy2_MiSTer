`timescale 1ns/1ps
// Unbound fixed-rate renderer, deliberately independent of MAME callback
// boundaries. Default cadence is 192 kHz; ceil(192000/15469.5695)=13 ticks.
// A new endpoint starts a causal 13-tick ramp from the current output. Signed
// division truncates toward zero; the final tick snaps to the exact endpoint.
// Interrupted ramps restart from the current value. Q24 is retained for the
// later board filters; no 16-bit conversion, gain or clipping occurs here.
// 6000 silent sample ticks = 31.25 ms; timeout begins on tick 6001, then ramps
// to zero. This is an explicit reference-inspired policy, not analog parity.
module exidyMc3417Stream #(
    parameter RAMP_TICKS=13,
    parameter IDLE_TICKS=6000
) (
    input wire clk,
    input wire cold_reset_n,
    input wire sample_ce,
    input wire clock_transition,
    input wire sample_valid,
    input wire signed [31:0] sample_q24,
    output reg signed [31:0] pcm_q24,
    output reg idle
);
    localparam RAMP_BITS=(RAMP_TICKS<2) ? 1 : $clog2(RAMP_TICKS+1);
    localparam AGE_BITS=(IDLE_TICKS<2) ? 1 : $clog2(IDLE_TICKS+1);
    localparam signed [32:0] RAMP_DIVISOR=RAMP_TICKS;
    reg signed [31:0] target;
    reg signed [32:0] increment;
    reg [RAMP_BITS-1:0] remaining;
    reg [AGE_BITS-1:0] age;
    wire activity=clock_transition || sample_valid;
    wire signed [32:0] current_wide={pcm_q24[31],pcm_q24};
    wire signed [32:0] new_delta=$signed({sample_q24[31],sample_q24})-current_wide;
    wire signed [32:0] silence_delta=-current_wide;
    // Exact unsigned division by 13 for a 32-bit magnitude:
    // floor(n/13)=floor(n*ceil(2^34/13)/2^34). The reciprocal surplus is 3;
    // for n<=2^32-1 its error is <3/52, below the smallest 1/13 gap.
    // A signed 33-bit endpoint difference has magnitude <=2^32-1.
    // Quartus's generic divider missed timing; use its DSP multiplier instead.
    function signed [32:0] ramp_quotient;
        input signed [32:0] delta;
        reg [31:0] magnitude;
        reg [63:0] product;
        reg signed [32:0] quotient;
        begin
            if (RAMP_TICKS==13) begin
                magnitude=delta[32] ? (~delta[31:0]+32'd1) : delta[31:0];
                product=magnitude*32'h4ec4ec4f;
                quotient=$signed({3'b000,product[63:34]});
                ramp_quotient=delta[32] ? -quotient : quotient;
            end else ramp_quotient=delta/RAMP_DIVISOR;
        end
    endfunction
    wire signed [32:0] ramp_delta=sample_valid ? new_delta : silence_delta;
    wire signed [32:0] ramp_increment=ramp_quotient(ramp_delta);
    wire signed [32:0] advanced=current_wide+increment;
    wire timeout_tick=sample_ce && !activity && !idle && (age==IDLE_TICKS);

    always @(posedge clk or negedge cold_reset_n) begin
        if (!cold_reset_n) begin
            pcm_q24<=0;
            target<=0;
            increment<=0;
            remaining<=0;
            age<=0;
            idle<=0;
        end else begin
            // Warm CPU/clock reset is intentionally not a renderer reset.
            // Caller keeps state and only restarts clock history at its boundary.
            if (activity) begin
                age<=0;
                idle<=0;
            end else if (sample_ce && !idle) begin
                if (age<IDLE_TICKS) age<=age+1'b1;
                else idle<=1;
            end

            if (sample_valid) begin
                target<=sample_q24;
                increment<=ramp_increment;
                remaining<=RAMP_TICKS;
            end else if (timeout_tick) begin
                target<=0;
                increment<=ramp_increment;
                remaining<=RAMP_TICKS;
            end else if (sample_ce && remaining!=0) begin
                remaining<=remaining-1'b1;
                if (remaining==1) pcm_q24<=target;
                else pcm_q24<=advanced[31:0];
            end
        end
    end
endmodule
