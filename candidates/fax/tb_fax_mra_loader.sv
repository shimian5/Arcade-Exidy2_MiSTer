`timescale 1ns/1ps
module tb_fax_mra_loader;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset_n = 0;
    reg transfer_begin = 0, transfer_end = 0, ioctl_wr = 0;
    reg [7:0] ioctl_index = 0, ioctl_data = 0;
    reg [23:0] ioctl_addr = 0;
    reg question_read = 0;
    reg [4:0] question_bank = 0;
    reg [15:0] question_cpu_addr = 0;
    wire legacy_base_wr, reset_hold, expansion_ready, question_image_ready, protocol_fault;
    wire [7:0] active_profile, question_data;
    wire question_valid;
    reg [7:0] base_rom [0:84543];
    reg [7:0] question_rom [0:196607];
    reg [7:0] marker_rom [0:0];
    reg [7:0] descriptor_rom [0:15];
    reg [7:0] options_rom [0:0];
    reg [7:0] stream_order [0:4];
    reg [7:0] cvsd_rom [0:16383];
    reg [7:0] cpu_databus_in = 0;
    integer base_bytes_seen = 0;
    integer base_bytes_this_stream = 0;
    integer checks = 0;
    reg [7:0] profile = 0;
    string image_dir, set_name, filename;

    faxExpansionWrapper dut (
        .clk(clk), .reset_n(reset_n),
        .transfer_begin(transfer_begin), .transfer_end(transfer_end),
        .ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data),
        .legacy_base_wr(legacy_base_wr), .reset_hold(reset_hold), .expansion_ready(expansion_ready),
        .question_image_ready(question_image_ready), .active_profile(active_profile), .protocol_fault(protocol_fault),
        .question_read(question_read), .question_bank(question_bank), .question_cpu_addr(question_cpu_addr),
        .question_data(question_data), .question_valid(question_valid)
    );

    always @(posedge clk) begin
        cpu_databus_in <= question_data;
        if (transfer_begin && (ioctl_index == 8'd0)) base_bytes_this_stream <= 0;
        if (legacy_base_wr) begin
            if (ioctl_addr != 24'(base_bytes_this_stream) || ioctl_data !== base_rom[base_bytes_this_stream])
                $fatal(1, "MRA base tuple %0d mismatch addr=%0d data=%02x", base_bytes_this_stream, ioctl_addr, ioctl_data);
            base_bytes_seen++;
            base_bytes_this_stream++;
        end
    end

    task automatic check(input logic ok, input string label);
        begin
            checks++;
            if (!ok) $fatal(1, "FAIL %s profile=%0d active=%0d ready=%b hold=%b fault=%b",
                            label, profile, active_profile, question_image_ready, reset_hold, protocol_fault);
        end
    endtask

    function automatic integer stream_length(input [7:0] index);
        case (index)
            8'd0: stream_length = 84544;
            8'd1: stream_length = 1;
            8'd2: stream_length = 1;
            8'd5: stream_length = 196608;
            8'd6: stream_length = 16384;
            8'd7: stream_length = 16;
            default: stream_length = 0;
        endcase
    endfunction

    function automatic [7:0] image_byte(input [7:0] index, input integer address);
        case (index)
            8'd0: image_byte = base_rom[address];
            8'd1: image_byte = marker_rom[address];
            8'd2: image_byte = options_rom[address];
            8'd5: image_byte = question_rom[address];
            8'd7: image_byte = descriptor_rom[address];
            default: image_byte = 8'h00;
        endcase
    endfunction

    task automatic begin_stream(input [7:0] index);
        begin
            @(negedge clk); transfer_begin = 1; ioctl_index = index; ioctl_addr = 0; ioctl_wr = 0;
            @(negedge clk); transfer_begin = 0;
        end
    endtask

    task automatic end_stream;
        begin
            @(negedge clk); ioctl_wr = 0; transfer_end = 1;
            @(negedge clk); transfer_end = 0;
            @(posedge clk); #1;
        end
    endtask

    task automatic send_index(input [7:0] index);
        integer length;
        begin
            length = stream_length(index);
            if (length == 0) $fatal(1, "unsupported MRA index %0d", index);
            begin_stream(index);
            for (integer i = 0; i < length; i++) begin
                @(negedge clk); ioctl_wr = 1; ioctl_addr = 24'(i); ioctl_data = image_byte(index, i);
            end
            end_stream();
        end
    endtask

    task automatic send_marker(input [7:0] value);
        begin_stream(8'd1);
        @(negedge clk); ioctl_wr = 1; ioctl_addr = 0; ioctl_data = value;
        end_stream();
    endtask

    task automatic send_descriptor(input integer override_profile);
        begin
            begin_stream(8'd7);
            for (integer i = 0; i < 16; i++) begin
                @(negedge clk); ioctl_wr = 1; ioctl_addr = 24'(i);
                ioctl_data = (i == 3) ? 8'(override_profile) : descriptor_rom[i];
            end
            end_stream();
        end
    endtask

    task automatic send_speech_descriptor;
        reg [7:0] bytes [0:15];
        begin
            bytes = '{8'h45,8'h58,8'h01,8'h03,8'h05,8'h01,8'h00,8'h00,
                      8'h00,8'h00,8'h00,8'h00,8'h40,8'h00,8'h00,8'h00};
            begin_stream(8'd7);
            for (integer i = 0; i < 16; i++) begin
                @(negedge clk); ioctl_wr = 1; ioctl_addr = 24'(i); ioctl_data = bytes[i];
            end
            end_stream();
        end
    endtask

    task automatic send_speech_base;
        begin_stream(8'd0);
        @(negedge clk); ioctl_wr = 1; ioctl_addr = 0; ioctl_data = base_rom[0];
        end_stream();
    endtask

    task automatic send_speech_rom;
        begin
            begin_stream(8'd6);
            for (integer i = 0; i < 16384; i++) begin
                @(negedge clk); ioctl_wr = 1; ioctl_addr = 24'(i); ioctl_data = 8'((i * 19) ^ (i >> 5));
            end
            end_stream();
        end
    endtask

    task automatic read_question(input integer bank, input integer offset);
        integer expected_offset;
        begin
            expected_offset = bank * 8192 + offset;
            @(negedge clk); question_read = 1; question_bank = 5'(bank);
            question_cpu_addr = 16'(16'h2000 + offset);
            @(posedge clk); #1;
            if (!question_valid || question_data !== question_rom[expected_offset])
                $fatal(1, "question bank read mismatch bank=%0d offset=%04x got=%02x expected=%02x",
                       bank, offset, question_data, question_rom[expected_offset]);
            @(posedge clk); #1;
            if (cpu_databus_in !== question_rom[expected_offset])
                $fatal(1, "CPU bus pipeline mismatch bank=%0d offset=%04x got=%02x expected=%02x",
                       bank, offset, cpu_databus_in, question_rom[expected_offset]);
            checks++;
            @(negedge clk); question_read = 0;
        end
    endtask

    task automatic run_question_profile;
        begin
            for (integer i = 0; i < 196608; i++)
                if (dut.loader.question_mem[i] !== question_rom[i])
                    $fatal(1, "loaded question byte mismatch offset=%0d", i);
            for (integer bank = 0; bank < 24; bank++) begin
                read_question(bank, 0);
                read_question(bank, 8191);
            end
            for (integer invalid_bank = 24; invalid_bank < 32; invalid_bank++) begin
                @(negedge clk); question_read = 1; question_bank = 5'(invalid_bank);
                question_cpu_addr = 16'h2000;
                @(posedge clk); #1;
                check(question_valid && question_data == 0,
                      "out-of-region bank returns deterministic quarantine zero");
                @(negedge clk); question_read = 0;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("IMAGE_DIR=%s", image_dir)) $fatal(1, "IMAGE_DIR missing");
        if (!$value$plusargs("SET=%s", set_name)) $fatal(1, "SET missing");
        filename = $sformatf("%s/%s_index0.mem", image_dir, set_name); $readmemh(filename, base_rom);
        filename = $sformatf("%s/%s_index1.mem", image_dir, set_name); $readmemh(filename, marker_rom);
        filename = $sformatf("%s/%s_index2.mem", image_dir, set_name); $readmemh(filename, options_rom);
        filename = $sformatf("%s/%s_index5.mem", image_dir, set_name); $readmemh(filename, question_rom);
        filename = $sformatf("%s/%s_index7.mem", image_dir, set_name); $readmemh(filename, descriptor_rom);
        filename = $sformatf("%s/%s_order.mem", image_dir, set_name); $readmemh(filename, stream_order);
        profile = descriptor_rom[3];
        repeat (3) @(negedge clk); reset_n = 1;

        for (integer i = 0; i < 5; i++) send_index(stream_order[i]);
        check(question_image_ready && expansion_ready && !reset_hold && !protocol_fault &&
              active_profile == profile, "actual candidate MRA XML order produces a ready FAX profile");
        check(base_bytes_seen == 84544, "all actual MRA base tuples forward in byte order");
        run_question_profile();

        // Re-arm from the actual MRA marker, then deliberately pair it with the other descriptor ID.
        send_index(8'd1);
        check(!question_image_ready && !question_valid && reset_hold,
              "reload marker revokes question readiness and validity");
        send_descriptor((profile == 8'd1) ? 2 : 1);
        check(protocol_fault && reset_hold && !question_image_ready,
              "wrong normalized PCB/descriptor profile pair is rejected");

        // Legacy profile bytes with bit 7 set are ordinary options, not extension markers.
        send_marker(8'hB0);
        check(!protocol_fault && !reset_hold && !question_image_ready,
              "legacy Pepper/Hard Hat PCB B0 is not reinterpreted as an extension marker");
        send_marker(8'hD0);
        check(!protocol_fault && !reset_hold && !question_image_ready,
              "legacy Teeter PCB D0 is not reinterpreted as an extension marker");
        send_index(8'd0);
        check(base_bytes_seen == 2 * 84544 && !question_image_ready,
              "legacy base image remains a direct forwarded byte stream");

        // Preserve the existing Mouse Trap speech marker/profile route.
        send_marker(8'h90);
        send_speech_descriptor();
        check(!protocol_fault && active_profile == 3 && !question_image_ready,
              "speech marker 90 still accepts descriptor profile 3 without FAX readiness");
        send_speech_base();
        send_speech_rom();
        check(expansion_ready && !reset_hold && !protocol_fault && active_profile == 3 &&
              !question_image_ready && (base_bytes_seen == (2 * 84544 + 1)),
              "speech profile 3 completes without question readiness and forwards its base byte");

        $display("PASS FAX MRA loader set=%s checks=%0d base_bytes=%0d question_bytes=196608",
                 set_name, checks, base_bytes_seen);
        $finish;
    end

    initial begin #100000000; $fatal(1, "FAX MRA loader watchdog timeout"); end
endmodule
