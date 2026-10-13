`timescale 1ns/1ps
// Isolated FAX bank-select and CPU read-priority adapter.
// A containing Exidy2 read-data register supplies the final master-clock stage.
module faxQuestionWindow (
    input             fax_enabled,
    input             cpu_clk,
    input             cpu_reset_n,
    input      [15:0]  cpu_addr,
    input             cpu_read,
    input             cpu_write,
    input      [7:0]   cpu_write_data,
    input      [7:0]   question_data,
    input      [7:0]   other_read_data,
    output reg [4:0]   question_bank,
    output            question_read,
    output     [15:0]  question_cpu_addr,
    output            question_selected,
    output     [7:0]   read_data
);
    wire bank_write = fax_enabled && cpu_write && (cpu_addr == 16'h2000);
    wire in_question_window = fax_enabled && cpu_read &&
                              (cpu_addr >= 16'h2000) && (cpu_addr <= 16'h3fff);

    always @(posedge cpu_clk or negedge cpu_reset_n) begin
        if (!cpu_reset_n)
            question_bank <= 5'd0;
        else if (bank_write)
            question_bank <= cpu_write_data[4:0];
    end

    assign question_read = in_question_window;
    assign question_cpu_addr = cpu_addr;
    assign question_selected = in_question_window;
    assign read_data = in_question_window ? question_data : other_read_data;
endmodule
