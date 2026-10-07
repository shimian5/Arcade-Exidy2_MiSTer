`timescale 1ns/1ps
module tb_t80_speech_reset_race;
    logic clk = 0, reset = 1, race_mode = 0;
    logic [15:0] addr;
    logic [7:0] cpu_data, datao;
    logic m1, mem_rd, mem_wr, io_rd, io_wr, intack;
    logic adapter_wait_n, rom_read;
    logic [13:0] rom_addr;
    logic [7:0] adapter_data;
    logic rom_ready = 0;
    logic [7:0] rom_data = 8'hff;
    logic [7:0] rom [0:16383];
    integer normal_reads = 0, race_reads = 0, overlap_requests = 0;
    integer io_reads = 0, io_writes = 0, mem_writes = 0, wait_cycles = 0;
    integer delay_left = 0;
    logic backend_pending = 0;
    logic [13:0] backend_addr = 0;
    logic backend_stale_returned = 0;
    logic normal_done = 0, expected_defect = 0;
    logic transaction_seen = 0;
    logic [13:0] held_rom_addr = 0;
    logic prev_io_rd = 0, prev_io_wr = 0, prev_mem_wr = 0;
    integer expected_rom_addr [0:15];

    always #5 clk = ~clk;
    Z80 cpu (
        .clk(clk), .clk_en(1'b1), .reset(reset), .addr(addr),
        .datai(cpu_data), .datao(datao), .m1(m1), .mem_rd(mem_rd),
        .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr), .wait_n(adapter_wait_n),
        .busrq_n(1'b1), .intreq(1'b0), .intvec(8'hff), .intack(intack), .nmi(1'b0)
    );
    speechRomBus adapter (
        .clk(clk), .reset(reset), .cpu_addr(addr), .mem_rd(mem_rd), .io_rd(io_rd),
        .rom_ready(rom_ready), .rom_data(rom_data), .rom_read(rom_read),
        .rom_addr(rom_addr), .wait_n(adapter_wait_n), .cpu_data(adapter_data)
    );
    assign cpu_data = io_rd ? 8'h5c : adapter_data;

    // Backend reset is intentionally absent. Normal responses alternate 4/7
    // clocks; the reset-race transaction takes 20 clocks and survives CPU reset.
    always @(posedge clk) begin
        rom_ready <= 0;
        if (backend_pending) begin
            if (delay_left <= 1) begin
                rom_data <= rom[backend_addr];
                rom_ready <= 1;
                backend_pending <= 0;
                delay_left <= 0;
                if (race_mode) begin
                    backend_stale_returned <= 1;
                    $display("RACE backend returns old addr=%h data=%h at %0t", backend_addr, rom[backend_addr], $time);
                end
            end else begin
                delay_left <= delay_left - 1;
            end
            if (rom_read) begin
                overlap_requests <= overlap_requests + 1;
                if (race_mode) $display("RACE overlapping new request addr=%h while old addr=%h pending at %0t", rom_addr, backend_addr, $time);
            end
        end else if (rom_read) begin
            backend_pending <= 1;
            backend_addr <= rom_addr;
            if (race_mode) begin
                race_reads <= race_reads + 1;
                delay_left <= 20;
                $display("RACE backend accepted addr=%h at %0t", rom_addr, $time);
            end else begin
                if (normal_reads >= 16) $fatal(1, "unexpected normal request %0d", normal_reads);
                if (rom_addr !== expected_rom_addr[normal_reads])
                    $fatal(1, "normal request %0d expected %h, got %h", normal_reads, expected_rom_addr[normal_reads], rom_addr);
                delay_left <= (normal_reads % 2 == 0) ? 4 : 7;
                normal_reads <= normal_reads + 1;
            end
        end

        if (reset || !mem_rd || io_rd) begin
            transaction_seen <= 0;
        end else begin
            if (transaction_seen && rom_addr !== held_rom_addr)
                $fatal(1, "adapter address changed while read strobe held");
            if (rom_read) begin
                if (transaction_seen) $fatal(1, "duplicate request in one held read strobe");
                transaction_seen <= 1;
                held_rom_addr <= rom_addr;
            end
        end

        if (!reset && !race_mode && !normal_done && mem_rd && !io_rd && !adapter_wait_n)
            wait_cycles <= wait_cycles + 1;
        if (!reset && !race_mode && !normal_done && io_rd && !prev_io_rd) begin
            io_reads <= io_reads + 1;
            if (addr !== 16'h1222 || !adapter_wait_n) $fatal(1, "normal IN address/wait mismatch: %h", addr);
        end
        if (!reset && !race_mode && !normal_done && io_wr && !prev_io_wr) begin
            case (io_writes)
                0: if (addr !== 16'h1221 || datao !== 8'h12) $fatal(1, "first OUT mismatch");
                1: if (addr !== 16'h5c23 || datao !== 8'h5c) $fatal(1, "second OUT mismatch");
                default: $fatal(1, "unexpected extra normal OUT");
            endcase
            io_writes <= io_writes + 1;
        end
        if (!reset && !race_mode && !normal_done && mem_wr && !prev_mem_wr) begin
            if (addr !== 16'h2000 || datao !== 8'ha5) $fatal(1, "normal memory write mismatch");
            mem_writes <= mem_writes + 1;
        end
        prev_io_rd <= io_rd;
        prev_io_wr <= io_wr;
        prev_mem_wr <= mem_wr;

        if (!race_mode && !normal_done && normal_reads == 16 && io_reads == 1 && io_writes == 2 && mem_writes == 1 &&
            !backend_pending && !mem_rd) begin
            if (normal_reads != 16 || wait_cycles == 0) $fatal(1, "normal delayed-response run incomplete");
            normal_done <= 1;
            $display("PASS delayed 4/7-cycle T80+adapter run: reads=%0d waits=%0d", normal_reads, wait_cycles);
        end
    end

    // Sample after adapter NBAs: a high wait_n while the new $0000 read is
    // active and data still belongs to reset-aborted $0004 proves stale capture.
    always @(posedge clk) begin
        #1;
        if (race_mode && backend_stale_returned && mem_rd && !io_rd &&
            addr == 16'h0000 && adapter_wait_n && adapter_data == rom[14'h0004]) begin
            expected_defect <= 1;
            $display("EXPECTED_DEFECT stale backend response for $%h released new CPU read at $%h with data=%h",
                     backend_addr, addr, adapter_data);
        end
    end

    initial begin
        foreach (rom[i]) rom[i] = 8'h00;
        rom[16'h0000] = 8'h3e; rom[16'h0001] = 8'h12;
        rom[16'h0002] = 8'hd3; rom[16'h0003] = 8'h21;
        rom[16'h0004] = 8'hdb; rom[16'h0005] = 8'h22;
        rom[16'h0006] = 8'hd3; rom[16'h0007] = 8'h23;
        rom[16'h0008] = 8'h3a; rom[16'h0009] = 8'h00;
        rom[16'h000a] = 8'h01; rom[16'h000b] = 8'h32;
        rom[16'h000c] = 8'h00; rom[16'h000d] = 8'h20;
        rom[16'h000e] = 8'h76; rom[16'h0100] = 8'ha5;
        expected_rom_addr[0] = 16'h0000; expected_rom_addr[1] = 16'h0001;
        expected_rom_addr[2] = 16'h0002; expected_rom_addr[3] = 16'h0003;
        expected_rom_addr[4] = 16'h0004; expected_rom_addr[5] = 16'h0005;
        expected_rom_addr[6] = 16'h0006; expected_rom_addr[7] = 16'h0007;
        expected_rom_addr[8] = 16'h0008; expected_rom_addr[9] = 16'h0009;
        expected_rom_addr[10] = 16'h000a; expected_rom_addr[11] = 16'h0100;
        expected_rom_addr[12] = 16'h000b; expected_rom_addr[13] = 16'h000c;
        expected_rom_addr[14] = 16'h000d; expected_rom_addr[15] = 16'h000e;

        repeat (5) @(posedge clk);
        @(negedge clk); reset = 0;
        wait(normal_done);

        // Restart from address zero, let the read at $0004 be issued, then
        // reset only CPU/adapter. The ROM endpoint retains that outstanding
        // request and returns it 20 clocks after issue, after reset release.
        @(negedge clk); reset = 1;
        repeat (3) @(posedge clk);
        @(negedge clk); race_mode = 1; reset = 0;
        wait(rom_read && rom_addr == 14'h0004);
        @(posedge clk); #1 reset = 1;
        repeat (2) @(posedge clk);
        @(negedge clk); reset = 0;

        wait(expected_defect);
        if (!backend_stale_returned || overlap_requests == 0)
            $fatal(1, "expected stale-response race did not prove overlap after reset");
        $display("EXPECTED_FAILURE endpoint has no cancellation/drained acknowledgment; adapter accepted post-reset stale valid");
        #10 $finish;
    end

    initial begin
        #20us;
        if (!expected_defect) $fatal(1, "reset-race fixture timed out before observing expected stale capture");
    end
endmodule
