`timescale 1ns/1ps

module tb_8253_live;
    logic reset = 1'b1;
    logic clk_sys = 1'b0;
    logic [1:0] addr = 0;
    logic [7:0] din = 0;
    logic wr = 0;
    logic rd = 0;
    logic [2:0] clk_timer = 0;
    logic [2:0] gate = 3'b111;
    wire [7:0] dout;
    wire [2:0] out;
    wire [2:0] sound_active;

    always #5 clk_sys = ~clk_sys;
    k580vi53 dut(.*);

    integer divider_phase = 0;
    integer audio_cycles = 0;
    integer pit_edges = 0;
    logic timer_prev = 0;
    logic out_prev = 0;
    integer failures = 0;
    integer write_done_pit = 0;

    // One-cycle positive pulse every 8 audio master clocks; the PIT detects its falling edge.
    always @(posedge clk_sys) begin
        audio_cycles <= audio_cycles + 1;
        if (divider_phase == 0) clk_timer <= 3'b111;
        else if (divider_phase == 1) clk_timer <= 3'b000;
        divider_phase <= (divider_phase == 7) ? 0 : divider_phase + 1;
        if (timer_prev && !clk_timer[0]) pit_edges <= pit_edges + 1;
        timer_prev <= clk_timer[0];
    end

    always @(negedge clk_sys) begin
        if (out[0] !== out_prev) begin
            $display("OUT_EDGE audio=%0d pit=%0d out=%b counter=%04x reload=%04x cw=%02x",
                     audio_cycles, pit_edges, out[0], dut.t0.counter, dut.t0.ld_count, dut.t0.cw);
            out_prev <= out[0];
        end
    end

    task automatic cpu_write(input logic [1:0] a, input logic [7:0] d);
        @(negedge clk_sys); addr = a; din = d; wr = 1;
        @(negedge clk_sys); wr = 0;
        repeat (14) @(negedge clk_sys);
        write_done_pit = pit_edges;
        $display("CPU_WRITE audio=%0d pit=%0d addr=%0d data=%02x", audio_cycles, pit_edges, a, d);
    endtask

    task automatic wait_pit_edge;
        integer old_count;
        begin
            old_count = pit_edges;
            while (pit_edges == old_count) @(negedge clk_sys);
        end
    endtask

    task automatic check(input logic condition, input string label);
        if (condition) $display("PASS %s audio=%0d pit=%0d out=%b", label, audio_cycles, pit_edges, out[0]);
        else begin
            $display("FAIL %s audio=%0d pit=%0d out=%b", label, audio_cycles, pit_edges, out[0]);
            failures = failures + 1;
        end
    endtask

    task automatic write_count(input logic [15:0] n);
        cpu_write(0, n[7:0]);
        cpu_write(0, n[15:8]);
    endtask

    task automatic measure_square(input integer expected_high, input integer expected_low,
                                  input integer periods, input string label);
        integer hi, lo;
        begin
            // Start at a falling-to-rising pair to exclude an arbitrary partial phase.
            while (out[0] !== 1'b0) wait_pit_edge();
            while (out[0] !== 1'b1) wait_pit_edge();
            for (integer p = 0; p < periods; p = p + 1) begin
                hi = 0;
                while (out[0] === 1'b1 && hi < 20) begin
                    wait_pit_edge();
                    hi = hi + 1;
                end
                lo = 0;
                while (out[0] === 1'b0 && lo < 20) begin
                    wait_pit_edge();
                    lo = lo + 1;
                end
                $display("SQUARE %s period=%0d high=%0d low=%0d count=%04x reload=%04x",
                         label, p, hi, lo, dut.t0.counter, dut.t0.ld_count);
                check(hi == expected_high && lo == expected_low, {label, " phase lengths"});
            end
        end
    endtask

    integer elapsed;
    integer before_reset_pit;
    initial begin
        // Warm reset remains asserted while the generated PIT clock continues to run.
        repeat (32) @(negedge clk_sys);
        reset = 0;

        // Mode 0 count 6 on channel 0; writes are one 16-audio-clock CPU slot apart.
        cpu_write(3, 8'h30);
        cpu_write(0, 8'd6);
        cpu_write(0, 8'd0);
        elapsed = 0;
        while (out[0] !== 1'b1 && elapsed < 12) begin
            wait_pit_edge(); elapsed = elapsed + 1;
        end
        check(out[0] == 1'b1 && elapsed <= 12, "live mode0 count6 reaches terminal after write stream");
        repeat (4) wait_pit_edge();
        check(out[0] == 1'b1, "live mode0 terminal output remains high");

        // Mode 0 -> mode 3, count 6. Control and bytes arrive while PIT edges continue.
        cpu_write(3, 8'h36);
        write_count(16'd6);
        measure_square(3, 3, 3, "mode3 count6 after live mode switch");

        // Rewrite the same mode from 6 to 5. MAME defers adoption until the next OUT phase edge;
        // the first transition after the completed MSB write may still finish the old phase.
        write_count(16'd5);
        measure_square(3, 2, 4, "mode3 count5 after phase-boundary adoption");

        // Captured Venture raw control word BE is 8253 mode 7, aliased to mode 3.
        cpu_write(3, 8'h3e); // captured raw mode 7 on counter 0
        write_count(16'd5);
        measure_square(3, 2, 4, "raw mode7 count5 alias");

        // Warm reset while counting, without stopping PIT clocks; then reprogram mode 0 count 6.
        before_reset_pit = pit_edges;
        reset = 1;
        repeat (16) @(negedge clk_sys);
        check(gate[0] == 1 && pit_edges > before_reset_pit, "warm reset keeps gate high and PIT clocks running");
        reset = 0;
        cpu_write(3, 8'h30);
        cpu_write(0, 8'd6);
        cpu_write(0, 8'd0);
        elapsed = 0;
        while (out[0] !== 1'b1 && elapsed < 12) begin
            wait_pit_edge(); elapsed = elapsed + 1;
        end
        check(out[0] == 1'b1 && elapsed <= 12, "warm-reset mode0 reprogram reaches terminal");

        if (failures != 0) $fatal(1, "%0d live-timing assertions failed", failures);
        $display("LIVE TIMING TESTS PASSED");
        $finish;
    end
endmodule
