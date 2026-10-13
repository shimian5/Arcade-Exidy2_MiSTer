`timescale 1ns/1ps
module tb_fax_question_window;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0, enabled = 0, rd = 0, wr = 0;
    reg [15:0] addr = 0;
    reg [7:0] wrdata = 0, question_data = 0, other_data = 8'ha5;
    reg [7:0] cpu_databus_in = 0;
    wire [4:0] bank;
    wire question_read, selected;
    wire [15:0] question_addr;
    wire [7:0] read_data;
    wire [7:0] expected_window_byte = (bank * 8'h25) ^ question_addr[7:0];
    integer checks = 0;

    faxQuestionWindow dut(
        .fax_enabled(enabled), .cpu_clk(clk), .cpu_reset_n(reset_n),
        .cpu_addr(addr), .cpu_read(rd), .cpu_write(wr), .cpu_write_data(wrdata),
        .question_data(question_data), .other_read_data(other_data),
        .question_bank(bank), .question_read(question_read), .question_cpu_addr(question_addr),
        .question_selected(selected), .read_data(read_data)
    );

    // Synchronous loader-RAM output plus Exidy2's existing bus-data register.
    always @(posedge clk) begin
        if (question_read) question_data <= expected_window_byte;
        cpu_databus_in <= read_data;
    end

    task automatic check(input logic ok, input string what);
        begin checks++; if(!ok) $fatal(1,"FAIL %s bank=%0d addr=%04x",what,bank,addr); end
    endtask
    task automatic write_bank(input [7:0] value);
        begin
            @(negedge clk); addr=16'h2000; wr=1; rd=0; wrdata=value;
            @(posedge clk); #1; wr=0;
        end
    endtask
    initial begin
        repeat(2) @(posedge clk); #1; reset_n=1; enabled=1;
        write_bank(8'h15); check(bank==5'h15,"selector latches MAME data[4:0]");
        write_bank(8'hf8); check(bank==5'h18,"selector preserves bank 24 for validity quarantine");
        addr=16'h2000; rd=1; #1; check(question_read && selected && question_addr==addr,"window includes first byte");
        question_data=8'h31; #1; check(read_data==8'h31,"question read outranks conflicting fallback");
        addr=16'h3fff; #1; check(question_read && question_addr==addr,"window includes final byte");
        addr=16'h4000; #1; check(!question_read && !selected && read_data==other_data,"window excludes next address");
        addr=16'h2000; rd=0; wr=0; #1; check(!question_read && read_data==other_data,"write/idle cycle does not read question ROM");
        enabled=0; rd=1; #1; check(!question_read && read_data==other_data,"non-FAX profile preserves ordinary ROM path");

        enabled=1;
        write_bank(8'h07);
        @(negedge clk); addr=16'h2123; rd=1; question_data=0; cpu_databus_in=0;
        @(posedge clk); #1;
        check(question_data==((8'h07 * 8'h25) ^ 8'h23) && cpu_databus_in==0,
              "synchronous question RAM supplies data one master edge before CPU bus register");
        @(posedge clk); #1;
        check(cpu_databus_in==((8'h07 * 8'h25) ^ 8'h23),
              "CPU bus register captures selected bank byte on following master edge");
        $display("PASS FAX question window checks=%0d",checks); $finish;
    end
endmodule


