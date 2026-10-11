`timescale 1ns/1ps
// Isolated Mouse Trap voice I/O/control helper. Not included in rtl/index.qip.
// Port decode follows the pinned local MAME exidysound.cpp handlers; RIOT
// command input is the MAME-style PA output callback, including DDR pull-ups.
module mousetrapVoiceIo (
    input  wire       clk,
    input  wire       state_reset_n,
    input  wire       decoder_reset_n,
    input  wire       z80_global_reset,

    input  wire [7:0] io_addr,
    input  wire [7:0] io_data_in,
    input  wire       io_wr,
    input  wire       cvsd_clock_state,
    output wire [7:0] io_data_out,

    // Accepted PA callback pulse; consecutive pulses are separate updates.
    input  wire       riot_pa_write_commit,
    input  wire [7:0] riot_pa_write_data,
    output reg  [7:0] cvsd_data,
    output wire       z80_reset,
    output wire       cvsd_decoder_reset_n,

    output reg        cvsd_digit,
    output reg        riot_pb0_in
);
    reg io_wr_d;
    wire io_write_accept = io_wr && !io_wr_d;
    wire [3:0] cvsd_status_nibble = {
        cvsd_data[3], cvsd_data[0], cvsd_data[2], cvsd_data[1]
    };

    reg [7:0] read_value;
    always @* begin
        read_value = 8'hff;
        if (!io_addr[7]) read_value[3:0] = cvsd_status_nibble;
        if (!io_addr[6]) read_value[7] = cvsd_clock_state;
    end
    assign io_data_out = read_value;

    // The T80 wrapper exposes io_wr as an active-high transaction level. It
    // may remain asserted for multiple clk periods, so accept its rising edge
    // once and require a low phase before accepting the next transaction.
    always @(posedge clk or negedge state_reset_n) begin
        if (!state_reset_n) begin
            io_wr_d <= 1'b0;
            cvsd_data <= 8'h00; // pinned MAME device constructor state
            cvsd_digit <= 1'b0;
            riot_pb0_in <= 1'b0;
        end else begin
            io_wr_d <= io_wr;
            if (riot_pa_write_commit)
                cvsd_data <= riot_pa_write_data;
            if (io_write_accept) begin
                if (!io_addr[4]) cvsd_digit <= io_data_in[0];
                if (!io_addr[5]) riot_pb0_in <= io_data_in[0];
            end
        end
    end

    // MAME resets the speech CPU from the saved PA callback byte, whose
    // input-configured bits are pulled high regardless of the PA input pins.
    assign z80_reset = z80_global_reset || !cvsd_data[4];

    // CVSD decoder reset is deliberately independent of the PA4-controlled
    // speech-CPU reset and is supplied by the integration's decoder lifecycle.
    assign cvsd_decoder_reset_n = decoder_reset_n;
endmodule
