/*
License: BSD-3-Clause

Copyright (c) Aaron Giles, Jonathan Gevaryahu
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
   may be used to endorse or promote products derived from this software
   without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.
============================================================================

*/
`timescale 1ns/1ps
// Unbound MC3417 bit-event model. State is Q24; output is normalized signed
// Q24, before interpolation, idle-stream silence, board filters and gain.
// Coefficients follow pinned MAME's fixed 16kHz design, not the edge rate.
module exidyMc3417 #(parameter SAMPLE_ON_RISING=1'b0) (
    input wire clk,
    input wire cold_reset_n,
    input wire clock_reset,
    input wire cvsd_clock,
    input wire digit,
    output reg signed [31:0] sample_q24,
    output reg [2:0] history,
    output reg [31:0] step_q24,
    output reg signed [31:0] integrator_q24
);
    localparam signed [31:0] LEAK=32'sd15760736;
    localparam [31:0] CHARGE=32'd16517109;
    localparam [31:0] STEP_MIN=32'd697932;
    localparam [31:0] STEP_MAX=32'd18377762;
    localparam signed [31:0] SAMPLE_GAIN=32'sd5120000;
    reg last_clock;
    wire active_edge=(cvsd_clock!=last_clock) && (cvsd_clock==SAMPLE_ON_RISING);
    wire [2:0] next_history={history[1:0],digit};
    wire signed [32:0] stepped=$signed(integrator_q24) +
        (digit ? -$signed({1'b0,step_q24}) : $signed({1'b0,step_q24}));
    wire signed [64:0] leaked=stepped*$signed(LEAK);
    wire signed [31:0] next_integrator=leaked[55:24];
    wire [63:0] charge_product=(STEP_MAX-step_q24)*CHARGE;
    wire [63:0] decay_product=step_q24*CHARGE;
    wire [31:0] charge_step=STEP_MAX-charge_product[55:24];
    wire [31:0] decay_step=decay_product[55:24];
    wire signed [63:0] output_product=next_integrator*$signed(SAMPLE_GAIN);
    always @(posedge clk or negedge cold_reset_n) begin
        if (!cold_reset_n) begin
            last_clock<=0;
            history<=0;
            step_q24<=0;
            integrator_q24<=0;
            sample_q24<=0;
        end else if (clock_reset) begin
            // MAME base device_reset clears clock history only. CPU reset
            // is separate and must not be connected to cold_reset_n.
            last_clock<=0;
        end else begin
            last_clock<=cvsd_clock;
            if (active_edge) begin
                history<=next_history;
                integrator_q24<=next_integrator;
                if (next_history==0 || next_history==7)
                    step_q24<=(charge_step>STEP_MAX) ? STEP_MAX : charge_step;
                else
                    step_q24<=(decay_step<STEP_MIN) ? STEP_MIN : decay_step;
                sample_q24<=output_product[55:24];
            end
        end
    end
endmodule

