`timescale 1ns/1ps
// Standalone FAX/FAX 2 answer-button input decoder candidate.
// The core must give this selected read data priority over RAM/ROM reads.
module faxControls (
	input             fax_enabled,
    input      [15:0] cpu_addr,
    input             cpu_read,
    input      [7:0]  other_read_data,
    input      [3:0]  p1_answer_pressed,
    input      [3:0]  p2_answer_pressed,
    input             p1_start1_pressed,
    input             p1_start2_pressed,
    output            fax_selected,
    output     [7:0]  read_data
);

    wire p1_select = fax_enabled && cpu_read && (cpu_addr == 16'h1c00);
    wire p2_select = fax_enabled && cpu_read && (cpu_addr == 16'h1a00);

    wire [7:0] p1_data = {
        ~p1_answer_pressed[0],
        ~p1_answer_pressed[1],
        ~p1_answer_pressed[2],
        ~p1_answer_pressed[3],
        2'b11,
        ~p1_start1_pressed,
        ~p1_start2_pressed
    };
    wire [7:0] p2_data = {
        ~p2_answer_pressed[0],
        ~p2_answer_pressed[1],
        ~p2_answer_pressed[2],
        ~p2_answer_pressed[3],
        4'b1111
    };

    assign fax_selected = p1_select | p2_select;
    assign read_data = p1_select ? p1_data : p2_select ? p2_data : other_read_data;

endmodule
