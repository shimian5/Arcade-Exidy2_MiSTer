`timescale 1ns/1ps
module tb_fax_profile_controls;
    reg ready = 0;
    reg [7:0] pcb = 0;
    reg [15:0] addr = 16'h1c00;
    reg rd = 1;
    reg [7:0] fallback = 8'h35;
    reg [3:0] p1 = 0, p2 = 0;
    reg start1 = 0, start2 = 0;
    wire enabled, selected;
    wire [7:0] data;
    integer checks = 0;

    faxProfileControls dut (
        .question_image_ready(ready), .pcb(pcb), .cpu_addr(addr), .cpu_read(rd),
        .other_read_data(fallback), .p1_answer_pressed(p1), .p2_answer_pressed(p2),
        .p1_start1_pressed(start1), .p1_start2_pressed(start2),
        .fax_enabled(enabled), .fax_selected(selected), .read_data(data)
    );

    task automatic check(input logic ok, input string what);
        begin
            checks++;
            if (!ok) $fatal(1, "FAIL %s pcb=%02x ready=%b data=%02x", what, pcb, ready, data);
        end
    endtask

    initial begin
        #1; check(!enabled && !selected && data == 8'h35, "unready image passes ordinary read");
        ready = 1; #1; check(!enabled && !selected && data == 8'h35, "unknown image passes ordinary read");
        pcb = 8'h50; #1; check(!enabled && data == 8'h35, "Venture interrupt profile is not FAX");
        pcb = 8'hd0; #1; check(!enabled && data == 8'h35, "Teeter profile is not FAX");
        pcb = 8'h74; #1; check(enabled && selected && data == 8'hfb, "FAX idle P1 read includes low diagnostic startup bit 2");
        for (integer i = 0; i < 4; i++) begin
            p1 = 4'b0001 << i; #1;
            check(data == (8'hfb ^ (8'h80 >> i)), "FAX answer button maps to MAME IN3 bit");
        end
        p1 = 0; start1 = 1; #1; check(data == 8'hf9, "Start 1P clears IN3 bit 1 while startup bit 2 stays low");
        start1 = 0; start2 = 1; #1; check(data == 8'hfa, "Start 2P clears IN3 bit 0 while startup bit 2 stays low");
        addr = 16'h1a00; p2 = 4'b0101; #1; check(data == 8'h5f, "P2 answer buttons use independent IN4 byte");
        rd = 0; #1; check(!selected && data == fallback, "write cycle passes through");
        rd = 1; addr = 16'h1c01; #1; check(!selected && data == fallback, "neighbor address passes through");
        addr = 16'h1c00; pcb = 8'h78; #1; check(enabled && selected, "FAX 2 exact identity enables controls");
        ready = 0; #1; check(!enabled && !selected && data == fallback, "reload clears input gate until loader ready");
        start2 = 0;
        ready = 1; pcb = 8'h74; #1; check(enabled && data == 8'hfb, "revalidated FAX image restores idle read");
        $display("PASS fax profile controls checks=%0d", checks);
        $finish;
    end
endmodule






