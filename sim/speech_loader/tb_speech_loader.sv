`timescale 1ns/1ps
module tb_speech_loader;
    reg clk = 0;
    reg audio_clk = 0;
    always #5 clk = ~clk;
    always #7 audio_clk = ~audio_clk;

    reg reset_n = 0;
    reg raw_download = 0;
    reg raw_wr = 0;
    reg [15:0] raw_index = 0;
    reg [24:0] raw_addr = 0;
    reg [7:0] raw_data = 0;
    reg speech_read = 0;
    reg [13:0] speech_addr = 0;
    wire [7:0] speech_data;
    wire speech_valid, speech_enable, ioctl_wait, base_wr, reset_hold;
    wire [24:0] base_addr;
    wire [7:0] base_data;

    exidySpeechLoader dut(.*);

    reg [7:0] descriptor [0:15];
    reg [7:0] mra_order [0:15];
    reg [7:0] speech_image [0:16383];
    integer base_length;
    integer mra_count;
    integer base_tuples;
    integer timeout;
    integer i;
    integer idx;
    reg [7:0] expected_byte;
    reg [24:0] expected_addr;
    reg [7:0] observed_data;
    reg [24:0] observed_addr;
    reg observed_wr;
    string descriptor_path;
    string order_path;
    string rom_path;

    function automatic [7:0] base_pattern(input integer address);
        base_pattern = ((address * 13) ^ (address >> 3) ^ 8'hA7) & 8'hFF;
    endfunction

    task automatic tick(input integer count);
        repeat (count) begin @(posedge clk); #1; end
    endtask

    task automatic hard_reset;
        begin
            @(negedge clk); reset_n = 0; raw_download = 0; raw_wr = 0;
            tick(4);
            @(negedge clk); reset_n = 1;
            tick(5);
            if (speech_enable || reset_hold || base_wr)
                $fatal(1, "external reset release did not return to idle");
        end
    endtask

    task automatic begin_transfer(input [15:0] index_value);
        begin
            @(negedge clk);
            raw_index = index_value;
            raw_addr = 0;
            raw_wr = 0;
            raw_download = 1;
            tick(2);
            timeout = 0;
            while (ioctl_wait && timeout < 100) begin tick(1); timeout = timeout + 1; end
            if (ioctl_wait) $fatal(1, "host wait did not clear before index %0d payload", index_value);
        end
    endtask

    task automatic send_byte(input integer address, input [7:0] value);
        begin
            @(negedge clk);
            raw_addr = address;
            raw_data = value;
            raw_wr = 1;
            // The wrapper must pair its registered write strobe with the same
            // normalized address/data tuple sampled on this source edge.
            observed_wr = 1;
            observed_addr = address;
            observed_data = value;
            @(posedge clk); #1;
            if (raw_index == 16'd0) begin
                if (!base_wr) $fatal(1, "missing delayed base write at %0d", address);
                if (base_addr !== observed_addr || base_data !== observed_data)
                    $fatal(1, "base tuple mismatch raw=(%0d,%02x) out=(%0d,%02x)",
                           observed_addr, observed_data, base_addr, base_data);
                base_tuples = base_tuples + 1;
            end else if (base_wr) begin
                $fatal(1, "base write leaked from index %0d", raw_index);
            end
        end
    endtask

    task automatic end_transfer;
        begin
            @(negedge clk); raw_wr = 0; raw_download = 0;
            tick(8);
        end
    endtask

    task automatic transfer_marker(input [7:0] value);
        begin
            begin_transfer(16'd1);
            send_byte(0, value);
            end_transfer();
        end
    endtask

    task automatic transfer_descriptor;
        integer k;
        begin
            begin_transfer(16'd7);
            for (k = 0; k < 16; k = k + 1) send_byte(k, descriptor[k]);
            end_transfer();
        end
    endtask

    task automatic transfer_base(input integer count);
        integer k;
        begin
            base_tuples = 0;
            begin_transfer(16'd0);
            for (k = 0; k < count; k = k + 1) send_byte(k, base_pattern(k));
            end_transfer();
            if (base_tuples != count)
                $fatal(1, "base forwarding tuple count %0d expected %0d", base_tuples, count);
        end
    endtask

    task automatic transfer_speech(input integer count);
        integer k;
        begin
            begin_transfer(16'd6);
            for (k = 0; k < count; k = k + 1) send_byte(k, speech_image[k]);
            end_transfer();
        end
    endtask

    task automatic transfer_ignored(input [15:0] index_value);
        begin
            @(negedge clk);
            raw_index = index_value;
            raw_addr = 0;
            raw_data = 8'h37;
            raw_download = 1;
            raw_wr = 1;
            tick(2);
            @(negedge clk); raw_download = 0; raw_wr = 0;
            tick(5);
            if (base_wr || reset_hold || !speech_enable)
                $fatal(1, "trailing MRA option index %0d changed committed speech state", index_value);
        end
    endtask

    task automatic assert_closed(input [255:0] context_text);
        begin
            tick(5);
            if (speech_enable) $fatal(1, "%0s: speech enabled unexpectedly", context_text);
        end
    endtask

    task automatic pulse_read_check(input [13:0] address);
        begin
            @(negedge audio_clk); speech_addr = address; speech_read = 1;
            @(posedge audio_clk); #1;
            if (!speech_valid) $fatal(1, "speech read not valid at %0d", address);
            if (speech_data !== speech_image[address])
                $fatal(1, "speech data mismatch at %0d", address);
            @(negedge audio_clk); speech_read = 0;
            @(posedge audio_clk); #1;
        end
    endtask

    initial begin
        if (!$value$plusargs("DESC=%s", descriptor_path)) $fatal(1, "DESC argument required");
        if (!$value$plusargs("ORDER=%s", order_path)) $fatal(1, "ORDER argument required");
        if (!$value$plusargs("ORDER_COUNT=%d", mra_count)) $fatal(1, "ORDER_COUNT argument required");
        if (!$value$plusargs("ROM=%s", rom_path)) $fatal(1, "ROM argument required");
        $readmemh(descriptor_path, descriptor);
        $readmemh(order_path, mra_order);
        $readmemh(rom_path, speech_image);
        base_length = descriptor[5] | (descriptor[6] << 8) | (descriptor[7] << 16);
        if (descriptor[0] != 8'h45 || descriptor[1] != 8'h58 ||
            descriptor[2] != 1 || descriptor[3] != 3 || descriptor[4] != 5 ||
            base_length != 24'h014940 || descriptor[8] != 0 || descriptor[9] != 0 ||
            descriptor[10] != 0 || descriptor[11] != 0 || descriptor[12] != 8'h40 ||
            descriptor[13] != 0 || descriptor[14] != 0 || descriptor[15] != 0)
            $fatal(1, "MRA descriptor does not match the production profile contract");
        $display("MRA descriptor decoded: base=%0d (0x%06x), CVSD=0x%06x",
                 base_length, base_length, {descriptor[13], descriptor[12], descriptor[11]});

        hard_reset();

        // Other option and auxiliary streams must be fully filtered before the
        // transport sees them; they cannot create a legacy or speech session.
        for (idx = 0; idx < 6; idx = idx + 1) begin
            case (idx)
                0: raw_index = 16'd2;
                1: raw_index = 16'd3;
                2: raw_index = 16'd4;
                3: raw_index = 16'd254;
                4: raw_index = 16'd255;
                default: raw_index = 16'd5;
            endcase
            @(negedge clk); raw_download = 1; raw_wr = 1; raw_addr = 0; raw_data = 8'h5A;
            tick(3);
            @(negedge clk); raw_download = 0; raw_wr = 0;
            tick(5);
            if (speech_enable || reset_hold || base_wr || ioctl_wait)
                $fatal(1, "irrelevant index %0d affected speech loader", raw_index);
        end

        // Existing PCB bytes, including high-bit interrupt profiles, stay out
        // of the new speech profile. The wrapper masks only its loader copy.
        transfer_marker(8'h10); assert_closed("legacy PCB 10");
        transfer_marker(8'h30); assert_closed("legacy PCB 30");
        transfer_marker(8'h50); assert_closed("legacy PCB 50");
        transfer_marker(8'hB0); assert_closed("legacy PCB B0");
        transfer_marker(8'hD0); assert_closed("legacy PCB D0");

        // A short base image faults the candidate session and keeps the gate shut.
        transfer_marker(8'h90);
        transfer_descriptor();
        transfer_base(base_length - 1);
        if (!reset_hold) $fatal(1, "short base did not retain loader reset hold");
        assert_closed("short base fault");
        hard_reset();

        // Replay the actual MRA XML rom element order. MiSTer sends those
        // entries immediately in document order, so ordering is part of the
        // descriptor/session contract, not merely presentation metadata.
        if (mra_count < 4 || mra_order[0] != 8'd1 || mra_order[1] != 8'd7 ||
            mra_order[2] != 8'd0 || mra_order[3] != 8'd6)
            $fatal(1, "MRA XML order must begin 1,7,0,6; got %0d,%0d,%0d,%0d",
                   mra_order[0], mra_order[1], mra_order[2], mra_order[3]);
        for (i = 0; i < mra_count; i = i + 1) begin
            case (mra_order[i])
                1: transfer_marker(8'h90);
                7: transfer_descriptor();
                0: transfer_base(base_length);
                6: transfer_speech(16384);
                default: transfer_ignored({8'd0, mra_order[i]});
            endcase
        end
        tick(8);
        if (reset_hold || !speech_enable)
            $fatal(1, "complete candidate did not reach ready speech state");
        pulse_read_check(14'h0000);
        pulse_read_check(14'h1234);
        pulse_read_check(14'h3FFF);

        // Starting a normal legacy Mouse Trap marker invalidates the old
        // validated speech profile; the external audio-domain gate follows it.
        begin_transfer(16'd1);
        send_byte(0, 8'h10);
        end_transfer();
        tick(5);
        if (reset_hold || speech_enable) $fatal(1, "legacy reload did not return to idle");

        // External reset clears parser/readiness state and allows another valid
        // marker to begin; the full valid path above already proves recovery.
        hard_reset();
        transfer_marker(8'h90);
        if (!reset_hold || speech_enable) $fatal(1, "external reset did not permit a fresh candidate session");

        $display("PASS speech_loader wrapper tuples=%0d base_bytes=%0d speech_bytes=16384 legacy=10,30,50,B0,D0",
                 base_tuples, base_length);
        $finish;
    end
endmodule
