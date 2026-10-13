`timescale 1ns/1ps
module tb_fax_t65;
    reg clk=0, reset_n=0;
    always #5 clk=~clk;
    wire done_fax0,done_fax1,done_legacy;
    wire [7:0] zero_fax0,ram400_fax0,zero_fax1,ram400_fax1,zero_legacy,ram400_legacy;
    wire [4:0] bank_fax0,bank_fax1,bank_legacy;
    wire enabled_fax0,enabled_fax1,enabled_legacy;

    fax_t65_harness #(.STARTUP_CHECK(0),.IMAGE_READY(1)) fax_start0(
        .master_clock(clk),.reset_n(reset_n),.done(done_fax0),.ram_zero(zero_fax0),
        .ram_400(ram400_fax0),.question_bank(bank_fax0),.fax_enabled(enabled_fax0));
    fax_t65_harness #(.STARTUP_CHECK(1),.IMAGE_READY(1)) fax_start1(
        .master_clock(clk),.reset_n(reset_n),.done(done_fax1),.ram_zero(zero_fax1),
        .ram_400(ram400_fax1),.question_bank(bank_fax1),.fax_enabled(enabled_fax1));
    fax_t65_harness #(.STARTUP_CHECK(0),.IMAGE_READY(0)) legacy(
        .master_clock(clk),.reset_n(reset_n),.done(done_legacy),.ram_zero(zero_legacy),
        .ram_400(ram400_legacy),.question_bank(bank_legacy),.fax_enabled(enabled_legacy));

    integer cycles=0;
    initial begin
        repeat(8) @(negedge clk); reset_n=1;
        while(!(done_fax0 && done_fax1 && done_legacy) && cycles<20000) begin
            @(negedge clk); cycles++;
        end
        if(!(done_fax0 && done_fax1 && done_legacy))
            $fatal(1,"synthetic T65 programs did not complete: fax0=%b fax1=%b legacy=%b",done_fax0,done_fax1,done_legacy);
        repeat(8) @(negedge clk);

        if(!enabled_fax0 || !enabled_fax1 || enabled_legacy) $fatal(1,"validated-profile gate mismatch");
        if(zero_fax0!==8'hA5 || ram400_fax0!==8'h5A ||
           zero_fax1!==8'hA5 || ram400_fax1!==8'h5A)
            $fatal(1,"FAX 2 KiB RAM pages aliased or corrupted: %02x/%02x %02x/%02x",
                   zero_fax0,ram400_fax0,zero_fax1,ram400_fax1);
        if(fax_start0.work_ram[2]!==8'hA5 || fax_start0.work_ram[3]!==8'h5A ||
           fax_start1.work_ram[2]!==8'hA5 || fax_start1.work_ram[3]!==8'h5A)
            $fatal(1,"T65 did not read back independent 0000/0400 work RAM bytes");
        if(bank_fax0!==5'd3 || bank_fax1!==5'd3 || bank_legacy!==5'd0)
            $fatal(1,"question bank write was not qualified by FAX decode and PH_1");
        if(fax_start0.work_ram[4]!==8'hD3 || fax_start1.work_ram[4]!==8'hD3)
            $fatal(1,"T65 question-bank/window read returned the wrong bank byte");
        if(fax_start0.work_ram[5]!==8'hA9 || fax_start1.work_ram[5]!==8'hAD)
            $fatal(1,"P1 controls or IN3 startup-check selection mismatch: %02x/%02x",
                   fax_start0.work_ram[5],fax_start1.work_ram[5]);
        if(fax_start0.work_ram[6]!==8'h5F || fax_start1.work_ram[6]!==8'h5F)
            $fatal(1,"P2 answer-button read mismatch");
        if(zero_legacy!==8'hA5 || ram400_legacy!==8'h00 || legacy.work_ram[2]!==8'hA5 ||
           legacy.work_ram[3]!==8'h00 || legacy.work_ram[4]!==8'h00)
            $fatal(1,"legacy 1 KiB RAM or unbound question fallthrough changed");
        if(legacy.work_ram[5]!==8'hA6 || legacy.work_ram[6]!==8'hA6)
            $fatal(1,"non-FAX input reads did not fall through to legacy DIPs");

        $display("PASS actual T65 bytecode: FAX 2KiB RAM, bank/window, P1/P2, startup bit, legacy fallthrough; cycles=%0d",cycles);
        $finish;
    end
    initial begin #10000000; $fatal(1,"fax T65 watchdog"); end
endmodule
