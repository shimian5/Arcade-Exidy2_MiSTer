`timescale 1ns/1ps
module tb_fax_controls;
    reg fax_enabled = 1;
    reg [15:0] cpu_addr = 0;
    reg cpu_read = 0;
    reg [7:0] other_read_data = 8'h5a;
    reg [3:0] p1_answer_pressed = 0;
    reg [3:0] p2_answer_pressed = 0;
    reg p1_start1_pressed = 0;
    reg p1_start2_pressed = 0;
    wire fax_selected;
    wire [7:0] read_data;
    integer errors = 0;
    integer i;
    reg [7:0] expected;

    faxControls dut(
        .fax_enabled(fax_enabled),
        .cpu_addr(cpu_addr), .cpu_read(cpu_read), .other_read_data(other_read_data),
        .p1_answer_pressed(p1_answer_pressed), .p2_answer_pressed(p2_answer_pressed),
        .p1_start1_pressed(p1_start1_pressed), .p1_start2_pressed(p1_start2_pressed),
        .fax_selected(fax_selected), .read_data(read_data)
    );

    task automatic check(input bit condition, input string message);
        begin
            if (!condition) begin errors = errors + 1; $display("FAIL %s", message); end
        end
    endtask

    initial begin
        #1;
        check(!fax_selected && read_data == 8'h5a, "unselected address passes through");

        cpu_read = 1;
        cpu_addr = 16'h1c00;
        #1;
        check(fax_selected && read_data == 8'hff, "P1 idle port and selected address");
        for (i = 0; i < 4; i = i + 1) begin
            p1_answer_pressed = 4'b0001 << i;
            expected = 8'hff & ~(8'h80 >> i);
            #1;
            check(fax_selected && read_data == expected, "each P1 answer maps independently to bits 7 through 4");
        end

        p1_answer_pressed = 0;
        p1_start1_pressed = 1;
        #1;
        check(read_data == 8'hfd, "P1 Start 1 is active-low bit 1");
        p1_start1_pressed = 0;
        p1_start2_pressed = 1;
        #1;
        check(read_data == 8'hfe, "P1 Start 2 is active-low bit 0");
        p1_start1_pressed = 1;
        #1;
        check(read_data == 8'hfc, "P1 starts combine independently");

        p1_answer_pressed = 4'hf;
        #1;
        check(read_data == 8'h0c, "P1 answer combo preserves starts and unused bits");

        cpu_addr = 16'h1a00;
        p1_answer_pressed = 0;
        p1_start1_pressed = 0;
        p1_start2_pressed = 0;
        #1;
        check(fax_selected && read_data == 8'hff, "P2 idle port selected independently");
        for (i = 0; i < 4; i = i + 1) begin
            p2_answer_pressed = 4'b0001 << i;
            expected = 8'hff & ~(8'h80 >> i);
            #1;
            check(fax_selected && read_data == expected, "each P2 answer maps independently to bits 7 through 4");
        end
        p2_answer_pressed = 4'hf;
        #1;
        check(read_data == 8'h0f, "P2 answer combo leaves unused low nibble high");

        // Selected port data overrides a conflicting lower-priority RAM value.
        other_read_data = 8'h00;
        p2_answer_pressed = 0;
        #1;
        check(read_data == 8'hff, "FAX input read wins over conflicting fallback RAM data");

        // Exact address and read qualification: writes/unselected reads pass through.
        cpu_read = 0;
        #1;
        check(!fax_selected && read_data == 8'h00, "write cycle does not select FAX input");
        cpu_read = 1;
        cpu_addr = 16'h1a01;
        #1;
        check(!fax_selected && read_data == 8'h00, "neighbor address passes through");

        fax_enabled = 0;
        cpu_addr = 16'h1c00;
        other_read_data = 8'h5a;
        #1;
        check(!fax_selected && read_data == 8'h5a, "disabled FAX profile preserves ordinary reads");

        if (errors == 0) $display("PASS fax controls");
        else $fatal(1, "FAILED %0d", errors);
        $finish;
    end
endmodule
