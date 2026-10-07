`timescale 1ns/1ps
// Standalone T80-style wait-state adapter for a one-cycle synchronous ROM.
// This does not decode I/O or writes and is not wired into the production core.
module speechRomBus (
    input  wire       clk,
    input  wire       reset,
    input  wire [15:0] cpu_addr,
    input  wire       mem_rd,
    input  wire       io_rd,
    input  wire       rom_ready,
    input  wire [7:0] rom_data,
    output wire       rom_read,
    output wire [13:0] rom_addr,
    output wire       wait_n,
    output wire [7:0] cpu_data
);
    localparam DRAIN_GUARD = 3'd0, DRAIN_RESPONSE = 3'd1, IDLE = 3'd2,
               WAIT_RESPONSE = 3'd3, DATA_READY = 3'd4;
    reg [2:0] state;
    reg [13:0] held_addr;
    reg [7:0] held_data;

    // Request is a one-clock pulse on entry. Keeping WAIT_n low prevents the
    // T80 from completing T-state 2 until the synchronous response is latched.
    assign rom_read = (state == IDLE) && mem_rd && !io_rd && !reset;
    assign rom_addr = (state == IDLE) ? cpu_addr[13:0] : held_addr;
    assign wait_n = !(mem_rd && !io_rd) || state == DATA_READY;
    assign cpu_data = held_data;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= DRAIN_GUARD;
            held_addr <= 14'd0;
            held_data <= 8'hff;
        end else begin
            case (state)
                // Do not associate a late pre-reset valid response with the
                // first post-reset request. Require the port to be drained.
                // Allow the known one-cycle synchronous ROM response to
                // emerge, then wait until its valid pulse has drained.
                DRAIN_GUARD: state <= DRAIN_RESPONSE;
                DRAIN_RESPONSE: if (!rom_ready) state <= IDLE;
                IDLE: if (mem_rd && !io_rd) begin
                    held_addr <= cpu_addr[13:0];
                    state <= WAIT_RESPONSE;
                end
                WAIT_RESPONSE: if (rom_ready) begin
                    held_data <= rom_data;
                    state <= DATA_READY;
                end
                DATA_READY: if (!mem_rd || io_rd) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
