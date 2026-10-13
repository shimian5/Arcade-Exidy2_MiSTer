`timescale 1ns/1ps
// Unbound FAX/FAX 2 question-image wrapper around the candidate session loader.
// Marker bytes are consumed by the loader; the shared core's PCB normalization
// remains a separate top-level integration responsibility.
module faxExpansionWrapper (
    input  logic        clk,
    input  logic        reset_n,
    input  logic        transfer_begin,
    input  logic        transfer_end,
    input  logic        ioctl_wr,
    input  logic [7:0]  ioctl_index,
    input  logic [23:0] ioctl_addr,
    input  logic [7:0]  ioctl_data,

    output wire         legacy_base_wr,
    output wire         reset_hold,
    output wire         expansion_ready,
    output wire         question_image_ready,
    output wire [7:0]   active_profile,
    output wire         protocol_fault,

    input  logic        question_read,
    input  logic [4:0]  question_bank,
    input  logic [15:0] question_cpu_addr,
    output wire [7:0]   question_data,
    output wire         question_valid
);
    wire [7:0] unused_cvsd_data;
    wire unused_cvsd_valid;
    wire loader_question_valid;

    assign question_image_ready = expansion_ready && !protocol_fault &&
                                  ((active_profile == 8'd1) || (active_profile == 8'd2));
    assign question_valid = question_image_ready && loader_question_valid;

    fax_exidy_expansion_loader loader (
        .clk(clk),
        .reset_n(reset_n),
        .cvsd_reset_n(reset_n),
        .transfer_begin(transfer_begin),
        .transfer_end(transfer_end),
        .ioctl_wr(ioctl_wr),
        .ioctl_index(ioctl_index),
        .ioctl_addr(ioctl_addr),
        .ioctl_data(ioctl_data),
        .legacy_base_wr(legacy_base_wr),
        .reset_hold(reset_hold),
        .expansion_ready(expansion_ready),
        .protocol_fault(protocol_fault),
        .active_profile(active_profile),
        .question_read(question_read),
        .question_bank(question_bank),
        .question_cpu_addr(question_cpu_addr),
        .question_data(question_data),
        .question_valid(loader_question_valid),
        .cvsd_clk(clk),
        .cvsd_read(1'b0),
        .cvsd_addr(14'd0),
        .cvsd_data(unused_cvsd_data),
        .cvsd_valid(unused_cvsd_valid)
    );
endmodule
