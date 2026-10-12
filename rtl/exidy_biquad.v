`timescale 1ns/1ps
// Fixed-point direct-form I biquad. Q24 sample/history, Q28 coefficients.
// Five multiply/accumulate cycles share one multiplier per stage. Input
// commits require an idle stage; an overlapping commit sets sticky overrun.
// Coefficients are the pinned Mouse Trap 192kHz low-pass, with feedback signs
// already negated. Saturation bounds state instead of allowing wraparound.
module exidyBiquad #(
    parameter signed [31:0] B0=-32'sd1006194,
    parameter signed [31:0] B1=-32'sd2012388,
    parameter signed [31:0] B2=-32'sd1006194,
    parameter signed [31:0] F1=32'sd507340529,
    parameter signed [31:0] F2=-32'sd241141060
) (
    input wire clk,
    input wire cold_reset_n,
    input wire input_valid,
    input wire signed [31:0] input_q24,
    output reg output_valid,
    output reg signed [31:0] output_q24,
    output reg overrun
);
    reg busy;
    reg [2:0] term_index;
    reg signed [31:0] x0,x1,x2,y1,y2;
    reg signed [31:0] operand,coefficient;
    reg signed [66:0] accumulator;
    wire signed [63:0] product=operand*coefficient;
    wire signed [66:0] total=accumulator+{{3{product[63]}},product};
    wire signed [38:0] shifted=total[66:28];
    wire signed [31:0] result=(shifted>39'sd2147483647) ? 32'sh7fffffff :
                             (shifted< -39'sd2147483648) ? 32'sh80000000 : shifted[31:0];
    always @* begin
        case(term_index)
            0: begin operand=x0; coefficient=B0; end
            1: begin operand=x1; coefficient=B1; end
            2: begin operand=x2; coefficient=B2; end
            3: begin operand=y1; coefficient=F1; end
            default: begin operand=y2; coefficient=F2; end
        endcase
    end
    always @(posedge clk or negedge cold_reset_n) begin
        if(!cold_reset_n) begin
            busy<=0; term_index<=0; accumulator<=0;
            x0<=0; x1<=0; x2<=0; y1<=0; y2<=0;
            output_valid<=0; output_q24<=0; overrun<=0;
        end else begin
            output_valid<=0;
            if(input_valid && busy) overrun<=1;
            if(!busy && input_valid) begin
                x0<=input_q24;
                term_index<=0;
                accumulator<=0;
                busy<=1;
            end else if(busy) begin
                if(term_index==4) begin
                    output_q24<=result;
                    output_valid<=1;
                    y2<=y1; y1<=result;
                    x2<=x1; x1<=x0;
                    busy<=0;
                end else begin
                    accumulator<=total;
                    term_index<=term_index+1'b1;
                end
            end
        end
    end
endmodule
