`timescale 1ns/1ps
module tb_t80_speech_reset_drained;
    logic clk = 0, reset = 1, quarantine = 1, quarantine_reset_n = 0;
    logic [15:0] addr;
    logic [7:0] cpu_data;
    wire [7:0] datao;
    wire m1, mem_rd, mem_wr, io_rd, io_wr, intack, wait_n, rom_read;
    wire [13:0] rom_addr;
    wire [7:0] adapter_data;
    logic rom_ready = 0;
    logic [7:0] rom_data = 8'hff;
    wire read_accept, quarantine_ack, ack_generation;
    logic pending = 0;
    logic [13:0] pending_addr = 0;
    integer delay_left = 0;
    logic [7:0] rom [0:16383];
    logic post_reset_zero_seen = 0;
    logic [7:0] post_reset_data = 8'hff;

    always #5 clk = ~clk;
    Z80 cpu (.clk(clk), .clk_en(1'b1), .reset(reset), .addr(addr),
        .datai(cpu_data), .datao(datao), .m1(m1), .mem_rd(mem_rd),
        .mem_wr(mem_wr), .io_rd(io_rd), .io_wr(io_wr), .wait_n(wait_n),
        .busrq_n(1'b1), .intreq(1'b0), .intvec(8'hff), .intack(intack), .nmi(1'b0));
    speechRomBus adapter (.clk(clk), .reset(reset), .cpu_addr(addr), .mem_rd(mem_rd), .io_rd(io_rd),
        .rom_ready(rom_ready), .rom_data(rom_data), .rom_read(rom_read),
        .rom_addr(rom_addr), .wait_n(wait_n), .cpu_data(adapter_data));
    assign cpu_data = adapter_data;

    // Use the real endpoint quarantine with a drain depth matching this
    // deliberately delayed backend. Reset release is gated by its ack.
    exidy_cvsd_read_quarantine #(.READ_LATENCY(20)) drain (
        .cvsd_clk(clk), .reset_n(quarantine_reset_n), .quarantine_request(quarantine),
        .quarantine_generation(1'b0), .read_request(rom_read), .read_accept(read_accept),
        .quarantine_ack(quarantine_ack), .ack_generation(ack_generation));

    always @(posedge clk) begin
        rom_ready <= 0;
        if (read_accept) begin
            if (pending) $fatal(1, "endpoint accepted overlapping speech reads");
            pending <= 1;
            pending_addr <= rom_addr;
            delay_left <= 20;
        end else if (pending) begin
            if (delay_left <= 1) begin
                rom_data <= rom[pending_addr];
                rom_ready <= 1;
                pending <= 0;
            end else delay_left <= delay_left - 1;
        end

        #1;
        if (!reset && mem_rd && !io_rd && addr == 16'h0000 && wait_n) begin
            if (adapter_data !== 8'hc3)
                $fatal(1, "post-reset read at $0000 received stale/wrong data %h", adapter_data);
            post_reset_data <= adapter_data;
            post_reset_zero_seen <= 1;
        end
    end

    initial begin
        foreach (rom[i]) rom[i] = 8'h00;
        // JP $0004 makes the delayed $0004 fetch the request canceled by reset.
        rom[0] = 8'hc3; rom[1] = 8'h04; rom[2] = 8'h00; rom[4] = 8'h76;
        repeat (2) @(posedge clk); quarantine_reset_n = 1;
        repeat (4) @(posedge clk);
        wait(quarantine_ack && ack_generation == 1'b0);
        @(negedge clk); quarantine = 0; reset = 0;
        wait(rom_read && rom_addr == 14'h0004);
        @(negedge clk); reset = 1; quarantine = 1;
        wait(quarantine_ack && ack_generation == 1'b0);
        if (pending) $fatal(1, "drain acknowledged while delayed endpoint response remained pending");
        $display("PASS actual T80 + speech adapter reset held through endpoint drain ack");
        @(negedge clk); quarantine = 0; reset = 0;
        wait(post_reset_zero_seen);
        $display("PASS post-reset $0000 read returned %h after draining old $0004 response", post_reset_data);
        #10 $finish;
    end

    initial begin
        #20us;
        $fatal(1, "reset-drained fixture timed out");
    end
endmodule
