`timescale 1ns/1ps
// Exact FAX image identity and validated question-storage gate for faxControls.
// Keep pcb[7:6] available for the existing Venture/FAX interrupt profile.
module faxProfileControls #(
    parameter STARTUP_CHECK = 1'b0
) (
    input             question_image_ready,
    input      [7:0]   pcb,
    input      [15:0]  cpu_addr,
    input             cpu_read,
    input      [7:0]   other_read_data,
    input      [3:0]   p1_answer_pressed,
    input      [3:0]   p2_answer_pressed,
    input             p1_start1_pressed,
    input             p1_start2_pressed,
    output            fax_enabled,
    output            fax_selected,
    output     [7:0]   read_data
);
    localparam [7:0] PCB_FAX  = 8'h74;
    localparam [7:0] PCB_FAX2 = 8'h78;

    wire profile_match = (pcb == PCB_FAX) || (pcb == PCB_FAX2);
    assign fax_enabled = question_image_ready && profile_match;

    faxControls #(.STARTUP_CHECK(STARTUP_CHECK)) controls (
        .fax_enabled(fax_enabled),
        .cpu_addr(cpu_addr),
        .cpu_read(cpu_read),
        .other_read_data(other_read_data),
        .p1_answer_pressed(p1_answer_pressed),
        .p2_answer_pressed(p2_answer_pressed),
        .p1_start1_pressed(p1_start1_pressed),
        .p1_start2_pressed(p1_start2_pressed),
        .fax_selected(fax_selected),
        .read_data(read_data)
    );
endmodule
