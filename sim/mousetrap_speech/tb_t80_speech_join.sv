`timescale 1ns/1ps
module tb_t80_speech_join;
    logic clk = 0, reset = 1;
    logic [15:0] addr;
    logic [7:0] cpu_data, datao;
    logic m1, mem_rd, mem_wr, io_rd, io_wr, intack;
    logic adapter_wait_n, rom_read;
    logic [13:0] rom_addr;
    logic [7:0] adapter_data;
    logic rom_ready = 0;
    logic [7:0] rom_data = 8'hff;
    logic [7:0] rom [0:16383];
    integer reads = 0, io_reads = 0, io_writes = 0, mem_writes = 0;
    integer wait_cycles = 0;
    logic prev_io_rd = 0, prev_io_wr = 0, prev_mem_wr = 0;
    logic done = 0;
    logic transaction_seen = 0;
    logic [13:0] held_rom_addr = '0;
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

    // Real synchronous memory response model, one edge after rom_read.
    always @(posedge clk) begin
        rom_ready <= 1'b0;
        if (rom_read) begin
            if (reads >= 16) $fatal(1, "unexpected extra ROM request %0d at %h", reads, rom_addr);
            if (rom_addr !== expected_rom_addr[reads])
                $fatal(1, "ROM request %0d expected %h, got %h", reads, expected_rom_addr[reads], rom_addr);
            rom_data <= rom[rom_addr];
            rom_ready <= 1'b1;
            reads <= reads + 1;
        end
        if (reset || !mem_rd || io_rd) begin
            transaction_seen <= 1'b0;
        end else begin
            if (transaction_seen && rom_addr !== held_rom_addr)
                $fatal(1, "adapter address changed during held read: expected %h, got %h", held_rom_addr, rom_addr);
            if (rom_read) begin
                if (transaction_seen) $fatal(1, "duplicate ROM request during one held mem_rd strobe");
                transaction_seen <= 1'b1;
                held_rom_addr <= rom_addr;
            end
        end
        if (!reset && mem_rd && !io_rd && !adapter_wait_n) wait_cycles <= wait_cycles + 1;
        if (!reset && io_rd && !prev_io_rd) begin
            io_reads <= io_reads + 1;
            if (addr !== 16'h1222) $fatal(1, "IN address expected 1222, got %h", addr);
            if (!adapter_wait_n) $fatal(1, "I/O read stalled by ROM adapter");
        end
        if (!reset && io_wr && !prev_io_wr) begin
            case (io_writes)
                0: if (addr !== 16'h1221 || datao !== 8'h12) $fatal(1, "first OUT mismatch: %h %h", addr, datao);
                1: if (addr !== 16'h5c23 || datao !== 8'h5c) $fatal(1, "second OUT mismatch: %h %h", addr, datao);
                default: $fatal(1, "unexpected extra OUT");
            endcase
            io_writes <= io_writes + 1;
        end
        if (!reset && mem_wr && !prev_mem_wr) begin
            if (addr !== 16'h2000 || datao !== 8'ha5) $fatal(1, "memory write mismatch: %h %h", addr, datao);
            mem_writes <= mem_writes + 1;
        end
        prev_io_rd <= io_rd;
        prev_io_wr <= io_wr;
        prev_mem_wr <= mem_wr;
        if (!done && reads >= 16 && io_reads == 1 && io_writes == 2 && mem_writes == 1) begin
            if (reads != 16) $fatal(1, "expected exactly 16 ROM requests, observed %0d", reads);
            if (wait_cycles == 0) $fatal(1, "adapter did not stall the CPU");
            done <= 1;
            $display("PASS actual T80 + production speechRomBus: reads=%0d waits=%0d", reads, wait_cycles);
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
        wait(done);
        #20 $finish;
    end

    initial begin
        #20us;
        $fatal(1, "T80 plus production speechRomBus timed out");
    end
endmodule
