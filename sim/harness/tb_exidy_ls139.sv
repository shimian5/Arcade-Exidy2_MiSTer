`timescale 1ns/1ps

// Smoke fixture for the production 2-to-4 decoder used by Exidy2.
module tb_exidy_ls139;
    logic a = 0;
    logic b = 0;
    logic n_g = 1;
    wire [3:0] y;
    integer checks = 0;

    ls139 dut (.a(a), .b(b), .n_g(n_g), .y(y));

    task automatic expect_y(input logic [3:0] expected, input string label);
        #1;
        if (y !== expected)
            $fatal(1, "%s: expected y=%b, got y=%b", label, expected, y);
        checks++;
    endtask

    initial begin
        expect_y(4'b1111, "disabled, select 00");
        n_g = 0; a = 0; b = 0; expect_y(4'b1110, "select 00");
        a = 1; b = 0; expect_y(4'b1101, "select 01");
        a = 0; b = 1; expect_y(4'b1011, "select 10");
        a = 1; b = 1; expect_y(4'b0111, "select 11");
        n_g = 1; expect_y(4'b1111, "disabled, select 11");
        $display("PASS tb_exidy_ls139 checks=%0d", checks);
        $finish;
    end
endmodule
