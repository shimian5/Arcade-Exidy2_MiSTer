`timescale 1ns/1ps
// Unbound callback adapter for accepted R6532 PA register writes.
// Same-domain accepted_write is a per-phi2-write pulse, not a bus level.
// MAME mos6530_device_base::update_pa uses output latches with input bits
// pulled high; it runs at reset and after both ORA and DDRA writes.
module mousetrapVoiceCommand (
    input wire clk,
    input wire reset_n,
    input wire accepted_write,
    input wire [4:0] address,
    input wire [7:0] data,
    output reg command_commit,
    output reg [7:0] command_data
);
    reg [7:0] ora, ddra;
    reg reset_pending;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            ora <= 8'h00;
            ddra <= 8'h00;
            command_data <= 8'hff;
            command_commit <= 1'b0;
            reset_pending <= 1'b1;
        end else begin
            command_commit <= 1'b0;
            if (reset_pending) begin
                reset_pending <= 1'b0;
                command_commit <= 1'b1;
                command_data <= 8'hff;
            end
            if (accepted_write && !address[2] && !address[1]) begin
                command_commit <= 1'b1;
                if (!address[0]) begin
                    ora <= data;
                    command_data <= (data & ddra) | ~ddra;
                end else begin
                    ddra <= data;
                    command_data <= (ora & data) | ~data;
                end
            end
        end
    end
endmodule
