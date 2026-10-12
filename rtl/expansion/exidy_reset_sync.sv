`timescale 1ns/1ps
// Per-domain reset conditioner: asynchronous assertion, synchronized release.
// Identify the actual local registers directly: Quartus 17 does not resolve
// the bare instance-path QSF patterns used by the isolated probe.
module exidy_reset_sync #(parameter int STAGES = 2) (
    input  logic clk,
    input  logic reset_n,      // asynchronous, active-low source (any domain)
    output logic reset_n_sync  // asserts with no clock; releases STAGES edges after reset_n
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic rst_meta;
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED" *) logic rst_sync;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rst_meta <= 1'b0;
            rst_sync <= 1'b0;
        end else begin
            rst_meta <= 1'b1;
            rst_sync <= rst_meta;
        end
    end
    assign reset_n_sync = rst_sync;
endmodule

// Negative control: release is not synchronized to the destination clock.
module exidy_reset_sync_unsafe (
    input  logic clk,
    input  logic reset_n,
    output logic reset_n_sync
);
    assign reset_n_sync = reset_n;
endmodule
