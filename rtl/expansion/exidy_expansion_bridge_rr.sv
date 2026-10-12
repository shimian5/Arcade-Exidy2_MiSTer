`timescale 1ns/1ps
// Isolated integration candidate: ordinary ioctl transport plus session loader.
// Core CPU/board and production framework are deliberately not instantiated.
// Candidate: per-domain reset conditioning (increment 14). Raw reset_n is only
// an asynchronous source; every sequential block sees a domain-synchronized copy.
module exidy_expansion_bridge_rr (
    input logic clk, reset_n, cvsd_clk,
    input logic raw_download, raw_wr,
    input logic [15:0] raw_index,
    input logic [26:0] raw_addr,
    input logic [7:0] raw_data,
    input logic question_read,
    input logic [4:0] question_bank,
    input logic [15:0] question_cpu_addr,
    input logic cvsd_read,
    input logic [13:0] cvsd_addr,
    output wire [7:0] question_data, cvsd_data, active_profile,
    output wire question_valid, cvsd_valid,
    output wire ioctl_wait, legacy_base_wr, reset_hold, expansion_ready,
    output wire adapter_fault, protocol_fault,
    // Accepted legacy bus and instrumentation for the isolated fixture.
    output wire ioctl_wr, transfer_begin, transfer_end, transfer_active,
    output wire [7:0] ioctl_index, ioctl_data,
    output wire [23:0] ioctl_addr,
    output wire quarantine_request, quarantine_generation, read_accept,
    output wire cvsd_quarantine_ack, cvsd_ack_generation
);
    wire transport_quarantine_request, loader_reset_hold;
    wire reset_n_main, reset_n_cvsd;
    exidy_reset_sync main_reset(.clk(clk),.reset_n(reset_n),.reset_n_sync(reset_n_main));
    exidy_reset_sync cvsd_reset(.clk(cvsd_clk),.reset_n(reset_n),.reset_n_sync(reset_n_cvsd));
    wire speech_verdict_pending = (ioctl_index == 8'd6) &&
                                  (raw_download || transfer_active || transfer_begin || transfer_end);
    // A transport byte count alone cannot accept a descriptor/session. Keep
    // remote reads revoked until the loader also accepts the complete image.
    assign quarantine_request = transport_quarantine_request || loader_reset_hold ||
                                protocol_fault || adapter_fault || !expansion_ready || speech_verdict_pending;
    // End stays asserted through the edge on which the loader commits the
    // session. This avoids releasing the core one edge before its verdict.
    assign reset_hold = raw_download || transfer_active || transfer_begin ||
                        transfer_end || loader_reset_hold || adapter_fault ||
                        !reset_n_main;
    exidy_transport_adapter transport(
        .reset_n(reset_n_main),.quarantine_request(transport_quarantine_request),.*);
    exidy_cvsd_read_quarantine remote(
        .reset_n(reset_n_cvsd),.read_request(cvsd_read),.quarantine_ack(cvsd_quarantine_ack),
        .ack_generation(cvsd_ack_generation),.*);
    exidy_expansion_loader loader(
        .reset_n(reset_n_main),.cvsd_reset_n(reset_n_cvsd),.reset_hold(loader_reset_hold),.cvsd_read(read_accept),.*);
endmodule
