`timescale 1ns/1ps
module tb_speech_rom_bus;
    reg clk = 0, reset = 1;
    reg [15:0] cpu_addr = 0;
    reg mem_rd = 0, io_rd = 0;
    reg rom_ready = 0;
    reg [7:0] rom_data = 0;
    wire rom_read, wait_n;
    wire [13:0] rom_addr;
    wire [7:0] cpu_data;
    integer reads = 0, errors = 0;
    reg [13:0] rom_sample_addr;
    reg inject_stale = 0;
    reg [7:0] rom_mem [0:16383];

    always #5 clk = ~clk;
    speechRomBus dut(.*);

    // One-clock synchronous-ROM model: read/address are sampled on the edge,
    // registered response/valid appear after that edge.
    always @(posedge clk) begin
        rom_ready <= 0;
        if (inject_stale) rom_ready <= 1;
        if (rom_read) begin
            reads <= reads + 1;
            rom_sample_addr <= rom_addr;
            rom_data <= rom_mem[rom_addr];
            rom_ready <= 1;
        end
    end

    task automatic check(input bit ok, input string msg);
        if (!ok) begin errors = errors + 1; $display("FAIL %s", msg); end
    endtask
    task automatic tick; begin @(posedge clk); #1; end endtask

    initial begin
        rom_mem[14'h1234] = 8'hA6;
        rom_mem[14'h3FFE] = 8'h5D;
        tick(); reset = 0; tick(); tick();

        // Held CPU read, changing external address must not redirect fetch.
        cpu_addr = 16'hD234; mem_rd = 1; #1;
        check(!wait_n && rom_read && rom_addr == 14'h1234, "first request stalls and masks address");
        tick();
        check(rom_sample_addr == 14'h1234 && !wait_n && !rom_read, "synchronous response waits one cycle");
        cpu_addr = 16'hBEEF; #1;
        check(rom_addr == 14'h1234, "address held while waiting");
        tick();
        check(wait_n && cpu_data == 8'hA6, "registered response releases wait with correct byte");
        repeat (3) tick();
        check(reads == 1, "held request does not issue duplicate reads");
        mem_rd = 0; tick();

        // I/O read does not consume the memory ROM port or wait.
        io_rd = 1; mem_rd = 1; #1;
        check(wait_n && !rom_read, "I/O read bypasses ROM adapter");
        tick(); check(reads == 1, "I/O read leaves memory transaction count unchanged");
        io_rd = 0; mem_rd = 0; tick();

        // Reset aborts an outstanding transaction. A late stale valid pulse
        // must be drained before a post-reset read can be accepted.
        cpu_addr = 16'hFFFE; mem_rd = 1; #1; check(rom_read, "second fetch begins");
        tick(); reset = 1; mem_rd = 0; inject_stale = 1; tick(); reset = 0;
        cpu_addr = 16'h7FFE; mem_rd = 1; #1;
        check(!rom_read && !wait_n, "late stale valid cannot release a new read");
        tick(); check(!rom_read && !wait_n, "stale-valid drain continues to block request");
        inject_stale = 0; tick();
        check(!rom_read && !wait_n, "drain requires observing valid low");
        tick(); #1;
        check(rom_read && !wait_n && rom_addr == 14'h3FFE, "read starts after stale response drains");
        tick(); tick(); check(wait_n && cpu_data == 8'h5D, "post-reset response delivered");
        check(reads == 3, "aborted read counted once and restart read counted once");

        if (errors != 0) $fatal(1, "speech ROM bus: %0d failures", errors);
        $display("PASS speech ROM bus"); $finish;
    end
endmodule
