`timescale 1ns/1ps
module tb_exidy_expansion_loader;
    logic clk = 0;
    logic cvsd_clk = 0;
    always #5 clk = ~clk;
    always #7 cvsd_clk = ~cvsd_clk;

    logic reset_n = 0;
    logic transfer_begin = 0;
    logic transfer_end = 0;
    logic ioctl_wr = 0;
    logic [7:0] ioctl_index = 0;
    logic [23:0] ioctl_addr = 0;
    logic [7:0] ioctl_data = 0;
    wire legacy_base_wr;
    wire reset_hold;
    wire expansion_ready;
    wire protocol_fault;
    wire [7:0] active_profile;
    logic question_read = 0;
    logic [4:0] question_bank = 0;
    logic [15:0] question_cpu_addr = 0;
    wire [7:0] question_data;
    wire question_valid;
    logic cvsd_read = 0;
    logic [13:0] cvsd_addr = 0;
    wire [7:0] cvsd_data;
    wire cvsd_valid;

    // Faithful timing fixture for Exidy2's 64-master-clock T65 enable and
    // registered CPU_databus_in. T65 samples the previous registered input.
    logic [5:0] cencnt = 0;
    logic ph_1 = 0;
    logic [7:0] cpu_databus_in = 0;
    logic [7:0] sampled_cpu_data = 0;
    integer cpu_sample_count = 0;
    integer old_count;
    always @(posedge clk) begin
        cencnt <= cencnt + 1'b1;
        ph_1 <= (cencnt == 6'd31);
        cpu_databus_in <= question_data;
        if (ph_1) begin
            sampled_cpu_data <= cpu_databus_in;
            cpu_sample_count <= cpu_sample_count + 1;
        end
    end

    exidy_expansion_loader dut (.*);

    task automatic begin_xfer(input logic [7:0] index);
        begin
            @(negedge clk); ioctl_index = index; transfer_begin = 1;
            @(negedge clk); transfer_begin = 0;
        end
    endtask

    task automatic put_byte(input logic [23:0] addr, input logic [7:0] data);
        begin
            @(negedge clk); ioctl_wr = 1; ioctl_addr = addr; ioctl_data = data;
            #1;
            if ((ioctl_index == 8'd0) && !legacy_base_wr)
                $fatal(1, "index-0 legacy write was not forwarded live");
            @(negedge clk); ioctl_wr = 0;
        end
    endtask

    task automatic end_xfer;
        begin
            @(negedge clk); transfer_end = 1;
            @(negedge clk); transfer_end = 0;
        end
    endtask

    task automatic send_byte_xfer(input logic [7:0] index, input logic [7:0] value);
        begin
            begin_xfer(index); put_byte(0, value); end_xfer();
        end
    endtask

    function automatic logic [7:0] qpattern(input integer offset);
        qpattern = 8'(((offset >> 13) * 37) ^ (offset & 255) ^ ((offset >> 8) & 31));
    endfunction

    task automatic cpu_read_stable(input logic [4:0] bank, input logic [12:0] low_addr,
                                   input logic [7:0] expected);
        integer old_count;
        begin
            old_count = cpu_sample_count;
            wait (cpu_sample_count != old_count);
            @(negedge clk); question_bank = bank; question_cpu_addr = {3'b001, low_addr}; question_read = 1;
            @(negedge clk); question_read = 0;
            old_count = cpu_sample_count;
            wait (cpu_sample_count != old_count);
            if (sampled_cpu_data != expected)
                $fatal(1, "stable T65 read bank=%0d low=%h got=%h expected=%h", bank, low_addr, sampled_cpu_data, expected);
        end
    endtask

    task automatic send_descriptor_mtrap;
        logic [7:0] d [0:15];
        integer i;
        begin
            // Independent literal: EX v1, profile 3, slots 0+6 mask=05,
            // base length=1, q length=0, CVSD length=0x4000, reserved=0.
            d[0]=8'h45; d[1]=8'h58; d[2]=8'h01; d[3]=8'h03;
            d[4]=8'h05; d[5]=8'h01; d[6]=8'h00; d[7]=8'h00;
            d[8]=8'h00; d[9]=8'h00; d[10]=8'h00;
            d[11]=8'h00; d[12]=8'h40; d[13]=8'h00;
            d[14]=8'h00; d[15]=8'h00;
            begin_xfer(8'd7);
            for (i=0; i<16; i=i+1) put_byte(i[23:0], d[i]);
            end_xfer();
        end
    endtask

    task automatic send_descriptor_fax;
        logic [7:0] d [0:15];
        integer i;
        begin
            // Independent literal: FAX profile, mask=03, base length=1,
            // 192-KiB questions, no CVSD.
            d[0]=8'h45; d[1]=8'h58; d[2]=8'h01; d[3]=8'h01;
            d[4]=8'h03; d[5]=8'h01; d[6]=8'h00; d[7]=8'h00;
            d[8]=8'h00; d[9]=8'h00; d[10]=8'h03;
            d[11]=8'h00; d[12]=8'h00; d[13]=8'h00;
            d[14]=8'h00; d[15]=8'h00;
            begin_xfer(8'd7);
            for (i=0; i<16; i=i+1) put_byte(i[23:0], d[i]);
            end_xfer();
        end
    endtask

    task automatic send_bad_fax_descriptor(input integer field, input logic [7:0] value);
        logic [7:0] d [0:15];
        integer j;
        begin
            d[0]=8'h45; d[1]=8'h58; d[2]=8'h01; d[3]=8'h01;
            d[4]=8'h03; d[5]=8'h01; d[6]=8'h00; d[7]=8'h00;
            d[8]=8'h00; d[9]=8'h00; d[10]=8'h03;
            d[11]=8'h00; d[12]=8'h00; d[13]=8'h00;
            d[14]=8'h00; d[15]=8'h00;
            d[field] = value;
            begin_xfer(8'd7);
            for (j=0; j<16; j=j+1) put_byte(j[23:0], d[j]);
            end_xfer();
        end
    endtask

    task automatic recover_legacy;
        begin
            begin_xfer(8'd0); put_byte(0, 8'h63); end_xfer();
            send_byte_xfer(8'd1, 8'h30);
            if (reset_hold || protocol_fault || expansion_ready)
                $fatal(1, "legacy recovery did not clear extension state");
        end
    endtask

    integer i;
    initial begin
        repeat (4) @(negedge clk);
        reset_n = 1;

        // Valid synthetic Mouse Trap transfer; all payload bytes are generated
        // in the testbench and are not ROM data.
        send_byte_xfer(8'd1, 8'h90);
        if (!reset_hold) $fatal(1, "marker did not hold reset");
        send_descriptor_mtrap();
        send_byte_xfer(8'd0, 8'h42);
        begin_xfer(8'd6);
        for (i=0; i<16384; i=i+1) put_byte(i[23:0], 8'(((i >> 12) * 53) ^ (i & 255)));
        end_xfer();
        if (!expansion_ready || reset_hold || active_profile != 8'd3)
            $fatal(1, "CVSD completion/readiness failed");

        // Wait for two-flop ready synchronization and verify an independent
        // asynchronous clock-domain read from the last CVSD byte.
        repeat (5) @(negedge cvsd_clk);
        @(negedge cvsd_clk); cvsd_addr = 14'h3fff; cvsd_read = 1;
        @(negedge cvsd_clk); cvsd_read = 0;
        if (!cvsd_valid || cvsd_data != 8'h60) $fatal(1, "CVSD dual-clock byte mismatch");

        // A trailing options stream is a fresh download but preserves ready data.
        send_byte_xfer(8'd2, 8'h37);
        if (!expansion_ready || reset_hold) $fatal(1, "index 2 invalidated complete extension");

        // A later invalid transport event must revoke the independent CVSD
        // readiness gate and propagate low through its two synchronizer stages.
        send_byte_xfer(8'd9, 8'h99);
        if (!reset_hold || expansion_ready) $fatal(1, "unknown index did not fault");
        repeat (5) @(negedge cvsd_clk);
        @(negedge cvsd_clk); cvsd_addr = 14'h3fff; cvsd_read = 1;
        @(negedge cvsd_clk); cvsd_read = 0;
        if (cvsd_valid) $fatal(1, "CVSD readiness stayed asserted after protocol fault");
        begin_xfer(8'd0); put_byte(0, 8'h49); end_xfer();
        send_byte_xfer(8'd1, 8'h30);
        if (reset_hold || protocol_fault) $fatal(1, "legacy recovery after CVSD fault failed");

        // New FAX marker invalidates old extension data; exact full store is then loaded.
        send_byte_xfer(8'd1, 8'hb0);
        if (!reset_hold || expansion_ready) $fatal(1, "fresh marker failed to invalidate stale image");
        send_descriptor_fax();
        send_byte_xfer(8'd0, 8'h46);
        begin_xfer(8'd5);
        for (i=0; i<196608; i=i+1) put_byte(i[23:0], qpattern(i));
        end_xfer();
        if (!expansion_ready || reset_hold || active_profile != 8'd1)
            $fatal(1, "FAX completion/readiness failed");

        // Bank-sensitive data checks defeat mirrored/ignored bank-select bugs.
        cpu_read_stable(0, 13'h000, qpattern(0));
        cpu_read_stable(1, 13'h000, qpattern(8192));
        cpu_read_stable(21, 13'h1fff, qpattern(22*8192-1));
        cpu_read_stable(22, 13'h000, qpattern(22*8192));
        cpu_read_stable(23, 13'h1fff, qpattern(24*8192-1));
        if (qpattern(0) != 8'h00 || qpattern(8192) != 8'h25 ||
            qpattern(22*8192-1) != 8'he9 || qpattern(22*8192) != 8'h2e ||
            qpattern(24*8192-1) != 8'hb3)
            $fatal(1, "bank-sensitive fixture literals changed");

        // Bank 24 is explicitly returned as zero pending separate parity proof.
        @(negedge clk); question_bank=24; question_cpu_addr=16'h2000; question_read=1;
        @(negedge clk); question_read=0;
        if (!question_valid || question_data != 8'h00) $fatal(1, "bank 24 fill mismatch");

        // At 62/63 clocks after T65 enable, changing the address is too late:
        // the upcoming sample returns the previous byte. A later enable sees B.
        cpu_read_stable(0, 13'h000, qpattern(0));
        wait (ph_1);
        repeat (61) @(negedge clk);
        @(negedge clk); question_bank=1; question_cpu_addr=16'h2000; question_read=1;
        @(negedge clk); question_read=0;
        @(negedge clk);
        if (sampled_cpu_data == qpattern(8192)) $fatal(1, "deadline-negative case unexpectedly captured new byte");
        old_count = cpu_sample_count;
        wait (cpu_sample_count != old_count);
        if (sampled_cpu_data != qpattern(8192)) $fatal(1, "next T65 enable did not capture settled byte");

        // Existing legacy order is base first, then PCB index. Index 0 must be
        // live through its original port and must clear old expansion readiness.
        begin_xfer(8'd0);
        put_byte(0, 8'h4c); end_xfer();
        if (expansion_ready) $fatal(1, "legacy base did not clear extension readiness");
        send_byte_xfer(8'd1, 8'h30);
        if (reset_hold || expansion_ready) $fatal(1, "legacy index 1 recovery failed");

        // Malformed/gapped question transfer faults and holds reset.
        send_byte_xfer(8'd1, 8'hb0);
        send_descriptor_fax();
        send_byte_xfer(8'd0, 8'h46);
        begin_xfer(8'd5);
        put_byte(0, 8'h00);
        put_byte(2, 8'h02); // duplicate/hole instead of address 1
        end_xfer();
        if (!reset_hold || !protocol_fault || expansion_ready)
            $fatal(1, "gapped stream did not fail closed");

        // Recovery uses the real legacy order and cannot rely on resetting the
        // downloaded base bytes: index 0 is forwarded live, then index 1 clears.
        begin_xfer(8'd0); put_byte(0, 8'h5a); end_xfer();
        if (reset_hold) $fatal(1, "legacy base recovery failed pending=%0b fault=%0b armed=%0b active=%0b", dut.extended_pending, protocol_fault, dut.extended_armed, dut.transfer_active);
        send_byte_xfer(8'd1, 8'h10);
        if (reset_hold || protocol_fault) $fatal(1, "legacy PCB did not clear prior fault");

        // New marker with an aborted empty transfer must fail closed.
        begin_xfer(8'd1); end_xfer();
        if (!reset_hold || !protocol_fault) $fatal(1, "empty marker transfer was accepted");
        begin_xfer(8'd0); put_byte(0, 8'h61); end_xfer();
        send_byte_xfer(8'd1, 8'h30);

        // Literal descriptor corruption (wrong version) must not arm/ready.
        send_byte_xfer(8'd1, 8'hb0);
        send_bad_fax_descriptor(2, 8'h02);
        if (!reset_hold || !protocol_fault || expansion_ready)
            $fatal(1, "malformed descriptor was accepted");

        // A new legacy base followed by PCB recovers; an unarmed late payload
        // then faults rather than silently retaining the preceding image.
        begin_xfer(8'd0); put_byte(0, 8'h62); end_xfer();
        send_byte_xfer(8'd1, 8'h30);
        begin_xfer(8'd5); put_byte(0, 8'hff); end_xfer();
        if (!reset_hold || !protocol_fault || expansion_ready)
            $fatal(1, "stray payload did not fail closed");

        // Descriptor validation matrix: profile, mask, declared base length,
        // and reserved bytes all reject independently, then legacy recovery works.
        recover_legacy(); send_byte_xfer(8'd1, 8'hb0);
        send_bad_fax_descriptor(3, 8'h04);
        if (!reset_hold || !protocol_fault) $fatal(1, "unsupported profile accepted");
        recover_legacy(); send_byte_xfer(8'd1, 8'hb0);
        send_bad_fax_descriptor(4, 8'h05);
        if (!reset_hold || !protocol_fault) $fatal(1, "wrong stream mask accepted");
        recover_legacy(); send_byte_xfer(8'd1, 8'hb0);
        send_bad_fax_descriptor(5, 8'h00);
        if (!reset_hold || !protocol_fault) $fatal(1, "zero base length accepted");
        recover_legacy(); send_byte_xfer(8'd1, 8'hb0);
        send_bad_fax_descriptor(14, 8'h01);
        if (!reset_hold || !protocol_fault) $fatal(1, "nonzero reserved byte accepted");

        // Nested begin is a protocol fault. A later base/PCB recovery is required.
        recover_legacy();
        begin_xfer(8'd1); begin_xfer(8'd1); end_xfer();
        if (!reset_hold || !protocol_fault) $fatal(1, "nested transfer begin accepted");
        recover_legacy();

        // A duplicate completed base faults the session; even a subsequent
        // complete question stream cannot clear that fault or expose readiness.
        send_byte_xfer(8'd1, 8'hb0);
        send_descriptor_fax();
        send_byte_xfer(8'd0, 8'h46);
        send_byte_xfer(8'd0, 8'h47);
        if (!reset_hold || !protocol_fault || expansion_ready)
            $fatal(1, "duplicate base did not fault");
        begin_xfer(8'd5);
        for (i=0; i<196608; i=i+1) put_byte(i[23:0], qpattern(i));
        end_xfer();
        if (!reset_hold || !protocol_fault || expansion_ready)
            $fatal(1, "payload completion cleared prior base fault");

        $display("PASS: expansion loader transport and main/CVSD read fixture");
        $finish;
    end
endmodule
